#!/usr/bin/env python3
"""
rip_graphics.py — Extract and render C64 Paradroid CE graphics from the
IDA disassembly listing (paradroid_ce.lst).

Produces:
  tools/output/sprites_hires.png      — All hi-res sprites (24x21, 64-byte blocks)
  tools/output/sprites_multicolor.png — All multicolor sprites (12x21 doubled)
  tools/output/charset_4800.png       — Character set at $4800 (console font)
  tools/output/charset_6800.png       — Character set at $6800 (game area)
  tools/output/charset_7800.png       — Character set at $7800 (main tiles)
  tools/output/memory_map.txt         — Summary of what's where

Requires: Pillow (pip install Pillow)
"""

import re
import os
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("ERROR: Pillow required. pip install Pillow")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
PROJECT = Path(r'C:\Users\khcon\OneDrive\Projects\Paradroid')
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_DIR = PROJECT / 'tools' / 'output'

VIC_BANK = 0x4000           # VIC-II bank 1 base
SPRITE_SIZE = 64            # bytes per C64 sprite slot (63 data + 1 pad)
SPRITE_W = 24               # pixels wide (hi-res)
SPRITE_H = 21               # pixels tall
CHAR_SIZE = 8               # bytes per character (8x8)

# C64 colour palette (VIC-II, approximate RGB)
C64_PALETTE = [
    (0x00, 0x00, 0x00),  # 0  black
    (0xFF, 0xFF, 0xFF),  # 1  white
    (0x88, 0x39, 0x32),  # 2  red
    (0x67, 0xB6, 0xBD),  # 3  cyan
    (0x8B, 0x3F, 0x96),  # 4  purple
    (0x55, 0xA0, 0x49),  # 5  green
    (0x40, 0x31, 0x8D),  # 6  blue
    (0xBF, 0xCE, 0x72),  # 7  yellow
    (0x8B, 0x54, 0x29),  # 8  orange
    (0x57, 0x42, 0x00),  # 9  brown
    (0xB8, 0x69, 0x62),  # 10 light red
    (0x50, 0x50, 0x50),  # 11 dark grey
    (0x78, 0x78, 0x78),  # 12 grey
    (0x94, 0xE0, 0x89),  # 13 light green
    (0x78, 0x69, 0xC4),  # 14 light blue
    (0x9F, 0x9F, 0x9F),  # 15 light grey
]

# ---------------------------------------------------------------------------
# Step 1: Parse the listing into a 64K memory image
# ---------------------------------------------------------------------------
def parse_listing(path):
    """Parse IDA .lst file, return bytearray[65536] with all .BYTE data filled in."""
    mem = bytearray(65536)
    filled = bytearray(65536)  # track which bytes are filled

    # For blocks where IDA repeats the same base address, we track running offset
    current_base = None
    running_offset = 0

    with open(path, 'r', encoding='latin-1') as f:
        for line in f:
            # Match lines with .BYTE data
            # Format: ADDR HH HH HH+  .BYTE val, val, val, ...
            # or:     ADDR HH HH HH+  .BYTE $xx, $xx, ...
            m = re.match(r'^([0-9A-Fa-f]{4})\s', line)
            if not m:
                continue

            addr = int(m.group(1), 16)

            # Check for .BYTE directive
            byte_match = re.search(r'\.BYTE\s+(.*)', line)
            if not byte_match:
                # Only reset base on actual instruction lines, not on
                # comment/cross-reference lines that IDA inserts within data blocks
                if re.search(r'\b(LDA|STA|LDX|STX|LDY|STY|JSR|JMP|RTS|RTI|BEQ|BNE|BPL|BMI|BCS|BCC|BVS|BVC|CLC|SEC|CLI|SEI|NOP|PHA|PLA|TAX|TAY|TXA|TYA|TSX|TXS|INX|INY|DEX|DEY|INC|DEC|ADC|SBC|AND|ORA|EOR|CMP|CPX|CPY|ASL|LSR|ROL|ROR|BIT|PHP|PLP|BRK|SED|CLD|CLV)\b', line):
                    current_base = None
                continue

            # Parse .BYTE values
            val_str = byte_match.group(1)
            # Remove comments (anything after ;)
            val_str = re.sub(r';.*', '', val_str)
            # Split by comma, parse each value
            values = []
            for v in val_str.split(','):
                v = v.strip()
                if not v:
                    continue
                try:
                    if v.startswith('$'):
                        values.append(int(v[1:], 16))
                    elif v.startswith('0x'):
                        values.append(int(v, 16))
                    else:
                        values.append(int(v))
                except ValueError:
                    break  # stop at non-numeric (labels, expressions)

            if not values:
                continue

            # Determine actual address for this line
            if current_base is None or addr != current_base:
                # New block or address changed
                current_base = addr
                running_offset = 0

            actual_addr = current_base + running_offset

            # Write bytes to memory
            for i, b in enumerate(values):
                a = (actual_addr + i) & 0xFFFF
                mem[a] = b & 0xFF
                filled[a] = 1

            running_offset += len(values)

    return mem, filled


