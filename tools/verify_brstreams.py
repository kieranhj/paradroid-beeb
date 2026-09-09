#!/usr/bin/env python3
"""
verify_brstreams.py - the briefing's ZX0 page streams against beebasm.

no-load step 5, stage 1. make_briefing.py lays each briefing page out
twice: once as beebasm source (src/data/briefing.asm, the bank-5 PARMAN
records the old renderer walks) and once as a Python-assembled blob it
ZX0s into src/data/brstreamN.asm. THE TWO MUST BE THE SAME PAGE. This
checks that against the bytes BEEBASM ACTUALLY EMITTED, not against
make_briefing's own idea of them, so a layout slip in the blob builder
cannot survive:

  1. decompress each stream with tools/zx0.py - the format the 6502
     depacker eats;
  2. pull the page's record region out of the assembled XREC block in
     build/paradroid-raw.ssd, using beebasm's own symbol dump for the
     addresses, and diff it against the stream byte for byte. XREC is
     src/data/briefing.asm - the old shipping layout, kept and
     assembled for no other purpose than this, and dropped from the
     disc because make_disc.py writes only its LAYOUT;
  3. RUN THE DRIVER'S SCAN over it - the $FF walk that rebuilds
     brRowLo/Hi at BR_BUF - and check every pointer it derives against
     the bank's own brRow_p_r, rebased on BR_RECS. That is the check the
     scan itself has to pass at run time, done here at build time.

Run it after a build. It needs build/paradroid-raw.ssd (beebasm's direct
output, whose PARMAN is uncompressed) and re-runs beebasm for -d.
"""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zx0                       # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
RAW_SSD = PROJECT / 'build' / 'paradroid-raw.ssd'
BEEBASM = PROJECT / 'bin' / 'beebasm.exe'
SECTOR = 256


def symbols():
    out = subprocess.run(
        [str(BEEBASM), '-i', 'src/main.asm', '-do', 'build/symbols.ssd',
         '-D', 'RELEASE=0', '-d'],
        cwd=PROJECT, capture_output=True, text=True, check=True).stdout
    syms = {}
    for m in re.finditer(r"'([^']+)':(-?\d+)", out):
        syms[m.group(1)] = int(m.group(2)) & 0xFFFF
    return syms


def catalogue(img):
    """name -> bytes, from a DFS image."""
    files = {}
    count = img[0x105] // 8
    for i in range(count):
        n = 8 + i * 8
        name = img[n:n + 7].decode('latin-1').strip()
        a = img[0x100 + n:0x100 + n + 8]
        length = a[4] | (a[5] << 8) | ((a[6] >> 4) & 3) << 16
        start = a[7] | ((a[6] & 3) << 8)
        files[name] = img[start * SECTOR:start * SECTOR + length]
    return files


def main():
    if not RAW_SSD.exists():
        raise SystemExit('%s missing - build first' % RAW_SSD)
    sym = symbols()
    parman = catalogue(RAW_SSD.read_bytes())['XREC']
    man_start = sym['rec_start']

    # the shape, from the generated constants rather than assumed
    con = (PROJECT / 'src' / 'data' / 'briefconst.asm').read_text()
    def const(name):
        m = re.search(r'^%s\s*=\s*(&?)([0-9A-Fa-f]+)' % name, con, re.M)
        return int(m.group(2), 16 if m.group(1) else 10)

    pages = const('BR_PAGES')
    row_lo, row_hi = const('BR_ROW_LO'), const('BR_ROW_HI')
    br_buf = const('BR_BUF_ASSUMED')
    rows = list(range(row_lo, row_hi + 1))
    br_recs = br_buf + 2 * len(rows)

    bad = 0
    for p in range(pages):
        def stream(name):
            path = PROJECT / 'src' / 'data' / name
            if not path.exists():
                return None
            return bytes(int(v, 16) for v in
                         re.findall(r'&([0-9A-F]{2})', path.read_text()))

        # A SPLIT PAGE IS CHECKED AS THE DRIVER SEES IT, chained. Page 5
        # ships as two independently packed chunks in two different banks
        # (no-load step 6); BrDepackChain depacks the second straight on
        # from where the first stopped, because Zx0Unpack leaves mapptr
        # past its last byte. Concatenating the two decompressions here is
        # the same operation, so what this diffs against beebasm is the
        # page the machine will actually have - not either half of it.
        recs = zx0.decompress(stream('brstream%d.asm' % p))
        chunk_b = stream('brstream%db.asm' % p)
        if chunk_b is not None:
            recs += zx0.decompress(chunk_b)
            print('page %d: two chunks, %d + %d packed'
                  % (p, len(stream('brstream%d.asm' % p)), len(chunk_b)))

        # the bank's record region: from the first row's list to the end
        # of the last one, which is the byte after the last row's $FF.
        first = sym['brRow_%d_%d' % (p, row_lo)]
        if p + 1 < pages:
            last = sym['brRow_%d_%d' % (p + 1, row_lo)]
        else:
            last = sym['brRecEnd']
        bank_recs = parman[first - man_start:last - man_start]

        if recs != bank_recs:
            print('page %d: RECORDS DIFFER - %d bytes vs %d'
                  % (p, len(recs), len(bank_recs)))
            bad += 1
            continue

        # the driver's scan, in Python: a row's list starts where the
        # last one's $FF left off, and $FE ends a record within it.
        scanned, i = [], 0
        for _ in rows:
            scanned.append(br_recs + i)
            while recs[i] != 0xFF:
                i += 1
            i += 1
        if i != len(recs):
            print('page %d: the scan ended at %d of %d' % (p, i, len(recs)))
            bad += 1

        for r, got in zip(rows, scanned):
            want = br_recs + (sym['brRow_%d_%d' % (p, r)] - first)
            if got != want:
                print('page %d row %d: scan gave &%04X, wanted &%04X'
                      % (p, r, got, want))
                bad += 1
        print('page %d: %d record bytes identical, %d pointers scanned back '
              'from &%04X' % (p, len(bank_recs), len(rows), br_recs))

    if bad:
        raise SystemExit('%d checks failed' % bad)
    print('verify_brstreams: all %d pages match beebasm byte for byte'
          % pages)


if __name__ == '__main__':
    main()
