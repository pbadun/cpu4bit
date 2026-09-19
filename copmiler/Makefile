PYTHON ?= python3
EXAMPLES := \
	examples/arithmetic.asm \
	examples/blink.asm \
	examples/pwm.asm \
	examples/counter.asm \
	examples/io_echo.asm \
	examples/flags.asm
BINARIES := $(EXAMPLES:examples/%.asm=generated/%.bin)
MEMORIES := $(EXAMPLES:examples/%.asm=generated/%.mem)
HEXES := $(EXAMPLES:examples/%.asm=generated/%.hex)

.PHONY: all test check clean

all: $(BINARIES) $(MEMORIES) $(HEXES)

generated/%.bin: examples/%.asm cpu_asm.py
	mkdir -p generated
	$(PYTHON) cpu_asm.py $< --format bin --output $@

generated/%.mem: examples/%.asm cpu_asm.py
	mkdir -p generated
	$(PYTHON) cpu_asm.py $< --format mem --output $@

generated/%.hex: examples/%.asm cpu_asm.py
	mkdir -p generated
	$(PYTHON) cpu_asm.py $< --format hex --output $@

test:
	$(PYTHON) -m unittest discover -s tests -v

check:
	$(PYTHON) -m py_compile cpu_asm.py tests/test_cpu_asm.py
	$(PYTHON) -m unittest discover -s tests -v

clean:
	rm -rf generated __pycache__ tests/__pycache__
