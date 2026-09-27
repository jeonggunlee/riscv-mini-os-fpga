`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// 8-N-1 UART transmitter with ready/valid input handshake
// -----------------------------------------------------------------------------
// valid && ready인 rising edge에서 data byte를 받아 다음 순서로 직렬화한다.
//   idle(1) -> start(0) -> data[0]..data[7] LSB first -> stop(1)
// parity bit는 없고 stop bit는 1개다. 송신 중 ready는 0이므로 producer는 새 data를
// 보내기 전에 ready가 다시 1이 될 때까지 기다려야 한다.
//
// CLKS_PER_BIT는 integer division이므로 실제 baud는 CLOCK_HZ/CLKS_PER_BIT다.
// Nexys A7 설정에서는 100 MHz / 868 = 약 115207 baud로 오차가 충분히 작다.
// -----------------------------------------------------------------------------
module uart_tx #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer BAUD     = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       valid,    // producer가 data를 보낼 준비가 되었음을 나타내는 1-cycle pulse
    input  wire [7:0] data,
    output wire       ready,    // transmitter가 data를 받을 준비가 되었음을 나타내는 combinational signal
    output reg        tx
);
    localparam integer CLKS_PER_BIT = CLOCK_HZ / BAUD;
    localparam integer COUNT_W = $clog2(CLKS_PER_BIT);
    reg [COUNT_W-1:0] count; // 현재 serial bit에 남은 clock 수
    reg [3:0] bit_index;     // 전송 중인 frame bit 번호: start=0 ... stop=9
    reg [9:0] shift;         // {stop, data[7:0], start} frame shift register
    reg busy;

    // ready는 idle 상태를 직접 나타내는 combinational handshake signal이다.
    assign ready = !busy;

    always @(posedge clk) begin
        if (rst) begin
            count <= 0;
            bit_index <= 0;
            shift <= 10'h3ff;
            busy <= 1'b0;
            tx <= 1'b1;
        end else if (!busy) begin
            // UART line은 idle-high. valid가 보이면 frame을 capture하고 start bit를
            // 즉시 출력한 뒤 그 bit를 CLKS_PER_BIT clocks 동안 유지한다.
            tx <= 1'b1;
            if (valid) begin
                shift <= {1'b1, data, 1'b0};
                count <= CLKS_PER_BIT - 1;
                bit_index <= 0;
                busy <= 1'b1;
                tx <= 1'b0;
            end
        end else if (count != 0) begin
            // 아직 현재 bit period 안에 있으면 line을 그대로 두고 countdown한다.
            count <= count - 1'b1;
        end else if (bit_index == 9) begin
            // Stop bit period까지 끝났으므로 idle/ready 상태로 돌아간다.
            busy <= 1'b0;
            tx <= 1'b1;
        end else begin
            // 다음 bit를 bit 0 위치로 shift하고, shift 전의 bit 1을 line에 출력한다.
            // 첫 전환에서는 data[0], 마지막 전환에서는 stop bit가 출력된다.
            bit_index <= bit_index + 1'b1;
            shift <= {1'b1, shift[9:1]};
            tx <= shift[1];
            count <= CLKS_PER_BIT - 1;
        end
    end
endmodule

`default_nettype wire
