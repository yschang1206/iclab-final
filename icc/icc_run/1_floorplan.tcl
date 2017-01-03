source setup.tcl

# Read I/O physical constraint.
# You must create io_pin.tdf by yourself.
read_pin_pad_physical_constraints ../pre_layout/design_data/io_pin.tdf

# Floorplan.
# The core utilization can be set up to 70~80% normally. 
# The core margins are reserved for the core power ring.
# You must modify it.
create_floorplan -core_utilization 0.5 -flip_first_row -left_io2core 40 -bottom_io2core 40 -right_io2core 40 -top_io2core 40

# Identify clock-gating for further P&R.
identify_clock_gating
report_clock_gating

# Virtual flat placement.
create_fp_placement -timing_driven

# Check the timing report.
# This step assume there is no net delay, so the timing analysis should pass.
set_zero_interconnect_delay_mode true
report_timing > ./report/report_time_zero_net_delay.rep
# Set the net delay back to false.
set_zero_interconnect_delay_mode false

# Analyze congestion.
# Open the Global Route Congestion menu and then click “Reload” on the right hand side.
# If the design is still congested, you have to modify the floorplan.
# It means you should reduce the utilization.
create_fp_placement -congestion_driven
create_fp_placement -congestion_driven -incremental all

# Save your design.
save_mw_cel CHIP
save_mw_cel -as 1_floorplan

# You can see the floorplan and flat placement result in Layout Window
# where the core area for standard cells is surrounded by the pins.