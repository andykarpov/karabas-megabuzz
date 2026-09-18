    DEVICE ZXSPECTRUM48

; --- Константы ESXDOS API ---
SYS_F_OPEN       EQU #40
SYS_F_CLOSE      EQU #41
SYS_F_READ       EQU #42

FA_READ          EQU #01
FA_OPEN_EX       EQU #00

; --- Константы портов Звуковой Платы (ZX-Uno / VS1053) ---
PORT_ZXUNO_REG   EQU #FC3B     ; Порт регистра
PORT_ZXUNO_DATA  EQU #FD3B     ; Порт данных
REG_CTRL         EQU #F5       ; Статус FIFO (бит 7: full, 6..0: занято блоков)
REG_DATA         EQU #F6       ; Регистр данных FIFO

; --- Настройки Буфера ОЗУ ---
; 1024 байта — оптимальный размер для баланса скорости чтения SD-карты и памяти
BUF_SIZE         EQU 1024   

    ORG #2000                      ; Все .dot команды ESXDOS стартуют отсюда

Start:
    ; При вызове из .browse: HL указывает на путь к файлу (например, "h0:/MUSIC/TRACK.MP3")
    LD A, (HL)
    AND A
    RET Z                          ; Если строка пустая, выходим

    PUSH HL                        ; Сохраняем указатель на имя файла
    DI                             ; Запрещаем маскируемые прерывания на время воспроизведения

    ; --- 1. Аппаратный сброс (Soft Reset) VS1053 ---
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

    ; --- 2. Открытие MP3 файла через ESXDOS ---
    POP HL                         ; Восстанавливаем сохраненный указатель на путь
    LD A, '*'                      ; Символ '*' означает "использовать текущий привод"
    LD B, FA_READ                  ; Режим: только чтение
    LD C, FA_OPEN_EX               ; Режим открытия: существующий файл
    RST #08                        ; Вызов ESXDOS
    DB SYS_F_OPEN
    JR NC, FileOpened              ; Если флаг переноса (C) сброшен — успешно
    
    ; Сюда попадаем в случае ошибки открытия (например, файл заблокирован)
    EI
    RET

FileOpened:
    LD (FileHandle), A             ; Запоминаем дескриптор файла

StreamLoop:
    ; --- 3. Чтение порции данных в промежуточный буфер ---
    LD A, (FileHandle)
    LD BC, BUF_SIZE                ; Запрашиваем 1024 байта
    LD DE, DataBuffer              ; Адрес буфера в ОЗУ Спектрума
    RST #08
    DB SYS_F_READ
    JR NC, ReadOk
    JR CloseFile                   ; При ошибке чтения аварийно закрываем файл

ReadOk:
    ; ESXDOS возвращает в BC количество реально прочитанных байт
    LD A, B
    OR C
    JR Z, CloseFile               ; Если вернулся 0 — файл прочитан полностью

    ; Настраиваем указатели для разбора буфера
    LD HL, DataBuffer              ; Начало данных
    PUSH HL
    ADD HL, BC
    EX DE, HL                      ; Теперь DE указывает на конец полезных данных (DataBuffer + BC)
    POP HL                         ; HL снова указывает на начало буфера

SendBufferLoop:
    ; Проверяем, не дошли ли до конца прочитанного буфера (HL >= DE)
    LD A, H
    CP D
    JR C, CheckFIFO
    JR NZ, StreamLoop              ; Если весь буфер отправлен, идем читать следующий с SD
    LD A, L
    CP E
    JR NC, StreamLoop

CheckFIFO:
    ; --- 4. Проверка состояния FIFO чипа ---
    LD A, REG_CTRL
    LD BC, PORT_ZXUNO_REG
    OUT (C), A

    LD BC, PORT_ZXUNO_DATA
    IN A, (C)                      ; Читаем байт состояния

    BIT 7, A                       ; Проверяем 7-й бит (FIFO Full)
    JR NZ, CheckFIFO               ; Если 1 — буфер полон, ждем

    AND #7F                        ; Маскируем, оставляя только количество блоков (биты 6..0)
    CP 64                          ; Безопасный порог из вашего примера
    JR NC, CheckFIFO               ; Если занято >= 64 блоков, ждем разгрузки FPGA

    ; --- 5. Отправка блока из 32 байт ---
    LD A, REG_DATA
    LD BC, PORT_ZXUNO_REG
    OUT (C), A

    LD BC, PORT_ZXUNO_DATA         ; Стабильный адрес порта данных #FD3B
    LD A, 32                       ; Счетчик на 32 итерации
Send32Loop:
    PUSH AF
    LD A, (HL)                     ; Берем байт из ОЗУ буфера
    OUT (C), A                     ; Кидаем в порт
    INC HL                         ; Инкремент указателя буфера
    POP AF
    DEC A
    JR NZ, Send32Loop              ; Повторяем, пока не уйдут все 32 байта

    ; --- 6. Опрос клавиатуры для возможности прерывания песни ---
    ; Опрашиваем полуряд пробела (Space-B-N-M-SymShift)
    LD BC, #7FFE
    IN A, (C)
    RRA                            ; Сдвигаем бит 0 (клавиша SPACE) в флаг переноса (C)
    JR C, SendBufferLoop           ; Если перенос равен 1, кнопка НЕ нажата — продолжаем играть

CloseFile:
    ; --- 7. Закрытие файла и ожидание опустошения буферов ---
    LD A, (FileHandle)
    RST #08
    DB SYS_F_CLOSE

WaitBufferEmpty:
    LD A, REG_CTRL
    LD BC, PORT_ZXUNO_REG
    OUT (C), A
    LD BC, PORT_ZXUNO_DATA
    IN A, (C)
    AND #7F                        ; Проверяем оставшиеся блоки
    JR NZ, WaitBufferEmpty         ; Ждем, пока железный FIFO станет пустым (0)

    ; Финальная пауза декодеру VS1053 на "дожевывание" внутреннего ОЗУ
    LD DE, 25000
FinalDelay:
    DEC DE
    LD A, D
    OR E
    JR NZ, FinalDelay

    EI                             ; Разрешаем системные прерывания обратно
    RET                            ; Возвращаемся обратно в интерфейс .browse

; --- Область данных плагина ---
FileHandle: DB 0
DataBuffer: DS BUF_SIZE            ; Выделяем 1024 байта памяти под буфер

; Команда компилятору для сборки готового бинарника
    SAVEBIN "playmp3.com", Start, $ - Start

