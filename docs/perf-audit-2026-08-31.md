# Performance audit: the flicker, the two windows, and where the pass actually sits — 2026-08-31

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md). Companion to
[`raster-timing.md`](raster-timing.md), which this extends with fresh measurements on the
2026-08-31 22:50 build (`5c98e21` + working tree).*

Commissioned by KC: "still seeing a lot of sprite flickering — full performance audit, review the
two-pass sprite system, prove where the two plots land against the raster, and propose debug
tooling." Everything below is measured in jsbeeb on the dev build unless marked otherwise.

## TL;DR

1. **The pass rate is fine.** 25.0 Hz exactly — 50 passes per 100 fields — stationary, scrolling,
   and on a 9-droid deck. `FRAME_LOCK` holds. (One unexplained transient: §7.)
2. **The tranche logic is correct and the split is taken almost always.** 123–128 of 128 passes
   split in every scenario tried; the assignment, the component merge and the forced-to-A rules
   all check out by review and by inspection of `sprTr` in flight. The stale-slot veto — the thing
   the design worries about — fired on only 0–3 passes per 128 in practice.
3. **The flicker is a window-capacity collapse, not a logic bug.** Window A's work no longer fits:
   the tranche-A draw finished with the beam already over the play area on **29% of passes**
   scrolling an empty corridor, **46% of passes** walking among droids — and on 17 of 128 crowd
   passes it was still drawing a *full field* late. Tranche B finished inside the second display
   on **30%** of crowd passes because the display-period work (droid AI + anim scan) overruns
   window B's opening by up to ~10,400 cycles. Every one of those passes shows sprites erased or
   half-drawn while displayed. That is the flicker.
4. **The level draw also leaves the latch window**: `DoRedraws` returned after fire 1 had latched
   the scroll on 15–27% of scrolling passes — the edge-tear budget is gone too.
5. **`DEBUG_DRAW` no longer assembles** (*Guard point hit*, code image full), so the band
   instrument that would show all of this on screen is currently unavailable. BUGS.md #17's "should
   fit comfortably (639 B free)" is stale — the image has 4 B free today.

## 1. Method

Zero-byte-in-the-build instrumentation, injected into the running emulator:

- **Stubs in the unused half of the stack page** (`&0130–&017E`) with counters at `&0100–&012F`.
  The four main-loop draw `JSR`s (`&1234`, `&123A`, `&129A`, `&121E`) and the loop-bottom
  `JMP mainloop` (`&12AC`) are re-pointed at stubs that call the real routine and then bump a
  4-bin histogram of `ruptState` — one histogram per site, so every pass self-reports where each
  phase ended against the raster with no emulator stops. A fifth histogram buckets System VIA T1
  (`&FE45`, remember it counts at **1 MHz** — one tick = two CPU cycles) at the end of the
  tranche-A draw to grade *how* late the late passes were. Appendix A has the bytes.
- **Breakpoint walks** (`set_breakpoint` + `elapsed_cycles` from `read_registers`) for exact
  per-phase timelines on individual passes — the `docs/raster-timing.md` harness, unchanged.
- `ruptState` decode: the byte names the fire that has just happened. **3, 0, 1 = play area off
  display** (fire 3 → VSync → fire 1 → fire 2); the CRTC latch is the 1→ boundary at fire 1;
  **2 = the play area is being displayed.** A draw phase ending in state 2 overran its window.

Three traps for whoever reruns this (all hit during this audit):

- A hand-assembled branch in the stub was two bytes short and executed `JSR &6001` from the middle
  of an instruction — it wrecked two sessions and *mimicked a game hang* (black screen, `BRK` loop
  in the MOS, fieldCount frozen) before it was found. Symptoms of a corrupt stub look exactly like
  a game bug: verify the stub bytes first.
- The jsbeeb MCP session **goes stale** exactly as the memory note says — "Searching / File not
  found" on a reboot means new machine, not a broken disc.
- The lift ride mid-measurement was *innocent* — the hang blamed on it was the stub bug above.

## 2. Frame lock — no regression

