; =============================================================================
; Karabas MegaBuzz Configurator ROM
; hardware driver (ports)
; =============================================================================

    MODULE MegaBuzz

PORT_ZXUNO_REG   EQU #FC3B     ; ZXUNO control port
PORT_ZXUNO_DATA  EQU #FD3B     ; ZXUNO data port
REG_BOARD        EQU #F4       ; Board id r: bits 2:0 revision, bit 3 XC6SLX25, bit 4 neorv32, bit 5 VS1053 chip
REG_CFG          EQU #F7       ; cfg byte r/w
REG_ROMBANK      EQU #F8       ; ROM bank w (bit 0 = 0 - zx rom, 1 = cfg rom)
REG_CTRL         EQU #F9       ; Control register w (bit 0 = 1 - reset trigger), r (bit 0 = 1 - flash busy)
REG_CFGA         EQU #FA       ; CFG byte address

BOARD_SLX25      EQU #08       ; REG_BOARD bit 3

;; Select a ZXUNO register
;; IN: A = register; OUT: BC = data port
SelectReg:
    LD BC, PORT_ZXUNO_REG : OUT (C), A
    LD B, high PORT_ZXUNO_DATA
    RET

;; Wait for flash ready; several seconds at most, a sector erase is the longest step
;; OUT: carry set = timed out
WaitFlash:
    LD A, REG_CTRL : CALL SelectReg
    LD HL, 0 : LD D, 8
.wait_flash:
    IN A, (C)
    RRA : RET NC                ; bit 0 = 0: ready, carry clear
    DEC HL : LD A, H : OR L : JR NZ, .wait_flash
    DEC D : JR NZ, .wait_flash
    SCF
    RET

;; Select config byte A for REG_CFG
;; IN: A = address; OUT: BC = data port
SelectConfig:
    LD E, A
    LD A, REG_CFGA : CALL SelectReg
    OUT (C), E
    LD A, REG_CFG : JR SelectReg

;; Read current config byte 1 / 2
;; OUT: A = cfg byte
ReadConfig:
    XOR A
.read:
    CALL SelectConfig
    IN A, (C)
    RET

ReadConfig2:
    LD A, 1 : JR ReadConfig.read

;; Write config byte 1 / 2 (byte 2 starts the save to flash), wait for the flash
;; IN: A = cfg byte; OUT: carry set = timed out
ApplyConfig:
    LD D, A : XOR A
.write:
    CALL SelectConfig
    OUT (C), D
    JR WaitFlash

ApplyConfig2:
    LD D, A : LD A, 1 : JR ApplyConfig.write

;; Read the board id
;; OUT: A = REG_BOARD value
ReadBoard:
    LD A, REG_BOARD : CALL SelectReg
    IN A, (C)
    RET

    ENDMODULE
