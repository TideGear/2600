; =============================================================================
; MECHA SIMULATOR - Bank 0: Main Kernel & Display
; Atari 2600 (16K F4 Bank-Switching)
; =============================================================================

        SEG     BANK0
        ORG     $F000
        RORG    $F000

; =============================================================================
; BANK 0 ENTRY POINT (from reset or bank switch)
; =============================================================================
Bank0Entry:
        ; Fall through to main loop after initial setup

; =============================================================================
; MAIN GAME LOOP
; =============================================================================
MainLoop:
        ; --- VERTICAL SYNC (3 scanlines) ---
        VERTICAL_SYNC

        ; --- VERTICAL BLANK (37 scanlines) ---
        TIMER_SETUP VBLANK_LINES

        ; Process game logic during VBLANK
        jsr ProcessInput
        jsr UpdateGame
        jsr UpdateAudio

        ; Wait for VBLANK to finish
        TIMER_WAIT
        sta WSYNC
        
        ; Turn off VBLANK (enable beam)
        lda #0
        sta VBLANK

        ; --- VISIBLE FRAME (192 scanlines) ---
        ; Check game state for which screen to draw
        lda gameState
        cmp #STATE_TITLE
        beq .drawTitle
        cmp #STATE_PAUSED
        beq .drawPause
        cmp #STATE_GAMEOVER
        beq .drawGameOver
        
        ; Default: draw game screen
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
        ; --- OVERSCAN (30 scanlines) ---
        sta WSYNC
        lda #$02
        sta VBLANK      ; Turn off beam

        TIMER_SETUP OVERSCAN_LINES

        ; Do any extra processing here
        jsr UpdateTimers
        
        TIMER_WAIT

        ; Loop back
        jmp MainLoop

; =============================================================================
; INPUT PROCESSING
; =============================================================================
ProcessInput:
        ; Save previous state
        lda joyState
        sta joyPrev
        lda buttonState
        sta buttonPrev

        ; Read current joystick (Player 0)
        lda SWCHA
        sta joyState

        ; Read fire button
        lda INPT4
        sta buttonState

        ; Handle debounce
        lda joyDebounce
        beq .noDebounce
        dec joyDebounce
        rts
.noDebounce:

        ; Check for pause toggle (double-tap fire)
        jsr CheckDoubleTap

        ; If paused, don't process other input
        lda gameState
        cmp #STATE_PAUSED
        beq .inputDone
        cmp #STATE_TITLE
        beq .checkStart
        cmp #STATE_GAMEOVER
        beq .checkStart

        ; --- GEAR SHIFTING ---
        ; Check UP (shift up)
        lda joyPrev
        and #MASK_UP
        bne .checkDown          ; Was not pressed before
        lda joyState
        and #MASK_UP
        beq .checkDown          ; Still pressed, no edge
        ; UP just released - handled differently
        jmp .checkDown

.checkUp:
        lda joyState
        and #MASK_UP
        bne .checkDown
        lda joyPrev
        and #MASK_UP
        beq .checkDown          ; Was already pressed
        ; UP edge detected - shift up
        lda currentGear
        cmp #GEAR_3
        bcs .checkDown          ; Already at max
        inc currentGear
        lda #DEBOUNCE_FRAMES
        sta joyDebounce
        jmp .checkTurn

.checkDown:
        lda joyState
        and #MASK_DOWN
        bne .checkTurn
        lda joyPrev
        and #MASK_DOWN
        beq .checkTurn          ; Was already pressed
        ; DOWN edge detected - shift down
        lda currentGear
        beq .checkTurn          ; Already at R2
        dec currentGear
        lda #DEBOUNCE_FRAMES
        sta joyDebounce

.checkTurn:
        ; --- TURNING ---
        ; Check if button held (torso twist mode)
        lda buttonState
        bmi .legTurn            ; Button not pressed (bit 7 clear = pressed)

        ; Button pressed - torso twist
        lda joyState
        and #MASK_LEFT
        bne .checkTwistRight
        ; Twist left
        lda torsoOffset
        cmp #<(-TORSO_MAX)      ; Check against -64
        beq .inputDone
        dec torsoOffset
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
        jmp .inputDone

