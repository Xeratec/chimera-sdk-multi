// SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
// SPDX-License-Identifier: Apache-2.0

#include "shared.h"

/*
 * Shared data - placed in '.common' section (NOLOAD in device ELF).
 * The host binary initialises this memory at 0x48000000 (start of memisl).
 * The device accesses it via the AXI interconnect at the same address.
 */
chimera_shared_data_t shared_data __attribute__((section(".common")));

int main(void) {
    /* Wait for host to signal that work is ready for cluster 1 */
    while (!shared_data.host_to_device_flag[1])
        ;

    /* Process data and write result into cluster 1's payload slot */
    shared_data.data_payload[1][0] = 84;

    /* Signal host that cluster 1 is done */
    shared_data.device_to_host_flag[1] = 1;

    return 0;
}
