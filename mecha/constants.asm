; =============================================================================
; MECHA SIMULATOR - Constants & Definitions
; Atari 2600 (16K F4 Bank-Switching)
; =============================================================================

; -----------------------------------------------------------------------------
; TIA Write Registers
; -----------------------------------------------------------------------------
VSYNC       = $00       ; Vertical sync set-clear
VBLANK      = $01       ; Vertical blank set-clear
WSYNC       = $02       ; Wait for horizontal sync
RSYNC       = $03       ; Reset horizontal sync counter
NUSIZ0      = $04       ; Number-size player-missile 0
NUSIZ1      = $05       ; Number-size player-missile 1
COLUP0      = $06       ; Color-luminance player 0
COLUP1      = $07       ; Color-luminance player 1
COLUPF      = $08       ; Color-luminance playfield
COLUBK      = $09       ; Color-luminance background
CTRLPF      = $0A       ; Control playfield ball size & collisions
REFP0       = $0B       ; Reflect player 0
REFP1       = $0C       ; Reflect player 1
PF0         = $0D       ; Playfield register byte 0
PF1         = $0E       ; Playfield register byte 1
PF2         = $0F       ; Playfield register byte 2
RESP0       = $10       ; Reset player 0
RESP1       = $11       ; Reset player 1
RESM0       = $12       ; Reset missile 0
RESM1       = $13       ; Reset missile 1
RESBL       = $14       ; Reset ball
AUDC0       = $15       ; Audio control 0
AUDC1       = $16       ; Audio control 1
AUDF0       = $17       ; Audio frequency 0
AUDF1       = $18       ; Audio frequency 1
AUDV0       = $19       ; Audio volume 0
AUDV1       = $1A       ; Audio volume 1
GRP0        = $1B       ; Graphics player 0
GRP1        = $1C       ; Graphics player 1
ENAM0       = $1D       ; Enable missile 0
ENAM1       = $1E       ; Enable missile 1
ENABL       = $1F       ; Enable ball
HMP0        = $20       ; Horizontal motion player 0
HMP1        = $21       ; Horizontal motion player 1
HMM0        = $22       ; Horizontal motion missile 0
HMM1        = $23       ; Horizontal motion missile 1
HMBL        = $24       ; Horizontal motion ball
VDELP0      = $25       ; Vertical delay player 0
VDELP1      = $26       ; Vertical delay player 1
VDELBL      = $27       ; Vertical delay ball
RESMP0      = $28       ; Reset missile 0 to player 0
RESMP1      = $29       ; Reset missile 1 to player 1
HMOVE       = $2A       ; Apply horizontal motion
HMCLR       = $2B       ; Clear horizontal motion registers
CXCLR       = $2C       ; Clear collision latches

; -----------------------------------------------------------------------------
; TIA Read Registers
; -----------------------------------------------------------------------------
CXM0P       = $30       ; Collision M0-P1, M0-P0
CXM1P       = $31       ; Collision M1-P0, M1-P1
CXP0FB      = $32       ; Collision P0-PF, P0-BL
CXP1FB      = $33       ; Collision P1-PF, P1-BL
CXM0FB      = $34       ; Collision M0-PF, M0-BL
CXM1FB      = $35       ; Collision M1-PF, M1-BL
CXBLPF      = $36       ; Collision BL-PF
CXPPMM      = $37       ; Collision P0-P1, M0-M1
INPT0       = $38       ; Paddle 0 input
INPT1       = $39       ; Paddle 1 input
INPT2       = $3A       ; Paddle 2 input
INPT3       = $3B       ; Paddle 3 input
INPT4       = $3C       ; Player 0 fire button
INPT5       = $3D       ; Player 1 fire button

; -----------------------------------------------------------------------------
; RIOT Registers
; -----------------------------------------------------------------------------
SWCHA       = $280      ; Joystick port A
SWACNT      = $281      ; Port A DDR
SWCHB       = $282      ; Console switches
SWBCNT      = $283      ; Port B DDR
INTIM       = $284      ; Timer output
TIMINT      = $285      ; Timer interrupt flag

TIM1T       = $294      ; Set 1-cycle timer
TIM8T       = $295      ; Set 8-cycle timer
TIM64T      = $296      ; Set 64-cycle timer
T1024T      = $297      ; Set 1024-cycle timer

; -----------------------------------------------------------------------------
; F4 Bank-Switching Hotspots
; -----------------------------------------------------------------------------
BANK0       = $FFF4     ; Select bank 0
BANK1       = $FFF5     ; Select bank 1
BANK2       = $FFF6     ; Select bank 2
BANK3       = $FFF7     ; Select bank 3

; -----------------------------------------------------------------------------
; Display Constants
; -----------------------------------------------------------------------------
VBLANK_LINES    = 37    ; NTSC vertical blank lines
VISIBLE_LINES   = 192   ; Visible scanlines
OVERSCAN_LINES  = 30    ; Overscan lines