# ---------------------------------------------------------------------------
# Step 2: Render C64 hi-res sprites
# ---------------------------------------------------------------------------
def render_sprite_hires(mem, base_addr, fg=(255, 255, 255), bg=(0, 0, 0)):
    """Render a single C64 hi-res sprite (24x21) as a PIL Image."""
    img = Image.new('RGB', (SPRITE_W, SPRITE_H), bg)
    for row in range(SPRITE_H):
        for col_byte in range(3):  # 3 bytes per row
            byte = mem[base_addr + row * 3 + col_byte]
            for bit in range(8):
                if byte & (0x80 >> bit):
                    x = col_byte * 8 + bit
                    img.putpixel((x, row), fg)
    return img


def render_sprite_multicolor(mem, base_addr, colors):
    """Render a C64 multicolor sprite (12x21 logical pixels, 24x21 physical).
    colors = [bg, mc1, sprite_color, mc2] (4 entries, RGB tuples)
    """
    img = Image.new('RGB', (SPRITE_W, SPRITE_H), colors[0])
    for row in range(SPRITE_H):
        for col_byte in range(3):
            byte = mem[base_addr + row * 3 + col_byte]
            for pair in range(4):  # 4 pixel pairs per byte
                bits = (byte >> (6 - pair * 2)) & 0x03
                color = colors[bits]
                x = col_byte * 8 + pair * 2
                img.putpixel((x, row), color)
                img.putpixel((x + 1, row), color)
    return img


def is_empty_sprite(mem, addr):
    """Check if a 63-byte sprite is all zeros."""
    return all(mem[addr + i] == 0 for i in range(63))


def render_sprite_sheet(mem, start, end, title, scale=4, multicolor=False):
    """Render a grid of sprites from start to end (64-byte aligned)."""
    sprites = []
    addrs = []
    for addr in range(start, end, SPRITE_SIZE):
        if not is_empty_sprite(mem, addr):
            sprites.append(addr)
            addrs.append(addr)

    if not sprites:
        print(f"  {title}: no non-empty sprites found in ${start:04X}-${end:04X}")
        return None, []

    # Grid layout: 16 columns
    cols = 16
    rows = (len(sprites) + cols - 1) // cols

    cell_w = SPRITE_W * scale + 2
    cell_h = SPRITE_H * scale + 14  # room for address label
    sheet_w = cols * cell_w + 2
    sheet_h = rows * cell_h + 20  # title bar

    sheet = Image.new('RGB', (sheet_w, sheet_h), (32, 32, 32))
    draw = ImageDraw.Draw(sheet)

    # Title
    draw.text((4, 2), f"{title}  ({len(sprites)} sprites)", fill=(255, 255, 100))

    mc_colors = [C64_PALETTE[0], C64_PALETTE[15], C64_PALETTE[1], C64_PALETTE[12]]

    for idx, addr in enumerate(sprites):
        col = idx % cols
        row = idx // cols
        x0 = col * cell_w + 2
        y0 = row * cell_h + 20

        if multicolor:
            spr = render_sprite_multicolor(mem, addr, mc_colors)
        else:
            spr = render_sprite_hires(mem, addr)

        spr_scaled = spr.resize((SPRITE_W * scale, SPRITE_H * scale), Image.NEAREST)
        sheet.paste(spr_scaled, (x0, y0))
        draw.text((x0, y0 + SPRITE_H * scale + 1),
                  f"${addr:04X}", fill=(180, 180, 180))

    print(f"  {title}: {len(sprites)} sprites, sheet {sheet_w}x{sheet_h}")
    return sheet, addrs


