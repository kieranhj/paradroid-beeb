# Layer 4 — Player droid: sprite, controls, collision ✅ DONE

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

Merged with the player half of Layer 5, because the point of the layer is the *feel* of moving the
player and the sprite alone does not demonstrate that. What landed: the 24×21 player sprite with its
8 rotor phases, the C64 speed model, pixel-granular 8-way scrolling, and wall collision.

The frame budget at full diagonal speed was the last thing outstanding and is **closed** — see the
end of this layer for the measurement. The one judgement still open is whether the dead-zone
camera's feel is right; KC has it "to sleep on".

## The player sprite is constructed, not stored

There is no player sprite in the C64 data. The dynamic sprite area `$5200-$53FF` ships **zeroed**
and every droid's sprite is built into it at runtime:

| routine | writes |
|---|---|
| `BuildDroidSprite` (`$3C77`) | the three-digit droid number into sprite rows 6-13 |
| `AnimateDroids` (`$3CFB`) | the spinning rotor into rows 0-4 and 15-19, from `RotAnim_*` |

Rows 5, 14 and 20 are never written, so they stay transparent. That is the entire sprite: a rotor
above and below, the number in the middle. `tools/export_droids.py` replays both routines offline
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

## 4a — Dead-zone camera, and 2 px sprite positioning

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
> feasibility — see [Master-only extensions](master-extensions.md).

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
`PlyBuildTables` into `&5480`. 1 px needs four copies, 1820 bytes, which does not fit below
`&3000` until `PARADAT` moves to sideways RAM.

> **This is thrift and nothing else — corrected 2026-08-14.** The paragraph above used to add that
> "a C64 multicolour pixel is exactly two MODE 1 pixels, so the artwork holds no finer detail".
> That is true of the deck, which mixes hires and multicolour cells, and false of the thing it was
> written beside. **Droid sprites are hires**: `dMd0_droid` clears `SpriteMC` at `$190C` and
> `SpriteXExp` at `$190E`, so a droid is 24 unexpanded pixels at the C64's full 320 across — one
> C64 pixel to one MODE 1 pixel. The original also *positions* them per pixel: `DroidNear`
> (`$321E`) computes `dPosX - ScreenPosX` in 16-bit pixels and `SetSpriteXY` (`$327E`) writes it
> straight to the VIC's sprite X, whose units are single hires pixels. Its background scroll is 1 px
> too, via `hScroll` into `$D016` in `Irq_91`.
>
> So 2 px is a real fidelity loss, not a free one: the drawn position is `floor(x/2)*2`, up to 1 px
> behind the truth, and a droid at `DSpeed_t` = 1 — one pixel an iteration — is drawn moving 0, 2,
> 0, 2. Right average speed, wrong texture, and it is the slow droids of Layer 6 that will show it.
> The port's own model is already 1 px; only the blit is not. See the cost note under Layer 5.

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

## The player does not move on screen; the deck does — mostly

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

## Scrolling is now a pixel position, not a step

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

## The speed model — and why the listing's numbers are not the ones to use

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

The conversion scales by *fields we get per pass ÷ fields the C64 spends per iteration*, i.e.
`FRAME_LOCK / PLY_ITER_FRAMES` — velocity once, acceleration twice (`src/player.asm:85-88`).
The loop is now locked to `FRAME_LOCK = 2`, so with `PLY_ITER_FRAMES = 2` the factor is 1 and
**the constants are the C64's own numbers, unmodified**:

| | C64, per iteration | here, per pass (2 fields, 25 Hz) |
|---|---|---|
| acceleration | 208/256 px/it² (`Acceleration_`, `$6955`) | 208/256 (`PLY_ACCEL`) |
| deceleration | 176/256 px/it² (`DecelerationNeg_`, `$6954`) | 176/256 (`PLY_DECEL`) |
| top speed | 7 px/it (`PlayerSpeed_t[DSpeed_t[0]]`) | **8 px** — `CAM_TOPSPD`, see below |

Top speed's provenance on the C64: the player starts as droid 001, type 0 → `DSpeed_t[0] = 4` →
`PlayerSpeed_t` (`$6D97` = `0,5,6,0,7,0,0,0,7`) index 4 = **7**, the fastest thing in the game.
Each axis accelerates independently, so a diagonal reaches ~1.4× that — as it does on the C64.

At 7 the port would sit at **175 px/s**, the C64's *empty-deck best case*; the original slows toward
117 px/s as an iteration drifts to 3 frames on a busy deck, and we do not. (That drift is also why
CE feels faster than the original — more iterations per second, not bigger steps.)

