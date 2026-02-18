// SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
// SPDX-License-Identifier: Apache-2.0

#include "shared.h"
#include "snitch_cluster_device_symbols.h"

/*
 * Shared data - placed first in '.common' (= start of memisl, 0x48000000).
 * The host binary owns and initialises this section.
 * Device binaries map the same address as NOLOAD and access it via AXI.
 */
chimera_shared_data_t shared_data __attribute__((section(".common"))) = {0};

int main(void) {
    /* Verify device symbols are accessible (address inspection only) */
    void *device_entry = (void *)snitch_cluster_device_device_main;
    void *device_start = (void *)snitch_cluster_device_binary_start;
    (void)device_entry;

    /* Signal device to start processing */
    shared_data.host_to_device_flag = 1;

    /*
     * In a real system:
     * 1. Program the DMA to transfer the device ELF to l1_tcdm
     * 2. Release the device core (write to cluster control registers)
     * 3. Poll device_to_host_flag (or use an interrupt) for completion
     * 4. Read results from shared_data.data_payload[]
     */

    /* Wait for device to signal completion */
    while (!shared_data.device_to_host_flag)
        ;

    return (int)device_start;  /* use symbol so linker keeps it */
}
