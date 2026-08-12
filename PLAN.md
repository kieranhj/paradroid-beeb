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
pathfinding and sprite slot allocation. There is ~14,000 cycles of identified but unclaimed
optimisation listed at the end of Layer 4; spend it when droids start competing for the frame.

**Before trusting any speed number, read the speed model section of Layer 4.** The C64's constants
are per `GameLoop` iteration and an iteration is 2–3 frames, not 1. Every droid speed in
`PlayerSpeed_t` needs the same conversion, so this will come up again immediately in Layer 5.

Three things anything drawing into the play buffer has to know:

1. **Display row 0 is a split row** — it can hold two map rows at once, in disjoint scanline
   ranges. Anything writing whole cells into it must repair scanlines `0..line-1` from map row
   `mapYr+16`, the way `DrawColumn` and `RedrawAll` do. This has already caused one bug. The player
   sprite sidesteps it by construction: it sits in strip rows 6-9 and cannot reach rows 0 or 15.
2. **Adjacent 4-pixel columns are 8 bytes apart, not 1.** Consecutive bytes within a column are
   consecutive scanlines. This cost a build.
3. **The draw window is frame rows 23 → 8 of the next frame**, released by `drawFlag` at `P+184`
   when the play area stops displaying. Everything shares it, and it is already full.

**Verification that actually works here:** diff the play buffer against `RedrawAll` at the same
position (SPACE), byte for byte. Screenshots have repeatedly said "fine" when it was not. Drive it
over **odd and even** `mapHX`, **non-zero `line`**, and **diagonals** — every scrolling bug so far
has hidden in one of those. Allow ~1,500,000 cycles to settle before dumping, or the oracle is
sampled mid-redraw.

**Open items, in the order they are likely to bite:**

| | |
|---|---|
| 1 px sprite positioning | Needs four shifted copies, 1820 bytes — waiting on `PARADAT` moving to sideways RAM. 2 px matches the C64 artwork's own pixel size. |
| 2 px world scrolling | Master-only via shadow RAM, and now **planned in full** — see **Master-only extensions**. Costs +60–80% on all drawing because both buffers must stay current, so it fits today with the player alone but not with a full droid pool. Two free perceptual A/Bs come first: at 25 Hz the frame rate may already be the coarser quantum. |
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
| Inline `CopyRun` / `BufNextUnit` / `CellXInc` — 72 cycles of call overhead per character | ~5,800 |
| Sprite: precompose the current phase instead of `PlyFetchRow` per row | ~2,500 |
| Cache the previous frame's 40 row pointers — group 2 of frame N is group 1 of frame N+1 | ~2,300 |
| Unroll `DrawColumn`'s 8-byte copy | ~1,300 |
| Replace `keydown`'s OSBYTE `&81` with a direct System VIA matrix scan | ~2,000 |

**The deadlines are staggered and tighter than a frame**, which matters more than the frame total:
an **up**-band and the columns both display at `P+64`, so they share only 192 scanlines (24,576
cycles), while a **down**-band has until `P+184` of the next frame.

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

5. **Round-robin updating** — still the step that buys the pool its headroom, but no longer urgent
   for correctness now the rate is fixed: 25 Hz gives ~80,000 cycles a pass against ~68,000 spent
   on seven sprites. Not started.
6. **Raster-ordered updating** — flicker, and probably `BUGS.md` #3 with it.

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

### 2 px horizontal scrolling, via shadow RAM — planned, not started

The scheme Layer 4a rules out on a Model B — two 10K circular strips, a second copy of the map
offset by 2 px, choosing which one R12/R13 points at. It fails there because a circular strip's
period must equal the hardware wrap span and only one wrap region exists. It is not a compromise
version of that idea; it is the *same* idea, which the Master can actually host.

**The mechanism.** Both buffers sit at the same address, `&5800–&7FFF`: one in main RAM, one in
shadow. Same 10K wrap, same R12/R13, same `scrollS`, same `line`, same scroll arithmetic — the only
difference between displaying A and displaying B is one bit of ACCCON (`&FE34`): `D` selects which
RAM the video fetches from, `X` selects which one the CPU sees at `&3000–&7FFF`. So none of the
addressing problems that kill it on a Model B arise; we are not fitting two strips into one wrap
region, we are using the same region twice over.

