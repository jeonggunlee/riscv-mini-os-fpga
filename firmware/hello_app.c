/* Standalone flat app: no libc, no globals, returns to the shell. */
typedef unsigned int uint32_t;

static void putc_sys(char c)
{
    register uint32_t a0 __asm__("a0") = (unsigned char)c;
    register uint32_t a7 __asm__("a7") = 1u; /* Mini OS SYS_PUTC */
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a7) : "memory"); // Call the system call.
}

__attribute__((section(".text.app_entry")))
void app_main(void)
{
    const char *p = "Hello from loaded app!\n";
    while (*p) putc_sys(*p++);
}
