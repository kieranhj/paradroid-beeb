#!/usr/bin/env python3
"""
analyse_alert.py - Per deck, check whether the ALERT lettering stays legible.

Two ways it can fail in the MODE 1 port:

  1. The characters land on a slot that is MULTICOLOUR for that deck's scheme.
     A multicolour character is 4 pixels wide, so the single-pixel gaps
     between letters cannot exist.

  2. The characters are hires, but their colour and the background collapse
     onto the SAME MODE 1 logical colour. MODE 1 has 4 logical colours and
     the C64 draws from a 12-slot palette, so build_logical_map keeps the
     three most-used foregrounds and maps the rest to the nearest by
     luminance - which can merge a colour into the background.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing  # noqa: E402
from export_bbc import (deck_colours, build_logical_map,       # noqa: E402
                        deck_background, CHARCOLOR, TILEDEF_ADDR, REC_LEN)

PROJECT = Path(__file__).resolve().parent.parent
ALERT_TILE = 22
NAMES = ['black', 'white', 'red', 'cyan', 'purple', 'green', 'blue', 'yellow',
         'orange', 'brown', 'lt red', 'dk grey', 'grey', 'lt green',
         'lt blue', 'lt grey']


def main():
    mem, _ = parse_listing(PROJECT / 'paradroid_ce.lst')

    # The lettering is row 0 of the ALERT tile ($63-$66), not row 1. Row 1
    # ($CC-$CE) is the panel below it, and checking that instead reported every
    # deck as fine while decks 0/5/9/13/14 were drawing the letters in
    # multicolour.
    letters = [mem[TILEDEF_ADDR + ALERT_TILE * 16 + i] for i in range(4)]
    print('ALERT lettering characters: %s'
          % ', '.join('$%02X' % c for c in letters))
    print('slots: %s\n' % ', '.join(str(mem[CHARCOLOR + c] >> 4) for c in letters))

    print('deck  scheme  mode         colour     logical  bg logical  verdict')
    print('-' * 72)
    bad = []
    for d in range(16):
        scheme, rec, cell_colour = deck_colours(mem, d)
        D021 = deck_background(mem, d)
        logical, _ = build_logical_map(mem, cell_colour, D021)

        def log_of(c64):
            if c64 in logical:
                return logical.index(c64)
            from export_bbc import LUMA
            return min(range(4), key=lambda i: abs(LUMA[logical[i]] - LUMA[c64]))

        colour = cell_colour(letters[1])          # a letter body character
        multi = bool(colour & 8)
        lg, bg = log_of(colour & 7 if multi else colour), log_of(D021)

        if multi:
            # Faithful to the C64: that slot is multicolour under this deck's
            # scheme, so the character is 4 pixels wide and the single-pixel
            # letter gaps cannot exist. The original looks the same.
            verdict, why = 'joined', 'multicolour - 4px wide, letters join'
        elif lg == bg:
            # This one IS a port bug: two C64 colours collapsed onto one
            # MODE 1 logical colour, so the letters vanish.
            verdict, why = 'INVISIBLE', 'colour merges into the background'
        else:
            verdict, why = 'crisp', ''
        if verdict != 'crisp':
            bad.append((d, verdict, why))

        # In a multicolour cell the VIC takes the "11" colour from bits 0-2
        # only, bit 3 being the mode selector - so report colour & 7 there,
        # not the whole nibble. This line used to print the nibble and named
        # e.g. brown where the cell actually draws white.
        print('%3d %6d   %-11s  %-9s  %5d  %9d   %s %s'
              % (d, scheme, 'multicolour' if multi else 'hires',
                 NAMES[colour & 7 if multi else colour & 15],
                 lg, bg, verdict, why))

    print()
    joined = [b for b in bad if b[1] == 'joined']
    broken = [b for b in bad if b[1] == 'INVISIBLE']
    if joined:
        print('%d deck(s) draw the lettering in multicolour, so the letters '
              'join. This matches the C64 - verify with compare_tile.py before '
              'treating it as a fault:' % len(joined))
        print('  decks ' + ', '.join(str(d) for d, _, _ in joined))
    if broken:
        print('\n%d deck(s) have a PORT BUG - lettering merges into the '
              'background:' % len(broken))
        for d, _, why in broken:
            print('  deck %2d: %s' % (d, why))
    if not bad:
        print('All decks keep the ALERT lettering crisp.')


if __name__ == '__main__':
    main()
