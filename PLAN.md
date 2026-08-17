# Paradroid → BBC Micro Model B: Port Plan

Living document. Revised as each layer lands.

**Completed layers keep their working notes in [`docs/`](docs/)** — the measurements, the dead ends
and the hardware facts that were bought the hard way. This file holds the state of the port, the
memory map, and one paragraph per layer saying what landed and where the detail is. If a layer's
detail has stopped being needed to make the next decision, it belongs in `docs/`.

| | |
|---|---|
| [`docs/memory-map.md`](docs/memory-map.md) | **The detailed map** — every region of main RAM and both banks, from the label dump, with the boot staging overlay and what is actually free |
| [`docs/decisions.md`](docs/decisions.md) | Decisions taken, why MODE 1, and which Paradroid the listing actually is |
| [`docs/graphics.md`](docs/graphics.md) | Where the C64's graphics data lives and which tool reads it — plus, per section, what has been ported and what has not |
| [`docs/layer-0-toolchain.md`](docs/layer-0-toolchain.md) | Toolchain, and the first confirmed CRTC facts |
| [`docs/layer-1-graphics-pipeline.md`](docs/layer-1-graphics-pipeline.md) | The C64 → MODE 1 conversion, hires/multicolour, per-deck palettes |
| [`docs/layer-2-static-render.md`](docs/layer-2-static-render.md) | Tile map, deck decode, the `PARA`/`PARADAT` split |
| [`docs/layer-3-scroll.md`](docs/layer-3-scroll.md) | The circular strip, the three-cycle rupture, CRTC register timing |
| [`docs/layer-4-player.md`](docs/layer-4-player.md) | The player sprite, the speed model, the level draw rewrite |
| [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md) | Compiling the sprite blitter — 14,000 cycles to 5,800 |
| [`docs/raster-timing.md`](docs/raster-timing.md) | **Where the main loop sits against the beam** — the frame, what writes the buffer when, and the plan for flicker and edge tearing |
| [`docs/layer-5-droids.md`](docs/layer-5-droids.md) | Droid movement: the roster, waypoints, and the waypoint-0 spawn |
| [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md) | Line of sight, collision, and the mode dispatch |
| [`docs/layer-7-combat.md`](docs/layer-7-combat.md) | **Combat — 7a-7f all landed** — bullets, explosions, damage, score, Alert, the recharge pads, and what is deliberately deferred |
| [`docs/bug-map-corruption.md`](docs/bug-map-corruption.md) | **OPEN BUG, read before resuming** — something writes the tile map in play. The instrument is built and verified; it needs a play session to fire |
| [`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md) | Doors (built) and lifts (planned), and the character-map problem they raise |
| [`docs/layer-9-hud.md`](docs/layer-9-hud.md) | **The status line and the console** — what the C64's status area actually is, the $7000 font's three out-of-line codes, the $C000 string table, and all four pages behind the menu icons |
| [`docs/master-extensions.md`](docs/master-extensions.md) | Things only a Master 128 could host. Not on the critical path |

## Where we are — read this first

**Layers 0–9 are done.** The port boots to a playable deck: the C64's own status box above a 320 × 120 play area, the player droid near the centre with its rotor spinning,
and the deck hardware-scrolling 8 ways underneath it — 4 px horizontally, 1 scanline vertically —
driven by the C64's own acceleration model and stopped by walls. The camera has a dead zone, so at
low speed the world holds still and the droid glides at 1 px instead of the world lurching at 4.
Frame-locked at 25 Hz (2 fields a pass) in every direction including full diagonal. 16 decks,
per-deck palette and charset built at load time, and the game **starts on a random deck 4-7** as
`$12B6` does — `random AND 3` plus 4, the middle of the ship. The status line is the original's:
the rounded box, the Paradroid logo, the mode word and the score, in a palette of its own. Walk
onto a console and the play area becomes the original's console screen, names and all. Keys: Z/X left/right, K/M up/down (and, in a lift,
choose the deck), L fire — which steps into and out of a lift — cursor up/down for a debug deck hop,
SPACE forces a full redraw.

Seven sprites cost **36,274 cycles of the 79,872 in a pass** and the droid AI another 17,000, so the
loop still has roughly a third of the pass spare. That is after the blitter was compiled and cut from
14,000 cycles a sprite to 5,800 — see [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md), which
also records what was costed and *rejected*, round-robin updating chief among them. **Where that
work lands against the beam matters as much as what it costs**, and that is
[`docs/raster-timing.md`](docs/raster-timing.md).

**The ship is traversable.** Doors open when you walk into them and close behind you; lift platforms
take RETURN and then UP/DOWN to move through the decks their shaft serves. Both are the C64's own
mechanisms — bit 7 of the character code for a door, a table walk for a lift. See
[`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md).

**The deck is populated.** Layer 5's droid half has landed: a ship-wide roster, droids standing on
each deck's waypoints and patrolling between them, and the sprite pool allocated and freed as they
come into view. The player spawns on waypoint 0, which closed `BUGS.md` #4. See
[`docs/layer-5-droids.md`](docs/layer-5-droids.md).

**And it is alive.** Layer 6 added the deck's own walls to the picture: a droid out of the player's
line of sight is not drawn, droids bump into each other and into the player, and the driver
dispatches on droid mode so Layer 7's bullets and explosions are a table entry rather than a
rewrite. See [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md).

**The loop is now built around the raster.** A pass is two fields and each opens a 24,576-cycle
window with the play area blanked; every buffer write belongs in one. The droid AI moved after the
drawing (it writes nothing), the sprite pool splits into two tranches with each restored *and* drawn
inside a single window, and the loop counts windows in the IRQ rather than consuming a flag. Both
symptoms KC reported — edge tearing while scrolling and sprites blinking at 25 Hz — come out of that
timing, and [`docs/raster-timing.md`](docs/raster-timing.md) is the map: the frame in cycles, what
writes the buffer when, and what is still open.

**Layer 7 is done** — combat: bullets, explosions, damage, score, the Alert level and the
energy recharge pads. **7a–7f all landed, 2026-08-15/16**, on branch `layer7-combat`: the player has
energy, the droid he is riding wears out on the C64's own schedule whether or not anything shoots at
him, standing on a recharge pad puts energy back at 5 points of score each, the pool draws bullets
and explosions as well as droids, and **L fires** — a bullet that flies at the original's own 12 px
a pass and dies on walls, a droid it hits explodes and scores, and **the droids shoot back and can
kill you** — at which point you explode where you fell, over `EF_EXPLODE_N` iterations, and come
back as a 001 on waypoint 0. Planned in
[`docs/layer-7-combat.md`](docs/layer-7-combat.md), in six stages, and
four findings shape it: **droid-table entry 0 is the player, not a sentinel**; the C64 has an eighth
sprite that we do not, for the player's own bullet; bullets and explosions come out of the existing
pool of six so **the sprite count per pass does not grow**; and an explosion cannot be compiled, so
the layer's largest new piece is a generic interpreted sprite path with a per-frame bounding box.
The three open decisions were settled on 2026-08-15 and are tabled at the end of that document:
the player **explodes and respawns as 001 on waypoint 0** at zero energy, **L does double duty** as
fire and lift — which the original does too, through the `moveMode` machine, so `lift.asm`'s trigger
was right all along — and the explosion ships as many frames as bank 4 allows while keeping its full
twelve-iteration length.

