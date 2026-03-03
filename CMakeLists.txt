# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.19)

# Set C standard
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Skip compiler test for baremetal targets
set(CMAKE_C_COMPILER_WORKS 1)

# Set toolchain file before project()
set(CMAKE_TOOLCHAIN_FILE ${CMAKE_CURRENT_SOURCE_DIR}/cmake/toolchain_llvm.cmake)

# Load configuration (ISA/ABI settings)
include(${CMAKE_CURRENT_SOURCE_DIR}/config.cmake)

project(chimera-sdk-multi LANGUAGES C ASM)

# Add CMake helper modules
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/scripts)

# Include helper functions
include(Chimera)

# Set common include directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/common)

# Export compile commands for better IDE integration
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_link_options(
    -L${CMAKE_CURRENT_SOURCE_DIR}/common   # for common.ldh
    -L${CMAKE_BINARY_DIR}                  # for host_placement.ldh (generated)
)

# ===========================================================================
# Options
# ===========================================================================

option(CHIMERA_UNIFIED_ELF
    "Generate a unified mixed-ISA ELF (host + all devices) after the build. \
Requires lief (managed via uv). Device segments are embedded as read-only \
LOAD segments so the host ISA cannot accidentally execute device code."
    OFF
)

# ===========================================================================
# Python environment (uv)
# ===========================================================================

find_program(CHIMERA_UV uv
    HINTS $ENV{HOME}/.local/bin $ENV{HOME}/.cargo/bin /usr/local/bin
    DOC   "uv — Python package / project manager"
)

if(NOT CHIMERA_UV)
    message(FATAL_ERROR
        "[CHIMERA] 'uv' not found.\n"
        "Install it with:\n"
        "  curl -LsSf https://astral.sh/uv/install.sh | sh\n"
        "Then re-run cmake."
    )
endif()

# Bootstrap the Python virtual environment at configure time so that all
# dependencies (lief, …) are available when build targets run.
message(STATUS "[CHIMERA] Bootstrapping Python venv via uv sync …")
execute_process(
    COMMAND           "${CHIMERA_UV}" sync
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    RESULT_VARIABLE   _uv_sync_result
    OUTPUT_VARIABLE   _uv_sync_output
    ERROR_VARIABLE    _uv_sync_error
)
if(NOT _uv_sync_result EQUAL 0)
    message(FATAL_ERROR
        "[CHIMERA] 'uv sync' failed (exit ${_uv_sync_result}).\n"
        "stdout: ${_uv_sync_output}\n"
        "stderr: ${_uv_sync_error}\n"
        "Check your internet connection or run 'uv sync' manually."
    )
endif()

# ===========================================================================
# Configuration summary (printed at configure time)
# ===========================================================================

message(STATUS "[CHIMERA] ============================================================")
message(STATUS "[CHIMERA]  Chimera SDK Multi-Binary Build")
message(STATUS "[CHIMERA] ============================================================")
message(STATUS "[CHIMERA]  LLVM toolchain : ${TOOLCHAIN_DIR}")
message(STATUS "[CHIMERA]  uv             : ${CHIMERA_UV}")
message(STATUS "[CHIMERA] ------------------------------------------------------------")
if(CHIMERA_UNIFIED_ELF)
message(STATUS "[CHIMERA]  Unified ELF  : ON  →  ${CMAKE_BINARY_DIR}/chimera_unified.elf")
else()
message(STATUS "[CHIMERA]  Unified ELF  : OFF (enable with -DCHIMERA_UNIFIED_ELF=ON)")
endif()
message(STATUS "[CHIMERA] ------------------------------------------------------------")

# ===========================================================================
# Subdirectories
#
# Build order:
#   1. Device binaries in placement-chain order (snitch_cluster_0 → snitch_cluster_1)
#   2. Host binary (placed immediately after the last device)
# ===========================================================================
add_subdirectory(devices/snitch_cluster_0)
add_subdirectory(devices/snitch_cluster_1)
add_subdirectory(host)
