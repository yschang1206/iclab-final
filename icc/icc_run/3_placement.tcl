# Check the power numbers of the current virtual flat placement.
report_power > ./report/report_power.rep

# Set Power Optimization Constraint.
set_optimize_pre_cts_power_options

# Run full placement.
identify_clock_gating
place_opt -power

# Check the power numbers again to see the improvement.
report_power > ./report/report_power_placement.rep
report_timing > ./report/report_time_placement.rep

# Power/Ground connection.
derive_pg_connection -power_net {VDD} -ground_net {VSS} -power_pin {VDD} -ground_pin {VSS}

# Save your design.
save_mw_cel CHIP
save_mw_cel -as 3_placement