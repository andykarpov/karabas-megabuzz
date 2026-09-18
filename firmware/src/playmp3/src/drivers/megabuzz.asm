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
PORT_ZXUNO_REG   EQU #FC3B     ; Порт выбора регистра ZXUNO
PORT_ZXUNO_DATA  EQU #FD3B     ; Порт данных ZXUNO
REG_CTRL         EQU #F5       ; Статус FIFO (бит 7 - FULL, биты 6..0 - блоки)
REG_DATA         EQU #F6       ; Регистр данных FIFO

init:
    MB_SetCommandMode
    MB_Send #80
    MB_Send #00
    MB_SetDataMode
    RET

;; Процедура проверки свободных блоков в FIFO
checkFifo:
    PUSH AF
.wait_fifo:

    MB_Read

    BIT 7, A                    ; Если FIFO переполнено - ждем
    JR NZ, .wait_fifo

    AND #7F                    ; Маскируем количество блоков
    CP 64                       ; Меньше безопасного порога?
    JR NC, .wait_fifo          ; Если занято >= 64, ждем

    POP AF
    RET

;; Процедура отправки байта с проверкой FIFO
; Вход: A = байт данных MP3
sendByte:
    MB_SendA
    RET

; --- Ожидание завершения воспроизведения остатков буфера ---
finish:
    MB_SetCommandMode
.wait_loop:
    MB_Read
    AND #7F
    JR NZ, .wait_loop

    ; Дополнительная пауза декодеру VS1053 на "дожевывание"
    LD DE, 25000
.final_delay:
    DEC DE
    LD A, D
    OR E
    JR NZ, .final_delay
    RET

    endmodule
