# Copyright 2025 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Chaoqun Liang <chaoqun.liang@unibo.it>

TMU_ROOT ?= $(shell pwd)
BENDER	 ?= bender -d $(TMU_ROOT)

include axi_tmu.mk

# `make regen_regs` starts regtool.py through its `#!/usr/bin/env python3` shebang,
# i.e. with the first python3 found in PATH. Warn (without failing) when that is not
# the project virtual environment prepared by `source bootstrap.sh`.
ifneq ($(filter regen_regs,$(MAKECMDGOALS)),)
TMU_PYTHON := $(shell command -v python3)
ifneq ($(realpath $(dir $(TMU_PYTHON))),$(realpath $(TMU_ROOT)/.venv/bin))
$(warning The project Python environment (.venv) is NOT active: regtool.py will run with $(or $(TMU_PYTHON),no python3 found). Run 'source bootstrap.sh' first so that the flow uses the pinned environment)
endif
endif
