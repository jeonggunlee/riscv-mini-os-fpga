OUTPUT_ARCH(riscv)
ENTRY(_start)
/* 32 KiB RAM: kernel below 0x4000, flat app at 0x4000..0x5fff,
 * kernel stack grows down from 0x8000 and must not enter the app window. */
MEMORY { KRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K }
SECTIONS
{
    . = ORIGIN(KRAM);
    .text : ALIGN(4) { KEEP(*(.text.start)) *(.text .text.*) *(.rodata .rodata.*) } > KRAM
    .data : ALIGN(4) { *(.data .data.*) } > KRAM
    .bss (NOLOAD) : ALIGN(4) {
        _bss_start = .; *(.bss .bss.*) *(COMMON)
        . = ALIGN(4); _bss_end = .;
    } > KRAM
    _stack_top = 0x00008000;
    ASSERT(_bss_end <= 0x00004000, "shell kernel exceeds reserved lower 16 KiB")
    /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
