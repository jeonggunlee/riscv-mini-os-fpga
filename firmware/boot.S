/*
 * Mini OS reset entry.
 *
 * The linker places this at address 0, which is the core's reset vector.
 * Nothing (stack, .bss, trap vector) is set up by hardware, so this code does
 * it in order:
 *   1. sp <- _stack_top            kernel stack, needed before any C call
 *   2. zero .bss                   CPU_RESETN does not clear RAM, so a warm
 *                                  reset would otherwise see stale globals
 *   3. mtvec <- trap_entry         direct-mode trap vector (4-byte aligned)
 *   4. call kernel_main            creates tasks, arms the timer, enables MIE
 */
    .option norvc
    .section .text.start, "ax", @progbits
    .globl _start
_start:
    la   sp, _stack_top       /* set up stack pointer */

    la   t0, _bss_start       /* zero .bss. _bss_start and _bss_end are defined in the linker script */
    la   t1, _bss_end         /* t0 = start, t1 = end */
1:  /* .bss vaiables must be zero on warm reset, but CPU_RESETN does not clear RAM, so we clear .bss here. */
    bgeu t0, t1, 2f           /* if t0 >= t1, done */
    sw   zero, 0(t0)          /* clear .bss since CPU_RESETN does not clear RAM and .bss variables need to be zero on warm reset */
    addi t0, t0, 4            /* next word */
    j    1b
2:
    la   t0, trap_entry         /* trap_entry in trap.S */
    csrw mtvec, t0              /* direct-mode trap vector. mtvec[1:0] must be 00, so trap_entry must be 4-byte aligned. */
                                /* mtvec can also be read back through a CSR instruction. */
    call kernel_main
3:
    j    3b                     /* kernel_main should never return, but if it does, just loop forever. */