## Top speed is 8, not 7, and that is a camera decision

**The one movement number in the port not taken from the C64.** The CRTC scrolls in 4 px units and
the loop runs once per 2 fields, so the camera can only move 0, 4, 8 … px a pass. At a top speed of
7 the world must average 7, which no sequence of 4s and 8s hits — simulating the deadzone shows it
settling into **8, 8, 8, 4**, the Bresenham dither of 7 onto a 4 px grid, and that periodic 4 px
hiccup is what reads as jerk. The average is forced by arithmetic, so **no deadzone or camera policy
can remove it**; only a top speed the 4 px step divides can.

Four settings were built and played:

| `CAM_TOPSPD` | `PLY_ITER_FRAMES` | px/pass | px/s | camera dither | ramp |
|---|---|---|---|---|---|
| 7 | 2 | 7 | 175 | 8, 8, 8, 4 | 0.34 s |
| **8** | **2** | **8** | **200** | **none — uniform 8** | **0.39 s** |
| 4 | 2 | 4 | 100 | none — uniform 4 | 0.20 s |
| 7 | 3 | 4.67 | 117 | 4, 4, 4, 4, 4, 8 | 0.52 s |

`CAM_TOPSPD = 8` was kept: a uniform scroll was judged worth 14 % of fidelity. Verified in jsbeeb —
`xSpd` clamps at `&0800` exactly. It lands precisely on the one-row-per-pass ceiling that
`ASSERT PLY_MAXSPD <= 8 * 256` guards.

Two notes on the rejected rows, because neither is what it looks like:

- **`CAM_TOPSPD = 4`** lands within 15 % of the 1985 release's 117 px/s and does feel close to it —
  but `PLY_ACCEL` is *not* scaled by `CAM_TOPSPD`, so it reaches that speed in 0.20 s against the
  original's 0.52 s. Right terminal velocity, wrong ramp; it plays snappier than it moves.
- **`PLY_ITER_FRAMES = 3`** is the only setting that reproduces the 1985 release properly — 117 px/s
  *and* a 0.52 s ramp, because that constant scales velocity by 2/3 and acceleration by 4/9
  together. It is the fidelity choice, and it is one constant away (`CAM_TOPSPD` back to 7). It lost
  on feel: 4.67 does not divide 4 either, so the scroll dithers again, just far more mildly.

**An earlier build ran at `FRAME_LOCK = 1`** — 3.5 px per field, quarter acceleration, the same
motion sampled at 50 Hz and genuinely smoother than the original. It was given up because with a
full sprite pool the loop no longer fits in a field, so free-running stretched to ~1.25 fields an
iteration and the player moved 20% slower with droids on screen than without. Speed that depends on
what is visible is worse than speed that is merely chunkier. See `src/player.asm:45-54`.

**The position needs a fraction byte.** The C64 adds only the whole-pixel part of the speed and
drops the fraction every iteration. We keep it: the speed is fractional all the way up the
acceleration ramp, and truncating each pass loses up to a pixel a pass and makes the first few
passes move nothing at all — a sticky start rather than a smooth one. `posXf`/`posYf` make the
position 16.8 and the speed adds into it whole, as a 24-bit signed add. Clamping, stopping and
wall-snapping all clear the fraction so the result lands on a whole pixel.

The clamp is 16-bit for the same reason — the fraction is part of the limit rather than something
to discard — even though at `FRAME_LOCK = 2` the limit itself happens to land on a whole 7.

## Two camera schemes costed and rejected — read before re-opening this

Both came out of trying to fix the 8, 8, 8, 4 jerk *without* changing the top speed. Neither works,
and the reasons are worth keeping because both look obviously right on paper.

### A lazy camera cannot keep up, and the decks are too long to hide it

The proposal was: on reaching the deadzone edge, scroll a fixed 4 px a pass until the player is back
at centre. At a top speed of 7 that is a **3 px/pass deficit = 75 px/s**, and the margin from the
deadzone edge (screen x 156) to the sprite's right limit (296) is 140 px — so the camera falls off
the back after 47 passes, **1.9 s, 327 world px** of continuous running.

The decks do not co-operate. Decoding `levels.asm` + `tiledefs.asm` (RLE per `BuildLevel`, solid =
character bit 7, deck padding excluded) gives the longest uninterrupted horizontal open runs:

