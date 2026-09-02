#!/usr/bin/env python3
"""
export_sideview.py - the lift screen's ship cross-section, for MODE 1.

Emits src/data/sideview.asm (bank 7) and src/data/svdecks6.asm (bank 6).

The second file is the SAME four deck-rectangle tables under bank-6
names. The lift screen lives in bank 7 but the cleared-deck marking
walk lives in bank 6 (layer-12 DECISION 6), and only one bank is
visible at a time, so both need the geometry. Emitting the copy here
rather than hand-writing it keeps ONE source of truth - the C64
listing - so the two can never drift.

WHAT THE SIDE VIEW IS
---------------------
SideView_dat ($F180) is 201 bytes of RLE - DrawPacked ($30A0) unpacks it
into a 64-wide, 16-row grid of CHARACTER codes, showing only grid
columns 3-41 (39 screen columns), at screen rows 9-24. Each stored code
gets ORA #$80, selecting the upper half of the $7800 game charset; the
stored code $29 is the blank and becomes 0. lift_HighlightDeck ($240C)
then lights the current deck by swapping characters +/-$10 - each hull
character has a "lit" partner - over the rectangle in the deck tables at
$F120-$F150, and FindLift ($272F) marks the chosen lift's shaft down its
length in colour RAM.

WHAT IS EMITTED
---------------
- the RLE stream verbatim (svData), its length found by running the
  decode to the 16th row exactly as DrawPacked does;
- the character set: every code the data uses PLUS every code the
  highlight's +/-$10 arithmetic can produce ($80-$9F and $A5-$A8), in
  TWO sets - normal, and shaft-marked;
- the deck rectangles (lift_DeckX/Y/Width/Height, 16 each) and the
  shaft positions (liftShaftX/Y/Height, 8 each) the two routines index.

CONVERSION - the colour lives IN the artwork
--------------------------------------------
The side view is embossed: box edges are 01 pairs ($D022, white) on the
top and left and 10 pairs ($D023, black) on the bottom and right, over
the background; the LIT deck variants ($9x) are the same art with the
interior filled with 11 pairs, whose colour the C64 takes from colour
RAM - dark purple in play. So the mapping is one logical colour per
pair, all four planes kept: 00 background (blue), 01 white, 10 black,
11 magenta. Flattening 10 into the background was tried first and
erased half of every outline. Whether a character is multicolour at all
is bit 3 of CharColor ($0800) - the hires ones (the fine ladders) map
set bits to white.

The SHAFT-MARKED set replicates what FindLift's colour RAM $F9 does on
the C64: bit 3 forces the cell multicolour and the low bits make its 11
colour 1 - so every character is read as pairs, hires ladders included
(which is exactly the chunky-white ladder the C64 shows down the chosen
shaft), and 11 maps to white instead of magenta.
"""

import sys
import importlib.util
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OUT = PROJECT / 'src' / 'data' / 'sideview.asm'
OUT6 = PROJECT / 'src' / 'data' / 'svdecks6.asm'

CHARSET = 0x7800
CHARCOLOR = 0x0800
SIDEVIEW = 0xF180
DECK_Y = 0xF120
DECK_X = 0xF130
DECK_H = 0xF140
DECK_W = 0xF150
SHAFT_X = 0x6CB0
SHAFT_Y = 0x6CB8
SHAFT_H = 0x6CC0


def load_memory():
    spec = importlib.util.spec_from_file_location('rg', PROJECT / 'tools' / 'rip_graphics.py')
    rg = importlib.util.module_from_spec(spec)
    sys.modules['rg'] = rg
    try:
        spec.loader.exec_module(rg)
    except SystemExit:
        pass
    mem, _ = rg.parse_listing(rg.LST_FILE)
    return mem


def decode(mem):
    """Run DrawPacked's decode: returns (grid[16][39] of final chars,
    stream length in bytes)."""
    grid = [[0] * 39 for _ in range(16)]
    pos = 0          # ptr_14: column within the 64-wide virtual grid
    row = 0          # ptr_14+1
    p = SIDEVIEW
    while row < 16:
        b = mem[p]
        if b & 0x80:
            char, length = b & 0x7F, mem[p + 1]
            p += 2
        else:
            char, length = b, 1
            p += 1
        for _ in range(length):
            if 3 <= pos < 42:
                grid[row][pos - 3] = 0 if char == 0x29 else char | 0x80
            pos += 1
            if pos == 64:
                pos = 0
                row += 1
                if row == 16:
                    break
    return grid, p - SIDEVIEW


