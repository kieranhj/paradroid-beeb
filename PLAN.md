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

**The main loop is released when the play area stops displaying, not at VSync.** The play area
occupies frame rows 8–23; the panel draws from `&4800`, so writing the play buffer while it shows
is safe. That makes the usable window rows 24 → 8 of the next frame — **24 rows**, against ~23 for
a worst-case redraw. Releasing at VSync (row 34) gave only 13 and was overrunning every step.

T1's three fires must land in different windows, which one period cannot do:

| Fire | Row | Job | Must be in |
|---|---|---|---|
| 1 | 3 | cycle 1 CRTC setup | rows 0–7 |
| 2 | 11 | cycle 2 CRTC setup | rows 8–15 |
| 3 | 24 | release the redraw | rows 24–26 |

So the latch is rewritten during fire 1. T1 reloads its counter at underflow, so a latch write
takes effect one reload later — fire 2 keeps the 8-row spacing while fire 3 moves out to 13.

**`SetCRTCStart` is called once, after all key handling, before any drawing.** Previously each
`Scroll*` routine parked the address itself, so on a diagonal the second one's park landed after
the first one's redraw — past frame row 3, where the IRQ latches R12/R13. The CRTC then used an
address missing one axis while the buffer held the combined position: one frame of wrong graphics
on the trailing edge. The routines now only set flags, and `DoRedraws` handles the drawing.

**Redraws run in raster order** — row 0 first (displays at frame row 8), then the columns (rows
8–23), then row 15 (row 23). A diagonal does two redraws in one window, so the tightest goes first.

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

#### Vertical scroll optimisation ✅ — both axes now frame-locked

Two changes, and the first was much less useful than predicted:

**1. `SetCell` loop → lookup tables** (`rowMulLo/Hi`, `unitMulLo/Hi`). It previously added 640 in a
loop: for `DrawRow` a constant 15 iterations × 80 cells, ~1200 redundant 16-bit adds. Vertical went
4 → **5** steps per 10 frames. Real, but small — `SetCell` was *not* the dominant cost, so that
diagnosis was wrong.

**2. `DrawRow` rewritten to hoist per-row constants.** `cellY` does not change across a row, so the
tile-map row base and sub-row offset are fixed; the tile pointer only moves every 4 characters; and
crucially **the character code is fetched once per pair of units**, because a character is two
4-pixel halves — 40 lookups instead of 80, with the right half just `chp + 8`. `DrawRow` no longer
calls `DrawHalf`/`MapChar` at all, and reuses their zero page. Vertical went 5 → **10**.

| | steps in 10 frames | |
|---|---|---|
| horizontal, 16 cells | 10 | unchanged |
| vertical, 80 cells | **10** | was 4 |

**The lesson worth keeping:** because vsync quantises to whole frames, a step costs 1 frame or 2
with nothing between. Vertical was never 2× too slow — it was a few thousand cycles over the line,
which is why the small first fix moved nothing and the second moved everything.

#### ~~⚠ KNOWN DEFECT — `DrawRow` corrupts the row it draws~~ — MOOT, routine deleted in 3d

**Broader than first recorded.** It was characterised as "unit 39 onward, after an *odd* offset".
Both halves of that are wrong: a diagonal-scroll diff found it corrupting **units 2–78 with
`mapHX` = 134, an even offset**. Every column and every other row matched a full redraw exactly, so
`DrawRow` alone is at fault — verified against `RedrawAll` *and* independently against the tile map.

Diagonal movement calls `DrawRow` on every step, which turns an occasional artifact into a
permanent one on the trailing edge.

**`DrawRow` has now produced three separate bugs**: uninitialised `chp` on odd row starts (fixed),
corruption from unit 39, and this. Each time the conversion looked right and the fault was in its
incremental state tracking.

**Recommended fix: revert `DrawRow` to the pre-optimisation version.** That one diffed byte-clean
twice. The cost was vertical scrolling at 2 frames/step rather than 1 — but the draw window has
roughly doubled since that measurement (release moved from VSync to frame row 24), so it may now
fit at 1 frame regardless. If the optimisation is redone, drive the diff harness over odd *and*
even offsets on both axes from the outset.

