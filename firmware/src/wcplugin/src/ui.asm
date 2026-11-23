;; Player window. Coordinates are inside the window: (0,0) is the frame
;; corner, the text area is x = 1..WIN_W-2, y = 1..WIN_H-2.

WIN_W           equ 64
WIN_H           equ 18
WIN_X           equ (80 - WIN_W) / 2

Y_FILE          equ 1
Y_TITLE         equ 3
Y_ARTIST        equ 4
Y_ALBUM         equ 5
Y_YEAR          equ 6
Y_FMT           equ 8
Y_DEC           equ 9
Y_PROG          equ 11
Y_STAT          equ 12          ; rows 12 and 13 are kept for the L/R peaks
Y_BUF           equ 14
Y_KEYS          equ 16

X_VAL           equ 10          ; values of File / Title / Artist / Album
W_VAL           equ WIN_W - 1 - X_VAL
X_BAR           equ 10
W_BAR           equ 46
X_TOTAL         equ X_BAR + W_BAR + 1

; colours: paper in bits 7:4, ink in bits 3:0 (the GS Player look)
CLR_WIN         equ %01111111
CLR_HEAD        equ %11110111
CLR_LABEL       equ %01110001
CLR_VALUE       equ %01111110
CLR_TIME        equ %01110000
CLR_BAR         equ %01110001
CLR_KEYS        equ %01110000

CH_FULL         equ #DB         ; CP866 block characters
CH_EMPTY        equ #B0
CH_LINE         equ #C4
ICON_PLAY       equ #10
ICON_PAUSE      equ #BA
ICON_END        equ #FE

;; HL = text, D = y, E = x, BC = length, A = colour
prn:
    push af
    ld ix,wnd
    WCALL WCF_PRSRW
    pop af
    ex af,af'
    WCALL WCF_PRIAT
    ret

;; HL = 0-terminated text, D = y, E = x, A = colour
prn_z:
    push af
    call strlen
    ld a,b
    or c
    jr z,.none
    pop af
    jr prn
.none:
    pop af
    ret

;; HL = 0-terminated text, D = y, E = x, C = field width, A = colour.
;; Pads with spaces, marks a cut with '~'.
prn_fld:
    push af
    push de
    ld de,linebuf
    ld b,c
.copy:
    ld a,(hl)
    or a
    jr z,.pad
    ld (de),a
    inc hl
    inc de
    djnz .copy
    ld a,(hl)
    or a
    jr z,.out
    dec de
    ld a,'~'
    ld (de),a
    jr .out
.pad:
    ld a,' '
.padl:
    ld (de),a
    inc de
    djnz .padl
.out:
    pop de
    pop af
    ld hl,linebuf
    ld b,0
    jr prn

;; A = filled cells, C = width -> bar in linebuf, then printed at D, E
prn_bar:
    push de
    ld hl,linebuf
    ld b,c
    ld e,a
.loop:
    ld a,e
    or a
    ld a,CH_EMPTY
    jr z,.put
    dec e
    ld a,CH_FULL
.put:
    ld (hl),a
    inc hl
    djnz .loop
    pop de
    ld hl,linebuf
    ld b,0
    ld a,CLR_BAR
    jr prn

ui_draw_all:
    ld ix,wnd
    WCALL WCF_PRWOW
    ld hl,s_head
    ld de,0*256 + (WIN_W - S_HEAD_LEN) / 2
    ld bc,S_HEAD_LEN
    ld a,CLR_HEAD
    call prn
    ld b,4
    ld hl,sep_rows
.sep:
    push bc
    push hl
    ld d,(hl)
    ld e,1
    ld hl,s_line
    ld bc,WIN_W-2
    ld a,CLR_WIN
    call prn
    pop hl
    pop bc
    inc hl
    djnz .sep
    ; labels
    ld hl,labels
.lab:
    ld a,(hl)
    cp #FF
    jr z,.vals
    ld d,a
    inc hl
    ld e,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    push hl
    ld h,b
    ld l,c
    ld a,CLR_LABEL
    call prn_z
    pop hl
    jr .lab
.vals:
    ld hl,fname
    ld de,Y_FILE*256 + X_VAL
    ld c,W_VAL
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_title
    ld a,(id3_found)
    or a
    jr nz,.tit
    ld hl,s_notag
.tit:
    ld de,Y_TITLE*256 + X_VAL
    ld c,W_VAL
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_artist
    ld a,(hl)
    or a
    jr nz,.art
    ld hl,f_aartist
