# Special routing for the Power/Ground nets of the standard cells.
derive_pg_connection -power_net {VDD} -ground_net {VSS} -power_pin {VDD} -ground_pin {VSS}

# Check routability of the design.
check_zrt_routability  -error_view CHIP.err

# Routing setup. > M9 (avoid using MRDL)
set_ignored_layers  -max_routing_layer M9

# Fix antenna violations.
source -echo /usr/cadtool/cad/synopsys/SAED32_EDK/tech/milkyway/saed32nm_ant_1p9m.tcl

# Signal integrity setting.
set_si_options -delta_delay true -static_noise true -timing_window false -min_delta_delay false -static_noise_threshold_above_low 0.30 -static_noise_threshold_below_high 0.30 -route_xtalk_prevention true -route_xtalk_prevention_threshold 0.35 -analysis_effort medium -max_transition_mode normal_slew

# Clock route.
route_zrt_group -all_clock_nets

# Perform auto routing.
route_zrt_auto

# Detail route
route_opt -stage detail -xtalk_reduction

# Report the timing and power.
report_timing | tee ./report/report_time_setup_route.rep
report_timing -delay_type min | tee ./report/report_time_hold_route.rep
report_power | tee ./report/report_power_route.rep

# Power/Ground connection.
derive_pg_connection -power_net {VDD} -ground_net {VSS} -power_pin {VDD} -ground_pin {VSS} -create_ports top

# Save your design.
save_mw_cel CHIP
save_mw_cel -as 5_route