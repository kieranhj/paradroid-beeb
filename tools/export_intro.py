#!/usr/bin/env python3
"""
export_intro.py — build the BBC intro screen and effect tables from the
VICE dump of the C64 loading intro.

Input is extracted/intro_ram.bin (NOT the listing — the intro is the
loader's own code; see docs/graphics.md §10 and tools/rip_intro.py, whose
constants and colour-RAM rebuild this tool imports). The plan and the
colour-model decisions are docs/intro.md §1–§2.

The conversion, in one paragraph: the C64 picture region (rows 0–15,
multicolour) maps pixel-class → MODE 1 logical colour — 00→0, 01→1,
10→2, and 11 by cell: the 27 glow cells →2 (they light with the flash,
[DECISION 2]), the eyes →3, sky cells (colour-RAM colour 6) →3,
everything else (the $08 machine/floor cells) →0. One C64 MC pixel is
two MODE 1 pixels. The credits region (rows 16–24, hires) maps 1:1 with
each row's pixels in one of three foreground logicals ([DECISION 4]).
The 25 C64 rows sit at MODE 1 rows 3–27; rows 0–2 and 28–31 are black.

Output:
  src/data/introscr.zx0   the 20K MODE 1 bitmap, ZX0-compressed
                          (bin/zx0.exe, round-trip-verified by zx0.py)
  src/data/introfx.asm    rest + credits palettes and the four colourway
                          step tables, in ULA register form — the
                          runtime does no translation
  tools/output/intro_bbc.bin       the raw bitmap, for the jsbeeb diff
  tools/output/intro_bbc_rest.png  expected output, rest state
  tools/output/intro_bbc_flash_N.png  each colourway at peak
"""

import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow required. pip install Pillow")
    sys.exit(1)

sys.path.insert(0, str(Path(__file__).parent))
import zx0
import rip_intro as rip

PROJECT = rip.PROJECT
OUT_DATA = PROJECT / 'src' / 'data'
OUT_DIR = PROJECT / 'tools' / 'output'

TOP_ROWS = 3                    # blank MODE 1 rows above the picture
SPLIT_C64_ROW = 16              # C64 rows 0..15 picture, 16..24 credits

# C64 colour → BBC physical, for every colour the intro uses. The BBC has
# no grey, orange, purple or brown; docs/intro.md §1 has the reasoning and
# marks this tune-by-eye.
C64_TO_BBC = {
    0x00: 0, 0x01: 7, 0x02: 1, 0x03: 6, 0x05: 2, 0x06: 4, 0x07: 3,
    0x08: 1, 0x09: 1, 0x0A: 5, 0x0B: 4, 0x0C: 6, 0x0D: 2, 0x0E: 4,
    0x0F: 7,
}

SKY_PHYS = C64_TO_BBC[0x06]     # logical 3 in the picture region
CRED_PHYS = [0, 5, 6, 2]        # credits region logicals 0-3 [DECISION 4]

# credits row → logical, from the C64 per-row colours (graphics.md §10):
# logo $0A/$0A → 1 (magenta), the blues $06/$0E/$03 → 2 (cyan), the
# greens-and-yellow $0D/$05/$07 → 3 (green). Row 16 is the black bar.
CRED_ROW_LOG = {16: 0, 17: 1, 18: 1, 19: 2, 20: 2, 21: 2, 22: 3, 23: 3, 24: 3}

# MODE 1: each logical colour owns four of the sixteen palette entries
# (the CAM compares only bits 7 and 5 of the pixel value — the same
# arithmetic as src/rupture.asm's PALENT tables).
ENTRIES = [[0, 1, 4, 5], [2, 3, 6, 7], [8, 9, 12, 13], [10, 11, 14, 15]]

BBC_RGB = [(0, 0, 0), (255, 0, 0), (0, 255, 0), (255, 255, 0),
           (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)]


def build_logical(ram):
    """The 320×200 image as logical colour numbers 0-3."""
    colram = rip.build_colram(ram)
    glow = set(ram[rip.GLOWCELL + i] for i in range(24)) | set(rip.GLOW_EXTRA)
    eyes = set(o + d for o in rip.EYE_PAIRS for d in (0, 1))
    img = [[0] * 320 for _ in range(200)]
    for row in range(25):
        for col in range(40):
            o = row * 40 + col
            code = ram[rip.SCREEN + o]
            if row < SPLIT_C64_ROW:
                if o in glow:
                    l11 = 2
                elif o in eyes or (colram[o] & 7) == 6:
                    l11 = 3
                else:
                    l11 = 0
                lut = [0, 1, 2, l11]
                for y in range(8):
                    b = ram[rip.CHARSET + code * 8 + y]
                    for p in range(4):
                        l = lut[(b >> (6 - p * 2)) & 3]
                        img[row * 8 + y][col * 8 + p * 2] = l
                        img[row * 8 + y][col * 8 + p * 2 + 1] = l
            else:
                fg = CRED_ROW_LOG[row]
                for y in range(8):
                    b = ram[rip.CHARSET + code * 8 + y]
                    for p in range(8):
                        if (b >> (7 - p)) & 1:
                            img[row * 8 + y][col * 8 + p] = fg
    return img


