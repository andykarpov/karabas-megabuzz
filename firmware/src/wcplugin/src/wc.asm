;; Wild Commander key helpers (constants and WCALL are in wcdefs.asm)

;; Keys: NZ if the key is pressed
key_esc:    WCALL WCF_ESC  : ret
key_space:  WCALL WCF_SPKE : ret
key_enter:  WCALL WCF_ENKE : ret
key_bspc:   WCALL WCF_BSPC : ret
key_left:   WCALL WCF_LFFF : ret
key_right:  WCALL WCF_RGGG : ret
key_up:     WCALL WCF_UPPP : ret
key_down:   WCALL WCF_DWWW : ret

;; OUT: NZ and A = char (lower case latin), or Z if none
key_char:
    ld a,1
    ex af,af'
    WCALL WCF_KBSCN
    ret
