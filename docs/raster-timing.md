# Where the main loop sits against the raster

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

Written 2026-08-15, after KC reported that flicker and edge tearing got worse once Layer 6's droid
AI went in. It is the timing picture the flicker work needs: what the frame looks like, what each
phase of the loop writes and when, and what the budget actually allows.

**It corrects a number in [`layer-5-blitter.md`](layer-5-blitter.md).** That document said the
off-display window was 184 scanlines and 11,776 cycles, and concluded that no rescheduling of the
existing work could fit inside it. **Both halves were wrong.** A BBC scanline is 64 µs, which is
**128 CPU cycles at 2 MHz, not 64**, and the window is 192 scanlines, not 184. The window is
**24,576 cycles**, and there are **two of them per pass**. The work fits. It is in the wrong places.

## The frame

From the rupture block in `main.asm`. P is the start of the panel cycle; a scanline is 128 cycles.

```
  P          panel cycle   7 rows, 5 displayed        P .. P+40
  P+44       fire 1        panel regs, blank, park the play cycle's R12/R13
  P+64       fire 2        unblank — the play area's visible TOP edge
             ...           the play area is on screen, 120 scanlines
  P+184      fire 3        blank — visible BOTTOM edge; sets drawFlag, ruptState = 3
  P+208      tail cycle    13 rows, none displayed; VSync at P+248 (row TAIL_R7)
  P+312      next P
```

| | scanlines | cycles |
|---|---:|---:|
| one scanline | 1 | **128** |
| one field | 312 | 39,936 |
| **one pass** (`FRAME_LOCK` = 2 fields) | 624 | **79,872** |
| play area **displayed** | 120 | 15,360 |
| play area **off display** — the window | 192 | **24,576** |
| windows per pass | | **2 — 49,152 cycles** |
| window open → the CRTC start is latched at the next fire 1 | 172 | **22,016** |

Two deadlines fall out of that, and they are different:

- **The scroll's content deadline is 22,016 cycles**, not 24,576. `SetCRTCStart` only *parks*
  R12/R13; fire 1 of the next frame latches them. Anything the scroll newly exposes has to be drawn
  before that latch, or the CRTC shows a column the level draw has not written yet.
- **A sprite must not be erased-and-not-yet-redrawn while the beam is over its rows.** The
  sufficient condition, and the one worth designing to, is that a sprite's restore and its draw
  happen **inside the same window**.

## What each phase writes, in loop order

Only three phases touch the play buffer. That is the single most useful fact here.

| # | phase | writes the buffer? | cost, measured |
|---|---|---|---|
| 1 | `WaitVSync` | — | idles to the field boundary |
| 2 | **`SprRestoreAll`** | **yes — erases all 7 sprites** | 12,313 |
| 3 | `ReadKeys`/`CalcSpeed`/`CheckWalls`/`ApplyMove` | no | ~1,500 |
| 4 | **`DroidsUpdate`** | no | **16,967** |
| 5 | `SetCRTCStart` | no — parks R12/R13 for fire 1 | ~100 |
| 6 | **`DoRedraws`** | **yes — the newly exposed edge, and door tiles** | 0 … 19,172 |
| 7 | lift / deck keys, SPACE | rarely | ~200 |
| 8 | `SprAnimateAll` | no | ~200 |
| 9 | **`SprDrawAll`** | **yes — saves background, then draws all 7** | 23,961 |

`CheckWalls` also runs `DoorScan`, and `DroidsUpdate` can register a door — but the door *tiles*
are only repainted inside `DoRedraws`, so the buffer writes stay in those three places.

**Buffer work per pass: 36,274 fixed plus 0–19,172 for the level draw.** Against 49,152 cycles of
window. It fits — with 30% spare in the worst case and nearly 40% typically.

## Where it actually lands — measured, not inferred

`ruptState` says which fire is expected next, so it says where the beam is: **`ruptState == 2`
means fire 2 has happened and fire 3 has not — the play area is on screen.** Four one-byte
histograms either side of two calls, 128 passes, scrolling on the full diagonal:

| | state 0 | state 1 | **state 2 — displaying** | state 3 — window |
|---|---:|---:|---:|---:|
| entering `SprRestoreAll` *(earlier run, stationary)* | 0 | 0 | **0** | 128 |
| entering `DoRedraws` | 4 | 8 | **116** | 0 |
| leaving `DoRedraws` | 3 | 1 | **124** | 0 |
| entering `SprDrawAll` | 3 | 1 | **120** | 4 |
| leaving `SprDrawAll` | 0 | 0 | **75** | 53 |

