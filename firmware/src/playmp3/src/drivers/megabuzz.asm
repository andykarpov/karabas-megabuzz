    macro MB_SetCommandMode
    push bc
    ld a, MegaBuzz.REG_CTRL : ld bc, MegaBuzz.PORT_ZXUNO_REG : out (c), a
    pop bc
    endm

    macro MB_SetDataMode
    push bc
    ld a, MegaBuzz.REG_DATA : ld bc, MegaBuzz.PORT_ZXUNO_REG : out (c), a
    pop bc
    endm

    macro MB_Send nn
    push bc
    ld a, nn : ld bc, MegaBuzz.PORT_ZXUNO_DATA : out (c), a
    pop bc
    endm

    macro MB_SendA
    push bc
    ld bc, MegaBuzz.PORT_ZXUNO_DATA : out (c), a
    pop bc
    endm

    macro MB_Read
    push bc
    ld bc, MegaBuzz.PORT_ZXUNO_DATA
    in a, (c)
    pop bc
    endm

    module MegaBuzz

;; Control ports
PORT_ZXUNO_REG   EQU #FC3B     ; ZXUNO control port
PORT_ZXUNO_DATA  EQU #FD3B     ; ZXUNO data port
REG_CTRL         EQU #F5       ; FIFO status (bit 7 - FULL, bit 6..0 - number of occupied 32byte blocks in FIFO)
REG_DATA         EQU #F6       ; FIFO data register

init:
    MB_SetCommandMode
    MB_Send #80
    MB_Send #00
    MB_SetDataMode
    RET

;; Check for enough free blocks in FIFO
checkFifo:
    PUSH AF
.wait_fifo:

    MB_Read

    BIT 7, A                    ; If the FIFO is overflowed - waiting
    JR NZ, .wait_fifo

    AND #7F                    ; Masking the bits 6..0
    CP 64                      ; Is enough free space to fill the FIFO?
    JR NC, .wait_fifo          ; If occupied >= 64 blocks - waiting

    POP AF
    RET

;; Sending a byte to the FIFO
; IN: A = data byte of MP3
sendByte:
    MB_SendA
    RET

;; Sending a buffer to the FIFO
;; IN: HL = current addres in the DataBuffer
;;     DE = count of bytes to send (e.g. 1024)
;; OUT: HL incremented by DE bytes
sendBuffer:
    PUSH BC
    PUSH DE
    PUSH AF

    LD A, MegaBuzz.REG_DATA 
    LD BC, MegaBuzz.PORT_ZXUNO_REG 
    OUT (C), A

    LD BC, MegaBuzz.PORT_ZXUNO_DATA

.loop:
    LD A, (HL)
    OUT (C), A
    INC HL
    
    DEC DE
    LD A, D
    OR E
    JR NZ, .loop

    POP AF
    POP DE
    POP BC
    RET

; Waiting for playback end
finish:
    MB_SetCommandMode
.wait_loop:
    MB_Read
    AND #7F
    JR NZ, .wait_loop

    ; Additional delay for VS1053
    LD DE, 25000
.final_delay:
    DEC DE
    LD A, D
    OR E
    JR NZ, .final_delay
    RET

    endmodule
