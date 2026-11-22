# The cross-validation harness of REGULATIVE-LOWERING-SPEC.md sections 6.2 and 6.3; see README.md.
#
#   make -C jl4/examples/explore/harness check [RELEASE=1] [OUT=<work dir>] [L4=<l4 binary>]
#
# The tools are found on PATH, or named by MCRL2_BIN (the directory holding ltscompare), TLA2TOOLS_JAR with JAVA,
# and NUSMV. A tool that is not installed makes its cells unknown, loudly; RELEASE=1 makes an unknown liveness or
# bisimulation check fail the run, which is the release gate.

HERE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PYTHON ?= python3

.PHONY: check
check:
	$(PYTHON) $(HERE)harness.py $(if $(filter 1,$(RELEASE)),--release) $(if $(OUT),--out "$(OUT)") $(if $(L4),--l4 "$(L4)")
