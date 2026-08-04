# Paradroid CE — Graphics Extraction Reference

This document details the C64 graphics data extracted from the Paradroid CE
disassembly listing (`paradroid_ce.lst`) and the tools created to rip and
visualise them. It is intended as a reference for converting the graphics
to BBC Master MODE 2 format.

---

## 1. Extraction Tools

All tools are in `tools/` and require Python 3 + Pillow. Each parses the IDA
listing file directly to reconstruct a 64K memory image, then extracts and
renders specific data regions. Output goes to `tools/output/`.

### tools/rip_graphics.py

Extracts sprites and character sets from the VIC-II bank ($4000-$7FFF).

| Output file | Contents |
|---|---|
| `sprites_hires.png` | All 192 non-empty sprites rendered as hi-res (24x21, 1bpp) |
| `sprites_multicolor.png` | Same sprites rendered as multicolor (12x21 logical pixels) |
| `sprites_5400_hires.png` | Main sprite definitions $5400-$67FF (80 sprites, hi-res) |
| `sprites_5400_multicolor.png` | Same as multicolor |
| `sprites_4C00_hires.png` | Effect sprites $4C00-$53FF (20 sprites) |
| `sprites_4C00_multicolor.png` | Same as multicolor |
| `charset_4800.png` | Charset at $4800 (console area — empty in listing, loaded at runtime) |
| `charset_6800.png` | Charset at $6800 (game area, 128 chars) |
| `charset_7000.png` | Charset at $7000 (text font + "paradroid" title lettering, 256 chars) |
| `charset_7800.png` | Charset at $7800 (main game tiles + circuit pieces, 128 chars) |
| `charset_7A80.png` | Charset at $7A80 (upper chars of $7800 set, 80 chars) |
| `vic_bank_raw.bin` | Raw 16KB binary dump of the VIC-II bank |
| `memory_map.txt` | Byte-level fill/non-zero counts per region |

### tools/rip_levels.py

Decodes all 16 RLE-compressed deck maps and renders them using the tile
definitions and character set.

| Output file | Contents |
|---|---|
| `deck_00.png` .. `deck_15.png` | Individual deck map images (per-deck colour scheme) |
| `all_decks.png` | All 16 decks in a single vertical strip |
| `tiles.png` | The 32 tile definitions rendered from $E800 |
| `level_stats.txt` | Per-deck dimensions, tile counts, unique tile usage |

### tools/rip_sideview.py

Decodes and renders the ship cross-section (side-on view showing all decks
stacked vertically with lift shafts).

| Output file | Contents |
|---|---|
| `side_view.png` | Ship cross-section with deck overlay rectangles |
| `side_view_full.png` | Full 64x16 grid without clipping or overlays |

### tools/rip_screens.py

Extracts the title screen and transfer minigame board layout.

| Output file | Contents |
|---|---|
| `title_screen_7800.png` | Title screen rendered with $7800 charset (correct for tiles/text) |
| `title_screen_7000.png` | Title screen rendered with $7000 charset (alternate font) |
| `title_screen_6800.png` | Title screen rendered with $6800 charset (alternate) |
| `transfer_game.png` | Transfer minigame board (solid cyan) |
| `transfer_game_color.png` | Transfer minigame board (player=white, CPU=grey, borders=yellow) |
| `transfer_chars.png` | The 15 unique circuit-piece characters used in the transfer game |

---

## 2. Character Sets (Tilesets)

The C64 version uses three custom character sets within VIC-II bank 1
($4000-$7FFF). Each character is 8x8 pixels, 1 bit per pixel (8 bytes).
The $D018 register switches between them at different scanlines via the
raster IRQ chain.

### Charset at $7800 (main game tiles) — 256 characters, 2048 bytes

This is the primary charset, used for:
- **Level map tiles** (chars $00-$7F): walls, floors, doors, lifts, consoles,
  decorative elements. These are the building blocks referenced by the 32
  tile definitions at $E800.
