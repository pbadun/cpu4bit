; Fixed-duty software PWM on PORT0.
; High phase: LDI0 15, OUT, NOP. Low phase: LDI0 0, OUT, JMP.
; Keep JMP PWM within the signed -8..+7 displacement range when editing.

        LDI0   0
PWM:    LDI0   15
        OUT    PORT0
        NOP
        LDI0   0
        OUT    PORT0
        JMP    PWM
