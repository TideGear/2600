; Atari 2600 Mecha Simulator
; Builds with DASM
; Main game logic, input, rendering kernel, audio, and state update loop.

        processor 6502

; TIA registers
VSYNC   = $00
VBLANK  = $01
WSYNC   = $02
RSYNC   = $03
NUSIZ0  = $04
NUSIZ1  = $05
COLUP0  = $06
COLUP1  = $07
COLUPF  = $08
COLUBK  = $09
CTRLPF  = $0A
REFP0   = $0B
REFP1   = $0C
PF0     = $0D
PF1     = $0E
PF2     = $0F
RESP0   = $10
RESP1   = $11
RESM0   = $12
RESM1   = $13
RESBL   = $14
AUDC0   = $15
AUDC1   = $16
AUDF0   = $17
AUDF1   = $18
AUDV0   = $19
AUDV1   = $1A
GRP0    = $1B
GRP1    = $1C
ENAM0   = $1D
ENAM1   = $1E
ENABL   = $1F
HMP0    = $20
HMP1    = $21
HMM0    = $22
HMM1    = $23
HMBL    = $24
VDELP0  = $25
VDELP1  = $26
VDELBL  = $27
RESMP0  = $28
RESMP1  = $29
HMOVE   = $2A
HMCLR   = $2B
CXCLR   = $2C
INPT4   = $30

; RIOT
SWCHA   = $0280
SWCHB   = $0282
INTIM   = $0284
TIM64T  = $0296

        seg.u Variables
        org $80

; Persistent game state (zero page)
gEAR            ds 1
heading         ds 1
torso_offset    ds 1
view_heading    ds 1
input_delay     ds 1
turn_delay      ds 1
ground_seed     ds 1
line_seed       ds 1
bob_phase       ds 1
footfall_timer  ds 1
shake_timer     ds 1
stomp_timer     ds 1
frame_counter   ds 1
crosshair_start ds 1
box_ptr_lo      ds 1
box_ptr_hi      ds 1
pause_flag      ds 1
button_prev     ds 1
tap_timer       ds 1
player_x        ds 1
player_y        ds 1
move_accum      ds 1
tmp_dx          ds 1
tmp_dy          ds 1
tmp_forward     ds 1
tmp_side        ds 1
rel_dir         ds 1
dir_to_player   ds 1
tmp_abs_dx      ds 1
tmp_abs_dy      ds 1
tmp_dist        ds 1
lidar_accum     ds 1
lidar_bar       ds 1
lidar_rate_sum  ds 1
lidar_any       ds 1
tank_lidar0     ds 1
tank_lidar1     ds 1
tank_lidar2     ds 1
tank_lidar3     ds 1
tank_cd0        ds 1
tank_cd1        ds 1
tank_cd2        ds 1
tank_cd3        ds 1
tank_turn_timer_lo ds 1
tank_turn_timer_hi ds 1
offmap_flag     ds 1
offmap_sec_tick ds 1
offmap_seconds  ds 1
offmap_bar      ds 1
offmap_timer_lo ds 1
offmap_timer_hi ds 1
game_over_flag  ds 1
tank_line0      ds 1
tank_line1      ds 1
tank_line2      ds 1
tank_line3      ds 1
tank_pf1_0      ds 1
tank_pf1_1      ds 1
tank_pf1_2      ds 1
tank_pf1_3      ds 1
tank_pf2_0      ds 1
tank_pf2_1      ds 1
tank_pf2_2      ds 1
tank_pf2_3      ds 1
map_pf1         ds 32
map_pf2         ds 32

        seg Code
        org $F000

Reset
        ; Standard 2600 init: interrupts off, decimal off, stack set, clear RAM.
        sei
        cld
        ldx #$FF
        txs
        lda #0
