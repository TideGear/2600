; =============================================================================
; MECHA SIMULATOR
; Atari 2600 Assembly Game (16K F4 Bank-Switching)
; =============================================================================
; 
; A first-person mecha cockpit simulator inspired by Star Raiders.
; 
; Features:
; - First-person cockpit view with heading compass
; - 6-speed transmission (R2, R1, N, 1, 2, 3)
; - Independent leg (movement) and torso (view) headings
; - 4 enemy tanks on a 32x32 world grid
; - LIDAR detection system
; - View bobbing and audio feedback
; 
; Controls:
; - Up/Down: Shift gears
; - Left/Right: Turn legs (movement direction)
; - Button + Left/Right: Twist torso (view direction)
; - Double-tap Button: Toggle pause
;
; Build with DASM:
;   dasm mecha.asm -f3 -omecha.bin
;
; =============================================================================

        PROCESSOR 6502

; =============================================================================
; INCLUDE FILES
; =============================================================================
        INCLUDE "constants.asm"
        INCLUDE "ram.asm"
        INCLUDE "macros.asm"

; =============================================================================
; NOTE: This is currently a 4K build. The bank1/2/3 files contain expansion
; content for future 16K F4 bank-switched builds.
; =============================================================================

; =============================================================================
; BANK 0 - Main Kernel (Always starts here on reset)
; This is the primary bank containing the display kernel
; =============================================================================

        SEG     BANK0_CODE
        ORG     $F000
        RORG    $F000

; =============================================================================
; RESET ENTRY POINT
; =============================================================================
Reset:
        CLEAN_START
        
        ; Initialize game state
        lda #STATE_TITLE
        sta gameState
        
        ; Initialize random seed with non-zero value
        lda #$A7
        sta randomSeed
        lda #$5C
        sta randomSeed+1
        
        ; Start at title screen
        jmp MainLoop

; =============================================================================
; MAIN GAME LOOP (in Bank 0)
; Produces exactly 262 scanlines per frame (NTSC)
; Uses timer for VBLANK to handle variable-time game logic
; =============================================================================
MainLoop:
        ; === VERTICAL SYNC (3 scanlines) ===
        lda #2
        sta WSYNC               ; Line 1
        sta VSYNC               ; VSYNC on
        sta WSYNC               ; Line 2
        sta WSYNC               ; Line 3
        lda #0
        sta VSYNC               ; VSYNC off
        
        ; === VERTICAL BLANK (37 scanlines) ===
        ; Use timer-based approach: game logic runs while timer counts
        ; Timer ensures consistent end point regardless of logic time
        sta WSYNC               ; Sync to known starting point
        lda #2
        sta VBLANK              ; Blank display
        
        ; Set timer for ~35 scanlines (leaving 2 for sync WSYNCs)
        ; 35 * 76 / 64 = 41.5, use 41
        lda #41
        sta TIM64T
        
        ; Do lightweight game logic (input, audio, bobbing)
        jsr ProcessInput
        jsr UpdateAudio
        
        ; Wait for timer - this bounds the lightweight logic
.waitVBlank1:
        lda INTIM
        bne .waitVBlank1
        
        ; Final WSYNC ensures consistent end of VBLANK
        sta WSYNC
        lda #0
        sta VBLANK              ; Turn on display
        
        ; === VISIBLE FRAME (192 scanlines) ===
        ; Position sprites (2 lines)
        jsr PrepareFrame
        
        ; Draw 190 scanlines based on game state
        lda gameState
        cmp #STATE_TITLE
        beq .drawTitle
        cmp #STATE_PAUSED  
        beq .drawPause
        cmp #STATE_GAMEOVER
        beq .drawGameOver
        
        ; Default: Playing state
        jsr DrawGameScreen
        jmp .overscan
        
.drawTitle:
        jsr DrawTitleScreen
        jmp .overscan
        
.drawPause:
        jsr DrawPauseScreen
        jmp .overscan
        
.drawGameOver:
        jsr DrawGameOverScreen
        
.overscan:
        ; === OVERSCAN (30 scanlines) ===
        ; Do heavier game logic here where timing is less critical
        sta WSYNC
        lda #2
        sta VBLANK              ; Turn off display
        
        ; Set timer for overscan
        lda #36                 ; ~30 lines
        sta TIM64T
        
        ; Heavy game logic during overscan (tank projection, etc.)
        jsr UpdateGame
        
        ; Frame counter
        inc frameCounter
        bne .noFrameHigh
        inc frameCounter+1
.noFrameHigh:
        
        ; Wait for overscan timer
.waitOverscan:
        lda INTIM
        bne .waitOverscan
        
        ; Loop forever
        jmp MainLoop

; =============================================================================
; INPUT PROCESSING
; =============================================================================
ProcessInput:
        ; Save previous joystick state
        lda joyState
        sta joyPrev
        lda buttonState
        sta buttonPrev
        
        ; Read current joystick
        lda SWCHA
        sta joyState
        
        ; Read fire button (active low, bit 7)
        lda INPT4
        sta buttonState
        
        ; Check for double-tap pause
        jsr CheckDoubleTap
        
        ; Skip other input if not playing
        lda gameState
        cmp #STATE_PLAYING
        beq .processGameInput
        
        ; Title/GameOver: check for start
        cmp #STATE_TITLE
        beq .checkStart
        cmp #STATE_GAMEOVER
        beq .checkStart
        rts

.checkStart:
        ; Button pressed (bit 7 = 0 when pressed)
        lda buttonState
        bmi .noStart
        lda buttonPrev
        bpl .noStart            ; Was already pressed
        ; Start game!
        jsr InitGame
.noStart:
        rts

.processGameInput:
        ; --- GEAR SHIFTING ---
        ; Check for UP press (shift up)
        lda joyState
        and #MASK_UP
        bne .checkDown
        lda joyPrev
        and #MASK_UP
        beq .checkDown          ; Already pressed
        ; UP edge - shift up
        lda currentGear
        cmp #GEAR_3
        bcs .checkDown          ; At max
        inc currentGear
        jmp .checkTurn

