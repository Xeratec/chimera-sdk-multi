# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0
#
# Post-build memory-map printer and section-overlap checker.
#
# Parses one `objdump -h` output file per binary, prints a memory map sorted
# by VMA, and checks for unintended overlaps between loaded (TEXT/DATA)
# sections of different binaries.
#
# BSS / NOLOAD sections (e.g. the shared .common region) are displayed but
# excluded from overlap checks because they are intentionally mapped at the
# same physical address on all cores.
#
# Invoked at build time via:
#   cmake -D CHIMERA_LISTS_FILE=<path> -P cmake/scripts/CheckSectionOverlaps.cmake
#
# The CHIMERA_LISTS_FILE is a small cmake file generated at configure time
# that sets two variables:
#   SECTION_FILES  semicolon-separated list of *.sections file paths
#   BINARY_NAMES   semicolon-separated list of binary display names
#                  (must correspond 1-to-1 with SECTION_FILES)

# ---------------------------------------------------------------------------
# _chimera_hex_to_dec(<hex_string> <output_var>)
#
# Convert a hexadecimal string (with or without 0x prefix, with or without
# leading zeros) to a CMake decimal integer stored in <output_var>.
# ---------------------------------------------------------------------------
macro(_chimera_hex_to_dec _HEX _OUT)
    string(REGEX REPLACE "^0[xX]" "" _h "${_HEX}")   # strip optional 0x
    string(REGEX REPLACE "^0+"    "" _h "${_h}")      # strip leading zeros
    if(_h STREQUAL "")
        set(${_OUT} 0)
    else()
        math(EXPR ${_OUT} "0x${_h}" OUTPUT_FORMAT DECIMAL)
    endif()
endmacro()

# ---------------------------------------------------------------------------
# _chimera_dec_to_hex(<decimal_int> <output_var>)
#
# Convert a CMake decimal integer to a 0x-prefixed lowercase hex string
# stored in <output_var>.  Requires CMake ≥ 3.13.
# ---------------------------------------------------------------------------
macro(_chimera_dec_to_hex _DEC _OUT)
    # OUTPUT_FORMAT HEXADECIMAL is the portable keyword (CMake ≥ 3.13).
    # HEX became a synonym only in CMake 3.27.
    math(EXPR ${_OUT} "${_DEC}" OUTPUT_FORMAT HEXADECIMAL)
endmacro()

# ---------------------------------------------------------------------------
# _chimera_zero_pad(<number_string> <total_length> <output_var>)
#
# Left-pad <number_string> with zeros to reach <total_length> characters.
# Used to produce fixed-width sort keys from decimal VMA values.
# ---------------------------------------------------------------------------
macro(_chimera_zero_pad _NUM _LEN _OUT)
    set(_s "${_NUM}")
    string(LENGTH "${_s}" _slen)
    while(_slen LESS ${_LEN})
        set(_s "0${_s}")
        string(LENGTH "${_s}" _slen)
    endwhile()
    set(${_OUT} "${_s}")
endmacro()

# ---------------------------------------------------------------------------
# _chimera_space_pad(<string> <total_length> <output_var>)
# Left-pad <string> with spaces to reach <total_length> characters.
# Used to align the "Size" column in the memory map printout.
# ---------------------------------------------------------------------------
macro(_chimera_space_pad _STR _LEN _OUT)
    set(_s "${_STR}")
    string(LENGTH "${_s}" _slen)
    while(_slen LESS ${_LEN})
        set(_s " ${_s}")
        string(LENGTH "${_s}" _slen)
    endwhile()
    set(${_OUT} "${_s}")
endmacro()

# ===========================================================================
# Load the section-file list generated at configure time
# ===========================================================================
if(NOT DEFINED CHIMERA_LISTS_FILE OR NOT EXISTS "${CHIMERA_LISTS_FILE}")
    message(FATAL_ERROR
        "[CHIMERA] CHIMERA_LISTS_FILE not set or does not exist: '${CHIMERA_LISTS_FILE}'")
endif()

include("${CHIMERA_LISTS_FILE}")

