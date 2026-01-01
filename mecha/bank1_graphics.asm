; =============================================================================
; MECHA SIMULATOR - Bank 1: Graphics Data
; Atari 2600 (16K F4 Bank-Switching)
; =============================================================================

        SEG     BANK1
        ORG     $D000
        RORG    $D000

; =============================================================================
; BANK 1 ENTRY POINT
; =============================================================================
Bank1Entry:
        ; Switch back to bank 0 for main loop
        lda BANK0
        jmp Reset               ; Jump to reset in bank 0

; =============================================================================
; TANK SPRITES - 8 DIRECTIONS (8 lines each)
; =============================================================================

; Tank facing North (toward player)
TankNorth:
        .byte %00111100
        .byte %01111110
        .byte %11111111
        .byte %11011011
        .byte %11111111
        .byte %01111110
        .byte %00111100
        .byte %00011000

; Tank facing Northeast
TankNorthEast:
        .byte %00001110
        .byte %00011111
        .byte %00111111
        .byte %01111110
        .byte %11111100
        .byte %11111000
        .byte %01110000
        .byte %00100000

; Tank facing East (side view)
TankEast:
        .byte %00000000
        .byte %11111100
        .byte %11111110
        .byte %11111111
        .byte %11111111
        .byte %11111110
        .byte %11111100
        .byte %00000000

; Tank facing Southeast
TankSouthEast:
        .byte %00100000
        .byte %01110000
        .byte %11111000
        .byte %11111100
        .byte %01111110
        .byte %00111111
        .byte %00011111
        .byte %00001110

; Tank facing South (away from player)
TankSouth:
        .byte %00011000
        .byte %00111100
        .byte %01111110
        .byte %11111111
        .byte %11011011
        .byte %11111111
        .byte %01111110
        .byte %00111100

; Tank facing Southwest
TankSouthWest:
        .byte %00000100
        .byte %00001110
        .byte %00011111
        .byte %00111111
        .byte %01111110
        .byte %11111100
        .byte %11111000
        .byte %01110000

; Tank facing West (side view)
TankWest:
        .byte %00000000
        .byte %00111111
        .byte %01111111
        .byte %11111111
        .byte %11111111
        .byte %01111111
        .byte %00111111
        .byte %00000000

; Tank facing Northwest
TankNorthWest:
        .byte %01110000
        .byte %11111000
        .byte %11111100
        .byte %01111110
        .byte %00111111
        .byte %00011111
        .byte %00001110
        .byte %00000100

; =============================================================================
; TANK SPRITE POINTER TABLE
; =============================================================================
TankSpriteTableLo:
        .byte <TankNorth
        .byte <TankNorthEast
        .byte <TankEast
        .byte <TankSouthEast
        .byte <TankSouth
        .byte <TankSouthWest
        .byte <TankWest
        .byte <TankNorthWest

TankSpriteTableHi:
        .byte >TankNorth
        .byte >TankNorthEast
        .byte >TankEast
        .byte >TankSouthEast
        .byte >TankSouth
        .byte >TankSouthWest
        .byte >TankWest
        .byte >TankNorthWest

; =============================================================================
; CROSSHAIR VARIATIONS
; =============================================================================

; Standard crosshair
CrosshairStd:
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

; Crosshair with lock indicator
CrosshairLock:
        .byte %01011010
        .byte %00111100
        .byte %00011000
        .byte %00011000
        .byte %11111111
        .byte %11111111
        .byte %00011000
        .byte %00011000
        .byte %00111100
        .byte %01011010
        .byte %00000000

; =============================================================================
; COCKPIT FRAME GRAPHICS
; =============================================================================

; Left side of cockpit (mirrored for right)
CockpitLeft:
        .byte %11111111
        .byte %11111110
        .byte %11111100
        .byte %11111000
        .byte %11110000
        .byte %11100000
        .byte %11000000
        .byte %10000000
        .byte %10000000
        .byte %10000000
        .byte %10000000
        .byte %10000000

; =============================================================================
; FONT DATA - 5x7 CHARACTERS
; Numbers 0-9 and letters for UI
; =============================================================================

; Number font (5 wide x 7 tall, stored as bytes)
Font0:
        .byte %01110000
        .byte %10001000
        .byte %10011000
        .byte %10101000
        .byte %11001000
        .byte %10001000
        .byte %01110000

Font1:
        .byte %00100000
        .byte %01100000
        .byte %00100000
        .byte %00100000
        .byte %00100000
        .byte %00100000
        .byte %01110000

Font2:
        .byte %01110000
        .byte %10001000
        .byte %00001000
        .byte %00110000
        .byte %01000000
        .byte %10000000
        .byte %11111000