.checkDown:
        lda joyState
        and #MASK_DOWN
        bne .checkTurn
        lda joyPrev
        and #MASK_DOWN
        beq .checkTurn          ; Already pressed
        ; DOWN edge - shift down
        lda currentGear
        beq .checkTurn          ; At min (R2)
        dec currentGear

.checkTurn:
        ; --- TURNING ---
        ; Check if button held for torso twist
        lda buttonState
        bmi .normalTurn         ; Button NOT pressed (bit 7 set)
        
        ; Button held - torso twist mode
        lda joyState
        and #MASK_LEFT
        bne .checkTwistRight
        ; Twist left
        lda torsoOffset
        cmp #<(-TORSO_MAX)
        beq .inputDone
        dec torsoOffset
        dec torsoOffset         ; 2 units per frame
        jmp .inputDone

.checkTwistRight:
        lda joyState
        and #MASK_RIGHT
        bne .inputDone
        ; Twist right
        lda torsoOffset
        cmp #TORSO_MAX
        beq .inputDone
        inc torsoOffset
        inc torsoOffset
        jmp .inputDone

.normalTurn:
        ; Normal leg turning
        lda joyState
        and #MASK_LEFT
        bne .checkRight
        ; Turn left
        dec legHeading
        dec legHeading
        dec legHeading          ; 3 units per frame for responsive turning
        jmp .inputDone

.checkRight:
        lda joyState
        and #MASK_RIGHT
        bne .inputDone
        ; Turn right
        inc legHeading
        inc legHeading
        inc legHeading

.inputDone:
        rts

; =============================================================================
; DOUBLE-TAP DETECTION
; =============================================================================
CheckDoubleTap:
        ; Decrement timer
        lda doubleTapTimer
        beq .checkTap
        dec doubleTapTimer

.checkTap:
        ; Check for button release edge
        lda buttonPrev
        bmi .noTap              ; Wasn't pressed
        lda buttonState
        bpl .noTap              ; Still pressed
        
        ; Button just released
        lda doubleTapTimer
        beq .firstTap
        
        ; Second tap - toggle pause!
        lda gameState
        cmp #STATE_PLAYING
        beq .toPaused
        cmp #STATE_PAUSED
        beq .toPlaying
        rts

.toPaused:
        lda #STATE_PAUSED
        sta gameState
        lda #0
        sta doubleTapTimer
        rts

.toPlaying:
        lda #STATE_PLAYING
        sta gameState
        lda #0
        sta doubleTapTimer
        rts

.firstTap:
        lda #DOUBLETAP_WINDOW
        sta doubleTapTimer
.noTap:
        rts

; =============================================================================
; GAME UPDATE
; =============================================================================
UpdateGame:
        lda gameState
        cmp #STATE_PLAYING
        bne .noUpdate
        
        jsr UpdatePlayerPos
        jsr UpdateTanks
        jsr UpdateLIDAR
        jsr CheckBoundary
        jsr UpdateBobbing

.noUpdate:
        rts

; =============================================================================
; UPDATE PLAYER POSITION
; =============================================================================
UpdatePlayerPos:
        ; Get speed from current gear
        ldx currentGear
        lda SpeedTable,X
        beq .noMove             ; Neutral
        sta mathTemp            ; Speed (signed)
        
        ; Get heading components
        ldx legHeading
        lda CosTableSmall,X
        sta mathTemp+1          ; X component
        lda SinTableSmall,X
        sta mathTemp+2          ; Y component
        
        ; Apply speed to components
        ; Simplified: just add direction to position
        lda mathTemp
        bmi .reverseDir
        
        ; Forward: add direction
        lda playerX
        clc
        adc mathTemp+1
        sta playerX
        lda playerX+1
        adc #0
        bpl .clampXHi
        lda #0                  ; Clamp to 0
.clampXHi:
        cmp #WORLD_SIZE
        bcc .storeXHi
        lda #WORLD_SIZE-1
.storeXHi:
        sta playerX+1
        
        lda playerY
        clc
        adc mathTemp+2
        sta playerY
        lda playerY+1
        adc #0
        bpl .clampYHi
        lda #0
.clampYHi:
        cmp #WORLD_SIZE
        bcc .storeYHi
        lda #WORLD_SIZE-1
.storeYHi:
        sta playerY+1
        jmp .noMove

.reverseDir:
        ; Reverse: subtract direction
        lda playerX
        sec
        sbc mathTemp+1
        sta playerX
        lda playerX+1
        sbc #0
        bpl .storeXRev
        lda #0
.storeXRev:
        sta playerX+1
        
        lda playerY
        sec
        sbc mathTemp+2
        sta playerY
        lda playerY+1
        sbc #0
        bpl .storeYRev
        lda #0
.storeYRev:
        sta playerY+1

.noMove:
        rts

; =============================================================================
; UPDATE TANKS
; =============================================================================
UpdateTanks:
        ; Rotate tanks slowly (every N frames)
        lda frameCounter
        and #$07                ; Every 8 frames
        bne .noRotate
        
        ; Rotate all tank headings
        inc tankHeading
        inc tankHeading+1
        inc tankHeading+2
        inc tankHeading+3

.noRotate:
        ; Project ONE tank per frame to spread CPU load
        ; This reduces worst-case time from 67 scanlines to ~17 scanlines
        lda frameCounter
        and #$03                ; 0-3, cycles through tanks
        tax
        stx tempX
        jsr ProjectOneTank
        rts

; =============================================================================
; PROJECT ALL TANKS TO SCREEN COORDINATES
; =============================================================================
ProjectAllTanks:
        ; Calculate cockpit heading once (leg + torso)
        lda legHeading
        clc
        adc torsoOffset
        sta mathTemp+3          ; Store cockpit heading
        
        ; Process each tank
        ldx #0
.projectLoop:
        stx tempX               ; Save tank index
        jsr ProjectOneTank
        ldx tempX
        inx
        cpx #NUM_TANKS
        bne .projectLoop
        rts

