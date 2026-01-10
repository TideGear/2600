; Atari 2600 / TIA + RIOT equates (DASM)
; Write-only TIA registers are $00-$2C (mirrored); read-only are $30-$3D.
; On 6507, only 13 address lines are used; $F000-$FFFF mirrors to $1000-$1FFF.

; --------------------
; TIA write registers
; --------------------
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

; --------------------
; TIA read registers
; --------------------
CXM0P   = $30
CXM1P   = $31
CXP0FB  = $32
CXP1FB  = $33
CXM0FB  = $34
CXM1FB  = $35
CXBLPF  = $36
CXPPMM  = $37
INPT0   = $38
INPT1   = $39
INPT2   = $3A
INPT3   = $3B
INPT4   = $3C  ; joystick button (left)
INPT5   = $3D  ; joystick button (right)

; --------------------
; RIOT (6532) registers
; --------------------
SWCHA   = $0280 ; joystick directions
SWCHB   = $0282 ; console switches
INTIM   = $0284 ; timer output (read)
TIM64T  = $0296 ; set timer (write)

