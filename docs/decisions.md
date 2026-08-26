# Decisions, and which Paradroid

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

## Decisions taken

**This table is the record, and this is its only copy** — it moved here from `PLAN.md` on
2026-08-25 when that file was slimmed to outstanding work. (An earlier era kept a copy in each
file and the copy fell out of date; one copy, linked from `PLAN.md`, is the fix.) The prose
sections below keep the *reasoning*: why MODE 1, the no-HAL rule and the files it deleted, and
the evidence for which Paradroid the listing is. Per-layer decisions are numbered in each layer's
own doc, and the RAM recovery pass's are in [`ram-pass.md`](ram-pass.md).

| Decision | Choice | Date |
|---|---|---|
| Target machine | BBC B / B+ with **4 × 16K sideways RAM banks**, numbered 4–7 as the Master does | 2026-08-16 |
| Source version | **1985 original / 1986 Competition Edition** lineage, which is what `paradroid_ce.lst` is. Redux's bug list is a spec, not code; Heavy Metal parked as a later tile set | 2026-08-06 |
| Architecture | No HAL. One working layer at a time, verified in the emulator before moving on | 2026-08-04 |
| Screen mode | MODE 1, 4 colours, **10K wrap at `&5800–&7FFF`** | 2026-08-04 |
| Screen layout | 3-cycle vertical rupture: static panel, gap, scrolled play area. The panel is **4 rows**, the C64's 32 scanlines | 2026-08-05/16 |
| Play area | **320 × 120** — 10 tiles wide, 15 character rows. The 16th row went to the single hardware wrap, which is what smooth vertical scrolling costs. **KC closed this 2026-08-21: 120 is what we ship** — the 20K wrap is not being pursued. It costs the **scrolled deck** only: with the scroll flattened the 16th row is real buffer, and every screen that is not the deck shows it | 2026-08-05, closed 2026-08-21 |
| Scrolling | CRTC hardware scroll over a circular strip. **4 px horizontal, 1 scanline vertical**. The asymmetry was left open for years and **KC settled it 2026-08-21: 1 scanline stays** — coarsening to 2 or 4 would cost nothing but buys nothing either | 2026-08-05, settled 2026-08-21 |
| Interrupts | We own IRQ1V outright, System VIA T1 continuous. No MOS chaining, no MOS sound | 2026-08-04 |
| Game loop rate | **Locked to 2 fields a pass**, not free-running — free-running made the player 20 % slower whenever droids were visible | 2026-08-13 |
| Sprite blitter | **Compiled**, not interpreted: generated 6502 per rotor row and per digit glyph | 2026-08-13 |
| The four logical colours have fixed roles | 0 the deck's background, 1 black, 2 the deck's highlight, 3 white. Chosen for the sprites, and what makes a sprite byte its own transparency mask | 2026-08-17 |
| Sprite colour is not baked in | The artwork is logical 3, so choosing a colour is choosing a nibble, and eleven zero page bytes carry it. Enemies black, player white, the deck's highlight in transfer mode, a 4-field flash below energy 8 | 2026-08-19 |
| Player top speed | **8 px a pass, not the C64's 7** (`CAM_TOPSPD`). 7 cannot divide the CRTC's 4 px step, so the camera dithers. 14 % fast, bought deliberately | 2026-08-14 |
| Player speed on a *slow* ride | **4 px a pass** (`CAM_SLOWSPD`) for `PlayerSpeed_t`'s 5 and 6 alike, which dithered the same way and made a slow droid jerkier than a fast one. `plySpdTab` is now `0,4,4,0,8,0,0,0,8` — a ride is fast or slow, nothing between. With `CAM_TOPSPD` these are the only movement numbers not from the original; enemy `DSpeed_t` is untouched. [layer-10 DECISION 11] | 2026-08-21 |
| **ESCAPE ends the game** | The port's own feature, not the C64's — its only abort is the RUN/STOP `DoPause` reads, which pauses. ESCAPE kills the player **as a 001**, so `CbCheckDeath`'s existing "a 001 has nothing to fall back on" arm ends the game through the whole death, wash, 999 page and title. It replaced `DEBUG_RESTART`, which is gone. `OSBYTE 229,1` makes ESCAPE an ordinary key so the escape condition cannot break `GoTitle`'s loads. [layer-11d DECISION 5] | 2026-08-21 |
| The disruptor's screen shake | **Not ported.** The strip is 16 rows in one hardware wrap, so a CRTC jitter fetches rows that were never drawn. Palette flash alone | 2026-08-19 |
| The ALERT lamp's four colours | **Four states, not four hues** — MODE 1 has no fifth colour. Black, the deck's highlight, white, white blinking. The blink is a deviation; **KC 2026-08-21: it stays for now and gets another look in layer 14**, once every palette is settled in one sitting | 2026-08-20, revisit in 14 |
| Code may live below `&1100` | The reclaimed DFS/OS workspace at `&0C90`–`&10FF`, staged and copied after the last `*LOAD`. Page `&0D`'s NMI half stays untouched | 2026-08-20 |
| The title is a disc overlay, and a game over reaches it | `PARTITL` at `&3000`, loaded by `TitleSeq` at boot and after a game over ([DECISION 6] restored); `GoTitle` tears the IRQ down, restores the MOS's VIA state and the DFS workspace snapshot, and rebuilds. Layer 13d | 2026-08-20 |
| The droid portrait is ported | Reversing layer-11's [DECISION 3]: the pool is 4,032 B of verbatim C64 sprites, expanded at draw time — the 6 K / 24 K costing that deferred it was wrong | 2026-08-20 |
| The deck maps ship ZX0-compressed | Decoded offline, byte-identical maps; the C64's RLE and both its decoders are gone, and bank 4 got ~1.1 K back. sideview stays in bank 7 — the approved move to bank 5 was unbuildable, `dfsSave` moved to bank 6 instead | 2026-08-20 |
| **The picture sits 3 rows lower on the tube** | `FRAME_DROP_ROWS` moves VSync three rows earlier (`TAIL_R7` 8 → 5) and `T1_I1` the same three rows later, so the panel and play area drop 24 scanlines without the frame or the cycles changing. KC tried four and it looked low. It forced `R7 = 255` out of fire 1 and into `RuptVSync`: at any `TAIL_R7` of 7 or below the 7-row panel cycle reaches the stale value and fires a VSync of its own, which blanked the play area entirely. **The title follows it**: `TiCRTC` sets `TITLE_R7 = 34 - FRAME_DROP_ROWS`, which is the same gap from VSync expressed in its own 39-row frame, and is the OS's own 34 when the drop is zero. [`layer-3-scroll.md`](layer-3-scroll.md) | 2026-08-21 |
| **Every non-gameplay screen shows all 16 rows** | Started 2026-08-16 as the transfer board alone, on a variable fire-2→3 interval (`t1i3`); the lift's deck select and the deck plan followed. Now the console and its three pages, the four information screens and the game over's wash have it too, so **only the scrolled deck is 15 rows**. Set on entry, restored in **one** place — `ReframeView` — which freed 47 B of bank 4. The **ported** pages (database, information screens, game over) moved down one row onto the C64's own rows; the console main screen stays plotted from row 0 per KC's earlier rule. [`layer-9-hud.md`](layer-9-hud.md) §6g | 2026-08-16, extended 2026-08-21 |
| The four banks ship ZX0-compressed on disc | Boot 14.4 s → 10.4 s measured. `PARDEPK` (an eighth disc file, the same depack macro as bank 4's) unpacks each bank from `&3200` straight into SWRAM; `tools/make_disc.py` compresses and lays the disc out in boot access order after beebasm — **the raw beebasm image is no longer bootable**. [`loader-compression.md`](loader-compression.md) | 2026-08-21 |
| **The Redux added-features triage** | All of https://paradro.id/'s enhancements ruled on with KC, 2026-08-26. **Adopted**: explosions no longer restarted by the disruptor/bullets; the three-droid-deadlock randomisation (if our port reproduces the deadlock); lift-adjacent waypoints excluded from droid starting points; high-score entry remembers the previous initials. **Rejected for 1.0**: the droid AI pack (flee/pursue/energizers/alert fire), radar, security doors, Redux scoring (accuracy/pacifist/alert bonuses — CE scoring stays, damage tables stay CE's too, laser swap included), transfer pulser-count link, randomised/spawn-point/deck-section map changes, disc-saved high scores, F7/F8 ship carryover, Competition Mode, F3 statistics, a shipped cheat mode (DEBUG_* builds remain the cheat surface). §12b records the detail | 2026-08-26 |
| **The RAM recovery pass** | Five commits, 2026-08-25: dead tables deleted, the effect blitter to bank 5, the boot loop to `PARDEPK`, one droid-icon copy in main RAM, `PAGEBANK`/`PNMIRROR` as subroutines. Main RAM 2 B → 639 B, every other region up too, for ~57 cycles a pass. [`ram-pass.md`](ram-pass.md) has the decisions, the rejections and the reserves | 2026-08-25 |

### How the bank count grew from two to four

`PLAN.md` carries only the settled answer, so the steps are here. Each was forced, not chosen, and
the shape of the argument matters more than the dates: every increase came from **code**, not data.

| | | |
|---|---|---|
| **2 × 16K** | the original target | 2026-08-04 |
| **3 × 16K** | a compiled shift is ~5.5 K of generated 6502 and 1 px positioning needs four of them, so the blitter alone outgrew one bank. [`layer-5-blitter.md`](layer-5-blitter.md) records the alternatives costed against it | 2026-08-14 |
| **4 × 16K** | bank 7 for Layer 10's transfer game, which keeps `xfer_DoColumn` and the rest verbatim on a shadow screen. Banks 4–7 is the Master's own sideways RAM numbering, so the port uses it on a B too | 2026-08-16 |

**Four is settled** (Layer 13a, 2026-08-19): the four hold ~57 K of the 64 K they offer with ~7 K
free across them, and three banks are 48 K and cannot take it. A machine with fewer is not a
supported target — 13b is where the build learns to say so rather than writing into ROM.

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

- player able to pass through walls by abusing asymmetry in the wall collision check
- `DroidNear()` returning true for faraway droids
- droids losing waypoints when bumped mid-transition; waypoints ignored when a droid paused on
  entering one; waypoints checked twice as often as necessary
- non-visible area scanned differently in each direction
- droid mode occasionally uninitialised, exploding droids on deck entry
- the exploding-droid event bugs: a transfer with a droid exploding that frame produced "droid
  402" (index $40, the explosion); a multi-collision involving an exploding droid could lose a
  droid; the player bumped off an explosion as if it were a 402-type droid
- the last waypoint of the maintenance deck sending droids into a wall

**The laser 1/2 damage swap is NOT in this list — KC ruled 2026-08-26: preserve CE's damage
tables in full** (the swap, the friendly-fire asymmetry, the explosion damage), as `layer-12-balance.md`
§12b's ported-bug precedent already had it. An earlier version of this list included the swap
and contradicted 12b; this ruling closes it.

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