; =============================================================================
; PROJECT ONE TANK (tank index in X)
; =============================================================================
ProjectOneTank:
        ; Get tank world position (high byte = grid cell 0-31)
        txa
        asl                     ; *2 for word index
        tay
        
        ; Calculate relative X: tankX - playerX
        lda tankX+1,Y           ; Tank X high byte (grid cell)
        sec
        sbc playerX+1           ; Player X high byte
        sta mathTemp            ; relX (signed, -31 to +31)
        
        ; Calculate relative Y: tankY - playerY  
        lda tankY+1,Y           ; Tank Y high byte
        sec
        sbc playerY+1           ; Player Y high byte
        sta mathTemp+1          ; relY (signed, -31 to +31)
        
        ; Rotate by cockpit heading
        ; rotX = relX * cos(h) + relY * sin(h)
        ; rotY = relY * cos(h) - relX * sin(h)
        
        ; Get sin/cos for cockpit heading (divide heading by 4 for 64-entry table)
        lda mathTemp+3          ; Cockpit heading (0-255)
        lsr
        lsr                     ; Divide by 4 -> 0-63
        tay
        lda SinTable64,Y
        sta mathTemp+4          ; sin(h)
        lda CosTable64,Y
        sta mathTemp+5          ; cos(h)
        
        ; Calculate rotX = relX * cos + relY * sin
        ; Using signed multiply approximation
        lda mathTemp            ; relX
        jsr SignedMulCos        ; A = relX * cos(h) / 64
        sta mathTemp+6          ; Store partial
        
        lda mathTemp+1          ; relY
        jsr SignedMulSin        ; A = relY * sin(h) / 64
        clc
        adc mathTemp+6
        sta mathTemp+6          ; rotX (scaled)
        
        ; Calculate rotY = relY * cos - relX * sin
        lda mathTemp+1          ; relY
        jsr SignedMulCos        ; A = relY * cos(h) / 64
        sta mathTemp+7          ; Store partial
        
        lda mathTemp            ; relX
        jsr SignedMulSin        ; A = relX * sin(h) / 64
        sta tempY               ; Store for subtraction
        lda mathTemp+7
        sec
        sbc tempY
        sta mathTemp+7          ; rotY (scaled)
        
        ; Check if tank is in front of player (rotY > 0)
        lda mathTemp+7          ; rotY
        bmi .tankBehind         ; Negative = behind
        beq .tankBehind         ; Zero = at player position
        
        ; Tank is in front - calculate screen position
        ; screenX = 80 + rotX * 4 (simplified perspective)
        lda mathTemp+6          ; rotX
        asl                     ; *2
        asl                     ; *4
        clc
        adc #80                 ; Center of screen
        
        ; Clamp to screen bounds
        bmi .tankOffScreen      ; Wrapped negative
        cmp #160
        bcs .tankOffScreen      ; Off right edge
        
        ; Store screen X
        ldx tempX
        sta tankScreenX,X
        
        ; Calculate screen Y
        ; screenY = HORIZON_LINE + 20 - (16 / rotY) approximately
        ; Simplified: closer tanks are lower on screen (higher Y)
        lda mathTemp+7          ; rotY (distance, 1-31 range)
        beq .tankBehind
        
        ; Use lookup table for Y position based on distance
        cmp #32
        bcc .validDist
        lda #31
.validDist:
        tay
        lda DepthToScreenY,Y
        sta tankScreenY,X
        
        ; Mark tank as visible
        lda #1
        sta tankVisible,X
        rts

.tankBehind:
.tankOffScreen:
        ldx tempX
        lda #0
        sta tankVisible,X
        rts

; =============================================================================
; SIGNED MULTIPLY BY COS (A * cos / 64)
; Input: A = signed value (-31 to +31)
; Uses: mathTemp+5 = cos value
; Output: A = result (signed)
; =============================================================================
SignedMulCos:
        sta tempY               ; Save input
        bpl .posMulCos
        ; Negative input - negate, multiply, negate result
        eor #$FF
        clc
        adc #1
        jsr .doMulCos
        eor #$FF
        clc
        adc #1
        rts
.posMulCos:
        jsr .doMulCos
        rts
.doMulCos:
        ; A = A * mathTemp+5 / 64 (unsigned)
        tax
        lda mathTemp+5          ; cos value
        bpl .cosPosVal
        ; Cos is negative
        eor #$FF
        clc
        adc #1
        sta tempY
        txa
        jsr .unsignedMul
        eor #$FF
        clc
        adc #1
        rts
.cosPosVal:
        sta tempY
        txa
        ; Fall through to unsigned multiply
        
.unsignedMul:
        ; A * tempY / 64, simple shift-add
        ; For small values, use repeated addition
        tax                     ; Multiplicand in X
        lda #0
        cpx #0
        beq .mulDone
.mulLoop:
        clc
        adc tempY
        dex
        bne .mulLoop
.mulDone:
        ; Divide by 64 (shift right 6 times)
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        rts

; =============================================================================
; SIGNED MULTIPLY BY SIN (A * sin / 64)
; Input: A = signed value
; Uses: mathTemp+4 = sin value
; =============================================================================
SignedMulSin:
        sta tempY               ; Save input  
        bpl .posMulSin
        ; Negative input
        eor #$FF
        clc
        adc #1
        jsr .doMulSin
        eor #$FF
        clc
        adc #1
        rts
.posMulSin:
        jsr .doMulSin
        rts
.doMulSin:
        tax
        lda mathTemp+4          ; sin value
        bpl .sinPosVal
        ; Sin is negative
        eor #$FF
        clc
        adc #1
        sta tempY
        txa
        jsr .unsignedMul
        eor #$FF
        clc
        adc #1
        rts
.sinPosVal:
        sta tempY
        txa
        jmp .unsignedMul

; =============================================================================
; UPDATE LIDAR
; =============================================================================
UpdateLIDAR:
        ; Check each tank for LIDAR detection
        ; Simplified: slowly fill bar for demo
        ldx #NUM_TANKS-1
.lidarLoop:
        ; Check if player in tank's field of view
        ; (Simplified check)
        lda tankHeading,X
        sec
        sbc legHeading
        bpl .posAngle
        eor #$FF
        clc
        adc #1
.posAngle:
        cmp #LIDAR_ARC          ; Within detection arc?
        bcs .nextTank
        
        ; Player detected - fill LIDAR bar
        lda lidarFill
        cmp #LIDAR_MAX
        bcs .nextTank
        inc lidarFill

