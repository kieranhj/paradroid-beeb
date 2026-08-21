# Layer 3 — Scroll ✅ DONE (3a–3d)

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

The decision point, and it is now decided: **CRTC hardware scroll over a circular strip, 4 px
horizontally and 1 scanline vertically, both axes vsync-locked at one step per frame.**

> **Superseded detail:** the panel described below as 5 rows at `&4800` became **4 rows at
> `&4A00`** in Layer 9 (the C64's status box is 32 scanlines, not 64 — see
> [`layer-9-hud.md`](layer-9-hud.md) §2a). The rupture mechanism is unchanged.

## 3a — Map browser ✅ DONE
Scroll the viewport by one character with Z/X/K/M; switch decks with UP/DOWN. Full-screen redraw
per step, no hardware scroll. Proves `DrawScreen` renders correctly from an arbitrary map origin,
which everything else depends on.

- `DrawScreen` generalised to a `(charX, charY)` origin. Map is 256 × 64 characters, viewport
  40 × 25, so the origin ranges 0–216 × 0–39.
- Row base is cheap because `tilemap` is page-aligned and 1K:
  `lo = (tileRow AND 3) << 6`, `hi = HI(tilemap) + (tileRow >> 2)`.
- Keys read with OSBYTE `&81`. Confirmed codes: Z `-98`, X `-67`, K `-71`, M `-102`,
  UP `-58`, DOWN `-42`. `*FX 4,1` stops the cursor keys doing cursor editing.
- Deck keys are **edge triggered**. A blocking wait-for-release deadlocks: hold UP before
  releasing DOWN and it spins forever, swallowing the press.
- Code moved to `&1100` (see memory budget) — 2K reclaimed.
- `CentreOnDeck` frames a deck on load. Decks sit at varying offsets in the 64×16 grid and are
  padded with empty tiles, so a (0,0) origin lands in blank space. Uses the **centroid** of
  non-empty tiles rather than the bounding box, because several decks are two clusters far apart
  and the midpoint of the extremes then falls in the gap. Division is by repeated subtraction —
  the quotient cannot exceed 63, and this runs once per deck change. Derived from the map itself,
  not the per-deck metadata tables, which hold side-view positions rather than map extents.

  *Honest limit:* on deck 0 the centroid lands within 2 characters of the bounding box, because
  its two clusters happen to balance near the same point. No single 40×25 viewport frames a
  34-tile-wide deck well; the centroid is kept because it degrades more gracefully — one outlying
  tile skews a bounding box badly and a centroid barely at all.

**Measured: a full-screen redraw costs ~466,000 cycles ≈ 11 frames** (30 scroll steps in 14M
cycles), so about 4 steps/second. `plot_char` dominates at ~256 cycles for its 16-byte copy;
unrolling the loop to drop `DEY`/`BPL` would take that to ~176. This is the number 3b has to beat.

## 3b — Hardware scroll + edge redraw ✅ DONE

**Play area verified against the C64: 9.5 × 4 tiles.** `DrawScreen` writes to `$4940` — `$140` past
the `$4800` screen base, so character row 8 — and draws 17 rows × 39 columns. That includes the
C64's one-character fine-scroll margin, so the *visible* area is 38 × 16 chars = 304 × 128 px.

