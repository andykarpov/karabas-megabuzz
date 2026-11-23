;; MPEG audio: find the first frame after the tag, read Xing / Info / VBRI,
;; work out the bitrate, the average byte rate and the duration.
;;
;; IN:  (audio_start) = where to start looking
;; OUT: (fmt_ok) = 1 if a frame was found; then (audio_start) = that frame,
;;      (bps) = bytes per second, (total_sec), (m_*) = stream parameters

SCAN_LIMIT      equ 65535       ; bytes to look through for a frame

mpeg_scan:
    xor a
    ld (fmt_ok),a
    ld (is_vbr),a
    ld hl,0
    ld (bps),hl
    ld (total_sec),hl
    ld (scan_cnt),hl
    ld hl,(audio_start)
    ld de,(audio_start+2)
    call rd_seek
.next:
    ld hl,(scan_cnt)
    inc hl
    ld (scan_cnt),hl
    ld a,h : or l
    ret z                       ; nothing found in SCAN_LIMIT bytes
    call rd_getbyte
    ret c
    cp #FF
    jr nz,.next
    call rd_tell
    ld bc,1
    or a
    sbc hl,bc
    jr nc,.nc
    dec de
.nc:
    ld (cand),hl
    ld (cand+2),de
    call rd_getbyte : ret c : ld (h1),a
    and #E0
    cp #E0
    jr nz,.retry
    ld a,(h1) : and #18 : cp #08 : jr z,.retry    ; reserved version
    ld a,(h1) : and #06 : jr z,.retry             ; reserved layer
    call rd_getbyte : ret c : ld (h2),a
    and #F0
    jr z,.retry                                     ; free format
    cp #F0
    jr z,.retry                                     ; bad bitrate
    ld a,(h2) : and #0C : cp #0C : jr z,.retry    ; reserved sample rate
    call rd_getbyte : ret c : ld (h3),a
    call hdr_decode
    call check_next
    jr z,found
.retry:
    ld hl,(cand)
    ld de,(cand+2)
    inc hl
    ld a,h : or l
    jr nz,.nc2
    inc de
.nc2:
    call rd_seek
    jr .next

found:
    ld hl,(cand) : ld (audio_start),hl
    ld hl,(cand+2) : ld (audio_start+2),hl
    ld a,1
    ld (fmt_ok),a
    ; alen = file_size - audio_start
    ld hl,(file_size) : ld bc,(audio_start) : or a : sbc hl,bc : ld (alen),hl
    ld hl,(file_size+2) : ld bc,(audio_start+2) : sbc hl,bc : ld (alen+2),hl
    call vbr_frames
    ld hl,(m_frames)
    ld de,(m_frames+2)
    ld a,h : or l : or d : or e
    jr z,.cbr
    ; total = frames * spf / sr
    ld (m32),hl
    ld (m32+2),de
    ld bc,(m_spf)
    call mul32_16
    call st_dvd
    ld bc,(m_sr)
    call div32_16
    ld hl,(dvd+2)
    ld a,h : or l
    ld hl,(dvd)
    jr z,.tot
    ld hl,#FFFE
.tot:
    ld a,h : or l
    jr z,.cbr
    ld (total_sec),hl
    ; bps = alen / total
    ld b,h : ld c,l
    ld hl,(alen) : ld (dvd),hl
    ld hl,(alen+2) : ld (dvd+2),hl
    call div32_16
    ld hl,(dvd)
    ld (bps),hl
    ld a,h : or l
    ret nz
.cbr:
    xor a
    ld (is_vbr),a
    ; bps = kbps * 125
    ld hl,(m_br) : ld (m32),hl
    ld hl,0 : ld (m32+2),hl
    ld bc,125
    call mul32_16
    ld (bps),hl
    ld a,h : or l
    ret z
    ; total = alen / bps
    ld b,h : ld c,l
    ld hl,(alen) : ld (dvd),hl
    ld hl,(alen+2) : ld (dvd+2),hl
    call div32_16
    ld hl,(dvd)
    ld (total_sec),hl
    ret

;; Split h1..h3 into fields and work out bitrate, sample rate, samples per
;; frame and the frame length
hdr_decode:
    ld a,(h1) : rrca : rrca : rrca : and 3 : ld (m_ver),a     ; 0 = 2.5, 2 = 2, 3 = 1
    ld a,(h1) : rrca : and 3 : ld (m_lay),a                   ; 1 = III, 2 = II, 3 = I
    ld a,(h2) : rrca : rrca : rrca : rrca : and #0F : ld (m_bri),a
    ld a,(h2) : rrca : rrca : and 3 : ld (m_sri),a
    ld a,(h2) : rrca : and 1 : ld (m_pad),a
    ld a,(h3) : rlca : rlca : and 3 : ld (m_mode),a
    ; bitrate table: MPEG-1 L1, L2, L3, MPEG-2/2.5 L1, L2/L3
    ld a,(m_ver)
    cp 3
    jr nz,.v2
    ld a,(m_lay)
    ld b,a
    ld a,3
    sub b
    jr .tab
.v2:
    ld a,(m_lay)
    cp 3
    ld a,3
    jr z,.tab
    inc a