.nextTank:
        dex
        bpl .lidarLoop
        
        ; Decay LIDAR when looking at tanks (crosshair break)
        ; Simplified: decay over time
        lda frameCounter
        and #$0F
        bne .noDecay
        lda lidarFill
        beq .noDecay
        dec lidarFill
.noDecay:
        rts

; =============================================================================
; CHECK BOUNDARY (Off-map countdown)
; =============================================================================
CheckBoundary:
        ; Check if player is outside 32x32 grid
        lda playerX+1
        cmp #WORLD_SIZE
        bcs .offMap
        lda playerY+1
        cmp #WORLD_SIZE
        bcs .offMap
        
        ; On map - reset countdown
        lda #COUNTDOWN_MAX
        sta offmapCountdown
        rts

.offMap:
        ; Off map - run countdown
        inc offmapCounter
        lda offmapCounter
        cmp #60                 ; Every 60 frames = 1 second
        bcc .noCountdown
        
        lda #0
        sta offmapCounter
        lda offmapCountdown
        beq .gameOver
        dec offmapCountdown
        rts

.noCountdown:
        rts

.gameOver:
        lda #STATE_GAMEOVER
        sta gameState
        rts

; =============================================================================
; UPDATE BOBBING
; =============================================================================
UpdateBobbing:
        lda currentGear
        cmp #GEAR_N
        beq .noBob
        cmp #GEAR_3
        beq .noBob              ; Skating = no bob
        
        ; Save previous phase for zero-crossing detection
        lda bobPhase
        sta tempY               ; Previous phase
        
        ; Advance bob phase (uniform rate for consistent footfalls)
        ldx currentGear
        lda BobRateTable,X
        clc
        adc bobPhase
        sta bobPhase
        
        ; Calculate offset from phase using sine lookup
        lda bobPhase
        lsr
        lsr
        lsr
        lsr                     ; /16 -> 0-15 index
        and #$0F
        tax
        lda BobOffsetTable,X
        sta bobOffset
        
        ; Check for stomp sound trigger at phase zero-crossing
        ; Trigger when phase wraps from 255->0 or crosses 128
        ; This ensures even timing regardless of frame rate
        lda tempY               ; Previous phase
        and #$80                ; Was in upper half?
        sta tempX
        lda bobPhase
        and #$80                ; Now in upper half?
        cmp tempX
        beq .noStomp            ; No transition
        
        ; Phase crossed 0 or 128 - trigger stomp!
        lda stompTimer
        bne .noStomp            ; Already playing
        lda #10
        sta stompTimer
.noStomp:
        rts

.noBob:
        lda #0
        sta bobOffset
        sta bobPhase
        rts

; =============================================================================
; PREPARE FRAME - Position sprites (exactly 2 scanlines always)
; Called at start of visible frame for consistent timing
; INLINE positioning - subroutine calls break cycle-critical timing!
; =============================================================================
PrepareFrame:
        lda gameState
        cmp #STATE_PLAYING
        beq .prepPlaying
        cmp #STATE_PAUSED
        beq .prepPaused
        
        ; Title/GameOver: still need 2 WSYNCs for timing consistency
        sta WSYNC
        sta WSYNC
        rts

.prepPlaying:
        ; Calculate cockpit heading for compass (do before timing-critical section)
        lda legHeading
        clc
        adc torsoOffset
        sta tempAngle
        lsr
        lsr
        lsr
        lsr
        lsr                     ; /32
        and #$07
        sta compassOffset
        
        ; Position P0 at center (X=76) for single compass letter
        sta WSYNC               ; Line 1
        lda #76                 ; 2 cycles - center of screen
        sec                     ; 2 cycles
.posP0a:
        sbc #15                 ; 2 cycles
        bcs .posP0a             ; 3/2 cycles
        eor #$07
        asl
        asl
        asl
        asl
        sta HMP0
        sta RESP0
        
        ; Line 2 - just sync, no second sprite needed
        sta WSYNC
        sta HMOVE
        rts

.prepPaused:
        ; Pre-calculate positions before timing-critical section
        lda playerX+1           ; Grid cell (0-31)
        asl                     ; *2
        clc
        adc #48                 ; Map left edge
        sta tempX
        
        lda tankX+1
        asl
        clc
        adc #48
        sta tempY
        
        ; Position P0 at player map X (INLINE)
        sta WSYNC               ; Line 1
        lda tempX               ; 3 cycles (zeropage)
        sec                     ; 2 cycles
.posP0b:
        sbc #15
        bcs .posP0b
        eor #$07
        asl
        asl
        asl
        asl
        sta HMP0
        sta RESP0
        
        ; Position P1 at tank map X (INLINE)
        sta WSYNC               ; Line 2
        lda tempY               ; 3 cycles
        sec                     ; 2 cycles
.posP1b:
        sbc #15
        bcs .posP1b
        eor #$07
        asl
        asl
        asl
        asl
        sta HMP1
        sta RESP1
        sta HMOVE
        rts

; =============================================================================
; UPDATE AUDIO
; =============================================================================
UpdateAudio:
        ; Channel 0: Engine hum
        lda #6                  ; Rumble tone
        sta AUDC0
        ldx currentGear
        lda EnginePitchTbl,X
        sta AUDF0
        lda #8
        sta AUDV0
        
        ; Channel 1: Stomp or skate
        lda stompTimer
        beq .checkSkate
        dec stompTimer
        ; Stomp sound
        lda #8                  ; Noise
        sta AUDC1
        lda #6
        sta AUDF1
        lda stompTimer
        sta AUDV1
        rts

.checkSkate:
        lda currentGear
        cmp #GEAR_3
        bne .silentCh1
        ; Skate whine
        lda #4                  ; Pure tone
        sta AUDC1
        lda #15
        sta AUDF1
        lda #5
        sta AUDV1
        rts

.silentCh1:
        lda #0
        sta AUDV1
        rts

; =============================================================================
; DRAW GAME SCREEN
; =============================================================================
DrawGameScreen:
        jsr DrawCompassBar
        jsr DrawStatusBars
        jsr DrawMainView
        jsr DrawCockpit
        rts