- **A** holds the world at the 4 px-aligned origin `mapHX * 4`, exactly as today.
- **B** holds the same origin **+ 2 px**.
- `posX` quantises to 2 px, and **bit 1 of `posX` selects the buffer.** 0 → A, 1 → B.

**This is not a per-field alternation and not a flicker trick.** One buffer is displayed for the
whole iteration and which one is a pure function of position parity. Nothing in the scroll
arithmetic changes; the CRTC still steps 4 px and the 2 px comes entirely from the choice of buffer.

**Confirmed by KC, not assumed:**
- The Master's screen wrap is driven the same way as the Model B's — the System VIA addressable
  latch — so the 10K/`&5800` setting and everything derived from it carries over unchanged, **and it
  holds for shadow fetches too**. This was the gating question; had it failed, the scheme died.
- Writing ACCCON's `D` bit takes effect **instantly**, including mid-scanline. Per-field switching
  is therefore trivially safe; mid-scanline switching is a whole other technique and a conversation
  for another day.
- `D` and `X` are independent, and ACCCON must be written whole from a shadow copy — never
  read-modify-written — because bit 7 (IRR) forces an interrupt.
- **The current Model B build already runs on a Master.** So the `&1100` code base, the `&0400`
  charset, SWRAM banks 4/5 and the IRQ1V takeover all survive MOS 3.20, and none of them are on the
  work list below. IRQ timing differences from the 65C12 and the MOS handler are taken as negligible
  for now; if the rupture drifts, `T1_PROBE` is still the way to re-derive `T1_TUNE`, and the rule
  is to err **late** rather than early.

#### Before building it: is the 4 px quantum actually what is wrong?

At `FRAME_LOCK = 2` the world updates 25 times a second, and **the temporal quantum may already be
coarser than the spatial one** — in which case halving the spatial one buys much less than the
+60–80% drawing cost is worth.

The A/B that settles this needs no new code, because the vertical axis is *already* fine-grained at
the same rate: hold M and then X at the same low speed and compare. If vertical reads visibly
smoother, granularity is the bottleneck and this is worth building. If it reads about as chunky, the
bottleneck is 25 Hz and the lever is `FRAME_LOCK`, not shadow RAM. A second free probe — force
horizontal to 8 px steps for one build — calibrates the perceptual slope 8 → 4 and so predicts what
4 → 2 is worth.

**Run both of these before writing any of the below.**

#### The 2 px shift is two tables

MODE 1 pixel *n* takes bits `7-n` and `3-n`, so shifting a 4 px column left by 2 px pulls the other
two pixels out of the next column:

```
B[u] = ((A[u] << 2) AND &CC)  OR  ((A[u+1] >> 2) AND &33)
```

Two 256-byte tables built at startup like `SPR_MASKTAB`. They must live **below `&3000`** — the
~1.1 K free at `&0C90–&10FF` — so they are readable under either `X` setting.

#### Correction: B cannot be produced by shifting bytes out of A

The paragraph this section used to carry said B's exposed edges could be made by shifting bytes out
of A rather than redrawing from the tile map. **On a Master that is not available**: `X` maps one
buffer or the other into `&3000–&7FFF`, never both, so no loop can read A and write B.

The way out is better than the thing it replaces. Every source the draw path reads lives *outside*
`&3000–&7FFF` — charset at `&0400`, tile map at `&2C00`, `tiledefs` and `charRemap` in SWRAM at
`&8000` — so **B can be drawn from the tile map with `X = 1` and no cross-buffer reads at all.** It
is the same routine with a different inner copy loop: same lookups, and the copy goes from ~13
cycles a byte to ~28. The +60–80% estimate stands; only the reason for it changes.

So the architecture is one sentence: **run the existing drawing code twice, with ACCCON `X` flipped,
B using the shifted copy loop and the other compiled sprite shift.**

