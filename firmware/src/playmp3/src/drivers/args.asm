    module Args

; HL - argv
; DE - arg buff
; B - len 
parseOne:
    ld b, 0
.skipWhiteSpace:
    ld a, (hl) 
    cp ' ' : jr nz, .load 
    and a  : jr z, .exit
    cp ':' : jr z, .exit
    cp 13  : jr z, .exit
    inc hl : jr .skipWhiteSpace
.load
    ld a, (hl)
    cp 13  : jr z, .exit
    cp ':' : jr z, .exit
    cp ' ' : jr z, .exit
    and a  : jr z, .exit
    ld (de), a
    inc hl : inc de : inc b
    jr .load
.exit
    xor a : ld (de), a
    ret
    
    endmodule