#!/usr/bin/env bash
# =============================================================================
# run_sim.sh  -  RTL simulation with Icarus Verilog (before synthesis)
#     bash scripts/run_sim.sh
# Expected last line: TEST PASSED
# Waveform: sim/tb_risc8_uart.vcd  (open with: gtkwave sim/tb_risc8_uart.vcd)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim
iverilog -g2005 -Wall -o sim/rtl_sim.out tb/tb_risc8_uart.v src/*.v
cd sim && vvp -n rtl_sim.out