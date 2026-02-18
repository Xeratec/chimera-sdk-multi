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

# Include helper functions
include(ChimeraUtils)

# Set common include directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/common)

# Export compile commands for better IDE integration
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_link_options(
    -L${CMAKE_CURRENT_SOURCE_DIR}/common
)

# Print build information
message(STATUS "========================================")
message(STATUS "Chimera SDK Multi-Binary Build")
message(STATUS "========================================")
message(STATUS "Host ISA:              ${ISA_HOST}")
message(STATUS "Host ABI:              ${ABI_HOST}")
message(STATUS "Device ISA:            ${ISA_DEVICE}")
message(STATUS "Device ABI:            ${ABI_DEVICE}")
message(STATUS "========================================")

# Build order:
# 1. Build device binaries first (with PIC)
add_subdirectory(devices/snitch_cluster)

# 2. Build host binary (linking with device symbols)
add_subdirectory(host)
