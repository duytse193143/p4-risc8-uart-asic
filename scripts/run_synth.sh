#!/usr/bin/env bash
# =============================================================================
# run_synth.sh  -  D41-D43: standalone Yosys synthesis to Sky130 standard cells
# -----------------------------------------------------------------------------
# Run INSIDE the LibreLane container, from the project folder:
#     librelane --dockerized
#     cd ~/p4-risc8-uart-asic
#     bash scripts/run_synth.sh
#
# Outputs:
#     results/risc8_uart_top.synth.v   gate-level netlist (Sky130 cells)
#     reports/synth_stat.txt           cell count + area
#     reports/synth.log                full Yosys log
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

PDK_ROOT=${PDK_ROOT:-$HOME/.ciel}
LIB=${LIB:-$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib}
YOSYS=${YOSYS:-yosys}

if [ ! -f "$LIB" ]; then
    echo "ERROR: liberty file not found: $LIB"
    echo "Run 'librelane --dockerized --smoke-test' once to download the PDK,"
    echo "or set LIB=/path/to/sky130_fd_sc_hd__tt_025C_1v80.lib"
    exit 1
fi

mkdir -p results reports
SRC=$(ls src/*.v | tr '\n' ' ')

$YOSYS -l reports/synth.log -p "
    # 1. read the Sky130 cell list (as black boxes) and the RTL
    read_liberty -lib $LIB
    read_verilog $SRC

    # 2. generic synthesis (flatten = one netlist for the whole chip)
    #    -nofsm keeps the FSM state encoding exactly as written in the RTL,
    #    so every register in the netlist matches the RTL for LEC (D44)
    synth -top risc8_uart_top -flatten -nofsm

    # 3. map flip-flops to Sky130 flip-flop cells
    dfflibmap -liberty $LIB -dont_use *lpflow* -dont_use *probe*

    # 4. map logic to Sky130 gates, aiming for a 5 ns (200 MHz) clock
    #    (low-power isolation and probe cells are not for normal logic)
    abc -D 5000 -liberty $LIB -dont_use *lpflow* -dont_use *probe* -showtmp

    # 5. constant 0/1 cells, clean up
    hilomap -singleton -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO
    splitnets -ports
    opt_clean -purge

    # 6. reports + netlist
    tee -o reports/synth_stat.txt stat -liberty $LIB
    tee -o reports/synth_check.txt check -assert
    write_verilog -noattr -noexpr -nohex -nodec results/risc8_uart_top.synth.v
"

echo "Synthesis done."
echo "  Netlist : results/risc8_uart_top.synth.v"
echo "  Report  : reports/synth_stat.txt"
grep -E "Number of cells|Chip area" reports/synth_stat.txt || true