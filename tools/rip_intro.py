#!/usr/bin/env python3
"""
rip_intro.py — Extract the CE loading-intro screen (three robots + credits)
and its 'flashing lightning' colour effect.

The intro is NOT in paradroid_ce.lst — it is the loader's own code, resident
only while the scroller runs. Source is therefore a VICE RAM dump taken while
the intro is on screen, not the listing:

  extracted/intro_ram.bin — 64K RAM dump + 2-byte header (VICE `bank ram; save`)
  extracted/intro_io.bin  — $D000-$DFFF IO-bank dump + 2-byte header

To regenerate the dumps, run the CE .prg in x64sc with a moncommands file that
`trace store d019` / `trace store d016` and `command N "save ..."` (the
unpack_prg.ps1 pattern) and kill it ~30 s in WITHOUT pressing any key — the
intro loops until SPACE, so the last save is intro state. Save the io bank in
a second run with `bank io`.

What the dump holds (all analysed from a disassembly of the intro loop, which
lives at $E000 in VIC bank 3):

  $E400  screen RAM, 40×25          $E800  custom charset, 2K
  $E191  25-byte per-ROW colour-RAM table, stored bottom row first
  $E1C4  four 16-byte flash colourway blocks
  $E204  16-byte flash envelope (offsets into the current block)
  $E214  24 colour-RAM cell offsets that carry the flash glow

Display: multicolour text mode, VIC bank 3, D018=$9B. Raster-split at line
$B2 by polled busy-wait: above it D016=$D8 (MC on) and D021/22/23 come from
the flash state; below it D016=$C8, D021=0 — the credits render as plain
hires text on black, coloured per row. The 'sky' is char $20, which in this
charset is SOLID 11-pixels, so the sky colour is per-row colour RAM ($0E →
MC colour 6, blue), NOT the background register. At rest D021/22/23 are all
BLACK: the picture is a blue sky, black silhouettes and a black floor, and
every 'metal' detail pixel (01/10 pairs) is invisible until a flash lights
D022/D023 up.

The flash: checked every 32 frames while $FC (a free-running frame counter)
is in $50..$CF, gated on a CIA-timer random byte. When it fires, one of four
colourway blocks is picked at random and a 15-frame envelope runs, one step
per frame, taking block offsets 0,4,8,C,C,C,8,8,8,8,4,4,4,4,0 — attack to
peak in 4 frames, hold 2, decay 9. Each 4-byte step is [D021, D022, D023,
glow], glow being written every frame to the 24 cells at $E214 plus $D93A/
$D95F/$D964 (the robots' torsos and the machine top). The four colourways
peak grey/white, orange/yellow, red, and green. A flash also triggers the
SID thunder voice ($81/$82).

Two smaller always-on animations, independent of the flash:
  * eyes — three cell PAIRS at $D800+{$16,$2E,$99} (the three heads) cycle
    through 0A 0C 0F 09 09 0F 0C 0A, each with its own phase, stepping every
    4th frame;
  * console sparkle — for 32 frames out of every 128, cells $D900+{0,1,2,3,
    5,9,A} get (random&7)|8, position stepping every 4 frames.

Output (tools/output/):
  intro_screen.bin   1000 B screen RAM
  intro_charset.bin  2048 B charset
  intro_colram.bin   1000 B colour RAM, rest state, rebuilt the way the
                     intro's init code builds it (row fill + machine patches)
  intro_flash.txt    the effect tables, ready to transcribe
  intro_rest.png     rendered rest state
  intro_flash_N.png  each colourway rendered at peak (N=1..4)
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow required. pip install Pillow")
    sys.exit(1)

PROJECT = Path(r'C:\Users\khcon\OneDrive\Projects\Paradroid')
OUT_DIR = PROJECT / 'tools' / 'output'

# Pepto palette, same as the other rip tools
C64_PAL = [
    (0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x68, 0x37, 0x2B), (0x70, 0xA4, 0xB2),
    (0x6F, 0x3D, 0x86), (0x58, 0x8D, 0x43), (0x35, 0x28, 0x79), (0xB8, 0xC7, 0x6F),
    (0x6F, 0x4F, 0x25), (0x43, 0x39, 0x00), (0x9A, 0x67, 0x59), (0x44, 0x44, 0x44),
    (0x6C, 0x6C, 0x6C), (0x9A, 0xD2, 0x84), (0x6C, 0x5E, 0xB5), (0x95, 0x95, 0x95),
]

SCREEN   = 0xE400
CHARSET  = 0xE800
ROWCOLS  = 0xE191   # 25 bytes, bottom row first
BLOCKS   = 0xE1C4   # 4 × 16 bytes
ENVELOPE = 0xE204   # 16 bytes (index 15 down to 1 used)
GLOWCELL = 0xE214   # 24 colour-RAM offsets
GLOW_EXTRA = [0x13A, 0x15F, 0x164]          # $D93A, $D95F, $D964
EYE_PAIRS  = [0x16, 0x2E, 0x99]             # + the cell after each
EYE_RING   = [0x0A, 0x0C, 0x0F, 0x09, 0x09, 0x0F, 0x0C, 0x0A]
SPARKLE    = [0x100 + o for o in (0, 1, 2, 3, 5, 9, 0x0A)]
SPLIT_ROW  = 16     # raster $B2 = end of char row 15


def build_colram(ram):
    """Rebuild colour RAM exactly as the intro's init at $E000 does."""
    col = bytearray(1000)
    # per-row fill, table stored bottom row first
    for row in range(25):
        v = ram[ROWCOLS + 24 - row]
        for c in range(40):
            col[row * 40 + c] = v
    # machine patches, all $08 (MC, colour 0): three 4-cell runs...
    for base in (0x0A5, 0x08D, 0x110):
        for i in range(4):
            col[base + i] = 0x08
    # ...and six 12-cell runs down the machine body
    for base in (0x129, 0x151, 0x179, 0x1A1, 0x1C9, 0x1F1):
        for i in range(12):
            col[base + i] = 0x08
    return col


