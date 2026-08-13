# Paradroid → BBC Micro Model B: Port Plan

Living document. Revised as each layer lands.

## Where we are — read this first

**Layers 0–4 are done.** The port boots to a playable deck: a static panel above a 320 × 120 play
area, the player droid near the centre with its rotor spinning, and the deck hardware-scrolling 8
ways underneath it — 4 px horizontally, 1 scanline vertically — driven by the C64's own acceleration
model and stopped by walls. The camera has a dead zone, so at low speed the world holds still and
the droid glides at 2 px instead of the world lurching at 4. Frame-locked at 50 Hz in every
direction including full diagonal. 16 decks, per-deck palette and charset built at load time. Keys: Z/X left/right, K/M
up/down, cursor up/down change deck, SPACE forces a full redraw.

**Next up: Layer 5, droids** — the same movement model applied to non-player droids, plus
pathfinding and sprite slot allocation. There is ~10,000 cycles of identified but unclaimed
optimisation listed at the end of Layer 4; spend it when droids start competing for the frame.

The level draw was measured and rewritten on 2026-08-13, in four steps: the band brings in **whole
character rows** on the pass that crosses into them rather than the scanlines a move exposed; the
copy that fills a cell was unrolled once its run length became constant; the `charRemap` unpack
became a precomputed table; and a character's two halves became one 16-byte run. Full-diagonal
redraw went 38,472 → **20,482** cycles a pass and vertical 28,527 → **12,225**, and the split row
stopped existing on the way. More than half a character's cost is now the pixel copy itself. See
*The level draw* under Layer 4's frame budget, which also lists what is left.

**Before trusting any speed number, read the speed model section of Layer 4.** The C64's constants
are per `GameLoop` iteration and an iteration is 2–3 frames, not 1. Every droid speed in
`PlayerSpeed_t` needs the same conversion, so this will come up again immediately in Layer 5.

Three things anything drawing into the play buffer has to know:

1. **Display row *r* holds map row `mapYr + r`, all eight scanlines.** That is the strip's
   invariant and it is now unconditional — there is no split row. It used to be one: display row 0
   aliased map rows `mapYr` and `mapYr+16` in disjoint scanline ranges, and everything writing a
   whole cell into it needed a repair pass. That went with the whole-row band; see *The level draw*
   below. Anything new drawing into the buffer inherits the simple rule.
2. **Adjacent 4-pixel columns are 8 bytes apart, not 1.** Consecutive bytes within a column are
   consecutive scanlines. This cost a build.
3. **The draw window is frame rows 23 → 8 of the next frame**, released by `drawFlag` at `P+184`
   when the play area stops displaying. Everything shares it. `DEBUG_DRAW` tints it: magenta the
   sprites, yellow the level draw, cyan everything else.

**Verification that actually works here:** diff the play buffer against `RedrawAll` at the same
position (SPACE), byte for byte. Screenshots have repeatedly said "fine" when it was not. Drive it
over **odd and even** `mapHX`, **non-zero `line`**, and **diagonals** — every scrolling bug so far
has hidden in one of those. Allow ~1,500,000 cycles to settle before dumping, or the oracle is
sampled mid-redraw.

**Open items, in the order they are likely to bite:**

| | |
|---|---|
| 1 px sprite positioning | Needs four shifted copies, 1820 bytes — waiting on `PARADAT` moving to sideways RAM. 2 px matches the C64 artwork's own pixel size. |
| 2 px world scrolling | Parked, Master-only via shadow RAM. Feasible and cheap to switch; costs +60–80% on all drawing because both buffers must stay current. See **Master-only extensions**. |
| Play area is 320 × 120, not 128 | Consequence of the single hardware wrap — see Layer 3d. Getting the row back needs the 20K wrap or per-cycle wrap bits. **KC's call.** |
| Vertical granularity | 1 scanline against 4 px horizontal is lopsided. 2 or 4 scanlines costs nothing extra. Decide when there is a droid to move. |
| `$D021` is an assumption | Marked `[assumed]` in `export_bbc.py`. First suspect if deck colours look wrong on hardware. |
| Panel shares the play palette | Its colours change with the deck. Fixable at the cycle boundary — we are already in the IRQ there. Layer 9. |
| `keydown` uses OSBYTE `&81` | The last OS call in the main loop. |
| 8 decks draw ALERT in multicolour | Confirmed faithful to the C64 original, not a bug. Worth a look on real hardware. |

## Decisions taken

| Decision | Choice | Date |
|---|---|---|
| Target machine | BBC Model B / B+ with **2 × 16K sideways RAM banks** | 2026-08-04 |
| Screen mode | MODE 1, 4 colours, **10K wrap at `&5800–&7FFF`** | 2026-08-04 |
| Screen layout | 3-cycle vertical rupture: 5-row panel at `&4800`, 3-row gap, scrolled play area | 2026-08-05 |
| Play area | **320 × 120** — 10 tiles wide, 15 character rows. See Layer 3d for why not 128. | 2026-08-05 |
| Scrolling | CRTC hardware scroll over a circular strip. **4 px horizontal, 1 scanline vertical.** | 2026-08-05 |
| Interrupts | We own IRQ1V outright, System VIA T1 continuous. No MOS chaining, no MOS sound. | 2026-08-04 |
| Architecture | No HAL. Build one working layer at a time, verified in the emulator before moving on. | 2026-08-04 |
| Source version | **1985 original / 1986 Competition Edition** lineage — which is what `paradroid_ce.lst` already is. Redux's bug list adopted as a spec, not as code. Heavy Metal parked as a possible later tile set. | 2026-08-06 |

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

## Source material: which Paradroid? ✅ DECIDED

**The target is the 1985 Hewson original / 1986 Competition Edition lineage. `paradroid_ce.lst` is
that lineage, so nothing extracted so far needs redoing.**

> An earlier version of this section stated the listing was a disassembly of *Paradroid Redux*, and
> that the port therefore reproduced Redux. That was wrong. It was never verified; this section
> now records the measurement that settled it.

### How it was settled

All four C64 releases were unpacked by running them under VICE and dumping RAM at a breakpoint —
see `tools/unpack_prg.ps1`. Diffing the unpacked images against the listing:

| | original | Competition Ed. | Heavy Metal | Redux |
|---|---|---|---|---|
| listing code image match | **82.4 %** | 67.6 %¹ | 1.2 % | 2.9 % |
| `"VERSION 1.0"` present at `$6E90` | yes | yes | no | no |
| listing blocks `$6B0E` `$6AA4` `$6FEA` `$E613` `$EA00` found at their listed addresses | yes | yes² | none | none |
| core code `$1000–$3FFF` | 99.8 % | 99.9 % | ~1 % | ~1 % |

¹ Depressed only because that dump was taken at the title screen, before the game copies its high
code up to `$C000–$FFFF`.  ² Staged at `$8000–$BFFF`, which is where both releases hold them until
the copy-up.

Heavy Metal and Redux relocate everything, so every tool in `tools/` would have to be rewritten to
target either. That alone rules them out as a baseline.

### Original vs Competition Edition is very nearly a non-choice

The staged code+data block `$8000–$B1FF` (12.5 K, holding the high code before it is copied up to
`$C000–$FFFF`) differs between the two by **8 bytes** — three a `"CBM"` marker, the rest small immediates
that look like raster split positions. Core code `$1000–$3FFF` is byte-identical, as are the
graphics and level data. Crucially:

```
PlayerSpeed_t @ $6D97   orig [0,5,6,0,7,0,0,0,7]     ==  CE [0,5,6,0,7,0,0,0,7]
DSpeed_t      @ $8A40   orig [4,1,2,4,2,1,8,2,...]   ==  CE [4,1,2,4,2,1,8,2,...]
```

**CE's "50 % faster" is frames-per-iteration, not distance-per-iteration.** The movement constants
are identical; CE simply completes more `GameLoop` iterations per second. On this port that dial is
`PLY_ITER_FRAMES` in `src/player.asm` — currently 2, which sits nearer CE's pace than the
original's ~3. So CE's feel is available from the original's data for free, by choosing a number.

CE's actual change is its rewritten C64 scroll code in `$C000–$FFFF`, which this port replaces with
CRTC hardware scrolling. It is therefore of no use to us. (That region was not diffed for CE — the
CE dump was on the title screen, before the copy-up — but nothing downstream depends on it.)

**A caveat on the method, for anyone repeating it:** the staging block is only intact for part of the
game's life. Paradroid passes through three states — title screen (staging populated, `$C000–$FFFF`
still zero), early in-game (both copies present), and later in-game (staging overwritten with filler,
only the `$C000` copy left). Both dumps used above were in a state with staging intact, so the
comparison is sound, but a dump taken later would have shown the two releases as ~99% *different* for
no reason at all. `tools/unpack_prg.ps1` documents which regions are stable in which state.

### Redux is a specification, not a codebase

Redux's [bug list](https://paradro.id/) is worth adopting as *behaviour*, without porting any of
its code:

- enemy laser 1 / laser 2 damage swapped
- player able to pass through walls by abusing asymmetry in the wall collision check
- `DroidNear()` returning true for faraway droids
- droids losing waypoints when bumped mid-transition; waypoints ignored when a droid paused on
  entering one; waypoints checked twice as often as necessary
- non-visible area scanned differently in each direction
- droid mode occasionally uninitialised, exploding droids on deck entry
- the last waypoint of the maintenance deck sending droids into a wall

