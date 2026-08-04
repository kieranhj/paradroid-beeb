#!/usr/bin/env python3
"""
rip_screens.py — Extract and render the Paradroid CE title screen
and transfer minigame layout.

Title screen:
  Title_dat at $CC00 — raw 40×25 character screen (1000 bytes)
  Copied to screen RAM $4800, coloured via CharColor[$0800]
  Charset at $7800 (with ORA #$80 for upper chars)

Transfer minigame:
  SubGameTopLines_dat at $E613 — 3 rows × 40 chars (120 bytes)
  SubGameLine_dat at $E68B — 1 row × 40 chars (repeated 12×)
  SubGameBottomLine_dat at $E6B3 — 1 row × 40 chars
  Total: 1 blank + 3 top + 12 middle + 1 bottom = 17 rows

Output:
  tools/output/title_screen.png
  tools/output/transfer_game.png
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


def render_char(mem, char_code, charset_base, fg, bg):
    """Render an 8×8 character, return list of (fg_or_bg) per pixel.
    With a custom charset, screen code indexes directly into the full 256-char set.
    No reverse video — that only applies to the C64 character ROM."""
    addr = charset_base + (char_code & 0xFF) * 8
    pixels = []
    for row in range(8):
        byte = mem[addr + row]
        row_px = []
        for bit in range(8):
            on = bool(byte & (0x80 >> bit))
            row_px.append(fg if on else bg)
        pixels.append(row_px)
    return pixels


def render_screen(mem, screen_data, width, height, charset_base, bg_color,
                  color_source='charcolor', title='', scale=3):
    """Render a C64 character screen.

    screen_data: list of character codes (width × height)
    color_source: 'charcolor' uses CharColor[$0800] table,
                  or a fixed colour tuple
    """
    char_w = 8 * scale
    char_h = 8 * scale
    title_h = 20 if title else 0

    img_w = width * char_w
    img_h = height * char_h + title_h

    img = Image.new('RGB', (img_w, img_h), bg_color)
    draw = ImageDraw.Draw(img)

    if title:
        draw.text((4, 2), title, fill=(255, 255, 200))

    for row in range(height):
        for col in range(width):
            idx = row * width + col
            if idx >= len(screen_data):
                continue

            char_code = screen_data[idx]

            # Determine foreground colour
            if color_source == 'charcolor':
                color_byte = mem[0x0800 + char_code]
                color_idx = (color_byte >> 4) & 0x0F
                fg = C64_PAL[color_idx]
                # Fallback: if CharColor gives black, use light grey
                if fg == (0, 0, 0):
                    fg = C64_PAL[15]  # light grey
            elif isinstance(color_source, tuple):
                fg = color_source
            else:
                fg = (255, 255, 255)

            # Render character
            pixels = render_char(mem, char_code, charset_base, fg, bg_color)

            x0 = col * char_w
            y0 = row * char_h + title_h

            for py in range(8):
                for px in range(8):
                    color = pixels[py][px]
                    if color != bg_color:
                        sx = x0 + px * scale
                        sy = y0 + py * scale
                        draw.rectangle([sx, sy, sx + scale - 1, sy + scale - 1],
                                       fill=color)

    return img


def render_screen_custom_color(mem, screen_data, width, height, charset_base,
                                bg_color, color_fn, title='', scale=3):
    """Like render_screen but color_fn(char_code) returns the fg colour."""
    char_w = 8 * scale
    char_h = 8 * scale
    title_h = 20 if title else 0

    img_w = width * char_w
    img_h = height * char_h + title_h

    img = Image.new('RGB', (img_w, img_h), bg_color)
    draw = ImageDraw.Draw(img)

    if title:
        draw.text((4, 2), title, fill=(255, 255, 200))

    for row in range(height):
        for col in range(width):
            idx = row * width + col
            if idx >= len(screen_data):
                continue
            char_code = screen_data[idx]
            if char_code == 0:
                continue

            fg = color_fn(char_code)
            pixels = render_char(mem, char_code, charset_base, fg, bg_color)

            x0 = col * char_w
            y0 = row * char_h + title_h

            for py in range(8):
                for px in range(8):
                    color = pixels[py][px]
                    if color != bg_color:
                        sx = x0 + px * scale
                        sy = y0 + py * scale
                        draw.rectangle([sx, sy, sx + scale - 1, sy + scale - 1],
                                       fill=color)

    return img


# ---------------------------------------------------------------------------
# Title screen
# ---------------------------------------------------------------------------
def rip_title_screen(mem):
    """Extract and render the title screen from Title_dat at $CC00."""
    print("Title screen:")

    # Title_dat is a raw 40×25 screen at $CC00 (1000 bytes)
    screen_data = list(mem[0xCC00:0xCC00 + 1000])

    # ShowTitle copies this to $4800 (screen RAM), then uses
    # charset pointed to by $D018=$2F which = screen $4C00, chars $7800
    # But the actual title screen uses $4800 as screen base with
    # $D018 settings from the IRQ. The chars are from $7800.
    #
    # After copying, it fills $8000 area with $30 chars and copies
    # to $4C00. The title uses the $4800 screen with charset at $7800.

    # Count unique chars
    chars = set(screen_data)
    print(f"  Screen data: 1000 bytes at $CC00")
    print(f"  Unique characters: {len(chars)}")
    print(f"  Non-zero chars: {sum(1 for c in screen_data if c != 0)}")

    # The title screen charset is at $4800 (from D018=$21: screen $4000, chars $4800)
    # But $4800 in the listing is all zeros. The title copies the charset too?
    # Actually ShowTitle copies 4 pages ($400 bytes = 1KB) from $CC00 to $4800.
    # Wait, it copies 4*256=1024 bytes. But Title_dat is the screen (1000 bytes).
    #
    # Re-reading: LDX #4 means 4 pages = 1024 bytes.
    # Source $CC00, dest $4800. So it copies screen data to $4800.
    # Then $D018 is set for screen at $4800... but that's only 1KB.
    # The C64 screen RAM is 1000 bytes (40×25).
    #
    # The charset is at $7800 (from D018=$2F = screen $4C00, chars $7800)
    # But wait, the IRQ sets D018 differently for different screen areas.
    # For the title, screen at $4000 + $21*$400... let me recalculate.
    #
    # D018 bits: bits 4-7 = screen offset (× $400), bits 1-3 = char offset (× $800)
    # $21 = 0010_0001: screen = 2 × $400 = $4800 (within VIC bank $4000) = $4800
    #                   chars = 0 × $800 + $4000 + $800 = $4800
    # Wait no: $21 = %0010_0001
    #   screen = (bits 4-7) = 2 → offset = 2 * $400 = $800 → screen at $4000+$800 = $4800
    #   chars  = (bits 1-3) = 0 → offset = 0 * $800 = $0000 → chars at $4000+$0000 = $4000
    # Hmm, but $4000 is all zeros in the listing.
    #
    # Actually from the annotation: $D018 = $21 → screen at $4000, chars at $4800
    # And $D018 = $2F → screen at $4C00, chars at $7800
    #
    # The ShowTitle code sets up $D018 differently via the IRQ chain.
    # Let me look at what the IRQ actually sets.
    # From the code: byte_0_FFFE = $2922 (the IRQ handler address)
    # The title uses the charset that's already in the VIC bank.
    #
    # The title likely uses charset at $7800 (the main tile charset we already extracted).
    # Let's render with $7800 first.

    # Render with charset at $7800
    bg = (0x00, 0x00, 0x00)
    img = render_screen(mem, screen_data, 40, 25, 0x7800, bg,
                        color_source='charcolor',
                        title="Title Screen (Title_dat $CC00, charset $7800)",
                        scale=3)
    img.save(OUT_DIR / 'title_screen_7800.png')
    print(f"  Saved title_screen_7800.png ({img.width}x{img.height})")

    # Also try charset at $7000 (the text/font charset)
    img2 = render_screen(mem, screen_data, 40, 25, 0x7000, bg,
                         color_source='charcolor',
                         title="Title Screen (Title_dat $CC00, charset $7000)",
                         scale=3)
    img2.save(OUT_DIR / 'title_screen_7000.png')
    print(f"  Saved title_screen_7000.png ({img2.width}x{img2.height})")

    # And the $6800 charset
    img3 = render_screen(mem, screen_data, 40, 25, 0x6800, bg,
                         color_source='charcolor',
                         title="Title Screen (Title_dat $CC00, charset $6800)",
                         scale=3)
    img3.save(OUT_DIR / 'title_screen_6800.png')
    print(f"  Saved title_screen_6800.png ({img3.width}x{img3.height})")


# ---------------------------------------------------------------------------
# Transfer minigame
# ---------------------------------------------------------------------------
def rip_transfer_game(mem):
    """Extract and render the transfer minigame board layout."""
    print("\nTransfer minigame:")

    # SubGameSelectSide builds the screen at $4940:
    # Row 0: blank (40 zeros)
    # Rows 1-3: SubGameTopLines_dat ($E613, 120 bytes = 3 × 40)
    # Rows 4-15: SubGameLine_dat ($E68B, 40 bytes) repeated 12×
    # Row 16: SubGameBottomLine_dat ($E6B3, 40 bytes)
    # Total: 17 rows × 40 chars

    screen = []

    # Row 0: blank
    screen.extend([0] * 40)

    # Rows 1-3: top lines
    for i in range(120):
        screen.append(mem[0xE613 + i])

    # Rows 4-15: middle line repeated 12×
    for rep in range(12):
        for i in range(40):
            screen.append(mem[0xE68B + i])

    # Row 16: bottom line
    for i in range(40):
        screen.append(mem[0xE6B3 + i])

    width = 40
    height = 17

    chars = set(screen)
    non_zero = sum(1 for c in screen if c != 0)
    print(f"  Board size: {width}×{height} chars")
    print(f"  Unique characters: {sorted(c for c in chars if c != 0)}")
    print(f"  Non-zero chars: {non_zero}")

    # The transfer game uses charset at $7800 (D018=$2F)
    # Characters used are mostly in the $F0-$FF range (circuit pieces)
    # and $D0-$D1 (connectors)
    #
    # IMPORTANT: CharColor[$D0+] is all $00 — the transfer game sets
    # colour RAM dynamically via FillCRAM with $F8 (colour $0F = light grey).
    # The player side uses xfer_PlyColor=$FF (white) and CPU side uses
    # xfer_CpuColor=$FC (light grey). We'll use a fixed colour scheme.

    bg = (0x00, 0x00, 0x10)

    # Render with per-character colours matching the game:
    # Left side (player): cyan, Right side (CPU): light grey, borders: yellow
    # We'll use 'transfer' as the colour source mode
    img = render_screen(mem, screen, width, height, 0x7800, bg,
                        color_source=(0x67, 0xB6, 0xBD),
                        title="Transfer Minigame Board ($E613/$E68B/$E6B3, charset $7800)",
                        scale=4)
    img.save(OUT_DIR / 'transfer_game.png')
    print(f"  Saved transfer_game.png ({img.width}x{img.height})")

    # Also render with two-tone player/CPU colour split
    # Player chars: $F1, $FD, $FB (left side) → white
    # CPU chars: $F2, $F3, $FC (right side) → light grey
    # Border chars: $F5, $F6, $F7, $FE, $D0, $D1 → yellow
    # Centre chars: $F8, $F9, $FA → cyan
    player_chars = {0xF1, 0xFD, 0xFB}
    cpu_chars = {0xF2, 0xF3, 0xFC}
    centre_chars = {0xF8, 0xF9, 0xFA, 0xD0, 0xD1}

    def xfer_color(cc):
        if cc in player_chars:
            return (0xFF, 0xFF, 0xFF)  # white
        elif cc in cpu_chars:
            return (0x9F, 0x9F, 0x9F)  # light grey
        elif cc in centre_chars:
            return (0x67, 0xB6, 0xBD)  # cyan
        else:
            return (0xBF, 0xCE, 0x72)  # yellow

    img2 = render_screen_custom_color(mem, screen, width, height, 0x7800, bg,
                                       xfer_color,
                                       title="Transfer Minigame (player=white, CPU=grey)",
                                       scale=4)
    img2.save(OUT_DIR / 'transfer_game_color.png')
    print(f"  Saved transfer_game_color.png ({img2.width}x{img2.height})")

    # Render just the unique circuit piece characters
    circuit_chars = sorted(c for c in chars if c != 0)
    render_circuit_chars(mem, circuit_chars)


def render_circuit_chars(mem, char_codes, charset_base=0x7800, scale=6):
    """Render the individual circuit piece characters used in the transfer game."""
    cols = min(len(char_codes), 16)
    rows = (len(char_codes) + cols - 1) // cols

    cell_w = 8 * scale + 4
    cell_h = 8 * scale + 16
    img_w = cols * cell_w + 4
    img_h = rows * cell_h + 20

    bg = (16, 16, 32)
    img = Image.new('RGB', (img_w, img_h), bg)
    draw = ImageDraw.Draw(img)
    draw.text((4, 2), f"Transfer game characters ({len(char_codes)} unique)",
              fill=(255, 255, 100))

    for idx, cc in enumerate(char_codes):
        col = idx % cols
        row = idx // cols
        x0 = col * cell_w + 4
        y0 = row * cell_h + 20

        # Use cyan for visibility (CharColor is $00 for these chars)
        fg = (0x67, 0xB6, 0xBD)

        # Draw cell background
        draw.rectangle([x0, y0, x0 + 8*scale - 1, y0 + 8*scale - 1],
                       fill=(0, 0, 0))

        # Render char
        pixels = render_char(mem, cc, charset_base, fg, (0, 0, 0))
        for py in range(8):
            for px in range(8):
                if pixels[py][px] != (0, 0, 0):
                    sx = x0 + px * scale
                    sy = y0 + py * scale
                    draw.rectangle([sx, sy, sx + scale - 1, sy + scale - 1],
                                   fill=pixels[py][px])

        # Label
        draw.text((x0, y0 + 8 * scale + 1), f"${cc:02X}", fill=(180, 180, 180))

    img.save(OUT_DIR / 'transfer_chars.png')
    print(f"  Saved transfer_chars.png ({img.width}x{img.height})")


# ---------------------------------------------------------------------------
def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print("Parsing listing...")
    mem, filled = parse_listing(LST_FILE)

    rip_title_screen(mem)
    rip_transfer_game(mem)

    print(f"\nDone! Output in {OUT_DIR}")


if __name__ == '__main__':
    main()