ClearRAM
        sta 0,x
        dex
        bne ClearRAM

        ; Initialize gameplay state (neutral gear, facing north, centered map).
        lda #2          ; start at Neutral
        sta gEAR
        lda #0
        sta heading
        sta torso_offset
        sta view_heading
        sta pause_flag
        sta button_prev
        sta tap_timer
        sta move_accum
        sta lidar_accum
        sta lidar_bar
        sta lidar_rate_sum
        sta lidar_any
        sta tank_lidar0
        sta tank_lidar1
        sta tank_lidar2
        sta tank_lidar3
        sta tank_cd0
        sta tank_cd1
        sta tank_cd2
        sta tank_cd3
        sta offmap_flag
        sta offmap_bar
        sta game_over_flag
        lda #16
        sta player_x
        sta player_y
        lda #60
        sta offmap_sec_tick
        lda #10
        sta offmap_seconds
        lda #$02
        sta offmap_timer_hi
        lda #$58
        sta offmap_timer_lo
        lda #$C2
        sta tank_turn_timer_lo
        lda #$01
        sta tank_turn_timer_hi
        lda #$6A
        sta ground_seed
        lda #72
        sta crosshair_start

MainLoop
        ; VBlank -> Kernel -> Overscan forever.
        jsr VBlank
        jsr Kernel
        jsr Overscan
        jmp MainLoop

VBlank
        ; 3-line VSYNC
        lda #2
        sta VSYNC
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #0
        sta VSYNC

        ; Enter VBlank
        lda #$2
        sta VBLANK

        ; Color setup for this frame.
        lda #$1E
        sta COLUBK
        lda #$C6
        sta COLUPF
        lda #$1C
        sta COLUP0
        lda #$0E
        sta COLUP1

        ; Input and state updates during VBlank.
        jsr UpdatePauseInput
        jsr UpdateMap
        jsr UpdateOffmap
        lda pause_flag
        beq .run_game
        ; If paused, mute channel 0 and keep the engine hum running.
        lda #0
        sta AUDV0
        jsr UpdateEngineHumPaused
        jmp .skip_game
.run_game
        lda game_over_flag
        beq .run_updates
        lda #1
        sta pause_flag
        jmp .skip_game
.run_updates
        jsr ReadInputs
        jsr UpdateViewHeading
        jsr UpdateMotion
        jsr UpdateTankRotation
        jsr UpdateTanks
        jsr UpdateSound
.skip_game

        ; Exit VBlank.
        lda #0
        sta VBLANK
        rts

ReadInputs
        ; Gear shift with up/down, turn/torso with left/right.
        lda input_delay
        beq .check_gear
        dec input_delay
.check_gear
        lda SWCHA
        and #$10        ; up
        bne .check_down
        lda input_delay
        bne .check_down
        lda gEAR
        cmp #5
        beq .check_down
        inc gEAR
        lda #6
        sta input_delay
.check_down
        lda SWCHA
        and #$20        ; down
        bne .check_turn
        lda input_delay
        bne .check_turn
        lda gEAR
        beq .check_turn
        dec gEAR
        lda #6
        sta input_delay
.check_turn
        lda turn_delay
        beq .turn_inputs
        dec turn_delay
.turn_inputs
        ; Button pressed -> torso twist, otherwise turn heading.
        lda INPT4
        bmi .turn_heading
        jmp .turn_torso
.turn_heading
        lda SWCHA
        and #$40        ; left
        bne .check_right
        lda turn_delay
        bne .check_right
        lda heading
        beq .wrap_left
        dec heading
        jmp .set_turn_delay
.wrap_left
        lda #7
        sta heading
.set_turn_delay
        lda #4
        sta turn_delay
.check_right
        lda SWCHA
        and #$80        ; right
        bne .done
        lda turn_delay
        bne .done
        lda heading
        cmp #7
        bne .inc_heading
        lda #0
        sta heading
        jmp .set_turn_delay2
.inc_heading
        inc heading
.set_turn_delay2
        lda #4
        sta turn_delay
        jmp .done
