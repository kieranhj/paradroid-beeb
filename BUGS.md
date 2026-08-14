# Known defects

Open defects found by measurement, with the evidence for each. Entries stay here until
fixed, and record what has been *ruled out* as well as what is suspected — the ruled-out
list is usually the expensive part to reproduce.

Defects 1–4 were found on 2026-08-10 while verifying the Layer 5 sprite save-geometry change
(`3f69b4d`); all of them predate that commit and reproduce identically on the build before it.
Later entries carry their own date.

Numbering is historical, not an order — 3 sits after 4 because it was added later.

---

## 1. `RedrawAll`'s split-row repair has no effect — the debug oracle is wrong

> **Probably moot as of 2026-08-13, not fixed.** The band now draws whole character rows, so no
> display row aliases two map rows, and both repair passes — `RedrawAll`'s and `DrawColumn`'s —
> were deleted along with `DrawHalfPart`. `RedrawAll` is now sixteen whole rows from `mapYr`, which
> *is* the strip's invariant, and it diffed byte-identical against incremental scrolling at
> `line` = 1, 3 and 4. The contradiction below was never resolved, so this entry stays until
> someone re-runs its own tests and confirms there is nothing left to explain.

**Severity:** does not affect the game. Affects verification only — but it affects *every*
layer's verification, which is why it is first.

**Symptom.** Diffing the play buffer against a SPACE-forced `RedrawAll` reports differences
whenever `line != 0`. They are always in the same place: display row 0, scanlines
`0..line-1` — the split character row.

**Who is wrong.** `RedrawAll`. The incremental scrolling is correct.

**Evidence.**

| Test | Result |
|---|---|
| `line == 0`, whole 10 K buffer | Incremental is **byte-identical** to `RedrawAll` — the band logic is sound |
| `line == 6` (`posY=94, mapYr=11`) | Exactly 6 scanlines differ, at display row 0 scans 0–5 |
| Repair reached? | **Yes** — a sentinel poked into `bandRun` was overwritten with `line` |
| Repair's output, `line == 2` | Display row 0 holds **69 non-blank cells, 0 splits** — every cell is one whole charset character |

That last one is the decisive, reference-free test. `RedrawAll` draws whole character rows
from `mapYr`, then the repair is supposed to overwrite scanlines `0..line-1` with character
row `mapYr+16`. If it worked, those cells would be a *split* of two different characters.
None of them is. The row is left entirely as character row `mapYr`.

The content is genuinely distinguishable — tilemap rows 2 and 6 (the tile rows behind
character rows 11 and 27) differ at several columns (`08`/`07`, `15`/`16`, …), so this is
not two rows that happen to render the same.

**Why the split row needs a repair at all.** The strip holds absolute rows
`[posY, posY+128)` and `posY = mapYr*8 + line`. Display row 0 scanline *s* therefore holds
map row `mapYr*8 + s` when `s >= line`, but `mapYr*8 + 128 + s` — character row
`mapYr+16` — when `s < line`. `LoadDeck` sidesteps this by zeroing `line` and `scrollS`
before its own `RedrawAll`; the SPACE debug key does not.

**Ruled out.**

- Not the parameters. `cellY = mapYr+16`, `bandScan = 0`, `bandRun = line`, `rCount = 0`
  are all correct in the assembled listing (`LDA &86 / ADC #&10 / STA &87 / JSR &1926`)
  and at runtime.
- Not the call target. `&1926` is `DrawBandRows`.
- Not `BandSetRow`'s arithmetic. `(tileRow AND 3)*64 + (tileRow>>2)*256` does equal
  `tileRow*64`, and it reads `&87`.
- Not placement by `SetCell`: `rCount = 0` gives `BUF_BASE + scrollS`, which is display
  row 0.
- Not overwritten afterwards — the repair is the last thing `RedrawAll` does, and nothing
  between it and the next frame's redraw touches that region.

So it executes, with correct inputs, through code that reads the addresses it should, and
produces the wrong character row. That contradiction is unresolved.

**Next step.** Separate *"wrote the wrong content"* from *"wrote to the wrong address"*:
poke a distinctive sentinel into the buffer at display row 0 scan 0, force the redraw, and
see whether the repair overwrites it. That is the fork the code reading could not close.

**Note for whoever picks this up:** jsbeeb breakpoints did not fire in any of these
sessions — not even on the main loop — so execution could not be traced. Memory sentinels
were the workaround and worked well.

---

## 2. Blank scanlines inside the visible window after stopping against a wall

**Severity:** visible, small.

