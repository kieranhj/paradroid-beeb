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
| [`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md) | Doors (built) and lifts (planned), and the character-map problem they raise |
| [`docs/master-extensions.md`](docs/master-extensions.md) | Things only a Master 128 could host. Not on the critical path |

## Where we are — read this first

**Layers 0–6 and 8 are done.** The port boots to a playable deck: a
static panel above a 320 × 120 play area, the player droid near the centre with its rotor spinning,
and the deck hardware-scrolling 8 ways underneath it — 4 px horizontally, 1 scanline vertically —
driven by the C64's own acceleration model and stopped by walls. The camera has a dead zone, so at
low speed the world holds still and the droid glides at 1 px instead of the world lurching at 4.
Frame-locked at 25 Hz (2 fields a pass) in every direction including full diagonal. 16 decks,
per-deck palette and charset built at load time. Keys: Z/X left/right, K/M up/down (and, in a lift,
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

**Next: Layer 7**, combat — `dMd1_bullet`, `dMd2_explosion`, `DoCollision`'s damage arms, `DoScore`,
`KillDroid` and `DoAlertAndAging`.

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
| Panel shares the play palette | Its colours change with the deck. Fixable at the cycle boundary — we are already in the IRQ there. Layer 9 |
| `keydown` uses OSBYTE `&81` | The last OS call in the main loop |
| 8 decks draw ALERT in multicolour | Confirmed faithful to the C64 original, not a bug. Worth a look on real hardware |

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
| `&1100–&27D9` | 6,362 B | code (`PARA`). DFS random-access buffer space, safe for `*LOAD` |
| `&27DA–&2FFF` | **2,086 B free** | the level draw and the droid AI both live in bank 4 now |
| `&3000–&36FF` | 1,792 B | sprite background save areas, one page per slot |
| `&3800–&3BFF` | 1,024 B | tile map, fixed home — floating it after `code_end` once put it over the save areas |
| `&3700`, `&3C00–&47FF` | **3,328 B free** | runtime-built data only: boot stages `PARASPR` through `&68B5` |
| `&4800–&547F` | 3,200 B | panel — 5 rows × 640, displayed by rupture cycle 1 |
| `&5480–&54FF` | **128 B free** | |
| `&5500–&56FF` | 512 B | `CHAR_PTR_LO`/`HI` — character code → charset address, built at startup |
| `&5700–&57FF` | 256 B | data byte → transparency mask table, built at startup |
| `&5800–&7FFF` | 10,240 B | play buffer: circular strip, 16 rows × 640 |
| SWRAM bank 4 | 16 K | `PARADAT` — char data, colour schemes, tile defs, deck RLE, waypoints, **the level-draw code and the droid AI**. Ends `&B5C3`, **2,621 B free** |
| SWRAM bank 5 | 16 K | `PARASPR` — the blitter at shifts 0 and 1 px. Ends `&B056`, **4,010 B free** |
| SWRAM bank 6 | 16 K | `PARSPR2` — the same at 2 and 3 px, laid out identically. Ends `&B199`, **3,687 B free** |

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

### Layer 7 — Combat
`dMd1_bullet`, `dMd2_explosion`, `DoCollision`/`DoCollision2`, `DoScore`, `KillDroid`,
`DoAlertAndAging`. The core game is playable at this point.

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
written down anywhere in the listing. The side view is still Layer 9's; until then a lift has no
display of its own.

**Arrival now comes from the lift table where there is one**, and from **waypoint 0** everywhere
else — the first deck and the debug deck hop included. `CentreOnDeck` is gone, and `BUGS.md` #4,
"lands inside a wall on some decks", closed with it in Layer 5.
→ [`docs/layer-8-doors-lifts.md`](docs/layer-8-doors-lifts.md)

### Layer 9 — HUD and console
The mid-frame split already exists (Layer 3c/3d) and the panel is a placeholder bordered box at
`&4800`. This layer fills it with real content: `Console`, `con_DroidInfo`, `con_DeckInfo`,
`con_ShipInfo`, side view. Also the point to revisit the panel palette — it currently shares the
play area's four colours and so changes with the deck.

### Layer 10 — Transfer minigame
`SubGameSelectSide` and the circuit puzzle. Paged from a sideways bank.

### Layer 11 — Sound, title, polish
SN76489 driver replacing the SID engine, title screen, attract mode. The chip is written through
System VIA port A with handshake at `&FE41`; a latch byte is `1 cc r nnnn` and a data byte
`0 0 nnnnnn`, so a tone is `&80 | (chan << 5) | (freq AND &0F)` then `freq >> 4`, and an
attenuation is `&90 | (chan << 5) | (15 - vol)`. **That came out of the deleted `hardware.asm` and
was never verified on hardware** — check it against the wiki before building on it, per the rule
about recalled facts.

## `src/` as it stands

Single-pass flat build, everything included from `main.asm`. No linker. **Four files assemble into
SWRAM bank 4 rather than main RAM** — they are included from inside the `PARADAT` block, and the rule
that makes that safe is in `bufcore.asm`'s header.

| File | Where | State |
|---|---|---|
| `main.asm` | main RAM | **Live.** Constants, the zero page map, memory map, main loop and its two windows, IRQ dispatch. Geometry constants live here because beebasm resolves them in file order and the other files need them |
| `rupture.asm` | main RAM | **Live.** Three-cycle vertical rupture, the T1 state machine, `FillPanel`, `DbgSetBg` |
| `bufcore.asm` | main RAM | **Live.** The four things the level draw could not take into the bank: `SetupScreen` and `SetCRTCStart`, which run before the bank is loaded, and `WrapBufFwd`, `SetCell` and the `rowMul`/`unitMul` tables, which run with the *sprite* bank paged in |
| `screen.asm` | **bank 4** | **Live.** `DrawHalf`, `HalfPtr`, `BuildCharPtrs`, `BandSetRow`/`BandCharPtr`, `ColSetup`, `MapChar`, `RedrawAll` |
| `scroll.asm` | **bank 4** | **Live.** `DrawColumn`, `DrawBandRows`, `CopyCell`, `ScrollAddS`, `DoRedraws` |
| `level.asm` | **bank 4** | **Live.** Deck decode, `BuildCharset`, `BuildLUTs`, `SetPalette` |
| `player.asm` | main RAM | **Live.** `ReadKeys`, `CalcSpeed`, `CheckWalls`, `ApplyMove`, `DeadZone`, the clamps |
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
