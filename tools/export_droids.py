#!/usr/bin/env python3
"""
export_droids.py - Droid sprites, waypoints and type tables for the BBC port.

Emits src/data/droids.asm. Supersedes export_player.py: the player is droid
type 0, so one table now serves every droid including him.

Sprites
-------
No droid sprite exists in the C64 data. The dynamic sprite area $5200-$53FF
ships zeroed and every droid's artwork is built at runtime:

  BuildDroidSprite ($3C77)  writes the three-digit droid number into sprite
                            rows 6-13, one 4-pixel-wide digit per byte column.
  AnimateDroids    ($3CFB)  writes the spinning rotor into rows 0-4 and 15-19
                            from the RotAnim_* tables, indexed by a phase
                            counter kept in the sprite's own pad byte ($3F).

Rows 5, 14 and 20 are never written, so they stay transparent.

The rotor is IDENTICAL for every droid - only the number differs. So the rows
are stored once and shared:

    rotor   5 rows x 8 phases            = 40 rows
    ends    2 alternating rows x 8 phases = 16 rows
    digits  8 rows x 24 types             = 192 rows
    blank   1
                                          = 249 rows x 7 bytes = 1743 bytes

Two lookups instead of one, because the digit rows depend on the droid TYPE
while the rotor rows depend on the PHASE. A single table indexed by both would
be 24 x 8 x 21 entries. So the blitter uses drOfs[] for rows 0-5 and 14-20,
and drDigit[type] + (row-6)*7 for rows 6-13.

Colour and resolution
---------------------
DROIDS ARE HIRES SPRITES, NOT MULTICOLOUR. This was got wrong once and the
code says so plainly:

  $190C  dMd0_droid, allocating a slot   LDA #0   / STA SpriteMC
  $187F  dMd1_bullet                     LDA #0   / STA SpriteMC
  $1BE8  ExplodeSprite                   LDA #$FF / STA SpriteMC

so only explosions are multicolour. $190E-$1912 also clear SpriteXExp and
SpriteYExp, so there is no doubling in either direction either.

A hires sprite is 24 pixels across at the C64's full 320-pixel horizontal
resolution, one BIT per pixel: set means the sprite's own colour, clear means
transparent. There is no second or third colour to map.

That is a straight 1:1 to MODE 1, which is also 320 across - 24 C64 pixels
become 24 MODE 1 pixels. Reading the bytes as multicolour bit pairs instead
produced 12 fat pixels doubled to 24, which is the same WIDTH and the same
byte count, so it built and ran and looked plausible while being wrong.

The single colour maps to DROID_COLOUR below. The C64 gives enemy droids
$F0 - colour 0, black ($1906) - but MODE 1's four logical colours are the
deck's own, and logical 1 is white on all 16 decks whereas logical 2 is black
on fourteen of them and green on the other two. Logical 1 is therefore the
one that reads consistently. Per-type colour from DColorTheme_t ($EA60) is a
question for the combat layer, not this one.

NO MASKS ARE STORED. Every opaque pixel maps to logical 1, 2 or 3 and never 0,
so a pixel is transparent exactly when both of its bits are clear, and a
256-byte table built at startup recovers the mask. The row is copied into a
buffer anyway, so deriving it there is free.

Rows are SEVEN bytes wide, not six: 24 px is 6 MODE 1 bytes on a 4-pixel
boundary, but sprites are positioned every 2 px and the shift spills into a
seventh byte.

Waypoints
---------
Droids only change direction on a waypoint. Each is a 3-byte record - char X,
char Y, and a bitmask of permitted exit directions - and a deck's records are
sorted by Y ascending, which FindWaypoint ($170D) relies on to bail early.

Waypoint 0 of each deck is never used by InitDeckDroids ($1664), which starts
placing at waypoint 1. We use it as the player's spawn point when changing
deck, which is why the exporter checks it exists for every deck.

Requires: Python 3. No third-party dependencies.
"""

import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_DIR = PROJECT / 'src' / 'data'

# --- C64 addresses: sprite construction ------------------------------------
ROT_2_17L = 0x6B0E
ROT_2_17M = 0x6B16
ROT_3_16L = 0x6B1E
ROT_3_16M = 0x6B26
ROT_3_16R = 0x6B2E
ROT_4_15L = 0x6B36
ROT_4_15M = 0x6B3E
ROT_4_15R = 0x6B46
ROT_0_19M = 0x6B4E          # 2 entries
ROT_1_18M = 0x6B50          # 2 entries

NUM_DATA_OFFSET = 0x6AA4    # digit -> offset into NumData
NUM_DATA = 0x6AAE

# AnimateDroids writes $80 into the right-hand byte of rows 2 and 17. There is
# no RotAnim_2_17R table; the accumulator still holds $80 from the row above.
ROW_2_17_R = 0x80

# --- C64 addresses: droid types --------------------------------------------
DCENT_T = 0xEA00            # hundreds digit
DNUM_T = 0xEA20             # tens/units, packed BCD
DSPEED_T = 0xEA40           # pixels per GameLoop iteration: 1, 2, 4 or 8
DWEAPON_T = 0xEA80          # weapon class 0-3; 3 is the disruptor

NUM_TYPES = 24

# --- C64 addresses: Layer 7 combat stats -----------------------------------
# DCent_t doubles as a CLASS index for these: it is the hundreds digit of the
# droid's number, so it rises 0-9 with how dangerous the droid is, and the
# score and aging tables are indexed by it rather than by the type.
AGING_MASK = 0x6DDE         # frameCount mask per class - how fast maxEnergy ages
AGING_MASK_N = 10           # DCent_t is 0-9
ALERT_SCORE = 0x6DE8        # points per alert level, indexed by Alert >> 6
ALERT_SCORE_N = 4

