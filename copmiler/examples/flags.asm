; Demonstrate conditional branches using C and V.
; The first ADD sets C. The second ADD sets signed overflow V.

        LDI0   15
        LDI1   1
        ADD
        JC     CARRY_SET
        NOP
        NOP
CARRY_SET:
        LDI0   7
        LDI1   1
        ADD
        JV     OVERFLOW_SET
        NOP
        NOP
OVERFLOW_SET:
        LDI0   0
        OUT    PORT0
        HALT