.turn_torso
        ; Clamp torso twist to +/-2 (90 degrees) while holding button.
        lda SWCHA
        and #$40        ; left
        bne .check_torso_right
        lda turn_delay
        bne .check_torso_right
        lda torso_offset
        cmp #$FE
        beq .check_torso_right
        sec
        sbc #1
        sta torso_offset
        lda #4
        sta turn_delay
.check_torso_right
        lda SWCHA
        and #$80        ; right
        bne .done
        lda turn_delay
        bne .done
        lda torso_offset
        cmp #2
        beq .done
        clc
        adc #1
        sta torso_offset
        lda #4
        sta turn_delay
.done
        rts

UpdatePauseInput
        ; Detect double-tap on the button to toggle pause.
        lda INPT4
        and #$80
        bne .released
        lda #1
        bne .have_current
.released
        lda #0
.have_current
        tax
        lda button_prev
        bne .update_prev
        cpx #0
        beq .update_prev
        lda tap_timer
        beq .start_timer
        lda #0
        sta tap_timer
        lda pause_flag
        eor #1
        sta pause_flag
        lda #0
        sta AUDV0
        sta AUDV1
        jmp .update_prev
.start_timer
        lda #20
        sta tap_timer
.update_prev
        stx button_prev
        lda tap_timer
        beq .done
        dec tap_timer
.done
        rts

UpdateViewHeading
        ; Combine leg heading + torso offset for rendering.
        lda heading
        clc
        adc torso_offset
        and #$07
        sta view_heading
        rts

UpdateEngineHumPaused
        ; Constant deep hum during pause (channel 1).
        lda #$08
        sta AUDC1
        lda #$0A
        sta AUDV1
        lda #$18
        sta AUDF1
        rts

UpdateEngineHum
        ; Deep hum that rises slightly with speed (channel 1).
        lda #$08
        sta AUDC1
        lda #$0A
        sta AUDV1
        ldx gEAR
        lda AbsSpeedTable,x
        tax
        lda HumFreqTable,x
        sta AUDF1
        rts

UpdateTankRotation
        ; Rotate tanks slowly (one 45-degree step about every 450 frames).
        lda tank_turn_timer_lo
        ora tank_turn_timer_hi
        beq .rotate
        dec tank_turn_timer_lo
        bne .done
        dec tank_turn_timer_hi
        jmp .done
.rotate
        lda #$C2
        sta tank_turn_timer_lo
        lda #$01
        sta tank_turn_timer_hi
        ldx #0
.rot_loop
        lda TankDir,x
        clc
        adc #1
        and #$07
        sta TankDir,x
        lda tank_cd0,x
        beq .next
        dec tank_cd0,x
.next
        inx
        cpx #4
        bne .rot_loop
.done
        rts

UpdateOffmap
        ; Update off-map countdown and bar.
        lda offmap_flag
        bne .countdown
        lda #0
        sta offmap_bar
        rts
.countdown
        lda offmap_timer_lo
        ora offmap_timer_hi
        bne .tick
        lda #1
        sta game_over_flag
        rts
.tick
        lda offmap_timer_lo
        bne .dec_lo
        dec offmap_timer_hi
.dec_lo
        dec offmap_timer_lo
        dec offmap_sec_tick
        bne .update_bar
        lda #60
        sta offmap_sec_tick
        lda offmap_seconds
        beq .update_bar
        dec offmap_seconds
.update_bar
        ldx offmap_seconds
        lda OffmapBarTable,x
        sta offmap_bar
        lda offmap_timer_lo
        ora offmap_timer_hi
        bne .done
        lda #1
        sta game_over_flag
.done
        rts

AbsA
        ; Absolute value of signed byte in A.
        bpl .abs_done
        eor #$FF
        clc
        adc #1
.abs_done
        rts

DirFromDelta
        ; Convert tmp_dx/tmp_dy to an 8-way direction index (0-7).
        lda tmp_dx
        beq .dir_y
        lda tmp_dy
        beq .dir_x
        lda tmp_dx
        bmi .dx_neg
        lda tmp_dy
        bmi .dx_pos_dy_neg
        lda #3
        rts
