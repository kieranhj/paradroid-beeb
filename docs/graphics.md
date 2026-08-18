> **The play area is HIRES, corrected 2026-08-18.** Anything below describing the deck charset as
> multicolour, or selecting the mode per cell on bit 3 of the colour nibble, is wrong: bit 3 is
> part of the colour. Multicolour applies only to the transfer board and the ship sideview. See
> `layer-1-graphics-pipeline.md`.

# Graphics extraction reference — the C64 side

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

Where the C64's graphics data lives in `paradroid_ce.lst`, what format it is in, and which tool
reads it. **This document describes the source, not the port.** How each thing was converted, and
what it cost, is in the layer documents — `layer-1-graphics-pipeline.md` for the charset and
palettes, `layer-4-player.md` and `layer-5-blitter.md` for the sprites.

Each section ends with a **Status** note saying what has actually been ported, so the two do not
drift apart again.

> **This file used to target BBC Master MODE 2 and was wrong throughout.** Every byte count,
> every "BBC port considerations" block and the whole conversion checklist assumed 8 colours at
> 4 bits per pixel on a Master. The port is **MODE 1 on a Model B**: 4 colours, 320 across, a
> character is **16 bytes**, and one C64 multicolour pixel is exactly two MODE 1 pixels. The old
> §9 also proposed a fixed C64 → BBC colour table, which is not merely inaccurate but a scheme
> that provably does not work — see *Colour* at the end.

---

## 1. Extraction tools

All in `tools/`, Python 3 + Pillow. Each parses the IDA listing directly to reconstruct a 64K
memory image, then extracts a region. Output goes to `tools/output/`.

### Producing the port's data

These emit BeebASM sources into `src/data/` (gitignored — converted game artwork).

| Tool | Emits | Contents |
|---|---|---|
| `export_bbc.py` | `chardata.asm` | C64 bitmaps, palette slots, code→index remap — the charset is built from this at deck load, not shipped |
| | `colours.asm` | 8 scheme records, deck→scheme, per-deck colour maps |
| | `tiledefs.asm` | 32 tile definitions, byte-identical |
| | `levels.asm` | 16 deck maps RLE + pointers + metadata, byte-identical |
| | `plandata.asm` | the deck plan's 31 char bitmaps plus the per-deck ink table, bank 7 |
| `export_droids.py` | `droids.asm` | 24 droid types × 8 rotor phases, as compiled 6502 plus stored rows |
| | `droidgame.asm` | The game-data half: speeds, waypoints, per-deck type base |
| `export_strings.py` | `strings.asm` | The `$C000` string table, translated to port glyph indices, bank 6 |
| | `strings7.asm` | The same bytes again under a second label, for the droid database in bank 7 |
| `export_droidicon.py` | `droidicon.asm` | The console's composed droid icon: one rotor phase and ten digits, bank 6 |
| | `droidicon7.asm` | The same bytes again, for bank 7 |
| `export_droidinfo.py` | `droidinfo.asm` | `DroidInfo_dat` (`$EB00`) less its portrait sprite images: per-type stats and the packed descriptions, bank 7 |
| `verify_bbc.py` | — | Round-trips the generated sources back to C64 form and diffs against the listing |

**Two tables exist twice on purpose.** The console is in bank 6 and the droid database in bank 7,
only one bank is visible at a time, and both print from the string table and draw the same droid
icon. Each pair is written by one tool from one list of bytes, so the copies cannot drift.

### Visualising the C64 original

| Tool | Output |
|---|---|
| `rip_graphics.py` | Sprites and charsets from the VIC-II bank, hires and multicolour renders, plus `vic_bank_raw.bin` and `memory_map.txt` |
| `rip_levels.py` | `deck_00.png`–`deck_15.png`, `all_decks.png`, `tiles.png`, `level_stats.txt` |
| `rip_deck_mixed.py` | Built on the retired multicolour model; **not** a faithful deck render. `palette_lab.py` is |
| `rip_tiles_mc.py` | The `$7800` tile set as multicolour characters |
| `rip_sideview.py` | Ship cross-section, with and without deck overlays |
| `rip_screens.py` | Title screen (three charsets), transfer board, the 15 circuit-piece characters |

### Answering specific questions

| Tool | Question |
|---|---|
| `analyse_charmode.py` | Retired with the multicolour model — every deck cell is hires |
| `analyse_alert.py` | Per deck, does the ALERT lettering stay legible? Hires everywhere now, so it does |
| `compare_tile.py` | One tile, C64 beside port — is a difference a bug or faithful? |
| `unpack_prg.ps1` | Unpacks the four C64 releases under VICE, for diffing against the listing |

