# Paradroid → BBC Micro Model B: Port Plan

Living document. Revised as each layer lands.

## Decisions taken

| Decision | Choice | Date |
|---|---|---|
| Target machine | BBC Model B / B+ with **2 × 16K sideways RAM banks** | 2026-08-04 |
| Screen mode | MODE 1, 320×200, 4 colours, 16K wrap at `&4000–&7FFF` | 2026-08-04 |
| Scrolling | **Undecided** — to be proven by spike in Layer 3 | 2026-08-04 |
| Architecture | No HAL. Build one working layer at a time, verified in the emulator before moving on. | 2026-08-04 |

### Why MODE 1

**Both the tiles and the sprites are C64 multicolour** — 2-screen-pixel-wide logical pixels, four
colours. MODE 1 is also four colours at 320 pixels across, so one C64 multicolour pixel is exactly
two MODE 1 pixels:

| | C64 | MODE 1 |
|---|---|---|
| Map character | 4 MC px = 8 screen px | 8 px, 1:1 |
| Tile (4×4 chars) | 32×32 px | 32×32 px, 1:1 |
| Multicolour pixel | 2 screen px | exactly 2 px |
| Colours per cell | 4 | 4 |
| Display | 320×200 | 320×200 |

Consequence: tiles, sprites, title screen and transfer board all convert **mechanically** from the
ripped C64 data. No artwork is redrawn, and the colour count is exact rather than merely adequate.

MODE 2 was rejected: 8 colours the game does not need, in exchange for redrawing every tile at half
width and breaking the 32×32 tile aspect ratio.

> An earlier version of this section described the map as 1bpp hires and the 4-colour budget as
> "tight". Both were wrong — see Layer 1.

## Source material: which Paradroid?

The listing this port is built from (`paradroid_ce.lst`) is a disassembly of **Paradroid Redux**, a
community-extended version — **not** the 1985 Hewson original. Everything downstream of it inherits
that: `ANNOTATION.md`, `GRAPHICS.md`, and all data extracted by `tools/` (sprites, charsets, the 16
deck maps, tile definitions, side view, title screen, transfer board).

Practically this means the port currently reproduces *Redux*. Not a problem for Layers 0–4, which
are pipeline and rendering work where any version would do. It could matter later:

| Layer | Possible divergence |
|---|---|
| 2 — deck render | Redux may have altered or added deck maps |
| 6 — droids | droid roster, stats, AI tuning |
| 7 — combat | scoring tables, alert behaviour |
| 10 — transfer | circuit-puzzle rules or board layout |

**If a clean reference is needed:** obtain the original release's `.prg` and disassemble it
separately, then diff the data tables against the Redux extraction. Not required yet — noted so
that an unexpected difference from remembered C64 behaviour is diagnosed rather than debugged.

Decide explicitly before Layer 6 whether the target is Redux fidelity or original fidelity.

## Memory budget

| Region | Size | Contents |
|---|---|---|
| ZP (`&00–&8F`, `&A8–&AF`) | ~150 B | hot game variables. C64 used ~206 B — the excess demotes to page 4. |
| `&0100–&01FF` | 256 B | stack |
| `&0400–&0CFF` | ~2.2 K | reclaimed OS workspace: BASIC, sound/printer buffers, UDK, UDC |
| `&0E00–&3FFF` | 12.5 K | main code + resident data (requires DFS displaced after load) |
| `&4000–&7FFF` | 16 K | MODE 1 screen, 320×200 |
| SWRAM bank 0 | 16 K | converted tiles, sprites, level RLE, metadata |
| SWRAM bank 1 | 16 K | paged code: transfer minigame, console/info screens, side view |

Open risk: sprite data in MODE 1 with pre-shifted copies runs 30–60K depending on how many shift
variants and whether masks are stored or generated. May force a third bank or runtime shifting.
Quantify at Layer 4.

## Layers