.legTurn:
        ; Normal turning (legs)
        lda joyState
        and #MASK_LEFT
        bne .checkLegRight
        ; Turn left
        dec legHeading
        dec legHeading          ; Turn 2 units per frame
        jmp .inputDone

.checkLegRight:
        lda joyState
        and #MASK_RIGHT
        bne .inputDone
        ; Turn right
        inc legHeading
        inc legHeading          ; Turn 2 units per frame

.inputDone:
        rts

.checkStart:
        ; Title/GameOver: any button press starts game
        lda buttonState
        bmi .inputDone          ; Not pressed
        lda buttonPrev
        bpl .inputDone          ; Was already pressed
        ; Start game
        jsr InitGame
        rts

; =============================================================================
; DOUBLE-TAP DETECTION FOR PAUSE
; =============================================================================
CheckDoubleTap:
        ; Decrement timer if active
        lda doubleTapTimer
        beq .checkPress
        dec doubleTapTimer

.checkPress:
        ; Check for button release edge
        lda buttonPrev
        bmi .noPrevPress        ; Was not pressed
        lda buttonState
        bpl .noPrevPress        ; Still pressed

        ; Button just released
        lda doubleTapTimer
        beq .startTimer
        
        ; Second tap within window - toggle pause!
        lda gameState
        cmp #STATE_PLAYING
        beq .toPause
        cmp #STATE_PAUSED
        beq .toPlay
        rts

.toPause:
        lda #STATE_PAUSED
        sta gameState
        lda #0
        sta doubleTapTimer
        rts

.toPlay:
        lda #STATE_PLAYING
        sta gameState
        lda #0
        sta doubleTapTimer
        rts

.startTimer:
        lda #DOUBLETAP_WINDOW
        sta doubleTapTimer
.noPrevPress:
        rts

; =============================================================================
; GAME UPDATE
; =============================================================================
UpdateGame:
        lda gameState
        cmp #STATE_PLAYING
        bne .noUpdate

        ; Update player position based on gear and heading
        jsr UpdatePlayerPosition
        
        ; Update tank AI (switch to bank 2)
        ; For now, inline simple rotation
        jsr UpdateTanks
        
        ; Check LIDAR detection
        jsr CheckLIDAR
        
        ; Check off-map status
        jsr CheckOffMap

.noUpdate:
        rts

; =============================================================================
; UPDATE PLAYER POSITION
; =============================================================================
UpdatePlayerPosition:
        ; Get speed from gear
        ldx currentGear
        lda GearSpeedTable,X
        beq .noMovement         ; Neutral
        
        sta mathTemp            ; Store speed
        
        ; Calculate movement vector
        ; deltaX = speed * cos(heading)
        ; deltaY = speed * sin(heading)
        
        ; Switch to bank 2 for math tables
        lda BANK2
        
        ; Get cos value
        ldx legHeading
        lda CosTable,X
        sta mathTemp+1          ; cos value (signed)
        
        ; Get sin value
        lda SinTable,X
        sta mathTemp+2          ; sin value (signed)
        
        ; Switch back to bank 0
        lda BANK0
        
        ; Simple movement: add scaled direction to position
        ; For now, simplified integer movement
        lda mathTemp            ; speed
        bmi .reverseMove
        
        ; Forward movement
        lda mathTemp+1          ; cos (X direction)
        bmi .negX
        ; Positive X
        clc
        lda playerX
        adc mathTemp+1
        sta playerX
        lda playerX+1
        adc #0
        sta playerX+1
        jmp .doY
.negX:
        ; Negative X
        clc
        lda playerX
        adc mathTemp+1          ; Adding negative = subtracting
        sta playerX
        lda playerX+1
        adc #$FF                ; Sign extend
        sta playerX+1

.doY:
        lda mathTemp+2          ; sin (Y direction)
        bmi .negY
        ; Positive Y
        clc
        lda playerY
        adc mathTemp+2
        sta playerY
        lda playerY+1
        adc #0
        sta playerY+1
        jmp .noMovement