- **Transfer game circuit pieces** (chars $D0-$FE): wire tracks, pulsers,
  connectors, diagonal routing, frame borders. 15 unique characters.
- **Title screen** reuses the level tile chars to form large block letters
  spelling "PARADROID".

Key character ranges within this set:
| Range | Purpose |
|---|---|
| $00-$3F | Wall segments, corners, room outlines, floor patterns |
| $40-$6F | Door elements, lift shafts, special objects (ALERT panel, consoles) |
| $70-$7F | Additional structural chars |
| $D0-$D1 | Transfer game signal connectors (top/bottom entry points) |
| $F1 | Player horizontal wire track |
| $F2 | CPU horizontal wire track |
| $F3 | CPU border with wire entry |
| $F5-$F7 | Frame/border verticals and bottom |
| $F8-$FA | Centre crossover diagonal patterns |
| $FB-$FC | Corner/junction pieces |
| $FD | Player pulser entry |
| $FE | Decorative diagonal border |

### Charset at $7000 (text font) — 256 characters, 2048 bytes

Contains the alphanumeric font used for score display, console text, and
the "PARADROID" title lettering. Includes upper/lowercase letters, digits,
punctuation, and the "paradroid" wordmark characters.

### Charset at $6800 (game area alternate) — up to 128 characters

Used by the IRQ chain for a specific screen region (set via $D018=$2D).
Contains game-area specific characters. Note: the $6800-$6FFF region
also contains data tables and IRQ handler code from $6EC0 onwards, so
only the first portion ($6800-$6EBF) is pure character data.

### Colour model

On the C64, each character cell has a single foreground colour from the
CharColor table at $0800 (256 bytes, one per screen code, upper nybble =
colour index 0-15). Background colour is set globally via $D021. The
CharColor table is modified at runtime by `NewCharColors` for per-deck
colour schemes — the static table in the listing only has valid entries
for chars $00-$CF; chars $D0-$FF have CharColor=0 and are coloured
dynamically by the game code.

---

## 3. Sprites

C64 hardware sprites are 24x21 pixels. In hi-res mode, each pixel is 1 bit
(3 bytes per row, 63 bytes + 1 pad = 64 bytes per sprite). In multicolor
mode, pixel pairs encode 2 bits (4 colours: background, multicolor 1,
sprite colour, multicolor 2), giving 12x21 logical pixels.

**The game sprites are multicolor format.** The multicolor renderings show
coherent droid shapes; the hi-res renderings look fragmented.

### Sprite regions

| Address range | Count | Contents |
|---|---|---|
| $4C00-$50FF | 20 | Effect sprites: bullets, explosions, particle effects, transfer starburst patterns |
| $5100-$51FF | 256 bytes | Individual sprite state entries (per-byte addresses in listing) |
| $5200-$53FF | 0 (zeroed) | Dynamic sprite area — constructed at runtime for animated droid composites |
| $5400-$67FF | 80 | **Main sprite definitions**: all droid bodies (multiple orientations and animation frames), weapon effects, UI elements |

### Sprite catalogue ($5400-$67FF, 80 multicolor sprites)

The 80 main sprites include:
- **Droid bodies**: Several droid designs in 8-directional rotation frames.
  Each droid type has 3-4 animation frames (left, centre, right lean) per
  direction.
- **Bullet/projectile sprites**: Small sprites for laser bolts in 8 directions.
- **Explosion frames**: 3-4 animation frames for the explosion sequence.
- **Transfer game droid display**: Sprites for showing the player/target
  droid during the circuit puzzle.
- **UI elements**: Recharge station animations, console indicators.

### Sprite pointer table ($4BF8-$4BFF)

8 bytes — one per hardware sprite slot. Each byte N means sprite data is at
$4000 + N*64. All initialised to $00 in the listing (pointing to the empty
sprite at $4000); the game sets these dynamically.