# ---------------------------------------------------------------------------
# Step 3: Render character sets
# ---------------------------------------------------------------------------
def render_charset(mem, base_addr, title, num_chars=256, scale=4):
    """Render a C64 character set (8x8 mono chars) as a sprite sheet."""
    cols = 32  # 32 chars per row
    rows = (num_chars + cols - 1) // cols

    cell_w = 8 * scale
    cell_h = 8 * scale
    sheet_w = cols * cell_w + 2
    sheet_h = rows * cell_h + 20

    sheet = Image.new('RGB', (sheet_w, sheet_h), (32, 32, 32))
    draw = ImageDraw.Draw(sheet)

    non_empty = 0
    for ch in range(num_chars):
        addr = base_addr + ch * CHAR_SIZE
        col = ch % cols
        row = ch // cols
        x0 = col * cell_w + 1
        y0 = row * cell_h + 16

        is_empty = all(mem[addr + i] == 0 for i in range(8))
        if not is_empty:
            non_empty += 1

        # Draw char cell background
        draw.rectangle([x0 - 1, y0 - 1, x0 + 8 * scale, y0 + 8 * scale],
                       fill=(16, 16, 40) if is_empty else (0, 0, 80))

        for py in range(8):
            byte = mem[addr + py]
            for px in range(8):
                if byte & (0x80 >> px):
                    sx = x0 + px * scale
                    sy = y0 + py * scale
                    draw.rectangle([sx, sy, sx + scale - 1, sy + scale - 1],
                                   fill=(255, 255, 255))

    draw.text((4, 2), f"{title}  (${base_addr:04X}, {non_empty}/{num_chars} non-empty)",
              fill=(255, 255, 100))

    print(f"  {title}: {non_empty}/{num_chars} non-empty chars")
    return sheet


