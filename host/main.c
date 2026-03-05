// SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
// SPDX-License-Identifier: Apache-2.0

#include <stdbool.h>
#include <stdint.h>

#include "shared.h"
#include "soc_addr_map.h"
#include "soc_regs.h"

#include "snitch_cluster_0_symbols.h"
#include "snitch_cluster_1_symbols.h"

/*
 * Shared data - placed first in '.common' (= start of memisl, 0x48000000).
 * The host binary owns and initialises this section.
 * Device binaries map the same address as NOLOAD and access it via AXI.
 */
chimera_shared_data_t shared_data __attribute__((section(".common"))) = {0};

/**
 * @brief Get the hart ID of a core within a cluster.
 *
 * @param CLUSTER ID of the cluster
 * @param CORE ID of the core
 *
 * @return uint32_t Hart ID of the core
 */
static uint32_t _get_hart_id(uint32_t CLUSTER, uint32_t CORE) {
    return _chimera_hartBase[CLUSTER] + CORE;
}

/**
 * @brief Check if the cluster is busy.
 *
 * @param clusterId ID of the cluster to check
 * @return int Return 1 if the cluster is busy, 0 if it is idle, -1 if the
 * cluster ID is invalid
 */
int snitchCluster_busy(uint8_t clusterId) {
    volatile int32_t *busy_ptr;

    switch (clusterId) {
    case 0:
        busy_ptr = (volatile int32_t *)(SOC_CTRL_BASE + CHIMERA_CLUSTER_0_BUSY_REG_OFFSET);
        break;
    case 1:
        busy_ptr = (volatile int32_t *)(SOC_CTRL_BASE + CHIMERA_CLUSTER_1_BUSY_REG_OFFSET);
        break;
    case 2:
        busy_ptr = (volatile int32_t *)(SOC_CTRL_BASE + CHIMERA_CLUSTER_2_BUSY_REG_OFFSET);
        break;
    case 3:
        busy_ptr = (volatile int32_t *)(SOC_CTRL_BASE + CHIMERA_CLUSTER_3_BUSY_REG_OFFSET);
        break;
    case 4:
        busy_ptr = (volatile int32_t *)(SOC_CTRL_BASE + CHIMERA_CLUSTER_4_BUSY_REG_OFFSET);
        break;
    default:
        return -1;
    }

    return *busy_ptr;
}

/**
 * @brief Blocking wait for the cluster to become idle.
 * The function busy waits until the cluster is ready.
 *
 * @warning In the current Snitch bootrom implementation each cores clears the
 * busy flag as soon as is returned. Hence the busy flag does not reflect the
 * actual status of the cluster.
 *
 * @todo Fix the bootrom after adding synchornization primitives for the Snitch
 * cores.
 *
 * @param CLUSTER ID of the cluster to wait for.
 */
void wait_snitchCluster_busy(uint8_t CLUSTER) {
    while (snitchCluster_busy(CLUSTER) == 1);
    // The core acltually may still be busy doing work, but the busy flag is cleared at the end of
    // bootrom execution. So we add a small delay here to ensure the core has time to clear the busy
    // flag before we proceed.
    for (volatile int i = 0; i < 100; i++);
    return;
}

/**
 * @brief Set Clock Gating on specified cluster
 * @param CLUSTER ID of the cluster to set clock gating for
 * @param enable true to enable clock gating, false to disable
 *
 */
void set_snitchCluster_clockGating(uint8_t CLUSTER, bool enable) {

    switch (CLUSTER) {
    case 0:
        *(volatile uint8_t *)(SOC_CTRL_BASE + CHIMERA_CLUSTER_0_CLK_GATE_EN_REG_OFFSET) = enable;
        break;
    case 1:
        *(volatile uint8_t *)(SOC_CTRL_BASE + CHIMERA_CLUSTER_1_CLK_GATE_EN_REG_OFFSET) = enable;
        break;
    case 2:
        *(volatile uint8_t *)(SOC_CTRL_BASE + CHIMERA_CLUSTER_2_CLK_GATE_EN_REG_OFFSET) = enable;
        break;
    case 3:
        *(volatile uint8_t *)(SOC_CTRL_BASE + CHIMERA_CLUSTER_3_CLK_GATE_EN_REG_OFFSET) = enable;
        break;
    case 4:
        *(volatile uint8_t *)(SOC_CTRL_BASE + CHIMERA_CLUSTER_4_CLK_GATE_EN_REG_OFFSET) = enable;
        break;
    default:
        break;
    }
}

