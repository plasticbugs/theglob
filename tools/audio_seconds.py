#!/usr/bin/env python3
"""Second-by-second comparison of two recordings of the same session.

    audio_seconds.py <mame.wav> <core.wav> [lag_search_ms]

For each whole second: the AC energy (DC removed) of each, their ratio, and
the waveform correlation at the best lag within +-lag_search_ms (default 5):
the core and MAME are driven by the same writes at the same cycle, so a right
AY is phase-locked to MAME's and correlates near 1; band energy (in
compare_audio.py) is the measure when it is not.  Seconds where MAME is
silent are shown but left out of the summary, which is the mean |log2 ratio|
(0 = the same level) and the mean correlation over the seconds that sound.
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare_audio import read_wav  # noqa: E402


def main(a):
    m, rate = read_wav(a[0])
    c, rate_c = read_wav(a[1])
    assert rate == rate_c, 'sample rates differ'
    lag_max = int(rate * (float(a[2]) if len(a) > 2 else 5.0) / 1000)
    n = min(len(m), len(c)) // rate
    logs, cors = [], []
    print(' sec    MAME ac    core ac   ratio   corr  lag')
    for s in range(n):
        x = m[s * rate:(s + 1) * rate]
        y = c[s * rate:(s + 1) * rate]
        mx, my = sum(x) / rate, sum(y) / rate
        x = [v - mx for v in x]
        y = [v - my for v in y]
        ex = math.sqrt(sum(v * v for v in x) / rate)
        ey = math.sqrt(sum(v * v for v in y) / rate)
        best, blag = 0.0, 0
        if ex > 50 and ey > 1:
            step = max(1, lag_max // 40)
            for lag in range(-lag_max, lag_max + 1, step):
                lo, hi = max(0, lag), min(rate, rate + lag)
                num = sum(x[i] * y[i - lag] for i in range(lo, hi))
                r = num / (ex * ey * rate)
                if r > best:
                    best, blag = r, lag
        ratio = ey / ex if ex > 0 else float('nan')
        loud = ex > 50
        if loud:
            logs.append(abs(math.log2(ratio)) if ratio > 0 else 9)
            cors.append(best)
        print(f'{s:4d} {ex:10.0f} {ey:10.0f} {ratio:7.3f} {best:6.3f} {blag:4d}{"" if loud else "   (silent)"}')
    if logs:
        print(f'over {len(logs)} sounding seconds: mean |log2 ratio| {sum(logs)/len(logs):.3f}, '
              f'mean correlation {sum(cors)/len(cors):.3f}')


if __name__ == '__main__':
    main(sys.argv[1:])