**Rounded up to 10 × 4 tiles = 320 × 128** (KC's suggestion), because 10240 bytes is exactly 16 rows
of 640 and the BBC supports a 10K wrap natively — System VIA addressable latch lines 4 and 5 both
high select subtract `&2800`, restart `&5800`. Both axes then wrap cleanly. Rounding up rather than
down also avoids narrowing the play area.

**The buffer is a circular strip, not a flat grid.** Display cell *(row, unit)* lives at
`BUF_BASE + ((scrollS + row*640 + unit*8) MOD 10240)`.

The BBC CRTC gives a *one-dimensional* scroll through linear memory: a character leaving the left
reappears one row up on the right. Drawn as a flat 2D grid that is corruption — verified in the
emulator, and it scales with the offset (at 80 px, the right quarter shows the wrong rows). Treated
as a circular strip it is simply where the next column legitimately lives, and the cost collapses:

| step | scrollS | cells to redraw |
|---|---|---|
| horizontal, 4 px | ± 8 | 16 |
| vertical, 8 px | ± 640 | 80 |

versus ~640 characters for a full redraw.

**A MODE 1 CRTC unit is one byte per scanline = 4 pixels, and characters are already stored as two
8-byte halves — so a 4-pixel column is exactly one stored half-character.** No pre-shifted data is
needed for sub-character horizontal scrolling, which was the thing that looked expensive.

Source split into `screen.asm` (buffer addressing, `DrawHalf`, `MapChar`, `RedrawAll`),
`scroll.asm` (the four scroll directions) and `level.asm` (deck decode, charset, palette, framing).

**The main loop is released when the play area stops displaying, not at VSync.** The play area
occupies frame rows 8–23; the panel draws from `&4800`, so writing the play buffer while it shows
is safe. That makes the usable window rows 24 → 8 of the next frame — **24 rows**, against ~23 for
a worst-case redraw. Releasing at VSync (row 34) gave only 13 and was overrunning every step.

T1's three fires must land in different windows, which one period cannot do:

| Fire | Row | Job | Must be in |
|---|---|---|---|
| 1 | 3 | cycle 1 CRTC setup | rows 0–7 |
| 2 | 11 | cycle 2 CRTC setup | rows 8–15 |
| 3 | 24 | release the redraw | rows 24–26 |

So the latch is rewritten during fire 1. T1 reloads its counter at underflow, so a latch write
takes effect one reload later — fire 2 keeps the 8-row spacing while fire 3 moves out to 13.

**`SetCRTCStart` is called once, after all key handling, before any drawing.** Previously each
`Scroll*` routine parked the address itself, so on a diagonal the second one's park landed after
the first one's redraw — past frame row 3, where the IRQ latches R12/R13. The CRTC then used an
address missing one axis while the buffer held the combined position: one frame of wrong graphics
on the trailing edge. The routines now only set flags, and `DoRedraws` handles the drawing.

**Redraws run in raster order** — row 0 first (displays at frame row 8), then the columns (rows
8–23), then row 15 (row 23). A diagonal does two redraws in one window, so the tightest goes first.

**VSYNC synced, no OS calls in the main loop.** R12/R13 form a 14-bit value across two writes; if
the CRTC samples between them the display shows one frame at a half-updated address. `WaitVSync` at
the top of the main loop puts both writes and the edge redraw in the blanking window, and paces
scrolling to one step per frame.

Two OS calls were replaced with direct hardware:

- **Palette** — writes `&FE21` instead of `VDU 19`. The register takes
  `(logical << 4) | (physical EOR 7)`, and the logical field is a content-addressable match: in a
  4-colour mode only bits 7 and 5 are compared, so bits 6 and 4 must be written in **every**
  combination or the colour comes out split. `SetPalette` writes all 16 entries, mapping each back
  with `logical = ((n AND 8) >> 2) OR ((n AND 2) >> 1)` — four entries per logical colour.
- **VSYNC** — `IrqHandler` sits at the head of `IRQ1V`, counts fields and chains on to the OS, so
  its timers and keyboard scan keep working. Polling `&FE4D` bit 1 directly would race the MOS,
  whose own handler clears that flag when it services vsync.

Verified: palette output identical to the `VDU 19` version, and horizontal scrolling still measures
exactly 10 steps in 10 frames.

*Still an OS call:* `keydown` uses OSBYTE `&81`, once per key per frame. Replacing it means driving
the System VIA keyboard matrix directly, which contends with the MOS's own scan in its IRQ handler
— worth doing alongside the eventual full IRQ takeover rather than piecemeal.

**Verified:** both axes scroll coherently with no shear or row-bleed. Step rate measured over 10
frames with the key held:

| | steps in 10 frames | cost |
|---|---|---|
| horizontal, 16 cells | **10** | 1 frame/step — vsync-locked |
| vertical, 80 cells | **4** | ~2.5 frames/step — overruns the frame |

## Vertical scroll optimisation ✅ — both axes now frame-locked

Two changes, and the first was much less useful than predicted:

**1. `SetCell` loop → lookup tables** (`rowMulLo/Hi`, `unitMulLo/Hi`). It previously added 640 in a
loop: for `DrawRow` a constant 15 iterations × 80 cells, ~1200 redundant 16-bit adds. Vertical went
4 → **5** steps per 10 frames. Real, but small — `SetCell` was *not* the dominant cost, so that
diagnosis was wrong.

**2. `DrawRow` rewritten to hoist per-row constants.** `cellY` does not change across a row, so the
tile-map row base and sub-row offset are fixed; the tile pointer only moves every 4 characters; and
crucially **the character code is fetched once per pair of units**, because a character is two
4-pixel halves — 40 lookups instead of 80, with the right half just `chp + 8`. `DrawRow` no longer
calls `DrawHalf`/`MapChar` at all, and reuses their zero page. Vertical went 5 → **10**.

| | steps in 10 frames | |
|---|---|---|
| horizontal, 16 cells | 10 | unchanged |
| vertical, 80 cells | **10** | was 4 |

**The lesson worth keeping:** because vsync quantises to whole frames, a step costs 1 frame or 2
with nothing between. Vertical was never 2× too slow — it was a few thousand cycles over the line,
which is why the small first fix moved nothing and the second moved everything.

## ~~⚠ KNOWN DEFECT — `DrawRow` corrupts the row it draws~~ — MOOT, routine deleted in 3d

**Broader than first recorded.** It was characterised as "unit 39 onward, after an *odd* offset".
Both halves of that are wrong: a diagonal-scroll diff found it corrupting **units 2–78 with
`mapHX` = 134, an even offset**. Every column and every other row matched a full redraw exactly, so
`DrawRow` alone is at fault — verified against `RedrawAll` *and* independently against the tile map.

Diagonal movement calls `DrawRow` on every step, which turns an occasional artifact into a
permanent one on the trailing edge.

**`DrawRow` has now produced three separate bugs**: uninitialised `chp` on odd row starts (fixed),
corruption from unit 39, and this. Each time the conversion looked right and the fault was in its
incremental state tracking.

**Recommended fix: revert `DrawRow` to the pre-optimisation version.** That one diffed byte-clean
twice. The cost was vertical scrolling at 2 frames/step rather than 1 — but the draw window has
roughly doubled since that measurement (release moved from VSync to frame row 24), so it may now
fit at 1 frame regardless. If the optimisation is redone, drive the diff harness over odd *and*
even offsets on both axes from the outset.

**Testing lesson.** Two earlier runs of that harness reported 0 differing bytes and were worthless:
both used an even number of horizontal steps (30 and 300), so `halfSel` was always 0 and the odd
path never executed. The harness was sound; the inputs never reached the failing case. Any future
scroll test must cover odd and even offsets on both axes.

## Bug: corrupted graphics that scrolling revealed but did not cause

`DrawHalf` computed `halfX >> 1` by shifting `halfX+1` in place and "restoring" it with `ASL`.
`LSR` then `ASL` only restores a value whose low bit was 0, so whenever `halfX+1` was 1 it came
back as 0.

`DrawColumn` recomputes `halfX` from `mapHX + uCount` every cell and was immune. Only `RedrawAll`,
which sets `halfX` once and increments it across the row, was affected — so the damage was written
**at deck load** and then persisted indefinitely, because incremental scrolling only redraws the
edges and never repairs the interior. Scrolling exposed it rather than caused it.

Triggers when `mapHX + 79` crosses 256 — **decks 2 and 14**, both centring at `mapHX` = 180.

*Diagnostic worth keeping:* a debug key (SPACE) forces `RedrawAll`, so the incremental buffer can be
diffed against a full redraw at the same position. Both then matched byte-for-byte — after
right/down/left, and after scrolling to the extremes with the buffer wrapping repeatedly — which
proved the scroll logic correct and pointed at the load-time draw instead.

*Not a bug:* the large flat areas on some decks are genuine. Empty tiles (index 0) are all
character 0, which renders as solid background. Verified against the tile map.

`DrawColumn` still uses the general `DrawHalf`/`MapChar` path. It only touches 16 cells and already
fits in a frame, so it was left alone — but the same hoisting applies if the sprite blitter later
squeezes the budget (`halfX` is constant down a column, so the character and tile lookups are
constant too; only the row base changes).

## 3c — Vertical rupture: static panel + scrolled play area ✅ DONE

Two CRTC cycles per TV frame. Reprogramming R4 mid-frame ends a cycle early; the next cycle
reloads VMA from R12/R13, so each cycle has its own screen start.

| Cycle | Content | R4 | Rows | R6 | R7 | R12/R13 |
|---|---|---|---|---|---|---|
| 1 | static panel | 7 | 8 | 5 | 255 (suppressed) | `&4800 / 8` |
| 2 | scrolled play area | 30 | 31 | 16 | 26 | `(&5800 + scrollS) / 8` |
| | | | **39 ✓** | | | |

Cycle 1 shows 5 rows of panel then 3 blank — the same title-plus-gap the C64 has above its play
area. `Σ(R4+1)` must total 39 rows / 312 scanlines or the picture rolls.

**Consistency check:** VSync lands at frame row `8 + 26 = 34`, which is MODE 1's default R7, so the
TV sees an identically phased frame and stays locked.

**Staging: System VIA T1 in CONTINUOUS mode, and we own IRQ1V outright.**

T2 was the wrong timer. It is one-shot only, so the interval starts when the handler writes
`T2C-H` — every interrupt's service latency feeds straight into the next interval and jitter
accumulates. T1 continuous auto-reloads from its latch at underflow, so the period is exact
however late we are serviced. VSync restarts it, keeping the stages phase-locked to the frame.

Nothing is chained on to the MOS either, so its handler never runs ahead of ours adding latency.
The cost is the MOS 100 Hz tick, and with it MOS sound. Keyboard still works (OSBYTE `&81` scans
the matrix directly) and the filing system is only needed before we take over — hence `*LOAD` now
runs *before* `InstallIrq`.

Both VIAs have every interrupt source disabled except System VIA CA1 and T1; anything unserviced
would hold the IRQ line asserted forever. The MOS saves the interrupted A in `&FC` but not X or Y,
so the handler saves those itself.

One period = 8 char rows, giving a three-state machine on the IRQ:

1. **VSync (CA1)** — inside cycle 2, five rows from its end. Latch R12/R13 = panel. Arm T2 for
   2560 ticks.
2. **T2, inside cycle 1** — set R4/R6/R7 for the panel, queue R12/R13 = play area. Arm T2 for
   4096 ticks.
3. **T2, inside cycle 2** — set R4/R6/R7 for the play area. Wait for VSync.

Timing is generous: the interrupt only has to land inside its cycle before `C4` reaches the target
R4. (The `C0<2` write window quoted for R4 applies to single-scanline RVI work, not here — KC.)

**Both waits deliberately overshoot the boundary by 3 rows.** Sizing them to reach the boundary
exactly is what glitched: IRQ latency alone carried them over, so any jitter fired them in the
*previous* cycle, where writing that cycle's R4 breaks the field. Overshooting costs nothing — the
deadline is `C4` reaching the old R4 (7), so arriving 3 rows in leaves ~4 rows of slack either side.

**`DEBUG_RASTER` build flag** tints the background at entry to each interrupt — magenta at VSync,
green at cycle 1, the deck's real colour at cycle 2 — so the scanline each one lands on is visible
and the band boundaries *are* the interrupt points. This is what diagnosed the margin problem;
reasoning about it from the timing numbers had led me the wrong way. Set `FALSE` for a clean
picture.

`SetCRTCStart` no longer writes R12/R13; it computes the address and parks it for the IRQ, with
`SEI` around the store so the IRQ can't read a half-updated pair.

**Interlace must be off — `R8 = 0`.** The OS leaves MODE 1 at `R8 = 1`, *interlace sync*, which
offsets VSync by half a scanline on alternate fields. The rupture timers are fixed intervals from
VSync, so that half line lands the split in a different place every other field — an intermittent
glitch along the top of the play area. Non-interlaced is what a game wants anyway.

**Verified:** panel holds position exactly while the play area scrolls on both axes, and
consecutive fields render identically with interlace off.

*Placeholder:* the panel is a bordered box, not artwork. Real title/HUD content is a later layer.

*Known limitation:* the panel shares the play area's 4-colour palette, so its colours change with
the deck. Fixable by reprogramming the palette at the cycle boundary — we are already in the IRQ
there — but that needs the panel's colour needs settled first.

## Scroll model — decided (reference)

Wide virtual buffer, CRTC R12/R13 hardware scroll. Horizontal granularity is **4 pixels**, not 8. CRTC R12/R13 addresses in 8-byte units, and a MODE 1
character cell is 16 bytes (8 px × 2bpp = 2 bytes/row × 8 rows), so one CRTC increment is half a
cell:

| Mode | bytes/char cell | 1 CRTC unit |
|---|---|---|
| MODE 0 | 8 | 8 px |
| MODE 1 | 16 | **4 px** |
| MODE 2 | 32 | 2 px |

4 px = 1/80 of screen width, and exactly 2 logical C64 multicolour sprite pixels. This may be smooth
enough unaided — that is what the spike measures.

To compare:
- 4-px horizontal (CRTC only) vs. 1-scanline vertical (R4/R5/R12 trick) vs. flip-screen.

**Parked option — 2-px horizontal, Master only.** A second buffer holding the map offset by 2 px,
alternating which one is displayed. Superseded by [Master-only extensions](master-extensions.md) — see there for this
document, which corrects this note: the obstacle on a Model B is not "no room for the second buffer"
but that a circular strip's period must equal the hardware wrap span and there is only one such
region. On a Master both buffers live at the *same* address in main and shadow RAM, so the wrap is
shared and the switch is one ACCCON bit.

## 3d — Smooth vertical scroll, 1-scanline granularity ✅ DONE

Vertical steps drop from 8 scanlines to 1. Reference: `llm-beeb-wiki`
`techniques/smooth-vertical-scroll` and its source, Talbot-Watkins's retrosoftware tutorial.

**The lever is R5 (vertical total adjust).** R5 appends 0–31 extra scanlines to the end of a CRTC
cycle. Give the playfield cycle `R5 = line` and take those scanlines back from the cycle above it
(`8 - line`), and the frame total stays at 312 so the TV never unlocks. The playfield cycle then
*starts* `line` scanlines earlier, so at any fixed physical scanline the raster is `line` lines
further into the buffer — the picture has scrolled down by `line`.

Two consequences fall straight out of that, and they are the whole cost of the technique:

- **The first `line` scanlines of the playfield cycle are real, displayed, and wrong** — as is the
  tail. Both must be blanked, and it is the blanking, not R5, that pins the visible edges to fixed
  scanlines. Blank via **CRTC R8's display-skew bits** (`&30` = display disabled, `&00` = on): the
  chip's own display enable, so there is no ULA serialiser artefact at the transition.
- **The playfield needs 17 rows of data resident and we have 16.**

### The 17th row, and why it costs nothing

`BUF_SIZE` = the 10K hardware wrap is load-bearing — that equality is what makes the display wrap.
It cannot grow: the only other wrap span divisible by 640 is 20K, which would swallow `&3000-&47FF`
where the level data and panel live.

We do not need a 17th row. Display row 16 wraps to buffer row 0, and the two only ever show
**disjoint scanlines** of it, so buffer row 0 holds two map rows at once:

| buffer row 0 | holds |
|---|---|
| scanlines `line..7` | map row `mapYr` — the top of the view |
| scanlines `0..line-1` | map row `mapYr+16` — the bottom sliver |

Work a step through and it collapses to something uniform, with no special case where the buffer
wraps a row:

| | action |
|---|---|
| down 1 scanline | write scanline `line` of buffer row 0 from map row `mapYr+16`, *then* advance `line`/`mapYr`/`scrollS` |
| up 1 scanline | retreat `line`/`mapYr`/`scrollS`, *then* write scanline `line` of buffer row 0 from map row `mapYr` |

When `line` wraps and `scrollS` moves a row, the row that was split becomes a full row — and the 7
scanlines it needs are already correct. The one scanline just written completes it.

**A scanline strip is 80 bytes against 640 for `DrawRow`.** Per 8 scanlines travelled that is the
same copying, spread evenly instead of lumped into one frame — the opposite of the current problem,
where a vertical step is the worst spike in the frame.

### Frame layout — three cycles, not two

Two cycles would leave the variable adjust between VSync and the panel, sliding the panel up to 7
scanlines while scrolling. Three cycles put both variable adjusts *after* the panel, where they
cancel:

| Cycle | Content | rows (R4) | R6 | R7 | R5 | R12/R13 |
|---|---|---|---|---|---|---|
| panel | static | 7 (6) | 5 | 255 | `8 - line` | `&4800 / 8` |
| play | scrolled | 18 (17) | **16** | 255 | `line` | `(&5800 + scrollS) / 8` |
| tail | nothing, holds VSync | 13 (12) | 0 | `TAIL_R7` = 4 | 0 | — |
| | | **38 ✓** | | | **+8 ✓** | |

`38 × 8 + 8 = 312`, confirmed by counting VSyncs: **1000 fields in 39,936,000 cycles, exactly.**
With `P` = start of the panel cycle: the play cycle starts at `P+64-line`, the visible top edge is at
`P+64` and the bottom at `P+184`, and VSync lands at `P+240`. It landed at `P+272` until
`FRAME_DROP_ROWS` moved it four rows earlier to push the picture down the tube — see the section
at the end of this file.

**18 cycle rows rather than 17 is deliberate.** It makes row 16 non-displayed, so display-enable
turns off by ordinary means and we never depend on the murky "R6 > R4" behaviour where the VADJ
scanlines themselves are displayed.

### The play area is 15 rows, not 16 — and that is a hard limit

`R6 = 17` was the original design: 16 rows plus the wrapped sliver. It cannot work, and the reason is
worth keeping.

**The display window must fit inside ONE hardware wrap.** The address translator subtracts its
mode-dependent amount once, when MA12 goes high (IC 39, see `hardware/address-translation`) — it
does not iterate. 17 rows is 10880 bytes over a 10240-byte wrap span, so past `scrollS = 9608` the
bottom rows need a second subtract, do not get one, and fetch from `&8000` upwards. ROM, displayed
as garbage across the bottom row — and only at some scroll positions, which is why it read as
intermittent.

Confirmed exactly: at `scrollS = 10200` the model predicts garbage from unit 5 of the bottom row
onward, and that is where it starts.

The strip period must equal the wrap span, and 10240 bytes with 80-unit rows is exactly 16 rows. So
**16 displayed rows is the ceiling, and smooth vertical scrolling costs one character row of play
area**: 16 displayed, 15 visible (120 px), the 16th carrying the sub-row fraction at both ends.
Nothing else changes — the split-row scheme is untouched, because the scanlines it writes are
precisely the ones falling outside the visible window.

*Parked ways to get 128 px back, neither cheap:* the 20K wrap (`&3000`, 32 rows) has room for a
17-row window, but the whole of `&3000-&7FFF` becomes screen and the strip sweeps the panel; or
switch the addressable-latch wrap bits per cycle in the IRQ, which is feasible — we are already in
there four times a frame — but needs thought about where the panel then lives.

### R5 write ordering

R5 is sampled at each cycle's *end*, so it must read a different value at three points in the frame.
Each write has to land in the gap between the sample it must not disturb and the one it serves:

| must read | at | so write it |
|---|---|---|
| `0` | `P+312` (tail end) | at VSync, `P+240` |
| `8 - line` | `P+56` (panel end) | at fire 1, `P+44` |
| `line` | `P+200` (play end) | at fire 2, `P+64` |

R4/R6/R7 are **not** latched, so each cycle's values must be written *inside* that cycle, after it
starts and before `C4` reaches the new R4. That is why the tail cycle's own registers are written at
VSync (tail row `TAIL_R7`) rather than earlier. **R7 is the exception and no longer
follows that rule:** it is written at VSync for the *panel* cycle, because at `TAIL_R7` = 4 a
7-row panel cycle would otherwise reach the stale value and fire a VSync of its own.

### IRQ schedule

| Event | Position | Actions | Tolerance |
|---|---|---|---|
| VSync (CA1) | `P+240` | R8←on; R5←0; tail R4/R5; **panel R6 and R7**; R12/R13←panel; `iline←line`; restart T1 | ~72 rows |
| T1 fire 1 | `P+44` | R8←blank; R5←`8-iline`; panel R4, play R6; R12/R13←play | 8 scanlines |
| T1 fire 2 | `P+64` | R8←on; R5←`iline`; play R4/R6/R7 | **1 scanline** |
| T1 fire 3 | `P+192` | R8←blank; `drawFlag`←1 | **1 scanline** |

T1 stays free-running continuous and is restarted only at VSync, so the three fires share one
jitter offset rather than accumulating three. Intervals are set by writing the latch one fire ahead,
as in Layer 3c.

Fires 2 and 3 must land in **horizontal blanking** — MODE 1 displays 80 of 128 character times, so
there are ~24 µs of blanking to hit and a write landing in the displayed portion cuts that scanline
part-way across. `T1_TUNE` exists to be calibrated against `DEBUG_RASTER`, exactly as the reference
implementation carries an empirically tuned constant for the same reason.

Nice side effect: `drawFlag` now fires at `P+192`, the exact scanline the play area stops
displaying, rather than the row-24 estimate — 15 rows of draw window, and no longer a guess.

### When each CRTC register may be written — they are not the same

This cost two wrong builds. The rules that actually hold:

| Register | Write it | Symptom of getting it wrong |
|---|---|---|
| R4 | inside its own cycle, before C4 reaches the new value | previous cycle trips over it |
| R7 | inside the **previous** cycle | that row's compare has already happened, **VSync never fires**, and the CRTC free-runs on the last cycle shape — the play area repeats down a rolling screen |
| R6 | inside the **previous** cycle | vertical display enable is a flip-flop cleared on match; raising R6 afterwards does not bring the cycle's display back |
| R12/R13 | inside the **previous** cycle | latched at cycle start |
| R5 | anywhere before the cycle's end — but see below | |

**The R5 trap, and it is a nasty one.** The vertical adjust counts up and compares against R5.
Change R5 once the count has passed the new value and the match never happens: the adjust runs on
until the 5-bit counter wraps, adding ~29 scanlines. Fire 2 sits within a scanline of the panel
cycle's adjust ending, and landing the wrong side of that boundary stretched the panel cycle from 64
scanlines to 85 — which presented as the play area starting 21 scanlines late and being 21 short.

The fix is not tighter timing, it is **not writing R5 anywhere near a cycle boundary**. Its legal
window is the whole cycle, so the play cycle's R5 moved to fire 3 and fire 2 now writes only R4 —
which is safe on both sides of the boundary, because written during an adjust it simply waits for
the next cycle.

### Calibration — `T1_TUNE = -6 * SL - 22`

Two components, measured separately.

**The scanline part, `-4 * SL`.** The VSync CA1 interrupt is serviced about **4 scanlines** after the
vsync edge, so every fire needs shifting back by that much. The timer chain itself is exact —
breakpoint bisection puts fire 1 at 78.3–79.3 scanlines after VSync handler entry against a design
figure of 78 — so the whole error is in where VSync itself sits.

This started at `-6`, which put fire 2's unblank at `P+62` instead of `P+64` and exposed two
scanlines of the *next* map row above the top of the view. **Erring late is harmless** — it just
starts the view a couple of scanlines further down the map — **but erring early shows content that
belongs at the bottom of the window at the top of it.** Bias late if in doubt.

Note the scanline component cannot be measured from screenshots to better than ±2: one scanline is
2 framebuffer pixels and the panel gives only ~2.0–2.05 px/scanline depending on how its edges are
read. It was KC spotting two wrong lines on b-em that pinned it, not any measurement here.

**The sub-scanline part, `-22` µs.** An R8 write takes effect immediately, so one landing in the
displayed part of a scanline cuts that scanline part-way across. MODE 1 displays 80 of 128 character
times, so the write has to land in µs 40–63 of the line before the one whose display should change.

Measuring the phase needed a trick, because the play area's edges cannot show it — one scanline is
2 framebuffer pixels, and jsbeeb crops each screenshot to its own content bounding box so builds are
not even to the same scale. **`T1_PROBE`** drags fire 1 back into the panel's *displayed* rows and
hands the time straight to fire 2, so fires 2 and 3 stay put and only the blank moves. The blank
then cuts the solid panel box, and the horizontal position of the step is the phase, read straight
off a screenshot: the step sat at 9 µs into the 40 µs of display. `-22` µs puts fire 1's write at
µs 51, fire 2 at ~53 and fire 3 at ~55 — they differ by the length of `RuptTimer`'s dispatch, which
is well inside the 24 µs window. The probe then shows a clean full-width cut, which is the
confirmation.

Keep `T1_PROBE` — it is the only phase measurement that has worked, and any change to the IRQ
prologue will need it again.

### Build order

Each step verified in the emulator before the next:

- **(b)** three-cycle rupture, `line` fixed at 0 — measured panel 40 scanlines, gap 24, play area
  128: identical to Layer 3c ✅
- **(c)** `line` swept 0–7 by poking the variable from the emulator — no debug keys needed. Content
  moves one scanline per step, both edges rock steady ✅
- **(d)** split-row scanline writer wired to K/M ✅

Step (a) — proving the R8 skew blank standalone — was skipped on KC's call. It would not have caught
either bug: R8 behaved exactly as documented, and both faults were in R5/R6/R7 timing.

### Verified

Buffer diffed byte-for-byte against `RedrawAll` at the same position, which is the only check that
has ever caught a drawing bug in this project:

| test | result |
|---|---|
| 8 steps down, even `mapHX` | 0 / 10240 differing |
| 8 steps up (through the row borrow), even `mapHX` | 0 / 10240 |
| mixed right / up / down, **odd** `mapHX`, `scrollS` wrapped mid-row | 0 / 10240 |
| as above, re-run after deferring the draw (exercises the down-wrap `scanRow`) | 0 / 10240 |
| diagonal right+down, **`line` = 3** — the split row is live | 0 / 10240 |
| diagonal left+up, **`line` = 3** | 0 / 10240 |

Step rate measured at **1 scanline per frame**, vsync-locked, on both axes.

*Testing trap worth remembering:* an earlier run of this harness reported 16 differing bytes, all on
one scanline of the split row. That was not a bug — `run_for_cycles` had stopped the emulator
mid-`DrawScanline` and the snapshot caught a half-written strip. Always idle a few frames after
releasing a key before dumping.

### The position pair must be latched atomically — and drawn after, not before

Reported by KC: scrolling **up**, the screen jumped a row for one frame every 8 scanlines; scrolling
**down**, a couple of wrong lines showed at the top. One root cause, and the asymmetry is the clue.

The scroll routines drew their scanline strip *inline*, before `SetCRTCStart` parked the address.
The strip costs ~75 scanlines, which pushed the park past VSync — where `iline` was being latched.
`line` and `scrollS` are one position between them, and they were being consumed by different
frames: the display would show an address from one frame with a sub-row offset from the next, a
position that never existed.

`ScrollUp` changes both *before* its draw, so at every row borrow the pair split — a one-frame row
jump. `ScrollDown` changes them *after*, so only the freshly written scanline was exposed at the top.
Same bug, two faces.

Two fixes, both worth having:

- **The scanline draw is deferred to `DoRedraws`**, like the columns, so the park happens first. This
  also removes a subtler artefact: drawing before the park writes content for the *next* frame's
  position into a scanline the *current* frame still displays.
- **`SetCRTCStart` parks `line` alongside `crtcHi`/`crtcLo` under the same `SEI`**, and fire 1 latches
  `iline` from that park rather than VSync reading the live value. The pair is now consumed at one
  instant, so a long frame can only ever be a frame late — never inconsistent.

Deferring meant K and M could both record into one draw slot, with a scanline number belonging to a
strip position that no longer exists, so **up and down are now mutually exclusive** in the main loop.
Net movement with both held is zero anyway.

### Anything that writes a whole cell into display row 0 must respect the split

Reported by KC: diagonal scrolling leaves mess behind.

`DrawColumn` writes all 8 scanlines of every row it touches, including display row 0 — which is the
split row. Scanlines `0..line-1` there belong to map row `mapYr+16`, and a column redraw was
overwriting them with `mapYr`. Those scanlines are **invisible at the time**, so nothing shows until
`line` wraps and that row rotates round to the bottom of the window — which is why it looked like
mess being left behind rather than a column being drawn wrong.

`DrawColumn` now re-writes scanlines `0..line-1` of its display-row-0 cell from `mapYr+16` after the
main loop, via `DrawHalfPart`. One cell, up to 7 bytes.

**`RedrawAll` had the same blind spot**, which is why the diff oracle had only ever been valid at
`line = 0`. It now applies the same repair across all 80 units, so a full redraw is correct at any
scroll position — and the incremental scrolling can be diffed against it at any value of `line`,
which is where these bugs actually live.

*Testing trap, cost an hour:* the first run of that diff reported 72 bytes differing on exactly the
split scanlines, and the natural reading was that the fix had not worked. It had — the **oracle**
was being sampled mid-redraw. `RedrawAll` plus its split pass runs longer than the 400,000 cycles
being allowed to settle, so the dump caught display row 0 rewritten by the main loop but not yet
repaired by the split pass. Allow 1,500,000 cycles after releasing SPACE. Confirmed by breakpointing
`ra_nosplit` and reading the buffer there: correct at the end of the routine, wrong in the middle.

Vertical scrolling no longer redraws whole rows, so `DrawRow`, `FetchChar` and `SetTilePtr` have
been deleted. The defect recorded above — three separate bugs in that one routine's incremental
state tracking — is moot rather than fixed. `DrawColumn` still uses the general
`DrawHalf`/`MapChar` path and is unaffected.

### Open questions

- **When to switch the CRTC into the rupture, and how not to lose the TV's lock.** *(KC,
  2026-08-21.)* `SetupRupture` rewrites R4, R5, R6 and R7 from `SetupMode`'s plain 39-row frame to
  the three-cycle shape, and it does it wherever the CPU has got to. A real television needs
  several fields to pull vertical sync back afterwards, so the way into a game — and the way back
  after a game over — rolls or tears for a moment. Three things to try, in rough order of promise:
  switch **on a field boundary** rather than mid-frame; **order the writes so every intermediate
  state is still a legal 312-line frame**, rather than passing through one that is not; and
  **blank the display across the change** so whatever the beam does is not visible. All three have
  to respect what is already known and written down above — R6, R7 and R12/R13 belong to the cycle
  *before* the one they fire on, R5 must not be touched near a cycle boundary (its 5-bit wrap costs
  ~29 scanlines), and R7 must not be sitting at `TAIL_R7` while a filing-system call runs, because
  that stops VSync and hangs the 8271 poll. **None of this is measured yet** — it wants the
  emulator and then real hardware, since a TV's tolerance is the thing being tuned.
