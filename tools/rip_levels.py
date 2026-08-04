#!/usr/bin/env python3
"""
rip_levels.py — Decode and visualise all 16 Paradroid CE level maps.

Data chain:
  Level RLE data ($F249+) → tile index (0-31)
  Tile definitions ($E800) → 4×4 grid of character codes (16 bytes/tile)
  Charset ($7800)          → 8×8 pixel patterns per character

Output:
  tools/output/deck_NN.png         — individual deck images
  tools/output/all_decks.png       — all decks in a single sheet
  tools/output/tiles.png           — the 32 tile definitions rendered
  tools/output/side_view.png       — the ship cross-section view
  tools/output/level_stats.txt     — per-deck stats

Requires: Pillow
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

# ---------------------------------------------------------------------------
PROJECT = Path(r'C:\Users\khcon\OneDrive\Projects\Paradroid')
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_DIR = PROJECT / 'tools' / 'output'

# C64 colour palette
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

# Per-deck colour schemes (from deckColorScheme at $F160)
# Index into a palette mapping: 0=blue/grey, 1=green, 2=red, 3=cyan, 4=purple, 5=orange, 6=yellow
DECK_COLOR_IDX = [0, 4, 1, 2, 3, 6, 2, 1, 4, 0, 4, 3, 2, 5, 5, 4]

# Approximate deck colours (background, wall, floor, accent)
DECK_COLORS = [
    # (bg,       wall,     floor,    door)
    ((0x20,0x20,0x40), (0x50,0x50,0x90), (0x30,0x30,0x60), (0x80,0x80,0xFF)),  # 0 blue
    ((0x20,0x10,0x30), (0x70,0x40,0x80), (0x40,0x20,0x50), (0xC0,0x60,0xFF)),  # 1 green->purple
    ((0x10,0x25,0x10), (0x40,0x80,0x40), (0x20,0x50,0x20), (0x60,0xFF,0x60)),  # 2 green
    ((0x25,0x10,0x10), (0x80,0x40,0x40), (0x50,0x20,0x20), (0xFF,0x60,0x60)),  # 3 red
    ((0x10,0x25,0x25), (0x40,0x80,0x80), (0x20,0x50,0x50), (0x60,0xFF,0xFF)),  # 4 cyan
    ((0x25,0x25,0x10), (0x80,0x80,0x40), (0x50,0x50,0x20), (0xFF,0xFF,0x60)),  # 5 yellow
    ((0x25,0x15,0x00), (0x80,0x55,0x20), (0x50,0x35,0x10), (0xFF,0xA0,0x40)),  # 6 orange
]

# Map dimensions: each tile is 4×4 characters, each char is 8×8 pixels
# The map buffer at $8000 has rows of 256 bytes, 4 pages per tile row (1024 bytes)
# Max: 64 tile columns × 16 tile rows
MAP_MAX_COLS = 64
MAP_MAX_ROWS = 16

# ---------------------------------------------------------------------------
# Parse listing (reuse from rip_graphics.py)
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
                # Only reset base on actual instruction lines (have opcode mnemonics),
                # not on comment/cross-reference lines that IDA inserts within data blocks
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
# Decode RLE level data
# ---------------------------------------------------------------------------
def decode_deck_rle(mem, deck_num):
    """Decode RLE level data for one deck. Returns list of tile indices."""
    lo = mem[0xF100 + deck_num]
    hi = mem[0xF110 + deck_num]
    src = (hi << 8) | lo

    tiles = []
    safety = 0
    while safety < 5000:
        safety += 1
        byte = mem[src]

        if byte & 0x80:
            # RLE: tile index in bits 0-4, next byte is repeat count
            tile_idx = byte & 0x1F
            repeat = mem[src + 1]
            src += 2
            tiles.extend([tile_idx] * repeat)
        else:
            # Single tile
            tile_idx = byte & 0x1F
            src += 1
            tiles.append(tile_idx)

        # Safety: stop if we've filled the entire map buffer
        if len(tiles) >= MAP_MAX_COLS * MAP_MAX_ROWS:
            break

    return tiles


def tiles_to_grid(tiles):
    """Convert flat tile list to 2D grid, detecting actual width/height."""
    # The BuildLevel code writes tiles left-to-right, then wraps to next row
    # when the dest pointer crosses a 1024-byte boundary (4 pages).
    # Each tile is 4 bytes wide, so max 64 tiles per row.
    # But actual deck widths vary. We need to figure out the deck width.
    #
    # From the pointer table analysis, decks use different widths.
    # The RLE data includes "empty" (tile 0) tiles for padding.
    # Let's try to detect width by looking at the first $80 xx encoding:
    # $80 means tile 0 with large repeat, often used for row padding.
    #
    # Alternative: the deckWidth data at $F150 gives width per deck!
    # But that might be the "highlight" width for the side view, not the map.
    #
    # Let's use a fixed approach: try various widths and see which produces
    # a non-ragged grid. Looking at actual Paradroid maps, they're around
    # 10-20 tiles wide.
    #
    # Actually, from the map buffer: 256 bytes per row / 4 bytes per tile = 64 tiles max.
    # But the RLE encoding itself doesn't encode row breaks - it just fills sequentially.
    # The tile placement wraps based on the dest pointer in the $8000 buffer.
    # With 256 bytes (64 tiles) per row, the actual visible width is determined by
    # which tiles are non-empty.
    #
    # For visualisation, let's decode into a 64-wide grid and then trim.

    rows = []
    ROW_WIDTH = 64
    for i in range(0, len(tiles), ROW_WIDTH):
        row = tiles[i:i + ROW_WIDTH]
        rows.append(row)

    # Trim: find the actual used width (rightmost non-zero tile in any row)
    max_col = 0
    for row in rows:
        for c in range(len(row) - 1, -1, -1):
            if row[c] != 0:
                max_col = max(max_col, c + 1)
                break

    # Trim empty rows from bottom
    while rows and all(t == 0 for t in rows[-1]):
        rows.pop()

    # Trim columns
    trimmed = [row[:max_col] for row in rows]

    return trimmed


# ---------------------------------------------------------------------------
# Render tiles and maps
# ---------------------------------------------------------------------------
def get_tile_def(mem, tile_idx):
    """Get the 4×4 character codes for a tile from $E800."""
    # Tile address = $E800 + tile_idx * 16
    # (the LSR/ROR chain in BuildLevel computes: index*16 + $E800)
    base = 0xE800 + tile_idx * 16
    chars = []
    for row in range(4):
        row_chars = []
        for col in range(4):
            row_chars.append(mem[base + row * 4 + col])
        chars.append(row_chars)
    return chars


def render_char(mem, char_code, charset_base=0x7800):
    """Render a single 8×8 character as an 8×8 pixel array."""
    pixels = []
    addr = charset_base + char_code * 8
    for row in range(8):
        byte = mem[addr]
        row_pixels = []
        for bit in range(8):
            row_pixels.append(1 if (byte & (0x80 >> bit)) else 0)
        pixels.append(row_pixels)
        addr += 1
    return pixels


def render_tile_image(mem, tile_idx, fg_color, bg_color, scale=1):
    """Render a 32×32 pixel tile (4×4 chars × 8×8 px)."""
    tile_def = get_tile_def(mem, tile_idx)
    img = Image.new('RGB', (32 * scale, 32 * scale), bg_color)

    for tr in range(4):
        for tc in range(4):
            char_code = tile_def[tr][tc]
            char_pixels = render_char(mem, char_code)
            for py in range(8):
                for px in range(8):
                    if char_pixels[py][px]:
                        x = (tc * 8 + px) * scale
                        y = (tr * 8 + py) * scale
                        for sy in range(scale):
                            for sx in range(scale):
                                img.putpixel((x + sx, y + sy), fg_color)
    return img


def classify_tile(mem, tile_idx):
    """Classify a tile type based on its character content."""
    if tile_idx == 0:
        return 'empty'

    tile_def = get_tile_def(mem, tile_idx)
    chars = [tile_def[r][c] for r in range(4) for c in range(4)]

    # Count non-zero characters
    non_zero = sum(1 for c in chars if c != 0)

    # Check for specific character patterns
    has_space = 0x20 in chars  # space char
    has_door_chars = any(c in (0x47, 0x42, 0x3D, 0x3F, 0x41) for c in chars)

    if non_zero == 0:
        return 'empty'
    elif non_zero <= 4:
        return 'sparse'
    elif has_door_chars and has_space:
        return 'door'
    else:
        return 'wall' if non_zero > 12 else 'floor'


def render_deck_image(mem, deck_num, grid, scale=2):
    """Render a full deck map as an image."""
    if not grid or not grid[0]:
        return None

    rows = len(grid)
    cols = max(len(r) for r in grid)

    tile_px = 32 * scale  # pixels per tile
    img_w = cols * tile_px
    img_h = rows * tile_px + 24  # title bar

    # Get deck colour scheme
    color_idx = DECK_COLOR_IDX[deck_num] if deck_num < len(DECK_COLOR_IDX) else 0
    color_idx = min(color_idx, len(DECK_COLORS) - 1)
    bg, wall_col, floor_col, door_col = DECK_COLORS[color_idx]

    img = Image.new('RGB', (img_w, img_h), bg)
    draw = ImageDraw.Draw(img)

    # Title
    draw.text((4, 4), f"Deck {deck_num} ({rows}x{cols} tiles, "
              f"{sum(1 for r in grid for t in r if t != 0)} non-empty)",
              fill=(255, 255, 200))

    for row_i, row in enumerate(grid):
        for col_i, tile_idx in enumerate(row):
            if tile_idx == 0:
                continue

            x0 = col_i * tile_px
            y0 = row_i * tile_px + 24

            # Choose colour based on tile type
            ttype = classify_tile(mem, tile_idx)
            if ttype == 'door':
                fg = door_col
            elif ttype == 'wall':
                fg = wall_col
            elif ttype == 'floor':
                fg = floor_col
            else:
                fg = (0x90, 0x90, 0x90)

            # Render the tile
            tile_img = render_tile_image(mem, tile_idx, fg, bg, scale)
            img.paste(tile_img, (x0, y0))

    return img


def render_tile_sheet(mem, scale=3):
    """Render all 32 tile definitions in a grid."""
    cols = 8
    rows = 4
    tile_px = 32 * scale
    pad = 2
    cell = tile_px + pad

    img_w = cols * cell + pad
    img_h = rows * cell + 20 + pad

    img = Image.new('RGB', (img_w, img_h), (32, 32, 32))
    draw = ImageDraw.Draw(img)
    draw.text((4, 2), "Tile definitions ($E800): 32 tiles, 4x4 chars each",
              fill=(255, 255, 100))

    for idx in range(32):
        col = idx % cols
        row = idx // cols
        x0 = col * cell + pad
        y0 = row * cell + 20

        fg = (200, 200, 255)
        bg = (0, 0, 40)

        tile_img = render_tile_image(mem, idx, fg, bg, scale)
        img.paste(tile_img, (x0, y0))

        # Label
        ttype = classify_tile(mem, idx)
        draw.text((x0, y0 + tile_px - 2), f"#{idx:02d}", fill=(150, 150, 150))

    return img


def render_side_view(mem, scale=2):
    """Decode and render the SideView data ($F180) — ship cross-section.
    This uses its own RLE-like format with tile references and special codes."""
    # The side view data is more complex — let's just render it from the
    # decoded deck grids as a simplified cross-section showing deck layouts
    # side by side
    pass


# ---------------------------------------------------------------------------
def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print("Parsing listing...")
    mem, filled = parse_listing(LST_FILE)

    # Render tile sheet
    print("Rendering tile sheet...")
    tile_sheet = render_tile_sheet(mem, scale=3)
    tile_sheet.save(OUT_DIR / 'tiles.png')
    print(f"  Saved tiles.png")

    # Decode and render all decks
    all_deck_images = []
    stats = []

    for deck in range(16):
        lo = mem[0xF100 + deck]
        hi = mem[0xF110 + deck]
        data_addr = (hi << 8) | lo

        print(f"\nDeck {deck:2d}: data at ${data_addr:04X}")

        tiles = decode_deck_rle(mem, deck)
        print(f"  RLE decoded: {len(tiles)} tiles")

        grid = tiles_to_grid(tiles)
        rows = len(grid)
        cols = max(len(r) for r in grid) if grid else 0
        non_empty = sum(1 for r in grid for t in r if t != 0)
        print(f"  Grid: {rows} rows x {cols} cols, {non_empty} non-empty tiles")

        # Count unique tile types used
        used_tiles = set()
        for r in grid:
            for t in r:
                if t != 0:
                    used_tiles.add(t)
        print(f"  Unique tiles used: {sorted(used_tiles)}")

        stats.append({
            'deck': deck,
            'addr': data_addr,
            'rle_tiles': len(tiles),
            'rows': rows,
            'cols': cols,
            'non_empty': non_empty,
            'unique_tiles': sorted(used_tiles),
        })

        img = render_deck_image(mem, deck, grid, scale=2)
        if img:
            img.save(OUT_DIR / f'deck_{deck:02d}.png')
            all_deck_images.append((deck, img))
            print(f"  Saved deck_{deck:02d}.png ({img.width}x{img.height})")

    # Composite: all decks in a vertical strip
    if all_deck_images:
        max_w = max(img.width for _, img in all_deck_images)
        total_h = sum(img.height + 8 for _, img in all_deck_images)

        composite = Image.new('RGB', (max_w, total_h), (16, 16, 16))
        y_off = 0
        for deck, img in all_deck_images:
            composite.paste(img, (0, y_off))
            y_off += img.height + 8

        composite.save(OUT_DIR / 'all_decks.png')
        print(f"\nSaved all_decks.png ({composite.width}x{composite.height})")

    # Write stats
    with open(OUT_DIR / 'level_stats.txt', 'w') as f:
        f.write("Paradroid CE — Level Data Analysis\n")
        f.write("=" * 60 + "\n\n")
        f.write("Level pointer table: $F100 (lo), $F110 (hi)\n")
        f.write("Tile definitions:    $E800 (32 tiles × 16 bytes = 512 bytes)\n")
        f.write("Charset:             $7800 (128 chars × 8 bytes = 1024 bytes)\n\n")

        for s in stats:
            f.write(f"Deck {s['deck']:2d}: ${s['addr']:04X}  "
                    f"{s['rows']:2d}×{s['cols']:2d} tiles  "
                    f"{s['non_empty']:3d} non-empty  "
                    f"unique: {s['unique_tiles']}\n")

        f.write(f"\nTotal decks: {len(stats)}\n")

        # Tile usage across all decks
        f.write("\nTile usage frequency:\n")
        tile_count = {}
        for s in stats:
            for t in s['unique_tiles']:
                tile_count[t] = tile_count.get(t, 0) + 1
        for t in sorted(tile_count.keys()):
            f.write(f"  Tile #{t:2d}: used in {tile_count[t]:2d} decks\n")

    print(f"\nDone! Output in {OUT_DIR}")


if __name__ == '__main__':
    main()
