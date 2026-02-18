# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

# Host binary compilation

set(HOST_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/crt0.S
    ${CMAKE_CURRENT_SOURCE_DIR}/main.c
)

set(HOST_LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/link.ld)

# Add host binary with dependencies on device binaries
add_host_binary(chimera_host
    LINKER_SCRIPT ${HOST_LINKER_SCRIPT}
    SOURCES ${HOST_SOURCES}
    DEVICE_DEPS snitch_cluster_device
    DEVICE_SYMBOLS snitch_cluster_device_symbols
)

# Make the linker script a dependency
set_source_files_properties(${HOST_SOURCES} PROPERTIES
    OBJECT_DEPENDS ${HOST_LINKER_SCRIPT}
)