Font3:
        .byte %01110000
        .byte %10001000
        .byte %00001000
        .byte %00110000
        .byte %00001000
        .byte %10001000
        .byte %01110000

Font4:
        .byte %00010000
        .byte %00110000
        .byte %01010000
        .byte %10010000
        .byte %11111000
        .byte %00010000
        .byte %00010000

Font5:
        .byte %11111000
        .byte %10000000
        .byte %11110000
        .byte %00001000
        .byte %00001000
        .byte %10001000
        .byte %01110000

Font6:
        .byte %00110000
        .byte %01000000
        .byte %10000000
        .byte %11110000
        .byte %10001000
        .byte %10001000
        .byte %01110000

Font7:
        .byte %11111000
        .byte %00001000
        .byte %00010000
        .byte %00100000
        .byte %01000000
        .byte %01000000
        .byte %01000000

Font8:
        .byte %01110000
        .byte %10001000
        .byte %10001000
        .byte %01110000
        .byte %10001000
        .byte %10001000
        .byte %01110000

Font9:
        .byte %01110000
        .byte %10001000
        .byte %10001000
        .byte %01111000
        .byte %00001000
        .byte %00010000
        .byte %01100000

; Letter R (for Reverse gears)
FontR:
        .byte %11110000
        .byte %10001000
        .byte %10001000
        .byte %11110000
        .byte %10100000
        .byte %10010000
        .byte %10001000

; Letter N (for Neutral)
FontN:
        .byte %10001000
        .byte %11001000
        .byte %10101000
        .byte %10011000
        .byte %10001000
        .byte %10001000
        .byte %10001000

; =============================================================================
; COMPASS DIRECTION MARKERS
; =============================================================================

; N marker
CompassN:
        .byte %10001000
        .byte %11001000
        .byte %10101000
        .byte %10011000
        .byte %10001000

; NE marker
CompassNE:
        .byte %10001000
        .byte %11001100
        .byte %10101010
        .byte %10011001
        .byte %10001000

; E marker
CompassE:
        .byte %11111000
        .byte %10000000
        .byte %11110000
        .byte %10000000
        .byte %11111000

; SE marker
CompassSE:
        .byte %01111000
        .byte %10000100
        .byte %01110010
        .byte %00001001
        .byte %11110000

; S marker
CompassS:
        .byte %01110000
        .byte %10000000
        .byte %01110000
        .byte %00001000
        .byte %11110000

; SW marker
CompassSW:
        .byte %01111000
        .byte %10000100
        .byte %01110010
        .byte %00001001
        .byte %11110000

; W marker
CompassW:
        .byte %10001000
        .byte %10001000
        .byte %10101000
        .byte %10101000
        .byte %01010000

; NW marker
CompassNW:
        .byte %10001000
        .byte %11011100
        .byte %10101010
        .byte %10011001
        .byte %10001000

; =============================================================================
; GEAR SELECTOR GRAPHICS (Full set)
; =============================================================================

; "R2" text
GearR2:
        .byte %11100111
        .byte %10010001
        .byte %10010010
        .byte %11100100
        .byte %10100111
        .byte %10010000
        .byte %10010000

; "R1" text
GearR1:
        .byte %11100010
        .byte %10010110
        .byte %10010010
        .byte %11100010
        .byte %10100010
        .byte %10010010
        .byte %10010111

; "N" text
GearN_Gfx:
        .byte %10001000
        .byte %11001000
        .byte %10101000
        .byte %10011000
        .byte %10001000
        .byte %10001000
        .byte %10001000

; "1" text
Gear1:
        .byte %00100000
        .byte %01100000
        .byte %00100000
        .byte %00100000
        .byte %00100000
        .byte %00100000
        .byte %01110000

; "2" text
Gear2:
        .byte %01110000
        .byte %10001000
        .byte %00001000
        .byte %00110000
        .byte %01000000
        .byte %10000000
        .byte %11111000

; "3" text
Gear3:
        .byte %01110000
        .byte %10001000
        .byte %00001000
        .byte %00110000
        .byte %00001000
        .byte %10001000
        .byte %01110000

; =============================================================================
; PAUSE MAP ICONS
; =============================================================================

; Player icon (arrow pointing up)
MapPlayerN:
        .byte %00010000
        .byte %00111000
        .byte %01010100
        .byte %00010000
        .byte %00010000

MapPlayerNE:
        .byte %00011100
        .byte %00001100
        .byte %00010100
        .byte %00100000
        .byte %01000000

MapPlayerE:
        .byte %00100000
        .byte %01110000
        .byte %00101000
        .byte %01110000
        .byte %00100000

