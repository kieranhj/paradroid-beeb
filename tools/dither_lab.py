#!/usr/bin/env python3
"""
dither_lab.py - a gallery of floor/wall dither options, rendered as the
BBC would draw them.

    python tools/dither_lab.py                # every deck, every option
    python tools/dither_lab.py --deck 5       # one deck
    python tools/dither_lab.py --open         # and open it in a browser

Writes tools/output/dither_lab.html: one row per deck, one column per
dithering option, each a real render of that deck's map through that
deck's MODE 1 palette. NOT part of any build, and it writes nothing the
game reads - it exists so a human can pick.

WHY IT EXISTS. hexwab, issue #5: "Create a tool to mock up a screenshot
of the deck as it would be rendered in-game with the postprocessed tiles.
Use it to produce a gallery of dithering options for a human to pick
between. One thing I would like to see tried is the walls being
undithered, or maybe dithered differently ... Or maybe the floor
undithered and the walls dithered. Vertical stripes? Horizontal stripes?
Checkerboard the other way around?"

WHAT THE GAME DOES TODAY, and what these options change. DitherChar
(src/level.asm) runs over the finished charset at deck load and sets half
of every LOGICAL 0 pixel to logical 1, in a 2x2 checker, so a fully
saturated BBC floor reads at half intensity (layer-14 DECISION 1). It
dithers logical 0 WHEREVER IT LANDS - floor, and any ink that merged onto
logical 0 - and it is a no-op on a deck whose logical 1 is not black.
The options below change which pixels are dithered and with what pattern;
"as shipped" is the current behaviour and is the one to compare against.

THE CLASSES. A character is floor or wall by the tile cell it appears in:
the tile definitions name 16 character codes per tile, and a code used by
tile 0 (the blank) or only in a tile's interior reads as floor, while the
codes a tile uses on its edges read as wall. That is a heuristic, and it
is stated here rather than hidden: the C64's tiles have rounded corners
and a wall does not always fill its cell, so "wall" here means "a
character the tile set uses at a tile edge", which is what you can see in
the gallery and judge.

Reads the C64 listing, like every other tool here, so it needs
paradroid_ce.lst in the project root. Pillow for the PNGs.
"""

import argparse
import base64
import io
import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from rip_levels import parse_listing, decode_deck_rle              # noqa: E402
from export_bbc import (BBC_RGB, CHARSET_ADDR, CHARCOLOR,          # noqa: E402
                        TILEDEF_ADDR, TILEDEF_SIZE,
                        deck_colours, deck_background,
                        build_logical_map, convert_charset)

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_DIR = PROJECT / 'tools' / 'output'
OUT_FILE = OUT_DIR / 'dither_lab.html'
OVERRIDE = PROJECT / 'tools' / 'deck_palettes.json'

MAP_COLS, MAP_ROWS = 64, 16
TILE_CELLS = 4                  # a tile is 4x4 characters
CELL_PX = 8
TILE_PX = TILE_CELLS * CELL_PX

# How much of a deck to show. The play area is 320x120, so this is a
# little wider than the player ever sees at once and tall enough to show
# floor and wall together.
VIEW_TILES_X, VIEW_TILES_Y = 10, 4


# ---------------------------------------------------------------------------
# The dither options
# ---------------------------------------------------------------------------
# Each is a function (byte_index, pixel_index) -> True if this pixel may be
# shaded. byte_index is the index within the 16-byte character, so bit 0 IS
# the scanline parity (the left half's 8 scanlines then the right half's -
# see DitherChar). pixel_index is 0-3 within the byte's nibble.
#
# "as shipped" reproduces DitherChar exactly: mask 0x0A on odd scanlines,
# 0x05 on even, which is pixels 0,2 / 1,3 - a 2x2 checker.

PATTERNS = {
    'none':        lambda i, p: False,
    'checker':     lambda i, p: (p + i) & 1 == 1,          # as shipped
    'checker_inv': lambda i, p: (p + i) & 1 == 0,          # the other phase
    'vertical':    lambda i, p: p & 1 == 1,                # every other column
    'horizontal':  lambda i, p: i & 1 == 1,                # every other line
    'quarter':     lambda i, p: (p & 1) == 1 and (i & 1) == 1,   # 1 in 4
}

# The gallery's columns: (label, floor pattern, wall pattern). A pattern per
# CLASS, not one pattern and one class - KC, 2026-09-12, asking for a quarter
# floor with everything else dithered, which the old shape could not say.
# "wall" is everything wall_codes() returns: the border, the area inside it,
# and the dimple.
OPTIONS = [
    ('as shipped',              'checker',     'checker'),
    ('none',                    'none',        'none'),
    ('floor only',              'checker',     'none'),
    ('walls only',              'none',        'checker'),
    ('inverted checker',        'checker_inv', 'checker_inv'),
    ('vertical stripes',        'vertical',    'vertical'),
    ('horizontal lines',        'horizontal',  'horizontal'),
    ('quarter floor only',      'quarter',     'none'),
    ('quarter floor, rest 2x2', 'quarter',     'checker'),
]