**Before trusting any speed number, read the speed model section of
[`docs/layer-4-player.md`](docs/layer-4-player.md).** The C64's constants are per `GameLoop`
iteration and an iteration is 2–3 frames, not 1. Every droid speed in `PlayerSpeed_t` needs the same
conversion, so this comes up immediately in the droid work.

### Five things anything drawing into the play buffer has to know

1. **Display row *r* holds map row `mapYr + r`, all eight scanlines.** That is the strip's invariant
   and it is unconditional — there is no split row. It used to be one, and everything writing a whole
   cell into display row 0 needed a repair pass; that went with the whole-row band.
2. **Adjacent 4-pixel columns are 8 bytes apart, not 1.** Consecutive bytes within a column are
   consecutive scanlines. This cost a build.
3. **The draw window is frame rows 23 → 8 of the next frame**, released by `drawFlag` at `P+184`
   when the play area stops displaying. Everything shares it. `DEBUG_DRAW` tints it: magenta the
   sprites, yellow the level draw, cyan everything else.
4. **`LDA abs` is 4 cycles and `LDA zp` is 3 — but `LDA abs,X` and `LDA zp,X` are both 4.** Zero page
   is fully allocated now (`&00–&8F`, map in `main.asm`); it went to scalars, and indexed tables
   gained nothing by moving. Worth knowing before costing a zero-page change.
5. **`mapYr` and `cellY` are SIGNED, and the row being drawn may be off the map.** The view scrolls
   up to `PLY_VOID` (64 px) beyond each vertical edge so the player can reach rows 0 and 63 — see
   the clamp note in `player.asm`. Map rows are 0–63, so one `AND #&C0` catches both ends, and every
   path that turns a row into characters already does it: `BandSetRow`, `DrawColumn` and `MapChar`.
   Anything new that reads a map row must too, or it indexes off `mapRowLo`.

### Verification that actually works here

Diff the play buffer against `RedrawAll` at the same position (SPACE), byte for byte. Screenshots
have repeatedly said "fine" when it was not. Drive it over **odd and even** `mapHX`, **non-zero
`line`**, and **diagonals** — every scrolling bug so far has hidden in one of those. Allow
~1,500,000 cycles to settle before dumping, or the oracle is sampled mid-redraw, and poke
`JSR SprDrawAll` to NOPs so the rotor cannot pollute the diff.

For a change that is meant to be purely mechanical, there is a faster check that is also stronger:
reduce both builds' beebasm listings to a stream of (mnemonic, addressing class) and compare. If
they match, no instruction was added, removed or reordered. That settled the zero-page pass in
seconds where a buffer diff would have taken an emulator run.

> **jsbeeb will not boot an unpadded SSD.** It hangs in the DFS FDC poll loading `PARASPR`, because
> beebasm's image ends mid-track and jsbeeb will not read the last partial one. Pad a copy to 200K
> before handing it to an emulator or publishing it. This cost an hour before it was recognised as
> an emulator problem rather than a game one.

### Open items, in the order they are likely to bite

| | |
|---|---|
| ~~Main RAM below `&3000`~~ | **Relieved twice.** 2026-08-14: `screen.asm`, `scroll.asm` and `level.asm` into bank 4, beside the tile and deck data they read, with `src/bufcore.asm` holding the 480 bytes that cannot be banked. 2026-08-15: `droid.asm` followed them, which is what made room for the raster work. Main RAM is `&1100–&27D9` with **2,086 B free** |
| ~~1 px sprite positioning~~ | **Done 2026-08-14**, on branch `layer5-1px-shifts`. Four compiled shifts across two sprite banks; the droid is drawn exactly where it is, as the C64 draws it. Cost **+122 cycles a pass** on `SprDrawAll`, measured, and a third 16K bank. See [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md) |
| ~~Main RAM: 116 bytes left~~ | **Relieved 2026-08-15.** `droid.asm` moved into bank 4 beside the waypoints, speeds and deck data it reads, and next to `MapChar` which it calls. Main RAM is `&1100–&2600`, **2,560 bytes free**; bank 4 ends `&B5C3` with 2,621 free |
| ~~Droids inside walls~~ | **Fixed 2026-08-15**, `BUGS.md` #8. `DroidsInit` skipped empty roster indices instead of emptying them, so every deck after the first inherited the previous deck's droids at the previous deck's coordinates. Invisible to every unattended test, all of which ran on deck 1 from a cold boot — **enter a second deck before believing a droid result** |
| Droid collision feel | `BUGS.md` #7 — droids lock together, and the player bounce reads as heavy. Tuning, by eye, in one sitting: `DR_COL_W`/`DR_COL_H`, `DrPause16`'s 16, and the `ASL A` in `DrBounce` |
| Droid worst case unmeasured | 7 sprites (36,274) + droids (17,000) + full-diagonal level draw (19,172) is 72,000 of 79,872 before the rest of the loop. It never arose by chance; it wants a rig on a deck with a long open corridor. See [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md) |
| **Flicker and edge tearing** | **Step 1 done 2026-08-15**: the droid AI moved after the sprite draw, so the level draw is back inside the off-display window — entering `DoRedraws` with the beam over the play area went 116 of 128 to **0 of 128**, and `SprDrawAll` now finishes inside the window on 93 of 128. **Step 2 built 2026-08-15**: the pool splits across the two windows, each tranche restored and drawn inside one, guarded against the level draw and against sprites straddling the tranches. It works, but the fixed 0-2 / 3-6 split refuses whenever a droid walks beside the player — assigning tranches by overlap component instead is the next move. Originally measured 2026-08-15. The restore is the only buffer phase inside the off-display window: `DoRedraws` runs with the beam over the play area on 116-124 passes of 128 and `SprDrawAll` on 120. **The budget is not the problem** — 49,152 cycles of window a pass against 36,274 of sprite work — the work is in the wrong places, and Layer 6's AI is what pushed it there. Staged plan in [`docs/raster-timing.md`](docs/raster-timing.md) |
| 2 px world scrolling | Parked, Master-only via shadow RAM. Costs +60–80% on all drawing because both buffers must stay current — see [`docs/master-extensions.md`](docs/master-extensions.md) |
| Play area is 320 × 120, not 128 | Consequence of the single hardware wrap — see Layer 3d. Getting the row back needs the 20K wrap or per-cycle wrap bits. **KC's call** |
| Vertical granularity | 1 scanline against 4 px horizontal is lopsided. 2 or 4 scanlines costs nothing extra. There are droids to move now, so this is decidable |
| `$D021` is an assumption | Marked `[assumed]` in `export_bbc.py`. First suspect if deck colours look wrong on hardware |
| ~~Panel shares the play palette~~ | **Fixed 2026-08-16.** The panel is its own CRTC cycle, so it is its own palette: `SetPalette` builds a `palPlay` table in main RAM and the rupture blasts sixteen ULA writes at each boundary — the panel's at the end of `RuptVSync`, the deck's at the end of fire 1. The status box is white/black/red as the C64's is, on every deck. ~210 cycles twice a frame |
| `keydown` uses OSBYTE `&81` | The last OS call in the main loop |
| 8 decks draw ALERT in multicolour | Confirmed faithful to the C64 original, not a bug. Worth a look on real hardware |
| **Transfer: no droid info screens** | The C64 shows two full-screen robot data pages (`ShowXferInfo`, `$3734`) — yours and the target's — before the board appears. Not ported; the game goes straight to side select. Wants doing alongside Layer 11's presentation work, which is where the token-string machinery it needs gets its second user |
| Transfer presentation differs for screen room | The C64 keeps status rows *above* its board; our board takes all 16 play rows, so the counter, the two droid numbers and the verdicts moved to the panel's text line, and the side-select droid *sprites* became the two numbers swapping ends. Decisions 6–8 in [`docs/layer-10-transfer.md`](docs/layer-10-transfer.md) |

