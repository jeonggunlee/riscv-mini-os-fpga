/*
 * Trap entry / exit and context switch.
 *
 * On any trap the core jumps here with MIE=0, mepc = interrupted PC and all
 * general registers untouched. The full context is saved as a 128-byte frame
 * on the *interrupted task's own stack*:
 *
 *     offset 0      mepc  (resume PC)
 *     offset 4*n    x_n   for n = 1..31   (x2 slot holds the pre-trap sp)
 *
 * trap_handler(frame*) in kernel.c returns the frame to resume. If it returns
 * a different task's frame, "mv sp, a0" switches stacks and the restore
 * sequence below reloads that task's registers: that single move is the
 * context switch. mret then jumps to the frame's mepc and restores MIE from
 * MPIE, which the hardware set from the MIE that was active before the trap.
 *
 * struct frame in kernel.c must match this layout exactly.
 */
    .option norvc
    .section .text.trap, "ax", @progbits
    .align 2                     /* mtvec[1:0] must be 00 */
    .globl trap_entry
trap_entry:
    addi sp, sp, -128
    sw   x1,    4(sp)
    sw   x3,   12(sp)
    sw   x4,   16(sp)
    sw   x5,   20(sp)
    sw   x6,   24(sp)
    sw   x7,   28(sp)
    sw   x8,   32(sp)
    sw   x9,   36(sp)
    sw   x10,  40(sp)
    sw   x11,  44(sp)
    sw   x12,  48(sp)
    sw   x13,  52(sp)
    sw   x14,  56(sp)
    sw   x15,  60(sp)
    sw   x16,  64(sp)
    sw   x17,  68(sp)
    sw   x18,  72(sp)
    sw   x19,  76(sp)
    sw   x20,  80(sp)
    sw   x21,  84(sp)
    sw   x22,  88(sp)
    sw   x23,  92(sp)
    sw   x24,  96(sp)
    sw   x25, 100(sp)
    sw   x26, 104(sp)
    sw   x27, 108(sp)
    sw   x28, 112(sp)
    sw   x29, 116(sp)
    sw   x30, 120(sp)
    sw   x31, 124(sp)
    /* All registers are saved; t0 (x5) is free to use from here on. */
    addi t0, sp, 128
    sw   t0,    8(sp)            /* original sp, for debugging only */
    csrr t0, mepc                /* save mepc in the frame */
    sw   t0,    0(sp)

    /* 
       Call trap_handler() in kernel.c, which returns the frame to resume in a0. 
       If it returns a different task's frame, "mv sp, a0" switches stacks and the restore sequence below reloads that task's registers:
        --> that single move is the context switch.

        struct frame *trap_handler(struct frame *f)

       * `trap_handler()`가 반환한 frame 포인터는 `a0` 레지스터로 전달되고, `trap.S`는 그 주소를 `sp`에 넣어 복원할 문맥을 선택합니다. 
    */    
    mv   a0, sp                  /* a0 = frame to resume, which may be the same or a different task */
    call trap_handler            /* <-- trap_handler may return a different task's frame in a0 */
    mv   sp, a0                  /* <-- context switch happens here */

    lw   t0,    0(sp)            /* restore mepc from the frame */
    csrw mepc, t0
    lw   x1,    4(sp)
    lw   x3,   12(sp)
    lw   x4,   16(sp)
    lw   x5,   20(sp)
    lw   x6,   24(sp)
    lw   x7,   28(sp)
    lw   x8,   32(sp)
    lw   x9,   36(sp)
    lw   x10,  40(sp)
    lw   x11,  44(sp)
    lw   x12,  48(sp)
    lw   x13,  52(sp)
    lw   x14,  56(sp)
    lw   x15,  60(sp)
    lw   x16,  64(sp)
    lw   x17,  68(sp)
    lw   x18,  72(sp)
    lw   x19,  76(sp)
    lw   x20,  80(sp)
    lw   x21,  84(sp)
    lw   x22,  88(sp)
    lw   x23,  92(sp)
    lw   x24,  96(sp)
    lw   x25, 100(sp)
    lw   x26, 104(sp)
    lw   x27, 108(sp)
    lw   x28, 112(sp)
    lw   x29, 116(sp)
    lw   x30, 120(sp)
    lw   x31, 124(sp)
    addi sp, sp, 128
    mret
