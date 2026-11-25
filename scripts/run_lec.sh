#!/usr/bin/env bash
# =============================================================================
# run_lec.sh  -  D44: Logical Equivalence Check (RTL vs synthesized netlist)
# -----------------------------------------------------------------------------
# Proves that results/risc8_uart_top.synth.v does exactly what the RTL does.
# Run in Ubuntu (or in the LibreLane tool shell) after scripts/run_synth.sh:
#     bash scripts/run_lec.sh
# Result: "LEC PASSED" (all signals proven equal) or "LEC FAILED".
# Log:    reports/lec.log
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

PDK_ROOT=${PDK_ROOT:-$HOME/.ciel}
LIB=${LIB:-$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib}
YOSYS=${YOSYS:-yosys}
NETLIST=results/risc8_uart_top.synth.v

[ -f "$NETLIST" ] || { echo "ERROR: run scripts/run_synth.sh first"; exit 1; }
[ -f "$LIB" ]     || { echo "ERROR: liberty file not found: $LIB"; exit 1; }
mkdir -p reports
SRC=$(ls src/*.v | tr '\n' ' ')

$YOSYS -q -l reports/lec.log -p "
    # ---- GOLD design: the RTL ----
    read_verilog $SRC
    prep -flatten -top risc8_uart_top
    memory -nomap; memory_map
    opt_clean; splitnets
    rename risc8_uart_top gold
    design -stash gold

    # ---- GATE design: the Sky130 netlist (cells read with their logic) ----
    read_liberty -ignore_miss_func $LIB
    read_verilog $NETLIST
    hierarchy -top risc8_uart_top
    flatten
    opt_clean; splitnets
    rename risc8_uart_top gate
    design -stash gate

    # ---- compare ----
    design -copy-from gold -as gold gold
    design -copy-from gate -as gate gate
    async2sync
    equiv_make gold gate equiv
    hierarchy -top equiv
    equiv_simple -seq 5
    equiv_induct -seq 5
    tee -o reports/lec_status.txt equiv_status
    equiv_status -assert
"
if [ $? -eq 0 ]; then
    echo "LEC PASSED  (see reports/lec_status.txt)"
else
    echo "LEC FAILED  (see reports/lec_status.txt and reports/lec.log)"
    exit 1
fi