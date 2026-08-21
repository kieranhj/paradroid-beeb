#!/usr/bin/env python3
"""
export_briefing.py - the intro manual's text, for Layer 11f's briefing.

Emits src/data/briefing.asm.

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

WHAT THIS PORT DOES INSTEAD
---------------------------
No canvas. The records are sorted by text line here and emitted with a
per-line index, so "paint canvas row R" is a walk of one short list and
the 15.5 K staging area is simply gone. That is a removal of C64
machinery the port has no use for, in the same spirit as the ZX0 deck
maps replacing the RLE. [11f DECISION 3]

Decoded, the canvas is:

    stride     256 bytes; a text line is TWO canvas rows
    rows       $82-$BB, so text lines 1 to 29
    columns    five pages of 40, at column 2 + 40n

so a page is 40 characters of 8 px = 320 px, which is exactly the port's
play area, and the only scrolling needed is vertical. Horizontal is not a
scroll at all: $122B jump-cuts to the next page.

GLYPHS
------
Port glyph indices, the same mapping export_strings.py uses -- the
briefing runs after TitleSeq has reloaded PARAFNT, so the real font is
resident and none of it needs carrying. TWO characters are missing from
that font, because export_bbc.py converts only what a TILE references:

    comma ($29) and apostrophe ($2D)

They are emitted here as two extra glyph bitmaps with indices above the
font's own, for the renderer to plot from its own data. See BR_EXTRA0.

TEXT OVERRIDES
--------------
Page 5 prints the C64's pause-key legend -- RUN/STOP, CLR/HOME, f7, f8 --
and none of those keys exist on a Beeb, so the page would print a lie.
OVERRIDES replaces or drops records by address; what the replacement says
is KC's, at the time. [11f DECISION 9]
"""

import sys
import importlib.util
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OUT = PROJECT / 'src' / 'data' / 'briefing.asm'

TEXT_BASE = 0xD000
PAGE_COLS = 40
PAGE_COL0 = 2

# Port glyph indices, from export_font.py's order.
PN_SPACE, PN_DIGIT0, PN_UPPER_A, PN_LOWER_A = 0, 1, 11, 63
PN_DOT, PN_DASH, PN_COLON, PN_BANG = 89, 98, 99, 102
PN_UPPER_I = PN_UPPER_A + 8
PN_LOWER_M = PN_LOWER_A + 12
PN_LOWER_W = PN_LOWER_A + 22
PN_GLYPHS = 103                 # what the shared font actually has

# The two the shared font has not got, carried by the briefing itself.
BR_COMMA, BR_APOS = PN_GLYPHS, PN_GLYPHS + 1

SPECIAL = {
    0x16: PN_UPPER_I,
    0x42: PN_LOWER_M,
    0x54: PN_LOWER_W,
    0x25: PN_BANG,
    0x28: PN_DOT,
    0x29: BR_COMMA,             # NOT in the shared font
    0x2A: PN_COLON,
    0x2D: BR_APOS,              # NOT in the shared font either
    0x2E: PN_DASH,
    0x30: PN_SPACE,
}

# Records to replace or drop, by their address in the C64 text. None
# drops the record entirely. Nothing is overridden yet -- the pause keys
# are KC's wording when pause exists, and until then the two blocks that
# name them are dropped so the page does not print a lie.
OVERRIDES = {
    0xDDC3: None,               # "To pause: press run-stop."
    0xDDDF: None,               # "From pause mode only:"
    0xDDF7: None,               # "fire      - restarts,"
    0xDE0F: None,               # "run-stop  - restarts,"
    0xDE27: None,               # "clr-home - quits game,"
    0xDE40: None,               # "f7        - cheese,"
    0xDE56: None,               # "f8        - pause."
}


