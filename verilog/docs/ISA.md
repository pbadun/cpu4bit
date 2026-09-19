# 4-bit CPU ISA

## Architecture

The CPU is a small synchronous processor with an external read-only instruction memory.

- Address bus: 8 bits
- Instruction width: 8 bits
- CPU data path: 4 bits
- Instruction memory: 256 x 8 bits, read only from the CPU
- General-purpose registers: R0 and R1, 4 bits each
- Program counter: PC, 8 bits
- Flags: C and V
- I/O ports: PORT0 and PORT1, 4 bits each
- Reset: asynchronous, active high

The core uses two states:

```text
FETCH -> EXECUTE -> FETCH
```

During FETCH, `mem_addr` is the current PC, `mem_data` is loaded into IR, and PC is incremented. Therefore, a relative
branch uses the address of the following instruction as its base. All PC arithmetic wraps at 8 bits.

## Registers

| Register |  Width | Description                                     |
|----------|-------:|-------------------------------------------------|
| PC       | 8 bits | Address of the instruction being fetched        |
| IR       | 8 bits | Instruction currently being executed            |
| R0       | 4 bits | General-purpose register and default I/O source |
| R1       | 4 bits | General-purpose register                        |
| C        |  1 bit | ADD carry or SUB borrow                         |
| V        |  1 bit | Signed arithmetic overflow                      |

Reset sets PC, IR, R0, R1, C, V, and the halted state to zero. PORT0 and PORT1 output registers are also cleared.

## Flags

For ADD:

```text
result = R0 + R1
C = result[4]
V = (~(R0[3] ^ R1[3])) & (result[3] ^ R0[3])
```

For SUB:

```text
result = R0 - R1
C = 1 when a borrow occurs
V = (R0[3] ^ R1[3]) & (result[3] ^ R0[3])
```

The result stored in R0 is the low four bits. AND and XOR update R0 but leave C and V unchanged.

## Instruction format

Every instruction is eight bits:

```text
7       4 3       0
+---------+---------+
| opcode  | operand |
+---------+---------+
```

The immediate or operand is always `instruction[3:0]`. The upper four bits are never used as an immediate.

## Opcode table

| Opcode | Mnemonic   | Operation                                    |
|-------:|------------|----------------------------------------------|
|  `0x0` | `NOP`      | No operation                                 |
|  `0x1` | `LDI0`     | `R0 = instruction[3:0]`                      |
|  `0x2` | `LDI1`     | `R1 = instruction[3:0]`                      |
|  `0x3` | `ADD`      | `R0 = R0 + R1`; update C and V               |
|  `0x4` | `SUB`      | `R0 = R0 - R1`; update C and V               |
|  `0x5` | `AND`      | `R0 = R0 & R1`                               |
|  `0x6` | `XOR`      | `R0 = R0 ^ R1`                               |
|  `0x7` | `JMP`      | `PC = PC + signed(operand)`                  |
|  `0x8` | `JC`       | Branch to `PC + signed(operand)` when C is 1 |
|  `0x9` | `JV`       | Branch to `PC + signed(operand)` when V is 1 |
|  `0xA` | `IN`       | Load the selected input port into R0         |
|  `0xB` | `OUT`      | Write R0 to the selected output port         |
|  `0xC` | `MOV01`    | `R0 = R1`                                    |
|  `0xD` | `MOV10`    | `R1 = R0`                                    |
|  `0xE` | `HALT`     | Stop fetching and hold all state             |
|  `0xF` | `RESERVED` | Treated as `NOP`                             |

## Instruction formats

```text
LDI0 imm   0001 imm
LDI1 imm   0010 imm
ADD        0011 xxxx
SUB        0100 xxxx
AND        0101 xxxx
XOR        0110 xxxx
JMP disp   0111 disp
JC disp    1000 disp
JV disp    1001 disp
IN port    1010 port
OUT port   1011 port
MOV01      1100 xxxx
MOV10      1101 xxxx
HALT       1110 xxxx
RESERVED   1111 xxxx
```

`xxxx` is ignored for register-register, branch, MOV, and HALT instructions. For IN and OUT, only port values 0 and 1
are valid. Other port values are treated as NOP.

## Relative branches

The displacement is the signed two's-complement value of the low four instruction bits:

```text
0x0 =  0
0x1 = +1
...
0x7 = +7
0x8 = -8
0x9 = -7
...
0xF = -1
```

The PC has already been incremented during FETCH. For example, a `JMP +2` fetched at address `0x10` is executed with PC
equal to `0x11`, so the resulting PC is `0x13`.

## I/O

IN and OUT use the low instruction operand as a port selector:

```text
operand 0 -> PORT0
operand 1 -> PORT1
```

IN samples the selected input port while its instruction is executed. OUT writes R0 to the selected output register on
the clock edge that executes the instruction. Output registers retain their values until another valid OUT or reset.

## Example machine-code program

The following program computes `(5 + 3) + 1`, copies the result to R1, outputs it to PORT0, and halts:

```text
Address  Instruction
0x00     0x15   LDI0 5
0x01     0x23   LDI1 3
0x02     0x30   ADD
0x03     0x21   LDI1 1
0x04     0x30   ADD
0x05     0xD0   MOV10
0x06     0xB0   OUT PORT0
0x07     0xE0   HALT
```

Final state:

```text
R0 = 9
R1 = 9
PORT0 = 9
halted = 1
```

The source technical specification prints `MOV01` in this control program while requiring `R1 = 9`. Because the ISA
explicitly defines `MOV01` as `R0 = R1`, that printed sequence would finish with `R0 = R1 = 1`. The executable program
above uses `MOV10`, which is the instruction that copies R0 to R1 and satisfies the stated final state.

## Example relative branch

```text
0x00: 0x72   JMP +2
0x01: 0x00   NOP
0x02: 0x00   NOP
0x03: 0x17   LDI0 7
0x04: 0xE0   HALT
```

After fetching the branch, PC is `0x01`; after execution it is `0x03`.
