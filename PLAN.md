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
| [`docs/decisions.md`](docs/decisions.md) | Why MODE 1, the no-HAL rule, and the evidence for which Paradroid the listing is |
| [`docs/graphics.md`](docs/graphics.md) | Where the C64's graphics live, which tool reads them, and per section what is ported |
| [`docs/raster-timing.md`](docs/raster-timing.md) | **Where the main loop sits against the beam** — the frame, what writes the buffer when, and the flicker work |
| `docs/layer-*.md` | One per layer, linked from the layer table at the end |

## Where we are

**Layers 0–11 are built; 12, 13b/c and 14 are the roadmap.** The port boots to a playable game: the
C64's own status box above a 320 × 120 play area, the deck hardware-scrolling eight ways under the
player — 4 px horizontally, 1 scanline vertically — with the original's acceleration model, a
dead-zone camera and a 25 Hz frame lock. Sixteen decks, per-deck palette and charset built at load.
The ship is traversable (doors, lifts, the deck-selection screen) and populated: droids patrol
waypoints, keep line of sight, collide, shoot back, kill each other and can kill you. The 711 and
the 742 carry the disruptor, and so do you once you have taken one. Die riding a captured droid and
you fall back to a 001 where you stood; die as a 001 and the game is over. Walk onto a console and
the play area becomes `ConsoleMain`'s screen with all four pages working; touch a droid at
`moveMode` 0 and the transfer minigame plays, all three outcomes landing on the droid tables.
Sprites are coloured the C64's way — enemies black, the player white, the deck's highlight in
transfer mode, flashing below energy 8.

Recharge pads turn under the player and the ALERT signs light as the ship gets angrier: both are
charset animations repainted onto the tiles in view.

**Keys:** Z/X left/right, K/M up/down, L fire — and, through the original's own `moveMode` machine,
the lift, console and transfer trigger. Cursor up/down is a debug deck hop — `DEBUG_DECK`, on by default — and SPACE a forced redraw.

**The frame budget:** the eight sprite slots cost ~36,000 cycles of the 79,872 in a pass and the
droid AI another ~17,000, so the loop keeps roughly a third spare.

> **Before trusting any speed number, read the speed model section of
> [`docs/layer-4-player.md`](docs/layer-4-player.md).** The C64's constants are per `GameLoop`
> iteration and an iteration is 2–3 frames, not 1. Every droid speed in `PlayerSpeed_t` needs the
> same conversion.

## What is left

### Missing in-game features

Compiled 2026-08-19 by walking `docs/` and the listing for everything the C64 does in play that the
port does not. **Presentation the game can be played without is excluded** — the intro manual and
the title's own polish are in the layer notes. Defects, as opposed to absences, are in `BUGS.md`.

| | | |
|---|---|---|
| **Sound — all of it** | Layer 11e. No SN76489 driver exists, and the `sndFx1`/`SndFx2` writes were dropped rather than stubbed, so no `snd*` symbol survives in `src/`. **The recovered chip encoding in [`docs/layer-11-sound-title.md`](docs/layer-11-sound-title.md) §6 is UNVERIFIED** — check it against the wiki and the emulator before building on it. The driver must be **resident**, because the IRQ reads no bank, **and main RAM is down to 77 bytes in five pieces**. Read the free-RAM section of [`docs/memory-map.md`](docs/memory-map.md) before starting: it lists where the next few hundred bytes have to come from | the biggest hole in the game as it plays |
| The 001 screen | Layer 11d. `NewShipInfo` (`$36B9`) on bank 7's shadow screen. Needs **`PrintTokenString`** (`$36DB`), the token machinery Layer 10 deferred | not started |
| Transfer: the two droid info screens | `ShowXferInfo` (`$3734`) shows two full-screen robot data pages before the board; the port goes straight to side select. [DECISION 8] in [`docs/layer-10-transfer.md`](docs/layer-10-transfer.md) | not started |
| `DoHighScore` | `$E4E5` — HIGH and LOW score and three-initial entry. It sits between `EndGame` and `TitleLoop`, and **that seam is already built** | not started |
| Game over → the title | `GoTick7` still ends a game with `JMP GameStart`. **Was blocked on ~39 B against 30 free; Layer 13a unblocked it.** Needs `UninstallIrq` and the rebuild sequence — and tearing down and rebuilding the IRQ unverified is the `hal_video.asm` mistake, so it wants the emulator | buildable now |
| The 48 × 84 droid portrait | ~6 K unported, **24 K in MODE 1**. Blocks the faithful console database page, `NewShipInfo`, the game-over screen and `ShowXferInfo`; the rotor-and-digits droid stands in. Deferred with KC; fallback is types 0 and 23 alone, ~2 K | deferred, by decision |
| The enemy bullet's colour flicker | `efAlt` from bank 5 plus a second per-entry field. Cheaper now the colour machinery exists, but effect sprites run the interpreted path and were left alone | Layer 7, deferred |

