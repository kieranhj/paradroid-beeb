#!/usr/bin/env python3
"""
export_bbc.py - Convert Paradroid C64 data to BeebASM source for the BBC port.

Emits into src/data/:
  charset.asm   - the $7800 charset converted to BBC MODE 1 (256 chars, 16 bytes each)
  tiledefs.asm  - the 32 tile definitions from $E800 (4x4 char codes, byte-identical)
  levels.asm    - deck pointer table, per-deck metadata and RLE map data (byte-identical)

MODE 1 conversion
-----------------
The play area runs in C64 HIRES character mode. $D016 bit 4 is the
multicolour flag and the self-modifying _d016Mode routine at $6F1B patches
its own LDA operand: $C0 (hires) for the play area and the text screens,
$D0 (multicolour) only for the transfer board ($22AD) and the ship
sideview ($3092). Entering the game goes through _reenter_game ($1532),
which writes $C0 and $D018 = $2F - the $7800 tile charset - and jumps to
EnterGame. So the deck is hires and nothing in it is multicolour.

A hires cell is eight 1-bit pixels: a set bit takes the cell's colour from
colour RAM, using the FULL four-bit nibble (0-15), and a clear bit takes
$D021, the shared background. $D022/$D023 are not involved; DrawSideview
sets them for its own multicolour screen and they simply persist.

That is a straight 1:1 to BBC MODE 1, which is also 320 pixels across: 8
C64 pixels become 8 MODE 1 pixels, 4 to a byte. MODE 1 packs pixel n with
bit (7-n) as its high colour bit and bit (3-n) as its low bit.

    left  byte of a scanline = C64 pixels 0-3
    right byte of a scanline = C64 pixels 4-7

BBC screen memory groups 4 pixels x 8 scanlines into 8 consecutive bytes, so
a character occupies 16 contiguous bytes: the left half's 8 scanlines then
the right half's 8. Characters are stored in that order, making a plot a
straight 16-byte copy to the screen.

THIS FILE READ THE SCREEN AS MULTICOLOUR UNTIL 2026-08-18, selecting the
mode per cell on bit 3 of the colour nibble. That theory was invented to
explain four colours in a cell and it is wrong: bit 3 is part of the
colour. It made every cell whose colour was 8-15 - orange, dark grey,
light grey - render as four fat pixels of the wrong colours, and mangled
the ALERT lettering on eight decks. ref/c64_deck5.png settles it: light
grey floor, ORANGE crosshairs (colour 8, bit 3 set) drawn solid, and
"ALERT." crisp at single-pixel spacing.

The real loss is smaller than the old model claimed: the C64 gives each
CELL its own colour from sixteen, and MODE 1 has four logical colours for
the whole screen. Per deck that turns out to be enough - the tiles a deck
places use the background plus three colours and little else.

Requires: Python 3. No third-party dependencies.
"""

import json
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
D022 = 1                # multicolour 01 - white
D023 = 0                # multicolour 10 - black

# $D021, the play-area background, is PER DECK - it is slot 0 of the deck's
# colour record. See deck_background() below. It was a hard-coded 14 here
# until 2026-08-17, which was right for decks 2 and 7 and wrong for the
# other fourteen.

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

# Aesthetic preferences, honoured when the colour is still free. These were
# chosen against the old multicolour reading and want re-judging in the lab
# now the decks look like the C64's: light blue floors to blue rather than a
# glaring cyan, and yellow floors to magenta rather than BBC yellow.
PREFERRED = {14: 4, 7: 5}


PALETTE_FILE = Path(__file__).resolve().parent / 'deck_palettes.json'


