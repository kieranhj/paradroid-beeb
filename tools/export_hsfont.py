#!/usr/bin/env python3
"""
export_hsfont.py - the glyphs and strings DoHighScore carries in PARTITL.

Emits src/data/hsfont.asm.

WHY THE TITLE OVERLAY CARRIES ITS OWN ALPHABET
----------------------------------------------
Layer 11f puts the high-score entry in the PARTITL overlay, which is
assembled over PARAFNT's ground at &3000 -- so by the time it runs, the
text font's glyph table is gone and only what PARTITL brought with it is
readable. That is the same argument the title screen already makes for
its own 36 characters (layer-11 [DECISION 8]).

What survives the PARTITL load, and is used rather than duplicated:

  FontCell   at the top of the PARAFNT file, ABOVE the overlay's end, so
             the 1bpp -> MODE 1 expansion is the game's own routine and
             this file supplies only the bits. main.asm's
             `ASSERT titl_end <= FONTCODE_ADDR` is what keeps it true.

WHAT IS IN HERE
---------------
    0-25    capitals A-Z, LEFT half
    26-51   capitals A-Z, RIGHT half
    52+     everything else the three strings actually use, in the order
            they first appear, plus the space and the full stop the
            initials field needs whether a string mentions them or not

The capitals are all 26 and in fixed places because the INITIALS are
chosen at run time and the entry indexes them directly. Everything else
is computed from the strings, so re-wording one re-picks the set and
nothing needs maintaining by hand. That matters here: the overlay has to
end below FontCell, and carrying the full lowercase alphabet put it 80
bytes over.

Capitals are sixteen pixels and lowercase m and w are too -- DrawChar
($0C5F) is where the original says so, and export_font.py's header has
the whole story, including why capital I is narrow and why m and w sit
outside the a-z run. The plotter tests for exactly those three cases, so
a wide letter's right half is emitted beside it; a wide letter no string
uses gets index 255, which the test can never match.

THE STRINGS ARE HERE TOO, in these indices, converted from the C64's
$E733 / $E742 / $E714 -- and checked back against the listing as ASCII
before they are written.
"""

import sys
import importlib.util
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OUT = PROJECT / 'src' / 'data' / 'hsfont.asm'

# The three DrawString records DoHighScore draws, by address.
RECORDS = [
    ('hsTxtGreat',  0xE733, 'Great Score!'),
    ('hsTxtLowest', 0xE742, 'Lowest Score of the Day!'),
    ('hsTxtEnter',  0xE714, 'Please enter your initials -'),
]

HS_UPPER, HS_UPPER_R, HS_EXTRA = 0, 26, 52

# The wide lowercase pair and their right halves, and capital I, which is
# narrow -- export_font.py's header has the why for all three.
WIDE_RIGHT = {0x42: 0x62, 0x54: 0x74}
NARROW_UPPER = 0x16
C64_UPPER = {8: NARROW_UPPER}


def load_font_tools():
    spec = importlib.util.spec_from_file_location(
        'ef', PROJECT / 'tools' / 'export_font.py')
    ef = importlib.util.module_from_spec(spec)
    sys.modules['ef'] = ef
    try:
        spec.loader.exec_module(ef)
    except SystemExit:
        pass
    return ef


def ef_char(c):
    """C64 text-font code -> ASCII, for the round-trip assertion."""
    if c <= 9:
        return chr(48 + c)
    if 0x0A <= c <= 0x23:
        return chr(97 + c - 0x0A)
    if 0x3A <= c <= 0x53:
        return chr(65 + c - 0x3A)
    return {0x30: ' ', 0x28: '.', 0x2A: ':', 0x2E: '-', 0x25: '!',
            0x16: 'I', 0x42: 'm', 0x54: 'w'}[c]


def read_record(mem, addr):
    """The C64 DrawString record at addr -> (row, col, [codes])."""
    row, col = mem[addr], mem[addr + 1]
    i, codes = addr + 2, []
    while True:
        c = mem[i]
        if codes and c & 0x80:
            break
        codes.append(c & 0x7F)
        i += 1
        assert len(codes) < 64
    return row, col, codes


