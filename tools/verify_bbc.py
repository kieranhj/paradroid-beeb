#!/usr/bin/env python3
"""
verify_bbc.py - Round-trip check on the data emitted by export_bbc.py.

Re-reads the generated BeebASM sources, decodes them back to their C64
representation, and diffs against the original listing. Catches conversion
and emission bugs that a screenshot comparison would not.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'
DATA_DIR = PROJECT / 'src' / 'data'

CHARSET_ADDR = 0x7800
TILEDEF_ADDR = 0xE800


def read_equb(path):
    """Pull every EQUB byte out of a generated .asm file, in order."""
    out = bytearray()
    for line in open(path):
        line = line.split('\\')[0]                 # strip BeebASM comments
        m = re.match(r'\s*EQUB\s+(.*)', line)
        if not m:
            continue
        for v in m.group(1).split(','):
            v = v.strip()
            if v.startswith('&'):
                out.append(int(v[1:], 16))
    return out


def check_tilemap(mem, dump_path, deck):
    """Diff a tile map dumped from the emulator against a fresh RLE decode."""
    from rip_levels import decode_deck_rle
    expected = decode_deck_rle(mem, deck)[:1024]
    expected += [0] * (1024 - len(expected))
    actual = list(open(dump_path, 'rb').read())

    if len(actual) != 1024:
        print('FAIL tilemap: dump is %d bytes, expected 1024' % len(actual))
        return 1

    diffs = [(i, e, a) for i, (e, a) in enumerate(zip(expected, actual)) if e != a]
    if diffs:
        print('FAIL tilemap: %d of 1024 bytes differ' % len(diffs))
        for i, e, a in diffs[:8]:
            print('       row %2d col %2d: expected %d, got %d'
                  % (i // 64, i % 64, e, a))
        return 1

    used = sum(1 for b in actual if b)
    print('OK   tilemap   deck %d: 1024 bytes match the RLE decode '
          '(%d non-empty tiles)' % (deck, used))
    return 0


def main():
    mem, _ = parse_listing(LST_FILE)
    failures = 0

    if len(sys.argv) > 2 and sys.argv[1] == '--tilemap':
        return check_tilemap(mem, sys.argv[2], int(sys.argv[3]))

    # ---- charset: decode MODE 1 back to 1bpp -----------------------
    chars = read_equb(DATA_DIR / 'charset.asm')
    if len(chars) != 256 * 16:
        print('FAIL charset: got %d bytes, expected %d' % (len(chars), 256 * 16))
        failures += 1
    else:
        bad = []
        for c in range(256):
            base = c * 16
            left, right = chars[base:base + 8], chars[base + 8:base + 16]
            for y in range(8):
                # each nibble must be a clean logical-colour-1 pattern
                if left[y] & 0xF0 or right[y] & 0xF0:
                    bad.append((c, y, 'high nibble set'))
                    break
                recovered = ((left[y] & 0x0F) << 4) | (right[y] & 0x0F)
                original = mem[CHARSET_ADDR + c * 8 + y]
                if recovered != original:
                    bad.append((c, y, '%02X != %02X' % (recovered, original)))
                    break
        if bad:
            print('FAIL charset: %d chars differ, first 5: %r' % (len(bad), bad[:5]))
            failures += 1
        else:
            print('OK   charset   256 chars round-trip to the original $7800 bytes')

    # ---- tile definitions: must be byte-identical ------------------
    tiles = read_equb(DATA_DIR / 'tiledefs.asm')
    original = mem[TILEDEF_ADDR:TILEDEF_ADDR + 32 * 16]
    if bytes(tiles) != bytes(original):
        print('FAIL tiledefs: differs from $E800')
        failures += 1
    else:
        print('OK   tiledefs  32 tiles byte-identical to $E800')

    # ---- levels: RLE must be byte-identical, offsets in range ------
    lv = read_equb(DATA_DIR / 'levels.asm')
    offs_lo, offs_hi, meta, rle = lv[0:16], lv[16:32], lv[32:32 + 96], lv[128:]
    orig_rle = mem[0xF249:0xF249 + len(rle)]
    if bytes(rle) != bytes(orig_rle):
        print('FAIL levels: RLE data differs from $F249')
        failures += 1
    else:
        print('OK   levels    %d bytes RLE byte-identical to $F249' % len(rle))

    bad_ptr = []
    for d in range(16):
        off = (offs_hi[d] << 8) | offs_lo[d]
        c64 = (mem[0xF110 + d] << 8) | mem[0xF100 + d]
        if off != c64 - 0xF249:
            bad_ptr.append((d, off, c64 - 0xF249))
    if bad_ptr:
        print('FAIL levels: deck offsets wrong: %r' % bad_ptr)
        failures += 1
    else:
        print('OK   levels    16 deck offsets re-based correctly from $F249')

    if bytes(meta) != bytes(mem[0xF120:0xF120 + 96]):
        print('FAIL levels: deck metadata differs from $F120')
        failures += 1
    else:
        print('OK   levels    96 bytes deck metadata byte-identical to $F120')

    print('\n%s' % ('ALL CHECKS PASSED' if not failures else '%d CHECK(S) FAILED' % failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
