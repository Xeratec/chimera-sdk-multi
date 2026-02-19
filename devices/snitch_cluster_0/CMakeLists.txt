# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

# Snitch Cluster 0 device binary

add_device_binary(snitch_cluster_0
    ISA ${ISA_DEVICE_SNITCH_CLUSTER_0}
    ABI ${ABI_DEVICE_SNITCH_CLUSTER_0}
    COMPILER ${CROSS_COMPILE_DEVICE_SNITCH_CLUSTER_0}
    COMPIERT_RT ${COMPILER_RT_DEVICE_SNITCH_CLUSTER_0}
    LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/link.ld.in
    SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/crt0.S
        ${CMAKE_CURRENT_SOURCE_DIR}/main.c
)