Each layer ends with something visibly working in b-em. Nothing moves on until it does.

### Layer 0 — Toolchain and a booting screen ✅ DONE
`bin/beebasm.exe`, `build.ps1` (`-Run` launches b-em), jsbeeb MCP for in-loop verification.
`src/main.asm` boots to a 320×200 MODE 1 screen at `&4000` and draws a fill + 1-px border.

**Confirmed empirically:**
- **CRTC start address = screen address ÷ 8.** Base `&4000` → R12/R13 = `&0800`. The 16K wrap holds.
- Geometry: R6 = 25 rows, R7 = 31, everything else at MODE 1 defaults. R4 = 38 / R5 = 0 is left
  alone to preserve 312 scanlines / 50 Hz.
- Screen occupies exactly `&4000–&7E7F` (16000 bytes). `&7E80+` untouched.
- **`&3000–&3FFF` is genuinely reclaimed** — verified still zero after the fill.
- Pixel address formula verified: `addr = &4000 + (y DIV 8)*640 + (x DIV 4)*8 + (y MOD 8)`.
- MODE 1 byte encoding: pixel *n* takes bit `7-n` (high colour bit) and bit `3-n` (low bit).
  Solid colour 0/1/2/3 = `&00`/`&0F`/`&F0`/`&FF`.
- DFS filenames are max 7 chars — the disc file is `PARA`, not `PARADROID`.

Outstanding niggle: the display sits slightly low; R7 wants a nudge. Deferred — final geometry
changes at Layer 9 anyway (see below).

**RAM reclaim opportunity (from KC):** Paradroid's layout is a static title bar at the top, a gap,
then the active play area. The play area needs far fewer than 25 char rows, so R6 can shrink
further and hand back more of `&4000–&7E7F`. Quantify once the HUD split is designed; it may
relieve the sprite-data budget without touching the mode choice.

### Layer 1 — Graphics data pipeline ✅ DONE
`tools/export_bbc.py` emits BeebASM sources into `src/data/` (gitignored — converted game
artwork). `tools/verify_bbc.py` round-trips them back and diffs against the listing.
`src/main.asm` renders all 32 tile definitions as an 8×4 sheet.

| Output | Size | Contents |
|---|---|---|
| `charset.asm` | 4096 B | 256 chars × 16 bytes, MODE 1 |
| `tiledefs.asm` | 512 B | 32 tiles × 4×4 char codes, byte-identical |
| `levels.asm` | 3335 B | 16 deck maps RLE + offsets + metadata, byte-identical |

> **Corrected twice.** First version: treated the charset as 1bpp hires, converted with a nibble
> split — wrong, `ref/start screen.png` shows four colours per cell. Second version: called the
> whole charset multicolour — also wrong, because ALERT keeps single-pixel letter spacing, which
> a 4-pixel-wide multicolour character cannot produce. The truth is that both modes are in use.

**The C64 mixes hires and multicolour cells on the same screen.** `$D016` bit 4 enables
multicolour text mode globally (the `_d016Mode` routine at `$6F1B` is self-modifying, patching its
own `LDA` operand between `$D0` and `$C0`), but in that mode the choice is made **per cell** by
bit 3 of the colour RAM nibble:

| colour RAM | cell renders as |
|---|---|
| `0`–`7` | hires — 8 pixels, background + that colour |
| `8`–`15` | multicolour — 4 double-width pixels, 4 colours |

**For deck 1 the split is 930 hires cells to 190 multicolour** — the play area is mostly hires,
with multicolour used for shading. That is why the ALERT lettering stays crisp while the floor
and walls carry four colours.

The mode is driven per character code, and it is **deck dependent**:

```
CharColor[code]  upper nibble = palette slot (0-11)
NewCharColors    rewrites the lower nibble per deck from a 12-slot record
                 at $6A44, chosen by deckColorScheme ($F160)
BuildLevel       writes that byte to colour RAM; the VIC uses the low nibble
```

