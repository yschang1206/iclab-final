set TOPLEVEL "conv_layer"

#change timing constraint here
set TEST_CYCLE 6.5

source -echo -verbose 0_readfile.tcl 
source -echo -verbose 1_setting.tcl 
source -echo -verbose 2_compile.tcl
source -echo -verbose 3_report.tcl

exit