Several other Redux fixes are C64 platform bugs that cannot occur on the Beeb and should not be
carried over as complexity: hardware sprite-collision handling, VIC-II register write buffering,
the decimal flag left set in the IRQ, and C128 / NTSC raster timing. Its optimisations (delta
calculation, `TestLine()`, screen redraw cycle counts) are C64-cycle-specific.

### Heavy Metal — parked as an optional skin

Heavy Metal has the more elaborate "embossed" Morpheus-style tiles and is widely considered the
best of the three original releases. It is **not** a baseline candidate: its data layout matches the
listing at ~1 %, so adopting it means re-disassembling and rewriting the whole extraction pipeline.
It could return later as an alternate tile set — Redux ships both sets, which is fair precedent —
but MODE 1's flat four colours may not flatter artwork that leans on C64 multicolour with per-tile
palettes. Judge that from a conversion, not from the C64 screenshots.


## Memory budget

**As actually built** (addresses from the `beebasm` output, not planned):

| Region | Size | Contents |
|---|---|---|
| ZP `&64–&6D`, `&70–&8F` | 42 B | all used — see the map in `main.asm` |
| `&0100–&01FF` | 256 B | stack |
| `&0400–&0C90` | 2192 B | MODE 1 charset, built at deck load — reclaimed OS workspace |
| `&0C90–&10FF` | ~1.1 K free | rest of the reclaimed OS workspace |
| `&1100–&2B0D` | 6.5 K | code + sprite data (`PARA`). DFS random-access buffer space, safe for `*LOAD` |
| `&2B0D–&2BFF` | **243 B free** | |
| `&2C00–&3000` | 1 K | tile map, built at deck load |
| `&3000–&4707` | 5.8 K | `PARADAT`: C64 char data, colour schemes, tile defs, deck RLE |
| `&4800–&547F` | 3.2 K | panel — 5 rows × 640, displayed by rupture cycle 1 |
| `&5500–&56FF` | 512 B | `CHAR_PTR_LO`/`HI` — character code → charset address, built at startup |
| `&5480–&5647` | 455 B | the player sprite, shifted 2 px right — built at startup |
| `&5647–&56FF` | **185 B free** | |
| `&5700–&57FF` | 256 B | data byte → transparency mask table — built at startup |
| `&5800–&7FFF` | 10 K | play buffer: circular strip, 16 rows × 640 |
| SWRAM bank 0 | 16 K | **unused so far** — sprites, and data displaced from `&3000` |
| SWRAM bank 1 | 16 K | **unused so far** — paged code: transfer minigame, console, side view |

**Layer 4 spent the slack.** The charset moved down into reclaimed OS workspace at `&0400` to buy
room, and even so only **243 bytes** remain contiguous below the tile map. Layer 5 has to fit droid
state and movement into that, so `PARADAT` into bank 0 — which frees `&3000–&4707` — is now the
next structural move rather than a someday one. Note the deck RLE and colour tables are read during
`LoadDeck`, so whatever pages them in has to be resident.

Sprite storage turned out far cheaper than the 30–60 K feared here before Layer 4: the player is
455 bytes plus 344 of tables, because masks are derived rather than stored and only 2 px shift
variants are kept. Four-way 1 px shifts would need 1820 bytes, which is what waits on `PARADAT`
moving out.

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

> Superseded by Layers 3b–3d. The screen is no longer a 16K MODE 1 frame at `&4000`: it is a 10K
> circular strip at `&5800` with a panel at `&4800`, driven by a three-cycle rupture. The
> "RAM reclaim opportunity" noted here was taken — shrinking the displayed area handed back
> `&3000–&57FF`, which is where the level data and panel now live.

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

| File | Contents |
|---|---|
| `PARA` | code, plus reserved space for the tile map and charset built at runtime |
| `PARADAT` | C64 char data, colour schemes, tile defs, deck RLE — `*LOAD`ed *after* the mode change |

Current addresses are in the memory budget above; they move as the code grows, so read them from
the `beebasm` output rather than from here.

This bites again at every later layer that adds data. The eventual fix is to stop using `VDU 22`
and program the video ULA and CRTC directly, which we need anyway to keep the OS from clearing or
scrolling our screen. Note `*LOAD` must also happen **before** `InstallIrq` — taking over IRQ1V
stops the MOS servicing the filing system.

**Verified:** `verify_bbc.py --tilemap <dump> <deck>` diffs a tile map dumped from the emulator
against a fresh Python RLE decode. Deck 1 (226 non-empty tiles) and deck 3 (498) both match all
1024 bytes, and both counts agree with `level_stats.txt`. Deck 3 was chosen deliberately — its RLE
lives at `&3393`, above `&3000`, so it exercises the clear-on-mode-change bug above.

*Note:* deck 1 masked that bug entirely. Its RLE sits at `&2DC0`, below `&3000`, so it rendered
identically before and after the fix. Screenshot comparison alone would not have caught it.

### Layer 3 — Scroll ✅ DONE (3a–3d)

The decision point, and it is now decided: **CRTC hardware scroll over a circular strip, 4 px
horizontally and 1 scanline vertically, both axes vsync-locked at one step per frame.**

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

**Parked option — 2-px horizontal, Master only.** A second buffer holding the map offset by 2 px,
alternating which one is displayed. Superseded by **Master-only extensions** at the end of this
document, which corrects this note: the obstacle on a Model B is not "no room for the second buffer"
but that a circular strip's period must equal the hardware wrap span and there is only one such
region. On a Master both buffers live at the *same* address in main and shadow RAM, so the wrap is
shared and the switch is one ACCCON bit.

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
| diagonal right+down, **`line` = 3** — the split row is live | 0 / 10240 |
| diagonal left+up, **`line` = 3** | 0 / 10240 |

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

##### Anything that writes a whole cell into display row 0 must respect the split

Reported by KC: diagonal scrolling leaves mess behind.

`DrawColumn` writes all 8 scanlines of every row it touches, including display row 0 — which is the
split row. Scanlines `0..line-1` there belong to map row `mapYr+16`, and a column redraw was
overwriting them with `mapYr`. Those scanlines are **invisible at the time**, so nothing shows until
`line` wraps and that row rotates round to the bottom of the window — which is why it looked like
mess being left behind rather than a column being drawn wrong.

`DrawColumn` now re-writes scanlines `0..line-1` of its display-row-0 cell from `mapYr+16` after the
main loop, via `DrawHalfPart`. One cell, up to 7 bytes.

**`RedrawAll` had the same blind spot**, which is why the diff oracle had only ever been valid at
`line = 0`. It now applies the same repair across all 80 units, so a full redraw is correct at any
scroll position — and the incremental scrolling can be diffed against it at any value of `line`,
which is where these bugs actually live.

*Testing trap, cost an hour:* the first run of that diff reported 72 bytes differing on exactly the
split scanlines, and the natural reading was that the fix had not worked. It had — the **oracle**
was being sampled mid-redraw. `RedrawAll` plus its split pass runs longer than the 400,000 cycles
being allowed to settle, so the dump caught display row 0 rewritten by the main loop but not yet
repaired by the split pass. Allow 1,500,000 cycles after releasing SPACE. Confirmed by breakpointing
`ra_nosplit` and reading the buffer there: correct at the end of the routine, wrong in the middle.

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

### Layer 4 — Player droid: sprite, controls, collision ✅ DONE

Merged with the player half of Layer 5, because the point of the layer is the *feel* of moving the
player and the sprite alone does not demonstrate that. What landed: the 24×21 player sprite with its
8 rotor phases, the C64 speed model, pixel-granular 8-way scrolling, and wall collision.

The frame budget at full diagonal speed was the last thing outstanding and is **closed** — see the
end of this layer for the measurement. The one judgement still open is whether the dead-zone
camera's feel is right; KC has it "to sleep on".

#### The player sprite is constructed, not stored

There is no player sprite in the C64 data. The dynamic sprite area `$5200-$53FF` ships **zeroed**
and every droid's sprite is built into it at runtime:

| routine | writes |
|---|---|
| `BuildDroidSprite` (`$3C77`) | the three-digit droid number into sprite rows 6-13 |
| `AnimateDroids` (`$3CFB`) | the spinning rotor into rows 0-4 and 15-19, from `RotAnim_*` |

Rows 5, 14 and 20 are never written, so they stay transparent. That is the entire sprite: a rotor
above and below, the number in the middle. `tools/export_player.py` replays both routines offline
for droid 001 (`DCent_t[0]` = 0, `DNum_t[0]` = `$01` → digits 0, 0, 1) and emits MODE 1 data.

Two details worth keeping:
- The bottom half is the top half in **reverse row order**, not mirrored left to right —
  `AnimateDroids` writes the same L/M/R bytes both times.
- Rows 0/1 and 18/19 carry only a middle byte, from 2-entry tables indexed by `phase >> 2`, and the
  bottom pair uses the *other* entry. That is what makes the two ends of the rotor alternate.
- Row 2 and row 17's right-hand byte is `$80`, left in the accumulator from the row above. There is
  no `RotAnim_2_17R` table.

