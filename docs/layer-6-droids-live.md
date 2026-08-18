# Layer 6 — the droids come alive

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

Layer 5 gave the deck droids that walk its waypoints
([`layer-5-droids.md`](layer-5-droids.md)). This layer is what turns a patrol into a population:
they can be hidden by the deck's own walls, they bump into each other and into the player, and the
driver is shaped so that Layer 7's bullets and explosions are a table entry rather than a rewrite.

| C64 | ours |
|---|---|
| `DroidModeJump` dispatch in `RunDroids` `$1769` | the mode test at the head of `DroidRun` |
| `LineOfVisibility` `$24AE` + `TestNextPiece` + `CalcDeltaAdd` | `DrLineOfSight` |
| `DoCollision` `$19EA` — the `_ply_droid` arm | `DrCollide` → `DrCollided` → `DrBounce` |
| `DoCollision2` `$1B51`, collision type `08` | the droid-v-droid arm of `DrCollided` |
| `ReverseDroidDir` `$1C5F` / `PauseDroidFor16` `$1C39` | `DrReverse` / `DrPause16` |

## Line of sight

`LineOfVisibility` walks the character grid from the player's cell towards the droid's and answers
whether anything solid is in the way. Carry set means blocked, and `dMd0_droid` turns that straight
into `SpriteEna`: **a droid behind a wall keeps its hardware sprite and is simply not displayed.**

The walk is a DDA with an 8.8 step, and the interesting part is `CalcDeltaAdd`, which normalises
the step **without dividing**: double the delta pair while both still fit in a byte, then add the
originals until one would overflow. The longer axis ends up stepping between half a character and
a whole one, and the shorter one keeps its proportion. That is ported as it stands.

**What could not be ported is how it knows it has arrived.** The original tracks its position as a
pointer into the 16K character map, so the two axes are the two bytes of one address and "have we
passed the target" is a pointer comparison. We deliberately do not have that map — `MapChar`
computes a character from the tile map, which is the 15K saving Layer 2 was built on — so the two
coordinates are held apart and the walk ends when the **dominant** axis reaches its target. The
dominant axis is monotonic by construction, so it is the same test written differently.

### Slot ownership had to be separated from `sprActive`

Hiding a droid is not the same as freeing its slot, and until this layer the port had only one flag
for both. So `drSlotOwner[7]` now says which droid holds each slot and `sprActive` says whether the
blitter draws it; `DrFindSlot` scans ownership, not activity. Without that, a droid that stepped
behind a wall would release its slot, another droid would take it, and the first would be destroyed
by the C64's "no free sprite" path the moment it stepped back into the light.

`DroidsUpdate`'s compaction has to carry ownership with it: when a droid moves down the table, its
slot has to be told where it went. That is three instructions and it is the kind of thing that
produces a sprite drawn at another droid's position a minute later.

### One sight line a pass

Six walks measured **~8,600 cycles a pass** — more than a tenth of the whole pass, on a question
whose answer changes when a droid walks through a doorway and not otherwise. So the slots take
turns: `losTurn` steps one slot a pass, and a droid that has *just* been allocated a slot is tested
at once rather than waiting for its turn, because there is no previous answer to reuse.

The cost is that a droid stepping behind a wall can stay drawn for five more passes — a fifth of a
second. That was judged cheaper than the budget it buys back. It is `drVis`/`drVisNew` in the
source and it is easy to revert if it ever reads wrong.

> This is the second time this port has traded exactness for the frame budget, after `CAM_TOPSPD`.
> Both are recorded on the constant itself as well as here.

## Collision: the one thing with no faithful port available

Everything else in the droid work is the listing's own arithmetic. This is not, and it is worth
being blunt about why.

`DoCollision` begins `LDA SprSprCollision` — `$D01E`, the VIC's sprite-to-sprite collision latch.
It is hardware, it is **pixel-exact**, and it is free. A software blitter knows what it wrote, not
what it overlapped, so there is nothing to read and the choice is between a box test and comparing
the pixels a second time. A box test it is.