def load_palette_override():
    """Hand-chosen palettes from tools/palette_lab.py, if they exist.

    The automatic assignment below is a starting point, not the answer: MODE 1
    gives four colours where the C64 gives sixteen, so which four a deck ends
    up with is a judgement made by eye. palette_lab.py is where that judgement
    is made and this is where it enters the build.

    A malformed file is fatal rather than ignored. A palette silently reverting
    to the automatic one would look exactly like a build that worked.
    """
    if not PALETTE_FILE.exists():
        return {}
    try:
        decks = json.loads(PALETTE_FILE.read_text()).get('decks', {})
    except (ValueError, OSError) as e:
        sys.exit('ERROR: %s: %s' % (PALETTE_FILE.name, e))

    out = {}
    for key, rec in decks.items():
        try:
            d = int(key)
        except ValueError:
            sys.exit('ERROR: %s: deck key %r is not a number'
                     % (PALETTE_FILE.name, key))
        if not 0 <= d < 16:
            sys.exit('ERROR: %s: deck %d out of range' % (PALETTE_FILE.name, d))
        clean = {}
        phys = rec.get('physical')
        if phys is not None:
            if len(phys) != 4 or not all(
                    isinstance(v, int) and 0 <= v < 8 for v in phys):
                sys.exit('ERROR: %s: deck %d physical must be 4 values 0-7, '
                         'got %r' % (PALETTE_FILE.name, d, phys))
            clean['physical'] = list(phys)
        cmap = rec.get('colourMap')
        if cmap is not None:
            if len(cmap) != 16 or not all(
                    isinstance(v, int) and 0 <= v < 4 for v in cmap):
                sys.exit('ERROR: %s: deck %d colourMap must be 16 values 0-3, '
                         'got %r' % (PALETTE_FILE.name, d, cmap))
            clean['colourMap'] = list(cmap)
        if clean:
            out[d] = clean
    return out


# Which SLOT gets to choose its physical colour first. Slot order and
# allocation order are different things, and conflating them is what made the
# C64's black come out green: the assignment is greedy nearest-unused, so
# whoever picks first wins a contested colour.
#
#   3 white       the sprites are drawn in it and the walls are made of it,
#                 and it has to read as white, so it picks first
#   0 the floor   the largest area on screen by far
#   1 darker      \ the deck's own two, and the pair with the most room to
#   2 lighter     / move: they are already a compromise for a C64 colour
SLOT_PRIORITY = (3, 0, 1, 2)


def assign_palette(logical):
    """Pick a distinct BBC physical colour for each of the four logical ones.

    A fixed C64->BBC table cannot work: several C64 colours share a nearest
    BBC match, so two logical colours collapse onto one physical and whatever
    is drawn in the second becomes invisible. Assigning greedily per deck,
    nearest-unused first, guarantees four distinct colours.

    Returned in SLOT order; allocated in SLOT_PRIORITY order.
    """
    out, taken = [None] * 4, set()
    for slot in SLOT_PRIORITY:
        c64 = logical[slot]
        want = PREFERRED.get(c64)
        if want is not None and want not in taken:
            out[slot] = want
            taken.add(want)
            continue
        r, g, b = C64_RGB[c64]
        best = min((p for p in range(8) if p not in taken),
                   key=lambda p: (BBC_RGB[p][0] - r) ** 2
                   + (BBC_RGB[p][1] - g) ** 2 + (BBC_RGB[p][2] - b) ** 2)
        out[slot] = best
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


def _deck_colour_freq(mem, cell_colour):
    """How often each C64 colour appears in the tiles, over the whole set.

    The deck-weighted count needs the RLE and is done by the caller in
    palette_lab; here the tile set is representative enough and keeps this
    function dependency-free.
    """
    from collections import Counter
    freq = Counter()
    for tile in range(TILEDEF_COUNT):
        for i in range(TILEDEF_SIZE):
            freq[cell_colour(mem[TILEDEF_ADDR + tile * TILEDEF_SIZE + i])] += 1
    return freq


def deck_background(mem, deck):
    """The play area's $D021 for a deck: SLOT 0 of its colour record.

    Traced 2026-08-17. InitColors ($27E5) copies the deck's 12-slot record to
    clr0_top_d020 with Y counting 11 down to 0, so the accumulator is left
    holding slot 0, and $2821 stores that in Irq1bgColor. The gameplay raster
    chain's third stage, Irq_118 ($6F4C), writes Irq1bgColor to $D021 and
    switches $D018 to $2F - the $7800 tile charset - for the 128 lines of play
    area. So slot 0 is the floor colour, and it differs per deck: only decks 2
    and 7 are the light blue this was once hard-coded to. Confirmed against
    ref/c64_deck0.png, whose floor is light grey (scheme 0, slot 0 = 15).

    Not to be confused with bgColor, which InitColors sets from slot 3 and
    Irq_91 uses for the band ABOVE the play area, nor with the status area,
    which Irq_254 draws on a fixed white ($F1) background.
    """
    scheme = mem[DECKSCHEME + deck]
    return mem[RECORDS + scheme * REC_LEN]