; =============================================================================
; DRAW COMPASS BAR (10 lines exactly)
; Shows single centered direction letter with scrolling tick marks
; =============================================================================
DrawCompassBar:
        lda #COL_COMPASS_BG
        sta COLUBK
        lda #COL_WHITE
        sta COLUP0
        sta COLUPF              ; White tick marks
        
        ; Pre-calculate tick mark index from heading
        lda legHeading
        clc
        adc torsoOffset
        lsr
        lsr
        lsr                     ; /8 for tick mark position
        and #$1F
        sta tempAngle           ; Store tick index
        
        ; Draw the compass bar with direction letter and tick marks
        ldx #0                  ; Line counter
.compassLoop:
        sta WSYNC
        
        ; Alternating stripe background
        txa
        and #$01
        beq .darkStripe
        lda #COL_COMPASS_BG
        bne .setStripe
.darkStripe:
        lda #COL_DARKGREY
.setStripe:
        sta COLUBK
        
        ; Draw tick marks (scrolling dots based on heading)
        ldy tempAngle
        lda CompassPF1Data,Y
        sta PF1
        lda CompassPF2Data,Y
        sta PF2
        
        ; Draw direction letter (lines 0-7 only)
        cpx #8
        bcs .noLetter
        
        ldy compassOffset
        lda DirLetterPtrLo,Y
        sta tempPtr
        lda DirLetterPtrHi,Y
        sta tempPtr+1
        
        txa
        tay
        lda (tempPtr),Y
        sta GRP0
        jmp .nextCompassLine

.noLetter:
        lda #0
        sta GRP0

.nextCompassLine:
        inx
        cpx #10
        bne .compassLoop
        
        ; Clear playfield and sprite
        lda #0
        sta PF1
        sta PF2
        sta GRP0
        rts

; =============================================================================
; DRAW STATUS BARS (6 lines)
; =============================================================================
DrawStatusBars:
        ; LIDAR bar (red, 3 lines)
        lda #COL_BLACK
        sta COLUBK
        lda #COL_LIDAR_BAR
        sta COLUPF
        
        ldx #3
.lidarBarLoop:
        sta WSYNC
        lda lidarFill
        lsr
        lsr
        lsr
        tay
        cpy #32
        bcc .lidarOk
        ldy #31
.lidarOk:
        lda BarPF1,Y
        sta PF1
        lda BarPF2,Y
        sta PF2
        dex
        bne .lidarBarLoop
        
        ; Countdown bar (yellow, 3 lines)
        lda #COL_COUNTDOWN
        sta COLUPF
        
        ldx #3
.countdownLoop:
        sta WSYNC
        lda offmapCountdown
        tay
        cpy #32
        bcc .countOk
        ldy #31
.countOk:
        lda BarPF1,Y
        sta PF1
        lda BarPF2,Y
        sta PF2
        dex
        bne .countdownLoop
        
        lda #0
        sta PF0
        sta PF1
        sta PF2
        rts

; =============================================================================
; DRAW MAIN VIEW (138 lines) - Simplified for stable timing
; =============================================================================
DrawMainView:
        lda #COL_SKY
        sta COLUBK
        lda #COL_CROSSHAIR
        sta COLUP0
        lda #0
        sta GRP1                ; Clear P1 (tanks disabled for timing stability)
        
        ldx #0                  ; Scanline counter
.mainLoop:
        sta WSYNC
        
        ; === CYCLE-BALANCED BACKGROUND ===
        ; Sky or ground based on horizon
        cpx #HORIZON_LINE       ; 2 cycles
        bcc .drawSky            ; 2/3 cycles
        
        ; Ground
        lda #COL_GROUND         ; 2 cycles
        sta COLUBK              ; 3 cycles
        jmp .drawCross          ; 3 cycles = 12 total for ground path
        
.drawSky:
        lda #COL_SKY            ; 2 cycles
        sta COLUBK              ; 3 cycles
        nop                     ; 2 cycles
        nop                     ; 2 cycles = 12 total for sky path (balanced)

.drawCross:
        ; === CROSSHAIR (lines 65-75) ===
        ; Simplified: always write to GRP0, just change what we write
        cpx #65                 ; 2 cycles
        bcc .noCross            ; 2/3 cycles
        cpx #76                 ; 2 cycles
        bcs .noCross            ; 2/3 cycles
        
        ; Draw crosshair line
        txa                     ; 2 cycles
        sec                     ; 2 cycles
        sbc #65                 ; 2 cycles
        tay                     ; 2 cycles
        lda CrosshairData,Y     ; 4 cycles
        sta GRP0                ; 3 cycles
        jmp .nextLine           ; 3 cycles
        
.noCross:
        lda #0                  ; 2 cycles
        sta GRP0                ; 3 cycles
        ; Padding to balance cycles with crosshair path
        nop                     ; 2 cycles
        nop                     ; 2 cycles
        nop                     ; 2 cycles
        nop                     ; 2 cycles
        nop                     ; 2 cycles

.nextLine:
        inx                     ; 2 cycles
        cpx #MAINVIEW_HEIGHT    ; 2 cycles
        bne .mainLoop           ; 3/2 cycles
        
        lda #0
        sta GRP0
        rts

; =============================================================================
; DRAW COCKPIT (36 lines)
; =============================================================================
DrawCockpit:
        lda #COL_COCKPIT
        sta COLUBK
        lda #COL_GEAR_TEXT
        sta COLUPF
        
        ldx #COCKPIT_HEIGHT
.cockpitLoop:
        sta WSYNC
        
        ; Draw gear indicator (lines 10-25)
        cpx #COCKPIT_HEIGHT-10
        bcs .blankCockpit
        cpx #COCKPIT_HEIGHT-26
        bcc .blankCockpit
        
        txa
        sec
        sbc #(COCKPIT_HEIGHT-26)
        cmp #8
        bcs .blankCockpit
        tay
        lda GearPF1Data,Y
        sta PF1
        lda GearPF2Data,Y
        sta PF2
        
        ; Highlight current gear with sprite
        lda currentGear
        asl
        asl
        asl
        clc
        adc #44                 ; Base X position
        ; (Would position sprite here in full impl)
        jmp .nextCockpit

.blankCockpit:
        lda #0
        sta PF1
        sta PF2