# ---------------------------------------------------------------------------
# Step 4: Identify and dump all graphics regions
# ---------------------------------------------------------------------------
def find_sprite_regions(mem, filled):
    """Find contiguous non-empty 64-byte aligned blocks in VIC bank."""
    regions = []
    addr = VIC_BANK
    while addr < VIC_BANK + 0x4000:
        if not is_empty_sprite(mem, addr):
            start = addr
            while addr < VIC_BANK + 0x4000 and not is_empty_sprite(mem, addr):
                addr += SPRITE_SIZE
            regions.append((start, addr))
        else:
            addr += SPRITE_SIZE
    return regions


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print("Parsing listing...")
    mem, filled = parse_listing(LST_FILE)

    # Count filled bytes in key regions
    regions_info = [
        ("$4000-$43FF Screen RAM (primary)", 0x4000, 0x4400),
        ("$4400-$47FF Screen data / text ptrs", 0x4400, 0x4800),
        ("$4800-$49FF Charset 1 (console)", 0x4800, 0x4A00),
        ("$4A00-$4BF7 Screen padding", 0x4A00, 0x4BF8),
        ("$4BF8-$4BFF Sprite pointers", 0x4BF8, 0x4C00),
        ("$4C00-$4FFF Screen RAM (alt)", 0x4C00, 0x5000),
        ("$5000-$51FF Sprite state / data", 0x5000, 0x5200),
        ("$5200-$53FF Dynamic sprites", 0x5200, 0x5400),
        ("$5400-$67FF Sprite definitions", 0x5400, 0x6800),
        ("$6800-$6FFF Charset 2 (game) + code", 0x6800, 0x7000),
        ("$7000-$77FF Charset padding / data", 0x7000, 0x7800),
        ("$7800-$7FFF Charset 3 (tiles)", 0x7800, 0x8000),
    ]

    print("\nMemory map (VIC-II bank $4000-$7FFF):")
    print("-" * 60)
    for name, start, end in regions_info:
        n_filled = sum(1 for a in range(start, end) if filled[a])
        n_nonzero = sum(1 for a in range(start, end) if mem[a] != 0)
        print(f"  {name}: {n_filled}/{end-start} filled, {n_nonzero} non-zero")

    # Also check $3EF4 area (BuildDroidSprite data before VIC bank)
    n_3e = sum(1 for a in range(0x3EF4, 0x4000) if filled[a])
    print(f"  $3EF4-$3FFF Pre-VIC data: {n_3e}/{0x4000-0x3EF4} filled")

    # Print sprite pointer table
    print("\nSprite pointer table ($4BF8-$4BFF):")
    for i in range(8):
        ptr = mem[0x4BF8 + i]
        addr = VIC_BANK + ptr * SPRITE_SIZE
        print(f"  Sprite {i}: ptr=${ptr:02X} -> data at ${addr:04X}")

    # Find non-empty sprite regions
    print("\nNon-empty sprite regions (64-byte aligned):")
    sprite_regions = find_sprite_regions(mem, filled)
    for start, end in sprite_regions:
        n = (end - start) // SPRITE_SIZE
        print(f"  ${start:04X}-${end-1:04X}: {n} sprites")

    # Render sprite sheets
    print("\nRendering sprite sheets...")

    # All sprites in VIC bank
    sheet_all, addrs_all = render_sprite_sheet(
        mem, VIC_BANK, VIC_BANK + 0x4000,
        "All VIC bank sprites (hi-res)", scale=3)
    if sheet_all:
        sheet_all.save(OUT_DIR / 'sprites_hires.png')

    # Same as multicolor
    sheet_mc, _ = render_sprite_sheet(
        mem, VIC_BANK, VIC_BANK + 0x4000,
        "All VIC bank sprites (multicolor)", scale=3, multicolor=True)
    if sheet_mc:
        sheet_mc.save(OUT_DIR / 'sprites_multicolor.png')

    # Sprite data at $5400 region specifically
    sheet_5400, _ = render_sprite_sheet(
        mem, 0x5400, 0x6800,
        "Sprite defs $5400-$67FF (hi-res)", scale=4)
    if sheet_5400:
        sheet_5400.save(OUT_DIR / 'sprites_5400_hires.png')

    sheet_5400mc, _ = render_sprite_sheet(
        mem, 0x5400, 0x6800,
        "Sprite defs $5400-$67FF (multicolor)", scale=4, multicolor=True)
    if sheet_5400mc:
        sheet_5400mc.save(OUT_DIR / 'sprites_5400_multicolor.png')

    # $4C00 region sprites
    sheet_4c, _ = render_sprite_sheet(
        mem, 0x4C00, 0x5400,
        "Sprites $4C00-$53FF (hi-res)", scale=4)
    if sheet_4c:
        sheet_4c.save(OUT_DIR / 'sprites_4C00_hires.png')

    sheet_4cmc, _ = render_sprite_sheet(
        mem, 0x4C00, 0x5400,
        "Sprites $4C00-$53FF (multicolor)", scale=4, multicolor=True)
    if sheet_4cmc:
        sheet_4cmc.save(OUT_DIR / 'sprites_4C00_multicolor.png')

    # Render character sets
    print("\nRendering character sets...")
    # $4800: 512 bytes = 64 chars (or up to 256)
    cs1 = render_charset(mem, 0x4800, "Charset $4800 (console)", num_chars=64, scale=5)
    cs1.save(OUT_DIR / 'charset_4800.png')

    # $6800: used for game area; but this region also contains code/tables
    # Only render the first 128 chars to avoid code
    cs2 = render_charset(mem, 0x6800, "Charset $6800 (game area)", num_chars=128, scale=5)
    cs2.save(OUT_DIR / 'charset_6800.png')

    # $7000: padding area between IRQ code and $7800 charset
    cs2b = render_charset(mem, 0x7000, "Charset $7000 (alt)", num_chars=256, scale=4)
    cs2b.save(OUT_DIR / 'charset_7000.png')

    # $7800: main tile charset
    cs3 = render_charset(mem, 0x7800, "Charset $7800 (tiles)", num_chars=128, scale=5)
    cs3.save(OUT_DIR / 'charset_7800.png')

    # Also render $7A60 and $7BF0 regions as charsets
    cs4 = render_charset(mem, 0x7A80, "Charset $7A80 (extra)", num_chars=80, scale=5)
    cs4.save(OUT_DIR / 'charset_7A80.png')

    # Write memory map summary
    with open(OUT_DIR / 'memory_map.txt', 'w') as f:
        f.write("Paradroid CE — VIC-II Bank Graphics Memory Map\n")
        f.write("=" * 60 + "\n\n")
        for name, start, end in regions_info:
            n_filled = sum(1 for a in range(start, end) if filled[a])
            n_nonzero = sum(1 for a in range(start, end) if mem[a] != 0)
            f.write(f"{name}\n  {n_filled}/{end-start} bytes filled, {n_nonzero} non-zero\n\n")

        f.write("\nSprite pointer table ($4BF8-$4BFF):\n")
        for i in range(8):
            ptr = mem[0x4BF8 + i]
            addr = VIC_BANK + ptr * SPRITE_SIZE
            f.write(f"  Sprite {i}: ptr=${ptr:02X} -> ${addr:04X}\n")

        f.write("\nNon-empty sprite regions:\n")
        for start, end in sprite_regions:
            n = (end - start) // SPRITE_SIZE
            f.write(f"  ${start:04X}-${end-1:04X}: {n} sprites\n")

        f.write(f"\nTotal non-empty sprites: {sum((e-s)//64 for s,e in sprite_regions)}\n")

    # Save raw binary dump of key regions for further analysis
    with open(OUT_DIR / 'vic_bank_raw.bin', 'wb') as f:
        f.write(bytes(mem[VIC_BANK:VIC_BANK + 0x4000]))

    print(f"\nDone! Output in {OUT_DIR}")
    print("Files:")
    for p in sorted(OUT_DIR.iterdir()):
        print(f"  {p.name} ({p.stat().st_size:,} bytes)")


if __name__ == '__main__':
    main()