.dx_pos_dy_neg
        lda #1
        rts
.dx_neg
        lda tmp_dy
        bmi .dx_neg_dy_neg
        lda #5
        rts
.dx_neg_dy_neg
        lda #7
        rts
.dir_y
        lda tmp_dy
        bmi .dir_n
        lda #4
        rts
.dir_n
        lda #0
        rts
.dir_x
        lda tmp_dx
        bmi .dir_w
        lda #2
        rts
.dir_w
        lda #6
        rts

MovePlayer
        ; Integrate movement on a 32x32 map based on gear speed.
        ldx gEAR
        lda AbsSpeedTable,x
        beq .done
        clc
        adc move_accum
        sta move_accum
        cmp #3
        bcc .done
        sec
        sbc #3
        sta move_accum

        lda SpeedTable,x
        bmi .reverse
        lda heading
        bne .move
.reverse
        lda heading
        clc
        adc #4
        and #$07
.move
        tax
        lda #0
        sta tmp_dist
        lda DirDX,x
        clc
        adc player_x
        sta tmp_abs_dx
        lda tmp_abs_dx
        bmi .offmap_x
        cmp #32
        bcs .offmap_x
        lda tmp_abs_dx
        sta player_x
        jmp .check_y
.offmap_x
        lda #1
        sta tmp_dist
.check_y
        lda DirDY,x
        clc
        adc player_y
        sta tmp_abs_dy
        lda tmp_abs_dy
        bmi .offmap_y
        cmp #32
        bcs .offmap_y
        lda tmp_abs_dy
        sta player_y
        jmp .check_offmap
.offmap_y
        lda #1
        sta tmp_dist
.check_offmap
        lda tmp_dist
        beq .clear_offmap
        lda offmap_flag
        bne .done
        lda #1
        sta offmap_flag
        lda #$02
        sta offmap_timer_hi
        lda #$58
        sta offmap_timer_lo
        lda #10
        sta offmap_seconds
        lda #60
        sta offmap_sec_tick
        jmp .done
.clear_offmap
        lda offmap_flag
        beq .done
        lda #0
        sta offmap_flag
        sta offmap_bar
        lda #$02
        sta offmap_timer_hi
        lda #$58
        sta offmap_timer_lo
        lda #10
        sta offmap_seconds
        lda #60
        sta offmap_sec_tick
.done
        rts

UpdateMap
        ; Rebuild the 32x32 pause map buffer each frame.
        ldx #0
.clear
        lda #0
        sta map_pf1,x
        sta map_pf2,x
        inx
        cpx #32
        bne .clear

        lda player_x
        lsr
        sta tmp_dx
        lda player_y
        sta tmp_dy
        jsr PlotMapDot

        lda view_heading
        tax
        lda DirDX,x
        clc
        adc player_x
        bmi .skip_player_head
        cmp #32
        bcs .skip_player_head
        lsr
        sta tmp_dx
        lda DirDY,x
        clc
        adc player_y
        bmi .skip_player_head
        cmp #32
        bcs .skip_player_head
        sta tmp_dy
        jsr PlotMapDot
.skip_player_head

        ldx #0
.tank_loop
        ; Plot tanks and their facing markers on the map.
        lda TankX,x
        lsr
        sta tmp_dx
        lda TankY,x
        sta tmp_dy
        jsr PlotMapDot

        lda TankDir,x
        tay
        lda TankX,x
        clc
        adc DirDX,y
        bmi .skip_tank_head
        cmp #32
        bcs .skip_tank_head
        lsr
        sta tmp_dx
        lda TankY,x
        clc
        adc DirDY,y
        bmi .skip_tank_head
        cmp #32
        bcs .skip_tank_head
        sta tmp_dy
        jsr PlotMapDot
.skip_tank_head

        inx
        cpx #4
        bne .tank_loop
        rts

