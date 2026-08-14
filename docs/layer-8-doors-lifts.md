# Layer 8 — doors and lifts

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

**8a (doors) is built and verified. 8b (lifts) is still a plan.** Everything about the C64 original
below was read out of `paradroid_ce_annotated.asm` and checked against `src/data/tiledefs.asm`.

## Why this comes next, ahead of the droid logic

The ship is sixteen decks and the player is currently sealed into whichever room `CentreOnDeck`
drops them in. Deck changes exist only as a debug shortcut on the cursor keys, which teleports
without a lift and lands wherever `CentreOnDeck` decides — sometimes inside a wall (see `BUGS.md`).

Droid AI, pathfinding and combat are all much harder to evaluate in one room. Waypoint logic in
particular is deck-scale behaviour: droids route between rooms *through doors*, and until doors
open there is nothing to route through. Building the droid layer first means building it against a
world it cannot move around in, and then rebuilding the tests once it can.

So: doors and lifts first, then droids.

**Recommendation: keep the existing layer numbers and reorder the work.** Layer 8 runs next, before
Layers 6 and 7. Renumbering would churn every commit message and document that already refers to
"Layer 5" or "Layer 7", for no gain — the numbers are labels, not a sequence anyone is obliged to
follow in order.

---

## What the original does

### Doors are bit 7 of the character code

This is the whole mechanism, and it lands very well on what the port already has.

`GetNearChar` (`$2A3E`) is the C64's version of our `ProbeGroup` inner body: it reads the character
at `plyMapPos + nearXoffset[X], nearYoffset[X]` and returns it, and the caller tests **bit 7 for
solid**. Our `MapChar` + `ProbeGroup` already do exactly this.

The one addition is four instructions:

```
2A57  CMP #$20        ; character $20 is a DOOR APPROACH PAD
2A59  BNE _2
2A5B  ...             ; MapPos = the probed cell
2A65  JSR OpenDoor
```

`OpenDoor` (`$2A6D`) then:

1. Tile-aligns the position (`AND #$FC` on both axes) — **a door is exactly one 4×4 tile**.
2. Searches `doorPosX`/`doorPosY` for that tile. Not found, and fewer than 7 doors tracked → register
   it, with an orientation taken from the column within the tile:
   `MapPos AND 3` of 0 or 3 → **vertical** (state `$40`); 1 or 2 → **horizontal** (state `$C0`).
3. Found → advance the animation. Each step clears bit 7 (`AND #$7F`) on **two** characters and
   increments `doorState`, which runs 0→4. Bit 7 both makes the cell passable *and* selects the
   open-door graphic, so one bit does both jobs.

`CloseDoors` (`$2B08`) reverses it with `ORA #$80`, one step per call, and compacts the door list as
entries reach state 0. **At most 7 doors are tracked at once**, which is the cap the port inherits
for free.

### The tile data confirms it

Three tiles carry the `$20` approach pad. Solid characters (bit 7 set) marked `*`:

```
tile 1 — VERTICAL door          tile 2 — HORIZONTAL door        tile 23 — LIFT
  3A  DB* CA* 39                  38  20  20  37                  B9* BA* BA* BD*
  20  DE* BC* 20                  C8* BB* BB* C9*                 EB* EC* EC* ED*
  20  DE* BC* 20                  D9* DD* DD* DA*                 EE* EF* EF* F0*
  37  DC* CB* 38                  39  20  20  3A                  39  20  20  3A
      ^^^^^^^^                        ^^^^^^^^
      the leaves                      the leaves
  pads at columns 0 and 3         pads at columns 1 and 2       pad at row 3, columns 1-2
  -> MapPos AND 3 = 0 or 3        -> MapPos AND 3 = 1 or 2
  -> vertical                     -> horizontal
```

The orientation test and the tile data agree exactly, which is a good sign the reading is right.

