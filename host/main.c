// SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
// SPDX-License-Identifier: Apache-2.0

#include "shared.h"
#include "snitch_cluster_0_symbols.h"
#include "snitch_cluster_1_symbols.h"

/*
 * Shared data - placed first in '.common' (= start of memisl, 0x48000000).
 * The host binary owns and initialises this section.
 * Device binaries map the same address as NOLOAD and access it via AXI.
 */
chimera_shared_data_t shared_data __attribute__((section(".common"))) = {0};

int main(void) {
    /*
     * In a real system the host would:
     * 1. DMA each device ELF into the cluster's TCDM.
     * 2. Program the cluster control registers:
     *      - boot address : snitch_clusterN__start
     *      - stack top    : snitch_clusterN___stack_top   (via symbols.h)
     *      - global ptr   : snitch_clusterN___global_pointer$
     * 3. Release both clusters simultaneously (or staggered).
     * 4. Poll / wait for completion flags.
     *
     * Here we just verify the symbols are accessible and simulate the flags.
     */

    /* Inspect device entry points (address reference keeps symbols alive) */
    void *c0_entry = (void *)snitch_cluster_0_main;
    void *c1_entry = (void *)snitch_cluster_1_main;
    (void)c0_entry;
    (void)c1_entry;

    /* Signal both clusters to start */
    shared_data.host_to_device_flag[0] = 1;
    shared_data.host_to_device_flag[1] = 1;

    /* Wait for cluster 0 to finish */
    while (!shared_data.device_to_host_flag[0])
        ;

    /* Wait for cluster 1 to finish */
    while (!shared_data.device_to_host_flag[1])
        ;

    /*
     * Results are in shared_data.data_payload[0][0] and [1][0].
     * Return the sum as a simple end-to-end check.
     */
    return (int)(shared_data.data_payload[0][0] + shared_data.data_payload[1][0]);
}
