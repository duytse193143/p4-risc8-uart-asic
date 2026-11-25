# =============================================================================
# risc8_uart.sdc  -  D42: timing constraints for risc8_uart_top
# -----------------------------------------------------------------------------
# Used by: LibreLane (PNR_SDC_FILE, SIGNOFF_SDC_FILE) and scripts/sta.tcl
# Units: ns, pF (from the Sky130 liberty files)
# =============================================================================

# 1. Clock: 200 MHz -> period 5 ns, 50% duty cycle
create_clock -name clk -period 5.0 [get_ports clk]

# 2. Clock quality: jitter/skew margin and edge rate
set_clock_uncertainty 0.25 [get_clocks clk]
set_clock_transition  0.15 [get_clocks clk]

# 3. Input delays: signals arrive 1 ns (20% of the period) after the clock edge
set_input_delay 1.0 -clock clk [get_ports {rst_n uart_rx}]

# 4. Output delays: the outside world needs the outputs 1 ns before the next edge
set_output_delay 1.0 -clock clk [get_ports {uart_tx halted}]

# 5. What drives the inputs and what loads the outputs
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [get_ports {rst_n uart_rx}]
set_load 0.0334 [all_outputs]

# 6. Design rules
set_max_fanout 10 [current_design]