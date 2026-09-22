#!/usr/bin/env python3
"""Bit-exact model of rtl/dc_block.sv: y[n] = x[n] - x[n-1] + (1 - 2^-9) y[n-1],
8 fractional bits in the accumulator, the output clamped to 16 bits."""
K, FRAC = 9, 8


def run(x):
    y, xd, out = 0, 0, []
    for s in x:
        y = y - (y >> K) + ((s - xd) << FRAC)
        xd = s
        out.append(max(-32768, min(32767, y >> FRAC)))
    return out
