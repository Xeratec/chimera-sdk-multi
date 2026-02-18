// SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
// SPDX-License-Identifier: Apache-2.0

#ifndef CHIMERA_SHARED_H
#define CHIMERA_SHARED_H

#include <stdint.h>

/*
 * Shared data structure exchanged between the host (CVA6, RV64) and device
 * accelerators (e.g. Snitch cluster, RV32).
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
 */
typedef struct __attribute__((packed)) {
    volatile uint32_t host_to_device_flag;  /* set by host, cleared by device */
    volatile uint32_t device_to_host_flag;  /* set by device, cleared by host */
    volatile uint32_t data_payload[16];     /* general-purpose exchange buffer */
} chimera_shared_data_t;

#endif /* CHIMERA_SHARED_H */