Only slot 5 is multicolour in every scheme and only slot 11 is hires in every scheme; the rest
vary, so **a character's mode genuinely changes between decks**. `tools/analyse_charmode.py`
dumps this; `tools/rip_deck_mixed.py` renders a deck the way the C64 displays it.

A multicolour character byte is four 2-bit pixel pairs, each two screen pixels wide:

| bits | source | in the artwork |
|---|---|---|
| `00` | `$D021` background | floor |
| `01` | `$D022` | |
| `10` | `$D023` | |
| `11` | colour RAM, per cell | |

**MODE 1 handles both modes**, because it has no attribute constraints: 4 colours freely per pixel
at 320 across. A hires cell converts to 8 MODE 1 pixels of background + one colour; a multicolour
cell converts to 4 doubled pixels using all four. Either way a character is **16 bytes**, so
`plot_char` is unchanged.

MODE 1 pixel *n* takes bit `7-n` as its high colour bit and bit `3-n` as its low.

**Logical colour assignment.** MODE 1's four colours are global, but the C64 draws on a 12-slot
per-deck palette. `export_bbc.py` counts how often each C64 colour is actually used across the
tile set and assigns logical 0 = background plus the three most-used; anything left over maps to
the nearest by luminance. For deck 1 that gives:

| logical | C64 | role | uses |
|---|---|---|---|
| 0 | light blue | floor | background |
| 1 | white | highlight | 272 |
| 2 | red | shadow | 220 |
| 3 | yellow | grid lines | 78 |

Three foregrounds is enough for deck 1. **This needs checking per deck** — a deck needing four or
more distinct foregrounds would lose one to the nearest-luminance fallback.

Two consequences worth carrying forward:
- **Per-deck recolour is free.** Colour is not baked into the tiles; a deck's scheme is a palette
  change (`VDU 19` / palette register), mirroring how the C64 recoloured via its `CharColor` table.
- **A character is 16 contiguous bytes** — BBC screen memory groups 4 px × 8 scanlines into 8
  consecutive bytes, so an 8×8 char is the left half's 8 scanlines then the right half's.
  Plotting one is a flat 16-byte copy, no shifting or masking. `plot_char` is 12 instructions.

*Known loss:* the C64 gives each cell its own colour from a 12-slot palette; MODE 1's four logical
colours are global. Deck 1 only needs three foregrounds so nothing is lost there, but decks needing
more will have colours merged.

**The charset is built at deck-load time** ✅, since a character's mode *and* colour both depend on
the deck scheme. Shipping 16 converted charsets would have cost 64K.

| shipped | size | |
|---|---|---|
| `chardata.asm` | 1489 B | C64 bitmaps, palette slots, code→index remap |
| `colours.asm` | 432 B | 8 scheme records, deck→scheme, per-deck colour maps |
| generated at runtime | 2192 B | the MODE 1 charset |

Two things keep this small. Only the **137 characters the tiles actually reference** are converted
(of 256, spanning `$00`–`$F0`), via a 256-byte remap table that `plot_char` indexes through — so
the charset is 2192 bytes rather than 4K. And the per-deck C64→logical colour maps are precomputed
offline, so the 6502 needs no search.

`BuildLUTs` builds eight 16-entry nibble→byte tables per deck — four hires, four multicolour.
**Both modes consume one source nibble per output byte** (hires: 4 pixels; multicolour: 2 pixels
each doubled), so the conversion inner loop is identical for both and only the table pointer
differs.

*Bug found by verification:* a few characters carry a palette slot ≥ 12, past the end of a 12-byte
scheme record. The 6502 was indexing into the *next* record while Python clamped to 0, giving 12
differing bytes in character `$16`. The C64 reads out of range here too — `clr0_top_d020` is 12
bytes and it indexes 14 — so the original's behaviour is incidental; both sides now clamp.