## Decisions taken

Full reasoning, and the measurement that settled which Paradroid the listing is, in
[`docs/decisions.md`](docs/decisions.md).

| Decision | Choice | Date |
|---|---|---|
| Target machine | BBC Model B / B+ with **2 × 16K sideways RAM banks** | 2026-08-04 |
| Target machine, revised | **3 × 16K sideways RAM banks** — a B+ 128 or a B with a 32/64K SWRAM board. A compiled shift is ~5.5 K of code and 1 px positioning needs four of them, which does not fit in two banks. See [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md) | 2026-08-14 |
| Screen mode | MODE 1, 4 colours, **10K wrap at `&5800–&7FFF`** | 2026-08-04 |
| Screen layout | 3-cycle vertical rupture: 5-row panel at `&4800`, 3-row gap, scrolled play area | 2026-08-05 |
| Play area | **320 × 120** — 10 tiles wide, 15 character rows. See Layer 3d for why not 128 | 2026-08-05 |
| Scrolling | CRTC hardware scroll over a circular strip. **4 px horizontal, 1 scanline vertical** | 2026-08-05 |
| Interrupts | We own IRQ1V outright, System VIA T1 continuous. No MOS chaining, no MOS sound | 2026-08-04 |
| Architecture | No HAL. Build one working layer at a time, verified in the emulator before moving on | 2026-08-04 |
| Source version | **1985 original / 1986 Competition Edition** lineage — which is what `paradroid_ce.lst` already is. Redux's bug list adopted as a spec, not as code. Heavy Metal parked as a possible later tile set | 2026-08-06 |
| Game loop rate | **Locked to 2 fields a pass**, not free-running — a full sprite pool does not fit in a field, and free-running made the player 20 % slower whenever droids were visible | 2026-08-13 |
| Sprite blitter | **Compiled**, not interpreted: generated 6502 per rotor row and per digit glyph, in a sideways bank of its own | 2026-08-13 |
| Player top speed | **8 px a pass, not the C64's 7** (`CAM_TOPSPD`, `main.asm`) — the only movement number not taken from the original. 7 cannot divide the CRTC's 4 px step, so the camera dithers 8,8,8,4 and the scroll stutters; 8 is uniform. 14 % fast, bought deliberately. `PLY_ITER_FRAMES = 3` + `CAM_TOPSPD = 7` is the exact-1985 alternative and lost on feel | 2026-08-14 |
| Target machine, revised again | **4 × 16K sideways RAM banks** — bank 7 (`PARXFER`) holds Layer 10's transfer game. Banks 4–7 is the Master's own sideways RAM numbering | 2026-08-16 |
| Transfer board shows all 16 rows | The play area always *displays* 16 rows; only fire 3's R8 blank hides the smooth scroll's spare one. The rupture's fire-2→3 interval became a variable (`t1i3`) so the transfer can move the bottom edge down a row and give the board the C64's full 16 | 2026-08-16 |

## Memory budget

**[`docs/memory-map.md`](docs/memory-map.md) is the map** — every region of main RAM and both banks,
region by region, taken from a `-dd` label dump of the build rather than from a plan, along with the
boot staging overlay and what is genuinely free. Read it there and regenerate it when a region
moves. The outline:

| Region | Size | Contents |
|---|---|---|
| ZP `&00–&8F` | 144 B | **all of it used** — the map is in `main.asm`. `&90` up is the OS |
| `&0400–&0C8F` | 2,192 B | MODE 1 charset, built at deck load — reclaimed OS workspace |
| `&0C90–&10FF` | **1,136 B free** | rest of the reclaimed OS workspace |
| `&1100–&2FCA` | 7,883 B | code (`PARA`). DFS random-access buffer space, safe for `*LOAD` |
| `&2FE8–&2FFF` | **24 B free** | **the binding constraint.** Layer 10 paid its way in by moving `CalcAxis`/`CalcSpeed` and its own shims into bank 4, and Layer 8b's lift view by deleting the routines it replaced; the deck plan's `ConsoleTick` arm took most of what was left, and the droid database's arm 33 bytes of the rest. Anything new in main RAM needs the same treatment |
| `&3000–&37FF` | 2,048 B | sprite background save areas, one page per slot — **eight now**, ending exactly where the tile map begins. A ninth would overwrite it |
| `&3800–&3BFF` | 1,024 B | tile map, fixed home — floating it after `code_end` once put it over the save areas |
| `&3C00–&483F` | 3,136 B | **Layer 9's text font**, `PARAFNT`, `*LOAD`ed straight here — 98 glyphs |
| `&4840–&48FF` | 192 B | the status box's twelve border cells, same file |
| `&4900–&495F` | 96 B | the four droid tables, mirrored out of bank 4 for the panel in bank 6 |
| `&4960–&49FF` | 160 B free | |
| `&4A00–&53FF` | 2,560 B | panel — **4 rows** × 640, the C64's status box exactly, displayed by rupture cycle 1 |
| `&5400–&54FF` | **256 B free** | |
| `&5500–&56FF` | 512 B | `CHAR_PTR_LO`/`HI` — character code → charset address, built at startup |
| `&5700–&57FF` | 256 B | data byte → transparency mask table, built at startup |
| `&5800–&7FFF` | 10,240 B | play buffer: circular strip, 16 rows × 640 |
| SWRAM bank 4 | 16 K | `PARADAT` — char data, colour schemes, tile defs, deck RLE, waypoints, the combat stat tables, **the level-draw code, the droid AI, Layer 7's combat, Layers 10 and 8b's entry/exit shims, and `CalcAxis`/`CalcSpeed`**. Ends `&BED0`, plus the console's menu and page shims — **303 B free** |
| SWRAM bank 5 | 16 K | `PARASPR` — the blitter at shifts 0 and 1 px, **plus Layer 7's effect artwork**: 31 bullet and explosion frames, 2,946 B, here rather than in bank 4 because the interpreted path reads them every row. Ends `&BBF7`, **1,033 B free** |
| SWRAM bank 6 | 16 K | `PARSPR2` — the same at 2 and 3 px, laid out identically, **plus Layer 9's panel engine, HUD, console, strings and icons**. Ends `&BFC6`, **58 B free — full** |
| SWRAM bank 7 | 16 K | `PARXFER` — **Layer 10's transfer game and Layer 8b's lift screen**, sharing the shadow screen/colour RAM, the glyph page and the renderer pattern; plus both glyph sets, the console's ship page, **the deck plan** (`condeck.asm`, `plandata.asm`) and **the droid database** (`condb.asm`, `droidinfo.asm`) with its second copies of the string table and the droid icon. Ends `&B7E5`, **~2.0 K free** |