def to_glyph(code):
    if code in SPECIAL:
        return SPECIAL[code]
    if code <= 0x09:
        return PN_DIGIT0 + code
    if 0x0A <= code <= 0x23:
        return PN_LOWER_A + (code - 0x0A)
    if 0x3A <= code <= 0x53:
        return PN_UPPER_A + (code - 0x3A)
    raise KeyError('no glyph for C64 code $%02X' % code)


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
    mem = load_memory()
    records = read_records(mem)

    kept, dropped = [], 0
    for addr, hi, lo, codes in records:
        if addr in OVERRIDES:
            if OVERRIDES[addr] is None:
                dropped += 1
                continue
            codes = [c for c in OVERRIDES[addr]]
        kept.append((addr, hi, lo, codes))

    # canvas row -> page + the records that START on it. A record spans
    # rows R and R+1 - the top cells of its glyphs then the bottom ones -
    # so painting canvas row r means the records at r drawn top-half and
    # the records at r-1 drawn bottom-half. THE LINES ARE NOT EVENLY
    # SPACED: page 1 steps three canvas rows a line and the later pages
    # two, so this is indexed by row and not by any notion of line.
    rows = {}
    for addr, hi, lo, codes in kept:
        row = hi - 0x80
        page, col = divmod(lo - PAGE_COL0, PAGE_COLS)
        assert 0 <= page <= 4, 'record $%04X is on page %d' % (addr, page)
        rows.setdefault((page, row), []).append((col, codes, addr))

    pages = sorted({p for p, _ in rows})
    row_lo = min(r for _, r in rows)
    row_hi = max(r for _, r in rows)

    bs = chr(92)
    out = []
    out.append(bs + ' ============================================================')
    out.append(bs + ' briefing.asm - GENERATED by tools/export_briefing.py')
    out.append(bs + ' ============================================================')
    out.append(bs + " The intro manual's text, $D000-$DED0, as records indexed by")
    out.append(bs + ' the canvas row they start on. No canvas: see the exporter')
    out.append(bs + ' header and docs/layer-11f-frontend.md.')
    out.append('')
    out.append('BR_PAGES     = %d' % len(pages))
    out.append('BR_ROW_LO    = %d' % row_lo)
    out.append('BR_ROW_HI    = %d' % row_hi)
    out.append('BR_ROWS      = BR_ROW_HI - BR_ROW_LO + 1')
    out.append('BR_COL0      = %d' % PAGE_COL0)
    out.append(bs + ' A record occupies the row it names AND the one below it: the')
    out.append(bs + ' top cells of its 8 x 16 glyphs, then the bottom ones. So a')
    out.append(bs + ' row is painted from ITS list top-half and the PREVIOUS list')
    out.append(bs + ' bottom-half, which is what UpTextChar does with its dest+$100.')
    out.append('')
    out.append(bs + ' The two glyphs the shared font has not got. The renderer plots')
    out.append(bs + ' an index of BR_COMMA or above from brExtra, not from the font.')
    out.append('BR_COMMA     = %d' % BR_COMMA)
    out.append('BR_APOS      = %d' % BR_APOS)
    out.append('')
    out.append(bs + ' A row list is (col, glyphs..., $FE) per record, then $FF.')
    out.append(bs + ' Rows with nothing on them are one byte: $FF.')
    out.append('')

    entries = [(p, r) for p in pages for r in range(row_lo, row_hi + 1)]
    out.append('.brRowLo')
    for p, r in entries:
        out.append('  EQUB LO(brRow_%d_%d)' % (p, r))
    out.append('.brRowHi')
    for p, r in entries:
        out.append('  EQUB HI(brRow_%d_%d)' % (p, r))
    out.append('')

    total = 0
    for p, r in entries:
        out.append('.brRow_%d_%d' % (p, r))
        for col, codes, addr in sorted(rows.get((p, r), [])):
            text = ''.join(to_text(c) for c in codes)
            out.append('  ' + bs + ' $%04X  "%s"' % (addr, text))
            gl = [to_glyph(c) for c in codes]
            out.append('  EQUB %d' % col)
            for j in range(0, len(gl), 12):
                out.append('  EQUB ' + ', '.join(str(v) for v in gl[j:j + 12]))
            out.append('  EQUB &FE')
            total += 2 + len(gl)
        out.append('  EQUB &FF')
        total += 1
    out.append('')

    out.append(bs + ' ---- the two missing glyphs, 1bpp, 16 bytes each ----------')
    out.append(bs + ' export_bbc.py converts only what a TILE references, so the')
    out.append(bs + ' comma and the apostrophe are in no deck and therefore in no')
    out.append(bs + ' charset. They are $29 and $2D of the $7000 text font.')
    out.append('.brExtra')
    for name, code in (('comma $29', 0x29), ('apostrophe $2D', 0x2D)):
        grows = glyph_rows(mem, code)
        out.append('  ' + bs + ' ' + name)
        out.append('  EQUB ' + ', '.join('&%02X' % b for b in grows[:8]))
        out.append('  EQUB ' + ', '.join('&%02X' % b for b in grows[8:]))
    out.append('')

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(chr(10).join(out) + chr(10))

    print('wrote %s' % OUT)
    print('  %d records (%d dropped by OVERRIDES), %d pages, rows %d-%d'
          % (len(kept), dropped, len(pages), row_lo, row_hi))
    print('  %d bytes of text and lists + %d index + 32 glyphs'
          % (total, len(entries) * 2))

    # THE CHECK THAT MATTERS: take the glyph indices that were just
    # emitted, decode them back to ASCII through an INVERSE of the map,
    # and diff against the C64's own text record for record. A slip in
    # to_glyph shows up here and nowhere else.
    inv = {0: ' ', PN_DOT: '.', PN_DASH: '-', PN_COLON: ':',
           PN_BANG: '!', BR_COMMA: ',', BR_APOS: "'"}
    for d in range(10):
        inv[PN_DIGIT0 + d] = chr(48 + d)
    for i in range(26):
        inv[PN_UPPER_A + i] = chr(65 + i)
        inv[PN_LOWER_A + i] = chr(97 + i)

    bad = []
    for addr, hi, lo, codes in kept:
        want = ''.join(to_text(c) for c in codes)
        got = ''.join(inv[to_glyph(c)] for c in codes)
        if want != got:
            bad.append((addr, want, got))
    if bad:
        for addr, want, got in bad[:5]:
            print('  MISMATCH $%04X' % addr)
            print('    C64  %r' % want)
            print('    ours %r' % got)
        raise SystemExit('%d records do not round-trip' % len(bad))
    print('  round-trip: all %d records decode back to the C64 text' % len(kept))


if __name__ == '__main__':
    main()