# --- C64 addresses: waypoints ----------------------------------------------
NUM_WAYPOINTS = 0xC800      # 16 bytes, one per deck
WAYPOINTS_LO = 0xC810
WAYPOINTS_HI = 0xC820
DECK_DROID_BASE = 0xC830    # per-deck droid type base

NUM_DECKS = 16
SPRITE_ROWS = 21
FRAMES = 8

# The player's speed is PlayerSpeed_t[DSpeed_t[type]]; every OTHER droid uses
# the raw DSpeed_t value. Kept here only to document the distinction - the
# chained lookup is the player's alone and lives in player.asm.
PLAYER_SPEED_T = 0x6D97

# The C64's droid speeds are per GameLoop ITERATION. Our loop is locked to
# FRAME_LOCK fields a pass and the C64 spends ITER_FRAMES fields an iteration,
# so a speed scales by FRAME_LOCK / ITER_FRAMES. At 2 and 2 they cancel and the
# per-pass delta is the C64's own value. Keep these in step with FRAME_LOCK in
# main.asm and PLY_ITER_FRAMES in player.asm.
ITER_FRAMES = 2
FRAME_LOCK = 2

DROID_COLOUR = 1            # MODE 1 logical colour of a set bit; see above

BANNER = """\\ ============================================================
\\ droids.asm
\\ GENERATED by tools/export_droids.py - do not edit by hand.
\\ Source: paradroid_ce.lst (Paradroid, C64 - original/CE lineage)
\\ 24 droid types, 8 rotor phases, waypoints for 16 decks
\\ ============================================================
"""


def mode1_mask(b):
    """The transparency mask for a MODE 1 data byte.

    Same derivation as SprBuildMask: fold the low nibble onto the high, invert,
    spread back across both. A set mask bit means "this pixel is transparent,
    keep the background".
    """
    m = ((b >> 4) | b) & 0x0F
    m ^= 0x0F
    return m | (m << 4)


def shift_row(row, px=2):
    """Shift a MODE 1 row right by px pixels, 0-3.

    Compiled code bakes its data in as immediates, so a shifted sprite cannot
    be derived at run time from the compiled form - each shift needs its own
    compiled copy, and all four are generated from here.

    MODE 1 pixel n of a byte is bits 7-n and 3-n, so a pixel shift moves both
    nibbles together and the pixels falling off the right become the next
    byte's leftmost. The mask picks the bits that survive; the complement,
    shifted up, is the carry into the next byte.

        1 px   keep &EE >> 1    carry (&11) << 3
        2 px   keep &CC >> 2    carry (&33) << 2
        3 px   keep &88 >> 3    carry (&77) << 1

    The carry out of the last byte is DROPPED, so the caller must pass a row
    wide enough to hold the spill - seven bytes for 24 px at any of the four
    shifts. Handing this a truncated row is what silently ate the right-hand
    column of every digit glyph until 2026-08-14.
    """
    if px == 0:
        return list(row)
    keep = {1: 0xEE, 2: 0xCC, 3: 0x88}[px]
    spill = (~keep) & 0xFF
    out, carry = [], 0
    for b in row:
        out.append(((b & keep) >> px) | carry)
        carry = (b & spill) << (4 - px)
    return out


def emit_bytes(f, data, per_line=12):
    for i in range(0, len(data), per_line):
        chunk = data[i:i + per_line]
        f.write('  EQUB ' + ','.join('&%02X' % b for b in chunk) + '\n')


def convert_row(c64_row):
    """3 C64 HIRES sprite bytes -> 7 MODE 1 data bytes.

    24 bits, one per pixel, straight across to 24 MODE 1 pixels at 4 per byte.
    MODE 1 pixel n takes bit (7-n) as its high colour bit and bit (3-n) as its
    low bit; a clear source bit sets neither, which is transparent.

    The seventh byte is always empty, so the 2-pixel-shifted copy built at
    startup has somewhere to put the pixels that spill out of byte 6.
    """
    assert DROID_COLOUR != 0, (
        'an opaque sprite pixel would map to logical 0; the mask could no '
        'longer be derived from the data')
    bits = [(byte >> (7 - i)) & 1 for byte in c64_row for i in range(8)]
    data = []
    for group in range(6):
        d = 0
        for n in range(4):
            if bits[group * 4 + n]:
                if DROID_COLOUR & 2:
                    d |= 1 << (7 - n)
                if DROID_COLOUR & 1:
                    d |= 1 << (3 - n)
        data.append(d)
    data.append(0)
    return data


# The 2 px shifted copy is NOT emitted. It is built at startup directly into
# spare sideways RAM above this data (SPR_SHIFT2 in main.asm). Shipping it
# would add 1743 bytes to PARADAT, and PARADAT is staged in main RAM at &3000
# before being copied up - which would push the staging area into the play
# buffer at &5800. Building it costs a few thousand cycles once.


def build_rotor(mem):
    """The 8 rotor phases: 5 top rows each, plus the 2 alternating end rows.

    The bottom half is the top half in reverse ROW order, not mirrored left to
    right - AnimateDroids writes the same L/M/R bytes both times. Rows 0/1 and
    18/19 carry only a middle byte from 2-entry tables indexed by phase >> 2,
    and the bottom pair uses the OTHER entry, which is what makes the two ends
    of the rotor alternate.
    """
    frames = []
    for phase in range(FRAMES):
        frames.append([
            [0, mem[ROT_0_19M + (phase >> 2)], 0],                  # row 0
            [0, mem[ROT_1_18M + (phase >> 2)], 0],                  # row 1
            [mem[ROT_2_17L + phase], mem[ROT_2_17M + phase], ROW_2_17_R],
            [mem[ROT_3_16L + phase], mem[ROT_3_16M + phase], mem[ROT_3_16R + phase]],
            [mem[ROT_4_15L + phase], mem[ROT_4_15M + phase], mem[ROT_4_15R + phase]],
        ])

    bottoms = []
    for phase in range(FRAMES):
        other = ((phase >> 2) + 1) & 1
        bottoms.append((mem[ROT_0_19M + other], mem[ROT_1_18M + other]))

    return frames, bottoms


