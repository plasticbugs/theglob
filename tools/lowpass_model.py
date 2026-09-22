#!/usr/bin/env python3
"""Bit-exact model of rtl/lowpass.sv: two one-pole sections, y += (x - y) >> k,
8 fractional bits; mode 0 off, 1 light (k=1), 2 and 3 medium (k=2).  The
sections run on every sample whatever the mode, as the RTL's do."""


def run(x, mode):
    k = 1 if mode == 1 else 2
    y1 = y2 = 0
    out = []
    for s in x:
        y1 += ((s << 8) - y1) >> k
        y2 += (y1 - y2) >> k
        out.append(s if mode == 0 else y2 >> 8)
    return out
