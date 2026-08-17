# Layer 5 — droid movement

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

The other half of Layer 5. The blitter half — compiling the sprite pool from 14,000 cycles a
sprite to 5,814, and then giving it four 1 px shifts across two sideways banks — is in
[`layer-5-blitter.md`](layer-5-blitter.md) and is worth reading first if the question is about
cost rather than behaviour.

This is what the pool was built for: **the deck's droids, standing on its waypoints and walking
between them.** `src/droidtest.asm` and `TEST_DROIDS` are gone, and `src/droid.asm` is what
replaces them.

## What landed

| C64 | ours |
|---|---|
| `NextLevel` `$15E8` | `NewShipDroids` — the ship's 256-byte roster, generated |
| `InitDeckDroids` `$1664` | `DroidsInit` — this deck's table, placed on waypoints |
| `GetWaypoints` `$1700` / `FindWaypoint` `$170D` | `DrWaypoints` / `DrFindWaypoint` |
| `RunDroids` `$174B` | `DroidsUpdate` — the driver and its compaction loop |
| `dMd0_droid` `$18CA` | `DroidRun`, minus the firing |
| `MoveDroid` `$1987` | `DrMove` |
| `GetNewDir` `$1CAD` | `DrNewDir` |
| `AdvanceMapPos` `$1D0D` / `CheckDroidAdvance` `$1D30` | `DrAdvancePos` / `DrCheckAdvance` |
| `Regenerate` `$1D45` | `DrRegenerate` |
| `GetDroidCharPos` `$299A` | `DrCharPos` |
| `DroidNear` `$321E` / `FindFreeSprite` `$32A8` | `DrScreen` / `DrFindSlot` |
| SID `$D41B` | `DrRandom`, an 8-bit LFSR — **the one substitution** |

## The three things worth knowing before touching this file

**1. A droid's position IS its reference cell.** `drPosX`/`drPosY` are world pixels, and the map
cell it occupies is `(drPosX >> 3, drPosY >> 3)` with no offset applied. That is what lets
`DrFindWaypoint` compare straight against a waypoint's character coordinates, which is how the
original does it. The sprite is then drawn at `drPosX - PLY_REFX` (11) and
`drPosY - DR_REFY` (13), so a droid sits on the same part of its sprite as the player sits on his
— see the reference-cell note in `player.asm`. The C64 offsets by 12 for the same reason: the
cell over the digit block is the middle of the droid.

**2. Waypoints are tile centres, and that is a load-bearing coincidence.** A record is
(charX, charY, exit mask); the char coordinates are always ≡ 2 mod 4, so a waypoint's pixel
position is ≡ 16 mod 32 on both axes. `dMd0` uses that as a cheap pre-filter before it will
search at all:

```
(drPosXlo OR drPosYlo) AND $1F == $10
```

Every droid speed — 1, 2, 4, 8 — divides 16, so a droid walking a corridor cannot step over a
waypoint without landing exactly on it. Change a speed to something that does not divide 16 and
droids will walk past junctions for ever.

**3. Droids turn only at waypoints.** `DrCheckAdvance` probes the cell the droid stands on and
the two ahead of it (two cells is one pass at the top droid speed) and, on a wall, sets
`drState = 2` — a two-iteration *pause*, not a turn. The original has no reversing behaviour here
either; the waypoint masks are what keep droids in corridors, and a droid that walks into a wall
is a sign the mask or the cell lookup is wrong, not that the pause needs to be cleverer.

## Two bugs found on the way, both worth recording

### The cell was right only for the first 512 pixels of a deck

`DrCharPos` shifted the high byte of the position **once** and rotated the low byte the rest of
the way. That computes the cell modulo 512. A deck is 2,048 pixels across.

The symptom did not look like an arithmetic bug at all: **the whole deck froze except one droid.**
Every droid past x=512 was looking up someone else's map cell, so `DrFindWaypoint` never matched
(no new direction, speed stayed 0) and `DrCheckAdvance` found walls that were not there (`drState`
re-armed every pass). One droid near the map origin walked around normally, which made it look
like a waypoint-data problem rather than a shift.

