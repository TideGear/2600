; Common macros/helpers for this project.

; Clear $00-$FF (TIA regs + RIOT RAM) and init CPU flags/stack.
; This is safe at reset and helps ensure deterministic startup.
    MAC CLEAN_START
        sei
        cld
        ldx #$FF
        txs

        lda #$00
        ldx #$00
.clear:
        sta $00,x
        inx
        bne .clear
    ENDM

; Convenience: waste 2 cycles
    MAC NOP2
        nop
    ENDM