.art:
    ld de,Y_ARTIST*256 + X_VAL
    ld c,W_VAL
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_album
    ld de,Y_ALBUM*256 + X_VAL
    ld c,W_VAL
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_year
    ld de,Y_YEAR*256 + 10
    ld c,4
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_track
    ld de,Y_YEAR*256 + 27
    ld c,8
    ld a,CLR_VALUE
    call prn_fld
    ld hl,f_genre
    ld de,Y_YEAR*256 + 45
    ld c,WIN_W - 1 - 45
    ld a,CLR_VALUE
    call prn_fld
    call build_fmt
    ld hl,fmtbuf
    ld de,Y_FMT*256 + 2
    ld c,WIN_W - 3
    ld a,CLR_VALUE
    call prn_fld
    ld hl,s_keys
    ld de,Y_KEYS*256 + 1
    ld a,CLR_KEYS
    call prn_z
    ; total time
    ld hl,#FFFF
    ld a,(bps+1)
    ld b,a
    ld a,(bps)
    or b
    jr z,.tt
    ld hl,(total_sec)
.tt:
    ld de,tbuf
    call fmt_time
    ld hl,tbuf
    ld de,Y_PROG*256 + X_TOTAL
    ld bc,5
    ld a,CLR_TIME
    call prn
    call ui_dec
    call ui_status
    call ui_prog
    jp ui_buf

;; Decoder, volume, bass and treble
ui_dec:
    ld hl,s_vs1053
    ld a,(dec_type)
    or a
    jr z,.dn
    ld hl,s_rv32
.dn:
    ld de,Y_DEC*256 + 11
    ld c,7
    ld a,CLR_VALUE
    call prn_fld
    ; volume bar: 10 cells, one per 4 dB
    ld a,(vol)
    rrca : rrca : rrca
    and #1F
    cp 10
    jr c,.vb
    ld a,10
.vb:
    ld b,a
    ld a,10
    sub b
    ld de,Y_DEC*256 + 25
    ld c,10
    call prn_bar
    ; "-N.5dB"
    ld de,tbuf
    ld a,(vol)
    or a
    jr z,.v0
    ld a,'-'
    ld (de),a
    inc de
    ld a,(vol)
    srl a
    ld l,a
    ld h,0
    call utoa16
    ld a,(vol)
    rrca
    jr nc,.db
    ld a,'.' : ld (de),a : inc de
    ld a,'5' : ld (de),a : inc de
    jr .db
.v0:
    ld a,'0' : ld (de),a : inc de
.db:
    ld a,'d' : ld (de),a : inc de
    ld a,'B' : ld (de),a : inc de
    xor a
    ld (de),a
    ld hl,tbuf
    ld de,Y_DEC*256 + 36
    ld c,7
    ld a,CLR_VALUE
    call prn_fld
    ; bass and treble, or '-' where the decoder ignores them
    ld a,(dec_type)
    or a
    ld a,'-'
    ld b,a
    jr nz,.fx
    ld a,(fx)
    and 7
    add a,'0'
    ld b,a
    ld a,(fx)
    rrca : rrca : rrca
    and 7
    add a,'0'
.fx:
    ld (tbuf+1),a
    ld a,b
    ld (tbuf),a
    ld hl,tbuf
    ld de,Y_DEC*256 + 50
    ld bc,1
    ld a,CLR_VALUE
    call prn
    ld hl,tbuf+1
    ld de,Y_DEC*256 + 61
    ld bc,1
    ld a,CLR_VALUE
    jp prn

;; Paused / end of track message
ui_status:
    ld hl,s_empty
    ld a,(eof)
    or a
    jr z,.p
    ld hl,s_end
.p:
    ld a,(paused)
    or a
    jr z,.out
    ld hl,s_paused
.out:
    ld de,Y_STAT*256 + 2
    ld c,30
    ld a,CLR_VALUE
    jp prn_fld

;; Icon, elapsed time and the progress bar
ui_prog:
    ld a,ICON_PLAY
    ld b,a
    ld a,(paused)
    or a
    jr z,.np
    ld b,ICON_PAUSE
.np:
    ld a,(eof)
    or a
    jr z,.ne
    ld b,ICON_END
.ne:
    ld a,b
    ld (tbuf),a
    ld hl,tbuf
    ld de,Y_PROG*256 + 2
    ld bc,1
    ld a,CLR_TIME
    call prn
    ; elapsed = play position / bps
    call play_pos
    ld (ppos),hl
    ld (ppos+2),de
    ld hl,(bps)
    ld a,h : or l
    ld hl,#FFFF
    jr z,.tm
    call st_dvd_ppos
    ld bc,(bps)
    call div32_16
    ld hl,(dvd+2)
    ld a,h : or l
    ld hl,(dvd)
    jr z,.tm
    ld hl,#FFFE
