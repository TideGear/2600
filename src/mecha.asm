; Atari 2600 Mecha Simulator (16K ROM, F6 bankswitch)
;
; This project intentionally prioritizes:
; - **Graphical stability** (cycle-safe kernel, no overruns)
; - **Proper NTSC scanline count** (262 total: 3 VSYNC + VBLANK + 192 visible + overscan)
; - **Asymmetric playfield** (left/right halves are different; no mirrored/doubled PF)
;
; Architecture overview:
; - We use 4x4K banks (F6). Many emulators/hardware power up in bank 0, so
;   bank0/1/2 contain trampolines that bank-switch to bank3, where `Reset` lives.
; - All time-critical visible-kernel code + its lookup tables live in **bank 3**
;   to avoid mid-frame bankswitching.
; - Game logic runs during VBLANK/overscan with the RIOT timer (TIM64T), so the
;   visible kernel remains deterministic and WSYNC-aligned.
;
; Asymmetric PF timing (critical):
; - Left PF0/PF1/PF2 must be written before the first visible playfield pixel.
; - Right PF0/PF1/PF2 must be written later, inside "safe windows" after the
;   left-side PF registers have finished shifting out (see RandomTerrain Session 17).
;   The visible kernel uses fixed-cycle delays (BIT/NOP) to hit those windows.

    processor 6502

    include "vcs.inc"
    include "macros.inc"
    ; Generated tables are split so bank3 (kernel) stays small:
    ; - `generated_kernel_tables.inc` is included into **bank3** near the end of the file.
    ; - `generated_pause_tables.inc` is included into **bank2** (pause-only).

; --------------------
; Bankswitch hotspots (F6)
; Writing to these addresses selects the corresponding 4K bank.
; --------------------
BANK0   = $FFF6
BANK1   = $FFF7
BANK2   = $FFF8
BANK3   = $FFF9

; --------------------
; Constants
; --------------------
NTSC_VSYNC_LINES     = 3
NTSC_VISIBLE_LINES   = 192

; We use the RIOT timer (TIM64T) to hold stable blanking intervals while
; running game logic. These values are chosen so that the overall frame stays
; stable at ~262 lines when combined with:
; - VSYNC: 3 scanlines (explicit WSYNC)
; - Visible: 192 scanlines (explicit WSYNC)
; Tune ONLY if you measure a consistent off-by-one in a cycle-accurate emulator.
VBLANK_TIMER_64      = 43    ; ~37 lines worth of cycles, rounded by final WSYNC align
OVERSCAN_TIMER_64    = 35    ; ~30 lines worth of cycles, rounded by final WSYNC align

; Visible kernel layout (must sum to 192)
COMPASS_LINES        = 8
LIDAR_BAR_LINES      = 4
COUNTDOWN_BAR_LINES  = 4
SKY_HEAD_LINES       = 60
VIEW_OVERLAY_LINES   = 8     ; crosshair + tank blip
SKY_TAIL_LINES       = 4
HORIZON_LINES        = 8     ; mountains/clouds band near horizon (view-dependent)
GROUND_LINES         = 48
UI_MARKER_LINES      = 5     ; gear selector labels + highlight box
UI_LINES             = 43

TANK_COUNT           = 4
TANK_NONE            = 5     ; used by overlay tables (0..4 positions, 5 = none)

MODE_PLAY            = 0
MODE_PAUSE           = 1
MODE_LOSE            = 2

; Joystick bit masks (SWCHA, left joystick = high nibble; 0 = pressed)
JOY_UP              = $10
JOY_DOWN            = $20
JOY_LEFT            = $40
JOY_RIGHT           = $80

DOUBLE_TAP_FRAMES   = 20      ; ~333ms at 60Hz
TORSO_TWIST_LIMIT   = 64      ; +/-90 degrees in 256-heading space

; World size
WORLD_W             = 16
WORLD_H             = 8

; Timer start value for off-map countdown: 10 seconds @ 60Hz = 600 frames = $0258
OFFMAP_START_LO     = $58
OFFMAP_START_HI     = $02

; --------------------
; RAM (RIOT) variables ($80-$FF)
; --------------------
    SEG.U Variables
    ORG $80

FrameCounter    ds 1
GameMode        ds 1

; Input / player state
GearIdx         ds 1          ; 0..5 (R2,R1,N,1,2,3)
LegHeading      ds 1          ; 0..255 (turning)
TorsoOffset     ds 1          ; signed, clamped to [-64..+64]
ViewDir         ds 1          ; 0..7 (derived each frame from LegHeading+TorsoOffset)
LegTurnFrac     ds 1          ; fractional turning accumulator (legs)
TorsoTurnFrac   ds 1          ; fractional turning accumulator (torso)
GroundDir       ds 1          ; 0..7 (legDir relative to ViewDir), used for ground motion pattern

JoyPrev         ds 1
BtnPrev         ds 1
BtnTapTimer     ds 1

