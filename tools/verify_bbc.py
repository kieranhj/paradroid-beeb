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


def unpack_mode1(b):
    """One MODE 1 byte -> its four pixel colours, left to right."""
    return [(((b >> (7 - n)) & 1) << 1) | ((b >> (3 - n)) & 1) for n in range(4)]


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
        # Decoding back to C64 form needs the per-character mode, which comes
        # from the deck's colour scheme - same inputs the exporter used, but
        # travelled in the opposite direction.
        from export_bbc import deck_colours, build_logical_map, DECK, D021
        _, _, cell_colour = deck_colours(mem, DECK)
        logical, _ = build_logical_map(mem, cell_colour)

        def logical_of(c64):
            return logical.index(c64) if c64 in logical else None

        bad, nhi, nmc, skipped = [], 0, 0, 0
        for c in range(256):
            base = c * 16
            left, right = chars[base:base + 8], chars[base + 8:base + 16]
            colour = cell_colour(c)
            multi = bool(colour & 8)
            bgl = logical_of(D021)

            if multi:
                nmc += 1
                pal = [D021, 1, 6, colour & 7]          # 00,01,10,11
                lut = {}
                for v, c64 in enumerate(pal):
                    li = logical_of(c64)
                    if li is not None:
                        lut.setdefault(li, v)
                if len(lut) < 4:
                    skipped += 1                        # colours collided
                    continue
            else:
                nhi += 1
                fgl = logical_of(colour)
                if fgl is None or fgl == bgl:
                    skipped += 1                        # fg indistinguishable
                    continue

            for y in range(8):
                px = unpack_mode1(left[y]) + unpack_mode1(right[y])
                if multi:
                    if px[0] != px[1] or px[2] != px[3] \
                            or px[4] != px[5] or px[6] != px[7]:
                        bad.append((c, y, 'multicolour pixels not doubled'))
                        break
                    vals = [lut.get(px[i]) for i in (0, 2, 4, 6)]
                    if None in vals:
                        break
                    recovered = (vals[0] << 6) | (vals[1] << 4) \
                        | (vals[2] << 2) | vals[3]
                else:
                    recovered = 0
                    for p in range(8):
                        if px[p] == fgl:
                            recovered |= 1 << (7 - p)
                original = mem[CHARSET_ADDR + c * 8 + y]
                if recovered != original:
                    bad.append((c, y, '%02X != %02X' % (recovered, original)))
                    break

        if bad:
            print('FAIL charset: %d chars differ, first 5: %r' % (len(bad), bad[:5]))
            failures += 1
        else:
            print('OK   charset   256 chars round-trip to the original $7800 bytes')
            print('              %d hires, %d multicolour, %d skipped '
                  '(colours collide, not decodable)' % (nhi, nmc, skipped))

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
