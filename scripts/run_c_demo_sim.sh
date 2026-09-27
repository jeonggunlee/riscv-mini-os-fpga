#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_ROOT="$PROJECT_DIR/build/tools/iverilog"

cd "$PROJECT_DIR"
mkdir -p build

if command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
    IVERILOG=(iverilog)
    VVP=(vvp)
elif [[ -x "$LOCAL_ROOT/usr/bin/iverilog" && -x "$LOCAL_ROOT/usr/bin/vvp" ]]; then
    IVL_LIB="$LOCAL_ROOT/usr/lib/x86_64-linux-gnu/ivl"
    IVERILOG=("$LOCAL_ROOT/usr/bin/iverilog" -B "$IVL_LIB")
    VVP=("$LOCAL_ROOT/usr/bin/vvp" -M "$IVL_LIB")
else
    echo "Icarus Verilog is required. Install it with: sudo apt install iverilog" >&2
    exit 1
fi

"${IVERILOG[@]}" -g2012 -Wall -o build/tb_c_demo \
    rtl/rv32_alu.v \
    rtl/rv32_regfile.v \
    rtl/rv32_csr.v \
    rtl/rv32_core.v \
    rtl/simple_timer.v \
    rtl/rv32_soc.v \
    tb/tb_c_demo.v

"${VVP[@]}" build/tb_c_demo
