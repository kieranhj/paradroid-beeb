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

**Layers 0–11 and 13a/13d are built; 12, 13b/c and 14 are the roadmap.** The port boots to a playable game: the
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
charset animations repainted onto the tiles in view. **It has a voice** — the SN76489 driver in
bank 4, every in-game trigger wired and tuned by ear with KC. And it has **the droid information
screens**: the 001 briefing a game opens on, the two pages the transfer shows before the board, and
`EndGame`'s 999 behind "Transmission / Terminated".

**And it has the whole front end** (Layer 11f, 2026-08-22): the high-score entry between the game
over and the title, under the game's own panel reading "game over"; and the five-page intro
manual the title falls into on a timeout — smooth-scrolled at the C64's own speeds and dwells,
with the live score table and a random droid portrait on page 5, driven from `PARBRF` at `&0400`
with the text in an evicted bank 5. **It burbles to itself while it scrolls**, which is the C64's
`sndState $11` chatter — the title's in name only, since `TitleLoop` posts it *after* `ShowTitle`
returns, so the logo screen is silent on both machines. The text itself is hand-editable
(`src/data/briefing.txt`, tracked; `make_briefing.py` converts it every build), and every
front-end screen inherits the last deck's palette.

**Every screen that is not the scrolled deck now uses all sixteen rows of the play area**, and the
ported pages sit on the C64's own rows rather than one above them. **The whole picture sits three
character rows lower on the tube**, title included, which is `FRAME_DROP_ROWS` in `main.asm` and one
constant to change if a real television disagrees with the emulator.

**Keys:** Z/X left/right, K/M up/down, L fire — and, through the original's own `moveMode` machine,
the lift, console and transfer trigger. **ESCAPE self-destructs and ends the game** — the port's
own, since the C64 has no abort. Cursor up/down is a debug deck hop — `DEBUG_DECK`, on by default — and SPACE a forced redraw.

**The frame budget:** the eight sprite slots cost ~36,000 cycles of the 79,872 in a pass and the
droid AI another ~17,000, so the loop keeps roughly a third spare.

> **Before trusting any speed number, read the speed model section of
> [`docs/layer-4-player.md`](docs/layer-4-player.md).** The C64's constants are per `GameLoop`
> iteration and an iteration is 2–3 frames, not 1. Every droid speed in `PlayerSpeed_t` needs the
> same conversion.

## What is left

### Missing in-game features

Compiled 2026-08-19 by walking `docs/` and the listing for everything the C64 does in play that the
port does not; **reviewed with KC 2026-08-21** and everything finished taken out — what was here is
in the layer docs. **Presentation the game can be played without is excluded** — the intro manual
and the title's own polish are in the layer notes. Defects, as opposed to absences, are in
`BUGS.md`.

