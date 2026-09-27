/*
 * Minimal freestanding RV32I C program.
 *
 * No C runtime or standard library is used. The linker places _start at address
 * zero, which is also the processor reset vector. The program computes
 * 1 + ... + 10, stores 55 at RAM address 0x400, prints "C OK\n" through the
 * memory-mapped UART, and then remains in an infinite loop.
 */

typedef unsigned int uint32_t;
typedef unsigned char uint8_t;

#define UART_TX_ADDR     0x10000000u
#define UART_READY_ADDR  0x10000004u
#define SIGNATURE_ADDR   0x00000400u

/* Volatile prevents GCC from replacing the summation loop with constant 55. */
volatile uint32_t sum_limit = 10u;

static void uart_putc(uint8_t value)
{
    volatile uint32_t *const uart_ready =
        (volatile uint32_t *)UART_READY_ADDR;
    volatile uint8_t *const uart_tx =
        (volatile uint8_t *)UART_TX_ADDR;

    while ((*uart_ready & 1u) == 0u) {
        /* Wait until the UART transmitter can accept the next byte. */
    }
    *uart_tx = value;
}

__attribute__((section(".text.start"), noreturn))
void _start(void)
{
    volatile uint32_t *const signature =
        (volatile uint32_t *)SIGNATURE_ADDR;
    static const char message[] = "C OK\n";
    uint32_t sum = 0u;
    uint32_t i;

    for (i = 1u; i <= sum_limit; ++i)
        sum += i;

    *signature = sum;

    for (i = 0u; message[i] != '\0'; ++i)
        uart_putc((uint8_t)message[i]);

    for (;;) {
        /* Bare-metal programs must not return from the reset entry point. */
    }
}