; Player position (tile + fractional), tile is signed (two's complement) so off-map is representable.
PlayerXTile     ds 1
PlayerXFrac     ds 1
PlayerYTile     ds 1
PlayerYFrac     ds 1

; Off-map countdown (10 seconds @ 60Hz = 600 frames)
OffMapLo        ds 1
OffMapHi        ds 1
OffMapSeg       ds 1          ; 0..16 segments (for UI)

; LIDAR fill (8.8 fixed: Hi is visible 0..255, Lo is fractional)
LidarLo         ds 1
LidarHi         ds 1
LidarSeg        ds 1          ; 0..16 segments (for UI)

; Tank display selection for cockpit overlay
TankXIndex      ds 1          ; 0..4 positions, 5=none
TankActive      ds 1          ; 0..3, $FF if none

TankRotCtr      ds 1
BobPhase        ds 1
BobOffset       ds 1          ; 0/1 vertical bob for world region
StepTimer       ds 1          ; frames until next footfall (walking gears)
ShakeTimer      ds 1          ; short camera shake after footfall
StompTimer      ds 1          ; stomp sound duration

; Enemy tanks
TankX           ds TANK_COUNT
TankY           ds TANK_COUNT
TankHeadingArr  ds TANK_COUNT
TankCooldownArr ds TANK_COUNT
TankFlagsArr    ds TANK_COUNT

; Pause map PF bytes (8 rows).
; NOTE: In PLAY mode, we also reuse these 48 bytes as a per-frame scratch buffer to
; build the 8 compass strip scanlines in RAM (so we can overlay the legs-dot and
; keep the first visible scanline ZP-fast). In PAUSE mode, OverscanLogic rebuilds
; these bytes as the centered 16x8 map.
MapPF0L         ds 8
MapPF1L         ds 8
MapPF2L         ds 8
MapPF0R         ds 8
MapPF1R         ds 8
MapPF2R         ds 8
PausePFColor    ds 1          ; COLUPF to use for pause map (white normally, red when flashing scans)

; Preloaded PF bytes for the FIRST visible compass scanline (must be ZP-fast)
CompassLinePF0L ds 1
CompassLinePF1L ds 1
CompassLinePF2L ds 1
CompassLinePF0R ds 1
CompassLinePF1R ds 1
CompassLinePF2R ds 1

; Scratch (used in VBLANK/overscan logic only).
; NOTE: The visible kernel uses `BIT Tmp0` as a 3-cycle delay. BIT modifies flags,
; so never branch based on flags set prior to those BITs inside the kernel.
Tmp0            ds 1
Tmp1            ds 1
Tmp2            ds 1
Tmp3            ds 1
Tmp4            ds 1
BestDist        ds 1
BestDiff        ds 1

; --------------------
; Bank 0 (reserved for future: tables / code)
; File offset $0000-$0FFF, runtime $F000-$FFFF
; --------------------
    SEG Bank0
    ORG $0000
    RORG $F000

Bank0_Start:
    ; F6 carts typically power up in bank 0.
    ; Immediately switch to bank 3 (main code) and jump to Reset.
    lda #$00
    sta BANK3
    jmp Reset

    ORG $0FFC
    RORG $FFFC
    .word Bank0_Start
    .word Bank0_Start

; --------------------
; Bank 1 (reserved)
; --------------------
    SEG Bank1
    ORG $1000
    RORG $F000

Bank1_Start:
    ; Safety: if emulator/hardware starts in bank 1, trampoline to main.
    lda #$00
    sta BANK3
    jmp Reset

    ORG $1FFC
    RORG $FFFC
    .word Bank1_Start
    .word Bank1_Start

; --------------------
; Bank 2 (reserved)
; --------------------
    SEG Bank2
    ORG $2000
    RORG $F000

Bank2_Start:
    ; Safety: if emulator/hardware starts in bank 2, trampoline to main.
    lda #$00
    sta BANK3
    jmp Reset

; --------------------
; Bank 2 code/data (pause-only)
; --------------------
; Bank2 is not used during the visible kernel, so it's a safe place to store:
; - pause/map lookup tables
; - helper routines called only during overscan/VBLANK

    ; Include pause-only PF column masks here so they don't bloat bank3.
    include "generated_pause_tables.inc"

; --------------------
; Pause map builder (bank2)
; --------------------
; Generates per-row PF bytes into MapPF* arrays for the pause kernel.
;
; This runs during overscan while paused (beam off), so it can do slower work:
; - clear buffers
; - OR in masks to set pixels
; - decide flashing color when tanks are scanning
;
; Inputs (RAM variables):
; - PlayerXTile/PlayerYTile: player map location (signed; can be off-map)
; - LegHeading: used for player's facing indicator
; - TankX[], TankY[], TankHeadingArr[]: tank locations + facings
; - TankFlagsArr[].bit0: 1 when tank is scanning (LIDARing)
; - FrameCounter: used to flash scanning tanks
;
; Outputs:
; - MapPF* arrays (8 rows): PF bytes for the pause kernel
; - PausePFColor: COLUPF color (white normally; red when flashing scans)
;
; NOTE: X/Y usage:
; - X is generally the map column (0..15) when calling MapSetBit
; - Y is generally the map row (0..7)
BuildPauseMap:
    ; Clear 8 rows of PF bytes.
    ldy #0
.clr_rows:
    lda #0
    sta MapPF0L,y
    sta MapPF1L,y
    sta MapPF2L,y
    sta MapPF0R,y
    sta MapPF1R,y
    sta MapPF2R,y
    iny
    cpy #8
    bne .clr_rows

    ; --- Player dot + facing ---
    ; Clamp to map bounds (tiles are signed, so negative means off-map).
    lda PlayerXTile
    bmi .skip_player
    cmp #WORLD_W
    bcs .skip_player
    sta Tmp2            ; col
    lda PlayerYTile
    bmi .skip_player
    cmp #WORLD_H
    bcs .skip_player
    sta Tmp3            ; row

    ldx Tmp2
    ldy Tmp3
    jsr MapSetBit

    ; Facing indicator (cardinal from LegHeading >> 6):
    ; 0=N, 1=E, 2=S, 3=W
    lda LegHeading
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    and #$03
    sta Tmp1
    jsr MapSetFacingFromTmp
.skip_player:

    ; --- Tanks ---
    ; If any tank is scanning, flash by alternating:
    ; - white full map
    ; - red scanning-tanks-only map
    lda #0
    sta Tmp0            ; anyScan flag
    ldx #0
.any_scan_loop:
    lda TankFlagsArr,x
    and #1
    ora Tmp0
    sta Tmp0
    inx
    cpx #TANK_COUNT
    bne .any_scan_loop

    lda #0
    sta Tmp4            ; scanOnly flag (0=draw all tanks, 1=draw scanning tanks only)
    lda Tmp0
    beq .pause_white_all
    lda FrameCounter
    and #$08
    beq .pause_white_all
    lda #$46            ; red
    sta PausePFColor
    lda #1
    sta Tmp4
    jmp .pause_color_set
.pause_white_all:
    lda #$0E            ; white
    sta PausePFColor
.pause_color_set:

    ldx #0
.tank_map_loop:
    stx Tmp0            ; save tank idx
    lda Tmp4
    beq .tank_draw      ; draw all tanks
    lda TankFlagsArr,x
    and #1
    beq .pm_tank_next   ; scanOnly => skip non-scanning tanks
.tank_draw:
    ldx Tmp0
    lda TankX,x
    sta Tmp2
    lda TankY,x
    sta Tmp3
    ldx Tmp2
    ldy Tmp3
    jsr MapSetBit

    ; Facing indicator (cardinal from TankHeadingArr >> 6)
    ldx Tmp0
    lda TankHeadingArr,x
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    and #$03
    sta Tmp1
    jsr MapSetFacingFromTmp

.pm_tank_next:
    ldx Tmp0
    inx
    cpx #TANK_COUNT
    bne .tank_map_loop

    rts

; Set a facing indicator for an entity using:
; - Tmp2: col (0..15)
; - Tmp3: row (0..7)
; - Tmp1: card dir (0=N,1=E,2=S,3=W)
; The indicator is one pixel adjacent to the entity pixel.
MapSetFacingFromTmp:
    lda Tmp1
    beq .face_n
    cmp #1
    beq .face_e
    cmp #2
    beq .face_s
    ; W
    lda Tmp2
    beq .face_done
    dec Tmp2
    jmp .face_set
.face_n:
    lda Tmp3
    beq .face_done
    dec Tmp3
    jmp .face_set
.face_e:
    lda Tmp2
    cmp #15
    beq .face_done
    inc Tmp2
    jmp .face_set
.face_s:
    lda Tmp3
    cmp #7
    beq .face_done
    inc Tmp3
.face_set:
    ldx Tmp2
    ldy Tmp3
    jsr MapSetBit
.face_done:
    rts

; OR the centered map-column mask (X=col 0..15) into the PF bytes for row Y (0..7).
; The masks are auto-generated so that the 16-bit-wide map is centered in the 40 PF bits.
MapSetBit:
    lda MapPF0L,y
    ora MapColPF0LMask,x
    sta MapPF0L,y
    lda MapPF1L,y
    ora MapColPF1LMask,x
    sta MapPF1L,y
    lda MapPF2L,y
    ora MapColPF2LMask,x
    sta MapPF2L,y

    lda MapPF0R,y
    ora MapColPF0RMask,x
    sta MapPF0R,y
    lda MapPF1R,y
    ora MapColPF1RMask,x
    sta MapPF1R,y
    lda MapPF2R,y
    ora MapColPF2RMask,x
    sta MapPF2R,y
    rts

; --------------------
; Banked-call stub region (must be identical across bank2 and bank3)
; --------------------
; We place the stub at runtime $FFE0 so it does NOT overlap the F6 hotspot area
; ($FFF6-$FFF9). Multi-byte instructions must never straddle those addresses.
    ORG $2FE0
    RORG $FFE0
    lda #$00
    sta BANK2           ; (idempotent here; we're already in bank2)
    jsr BuildPauseMap   ; build MapPF* rows + PausePFColor
    lda #$00
    sta BANK3           ; return to main/kernel bank
    rts

    ORG $2FFC
    RORG $FFFC
    .word Bank2_Start
    .word Bank2_Start

; --------------------
; Bank 3 - main code + visible kernel + kernel tables
;
; IMPORTANT:
; - Keep the visible kernel and any scanline-time tables in this bank.
; - It is safe to bankswitch during VBLANK/overscan, but NOT during the visible
;   region (unless you *really* know what you're doing and measure cycles).
; --------------------
    SEG Bank3
    ORG $3000
    RORG $F000

Reset:
    CLEAN_START

    ; Reset runs with an unknown prior machine state. CLEAN_START:
    ; - sets stack
    ; - clears RAM ($00-$FF)
    ; - disables interrupts and BCD mode
    ;
    ; After this point we must:
    ; - initialize TIA registers to known values
    ; - initialize game state variables
    ; - enter the stable frame loop

    ; Basic TIA init
    lda #$00
    sta COLUBK          ; black background
    lda #$0E
    sta COLUPF          ; bright-ish white playfield
    sta PausePFColor    ; default pause-map color (white)
    lda #$00
    sta CTRLPF          ; no reflect, no score mode (we do asym PF manually)

    ; Game state init
    lda #MODE_PLAY
    sta GameMode
    lda #2
    sta GearIdx         ; Neutral (N)
    lda #$00
    sta LegHeading
    sta TorsoOffset
    sta LegTurnFrac
    sta TorsoTurnFrac
    sta GroundDir
    sta JoyPrev
    sta BtnPrev
    sta BtnTapTimer
    sta OffMapLo
    sta OffMapHi
    sta OffMapSeg
    sta LidarLo
    sta LidarHi
    sta LidarSeg
    lda #TANK_NONE
    sta TankXIndex
    lda #$FF
    sta TankActive
    lda #$00
    sta TankRotCtr
    sta BobPhase
    sta BobOffset
    sta StepTimer
    sta ShakeTimer
    sta StompTimer

    ; Audio init
    sta AUDV0
    sta AUDV1
    sta AUDC0
    sta AUDC1
    sta AUDF0
    sta AUDF1

    ; Player starts near center of 16x8 world
    lda #8
    sta PlayerXTile
    lda #0
    sta PlayerXFrac
    lda #4
    sta PlayerYTile
    lda #0
    sta PlayerYFrac

    ; Tank initial placement (tile coords) + headings
    lda #2
    sta TankX+0
    lda #1
    sta TankY+0
    lda #$00
    sta TankHeadingArr+0
    sta TankCooldownArr+0
    sta TankFlagsArr+0

    lda #13
    sta TankX+1
    lda #1
    sta TankY+1
    lda #$40
    sta TankHeadingArr+1
    lda #$00
    sta TankCooldownArr+1
    sta TankFlagsArr+1

    lda #2
    sta TankX+2
    lda #6
    sta TankY+2
    lda #$80
    sta TankHeadingArr+2
    lda #$00
    sta TankCooldownArr+2
    sta TankFlagsArr+2

    lda #13
    sta TankX+3
    lda #6
    sta TankY+3
    lda #$C0
    sta TankHeadingArr+3
    lda #$00
    sta TankCooldownArr+3
    sta TankFlagsArr+3

MainLoop:
    inc FrameCounter

    ; NTSC frame structure (262 scanlines):
    ; - VSYNC:   3 scanlines (write VSYNC=2, WSYNC 3x, then VSYNC=0)
    ; - VBLANK:  ~37 scanlines (VBLANK=2, run game logic while RIOT timer counts down)
    ; - Visible: 192 scanlines (cycle-stable kernel, WSYNC-aligned)
    ; - Overscan:~30 scanlines (VBLANK=2, run overscan logic)
    ;
    ; The visible kernel must *always* execute in a fixed amount of time per scanline.

    ; ----------------
    ; VSYNC (3 lines)
    ; ----------------
    lda #$02
    sta VSYNC
    sta WSYNC
    sta WSYNC
    sta WSYNC
    lda #$00
    sta VSYNC

    ; ----------------
    ; VBLANK (timered)
    ; ----------------
    lda #$02
    sta VBLANK
    lda #VBLANK_TIMER_64
    sta TIM64T
    jsr GameLogic
.vblank_wait:
    lda INTIM
    bne .vblank_wait
    ; Visible region transition + kernel.
    ; Keep VBLANK enabled until the kernel code aligns to the next scanline and disables it.
    jsr VisibleDispatch

    ; ----------------
    ; Overscan (timered)
    ; ----------------
    lda #$02
    sta VBLANK
    lda #OVERSCAN_TIMER_64
    sta TIM64T
    jsr OverscanLogic
.overscan_wait:
    lda INTIM
    bne .overscan_wait
    sta WSYNC              ; align to scanline boundary before next frame
    lda #$00
    sta VBLANK

    jmp MainLoop

; --------------------
; Per-frame logic (runs during VBLANK while display is off)
; Keep this bounded so it always finishes before the VBLANK timer expires.
; --------------------
GameLogic:
    ; GameLogic runs during VBLANK while the beam is off-screen.
    ;
    ; Responsibilities (high level):
    ; - Input handling (gear shift, leg turn, torso twist, pause toggle)
    ; - Motion integration (player tile+frac position)
    ; - Off-map countdown bookkeeping (10s timer + UI segments)
    ; - Enemy tank rotation + LIDAR detection/fill + lock-break cooldown
    ; - Build per-frame UI buffers used by the visible kernel (compass tape + legs-dot)
    ; - Update audio state (engine hum + footfalls/skate)
    ;
    ; IMPORTANT: This must always complete before the VBLANK timer expires.

    ; ---- Double-tap pause toggle (works in all modes) ----
    ; Decrement tap timer if active
    lda BtnTapTimer
    beq .no_tap_dec
    dec BtnTapTimer
.no_tap_dec:

    ; Read button (INPT4 bit7: 0=pressed, 1=released)
    lda INPT4
    bmi .btn_released
    lda #1
    bne .btn_got
.btn_released:
    lda #0
.btn_got:
    sta Tmp0            ; Tmp0 = btnNow (0/1)

    ; Edge detect: new press when btnNow=1 and BtnPrev=0
    lda BtnPrev
    bne .btn_prev_down
    lda Tmp0
    beq .btn_prev_down  ; still up
    ; new press
    lda BtnTapTimer
    beq .start_tap_timer
    ; second tap within window -> toggle pause
    lda #0
    sta BtnTapTimer
    lda GameMode
    cmp #MODE_PAUSE
    beq .unpause
    lda #MODE_PAUSE
    sta GameMode
    jmp .after_pause_toggle
.unpause:
    lda #MODE_PLAY
    sta GameMode
.after_pause_toggle:
    jmp .btn_prev_down
.start_tap_timer:
    lda #DOUBLE_TAP_FRAMES
    sta BtnTapTimer

.btn_prev_down:
    ; Update BtnPrev for next frame
    lda Tmp0
    sta BtnPrev

    ; If paused or lost, skip world updates (audio TODO still runs later)
    lda GameMode
    beq .do_world
    jmp .compute_bars_only
.do_world:

    ; ---- Read joystick (SWCHA high nibble, 0=pressed) ----
    lda SWCHA
    and #$F0
    sta Tmp1            ; Tmp1 = joyNow masked

    ; Gear shift on up/down edge
    lda JoyPrev
    sta Tmp2            ; Tmp2 = joyPrev

    ; Up edge: now pressed (bit=0) and prev released (bit=1)
    lda Tmp1
    and #JOY_UP
    bne .no_up
    lda Tmp2
    and #JOY_UP
    beq .no_up
    lda GearIdx
    cmp #5
    bcs .no_up
    inc GearIdx
.no_up:

    ; Down edge
    lda Tmp1
    and #JOY_DOWN
    bne .no_down
    lda Tmp2
    and #JOY_DOWN
    beq .no_down
    lda GearIdx
    beq .no_down
    dec GearIdx
.no_down:

    ; Turning / torso twist
    ; If left (only)
    lda Tmp1
    and #JOY_LEFT
    bne .check_right
    lda Tmp1
    and #JOY_RIGHT
    bne .not_both_held
    jmp .turn_done      ; ignore if both held
.not_both_held:
    lda Tmp0
    beq .leg_left
    ; torso left
    ; Base step: -2 per frame, plus -1 extra 32 times per 240 frames (2+2/15)
    lda TorsoOffset
    sec
    sbc #2
    sta TorsoOffset

    lda TorsoTurnFrac
    clc
    adc #2
    cmp #15
    bcc .torso_l_store_frac
    sec
    sbc #15
    sta TorsoTurnFrac
    lda TorsoOffset
    sec
    sbc #1
    sta TorsoOffset
    jmp .torso_l_clamp
.torso_l_store_frac:
    sta TorsoTurnFrac
.torso_l_clamp:
    ; Clamp to -64 ($C0)
    lda TorsoOffset
    bpl .store_torso_l          ; positive => already >= -64
    cmp #$C0                    ; $C0..$FF == -64..-1
    bcs .store_torso_l
    lda #$C0                    ; clamp only if less than -64 ($80..$BF)
.store_torso_l:
    sta TorsoOffset
    jmp .turn_done
.leg_left:
    lda LegHeading
    sec
    sbc #1
    sta LegHeading
    inc LegTurnFrac
    lda LegTurnFrac
    cmp #15
    bne .turn_done
    lda #0
    sta LegTurnFrac
    lda LegHeading
    sec
    sbc #1
    sta LegHeading
    jmp .turn_done

.check_right:
    lda Tmp1
    and #JOY_RIGHT
    bne .turn_done
    lda Tmp0
    beq .leg_right
    ; torso right
    ; Base step: +2 per frame, plus +1 extra 32 times per 240 frames (2+2/15),
    ; so torso turn rate is exactly 2x the leg turn rate.
    lda TorsoOffset
    clc
    adc #2
    sta TorsoOffset

    lda TorsoTurnFrac
    clc
    adc #2
    cmp #15
    bcc .torso_r_store_frac
    sec
    sbc #15
    sta TorsoTurnFrac
    lda TorsoOffset
    clc
    adc #1
    sta TorsoOffset
    jmp .torso_r_clamp
.torso_r_store_frac:
    sta TorsoTurnFrac
.torso_r_clamp:
    ; Clamp to +64
    lda TorsoOffset
    bmi .store_torso_r          ; negative => still below +64
    cmp #$41                    ; 65
    bcc .store_torso_r
    lda #TORSO_TWIST_LIMIT      ; clamp to +64
.store_torso_r:
    sta TorsoOffset
    jmp .turn_done
.leg_right:
    ; Leg turn rate: exactly 4 seconds per 360° at 60Hz.
    ; 256 heading units / 240 frames = 1 + 1/15 units per frame while turning.
    lda LegHeading
    clc
    adc #1
    sta LegHeading
    inc LegTurnFrac
    lda LegTurnFrac
    cmp #15
    bne .turn_done
    lda #0
    sta LegTurnFrac
    lda LegHeading
    clc
    adc #1
    sta LegHeading
    jmp .turn_done

.turn_done:
    ; Store joystick for edge detection next frame
    lda Tmp1
    sta JoyPrev

    ; Auto-center torso when button is released.
    ; This runs even while leg-turning, and keeps the cockpit returning to the legs.
    lda Tmp0
    bne .after_torso_center
    lda TorsoOffset
    beq .after_torso_center
    bmi .torso_center_from_left

    ; Returning from right (positive): subtract ~2+2/15, clamp at 0
    lda TorsoOffset
    cmp #3
    bcc .torso_center_zero
    sec
    sbc #2
    sta TorsoOffset
    lda TorsoTurnFrac
    clc
    adc #2
    cmp #15
    bcc .torso_center_store_frac_pos
    sec
    sbc #15
    sta TorsoTurnFrac
    lda TorsoOffset
    beq .after_torso_center
    sec
    sbc #1
    sta TorsoOffset
    jmp .after_torso_center
.torso_center_store_frac_pos:
    sta TorsoTurnFrac
    jmp .after_torso_center

.torso_center_from_left:
    ; Returning from left (negative): add ~2+2/15, clamp at 0
    lda TorsoOffset
    cmp #$FE                 ; -2 or -1
    bcs .torso_center_zero
    clc
    adc #2
    sta TorsoOffset
    lda TorsoTurnFrac
    clc
    adc #2
    cmp #15
    bcc .torso_center_store_frac_neg
    sec
    sbc #15
    sta TorsoTurnFrac
    lda TorsoOffset
    beq .after_torso_center
    clc
    adc #1
    sta TorsoOffset
    jmp .after_torso_center
.torso_center_store_frac_neg:
    sta TorsoTurnFrac
    jmp .after_torso_center

.torso_center_zero:
    lda #0
    sta TorsoOffset
    sta TorsoTurnFrac

.after_torso_center:

    ; ---- Compute view direction (0..7) ----
    lda LegHeading
    clc
    adc TorsoOffset
    lsr
    lsr
    lsr
    lsr
    lsr
    and #$07
    sta ViewDir

    ; ---- Leg direction (0..7) ----
    lda LegHeading
    lsr
    lsr
    lsr
    lsr
    lsr
    and #$07
    sta Tmp3            ; legDir 0..7

    ; Ground motion direction is based on leg heading relative to the view.
    lda Tmp3
    sec
    sbc ViewDir
    and #$07
    sta GroundDir

    ; ---- Build compass strip PF bytes in RAM (re-using MapPF* buffers) ----
    ; Copy 8 scanlines of the view-centered tape for ViewDir into MapPF* arrays.
    lda ViewDir
    asl
    asl
    asl
    tax                 ; X = ViewDir * 8
    ldy #0
.gl_comp_copy:
    lda CompassStripPF0L,x
    sta MapPF0L,y
    lda CompassStripPF1L,x
    sta MapPF1L,y
    lda CompassStripPF2L,x
    sta MapPF2L,y
    lda CompassStripPF0R,x
    sta MapPF0R,y
    lda CompassStripPF1R,x
    sta MapPF1R,y
    lda CompassStripPF2R,x
    sta MapPF2R,y
    inx
    iny
    cpy #8
    bne .gl_comp_copy

    ; Inject a legs-heading dot into the bottom two compass scanlines (rows 6 and 7).
    ; dotIdx = (legDir - viewDir + 4) & 7  (0..7, left-to-right across the tape)
    lda Tmp3
    sec
    sbc ViewDir
    clc
    adc #4
    and #$07
    tax

    ; Only one PF byte needs modification for the dot; use compact tables:
    ; - DotReg maps dotIdx -> which 8-byte PF row group (0..5) inside the 48-byte MapPF block.
    ; - DotMask is the PF-byte OR mask for that position.
    ;
    ; Memory layout note:
    ; `MapPF0L` is the base of a 48-byte contiguous block:
    ;   PF0L[0..7], PF1L[0..7], PF2L[0..7], PF0R[0..7], PF1R[0..7], PF2R[0..7]
    ; so indexing `MapPF0L + (DotReg*8 + row)` targets the desired PF byte.
    lda DotMask,x
    sta Tmp2
    lda DotReg,x
    asl
    asl
    asl                 ; *8 (row group)
    clc
    adc #6              ; row 6 offset
    tax
    lda MapPF0L,x
    ora Tmp2
    sta MapPF0L,x
    inx                 ; row 7 offset
    lda MapPF0L,x
    ora Tmp2
    sta MapPF0L,x

    ; Preload the FIRST visible compass scanline PF bytes into ZP.
    ; This avoids slow table reads on the first visible scanline (we clear VBLANK at cycle ~3).
    lda MapPF0L
    sta CompassLinePF0L
    lda MapPF1L
    sta CompassLinePF1L
    lda MapPF2L
    sta CompassLinePF2L
    lda MapPF0R
    sta CompassLinePF0R
    lda MapPF1R
    sta CompassLinePF1R
    lda MapPF2R
    sta CompassLinePF2R

    ; idx = (GearIdx*8) + legDir
    lda GearIdx
    asl
    asl
    asl
    clc
    adc Tmp3
    tax

    lda MoveDx,x
    sta Tmp0            ; dx
    lda MoveDy,x
    sta Tmp1            ; dy

    ; X position (16-bit: tile=hi, frac=lo)
    clc
    lda PlayerXFrac
    adc Tmp0
    sta PlayerXFrac
    lda PlayerXTile
    adc #0              ; carry from low-byte add
    ; sign-extend dx into carry adjustment
    ldy Tmp0
    bpl .dx_pos
    sec
    sbc #1
.dx_pos:
    sta PlayerXTile

    ; Y position
    clc
    lda PlayerYFrac
    adc Tmp1
    sta PlayerYFrac
    lda PlayerYTile
    adc #0
    ldy Tmp1
    bpl .dy_pos
    sec
    sbc #1
.dy_pos:
    sta PlayerYTile

    ; ---- Off-map countdown ----
    ; offmap if x<0 || x>=16 || y<0 || y>=8
    lda PlayerXTile
    bmi .offmap
    cmp #WORLD_W
    bcs .offmap
    lda PlayerYTile
    bmi .offmap
    cmp #WORLD_H
    bcc .in_map
.offmap:
    lda OffMapLo
    ora OffMapHi
    bne .dec_offmap
    lda #OFFMAP_START_LO
    sta OffMapLo
    lda #OFFMAP_START_HI
    sta OffMapHi
.dec_offmap:
    ; 16-bit decrement
    lda OffMapLo
    bne .dec_lo
    lda OffMapHi
    beq .offmap_expired
    dec OffMapHi
    lda #$FF
    sta OffMapLo
    jmp .after_offmap
.dec_lo:
    dec OffMapLo
    lda OffMapLo
    ora OffMapHi
    bne .after_offmap
.offmap_expired:
    lda #MODE_LOSE
    sta GameMode
    jmp .compute_bars_only
.in_map:
    lda #0
    sta OffMapLo
    sta OffMapHi

.after_offmap:

    ; ---- Tank rotation (~1 minute per 360) ----
    inc TankRotCtr
    lda TankRotCtr
    cmp #14
    bcc .no_tank_rot
    lda #0
    sta TankRotCtr
    ldx #0
.rot_loop:
    inc TankHeadingArr,x
    lda TankCooldownArr,x
    beq .rot_next
    dec TankCooldownArr,x
.rot_next:
    inx
    cpx #TANK_COUNT
    bne .rot_loop
.no_tank_rot:

    ; ---- LIDAR + tank projection (coarse 8-dir) ----
    lda #$FF
    sta BestDist
    sta TankActive
    lda #TANK_NONE
    sta TankXIndex

    ldx #0
.tank_loop:
    ; dx = playerX - tankX
    lda PlayerXTile
    sec
    sbc TankX,x
    sta Tmp0            ; dx (signed)
    ; dy = playerY - tankY
    lda PlayerYTile
    sec
    sbc TankY,x
    sta Tmp1            ; dy (signed)

    ; absdx -> Tmp2
    lda Tmp0
    bpl .absdx_ok
    eor #$FF
    clc
    adc #1
.absdx_ok:
    sta Tmp2

    ; absdy -> Tmp3
    lda Tmp1
    bpl .absdy_ok
    eor #$FF
    clc
    adc #1
.absdy_ok:
    sta Tmp3

    ; Distance for LIDAR timing/projection:
    ; Use Chebyshev distance (max(absdx,absdy)) and clamp to 8 so that
    ; "half map" distances (~8 tiles) map to ~60s fill time per README.
    lda Tmp2
    cmp Tmp3
    bcs .dist_use_x
    lda Tmp3
.dist_use_x:
    cmp #9
    bcc .dist_ok
    lda #8
.dist_ok:
    tay                 ; Y = dist (0..8)

    ; dirTankToPlayer (0..7) -> Tmp2
    ; Decide diagonal vs cardinal using abs comparisons
    lda Tmp2
    asl                 ; absdx*2
    cmp Tmp3
    bcc .maybe_vert
    ; horizontal
    lda Tmp0
    bpl .dir_e
    lda #6              ; W
    bne .dir_set
.dir_e:
    lda #2              ; E
    bne .dir_set
.maybe_vert:
    lda Tmp3
    asl                 ; absdy*2
    cmp Tmp2
    bcc .diag
    ; vertical
    lda Tmp1
    bpl .dir_s
    lda #0              ; N
    bne .dir_set
.dir_s:
    lda #4              ; S
    bne .dir_set
.diag:
    ; diagonal by signs
    lda Tmp0
    bmi .dx_neg
    lda Tmp1
    bmi .dir_ne
    lda #3              ; SE
    bne .dir_set
.dir_ne:
    lda #1              ; NE
    bne .dir_set
.dx_neg:
    lda Tmp1
    bmi .dir_nw
    lda #5              ; SW
    bne .dir_set
.dir_nw:
    lda #7              ; NW
.dir_set:
    sta Tmp2            ; dir tank->player

    ; Facing dir from tank heading (>>5) -> Tmp3
    lda TankHeadingArr,x
    lsr
    lsr
    lsr
    lsr
    lsr
    and #$07
    sta Tmp3

    ; absdiff = min((dir-facing)&7, 8-((dir-facing)&7)) -> A
    lda Tmp2
    sec
    sbc Tmp3
    and #$07
    sta Tmp1            ; diff
    cmp #5
    bcc .abs_ok
    lda #8
    sec
    sbc Tmp1
.abs_ok:
    ; A = absdiff

    ; Scanning: mech must be within the tank's front 45° arc.
    ; With our coarse 8-way direction model (45° per sector), that means absdiff==0.
    bne .not_scanning
    lda TankCooldownArr,x
    bne .not_scanning

    ; Crosshair break lock if player->tank dir == ViewDir
    ; player->tank = (tank->player + 4) & 7
    lda Tmp2
    clc
    adc #4
    and #$07
    cmp ViewDir
    bne .do_scan_add
    ; break lock
    lda #32
    sta TankCooldownArr,x
    lda #0
    sta TankFlagsArr,x
    jmp .proj_check

.do_scan_add:
    ; mark scanning
    lda #1
    sta TankFlagsArr,x

    ; Add distance-based rate to LIDAR fill (8.8 fixed)
    lda LidarLo
    clc
    adc LidarRate,y
    sta LidarLo
    lda LidarHi
    adc #0
    sta LidarHi
    cmp #$FF
    bne .proj_check
    lda #MODE_LOSE
    sta GameMode
    jmp .compute_bars_only

.not_scanning:
    lda #0
    sta TankFlagsArr,x

.proj_check:
    ; Determine visibility for projection: player->tank within +/-90deg => absdiffView <=2
    ; diffView = (player->tank - ViewDir) &7
    lda Tmp2
    clc
    adc #4
    and #$07
    sec
    sbc ViewDir
    and #$07
    sta Tmp1
    cmp #5
    bcc .abs_view_ok
    lda #8
    sec
    sbc Tmp1
.abs_view_ok:
    cmp #3
    bcs .gl_tank_next

    ; If closer than current best, select
    tya                 ; dist
    cmp BestDist
    bcs .gl_tank_next
    sta BestDist
    stx TankActive
    ; Store signed diff (player->tank - ViewDir) in BestDiff (-4..+3)
    lda Tmp1
    cmp #4
    bcc .diff_small
    sec
    sbc #8
.diff_small:
    sta BestDiff

.gl_tank_next:
    inx
    cpx #TANK_COUNT
    beq .tank_loop_done
    jmp .tank_loop
.tank_loop_done:

    ; Map selected tank -> cockpit overlay position.
    ;
    ; Inputs:
    ; - BestDiff: signed horizontal bearing of player->tank relative to ViewDir, in coarse 8-way units.
    ;            Range is typically [-2..+2] due to the +/-90° visibility gate.
    ; - BestDist: Chebyshev distance 0..8 (clamped)
    ; - TankHeadingArr[TankActive]: used for a subtle lateral bias to mimic rotation
    ;
    ; Output:
    ; - TankXIndex: 0..4 (far left..far right), or TANK_NONE if no visible tank
    lda TankActive
    cmp #$FF
    beq .compute_bars_only

    ; Add a small rotation-based lateral bias so the blip "wobbles" as tanks rotate.
    ldx TankActive
    lda TankHeadingArr,x
    lsr
    lsr
    lsr
    lsr
    lsr
    and #$07
    tax                 ; X = tank facing dir (0..7)
    lda BestDiff
    clc
    adc TankRotXBias,x

    ; Clamp signed diff to [-2..2] before converting to screen slot.
    bmi .clamp_neg
    cmp #3
    bcc .clamp_store
    lda #2
    bne .clamp_store
.clamp_neg:
    cmp #$FE            ; -2
    bcs .clamp_store
    lda #$FE
.clamp_store:
    sta Tmp0            ; Tmp0 = clamped signed diff (-2..2)

    ; Depth mapping (very coarse): far tanks compress toward the center.
    ; If dist >= 6, clamp to [-1..1] by reducing +/-2 to +/-1.
    lda BestDist
    cmp #6
    bcc .depth_done
    lda Tmp0
    cmp #2
    bne .depth_chk_neg2
    lda #1
    sta Tmp0
    bne .depth_done
.depth_chk_neg2:
    cmp #$FE            ; -2
    bne .depth_done
    lda #$FF            ; -1
    sta Tmp0
.depth_done:

    lda Tmp0
    clc
    adc #2              ; -> 0..4
    sta TankXIndex

.compute_bars_only:
    ; ---- LIDAR bar segments ----
    lda LidarHi
    cmp #$FF
    bne .lidar_not_full
    lda #16
    sta LidarSeg
    jmp .offmap_seg
.lidar_not_full:
    lsr
    lsr
    lsr
    lsr
    and #$0F
    sta LidarSeg

.offmap_seg:
    ; OffMapSeg: 0..16 segments of the orange countdown bar.
    ;
    ; The off-map timer is 600 frames (10s @ 60Hz). To map that to 16 segments
    ; cleanly without slow division, we approximate 600/16 = 37.5 by alternating
    ; subtract steps of 38 and 37. This yields a bar that shrinks evenly.
    lda OffMapLo
    ora OffMapHi
    bne .seg_compute
    sta OffMapSeg
    jmp UpdateAudio
.seg_compute:
    ; Tmp0:Tmp1 = remaining frames
    lda OffMapLo
    sta Tmp0
    lda OffMapHi
    sta Tmp1
    ldx #0
    stx OffMapSeg
.seg_loop:
    inc OffMapSeg

    ; step = 38 (even), 37 (odd)
    txa
    and #1
    beq .seg_step_38
    lda #37
    bne .seg_step_set
.seg_step_38:
    lda #38
.seg_step_set:
    sta Tmp2

    ; remaining -= step
    lda Tmp0
    sec
    sbc Tmp2
    sta Tmp0
    lda Tmp1
    sbc #0
    sta Tmp1

    bcc .seg_done            ; went negative => current segment count is correct
    lda Tmp0
    ora Tmp1
    beq .seg_done            ; exactly zero => done

    inx
    cpx #16
    bne .seg_loop
.seg_done:
    jmp UpdateAudio

; --------------------
; Audio update
; - Engine hum on channel 0 (always on; steady pitch during pause)
; - Footfall stomp on channel 1 for walking gears (R2,R1,1,2)
; - Skate whine on channel 1 for gear 3
; --------------------
UpdateAudio:
    ; Engine base (always)
    lda #$02
    sta AUDC0
    lda #$06
    sta AUDV0

    lda GameMode
    cmp #MODE_PLAY
    beq .aud_play
    jmp .aud_paused
.aud_play:

    ldx GearIdx
    lda EngineAUDF,x
    sta AUDF0
    ; Default: no bob/shake this frame
    lda #0
    sta BobOffset

    ; Gear 3: skate whine, no bobbing, no stomps
    cpx #5
    beq .aud_skate_play

    ; Neutral: no bobbing, no stomps
    cpx #2
    beq .aud_neutral_play

    ; ---- Walking gears (R2,R1,1,2): bobbing + footfalls ----
    lda BobPhase
    clc
    adc BobInc,x
    sta BobPhase

    ; BobOffset is a small 0/1 triangle wave derived from BobPhase
    lda BobPhase
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr                 ; >> 6
    and #$03
    cmp #1
    beq .bob_1
    cmp #2
    beq .bob_1
    lda #0
    bne .bob_store
.bob_1:
    lda #1
.bob_store:
    sta BobOffset

    ; StepTimer counts down to the next footfall
    lda StepTimer
    beq .step_reload
    dec StepTimer
    bne .after_footfall

    ; Footfall (timer hit 0)
    lda StepInterval,x
    sta StepTimer
    lda #2
    sta ShakeTimer
    lda #6
    sta StompTimer
    jmp .after_footfall

.step_reload:
    lda StepInterval,x
    sta StepTimer

.after_footfall:
    ; Shake modifies bobbing briefly
    lda ShakeTimer
    beq .no_shake
    dec ShakeTimer
    lda BobOffset
    eor #1
    sta BobOffset
.no_shake:

    ; Stomp sound if active
    lda StompTimer
    beq .aud_stomp_off
    dec StompTimer
    lda #$08
    sta AUDC1
    lda #$0F
    sta AUDV1
    lda #$1A
    sta AUDF1
    rts

.aud_skate_play:
    lda #0
    sta StepTimer
    sta ShakeTimer
    sta StompTimer
    sta BobOffset
    lda #$04
    sta AUDC1
    lda #$06
    sta AUDV1
    lda #$08
    sta AUDF1
    rts

.aud_neutral_play:
    lda #0
    sta StepTimer
    sta ShakeTimer
    sta StompTimer
    sta BobOffset
    jmp .aud_stomp_off

.aud_paused:
    ; Steady hum while paused/lost
    ldx #2
    lda EngineAUDF,x
    sta AUDF0
    lda #0
    sta StepTimer
    sta ShakeTimer
    sta StompTimer
    sta BobOffset
.aud_stomp_off:
    lda #$00
    sta AUDV1
    rts

; Overscan-time logic hook (display is off)
OverscanLogic:
    lda GameMode
    cmp #MODE_PAUSE
    bne .os_done
    ; Build the pause map during overscan (beam off).
    ; This is implemented as a banked call into bank2 (pause-only tables/routine),
    ; then returns to bank3 for the next frame.
    jsr CallBuildPauseMap
.os_done:
    rts

; --------------------
; Pause map builder
; --------------------
; The pause-map build routine is intentionally placed in **bank2**, along with
; the pause-only map column mask tables, to keep bank3 (kernel) smaller.
;
; See `BuildPauseMap` in the Bank2 segment.

; --------------------
; Visible kernel dispatch
; Called after VBLANK timer expires while VBLANK is still enabled.
; This routine selects the correct kernel and returns to MainLoop.
; --------------------
VisibleDispatch:
    lda GameMode
    beq PlayKernel
    cmp #MODE_PAUSE
    bne .vd_not_pause
    jmp PauseKernel
.vd_not_pause:
    jmp LoseKernel

; --------------------
; Play mode kernel (192 visible lines)
; Cycle-stable asymmetric playfield:
; - Left-half PF0/PF1/PF2 are written early in the scanline (before visible PF pixels).
; - Right-half PF0/PF1/PF2 are written later (after the left-half latch point).
; We keep CTRLPF reflect=0 and perform mid-scanline PF rewrites to avoid a doubled/mirrored PF.
; --------------------
PlayKernel:
    ; Initial colors while still VBLANK (not visible yet)
    lda #$00
    sta COLUBK
    lda #$0E
    sta COLUPF

    ; Align to scanline boundary, then enable display for the first visible line.
    ; Keep A=0 so we can clear VBLANK at cycle ~3 of the first visible scanline.
    lda #$00
    sta WSYNC
    sta VBLANK

    ; ---- Compass strip (N/NE/E/SE/S/SW/W/NW + pointer) ----
    ; First visible scanline must use ZP-fast reads (ROM table reads are too slow starting at cycle ~3).
    ; IMPORTANT: Asym PF timing (see Session 17: Asymmetrical Playfields).
    ; Right-side updates must be written in the safe windows (after left register finished):
    ; - PF0 right: CPU cycles ~28-49
    ; - PF1 right: CPU cycles ~39-54
    ; - PF2 right: CPU cycles ~49-65
    ;
    ; Left-side writes (ZP) complete by ~cycle 21 (we cleared VBLANK at ~cycle 3).
    lda CompassLinePF0L
    sta PF0
    lda CompassLinePF1L
    sta PF1
    lda CompassLinePF2L
    sta PF2
    ; Delay into PF0-right safe window
    bit Tmp0
    NOP2
    NOP2
    lda CompassLinePF0R
    sta PF0
    ; Delay into PF1-right safe window
    bit Tmp0
    NOP2
    lda CompassLinePF1R
    sta PF1
    ; Delay into PF2-right safe window
    NOP2
    NOP2
    lda CompassLinePF2R
    sta PF2

    ; Remaining compass lines (from RAM; start at cycle 0 on each scanline)
    ldy #1
    ldx #COMPASS_LINES-1
.compass:
    sta WSYNC
    lda MapPF0L,y
    sta PF0
    lda MapPF1L,y
    sta PF1
    lda MapPF2L,y
    sta PF2
    ; Delay into PF0-right safe window
    bit Tmp0
    NOP2
    NOP2
    lda MapPF0R,y
    sta PF0
    ; Delay into PF1-right safe window
    NOP2
    NOP2
    lda MapPF1R,y
    sta PF1
    ; Delay into PF2-right safe window
    bit Tmp0
    lda MapPF2R,y
    sta PF2
    iny
    dex
    bne .compass

    ; ---- LIDAR bar (red) ----
    lda #$46            ; red
    sta COLUPF
    ldy LidarSeg        ; 0..16
    ldx #LIDAR_BAR_LINES
.lidar:
    sta WSYNC
    lda BarPF0L,y
    sta PF0
    lda BarPF1L,y
    sta PF1
    lda BarPF2L,y
    sta PF2
    ; Delay into PF0-right safe window
    bit Tmp0
    NOP2
    NOP2
    lda BarPF0R,y
    sta PF0
    ; Delay into PF1-right safe window
    NOP2
    NOP2
    lda BarPF1R,y
    sta PF1
    ; Delay into PF2-right safe window
    bit Tmp0
    lda BarPF2R,y
    sta PF2
    dex
    bne .lidar

    ; ---- Off-map countdown bar (orange) ----
    lda #$3A            ; orange/yellow-ish
    sta COLUPF
    ldy OffMapSeg       ; 0..16
    ldx #COUNTDOWN_BAR_LINES
.countdown:
    sta WSYNC
    lda BarPF0L,y
    sta PF0
    lda BarPF1L,y
    sta PF1
    lda BarPF2L,y
    sta PF2
    ; Delay into PF0-right safe window
    bit Tmp0
    NOP2
    NOP2
    lda BarPF0R,y
    sta PF0
    ; Delay into PF1-right safe window
    NOP2
    NOP2
    lda BarPF1R,y
    sta PF1
    ; Delay into PF2-right safe window
    bit Tmp0
    lda BarPF2R,y
    sta PF2
    dex
    bne .countdown

    ; ---- Sky (blue background, white frame) ----
    lda #$84            ; blue-ish background
    sta COLUBK
    lda #$0E
    sta COLUPF

    ; Vertical bobbing: shift one scanline between sky and ground while keeping 192 visible lines.
    lda BobOffset
    sta Tmp0
    ldx #SKY_HEAD_LINES
    lda Tmp0
    beq .sky_head_count_ok
    dex
.sky_head_count_ok:
.sky_head:
    sta WSYNC
    lda #$10
    sta PF0
    lda #$00
    sta PF1
    sta PF2
    ; Delay into PF0-right safe window (left writes are quick because we reuse A=0 for PF1/PF2)
    bit Tmp0
    NOP2
    NOP2
    NOP2
    NOP2
    NOP2
    NOP2
    ; PF0 right = 0
    sta PF0
    ; Delay into PF1-right safe window
    NOP2
    NOP2
    NOP2
    NOP2
    ; PF1 right = 0
    sta PF1
    ; Delay into PF2-right safe window, then set border bit on far right
    NOP2
    NOP2
    NOP2
    lda #$80
    sta PF2
    dex
    bne .sky_head

    ; ---- Crosshair + tank overlay ----
    lda TankXIndex
    cmp #TANK_NONE
    bcc .overlay_ok
    lda #TANK_NONE
.overlay_ok:
    asl
    asl
    asl
    tay                 ; Y = TankXIndex * 8

    ldx #VIEW_OVERLAY_LINES
.overlay:
    sta WSYNC
    lda OverlayPF0L,y
    sta PF0
    lda OverlayPF1L,y
    sta PF1
    lda OverlayPF2L,y
    sta PF2
    ; Delay into PF0-right safe window
    bit Tmp0
    NOP2
    NOP2
    lda OverlayPF0R,y
    sta PF0
    ; Delay into PF1-right safe window
    NOP2
    NOP2
    lda OverlayPF1R,y
    sta PF1
    ; Delay into PF2-right safe window
    bit Tmp0
    lda OverlayPF2R,y
    sta PF2
    iny
    dex
    bne .overlay

    ldx #SKY_TAIL_LINES
.sky_tail:
    sta WSYNC
    lda #$10
    sta PF0
    lda #$00
    sta PF1
    sta PF2
    ; Delay into PF0-right safe window
    bit Tmp0
    NOP2
    NOP2
    NOP2
    NOP2
    NOP2
    NOP2
    sta PF0
    ; Delay into PF1-right safe window
    NOP2
    NOP2
    NOP2
    NOP2
    sta PF1
    ; Delay into PF2-right safe window
    NOP2
    NOP2
    NOP2
    lda #$80
    sta PF2
    dex
    bne .sky_tail

    ; ---- Horizon band (mountains/clouds) ----
    ; Shifted smoothly by view heading (legs + torso) for a turning cue.
    lda #$0A            ; grey-ish PF for mountains
    sta COLUPF
    lda LegHeading
    clc
    adc TorsoOffset
    lsr
    lsr
    lsr
    tay                 ; Y = (viewHeading >> 3) in range 0..31
    ldx #HORIZON_LINES
.horizon:
    sta WSYNC
    lda HorizonPF0L,y
    sta PF0
    lda HorizonPF1L,y
    sta PF1
    lda HorizonPF2L,y
    sta PF2
    ; Delay into PF0-right safe window
    bit Tmp0
    NOP2
    NOP2
    lda HorizonPF0R,y
    sta PF0
    ; Delay into PF1-right safe window
    NOP2
    NOP2
    lda HorizonPF1R,y
    sta PF1
    ; Delay into PF2-right safe window
    bit Tmp0
    lda HorizonPF2R,y
    sta PF2
    dex
    bne .horizon

    ; ---- Ground (brown background) ----
    lda #$28            ; brown-ish background
    sta COLUBK
    lda #$0E
    sta COLUPF

    ; Adjust ground line count opposite to sky bob
    ldx #GROUND_LINES
    lda BobOffset
    beq .ground_count_set
    inx
.ground_count_set:
    stx Tmp1

    ; Choose ground texture based on leg heading relative to view (GroundDir),
    ; and animate with frame parity when moving.
    lda GearIdx
    cmp #2                  ; Neutral => no motion / no animation
    beq .ground_static

    lda FrameCounter
    and #1
    sta Tmp0                ; parity 0/1
    lda GroundDir
    and #$07
    tax
    lda GroundGroup,x       ; 0..3
    asl                     ; *2
    ora Tmp0                ; + parity => 0..7
    tax
    lda GroundPF1L,x
    sta Tmp0                ; PF1 left
    lda GroundPF2L,x
    sta Tmp2                ; PF2 left
    lda GroundPF1R,x
    sta Tmp3                ; PF1 right
    lda GroundPF2R,x
    sta Tmp4                ; PF2 right
    jmp .ground_draw

.ground_static:
    ldx #0
    lda GroundPF1L,x
    sta Tmp0
    lda GroundPF2L,x
    sta Tmp2
    lda GroundPF1R,x
    sta Tmp3
    lda GroundPF2R,x
    sta Tmp4

.ground_draw:
    ldx Tmp1
.ground_loop:
    sta WSYNC
    lda #$10
    sta PF0
    lda Tmp0
    sta PF1
    lda Tmp2
    sta PF2
    ; Delay into PF0-right safe window
    bit Tmp0
    NOP2
    NOP2
    NOP2
    ; PF0 right = 0
    lda #$00
    sta PF0
    ; Delay into PF1-right safe window
    NOP2
    NOP2
    NOP2
    ; PF1 right from Tmp3
    lda Tmp3
    sta PF1
    ; Delay into PF2-right safe window
    NOP2
    NOP2
    ; PF2 right from Tmp4
    lda Tmp4
    sta PF2
    dex
    bne .ground_loop

.ground_done:

    ; ---- Cockpit UI (dark background, gear marker) ----
    lda #$02            ; very dark background
    sta COLUBK
    lda #$0E
    sta COLUPF

    ; Gear selector labels + moving highlight box (5 scanlines)
    lda GearIdx
    asl
    asl
    clc
    adc GearIdx
    tay                 ; Y = GearIdx * 5
    ldx #UI_MARKER_LINES
.gear_marker:
    sta WSYNC
    lda GearUIPF0L,y
    sta PF0
    lda GearUIPF1L,y
    sta PF1
    lda GearUIPF2L,y
    sta PF2
    ; Delay into PF0-right safe window
    bit Tmp0
    NOP2
    NOP2
    lda GearUIPF0R,y
    sta PF0
    ; Delay into PF1-right safe window
    NOP2
    NOP2
    lda GearUIPF1R,y
    sta PF1
    ; Delay into PF2-right safe window
    bit Tmp0
    lda GearUIPF2R,y
    sta PF2
    iny
    dex
    bne .gear_marker

    ldx #UI_LINES
.ui:
    sta WSYNC
    ; Solid cockpit panel across full width (placeholder)
    lda #$F0
    sta PF0
    lda #$FF
    sta PF1
    sta PF2
    ; Delay into PF0-right safe window
    bit Tmp0
    NOP2
    NOP2
    NOP2
    NOP2
    NOP2
    NOP2
    lda #$F0
    sta PF0
    ; Delay into PF1-right safe window
    NOP2
    NOP2
    NOP2
    lda #$FF
    sta PF1
    ; Delay into PF2-right safe window
    bit Tmp0
    NOP2
    sta PF2
    dex
    bne .ui

    ; End of visible region: align, re-enable VBLANK for overscan, return
    sta WSYNC
    lda #$02
    sta VBLANK
    rts

; --------------------
; Pause kernel (192 visible lines)
; Centered 16x8 map using MapPF* arrays (prebuilt during overscan while paused).
; --------------------
PauseKernel:
    lda #$00
    sta COLUBK
    lda PausePFColor
    sta COLUPF

    sta WSYNC
    lda #$00
    sta VBLANK

    ; Top margin: 64 lines
    lda #$00
    sta PF0
    sta PF1
    sta PF2
    NOP2
    NOP2
    lda #$00
    sta PF0
    sta PF1
    sta PF2

    ldx #63
.pause_top:
    sta WSYNC
    lda #$00
    sta PF0
    sta PF1
    sta PF2
    NOP2
    NOP2
    lda #$00
    sta PF0
    sta PF1
    sta PF2
    dex
    bne .pause_top

    ; Map: 8 rows, each row repeated for 8 scanlines (64 lines)
    ldy #0
.pause_row:
    ldx #8
.pause_row_lines:
    sta WSYNC
    lda MapPF0L,y
    sta PF0
    lda MapPF1L,y
    sta PF1
    lda MapPF2L,y
    sta PF2
    lda MapPF0R,y
    sta PF0
    lda MapPF1R,y
    sta PF1
    lda MapPF2R,y
    sta PF2
    dex
    bne .pause_row_lines
    iny
    cpy #8
    bne .pause_row

    ; Bottom margin: 64 lines
    ldx #64
.pause_bottom:
    sta WSYNC
    lda #$00
    sta PF0
    sta PF1
    sta PF2
    NOP2
    NOP2
    lda #$00
    sta PF0
    sta PF1
    sta PF2
    dex
    bne .pause_bottom

    sta WSYNC
    lda #$02
    sta VBLANK
    rts

; --------------------
; Lose kernel (192 visible lines)
; TODO: Add clear feedback + restart prompt.
; --------------------
LoseKernel:
    lda #$46            ; red background
    sta COLUBK
    lda #$0E
    sta COLUPF

    sta WSYNC
    lda #$00
    sta VBLANK

    ldx #NTSC_VISIBLE_LINES
.lose_lines:
    sta WSYNC
    lda #$00
    sta PF0
    sta PF1
    sta PF2
    NOP2
    NOP2
    lda #$00
    sta PF0
    sta PF1
    sta PF2
    dex
    bne .lose_lines

    sta WSYNC
    lda #$02
    sta VBLANK
    rts

; --------------------
; Game data tables (bank 3)
; --------------------

; Movement delta tables (signed 8-bit fractional units per frame)
; Index = GearIdx*8 + Dir8
; Dir8: 0=N,1=NE,2=E,3=SE,4=S,5=SW,6=W,7=NW
; GearIdx: 0=R2,1=R1,2=N,3=1,4=2,5=3
MoveDx:
    .byte $00,$FC,$FC,$FC,$00,$04,$04,$04   ; R2  (fast reverse)
    .byte $00,$FE,$FE,$FE,$00,$02,$02,$02   ; R1  (slow reverse)
    .byte $00,$00,$00,$00,$00,$00,$00,$00   ; N   (m=0)
    .byte $00,$02,$02,$02,$00,$FE,$FE,$FE   ; 1   (m=+1)
    .byte $00,$04,$04,$04,$00,$FC,$FC,$FC   ; 2   (m=+2)
    .byte $00,$06,$06,$06,$00,$FA,$FA,$FA   ; 3   (m=+3)

MoveDy:
    .byte $04,$04,$00,$FC,$FC,$FC,$00,$04   ; R2 (fast reverse)
    .byte $02,$02,$00,$FE,$FE,$FE,$00,$02   ; R1 (slow reverse)
    .byte $00,$00,$00,$00,$00,$00,$00,$00   ; N
    .byte $FE,$FE,$00,$02,$02,$02,$00,$FE   ; 1
    .byte $FC,$FC,$00,$04,$04,$04,$00,$FC   ; 2
    .byte $FA,$FA,$00,$06,$06,$06,$00,$FA   ; 3

; LIDAR fill rate by Chebyshev distance (0..8), 8.8 fixed fractional increment per frame.
; Calibrated to README:
; - dist=0 (very close): ~5s to fill
; - dist=8 (~half map): ~60s to fill
LidarRate:
    .byte $DA,$5C,$3A,$2B,$22,$1C,$18,$15,$12

; Ground motion pattern selection tables (playfield bytes).
; GroundDir (0..7) maps to one of 4 pattern groups:
; 0/4 forward/back, 2/6 strafe, 1/5 diag1, 3/7 diag2.
GroundGroup:
    .byte 0,2,1,3,0,2,1,3

; Pattern index = group*2 + parity (0 even, 1 odd). Each table has 8 entries.
GroundPF1L:
    .byte $CC,$33, $F0,$0F, $AA,$55, $66,$99
GroundPF2L:
    .byte $33,$CC, $0F,$F0, $55,$AA, $99,$66
GroundPF1R:
    .byte $33,$CC, $0F,$F0, $55,$AA, $99,$66
GroundPF2R:
    .byte $CC,$33, $F0,$0F, $AA,$55, $66,$99

; Compass legs-dot helper tables (8 entries)
; dotIdx = (legDir - viewDir + 4) & 7
; DotReg selects which 8-byte row group inside the 48-byte MapPF block to modify:
; 0=PF0L,1=PF1L,2=PF2L,3=PF0R,4=PF1R,5=PF2R
DotReg:
    .byte 0,1,1,2,3,4,4,5
DotMask:
    .byte $30,$60,$03,$18,$30,$60,$03,$18

; Tank overlay lateral bias by facing direction (0..7 from TankHeadingArr >> 5).
; Values are signed (-1,0,+1). This provides a subtle "rotation wobble" in the
; cockpit projection without requiring extra overlay tables.
TankRotXBias:
    .byte $00,$01,$01,$01,$00,$FF,$FF,$FF   ; N,NE,E,SE,S,SW,W,NW

; Engine pitch by gear (AUDF0 values; lower tends to be higher pitch)
EngineAUDF:
    .byte $12,$18,$1C,$18,$12,$0C   ; R2,R1,N,1,2,3 (R2 faster => higher pitch)

; Bobbing phase increment per frame (walking gears only)
BobInc:
    .byte $06,$04,$00,$04,$06,$00   ; R2,R1,N,1,2,3 (R2 faster => more bob)

; Footfall interval in frames (walking gears only)
StepInterval:
    .byte $14,$1E,$00,$1E,$14,$00   ; R2,R1,N,1,2,3  (20,30,0,30,20,0)

; --------------------
; Bank 3 data tables
; Keep kernel tables in the same bank as the visible kernel to avoid mid-frame bankswitching.
; --------------------
    ; NOTE:
    ; - Pause-only map column masks live in bank2 (`generated_pause_tables.inc`).
    ; - Visible-kernel tables live here in bank3 (`generated_kernel_tables.inc`).
    include "generated_kernel_tables.inc"

; --------------------
; Banked-call stub region (bank3)
; --------------------
; This stub is executed during overscan (beam off) to call the pause-map builder in bank2.
;
; IMPORTANT:
; The code bytes at runtime $FFE0 must be identical in bank3 and bank2, because
; the `sta BANK2` bankswitch happens *mid-stream* and the CPU will fetch the next
; instruction from the newly-selected bank at the same PC.
    ORG $3FE0
    RORG $FFE0
CallBuildPauseMap:
    lda #$00
    sta BANK2           ; switch to bank2 (pause-only)
    jsr BuildPauseMap
    lda #$00
    sta BANK3           ; back to bank3 (kernel)
    rts

    ; Vectors (must be in the last bank for F6)
    ORG $3FFC
    RORG $FFFC
    .word Reset
    .word Reset