Only the distinct rows are stored: 5 rotor rows × 8 phases, the 2 alternating end rows × 8 phases,
8 digit rows shared by every phase, and one blank — **65 rows of 7 bytes, 455 bytes**. Finding them
costs a 16-bit offset per sprite row per phase (`plyOfsLo`/`plyOfsHi`, 8 × 21) plus `plyMulRows`,
another 344 bytes. Blank rows point at a real all-transparent row, so the blit needs no special
case for them.

**Colour is approximate.** A C64 multicolour sprite's bit pairs are transparent / `$D025` (black) /
the sprite's own colour (white) / `$D026` (orange). MODE 1's four logical colours are the deck's, so
the three are mapped onto logical 1-3 by role. The player therefore changes colour with the deck,
exactly as the tiles do. Revisit if it reads badly on a particular deck.

#### 4a — Dead-zone camera, and 2 px sprite positioning

**The CRTC's horizontal granularity is 1/80 of the display width in every mode.** It addresses in
8-byte units and a row is 80 of them, so a step is ~4 MODE 1 pixels; MODE 0 does not help, because
its pixels are half the width. Anything finer is software.

Two 10K circular strips — a second copy of the map offset by 2 px, alternating which one R12/R13
points at — is the obvious answer and **cannot work on a Model B**. A circular strip only works
because its period equals the hardware wrap span, and there is exactly one wrap region available:
10K wrapping at `&5800`. A second strip at `&3000` under the 20K wrap runs out of its own 10K and
continues into the first. Interleaving rows, a 1280-byte row stride with `R1` = 80, switching the
wrap per field — all fail on the same point, that the CRTC's row stride *is* `R1`.

> The same 2 px scheme *is* hostable on a Master, via shadow RAM. It is parked on cost, not
> feasibility — see **Master-only extensions** at the end of this document.

**So the camera moved instead of the scroll.** `plyX` is the player's own position in the world, at
1 px; `posX` is the view, which only follows once the player leaves a ±8 px window around the
centre and then moves in whole 4 px units. Walking slowly the world holds perfectly still and only
the droid moves, which is the case that looked bad; at speed the window saturates and the view
scrolls as before. The cost is that the player is no longer pinned centre and that reversing
direction crosses the window — about 5 frames at top speed — before the world reacts.

Vertically nothing changed: the scroll is already 1 scanline, so the player stays pinned and
`posY` remains the authority.

**The sprite is positioned every 2 px.** A 2 px shift spills 24 px into seven bytes, so rows are
stored seven wide and there are two copies — unshifted on disc, shifted built at startup by
`PlyBuildTables` into `&5480`. 2 px rather than 1 is not only thrift: a C64 multicolour pixel is
exactly two MODE 1 pixels, so the artwork holds no finer detail. 1 px needs four copies, 1820
bytes, which does not fit below `&3000` until `PARADAT` moves to sideways RAM.

**Masks are no longer stored.** Every opaque pixel maps to logical 1, 2 or 3 and never 0 — the
exporter asserts it — so a pixel is transparent exactly when both its bits are clear, and a
256-byte table recovers the mask from the data. The row was being copied into a buffer anyway, so
deriving it there is free, and it halves the sprite data.

> **The collision snap must not move the reference cell.** With the reference offset now 11 rather
> than 159, the C64's `(X+7) AND $F8` rounds *up* and tips the cell over — the same one-pixel
> jitter as before, back again by a different route. Both snaps now stay inside the current cell and
> only strip the sub-cell remainder: `(cwU AND &F8) + 1` going right, `cwU OR 7` going left. Both
> idempotent, so holding against a wall is stable. The vertical snap still uses the C64's form
> because `PLY_REFY` is 63 and 63 MOD 8 = 7 makes the two coincide.

#### The player does not move on screen; the deck does — mostly

`PlayerSprite_dat` (`$6A2E`) puts sprite 7 at VIC (172, 172) = screen (148, 122). 148 is exactly
`(320-24)/2` and a multiple of 4, so the sprite lands on a CRTC unit boundary and **needs no
pre-shifting at all** — the open question from the old Layer 4 notes is answered: zero shift
variants, not two.

Our play area is 120 px rather than 136, so the sprite sits at y = 50. That puts it in strip rows
6-9, which means **it never touches display row 0 or row 15** — the two rows the scroll redraws
write. The split-row hazard and any blit/redraw collision are structurally impossible here rather
than merely avoided.

Order within a frame is load-bearing: restore at the old address, *then* move, *then* save and blit
at the new one.

> **Adjacent 4-pixel columns are 8 bytes apart, not 1.** Consecutive bytes within a column are
> consecutive scanlines. The first build blitted the six bytes of a sprite row to six consecutive
> addresses and drew the sprite one column wide and six scanlines deep. Obvious in hindsight, and
> the same trap will be there for every sprite added later.

#### Scrolling is now a pixel position, not a step

`posX`/`posY` are 16-bit map pixel positions and everything derives from them: `mapHX = posX >> 2`,
`mapYr = posY >> 3`, `line = posY AND 7`. A frame moves 0-7 pixels on each axis, which is up to 2
columns and up to 7 scanlines.

The addressing invariant that makes this work — absolute map pixel row `A`, unit `u`, lives at

```
BUF_BASE + ((scrollS + ((A>>3) - mapYr)*640 + u*8 + (A AND 7)) MOD BUF_SIZE)
```

and **that expression is invariant under scrolling**: substitute the new `scrollS` and `mapYr` after
a move and it names the same byte. So nothing already drawn ever moves, and only the leading edge is
drawn. `((A>>3) - mapYr) AND 15` is exactly what makes display row 16 and display row 0 the same
row.

`ScrollUp`/`ScrollDown`/`ScrollLeft`/`ScrollRight` and `DrawScanline` are gone, replaced by
`ApplyMove` (state, and a record of what got exposed) and `DrawBand` (N scanlines from an absolute
map pixel row, split across at most two character rows).

#### The speed model — and why the listing's numbers are not the ones to use

**The C64's constants are per `GameLoop` iteration, and an iteration is not a frame.** Taking them
literally made the player move at twice the original's speed, which is what KC saw.

`GameLoop` (`$13DA`) has five reads of `irqToggle` that look like frame waits. Three — `$13DC`,
`$13F5`, `$13FC` — assemble as `D0 00` and `F0 00`: branch offset zero, falling straight through.
The listing's annotator marks them `; !! remove`. Only `_w4` (`$1417`, `F0 FC`) and
`EnterGame` (`$1430`, `D0 FC`) really spin, one on each edge of `irqToggle` — which `Irq_254` sets
and the raster handler at `$6FB1` clears. So the loop is bounded by one rising and one falling edge:
**one frame, if the work fits in a frame.**

It does not. `DrawScreen` (`$391A`) copies 17 rows of 39 characters to screen RAM and colour RAM,
and its inner loop is 26 cycles:

```
LDA $4940,Y 4 / STA (dest),Y 6 / TAX 2 / LDA CharColor,X 4 / STA $D940,Y 5 / DEY 2 / BPL 3
```

663 characters × 26 = **~17,250 cycles**, against roughly 18,300 usable in a PAL frame once badline
and sprite DMA are taken out. `DrawScreen` alone very nearly fills a frame, before `RunDroids`,
`DoCollision`, `AnimateDroids` or the sound driver have run. An iteration is **2 to 3 frames**,
drifting towards 3 as a deck fills with droids.

So the conversion, with `PLY_ITER_FRAMES = 2` — velocity divides by the frame count once,
acceleration twice:

| | C64, per iteration | here, per frame |
|---|---|---|
| acceleration | 208/256 px/it² (`Acceleration_`, `$6955`) | 52/256 |
| deceleration | 176/256 px/it² (`DecelerationNeg_`, `$6954`) | 44/256 |
| top speed | 7 px/it (`PlayerSpeed_t[DSpeed_t[0]]`) | **3.5 px/frame** |

Same motion in real time — 0.34 s from standing to top speed either way — but sampled at 50 Hz
instead of 25, so it is smoother than the original rather than merely as fast. `PLY_ITER_FRAMES` is
the one number to change if it still reads wrong; raising it slows everything together and keeps the
acceleration curve's shape.

**The position needs a fraction byte.** The C64 adds only the whole-pixel part of the speed and
drops the fraction every frame, which it can afford because its top speed is a whole number of
pixels per iteration. Ours is 3.5: truncating moves 3 and throws the half away every frame — 14%
short — and makes the first few frames of acceleration move nothing at all, which reads as a sticky
start. `posXf`/`posYf` make the position 16.8 and the speed adds into it whole, as a 24-bit signed
add. Clamping, stopping and wall-snapping all clear the fraction so the result lands on a whole
pixel.

The clamp is 16-bit for the same reason: 3.5 has a fraction, so it is part of the limit rather than
something to discard.

*Deliberate divergence:* the C64's accelerate-negative path is one 256th weaker than its positive
one, an artefact of the `SEC`/`ADC` idiom it uses to subtract. We subtract properly and both
directions match.

Opposite keys cancel, which falls out of a `DEC`/`INC` pair rather than needing a test — and that
retires the hand-written up/down exclusion Layer 3d needed.

#### Wall collision, and a one-pixel jitter worth understanding

`CheckPlyAdvance` (`$29C1`) probes 12 cells in a diamond around the player; the listing draws it at
`$6B52`. Probes 9-B guard the right, 6-8 the left, 3-5 below, 0-2 above, and a probe only counts if
the player is moving that way — which is what lets the player slide along a wall instead of sticking
to it. A cell is solid if its **character code has bit 7 set**, the same test the droid AI uses.

