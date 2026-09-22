#!/usr/bin/env python3
"""Bit-exact model of rtl/lowpass.sv: two one-pole sections, y += a * (x - y),
a = 3/8 (d>>2 + d>>3) for mode 1 Light, 3/16 (d>>3 + d>>4) for modes 2 and 3
Heavy, 8 fractional bits; mode 0 off.  The sections run on every sample
whatever the mode, as the RTL's do."""


def run(x, mode):
    sh = (2, 3) if mode == 1 else (3, 4)
    y1 = y2 = 0
    out = []
    for s in x:
        d = (s << 8) - y1
        y1 += (d >> sh[0]) + (d >> sh[1])
        d = y1 - y2
        y2 += (d >> sh[0]) + (d >> sh[1])
        out.append(s if mode == 0 else y2 >> 8)
    return out