### BBC port considerations for sprites

- **80 unique frames** at 64 bytes each = 5,120 bytes on C64.
- On BBC MODE 2, each multicolor pixel (2 C64 pixels wide) maps to roughly
  1 MODE 2 pixel (4 bits). A 12x21 MC sprite becomes approximately 12x21
  in MODE 2 = 12 pixels wide.
- BBC sprite format in the scaffolding: 16px wide, 512 bytes per sprite
  (mask + pixel data, 17 rows x 8 bytes for bg save). At 512 bytes x 80
  sprites = 40KB — fits in sideways RAM bank 1.
- C64 sprites use per-sprite colour (1 unique colour) plus 2 shared
  multicolor registers plus background. BBC MODE 2 has 8 colours per pixel
  with no attribute clash — actually more flexible. Recolouring can be done
  at draw time by palette manipulation.
- The `$5200-$53FF` dynamic sprite area is used by `BuildDroidSprite` to
  composite droid frames at runtime. The BBC port will need an equivalent
  compositing routine or pre-built frame table.

---

## 4. Tile Definitions ($E800)

32 tiles, each a 4x4 grid of character codes (16 bytes per tile, 512 bytes
total). These are the building blocks for all 16 deck maps.

Tile address formula: `$E800 + tile_index * 16`

Each tile references 16 character codes from the $7800 charset. On screen,
each tile is 32x32 pixels (4 chars x 8px).

### Tile catalogue

| Tile | Purpose | Used in |
|---|---|---|
| 0 | Empty (space) | All decks (padding) |
| 1-2 | Outer wall corners / ends | 13-14 decks |
| 3-9 | **Core wall set**: straight walls, T-junctions, corners, inner walls | All 16 decks |
| 10-13 | Room interior variants: floors, cross-hatching, open areas | 11-14 decks |
| 14-15 | Additional wall variants | 6-8 decks |
| 16-19 | **Doors and corridors**: horizontal/vertical door segments, passage tiles | 8-12 decks |
| 20 | Console / recharge station | 12 decks |
| 21-22 | **ALERT panel and status display** | All 16 decks |
| 23 | Lift shaft (variant) | 2 decks |
| 24 | Lift shaft (standard) | 5 decks |
| 25-27 | Lift shaft structural elements | 2 decks each |
| 28-29 | Decorative wall panels | 8 decks each |
| 30 | Circular element / vent | 5 decks |
| 31 | Unused (empty) | 0 decks |

Tiles 3-9, 21, and 22 appear in every single deck and form the minimum
required tile set.

### BBC port considerations for tiles

- Each 8x8 C64 character (1bpp, 8 bytes) needs converting to MODE 2 format
  (4bpp, 2 pixels per byte, 4 bytes per row = 32 bytes per character).
- 256 characters x 32 bytes = 8,192 bytes (8KB) for the full charset in
  MODE 2. Fits comfortably in sideways RAM bank 1 alongside sprites.
- The 32 tile definitions (4x4 character codes) can remain byte-identical —
  only the character graphics themselves need redrawing.
- Colour: on C64, each character cell has one foreground colour (from
  CharColor table) on a shared background. On BBC MODE 2, each pixel can
  be any of 8 colours. The tile characters could be redrawn with multiple
  colours per character for a richer look, or kept as 2-colour to match
  the C64 aesthetic.

---

## 5. Level Data

### Format

Levels use a simple RLE compression scheme:
- **Single byte** (bit 7 clear): tile index in bits 0-4, placed once.
- **Two bytes** (bit 7 set): tile index in bits 0-4 of first byte, repeat
  count in second byte.

The decoder (`BuildLevel` at $3590) fills a 64-column x 16-row tile buffer
at $8000. Each tile occupies a 4x4 character block. The buffer wraps every
256 bytes (64 tiles) and advances 4 pages (1024 bytes) per row.

