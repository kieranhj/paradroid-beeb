# Decisions, and which Paradroid

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

## Decisions taken

**The table of record is in [`../PLAN.md`](../PLAN.md) — "Decisions taken"** — and is not
duplicated here, because a copy of it in this file fell out of date (it still said two sideways
banks and a five-row panel). This file keeps the *reasoning*: why MODE 1, the no-HAL rule and the
files it deleted, and the evidence for which Paradroid the listing is. Per-layer decisions are
numbered in each layer's own doc.

### The no-HAL rule, and the five deleted files

An earlier iteration of this project designed a hardware abstraction layer up front, targeting a
Master 128 in MODE 2 with shadow-RAM double buffering. That was explicitly rejected in favour of
building one verified layer at a time. Five inherited files from that era survived in `src/`
without being in the build — `zeropage.asm`, `hardware.asm`, `macros.asm`, `hal_video.asm` and
`hal_irq.asm` — and were deleted rather than left to be mistaken for live code; `hal_video.asm` in
particular carried unverified CRTC arithmetic with `TODO: verify in emulator` still in it. They
are in git history if ever wanted (`git show <rev>:src/hardware.asm`). The only content with a
future was `hardware.asm`'s SN76489 encoding, now recorded — still unverified — in
[`layer-11-sound-title.md`](layer-11-sound-title.md).

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
> "tight". Both were wrong — see [Layer 1](layer-1-graphics-pipeline.md).

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
