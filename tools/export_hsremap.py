#!/usr/bin/env python3
"""
export_hsremap.py - the remap and strings DoHighScore uses in PARTITL.

Emits src/data/hsremap.asm.

IT USED TO BE A FONT, AND THAT IS THE POINT OF THIS FILE
--------------------------------------------------------
Layer 11f gave the high-score entry its OWN 72-glyph alphabet, 1,152
bytes of it, because PARTITL was assembled over PARAFNT's ground at
&3000: by the time the screen ran, the text font's glyph table had been
loaded over and only what PARTITL brought with it was readable.

no-load step 3 moved PARTITL off &3000 (docs/no-load.md §6), so the
text font survives the title and the alphabet is pure duplication --
ALL 72 GLYPHS ARE BYTE-IDENTICAL TO GLYPHS ALREADY IN textfont. They
are permuted rather than contiguous, which is why a block diff misses
them, so what ships now is a 72-BYTE REMAP into textfont's index space
and the assertion below is what keeps it honest: every run re-derives
both tables from the C64 listing and compares all 1,152 bytes.

1,152 bytes of overlay became 72. HsGlyph grew four bytes (TAX / LDA
hsRemap,X) and one base swap, and every wide-capital path inherits it
because HsWide does all its arithmetic in INDEX space before calling.

THE PRECONDITION, AND IT IS NOT CHECKABLE AT ASSEMBLY TIME:
PARAFNT MUST BE RESIDENT WHENEVER THE HIGH-SCORE SCREEN RUNS. It is:
HsRun only runs when hsArmed is set, which only a finished game does,
and GoTitle reaches TitleSeq through SetupPlain -- which exists
precisely because SetupMode's VDU 22 would clear &3000-&7FFF. At a
COLD boot PARAFNT has never been loaded, and that is safe for the same
reason it always was: hsArmed is zero, so nothing here is read.

What is used rather than duplicated:

  FontCell   at the top of the PARAFNT file, so the 1bpp -> MODE 1
             expansion is the game's own routine.
  textfont   at FONT_ADDR, which this file now indexes into.

WHAT IS IN HERE
---------------
    0-25    capitals A-Z, LEFT half
    26-51   capitals A-Z, RIGHT half
    52+     everything else the three strings actually use, in the order
            they first appear, plus the space and the full stop the
            initials field needs whether a string mentions them or not

The indices are unchanged from the font version -- they are the SCREEN's
index space, which the entry code walks arithmetically -- and hsRemap is
what turns one into a textfont glyph.

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
OUT = PROJECT / 'src' / 'data' / 'hsremap.asm'

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


# THE THREE OUT-OF-LINE CODES ARE TESTED FIRST, and $16 is why: capital
# I sits INSIDE the $0A-$23 lowercase run, so the range test claimed it
# was 'm'. Nothing was ever wrong in the data -- no record contains a
# capital I -- but the remap table this tool now writes annotates every
# entry with its character, and that one came out as an 'm' beside a
# perfectly correct index. export_font.py's header has the whole story.
ODD_CODES = {0x30: ' ', 0x28: '.', 0x2A: ':', 0x2E: '-', 0x25: '!',
             0x16: 'I', 0x42: 'm', 0x54: 'w'}


def ef_char(c):
    """C64 text-font code -> ASCII, for the round-trip assertion."""
    if c in ODD_CODES:
        return ODD_CODES[c]
    if c <= 9:
        return chr(48 + c)
    if 0x0A <= c <= 0x23:
        return chr(97 + c - 0x0A)
    if 0x3A <= c <= 0x53:
        return chr(65 + c - 0x3A)
    raise KeyError(c)


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


def check_against_textfont(remap, want_rows):
    """The strong form: compare against the COMMITTED src/data/textfont.asm.

    The asserts above prove the two exporters agree about the listing.
    This proves the remap indexes the bytes that are actually on the
    disc, which is what the 6502 reads -- so a textfont.asm that was
    regenerated from a different listing, or hand-edited, is caught here
    rather than as a garbled word on the high-score screen.
    """
    import re
    src = (PROJECT / 'src' / 'data' / 'textfont.asm').read_text()
    tf, on = [], False
    for line in src.splitlines():
        s = line.strip()
        if s.startswith('.textfont'):
            on = True
            continue
        if on:
            if s.startswith('.'):
                break
            m = re.match(r'EQUB\s+(.*)$', s)
            if m:
                for tok in m.group(1).split(','):
                    tok = tok.strip()
                    tf.append(int(tok[1:], 16) if tok.startswith('&') else int(tok))
    assert tf, 'no .textfont bytes found in src/data/textfont.asm'
    for i, (j, want) in enumerate(zip(remap, want_rows)):
        got = tf[j * 16:(j + 1) * 16]
        assert got == want, (
            'screen glyph %d -> textfont %d: committed textfont.asm holds %s, '
            'the listing says %s' % (i, j, got, want))
    print('  identity checked: %d glyphs, %d bytes, against the committed '
          'textfont.asm' % (len(remap), len(remap) * 16))


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

    # THE IDENTITY, RE-DERIVED AND CHECKED EVERY RUN. remap[i] is the
    # textfont index whose 16 packed bytes ARE this screen's glyph i.
    # export_font.py's GLYPHS is the port's own index space, so the
    # lookup is by C64 code and the byte compare is what proves the two
    # exporters have not drifted apart.
    tf_index = {}
    for idx, (_, tf_code) in enumerate(ef.GLYPHS):
        tf_index.setdefault(tf_code, idx)      # first wins: space is 0,
                                               # not capital I's blank right half
    remap = []
    for i, code in enumerate(codes):
        assert code in tf_index, (
            'screen glyph %d is C64 code $%02X, which textfont does not carry'
            % (i, code))
        j = tf_index[code]
        assert ef.glyph_rows(mem, ef.GLYPHS[j][1]) == ef.glyph_rows(mem, code), (
            'screen glyph %d ($%02X) does not match textfont glyph %d'
            % (i, code, j))
        remap.append(j)
    check_against_textfont(remap, [ef.glyph_rows(mem, c) for c in codes])

    bs = chr(92)
    out = []
    out.append(bs + ' ============================================================')
    out.append(bs + ' hsremap.asm - GENERATED by tools/export_hsremap.py, do not edit')
    out.append(bs + ' ============================================================')
    out.append(bs + " DoHighScore's alphabet, as INDICES INTO textfont. It used to")
    out.append(bs + ' be 1,152 bytes of its own glyphs, because PARTITL was')
    out.append(bs + ' assembled over the text font; no-load step 3 moved PARTITL')
    out.append(bs + ' off &3000, so the font survives the title and all 72 were')
    out.append(bs + ' duplicates. The exporter re-derives both and compares every')
    out.append(bs + ' byte on every run. See its header, and HsGlyph.')
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
    out.append(bs + ' ---- screen glyph -> textfont glyph ------------------------')
    out.append(bs + ' 0-51 are uniformly index + 11, because textfont puts its own')
    out.append(bs + ' capitals at 11 and 37 and this screen puts them at 0 and 26.')
    out.append(bs + ' The table is emitted whole anyway: it costs 52 bytes of a')
    out.append(bs + ' bank that has room, and it means HsGlyph has ONE path.')
    out.append('.hsRemap')
    for j in range(0, len(remap), 8):
        chunk = remap[j:j + 8]
        codes_c = codes[j:j + 8]
        what = []
        for c in codes_c:
            try:
                what.append(ef_char(c))
            except KeyError:
                what.append('>')     # a capital's right half has no code of its own
        out.append('  EQUB ' + ', '.join('%3d' % v for v in chunk)
                   + '   ' + bs + ' %2d  %s' % (j, ' '.join(what)))
    out.append('.hsRemap_end')
    out.append('ASSERT hsRemap_end - hsRemap == HS_GLYPHS')
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
    print('  %d remap entries: 52 capitals + %d picked from the strings'
          % (len(codes), len(extra)))


if __name__ == '__main__':
    main()
