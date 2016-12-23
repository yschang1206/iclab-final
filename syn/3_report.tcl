###-----------------------------Naming Rules----------------------------
set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true
change_names -rules verilog -hierarchy
define_name_rules name_rule -allowed {a-z A-Z 0-9 _} -max_length 255 -type cell
define_name_rules name_rule -allowed {a-z A-Z 0-9 _[]} -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule

####--------------------------Netlist-related------------------------------------
write -format ddc     -hierarchy -output ./$NET_DIR/${TOPLEVEL}_syn.ddc
write -format verilog -hierarchy -output ./$NET_DIR/${TOPLEVEL}_syn.v
write_sdf -version 2.1 -context verilog ./$NET_DIR/${TOPLEVEL}_syn.sdf
write_sdc ./$NET_DIR/${TOPLEVEL}_syn.sdc
write_saif -output ./$NET_DIR/${TOPLEVEL}_syn.saif 

####---------------------------Syntheis result reports----------------------------
report_timing -path full -delay max -max_paths 4 -nworst 4 -significant_digits 4 > ./$RPT_DIR/report_time_${TOPLEVEL}.out
report_timing -delay max -max_paths 4 > ./$RPT_DIR/report_setup_${TOPLEVEL}.out
report_constraint -all_violators > ./$RPT_DIR/report_violation_${TOPLEVEL}.out
report_area -hier  > ./$RPT_DIR/report_area_${TOPLEVEL}.out
report_power -hier > ./$RPT_DIR/report_power_${TOPLEVEL}.out