def render(ram, colram, d021, d022, d023, glow, name):
    img = Image.new('RGB', (320, 200))
    px = img.load()
    col = bytearray(colram)
    for o in [ram[GLOWCELL + i] for i in range(24)] + GLOW_EXTRA:
        col[o] = glow
    for i, o in enumerate(EYE_PAIRS):
        col[o] = col[o + 1] = EYE_RING[(6, 3, 0)[i]]   # counters' init phases
    for row in range(25):
        mc_region = row < SPLIT_ROW
        bg = [d021, d022, d023] if mc_region else [0, 0, 0]
        for c in range(40):
            code = ram[SCREEN + row * 40 + c]
            attr = col[row * 40 + c]
            mc = mc_region and (attr & 8)
            for y in range(8):
                b = ram[CHARSET + code * 8 + y]
                if mc:
                    for p in range(4):
                        bits = (b >> (6 - p * 2)) & 3
                        rgb = C64_PAL[(bg + [attr & 7])[bits]]
                        px[c * 8 + p * 2, row * 8 + y] = rgb
                        px[c * 8 + p * 2 + 1, row * 8 + y] = rgb
                else:
                    for p in range(8):
                        on = (b >> (7 - p)) & 1
                        px[c * 8 + p, row * 8 + y] = C64_PAL[attr & 7 if on else bg[0]]
    img = img.resize((640, 400), Image.NEAREST)
    img.save(OUT_DIR / name)
    print(f"  {name}")


def main():
    ram = Path(PROJECT / 'extracted' / 'intro_ram.bin').read_bytes()[2:]
    OUT_DIR.mkdir(exist_ok=True)

    (OUT_DIR / 'intro_screen.bin').write_bytes(ram[SCREEN:SCREEN + 1000])
    (OUT_DIR / 'intro_charset.bin').write_bytes(ram[CHARSET:CHARSET + 2048])
    colram = build_colram(ram)
    (OUT_DIR / 'intro_colram.bin').write_bytes(colram)

    # sanity: rebuilt colour RAM must match the live dump except at the
    # animated cells (glow, eyes, sparkle) — anything else means the
    # analysis of the init code is wrong
    io_path = PROJECT / 'extracted' / 'intro_io.bin'
    if io_path.exists():
        io = io_path.read_bytes()[2:]
        animated = set(ram[GLOWCELL + i] for i in range(24)) | set(GLOW_EXTRA) \
                 | set(SPARKLE) | set(o + d for o in EYE_PAIRS for d in (0, 1))
        bad = [i for i in range(1000)
               if i not in animated and (io[0x800 + i] ^ colram[i]) & 0x0F]
        if bad:
            print(f"WARNING: rebuilt colour RAM differs from dump at {len(bad)} "
                  f"static cells, first at offset ${bad[0]:03X} — analysis wrong?")
        else:
            print("colour RAM rebuild matches the live dump at every static cell")

    with open(OUT_DIR / 'intro_flash.txt', 'w') as f:
        f.write("Flash envelope (block offsets, one per frame): "
                + ' '.join(f'{ram[ENVELOPE + x]:02X}' for x in range(15, 0, -1)) + '\n')
        for b in range(4):
            steps = [ram[BLOCKS + b * 16 + o:BLOCKS + b * 16 + o + 4] for o in (0, 4, 8, 12)]
            f.write(f"colourway {b + 1} [D021 D022 D023 glow] rest->peak: "
                    + ' | '.join(' '.join(f'{v:02X}' for v in s) for s in steps) + '\n')
        f.write("row colours top->bottom: "
                + ' '.join(f'{ram[ROWCOLS + 24 - r]:02X}' for r in range(25)) + '\n')
        f.write("glow cells (colour-RAM offsets): "
                + ' '.join(f'{ram[GLOWCELL + i]:03X}' for i in range(24))
                + ' + ' + ' '.join(f'{o:03X}' for o in GLOW_EXTRA) + '\n')
        f.write("eye pairs at offsets " + ' '.join(f'{o:03X}' for o in EYE_PAIRS)
                + f", ring {' '.join(f'{v:02X}' for v in EYE_RING)}, step every 4 frames\n")
        f.write("sparkle cells: " + ' '.join(f'{o:03X}' for o in SPARKLE)
                + " get (rnd&7)|8 for 32 frames in every 128\n")
    print("  intro_flash.txt")

    render(ram, colram, 0, 0, 0, 0x08, 'intro_rest.png')
    for b in range(4):
        d021, d022, d023, glow = ram[BLOCKS + b * 16 + 12:BLOCKS + b * 16 + 16]
        render(ram, colram, d021, d022, d023, glow, f'intro_flash_{b + 1}.png')


if __name__ == '__main__':
    main()