**The box is deliberately smaller than the sprite.** A droid is 24 × 21, but most of its corners
are the rotor's transparent gaps, so a full-size box collides where the VIC would not — droids
bouncing off each other with clear space between them. `DR_COL_W` = 18 and `DR_COL_H` = 14 are a
judgement about where two droids *look* like they have touched, and they are meant to be tuned by
eye rather than derived.

Two things about the original's shape are kept because they matter:

- **One pair a pass.** `DoCollision` picks the two lowest set bits out of the register and handles
  that pair alone; the rest wait for the next iteration. Ours stops at the first overlapping pair.
- **Only drawn sprites collide.** That falls out of the C64 reading a *display* register, and it
  means a droid hidden behind a wall cannot be bumped into. Ours tests `sprActive`, which is now
  exactly "the blitter draws it", so the same property holds for the same reason.

What happens on contact, from `DoCollision2`'s type table (`$6D6D`, entry `08` = "reverse dir") and
the `_ply_droid` arm:

| | |
|---|---|
| droid v droid | the first reverses direction, the second stands still for 16 iterations |
| player v droid | the droid does **both**, and the player's own speed is negated and doubled |

Damage, scoring, `Alert` and the transfer game all hang off those same two arms in the original.
They are Layer 7's; this is the movement half on its own.

### The bounce is clamped, and the C64's is not

`$1A85` negates the whole-pixel part of each player speed, forces it to at least 1, and doubles it.
Ours does the same and then **clamps to `CAM_TOPSPD`**, because our band redraw brings in exactly
one character row a pass — the `ASSERT PLY_MAXSPD <= 8 * 256` in `player.asm`. Doubling 8 px into
16 would cross two rows, the second would never be drawn, and the strip would hold a stale row to
show later as a band of the wrong deck. The C64 scrolls a pixel at a time and has no such ceiling.

### The debounce is the original's, and it is load-bearing

`ReverseDroidDir` guards itself with `byte_0_6C`, which `DoCollision` clears on any pass with no
collision at all. So a reverse happens **once per collision episode**, not once per pass — without
it, two droids sitting on top of each other reverse every pass and vibrate. `drCollHit`/`drCollWas`
are the same latch.

> **Written down here in Layer 6, and then not implemented on the droid-droid arm.** The paragraph
> above is right and the code was wrong for two months: `DrReverse` dropped the guard, and only the
> *player* arm tested it. Two droids did exactly what the last sentence predicts. Fixed 2026-08-18
> — see `BUGS.md` #7a and §Collision fidelity below.

---

## Collision fidelity — revisited 2026-08-18

Prompted by KC from play: droids lock together far more readily here than on the C64. Two separate
faults, one a defect and one a shape.

### The reverse was never debounced on the droid-droid arm — **defect, fixed**

`ReverseDroidDir` (`$1C5F`) carries the latch **inside itself**, before it touches the speeds:

```
1C5F  LDA collision2mode
1C61  EOR #$FF
1C63  CMP byte_0_6C
1C65  BEQ _1            \ already latched against this — do nothing at all
1C67  STA byte_0_6C
      ...negate droidSpdX,X and droidSpdY,X...
```

Both call sites reach it: `DoCollision2`'s `_08_1` (`$1BA6`, droid v droid) and `$1A82` in
`_ply_droid`. Our `DrReverse` omitted the `CMP`/`BEQ` on a note that both call sites had already
made the test — true of `dc_player`, which tests `drCollWas`, and **false of the droid-droid arm**,
which called `DrReverse` unconditionally.

What that produces, while two droids overlap:

| pass | droid A (the outer slot) | droid B (the inner) |
|---|---|---|
| 1 | reverses, starts walking away | `drState = 16` |
| 2 | still overlapping → **reverses again**, back into B | re-paused to 16 |
| 3 | reverses again | re-paused to 16 |

A jitters on the spot with no net drift, and B is re-frozen every pass so its 16 can never run out.
The pair is stuck permanently. On the C64 the second and later passes change nothing: A keeps the
direction it was given, clears the overlap in a few iterations, and B's pause then expires. Both
machines re-pause B every pass — `_08_2` is unguarded — so the pause is not the difference; the
reverse is.

