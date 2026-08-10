# Known defects

Open defects found by measurement, with the evidence for each. Entries stay here until
fixed, and record what has been *ruled out* as well as what is suspected — the ruled-out
list is usually the expensive part to reproduce.

Found 2026-08-10 while verifying the Layer 5 sprite save-geometry change (`3f69b4d`).
**All three predate that commit** and reproduce identically on the build before it.

---

## 1. `RedrawAll`'s split-row repair has no effect — the debug oracle is wrong

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

**Next step.** Reproduce headless: hold up at full speed, release, and dump the buffer on
consecutive frames. If the *buffer* is correct on the frame that looks wrong, it is a race
and not a content bug, which settles it immediately.