PlotMapDot
        ; Plot a single dot into the 32x32 map (PF1 for left 8, PF2 for right 8).
        lda tmp_dx
        cmp #16
        bcs .done
        lda tmp_dy
        cmp #32
        bcs .done
        lda tmp_dx
        cmp #8
        bcc .pf1
        sec
        sbc #8
        tax
        lda MapMaskPF2,x
        ldy tmp_dy
        ora map_pf2,y
        sta map_pf2,y
        rts
.pf1
        tax
        lda MapMaskPF1,x
        ldy tmp_dy
        ora map_pf1,y
        sta map_pf1,y
.done
        rts

UpdateTanks
        ; Project tank positions into cockpit view as PF masks.
        lda #0
        sta lidar_rate_sum
        sta lidar_any
        ldx #0
.tank_iter
        ; Relative position without map wrap.
        lda TankX,x
        sec
        sbc player_x
        sta tmp_dx
        lda TankY,x
        sec
        sbc player_y
        sta tmp_dy
        lda TankDir,x
        sec
        sbc view_heading
        and #$07
        sta rel_dir

        lda tmp_dx
        jsr AbsA
        sta tmp_abs_dx
        lda tmp_dy
        jsr AbsA
        sta tmp_abs_dy
        lda tmp_abs_dx
        cmp tmp_abs_dy
        bcs .use_dx
        lda tmp_abs_dy
.use_dx
        sta tmp_dist

        jsr DirFromDelta
        sta dir_to_player
        lda TankDir,x
        sec
        sbc dir_to_player
        and #$07
        tay
        lda tank_cd0,x
        bne .skip_lidar
        tya
        beq .activate_lidar
        cmp #1
        beq .activate_lidar
        cmp #7
        beq .activate_lidar
        lda #0
        sta tank_lidar0,x
        jmp .skip_lidar
.activate_lidar
        lda #1
        sta tank_lidar0,x
.skip_lidar

        ; Rotate world delta into view-forward/side axes.
        lda view_heading
        and #$07
        tay
        lda tmp_dx
        sta tmp_forward
        lda tmp_dy
        sta tmp_side

        cpy #0
        beq .heading_n
        cpy #1
        beq .heading_ne
        cpy #2
        beq .heading_e
        cpy #3
        beq .heading_se
        cpy #4
        beq .heading_s
        cpy #5
        beq .heading_sw
        cpy #6
        beq .heading_w
        ; heading 7
.heading_nw
        lda tmp_dx
        sec
        sbc tmp_dy
        jsr NegateA
        sta tmp_forward
        lda tmp_dx
        clc
        adc tmp_dy
        jsr NegateA
        sta tmp_side
        jmp .post_heading
.heading_n
        lda tmp_dy
        jsr NegateA
        sta tmp_forward
        lda tmp_dx
        sta tmp_side
        jmp .post_heading
.heading_ne
        lda tmp_dy
        clc
        adc tmp_dx
        jsr NegateA
        sta tmp_forward
        lda tmp_dx
        sec
        sbc tmp_dy
        sta tmp_side
        jmp .post_heading
.heading_e
        lda tmp_dx
        sta tmp_forward
        lda tmp_dy
        sta tmp_side
        jmp .post_heading
.heading_se
        lda tmp_dx
        sec
        sbc tmp_dy
        sta tmp_forward
        lda tmp_dx
        clc
        adc tmp_dy
        sta tmp_side
        jmp .post_heading
.heading_s
        lda tmp_dy
        sta tmp_forward
        lda tmp_dx
        jsr NegateA
        sta tmp_side
        jmp .post_heading
.heading_sw
        lda tmp_dy
        clc
        adc tmp_dx
        sta tmp_forward
        lda tmp_dy
        sec
        sbc tmp_dx
        sta tmp_side
        jmp .post_heading
.heading_w
        lda tmp_dx
        jsr NegateA
        sta tmp_forward
        lda tmp_dy
        jsr NegateA
        sta tmp_side
