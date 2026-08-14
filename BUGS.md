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

> **Retest this against the 2026-08-14 wrap fix first.** Defects 5 and 6 were both the
> interpreted row falling into the non-walking tail, and this entry has never been
> instrumented. A one-frame wrong top line is not obviously the same thing, but it costs one
> run to find out and the fix landed after this was last seen.

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

## 5. Player sprite's lower part missing at a doorway — **FIXED 2026-08-14**

**The interpreted row fell into the wrong tail.** `sd_slow` ends by putting `bufp` back to the
row's first column — so it has *not* advanced a scanline — and then ran straight into `sd_nextnw`,
the tail for rows that walked themselves. Every row after the first wrapping one was therefore
drawn on top of it. `sr_slow` had the same fall-through. One `JMP sd_next` and one `JMP sr_next`.

The two tails arrived when the compiled rows took over their own walking; the comment above them
even says "blank rows and the interpreted paths do not" advance, which is exactly the case that was
then left falling into the wrong one.

**Why it looked like a doorway bug.** A row only takes the interpreted path when its seven columns
straddle the end of the circular strip, which depends on `scrollS` — so it fires at particular
scroll offsets, which for a given route are the same map positions every time. Doors were a red
herring: KC's sightings were near doors because that is where you stop and look.

**Why the oracle never saw it.** The restore mirrored the fault exactly: it collapsed the same rows
onto the same scanlines it had drawn them at, so the background came back correctly. Diffing the
buffer against `RedrawAll` with the draw disabled therefore reported 0 differences for weeks. The
symptom was only ever in the *drawn* sprite, and every check we had disabled the draw.

**Reproduced and verified deterministically.** With the player at unit 37, `line` 0 and
`scrollS` = &17B0, seven of the sprite's 21 rows straddle the wrap. Before the fix the droid is a
one-row streak; after it, at the identical position, it draws in full.

> KC found it: "it's definitely at the wrap around point — if I poke zeros into RAM at &5800 and
> just below &8000 I can erase the smeared pixels." Pixels at *both* ends of the strip is the
> signature of a sprite whose rows are landing across the wrap, and that pointed straight at the
> interpreted path.

**Defect 6 may be the same root cause** — its debris was in rotor rows, at positions that varied,
and it survived a frozen rotor phase. It has not been re-tested since this fix. Do that before
spending anything else on it.

## 6. The rotor restore leaves pixels behind, at both shifts — **FIXED 2026-08-14, same cause as 5**

Closed by the `sd_slow`/`sr_slow` tail fix. The debris was the same collapsed rows: a sprite whose
row straddled the strip wrap drew its remaining rows on top of one another, and the leftovers that
showed up in a restore-only buffer were those rows sitting where nothing expected them. Everything
below is the evidence as it was gathered, kept because the ruled-out list cost more than the fix.

The two facts that pointed away from the real cause, for the record:

- **"It survives freezing the rotor phase."** True, and irrelevant — the fault is in the row walk,
  not the artwork, so the phase never mattered.
- **"A single sprite is clean, 0 of 10240."** True at the position tested, and misleading: that
  position had no row crossing the wrap. Sprite *count* was never the variable; scroll offset was.

The lesson worth keeping: both of those were sound measurements that supported a wrong conclusion,
because the thing being varied was not the thing that mattered. `DEBUG_POS` now prints `scrollS`
precisely so the variable that does matter is visible.

Found 2026-08-14 while verifying the glyph-spill fix, which is **not** its cause — see below.

**Severity:** visible as flicker/debris, transient. Probably the same thing as #3, and probably
what the raster-ordered sprite updating item in `PLAN.md` is really about.

**Symptom.** With `JSR SprDrawAll` poked to `RTS` so the pool only restores, the play buffer
differed from a SPACE-forced `RedrawAll` in **24 bytes of 10240**, all of them extra lit pixels
that the restore did not put back.

**Where they were.** Mapping every differing byte onto the seven slots' 21 × 7 footprints:

| slot | shift | sprite rows affected |
|---|---|---|
| 0 | 1 | 0, 1, 2, 4, 15, 17, 18, 19 |
| 1 | 0 | 18, 19 |
| 3 | 0 | 18, 19 |
| 4 | 0 | 0, 1 |
| 5 | 1 | 0, 1 |

**Every one is a rotor row, and rows 0, 1, 18 and 19 dominate.** Not one is in the digit block
(rows 6–13), and four of the five affected slots are at shift 0.

> **The phase hypothesis below is REFUTED, 2026-08-14.** Freezing the rotor — `SprAnimateAll` poked
> to `RTS`, so the draw and the restore see the same phase — still leaves 24 bytes. Whatever this is,
> it is not the phase advancing between the two. The same runs also showed the count varying with
> the player's position in one build (0, 6, 24 and 39 at four positions), so position, not phase, is
> the thing to vary when reproducing it. Everything below is kept because the row mapping is still
> good evidence.

**Leading hypothesis (refuted — see above): the end rows are restored under the wrong phase.** Rows 0/1/18/19 come from
two-entry tables indexed by `phase >> 2`, and the restore's column list is generated per
`(shift, phase >> 2)` — `drRHalf<shift>_<arr>_<half>`. The restore runs a frame after the draw, by
which time the phase has advanced; `sprTabBaseS` exists precisely to carry the draw's phase across,
so the question is whether the *halves* dispatch honours it or re-reads the current phase. Rows 2,
4, 15 and 17 on slot 0 are the same rows under the other half of the same table, which fits.

**Ruled out as the cause: the 2026-08-14 glyph-spill fix.** That change touches the digit block
only — the glyph code, `SprDigitBlock`'s draw order and `SprBlkRest`'s column count, all of which
address rows 6–13. Those rows show zero differences here, and the defect appears on shift-0 slots
where no spill exists at all.

**A single sprite is clean — 2026-08-14.** With the test droids deactivated and `TestDroidsUpdate`
NOPed, the player alone restores byte-exactly: **0 of 10240**. So this needs more than one sprite on
screen, or a position only reachable with them there. The save areas are not the mechanism either:
the worst case is 223 bytes of the 256-byte page (`scan0` = 7, three character-row crossings), and
`SprCalcAddr`'s no-wrap test covers the furthest byte a sprite touches — `bufp + 1964` against a
threshold of `bufp + 1968`, safe by four bytes and worth knowing.

**And see the oracle warning on defect 5**, which applies here too: if this turns out to be
door-shaped, the diff that found it is measuring the wrong thing.

**Next step.** Read the restore dispatch for the end rows against `sprTabBaseS`, then reproduce
with `DEBUG_POS` at a location KC has actually seen it, rather than hunting positions blind.

---

## Delivered: DEBUG_POS, the position bookmark

Asked for 2026-08-14 alongside defect 5, built the same day once the level draw moved into bank 4
and freed the main RAM it was waiting on.

`DEBUG_POS` in `main.asm` prints, as hex along the top of the panel and rewritten every pass:

```
deck  plyX  posX  posY  mapHX  mapYr  line  numDoors  d0 col/row/state  d1 col/row/state
 01   0264  01D0  0050   0074   0A     00      00        00 00 00          00 00 00
```

Read it off the screen or a screenshot and poke the values back to return to a spot in one step.
Verified against RAM: the panel and zero page agree.

**Not compatible with `DEBUG_VSYNC`** — both write the top-left digit. `DbgPosOut` is in
`rupture.asm`; it borrows `swSrc`/`swDst`, which belong to the startup bank copy and are dead from
`LoadDeck` onwards.

If you would rather read RAM directly: `deck` &8B, `plyX` &2B, `posX` &27, `posY` &29, `mapHX` &80,
`mapYr` &86, `line` &24, `scrollS` &7E, `plyCX` &35, `plyCY` &37 (all zero page, 16-bit except
`deck`, `mapYr` and `line`); `numDoors` &1E7D, `doorCol` &1E61, `doorRow` &1E68, `doorState` &1E6F,
`doorDirty` &1E76, `tilemap` &3800; and in bank 4, which is the resting state, `doorDef` &A2FB and
`tiledefs` &8800. Take them from a fresh label dump after any build — they move.
