# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

# ---------------------------------------------------------------------------
# add_device_binary(TARGET_NAME
#   LINKER_SCRIPT  <link.ld.in>    linker script template (see below)
#   ISA            <march>         e.g. rv32imafd
#   ABI            <mabi>          e.g. ilp32d
#   COMPILER       <triple>        e.g. riscv32-unknown-elf
#   COMPIERT_RT    <rt-dir>        compiler-rt baremetal subdir (e.g. rv32imafd)
#   SOURCES        <file> ...
#   [PREV_DEVICE   <target>]       optional: device that precedes this one in
#                                  memisl; its placement file is INCLUDEd by
#                                  the generated linker script so this device
#                                  starts immediately after it
# )
#
# Linker script template placeholders (substituted by configure_file @ONLY):
#   @CHIMERA_PREV_INCLUDE@     → empty, or "INCLUDE <prev>_placement.ldh"
#   @CHIMERA_RESERVED_SECTION@ → empty, or a .reserved (NOLOAD) section that
#                                 advances the LC past the previous device's
#                                 memory region
#
# Build outputs (all in CMAKE_CURRENT_BINARY_DIR):
#   ${TARGET_NAME}_link.ld       generated linker script (do not edit)
#   ${TARGET_NAME}.elf           device ELF
#   ${TARGET_NAME}.dump          disassembly
#   ${TARGET_NAME}.sections      section headers  (input for overlap checker)
#   ${TARGET_NAME}.symbols       full symbol table
#   ${TARGET_NAME}_symbols.s     absolute-symbol assembly for the host linker
#   ${TARGET_NAME}_symbols.h     extern declarations for host C code
#   ${TARGET_NAME}_symbols       INTERFACE library consumed by add_host_binary
#   (CMAKE_BINARY_DIR)/${TARGET_NAME}_placement.ldh
#                                placement header read by the next binary
# ---------------------------------------------------------------------------
function(add_device_binary TARGET_NAME)
    set(oneValueArgs   LINKER_SCRIPT PREV_DEVICE ISA ABI COMPILER COMPIERT_RT)
    set(multiValueArgs SOURCES)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    message(STATUS "[CHIMERA] Device: ${TARGET_NAME}")
    message(STATUS "          ISA=${ARG_ISA}  ABI=${ARG_ABI}  CC=${ARG_COMPILER}")
    if(ARG_PREV_DEVICE)
        message(STATUS "          placed after: ${ARG_PREV_DEVICE}")
    else()
        message(STATUS "          first device in chain")
    endif()

    # -----------------------------------------------------------------------
    # 1. Generate the linker script from the user's template.
    #    configure_file substitutes @CHIMERA_PREV_INCLUDE@ and
    #    @CHIMERA_RESERVED_SECTION@ at cmake configure time.
    # -----------------------------------------------------------------------
    if(ARG_PREV_DEVICE)
        set(CHIMERA_PREV_INCLUDE
            "INCLUDE ${ARG_PREV_DEVICE}_placement.ldh")
        # Build the .reserved block with string(APPEND) to avoid the semicolon
        # being mis-interpreted as a CMake list separator inside set().
        set(CHIMERA_RESERVED_SECTION "")
        string(APPEND CHIMERA_RESERVED_SECTION "  .reserved (NOLOAD) : {\n")
        string(APPEND CHIMERA_RESERVED_SECTION "    . = . + (__${ARG_PREV_DEVICE}_end - ORIGIN(memisl));\n")
        string(APPEND CHIMERA_RESERVED_SECTION "  } > memisl\n")
    else()
        set(CHIMERA_PREV_INCLUDE "")
        set(CHIMERA_RESERVED_SECTION "")
    endif()

    set(GEN_LINK_LD "${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}_link.ld")
    configure_file("${ARG_LINKER_SCRIPT}" "${GEN_LINK_LD}" @ONLY)

    # -----------------------------------------------------------------------
    # 2. Compile the device ELF
    # -----------------------------------------------------------------------
    add_executable(${TARGET_NAME}.elf ${ARG_SOURCES})

    target_compile_options(${TARGET_NAME}.elf PRIVATE
        --target=${ARG_COMPILER}
        -march=${ARG_ISA}
        -mabi=${ARG_ABI}
        -O2
        -g
        -Wall
        -Wextra
    )

    target_link_options(${TARGET_NAME}.elf PRIVATE
        --target=${ARG_COMPILER}
        -march=${ARG_ISA}
        -mabi=${ARG_ABI}
        -nostdlib
        -T${GEN_LINK_LD}
        -Wl,--build-id=none
        # -rtlib=compiler-rt
        -lclang_rt.builtins-riscv32
    )

    target_link_directories(${TARGET_NAME}.elf PRIVATE
        ${TOOLCHAIN_DIR}/lib/clang/${LLVM_VERSION_MAJOR}/lib/baremetal/${ARG_COMPIERT_RT}
    )

    # LINK_DEPENDS: relink the ELF when the generated linker script changes.
    # The generated script itself is regenerated (via configure_file) whenever
    # the source template changes, so tracking GEN_LINK_LD is sufficient.
    # For devices with a previous device, also track the placement file so
    # the ELF relinks when the previous device's size changes.
    if(ARG_PREV_DEVICE)
        set(PREV_PLACEMENT_LDH "${CMAKE_BINARY_DIR}/${ARG_PREV_DEVICE}_placement.ldh")
        set_target_properties(${TARGET_NAME}.elf PROPERTIES
            LINK_DEPENDS "${GEN_LINK_LD};${PREV_PLACEMENT_LDH}"
        )
        add_dependencies(${TARGET_NAME}.elf ${ARG_PREV_DEVICE}_gen_placement)
    else()
        set_target_properties(${TARGET_NAME}.elf PROPERTIES
            LINK_DEPENDS "${GEN_LINK_LD}"
        )
    endif()

    # -----------------------------------------------------------------------
    # 3. Debug artifacts: disassembly + section headers + full symbol table
    # -----------------------------------------------------------------------
    add_custom_command(
        OUTPUT  ${TARGET_NAME}.dump
        COMMAND ${CMAKE_OBJDUMP} -d  ${TARGET_NAME}.elf > ${TARGET_NAME}.dump
        COMMAND ${CMAKE_OBJDUMP} -h  ${TARGET_NAME}.elf > ${TARGET_NAME}.sections
        COMMAND ${CMAKE_NM}      -n  ${TARGET_NAME}.elf > ${TARGET_NAME}.symbols
        DEPENDS ${TARGET_NAME}.elf
        COMMENT "[CHIMERA] Disassembling ${TARGET_NAME}"
        VERBATIM
    )

    # -----------------------------------------------------------------------
    # 4. Extract public symbols → assembly stub + C header
    # -----------------------------------------------------------------------
    set(SYMBOLS_ASM "${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}_symbols.s")
    set(SYMBOLS_H   "${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}_symbols.h")
    set(HELPERS     "${CMAKE_SOURCE_DIR}/cmake/scripts/ChimeraBuildHelpers.cmake")

    add_custom_command(
        OUTPUT  ${SYMBOLS_ASM} ${SYMBOLS_H}
        COMMAND ${CMAKE_COMMAND}
                    -D CHIMERA_MODE=symbols
                    -D NM=${CMAKE_NM}
                    -D TARGET_NAME=${TARGET_NAME}
                    -D ELF=${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}.elf
                    -D OUT_ASM=${SYMBOLS_ASM}
                    -D OUT_H=${SYMBOLS_H}
                    -P ${HELPERS}
        DEPENDS ${TARGET_NAME}.elf ${HELPERS}
        COMMENT "[CHIMERA] Extracting symbols from ${TARGET_NAME}"
        VERBATIM
    )

    add_custom_target(${TARGET_NAME}_gen_symbols
        DEPENDS ${SYMBOLS_ASM} ${SYMBOLS_H}
    )

    # -----------------------------------------------------------------------
    # 5. Generate placement file: read __device_end → write _placement.ldh
    # -----------------------------------------------------------------------
    set(PLACEMENT_LDH "${CMAKE_BINARY_DIR}/${TARGET_NAME}_placement.ldh")

    add_custom_command(
        OUTPUT  ${PLACEMENT_LDH}
        COMMAND ${CMAKE_COMMAND}
                    -D CHIMERA_MODE=placement
                    -D NM=${CMAKE_NM}
                    -D ELF=${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}.elf
                    -D TARGET_NAME=${TARGET_NAME}
                    -D OUT_LDH=${PLACEMENT_LDH}
                    -P ${HELPERS}
        DEPENDS ${TARGET_NAME}.elf ${HELPERS}
        COMMENT "[CHIMERA] Generating placement for ${TARGET_NAME}"
        VERBATIM
    )

    add_custom_target(${TARGET_NAME}_gen_placement
        DEPENDS ${PLACEMENT_LDH}
    )

    # -----------------------------------------------------------------------
    # 6. Compile the symbol assembly with the HOST toolchain.
    #    The symbols are absolute addresses so the host ABI is correct here.
    # -----------------------------------------------------------------------
    add_library(${TARGET_NAME}_syms_obj OBJECT ${SYMBOLS_ASM})

    set_source_files_properties(${SYMBOLS_ASM} PROPERTIES
        GENERATED TRUE
        LANGUAGE  ASM
    )

    target_compile_options(${TARGET_NAME}_syms_obj PRIVATE
        --target=${CROSS_COMPILE_HOST}
        -march=${ISA_HOST}
        -mabi=${ABI_HOST}
        -mcmodel=medany
        -Wno-unused-command-line-argument
    )

    add_dependencies(${TARGET_NAME}_syms_obj ${TARGET_NAME}_gen_symbols)

    # -----------------------------------------------------------------------
    # 7. INTERFACE library consumed by add_host_binary().
    #    target_sources propagates OBJECT files through INTERFACE correctly
    #    (target_link_libraries does not in CMake < 3.24).
    # -----------------------------------------------------------------------
    add_library(${TARGET_NAME}_symbols INTERFACE)
    target_sources(${TARGET_NAME}_symbols INTERFACE
        $<TARGET_OBJECTS:${TARGET_NAME}_syms_obj>
    )
    target_include_directories(${TARGET_NAME}_symbols INTERFACE
        ${CMAKE_CURRENT_BINARY_DIR}
    )

    # -----------------------------------------------------------------------
    # 8. Register this binary's section file for the overlap checker
    # -----------------------------------------------------------------------
    set_property(GLOBAL APPEND PROPERTY CHIMERA_SECTION_FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}.sections")
    set_property(GLOBAL APPEND PROPERTY CHIMERA_BINARY_NAMES  "${TARGET_NAME}")
    # Store the named CMake target (not a relative file path) so that
    # chimera_check_overlaps can reference it from any subdirectory.
    set_property(GLOBAL APPEND PROPERTY CHIMERA_DUMP_TARGETS  "${TARGET_NAME}")

    # -----------------------------------------------------------------------
    # 9. Top-level convenience target
    # -----------------------------------------------------------------------
    add_custom_target(${TARGET_NAME} ALL
        DEPENDS
            ${TARGET_NAME}.dump
            ${TARGET_NAME}_gen_symbols
            ${TARGET_NAME}_gen_placement
    )
