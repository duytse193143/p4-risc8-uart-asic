#!/usr/bin/env bash
# =============================================================================
# run_sim_jitter.sh  -  D45 demo: RTL simulation with a jittery clock
#     bash scripts/run_sim_jitter.sh
# Prints the first 12 clock periods (each one different), the shortest and
# longest period, and still ends with TEST PASSED: simulation checks function,
# STA checks timing.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim
iverilog -g2005 -Wall -DJITTER -o sim/rtl_jitter.out tb/tb_risc8_uart.v src/*.v
cd sim && vvp -n rtl_jitter.out | grep -E "JITTER|PASSED|FAILED"