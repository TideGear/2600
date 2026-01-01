; =============================================================================
; MECHA SIMULATOR - Bank 2: Math Tables & Game Logic
; Atari 2600 (16K F4 Bank-Switching)
; =============================================================================

        SEG     BANK2
        ORG     $E000
        RORG    $E000

; =============================================================================
; BANK 2 ENTRY POINT
; =============================================================================
Bank2Entry:
        ; Switch back to bank 0 for main loop
        lda BANK0
        jmp Reset               ; Jump to reset in bank 0

; =============================================================================
; SINE TABLE (256 entries, -127 to +127 scaled)
; Index 0 = 0 degrees, 64 = 90 degrees, 128 = 180 degrees, 192 = 270 degrees
; Values are signed: negative values use two's complement
; =============================================================================
SinTable:
        ; 0-15 degrees (indices 0-10)
        .byte   0,   3,   6,   9,  12,  15,  18,  21
        .byte  24,  27,  30,  33,  36,  39,  42,  45
        ; 16-31 degrees (indices 11-21)
        .byte  48,  51,  54,  57,  59,  62,  65,  67
        .byte  70,  73,  75,  78,  80,  82,  85,  87
        ; 32-47 degrees (indices 22-32)
        .byte  89,  91,  94,  96,  98, 100, 102, 103
        .byte 105, 107, 108, 110, 112, 113, 114, 116
        ; 48-63 degrees (indices 33-43)
        .byte 117, 118, 119, 120, 121, 122, 123, 124
        .byte 124, 125, 126, 126, 126, 127, 127, 127
        ; 64-79 degrees (90 deg peak, indices 44-54)
        .byte 127, 127, 127, 127, 126, 126, 126, 125
        .byte 124, 124, 123, 122, 121, 120, 119, 118
        ; 80-95 degrees (indices 55-65)
        .byte 117, 116, 114, 113, 112, 110, 108, 107
        .byte 105, 103, 102, 100,  98,  96,  94,  91
        ; 96-111 degrees (indices 66-76)
        .byte  89,  87,  85,  82,  80,  78,  75,  73
        .byte  70,  67,  65,  62,  59,  57,  54,  51
        ; 112-127 degrees (indices 77-87)
        .byte  48,  45,  42,  39,  36,  33,  30,  27
        .byte  24,  21,  18,  15,  12,   9,   6,   3
        ; 128-143 degrees (180 deg, going negative)
        .byte   0,  <(-3),  <(-6),  <(-9), <(-12), <(-15), <(-18), <(-21)
        .byte <(-24), <(-27), <(-30), <(-33), <(-36), <(-39), <(-42), <(-45)
        ; 144-159 degrees
        .byte <(-48), <(-51), <(-54), <(-57), <(-59), <(-62), <(-65), <(-67)
        .byte <(-70), <(-73), <(-75), <(-78), <(-80), <(-82), <(-85), <(-87)
        ; 160-175 degrees
        .byte <(-89), <(-91), <(-94), <(-96), <(-98), <(-100), <(-102), <(-103)
        .byte <(-105), <(-107), <(-108), <(-110), <(-112), <(-113), <(-114), <(-116)
        ; 176-191 degrees
        .byte <(-117), <(-118), <(-119), <(-120), <(-121), <(-122), <(-123), <(-124)
        .byte <(-124), <(-125), <(-126), <(-126), <(-126), <(-127), <(-127), <(-127)
        ; 192-207 degrees (270 deg trough)
        .byte <(-127), <(-127), <(-127), <(-127), <(-126), <(-126), <(-126), <(-125)
        .byte <(-124), <(-124), <(-123), <(-122), <(-121), <(-120), <(-119), <(-118)
        ; 208-223 degrees
        .byte <(-117), <(-116), <(-114), <(-113), <(-112), <(-110), <(-108), <(-107)
        .byte <(-105), <(-103), <(-102), <(-100), <(-98), <(-96), <(-94), <(-91)
        ; 224-239 degrees
        .byte <(-89), <(-87), <(-85), <(-82), <(-80), <(-78), <(-75), <(-73)
        .byte <(-70), <(-67), <(-65), <(-62), <(-59), <(-57), <(-54), <(-51)
        ; 240-255 degrees (back to 0)
        .byte <(-48), <(-45), <(-42), <(-39), <(-36), <(-33), <(-30), <(-27)
        .byte <(-24), <(-21), <(-18), <(-15), <(-12), <(-9), <(-6), <(-3)