**`$D023` is 0 (black), not 6.** The only character-mode writes to `$D022`/`$D023` are in
`DrawSideview` (`$308A`/`$308F`), setting `$F1`/`$F0`; the other writes to that area are `+3`/`+4`/
`+$C`, which are the *sprite* multicolour registers. Having `$D023` wrong corrupted every
multicolour cell on every deck.

**`$D021` is still an assumption.** It comes from `bgColor`, which `SetIntroColors` loads from slot
3 of the deck record — but slot 3 does not match the lavender floor in `ref/start screen.png`, so
gameplay sets it somewhere not yet found. 14 (light blue) is taken from the screenshot. Marked
`[assumed]` in `export_bbc.py`; **re-derive before trusting deck colours.**

**Multicolour ALERT lettering is faithful, not a bug.** Row 0 of tile 22 (`$63`–`$66`) is the
lettering and sits on slot 7, which is multicolour under 8 of the 16 deck schemes — 4 pixels wide,
so the single-pixel letter gaps cannot exist and the letters join. The C64 does exactly the same;
`tools/compare_tile.py` renders a tile side by side, C64 against port, to settle such questions.
Decided to stay faithful for now rather than force those characters to hires.

**Physical colours must be assigned per deck, greedily.** A fixed C64→BBC table cannot work:
several C64 colours share a nearest BBC match, so two logical colours collapse onto one physical
and whatever is drawn in the second becomes invisible. Light blue (the floor) and blue (shadow
detail) both mapped to BBC blue, which silently erased detail on **12 of the 16 decks** — including
the ALERT panel's frame, which is what made the lettering look wrong. `assign_palette` now picks
nearest-*unused* per deck, with preferences honoured while free (floor → blue, grid → magenta,
shadow → black).

This is the second time a bug hid in the stage *after* conversion. The conversion was correct in
both cases; the damage happened in colour assignment.

