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
#include "minifs.h"

#define UART_TX      (*(volatile uint8_t  *)0x10000000u)    /* write-only. UART_TX is a byte-wide register, so the compiler must not generate 32-bit writes. */
#define UART_READY   (*(volatile uint32_t *)0x10000004u)    /* read-only. UART_READY is a 32-bit register, so the compiler must not generate 8-bit reads. */
#define UART_RX_DATA (*(volatile uint32_t *)0x10000008u)
#define UART_RX_READY (*(volatile uint32_t *)0x1000000cu)
#define MTIME_LO     (*(volatile uint32_t *)0x10001000u)    /* read-only. Only the low 32 bits of the 64-bit timer are memory-mapped. */
#define MTIMECMP_LO  (*(volatile uint32_t *)0x10001004u)    /* read/write. Only the low 32 bits of the 64-bit timer are memory-mapped. */

#ifndef TICK_CYCLES                  /* TICK_CYCLES is the timer period in CPU clocks */
#define TICK_CYCLES 125000u          /* 10 ms at 12.5 MHz */
#endif

#ifdef SHELL_MODE
#define NTASK        2               /* idle + interactive shell */
#else
#define NTASK        4               /* idle + 3 tasks */
#endif
#define STACK_WORDS  256             /* 1 KiB per task. The stack pointer is always aligned to 16 bytes, so the compiler can use aligned loads/stores for the frame. */

#define CAUSE_ILLEGAL   2u           /* illegal instruction */
#define CAUSE_ECALL_M   11u          /* ecall from M-mode */
#define CAUSE_MTIMER    0x80000007u  /* machine timer interrupt */

/* Must match the frame layout in trap.S: mepc, then x1..x31. */
struct frame {
    uint32_t mepc;                   /* saved mepc */
    uint32_t x[31];                  /* x[i] holds register x(i+1) */
};
#define REG(f, n) ((f)->x[(n) - 1])  /* REG(f, 10) is a0, REG(f, 17) is a7 */

