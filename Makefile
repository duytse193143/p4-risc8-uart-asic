# =============================================================================
# Makefile  -  one-word commands for the P4 project
#   In Ubuntu (project folder):
#     make sim          RTL simulation                      (Part H)
#     make sim_jitter   RTL simulation with a jittery clock (Part H)
#     make lec          logic equivalence check             (Part K)
#     make gls          gate-level simulation               (Part K)
#     make flow         full RTL-to-GDSII run, venv active  (Part L)
#     make summary      signoff PASS/FAIL table             (Part N)
#   In the tool shell (librelane --dockerized):
#     make synth        Yosys synthesis                     (Part I)
#     make sta          OpenSTA pre-layout timing           (Part J)
#     make sta_jitter   OpenSTA jitter experiment           (Part J)
# =============================================================================
CXX      ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra
FLOW     ?= librelane --dockerized

.PHONY: sim sim_jitter synth sta sta_jitter lec gls flow summary clean

sim:
	bash scripts/run_sim.sh

sim_jitter:
	bash scripts/run_sim_jitter.sh

synth:
	bash scripts/run_synth.sh

sta:
	bash scripts/run_sta.sh

sta_jitter:
	bash scripts/run_sta_jitter.sh

lec:
	bash scripts/run_lec.sh

gls:
	bash scripts/run_gls.sh

flow:
	$(FLOW) config.json

scripts/signoff_summary: scripts/signoff_summary.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

summary: scripts/signoff_summary
	./scripts/signoff_summary

clean:
	rm -rf sim results reports scripts/signoff_summary