.negY:
        clc
        lda playerY
        adc mathTemp+2
        sta playerY
        lda playerY+1
        adc #$FF
        sta playerY+1
        jmp .noMovement

.reverseMove:
        ; Reverse: negate the movement
        ; For simplicity, just move opposite direction
        lda mathTemp+1
        eor #$FF
        clc
        adc #1
        sta mathTemp+1
        lda mathTemp+2
        eor #$FF
        clc
        adc #1
        sta mathTemp+2
        jmp .doY                ; Reuse forward logic with negated values

.noMovement:
        rts

; =============================================================================
; UPDATE TANKS (Simple AI)
; =============================================================================
UpdateTanks:
        ; Increment frame counter
        inc frameCounter
        lda frameCounter
        and #(TANK_ROT_SPEED-1) ; Check if time to rotate (every 8 frames ~= 7)
        bne .noRotate
        
        ; Rotate all tanks
        ldx #NUM_TANKS-1
.rotateLoop:
        inc tankHeading,X
        dex
        bpl .rotateLoop

.noRotate:
        rts

; =============================================================================
; CHECK LIDAR DETECTION
; =============================================================================
CheckLIDAR:
        ; For each tank, check if player is in detection arc
        lda #0
        sta mathTemp            ; Accumulator for LIDAR fill rate
        
        ldx #NUM_TANKS-1
.checkLoop:
        ; Calculate angle from tank to player
        ; Simplified: check if player is roughly in front of tank
        
        ; Get tank heading
        lda tankHeading,X
        sta mathTemp+1
        
        ; Get relative position (very simplified)
        ; In a full implementation, calculate actual angle
        ; For now, just accumulate based on distance
        
        ; Check if tank is "looking" at player (simplified)
        ; Compare tank heading to direction toward player
        lda playerX+1           ; High byte = grid position
        sec
        sbc tankX+1,X           ; Relative X (high byte)
        sta mathTemp+2
        
        lda playerY+1
        sec
        sbc tankY+1,X
        sta mathTemp+3
        
        ; Very simplified detection: if relative position matches heading quadrant
        ; This is a placeholder - real implementation uses atan2 approximation
        
        ; For demo: just slowly fill LIDAR bar
        lda lidarFill
        cmp #LIDAR_MAX
        bcs .nextTank
        inc lidarFill

.nextTank:
        dex
        bpl .checkLoop
        
        rts

; =============================================================================
; CHECK OFF-MAP STATUS
; =============================================================================
CheckOffMap:
        ; Check if player X is out of bounds (0-31)
        lda playerX+1           ; High byte = grid cell
        cmp #WORLD_SIZE
        bcs .offMap
        
        lda playerY+1
        cmp #WORLD_SIZE
        bcs .offMap
        
        ; On map - reset countdown if active
        lda #COUNTDOWN_MAX
        sta offmapCountdown
        rts

.offMap:
        ; Off map - decrement countdown
        inc offmapCounter
        lda offmapCounter
        cmp #COUNTDOWN_RATE
        bcc .noDecrement
        
        lda #0
        sta offmapCounter
        
        lda offmapCountdown
        beq .gameOver
        dec offmapCountdown
        rts

.noDecrement:
        rts

.gameOver:
        lda #STATE_GAMEOVER
        sta gameState
        rts

; =============================================================================
; UPDATE TIMERS
; =============================================================================
UpdateTimers:
        ; Increment 16-bit frame counter
        inc frameCounter
        bne .noHigh
        inc frameCounter+1
.noHigh:

        ; Update view bobbing
        jsr UpdateBobbing
        
        rts

; =============================================================================
; UPDATE VIEW BOBBING
; =============================================================================
UpdateBobbing:
        ; Only bob in walking gears
        lda currentGear
        cmp #GEAR_3
        beq .noBob              ; Skating mode
        cmp #GEAR_N
        beq .noBob              ; Neutral
        
        ; Advance bob phase based on gear speed
        ldx currentGear
        lda BobSpeedTable,X
        clc
        adc bobPhase
        sta bobPhase
        
        ; Calculate bob offset from phase (sine approximation)
        ; Use upper bits of phase to index small sine table
        lda bobPhase
        lsr
        lsr
        lsr
        lsr                     ; /16 = 0-15 index
        and #$0F
        tax
        lda BobSineTable,X
        sta bobOffset
        
        ; Check for footfall (phase crossing zero)
        lda bobPhase
        and #$F0
        cmp #$80
        bne .noStomp
        lda stompTimer
        bne .noStomp
        ; Trigger stomp sound
        lda #8
        sta stompTimer