PAIR_HULL   = {0: 0, 1: 1, 2: 2, 3: 3}   # slot 5: 11 is the lit fill, magenta
PAIR_LADDER = {0: 0, 1: 1, 2: 2, 3: 1}   # the shafts: 11 rungs render white
PAIR_MARKED = {0: 0, 1: 1, 2: 2, 3: 3}   # $F9, YOUR shaft: rungs magenta


def mode1_char(mem, code, marked):
    """One charset entry -> 16 MODE 1 bytes (left half's 8 scanlines then
    the right's). EVERY character converts as multicolour pairs.

    That was learned twice. The runtime multicolour flag is colour RAM
    bit 3, which NewCharColors ($3577) rewrites per deck - the static
    CharColor table's low nibble is 0, so reading ITS bit 3 rendered
    everything hires and dotted the hull lines. Deciding by the upper
    nibble's palette slot was next (slot 5 multicolour), and that left
    the SHAFT characters ($A5-$A8, slot F) hires - whose rung rows are
    01-pair runs, dotted again at the ladder tops and bottoms. The art
    itself settles it: every one of these characters is drawn in pairs -
    2px rails, embossed shadows, solid rungs - so pairs they are.

    The 11 plane's colour is per set and per slot: the hull's (slot 5)
    is the lit deck's magenta fill; an unmarked ladder's rungs render
    white so the ship's shafts read neutral; the MARKED shaft's rungs
    take the magenta - the highlight marking YOURS, the role colour
    RAM $F9 plays on the C64."""
    if marked:
        pairmap = PAIR_MARKED
    elif (mem[CHARCOLOR + code] >> 4) == 5:
        pairmap = PAIR_HULL
    else:
        pairmap = PAIR_LADDER
    left, right = [], []
    for r in range(8):
        b = mem[CHARSET + code * 8 + r]
        pairs = [(b >> 6) & 3, (b >> 4) & 3, (b >> 2) & 3, b & 3]
        px = []
        for pr in pairs:
            c = pairmap[pr]
            px += [c, c]
        for half, src in ((left, px[0:4]), (right, px[4:8])):
            byte = 0
            for n, c in enumerate(src):
                if c & 2:
                    byte |= 0x80 >> n
                if c & 1:
                    byte |= 0x08 >> n
            half.append(byte)
    return left + right


