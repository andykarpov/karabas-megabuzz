#!/usr/bin/env python3
# Simulates audio_img_lpf.v with iverilog and compares every output with a bit-exact model, then checks the
# response. Run from this directory: ./audio_img_tb.py   (needs iverilog; only standard Python)
import math
import subprocess
import sys

import audio_img_gen

FS = audio_img_gen.FS
SEG = 3000


def tone(f, a, n):
    return int(round(a * math.sin(2 * math.pi * f * n / FS)))


SEGMENTS = [
    ('DC', lambda n: 12345, lambda n: -23456),
    ('1 kHz', lambda n: tone(1000, 20000, n), lambda n: tone(1500, 10000, n)),
    ('15 kHz', lambda n: tone(15000, 20000, n), lambda n: tone(10000, 10000, n)),
    ('24.4 kHz', lambda n: tone(24400, 20000, n), lambda n: tone(37500, 20000, n)),
    ('square', lambda n: 32767 if int(n * 4000 / FS) % 2 == 0 else -32768, lambda n: 0),
]


def amplitude(y, f):
    n = len(y)
    w = [0.5 - 0.5 * math.cos(2 * math.pi * i / n) for i in range(n)]
    re = sum(a * v * math.cos(2 * math.pi * f * i / FS) for i, (a, v) in enumerate(zip(w, y)))
    im = sum(a * v * math.sin(2 * math.pi * f * i / FS) for i, (a, v) in enumerate(zip(w, y)))
    return 2 * math.hypot(re, im) / sum(w)


def model(x, h, newest):
    acc = sum(c * x[newest - i] for i, c in enumerate(h))
    return max(-32768, min(32767, acc >> audio_img_gen.Q))


def s16(v):
    v = int(v, 16)
    return v - 65536 if v & 0x8000 else v


def main():
    half = audio_img_gen.design()
    h = half + half[::-1]
    xl, xr = [], []
    for _, fl, fr in SEGMENTS:
        for n in range(SEG):
            xl.append(fl(n))
            xr.append(fr(n))
    with open('audio_img_vec.hex', 'w') as f:
        for l, r in zip(xl, xr):
            f.write('%04x\n%04x\n' % (l & 0xFFFF, r & 0xFFFF))
    subprocess.check_call(['iverilog', '-g2005', '-P', 'audio_img_tb.N=%d' % len(xl), '-o', 'audio_img_tb.vvp',
                           'audio_img_tb.v', 'audio_img_lpf.v'])
    subprocess.check_call(['vvp', 'audio_img_tb.vvp'], stdout=subprocess.DEVNULL)
    with open('audio_img_out.txt') as f:
        rows = [ln.split() for ln in f]
    first = max([i for i, r in enumerate(rows[:80]) if 'x' in ''.join(r)] + [-1]) + 1
    yl = [None if i < first else s16(r[0]) for i, r in enumerate(rows)]
    yr = [None if i < first else s16(r[1]) for i, r in enumerate(rows)]
    probe = SEG + 500
    best = None
    for lag in range(-4, 8):
        if all(yl[i] is not None and yl[i] == model(xl, h, i - lag) for i in range(probe, probe + 40)):
            best = lag
            break
    if best is None:
        print('no alignment found')
        sys.exit(1)
    n = bad = 0
    for i in range(first + len(h) + abs(best) + 1, len(yl)):
        if i - best >= len(xl):
            break
        n += 1
        if yl[i] != model(xl, h, i - best) or yr[i] != model(xr, h, i - best):
            bad += 1
            if bad < 6:
                print('mismatch at', i, yl[i], model(xl, h, i - best), yr[i], model(xr, h, i - best))
    print('compared', n, 'output pairs, mismatches', bad)
    seg = lambda k: k * SEG + 400
    checks = [
        ('DC gain', abs(yl[seg(0) + 400] - 12345) <= 1 and abs(yr[seg(0) + 400] + 23456) <= 1),
        ('1 kHz', abs(amplitude(yl[seg(1):seg(1) + 2000], 1000) - 20000) < 150),
        ('15 kHz', abs(amplitude(yl[seg(2):seg(2) + 2000], 15000) - 20000) < 150),
        ('24.4 kHz at -60 dB', amplitude(yl[seg(3):seg(3) + 2000], 24400) < 25),
        ('37.5 kHz at -60 dB', amplitude(yr[seg(3):seg(3) + 2000], 37500) < 25),
        ('square wave clips', max(yl[seg(4):seg(4) + 2000]) == 32767 and min(yl[seg(4):seg(4) + 2000]) == -32768),
    ]
    for name, ok in checks:
        print('%-20s %s' % (name, 'ok' if ok else 'FAIL'))
    sys.exit(0 if bad == 0 and all(ok for _, ok in checks) else 1)


if __name__ == '__main__':
    main()