enum {
    SYS_PUTC    = 1,                 /* a0 = byte            */
    SYS_YIELD   = 2,                 /* give up the rest of the slice */
    SYS_GETTICK = 3,                 /* returns tick count in a0 */
    SYS_FS_CREATE = 4,              /* a0=name */
    SYS_FS_WRITE = 5,               /* a0=name, a1=data, a2=size */
    SYS_FS_READ = 6,                /* a0=name, a1=buffer, a2=capacity */
    SYS_FS_DELETE = 7,              /* a0=name */
    SYS_FS_LIST = 8,                /* prints entries through UART */
    SYS_GETC = 9,                   /* nonblocking UART RX; -1 if empty */
    SYS_FS_READ_AT = 10            /* a0=name, a1=buffer, a2=capacity, a3=offset */
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

static void uart_putc_raw(char c)
{
    while ((UART_READY & 1u) == 0u) {
        /* transmitter busy */
    }
    UART_TX = (uint8_t)c;
}

static void uart_putc(char c)
{
#ifdef SHELL_MODE
    /* A terminal's LF may keep the current column; CR returns to column 0. */
    if (c == '\n') uart_putc_raw('\r');
#endif
    uart_putc_raw(c);
}

static void uart_puts(const char *s)
{
    while (*s != '\0')
        uart_putc(*s++);
}

// Print a 32-bit unsigned integer in decimal to the UART. This is used for the file size in the MiniFS demo.
// It is not used for the tick count, which is printed in hexadecimal by panic().
static void uart_put_u32(uint32_t n)
{
    static const uint32_t powers[] = {1000000000u, 100000000u, 10000000u,
        1000000u, 100000u, 10000u, 1000u, 100u, 10u, 1u};
    int i, started = 0;
    for (i = 0; i < 10; i++) {
        char digit = '0';
        while (n >= powers[i]) { n -= powers[i]; digit++; }
        if (digit != '0' || started || i == 9) {
            uart_putc(digit);
            started = 1;
        }
    }
}

// Print a file name and its size in bytes to the UART.
// This is used by the MiniFS demo to show the contents of the file system.
static void fs_emit(const char *name, uint32_t size)
{
    uart_puts(name);
    uart_puts("  ");
    uart_put_u32(size);
    uart_puts(" bytes\n");
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
#ifdef SHELL_MODE
    cur = 1;                        /* only shell task: do not idle for 10 ms */
#else
    if (++cur >= NTASK)              /* no '%' : RV32I has no divider and   */
        cur = 0;                     /* libgcc is not linked                 */
#endif
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
        case SYS_FS_CREATE:
            REG(f, 10) = (uint32_t)fs_create((const char *)REG(f, 10));
            return f;
        case SYS_FS_WRITE:
            REG(f, 10) = (uint32_t)fs_write((const char *)REG(f, 10),
                (const void *)REG(f, 11), REG(f, 12));
            return f;
        case SYS_FS_READ:
            REG(f, 10) = (uint32_t)fs_read((const char *)REG(f, 10),
                (void *)REG(f, 11), REG(f, 12));
            return f;
        case SYS_FS_DELETE:
            REG(f, 10) = (uint32_t)fs_delete((const char *)REG(f, 10));
            return f;
        case SYS_FS_LIST:
            fs_list(fs_emit);
            REG(f, 10) = 0;
            return f;
        case SYS_GETC:
            REG(f, 10) = (UART_RX_READY & 1u) ? UART_RX_DATA & 0xffu : (uint32_t)-1;
            return f;
        case SYS_FS_READ_AT:
            REG(f, 10) = (uint32_t)fs_read_at((const char *)REG(f, 10),
                (void *)REG(f, 11), REG(f, 12), REG(f, 13));
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

static int sys_fs_call(uint32_t number, uint32_t arg0, uint32_t arg1, uint32_t arg2)
{
    register uint32_t a0 __asm__("a0") = arg0;
    register uint32_t a1 __asm__("a1") = arg1;
    register uint32_t a2 __asm__("a2") = arg2;
    register uint32_t a7 __asm__("a7") = number;
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return (int)a0;
}

static void sys_puts(const char *s)
{
    while (*s) sys_putc(*s++);
}

#ifdef SHELL_MODE
#define APP_BASE          0x00004000u
#define APP_WINDOW_BYTES  8192u
#define APP_MAGIC         0x31505041u /* "APP1" little-endian */
#define APP_HEADER_BYTES  12u
#define APP_MAX_BYTES     ((FS_BLOCK_COUNT - 3u) * FS_BLOCK_SIZE - APP_HEADER_BYTES)

static int sys_fs_read_at(const char *name, void *buf, uint32_t cap, uint32_t off)
{
    register uint32_t a0 __asm__("a0") = (uint32_t)name;
    register uint32_t a1 __asm__("a1") = (uint32_t)buf;
    register uint32_t a2 __asm__("a2") = cap;
    register uint32_t a3 __asm__("a3") = off;
    register uint32_t a7 __asm__("a7") = SYS_FS_READ_AT;
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a3), "r"(a7) : "memory");
    return (int)a0;
}

