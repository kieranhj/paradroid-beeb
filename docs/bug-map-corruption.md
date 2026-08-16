# The level gets scribbled on when a droid's shot kills you

**Status: cause found and fixed, 2026-08-16. KC confirms the corruption is gone in play.**

The title is the wrong hypothesis, kept because `BUGS.md` #10 and several commits refer to it. The
**tile map was never being written**. The thing being written is **sideways RAM bank 4**, and the
route to it is the player's respawn.

---

## 1. What the evidence actually said

Three sessions, in order:

1. Deck 8, first interaction with a droid that fires: laser sprite stuck on screen, level goes
   wrong, "including its collision data". Cleared by a deck hop away and back.
2. Deck 8 again, with `DEBUG_MAPGUARD` on. Corruption reproduced. **`hit` stayed `00`.**
3. After a corruption, hopped to deck 7: **the corruption came with it**, and individual tile
   characters had become 4×4 blocks of red vertical lines. A second run corrupted the tile
   characters the instant the player was hit by a laser.

Reading 2 rules out the tile map at `&3800-&3BFF` — the guard is verified to fire on a single poked
byte and it did not fire. Reading 3 rules out the play buffer and the charset at `&0400` as the
*origin*, because both are rebuilt by a deck load and the fault survived one.

What is left is data that a deck load **re-reads rather than rebuilds**: the contents of bank 4.
Its layout, from `&8000` up, is `chardata`, `colours`, `tiledefs`, `levels`, `droidgame`. The two
symptoms are the first and third of those, in address order — corrupted character definitions
(red vertical lines inside otherwise normal tiles) and a corrupted tile layout.

## 2. The cause

`CbCheckDeath` in `src/combat.asm` respawns the player:

```
  JSR DrSpawnPoint
  JSR SetPosFromWaypoint
```

`SetPosFromWaypoint` ends in `SetMapFromPos`, which computes `mapHX` from `posX` and **assigns it**.
Nothing updates `scrollS`. The incremental scroll never has to think about this because it moves
both by the same `sDelta`; a teleport has no delta.

`COPYCHAR` in `src/scroll.asm` writes a character's two halves as one 16-byte run to consecutive
buffer bytes. Its header states the one condition and derives it:

```
    scrollS/8 == mapHX   (mod 2)
```

When that holds, the strip's 10K wrap always falls on a character boundary. When it does not, the
wrap falls *between* the halves and the second half is written **8 bytes past `&8000`**, into
whatever sideways bank is paged in. The level draw runs at the resting state, which is
`SWRAM_DATA` — bank 4.

A respawn flips the parity whenever waypoint 0's `mapHX` parity differs from the parity the view
happens to be at. That is the intermittency — and it is not a coin toss: `mapHX` was observed even
at every point sampled on deck 1, so the flip looks to be a property of the DECK's waypoint 0, which
would explain why the reports are all from deck 8. Not established for every deck.

`LoadDeck` is where the invariant was established, and it was the only place, precisely because
until Layer 7f nothing else could move the player without moving the view.

### The other two symptoms are the same omission

`CbCheckDeath` also skipped `RedrawAll` and the `sprSaved` clear. So after a respawn the buffer
still held the *old* view (the level "goes wrong"), and every sprite slot's saved background
belonged to that old view — which is the laser sprite that stays on screen: its restore paints
stale pixels back forever.

## 3. The fix

`LoadDeck`'s re-framing block is now a routine, `ReframeView`, in `src/main.asm`:

| | |
|---|---|
| `scrollS` | `(mapHX AND 1) * 8` — re-establishes the parity invariant |
| `scrollS+1`, `line`, `iline` | 0 |
| `bandDo`, `colCount` | 0 — the exposed edges belonged to the frame just discarded |
| `sprSaved[0..7]` | 0 — the saved backgrounds belong to the old view |
| | `SetCRTCStart`, then `RedrawAll` |

`LoadDeck` calls it (with its own `DoorInit` kept alongside, which is deck-specific and not part of
re-framing) and `CbCheckDeath` tail-calls it. **Any future teleport must go through it.** The two
routines that assign `mapHX` outright are `SetPosFromWaypoint` and `LiftPlace`, and both callers of
`LiftPlace` are inside `LoadDeck`.

## 4. Verification

- **In play, by KC**: the corruption no longer happens.
- **Still worth doing once**: several deaths on **deck 8** specifically, which is where every report
  came from and therefore the deck whose waypoint 0 is most likely to be the odd-parity one. The
  cheap check afterwards is `(scrollS/8) AND 1 == mapHX AND 1`.

## 5. Superseded

The leading suspicion was that the eighth sprite save page (`&3700`, added by Layer 7c) had removed
the gap below the tile map, so a save-area overrun would now land on it. That remains structurally
true and the `ASSERT` stays, but it is not this bug — the map was never touched.

`DEBUG_MAPGUARD` is `MapGuardSnap` / `MapGuardCheck` at the end of `src/droid.asm`, with its
snapshot at `MG_COPY = &3C00` and its readout appended to the `DEBUG_ENERGY` line. It is verified in
both directions and worth keeping. Its readout format is documented in `src/main.asm` at the flag.

## 6. Other things still open on this branch

- **`BUGS.md` #9** — the leftmost 4-pixel column of the view is displaced one character row after
  horizontal scrolling. Reproducible, level-draw side, independent of this.
- **The lift/fire tiebreak was never exercised** — `L` firing is verified, but the branch where
  `LiftEnter` succeeds needs the player standing on a lift platform.
- **Deferred from 7f**: the disruptor, `EnemyFireEnemy`'s friendly fire, the enemy bullet's colour
  flicker, and the player's own explosion before he respawns.
- **Main RAM** — `code_end` is `&2EE4` against `SPR_SAVE` at `&3000`.
