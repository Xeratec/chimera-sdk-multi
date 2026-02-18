# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

# ---------------------------------------------------------------------------
# add_device_binary(TARGET_NAME
#   LINKER_SCRIPT <linker.ld>
#   SOURCES       <file> ...
# )
#
# Compiles a device binary (PIC, device ISA/ABI) and generates:
#   - <TARGET>_symbols.s  : absolute-symbol assembly for all public symbols
#   - <TARGET>_symbols.h  : matching extern declarations (symbols prefixed
#                           with TARGET_NAME_)
#   - <TARGET>_symbols    : INTERFACE library the host links against
# ---------------------------------------------------------------------------
function(add_device_binary TARGET_NAME)
    set(oneValueArgs  LINKER_SCRIPT)
    set(multiValueArgs SOURCES)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # -----------------------------------------------------------------------
    # 1. Compile the device ELF
    # -----------------------------------------------------------------------
    add_executable(${TARGET_NAME}.elf ${ARG_SOURCES})

    target_compile_options(${TARGET_NAME}.elf PRIVATE
        --target=${CROSS_COMPILE_DEVICE}
        -march=${ISA_DEVICE}
        -mabi=${ABI_DEVICE}
        -fPIC
        -O2
        -g
        -Wall
        -Wextra
    )

    target_link_options(${TARGET_NAME}.elf PRIVATE
        --target=${CROSS_COMPILE_DEVICE}
        -march=${ISA_DEVICE}
        -mabi=${ABI_DEVICE}
        -nostartfiles
        -nostdlib
        -T${ARG_LINKER_SCRIPT}
        -Wl,--build-id=none
        -rtlib=compiler-rt
        -lclang_rt.builtins-riscv32
    )

    target_link_directories(${TARGET_NAME}.elf PRIVATE
        ${TOOLCHAIN_DIR}/lib/clang/${LLVM_VERSION_MAJOR}/lib/baremetal/${COMPILERRT_DEVICE}
    )

    # -----------------------------------------------------------------------
    # 2. Disassembly (optional debug artifact)
    # -----------------------------------------------------------------------
    add_custom_command(
        OUTPUT  ${TARGET_NAME}.dump
        COMMAND ${CMAKE_OBJDUMP} -d ${TARGET_NAME}.elf > ${TARGET_NAME}.dump
        COMMAND ${CMAKE_OBJDUMP} -h ${TARGET_NAME}.elf > ${TARGET_NAME}.sections
        COMMAND ${CMAKE_NM} -n ${TARGET_NAME}.elf > ${TARGET_NAME}.symbols
        DEPENDS ${TARGET_NAME}.elf
        COMMENT "Disassembling ${TARGET_NAME}"
        VERBATIM
    )

    # -----------------------------------------------------------------------
    # 3. Generate symbol assembly + header via cmake -P script
    # -----------------------------------------------------------------------
    set(SYMBOLS_ASM ${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}_symbols.s)
    set(SYMBOLS_H   ${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}_symbols.h)
    set(GEN_SCRIPT  ${CMAKE_SOURCE_DIR}/cmake/GenerateDeviceSymbols.cmake)

    add_custom_command(
        OUTPUT  ${SYMBOLS_ASM} ${SYMBOLS_H}
        COMMAND ${CMAKE_COMMAND}
                    -D NM=${CMAKE_NM}
                    -D TARGET_NAME=${TARGET_NAME}
                    -D ELF=${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}.elf
                    -D OUT_ASM=${SYMBOLS_ASM}
                    -D OUT_H=${SYMBOLS_H}
                    -P ${GEN_SCRIPT}
        DEPENDS ${TARGET_NAME}.elf ${GEN_SCRIPT}
        COMMENT "Generating device symbols for ${TARGET_NAME}"
        VERBATIM
    )

    add_custom_target(${TARGET_NAME}_gen_symbols
        DEPENDS ${SYMBOLS_ASM} ${SYMBOLS_H}
    )

    # -----------------------------------------------------------------------
    # 4. Compile the generated assembly with the HOST toolchain.
    #    The symbols are absolute addresses, so host ABI is correct here.
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
    )

    add_dependencies(${TARGET_NAME}_syms_obj ${TARGET_NAME}_gen_symbols)

    # -----------------------------------------------------------------------
    # 5. INTERFACE library consumed by add_host_binary()
    #    Use target_sources so object files are properly propagated to the
    #    consuming executable (target_link_libraries does not propagate
    #    OBJECT libraries through INTERFACE in CMake 3.24).
    # -----------------------------------------------------------------------
    add_library(${TARGET_NAME}_symbols INTERFACE)
    target_sources(${TARGET_NAME}_symbols INTERFACE
        $<TARGET_OBJECTS:${TARGET_NAME}_syms_obj>
    )
    target_include_directories(${TARGET_NAME}_symbols INTERFACE ${CMAKE_CURRENT_BINARY_DIR})

    # -----------------------------------------------------------------------
    # 6. Top-level convenience target
    # -----------------------------------------------------------------------
    add_custom_target(${TARGET_NAME} ALL
        DEPENDS
            ${TARGET_NAME}.dump
            ${TARGET_NAME}_gen_symbols
    )
