;; ID3v2.2 / 2.3 / 2.4 tag parser.
;;
;; Text goes into the f_* fields, converted to CP866 (the WC font):
;; encoding 0 is taken as CP1251 (what Russian taggers write there),
;; 1 / 2 are UTF-16 with or without BOM, 3 is UTF-8.
;; OUT: (audio_start) = first byte after the tag, (id3_found) = 1 if parsed.

FLD_LEN         equ 56          ; chars kept per long field

id3_parse:
    xor a
    ld (id3_found),a
    ld (tag_unsync),a
    ld (frame_unsync),a
    ld (prev_raw),a
    ld (v4_all_unsync),a
    ld (f_title),a
    ld (f_artist),a
    ld (f_aartist),a
    ld (f_album),a
    ld (f_year),a
    ld (f_track),a
    ld (f_genre),a
    ld hl,0
    ld (audio_start),hl
    ld (audio_start+2),hl
    call rd_getbyte : ret c : cp 'I' : ret nz
    call rd_getbyte : ret c : cp 'D' : ret nz
    call rd_getbyte : ret c : cp '3' : ret nz
    call rd_getbyte : ret c : ld (id3_ver),a
    call rd_getbyte : ret c
    call rd_getbyte : ret c : ld (id3_flg),a
    call rd_ss32
    ld bc,10
    add hl,bc
    jr nc,.nc
    inc de
.nc:
    ld (tag_end),hl
    ld (tag_end+2),de
    ld (audio_start),hl
    ld (audio_start+2),de
    ld a,(id3_ver)
    cp 4
    jr nz,.nofoot
    ld a,(id3_flg)
    bit 4,a                     ; footer present
    jr z,.nofoot
    ld bc,10
    add hl,bc
    jr nc,.nc2
    inc de
.nc2:
    ld (audio_start),hl
    ld (audio_start+2),de
.nofoot:
    ld a,(id3_ver)
    cp 2
    ret c
    cp 5
    ret nc                      ; unknown version: just skip the tag
    ld a,1
    ld (id3_found),a
    ; tag-level unsynchronisation (v2.2 / v2.3; in v2.4 it is per frame)
    ld a,(id3_ver)
    cp 4
    jr z,.v4u
    ld a,(id3_flg)
    rlca
    and 1
    ld (tag_unsync),a
    jr .ext
.v4u:
    ld a,(id3_flg)
    rlca
    and 1
    ld (v4_all_unsync),a
.ext:
    ld a,(id3_ver)
    cp 3
    jr c,.frames                ; v2.2 has no extended header
    ld a,(id3_flg)
    bit 6,a
    call nz,skip_ext_header
.frames:
    call frame_hdr
    jr c,.done
    call frame_handle
    jr .frames
.done:
    xor a
    ld (tag_unsync),a
    ld (frame_unsync),a
    jp genre_fix

;; v2.3: size (BE32) without itself; v2.4: syncsafe size including itself
skip_ext_header:
    ld a,(id3_ver)
    cp 4
    jr z,.v4
    call rd_be32
    jr .skip
.v4:
    call rd_ss32
    ld bc,-4
    add hl,bc
    jr c,.skip
    dec de
.skip:
    ld a,h : or l : or d : or e
    ret z
    ld a,d : or e
    ret nz                      ; nonsense size, give up on it
.loop:
    push hl
    call rawt
    pop hl
    ret c
    dec hl
    ld a,h : or l
    jr nz,.loop
    ret

;; Next byte of the tag, undoing v2.2/v2.3 unsynchronisation (FF 00 -> FF).
;; OUT: A, CF = 1 at EOF. Keeps B, DE, HL.
rawt:
    call rd_getbyte
    ret c
    ld c,a
    ld a,(tag_unsync)
    or a
    jr z,.keep
    ld a,(prev_raw)
    cp #FF
    jr nz,.keep
    ld a,c
    or a
    jr nz,.keep
    call rd_getbyte
    ret c
    ld c,a
