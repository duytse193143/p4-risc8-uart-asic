# =============================================================================
# sta_jitter.tcl  -  D45 experiment: add clock jitter on purpose, watch slack,
#                    then remove it again.
# -----------------------------------------------------------------------------
# Jitter is modelled in STA with set_clock_uncertainty. We raise it step by
# step (more jitter), report setup and hold slack, then put it back to the
# value in our SDC (0.25 ns).
# Run inside the LibreLane tool shell, after scripts/run_synth.sh:
#     bash scripts/run_sta_jitter.sh
# =============================================================================

read_liberty $::env(LIB)
read_verilog results/risc8_uart_top.synth.v
link_design risc8_uart_top
read_sdc constraints/risc8_uart.sdc

proc show {label} {
    set ws [worst_slack -max]
    set ts [total_negative_slack -max]
    set wh [worst_slack -min]
    set th [total_negative_slack -min]
    set ok [expr {($ws >= 0 && $wh >= 0) ? "MET" : "VIOLATED"}]
    puts [format "%-26s setup WNS %7.3f  TNS %8.3f | hold WNS %7.3f  TNS %8.3f | %s" \
              $label $ws $ts $wh $th $ok]
}

puts "\n=== 1. Baseline: our SDC (uncertainty 0.25 ns) ==="
show "uncertainty 0.25 (SDC)"

puts "\n=== 2. Add jitter to SETUP checks (period 5 ns) ==="
foreach u {0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00} {
    set_clock_uncertainty -setup $u [get_clocks clk]
    show "setup uncertainty $u"
}

puts "\n=== 3. Add uncertainty to HOLD checks ==="
set_clock_uncertainty -setup 0.25 [get_clocks clk]
foreach u {0.00 0.10 0.25 0.35 0.40 0.50} {
    set_clock_uncertainty -hold $u [get_clocks clk]
    show "hold uncertainty $u"
}

puts "\n=== 4. Remove the extra jitter: back to the SDC value ==="
set_clock_uncertainty 0.25 [get_clocks clk]
show "uncertainty 0.25 (SDC)"