; Display zone heights (total must be 190 for playing state)
; 2 lines used by PrepareFrame for sprite positioning
COMPASS_HEIGHT  = 10    ; Heading strip
BAR_HEIGHT      = 6     ; LIDAR/countdown bars
MAINVIEW_HEIGHT = 138   ; Main 3D view area (reduced by 2)
COCKPIT_HEIGHT  = 36    ; Cockpit UI at bottom
; Total: 10 + 6 + 138 + 36 = 190

; Horizon position in main view
HORIZON_LINE    = 50    ; Scanlines from top of main view to horizon

; -----------------------------------------------------------------------------
; Colors (NTSC)
; -----------------------------------------------------------------------------
COL_BLACK       = $00
COL_WHITE       = $0E
COL_GREY        = $06
COL_DARKGREY    = $04

COL_RED         = $36
COL_DARKRED     = $32
COL_ORANGE      = $2A
COL_YELLOW      = $1A
COL_GREEN       = $C4
COL_DARKGREEN   = $C2
COL_BLUE        = $84
COL_DARKBLUE    = $82
COL_CYAN        = $A6
COL_BROWN       = $E2

; Specific UI colors
COL_SKY         = $86   ; Blue-grey sky
COL_GROUND      = $E4   ; Brown ground
COL_COCKPIT     = $04   ; Dark grey cockpit
COL_COMPASS_BG  = $02   ; Very dark compass background
COL_COMPASS_FG  = $0E   ; White compass markers
COL_CROSSHAIR   = $0E   ; White crosshair
COL_LIDAR_BAR   = $36   ; Red LIDAR warning
COL_COUNTDOWN   = $1A   ; Yellow countdown bar
COL_PAUSE_TEXT  = $84   ; Blue pause text
COL_TANK        = $46   ; Red-orange tanks
COL_GEAR_BOX    = $0E   ; White gear selector box
COL_GEAR_TEXT   = $08   ; Grey gear text

; -----------------------------------------------------------------------------
; Game Constants
; -----------------------------------------------------------------------------
; World size
WORLD_SIZE      = 32    ; 32x32 grid
WORLD_MAX       = 31    ; Maximum coordinate (0-31)

; Gear indices
GEAR_R2         = 0
GEAR_R1         = 1
GEAR_N          = 2
GEAR_1          = 3
GEAR_2          = 4
GEAR_3          = 5
NUM_GEARS       = 6

; Heading constants (256 = 360 degrees)
HEADING_N       = 0
HEADING_NE      = 32
HEADING_E       = 64
HEADING_SE      = 96
HEADING_S       = 128
HEADING_SW      = 160
HEADING_W       = 192
HEADING_NW      = 224

; Torso twist limits
TORSO_MAX       = 64    ; +/- 90 degrees (64 = 90 degrees)

; LIDAR constants
LIDAR_ARC       = 32    ; 45 degrees detection arc (32 = 45 deg)
LIDAR_MAX       = 255   ; Full LIDAR bar
LIDAR_PENALTY   = 32    ; 45 degree rotation penalty on lock-break

; Off-map countdown
COUNTDOWN_MAX   = 60    ; 10 seconds at 60fps = 600 frames, /10 = 60 ticks
COUNTDOWN_RATE  = 10    ; Decrement every 10 frames (0.17 sec)

; Tank rotation speed (frames per heading unit)
TANK_ROT_SPEED  = 7     ; ~6 deg/sec at 60fps

; Number of tanks
NUM_TANKS       = 4

; Input constants
DEBOUNCE_FRAMES = 4     ; Joystick debounce
DOUBLETAP_WINDOW = 20   ; Frames for double-tap detection

; View bobbing
BOB_AMPLITUDE   = 3     ; Pixels of vertical bob
BOB_FREQ_SLOW   = 8     ; Frames per bob cycle (slow gears)
BOB_FREQ_FAST   = 4     ; Frames per bob cycle (fast gears)

; -----------------------------------------------------------------------------
; Game States
; -----------------------------------------------------------------------------
STATE_TITLE     = 0
STATE_PLAYING   = 1
STATE_PAUSED    = 2
STATE_GAMEOVER  = 3

; -----------------------------------------------------------------------------
; Joystick Bit Masks (active low)
; -----------------------------------------------------------------------------
JOY_RIGHT       = %01111111
JOY_LEFT        = %10111111
JOY_DOWN        = %11011111
JOY_UP          = %11101111
JOY_FIRE        = %01111111     ; For INPT4 (bit 7)

; Inverted masks for easy testing
MASK_RIGHT      = %10000000
MASK_LEFT       = %01000000
MASK_DOWN       = %00100000
MASK_UP         = %00010000
MASK_FIRE       = %10000000

; =============================================================================
; End of constants.asm
; =============================================================================

