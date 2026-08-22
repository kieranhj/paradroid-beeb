#!/usr/bin/env python3
"""
export_briefing.py - decode the C64 intro manual ONCE, into briefing.txt.

THIS TOOL IS THE ONE-SHOT HALF OF A TWO-STAGE PIPELINE. KC, 2026-08-22:
the briefing text should be exported once into a file that can be edited
by hand, and THAT file is the build input. So:

    export_briefing.py   C64 listing -> src/data/briefing.txt   (run ONCE)
    make_briefing.py     briefing.txt -> src/data/briefing.asm  (every build)

Because briefing.txt may carry KC's hand edits, this tool REFUSES to
overwrite it unless given --force. Losing edits to a casual re-run is the
failure mode this guards against; there is no other reason to re-run it.

The text is kept VERBATIM, the C64's pause-key legend included - KC,
2026-08-22: worry about the wording later, in the text file, by hand.

WHAT THE C64 HAS
----------------
$D000-$DED0, 3,792 bytes read by UpackText ($3C14). The format is a run
of records, each

    byte 0   canvas row      (AND $3F, OR $80 -> $80..$BF)
    byte 1   canvas column
    byte 2+  characters, terminated by a bit-7 byte

and a record whose terminator arrives before byte 4 ends the whole text.
UpackText unpacks them into a 15.5 K character canvas at $8000 with a
stride of 256, writing each character TWICE - code c at dest and c OR $80
one row below - because the text font is 8 x 16. UpTextChar ($3C4E)
writes a SECOND COLUMN for any code in $3A-$59: capitals are 16 px, which
is DrawChar's own rule and export_font.py's header has the why.

Decoded, the canvas is:

    stride     256 bytes; a text line is TWO canvas rows
    rows       $82-$BB, so canvas rows 2 to 59
    columns    five pages of 40, at column 2 + 40n

so a page is 40 characters of 8 px = 320 px, exactly the port's play
area, and the only scrolling needed is vertical. Horizontal is not a
scroll at all: $122B jump-cuts to the next page.

THE OUTPUT FORMAT is make_briefing.py's input and its header documents
it; the short version is one record a line, `row col |text`, grouped
under `page N` headings, with `label` naming the next record and `glyph`
carrying the bitmaps of characters the shared font has not got.

The two SCORE-TABLE lines on page 5 ($DD89, $DDB4) are labelled hiscore
and loscore: the driver patches them from bank 7's table at load time,
which is UpdateTextScore's job moved to the read side. [11f DECISION 7]
"""

import sys
import importlib.util
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OUT = PROJECT / 'src' / 'data' / 'briefing.txt'

TEXT_BASE = 0xD000
PAGE_COLS = 40
PAGE_COL0 = 2

# The two records UpdateTextScore ($E5AC) patches in place: the high and
# low score lines of page 5. The driver needs to find them, so they are
# labelled in the output.
LABELS = {0xDD89: 'hiscore', 0xDDB4: 'loscore'}

# Characters the shared font has not got, whose bitmaps therefore ride in
# briefing.txt as `glyph` lines: comma, apostrophe, semicolon. export_bbc
# converts only what a TILE references and no deck uses any of the three.
# Semicolon is included although the C64 text happens not to use it, so a
# hand edit may - the glyphs cost 16 bytes each in a bank with 12K spare.
EXTRA_GLYPHS = [(',', 0x29), ("'", 0x2D), (';', 0x2B)]


def to_text(code):
    # THE SPECIALS COME FIRST, and that is not cosmetic: $16 is capital I
    # sitting in lowercase m's arithmetic slot and $42 is lowercase m in
    # capital I's, so a range check that runs first renders both swapped.
    # export_font.py's header has the story. Written the other way round,
    # this decodes "In addition" as "mn addition" -- which is exactly what
    # the round-trip caught.
    out = {0x30: ' ', 0x28: '.', 0x29: ',', 0x2A: ':', 0x2B: ';',
           0x2D: "'", 0x2E: '-', 0x25: '!', 0x16: 'I', 0x42: 'm',
           0x54: 'w'}.get(code)
    if out is not None:
        return out
    if code <= 9:
        return chr(48 + code)
    if 0x0A <= code <= 0x23:
        return chr(97 + code - 0x0A)
    if 0x3A <= code <= 0x53:
        return chr(65 + code - 0x3A)
    raise KeyError('no text for C64 code $%02X' % code)