**"Main RAM is full" meant the `PARA` image could not grow past `&3000`** — never that there was no
RAM. Moving code rather than data is what fixed it: `screen.asm`, `scroll.asm` and `level.asm` now
live in bank 4 next to the tile and deck data they read, which costs no paging because that bank is
the resting state. `src/bufcore.asm` holds the 480 bytes that could not go — the routines that run
before the bank is loaded, or with the *sprite* bank paged in.

Only one bank is visible at a time. That works because the two halves are never wanted at once —
`DoRedraws` reads tiles, the blitter reads none of them — so `SprRestoreAll` and `SprDrawAll` page
their own bank in and the data bank back out around themselves. **The IRQ reads neither**, which is
what makes it safe; check that again before putting anything else in a bank.

`PARADAT` and `PARASPR` are staged through `&3000` by `*LOAD` and copied up, because the MOS has the
DFS ROM paged in at `&8000` during a filing-system call. The staging area overruns the panel and the
bottom of the play buffer, which is safe only because `PageBankIn` runs before either is next read.
Boot shows a moment of garbage in the play area.

## Layers

Each layer ends with something visibly working in b-em. Nothing moves on until it does.

### Layer 0 — Toolchain and a booting screen ✅ DONE
`bin/beebasm.exe`, `build.ps1`, jsbeeb MCP for in-loop verification, and the first measured CRTC
facts — start address ÷ 8, the pixel address formula, MODE 1 byte encoding. Its screen layout is
superseded by Layer 3. → [`docs/layer-0-toolchain.md`](docs/layer-0-toolchain.md)

### Layer 1 — Graphics data pipeline ✅ DONE
`tools/export_bbc.py` converts the C64 artwork to MODE 1 and `verify_bbc.py` round-trips it back.
The find that shaped everything after it: **the C64 mixes hires and multicolour cells on the same
screen**, chosen per cell by bit 3 of the colour RAM nibble, and a character's mode changes between
decks — so the charset is built at deck load rather than shipped 16 times over.
→ [`docs/layer-1-graphics-pipeline.md`](docs/layer-1-graphics-pipeline.md)

### Layer 2 — Static deck render ✅ DONE
RLE deck decode into a **64 × 16 tile map (1 K)**, expanded to characters at draw time rather than
the C64's 16 K character map — two extra lookups per character for a 15 K saving. This is also where
the `PARA`/`PARADAT` disc split comes from: `VDU 22` clears `&3000–&7FFF` before anything loaded
there can be read. → [`docs/layer-2-static-render.md`](docs/layer-2-static-render.md)

### Layer 3 — Scroll ✅ DONE (3a–3d)
CRTC hardware scroll over a circular strip at `&5800`, 4 px horizontally and 1 scanline vertically,
under a **three-cycle vertical rupture** that keeps a static panel above a scrolled play area. Most
of the hardware knowledge in this port is in here: which CRTC registers may be written when, why R5
must never be touched near a cycle boundary, and why the display window must fit inside one hardware
wrap — which is what costs the port its 16th character row.
→ [`docs/layer-3-scroll.md`](docs/layer-3-scroll.md)

### Layer 4 — Player droid: sprite, controls, collision ✅ DONE
The 24 × 21 player sprite with its 8 rotor phases (constructed at runtime on the C64, so exported by
replaying `BuildDroidSprite` and `AnimateDroids` offline), the C64 speed model, the dead-zone camera,
and wall collision. Then the frame budget: the level draw was measured and rewritten in stages,
full-diagonal redraw going **38,472 → 19,172 cycles** and vertical **28,527 → 10,787**, with the
split row ceasing to exist on the way. Two thirds of what remains is the byte movement itself.
→ [`docs/layer-4-player.md`](docs/layer-4-player.md)

### Layer 5 — Droid movement ✅ DONE
`src/droid.asm`: the ship's droid roster generated by `NextLevel`'s own rule, each deck's droids
standing on its waypoints, and `GetNewDir`/`AdvanceMapPos`/`CheckDroidAdvance` walking them between
junctions. Sprite slots are allocated and freed by `DroidNear`'s test, matched exactly to the
blitter's cull — approximately was not good enough, and cost a deck its droids. `droidtest.asm` and
`TEST_DROIDS` are deleted.

**The player now spawns on waypoint 0**, which retires `CentreOnDeck` and closes `BUGS.md` #4:
0 of the 239 waypoints on the 16 decks is in a wall, checked offline against the same RLE decode
that reproduces the port's tile map byte-for-byte.

`DroidsUpdate` costs **15,576 cycles a pass with 11 droids**, 19.5% of the 79,872 in a pass and in
line with the ~14,000 the C64 spends in `RunDroids`.
→ [`docs/layer-5-droids.md`](docs/layer-5-droids.md)

**The blitter half is done.** Seven slots at the Layer 4 cost did not fit in a frame, so the blitter
was compiled — generated 6502 per rotor row and per digit glyph, in a bank of its own — taking a
sprite from **13,998 cycles to 5,814**. Read that document before optimising anything here: it
records what was costed and rejected as well as what landed, and round-robin updating in particular
should not be revived without reading why it was dropped.
→ [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md)

