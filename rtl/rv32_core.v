`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// Single-cycle RV32I processor core
// -----------------------------------------------------------------------------
// 이 모듈은 RV32I 정수 명령어와 최소한의 M-mode CSR/trap 기능을 구현한다.
// fetch, decode, register read, execute, memory access, write-back이 모두 하나의
// 조합 경로에 있으며, 정상 명령어는 다음 rising edge에서 한 번에 retire된다.
//
// Memory interface contract
//   * imem_addr에는 현재 PC가 항상 출력된다.
//   * imem_rdata와 dmem_rdata는 같은 cycle 안에 조합식으로 응답해야 한다.
//   * dmem_addr는 byte address지만 dmem_rdata는 그 주소가 속한 aligned 32-bit
//     word이다. address[1:0]을 이용한 byte/halfword 선택은 core가 수행한다.
//   * dmem_wstrb[n]은 dmem_wdata의 byte lane n이 유효함을 의미한다.
//   * ready/valid 또는 wait-state가 없으므로 느린 memory에는 직접 연결할 수 없다.
//
// Architectural assumptions and limitations
//   * instruction은 32-bit aligned, load/store는 자연 정렬되었다고 가정한다.
//   * misalignment/access-fault trap, EBREAK, U-mode, MMU는 구현하지 않는다.
//   * mtvec는 direct mode만 사용하며 timer interrupt는 machine timer cause 7이다.
//   * interrupt 또는 exception이 선택되면 현재 명령의 register/CSR/memory write를
//     억제하고 PC를 mtvec로 변경한다.
// -----------------------------------------------------------------------------
module rv32_core #(
    // Reset 해제 후 최초로 fetch할 byte address.
    parameter RESET_PC = 32'h0000_0000
) (
    // Clock과 synchronous active-high reset.
    input  wire        clk,
    input  wire        rst,

    // Combinational instruction-memory read port.
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    // Combinational data-memory read / synchronous byte-enable write port.
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    input  wire [31:0] dmem_rdata,

    // Level-sensitive machine timer interrupt request.
    input  wire        timer_irq,

    // FPGA 관측 및 testbench 확인을 위한 debug 출력.
    output wire [31:0] debug_pc,
    output wire        trap_taken
);
    // rv32_alu.v와 공유하는 내부 ALU operation encoding.
    localparam ALU_ADD=4'd0, ALU_SUB=4'd1, ALU_SLL=4'd2, ALU_SLT=4'd3,
               ALU_SLTU=4'd4, ALU_XOR=4'd5, ALU_SRL=4'd6, ALU_SRA=4'd7,
               ALU_OR=4'd8, ALU_AND=4'd9;

    // -------------------------------------------------------------------------
    // Instruction fields and architectural state
    // -------------------------------------------------------------------------
    reg [31:0] pc;                    // 현재 instruction의 byte address
    wire [31:0] insn = imem_rdata;
    wire [6:0] opcode = insn[6:0];
    wire [2:0] funct3 = insn[14:12];
    wire [6:0] funct7 = insn[31:25];
    wire [4:0] rs1 = insn[19:15], rs2 = insn[24:20], rd = insn[11:7];
    wire [31:0] rs1_data, rs2_data;   // register-file 조합식 read 결과
    reg rd_we;                         // rising edge에서 rd를 쓸 때 1
    reg [31:0] rd_data, next_pc;       // write-back 값과 다음 정상 PC

    // ALU 입력과 operation 선택. alu_y는 조합식 결과다.
    reg [3:0] alu_op;
    reg [31:0] alu_a, alu_b;
    wire [31:0] alu_y;
    // Data-memory 요청. write strobe가 0000이면 read-only/no-write이다.
    reg [31:0] daddr_r, dwdata_r;
    reg [3:0] dwstrb_r;

    // Decode 중 발견한 synchronous exception과 MRET 제어 신호.
    reg illegal, exception, do_mret;
    reg [31:0] exception_cause;

    // CSR instruction의 write-back 요청과 새 CSR 값.
    reg csr_we;
    reg [11:0] csr_waddr;
    reg [31:0] csr_wdata;
    // Address 하위 비트만큼 memory word를 이동시킨 byte/halfword load 값.
    reg [31:0] load_shifted;
    wire [31:0] csr_rdata, csr_mtvec, csr_mepc;
    wire csr_valid;     // CSR read data가 유효하면 1. instruction[31:20]이 CSR 주소로 decode되면 1.
    wire irq_pending;   // CSR block이 timer_irq를 보고 interrupt가 pending이면 1

    // Interrupt가 exception보다 우선한다. trap을 받는 cycle에는 현재 instruction이
    // retire되지 않으며 mepc에는 현재 pc가 저장된다.
    wire take_trap = irq_pending || exception;  // trap 진입 여부
    wire [31:0] trap_cause = irq_pending ? 32'h8000_0007 : exception_cause;  // interrupt cause 7, exception cause는 decode에서 결정
                                                                             // CSR block이 mepc/mcause/mstatus를 갱신하고, MRET 시 interrupt enable을 복구한다.

    // -------------------------------------------------------------------------
    // External interface and architectural side-effect gating
    // -------------------------------------------------------------------------
    assign imem_addr = pc;
    assign dmem_addr = daddr_r;
    assign dmem_wdata = dwdata_r;
    // Trap이 같은 cycle에 선택되면 잘못된 store가 발생하지 않도록 byte enable을 제거한다.
    assign dmem_wstrb = take_trap ? 4'b0000 : dwstrb_r;
    assign debug_pc = pc;
    assign trap_taken = take_trap;

    // x0는 항상 0이며 실제 write는 register-file 내부에서도 x0에 대해 무시된다.
    // take_trap gating은 faulting/interrupted instruction의 write-back을 막는다.
    rv32_regfile rf (
        .clk(clk), .rst(rst), .rs1_addr(rs1), .rs2_addr(rs2),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .rd_we(rd_we && !take_trap), .rd_addr(rd), .rd_data(rd_data)
    );

    // ALU는 combinational으로 동작하며, ALU operation과 두 operand를 입력받아 결과를 출력한다.
    rv32_alu alu (.op(alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

    // CSR block은 trap 진입 시 mepc/mcause/mstatus를 갱신하고, MRET 시 interrupt
    // enable을 복구한다. CSR 주소는 instruction[31:20]에 직접 들어 있다.
    rv32_csr csr (
        .clk(clk), .rst(rst), .read_addr(insn[31:20]),
        .read_data(csr_rdata), .read_valid(csr_valid),
        .write_en(csr_we && !take_trap), .write_addr(csr_waddr), .write_data(csr_wdata),
        .trap_enter(take_trap), .trap_pc(pc), .trap_cause(trap_cause),
        .mret(do_mret && !take_trap), .timer_irq(timer_irq),
        .irq_pending(irq_pending), .mtvec(csr_mtvec), .mepc(csr_mepc)
    );

    // -------------------------------------------------------------------------
    // Immediate reconstruction
    // B/J immediate의 bit 0은 instruction alignment 때문에 항상 0이다. I/S/B/J
    // immediate는 bit 31을 복제하여 32-bit signed value로 sign extension한다.
    // -------------------------------------------------------------------------
    function [31:0] imm_i; input [31:0] x; imm_i={{20{x[31]}},x[31:20]}; endfunction
    function [31:0] imm_s; input [31:0] x; imm_s={{20{x[31]}},x[31:25],x[11:7]}; endfunction
    function [31:0] imm_b; input [31:0] x; imm_b={{19{x[31]}},x[31],x[7],x[30:25],x[11:8],1'b0}; endfunction
    function [31:0] imm_u; input [31:0] x; imm_u={x[31:12],12'd0}; endfunction
    function [31:0] imm_j; input [31:0] x; imm_j={{11{x[31]}},x[31],x[19:12],x[20],x[30:21],1'b0}; endfunction

    // -------------------------------------------------------------------------
    // Main combinational decode / execute / memory / write-back logic
    // -------------------------------------------------------------------------
    // 모든 출력에 먼저 안전한 기본값을 주어 latch inference를 막는다. 가장 일반적인
    // 경우는 PC+4, register/memory/CSR write 없음이다. 각 opcode case가 필요한
    // 제어와 결과만 override한다.
    always @* begin
        rd_we = 1'b0; rd_data = 32'd0; next_pc = pc + 32'd4;
        alu_op = ALU_ADD; alu_a = rs1_data; alu_b = rs2_data;
        daddr_r = 32'd0; dwdata_r = 32'd0; dwstrb_r = 4'd0; load_shifted = 32'd0;
        illegal = 1'b0; exception = 1'b0; exception_cause = 32'd0;
        do_mret = 1'b0; csr_we = 1'b0; csr_waddr = insn[31:20]; csr_wdata = 32'd0;

        case (opcode)
            // U-type: upper immediate를 그대로 쓰거나 현재 PC에 더한다.
            7'b0110111: begin rd_we=1'b1; rd_data=imm_u(insn); end // LUI
            7'b0010111: begin rd_we=1'b1; rd_data=pc+imm_u(insn); end // AUIPC

            // JAL은 return address(PC+4)를 rd에 쓰고 PC-relative target으로 이동한다.
            7'b1101111: begin rd_we=1'b1; rd_data=pc+4; next_pc=pc+imm_j(insn); end

            // JALR target의 bit 0은 ISA 규칙에 따라 항상 0으로 만든다.
            7'b1100111: begin
                if (funct3 != 3'b000) illegal=1'b1;
                else begin rd_we=1'b1; rd_data=pc+4; next_pc=(rs1_data+imm_i(insn))&32'hffff_fffe; end
            end
            // Conditional branches. signed/unsigned 비교를 명시적으로 구분한다.
            7'b1100011: begin
                case (funct3)
                    3'b000: if (rs1_data == rs2_data) next_pc=pc+imm_b(insn);
                    3'b001: if (rs1_data != rs2_data) next_pc=pc+imm_b(insn);
                    3'b100: if ($signed(rs1_data) < $signed(rs2_data)) next_pc=pc+imm_b(insn);
                    3'b101: if ($signed(rs1_data) >= $signed(rs2_data)) next_pc=pc+imm_b(insn);
                    3'b110: if (rs1_data < rs2_data) next_pc=pc+imm_b(insn);
                    3'b111: if (rs1_data >= rs2_data) next_pc=pc+imm_b(insn);
                    default: illegal=1'b1;
                endcase
            end
            // LOAD: effective address를 만든 뒤 aligned word를 address offset만큼
            // right shift한다. LB/LH는 sign extension, LBU/LHU는 zero extension한다.
            // 자연 정렬을 가정하므로 LW에는 별도 shift가 필요하지 않다.
            7'b0000011: begin
                daddr_r=rs1_data+imm_i(insn); rd_we=1'b1;
                load_shifted=dmem_rdata >> (8*daddr_r[1:0]);
                case (funct3)
                    3'b000: rd_data={{24{load_shifted[7]}},load_shifted[7:0]};
                    3'b001: rd_data={{16{load_shifted[15]}},load_shifted[15:0]};
                    3'b010: rd_data=dmem_rdata;
                    3'b100: rd_data={24'd0,load_shifted[7:0]};
                    3'b101: rd_data={16'd0,load_shifted[15:0]};
                    default: begin illegal=1'b1; rd_we=1'b0; end
                endcase
            end
            // STORE: address[1:0]으로 byte enable lane을 고른다. byte/halfword 값을
            // 모든 lane에 복제하면 선택된 lane의 wstrb가 필요한 byte만 기록한다.
            7'b0100011: begin
                daddr_r=rs1_data+imm_s(insn);
                case (funct3)
                    3'b000: begin dwstrb_r=4'b0001 << daddr_r[1:0]; dwdata_r={4{rs2_data[7:0]}}; end
                    3'b001: begin dwstrb_r=4'b0011 << daddr_r[1:0]; dwdata_r={2{rs2_data[15:0]}}; end
                    3'b010: begin dwstrb_r=4'b1111; dwdata_r=rs2_data; end
                    default: illegal=1'b1;
                endcase
            end
            // OP-IMM: 두 번째 ALU operand로 sign-extended I immediate를 사용한다.
            // Shift-immediate는 funct7을 검사해 SRLI/SRAI와 illegal encoding을 구분한다.
            7'b0010011: begin
                rd_we=1'b1; alu_b=imm_i(insn);
                case (funct3)
                    3'b000: alu_op=ALU_ADD; 3'b010: alu_op=ALU_SLT;
                    3'b011: alu_op=ALU_SLTU; 3'b100: alu_op=ALU_XOR;
                    3'b110: alu_op=ALU_OR; 3'b111: alu_op=ALU_AND;
                    3'b001: begin alu_op=ALU_SLL; if (funct7!=7'b0000000) illegal=1'b1; end
                    3'b101: begin
                        if (funct7==7'b0000000) alu_op=ALU_SRL;
                        else if (funct7==7'b0100000) alu_op=ALU_SRA;
                        else illegal=1'b1;
                    end
                endcase
                rd_data=alu_y; if (illegal) rd_we=1'b0;
            end
            // OP: funct7+funct3 조합으로 register-register ALU operation을 선택한다.
            7'b0110011: begin
                rd_we=1'b1;
                case ({funct7,funct3})
                    {7'b0000000,3'b000}: alu_op=ALU_ADD;
                    {7'b0100000,3'b000}: alu_op=ALU_SUB;
                    {7'b0000000,3'b001}: alu_op=ALU_SLL;
                    {7'b0000000,3'b010}: alu_op=ALU_SLT;
                    {7'b0000000,3'b011}: alu_op=ALU_SLTU;
                    {7'b0000000,3'b100}: alu_op=ALU_XOR;
                    {7'b0000000,3'b101}: alu_op=ALU_SRL;
                    {7'b0100000,3'b101}: alu_op=ALU_SRA;
                    {7'b0000000,3'b110}: alu_op=ALU_OR;
                    {7'b0000000,3'b111}: alu_op=ALU_AND;
                    default: illegal=1'b1;
                endcase
                rd_data=alu_y; if (illegal) rd_we=1'b0;
            end
            // 이 단순한 in-order memory system에는 outstanding transaction이 없으므로
            // FENCE는 NOP로 처리한다. 다른 MISC-MEM encoding은 illegal이다.
            7'b0001111: begin if (funct3!=3'b000) illegal=1'b1; end

            // SYSTEM opcode:
            //   funct3=000 : ECALL 또는 MRET처럼 register operand가 없는 명령
            //   funct3!=000: CSR read-modify-write 명령
            // CSR instruction은 항상 이전 CSR 값을 rd에 반환한다. CSRRS/CSRRC 계열은
            // source가 x0/zimm=0이면 CSR write를 하지 않는 read-only access가 된다.
            7'b1110011: begin
                if (funct3 == 3'b000) begin
                    // ECALL from M-mode: synchronous exception cause 11.
                    if (insn == 32'h0000_0073) begin exception=1'b1; exception_cause=32'd11; end
                    // MRET: CSR block이 mstatus를 복구하고 next PC는 mepc가 된다.
                    else if (insn == 32'h3020_0073) begin do_mret=1'b1; next_pc=csr_mepc; end
                    else illegal=1'b1;
                end else begin
                    if (!csr_valid) illegal=1'b1;
                    else begin
                        rd_we=1'b1; rd_data=csr_rdata;
                        case (funct3)
                            // CSRRW / CSRRS / CSRRC use rs1_data.
                            3'b001: begin csr_we=1'b1; csr_wdata=rs1_data; end
                            3'b010: begin csr_we=(rs1!=0); csr_wdata=csr_rdata|rs1_data; end
                            3'b011: begin csr_we=(rs1!=0); csr_wdata=csr_rdata&~rs1_data; end
                            // Immediate variants use the encoded rs1 field as 5-bit zimm.
                            3'b101: begin csr_we=1'b1; csr_wdata={27'd0,rs1}; end
                            3'b110: begin csr_we=(rs1!=0); csr_wdata=csr_rdata|{27'd0,rs1}; end
                            3'b111: begin csr_we=(rs1!=0); csr_wdata=csr_rdata&~{27'd0,rs1}; end
                            default: begin illegal=1'b1; csr_we=1'b0; rd_we=1'b0; end
                        endcase
                    end
                end
            end
            // 알 수 없는 major opcode는 illegal-instruction exception으로 변환한다.
            default: illegal=1'b1;
        endcase

        // Illegal instruction cause는 2이다. 이미 만들어졌을 수 있는 모든 side
        // effect를 제거하여 faulting instruction이 architectural state를 바꾸지 못한다.
        if (illegal) begin exception=1'b1; exception_cause=32'd2; csr_we=1'b0; rd_we=1'b0; dwstrb_r=4'd0; end
    end

    // -------------------------------------------------------------------------
    // PC state update
    // -------------------------------------------------------------------------
    // Priority: reset > trap > normal sequential/branch/jump/MRET next_pc.
    // Register file, CSR, memory write도 같은 rising edge에서 commit된다.
    always @(posedge clk) begin
        if (rst) pc <= RESET_PC;
        else if (take_trap) pc <= csr_mtvec;
        else pc <= next_pc;
    end
endmodule

`default_nettype wire
