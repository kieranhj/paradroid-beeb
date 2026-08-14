#!/usr/bin/env python3
"""
export_bbc.py - Convert Paradroid C64 data to BeebASM source for the BBC port.

Emits into src/data/:
  charset.asm   - the $7800 charset converted to BBC MODE 1 (256 chars, 16 bytes each)
  tiledefs.asm  - the 32 tile definitions from $E800 (4x4 char codes, byte-identical)
  levels.asm    - deck pointer table, per-deck metadata and RLE map data (byte-identical)

MODE 1 conversion
-----------------
The play area runs in C64 MULTICOLOUR character mode - $D016 bit 4 set, via
the self-modifying _d016Mode routine at $6F1B, which patches its own LDA
operand between $D0 (multicolour, play area) and $C0 (hires, text screens).

In multicolour mode a character byte is four 2-bit pixel pairs, each drawn
two screen pixels wide:

    00 -> $D021 background      10 -> $D023
    01 -> $D022                 11 -> colour RAM (per cell)

So a character is 4 logical pixels wide carrying 4 colours, not 8 pixels of
1bpp. This maps onto BBC MODE 1 exactly: MODE 1 is also 4 colours, also 320
pixels across, and one C64 multicolour pixel becomes two MODE 1 pixels.

MODE 1 packs 4 pixels per byte; pixel n takes bit (7-n) as its high colour
bit and bit (3-n) as its low bit. Each C64 pixel is emitted twice:

    left  byte of a scanline = C64 pixels 0,0,1,1
    right byte of a scanline = C64 pixels 2,2,3,3

Logical colours 0-3 are preserved as-is, so a deck's colour scheme is a
palette change at runtime, mirroring how the C64 varied $D021/$D022/$D023.

BBC screen memory groups 4 pixels x 8 scanlines into 8 consecutive bytes, so
a character occupies 16 contiguous bytes: the left half's 8 scanlines then
the right half's 8. Characters are stored in that order, making a plot a
straight 16-byte copy to the screen.

Caveat: on the C64 the 11 pixel value comes from colour RAM and so can vary
per cell. MODE 1's four logical colours are global, so per-cell variation of
that one colour is lost. The play area looks uniform, so a per-deck palette
should cover it.

Requires: Python 3. No third-party dependencies.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_DIR = PROJECT / 'src' / 'data'

CHARSET_ADDR = 0x7800
CHARSET_CHARS = 256

CHARCOLOR = 0x0800      # one byte per character code; upper nibble = slot
RECORDS = 0x6A44        # 12-byte colour slot records, one per scheme
REC_LEN = 12
DECKSCHEME = 0xF160     # deck -> scheme index

# Play-area shared colours. Only the low nibble of each $D02x is used.
# D022/D023 are set by DrawSideview ($308A/$308F) as $F1/$F0 and persist into
# gameplay; the other writes to that area are +3/+4/+$C, which are the sprite
# multicolour registers rather than the character ones.
# D021 is NOT confirmed: it comes from bgColor, which SetIntroColors loads
# from slot 3 of the deck record - but slot 3 does not match the lavender
# floor in ref/start screen.png, so gameplay evidently sets it elsewhere.
# 14 (light blue) is taken from the screenshot and should be re-derived.
D021 = 14               # background - light blue, the lavender floor  [assumed]
D022 = 1                # multicolour 01 - white
D023 = 0                # multicolour 10 - black

DECK = 1                # deck whose colour scheme the charset is built for

# Rough luminance of the C64 palette, for mapping colours we cannot keep.
LUMA = [0, 255, 79, 161, 94, 128, 62, 191,
        99, 62, 122, 80, 120, 178, 100, 159]

# BBC MODE 1 physical colours, as RGB.
BBC_RGB = [
    (0, 0, 0),        # 0 black
    (255, 0, 0),      # 1 red
    (0, 255, 0),      # 2 green
    (255, 255, 0),    # 3 yellow
    (0, 0, 255),      # 4 blue
    (255, 0, 255),    # 5 magenta
    (0, 255, 255),    # 6 cyan
    (255, 255, 255),  # 7 white
]

# The C64 palette, for nearest-colour matching.
C64_RGB = [
    (0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x88, 0x39, 0x32), (0x67, 0xB6, 0xBD),
    (0x8B, 0x3F, 0x96), (0x55, 0xA0, 0x49), (0x40, 0x31, 0x8D), (0xBF, 0xCE, 0x72),
    (0x8B, 0x54, 0x29), (0x57, 0x42, 0x00), (0xB8, 0x69, 0x62), (0x50, 0x50, 0x50),
    (0x78, 0x78, 0x78), (0x94, 0xE0, 0x89), (0x78, 0x69, 0xC4), (0x9F, 0x9F, 0x9F),
]

# Aesthetic preferences, honoured when the colour is still free: the floor
# goes to blue rather than a glaring cyan, the grid lines to magenta, and
# shadows to black rather than a glaring BBC red.
PREFERRED = {14: 4, 7: 5, 2: 0}


def assign_palette(logical):
    """Pick a distinct BBC physical colour for each of the four logical ones.

    A fixed C64->BBC table cannot work: several C64 colours share a nearest
    BBC match, so two logical colours collapse onto one physical and whatever
    is drawn in the second becomes invisible. Assigning greedily per deck,
    nearest-unused first, guarantees four distinct colours.
    """
    out, taken = [], set()
    for c64 in logical:
        want = PREFERRED.get(c64)
        if want is not None and want not in taken:
            out.append(want)
            taken.add(want)
            continue
        r, g, b = C64_RGB[c64]
        best = min((p for p in range(8) if p not in taken),
                   key=lambda p: (BBC_RGB[p][0] - r) ** 2
                   + (BBC_RGB[p][1] - g) ** 2 + (BBC_RGB[p][2] - b) ** 2)
        out.append(best)
        taken.add(best)
    return out

TILEDEF_ADDR = 0xE800
TILEDEF_COUNT = 32
TILEDEF_SIZE = 16

LVPTR_LO = 0xF100
LVPTR_HI = 0xF110
DECK_META = 0xF120          # 6 tables x 16 bytes: Y, X, height, width, colour, droids

# ---- lifts ----------------------------------------------------------------
# liftPosX/Y are the VIEW ORIGIN in characters for each stop, not the player's
# position: DoLift ($267A) writes ScreenPosX/Y = liftPos * 8, and FindLift
# compares them against the tile-aligned origin. Both are multiples of 4, so
# every stop names a tile.
#
# The lift PLATFORM is tile 3, at origin tile + (5, 2). That was found by
# scanning every offset and asking which gives a consistent tile across all 30
# stops: (5,2) gives tile 3 on 30/30, and the next best is 21/30. Tile 3's
# sixteen characters are all bit-7-clear - a 32x32 patch with no wall in it,
# which is what a platform you stand on should look like.
#
# The offset is applied HERE so it never appears at run time, and the C64's
# indexing is kept including the sentinels at index 0 and 31: those carry
# shaft 8, which matches no real shaft (0-7), and that is what stops a lift at
# the end of its run.
LIFT_POS_DECK = 0x6CC8      # 32 - which deck each stop is on
LIFT_IDX2SH   = 0x6CE7      # 32 - which shaft each stop belongs to
LIFT_POS_X    = 0x6D07      # 32 - view origin, characters
LIFT_POS_Y    = 0x6D26      # 32
LIFT_STOPS    = 32
LIFT_TILE_DX  = 5
LIFT_TILE_DY  = 2
DECK_META_LEN = 6 * 16
RLE_START = 0xF249
RLE_END = 0xFED0            # inclusive-exclusive; covers deck 15 plus terminator

BANNER = """\\ ============================================================
\\ {name}
\\ GENERATED by tools/export_bbc.py - do not edit by hand.
\\ Source: paradroid_ce.lst (Paradroid, C64 - original/CE lineage)
\\ {desc}
\\ ============================================================
"""


def emit_bytes(f, data, per_line=16):
    for i in range(0, len(data), per_line):
        chunk = data[i:i + per_line]
        f.write('  EQUB ' + ','.join('&%02X' % b for b in chunk) + '\n')


def mode1_byte(pixels):
    """Pack four logical colours (0-3) into one MODE 1 byte, left to right.

    MODE 1 pixel n: high colour bit at (7-n), low bit at (3-n).
    """
    out = 0
    for n, c in enumerate(pixels):
        if c & 2:
            out |= 1 << (7 - n)
        if c & 1:
            out |= 1 << (3 - n)
    return out


def deck_colours(mem, deck):
    """The 12 colour slots in force for a deck, and its cell-colour lookup."""
    scheme = mem[DECKSCHEME + deck]
    rec = list(mem[RECORDS + scheme * REC_LEN:RECORDS + (scheme + 1) * REC_LEN])

    def cell_colour(code):
        slot = mem[CHARCOLOR + code] >> 4
        return rec[slot] if slot < REC_LEN else 0

    return scheme, rec, cell_colour


def build_logical_map(mem, cell_colour):
    """Pick which C64 colours become MODE 1 logical 0-3, by how much each is
    used across the tile set. Logical 0 is always the background."""
    from collections import Counter
    freq = Counter()
    for tile in range(32):
        for i in range(16):
            code = mem[TILEDEF_ADDR + tile * 16 + i]
            colour = cell_colour(code)
            if colour & 8:                       # multicolour cell
                freq[D022] += 1
                freq[D023] += 1
                freq[colour & 7] += 1
            else:                                # hires cell
                freq[colour] += 1
    freq.pop(D021, None)

    chosen = [D021] + [c for c, _ in freq.most_common(3)]
    while len(chosen) < 4:
        chosen.append(0)
    return chosen, freq


def convert_charset(mem, cell_colour, logical):
    """C64 charset -> MODE 1, 16 bytes per char, mode chosen per character.

    Multicolour is selected per cell by bit 3 of the colour RAM nibble, so a
    character is converted as hires (8 px, background + its cell colour) or
    as multicolour (4 double-width px, 4 colours) depending on the deck.
    """
    def logical_of(c64):
        if c64 in logical:
            return logical.index(c64)
        return min(range(4), key=lambda i: abs(LUMA[logical[i]] - LUMA[c64]))

    out = bytearray()
    stats = {'hires': 0, 'multi': 0}
    for c in range(CHARSET_CHARS):
        rows = mem[CHARSET_ADDR + c * 8:CHARSET_ADDR + c * 8 + 8]
        colour = cell_colour(c)
        if colour & 8:
            stats['multi'] += 1
            pal = [logical_of(D021), logical_of(D022),
                   logical_of(D023), logical_of(colour & 7)]
            px = [[pal[(b >> (6 - p * 2)) & 3] for p in range(4)] for b in rows]
            # each C64 pixel occupies two MODE 1 pixels
            left = [mode1_byte([p[0], p[0], p[1], p[1]]) for p in px]
            right = [mode1_byte([p[2], p[2], p[3], p[3]]) for p in px]
        else:
            stats['hires'] += 1
            fg, bg = logical_of(colour), logical_of(D021)
            px = [[fg if (b >> (7 - p)) & 1 else bg for p in range(8)] for b in rows]
            left = [mode1_byte(p[0:4]) for p in px]
            right = [mode1_byte(p[4:8]) for p in px]
        out.extend(left)
        out.extend(right)
    return out, stats


def main():
    if not LST_FILE.exists():
        sys.exit('ERROR: %s not found. See README.' % LST_FILE)

    print('Parsing %s ...' % LST_FILE.name)
    mem, filled = parse_listing(LST_FILE)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # ---- character source + per-deck colour data -----------------------
    # The MODE 1 charset is built on the BBC at deck-load time, because a
    # character's mode AND colour both depend on the deck's colour scheme.
    # Ship the C64 bitmaps plus the colour metadata instead of 16 converted
    # charsets, and convert only the characters the tiles actually use.
    used = sorted({mem[TILEDEF_ADDR + i] for i in range(32 * TILEDEF_SIZE)})
    remap = [0] * 256
    for i, code in enumerate(used):
        remap[code] = i

    src = bytearray()
    slots = bytearray()
    for code in used:
        src.extend(mem[CHARSET_ADDR + code * 8:CHARSET_ADDR + code * 8 + 8])
        slots.append(mem[CHARCOLOR + code] >> 4)

    path = OUT_DIR / 'chardata.asm'
    with open(path, 'w') as f:
        f.write(BANNER.format(
            name='chardata.asm',
            desc='C64 bitmaps for the %d characters the tiles use, plus their '
                 'palette slots and a code->index remap' % len(used)))
        f.write('\nNUM_CHARS = %d\n' % len(used))
        f.write('\n.charSrc\n')
        emit_bytes(f, src)
        f.write('\n.charSlot\n')
        emit_bytes(f, slots)
        f.write('\nALIGN &100\n.charRemap\n')
        emit_bytes(f, remap)
    print('  chardata.asm  %5d bytes (%d of 256 chars used by tiles)'
          % (len(src) + len(slots) + 256, len(used)))

    # Per-deck colour data. colourMap is deck*16 + C64 colour -> MODE 1
    # logical 0-3, precomputed here so the 6502 needs no search.
    names = ['black', 'white', 'red', 'cyan', 'purple', 'green', 'blue',
             'yellow', 'orange', 'brown', 'lt red', 'dk grey', 'grey',
             'lt green', 'lt blue', 'lt grey']
    colour_map = bytearray()
    deck_pal = bytearray()
    for d in range(16):
        scheme, rec, cell_colour = deck_colours(mem, d)
        logical, freq = build_logical_map(mem, cell_colour)
        for c64 in range(16):
            if c64 in logical:
                colour_map.append(logical.index(c64))
            else:
                colour_map.append(min(range(4),
                                      key=lambda i: abs(LUMA[logical[i]] - LUMA[c64])))
        deck_pal.extend(assign_palette(logical))
        if d == DECK:
            print('  deck %d -> scheme %d -> logical %s'
                  % (d, scheme, ', '.join('%d=%s' % (i, names[c])
                                          for i, c in enumerate(logical))))

    schemes = bytearray()
    for s in range(8):
        schemes.extend(mem[RECORDS + s * REC_LEN:RECORDS + (s + 1) * REC_LEN])

    path = OUT_DIR / 'colours.asm'
    with open(path, 'w') as f:
        f.write(BANNER.format(
            name='colours.asm',
            desc='colour slot records, deck->scheme, and per-deck C64->MODE 1 '
                 'logical colour maps'))
        f.write('\n.schemes\n')
        emit_bytes(f, schemes)
        f.write('\n.deckScheme\n')
        emit_bytes(f, mem[DECKSCHEME:DECKSCHEME + 16])
        f.write('\n.deckPalette\n')
        emit_bytes(f, deck_pal)
        f.write('\nALIGN &100\n.colourMap\n')
        emit_bytes(f, colour_map)
    print('  colours.asm   %5d bytes' % (len(schemes) + 16 + len(deck_pal) + 256))

    # ---- tile definitions ----------------------------------------------
    tiles = mem[TILEDEF_ADDR:TILEDEF_ADDR + TILEDEF_COUNT * TILEDEF_SIZE]
    path = OUT_DIR / 'tiledefs.asm'
    with open(path, 'w') as f:
        f.write(BANNER.format(
            name='tiledefs.asm',
            desc='%d tiles x 4x4 character codes - byte-identical to the C64'
                 % TILEDEF_COUNT))
        f.write('\nALIGN &100\n.tiledefs\n')
        emit_bytes(f, tiles)
        f.write('.tiledefs_end\n')
    print('  tiledefs.asm  %5d bytes (%d tiles)' % (len(tiles), TILEDEF_COUNT))

    # ---- levels ---------------------------------------------------------
    ptr_lo = mem[LVPTR_LO:LVPTR_LO + 16]
    ptr_hi = mem[LVPTR_HI:LVPTR_HI + 16]
    meta = mem[DECK_META:DECK_META + DECK_META_LEN]
    rle = mem[RLE_START:RLE_END]

    # C64 pointers are absolute into $F249+. Re-base them to an offset from
    # the start of the RLE block so the BBC build can place it anywhere.
    offs = [(((ptr_hi[i] << 8) | ptr_lo[i]) - RLE_START) for i in range(16)]
    if any(o < 0 or o >= len(rle) for o in offs):
        sys.exit('ERROR: deck pointer outside the RLE block: %r' % offs)

    path = OUT_DIR / 'levels.asm'
    with open(path, 'w') as f:
        f.write(BANNER.format(
            name='levels.asm',
            desc='16 deck maps, RLE encoded - byte-identical to the C64'))
        f.write('\n\\ Per-deck offsets into leveldata (re-based from C64 $F249)\n')
        f.write('.deckOffsetLo\n')
        emit_bytes(f, [o & 0xFF for o in offs])
        f.write('.deckOffsetHi\n')
        emit_bytes(f, [(o >> 8) & 0xFF for o in offs])
        for n, label in enumerate(['deckY', 'deckX', 'deckHeight',
                                   'deckWidth', 'deckColour', 'deckDroids']):
            f.write('.%s\n' % label)
            emit_bytes(f, meta[n * 16:(n + 1) * 16])
        # ---- lift stops ----
        sh  = mem[LIFT_IDX2SH:LIFT_IDX2SH + LIFT_STOPS]
        lkd = mem[LIFT_POS_DECK:LIFT_POS_DECK + LIFT_STOPS]
        lpx = mem[LIFT_POS_X:LIFT_POS_X + LIFT_STOPS]
        lpy = mem[LIFT_POS_Y:LIFT_POS_Y + LIFT_STOPS]
        col = [((lpx[i] >> 2) + LIFT_TILE_DX) & 0xFF for i in range(LIFT_STOPS)]
        row = [((lpy[i] >> 2) + LIFT_TILE_DY) & 0xFF for i in range(LIFT_STOPS)]
        for i in range(1, LIFT_STOPS - 1):
            if not (0 <= col[i] < 64 and 0 <= row[i] < 16):
                sys.exit('ERROR: lift stop %d is outside the map: %d,%d'
                         % (i, col[i], row[i]))
        f.write('\n\\ Lift stops, as the TILE the platform occupies - the\n'
                '\\ +5/+2 from the C64 view origin is applied by the exporter.\n'
                '\\ Index 0 and 31 are its sentinels: shaft 8 matches no real\n'
                '\\ shaft, which is what stops a lift at the end of its run.\n')
        f.write('.liftTileCol\n')
        emit_bytes(f, col)
        f.write('.liftTileRow\n')
        emit_bytes(f, row)
        f.write('.liftDeck\n')
        emit_bytes(f, lkd)
        f.write('.liftShaft\n')
        emit_bytes(f, sh)

        f.write('\n.leveldata\n')
        emit_bytes(f, rle)
        f.write('.leveldata_end\n')
    print('  levels.asm    %5d bytes RLE + %d bytes metadata'
          % (len(rle), len(meta) + 32))

    print('\nWrote to %s' % OUT_DIR)


if __name__ == '__main__':
    main()