`gameTick` over exactly 100 fields (3,993,600 cycles), `fieldCount` checked alongside:

| scenario | passes / 100 fields | rate |
|---|---:|---|
| stationary, 2 sprites | 50 | 25.0 Hz |
| scrolling diagonally | 50 | 25.0 Hz |
| walking a 9-droid deck (Repairs) | 50 | 25.0 Hz |

`fieldCount` advanced exactly +100 each time — the rupture IRQ is healthy under load.

## 3. Window A — the tranche-A draw against its 24,576-cycle budget

`ruptState` at the **end of `SprDrawTr(A)`**, 128-pass histograms:

| scenario | s0 (in window) | s1 (in window, past latch) | **s2 — beam over play area** | s3 — a whole field late |
|---|---:|---:|---:|---:|
| scroll, corridor, 2 sprites | 78 | 13 | **37 (29%)** | 0 |
| stationary at wall, 2 sprites | 120 | 2 | **6 (5%)** | 0 |
| firing at wall (Weapon mode) | 87 | 20 | **25 (19%)** | 0 |
| walking among droids | 42 | 7 | **57 (46%)** | **17 (13%)** |

The T1 buckets grade the late passes: on the corridor scroll, 11 were ≤3,070 cycles late (beam in
the top ~24 lines), 19 were 3–7k late (beam 24–56 lines in — the player's own row), 8 were 7k+
late. On the droid deck the largest bucket was the **worst** one, and 17 passes ended in state 3 —
the *entire* visible frame had passed while tranche A (the player's tranche) was mid-draw.

**Anatomy of a late pass**, breakpoint-walked (stationary, split taken, both sprites merged into
tranche A, recharge-pad animation running, offsets from window A open):

| segment | cycles |
|---|---:|
| keys, movement, fire, `AnimTick` | 5,263 |
| `SprSplitOK` + `SprRestoreTr(A)` ×2 + `SetCRTCStart` | 7,852 |
| `DoRedraws` + `AnimPaint` + debug keys — **with `bandDo`=0, `colCount`=0** | 7,357 |
| `SprAnimateAll` + `SprDrawTr(A)` ×2 | 8,765 |
| **end of tranche-A draw** | **29,237 — 4,661 past the close** |

Two things stand out against the 2026-08-20 measurements in `raster-timing.md`:

- **`SprSplitOK` is no longer cheap.** ~4,200 cycles on a pass with five animated tiles listed and
  doors registered (each live anim tile and door runs `SprTileHit` per active sprite). It was a
  handful of flag tests when the veto was global. It runs at the front of window A every pass.
- **The anim-tile repaint is a heavyweight window-A tenant.** 7,357 cycles for the
  `DoRedraws`/`AnimPaint` segment with *no scroll work at all* — the recharge pad's rotate pass
  repaints its tiles in window A and simultaneously forces any sprite within 8 units of them into
  tranche A. The rotate cadence (~every 4th pass with a pad in view) matches the ~30% late-pass
  rate on the corridor scroll almost exactly.

And the structural one: **tranches merge more than the design hoped.** `sprTr` read in flight
repeatedly showed `[0,FF,FF,FF,FF,FF,0,FF]` — a droid walking near the player shares tranche A
(overlap merge, or forced by the draw), tranche B empty. A 2-sprite tranche A plus a level draw
plus today's fixed costs does not fit 24,576, and the design's accepted answer ("an unbalanced
split is strictly better than none") is true but is exactly the flicker KC sees: it degrades to
the old whole-pass behaviour on the commonest screen configuration.

## 4. The level draw and the fire-1 latch

`ruptState` on **leaving `DoRedraws`**: after the latch (states 1/2/3) on **12/128** corridor-scroll
passes and **35/128** droid-deck passes. On those passes the newly exposed edge is being written
while (or after) the CRTC has already latched the new scroll position — the edge-tear condition
`raster-timing.md` Step 1 had driven to 0/128. It is back, because everything in front of
`DoRedraws` grew.

## 5. Window B — the droid AI has outgrown the display period

Breakpoint walk on a droid-deck pass (offsets from window A open; window B opens at 39,936):

| event | offset |
|---|---:|
| tranche-A draw ends | 17,496 |
| `AnimScanPass` + transfer/ship checks | +92 |
| **`DroidsUpdate`** (9-droid deck, quiet pass) | **+14,307** |
| collisions, aging, entry hold, sound, char-under, panel | +570 |
| enters `WaitWindowB` | 50,365 — **10,429 past window B's opening** |
| tranche B (1 droid): restore + draw | 6,173 — ends 56,538, still inside window B |

On a *quiet* pass the display-period segment is ~15k and window B opens with room to spare. But
`DroidsUpdate` alone ranges to ~20k+, `AnimScanPass` adds ~7k on a rebuild pass (every tile-column
crossing), and `PanelTick` adds more when the panel redraws — the measured worst here was
**32,869 cycles** between draw-A-end and `WaitWindowB`, which eats the whole display period plus a
quarter of window B. Tranche B then starts late, and its draw ended in state 2 — the *second*
field's display — on **37 of 123** split passes on the droid deck. The end-of-draw-B histograms:

| scenario | s3+s0+s1 (in window B) | s2 — late |
|---|---:|---:|
| corridor scroll | 128 | 0 |
| droid deck | 87 | **37 (30%)** |

So on a busy deck *both* tranches routinely miss their windows. A sprite erased in a window and
redrawn after the beam has passed its rows is displayed missing — one field in two, the 25 Hz
blink. Two consecutive single-field screenshots caught it directly: the same droid solid in one
field, half-faded in the next.

## 6. The split system itself — reviewed, and it holds

Full static review of `sprsplit.asm` + the slot lifecycle (`sprActive`/`sprSaved`/`sprTr`) against
`droid.asm`, `combat.asm`, `sprite.asm`, the modal arms and the effect-sprite paths:

**Verified correct:**
- `sat_init` re-labels every slot each run — no stale `sprTr` can leak into a split pass, and on a
  whole/veto pass `sprTr` is never read (`SprRestoreAll`/`SprDrawAll` pass `&FF`).
- The component merge, `satNA/satNB` accounting, tie-to-A and slot-0-first are right; the player
  is always in the first window.
- A slot newly activated by `DroidsUpdate` (which runs after the draws) carries `sprTr = &FF` and
  is skipped by both tranche loops until the next pass's assignment — one pass of latency by
  design, no draw without assignment.
- `SprHitsDraw`'s coordinate frames check out (`line + sprScrY` vs `bandRc*8` are the same
  strip-relative scanline frame; no 8-bit overflow; pads err safe). One nit: the header's "a pass
  can scroll the view eight units" rationale is wrong — the scroll cancels between the view rebase
  and the buffer base shift, and the pad actually covers the sprite's *own* movement — but the pad
  is sufficient (horizontal is over-generous, costing split opportunities only).
- Effects (bullets, explosions) share the arrays with identical semantics and are covered by the
  same tests; the full 7×21 footprint for a small bullet is conservative, never wrong.
- The four `SprHitsDraw` writers are the only split-pass buffer writers on release paths; the
  console/lift/transfer takeovers either clear `sprSplit` (`ConMenuInit4`) or skip the tranche-B
  block and repaint on exit.

**The stale-slot veto is real but rare in practice.** Whole passes measured: 0/128 corridor,
1/128 firing at a wall, 3/128 droid deck. The events that raise it (bullet death via `mpf_kill`,
droid stepping behind a wall via `drs_keepvis`, droid leaving the view via `drs_off`, explosion
end via `dxp_dead`) each cost exactly one whole-pool pass, and a whole pass with the pool loaded
flickers everything — but at these rates it is a minor contributor next to §3/§5. (The firing test
was weak: shots at an adjacent wall may never spawn the bullet. Worth one more measurement in a
real firefight before closing the question.)

**Two low-frequency correctness gaps found (ghost pixels, not flicker):**
1. *Slot reuse before restore.* A slot freed and re-allocated to a different droid inside one
   `DroidsUpdate` dodges the stale veto (`sprActive` is 1 again) while its pending restore still
   points at the old position — the restore then replays in whatever tranche the *new* position
   earns, which can violate the invariant against the other tranche and, worst case, stamp a
   ghost into another sprite's saved background. Needs `DrFindSlot` to hand the same slot to a
   newcomer in the same pass — rare, but real.
2. *`SprOverlapXY` pad covers one sprite's movement, not two.* Two sprites that overlapped last
   pass and separate at combined speed (Δ up to 4 units/16 scanlines in a pass) can land in
   different tranches while one's save still holds the other's pixels; the window-B restore then
   stamps last pass's overlap back. Fix is two constants (`SPR_W+4`, `SPR_H+16`) at the price of
   some split opportunities.

Neither is the reported flicker; both are worth fixing when the file is next open.

## 7. Two loose ends, flagged not concluded

- **A 62-passes-in-100-fields transient** (31 Hz — the design says the rate "never exceeds
  25 Hz") was measured once on the droid deck, immediately after heavy single-frame stepping and
  breakpoint traffic; the identical scenario re-measured clean at exactly 50/100 twice. Overrun
  arithmetic says sustained >25 Hz should be impossible (an overrun's recovery pass averages back
  to 2.0 fields), so either the debugger perturbed the rupture (fieldCount re-entry?) or there is
  a real re-dating hole. `DEBUG_VSYNC`'s counter is the instrument if it shows on hardware;
  nothing in this audit reproduces it without the debugger in the loop.
- **jsbeeb screenshots of the lift view came back solid black** during the misadventure in §1.
  Almost certainly the stub crash, but the lift view was not re-screenshotted on the clean
  session; if a black lift screen ever shows on b2, that memory note about the MCP capture
  misrendering the rupture is the first suspect, not the game.

## 8. Debug tooling — what exists, what is broken, what to add

- **`DEBUG_DRAW` is the right instrument and it does not build.** *Guard point hit* at
  `main.asm:3555` — the code image is at 4 B free and the band setters cost ~75+ B of it. BUGS.md
  #17's note that it "should fit comfortably (639 B free)" predates Layer 13b/15 and is stale.
  Reviving it means buying bytes: the RAM-pass reserve list (`sprsplit.asm` is *already* in bank 6;
  next candidates were SCANSTEP tail folding, `door.asm` to bank 4, the `hsfont` dedup) or a
  DEBUG-only overlay that steals a region a dev build can afford (e.g. assemble the band code over
  `dfsSave`'s 912 B in bank 6 on `DEBUG_DRAW` builds, since a dev session can forgo the game-over
  → title seam, with an `ASSERT` refusing the combination).
- **Tranche visualisation (proposed, not built): `DEBUG_TRANCHE`.** After each `SprDrawSlot` in
  the tranche loops, stamp one solid byte at the slot's top-left buffer address — colour 1 for
  tranche A, colour 2 for B, colour 3 on the whole-pass path. ~25 bytes, and they must live in a
  bank (image full); the tranche loops are in the code image but run with the sprite bank paged,
  so the stamp belongs beside the blitter in bank 5 (602 B free). One glance then shows the
  assignment, the merges, and every whole pass as a colour change.
- **Plot-pass raster position without any build cost**: the stack-page stub harness (Appendix A)
  gives per-phase `ruptState` histograms and T1 lateness grading on any running build in jsbeeb.
  It found everything in this report; it is the cheap recurring check that "each tranche ends in
  its own window" stays true — the provable-correctness KC asked for is exactly "histogram bins
  1/2/3 at the end of each drawer are zero", and today they are not.
- `DEBUG_RASTER` (rupture-stage tints) was not retried; assume it no longer fits either until
  proven otherwise.

## 9. Recommendations, in the order I would take them

1. **Get the animated-tile work out of window A** (biggest single win on the corridor numbers).
   The rotate pass currently pays `AnimPaint` in window A *and* forces nearby sprites into
   tranche A. The tile repaint writes single tiles, exactly like doors — it could move to window B
   (after the tranche-B draw, still off-display) with `SprHitsDraw` teaching tranche-*B* avoidance
   instead of tranche-A forcing for anim tiles; or the pad's four chars could rotate less often.
   Needs KC's call on which shape — both are deviations from the current [DECISION 2026-08-20]
   arrangement.
2. **Move the column half of `DoRedraws` to window B** — `raster-timing.md` Step 3, already
   designed, still cheap, directly attacks the 46%-late crowd number and the latch misses in §4.
3. **Cut `SprSplitOK`'s per-pass cost.** It re-derives every span test even when the writer lists
   are empty; an early-out when `bandDo|colCount|animDirty|doorwork` is clear (the commonest pass)
   keeps its cost at flag-test level, and the tile loops could hoist the per-sprite span setup.
4. **Pipeline `ReadKeys`/`CalcSpeed`/`CheckWalls`** (~5,000 cycles out of window A) — the item
   `raster-timing.md` already queues, unblocking ~2 more sprites of window-A headroom.
5. **Replace the stale-slot veto with saved-position forcing** (fix #1 in §6's gaps at the same
   time): record the drawn view position per slot (16 B), treat a stale slot as a forced-A member
   using the saved coordinates. Converts every combat slot-death from a whole-pool flicker pass
   into a normal split pass. Lower priority than 1–4 because the veto is rare, but it also closes
   the slot-reuse ghost.
6. **Widen `SprOverlapXY`'s pads to two sprites' movement** — two constants, closes §6 gap #2.
7. `FRAME_LOCK` 3 remains the last resort and remains KC's call — at today's costs it would make
   every number in §3–§5 fit with room to spare, at 16.7 Hz.

## Appendix A — the stub harness (jsbeeb, dev build 2026-08-31)

Counters `&0100–&012F` (zero them first), stubs at `&0140`. All five patches are 2-byte operand
pokes; restore by re-poking the originals (or rebooting).

| patch site | original operand | stub | records |
|---|---|---|---|
| `&1235` (`JSR SprDrawTr`, tranche A) | `05 2A` | `&0140` | `ruptState` end-of-draw-A → `&0100+s`; split count `&0118`; T1CH/8 lateness when s=2 → `&0120+b` |
| `&123B` (`JSR SprDrawAll`, whole) | `01 2A` | `&015C` | end-of-whole-draw → `&0104+s`; whole count `&0119` |
| `&129B` (`JSR SprDrawTr`, tranche B) | `05 2A` | `&0168` | end-of-draw-B → `&0108+s` |
| `&121F` (`JSR DoRedraws`) | `62 A5` | `&0171` | entry → `&010C+s`, exit → `&0110+s` |
| `&12AD` (`JMP mainloop`) | `1E 11` | `&0130` | pass-start state → `&011C+s` |

Stub bytes (63 at `&0140`, 8 at `&0130`):

```
0130: A6 20 FE 1C 01 4C 1E 11
0140: 20 05 2A A6 20 FE 00 01 EE 18 01 A5 20 C9 02 D0
0150: 0A AD 45 FE 4A 4A 4A AA FE 20 01 60 20 01 2A A6
0160: 20 FE 04 01 EE 19 01 60 20 05 2A A6 20 FE 08 01
0170: 60 A6 20 FE 0C 01 20 62 A5 A6 20 FE 10 01 60
```

The addresses are this build's — re-derive from the symbol dump after any change. The `&0158`
`INC &0120,X` makes a perfect trap breakpoint: it executes only at the end of a *late* tranche-A
draw, so `set_breakpoint(0x0158)` lands you inside the exact pass to autopsy. The stack page's
`&0100–&017F` was measured untouched (see `ram-pass.md`) but the lift, transfer and briefing paths
were never exercised in that measurement — in the emulator that risk is acceptable; it is another
reason this harness must never ship.

One hard-won correction to the T1 arithmetic: **the System VIA counts at 1 MHz.** A T1 reading is
half the CPU cycles remaining to the next fire; forgetting the factor of two makes every lateness
estimate double and does not reconcile with `elapsed_cycles`.
