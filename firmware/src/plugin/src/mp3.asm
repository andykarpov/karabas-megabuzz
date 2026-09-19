	OPT --dirbol			; enable directives processing
					; from the beginning of line

DEVICE ZXSPECTRUM48

PLUGIN_ORG  = #8000
PLUGIN_SIZE = #2000

RESULT_OK   = 1
PLUGIN_NAVIGATE = 8
RESULT_ERR  = 128

PLUGIN_NAVIGATE_NEXT  = 1
PLUGIN_FLAGS1_COPY_SETTINGS = 1
PLUGIN_SETTING_MAX = 14
PLUGIN_STATUS_SCREEN_ADDR EQU $50e0 + 24	; x, 20, y  EQU  bottom line

    org PLUGIN_ORG
    jr _plugin_start

_plugin_info:

	defb "BP"				; id
	defb 0					; spare
	defb 0					; spare
	defb PLUGIN_FLAGS1_COPY_SETTINGS	; flags
	defb 0					; flags2  

_plugin_user_data:

	defs(PLUGIN_SETTING_MAX)		; reserve space for settings copy

_plugin_id_string:

	defb ".MP3 file plugin v0.5 for MegaBuzz - andykarpov", $0

;; Entry point
; hl - the 8.3 filename of the selected item from the browser.
; bc - address of the browser's parameter block.
; de - address of the config buffer.
_plugin_start:
    ld b, Dos.FMODE_READ
    call Dos.fopen : jp c, err
    ld (fp), a
    call MegaBuzz.init

	ld hl, _plugin_status_playing
	call _set_status_icon

.loadLoop
    ld a, (fp)
    ld hl, buffer
    ld bc, buffer_size 
    call Dos.fread ; read 4kb buffer
    ld a, b : or c : jp z, .exit_next

    srl b : rr c
    srl b : rr c
    srl b : rr c
    srl b : rr c
    srl b : rr c
    ; now C = count of 32 byte blocks (1..128)
    
    ld hl, buffer

.sendBlocksLoop
    ld a, c : or a : jr z, .loadLoop

.kbd_poll:
    ; Q
    ld a, #FB : in a, (#FE) : bit 0, a
    jr z, .exit

    ; SPACE
    ld a, #7F : in a, (#FE) : bit 0, a
    jr z, .exit_next

.get_free_blocks:
    push bc
    push hl
    call MegaBuzz.getFreeBlocks ; A = free blocks
    pop hl
    pop bc

    or a : jr z, .sendBlocksLoop

    cp c
    jr c, .use_available
    ld a, c
.use_available:
    ; A = count of blocks to send on this interation
    ld b, a                 ; Move to B for djnz loop
    
    ; Remaining blocks count in C
    sub c
    neg
    ld c, a

.blockLoop
    push bc
    call MegaBuzz.send32Bytes
    pop bc
    djnz .blockLoop

    jr .sendBlocksLoop

.exit
    ld a, (fp) : call Dos.fclose
    call MegaBuzz.finish
    ld hl, 0
    ld bc, 0 
    ld a, RESULT_OK 
    ret

.exit_next:
    ld a, (fp) : call Dos.fclose
    call MegaBuzz.finish
	ld hl, _plugin_status_seek_next
	call _set_status_icon
    ld bc, PLUGIN_NAVIGATE_NEXT ; bc = 1
    ld a, RESULT_OK | PLUGIN_NAVIGATE; a = 9
    ret

_set_status_icon:

	ld a, h
	or l
	ret z

					; hl points to status graphic
	ld de, PLUGIN_STATUS_SCREEN_ADDR
	ld b, 8

_set_status_icon_loop:

	ld a, (hl)
	ld (de), a
	inc hl
	inc d
	djnz _set_status_icon_loop
	ret

err:
    ld a, RESULT_ERR
    ret

    include "esxdos.asm"
    include "megabuzz.asm"

fp          db 0
buffer      ds 4096
buffer_size equ 4096

_plugin_status_playing:

	defb %00000000
	defb %00100000
	defb %00110000
	defb %00111000
	defb %00110000
	defb %00100000
	defb %00000000
	defb %00000000

_plugin_status_seek_next:

	defb %00000000
	defb %01000100
	defb %01100110
	defb %01110111
	defb %01100110
	defb %01000100
	defb %00000000
	defb %00000000

    savebin "mp3", PLUGIN_ORG, $-PLUGIN_ORG