endfunction()

# ---------------------------------------------------------------------------
# add_host_binary(TARGET_NAME
#   LINKER_SCRIPT  <link.ld.in>   linker script template (see below)
#   ISA            <march>        e.g. rv64imc
#   ABI            <mabi>         e.g. lp64
#   COMPILER       <triple>       e.g. riscv64-unknown-elf
#   COMPIERT_RT    <rt-dir>       compiler-rt baremetal subdir (e.g. rv64imc)
#   SOURCES        <file> ...
#   DEVICE_DEPS    <target> ...   device targets that must be built first
#   DEVICE_SYMBOLS <lib>   ...   ${dev}_symbols INTERFACE libraries to link
#   LAST_DEVICE    <target>       device at the tail of the placement chain;
#                                 its _placement.ldh is INCLUDEd by the host
#                                 linker script via @CHIMERA_LAST_DEVICE@
# )
#
# Linker script template placeholder:
#   @CHIMERA_LAST_DEVICE@   → the value of LAST_DEVICE (e.g. snitch_cluster_1)
#                             Used to form "INCLUDE snitch_cluster_1_placement.ldh"
#                             and "__snitch_cluster_1_end" in the script.
#
# After building the host binary this function creates a
# chimera_check_overlaps target that prints a memory map and checks for
# section overlaps across all registered binaries.
# ---------------------------------------------------------------------------
function(add_host_binary TARGET_NAME)
    set(oneValueArgs   LINKER_SCRIPT LAST_DEVICE ISA ABI COMPILER COMPIERT_RT)
    set(multiValueArgs SOURCES DEVICE_DEPS DEVICE_SYMBOLS)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Fall back to global host settings when ISA/ABI not given explicitly
    if(NOT ARG_ISA)
        set(ARG_ISA "${ISA_HOST}")
        message(WARNING "ISA not specified for host binary ${TARGET_NAME}, falling back to ${ARG_ISA}")
    endif()
    if(NOT ARG_ABI)
        set(ARG_ABI "${ABI_HOST}")
        message(WARNING "ABI not specified for host binary ${TARGET_NAME}, falling back to ${ARG_ABI}")
    endif()
    if(NOT ARG_COMPILER)
        set(ARG_COMPILER "${CROSS_COMPILE_HOST}")
        message(WARNING "Compiler not specified for host binary ${TARGET_NAME}, falling back to ${ARG_COMPILER}")
    endif()
    if(NOT ARG_COMPIERT_RT)
        set(ARG_COMPIERT_RT "${COMPILER_RT_HOST}")
        message(WARNING "Compiler-rt not specified for host binary ${TARGET_NAME}, falling back to ${ARG_COMPIERT_RT}")
    endif()

    message(STATUS "[CHIMERA] Host:   ${TARGET_NAME}")
    message(STATUS "          ISA=${ARG_ISA}  ABI=${ARG_ABI}  CC=${ARG_COMPILER}")
    message(STATUS "          placed after: ${ARG_LAST_DEVICE}")

    # -----------------------------------------------------------------------
    # 1. Generate the host linker script from template
    # -----------------------------------------------------------------------
    set(CHIMERA_LAST_DEVICE "${ARG_LAST_DEVICE}")
    set(GEN_LINK_LD "${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}_link.ld")
    configure_file("${ARG_LINKER_SCRIPT}" "${GEN_LINK_LD}" @ONLY)

    # -----------------------------------------------------------------------
    # 2. Compile the host ELF
    # -----------------------------------------------------------------------
    add_executable(${TARGET_NAME}.elf ${ARG_SOURCES})

    target_compile_options(${TARGET_NAME}.elf PRIVATE
        --target=${ARG_COMPILER}
        -march=${ARG_ISA}
        -mabi=${ARG_ABI}
        -mcmodel=medany
        -O2
        -g
        -Wall
        -Wextra
    )

    target_link_options(${TARGET_NAME}.elf PRIVATE
        --target=${ARG_COMPILER}
        -march=${ARG_ISA}
        -mabi=${ARG_ABI}
        -mcmodel=medany
        -nostdlib
        -T${GEN_LINK_LD}
        -Wl,--build-id=none
        # -rtlib=compiler-rt
        -lclang_rt.builtins-riscv64
    )

    target_link_directories(${TARGET_NAME}.elf PRIVATE
        ${TOOLCHAIN_DIR}/lib/clang/${LLVM_VERSION_MAJOR}/lib/baremetal/${ARG_COMPIERT_RT}
        ${CMAKE_BINARY_DIR}     # so the linker can find *_placement.ldh via INCLUDE
    )

    # Relink when the generated linker script or last device's placement changes
    set(LAST_PLACEMENT_LDH "${CMAKE_BINARY_DIR}/${ARG_LAST_DEVICE}_placement.ldh")
    set_target_properties(${TARGET_NAME}.elf PROPERTIES
        LINK_DEPENDS "${GEN_LINK_LD};${LAST_PLACEMENT_LDH}"
    )

    # -----------------------------------------------------------------------
    # 3. Device build-order dependencies
    # -----------------------------------------------------------------------
    if(ARG_DEVICE_DEPS)
        add_dependencies(${TARGET_NAME}.elf ${ARG_DEVICE_DEPS})
    endif()

    # -----------------------------------------------------------------------
    # 4. Link device symbol objects
    # -----------------------------------------------------------------------
    foreach(dev_lib IN LISTS ARG_DEVICE_SYMBOLS)
        target_link_libraries(${TARGET_NAME}.elf PRIVATE ${dev_lib})
    endforeach()

    # -----------------------------------------------------------------------
    # 5. Debug artifacts
    # -----------------------------------------------------------------------
    add_custom_command(
        OUTPUT  ${TARGET_NAME}.dump
        COMMAND ${CMAKE_OBJDUMP} -d ${TARGET_NAME}.elf > ${TARGET_NAME}.dump
        COMMAND ${CMAKE_OBJDUMP} -h ${TARGET_NAME}.elf > ${TARGET_NAME}.sections
        COMMAND ${CMAKE_NM}      -n ${TARGET_NAME}.elf > ${TARGET_NAME}.symbols
        DEPENDS ${TARGET_NAME}.elf
        COMMENT "[CHIMERA] Disassembling ${TARGET_NAME}"
        VERBATIM
    )

    add_custom_target(${TARGET_NAME} ALL
        DEPENDS ${TARGET_NAME}.dump
    )

    # -----------------------------------------------------------------------
    # 6. Register host section file and create the overlap-check target
    # -----------------------------------------------------------------------
    set_property(GLOBAL APPEND PROPERTY CHIMERA_SECTION_FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}.sections")
    set_property(GLOBAL APPEND PROPERTY CHIMERA_BINARY_NAMES  "${TARGET_NAME}")
    set_property(GLOBAL APPEND PROPERTY CHIMERA_DUMP_TARGETS  "${TARGET_NAME}")

    get_property(ALL_SECTION_FILES GLOBAL PROPERTY CHIMERA_SECTION_FILES)
    get_property(ALL_BINARY_NAMES  GLOBAL PROPERTY CHIMERA_BINARY_NAMES)
    get_property(ALL_DUMP_TARGETS  GLOBAL PROPERTY CHIMERA_DUMP_TARGETS)

    # Write the section-file list to a cmake file so the overlap-check script
    # can read it without dealing with semicolons in COMMAND arguments.
    set(CHIMERA_LISTS_FILE "${CMAKE_BINARY_DIR}/chimera_section_files.cmake")
    file(WRITE "${CHIMERA_LISTS_FILE}"
        "# Auto-generated by ChimeraUtils.cmake - do not edit\n"
        "set(SECTION_FILES \"${ALL_SECTION_FILES}\")\n"
        "set(BINARY_NAMES  \"${ALL_BINARY_NAMES}\")\n"
    )

    add_custom_target(chimera_check_overlaps ALL
        COMMAND ${CMAKE_COMMAND}
                    -D "CHIMERA_LISTS_FILE=${CHIMERA_LISTS_FILE}"
                    -P "${CMAKE_SOURCE_DIR}/cmake/scripts/CheckSectionOverlaps.cmake"
        DEPENDS ${ALL_DUMP_TARGETS}
        COMMENT "[CHIMERA] Checking memory layout for section overlaps"
        VERBATIM
    )

    add_custom_target(chimera_footer ALL
        COMMAND ${CMAKE_COMMAND}
                    -D "CHIMERA_BINARY_DIR=${CMAKE_BINARY_DIR}"
                    -D "CHIMERA_LISTS_FILE=${CHIMERA_LISTS_FILE}"
                    -P "${CMAKE_SOURCE_DIR}/cmake/scripts/PrintBuildFooter.cmake"
        DEPENDS chimera_check_overlaps
        COMMENT "[CHIMERA] Printing build footer"
        VERBATIM
    )
endfunction()