| | | |
|---|---|---|
| **The deck goes dark when it is cleared** | The C64's `RunDroids` `_6` arm (`$17DC`) calls `InitColors`, which on `numDeckDroids == 1` takes **colour scheme 7** (`0B 00 0F 07 07 0B 0E 00 08 0C 0C 00` — dark grey, black, light grey, orange) instead of `deckScheme[deck]`. Free on the C64, where colour is per-cell in colour RAM. **Ours bakes colour into the charset at deck load**, and scheme 7's colours merge onto MODE 1's four differently from every deck's own scheme, so this is not a straight palette swap. **KC's call, 2026-08-21: do it as a palette-only repaint** — keep the deck's charset and its logical merges, repaint `palPlay`'s four entries towards scheme 7. Free, no hitch at the moment of clear, greys land approximately. The scheme table is already shipped (`.schemes`, all 8 records, `src/data/colours.asm`); what is needed is a scheme-7 row for `deckPalette` and a repaint on the clear arm. Mind the fixed colour roles — logical 1 black and 3 white carry the sprites | **next up** |
| **Sound** | Layer 11e stages 0–4 **BUILT AND TUNED 2026-08-21**: driver in bank 4, every in-game trigger wired, and ten by-ear rounds with KC signed off the hum, explosions, bump, disruptor, ram-kill, bullet-hit, lift and start. **Open**: the game-over set (KC: "needs work, leave for now"), the transfer-verdict mapping (unverified guess), fx06 with 11d. The chatter landed with 11f (it is the *briefing's* sound, not the title's). **Bank 4: 4 bytes free.** [`docs/layer-11e-sound.md`](docs/layer-11e-sound.md) | game-over set + odds and ends |
| **The ± volume keys** — `AdjustVolume` (`$0CB4`) | **WANTED, KC 2026-08-22**: "we'll definitely want that volume control." Promoted out of 11e §8's deferred list on the strength of the chatter's loudness rounds — three of them went into turning one effect down, and some of "too loud" is really "no way to turn it down". `sndVolume` already exists and the driver already honours it. Two things stand in the way and both are costed in [`docs/layer-11e-sound.md`](docs/layer-11e-sound.md) §8: the **attenuation clamp round nine deleted must come back** (a lower master volume without it wraps the nibble into garbage — 4 B in bank 4, which has 2, via `BCS snfv_off` rather than the 6-byte form), and the **key poll needs a home in a machine where every region is full** (main RAM 2 B, bank 4 2 B, PARBRF 3 B, low overlay 1 B, `lowcode2` 8 B). Wants a RAM hunt first, and it should land **before** any more eared level deviations | **on the list** |
| **The droid information screens** | Layer 11d, **DONE and verified 2026-08-21**: `NewShipInfo` (`$36B9`), both `ShowXferInfo` pages (`$3734`) and `EndGame`'s 999 page (`$37DC`). `PrintTokenString` turned out to be 90 % built already — Layer 9's database page had the printer, the wrap, the capitalisation and `ShowRobotType` — and `PoDraw`'s rectangle is parameterised horizontally, so the 999 centres the way `$37E8` centres it. [`docs/layer-11d-droid-screens.md`](docs/layer-11d-droid-screens.md) | done |
| `DoHighScore` + the briefing | Layer 11f, **BUILT, VERIFIED AND MERGED 2026-08-22** — the entry (bank-7 table, `PARTITL` overlay, under the game's own "game over" panel), the five-page briefing scroller (`PARBRF` at `&0400` — hard ceiling `&0800`, the MOS owns the page above — text + bank-half in an evicted bank 5, live score table and portrait on page 5, hand-editable `briefing.txt`), the panel box, inherited palettes, blanked load seams. **F2 the chatter BUILT AND VERIFIED 2026-08-22** — and it is the briefing's sound, not the title's: `TitleLoop` writes `$11` only after `ShowTitle` returns, so the logo screen is silent and the 50 Hz tick the block was waiting on was already running under `BrWaitField`. Three records against bank 4's fifteen bytes became one rewritable scratch slot, with the records in bank 5 (§4f). **Signed off by KC's ear** the same day, after three rounds that took the lift blip it reuses to periodic bass and down 6 dB — and that reaches the in-game lift too, re-heard and fine. **Open in the layer**: F6 exit-load trim (deferred; naive reloads ~1.1 s briefing→game), and the pause-legend wording in `briefing.txt` (KC's, ongoing). [`docs/layer-11f-frontend.md`](docs/layer-11f-frontend.md) | F2 + F6, later |
| The enemy bullet's colour flicker | `efAlt` from bank 5 plus a second per-entry field. Cheaper now the colour machinery exists, but effect sprites run the interpreted path and were left alone | Layer 7, deferred |

**`PrintTokenString` was the bottleneck and it is gone.** Three items waited on it — the 001 screen,
`ShowXferInfo` and `DoHighScore` — and Layer 11d built the first two along with the printer itself.
`DoHighScore` is what is left, and it now has everything it needs.

The console database page's portrait had never had an **in-game play-check**; it has now
(2026-08-21, walked to a console on deck 2 and browsed both sub-pages). Nothing on that count is
outstanding.

### Open items — hazards, and things still undecided

Reviewed with KC 2026-08-21; what was settled that day moved into the decisions table below.

