// SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
// SPDX-License-Identifier: Apache-2.0

#include "shared.h"
#include "soc_addr_map.h"
#include "soc_regs.h"
#include <stddef.h>

/*
 * Shared data - placed in '.common' section (NOLOAD in device ELF).
 * The host binary initialises this memory at 0x48000000 (start of memisl).
 * The device accesses it via the AXI interconnect at the same address.
 */
chimera_shared_data_t shared_data __attribute__((section(".common")));

/**
 * @brief Setup the core to a known state.
 *
 * This function will set up the global pointer and thread pointer for the core.
 */
#define _SETUP_GP() \
    asm volatile(".option push\n" \
                 ".option norelax\n" \
                 "la gp, __global_pointer$\n" \
                 ".option pop\n" \
                 : /* No outputs */ \
                 : /* No inputs */ \
                 : /* No clobbered registers */)

/**
 * @brief Calculate the cluster ID from mhartid and set busy flag.
 *
 * @note This is a string fragment intended to be used inside an asm volatile
 * block. It reqires the following operands: %0: Base address of the busy
 * register for cluster 0 %1: Threshold for cluster 1 %2: Threshold for cluster
 * 2 %3: Threshold for cluster 3 %4: Threshold for cluster 4
 */
#define __CLUSTER_ID_ASM \
    "csrr t0, mhartid\n" /* t0 = mhartid */ \
    "li t1, 0\n"         /* t1 = cluster_id = 0 */ \
    "sltu t3, t0, %1\n"  /* t3 = (t0 < thresh1) ? 1 : 0 */ \
    "xori t3, t3, 1\n"   /* t3 = (t0 >= thresh1) ? 1 : 0 */ \
    "add t1, t1, t3\n"   /* t1 += t3 (cluster_id = 1) */ \
    "sltu t3, t0, %2\n"  /* t3 = (t0 < thresh2) ? 1 : 0 */ \
    "xori t3, t3, 1\n"   /* t3 = (t0 >= thresh2) ? 1 : 0 */ \
    "add t1, t1, t3\n"   /* t1 += t3 (cluster_id = 2) */ \
    "sltu t3, t0, %3\n"  /* t3 = (t0 < thresh3) ? 1 : 0 */ \
    "xori t3, t3, 1\n"   /* t3 = (t0 >= thresh3) ? 1 : 0 */ \
    "add t1, t1, t3\n"   /* t1 += t3 (cluster_id = 3) */ \
    "sltu t3, t0, %4\n"  /* t3 = (t0 < thresh4) ? 1 : 0 */ \
    "xori t3, t3, 1\n"   /* t3 = (t0 >= thresh4) ? 1 : 0 */ \
    "add t1, t1, t3\n"   /* t1 += t3 (cluster_id = 4) */

/**
 * @brief Compute cluster id form the hartid adn set busy flag.
 *
 * @note This is a naked-friendly macro intended to be used inside an asm
 * volatile block.
 */
#define _SET_CLUSTER_BUSY() \
    asm volatile(__CLUSTER_ID_ASM "slli t1, t1, 2\n" /* t1 = cluster_id * 4 */ \
                                  "add t1, %0, t1\n" /* t1 = base + cluster_id*4 */ \
                                  "li t2, 1\n" \
                                  "sw t2, 0(t1)\n" \
                 : /* no outputs */ \
                 : "r"((uintptr_t)(SOC_CTRL_BASE + CHIMERA_CLUSTER_0_BUSY_REG_OFFSET)), \
                   "r"((uintptr_t)(HOST_NUMCORES + CLUSTER_0_NUMCORES)), \
                   "r"((uintptr_t)(HOST_NUMCORES + CLUSTER_0_NUMCORES + CLUSTER_1_NUMCORES)), \
                   "r"((uintptr_t)(HOST_NUMCORES + CLUSTER_0_NUMCORES + CLUSTER_1_NUMCORES + \
                                   CLUSTER_2_NUMCORES)), \
                   "r"((uintptr_t)(HOST_NUMCORES + CLUSTER_0_NUMCORES + CLUSTER_1_NUMCORES + \
                                   CLUSTER_2_NUMCORES + CLUSTER_3_NUMCORES)) \
                 : "t0", "t1", "t2", "t3", "memory");

/**
 * @brief Compute cluster id from `mhartid` and clear busy.
 *
 * @note This is a naked-friendly macro intended to be used inside an asm
 * volatile block.
 */
#define _CLEAR_CLUSTER_BUSY() \
    asm volatile(__CLUSTER_ID_ASM "slli t1, t1, 2\n" /* t1 = cluster_id * 4 */ \
                                  "add t1, %0, t1\n" /* t1 = base + cluster_id*4 */ \
                                  "li t2, 0\n" \
                                  "sw t2, 0(t1)\n" \
                 : /* no outputs */ \
                 : "r"((uintptr_t)(SOC_CTRL_BASE + CHIMERA_CLUSTER_0_BUSY_REG_OFFSET)), \
                   "r"((uintptr_t)(HOST_NUMCORES + CLUSTER_0_NUMCORES)), \
                   "r"((uintptr_t)(HOST_NUMCORES + CLUSTER_0_NUMCORES + CLUSTER_1_NUMCORES)), \
                   "r"((uintptr_t)(HOST_NUMCORES + CLUSTER_0_NUMCORES + CLUSTER_1_NUMCORES + \
                                   CLUSTER_2_NUMCORES)), \
                   "r"((uintptr_t)(HOST_NUMCORES + CLUSTER_0_NUMCORES + CLUSTER_1_NUMCORES + \
                                   CLUSTER_2_NUMCORES + CLUSTER_3_NUMCORES)) \
                 : "t0", "t1", "t2", "t3", "memory");

