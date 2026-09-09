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
Records indexed by canvas row. No canvas: the C64's UpackText unpacks
into a 15.5 K staging canvas and the port renders straight from the
record lists instead. [11f DECISION 3]

src/data/briefing.asm IS NO LONGER THE SHIPPING FORM. Since no-load
step 5 the game reads the ZX0 page streams below; briefing.asm is
assembled into a block the disc throws away and exists ONLY as the
oracle tools/verify_brstreams.py diffs those streams against, so that
a bug in the blob builder cannot survive. brExtra moved out to its own
file for that reason: it IS shipped, and in the briefing's own bank.

    brRowLo/Hi   (page, row) -> row list, over pages 0-4 and the global
                 row range BR_ROW_LO..BR_ROW_HI
    a row list   (col, glyph indices..., $FE) per record, then $FF
    brExtra      bitmaps for the characters the shared font lacks; the
                 renderer plots any index >= BR_XTRA0 from here
    .br_<name>   a label on each `label`-tagged record (the score lines)

AND, SINCE no-load STEP 5, THE SAME PAGES AS ZX0 STREAMS. Each page is
assembled here, in Python, EXACTLY as beebasm lays it out above and ZX0'd
into src/data/brstreamN.asm, which main.asm places in whichever bank has
room; nothing spans a bank. A stream is THE ROW LISTS AND NOTHING ELSE
and depacks to BR_RECS = BR_BUF + 2 * BR_ROWS; the driver rebuilds
brRowLo/Hi at BR_BUF by walking the depacked page for its $FF row
terminators. Carrying the tables INSIDE the stream was the design of
docs/no-load.md 14d and it was measured against this one: 2,798 packed
against 2,466, so the scan is worth 332 bytes of bank for ~40 of code
(KC, 2026-09-09; 15d). The record addresses emitted below are therefore
still absolute and still correct by construction - only the tables that
point at them are built at run time.
The blobs are checked against beebasm's own output by
tools/verify_brstreams.py, which also runs the scan and checks the
pointers it derives, and each stream is round-tripped through
tools/zx0.py before it is written.

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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zx0                       # noqa: E402  - the round-trip check
import zx0tool                   # noqa: E402  - which compressor to run

PROJECT = Path(__file__).resolve().parent.parent
SRC = PROJECT / 'src' / 'data' / 'briefing.txt'
OUT = PROJECT / 'src' / 'data' / 'briefing.asm'
# The four shape constants go to their OWN file, included from main.asm's
# header rather than from the bank. beebasm resolves constant assignments
# in file order, and src/briefing.asm - the PARBRF overlay - is assembled
# ABOVE bank 6 now so that bank 6 can COPYBLOCK it, which is well before
# this data. Same numbers, defined once, just earlier. (2026-09-09)
OUT_CONST = PROJECT / 'src' / 'data' / 'briefconst.asm'
# ...and one ZX0 stream a page, each in its own file so main.asm can put
# it in whichever bank has room. no-load step 5.
OUT_STREAM = PROJECT / 'src' / 'data' / 'brstream%d.asm'
# brExtra is not in briefing.asm any more: that file is the VERIFICATION
# ORACLE now (see the header) and is assembled into a block the disc throws
# away, while these glyphs are read by the live renderer and have to be in
# the briefing's own bank.
OUT_EXTRA = PROJECT / 'src' / 'data' / 'brextra.asm'

# WHERE A DEPACKED PAGE LANDS, and the reason the pointer tables can ride
# inside the stream: the blob is assembled below as if it were AT this
# address, so brRowLo/Hi hold the addresses the page really will have.
# main.asm declares BR_BUF and ASSERTs it against BR_BUF_ASSUMED, which
# this tool writes into briefconst.asm - the two cannot drift.
# &4500 is 440 bytes clear of the briefing's measured high-water mark in
# the arena (docs/no-load.md 14b) and leaves 1,280 for the tables and the
# page together.
BR_BUF = 0x4500

PAGE_COLS = 40

# The text is nudged right so the WIDEST lines sit centred in the
# 40-cell window (KC, 2026-08-22): the widest record extent is 36
# cells, so two cells each side. Applied here, to the emitted columns,
# so the renderer stays a straight copy and the width check below
# guards the margin too.
MARGIN = 2

