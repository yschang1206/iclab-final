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

# Working Directories
HDL_DIR =../hdl/
SYN_DIR =../syn/

# testbench
TESTBENCH = test_top.v

# misc
TOP   = top

# temp files
SIM_TEMP =  INCA_libs \
						verdiLog \
						nLintDB \
						nLintLog \
						sim_nLint \
						sim_pre \
						sim_gate \
						sim_post \
						*.log \
						*~

SYN_TEMP =  alib-52 \
						$(TOP) \
						netlist \
						report \
						*.svf \
						*.log \
						*~

# Targets
lint:
	make simclean
	mkdir sim_nLint
	nLint -f $(HDL_DIR)hdl.f -out nLint.txt
	mv nLintDB sim_nLint
	mv nLintLog sim_nLint
	cat nLint.txt | less

nwave:
	verdi & -nWave -f *.fsdb

presim:
	make simclean
	mkdir sim_pre
	ncverilog -f sim_pre.f
	mv INCA_libs sim_pre
	mv *.log sim_pre
# cat ./sim_pre/ncverilog.log | less

gatesim:
	make simclean
	mkdir sim_gate
	ncverilog -f sim_gate.f -warnmax 0
	mv INCA_libs sim_pre
	mv *.log sim_pre

syn:
	cd $(SYN_DIR) && dc_shell -f synthesis.tcl | tee da.log

# clean working directories
simclean:
	rm -rf $(SIM_TEMP)

synclean:
	cd $(SYN_DIR) && $(RM) $(SYN_TEMP)



###########################################

INCLIST = ../hdl/$(basename $@).f
NETLIST = ../syn/netlist/fir1_syn.v
GATE = /usr/cad/synopsys/SAED32_EDK/lib/stdcell_hvt/verilog/saed32nm_hvt.tv
# TEST_DEFINE_FILE = $(basename $@)_test_define.v
# DEFINE_FILE = ../hdl/define.v
TESTBENCH = $(basename $@)_test.v
LIB = -v /usr/cad/synopsys/SAED32_EDK/synthesis/vG-2012.06-SP5/dw/dw02/src_ver/DW02_prod_sum1.v
OPT = +notimingcheck

%.verdi :
	cd verdi
	verdi -autoalias -logfile ./verdi_compiler.log \
	+incdir + $(INCDIR) $(TEST_DEFINE_FILE) \
	$(DEFINE_FILE) $(LIB) $(TESTBENCH) &

%.lint:
	make simclean
	rm -rf sim_nLint
	mkdir sim_nLint
	nLint $(HDL_DIR)$(basename $@).v -out nLint.txt
	mv nLintDB sim_nLint
	mv nLintLog sim_nLint
	cat nLint.txt | less

%.com :
	ncverilog -c $(DEFINE_FILE) $(TESTBENCH) -F $(INCLIST)

%.sim :
	make simclean
	mkdir sim_pre
	ncverilog $(DEFINE_FILE) $(TESTBENCH) $(LIB) -F $(INCLIST)
	mv INCA_libs sim_pre
	mv *.log sim_pre

%.posim :
	make simclean
	mkdir sim_post
	ncverilog $(DEFINE_FILE) $(TESTBENCH) $(LIB) +vg $(GATE) $(NETLIST) +define+SDF
	mv INCA_libs sim_post
	mv *.log sim_post

# %.vcs :
#   make clean
#   vcs -R -full64 + v2k $(OPT) +define + $(DEFINE_FILE) +incdir + $(INCDIR) $(TEST_DEFINE_FILE)\
#   $(DEFINE_FILE) $(LIB) $(TESTBENCH) \
#   -l vcs.log -debug_pp +vcs_d + vpi + memcbk -P