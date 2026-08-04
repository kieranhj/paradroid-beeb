#!/usr/bin/env python3
"""
analyse_charmode.py - Work out which characters are hires and which are
multicolour, and whether that is stable across decks.

On the C64, multicolour is selected PER CELL: bit 3 of the colour RAM nibble
picks multicolour (set) or hires (clear) for that cell. The game drives this
from CharColor ($0800), one byte per character code:

  upper nibble = a palette slot index (0-11)
  lower nibble = the colour, rewritten per deck by NewCharColors ($3577)
                 from clr0_top_d020 ($0215), a 12-slot array reloaded from
                 12-byte records at $6A44.

BuildLevel writes that byte straight to colour RAM, where the VIC uses only
the low nibble. So for a given deck:

  colour = record[CharColor[code] >> 4]
  multicolour if colour & 8

If a slot's bit 3 is consistent across every deck record, then each character
has one fixed mode and a single offline conversion works. If not, the same
character would need converting two different ways depending on the deck.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'

CHARCOLOR = 0x0800
RECORDS = 0x6A44
REC_LEN = 12
NUM_REC = 8          # records past this hold values > $0F, so are not colour data
TILEDEFS = 0xE800
ALERT_TILE = 22      # the ALERT panel


def main():
    mem, filled = parse_listing(LST_FILE)

    print('=== colour slot records at $%04X (12 bytes each) ===' % RECORDS)
    print('                                     slot: 0 1 2 3 4 5 6 7 8 9 A B')
    recs = []
    for r in range(NUM_REC):
        rec = list(mem[RECORDS + r * REC_LEN:RECORDS + (r + 1) * REC_LEN])
        recs.append(rec)
        mc = ''.join('M' if (c & 8) else 'h' for c in rec)
        print('  record %2d: %s   mode: %s'
              % (r, ' '.join('%X' % c for c in rec), ' '.join(mc)))

    print('\n  (h = hires cell, M = multicolour cell)')

    print('\n=== is each slot consistent across all records? ===')
    stable = True
    for s in range(REC_LEN):
        bits = {(rec[s] & 8) != 0 for rec in recs}
        if len(bits) == 1:
            print('  slot %2d: always %s' % (s, 'MULTICOLOUR' if bits.pop() else 'hires'))
        else:
            stable = False
            print('  slot %2d: VARIES by deck  <-- problem' % s)

    print('\n=== CharColor slot usage ($%04X) ===' % CHARCOLOR)
    slots = {}
    for code in range(256):
        slot = mem[CHARCOLOR + code] >> 4
        slots.setdefault(slot, []).append(code)
    for slot in sorted(slots):
        codes = slots[slot]
        mode = ''
        if slot < REC_LEN:
            bits = {(rec[slot] & 8) != 0 for rec in recs}
            mode = ('MULTICOLOUR' if bits.pop() else 'hires') if len(bits) == 1 else 'VARIES'
        rng = '%d chars: %s%s' % (
            len(codes),
            ', '.join('$%02X' % c for c in codes[:10]),
            ' ...' if len(codes) > 10 else '')
        print('  slot %2d  %-12s  %s' % (slot, mode, rng))

    print('\n=== the ALERT panel (tile %d) ===' % ALERT_TILE)
    for row in range(4):
        cells = []
        for col in range(4):
            code = mem[TILEDEFS + ALERT_TILE * 16 + row * 4 + col]
            slot = mem[CHARCOLOR + code] >> 4
            if slot < REC_LEN:
                bits = {(rec[slot] & 8) != 0 for rec in recs}
                m = ('MC' if bits.pop() else 'hi') if len(bits) == 1 else '??'
            else:
                m = '--'
            cells.append('$%02X slot%-2d %s' % (code, slot, m))
        print('  ' + ' | '.join(cells))

    print('\n%s' % ('One fixed mode per character - a single conversion works.'
                    if stable else
                    'Mode varies by deck - conversion must be deck aware.'))


if __name__ == '__main__':
    main()
