/* SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna */
/* SPDX-License-Identifier: Apache-2.0 */

/*
 * Device linker script for the Snitch Cluster.
 *
 * Includes common.ldh to get the 'memisl' memory region definition, then
 * adds the device-private 'l1_tcdm' region.  The '.common' section is placed
 * into 'memisl' with NOLOAD: the linker records the correct address
 * (ORIGIN(memisl) = 0x48000000) but emits no bytes in the device ELF.
 * The host binary owns and initialises that memory.
 */

INCLUDE common.ldh

/* Device-private memory (merged with memisl from common.ldh) */
MEMORY {
  l1_tcdm (rwx) : ORIGIN = 0x10000000, LENGTH = 128K
}

/* Device-specific symbols */
__global_pointer$ = ADDR(.data) + SIZEOF(.data) / 2;
__stack_pointer$  = ORIGIN(l1_tcdm) + LENGTH(l1_tcdm);

SECTIONS {
  /* Keep binaries lean */
  /DISCARD/ : { *(.riscv.attributes) *(.comment) }

  /*
   * Shared communication area - NOLOAD.
   * Placed at the start of 'memisl' (0x48000000) to match the host binary.
   * The device accesses this region via the AXI interconnect; the host
   * initialises it.  No bytes are emitted in the device ELF.
   */
  .common (NOLOAD) : ALIGN(64) {
    __common_start = .;
    *(.common)
    *(.common.*)
    . = ALIGN(64);
    __common_end = .;
  } > memisl

  .init : {
    *(.init)
    *(.init.*)
  } > l1_tcdm

  .text : {
    *(.text)
    *(.text.*)
  } > l1_tcdm

  .rodata : ALIGN(16) {
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
  } > l1_tcdm

  .data : ALIGN(16) {
    *(.data)
    *(.data.*)
    *(.sdata)
    *(.sdata.*)
  } > l1_tcdm

  .bss (NOLOAD) : {
    . = ALIGN(16);
    __bss_start = .;
    *(.bss)
    *(.bss.*)
    *(.sbss)
    *(.sbss.*)
    . = ALIGN(16);
    __bss_end = .;
  } > l1_tcdm
}
