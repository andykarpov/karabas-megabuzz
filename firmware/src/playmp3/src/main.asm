    DEVICE ZXSPECTRUM48
    org #2000
    jp start

    include "drivers/esxdos.asm"
    include "drivers/megabuzz.asm"
    include "drivers/zxbios.asm"
    include "drivers/args.asm"
    include "utils/strings.asm"

start:
    push hl
    print hello
    pop hl
    ;; ARGS parsing
    ld a, l : or h : jp z, noArgs

    ld de, argBuff : call Args.parseOne
    ld a, b : and a : jp z, noArgsTxt

playMP3:
    ld a, (argBuff) : and a : jp z, noArgs

    ld hl, argBuff, a, '.', bc, 80 : cpir : call nz, addExt

    print initingTxt
    xor a : call MegaBuzz.init

    print openingTxt
    print argBuff
    print crLf

    ld b, Dos.FMODE_READ, hl, argBuff
    call Dos.fopen : jp c, error
    ld (fp), a

loadLoop:
    ld a, (fp), bc, bufferSize, hl, buffer
    call Dos.fread
    call MegaBuzz.checkFifo
    ld a, b : or c : jr z, .playSong

    ld hl, buffer
.sendBytesToMB
    ld a, (hl)
    call MegaBuzz.sendByte
    inc hl
    dec bc
    ld a, b : or c : jr nz, .sendBytesToMB

    jr loadLoop
.playSong
    ld a, (fp) : call Dos.fclose
    jp MegaBuzz.finish

addExt:
    xor a : ld hl, argBuff, bc, 80 : cpir : dec hl
    ld a, '.' : ld (hl), a : inc hl
    ld a, 'm' : ld (hl), a : inc hl
    ld a, 'p' : ld (hl), a : inc hl 
    ld a, '3' : ld (hl), a : inc hl
    xor a     : ld (hl), a
    ret

noArgs:
    print noArgsTxt
    ret

error:
    print errorTxt
    ret

hello db "PlayMP3", 13
      db "v. 0.2 by andykarpov", 13, 0

noArgsTxt db 13
          db "Usage:",13
          db "To play track:",13
          db ".playmp3 <file.mp3>",13, 13

initingTxt db "Initing Megabuzz", 13, 0 

openingTxt db "Loading: ", 0
errorTxt   db 13, "ERROR!", 13, 0
crLf db 13, 0

fp db 0

argBuff ds 80

buffer ds #1000
bufferSize equ $ - buffer
    SAVEBIN "playmp3", #2000, $ - #2000