def pack_mode1(img):
    """Logical image → 20K MODE 1 bitmap (32 rows × 640 bytes)."""
    bmp = bytearray(32 * 640)
    for y200 in range(200):
        y = y200 + TOP_ROWS * 8
        base = (y // 8) * 640 + (y % 8)
        for xc in range(80):                     # byte columns, 4 px each
            b = 0
            for p in range(4):
                l = img[y200][xc * 4 + p]
                b |= ((l >> 1) << (7 - p)) | ((l & 1) << (3 - p))
            bmp[base + xc * 8] = b
    return bytes(bmp)


def palette_bytes(phys_by_logical, logicals):
    """ULA bytes — (entry << 4) | (physical EOR 7) — for the given logicals."""
    out = []
    for l in logicals:
        for e in ENTRIES[l]:
            out.append((e << 4) | (phys_by_logical[l] ^ 7))
    return out


def colourway_steps(ram):
    """Per colourway, per envelope step, the (D021,D022,D023) → BBC physicals."""
    ways = []
    for b in range(4):
        steps = []
        for o in (0, 4, 8, 12):
            d021, d022, d023, _glow = ram[rip.BLOCKS + b * 16 + o:
                                          rip.BLOCKS + b * 16 + o + 4]
            steps.append([C64_TO_BBC[d021], C64_TO_BBC[d022], C64_TO_BBC[d023]])
        ways.append(steps)
    return ways


def render(img, pic_phys, name):
    im = Image.new('RGB', (320, 256))
    px = im.load()
    for y in range(256):
        y200 = y - TOP_ROWS * 8
        for x in range(320):
            if 0 <= y200 < 200:
                l = img[y200][x]
                phys = pic_phys[l] if y200 < SPLIT_C64_ROW * 8 else CRED_PHYS[l]
            else:
                phys = 0
            px[x, y] = BBC_RGB[phys]
    im.resize((640, 512), Image.NEAREST).save(OUT_DIR / name)
    print(f"  {name}")


def main():
    ram = (PROJECT / 'extracted' / 'intro_ram.bin').read_bytes()[2:]
    OUT_DIR.mkdir(exist_ok=True)
    OUT_DATA.mkdir(exist_ok=True)

    img = build_logical(ram)
    bmp = pack_mode1(img)
    (OUT_DIR / 'intro_bbc.bin').write_bytes(bmp)

    with tempfile.TemporaryDirectory() as td:
        src = Path(td) / 'in.bin'
        dst = Path(td) / 'out.zx0'
        src.write_bytes(bmp)
        subprocess.run([str(PROJECT / 'bin' / 'zx0.exe'), '-f',
                        str(src), str(dst)], check=True, capture_output=True)
        packed = dst.read_bytes()
    if zx0.decompress(packed) != bmp:
        raise SystemExit("zx0.exe stream fails zx0.py round-trip")
    (OUT_DATA / 'introscr.zx0').write_bytes(packed)
    print(f"  introscr.zx0  {len(bmp)} -> {len(packed)} bytes")

    ways = colourway_steps(ram)
    rest = palette_bytes([0, 0, 0, SKY_PHYS], [0, 1, 2, 3])
    cred = palette_bytes(CRED_PHYS, [0, 1, 2, 3])
    with open(OUT_DATA / 'introfx.asm', 'w') as f:
        f.write("\\ Generated by tools/export_intro.py - DO NOT EDIT.\n"
                "\\ Palettes and flash tables for PINTRO (docs/intro.md).\n"
                "\\ All values are ULA register form: (entry<<4) OR (phys EOR 7).\n\n")
        f.write(".palPicRest \\ picture region, rest: L0-2 black, L3 sky\n")
        f.write("  EQUB " + ",".join(f"&{v:02X}" for v in rest) + "\n\n")
        f.write(".palCred \\ credits region, constant\n")
        f.write("  EQUB " + ",".join(f"&{v:02X}" for v in cred) + "\n\n")
        f.write("\\ Four colourways x four envelope steps x 12 bytes: the\n"
                "\\ palette entries for logicals 0,1,2 (D021,D022,D023 ramps,\n"
                "\\ pre-mapped to BBC physicals). Step 0 = rest, 3 = peak.\n")
        f.write(".cwSteps\n")
        for w, steps in enumerate(ways):
            for s, phys3 in enumerate(steps):
                vals = palette_bytes(phys3 + [0], [0, 1, 2])
                f.write("  EQUB " + ",".join(f"&{v:02X}" for v in vals)
                        + f" \\ cw{w + 1} step {s}\n")
    print("  introfx.asm")

    render(img, [0, 0, 0, SKY_PHYS], 'intro_bbc_rest.png')
    for w, steps in enumerate(ways):
        render(img, steps[3] + [SKY_PHYS], f'intro_bbc_flash_{w + 1}.png')


if __name__ == '__main__':
    main()
