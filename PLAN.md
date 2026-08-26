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
| `docs/layer-*.md` | One per layer, linked from the layer table at the end |

## Where we are

**Layers 0–11, 13a/13d and 15 are built; 12, 13b/c and the rest of 14 are the roadmap.** The port
boots to a playable game with the whole loop closed: the C64's status box above a 320 × 120 play
area scrolling eight ways at 25 Hz, sixteen traversable decks of patrolling, fighting droids, the
console with all four pages, the transfer minigame with all three outcomes, the lift screen, the
droid information screens, sound throughout, the title / high-score / five-page briefing front
end, and — since Layer 15 — the endgame: decks clear for 500, ships clear for 2,000 and hand over
to the next, names cycling under a difficulty that caps at ship 8, so the game is survived rather
than won. Per-layer detail is in the layer table at the end and its docs.

**Keys:** Z/X left/right, K/M up/down, L fire — and, through the original's own `moveMode`
machine, the lift, console and transfer trigger. **ESCAPE self-destructs and ends the game.**
Cursor up/down is `DEBUG_DECK`'s deck hop, C is `DEBUG_KILL`'s clear-the-deck, W wins a transfer
(`DEBUG_XFERWIN`), SPACE a forced redraw — all three flags ship ON.

**The frame budget:** the eight sprite slots cost ~36,000 cycles of the 79,872 in a pass and the
droid AI another ~17,000, so the loop keeps roughly a third spare. The RAM squeeze that shaped
2026-08's work is over: **the RAM recovery pass (2026-08-25) left 639 B of main RAM and double
or triple digits in every other region** — current figures in `CLAUDE.md`'s table, details in
[`docs/ram-pass.md`](docs/ram-pass.md).

> **Before trusting any speed number, read the speed model section of
> [`docs/layer-4-player.md`](docs/layer-4-player.md).** The C64's constants are per `GameLoop`
> iteration and an iteration is 2–3 frames, not 1. Every droid speed in `PlayerSpeed_t` needs the
> same conversion.

## What is left

### Features

| | | |
|---|---|---|
| **The ± volume keys** — `AdjustVolume` (`$0CB4`) | **WANTED, KC 2026-08-22**: "we'll definitely want that volume control." `sndVolume` already exists and the driver already honours it. Two prerequisites, both costed in [`docs/layer-11e-sound.md`](docs/layer-11e-sound.md) §8: the **attenuation clamp deleted in round nine must come back** (a lower master volume without it wraps the nibble into garbage — 4 B in bank 4 via `BCS snfv_off`), and the key poll needs a home — **the RAM pass has since provided one everywhere**. Should land **before** any more eared level deviations | **next on the list** |
| **Sound: the game-over set** | Layer 11e is otherwise built and tuned. KC: "needs work, leave for now." Also open: the transfer-verdict mapping (unverified guess) and fx06 with 11d | open |
| **Briefing F6: exit-load trim** | The briefing → game reload is ~1.1 s naive; deferred from 11f. The pause-legend wording in `briefing.txt` is KC's, ongoing | later |
| **Layer 12 — balance, fidelity and feel** | Not a feature layer: the fidelity audit against the listing, the Redux fix list triaged, playtesting against the isolated dials, graceful degradation. **Verify before tuning**, or a fidelity bug gets balanced around instead of fixed. [`docs/layer-12-balance.md`](docs/layer-12-balance.md) | TODO |
| **Layer 13b/13c — machine compatibility** | 13b: sideways-RAM detection at boot, of which there is none today (a machine without 4 banks hangs undiagnosed). 13c: running on the machines people actually have. [`docs/layer-13-compatibility.md`](docs/layer-13-compatibility.md) | TODO |
| **Layer 14 — the rest of the visual pass** | Deck floors, the fifth-tone dither and the cleared-deck floor are done. Still to do: the remaining screens' palettes, the characters that fight MODE 1, and the ALERT lamp's blinking fourth state (revisit promised 2026-08-21). [`docs/layer-14-visual.md`](docs/layer-14-visual.md) | in progress |
| Collision box shape | **Agreed 2026-08-18, confirmed 2026-08-21, not built.** `DR_COL_W`/`DR_COL_H` become a generated silhouette profile instead of a rectangle, at box-test cost. [DECISION 1] in [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md). `BUGS.md` #7b's bounce tuning waits on it | agreed, unbuilt |
| Twelve title characters, four wash characters | `export_bbc.py` converts only what a TILE references, so the title ships its own 36 glyphs and `EndGame`'s wash uses substitutes. **KC 2026-08-21: extend the shared charset when space allows** — bank 4 now has the room | unblocked by the RAM pass |
| The enemy bullet's colour flicker | `efAlt` from bank 5 plus a second per-entry field; effect sprites run the interpreted path (now in bank 5 itself, `src/sprfx.asm`) and are one colour | Layer 7, deferred |
| 2 px world scrolling | Parked, Master-only via shadow RAM. Costs +60–80 % on all drawing — [`docs/master-extensions.md`](docs/master-extensions.md) | parked |
| **The four Redux adoptions** — triaged with KC 2026-08-26 | (1) explosions not restarted by the disruptor/bullets; (2) the three-droid-deadlock priority randomisation, **after reproducing the deadlock here first**; (3) lift-adjacent waypoints excluded from droid starts; (4) high-score entry remembers the previous initials. Everything else on https://paradro.id/ was rejected for 1.0 — the record is in [`docs/decisions.md`](docs/decisions.md) and §12b. Damage tables stay CE's in full, laser swap included | adopted, unbuilt |

### Polish items — from Kieran's Human Notes