def build_rotor_code(mem, frames, bottoms):
    """The 28 distinct rotor rows, and the slot each sprite row maps to.

    The rotor's 10 non-blank rows per phase are NOT 10 distinct pictures. The
    bottom half is the top half in reverse row order, so rows 15/16/17 are rows
    4/3/2 again; and rows 0/1/18/19 come from two-entry tables indexed by
    phase >> 2, so across all eight phases there are only four of them. Seven
    distinct rows per phase, 8 * 3 rotor + 4 end = 28 in all.

    Slots, per phase, with a = phase >> 2 and b = 1 - a:

        0  end kind 0, index a      sprite row 0
        1  end kind 1, index a      sprite row 1
        2  rotor row 2              sprite rows 2 and 17
        3  rotor row 3              sprite rows 3 and 16
        4  rotor row 4              sprite rows 4 and 15
        5  end kind 1, index b      sprite row 18
        6  end kind 0, index b      sprite row 19
    """
    rows = {}                       # key -> 7 MODE 1 bytes, unshifted
    for phase in range(FRAMES):
        for r in (2, 3, 4):
            rows[('R', phase, r)] = convert_row(frames[phase][r])
    for idx in (0, 1):
        rows[('E', 0, idx)] = convert_row([0, mem[ROT_0_19M + idx], 0])
        rows[('E', 1, idx)] = convert_row([0, mem[ROT_1_18M + idx], 0])

    slots = []                      # [phase][slot] -> key
    for phase in range(FRAMES):
        a = phase >> 2
        b = 1 - a
        slots.append([('E', 0, a), ('E', 1, a),
                      ('R', phase, 2), ('R', phase, 3), ('R', phase, 4),
                      ('E', 1, b), ('E', 0, b)])

    # sprite row -> slot, &FF for the rows the compiled path does not own
    row_slot = [0xFF] * SPRITE_ROWS
    for r, s in ((0, 0), (1, 1), (2, 2), (3, 3), (4, 4),
                 (15, 4), (16, 3), (17, 2), (18, 5), (19, 6)):
        row_slot[r] = s

    return rows, slots, row_slot


