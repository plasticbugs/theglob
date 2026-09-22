#!/usr/bin/env python3
"""Check the .rom image theglob.mra builds against MAME's own loaded regions.

tools/dump_regions.lua writes out the bytes MAME hands the chips; this compares
each with its slice of the image.  The layout is the one in theglob.mra and
target/pocket/theglob_mem.sv.

Usage:
    verify_rom.py <image.rom> <region_dir>

    REGION_DIR=.build/regions tools/mame.sh -seconds_to_run 1 \\
        -autoboot_script tools/dump_regions.lua
"""
import sys

PROG_BASE, PROG_LEN = 0x0000, 0x7800    # Z80 0000-77FF; the region is 64 KB, the rest unused
PROM_BASE, PROM_LEN = 0x7800, 0x0020
IMAGE_LEN = PROM_BASE + PROM_LEN


def fail(msg):
    print(f'FAIL: {msg}')
    sys.exit(1)


def same(name, img, ref):
    if img != ref:
        i = next(k for k in range(len(ref)) if img[k] != ref[k])
        fail(f'{name} differs at 0x{i:04x}: image {img[i]:02x}, MAME {ref[i]:02x}')
    print(f'  {name:14s} {len(ref):6d} bytes  identical to MAME')


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    image = open(sys.argv[1], 'rb').read()
    d = sys.argv[2].rstrip('/')
    maincpu = open(f'{d}/maincpu.bin', 'rb').read()
    proms = open(f'{d}/proms.bin', 'rb').read()
    if len(image) != IMAGE_LEN:
        fail(f'image is {len(image)} bytes, expected {IMAGE_LEN}')
    if len(maincpu) < PROG_LEN or len(proms) != PROM_LEN:
        fail(f'regions are {len(maincpu)} and {len(proms)} bytes')
    same('Z80 program', image[PROG_BASE:PROG_BASE + PROG_LEN], maincpu[:PROG_LEN])
    same('colour PROM', image[PROM_BASE:PROM_BASE + PROM_LEN], proms)
    print('PASS')


if __name__ == '__main__':
    main()
