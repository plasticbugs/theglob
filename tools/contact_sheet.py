#!/usr/bin/env python3
"""Tile several frames into one PNG, rotated the way the cabinet shows them.

The board draws a 272 x 236 raster that the monitor shows rotated (ROT270 in
MAME): the picture is turned a quarter turn anticlockwise, so it stands 272
tall and 236 wide.

Usage: contact_sheet.py out.png cols a.png b.png ...
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio  # noqa: E402


def rot270(w, h, rgb):
    """Anticlockwise quarter turn: source (x, y) lands at (y, w - 1 - x)."""
    out = bytearray(w * h * 3)
    for y in range(h):
        for x in range(w):
            s = (y * w + x) * 3
            d = ((w - 1 - x) * h + y) * 3
            out[d:d + 3] = rgb[s:s + 3]
    return h, w, bytes(out)


def main(argv):
    out, cols, files = argv[0], int(argv[1]), argv[2:]
    tiles = [rot270(*pngio.read(f)) for f in files]
    tw, th = tiles[0][0], tiles[0][1]
    gap = 4
    rows = (len(tiles) + cols - 1) // cols
    W, H = cols * (tw + gap) - gap, rows * (th + gap) - gap
    img = bytearray(b'\x40' * (W * H * 3))
    for i, (w, h, rgb) in enumerate(tiles):
        ox, oy = (i % cols) * (tw + gap), (i // cols) * (th + gap)
        for y in range(h):
            d = ((oy + y) * W + ox) * 3
            img[d:d + w * 3] = rgb[y * w * 3:(y + 1) * w * 3]
    pngio.write(out, W, H, bytes(img))


if __name__ == '__main__':
    main(sys.argv[1:])
