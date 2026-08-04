#!/usr/bin/env python3
"""
compare_tile.py - Render one tile side by side as the C64 shows it and as the
BBC port shows it, for a given deck.

Use to decide whether a difference is a port bug or faithful to the original.

Usage: python tools/compare_tile.py <tile> <deck> [bbc_charset_dump]
       Without a dump, the BBC side is computed by the exporter's conversion.
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit('ERROR: Pillow required. pip install Pillow')

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing, C64_PAL  # noqa: E402
from export_bbc import (deck_colours, build_logical_map, convert_charset,  # noqa: E402
                        assign_palette, CHARSET_ADDR, TILEDEF_ADDR,
                        TILEDEF_SIZE, D021, D022, D023)

PROJECT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT / 'tools' / 'output'

BBC_RGB = [(0, 0, 0), (255, 0, 0), (0, 255, 0), (255, 255, 0),
           (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)]
SCALE = 8


def main():
    tile = int(sys.argv[1]) if len(sys.argv) > 1 else 22
    deck = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    mem, _ = parse_listing(PROJECT / 'paradroid_ce.lst')

    _, _, cell_colour = deck_colours(mem, deck)
    logical, _ = build_logical_map(mem, cell_colour)
    palette = assign_palette(logical)
    full, _ = convert_charset(mem, cell_colour, logical)

    img = Image.new('RGB', (32 * 2 * SCALE + 16, 32 * SCALE), (40, 40, 40))
    px = img.load()

    for row in range(4):
        for col in range(4):
            code = mem[TILEDEF_ADDR + tile * TILEDEF_SIZE + row * 4 + col]
            colour = cell_colour(code)
            multi = bool(colour & 8)

            # ---- C64 side ----
            for y in range(8):
                b = mem[CHARSET_ADDR + code * 8 + y]
                for p in range(4 if multi else 8):
                    if multi:
                        pal = [D021, D022, D023, colour & 7]
                        c = C64_PAL[pal[(b >> (6 - p * 2)) & 3]]
                        xs = [col * 8 + p * 2, col * 8 + p * 2 + 1]
                    else:
                        c = C64_PAL[colour if (b >> (7 - p)) & 1 else D021]
                        xs = [col * 8 + p]
                    for x in xs:
                        for sx in range(SCALE):
                            for sy in range(SCALE):
                                px[x * SCALE + sx, (row * 8 + y) * SCALE + sy] = c

            # ---- BBC side, decoded from the MODE 1 conversion ----
            base = code * 16
            for y in range(8):
                for half in (0, 1):
                    byte = full[base + half * 8 + y]
                    for n in range(4):
                        lo = (byte >> (3 - n)) & 1
                        hi = (byte >> (7 - n)) & 1
                        c = BBC_RGB[palette[(hi << 1) | lo]]
                        x = 32 * SCALE + 16 + (col * 8 + half * 4 + n) * SCALE
                        for sx in range(SCALE):
                            for sy in range(SCALE):
                                px[x + sx, (row * 8 + y) * SCALE + sy] = c

    out = OUT_DIR / ('compare_tile%d_deck%d.png' % (tile, deck))
    img.save(out)
    print('C64 (left) vs BBC (right), tile %d deck %d -> %s' % (tile, deck, out))


if __name__ == '__main__':
    main()