; =============================================================================
; COSINE TABLE (256 entries)
; cos(x) = sin(x + 64), so we just offset into the sine table
; =============================================================================
CosTable:
        ; 0-15 (cos starts at 127)
        .byte 127, 127, 127, 127, 126, 126, 126, 125
        .byte 124, 124, 123, 122, 121, 120, 119, 118
        ; 16-31
        .byte 117, 116, 114, 113, 112, 110, 108, 107
        .byte 105, 103, 102, 100,  98,  96,  94,  91
        ; 32-47
        .byte  89,  87,  85,  82,  80,  78,  75,  73
        .byte  70,  67,  65,  62,  59,  57,  54,  51
        ; 48-63
        .byte  48,  45,  42,  39,  36,  33,  30,  27
        .byte  24,  21,  18,  15,  12,   9,   6,   3
        ; 64-79 (cos goes to 0 and negative)
        .byte   0,  <(-3),  <(-6),  <(-9), <(-12), <(-15), <(-18), <(-21)
        .byte <(-24), <(-27), <(-30), <(-33), <(-36), <(-39), <(-42), <(-45)
        ; 80-95
        .byte <(-48), <(-51), <(-54), <(-57), <(-59), <(-62), <(-65), <(-67)
        .byte <(-70), <(-73), <(-75), <(-78), <(-80), <(-82), <(-85), <(-87)
        ; 96-111
        .byte <(-89), <(-91), <(-94), <(-96), <(-98), <(-100), <(-102), <(-103)
        .byte <(-105), <(-107), <(-108), <(-110), <(-112), <(-113), <(-114), <(-116)
        ; 112-127
        .byte <(-117), <(-118), <(-119), <(-120), <(-121), <(-122), <(-123), <(-124)
        .byte <(-124), <(-125), <(-126), <(-126), <(-126), <(-127), <(-127), <(-127)
        ; 128-143 (cos at minimum)
        .byte <(-127), <(-127), <(-127), <(-127), <(-126), <(-126), <(-126), <(-125)
        .byte <(-124), <(-124), <(-123), <(-122), <(-121), <(-120), <(-119), <(-118)
        ; 144-159
        .byte <(-117), <(-116), <(-114), <(-113), <(-112), <(-110), <(-108), <(-107)
        .byte <(-105), <(-103), <(-102), <(-100), <(-98), <(-96), <(-94), <(-91)
        ; 160-175
        .byte <(-89), <(-87), <(-85), <(-82), <(-80), <(-78), <(-75), <(-73)
        .byte <(-70), <(-67), <(-65), <(-62), <(-59), <(-57), <(-54), <(-51)
        ; 176-191
        .byte <(-48), <(-45), <(-42), <(-39), <(-36), <(-33), <(-30), <(-27)
        .byte <(-24), <(-21), <(-18), <(-15), <(-12), <(-9), <(-6), <(-3)
        ; 192-207 (cos goes back positive)
        .byte   0,   3,   6,   9,  12,  15,  18,  21
        .byte  24,  27,  30,  33,  36,  39,  42,  45
        ; 208-223
        .byte  48,  51,  54,  57,  59,  62,  65,  67
        .byte  70,  73,  75,  78,  80,  82,  85,  87
        ; 224-239
        .byte  89,  91,  94,  96,  98, 100, 102, 103
        .byte 105, 107, 108, 110, 112, 113, 114, 116
        ; 240-255 (back to peak)
        .byte 117, 118, 119, 120, 121, 122, 123, 124
        .byte 124, 125, 126, 126, 126, 127, 127, 127

; =============================================================================
; ATAN2 APPROXIMATION TABLE
; For converting relative X,Y to angle
; Index by (Y/X ratio), returns angle 0-63 (0-90 degrees)
; =============================================================================
AtanTable:
        .byte   0,  1,  2,  3,  4,  5,  6,  7
        .byte   8,  9, 10, 11, 12, 13, 14, 14
        .byte  15, 16, 17, 17, 18, 19, 19, 20
        .byte  21, 21, 22, 22, 23, 24, 24, 25
        .byte  25, 26, 26, 27, 27, 28, 28, 29
        .byte  29, 30, 30, 30, 31, 31, 32, 32
        .byte  32, 33, 33, 33, 34, 34, 34, 35
        .byte  35, 35, 36, 36, 36, 36, 37, 37

