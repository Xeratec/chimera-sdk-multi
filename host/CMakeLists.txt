# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

# Host binary compilation
set(HOST_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/crt0.S
    ${CMAKE_CURRENT_SOURCE_DIR}/main.c
)

set(HOST_LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/link.ld.in)

# Add host binary with dependencies on both device binaries.
# LAST_DEVICE tells the build system which device's placement file to copy
# to host_placement.ldh (the host linker script INCLUDEs this file).
add_host_binary(host
    ISA ${ISA_HOST}
    ABI ${ABI_HOST}
    COMPILER ${CROSS_COMPILE_HOST}
    COMPIERT_RT ${COMPILER_RT_HOST}
    LINKER_SCRIPT  ${HOST_LINKER_SCRIPT}
    SOURCES        ${HOST_SOURCES}
    DEVICE_DEPS    snitch_cluster_0 snitch_cluster_1
    DEVICE_SYMBOLS snitch_cluster_0_symbols snitch_cluster_1_symbols
    LAST_DEVICE    snitch_cluster_1
)