**The latch must also persist.** `byte_0_6C` is cleared at `_x_none` (`$1A3E`) alone — a pass on
which no colliding pair was found at all. Ours cleared it at the top of every pass and re-latched
it from `DrReverse`, so a pass the guard suppressed left it zero and re-armed the reverse for the
pass after. That alone would have halved the oscillation rate without stopping it. So the fix is
both halves: the guard inside `DrReverse`, and one persistent `drCollHit` cleared only where the
C64 clears it. `drCollWas` is gone.

**The latch value is a tag, not a boolean.** In the droid path `collision2mode` is `SprNumber >> 5`,
so what gets stored is `$FF` — "a droid", any droid. In the player path (`$1A73`) it is the raw
`SprNumber` of the specific droid hit. We store `$FF` from `DrReverse` and test for non-zero, which
matches the droid-droid case exactly and is coarser than the original only for the player: on the
C64 he can bounce off droid 2 in the pass after bouncing off droid 1, and here he cannot until a
clear pass. Left coarse deliberately — the finer tag needs the droid index threaded into `DrReverse`
and the player arm is not where the complaint came from.

### The box is the wrong shape — **[DECISION 1]: replace it with a generated distance profile**

Not yet built. Agreed with KC 2026-08-18, before building, under the usual rule.

The box test is `|dx| < 18 && |dy| < 14`, and its constants were always marked "meant to be tuned by
eye". Its problem is not its area but its corners: two droids offset by (17, 13) are visibly clear
of each other — the sprites are 24 wide and those are the rotor's transparent gaps — and the box
says they have collided. Those are also the offsets from which a single reverse is least likely to
separate the pair, so the shape and the defect above compounded.

**What replaces it.** The Paradroid Redux author solved the same problem the same way and wrote it
up at <https://paradro.id/coltest.html>: a table of the minimum `|dx|` that clears, indexed by
`|dy|`, so the region is an octagonal envelope tracking the silhouette instead of a rectangle. His
droid-droid table, for the record:

```
DroidDroidDX: 23,23,23,23,22,22,21,21,20,19,18,17,16,15,13,11,7,3,0,0,0
```

**We generate ours rather than copy his.** `tools/export_droids.py` already replays
`BuildDroidSprite` and `AnimateDroids` and has per-pixel opacity, so for each `dy` in 0..20 it can
compute the smallest `dx` at which any opaque pixel of two droids overlaps, unioned over the eight
rotor phases. Redux simplified his masks the same way — "eliminated animated sprite variations and
holes". The result is what `$D01E` would have reported on the original's own artwork, so this is a
deviation in **mechanism** (a table where the C64 read a register) and not in behaviour; it is more
faithful than the box, not less, and it retires two hand-tuned constants.

**Why it is affordable.** `TAY` then `CMP drColDX,Y` is 4 cycles against `CMP #imm`'s 2, plus one
range check on `|dy|`; the table is 21 bytes. Against a `DrCollide` that already costs ~1,400 cycles
a pass this is noise.

`BUL_COL_W`/`BUL_COL_H` get the same treatment as a second, smaller table when this lands.

### What is NOT changing

- **One pair a pass.** `DoCollision` takes the two lowest set bits of `$D01E` and leaves the rest.
  Faithful, and a pile-up unwinding one pair at a time is the original's behaviour.
- **`DrPause16`'s 16 and `DrBounce`'s doubling.** Judged by feel, and only once the two faults above
  are out of the way — `BUGS.md` #7b.

## The mode dispatch

`RunDroids` picks a handler from `DroidModeJump` using the top bits of the droid's type: mode 0 is a
droid, 1 a bullet, 2 an explosion. Types `$20` and up are therefore not droids at all — which is
how `dMd1_bullet` can keep its countdown in `droidType` and how a bullet becomes an explosion by
having `$40` written into it.

`DroidRun` now makes that test and returns for anything that is not mode 0, so Layer 7 adds two
arms rather than restructuring the driver. Nothing yet creates a type above 23.

## The bug that cost the most

