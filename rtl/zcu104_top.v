`timescale 1ns/1ps
`default_nettype none

// ZCU104 PL-only RV32I + Mini OS. No ARM software, PS clock or DDR is needed.
// Board clock: CLK_300_P/N (AH18/AH17), nominal 300 MHz from U182.
// CPU_RESET: SW20, active HIGH (unlike the Nexys A7 reset input).
// UART_TX: C19 -> FT4232 channel D RX, 115200 8-N-1, no flow control.
module zcu104_top #(
    parameter MEM_HEX = "firmware/mini_os.hex"
) (
    input  wire CLK_300_P,
    input  wire CLK_300_N,
    input  wire CPU_RESET,
    output wire UART_TX,
    output wire [3:0] LED
);
    wire clk_in, clk_300, cpu_clk;
    // AC-coupled, externally biased 1.2 V differential clock input.
    IBUFDS #(.IBUF_LOW_PWR("FALSE")) clock_input (
        .I(CLK_300_P), .IB(CLK_300_N), .O(clk_in)
    );
    BUFG clock_global (.I(clk_in), .O(clk_300));

    // Divide by 24, then use a global clock buffer: CPU and UART both run
    // at 12.5 MHz. Sharing one domain avoids a UART ready/valid CDC entirely.
    // FPGA INIT values start the divider without requiring a button press.
    reg [3:0] divider = 4'd0;
    reg divided_clk = 1'b0;
    always @(posedge clk_300) begin
        if (divider == 4'd11) begin
            divider <= 4'd0;
            divided_clk <= ~divided_clk;
        end else divider <= divider + 1'b1;
    end
    BUFG cpu_clk_buf (.I(divided_clk), .O(cpu_clk));

    // Configuration-time reset plus asynchronous button assertion and
    // synchronous release. The divider keeps running while SW20 is pressed.
    (* ASYNC_REG = "TRUE" *) reg [3:0] reset_sync = 4'b1111;
    always @(posedge cpu_clk or posedge CPU_RESET) begin
        if (CPU_RESET) reset_sync <= 4'b1111;
        else reset_sync <= {reset_sync[2:0], 1'b0};
    end
    wire rst = reset_sync[3];
    wire valid, ready;
    wire [7:0] data;
    wire [31:0] pc;

    rv32_soc #(.MEM_WORDS(2048), .MEM_HEX(MEM_HEX)) soc (
        .clk(cpu_clk), .rst(rst), .uart_tx_ready(ready),
        .uart_tx_data(data), .uart_tx_valid(valid), .debug_pc(pc)
    );
    uart_tx #(.CLOCK_HZ(12_500_000), .BAUD(115_200)) serial (
        .clk(cpu_clk), .rst(rst), .valid(valid), .data(data),
        .ready(ready), .tx(UART_TX)
    );

    // LED0 heartbeat (~1.5 Hz), LED1 reset released, LED2 UART busy,
    // LED3 a PC bit. LED activity alone is NOT a Mini OS correctness test.
    reg [23:0] heartbeat = 24'd0;
    always @(posedge cpu_clk) begin
        if (rst) heartbeat <= 24'd0;
        else heartbeat <= heartbeat + 1'b1;
    end
    assign LED = {pc[8], !ready, !rst, heartbeat[22]};
endmodule

`default_nettype wire