; =============================================================================
; MULTIPLY TABLE (8x8 -> 16 bit, lower 64 values)
; For speed calculation
; =============================================================================
MultiplyTable:
        ; Squares table: (a+b)^2/4 method
        ; For n from 0-63: n*n/4
        .byte   0,  0,  1,  2,  4,  6,  9, 12
        .byte  16, 20, 25, 30, 36, 42, 49, 56
        .byte  64, 72, 81, 90,100,110,121,132
        .byte 144,156,169,182,196,210,225,240
        .byte   0, 16, 33, 50, 68, 86,105,124  ; 32-39 (values > 255 wrap)
        .byte 144,164,185,206,228,250, 17, 40  ; 40-47
        .byte  64, 88,113,138,164,190,217,244  ; 48-55
        .byte  16, 44, 73,102,132,162,193,224  ; 56-63

; =============================================================================
; DIVIDE TABLE (256/n for n=1-32)
; For perspective calculations
; =============================================================================
DivideTable:
        .byte 255       ; 256/1 = 256, clamped to 255
        .byte 128       ; 256/2
        .byte  85       ; 256/3
        .byte  64       ; 256/4
        .byte  51       ; 256/5
        .byte  42       ; 256/6
        .byte  36       ; 256/7
        .byte  32       ; 256/8
        .byte  28       ; 256/9
        .byte  25       ; 256/10
        .byte  23       ; 256/11
        .byte  21       ; 256/12
        .byte  19       ; 256/13
        .byte  18       ; 256/14
        .byte  17       ; 256/15
        .byte  16       ; 256/16
        .byte  15       ; 256/17
        .byte  14       ; 256/18
        .byte  13       ; 256/19
        .byte  12       ; 256/20
        .byte  12       ; 256/21
        .byte  11       ; 256/22
        .byte  11       ; 256/23
        .byte  10       ; 256/24
        .byte  10       ; 256/25
        .byte   9       ; 256/26
        .byte   9       ; 256/27
        .byte   9       ; 256/28
        .byte   8       ; 256/29
        .byte   8       ; 256/30
        .byte   8       ; 256/31
        .byte   8       ; 256/32

; =============================================================================
; DEPTH SCALE TABLE
; Maps distance (0-31) to sprite scaling factor
; =============================================================================
DepthScaleTable:
        .byte   0       ; Distance 0 (too close - not rendered)
        .byte 255       ; Distance 1 (very close)
        .byte 200       ; Distance 2
        .byte 160       ; Distance 3
        .byte 128       ; Distance 4
        .byte 100       ; Distance 5
        .byte  80       ; Distance 6
        .byte  64       ; Distance 7
        .byte  52       ; Distance 8
        .byte  44       ; Distance 9
        .byte  38       ; Distance 10
        .byte  32       ; Distance 11
        .byte  28       ; Distance 12
        .byte  24       ; Distance 13
        .byte  21       ; Distance 14
        .byte  18       ; Distance 15
        .byte  16       ; Distance 16
        .byte  14       ; Distance 17
        .byte  12       ; Distance 18
        .byte  11       ; Distance 19
        .byte  10       ; Distance 20
        .byte   9       ; Distance 21
        .byte   8       ; Distance 22
        .byte   7       ; Distance 23
        .byte   6       ; Distance 24
        .byte   6       ; Distance 25
        .byte   5       ; Distance 26
        .byte   5       ; Distance 27
        .byte   4       ; Distance 28
        .byte   4       ; Distance 29
        .byte   4       ; Distance 30
        .byte   3       ; Distance 31

; =============================================================================
; LIDAR FILL RATE TABLE
; Maps distance (1-31) to fill rate per frame
; Closer = faster fill
; =============================================================================
LidarRateTable:
        .byte 255       ; Distance 0 (not used)
        .byte 128       ; Distance 1 - very fast
        .byte  64       ; Distance 2
        .byte  42       ; Distance 3
        .byte  32       ; Distance 4
        .byte  25       ; Distance 5
        .byte  21       ; Distance 6
        .byte  18       ; Distance 7
        .byte  16       ; Distance 8
        .byte  14       ; Distance 9
        .byte  12       ; Distance 10
        .byte  11       ; Distance 11
        .byte  10       ; Distance 12
        .byte   9       ; Distance 13
        .byte   9       ; Distance 14
        .byte   8       ; Distance 15
        .byte   8       ; Distance 16 (half map)
        .byte   7       ; Distance 17
        .byte   7       ; Distance 18
        .byte   6       ; Distance 19
        .byte   6       ; Distance 20
        .byte   5       ; Distance 21
        .byte   5       ; Distance 22
        .byte   5       ; Distance 23
        .byte   4       ; Distance 24
        .byte   4       ; Distance 25
        .byte   4       ; Distance 26
        .byte   4       ; Distance 27
        .byte   3       ; Distance 28
        .byte   3       ; Distance 29
        .byte   3       ; Distance 30
        .byte   3       ; Distance 31

