;; Wild Commander plugin API (plugin system #10, WC 1.09+)
;;
;; Every call goes through CALL #6006 with the function number in A.
;; WC clobbers AF, BC, DE, HL, IX and keeps IY, AF', BC', DE', HL', SP.
;; Buffers and strings passed to WC must live in #8000-#BFFF.

WC_API          equ #6006
WC_TMN          equ #6009       ; word, incremented on every INT (50 Hz)
WC_HEI          equ #600E       ; text screen height: 25 / 30 / 36

WCF_PRWOW       equ #01         ; IX = window: draw it
WCF_RRESB       equ #02         ; IX = window: erase it, restore what was under it
WCF_PRSRW       equ #03         ; IX = window, HL = text, D = y, E = x, BC = length
WCF_PRIAT       equ #04         ; A' = colour for the span of the last PRSRW
WCF_TURBOPL     equ #0E         ; B = 0: C = CPU clock (0 = 3.5, 1 = 7, 2 = 14 MHz)
WCF_GEDPL       equ #0F         ; restore palette, offsets and the text mode
WCF_SPKE        equ #10         ; key tests: NZ = pressed (with autorepeat)
WCF_UPPP        equ #11
WCF_DWWW        equ #12
WCF_LFFF        equ #13
WCF_RGGG        equ #14
WCF_ENKE        equ #16
WCF_ESC         equ #17
WCF_BSPC        equ #18
WCF_KBSCN       equ #2A         ; A' = 1: NZ, A = char of the pressed key
WCF_USPO        equ #2E         ; wait until all keys are released
WCF_LOAD512     equ #30         ; HL = buffer, B = sectors: read the file on
WCF_GIPAGPL     equ #32         ; rewind the file to its start
WCF_LOADNONE    equ #3D         ; B = sectors: skip them without reading

; exit codes in A
WCX_ESC         equ 0
WCX_NOTMINE     equ 1
WCX_NEXT        equ 2
WCX_PREV        equ 4

    macro WCALL fn
        ld a,fn
        call WC_API
    endm