Everything in [`docs/Kieran's Human Notes.txt`](docs/Kieran's%20Human%20Notes.txt) not marked
DONE or NO, added 2026-08-26. Where a note overlaps a row elsewhere in this file, the row is the
home and the note is cross-referenced.

**Transfer**

- The score should go up **inside** the transfer game, before returning to the main game. Was
  marked NEEDS RAM — the RAM pass has since provided it.

**Gameplay**

- Sprite flicker (still).
- Player 001 should flash on teleport-in at the start.
- Some of the decks have the lift tile missing?
- Lift selection does weird palette changes.
- Separate key for transfer vs fire? (= Redux's two-button mode: second button enters transfer, first does everything else)
- Getting into the lift just as the disruptor fires leaves the screen white.

**Console**

- Continually redrawing the top line when on the droid info page? Also the panel word?
- The droid info screens are always on a white background with blue header and red text —
  should follow the deck?

**Game over**

- Improve the static — just B&W, and use the original's characters.
- "Game over" has a small g, and should be in red.

**Front end**

- Update the scroll text wording.
- Add a Beeb page.
- Why does it need to load after the Paradroid logo?
- The briefing scroll speed is 2× the C64's.
- The copyright symbol is missing.
- After exiting the game back to the front end there's a quiet sequence of tones that rise in
  pitch?!

**Niceties**

- Redux bug fixes and feature additions — Layer 12's triage; the bug list is adopted as behaviour in `docs/decisions.md`. The one KC named already: **the droids-remaining count on the console** (Redux shows it per deck/ship).
- Pause.
- Volume — the ± volume keys row above is the home for this.
- What's Cheese?
- Redefine keys.

**Attention to detail**

- Palette change timing.
- TV resync — the rupture-mid-frame hazard row below is the home for this.
- Single-line scroll flicker — move keys off OSBYTE? (The `keydown` row below.)
- Blanking during load.
- Show the screen only after the frame is drawn — return from console, high-score → Paradroid
  logo, between briefing pages.

**Loader**

- SWRAM detection — Layer 13b above is the home for this.
- MODE 7 splash to hide loading?
- Robot intro with Chris's music — music in progress.

### Open hazards and things undecided

| | |
|---|---|
| **RAM** | **The squeeze is over but the discipline stays.** Post-recovery figures (2026-08-25): main RAM **639 B**, bank 4 **51 B** (+17 B pad), bank 5 **602 B**, bank 6 **114 B**, bank 7 7 B + **~176 B pad**, `PARBRF` **56 B** — live numbers from the build output, spending rules and reserves in [`docs/ram-pass.md`](docs/ram-pass.md) and `CLAUDE.md` |
| **Some debug builds may still fail to assemble** | Pre-pass, every flag except `DEBUG_INVULN` broke the build on space (`GUARD` / `spr2_end` / `sound.asm` asserts). KC 2026-08-21: accepted. The pass's headroom may have brought some back — try the flag before assuming. `BUGS.md` #17 |
| Droid worst case unmeasured | 8 slots (~36,000) + droids (17,000) + full-diagonal level draw (19,172) is ~72,000 of 79,872 before the rest of the loop. It never arose by chance; it wants a rig on a deck with a long open corridor. `docs/raster-timing.md` Step 3 is the planned relief |
| **The rupture goes up mid-frame, and the TV loses lock** | `SetupRupture` switches the CRTC shape wherever the CPU happens to be; a television needs several fields to pull sync back — a roll or tear into a game and after a game over. Candidates: switch on a field boundary, order the writes so the frame stays legal at every step, blank across the change. Mind the R5/R6/R7 write-window rules in `CLAUDE.md`; nothing here is measured yet | 
| **The picture's height was set in an emulator** | `FRAME_DROP_ROWS` = 3 was chosen against jsbeeb and b-em; a real television crops differently. One constant in `main.asm`, and the title follows it. **Re-check on hardware** |
| 8 decks draw ALERT in multicolour | Confirmed faithful to the C64, not a bug. Worth a look on real hardware |
| `keydown` uses OSBYTE `&81` | The last OS call in the main loop |
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
| 11 | Title, game over, boot split, droid screens (11d), sound (11e), front end (11f) | **DONE** except the open sound items above [`docs/layer-11-sound-title.md`](docs/layer-11-sound-title.md), [`docs/layer-11d-droid-screens.md`](docs/layer-11d-droid-screens.md), [`docs/layer-11e-sound.md`](docs/layer-11e-sound.md), [`docs/layer-11f-frontend.md`](docs/layer-11f-frontend.md) |
| 12 | **Balance, fidelity and feel** — verify before tuning | **TODO** [`docs/layer-12-balance.md`](docs/layer-12-balance.md) |
| 13 | Memory and compatibility. 13a (+6,085 B) and 13d (title overlay, portrait, ZX0 maps) done; **13b sideways-RAM detection and 13c real machines are open** | **PART** [`docs/layer-13-ram-pass.md`](docs/layer-13-ram-pass.md), [`docs/layer-13d-space.md`](docs/layer-13d-space.md), [`docs/layer-13-compatibility.md`](docs/layer-13-compatibility.md) |
| 14 | **The visual pass** — floors and cleared-deck done; screens' palettes, the MODE-1-fighting characters and the ALERT blink open | **in progress** [`docs/layer-14-visual.md`](docs/layer-14-visual.md) |
| 15 | **The endgame** — deck clear, ship clear, the next ship, names cycling at the cap | **DONE** [`docs/layer-15-endgame.md`](docs/layer-15-endgame.md) |
| — | **The RAM recovery pass** — every region bought back room for the final features | **DONE** [`docs/ram-pass.md`](docs/ram-pass.md) |