| deck | longest run | | deck | longest run |
|---|---|---|---|---|
| 3, 10, 11 | **136 ch = 1088 px** | | 2, 12 | 104 ch = 832 px |
| 4 | 94 ch = 752 px | | 14 | 88 ch = 704 px |
| 1 | 80 ch = 640 px | | 5 | 66 ch = 528 px |
| 15 | 60 ch = 480 px | | 7 | 50 ch = 400 px |
| 6 | 49 ch = 392 px | | 8 | 42 ch = 336 px |
| 13 | 40 ch = 320 px | | 0, 9 | 34 / 32 ch = 272 / 256 px |

Median run is 2 ch and p90 is 18 ch, but the **max is 1088 px** — over 3× the budget. Traversing it
at top speed leaves the camera 465 px behind, i.e. the droid leaves the screen. Even deck 0's modest
272 px run costs 117 px of drift, which eats essentially the whole right-hand margin on its own.

More fundamentally: *any* camera policy must still average 7 px a pass at top speed, so it can only
relocate the dither, not remove it. A recentring variant ("run at 8 until back at centre") was
simulated and is worse — ~16 passes of smooth 8 px scrolling then a ~2-pass **dead stop**, repeating
every 730 ms. Lower frequency, much higher amplitude.

### Splitting the CRTC step across the two fields corrupts the picture

The idea: park the half-way point of the move for the pass's FIRST field and the full move for the
second, so an 8 px pass scrolls 4 + 4 at 50 Hz. One extra CRTC park, ~18 cycles at fire 1, no extra
drawing at all, because the columns for the whole move are drawn before either field displays.

It does not work, and the strip is why. **15 displayed rows of 80 units are 9600 contiguous bytes of
a 10240-byte ring, so rows are adjacent.** Moving the displayed start back one unit therefore does
not translate the picture — it **splices**, taking each row's leftmost column from the row above's
rightmost. On a rightward move that column is the leading edge `DrawColumn` has just written, so the
lagging field shows the new right-hand column down the left edge of rows 1–14.

It was built and it ran, and *a still screenshot looked clean* — the artefact is 4 px wide. It was
caught by exaggerating the lag to 20 units in jsbeeb: the view **re-framed rather than translating
80 px**, which is the splice. Same wrap geometry as the sprite smear fixed in `39315d0`, and a good
reminder of why the rule is to verify against the buffer rather than the picture.