---

## 2. Character sets

Three custom charsets in VIC-II bank 1 (`$4000-$7FFF`), 8 bytes per character. `$D018` switches
between them at different scanlines via the raster IRQ chain.

### The play area is HIRES

This is the single most important fact in the document, and getting it wrong cost three rewrites of
the conversion — the third of which survived from Layer 1 to 2026-08-18.

`$D016` bit 4 enables multicolour text mode, and the self-modifying `_d016Mode` routine at `$6F1B`
patches its own `LDA` operand. **Gameplay writes `$C0` — bit 4 CLEAR.** `_reenter_game` (`$1532`)
sets it along with `$D018 = $2F`, the `$7800` tile charset, and jumps to `EnterGame`. The two
places that write `$D0` are `$22AD`, after `ShowXferInfo`, for the transfer board, and `$3092` in
`DrawSideview` for the ship cross-section.

So every deck cell is hires: **eight 1-bit pixels, the cell's colour against `$D021`**, and the
colour is the **full four-bit** colour-RAM nibble, 0–15. Bit 3 is part of the colour.

`CharColor` (`$0800`) holds a palette slot in its upper nibble; `NewCharColors` (`$3577`) rewrites
the lower nibble per deck from a 12-slot record at `$6A44`, selected by `deckColorScheme`
(`$F160`); `BuildLevel` writes the byte to colour RAM. So a character's **colour** changes between
decks — its mode does not, because there is only one.

> **The bit-3 theory was wrong and three screenshots disprove it.** `ref/c64_deck5.png` shows the
> deck-5 floor in light grey with **orange** crosshairs — colour 8, bit 3 set — drawn solid, and
> `ALERT.` crisp at single-pixel spacing. Under the old reading that cell was multicolour: the
> crosshairs would be four fat pixels of the wrong colours and the letters would join.
> `c64_deck0a.png` (blue grid, dark grey ALERT plaque) and `c64_deck4.png` (grey grid on light
> green) agree. `rip_deck_mixed.py` and `analyse_charmode.py` were built on the wrong model and
> their output is only meaningful for the transfer board and the sideview.

**`$D022`/`$D023` do not apply to the deck.** `DrawSideview` (`$308A`/`$308F`) sets them to `$F1`
and `$F0` for its own multicolour screen and they persist, which is what made them look like
play-area state.

**`$D021` is solved: it is slot 0 of the deck's colour record**, and it differs per deck.
`InitColors` (`$27E5`) copies the record with `Y` counting down to zero, leaving slot 0 in the
accumulator, and `$2821` stores it in `Irq1bgColor`; `Irq_118` (`$6F4C`) writes that to `$D021`
for the 128 lines of play area. `SetIntroColors` does the same copy from a **random** record, which
is what made "slot 3" look plausible for years. Only decks 2 and 7 are light blue; the rest are
greys, light red, yellow, light green and cyan.

### Charset at `$7800` — main game tiles, 256 characters, 2048 bytes

The primary charset:
- **Level map tiles** (`$00-$7F`) — walls, floors, doors, lifts, consoles, decoration. The building
  blocks referenced by the 32 tile definitions at `$E800`.
- **Transfer game circuit pieces** (`$D0-$FE`) — 15 unique characters.
- **Title screen** reuses the level tile chars as large block letters spelling "PARADROID".

| Range | Purpose |
|---|---|
| `$00-$3F` | Wall segments, corners, room outlines, floor patterns |
| `$40-$6F` | Door elements, lift shafts, special objects (ALERT panel, consoles) |
| `$70-$7F` | Additional structural chars |
| `$D0-$D1` | Transfer game signal connectors (top/bottom entry) |
| `$F1`/`$F2` | Player / CPU horizontal wire track |
| `$F3` | CPU border with wire entry |
| `$F5-$F7` | Frame/border verticals and bottom |
| `$F8-$FA` | Centre crossover diagonal patterns |
| `$FB-$FC` | Corner/junction pieces |
| `$FD` | Player pulser entry |
| `$FE` | Decorative diagonal border |

> Codes `$00-$1E` double as the **console deck plan's** map glyphs — `con_DeckInfo` places level
> RLE codes directly as characters, in hires. `export_bbc.py` ships them a second time for that,
> as raw bitmaps plus a per-deck ink table in `plandata.asm` (bank 7) — see layer-9 §6e.

