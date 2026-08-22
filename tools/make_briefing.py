#!/usr/bin/env python3
"""
make_briefing.py - src/data/briefing.txt -> src/data/briefing.asm.

The build-time half of the briefing pipeline (see export_briefing.py's
header for the split, and docs/layer-11f-frontend.md for the layer).
briefing.txt is the hand-editable source of the intro manual's text;
this tool converts it every build - build.ps1 runs it before beebasm -
and validates it, so a hand edit cannot silently overflow a page or use
a character no glyph exists for.

WHAT IT EMITS
-------------
Records indexed by canvas row, for the bank-5 PARMAN block. No canvas:
the C64's UpackText unpacks into a 15.5 K staging canvas and the port
renders straight from the record lists instead. [11f DECISION 3]

    brRowLo/Hi   (page, row) -> row list, over pages 0-4 and the global
                 row range BR_ROW_LO..BR_ROW_HI
    a row list   (col, glyph indices..., $FE) per record, then $FF
    brExtra      bitmaps for the characters the shared font lacks; the
                 renderer plots any index >= BR_XTRA0 from here
    .br_<name>   a label on each `label`-tagged record (the score lines)

A record occupies the row it names AND the one below - the top cells of
its 8 x 16 glyphs, then the bottom ones - so painting canvas row r is
row r's list drawn top-half plus row r-1's list drawn bottom-half.
THE LINES ARE NOT EVENLY SPACED (page 1 steps three rows a line, later
pages two), which is why the index is by canvas row and not by line.

GLYPH INDICES are the shared font's, from export_font.py's order:
capitals are two cells wide (left at 11+i, right at +26) EXCEPT capital
I, and lowercase m and w are wide too (rights at 100/101) - DrawChar's
own rule, which the renderer applies; the emitted list holds one index
per character. The round-trip check at the end decodes what was emitted
back to ASCII and diffs it against the input, so a mapping slip cannot
survive.
"""

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
SRC = PROJECT / 'src' / 'data' / 'briefing.txt'
OUT = PROJECT / 'src' / 'data' / 'briefing.asm'

PAGE_COLS = 40

# The shared font's layout - export_font.py's order, checked against
# panel.asm's PN_* constants.
PN_SPACE, PN_DIGIT0, PN_UPPER_A, PN_LOWER_A = 0, 1, 11, 63
PN_DOT, PN_DASH, PN_COLON, PN_BANG = 89, 98, 99, 102
PN_GLYPHS = 103                 # what the shared font actually has
PN_CAP_RIGHT = 26               # a capital's right half is left + 26
PN_M_RIGHT, PN_W_RIGHT = 100, 101

WIDE = set('ABCDEFGHJKLMNOPQRSTUVWXYZmw')   # capitals minus I, plus m and w


def to_glyph(ch, extras):
    if ch == ' ':
        return PN_SPACE
    if '0' <= ch <= '9':
        return PN_DIGIT0 + ord(ch) - 48
    if 'A' <= ch <= 'Z':
        return PN_UPPER_A + ord(ch) - 65
    if 'a' <= ch <= 'z':
        return PN_LOWER_A + ord(ch) - 97
    fixed = {'.': PN_DOT, '-': PN_DASH, ':': PN_COLON, '!': PN_BANG}
    if ch in fixed:
        return fixed[ch]
    if ch in extras:
        return extras[ch][0]
    raise SystemExit("briefing.txt: no glyph for %r - allowed: a-z A-Z 0-9 "
                     "space . , : ; ' - ! (and any `glyph` line's character)"
                     % ch)


def parse(path):
    pages, extras, labels = {}, {}, {}
    page, label, order = None, None, []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        if s.startswith('page '):
            page = int(s[5:]) - 1
            if not 0 <= page <= 4:
                raise SystemExit('briefing.txt:%d: page must be 1-5' % n)
            continue
        if s.startswith('label '):
            label = s[6:].strip()
            continue
        if s.startswith('glyph '):
            ch, hexs = s[6:7], s[8:].strip()
            data = bytes.fromhex(hexs)
            if len(data) != 16:
                raise SystemExit('briefing.txt:%d: glyph wants 16 hex bytes'
                                 % n)
            extras[ch] = (PN_GLYPHS + len(extras), data)
            continue
        if '|' not in line:
            raise SystemExit('briefing.txt:%d: no | before the text' % n)
        if page is None:
            raise SystemExit('briefing.txt:%d: record before any page' % n)
        head, text = line.split('|', 1)
        try:
            row, col = (int(t) for t in head.split())
        except ValueError:
            raise SystemExit('briefing.txt:%d: want ROW COL |text' % n)
        rec = (col, text, label, n)
        label = None
        pages.setdefault(page, {}).setdefault(row, []).append(rec)
        order.append((page, row, rec))
    return pages, extras, order


