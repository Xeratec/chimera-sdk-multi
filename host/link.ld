/* SPDX-FileCopyrightText: 2024 ETH Zurich and University of Bologna */
/* SPDX-License-Identifier: Apache-2.0 */

INCLUDE common.ldh

/* Host-specific memory definitions */
__global_pointer$ = ADDR(.misc) + SIZEOF(.misc) / 2;
__stack_pointer$  = ORIGIN(memisl) + LENGTH(memisl);

/* Base addresses for peripherals */
__base_dma      = 0x01000000;
__base_bootrom  = 0x02000000;
__base_clint    = 0x02040000;
__base_axirt    = 0x020C0000;
__base_axirtgrd = 0x020C1ffc;
__base_regs     = 0x03000000;
__base_llc      = 0x03001000;
__base_uart     = 0x03002000;
__base_i2c      = 0x03003000;
__base_spih     = 0x03004000;
__base_gpio     = 0x03005000;
__base_slink    = 0x03006000;
__base_vga      = 0x03007000;
__base_usb      = 0x03008000;
__base_bus_err  = 0x03009000;
__base_plic     = 0x04000000;
__base_clic     = 0x08000000;
__base_memisl   = ORIGIN(memisl);

SECTIONS {
  /* Keep binaries lean */
  /DISCARD/ : { *(.riscv.attributes) *(.comment) }

  /*
   * Shared communication area.
   * Placed first in memisl so it lives at a fixed, well-known address
   * (ORIGIN(memisl) = 0x48000000).  The host binary loads (initialises)
   * this section; device binaries map it NOLOAD.
   */
  .common : ALIGN(64) {
    __common_start = .;
    KEEP(*(.common))
    KEEP(*(.common.*))
    . = ALIGN(64);
    __common_end = .;
  } > memisl

  .text : {
    *(.text._start)
    *(.text)
    *(.text.*)
  } > memisl

  .misc : ALIGN(16) {
    *(.rodata)
    *(.rodata.*)
    *(.data)
    *(.data.*)
    *(.srodata)
    *(.srodata.*)
    *(.sdata)
    *(.sdata.*)
  } > memisl

  .bss (NOLOAD) : {
    . = ALIGN(32);
    __bss_start = .;
    *(.bss)
    *(.bss.*)
    *(.sbss)
    *(.sbss.*)
    . = ALIGN(32);
    __bss_end = .;
  } > memisl
}
