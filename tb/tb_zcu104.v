`timescale 1ns/1ps
`default_nettype none

// Exercise the actual board top, clock divider, reset and UART serializer.
// Only the firmware timer interval is shortened; UART baud is unchanged.
module tb_zcu104;
    reg clk = 0;
    reg reset = 0;                 // also test FPGA INIT / automatic boot
    always #1.667 clk = ~clk;      // board input: ~300 MHz (1 ps resolution)
    wire tx;
    wire [3:0] led;
    zcu104_top #(.MEM_HEX("build/firmware/mini_os_sim.hex")) dut (
        .CLK_300_P(clk), .CLK_300_N(~clk), .CPU_RESET(reset), .UART_RX(1'b1),
        .UART_TX(tx), .LED(led)
    );
    localparam BIT_NS = 8680;      // independent host receiver at ~115200 baud
    reg [7:0] rx [0:1023];
    reg [7:0] byte_data;
    integer received = 0, bit_no;
    integer timers = 0, ecalls = 0;
    reg [103:0] banner = "mini OS boot\n";
    integer a, b, c, transitions, i;
    reg [7:0] last;
    reg [103:0] fs_pass = "[MiniFS] PASS";
    integer fs_match;

    // Decode the external pin, not the internal MMIO byte channel. Sampling
    // with nominal baud also checks integer-divider baud error tolerance.
    initial forever begin
        @(negedge tx);
        #(BIT_NS/2);
        if (tx !== 0) $fatal(1, "Invalid UART start bit");
        for (bit_no=0; bit_no<8; bit_no=bit_no+1) begin
            #BIT_NS;
            byte_data[bit_no] = tx;
        end
        #BIT_NS;
        if (tx !== 1) $fatal(1, "Invalid UART stop bit");
        if (received >= 1024) $fatal(1, "RX buffer overflow");
        rx[received] = byte_data;
        received = received + 1;
    end

    always @(posedge dut.cpu_clk) begin
        if (!dut.rst && dut.soc.cpu.take_trap) begin
            case (dut.soc.cpu.trap_cause)
                32'h80000007: timers = timers + 1;
                32'd11: ecalls = ecalls + 1;
                default: $fatal(1, "Unexpected trap at PC %h", dut.pc);
            endcase
        end
    end

    task check_output;
        begin
            if (received < 20) $fatal(1, "Too few UART bytes: %0d", received);
            for (i=0; i<13; i=i+1)
                if (rx[i] !== banner[8*(12-i) +: 8])
                    $fatal(1, "Boot banner mismatch byte %0d: %h", i, rx[i]);
            a=0; b=0; c=0; transitions=0; last=0; fs_match=0;
            for (i=13; i<received; i=i+1) begin
                if (fs_match < 13 && rx[i] == fs_pass[8*(12-fs_match) +: 8])
                    fs_match=fs_match+1;
                else if (rx[i] != "A" && rx[i] != "B" && rx[i] != "C" && fs_match < 13)
                    fs_match=0;
                case (rx[i])
                    "A": a=a+1;
                    "B": b=b+1;
                    "C": c=c+1;
                    default: begin
                        if (rx[i] != 8'h0a && (rx[i] < 8'h20 || rx[i] > 8'h7e))
                            $fatal(1, "Invalid UART byte %h", rx[i]);
                    end
                endcase
                if (rx[i] == "A" || rx[i] == "B" || rx[i] == "C") begin
                    if (last!=0 && last!=rx[i]) transitions=transitions+1;
                    last=rx[i];
                end
            end
            if (a<3 || b<3 || c<3 || transitions<6 || timers<8 || ecalls<8 || fs_match<13)
                $fatal(1, "Insufficient task/timer/MiniFS activity: fs_match=%0d", fs_match);
            $display("PASS: ZCU104 serial pin: A=%0d B=%0d C=%0d transitions=%0d timer=%0d ecall=%0d",
                     a,b,c,transitions,timers,ecalls);
        end
    endtask

    initial begin
        $dumpfile("build/zcu104_serial.vcd");
        $dumpvars(0, tx, reset, led);
        repeat (700000) @(negedge dut.cpu_clk);
        check_output;
        // Finish the in-flight byte before asserting the warm reset. All
        // three task stacks and task_sp[] must be correctly reinitialized.
        wait (dut.serial.busy && dut.serial.bit_index == 9);
        #(BIT_NS/2);
        reset=1;
        repeat (8) @(negedge dut.cpu_clk);
        received=0; timers=0; ecalls=0;
        reset=0;
        repeat (700000) @(negedge dut.cpu_clk);
        check_output;
        $display("PASS: automatic power-on reset and SW20 warm reset");
        $finish;
    end
    initial begin
        #150_000_000;
        $fatal(1, "Clock/reset/UART simulation timeout");
    end
endmodule
`default_nettype wire
