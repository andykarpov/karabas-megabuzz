;; MEGABUZZ.WMF - Wild Commander plugin that plays MP3 through the
;; Karabas-MegaBuzz decoder (VS1053 chip or neorv32), see PORTS.md.
;;
;; Build: sjasmplus src/main.asm  ->  MEGABUZZ.WMF

    DEFINE VERSION "0.3"

CPU_CLOCK       equ 2           ; TURBOPL: 0 = 3.5, 1 = 7, 2 = 14 MHz
SEEK_SEC        equ 10          ; seconds per <- / ->
VOL_STEP        equ 4           ; 2 dB
DRAIN_FRAMES    equ 15          ; wait after the FIFO runs dry at the end

    include "wcdefs.asm"

    IFDEF EMU_MODE
    OUTPUT "MEGABUZZ_EMU.WMF"
    ELSE
    OUTPUT "MEGABUZZ.WMF"
    ENDIF

;; ---------------------------------------------------------------------------
;; Plugin header, 512 bytes (plugin system #10)
;; ---------------------------------------------------------------------------
    ORG 0
header:
    ds 16                                   ; +0
    db "WildCommanderMDL"                   ; +16
    db #10                                  ; +32 format version
    db 0                                    ; +33
    db 1                                    ; +34 pages
    db 0                                    ; +35 page at #8000
    db 0, (code_end - #8000 + 511) / 512    ; +36 block: page 0, 512-byte sectors
    ds 5*2                                  ;     no more blocks
    ds 15                                   ; +48
    db 0                                    ; +63 run by ENTER and F3
    db "MP3"                                ; +64 extensions
    ds 31*3
    db 0                                    ; +160
    dd #FFFFFFFF                            ; +161 any file size
name_start:
    IFDEF EMU_MODE
    db "Megabuzz MP3 Player EMU v", VERSION ; +165 name, 32 chars
    ELSE
    db "Megabuzz MP3 Player v", VERSION     ; +165 name, 32 chars
    ENDIF
    ds 32 - ($ - name_start), ' '
    db #05                                  ; +197 also from F10 and Shift+F3
    ds 6                                    ; +198 F2 / F4 text (unused)
viewer_start:
    db "Play on Megabuzz"                   ; +204 Shift+F3 menu, 24 chars
    ds 24 - ($ - viewer_start), ' '
    ds 512 - ($ - header)
    ASSERT $ == 512

;; ---------------------------------------------------------------------------
;; Code, page 0 at #8000
;; ---------------------------------------------------------------------------
    ORG #8000

;; IN: A = call type, DEHL = file size, BC = file name, IX = panel,
;;     DE' = files in the panel, HL' = this file's number (from 1)
entry:
    ld (entry_sp),sp
    ld (panel_ix),ix
    ld (file_size),hl
    ld (file_size+2),de
    ld (name_ptr),bc
    exx
    ld (wc_count),de
    ld (wc_index),hl
    exx
    ld (call_type),a
    or a
    jr z,.byext
    cp 4
    jr z,.byext                 ; chosen in the Shift+F3 menu
    ; from the F10 menu: show what the board answers
    call probe
    call diag
    xor a                       ; WCX_ESC
    ret
.byext:
    ; copy the name before any WC call can move it
    ld hl,(name_ptr)
    ld de,fname
    ld bc,255
.name:
    ld a,(hl)
    ld (de),a
    or a
    jr z,.named
    inc hl
    inc de
    dec bc
    ld a,b
    or c
    jr nz,.name
    xor a
    ld (de),a
.named:
    call probe
    jr nc,.found
    call diag                   ; say why
    ld a,(call_type)
    or a
    ld a,WCX_NOTMINE            ; Enter: WC opens its Shift+F3 menu
    ret z
    xor a                       ; WCX_ESC
    ret
.found:
    ; code and data stay loaded between runs: set everything up again
    xor a
    ld (paused),a
    ld (eof),a
    ld (drain),a
    ld (exit_req),a
    ld (fcnt),a
    ld hl,wnd_tpl
    ld de,wnd
    ld bc,WND_SIZE
    ldir
    ld a,(WC_HEI)
    ld b,a
    sub WIN_H
    srl a
    ld (wnd+3),a
    ld a,(90 - WIN_W) / 2       ; the 36-line mode is 90 columns wide
    ld c,a
    ld a,b
    cp 36
    jr z,.wx
    ld c,(80 - WIN_W) / 2
.wx:
    ld a,c
    ld (wnd+2),a

    call mb_reset
    ld a,MB_REG_VOL : call mb_rd : ld (vol),a
    ld a,MB_REG_FX : call mb_rd : ld (fx),a

    call rd_init
    call id3_parse
    ; alen = file_size - audio_start, kept if no frame is found
    ld hl,(file_size) : ld bc,(audio_start) : or a : sbc hl,bc : ld (alen),hl
    ld hl,(file_size+2) : ld bc,(audio_start+2) : sbc hl,bc : ld (alen+2),hl
    jr nc,.alen
    ld hl,0
    ld (alen),hl
    ld (alen+2),hl
    ld hl,(file_size) : ld (audio_start),hl
    ld hl,(file_size+2) : ld (audio_start+2),hl
.alen:
    call mpeg_scan
    call mb_rate
    ld hl,(audio_start)
    ld de,(audio_start+2)
    call rd_seek

    WCALL WCF_GEDPL
    call ui_draw_all
    WCALL WCF_USPO              ; the ENTER that started us must be released
    ld hl,(WC_TMN)
    ld (last_tmn),hl

;; ---------------------------------------------------------------------------
main_loop:
    ei
    ld a,(exit_req)
    or a
    jp nz,do_exit
    ld a,(paused)
    ld b,a
    ld a,(eof)
    or b
    jr nz,.idle
    call feed
    jr nc,.idle
    ld a,1
    ld (eof),a
    call ui_status
.idle:
    ld hl,(WC_TMN)
    ld de,(last_tmn)
    or a
    sbc hl,de
    jr z,main_loop
    add hl,de
    ld (last_tmn),hl
    call keys
    call frame_tick
    jr main_loop

;; Once per frame: redraw a part of the window, watch the end of the track
frame_tick:
    call mb_tick
    ld hl,fcnt
    inc (hl)
    ld a,(hl)
    cp 5
    call z,ui_buf
    ld a,(fcnt)
    cp 10
    jr c,.end
    xor a
    ld (fcnt),a
    call ui_prog
.end:
    ld a,(eof)
    or a
    ret z
    call mb_fifo_used
    or a
    ret nz
    ld hl,drain
    inc (hl)
    ld a,(hl)
    cp DRAIN_FRAMES
    ret c
    ld a,EXIT_END
    ld (exit_req),a
    ret

;; Push as much of the buffer into the decoder FIFO as fits.
;; OUT: CF = 1 when the whole file has been sent
feed:
    call mb_fifo_free
    or a
    ret z
    ld (feed_blk),a
.again:
    ld hl,(buf_len)
    ld de,(rd_off)
    or a
    sbc hl,de
    jr nz,.have
    call rd_refill
    jr nz,.again
    scf
    ret
.have:
    ex de,hl                    ; DE = bytes left in the buffer
    ld a,(feed_blk)
    ld l,a
    ld h,0
    add hl,hl : add hl,hl : add hl,hl : add hl,hl : add hl,hl
    push hl
    or a
    sbc hl,de
    pop hl
    jr c,.n
    ld h,d
    ld l,e
.n:
    ld b,h
    ld c,l
    ld hl,(rd_off)
    push hl
    add hl,bc
    ld (rd_off),hl
    pop hl
    ld de,BUF
    add hl,de
    ld d,b
    ld e,c
    call mb_send
    or a
    ret

;; CPU clock for the plugin: the one probe found the board at
set_clock:
    ld a,(clk_sel)
    ld c,a
    ld b,0
    WCALL WCF_TURBOPL
    ret

;; Find the board at 14, 7, then 3.5 MHz: TSConf runs I/O to the slot at
;; the full clock (it slows down only for AY and the WD1793), and the
;; board may not answer that fast. The id read at each clock tried goes
;; to ids[clock], the lowest clock tried to clk_lo.
;; OUT: CF = 1 if no clock gives a decoder; the clock is set
probe:
    ld a,CPU_CLOCK
.loop:
    ld (clk_sel),a
    ld (clk_lo),a
    call set_clock
    call mb_detect
    push af
    ld a,(clk_sel)
    ld e,a
    ld d,0
    ld hl,ids
    add hl,de
    ld a,(mb_id)
    ld (hl),a
    pop af
    ret nc
    ld a,(clk_sel)
    or a
    jr z,.none
    dec a
    jr .loop
.none:
    ld a,CPU_CLOCK
    ld (clk_sel),a
    call set_clock
    scf
    ret

;; Wait for Esc, Enter, Space or a letter
wait_key:
    WCALL WCF_USPO
.loop:
    ei
    call key_esc   : ret nz
    call key_enter : ret nz
    call key_space : ret nz
    call key_char  : ret nz
    jr .loop

;; ---------------------------------------------------------------------------
;; Keys, polled once per frame
;; ---------------------------------------------------------------------------
keys:
    call key_esc   : jp nz,.esc
    call key_space : jp nz,.next
    call key_enter : jp nz,.next
    call key_bspc  : jp nz,.prev
    call key_left  : jp nz,seek_back
    call key_right : jp nz,seek_fwd
    call key_up    : jp nz,vol_up
    call key_down  : jp nz,vol_down
    call key_char
    ret z
    cp 'p' : jr z,.prev
    cp 's' : jr z,pause
    cp '+' : jp z,vol_up
    cp '=' : jp z,vol_up
    cp '-' : jp z,vol_down
    cp 'b' : jp z,bass
    cp 't' : jp z,treble
    ret
.esc:
    ld a,EXIT_ESC
    jr .set
.next:
    ld a,EXIT_NEXT
    jr .set
.prev:
    ld a,EXIT_PREV
.set:
    ld (exit_req),a
    ret

pause:
    ld a,(paused)
    xor 1
    ld (paused),a
    call ui_status
    jp ui_prog

vol_up:
    ld a,(vol)
    sub VOL_STEP
    jr nc,vol_set
    xor a
    jr vol_set
vol_down:
    ld a,(vol)
    add a,VOL_STEP
    jr c,.max
    cp #FE
    jr c,vol_set
.max:
    ld a,#FE
vol_set:
    ld (vol),a
    ld e,a
    ld a,MB_REG_VOL
    call mb_wr
    jp ui_dec

bass:
    ld a,(fx)
    ld b,a
    inc a
    and #07
    ld c,a
    ld a,b
    and #F8
    or c
    jr fx_set
treble:
    ld a,(fx)
    ld b,a
    add a,#08
    and #38
    ld c,a
    ld a,b
    and #C7
    or c
fx_set:
    ld b,a
    ld a,(dec_type)
    or a
    ret nz                      ; neorv32 has no bass / treble
    ld a,b
    ld (fx),a
    ld e,a
    ld a,MB_REG_FX
    call mb_wr
    jp ui_dec

;; ---------------------------------------------------------------------------
;; Seeking: SEEK_SEC seconds, or 1/32 of the file if the rate is unknown
;; ---------------------------------------------------------------------------
seek_step:
    ld hl,(bps)
    ld a,h : or l
    jr z,.part
    ld (m32),hl
    ld hl,0
    ld (m32+2),hl
    ld bc,SEEK_SEC
    call mul32_16
    jr .st
.part:
    ld hl,(alen)
    ld de,(alen+2)
    ld b,5
.sh:
    srl d : rr e : rr h : rr l
    djnz .sh
.st:
    ld (step),hl
    ld (step+2),de
    jp play_pos                 ; DEHL = where we are, from audio_start

seek_fwd:
    call seek_step
    ld bc,(step) : add hl,bc
    ex de,hl
    ld bc,(step+2) : adc hl,bc
    ex de,hl
    ; past the end: go to the end
    push hl
    push de
    ld bc,(alen) : or a : sbc hl,bc
    ex de,hl
    ld bc,(alen+2) : sbc hl,bc
    pop de
    pop hl
    jr c,seek_to
    ld hl,(alen)
    ld de,(alen+2)
    jr seek_to

seek_back:
    call seek_step
    ld bc,(step) : or a : sbc hl,bc
    ex de,hl
    ld bc,(step+2) : sbc hl,bc
    ex de,hl
    jr nc,seek_to
    ld hl,0
    ld d,h
    ld e,l
;; DEHL = position from audio_start
seek_to:
    ld bc,(audio_start) : add hl,bc
    ex de,hl
    ld bc,(audio_start+2) : adc hl,bc
    ex de,hl
    push hl
    push de
    call mb_reset
    pop de
    pop hl
    call rd_seek
    xor a
    ld (eof),a
    ld (drain),a
    call ui_status
    jp ui_prog

;; OUT: DEHL = bytes played, from audio_start (what is sent minus the FIFO)
play_pos:
    call mb_fifo_used
    ld l,a
    ld h,0
    add hl,hl : add hl,hl : add hl,hl : add hl,hl : add hl,hl
    ld (tmpw),hl
    call rd_tell
    ld bc,(tmpw)
    or a
    sbc hl,bc
    jr nc,.nb
    dec de
.nb:
    ld bc,(audio_start) : or a : sbc hl,bc
    ex de,hl
    ld bc,(audio_start+2) : sbc hl,bc
    ex de,hl
    ret nc
    ld hl,0
    ld d,h
    ld e,l
    ret

;; ---------------------------------------------------------------------------
;; Leave the plugin
;; ---------------------------------------------------------------------------
EXIT_ESC        equ 1
EXIT_NEXT       equ 2
EXIT_END        equ 3
EXIT_PREV       equ 4

do_exit:
    ld a,(exit_req)
    cp EXIT_END
    call nz,mb_reset            ; stop the sound unless the track played out
    ld ix,wnd
    WCALL WCF_RRESB
    ld a,(exit_req)
    cp EXIT_PREV
    ld b,WCX_PREV
    jr z,.ret
    cp EXIT_ESC
    ld b,WCX_ESC
    jr z,.ret
    ; next track, unless this is the last file of the panel
    ld hl,(wc_index)
    ld de,(wc_count)
    or a
    sbc hl,de
    ld b,WCX_ESC
    jr nc,.ret
    ld b,WCX_NEXT
.ret:
    ld a,b
    ld sp,(entry_sp)
    ret

    include "wc.asm"
    include "mb.asm"
    include "math.asm"
    include "reader.asm"
    include "id3.asm"
    include "mpeg.asm"
    include "ui.asm"

code_end:
    ds (512 - ($ & 511)) & 511
    OUTEND

;; ---------------------------------------------------------------------------
;; Variables and buffers: not in the file, set up at run time
;; ---------------------------------------------------------------------------
    ORG #A800
    ASSERT code_end <= $
vars:
entry_sp    ds 2
call_type   ds 1
clk_sel     ds 1
clk_lo      ds 1
ids         ds 3
panel_ix    ds 2
name_ptr    ds 2
wc_count    ds 2
wc_index    ds 2
file_size   ds 4
file_pos    ds 4
buf_base    ds 4
buf_len     ds 2
rd_off      ds 2
seek_tgt    ds 4
seek_sec    ds 4
seek_in     ds 2
mb_id       ds 1
dec_type    ds 1
vol         ds 1
fx          ds 1
paused      ds 1
eof         ds 1
drain       ds 1
exit_req    ds 1
fcnt        ds 1
feed_blk    ds 1
last_tmn    ds 2
step        ds 4
ppos        ds 4
tmpw        ds 2
tmpb        ds 1
dvd         ds 4
m32         ds 4
utoa_st     ds 1
emu_sel     ds 1
emu_vol     ds 1
emu_fx      ds 1
emu_cnt     ds 2
emu_drain   ds 2
; ID3
id3_found   ds 1
id3_ver     ds 1
id3_flg     ds 1
tag_unsync  ds 1
v4_all_unsync ds 1
frame_unsync ds 1
prev_raw    ds 1
prev_f      ds 1
fflag2      ds 1
fid         ds 4
tag_end     ds 4
frame_left  ds 4
rt_dst      ds 2
rt_max      ds 1
rt_len      ds 1
; MPEG
audio_start ds 4
alen        ds 4
fmt_ok      ds 1
is_vbr      ds 1
scan_cnt    ds 2
cand        ds 4
h1          ds 1
h2          ds 1
h3          ds 1
m_ver       ds 1
m_lay       ds 1
m_bri       ds 1
m_sri       ds 1
m_pad       ds 1
m_mode      ds 1
m_br        ds 2
m_sr        ds 2
m_spf       ds 2
m_flen      ds 2
m_frames    ds 4
bps         ds 2
total_sec   ds 2
tmp4        ds 4
; text
wnd         ds 16
tbuf        ds 16
linebuf     ds 80
fmtbuf      ds 80
fname       ds 256
f_title     ds FLD_LEN+1
f_artist    ds FLD_LEN+1
f_aartist   ds FLD_LEN+1
f_album     ds FLD_LEN+1
f_year      ds 5
f_track     ds 9
f_genre     ds 21
vars_end:
    ASSERT vars_end <= BUF

BUF         equ #B000
    ASSERT BUF + BUFSZ <= #C000
