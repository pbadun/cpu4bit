IVERILOG ?= iverilog
VVP ?= vvp

RTL_SOURCES = rtl/alu.v rtl/decoder.v rtl/cpu.v
TB_SOURCE = tb/tb_cpu.v
SIM_BINARY = sim/cpu_sim

.PHONY: all sim clean lint

all: sim

$(SIM_BINARY): $(RTL_SOURCES) $(TB_SOURCE)
	mkdir -p sim
	$(IVERILOG) -g2012 -Wall -s tb_cpu -o $@ $(RTL_SOURCES) $(TB_SOURCE)

sim: $(SIM_BINARY)
	$(VVP) $(SIM_BINARY)

lint:
	$(IVERILOG) -g2012 -Wall -s cpu -o sim/cpu_rtl.vvp $(RTL_SOURCES)

clean:
	rm -f $(SIM_BINARY) sim/cpu_rtl.vvp
