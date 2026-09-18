    module String
; HL - asciiZ 
; DE - asciiZ
; Z - equals, NZ - not equals
; CaSe INSenSITIve !!!!
strcmp:
    ld a, (hl) : and #df : ld b, a
    ld a, (de) : and #df ;; Case insense
    cp b : ret nz
    and a  : ret z
    inc hl
    inc de
    jr strcmp

    endmodule