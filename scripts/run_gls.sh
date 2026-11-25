#!/usr/bin/env bash
# =============================================================================
# run_gls.sh  -  gate-level simulation of a Sky130 netlist
# -----------------------------------------------------------------------------
#     bash scripts/run_gls.sh                                  # synthesis netlist
#     bash scripts/run_gls.sh runs/<run>/final/nl/risc8_uart_top.nl.v   # after PnR
#
# Yosys reads the Sky130 cells with their logic from the liberty file and
# writes one flat Verilog model; Icarus then runs the same testbench at the
# real baud rate (1736 clocks per bit). Takes a few minutes.
# Expected last line: TEST PASSED
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

NETLIST=${1:-results/risc8_uart_top.synth.v}
PDK_ROOT=${PDK_ROOT:-$HOME/.ciel}
LIB=${LIB:-$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib}
YOSYS=${YOSYS:-yosys}

[ -f "$NETLIST" ] || { echo "ERROR: netlist not found: $NETLIST"; exit 1; }
[ -f "$LIB" ]     || { echo "ERROR: liberty file not found: $LIB"; exit 1; }
mkdir -p sim

$YOSYS -q -p "
    read_liberty -ignore_miss_func $LIB
    read_verilog $NETLIST
    hierarchy -top risc8_uart_top
    flatten
    opt_clean
    write_verilog -noattr sim/gate_flat.v
"
iverilog -g2005 -DGATE_LEVEL -o sim/gls_sim.out tb/tb_risc8_uart.v sim/gate_flat.v
cd sim && vvp -n gls_sim.out