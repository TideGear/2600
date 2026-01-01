; =============================================================================
; MECHA SIMULATOR - Macros
; Atari 2600 (16K F4 Bank-Switching)
; =============================================================================

; -----------------------------------------------------------------------------
; VERTICAL_SYNC - Generate 3 lines of VSYNC
; Timing: Exactly 3 scanlines
; -----------------------------------------------------------------------------
        MAC VERTICAL_SYNC
        lda #$02        ; D1=1 for VSYNC on
        sta WSYNC       ; End line 1
        sta VSYNC
        sta WSYNC       ; End line 2
        sta WSYNC       ; End line 3
        lda #$00
        sta VSYNC       ; VSYNC off
        ENDM

; -----------------------------------------------------------------------------
; CLEAN_START - Zero RAM and TIA, initialize stack
; Call once at startup
; -----------------------------------------------------------------------------
        MAC CLEAN_START
        sei             ; Disable interrupts
        cld             ; Clear decimal mode
        ldx #$FF
        txs             ; Initialize stack pointer
        lda #0
.clearLoop:
        sta $00,X       ; Clear TIA registers ($00-$3F)
        sta $80,X       ; Clear RAM ($80-$FF) - wraps at 128 bytes
        dex
        bne .clearLoop
        ENDM

; -----------------------------------------------------------------------------
; SLEEP - Waste cycles
; Usage: SLEEP n (where n is number of cycles to waste)
; -----------------------------------------------------------------------------
        MAC SLEEP
        IF {1} >= 2
            IF {1} & 1
                bit $00     ; 3 cycles (zeropage)
                REPEAT ({1} - 3) / 2
                    nop     ; 2 cycles each
                REPEND
            ELSE
                REPEAT {1} / 2
                    nop     ; 2 cycles each
                REPEND
            ENDIF
        ENDIF
        ENDM

; -----------------------------------------------------------------------------
; TIMER_SETUP - Set timer for scanline counting
; Usage: TIMER_SETUP lines
; Uses TIM64T: 64 cycles per tick, ~76 cycles per scanline
; Formula: ticks = (lines * 76) / 64 = lines * 1.1875
; -----------------------------------------------------------------------------
        MAC TIMER_SETUP
.lines  SET {1}
.ticks  SET (.lines * 76 + 32) / 64   ; Round to nearest
        lda #.ticks
        sta TIM64T
        ENDM

; -----------------------------------------------------------------------------
; TIMER_WAIT - Wait for timer to expire
; -----------------------------------------------------------------------------
        MAC TIMER_WAIT
.waitTimer:
        lda INTIM
        bne .waitTimer
        ENDM

; -----------------------------------------------------------------------------
; SWITCH_BANK - Switch to specified bank
; Usage: SWITCH_BANK bank_number
; Note: Code continues at same address in new bank
; -----------------------------------------------------------------------------
        MAC SWITCH_BANK
        lda BANK0 + {1}
        ENDM

; -----------------------------------------------------------------------------
; CALL_BANK - Call subroutine in another bank, return to current bank
; Usage: CALL_BANK bank_number, subroutine_address, return_bank
; Note: Uses JSR/RTS pattern with trampoline
; -----------------------------------------------------------------------------
        MAC CALL_BANK
        ; Push return address info
        lda #>{3}               ; Return bank
        pha
        lda #<.returnPoint-1    ; Return address low (RTS adds 1)
        pha
        lda #>.returnPoint-1    ; Return address high
        pha
        ; Switch to target bank and jump
        lda BANK0 + {1}
        jmp {2}
.returnPoint:
        ENDM

; -----------------------------------------------------------------------------
; POSITION_SPRITE - Position a sprite horizontally
; Usage: POSITION_SPRITE xpos, RESPx
; A = X position (0-159), X = RESP register offset
; Destroys: A, X (if used for register)
; Must be called during horizontal blank or with WSYNC
; -----------------------------------------------------------------------------
        MAC POSITION_SPRITE
        lda {1}         ; Load X position
        ldx #{2}        ; Load RESP register ($10=P0, $11=P1, etc.)
        jsr PosSprite   ; Call positioning routine
        ENDM

; -----------------------------------------------------------------------------
; SET_POINTER - Set a 16-bit pointer
; Usage: SET_POINTER pointer, address
; -----------------------------------------------------------------------------
        MAC SET_POINTER
        lda #<{2}
        sta {1}
        lda #>{2}
        sta {1}+1
        ENDM

; -----------------------------------------------------------------------------
; ADD16 - 16-bit addition
; Usage: ADD16 dest, src (adds src to dest)
; -----------------------------------------------------------------------------
        MAC ADD16
        clc
        lda {1}
        adc {2}
        sta {1}
        lda {1}+1
        adc {2}+1
        sta {1}+1
        ENDM

; -----------------------------------------------------------------------------
; SUB16 - 16-bit subtraction
; Usage: SUB16 dest, src (subtracts src from dest)
; -----------------------------------------------------------------------------
        MAC SUB16
        sec
        lda {1}
        sbc {2}
        sta {1}
        lda {1}+1
        sbc {2}+1
        sta {1}+1
        ENDM

; -----------------------------------------------------------------------------
; NEG8 - Negate 8-bit value (two's complement)
; Usage: NEG8 (operates on A)
; -----------------------------------------------------------------------------
        MAC NEG8
        eor #$FF
        clc
        adc #1
        ENDM

; -----------------------------------------------------------------------------
; ABS8 - Absolute value of signed 8-bit
; Usage: ABS8 (operates on A, assumes signed)
; -----------------------------------------------------------------------------
        MAC ABS8
        bpl .positive
        NEG8
.positive:
        ENDM

; -----------------------------------------------------------------------------
; LFSR_NEXT - Advance 16-bit LFSR (pseudo-random)
; Uses taps at bits 16,15,13,4 for maximal length
; Operates on randomSeed/randomSeed+1
; -----------------------------------------------------------------------------
        MAC LFSR_NEXT
        lda randomSeed
        asl
        rol randomSeed+1
        bcc .noXor
        ; XOR with $B400 for maximal period
        lda randomSeed
        eor #$00
        sta randomSeed
        lda randomSeed+1
        eor #$B4
        sta randomSeed+1
.noXor:
        ENDM

; -----------------------------------------------------------------------------
; DRAW_BLANK_LINES - Draw N blank scanlines
; Usage: DRAW_BLANK_LINES n
; -----------------------------------------------------------------------------
        MAC DRAW_BLANK_LINES
        ldx #{1}
.blankLoop:
        sta WSYNC
        dex
        bne .blankLoop
        ENDM

; -----------------------------------------------------------------------------
; DEBUG_COLOR - Set background color (for timing debug)
; Usage: DEBUG_COLOR color
; Uncomment the IFCONST block to enable debug colors
; -----------------------------------------------------------------------------
        MAC DEBUG_COLOR
        ; No-op in release builds
        ; To enable: uncomment lines below
        ; lda #{1}
        ; sta COLUBK
        ENDM

; =============================================================================
; End of macros.asm
; =============================================================================