> **The tile catalogue in [`graphics.md`](graphics.md) contradicts this and is probably wrong.** It
> calls tiles 1–2 "outer wall corners / ends" and tile 23 "lift shaft (variant)". That catalogue was
> written from *looking at* the rendered tiles; the reading above comes from the character codes and
> from `OpenDoor`'s own orientation arithmetic, which is much stronger evidence. Settle it with
> `tools/compare_tile.py` when Layer 8 starts, and correct whichever is wrong — but do not plan
> around the catalogue.

### Lifts are a table lookup and a modal screen

Six tables, none of them currently exported:

| Table | Address | Size | Contents |
|---|---|---|---|
| `liftPosX` | `$6D07` | 24+ | Absolute X of each lift stop |
| `liftPosY` | `$6D26` | 24+ | Absolute Y of each lift stop |
| `liftPosDeck` | `$6CC8` | 31 | Which deck each stop is on |
| `liftIdx2Shaft` | `$6CE7` | 32 | Which shaft each stop belongs to |
| `liftShaftX/Y` | `$6CB0`/`$6CB8` | 8 each | Shaft position in the side view |
| `liftShaftHeight` | `$6CC0` | 8 | Shaft height in the side view |

`FindLift` (`$272F`) scans all 32 stops for one whose **tile-aligned** position matches the player's
and whose deck is the current one. Carry set = not on a lift.

`DoLift` (`$267A`) is **modal**: it saves the VIC state, switches to hires, draws the ship side view,
and loops on the joystick — up/down call `ChangeDeck`, fire exits. `ChangeDeck` (`$2705`) steps
`liftPos`, refuses to leave the current shaft (`liftIdx2Shaft` must match `liftNum`), reads the new
deck from `liftPosDeck`, and calls `BuildLevel`.

On exit the player is placed at the destination stop: `liftPosX/Y × 8`, **preserving the low 5 bits
of the old position** so sub-tile alignment survives the trip.

---

## The one real design problem

**The C64 mutates a character map. We do not have one.**

`OpenDoor` writes `AND #$7F` into the expanded 256×64 character map at `$8000`. Layer 2 deliberately
did not build that map — the port keeps the 64×16 tile map (1 K) and expands tiles to characters at
draw time, which is worth 15 K and is not a decision worth reversing for doors.

So there is nowhere to write the modified character code, and every character read in the port comes
from `tiledefs` via `tdp`. Options considered:

| | |
|---|---|
| Build the 16 K character map after all | Gives up Layer 2's saving and does not fit below `&3000`. No |
| Patch the shared tile definition | Every door of that type on the deck opens at once. No |
| Consult a door list per character drawn | 40 characters a band pass, ~7 passes in 8. Too hot |
| **Patch a private copy of the tile definition, per open door** | **Recommended** |

### Why the private-copy scheme fits

A door is exactly one tile, and the draw already selects a tile definition **per tile, not per
character**:

```
.dbr_tile
  LDY dbTile
  LDA (maprow),Y          \ tile number
  TAX
  LDA tdpLo,X : ADC subRowOfs : STA tdp
  LDA tdpHi,X : STA tdp+1
```

Pointing `tdp` at a patched 16-byte copy instead costs **nothing per character** — only the choice
of pointer, once per tile. Eleven tiles a band pass, not forty characters.

- **Storage:** 16 bytes per open door × 7 = 112 bytes. There is 1.4 K free below `&3000`.
- **The test:** "does tile (col,row) hold an open door?" A per-deck 128-byte bitmap (64×16 bits)
  built at `LoadDeck` answers the common case in one `AND`; only actual door tiles then scan the
  ≤7-entry list. Doors are sparse — a handful per deck.
- **`MapChar` uses the same substitution**, so the wall probes and the draw cannot disagree. That is
  the correctness-critical path and it runs 12 times a pass, so it can afford the full scan.

### The new drawing primitive