.tm:
    ld de,tbuf
    call fmt_time
    ld hl,tbuf
    ld de,Y_PROG*256 + 4
    ld bc,5
    ld a,CLR_TIME
    call prn
    ; bar = (ppos >> 10) * W_BAR / (alen >> 10)
    ld hl,(alen)
    ld de,(alen+2)
    call shr10
    ld a,h : or l
    ld a,0
    jr z,.bar
    push hl
    ld hl,(ppos)
    ld de,(ppos+2)
    call shr10
    ld (m32),hl
    ld hl,0
    ld (m32+2),hl
    ld bc,W_BAR
    call mul32_16
    call st_dvd
    pop bc
    call div32_16
    ld a,(dvd+1)
    or a
    ld a,W_BAR
    jr nz,.bar
    ld a,(dvd)
    cp W_BAR
    jr c,.bar
    ld a,W_BAR
.bar:
    ld de,Y_PROG*256 + X_BAR
    ld c,W_BAR
    jp prn_bar

st_dvd_ppos:
    ld hl,(ppos)
    ld (dvd),hl
    ld hl,(ppos+2)
    ld (dvd+2),hl
    ret

;; FIFO fill: bar of 8 cells and percent
ui_buf:
    call mb_fifo_used
    ld (tmpb),a
    add a,8
    rrca : rrca : rrca : rrca
    and #0F
    cp 9
    jr c,.b
    ld a,8
.b:
    ld de,Y_BUF*256 + 6
    ld c,8
    call prn_bar
    ld a,(tmpb)
    call pct
    ld de,tbuf
    call utoa16
    ld a,'%'
    ld (de),a
    inc de
    xor a
    ld (de),a
    ld hl,tbuf
    ld de,Y_BUF*256 + 15
    ld c,4
    ld a,CLR_VALUE
    jp prn_fld

;; A = used blocks (0..128) -> HL = A * 100 / 128
pct:
    ld l,a
    ld h,0
    ld d,h
    ld e,l
    add hl,hl                   ; *2
    add hl,hl                   ; *4
    add hl,de                   ; *5
    ld d,h
    ld e,l
    add hl,hl                   ; *10
    add hl,hl                   ; *20
    add hl,de                   ; *25
    srl h : rr l                ; /2
    srl h : rr l                ; /4
    srl h : rr l                ; /8
    srl h : rr l                ; /16
    srl h : rr l                ; /32  -> used * 25 / 32
    ret

;; Stream line: "MPEG-1 Layer III  192 kbps CBR  44.1 kHz  Joint Stereo"
build_fmt:
    ld de,fmtbuf
    ld a,(fmt_ok)
    or a
    jr nz,.ok
    ld hl,s_nofmt
    call sapp
    xor a
    ld (de),a
    ret
.ok:
    ld hl,s_mpeg
    call sapp
    ld a,(m_ver)
    ld hl,s_v25
    or a
    jr z,.v
    ld hl,s_v2
    cp 2
    jr z,.v
    ld hl,s_v1
.v:
    call sapp
    ld hl,s_layer
    call sapp
    ld a,(m_lay)
    ld hl,s_l3
    cp 1
    jr z,.l
    ld hl,s_l2
    cp 2
    jr z,.l
    ld hl,s_l1
.l:
    call sapp
    ld hl,s_2sp
    call sapp
    ; bitrate: the header one, or the average for VBR
    ld hl,(m_br)
    ld a,(is_vbr)
    or a
    jr z,.br
    push de
    ld hl,(bps)
    ld (dvd),hl
    ld hl,0
    ld (dvd+2),hl
    ld bc,125
    call div32_16
    ld hl,(dvd)
    pop de
.br:
    call utoa16
    ld hl,s_kbps
    call sapp
    ld hl,s_cbr
    ld a,(is_vbr)
    or a
    jr z,.c
    ld hl,s_vbr