.nextCockpit:
        dex
        bne .cockpitLoop
        
        lda #0
        sta PF0
        sta PF1
        sta PF2
        rts

; =============================================================================
; DRAW TITLE SCREEN (190 lines - PrepareFrame uses 2)
; =============================================================================
DrawTitleScreen:
        lda #COL_BLACK
        sta COLUBK
        lda #COL_BLUE
        sta COLUPF
        
        ldx #190                ; 192 - 2 for PrepareFrame
.titleLoop:
        sta WSYNC
        
        ; Draw "MECHA" title
        cpx #80
        bcc .noTitle
        cpx #112
        bcs .noTitle
        
        txa
        sec
        sbc #80
        lsr                     ; Double height
        cmp #16
        bcs .noTitle
        tay
        lda TitlePF1Data,Y
        sta PF1
        lda TitlePF2Data,Y
        sta PF2
        jmp .titleNext

.noTitle:
        lda #0
        sta PF1
        sta PF2

.titleNext:
        dex
        bne .titleLoop
        rts

; =============================================================================
; DRAW PAUSE SCREEN (190 lines - PrepareFrame uses 2)
; Simplified for timing stability - minimal branching
; =============================================================================
DrawPauseScreen:
        lda #COL_BLACK
        sta COLUBK
        lda #COL_PAUSE_TEXT
        sta COLUPF
        lda #0
        sta GRP0
        sta GRP1
        
        ldx #190                ; 192 - 2 for PrepareFrame
.pauseLoop:
        sta WSYNC
        
        ; === SIMPLIFIED RENDERING FOR STABLE TIMING ===
        ; Map area: lines 50-113 (X counts down from 190)
        ; So map is when X is 77-140 (190-113=77, 190-50=140)
        
        cpx #77                 ; Below map area?
        bcc .belowMap
        cpx #141                ; Above map area?
        bcs .aboveMap
        
        ; Inside map area - simple blue background with border
        lda #COL_DARKBLUE
        sta COLUBK
        lda #$81                ; Border pattern
        sta PF1
        sta PF2
        jmp .pauseNext
        
.belowMap:
        ; Below map - check for PAUSE text (lines 170-186 = X: 4-20)
        cpx #4
        bcc .blackArea
        cpx #21
        bcs .blackArea
        
        ; PAUSE text area
        lda #COL_BLACK
        sta COLUBK
        txa
        sec
        sbc #4
        tay
        lda PausePF1Data,Y
        sta PF1
        lda PausePF2Data,Y
        sta PF2
        jmp .pauseNext
        
.aboveMap:
.blackArea:
        ; Black area
        lda #COL_BLACK
        sta COLUBK
        lda #0
        sta PF1
        sta PF2

.pauseNext:
        dex
        bne .pauseLoop
        
        lda #0
        sta PF1
        sta PF2
        rts

; =============================================================================
; DRAW GAME OVER SCREEN (190 lines - PrepareFrame uses 2)
; =============================================================================
DrawGameOverScreen:
        ; Flashing red background
        lda frameCounter
        and #$08
        beq .blackBg
        lda #COL_DARKRED
        jmp .setGOBg
.blackBg:
        lda #COL_BLACK
.setGOBg:
        sta COLUBK
        lda #COL_RED
        sta COLUPF
        
        ldx #190                ; 192 - 2 for PrepareFrame
.goLoop:
        sta WSYNC
        
        ; "GAME OVER" text
        cpx #88
        bcc .noGOText
        cpx #104
        bcs .noGOText
        
        txa
        sec
        sbc #88
        tay
        lda GameOverPF1Data,Y
        sta PF1
        lda GameOverPF2Data,Y
        sta PF2
        jmp .goNext

.noGOText:
        lda #0
        sta PF1
        sta PF2

.goNext:
        dex
        bne .goLoop
        rts

; =============================================================================
; INITIALIZE GAME
; =============================================================================
InitGame:
        lda #STATE_PLAYING
        sta gameState
        
        ; Player starts at center
        lda #16
        sta playerX+1
        sta playerY+1
        lda #$80
        sta playerX
        sta playerY
        
        ; Facing north
        lda #0
        sta legHeading
        sta torsoOffset
        
        ; Neutral gear
        lda #GEAR_N
        sta currentGear
        
        ; Place tanks at corners of map (world coordinates)
        ; Tank 0: Southwest corner (4, 4)
        lda #0
        sta tankX               ; Low byte (fractional)
        sta tankY
        sta tankX+2
        sta tankY+2
        sta tankX+4
        sta tankY+4
        sta tankX+6
        sta tankY+6
        
        lda #6                  ; Tank 0 at (6, 6)
        sta tankX+1             ; High byte (grid cell)
        sta tankY+1
        
        lda #26                 ; Tank 1 at (26, 6)
        sta tankX+3
        lda #6
        sta tankY+3
        
        lda #6                  ; Tank 2 at (6, 26)
        sta tankX+5
        lda #26
        sta tankY+5
        
        lda #26                 ; Tank 3 at (26, 26)
        sta tankX+7
        sta tankY+7
        
        ; Tank headings (pointing inward toward center)
        lda #HEADING_NE         ; Tank 0 faces northeast
        sta tankHeading
        lda #HEADING_NW         ; Tank 1 faces northwest
        sta tankHeading+1
        lda #HEADING_SE         ; Tank 2 faces southeast
        sta tankHeading+2
        lda #HEADING_SW         ; Tank 3 faces southwest
        sta tankHeading+3
        
        ; Clear visibility flags (projection will set them)
        lda #0
        sta tankVisible
        sta tankVisible+1
        sta tankVisible+2
        sta tankVisible+3
        
        ; Screen positions will be calculated by ProjectAllTanks
        sta tankScreenX
        sta tankScreenX+1
        sta tankScreenX+2
        sta tankScreenX+3
        sta tankScreenY
        sta tankScreenY+1
        sta tankScreenY+2
        sta tankScreenY+3
        
        ; Clear status
        lda #0
        sta lidarFill
        sta bobPhase
        sta bobOffset
        sta stompTimer
        
        lda #COUNTDOWN_MAX
        sta offmapCountdown
        lda #0
        sta offmapCounter
        
        rts

