#!/usr/bin/env python3
"""Fast-boot patch of the General Sound ROM 1.05b: gs105b.rom -> gs105b_mb.rom

At start the ROM finds the RAM pages and for each one does a byte test at
#FFFF, fills the whole 32 KB page with a pattern, reads it back, then clears
the page. With 2 MB (63 pages) and the CPU at 14 MHz that takes about 9 s,
and NeoGS software resets the GS through #33 and waits for it each time.

The patch jumps from the start of the pattern fill (#01F9: EXX) straight to the
page clear (#023D), so the page is still detected, byte-tested, counted and
cleared, but not pattern-tested: about 0.8 s for 2 MB.

    01F9  D9        exx              (kept: the clear runs in the alternate set)
    01FA  21 00 80  ld hl,#8000  ->  C3 3D 02  jp #023D

The bytes from #01FD to #023C are no longer executed; the word at #01FE is
changed so that the 16-bit word sum of the ROM stays the same.

Usage: gs_rom_patch.py [in.rom] [out.rom]
"""
import sys

PATCH = {0x1FA: (0x21, 0xC3), 0x1FB: (0x00, 0x3D), 0x1FC: (0x80, 0x02)}
FILL = 0x1FE    # even address inside the skipped code, used to keep the word sum


def word_sum(d):
    return sum(d[i] | d[i + 1] << 8 for i in range(0, len(d), 2)) & 0xFFFF


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "gs105b.rom"
    dst = sys.argv[2] if len(sys.argv) > 2 else "gs105b_mb.rom"
    d = bytearray(open(src, "rb").read())
    if len(d) != 32768 or d[0x1F9] != 0xD9 or d[0x23D:0x240] != b"\x21\x00\x00":
        sys.exit(f"{src}: not the GS ROM 1.05b this patch is for")
    before = word_sum(d)
    for a, (old, new) in PATCH.items():
        if d[a] != old:
            sys.exit(f"{src}: #{a:04X} is #{d[a]:02X}, expected #{old:02X}")
        d[a] = new
    w = (d[FILL] | d[FILL + 1] << 8) - (word_sum(d) - before)
    d[FILL], d[FILL + 1] = w & 0xFF, (w >> 8) & 0xFF
    assert word_sum(d) == before
    open(dst, "wb").write(d)
    print(f"{dst}: written")


if __name__ == "__main__":
    main()