list(LENGTH SECTION_FILES _n_files)
if(_n_files EQUAL 0)
    message(WARNING "[CHIMERA] No section files to check.")
    return()
endif()

# ===========================================================================
# Parse every *.sections file
#
# Parallel lists (one entry per section):
#   _all_bin    binary display name
#   _all_sec    section name
#   _all_start  VMA start (decimal)
#   _all_end    VMA end = start + size (decimal)
#   _all_type   section type string (TEXT, DATA, BSS, …)
# ===========================================================================
set(_all_bin   "")
set(_all_sec   "")
set(_all_start "")
set(_all_end   "")
set(_all_type  "")

math(EXPR _last_file_idx "${_n_files} - 1")
foreach(_fi RANGE ${_last_file_idx})
    list(GET SECTION_FILES ${_fi} _file)
    list(GET BINARY_NAMES  ${_fi} _bin)

    if(NOT EXISTS "${_file}")
        message(WARNING "[CHIMERA] Sections file not found (binary not yet built?): ${_file}")
        continue()
    endif()

    file(READ "${_file}" _content)
    string(REPLACE "\n" ";" _lines "${_content}")

    foreach(_line IN LISTS _lines)
        # objdump -h data line format:
        #   <idx> <name> <size_hex> <vma_hex> <type>
        # VMA can be 8 digits (32-bit ELF) or 16 digits (64-bit ELF)
        if(NOT _line MATCHES
            "^[ \t]+[0-9]+[ \t]+([^ \t]+)[ \t]+([0-9a-fA-F]+)[ \t]+([0-9a-fA-F]+)[ \t]+([A-Z]+)")
            continue()
        endif()

        set(_sec_name "${CMAKE_MATCH_1}")
        set(_size_hex "${CMAKE_MATCH_2}")
        set(_vma_hex  "${CMAKE_MATCH_3}")
        set(_type     "${CMAKE_MATCH_4}")

        _chimera_hex_to_dec("${_size_hex}" _size_dec)
        _chimera_hex_to_dec("${_vma_hex}"  _vma_dec)

        # Skip empty sections and metadata (VMA == 0 → debug/reloc)
        if(_size_dec EQUAL 0 OR _vma_dec EQUAL 0)
            continue()
        endif()

        math(EXPR _end_dec "${_vma_dec} + ${_size_dec}")

        list(APPEND _all_bin   "${_bin}")
        list(APPEND _all_sec   "${_sec_name}")
        list(APPEND _all_start "${_vma_dec}")
        list(APPEND _all_end   "${_end_dec}")
        list(APPEND _all_type  "${_type}")
    endforeach()
endforeach()

list(LENGTH _all_start _n_secs)
if(_n_secs EQUAL 0)
    message(STATUS "[CHIMERA] No non-empty sections found.")
    return()
endif()

# ===========================================================================
# Sort by VMA using zero-padded decimal sort keys
# ===========================================================================
set(_sort_keys "")
math(EXPR _n_secs_1 "${_n_secs} - 1")
foreach(_i RANGE ${_n_secs_1})
    list(GET _all_start ${_i} _s)
    _chimera_zero_pad("${_s}" 12 _s_padded)
    # Sort key: "NNNNNNNNNNNN:I" → sorts by VMA then by original index
    _chimera_zero_pad("${_i}" 4 _i_padded)
    list(APPEND _sort_keys "${_s_padded}:${_i_padded}")
endforeach()

list(SORT _sort_keys)

# ===========================================================================
# Print memory map
# ===========================================================================
message(STATUS "[CHIMERA] ===================================================================")
message(STATUS "[CHIMERA]  Memory Map  (all non-empty sections, sorted by VMA)")
message(STATUS "[CHIMERA] ===================================================================")
message(STATUS "[CHIMERA]  VMA Start     VMA End       Size      Type  Binary / Section")
message(STATUS "[CHIMERA] -------------------------------------------------------------------")

set(_loaded_idx "") # indices of TEXT/DATA sections for overlap check