### Pointer tables

| Table | Address | Contents |
|---|---|---|
| `lvPtr_lo` | $F100 | 16 low bytes (one per deck) |
| `lvPtr_hi` | $F110 | 16 high bytes (one per deck) |

### Per-deck data

| Deck | Data address | Grid size | Non-empty tiles | Unique tile types |
|---|---|---|---|---|
| 0 | $F249 | 12 x 34 | 60 | 10 |
| 1 | $F289 | 12 x 42 | 226 | 20 |
| 2 | $F325 | 16 x 64 | 136 | 13 |
| 3 | $F35C | 15 x 40 | 498 | 21 |
| 4 | $F46C | 15 x 42 | 414 | 23 |
| 5 | $F55B | 15 x 42 | 354 | 23 |
| 6 | $F65B | 15 x 42 | 362 | 21 |
| 7 | $F778 | 14 x 39 | 288 | 22 |
| 8 | $F847 | 14 x 37 | 266 | 21 |
| 9 | $F8F9 | 13 x 32 | 162 | 17 |
| 10 | $F976 | 16 x 40 | 544 | 22 |
| 11 | $FA98 | 16 x 40 | 544 | 20 |
| 12 | $FBE5 | 16 x 36 | 416 | 22 |
| 13 | $FD20 | 15 x 28 | 143 | 17 |
| 14 | $FDAF | 15 x 54 | 438 | 24 |
| 15 | $FECB | 15 x 50 | 384 | 24 |

Total RLE data: $F249-$FECB + terminator padding = approximately 3,200 bytes.

### Per-deck metadata

| Table | Address | Size | Contents |
|---|---|---|---|
| `lift_DeckY` | $F120 | 16 bytes | Row position of each deck in side view |
| `lift_DeckX` | $F130 | 16 bytes | Column position of each deck in side view |
| `lift_DeckHeight` | $F140 | 16 bytes | Height in rows |
| `lift_DeckWidth` | $F150 | 16 bytes | Width in columns |
| `deckColorScheme` | $F160 | 16 bytes | Colour palette index per deck |
| `deckNumDroids` | $F170 | 16 bytes | Number of droids per deck |

### BBC port considerations for levels

- The RLE format and tile definitions are completely platform-independent.
  The level data, pointer tables, and per-deck metadata can be kept
  byte-identical.
- Only the rendering pipeline changes: instead of writing character codes
  to C64 screen RAM, the BBC version writes MODE 2 pixel data to the
  virtual scroll buffer.
- The largest deck (deck 2) is 64 tiles wide = 2048 pixels. The BBC
  virtual scroll buffer is 24 tiles wide (192 pixels visible, 768 pixels
  in buffer). Decks wider than 24 tiles will need the scroll buffer to
  be panned during gameplay, which is already handled by the CRTC scroll
  mechanism in `hal_video.asm`.

---

## 6. Ship Side View

### Format

Stored at `SideView_dat` ($F180), 201 bytes of RLE-encoded character codes.
Uses the same RLE scheme as level data but places character codes (not tile
indices) into a 64-column x 16-row grid.

The `DrawPacked` routine ($30A0) decodes this to screen RAM at $4940
(within the $4800 screen, 8 rows down). Only columns 3-41 (39 visible
characters) are displayed; the rest are clipped.

The `ORA #$80` self-modifying instruction adds $80 to each character code
before writing, selecting characters from the upper half of the $7800
charset ($80-$FF).

After drawing, `lift_HighlightDeck` overlays coloured rectangles from the
deck metadata tables ($F120-$F150) to highlight the current deck.

### Characters used in side view

15 unique character codes (before the $80 offset): 1, 2, 3, 4, 5, 7, 8,
9, 10, 11, 13, 37, 38, 39, 40. These render as:
- Hull outline walls (vertical and horizontal segments)
- Lift shaft ladders (alternating dark/light blocks)
- Deck floor lines (dashed/dotted horizontal bars)
- Hatching patterns (engine room fill)
- Corner and junction pieces