MapPlayerSE:
        .byte %01000000
        .byte %00100000
        .byte %00010100
        .byte %00001100
        .byte %00011100

MapPlayerS:
        .byte %00010000
        .byte %00010000
        .byte %01010100
        .byte %00111000
        .byte %00010000

MapPlayerSW:
        .byte %00000100
        .byte %00001000
        .byte %01010000
        .byte %01100000
        .byte %01110000

MapPlayerW:
        .byte %00001000
        .byte %00011100
        .byte %00101000
        .byte %00011100
        .byte %00001000

MapPlayerNW:
        .byte %01110000
        .byte %01100000
        .byte %01010000
        .byte %00001000
        .byte %00000100

; Tank icon for map
MapTank:
        .byte %01110000
        .byte %11111000
        .byte %11111000
        .byte %11111000
        .byte %01110000

; =============================================================================
; GROUND TEXTURE PATTERNS
; =============================================================================

; Different ground patterns for variety
GroundPattern0:
        .byte %10010010
        .byte %01001001
        .byte %10010010
        .byte %00100100
        .byte %10010010
        .byte %01001001
        .byte %00100100
        .byte %10010010

GroundPattern1:
        .byte %01010101
        .byte %10101010
        .byte %01010101
        .byte %10101010
        .byte %01010101
        .byte %10101010
        .byte %01010101
        .byte %10101010

GroundPattern2:
        .byte %11001100
        .byte %11001100
        .byte %00110011
        .byte %00110011
        .byte %11001100
        .byte %11001100
        .byte %00110011
        .byte %00110011

GroundPattern3:
        .byte %10001000
        .byte %01000100
        .byte %00100010
        .byte %00010001
        .byte %10001000
        .byte %01000100
        .byte %00100010
        .byte %00010001

; =============================================================================
; TITLE SCREEN GRAPHICS - "MECHA"
; Large stylized text
; =============================================================================

TitleMECHA_Line0:
        .byte %11000011, %11111110, %01111110, %11000011, %01111110
TitleMECHA_Line1:
        .byte %11100111, %11000000, %11000011, %11000011, %11000011
TitleMECHA_Line2:
        .byte %11111111, %11000000, %11000000, %11111111, %11000011
TitleMECHA_Line3:
        .byte %11011011, %11111100, %11000000, %11111111, %11111111
TitleMECHA_Line4:
        .byte %11000011, %11000000, %11000000, %11000011, %11000011
TitleMECHA_Line5:
        .byte %11000011, %11000000, %11000011, %11000011, %11000011
TitleMECHA_Line6:
        .byte %11000011, %11111110, %01111110, %11000011, %11000011

; =============================================================================
; EXPLOSION/EFFECT SPRITES (for future use)
; =============================================================================

Explosion0:
        .byte %00010000
        .byte %01010100
        .byte %00111000
        .byte %11111110
        .byte %00111000
        .byte %01010100
        .byte %00010000
        .byte %00000000

Explosion1:
        .byte %00100100
        .byte %10010010
        .byte %01111100
        .byte %00111000
        .byte %01111100
        .byte %10010010
        .byte %00100100
        .byte %00000000

Explosion2:
        .byte %10000010
        .byte %01000100
        .byte %00101000
        .byte %01111100
        .byte %00101000
        .byte %01000100
        .byte %10000010
        .byte %00000000

; =============================================================================
; LIDAR SCANNING EFFECT
; =============================================================================

LidarScan0:
        .byte %10000000
        .byte %11000000
        .byte %11100000
        .byte %11110000
        .byte %11100000
        .byte %11000000
        .byte %10000000
        .byte %00000000

LidarScan1:
        .byte %00000001
        .byte %00000011
        .byte %00000111
        .byte %00001111
        .byte %00000111
        .byte %00000011
        .byte %00000001
        .byte %00000000

; =============================================================================
; UTILITY: Get Tank Sprite Pointer
; Input: A = direction (0-7)
; Output: tempPtr = address of sprite
; =============================================================================
GetTankSprite:
        and #$07                ; Mask to 0-7
        tax
        lda TankSpriteTableLo,X
        sta tempPtr
        lda TankSpriteTableHi,X
        sta tempPtr+1
        rts

; =============================================================================
; BANK 1 PADDING AND VECTORS
; =============================================================================
        ECHO    "---- Bank 1 ----"
        ECHO    "Code ends at:", *
        ECHO    "Bytes used:", (* - $D000)
        ECHO    "Bytes free:", ($DFFA - *)

        ORG     $DFFA
        RORG    $DFFA

        .word   Reset           ; NMI
        .word   Reset           ; Reset
        .word   Reset           ; IRQ

; =============================================================================
; End of bank1_graphics.asm
; =============================================================================