def emit_rotor_code(tab, f, rows, slots, row_slot, shifts, pfx):
    """Compiled draw and restore routines for every distinct rotor row.

    TWO OUTPUTS, and which one a thing goes to is load-bearing. `tab` is the
    bank's fixed section: every table the blitter reaches by name, laid out in
    the same order and at the same size in BOTH sprite banks, so one set of
    labels addresses whichever bank is paged. `f` is the code, whose size
    differs between banks and which is therefore only ever entered through the
    tables. `pfx` prefixes the table labels in the second bank's copy - the
    blitter uses the first bank's names and main.asm asserts the addresses
    match.

    `shifts` is the two this bank holds. Table indices are the POSITION in
    that pair, not the absolute shift, so they still fit in a byte: sprSeqBase
    is (shift AND 1) * DR_SEQSHIFT + phase * 10.

    A compiled row costs 23 cycles per OPAQUE byte and nothing at all for the
    transparent ones; the interpreted path costs 26 to fetch and 27 to blit
    every one of the seven whether it draws anything or not. The rotor averages
    3.2 opaque bytes of 7, so this is the row where compiling pays best - and
    the digits, which are two thirds of the work, are left alone for now.

    THE ALIGNMENT ESCAPE. A compiled sprite normally needs eight variants, one
    per vertical alignment. Here it needs one: within a character row a byte is
    at col*8 + scan, the scan part is carried by bufp, and SprNextScan advances
    bufp and svp together - so Y is always col*8, whatever the alignment.

    Restore routines are keyed on the SET OF COLUMNS, not the artwork: putting
    the background back does not care what was drawn over it. Four sets cover
    all 28 rows, so 28 draw routines share 4 restore routines.
    """
    labels = {}                     # (shift, key) -> draw label
    rest_labels = {}                # (shift, cols) -> restore label
    draw_bytes = rest_bytes = 0

    for shift in shifts:
        f.write('\\ ---- shift %d px -------------------------------------\n'
                % shift)
        for n, (key, row) in enumerate(sorted(rows.items())):
            data = shift_row(row, shift)
            label = 'drD%d_%02d' % (shift, n)
            labels[(shift, key)] = label
            f.write('.%s\n' % label)
            for col, b in enumerate(data):
                if not b:
                    continue        # transparent: not drawn, and not saved
                m = mode1_mask(b)
                f.write('  LDY #%d*UNIT_BYTES\n' % col)
                f.write('  LDA (bufp),Y : STA (svp),Y\n')
                if m == 0:
                    # every pixel opaque, so the background contributes nothing
                    f.write('  LDA #&%02X : STA (bufp),Y\n' % b)
                    draw_bytes += 10
                else:
                    f.write('  AND #&%02X : ORA #&%02X : STA (bufp),Y\n' % (m, b))
                    draw_bytes += 12
            f.write('  SCANSTEP\n')      # C: the walk lives in the row
            f.write('  RTS\n')
            draw_bytes += 18

        sets = []
        for key, row in sorted(rows.items()):
            data = shift_row(row, shift)
            cols = tuple(i for i, b in enumerate(data) if b)
            if cols not in sets:
                sets.append(cols)
        for n, cols in enumerate(sets):
            label = 'drR%d_%02d' % (shift, n)
            rest_labels[(shift, cols)] = label
            f.write('.%s\n' % label)
            for col in cols:
                f.write('  LDY #%d*UNIT_BYTES : LDA (svp),Y : STA (bufp),Y\n'
                        % col)
                rest_bytes += 6
            f.write('  SCANSTEP\n')      # C: the walk lives in the row
            f.write('  RTS\n')
            rest_bytes += 18

    def rest_for(shift, key):
        data = shift_row(rows[key], shift)
        cols = tuple(i for i, b in enumerate(data) if b)
        return rest_labels[(shift, cols)]

    # ---- dispatch, in ROW order rather than by slot -------------------
    # The ten rotor rows a sprite draws are fixed once its shift and phase
    # are known, so the sequence is a property of (shift, phase) - sixteen
    # of them - not of the sprite. Listing them in the order they are drawn
    # lets SprRotor5 walk the list with one index and no row->slot lookup,
    # where the slot-indexed table needed a lookup and an add per row.
    #
    # Rows 0-4 then 15-19: the bottom half visits slots 4,3,2,5,6, which is
    # the top half's 2,3,4 reversed with the two end rows swapped, so it
    # cannot share entries with the top - hence ten, not seven.
    seq_rows = [0, 1, 2, 3, 4, 15, 16, 17, 18, 19]
    tab.write('\n')
    tab.write('\\ Rotor dispatch, at index (shift AND 1)*%d + phase*%d + n,\n'
              % (FRAMES * len(seq_rows), len(seq_rows)))
    tab.write('\\ where n counts the ten drawn rotor rows in drawing order.\n')
    tab.write('\\ This bank holds shifts %d and %d px; the other holds the\n'
              % tuple(shifts))
    tab.write('\\ other two, at the same addresses with its own contents.\n')
    for name, pick in (('drSeqLo',  lambda s, k: 'LO(%s)' % labels[(s, k)]),
                       ('drSeqHi',  lambda s, k: 'HI(%s)' % labels[(s, k)]),
                       ('drRSeqLo', lambda s, k: 'LO(%s)' % rest_for(s, k)),
                       ('drRSeqHi', lambda s, k: 'HI(%s)' % rest_for(s, k))):
        tab.write('.%s%s\n' % (pfx, name))
        for shift in shifts:
            for phase in range(FRAMES):
                tab.write('  EQUB ' + ','.join(
                    pick(shift, slots[phase][row_slot[r]]) for r in seq_rows) + '\n')
    # ---- B: one straight-line program per (shift, phase) -------------
    # Every rotor routine ends by walking, so a program is just the calls in
    # drawing order with the digit block in the middle - no index, no counter,
    # no end test. The two explicit walks are the blank rows 5 and 14; the
    # block does its own eight.
    #
    # THE LAST CALL IS A JMP. The program ends in RTS, so a JSR followed by
    # that RTS is a tail call written the long way: 9 cycles instead of 18,
    # and one byte shorter.
    #
    # THE RESTORE HALVES ARE MERGED. A restore routine is keyed on the COLUMN
    # SET, and the ten rows of a sprite draw only four distinct sets, so the
    # sequence comes out as five identical pairs - 00,00 02,02 03 | 03 02,02
    # 01,01. It also depends only on (shift, phase>>2), because that is all
    # the column set depends on. So instead of ten calls there are two, to a
    # routine per half with all five rows inlined: eight routines cover every
    # shift and phase. That is 8 of the 10 JSR/RTS pairs gone.
    #
    # The draw gets none of this: its ten rows are ten DIFFERENT routines
    # (00,02,04,05,06 | 06,05,04,03,01), and merging them would mean a copy
    # per phase of the rows that are currently shared.
    def rest_cols(shift, key):
        data = shift_row(rows[key], shift)
        return tuple(i for i, b in enumerate(data) if b)

    f.write('\n')
    f.write('\\ Five rows of restore inlined. Only the column set matters, and\n')
    f.write('\\ that depends on shift and phase>>2 alone - so eight of these\n')
    f.write('\\ cover all sixteen sequences. The last row of the bottom half\n')
    f.write('\\ does not walk: nothing reads the pointers after it.\n')
    for shift in shifts:
        for arr in (0, 1):
            phase = arr * 4
            for half, half_rows in ((0, seq_rows[:5]), (1, seq_rows[5:])):
                f.write('.drRHalf%d_%d_%d\n' % (shift, arr, half))
                for n, r in enumerate(half_rows):
                    key = slots[phase][row_slot[r]]
                    for col in rest_cols(shift, key):
                        f.write('  LDY #%d*UNIT_BYTES : LDA (svp),Y'
                                ' : STA (bufp),Y\n' % col)
                        rest_bytes += 6
                    if not (half == 1 and n == len(half_rows) - 1):
                        f.write('  SCANSTEP\n')
                        rest_bytes += 17
                f.write('  RTS\n')
                rest_bytes += 1

    f.write('\n')
    for shift in shifts:
        for phase in range(FRAMES):
            f.write('.drPrg%d_%d\n' % (shift, phase))
            for n, r in enumerate(seq_rows):
                if n == 5:
                    f.write('  SCANSTEP\n')                 # row 5, blank
                    f.write('  JSR SprDigitBlock\n')         # rows 6-13
                    f.write('  SCANSTEP\n')                 # row 14, blank
                op = 'JMP' if n == len(seq_rows) - 1 else 'JSR'
                f.write('  %s %s\n' % (op, labels[(shift, slots[phase][row_slot[r]])]))

    f.write('\n')
    for shift in shifts:
        for phase in range(FRAMES):
            f.write('.drRPrg%d_%d\n' % (shift, phase))
            f.write('  JSR drRHalf%d_%d_0\n' % (shift, phase >> 2))
            f.write('  SCANSTEP\n')
            f.write('  JSR SprBlkRest\n')
            f.write('  SCANSTEP\n')
            f.write('  JMP drRHalf%d_%d_1\n' % (shift, phase >> 2))

    # Indexed by the SAME sprSeqBase the fallback uses, so entering a program
    # costs a table read and a poke and no arithmetic at all. Only every tenth
    # entry can be reached; the rest are filled to keep the table square.
    tab.write('\n')
    for name, kind, half in (('drPrgLo', 'drPrg', 'LO'), ('drPrgHi', 'drPrg', 'HI'),
                             ('drRPrgLo', 'drRPrg', 'LO'), ('drRPrgHi', 'drRPrg', 'HI')):
        tab.write('.%s%s\n' % (pfx, name))
        for shift in shifts:
            for phase in range(FRAMES):
                tab.write('  EQUB ' + ','.join(
                    ['%s(%s%d_%d)' % (half, kind, shift, phase)] * len(seq_rows)) + '\n')

    tab.write('\n')
    tab.write('\\ Sprite row -> position in that sequence; &FF means the row is\n'
              '\\ not the rotor\'s (a digit row, or one of the three blank ones).\n'
              '\\ Only the wrap fallback needs it - the fast path knows the\n'
              '\\ shape and walks the list straight through.\n')
    seq_idx = [0xFF] * SPRITE_ROWS
    for n, r in enumerate(seq_rows):
        seq_idx[r] = n
    tab.write('.%sdrSeqIdx\n' % pfx)
    emit_bytes(tab, seq_idx, per_line=SPRITE_ROWS)
    tab.write('.%sdrMul10                     \\ phase * %d\n' % (pfx, len(seq_rows)))
    emit_bytes(tab, [len(seq_rows) * p for p in range(FRAMES)], per_line=FRAMES)
    tab.write('\n')

    return draw_bytes, rest_bytes


