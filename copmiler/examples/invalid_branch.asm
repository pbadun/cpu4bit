; Negative example: START is at address 0, but this branch is at 0xF8.
; The assembler must reject the resulting displacement instead of wrapping it.

START:  NOP
        .org   0xF8
        JMP    START