.keep:
    ld a,c
    ld (prev_raw),a
    or a
    ret

;; OUT: DEHL = big-endian 32-bit value
rd_be32:
    ld hl,0
    ld d,h : ld e,l
    ld b,4
.loop:
    ld d,e : ld e,h : ld h,l
    call rawt
    ld l,a
    djnz .loop
    ret

;; OUT: DEHL = syncsafe 28-bit value (4 x 7 bits)
rd_ss32:
    ld hl,0
    ld d,h : ld e,l
    ld b,4
.loop:
    push bc
    ld b,7
.shl:
    add hl,hl : rl e : rl d
    djnz .shl
    call rawt
    and #7F
    or l
    ld l,a
    pop bc
    djnz .loop
    ret

;; Read a frame header. OUT: CF = 1 at the end of the frames
frame_hdr:
    call rd_tell
    ld bc,10
    ld a,(id3_ver)
    cp 3
    jr nc,.hl
    ld c,6
.hl:
    add hl,bc
    jr nc,.nc
    inc de
.nc:
    ; stop if pos + header > tag_end
    ld bc,(tag_end) : or a : sbc hl,bc
    ex de,hl
    ld bc,(tag_end+2) : sbc hl,bc
    jr c,.room
    ld a,h : or l : or d : or e
    jr nz,.stop
.room:
    xor a
    ld (fflag2),a
    ld (fid+3),a
    ld a,(id3_ver)
    cp 3
    jr c,.v2
    ld hl,fid
    ld b,4
    call rd_id
    ret c
    ld a,(id3_ver)
    cp 4
    jr z,.ss
    call rd_be32
    jr .size
.ss:
    call rd_ss32
.size:
    ld (frame_left),hl
    ld (frame_left+2),de
    call rawt                   ; status flags
    call rawt
    ld (fflag2),a               ; format flags
    jr .common
.v2:
    ld hl,fid
    ld b,3
    call rd_id
    ret c
    ld hl,0
    ld d,h : ld e,l
    ld b,3
.v2s:
    ld e,h : ld h,l
    call rawt
    ld l,a
    djnz .v2s
    ld (frame_left),hl
    ld (frame_left+2),de
.common:
    ; per-frame unsync: v2.4 format flag bit 1, or the v2.4 tag flag
    xor a
    ld (prev_f),a
    ld a,(id3_ver)
    cp 4
    ld a,0
    jr nz,.nofu
    ld a,(fflag2)
    and #02
    ld b,a
    ld a,(v4_all_unsync)
    or b
.nofu:
    ld (frame_unsync),a
    or a
    ret
.stop:
    scf
    ret

;; Read B chars of a frame id into (HL). CF = 1 on padding or garbage
rd_id:
    push hl
    push bc
    call rawt
    pop bc
    pop hl
    ret c
    cp '0'
    jr c,.bad
    cp '9'+1
    jr c,.ok
    cp 'A'
    jr c,.bad
    cp 'Z'+1
    jr nc,.bad
.ok:
    ld (hl),a
    inc hl
    djnz rd_id
    or a
    ret
.bad:
    scf
    ret

;; Next byte of the frame data. OUT: A, CF = 1 when the frame is over
fbyte:
    call fl_dec
    ret c
    call rawt
    ret c
    push af
    ld a,(frame_unsync)
    or a
    jr z,.ok
    ld a,(prev_f)
    cp #FF
    jr nz,.ok
    pop af
    push af
    or a
    jr nz,.ok
    pop af
    call fl_dec
    ret c
    call rawt
    ret c
    push af
.ok:
    pop af
    ld (prev_f),a
    or a
    ret

;; frame_left -= 1. CF = 1 if it was 0
fl_dec:
    push hl
    ld hl,(frame_left)
    ld a,h : or l
    jr nz,.lo
    ld hl,(frame_left+2)
    ld a,h : or l
    jr z,.zero
    dec hl
    ld (frame_left+2),hl
    ld hl,0
.lo:
    dec hl
    ld (frame_left),hl
    pop hl
    or a
    ret
