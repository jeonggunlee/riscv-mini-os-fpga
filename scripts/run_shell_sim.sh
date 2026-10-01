#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_ROOT="$PROJECT_DIR/build/tools/iverilog"
cd "$PROJECT_DIR"
if command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
    IVERILOG=(iverilog)
    VVP=(vvp)
else
    IVL_LIB="$LOCAL_ROOT/usr/lib/x86_64-linux-gnu/ivl"
    IVERILOG=("$LOCAL_ROOT/usr/bin/iverilog" -B "$IVL_LIB")
    VVP=("$LOCAL_ROOT/usr/bin/vvp" -M "$IVL_LIB")
fi
APP_BYTES=$(wc -c < build/firmware/hello_app.bin)
"${IVERILOG[@]}" -g2012 -Wall -DAPP_BYTES="$APP_BYTES" -s tb_shell -o build/tb_shell \
    rtl/rv32_alu.v rtl/rv32_regfile.v rtl/rv32_csr.v rtl/rv32_core.v \
    rtl/simple_timer.v rtl/rv32_soc.v rtl/uart_rx.v tb/tb_shell.v
SIM_OUTPUT="$("${VVP[@]}" build/tb_shell)"
printf '%s\n' "$SIM_OUTPUT"
[[ "$SIM_OUTPUT" == *"PASS: UART RX, MiniFS upload, CPU app fetch/execute/return"* ]]