- **Granularity.** 1 scanline vertical against 4 pixels horizontal is a lopsided pair. Stepping
  vertical by 2 or 4 scanlines costs nothing extra (identical machinery) and may feel better.
  *(Settled 2026-08-21: 1 scanline stays. Kept here for the reasoning.)*
- **Source-pointer cache.** A scanline strip still does 40 character lookups for 80 bytes copied, so
  lookups dominate. Caching the current source row's 40 pointers (80 bytes, rebuilt every 8
  scanlines) makes a strip a straight indexed copy. That is the difference between smooth scrolling
  costing *less* than today's row draw and costing ~2.5× more at full speed.

## Where the picture sits on the tube — `FRAME_DROP_ROWS`, 2026-08-21

The rupture's three cycles put the panel and the play area at a fixed place in a 312-scanline
frame, and where that lands on the screen is decided by one thing: **where VSync falls**. The set
locks to VSync and counts down from it, so moving VSync *earlier* in our frame moves the picture
*down*. Nothing else changes — the frame is still 312 lines and the three cycles are untouched; all
that moves is how the 120 scanlines of blanking are split between the front porch (picture bottom →
VSync) and the back porch (VSync → panel top).

`FRAME_DROP_ROWS` in `main.asm` is that number, in character rows. **KC, 2026-08-21: four**, the
picture having sat high with the black stacked under it. `TAIL_R7` becomes `8 - FRAME_DROP_ROWS`,
so VSync moves from `P+272` to `P+240` and the panel top from 40 scanlines after VSync to 72.

