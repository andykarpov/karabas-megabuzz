        MODULE MegaBuzz

; todo - rework to zxuno ports!
PORT_DATA       EQU 0x7F    ; CFG port
PORT_ROM_SWITCH EQU 0xBF    ; ROM select port
ROM_SWITCH_VAL  EQU 0x01    ; ROM select port bit

;; Read current config
ReadConfig:
        IN A, (PORT_DATA)
        RET

;; Write config and switch to main ROM
ApplyConfig:
        OUT (PORT_DATA), A

;; Cancel - switch back a normal ROM
Cancel:
        LD A, ROM_SWITCH_VAL
        OUT (PORT_ROM_SWITCH), A
        ; TODO: soft reset ?

.Infinite:
        JR .Infinite

        ENDMODULE