#### What the memory map does for us, and to us

| Region | Effect of the `X` flip |
|---|---|
| `SPR_SAVE = &3000` | inside the shadow region, so **each buffer gets its own sprite save area at the same address, for no code at all** |
| Panel `&4800`, mask table `&5700` | also inside it — so both must be **built twice**, once per `X`. Cheap, and a silent-corruption trap if missed |
| Tile map `&2C00`, charset `&0400`, code `&1100`, ZP, stack, SWRAM | outside it — unaffected, which is what makes the paragraph above work |
| `PARADAT` staging at `&3000–&4707` | inside it, but dead after `PageDataIn`, and the load runs with `X = 0`. No action |
| `sprSaved` flags (in code space) | **shared** between the buffers. Correct only while A and B are always drawn in lockstep — a real trap if B is ever skipped |

#### Work list, in dependency order

1. **`TARGET_MASTER` build flag** and a separate SSD. Not a runtime detect — the draw path forks.
2. `shl2`/`shr2` tables below `&3000`; an ACCCON shadow-copy byte with set/flip helpers.
3. **Init duplication:** `FillPanel` and `SprBuildMask` under both `X` settings, and `LoadDeck`'s
   initial `RedrawAll` run for both.
4. **Shifted copy loop** in `DrawBandRows`, `DrawColumn`, `DrawHalf*` and `RedrawAll`, selected by a
   flag — duplicated inner loops, not a per-byte branch. **Right-edge case:** B's last unit needs the
   character one beyond the view, and at `MAX_HX` that is map column 64, which does not exist. Clamp
   `MAX_HX` by one half-character or feed a blank.
5. **Main-loop sequencing**, six `X` flips an iteration — each an `LDA`/`STA`, so the flipping itself
   is free:
   `[X=0 restore A] [X=1 restore B] [move] [X=0 redraw A] [X=1 redraw B] [X=0 sprites A] [X=1 sprites B]`
6. **Parity is part of the position and must be latched with it.** Park the `D` value alongside
   `crtcLo`/`crtcHi`/`line` under the same `SEI` in `SetCRTCStart`, and have the VSync handler write
   ACCCON from the park. Skip this and the display shows one field at a parity that belongs to the
   next position — a one-field flicker indistinguishable from "the technique does not work". This is
   the same bug Layer 3d already paid for once with `line`/`scrollS`.
7. **Sprites** use the two existing compiled shift variants (`SPR_SHIFT0`/`SPR_SHIFT2`), chosen per
   buffer from the parity. No new sprite data, no new tables.
8. **Revisit the dead-zone camera** — this is the point of the exercise. With 2 px world scroll, try
   pinning the player and compare against the dead zone, which exists only because 4 px lurched.

#### Verification

Extend the only oracle that has ever caught a drawing bug here. Dump **both** 10K buffers after
full-speed diagonal scrolling at odd `mapHX` and `line != 0`; check A against `RedrawAll` as today,
and **B against a Python 2 px shift of A**. Validate `shl2`/`shr2` offline against a reference shift
before any 6502 is written, the way the sprite compiler was validated. Sample inside the `WaitVSync`
spin and exclude the sprite footprint — both traps are recorded in Layer 5.

#### Build log — steps 1 to 4 landed

Steps 1-4 of the work list are in, and verified: **buffer B is a true 2 px shift of buffer A, 0
differing bytes in 10240**, at odd `mapHX` (137) with `line` = 1 after full-speed diagonal
scrolling, checked against a Python shift computed from A's own bytes. The unshifted checkpoint
(step 3, B as a plain duplicate) also came out 0/10240.

Four things worth carrying forward:

- **ACCCON is `IRR TST IFJ ITU Y X E D`, so X is bit 2, not bit 1.** Flipping bit 1 flips E, which
  only redirects code executing in `&C000-&DFFF` — so every write went to main RAM, both passes drew
  the same buffer, and shadow stayed the zeros it powered on with. It presents as "the second pass
  never ran". Settled by reading jsbeeb's `writeAcccon` after three emulator tests disagreed with the
  model in my head.
