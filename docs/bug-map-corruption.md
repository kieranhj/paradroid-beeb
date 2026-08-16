# The tile map gets scribbled on — handover

**Status: OPEN, not reproduced on demand. An instrument is built and verified; it needs a play
session to fire.** This document is self-contained: it is what a fresh session should read first,
and what KC needs to run the experiment.

`BUGS.md` #10 is the short entry; this is the working detail.

---

## 1. The symptom

From play, on **deck 8**, on the first interaction with a droid that fires:

- the **laser sprite is left on screen**, and
- **the level goes wrong, including its collision data** — so the tile map at `&3800-&3BFF` is being
  written, not merely stray pixels in the play buffer at `&5800`.

It **survives until the deck is reloaded**. The debug deck hop away and back clears it, and it comes
back on meeting the firing droid again.

The deck was identified by peeking `&8B`, which is the `deck` variable.

---

## 2. Run the experiment

```powershell
.\build.ps1 -Run          # assembles and launches b-em
```

`DEBUG_MAPGUARD` is **on by default** in `src/main.asm` while this is open, so nothing needs
switching on.

**Get to deck 8 and meet a firing droid.** Cursor up/down is the debug deck hop, so seven presses of
cursor-down from the start gets there. Then play until the corruption appears — the visual tell is
the laser sprite stuck on screen and the level going wrong around it.

**Then read the last five hex pairs off the second panel row** (the debug line) and write them down.

### Reading the debug line

The second row of the panel is `DEBUG_ENERGY`, and `DEBUG_MAPGUARD` appends five bytes to it. The
whole line, in hex pairs, is:

```
  TT EE MM WW AA SSSSSSSS HH QQOO GGWW
   |  |  |  |  |     |     |  | |  | |
   |  |  |  |  |     |     |  | |  | +-- want:    what the deck load put there
   |  |  |  |  |     |     |  | |  +---- got:     what the map holds NOW
   |  |  |  |  |     |     |  | +------- offset:  0-255 within that quarter
   |  |  |  |  |     |     |  +--------- quarter: 0-3, which 256 bytes of the map
   |  |  |  |  |     |     +------------ hit:     00 clean, 01 the map has changed
   |  |  |  |  |     +------------------ score, 4 bytes BCD
   |  |  |  |  +------------------------ alert level
   |  |  |  +--------------------------- weapon type
   |  |  +------------------------------ maxEnergy
   |  +--------------------------------- energy
   +------------------------------------ the droid type you are riding
```

`hit` latches at `01` and checking then **stops**, so the reading is where the corruption *began*,
not wherever it has spread to by the time you look. It resets on the next deck load.

The corrupted byte is `tilemap + quarter*256 + offset`, and the tile map is 64 columns × 16 rows,
so:

```
  index  = quarter*256 + offset
  map row    = index DIV 64
  map column = index MOD 64
```

### What to bring back

1. The five numbers: **hit, quarter, offset, got, want**.
2. Which **deck** it happened on (`&8B`).
3. Whether the stuck laser sprite appeared at the same moment.
4. Roughly what you were doing — standing still, moving, firing, being fired at.

If `hit` never reaches `01` but the level still visibly corrupts, that is **also** a result and an
important one: it would mean the play buffer is being corrupted while the map is intact, and the
collision-data impression came from somewhere else.

---

## 3. What is already known

### Not reproduced

Two attempts in jsbeeb, both on deck 8 with droids firing and the player taking damage:

| | |
|---|---|
| ~12 s of play, then the buffer oracle against `RedrawAll` | **0 of 10240** |
| ~12 s more, tile map dumped before and after | **0 of 1024 changed** |

### Ruled out

- **The tranche split.** `sprSplit` was 1 throughout a run that came out clean, so the
  split-pool draw order is not obviously implicated.
- **`BUGS.md` #9**, the incremental column draw, which is a separate reproducible defect and does
  not touch the map.

### The leading suspicion — adjacency

**The sprite save areas now end exactly where the map begins.**