.post_heading
        ; Scale diagonals for a crude distance match.
        tya
        and #$01
        beq .no_diag_scale
        lda tmp_forward
        jsr AsrA
        sta tmp_forward
        lda tmp_side
        jsr AsrA
        sta tmp_side
.no_diag_scale
        ; Reject behind player or too far, then convert to scanline.
        lda tmp_forward
        beq .tank_hidden
        bmi .tank_hidden
        cmp #16
        bcc .depth_ok
        lda #15
.depth_ok
        tay
        lda DepthLineTable,y
        sta tank_line0,x

        ; Horizontal placement with directional nudge based on relative facing.
        lda tmp_side
        clc
        adc #8
        cmp #16
        bcs .tank_hidden
        tay
        lda rel_dir
        cmp #2
        bcc .check_left
        cmp #5
        bcc .offset_right
.check_left
        cmp #6
        bcc .no_offset
        tya
        beq .no_offset
        dey
        jmp .no_offset
.offset_right
        cpy #15
        beq .no_offset
        iny
.no_offset
        lda MaskPF1,y
        sta tank_pf1_0,x
        lda MaskPF2,y
        sta tank_pf2_0,x

        ; Close tanks render slightly wider (two bits).
        lda tmp_forward
        cmp #4
        bcs .tank_done
        tya
        beq .tank_done
        dey
        lda MaskPF1,y
        ora tank_pf1_0,x
        sta tank_pf1_0,x
        lda MaskPF2,y
        ora tank_pf2_0,x
        sta tank_pf2_0,x

        lda tank_lidar0,x
        beq .after_lidar
        lda #1
        sta lidar_any
        lda tmp_dist
        beq .after_lidar
        cmp #16
        bcc .rate_ok
        lda #16
.rate_ok
        tay
        lda LidarRateTable,y
        clc
        adc lidar_rate_sum
        sta lidar_rate_sum

        lda tmp_side
        beq .check_crosshair
        cmp #$FF
        beq .check_crosshair
        jmp .after_lidar
.check_crosshair
        lda tank_line0,x
        sec
        sbc crosshair_start
        cmp #4
        bcs .after_lidar
        lda #0
        sta tank_lidar0,x
        lda #1
        sta tank_cd0,x
.after_lidar
.tank_done
        inx
        cpx #4
        bne .tank_iter
        lda lidar_rate_sum
        beq .done_lidar
        lda lidar_accum
        clc
        adc lidar_rate_sum
        sta lidar_accum
        bcc .done_lidar
        lda lidar_bar
        cmp #16
        bcs .done_lidar
        inc lidar_bar
.done_lidar
        rts
.tank_hidden
        ; Clear render data for tanks outside view.
        lda #0
        sta tank_line0,x
        sta tank_pf1_0,x
        sta tank_pf2_0,x
        inx
        cpx #4
        bne .tank_iter
        rts

NegateA
        ; Two's complement negate.
        eor #$FF
        clc
        adc #1
        rts

AsrA
        ; Arithmetic shift right (preserve sign).
        lsr
        bcc .asr_done
        ora #$80
.asr_done
        rts

UpdateMotion
        ; Update ground scroll, bobbing, and player motion.
        lda frame_counter
        clc
        adc #1
        sta frame_counter

        ldx gEAR
        lda SpeedTable,x
        beq .still

        cpx #5
        beq .skate_move

        clc
        adc ground_seed
        adc heading
        sta ground_seed

        lda bob_phase
        clc
        adc AbsSpeedTable,x
        sta bob_phase

        lda bob_phase
        and #$10
        lsr
        lsr
        lsr
        lsr
        clc
        adc #72
        sta crosshair_start

        jsr MovePlayer

        lda footfall_timer
        beq .trigger_footfall
        dec footfall_timer
        jmp .no_move
.trigger_footfall
        lda AbsSpeedTable,x
        beq .no_move
        lda #16
        sec
        sbc AbsSpeedTable,x
        sta footfall_timer
        lda #4
        sta shake_timer
        lda #6
        sta stomp_timer
        jmp .no_move
