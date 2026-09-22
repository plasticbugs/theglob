#!/usr/bin/env python3
"""The Glob's video hardware in Python: the executable specification.

Reads a state dumped by tools/dump_state.lua (the bitmap and the palette bank)
and the colour PROM, and produces the frame the board draws.  Checked pixel
for pixel against MAME's own output for the same frame, which is in the dump.

The model is docs/hardware.md section 7, step by step:

  1. byte `offs` of VRAM (8000-FFFF) is line offs / 136, pixels
     (offs % 136) * 2 and that + 1;
  2. the LOW nibble is the left pixel;
  3. pen = palette_bank << 4 | nibble;
  4. the PROM byte for the pen is RGB 3-3-2, weighted 0x92 0x4A 0x23 for red
     and green (bits 7-5 and 4-2, MSB first) and 0xAD 0x52 for blue;
  5. lines 0-235 and pixels 0-271 are visible.

Usage:
    render_model.py <prom.bin | image.rom> <state.bin> [...] [-o DIR]

For each state: prints the number of pixels that differ from MAME, and with
-o writes model_<frame>.png, mame_<frame>.png and pens_<frame>.bin (one pen
index per pixel, which the RTL bench is diffed against).
"""
import os, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio  # noqa: E402

W, H, STRIDE = 272, 236, 136


def load_prom(path):
    d = open(path, 'rb').read()
    if len(d) == 32:
        return d
    if len(d) == 0x7820:            # the core's ROM image: the PROM is last
        return d[0x7800:0x7820]
    sys.exit(f'{path}: neither a 32-byte PROM nor the 30752-byte image')


def prom_rgb(b):
    r = 0x92 * (b >> 7 & 1) + 0x4a * (b >> 6 & 1) + 0x23 * (b >> 5 & 1)
    g = 0x92 * (b >> 4 & 1) + 0x4a * (b >> 3 & 1) + 0x23 * (b >> 2 & 1)
    bl = 0xad * (b >> 1 & 1) + 0x52 * (b & 1)
    return r, g, bl


def load_state(path):
    d = open(path, 'rb').read()
    if d[:4] != b'TGST':
        sys.exit(f'{path}: not a theglob state')
    _ver, frame, palbank = struct.unpack('<III', d[4:16])
    vram = d[16:16 + 32768]
    ram = d[16 + 32768:16 + 32768 + 2048]
    o = 16 + 32768 + 2048
    w, h = struct.unpack('<II', d[o:o + 8])
    pix = d[o + 8:o + 8 + w * h * 4]
    return dict(frame=frame, palbank=palbank, vram=vram, ram=ram, w=w, h=h, pix=pix)


def pens(vram, palbank):
    """One pen (0-31) per visible pixel, row-major."""
    out = bytearray(W * H)
    for y in range(H):
        row = y * STRIDE
        for bx in range(STRIDE):
            v = vram[row + bx]
            o = y * W + bx * 2
            out[o] = (palbank << 4) | (v & 0x0f)
            out[o + 1] = (palbank << 4) | (v >> 4)
    return bytes(out)


def to_rgb(pen_bytes, prom):
    lut = [prom_rgb(b) for b in prom]
    out = bytearray(len(pen_bytes) * 3)
    for i, p in enumerate(pen_bytes):
        out[i * 3:i * 3 + 3] = bytes(lut[p])
    return bytes(out)


def mame_rgb(st):
    """MAME's screen:pixels() is 32-bit ARGB, little-endian in the string."""
    pix, n = st['pix'], st['w'] * st['h']
    out = bytearray(n * 3)
    for i in range(n):
        b, g, r = pix[i * 4], pix[i * 4 + 1], pix[i * 4 + 2]
        out[i * 3:i * 3 + 3] = bytes((r, g, b))
    return bytes(out)


def main(argv):
    out_dir = None
    if '-o' in argv:
        i = argv.index('-o')
        out_dir = argv[i + 1]
        del argv[i:i + 2]
    if len(argv) < 2:
        sys.exit(__doc__)
    prom = load_prom(argv[0])
    worst = 0
    for path in argv[1:]:
        st = load_state(path)
        if (st['w'], st['h']) != (W, H):
            sys.exit(f'{path}: MAME bitmap is {st["w"]}x{st["h"]}, expected {W}x{H}')
        p = pens(st['vram'], st['palbank'])
        model = to_rgb(p, prom)
        mame = mame_rgb(st)
        bad = sum(1 for i in range(W * H) if model[i * 3:i * 3 + 3] != mame[i * 3:i * 3 + 3])
        worst = max(worst, bad)
        print(f'frame {st["frame"]:6d}  bank {st["palbank"]}  {bad:6d} pixels differ from MAME')
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
            n = st['frame']
            pngio.write(f'{out_dir}/model_{n:05d}.png', W, H, model)
            pngio.write(f'{out_dir}/mame_{n:05d}.png', W, H, mame)
            open(f'{out_dir}/pens_{n:05d}.bin', 'wb').write(p)
    return 1 if worst else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
