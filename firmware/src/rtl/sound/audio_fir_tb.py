#!/usr/bin/env python3
# Simulates audio_fir_decim.v with iverilog and compares every output with a bit-exact model.
# Run from this directory: ./audio_fir_tb.py   (needs iverilog; only standard Python)
import math
import subprocess
import sys

import audio_fir_gen

FS = 875000.0
SEG = 4000                  # input samples per test signal
OUT_FS = FS / 8


def tone(f, a, n):
    return int(round(a * math.sin(2 * math.pi * f * n / FS)))


SEGMENTS = [
    ('DC', lambda n: 12345, lambda n: -23456),
    ('1 kHz', lambda n: tone(1000, 20000, n), lambda n: tone(1500, 10000, n)),
    ('18 kHz', lambda n: tone(18000, 20000, n), lambda n: tone(15000, 10000, n)),
    ('95 kHz', lambda n: tone(95000, 20000, n), lambda n: tone(120000, 20000, n)),
    ('square', lambda n: 32767 if int(n * 4000 / FS) % 2 == 0 else -32768, lambda n: 0),
]


def amplitude(y, f):
    n = len(y)
    w = [0.5 - 0.5 * math.cos(2 * math.pi * i / n) for i in range(n)]    # Hann, the tone is not periodic in y
    re = sum(a * v * math.cos(2 * math.pi * f * i / OUT_FS) for i, (a, v) in enumerate(zip(w, y)))
    im = sum(a * v * math.sin(2 * math.pi * f * i / OUT_FS) for i, (a, v) in enumerate(zip(w, y)))
    return 2 * math.hypot(re, im) / sum(w)


def model(x, h, newest):
    acc = sum(c * x[newest - i] for i, c in enumerate(h))
    return max(-32768, min(32767, acc >> 19))


def s16(v):
    v = int(v, 16)
    return v - 65536 if v & 0x8000 else v


def main():
    half = audio_fir_gen.design()
    h = half + half[::-1]
    xl, xr = [], []
    for _, fl, fr in SEGMENTS:
        for n in range(SEG):
            xl.append(fl(n))
            xr.append(fr(n))
    with open('audio_fir_vec.hex', 'w') as f:
        for l, r in zip(xl, xr):
            f.write('%04x\n%04x\n' % (l & 0xFFFF, r & 0xFFFF))
    subprocess.check_call(['iverilog', '-g2005', '-P', 'audio_fir_tb.N=%d' % len(xl), '-o', 'audio_fir_tb.vvp',
                           'audio_fir_tb.v', 'audio_fir_decim.v'])
    subprocess.check_call(['vvp', 'audio_fir_tb.vvp'], stdout=subprocess.DEVNULL)

    with open('audio_fir_out.txt') as f:
        rows = [ln.split() for ln in f]
    # the delay line is undefined until it has been filled once
    first = max(i for i, r in enumerate(rows[:64]) if 'x' in r[0] or 'x' in r[1]) + 1 if any('x' in ''.join(r) for r in rows[:64]) else 0
    yl = [None if i < first else s16(r[0]) for i, r in enumerate(rows)]
    yr = [None if i < first else s16(r[1]) for i, r in enumerate(rows)]

    # the input/output alignment is fixed but not obvious: find it on a tone, then every sample has to match
    probe = SEG // 8 + 100
    for lag in range(-16, 32):
        if all(yl[k] == model(xl, h, 8 * k + lag) for k in range(probe, probe + 30)):
            break
    else:
        print('FAIL: no alignment matches the model')
        return 1

    bad = 0
    total = 0
    for k in range(first, len(yl)):
        newest = 8 * k + lag
        if newest < 64 or newest >= len(xl):
            continue
        total += 1
        bad += (yl[k] != model(xl, h, newest)) + (yr[k] != model(xr, h, newest))
    print('compared %d output pairs from #%d, lag %d: %d mismatches' % (total, first, lag, bad))

    seg_out = SEG // 8
    margin = 16 + abs(lag) // 8
    def seg(y, i):
        return y[i * seg_out + margin: (i + 1) * seg_out - margin]

    print('DC: L %d (in 12345), R %d (in -23456)' % (seg(yl, 0)[50], seg(yr, 0)[50]))
    print('1 kHz gain: %.3f dB' % (20 * math.log10(amplitude(seg(yl, 1), 1000) / 20000)))
    print('18 kHz gain: %.3f dB' % (20 * math.log10(amplitude(seg(yl, 2), 18000) / 20000)))
    print('95 kHz: peak after the filter %d of 20000' % max(abs(v) for v in seg(yl, 3)))
    print('120 kHz: peak after the filter %d of 20000' % max(abs(v) for v in seg(yr, 3)))
    print('square: min %d max %d' % (min(seg(yl, 4)), max(seg(yl, 4))))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