**Testing lesson.** Two earlier runs of that harness reported 0 differing bytes and were worthless:
both used an even number of horizontal steps (30 and 300), so `halfSel` was always 0 and the odd
path never executed. The harness was sound; the inputs never reached the failing case. Any future
scroll test must cover odd and even offsets on both axes.

#### Bug: corrupted graphics that scrolling revealed but did not cause

`DrawHalf` computed `halfX >> 1` by shifting `halfX+1` in place and "restoring" it with `ASL`.
`LSR` then `ASL` only restores a value whose low bit was 0, so whenever `halfX+1` was 1 it came
back as 0.

`DrawColumn` recomputes `halfX` from `mapHX + uCount` every cell and was immune. Only `RedrawAll`,
which sets `halfX` once and increments it across the row, was affected — so the damage was written
**at deck load** and then persisted indefinitely, because incremental scrolling only redraws the
edges and never repairs the interior. Scrolling exposed it rather than caused it.

Triggers when `mapHX + 79` crosses 256 — **decks 2 and 14**, both centring at `mapHX` = 180.

*Diagnostic worth keeping:* a debug key (SPACE) forces `RedrawAll`, so the incremental buffer can be
diffed against a full redraw at the same position. Both then matched byte-for-byte — after
right/down/left, and after scrolling to the extremes with the buffer wrapping repeatedly — which
proved the scroll logic correct and pointed at the load-time draw instead.

*Not a bug:* the large flat areas on some decks are genuine. Empty tiles (index 0) are all
character 0, which renders as solid background. Verified against the tile map.

`DrawColumn` still uses the general `DrawHalf`/`MapChar` path. It only touches 16 cells and already
fits in a frame, so it was left alone — but the same hoisting applies if the sprite blitter later
squeezes the budget (`halfX` is constant down a column, so the character and tile lookups are
constant too; only the row base changes).

#### 3c — Vertical rupture: static panel + scrolled play area ✅ DONE

Two CRTC cycles per TV frame. Reprogramming R4 mid-frame ends a cycle early; the next cycle
reloads VMA from R12/R13, so each cycle has its own screen start.

| Cycle | Content | R4 | Rows | R6 | R7 | R12/R13 |
|---|---|---|---|---|---|---|
| 1 | static panel | 7 | 8 | 5 | 255 (suppressed) | `&4800 / 8` |
| 2 | scrolled play area | 30 | 31 | 16 | 26 | `(&5800 + scrollS) / 8` |
| | | | **39 ✓** | | | |

Cycle 1 shows 5 rows of panel then 3 blank — the same title-plus-gap the C64 has above its play
area. `Σ(R4+1)` must total 39 rows / 312 scanlines or the picture rolls.

**Consistency check:** VSync lands at frame row `8 + 26 = 34`, which is MODE 1's default R7, so the
TV sees an identically phased frame and stays locked.

**Staging: System VIA T1 in CONTINUOUS mode, and we own IRQ1V outright.**

T2 was the wrong timer. It is one-shot only, so the interval starts when the handler writes
`T2C-H` — every interrupt's service latency feeds straight into the next interval and jitter
accumulates. T1 continuous auto-reloads from its latch at underflow, so the period is exact
however late we are serviced. VSync restarts it, keeping the stages phase-locked to the frame.

Nothing is chained on to the MOS either, so its handler never runs ahead of ours adding latency.
The cost is the MOS 100 Hz tick, and with it MOS sound. Keyboard still works (OSBYTE `&81` scans
the matrix directly) and the filing system is only needed before we take over — hence `*LOAD` now
runs *before* `InstallIrq`.

Both VIAs have every interrupt source disabled except System VIA CA1 and T1; anything unserviced
would hold the IRQ line asserted forever. The MOS saves the interrupted A in `&FC` but not X or Y,
so the handler saves those itself.

One period = 8 char rows, giving a three-state machine on the IRQ:

1. **VSync (CA1)** — inside cycle 2, five rows from its end. Latch R12/R13 = panel. Arm T2 for
   2560 ticks.
2. **T2, inside cycle 1** — set R4/R6/R7 for the panel, queue R12/R13 = play area. Arm T2 for
   4096 ticks.
3. **T2, inside cycle 2** — set R4/R6/R7 for the play area. Wait for VSync.

Timing is generous: the interrupt only has to land inside its cycle before `C4` reaches the target
R4. (The `C0<2` write window quoted for R4 applies to single-scanline RVI work, not here — KC.)