**Three of these want `PrintTokenString` first** — the 001 screen, `ShowXferInfo` and `DoHighScore`
— so it is the highest-leverage single thing on the list.

### Open items — hazards, and things still undecided

| | |
|---|---|
| **RAM** | main RAM **389 B in five pieces** — 323 below `&3000`, 0 in `lowcode`, 36 in `lowcode2`, 7 in `lowbss`, 8 in the `PARAFNT` tail — and bank 4 **12 B**. Bank 5 1,033 B, bank 6 975 B, bank 7 4,410 B, all three paged out during play. **It was 77 bytes at its worst**: 2026-08-20 spent the whole 1,136-byte `&0C90` hole, the 64 at `&54C0` and 112 of the `PARAFNT` tail on the low overlay and the disruptor, and then the raster-timing pass gave 312 back by moving the tranche decision into bank 6 — the code image had ELEVEN bytes at its worst. The sound driver still has to be resident. [`docs/memory-map.md`](docs/memory-map.md) lists the reservoirs left |
| **One debug flag will not build** | `DEBUG_MAPGUARD` (`MG_COPY` is 1 K and bank 4 has 12 B), plus `DEBUG_POS`+`DEBUG_ENERGY` together. `DEBUG_RASTER`, `DEBUG_DRAW` and `DEBUG_TIME` **build again** as of 2026-08-20: the raster-timing pass took the tranche decision out to bank 6 and the code image went from 11 free bytes to 323. `DEBUG_RASTER` has been built and run and draws its four bands correctly — mind that fire 2's band is the deck's own background, so it merges with fire 1's on a green deck and fire 3's on a blue one. `DEBUG_DRAW` and `DEBUG_TIME` assemble but have not been run. They were all corrupting the build SILENTLY until the `GUARD FONT_ADDR` of 2026-08-20; now they fail it. `DEBUG_RASTER`'s and `DEBUG_DRAW`'s instrumentation cannot move to a bank — the interrupt and the blitter call it — so they want main-RAM room found first. The table is in `main.asm`'s debug header; `BUGS.md` #17 has the story |
| Collision box shape | **Agreed 2026-08-18, not built.** `DR_COL_W`/`DR_COL_H` become a generated minimum-abs-dx-per-abs-dy profile — the silhouette instead of a rectangle, at box-test cost. [DECISION 1] in [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md). `BUGS.md` #7b's bounce tuning waits on it |
| Droid worst case unmeasured | 8 slots (~36,000) + droids (17,000) + full-diagonal level draw (19,172) is ~72,000 of 79,872 before the rest of the loop. It never arose by chance; it wants a rig on a deck with a long open corridor. `docs/raster-timing.md` Step 3 is the planned relief |
| Twelve title characters, four wash characters | `export_bbc.py` converts only what a TILE references, so the title ships its own 36 glyphs and `EndGame`'s wash uses substitutes. Extending the shared charset is the better fix, moves `NUM_CHARS`, and needs KC |
| Effect sprites are one colour | Bullets and explosions run the interpreted path, which the sprite-colour work left alone |
| Play area is 320 × 120, not 128 | Consequence of the single hardware wrap. Getting the row back needs the 20K wrap or per-cycle wrap bits. **KC's call** |
| Vertical granularity | 1 scanline against 4 px horizontal is lopsided. 2 or 4 scanlines costs nothing extra. Decidable now there are droids to watch |
| 2 px world scrolling | Parked, Master-only via shadow RAM. Costs +60–80% on all drawing — [`docs/master-extensions.md`](docs/master-extensions.md) |
| `keydown` uses OSBYTE `&81` | The last OS call in the main loop |
| 8 decks draw ALERT in multicolour | Confirmed faithful to the C64, not a bug. Worth a look on real hardware |
| Transfer presentation differs | Status text on the panel line rather than above the board, numbers standing in for the side-select sprites. Decisions 6–8 in [`docs/layer-10-transfer.md`](docs/layer-10-transfer.md) |

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
nothing else did.** `CLEAR FONT_ADDR, ...` releases beebasm's own overwrite check over exactly the
range an over-long image spills into, so for weeks an over-long debug build assembled cleanly,
`*RUN PARA` scribbled on the text font and the `*LOAD PARAFNT` scribbled back over the code. If a
build stops with *Guard point hit* at `sprScan0`, that is the code image full — not a bug in what
you just added. `BUGS.md` #17.

The other regions have `ASSERT`s of their own: `low_end <= LOW_LIMIT`, `low2_end <= LOW2_LIMIT`,
`lowbss_end <= LOWBSS_LIMIT`, `data_end <= SWRAM_BASE + &4000`. Add one for anything new.