**Symptom.** After scrolling **down** at speed and stopping against a wall
(`posY = 169`, `ySpd = 0`, `line = 1`), the buffer held **blank** scanlines at display row 0
scans 1 and 2. With `line = 1` the display starts at scan 1, so those are the top two
visible pixel rows, and they should hold in-window map rows 169–170.

Only scan 0 is a legitimate split-row scanline at `line = 1`, so this is *not* defect 1 —
scans 1 and 2 come from the main loop's reliable path.

**What it looks like.** The affected rows are mostly background, so the cost is a few
pixels of grid line missing from the top scanline. Easy to miss.

**Ruled out.**

- Not the map clamp. `MAX_PX_Y = 384`; the view stopped at 169 against a *wall*, nowhere
  near the limit.
- Not `ClampY` ordering — the band is computed from the post-`ClampY` `posY`.
- Not `CheckWalls` — it runs before `ApplyMove` and only zeroes the speed.

**Lead.** Stepping frame by frame, the view ran 167 → 168 → **170** → settled at **169**.
It moved *backwards* by a pixel. The band drawn while it read 170 covered rows 296–297;
the settled window `[169, 297)` excludes 297, leaving that scanline holding the strip's
blank bottom edge. Whatever retreats the view by one pixel after the band has been
computed is the thing to find.

---

## 4. The player can spawn inside a wall, and is then stuck

**Severity:** blocks play on the affected decks.

**Symptom.** On some decks the player cannot move at all after `LoadDeck` — holding a direction
for 46 game-loop iterations moves `plyX` by 2 pixels and then nothing. Confirmed on **decks 5 and
14**; deck 1 is fine.

**Cause.** `CentreOnDeck` (`src/level.asm`) picks the view from the **centroid of the deck's
non-zero tiles**, and `SetPosFromMap` then drops the player at `posX + PLY_HOME_X`, `posY + PLY_Y`.
Nothing in that chain asks whether the resulting cell is walkable. On a deck whose tiles happen to
average out onto a wall — or onto a region the deck does not actually cover — the player lands
solid and `CheckWalls` zeroes the speed on every axis, every iteration.

**Ruled out.** Not the sprite pool: with `TestDroidsUpdate` NOPed out and slots 1-6 cleared, the
player is still stuck. Not a Layer 5 regression either — it is a property of `CentreOnDeck`, which
has not changed since Layer 3.

**The fix is already known and written down.** `tools/export_droids.py` records that **waypoint 0
of each deck is never used by `InitDeckDroids`** and is there to be the player's spawn point when
changing deck. Waypoints are walkable by construction, since droids patrol between them. Spawning
on waypoint 0 and centring the view on that replaces the centroid guess entirely, and the waypoint
data is already exported (`wpData`, `wpOfsLo/Hi`, `wpCount`). This belongs with the droid-state
work rather than the blitter.

**Workaround meanwhile:** `TD_DECK = 1` in `main.asm`.

---

## 3. Top line wrong for one frame when stopping after moving up at full speed

**Severity:** visible, transient.

**Symptom** (reported from play, not yet instrumented): moving **upwards** at full speed
and then stopping, the top line of the play window is briefly incorrect — for a single
frame, then it corrects itself.

**Why it is probably not #2.** Opposite direction, and self-correcting. A buffer-content
error persists; this does not.

**Leading hypothesis: a raster race, not a logic error.** `SetCRTCStart` deliberately runs
*before* `DoRedraws`, and the IRQ latches the new start address at frame row 3. Moving up,
the newly exposed band is at the *top* of the strip — the part the raster reaches first. At
7 px/frame that is a 7-scanline band which must be drawn before the beam arrives. If the
band loses that race the display shows one frame of stale pixels, and the next frame is
clean. That matches the symptom exactly, including why it needs full speed to show.

If that is right, it belongs with the flicker work — it is the same class of problem as
the sprite tearing, and the same fix (ordering work against the raster) addresses both.

> Note the same hypothesis was raised for defect 5 and **rejected** there. That does not settle
> this one — different symptom, different direction, and this entry has never been instrumented —
> but do not treat "buffer correct, display wrong" as automatically meaning a raster race.

**Next step.** Reproduce headless: hold up at full speed, release, and dump the buffer on
consecutive frames. If the *buffer* is correct on the frame that looks wrong, it is a race
and not a content bug, which settles it immediately.

---

## 5. Player sprite's lower part missing at a doorway, with leftover pixels beside it

Reported from play 2026-08-14, on the Layer 8b build. Screenshot: `ref/player-render-bug1.png`.

**Severity:** visible, persistent while it lasts.