.zero:
    pop hl
    scf
    ret

;; Skip what is left of the frame
skip_frame:
    ld a,(tag_unsync)
    ld b,a
    ld a,(frame_unsync)
    or b
    jr nz,.slow
    call rd_tell
    ld bc,(frame_left)
    add hl,bc
    ex de,hl
    ld bc,(frame_left+2)
    adc hl,bc
    ex de,hl
    jp rd_seek
.slow:
    call fbyte
    jr nc,.slow
    ret

;; Use the frame if it is one we show
frame_handle:
    ld hl,frame_tab
.find:
    ld a,(hl)
    or a
    jr z,skip_frame
    push hl
    ld de,fid
    ld b,4
.cmp:
    ld a,(de)
    cp (hl)
    jr nz,.no
    inc hl
    inc de
    djnz .cmp
    pop de                      ; drop the entry start
    ld e,(hl) : inc hl
    ld d,(hl) : inc hl
    ld b,(hl)
    push de
    push bc
    call frame_prefix
    pop bc
    pop hl
    jr c,skip_frame
    call read_text
    jr skip_frame
.no:
    pop hl
    ld bc,7
    add hl,bc
    jr .find

;; Skip the extra bytes in front of the frame data. CF = 1: frame is unusable
frame_prefix:
    ld a,(id3_ver)
    cp 3
    ccf
    ret nc                      ; v2.2: none
    ld a,(fflag2)
    ld b,a
    ld a,(id3_ver)
    cp 4
    jr z,.v4
    ld a,b
    and #C0                     ; compressed or encrypted
    scf
    ret nz
    bit 5,b                     ; group id
    jr z,.ok
    call fbyte
    ret
.v4:
    ld a,b
    and #0C                     ; compressed or encrypted
    scf
    ret nz
    bit 6,b                     ; group id
    jr z,.dli
    push bc
    call fbyte
    pop bc
    ret c
.dli:
    bit 0,b                     ; data length indicator
    jr z,.ok
    call fbyte : ret c
    call fbyte : ret c
    call fbyte : ret c
    call fbyte : ret c
.ok:
    or a
    ret

;; Read a text frame into (HL), at most B chars. Fields already set are kept.
read_text:
    ld a,(hl)
    or a
    ret nz
    ld (rt_dst),hl
    ld a,b
    ld (rt_max),a
    xor a
    ld (rt_len),a
    call fbyte
    ret c
    cp 1
    jr z,.bom
    cp 2
    jr z,.be
    cp 3
    jr z,.utf8
.cp1251:
    call fbyte
    ret c
    or a
    ret z
    call cp1251_866
    call rt_put
    jr .cp1251
.bom:
    call fbyte : ret c : ld d,a
    call fbyte : ret c : ld e,a
    ld a,d
    cp #FE
    jr z,.be                    ; FE FF: big endian
    cp #FF
    jr z,.le                    ; FF FE: little endian
    ld a,d                      ; no BOM: take it as a LE char
    ld d,e
    ld e,a
    jr .le_chr
.le:
    call fbyte : ret c : ld e,a
    call fbyte : ret c : ld d,a
.le_chr:
    ld a,d : or e
    ret z
    call uni_put
    jr .le
.be:
    call fbyte : ret c : ld d,a
    call fbyte : ret c : ld e,a
    ld a,d : or e
    ret z
    call uni_put
    jr .be
.utf8:
    call fbyte
    ret c
    or a
    ret z
    cp #80
    jr c,.asc
    cp #C0
    jr c,.utf8                  ; stray continuation byte
    cp #E0
    jr c,.two
    cp #F0
    jr c,.three
    call fbyte : ret c          ; 4-byte sequence: outside the BMP
    call fbyte : ret c
    call fbyte : ret c
    ld a,'?'
    call rt_put
    jr .utf8
.asc:
    call ctl_fix
    call rt_put
    jr .utf8
