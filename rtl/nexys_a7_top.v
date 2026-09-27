`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// Nexys A7-100T board-level top module
// -----------------------------------------------------------------------------
// Board resources
//   CLK100MHZ    : 100 MHz oscillator, pin E3
//   CPU_RESETN   : active-low CPU reset button, pin C12
//   UART_RXD_OUT : FPGA -> USB-UART bridge transmit line, pin D4
//   LED[15:0]    : current PC[17:2] for visible execution/debug indication
//
// Clock domains
//   * 100 MHz domain: clock divider and UART transmitter
//   * 12.5 MHz domain: RV32I SoC (cpu_div[2] through a BUFG)
//
// uart_valid/data는 12.5 MHz에서 만들어져 100 MHz UART로 전달되고 ready는 반대로
// 전달된다. 두 clock은 같은 100 MHz source에서 정확히 divide-by-8된 related clock이며
// XDC의 create_generated_clock가 CDC 경로를 timing 분석한다. valid/data는 한 CPU
// cycle(80 ns) 동안 유지되어 여러 100 MHz edge에서 안정적으로 관측된다.
// -----------------------------------------------------------------------------
module nexys_a7_top (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    output wire        UART_RXD_OUT,
    output wire [15:0] LED
);
    // CPU_RESETN은 board에서 비동기로 들어온다. reset은 즉시(assert asynchronously)
    // 걸되 각 clock domain에서 2-stage shift register로 동기 해제한다.
    reg [1:0] reset_sync;

    // 100 MHz binary counter의 bit 2는 input clock의 1/8인 12.5 MHz square wave다.
    reg [2:0] cpu_div;
    always @(posedge CLK100MHZ or negedge CPU_RESETN) begin
        if (!CPU_RESETN) begin
            reset_sync <= 2'b11;
            cpu_div <= 3'd0;
        end else begin
            reset_sync <= {reset_sync[0], 1'b0};
            cpu_div <= cpu_div + 1'b1;
        end
    end
    // UART/100 MHz domain용 active-high reset.
    wire rst_100 = reset_sync[1];
    wire cpu_clk;

    // Fabric divider 출력을 global clock network에 올려 clock skew를 줄인다.
    // constraints/nexys_a7_100t.xdc에서 이 BUFG output에 generated clock를 정의한다.
    BUFG cpu_clk_buf (.I(cpu_div[2]), .O(cpu_clk));

    // CPU clock domain용 reset synchronizer. CPU_RESETN low는 clock이 멈춘 상태에서도
    // reset을 assert할 수 있고, deassert는 cpu_clk rising edge에 맞춰 진행된다.
    reg [1:0] cpu_reset_sync;
    always @(posedge cpu_clk or negedge CPU_RESETN) begin
        if (!CPU_RESETN) cpu_reset_sync <= 2'b11;
        else cpu_reset_sync <= {cpu_reset_sync[0], 1'b0};
    end
    wire cpu_rst = cpu_reset_sync[1];

    // SoC와 UART transmitter 사이의 ready/valid byte channel.
    wire uart_valid, uart_ready;
    wire [7:0] uart_data;
    wire [31:0] debug_pc;

    // 2048 x 32-bit = 8 KiB unified memory. Firmware HEX는 Vivado synthesis 시
    // $readmemh로 memory 초기화 값에 포함된다.
    rv32_soc #(
        .MEM_WORDS(2048),
        .MEM_HEX("firmware/nexys_hello.hex")
    ) soc (
        .clk(cpu_clk), .rst(cpu_rst), .uart_tx_ready(uart_ready),
        .uart_tx_data(uart_data), .uart_tx_valid(uart_valid), .debug_pc(debug_pc)
    );

    // USB-UART bridge가 기대하는 115200 baud, 8 data bits, no parity, 1 stop bit.
    uart_tx #(.CLOCK_HZ(100_000_000), .BAUD(115_200)) serial (
        .clk(CLK100MHZ), .rst(rst_100), .valid(uart_valid), .data(uart_data),
        .ready(uart_ready), .tx(UART_RXD_OUT)
    );

    // PC는 4-byte 단위로 이동하므로 항상 0인 [1:0]을 버린다. Loop가 빠르면 LED에는
    // 시간 평균처럼 보이지만 reset/정지 loop와 대략적인 실행 위치 확인에 유용하다.
    assign LED = debug_pc[17:2];
endmodule

`default_nettype wire
