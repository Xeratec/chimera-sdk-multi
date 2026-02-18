# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

# Snitch Cluster device binary compilation

set(DEVICE_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/crt0.S
    ${CMAKE_CURRENT_SOURCE_DIR}/main.c
)

set(DEVICE_LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/link.ld)

# Add device binary with PIC
# This automatically:
# - Compiles the device ELF
# - Generates a disassembly dump
# - Extracts symbols and generates ${TARGET}_symbols.h header
# - Creates ${TARGET}_symbols interface library for linking with host
add_device_binary(snitch_cluster_device
    LINKER_SCRIPT ${DEVICE_LINKER_SCRIPT}
    SOURCES ${DEVICE_SOURCES}
)

# Make the linker script a dependency
set_source_files_properties(${DEVICE_SOURCES} PROPERTIES
    OBJECT_DEPENDS ${DEVICE_LINKER_SCRIPT}
)