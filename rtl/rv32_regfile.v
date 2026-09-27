`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// RV32I integer register file: 2 asynchronous read ports, 1 synchronous write
// -----------------------------------------------------------------------------
// Architectural registers x0..x31 중 x1..x31만 실제 storage로 구현한다. x0 read는
// 항상 0이고 x0 write는 무시된다. 두 source operand는 조합식으로 읽고 destination
// register는 rising edge에서 기록하므로 single-cycle core에 필요한 2R1W 구조다.
//
// Reset 시 x1..x31도 0으로 초기화한다. RISC-V ISA가 reset register 값을 요구하는
// 것은 아니지만 simulation의 X 전파를 막고 교육용 FPGA 동작을 deterministic하게
// 만들기 위한 선택이다.
// -----------------------------------------------------------------------------
module rv32_regfile (
    input  wire        clk,
    input  wire        rst,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    input  wire        rd_we,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);
    // x0를 배열에서 제외하여 물리적인 storage가 만들어지지 않게 한다.
    reg [31:0] regs [1:31];
    integer i; // reset loop의 elaboration/simulation index

    // 같은 cycle에 write하는 주소를 read하더라도 별도 bypass는 없다. 이 core에서는
    // 이전 명령 write와 다음 명령 read가 clock edge를 사이에 두므로 문제가 없다.
    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : regs[rs2_addr];

    // Synchronous active-high reset. rd_we가 1이어도 rd_addr=0이면 write를 버린다.
    always @(posedge clk) begin
        if (rst) begin
            for (i = 1; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (rd_we && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end
endmodule

`default_nettype wire
