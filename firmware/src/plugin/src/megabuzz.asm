    macro MB_SetCommandMode
    ld a, MegaBuzz.REG_CTRL : ld bc, MegaBuzz.PORT_ZXUNO_REG : out (c), a
    endm

    macro MB_SetDataMode
    ld a, MegaBuzz.REG_DATA : ld bc, MegaBuzz.PORT_ZXUNO_REG : out (c), a
    endm

    macro MB_Send nn
    ld a, nn : ld bc, MegaBuzz.PORT_ZXUNO_DATA : out (c), a
    endm

    macro MB_SendA
    ld bc, MegaBuzz.PORT_ZXUNO_DATA : out (c), a
    endm

    macro MB_Read
    ld bc, MegaBuzz.PORT_ZXUNO_DATA : in a, (c)
    endm

    module MegaBuzz

;; Control ports
PORT_ZXUNO_REG   EQU #FC3B     ; ZXUNO control port
PORT_ZXUNO_DATA  EQU #FD3B     ; ZXUNO data port
REG_CTRL         EQU #F5       ; FIFO status
REG_DATA         EQU #F6       ; FIFO data register

init:
    MB_SetCommandMode
    MB_Send #80
    MB_Send #00
    MB_SetDataMode
    RET

;; Check FIFO free space 
;; OUT: A = count of free 32-bytes blocks (0..127)
getFreeBlocks:
    MB_SetCommandMode
    MB_Read
    push af
    MB_SetDataMode
    pop af

    bit 7, a
    jr nz, .fifo_full

    and #7F
    ld b, a
    ld a, 127
    sub b
    jr nc, .limit_ok    
    xor a
.limit_ok:
    ret

.fifo_full:
    xor a
    ret

;; Send 32-bytes data block to FIFO
;; IN: HL = start address
;; OUT: HL increments by 32 bytes. BC = #FD3B. A is dirty.
send32Bytes:
    ld bc, PORT_ZXUNO_DATA

    macro _send4
    ld a, (hl) : out (c), a : inc hl
    ld a, (hl) : out (c), a : inc hl
    ld a, (hl) : out (c), a : inc hl
    ld a, (hl) : out (c), a : inc hl
    endm

    _send4 : _send4 : _send4 : _send4
    _send4 : _send4 : _send4 : _send4
    ret

; Waiting for playback finish
finish:
    MB_SetCommandMode
.wait_loop:
    MB_Read
    and #7F
    jr nz, .wait_loop

    ; Additional delay for VS1053
    ld de, 25000
.final_delay:
    dec de
    ld a, d
    or e
    jr nz, .final_delay
    ret

    endmodule