; =============================================================================
; DATA TABLES (Bank 0)
; =============================================================================

; Speed table (signed)
SpeedTable:
        .byte <(-2)             ; R2
        .byte <(-1)             ; R1
        .byte 0                 ; N
        .byte 1                 ; 1
        .byte 2                 ; 2
        .byte 3                 ; 3

; Engine pitch (lower = higher pitch)
EnginePitchTbl:
        .byte 26, 28, 31, 28, 26, 22

; Bob rate per gear
BobRateTable:
        .byte 12, 8, 0, 8, 12, 0

; Bob offset sine approximation (16 values)
BobOffsetTable:
        .byte 0, 1, 2, 2, 3, 2, 2, 1
        .byte 0, <(-1), <(-2), <(-2), <(-3), <(-2), <(-2), <(-1)

; Small sine table (32 entries for direction/movement)
SinTableSmall:
        .byte 0, 1, 2, 3, 3, 3, 2, 1
        .byte 0, <(-1), <(-2), <(-3), <(-3), <(-3), <(-2), <(-1)
        .byte 0, 1, 2, 3, 3, 3, 2, 1
        .byte 0, <(-1), <(-2), <(-3), <(-3), <(-3), <(-2), <(-1)

CosTableSmall:
        .byte 3, 3, 2, 1, 0, <(-1), <(-2), <(-3)
        .byte <(-3), <(-3), <(-2), <(-1), 0, 1, 2, 3
        .byte 3, 3, 2, 1, 0, <(-1), <(-2), <(-3)
        .byte <(-3), <(-3), <(-2), <(-1), 0, 1, 2, 3

; =============================================================================
; 64-entry Sin/Cos tables for 3D projection (256 heading units -> 64 entries)
; Values scaled to -32 to +32 range for fixed-point math
; Index = heading / 4
; =============================================================================
SinTable64:
        ; 0-15 (0 to 90 degrees)
        .byte   0,   3,   6,   9,  12,  15,  18,  21
        .byte  24,  26,  28,  30,  31,  32,  32,  32
        ; 16-31 (90 to 180 degrees)  
        .byte  32,  32,  32,  31,  30,  28,  26,  24
        .byte  21,  18,  15,  12,   9,   6,   3,   0
        ; 32-47 (180 to 270 degrees) - negative
        .byte   0,  <(-3),  <(-6),  <(-9), <(-12), <(-15), <(-18), <(-21)
        .byte <(-24), <(-26), <(-28), <(-30), <(-31), <(-32), <(-32), <(-32)
        ; 48-63 (270 to 360 degrees) - negative to zero
        .byte <(-32), <(-32), <(-32), <(-31), <(-30), <(-28), <(-26), <(-24)
        .byte <(-21), <(-18), <(-15), <(-12),  <(-9),  <(-6),  <(-3),   0

CosTable64:
        ; 0-15 (cos starts at 32, goes to 0)
        .byte  32,  32,  32,  31,  30,  28,  26,  24
        .byte  21,  18,  15,  12,   9,   6,   3,   0
        ; 16-31 (0 to -32)
        .byte   0,  <(-3),  <(-6),  <(-9), <(-12), <(-15), <(-18), <(-21)
        .byte <(-24), <(-26), <(-28), <(-30), <(-31), <(-32), <(-32), <(-32)
        ; 32-47 (-32 back to 0)
        .byte <(-32), <(-32), <(-32), <(-31), <(-30), <(-28), <(-26), <(-24)
        .byte <(-21), <(-18), <(-15), <(-12),  <(-9),  <(-6),  <(-3),   0
        ; 48-63 (0 back to 32)
        .byte   0,   3,   6,   9,  12,  15,  18,  21
        .byte  24,  26,  28,  30,  31,  32,  32,  32