; =============================================================================
; NUSIZ VALUES FOR SPRITE SCALING
; Based on depth, select appropriate NUSIZ value
; =============================================================================
NusizByDepth:
        .byte $05       ; Depth 0-3:  Double-size
        .byte $05       ; 
        .byte $05       ;
        .byte $05       ;
        .byte $00       ; Depth 4-7:  Normal size
        .byte $00       ;
        .byte $00       ;
        .byte $00       ;
        .byte $00       ; Depth 8-15: Normal (could use quad for smaller)
        .byte $00
        .byte $00
        .byte $00
        .byte $00
        .byte $00
        .byte $00
        .byte $00

; =============================================================================
; ADVANCED MATH ROUTINES
; =============================================================================

; -----------------------------------------------------------------------------
; Calculate angle from relative position
; Input: mathTemp = relX, mathTemp+1 = relY
; Output: A = angle (0-255)
; -----------------------------------------------------------------------------
CalcAngle:
        ; Determine quadrant
        lda mathTemp            ; relX
        sta mathTemp+2          ; Save sign
        bpl .posX
        ; Negative X - take absolute value
        eor #$FF
        clc
        adc #1
        sta mathTemp
.posX:
        lda mathTemp+1          ; relY
        sta mathTemp+3          ; Save sign
        bpl .posY
        ; Negative Y
        eor #$FF
        clc
        adc #1
        sta mathTemp+1
.posY:
        ; Now both are positive
        ; Calculate ratio and look up in atan table
        ; Simplified: compare magnitudes
        lda mathTemp            ; |relX|
        cmp mathTemp+1          ; |relY|
        bcs .xGreater
        
        ; Y >= X, angle is 45-90 range
        ; ratio = X/Y
        ldx mathTemp+1
        beq .zeroDiv
        lda mathTemp
        jsr DivideSmall
        tax
        lda AtanTable,X
        clc
        adc #32                 ; Add 45 degrees
        jmp .applyQuadrant

.xGreater:
        ; X > Y, angle is 0-45 range
        ; ratio = Y/X
        ldx mathTemp
        beq .zeroDiv
        lda mathTemp+1
        jsr DivideSmall
        tax
        lda AtanTable,X
        jmp .applyQuadrant

.zeroDiv:
        lda #0

.applyQuadrant:
        ; Apply quadrant based on original signs
        ; mathTemp+2 = X sign, mathTemp+3 = Y sign
        ldx mathTemp+2
        bmi .negXQuad
        ldx mathTemp+3
        bmi .quadrant4
        ; Quadrant 1: angle as-is (0-63)
        rts

.quadrant4:
        ; Quadrant 4: 256 - angle
        sta mathTemp
        lda #0
        sec
        sbc mathTemp
        rts

.negXQuad:
        ldx mathTemp+3
        bmi .quadrant3
        ; Quadrant 2: 128 - angle
        sta mathTemp
        lda #128
        sec
        sbc mathTemp
        rts

.quadrant3:
        ; Quadrant 3: 128 + angle
        clc
        adc #128
        rts

; -----------------------------------------------------------------------------
; Small divide: A / X -> A (result clamped to 63)
; -----------------------------------------------------------------------------
DivideSmall:
        cpx #0
        beq .divZero
        stx mathTemp+4
        ldx #0
        sec
.divLoop:
        sbc mathTemp+4
        bcc .divDone
        inx
        cpx #64
        bcc .divLoop
.divDone:
        txa
        cmp #64
        bcc .divOk
        lda #63
.divOk:
        rts
.divZero:
        lda #63
        rts

; -----------------------------------------------------------------------------
; Calculate distance (Manhattan approximation)
; Input: mathTemp = relX (signed), mathTemp+1 = relY (signed)
; Output: A = approximate distance
; -----------------------------------------------------------------------------
CalcDistance:
        ; Get absolute values
        lda mathTemp
        bpl .posDistX
        eor #$FF
        clc
        adc #1
.posDistX:
        sta mathTemp+2          ; |X|
        
        lda mathTemp+1
        bpl .posDistY
        eor #$FF
        clc
        adc #1
.posDistY:
        ; Distance ~= max(|X|,|Y|) + min(|X|,|Y|)/2
        cmp mathTemp+2
        bcs .yGreater
        ; X >= Y
        lsr                     ; Y/2
        clc
        adc mathTemp+2          ; + X
        rts