**The reference cell must use the C64's ceiling-rounded origin.** `DrawScreen` computes it as
`(ScreenPosX + 7) >> 3`, and `plyMapPos` is that plus 19. Round *down* instead and the collision
snap moves the reference cell: snapping to a character boundary tips the cell index over by one, the
whole probe diamond shifts right, the wall drops out of the probes, and the player drifts back into
it next frame. It sat against the wall visibly jittering one pixel. With the `+7`, snapping can only
remove the sub-character remainder, never change the cell — which is the property the scheme
depends on.

Our offsets are `PLY_REFX = 159` (sprite left 148 + 11) and `PLY_REFY = 63` (sprite top 50 + 13),
putting the reference cell over the digit block, the same part of the sprite the C64 uses.

#### Memory: the charset moved to `&0400`

Layer 4 filled the space below `&3000`. `&0400-&0CFF` is 2.3 K of MOS workspace nothing here uses —
BASIC's variables, the sound and printer queues, the soft key and user-defined character buffers.
BASIC is not running, we own IRQ1V so the MOS sound code never executes, and the charset is built at
deck load, after the last filing-system call.

The alternative was moving `PARADAT` into sideways RAM. That is still the right answer eventually,
but it was not the one that unblocked this layer.

As the build actually reports it — regenerate these numbers from `build.ps1` rather than trusting
the table, because Layer 4 moved them twice:

| | |
|---|---|
| `&0400-&0C90` | MODE 1 charset, built at deck load |
| `&1100-&2B0D` | code + sprite data |
| `&2B0D-&2BFF` | **free — 243 bytes** |
| `&2C00-&3000` | tile map |
| `&3000-&4707` | `PARADAT`, loaded after the mode change |

**243 bytes is the whole of the headroom below `&3000`**, and Layer 5 has to fit droid state and
movement code into it. Moving `PARADAT` to sideways RAM frees 5.8 K and is now closer to necessary
than optional — it is also the prerequisite for 1 px sprite positioning.

#### The frame budget — closed, and how

At the (wrong) 7 px/frame this did not fit. Measured by holding keys and reading `posX`/`posY` over
exactly 25 frames (998,400 cycles):

| | at 7 px/frame | at 3.5 px/frame |
|---|---|---|
| horizontal only | 7.0 — 100% | **3.5 — 100%** |
| vertical only | 6.2 — 88% | **3.5 — 100%** |
| diagonal | 5.0 — 72% | **3.5 — 100%** |

Correcting the speed halved the work per frame as well as the speed — a step is now at most 4
scanlines and 1 column instead of 7 and 2 — and the budget closed as a side effect. Both axes hold
exactly 35 pixels per 10 frames on a full-speed diagonal, frame-locked. *(Measured with `CheckWalls`
poked to `RTS`, so the run was not cut short by a wall.)*

**Watch this if anything gets added to the frame.** When the loop overruns, `WaitVSync` finds
`drawFlag` already set and returns immediately, so it free-runs rather than quantising to 2 frames:
the symptom is not a halved frame rate but movement that is quietly slower than it should be, and a
leading edge that can tear. The check is the measurement above — hold a diagonal and confirm 35
pixels per 10 frames.

Two rounds of optimisation landed while chasing this and are worth keeping regardless:

- **`BandSetRow`/`BandCharPtr` and `ColSetup`/`ColCharPtr`** hoist everything that depends on only
  one axis out of `MapChar`, and cache the tile pointer (it changes every 4 characters, or every 4
  rows down a column).
- **`DrawBandRows` walks characters, not units.** Two adjacent units are the two halves of one
  character, so one lookup serves both — and, more importantly, it halves the per-unit bookkeeping,
  which turned out to cost more than the lookups did.
- **`BUF_END` is page aligned**, so the strip wrap test is one compare on the high byte: 5 cycles
  when it does not fire, which is 159 times in 160.

Those took the diagonal from 4.2 to 5.0 px/frame before the speed was corrected. Headroom still in
the bank, in rough order of value, for when droids start competing for the frame:

| | worth |
|---|---|
| Sprite: precompose the current phase instead of `PlyFetchRow` per row | ~2,500 |
| Cache the previous frame's 40 row pointers — group 2 of frame N is group 1 of frame N+1 | ~2,300 |
| Replace `keydown`'s OSBYTE `&81` with a direct System VIA matrix scan | ~2,000 |
| Inline `BufNextUnit` / `CellXInc` — 36 cycles of call overhead per character | ~1,440 |
| Unroll `DrawColumn`'s 8-byte copy | ~1,100 |

`CopyRun` was the top line and is done — see *The level draw* below for what it was worth and what
is left behind it.

**The deadlines are staggered and tighter than a frame**, which matters more than the frame total:
an **up**-band and the columns both display at `P+64`, so they share only 192 scanlines (24,576
cycles), while a **down**-band has until `P+184` of the next frame.

#### The level draw — where its time goes, measured

Measured 2026-08-13 with **`DEBUG_TIME`** in `main.asm` — a User VIA T1 bracket around one routine,
plus a poked `dbgSpdX`/`dbgSpdY` that takes the controls over and skips `CheckWalls`, so a run is
exact and repeatable in a way a held key is not. Its header carries the arithmetic and the two
rules that make a reading mean anything (one call site; poke, do not press). One game pass is
2 fields = **79,872 cycles**; top speed is 7 px a pass.

The band's cost separates cleanly into a per-row entry fee and a per-scanline copy, fitted from
three vertical speeds whose bands each fall inside one character row (1, 2 and 4 px a pass):

```
band = 10,954 per DrawBandRows pass  +  1,371 per scanline across the 320 px width
```

Per character across the 40-character width that is **274 fixed + 34 a scanline**. The fixed part,
by static count: `BandCharPtr` 99 (36%), two `BufNextUnit` 66, two `CopyRun` call+setup 34,
`CellXInc` 20, `chp + 8` 13, loop control 8. **Half of it is JSR/RTS and pointer arithmetic, not
lookups** — which is what makes the inlining line in the table above real.

A column is **5,005 cycles**, 313 per 8-byte cell: `ColCharPtr` ~114, the copy 129, pointer advance
and wrap test 26, loop control 18. It spends 40% of its time copying against the band's 23%,
because one lookup serves 8 bytes there instead of 2.

Per byte written: band 51 cycles, column 40, against a floor of ~18 for the copy loop itself.

##### `CopyRun` unrolled — the parameterisation outlived its case

`CopyRun` took `bandScan` and `bandRun` as variables and cost 18 cycles a byte to do it. After the
whole-row change `DrawBandRows` has one caller which always passes 0 and 8, so that generality was
being paid 640 times a band pass to support a case that no longer occurs. Unrolled into a `COPYCELL`
macro with an immediate `Y` — 13 cycles a byte, the floor for `(zp),Y` on both sides — and inlined
at the two sites inside the loop. The two edge halves of an odd `mapHX` call `CopyCell` instead:
they run once a pass against the loop's 40, and 12 cycles of call is not worth 48 bytes each.
`bandScan` and `bandRun` are deleted.

| per pass, 7 px | scanline bands | whole rows | + unrolled copy |
|---|---|---|---|
| vertical | 28,527 | 19,655 | **15,280** |
| full diagonal | 38,472 | 28,143 | **24,249** |
| one band pass | 31,505 *(peak, 2 rows)* | 22,311 | **17,290** |

**−5,021 a band pass for +114 bytes**, against −4,560 predicted. Cumulatively the level draw is
**46% cheaper vertically and 37% on a diagonal** than it was at the start of the day. Columns are
untouched and measure 5,260, confirming the change is where it was meant to be.

Where a character's 414 cycles now go: pixel copy 176 (43%), `BandCharPtr` 99 (24%), two
`BufNextUnit` 66 (16%), `CellXInc` and loop 28, `chp + 8` 13, `Y` setup 32. Copy loop overhead has
gone from 146 to 32.

##### `charRemap` precomputed — address arithmetic beat the lookup it followed

`charRemap` packs the used-character index into a byte, and every one of the three lookup paths
unpacked it into a 16-bit pointer at the point of use: `PHA`, `AND`, four `ASL`s, `PLA`, four
`LSR`s, `ADC`. **41 cycles of address arithmetic per character drawn — more than the tile-map
lookup it follows**, which is cached three calls in four and costs ~11 amortised. That is the shape
worth remembering: the expensive part of "decoding a tile" was not the decoding.

`BuildCharPtrs` folds it into `CHAR_PTR_LO`/`CHAR_PTR_HI` at startup, so a lookup is `TAX` and two
indexed loads: **16 cycles**. Both tables are page aligned, so the `abs,X` never crosses a page.
They cost 512 bytes at `&5500-&56FF`, of the scratch between the panel and the strip that nothing
else wanted, and the code came out 3 bytes *smaller* — three unpack blocks deleted against one
builder added.

It is a pure function of `charRemap` and the charset base, both fixed for the whole run, so it is
built once rather than per deck: `BuildCharset` rewrites the charset's *contents* per deck, never
its address. `charRemap` is now read only at startup — `tiledefs` is what still pins the data bank
in during play.

| per pass, 7 px | + unrolled copy | + precomputed pointers |
|---|---|---|
| horizontal | 8,759 | **8,067** |
| vertical | 15,280 | **14,304** |
| full diagonal | 24,249 | **22,810** |
| one band pass | 17,290 | **16,237** |
| one column | 5,005 | **4,663** |