**Both waits deliberately overshoot the boundary by 3 rows.** Sizing them to reach the boundary
exactly is what glitched: IRQ latency alone carried them over, so any jitter fired them in the
*previous* cycle, where writing that cycle's R4 breaks the field. Overshooting costs nothing — the
deadline is `C4` reaching the old R4 (7), so arriving 3 rows in leaves ~4 rows of slack either side.

**`DEBUG_RASTER` build flag** tints the background at entry to each interrupt — magenta at VSync,
green at cycle 1, the deck's real colour at cycle 2 — so the scanline each one lands on is visible
and the band boundaries *are* the interrupt points. This is what diagnosed the margin problem;
reasoning about it from the timing numbers had led me the wrong way. Set `FALSE` for a clean
picture.

`SetCRTCStart` no longer writes R12/R13; it computes the address and parks it for the IRQ, with
`SEI` around the store so the IRQ can't read a half-updated pair.

**Interlace must be off — `R8 = 0`.** The OS leaves MODE 1 at `R8 = 1`, *interlace sync*, which
offsets VSync by half a scanline on alternate fields. The rupture timers are fixed intervals from
VSync, so that half line lands the split in a different place every other field — an intermittent
glitch along the top of the play area. Non-interlaced is what a game wants anyway.

**Verified:** panel holds position exactly while the play area scrolls on both axes, and
consecutive fields render identically with interlace off.

*Placeholder:* the panel is a bordered box, not artwork. Real title/HUD content is a later layer.

*Known limitation:* the panel shares the play area's 4-colour palette, so its colours change with
the deck. Fixable by reprogramming the palette at the cycle boundary — we are already in the IRQ
there — but that needs the panel's colour needs settled first.

#### Scroll model — decided (reference)

Wide virtual buffer, CRTC R12/R13 hardware scroll. Horizontal granularity is **4 pixels**, not 8. CRTC R12/R13 addresses in 8-byte units, and a MODE 1
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

#### 3d — Smooth vertical scroll, 1-scanline granularity ✅ DONE

Vertical steps drop from 8 scanlines to 1. Reference: `llm-beeb-wiki`
`techniques/smooth-vertical-scroll` and its source, Talbot-Watkins's retrosoftware tutorial.

**The lever is R5 (vertical total adjust).** R5 appends 0–31 extra scanlines to the end of a CRTC
cycle. Give the playfield cycle `R5 = line` and take those scanlines back from the cycle above it
(`8 - line`), and the frame total stays at 312 so the TV never unlocks. The playfield cycle then
*starts* `line` scanlines earlier, so at any fixed physical scanline the raster is `line` lines
further into the buffer — the picture has scrolled down by `line`.

Two consequences fall straight out of that, and they are the whole cost of the technique:

- **The first `line` scanlines of the playfield cycle are real, displayed, and wrong** — as is the
  tail. Both must be blanked, and it is the blanking, not R5, that pins the visible edges to fixed
  scanlines. Blank via **CRTC R8's display-skew bits** (`&30` = display disabled, `&00` = on): the
  chip's own display enable, so there is no ULA serialiser artefact at the transition.
- **The playfield needs 17 rows of data resident and we have 16.**

##### The 17th row, and why it costs nothing

`BUF_SIZE` = the 10K hardware wrap is load-bearing — that equality is what makes the display wrap.
It cannot grow: the only other wrap span divisible by 640 is 20K, which would swallow `&3000-&47FF`
where the level data and panel live.

We do not need a 17th row. Display row 16 wraps to buffer row 0, and the two only ever show
**disjoint scanlines** of it, so buffer row 0 holds two map rows at once:

| buffer row 0 | holds |
|---|---|
| scanlines `line..7` | map row `mapYr` — the top of the view |
| scanlines `0..line-1` | map row `mapYr+16` — the bottom sliver |

Work a step through and it collapses to something uniform, with no special case where the buffer
wraps a row:

| | action |
|---|---|
| down 1 scanline | write scanline `line` of buffer row 0 from map row `mapYr+16`, *then* advance `line`/`mapYr`/`scrollS` |
| up 1 scanline | retreat `line`/`mapYr`/`scrollS`, *then* write scanline `line` of buffer row 0 from map row `mapYr` |

