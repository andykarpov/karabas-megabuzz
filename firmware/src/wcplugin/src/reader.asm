;; Buffered reader over the WC file stream.
;;
;; WC streams the file by 512-byte sectors (LOAD512), can rewind it (GIPAGPL)
;; and skip sectors (LOADNONE). The buffer BUF holds the bytes
;; [buf_base, buf_base + buf_len) of the file, rd_off is the next byte in it.
;; file_pos is where the WC stream stands (always a multiple of 512).

BUF_SECT        equ 4           ; small reads keep the FIFO topped up on a slow card
BUFSZ           equ BUF_SECT*512

rd_init:
    ld ix,(panel_ix)
    WCALL WCF_GIPAGPL
    ld hl,0
    ld (file_pos),hl : ld (file_pos+2),hl
    ld (buf_base),hl : ld (buf_base+2),hl
    ld (buf_len),hl
    ld (rd_off),hl
    ret

;; Read the next chunk at file_pos into BUF.
;; OUT: NZ = data loaded, Z = end of file (buf_len = 0)
rd_refill:
    ld hl,(file_pos) : ld (buf_base),hl
    ld hl,(file_pos+2) : ld (buf_base+2),hl
    ld hl,0
    ld (rd_off),hl
    ld (buf_len),hl
    ; HL:DE = file_size - file_pos
    ld hl,(file_size) : ld bc,(file_pos) : or a : sbc hl,bc : ex de,hl
    ld hl,(file_size+2) : ld bc,(file_pos+2) : sbc hl,bc
    jr c,.eof
    ld a,h : or l
    jr nz,.full
    ld a,d : or e
    jr z,.eof
    ex de,hl
    ld bc,BUFSZ
    or a
    sbc hl,bc
    add hl,bc
    jr nc,.full
    ld (buf_len),hl             ; the tail of the file, < BUFSZ
    ld bc,511
    add hl,bc
    ld a,h
    srl a                       ; sectors = (len + 511) / 512
    jr .load
.full:
    ld hl,BUFSZ
    ld (buf_len),hl
    ld a,BUF_SECT
.load:
    ld b,a
    push bc
    ld ix,(panel_ix)
    ld hl,BUF
    WCALL WCF_LOAD512
    pop bc
    ld a,b                      ; file_pos += sectors * 512
    add a,a
    ld hl,(file_pos)
    add a,h
    ld h,a
    ld (file_pos),hl
    jr nc,.done
    ld hl,(file_pos+2)
    inc hl
    ld (file_pos+2),hl
.done:
    or 1                        ; NZ
    ret
.eof:
    xor a
    ret

;; OUT: A = next byte, CF = 0; CF = 1 at the end of file. Keeps BC, DE, HL.
rd_getbyte:
    push hl
    push de
    ld hl,(rd_off)
    ld de,(buf_len)
    or a
    sbc hl,de
    jr c,.have
    push bc
    call rd_refill
    pop bc
    jr z,.eof
.have:
    ld hl,(rd_off)
    ld de,BUF
    inc hl
    ld (rd_off),hl
    dec hl
    add hl,de
    ld a,(hl)
    pop de
    pop hl
    or a                        ; CF = 0
    ret
.eof:
    pop de
    pop hl
    scf
    ret

;; OUT: DEHL = file position of the next byte
rd_tell:
    ld hl,(buf_base)
    ld bc,(rd_off)
    add hl,bc
    ld de,(buf_base+2)
    ret nc
    inc de
    ret

;; DEHL = new file position (may be behind or ahead)
rd_seek:
    ld (seek_tgt),hl
    ld (seek_tgt+2),de
    ; inside the buffer already?
    ld bc,(buf_base) : or a : sbc hl,bc : push hl
    ex de,hl
    ld bc,(buf_base+2) : sbc hl,bc
    pop de                      ; HL:DE = target - buf_base
    jr c,.far
    ld a,h : or l
    jr nz,.far
    ld hl,(buf_len)
    or a
    sbc hl,de
    jr c,.far
    jr z,.far
    ld (rd_off),de
    ret
.far:
    ld hl,(seek_tgt)
    ld a,h
    and 1
    ld h,a
    ld (seek_in),hl             ; offset inside the sector
    ld hl,(seek_tgt)
    ld a,h
    and #FE
    ld h,a
    ld l,0
    ld (seek_sec),hl
    ld de,(seek_tgt+2)
    ld (seek_sec+2),de
    ; behind the stream? rewind
    ld bc,(file_pos) : or a : sbc hl,bc
    ex de,hl
    ld bc,(file_pos+2) : sbc hl,bc
    jr nc,.fwd
    ld ix,(panel_ix)
    WCALL WCF_GIPAGPL
    ld hl,0
    ld (file_pos),hl
    ld (file_pos+2),hl
.fwd:
    ; HL = (seek_sec - file_pos) / 512, files up to 32 MB
    ld hl,(seek_sec) : ld bc,(file_pos) : or a : sbc hl,bc : ex de,hl
    ld hl,(seek_sec+2) : ld bc,(file_pos+2) : sbc hl,bc
    srl h : rr l : rr d
    ld h,l
    ld l,d
.skip:
    ld a,h
    or a
    jr nz,.big
    ld a,l
    or a
    jr z,.done
    ld b,a
    ld hl,0
    jr .do
.big:
    ld b,255
    ld de,-255
    add hl,de
.do:
    push hl
    call rd_skip_sectors
    pop hl
    jr .skip
.done:
    ld hl,(seek_sec) : ld (file_pos),hl
    ld hl,(seek_sec+2) : ld (file_pos+2),hl
    call rd_refill
    ld hl,(buf_len)
    ld de,(seek_in)
    or a
    sbc hl,de
    jr nc,.in
    ld de,(buf_len)
.in:
    ld (rd_off),de
    ret

;; B = sectors to skip in the WC stream
rd_skip_sectors:
    IFNDEF NO_LOADNONE
    ld ix,(panel_ix)
    WCALL WCF_LOADNONE
    ELSE
    ; fallback: read them into the buffer
.loop:
    ld a,b
    cp BUF_SECT
    jr c,.last
    ld a,BUF_SECT
.last:
    ld c,a
    push bc
    ld b,c
    ld ix,(panel_ix)
    ld hl,BUF
    WCALL WCF_LOAD512
    pop bc
    ld a,b
    sub c
    ld b,a
    jr nz,.loop
    ENDIF
    ret