def emit_glyph_code(tab, f, mem, shifts, pfx):
    """Compiled draw code for the ten digit glyphs.

    THE DIGITS ARE DENSE WHERE THE ROTOR WAS SPARSE - 42.7 opaque bytes of 56
    against 3.2 of 7 - so almost nothing is saved by skipping transparent
    bytes. The win is deleting SprFetchRow, which copies and masks all seven
    bytes of all eight rows whether they draw anything or not.

    That changes what is worth compiling. Per-TYPE code would be ~1,012 bytes
    a type and 24 types do not fit in a 16K bank with the level data. But the
    number is three independent 8-pixel glyphs and there are only ten glyphs,
    so ten routines cover all 24 types - and the three positions are reached
    by offsetting bufp, not by generating three copies.

    A GLYPH DOES NOT WALK. The block is eight known scanlines, so
    SprBuildRowPtrs works out all eight addresses once and row n addresses
    (rowp+2n),Y. Three glyph passes over eight rows used to cost 21 calls to
    a scanline-advance routine; now they cost one build, shared.

    The POSITION rides in X for the whole routine and drYcolN,X turns it into
    a Y offset of pos*16 + col*8. That costs two cycles a column against
    offsetting eight pointers per position, and it is what lets the three
    positions share one set of pointers.

    THREE COLUMNS UNDER A SHIFT, TWO WITHOUT. The 2 px shift spills each
    glyph into the next position's first byte, so the three glyphs share
    columns 2 and 4 and the last one reaches column 6. A glyph saves only
    its own two columns; SprDigitBlock draws the positions in descending
    order so that the owner of each shared column saves it before the spill
    arrives, and saves column 6 itself. See the note in the loop below.
    """
    def glyph_rows(d):
        # THREE bytes, not two. A glyph is 8 pixels wide, so two bytes hold it
        # unshifted and the third is always empty - but shift_row drops the
        # carry out of the last byte it is given, so truncating BEFORE the
        # shift threw the rightmost pixel column away. It did exactly that
        # until 2026-08-14, and the assert below could not catch it because
        # the truncation made its length test vacuous.
        base = mem[NUM_DATA_OFFSET + d]
        return [convert_row([mem[NUM_DATA + base + 3 * r], 0, 0])[:3]
                for r in range(8)]

    size = 0
    for shift in shifts:
        for d in range(10):
            rows = glyph_rows(d)
            assert all(row[2] == 0 for row in rows), (
                'glyph %d is wider than 8 pixels unshifted' % d)
            rows = [shift_row(r, shift) for r in rows]
            assert all(len(row) == 3 for row in rows), (
                'a shifted glyph row lost its spill column')
            # A GLYPH SAVES ITS OWN TWO COLUMNS AND NOT ITS SPILL. The C64
            # digits are 7 pixels wide in an 8 pixel cell, so unshifted the
            # three positions are disjoint - columns 0-1, 2-3, 4-5. SHIFTED
            # THEY ARE NOT: 2 px right puts the last pixel column into the
            # next position's first byte, because position p column 2 and
            # position p+1 column 0 are the same byte (Y = (p+1)*16).
            #
            # A shared column must be saved by whichever glyph touches it
            # FIRST, and a glyph does not know its own position. So the
            # rule is the other way round: nobody saves a spill, and
            # SprDigitBlock draws the positions in DESCENDING order, which
            # makes the neighbour that owns each shared column save it
            # clean before the spill arrives. Column 6 has no owner and is
            # saved by SprDigitBlock itself.
            #
            # The save of columns 0 and 1 folds into the draw, where the
            # byte is being loaded anyway, and happens even for a
            # transparent byte so SprBlkRest can stay generic.
            f.write('.drGlyph%d_%d\n' % (shift, d))
            for n, row in enumerate(rows):
                # Row n of the block has its own pointer, so nothing walks.
                # X holds the digit POSITION for the whole routine and
                # drYcolN,X turns it into a Y offset - see the digit block
                # header in sprite.asm.
                ptr = 'rowp+%d' % (2 * n)
                sav = 'rowq+%d' % (2 * n)
                for col in range(3):
                    b = row[col]
                    if col == 2:
                        # The spill. Not saved - see the note above - and
                        # merged into whatever the neighbouring position
                        # has already drawn there, so it is a read, mask
                        # and write rather than a store.
                        if not b:
                            continue
                        f.write('  LDY drYcol2,X\n')
                        f.write('  LDA (%s),Y : AND #&%02X : ORA #&%02X'
                                ' : STA (%s),Y\n'
                                % (ptr, mode1_mask(b), b, ptr))
                        size += 13
                        continue
                    m = mode1_mask(b)
                    f.write('  LDY drYcol%d,X\n' % col)
                    f.write('  LDA (%s),Y : STA (%s),Y\n' % (ptr, sav))
                    size += 7
                    if not b:
                        continue            # saved, nothing drawn over it
                    if m == 0:
                        f.write('  LDA #&%02X : STA (%s),Y\n' % (b, ptr))
                        size += 4
                    else:
                        f.write('  AND #&%02X : ORA #&%02X : STA (%s),Y\n'
                                % (m, b, ptr))
                        size += 6
            f.write('  RTS\n')
            size += 1

    # Column 6's save, generated here rather than written in sprite.asm
    # only because main RAM is the binding constraint and this bank is not.
    # It runs with the sprite bank paged in, like the glyphs it precedes.
    # IN THE FIXED SECTION, not the code, even though it is code: the blitter
    # calls it by name from main RAM, so it has to be at the same address in
    # both sprite banks, and only the fixed section guarantees that.
    tab.write('\n\\ drBlkSave6 - the digit block\'s column 6, all eight rows.\n'
              '\\ Nothing owns it: it is only ever written by the last\n'
              '\\ position\'s spill under a shift. See SprDigitBlock.\n')
    tab.write('.%sdrBlkSave6\n' % pfx)
    tab.write('  LDY #6*UNIT_BYTES\n')
    for n in range(8):
        tab.write('  LDA (rowp+%d),Y : STA (rowq+%d),Y\n' % (2 * n, 2 * n))
        size += 4
    tab.write('  RTS\n')
    size += 3

    tab.write('\n\\ Glyph dispatch, at index (shift AND 1)*10 + digit.\n')
    tab.write('.%sdrGlyphLo\n' % pfx)
    for shift in shifts:
        tab.write('  EQUB ' + ','.join('LO(drGlyph%d_%d)' % (shift, d)
                                       for d in range(10)) + '\n')
    tab.write('.%sdrGlyphHi\n' % pfx)
    for shift in shifts:
        tab.write('  EQUB ' + ','.join('HI(drGlyph%d_%d)' % (shift, d)
                                       for d in range(10)) + '\n')

    tab.write('\n\\ The three digits of each droid type, as glyph numbers.\n')
    for pos in range(3):
        tab.write('.%sdrDigit%d\n' % (pfx, pos))
        vals = []
        for t in range(NUM_TYPES):
            if pos == 0:
                vals.append(mem[DCENT_T + t])
            elif pos == 1:
                vals.append(mem[DNUM_T + t] >> 4)
            else:
                vals.append(mem[DNUM_T + t] & 0x0F)
        emit_bytes(tab, vals)
    tab.write('\n')
    return size