The port only ever draws the leading edge of a scroll. A door that animates while stationary changes
cells that are already on screen and nothing would redraw them. Layer 8 needs **`DrawTileCells`** —
redraw one tile's 4×4 characters into the play buffer at its current scroll position, or skip if it
is off screen. That is `DrawColumn`'s inner work with both axes bounded; the addressing is already
solved by `SetCell`.

**It must run inside the existing draw window**, in `DoRedraws`, after `SprRestoreAll` and before
`SprDrawAll`. Writing into the buffer at any other point stamps pixels into a sprite's saved
background — the same hazard the *Why not round-robin* section of
[`layer-5-blitter.md`](layer-5-blitter.md) describes, and it is permanent rather than transient.

---

## Work breakdown

### 8a — doors ✅ DONE

Landed as `src/door.asm` with hooks in `player.asm`, `screen.asm` and `scroll.asm`. The
private-copy scheme worked as designed and needed no revision — but two things about it were
wrong in the first build, and one assumption about the port did not survive contact.

#### Probing had to move out of ProbeGroup entirely

The plan said "hook the probe" and that was too glib. `ProbeGroup` cannot host the door test, for
two independent reasons that only show up together:

- It runs **only when there is speed on that axis**, and the moment a closed door blocks the player
  `CheckWalls` zeroes that speed. The next pass probes nothing at all.
- It **abandons the group at the first solid cell**, because one solid cell is all "am I blocked?"
  needs. The approach pad is usually probed *after* a solid cell of the same door tile.

Together those make the door open one step, close one step, and never open — observed exactly that
way. `CheckPlyAdvance` ($29C1) has neither property: it calls `GetNearChar` on all twelve cells
unconditionally and only afterwards asks whether the speed is into the wall. So doors get their own
`DoorScan` over the full diamond, called from `CheckWalls` before any blocking test. Twelve
`MapChar`s is about 1,100 cycles of the ~39,000 spare.

> Worth generalising: the blocking probe and the *sensing* probe want different sweeps, and merging
> them looks like an obvious saving right up to the point where it silently does not work.

#### Two bugs, one of which crashed the machine into BASIC

**`DoorMoveDef` walked its 16-byte copy downwards from `slot*16`** instead of `slot*16 + 15`, so
slot 0 immediately underflowed to index 255 and wrote sixteen bytes over whatever followed
`doorDef` — which is code.

**Both close arms use Y as an index into `doorDef`, destroying the compaction destination index.**
That is the root cause and it made the first bug reachable: `du_keep` then compared X against a
tile-definition offset, copied entries to a wild slot, and stored that offset as `numDoors`.
`CloseDoors` saves Y across exactly these two arms, into `xfer_cpuSpriteX` — those otherwise
baffling stores are the whole point, and skipping them cost an afternoon.

> **Read the original's register saves as load-bearing until proven otherwise.** Both of these were
> visible in the listing and both were dropped as noise while porting.

#### Verified

Play buffer diffed byte-for-byte against `RedrawAll`, with `JSR SprDrawAll` poked to NOPs:

| | result |
|---|---|
| door fully open, stationary | **0 differences in 10240** |
| door closed again, after a vertical scroll | **0 differences in 10240** |

That is the check that matters: `RedrawAll` reaches the tile definitions through `MapChar` and the
band and column paths reach them through `DoorTdp`, so agreeing byte-for-byte proves all three
substitutions are consistent. Also confirmed by walking: the player opens a door, passes through,
and the door closes behind — over two different doors on deck 1, with the list compacting between
them.

**Not yet measured:** the per-pass cost. `LDA numDoors : BEQ` is four cycles a tile with nothing
open, and `DoorScan` is unconditional, but neither has been put under the T1 bracket.

1. **Export the door data.** Nothing new is needed from the listing: doors are found by scanning the
   tile map for tiles containing `$20`. Build the per-deck door list and the tile bitmap in
   `LoadDeck`.
