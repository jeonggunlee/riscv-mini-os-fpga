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
    la   sp, _stack_top

    la   t0, _bss_start
    la   t1, _bss_end
1:
    bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
    la   t0, trap_entry
    csrw mtvec, t0

    call kernel_main
3:
    j    3b
