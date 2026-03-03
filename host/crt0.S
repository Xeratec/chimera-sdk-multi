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
    addi sp, sp, -12
    sw ra, 8(sp)
    sw gp, 4(sp)
    sw sp, 0(sp)

    // Set trap vector
    la t0, _trap_handler_wrap
    csrrw x0, mtvec, t0

    // Zero the .bss section
    la t0, __bss_start
    la t1, __bss_end
    sub t2, t1, t0
    li a0, 0

_zero_bss_loop:
    addi t4, t2, -16
    blez t2, _fp_init
    blt t4, x0, _zero_bss_rem
    sw a0, 0(t0)
    sw a0, 4(t0)
    sw a0, 8(t0)
    sw a0, 12(t0)
    addi t2, t2, -16
    addi t0, t0, 16
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
    lw ra, 8(sp)
    lw gp, 4(sp)
    lw sp, 0(sp)
    // Save return value and exit
    slli t0, a0, 1
    ori  t0, t0, 1
    la t1, __base_regs
    sw t0, 8(t1)
    ebreak
    ret

// Trap handler wrapper
.align 4
_trap_handler_wrap:
    addi sp, sp, -64
    sw ra, 60(sp)
    sw t0, 56(sp)
    sw t1, 52(sp)
    sw t2, 48(sp)
    sw a0, 44(sp)
    sw a1, 40(sp)
    sw a2, 36(sp)
    sw a3, 32(sp)
    sw a4, 28(sp)
    sw a5, 24(sp)
    sw a6, 20(sp)
    sw a7, 16(sp)
    sw t3, 12(sp)
    sw t4, 8(sp)
    sw t5, 4(sp)
    sw t6, 0(sp)

    jal trap_vector

    lw ra, 60(sp)
    lw t0, 56(sp)
    lw t1, 52(sp)
    lw t2, 48(sp)
    lw a0, 44(sp)
    lw a1, 40(sp)
    lw a2, 36(sp)
    lw a3, 32(sp)
    lw a4, 28(sp)
    lw a5, 24(sp)
    lw a6, 20(sp)
    lw a7, 16(sp)
    lw t3, 12(sp)
    lw t4, 8(sp)
    lw t5, 4(sp)
    lw t6, 0(sp)
    addi sp, sp, 64
    mret

.weak trap_vector
trap_vector:
    j trap_vector
