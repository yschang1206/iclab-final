
set TOP_DIR $TOPLEVEL
set RPT_DIR report
set NET_DIR netlist

sh rm -rf ./$TOP_DIR
sh rm -rf ./$RPT_DIR
sh rm -rf ./$NET_DIR
sh mkdir ./$TOP_DIR
sh mkdir ./$RPT_DIR
sh mkdir ./$NET_DIR

define_design_lib $TOPLEVEL -path ./$TOPLEVEL
													   
set HDL_DIR "../hdl"

#Read Design File (add your files here)
analyze -library $TOPLEVEL -format verilog "$HDL_DIR/lenet.v \
$HDL_DIR/conv_ctrl.v \
$HDL_DIR/conv.v \
$HDL_DIR/relu.v \
$HDL_DIR/max_pool.v \
"
elaborate $TOPLEVEL -architecture verilog -library $TOPLEVEL

#Solve Multiple Instance
set uniquify_naming_style "%s_mydesign_%d"
uniquify

current_design $TOPLEVEL
link    