def build_digits(mem, dtype):
    """The 8 digit rows for one droid type, as C64 sprite bytes."""
    digits_of = [mem[DCENT_T + dtype],
                 mem[DNUM_T + dtype] >> 4,
                 mem[DNUM_T + dtype] & 0x0F]
    rows = []
    for r in range(8):
        rows.append([mem[NUM_DATA + mem[NUM_DATA_OFFSET + d] + 3 * r]
                     for d in digits_of])
    return rows, digits_of


def droid_number(mem, dtype):
    return '%d%02X' % (mem[DCENT_T + dtype], mem[DNUM_T + dtype])


def collect_waypoints(mem):
    """Per-deck waypoint records, and a flat blob with per-deck offsets."""
    counts = [mem[NUM_WAYPOINTS + d] for d in range(NUM_DECKS)]
    blob, offsets = [], []
    for d in range(NUM_DECKS):
        addr = mem[WAYPOINTS_LO + d] | (mem[WAYPOINTS_HI + d] << 8)
        offsets.append(len(blob))
        for i in range(counts[d]):
            blob += [mem[addr + 3 * i], mem[addr + 3 * i + 1], mem[addr + 3 * i + 2]]
        assert counts[d] >= 1, 'deck %d has no waypoints, so no player spawn' % d
        # FindWaypoint bails early on wp.Y > droid.Y, so the sort matters.
        ys = [blob[offsets[d] + 3 * i + 1] for i in range(counts[d])]
        assert ys == sorted(ys), 'deck %d waypoints are not sorted by Y' % d
    return counts, offsets, blob