So **the restore is the only buffer phase inside the window.** The level draw runs with the beam
over the play area on 116–124 passes of 128, and the sprite draw on 120 of 128, finishing during
the display more often than not.

That is both symptoms in one table:

- **Edge tearing** — `DoRedraws` writes the newly exposed column or row *after* fire 1 has already
  latched the new scroll position and *while* the beam is displaying it.
- **Sprite flicker** — the restore erases every sprite at the top of the pass and the draw does not
  finish for another ~40,000 cycles. That gap is longer than a whole field (39,936), so **a display
  period always falls inside it**. Each sprite is therefore missing, or half-drawn, for one field
  in every two: a 25 Hz blink on every droid.

## Why Layer 6 made it worse

The arithmetic is direct. From the window opening at fire 3, the work ahead of `DoRedraws` is:

```
  SprRestoreAll        12,313
  keys + movement       ~1,500
  DroidsUpdate         16,967      <- Layer 5/6
                       ------
                       30,780 cycles, against a 22,016-cycle latch deadline
```

Before the droids existed that sum was about 13,800 and the level draw comfortably beat the latch.
**`DroidsUpdate` is what pushed it past**, and it pushed `SprDrawAll` a further 17,000 cycles later
with it. Nothing about the drawing changed; it simply got shifted into the display.

## What to do about it

The shape of the fix follows from the table above: **the AI and the movement code write nothing to
the play buffer, so they belong in the display period, and the three phases that do write belong in
the two windows.**

### Step 1 — get the level draw back inside a window — **DONE 2026-08-15**

Move `ReadKeys`/`CalcSpeed`/`CheckWalls`/`ApplyMove`/`DroidsUpdate` to *after* the sprite draw, so
they run during the display and compute the state the **next** pass will use. That is a one-pass
pipeline: the droids' positions become one pass stale relative to the scroll, which at 25 Hz is not
visible, and it frees ~18,500 cycles at the front of the window.

Watch out: `ApplyMove` decides the scroll, and `SetCRTCStart`/`DoRedraws` depend on it, so the
*player's* half has to stay ahead of the level draw or be pipelined with it consistently. It is only
~1,500 cycles, so the cheap version is to pipeline the droid AI alone and leave the player where it
is.

**Done**, and it was one moved `JSR`. `DroidsUpdate` now runs after `SprDrawAll`; the player's own
movement stayed above the level draw because the scroll depends on it, and only the droid AI moved.
`droid.asm` went into bank 4 first, which is what made the room.

Measured the same way, 128 passes scrolling on the diagonal:

| | before | after |
|---|---:|---:|
| entering `DoRedraws` with the play area **on screen** | 116 of 128 | **0 of 128** |
| leaving `DoRedraws` on screen | 124 of 128 | **0 of 128** |
| entering `SprDrawAll` on screen | 120 of 128 | **0 of 128** |
| leaving `SprDrawAll` on screen | 75 of 128 | **35 of 128** |

So the level draw is now wholly inside the window — the edge tearing should be gone — and the sprite
draw both starts in the window and **finishes there on 93 passes of 128**. On those 93, the restore
and the draw are in the same window, which is exactly the condition for a sprite never to be
displayed erased: the flicker is gone on those passes and step 2 is about closing the other 35.

The frame lock is untouched: the histograms sum to exactly 128 over 10,223,616 cycles.

**What it costs is one pass of latency** on droid positions — the slots this writes are drawn by the
next pass. At 25 Hz and 1-8 px a pass it is not visible. Three properties make it safe, and they are
written out at the call site in `main.asm`: the restore replays the *draw's* addresses rather than
`sprUnit`, a slot freed after the draw still has `sprSaved` set so its background is put back, and a
door probed here is held open by the next pass's `DoorsUpdate`.

### Step 2 — put each sprite's erase and redraw in the same window — **BUILT 2026-08-15**

Per sprite, restore + draw is **5,814 cycles**, so a 24,576-cycle window holds **4.2 sprites**, and
two windows hold **8.4** — against a pool of 7. So the pool splits into two tranches, each restored
**and** drawn inside its own window:

```
  window A   SprRestoreA → DoRedraws → SprDrawA
  display    keys, movement, droid AI, animate     (no buffer writes)
  window B   SprRestoreB → SprDrawB
```

