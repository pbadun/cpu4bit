; Count from 0 through 15 on PORT0, then halt.
; ADD sets C when the 4-bit counter wraps from 15 to 0.

        LDI0   0
COUNT:  OUT    PORT0
        LDI1   1
        ADD
        JC     DONE
        JMP    COUNT
DONE:   HALT
