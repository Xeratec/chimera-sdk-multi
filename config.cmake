# SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna
# SPDX-License-Identifier: Apache-2.0

############################
# Host configuration
############################
set(ABI_HOST lp64)
set(ISA_HOST rv64imc)
set(COMPILER_RT_HOST rv64imc)
set(CROSS_COMPILE_HOST "riscv64-unknown-elf")

############################
# Device configuration
############################

#---- Device: Snitch Cluster 0 ----
set(ISA_DEVICE_SNITCH_CLUSTER_0 rv32imafd)
set(ABI_DEVICE_SNITCH_CLUSTER_0 ilp32d)
set(COMPILER_RT_DEVICE_SNITCH_CLUSTER_0 rv32imafd)
set(CROSS_COMPILE_DEVICE_SNITCH_CLUSTER_0 "riscv32-unknown-elf")

#---- Device: Snitch Cluster 1 ----
set(ISA_DEVICE_SNITCH_CLUSTER_1 rv32ima)
set(ABI_DEVICE_SNITCH_CLUSTER_1 ilp32)
set(COMPILER_RT_DEVICE_SNITCH_CLUSTER_1 rv32ima)
set(CROSS_COMPILE_DEVICE_SNITCH_CLUSTER_1 "riscv32-unknown-elf")