### Charset at `$7000` — text font, 256 characters, 2048 bytes

Alphanumerics for score display, console text, and the "PARADROID" title lettering. Upper and
lowercase, digits, punctuation, and the wordmark characters.

### Charset at `$6800` — game area alternate, up to 128 characters

Used by the IRQ chain for a specific screen region (`$D018=$2D`). Note `$6800-$6FFF` also holds data
tables and IRQ handler code from `$6EC0` onwards, so only `$6800-$6EBF` is character data.

> **Status.** Only `$7800` is ported. A MODE 1 character is **16 bytes** — two 8-byte halves, left
> then right — so plotting one is a flat 16-byte copy with no shifting or masking. Only the **137
> characters the tiles actually reference** are converted, through a 256-byte remap table, giving a
> 2192-byte charset rather than 4K. It is **built at deck load**, because a character's mode *and*
> colour both depend on the deck scheme and shipping 16 converted charsets would have cost 64K.
> `$7000` and `$6800` are not converted and are wanted for Layers 9–11.
> See [`layer-1-graphics-pipeline.md`](layer-1-graphics-pipeline.md).

---

## 3. Sprites

C64 hardware sprites are 24×21. Hires is 1 bit per pixel (63 bytes + 1 pad = 64 per sprite);
multicolour encodes pixel pairs, giving 12×21 logical pixels in 4 colours.

**The game sprites are multicolour.** The multicolour renderings show coherent droid shapes; the
hires renderings look fragmented.

### Sprite regions

| Address | Count | Contents |
|---|---|---|
| `$4C00-$50FF` | 20 | Effect sprites: bullets, explosions, particles, transfer starbursts |
| `$5100-$51FF` | 256 B | Individual sprite state entries |
| `$5200-$53FF` | 0 (zeroed) | **Dynamic sprite area** — droid artwork is constructed here at runtime |
| `$5400-$67FF` | 80 | Main sprite definitions: weapon effects, UI elements |

### There is no droid sprite in the data

`$5200-$53FF` ships **zeroed**. Every droid's artwork is built at runtime:

| Routine | Writes |
|---|---|
| `BuildDroidSprite` (`$3C77`) | the three-digit droid number into sprite rows 6–13 |
| `AnimateDroids` (`$3CFB`) | the spinning rotor into rows 0–4 and 15–19, from `RotAnim_*` |

Rows 5, 14 and 20 are never written, so they stay transparent. That is the entire droid: a rotor
above and below, the number in the middle. Details that matter when replaying it:

- The bottom half is the top half in **reverse row order**, not mirrored left to right.
- Rows 0/1 and 18/19 carry only a middle byte, from 2-entry tables indexed by `phase >> 2`, and the
  bottom pair uses the *other* entry — which is what makes the two ends alternate.
- Row 2 and row 17's right-hand byte is `$80`, left in the accumulator from the row above. There is
  no `RotAnim_2_17R` table.

### Sprite pointer table (`$4BF8-$4BFF`)

8 bytes, one per hardware sprite slot; byte *N* means data at `$4000 + N*64`. All `$00` in the
listing (the empty sprite at `$4000`); the game sets them dynamically.

> **Status.** `export_droids.py` replays both routines offline for all 24 droid types and 8 phases.
> The rotor is identical for every droid, so rows are shared: 5 rotor rows × 8 phases, 2 alternating
> end rows × 8 phases, 8 digit rows × 24 types, one blank — **249 rows × 7 bytes = 1743 bytes**.
>
> **Masks are not stored.** Every opaque pixel maps to logical colour 1, 2 or 3 and never 0, so a
> pixel is transparent exactly when both its bits are clear, and one 256-byte table recovers the
> mask from the data.
>
> The blitter is **compiled**: generated 6502 per rotor row and per digit glyph, pixels and masks
> baked in as immediates, occupying a 16K sideways bank of its own. A sprite costs 5,814 cycles.
> The old estimate here — 512 bytes per sprite, 51K total — was out by an order of magnitude in the
> wrong direction and assumed a format never used.
> See [`layer-4-player.md`](layer-4-player.md) and [`layer-5-blitter.md`](layer-5-blitter.md).
>
> The effect sprites **were ported in Layer 7c** (2026-08-15) — 31 bullet and explosion frames
> exported with bounding boxes into bank 5, 0/31 round-trip mismatches. The 80 main definitions
> remain unported.
>
> **The droid database's portrait is in that unported block.** `BuildIntroSprites` (`$3629`) builds
> a 48 × 84 multicolour picture per type from four images the type's `DroidInfo_dat` record names
> (bytes 0-7) plus their mirrors — image *N* meaning `$4000 + N*64`, so `$66`-`$90` land in
> `$5400-$67FF`. Twenty-four types of it is ~6 K raw, which is the whole of bank 7's free space, so
> the console's database draws the runtime-composed rotor-and-digits droid instead and
> `export_droidinfo.py` does not export bytes 0-7 at all. See `docs/layer-9-hud.md` §6f, decision 2.

