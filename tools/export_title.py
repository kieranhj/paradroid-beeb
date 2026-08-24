#!/usr/bin/env python3
"""
export_title.py - the C64 title screen, as a self-contained BBC data file.

`Title_dat` at $CC00 is a raw 40x25 character screen, 1,000 bytes, that
`ShowTitle` ($2879) copies to screen RAM and colours by looking each code up in
`CharColor` ($0800). Thirty-six distinct codes compose it: block letters built
from the same $7800 characters the decks use, two bordered panels in the text
font, and the Hewson branding.

WHY IT CARRIES ITS OWN GLYPHS.  export_bbc.py converts only the characters some
TILE DEFINITION references - 137 of 256 - and twelve of the title's thirty-six
are not among them ($52 $53 $DF $E0-$E7 $FF), because nothing but the title
screen uses them.  Adding them to the shared charset would work and would be
the more faithful arrangement, but it changes NUM_CHARS and the code->index
remap that every deck's rendering depends on, so it is KC's call rather than
something to do in passing.  Until then the title ships the thirty-six glyphs
it needs, converted here, and touches nothing else.
    -> src/data/title.asm

COLOUR - and this is where the emboss comes from.  The C64 screen is HIRES
(`Irq1` $2922 writes $D016 = $C8, bit 4 clear), so a cell is the shared
background plus ONE foreground colour, and `ShowTitle` makes a second pass over
the same 1,000 codes writing $D800 from `CharColor` ($0800): colour is a
property of the CHARACTER CODE, not of the cell.  `CharColor`'s high nibble is a
fixed SLOT and `NewCharColors` ($3577) patches the low nibble per deck from the
current colour scheme - so the slot is artwork and the physical is the palette.

Measured against ref/c64-logo-screen.png on a fitted grid, the whole screen is
five slots:

    slot 0  484 cells  code $00, blank - the background shows through
    slot 9  247 cells  (241,238,251) white  - highlight strokes, top-left
    slot 7  249 cells  (100, 79,180) violet - shadow strokes, bottom-right
    slot 4   17 cells  ( 23, 15, 61) near-black - the BY ANDREW / BRAYBROOK text
    slot E    3 cells  green - the three blobs

The highlight and its shadow sit about three character cells apart and never
share one, so NOTHING here needs per-pixel colour: baking the slot's logical
colour into each of the 36 glyphs reproduces it exactly, and costs no data, no
code in TiCell and no change to the RLE stream.

SLOT_LOGICAL below is that mapping, onto the port's fixed slot roles (main.asm):
0 = the deck background, 1 = black, 2 = the deck highlight, 3 = white.  Those
four ARE the four tones the logo wants, so the only substitution is slot E's
green - three decorative cells - taking the deck highlight instead.  The title
inherits palPlay from the last deck played (KC 2026-08-22, src/title.asm), which
makes this the same split the C64 has: fixed slot here, per-deck physical there.

RLE.  The 25 rows are 640 bytes each and contiguous, so the whole screen is one
linear run of 1,000 cells and a run may cross a row end.  A token below $80 is
a literal glyph index; $80+n is a run of n+1 cells whose index follows.  $FF
ends the stream.  Thirty-six glyphs leaves the high bit free for exactly this.
"""

import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_FILE = PROJECT / 'src' / 'data' / 'title.asm'

TITLE_ADDR = 0xCC00
CHARCOLOR_ADDR = 0x0800     # 256 bytes; high nibble = colour slot
TITLE_COLS = 40
TITLE_ROWS = 25
CHARSET_ADDR = 0x7800


def parse_listing(path):
    """The .BYTE scrape rip_screens.py uses, verbatim less its `filled` map.

    A .BYTE block carries its address on the FIRST line only and continues on
    the ones after it, so the running offset is not optional: without it every
    continuation line lands back on the block's own address and a 1,000-byte
    screen reads as one character repeated.
    """
    mem = bytearray(65536)
    current_base = None
    running_offset = 0
    with open(path, 'r', encoding='latin-1') as f:
        for line in f:
            m = re.match(r'^([0-9A-Fa-f]{4})\s', line)
            if not m:
                continue
            addr = int(m.group(1), 16)
            bm = re.search(r'\.BYTE\s+(.*)', line)
            if not bm:
                if re.search(r'(LDA|STA|LDX|STX|LDY|STY|JSR|JMP|RTS|RTI|BEQ|BNE'
                             r'|BPL|BMI|BCS|BCC|BVS|BVC|CLC|SEC|CLI|SEI|NOP|PHA|PLA'
                             r'|TAX|TAY|TXA|TYA|TSX|TXS|INX|INY|DEX|DEY|INC|DEC|ADC'
                             r'|SBC|AND|ORA|EOR|CMP|CPX|CPY|ASL|LSR|ROL|ROR|BIT|PHP'
                             r'|PLP|BRK|SED|CLD|CLV)', line):
                    current_base = None
                continue
            vals = []
            for v in re.sub(r';.*', '', bm.group(1)).split(','):
                v = v.strip()
                if not v:
                    continue
                try:
                    vals.append(int(v[1:], 16) if v.startswith('$') else int(v))
                except ValueError:
                    break
            if not vals:
                continue
            if current_base is None or addr != current_base:
                current_base = addr
                running_offset = 0
            base = current_base + running_offset
            for i, b in enumerate(vals):
                mem[(base + i) & 0xFFFF] = b & 0xFF
            running_offset += len(vals)
    return mem


