/* Minimum flat application ABI: position-dependent RV32I code at 0x4000.
 * No .bss or relocation. The shell calls app_main() as an ordinary function. */
OUTPUT_ARCH(riscv)
ENTRY(app_main)
MEMORY { APP (rwx) : ORIGIN = 0x00004000, LENGTH = 8K }
SECTIONS
{
    . = ORIGIN(APP);
    .text : ALIGN(4) {
        KEEP(*(.text.app_entry))
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > APP
    .data : ALIGN(4) { *(.data .data.*) } > APP
    .bss (NOLOAD) : ALIGN(4) { *(.bss .bss.*) *(COMMON) } > APP
    ASSERT(SIZEOF(.bss) == 0, "minimum app format does not support .bss")
    /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