def main():
    ef = load_font_tools()
    mem = ef.load_memory()

    records = []
    for label, addr, text in RECORDS:
        row, col, codes_s = read_record(mem, addr)
        got = ''.join(ef_char(c) for c in codes_s)
        assert got == text, ('record $%04X reads %r, expected %r'
                             % (addr, got, text))
        records.append((label, addr, text, row, col, codes_s))

    # glyph index -> C64 code of its 8 x 16 cell. The capitals are fixed;
    # everything else is whatever the strings ask for.
    codes = []
    for i in range(26):                                   # capitals, left
        codes.append(C64_UPPER.get(i, 0x3A + i))
    for i in range(26):                                   # capitals, right
        codes.append(0x30 if i in C64_UPPER else 0x3A + 0x20 + i)

    # A space and a full stop are wanted by the initials field whether a
    # string mentions them or not: $E4E7 sets two slots to full stops and
    # the record's tail is three spaces.
    extra = [0x30, 0x28]
    for _, _, _, _, _, scodes in records:
        for c in scodes:
            if 0x3A <= c <= 0x53 or c == NARROW_UPPER:
                continue                                  # a capital
            if c not in extra:
                extra.append(c)
            right = WIDE_RIGHT.get(c)
            if right is not None and right not in extra:
                extra.append(right)
    codes += extra

    def to_index(code):
        if 0x3A <= code <= 0x53:
            return HS_UPPER + (code - 0x3A)
        if code == NARROW_UPPER:
            return HS_UPPER + 8
        return HS_EXTRA + extra.index(code)

    def opt(code):
        """Index of code, or 255 when it is not carried at all."""
        return HS_EXTRA + extra.index(code) if code in extra else 255

    bs = chr(92)
    out = []
    out.append(bs + ' ============================================================')
    out.append(bs + ' hsfont.asm - GENERATED by tools/export_hsfont.py, do not edit')
    out.append(bs + ' ============================================================')
    out.append(bs + ' The alphabet DoHighScore carries into the PARTITL overlay,')
    out.append(bs + ' because PARTITL is assembled over the text font. 1bpp, 16')
    out.append(bs + ' bytes a glyph - top cell then bottom - which is what FontCell')
    out.append(bs + ' expands, eight bytes at a time. See the exporter header.')
    out.append('')
    out.append('HS_GLYPHS   = %d' % len(codes))
    out.append('HS_UPPER    = %d' % HS_UPPER)
    out.append('HS_UPPER_R  = %d' % HS_UPPER_R)
    out.append('HS_SPACE    = %d' % opt(0x30))
    out.append('HS_DOT      = %d' % opt(0x28))
    out.append('HS_UPPER_I  = HS_UPPER + 8      ' + bs + ' narrow, a bare stem')
    out.append(bs + ' 255 where a wide lowercase is used by no string, so the')
    out.append(bs + " plotter's test for it can never match.")
    out.append('HS_LOWER_M  = %d' % opt(0x42))
    out.append('HS_M_RIGHT  = %d' % opt(0x62))
    out.append('HS_LOWER_W  = %d' % opt(0x54))
    out.append('HS_W_RIGHT  = %d' % opt(0x74))
    out.append('')
    out.append('.hsGlyphs')
    for idx, code in enumerate(codes):
        rows = ef.glyph_rows(mem, code)
        assert len(rows) == 16
        try:
            what = "'%s'" % ef_char(code)
        except KeyError:
            what = 'right half'      # capitals' right halves have no code of their own
        out.append('  ' + bs + ' %2d  $%02X  %s' % (idx, code, what))
        out.append('  EQUB ' + ', '.join('&%02X' % b for b in rows[:8]))
        out.append('  EQUB ' + ', '.join('&%02X' % b for b in rows[8:]))
    out.append('.hsGlyphs_end')
    out.append('ASSERT hsGlyphs_end - hsGlyphs == HS_GLYPHS * 16')
    out.append('')
    out.append(bs + ' ---- the three strings, $E733 / $E742 / $E714 -------------')
    out.append(bs + " In THIS file's indices. A capital is ONE index and the")
    out.append(bs + ' plotter draws its right half; so are lowercase m and w.')
    for label, addr, text, row, col, codes_s in records:
        idxs = [to_index(c) for c in codes_s] + [0xFF]
        out.append('')
        out.append(bs + ' row %d col %d  "%s"' % (row, col, text))
        out.append('.%s' % label)
        for j in range(0, len(idxs), 8):
            out.append('  EQUB ' + ', '.join(
                '&FF' if v == 0xFF else str(v) for v in idxs[j:j + 8]))
    out.append('')

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text('\n'.join(out) + '\n')
    print('wrote %s' % OUT)
    print('  %d glyphs, %d bytes: 52 capitals + %d picked from the strings'
          % (len(codes), len(codes) * 16, len(extra)))


if __name__ == '__main__':
    main()
