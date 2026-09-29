`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// Small reference SoC: RV32I core + unified memory + UART MMIO + timer MMIO
// -----------------------------------------------------------------------------
// Address map
//   0x0000_0000 .. MEM_WORDS*4-1 : unified instruction/data memory
//   0x1000_0000                  : UART TX data (write low byte)
//   0x1000_0004                  : UART TX ready (read bit 0)
//   0x1000_1000                  : mtime low 32 bits
//   0x1000_1004                  : mtimecmp low 32 bits
//
// CPU에는 instruction/data port가 따로 있지만 둘 다 같은 mem array를 접근하는
// Harvard-interface/unified-storage 구조다. 두 조합식 read port와 byte write enable
// 때문에 Nexys A7의 현재 single-cycle 구현에서는 block RAM이 아니라 distributed
// RAM으로 합성된다.
// -----------------------------------------------------------------------------
module rv32_soc #(
    // Memory capacity in 32-bit words. Nexys top은 2048 words = 8 KiB를 사용한다.
    parameter MEM_WORDS = 16384,
    // 비어 있지 않으면 synthesis/simulation 시작 시 $readmemh image를 적재한다.
    parameter MEM_HEX = ""
) (
    input  wire       clk,
    input  wire       rst,
    // UART producer handshake. valid는 이 clock domain에서 한 cycle pulse다.
    input  wire       uart_tx_ready,
    output reg  [7:0] uart_tx_data,
    output reg        uart_tx_valid,
    output wire [31:0] debug_pc
);
    // Unified little-endian word memory. Byte ordering은 write strobe에서 명시된다.
    reg [31:0] mem [0:MEM_WORDS-1];
    integer i;
    // FPGA configuration 시 firmware image를 memory 초기값으로 사용한다. 먼저 전체를
    // 0으로 채워 HEX 파일 뒤쪽의 사용하지 않는 공간도 deterministic하게 만든다.
    initial begin
        for (i=0; i<MEM_WORDS; i=i+1) mem[i]=32'd0;  // 초기화
        if (MEM_HEX != "") $readmemh(MEM_HEX, mem);  // HEX 파일 적재
    end

    // Core-facing instruction/data buses.
    wire [31:0] iaddr, daddr, dwdata;
    wire [3:0] dwstrb;  // write strobe: 4'b0001=byte0, 4'b0010=byte1, 4'b0100=byte2, 4'b1000=byte3

    localparam MEM_BYTES = MEM_WORDS * 4;
    wire imem_sel = (iaddr < MEM_BYTES);    // instruction fetch는 unified memory만 허용한다.
    wire dmem_sel = (daddr < MEM_BYTES);    // data access는 unified memory + MMIO를 허용한다.

    // instruction address는 byte address이므로 [15:2]로 word index를 만든다.
    // 범위 밖 fetch에는 ADDI x0,x0,0(NOP)을 반환해 X propagation을 막는다.
    wire [31:0] irdata = imem_sel ? mem[iaddr[15:2]] : 32'h0000_0013;
    reg [31:0] drdata;  // data read mux output. MMIO는 아래에서 선택한다.

    // 0x1000_1xxx page 전체를 timer peripheral로 decode한다. Timer 내부에서는
    // address bit 2가 mtime과 mtimecmp를 선택한다.
    wire timer_sel = (daddr[31:12] == 20'h10001);
    wire timer_wr = timer_sel && (|dwstrb);
    wire [31:0] timer_rdata;
    wire timer_irq;

    // Timer IRQ는 core의 machine timer interrupt 입력으로 직접 연결된다.
    simple_timer timer (
        .clk(clk), .rst(rst), .wr_en(timer_wr), .addr(daddr[2:0]),
        .wr_data(dwdata), .rd_data(timer_rdata), .irq(timer_irq)
    );

    // Data read mux. 선택되지 않은/unmapped address는 0을 반환한다.
    always @* begin
        if (dmem_sel) drdata = mem[daddr[15:2]];                            // unified memory; MEM_WORDS가 실제 RAM 범위를 결정한다.
        else if (daddr == 32'h1000_0004) drdata = {31'd0, uart_tx_ready};   // UART TX ready register
        else if (timer_sel) drdata = timer_rdata;                           // Timer MMIO
        else drdata = 32'd0;
    end

    // MMIO와 RAM write는 clock edge에서 commit된다. uart_tx_valid는 기본적으로 매
    // cycle 0이며 accepted UART write가 있을 때만 정확히 한 cycle 동안 1이 된다.
    always @(posedge clk) begin
        uart_tx_valid <= 1'b0;
        if (!rst) begin
            // ready=0일 때 UART write는 받아들이지 않는다. Firmware는 ready register를
            // polling하므로 정상 사용에서는 data가 유실되지 않는다.
            if ((daddr == 32'h1000_0000) && (|dwstrb) && uart_tx_ready) begin
                uart_tx_data <= dwdata[7:0];
                uart_tx_valid <= 1'b1;
            end
            // Little-endian byte write enables: lane 0은 address+0의 least byte다.
            if (dmem_sel && (|dwstrb)) begin
                if (dwstrb[0]) mem[daddr[15:2]][7:0]   <= dwdata[7:0];
                if (dwstrb[1]) mem[daddr[15:2]][15:8]  <= dwdata[15:8];
                if (dwstrb[2]) mem[daddr[15:2]][23:16] <= dwdata[23:16];
                if (dwstrb[3]) mem[daddr[15:2]][31:24] <= dwdata[31:24];
            end
        end
    end

    // Processor core. trap_taken은 현재 SoC 외부에서 사용하지 않아 open 처리한다.
    rv32_core cpu (
        .clk(clk), .rst(rst),   // clock and reset
        .imem_addr(iaddr),      // instruction fetch address
        .imem_rdata(irdata),    // instruction fetch data
        .dmem_addr(daddr),      // data access address
        .dmem_wdata(dwdata),    // data write data
        .dmem_wstrb(dwstrb),    // data write strobe. dwstrb[0] = byte0, dwstrb[1] = byte1, dwstrb[2] = byte2, dwstrb[3] = byte3
        .dmem_rdata(drdata),    // data read data
        .timer_irq(timer_irq),  // machine timer interrupt
        .debug_pc(debug_pc),    // debug PC output for waveform inspection
        .trap_taken()           // trap_taken output is not used in this SoC
    );
endmodule

`default_nettype wire