---

## 4. Tile definitions (`$E800`)

32 tiles, each a 4×4 grid of character codes: 16 bytes per tile, 512 bytes total. Address is
`$E800 + tile_index * 16`. Each tile references 16 characters from the `$7800` charset, and is
32×32 pixels on screen.

| Tile | Purpose | Used in |
|---|---|---|
| 0 | Empty (space) | All decks (padding) |
| 1-2 | Outer wall corners / ends | 13-14 decks |
| 3-9 | **Core wall set**: straight walls, T-junctions, corners, inner walls | All 16 decks |
| 10-13 | Room interior variants: floors, cross-hatching, open areas | 11-14 decks |
| 14-15 | Additional wall variants | 6-8 decks |
| 16-19 | **Doors and corridors** | 8-12 decks |
| 20 | Console / recharge station | 12 decks |
| 21-22 | **ALERT panel and status display** | All 16 decks |
| 23 | Lift shaft (variant) | 2 decks |
| 24 | Lift shaft (standard) | 5 decks |
| 25-27 | Lift shaft structural elements | 2 decks each |
| 28-29 | Decorative wall panels | 8 decks each |
| 30 | Circular element / vent | 5 decks |
| 31 | Unused (empty) | 0 decks |

Tiles 3–9, 21 and 22 appear in every deck and form the minimum required set.

> **Status.** Ported byte-identical — only the character graphics needed converting, exactly as
> predicted. `tiledefs.asm`, 512 bytes.

---

## 5. Level data

### Format

- **Single byte** (bit 7 clear): tile index in bits 0–4, placed once.
- **Two bytes** (bit 7 set): tile index in bits 0–4 of the first, repeat count in the second.

`BuildLevel` (`$3590`) fills a 64-column × 16-row tile buffer at `$8000`. The buffer wraps every
256 bytes (64 tiles) and advances 4 pages per row.

### Pointer tables

| Table | Address | Contents |
|---|---|---|
| `lvPtr_lo` | `$F100` | 16 low bytes, one per deck |
| `lvPtr_hi` | `$F110` | 16 high bytes |

### Per-deck data

| Deck | Address | Grid | Non-empty tiles | Unique types |
|---|---|---|---|---|
| 0 | `$F249` | 12 × 34 | 60 | 10 |
| 1 | `$F289` | 12 × 42 | 226 | 20 |
| 2 | `$F325` | 16 × 64 | 136 | 13 |
| 3 | `$F35C` | 15 × 40 | 498 | 21 |
| 4 | `$F46C` | 15 × 42 | 414 | 23 |
| 5 | `$F55B` | 15 × 42 | 354 | 23 |
| 6 | `$F65B` | 15 × 42 | 362 | 21 |
| 7 | `$F778` | 14 × 39 | 288 | 22 |
| 8 | `$F847` | 14 × 37 | 266 | 21 |
| 9 | `$F8F9` | 13 × 32 | 162 | 17 |
| 10 | `$F976` | 16 × 40 | 544 | 22 |
| 11 | `$FA98` | 16 × 40 | 544 | 20 |
| 12 | `$FBE5` | 16 × 36 | 416 | 22 |
| 13 | `$FD20` | 15 × 28 | 143 | 17 |
| 14 | `$FDAF` | 15 × 54 | 438 | 24 |
| 15 | `$FECB` | 15 × 50 | 384 | 24 |

Total RLE ≈ 3,200 bytes.

### Per-deck metadata

| Table | Address | Size | Contents |
|---|---|---|---|
| `lift_DeckY` | `$F120` | 16 B | Row position of each deck in side view |
| `lift_DeckX` | `$F130` | 16 B | Column position in side view |
| `lift_DeckHeight` | `$F140` | 16 B | Height in rows |
| `lift_DeckWidth` | `$F150` | 16 B | Width in columns |
| `deckColorScheme` | `$F160` | 16 B | Colour palette index per deck |
| `deckNumDroids` | `$F170` | 16 B | Number of droids per deck |

