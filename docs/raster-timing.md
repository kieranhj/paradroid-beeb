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
  P+208      tail cycle    13 rows, none displayed; VSync at P+272
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

### Step 2 — put each sprite's erase and redraw in the same window

Per sprite, restore + draw is **5,814 cycles**, so a 24,576-cycle window holds **4.2 sprites**, and
two windows hold **8.4** — against a pool of 7. So split the pool into two tranches, each doing its
own restore-then-draw inside one window:

```
  window A   SprRestore(A) → DoRedraws → SprDraw(A)
  display    keys, movement, droid AI, animate        (no buffer writes)
  window B   SprRestore(B) → SprDraw(B)
  display    spare
```

`WaitVSync` becomes two one-field waits rather than one two-field wait; the 25 Hz rate is unchanged.

**Two hazards, and the second decides whether this works at all.**

1. **Overlapping sprites must share a tranche.** The whole pool restores before it draws because
   drawing one sprite while another is still on screen captures the second one's pixels into the
   first one's save area, and restoring it later stamps them in permanently — the same trap that
   killed round-robin. Within a tranche the invariant holds; across tranches it only holds for
   sprites that do not overlap. Layer 6's `DrCollide` already computes overlaps, though this needs
   the true 7 × 21 footprint rather than the feel-based box. Overlaps are rare, so the simple rule
   is to pull an overlapping pair into the earlier tranche and accept an occasional 5-sprite
   tranche that overruns its window (that pass flickers exactly as today).

2. **`DoRedraws` must not repaint over a sprite that is currently drawn**, or that sprite's saved
   background is stale. With all restores in window A this is free; with tranche B still drawn
   during window A it is not. **The thing to check first is whether it can happen at all**: sprites
   are *culled, not clipped* (`SPR_MAX_UNIT` = 73 of 80, `SPR_MAX_Y` = 99 of 120), so no sprite ever
   occupies the outermost units or the bottom rows — and the band `DoRedraws` paints is exactly the
   newly exposed edge. If the two provably cannot intersect, step 2 is safe as written. **If they
   can, the fallback is to run the two-tranche scheme only when the level draw is empty** — which is
   most passes, and scrolling masks flicker anyway.

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