.two:
    and #1F
    ld d,a
    call fbyte
    ret c
    and #3F
    ld e,a
    ld a,d                      ; code = D << 6 | E
    rrca : rrca
    and #07
    ld h,a
    ld a,d
    rrca : rrca
    and #C0
    or e
    ld e,a
    ld d,h
    call uni_put
    jr .utf8
.three:
    and #0F
    rlca : rlca : rlca : rlca
    ld d,a
    call fbyte
    ret c
    and #3F
    ld e,a
    rrca : rrca
    and #0F
    or d
    ld d,a
    ld a,e
    rrca : rrca
    and #C0
    ld e,a
    call fbyte
    ret c
    and #3F
    or e
    ld e,a
    call uni_put
    jr .utf8

;; A < #20 -> space
ctl_fix:
    cp #20
    ret nc
    ld a,' '
    ret

;; A = CP1251 char -> A = CP866 char
cp1251_866:
    cp #80
    jr c,ctl_fix
    cp #C0
    jr nc,.cyr
    cp #A8
    jr z,.yo
    cp #B8
    jr z,.yo2
    cp #B9
    jr z,.no
    cp #A0
    jr z,.sp
    cp #96
    jr z,.dash
    cp #97
    jr z,.dash
    ld a,'?'
    ret
.cyr:
    cp #F0
    jr nc,.r
    sub #40                     ; А..п
    ret
.r:
    sub #10                     ; р..я
    ret
.yo:
    ld a,#F0
    ret
.yo2:
    ld a,#F1
    ret
.no:
    ld a,#FC
    ret
.sp:
    ld a,' '
    ret
.dash:
    ld a,'-'
    ret

;; DE = Unicode code point (BMP) -> CP866 char appended to the field
uni_put:
    ld a,d
    or a
    jr nz,.hi
    ld a,e
    cp #80
    jr c,.asc
    cp #A0
    jr z,.sp
    jr .q
.asc:
    call ctl_fix
    jr rt_put
.hi:
    cp #04
    jr z,.cyr
    cp #20
    jr nz,.q
    ld a,e                      ; punctuation block
    cp #13
    jr z,.dash
    cp #14
    jr z,.dash
    cp #18
    jr z,.apo
    cp #19
    jr z,.apo
    cp #1C
    jr z,.quo
    cp #1D
    jr z,.quo
    jr .q
.cyr:
    ld a,e
    cp #01
    jr z,.yo
    cp #51
    jr z,.yo2
    cp #10
    jr c,.q
    cp #40
    jr c,.a_p
    cp #50
    jr nc,.q
    add a,#A0                   ; р..я -> #E0..#EF
    jr rt_put
.a_p:
    add a,#70                   ; А..п -> #80..#AF
    jr rt_put
.yo:
    ld a,#F0
    jr rt_put
.yo2:
    ld a,#F1
    jr rt_put
.sp:
    ld a,' '
    jr rt_put
.dash:
    ld a,'-'
    jr rt_put
.apo:
    ld a,"'"
    jr rt_put
.quo:
    ld a,'"'
    jr rt_put
.q:
    ld a,'?'
    ; fall through

;; Append A to the current field if there is room
rt_put:
    push hl
    push af
    ld a,(rt_len)
    ld hl,rt_max
    cp (hl)
    jr nc,.full
    inc a
    ld (rt_len),a
    dec a
    ld hl,(rt_dst)
    add a,l
    ld l,a
    jr nc,.nc
    inc h
.nc:
    pop af
    ld (hl),a
    inc hl
    ld (hl),0
    pop hl
    ret
.full:
    pop af
    pop hl
    ret

;; TCON: "(17)", "17", "(17)Rock" or plain text -> plain text
genre_fix:
    ld hl,f_genre
    ld a,(hl)
    or a
    ret z
    ld e,0                      ; 1 = the number is in parentheses
    cp '('
    jr nz,.num
    inc hl
    inc e
.num:
    ld c,0                      ; number
    ld b,0                      ; digits seen