The C64 holds the high byte in A across all three `LSR A : ROR ptr`, pairs at `GetDroidCharPos`.
It is written that way for exactly this reason, and ours is now too.

> The general lesson: a 16-bit → 8-bit shift that only touches the high byte once is *correct on
> small values*, which is precisely the range you test in first.

### The near test has to match the blitter's cull exactly, not approximately

The first `DrScreen` tested only the **high byte** of the screen Y, so anything from 0 to 255
scanlines below the view counted as on screen. Droids 200 px below the window claimed sprite
slots, `SprSetSlot` then culled them at its own limit of 99 so nothing was drawn — and the droids
that really were on screen found the pool full and hit the C64's `FindFreeSprite` failure path,
which **destroys the droid**. A deck quietly lost droids to an off-by-a-range.

So the near test is now `sy <= SPR_MAX_Y` and `sx <= SPR_MAX_UNIT*4 + 3`, which is the cull
condition and not an approximation of it. Anything that changes the cull has to change both.

## The C64 behaviours kept deliberately

- **No free sprite means the droid is destroyed**, not queued: `drs_nofree` zeroes its energy and
  calls `DrRemoveShip`, which takes it off the *ship*, not just the deck. That is `dMd0_droid`
  at `$18F1`. It fires less often here than on the C64 because our window is 320×120 against
  their 320×200.
- **Choosing a candidate direction that does not exist.** `DrNewDir` takes the first three set
  bits of the exit mask and zeroes any candidate slot left over, then picks one of the three at
  random. Picking an empty slot gives speed (0,0), which sets `drState = 8` — the droid stands
  still for eight iterations and asks again. That is not a bug being reproduced; it is most of
  what makes droids look like they are deciding something.
- **The table is indexed 1–13 with entry 0 a sentinel**, so `DroidsUpdate`'s "deck cleared" test
  is `count == 1`. Keeping it means the compaction loop ports across unchanged.
- **`DroidsInit` walks one waypoint per table index**, occupied or not, so droid 13 gets waypoint
  1 and droid 1 gets waypoint 13. At most twelve are ever placed, so the walk wants waypoints
  1–13 at worst; checked deck by deck against `deckDroids` and `wpCount` before relying on it,
  and the tightest is deck 2 — 5 waypoints against 3 droids, reaching waypoint 4.

## The random source

The C64 reads SID register `$D41B` — oscillator 3's free-running noise output — in `NextLevel`
and again in `GetNewDir`. There is no equivalent on this machine, so `DrRandom` is an 8-bit
maximal LFSR (`x^8 + x^4 + x^3 + x^2 + 1`). It never returns 0, which matters nowhere: both
callers mask it to 2 or 4 bits.

This is the only substitution in the file. Everything else is the listing's own arithmetic,
including the roster generator's odd two-halves rule — indices 12–6 get `base + rnd AND 3`, and
indices 5–1 get a random type found by *halving* a 4-bit random until it drops below `base + 3`,
which is what makes the tail of a deck's complement weaker and bottom-weighted.

## The player now spawns on waypoint 0 — `BUGS.md` #4 closed

`CentreOnDeck` framed a deck from the centroid of its non-empty tiles and dropped the player at a
fixed offset from that, never asking whether the cell underneath was walkable. On decks 5 and 14
it was not, and the player could not move at all.

**Waypoint 0 is never used by `InitDeckDroids`, which starts placing at waypoint 1**, and
`tools/export_droids.py` has said for two layers that it is there to be the player's spawn point.
Waypoints are walkable by construction — droids patrol between them — so this replaces the guess
with a fact. `SetPosFromWaypoint` in `player.asm` works backwards from the reference cell:

```
plyX = cellX * 8 - PLY_REFX      ->  (plyX + 11) >> 3 == cellX
posY = cellY * 8 - 56            ->  (posY + 63) >> 3 == cellY
```