FLOOR_SLOTS = (0, 1)            # see below: open deck, and its grid pattern


def wall_codes(mem):
    """Character codes that belong to a WALL, by their C64 colour slot.

    KC, 2026-09-12, correcting the first cut of this tool: a wall is the area
    INSIDE its light/dark border, not the tile's outer cells, and the dimple
    in a wall tile is part of the wall, not floor. Cell position cannot say
    that - the tiles' structures do not fill their 4x4 - but the colour slot
    can, because the artwork colours the deck by role:

      slot 0   codes $00, $20, $42, all EMPTY - the open deck itself. 69% of
               deck 5's cells and 80% of deck 1's.
      slot 1   $3D/$3F/$41/$47, density 15 - the floor's own grid pattern,
               drawn ON the open area.
      slots
      7 and 9  the light/dark border pair, alternating along a structure's
               edges (tile 2 is a dark row above a light one).
      $D8      slot 9 and EMPTY: the area enclosed by that border, and the
               second most common code on every deck (688 cells on deck 5).
               The first cut called it floor, which is the bug KC caught.
      $D4-$D7  the dimple inside a wall tile - slots 7 and 9, so it lands on
               the wall side by construction.
      2, 8, 14 the remaining structural pieces (doors, lift, console).

    So: slot 0 or 1 is floor, everything else is wall. The dither's target is
    LOGICAL 0 pixels, which exist inside the wall body as well as on the open
    deck, and that is exactly what "walls undithered" has to be able to spare.
    """
    return {code for code in range(256)
            if (mem[CHARCOLOR + code] >> 4) not in FLOOR_SLOTS}


def dither_char(chardata, shade, may_shade):
    """One character's 16 MODE 1 bytes, dithered by `may_shade`.

    The shape is DitherChar's: find the pixels with no colour at all (both
    planes clear) and set the LOW plane on the ones the pattern picks, so
    logical 0 becomes logical 1 and a pixel with any colour is left alone.
    """
    out = bytearray(chardata)
    for i, b in enumerate(out):
        zero = ~((b >> 4) | b) & 0x0F              # pixels with no colour
        mask = 0
        for p in range(4):
            if (zero >> (3 - p)) & 1 and may_shade(i, p):
                mask |= 1 << (3 - p)
        out[i] = b | mask
    return out


def mode1_pixels(chardata):
    """A character's 16 bytes -> 8x8 logical colours (0-3)."""
    px = [[0] * 8 for _ in range(8)]
    for row in range(8):
        for half in range(2):
            b = chardata[half * 8 + row]
            for p in range(4):
                hi = (b >> (7 - p)) & 1
                lo = (b >> (3 - p)) & 1
                px[row][half * 4 + p] = hi * 2 + lo
    return px


def deck_palette(deck, logical, override):
    """The deck's four MODE 1 physicals, preferring the hand-chosen set."""
    d = (override.get('decks') or {}).get(str(deck)) if override else None
    if d and 'physical' in d:
        return d['physical']
    # The automatic assignment, as export_bbc computes it.
    from export_bbc import assign_palette
    return assign_palette(logical)


def render(mem, deck, chars, palette, x0, y0):
    """A VIEW_TILES_X x VIEW_TILES_Y window of the deck, as RGB rows."""
    tiles = decode_deck_rle(mem, deck)[:MAP_COLS * MAP_ROWS]
    tiles += [0] * (MAP_COLS * MAP_ROWS - len(tiles))

    w = VIEW_TILES_X * TILE_PX
    h = VIEW_TILES_Y * TILE_PX
    buf = bytearray(w * h * 3)
    for ty in range(VIEW_TILES_Y):
        for tx in range(VIEW_TILES_X):
            tile = tiles[(y0 + ty) * MAP_COLS + (x0 + tx)]
            for cy in range(TILE_CELLS):
                for cx in range(TILE_CELLS):
                    code = mem[TILEDEF_ADDR + tile * TILEDEF_SIZE
                               + cy * TILE_CELLS + cx]
                    px = mode1_pixels(chars[code])
                    ox = tx * TILE_PX + cx * CELL_PX
                    oy = ty * TILE_PX + cy * CELL_PX
                    for row in range(8):
                        for col in range(8):
                            r, g, b = BBC_RGB[palette[px[row][col]] & 7]
                            o = ((oy + row) * w + ox + col) * 3
                            buf[o:o + 3] = bytes((r, g, b))
    return w, h, bytes(buf)


