# Paradroid → BBC Micro Model B: Port Plan

Living document. Revised as each layer lands.

**Completed layers keep their working notes in [`docs/`](docs/)** — the measurements, the dead ends
and the hardware facts that were bought the hard way. This file holds the state of the port, the
memory map outline, and one paragraph per layer saying what landed and where the detail is. If a
layer's detail has stopped being needed to make the next decision, it belongs in `docs/`.

| | |
|---|---|
| [`docs/memory-map.md`](docs/memory-map.md) | **The detailed map** — every region of main RAM and all four banks, from the label dump, with the boot staging overlay and what is actually free |
| [`docs/decisions.md`](docs/decisions.md) | Decisions taken, why MODE 1, and which Paradroid the listing actually is |
| [`docs/graphics.md`](docs/graphics.md) | Where the C64's graphics data lives and which tool reads it — plus, per section, what has been ported and what has not |
| [`docs/layer-0-toolchain.md`](docs/layer-0-toolchain.md) | Toolchain, and the first confirmed CRTC facts |
| [`docs/layer-1-graphics-pipeline.md`](docs/layer-1-graphics-pipeline.md) | The C64 → MODE 1 conversion, hires/multicolour, per-deck palettes |
| [`docs/layer-2-static-render.md`](docs/layer-2-static-render.md) | Tile map, deck decode, the `PARA`/`PARADAT` split |
| [`docs/layer-3-scroll.md`](docs/layer-3-scroll.md) | The circular strip, the three-cycle rupture, CRTC register timing |
| [`docs/layer-4-player.md`](docs/layer-4-player.md) | The player sprite, the speed model, the level draw rewrite |
| [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md) | Compiling the sprite blitter — 14,000 cycles to 5,800 |
| [`docs/raster-timing.md`](docs/raster-timing.md) | **Where the main loop sits against the beam** — the frame, what writes the buffer when, and the flicker/tearing work (steps 1 and 2 done) |
| [`docs/layer-5-droids.md`](docs/layer-5-droids.md) | Droid movement: the roster, waypoints, and the waypoint-0 spawn |
| [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md) | Line of sight, collision, and the mode dispatch |
| [`docs/layer-7-combat.md`](docs/layer-7-combat.md) | Combat, 7a–7f — bullets, explosions, damage, score, Alert, the recharge pads, and what is deliberately deferred |
| [`docs/bug-map-corruption.md`](docs/bug-map-corruption.md) | The BUGS.md #10 hunt — **cause found and fixed 2026-08-16** (a teleport broke `COPYCHAR`'s parity rule; `ReframeView` is the fix). Named for the wrong hypothesis; kept for `DEBUG_MAPGUARD` and the method |
| [`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md) | Doors and lifts, both built, and the character-map problem they raise |
| [`docs/layer-8b-lift-view.md`](docs/layer-8b-lift-view.md) | The lift deck-selection screen, on Layer 10's shadow machinery |
| [`docs/layer-9-hud.md`](docs/layer-9-hud.md) | **The status line and the console** — the $7000 font, the $C000 string table, and all four pages behind the menu icons |
| [`docs/layer-10-transfer.md`](docs/layer-10-transfer.md) | The transfer minigame — the shadow screen/colour RAM that keeps the C64 code verbatim, and the eleven numbered decisions |
| [`docs/layer-11-sound-title.md`](docs/layer-11-sound-title.md) | **Planned in full, 2026-08-18** — the title, the 001 screen, game over instead of a respawn, and back to the title. Six numbered decisions, the title's 25-row memory map, and the SN76489 encoding (still unverified) |
| [`docs/master-extensions.md`](docs/master-extensions.md) | Things only a Master 128 could host. Not on the critical path |

**Open defects live in [`BUGS.md`](BUGS.md)**, with the evidence and what has been ruled out.
Currently open: **#12** (live lasers corrupt the console text — filed, not investigated), **#9**
(the leftmost 4-px column lands one row low after horizontal scrolling), **#7b** (the player's
bounce reads as heavy — tuning), and **#1/#2/#3**, all three of which want retesting against fixes
that landed after they were filed. **#7a — droids locking together — was a defect and is fixed**
(2026-08-18): the droid-droid arm had dropped `ReverseDroidDir`'s own `byte_0_6C` guard, so an
overlapped droid reversed every pass instead of once.

## Where we are — read this first

**Layers 0–10 are done; 11–14 (sound and title, balance, memory and compatibility, the visual
pass) are planned below.** The port boots to a playable game: the C64's own status box above a
320 × 120 play area, the deck hardware-scrolling 8 ways under the player droid — 4 px horizontally,
1 scanline vertically — with the C64's acceleration model, a dead-zone camera, and a 25 Hz frame
lock (2 fields a pass, a floor not a fixed length). Sixteen decks, per-deck palette and charset
built at load, starting on a random deck 4–7 as `$12B6` does. The ship is traversable — doors,
lifts, and the C64's deck-selection screen — and populated: droids patrol their waypoints, keep
line of sight, collide, shoot back and can kill you; die riding a captured droid and you fall
back to a 001 where you stood, die as a 001 and the game is over. L fires,
and through the original's own `moveMode` machine it is also the lift, console and transfer
trigger. Walk onto a console and the play area becomes `ConsoleMain`'s screen, names and all,
with **all four menu pages** working; touch a droid at `moveMode` 0 and the transfer minigame
plays, all three outcomes landing on the droid tables. Keys: Z/X left/right, K/M up/down, L fire,
cursor up/down a debug deck hop, SPACE a forced full redraw.

The frame budget: the **eight sprite slots** (player, six droids, the player's bullet) cost
~36,000 cycles of the 79,872 in a pass and the droid AI another ~17,000, so the loop keeps
roughly a third spare. That is after the blitter was compiled — 14,000 cycles a sprite to 5,800,
[`docs/layer-5-blitter.md`](docs/layer-5-blitter.md), which also records what was costed and
*rejected* — and after the loop was rebuilt around the raster so every buffer write sits inside
one of the two 24,576-cycle blanked windows: [`docs/raster-timing.md`](docs/raster-timing.md).

**Before trusting any speed number, read the speed model section of
[`docs/layer-4-player.md`](docs/layer-4-player.md).** The C64's constants are per `GameLoop`
iteration and an iteration is 2–3 frames, not 1. Every droid speed in `PlayerSpeed_t` needs the
same conversion.

### Rules for anything drawing into the play buffer

(The byte-layout and cycle-cost facts are in `CLAUDE.md`'s hardware list; these are the port's own.)

1. **Display row *r* holds map row `mapYr + r`, all eight scanlines.** Unconditional — there is no
   split row any more, and nothing needs a repair pass.
2. **The draw window is frame rows 23 → 8 of the next frame**, released by `drawFlag` at `P+184`
   when the play area stops displaying. Everything shares it. `DEBUG_DRAW` tints it: magenta the
   sprites, yellow the level draw, cyan everything else.
3. **`mapYr` and `cellY` are SIGNED, and the row being drawn may be off the map** — the view
   scrolls up to `PLY_VOID` (64 px) past each vertical edge. One `AND #&C0` catches both ends, and
   `BandSetRow`, `DrawColumn` and `MapChar` all do it. Anything new that reads a map row must too,
   or it indexes off `mapRowLo`.

### Verification

The buffer-vs-`RedrawAll` oracle and the listing-stream check are both described in `CLAUDE.md`
("Verify against the buffer, not the screenshot"), and per-defect method notes are in `BUGS.md`.
Two porting-specific reminders: **enter a second deck before believing a droid result** (BUGS.md
#8 was invisible on deck 1 by construction), and quiesce the pool with `drCount = 1` or by NOPing
the draw call sites — zeroing `sprActive` alone is not enough (BUGS.md #9's note).

### Open items, in the order they are likely to bite

| | |
|---|---|
| **RAM: Layer 13a done, 2026-08-19** | main RAM **148 B** (was 30), bank 4 15 B, bank 5 1,033 B, bank 6 **1,609 B** (was 40), bank 7 **4,410 B** (was 282), plus 120 B at `&3D88`. **+6,085 bytes**, no cycle cost and no behaviour change. **11c's loop, 11d and 11e are all unblocked**, and bank 4's 15 B is the only tight region left. The font ships 1bpp — the C64's own bytes — with one `FontCell` decoder shared by both banks and sitting in the font file rather than the code image, and the string table exists once instead of twice. See [`docs/layer-13-ram-pass.md`](docs/layer-13-ram-pass.md) |
| Twelve title characters, four wash characters | `export_bbc.py` converts only what a tile references, so the title ships its own 36 glyphs and `EndGame`'s wash uses substitute patterns. Extending the shared charset is the better fix and needs KC — [DECISION 8] and [DECISION 7] |
| Console vs live lasers | **BUGS.md #12, open.** Lasers on screen when a console activates stay drawn over the console text. Likely a missing pool teardown on console entry — compare `ReframeView`'s |
| Edge column off-by-one | **BUGS.md #9, open.** After horizontal scrolling, CRTC unit 0 holds the right content one character row too low — ~60 bytes of 10240, nearly invisible on screen, fails the oracle. In the incremental column draw; sprites all ruled out |
| Collision box shape | **Agreed 2026-08-18, not built.** `DR_COL_W`/`DR_COL_H` become a generated minimum-`|dx|`-per-`|dy|` profile — the silhouette instead of a rectangle, at box-test cost, built from our own sprite masks by `tools/export_droids.py`. [DECISION 1] in [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md) |
| Droid collision feel | `BUGS.md` #7b — the player bounce reads as heavy. Tuning, by eye, once the box lands: `DrPause16`'s 16 and the `ASL A` in `DrBounce` |
| Droid worst case unmeasured | 8 slots (~36,000) + droids (17,000) + full-diagonal level draw (19,172) is ~72,000 of 79,872 before the rest of the loop. It never arose by chance; it wants a rig on a deck with a long open corridor. If it bites, `docs/raster-timing.md` Step 3 is the planned relief |
| Flicker and edge tearing | Steps 1 and 2 **done 2026-08-15**: the AI moved after the drawing, and the pool splits into two tranches assigned by overlap component, each restored and drawn inside one window. What remains is the worst-case measurement above. [`docs/raster-timing.md`](docs/raster-timing.md) |
| 2 px world scrolling | Parked, Master-only via shadow RAM. Costs +60–80% on all drawing — see [`docs/master-extensions.md`](docs/master-extensions.md) |
| Play area is 320 × 120, not 128 | Consequence of the single hardware wrap — see Layer 3d. Getting the row back needs the 20K wrap or per-cycle wrap bits. **KC's call** |
| Vertical granularity | 1 scanline against 4 px horizontal is lopsided. 2 or 4 scanlines costs nothing extra. There are droids to move now, so this is decidable |
| ~~`$D021` is an assumption~~ | **Solved 2026-08-17.** It is **slot 0 of the deck's colour record**, per deck — `InitColors` leaves it in A and `Irq_118` writes it to `$D021` for the play area. Only decks 2 and 7 are the light blue the port assumed for all sixteen; the rest are greys, light red, yellow, light green and cyan. Emitted as `.deckBg`, confirmed against `ref/c64_deck0.png`. See [`docs/layer-1-graphics-pipeline.md`](docs/layer-1-graphics-pipeline.md) |
| **ALERT lamp is dead** | `BUGS.md` #13 — character `$16`, the lamp in the ALERT sign, is coloured by **alert level** on the C64 (green/yellow/orange/red, `AlertColors` at `$6D45`) and is always black here |
| `keydown` uses OSBYTE `&81` | The last OS call in the main loop |
| 8 decks draw ALERT in multicolour | Confirmed faithful to the C64 original, not a bug. Worth a look on real hardware |
| Transfer: no droid info screens | The C64 shows two full-screen robot data pages (`ShowXferInfo`, `$3734`) before the board. Not ported; the game goes straight to side select. Wants doing alongside Layer 11's presentation work, where the token-string machinery gets its second user |
| Transfer presentation differs for screen room | Status text on the panel line rather than above the board, numbers standing in for the side-select sprites. Decisions 6–8 in [`docs/layer-10-transfer.md`](docs/layer-10-transfer.md) |

## Decisions taken

Full reasoning, and the measurement that settled which Paradroid the listing is, in
[`docs/decisions.md`](docs/decisions.md).

| Decision | Choice | Date |
|---|---|---|
| Target machine | BBC Model B / B+ with **2 × 16K sideways RAM banks** | 2026-08-04 |
| Target machine, revised | **3 × 16K sideways RAM banks** — a compiled shift is ~5.5 K and 1 px positioning needs four of them. See [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md) | 2026-08-14 |
| Screen mode | MODE 1, 4 colours, **10K wrap at `&5800–&7FFF`** | 2026-08-04 |
| Screen layout | 3-cycle vertical rupture: static panel, gap, scrolled play area | 2026-08-05 |
| Play area | **320 × 120** — 10 tiles wide, 15 character rows. See Layer 3d for why not 128 | 2026-08-05 |
| Scrolling | CRTC hardware scroll over a circular strip. **4 px horizontal, 1 scanline vertical** | 2026-08-05 |
| Interrupts | We own IRQ1V outright, System VIA T1 continuous. No MOS chaining, no MOS sound | 2026-08-04 |
| Architecture | No HAL. Build one working layer at a time, verified in the emulator before moving on | 2026-08-04 |
| Source version | **1985 original / 1986 Competition Edition** lineage — which is what `paradroid_ce.lst` already is. Redux's bug list adopted as a spec, not as code. Heavy Metal parked as a possible later tile set | 2026-08-06 |
| Game loop rate | **Locked to 2 fields a pass**, not free-running — a full sprite pool does not fit in a field, and free-running made the player 20 % slower whenever droids were visible | 2026-08-13 |
| Sprite blitter | **Compiled**, not interpreted: generated 6502 per rotor row and per digit glyph, in a sideways bank of its own | 2026-08-13 |
| Player top speed | **8 px a pass, not the C64's 7** (`CAM_TOPSPD`, `main.asm`) — the only movement number not taken from the original. 7 cannot divide the CRTC's 4 px step, so the camera dithers and the scroll stutters; 8 is uniform. 14 % fast, bought deliberately. `PLY_ITER_FRAMES = 3` + `CAM_TOPSPD = 7` is the exact-1985 alternative and lost on feel | 2026-08-14 |
| Panel is 4 rows, not 5 | The C64's status box is 32 scanlines, not 64 — `PANEL_ROWS` 5 → 4 at `&4A00`, costing only R6's write. See [`docs/layer-9-hud.md`](docs/layer-9-hud.md) §2a | 2026-08-16 |
| Target machine, revised again | **4 × 16K sideways RAM banks** — bank 7 (`PARXFER`) holds Layer 10's transfer game. Banks 4–7 is the Master's own sideways RAM numbering | 2026-08-16 |
| Transfer board shows all 16 rows | The play area always *displays* 16 rows; only fire 3's R8 blank hides the smooth scroll's spare one. The rupture's fire-2→3 interval became a variable (`t1i3`) so the transfer can move the bottom edge down a row | 2026-08-16 |

## Memory budget

**[`docs/memory-map.md`](docs/memory-map.md) is the map** — every region, from a label dump of the
build rather than from a plan. Read it there and regenerate it when a region moves. The outline
(figures from the 2026-08-17 build):

| Region | Size | Contents |
|---|---|---|
| ZP `&00–&8F` | 144 B | **all of it used** — the map is in `main.asm`. `&90` up is the OS |
| `&0400–&0C8F` | 2,192 B | MODE 1 charset, built at deck load — reclaimed OS workspace |
| `&0C90–&10FF` | **1,136 B free** | rest of the reclaimed OS workspace |
| `&1100–&2F6C` | 7,789 B | code (`PARA`), starting below DFS's `PAGE`. DFS random-access buffer space, safe for `*LOAD` |
| `&2F6D–&2FFF` | **148 B free** | **the binding constraint**, and where Layer 11e's sound driver has to go — the IRQ reads no sideways bank. It was 24, then 30; Layer 13a's TASK 6 and TASK 8 took it here |
| `&3000–&366F` | 1,648 B | **the text font**, `PARAFNT` — 103 glyphs at **1bpp, the C64's own bytes**, expanded by `FontCell` as it draws. Layer 13a TASK 3 |
| `&3670–&36CF` | 96 B | the status box's twelve border cells, same file, also 1bpp |
| `&36D0–&3CD5` | 1,542 B | `constrings` — the `$C000` name table, **one copy**, read by the console in bank 6 and the droid database in bank 7 alike. TASK 7 |
| `&3CD6–&3D27` | 82 B | `FontCell` and its expansion table — main RAM because both banks call it, but not the code image. TASK 8 |
| `&3D28–&3D87` | 96 B | the four droid tables, mirrored out of bank 4 for the panel in bank 6 |
| `&3D88–&3DFF` | **120 B free** | what is left of the room the 1bpp font freed |
| `&3E00–&45FF` | 2,048 B | sprite background save areas, one page per slot — **eight**, ending exactly where the tile map begins. Also the transfer and lift screens' shadow buffers, which never coexist with them (TASK 1) |
| `&4600–&49FF` | 1,024 B | tile map, fixed home — floating it after `code_end` once put it over the save areas. Ends exactly at the panel, **0 B free** |
| `&4A00–&53FF` | 2,560 B | panel — **4 rows** × 640, the C64's status box exactly, displayed by rupture cycle 1 |
| `&5400–&54BF` | 192 B | `rowMul`/`unitMul`, the row and unit offset tables, built at startup. TASK 6 |
| `&54C0–&54FF` | **64 B free** | |
| `&5500–&56FF` | 512 B | `CHAR_PTR_LO`/`HI` — character code → charset address, built at startup |
| `&5700–&57FF` | 256 B | data byte → transparency mask table, built at startup |
| `&5800–&7FFF` | 10,240 B | play buffer: circular strip, 16 rows × 640 |
| SWRAM bank 4 | 16 K | `PARADAT` — char data, colour schemes, tile defs, deck RLE, waypoints, the combat stat tables, **the level-draw code, the droid AI, Layer 7's combat, Layers 10 and 8b's entry/exit shims, the console menu and page shims, and `CalcAxis`/`CalcSpeed`**. **15 B free — the only tight region left** |
| SWRAM bank 5 | 16 K | `PARASPR` — the blitter at shifts 0 and 1 px, **plus Layer 7's effect artwork**: 31 bullet and explosion frames, 2,946 B, here because the interpreted path reads them every row. **1,033 B free** |
| SWRAM bank 6 | 16 K | `PARSPR2` — the same at 2 and 3 px, laid out identically, **plus Layer 9's panel engine, HUD, console and icons**. **1,609 B free** |
| SWRAM bank 7 | 16 K | `PARXFER` — **Layer 10's transfer game and Layer 8b's lift screen**, sharing the glyph page and the renderer; plus the console's ship page, **the deck plan** (`condeck.asm`, `plandata.asm`), **the droid database** (`condb.asm`, `droidinfo.asm`) and Layer 11's title and game over. **4,410 B free** |

> Figures from the **2026-08-19** build, after Layer 13a. The pass freed **6,085 bytes** with no
> cycle cost and no behaviour change; [`docs/layer-13-ram-pass.md`](docs/layer-13-ram-pass.md) has
> the task-by-task account and the analysis of why 96 K held less game than the C64's 64 K.

**"Main RAM is full" meant the `PARA` image could not grow past `&3000`** — never that there was no
RAM. Moving code rather than data is what fixed it: `screen.asm`, `scroll.asm`, `level.asm` and
`droid.asm` live in bank 4 next to the tile and deck data they read, which costs no paging because
that bank is the resting state. `src/bufcore.asm` holds the 480 bytes that could not go — the
routines that run before the bank is loaded, or with the *sprite* bank paged in.

Only one bank is visible at a time. That works because the two halves are never wanted at once —
`DoRedraws` reads tiles, the blitter reads none of them — so `SprRestoreAll` and `SprDrawAll` page
their own bank in and the data bank back out around themselves. **The IRQ reads neither**, which is
what makes it safe; check that again before putting anything else in a bank.

All four bank files are staged through `&3000` by `*LOAD` and copied up, because the MOS has the
DFS ROM paged in at `&8000` during a filing-system call. The staging area overruns the panel and
the bottom of the play buffer, which is safe only because `PageBankIn` runs before either is next
read. Boot shows a moment of garbage in the play area.

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
split row ceasing to exist on the way.
→ [`docs/layer-4-player.md`](docs/layer-4-player.md)

### Layer 5 — Droid movement and the compiled blitter ✅ DONE
`src/droid.asm`: the ship's droid roster generated by `NextLevel`'s own rule, each deck's droids
standing on its waypoints, and `GetNewDir`/`AdvanceMapPos`/`CheckDroidAdvance` walking them between
junctions. Sprite slots are allocated and freed by `DroidNear`'s test, matched exactly to the
blitter's cull. **The player spawns on waypoint 0** (0 of the ship's 239 waypoints is in a wall,
checked offline), which retired `CentreOnDeck` and closed `BUGS.md` #4. `DroidsUpdate` costs
**15,576 cycles a pass with 11 droids**, in line with the C64's ~14,000 in `RunDroids`.
→ [`docs/layer-5-droids.md`](docs/layer-5-droids.md)

Seven slots at the Layer 4 cost did not fit in a frame, so the blitter was **compiled** — generated
6502 per rotor row and per digit glyph, in a bank of its own — taking a sprite from **13,998 cycles
to 5,814**, with 1 px positioning from four compiled shifts across two banks. Read that document
before optimising anything here: it records what was costed and rejected as well as what landed.
→ [`docs/layer-5-blitter.md`](docs/layer-5-blitter.md)

### Layer 6 — Droids live ✅ DONE
Line of sight (`LineOfVisibility`, walked without a division and taken one droid a pass), collision
(`DoCollision`/`DoCollision2`'s movement half), and the `DroidModeJump` dispatch. A droid behind a
wall keeps its sprite slot and is not drawn, which needed slot **ownership** separated from
`sprActive`. Collision is the one place with no faithful port available — the C64 reads the VIC's
pixel-exact `$D01E`, so ours is a box test, deliberately smaller than the sprite. Costs ~1,400
cycles a pass, and the frame lock holds in every case measured.
→ [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md)

### Layer 7 — Combat ✅ DONE (7a–7f, 2026-08-15/16)
`src/combat.asm` and the bank-4 kill chain. The player joined the droid table as **entry 0** (the
C64's layout — it was never a sentinel), with energy, aging on the C64's own schedule, BCD score,
and the recharge pads (+1 energy every 4th iteration, −5 score). Effect sprites are a second class
sharing the slot machinery — 31 bullet/explosion frames in bank 5, drawn by a generic interpreted
path, `SPR_SLOTS` 7 → 8 for the player's bullet — so **the sprite count per pass does not grow**.
L fires through `DoMoveMode`'s Mobile/Weapon/Transfer machine; bullets are world-coordinate, fly at
the original's 12 px a pass and die on walls; droids shoot back and can kill you, at which point
you explode where you fell and respawn as a 001 on waypoint 0 through `ReframeView` — **any
teleport must go through it** (BUGS.md #10). Still deferred: the disruptor, friendly fire, and the
bullet's colour flicker. Stage-by-stage record, measurements and decisions:
→ [`docs/layer-7-combat.md`](docs/layer-7-combat.md)

### Layer 8 — Doors, lifts, decks ✅ DONE — taken ahead of 6 and 7
Taken early because droid AI routes *through doors* — there was no way to evaluate it while the
player was sealed into one room. **Doors** (`src/door.asm`): a door is bit 7 of the character code,
and each open door gets a patched private copy of its 16-byte tile definition — free, because the
draw already selects a definition per tile. **Lifts** (`src/lift.asm`): stand on a platform, L,
then K/M step through the decks the shaft serves via the C64's lift table. **The deck-selection
screen** (`src/liftview.asm`, bank 7, 2026-08-17) shows the C64's ship cross-section on Layer 10's
shadow machinery, with ONE deck load on commit. Arrival comes from the lift table where there is
one and waypoint 0 everywhere else; `CentreOnDeck` is gone.
→ [`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md),
[`docs/layer-8b-lift-view.md`](docs/layer-8b-lift-view.md)

### Layer 9 — HUD and console ✅ DONE (console complete 2026-08-17)
The C64's status area is four `DrawString` calls and **32 scanlines**, so the panel is 4 rows with
a palette of its own; the `$7000` text font is **8 × 16** (two stacked MODE 1 cells, shipped as the
disc file `PARAFNT` with the logo and border cells). **The status line is the C64's and nothing
else** (KC, 2026-08-16): the rounded box, the logo, the mode word, and the score with `DoScore`'s
leading-zero blanking — the port's earlier synthesised readouts are gone. **The console screen is
`ConsoleMain`'s, line for line**, names out of the `$C000` string table, taking over the play area;
all four menu pages work — back to the game, the **droid database** (browser, stat pages, word-wrapped
description with `More...`), the **deck plan** (hires, drawn from bank 7's raw bitmaps), and the
static **ship plan**. The engine is in bank 6 (full), the menu in bank 4, the pages in bank 7.
Still missing: the C64's 48 × 84 **droid portrait** (~6 K of unported artwork — deferred by KC
2026-08-17, §6f decision 2) and the low-energy sprite flash. Every decision is numbered in
→ [`docs/layer-9-hud.md`](docs/layer-9-hud.md)

### Layer 10 — Transfer minigame ✅ BUILT (2026-08-17)
The whole subgame plays, entered the original's way — touching a droid at `moveMode` 0 — and all
three outcomes land on the droid tables: take the target over, fall back to a 001 with the bump
fine, or burn out as one. The target is consumed in every outcome. Verified end to end in jsbeeb.
The shadow screen/colour RAM that keeps `xfer_DoColumn` (`$1EB6`) and the rest verbatim, the fourth
SWRAM bank, the 16th row, the palette and the eleven numbered decisions are in
[`docs/layer-10-transfer.md`](docs/layer-10-transfer.md). Still wanted from play-testing:
difficulty feel against the C64, and consuming the last droid on a deck. Known gaps are in the
open items above: `ShowXferInfo`'s two droid info screens, and the presentation moved for screen room.

### Layer 11 — Title, the 001 screen, game over, sound — 11a, 11b and the title BUILT 2026-08-18
The original's own flow: `TitleLoop` → `StartGame` → the game → `EndGame` → `TitleLoop`. Three
findings shaped it. **Death is only a game over when you are already a 001** — `$144D` is the whole
test, and the other branch is `BlowInto001`, which `CbCheckDeath` already is. **`BlowInto001` does
not move the player**, so the port's waypoint-0 respawn is dropped, taking BUGS.md #10's cause with
it. And **`NewShipInfo` (`$36B9`) *is* the 001 screen** — it draws the play-area rows only, the shape
Layer 10's shadow screen already has, as do `EndGame` and `ShowXferInfo`.

Only the title needs a display of its own: 25 rows × 640 = 16,000 contiguous bytes, which fit
because the title's buffers and the game's never coexist. `PARAFNT` moved permanently to `&3000`,
the sprite save areas to `&3E00` and the tile map to `&4600` — the three pack exactly onto
`PANEL_ADDR` and the framebuffer takes `&4000`-`&7E7F` with the font below it.

**Built:** 11a, the boot split — `GameStart` in bank 4 is the C64's `StartGame` + `_entership`, and
boot keeps only the cold half. 11b, the game over — the `$144D` branch, the explosion cloud with the
ship frozen, `EndGame`'s wash and "game over" on the panel line. And **the title screen**, matching
the C64 cell for cell, with fire or a timeout into the game — which is also where `drSeed` finally
gets its entropy, so the starting deck is no longer the same on every cold boot.

**Not built:** the loop back to the title after a game over (**blocked on main RAM** — it needs an
IRQ teardown and ~39 bytes against 30 free), the 001 screen, and sound. Deferred with KC's
agreement: the 48 × 84 portrait (24 K in MODE 1 — the console's rotor-and-digits droid stands in),
the 5-page intro manual, and `DoHighScore`. Nine numbered decisions, the RAM position and what
unblocks the rest in [`docs/layer-11-sound-title.md`](docs/layer-11-sound-title.md).

### Layer 12 — Balance, fidelity and feel — planned

Not a feature layer. Everything is built by now; this is the pass that decides whether it plays
like Paradroid. Four strands, and the order matters — verify before tuning, or a fidelity bug gets
"balanced" around instead of fixed.

#### 12a — Fidelity audit against the C64

**Every gameplay routine walked against `paradroid_ce.lst`, one at a time, and each one either
confirmed identical or the departure written down with its reason.** Layer 7 twice shipped a
constant read out of the listing without following where its input came from (`AddBullet`'s
normalised direction, BUGS.md #11; the collision debounce applied to three arms instead of one).
Those are not the kind of thing playtesting finds; they need the listing open beside the source.

The output is a table, one row per routine: C64 address, our label, **identical / deviates /
not ported**, and for a deviation the reason. Candidates already known to deviate, so the audit
starts with them:

| | |
|---|---|
| collision | the VIC's register is pixel-exact and free; ours is a box test tuned by eye. **No faithful port exists** |
| the sight line | the C64 tests every near droid every iteration; ours tests one a pass (`losTurn`). A droid that steps behind a wall stays drawn up to five passes longer |
| speed | `PLY_ITER_FRAMES` and the CE's faster loop, written up in `docs/layer-4-player.md` — confirm the movement constants still transfer byte for byte |
| the death respawn | the C64 does not move the player; ours teleports to waypoint 0 and re-frames |
| the death explosion | the C64 draws the player's droid *under* the explosion; ours replaces it |
| culling | sprites are culled, not clipped, so a droid pops in and out a sprite's width from the edge. The C64's hardware clips |

#### 12b — The Redux fix list

**Paradroid Redux is a different codebase** — `docs/decisions.md` has the evidence — so its fixes
cannot be lifted as code. What it is good for is a **list of what Braybrook himself thought was
wrong**, each one then a question to ask of our own port: does the same defect exist here, and do
we want it fixed or preserved? Two of the original's own bugs are already ported deliberately as
the precedent: `dhp_bullet`'s type1/type2 damage mix-up, and `AddBullet`'s logical shift making a
leftward bullet one pixel a pass faster. Both invisible in play; removing them would be a silent
divergence.

#### 12c — Playtesting and balance

The dials, all already isolated:

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

1. **Is the feel consistent?** `FRAME_LOCK` is a floor: a pass that overruns carries on, so a busy
   deck runs at a different rate from an empty one. Measure `vsyncCount` against the pass count
   across the worst decks — and remember the standing rule that judder in an emulator is 60 Hz
   beat, not the code. Measure, do not watch.
2. **Does an overrun degrade gracefully?** The known cliff is the level draw's 22,016-cycle window
   before the CRTC latch at fire 1. The tranche split is the existing relief valve; nothing is
   built for a pass that overruns anyway — it currently just runs long. Options to cost: dropping
   the rotor animation, thinning the sight-line budget, skipping a tranche.

**Entry condition:** Layer 11 done, so the pass measures the finished game.
**Exit condition:** the fidelity table complete, the Redux list triaged, and a build KC is happy to
put in front of someone else.

### Layer 13 — Memory, banks and machine compatibility — 13a DONE 2026-08-19

**Until this layer, RAM is not a constraint worth designing around.** KC's ruling, 2026-08-16:
where a layer needs room, take a fourth sideways bank and move on. Layer 13 is where the
accumulated cost is paid off in one pass, with the whole game in front of us. Three strands:

#### 13a — The RAM pass — **DONE 2026-08-19**, [`docs/layer-13-ram-pass.md`](docs/layer-13-ram-pass.md)

Taken early rather than after Layer 12, because Layer 11 had filled main RAM to 30 bytes and bank 6
to 40 and the rest of Layer 11 could not be built until it was. **+6,085 bytes**, in seven changes
that each cost no cycles and changed no behaviour:

| | |
|---|---|
| the transfer's 2 K shadow screen | onto the sprite save areas, which are dead whenever it is up |
| the lift's second glyph set | 592 bytes to change three glyphs; only those three ship now |
| the row/unit offset tables | 192 bytes of pure arithmetic out of the code image, built at startup |
| the text font | **1bpp — the C64's own bytes**, halving `PARAFNT`, with one shared `FontCell` decoder replacing four copies of the same loop |
| the string table | existed twice, once per bank; now once, in main RAM where both can reach it |
| `FontCell` itself | out of the code image into the font file — main RAM either way |

It also found and fixed a real defect: `PnClear` cleared a whole extra page past the panel, because
`LO(PANEL_BYTES)` is zero and its tail loop compared `CPY #0` against a Y that was already zero.

**The questions this pass was going to ask have answered themselves.** Four banks are the working
assumption and stay; the bank-4/bank-6 split no longer needs undoing, because bank 6 has 1,609 bytes
rather than 40; and the 3 K font hole is now 1,648 bytes of font plus the string table that used to
be duplicated. What is left of the original list:

| | |
|---|---|
| how many banks | **four, settled.** The four hold ~57 K of the 64 K they offer and 7 K is free across them; three banks are 48 K and cannot take it. The original two-bank target went when the blitter was compiled |
| bank 4's 15 bytes | the only tight region left. It holds the tile, deck and waypoint data with the level draw and droid AI beside it, all finished — but anything new there still needs something moved first |
| `&0C90–&10FF` | 1,136 bytes still free and still unclaimed. It is below DFS's workspace at `&0E00`, so it takes runtime-built data, not anything loaded with the code |
| what was costed and declined | sharing the two-cell glyph wrapper (~200 B), de-duplicating the console droid icon (110 B), and interpreting the compiled digit glyphs (~5.9 K, and it costs cycles). All three are written up in the layer notes with their numbers |

#### 13b — Sideways RAM detection at boot

There is **no detection at all today**: the build assumes banks 4–7 are RAM and writes into them
regardless. Needed: the standard write/read-back probe over all 16 banks at boot, bank assignments
chosen from the result rather than hard-coded, and an honest message and a stop when there are not
enough.

#### 13c — Machine compatibility testing

The port has only ever run on jsbeeb's `B-DFS1.2` and b-em. This pass runs it on the machines
people actually have: B with DFS 1.2 and 2.26, B+, Master 128 (shadow RAM and a different `PAGE`),
and second processors, which the IRQ takeover and the rupture are both likely to dislike. Each
combination either works, or is documented as unsupported with the reason.

**Entry condition:** Layer 12 done, so memory needs are final. **Exit condition:** a build that
detects what it is running on, says so, and either runs correctly or refuses honestly.

### Layer 14 — Visual pass — the last pass, planned

Asked for by KC, 2026-08-16. Everything is drawn by now and has been seen on real hardware; this is
the pass that settles how it **looks**, as one deliberate sitting. Two strands:

1. **The final palettes, for every deck and every game screen.** MODE 1 gives four colours against
   the C64's sixteen, so a deck's palette here is a choice, not a transcription. This pass sets all
   sixteen decks together, plus the panel, the console, the transfer board and the title, so they
   read as one game. The original's own per-deck colours are the starting point, not the answer.
   **Include the deck plan page (KC, 2026-08-17)**: re-judge `planInk` (built by `export_bbc.py`
   with two legibility overrides) and layer-9 §6e decision 1 alongside the deck palettes.

   **The four logical colours now carry fixed roles** (KC, 2026-08-17): 0 = the deck's background,
   1 = black, 2 = the deck's highlight, 3 = white. Chosen for the sprites — logical 3 is `%11`, so
   a sprite byte is its own mask and `AND &0F` / `AND &F0` recolour it to black or the highlight
   in place. Allocation runs in priority order 3, 1, 0, 2, which puts white on all 16 decks and
   black on all 16. Anything drawing on the deck's palette must follow the roles; the console
   already had to be moved. See [`docs/layer-1-graphics-pipeline.md`](docs/layer-1-graphics-pipeline.md).

   **The tool for it is `tools/palette_lab.py`** (2026-08-17): every deck rendered in the C64's own
   colours beside the port's MODE 1 render, with both the palette and the colour *merge* editable
   live, and a 320 × 120 window showing what actually fits on screen. It writes
   `tools/deck_palettes.json`, which `export_bbc.py` reads as an override when it regenerates
   `colours.asm` — so a decision made by eye lands in the build without hand-editing generated
   data. Verified: its BBC render is byte-identical to `convert_charset` (what `BuildCharset`
   reproduces) over all 2,192 characters of all 16 decks.
2. **Redrawing graphics characters that fight the palette.** Where a tile or glyph only works
   because of a colour MODE 1 cannot give it, the honest fix is to change the artwork — a
   **deviation from the original's graphics, agreed case by case** under the usual rule.

**Why last:** judging a palette wants the finished screens and a real display — 13c is what puts
the build in front of one. **Exit condition:** every deck and screen has a palette recorded in the
source with a comment saying why, and every redrawn character has a decision entry.

## `src/` as it stands

Single-pass flat build, everything included from `main.asm`. No linker. **Everything in `src/` is
in the build** — the five inherited HAL-era files that were not have been deleted (see
`docs/decisions.md`). Files assemble into main RAM or into a bank, as marked; the one-way rule
that makes the bank-4 files safe is in `bufcore.asm`'s header.

| File | Where | Contents |
|---|---|---|
| `main.asm` | main RAM | Constants, the zero page map, memory map, main loop and its two windows, IRQ dispatch. Geometry constants live here because beebasm resolves them in file order |
| `rupture.asm` | main RAM | Three-cycle vertical rupture, the T1 state machine, `FillPanel`, `DbgSetBg` |
| `bufcore.asm` | main RAM | What the level draw could not take into the bank: `SetupMode`/`SetupRupture`, `SetCRTCStart`, `WrapBufFwd`, `SetCell`, the `rowMul`/`unitMul` tables |
| `player.asm` | main RAM | `ReadKeys`, `CheckWalls`, `ApplyMove`, `DeadZone`, the clamps |
| `combat.asm` | main RAM | Layer 7a: energy, ceiling, weapon, alert, BCD score, `DoAging`. Main RAM because BOTH banks' code reaches it |
| `sprite.asm` | main RAM | The blitter front end: slot state, the tranche walk, `SprSplitOK`/`SprAssignTr`, the compiled-row dispatch and the wrap fallback |
| `door.asm` | main RAM | Door state, `DoorScan`, the patched tile definitions, `DoorsUpdate`, `DrawDoorTile` |
| `lift.asm` | main RAM | `LiftFind`, lift mode, stepping a shaft, `LiftPlace` |
| `screen.asm` | bank 4 | `DrawHalf`, `BuildCharPtrs`, `BandSetRow`, `ColSetup`, `MapChar`, `RedrawAll` |
| `scroll.asm` | bank 4 | `DrawColumn`, `DrawBandRows`, `CopyCell`, `ScrollAddS`, `DoRedraws` |
| `level.asm` | bank 4 | Deck decode, `BuildCharset`, `BuildLUTs`, `SetPalette` |
| `droid.asm` | bank 4 | The ship roster, waypoints, `DroidsUpdate`, line of sight, collision, the kill chain, `ConMenu4` |
| `panel.asm` | bank 6 | Layer 9's panel text engine and HUD |
| `console.asm` | bank 6 | The console screen, its strings and icons |
| `xfer.asm` | bank 7 | Layer 10's transfer minigame |
| `liftview.asm` | bank 7 | Layer 8b's deck-selection screen |
| `condeck.asm` | bank 7 | The console's deck plan page |
| `condb.asm` | bank 7 | The console's droid database page |

`src/data/` is generated by the exporters in `tools/` and is gitignored — regenerate it rather
than editing it.
