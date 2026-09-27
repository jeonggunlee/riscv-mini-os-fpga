`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// Minimal RISC-V machine-mode CSR and trap state
// -----------------------------------------------------------------------------
// Mini OS의 ECALL/MRET와 machine timer interrupt에 필요한 CSR만 구현한다. 전체
// privileged specification 구현이 아니며 M-mode만 존재한다.
//
// Implemented writable state
//   0x300 mstatus  : MIE(bit 3), MPIE(bit 7)만 구현
//   0x304 mie      : MTIE(bit 7)만 구현
//   0x305 mtvec    : direct mode, 4-byte aligned base
//   0x340 mscratch : 32-bit software scratch value
//   0x341 mepc     : 4-byte aligned return PC
//   0x342 mcause   : last trap cause
//   0x344 mip      : MTIP(bit 7)을 timer_irq에서 실시간 생성(read-only)
//
// Trap entry가 일반 CSR write보다 우선하고, trap entry가 MRET보다도 우선한다.
// -----------------------------------------------------------------------------
module rv32_csr (
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] read_addr,
    output reg  [31:0] read_data,
    output reg         read_valid,
    input  wire        write_en,
    input  wire [11:0] write_addr,
    input  wire [31:0] write_data,
    input  wire        trap_enter,
    input  wire [31:0] trap_pc,
    input  wire [31:0] trap_cause,
    input  wire        mret,
    input  wire        timer_irq,
    output wire        irq_pending,
    output wire [31:0] mtvec,
    output wire [31:0] mepc
);
    // CSR storage. mip는 외부 interrupt level로부터 조합식 생성하므로 storage가 없다.
    reg [31:0] mstatus_r, mie_r, mtvec_r, mscratch_r, mepc_r, mcause_r;

    // 이 RV32I core는 32-bit instruction만 지원하므로 trap/return PC를 4-byte 정렬한다.
    assign mtvec = {mtvec_r[31:2], 2'b00}; // direct mode only
    assign mepc = {mepc_r[31:2], 2'b00};
    // Machine timer interrupt는 global MIE, local MTIE, external level이 모두 1일 때 pending.
    assign irq_pending = mstatus_r[3] && mie_r[7] && timer_irq;

    // CSR read는 single-cycle datapath를 위한 combinational port다. read_valid=0이면
    // core가 해당 SYSTEM instruction을 illegal instruction으로 처리한다.
    always @* begin
        read_valid = 1'b1;
        case (read_addr)
            12'h300: read_data = mstatus_r;
            12'h304: read_data = mie_r;
            12'h305: read_data = mtvec_r;
            12'h340: read_data = mscratch_r;
            12'h341: read_data = mepc_r;
            12'h342: read_data = mcause_r;
            // mip.MTIP는 timer_irq level을 그대로 반영하며 CSR write로 변경할 수 없다.
            12'h344: read_data = timer_irq ? 32'h0000_0080 : 32'd0;
            // ID CSR은 존재하지만 구현 고유 ID를 할당하지 않아 0을 반환한다.
            12'hF11: read_data = 32'd0;          // mvendorid
            12'hF12: read_data = 32'd0;          // marchid
            12'hF13: read_data = 32'd0;          // mimpid
            12'hF14: read_data = 32'd0;          // mhartid
            default: begin read_data = 32'd0; read_valid = 1'b0; end
        endcase
    end

    // CSR state update. Reset 후 interrupt는 disable되고 trap vector는 address 0이다.
    always @(posedge clk) begin
        if (rst) begin
            mstatus_r  <= 32'd0;
            mie_r      <= 32'd0;
            mtvec_r    <= 32'd0;
            mscratch_r <= 32'd0;
            mepc_r     <= 32'd0;
            mcause_r   <= 32'd0;
        end else begin
            // Software CSR write. 구현하지 않은/reserved bit는 mask하거나 무시한다.
            if (write_en) begin
                case (write_addr)
                    // mstatus에서는 MIE(3)와 MPIE(7)만 writable이다.
                    12'h300: mstatus_r  <= (mstatus_r & ~32'h0000_0088) |
                                              (write_data & 32'h0000_0088);
                    12'h304: mie_r      <= write_data & 32'h0000_0080;
                    12'h305: mtvec_r    <= {write_data[31:2], 2'b00};
                    12'h340: mscratch_r <= write_data;
                    12'h341: mepc_r     <= {write_data[31:2], 2'b00};
                    12'h342: mcause_r   <= write_data;
                    default: ;
                endcase
            end
            // Trap entry:
            //   mepc   <- interrupted/faulting instruction PC
            //   mcause <- exception 또는 interrupt cause
            //   MPIE   <- 이전 MIE, MIE <- 0 (handler 동안 nested IRQ 방지)
            if (trap_enter) begin
                mepc_r       <= trap_pc;
                mcause_r     <= trap_cause;
                mstatus_r[7] <= mstatus_r[3]; // MPIE <- MIE
                mstatus_r[3] <= 1'b0;         // MIE <- 0
            // MRET는 saved MPIE를 MIE로 복구하고 MPIE를 1로 만든다. PC 복귀 자체는
            // rv32_core가 mepc output을 next_pc로 선택하여 수행한다.
            end else if (mret) begin
                mstatus_r[3] <= mstatus_r[7]; // MIE <- MPIE
                mstatus_r[7] <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