.c:
    call sapp
    ld hl,s_2sp
    call sapp
    ; sample rate in kHz, trailing zeros dropped
    push de
    ld hl,(m_sr)
    ld (dvd),hl
    ld hl,0
    ld (dvd+2),hl
    ld bc,1000
    call div32_16               ; HL = remainder, 0..999
    ld c,10
    call div16_8                ; HL = two decimal digits, 0..99
    ld a,l
    ld (tmpb),a
    pop de
    ld hl,(dvd)
    call utoa16
    ld a,(tmpb)
    or a
    jr z,.khz
    ld b,a
    ld a,'.'
    ld (de),a
    inc de
    ld a,b
    ld c,'0'-1
.t:
    inc c
    sub 10
    jr nc,.t
    add a,10+'0'                ; A = hundredths, C = tenths
    ex de,hl
    ld (hl),c
    inc hl
    ex de,hl
    cp '0'
    jr z,.khz
    ld (de),a
    inc de
.khz:
    ld hl,s_khz
    call sapp
    ld a,(m_mode)
    add a,a
    ld c,a
    ld b,0
    ld hl,mode_names
    add hl,bc
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    call sapp
    xor a
    ld (de),a
    ret

;; ---------------------------------------------------------------------------
;; Diagnostic window: what the board answered, then wait for a key.
;; IN: CF from probe (1 = no decoder)
;; ---------------------------------------------------------------------------
INF_W           equ 58
INF_H           equ 9

diag:
    push af
    ld hl,inf_tpl
    ld de,wnd
    ld bc,WND_SIZE
    ldir
    ld a,(WC_HEI)
    ld b,a
    sub INF_H
    srl a
    ld (wnd+3),a
    ld c,(80 - INF_W) / 2
    ld a,b
    cp 36
    jr nz,.wx
    ld c,(90 - INF_W) / 2
.wx:
    ld a,c
    ld (wnd+2),a
    WCALL WCF_GEDPL             ; any screen may be on at entry
    ld ix,wnd
    WCALL WCF_PRWOW
    ld hl,s_head
    ld de,0*256 + (INF_W - S_HEAD_LEN) / 2
    ld bc,S_HEAD_LEN
    ld a,CLR_HEAD
    call prn
    ; "Board id (#F4): 14 MHz #xx, 7 MHz #xx, 3.5 MHz #xx", the clocks tried
    ld de,linebuf
    ld hl,s_d_id
    call sapp
    ld b,CPU_CLOCK
.idl:
    push bc
    ld a,b
    add a,a
    ld l,a
    ld h,0
    push de
    ld de,clk_names
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    pop de
    call sapp
    pop bc
    push bc
    ld l,b
    ld h,0
    push de
    ld de,ids
    add hl,de
    pop de
    ld a,(hl)
    call hex8
    pop bc
    ld a,(clk_lo)
    cp b
    jr z,.ide
    ld a,','
    ld (de),a
    inc de
    ld a,' '
    ld (de),a
    inc de
    dec b
    jr .idl
.ide:
    xor a
    ld (de),a
    ld hl,linebuf
    ld de,2*256 + 2
    ld a,CLR_VALUE
    call prn_z
    ; what it means
    pop af
    push af
    jr c,.bad
    ld hl,s_d_vs
    ld a,(dec_type)
    or a
    jr z,.why
    ld hl,s_d_rv
    jr .why
.bad:
    ld a,(ids+CPU_CLOCK)        ; what the board said at full speed
    ld hl,s_d_ff
    cp #FF
    jr z,.why
    ld hl,s_d_odd
    and #C0
    jr nz,.why
    ld hl,s_d_nodec
.why:
    ld de,3*256 + 2
    ld a,CLR_VALUE
    call prn_z
    pop af
    ld hl,s_d_notf
    jr c,.msg
    ld hl,s_d_use
    ld a,(clk_sel)
    cp CPU_CLOCK
    jr z,.msg
    ld hl,s_d_slow7
    dec a
    jr z,.msg
    ld hl,s_d_slow35
.msg:
    ld de,4*256 + 2
    ld a,CLR_LABEL
    call prn_z
    ; "Firmware: A2 25 RV 2026-11-24 1a2b3c4"
    ld de,linebuf
    ld hl,s_d_fw
    call sapp
    push de
    ld b,INF_W - 4 - 10
    call mb_coreid
    pop hl
    ld a,(hl)
    or a
    jr nz,.fw
    ex de,hl
    ld hl,s_d_nofw
    call sapp
    xor a
    ld (de),a
.fw:
    ld hl,linebuf
    ld de,5*256 + 2
    ld a,CLR_VALUE
    call prn_z
    ld hl,s_d_key
    ld de,7*256 + 2
    ld a,CLR_KEYS
    call prn_z
    call wait_key
    WCALL WCF_USPO              ; or WC gets the key too
    ld ix,wnd
    WCALL WCF_RRESB
    ret