### The low-RAM overlay, `&0C90`–`&10FF`

New since 2026-08-20, and it changes where code may live.

1. **`&0E00`–`&10FF` and `&0D60`–`&0DEF` are ours, `&0D00`–`&0D5F` and `&0DF0`–`&0DFF` are not.**
   The first is DFS's shared workspace, the second Econet/mouse workspace and the extended vector
   table; the two exclusions are the NMI handler and the sideways ROMs' private-workspace page
   bytes. `src/lowcode.asm`, `src/lowcode2.asm` and `src/lowbss.asm` are the three blocks.
2. **Nothing may be LOADED there.** DFS is using it while it delivers the file. `PARALOW` is staged
   at `LOW_STAGE` and copied down by `PageLowIn`, which **must be the last filing-system call** —
   do it earlier and the next `*LOAD` hangs in the 8271 poll. That cost a build.
3. **It is main RAM**, so bank 4 may `JSR` in and so may the code image, and it may read bank 4
   wherever `SWRAM_DATA` is paged — everywhere in the main loop, but not at boot before `PARADAT`
   lands and not inside the blitter. The same one-way rule `bufcore.asm` states.
4. `src/lowbss.asm` is `SKIP`ped, not shipped: everything in it is written before it is read.

### Verification

The buffer-vs-`RedrawAll` oracle and the listing-stream check are described in `CLAUDE.md`;
per-defect method notes are in `BUGS.md`. Three porting-specific reminders:

- **Enter a second deck before believing a droid result** — `BUGS.md` #8 was invisible on deck 1 by
  construction.
