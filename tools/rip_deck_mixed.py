#!/usr/bin/env python3
"""
rip_deck_mixed.py - Render a deck the way the C64 actually displays it:
hires and multicolour cells MIXED on the same screen.

$D016 bit 4 turns multicolour text mode on globally, but it is selected per
cell by bit 3 of the colour RAM nibble:

    colour RAM 0-7   -> hires cell:       8 pixels, background + that colour
    colour RAM 8-15  -> multicolour cell: 4 double-width pixels, 4 colours

The game drives colour RAM from CharColor ($0800), one byte per character
code, whose upper nibble is a palette slot. NewCharColors ($3577) rewrites
each entry's lower nibble per deck from a 12-slot record at $6A44, selected
by deckColorScheme ($F160). BuildLevel then writes the byte to colour RAM.

So a character's MODE depends on the deck, not just the character. This is
why the ALERT lettering keeps single-pixel spacing (its characters land on a
slot that is hires in almost every scheme) while the floor and wall shading
comes out multicolour.

Usage: python tools/rip_deck_mixed.py [deck]
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit('ERROR: Pillow required. pip install Pillow')

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing, decode_deck_rle, C64_PAL  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_DIR = PROJECT / 'tools' / 'output'

CHARSET = 0x7800
TILEDEFS = 0xE800
CHARCOLOR = 0x0800
RECORDS = 0x6A44
REC_LEN = 12
DECKSCHEME = 0xF160

# Play-area shared colours. Only the low nibble of $D02x is used.
D021 = 14      # DEFAULT ONLY - overridden per deck below from slot 0
D022 = 1       # multicolour 01 - white
D023 = 0       # multicolour 10 - black
# D023 was 6 (blue) here until 2026-08-17. It is 0: the only character-mode
# writes to $D022/$D023 are DrawSideview's ($308A/$308F), setting $F1/$F0 --
# the other writes to that area are the SPRITE multicolour registers. Getting
# this wrong recolours every multicolour cell on every deck. export_bbc.py and
# palette_lab.py have always used 0; this file had been left behind.

VIEW_TILES_X, VIEW_TILES_Y = 10, 7
SCALE = 3


def main():
    deck = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    mem, _ = parse_listing(LST_FILE)

    scheme = mem[DECKSCHEME + deck]
    rec = list(mem[RECORDS + scheme * REC_LEN:RECORDS + (scheme + 1) * REC_LEN])
    global D021
    D021 = rec[0]           # $D021 is slot 0 of the deck's record - see
                            # export_bbc.deck_background()
    print('deck %d -> colour scheme %d -> slots %s'
          % (deck, scheme, ' '.join('%X' % c for c in rec)))

    def cell_colour(code):
        slot = mem[CHARCOLOR + code] >> 4
        return rec[slot] if slot < REC_LEN else 0

    tiles = decode_deck_rle(mem, deck)[:1024]
    tiles += [0] * (1024 - len(tiles))

    # frame the content so there is something to look at
    used = [i for i, t in enumerate(tiles) if t]
    cx = sum(i % 64 for i in used) // max(len(used), 1)
    cy = sum(i // 64 for i in used) // max(len(used), 1)
    ox = max(0, min(64 - VIEW_TILES_X, cx - VIEW_TILES_X // 2))
    oy = max(0, min(16 - VIEW_TILES_Y, cy - VIEW_TILES_Y // 2))

    w, h = VIEW_TILES_X * 32, VIEW_TILES_Y * 32
    img = Image.new('RGB', (w * SCALE, h * SCALE), C64_PAL[D021])
    px = img.load()

    nhi = nmc = 0
    for ty in range(VIEW_TILES_Y):
        for tx in range(VIEW_TILES_X):
            tile = tiles[(oy + ty) * 64 + (ox + tx)]
            for cyy in range(4):
                for cxx in range(4):
                    code = mem[TILEDEFS + tile * 16 + cyy * 4 + cxx]
                    colour = cell_colour(code)
                    multi = bool(colour & 8)
                    if multi:
                        nmc += 1
                        pal = [D021, D022, D023, colour & 7]
                    else:
                        nhi += 1
                    base = CHARSET + code * 8
                    x0 = (tx * 4 + cxx) * 8
                    y0 = (ty * 4 + cyy) * 8
                    for row in range(8):
                        b = mem[base + row]
                        for p in range(8 if not multi else 4):
                            if multi:
                                c = pal[(b >> (6 - p * 2)) & 3]
                                xs = [x0 + p * 2, x0 + p * 2 + 1]
                            else:
                                c = colour if (b >> (7 - p)) & 1 else D021
                                xs = [x0 + p]
                            rgb = C64_PAL[c]
                            for x in xs:
                                for sx in range(SCALE):
                                    for sy in range(SCALE):
                                        px[x * SCALE + sx,
                                           (y0 + row) * SCALE + sy] = rgb

    out = OUT_DIR / ('deck_%02d_mixed.png' % deck)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print('cells: %d hires, %d multicolour' % (nhi, nmc))
    print('Wrote %s' % out)


if __name__ == '__main__':
    main()