A correct version has to make the half-step **lead** rather than lag — draw the leading edge for the
half position, display it, then draw the rest — which means splitting `DoRedraws` across the two
fields, not merely re-parking the CRTC. That is a real restructure, complicated by the sprite pass
(36,274 of the pass's cycles, and it runs once). Not attempted.

## What the C64 updates at 50 Hz — and what it doesn't

Worth recording, because it is the thing that justifies the 25 Hz lock. The C64's four-stage raster
IRQ chain (`Irq_254`/`Irq_91`/`Irq_118`/`Irq_246`, `$6EC0–$6FE9`) runs every field, but **it never
writes a sprite position**. Its writes are `$D011`/`$D016` (fine scroll), `$D018` (charset bank),
`$D012`/`$D019`/`$D01A` (chain bookkeeping), the eight sprite pointers at `$4BF8–$4BFF`, and a read
of `$D01E` for collisions — plus `Sound` at `$0500`, which really is a 50 Hz job.

Sprite X/Y reach `$D000–$D00F` only through `WrSpriteState` (`$2643`), and every one of its call
sites is game code (`$14A5` … `$3E90`, plus the `$E1xx` copies). The fine-scroll and sprite-pointer
shadows the IRQ copies out are likewise only written by the game loop. So the hardware *latches*
every visual value at 50 Hz, but the values only *change* once per `GameLoop` iteration: the player
sprite sits still for 2–3 fields and then jumps 7 px. It does not flicker or tear while it waits —
a VIC-II sprite is a hardware overlay — but the motion is sampled at ~16–25 Hz, not 50. Our 25 Hz
lock is the top of that range, not a concession below it.

*Deliberate divergence:* the C64's accelerate-negative path is one 256th weaker than its positive
one, an artefact of the `SEC`/`ADC` idiom it uses to subtract. We subtract properly and both
directions match.

Opposite keys cancel, which falls out of a `DEC`/`INC` pair rather than needing a test — and that
retires the hand-written up/down exclusion Layer 3d needed.

## The view scrolls off the map vertically, and has to

The player's reference cell is fixed at `PLY_REFY` (63 px) below the view origin, so clamping the
view at the map edge stopped the player `PLY_REFY/8` rows short of it — **eight character rows at
each end of a deck that could be seen but never entered.** On deck 1 the top wall is character rows
0–3 and the first corridor is 4–7, so the player was pinned to the bottom scanline of that corridor
and could not reach the two doors on it. Symmetrical at the bottom for the decks that are a full 16
tiles tall.

`DoMove` (`$3849`) has **no clamp at all** — it adds the speed to `ScreenPosY` with plain 16-bit
arithmetic and lets the view run off the map, which is why the original shows blank space above the
top wall. Only the wall probes stop the player. The port now does the same, bounded to `PLY_VOID` =
64 px either side, which is enough for the reference cell to reach rows 0 and 63 and keeps `mapYr`
inside a signed byte.

Three consequences, and the third is what made it cheap:

- **`mapYr` is signed**, so `ApplyMove` needs an *arithmetic* shift for `posY >> 3`. That is not
  pedantry: floor division is what makes `posY AND 7` the correct sub-row offset on the negative
  side as well.
- **`ClampY`'s low end is a compare against `MIN_PX_Y`**, not against zero. Both values are above
  `&80` on that path, so an unsigned compare orders them correctly — the same trick `ca_clampneg`
  already used.
- **Off the map is a row of tile 0.** Map rows are 0–63, so a single `AND #&C0` catches a negative
  row and one past 63 at once. `BandSetRow` points `maprow` at 64 zero bytes, `DrawColumn` points
  `tdp` at `tiledefs` (tile 0 is 16 zero bytes), and `MapChar` returns character 0 — blank, and bit 7
  clear, so the probes read it as walkable and only the deck's own edge wall stops the player. The
  rest of the draw runs completely unchanged.

**Verified:** play buffer diffed byte-for-byte against `RedrawAll` at `mapYr` = −3, after a diagonal
scroll along the top edge, with `JSR SprDrawAll` poked to NOPs — **0 differences in 10240**. That is
the check that matters, because the incremental path reaches the blank rows through `BandSetRow` and
`DrawColumn` while `RedrawAll` reaches them through `MapChar`.

## Wall collision, and a one-pixel jitter worth understanding

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

## Memory: the charset moved to `&0400`

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

## The frame budget — closed, and how

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
| Sprite: precompose the current phase instead of `PlyFetchRow` per row | ~2,500 |
| Cache the previous frame's 40 row pointers — group 2 of frame N is group 1 of frame N+1 | ~2,300 |
| Replace `keydown`'s OSBYTE `&81` with a direct System VIA matrix scan | ~2,000 |
| Inline `BufNextUnit` / `CellXInc` — 36 cycles of call overhead per character | ~1,440 |
| Unroll `DrawColumn`'s 8-byte copy | ~1,100 |

`CopyRun` was the top line and is done — see *The level draw* below for what it was worth and what
is left behind it.

**The deadlines are staggered and tighter than a frame**, which matters more than the frame total:
an **up**-band and the columns both display at `P+64`, so they share only 192 scanlines (24,576
cycles), while a **down**-band has until `P+184` of the next frame.

## The level draw — where its time goes, measured

Measured 2026-08-13 with **`DEBUG_TIME`** in `main.asm` — a User VIA T1 bracket around one routine,
plus a poked `dbgSpdX`/`dbgSpdY` that takes the controls over and skips `CheckWalls`, so a run is
exact and repeatable in a way a held key is not. Its header carries the arithmetic and the two
rules that make a reading mean anything (one call site; poke, do not press). One game pass is
2 fields = **79,872 cycles**; top speed is 7 px a pass.

The band's cost separates cleanly into a per-row entry fee and a per-scanline copy, fitted from
three vertical speeds whose bands each fall inside one character row (1, 2 and 4 px a pass):

```
band = 10,954 per DrawBandRows pass  +  1,371 per scanline across the 320 px width
```

Per character across the 40-character width that is **274 fixed + 34 a scanline**. The fixed part,
by static count: `BandCharPtr` 99 (36%), two `BufNextUnit` 66, two `CopyRun` call+setup 34,
`CellXInc` 20, `chp + 8` 13, loop control 8. **Half of it is JSR/RTS and pointer arithmetic, not
lookups** — which is what makes the inlining line in the table above real.

A column is **5,005 cycles**, 313 per 8-byte cell: `ColCharPtr` ~114, the copy 129, pointer advance
and wrap test 26, loop control 18. It spends 40% of its time copying against the band's 23%,
because one lookup serves 8 bytes there instead of 2.

Per byte written: band 51 cycles, column 40, against a floor of ~18 for the copy loop itself.

### `CopyRun` unrolled — the parameterisation outlived its case

`CopyRun` took `bandScan` and `bandRun` as variables and cost 18 cycles a byte to do it. After the
whole-row change `DrawBandRows` has one caller which always passes 0 and 8, so that generality was
being paid 640 times a band pass to support a case that no longer occurs. Unrolled into a `COPYCELL`
macro with an immediate `Y` — 13 cycles a byte, the floor for `(zp),Y` on both sides — and inlined
at the two sites inside the loop. The two edge halves of an odd `mapHX` call `CopyCell` instead:
they run once a pass against the loop's 40, and 12 cycles of call is not worth 48 bytes each.
`bandScan` and `bandRun` are deleted.

| per pass, 7 px | scanline bands | whole rows | + unrolled copy |
|---|---|---|---|
| vertical | 28,527 | 19,655 | **15,280** |
| full diagonal | 38,472 | 28,143 | **24,249** |
| one band pass | 31,505 *(peak, 2 rows)* | 22,311 | **17,290** |

**−5,021 a band pass for +114 bytes**, against −4,560 predicted. Cumulatively the level draw is
**46% cheaper vertically and 37% on a diagonal** than it was at the start of the day. Columns are
untouched and measure 5,260, confirming the change is where it was meant to be.

Where a character's 414 cycles now go: pixel copy 176 (43%), `BandCharPtr` 99 (24%), two
`BufNextUnit` 66 (16%), `CellXInc` and loop 28, `chp + 8` 13, `Y` setup 32. Copy loop overhead has
gone from 146 to 32.

### `charRemap` precomputed — address arithmetic beat the lookup it followed

`charRemap` packs the used-character index into a byte, and every one of the three lookup paths
unpacked it into a 16-bit pointer at the point of use: `PHA`, `AND`, four `ASL`s, `PLA`, four
`LSR`s, `ADC`. **41 cycles of address arithmetic per character drawn — more than the tile-map
lookup it follows**, which is cached three calls in four and costs ~11 amortised. That is the shape
worth remembering: the expensive part of "decoding a tile" was not the decoding.

`BuildCharPtrs` folds it into `CHAR_PTR_LO`/`CHAR_PTR_HI` at startup, so a lookup is `TAX` and two
indexed loads: **16 cycles**. Both tables are page aligned, so the `abs,X` never crosses a page.
They cost 512 bytes at `&5500-&56FF`, of the scratch between the panel and the strip that nothing
else wanted, and the code came out 3 bytes *smaller* — three unpack blocks deleted against one
builder added.

It is a pure function of `charRemap` and the charset base, both fixed for the whole run, so it is
built once rather than per deck: `BuildCharset` rewrites the charset's *contents* per deck, never
its address. `charRemap` is now read only at startup — `tiledefs` is what still pins the data bank
in during play.

| per pass, 7 px | + unrolled copy | + precomputed pointers |
|---|---|---|
| horizontal | 8,759 | **8,067** |
| vertical | 15,280 | **14,304** |
| full diagonal | 24,249 | **22,810** |
| one band pass | 17,290 | **16,237** |
| one column | 5,005 | **4,663** |

**−1,053 a band pass and −342 a column**, against −1,000 and −400 predicted. This one helps every
path that draws a character, which the previous two did not.

### One 16-byte run a character — and why no loop split was needed

A character's two halves are 16 consecutive bytes in the charset, and the two units they go to are
16 consecutive bytes in the strip. So one `Y` running 0-15 addresses both, and the `chp + 8` and
the `BufNextUnit` that sat between the halves are simply gone.

The obstacle looked like the buffer wrap: it lands on a *unit* boundary, so it could fall between a
character's two halves, and the second half would then be written 8 bytes past `&8000` — into
sideways RAM, not a wrong pixel. The plan was to find the straddling character in the prologue and
split the loop around it. **It turns out not to be possible.** Units from the row start to the wrap
is `W = 1280 - off/8` where `off = (scrollS + rCount*640) MOD 10240`; `rCount*640` is 80 units, so
`W ≡ scrollS/8 (mod 2)`. Characters begin at even units when `mapHX` is even and odd units when it
is odd. So the wrap lands on a character boundary exactly when

```
scrollS/8 == mapHX   (mod 2)
```

and that is invariant: both sides move by `dUnits` horizontally, a vertical step moves `scrollS/8`
by 80 and `mapHX` not at all, `scrollS` wraps at 1280 units, and 80, 1280 and 0 are all even. Even
a clamp is safe, because `sDelta` is computed *from* the `mapHX` difference rather than alongside
it.

`LoadDeck` now sets `scrollS` to 0 or 8 to match `mapHX`'s parity instead of always 0. As things
stand that is a no-op — `CentreOnDeck` produces `charX * 2`, always even — but the consequence of
the invariant being false is a write outside the buffer, and that should not rest on another
routine's arithmetic staying as it is.

The per-character wrap test stays, at 8 cycles; only the *mid-character* case had to be excluded.
Its fixup moved out of line, which keeps the loop's branch in range and makes the common path a
not-taken `BCS` at 2 cycles rather than a taken `BCC` at 3.

| per pass, 7 px | + precomputed pointers | + 16-byte run |
|---|---|---|
| vertical | 14,304 | **12,225** |
| full diagonal | 22,810 | **20,482** |
| one band pass | 16,237 | **13,878** |

**−2,359 a band pass for +23 bytes**, against −2,320 predicted.

### `CellXInc` inlined, and the copy walks Y instead of reloading it

`CellXInc` is 8 cycles of work behind 12 of `JSR` and `RTS`. Inlining it in the loop would have
pushed the branch at the bottom past its 128-byte reach, so `COPYCELL`/`COPYCHAR` changed from
`LDY #n` per byte to a single `LDY #0` and `INY` between: **identical at 13 cycles a byte** — `LDY
#n` and `INY` are both 2 — but 5 bytes a copy against 6. That paid for the inlining twice over and
the build came out **19 bytes smaller**.

| per pass, 7 px | + 16-byte run | + inlined `CellXInc` |
|---|---|---|
| vertical | 12,225 | **11,803** |
| full diagonal | 20,482 | **20,065** |
| one band pass | 13,878 | **13,398** |

**−480 a band pass**, exactly as predicted.

### Where the level draw stands

| per pass, 7 px | start of 2026-08-13 | now | |
|---|---|---|---|
| vertical | 28,527 | **11,803** | **−59%** |
| full diagonal | 38,472 | **20,065** | **−48%** |

A character costs 318 cycles and **more than half of it is the pixel copy** (176), against a third
when the day started: `BandCharPtr` 74, buffer advance and wrap test 20, `cellX` and loop control
16, `Y` walk 32. The band has stopped being a lookup walk that happens to copy some bytes.

### Walking the tile row instead of `cellX` — and why it paid half what was predicted

`BandCharPtr` spent most of its 74 cycles rediscovering where it already was: derive the tile
column from `cellX`, compare it against a cache, then rebuild `(cellX AND 3) + subRowOfs` as an
index into the tile. But **a tile is 4 characters wide and those 4 codes are 4 consecutive bytes of
`tiledefs`**. The row is now walked as tiles of four, with the tile's row folded into `tdp` when it
is built — `(tile AND 15)*16` is at most 240 and `subRowOfs` at most 12, so the add cannot carry —
which leaves the four characters at `Y` = 0..3. `cellX` is no longer maintained across the row at
all; the trailing half of an odd `mapHX` recomputes it, and forces `tileCol` to miss rather than
trusting a stale column.

A row of 40 characters starting anywhere covers eleven tiles with a partial one at each end, so
each tile draws `min(4 - sub, remaining)` and every tile after the first starts at 0. That composes
with the odd-`mapHX` halves without a second special case.

| per pass, 7 px | + inlined `CellXInc` | + tile walk |
|---|---|---|
| vertical | 11,803 | **10,787** |
| full diagonal | 20,065 | **19,172** |
| one band pass | 13,398 | **12,245** |

**−1,153 a band pass for +111 bytes.** The estimate here was **2,240 and it came in at half that**,
for a reason worth recording: the per-tile block is 111 cycles, not the ~61 first counted, because
the walk's state does not fit in zero page and `LDY abs`/`INC abs` are a cycle or two dearer than
their zero-page forms — plus the `min()` is 46 of those 111. Moving `dbN` and `dbCount` into the
slots `halfSel` and `dirty` had been holding since both were retired recovered 162 of it. **Count
the addressing modes, not just the instructions, before quoting a saving.**

### DrawColumn, and the zero page nobody was using

`ColCharPtr` had one caller and ran 16 times a column, so it is inlined with its tile-row miss out
of line; the 8-byte copy uses `COPYCELL`; and the two multiplies became tables. `tdp = tiledefs +
tile*16` was 35 cycles of `PHA`/`AND`/four `ASL`s/`PLA`/four `LSR`s/`ADC` over 32 possible tiles,
and `maprow = tilemap + tileRow*64` was 30 over 16. Both are pure functions of labels fixed at
assembly time, so unlike `CHAR_PTR` they need **no builder and no RAM** — 96 bytes of the code image
that beebasm fills in. `colRight` went too: it is constant down a whole column, so `ColSetup` now
stores 0 or 8 in `colHalf` and the row loop adds it to the `CHAR_PTR` read instead of testing it.

Then **`&00-&3F` turned out to be entirely unused** — 64 bytes of language workspace nothing had
ever claimed. Everything the draw loops read went into it: `colSubX`, `colHalf` and `colTileRow` are
read once per row of every column, `dbTile` and `dbSub` once per tile of every band. An absolute
read is 4 cycles against 3, and the operand is a byte shorter, so the build **shrank 79 bytes**
while getting faster.

| per pass, 7 px | + tile walk | + DrawColumn | + zero page |
|---|---|---|---|
| one column | 4,663 | 3,811 | **3,764** |
| one band pass | 12,245 | 12,244 | **12,138** |
| horizontal | 8,067 | 6,594 | **6,513** |

> **One result does not add up and is recorded rather than explained.** The same `tdp` table was
> applied to the band's tile walk, where it should have been worth ~190 a band pass; the band
> measured 12,244 against 12,245. The column on the same build moved by the predicted amount, and
> the zero page move afterwards moved the band by 106 — so the harness is sensitive at that scale
> and the table genuinely did nothing there. Unexplained. Worth a controlled check before trusting
> any further reasoning about the band's tile block.

### Where the level draw stands

| per pass, 7 px | start of 2026-08-13 | now | |
|---|---|---|---|
| vertical | 28,527 | **10,701** | **−62%** |
| horizontal | 8,920 | **6,513** | **−27%** |
| full diagonal | 38,472 | **~19,000** | **−51%** |

Of a band pass's 12,245 cycles, **8,320 is the irreducible byte movement** — 13 cycles a byte is
what `(zp),Y` on both sides costs and 640 bytes have to move. Two thirds of what is left is the
copy itself.

Still in the bank, all of it now small:

| | per band pass |
|---|---|
| Hoist the `min(4 - sub, remaining)` out of the nine middle tiles by splitting head / full / tail | ~400 |
| Inline `BandCharPtr`'s call for the two edge halves — 12 cycles, twice a pass | ~24 |
| Self-modify the copy's addresses to use `abs,Y` instead of `(zp),Y` — 11 cycles a byte instead of 13, less the patching. Self-modifying code in the hottest loop in the port | ~1,000 |

The first two are not worth the code paths. The third is the only one with real money in it and it
is the least pleasant. **The band is close enough to done that the next real gains are elsewhere** —
the sprite pool, or `keydown`'s OSBYTE `&81`.

### Whole rows, not exposed scanlines

`DrawBand` used to draw exactly the scanlines a move exposed, splitting them across two character
rows whenever they straddled a boundary — which at 7 px a pass is 7 passes in 8. That paid the
40-character lookup walk **2.03 times per map row** against a floor of 1, measured.

It now draws one whole character row, and only on the pass that crosses into it. The copy volume is
identical at every speed — all 8 scanlines of every row get drawn either way — so the whole saving
is the eliminated duplicate walk, and it is worth **~10,000 cycles a pass at any non-zero vertical
speed**, including 1 px/pass where the old scheme paid a full walk to move one scanline.

| per pass, 7 px | before | after | |
|---|---|---|---|
| horizontal | 8,920 | 8,759 | −2% |
| vertical | 28,527 | **19,655** | **−31%** |
| full diagonal | 38,472 | **28,143** | **−27%** |
| band passes per 42 game passes | 73 | **37** | one per crossing |
| cost of one band pass | — | 22,311 | model says 21,922 |

Peak improves as well as average — the worst pass was 2 rows + 7 scanlines = 31,505, and is now
1 row + 8 = 22,311 — which matters more, because the deadline is per pass and staggered.

**It costs no window height, and that is the part worth understanding.** The handover is exactly
clean with the 16-row strip: going down, when `mapYr` reaches `M+1` the window starts at
`(M+1)*8 + line'`, so map row `M` is wholly above it at the moment map row `M+16` — which occupies
the same physical row, since old relative 0 is new relative 15 — needs its first scanline. Going
up, `line < d` is precisely the condition for the decrement and also the condition for the bottom
row having left the window. The 16th row already given up to smooth scrolling *is* the slack this
needs.

**And it retires the split row.** Every physical row now holds one map row entire, so
`DrawColumn`'s repair pass, `RedrawAll`'s repair pass, and `DrawHalfScan`/`DrawHalfPart` are all
deleted — **230 bytes**, and `RedrawAll` becomes a valid oracle at any value of `line`, which it
was not. **BUGS #1 should be moot**; re-run its tests before closing it.

The one new constraint: a pass must cross at most one row boundary, or the second crossing is never
drawn and the strip holds a stale row that only shows when it scrolls into view. `ASSERT
PLY_MAXSPD <= 8 * 256` in `player.asm` fails the build rather than leaving that to be discovered in
play.

### The budget, and one measurement trap

Stationary with seven sprites live, the loop is **idle 40,729 of 79,872 cycles**, corroborating the
39,212 measured during the sprite work. The full-diagonal level draw was consuming 38,472 of that —
95% of the standing headroom — and now consumes 28,143, leaving ~12,600.

*Do not measure idle while scrolling to check this.* `TestDroidsUpdate` pins the test droids to
world positions, so they leave the view within ~10 passes and the sprite cost collapses; measured
idle under a diagonal was a flattering 24,583. The 95% figure is the sum of two independently
measured quantities, which is the right way round.

### Reading `DEBUG_DRAW`

The bands only appear where the CRTC is displaying something. From `drawFlag` release at `P+184`
through VSync to the next panel at `P+312`, nothing is display-enabled — R6 has already ended the
play cycle and the tail displays no rows — so that whole stretch is black whatever the palette
says. The panel is the first place a tint can land, 128 scanlines after the loop starts.

So the yellow band shows **where the level draw finishes, not how long it took**. No yellow means
it ended before `P+312`, not that it was free: horizontal scrolling shows no bands at all. Yellow
reaching into the play area means the draw is still writing while the raster reads — on a
row-crossing pass it currently does, by about five rows.

## Verified

Play buffer diffed byte-for-byte against `RedrawAll` after full-speed diagonal scrolling in both
vertical directions:

| | result |
|---|---|
| odd `mapHX` (167), `line` = 1, before the dead zone | **0 real differences in 10240** |
| odd `mapHX` (155), `line` = 5, sprite at unit 39 with a 2 px shift | **0 real differences in 10240** |

In both runs some bytes differed and every one was inside the sprite's own footprint, where the
rotor had spun between the two dumps. Compute that footprint and exclude it rather than staring at
the diff wondering — it depends on `scrollS`, `line` and `plyUnit`.

Re-verified after the whole-row band, this time with `JSR SprDrawAll` poked to NOPs so the rotor
could not pollute the diff at all — simpler than computing the footprint, and worth doing that way
from now on:

| | result |
|---|---|
| odd `mapHX` (137), `line` = 1, down-right diagonal | **0 differences in 10240** |
| odd `mapHX` (107), `line` = 4, up-left then down — `line` wrapped both ways | **0 differences in 10240** |
| even `mapHX` (142), `line` = 3, after an 11M-cycle diagonal through the vertical clamp | **0 differences in 10240** |

and again after `CopyRun` was unrolled, covering both branches of the odd/even split:

| | result |
|---|---|
| odd `mapHX` (137), `line` = 1 — leading and trailing halves, 39 whole characters | **0 differences in 10240** |
| even `mapHX` (180), `line` = 1, deck 2 — the plain 40-character loop | **0 differences in 10240** |

> **Let the view SETTLE before the first dump, and check it has not moved between the two.** A run
> that dumped two passes after releasing the keys reported 66 differing bytes; the view had coasted
> one unit between the dumps, so the two were of different scroll positions. Record `mapHX`,
> `mapYr`, `line` and `scrollS` with each dump and compare them before believing a diff. Deck 2 is
> the easy way to an even `mapHX`: it centres at 180.

Then the clean build with sprites live: diagonal scrolling and a deck change both render correctly,
no torn top or bottom row.

> **jsbeeb will not boot an unpadded SSD.** It hangs in the DFS FDC poll at `&ACAE` loading
> `PARASPR`, because beebasm's image ends mid-track and jsbeeb will not read the last partial one.
> It reproduces from BASIC with `*LOAD PARASPR`, so it is not the game. Pad a copy to 200K before
> handing it to the emulator. This cost an hour before it was recognised as an emulator problem.