2. **Door state.** `doorTile[7]` (position), `doorState[7]`, `numDoors`, plus the 7 × 16-byte patch
   buffers. Port `OpenDoor`'s registration and orientation test verbatim — the `MapPos AND 3` rule
   is confirmed by the tile data above.
3. **Hook the probe.** Add the `CMP #$20` test to `ProbeGroup`, so walking at a door opens it.
   `CheckWalls` already reads bit 7 and needs no change.
4. **Patched-tile lookup** in `DrawBandRows`, `DrawColumn` and `MapChar`.
5. **`DrawTileCells`**, called from `DoRedraws` for any door whose state changed this pass.
6. **`CloseDoors`** once a pass, one animation step, with the list compaction.

**Verify:** the play-buffer oracle still works — diff against `RedrawAll` with a door half open, at
odd and even `mapHX` and non-zero `line`. A door mid-animation is a new class of buffer state and is
exactly where a patched-tile bug would show. Also scroll a door off screen and back while open.

### 8b — lifts

1. **Export the six lift tables** into `levels.asm`. `export_bbc.py` already ships the `$F120`
   deck metadata; this is the same shape of change.
2. **`FindLift`** — tile-align the player position, scan 32 stops, match on deck.
3. **Lift mode.** The C64's is modal and draws the ship side view, which is Layer 9's artwork.
   Propose a **minimal lift for now**: entering it takes over the cursor keys, up/down step through
   the stops *in the same shaft*, fire commits. The existing debug deck-change keys are exactly this
   minus the constraint, so this mostly means routing them through `liftPosDeck` instead of
   `deck ± 1`. The side view drops in later without changing the mechanic.
4. **Arrival.** Set `posX`/`posY`/`plyX` from `liftPosX/Y × 8`, preserving the low 5 bits as the
   original does, then `LoadDeck`. This also **retires `CentreOnDeck` as the arrival path** and with
   it the "player spawns in a wall on some decks" defect in `BUGS.md`.

**Verify:** ride every shaft end to end and confirm the player arrives on a walkable cell on all 16
decks. That is a check worth scripting through the jsbeeb MCP rather than doing by hand.

---

## Risks and open questions

- ~~**Does anything else write `$20`?**~~ **Closed.** A `$20` in open floor would register spurious
  doors and corrupt the map, so this looked like the scheme's main risk. It is not: **only tiles 1,
  2 and 23 contain `$20` anywhere in their 16 characters**, and a deck map is built *only* from
  tiles, so `$20` cannot appear anywhere those three are not placed. The tile data closes it without
  needing to decode a single deck.
- **7 doors is the C64's cap, and it compacts the list when doors close.** If a player can get 8
  doors open at once the eighth silently does not open. Faithful, but worth a note if it ever looks
  like a bug.
- **Door cells under a sprite.** `DrawTileCells` runs before `SprDrawAll`, so a sprite standing in a
  doorway gets redrawn over the new background — correct. But its *saved* background is captured
  after, which is also correct. Worth one explicit test with a droid parked in a door.
- **Lift arrival mid-animation.** `LoadDeck` resets `sprSaved` for every slot; door state must be
  reset too, or a door left open on the old deck patches a tile on the new one.
- **Sound.** `ChangeDeck` and `DoLift` set `SndFx2`/`sndFx1`. No sound driver until Layer 11; leave
  the writes out rather than stubbing them.

## What it unblocks

The whole ship becomes traversable, which is the precondition for evaluating droid movement at deck
scale — waypoints, `GetNewDir` and `CheckDroidAdvance` all assume a droid can leave the room. It
also gives Layer 9 a working lift to hang the side view on, and retires the `CentreOnDeck` spawn
defect.

> **Noticed while researching this:** `tools/export_bbc.py` stamps
> `Source: paradroid_ce.lst (Paradroid Redux, C64)` into every file it generates. That attribution
> is wrong — see [`decisions.md`](decisions.md) — and `export_droids.py` already says
> "original/CE lineage". Worth fixing when `export_bbc.py` is next touched for the lift tables.