.noStomp:
        rts

.noBob:
        lda #0
        sta bobOffset
        sta bobPhase
        rts

; =============================================================================
; UPDATE AUDIO
; =============================================================================
UpdateAudio:
        ; Engine hum (always on)
        lda #6                  ; Bass tone
        sta AUDC0
        
        ; Pitch based on gear
        ldx currentGear
        lda EnginePitchTable,X
        sta AUDF0
        
        lda #8                  ; Medium volume
        sta AUDV0
        
        ; Stomp/skate sound
        lda stompTimer
        beq .checkSkate
        dec stompTimer
        
        ; Stomp sound active
        lda #8                  ; Noise
        sta AUDC1
        lda #4
        sta AUDF1
        lda stompTimer
        sta AUDV1
        rts

.checkSkate:
        lda currentGear
        cmp #GEAR_3
        bne .noSkate
        
        ; Skate whine
        lda #12                 ; Lead/saw
        sta AUDC1
        lda #20
        sta AUDF1
        lda #4
        sta AUDV1
        rts

.noSkate:
        lda #0
        sta AUDV1
        rts

; =============================================================================
; DRAW GAME SCREEN
; =============================================================================
DrawGameScreen:
        ; Draw compass strip
        jsr DrawCompass
        
        ; Draw LIDAR and countdown bars
        jsr DrawStatusBars
        
        ; Draw main 3D view
        jsr DrawMainView
        
        ; Draw cockpit UI
        jsr DrawCockpitUI
        
        rts

; =============================================================================
; DRAW COMPASS STRIP (10 scanlines)
; =============================================================================
DrawCompass:
        ; Set colors
        lda #COL_COMPASS_BG
        sta COLUBK
        lda #COL_COMPASS_FG
        sta COLUPF

        ; Calculate compass offset from cockpit heading
        lda legHeading
        clc
        adc torsoOffset
        sta compassOffset

        ; Draw compass scanlines
        ldx #COMPASS_HEIGHT
.compassLoop:
        sta WSYNC
        
        ; Simple compass representation using playfield
        ; Show markers based on heading offset
        lda compassOffset
        lsr
        lsr
        lsr                     ; /8 for coarse position
        and #$1F
        tay
        
        ; Set playfield based on heading position
        lda CompassPF0,Y
        sta PF0
        lda CompassPF1,Y
        sta PF1
        lda CompassPF2,Y
        sta PF2
        
        dex
        bne .compassLoop
        
        ; Clear playfield
        lda #0
        sta PF0
        sta PF1
        sta PF2
        
        rts

; =============================================================================
; DRAW STATUS BARS (6 scanlines)
; =============================================================================
DrawStatusBars:
        lda #COL_BLACK
        sta COLUBK
        
        ; LIDAR bar (3 lines)
        lda #COL_LIDAR_BAR
        sta COLUPF
        
        ldx #3
.lidarLoop:
        sta WSYNC
        ; Set playfield width based on lidarFill
        lda lidarFill
        lsr
        lsr
        lsr                     ; /8 for PF width
        tay
        lda BarWidthPF1,Y
        sta PF1
        lda BarWidthPF2,Y
        sta PF2
        dex
        bne .lidarLoop
        
        ; Countdown bar (3 lines)
        lda #COL_COUNTDOWN
        sta COLUPF
        
        ldx #3
.countdownLoop:
        sta WSYNC
        lda offmapCountdown
        lsr                     ; /2 for PF width
        tay
        lda BarWidthPF1,Y
        sta PF1
        lda BarWidthPF2,Y
        sta PF2
        dex
        bne .countdownLoop
        
        ; Clear playfield
        lda #0
        sta PF0
        sta PF1
        sta PF2
        
        rts

