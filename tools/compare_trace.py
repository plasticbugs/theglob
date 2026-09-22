#!/usr/bin/env python3
"""Diff two CPU write traces a transaction at a time (METHODOLOGY section 4).

    compare_trace.py <mame_trace.txt> <rtl_trace.txt> [context]

Prints how many leading transactions agree, and the first disagreement with
the lines around it.  Anything the CPU polls will eventually sample
differently, so a trace is comparable only up to the first such divergence;
say where that is rather than masking it.
"""
import sys


def load(p):
    """The writes only (M, O), and only address and data: frame and interrupt
    markers and timestamps say where, not what."""
    return [' '.join(l.split()[:3]) for l in open(p) if l[:1] in ('M', 'O')]


def main(a):
    m, r = load(a[0]), load(a[1])
    ctx = int(a[2]) if len(a) > 2 else 6
    n = min(len(m), len(r))
    i = next((k for k in range(n) if m[k] != r[k]), n)
    print(f'MAME {len(m)} writes, RTL {len(r)}; the first {i} agree')
    if i < n or len(m) != len(r):
        lo = max(0, i - ctx)
        for k in range(lo, min(i + ctx, max(len(m), len(r)))):
            mk = m[k] if k < len(m) else '-'
            rk = r[k] if k < len(r) else '-'
            print(f'{k:9d}  {mk:12s} {rk:12s} {"" if mk == rk else "<--"}')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
