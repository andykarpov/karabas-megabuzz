;; 32-bit helpers. 32-bit values are DEHL (DE = high word) or 4 bytes LE in memory.

;; (dvd) / BC -> (dvd) = quotient, HL = remainder. BC must not be 0.
div32_16:
    ld hl,0
    ld a,32
.loop:
    push af
    ld a,(dvd) : add a,a : ld (dvd),a
    ld a,(dvd+1) : rla : ld (dvd+1),a
    ld a,(dvd+2) : rla : ld (dvd+2),a
    ld a,(dvd+3) : rla : ld (dvd+3),a
    adc hl,hl                   ; CF = bit 16 of the remainder
    jr c,.sub
    sbc hl,bc                   ; CF was 0
    jr nc,.one
    add hl,bc
    jr .next
.sub:
    or a
    sbc hl,bc
.one:
    ld a,(dvd) : or 1 : ld (dvd),a
.next:
    pop af
    dec a
    jr nz,.loop
    ret

;; (m32) * BC -> DEHL (low 32 bits)
mul32_16:
    ld hl,0
    ld d,h : ld e,l
    ld a,16
.loop:
    add hl,hl : rl e : rl d
    sla c : rl b
    jr nc,.next
    push bc
    ld bc,(m32) : add hl,bc
    ld bc,(m32+2) : ex de,hl : adc hl,bc : ex de,hl
    pop bc
.next:
    dec a
    jr nz,.loop
    ret

;; DEHL -> (dvd)
st_dvd:
    ld (dvd),hl
    ld (dvd+2),de
    ret

;; HL / C -> HL = quotient, A = remainder (C < 128)
div16_8:
    xor a
    ld b,16
.loop:
    add hl,hl
    rla
    cp c
    jr c,.next
    sub c
    inc l
.next:
    djnz .loop
    ret

;; HL = unsigned value -> decimal at (DE), no leading zeros. OUT: DE past the text
utoa16:
    xor a
    ld (utoa_st),a
    ld bc,-10000 : call .dig
    ld bc,-1000 : call .dig
    ld bc,-100 : call .dig
    ld bc,-10 : call .dig
    ld a,l
    add a,'0'
    ld (de),a
    inc de
    ret
.dig:
    ld a,'0'-1
.sub:
    inc a
    add hl,bc
    jr c,.sub
    sbc hl,bc                   ; undo the last step (CF = 0 here)
    cp '0'
    jr nz,.put
    push af
    ld a,(utoa_st)
    or a
    jr nz,.put0
    pop af
    ret
.put0:
    pop af
.put:
    ld (de),a
    inc de
    ld a,1
    ld (utoa_st),a
    ret

;; A = 0..99 -> two digits at (DE). OUT: DE past them
utoa2:
    ld b,'0'-1
.loop:
    inc b
    sub 10
    jr nc,.loop
    add a,10+'0'
    ex de,hl
    ld (hl),b : inc hl
    ld (hl),a : inc hl
    ex de,hl
    ret

;; HL = seconds or #FFFF (unknown) -> "MM:SS" at (DE), minutes capped at 99
fmt_time:
    ld a,h
    and l
    inc a
    jr z,.unknown
    ld c,60
    push de
    call div16_8                ; HL = minutes, A = seconds
    pop de
    push af
    ld a,h
    or a
    jr nz,.cap
    ld a,l
    cp 100
    jr c,.mm
.cap:
    pop af
    ld a,59
    push af
    ld a,99
.mm:
    call utoa2
    ld a,':'
    ld (de),a
    inc de
    pop af
    jp utoa2
.unknown:
    ld hl,s_notime
    ld bc,5
    ldir
    ret

;; HL = source string (0-terminated) appended at (DE). OUT: DE past the text
sapp:
    ld a,(hl)
    or a
    ret z
    ld (de),a
    inc hl
    inc de
    jr sapp

;; HL = string -> BC = length
strlen:
    push hl
    ld bc,0
.loop:
    ld a,(hl)
    or a
    jr z,.done
    inc hl
    inc bc
    jr .loop
.done:
    pop hl
    ret
;; A -> "#XY" at (DE). OUT: DE past it
hex8:
    push af
    ld a,'#'
    ld (de),a
    inc de
    pop af
    push af
    rrca : rrca : rrca : rrca
    call .nib
    pop af
.nib:
    and #0F
    add a,'0'
    cp '9'+1
    jr c,.put
    add a,7
.put:
    ld (de),a
    inc de
    ret