def main():
    pages, extras, order = parse(SRC)

    # validate width against the page, counting wide characters twice
    for page, row, (col, text, label, n) in order:
        width = sum(2 if c in WIDE else 1 for c in text)
        if col + width > PAGE_COLS:
            raise SystemExit(
                'briefing.txt:%d: line is %d cells from column %d, past the '
                "page's %d (capitals except I, and m and w, are two cells)"
                % (n, width, col, PAGE_COLS))

    row_lo = min(r for p in pages.values() for r in p)
    row_hi = max(r for p in pages.values() for r in p)
    npages = max(pages) + 1

    bs = chr(92)
    out = []
    out.append(bs + ' ============================================================')
    out.append(bs + ' briefing.asm - GENERATED by tools/make_briefing.py')
    out.append(bs + ' ============================================================')
    out.append(bs + ' From src/data/briefing.txt, the hand-editable text. Edit THAT')
    out.append(bs + ' and rebuild; do not edit this. Format and rules: the tool.')
    out.append('')
    out.append('BR_PAGES     = %d' % npages)
    out.append('BR_ROW_LO    = %d' % row_lo)
    out.append('BR_ROW_HI    = %d' % row_hi)
    out.append('BR_ROWS      = BR_ROW_HI - BR_ROW_LO + 1')
    out.append('')
    out.append(bs + ' Characters the shared font has not got; the renderer plots an')
    out.append(bs + ' index of BR_XTRA0 or above from brExtra, not from the font.')
    out.append('BR_XTRA0     = %d' % PN_GLYPHS)
    out.append('')
    out.append(bs + ' A row list is (col, glyphs..., $FE) per record, then $FF.')
    out.append(bs + ' Rows with nothing on them are one byte: $FF.')
    out.append('')

    # Split per page so every runtime index stays 8-bit: BR_ROWS rows a
    # page rather than BR_PAGES * BR_ROWS. The driver looks a page's two
    # arrays up through brPageLLo/LHi (the LO arrays) and brPageHLo/HHi
    # (the HI arrays), then indexes them by row - BR_ROW_LO.
    entries = [(p, r) for p in range(npages) for r in range(row_lo, row_hi + 1)]
    for p in range(npages):
        out.append('.brRowLo_%d' % p)
        for r in range(row_lo, row_hi + 1):
            out.append('  EQUB LO(brRow_%d_%d)' % (p, r))
        out.append('.brRowHi_%d' % p)
        for r in range(row_lo, row_hi + 1):
            out.append('  EQUB HI(brRow_%d_%d)' % (p, r))
    out.append('.brPageLLo')
    for p in range(npages):
        out.append('  EQUB LO(brRowLo_%d)' % p)
    out.append('.brPageLHi')
    for p in range(npages):
        out.append('  EQUB HI(brRowLo_%d)' % p)
    out.append('.brPageHLo')
    for p in range(npages):
        out.append('  EQUB LO(brRowHi_%d)' % p)
    out.append('.brPageHHi')
    for p in range(npages):
        out.append('  EQUB HI(brRowHi_%d)' % p)
    out.append('')

    total, emitted = 0, []          # (glyphs, text) for the round-trip
    for p, r in entries:
        out.append('.brRow_%d_%d' % (p, r))
        for col, text, label, n in sorted(pages.get(p, {}).get(r, [])):
            gl = [to_glyph(c, extras) for c in text]
            emitted.append((gl, text))
            if label:
                out.append('.br_%s' % label)
            out.append('  ' + bs + ' "%s"' % text)
            out.append('  EQUB %d' % col)
            for j in range(0, len(gl), 12):
                out.append('  EQUB ' + ', '.join(str(v) for v in gl[j:j + 12]))
            out.append('  EQUB &FE')
            total += 2 + len(gl)
        out.append('  EQUB &FF')
        total += 1
    out.append('')

    out.append('.brExtra')
    for ch, (idx, data) in sorted(extras.items(), key=lambda kv: kv[1][0]):
        out.append('  ' + bs + ' %r = index %d' % (ch, idx))
        out.append('  EQUB ' + ', '.join('&%02X' % b for b in data[:8]))
        out.append('  EQUB ' + ', '.join('&%02X' % b for b in data[8:]))
    out.append('')

    OUT.write_text(chr(10).join(out) + chr(10))

    # THE CHECK THAT MATTERS: decode the emitted indices back to ASCII
    # through an inverse map and diff against the input, record for
    # record. A slip in to_glyph shows up here and nowhere else.
    inv = {PN_SPACE: ' ', PN_DOT: '.', PN_DASH: '-', PN_COLON: ':',
           PN_BANG: '!'}
    for d in range(10):
        inv[PN_DIGIT0 + d] = chr(48 + d)
    for i in range(26):
        inv[PN_UPPER_A + i] = chr(65 + i)
        inv[PN_LOWER_A + i] = chr(97 + i)
    for ch, (idx, _) in extras.items():
        inv[idx] = ch
    bad = sum(1 for gl, text in emitted
              if ''.join(inv[g] for g in gl) != text)
    if bad:
        raise SystemExit('%d records do not round-trip' % bad)

    print('make_briefing: %d records, %d pages, rows %d-%d; '
          '%d bytes of lists + %d index + %d glyphs; round-trip clean'
          % (len(emitted), npages, row_lo, row_hi,
             total, len(entries) * 2 + 4 * npages, 16 * len(extras)))


if __name__ == '__main__':
    main()
