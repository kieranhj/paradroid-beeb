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

NUM_TYPES = 24

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

# Frames per C64 GameLoop iteration, matching PLY_ITER_FRAMES in player.asm.
# The C64's speeds are per iteration and an iteration is 2-3 frames.
ITER_FRAMES = 2

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


def shift_row(row):
    """The 2 px right shift SprBuildShift performs, done here instead.

    Compiled code bakes its data in as immediates, so the shifted artwork
    cannot be derived at run time from the compiled form - it needs its own
    compiled copy, and that copy is generated from here.
    """
    out, carry = [], 0
    for b in row:
        out.append(((b & 0xCC) >> 2) | carry)
        carry = (b & 0x33) << 2
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


def emit_rotor_code(f, rows, slots, row_slot):
    """Compiled draw and restore routines for every distinct rotor row.

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

    for shift in (0, 1):
        f.write('\\ ---- shift %d ----------------------------------------\n'
                % (shift * 2))
        for n, (key, row) in enumerate(sorted(rows.items())):
            data = shift_row(row) if shift else row
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
            f.write('  RTS\n')
            draw_bytes += 1

        sets = []
        for key, row in sorted(rows.items()):
            data = shift_row(row) if shift else row
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
            f.write('  RTS\n')
            rest_bytes += 1

    def rest_for(shift, key):
        data = shift_row(rows[key]) if shift else rows[key]
        cols = tuple(i for i, b in enumerate(data) if b)
        return rest_labels[(shift, cols)]

    f.write('\n')
    f.write('\\ Dispatch, at index shift*%d + phase*7 + slot.\n' % (FRAMES * 7))
    for name, pick in (('drDrawLo', lambda s, k: 'LO(%s)' % labels[(s, k)]),
                       ('drDrawHi', lambda s, k: 'HI(%s)' % labels[(s, k)]),
                       ('drRestLo', lambda s, k: 'LO(%s)' % rest_for(s, k)),
                       ('drRestHi', lambda s, k: 'HI(%s)' % rest_for(s, k))):
        f.write('.%s\n' % name)
        for shift in (0, 1):
            for phase in range(FRAMES):
                f.write('  EQUB ' + ','.join(pick(shift, k)
                                             for k in slots[phase]) + '\n')
    f.write('\n')
    f.write('\\ Sprite row -> rotor slot; &FF means the row is not the rotor\'s\n')
    f.write('\\ (a digit row, or one of the three always-blank ones).\n')
    f.write('.drRotSlot\n')
    emit_bytes(f, row_slot, per_line=SPRITE_ROWS)
    f.write('.drMul7                         \\ phase * 7\n')
    emit_bytes(f, [7 * p for p in range(FRAMES)], per_line=FRAMES)
    f.write('\n')

    return draw_bytes, rest_bytes


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
    path = OUT_DIR / 'droids.asm'
    with open(path, 'w') as f:
        f.write(BANNER)
        f.write('\n')
        f.write('DR_W        = 7                 \\ 24 px, plus one for a 2 px shift\n')
        f.write('DR_H        = %d\n' % SPRITE_ROWS)
        f.write('DR_FRAMES   = %d\n' % FRAMES)
        f.write('DR_TYPES    = %d\n' % NUM_TYPES)
        f.write('DR_ROWS     = %d              \\ distinct stored rows\n' % len(rows))
        f.write('DR_DATASIZE = DR_ROWS * DR_W\n')
        f.write('DR_DIGIT0   = 6                 \\ first digit row\n')
        f.write('DR_DIGITN   = 8                 \\ how many digit rows\n')
        f.write('\n')

        f.write('\\ Every distinct row, seven bytes each, unshifted. The 2 px\n')
        f.write('\\ shifted copy is built from this at startup and the masks are\n')
        f.write('\\ derived, not stored - see the header comment.\n')
        f.write('.drSprData\n')
        for row in rows:
            emit_bytes(f, row, per_line=7)
        f.write('\n')
        f.write('\\ Byte offset into drSprData for sprite row r of phase p, at\n')
        f.write('\\ index p*%d + r. Rows %d-%d (the number) point at the blank\n'
                % (SPRITE_ROWS, 6, 13))
        f.write('\\ row: they depend on the droid type, not the phase, so the\n')
        f.write('\\ blitter takes them from drDigit instead.\n')
        f.write('.drOfsLo\n')
        emit_bytes(f, [o & 0xFF for o in offsets], per_line=SPRITE_ROWS)
        f.write('.drOfsHi\n')
        emit_bytes(f, [o >> 8 for o in offsets], per_line=SPRITE_ROWS)
        f.write('\n')
        f.write('\\ p * %d, to index the tables above.\n' % SPRITE_ROWS)
        f.write('.drMulRows\n')
        emit_bytes(f, [SPRITE_ROWS * p for p in range(FRAMES)], per_line=FRAMES)
        f.write('\n')

        f.write('\\ Byte offset of each type\'s 8 digit rows. Row 6+n is at\n')
        f.write('\\ drDigit[type] + n*%d.\n' % 7)
        f.write('.drDigitLo\n')
        emit_bytes(f, [(digit_at[t] * 7) & 0xFF for t in range(NUM_TYPES)])
        f.write('.drDigitHi\n')
        emit_bytes(f, [(digit_at[t] * 7) >> 8 for t in range(NUM_TYPES)])
        f.write('\n')

        f.write('\\ ---- compiled rotor ---------------------------------------\n')
        f.write('\\ Rows 0-4 and 15-19 are drawn by generated code rather than\n')
        f.write('\\ fetched and blitted. See emit_rotor_code in the exporter for\n')
        f.write('\\ why this is the row that pays, and why one variant suffices\n')
        f.write('\\ where a compiled sprite usually needs eight.\n')
        f.write('\\\n')
        f.write('\\ The interpreted path is NOT retired: a row straddling the end\n')
        f.write('\\ of the play strip has its columns out of address order and\n')
        f.write('\\ falls back to it, so drOfs and the rotor rows in drSprData\n')
        f.write('\\ are still live.\n')
        f.write('DR_TABSHIFT = %d                \\ table stride between the two shifts\n'
                % (FRAMES * 7))
        rotor_rows, rotor_slots, rotor_rowslot = build_rotor_code(mem, frames, bottoms)
        code_d, code_r = emit_rotor_code(f, rotor_rows, rotor_slots, rotor_rowslot)

        f.write('\\ Speed in pixels per GameLoop ITERATION, straight from the\n')
        f.write('\\ C64\'s DSpeed_t. Enemy droids use this value directly; only\n')
        f.write('\\ the player chains it through PlayerSpeed_t. An iteration is\n')
        f.write('\\ %d frames here, so 1/2/4/8 becomes 0.5/1/2/4 px per frame -\n' % ITER_FRAMES)
        f.write('\\ hence drSpeedF, the 8.8 fixed-point per-frame value.\n')
        f.write('.drSpeed\n')
        emit_bytes(f, speeds)
        f.write('.drSpeedF                       \\ (speed * 256) / %d, 8.8\n' % ITER_FRAMES)
        emit_bytes(f, [(s * 256 // ITER_FRAMES) & 0xFF for s in speeds])
        f.write('.drSpeedFHi\n')
        emit_bytes(f, [(s * 256 // ITER_FRAMES) >> 8 for s in speeds])
        f.write('\n')

        f.write('\\ Droid numbers, for reference: ')
        f.write(', '.join('%d=%s' % (t, numbers[t]) for t in range(NUM_TYPES)))
        f.write('\n\n')

        f.write('\\ ---- waypoints ------------------------------------------\n')
        f.write('\\ 3 bytes per record: char X, char Y, permitted directions.\n')
        f.write('\\ Sorted by Y ascending within a deck - FindWaypoint bails\n')
        f.write('\\ out as soon as it passes the droid\'s row.\n')
        f.write('\\\n')
        f.write('\\ Direction bit n gives a delta pair via the C64\'s overlapping\n')
        f.write('\\ dirXdelta/dirYdelta tables, 0 = -speed, 1 = 0, 2 = +speed:\n')
        f.write('\\   bit  7   6   5   4   3   2   1   0\n')
        f.write('\\   dx   0   0   1   2   2   2   1   0\n')
        f.write('\\   dy   1   2   2   2   1   0   0   0\n')
        f.write('\\        W  SW   S  SE   E  NE   N  NW\n')
        f.write('DR_WP_TOTAL = %d\n' % (len(wp_blob) // 3))
        f.write('.wpCount\n')
        emit_bytes(f, counts, per_line=NUM_DECKS)
        f.write('.wpOfsLo\n')
        emit_bytes(f, [o & 0xFF for o in wp_offsets], per_line=NUM_DECKS)
        f.write('.wpOfsHi\n')
        emit_bytes(f, [o >> 8 for o in wp_offsets], per_line=NUM_DECKS)
        f.write('.wpData\n')
        emit_bytes(f, wp_blob, per_line=9)
        f.write('\n')

        f.write('\\ Per-deck droid type base, from the C64\'s deckDroidBase.\n')
        f.write('\\ NextLevel adds shipLevel and a random spread on top; that\n')
        f.write('\\ arrives with shipLevel in Layer 6. Deck counts are already\n')
        f.write('\\ exported as deckDroids in levels.asm.\n')
        f.write('.deckDroidBase\n')
        emit_bytes(f, [mem[DECK_DROID_BASE + d] for d in range(NUM_DECKS)],
                   per_line=NUM_DECKS)
        f.write('\n')

    print('%s' % path)
    print('  sprites   %d rows x 7 = %d bytes  (+ %d offsets, %d digit ptrs)'
          % (len(rows), len(rows) * 7, len(offsets) * 2, NUM_TYPES * 2))
    print('  rotor     compiled: %d bytes draw + %d restore, 2 shifts'
          % (code_d, code_r))
    print('  waypoints %d records = %d bytes' % (len(wp_blob) // 3, len(wp_blob)))
    print('  per-deck waypoint counts: %s' % counts)


if __name__ == '__main__':
    main()