- **Quiesce the pool with `drCount = 1`, or NOP the draw call sites** — zeroing `sprActive` alone is
  not enough, because `DrScreen` re-activates a slot from `drSlotOwner` every pass (#9's note).
- **A cross-build buffer diff needs the seed pinned.** The title's dwell seeds `drSeed`, so a build
  of a different size reaches the title at a different cycle and picks a different deck.

## Decisions taken

**This table is the record.** [`docs/decisions.md`](docs/decisions.md) holds the *reasoning* —
why MODE 1, the no-HAL rule, how the bank count grew from two to four, and the measurement that
settled which Paradroid this listing is. Per-layer decisions are numbered in each layer's own doc.

| Decision | Choice | Date |
|---|---|---|
| Target machine | BBC B / B+ with **4 × 16K sideways RAM banks**, numbered 4–7 as the Master does | 2026-08-16 |
| Source version | **1985 original / 1986 Competition Edition** lineage, which is what `paradroid_ce.lst` is. Redux's bug list is a spec, not code; Heavy Metal parked as a later tile set | 2026-08-06 |
| Architecture | No HAL. One working layer at a time, verified in the emulator before moving on | 2026-08-04 |
| Screen mode | MODE 1, 4 colours, **10K wrap at `&5800–&7FFF`** | 2026-08-04 |
| Screen layout | 3-cycle vertical rupture: static panel, gap, scrolled play area. The panel is **4 rows**, the C64's 32 scanlines | 2026-08-05/16 |
| Play area | **320 × 120** — 10 tiles wide, 15 character rows | 2026-08-05 |
| Scrolling | CRTC hardware scroll over a circular strip. **4 px horizontal, 1 scanline vertical** | 2026-08-05 |
| Interrupts | We own IRQ1V outright, System VIA T1 continuous. No MOS chaining, no MOS sound | 2026-08-04 |
| Game loop rate | **Locked to 2 fields a pass**, not free-running — free-running made the player 20 % slower whenever droids were visible | 2026-08-13 |
| Sprite blitter | **Compiled**, not interpreted: generated 6502 per rotor row and per digit glyph | 2026-08-13 |
| The four logical colours have fixed roles | 0 the deck's background, 1 black, 2 the deck's highlight, 3 white. Chosen for the sprites, and what makes a sprite byte its own transparency mask | 2026-08-17 |
| Sprite colour is not baked in | The artwork is logical 3, so choosing a colour is choosing a nibble, and eleven zero page bytes carry it. Enemies black, player white, the deck's highlight in transfer mode, a 4-field flash below energy 8 | 2026-08-19 |
| Player top speed | **8 px a pass, not the C64's 7** (`CAM_TOPSPD`) — the only movement number not taken from the original. 7 cannot divide the CRTC's 4 px step, so the camera dithers. 14 % fast, bought deliberately | 2026-08-14 |
| The disruptor's screen shake | **Not ported.** The strip is 16 rows in one hardware wrap, so a CRTC jitter fetches rows that were never drawn. Palette flash alone | 2026-08-19 |
| The ALERT lamp's four colours | **Four states, not four hues** — MODE 1 has no fifth colour. Black, the deck's highlight, white, white blinking. The blink is a deviation and is **not yet ratified** | 2026-08-20 |
| Code may live below `&1100` | The reclaimed DFS/OS workspace at `&0C90`–`&10FF`, staged and copied after the last `*LOAD`. Page `&0D`'s NMI half stays untouched | 2026-08-20 |
| Transfer board shows all 16 rows | The rupture's fire-2→3 interval became a variable (`t1i3`) so the transfer can move the bottom edge down a row | 2026-08-16 |

## Layers

Each layer ends with something visibly working in an emulator. Nothing moves on until it does.

| | | |
|---|---|---|
| 0 | Toolchain, and the first measured CRTC facts | **DONE** [`docs/layer-0-toolchain.md`](docs/layer-0-toolchain.md) |
| 1 | Graphics pipeline. **The C64 mixes hires and multicolour cells on one screen**, per cell by bit 3 of the colour nibble, and a character's mode changes between decks — so the charset is built at deck load | **DONE** [`docs/layer-1-graphics-pipeline.md`](docs/layer-1-graphics-pipeline.md) |
| 2 | Static deck render: RLE decode into a 64 × 16 tile map, expanded to characters at draw time. Also where the `PARA`/`PARADAT` disc split comes from | **DONE** [`docs/layer-2-static-render.md`](docs/layer-2-static-render.md) |
| 3 | Scroll: the circular strip and the three-cycle rupture. **Most of the port's hardware knowledge is here** — CRTC write windows, why R5 must not be touched near a cycle boundary, and why one hardware wrap costs the 16th row | **DONE** [`docs/layer-3-scroll.md`](docs/layer-3-scroll.md) |
| 4 | Player sprite, speed model, dead-zone camera, wall collision — then the level-draw rewrite, full-diagonal 38,472 → 19,172 cycles | **DONE** [`docs/layer-4-player.md`](docs/layer-4-player.md) |
| 5 | Droid movement and the ship's roster; **the player spawns on waypoint 0**. Then the **compiled blitter**, 13,998 cycles a sprite → 5,814, four shifts across two banks | **DONE** [`docs/layer-5-droids.md`](docs/layer-5-droids.md), [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md) |
| 6 | Droids live: line of sight, collision, the mode dispatch. Slot **ownership** separated from `sprActive`, so a droid hidden behind a wall keeps its slot | **DONE** [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md) |
| 7 | Combat: the player as droid entry 0, energy, aging, BCD score, recharge pads, and bullets and explosions as a second sprite class in the same eight slots. **7g and 7h, 2026-08-20**: the `CollisionType` matrix, friendly fire, the disruptor, the recharger's animation and the ALERT lamp | **DONE** [`docs/layer-7-combat.md`](docs/layer-7-combat.md) |
| 8 | Doors, lifts and the deck-selection screen. Taken ahead of 6 and 7, because droid AI routes *through* doors | **DONE** [`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md), [`docs/layer-8b-lift-view.md`](docs/layer-8b-lift-view.md) |
| 9 | HUD and console: the status line is the C64's and nothing else, and the console is `ConsoleMain`'s line for line, all four pages working | **DONE** [`docs/layer-9-hud.md`](docs/layer-9-hud.md) |
| 10 | The transfer minigame, entered the original's way, all three outcomes landing on the droid tables | **DONE** [`docs/layer-10-transfer.md`](docs/layer-10-transfer.md) |
| 11 | Title, game over, and the boot split. **11a, 11b and the title are built**; the loop back to the title, the 001 screen and sound are in the feature list above | **PART** [`docs/layer-11-sound-title.md`](docs/layer-11-sound-title.md) |
| 12 | **Balance, fidelity and feel.** Not a feature layer: the fidelity audit against the listing, the Redux fix list triaged, playtesting against the isolated dials, and graceful degradation. Verify before tuning, or a fidelity bug gets balanced around instead of fixed | **TODO** [`docs/layer-12-balance.md`](docs/layer-12-balance.md) |
| 13 | Memory and machine compatibility. **13a, the RAM pass, is done — +6,085 bytes, no cycle cost, no behaviour change.** 13b is sideways-RAM detection at boot, of which there is none today; 13c is running on the machines people actually have | **PART** [`docs/layer-13-ram-pass.md`](docs/layer-13-ram-pass.md), [`docs/layer-13-compatibility.md`](docs/layer-13-compatibility.md) |
| 14 | **The visual pass, deliberately last.** Every deck's and every screen's palette settled in one sitting with `tools/palette_lab.py`, plus redrawing the characters that fight MODE 1 | **TODO** [`docs/layer-14-visual.md`](docs/layer-14-visual.md) |