- **Y must be preserved.** The Master boots at `ACCCON = &18` with Hazel paged in at `&C000-&DFFF`
  and the OS keeps filing-system workspace there. `AcconInit` keeps Y, ITU, IFJ and TST and forces
  D, X and IRR off.
- **The tile map moved to `&3800`, on both machines.** The Master build pushed it past `&3000` into
  the shadowed region, where it collided with the sprite save area. The headroom below `&3000` was
  **99 bytes, not the 243 recorded above** — that figure was stale. `&3800` is space PARADAT's
  staging freed; `BuildLevel` runs once per buffer on the Master. It hands ~1K back to the code on
  the Model B as well, and leaves `&3C00-&47FF` free in both.
- **`MAX_HX` loses one character on the Master.** B's rightmost 4-pixel column takes its low two
  pixels from the character beyond the right edge of the view, and at the Model B's limit that
  character is map column 256, past the end of the tile map row. Cheaper than an edge test in the
  hottest loop.

**The shift is done with shifts, not tables.** `B[u] = ((A[u] << 2) AND &CC) OR ((A[u+1] >> 2) AND
&33)`. A pair of 256-byte tables measures the same 41 cycles a byte — the running index is in Y and
only X is left to index with, so the table form needs the same temporary — and would cost 512 bytes
below `&3000` plus a build step. The band carries its lookahead between characters rather than
looking each one up twice, so buffer B costs the same 41 lookups as A's 40, not 80.

#### Steps 6 and 8's rounding — parity is live

`DzRoundUnits` rounded the view to whole 4 px units, so bit 1 of `posX` was always 0 and buffer B
could never be selected. `DZ_GRAIN` is now 2 on a Master, and that one constant is what makes the
whole scheme visible. The parity is parked with `crtcHi`/`crtcLo`/`line` under the same `SEI` in
`SetCRTCStart` and consumed by the VSync handler, so it cannot be split across frames the way
`line`/`scrollS` were in Layer 3d.

Confirmed: with `posX` moved from 524 to 526 and nothing redrawn, `acconVal` reads `&19` and the
whole view steps 2 px. That is the technique working — a scroll step with no drawing at all.

**The sprite is not yet per-buffer, and it shows.** Both buffers get the sprite at the same
buffer-relative offset, so on odd parity it lands 2 px from where it belongs. Step 7 is what fixes
it, and the shape is now clear: the input side is a two-line transform in `SprSetSlot`
(`shift 1 → shift 0, same unit`; `shift 0 → shift 1, one unit back`), but the seven per-slot
**draw-record** arrays have to be duplicated per buffer, because `SprRestoreSlot` replays the draw's
own record and the two buffers' records differ. Culling can differ between them too, so `sprSaved`
is one of the seven.

#### The measured cost — it does not fit yet, even player-only

Player only, full-speed diagonal, `CheckWalls` poked to `RTS`, both buffers maintained:

| | measured | frame-locked would be |
|---|---|---|
| `posX` over 10 fields | **16 px** | 35 |
| `posY` over 10 fields | **14 px** | 35 |

`xSpd` and `ySpd` were both at `&0700`, so this is the loop stretching to ~4 fields an iteration,
not the player moving slower. **The "fits comfortably today" estimate above was wrong**, and the
error was in the drawing, not the sprites: the shifted copy is 41 cycles a byte against `CopyRun`'s
13, so a band costs ~3× rather than the +60-80% assumed, and `DrawColumn` falls back to the generic
uncached two-lookup path, which costs more again.

**`DrawColumn`'s fallback is fixed** and it did not need a second set of the `Col*` state after all.
The partner column is the *other half of the same character* when `halfX` is even, so `chp2` is just
`chp + 8`; when `halfX` is odd it is the next character along, which is behind the **same cached tile
pointer** unless this is the last character of the tile. So 7 columns in 8 cost a few instructions
over the straight path and only the eighth falls back to the generic per-cell lookup.