.skate_move
        clc
        adc ground_seed
        adc heading
        sta ground_seed
        lda #72
        sta crosshair_start
        jsr MovePlayer
        jmp .no_move
.still
        lda #72
        sta crosshair_start
.no_move
        lda shake_timer
        beq .done
        dec shake_timer
.done
        rts

UpdateSound
        ; Engine hum on channel 1, stomps or skate whine on channel 0.
        jsr UpdateEngineHum
        lda gEAR
        cmp #5
        beq .skate_sound

        lda stomp_timer
        beq .no_stomp
        dec stomp_timer
        lda #$08
        sta AUDC0
        lda #$0F
        sta AUDV0
        lda #$05
        sta AUDF0
        rts
.no_stomp
        lda #0
        sta AUDV0
        rts

.skate_sound
        lda #$0A
        sta AUDC0
        lda #$0C
        sta AUDV0
        lda frame_counter
        and #$0F
        sta AUDF0
        rts

Kernel
        ; Main visible kernel: compass, ground, crosshair, cockpit.
        lda pause_flag
        beq .normal_kernel
        jmp PauseKernel
.normal_kernel
        lda #0
        sta GRP0
        sta GRP1
        sta ENAM0
        sta ENAM1
        sta ENABL
        sta HMCLR

        lda #$00
        sta CTRLPF

        ; Position crosshair and heading marker.
        lda #$50
        sta RESP0
        lda #$20
        sta RESP1
        lda view_heading
        tax
        lda HeadingXTable,x
        sta RESBL

        lda shake_timer
        beq .no_shake
        lda frame_counter
        and #$01
        beq .shake_left
        lda #$10
        bne .set_shake
.shake_left
        lda #$F0
.set_shake
        sta HMP0
        sta HMOVE
        bne .shake_done
.no_shake
        lda #0
        sta HMP0
        sta HMOVE
.shake_done

        ; top compass
        ldx #0
CompassLoop
        ; Compass banner uses playfield + ball for heading indicator.
        sta WSYNC
        lda #2
        sta ENABL
        lda CompassPF0,x
        sta PF0
        lda CompassPF1,x
        sta PF1
        lda CompassPF2,x
        sta PF2
        lda #0
        sta GRP0
        sta GRP1
        inx
        cpx #16
        bne CompassLoop
        lda #0
        sta ENABL

        ; status bars (lidar + off-map countdown)
        ldx #0
StatusLoop
        sta WSYNC
        lda #0
        sta PF0
        cpx #4
        bcs .offmap_bar
        lda #$46
        sta COLUPF
        lda lidar_bar
        tay
        lda BarPF1,y
        sta PF1
        lda BarPF2,y
        sta PF2
        jmp .status_next
.offmap_bar
        lda #$E8
        sta COLUPF
        lda offmap_bar
        tay
        lda BarPF1,y
        sta PF1
        lda BarPF2,y
        sta PF2
.status_next
        inx
        cpx #8
        bne StatusLoop
        lda #$C6
        sta COLUPF

        ; ground region
        ; Ground PF with pseudo-random dirt/rock pattern.
        lda ground_seed
        clc
        adc view_heading
        sta line_seed
        ldx #0
GroundLoop
        sta WSYNC
        lda line_seed
        asl
        bcc .no_xor
        eor #$1D
.no_xor
        sta line_seed
        lda line_seed
        and #$F0
        sta PF0
        lda line_seed
        sta PF1
        lda line_seed
        eor #$AA
        sta PF2

        ; Merge tank masks into ground PF.
        cpx tank_line0
        bne .tank1
        lda PF1
        ora tank_pf1_0
        sta PF1
        lda PF2
        ora tank_pf2_0
        sta PF2
.tank1
        cpx tank_line1
        bne .tank2
        lda PF1
        ora tank_pf1_1
        sta PF1
        lda PF2
        ora tank_pf2_1
        sta PF2
.tank2
        cpx tank_line2
        bne .tank3
        lda PF1
        ora tank_pf1_2
        sta PF1
        lda PF2
        ora tank_pf2_2
        sta PF2