def mode1_byte(pixels):
    """Four logical colours into one MODE 1 byte: bit 7-n high, bit 3-n low."""
    out = 0
    for n, c in enumerate(pixels):
        if c & 2:
            out |= 1 << (7 - n)
        if c & 1:
            out |= 1 << (3 - n)
    return out


# C64 CharColor slot -> BBC MODE 1 logical colour.  See COLOUR in the header.
SLOT_LOGICAL = {
    0x0: 0,     # blank cells - the deck background
    0x9: 3,     # highlight strokes -> white
    0x7: 1,     # shadow strokes    -> black.  The C64's is a dark tint of its
                #                     background; black is the nearest role
    0x4: 1,     # panel lettering   -> black, and the C64's is near-black too
    0xE: 2,     # the three green blobs -> the deck highlight.  The one
                #                     substitution: MODE 1 has no fifth colour
}


def glyph16(rows, fg=3, bg=0):
    """One C64 character (8 bytes, hires) -> one MODE 1 cell (16 bytes).

    Left half's eight scanlines then the right half's, which is what makes
    plotting a character a flat copy - see CLAUDE.md.
    """
    px = [[fg if (b >> (7 - p)) & 1 else bg for p in range(8)] for b in rows]
    return bytearray([mode1_byte(p[0:4]) for p in px] +
                     [mode1_byte(p[4:8]) for p in px])


def rle_pack(indices):
    """Literal/run tokens over the whole 1,000 cells - see the header."""
    out = bytearray()
    i = 0
    n = len(indices)
    while i < n:
        j = i
        while j < n and indices[j] == indices[i] and j - i < 0x7E:
            j += 1
        run = j - i
        if run == 1:
            out.append(indices[i])
        else:
            out.append(0x80 | (run - 1))
            out.append(indices[i])
        i = j
    out.append(0xFF)
    return out


def emit_bytes(f, data, per_line=16):
    for i in range(0, len(data), per_line):
        f.write('  EQUB ' + ', '.join('&%02X' % b for b in data[i:i + per_line]) + '\n')


def main():
    if not LST_FILE.exists():
        sys.exit('ERROR: %s not found. See README.' % LST_FILE)
    mem = parse_listing(LST_FILE)

    screen = mem[TITLE_ADDR:TITLE_ADDR + TITLE_COLS * TITLE_ROWS]
    codes = sorted(set(screen))
    remap = {c: i for i, c in enumerate(codes)}
    indices = [remap[c] for c in screen]

    slots = {c: mem[CHARCOLOR_ADDR + c] >> 4 for c in codes}
    unknown = sorted({v for v in slots.values() if v not in SLOT_LOGICAL})
    if unknown:
        sys.exit('ERROR: the title uses CharColor slot(s) %s, which '
                 'SLOT_LOGICAL does not map. Read the COLOUR note in this '
                 'file before adding one - MODE 1 has four logical colours '
                 'and the five known slots already need one substitution.'
                 % ' '.join('$%X' % v for v in unknown))

    glyphs = bytearray()
    for c in codes:
        glyphs += glyph16(mem[CHARSET_ADDR + c * 8:CHARSET_ADDR + c * 8 + 8],
                          fg=SLOT_LOGICAL[slots[c]])

    packed = rle_pack(indices)

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_FILE, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\\ Generated by tools/export_title.py - do not edit.\n')
        f.write('\\ Title_dat ($CC00): %d x %d characters, %d distinct, drawn\n'
                % (TITLE_COLS, TITLE_ROWS, len(codes)))
        f.write('\\ from the $7800 charset, each glyph in the logical\n')
        f.write('\\ colour its CharColor ($0800) slot maps to.\n')
        f.write('\\ Read the tool header before changing anything here.\n\n')
        f.write('TITLE_COLS   = %d\n' % TITLE_COLS)
        f.write('TITLE_ROWS   = %d\n' % TITLE_ROWS)
        f.write('TITLE_GLYPHS = %d\n\n' % len(codes))
        f.write('\\ %d glyphs x 16 bytes\n.titleGlyphs\n' % len(codes))
        emit_bytes(f, glyphs)
        f.write('\n\\ (count, index) pairs, runs inside a row, zero count ends\n')
        f.write('.titleRLE\n')
        emit_bytes(f, packed)
        f.write('.titleRLE_end\n')

    print('  title.asm  %5d bytes  (%d glyphs = %d B, map %d B RLE from %d)'
          % (len(glyphs) + len(packed), len(codes), len(glyphs),
             len(packed), TITLE_COLS * TITLE_ROWS))
    cells = {}
    for b in screen:
        cells[slots[b]] = cells.get(slots[b], 0) + 1
    print('  colour slots: ' + '  '.join(
        'slot $%X -> logical %d (%d cells)' % (v, SLOT_LOGICAL[v], n)
        for v, n in sorted(cells.items())))
    missing = [c for c in codes
               if c not in {mem[0xE800 + i] for i in range(32 * 16)}]
    print('  %d of the %d codes are not in the tile-referenced charset: %s'
          % (len(missing), len(codes), ' '.join('$%02X' % c for c in missing)))


if __name__ == '__main__':
    main()
