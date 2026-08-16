#!/usr/bin/env python3
"""
export_font.py - Convert the C64 Paradroid text font at $7000 to BBC MODE 1.

Emits src/data/textfont.asm.

THE FONT IS 8 x 16, NOT 8 x 8
-----------------------------
The $7000 charset stores a glyph's top half at code c and its bottom half
at code c + $80. Rendered, the map is:

    $00-$09   digits 0-9
    $0A-$23   lowercase a-z BY POSITION, but see the m/w/I note below:
              $16 is capital I and $20 is a symbol
    $28       full stop     $29 comma    $2A colon    $2B semicolon
    $2E       DASH -- the separator in "Blk-Whte" and "robo-stores"
    $30       space
    $31-$37   the PARADROID LOGO, nine cells wide
    $3A-$53   capitals A-Z BY POSITION, but $42 is lowercase m
    $54       lowercase w, wide
    $55-$59   status box frame, wide (right half at +$20)
    $7A-$7C   status box frame, narrow

confirmed against Mobile_txt at $698A, which reads $46 $18 $0B $12 $15 $0E
= M o b i l e.

THE STATUS BOX, AND WHY THE FRAME IS EXPORTED AS HALF GLYPHS
------------------------------------------------------------
StartGame draws the whole status area with four DrawString calls:

    $6900  Y=0 X=0    $55 + 18 x $56 + $57            top border
    $6917  Y=2 X=0    $7C, 14 spaces, the logo, spaces
    $6937  Y=2 X=38   space, $7C                      right edge
    $693C  Y=4 X=0    $58 + 18 x $59 + $7A $7B        bottom border

$55-$59 are inside DrawChar's "wide" range so each is 16 px and occupies
two cells; $7A, $7B and $7C are 8 px. That fills screen rows 0-5, but the
INK does not: the top border's glyphs are solid for their whole top half
and only start curving in their bottom half, and the bottom border's are
the mirror of that. The box therefore runs from scanline 8 to scanline
39 -- exactly 32 scanlines -- with solid surround above and below it.

So the port takes 32 scanlines, four BBC character rows:

    row 0   the BOTTOM halves of $55/$75, $56/$76, $57/$77
    rows 1-2  the text line: $7C bars, mode word, logo, score
    row 3   the TOP halves of $58/$78, $59/$79, $7A, $7B

A half glyph is 8 px by 8 scanlines, which is ONE MODE 1 cell of 16
bytes, so the twelve distinct border pieces are emitted as a separate
192-byte `panelframe` table rather than as 32-byte font glyphs.

MODE 1 CONVERSION
-----------------
A MODE 1 character cell is 8 pixels wide by 8 scanlines and occupies 16
bytes: the left half's 8 scanlines then the right half's. An 8 x 16 glyph
is therefore TWO stacked cells, 32 bytes, and that is how each glyph is
emitted -- top cell first, then bottom.

MODE 1 packs 4 pixels per byte; pixel n takes bit (7-n) as its high colour
bit and bit (3-n) as its low bit. The source is 1bpp, so a set pixel gets
both bits and comes out as logical colour 3.

GLYPH INDEX
-----------
The port indexes glyphs 0-101 rather than by C64 code, so the table is
contiguous and PnAscii can map ASCII onto it with four compares:

    0        space
    1-10     digits 0-9
    11-36    capitals A-Z, LEFT half
    37-62    capitals A-Z, RIGHT half
    63-88    lowercase a-z
    89       full stop
    90-96    the logo, cells 0-6 ($31-$37)
    97       the box's vertical bar ($7C)

then, separately, `panelframe`: twelve 16-byte border cells.

NOTHING HERE IS SYNTHESISED. The two energy-bar cells that used to sit at
90 and 91 are gone along with the energy bar itself -- the C64 has no such
readout, so there was nothing to be faithful to and it is not shown.
"""

import sys
import importlib.util
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OUT = PROJECT / 'src' / 'data' / 'textfont.asm'

FONT_BASE = 0x7000