.yGreater:
        sta mathTemp+3
        lda mathTemp+2
        lsr                     ; X/2
        clc
        adc mathTemp+3          ; + Y
        rts

; -----------------------------------------------------------------------------
; Check if angle is within arc
; Input: A = angle to test, X = center angle, Y = half-arc width
; Output: Carry set if within arc
; -----------------------------------------------------------------------------
CheckInArc:
        ; Calculate difference
        stx mathTemp
        sec
        sbc mathTemp
        ; Get absolute value of difference
        bpl .posDiff
        eor #$FF
        clc
        adc #1
.posDiff:
        ; Handle wrap-around (if diff > 128, use 256-diff)
        cmp #128
        bcc .noWrap
        eor #$FF
        clc
        adc #1
.noWrap:
        ; Compare with arc width
        sty mathTemp
        cmp mathTemp
        ; Carry clear if A < Y (within arc)
        bcc .inArc
        clc                     ; Not in arc
        rts
.inArc:
        sec                     ; In arc
        rts

; =============================================================================
; 3D PROJECTION ROUTINE
; Projects a world point to screen coordinates
; =============================================================================

; Input: Tank index in X
; Uses tank position and player position from RAM
; Output: Updates tankScreenX, tankScreenY, tankVisible for that tank
ProjectTank:
        ; Calculate relative position
        lda tankX+1,X           ; Tank X high byte
        sec
        sbc playerX+1           ; - Player X high byte
        sta mathTemp            ; Relative X
        
        lda tankY+1,X
        sec
        sbc playerY+1
        sta mathTemp+1          ; Relative Y
        
        ; Apply cockpit heading rotation
        ; newX = relX * cos(heading) - relY * sin(heading)
        ; newY = relX * sin(heading) + relY * cos(heading)
        ; Simplified version: just offset by heading
        
        lda legHeading
        clc
        adc torsoOffset         ; Total cockpit heading
        tay                     ; Y = heading
        
        ; Get sin and cos
        lda SinTable,Y
        sta mathTemp+2          ; sin
        lda CosTable,Y
        sta mathTemp+3          ; cos
        
        ; Simplified rotation (approximation)
        ; For demo, just translate directly
        
        ; Check if in front of player (relY should be positive for "forward")
        lda mathTemp+1
        bmi .behindPlayer
        beq .behindPlayer       ; Too close
        
        ; Calculate screen X
        ; screenX = 80 + relX * scale / relY
        lda mathTemp            ; relX
        sta mathTemp+4
        
        ; Scale by inverse of distance
        ldx mathTemp+1          ; relY = distance
        cpx #32
        bcc .validDist
        ldx #31                 ; Clamp distance
.validDist:
        lda DivideTable,X       ; Get 256/distance
        sta mathTemp+5          ; Scale factor
        
        ; Multiply relX by scale (simplified: shift)
        lda mathTemp+4
        bpl .posRelX
        ; Negative relX
        eor #$FF
        clc
        adc #1
        lsr
        lsr                     ; /4 for reasonable spread
        eor #$FF
        clc
        adc #1
        jmp .addCenterX
.posRelX:
        lsr
        lsr
.addCenterX:
        clc
        adc #80                 ; Center of screen
        bcc .clampX
        lda #159                ; Clamp to right edge
.clampX:
        cmp #160
        bcc .storeX
        lda #0                  ; Off left edge
        jmp .setInvisible
.storeX:
        ldx tempX               ; Restore tank index
        sta tankScreenX,X
        
        ; Calculate screen Y
        ; screenY = horizon - height/distance
        lda #HORIZON_LINE
        clc
        adc #20                 ; Base Y below horizon for ground units
        sec
        sbc mathTemp+5          ; - scale (closer = higher on screen...wait, lower Y)
        bcs .validY
        lda #0
.validY:
        sta tankScreenY,X
        
        ; Mark visible
        lda #1
        sta tankVisible,X
        rts

.behindPlayer:
.setInvisible:
        ldx tempX
        lda #0
        sta tankVisible,X
        rts

; =============================================================================
; BANK 2 PADDING AND VECTORS
; =============================================================================
        ECHO    "---- Bank 2 ----"
        ECHO    "Code ends at:", *
        ECHO    "Bytes used:", (* - $E000)
        ECHO    "Bytes free:", ($EFFA - *)

        ORG     $EFFA
        RORG    $EFFA

        .word   Reset           ; NMI
        .word   Reset           ; Reset
        .word   Reset           ; IRQ

; =============================================================================
; End of bank2_logic.asm
; =============================================================================

