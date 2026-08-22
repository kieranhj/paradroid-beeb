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


def check_charset(mem, dump_path, deck):
    """Diff the charset the BBC built at deck-load time against Python.

    The 6502 builds it from nibble lookup tables; this recomputes it directly
    from the C64 bitmaps and the deck's colour scheme, so agreement means two
    independent implementations match.

    EXPECT CODES $4C-$4F TO DIFFER on a dump taken from a running game. They
    are the recharge pad, and AnimTick rotates those four characters inside
    the charset every pass, so they hold whatever phase the animation had
    reached. Character $16 - the ALERT lamp - can differ for the same reason:
    BuildLampChar rewrites it when the alert level changes. Anything else is
    a real failure.
    """
    from export_bbc import (deck_colours, build_logical_map, convert_charset,
                            deck_background, assign_palette, load_palette_override,
                            dither_charset, deck_dithers,
                            CHARSET_ADDR, TILEDEF_ADDR, TILEDEF_SIZE)

    used = sorted({mem[TILEDEF_ADDR + i] for i in range(32 * TILEDEF_SIZE)})
    _, _, cell_colour = deck_colours(mem, deck)
    logical, _ = build_logical_map(mem, cell_colour, deck_background(mem, deck))
    full, _ = convert_charset(mem, cell_colour, logical)

    # Layer 14's floor dither is part of what BuildCharset leaves behind, so
    # the oracle has to apply it too or every dithered deck reads as a fail.
    # The enable rule needs the deck's PHYSICAL palette, hand-set or not.
    dpal = load_palette_override().get(deck, {}).get(
        'physical', assign_palette(logical))
    dither = deck_dithers(dpal)

    expected = bytearray()
    for code in used:
        expected.extend(
            dither_charset(full[code * 16:code * 16 + 16], dither))

    actual = open(dump_path, 'rb').read()
    if len(actual) != len(expected):
        print('FAIL charset: dump is %d bytes, expected %d'
              % (len(actual), len(expected)))
        return 1

    diffs = [i for i, (e, a) in enumerate(zip(expected, actual)) if e != a]
    if diffs:
        codes = sorted({used[i // 16] for i in diffs})
        live = {0x4C, 0x4D, 0x4E, 0x4F, 0x16}
        if set(codes) <= live:
            print('OK   charset   deck %d: %d bytes match, except the %d '
                  'live-animated character(s) %s - see the docstring '
                  '(dither %s)'
                  % (deck, len(expected), len(codes),
                     ' '.join('$%02X' % c for c in codes),
                     'on' if dither else 'off'))
            return 0
        print('FAIL charset: %d of %d bytes differ' % (len(diffs), len(expected)))
        for i in diffs[:8]:
            print('       char index %d (code $%02X) byte %d: expected %02X, got %02X'
                  % (i // 16, used[i // 16], i % 16, expected[i], actual[i]))
        return 1

    print('OK   charset   deck %d: %d bytes (%d chars) match the Python '
          'conversion (dither %s)'
          % (deck, len(expected), len(used), 'on' if dither else 'off'))
    return 0


def main():
    mem, _ = parse_listing(LST_FILE)
    failures = 0

    if len(sys.argv) > 2 and sys.argv[1] == '--tilemap':
        return check_tilemap(mem, sys.argv[2], int(sys.argv[3]))
    if len(sys.argv) > 2 and sys.argv[1] == '--charset':
        return check_charset(mem, sys.argv[2], int(sys.argv[3]))

    # ---- character source data ------------------------------------
    used = sorted({mem[TILEDEF_ADDR + i] for i in range(32 * 16)})
    src = read_equb(DATA_DIR / 'chardata.asm')
    exp_src = bytearray()
    for code in used:
        exp_src.extend(mem[CHARSET_ADDR + code * 8:CHARSET_ADDR + code * 8 + 8])
    exp_slot = bytearray(mem[0x0800 + code] >> 4 for code in used)
    exp_remap = bytearray(256)
    for i, code in enumerate(used):
        exp_remap[code] = i
    n = len(used)
    got_src, got_slot, got_remap = src[:n * 8], src[n * 8:n * 9], src[-256:]

    if bytes(got_src) != bytes(exp_src):
        print('FAIL chardata: C64 bitmaps differ from ')
        failures += 1
    elif bytes(got_slot) != bytes(exp_slot):
        print('FAIL chardata: palette slots differ from CharColor')
        failures += 1
    elif bytes(got_remap) != bytes(exp_remap):
        print('FAIL chardata: code->index remap is wrong')
        failures += 1
    else:
        print('OK   chardata  %d chars: bitmaps, slots and remap all correct' % n)

    # ---- per-deck colour data -------------------------------------
    col = read_equb(DATA_DIR / 'colours.asm')
    if bytes(col[:96]) != bytes(mem[0x6A44:0x6A44 + 96]):
        print('FAIL colours: scheme records differ from ')
        failures += 1
    elif bytes(col[96:112]) != bytes(mem[0xF160:0xF160 + 16]):
        print('FAIL colours: deck->scheme table differs from ')
        failures += 1
    else:
        print('OK   colours   8 scheme records and 16 deck->scheme entries match')

    # Every deck must map its four logical colours to four DISTINCT physical
    # ones. A fixed C64->BBC table cannot guarantee this - several C64 colours
    # share a nearest BBC match - and when two collapse, whatever is drawn in
    # the second becomes invisible against the first.
    pal = col[112:176]
    clash = [d for d in range(16) if len(set(pal[d * 4:d * 4 + 4])) < 4]
    if clash:
        print('FAIL colours: decks %s have colliding physical colours' % clash)
        failures += 1
    else:
        print('OK   colours   all 16 decks have 4 distinct physical colours')

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
