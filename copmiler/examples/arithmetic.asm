; (5 + 3) + 1, copy the result to R1, output it, and halt.
; Expected compact bytes: 15 23 30 21 30 D0 B0 E0

        LDI0  5
        LDI1  3
        ADD
        LDI1  1
        ADD
        MOV10
        OUT   PORT0
        HALT
