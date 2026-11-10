#!/usr/bin/env python3
# Coefficients of the 64-tap image filter in audio_img_lpf.v (Kaiser-windowed sinc at the 109.375 kHz DAC
# rate), which removes the images of the 37.5 kHz (GS) and 44.1 kHz (MP3) sample rates from those sources.
# Prints the first half of the symmetric filter in Q18 and its response.
import math

FS = 109375.0
FC = 21000.0
TAPS = 64
BETA = 5.65
Q = 18


def i0(x):
    s = t = 1.0
    k = 1
    while t > 1e-14 * s:
        t *= (x / (2 * k)) ** 2
        s += t
        k += 1
    return s


def design(fc=FC, beta=BETA, taps=TAPS):
    m = (taps - 1) / 2
    h = []
    for n in range(taps):
        d = n - m
        w = i0(beta * math.sqrt(1 - (d / m) ** 2)) / i0(beta)
        h.append(math.sin(2 * math.pi * fc / FS * d) / (math.pi * d) * w)
    g = sum(h)
    c = [round(x / g * (1 << Q)) for x in h[:taps // 2]]
    c[-1] += ((1 << Q) - 2 * sum(c)) // 2    # DC gain must be exactly 1
    return c


def resp_db(c, f):
    full = c + c[::-1]
    re = sum(x * math.cos(2 * math.pi * f / FS * n) for n, x in enumerate(full))
    im = sum(x * math.sin(2 * math.pi * f / FS * n) for n, x in enumerate(full))
    return 20 * math.log10(max(math.hypot(re, im), 1e-3) / (1 << Q))


if __name__ == '__main__':
    c = design()
    print('sum*2 =', 2 * sum(c), 'peak =', max(c))
    for f in (1000, 10000, 15000, 18000, 19000, 20000, 21500, 24000, 25000, 30000):
        print('%6d Hz: %8.3f dB' % (f, resp_db(c, f)))
    print('worst above 24.4 kHz: %.1f dB' % max(resp_db(c, f * 50.0) for f in range(488, 1094)))
    for i, x in enumerate(c):
        print("            5'd%-2d: coef <= %d;" % (i, x))
