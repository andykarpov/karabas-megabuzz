    DEVICE ZXSPECTRUM48

; --- Константы портов ---
PORT_ZXUNO_REG  EQU #FC3B     ; Порт регистра ZXUNO
PORT_ZXUNO_DATA EQU #FD3B     ; Порт данных ZXUNO
REG_CTRL        EQU #F5       ; Регистр статуса FIFO (биты 6..0 - блоки, бит 7 - full)
REG_DATA        EQU #F6       ; Регистр данных

; --- Инициализация TAP ---
;    EMPTYTAP "testmp3.tap"               
    ORG #8000                           

Start:
    DI                                  ; Запрещаем прерывания на время воспроизведения

    ; Soft Reset VS1053 при старте программы
    LD A, REG_CTRL
    LD BC, PORT_ZXUNO_REG
    OUT (C), A

    LD A, #80
    LD BC, PORT_ZXUNO_DATA
    OUT (C), A

    LD B, 0
ResetDelay:
    DJNZ ResetDelay
    LD B, 0
ResetDelay2:
    DJNZ ResetDelay2

    LD A, REG_CTRL
    LD BC, PORT_ZXUNO_REG
    OUT (C), A

    XOR A
    LD BC, PORT_ZXUNO_DATA
    OUT (C), A

    ; Основной счетчик проигрывания файла (20 раз)
    LD B, 20                            

MainLoop:
    PUSH BC                             ; Сохраняем счетчик повторов

    ; --- 2. Инициализация указателей MP3 файла ---
    LD HL, FileStart                    
    LD DE, FileEnd                      

StreamLoop:
    ; Проверяем достижение конца файла (HL >= DE)
    LD A, H
    CP D
    JR C, CheckFIFO                     ; Если H < D, гарантированно шлем блок
    JR NZ, EndOfFile                    ; Если H > D, файл кончился
    LD A, L
    CP E
    JR NC, EndOfFile                    ; Если L >= E, файл кончился

CheckFIFO:
    ; --- 3. Опрос порта статуса ---
    LD A, REG_CTRL
    LD BC, PORT_ZXUNO_REG
    OUT (C), A

    LD BC, PORT_ZXUNO_DATA
    IN A, (C)                           ; Читаем состояние FIFO

    ; Шаг А: Проверяем жесткий флаг переполнения (7-й бит)
    BIT 7, A                            
    JR NZ, CheckFIFO                    ; Если FIFO Full, крутимся в цикле и ждем

    ; Шаг Б: Анализируем количество занятых блоков (биты 6..0)
    AND #7F                             ; Отрезаем 7-й бит
    CP 64                               ; Безопасный порог: в FIFO занято меньше 64 блоков?
    JR NC, CheckFIFO                    ; Если занято >= 64 блоков, ждем, пока FPGA подразгрузит буфер

    ; --- 4. Отправка блока из 32 байт (Оптимизированный вариант) ---
    LD A, REG_DATA
    LD BC, PORT_ZXUNO_REG
    OUT (C), A

    LD BC, PORT_ZXUNO_DATA  ; В BC всегда стабильно #FD3B
    LD E, 32                ; Используем регистр E как счетчик байт
SendBlockLoop:
    LD A, (HL)              ; Читаем байт из памяти
    OUT (C), A              ; Отправляем в 16-битный порт #FD3B
    INC HL                  ; Сдвигаем указатель памяти
    DEC E                   ; Уменьшаем счетчик
    JR NZ, SendBlockLoop    ; Циблим, пока не отправим все 32 байта

    JR StreamLoop           ; Возвращаемся к стримингу следующего блока

EndOfFile:
    ; --- 5. Ожидание окончания воспроизведения текущего трека ---
    ; Перед следующим повтором мы обязаны дождаться, пока FPGA полностью 
    ; выкачает все данные по SPI и буфер станет абсолютно пустым (0 блоков).
WaitBufferEmpty:
    LD A, REG_CTRL
    LD BC, PORT_ZXUNO_REG
    OUT (C), A

    LD BC, PORT_ZXUNO_DATA
    IN A, (C)                           ; Читаем состояние FIFO
    AND #7F                             ; Проверяем только биты занятости 6..0
    JR NZ, WaitBufferEmpty              ; Если занято > 0 блоков, продолжаем ждать

    ; Дополнительная пауза (около 300 мс) чтобы внутренний 2КБ декодер VS1053 
    ; успел полностью «дожевать» аудиопоток из своего внутреннего ОЗУ.
    LD DE, 25000
VS1053_InternalDelay:
    DEC DE
    LD A, D
    OR E
    JR NZ, VS1053_InternalDelay

    POP BC                              ; Восстанавливаем счетчик циклов из стека
    DJNZ MainLoop                       ; Повторяем процедуру 20 раз

    ; --- Финализация ---
    EI                                  ; Возвращаем прерывания системе
    RET                                 ; Корректный выход в BASIC

; --- Секция данных ---
FileStart:
    INCBIN "sweep32.mp3"                 ; Подключаем ваш MP3 файл
FileEnd:

;    SAVETAP "testmp3.tap", BASIC, "Loader", Start, 10
;    SAVETAP "testmp3.tap", CODE, "PlayMP3", Start, FileEnd - Start
    SAVESNA "testmp3.sna", Start

