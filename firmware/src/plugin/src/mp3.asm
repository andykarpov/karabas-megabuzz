PLUGIN_ORG  = #8000
PLUGIN_SIZE = #2000

RESULT_OK   = 1
RESULT_ERR  = 128

    device zxspectrum48
    org PLUGIN_ORG
    jr start
    db "BP", 0, 0 ;; Browse plugin
    db 0, 0 ;; Flags
    db ".MP3 player v0.1 - MegaBuzz", 0

;; HL - filename
start:
    ld b, Dos.FMODE_READ
    call Dos.fopen : jp c, err
    ld (fp), a
    call MegaBuzz.init
.loadLoop
    ld a, (fp), hl, buffer, bc, buffer_size : call Dos.fread
    ld a, b : or c : jp z, .exit
    ld hl, buffer
.sendLoop
    ld a, b : or c : jp z, .loadLoop
    call MegaBuzz.checkFifo
    ld a, (hl) : call MegaBuzz.sendByte
    inc hl : dec bc
    jr .sendLoop
.exit
    ld a, (fp) : call Dos.fclose
    call MegaBuzz.finish

    ld a, RESULT_OK 
    ret

err:
    ld a, RESULT_ERR
    ret

    include "esxdos.asm"
    include "megabuzz.asm"

fp          db 0
buffer      ds (PLUGIN_ORG + PLUGIN_SIZE) - $
buffer_size equ $ - buffer

    savebin "mp3", PLUGIN_ORG, PLUGIN_SIZE
    
