;; Karabas-MegaBuzz decoder ports (see PORTS.md)
;;
;; ZXUNO-style register select #FC3B, data #FD3B. The full 16-bit address
;; is decoded, so OTIR (which puts B on A8-A15) cannot be used.
;;
;; With EMU_MODE the ports are not touched: a software FIFO drains at the
;; stream's byte rate, so the UI can be tried on a host without Megabuzz.

MB_PORT_REG     equ #FC3B
MB_PORT_DATA    equ #FD3B
MB_REG_ID       equ #F4     ; board id (read only)
MB_REG_FIFO     equ #F5     ; r: bit 7 full, 6:0 used 32-byte blocks; w: bit 7 reset
MB_REG_DATA     equ #F6     ; w: byte into the decoder FIFO
MB_REG_CFG      equ #F7     ; config byte at the address in #FA
MB_REG_CFGA     equ #FA     ; config byte address
MB_REG_VOL      equ #FB     ; volume, 0 = max, #FE = silence (0.5 dB steps)
MB_REG_COREID   equ #FF     ; firmware id: ASCII, next char per read, then 0
MB_REG_FX       equ #FC     ; 7:6 ear speaker, 5:3 treble, 2:0 bass (VS1053 chip only)

DEC_VS1053      equ 0
DEC_RV32        equ 1

    IFNDEF EMU_MODE

;; A = register
mb_sel:
    ld bc,MB_PORT_REG
    out (c),a
    ret

;; A = register -> A = value
mb_rd:
    call mb_sel
    ld b,high MB_PORT_DATA
    in a,(c)
    ret

;; A = register, E = value
mb_wr:
    call mb_sel
    ld b,high MB_PORT_DATA
    out (c),e
    ret

;; HL = data, DE = byte count: into the FIFO (the caller checked the room)
mb_send:
    push hl
    push de
    ld a,MB_REG_DATA
    call mb_sel
    pop de
    pop hl
    ld bc,MB_PORT_DATA
.l32:
    ld a,d
    or a
    jr nz,.blk
    ld a,e
    cp 32
    jp c,.tail
.blk:
    DUP 32
    ld a,(hl) : out (c),a : inc hl
    EDUP
    ld a,e
    sub 32
    ld e,a
    jp nc,.l32
    dec d
    jp .l32
.tail:
    or a
    ret z
.t1:
    ld a,(hl)
    out (c),a
    inc hl
    dec e
    jr nz,.t1
    ret

;; Hooks for the emulation
mb_rate:
mb_tick:
    ret

    ELSE

mb_sel:
    ld (emu_sel),a
    ret

mb_rd:
    call mb_sel
    cp MB_REG_ID
    ld a,#2B                    ; A3, XC6SLX25, VS1053 chip
    ret z
    ld a,(emu_sel)
    cp MB_REG_VOL
    ld a,(emu_vol)
    ret z
    ld a,(emu_sel)
    cp MB_REG_FX
    ld a,(emu_fx)
    ret z
    ld a,(emu_sel)
    cp MB_REG_CFG
    ld a,0
    ret z
    ; FIFO status
    push hl
    ld hl,(emu_cnt)
    ld a,h
    cp #10
    ld a,#FF
    jr nc,.full
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,h                      ; count / 32
.full:
    pop hl
    ret

mb_wr:
    call mb_sel
    cp MB_REG_VOL
    jr nz,.fx
    ld a,e
    ld (emu_vol),a
    ret
.fx:
    cp MB_REG_FX
    jr nz,.fifo
    ld a,e
    ld (emu_fx),a
    ret
.fifo:
    cp MB_REG_FIFO
    ret nz
    bit 7,e
    ret z
    ld hl,0
    ld (emu_cnt),hl
    ret

mb_send:
    add hl,de
    push hl
    ld hl,(emu_cnt)
    add hl,de
    ld (emu_cnt),hl
    pop hl
    ret

;; Drain rate: bps / 50 bytes per frame, 320 if unknown
mb_rate:
    ld hl,(bps)
    ld a,h : or l
    ld hl,320
    jr z,.set
    ld hl,(bps)
    ld c,50
    call div16_8
.set:
    ld (emu_drain),hl
    ret

;; Once per frame
mb_tick:
    ld hl,(emu_cnt)
    ld de,(emu_drain)
    or a
    sbc hl,de
    jr nc,.set
    ld hl,0
.set:
    ld (emu_cnt),hl
    ret

    ENDIF

;; Soft reset of the decoder, clears the FIFO (as the NMI plugin does)
mb_reset:
    ld a,MB_REG_FIFO : ld e,#80 : call mb_wr
    ld a,MB_REG_FIFO : ld e,#00 : jp mb_wr

;; OUT: A = used 32-byte blocks in the FIFO (0..128)
mb_fifo_used:
    ld a,MB_REG_FIFO
    call mb_rd
    bit 7,a
    jr nz,.full
    and #7F
    ret
.full:
    ld a,128
    ret

;; OUT: A = free 32-byte blocks (0..127)
mb_fifo_free:
    call mb_fifo_used
    ld b,a
    ld a,127
    sub b
    ret nc
    xor a
    ret

;; Find the board and its MP3 decoder.
;; OUT: CF = 1 if there is no Megabuzz with a decoder; else (dec_type) is set
mb_detect:
    IFDEF EMU_MODE
    ld a,8
    ld (emu_vol),a
    xor a
    ld (emu_fx),a
    ld hl,0
    ld (emu_cnt),hl
    ENDIF
    ld a,MB_REG_ID
    call mb_rd
    ld (mb_id),a
    and #C0                     ; bits 7:6 read as 0; a free bus reads #FF
    jr nz,.none
    ld a,(mb_id)
    and #30                     ; bit 5 VS1053 chip, bit 4 neorv32
    jr z,.none
    cp #20
    jr z,.vs
    cp #10
    jr z,.rv
    ; both: config byte 1 bit 3 picks the decoder
    ld a,MB_REG_CFGA : ld e,1 : call mb_wr
    ld a,MB_REG_CFG : call mb_rd
    push af
    ld a,MB_REG_CFGA : ld e,0 : call mb_wr
    pop af
    and #08
    jr nz,.rv
.vs:
    ld a,DEC_VS1053
    jr .set
.rv:
    ld a,DEC_RV32
.set:
    ld (dec_type),a
    or a                        ; CF = 0
    ret
.none:
    scf
    ret

;; Firmware id (reg #FF) into DE, 0-terminated, at most B chars.
;; Empty on firmware without it. OUT: DE at the terminating 0
mb_coreid:
    IFDEF EMU_MODE
    ld hl,s_emu_id
    call sapp
    ELSE
    push de
    push bc
    ld a,MB_REG_COREID
    call mb_sel                 ; selecting it rewinds the string
    pop hl                      ; H = room
    pop de
    ld bc,MB_PORT_DATA
.next:
    in a,(c)
    cp 32
    jr c,.end                   ; 0 at the end
    cp 128
    jr nc,.end                  ; #FF: no such register
    ld (de),a
    inc de
    dec h
    jr nz,.next
.end:
    ENDIF
    xor a
    ld (de),a
    ret
