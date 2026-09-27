/*
 * Mini OS kernel for the single-cycle RV32I SoC.
 *
 * Preemptive round-robin scheduler driven by the machine timer interrupt,
 * plus a tiny ecall-based system call interface. Everything runs in M-mode;
 * there is no memory protection, so tasks are trusted code.
 *
 * Task slots
 *   0        : the kernel idle loop at the end of kernel_main (kernel stack)
 *   1..NTASK-1: tasks created with task_create, each with its own stack
 *
 * TICK_CYCLES is the timer period in CPU clocks. The Makefile passes 125000
 * (10 ms at 12.5 MHz) for the FPGA image and a much smaller value for the
 * simulation image so a short run shows many context switches.
 *
 * Hardware facts this code relies on (see rtl/rv32_csr.v, rtl/simple_timer.v):
 *   * timer IRQ is a level: mtime >= mtimecmp. The handler must move
 *     mtimecmp forward before mret or the trap re-fires immediately.
 *   * trap entry sets mepc to the trapping PC. For ecall that instruction has
 *     completed, so the handler adds 4; for interrupts it is re-executed.
 *   * only the low 32 bits of mtime/mtimecmp are memory-mapped.
 */

typedef unsigned int uint32_t;
typedef unsigned char uint8_t;

#define UART_TX      (*(volatile uint8_t  *)0x10000000u)
#define UART_READY   (*(volatile uint32_t *)0x10000004u)
#define MTIME_LO     (*(volatile uint32_t *)0x10001000u)
#define MTIMECMP_LO  (*(volatile uint32_t *)0x10001004u)

#ifndef TICK_CYCLES
#define TICK_CYCLES 125000u          /* 10 ms at 12.5 MHz */
#endif

#define NTASK        4               /* idle + 3 tasks */
#define STACK_WORDS  256             /* 1 KiB per task */

#define CAUSE_ILLEGAL   2u
#define CAUSE_ECALL_M   11u
#define CAUSE_MTIMER    0x80000007u

/* Must match the frame layout in trap.S: mepc, then x1..x31. */
struct frame {
    uint32_t mepc;                   /* saved mepc */
    uint32_t x[31];                  /* x[i] holds register x(i+1) */
};
#define REG(f, n) ((f)->x[(n) - 1])  /* REG(f, 10) is a0, REG(f, 17) is a7 */

enum {
    SYS_PUTC    = 1,                 /* a0 = byte            */
    SYS_YIELD   = 2,                 /* give up the rest of the slice */
    SYS_GETTICK = 3                  /* returns tick count in a0 */
};

static struct frame *task_sp[NTASK];    /* saved stack pointer for each task */
static uint32_t stacks[NTASK - 1][STACK_WORDS] __attribute__((aligned(16)));  /* task stacks, 1 KiB each */
static int cur;                      /* slot currently running */
static volatile uint32_t ticks;      /* timer interrupts so far */

/* ------------------------------------------------------------------ CSR */

static inline uint32_t csr_read_mcause(void)
{
    uint32_t v;
    __asm__ volatile ("csrr %0, mcause" : "=r"(v));
    return v;
}

static inline void csr_write_mie(uint32_t v)
{
    __asm__ volatile ("csrw mie, %0" : : "r"(v));
}

static inline void csr_set_mstatus_mie(void)
{
    __asm__ volatile ("csrsi mstatus, 0x8");
}

/* ----------------------------------------------------------------- UART */

static void uart_putc(char c)
{
    while ((UART_READY & 1u) == 0u) {
        /* transmitter busy */
    }
    UART_TX = (uint8_t)c;
}

static void uart_puts(const char *s)
{
    while (*s != '\0')
        uart_putc(*s++);
}

/* ---------------------------------------------------------------- timer */

static void timer_rearm(void)
{
    /* Clears the level IRQ and schedules the next tick in one write. */
    MTIMECMP_LO = MTIME_LO + TICK_CYCLES;
}

