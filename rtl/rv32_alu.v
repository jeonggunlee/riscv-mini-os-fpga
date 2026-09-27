`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// RV32I combinational arithmetic/logic unit
// -----------------------------------------------------------------------------
// 두 32-bit operand와 core가 생성한 4-bit operation code를 받아 같은 cycle에
// 결과를 만든다. 상태를 저장하지 않으며 clock/reset도 필요하지 않다.
//
// 주의할 점
//   * RISC-V shift amount는 RV32에서 하위 5 bit만 사용한다(0..31).
//   * SLT와 SRA는 signed 해석이 필요하므로 $signed cast를 명시한다.
//   * SLTU와 SRL은 Verilog의 기본 unsigned 연산을 사용한다.
//   * 비교 결과는 32-bit 0 또는 1이다.
// -----------------------------------------------------------------------------
module rv32_alu (
    // Operation encoding은 rv32_core.v의 localparam과 동일해야 한다.
    input  wire [3:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] y
);
    // ISA opcode가 아니라 core 내부에서만 사용하는 compact ALU encoding이다.
    localparam ALU_ADD  = 4'd0, ALU_SUB = 4'd1,
               ALU_SLL  = 4'd2, ALU_SLT = 4'd3,
               ALU_SLTU = 4'd4, ALU_XOR = 4'd5,
               ALU_SRL  = 4'd6, ALU_SRA = 4'd7,
               ALU_OR   = 4'd8, ALU_AND = 4'd9;

    // 모든 case에서 y를 할당하므로 latch가 생성되지 않는다. 정의되지 않은 op는
    // deterministic한 0을 반환하지만 정상 decode에서는 이 경로를 사용하지 않는다.
    always @* begin
        case (op)
            ALU_ADD:  y = a + b;
            ALU_SUB:  y = a - b;
            // Shift 연산은 b 전체가 아니라 ISA가 규정한 shamt[4:0]만 사용한다.
            ALU_SLL:  y = a << b[4:0];
            // Signed less-than와 unsigned less-than를 분리한다.
            ALU_SLT:  y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU: y = (a < b) ? 32'd1 : 32'd0;
            ALU_XOR:  y = a ^ b;
            ALU_SRL:  y = a >> b[4:0];
            // >>>만으로는 왼쪽 operand가 unsigned일 수 있어 $signed가 필요하다.
            ALU_SRA:  y = $signed(a) >>> b[4:0];
            ALU_OR:   y = a | b;
            ALU_AND:  y = a & b;
            default:  y = 32'd0;
        endcase
    end
endmodule

`default_nettype wire