**−1,053 a band pass and −342 a column**, against −1,000 and −400 predicted. This one helps every
path that draws a character, which the previous two did not.

##### One 16-byte run a character — and why no loop split was needed

A character's two halves are 16 consecutive bytes in the charset, and the two units they go to are
16 consecutive bytes in the strip. So one `Y` running 0-15 addresses both, and the `chp + 8` and
the `BufNextUnit` that sat between the halves are simply gone.

The obstacle looked like the buffer wrap: it lands on a *unit* boundary, so it could fall between a
character's two halves, and the second half would then be written 8 bytes past `&8000` — into
sideways RAM, not a wrong pixel. The plan was to find the straddling character in the prologue and
split the loop around it. **It turns out not to be possible.** Units from the row start to the wrap
is `W = 1280 - off/8` where `off = (scrollS + rCount*640) MOD 10240`; `rCount*640` is 80 units, so
`W ≡ scrollS/8 (mod 2)`. Characters begin at even units when `mapHX` is even and odd units when it
is odd. So the wrap lands on a character boundary exactly when

```
scrollS/8 == mapHX   (mod 2)
```

and that is invariant: both sides move by `dUnits` horizontally, a vertical step moves `scrollS/8`
by 80 and `mapHX` not at all, `scrollS` wraps at 1280 units, and 80, 1280 and 0 are all even. Even
a clamp is safe, because `sDelta` is computed *from* the `mapHX` difference rather than alongside
it.

`LoadDeck` now sets `scrollS` to 0 or 8 to match `mapHX`'s parity instead of always 0. As things
stand that is a no-op — `CentreOnDeck` produces `charX * 2`, always even — but the consequence of
the invariant being false is a write outside the buffer, and that should not rest on another
routine's arithmetic staying as it is.

The per-character wrap test stays, at 8 cycles; only the *mid-character* case had to be excluded.
Its fixup moved out of line, which keeps the loop's branch in range and makes the common path a
not-taken `BCS` at 2 cycles rather than a taken `BCC` at 3.

| per pass, 7 px | + precomputed pointers | + 16-byte run |
|---|---|---|
| vertical | 14,304 | **12,225** |
| full diagonal | 22,810 | **20,482** |
| one band pass | 16,237 | **13,878** |

**−2,359 a band pass for +23 bytes**, against −2,320 predicted.

##### Where the level draw stands

| per pass, 7 px | start of 2026-08-13 | now | |
|---|---|---|---|
| vertical | 28,527 | **12,225** | **−57%** |
| full diagonal | 38,472 | **20,482** | **−47%** |

A character costs 330 cycles, and **more than half of it is now the pixel copy** (176), against a
third when the day started: `BandCharPtr` 74, buffer advance and wrap test 20, `CellXInc` 20, loop
control 8. The band has stopped being a lookup walk that happens to copy some bytes.

Still in the bank, and it is thinner than it was:

| | per band pass |
|---|---|
| Inline `CellXInc` and `BandCharPtr`'s own call — 24 cycles a character | ~960 |
| Self-modify the copy's addresses to use `abs,Y` instead of `(zp),Y` — 11 cycles a byte instead of 13, less the patching. Marginal, and it is self-modifying code in the hottest loop in the port | ~1,000 |

Beyond that the band is close to its floor: 13 cycles a byte is what `(zp),Y` on both sides costs,
and 640 bytes have to move.

##### Whole rows, not exposed scanlines

`DrawBand` used to draw exactly the scanlines a move exposed, splitting them across two character
rows whenever they straddled a boundary — which at 7 px a pass is 7 passes in 8. That paid the
40-character lookup walk **2.03 times per map row** against a floor of 1, measured.

It now draws one whole character row, and only on the pass that crosses into it. The copy volume is
identical at every speed — all 8 scanlines of every row get drawn either way — so the whole saving
is the eliminated duplicate walk, and it is worth **~10,000 cycles a pass at any non-zero vertical
speed**, including 1 px/pass where the old scheme paid a full walk to move one scanline.

| per pass, 7 px | before | after | |
|---|---|---|---|
| horizontal | 8,920 | 8,759 | −2% |
| vertical | 28,527 | **19,655** | **−31%** |
| full diagonal | 38,472 | **28,143** | **−27%** |
| band passes per 42 game passes | 73 | **37** | one per crossing |
| cost of one band pass | — | 22,311 | model says 21,922 |

Peak improves as well as average — the worst pass was 2 rows + 7 scanlines = 31,505, and is now
1 row + 8 = 22,311 — which matters more, because the deadline is per pass and staggered.

**It costs no window height, and that is the part worth understanding.** The handover is exactly
clean with the 16-row strip: going down, when `mapYr` reaches `M+1` the window starts at
`(M+1)*8 + line'`, so map row `M` is wholly above it at the moment map row `M+16` — which occupies
the same physical row, since old relative 0 is new relative 15 — needs its first scanline. Going
up, `line < d` is precisely the condition for the decrement and also the condition for the bottom
row having left the window. The 16th row already given up to smooth scrolling *is* the slack this
needs.

**And it retires the split row.** Every physical row now holds one map row entire, so
`DrawColumn`'s repair pass, `RedrawAll`'s repair pass, and `DrawHalfScan`/`DrawHalfPart` are all
deleted — **230 bytes**, and `RedrawAll` becomes a valid oracle at any value of `line`, which it
was not. **BUGS #1 should be moot**; re-run its tests before closing it.

The one new constraint: a pass must cross at most one row boundary, or the second crossing is never
drawn and the strip holds a stale row that only shows when it scrolls into view. `ASSERT
PLY_MAXSPD <= 8 * 256` in `player.asm` fails the build rather than leaving that to be discovered in
play.

##### The budget, and one measurement trap

Stationary with seven sprites live, the loop is **idle 40,729 of 79,872 cycles**, corroborating the
39,212 measured during the sprite work. The full-diagonal level draw was consuming 38,472 of that —
95% of the standing headroom — and now consumes 28,143, leaving ~12,600.

*Do not measure idle while scrolling to check this.* `TestDroidsUpdate` pins the test droids to
world positions, so they leave the view within ~10 passes and the sprite cost collapses; measured
idle under a diagonal was a flattering 24,583. The 95% figure is the sum of two independently
measured quantities, which is the right way round.

##### Reading `DEBUG_DRAW`

The bands only appear where the CRTC is displaying something. From `drawFlag` release at `P+184`
through VSync to the next panel at `P+312`, nothing is display-enabled — R6 has already ended the
play cycle and the tail displays no rows — so that whole stretch is black whatever the palette
says. The panel is the first place a tint can land, 128 scanlines after the loop starts.

So the yellow band shows **where the level draw finishes, not how long it took**. No yellow means
it ended before `P+312`, not that it was free: horizontal scrolling shows no bands at all. Yellow
reaching into the play area means the draw is still writing while the raster reads — on a
row-crossing pass it currently does, by about five rows.

#### Verified

Play buffer diffed byte-for-byte against `RedrawAll` after full-speed diagonal scrolling in both
vertical directions:

| | result |
|---|---|
| odd `mapHX` (167), `line` = 1, before the dead zone | **0 real differences in 10240** |
| odd `mapHX` (155), `line` = 5, sprite at unit 39 with a 2 px shift | **0 real differences in 10240** |

In both runs some bytes differed and every one was inside the sprite's own footprint, where the
rotor had spun between the two dumps. Compute that footprint and exclude it rather than staring at
the diff wondering — it depends on `scrollS`, `line` and `plyUnit`.

Re-verified after the whole-row band, this time with `JSR SprDrawAll` poked to NOPs so the rotor
could not pollute the diff at all — simpler than computing the footprint, and worth doing that way
from now on:

| | result |
|---|---|
| odd `mapHX` (137), `line` = 1, down-right diagonal | **0 differences in 10240** |
| odd `mapHX` (107), `line` = 4, up-left then down — `line` wrapped both ways | **0 differences in 10240** |
| even `mapHX` (142), `line` = 3, after an 11M-cycle diagonal through the vertical clamp | **0 differences in 10240** |

and again after `CopyRun` was unrolled, covering both branches of the odd/even split:

| | result |
|---|---|
| odd `mapHX` (137), `line` = 1 — leading and trailing halves, 39 whole characters | **0 differences in 10240** |
| even `mapHX` (180), `line` = 1, deck 2 — the plain 40-character loop | **0 differences in 10240** |

> **Let the view SETTLE before the first dump, and check it has not moved between the two.** A run
> that dumped two passes after releasing the keys reported 66 differing bytes; the view had coasted
> one unit between the dumps, so the two were of different scroll positions. Record `mapHX`,
> `mapYr`, `line` and `scrollS` with each dump and compare them before believing a diff. Deck 2 is
> the easy way to an even `mapHX`: it centres at 180.

Then the clean build with sprites live: diagonal scrolling and a deck change both render correctly,
no torn top or bottom row.

> **jsbeeb will not boot an unpadded SSD.** It hangs in the DFS FDC poll at `&ACAE` loading
> `PARASPR`, because beebasm's image ends mid-track and jsbeeb will not read the last partial one.
> It reproduces from BASIC with `*LOAD PARASPR`, so it is not the game. Pad a copy to 200K before
> handing it to the emulator. This cost an hour before it was recognised as an emulator problem.