/**
 * @brief Trampoline function for the cluster core.
 * This function will set up the stack pointer and call the function.
 *
 * @warning Make sure that this function is compiled with ISA for the Snitch
 * cores (RV32IM)
 *
 */
/*
 * _trampoline() — per-core entry point for offloaded work.
 *
 * Called by the interrupt handler after the host has written a function
 * pointer, argument, and stack pointer into the shared_data arrays for this
 * core.  The trampoline:
 *   1. Computes the core-local array index:  idx = hartid - CLUSTER_HART_BASE
 *   2. Loads sp  from shared_data.trampoline_stack[idx]
 *   3. Allocates TLS (.tdata + .tbss) on the new stack
 *   4. Loads fn  from shared_data.trampoline_function[idx]
 *   5. Loads arg from shared_data.trampoline_args[idx]
 *   6. Tail-calls fn(arg)
 *
 * Why this works across all device binaries:
 *   The .common section is placed at ORIGIN(memisl) = 0x48000000 (NOLOAD)
 *   in every device linker script, so &shared_data == 0x48000000 everywhere.
 *   The field offsets are compile-time constants (offsetof), identical for
 *   every compilation unit that includes shared.h.
 *   => All devices access the same physical memory cells.
 *
 * NOTE: naked attribute — compiler emits no prologue/epilogue.
 *       Only asm volatile blocks are allowed inside.
 */
void __attribute__((naked)) _trampoline() {
    _SETUP_GP();

    asm volatile(
        /* ── Step 1: core index → t0 = (hartid - CLUSTER_HART_BASE) * 4 ── */
        "csrr t0, mhartid\n"
        "addi t0, t0, -%[hartOffset]\n" /* t0 = hartid - CLUSTER_HART_BASE  */
        "slli t0, t0, 2\n"              /* t0 *= 4 (word-pointer byte index) */

        /* ── Step 2: sp = shared_data.trampoline_stack[idx] ── */
        "la   a0, shared_data\n"         /* a0  = &shared_data              */
        "addi a0, a0, %[stack_offset]\n" /* a0 += offsetof(trampoline_stack) */
        "add  a0, a0, t0\n"              /* a0  = &trampoline_stack[idx]   */
        "lw   sp, 0(a0)\n"               /* sp  = trampoline_stack[idx]    */

        /* ── Step 3: allocate TLS on the new stack ── */
        "la   t1, __tdata_end\n"
        "la   t2, __tdata_start\n"
        "sub  t1, t1, t2\n" /* t1 = sizeof(.tdata)             */
        "sub  sp, sp, t1\n" /* sp -= sizeof(.tdata)            */

        "la   t1, __tbss_end\n"
        "la   t2, __tbss_start\n"
        "sub  t1, t1, t2\n" /* t1 = sizeof(.tbss)              */
        "sub  sp, sp, t1\n" /* sp -= sizeof(.tbss)             */

        "mv   tp, sp\n"      /* tp = TLS base                   */
        "andi sp, sp, -16\n" /* align sp to 16-byte ABI boundary */

        /* ── Step 4: a1 = shared_data.trampoline_function[idx] ── */
        "la   a0, shared_data\n"
        "addi a0, a0, %[fn_offset]\n" /* a0 += offsetof(trampoline_function) */
        "add  a0, a0, t0\n"           /* a0  = &trampoline_function[idx] */
        "lw   a1, 0(a0)\n"            /* a1  = trampoline_function[idx]  */

        /* ── Step 5: a0 = shared_data.trampoline_args[idx] ── */
        "la   a0, shared_data\n"
        "addi a0, a0, %[args_offset]\n" /* a0 += offsetof(trampoline_args) */
        "add  a0, a0, t0\n"             /* a0  = &trampoline_args[idx]     */
        "lw   a0, 0(a0)\n"              /* a0  = trampoline_args[idx]      */

        /* ── Step 6: tail-call fn(arg) ── */
        "jr   a1\n"
        : /* no outputs */
        : [hartOffset] "i"(CLUSTER_HART_BASE),
          [stack_offset] "i"(offsetof(chimera_shared_data_t, trampoline_stack)),
          [fn_offset] "i"(offsetof(chimera_shared_data_t, trampoline_function)),
          [args_offset] "i"(offsetof(chimera_shared_data_t, trampoline_args)));
}

/**
 * @brief Interrupt handler for the cluster, which clears the interrupt flag for
 * the current hart.
 *
 * @warning Stack, thread and global pointer might not yet be set up!
 */
__attribute__((naked)) void clusterInterruptHandler() {
    _SET_CLUSTER_BUSY();
    _SETUP_GP();

    asm volatile(
        // Load mhartid CSR into t0
        "csrr t0, mhartid\n"

        // Load clint base address into t1
        "la t1, __base_clint\n"

        // Calculate the interrupt target address: t1 = t1 + (t0 * 4)
        "slli t0, t0, 2\n"
        "add t1, t1, t0\n"
        // Store 0 to the interrupt target address
        "sw zero, 0(t1)\n"
        "ret"
        :            // No outputs
        :            // No inputs
        : "t0", "t1" // Declare clobbered registers
    );
}

// Define some global variabils
char buffer[128];
char zero_buffer[128] = {0};
char one_buffer[128] = {[0 ... 127] = 1};

int main(void) {
    /* Wait for host to signal that work is ready for cluster 0 */
    while (!shared_data.host_to_device_flag[0]);

    /* Process data and write result into cluster 0's payload slot */
    shared_data.data_payload[0][0] = 42;

    /* Signal host that cluster 0 is done */
    shared_data.device_to_host_flag[0] = 1;

    return 0;
}
