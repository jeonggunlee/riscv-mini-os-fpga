/* RV32I demo used to generate nexys_hello.hex. */
    .option norvc
    .section .text.start, "ax", @progbits
    .globl _start
_start:
    lui  ra, 0x10000          /* UART base: 0x10000000 */
    li   sp, 0x100            /* message address */
1:
    lbu  gp, 0(sp)
    beqz gp, 3f
2:
    lw   tp, 4(ra)            /* UART ready status */
    beqz tp, 2b
    sb   gp, 0(ra)
    addi sp, sp, 1
    j    1b
3:
    j    3b

    .org 0x100
message:
    .asciz "Hello Nexys A7!\r\n"