**Two constants move together, which is why they are one.** The T1 chain is restarted at VSync, so
every fire in the frame is measured from it: `T1_I1 = (84 + FRAME_DROP_ROWS * 8) * SL - 2 + T1_TUNE`.
Shift VSync without shifting `T1_I1` and the whole rupture arrives 32 scanlines into the wrong part
of the frame.

### The trap: R7 = 255 had to move to VSync

`R7 = 255` — no VSync in the panel or play cycles, only in the tail — was written at **fire 1**,
`P+44`. That is row 5 of the 7-row panel cycle, so for the first five rows of every frame R7 still
held the tail's value. It was harmless only because that value was **8**, and a 7-row cycle can
never reach row 8.

At `TAIL_R7 = 4` it is not harmless. The panel cycle reaches row 4 at `P+32`, twelve scanlines
before fire 1, and fires **a second VSync of its own**. That re-enters `RuptVSync` mid-frame, which
restarts T1 and zeroes `ruptState`, so fire 1 never runs, the play cycle is never set up or
unblanked, and the symptom is the panel sitting alone on a rolling picture with the **play area
completely black**. Found by building it, not by reasoning about it.

The fix is the file's own rule, applied properly: R7 belongs to the *previous* cycle, and the tail
cycle is the panel's previous cycle. `RuptVSync` writes it, 72 scanlines before the panel starts.
The tail's own VSync has already fired by then — that is why we are in the handler — and the 6845
counts the pulse out of R3 independently of R7.

**So `TAIL_R7` may not be raised back above `PANEL_CYC_ROWS` and left there carelessly**: the code
is now correct for any value, but the *reason* fire 1 used to get away with it is gone.

### What did NOT move: the title

The title screen runs under `SetupMode`'s ordinary MODE 1 frame, not the rupture, so
`FRAME_DROP_ROWS` does not touch it and it now sits about two rows higher than the game does.
Matching it is **not** a matter of dropping its R7 by four: the OS frame is `R6 = 32`, `R4 = 38`,
`R7 = 34`, which leaves only two rows of blanking between the end of the display and VSync — take
R7 below 32 and VSync fires inside the displayed rows. Moving the title down means drawing its
artwork lower in its own framebuffer, which is `title.asm`'s business and has not been done.