When `line` wraps and `scrollS` moves a row, the row that was split becomes a full row — and the 7
scanlines it needs are already correct. The one scanline just written completes it.

**A scanline strip is 80 bytes against 640 for `DrawRow`.** Per 8 scanlines travelled that is the
same copying, spread evenly instead of lumped into one frame — the opposite of the current problem,
where a vertical step is the worst spike in the frame.

##### Frame layout — three cycles, not two

Two cycles would leave the variable adjust between VSync and the panel, sliding the panel up to 7
scanlines while scrolling. Three cycles put both variable adjusts *after* the panel, where they
cancel:

| Cycle | Content | rows (R4) | R6 | R7 | R5 | R12/R13 |
|---|---|---|---|---|---|---|
| panel | static | 7 (6) | 5 | 255 | `8 - line` | `&4800 / 8` |
| play | scrolled | 18 (17) | **16** | 255 | `line` | `(&5800 + scrollS) / 8` |
| tail | nothing, holds VSync | 13 (12) | 0 | 8 | 0 | — |
| | | **38 ✓** | | | **+8 ✓** | |

`38 × 8 + 8 = 312`, confirmed by counting VSyncs: **1000 fields in 39,936,000 cycles, exactly.**
With `P` = start of the panel cycle: the play cycle starts at `P+64-line`, the visible top edge is at
`P+64` and the bottom at `P+184`, and VSync lands at `P+272`.

**18 cycle rows rather than 17 is deliberate.** It makes row 16 non-displayed, so display-enable
turns off by ordinary means and we never depend on the murky "R6 > R4" behaviour where the VADJ
scanlines themselves are displayed.

##### The play area is 15 rows, not 16 — and that is a hard limit

`R6 = 17` was the original design: 16 rows plus the wrapped sliver. It cannot work, and the reason is
worth keeping.

**The display window must fit inside ONE hardware wrap.** The address translator subtracts its
mode-dependent amount once, when MA12 goes high (IC 39, see `hardware/address-translation`) — it
does not iterate. 17 rows is 10880 bytes over a 10240-byte wrap span, so past `scrollS = 9608` the
bottom rows need a second subtract, do not get one, and fetch from `&8000` upwards. ROM, displayed
as garbage across the bottom row — and only at some scroll positions, which is why it read as
intermittent.

Confirmed exactly: at `scrollS = 10200` the model predicts garbage from unit 5 of the bottom row
onward, and that is where it starts.

The strip period must equal the wrap span, and 10240 bytes with 80-unit rows is exactly 16 rows. So
**16 displayed rows is the ceiling, and smooth vertical scrolling costs one character row of play
area**: 16 displayed, 15 visible (120 px), the 16th carrying the sub-row fraction at both ends.
Nothing else changes — the split-row scheme is untouched, because the scanlines it writes are
precisely the ones falling outside the visible window.

*Parked ways to get 128 px back, neither cheap:* the 20K wrap (`&3000`, 32 rows) has room for a
17-row window, but the whole of `&3000-&7FFF` becomes screen and the strip sweeps the panel; or
switch the addressable-latch wrap bits per cycle in the IRQ, which is feasible — we are already in
there four times a frame — but needs thought about where the panel then lives.

##### R5 write ordering

R5 is sampled at each cycle's *end*, so it must read a different value at three points in the frame.
Each write has to land in the gap between the sample it must not disturb and the one it serves:

| must read | at | so write it |
|---|---|---|
| `0` | `P+312` (tail end) | at VSync, `P+272` |
| `8 - line` | `P+56` (panel end) | at fire 1, `P+44` |
| `line` | `P+200` (play end) | at fire 2, `P+64` |

R4/R6/R7 are **not** latched, so each cycle's values must be written *inside* that cycle, after it
starts and before `C4` reaches the new R4. That is why the tail cycle's own registers are written at
VSync (tail row 8) rather than earlier.

##### IRQ schedule

| Event | Position | Actions | Tolerance |
|---|---|---|---|
| VSync (CA1) | `P+272` | R8←on; R5←0; tail R4/R6/R7; R12/R13←panel; `iline←line`; restart T1 | ~40 rows |
| T1 fire 1 | `P+44` | R8←blank; R5←`8-iline`; panel R4/R6/R7; R12/R13←play | 8 scanlines |
| T1 fire 2 | `P+64` | R8←on; R5←`iline`; play R4/R6/R7 | **1 scanline** |
| T1 fire 3 | `P+192` | R8←blank; `drawFlag`←1 | **1 scanline** |

