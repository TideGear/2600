; =============================================================================
; MECHA SIMULATOR - RAM Variables
; Atari 2600 (128 bytes: $80-$FF)
; =============================================================================

        SEG.U   VARIABLES
        ORG     $80

; -----------------------------------------------------------------------------
; Player State (6 bytes)
; -----------------------------------------------------------------------------
playerX         ds 2    ; 8.8 fixed-point X position
playerY         ds 2    ; 8.8 fixed-point Y position
legHeading      ds 1    ; Direction of movement (0-255)
torsoOffset     ds 1    ; Cockpit offset from legs (-64 to +64)

; -----------------------------------------------------------------------------
; Tank States (20 bytes) - 4 tanks x 5 bytes each
; -----------------------------------------------------------------------------
tankX           ds 8    ; 4 tanks x 2 bytes (8.8 fixed-point X)
tankY           ds 8    ; 4 tanks x 2 bytes (8.8 fixed-point Y)
tankHeading     ds 4    ; 4 tanks x 1 byte heading

; -----------------------------------------------------------------------------
; Game State (10 bytes)
; -----------------------------------------------------------------------------
gameState       ds 1    ; Current game state (title/playing/paused/gameover)
currentGear     ds 1    ; Current gear (0-5: R2,R1,N,1,2,3)
lidarFill       ds 1    ; LIDAR warning bar fill level (0-255)
offmapCountdown ds 1    ; Off-map countdown (0-60)
offmapCounter   ds 1    ; Frame counter for countdown rate
frameCounter    ds 2    ; 16-bit frame counter for timing
bobPhase        ds 1    ; View bobbing phase (0-255)
bobOffset       ds 1    ; Current vertical bob offset
screenShake     ds 1    ; Screen shake intensity

; -----------------------------------------------------------------------------
; Input State (6 bytes)
; -----------------------------------------------------------------------------
joyState        ds 1    ; Current joystick state
joyPrev         ds 1    ; Previous frame joystick state
joyDebounce     ds 1    ; Debounce counter
buttonState     ds 1    ; Current button state
buttonPrev      ds 1    ; Previous button state
doubleTapTimer  ds 1    ; Timer for double-tap detection

; -----------------------------------------------------------------------------
; Audio State (4 bytes)
; -----------------------------------------------------------------------------
enginePitch     ds 1    ; Current engine hum pitch
stompTimer      ds 1    ; Timer for stomp sound
audioFlags      ds 1    ; Bit flags for audio states
sfxTimer        ds 1    ; Sound effect duration timer

; -----------------------------------------------------------------------------
; Rendering Temps (24 bytes)
; -----------------------------------------------------------------------------
scanline        ds 1    ; Current scanline counter
tempX           ds 1    ; Temporary X coordinate
tempY           ds 1    ; Temporary Y coordinate
tempAngle       ds 1    ; Temporary angle calculation
tempDist        ds 1    ; Temporary distance
tempDepth       ds 1    ; Depth for current tank
tempPtr         ds 2    ; Temporary pointer
graphicsTemp    ds 8    ; Buffer for sprite graphics
pfTemp          ds 6    ; Playfield temporary buffer (PF0,PF1,PF2 x2)
mathTemp        ds 8    ; Math operation temporaries

; -----------------------------------------------------------------------------
; Tank Rendering Cache (12 bytes)
; -----------------------------------------------------------------------------
tankScreenX     ds 4    ; Screen X for each tank
tankScreenY     ds 4    ; Screen Y for each tank
tankVisible     ds 4    ; Visibility flags for each tank

; -----------------------------------------------------------------------------
; Compass/UI State (4 bytes)
; -----------------------------------------------------------------------------
compassOffset   ds 1    ; Scroll offset for compass strip
gearDisplayPos  ds 1    ; X position of gear box
uiFlashTimer    ds 1    ; Timer for UI flashing effects
pauseMapOffset  ds 1    ; Offset for pause map rendering

; -----------------------------------------------------------------------------
; Random Number Generator (2 bytes)
; -----------------------------------------------------------------------------
randomSeed      ds 2    ; 16-bit LFSR seed

; -----------------------------------------------------------------------------
; Reserved for Expansion (22 bytes)
; -----------------------------------------------------------------------------
expansion       ds 22   ; Future use: weapons, power-ups, etc.

; -----------------------------------------------------------------------------
; Stack Space
; The 6502 stack grows downward from $FF
; We leave some room at the top of RAM for stack usage
; -----------------------------------------------------------------------------

        ECHO    "---- RAM Usage ----"
        ECHO    "Variables end at:", *
        ECHO    "Bytes used:", (* - $80)
        ECHO    "Bytes free:", ($100 - *)

; =============================================================================
; End of ram.asm
; =============================================================================