def busiest_window(mem, deck):
    """Where to point the camera: the window with the most non-blank tiles."""
    tiles = decode_deck_rle(mem, deck)[:MAP_COLS * MAP_ROWS]
    tiles += [0] * (MAP_COLS * MAP_ROWS - len(tiles))
    best, at = -1, (0, 0)
    for y0 in range(0, MAP_ROWS - VIEW_TILES_Y + 1):
        for x0 in range(0, MAP_COLS - VIEW_TILES_X + 1):
            n = sum(1 for ty in range(VIEW_TILES_Y)
                    for tx in range(VIEW_TILES_X)
                    if tiles[(y0 + ty) * MAP_COLS + x0 + tx])
            if n > best:
                best, at = n, (x0, y0)
    return at


def png_b64(w, h, rgb):
    from PIL import Image
    im = Image.frombytes('RGB', (w, h), rgb)
    out = io.BytesIO()
    im.save(out, format='PNG')
    return base64.b64encode(out.getvalue()).decode('ascii')


def build_charset(mem, deck, walls, floor_pattern, wall_pattern):
    """Every character the tiles use, converted and dithered for this deck.

    One pattern for the floor characters and one for the wall ones, so an
    option can dither both differently - a quarter floor against a 2x2 wall,
    say. 'none' for either leaves that class alone.
    """
    scheme, rec, cell_colour = deck_colours(mem, deck)
    bg = deck_background(mem, deck)
    logical, _freq = build_logical_map(mem, cell_colour, bg)   # (chosen, freq)
    raw, _stats = convert_charset(mem, cell_colour, logical)

    may = {True: PATTERNS[wall_pattern], False: PATTERNS[floor_pattern]}
    chars = {}
    for code in range(256):
        chars[code] = dither_char(raw[code * 16:code * 16 + 16], None,
                                  may[code in walls])
    return chars, logical


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[1])
    ap.add_argument('--deck', type=int, action='append',
                    help='deck 0-15 (repeatable; default all sixteen)')
    ap.add_argument('--open', action='store_true', help='open in a browser')
    args = ap.parse_args()

    if not LST_FILE.exists():
        sys.exit('ERROR: %s not found. See README.' % LST_FILE)
    print('Parsing %s ...' % LST_FILE.name)
    mem, _filled = parse_listing(LST_FILE)

    override = json.loads(OVERRIDE.read_text()) if OVERRIDE.exists() else None
    walls = wall_codes(mem)
    decks = args.deck or list(range(16))

    rows = []
    for deck in decks:
        x0, y0 = busiest_window(mem, deck)
        shots = []
        for label, floor_pattern, wall_pattern in OPTIONS:
            chars, logical = build_charset(mem, deck, walls,
                                           floor_pattern, wall_pattern)
            palette = deck_palette(deck, logical, override)
            w, h, rgb = render(mem, deck, chars, palette, x0, y0)
            shots.append({'label': label, 'png': png_b64(w, h, rgb),
                          'w': w, 'h': h})
        rows.append({'deck': deck, 'shots': shots,
                     'at': '%d,%d' % (x0, y0)})
        print('  deck %2d: %d options at tile %d,%d'
              % (deck, len(shots), x0, y0))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_FILE.write_text(page(rows), encoding='utf-8')
    print('Wrote %s' % OUT_FILE)
    if args.open:
        import webbrowser
        webbrowser.open(OUT_FILE.as_uri())


def page(rows):
    cells = []
    for r in rows:
        shots = ''.join(
            '<figure><img src="data:image/png;base64,%s" width="%d">'
            '<figcaption>%s</figcaption></figure>'
            % (s['png'], s['w'] // 2, s['label']) for s in r['shots'])
        cells.append('<section><h2>Deck %d <small>at tile %s</small></h2>'
                     '<div class="row">%s</div></section>'
                     % (r['deck'], r['at'], shots))
    return """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>Paradroid - dither options</title>
<style>
 body { background:#111; color:#ddd; font:14px/1.4 system-ui, sans-serif;
        margin:0; padding:16px; }
 h1 { font-size:18px; } h2 { font-size:15px; margin:18px 0 6px; }
 small { color:#888; font-weight:normal; }
 .row { display:flex; flex-wrap:wrap; gap:12px; }
 figure { margin:0; }
 img { image-rendering:pixelated; border:1px solid #333; display:block; }
 figcaption { color:#aaa; font-size:12px; padding-top:3px; }
 p.note { color:#999; max-width:70ch; }
</style></head><body>
<h1>Dither options, rendered as the BBC would draw them</h1>
<p class="note">Each image is that deck's own map and palette, drawn through a
charset dithered the named way. <b>as shipped</b> is what the game does today
(DitherChar, a 2x2 checker over every logical-0 pixel). Decks whose logical 1
is not black are never dithered in the game, so their columns are identical by
design. "walls" means a character the tile set uses at a tile edge - a
heuristic, and the point of looking.</p>
%s
</body></html>
""" % ''.join(cells)


if __name__ == '__main__':
    main()