> **Status.** Ported byte-identical — RLE, pointers and metadata all unchanged, 3,335 bytes.
>
> The **rendering diverges deliberately.** The C64 expands every tile into a 256×64 *character* map
> at `$8000` (16K); the port keeps only the **64×16 tile map (1K)** and expands to characters at
> draw time — two extra lookups per character for a 15K saving, which is not a close call on a
> Model B. And the map is never buffered whole: the play area is a 10K circular strip at `&5800`
> scrolled by the CRTC, so only the leading edge is ever drawn and a deck's width costs nothing.
> See [`layer-2-static-render.md`](layer-2-static-render.md) and
> [`layer-3-scroll.md`](layer-3-scroll.md).

---

## 6. Ship side view

`SideView_dat` (`$F180`), 201 bytes of RLE — same scheme as the level data, but placing *character*
codes into a 64×16 grid.

`DrawPacked` (`$30A0`) decodes it to screen RAM at `$4940` (8 rows into the `$4800` screen). Only
columns 3–41 are displayed; the rest is clipped. An `ORA #$80` self-modifying instruction adds `$80`
to each code, selecting the upper half of the `$7800` charset. Afterwards `lift_HighlightDeck`
overlays coloured rectangles from the deck metadata at `$F120-$F150`.

15 unique codes (before the `$80` offset): 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 13, 37, 38, 39, 40 —
hull outline, lift shaft ladders, deck floor lines, engine-room hatching, corners and junctions.

> **Status.** Ported 2026-08-17 as Layer 8b, the lift's deck-selection screen —
> `tools/export_sideview.py` emits the RLE verbatim plus the characters in three pen sets, and
> `src/liftview.asm` (bank 7) transliterates `DrawPacked` and `lift_HighlightDeck` against Layer
> 10's shadow screen. The deck highlight is the C64's own ±$10 character swap; only the *colour*
> became a per-character pen rule. See [`layer-8b-lift-view.md`](layer-8b-lift-view.md).
> The console's ship page (`con_ShipInfo`) can now reuse all of it.

---

## 7. Title screen

`Title_dat` at `$CC00` — a raw 40×25 character screen, 1000 bytes. `ShowTitle` (`$2879`) copies it
to screen RAM at `$4800`; colours come from looking each code up in `CharColor` (`$0800`) and
writing colour RAM at `$D800`.

Just 36 unique characters compose it: large block letters spelling "PARADROID", built from the same
wall and room tile characters used for the deck maps; two bordered info panels reading "BY ANDREW"
and "BRAYBROOK" in the text font; and the Hewson Consultants branding.

> **Status. Ported 2026-08-18** by `tools/export_title.py` → `src/data/title.asm`, in bank 7, and
> verified against `tools/output/title_screen_7800.png` cell for cell.
>
> **The block letters did NOT come free with the `$7800` conversion.** Twelve of the title's
> thirty-six characters — `$52` `$53` `$DF` `$E0`-`$E7` `$FF` — are not in `chardata.asm` at all,
> because `export_bbc.py` converts only the characters some TILE DEFINITION references and those
> twelve are used by the title and nothing else. The title therefore carries its own 36 glyphs
> (576 B) beside its RLE map (564 B). Extending the shared charset instead would be more faithful
> and would also give `EndGame`'s wash its four missing characters back, but it moves `NUM_CHARS`
> and the code→index remap every deck depends on. See `layer-11-sound-title.md` [DECISION 8].
>
> Colour is logical 3 on logical 0 — white on black under MODE 1's default palette, against the
> C64's two-tone outlines and purple panel text. Layer 14's.

---

## 8. Transfer minigame

`SubGameSelectSide` (`$E016`) builds the board from three blocks:

| Data | Address | Size | Contents |
|---|---|---|---|
| `SubGameTopLines_dat` | `$E613` | 120 B | 3 header rows: top frame, signal connectors, pulser entries |
| `SubGameLine_dat` | `$E68B` | 40 B | 1 wire row template, repeated 12× |
| `SubGameBottomLine_dat` | `$E6B3` | 40 B | Bottom frame row |

Total 1 blank + 3 top + 12 middle + 1 bottom = 17 rows × 40 columns, written to `$4940`.

### Circuit piece characters (from the `$7800` charset)