# CAPITALS ARE 16 PIXELS WIDE, and DrawChar ($0C5F) is where that is
# stated: having written the code and code|$80 for the two rows, it does
#
#     AND #$7F : CMP #$3A : BCC _1 : CMP #$5A : BCS _1   ; see if it was wide
#     LDY #1 : ADC #$20 : STA (cpyDest),Y ...            ; ...and if so
#     INC prntX                                          ; two columns
#
# so a capital at code c has its RIGHT half at c + $20 and occupies two
# character cells. Lowercase and digits are 8 px and occupy one. The port
# keeps that: a capital is exported as two glyphs, left and right, and
# PnStr draws the second whenever the first is in the capital range —
# exactly DrawChar's own test.
#
# THREE CODES ARE NOT WHERE THE ALPHABET PUTS THEM, and ToUpper ($2E3D) is
# where the original says so. It converts lowercase to wide capitals and
# special-cases exactly these before falling back to "capital = lowercase
# + $30":
#
#     CMP #$54 : BEQ _1     ; 'w' is $54, and its capital is $50
#     CMP #$42 : BEQ _2     ; 'm' is $42, and its capital is $46
#     CMP #$12 : BEQ _3     ; 'i' $12 -> capital I is $16, not $42
#     CMP #$16 : BEQ _x     ; and $16 is already that capital
#     CMP #$A : BCC _x : CMP #$24 : BCS _x : ADC #$30
#
# so LOWERCASE m AND w ARE 16 PX WIDE and live at $42 and $54, outside the
# a-z run; the $16 and $20 slots where they would sit hold CAPITAL I --
# which is narrow, being a bare stem -- and a symbol. Render $42 and $46
# side by side and they are the same double-arch shape, one lowercase and
# one capital, which is the giveaway.
#
# This file had m, w and I all wrong, and the full stop as $2E. $2E is the
# DASH: it is the separator in "Blk/Whte" ($69D8), in the deck name
# "robo-stores", and on the console's own "Unit type 001 - Influence
# device" line, where ShowRobotType prints it as token 50. The full stop
# is $28 -- the low dot that $29 (comma) and $2B (semicolon) are built
# from by adding a tail.
#
# None of it ever showed, because no word on the panel -- Mobile, Weapon,
# Transfer, Console -- contains m, w, capital I or a full stop.
C64_LOWER = {12: 0x42, 22: 0x54}        # m and w, wide and out of line
C64_UPPER = {8: 0x16}                   # capital I, narrow and out of line

# glyph index -> C64 code of the TOP-LEFT cell
GLYPHS = []
GLYPHS.append(('space', 0x30))
for d in range(10):
    GLYPHS.append((f"'{d}'", 0x00 + d))
for i in range(26):
    GLYPHS.append((f"'{chr(65+i)}' left", C64_UPPER.get(i, 0x3A + i)))
for i in range(26):
    # Capital I has no right half. Space fills the slot so the index stays
    # LEFT + 26 for every capital and PnWide needs one test, not a table.
    GLYPHS.append((f"'{chr(65+i)}' right",
                   0x30 if i in C64_UPPER else 0x3A + 0x20 + i))
for i in range(26):
    GLYPHS.append((f"'{chr(97+i)}'", C64_LOWER.get(i, 0x0A + i)))
GLYPHS.append(("'.'", 0x28))
# The logo. $6917 draws it as $31 $32 $33 $32 $34 $33 $35 $36 $37 -- nine
# cells from seven distinct glyphs, two of them used twice.
for i in range(7):
    GLYPHS.append(('logo cell %d' % i, 0x31 + i))
GLYPHS.append(('box bar', 0x7C))

# The console's punctuation, and the right halves of the two wide
# lowercase letters. They go on the end rather than in the alphabet so
# that a-z stays a contiguous run PnAscii can index arithmetically.
GLYPHS.append(("'-'", 0x2E))            # token 50, and "robo-stores"
GLYPHS.append(("':'", 0x2A))            # "Ship  :" at $6E12
GLYPHS.append(("'m' right", 0x62))
GLYPHS.append(("'w' right", 0x74))