| | |
|---|---|
| Before Layer 7c | save areas `&3000-&36FF` (7 slots), **`&3700` free**, map at `&3800` |
| Now | save areas `&3000-&37FF` (8 slots — the eighth is the player's bullet), map at `&3800` |

So **any save-area overrun that used to land in a free page now lands on the map**, which is exactly
the reported symptom. `ASSERT tilemap >= SPR_SAVE + SPR_SLOTS * 256` still passes but is now exact
rather than slack.

The bound that should make an overrun impossible is
`3 * SPR_BLOCK + (SPR_W-1) * UNIT_BYTES + 7 = 223 < 256`. The Layer 7c effect path was checked
against it **by hand, not measured**: `efRow0 + efHgt <= 21` holds for all 31 frames, so an effect
walks no more scanlines than a droid, and its Y offsets reach the same 48.

### How the numbers will discriminate

- **`got` looks like sprite pixels** — `&0F`, `&F0`, `&FF`, `&11`, `&EE` and similar — and the index
  is low, in the first page or two (`&3800-&39FF`): consistent with a **save-area overrun from slot
  7**, whose page is `&3700-&37FF`. That confirms adjacency.
- **`got` is a plausible tile index (0-31)**: something is writing *map-shaped* data to the wrong
  place — look at `BuildLevel` and anything indexing the map.
- **The index is high or scattered**: a different writer entirely. Suspects then are `DoorCopyDef` /
  `DoorMoveDef`, or an indexed store with a bad index.

---

## 4. Candidate fixes, once it is confirmed

**Do not apply these before the numbers come back** — the point of the guard is to avoid another
guess.

1. **Put the gap back.** Move the tile map to `&3C00` (`&3C00-&47FF` is free) so there is a 1K dead
   zone between the save areas and the map. Cheap, but **masks** rather than fixes an overrun, so
   only after the cause is understood. Note `MG_COPY` currently uses `&3C00` and would have to move.
2. **Confirm by bisection.** Temporarily set `SPR_SLOTS = 7` and disable the player's bullet. If the
   corruption stops, the eighth slot is implicated directly.
3. **Fix the overrun itself**, if that is what it is — most likely in `SprEfDraw` / `SprEfRestore`'s
   `svp` walk in `src/sprite.asm`.

---

## 5. Where things are

| | |
|---|---|
| Branch | `layer7-combat`, 8 commits, **not merged** to `main` |
| The guard | `MapGuardSnap` / `MapGuardCheck` at the end of `src/droid.asm`, under `IF DEBUG_MAPGUARD` |
| Its flag | `DEBUG_MAPGUARD` in `src/main.asm`, with a header explaining the readout |
| Snapshot buffer | `MG_COPY = &3C00`, 1K |
| Readout | `dbgEnSrcLo/Hi/Gap` in `src/rupture.asm`, `DBG_EN_N = 14` |
| Effect blitter | `SprEfSetup`…`SprEfRestore` in `src/sprite.asm` |
| Save areas | `SPR_SAVE = &3000`, `SPR_SLOTS = 8`, so `&3000-&37FF` |
| Tile map | `ORG &3800` in `src/main.asm`, 64 × 16 |

**The snapshot must be the LAST thing `LoadDeck` does.** The first version of this guard sat in
unreachable code after a `JMP` and silently never ran; moved to just before `ld_spawn` it captured
boot-staging garbage and fired immediately. It is now after `DroidsInit`.

### The guard is verified in both directions

- **No false positive** over a clean boot and a settled deck.
- **Fires correctly**: poking one map byte at `tilemap+300` reported quarter 1, offset 44, got `FF`,
  want `00` — exactly the byte poked.

---

## 6. Other things left open on this branch

Not related to this bug, but a fresh session should know about them:

- **`BUGS.md` #9** — the leftmost 4-pixel column of the view is displaced one character row after
  horizontal scrolling. Reproducible, level-draw side, independent of Layer 7. Not yet checked
  against a pre-Layer-7 build.
- **The lift/fire tiebreak was never exercised** — `L` firing is verified, but the branch where
  `LiftEnter` succeeds needs the player standing on a lift platform, which no test session did.
- **Deferred from 7f**: the disruptor, `EnemyFireEnemy`'s friendly fire, the enemy bullet's colour
  flicker, and the player's own explosion before he respawns.
- **Main RAM is at ~315 bytes free.** It is the binding constraint; Layer 7 put its bulk in bank 4
  for that reason.
