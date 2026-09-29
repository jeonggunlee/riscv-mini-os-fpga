`timescale 1ns/1ps
`default_nettype none

// 8-N-1 UART receiver. valid pulses for one clock on a good stop bit.
module uart_rx #(
    parameter integer CLOCK_HZ = 12_500_000,
    parameter integer BAUD = 115_200
) (
    input wire clk, rst, rx,
    output reg [7:0] data,
    output reg valid
);
    localparam integer PERIOD = CLOCK_HZ / BAUD;
    localparam integer CW = $clog2(PERIOD);
    reg rx_meta, rx_sync;
    reg [CW-1:0] count;
    reg [3:0] bit_no;
    reg [7:0] shift;
    reg [1:0] state;
    localparam IDLE=2'd0, START=2'd1, BITS=2'd2, STOP=2'd3;

    always @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
        valid <= 1'b0;
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            count <= 0;
            bit_no <= 0;
            shift <= 0;
            data <= 0;
            state <= IDLE;
        end else case (state)
            IDLE: if (!rx_sync) begin count <= PERIOD/2 - 1; state <= START; end
            START: if (count != 0) count <= count - 1'b1;
                   else if (!rx_sync) begin
                       count <= PERIOD - 1; bit_no <= 0; state <= BITS;
                   end else state <= IDLE; // false start
            BITS: if (count != 0) count <= count - 1'b1;
                  else begin
                      shift[bit_no] <= rx_sync;
                      count <= PERIOD - 1;
                      if (bit_no == 7) state <= STOP;
                      else bit_no <= bit_no + 1'b1;
                  end
            STOP: if (count != 0) count <= count - 1'b1;
                  else begin
                      if (rx_sync) begin data <= shift; valid <= 1'b1; end
                      state <= IDLE;
                  end
            default: state <= IDLE;
        endcase
    end
endmodule
`default_nettype wire