; =============================================================================
; DRAW MAIN VIEW (140 scanlines)
; =============================================================================
DrawMainView:
        ; Set sky color
        lda #COL_SKY
        sta COLUBK
        
        ; Set crosshair color
        lda #COL_CROSSHAIR
        sta COLUP0
        
        ; Set tank color
        lda #COL_TANK
        sta COLUP1
        
        ; Position crosshair at center
        sta WSYNC
        lda #80                 ; Center X
        ldx #0                  ; P0
        jsr PosSprite
        sta WSYNC
        sta HMOVE
        
        ; Calculate visible tank positions
        jsr CalcTankPositions
        
        ; Draw scanlines
        ldx #0                  ; Scanline counter
.viewLoop:
        sta WSYNC
        
        ; Check if at horizon
        cpx #HORIZON_LINE
        bcc .aboveHorizon
        
        ; Below horizon - ground
        lda #COL_GROUND
        sta COLUBK
        
        ; Add ground texture (pseudo-random based on position)
        txa
        eor frameCounter
        eor legHeading
        and #$0F
        beq .groundDark
        lda #COL_GROUND
        jmp .setGround
.groundDark:
        lda #COL_BROWN
.setGround:
        sta COLUBK
        jmp .drawSprites

.aboveHorizon:
        lda #COL_SKY
        sta COLUBK

.drawSprites:
        ; Apply bob offset to sprite positions
        txa
        clc
        adc bobOffset
        sta tempY
        
        ; Draw crosshair at center (scanlines 65-75 of view)
        txa
        cmp #65
        bcc .noCrosshair
        cmp #76
        bcs .noCrosshair
        ; Get crosshair graphics
        txa
        sec
        sbc #65
        tay
        lda CrosshairGfx,Y
        sta GRP0
        jmp .checkTank

.noCrosshair:
        lda #0
        sta GRP0

.checkTank:
        ; Draw tanks if visible at this scanline
        ; Simplified: check if any tank should be drawn
        jsr DrawTankSprite

        inx
        cpx #MAINVIEW_HEIGHT
        bne .viewLoop
        
        ; Clear sprites
        lda #0
        sta GRP0
        sta GRP1
        
        rts

; =============================================================================
; CALCULATE TANK SCREEN POSITIONS
; =============================================================================
CalcTankPositions:
        ; For each tank, calculate screen X, Y and visibility
        ldx #NUM_TANKS-1
.calcLoop:
        ; Get relative position
        lda tankX+1,X           ; High byte = grid position
        sec
        sbc playerX+1
        sta mathTemp            ; Relative X
        
        lda tankY+1,X
        sec
        sbc playerY+1
        sta mathTemp+1          ; Relative Y
        
        ; Apply cockpit rotation (simplified)
        ; For now, just use relative position directly
        
        ; Calculate screen X (center + offset)
        lda #80
        clc
        adc mathTemp
        adc mathTemp            ; *2 for more spread
        sta tankScreenX,X
        
        ; Calculate screen Y (horizon + depth offset)
        lda #HORIZON_LINE
        sec
        sbc mathTemp+1
        sbc mathTemp+1
        sta tankScreenY,X
        
        ; Check visibility (in front of player and on screen)
        lda mathTemp+1
        bmi .notVisible         ; Behind player
        cmp #32
        bcs .notVisible         ; Too far
        
        lda tankScreenX,X
        cmp #160
        bcs .notVisible         ; Off screen
        
        lda #1
        sta tankVisible,X
        jmp .nextTank

.notVisible:
        lda #0
        sta tankVisible,X

.nextTank:
        dex
        bpl .calcLoop
        rts

; =============================================================================
; DRAW TANK SPRITE AT CURRENT SCANLINE
; =============================================================================
DrawTankSprite:
        ; Check each tank for visibility at current scanline (X register)
        stx tempX               ; Save scanline
        
        ldy #NUM_TANKS-1