### Layer 5 — Droid movement
`GetNewDir`, `AdvanceMapPos`, `CheckDroidAdvance` and the waypoint logic — the same speed model
applied to non-player droids. The player half of this layer landed in Layer 4.

#### Blitter optimisation, before the droids go in

Seven slots at the Layer 4 cost do not fit in a frame, so the blitter is being cut down first. Four
steps, in dependency order:

1. **Save area into screen geometry** — done (`3f69b4d`). `(svp),Y` with the same Y as `(bufp),Y`.
   Cycle-neutral in itself; its point is that it makes compilation *possible*, since a compiled
   blitter cannot poke a save address into each of its ~72 stores.
2. **Compile the rotor** — done. Rows 0–4 and 15–19 are generated 6502 in the data bank, with the
   pixels and masks baked in as immediates.
3. **Compile the digits** — done, but it bought less than half what was projected. See below.
4. **Frame lock to 25 Hz** — done. `FRAME_LOCK = 2` in `main.asm`; `WaitVSync` consumes two fields
   an iteration instead of one, so one pass of the loop is one C64 GameLoop iteration.

   | loop iterations per 100 fields | free-running | locked |
   |---|---|---|
   | player only | 101 (50 Hz) | 50 (25 Hz) |
   | player + 6 droids | 80 (40 Hz) | 50 (25 Hz) |

   Free-running was the worse option and it took the test droids to show why: the loop does not fit
   in a field with a full pool, so it stretched to 1.25 fields and **the player moved 20% slower
   with droids on screen than without**. Speed that depends on what is visible is a worse fault
   than speed that is merely chunkier.

   Real-time speed is unchanged — `PLY_ACCEL`/`PLY_DECEL`/`PLY_MAXSPD` now scale by
   `FRAME_LOCK / PLY_ITER_FRAMES`, which cancels at 2 and 2, so the C64's own per-iteration
   constants apply unmodified. Confirmed in the emulator: `xSpd` tops out at `&0700`, 7.0 px per
   iteration, the same 175 px/s as 3.5 px/field at 50 Hz. What is given up is the extra smoothness
   the 50 Hz sampling bought — that was always a bonus over the original, not a requirement.

5. **Round-robin updating** — **dropped, on measurement.** It was the step that bought the pool
   its headroom when seven sprites cost 68K of an 80K pass. They now cost 40.7K and the loop
   spends **39,212 of its 79,872 cycles idle — 49% of the pass** (T1 around `WaitVSync`, seven
   sprites live, averaged over 127 passes). There is nothing left to buy. See *Why not
   round-robin* below before reviving it.
6. **Raster-ordered updating** — flicker, and probably `BUGS.md` #3 with it. Still open, and now
   the only sprite-pool work outstanding.

**Measured, one sprite, one frame** (User VIA T1 around the two calls; both builds at the same
position; ±0 across repeats — the emulator is deterministic):

| | before | after | |
|---|---|---|---|
| `SprRestoreAll` | 3,490 | 3,506 | +0.5% |
| `SprDrawAll` | 10,508 | 7,142 | **−32%** |
| total | 13,998 | 10,648 | **−24%** |

The draw is where compiling pays: the rotor averages **3.2 opaque bytes of 7**, and a compiled row
costs nothing for the transparent ones, where the interpreted path pays 26 cycles to fetch and 27 to
blit each of the seven regardless.

**Restore came out flat, and that is not a disappointment — it is arithmetic.** Copying seven bytes
back costs 91 cycles; the compiled form costs 13 per saved byte plus ~49 to dispatch, which at 3.2
bytes is 91 again. It is kept because the alternative is worse: an interpreted restore would force
the *draw* to save all seven columns, and that costs the draw more than the restore saves.

Seven sprites at 10,648 is 74.5K against a frame of 80K, so this step alone does not buy the pool —
step 3 has to. It does prove the addressing, which was the risk.

**Cost in the bank:** 3,159 bytes of generated code and tables, so `SPR_SHIFT2` moved `&A800` →
`&B000` and the bank now ends at `&B6CF` of `&C000`. The staging assert had to be relaxed with it:
`PARADAT` is now 48 pages and overruns the panel, the mask table and the bottom of the play buffer,
which is safe because `PageDataIn` is the first thing after the load and everything above it is
rewritten before it is next read. Boot shows a moment of garbage in the play area.

**Verification.**
- The generator is checked against the interpreted path in Python: for all 8 phases × 21 rows × 2
  shifts the compiled row is the row `drOfs` would have fetched (320 rows, 0 mismatches), and for
  every distinct row over eight background patterns the compiled writes equal the interpreted
  writes and the compiled restore undoes them exactly.