def main():
    mem = load_memory()
    grid, rle_len = decode(mem)

    used = sorted({c for row in grid for c in row if c})
    # everything the highlight arithmetic can reach, used or not
    codes = [0] + sorted(set(used) | set(range(0x80, 0xA0)) | set(range(0xA5, 0xA9)))

    out = []
    out.append('\\ ============================================================')
    out.append('\\ sideview.asm - GENERATED by tools/export_sideview.py, do not edit')
    out.append('\\ ============================================================')
    out.append('\\ The lift screen: SideView_dat ($F180) RLE verbatim, the deck and')
    out.append('\\ shaft tables, and the characters in three pen sets - white ship,')
    out.append('\\ yellow lit deck, magenta marked shaft. See the exporter header.')
    out.append('')
    out.append('SV_CHARS   = %d' % len(codes))
    out.append('SV_RLE_LEN = %d' % rle_len)
    out.append('')
    out.append('\\ The C64 codes in svChars order; code 0 is the blank. LvBuildGlyphOf')
    out.append('\\ expands this into the 256-byte code->glyph table at xsGlyphOf.')
    out.append('.svCode')
    out.append('  EQUB ' + ', '.join('&%02X' % c for c in codes))
    out.append('')

    normal = [mode1_char(mem, c, False) if c else [0] * 16 for c in codes]
    marked = [mode1_char(mem, c, True) if c else [0] * 16 for c in codes]

    out.append('\\ NORMAL: the embossed art in its own colours. 16 bytes each,')
    out.append('\\ left half then right.')
    out.append('.svChars1')
    for c, data in zip(codes, normal):
        out.append('  \\ code &%02X' % c)
        out.append('  EQUB ' + ', '.join('&%02X' % b for b in data))
    out.append('.svChars1_end')
    out.append('ASSERT svChars1_end - svChars1 == SV_CHARS * 16')
    out.append('')

    # The shaft-marked set used to be emitted whole, all SV_CHARS of it, and
    # was 592 bytes of bank 7 to say the same thing as svChars1 for all but
    # three glyphs: colour RAM $F9 only changes a character that HAS 01 pairs
    # to promote, and only the shaft rungs do. So emit the run that differs
    # and let LvCell fall back to svChars1 for every glyph outside it.
    diff = [i for i in range(len(codes)) if normal[i] != marked[i]]
    assert diff, 'no marked glyph differs - the pen has become redundant'
    first, last = diff[0], diff[-1]
    assert diff == list(range(first, last + 1)), \
        'the differing glyphs are not one run (%r); LvCell assumes a range' % diff
    out.append('\\ SHAFT-MARKED: colour RAM $F9 - forced multicolour, 11s white.')
    out.append('\\ ONLY the glyphs that $F9 actually changes, which is the shaft')
    out.append('\\ rungs and nothing else. LvCell uses svChars1 below SV_MARK0 and')
    out.append('\\ above SV_MARK0 + SV_MARK_N, and this table between.')
    out.append('SV_MARK0  = %d' % first)
    out.append('SV_MARK_N = %d' % (last - first + 1))
    out.append('.svCharsMk')
    for i in range(first, last + 1):
        out.append('  \\ code &%02X' % codes[i])
        out.append('  EQUB ' + ', '.join('&%02X' % b for b in marked[i]))
    out.append('.svCharsMk_end')
    out.append('ASSERT svCharsMk_end - svCharsMk == SV_MARK_N * 16')
    out.append('')

    out.append('\\ SideView_dat ($F180), the RLE stream verbatim - LvDrawPacked is a')
    out.append('\\ transliteration of DrawPacked ($30A0) and reads it as the C64 does.')
    out.append('.svData')
    raw = [mem[SIDEVIEW + i] for i in range(rle_len)]
    for i in range(0, len(raw), 16):
        out.append('  EQUB ' + ', '.join('&%02X' % b for b in raw[i:i+16]))
    out.append('')

    def table(name, addr, n, note):
        out.append('\\ %s' % note)
        out.append('.%s' % name)
        out.append('  EQUB ' + ', '.join('%d' % mem[addr + i] for i in range(n)))

    table('svDeckY', DECK_Y, 16, 'lift_DeckY ($F120): highlight row, +10 for the C64 screen row')
    table('svDeckX', DECK_X, 16, 'lift_DeckX ($F130): highlight column, +1 applied by the code')
    table('svDeckH', DECK_H, 16, 'lift_DeckHeight ($F140): 1 for most decks, 2-3 for the engine rooms')
    table('svDeckW', DECK_W, 16, 'lift_DeckWidth ($F150)')
    table('svShaftX', SHAFT_X, 8, 'liftShaftX ($6CB0): shaft column, +1 applied by the code')
    table('svShaftY', SHAFT_Y, 8, 'liftShaftY ($6CB8): shaft top row, +10 for the C64 screen row')
    table('svShaftH', SHAFT_H, 8, 'liftShaftHeight ($6CC0): rows of colour the shaft mark paints')
    out.append('')

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text('\n'.join(out) + '\n')
    print(f'wrote {OUT}')

    # ---- the bank-6 copy of the deck rectangles -------------------
    # Same four tables, bank-6 names. See the module docstring: the
    # marking walk is in bank 6 and cannot read bank 7's copy.
    six = [
        '\\ ============================================================',
        '\\ svdecks6.asm - the deck rectangles, BANK 6 COPY',
        '\\ GENERATED by tools/export_sideview.py - do not edit by hand.',
        '\\ ============================================================',
        '\\ Byte-for-byte svDeckY/X/H/W from src/data/sideview.asm, which is',
        '\\ bank 7. LvClearedMark walks these from bank 6 and only one bank',
        '\\ is visible at a time, so the geometry has to exist in both. Both',
        '\\ copies come from the same C64 listing in the same exporter run,',
        '\\ so they cannot drift; regenerate, never hand-edit.',
        '',
    ]
    for nm, addr in (('lvcDeckY', DECK_Y), ('lvcDeckX', DECK_X),
                     ('lvcDeckH', DECK_H), ('lvcDeckW', DECK_W)):
        six.append('.%s' % nm)
        six.append('  EQUB ' + ', '.join('%d' % mem[addr + i] for i in range(16)))
    six.append('')
    OUT6.write_text('\n'.join(six) + '\n')
    print(f'wrote {OUT6}')
    print(f'  RLE {rle_len} B; {len(codes)} chars x 2 sets = {len(codes)*32} B; tables 88 B')
    print('  codes used by the data: ' + ' '.join('$%02X' % c for c in used))
    # the decoded picture, for eyeballing
    for row in grid:
        print('  ' + ''.join('.' if not c else ('#' if c < 0x90 else '+') if c < 0xA0 else '@' for c in row))


if __name__ == '__main__':
    main()