**Measured after that fix: 100,000 cycles an iteration against a 79,872-cycle budget — 25% over.**
(Measured by neutering `WaitVSync` so the loop free-runs, then timing `posY`, which advances exactly
`ySpd` per iteration. The px-per-10-fields figures above cannot show this: the overrun quantises to
whole fields, so they read 16/14 both before and after the column fix.)

~20,000 cycles have to come out. What is on the table:

- **A pre-shifted charset** takes the band from 41 cycles a byte to 29 — store `shr2` of every
  charset byte and the other half stays an inline `ASL`/`ASL`/`AND`. It is 2192 bytes and needs to be
  readable with the CPU on shadow, so it goes at `&3C00` in shadow RAM, in the space the tile map
  move just opened. Both halves pre-shifted would reach 23 cycles but needs 4384 bytes, which does
  not fit under the panel. Worth roughly 6,700 cycles on a full-speed diagonal band plus ~3,000 on
  the columns.
- **The Layer 4 optimisation backlog**, ~14K identified and still unspent — and worth close to
  double here, because inlining `CopyRun`/`BufNextUnit`/`CellXInc` saves the same call overhead on
  both passes.
- **`FRAME_LOCK = 3`** is the escape hatch if the cycles cannot be found: 119,808 cycles an
  iteration, which 100,000 fits inside, with real-time speed preserved because `player.asm` scales
  its constants by `FRAME_LOCK / PLY_ITER_FRAMES`. It buys a stable rate at the cost of 16.7 Hz,
  which is the wrong trade when the thing being judged is smoothness — but a stable 16.7 Hz is a
  far better thing to look at than a free-running 12.5.

#### Budget: what can be seen now, and what waits

25 Hz gives ~80,000 cycles a pass, and seven sprites already cost ~67.6 K of it.

| configuration | rough cost | verdict |
|---|---|---|
| player only, both buffers | ~19.3 K sprites, plus the redraw at ~+70% | **fits comfortably today** |
| 7 droids, both buffers | ~135 K on sprites alone | ~1.7× over — needs round-robin updating (Layer 5 step 5) first |

So the feel can be judged now, without spending the optimisation backlog, by building the spike with
`TEST_DROIDS = FALSE`. What that spike cannot answer is whether it survives a full droid pool; that
judgement waits on round-robin updating. Re-baseline both numbers on a Master with the User VIA T1
harness before committing — the figures above are Model B measurements.

## `src/` as it stands

Single-pass flat build, everything included from `main.asm`. No linker.

| File | State |
|---|---|
| `main.asm` | **Live.** Constants, memory map, main loop, IRQ dispatch. Geometry constants live here because beebasm resolves them in file order and the other files need them. |
| `rupture.asm` | **Live.** Three-cycle vertical rupture, the T1 state machine, `FillPanel`, `DbgSetBg`. |
| `screen.asm` | **Live.** `SetupScreen`, `SetCRTCStart`, `DrawHalf`/`DrawHalfScan`/`DrawHalfPart`, `HalfPtr`, `MapChar`, `RedrawAll`, buffer wrapping. |
| `scroll.asm` | **Live.** Offset tables, `SetCell`, `DrawScanline`, `DrawColumn`, the four scroll directions, `DoRedraws`. |
| `level.asm` | **Live.** Deck decode, `BuildCharset`, `BuildLUTs`, `SetPalette`, `CentreOnDeck`. |
| `zeropage.asm` | **Dead** — not included. Inherited scaffolding; the live ZP map is in `main.asm`. |
| `hardware.asm` | **Dead** — not included. Inherited; live register definitions are in `main.asm`. |
| `macros.asm` | **Dead** — not included. `CRTC` and `ADDPTR` macros live in `main.asm`. |
| `hal_video.asm` | **Retired** — Master/MODE 2, unverified CRTC arithmetic, carries `TODO`s. Do not build on it. |
| `hal_irq.asm` | **Retired** — assumes Master shadow RAM and a HAL we are not building. |

Five of these ten files are not in the build. Worth deleting the three dead ones and the two retired
ones before Layer 4 adds more, so that what is on disc is what runs — but check nothing wanted is
buried in them first.
