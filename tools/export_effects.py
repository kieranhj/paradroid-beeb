#!/usr/bin/env python3
"""export_effects.py - Layer 7 effect sprites (bullets and explosions) for the BBC port.

Writes src/data/effects.asm, which is assembled into SIDEWAYS BANK 5 alongside
the compiled blitter - not into bank 4 with the droid artwork. Two reasons, and
the second is the one that matters:

  SPACE.  Bank 4 has ~2.5K free and this is 2.7K of artwork before any tables.
          Bank 5 has ~4K. Bank 4 became the scarcer of the two when the level
          draw and the droid AI moved into it.

  PAGING. drSprData lives in bank 4 because SprFetchRow reads it on about one
          row in fifty and can afford to page the bank in around itself. An
          effect sprite is drawn ENTIRELY by the interpreted path, so its
          artwork is read on every row - paging per row would cost more than
          the blit. An effect never uses a compiled shift, so it does not care
          which sprite bank is selected, and it can simply live in the one the
          slot pages in anyway.

HIRES BULLETS, MULTICOLOUR EXPLOSIONS. dMd1_bullet ($187F) writes SpriteMC = 0
and ExplodeSprite ($1BE8) writes $FF, so the two halves are read differently:
a bullet is 24 one-bit pixels, an explosion 12 two-bit pixels each two wide.
Same 24-pixel width either way, so both become 6 MODE 1 bytes a row.

EVERYTHING OPAQUE BECOMES LOGICAL COLOUR 1, and that is a deliberate loss on
the explosion, which has three colours on the C64. MODE 1's four logicals are
the deck's own: logical 1 is white on all 16 decks, logical 2 is black on
fourteen of them, and logical 3 is BLACK ON DECKS 4 AND 11. An explosion drawn
in 3 would be invisible on two decks. This is the same argument that put the
droids on logical 1 - see export_droids.py - and the sprite MC colours cannot
be recovered from the listing anyway: $D025/$D026 are never written by the game
and the dump has the game's own text data overlaying $D022 upwards.

BOUNDING BOXES ARE THE WHOLE POINT. Stored unclipped these 31 frames are 4557
bytes and do not fit anywhere. Stored as (first row, height, first column,
width) plus just the bytes inside the box they are 2748, because most frames
are a streak across a mostly empty 24x21 sprite.

Requires: Python 3. No third-party dependencies.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_DIR = PROJECT / 'src' / 'data'

VIC_BANK = 0x4000           # sprite pointer N addresses VIC_BANK + N*64
SPRITE_ROWS = 21
EFFECT_COLOUR = 1           # MODE 1 logical; see the header

BULLET_SPRITE_T = 0x6E4C    # 12 entries: weaponType*4 + direction
BULLET_ANIM_MIN = 0x56      # MovePlyFire ($333E) only animates images >= this

EXPLODE_FIRST = 0x39        # ExplodeSprite sets this...
EXPLODE_LAST = 0x43         # ...and dMd2_explosion frees the slot at $44


def sprite_addr(ptr):
    return VIC_BANK + ptr * 64


def rows_hires(mem, ptr):
    """21 rows of 24 booleans. One bit per pixel, set = opaque."""
    out = []
    base = sprite_addr(ptr)
    for r in range(SPRITE_ROWS):
        px = []
        for b in range(3):
            byte = mem[base + r * 3 + b]
            for i in range(8):
                px.append((byte >> (7 - i)) & 1 != 0)
        out.append(px)
    return out


def rows_mc(mem, ptr):
    """21 rows of 24 booleans. Bit PAIRS, 12 a row, each two pixels wide.

    Pair 00 is transparent; 01, 10 and 11 are three different colours on the
    C64 and all become logical 1 here.
    """
    out = []
    base = sprite_addr(ptr)
    for r in range(SPRITE_ROWS):
        px = []
        for b in range(3):
            byte = mem[base + r * 3 + b]
            for i in range(4):
                on = ((byte >> (6 - i * 2)) & 3) != 0
                px.append(on)
                px.append(on)
        out.append(px)
    return out


def to_mode1(px):
    """24 booleans -> 6 MODE 1 bytes at EFFECT_COLOUR.

    Pixel n of a byte takes bit 7-n as its high colour bit and bit 3-n as its
    low one. Colour 1 sets only the low plane.
    """
    assert EFFECT_COLOUR != 0, (
        'an opaque pixel would map to logical 0 and the mask, which is derived '
        'from the data rather than stored, could no longer tell it from a hole')
    out = []
    for group in range(6):
        d = 0
        for n in range(4):
            if px[group * 4 + n]:
                if EFFECT_COLOUR & 2:
                    d |= 1 << (7 - n)
                if EFFECT_COLOUR & 1:
                    d |= 1 << (3 - n)
        out.append(d)
    return out


def frame_of(mem, ptr, mc):
    """-> (r0, h, c0, w, data) with data h*w bytes, or None if wholly empty."""
    px = rows_mc(mem, ptr) if mc else rows_hires(mem, ptr)
    grid = [to_mode1(row) for row in px]

    used_r = [i for i, row in enumerate(grid) if any(row)]
    used_c = sorted({c for row in grid for c, b in enumerate(row) if b})
    if not used_r:
        return None
    r0, r1 = used_r[0], used_r[-1]
    c0, c1 = used_c[0], used_c[-1]
    data = []
    for r in range(r0, r1 + 1):
        data.extend(grid[r][c0:c1 + 1])
    return r0, r1 - r0 + 1, c0, c1 - c0 + 1, data


def emit_bytes(f, data, per_line=12):
    for i in range(0, len(data), per_line):
        chunk = data[i:i + per_line]
        f.write('  EQUB ' + ','.join('&%02X' % b for b in chunk) + '\n')


def main():
    if not LST_FILE.exists():
        sys.exit('missing %s - see CLAUDE.md, it is gitignored' % LST_FILE)
    mem, _filled = parse_listing(LST_FILE)

    # ---- which C64 sprite images we need ---------------------------------
    explode = list(range(EXPLODE_FIRST, EXPLODE_LAST + 1))

    bullet_t = [mem[BULLET_SPRITE_T + i] for i in range(12)]
    # MovePlyFire toggles an image >= $56 between (n, n+1) for odd n, so both
    # halves of every animated pair have to ship.
    anim = set()
    for b in bullet_t:
        if b >= BULLET_ANIM_MIN:
            anim.add(b)
            anim.add(b + 1 if b & 1 else b - 1)
    bullets = sorted(set(b for b in bullet_t if b < BULLET_ANIM_MIN) | anim)

    # Frame ids: explosion first and contiguous, so dMd2 can just add one.
    order = [(p, True) for p in explode] + [(p, False) for p in bullets]
    frame_id = {p: i for i, (p, _mc) in enumerate(order)}

    frames = []
    for ptr, mc in order:
        fr = frame_of(mem, ptr, mc)
        if fr is None:
            sys.exit('sprite $%02X is empty - wrong pointer or wrong VIC bank' % ptr)
        frames.append(fr)

    # The animation partner of each frame, itself where it does not animate.
    alt = []
    for ptr, _mc in order:
        if ptr in explode or ptr < BULLET_ANIM_MIN:
            alt.append(frame_id[ptr])
        else:
            alt.append(frame_id[ptr + 1 if ptr & 1 else ptr - 1])

    # ---- write it out -----------------------------------------------------
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / 'effects.asm'
    blob = []
    offsets = []
    for _r0, _h, _c0, _w, data in frames:
        offsets.append(len(blob))
        blob.extend(data)

    with open(path, 'w', encoding='utf-8', newline='\n') as g:
        g.write('\\ ============================================================\n')
        g.write('\\ effects.asm\n')
        g.write('\\ GENERATED by tools/export_effects.py - do not edit by hand.\n')
        g.write('\\ Source: paradroid_ce.lst (Paradroid, C64 - original/CE lineage)\n')
        g.write('\\ Layer 7 effect sprites: %d explosion frames, %d bullet frames\n'
                % (len(explode), len(bullets)))
        g.write('\\ ============================================================\n\n')
        g.write('\\ IN SIDEWAYS BANK 5 with the blitter, NOT in bank 4 with the\n')
        g.write('\\ droid artwork. An effect sprite is drawn entirely by the\n')
        g.write('\\ interpreted path, so its rows are read on every row of every\n')
        g.write('\\ frame rather than one in fifty like drSprData - paging a\n')
        g.write('\\ different bank in per row would cost more than the blit. An\n')
        g.write('\\ effect never uses a compiled shift, so it does not care which\n')
        g.write('\\ sprite bank is up and can live in the one already selected.\n')
        g.write('\\\n')
        g.write('\\ EVERY OPAQUE PIXEL IS LOGICAL COLOUR 1. The explosion is\n')
        g.write('\\ multicolour on the C64 and has three; MODE 1 logical 3 is\n')
        g.write('\\ BLACK on decks 4 and 11 and logical 2 on fourteen decks, so 1\n')
        g.write('\\ is the only one that is visible everywhere. Same argument as\n')
        g.write('\\ the droids. The C64 sprite MC colours are not recoverable\n')
        g.write('\\ from the listing in any case - $D025/$D026 are never written.\n')
        g.write('\\\n')
        g.write('\\ Each frame is a BOUNDING BOX - first row, height, first byte\n')
        g.write('\\ column, width - and only the bytes inside it. Unclipped these\n')
        g.write('\\ frames would be %d bytes and would not fit anywhere.\n\n'
                % (len(frames) * SPRITE_ROWS * 7))

        g.write('EF_FRAMES     = %d\n' % len(frames))
        g.write('EF_EXPLODE    = %d               \\ frames %d-%d, in order\n'
                % (frame_id[explode[0]], frame_id[explode[0]], frame_id[explode[-1]]))
        g.write('EF_EXPLODE_N  = %d\n' % len(explode))
        g.write('EF_SPRITE_ROWS = %d              \\ checked against SPR_H\n\n'
                % SPRITE_ROWS)

        g.write('\\ Frame geometry. efR0/efC0 are where the box sits inside the\n')
        g.write('\\ nominal 24 x 21 sprite; efH/efW are what is actually stored.\n')
        g.write('.efR0\n')
        emit_bytes(g, [f[0] for f in frames])
        g.write('.efH\n')
        emit_bytes(g, [f[1] for f in frames])
        g.write('.efC0\n')
        emit_bytes(g, [f[2] for f in frames])
        g.write('.efW\n')
        emit_bytes(g, [f[3] for f in frames])
        g.write('\n')

        g.write('\\ Where each frame\'s rows start, as a full address.\n')
        g.write('.efDataLo\n')
        emit_bytes(g, [(o + 0) & 0xFF for o in offsets])
        g.write('.efDataHi\n')
        emit_bytes(g, [(o >> 8) & 0xFF for o in offsets])
        g.write('\n')

        g.write('\\ The animation partner of each frame, or the frame itself\n')
        g.write('\\ where it does not animate. MovePlyFire ($333E) toggles an\n')
        g.write('\\ image between n and n+1, but only for images >= $%02X, which\n'
                % BULLET_ANIM_MIN)
        g.write('\\ is why the slow weapon-0 bullets sit still and the others\n')
        g.write('\\ flicker.\n')
        g.write('.efAlt\n')
        emit_bytes(g, alt)
        g.write('\n')

        g.write('\\ Frame id per weaponType*4 + direction, replacing the C64\'s\n')
        g.write('\\ BulletSprite_t ($6E4C) - same table, resolved to our frame\n')
        g.write('\\ numbering. DoFire and AddBullet both index it.\n')
        g.write('.efBullet\n')
        emit_bytes(g, [frame_id[b] for b in bullet_t])
        g.write('\n')

        g.write('.efData\n')
        emit_bytes(g, blob)
        g.write('.efData_end\n')

    print('%s' % path)
    print('  explosion %2d frames  %5d B' % (len(explode), sum(f[1] * f[3] for f in frames[:len(explode)])))
    print('  bullets   %2d frames  %5d B' % (len(bullets), sum(f[1] * f[3] for f in frames[len(explode):])))
    print('  tables               %5d B' % (len(frames) * 6 + 12))
    print('  TOTAL                %5d B   (unclipped would be %d)'
          % (len(blob) + len(frames) * 6 + 12, len(frames) * SPRITE_ROWS * 7))


if __name__ == '__main__':
    main()
