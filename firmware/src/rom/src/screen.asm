; =============================================================================
; Karabas MegaBuzz Configurator ROM
; screen routines
; =============================================================================

        MODULE Screen

; Attr masks
ATTR_DEFAULT    EQU %00000111 ; Black paper, white pixels
ATTR_HIGHLIGHT  EQU %00001111 ; Blue paper, white pixels
ATTR_BUTTON     EQU %00000000 | (7 << 3) | 0 ; Bright=0, Flash=0, Paper=7 (grey), Ink=0 (black)

;; Clear the screen pixels
Clear:
        ; black border
        XOR A : OUT (0xFE), A

        LD HL, 0x4000
        LD DE, 0x4001
        LD BC, 0x17FF
        LD (HL), 0
        LDIR
        RET

;; Reset attributes to defaults
ResetAttributes:
        LD HL, 0x5800
        LD DE, 0x5801
        LD BC, 0x02FF
        LD (HL), ATTR_DEFAULT
        LDIR
        RET

;; Colorize a part of row with blue bg / white pixels
;; B = Row (0-23), C = Column (0-31), D = Length
ColorizeHighlight:
        PUSH DE
        CALL ColorizeRow.CalcAddress
        POP DE
        LD A, ATTR_HIGHLIGHT
        JR ColorizeRow.Fill

;; Colorize a part of row with black bg / white pixels
;; B = Row, C = Column, D = Length
ColorizeNormal:
        PUSH DE
        CALL ColorizeRow.CalcAddress
        POP DE
        LD A, ATTR_DEFAULT
        JR ColorizeRow.Fill

; Colorize a button with grey bg / black pixels
;; B = Row, C = Column, D = Length
ColorizeButtonDefault:
        PUSH DE
        CALL ColorizeRow.CalcAddress
        POP DE
        LD A, ATTR_BUTTON
        JR ColorizeRow.Fill

ColorizeRow:
.Fill:
        LD (HL), A
        INC HL
        DEC D
        JR NZ, .Fill
        RET

.CalcAddress:
        LD H, 0
        LD L, B
        ADD HL, HL          ; * 2
        ADD HL, HL          ; * 4
        ADD HL, HL          ; * 8
        ADD HL, HL          ; * 16
        ADD HL, HL          ; * 32
        LD A, C
        ADD A, L
        LD L, A
        LD A, H
        ADC A, 0x58         ; + 0x5800
        LD H, A             ; HL = Address in attributes
        RET

;; Print string (0-terminated)
;; DE = String, B = Row (0-23), C = Column (0-31)
PrintString:
        LD A, (DE)
        AND A
        RET Z               
        PUSH DE
        PUSH BC
        CALL PrintChar
        POP BC
        INC C               
        POP DE
        INC DE
        JR PrintString

;; Print a single character
PrintChar:
        PUSH AF
        ; Calc pixel address of ZX screen
        LD A, B
        AND 0x18            
        OR 0x40             
        LD H, A
        LD A, B
        AND 0x07            
        RRCA
        RRCA
        RRCA                
        OR C                
        LD L, A             

        POP AF
        SUB 32              ; Font (started from space (code 32))
        LD E, A
        LD D, 0
        EX DE, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        EX DE, HL           
        LD IX, FontData
        ADD IX, DE          

        LD B, 8
.LineLoop:
        LD A, (IX+0)
        LD (HL), A          
        INC H               
        INC IX
        DJNZ .LineLoop
        RET

;; Print HEX byte
;; A = byte to print, B = Row (0..23), C = Column (0..31)
PrintHexByte:
        LD (TMP_HEX_COORD), BC
        LD (TMP_HEX_BYTE), A

        ; print high semi-byte
        RRCA
        RRCA
        RRCA
        RRCA
        CALL .NumToChar
        
        ; Restore coords for the first print
        LD BC, (TMP_HEX_COORD)
        CALL PrintChar             ; print first semibyte

        ; print low semi-byte
        LD BC, (TMP_HEX_COORD)
        INC C                      ; shift column
        LD (TMP_HEX_COORD), BC

        LD A, (TMP_HEX_BYTE)
        CALL .NumToChar
        
        LD BC, (TMP_HEX_COORD)
        CALL PrintChar
        RET

.NumToChar:
        AND 0x0F
        CP 10
        JR C, .IsDigit
        ADD A, 7            ; letters offset A..F
.IsDigit:
        ADD A, 48           ; digits offset 0..9 (ASCII code '0')
        RET

TMP_HEX_COORD   EQU 0x5C07  ; 2 bytes to store temp coords BC
TMP_HEX_BYTE    EQU 0x5C09  ; 1 byte to store source cfg byte

        ALIGN 8
FontData:
    INCBIN "font.bin"

        ENDMODULE