.tab:
    add a,a
    ld e,a
    ld d,0
    ld hl,br_tabs
    add hl,de
    ld a,(hl) : inc hl : ld h,(hl) : ld l,a
    ld a,(m_bri)
    add a,a
    ld e,a
    add hl,de
    ld a,(hl) : inc hl : ld h,(hl) : ld l,a
    ld (m_br),hl
    ; sample rate: the MPEG-1 one, halved for MPEG-2, quartered for 2.5
    ld a,(m_sri)
    add a,a
    ld e,a
    ld hl,sr_tab
    add hl,de
    ld a,(hl) : inc hl : ld h,(hl) : ld l,a
    ld a,(m_ver)
    cp 3
    jr z,.sr
    srl h : rr l
    cp 2
    jr z,.sr
    srl h : rr l
.sr:
    ld (m_sr),hl
    ; samples per frame and the frame length constant (C:DE)
    ld a,(m_lay)
    cp 3
    jr nz,.l23
    ld hl,384
    ld de,12000
    ld c,0
    jr .spf
.l23:
    ld hl,1152
    ld de,144000 & #FFFF
    ld c,144000 >> 16
    cp 1
    jr nz,.spf
    ld a,(m_ver)
    cp 3
    jr z,.spf
    ld hl,576
    ld de,72000 & #FFFF
    ld c,72000 >> 16
.spf:
    ld (m_spf),hl
    ld (m32),de
    ld l,c
    ld h,0
    ld (m32+2),hl
    ; flen = coef * kbps / sr + pad (Layer I: in 4-byte slots)
    ld bc,(m_br)
    call mul32_16
    call st_dvd
    ld bc,(m_sr)
    call div32_16
    ld hl,(dvd)
    ld a,(m_pad)
    add a,l
    ld l,a
    jr nc,.np
    inc h
.np:
    ld a,(m_lay)
    cp 3
    jr nz,.flen
    add hl,hl
    add hl,hl
.flen:
    ld (m_flen),hl
    ret

;; Look for the next frame header right after this one.
;; OUT: Z = it is there (or the file ends), NZ = no
check_next:
    ld hl,(cand)
    ld de,(cand+2)
    ld bc,(m_flen)
    add hl,bc
    jr nc,.nc
    inc de
.nc:
    call rd_seek
    call rd_getbyte
    jr c,.ok
    cp #FF
    ret nz
    call rd_getbyte
    jr c,.ok
    ld b,a
    and #E0
    cp #E0
    ret nz
    ld a,(h1)
    xor b
    and #1E                     ; same version and layer
    ret
.ok:
    xor a
    ret

;; Frame count from a Xing / Info header (after the side info) or from a
;; VBRI header (32 bytes after the frame header). Layer III only.
vbr_frames:
    ld hl,0
    ld (m_frames),hl
    ld (m_frames+2),hl
    ld a,(m_lay)
    cp 1
    ret nz
    ld a,(m_ver)
    cp 3
    ld a,(m_mode)
    jr nz,.v2
    cp 3
    ld c,17
    jr z,.si
    ld c,32
    jr .si
.v2:
    cp 3
    ld c,9
    jr z,.si
    ld c,17
.si:
    ld b,0
    ld hl,4
    add hl,bc
    call seek_cand
    call rd_4
    ld hl,s_xing
    call cmp4
    jr z,.xing
    ld hl,s_info
    call cmp4
    jr z,.info
    ld hl,4+32
    call seek_cand
    call rd_4
    ld hl,s_vbri
    call cmp4
    ret nz
    ld b,10                     ; version, delay, quality, bytes
.skip:
    call rd_getbyte
    ret c
    djnz .skip
    ld a,1
    ld (is_vbr),a
    jr .frames
.xing:
    ld a,1
    ld (is_vbr),a
.info:
    call rd_be32                ; flags
    bit 0,l
    ret z
.frames:
    call rd_be32
    ld (m_frames),hl
    ld (m_frames+2),de
    ret

;; Seek to cand + HL
seek_cand:
    ld de,(cand+2)
    ld bc,(cand)
    add hl,bc
    jp nc,rd_seek
    inc de
    jp rd_seek

;; Read 4 bytes into tmp4
rd_4:
    ld hl,tmp4
    ld b,4
.loop:
    call rd_getbyte
    ld (hl),a
    inc hl
    djnz .loop
    ret

;; Z if tmp4 matches 4 bytes at HL
cmp4:
    ld de,tmp4
    ld b,4
.loop:
    ld a,(de)
    cp (hl)
    ret nz
    inc hl
    inc de
    djnz .loop
    ret

s_xing: db "Xing"
s_info: db "Info"
s_vbri: db "VBRI"

br_tabs:
    dw br_v1l1, br_v1l2, br_v1l3, br_v2l1, br_v2l23
br_v1l1:  dw 0,32,64,96,128,160,192,224,256,288,320,352,384,416,448,0
br_v1l2:  dw 0,32,48,56,64,80,96,112,128,160,192,224,256,320,384,0
br_v1l3:  dw 0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0
br_v2l1:  dw 0,32,48,56,64,80,96,112,128,144,160,176,192,224,256,0
br_v2l23: dw 0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0
sr_tab:   dw 44100,48000,32000,0