| Char | Purpose |
|---|---|
| `$D0` / `$D1` | Top / bottom signal connector |
| `$F1` / `$F2` | Player / CPU horizontal wire track |
| `$F3` | CPU wire entry / border |
| `$F5` / `$F7` | Frame top / bottom element |
| `$F6` | Vertical frame bar |
| `$F8`–`$FA` | Centre crossover, upper / connector / lower |
| `$FB` / `$FC` | Corner junction, top / bottom |
| `$FD` | Player pulser entry |
| `$FE` | Decorative border hatching |

`XferWire_anim` (`$6C6C`, 16 bytes) gives 8 animation frames for signal propagation, cycling
`$BA`, `$AE`, `$AB`, `$EA`.

Colours are set at runtime by `FillCRAM`, since `CharColor` is `$00` for `$D0-$FF`: board fill
`$F8`, player side `$FF` (white), CPU side `$FC` (light grey), with the vertical bars at columns 3,
18, 21 and 36 taking alternating player/CPU colours.

> **Status.** Ported — Layer 10, built 2026-08-17: `src/data/xferboard.asm` in bank 7, drawn by
> `xfer.asm` (see `layer-10-transfer.md`). As predicted below, the layout data is
> platform-independent and the circuit characters come with the `$7800` conversion; the four wire
> animation characters do too. The two-tone player/CPU scheme needs two of MODE 1's four colours,
> which is affordable on a screen with no deck art on it.

---

## 9. What is converted, and what is not

| | C64 source | Ported as | Status |
|---|---|---|---|
| `$7800` charset | 2,048 B | `chardata.asm` 1,489 B → 2,192 B built at deck load | ✅ |
| Tile definitions | 512 B | `tiledefs.asm`, byte-identical | ✅ |
| Level RLE + metadata | ~3,300 B | `levels.asm`, byte-identical | ✅ |
| Colour schemes | — | `colours.asm` 432 B, precomputed per deck | ✅ |
| Droid sprites | constructed at runtime | `droids.asm` — 1,743 B of rows plus compiled 6502 | ✅ |
| Droid game data | — | `droidgame.asm` — speeds, waypoints, per-deck type base | ✅ |
| `$7000` text font | 2,048 B | — | Layers 9–11 |
| `$6800` alternate | ~768 B | — | Probably never; check what uses it first |
| Effect sprites | 1,280 B | — | Layer 7 |
| Main sprite defs `$5400` | 5,120 B | — | Layer 7 |
| Side view | 201 B | — | Layer 9 |
| Title screen | 1,000 B | — | Layer 11 |
| Transfer board | 200 B | — | Layer 10 |

### Colour — a fixed C64 → BBC table does not work

The old version of this section proposed a static 16 → 8 mapping. **That scheme is broken, and it
was not obvious.** Several C64 colours share a nearest BBC match, so two logical colours collapse
onto one physical and whatever is drawn in the second becomes invisible. Light blue (the floor) and
blue (shadow detail) both map to BBC blue, which silently erased detail on **12 of the 16 decks** —
including the ALERT panel's frame, which is what made the lettering look wrong.

What works instead, and is what `export_bbc.py` does:

1. **Logical colours are assigned per deck by usage.** Count how often each C64 colour appears
   across the tile set; logical 0 is the background, and the three most-used take 1–3. Anything left
   over maps to the nearest by luminance. Deck 1 needs only three foregrounds — white (272 uses),
   red (220), yellow (78) — so nothing is lost there, but a deck needing four or more would lose one.
2. **Physical colours are assigned per deck, greedily, to the nearest *unused*.** Preferences are
   honoured while free (floor → blue, grid → magenta, shadow → black). `verify_bbc.py` asserts all
   16 decks end with four distinct physical colours, so the collapse cannot silently return.

**Per-deck recolour is therefore free.** Colour is not baked into the tiles; a deck's scheme is a
palette write, mirroring how the C64 recoloured through `CharColor`.

> Twice now a bug has hidden in the stage *after* conversion. Both times the conversion itself was
> correct and the damage was done in colour assignment. Check the palette before re-reading the
> pixel maths.

**Multicolour ALERT lettering is faithful, not a bug.** Row 0 of tile 22 (`$63-$66`) is the
lettering and sits on slot 7, which is multicolour under 8 of the 16 deck schemes — 4 pixels wide,
so the single-pixel letter gaps cannot exist and the letters join. The C64 does exactly the same.
Decided to stay faithful rather than force those characters to hires; `compare_tile.py` is how such
questions get settled.

---

*Originally generated from analysis of `paradroid_ce.lst` (18,339 lines), April 2026. Rewritten
2026-08-14, when the MODE 2 assumptions throughout were corrected to what was actually built.*