static int str_eq(const char *a, const char *b)
{
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

static uint32_t str_len(const char *s)
{
    uint32_t n = 0;
    while (s[n]) n++;
    return n;
}

static char *word(char **cursor)
{
    char *p = *cursor, *start;
    while (*p == ' ') p++;
    start = p;
    while (*p && *p != ' ') p++;
    if (*p) *p++ = 0;
    *cursor = p;
    return start;
}

static int hex_digit(int ch)
{
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
    return -1;
}

static int parse_size(const char *s, uint32_t *value)
{
    uint32_t n = 0;
    if (!*s) return 0;
    while (*s) {
        if (*s < '0' || *s > '9') return 0;
        n = n * 10u + (uint32_t)(*s++ - '0');
        if (n > APP_MAX_BYTES) return 0;
    }
    if (!n) return 0;
    *value = n;
    return 1;
}

static int parse_checksum(const char *s, uint32_t *value)
{
    uint32_t n = 0;
    int i, d;
    for (i = 0; i < 8; i++) {
        if (!s[i]) return 0;
        d = hex_digit((unsigned char)s[i]);
        if (d < 0) return 0;
        n = (n << 4) | (uint32_t)d;
    }
    if (s[8]) return 0;
    *value = n;
    return 1;
}

/* ASCII-hex transfer keeps the UART protocol simple and inspectable. */
static int receive_hex_byte(void)
{
    int hi = -1, lo, ch;
    for (;;) {
        ch = sys_fs_call(SYS_GETC, 0, 0, 0);
        if (ch < 0) { sys_yield(); continue; }
        if (ch == ' ' || ch == '\r' || ch == '\n' || ch == '\t') continue;
        hi = hex_digit(ch);
        break;
    }
    if (hi < 0) return -1;
    for (;;) {
        ch = sys_fs_call(SYS_GETC, 0, 0, 0);
        if (ch < 0) { sys_yield(); continue; }
        if (ch == ' ' || ch == '\r' || ch == '\n' || ch == '\t') continue;
        lo = hex_digit(ch);
        break;
    }
    if (lo < 0) return -1;
    return (hi << 4) | lo;
}

static void shell_upload(const char *name, uint32_t size, uint32_t checksum)
{
    uint32_t *header = (uint32_t *)APP_BASE;
    uint8_t *payload = (uint8_t *)(APP_BASE + APP_HEADER_BYTES);
    uint32_t sum = 0, i;
    int byte;
    sys_puts("send hex:\n");
    for (i = 0; i < size; i++) {
        byte = receive_hex_byte();
        if (byte < 0) { sys_puts("bad hex\n"); return; }
        payload[i] = (uint8_t)byte;
        sum += (uint32_t)byte;
    }
    if (sum != checksum) { sys_puts("checksum mismatch\n"); return; }
    header[0] = APP_MAGIC;
    header[1] = size;
    header[2] = checksum;
    sys_fs_call(SYS_FS_CREATE, (uint32_t)name, 0, 0); /* duplicate is OK */
    byte = sys_fs_call(SYS_FS_WRITE, (uint32_t)name, APP_BASE,
                       APP_HEADER_BYTES + size);
    sys_puts(byte == (int)(APP_HEADER_BYTES + size) ? "uploaded\n" : "upload failed\n");
}

static void shell_run(const char *name)
{
    uint32_t header[3], size, sum = 0, off, chunk, i;
    uint8_t extra;
    uint8_t *app = (uint8_t *)APP_BASE;
    int got;
    if (sys_fs_read_at(name, header, sizeof(header), 0) != (int)sizeof(header) ||
        header[0] != APP_MAGIC) {
        sys_puts("not an app file\n"); return;
    }
    size = header[1];
    if (size < 4u || size > APP_MAX_BYTES || size > APP_WINDOW_BYTES) {
        sys_puts("invalid app size\n"); return;
    }
    for (off = 0; off < size; off += chunk) {
        chunk = size - off;
        if (chunk > 64u) chunk = 64u;
        got = sys_fs_read_at(name, app + off, chunk, APP_HEADER_BYTES + off);
        if (got != (int)chunk) { sys_puts("truncated app\n"); return; }
        for (i = 0; i < chunk; i++) sum += app[off + i];
    }
    if (sum != header[2] ||
        sys_fs_read_at(name, &extra, 1u, APP_HEADER_BYTES + size) != 0) {
        sys_puts("bad app checksum\n"); return;
    }
    sys_puts("running\n");
    ((void (*)(void))APP_BASE)(); /* trusted M-mode code, same shell task stack */
    sys_puts("returned\n");
}

static void shell_command(char *line)
{
    char buf[64];
    char *p = line, *cmd = word(&p), *name;
    int n, i;
    uint32_t off;
    if (!*cmd) return;
    if (str_eq(cmd, "help")) {
        sys_puts("help ls cat <file> write <file> <text> rm <file>\n");
        sys_puts("upload <file> <bytes> <sum8> | run <file>\n");
    } else if (str_eq(cmd, "ls")) {
        sys_fs_call(SYS_FS_LIST, 0, 0, 0);
    } else if (str_eq(cmd, "cat")) {
        name = word(&p);
        if (!*name) { sys_puts("usage: cat <file>\n"); return; }
        off = 0;
        for (;;) {
            n = sys_fs_read_at(name, buf, sizeof(buf), off);
            if (n < 0) { sys_puts("file not found\n"); break; }
            if (n == 0) { sys_putc('\n'); break; }
            for (i = 0; i < n; i++) sys_putc(buf[i]);
            off += (uint32_t)n;
        }
    } else if (str_eq(cmd, "write")) {
        name = word(&p);
        while (*p == ' ') p++;
        if (!*name) { sys_puts("usage: write <file> <text>\n"); return; }
        sys_fs_call(SYS_FS_CREATE, (uint32_t)name, 0, 0); // existing file: replace
        n = sys_fs_call(SYS_FS_WRITE, (uint32_t)name, (uint32_t)p, str_len(p));
        if (n < 0) sys_puts("write failed\n");
        else { sys_puts("written\n"); }
    } else if (str_eq(cmd, "rm")) {
        name = word(&p);
        if (!*name) { sys_puts("usage: rm <file>\n"); return; }
        n = sys_fs_call(SYS_FS_DELETE, (uint32_t)name, 0, 0);
        sys_puts(n == 0 ? "removed\n" : "file not found\n");
    } else if (str_eq(cmd, "upload")) {
        uint32_t size, checksum;
        char *bytes, *sum;
        name = word(&p);
        bytes = word(&p);
        sum = word(&p);
        if (!*name || !parse_size(bytes, &size) ||
            !parse_checksum(sum, &checksum)) {
            sys_puts("usage: upload <file> <bytes> <8-hex-digit-sum>\n");
            return;
        }
        shell_upload(name, size, checksum);
    } else if (str_eq(cmd, "run")) {
        name = word(&p);
        if (!*name) { sys_puts("usage: run <file>\n"); return; }
        shell_run(name);
    } else {
        sys_puts("unknown command (help)\n");
    }
}

static void task_shell(void)
{
    char line[96];
    uint32_t used = 0;
    int ch, overflow = 0, last_cr = 0;
    sys_puts("Mini Shell ready. Type help.\nrv> ");
    for (;;) {
        ch = sys_fs_call(SYS_GETC, 0, 0, 0);
        if (ch < 0) { sys_yield(); continue; }
        if (ch == '\n' && last_cr) { last_cr = 0; continue; }
        last_cr = (ch == '\r');
        if (ch == '\r' || ch == '\n') {
            sys_putc('\n');
            if (overflow) sys_puts("line too long\n");
            else { line[used] = 0; shell_command(line); }
            used = 0; overflow = 0;
            sys_puts("rv> ");
        } else if (ch == 8 || ch == 127) {
            if (used) { used--; sys_puts("\b \b"); }
        } else if (ch >= 32 && ch <= 126) {
            if (used < sizeof(line) - 1u && !overflow) {
                line[used++] = (char)ch;
                sys_putc((char)ch);
            } else overflow = 1;
        }
    }
}
#else

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
    static const char hello[] = "Hello RISC-V!\n";
    char buffer[sizeof(hello)];
    int size, i, ok;

    sys_puts("\n[MiniFS] create/write/list/read/delete demo\n");
    /* A CPU reset during an earlier demo may have left this test file. */
    sys_fs_call(SYS_FS_DELETE, (uint32_t)"hello.txt", 0, 0);
    if (sys_fs_call(SYS_FS_CREATE, (uint32_t)"hello.txt", 0, 0) == 0 &&
        sys_fs_call(SYS_FS_WRITE, (uint32_t)"hello.txt", (uint32_t)hello,
                    sizeof(hello) - 1u) == (int)sizeof(hello) - 1) {
        sys_puts("ls:\n");
        sys_fs_call(SYS_FS_LIST, 0, 0, 0);
        size = sys_fs_call(SYS_FS_READ, (uint32_t)"hello.txt", (uint32_t)buffer,
                           sizeof(buffer));
        ok = (size == (int)sizeof(hello) - 1);
        if (ok) {
            sys_puts("cat hello.txt: ");
            for (i = 0; i < size; i++) {
                if (buffer[i] != hello[i]) ok = 0;
                sys_putc(buffer[i]);
            }
        }
        if (sys_fs_call(SYS_FS_DELETE, (uint32_t)"hello.txt", 0, 0) != 0)
            ok = 0;
        if (sys_fs_call(SYS_FS_READ, (uint32_t)"hello.txt", (uint32_t)buffer,
                        sizeof(buffer)) != -1)
            ok = 0;
        sys_puts("rm hello.txt; ls:\n");
        sys_fs_call(SYS_FS_LIST, 0, 0, 0);
        sys_puts(ok ? "[MiniFS] PASS\n" : "[MiniFS] FAIL\n");
    } else {
        sys_puts("[MiniFS] FAIL\n");
    }
    for (;;) {
        sys_putc('C');
        sys_yield();
    }
}
#endif

/* --------------------------------------------------------------- kernel */

void kernel_main(void)
{
    fs_init();                      /* format on first boot; preserve on CPU reset */
#ifdef SHELL_MODE
    task_create(1, task_shell);
#else
    task_create(1, task_a);
    task_create(2, task_b);
    task_create(3, task_c);
#endif
    cur = 0;                         /* we are the idle task, slot 0 */

    uart_puts(
#ifdef SHELL_MODE
        "mini shell boot\n"
#else
        "mini OS boot\n"
#endif
    );

    timer_rearm();
    csr_write_mie(0x80u);            /* MTIE */
    csr_set_mstatus_mie();           /* MIE: from here on we can be preempted */

    for (;;) {
        /* Idle. The first timer IRQ saves this context into slot 0 and
         * switches to task_a; we get a turn again once per round. */
    }
}
