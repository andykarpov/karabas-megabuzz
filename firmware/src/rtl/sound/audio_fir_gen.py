#!/usr/bin/env python3
# Coefficients of the 64-tap decimator in audio_fir_decim.v (Kaiser-windowed sinc, input 875 kHz, x8).
# Prints the first half of the symmetric filter in Q19 and its response.
import math

FS = 875000.0
FC = 54687.5     # half of the output rate
TAPS = 64
BETA = 7.857     # about 80 dB
Q = 19


def i0(x):
    s = t = 1.0
    k = 1
    while t > 1e-14 * s:
        t *= (x / (2 * k)) ** 2
        s += t
        k += 1
    return s


def design():
    m = (TAPS - 1) / 2
    h = []
    for n in range(TAPS):
        d = n - m
        w = i0(BETA * math.sqrt(1 - (d / m) ** 2)) / i0(BETA)
        h.append(math.sin(2 * math.pi * FC / FS * d) / (math.pi * d) * w)
    g = sum(h)
    c = [round(x / g * (1 << Q)) for x in h[:TAPS // 2]]
    c[-1] += ((1 << Q) - 2 * sum(c)) // 2   # DC gain must be exactly 1
    return c


def resp_db(c, f):
    full = c + c[::-1]
    re = sum(x * math.cos(2 * math.pi * f / FS * n) for n, x in enumerate(full))
    im = sum(x * math.sin(2 * math.pi * f / FS * n) for n, x in enumerate(full))
    return 20 * math.log10(max(math.hypot(re, im), 1e-3) / (1 << Q))


if __name__ == '__main__':
    c = design()
    print('sum*2 =', 2 * sum(c), 'peak =', max(c))
    for f in (1000, 10000, 15000, 18000, 20000):
        print('%6d Hz: %.3f dB' % (f, resp_db(c, f)))
    worst = max(resp_db(c, f * 100.0) for f in range(894, 4375))
    print('worst above 89.4 kHz: %.1f dB' % worst)
    for i, x in enumerate(c):
        print("            5'd%-2d: coef <= %d;" % (i, x))
