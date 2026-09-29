OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K }
SECTIONS
{
    . = ORIGIN(RAM);
    .text : ALIGN(4) { KEEP(*(.text.start)) *(.text .text.*) *(.rodata .rodata.*) } > RAM
    .data : ALIGN(4) { *(.data .data.*) } > RAM
    .bss (NOLOAD) : ALIGN(4) {
        _bss_start = .; *(.bss .bss.*) *(COMMON)
        . = ALIGN(4); _bss_end = .;
    } > RAM
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
    /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
