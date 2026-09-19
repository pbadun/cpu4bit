# 4-bit Verilog CPU

This project implements the minimal 4-bit CPU described in `../tz_cpu.md`. It is intended as a small, readable, synthesizable teaching core.

## Architecture

```text
                 +------------------+
 read-only memory | instruction      |
 mem_data <-------| fetch (PC, IR)   |
                 +--------+---------+
                          |
                          v
                 +--------+---------+
                 | decoder / FSM    |
                 +--+-----------+---+
                    |           |
                    v           v
                 +------+    +------+
                 | R0/R1|    | PC  |
                 +--+---+    +------+
                    |
                    v
                 +------+
                 | ALU  |
                 +--+---+
                    |
                    v
                 flags / I/O
```

The core has an 8-bit address bus, an 8-bit read-only instruction interface, a 4-bit data path, two 4-bit general-purpose registers, C and V flags, and two 4-bit I/O ports. Instructions are fixed at 8 bits.

The FSM is `FETCH -> EXECUTE`. FETCH loads `mem_data` into IR and increments PC. EXECUTE performs the decoded operation. Consequently, relative branches are relative to the already incremented PC and all PC updates wrap at 8 bits.

Reset is asynchronous and active high. It starts execution at address `0x00`. HALT is a separate state: PC, registers, flags, I/O outputs, and memory address remain unchanged until reset.

## Files

```text
verilog/
├── Makefile
├── README.md
├── docs/
│   └── ISA.md
├── rtl/
│   ├── alu.v
│   ├── decoder.v
│   └── cpu.v
├── sim/
└── tb/
    └── tb_cpu.v
```

`cpu.v` contains the register file, PC, FSM, flag registers, and I/O output registers. `alu.v` is combinational. `decoder.v` converts each opcode and operand into control signals. `tb_cpu.v` contains a 256-byte instruction-memory model and automated checks.

## Requirements

- `iverilog`
- `vvp`
- `make` is optional

## Build and run

From this directory, compile and run directly with Icarus Verilog:

```sh
mkdir -p sim
iverilog -g2012 -Wall -s tb_cpu -o sim/cpu_sim rtl/alu.v rtl/decoder.v rtl/cpu.v tb/tb_cpu.v
vvp sim/cpu_sim
```

If `make` is available, the equivalent command is `make sim`. `make lint` compiles the RTL without the testbench, and `make clean` removes simulation outputs.

## Testbench coverage

The testbench automatically checks:

- LDI0 and LDI1
- ADD, carry, and signed overflow
- SUB and borrow
- AND and XOR, including flag preservation
- MOV01 and MOV10
- positive and negative PC-relative jumps
- JC taken and not taken
- JV taken and not taken
- IN and OUT for both ports
- HALT state retention
- PC wraparound from `0xFF` to `0x00`
- RESERVED and invalid I/O operands as NOP
- the intended control program and the `MOV01`/`MOV10` discrepancy in the technical specification

A failed comparison prints the expected and actual value and increments the final error count. A successful run ends with `ALL TESTS PASSED`.

## Example program

```asm
LDI0  5
LDI1  3
ADD
LDI1  1
ADD
MOV10
OUT   PORT0
HALT
```

Machine code:

```text
15 23 30 21 30 D0 B0 E0
```

The final state is `R0 = 9`, `R1 = 9`, `PORT0 = 9`, and `halted = 1`.

The source technical specification prints `MOV01` in this program while also requiring `R1 = 9`. The ISA table defines `MOV01` as `R0 = R1`, so the program as printed would leave both registers equal to 1. The testbench checks that behavior separately and uses `MOV10` for the intended final-state control program.

## ISA summary

| Opcode | Mnemonic | Operation |
| ---: | --- | --- |
| `0x0` | `NOP` | No operation |
| `0x1` | `LDI0` | `R0 = imm` |
| `0x2` | `LDI1` | `R1 = imm` |
| `0x3` | `ADD` | `R0 = R0 + R1`, update C/V |
| `0x4` | `SUB` | `R0 = R0 - R1`, update C/V |
| `0x5` | `AND` | `R0 = R0 & R1` |
| `0x6` | `XOR` | `R0 = R0 ^ R1` |
| `0x7` | `JMP` | PC-relative unconditional branch |
| `0x8` | `JC` | PC-relative branch if C |
| `0x9` | `JV` | PC-relative branch if V |
| `0xA` | `IN` | selected input port to R0 |
| `0xB` | `OUT` | R0 to selected output port |
| `0xC` | `MOV01` | `R0 = R1` |
| `0xD` | `MOV10` | `R1 = R0` |
| `0xE` | `HALT` | stop and hold state |
| `0xF` | `RESERVED` | NOP |

See `docs/ISA.md` for instruction encodings, flag equations, branch examples, and additional machine-code examples.