/**
 * @brief Set Soft Reset on specified cluster
 * @param CLUSTER ID of the cluster to set soft reset for
 * @param enable true to enable soft reset, false to disable
 */
void set_snitchCluster_reset(uint8_t CLUSTER, bool enable) {
    switch (CLUSTER) {
    case 0:
        *(volatile uint8_t *)(SOC_CTRL_BASE + CHIMERA_RESET_CLUSTER_0_REG_OFFSET) = enable;
        break;
    case 1:
        *(volatile uint8_t *)(SOC_CTRL_BASE + CHIMERA_RESET_CLUSTER_1_REG_OFFSET) = enable;
        break;
    case 2:
        *(volatile uint8_t *)(SOC_CTRL_BASE + CHIMERA_RESET_CLUSTER_2_REG_OFFSET) = enable;
        break;
    case 3:
        *(volatile uint8_t *)(SOC_CTRL_BASE + CHIMERA_RESET_CLUSTER_3_REG_OFFSET) = enable;
        break;
    case 4:
        *(volatile uint8_t *)(SOC_CTRL_BASE + CHIMERA_RESET_CLUSTER_4_REG_OFFSET) = enable;
        break;
    default:
        break;
    }

    // if (!enable) {
    //     // Wait for the cores to boot up and clear the busy flag (bootrom sets busy=1 at the end
    //     of boot) for (volatile int i = 0; i < 2500; i++);
    // } else {
    //     // Wait for the cores to reset and set the busy flag (bootrom sets busy=0 at the
    //     beginning of boot) for (volatile int i = 0; i < 100; i++);
    // }
}

#define CLUSTER 0
#define CORE 0
#define STACK_ADDRESS (_chimera_clusterBase[CLUSTER] + 0x20000 - 1)

int main(void) {
    volatile void **snitchTrapHandlerAddr =
        (volatile void **)(SOC_CTRL_BASE + CHIMERA_SNITCH_INTR_HANDLER_ADDR_REG_OFFSET);

    *snitchTrapHandlerAddr = snitch_cluster_0_clusterInterruptHandler;

    set_snitchCluster_clockGating(CLUSTER, 0);

    set_snitchCluster_reset(CLUSTER, 1);
    set_snitchCluster_reset(CLUSTER, 0);

    /* Inspect device entry points (address reference keeps symbols alive) */
    volatile uint32_t *snitchBootAddr =
        (volatile uint32_t *)(SOC_CTRL_BASE + CHIMERA_SNITCH_BOOT_ADDR_REG_OFFSET);

    uint32_t hartId = _get_hart_id(CLUSTER, CORE);
    uint32_t trampoline_idx = hartId - CLUSTER_HART_BASE;

    // Assign trampoline with captured arguments to the persistent function
    // pointer
    shared_data.trampoline_function[trampoline_idx] = (uint32_t)&snitch_cluster_0_main;
    shared_data.trampoline_args[trampoline_idx] = 0;
    shared_data.trampoline_stack[trampoline_idx] = STACK_ADDRESS;

    *snitchBootAddr = (uint32_t)&snitch_cluster_0__trampoline;

    // Check if the cluster is busy
    wait_snitchCluster_busy(CLUSTER);
    volatile uint32_t *interruptTarget = ((uint32_t *)CLINT_CTRL_BASE) + hartId;
    *interruptTarget = 1;

    shared_data.host_to_device_flag[0] = 1;

    while (!shared_data.device_to_host_flag[0]) {
        // Flush the d-cache
        asm volatile("fence" :::);
    }

    wait_snitchCluster_busy(CLUSTER);
    /*
     * Results are in shared_data.data_payload[0][0] and [1][0].
     * Return the sum as a simple end-to-end check.
     */
    return (shared_data.data_payload[0][0] != 42);
}
