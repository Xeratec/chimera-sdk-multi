# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

# Configuration for multi-binary example
# Host: CVA6 with RV64IMC
# Device: Snitch cluster with RV32IMAFD

# Host configuration (CVA6)
set(ABI_HOST lp64)
set(ISA_HOST rv64imc)
set(COMPILERRT_HOST rv64imc)

# Device configuration (Snitch Cluster)
set(ABI_DEVICE ilp32d)
set(ISA_DEVICE rv32imafd)
set(COMPILERRT_DEVICE rv32imafd)

# Cross-compile targets
set(CROSS_COMPILE_HOST "riscv64-unknown-elf")
set(CROSS_COMPILE_DEVICE "riscv32-unknown-elf")