; =============================================================================
; Depth to Screen Y position lookup (distance 0-31 -> screen Y)
; Closer objects appear lower (higher Y value)
; =============================================================================
DepthToScreenY:
        .byte HORIZON_LINE+60   ; Distance 0 (at player - shouldn't happen)
        .byte HORIZON_LINE+55   ; Distance 1 - very close
        .byte HORIZON_LINE+48   ; Distance 2
        .byte HORIZON_LINE+42   ; Distance 3
        .byte HORIZON_LINE+36   ; Distance 4
        .byte HORIZON_LINE+32   ; Distance 5
        .byte HORIZON_LINE+28   ; Distance 6
        .byte HORIZON_LINE+24   ; Distance 7
        .byte HORIZON_LINE+21   ; Distance 8
        .byte HORIZON_LINE+18   ; Distance 9
        .byte HORIZON_LINE+16   ; Distance 10
        .byte HORIZON_LINE+14   ; Distance 11
        .byte HORIZON_LINE+12   ; Distance 12
        .byte HORIZON_LINE+10   ; Distance 13
        .byte HORIZON_LINE+9    ; Distance 14
        .byte HORIZON_LINE+8    ; Distance 15
        .byte HORIZON_LINE+7    ; Distance 16
        .byte HORIZON_LINE+6    ; Distance 17
        .byte HORIZON_LINE+5    ; Distance 18
        .byte HORIZON_LINE+5    ; Distance 19
        .byte HORIZON_LINE+4    ; Distance 20
        .byte HORIZON_LINE+4    ; Distance 21
        .byte HORIZON_LINE+3    ; Distance 22
        .byte HORIZON_LINE+3    ; Distance 23
        .byte HORIZON_LINE+2    ; Distance 24
        .byte HORIZON_LINE+2    ; Distance 25
        .byte HORIZON_LINE+2    ; Distance 26
        .byte HORIZON_LINE+1    ; Distance 27
        .byte HORIZON_LINE+1    ; Distance 28
        .byte HORIZON_LINE+1    ; Distance 29
        .byte HORIZON_LINE+1    ; Distance 30
        .byte HORIZON_LINE      ; Distance 31 - at horizon

; Crosshair sprite (11 lines)
CrosshairData:
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %11111111
        .byte %11111111
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00000000

; Tank sprite (8 lines)
TankGfx:
        .byte %00111100
        .byte %01111110
        .byte %11111111
        .byte %11011011
        .byte %11111111
        .byte %01111110
        .byte %00111100
        .byte %00011000

; Compass playfield tick marks (32 entries for scrolling)
CompassPF0Data:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00

CompassPF1Data:
        .byte $80,$40,$20,$10,$08,$04,$02,$01
        .byte $80,$40,$20,$10,$08,$04,$02,$01
        .byte $80,$40,$20,$10,$08,$04,$02,$01
        .byte $80,$40,$20,$10,$08,$04,$02,$01

CompassPF2Data:
        .byte $01,$02,$04,$08,$10,$20,$40,$80
        .byte $01,$02,$04,$08,$10,$20,$40,$80
        .byte $01,$02,$04,$08,$10,$20,$40,$80
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; =============================================================================
; Direction Letter Graphics (8 lines each, for compass display)
; Order: N, NE, E, SE, S, SW, W, NW
; =============================================================================

; "N" letter (8 lines)
DirLetterN:
        .byte %10000010
        .byte %11000010
        .byte %10100010
        .byte %10010010
        .byte %10001010
        .byte %10000110
        .byte %10000010
        .byte %00000000

; "NE" letters (8 lines, compressed)
DirLetterNE:
        .byte %10011110
        .byte %11010000
        .byte %10110000
        .byte %10011100
        .byte %10010000
        .byte %10010000
        .byte %10011110
        .byte %00000000

; "E" letter (8 lines)
DirLetterE:
        .byte %11111110
        .byte %10000000
        .byte %10000000
        .byte %11111000
        .byte %10000000
        .byte %10000000
        .byte %11111110
        .byte %00000000

; "SE" letters (8 lines, compressed)
DirLetterSE:
        .byte %01111110
        .byte %10010000
        .byte %01010000
        .byte %00111100
        .byte %00010000
        .byte %10010000
        .byte %01111110
        .byte %00000000

; "S" letter (8 lines)
DirLetterS:
        .byte %01111110
        .byte %10000000
        .byte %10000000
        .byte %01111100
        .byte %00000010
        .byte %00000010
        .byte %11111100
        .byte %00000000

; "SW" letters (8 lines, compressed)
DirLetterSW:
        .byte %01110100
        .byte %10000100
        .byte %01000100
        .byte %00100100
        .byte %00010100
        .byte %10001010
        .byte %01110010
        .byte %00000000

; "W" letter (8 lines)
DirLetterW:
        .byte %10000010
        .byte %10000010
        .byte %10000010
        .byte %10010010
        .byte %10101010
        .byte %11000110
        .byte %10000010
        .byte %00000000

; "NW" letters (8 lines, compressed)
DirLetterNW:
        .byte %10010100
        .byte %11010100
        .byte %10110100
        .byte %10010100
        .byte %10010100
        .byte %10011010
        .byte %10010010
        .byte %00000000

; Pointer tables for direction letters
DirLetterPtrLo:
        .byte <DirLetterN
        .byte <DirLetterNE
        .byte <DirLetterE
        .byte <DirLetterSE
        .byte <DirLetterS
        .byte <DirLetterSW
        .byte <DirLetterW
        .byte <DirLetterNW

DirLetterPtrHi:
        .byte >DirLetterN
        .byte >DirLetterNE
        .byte >DirLetterE
        .byte >DirLetterSE
        .byte >DirLetterS
        .byte >DirLetterSW
        .byte >DirLetterW
        .byte >DirLetterNW

; Bar width PF data (32 entries)
BarPF1:
        .byte $00,$80,$C0,$E0,$F0,$F8,$FC,$FE
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

BarPF2:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$01,$03,$07,$0F,$1F,$3F,$7F
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

; Gear display (8 lines)
GearPF1Data:
        .byte %11011011
        .byte %10010010
        .byte %10010010
        .byte %11011011
        .byte %10010010
        .byte %10010010
        .byte %10010010
        .byte %00000000

GearPF2Data:
        .byte %01101101
        .byte %01001001
        .byte %01001001
        .byte %01001001
        .byte %01001001
        .byte %01001001
        .byte %01101101
        .byte %00000000

; Title "MECHA" (16 lines)
TitlePF1Data:
        .byte %11101110
        .byte %10101000
        .byte %10101100
        .byte %10101000
        .byte %10101110
        .byte %00000000
        .byte %11001110
        .byte %10101000
        .byte %11101100
        .byte %10101000
        .byte %10101110
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000

TitlePF2Data:
        .byte %01110111
        .byte %00010100
        .byte %00010110
        .byte %00010100
        .byte %01110100
        .byte %00000000
        .byte %01110111
        .byte %01000101
        .byte %01110111
        .byte %01000101
        .byte %01000101
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000

; Pause text (16 lines)
PausePF1Data:
        .byte %11101110
        .byte %10101010
        .byte %11101010
        .byte %10001010
        .byte %10001110
        .byte %00000000
        .byte %10101110
        .byte %10101000
        .byte %10101100
        .byte %10101000
        .byte %01001110
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000

PausePF2Data:
        .byte %01110111
        .byte %01010100
        .byte %01110110
        .byte %01000100
        .byte %01000111
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000

; Game Over text (16 lines)
GameOverPF1Data:
        .byte %11101110
        .byte %10001010
        .byte %10101110
        .byte %10101010
        .byte %11101010
        .byte %00000000
        .byte %10101110
        .byte %10101000
        .byte %10101100
        .byte %10101000
        .byte %01001110
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000

GameOverPF2Data:
        .byte %01110101
        .byte %01000101
        .byte %01010101
        .byte %01010101
        .byte %01110010
        .byte %00000000
        .byte %01110111
        .byte %01010100
        .byte %01010110
        .byte %01010100
        .byte %01100111
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000

; =============================================================================
; VECTORS
; =============================================================================
        ECHO    "---- Bank 0 ----"
        ECHO    "Code ends at:", *
        ECHO    "Bytes used:", (* - $F000)
        ECHO    "Bytes free:", ($FFFA - *)

        ORG     $FFFA
        RORG    $FFFA
        
        .word   Reset           ; NMI
        .word   Reset           ; Reset
        .word   Reset           ; IRQ

; =============================================================================
; End of mecha.asm
; =============================================================================