| | |
|---|---|
| **RAM** | **Measured from the build of 2026-08-24**, not remembered. Every region is single or low double digits: main RAM **6 B** below `&3000` (`code_end` = `&2FFA` — Layer 14's DECISION 5 gave four back), bank 4 **2 B**, `PARBRF` **3 B** (ceiling `&0800`, not `&0C90` — the MOS owns the page above), the low overlay **1 B**, `lowcode2` **8 B**, bank 6 **16 B**, bank 7 **314 B**. Bank 4 went to 26 B when Layer 14's floor dither paid for itself and spent it again on the text palettes ([`docs/layer-14-visual.md`](docs/layer-14-visual.md)); **bank 4 also has ~160 B of alignment padding in front of `colourMap` that the fuel gauge does not count, and DATA can ride there for nothing** — that is where `deckTextPal` lives. The roomy ones are bank 5 **1,033 B** and bank 7 **314 B**, both paged out during play and so unreachable from the main loop, plus `PARMAN`'s unused 11 K when the briefing has bank 5. Layer 11e's sound driver took bank 4's margin and Layer 11f's front end took what the sixteen-row change had bought back. **The build PRINTs bank 4's fuel gauge every run**, and the others are `&C000` minus the end addresses it PRINTs beside it. **Anything new needs something moved first**; [`docs/memory-map.md`](docs/memory-map.md) lists the reservoirs left |
| **Every debug build is broken except `DEBUG_INVULN`** | Re-tested one flag at a time, 2026-08-21: `DEBUG_RASTER`, `DEBUG_DRAW` and `DEBUG_TIME` hit the main-RAM `GUARD`; `DEBUG_POS`, `DEBUG_VSYNC` and `DEBUG_ENERGY` blow `ASSERT spr2_end <= SWRAM_BASE + &4000` (bank 6); `DEBUG_MAPGUARD` blows `sound.asm`'s one-page assert (bank 4). The three that ship ON — `XFERWIN`, `RESTART`, `DECK` — still build, which is why the default build is fine. **Cause is the RAM row above, not any of the flags.** **KC 2026-08-21: accepted, not to be rescued now** — they come back when space does, and until then the diagnostics they provide are unavailable. Note that they used to corrupt a build SILENTLY; since the `GUARD FONT_ADDR` of 2026-08-20 they fail loudly instead, which is the good outcome. `BUGS.md` #17 |
| Collision box shape | **Agreed 2026-08-18, not built; still wanted, confirmed 2026-08-21.** `DR_COL_W`/`DR_COL_H` become a generated minimum-abs-dx-per-abs-dy profile — the silhouette instead of a rectangle, at box-test cost. [DECISION 1] in [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md). `BUGS.md` #7b's bounce tuning waits on it |
| Droid worst case unmeasured | 8 slots (~36,000) + droids (17,000) + full-diagonal level draw (19,172) is ~72,000 of 79,872 before the rest of the loop. It never arose by chance; it wants a rig on a deck with a long open corridor. `docs/raster-timing.md` Step 3 is the planned relief |
| **The annotated listing was missing 43% of the original's data** | `annotate.py` kept only the first tab-separated column group of a `.BYTE` line, so blocks were truncated **and what survived was misaligned** — a lookup returned a real-looking byte from the wrong offset. Fixed 2026-08-24 and `tools/verify_annotation.py` is now the standing check; run it after any `annotate.py` change. Zero-page initial values are still equates only, so read those from `paradroid_ce.lst`. [BUGS.md #19](BUGS.md) |
| Twelve title characters, four wash characters | `export_bbc.py` converts only what a TILE references, so the title ships its own 36 glyphs and `EndGame`'s wash uses substitutes. Extending the shared charset is the better fix and moves `NUM_CHARS`. **KC 2026-08-21: do it when space allows** — it is the right fix the moment bank 4 has room, and until then both workarounds stand |
| Effect sprites are one colour | Bullets and explosions run the interpreted path, which the sprite-colour work left alone |
| 2 px world scrolling | Parked, Master-only via shadow RAM. Costs +60–80% on all drawing — [`docs/master-extensions.md`](docs/master-extensions.md) |
| **The rupture goes up mid-frame, and the TV loses lock** | `SetupRupture` changes R4/R5/R6/R7 from `SetupMode`'s plain 39-row frame to the three-cycle shape, and it does it wherever the CPU happens to be. A television needs several fields to pull vertical sync back — visible as a roll or a tear on the way into a game, and again after a game over. **Find the timing that costs the fewest frames**: candidates are switching on a field boundary rather than mid-frame, ordering the register writes so the frame stays legal at every intermediate step, and blanking the display across the change. Mind what is already known — R6/R7/R12/R13 must be written the cycle *before* they fire, R5 must not be touched near a cycle boundary, and R7 must not be in its rupture value while a filing-system call is running. `docs/layer-3-scroll.md` has those facts; nothing here is measured yet. **One of them stopped being theoretical on 2026-08-21**: `R7 = 255` was being written at fire 1, five rows into the panel cycle, and `FRAME_DROP_ROWS` made the stale tail value reachable there — the panel cycle fired its own VSync and the play area went black. It is written at VSync now. KC, 2026-08-21 |
| **The picture's height was set in an emulator** | `FRAME_DROP_ROWS` = 3 was chosen against jsbeeb's raw 312-line frame and KC's eye on b-em — four rows looked low, three looks right. A real television crops differently and the overscan varies set to set, so **this is a number to re-check on hardware** and it is one constant to change: `main.asm`, and the title follows it. The same caution as the smoothness one — an emulator is not the display this is for |
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
| Play area | **320 × 120** — 10 tiles wide, 15 character rows. The 16th row went to the single hardware wrap, which is what smooth vertical scrolling costs. **KC closed this 2026-08-21: 120 is what we ship** — the 20K wrap is not being pursued. It costs the **scrolled deck** only: with the scroll flattened the 16th row is real buffer, and every screen that is not the deck shows it — see the sixteen-rows row below | 2026-08-05, closed 2026-08-21 |
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
| **The picture sits 3 rows lower on the tube** | `FRAME_DROP_ROWS` moves VSync three rows earlier (`TAIL_R7` 8 → 5) and `T1_I1` the same three rows later, so the panel and play area drop 24 scanlines without the frame or the cycles changing. KC tried four and it looked low. It forced `R7 = 255` out of fire 1 and into `RuptVSync`: at any `TAIL_R7` of 7 or below the 7-row panel cycle reaches the stale value and fires a VSync of its own, which blanked the play area entirely. **The title follows it**: `TiCRTC` sets `TITLE_R7 = 34 - FRAME_DROP_ROWS`, which is the same gap from VSync expressed in its own 39-row frame, and is the OS's own 34 when the drop is zero. [`docs/layer-3-scroll.md`](docs/layer-3-scroll.md) | 2026-08-21 |
| **Every non-gameplay screen shows all 16 rows** | Started 2026-08-16 as the transfer board alone, on a variable fire-2→3 interval (`t1i3`); the lift's deck select and the deck plan followed. Now the console and its three pages, the four information screens and the game over's wash have it too, so **only the scrolled deck is 15 rows**. Set on entry, restored in **one** place — `ReframeView` — which freed 47 B of bank 4. The **ported** pages (database, information screens, game over) moved down one row onto the C64's own rows; the console main screen stays plotted from row 0 per KC's earlier rule. [`docs/layer-9-hud.md`](docs/layer-9-hud.md) §6g | 2026-08-16, extended 2026-08-21 |
| The four banks ship ZX0-compressed on disc | Boot 14.4 s → 10.4 s measured. `PARDEPK` (an eighth disc file, the same depack macro as bank 4's) unpacks each bank from `&3200` straight into SWRAM; `tools/make_disc.py` compresses and lays the disc out in boot access order after beebasm — **the raw beebasm image is no longer bootable**. [`docs/loader-compression.md`](docs/loader-compression.md) | 2026-08-21 |

## Layers

Each layer ends with something visibly working in an emulator. Nothing moves on until it does.

| | | |
|---|---|---|
| 0 | Toolchain, and the first measured CRTC facts | **DONE** [`docs/layer-0-toolchain.md`](docs/layer-0-toolchain.md) |
| 1 | Graphics pipeline. **The C64 mixes hires and multicolour cells on one screen**, per cell by bit 3 of the colour nibble, and a character's mode changes between decks — so the charset is built at deck load | **DONE** [`docs/layer-1-graphics-pipeline.md`](docs/layer-1-graphics-pipeline.md) |
| 2 | Static deck render: a deck decoded into a 64 × 16 tile map, expanded to characters at draw time. Also where the `PARA`/`PARADAT` disc split comes from. (The RLE this layer built was replaced by ZX0 streams in 13d; the tile map is unchanged) | **DONE** [`docs/layer-2-static-render.md`](docs/layer-2-static-render.md) |
| 3 | Scroll: the circular strip and the three-cycle rupture. **Most of the port's hardware knowledge is here** — CRTC write windows, why R5 must not be touched near a cycle boundary, and why one hardware wrap costs the 16th row | **DONE** [`docs/layer-3-scroll.md`](docs/layer-3-scroll.md) |
| 4 | Player sprite, speed model, dead-zone camera, wall collision — then the level-draw rewrite, full-diagonal 38,472 → 19,172 cycles | **DONE** [`docs/layer-4-player.md`](docs/layer-4-player.md) |
| 5 | Droid movement and the ship's roster; **the player spawns on waypoint 0**. Then the **compiled blitter**, 13,998 cycles a sprite → 5,814, four shifts across two banks | **DONE** [`docs/layer-5-droids.md`](docs/layer-5-droids.md), [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md) |
| 6 | Droids live: line of sight, collision, the mode dispatch. Slot **ownership** separated from `sprActive`, so a droid hidden behind a wall keeps its slot | **DONE** [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md) |
| 7 | Combat: the player as droid entry 0, energy, aging, BCD score, recharge pads, and bullets and explosions as a second sprite class in the same eight slots. **7g and 7h, 2026-08-20**: the `CollisionType` matrix, friendly fire, the disruptor, the recharger's animation and the ALERT lamp | **DONE** [`docs/layer-7-combat.md`](docs/layer-7-combat.md) |
| 8 | Doors, lifts and the deck-selection screen. Taken ahead of 6 and 7, because droid AI routes *through* doors | **DONE** [`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md), [`docs/layer-8b-lift-view.md`](docs/layer-8b-lift-view.md) |
| 9 | HUD and console: the status line is the C64's and nothing else, and the console is `ConsoleMain`'s line for line, all four pages working | **DONE** [`docs/layer-9-hud.md`](docs/layer-9-hud.md) |
| 10 | The transfer minigame, entered the original's way, all three outcomes landing on the droid tables | **DONE** [`docs/layer-10-transfer.md`](docs/layer-10-transfer.md) |
| 11 | Title, game over, and the boot split. **11a, 11b and all of 11c are built — the game loops through the title after a game over (2026-08-20)**; the 001 screen (11d) and sound (11e) are in the feature list above | **PART** [`docs/layer-11-sound-title.md`](docs/layer-11-sound-title.md) |
| 12 | **Balance, fidelity and feel.** Not a feature layer: the fidelity audit against the listing, the Redux fix list triaged, playtesting against the isolated dials, and graceful degradation. Verify before tuning, or a fidelity bug gets balanced around instead of fixed | **TODO** [`docs/layer-12-balance.md`](docs/layer-12-balance.md) |
| 13 | Memory and machine compatibility. **13a, the RAM pass, is done — +6,085 bytes, no cycle cost, no behaviour change. 13d, the space pass, is done 2026-08-20** — the title overlay, the game-over loop, the droid portrait and the ZX0 deck maps. 13b is sideways-RAM detection at boot, of which there is none today; 13c is running on the machines people actually have | **PART** [`docs/layer-13-ram-pass.md`](docs/layer-13-ram-pass.md), [`docs/layer-13d-space.md`](docs/layer-13d-space.md), [`docs/layer-13-compatibility.md`](docs/layer-13-compatibility.md) |
| 14 | **The visual pass, deliberately last.** Every deck's and every screen's palette settled with `tools/palette_lab.py`, plus redrawing the characters that fight MODE 1. **STARTED 2026-08-22**: the deck floor is dithered to half intensity (DECISION 1), which turned out to buy a fifth tone that decks 0, 5 and 9 spend on grey (DECISION 2); dithering the static screens was tried and reverted, and they take a solid per-deck background instead (DECISION 4). Still to do: the remaining screens' palettes, the characters that fight MODE 1, the ALERT lamp's blinking fourth state, and the cleared-deck repaint | **in progress** [`docs/layer-14-visual.md`](docs/layer-14-visual.md) |
