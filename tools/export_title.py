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

COLOUR.  Every glyph is rendered in logical 3 on logical 0.  Under the port's
fixed slot roles (main.asm) 3 is white and 0 is the deck background, and the
title runs before any deck is loaded, where MODE 1's default palette makes that
white on black - which is what the C64's title very nearly is.  The real title
palette is Layer 14's to settle; this is a starting point, not an answer.

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

    glyphs = bytearray()
    for c in codes:
        glyphs += glyph16(mem[CHARSET_ADDR + c * 8:CHARSET_ADDR + c * 8 + 8])

    packed = rle_pack(indices)

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_FILE, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\\ Generated by tools/export_title.py - do not edit.\n')
        f.write('\\ Title_dat ($CC00): %d x %d characters, %d distinct, drawn\n'
                % (TITLE_COLS, TITLE_ROWS, len(codes)))
        f.write('\\ from the $7800 charset in logical 3 on logical 0.\n')
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
    missing = [c for c in codes
               if c not in {mem[0xE800 + i] for i in range(32 * 16)}]
    print('  %d of the %d codes are not in the tile-referenced charset: %s'
          % (len(missing), len(codes), ' '.join('$%02X' % c for c in missing)))


if __name__ == '__main__':
    main()