.tankLoop:
        lda tankVisible,Y
        beq .nextTankSprite
        
        ; Check if scanline matches tank Y position
        lda tempX
        sec
        sbc tankScreenY,Y
        bmi .nextTankSprite     ; Above tank
        cmp #8                  ; Tank height
        bcs .nextTankSprite     ; Below tank
        
        ; Draw tank at this scanline
        tax                     ; Line within tank sprite
        lda TankSprite,X
        sta GRP1
        
        ; Position tank X (would need to be done earlier for proper timing)
        ; This is simplified - real impl needs cycle-counted positioning
        
        ldx tempX               ; Restore scanline counter
        rts

.nextTankSprite:
        dey
        bpl .tankLoop
        
        ; No tank visible
        lda #0
        sta GRP1
        
        ldx tempX               ; Restore scanline counter
        rts

; =============================================================================
; DRAW COCKPIT UI (36 scanlines)
; =============================================================================
DrawCockpitUI:
        ; Set cockpit colors
        lda #COL_COCKPIT
        sta COLUBK
        lda #COL_GEAR_TEXT
        sta COLUPF
        
        ; Clear sprites
        lda #0
        sta GRP0
        sta GRP1
        
        ; Draw gear selector area
        ldx #COCKPIT_HEIGHT
.cockpitLoop:
        sta WSYNC
        
        ; Draw gear display (scanlines 10-25 of cockpit)
        txa
        cmp #COCKPIT_HEIGHT-10
        bcs .blankCockpit
        cmp #COCKPIT_HEIGHT-26
        bcc .blankCockpit
        
        ; Calculate which line of gear text
        txa
        sec
        sbc #(COCKPIT_HEIGHT-26)
        tay
        
        ; Get gear graphics for this line
        cpy #8
        bcs .blankCockpit
        
        ; Draw all gears as playfield
        lda GearPF1,Y
        sta PF1
        lda GearPF2,Y
        sta PF2
        
        ; Draw selection box around current gear using sprites
        lda currentGear
        asl
        asl
        asl                     ; *8 for position offset
        clc
        adc #40                 ; Base position
        sta tempX
        
        ; Draw box outline
        cpy #0
        beq .drawBox
        cpy #7
        beq .drawBox
        jmp .noBox
.drawBox:
        lda #COL_GEAR_BOX
        sta COLUP0
        lda #$FF
        sta GRP0
.noBox:
        jmp .nextCockpitLine

.blankCockpit:
        lda #0
        sta PF1
        sta PF2
        sta GRP0

.nextCockpitLine:
        dex
        bne .cockpitLoop
        
        ; Clear
        lda #0
        sta PF0
        sta PF1
        sta PF2
        sta GRP0
        
        rts

; =============================================================================
; DRAW TITLE SCREEN
; =============================================================================
DrawTitleScreen:
        lda #COL_BLACK
        sta COLUBK
        lda #COL_BLUE
        sta COLUPF
        
        ldx #VISIBLE_LINES
.titleLoop:
        sta WSYNC
        
        ; Draw title text in middle of screen
        txa
        cmp #80
        bcc .noTitle
        cmp #112
        bcs .noTitle
        
        ; Get title graphics
        txa
        sec
        sbc #80
        lsr
        tay
        cpy #16
        bcs .noTitle
        
        lda TitlePF1,Y
        sta PF1
        lda TitlePF2,Y
        sta PF2
        jmp .nextTitleLine

.noTitle:
        lda #0
        sta PF1
        sta PF2

.nextTitleLine:
        dex
        bne .titleLoop
        
        rts

; =============================================================================
; DRAW PAUSE SCREEN
; =============================================================================
DrawPauseScreen:
        lda #COL_BLACK
        sta COLUBK
        lda #COL_PAUSE_TEXT
        sta COLUPF
        
        ldx #VISIBLE_LINES
.pauseLoop:
        sta WSYNC
        
        ; Draw PAUSE text at top
        txa
        cmp #170
        bcc .noPauseText
        cmp #186
        bcs .noPauseText
        txa
        sec
        sbc #170
        tay
        lda PausePF1,Y
        sta PF1
        lda PausePF2,Y
        sta PF2
        jmp .checkMap