def main():
    mem, _ = parse_listing(LST_FILE)
    frames, bottoms = build_rotor(mem)

    # --- flatten every distinct row -----------------------------------------
    # order: rotor[phase][0..4], rotorend[phase][0..1], digits[type][0..7], blank
    rows = []
    rotor_at, end_at, digit_at = {}, {}, {}
    for phase in range(FRAMES):
        for r in range(5):
            rotor_at[(phase, r)] = len(rows)
            rows.append(convert_row(frames[phase][r]))
    for phase in range(FRAMES):
        for r in range(2):           # 0 = sprite row 19, 1 = sprite row 18
            end_at[(phase, r)] = len(rows)
            rows.append(convert_row([0, bottoms[phase][r], 0]))
    numbers = []
    for dtype in range(NUM_TYPES):
        digits, _ = build_digits(mem, dtype)
        digit_at[dtype] = len(rows)
        for r in range(8):
            rows.append(convert_row(digits[r]))
        numbers.append(droid_number(mem, dtype))
    blank_at = len(rows)
    rows.append([0] * 7)

    # --- per-phase offsets for the rows that do NOT depend on type ----------
    def row_index(phase, r):
        if r < 5:
            return rotor_at[(phase, r)]
        if r in (5, 14, 20):
            return blank_at
        if r < 14:
            return blank_at         # digit rows: the blitter uses drDigit
        if r < 18:
            return rotor_at[(phase, 19 - r)]     # 15->4, 16->3, 17->2
        return end_at[(phase, 19 - r)]           # 18->end 1, 19->end 0

    offsets = []
    for phase in range(FRAMES):
        for r in range(SPRITE_ROWS):
            offsets.append(row_index(phase, r) * 7)

    counts, wp_offsets, wp_blob = collect_waypoints(mem)
    speeds = [mem[DSPEED_T + t] for t in range(NUM_TYPES)]

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rotor_rows, rotor_slots, rotor_rowslot = build_rotor_code(mem, frames, bottoms)

    # ---- the two sprite banks ------------------------------------------
    # A compiled shift is ~5.5K of code, so the four do not fit in one 16K
    # bank: shifts 0 and 1 px go in SWRAM_SPR, 2 and 3 px in SWRAM_SPR+1, and
    # PAGESPRBANK pages whichever a sprite needs.
    #
    # EACH FILE IS TABLES THEN CODE, and the tables are the same size in both,
    # so they land at the same addresses. That is what lets the blitter name
    # one set: it addresses bank 5's labels and gets bank 6's tables when bank
    # 6 is paged. The second file's table labels are prefixed to keep beebasm
    # happy, and main.asm asserts the two agree.
    sizes = {}
    for bank, (shifts, pfx, name) in enumerate((((0, 1), '', 'droids.asm'),
                                                ((2, 3), 'x', 'droids2.asm'))):
        tab, code = io.StringIO(), io.StringIO()
        code_d, code_r = emit_rotor_code(tab, code, rotor_rows, rotor_slots,
                                         rotor_rowslot, shifts, pfx)
        code_g = emit_glyph_code(tab, code, mem, shifts, pfx)
        sizes[bank] = (code_d, code_r, code_g)
        with open(OUT_DIR / name, 'w') as f:
            f.write(BANNER)
            f.write('\\ Shifts %d and %d px. The other two are in the other\n'
                    '\\ sprite bank, at the same table addresses.\n' % shifts)
            f.write('\n')
            if not pfx:
                f.write('DR_W        = 7                 '
                        '\\ 24 px, plus one for the shift spill\n')
                f.write('DR_H        = %d\n' % SPRITE_ROWS)
                f.write('DR_FRAMES   = %d\n' % FRAMES)
                f.write('DR_TYPES    = %d\n' % NUM_TYPES)
                f.write('DR_ROWS     = %d              '
                        '\\ distinct stored rows\n' % len(rows))
                f.write('DR_DATASIZE = DR_ROWS * DR_W\n')
                f.write('DR_DIGIT0   = 6                 \\ first digit row\n')
                f.write('DR_DIGITN   = 8                 \\ how many digit rows\n')
                f.write('DR_SEQSHIFT = %d                '
                        '\\ sequence stride between this bank\'s two shifts\n'
                        % (FRAMES * 10))
                f.write('DR_GLYPHS   = 10                '
                        '\\ digit glyphs, and the glyph-table stride\n')
                f.write('\n')

            f.write('\\ ==== fixed section: SAME SIZE AND ORDER IN BOTH BANKS ====\n')
            f.write('\\ Everything the blitter reaches by name. Sizes here are\n')
            f.write('\\ independent of which shifts the bank holds, so the\n')
            f.write('\\ addresses match and one set of labels serves both.\n')
            f.write('\\ The stored artwork is not among them: drSprData and\n')
            f.write('\\ drOfs are in the DATA bank, read only by SprFetchRow.\n')
            f.write('\n')
            f.write('\\ p * %d, to index drOfs.\n' % SPRITE_ROWS)
            f.write('.%sdrMulRows\n' % pfx)
            emit_bytes(f, [SPRITE_ROWS * p for p in range(FRAMES)], per_line=FRAMES)
            f.write('\n')
            f.write('\\ Byte offset of each type\'s 8 digit rows into drSprData.\n')
            f.write('.%sdrDigitLo\n' % pfx)
            emit_bytes(f, [(digit_at[t] * 7) & 0xFF for t in range(NUM_TYPES)])
            f.write('.%sdrDigitHi\n' % pfx)
            emit_bytes(f, [(digit_at[t] * 7) >> 8 for t in range(NUM_TYPES)])
            f.write(tab.getvalue())
            f.write('\\ ==== code: sizes differ between the banks ================\n')
            f.write(code.getvalue())

    code_d, code_r, code_g = sizes[0]
    path2 = OUT_DIR / 'droidgame.asm'    # sideways bank SWRAM_DATA
    with open(path2, 'w') as g:
        g.write(BANNER)
        g.write('\n')
        g.write('\\ The half of the droid export that is GAME DATA, not sprite: speeds,\n')
        g.write('\\ waypoints and the per-deck type base. These live in the DATA bank\n')
        g.write('\\ with the tiles and levels, because the sprite bank is only paged\n')
        g.write('\\ in around the blitter and none of this is read there.\n')
        g.write('\n')

        g.write('\\ ---- droid artwork, read only by the wrap fallback --------\n')
        g.write('\\ Every distinct row, seven bytes each, unshifted; the shift is\n')
        g.write('\\ done on the fly by SprFetchRow and the masks are derived from\n')
        g.write('\\ a table, not stored.\n')
        g.write('\\\n')
        g.write('\\ IN THIS BANK RATHER THAN THE SPRITE BANK because SprFetchRow\n')
        g.write('\\ is the only thing that reads it, on about one row in fifty,\n')
        g.write('\\ and it pages this bank in around itself for ~24 cycles. The\n')
        g.write('\\ sprite bank is the scarce one - it has to hold two compiled\n')
        g.write('\\ shifts - and this is 2,079 bytes of it that need not be.\n')
        g.write('.drSprData\n')
        for row in rows:
            emit_bytes(g, row, per_line=7)
        g.write('\n')
        g.write('\\ Byte offset into drSprData for sprite row r of phase p, at\n')
        g.write('\\ index p*%d + r. Rows %d-%d (the number) point at the blank\n'
                % (SPRITE_ROWS, 6, 13))
        g.write('\\ row: they depend on the droid type, not the phase, so the\n')
        g.write('\\ blitter takes them from drDigit instead.\n')
        g.write('.drOfsLo\n')
        emit_bytes(g, [o & 0xFF for o in offsets], per_line=SPRITE_ROWS)
        g.write('.drOfsHi\n')
        emit_bytes(g, [o >> 8 for o in offsets], per_line=SPRITE_ROWS)
        g.write('\n')

        g.write('\\ Speed in pixels per GameLoop ITERATION, straight from the\n')
        g.write('\\ C64\'s DSpeed_t. Enemy droids use this value directly; only\n')
        g.write('\\ the player chains it through PlayerSpeed_t. An iteration is\n')
        g.write('\\ %d frames here, so 1/2/4/8 becomes 0.5/1/2/4 px per frame -\n' % ITER_FRAMES)
        g.write('\\ hence drSpeedF, the 8.8 fixed-point per-frame value.\n')
        g.write('.drSpeed\n')
        emit_bytes(g, speeds)
        g.write('.drSpeedF                       \\ (speed * 256) / %d, 8.8\n' % ITER_FRAMES)
        emit_bytes(g, [(s * 256 * FRAME_LOCK // ITER_FRAMES) & 0xFF for s in speeds])
        g.write('.drSpeedFHi\n')
        emit_bytes(g, [(s * 256 * FRAME_LOCK // ITER_FRAMES) >> 8 for s in speeds])
        g.write('\n')

        g.write('\\ ---- Layer 7 combat stats -------------------------------\n')
        g.write('\\ drCent is the C64\'s DCent_t, the hundreds digit of the\n')
        g.write('\\ droid number - which rises with how dangerous the droid is,\n')
        g.write('\\ so the original uses it as a CLASS index and looks the aging\n')
        g.write('\\ and score tables up through it rather than through the type.\n')
        g.write('.drCent\n')
        emit_bytes(g, [mem[DCENT_T + t] for t in range(NUM_TYPES)])
        g.write('\n')

        g.write('\\ Weapon class per type: 0 = unarmed, 3 = the disruptor.\n')
        g.write('\\ The player\'s own is weaponType, seeded from entry 0 here.\n')
        g.write('.drWeapon\n')
        emit_bytes(g, [mem[DWEAPON_T + t] for t in range(NUM_TYPES)])
        g.write('\n')

        g.write('\\ DoAlertAndAging ($3E32). drAgingMask is ANDed with the\n')
        g.write('\\ iteration counter, so a SMALLER mask ages the droid faster:\n')
        g.write('\\ $7F for class 0 against $0F for class 9. drAlertScore pays\n')
        g.write('\\ out as the alert level decays, indexed by Alert >> 6.\n')
        g.write('.drAgingMask\n')
        emit_bytes(g, [mem[AGING_MASK + i] for i in range(AGING_MASK_N)])
        g.write('.drAlertScore\n')
        emit_bytes(g, [mem[ALERT_SCORE + i] for i in range(ALERT_SCORE_N)])
        g.write('\n')

        g.write('\\ Droid numbers, for reference: ')
        g.write(', '.join('%d=%s' % (t, numbers[t]) for t in range(NUM_TYPES)))
        g.write('\n\n')

        g.write('\\ ---- waypoints ------------------------------------------\n')
        g.write('\\ 3 bytes per record: char X, char Y, permitted directions.\n')
        g.write('\\ Sorted by Y ascending within a deck - FindWaypoint bails\n')
        g.write('\\ out as soon as it passes the droid\'s row.\n')
        g.write('\\\n')
        g.write('\\ Direction bit n gives a delta pair via the C64\'s overlapping\n')
        g.write('\\ dirXdelta/dirYdelta tables, 0 = -speed, 1 = 0, 2 = +speed:\n')
        g.write('\\   bit  7   6   5   4   3   2   1   0\n')
        g.write('\\   dx   0   0   1   2   2   2   1   0\n')
        g.write('\\   dy   1   2   2   2   1   0   0   0\n')
        g.write('\\        W  SW   S  SE   E  NE   N  NW\n')
        g.write('DR_WP_TOTAL = %d\n' % (len(wp_blob) // 3))
        g.write('.wpCount\n')
        emit_bytes(g, counts, per_line=NUM_DECKS)
        g.write('.wpOfsLo\n')
        emit_bytes(g, [o & 0xFF for o in wp_offsets], per_line=NUM_DECKS)
        g.write('.wpOfsHi\n')
        emit_bytes(g, [o >> 8 for o in wp_offsets], per_line=NUM_DECKS)
        g.write('.wpData\n')
        emit_bytes(g, wp_blob, per_line=9)
        g.write('\n')

        g.write('\\ Per-deck droid type base, from the C64\'s deckDroidBase.\n')
        g.write('\\ NextLevel adds shipLevel and a random spread on top; that\n')
        g.write('\\ arrives with shipLevel in Layer 6. Deck counts are already\n')
        g.write('\\ exported as deckDroids in levels.asm.\n')
        g.write('.deckDroidBase\n')
        emit_bytes(g, [mem[DECK_DROID_BASE + d] for d in range(NUM_DECKS)],
                   per_line=NUM_DECKS)
        g.write('\n')

    print('%s' % path2)
    print('  sprites   %d rows x 7 = %d bytes  (+ %d offsets, %d digit ptrs)'
          % (len(rows), len(rows) * 7, len(offsets) * 2, NUM_TYPES * 2))
    for bank, (d, r, gl) in sizes.items():
        print('  bank %d    shifts %d/%d px: rotor %d draw + %d restore,'
              ' glyphs %d' % (5 + bank, bank * 2, bank * 2 + 1, d, r, gl))
    print('  waypoints %d records = %d bytes' % (len(wp_blob) // 3, len(wp_blob)))
    print('  per-deck waypoint counts: %s' % counts)


if __name__ == '__main__':
    main()