# The order $6917 draws the logo in, as indices into the seven glyphs above.
LOGO_SEQ = [0, 1, 2, 1, 3, 2, 4, 5, 6]

# The twelve border cells, each ONE MODE 1 cell of 16 bytes. 'bot' takes
# the glyph's TOP half (source rows 0-7), 'top' its BOTTOM half (rows
# 8-15) -- see the header: the box's ink is the inner half of each.
#   name, C64 code, which half
FRAME = [
    ('top-left  L', 0x55, 'lower'),
    ('top-left  R', 0x75, 'lower'),
    ('top-mid   L', 0x56, 'lower'),
    ('top-mid   R', 0x76, 'lower'),
    ('top-right L', 0x57, 'lower'),
    ('top-right R', 0x77, 'lower'),
    ('bot-left  L', 0x58, 'upper'),
    ('bot-left  R', 0x78, 'upper'),
    ('bot-mid   L', 0x59, 'upper'),
    ('bot-mid   R', 0x79, 'upper'),
    ('bot-end 1  ', 0x7A, 'upper'),
    ('bot-end 2  ', 0x7B, 'upper'),
]


def load_memory():
    spec = importlib.util.spec_from_file_location('rg', PROJECT / 'tools' / 'rip_graphics.py')
    rg = importlib.util.module_from_spec(spec)
    sys.modules['rg'] = rg
    try:
        spec.loader.exec_module(rg)
    except SystemExit:
        pass
    mem, _ = rg.parse_listing(rg.LST_FILE)
    return mem


def glyph_rows(mem, code):
    """16 rows of 1bpp, top half then bottom half."""
    if code is None:
        return None
    top = [mem[FONT_BASE + code * 8 + r] for r in range(8)]
    bot = [mem[FONT_BASE + (code + 0x80) * 8 + r] for r in range(8)]
    return top + bot


def cell_bytes(rows8):
    """One MODE 1 cell: 8 scanlines of 8 pixels -> 16 bytes, left half then right."""
    left, right = [], []
    for row in rows8:
        lo = hi = 0
        for n in range(4):
            if row & (0x80 >> n):
                lo |= (0x80 >> n) | (0x08 >> n)
            if row & (0x08 >> n):
                hi |= (0x80 >> n) | (0x08 >> n)
        left.append(lo)
        right.append(hi)
    return left + right


