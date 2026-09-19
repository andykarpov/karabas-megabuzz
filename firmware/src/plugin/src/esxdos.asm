        MODULE Dos
; API methods
ESX_GETSETDRV = #89
ESX_FOPEN = #9A
ESX_FCLOSE = #9B
ESX_FREAD = #9D

; File modes
FMODE_READ = #01

    MACRO esxCall func
    rst #8 : db func
    ENDM


; Returns: 
;  A - current drive
getDefaultDrive:
    ld a, 0 : esxCall ESX_GETSETDRV
    ret

; Opens file on default drive
; B - File mode
; HL - File name
; Returns:
;  A - file stream id
fopen:
    push bc : push hl 
    call getDefaultDrive
    pop ix : pop bc
    esxCall ESX_FOPEN
    ret

; A - file stream id
fclose:
    esxCall ESX_FCLOSE
    ret

; A - file stream id
; BC - length
; HL - buffer
; Returns
;  BC - length(how much was actually read) 
fread:
    push hl : pop ix
    esxCall ESX_FREAD
    ret

    ENDMODULE