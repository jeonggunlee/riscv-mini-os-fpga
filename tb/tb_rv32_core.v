`timescale 1ns/1ps
`default_nettype none

module tb_rv32_core;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    wire [31:0] pc;
    wire [7:0] uart_data;
    wire uart_valid;
    rv32_soc #(.MEM_WORDS(256)) dut (
        .clk(clk), .rst(rst), .uart_tx_ready(1'b1),
        .uart_rx_data(8'd0), .uart_rx_valid(1'b0), .uart_tx_data(uart_data),
        .uart_tx_valid(uart_valid), .debug_pc(pc)
    );

    initial begin
        // Arithmetic, RAM store/load, branch, byte lanes, and UART smoke test.
        dut.mem[0]  = 32'h00500093; // addi x1,x0,5
        dut.mem[1]  = 32'h00700113; // addi x2,x0,7
        dut.mem[2]  = 32'h002081b3; // add  x3,x1,x2 (=12)
        dut.mem[3]  = 32'h08302023; // sw   x3,128(x0)
        dut.mem[4]  = 32'h08002203; // lw   x4,128(x0)
        dut.mem[5]  = 32'h00320463; // beq  x4,x3,+8
        dut.mem[6]  = 32'h00100293; // addi x5,x0,1 (skipped)
        dut.mem[7]  = 32'h02a00293; // addi x5,x0,42
        dut.mem[8]  = 32'h05500313; // addi x6,x0,'U'
        dut.mem[9]  = 32'h100003b7; // lui  x7,0x10000
        dut.mem[10] = 32'h00638023; // sb   x6,0(x7) (UART)
        dut.mem[11] = 32'h0000006f; // jal  x0,0
        #22 rst=0;
        repeat (20) @(posedge clk);
        if (dut.mem[32] !== 32'd12) begin $display("FAIL RAM: %h",dut.mem[32]); $fatal; end
        if (dut.cpu.rf.regs[5] !== 32'd42) begin $display("FAIL BRANCH"); $fatal; end
        if (uart_data !== 8'h55) begin $display("FAIL UART: %h",uart_data); $fatal; end
        $display("PASS: RV32I smoke test");
        $finish;
    end
endmodule

`default_nettype wire