The loop **counts windows rather than consuming a flag**. The IRQ bumps `fieldCount` at fire 3 and
`WaitUntilField` spins until the counter reaches a target, returning at once if it is already past
it. A boolean coalesces — work running past two fire-3s sets the same flag twice, the loop consumes
one stale release and then blocks for the next, turning a small overrun into a whole extra field.
A counter cannot lose one. It also makes the pass's contract explicit: **not shorter than
FRAME_LOCK fields, and allowed to be longer**, so a heavy pass costs what it costs and the rate
recovers on the next one instead of stepping down to 16.7 Hz for as long as the load lasts. `SPR_SPLIT` = 3: slots 0-2 in the first window,
3-6 in the second, and the player is slot 0 so he is always in the first.

**The split is abandoned for a pass when either guard fails**, and both are in `SprSplitOK`:

1. **Anything else writing the buffer.** Split the pool and tranche B is still *on screen* while
   the level draw runs, so any band, column or door tile touching it corrupts its save permanently —
   `DoRedraws`' own comment says a door repaint "must happen between `SprRestoreAll` and
   `SprDrawAll` … or it stamps pixels into a sprite's saved background". So the split needs a pass
   with no band, no columns and no *moving* door. A door being **held open** is static: bit 6 is
   set by the probes in `CheckWalls`, which now run before the decision, and `DoorsUpdate` neither
   decrements it nor marks it dirty. Testing `numDoors` instead cost the split almost everywhere on
   deck 1, where four doors are typically registered.
2. **A sprite straddling the tranches.** Restore-all-then-draw-all holds within a tranche and not
   across the two, so an A sprite overlapping a B sprite gives up and draws the pool whole. The test
   is in units and deliberately loose — 7 wide plus 2 units of a pass's movement, 21 scanlines plus
   8 — because it has to cover where the other tranche was drawn *last* pass as well as this one.

The movement moved above the erase to make guard 1 answerable: it decides how much work `DoRedraws`
has. Nothing is lost by it, because the restore replays the addresses the *draw* recorded and does
not care where anything has moved to since.

**Verified**: the split path renders correctly, `sprSplit` goes to 1 when both guards pass, and with
all three draw sites disabled on a split pass the buffer is **0 of 10240** against a forced
`RedrawAll` — so the two-window restore puts back exactly what the two-window draw took.