# The shared font's layout - export_font.py's order, checked against
# panel.asm's PN_* constants.
PN_SPACE, PN_DIGIT0, PN_UPPER_A, PN_LOWER_A = 0, 1, 11, 63
PN_DOT, PN_DASH, PN_COLON, PN_BANG = 89, 98, 99, 102
PN_QUERY = 103                  # $24, added 2026-08-27 for "Colour?"
PN_GLYPHS = 104                 # what the shared font actually has. KEEP
                                # THIS IN STEP WITH export_font.py: the
                                # extras below are numbered from it, so a
                                # stale value aliases the first extra onto
                                # a real glyph and the briefing silently
                                # draws the wrong character.
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
    fixed = {'.': PN_DOT, '-': PN_DASH, ':': PN_COLON, '!': PN_BANG,
             '?': PN_QUERY}
    if ch in fixed:
        return fixed[ch]
    if ch in extras:
        return extras[ch][0]
    raise SystemExit("briefing.txt: no glyph for %r - allowed: a-z A-Z 0-9 "
                     "space . , : ; ' - ! ? (and any `glyph` line's character)"
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


def page_blob(pages, extras, p, rows):
    """One page's row lists, EXACTLY as beebasm lays out briefing.asm's
    brRow_p_r, laid out at BR_RECS. The two pointer tables are NOT here:
    the driver rebuilds them by scanning for the $FF row terminators.
    Returns the bytes and {label: address}."""
    recs, labels = bytearray(), {}
    base = BR_BUF + 2 * len(rows)       # BR_RECS
    for r in rows:
        for col, text, label, n in sorted(pages.get(p, {}).get(r, [])):
            if label:
                labels[label] = base + len(recs)
            recs.append(col + MARGIN)
            recs += bytes(to_glyph(c, extras) for c in text)
            recs.append(0xFE)
        recs.append(0xFF)
    return bytes(recs), labels


def zx0_pack(raw, name):
    """The reference compressor, then tools/zx0.py's decompressor over
    what it wrote. make_disc.py does the same for the banks and for the
    same reason: the stream the 6502 depacker eats is zx0.py's format, so
    a compressor that drifted from it would ship silently. Which binary
    that is, tools/zx0tool.py decides - $ZX0, then bin/, then $PATH."""
    packed = zx0tool.run_zx0(zx0tool.find_zx0(), raw)
    if zx0.decompress(packed) != raw:
        raise SystemExit('%s: stream fails the zx0.py round-trip' % name)
    return packed


def main():
    pages, extras, order = parse(SRC)

    # validate width against the page, counting wide characters twice
    # and the centring margin once
    for page, row, (col, text, label, n) in order:
        width = sum(2 if c in WIDE else 1 for c in text)
        if MARGIN + col + width > PAGE_COLS:
            raise SystemExit(
                'briefing.txt:%d: line is %d cells from column %d plus the '
                "%d-cell margin, past the page's %d (capitals except I, and "
                'm and w, are two cells)'
                % (n, width, col, MARGIN, PAGE_COLS))

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
    out.append(bs + ' The shape constants are in src/data/briefconst.asm, which')
    out.append(bs + ' main.asm includes from its header - see OUT_CONST above.')
    out.append('')

    con = []
    con.append(bs + ' ============================================================')
    con.append(bs + ' briefconst.asm - GENERATED by tools/make_briefing.py')
    con.append(bs + ' ============================================================')
    con.append(bs + ' The briefing text\'s shape, and nothing else. Separate from')
    con.append(bs + ' briefing.asm because main.asm includes THIS from its header,')
    con.append(bs + ' ahead of the PARBRF overlay that reads it, while the data')
    con.append(bs + ' itself stays in the bank. Edit src/data/briefing.txt.')
    con.append('')
    con.append('BR_PAGES     = %d' % npages)
    con.append('BR_ROW_LO    = %d' % row_lo)
    con.append('BR_ROW_HI    = %d' % row_hi)
    con.append('BR_ROWS      = BR_ROW_HI - BR_ROW_LO + 1')
    con.append('')
    con.append(bs + ' Characters the shared font has not got; the renderer plots an')
    con.append(bs + ' index of BR_XTRA0 or above from brExtra, not from the font.')
    con.append('BR_XTRA0     = %d' % PN_GLYPHS)

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
            out.append('  EQUB %d' % (col + MARGIN))
            for j in range(0, len(gl), 12):
                out.append('  EQUB ' + ', '.join(str(v) for v in gl[j:j + 12]))
            out.append('  EQUB &FE')
            total += 2 + len(gl)
        out.append('  EQUB &FF')
        total += 1
    out.append('')

    out.append('.brRecEnd')     # tools/verify_brstreams.py's end marker
    out.append('')

    ex = []
    ex.append(bs + ' ============================================================')
    ex.append(bs + ' brextra.asm - GENERATED by tools/make_briefing.py')
    ex.append(bs + ' ============================================================')
    ex.append(bs + ' The characters the shared font has not got. The renderer')
    ex.append(bs + ' plots a glyph index of BR_XTRA0 or above from here rather')
    ex.append(bs + ' than from textfont, with this bank paged - so unlike the')
    ex.append(bs + ' page streams these bytes are read on the HOT path and must')
    ex.append(bs + " be in the briefing's own resting bank.")
    ex.append('')
    ex.append('.brExtra')
    for ch, (idx, data) in sorted(extras.items(), key=lambda kv: kv[1][0]):
        ex.append('  ' + bs + ' %r = index %d' % (ch, idx))
        ex.append('  EQUB ' + ', '.join('&%02X' % b for b in data[:8]))
        ex.append('  EQUB ' + ', '.join('&%02X' % b for b in data[8:]))
    ex.append('')
    OUT_EXTRA.write_text(chr(10).join(ex) + chr(10))

    OUT.write_text(chr(10).join(out) + chr(10))

    # ---- and the same pages as ZX0 streams (no-load step 5) ----
    # One file a page, so main.asm can put each in whichever bank has
    # room. The blob is the page AS IT WILL BE IN MAIN RAM, tables and
    # all; verify_brstreams.py checks it against what beebasm assembled.
    rows = list(range(row_lo, row_hi + 1))
    scores, raws, packs = {}, [], []
    for p in range(npages):
        blob, labels = page_blob(pages, extras, p, rows)
        packed = zx0_pack(blob, 'briefing page %d' % p)
        raws.append(blob)
        packs.append(packed)
        for name, addr in labels.items():
            scores[name] = (p, addr)
        st = []
        st.append(bs + ' ============================================================')
        st.append(bs + ' brstream%d.asm - GENERATED by tools/make_briefing.py' % p)
        st.append(bs + ' ============================================================')
        st.append(bs + " Briefing page %d, ZX0-packed: %d bytes -> %d."
                  % (p + 1, len(blob), len(packed)))
        st.append(bs + ' The row lists and nothing else. It depacks to BR_RECS and')
        st.append(bs + ' the driver rebuilds brRowLo/Hi at BR_BUF by scanning it for')
        st.append(bs + ' the $FF row terminators - 332 bytes cheaper across the five')
        st.append(bs + ' pages than carrying the tables in (docs/no-load.md 15d).')
        st.append(bs + ' Placed in a bank by main.asm; nothing here may span one.')
        st.append('.brStream_%d' % p)
        for j in range(0, len(packed), 16):
            st.append('  EQUB ' + ', '.join('&%02X' % b
                                            for b in packed[j:j + 16]))
        st.append('.brStream_%d_end' % p)
        st.append('')
        (Path(str(OUT_STREAM) % p)).write_text(chr(10).join(st) + chr(10))

    con.append('')
    con.append(bs + ' ---- no-load step 5: the pages as ZX0 streams ----')
    con.append(bs + " BR_BUF is main.asm's to declare - this is what the streams")
    con.append(bs + ' were assembled against, and main.asm ASSERTs the two agree.')
    con.append('BR_BUF_ASSUMED = &%04X' % BR_BUF)
    con.append(bs + " The largest page's row lists, unpacked, for the arena ASSERT.")
    con.append('BR_PAGE_MAX  = %d' % max(len(r) for r in raws))
    con.append('')
    con.append(bs + ' The two score records BmPatch writes, as addresses in the')
    con.append(bs + ' depacked page - and the page they are on, which is the only')
    con.append(bs + ' one that may be patched.')
    for name in sorted(scores):
        p, addr = scores[name]
        con.append('BR_%-9s = &%04X' % (name.upper(), addr))
    con.append('BR_SCORE_PAGE = %d' % scores[sorted(scores)[0]][0])
    for name in sorted(scores):
        if scores[name][0] != scores[sorted(scores)[0]][0]:
            raise SystemExit('the score records are not on one page')

    OUT_CONST.write_text(chr(10).join(con) + chr(10))

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
    print('make_briefing: streams ' +
          ', '.join('%d->%d' % (len(r), len(k)) for r, k in zip(raws, packs))
          + ' = %d packed (largest page %d unpacked)'
          % (sum(len(k) for k in packs), max(len(r) for r in raws)))


if __name__ == '__main__':
    main()
