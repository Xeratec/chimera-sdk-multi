// SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
// SPDX-License-Identifier: Apache-2.0

// Simplified startup code for Snitch Cluster device

.section .init
.global _start
_start:
    // Initialize global pointer
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    // Initialize stack pointer
    la sp, __stack_pointer$

    // Clear integer registers
    mv t0, x0
    mv t1, x0
    mv t2, x0
    mv t3, x0
    mv t4, x0
    mv t5, x0
    mv t6, x0
    mv a0, x0
    mv a1, x0
    mv a2, x0
    mv a3, x0
    mv a4, x0
    mv a5, x0
    mv a6, x0
    mv a7, x0
    mv s0, x0
    mv s1, x0
    mv s2, x0
    mv s3, x0
    mv s4, x0
    mv s5, x0
    mv s6, x0
    mv s7, x0
    mv s8, x0
    mv s9, x0
    mv s10, x0
    mv s11, x0

    // Clear FP registers (device has F and D extensions)
    fcvt.d.w f0, zero
    fcvt.d.w f1, zero
    fcvt.d.w f2, zero
    fcvt.d.w f3, zero
    fcvt.d.w f4, zero
    fcvt.d.w f5, zero
    fcvt.d.w f6, zero
    fcvt.d.w f7, zero
    fcvt.d.w f8, zero
    fcvt.d.w f9, zero
    fcvt.d.w f10, zero
    fcvt.d.w f11, zero
    fcvt.d.w f12, zero
    fcvt.d.w f13, zero
    fcvt.d.w f14, zero
    fcvt.d.w f15, zero
    fcvt.d.w f16, zero
    fcvt.d.w f17, zero
    fcvt.d.w f18, zero
    fcvt.d.w f19, zero
    fcvt.d.w f20, zero
    fcvt.d.w f21, zero
    fcvt.d.w f22, zero
    fcvt.d.w f23, zero
    fcvt.d.w f24, zero
    fcvt.d.w f25, zero
    fcvt.d.w f26, zero
    fcvt.d.w f27, zero
    fcvt.d.w f28, zero
    fcvt.d.w f29, zero
    fcvt.d.w f30, zero
    fcvt.d.w f31, zero

    // Zero .bss section
    la t0, __bss_start
    la t1, __bss_end
    sub t2, t1, t0
    beqz t2, _call_main

_zero_bss:
    sw zero, 0(t0)
    addi t0, t0, 4
    addi t2, t2, -4
    bnez t2, _zero_bss

_call_main:
    // Call main function
    call device_main

    // Park core after main returns
_end:
    wfi
    j _end