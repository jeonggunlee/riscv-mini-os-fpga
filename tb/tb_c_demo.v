`timescale 1ns/1ps
`default_nettype none

// End-to-end test of the image generated from firmware/c_demo.c.
module tb_c_demo;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    wire [7:0] uart_data;
    wire uart_valid;
    wire [31:0] debug_pc;

    // Explicit waveform probes for the C summation result. The compiler keeps
    // sum in x15(a5) and loop variable i in x14(a4) until the SW at PC=0x2c.
    // signature_value mirrors RAM word 0x400 and therefore changes to 55 when
    // signature_write is asserted.
    wire [31:0] sum_x15 = dut.cpu.rf.regs[15];
    wire [31:0] loop_i_x14 = dut.cpu.rf.regs[14];
    wire        signature_write =
        (dut.cpu.dmem_addr == 32'h0000_0400) && (|dut.cpu.dmem_wstrb);
    wire [31:0] signature_write_data = dut.cpu.dmem_wdata;
    wire [3:0]  signature_write_strobe = dut.cpu.dmem_wstrb;
    wire [31:0] signature_value = dut.mem[32'h400 >> 2];

    reg [7:0] received [0:4];
    integer received_count = 0;
    integer i;

    // Generate a compact waveform for VS Code/GTKWave. Dump the CPU hierarchy
    // and the SoC-level UART/control signals, but not the full 8 KiB mem array.
    initial begin
        $dumpfile("build/c_demo.vcd");
        $dumpvars(0, tb_c_demo.dut.cpu);
        $dumpvars(0, tb_c_demo.clk);
        $dumpvars(0, tb_c_demo.rst);
        $dumpvars(0, tb_c_demo.uart_data);
        $dumpvars(0, tb_c_demo.uart_valid);
        $dumpvars(0, tb_c_demo.debug_pc);
        $dumpvars(0, tb_c_demo.received_count);
        $dumpvars(0, tb_c_demo.sum_x15);
        $dumpvars(0, tb_c_demo.loop_i_x14);
        $dumpvars(0, tb_c_demo.signature_write);
        $dumpvars(0, tb_c_demo.signature_write_data);
        $dumpvars(0, tb_c_demo.signature_write_strobe);
        $dumpvars(0, tb_c_demo.signature_value);
    end

    rv32_soc #(
        .MEM_WORDS(2048),
        .MEM_HEX("firmware/c_demo.hex")
    ) dut (
        .clk(clk),
        .rst(rst),
        .uart_tx_ready(1'b1),
        .uart_rx_data(8'd0), .uart_rx_valid(1'b0),
        .uart_tx_data(uart_data),
        .uart_tx_valid(uart_valid),
        .debug_pc(debug_pc)
    );

    always @(posedge clk) begin
        if (uart_valid && received_count < 5) begin
            received[received_count] <= uart_data;
            received_count <= received_count + 1;
        end
    end

    initial begin
        for (i = 0; i < 5; i = i + 1)
            received[i] = 8'd0;

        #22 rst = 1'b0;
        repeat (1000) @(posedge clk);

        if (dut.mem[32'h400 >> 2] !== 32'd55) begin
            $display("FAIL: signature=%0d, expected=55", dut.mem[32'h400 >> 2]);
            $fatal;
        end
        if (received_count !== 5 ||
            received[0] !== "C" || received[1] !== " " ||
            received[2] !== "O" || received[3] !== "K" ||
            received[4] !== 8'h0a) begin
            $display("FAIL: UART byte count=%0d", received_count);
            $fatal;
        end

        $display("PASS: C firmware signature=55, UART=\"C OK\\n\"");
        $finish;
    end
endmodule

`default_nettype wire