### BBC port considerations

- The side view data is platform-independent (just character codes + RLE).
  Can be kept byte-identical.
- Need to redraw the 15 side-view characters in MODE 2 format.
- The deck highlight overlay is drawn with C64 colour RAM writes — on BBC,
  this would use MODE 2 pixel colours directly.

---

## 7. Title Screen

### Format

`Title_dat` at $CC00 — a raw 40x25 character screen (1000 bytes). Copied
by `ShowTitle` ($2879) to screen RAM at $4800 using `MoveMem` (4 pages =
1024 bytes). Colours are applied by looking up each character code in the
`CharColor` table at $0800 and writing to colour RAM at $D800.

### Contents

The title screen uses just 36 unique characters to compose:
- Large block letters spelling "PARADROID" — cleverly built from the same
  wall and room tile characters used for the deck maps (tiles for corners,
  straight walls, T-junctions form the letter shapes).
- Two info panels on the right side displaying "BY ANDREW" and "BRAYBROOK"
  in bordered boxes using the text font.
- The Hewson Consultants branding area.

### BBC port considerations

- The screen layout (1000 bytes of character codes) is platform-independent.
- The title reuses level tile characters, so converting the $7800 charset
  to MODE 2 automatically gives you the title screen for free.
- The info panel text uses different characters from the $7000 font —
  these will also need converting.

---

## 8. Transfer Minigame

### Screen layout

Built by `SubGameSelectSide` ($E016) from three data blocks:

| Data | Address | Size | Contents |
|---|---|---|---|
| `SubGameTopLines_dat` | $E613 | 120 bytes | 3 header rows (40 chars each): top frame, signal connectors, pulser entries |
| `SubGameLine_dat` | $E68B | 40 bytes | 1 wire row template, repeated 12 times: player wires, centre crossover, CPU wires |
| `SubGameBottomLine_dat` | $E6B3 | 40 bytes | Bottom frame row |

Total board: 1 blank row + 3 top + 12 middle + 1 bottom = 17 rows x 40
columns. Written to screen RAM at $4940.

### Circuit piece characters (from $7800 charset)

| Char | Hex | Purpose |
|---|---|---|
| $D0 | Top signal connector | Entry point at top of board |
| $D1 | Bottom signal connector | Entry point at bottom of board |
| $F1 | Player horizontal wire | Dashed horizontal track (left side) |
| $F2 | CPU horizontal wire | Dashed horizontal track (right side) |
| $F3 | CPU wire entry/border | Right-side pulser entry |
| $F5 | Frame top element | Top border decoration |
| $F6 | Vertical frame bar | Left/right board divider |
| $F7 | Frame bottom element | Bottom border decoration |
| $F8 | Centre crossover (top) | Diagonal signal routing, upper |
| $F9 | Centre crossover (mid) | Diagonal signal routing, connector |
| $FA | Centre crossover (bottom) | Diagonal signal routing, lower |
| $FB | Corner/junction top | Top frame corner |
| $FC | Corner/junction bottom | Bottom frame corner |
| $FD | Player pulser entry | Left-side pulser entry |
| $FE | Diagonal border | Decorative border hatching |

### Wire animation

`XferWire_anim` at $6C6C (16 bytes) provides 8 animation frames for the
signal propagation effect, cycling through characters $BA, $AE, $AB, $EA
(diagonal wire patterns).

### Runtime colours

The static `CharColor` table has $00 (black) for chars $D0-$FF. The game
sets colours dynamically via `FillCRAM`:
- Board fill: colour $F8 (light grey bg)
- Player side: `xfer_PlyColor` = $FF (white foreground)
- CPU side: `xfer_CpuColor` = $FC (light grey foreground)
- The vertical bar positions (columns 3, 18, 21, 36) get alternating
  player/CPU colours.