T1 stays free-running continuous and is restarted only at VSync, so the three fires share one
jitter offset rather than accumulating three. Intervals are set by writing the latch one fire ahead,
as in Layer 3c.

Fires 2 and 3 must land in **horizontal blanking** — MODE 1 displays 80 of 128 character times, so
there are ~24 µs of blanking to hit and a write landing in the displayed portion cuts that scanline
part-way across. `T1_TUNE` exists to be calibrated against `DEBUG_RASTER`, exactly as the reference
implementation carries an empirically tuned constant for the same reason.

Nice side effect: `drawFlag` now fires at `P+192`, the exact scanline the play area stops
displaying, rather than the row-24 estimate — 15 rows of draw window, and no longer a guess.

##### When each CRTC register may be written — they are not the same

This cost two wrong builds. The rules that actually hold:

| Register | Write it | Symptom of getting it wrong |
|---|---|---|
| R4 | inside its own cycle, before C4 reaches the new value | previous cycle trips over it |
| R7 | inside the **previous** cycle | that row's compare has already happened, **VSync never fires**, and the CRTC free-runs on the last cycle shape — the play area repeats down a rolling screen |
| R6 | inside the **previous** cycle | vertical display enable is a flip-flop cleared on match; raising R6 afterwards does not bring the cycle's display back |
| R12/R13 | inside the **previous** cycle | latched at cycle start |
| R5 | anywhere before the cycle's end — but see below | |

**The R5 trap, and it is a nasty one.** The vertical adjust counts up and compares against R5.
Change R5 once the count has passed the new value and the match never happens: the adjust runs on
until the 5-bit counter wraps, adding ~29 scanlines. Fire 2 sits within a scanline of the panel
cycle's adjust ending, and landing the wrong side of that boundary stretched the panel cycle from 64
scanlines to 85 — which presented as the play area starting 21 scanlines late and being 21 short.

The fix is not tighter timing, it is **not writing R5 anywhere near a cycle boundary**. Its legal
window is the whole cycle, so the play cycle's R5 moved to fire 3 and fire 2 now writes only R4 —
which is safe on both sides of the boundary, because written during an adjust it simply waits for
the next cycle.

##### Calibration — `T1_TUNE = -6 * SL - 22`

Two components, measured separately.

**The scanline part, `-4 * SL`.** The VSync CA1 interrupt is serviced about **4 scanlines** after the
vsync edge, so every fire needs shifting back by that much. The timer chain itself is exact —
breakpoint bisection puts fire 1 at 78.3–79.3 scanlines after VSync handler entry against a design
figure of 78 — so the whole error is in where VSync itself sits.

This started at `-6`, which put fire 2's unblank at `P+62` instead of `P+64` and exposed two
scanlines of the *next* map row above the top of the view. **Erring late is harmless** — it just
starts the view a couple of scanlines further down the map — **but erring early shows content that
belongs at the bottom of the window at the top of it.** Bias late if in doubt.

Note the scanline component cannot be measured from screenshots to better than ±2: one scanline is
2 framebuffer pixels and the panel gives only ~2.0–2.05 px/scanline depending on how its edges are
read. It was KC spotting two wrong lines on b-em that pinned it, not any measurement here.

**The sub-scanline part, `-22` µs.** An R8 write takes effect immediately, so one landing in the
displayed part of a scanline cuts that scanline part-way across. MODE 1 displays 80 of 128 character
times, so the write has to land in µs 40–63 of the line before the one whose display should change.

Measuring the phase needed a trick, because the play area's edges cannot show it — one scanline is
2 framebuffer pixels, and jsbeeb crops each screenshot to its own content bounding box so builds are
not even to the same scale. **`T1_PROBE`** drags fire 1 back into the panel's *displayed* rows and
hands the time straight to fire 2, so fires 2 and 3 stay put and only the blank moves. The blank
then cuts the solid panel box, and the horizontal position of the step is the phase, read straight
off a screenshot: the step sat at 9 µs into the 40 µs of display. `-22` µs puts fire 1's write at
µs 51, fire 2 at ~53 and fire 3 at ~55 — they differ by the length of `RuptTimer`'s dispatch, which
is well inside the 24 µs window. The probe then shows a clean full-width cut, which is the
confirmation.