- In the emulator, after full-speed diagonal scrolling, disabling the sprite and letting it restore
  leaves the play buffer **byte-identical to a forced `RedrawAll` across all 10K** — 0 diffs.
  (Run this at `line == 0`; at `line != 0` the oracle itself is wrong — `BUGS.md` #1.)

#### Step 3, the digits — and why it under-delivered

**The digits are dense where the rotor is sparse: 42.7 opaque bytes of 56 against 3.2 of 7.** So
almost nothing is saved by skipping transparent bytes; the whole win is deleting `SprFetchRow`.

Per-TYPE compiled code is ~1,012 bytes and 24 types is 25K, which does not fit. But the number is
three independent 8-pixel glyphs and there are only ten glyphs, so **ten routines cover all 24
types** and the three positions are reached by offsetting `bufp` by 0/16/32 rather than by
generating three copies. Nothing is generated at run time.

The glyphs draw without saving. Under a 2 px shift each glyph spills into the next one's first
byte, so the three share columns 2 and 4 — and whichever writes a shared column first would have to
be the one that saves it, which is not something a glyph can know about itself. Hoisting the save
into one generic pass over all seven columns removes the question entirely, and the same trick makes
the *restore* a single pass, because putting the background back does not care what was drawn.

| | before | after | |
|---|---|---|---|
| `SprRestoreAll` | 3,506 | 3,260 | −7% |
| `SprDrawAll` | 7,142 | 6,400 | −10% |
| total | 10,648 | **9,660** | −9.3% |

**That is ~990 cycles, against the ~2,600 projected when the scheme was chosen, and the shortfall is
structural rather than a bug.** Three glyph positions mean three walks of the eight rows, plus one
for the save — four walks where the interpreted path made one. A walk step is `JSR SprNextScan`, ~37
cycles including call and return, so the block spends ~1,180 cycles just advancing scanlines where
the old code spent ~296. The projection did not count that.

Getting to one walk needs per-row code covering all three glyphs at once, which is per-type — either
25K shipped or a run-time generator plus a bank to put it in. That was the option deliberately not
taken, and the 990 is what the cheaper choice is worth. It is not worth revisiting: the same effort
spent on step 4 is worth far more.

**Cumulative: 13,998 at the end of Layer 4 → 9,660, a 31% cut.** Seven sprites is still 67.6K
against a 40,000-cycle frame, so compilation has now clearly run out of road and the update rate is
the whole remaining problem.

Verified byte-identical two ways: the compiled digits against the same build's interpreted path
(force it by patching `sd_digit`/`sr_digit`'s `LDA sprNoWrap` to `LDA #0`) — 0 diffs over the whole
10K; and the restore against a forced `RedrawAll` after full-speed diagonal scrolling — 0 diffs.

> **Sample the buffer inside `WaitVSync`, not at an arbitrary cycle count.** A dump taken mid-
> `SprDrawSlot` shows the sprite half-drawn and looks exactly like missing rows. That cost an hour
> here: rows 16-19 appeared to be absent in two independent dumps, and the save area proved they had
> been written all along. Poll the PC until it reaches the `WaitVSync` spin, then dump.

**Bank after step 3:** `&8000-&BA84` of `&C000`, 1,404 bytes spare; `PARADAT` is 59 pages. The 2 px
shifted copy of the artwork is gone — both shifts exist as compiled code, and the stored rows are
read only by the wrap fallback, which shifts the few it needs on the fly in `SprFetchRow`. That
reclaimed the 1,743 bytes the glyph code now occupies.

**Noted while measuring, not chased:** adding ~44 cycles of instrumentation to the *draw* call site
deadlocks the main loop in both builds, while the same stub on the *restore* call site is harmless.
So the loop finishes very close to a raster deadline at that point, and a miss appears to hang the
`ruptState` machine rather than merely costing a frame. Worth understanding before the budget gets
spent.

#### Step 3a — the scanline walk

A static cycle model built from the generated code (reconciling to within 3% of the measured
totals) put **`SprNextScan` at 2,433 cycles, 25% of the per-sprite cost** — the single biggest
line item, ahead of the play-buffer reads and writes at 17%. 42 calls in a draw and 21 in a
restore, at 33-37 cycles each. Three changes, each verified byte-identical before the next:

| | draw | restore | total |
|---|---:|---:|---:|
| after step 3 | 6,345 | 3,271 | 9,616 |
| drop dead `svp` work in the glyph passes | 6,226 | 3,226 | 9,452 |
| read the scanline from `bufp AND 7` | 6,038 | 3,177 | 9,215 |
| inline the walk as the `SCANSTEP` macro | 5,773 | 2,939 | 8,712 |
| stop the loops after the last drawing row | 5,587 | 2,879 | 8,466 |
| eight row pointers, so the glyphs stop walking | 5,093 | 2,913 | 8,006 |
| sequence dispatch + straight-line sprite shape | 4,566 | 2,454 | 7,020 |
| own bank; walk into the rows, rows into a program | 4,300 | 2,243 | 6,543 |
| merged restore halves, tail calls | 4,283 | 2,095 | 6,378 |
| the glyphs save what they draw | 3,844 | 1,970 | **5,814** |

**−3,802 cycles, 39.5%.** Seven sprites cost 40.7K of the 79,872-cycle pass — just over half of
it — against 67.3K. The
walk is down from 2,433 to about 800, and from 25% of a sprite to under 10%; dispatch and the
row loop, 2,000 between them, are down to a couple of hundred.

The restore's +34 on the last row is the ±50 code-layout noise floor, not a regression: nothing
in the restore path changed, only its addresses.

They are worth distinguishing. The first was *dead work*: glyphs address everything as
`(bufp),Y` and never read `svp`, so 21 walks a frame were maintaining a value that
`SprDigitBlock` then overwrote. The second was *redundant state*: every term of `bufp` is a
multiple of 8 except the scanline, so `bufp AND 7` **is** the scanline and the counter beside it
was never needed. The fourth was *work off the end*: row 20 is blank for every droid, so its
whole iteration and the advance into it drew nothing anyone reads. Only the third was ordinary
cycle-shaving — and it was the largest single win, which is worth remembering before assuming
the clever ones pay best.

**What is left.** Compiling bought the rotor and the digits; these five bought the walk, and the
walk is now spent — what remains of it is `SprBlkSave`/`SprBlkRest`'s 16 steps and the 26 in the
row loops, all of them advancing to a row that genuinely draws.

The step-5 tax was worth naming: three glyph *positions* would have meant offsetting eight
pointers each, which is most of the win. Moving the position out of the pointer and into Y
(`LDY drYcol0,X`, position held in X across the glyph) costs two cycles a column instead of ~100
a position, and it is what lets one set of pointers serve all three. The same trick is why the
shifted glyphs' spill into a shared column still lands correctly: position *p* column 2 and
position *p+1* column 0 are both Y = (*p*+1)·16.

#### Step 3b — dispatch and the row loop

Dispatch (~1,000) and the 21-row interpreter loop (~1,150) looked structural — removable only by
compiling a whole sprite per type × phase × alignment, the 25K option deliberately not taken.
They were not, because of one observation: **the ten rotor rows a sprite draws are fixed once its
shift and phase are known.** The sequence is a property of (shift, phase) — sixteen of them — not
of the sprite, so it can be listed rather than derived per row.

Two changes fall out of that:

- **`drSeqLo/Hi`, ten addresses per (shift, phase) in drawing order.** Dispatch becomes an indexed
  read and a poke: no row→slot lookup, no add, no row counter. The list is indexed by **X**, not
  Y — the compiled rows use A and Y and would eat an index kept in Y.
- **The fast path writes the shape out.** A sprite that cleared the wrap test has no row that
  *can* wrap, so its shape is a constant: five rotor rows, a blank, the digit block, a blank,
  five more. That removes the row counter, the blank-row lookup and the end test from every
  iteration — everything the loop did to discover what it already knew.

The interpreted loop stays for the one sprite in five that fails the wrap test, since only a
per-row test can decide which rows fall back. But it now runs *only* with `sprNoWrap` clear, so it
drops that test from every row and its digit-block arm goes entirely — the block never opens
there.

**−986 cycles for +192 bytes of bank** (640 of lists against 448 of dispatch tables deleted). The
alternatives were costed and rejected: fully unrolled `JSR` programs per (shift, phase) buy ~1,220
for ~2,150 bytes, and putting the walk inside every compiled routine buys ~1,360 for ~2,370 —
neither fits, and neither survives the fact that the fallback path keeps the old tables alive.
Both become affordable only with a second bank paged in for the sprite phase.

> **The tile map now has a fixed home at `&3800`.** It used to sit at the next page boundary after
> `code_end` — fine while the code was small, and silently over the sprite save areas at `&3000`
> when it was not. This step is what made it not: the first build put it at `&2D00–&3100`, on top
> of slot 0's saved background, with no assert to catch it. There are asserts now. `&3700–&47FF`
> is clear, and the move takes code headroom from 143 bytes to 1,005 — the constraint that would
> have blocked the next layer regardless.

#### Step 3c — a bank of its own, and the full unroll

The blitter now has **SWRAM_SPR to itself**: artwork, compiled rows, glyphs and programs, with
tiles, levels, palettes and the droid game data left in `SWRAM_DATA`. Only one bank is visible at
a time, which works because the two halves are never wanted at once — `DoRedraws` reads tiles,
the blitter reads none of that, and they run at different points in the pass. `SprRestoreAll` and
`SprDrawAll` swap around themselves, so the data bank is the resting state and no caller has to
know. Two swaps a pass, 8 cycles each. The IRQ was the thing that could have broken it and does
not: `RuptVSync` and `RuptTimer` read nothing out of either bank.

With the space, the two options costed and rejected at step 3b both land:

- **C — every compiled rotor routine ends by walking a scanline.** The walk was the one thing
  that had to happen between rows, so putting it inside each row leaves nothing between them.
- **B — a straight-line program per (shift, phase).** Sixteen for the draw, sixteen for the
  restore: ten `JSR`s with the digit block and the two blank rows in the middle. Entering one is a
  table read, a poke and a `JMP` — the program ends in `RTS`, so the tail call returns straight to
  `SprDrawSlot`'s caller. A rotor row costs a `JSR` and an `RTS`.

Then two more, both from reading the generated programs rather than the model. **A `JSR`
immediately before the program's closing `RTS` is a tail call written the long way** — `JMP`
instead, 9 cycles and a byte cheaper, on both sides. And **the restore's ten calls are five
identical pairs**: a restore routine is keyed on the column set, only four sets exist, and which
one a row uses depends on nothing but shift and *phase>>2*. So the ten collapse to two calls into
a routine per half with all five rows inlined — eight routines cover all sixteen sequences, 8 of
the 10 `JSR`/`RTS` pairs gone, and the bottom half can simply omit its final walk because nothing
reads the pointers after it. That last point collects the 42 cycles the unroll had been wasting.

The draw gets only the tail call: its ten rows are ten *different* routines (00,02,04,05,06 |
06,05,04,03,01), and merging them would need a copy per phase of the rows that are currently
shared.

**−477 cycles for the bank move and the unroll, then −165 more for the roll-up.** Less than the −1,220/−1,360 those options were worth against
the step-5 baseline, because step 3b's sequence dispatch had already taken most of it — worth
knowing before costing an option twice.

The fallback keeps the sequence lists and the per-row wrap test, since only that can decide which
rows drop to the slow path. But the compiled rows it calls now walk on their own account, so it
needs a tail that does not walk again: `sd_nextnw`/`sr_nextnw`, taken only from the self-modified
call site.

> **Two beebasm mechanics, both learned the hard way.** `CLEAR` is what lets `&8000-&BFFF` be
> assembled twice — beebasm tracks written bytes and refuses to overwrite them. And **`SAVE`
> writes whatever the image holds at the time it runs**, so each bank must be saved where it is
> assembled; both `SAVE`s left at the bottom of the file silently wrote the sprite bank into
> `PARADAT`, and the deck rendered as garbage with droid types of 164-169.

> **The save areas differ between builds, in bytes nothing reads.** A slot's 256-byte page is only
> partly covered — blank rows save nothing, a compiled row saves only the columns it draws — so
> the rest keeps whatever the staging copy left at `&3000`, which changed when `PARASPR` arrived.
> The play buffer being identical is the proof it does not matter: the save area exists only to be
> read back into the buffer, so a differing byte that was ever read would show up there.

#### Step 3d — the glyphs save what they draw

The digit block still saved all seven columns of all eight rows in a pass of its own before the
glyphs drew. That existed for a stated reason: under a 2 px shift a glyph was expected to spill
into the next position's first byte, so two positions would share a column and neither could own
saving it.

**It never spills.** Every glyph's rightmost two pixels are blank, so the generated code uses
relative columns 0 and 1 and never 2 — 120 and 143 uses of `drYcol0`/`drYcol1` against **zero** of
`drYcol2`. The three positions are therefore disjoint (columns 0-1, 2-3, 4-5) and column 6 is
never written at all. The premise the hoisted save was protecting against was vacuous for this
artwork all along.

So the save folds into the draw, where the byte is being loaded anyway: one extra `STA (rowq),Y`
per position. All sixteen of a glyph's positions are saved, transparent ones included, so
`SprBlkRest` stays generic — over six columns now, not seven. `SprBlkSave` is gone entirely, and
with it a whole extra walk of the eight scanlines: `SprBuildRowPtrs` now fills both pointer sets
in one pass and leaves `bufp`/`svp` on row 14, which is exactly where the save pass used to leave
them.

**−564 cycles**, better than the ~500 estimated, because deleting the save pass took its eight
`SCANSTEP`s with it. Cost: 16 more bytes of zero page for `rowq`, and the glyph code grows from
2.7K to 3.7K.

> The blitter now depends on a property of the *artwork* rather than of the geometry, so the
> exporter asserts it: a glyph that ever emitted a lit pixel in column 2 would corrupt its
> neighbour's saved background silently.

**What is left.** Per sprite is now ~3,000 of real pixel movement and ~2,800 of everything else,
of which the largest single items are the six inactive slots scanned every frame (~630) and the
per-slot setup (~480). Nothing structural remains, and nothing needs to.

#### Why not round-robin

Every earlier note here treated round-robin as the next step and the biggest remaining lever. It
is neither, and the reason is the work above. **The loop spends 39,212 of its 79,872 cycles idle
— 49% of the pass** with all seven sprites live. Round-robin would buy back ~20K of a budget that
already has 39K spare.

It is also not free, which the earlier notes never costed:

- **Overlap.** The order — restore *all*, scroll, draw *all* — exists because drawing one sprite
  while another is still on screen captures the second one's pixels into the first one's save
  area, and restoring it later stamps them permanently into the buffer. Round-robin breaks that
  invariant by construction, and the corruption is permanent rather than transient.
- **Scroll bands.** A sprite left undrawn keeps its correct world position — the buffer is
  circular and the world moves with it — but if `DoRedraws` repaints a band over it, its saved
  background is stale and restoring it writes old pixels over new. That only shows while
  scrolling, which is where the oracle is weakest.
- **Visible cost.** At four slots of seven a pass, droids animate and move at ~14 Hz against the
  player's 25.

If a later layer does eat the headroom, measure first: `RunDroids`, pathfinding and slot
allocation are budgeted at ~14,000 cycles on the C64, which would still leave ~25K spare. The
cheap half-step, if it is ever needed, is not round-robin but **skipping a sprite that provably
cannot have changed** — same screen position, same rotor phase, no scroll, no overlapping sprite
redrawn. That is correct with no visual cost at all, though it only pays when droids are
stationary or low-energy, since `SPR_SPIN = 0` advances a full-energy rotor every pass.

> **Measuring across builds.** Average over ~128 passes, not 16: the rotor phase cycles every 8
> and the per-phase spread is a few hundred cycles, so a short average is biased by which phases
> it caught. There is also a ±50-cycle floor between builds from `abs,X` lookups landing on
> different sides of a page boundary once the code shifts.

> **Drive the scroll by patching `ReadKeys`, not by holding a key.** A keypress injected at a
> fixed cycle count lands a pass earlier or later once the code speed changes, and the two runs
> then diverge for reasons that have nothing to do with the change under test. Half an hour went
> into a 38-byte difference that was entirely this.

> **Check `code_end` against the stub address after every build.** The measurement and input
> stubs live between `code_end` and the tile map at `&2C00`. Step 3a moved `code_end` from `&2B7B`
> to `&2BA4`, and a stub left at `&2BA0` lands on `vsyncCount` and `oldIrq1V` — which reads
> exactly like a sprite bug that only appears when scrolling.

> **Anchor the rotor phase before the counted passes.** The oracle parks the game after N passes
> by patching the `JMP` at the bottom of the main loop, but that patch is installed at a fixed
> cycle count — and once the code speed changes, the two builds are not in the same pass when it
> lands. Step 4's builds parked **three passes apart**. The signature is unmistakable once seen:
> every rotor row of every sprite differs and the digit rows match exactly, because the rotor
> depends on phase and the digits on type. Zero `sprFrame` and `sprDelay` before the counted
> passes. Safe to do mid-run — the restore replays `sprTabBaseS`, which records the phase the
> draw actually used.
>
> **And anchor it at a LOGICAL point, not a cycle count.** Zeroing `sprFrame` mid-pass lands
> either side of `SprAnimateAll` depending on where that build happens to be, so the two runs
> still come out one phase apart — the same signature, and step 5 hit it after step 4 had already
> established the rule. Park first, zero while parked, then resume: write `JMP` *the park
> routine's own resume path* over the self-park, run ~2000 cycles to let the CPU out, and put the
> self-park back. Check afterwards that `sprFrame` is exactly `passes MOD 8`.

### Layer 6 — Droids
`RunDroids`, `dMd0_droid`, sprite slot allocation, pathfinding. Droids move and chase.

### Layer 7 — Combat
`dMd1_bullet`, `dMd2_explosion`, `DoCollision`/`DoCollision2`, `DoScore`, `KillDroid`,
`DoAlertAndAging`. The core game is playable at this point.

### Layer 8 — Doors, lifts, decks
`OpenDoor`, `CloseDoors`, `DoLift`, `FindLift`, `ChangeDeck`. The whole ship becomes traversable.

### Layer 9 — HUD and console
The mid-frame split already exists (Layer 3c/3d) and the panel is a placeholder bordered box at
`&4800`. This layer fills it with real content: `Console`, `con_DroidInfo`, `con_DeckInfo`,
`con_ShipInfo`, side view. Also the point to revisit the panel palette — it currently shares the
play area's four colours and so changes with the deck.

### Layer 10 — Transfer minigame
`SubGameSelectSide` and the circuit puzzle. Paged from SWRAM bank 1.

### Layer 11 — Sound, title, polish
SN76489 driver replacing the SID engine, title screen, attract mode.

## Master-only extensions

Things the port could do on a Master 128 that a Model B cannot host, kept together so the Model B
path stays readable. **None of these are on the critical path.** `PLAN.md`'s target is a Model B
with two sideways RAM banks; anything here either forks the rendering path or makes the port
Master-only, and that is a decision not yet taken.

### ⏸ 2 px horizontal scrolling, via shadow RAM

The scheme Layer 4a rules out on a Model B — two 10K circular strips, a second copy of the map
offset by 2 px, alternating which one R12/R13 points at. It fails there because a circular strip's
period must equal the hardware wrap span and only one wrap region exists. It is not a compromise
version of that idea; it is the *same* idea, which the Master can actually host.

**The mechanism.** Both buffers sit at the same address, `&5800–&7FFF`: one in main RAM, one in
shadow. Same 10K wrap, same R12/R13, same scroll arithmetic, same everything — the only difference
between displaying A and displaying B is one bit of ACCCON (`&FE34`): `D` selects which RAM the
video fetches from, `X` selects which one the CPU sees at `&3000–&7FFF`. So none of the addressing
problems that kill it on a Model B arise; we are not fitting two strips into one wrap region, we are
using the same region twice over. Flip `D` in the VSync handler and the view is 2 px further along.

**Confirmed by KC, not assumed:**
- The Master's screen wrap is driven the same way as the Model B's — the System VIA addressable
  latch — so the 10K/`&5800` setting and everything derived from it carries over unchanged.
- Writing ACCCON's `D` bit takes effect **instantly**, including mid-scanline. Per-field switching
  is therefore trivially safe; mid-scanline switching is a whole other technique and a conversation
  for another day.

**Why it is parked: cost, not feasibility.** Either buffer might be the one displayed next field, so
both must be current at all times. Every edge redraw and every sprite blit happens twice.

- It is cheaper than a straight doubling. B's exposed edges can be produced by *shifting bytes out
  of A* rather than redrawing from the tile map, which skips the tile → character → charset
  lookups — and those are the expensive half of a band, not the copying. Call it +60–80% on the
  drawing rather than +100%.
- Even so that is roughly +12–16K cycles a frame against about 5K spare. It needs the optimisation
  backlog at the end of Layer 4 spent (~14K identified) or a smaller play area, or both.

**Revisit when** the frame budget has real headroom — most likely after `PARADAT` moves to sideways
RAM and Layer 4's inlining work is done — or if the target ever moves to the Master. The dead-zone
camera already fixes the case that actually looked bad (the world lurching when you creep), so this
buys smoothness at moderate speeds rather than curing a defect.

## `src/` as it stands

Single-pass flat build, everything included from `main.asm`. No linker.

| File | State |
|---|---|
| `main.asm` | **Live.** Constants, memory map, main loop, IRQ dispatch. Geometry constants live here because beebasm resolves them in file order and the other files need them. |
| `rupture.asm` | **Live.** Three-cycle vertical rupture, the T1 state machine, `FillPanel`, `DbgSetBg`. |
| `screen.asm` | **Live.** `SetupScreen`, `SetCRTCStart`, `DrawHalf`, `HalfPtr`, `BandSetRow`/`BandCharPtr`, `ColSetup`/`ColCharPtr`, `MapChar`, `RedrawAll`, buffer wrapping. |
| `scroll.asm` | **Live.** Offset tables, `SetCell`, `DrawColumn`, `DrawBandRows`, `DoRedraws`. |
| `level.asm` | **Live.** Deck decode, `BuildCharset`, `BuildLUTs`, `SetPalette`, `CentreOnDeck`. |
| `zeropage.asm` | **Dead** — not included. Inherited scaffolding; the live ZP map is in `main.asm`. |
| `hardware.asm` | **Dead** — not included. Inherited; live register definitions are in `main.asm`. |
| `macros.asm` | **Dead** — not included. `CRTC` and `ADDPTR` macros live in `main.asm`. |
| `hal_video.asm` | **Retired** — Master/MODE 2, unverified CRTC arithmetic, carries `TODO`s. Do not build on it. |
| `hal_irq.asm` | **Retired** — assumes Master shadow RAM and a HAL we are not building. |

Five of these ten files are not in the build. Worth deleting the three dead ones and the two retired
ones before Layer 4 adds more, so that what is on disc is what runs — but check nothing wanted is
buried in them first.
