#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
LOCAL_ROOT="$PROJECT_DIR/build/tools/iverilog"
if command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
    IVERILOG=(iverilog)
    VVP=(vvp)
else
    IVL_LIB="$LOCAL_ROOT/usr/lib/x86_64-linux-gnu/ivl"
    IVERILOG=("$LOCAL_ROOT/usr/bin/iverilog" -B "$IVL_LIB")
    VVP=("$LOCAL_ROOT/usr/bin/vvp" -M "$IVL_LIB")
fi
VIVADO_DIR="${VIVADO_DIR:-/tools/Vivado/2022.1}"
"${IVERILOG[@]}" -g2012 -Wall -s tb_zcu104 -o build/tb_zcu104 \
    "$VIVADO_DIR/data/verilog/src/unisims/IBUFDS.v" \
    "$VIVADO_DIR/data/verilog/src/unisims/BUFG.v" \
    rtl/rv32_alu.v rtl/rv32_regfile.v rtl/rv32_csr.v rtl/rv32_core.v \
    rtl/simple_timer.v rtl/rv32_soc.v rtl/uart_tx.v rtl/zcu104_top.v tb/tb_zcu104.v
"${VVP[@]}" build/tb_zcu104