### BBC port considerations

- The board layout data (200 bytes) is platform-independent.
- The 15 circuit characters need redrawing in MODE 2 format.
- The wire animation uses 4 additional characters ($AE, $AB, $BA, $EA)
  that also need converting.
- The two-tone colour scheme (player vs CPU) maps well to MODE 2 where
  each pixel can be independently coloured.

---

## 9. Summary: Graphics Conversion Checklist for BBC Port

### Character sets to convert (C64 1bpp -> BBC MODE 2 4bpp)

| Set | Address | Chars | C64 bytes | BBC bytes (32/char) | Purpose |
|---|---|---|---|---|---|
| Main tiles | $7800 | 256 | 2,048 | 8,192 | Level tiles, transfer pieces, side view |
| Text font | $7000 | 256 | 2,048 | 8,192 | Console text, score, title panels |
| Game alt | $6800 | ~96 | 768 | 3,072 | Game area alternate chars |
| **Total** | | ~608 | ~4,864 | ~19,456 | |

### Sprites to convert (C64 multicolor -> BBC MODE 2 software sprites)

| Set | Address | Count | C64 bytes | BBC bytes (512/spr) | Purpose |
|---|---|---|---|---|---|
| Main defs | $5400-$67FF | 80 | 5,120 | 40,960 | Droids, bullets, explosions |
| Effects | $4C00-$50FF | 20 | 1,280 | 10,240 | Particles, transfer effects |
| **Total** | | 100 | 6,400 | 51,200 | |

51KB of sprite data fits in sideways RAM banks 1-2 (32KB available across
two banks, so sprites may need to share bank 1 with tile data or overflow
into bank 2).

### Data that ports byte-identical (no conversion needed)

| Data | Address | Size | Contents |
|---|---|---|---|
| Level RLE | $F249-$FECB | ~3,200 | All 16 deck maps |
| Tile defs | $E800-$E9FF | 512 | 32 tile definitions (4x4 char indices) |
| Level ptrs | $F100-$F11F | 32 | Deck data pointer table |
| Deck metadata | $F120-$F17F | 96 | Positions, sizes, colours, droid counts |
| Side view | $F180-$F248 | 201 | Ship cross-section RLE |
| Title screen | $CC00-$CDE7 | 1,000 | Title screen character layout |
| Transfer board | $E613-$E6DA | 200 | Minigame board layout |
| All data tables | $6B00-$6EBF | ~960 | Movement, scoring, animation, text |

### Colour mapping (C64 16-colour -> BBC MODE 2 8-colour)

The C64 has 16 colours; BBC MODE 2 has 8 (with flash giving 16 logical
colours, though flash is rarely useful for games). Suggested mapping:

| C64 colour | Index | BBC MODE 2 | Notes |
|---|---|---|---|
| Black | 0 | Black (0) | Direct |
| White | 1 | White (7) | Direct |
| Red | 2 | Red (1) | Direct |
| Cyan | 3 | Cyan (6) | Direct |
| Purple | 4 | Magenta (5) | Closest |
| Green | 5 | Green (2) | Direct |
| Blue | 6 | Blue (4) | Direct |
| Yellow | 7 | Yellow (3) | Direct |
| Orange | 8 | Yellow (3) | Approximate |
| Brown | 9 | Red (1) | Approximate |
| Light red | 10 | Red (1) | Approximate |
| Dark grey | 11 | Black (0) | Approximate |
| Grey | 12 | White (7) | Approximate (or use flash) |
| Light green | 13 | Green (2) | Approximate |
| Light blue | 14 | Cyan (6) | Approximate |
| Light grey | 15 | White (7) | Approximate |

The per-deck colour schemes (`deckColorScheme` at $F160) will need
adjustment after the palette mapping to ensure sufficient contrast.

---

*Generated from analysis of `paradroid_ce.lst` (18,339 lines), April 2026.*
