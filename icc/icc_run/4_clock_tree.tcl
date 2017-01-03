source setup.tcl
# Since it has been reset to false when ICC is initialized.
set power_cg_auto_identify true

# Add tie cells for constant signals 1’b1 (tie high) and 1’b0 (tie low).
source -echo ../pre_layout/design_data/add_tie.tcl

# Identify clock gating by executing.
identify_clock_gating

# Set available metal layer.
set_clock_tree_options -max_transition 0.500 -max_capacitance 600.000 -max_fanout 2000 -max_rc_scale_factor 0.000 -target_early_delay 0.000 -target_skew 0.000 -buffer_relocation TRUE -gate_sizing FALSE -buffer_sizing TRUE -gate_relocation TRUE -layer_list {M1 M2 M3 M4 M5 M6 M7 M8 M9 } -logic_level_balance FALSE -insert_boundary_cell FALSE -ocv_clustering FALSE -ocv_path_sharing FALSE -operating_condition max

# Turn on hold time fixing.
set_fix_hold [all_clocks]

# CTS optimization.
clock_opt -fix_hold_all_clocks -no_clock_route

# Use report_timing to check if setup time is violated,
# and report_timing -delay_type min to report hold time.
report_timing > ./report/report_time_setup_cts.rep
report_timing -delay_type min > ./report/report_time_hold_cts.rep

# View the clock tree by selecting View->Visual Mode in the Layout Window.
# Choose the option Clock Trees in the menu on the right.

# Save your design.
save_mw_cel CHIP
save_mw_cel -as 4_cts