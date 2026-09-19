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
    ld a, (fp)
    ld hl, buffer
    ld bc, buffer_size 
    call Dos.fread ; read 4kb buffer
    ld a, b : or c : jp z, .exit

    srl b : rr c
    srl b : rr c
    srl b : rr c
    srl b : rr c
    srl b : rr c
    ; now C = count of 32 byte blocks (1..128)
    
    ld hl, buffer

.sendBlocksLoop
    ld a, c : or a : jr z, .loadLoop

    push bc
    push hl
    call MegaBuzz.getFreeBlocks ; A = free blocks
    pop hl
    pop bc

    or a : jr z, .sendBlocksLoop

    cp c
    jr c, .use_available
    ld a, c
.use_available:
    ; A = count of blocks to send on this interation
    ld b, a                 ; Move to B for djnz loop
    
    ; Remaining blocks count in C
    sub c
    neg
    ld c, a

.blockLoop
    push bc
    call MegaBuzz.send32Bytes
    pop bc
    djnz .blockLoop

    jr .sendBlocksLoop

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
buffer      ds 4096
buffer_size equ 4096

    savebin "mp3", PLUGIN_ORG, $-PLUGIN_ORG

