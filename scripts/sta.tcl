# =============================================================================
# sta.tcl  -  D43 / D45: Static Timing Analysis with OpenSTA (pre-layout)
# -----------------------------------------------------------------------------
# Reads the synthesized netlist + Sky130 timing library + SDC, then reports
# setup (max) and hold (min) timing. Run with scripts/run_sta.sh.
# Wires are not placed yet, so this is an estimate; post-route STA is done
# by LibreLane (D50, D54).
# =============================================================================

read_liberty $::env(LIB)
read_verilog results/risc8_uart_top.synth.v
link_design risc8_uart_top
read_sdc constraints/risc8_uart.sdc

puts "\n==================== SETUP: 5 worst paths (D43) ===================="
report_checks -sort_by_slack -path_delay max -fields {slew cap input net fanout} \
    -format full_clock_expanded -group_path_count 5

puts "\n==================== HOLD: worst path =============================="
report_checks -sort_by_slack -path_delay min -fields {slew cap input net fanout} \
    -format full_clock_expanded -group_path_count 1

puts "\n==================== DESIGN RULES (slew / cap / fanout) ============"
report_check_types -max_slew -max_capacitance -max_fanout -violators

puts "\n==================== SUMMARY ======================================="
set wns_setup [worst_slack -max]
set wns_hold  [worst_slack -min]
set tns_setup [total_negative_slack -max]
set tns_hold  [total_negative_slack -min]
puts [format "Setup  WNS = %8.3f ns   TNS = %8.3f ns" $wns_setup $tns_setup]
puts [format "Hold   WNS = %8.3f ns   TNS = %8.3f ns" $wns_hold  $tns_hold]
if { $wns_setup >= 0 && $wns_hold >= 0 } {
    puts "TIMING MET at 200 MHz (WNS >= 0, TNS = 0)"
} else {
    puts "TIMING VIOLATED - fix the worst paths listed above"
}