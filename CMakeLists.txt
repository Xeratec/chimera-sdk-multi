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

# Print build information
message(STATUS "========================================")
message(STATUS "Chimera SDK Multi-Binary Build")
message(STATUS "========================================")

# Build order:
# 1. Build device binaries first in chain order.
#    snitch_cluster_1 is placed immediately after snitch_cluster_0 in memisl.
add_subdirectory(devices/snitch_cluster_0)
add_subdirectory(devices/snitch_cluster_1)

# 2. Build host binary after all devices are known.
#    The host is placed immediately after snitch_cluster_1 in memisl.
add_subdirectory(host)