inf_tpl:
    db 0, 0, 0, 0, INF_W, INF_H, CLR_WIN, 0
    dw 0
    db 0, 0, 1, 0, 0, 0

s_d_id:     db "Board id (#F4): ",0
clk_names:  dw s_c35, s_c7, s_c14
s_c35:      db "3.5 MHz ",0
s_c7:       db "7 MHz ",0
s_c14:      db "14 MHz ",0
s_d_vs:     db "MP3 decoder: VS1053 chip",0
s_d_rv:     db "MP3 decoder: neorv32",0
s_d_ff:     db "No answer: no Megabuzz, or its firmware has no #F4",0
s_d_odd:    db "Not a Megabuzz id: another device on the bus?",0
s_d_nodec:  db "This firmware has no MP3 decoder (XC6SLX16?)",0
s_d_slow7:  db "Bad reads at 14 MHz: the player runs at 7 MHz",0
s_d_slow35: db "Bad reads at 7-14 MHz: the player runs at 3.5 MHz",0
s_d_notf:   db "MP3 decoder not found, the file is not played",0
s_d_use:    db "Press Enter on an .mp3 file to play it",0
s_d_key:    db "Press any key",0
s_d_fw:     db "Firmware: ",0
s_d_nofw:   db "no id (reg #FF), older firmware",0
    IFDEF EMU_MODE
s_emu_id:   db "EMU",0
    ENDIF

;; Window: type 0, frame, no cursor. Copied to wnd before every run.
wnd_tpl:
    db 0, 0, WIN_X, 0, WIN_W, WIN_H, CLR_WIN, 0
    dw 0
    db 0, 0, 1, 0, 0, 0
WND_SIZE        equ $ - wnd_tpl

sep_rows:   db 2, 7, 10, 15

labels:
    db Y_FILE,   2 : dw s_l_file
    db Y_TITLE,  2 : dw s_l_title
    db Y_ARTIST, 2 : dw s_l_artist
    db Y_ALBUM,  2 : dw s_l_album
    db Y_YEAR,   2 : dw s_l_year
    db Y_YEAR,  20 : dw s_l_track
    db Y_YEAR,  38 : dw s_l_genre
    db Y_DEC,    2 : dw s_l_dec
    db Y_DEC,   20 : dw s_l_vol
    db Y_DEC,   44 : dw s_l_bass
    db Y_DEC,   53 : dw s_l_treble
    db Y_BUF,    2 : dw s_l_buf
    db #FF

    IFDEF EMU_MODE
s_head:     db " Megabuzz MP3 Player v", VERSION, " EMU "
    ELSE
s_head:     db " Megabuzz MP3 Player v", VERSION, " "
    ENDIF
S_HEAD_LEN  equ $ - s_head
s_line:     ds WIN_W-2, CH_LINE
s_l_file:   db "File:",0
s_l_title:  db "Title:",0
s_l_artist: db "Artist:",0
s_l_album:  db "Album:",0
s_l_year:   db "Year:",0
s_l_track:  db "Track:",0
s_l_genre:  db "Genre:",0
s_l_dec:    db "Decoder:",0
s_l_vol:    db "Vol:",0
s_l_bass:   db "Bass:",0
s_l_treble: db "Treble:",0
s_l_buf:    db "Buf",0
s_keys:     db "Spc:next P:prev <>:seek S:pause +-:vol B/T:bass/treb Esc:exit",0
s_notag:    db "(no ID3v2 tag)",0
s_vs1053:   db "VS1053",0
s_rv32:     db "neorv32",0
s_paused:   db "Paused",0
s_end:      db "End of track",0
s_empty:    db 0
s_notime:   db "--:--"
s_nofmt:    db "No MPEG audio frames found",0
s_mpeg:     db "MPEG-",0
s_v1:       db "1",0
s_v2:       db "2",0
s_v25:      db "2.5",0
s_layer:    db " Layer ",0
s_l1:       db "I",0
s_l2:       db "II",0
s_l3:       db "III",0
s_2sp:      db "  ",0
s_kbps:     db " kbps ",0
s_cbr:      db "CBR",0
s_vbr:      db "VBR",0
s_khz:      db " kHz  ",0
mode_names: dw s_m0, s_m1, s_m2, s_m3
s_m0:       db "Stereo",0
s_m1:       db "Joint Stereo",0
s_m2:       db "Dual Channel",0
s_m3:       db "Mono",0
