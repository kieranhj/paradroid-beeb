# Paradroid → BBC Micro Model B: Port Plan

**The live planning document. Read it at the start of a session: it is the state of the port and
the list of what is left, and nothing else.**

Everything *finished* keeps its detail in [`docs/`](docs/) — the measurements, the dead ends, and
the options that were costed and deliberately rejected. When a layer's detail stops being needed to
decide what to do next, it moves there. `CLAUDE.md` holds the standing rules, the build, the
hardware facts and the memory outline, and is loaded every session, so this file does not repeat
them.

| | |
|---|---|
| [`BUGS.md`](BUGS.md) | **Open defects, indexed in a table at the top.** Fixed entries stay, for what they ruled out |
| [`docs/memory-map.md`](docs/memory-map.md) | The map, from a label dump — every region of main RAM and all four banks, plus which source file lands where |
| [`docs/decisions.md`](docs/decisions.md) | **The decision table of record**, plus the reasoning — why MODE 1, the no-HAL rule, and the evidence for which Paradroid the listing is |
| [`docs/ram-pass.md`](docs/ram-pass.md) | The 2026-08-25 RAM recovery pass — what it bought, what it rejected, the reserves left, and the corrected buffer-diff oracle recipe |
| [`docs/graphics.md`](docs/graphics.md) | Where the C64's graphics live, which tool reads them, and per section what is ported |
| [`docs/raster-timing.md`](docs/raster-timing.md) | **Where the main loop sits against the beam** — the frame, what writes the buffer when, and the flicker work |
| [`docs/human-notes-status.md`](docs/human-notes-status.md) | KC's polish notes, reconciled item by item — nearly all closed; the record of each fix |
| `docs/layer-*.md` | One per layer, linked from the layer table at the end |

## Where we are

**Everything is built except Layer 12 and real-hardware testing.** The port boots to a complete
game: the C64's status box above a 320 × 120 play area scrolling eight ways at 25 Hz, sixteen
traversable decks of patrolling, fighting droids, the console with all four pages, the transfer
minigame with all three outcomes, the lift screen, the droid information screens, sound
throughout, the title / high-score / five-page briefing front end, and the endgame — decks clear
for 500, ships clear for 2,000 and hand over to the next, names cycling under a difficulty that
caps at ship 8, so the game is survived rather than won. Since 2026-09-01 **every screen swap
hides its drawing** (black in, revealed complete — layer-8b §4b–4d), **every key binds except
ESCAPE and CTRL**, and **fire or transfer starts the game**. The boot chain is `!BOOT` → `PARSWR`
(banks probed, 4–7 not assumed) → (`PINTRO`) → `PARA`; `build.ps1 -Release` is the build for
other people. Keys and controls are in `README.md`;
[`docs/layer-11f-frontend.md`](docs/layer-11f-frontend.md) §8 has the redefinition mechanism.

**The frame budget:** the eight sprite slots cost ~36,000 cycles of the 79,872 in a pass and the
droid AI another ~17,000, so the loop keeps roughly a third spare. **RAM is the tight one:** main
RAM is down to **3 B** (`code_end` `&2FFD`, 2026-09-01), bank 4 to **14 B** — the RAM row below
has the rest, live numbers come from the build output, and the reserves still sellable are in
[`docs/ram-pass.md`](docs/ram-pass.md). The stack page's `&0100–&017F` (128 B, measured free) is
the largest contiguous main RAM left.

> **Before trusting any speed number, read the speed model section of
> [`docs/layer-4-player.md`](docs/layer-4-player.md).** The C64's constants are per `GameLoop`
> iteration and an iteration is 2–3 frames, not 1. Every droid speed in `PlayerSpeed_t` needs the
> same conversion.

## What is left

### Layer 12 — balance, fidelity and feel

Not a feature layer: **verify before tuning**, or a fidelity bug gets balanced around instead of
fixed. [`docs/layer-12-balance.md`](docs/layer-12-balance.md). 12b (the Redux adoptions) closed
2026-08-31; still open:

- **12a — the fidelity audit against the listing**: constants, tables and behaviour, routine by
  routine.
