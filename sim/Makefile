# Targets description
# make check : use nLint to check your hdl source code, and save the check result in /sim/nlint_check_result.txt
# make presim : run CPU simulation and save the result in /sim/register.txt
# make gatesim : run CPU gate-level simulation and save the result in /sim/register.txt
# (Note : you should run synthesis first before gate-level simulation!! )
# make syn " run Design Compiler to synthesize the CPU into netlist under /syn
# make veryclean : clean all the temporary files under /sim, /source and syn
# make simclean : clean temporary files under /sim
# make hdlclean : clean temporary files under /source
# make synclean : clean temporary files under /syn
# Simulation : $ make xxx.sim
# nLint      : $ make xxx.lint
# Verdi      : $ make xxx.verdi
# Clean      : $ make clean

# CAD-Tools & shell-commands
VLOG  = ncverilog
LINT  = nLint
DC  = dc_shell
RM  = rm -rf

# Working Directories
HDL_DIR =../hdl/
SYN_DIR =../syn/

# testbench
TESTBENCH = test_top.v

# misc
TOP   = top_pipe

# arguments
VLOGARG =+access+r

# temp files
TEMP  =INCA_libs \
	VerdiLog \
	nWaveLog \
	nLintDB \
	nLintLog \
	novas.rc \
	novas.conf \
	*.fsdb \
	*.log \
	*.key \
	*~ \
	*.X 
SYN_TEMP=*.log \
	alib-52 \
	$(TOP) \
	netlist \
	report \
	*.svf \
	*.key \
	*~
  
# Targets
lint :
	rm -rf sim_nLint
	mkdir sim_nLint
	nLint -f $(HDL_DIR)hdl.f -out nLint.txt
	mv nLintDB sim_nLint
	mv nLintLog sim_nLint
	cat nLint.txt | less

presim :
	rm -rf sim_pre
	mkdir sim_pre
	ncverilog -f sim_pre.f
	mv INCA_libs sim_pre
	mv ncverilog.log sim_pre
	mv novas_dump.log sim_pre
	# cat ./sim_pre/ncverilog.log | less

gatesim :
	ncverilog -f sim_gate.f | tee gatesim_log.log
syn :
	cd $(SYN_DIR) && dc_shell -f synthesis.tcl | tee da.log

# clean working directories
veryclean: hdlclean simclean synclean
hdlclean :
	cd $(HDL_DIR) && $(RM) $(TEMP)
simclean :
	cd rm -rf $(TEMP)
synclean :
	cd $(SYN_DIR) && $(RM) $(SYN_TEMP)



###########################################

INCLIST = ../hdl/$(basename $@).f
NETLIST = ../syn/netlist/fir1_syn.v
GATE = /usr/cad/synopsys/SAED32_EDK/lib/stdcell_hvt/verilog/saed32nm_hvt.tv
TEST_DEFINE_FILE = $(basename $@)_test_define.v
# DEFINE_FILE = ../hdl/define.v
TESTBENCH = $(basename $@)_test.v
LIB = -v /usr/cad/synopsys/SAED32_EDK/synthesis/vG-2012.06-SP5/dw/dw02/src_ver/DW02_prod_sum1.v
OPT = +notimingcheck
%.verdi :
	cd verdi; \
	verdi -autoalias -logfile ./verdi_compiler.log \
	+incdir + $(INCDIR) $(TEST_DEFINE_FILE) \
	$(DEFINE_FILE) $(LIB) $(TESTBENCH) &
# %.vcs :
#   make clean
#   vcs -R -full64 + v2k $(OPT) +define + $(DEFINE_FILE) +incdir + $(INCDIR) $(TEST_DEFINE_FILE)\
#   $(DEFINE_FILE) $(LIB) $(TESTBENCH) \
#   -l vcs.log -debug_pp +vcs_d + vpi + memcbk -P
%.lint :
	mkdir lint; \
	nLint -2001 -beauty -F $(INCLIST) \
	-maxseverity 2 -minseverity 2 -out $(basename $@)_warn.log; \
	nLint -rdb nLintDB -beauty -maxseverity 3 -minseverity 3 -out $(basename $@)_error.log; \
	nLint -rdb nLintDB -beauty -maxseverity 4 -minseverity 4 -out $(basename $@)_fatal.log; \
	mv *.log lint
%.com :
	ncverilog -c $(DEFINE_FILE) $(TESTBENCH) -F $(INCLIST)
%.sim :
	make clean; \
	mkdir simu; \
	ncverilog $(DEFINE_FILE) $(TESTBENCH) $(LIB) -F $(INCLIST) +access+r
	mv INCA_libs simu; \
	mv *.log simu
%.posim :
	make clean; \
	mkdir simu; \
	ncverilog $(DEFINE_FILE) $(TESTBENCH) $(LIB) +vg $(GATE) $(NETLIST) +define+SDF +access+r
	mv INCA_libs simu; \
	mv *.log simu
	mv *.X simu
clean :
	rm -rf simu
