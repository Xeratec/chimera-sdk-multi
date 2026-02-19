# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

# Snitch Cluster 1 device binary.
# PREV_DEVICE: cluster 1 is placed immediately after cluster 0.
# CMake will ensure snitch_cluster_0_placement.ldh exists before linking.

add_device_binary(snitch_cluster_1
    ISA ${ISA_DEVICE_SNITCH_CLUSTER_1}
    ABI ${ABI_DEVICE_SNITCH_CLUSTER_1}
    COMPILER ${CROSS_COMPILE_DEVICE_SNITCH_CLUSTER_1}
    COMPIERT_RT ${COMPILER_RT_DEVICE_SNITCH_CLUSTER_1}
    LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/link.ld.in
    PREV_DEVICE   snitch_cluster_0
    SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/crt0.S
        ${CMAKE_CURRENT_SOURCE_DIR}/main.c
)