Keep `T1_PROBE` — it is the only phase measurement that has worked, and any change to the IRQ
prologue will need it again.

##### Build order

Each step verified in the emulator before the next:

- **(b)** three-cycle rupture, `line` fixed at 0 — measured panel 40 scanlines, gap 24, play area
  128: identical to Layer 3c ✅
- **(c)** `line` swept 0–7 by poking the variable from the emulator — no debug keys needed. Content
  moves one scanline per step, both edges rock steady ✅
- **(d)** split-row scanline writer wired to K/M ✅

Step (a) — proving the R8 skew blank standalone — was skipped on KC's call. It would not have caught
either bug: R8 behaved exactly as documented, and both faults were in R5/R6/R7 timing.

##### Verified

Buffer diffed byte-for-byte against `RedrawAll` at the same position, which is the only check that
has ever caught a drawing bug in this project:

| test | result |
|---|---|
| 8 steps down, even `mapHX` | 0 / 10240 differing |
| 8 steps up (through the row borrow), even `mapHX` | 0 / 10240 |
| mixed right / up / down, **odd** `mapHX`, `scrollS` wrapped mid-row | 0 / 10240 |
| as above, re-run after deferring the draw (exercises the down-wrap `scanRow`) | 0 / 10240 |

Step rate measured at **1 scanline per frame**, vsync-locked, on both axes.

*Testing trap worth remembering:* an earlier run of this harness reported 16 differing bytes, all on
one scanline of the split row. That was not a bug — `run_for_cycles` had stopped the emulator
mid-`DrawScanline` and the snapshot caught a half-written strip. Always idle a few frames after
releasing a key before dumping.

##### The position pair must be latched atomically — and drawn after, not before

Reported by KC: scrolling **up**, the screen jumped a row for one frame every 8 scanlines; scrolling
**down**, a couple of wrong lines showed at the top. One root cause, and the asymmetry is the clue.

The scroll routines drew their scanline strip *inline*, before `SetCRTCStart` parked the address.
The strip costs ~75 scanlines, which pushed the park past VSync — where `iline` was being latched.
`line` and `scrollS` are one position between them, and they were being consumed by different
frames: the display would show an address from one frame with a sub-row offset from the next, a
position that never existed.

`ScrollUp` changes both *before* its draw, so at every row borrow the pair split — a one-frame row
jump. `ScrollDown` changes them *after*, so only the freshly written scanline was exposed at the top.
Same bug, two faces.

Two fixes, both worth having:

- **The scanline draw is deferred to `DoRedraws`**, like the columns, so the park happens first. This
  also removes a subtler artefact: drawing before the park writes content for the *next* frame's
  position into a scanline the *current* frame still displays.
- **`SetCRTCStart` parks `line` alongside `crtcHi`/`crtcLo` under the same `SEI`**, and fire 1 latches
  `iline` from that park rather than VSync reading the live value. The pair is now consumed at one
  instant, so a long frame can only ever be a frame late — never inconsistent.

Deferring meant K and M could both record into one draw slot, with a scanline number belonging to a
strip position that no longer exists, so **up and down are now mutually exclusive** in the main loop.
Net movement with both held is zero anyway.

##### `DrawRow` is gone, and with it its defect

Vertical scrolling no longer redraws whole rows, so `DrawRow`, `FetchChar` and `SetTilePtr` have
been deleted. The defect recorded above — three separate bugs in that one routine's incremental
state tracking — is moot rather than fixed. `DrawColumn` still uses the general
`DrawHalf`/`MapChar` path and is unaffected.

##### Open questions

- **Granularity.** 1 scanline vertical against 4 pixels horizontal is a lopsided pair. Stepping
  vertical by 2 or 4 scanlines costs nothing extra (identical machinery) and may feel better.
- **Source-pointer cache.** A scanline strip still does 40 character lookups for 80 bytes copied, so
  lookups dominate. Caching the current source row's 40 pointers (80 bytes, rebuilt every 8
  scanlines) makes a strip a straight indexed copy. That is the difference between smooth scrolling
  costing *less* than today's row draw and costing ~2.5× more at full speed.

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