def load_memory():
    spec = importlib.util.spec_from_file_location(
        'rg', PROJECT / 'tools' / 'rip_graphics.py')
    rg = importlib.util.module_from_spec(spec)
    sys.modules['rg'] = rg
    try:
        spec.loader.exec_module(rg)
    except SystemExit:
        pass
    mem, _ = rg.parse_listing(rg.LST_FILE)
    return mem


def read_records(mem):
    """UpackText's own walk. -> [(addr, row, col, [codes])]"""
    src, out = TEXT_BASE, []
    while True:
        hi = (mem[src] & 0x3F) | 0x80
        lo = mem[src + 1]
        y, codes = 2, []
        while y < 0x80:
            c = mem[src + y]
            y += 1
            if c & 0x80:
                break
            codes.append(c)
        if y < 4:                       # $3C3D: an empty record ends it
            break
        out.append((src, hi, lo, codes))
        src += y
    return out


def glyph_rows(mem, code):
    """The 8 x 16 glyph at a $7000 text-font code, 1bpp, 16 bytes."""
    base = 0x7000
    top = [mem[base + code * 8 + r] for r in range(8)]
    bot = [mem[base + ((code + 0x80) & 0xFF) * 8 + r] for r in range(8)]
    return top + bot


def main():
    force = '--force' in sys.argv
    if OUT.exists() and not force:
        raise SystemExit(
            '%s exists and may carry hand edits - re-run with --force '
            'only if you really mean to regenerate it from the C64 text'
            % OUT)

    mem = load_memory()
    records = read_records(mem)

    # (page, row) -> records, exactly as the canvas holds them
    by_page = {}
    for addr, hi, lo, codes in records:
        row = hi - 0x80
        page, col = divmod(lo - PAGE_COL0, PAGE_COLS)
        assert 0 <= page <= 4, 'record $%04X is on page %d' % (addr, page)
        by_page.setdefault(page, []).append((row, col, addr, codes))

    out = []
    out.append('# briefing.txt - the intro manual, decoded from the C64 original.')
    out.append('# EDIT FREELY: this file is the build input. tools/make_briefing.py')
    out.append('# turns it into src/data/briefing.asm (build.ps1 runs it).')
    out.append('#')
    out.append('# Format, one record per line:')
    out.append('#   page N                   the records below are on page N (1-5)')
    out.append('#   ROW COL |text            canvas row (2-58), column (0-39), text.')
    out.append('#                            The | marks where the text starts, so')
    out.append('#                            leading spaces are unambiguous.')
    out.append('#   label NAME               names the NEXT record for the driver')
    out.append('#   glyph C XX..XX           the 8x16 bitmap of a character the shared')
    out.append('#                            font lacks: 32 hex bytes, top cell then')
    out.append('#                            bottom. Do not remove these.')
    out.append('#')
    out.append('# Rules make_briefing.py enforces:')
    out.append("#   characters: a-z A-Z 0-9 space . , : ; ' - !")
    out.append('#   capitals (except I) and m and w are 16 px wide, everything else 8,')
    out.append('#   and a line must fit its page: start column + width <= 40.')
    out.append('#   A text line occupies TWO canvas rows, so records on consecutive')
    out.append('#   rows overlap; the decoded text uses every OTHER row at least.')
    out.append('#')
    out.append('# The hiscore/loscore labels mark the lines the driver patches from')
    out.append("# the live table in bank 7, so their text here is only the default")
    out.append("# (Braybrook's own joke entries). Keep their shape if you edit them.")

    for page in sorted(by_page):
        out.append('')
        out.append('page %d' % (page + 1))
        for row, col, addr, codes in sorted(by_page[page]):
            text = ''.join(to_text(c) for c in codes)
            if addr in LABELS:
                out.append('label %s' % LABELS[addr])
            out.append('%2d %2d |%s' % (row, col, text))

    out.append('')
    out.append('# The bitmaps of the characters the shared font has not got, from')
    out.append("# the C64's $7000 text font. The renderer plots these from brExtra.")
    for ch, code in EXTRA_GLYPHS:
        rows = glyph_rows(mem, code)
        out.append('glyph %s %s' % (ch, ''.join('%02X' % b for b in rows)))
    out.append('')

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text('\n'.join(out) + '\n')

    n = sum(len(v) for v in by_page.values())
    print('wrote %s' % OUT)
    print('  %d records over %d pages, verbatim - the pause-key legend included'
          % (n, len(by_page)))


if __name__ == '__main__':
    main()
