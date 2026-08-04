#!/usr/bin/env python3
"""
rip_sideview.py — Decode and render the Paradroid CE ship cross-section
(side view) that shows all decks stacked vertically.

Data:
  SideView_dat at $F180 — RLE-encoded character codes
  DrawPacked decodes into a 64-column × 16-row grid
  Characters from charset at $7800, displayed with bit 7 set (ORA #$80)
  CharColor at $0800 — per-character colour nybble

The routine also overlays lift_HighlightDeck rectangles using:
  lift_DeckY ($F120), lift_DeckX ($F130),
  lift_DeckHeight ($F140), lift_DeckWidth ($F150)

Output:
  tools/output/side_view.png       — rendered ship cross-section
  tools/output/side_view_chars.png — character grid with indices
"""

import re
import os
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("ERROR: Pillow required. pip install Pillow")
    sys.exit(1)

PROJECT = Path(r'C:\Users\khcon\OneDrive\Projects\Paradroid')
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_DIR = PROJECT / 'tools' / 'output'

# C64 colour palette (VIC-II)
C64_PAL = [
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
def parse_listing(path):
    mem = bytearray(65536)
    filled = bytearray(65536)
    current_base = None
    running_offset = 0

    with open(path, 'r', encoding='latin-1') as f:
        for line in f:
            m = re.match(r'^([0-9A-Fa-f]{4})\s', line)
            if not m:
                continue
            addr = int(m.group(1), 16)
            byte_match = re.search(r'\.BYTE\s+(.*)', line)
            if not byte_match:
                if re.search(r'\b(LDA|STA|LDX|STX|LDY|STY|JSR|JMP|RTS|RTI|BEQ|BNE|BPL|BMI|BCS|BCC|BVS|BVC|CLC|SEC|CLI|SEI|NOP|PHA|PLA|TAX|TAY|TXA|TYA|TSX|TXS|INX|INY|DEX|DEY|INC|DEC|ADC|SBC|AND|ORA|EOR|CMP|CPX|CPY|ASL|LSR|ROL|ROR|BIT|PHP|PLP|BRK|SED|CLD|CLV)\b', line):
                    current_base = None
                continue

            val_str = re.sub(r';.*', '', byte_match.group(1))
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
                    break

            if not values:
                continue

            if current_base is None or addr != current_base:
                current_base = addr
                running_offset = 0

            actual_addr = current_base + running_offset
            for i, b in enumerate(values):
                a = (actual_addr + i) & 0xFFFF
                mem[a] = b & 0xFF
                filled[a] = 1
            running_offset += len(values)

    return mem, filled


# ---------------------------------------------------------------------------
def decode_sideview_rle(mem):
    """Decode SideView_dat at $F180 using DrawPacked's RLE format.
    Returns a 64×16 grid of character codes (after masking)."""

    src = 0xF180
    grid = [[0] * 64 for _ in range(16)]
    col = 0  # ptr_14 low (0-63)
    row = 0  # ptr_14 high (0-15)

    safety = 0
    while safety < 10000 and row < 16:
        safety += 1
        byte = mem[src]

        if byte & 0x80:
            # RLE: char code in bits 0-6, next byte is count
            char_code = byte & 0x7F
            repeat = mem[src + 1]
            src += 2
        else:
            # Single character
            char_code = byte & 0x7F
            repeat = 1
            src += 1

        # Special: char $29 becomes $00 (space)
        if char_code == 0x29:
            char_code = 0

        for _ in range(repeat):
            if row >= 16:
                break
            grid[row][col] = char_code
            col += 1
            if col >= 64:
                col = 0
                row += 1

    return grid


def render_char_pixels(mem, char_code, charset_base=0x7800):
    """Get 8×8 pixel grid for a character from the charset.
    With a custom charset, screen code indexes directly into all 256 chars."""
    addr = charset_base + (char_code & 0xFF) * 8
    pixels = []
    for row in range(8):
        byte = mem[addr + row]
        row_px = []
        for bit in range(8):
            on = bool(byte & (0x80 >> bit))
            row_px.append(on)
        pixels.append(row_px)
    return pixels


def render_sideview(mem, grid, scale=4):
    """Render the side view with character graphics and colours."""
    # Visible area: columns 3-41 (39 chars), all 16 rows
    # But let's render the full 64×16 for context, highlighting the visible area
    vis_left = 3
    vis_right = 42  # exclusive
    vis_cols = vis_right - vis_left
    num_rows = 16

    char_w = 8 * scale
    char_h = 8 * scale

    # The DrawPacked code applies ORA #$80 to all characters, making them display
    # as reverse video from the $7800 charset
    # Background colours: $FE (light blue) for bg, $F1/$F0 for multicolor

    # Get per-character colour from CharColor table at $0800
    # The high nybble of CharColor byte is the colour index
    # DrawSideview sets Irq1bgColor=$FE, but the actual display uses black bg
    # with the ship drawn in colour. The multicolor bg regs ($D022/$D023) are
    # used for the charset multicolor mode, not the screen background.
    bg_color = (0x00, 0x00, 0x00)  # black background

    img_w = vis_cols * char_w + 40  # left margin for deck labels
    img_h = num_rows * char_h + 30  # top margin for title

    img = Image.new('RGB', (img_w, img_h), (0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.text((4, 4), "Paradroid CE — Ship Side View (SideView_dat $F180)",
              fill=(255, 255, 200))

    margin_x = 32
    margin_y = 24

    # Draw background
    draw.rectangle([margin_x, margin_y,
                     margin_x + vis_cols * char_w,
                     margin_y + num_rows * char_h],
                    fill=bg_color)

    # Draw each character
    for row in range(num_rows):
        for col_i in range(vis_cols):
            col = vis_left + col_i
            char_code = grid[row][col]

            if char_code == 0:
                continue  # transparent / space

            # Apply ORA #$80 (reverse video) as the actual code does
            display_char = char_code | 0x80

            # Get colour from CharColor table
            color_byte = mem[0x0800 + (char_code | 0x80)]
            color_idx = (color_byte >> 4) & 0x0F
            fg_color = C64_PAL[color_idx]

            # Render character pixels
            pixels = render_char_pixels(mem, display_char)

            x0 = margin_x + col_i * char_w
            y0 = margin_y + row * char_h

            for py in range(8):
                for px in range(8):
                    if pixels[py][px]:
                        sx = x0 + px * scale
                        sy = y0 + py * scale
                        draw.rectangle([sx, sy, sx + scale - 1, sy + scale - 1],
                                       fill=fg_color)

    # Draw deck labels on the left
    for row in range(num_rows):
        y = margin_y + row * char_h + char_h // 3
        draw.text((2, y), f"{row:2d}", fill=(200, 200, 200))

    # Overlay lift/deck rectangles from metadata
    # lift_DeckY at $F120 (16 entries): row position of each deck entry
    # lift_DeckX at $F130 (16 entries): column position
    # lift_DeckHeight at $F140 (16 entries): height in rows
    # lift_DeckWidth at $F150 (16 entries): width in columns
    deck_colors = [
        (255, 100, 100),  # red
        (100, 255, 100),  # green
        (100, 100, 255),  # blue
        (255, 255, 100),  # yellow
        (255, 100, 255),  # magenta
        (100, 255, 255),  # cyan
        (255, 180, 100),  # orange
        (180, 100, 255),  # purple
        (255, 100, 100),
        (100, 255, 100),
        (100, 100, 255),
        (255, 255, 100),
        (255, 100, 255),
        (100, 255, 255),
        (255, 180, 100),
        (180, 100, 255),
    ]

    for i in range(16):
        dy = mem[0xF120 + i]
        dx = mem[0xF130 + i]
        dh = mem[0xF140 + i]
        dw = mem[0xF150 + i]

        if dw == 0 or dh == 0:
            continue

        # Convert to pixel coordinates relative to visible area
        px_x = margin_x + (dx - vis_left) * char_w
        px_y = margin_y + dy * char_h
        px_w = dw * char_w
        px_h = dh * char_h

        color = deck_colors[i % len(deck_colors)]

        # Draw outline rectangle
        draw.rectangle([px_x - 1, px_y - 1, px_x + px_w, px_y + px_h],
                       outline=color, width=2)

        # Label
        draw.text((px_x + 2, px_y + 2), f"Deck {i}", fill=color)

    return img


def render_sideview_plain(mem, grid, scale=3):
    """Simpler rendering: just show character codes as coloured blocks
    with the charset graphics, no clipping."""
    num_cols = 64
    num_rows = 16
    char_w = 8 * scale
    char_h = 8 * scale

    bg_color = (0x00, 0x00, 0x00)

    img_w = num_cols * char_w
    img_h = num_rows * char_h + 20

    img = Image.new('RGB', (img_w, img_h), (0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.text((4, 2), "Full 64x16 side view grid (unclipped)", fill=(255, 255, 100))

    for row in range(num_rows):
        for col in range(num_cols):
            char_code = grid[row][col]
            x0 = col * char_w
            y0 = row * char_h + 20

            if char_code == 0:
                draw.rectangle([x0, y0, x0 + char_w - 1, y0 + char_h - 1],
                               fill=bg_color)
                continue

            display_char = char_code | 0x80
            color_byte = mem[0x0800 + display_char]
            color_idx = (color_byte >> 4) & 0x0F
            fg_color = C64_PAL[color_idx]

            pixels = render_char_pixels(mem, display_char)

            # Draw background
            draw.rectangle([x0, y0, x0 + char_w - 1, y0 + char_h - 1],
                           fill=bg_color)

            for py in range(8):
                for px in range(8):
                    if pixels[py][px]:
                        sx = x0 + px * scale
                        sy = y0 + py * scale
                        draw.rectangle([sx, sy, sx + scale - 1, sy + scale - 1],
                                       fill=fg_color)

    return img


# ---------------------------------------------------------------------------
def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print("Parsing listing...")
    mem, filled = parse_listing(LST_FILE)

    print("Decoding side view RLE...")
    grid = decode_sideview_rle(mem)

    # Debug: show unique chars used
    chars_used = set()
    for row in grid:
        for c in row:
            if c != 0:
                chars_used.add(c)
    print(f"  Unique character codes: {sorted(chars_used)}")
    print(f"  Grid filled: {sum(1 for r in grid for c in r if c != 0)} / {64*16} cells")

    # Print deck metadata
    print("\nDeck layout metadata:")
    for i in range(16):
        dy = mem[0xF120 + i]
        dx = mem[0xF130 + i]
        dh = mem[0xF140 + i]
        dw = mem[0xF150 + i]
        if dw > 0 and dh > 0:
            print(f"  Deck {i:2d}: pos=({dx:2d},{dy:2d}) size={dw}x{dh}")

    print("\nRendering side view...")
    img = render_sideview(mem, grid, scale=4)
    img.save(OUT_DIR / 'side_view.png')
    print(f"  Saved side_view.png ({img.width}x{img.height})")

    img2 = render_sideview_plain(mem, grid, scale=3)
    img2.save(OUT_DIR / 'side_view_full.png')
    print(f"  Saved side_view_full.png ({img2.width}x{img2.height})")

    # Also render with deck outline only (no charset, just blocks)
    print(f"\nDone! Output in {OUT_DIR}")


if __name__ == '__main__':
    main()
