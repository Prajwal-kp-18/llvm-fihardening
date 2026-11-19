/* Cortex-M memory map for eval/fisim.py: flash at 0, RAM at 0x20000000. Works
   with ld.lld and GNU ld. */
MEMORY {
  FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 256K
  RAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 64K
}
ENTRY(Reset_Handler)
SECTIONS {
  .text : { KEEP(*(.vectors)) *(.text*) *(.rodata*) } > FLASH
  .data : { _sdata = .; *(.data*) _edata = .; } > RAM AT > FLASH
  _sidata = LOADADDR(.data);
  .bss (NOLOAD) : { _sbss = .; *(.bss*) *(COMMON) _ebss = .; } > RAM
  _estack = ORIGIN(RAM) + LENGTH(RAM);
}