.noPauseText:
        lda #0
        sta PF1
        sta PF2

.checkMap:
        ; Draw 32x32 map in center (scanlines 40-104)
        txa
        cmp #40
        bcc .nextPauseLine
        cmp #104
        bcs .nextPauseLine
        
        ; Draw map border and contents
        txa
        sec
        sbc #40
        tay
        
        ; Simple map display
        cpy #0
        beq .mapBorder
        cpy #63
        beq .mapBorder
        jmp .mapContent

.mapBorder:
        lda #$FF
        sta PF1
        sta PF2
        jmp .nextPauseLine

.mapContent:
        ; Draw player and tanks on map
        ; Simplified: just draw grid
        lda #$11
        sta PF1
        lda #$44
        sta PF2

.nextPauseLine:
        dex
        bne .pauseLoop
        
        lda #0
        sta PF1
        sta PF2
        rts

; =============================================================================
; DRAW GAME OVER SCREEN
; =============================================================================
DrawGameOverScreen:
        ; Flash red background
        lda frameCounter
        and #$10
        beq .blackBG
        lda #COL_DARKRED
        jmp .setBG
.blackBG:
        lda #COL_BLACK
.setBG:
        sta COLUBK
        
        lda #COL_RED
        sta COLUPF
        
        ldx #VISIBLE_LINES
.gameOverLoop:
        sta WSYNC
        
        ; Draw GAME OVER text
        txa
        cmp #88
        bcc .noGOText
        cmp #104
        bcs .noGOText
        txa
        sec
        sbc #88
        tay
        lda GameOverPF1,Y
        sta PF1
        lda GameOverPF2,Y
        sta PF2
        jmp .nextGOLine

.noGOText:
        lda #0
        sta PF1
        sta PF2

.nextGOLine:
        dex
        bne .gameOverLoop
        
        rts

; =============================================================================
; SPRITE POSITIONING ROUTINE
; =============================================================================
; A = desired X position (0-159)
; X = RESP register offset (0=P0, 1=P1, 2=M0, 3=M1, 4=BL)
; Destroys A, Y
PosSprite:
        sta WSYNC               ; Start fresh scanline
        sec
.divideLoop:
        sbc #15                 ; 5 cycles per iteration
        bcs .divideLoop         ; 2/3 cycles
        ; A now contains remainder - 15
        eor #$FF                ; Convert to positive offset
        asl                     ; *2 (now we have -14 to 0 -> 0 to 14 -> 0 to 28)
        asl                     ; *4
        asl                     ; *8
        asl                     ; *16 for HMxx value
        sta HMP0,X              ; Set fine position
        sta RESP0,X             ; Set coarse position (timing dependent)
        rts

; =============================================================================
; INITIALIZE GAME
; =============================================================================
InitGame:
        ; Set game state
        lda #STATE_PLAYING
        sta gameState
        
        ; Initialize player at center of map
        lda #16                 ; Center of 32x32
        sta playerX+1
        sta playerY+1
        lda #$80                ; 0.5 fraction
        sta playerX
        sta playerY
        
        ; Player starts facing north
        lda #HEADING_N
        sta legHeading
        lda #0
        sta torsoOffset
        
        ; Start in neutral
        lda #GEAR_N
        sta currentGear
        
        ; Initialize tanks at corners
        lda #4
        sta tankX+1             ; Tank 0 X
        sta tankY+1             ; Tank 0 Y
        lda #28
        sta tankX+3             ; Tank 1 X
        lda #4
        sta tankY+3             ; Tank 1 Y
        lda #4
        sta tankX+5             ; Tank 2 X
        lda #28
        sta tankY+5             ; Tank 2 Y
        lda #28
        sta tankX+7             ; Tank 3 X
        sta tankY+7             ; Tank 3 Y
        
        ; Tank starting headings (pointing inward)
        lda #HEADING_SE
        sta tankHeading
        lda #HEADING_SW
        sta tankHeading+1
        lda #HEADING_NE
        sta tankHeading+2
        lda #HEADING_NW
        sta tankHeading+3
        
        ; Clear status
        lda #0
        sta lidarFill
        lda #COUNTDOWN_MAX
        sta offmapCountdown
        lda #0
        sta offmapCounter
        sta bobPhase
        sta bobOffset
        
        ; Initialize random seed
        lda #$A5
        sta randomSeed
        lda #$5A
        sta randomSeed+1
        
        rts