56 rather than 63 because `LoadDeck` forces `line` to 0 and `RedrawAll` draws whole character
rows, so `posY` has to be a multiple of 8 at deck load; 63 − 56 = 7 keeps the reference row on
`cellY` because `cellY*8 + 7` is still inside that row's own eight scanlines. `posX` is clamped
and snapped to the 4-pixel CRTC grid and `plyX` is deliberately **not** adjusted to match — the
dead zone carries the difference, and the player's world position is the thing that has to stay
on the waypoint.

`CentreOnDeck` and its subtraction `divide` are deleted rather than left as a fallback: nothing
called them, and the project's rule is that everything in `src/` is live.

**Verified offline over the whole game, which is stronger than sampling decks in the emulator.**
`tools/rip_levels.py`'s RLE decoder reproduces the port's tile map byte-for-byte (deck 1, 0 of
1024 differing), so the same decode can answer the question for every deck at once:

| | |
|---|---|
| Waypoint 0 in a wall, all 16 decks | **0** |
| Any of the 239 waypoints in a wall | **0** |

and in the emulator, on the two decks the defect named: deck 5 walks 233 px to the right from its
spawn, deck 14 walks 364 px down. Both were completely stuck before.

## What it costs

`DroidsUpdate`, User VIA T1 bracket, **128 passes averaged**, deck 1, 11 droids alive with one or
two of them on screen, player stationary:

| | cycles a pass |
|---|---|
| `DroidsUpdate`, 11 droids | **15,576** |
| | 19.5% of the 79,872 in a pass, ~1,400 a droid |

That is in line with the ~14,000 `PLAN.md` records for the C64's own `RunDroids`, which is the
number this was budgeted against. The pass had about 39,000 cycles spare after the blitter work;
it now has about 24,000.

Where it goes, per droid: three `MapChar` probes (~270), `DrFindWaypoint` walking up to 24 records
when the droid is on a tile centre, `DrCharPos`, `DrScreen`, and `DrMove`. Nothing here has been
optimised and nothing needs to be yet — but if it ever does, the first move is that
`DrFindWaypoint` is called only on tile centres and could be skipped entirely for a droid whose
position has not crossed one.

> **Measure with the T1 harness the way `layer-5-blitter.md` says**: one call site at a time,
> average over ~128 passes, and zero `dbgAcc`/`dbgN` immediately before the counted run. The
> accumulator is 24-bit but `dbgN` is a byte, so a run longer than 256 passes reports a per-pass
> figure that is silently wrong rather than obviously wrong.

## Verification

| | |
|---|---|
| Restore vs `RedrawAll`, droids walking, `line == 0` | **0 of 10240** |
| Restore vs `RedrawAll`, after a full-speed diagonal scroll, `line == 1` | **0 of 10240** |
| 11 droids after 20 s of play | all 11 moved; none standing on a solid cell |
| Waypoints, all decks, offline | 0 of 239 in a wall |
| Decks 5 and 14 | player moves freely from the spawn |

The oracle procedure is the one in `PLAN.md`: poke the `JSR SprDrawAll` in the main loop to three
`NOP`s so the pool only restores, let it settle, dump `&5800`–`&7FFF`, force a `RedrawAll` with
SPACE, dump again, compare. Droids moving during the comparison is fine and is the point — the
restore has to put back exactly what the draw took, wherever the droid has since walked to.

## Still open here — all since landed

- **Droids walk through each other and through the player.** Collision is Layer 6 — landed, see
  [`layer-6-droids-live.md`](layer-6-droids-live.md).
- **No line of sight and no firing.** Line of sight landed with Layer 6, firing with Layer 7
  ([`layer-7-combat.md`](layer-7-combat.md)).
- **`sprType` is set every pass** rather than only when it changes, because a 999 blowing into a
  001 changes type mid-life. Cheap; noted so it does not look like an oversight.