- **12c — playtesting against the isolated dials** (`PLY_ITER_FRAMES` and friends).
- **12d — performance**: the droid worst case has never been measured — 8 slots (~36,000) +
  droids (~17,000) + full-diagonal level draw (19,172) is ~72,000 of 79,872 before the rest of
  the loop. It wants a rig on a deck with a long open corridor; `docs/raster-timing.md` Step 3
  is the planned relief. Graceful degradation if it overruns.

### Layer 13c — the machines people actually have

Everything needing real hardware, in one place ([`docs/layer-13-compatibility.md`](docs/layer-13-compatibility.md)
holds 13b, the probing half, which is done):

- **The rupture goes up mid-frame and a TV can lose lock** — a roll or tear into a game and
  after a game over. Candidates: switch on a field boundary, order the writes so the frame stays
  legal at every step, blank across the change. Mind the R5/R6/R7 write-window rules in
  `CLAUDE.md`; nothing measured yet. *(The one 13c item that is code work, not just a check.)*
- `FRAME_DROP_ROWS` = 3 was chosen against emulators; a real television crops differently. One
  constant in `main.asm`; the title follows it.
- The briefing scroller's top line flickers more on real hardware (KC) — §4e-2's measurement
  method applies: sample `iline`, not the counters.
- Five keys held can phantom a sixth on the diode-less matrix. Debug keys are CTRL-gated now,
  but a phantom landing on a *control* is untested.
- 8 decks draw ALERT in multicolour — faithful to the C64, worth an eye on a CRT.

### Features and polish, all small

