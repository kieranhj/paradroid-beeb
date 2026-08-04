#!/usr/bin/env python3
"""
rip_tiles_mc.py - Render the $7800 tile set as C64 MULTICOLOUR characters.

The game runs the play area in multicolour character mode ($D016 bit 4 set;
see the self-modifying _d016Mode routine at $6F1B). In that mode a character
byte is four 2-bit pixel pairs, each drawn two screen pixels wide:

    00 -> $D021 background      10 -> $D023
    01 -> $D022                 11 -> colour RAM (per cell)

So a character is 4 logical pixels wide, not 8, and carries four colours.

Writes tools/output/tiles_mc.png next to the existing 1bpp tiles.png so the
two interpretations can be compared directly against a real screenshot.
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit('ERROR: Pillow required. pip install Pillow')

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT = PROJECT / 'tools' / 'output' / 'tiles_mc.png'

CHARSET = 0x7800
TILEDEFS = 0xE800

# Approximated from ref/start screen.png: lavender floor, olive grid,
# white highlight, dark shadow.
PAL = [
    (0x8B, 0x8B, 0xD0),   # 00  background   ($D021)
    (0xBF, 0xCE, 0x72),   # 01  grid lines   ($D022)
    (0x40, 0x31, 0x8D),   # 10  shadow       ($D023)
    (0xFF, 0xFF, 0xFF),   # 11  highlight    (colour RAM)
]

SCALE = 3


def main():
    mem, _ = parse_listing(LST_FILE)

    cols, rows = 8, 4
    tw, th = 32, 32                      # 4 chars x (4 MC px * 2) = 32 screen px
    img = Image.new('RGB', (cols * tw * SCALE, rows * th * SCALE), (0, 0, 0))
    px = img.load()

    for t in range(32):
        tx, ty = (t % cols) * tw, (t // cols) * th
        for cy in range(4):
            for cx in range(4):
                code = mem[TILEDEFS + t * 16 + cy * 4 + cx]
                base = CHARSET + code * 8
                for row in range(8):
                    b = mem[base + row]
                    for p in range(4):           # four 2-bit pairs, MSB first
                        colour = PAL[(b >> (6 - p * 2)) & 3]
                        x0 = tx + cx * 8 + p * 2  # each MC pixel is 2 wide
                        y0 = ty + cy * 8 + row
                        for dx in range(2):
                            for sx in range(SCALE):
                                for sy in range(SCALE):
                                    px[(x0 + dx) * SCALE + sx,
                                       y0 * SCALE + sy] = colour

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print('Wrote %s' % OUT)


if __name__ == '__main__':
    main()