> **The oracle needs all THREE draw call sites poked now**, not one: the `JSR SprDrawAll` and
> both `JSR SprDrawTr`s (the split path's two windows). Poking only the old one leaves the split
> path drawing and the diff is meaningless.

#### Tranches are overlap components, not slot ranges — **2026-08-15**

**Guard 2 fires more often than it should**, and it is the fixed slot range that causes it. A droid
walking alongside the player is slot 6 against the player's slot 0 — opposite tranches — so the
commonest situation on screen is exactly the one that refuses the split. Measured on deck 1 the
split was refused continuously until the droid was taken out of the pool by hand.

So the assignment stopped being a slot range. `SprAssignTr` labels each active slot with its own
index, merges labels across every overlapping pair, and hands whole components to whichever tranche
is emptier — slot 0 first and ties to A, so the player is always in the window drawn first. Seven
slots makes the naive algorithm free. **It never refuses on balance**, and an earlier version did — giving up when a tranche came out
bigger than the four a window holds. That was the wrong trade: an oversized tranche is doing
exactly what the whole pool does today, and the *other* tranche still gets a clean window, so an
unbalanced split is strictly better than none. The degenerate case falls out of the same rule — if
everything overlaps everything it is one component, it all goes to A with the player, tranche B is
empty, and the pass behaves as it did before any of this.

One more guard came with it: a slot that is no longer drawable but still holds a saved background
has to be restored at the position it was *drawn* at, and nothing in the assignment knows that
position — so a pass with one of those is drawn whole. It happens on the one pass a droid leaves the
window.

**Measured on deck 1 where the fixed split was refused continuously**: `sprSplit` is now 1 at the
spawn, and with a droid walking beside the player the two land in tranches A and B when they are
apart and in the same tranche when they overlap. The oracle on a split pass, all three draw sites
disabled: **0 of 10240**.

### Step 3 — only if the worst case still bites

The full-diagonal level draw is 19,172 and shares window A with tranche A (17,442 for three
sprites): 36,614 against 24,576. `DoRedraws` already separates its two halves —
`colCount` for columns and `bandDo` for the band row — so the column half can go to window B, and
the band row, which is the expensive one and only happens on a row crossing, keeps window A.

## How to check each step

The instrument is the one that produced the table above and it is worth keeping in a drawer:
four `SKIP 4` histograms and `LDX ruptState : INC dbgRsN,X` either side of the call in question,
about 20 bytes and no cycles worth counting. **Every buffer phase should end in state 3.** Read
them after 128 passes with the player scrolling; scrolling matters, because a stationary player
gives `DoRedraws` nothing to do and it lands anywhere.

Alongside it, the checks the droid layers already use: the buffer oracle at `line != 0` after a
diagonal scroll, and the frame-lock check that 128 passes take exactly 10,223,616 cycles.

> **Main RAM is the practical constraint on all of this: 116 bytes.** Splitting the pool and
> pipelining the AI both add code. `droid.asm` moving into bank 4 comes first — see `PLAN.md`.

---

# The 2026-08-20 pass: where it had drifted back to, and Phases 1 and 2

Reopened after KC reported the flicker back, "particularly the enemy droids", and suspected that
the collision work and the animated tiles had eaten the budget. Both halves of that were right.

## The instrument, since `DEBUG_TIME` stopped building

`DEBUG_TIME` is 154 bytes over the code image (`BUGS.md` #17), so everything below was measured
with a **zero-byte harness**: execute breakpoints on the `JSR` sites in `mainloop` — addresses out
of `build/PARADROID.lst` — and, at each stop, `read_registers` for `elapsed_cycles`. Two jsbeeb
quirks decide whether it works at all:

- **`cycles_run` is NOT the actual count when a breakpoint fires.** It returns the number
  *requested*. Use `elapsed_cycles` from `read_registers`; that one is exact.
- **A run that starts with PC already on a breakpoint returns immediately with `cycles_run` 0.** So
  the sweep is: read, *clear the breakpoint that just fired*, run. Set every site up front and walk
  them one per run.

Breakpoints do fire under `run_for_cycles` — the older note saying otherwise was wrong. Anchor the
timeline on the fire-3 handler (`INC fieldCount`), which is where a window opens.

## What the pass looked like before

Deck 1, standing still, **one sprite**, split taken, no level draw — the lightest pass the game can
have. Offsets from window A opening:

| offset | phase | cost |
|---:|---|---:|
| 0 | fire 3 — **window A opens** | |
| 70 → 6,898 | `DoScore`, `CbDisruptor`, keys, movement, fire | 6,828 |
| 6,898 → 16,958 | **`AnimTick`** | **10,060** |
| 16,958 → 20,484 | `SprSplitOK` + restore | 3,526 |
| 20,484 → 20,600 | `SetCRTCStart`; level draw skipped | 116 |
| 20,600 → 21,392 | three debug `keydown`s (OSBYTE) | 774 |
| 21,392 → **26,148** | `SprAnimateAll` + draw | 4,756 |
| **24,576** | **window closes — the draw is 1,572 cycles LATE** | |
| 26,148 → 37,870 | `DroidsUpdate` (11,786 with everything culled) + the rest | 11,722 |

Three things fall out of that, and they are the whole diagnosis:

1. **There is no headroom at all.** One sprite and no level draw already overruns the window. Each
   further sprite is +5,182 (1,759 restore + 3,423 draw), so four sprites finish ~13,000 cycles
   into the display. Enemy droids are drawn *after* the player in slot order, so they are the ones
   still missing when the beam arrives — exactly the reported symptom.
2. **16,888 cycles — 69% of the window — went on work that writes no pixels.**
3. **`AnimTick` cost 10,060 cycles and on that pass found nothing.** `AnimScan` walks 11 tile
   columns by 16 map rows, and it was doing it at the front of window A.

And the split — the only thing that prevents flicker — was refused on **every pass the player
moves**, because `colCount` was a global veto.

## Phase 1 — get the work that draws nothing out of the window

**`AnimScan` and `AnimLamp` moved below the draw**, into the play area's own display period, and
fill the list for the *next* pass. `AnimTick` keeps only `AnimRotate`, because that changes the
charset every draw reads. It is the same one-pass pipeline the droid AI took, and `AnimReset` had
to learn to empty the list, because the list now survives a pass.

**What the lamp costs** is that `BuildLampChar` rebuilds character `$16` after this pass's level
draw rather than before it, so a sign scrolling in on the pass the alert level changes shows the
old colour for one pass. 40 ms, once per change of state.

**`DoScore` and `CbDisruptor` moved to `ml_afterdraw`**, immediately above `ml_passend` — the one
point every arm of the pass converges on, the four modal ones included, which is what preserves the
C64's "runs whether the console is up or not" ordering.

A **cached** tile list keyed on the view's left tile column would take `AnimTick` to ~20 cycles
rather than ~1,500. It was built and then abandoned: ~60 bytes, and the low overlay had 15. Worth
returning to if `AnimScanPass`'s ~7,000 cycles of display time are ever wanted back.

## Phase 2 — let the split survive scrolling

**[DECISION, 2026-08-20] The global veto is replaced by a local test.** What the level draw writes
this pass is known before it runs, and every writer reduces to a one-dimensional span:

| writer | covers | test |
|---|---|---|
| the band | one display row, full width | scanlines only |
| the columns | 4-pixel columns, full height | units only |
| a door | one tile | units only |
| an animated tile | one tile | units only |

So instead of refusing the split, `SprAssignTr` **forces any overlap component holding a sprite
under one of those writes into tranche A** — the tranche that is already erased while the level
draw runs. Tranche B is then disjoint from everything the pass writes, by construction.

Both sprite spans are padded by eight, a pass's worth of scroll, because a tranche-B sprite's saved
background was taken last pass and has to be covered where it was drawn *then*. The tile tests
ignore rows. Every approximation errs towards forcing A, which costs a split and never costs
correctness.

The one global veto left is the **stale slot** — no longer drawable but still holding a saved
background — which is the single pass a droid leaves the window.

`DoRedraws` is **no longer skipped on a split pass**. It used to be, because a split pass was
*defined* as one with nothing to draw; skipping it after this change would stop the deck scrolling.

**Where the code went.** The decision grew past the eleven bytes the code image had left, so it
moved to **bank 6** as `src/sprsplit.asm`, behind a five-instruction bridge in `sprite.asm` on
`PanelTick`'s pattern. It can live there because every byte it reads is outside bank 4 — the level
draw's flags and `line` are zero page, and the door table, the animated-tile list and the sprite
arrays are all main RAM. Moving it out gave the code image back **323 free bytes** against 11
before; bank 6 went from 1,609 free to 975.

## What it measures now

Same harness, on the pass that matters: **scrolling diagonally, two sprites (the player and a 302),
the level draw running, split taken.**

| offset from window A open | phase | cost |
|---:|---|---:|
| 0 | window A opens | |
| 0 → 11,459 | keys, movement, fire, `AnimTick`, `SprSplitOK`, restore of tranche A | 11,459 |
| 11,459 → 16,340 | **`DoRedraws`** — a column pass | 4,881 |
| 16,340 → 17,133 | `AnimPaint` + the three debug keys | 793 |
| 17,133 → **21,617** | `SprAnimateAll` + `SprDrawTr(A)` | 4,484 |
| **24,576** | **window A closes — 2,959 cycles to spare** | |
| 39,936 | window B opens; tranche B — the enemy droid — is erased and redrawn there | |

`sprTr` on that pass is `[0, FF, FF, FF, FF, FF, 1, FF]`: the player in A, the droid in B, **while
scrolling**. The old code refused the split outright on exactly that pass.

`AnimTick` is 1,558 cycles on a rotate pass and ~30 otherwise, against 10,060.

## How it was verified, and the trap in the obvious method

**The buffer oracle has to take both dumps inside ONE pass.** The first attempt dumped the buffer,
pressed SPACE, ran 800,000 cycles and dumped again — and reported 35 bytes wrong on the new build
and 196 on an intermediate one. Both were **artefacts**: 800,000 cycles is twenty passes, and a
door opening or a recharger turning in between is a difference that has nothing to do with the
change under test. The baseline scoring 0 on the same method was luck of that run's state.

The protocol that works:

1. drive the view diagonally so `line != 0` and `mapHX` is odd, then stop;
2. poke **all three** draw sites to `NOP` — the `JSR SprDrawAll` and both `JSR SprDrawTr`s — and let
   a pass or two run, so the restores take every sprite off the buffer;
3. hold SPACE and break on the `JSR RedrawAll` itself; dump the buffer;
4. clear that breakpoint, break on the instruction *after* it, run, dump. `RedrawAll` takes more
   than 500,000 cycles, so the first run may not reach the second breakpoint — run again rather
   than concluding it was missed;
5. diff. Nothing else has moved: it is the same pass.

**Result: 0 of 10,240 bytes**, scrolled diagonally with the split active.

## What is left

The margin in window A is **2,959 cycles**, which is 0.57 of a sprite — a third sprite in tranche A
overflows it. The next item is the one Phase 1 did not take:

- **`ReadKeys` + `CalcSpeed` + `CheckWalls` cost 5,004 cycles** and are the largest thing left
  above the erase. They cannot simply move below the level draw, because `ApplyMove` decides the
  scroll — but they can be *pipelined*, computing the speeds at the end of the pass for the next
  one's `ApplyMove`. `CheckWalls` would then run against the position `ApplyMove` has just
  produced, which is the position it will move from, so it is not even stale. `DoCharUnder` reads
  `plyCX`/`plyCY` and would have to follow it.
- Step 3 above — the column half of `DoRedraws` into window B — is still available and still cheap.
- `FRAME_LOCK` 3 remains the last resort, and remains KC's call.

## A postscript: the magenta band was lying

Reported by KC while reading `DEBUG_DRAW` on the build above — *"the magenta portion is still
frequently catching the main play area"*. It was, and **nothing was overrunning**: the band was
over-reporting.

`DEBUG_DRAW` tints the background at the start of a piece of work and the tint runs until the next
one. The magenta set before `SprAnimateAll` had no close after the draw, so it ran on through
`AnimScanPass`, `DroidsUpdate`, the collisions, `DoAging`, `DoCharUnder`, `PanelTick` and the
`WaitWindowB` idle — to the tranche-B block at the far end of the pass. It was reporting some
20,000 cycles of display-period work as sprite work.

**It broke in Step 1 above.** While `DroidsUpdate` ran *before* the draw there was almost nothing
between the draw and the end of the pass, so the band ended about where the sprite work did. Moving
the droid AI below the draw left the closing tint where it was, and Phase 1 then put
`AnimScanPass` in the same gap.

The fix closes magenta where the draw ends and gives the display-period work a band of its own
(**red**, `DBG_AI`), closed before `WaitWindowB` so that untinted space is genuine slack. Measured
on the fixed build, from window A opening:

| band | opens | closes | |
|---|---:|---:|---|
| magenta — `SprAnimateAll` + the draw | 12,833 | **17,049** | ends 7,527 cycles before the play area |
| red — the droid AI and the rest | 17,049 | 30,038 | 5,462 cycles into the play area, by design |
| | | 39,936 | window B opens — 9,898 cycles of slack |

So on the fixed build **magenta touching the play area is a real overrun again**, which is what the
instrument is for. Red touching it is expected: none of that work writes the buffer.

# `keydown` goes direct to the matrix — 2026-08-26

## Why it was worth doing

The pass tests ten to twelve keys — Z/X/K/M, ESCAPE, L, SPACE, P, R, the volume trio every other
pass, and `[`/`]` on a `DEBUG_DECK` build. Four of those arrived in one afternoon (volume, mute,
pause, the second transfer button), which is what made the cost visible: every one of them was an
`OSBYTE &81`, and the OS charges a lot for a question the hardware answers in one write and one
read.

## The measurements

| | cycles |
|---|---|
| `JSR keydown` via `OSBYTE &81` | **243** |
| `JSR keydown` direct | **69** |

Both are `JSR` to `RTS` inclusive. The OSBYTE figure was taken twice by different routes and the
two agree: the title's `TiWait` loop turned 3,654 times a second with a body that is one `keydown`
plus ~36 cycles of counter (→ 238 for the call itself), and a `DEBUG_TIME` bracket round `ReadKeys`
read 1,009 cycles for four calls plus ~62 of glue (→ 237). The direct figure is a breakpoint pair
on the `JSR` and its return instruction, differencing `elapsed_cycles`.

**~2,175 cycles a pass**, then, at 12.5 tests — about 2.7% of the 79,872-cycle pass, arithmetic
from the per-call measurement rather than measured as headroom.

**And it fixed the single-line scroll flicker** (KC, 2026-08-26), which is what `PLAN.md`'s polish
note had guessed at when it asked "move keys off OSBYTE?". Worth recording as the visible payoff:
the saving is small as a percentage, but it came out of the foreground at the point in the pass
where the scroll is least able to afford it.

## The mechanism, and the proof it is doing what it claims

Port A is the slow bus; port B's low nibble is an addressable latch selecting who is listening
(`(value << 3) | line`). Line 3 is the keyboard's write-enable — drop it and the hardware's
free-running column scan stops, so the matrix can be driven by hand. `DDRA = &7F` makes PA0-PA6
outputs carrying the internal key number (PA0-PA3 column, PA4-PA6 row) and leaves PA7 an input
carrying the answer. Write, read, done — this tests a key we *name*, it does not go looking for
whatever is pressed, so there is no iteration.

The emulator showed the bit pattern outright. Testing Z (INKEY `&9E`, so IKN `&61`):

- key up — port A reads back `&61`: the seven bits we wrote, PA7 clear.
- key down — port A reads back `&E1`: the same seven bits, PA7 **set**.

`&FE4F` and not `&FE41` is load-bearing: the no-handshake register. `&FE41` strobes CA2.

## The raster effect, which was the actual risk

The sequence must not be interleaved by the MOS or by the sound driver (which drives the same port
A from the IRQ), so it runs under `PHP`/`SEI`/`PLP` — **26 masked cycles**, twelve times a pass,
against a rupture whose T1 stages are deadline-driven. That was the thing worth measuring, not the
saving.

It costs them nothing. The pass rate is **exactly 25.0 Hz** before and after (50 passes per
4,000,000 cycles, counted on `gameTick`), the rupture holds, and the panel/play boundary is clean
while scrolling. Note what is *not* claimed: what the MOS masks for inside `OSBYTE &81` was never
measured, so "ours interrupts less than the OS did" is not a statement this file makes.

`DDRA` is deliberately **not** restored, which is safe for one reason worth writing down:
`SndWrOpen`/`SndWrClose` save whatever they find and put it back, and the MOS sets `DDRA` itself in
its own scan. Thrust's `test_inkey` — the source this was ported from, in
`BEEB/Repos/thrust/thrust.6502` — does the same.

## The knock-on nobody would have predicted: the title screen

`TiWait` is a free-running poll loop whose body *was* one OSBYTE, so making `keydown` 3.5× cheaper
made the loop 3.15× faster — **87 cycles a turn against 274, 11,508 turns a second against 3,654**.
Two things hang off that count:

- **The volume-key gate** had to be retuned from 1-in-256 back to 1-in-1024. On the OSBYTE build
  1024 gave 3.6 Hz and was rejected as unusable; on this build 256 gives 45 Hz and 1024 gives
  11.2 Hz, which is where the other two call sites sit. The divisor tracks the cost of `keydown`
  and nothing else — the table is in `title.asm`'s header.
- **The timeout into the briefing** is 65,536 turns, so it fell from **17.9 s to 5.7 s**. That is
  not a regression: the C64's own timeout is 256 frames — 5.1 s — and `TiWait`'s header has always
  claimed its wrap was "the same order as the original's". It finally is. Flagged for KC; restoring
  18 s means counting something other than raw turns, not putting the OSBYTE back.

## A trap in `DEBUG_TIME` this uncovered

The first attempt to measure the change with the `DEBUG_TIME` bracket reported `ReadKeys` costing
**2,903** cycles after the conversion, against 1,009 before — three times *worse* for code that is
demonstrably three times cheaper.

The bracket is a User VIA T1 difference, and T1 free-runs from its latch: the subtraction is only
modular arithmetic while the counter does not pass zero between the two reads. When it does, that
pass contributes ~65,536 spurious ticks — 131,000 cycles — so the run's average is wrong by a mile
rather than by a little. The arithmetic confirms it exactly: 147,460 ticks against 19,200 expected
is an excess of 1.96 × 65,536, i.e. **two wraps**; the baseline run's 53,281 against 53,277
expected had none. And because the reload point drifts slowly through the pass (the period is ~1.6
passes) the bad readings arrive in short consecutive runs when it lines up, not sprinkled at
random — which is why one run was clean and the next was not.

**jsbeeb breakpoints fire now**, whatever `DEBUG_TIME`'s header used to say, so for anything short
the honest tool is a breakpoint pair and an `elapsed_cycles` difference. The bracket is still right
for per-pass totals. Both notes are now in the header itself.