/* ------------------------------------------------------------ scheduler */

static struct frame *schedule(struct frame *f)
{
    task_sp[cur] = f;                /* remember where this task's frame is */
    if (++cur >= NTASK)              /* no '%' : RV32I has no divider and   */
        cur = 0;                     /* libgcc is not linked                 */
    return task_sp[cur];
}

static void panic(uint32_t cause, uint32_t pc)
{
    static const char hex[] = "0123456789abcdef";
    int i;

    uart_puts("\nPANIC cause=");
    for (i = 28; i >= 0; i -= 4)
        uart_putc(hex[(cause >> i) & 0xfu]);
    uart_puts(" pc=");
    for (i = 28; i >= 0; i -= 4)
        uart_putc(hex[(pc >> i) & 0xfu]);
    uart_putc('\n');
    for (;;) {
    }
}

/* Called from trap.S with the saved frame; returns the frame to resume. */
struct frame *trap_handler(struct frame *f)
{
    uint32_t cause = csr_read_mcause();

    if (cause == CAUSE_MTIMER) {
        ticks++;
        timer_rearm();               /* before mret, or the IRQ re-fires */
        return schedule(f);
    }

    if (cause == CAUSE_ECALL_M) {
        f->mepc += 4;                /* resume after the ecall itself */
        switch (REG(f, 17)) {        /* a7 = system call number */
        case SYS_PUTC:
            uart_putc((char)REG(f, 10));
            return f;
        case SYS_YIELD:
            return schedule(f);
        case SYS_GETTICK:
            REG(f, 10) = ticks;
            return f;
        default:
            REG(f, 10) = (uint32_t)-1;
            return f;
        }
    }

    panic(cause, f->mepc);           /* illegal instruction or unknown */
    return f;
}

/* ---------------------------------------------------------------- tasks */

static void task_exit(void)
{
    /* A task's entry function returned. Park it here forever. */
    for (;;) {
    }
}

/*
 * Build an initial frame at the top of the task's stack so that the normal
 * restore path in trap.S can "return" into the task for the first time.
 */
static void task_create(int slot, void (*entry)(void))
{
    uint32_t *top = &stacks[slot - 1][STACK_WORDS];
    struct frame *f = (struct frame *)((uint8_t *)top - sizeof(struct frame));
    int i;

    for (i = 0; i < 31; i++)
        f->x[i] = 0;
    f->mepc   = (uint32_t)entry;
    REG(f, 1) = (uint32_t)task_exit; /* ra */
    REG(f, 2) = (uint32_t)top;       /* sp slot, informational */
    task_sp[slot] = f;
}

/* System call stubs used by tasks. */
static void sys_putc(char c)
{
    register uint32_t a0 __asm__("a0") = (uint8_t)c;
    register uint32_t a7 __asm__("a7") = SYS_PUTC;
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a7) : "memory");
}

static void sys_yield(void)
{
    register uint32_t a7 __asm__("a7") = SYS_YIELD;
    __asm__ volatile ("ecall" : : "r"(a7) : "memory");
}

static void task_a(void)
{
    for (;;)
        sys_putc('A');
}

static void task_b(void)
{
    for (;;)
        sys_putc('B');
}

/* Prints one character per turn, then hands the CPU back voluntarily. */
static void task_c(void)
{
    for (;;) {
        sys_putc('C');
        sys_yield();
    }
}

/* --------------------------------------------------------------- kernel */

void kernel_main(void)
{
    task_create(1, task_a);
    task_create(2, task_b);
    task_create(3, task_c);
    cur = 0;                         /* we are the idle task, slot 0 */

    uart_puts("mini OS boot\n");

    timer_rearm();
    csr_write_mie(0x80u);            /* MTIE */
    csr_set_mstatus_mie();           /* MIE: from here on we can be preempted */

    for (;;) {
        /* Idle. The first timer IRQ saves this context into slot 0 and
         * switches to task_a; we get a turn again once per round. */
    }
}
