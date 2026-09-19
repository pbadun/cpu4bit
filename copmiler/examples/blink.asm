; Software blink on PORT0.
; Low phase: LDI0 0, OUT, NOP, NOP. High phase: LDI0 15, OUT, NOP, JMP.
; JMP BLINK uses the minimum valid signed displacement (-8).

BLINK:  LDI0   0
        OUT    PORT0
        NOP
        NOP
        LDI0   15
        OUT    PORT0
        NOP
        JMP    BLINK