; =============================================================================
; DATA TABLES
; =============================================================================

; Gear speed table (signed: negative = reverse)
GearSpeedTable:
        .byte <(-3)             ; R2 - fast reverse
        .byte <(-1)             ; R1 - slow reverse
        .byte 0                 ; N  - neutral
        .byte 1                 ; 1  - slow forward
        .byte 2                 ; 2  - medium forward
        .byte 4                 ; 3  - fast forward (skates)

; Engine pitch table (lower = higher pitch)
EnginePitchTable:
        .byte 28                ; R2
        .byte 30                ; R1
        .byte 31                ; N
        .byte 30                ; 1
        .byte 28                ; 2
        .byte 24                ; 3

; Bob speed table (phase increment per frame)
BobSpeedTable:
        .byte 16                ; R2
        .byte 8                 ; R1
        .byte 0                 ; N
        .byte 8                 ; 1
        .byte 16                ; 2
        .byte 0                 ; 3 (no bob)

; Simple sine table for bobbing (16 entries, 0-centered)
BobSineTable:
        .byte 0, 1, 2, 3, 3, 3, 2, 1
        .byte 0, -1, -2, -3, -3, -3, -2, -1

; Crosshair sprite (11 lines)
CrosshairGfx:
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
TankSprite:
        .byte %00111100
        .byte %01111110
        .byte %11111111
        .byte %11011011
        .byte %11111111
        .byte %01111110
        .byte %00111100
        .byte %00011000

; Compass playfield data (simplified - 32 entries for full rotation)
CompassPF0:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00

CompassPF1:
        .byte $80,$00,$00,$00,$08,$00,$00,$00  ; N, NE
        .byte $80,$00,$00,$00,$08,$00,$00,$00  ; E, SE
        .byte $80,$00,$00,$00,$08,$00,$00,$00  ; S, SW
        .byte $80,$00,$00,$00,$08,$00,$00,$00  ; W, NW

CompassPF2:
        .byte $01,$00,$00,$00,$10,$00,$00,$00
        .byte $01,$00,$00,$00,$10,$00,$00,$00
        .byte $01,$00,$00,$00,$10,$00,$00,$00
        .byte $01,$00,$00,$00,$10,$00,$00,$00

; Bar width playfield (for LIDAR/countdown bars)
BarWidthPF1:
        .byte $00,$80,$C0,$E0,$F0,$F8,$FC,$FE
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

BarWidthPF2:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$01,$03,$07,$0F,$1F,$3F,$7F
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

; Gear display playfield (8 lines of R2 R1 N 1 2 3)
GearPF1:
        .byte %11011011  ; Top of characters
        .byte %10010010
        .byte %10010010
        .byte %11011011
        .byte %10010010
        .byte %10010010
        .byte %10010010
        .byte %00000000

GearPF2:
        .byte %01101101
        .byte %01001001
        .byte %01001001
        .byte %01001001
        .byte %01001001
        .byte %01001001
        .byte %01101101
        .byte %00000000

; Title screen "MECHA" (16 lines, doubled)
TitlePF1:
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

TitlePF2:
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

; Pause text "PAUSE" (16 lines)
PausePF1:
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

PausePF2:
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
GameOverPF1:
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

GameOverPF2:
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
; BANK 0 PADDING AND VECTORS
; =============================================================================
        ECHO    "---- Bank 0 ----"
        ECHO    "Code ends at:", *
        ECHO    "Bytes used:", (* - $F000)
        ECHO    "Bytes free:", ($FFFA - *)

        ORG     $FFFA
        RORG    $FFFA

        .word   Reset           ; NMI vector (not used on 2600)
        .word   Reset           ; Reset vector
        .word   Reset           ; IRQ vector (not used on 2600)

; =============================================================================
; End of bank0_kernel.asm
; =============================================================================