| | | |
|---|---|---|
| Collision box shape | **Agreed 2026-08-18, unbuilt.** `DR_COL_W`/`DR_COL_H` become a generated silhouette profile instead of a rectangle, at box-test cost. [DECISION 1] in [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md); `BUGS.md` #7b's bounce tuning waits on it | agreed |
| Layer 14 leftovers | An eye for any remaining character whose C64 colour merges in MODE 1 (the lift tile was one), and the open question at the end of [`docs/layer-14-visual.md`](docs/layer-14-visual.md): deck 5 is scheme 6 yet carries scheme 0's collision — intended, or slipped? | eye pass |
| Enemy bullet flicker / explosion multicolour | `efAlt` from bank 5 plus a second per-entry field; effect sprites run the interpreted path (`src/sprfx.asm`) and are one colour. The explosion-multicolour note from KC's list is the same mechanism | deferred (L7) |
| Briefing exit-load trim | The briefing → game reload is ~1.1 s naive; deferred from 11f | later |
| Redux adoptions (2), (3), (6) | Parked with their evidence in [`docs/layer-12-balance.md`](docs/layer-12-balance.md): the three-droid-deadlock randomisation (reproduce it here first), lift-adjacent waypoints excluded from starts, and the lift screen colouring completed decks — (6) parked on bank 7 space | parked |
| Intro droid cards | White background on the C64; ours differs (KC's note) | eye pass |
| Front-end text | Scroll-text wording update (KC's), and a Beeb credits page | KC |
| Blanking amount | KC's standing caveat: the load/seam blanking is aggressive — "may be too many black screens" — and the 2026-09-01 hide-the-drawing pass leaned further in. Watch for it in playtesting | watch |
| 2 px world scrolling | Parked, Master-only via shadow RAM. Costs +60–80 % on all drawing — [`docs/master-extensions.md`](docs/master-extensions.md) | parked |

### Open hazards and things undecided

| | |
|---|---|
| **RAM** | Measured 2026-09-02 after layer-12 DECISION 6: main RAM **31 B**, bank 4 **11 B**, bank 5 **674 B**, bank 6 **748 B**, bank 7 **25 B**, bank 7 **~100-105 B** (tail + pad), `PARBRF` ~20 B, `PARAFNT` tail 16 B, `PARMAN` well down from 225 B, `PINTRO` **0 B**. **No held reserve frees bank 7** — that parked layer-12 DECISION 6. The stack page's `&0100-&017F` is 128 measured-free bytes. Live numbers from the build output; spending rules and reserves in [`docs/ram-pass.md`](docs/ram-pass.md) and `CLAUDE.md` |
| **Some debug builds may still fail to assemble** | Pre-RAM-pass, every flag except `DEBUG_INVULN` broke the build on space. KC 2026-08-21: accepted. The pass's headroom may have brought some back — try the flag before assuming. `BUGS.md` #17 |
| Open defects | `BUGS.md` #2, #3, #7b, #9 and #15 — all old, all wanting retests against builds that have moved under them; #1 is probably moot |
| Transfer presentation differs | Status text on the panel line rather than above the board, numbers standing in for the side-select sprites. Decisions 6–8 in [`docs/layer-10-transfer.md`](docs/layer-10-transfer.md) |
| Zero-page initial values in the annotation are equates only | Read them from `paradroid_ce.lst`; `tools/verify_annotation.py` is the standing check after any `annotate.py` change (BUGS.md #19 history) |

## Rules that bite

### Anything drawing into the play buffer

(The byte-layout and cycle-cost facts are in `CLAUDE.md`; these are the port's own.)

1. **Display row *r* holds map row `mapYr + r`, all eight scanlines.** Unconditional — there is no
   split row any more, and nothing needs a repair pass.
2. **The draw window is frame rows 23 → 8 of the next frame**, released by `drawFlag` at `P+184`
   when the play area stops displaying. Everything shares it. `DEBUG_DRAW` tints it: magenta the
   sprites, yellow the level draw, cyan everything else.
3. **`mapYr` and `cellY` are SIGNED, and the row being drawn may be off the map** — the view
   scrolls up to `PLY_VOID` (64 px) past each vertical edge. One `AND #&C0` catches both ends, and
   `BandSetRow`, `DrawColumn` and `MapChar` all do it. Anything new that reads a map row must too.

### Adding code anywhere

**`GUARD FONT_ADDR` is what stops the code image growing into `PARAFNT`, and it exists because
nothing else did.** If a build stops with *Guard point hit* at `sprScan0`, that is the code image
full — not a bug in what you just added. The other regions have `ASSERT`s of their own: `low_end`,
`low2_end`, `lowbss_end`, `data_end`, `spr2_end`, `depk_end <= DEPK_STREAM`. Add one for anything
new.

### The low-RAM overlay, `&0C90`–`&10FF`

1. **`&0E00`–`&10FF` and `&0D60`–`&0DEF` are ours, `&0D00`–`&0D5F` and `&0DF0`–`&0DFF` are not.**
   `src/lowcode.asm`, `src/lowcode2.asm` and `src/lowbss.asm` are the three blocks.
2. **Nothing may be LOADED there.** `PARALOW` is staged at `LOW_STAGE` and copied down by
   `PageLowIn`, which **must be the last filing-system call**.
3. **It is main RAM**, so bank 4 may `JSR` in, and it may read bank 4 wherever `SWRAM_DATA` is
   paged — everywhere in the main loop, but not at boot before `PARADAT` lands and not inside the
   blitter. The same one-way rule `bufcore.asm` states.
4. `src/lowbss.asm` is `SKIP`ped, not shipped: everything in it is written before it is read.

### Verification

The buffer-vs-`RedrawAll` oracle (**NOP all three draw call sites** — see `CLAUDE.md` and
[`docs/ram-pass.md`](docs/ram-pass.md) §"The oracle recipe changed") and the listing-stream check
are described in `CLAUDE.md`; per-defect method notes are in `BUGS.md`. Three porting-specific
reminders:

- **Enter a second deck before believing a droid result** — `BUGS.md` #8 was invisible on deck 1 by
  construction.
- **Quiesce the pool with `drCount = 1`, or NOP the draw call sites** — zeroing `sprActive` alone is
  not enough, because `DrScreen` re-activates a slot from `drSlotOwner` every pass (#9's note).
- **A cross-build buffer diff needs the seed pinned.** The title's dwell seeds `drSeed`, so a build
  of a different size reaches the title at a different cycle and picks a different deck.

## Decisions taken

**The table of record moved to [`docs/decisions.md`](docs/decisions.md)** (2026-08-25), which also
holds the reasoning. Per-layer decisions are numbered in each layer's own doc; the RAM pass's are
in [`docs/ram-pass.md`](docs/ram-pass.md). Nothing is decided that is not written in one of those.

## Layers

Each layer ends with something visibly working in an emulator. Nothing moves on until it does.
The one-line summaries below are an index; the layer docs hold everything else.

| | | |
|---|---|---|
| 0 | Toolchain, first measured CRTC facts | **DONE** [`docs/layer-0-toolchain.md`](docs/layer-0-toolchain.md) |
| 1 | Graphics pipeline — per-cell hires/multicolour, charset built at deck load | **DONE** [`docs/layer-1-graphics-pipeline.md`](docs/layer-1-graphics-pipeline.md) |
| 2 | Static deck render; the `PARA`/`PARADAT` disc split | **DONE** [`docs/layer-2-static-render.md`](docs/layer-2-static-render.md) |
| 3 | Scroll: the circular strip and the three-cycle rupture — **most of the port's hardware knowledge is here** | **DONE** [`docs/layer-3-scroll.md`](docs/layer-3-scroll.md) |
| 4 | Player, speed model, dead-zone camera, wall collision, the level-draw rewrite | **DONE** [`docs/layer-4-player.md`](docs/layer-4-player.md) |
| 5 | Droid movement, the roster, and the **compiled blitter** (13,998 → 5,814 cycles a sprite) | **DONE** [`docs/layer-5-droids.md`](docs/layer-5-droids.md), [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md) |
| 6 | Droids live: line of sight, collision, mode dispatch, slot ownership | **DONE** [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md) |
| 7 | Combat: energy, aging, score, bullets and explosions, the disruptor, ALERT | **DONE** [`docs/layer-7-combat.md`](docs/layer-7-combat.md) |
| 8 | Doors, lifts and the deck-selection screen | **DONE** [`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md), [`docs/layer-8b-lift-view.md`](docs/layer-8b-lift-view.md) |
| 9 | HUD and console — `ConsoleMain` line for line, all four pages | **DONE** [`docs/layer-9-hud.md`](docs/layer-9-hud.md) |
| 10 | The transfer minigame, all three outcomes | **DONE** [`docs/layer-10-transfer.md`](docs/layer-10-transfer.md) |
| 11 | Title, game over, boot split, droid screens (11d), sound (11e), front end (11f) | **DONE** — the last two sound items closed 2026-09-01 [`docs/layer-11-sound-title.md`](docs/layer-11-sound-title.md), [`docs/layer-11d-droid-screens.md`](docs/layer-11d-droid-screens.md), [`docs/layer-11e-sound.md`](docs/layer-11e-sound.md), [`docs/layer-11f-frontend.md`](docs/layer-11f-frontend.md) |
| 12 | **Balance, fidelity and feel** — verify before tuning | **TODO** — the open half of this plan. [`docs/layer-12-balance.md`](docs/layer-12-balance.md) |
| 13 | Memory and compatibility. 13a (+6,085 B), 13b (**sideways-RAM detection**) and 13d done; **13c real machines is open** | **PART** [`docs/layer-13-ram-pass.md`](docs/layer-13-ram-pass.md), [`docs/layer-13d-space.md`](docs/layer-13d-space.md), [`docs/layer-13-compatibility.md`](docs/layer-13-compatibility.md) |
| 14 | **The visual pass** — floors, dither, text-screen backgrounds, cleared-deck and lift tile done; palettes and the ALERT lamp signed off 2026-08-31 | **nearly done** — the eye-pass leftovers are in the table above. [`docs/layer-14-visual.md`](docs/layer-14-visual.md) |
| 15 | **The endgame** — deck clear, ship clear, the next ship, names cycling at the cap | **DONE** [`docs/layer-15-endgame.md`](docs/layer-15-endgame.md) |
| — | **The RAM recovery pass** — every region bought back room for the final features | **DONE** [`docs/ram-pass.md`](docs/ram-pass.md) |
| — | **The loading intro** — scarybeasts' executable and sample player, chained behind `PARSWR` on `-Intro`/`-Release` builds | **DONE** [`docs/intro.md`](docs/intro.md) |
