`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// Minimal machine timer peripheral
// -----------------------------------------------------------------------------
// 매 clock 증가하는 64-bit mtime과 비교 기준 mtimecmp를 가진다. mtime이
// mtimecmp 이상이면 irq를 level-high로 유지한다. Software는 더 먼 미래 값을
// mtimecmp에 써서 interrupt를 해제하고 다음 tick을 예약한다.
//
// 현재 MMIO interface는 교육용으로 두 register의 하위 32 bit만 노출한다.
//   addr[2]=0 (base + 0): mtime[31:0]
//   addr[2]=1 (base + 4): mtimecmp[31:0]
// 장시간 실행과 완전한 RISC-V timer ABI에는 상위 32-bit register도 추가해야 한다.
// -----------------------------------------------------------------------------
module simple_timer (
    input  wire        clk,
    input  wire        rst,
    input  wire        wr_en,
    input  wire [2:0]  addr,    // 4-byte aligned MMIO address, bit2 selects mtime vs mtimecmp
                                // addr[1:0]은 word-aligned MMIO access를 가정하므로 사용하지 않는다.
    input  wire [31:0] wr_data,
    output reg  [31:0] rd_data,
    output wire        irq
);
    reg [63:0] mtime;     // free-running time counter
    reg [63:0] mtimecmp;  // next interrupt deadline

    // Comparator output은 pulse가 아니라 level이다. compare를 갱신할 때까지 유지된다.
    assign irq = (mtime >= mtimecmp);

    // Address bit 2가 4-byte 간격의 두 32-bit register를 선택한다. addr[1:0]은
    // word-aligned MMIO access를 가정하므로 사용하지 않는다.
    always @* begin
        case (addr[2])  // addr[2]=0: mtime, addr[2]=1: mtimecmp
            1'b0: rd_data = mtime[31:0];
            1'b1: rd_data = mtimecmp[31:0];
        endcase
    end

    // Timer state update. Reset 직후 즉시 IRQ가 걸리지 않도록 low-word compare를
    // 최대값으로 설정한다. 같은 cycle의 software write가 자동 increment보다 우선한다.
    always @(posedge clk) begin
        if (rst) begin
            mtime <= 64'd0;
            mtimecmp <= 64'h0000_0000_ffff_ffff;
        end else begin
            mtime <= mtime + 64'd1;
            // Minimal 32-bit MMIO: low words only, enough for short FPGA demos.
            if (wr_en && !addr[2]) mtime[31:0] <= wr_data;
            if (wr_en &&  addr[2]) mtimecmp[31:0] <= wr_data;
        end
    end
endmodule

`default_nettype wire