### Layer 6 — Droids ✅ DONE
Line of sight (`LineOfVisibility`, walked without a division and with the answer taken one droid a
pass), collision (`DoCollision`/`DoCollision2`'s movement half), and the `DroidModeJump` dispatch.
A droid behind a wall keeps its sprite slot and is not drawn, which needed slot **ownership**
separated from `sprActive`.

Collision is the one place in the droid work with no faithful port available: the C64 reads the
VIC's pixel-exact `$D01E` and a software blitter has nothing to read, so it is a box test —
deliberately smaller than the sprite, because most of a droid's corners are the rotor's transparent
gaps. Costs **~1,400 cycles a pass** over Layer 5, and the frame lock holds in every case measured.
→ [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md)

### Layer 7 — Combat — **planned, nothing built**
`DoFire`/`MovePlyFire`, `dMd1_bullet`, `dMd2_explosion`, `DoCollision`/`DoCollision2`'s damage arms,
`KillDroid`, `AddScore`, `DoAlertAndAging` and `DoCharUnder`. The core game is playable at this
point. Six stages, each ending in something visible:

| | |
|---|---|
| 7a ✅ | **DONE 2026-08-15.** `src/combat.asm`: entry 0 becomes the player, `AddScore`'s BCD, `DoAging`, the `gameTick` iteration counter, and a `DEBUG_ENERGY` readout on panel row 1 because the panel that would show any of it is Layer 9's. `DroidsInit` no longer clears entry 0 — measured surviving a deck change |
| 7b ✅ | **DONE 2026-08-15.** `DoCharUnder`'s recharger arm — **the recharge pads**, character 20: +1 energy every 4th iteration and −5 score, plus `SubScore`. Rate, ceiling, BCD wrap, zero-saturate and a control all measured exact. The lift arm is not ported: **L does double duty as fire and lift trigger in the original too**, through `moveMode`, so `lift.asm` keeps its trigger |
| 7c ✅ | **DONE 2026-08-15.** Effect sprites as a second class sharing all the slot machinery: 31 frames exported with bounding boxes into **bank 5** (0/31 round-trip mismatches, no frames cut), a generic interpreted draw/restore, and `SPR_SLOTS` 7 → 8 for the player's bullet at save page `&3700`. Draw verified pixel-exact at shift 3; restore and the scrolling oracle both **0 of 10240** |
| 7d ✅ | **DONE 2026-08-15.** `DoMoveMode`'s Mobile/Weapon/Transfer machine, `DoFire`, `MovePlyFire` and the wall test. The bullet's position is **world, not screen**, so the C64's scroll compensation does not port. Flight measured at exactly +12 px a pass, the original's own value. **403 B of main RAM left** |
| 7e ◐ | **Kill chain DONE 2026-08-15**, in bank 4 beside `DrCollided`: `DrBulletHit`, `DrPlyFireEnemy`, `DrKillDroid`, `DrExplodeSprite` and the mode-2 `DrExplode`. Shoot a droid and it explodes over 11 frames, one a pass, scoring by class and raising Alert by its type. **Deferred to 7f**: the arms that damage the *player* and the death that follows, with `CollisionType`, `BumpScore` and `EnemyFireEnemy` — nothing can hurt him until enemy fire exists and they are all one arm |
| 7f ✅ | **DONE 2026-08-16.** `DrEnemyFire`, `DrAddBullet`, the mode-1 `DrBullet` and `DrHurtPlayer`'s three damage arms, plus death and respawn. Droids shoot back and can kill you. **Deferred**: the disruptor, friendly fire, the bullet's colour flicker and the player's own explosion before he respawns |

**`droid.asm`'s header is wrong from here on** and says so where it claims entry 0 is a sentinel:
the C64 reads `droidEnergy`/`droidType`/`droidFireDelay` unindexed all through the combat code, and
that is the player. Correct it when 7a lands.
→ [`docs/layer-7-combat.md`](docs/layer-7-combat.md)

### Layer 8 — Doors, lifts, decks ✅ DONE — **taken ahead of 6 and 7**
`OpenDoor`, `CloseDoors`, `DoLift`, `FindLift`, `ChangeDeck`. The whole ship becomes traversable.

**Moved ahead of the droid layers deliberately.** The player is currently sealed into one room, and
droid AI, waypoints and pathfinding are all deck-scale behaviours that route *through doors* — there
is no way to evaluate them until doors open. Building droids first means building them against a
world they cannot move around in.

**8a, doors, has landed** (`src/door.asm`). A door is **bit 7 of the character code**, which
`CheckWalls` already tests: clearing it makes the cell passable and selects the open graphic in one
bit. The C64 mutates its 16 K expanded character map and we deliberately do not have one, so each
open door gets a patched private copy of its 16-byte tile definition — which costs nothing per
character, because the draw already selects a tile definition per tile. Verified against `RedrawAll`
byte-for-byte with a door open and again after it closed: 0 differences in 10240 both times.

Doors also needed their own probe sweep. `ProbeGroup` runs only when there is speed on that axis and
abandons a group at the first wall, and both defeat a door — read that note before touching the
probes.

**8b, lifts, has landed too** (`src/lift.asm`). Stand on a lift platform, press L, and K/M move
through the decks that shaft serves — which are *not* adjacent, so stepping walks a table. The
platform turned out to be tile 3 at the C64 view origin + (5, 2), found by searching for the offset
that gives a consistent tile across all 30 stops (30/30 against a next-best of 21/30) — it is not
written down anywhere in the listing.

**The deck-selection screen landed 2026-08-17** (`src/liftview.asm`, bank 7, on Layer 10's shadow
machinery): fire on a lift pauses the game and shows the C64's ship cross-section — your shaft
marked magenta, the selected deck lit yellow, "lift" and the deck number on the panel line — K/M
walk the selection, fire commits with ONE deck load (the C64 rebuilds per step; ours cannot, the
buffer is the view — decision 1 in the doc). An unmoved fire returns without a load.
→ [`docs/layer-8b-lift-view.md`](docs/layer-8b-lift-view.md)

**Arrival now comes from the lift table where there is one**, and from **waypoint 0** everywhere
else — the first deck and the debug deck hop included. `CentreOnDeck` is gone, and `BUGS.md` #4,
"lands inside a wall on some decks", closed with it in Layer 5.
→ [`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md)

### Layer 9 — HUD and console — **the status line and the console screen are DONE**
Plan and every decision taken: [`docs/layer-9-hud.md`](docs/layer-9-hud.md).

Two things the earlier one-line plan ran together. The C64's **status area is eight character rows**
at the top of the screen; the **console is a separate full-screen mode**, entered from character 66.

**The status area's artwork is four `DrawString` calls** — `$6900`, `$6917`, `$6937`, `$693C` from
`StartGame` — and the ink in them runs from scanline 8 to scanline 39. **The box is 32 scanlines,
not 64**, inside a region that is otherwise flat surround. So `PANEL_ROWS` is **4**, and dropping
from 5 cost one CRTC register: R6, written at VSync. No T1 interval moved and the play area did not
shift a scanline.

The constraint that shapes the layer: the text font at `$7000` is **8 × 16, not 8 × 8** — top half
at code `c`, bottom half at `c + $80` — so a glyph is two stacked MODE 1 cells, 32 bytes. The
4-row panel is therefore a border row, **one** line of 40, and a border row.

Two things the listing settles that the earlier plan had wrong. **Capitals are 16 px wide**, right
half at code `+ $20`, which `DrawChar` tests for outright at `$0C82` — so columns count cells, not
letters. And **`$31-$37` are the Paradroid logo**, not "frame pieces": the frame is `$55-$59`,
`$7A`, `$7B`, `$7C`.

**Built:** the font as a fourth disc file `PARAFNT` at `&3C00`, now carrying the logo, the box bar
and twelve border cells as well; the panel text engine, the HUD and the console, all in **bank 6**
— bank 4 had 224 bytes too few — with a main-RAM bridge for the droid tables and two live scalars.
The console takes over the **play area** rather than the whole screen. **The panel has its own
palette**, swapped at both cycle boundaries, so the box is white/black/red on every deck.

**The status line is the C64's and nothing else** (KC, 2026-08-16): the rounded box, the logo, the
mode word at column 2 — `Mobile`/`Weapon`/`Transfer`/`Console` — and the score at column 30 with
`DoScore`'s own leading-zero blanking. The droid number, energy bar, ceiling, deck number, alert
bar and droids-left the port used to show are **gone**, and with them the only two synthesised
glyphs in the project.

**The console screen is `ConsoleMain`'s, line for line**, with the original's own names out of the
`$C000` string table — `Unit type 001 - Influence Device`, `Access granted.`, and the ship, deck and
alert by name rather than number. All four menu icons are drawn, the fourth composed from a rotor
and the droid's own digits because the C64 builds it at run time and our droid artwork is compiled.

**The menu selection and the ship plan LANDED 2026-08-17** — [`docs/layer-9-hud.md`](docs/layer-9-hud.md)
§6e. `conWaitInput`'s port is `ConMenu4` in droid.asm, BANK 4 (bank 6 was full; everything the
menu touches is main RAM): K/M walk the marker 0-3 clamped as `consoleState` walks $80-$83, fire
dispatches as `conJump_t` — entry 0 back to the game, entry 3 the **ship plan**, which is
`con_ShipInfo` faithfully: Layer 8b's side view drawn once and STATIC, current deck lit, no shaft
mark, fire back to the console main with the selection kept.

**The deck plan LANDED 2026-08-17** — §6e again. `con_DeckInfo` faithfully: `DrawPacked` over the
level RLE with no ORA offset, one character per tile, the player's cell solid white, drawn once
and static, fire back with the selection kept. The page is **hires** — the console screen is
`GotoHires`'s, and `con_ShipInfo` flips multicolour back on only for the side view — so the plan
does not draw from the play-area charset at all: bank 7 carries the 31 raw bitmaps and a per-deck
ink table built at export time (`plandata.asm`), and converts each cell as it plots it. The RLE
is staged through the sprite save pages — scratch while the console is up — because bank 7 cannot
see bank 4, and the page shows all 16 map rows by the transfer game's `t1i3` trick. Consoles draw
in red by KC's ruling; the other deviations are §6e's decisions 1-7.

**The droid database LANDED 2026-08-17, and the console is COMPLETE** — §6f. `con_DroidInfo`
(`$2CC6`) and all five of `dInfoPgJump_t`'s sub-pages: the browser walks `dType` between 0 and the
player's own class and **wraps at both ends** — you cannot read up on a droid better than the one
you are wearing — and left/right pages through the stat lines and then the description, with
`More...` in the **status line** where `More_txt` puts it. Unlike the other two pages it is
interactive, so its tick runs every pass and reads the keys itself (`src/condb.asm`, bank 7);
`keydown` is main RAM, so no bank-4 key shim was needed and main RAM pays 33 bytes for the arm.
The layout is the original's line for line — its six content lines are exactly what our seven text
lines leave under the name — and the word wrap is `sub_0_BE9`'s, measuring cells and leaving an
unfitting word unconsumed so `More...` can resume mid-sentence.

Two things are ours and both are §6f decisions: the **image is the port's rotor-and-digits droid**,
not the C64's 48 × 84 portrait, which is unported artwork ~6 K of bank 7 wide (decision 16 again);
and the **string table is emitted a second time into bank 7** (`strings7.asm`, with
`droidicon7.asm`), because the console that owns the first copy is in bank 6 and only one bank is
visible at a time. Bank 7 is now **~2.0 K free**; bank 6 and bank 4 are untouched. Building it also
found a real bug in the console main screen: `ConTok` never cleared `conCap`, so the name line drew
`Influence Device` where the C64 draws `Influence device`.

**Still missing: the droid PORTRAIT.** The database page is complete except for its artwork — it
shows the small composed droid where the C64 shows `BuildIntroSprites`' 48 × 84 multicolour
picture of the type being read about. That artwork is in the unported `$5400-$67FF` sprite block
and 24 types of it is ~6 K raw, three times what bank 7 has left, so it needs its own space and a
palette decision as well as an exporter. **Deferred by KC 2026-08-17**; §6f decision 2 says what
it would take.

Still deferred: the low-energy sprite flash, which is now the *only* energy cue the port lacks —
see decisions 4 and 5 — and every `sndFx1` write in the console, for Layer 12.

### Layer 10 — Transfer minigame — **BUILT** (2026-08-17)
The whole subgame plays, entered the original's way — touching a droid at `moveMode` 0 — and all
three outcomes land on the droid tables: take the target over (type, energy, weapon, per-type
speed, shoot score), fall back to a 001 with the bump fine, or burn out as one. The target is
consumed in every outcome. Verified end to end in jsbeeb, including a real-collision entry, a
001 → 476 takeover, and a tie's short-circuit replay.

Everything about how — the shadow screen/colour RAM that keeps `xfer_DoColumn` (`$1EB6`) and the
rest verbatim, the fourth SWRAM bank, the 16th row, the palette, the eleven numbered decisions —
is in [`docs/layer-10-transfer.md`](docs/layer-10-transfer.md). Still wanted from play-testing:
difficulty feel against the C64, and consuming the last droid on a deck.

**Known gaps, recorded in the open items above**: the C64's two droid info screens before the
board (`ShowXferInfo`) are not ported, and the presentation differs where the screen has no room
for the original's — status text on the panel line rather than above the board, numbers standing
in for the side-select sprites.

### Layer 11 — Sound, title, polish
SN76489 driver replacing the SID engine, title screen, attract mode. The chip is written through
System VIA port A with handshake at `&FE41`; a latch byte is `1 cc r nnnn` and a data byte
`0 0 nnnnnn`, so a tone is `&80 | (chan << 5) | (freq AND &0F)` then `freq >> 4`, and an
attenuation is `&90 | (chan << 5) | (15 - vol)`. **That came out of the deleted `hardware.asm` and
was never verified on hardware** — check it against the wiki before building on it, per the rule
about recalled facts.

**The title screen owes the game its randomness.** The C64's random source is `$D41B`, free-running
SID noise, and what makes the starting deck genuinely unpredictable is that `$12B6` samples it
after however long the player left the title up. We have no noise source, so `drSeed` is currently
taken from the User VIA's T1 counter at boot — which varies on hardware and **not at all under an
emulator**, where two cold boots land on the same deck. Stir `drSeed` once a frame while the title
is waiting for fire and that goes away, by the original's own mechanism. See
[`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md).

### Layer 12 — Balance, fidelity and feel — **the last pass, planned**

Not a feature layer. Everything is built by now; this is the pass that decides whether it plays
like Paradroid. Four strands, and the order matters — verify before tuning, or a fidelity bug gets
"balanced" around instead of fixed.

#### 12a — Fidelity audit against the C64

**Every gameplay routine walked against `paradroid_ce.lst`, one at a time, and each one either
confirmed identical or the departure written down with its reason.** Layers 7f and 7g both shipped
a constant that had been read out of the listing without following where its input came from —
`AddBullet`'s `deltaX` looked like a raw distance and was a normalised direction (BUGS.md #11), and
the collision debounce was applied to three arms where the original applies it to one. Those are not
the kind of thing playtesting finds; they need the listing open beside the source.

The output is a table, one row per routine: C64 address, our label, **identical / deviates /
not ported**, and for a deviation the reason. Candidates already known to deviate, so the audit
starts with them rather than discovering them:

| | |
|---|---|
| collision | the VIC's `SprSprCollision` register is pixel-exact and free; ours is a box test with `DR_COL_W/H` tuned by eye. **No faithful port exists** — this is the one place with no alternative |
| the sight line | the C64 tests every near droid every iteration; ours tests one a pass (`losTurn`) on a cycle budget. A droid that steps behind a wall stays drawn up to five passes longer |
| speed | `PLY_ITER_FRAMES` and the CE's faster loop, already written up in `docs/layer-4-player.md` — confirm the movement constants still transfer byte for byte |
| the death respawn | the C64 does not move the player at all; ours teleports to waypoint 0 and re-frames. Deliberate, and the reason the corruption in BUGS.md #10 existed |
| the death explosion | the C64 draws the player's droid *under* the explosion; ours replaces it, because our player slot is always a 001 with a spinning rotor |
| culling | sprites are culled, not clipped, so a droid pops in and out a sprite's width from the edge. The C64's hardware clips |

#### 12b — The Redux fix list

**Paradroid Redux is a different codebase** — `docs/decisions.md` has the evidence: it relocates
everything and matches this listing at 1–3%. So its fixes cannot be lifted as code. What it is
good for is a **list of what Braybrook himself thought was wrong**, and each one is then a question
to ask of our own port: does the same defect exist here, and do we want it fixed or preserved?

Two of the original's own bugs are already ported deliberately and are the precedent for how to
decide: `dhp_bullet` keeps the type1/type2 damage mix-up the disassembly flags at `$1AF8`, and
`AddBullet`'s logical shift makes a bullet flying left one pixel a pass faster than its mirror
image. Both are invisible in play and removing them would be a silent divergence.

#### 12c — Playtesting and balance

The dials, all of them already isolated:

| | |
|---|---|
| `PLY_ITER_FRAMES` | `src/player.asm` — the CE speed dial, and the one that changes the game most |
| `DR_COL_W/H`, `BUL_COL_W/H` | the collision boxes, explicitly "meant to be tuned by eye" |
| `SPR_OVL_U/Y` | the tranche overlap test, deliberately loose |
| `drAgingMask` | the economy: how fast the droid you are riding wears out |
| the `random AND $1F` vs `shipLevel` draw | the difficulty curve |

Feedback goes into a session log — what deck, what was happening, what felt wrong — because
"feels wrong" is not actionable and "the 872s on deck 8 corner me because they fire before I can
see them" is.

#### 12d — Performance and graceful degradation

`docs/raster-timing.md` has the method. Two questions:

1. **Is the feel consistent?** `FRAME_LOCK` is a floor, not a fixed length: a pass that overruns
   carries on rather than waiting out another field, so a busy deck runs at a different rate from
   an empty one. Measure `vsyncCount` against the pass count across the worst decks and decide
   whether the variation is visible — and remember
   the standing rule that judder in an emulator is 60 Hz beat, not the code — measure, do not watch.
2. **Does an overrun degrade gracefully?** The known cliff is the level draw's 22,016-cycle window
   before the CRTC latch at fire 1; miss it and a newly exposed column is written while the beam is
   displaying it. The tranche split (`SprSplitOK`) is the existing relief valve and only fires when
   the level draw has nothing to do. What is *not* built is any behaviour for a pass that overruns
   anyway — it currently just runs long. Options to cost: dropping the rotor animation, thinning
   the sight-line budget further, skipping a tranche.

**Entry condition:** Layers 9, 10 and 11 done, so the pass measures the finished game and not a
subset of it. **Exit condition:** the fidelity table complete, the Redux list triaged, and a
build KC is happy to put in front of someone else.

### Layer 13 — Memory, banks and machine compatibility — **planned**

**Until this layer, RAM is not a constraint worth designing around.** KC's ruling, 2026-08-16:
where a layer needs room, take a **fourth sideways bank in slot 7** and move on. Squeezing a
feature into a hole that a later layer will rearrange anyway costs more design time than the RAM is
worth, and every such squeeze is a decision that has to be re-litigated when the next layer lands.
Layer 13 is where the accumulated cost is paid off in one pass, with the whole game in front of us.

Three strands:

#### 13a — The RAM pass

Every bank and every main-RAM hole re-audited with the finished game's real requirements, not the
requirements each layer guessed at while it was being built. The questions already known to be
waiting:

| | |
|---|---|
| how many banks are actually needed | four is the working assumption from this layer on; the target says three. Deciding is this pass's job, not each layer's |
| the bank-4/bank-6 split | Layer 9's panel, HUD and console are in bank 6 with a main-RAM bridge for four scalars and the droid tables, purely because bank 4 was 224 bytes short (`docs/layer-9-hud.md`, decision 8). If bank 4 gets 1.4 K back they all move home and the bridge goes |
| the font in main RAM | `&3C00` upward, because it must be readable from bank 4 and bank 6 alike (decision 1). Costs a 3 K hole that nothing else can use |
| `&2F03–&3000` and `&5400–&57FF` | the leftovers, and what wants them |

#### 13b — Sideways RAM detection at boot

There is **no detection at all today**: the build assumes banks 4, 5 and 6 are RAM and writes into
them regardless. On a machine where any of those is a ROM socket the game loads garbage and runs.
What this needs is the standard write/read-back probe over all 16 banks at boot, a table of which
are usable, and the bank assignments chosen from it rather than hard-coded — plus an honest message
and a stop when there are not enough.

#### 13c — Machine compatibility testing

The target is a Model B / B+ with sideways RAM, but the port has only ever been run on
jsbeeb's `B-DFS1.2` and b-em. This is the pass that runs it on the machines people actually have:
B with DFS 1.2 and 2.26, B+, Master 128 (whose shadow RAM and different `PAGE` are the obvious
hazards), and second-processor configurations, which the IRQ takeover and the CRTC rupture are
both likely to dislike. Each combination either works, or is documented as unsupported with the
reason.

**Entry condition:** Layer 12 done, so the game is finished and its memory needs are final.
**Exit condition:** a build that detects what it is running on, says so, and either runs correctly
or refuses honestly.

### Layer 14 — Visual pass — **the last pass, planned**

Asked for by KC, 2026-08-16. Everything is drawn by now and has been seen on real hardware; this is
the pass that settles how it **looks**, as one deliberate sitting rather than a decision taken
sixteen times in passing.

Two strands:

1. **The final palettes, for every deck and every game screen.** MODE 1 gives four logical colours
   at a time and the C64 gives sixteen with per-character colour, so a deck's palette here is a
   choice, not a transcription — and the choice has been made deck by deck as decks landed. This
   pass sets all sixteen decks together, plus the panel, the console, the transfer board and the
   title, so they read as one game and so no two adjacent decks land on the same scheme by
   accident. The original's own per-deck colours are the starting point, not the answer.
   **Include the deck plan page (KC, 2026-08-17)**: its per-deck inks are `planInk`, built by
   `tools/export_bbc.py` from the C64 chain plus two legibility overrides — re-judge that table
   and §6e decision 1 (the plan keeps the deck's palette) alongside the deck palettes themselves.
2. **Redrawing graphics characters that fight the palette.** Where a tile or a glyph only works
   because of a colour MODE 1 cannot give it, the honest fix is to change the artwork rather than
   spend a palette entry on it. That is a **deviation from the original's graphics and needs
   agreeing case by case** under the usual rule — each one written down with what it was and why
   the ported character did not survive the four-colour restriction.

**Why last:** judging a palette wants the finished screens and a real machine and a real display —
`13c` is what puts the build in front of one, and an emulator's colours are not the ones the game
will be played in. Some of this can be prototyped earlier (a palette is a poke), but nothing should
be *settled* before then.

**Exit condition:** every deck and screen has a palette recorded in the source with a comment
saying why, and every redrawn character has a decision entry.

## `src/` as it stands

Single-pass flat build, everything included from `main.asm`. No linker. **Four files assemble into
SWRAM bank 4 rather than main RAM** — they are included from inside the `PARADAT` block, and the rule
that makes that safe is in `bufcore.asm`'s header.

| File | Where | State |
|---|---|---|
| `main.asm` | main RAM | **Live.** Constants, the zero page map, memory map, main loop and its two windows, IRQ dispatch. Geometry constants live here because beebasm resolves them in file order and the other files need them |
| `rupture.asm` | main RAM | **Live.** Three-cycle vertical rupture, the T1 state machine, `FillPanel`, `DbgSetBg` |
| `bufcore.asm` | main RAM | **Live.** The four things the level draw could not take into the bank: `SetupMode`/`SetupRupture` and `SetCRTCStart`, which run before the bank is loaded, and `WrapBufFwd`, `SetCell` and the `rowMul`/`unitMul` tables, which run with the *sprite* bank paged in |
| `screen.asm` | **bank 4** | **Live.** `DrawHalf`, `HalfPtr`, `BuildCharPtrs`, `BandSetRow`/`BandCharPtr`, `ColSetup`, `MapChar`, `RedrawAll` |
| `scroll.asm` | **bank 4** | **Live.** `DrawColumn`, `DrawBandRows`, `CopyCell`, `ScrollAddS`, `DoRedraws` |
| `level.asm` | **bank 4** | **Live.** Deck decode, `BuildCharset`, `BuildLUTs`, `SetPalette` |
| `player.asm` | main RAM | **Live.** `ReadKeys`, `CalcSpeed`, `CheckWalls`, `ApplyMove`, `DeadZone`, the clamps |
| `combat.asm` | main RAM | **Live.** Layer 7a: the player's energy, ceiling, weapon, alert and BCD score, `CombatInit`, `AddScore`, `DoAging`. Main RAM because BOTH banks' code reaches it |
| `sprite.asm` | main RAM | **Live.** The blitter: slot state, the tranche walk behind `SprDrawAll`/`SprRestoreAll`, `SprSplitOK`/`SprAssignTr`, the compiled-row dispatch and the wrap fallback |
| `door.asm` | main RAM | **Live.** Door state, `DoorScan`, the patched tile definitions, `DoorsUpdate`, `DrawDoorTile` |
| `lift.asm` | main RAM | **Live.** `LiftFind`, lift mode, stepping a shaft, `LiftPlace` |
| `droid.asm` | **bank 4** | **Live.** The ship roster, the deck's droid table, waypoints, `DroidsUpdate`, `DrNewDir`, `DrLineOfSight`, `DrCollide`, the sprite-slot allocation. **Wants moving into bank 4** — see the memory item above |

**Everything in `src/` is in the build.** Five inherited files that were not — `zeropage.asm`,
`hardware.asm`, `macros.asm` and the retired `hal_video.asm` / `hal_irq.asm` — were deleted rather
than left to be mistaken for live code. They targeted a Master 128 in MODE 2 with shadow-RAM double
buffering and a hardware abstraction layer this project explicitly rejected, and `hal_video.asm` in
particular carried unverified CRTC arithmetic with `TODO: verify in emulator` still in it.

They are in git history if ever wanted (`git show <rev>:src/hardware.asm`). The only thing in them
with a future was `hardware.asm`'s SN76489 encoding, which is now recorded under Layer 11 above —
with the caveat that it was never verified either.
