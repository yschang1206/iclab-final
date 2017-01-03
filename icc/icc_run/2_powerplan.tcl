source setup.tcl

# Since it has been reset to false when ICC is initialized.
set power_cg_auto_identify true

# Use Power Network Synthesis of ICC to automatically generate power ring and power straps.
# You must modify it.
set_fp_rail_constraints -add_layer  -layer M4 -direction horizontal -max_strap 1 -min_strap 1 -max_width 2 -min_width 2 -spacing minimum
set_fp_rail_constraints -add_layer  -layer M5 -direction vertical -max_strap 4 -min_strap 2 -max_width 2 -min_width 2 -spacing minimum
set_fp_rail_constraints  -set_ring -nets  {VDD VSS}  -horizontal_ring_layer { M4 } -vertical_ring_layer { M5 } -ring_width 4 -ring_offset 1 -extend_strap core_ring

# Execute PNS.
synthesize_fp_rail  -nets {VDD VSS} -voltage_supply 1.05 -synthesize_power_plan -synthesize_power_pads -analyze_power -power_budget 10 -use_strap_ends_as_pads -create_virtual_rail M1

# Commit the PNS result.
commit_fp_rail

# Three post-processing actions should be taken to avoid P&R errors later.
# 1. Delete horizontal straps which could cause unwanted short circuits.
# 2. Avoid cells placed under the straps.
set_pnet_options -complete "M4 M5"
create_fp_placement -incremental all
# 3. Delete the vias for the deleted horizontal straps on the core ring and vertical straps.

# Create standard cell rails.
preroute_standard_cells -extend_for_multiple_connections  -extension_gap 20 -connect horizontal  -remove_floating_pieces  -do_not_route_over_macros  -fill_empty_rows  -port_filter_mode off -cell_master_filter_mode off -cell_instance_filter_mode off -voltage_area_filter_mode off -route_type {P/G Std. Cell Pin Conn}

# Save your design.
save_mw_cel CHIP
save_mw_cel -as 2_powerplan