**`DrLineOfSight` does not preserve X**, because the scaling loop uses it as scratch exactly as
`CalcDeltaAdd` does. The caller was still holding the droid index there.

The symptom was that **the player disappeared**. `sprActive,Y` was written with a Y read out of
`drSprNum` at a junk index — which lands in a neighbouring array, so the value was a plausible-
looking small number — and three sprite slots that nobody owned were switched on with no position
ever written into them. The pool then drew three slots of rubbish and the player was somewhere
underneath.

Worth keeping for two reasons. The visible failure was in a completely different subsystem from the
change, and the arrays being adjacent is what turned an out-of-range index into a *believable* one
rather than an obvious crash.

## What it costs

`DroidsUpdate`, User VIA T1 bracket, 128 passes averaged, deck 1, 11 droids alive:

| | cycles a pass |
|---|---|
| Layer 5, movement only | 15,576 |
| + line of sight (every near droid) + collision | 20,238 |
| + line of sight taking turns | **16,967** |
| six droids poked around the player, stationary | 14,146 |
| 11 droids, scrolling full diagonal | ~17,000 |

So this layer costs about **1,400 cycles a pass** over Layer 5, and the sight line as originally
written would have cost 4,700.

**The frame lock holds in every case measured**: 128 passes in exactly 10,223,616 cycles, which is
79,872 a pass — the loop is still taking two fields and no more.

> **The worst case has NOT been measured and is not obviously safe.** Seven sprites drawn
> (36,274 by the blitter's own measurement) plus this (17,000) plus a full-diagonal level draw
> (19,172 from Layer 4) is 72,000 of 79,872 before anything else in the loop. Arranging six droids
> that are simultaneously on screen, in line of sight, and being scrolled diagonally did not happen
> by chance in any of these runs, and poking them into place put most of them inside walls where
> the sight line hid them again. It wants a deliberate rig on a deck with a long open corridor.

## Verification

| | |
|---|---|
| Restore vs `RedrawAll`, droids walking, sight lines and collisions live | **0 of 10240** |
| The same at `line == 1` after a full-speed diagonal scroll | **0 of 10240** |
| A droid walking into the player | paused 16 iterations, player nudged clear, droid reversed |
| Frame lock, all measured cases | 128 passes in 128 × 79,872 cycles exactly |

## Still open — as of Layer 6; the first three have since landed

- **Main RAM has 116 bytes left.** *(Relieved 2026-08-15 exactly as below — `droid.asm` moved into
  bank 4 — and since refilled by Layers 7–10; see `docs/memory-map.md`.)* `&1100–&2F8C` against a ceiling of `&3000`, and Layer 7 needs
  bullets, explosions, damage and scoring. The remedy is the one Layer 4 already used: move
  `droid.asm` into **bank 4** beside the tile and deck data it reads. It calls `MapChar` (already
  in that bank) and `DoorProbe` (main RAM, which bank code may call freely), and it runs from the
  main loop and from `LoadDeck` where `SWRAM_DATA` is the resting state — so the rule in
  `bufcore.asm`'s header is satisfied. **Read that header before doing it.**
  Building with `DEBUG_TIME` already overruns and needs `DEBUG_VSYNC` turned off to fit, which is
  how this was noticed.
- **No firing, no damage, no `Alert`.** Layer 7 — landed ([`layer-7-combat.md`](layer-7-combat.md)).
- **The transfer game arm.** `DoCollision`'s `_ply_droid` checks `moveMode` first: with the player
  in transfer mode a collision sets `xferDroid` instead of bouncing. Layer 10 — landed
  ([`layer-10-transfer.md`](layer-10-transfer.md)).
- **`DR_COL_W`/`DR_COL_H` have not been played with**, only measured. They are the first thing to
  adjust if droids feel sticky or pass through each other.
- **Three things from KC's first play of this build**, all in `BUGS.md`: droids that lock together
  (#7a), a player bounce that reads as heavy even though it is already gentler than the C64's
  (#7b — the camera's 4-pixel step is the likelier culprit than the speed), and **droids seen
  inside walls** (#8), which is a correctness fault rather than feel and did not reproduce in an
  idle 100-second run.
