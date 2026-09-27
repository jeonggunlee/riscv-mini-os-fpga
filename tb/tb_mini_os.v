`timescale 1ns/1ps
`default_nettype none

// End-to-end test of the mini OS image (firmware/boot.S, trap.S, kernel.c).
//
// The simulation image is built with a short timer period so that a run of a
// few tens of thousands of cycles contains many timer interrupts. The test
// records every UART byte and every trap the core takes, then checks that
//   * the boot banner came out first,
//   * timer interrupts happened and no unexpected trap (illegal etc.) did,
//   * all three tasks produced output, so context switching works in both
//     directions and a freshly created frame can be entered via mret,
//   * the output alternates between tasks, i.e. preemption really happened.
module tb_mini_os;
    // Cycles to run after reset. ~2000-cycle ticks -> a few dozen slices.
    localparam integer RUN_CYCLES = 80000;
    localparam integer RX_MAX = 4096;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    wire [7:0] uart_data;
    wire uart_valid;
    wire [31:0] debug_pc;

    // Probes that are useful in the waveform viewer.
    wire [31:0] sp_x2      = dut.cpu.rf.regs[2];
    wire [31:0] mepc       = dut.cpu.csr.mepc_r;
    wire [31:0] mcause     = dut.cpu.csr.mcause_r;
    wire        mie_bit    = dut.cpu.csr.mstatus_r[3];
    wire        timer_irq  = dut.timer_irq;
    wire        take_trap  = dut.cpu.take_trap;
    wire [31:0] trap_cause = dut.cpu.trap_cause;

    initial begin
        $dumpfile("build/mini_os.vcd");
        $dumpvars(0, clk);
        $dumpvars(0, rst);
        $dumpvars(0, debug_pc);
        $dumpvars(0, uart_data);
        $dumpvars(0, uart_valid);
        $dumpvars(0, sp_x2);
        $dumpvars(0, mepc);
        $dumpvars(0, mcause);
        $dumpvars(0, mie_bit);
        $dumpvars(0, timer_irq);
        $dumpvars(0, take_trap);
        $dumpvars(0, trap_cause);
    end

    rv32_soc #(
        .MEM_WORDS(2048),
        .MEM_HEX("build/firmware/mini_os_sim.hex")
    ) dut (
        .clk(clk),
        .rst(rst),
        .uart_tx_ready(1'b1),
        .uart_tx_data(uart_data),
        .uart_tx_valid(uart_valid),
        .debug_pc(debug_pc)
    );

    // UART sink and trap statistics.
    reg [7:0] rx [0:RX_MAX-1];
    integer rx_count = 0;
    integer count_a = 0, count_b = 0, count_c = 0;
    integer switches = 0;          // A/B/C -> different task letter
    reg [7:0] last_letter = 8'd0;
    integer timer_traps = 0, ecall_traps = 0, other_traps = 0;
    integer i;

    always @(posedge clk) begin
        if (uart_valid) begin
            if (rx_count < RX_MAX) rx[rx_count] <= uart_data;
            rx_count <= rx_count + 1;
            if (uart_data == "A") count_a <= count_a + 1;
            if (uart_data == "B") count_b <= count_b + 1;
            if (uart_data == "C") count_c <= count_c + 1;
            if (uart_data == "A" || uart_data == "B" || uart_data == "C") begin
                if (last_letter != 8'd0 && uart_data != last_letter)
                    switches <= switches + 1;
                last_letter <= uart_data;
            end
        end
        if (!rst && take_trap) begin
            if (trap_cause == 32'h8000_0007) timer_traps <= timer_traps + 1;
            else if (trap_cause == 32'd11)   ecall_traps <= ecall_traps + 1;
            else                             other_traps <= other_traps + 1;
        end
    end

    // Expected banner printed by kernel_main before interrupts are enabled.
    localparam integer BANNER_LEN = 13;
    reg [8*BANNER_LEN-1:0] banner = "mini OS boot\n";
    integer banner_ok;

    initial begin
        for (i = 0; i < RX_MAX; i = i + 1)
            rx[i] = 8'd0;

        #22 rst = 1'b0;
        repeat (RUN_CYCLES) @(posedge clk);

        $display("--- UART output (%0d bytes, first 300 shown) ---", rx_count);
        for (i = 0; i < rx_count && i < 300; i = i + 1)
            $write("%c", rx[i]);
        $display("\n--- end of UART output ---");
        $display("timer traps=%0d  ecall traps=%0d  other traps=%0d",
                 timer_traps, ecall_traps, other_traps);
        $display("A=%0d  B=%0d  C=%0d  task switches seen on UART=%0d",
                 count_a, count_b, count_c, switches);

        banner_ok = 1;
        for (i = 0; i < BANNER_LEN; i = i + 1)
            if (rx[i] !== banner[8*(BANNER_LEN-1-i) +: 8]) banner_ok = 0;

        if (!banner_ok) begin
            $display("FAIL: boot banner missing or corrupted");
            $fatal;
        end
        if (other_traps !== 0) begin
            $display("FAIL: %0d unexpected trap(s) (illegal instruction?)", other_traps);
            $fatal;
        end
        if (timer_traps < 8) begin
            $display("FAIL: only %0d timer interrupts", timer_traps);
            $fatal;
        end
        if (count_a == 0 || count_b == 0 || count_c == 0) begin
            $display("FAIL: not every task ran (A=%0d B=%0d C=%0d)", count_a, count_b, count_c);
            $fatal;
        end
        if (switches < 6) begin
            $display("FAIL: only %0d task switches visible on UART", switches);
            $fatal;
        end

        $display("PASS: mini OS boot, %0d timer IRQs, %0d syscalls, tasks A/B/C interleaved",
                 timer_traps, ecall_traps);
        $finish;
    end
endmodule

`default_nettype wire