.tank3
        cpx tank_line3
        bne .after_tanks
        lda PF1
        ora tank_pf1_3
        sta PF1
        lda PF2
        ora tank_pf2_3
        sta PF2
.after_tanks

        lda #0
        sta GRP1

        ; Draw crosshair at bob-adjusted vertical position.
        txa
        sec
        sbc crosshair_start
        cmp #4
        bcs .no_crosshair
        tay
        lda CrosshairGfx,y
        sta GRP0
        jmp .after_crosshair
.no_crosshair
        lda #0
        sta GRP0
.after_crosshair

        inx
        cpx #136
        bne GroundLoop

        ; cockpit / gear area
        ; Gear labels and highlight box.
        lda gEAR
        asl
        tax
        lda GearBoxPtr,x
        sta box_ptr_lo
        lda GearBoxPtr+1,x
        sta box_ptr_hi
        ldx #0
CockpitLoop
        sta WSYNC
        lda GearPF1,x
        sta PF1
        lda GearPF2,x
        sta PF2
        lda #0
        sta PF0

        lda #0
        sta GRP0

        txa
        tay
        lda (box_ptr_lo),y
        sta GRP1

        inx
        cpx #32
        bne CockpitLoop

        rts

PauseKernel
        ; Pause screen with text banner and center map.
        lda #0
        sta GRP0
        sta GRP1
        sta PF0
        sta PF1
        sta PF2
        sta ENABL
        sta ENAM0
        sta ENAM1
        lda #$00
        sta COLUBK
        lda #$C4
        sta COLUPF
        lda #0
        sta CTRLPF
        ldx #0
PauseLoop
        sta WSYNC
        ; Draw PAUSE text near the top.
        cpx #40
        bcc .check_map
        cpx #48
        bcs .check_map
        txa
        sec
        sbc #40
        tay
        lda PausePF0,y
        sta PF0
        lda PausePF1,y
        sta PF1
        lda PausePF2,y
        sta PF2
        jmp .pause_next
.check_map
        ; Draw 32x32 map centered in the pause screen.
        cpx #80
        bcc .pause_clear
        cpx #112
        bcs .pause_clear
        txa
        sec
        sbc #80
        tay
        lda lidar_any
        beq .map_color
        lda frame_counter
        and #$10
        beq .map_color
        lda #$46
        sta COLUPF
.map_color
        lda #0
        sta PF0
        lda map_pf1,y
        sta PF1
        lda map_pf2,y
        sta PF2
        jmp .pause_next
.pause_clear
        lda #0
        sta PF0
        sta PF1
        sta PF2
.pause_next
        lda #$C4
        sta COLUPF
        inx
        cpx #192
        bne PauseLoop
        rts

Overscan
        ; Overscan lines to finish the frame.
        lda #2
        sta VBLANK
        ldx #30
OverscanLoop
        sta WSYNC
        dex
        bne OverscanLoop
        lda #0
        sta VBLANK
        rts

; Tables
SpeedTable
        .byte $FE,$FF,$00,$01,$02,$03
AbsSpeedTable
        .byte $02,$01,$00,$01,$02,$03

HumFreqTable
        .byte $18,$16,$14,$12

; Sprite and playfield graphics (UI, compass, map masks, etc).
        include "sprites.asm"
        include "map.asm"

; Projection and direction tables used by logic.
OffmapBarTable
        .byte 0,2,3,5,6,8,10,11,13,14,16

LidarRateTable
        .byte 0,14,12,10,8,7,6,5,4,4,3,3,2,2,2,1,1

DepthLineTable
        .byte 0,44,48,52,56,60,64,68,72,76,80,84,88,92,96,100

DirDX
        .byte 0,1,1,1,0,$FF,$FF,$FF
DirDY
        .byte $FF,$FF,0,1,1,1,0,$FF

        org $FFFA
        .word Reset
        .word Reset
        .word Reset
