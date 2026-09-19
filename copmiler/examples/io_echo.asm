; Continuously copy PORT0 input to PORT1 output.
; Reset the CPU to leave this infinite loop.

ECHO:   IN     PORT0
        OUT    PORT1
        JMP    ECHO
