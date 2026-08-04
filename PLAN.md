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

The C64 map graphics are 1bpp hires line art at the full 320px width (see `tools/output/tiles.png`),
and the sprites are multicolour with 2-screen-pixel-wide logical pixels. MODE 1 maps both 1:1:

| | C64 | MODE 1 |
|---|---|---|
| Map character | 8×8 px, 1bpp | 8×8 px, 1:1 |
| Tile (4×4 chars) | 32×32 px | 32×32 px, 1:1 |
| Multicolour sprite pixel | 2 screen px | exactly 2 px |
| Display | 320×200 | 320×200 |

Consequence: tiles, sprites, title screen and transfer board all convert **mechanically** from the
ripped C64 data. No artwork is redrawn. The cost is a 4-colour budget where 5 are wanted
(background + map colour + 3 sprite tones); resolved by sharing the map colour with a sprite tone,
or by reprogramming the palette at the HUD split.

MODE 2 was rejected: 8 colours the game barely uses, in exchange for redrawing every tile at half
width and breaking the 32×32 tile aspect ratio.

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

**Key result — the 1bpp→MODE 1 conversion is a nibble split.** MODE 1 puts pixel *n*'s low colour
bit in bit `3-n`, so storing the foreground as **logical colour 1** makes the conversion:

```
left  4 pixels of a scanline = (b >> 4) & 0x0F
right 4 pixels of a scanline =  b       & 0x0F
```

Two consequences worth carrying forward:
- **Per-deck recolour is free.** Colour is not baked into the tiles; a deck's scheme is a palette
  change (`VDU 19` / palette register), mirroring how the C64 recoloured via its `CharColor` table.
- **A character is 16 contiguous bytes** — BBC screen memory groups 4 px × 8 scanlines into 8
  consecutive bytes, so an 8×8 char is the left half's 8 scanlines then the right half's.
  Plotting one is a flat 16-byte copy, no shifting or masking. `plot_char` is 12 instructions.

*Option not taken:* since the conversion is a nibble split, tiles could be stored in C64 1bpp form
(2K instead of 4K) and expanded during the blit. Worth revisiting only if the tile charset ever
needs to compete for space with sprite data.

**Verified:** `verify_bbc.py` passes 5/5 — charset round-trips to the original `$7800` bytes with
no high nibble ever set; tile defs, RLE, deck offsets and metadata all byte-identical.

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

#### 3b — Hardware scroll + edge redraw
CRTC R12/R13 for the 4-px horizontal step, and redraw only the leading column/row as it comes into
view — 25 characters instead of 1000, ~8,500 cycles, a fifth of a frame. Needs the map buffer to be
wider than the viewport so there is somewhere to draw into.

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
