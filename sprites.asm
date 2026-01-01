; Sprite and playfield graphics tables
; These are purely static visual assets and layout tables.

CrosshairGfx
        ; 4-line crosshair (player 0 graphics).
        .byte %00011000
        .byte %00011000
        .byte %11111111
        .byte %00011000

; 16-line compass using playfield bits
; PF0/PF1/PF2 rows create the top-of-screen compass band.
CompassPF0
        .byte $F0,$F0,$00,$00,$F0,$F0,$00,$00,$F0,$F0,$00,$00,$F0,$F0,$00,$00
CompassPF1
        .byte $00,$00,$F0,$0F,$00,$00,$F0,$0F,$00,$00,$F0,$0F,$00,$00,$F0,$0F
CompassPF2
        .byte $F0,$0F,$00,$00,$F0,$0F,$00,$00,$F0,$0F,$00,$00,$F0,$0F,$00,$00

; 32-line cockpit PF with gear labels (blocky vertical list)
; Gear labels are baked into PF1/PF2 rows for the cockpit UI.
GearPF1
        .byte $00,$EE,$A2,$EE,$A8,$AE,$E4,$AC
        .byte $E4,$A4,$AE,$A0,$E0,$E0,$E0,$A0
        .byte $04,$0C,$04,$04,$0E,$0E,$02,$0E
        .byte $08,$0E,$0E,$02,$0E,$02,$0E,$00

GearPF2
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00

PausePF0
        .byte $00,$E0,$A0,$E0,$80,$80,$00,$00
PausePF1
        .byte $00,$4A,$AA,$EA,$AA,$AE,$00,$00
PausePF2
        .byte $00,$EE,$88,$EE,$28,$EE,$00,$00

; Map plotting masks (left half in PF1, right half in PF2).
MapMaskPF1
        .byte $80,$40,$20,$10,$08,$04,$02,$01
MapMaskPF2
        .byte $80,$40,$20,$10,$08,$04,$02,$01

; Playfield bit masks across PF1 (left) and PF2 (right) columns.
MaskPF1
        .byte $80,$40,$20,$10,$08,$04,$02,$01
        .byte $00,$00,$00,$00,$00,$00,$00,$00
MaskPF2
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $80,$40,$20,$10,$08,$04,$02,$01

; Status bar fill masks (0-16 segments across PF1/PF2).
BarPF1
        .byte $00,$80,$C0,$E0,$F0,$F8,$FC,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
BarPF2
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$E0,$F0,$F8,$FC,$FE,$FF

; Screen-space heading marker positions for the compass.
HeadingXTable
        .byte $20,$28,$30,$38,$40,$48,$50,$58

; Gear highlight box data (one bitmap per gear position).
GearBoxPtr
        .word GearBox0, GearBox1, GearBox2, GearBox3, GearBox4, GearBox5

GearBox0
        .byte $00,$FF,$81,$81,$81,$FF,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
GearBox1
        .byte $00,$00,$00,$00,$00,$00,$FF,$81
        .byte $81,$81,$FF,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
GearBox2
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$FF,$81,$81,$81,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
GearBox3
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $FF,$81,$81,$81,$FF,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
GearBox4
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$FF,$81,$81
        .byte $81,$FF,$00,$00,$00,$00,$00,$00
GearBox5
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$FF,$81,$81,$81,$FF,$00
