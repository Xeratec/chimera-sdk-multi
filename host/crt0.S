// SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
// SPDX-License-Identifier: Apache-2.0

.section .text._start
// Minimal CRT0 for CVA6 Host
.global _start
_start:
    // Globally disable Machine and Supervisor interrupts
    csrrc x0, mstatus, 10

    // Park SMP harts
    csrr t0, mhartid
    beqz t0, 2f
1:
    wfi
    j 1b
2:
    // Init stack and global pointer
    .option push
    .option norelax
    la sp, __stack_pointer$
    la gp, __global_pointer$
    .option pop

    // Store existing stack, global, return pointers on new stack
    addi sp, sp, -24
    sd ra, 16(sp)
    sd gp, 8(sp)
    sd sp, 0(sp)

    // Set trap vector
    la t0, _trap_handler_wrap
    csrrw x0, mtvec, t0

    // Zero the .bss section
    la t0, __bss_start
    la t1, __bss_end
    sub t2, t1, t0
    li a0, 0

_zero_bss_loop:
    addi t4, t2, -32
    blez t2, _fp_init
    blt t4, x0, _zero_bss_rem
    sd a0, 0(t0)
    sd a0, 8(t0)
    sd a0, 16(t0)
    sd a0, 24(t0)
    addi t2, t2, -32
    addi t0, t0, 32
    bgt t2, x0, _zero_bss_loop
    j _fp_init

_zero_bss_rem:
    sb a0, 0(t0)
    addi t2, t2, -1
    addi t0, t0, 1
    bgt t2, x0, _zero_bss_rem

_fp_init:
    // Initialize UART and call main
    # call _uart_init
    call main
    mv t0, a0
    # call _uart_deinit
    mv a0, t0

// If main returns, we end up here
.global _exit
_exit:
    // Restore the original context registers
    ld ra, 16(sp)
    ld gp, 8(sp)
    ld sp, 0(sp)
    // Save return value and exit
    slli t0, a0, 1
    ori  t0, t0, 1
    la t1, __base_regs
    sd t0, 16(t1)
    ebreak
    ret

// Trap handler wrapper
.align 4
_trap_handler_wrap:
    addi sp, sp, -128
    sd ra, 120(sp)
    sd t0, 112(sp)
    sd t1, 104(sp)
    sd t2, 96(sp)
    sd a0, 88(sp)
    sd a1, 80(sp)
    sd a2, 72(sp)
    sd a3, 64(sp)
    sd a4, 56(sp)
    sd a5, 48(sp)
    sd a6, 40(sp)
    sd a7, 32(sp)
    sd t3, 24(sp)
    sd t4, 16(sp)
    sd t5, 8(sp)
    sd t6, 0(sp)

    jal trap_vector

    ld ra, 120(sp)
    ld t0, 112(sp)
    ld t1, 104(sp)
    ld t2, 96(sp)
    ld a0, 88(sp)
    ld a1, 80(sp)
    ld a2, 72(sp)
    ld a3, 64(sp)
    ld a4, 56(sp)
    ld a5, 48(sp)
    ld a6, 40(sp)
    ld a7, 32(sp)
    ld t3, 24(sp)
    ld t4, 16(sp)
    ld t5, 8(sp)
    ld t6, 0(sp)
    addi sp, sp, 128
    mret

.weak trap_vector
trap_vector:
    j trap_vector