foreach(_key IN LISTS _sort_keys)
    string(REGEX MATCH "^[0-9]+:([0-9]+)$" _ "${_key}")
    set(_i "${CMAKE_MATCH_1}")
    # Strip leading zeros from index (avoids octal interpretation)
    math(EXPR _i "${_i}" OUTPUT_FORMAT DECIMAL)

    list(GET _all_bin   ${_i} _bin)
    list(GET _all_sec   ${_i} _sec)
    list(GET _all_start ${_i} _start)
    list(GET _all_end   ${_i} _end)
    list(GET _all_type  ${_i} _type)

    _chimera_dec_to_hex(${_start} _start_hex)
    _chimera_dec_to_hex(${_end}   _end_hex)
    math(EXPR _size "${_end} - ${_start}")
    _chimera_dec_to_hex(${_size} _size_hex)

    if(_type STREQUAL "TEXT" OR _type STREQUAL "DATA")
        _chimera_space_pad("${_size_hex}" 8 _size_hex_padded)
        message(STATUS
            "[CHIMERA]  ${_start_hex}    ${_end_hex}    ${_size_hex_padded}  ${_type}  ${_bin} / ${_sec}")
        list(APPEND _loaded_idx ${_i})
    else()
        message(DEBUG
            "[CHIMERA]  ${_start_hex}    ${_end_hex}    ${_size_hex_padded}  ${_type}  ${_bin} / ${_sec}  [shared/NOLOAD]")
    endif()
endforeach()

message(STATUS "[CHIMERA] ===================================================================")

# ===========================================================================
# Overlap detection: check all pairs of loaded (TEXT/DATA) sections
# belonging to DIFFERENT binaries for VMA range intersection.
#
# Two ranges [s1, e1) and [s2, e2) overlap iff s1 < e2 AND s2 < e1.
# ===========================================================================
list(LENGTH _loaded_idx _n_loaded)
set(_found_overlap FALSE)

if(_n_loaded GREATER 1)
    math(EXPR _n_loaded_1 "${_n_loaded} - 1")
    foreach(_ii RANGE ${_n_loaded_1})
        list(GET _loaded_idx ${_ii} _i)
        list(GET _all_bin    ${_i}  _bi)
        list(GET _all_sec    ${_i}  _ni)
        list(GET _all_start  ${_i}  _si)
        list(GET _all_end    ${_i}  _ei)

        math(EXPR _jj_start "${_ii} + 1")
        foreach(_jj RANGE ${_jj_start} ${_n_loaded_1})
            if(_jj GREATER_EQUAL _n_loaded)
                break()
            endif()

            list(GET _loaded_idx ${_jj} _j)
            list(GET _all_bin    ${_j}  _bj)
            list(GET _all_sec    ${_j}  _nj)
            list(GET _all_start  ${_j}  _sj)
            list(GET _all_end    ${_j}  _ej)

            # Skip sections belonging to the same binary
            if(_bi STREQUAL _bj)
                continue()
            endif()

            # Check for intersection
            if(_si LESS _ej AND _sj LESS _ei)
                _chimera_dec_to_hex(${_si} _si_hex)
                _chimera_dec_to_hex(${_ei} _ei_hex)
                _chimera_dec_to_hex(${_sj} _sj_hex)
                _chimera_dec_to_hex(${_ej} _ej_hex)
                message(WARNING
                    "[CHIMERA] OVERLAP: ${_bi} / ${_ni} "
                    "[${_si_hex}, ${_ei_hex}) overlaps "
                    "${_bj} / ${_nj} [${_sj_hex}, ${_ej_hex})")
                set(_found_overlap TRUE)
            endif()
        endforeach()
    endforeach()
endif()

if(_found_overlap)
    message(FATAL_ERROR
        "[CHIMERA] Section overlaps detected — see WARNINGs above.\n"
        "Verify the placement chain in cmake/ChimeraUtils.cmake and "
        "each device's __device_end symbol.")
else()
    message(STATUS "[CHIMERA] => No section overlaps detected. Layout is clean.")
endif()