**Symptom.** The player sprite is drawn only down to somewhere inside a character row — the bottom
of it is absent — and a few stray pixels sit beside it that nothing clears.

**Repro.** From the start of deck 1, take the lift down one stop (deck 4), then go down and left
into the empty room. It appears on approach to the door at the bottom left of that room.

Reproduced headless at **deck 4, player reference cell (56, 31) = tile (14, 7)**, wedged between a
vertical door at tile (13, 7) and a horizontal one at (14, 8) — both fully open, `numDoors` = 2,
states `&04` and `&84`. `plyX` = 444, `posY` = 185, `posX` = 300.

**The play buffer is correct. Whatever is wrong happens after it.**

That is the useful half of this entry, because it removes the blitter, the save/restore pair and the
door redraw from suspicion in one go:

| Test | Result |
|---|---|
| Sprite draw NOPed, buffer vs SPACE `RedrawAll` | **0 differences in 10240** — the restore leaves nothing behind |
| Sprite *restore* NOPed, buffer vs the no-sprite buffer | **79 bytes**, across strip rows 7, 8 and 9 — top rotor, digit block and bottom rotor all present |
| Missing scanlines within that footprint | Only sprite rows 5, 14 and 20 — the three that are blank for every droid by design |
| `DEBUG_VSYNC` field counter | **2** — the pass is not overrunning its frame |
| Slot 0 state | `sprActive` 1, `sprUnit` 36, `sprScrY` 50 — nowhere near the cull limits (73 / 99) |
| The draw's own answers | `sprNoWrapS` = 1, so it took the compiled fast path; start `&6A2B`, `sprScan0` = 3 |

So the blitter drew a complete sprite, into the right place, and the restore put the background back
exactly. The buffer holds what it should and the screen does not show it.

> **Sample with the restore disabled, not with the draw disabled.** A dump taken at an arbitrary
> cycle count can land between `SprRestoreAll` and `SprDrawAll`, where the buffer legitimately has no
> sprite in it — which reads exactly like "the blitter drew nothing". NOPing the *restore* makes the
> sprite persist and the sample point stop mattering. This cost a wrong conclusion before it was
> spotted.

**Ruled out.** The blitter's row walk, the compiled fast path, the sprite culling, the save/restore
pair, the door redraw (`DrawDoorTile` never runs here — both doors are at step 4 and not dirty), and
stale buffer content of any kind.

**Not raster timing — KC's call.** The obvious reading of "buffer right, display wrong" is that the
main loop is still writing while the beam reads: the body is ~39,100 cycles against a window of
~24,600 from `drawFlag` at P+184 to the play area redisplaying at P+376, so it has overrun by ~113
scanlines for a long time, and Layer 8 added ~1,500 more. That hypothesis has been **rejected**;
the mechanism is something else and is still open. Do not spend the afternoon re-deriving it.

**Next step.** `DEBUG_DRAW` will show where each piece of work lands relative to the play area, which
is the one thing not yet instrumented. Beyond that the open question is narrow: what can make a
correct 10 K buffer display incorrectly, given the field counter is 2 and the CRTC start address is
parked once per pass before any drawing.

---

## Wanted: a way to hand game state back without a full repro

Raised 2026-08-14, alongside defect 5.

Reproducing a reported bug currently means re-walking the route in the emulator, which took about a
dozen round trips for defect 5 — far more than reading the state would have. A dump would have made
it minutes.

**What is actually needed is smaller than a state dump: a position bookmark.** Deck, `plyX`, `posY`
is enough to poke the player straight back to the spot; the rest can be read from memory once there.
Everything else — the play buffer, the save areas, the door and lift tables — is already reachable
from the emulator once the position is right.

**The blocker is main RAM.** Layer 8b left **46 bytes** free below `&3000`, and an on-screen readout
needs more than that, even reusing `DEBUG_VSYNC`'s 4x5 digit font. So this waits on `PARADAT` moving
to sideways RAM, which is the binding constraint for the next layer anyway.

Two options when the space exists:

- **Digits in the panel.** Reuse `dbgFont` to print deck / `plyX` / `posY` on a key. Readable
  straight off a screenshot, no tooling either end.
- **Raw state bytes written into panel screen memory.** Perhaps 15 bytes of code — copy N bytes of
  state to `PANEL_ADDR` and let the pixel pattern carry them. Unreadable by eye, but trivially
  decoded from a screenshot in Python, and it scales to as much state as wanted.

Neither is needed if the repro is short. **Repro steps plus a screenshot were enough for defect 5**;
it was the walking that was slow, not the diagnosis.
