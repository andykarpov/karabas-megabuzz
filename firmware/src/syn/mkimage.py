#!/usr/bin/env python3
"""Собирает полный raw-образ SPI-флешки для внешнего программатора.

    mkimage.py -o out.bin [-s SIZE] OFFSET:FILE [OFFSET:FILE ...]

Пустое место заполняется 0xFF (стертая флешка). Скрипт проверяет, что
куски не перекрываются и влезают в SIZE (по умолчанию 0x200000, 25Q16).
"""
import argparse
import sys


def main():
    p = argparse.ArgumentParser(description="Build a raw SPI flash image")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("-s", "--size", default="0x200000",
                   help="image size in bytes (default 0x200000 = 2 MB)")
    p.add_argument("parts", nargs="+", metavar="OFFSET:FILE")
    a = p.parse_args()

    size = int(a.size, 0)
    img = bytearray(b"\xff" * size)
    used = []

    for part in a.parts:
        off_s, sep, path = part.partition(":")
        if not sep or not path:
            sys.exit(f"mkimage: bad part '{part}', expected OFFSET:FILE")
        off = int(off_s, 0)
        with open(path, "rb") as f:
            data = f.read()
        end = off + len(data)
        if end > size:
            sys.exit(f"mkimage: {path} (0x{off:06X}..0x{end:06X}) "
                     f"does not fit into 0x{size:X} bytes")
        for o_off, o_end, o_path in used:
            if off < o_end and o_off < end:
                sys.exit(f"mkimage: {path} (0x{off:06X}..0x{end:06X}) overlaps "
                         f"{o_path} (0x{o_off:06X}..0x{o_end:06X})")
        img[off:end] = data
        used.append((off, end, path))

    with open(a.output, "wb") as f:
        f.write(img)

    print(f"{a.output}: 0x{size:X} bytes")
    for off, end, path in sorted(used):
        print(f"  0x{off:06X}..0x{end - 1:06X}  {path}")


if __name__ == "__main__":
    main()
