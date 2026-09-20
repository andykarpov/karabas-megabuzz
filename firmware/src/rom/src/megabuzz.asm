; =============================================================================
; Karabas MegaBuzz Configurator ROM
; hardware driver (ports)
; =============================================================================

    macro MB_SetCfgMode
    push bc
    ld a, MegaBuzz.REG_CTRL : ld bc, MegaBuzz.PORT_ZXUNO_REG : out (c), a
    pop bc
    endm

    macro MB_SetRomMode
    push bc
    ld a, MegaBuzz.REG_ROMBANK : ld bc, MegaBuzz.PORT_ZXUNO_REG : out (c), a
    pop bc
    endm

    macro MB_SetCtrlMode
    push bc
    ld a, MegaBuzz.REG_CTRL : ld bc, MegaBuzz.PORT_ZXUNO_REG : out (c), a
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
    ld bc, MegaBuzz.PORT_ZXUNO_DATA : in a, (c)
    pop bc
    endm

    MODULE MegaBuzz

PORT_ZXUNO_REG   EQU #FC3B     ; ZXUNO control port
PORT_ZXUNO_DATA  EQU #FD3B     ; ZXUNO data port
REG_CFG          EQU #F7       ; cfg byte r/w
REG_ROMBANK      EQU #F8       ; ROM bank w (bit 0 = 0 - zx rom, 1 = cfg rom)
REG_CTRL         EQU #F9       ; Control register w (bit 0 = 1 - reset trigger), r (bit 0 = 1 - flash busy)

;; Read current config
;; OUT: A = cfg byte
ReadConfig:
    MB_SetCfgMode
    MB_Read
    RET

;; Write config and switch to main ROM
;; IN: A = cfg byte
ApplyConfig:
    MB_SetCfgMode
    MB_SendA
    MB_SetCtrlMode
.wait_flash:
    MB_Read
    bit 0, a
    jr nz, .wait_flash
    ; continue to cancel action

;; Cancel - switch back a normal ROM + soft reset trigger
Cancel:
    MB_SetRomMode
    MB_Send 0 ; switch to zx rom
    MB_SetCtrlMode
    MB_Send 1 ; send a reset trigger pulse
    MB_Send 0

.Infinite:
    JR .Infinite

    ENDMODULE