def build_logical_map(mem, cell_colour, bg):
    """Pick which C64 colours become MODE 1 logical 0-3, in FIXED ROLES.

        logical 0 = the deck's background      (%00 - also transparent)
        logical 1 = its darker foreground      (%01 - the low plane alone)
        logical 2 = its lighter foreground     (%10 - the high plane alone)
        logical 3 = white                      (%11 - both planes)

    Logical 3 is white and holds the sprites, which is KC's ordering and the
    reason the slots have roles at all: artwork exported at logical 3 has both
    bits set on an opaque pixel and neither on a transparent one, so a sprite
    byte IS its own transparency mask, and AND &0F / AND &F0 recolour it in
    place to logical 1 or 2. It is also faithful - the C64 draws the player
    white (ref/c64_deck5.png).

    The other two are the deck's own next-most-used colours, ordered dark then
    light by luminance so that masking a sprite to 1 always gives the darker
    option and to 2 the lighter, whatever deck it is standing on.

    Counted over the tiles a deck ACTUALLY PLACES, weighted by how often it
    places them, rather than over the whole tile set: what matters is what is
    on the screen. Every deck comes out wanting the background plus three
    colours, so nothing is merged - the fourth is used 2 to 40 times against
    the third's hundreds or thousands.
    """
    from collections import Counter
    from rip_levels import decode_deck_rle           # noqa: F401 (see below)
    freq = _deck_colour_freq(mem, cell_colour)
    freq.pop(bg, None)

    white = D022                                     # 1, and it is white
    rest = [c for c, _ in freq.most_common() if c != white]
    while len(rest) < 2:
        rest.append(0 if 0 not in rest else 2)
    a, b = rest[0], rest[1]
    dark, light = (a, b) if LUMA[a] <= LUMA[b] else (b, a)

    chosen = [bg, dark, light, white]

    # If the background IS white the roles would collide and a slot would be
    # unreachable. No deck does that, but take the next unused rather than
    # ship a colour that can never be selected.
    seen = set()
    for i, c in enumerate(chosen):
        if c in seen:
            spare = [x for x in rest + list(range(16)) if x not in seen]
            chosen[i] = spare[0] if spare else c
        seen.add(chosen[i])
    return chosen, freq


def build_colour_map(logical):
    """C64 colour 0-15 -> MODE 1 logical 0-3, for one deck.

    Precomputed here so the 6502 needs no search, and emitted as .colourMap.
    A colour that is not one of the four keeps the nearest by luminance - which
    is the merge, and the place a deck wanting five colours loses one.

    tools/palette_lab.py imports this: the rule must have ONE definition, or a
    preview drifts from what the build actually draws.
    """
    out = []
    for c64 in range(16):
        if c64 in logical:
            out.append(logical.index(c64))
        else:
            out.append(min(range(4),
                           key=lambda i: abs(LUMA[logical[i]] - LUMA[c64])))
    return out


