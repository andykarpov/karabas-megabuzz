; A - char
putC:
    rst #10
    ret

; HL - string
putStringZ:
    ld a, (hl)
    and a
    ret z
    push hl
    call putC
    pop hl
    inc hl
    jr putStringZ

    macro print pointer
    ld hl, pointer : call putStringZ
    endm