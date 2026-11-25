#!/usr/bin/env bash
# =============================================================================
# run_sta_jitter.sh  -  D45 experiment: add jitter in STA, watch slack, remove it
# Run INSIDE the LibreLane tool shell after scripts/run_synth.sh:
#     bash scripts/run_sta_jitter.sh
# Report: reports/sta_jitter.rpt
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
PDK_ROOT=${PDK_ROOT:-$HOME/.ciel}
export LIB=${LIB:-$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib}
[ -f results/risc8_uart_top.synth.v ] || { echo "ERROR: run scripts/run_synth.sh first"; exit 1; }
[ -f "$LIB" ] || { echo "ERROR: liberty file not found: $LIB"; exit 1; }
mkdir -p reports
if command -v sta >/dev/null 2>&1; then
    sta -no_splash -exit scripts/sta_jitter.tcl | tee reports/sta_jitter.rpt
else
    openroad -no_splash -exit scripts/sta_jitter.tcl | tee reports/sta_jitter.rpt
fi