def main():
    mem = load_memory()
    out = []
    out.append('\\ ============================================================')
    out.append('\\ textfont.asm - GENERATED by tools/export_font.py, do not edit')
    out.append('\\ ============================================================')
    out.append('\\ The C64 text font at $7000, converted to MODE 1.')
    out.append('\\')
    out.append('\\ IT IS 8 x 16, NOT 8 x 8: the glyph top half is at C64 code c and')
    out.append('\\ its bottom half at c + $80. A MODE 1 cell is 8 x 8 in 16 bytes, so')
    out.append('\\ a glyph is TWO STACKED CELLS, 32 bytes - top cell then bottom. That')
    out.append('\\ is why the four-row panel holds ONE line of text with a border row')
    out.append('\\ above it and another below.')
    out.append('\\')
    out.append('\\ CAPITALS ARE 16 PX WIDE, right half at C64 code + $20, which is')
    out.append('\\ DrawChar\'s own arrangement at $0C82 — "see if it was wide". Each is')
    out.append('\\ exported as two glyphs and PnStr draws the second when the first')
    out.append('\\ falls in the capital range. Lowercase and digits are 8 px, one cell.')
    out.append('\\')
    out.append('\\ Glyph index, contiguous so PnAscii can map ASCII with four compares:')
    out.append('\\   0 space, 1-10 digits, 11-36 capitals LEFT, 37-62 capitals RIGHT,')
    out.append('\\   63-88 lowercase, 89 full stop, 90-96 the LOGO, 97 the box bar.')
    out.append('\\ NOTHING IS SYNTHESISED: every byte below is the C64\'s own artwork.')
    out.append('')
    out.append("\ Declared here and checked against main.asm's FONT_GLYPHS and")
    out.append('\ FONT_BYTES, which have to come first: beebasm resolves constants in')
    out.append('\ file order and droid.asm asserts on the font size before this file.')
    out.append('GEN_FONT_GLYPHS = %d' % len(GLYPHS))
    out.append('GEN_FONT_BYTES  = %d' % (len(GLYPHS) * 32))
    out.append('GEN_FRAME_CELLS = %d' % len(FRAME))
    out.append('GEN_FRAME_BYTES = %d' % (len(FRAME) * 16))
    out.append('')
    out.append('.textfont')

    for idx, (name, code) in enumerate(GLYPHS):
        rows = glyph_rows(mem, code)
        data = cell_bytes(rows[:8]) + cell_bytes(rows[8:])
        assert len(data) == 32
        out.append('  \\ %2d  %s' % (idx, name))
        for half in (0, 16):
            out.append('  EQUB ' + ', '.join('&%02X' % b for b in data[half:half + 16]))

    out.append('.textfont_end')
    out.append('ASSERT textfont_end - textfont == GEN_FONT_BYTES')
    out.append('ASSERT GEN_FONT_GLYPHS == FONT_GLYPHS')
    out.append('ASSERT GEN_FONT_BYTES  == FONT_BYTES')
    out.append('')

    # ---- the twelve border cells ------------------------------------
    out.append('\\ ------------------------------------------------------------')
    out.append('\\ panelframe - the status box border, twelve MODE 1 cells')
    out.append('\\ ------------------------------------------------------------')
    out.append('\\ HALF glyphs, 16 bytes each, not 32: the box is 32 scanlines and')
    out.append('\\ the border rows contribute only their inner 8. Row 0 of the panel')
    out.append('\\ is cells 0,1 then 18 x (2,3) then 4,5; row 3 is 6,7 then')
    out.append('\\ 18 x (8,9) then 10, 11 - which is $6900 and $693C exactly.')
    out.append('.panelframe')
    for idx, (name, code, half) in enumerate(FRAME):
        rows = glyph_rows(mem, code)
        data = cell_bytes(rows[:8] if half == 'upper' else rows[8:])
        assert len(data) == 16
        out.append('  \\ %2d  %s  ($%02X %s half)' % (idx, name, code, half))
        out.append('  EQUB ' + ', '.join('&%02X' % b for b in data))
    out.append('.panelframe_end')
    out.append('ASSERT panelframe_end - panelframe == GEN_FRAME_BYTES')
    out.append('ASSERT GEN_FRAME_CELLS == PN_FRAME_CELLS')
    out.append('ASSERT GEN_FRAME_BYTES == PN_FRAME_BYTES')
    out.append('')

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text('\n'.join(out) + '\n')
    print(f'wrote {OUT}  ({len(GLYPHS)} glyphs, {len(GLYPHS)*32} bytes'
          f' + {len(FRAME)} frame cells, {len(FRAME)*16} bytes)')

    # sanity: report which glyphs came out blank, which would mean a bad map
    # 'I' right is deliberately the space glyph -- capital I is narrow.
    blank = [(i, n, c) for i, (n, c) in enumerate(GLYPHS)
             if c != 0x30 and not any(glyph_rows(mem, c))]
    if blank:
        print('WARNING blank glyphs:', blank)
    else:
        print('no blank glyphs except space')

    # sanity: the logo, drawn the way $6917 draws it, as ASCII art
    print('\nthe logo, $31 $32 $33 $32 $34 $33 $35 $36 $37:')
    cells = [glyph_rows(mem, 0x31 + i) for i in range(7)]
    for r in range(16):
        print('  ' + ''.join(
            ''.join('#' if cells[s][r] & (0x80 >> b) else '.' for b in range(8))
            for s in LOGO_SEQ))


if __name__ == '__main__':
    main()
