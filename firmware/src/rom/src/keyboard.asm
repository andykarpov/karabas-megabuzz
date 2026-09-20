        MODULE Keyboard

; Return codes
KEY_NONE   EQU 0
KEY_UP     EQU 1
KEY_DOWN   EQU 2
KEY_SELECT EQU 3

;; Scan keyboard
;; A = action code
Scan:
        JR .ScanKeyboard
        ; Poll kempston joystick (0x1F)
        IN A, (0x1F)
        AND A                   ; If joy is not connected or not pressed - return 0
        JR Z, .ScanKeyboard

        BIT 3, A                ; UP
        JR NZ, .KeyUp
        
        BIT 2, A                ; DOWN
        JR NZ, .KeyDown
        
        BIT 4, A                ; FIRE
        JR NZ, .KeySelect

        ; Poll keyboard (Q/A, Cursor, Space/Enter)
.ScanKeyboard:
        ; Q (port 0xFBFE, bit 0)
        LD BC, 0xFBFE
        IN A, (C)
        BIT 0, A
        JR Z, .KeyUp

        ; A -> (port 0xFDFE, bit 0)
        LD BC, 0xFDFE
        IN A, (C)
        BIT 0, A
        JR Z, .KeyDown

        ; Cursor (Requires pressed Caps Shift)
        LD BC, 0xFEFE
        IN A, (C)
        BIT 0, A
        JR NZ, .NoCursor        ; If Caps Shift is not pressed, skipping cursor checks

        ; digits (port 0xEFFE)
        LD BC, 0xEFFE
        IN A, (C)
        
        BIT 3, A                ; UP
        JR Z, .KeyUp
        
        BIT 4, A                ; DOWN
        JR Z, .KeyDown

.NoCursor:
        ; Space (port 0x7FFE, bit 0)
        LD BC, 0x7FFE
        IN A, (C)
        BIT 0, A
        JR Z, .KeySelect

        ; Enter (port 0xBFFE, bit 0)
        LD BC, 0xBFFE
        IN A, (C)
        BIT 0, A
        JR Z, .KeySelect

        ; If nothing pressed
        XOR A                   ; KEY_NONE
        RET

.KeyUp:     LD A, KEY_UP : RET
.KeyDown:   LD A, KEY_DOWN : RET
.KeySelect: LD A, KEY_SELECT : RET

        ENDMODULE