**Verified:**
- `verify_bbc.py --charset <dump> <deck>` diffs the charset the BBC built against a Python
  conversion computed by a different route (direct, versus the 6502's lookup tables). Decks 1 and 2
  both match all 2192 bytes.
- `verify_bbc.py` asserts all 16 decks have four distinct physical colours, so the collision above
  cannot silently return.
- `tools/analyse_alert.py` checks per deck that the ALERT lettering stays hires and distinct from
  the background.

*Option not taken:* tiles could be stored in C64 form (2K instead of 4K) and expanded during the
blit. Worth revisiting only if the tile charset ever needs to compete for space with sprite data.

**Verified:** `verify_bbc.py` passes 5/5 — the charset round-trips to the original `$7800` bytes
*and* asserts every pixel pair is correctly doubled; tile defs, RLE, deck offsets and metadata all
byte-identical. `tools/rip_tiles_mc.py` renders the tile set as multicolour for direct comparison
against `ref/start screen.png`.

### Layer 2 — Static deck render ✅ DONE
`BuildLevel` RLE-decodes a deck into a tile map; `DrawScreen` renders the viewport from it.

**Divergence from the C64 — the map buffer.** The original expands every tile into a 256×64
*character* map at `$8000` (16K) and `DrawScreen` just copies characters from it to screen RAM.
We keep only the **64×16 tile map (1K)** and expand tiles to characters at draw time:

```
tile      = tilemap[(cy>>2)*64 + (cx>>2)]
character = tiledefs[tile*16 + (cy AND 3)*4 + (cx AND 3)]
```

Two extra lookups per character against a ~100-cycle 16-byte copy — roughly 25% more work when
drawing, for a **15K saving**. Not a close call on a Model B. Scrolling only redraws the leading
edge, so the overhead lands on a column of 25 characters, not the full screen.

**Memory layout — code and data must be split across two disc files.** `VDU 22` makes the OS clear
what it still believes is its screen, `&3000–&7FFF`. Anything loaded above `&3000` is wiped before
it can be read. So:

| File | Range | Contents |
|---|---|---|
| `PARA` | `&1900–&1ACE` | code |
| — | `&1C00–&1FFF` | tile map (reserved, built at runtime) |
| `PARADAT` | `&2000–&3F07` | charset, tile defs, level data — `*LOAD`ed *after* the mode change |

This bites again at every later layer that adds data. The eventual fix is to stop using `VDU 22`
and program the video ULA and CRTC directly, which we need anyway to keep the OS from clearing or
scrolling our screen.

**Verified:** `verify_bbc.py --tilemap <dump> <deck>` diffs a tile map dumped from the emulator
against a fresh Python RLE decode. Deck 1 (226 non-empty tiles) and deck 3 (498) both match all
1024 bytes, and both counts agree with `level_stats.txt`. Deck 3 was chosen deliberately — its RLE
lives at `&3393`, above `&3000`, so it exercises the clear-on-mode-change bug above.

*Note:* deck 1 masked that bug entirely. Its RLE sits at `&2DC0`, below `&3000`, so it rendered
identically before and after the fix. Screenshot comparison alone would not have caught it.

### Layer 3 — Scroll ← *the decision point*, split into chunks

#### 3a — Map browser ✅ DONE
Scroll the viewport by one character with Z/X/K/M; switch decks with UP/DOWN. Full-screen redraw
per step, no hardware scroll. Proves `DrawScreen` renders correctly from an arbitrary map origin,
which everything else depends on.

- `DrawScreen` generalised to a `(charX, charY)` origin. Map is 256 × 64 characters, viewport
  40 × 25, so the origin ranges 0–216 × 0–39.
- Row base is cheap because `tilemap` is page-aligned and 1K:
  `lo = (tileRow AND 3) << 6`, `hi = HI(tilemap) + (tileRow >> 2)`.
- Keys read with OSBYTE `&81`. Confirmed codes: Z `-98`, X `-67`, K `-71`, M `-102`,
  UP `-58`, DOWN `-42`. `*FX 4,1` stops the cursor keys doing cursor editing.
- Deck keys are **edge triggered**. A blocking wait-for-release deadlocks: hold UP before
  releasing DOWN and it spins forever, swallowing the press.
- Code moved to `&1100` (see memory budget) — 2K reclaimed.
- `CentreOnDeck` frames a deck on load. Decks sit at varying offsets in the 64×16 grid and are
  padded with empty tiles, so a (0,0) origin lands in blank space. Uses the **centroid** of
  non-empty tiles rather than the bounding box, because several decks are two clusters far apart
  and the midpoint of the extremes then falls in the gap. Division is by repeated subtraction —
  the quotient cannot exceed 63, and this runs once per deck change. Derived from the map itself,
  not the per-deck metadata tables, which hold side-view positions rather than map extents.

  *Honest limit:* on deck 0 the centroid lands within 2 characters of the bounding box, because
  its two clusters happen to balance near the same point. No single 40×25 viewport frames a
  34-tile-wide deck well; the centroid is kept because it degrades more gracefully — one outlying
  tile skews a bounding box badly and a centroid barely at all.

**Measured: a full-screen redraw costs ~466,000 cycles ≈ 11 frames** (30 scroll steps in 14M
cycles), so about 4 steps/second. `plot_char` dominates at ~256 cycles for its 16-byte copy;
unrolling the loop to drop `DEY`/`BPL` would take that to ~176. This is the number 3b has to beat.

#### 3b — Hardware scroll + edge redraw ✅ DONE

**Play area verified against the C64: 9.5 × 4 tiles.** `DrawScreen` writes to `$4940` — `$140` past
the `$4800` screen base, so character row 8 — and draws 17 rows × 39 columns. That includes the
C64's one-character fine-scroll margin, so the *visible* area is 38 × 16 chars = 304 × 128 px.

**Rounded up to 10 × 4 tiles = 320 × 128** (KC's suggestion), because 10240 bytes is exactly 16 rows
of 640 and the BBC supports a 10K wrap natively — System VIA addressable latch lines 4 and 5 both
high select subtract `&2800`, restart `&5800`. Both axes then wrap cleanly. Rounding up rather than
down also avoids narrowing the play area.

**The buffer is a circular strip, not a flat grid.** Display cell *(row, unit)* lives at
`BUF_BASE + ((scrollS + row*640 + unit*8) MOD 10240)`.

The BBC CRTC gives a *one-dimensional* scroll through linear memory: a character leaving the left
reappears one row up on the right. Drawn as a flat 2D grid that is corruption — verified in the
emulator, and it scales with the offset (at 80 px, the right quarter shows the wrong rows). Treated
as a circular strip it is simply where the next column legitimately lives, and the cost collapses:

| step | scrollS | cells to redraw |
|---|---|---|
| horizontal, 4 px | ± 8 | 16 |
| vertical, 8 px | ± 640 | 80 |

versus ~640 characters for a full redraw.

**A MODE 1 CRTC unit is one byte per scanline = 4 pixels, and characters are already stored as two
8-byte halves — so a 4-pixel column is exactly one stored half-character.** No pre-shifted data is
needed for sub-character horizontal scrolling, which was the thing that looked expensive.

Source split into `screen.asm` (buffer addressing, `DrawHalf`, `MapChar`, `RedrawAll`),
`scroll.asm` (the four scroll directions) and `level.asm` (deck decode, charset, palette, framing).

**VSYNC synced, no OS calls in the main loop.** R12/R13 form a 14-bit value across two writes; if
the CRTC samples between them the display shows one frame at a half-updated address. `WaitVSync` at
the top of the main loop puts both writes and the edge redraw in the blanking window, and paces
scrolling to one step per frame.

Two OS calls were replaced with direct hardware:

- **Palette** — writes `&FE21` instead of `VDU 19`. The register takes
  `(logical << 4) | (physical EOR 7)`, and the logical field is a content-addressable match: in a
  4-colour mode only bits 7 and 5 are compared, so bits 6 and 4 must be written in **every**
  combination or the colour comes out split. `SetPalette` writes all 16 entries, mapping each back
  with `logical = ((n AND 8) >> 2) OR ((n AND 2) >> 1)` — four entries per logical colour.
- **VSYNC** — `IrqHandler` sits at the head of `IRQ1V`, counts fields and chains on to the OS, so
  its timers and keyboard scan keep working. Polling `&FE4D` bit 1 directly would race the MOS,
  whose own handler clears that flag when it services vsync.

Verified: palette output identical to the `VDU 19` version, and horizontal scrolling still measures
exactly 10 steps in 10 frames.

*Still an OS call:* `keydown` uses OSBYTE `&81`, once per key per frame. Replacing it means driving
the System VIA keyboard matrix directly, which contends with the MOS's own scan in its IRQ handler
— worth doing alongside the eventual full IRQ takeover rather than piecemeal.

**Verified:** both axes scroll coherently with no shear or row-bleed. Step rate measured over 10
frames with the key held:

| | steps in 10 frames | cost |
|---|---|---|
| horizontal, 16 cells | **10** | 1 frame/step — vsync-locked |
| vertical, 80 cells | **4** | ~2.5 frames/step — overruns the frame |

**`SetCell` loop replaced with lookup tables** (`rowMulLo/Hi`, `unitMulLo/Hi`). It previously added
640 in a loop — for `DrawRow` a constant 15 iterations × 80 cells, ~1200 redundant 16-bit adds.

*Result: less than predicted.* Vertical went from 4 to **5 steps per 10 frames** (2.5 → 2.0
frames/step); horizontal unchanged at 10. So `SetCell` was **not** the dominant cost — that
diagnosis was wrong.

**Where the time actually goes.** `OSBYTE 19` quantises to whole frames, so a step costs 1 frame if
the work fits and 2 if it spills over by any amount. Vertical is sitting just above the boundary —
the remaining gap is small, and crossing it jumps straight from 5 to 10 steps.

The likely culprit is `MapChar`, which per cell recomputes the tile-map row base (shifts, adds, a
16-bit pointer build) and then the tile-definition pointer. For `DrawRow` `cellY` is *constant*, so
the row base is identical for all 80 cells and recomputed 80 times. Hoisting it — and the tile
pointer, which only changes every 4 cells — should get under one frame. Still deferred, but now
pointed at the right routine.

#### 3c — Decide the scroll model
Wide virtual buffer, CRTC R12/R13 hardware scroll, keyboard-driven. **Decide the scroll model here
and record it in this document.** Everything downstream depends on the map buffer layout.

Horizontal granularity is **4 pixels**, not 8. CRTC R12/R13 addresses in 8-byte units, and a MODE 1
character cell is 16 bytes (8 px × 2bpp = 2 bytes/row × 8 rows), so one CRTC increment is half a
cell:

| Mode | bytes/char cell | 1 CRTC unit |
|---|---|---|
| MODE 0 | 8 | 8 px |
| MODE 1 | 16 | **4 px** |
| MODE 2 | 32 | 2 px |

4 px = 1/80 of screen width, and exactly 2 logical C64 multicolour sprite pixels. This may be smooth
enough unaided — that is what the spike measures.

To compare:
- 4-px horizontal (CRTC only) vs. 1-scanline vertical (R4/R5/R12 trick) vs. flip-screen.

**Parked option — 2-px horizontal, Master only.** Keep a second 16K buffer in shadow RAM holding a
copy of the map offset by 2 px, and alternate which buffer is displayed to halve the granularity.
Significant added complexity, and a Model B has no room for the second buffer — revisit only if the
target moves back to the Master.

### Layer 4 — Sprite blitter
MODE 1 software sprites, 24×21, background save/restore, pre-shifted variants. One player droid
drawn over the scrolling map. **Proves:** the frame budget. Measure cycles; this is where the port
either performs or doesn't.

### Layer 5 — Player movement
Port `GetNewDir`, `CalcSpeed`, `SpriteHitWall`, rotation animation tables. Player walks the deck
and is stopped by walls.

### Layer 6 — Droids
`RunDroids`, `dMd0_droid`, sprite slot allocation, pathfinding. Droids move and chase.

### Layer 7 — Combat
`dMd1_bullet`, `dMd2_explosion`, `DoCollision`/`DoCollision2`, `DoScore`, `KillDroid`,
`DoAlertAndAging`. The core game is playable at this point.

### Layer 8 — Doors, lifts, decks
`OpenDoor`, `CloseDoors`, `DoLift`, `FindLift`, `ChangeDeck`. The whole ship becomes traversable.

### Layer 9 — HUD and console
Status bar via the mid-frame split, `Console`, `con_DroidInfo`, `con_DeckInfo`, `con_ShipInfo`,
side view.

### Layer 10 — Transfer minigame
`SubGameSelectSide` and the circuit puzzle. Paged from SWRAM bank 1.

### Layer 11 — Sound, title, polish
SN76489 driver replacing the SID engine, title screen, attract mode.

## Fate of the existing `src/`

| File | Fate |
|---|---|
| `zeropage.asm` | Keep, rework for the ~150-byte Model B ZP budget |
| `hardware.asm` | Keep, strip Master-only registers (ACCCON, shadow RAM) |
| `macros.asm` | Keep `CRTC_WRITE`, `SN_WRITE`; drop `ACCCON_*` |
| `main.asm` | Rewrite — assumes Master, MODE 2, shadow double-buffering |
| `hal_video.asm` | Retire — MODE 2 CRTC arithmetic, unverified, carries `TODO`s |
| `hal_irq.asm` | Retire — assumes Master shadow RAM and a HAL structure we're not building |
