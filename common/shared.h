// SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
// SPDX-License-Identifier: Apache-2.0

#ifndef CHIMERA_SHARED_H
#define CHIMERA_SHARED_H

#include "soc_addr_map.h"
#include <stdint.h>

/*
 * Shared data structure exchanged between the host (CVA6, RV64) and all
 * device accelerators (Snitch clusters, RV32).
 *
 * __attribute__((packed)) guarantees identical field layout regardless of the
 * ABI in use (lp64 on the host, ilp32d on the device).  All fields use
 * fixed-width types for the same reason.
 *
 * Both the host and each device define a 'shared_data' variable in the
 * '.common' section:
 *   - Host link.ld maps '.common' into memisl at 0x48000000 (loaded).
 *   - Device link.ld maps '.common' into memisl as NOLOAD (same address,
 *     no bytes emitted — device accesses host memory via AXI interconnect).
 *
 * Per-cluster arrays are indexed by cluster ID (0 = cluster 0, 1 = cluster 1).
 */
typedef struct __attribute__((packed)) {
    /* Host sets host_to_device_flag[i] = 1 to signal cluster i to start. */
    volatile uint32_t host_to_device_flag[NUM_CLUSTERS];

    /* Cluster i sets device_to_host_flag[i] = 1 when it is done. */
    volatile uint32_t device_to_host_flag[NUM_CLUSTERS];

    /* General-purpose exchange buffer, one 16-word slot per cluster. */
    volatile uint32_t data_payload[NUM_CLUSTERS][16];

    /**
     * @brief Persistent trampoline function pointers for each cluster core.
     *
     * Each entry holds the function to be called by the trampoline on the
     * corresponding core.
     */
    volatile uint32_t trampoline_function[NUM_CLUSTER_CORES];

    /**
     * @brief Persistent argument storage for each cluster core's trampoline
     * function.
     *
     * Each entry holds the `void*` argument passed to the trampoline on the
     * corresponding core.
     */
    volatile uint32_t trampoline_args[NUM_CLUSTER_CORES];

    /**
     * @brief Persistent stack pointer storage for each cluster core's trampoline
     * context.
     *
     * Each entry holds the stack pointer to be loaded by the trampoline on the
     * corresponding core.
     */
    volatile uint32_t trampoline_stack[NUM_CLUSTER_CORES];

} chimera_shared_data_t;

extern chimera_shared_data_t shared_data;

#endif /* CHIMERA_SHARED_H */
