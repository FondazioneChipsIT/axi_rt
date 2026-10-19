# Copyright 2025 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Chaoqun Liang <chaoqun.liang@unibo.it>

BENDER   ?= bender
PYTHON3  ?= python3
REGTOOL  ?= $(shell $(BENDER) path register_interface)/vendor/lowrisc_opentitan/util/regtool.py
QUESTA 	 ?= questa-2023.4
TBENCH   ?= tb_axi_tmu
DUT      ?= axi_tmu_top

# Design and simulation variables
TMU_ROOT      ?= $(shell $(BENDER) path axi_tmu)
TMU_VSIM_DIR  := $(TMU_ROOT)/target/sim/vsim

compile_script_synth ?= $(TMU_ROOT)/target/sim/vsim/synth_compile.tcl

QUESTA_FLAGS := -permissive -suppress 3009 -suppress 8386 -error 7 +UVM_NO_RELNOTES

ifdef DEBUG
	VOPT_FLAGS := $(QUESTA_FLAGS) +acc
	VSIM_FLAGS := $(QUESTA_FLAGS) +acc
	RUN_AND_EXIT := log -r /*; run -all
else
	VOPT_FLAGS := $(QUESTA_FLAGS) +acc=npr+$(TBENCH). +acc=npr+$(DUT).
	VSIM_FLAGS := $(QUESTA_FLAGS) -c
	RUN_AND_EXIT := run -all; exit
endif

ifeq ($(netlist_sim),1)
	NETLIST := -t netlist_sim
	VSIM_FLAGS += +notimingchecks
endif

# Download bender
bender:
	curl --proto '=https'  \
	--tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh -s -- 0.24.0

synth_targs += -t rtl -t tmu_synth

synth-ips:
	$(BENDER) update
	$(BENDER) script synopsys \
    $(synth_targs) \
	> ${compile_script_synth}

##############
# Simulation #
##############

# Questasim
$(TMU_ROOT)/target/sim/vsim/compile.tmu.tcl: Bender.yml
	$(BENDER) script vsim -t rtl -t test -t tmu_test -t sim $(NETLIST) \
	--vlog-arg="-svinputport=compat" \
	--vlog-arg="-override_timescale 1ns/1ps" \
	--vlog-arg="-suppress 2583" > $@
	echo 'vopt $(VOPT_FLAGS) $(TBENCH) -o $(TBENCH)_opt' >> $@

tmu-sim-init: $(TMU_ROOT)/target/sim/vsim/compile.tmu.tcl

tmu-build: tmu-sim-init
	cd $(TMU_VSIM_DIR) && $(QUESTA) vsim -c -do "quit -code [source $(TMU_ROOT)/target/sim/vsim/compile.tmu.tcl]"

tmu-sim:
	cd $(TMU_VSIM_DIR) && $(QUESTA) vsim $(VSIM_FLAGS) -do \
		"set TESTBENCH $(TBENCH); \
		 set VSIM_FLAGS \"$(VSIM_FLAGS)\"; \
		 source $(TMU_ROOT)/target/sim/vsim/start.tmu.tcl ; \
		 $(RUN_AND_EXIT)"

#################################
# Phonies #
#################################

## @section register generation
.PHONY: regen_regs

# Define the path to regtool.py
REGTOOL ?= $(REG_DIR)/vendor/lowrisc_opentitan/util/regtool.py

# Register blocks, one per variant. Every variant needs
# src/registers/regmap/axi_tmu_<variant>_regs.hjson whose `name:` field is axi_tmu_<variant>:
# regtool derives the names of everything it generates (package, modules, types,
# C macros) from that field. Restrict the list with e.g. `make regen_regs TMU_VARIANTS=ilt`.
TMU_VARIANTS ?= ilt clt plt
REG_MAP_DIR  := $(TMU_ROOT)/src/registers/regmap
REG_SRC_DIR  := $(TMU_ROOT)/src/registers
REG_SW_DIR   := $(TMU_ROOT)/sw/include/regs

# Register generation targets
REGEN_TARGETS := $(foreach v,$(TMU_VARIANTS), \
                   $(REG_SRC_DIR)/axi_tmu_$(v)_reg_pkg.sv \
                   $(REG_SRC_DIR)/axi_tmu_$(v)_reg_top.sv \
                   $(REG_SW_DIR)/axi_tmu_$(v)_reg.h)

# Rule to generate .sv files. A pattern rule with several targets is run once for
# all of them, so regtool is not started twice. The check catches an hjson whose
# `name:` does not match its file name (regtool would write differently named files).
$(REG_SRC_DIR)/%_reg_pkg.sv $(REG_SRC_DIR)/%_reg_top.sv: $(REG_MAP_DIR)/%_regs.hjson
	$(REGTOOL) -r -t $(REG_SRC_DIR) $<
	@test -f $(REG_SRC_DIR)/$*_reg_pkg.sv && test -f $(REG_SRC_DIR)/$*_reg_top.sv || \
	  { echo "error: $< must declare name: \"$*\" (regtool did not write $*_reg_pkg.sv / $*_reg_top.sv)"; exit 1; }

# Rule to generate .h file
$(REG_SW_DIR)/%_reg.h: $(REG_MAP_DIR)/%_regs.hjson
	$(REGTOOL) -D -o $@ $<

# Main target
regen_regs: $(REGEN_TARGETS)

.PHONY: tmu-all tmu-sim-init tmu-build tmu-sim