def convert_charset(mem, cell_colour, logical):
    """C64 charset -> MODE 1, 16 bytes per char. Every cell is HIRES.

    Eight 1-bit pixels: a set bit takes the cell's colour, a clear bit the
    deck's background. See the header for why there is no multicolour path.
    """
    def logical_of(c64):
        if c64 in logical:
            return logical.index(c64)
        return min(range(4), key=lambda i: abs(LUMA[logical[i]] - LUMA[c64]))

    bg = logical_of(logical[0])          # logical 0 is the background
    out = bytearray()
    stats = {'hires': 0, 'multi': 0}
    for c in range(CHARSET_CHARS):
        rows = mem[CHARSET_ADDR + c * 8:CHARSET_ADDR + c * 8 + 8]
        fg = logical_of(cell_colour(c))
        stats['hires'] += 1
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
    override = load_palette_override()
    colour_map = bytearray()
    deck_pal = bytearray()
    deck_bg = bytearray()
    deck_logicals = []
    for d in range(16):
        scheme, rec, cell_colour = deck_colours(mem, d)
        bg = deck_background(mem, d)
        deck_bg.append(bg)
        logical, freq = build_logical_map(mem, cell_colour, bg)
        deck_logicals.append(logical)
        dmap = build_colour_map(logical)
        dpal = assign_palette(logical)
        chosen = override.get(d, {})
        dmap = chosen.get('colourMap', dmap)
        dpal = chosen.get('physical', dpal)
        colour_map.extend(dmap)
        deck_pal.extend(dpal)
        if d == DECK:
            print('  deck %d -> scheme %d -> logical %s'
                  % (d, scheme, ', '.join('%d=%s' % (i, names[c])
                                          for i, c in enumerate(logical))))

    schemes = bytearray()
    for s in range(8):
        schemes.extend(mem[RECORDS + s * REC_LEN:RECORDS + (s + 1) * REC_LEN])

    # ---- the console's deck plan (con_DeckInfo, $3001) ------------------
    # DrawPacked places each level-RLE code AND $7F as a CHARACTER on the
    # console screen, which conRedraw put in HIRES mode (GotoHires, $C0
    # into _d016Mode) -- so every cell renders hires with colour RAM's
    # full 4-bit value as foreground, the multicolour flag included as a
    # colour bit, over the deck's background. The codes run $00-$1E (all
    # sixteen streams verified) and 28 of them the tiles never touch, so
    # the plan gets its own bank-7 data: the raw bitmaps, and a per-deck
    # ink table baking the whole C64 colour chain -- CharColor slot ->
    # deck record (slots 12-15 read the zeroed block after the record on
    # the C64, so >= 12 is genuinely colour 0) -> the deck's logical.
    # ONE DEVIATION, KC's ruling 2026-08-17: the console characters
    # $10-$13 draw in C64 red (colour 2), not their slot's colour, which
    # is black or brown on most decks and illegible.
    PLAN_CODES = 0x1F
    plan_chars = mem[CHARSET_ADDR:CHARSET_ADDR + PLAN_CODES * 8]
    plan_ink = bytearray()
    for d in range(16):
        scheme = mem[DECKSCHEME + d]
        for code in range(32):
            if code >= PLAN_CODES:
                plan_ink.append(0)
                continue
            slot = mem[CHARCOLOR + code] >> 4
            colour = mem[RECORDS + scheme * REC_LEN + slot] if slot < REC_LEN else 0
            if 0x10 <= code <= 0x13:
                colour = 2
            ink = colour_map[d * 16 + colour]
            # Legibility guard for the 4-colour compromise: a glyph whose
            # C64 colour is NOT the background must not map onto logical 0
            # (our plan background) just because that was nearest by luma
            # -- the C64 shows it low-contrast, we would show nothing.
            # Take the nearest of logicals 1-3 instead.
            logical = deck_logicals[d]
            if ink == 0 and colour != logical[0]:
                ink = min(range(1, 4),
                          key=lambda i: abs(LUMA[logical[i]] - LUMA[colour]))
            plan_ink.append(ink)

    path = OUT_DIR / 'plandata.asm'
    with open(path, 'w') as f:
        f.write(BANNER.format(
            name='plandata.asm',
            desc='the deck plan: C64 bitmaps for codes $00-$1E and the '
                 'per-deck ink table, deck*32 + code -> logical 0-3'))
        f.write('\n.planChars\n')
        emit_bytes(f, plan_chars)
        f.write('\nALIGN &100\n.planInk\n')
        emit_bytes(f, plan_ink)
    print('  plandata.asm  %5d bytes (%d plan chars + 16 deck ink rows)'
          % (len(plan_chars) + len(plan_ink), PLAN_CODES))

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
        f.write('\n.deckBg\n')
        f.write('\\ $D021 per deck - slot 0 of the deck\'s colour record.\n'
                '\\ BuildCharset indexes colourMap with this rather than a\n'
                '\\ constant: only decks 2 and 7 are the light blue the port\n'
                '\\ used to assume for all sixteen.\n')
        emit_bytes(f, deck_bg)
        f.write('\n.deckPalette\n')
        emit_bytes(f, deck_pal)
        f.write('\nALIGN &100\n.colourMap\n')
        emit_bytes(f, colour_map)
    print('  colours.asm   %5d bytes%s'
          % (len(schemes) + 16 + len(deck_pal) + 256,
             '' if not override else
             '  [%s: %d deck(s) hand-set]' % (PALETTE_FILE.name, len(override))))

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