endfunction()

# ---------------------------------------------------------------------------
# add_host_binary(TARGET_NAME
#   LINKER_SCRIPT  <linker.ld>
#   SOURCES        <file> ...
#   DEVICE_DEPS    <target> ...   # ensures device is built first
#   DEVICE_SYMBOLS <lib>   ...   # ${dev}_symbols libraries to link
# )
# ---------------------------------------------------------------------------
function(add_host_binary TARGET_NAME)
    set(oneValueArgs   LINKER_SCRIPT)
    set(multiValueArgs SOURCES DEVICE_DEPS DEVICE_SYMBOLS)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # -----------------------------------------------------------------------
    # 1. Compile the host ELF
    # -----------------------------------------------------------------------
    add_executable(${TARGET_NAME}.elf ${ARG_SOURCES})

    target_compile_options(${TARGET_NAME}.elf PRIVATE
        --target=${CROSS_COMPILE_HOST}
        -march=${ISA_HOST}
        -mabi=${ABI_HOST}
        -mcmodel=medany
        -O2
        -g
        -Wall
        -Wextra
    )

    target_link_options(${TARGET_NAME}.elf PRIVATE
        --target=${CROSS_COMPILE_HOST}
        -march=${ISA_HOST}
        -mabi=${ABI_HOST}
        -mcmodel=medany
        -nostartfiles
        -T${ARG_LINKER_SCRIPT}
        -Wl,--build-id=none
        -rtlib=compiler-rt
        -lclang_rt.builtins-riscv64
    )

    target_link_directories(${TARGET_NAME}.elf PRIVATE
        ${TOOLCHAIN_DIR}/lib/clang/${LLVM_VERSION_MAJOR}/lib/baremetal/${COMPILERRT_HOST}
    )

    # -----------------------------------------------------------------------
    # 2. Device build-order dependencies
    # -----------------------------------------------------------------------
    if(ARG_DEVICE_DEPS)
        add_dependencies(${TARGET_NAME}.elf ${ARG_DEVICE_DEPS})
    endif()

    # -----------------------------------------------------------------------
    # 3. Link device symbol objects (absolute symbols + include path for .h)
    # -----------------------------------------------------------------------
    foreach(dev_lib IN LISTS ARG_DEVICE_SYMBOLS)
        target_link_libraries(${TARGET_NAME}.elf PRIVATE ${dev_lib})
    endforeach()

    # -----------------------------------------------------------------------
    # 4. Disassembly
    # -----------------------------------------------------------------------
    add_custom_command(
        OUTPUT  ${TARGET_NAME}.dump
        COMMAND ${CMAKE_OBJDUMP} -d ${TARGET_NAME}.elf > ${TARGET_NAME}.dump
        COMMAND ${CMAKE_OBJDUMP} -h ${TARGET_NAME}.elf > ${TARGET_NAME}.sections
        COMMAND ${CMAKE_NM} -n ${TARGET_NAME}.elf > ${TARGET_NAME}.symbols
        DEPENDS ${TARGET_NAME}.elf
        COMMENT "Disassembling ${TARGET_NAME}"
        VERBATIM
    )

    add_custom_target(${TARGET_NAME} ALL
        DEPENDS ${TARGET_NAME}.dump
    )
endfunction()