.dig:
    ld a,(hl)
    sub '0'
    jr c,.end
    cp 10
    jr nc,.end
    ld d,a
    ld a,c                      ; c = c * 10 + d
    add a,a
    ld c,a
    add a,a
    add a,a
    add a,c
    add a,d
    ld c,a
    inc b
    inc hl
    jr .dig
.end:
    ld a,b
    or a
    ret z                       ; plain text
    cp 4
    ret nc
    ld a,e
    or a
    jr z,.bare
    ld a,(hl)
    cp ')'
    ret nz
    inc hl
    ld a,(hl)
    or a
    jr z,.lookup
    ld de,f_genre               ; "(17)Rock" -> "Rock"
.mv:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    or a
    jr nz,.mv
    ret
.bare:
    ld a,(hl)
    or a
    ret nz                      ; "80s Pop": text that starts with digits
.lookup:
    ld a,c
    cp GENRES
    ret nc
    ld hl,genre_names
    or a
    jr z,.copy
    ld b,a
.skip:
    ld a,(hl)
    inc hl
    or a
    jr nz,.skip
    djnz .skip
.copy:
    ld de,f_genre
.cp:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    or a
    jr nz,.cp
    ret

;; id (4 bytes, v2.2 ids padded with 0), field, max length
frame_tab:
    db "TIT2" : dw f_title   : db FLD_LEN
    db "TPE1" : dw f_artist  : db FLD_LEN
    db "TPE2" : dw f_aartist : db FLD_LEN
    db "TALB" : dw f_album   : db FLD_LEN
    db "TYER" : dw f_year    : db 4
    db "TDRC" : dw f_year    : db 4
    db "TRCK" : dw f_track   : db 8
    db "TCON" : dw f_genre   : db 20
    db "TT2",0 : dw f_title   : db FLD_LEN
    db "TP1",0 : dw f_artist  : db FLD_LEN
    db "TP2",0 : dw f_aartist : db FLD_LEN
    db "TAL",0 : dw f_album   : db FLD_LEN
    db "TYE",0 : dw f_year    : db 4
    db "TRK",0 : dw f_track   : db 8
    db "TCO",0 : dw f_genre   : db 20
    db 0

;; ID3v1 genres 0..79
genre_names:
    db "Blues",0,"Classic Rock",0,"Country",0,"Dance",0,"Disco",0
    db "Funk",0,"Grunge",0,"Hip-Hop",0,"Jazz",0,"Metal",0
    db "New Age",0,"Oldies",0,"Other",0,"Pop",0,"R&B",0
    db "Rap",0,"Reggae",0,"Rock",0,"Techno",0,"Industrial",0
    db "Alternative",0,"Ska",0,"Death Metal",0,"Pranks",0,"Soundtrack",0
    db "Euro-Techno",0,"Ambient",0,"Trip-Hop",0,"Vocal",0,"Jazz+Funk",0
    db "Fusion",0,"Trance",0,"Classical",0,"Instrumental",0,"Acid",0
    db "House",0,"Game",0,"Sound Clip",0,"Gospel",0,"Noise",0
    db "Alt. Rock",0,"Bass",0,"Soul",0,"Punk",0,"Space",0
    db "Meditative",0,"Instrumental Pop",0,"Instrumental Rock",0,"Ethnic",0,"Gothic",0
    db "Darkwave",0,"Techno-Industrial",0,"Electronic",0,"Pop-Folk",0,"Eurodance",0
    db "Dream",0,"Southern Rock",0,"Comedy",0,"Cult",0,"Gangsta",0
    db "Top 40",0,"Christian Rap",0,"Pop/Funk",0,"Jungle",0,"Native American",0
    db "Cabaret",0,"New Wave",0,"Psychedelic",0,"Rave",0,"Showtunes",0
    db "Trailer",0,"Lo-Fi",0,"Tribal",0,"Acid Punk",0,"Acid Jazz",0
    db "Polka",0,"Retro",0,"Musical",0,"Rock & Roll",0,"Hard Rock",0
GENRES          equ 80
