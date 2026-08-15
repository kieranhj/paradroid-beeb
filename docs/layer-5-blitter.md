# Layer 5 — blitter optimisation

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

Done before the droids went in: seven slots at the Layer 4 cost did not fit in a frame.
The droid movement half of Layer 5 is still open — see [`../PLAN.md`](../PLAN.md).

Seven slots at the Layer 4 cost do not fit in a frame, so the blitter is being cut down first. Four
steps, in dependency order:

1. **Save area into screen geometry** — done (`3f69b4d`). `(svp),Y` with the same Y as `(bufp),Y`.
   Cycle-neutral in itself; its point is that it makes compilation *possible*, since a compiled
   blitter cannot poke a save address into each of its ~72 stores.
2. **Compile the rotor** — done. Rows 0–4 and 15–19 are generated 6502 in the data bank, with the
   pixels and masks baked in as immediates.
3. **Compile the digits** — done, but it bought less than half what was projected. See below.
4. **Frame lock to 25 Hz** — done. `FRAME_LOCK = 2` in `main.asm`; `WaitVSync` consumes two fields
   an iteration instead of one, so one pass of the loop is one C64 GameLoop iteration.

   | loop iterations per 100 fields | free-running | locked |
   |---|---|---|
   | player only | 101 (50 Hz) | 50 (25 Hz) |
   | player + 6 droids | 80 (40 Hz) | 50 (25 Hz) |

   Free-running was the worse option and it took the test droids to show why: the loop does not fit
   in a field with a full pool, so it stretched to 1.25 fields and **the player moved 20% slower
   with droids on screen than without**. Speed that depends on what is visible is a worse fault
   than speed that is merely chunkier.

   Real-time speed is unchanged — `PLY_ACCEL`/`PLY_DECEL`/`PLY_MAXSPD` now scale by
   `FRAME_LOCK / PLY_ITER_FRAMES`, which cancels at 2 and 2, so the C64's own per-iteration
   constants apply unmodified. Confirmed in the emulator: `xSpd` tops out at `&0700`, 7.0 px per
   iteration, the same 175 px/s as 3.5 px/field at 50 Hz. What is given up is the extra smoothness
   the 50 Hz sampling bought — that was always a bonus over the original, not a requirement.

5. **Round-robin updating** — **dropped, on measurement.** It was the step that bought the pool
   its headroom when seven sprites cost 68K of an 80K pass. They now cost 40.7K and the loop
   spends **39,212 of its 79,872 cycles idle — 49% of the pass** (T1 around `WaitVSync`, seven
   sprites live, averaged over 127 passes). There is nothing left to buy. See *Why not
   round-robin* below before reviving it.
6. **Raster-ordered updating** — flicker, and probably `BUGS.md` #3 with it. Still open, and now
   the only sprite-pool work outstanding. **The mechanism is now measured rather than assumed** —
   see *Where the sprite work actually lands* below, which also rules out the cheap version of the
   fix.

**Measured, one sprite, one frame** (User VIA T1 around the two calls; both builds at the same
position; ±0 across repeats — the emulator is deterministic):

| | before | after | |
|---|---|---|---|
| `SprRestoreAll` | 3,490 | 3,506 | +0.5% |
| `SprDrawAll` | 10,508 | 7,142 | **−32%** |
| total | 13,998 | 10,648 | **−24%** |

The draw is where compiling pays: the rotor averages **3.2 opaque bytes of 7**, and a compiled row
costs nothing for the transparent ones, where the interpreted path pays 26 cycles to fetch and 27 to
blit each of the seven regardless.

**Restore came out flat, and that is not a disappointment — it is arithmetic.** Copying seven bytes
back costs 91 cycles; the compiled form costs 13 per saved byte plus ~49 to dispatch, which at 3.2
bytes is 91 again. It is kept because the alternative is worse: an interpreted restore would force
the *draw* to save all seven columns, and that costs the draw more than the restore saves.

Seven sprites at 10,648 is 74.5K against a frame of 80K, so this step alone does not buy the pool —
step 3 has to. It does prove the addressing, which was the risk.

**Cost in the bank:** 3,159 bytes of generated code and tables, so `SPR_SHIFT2` moved `&A800` →
`&B000` and the bank now ends at `&B6CF` of `&C000`. The staging assert had to be relaxed with it:
`PARADAT` is now 48 pages and overruns the panel, the mask table and the bottom of the play buffer,
which is safe because `PageDataIn` is the first thing after the load and everything above it is
rewritten before it is next read. Boot shows a moment of garbage in the play area.

**Verification.**
- The generator is checked against the interpreted path in Python: for all 8 phases × 21 rows × 2
  shifts the compiled row is the row `drOfs` would have fetched (320 rows, 0 mismatches), and for
  every distinct row over eight background patterns the compiled writes equal the interpreted
  writes and the compiled restore undoes them exactly.
- In the emulator, after full-speed diagonal scrolling, disabling the sprite and letting it restore
  leaves the play buffer **byte-identical to a forced `RedrawAll` across all 10K** — 0 diffs.
  (Run this at `line == 0`; at `line != 0` the oracle itself is wrong — `BUGS.md` #1.)

## Step 3, the digits — and why it under-delivered

**The digits are dense where the rotor is sparse: 42.7 opaque bytes of 56 against 3.2 of 7.** So
almost nothing is saved by skipping transparent bytes; the whole win is deleting `SprFetchRow`.

Per-TYPE compiled code is ~1,012 bytes and 24 types is 25K, which does not fit. But the number is
three independent 8-pixel glyphs and there are only ten glyphs, so **ten routines cover all 24
types** and the three positions are reached by offsetting `bufp` by 0/16/32 rather than by
generating three copies. Nothing is generated at run time.

The glyphs draw without saving. Under a 2 px shift each glyph spills into the next one's first
byte, so the three share columns 2 and 4 — and whichever writes a shared column first would have to
be the one that saves it, which is not something a glyph can know about itself. Hoisting the save
into one generic pass over all seven columns removes the question entirely, and the same trick makes
the *restore* a single pass, because putting the background back does not care what was drawn.

| | before | after | |
|---|---|---|---|
| `SprRestoreAll` | 3,506 | 3,260 | −7% |
| `SprDrawAll` | 7,142 | 6,400 | −10% |
| total | 10,648 | **9,660** | −9.3% |

**That is ~990 cycles, against the ~2,600 projected when the scheme was chosen, and the shortfall is
structural rather than a bug.** Three glyph positions mean three walks of the eight rows, plus one
for the save — four walks where the interpreted path made one. A walk step is `JSR SprNextScan`, ~37
cycles including call and return, so the block spends ~1,180 cycles just advancing scanlines where
the old code spent ~296. The projection did not count that.

Getting to one walk needs per-row code covering all three glyphs at once, which is per-type — either
25K shipped or a run-time generator plus a bank to put it in. That was the option deliberately not
taken, and the 990 is what the cheaper choice is worth. It is not worth revisiting: the same effort
spent on step 4 is worth far more.

**Cumulative: 13,998 at the end of [Layer 4](layer-4-player.md) → 9,660, a 31% cut.** Seven sprites is still 67.6K
against a 40,000-cycle frame, so compilation has now clearly run out of road and the update rate is
the whole remaining problem.

Verified byte-identical two ways: the compiled digits against the same build's interpreted path
(force it by patching `sd_digit`/`sr_digit`'s `LDA sprNoWrap` to `LDA #0`) — 0 diffs over the whole
10K; and the restore against a forced `RedrawAll` after full-speed diagonal scrolling — 0 diffs.

> **Sample the buffer inside `WaitVSync`, not at an arbitrary cycle count.** A dump taken mid-
> `SprDrawSlot` shows the sprite half-drawn and looks exactly like missing rows. That cost an hour
> here: rows 16-19 appeared to be absent in two independent dumps, and the save area proved they had
> been written all along. Poll the PC until it reaches the `WaitVSync` spin, then dump.

**Bank after step 3:** `&8000-&BA84` of `&C000`, 1,404 bytes spare; `PARADAT` is 59 pages. The 2 px
shifted copy of the artwork is gone — both shifts exist as compiled code, and the stored rows are
read only by the wrap fallback, which shifts the few it needs on the fly in `SprFetchRow`. That
reclaimed the 1,743 bytes the glyph code now occupies.

**Noted while measuring, not chased:** adding ~44 cycles of instrumentation to the *draw* call site
deadlocks the main loop in both builds, while the same stub on the *restore* call site is harmless.
So the loop finishes very close to a raster deadline at that point, and a miss appears to hang the
`ruptState` machine rather than merely costing a frame. Worth understanding before the budget gets
spent.

## Step 3a — the scanline walk

A static cycle model built from the generated code (reconciling to within 3% of the measured
totals) put **`SprNextScan` at 2,433 cycles, 25% of the per-sprite cost** — the single biggest
line item, ahead of the play-buffer reads and writes at 17%. 42 calls in a draw and 21 in a
restore, at 33-37 cycles each. Three changes, each verified byte-identical before the next:

| | draw | restore | total |
|---|---:|---:|---:|
| after step 3 | 6,345 | 3,271 | 9,616 |
| drop dead `svp` work in the glyph passes | 6,226 | 3,226 | 9,452 |
| read the scanline from `bufp AND 7` | 6,038 | 3,177 | 9,215 |
| inline the walk as the `SCANSTEP` macro | 5,773 | 2,939 | 8,712 |
| stop the loops after the last drawing row | 5,587 | 2,879 | 8,466 |
| eight row pointers, so the glyphs stop walking | 5,093 | 2,913 | 8,006 |
| sequence dispatch + straight-line sprite shape | 4,566 | 2,454 | 7,020 |
| own bank; walk into the rows, rows into a program | 4,300 | 2,243 | 6,543 |
| merged restore halves, tail calls | 4,283 | 2,095 | 6,378 |
| the glyphs save what they draw | 3,844 | 1,970 | **5,814** |

**−3,802 cycles, 39.5%.** Seven sprites cost 40.7K of the 79,872-cycle pass — just over half of
it — against 67.3K. The
walk is down from 2,433 to about 800, and from 25% of a sprite to under 10%; dispatch and the
row loop, 2,000 between them, are down to a couple of hundred.

The restore's +34 on the last row is the ±50 code-layout noise floor, not a regression: nothing
in the restore path changed, only its addresses.

They are worth distinguishing. The first was *dead work*: glyphs address everything as
`(bufp),Y` and never read `svp`, so 21 walks a frame were maintaining a value that
`SprDigitBlock` then overwrote. The second was *redundant state*: every term of `bufp` is a
multiple of 8 except the scanline, so `bufp AND 7` **is** the scanline and the counter beside it
was never needed. The fourth was *work off the end*: row 20 is blank for every droid, so its
whole iteration and the advance into it drew nothing anyone reads. Only the third was ordinary
cycle-shaving — and it was the largest single win, which is worth remembering before assuming
the clever ones pay best.

**What is left.** Compiling bought the rotor and the digits; these five bought the walk, and the
walk is now spent — what remains of it is `SprBlkSave`/`SprBlkRest`'s 16 steps and the 26 in the
row loops, all of them advancing to a row that genuinely draws.

The step-5 tax was worth naming: three glyph *positions* would have meant offsetting eight
pointers each, which is most of the win. Moving the position out of the pointer and into Y
(`LDY drYcol0,X`, position held in X across the glyph) costs two cycles a column instead of ~100
a position, and it is what lets one set of pointers serve all three. The same trick is why the
shifted glyphs' spill into a shared column still lands correctly: position *p* column 2 and
position *p+1* column 0 are both Y = (*p*+1)·16.

## Step 3b — dispatch and the row loop

Dispatch (~1,000) and the 21-row interpreter loop (~1,150) looked structural — removable only by
compiling a whole sprite per type × phase × alignment, the 25K option deliberately not taken.
They were not, because of one observation: **the ten rotor rows a sprite draws are fixed once its
shift and phase are known.** The sequence is a property of (shift, phase) — sixteen of them — not
of the sprite, so it can be listed rather than derived per row.

Two changes fall out of that:

- **`drSeqLo/Hi`, ten addresses per (shift, phase) in drawing order.** Dispatch becomes an indexed
  read and a poke: no row→slot lookup, no add, no row counter. The list is indexed by **X**, not
  Y — the compiled rows use A and Y and would eat an index kept in Y.
- **The fast path writes the shape out.** A sprite that cleared the wrap test has no row that
  *can* wrap, so its shape is a constant: five rotor rows, a blank, the digit block, a blank,
  five more. That removes the row counter, the blank-row lookup and the end test from every
  iteration — everything the loop did to discover what it already knew.

The interpreted loop stays for the one sprite in five that fails the wrap test, since only a
per-row test can decide which rows fall back. But it now runs *only* with `sprNoWrap` clear, so it
drops that test from every row and its digit-block arm goes entirely — the block never opens
there.

**−986 cycles for +192 bytes of bank** (640 of lists against 448 of dispatch tables deleted). The
alternatives were costed and rejected: fully unrolled `JSR` programs per (shift, phase) buy ~1,220
for ~2,150 bytes, and putting the walk inside every compiled routine buys ~1,360 for ~2,370 —
neither fits, and neither survives the fact that the fallback path keeps the old tables alive.
Both become affordable only with a second bank paged in for the sprite phase.

> **The tile map now has a fixed home at `&3800`.** It used to sit at the next page boundary after
> `code_end` — fine while the code was small, and silently over the sprite save areas at `&3000`
> when it was not. This step is what made it not: the first build put it at `&2D00–&3100`, on top
> of slot 0's saved background, with no assert to catch it. There are asserts now. `&3700–&47FF`
> is clear, and the move takes code headroom from 143 bytes to 1,005 — the constraint that would
> have blocked the next layer regardless.

## Step 3c — a bank of its own, and the full unroll

The blitter now has **SWRAM_SPR to itself**: artwork, compiled rows, glyphs and programs, with
tiles, levels, palettes and the droid game data left in `SWRAM_DATA`. Only one bank is visible at
a time, which works because the two halves are never wanted at once — `DoRedraws` reads tiles,
the blitter reads none of that, and they run at different points in the pass. `SprRestoreAll` and
`SprDrawAll` swap around themselves, so the data bank is the resting state and no caller has to
know. Two swaps a pass, 8 cycles each. The IRQ was the thing that could have broken it and does
not: `RuptVSync` and `RuptTimer` read nothing out of either bank.

With the space, the two options costed and rejected at step 3b both land:

- **C — every compiled rotor routine ends by walking a scanline.** The walk was the one thing
  that had to happen between rows, so putting it inside each row leaves nothing between them.
- **B — a straight-line program per (shift, phase).** Sixteen for the draw, sixteen for the
  restore: ten `JSR`s with the digit block and the two blank rows in the middle. Entering one is a
  table read, a poke and a `JMP` — the program ends in `RTS`, so the tail call returns straight to
  `SprDrawSlot`'s caller. A rotor row costs a `JSR` and an `RTS`.

Then two more, both from reading the generated programs rather than the model. **A `JSR`
immediately before the program's closing `RTS` is a tail call written the long way** — `JMP`
instead, 9 cycles and a byte cheaper, on both sides. And **the restore's ten calls are five
identical pairs**: a restore routine is keyed on the column set, only four sets exist, and which
one a row uses depends on nothing but shift and *phase>>2*. So the ten collapse to two calls into
a routine per half with all five rows inlined — eight routines cover all sixteen sequences, 8 of
the 10 `JSR`/`RTS` pairs gone, and the bottom half can simply omit its final walk because nothing
reads the pointers after it. That last point collects the 42 cycles the unroll had been wasting.

The draw gets only the tail call: its ten rows are ten *different* routines (00,02,04,05,06 |
06,05,04,03,01), and merging them would need a copy per phase of the rows that are currently
shared.

**−477 cycles for the bank move and the unroll, then −165 more for the roll-up.** Less than the −1,220/−1,360 those options were worth against
the step-5 baseline, because step 3b's sequence dispatch had already taken most of it — worth
knowing before costing an option twice.

The fallback keeps the sequence lists and the per-row wrap test, since only that can decide which
rows drop to the slow path. But the compiled rows it calls now walk on their own account, so it
needs a tail that does not walk again: `sd_nextnw`/`sr_nextnw`, taken only from the self-modified
call site.

> **Two beebasm mechanics, both learned the hard way.** `CLEAR` is what lets `&8000-&BFFF` be
> assembled twice — beebasm tracks written bytes and refuses to overwrite them. And **`SAVE`
> writes whatever the image holds at the time it runs**, so each bank must be saved where it is
> assembled; both `SAVE`s left at the bottom of the file silently wrote the sprite bank into
> `PARADAT`, and the deck rendered as garbage with droid types of 164-169.

> **The save areas differ between builds, in bytes nothing reads.** A slot's 256-byte page is only
> partly covered — blank rows save nothing, a compiled row saves only the columns it draws — so
> the rest keeps whatever the staging copy left at `&3000`, which changed when `PARASPR` arrived.
> The play buffer being identical is the proof it does not matter: the save area exists only to be
> read back into the buffer, so a differing byte that was ever read would show up there.

## Step 3d — the glyphs save what they draw

The digit block still saved all seven columns of all eight rows in a pass of its own before the
glyphs drew. That existed for a stated reason: under a 2 px shift a glyph was expected to spill
into the next position's first byte, so two positions would share a column and neither could own
saving it.

**It never spills.** Every glyph's rightmost two pixels are blank, so the generated code uses
relative columns 0 and 1 and never 2 — 120 and 143 uses of `drYcol0`/`drYcol1` against **zero** of
`drYcol2`. The three positions are therefore disjoint (columns 0-1, 2-3, 4-5) and column 6 is
never written at all. The premise the hoisted save was protecting against was vacuous for this
artwork all along.

So the save folds into the draw, where the byte is being loaded anyway: one extra `STA (rowq),Y`
per position. All sixteen of a glyph's positions are saved, transparent ones included, so
`SprBlkRest` stays generic — over six columns now, not seven. `SprBlkSave` is gone entirely, and
with it a whole extra walk of the eight scanlines: `SprBuildRowPtrs` now fills both pointer sets
in one pass and leaves `bufp`/`svp` on row 14, which is exactly where the save pass used to leave
them.

**−564 cycles**, better than the ~500 estimated, because deleting the save pass took its eight
`SCANSTEP`s with it. Cost: 16 more bytes of zero page for `rowq`, and the glyph code grows from
2.7K to 3.7K.

> The blitter now depends on a property of the *artwork* rather than of the geometry, so the
> exporter asserts it: a glyph that ever emitted a lit pixel in column 2 would corrupt its
> neighbour's saved background silently.

### It did spill, and the assert could not fire — fixed 2026-08-14

**"It never spills" was false, and so was the measurement behind it.** The exporter truncated a
glyph row to two bytes *before* shifting it, and `shift_row` drops the carry out of the last byte
it is given, so the spill was thrown away rather than absent. `drYcol2` was used zero times
because the pixel that needed it had already been deleted. The assert that was supposed to guard
the premise read `len(row) < 3 or row[2] == 0` against rows that the same truncation had just made
two bytes long, so it was vacuously true and could never fail.

The visible effect was a **column of pixels missing from the right edge of every glyph except 1,
at odd 2 px positions only** — five of the eight rows for a `0`, which is the right-hand stroke
minus its caps. Reported from play on the player's own `001`.

The fix is the one this step ruled out, but arrived at from the other end. A glyph still saves
only its own two columns; what changed is that **`SprDigitBlock` draws the positions 2, 1, 0**, so
the owner of each shared column saves it clean before the spill arrives, and the spill is merged
into what the owner drew rather than stored over it. Column 6 has no owner and is saved by
`drBlkSave6` — generated into the sprite bank rather than written in `sprite.asm`, because main
RAM is the binding constraint and the bank is not. `SprBlkRest` restores seven columns again.

Cost ~200 cycles a sprite, ~1,400 for the pool against 36,274, and 7 bytes of main RAM.

Verified in jsbeeb with slots at both shifts on screen: the play buffer diffed **0 of 10240**
against a SPACE-forced `RedrawAll` with the draw disabled, and with the restore disabled the eight
digit rows of every slot matched a byte-exact reconstruction from the glyph data — 10 spill bytes
for the player's `001` at shift 1, the pixels that used to be missing.

## What compiling did to the price of 1 px positioning

Worth stating plainly, because the figure quoted elsewhere for years came from the interpreted
blitter and is now wrong by a factor of five.

When rows were *data*, a shift was a second copy of the artwork — 1,820 bytes, and four shifts
were a main-RAM problem. **A shift is now code.** From this build:

| | 2 shifts | per shift |
|---|---|---|
| rotor draw | 3,500 | 1,750 |
| rotor restore | 1,610 | 805 |
| glyphs | 4,154 | 2,077 |
| | | **~4,632 B** |

Bank 5 ends at `&B8B6`, leaving 1,866 bytes. Two more shifts want ~9,264. It does not fit. Main RAM
had 39 bytes when this was written and has 2,496 since the level draw moved to bank 4, with another
4.5 K free elsewhere — still well short of a shift, and the compiled code is the half that cannot be
moved out of the sprite bank.

Three ways out, cheapest first:

- **One restore program for every shift.** The restore is only a column list, and every shift
  touches the same seven columns; making it unconditionally seven costs a few cycles a row and
  saves 805 bytes per shift. Necessary, not sufficient.
- **Player at 1 px, droids at 2.** Odd offsets take the interpreted path — which exists already for
  the wrap fallback — with a 1 px shift added to `SprFetchRow`; the compiled path keeps the even
  ones. About one sprite's worth of slow path, ~8,000 cycles, when the player is on an odd pixel,
  against the ~44,000 the pass is idle. Inconsistent between player and droids, but the player is
  what the eye tracks.
- **A third sideways bank.** Cheapest in cycles, and it breaks the 2 × 16K target.

Why it matters at all is in [`layer-4-player.md`](layer-4-player.md): the original is 1 px in both
the sprite and the scroll, and ours is 2 px in the sprite and 4 px in the world.

**What is left.** Per sprite is now ~3,000 of real pixel movement and ~2,800 of everything else,
of which the largest single items are the six inactive slots scanned every frame (~630) and the
per-slot setup (~480). Nothing structural remains, and nothing needs to.

## Step 3e — the rest of zero page

`&10-&3F`, `&60-&63` and `&65` were still free, 53 bytes, and every module was still keeping its
working variables in absolute storage. They now hold the blitter's twelve working scalars
(`sprSlot`, `sprIter`, `sprNoWrap`, `sprSeqBase`, `sprGlyphBase`, `sprDigit`…), the rupture/CRTC
state (`ruptState`, `drawFlag`, `crtcHi/Lo`, `line/pline/iline`) and sixteen of player.asm's
(`posX`, `posY`, `plyX`, `xSpd`, `ySpd`, `spd`, `cwU`, `plyCX/plyCY`, `dzSx`, `dzD`, `oldHX`…).

**Measured, seven sprites, averaged over 128 passes** (User VIA T1, both builds at the same
position, `TEST_DROIDS` deck 1, stationary):

| | before | after | |
|---|---:|---:|---|
| `SprDrawAll` | 24,134 | 23,961 | −173 |
| `SprRestoreAll` | 12,418 | 12,313 | −105 |
| total | 36,552 | **36,274** | **−278, −0.76%** |

**Under 1%, and that is the honest ceiling for this kind of change** — worth recording so it is not
costed optimistically again. The reason is one line of the 6502 data sheet: **`LDA abs` is 4 cycles
and `LDA zp` is 3, but `LDA abs,X` and `LDA zp,X` are both 4.** The blitter reaches almost
everything through X — all fourteen per-slot arrays, 98 bytes of them — so none of it gains
anything, and only the handful of scalars around the indexing were ever on the table. The same rules
out `sprRowBuf`, the offset tables in scroll.asm, `tdpLo/tdpHi` and `nearXoffset`.

Where it does pay is read-modify-write, at 5 cycles against 6: `CheckWalls` alone does twelve
`LSR`/`ROR`s on `plyCX`/`plyCY` every pass.

**The larger win was space: the code shrank 372 bytes**, `&1100-&2BB4` → `&1100-&2A40`, since a
zero-page operand is a byte shorter. That is worth more than the cycles at this point.

Deliberately not moved: everything in level.asm (`bcSrc`..`palTmp`), which runs at deck load and
nowhere else, and `BuildCharPtrs`/`FillPanel`. Forty-odd bytes of zero page to save a few hundred
cycles once every few minutes is the wrong trade while anything per-pass is still absolute.

> **Verification, and a cheap technique worth reusing.** Both builds' listings were reduced to a
> stream of (mnemonic, addressing class) with abs and zp collapsed together: **7,753 instructions,
> identical in both.** That proves no instruction was added, removed or reordered and that every
> difference is a width change — which is a stronger and far faster check than diffing the play
> buffer, for any change that is meant to be purely mechanical. The emulator run afterwards was
> then only confirming that the addresses chosen do not collide.

## 1 px positioning — step A: making room

*Branch `layer5-1px-shifts`. Four steps; this is the first, and it changes nothing visible.*

Four shifts need ~24.6 K of compiled code against one 16 K bank, so the plan is two sprite banks
split by shift — 0 and 1 in bank 5, 2 and 3 in bank 6 — with the shift-independent parts kept out of
both. Step A moves the largest of those parts.

**The artwork left the sprite bank.** `drSprData` (1,743 B) and `drOfsLo`/`Hi` (336 B) are read by
exactly one routine, `SprFetchRow`, on the wrap fallback — about one row in fifty, plus all eight
digit rows of a sprite that wraps. So they now live in `SWRAM_DATA` with the tiles, and
`SprFetchRow` pages that bank in and the sprite bank back out around itself: ~24 cycles a call, and
at most ~600 a pass in the worst case, against ~39,000 idle.

`drMulRows` and `drDigitLo`/`Hi` (56 B) stayed. `drMulRows` is read at the top of the fallback loop
and `drDigit*` in `SprSetSlot`, both inside the window, and 56 bytes is not worth a paging pair —
they will simply be duplicated into bank 6, at the same address, when it exists.

| | before | after |
|---|---|---|
| bank 5 | 14,518 used, 1,866 free | **12,439 used, 3,945 free** |
| bank 4 | 9,489 used, 6,895 free | 11,568 used, 4,816 free |
| main RAM code | `&1100–&263F` | `&1100–&2654` (+21 for the two `PAGEBANK`s) |

**Verification.** The change is invisible in normal play — the fallback is where it lives — so the
test forced every row through it, by poking `LDA sprNoWrap` to `LDA #0` in `SprDrawSlot`:

- All seven sprites still drew correctly with every row interpreted.
- With the rotor frozen (`SprAnimateAll` → `RTS`) and the restore disabled so the sprites persist,
  the interpreted buffer was **byte-identical to the compiled one — 0 of 10240**, which is the real
  claim: paging in the middle of the fetch does not disturb what gets drawn.
- Back in normal operation, the usual oracle after scrolling: **0 of 10240** against a SPACE-forced
  `RedrawAll` with the draw disabled.

> **The first attempt at the middle test reported 146 differences, and they were an artefact.** The
> interpreted path is ~2.5× slower, so a dump at an arbitrary cycle count lands *inside*
> `SprDrawAll` with some slots drawn and others not yet. This document already warned about that
> from the other direction; the fix is the same one — disable the restore so the sprites persist,
> and the sample point stops mattering.

## 1 px positioning — step B: the pool pages per slot

*Still nothing visible, and still one sprite bank — the point is that the value being paged is now
derived rather than fixed.*

`SprDrawAll` and `SprRestoreAll` used to page `SWRAM_SPR` in once around the whole loop. **Which
bank a sprite needs is a property of the sprite**, not of the pool, so the paging moved inside:

- `PAGESPRBANK` takes the shift in A and pages `SWRAM_SPR + (shift >> 1)`. `LSR` leaves carry set
  from bit 0 of the shift, so the `CLC` before the `ADC` is load-bearing.
- The draw pages in `SprSetSlot`, immediately after it reads `sprShift` — and **before** the
  `drDigitLo` read a few instructions later, which is in the bank.
- The restore pages in `SprRestoreSlot`, after it reads `sprShiftS`: the *draw's* shift, because
  that is where the compiled restore for that sprite lives. `sprShiftS` already existed for exactly
  this class of reason.
- Both loops still leave `SWRAM_DATA` in on the way out, which is what everything outside the
  blitter assumes.
- `sprBank` (one byte, main RAM) remembers the current slot's bank, because `SprFetchRow` pages
  `SWRAM_DATA` in over the top and has to put *that slot's* bank back rather than a fixed one.

Cost: 6 instructions, ~16 cycles, twice a slot — **~224 cycles a pass** of the ~39,000 spare. Code
grew 13 bytes. **Not yet measured on the T1 harness**: a before/after is only meaningful once both
banks exist, so it is deferred to step D rather than claimed here.

*Verified:* 0 of 10240 against a SPACE-forced `RedrawAll` after a diagonal scroll, and — since
`SprFetchRow`'s return-page changed from a constant to `sprBank` — the forced-fallback comparison
again, 0 of 10240 against the compiled path with the rotor frozen and the sprites persisted.

## 1 px positioning — step C: four shifts, two banks

*The picture is still unchanged, but half the pool is now drawn out of a bank that did not exist
before, and the odd shifts are compiled and loaded waiting for step D to select them.*

**The exporter emits four shifts across two files.** `shift_row` generalised from a hard-coded 2 px
to any of 0–3: a MODE 1 pixel is bits 7−n and 3−n, so the two nibbles move together — keep `&EE`
shifted down 1 with `&11` carried up 3, or `&CC`/`&33` at 2, or `&88`/`&77` at 3. Shifts 0 and 1 px
go to `droids.asm` in `SWRAM_SPR`; 2 and 3 px to `droids2.asm` in `SWRAM_SPR2` = bank 6.

**How two banks can share one set of labels.** beebasm's labels are global, so the same table cannot
be declared twice — and duplicating the *contents* is exactly what is wanted, since each bank needs
its own dispatch. The resolution is layout, not naming:

- Each file is **fixed section first, code after**. The fixed section holds every table the blitter
  reaches by name, and its size does not depend on which shifts the bank holds — so it lands at the
  same addresses in both. `drBlkSave6` lives there too, code though it is, for the same reason.
- The second file's fixed-section labels are prefixed `x`. The blitter names bank 5's, and gets bank
  6's tables when bank 6 is paged.
- **`main.asm` asserts all nineteen agree.** This is a hidden coupling with no run-time diagnostic —
  a mismatch would send the blitter into compiled sprite rows — so it is checked at build time.

**Indices are bit 0 of the shift, not the shift.** Bit 1 chose the bank; what is left picks which of
that bank's two. Four shifts' worth of sequence table would be 320 entries and `sprSeqBase` is a
byte, so this is not only tidier, it is the only thing that fits.

**The fallback shifts one pixel at a time**, `sprShiftW` passes of one loop, with the masks derived
afterwards rather than during — a partly-shifted byte's mask means nothing. A per-shift routine
would be faster and this is the wrong place to spend: one row in fifty, and correctness across four
shifts matters more than ~90 cycles.

| | |
|---|---|
| bank 5 (0, 1 px) | 12,374 used, **4,010 free** |
| bank 6 (2, 3 px) | 12,697 used, **3,687 free** |
| main RAM code | `&1100–&267E` |
| disc | +12.4K for `PARSPR2`, a third `*LOAD` staged through `&3000` |

**Verified.** The player and the test droids were switched from shift 1 to shift **2**, so the
picture is bit-for-bit what it was while half the pool draws from bank 6:

- 0 of 10240 against a SPACE-forced `RedrawAll` after scrolling.
- The digit block reconstructed byte-exactly from the glyph data for five slots — three at shift 0
  in bank 5, two at shift 2 in bank 6, the latter with 2 and 9 spill bytes. That is the check that
  catches a glyph the exporter got wrong, which is how the truncated spill column was found.
- The rewritten fallback shift against the compiled path, every row forced through it: 0 of 10240.

## 1 px positioning — step D: the droid lands where it is

Two lines, after three steps of groundwork. `player.asm` and `droidtest.asm` split the screen X at
the bottom two bits: they are the shift, what is above them is the 4 px CRTC unit.

```
LDA dzSx : AND #3 : STA sprShift+PLY_SLOT      \ the pixel within the unit
LDA dzSx+1 : LSR A : LDA dzSx : ROR A : LSR A  \ sx >> 2 = the unit
```

Cheaper than the 2 px version it replaces, which needed a shift and a mask to separate the same two
fields. **The port now positions droids exactly where the C64 does** — see
[`layer-4-player.md`](layer-4-player.md) for the evidence that the original is 1 px in both the
sprite and the scroll, and for what 2 px was costing.

### Verified

| | |
|---|---|
| shift 3 (bank 6), restore vs `RedrawAll` | **0 of 10240** |
| shift 3, digit block vs reconstruction | **0 mismatches**, 22 spill bytes for `001` |
| shift 1 (bank 5), digit block vs reconstruction | **0 mismatches**, 0 spill — correct: 7 px shifted 1 still fits its cell |
| shifts 0 and 2, same reconstruction | **0 mismatches** |
| movement | `plyX` 100 → 101 → 103 → 104 gives (unit 37, shift 0), (37, 1), (37, 3), (38, 0) — one pixel at a time, carrying correctly across the 4 px boundary |

### What it costs, measured

`SprDrawAll`, seven sprites, 64 passes, User VIA T1 bracket, same position in both builds:

| | cycles a pass |
|---|---|
| before the branch — 2 shifts, one sprite bank | 24,821 |
| after step D — 4 shifts, two banks | **24,943** |
| | **+122, or 0.49%** of `SprDrawAll`, against 79,872 in a pass |

Predicted by construction: `PAGESPRBANK` is 18 cycles and runs once per drawn slot, 7 × 18 = 126.
Measurement and arithmetic agree to four cycles.

> **The first attempt at this measurement was wrong, and wrong in a way that looked like a serious
> regression.** The patch that was supposed to move the T1 bracket off `DoRedraws` silently failed —
> the pattern contained an em dash that did not match the file's encoding — so the build had **two**
> brackets. `dbgAcc` then summed two routines and `dbgN` counted twice a pass, which made the game
> look like it was running at one field a pass instead of two, i.e. double speed. It was not: the
> release builds move `plyX` 612 → 901 in the same two seconds, before and after. This document
> already said "one call site at a time"; what it did not say is *how* two fail — not a hang, but a
> plausible-looking number and an inflated pass count. Assert your patches.

### Not fixed here: the rotor debris

Across these runs the restore-vs-`RedrawAll` check returned 0, 6, 24 and 39 differences at different
player positions **in the same build**. Every one was in a rotor row; the digit block — the part this
work changes — was byte-exact every time, and the shift-0 slots were affected as much as the shifted
ones. That is `BUGS.md` #6, and these runs add one fact to it: it **survives freezing the rotor
phase**, which refutes the leading hypothesis recorded there.

## What is in the bank, block by block

Reference for the finished article. Addresses are from a `-dd` label dump of the current build;
[`memory-map.md`](memory-map.md) carries the same table in its outline form, and it is the one to
regenerate when something moves.

**The bank has two consumers with almost no overlap.** The compiled fast path is *code*, and reads
none of the artwork. The wrap fallback — a sprite straddling the end of the circular strip, about
one row in fifty — is the only thing that reads the stored rows, and it needs an entirely
different set of tables to find them. Knowing which half a block belongs to is most of
understanding why it exists.

### Stored artwork and its indexes — the fallback's half

| | | |
|---|---|---|
| `&8000` | 1,743 | **`drSprData`** — the artwork as data: 249 rows × 7 bytes, unshifted. 40 rotor rows (5 per phase × 8), 16 alternating end rows, 192 digit rows (8 × 24 types), 1 blank. Seven bytes because 24 px is 6 on a 4 px boundary and the shift spills into a seventh |
| `&86CF` | 168 + 168 | **`drOfsLo`/`Hi`** — offset into `drSprData` for every (phase, row): 8 × 21, split so a pointer is two indexed loads |
| `&881F` | 8 | **`drMulRows`** — phase × 21, so the index above is a table read and not a multiply |
| `&8827` | 24 + 24 | **`drDigitLo`/`Hi`** — where each droid type's eight digit rows start. Read once per sprite into `sprDigit` |

`SprFetchRow` shifts a stored row on the fly, which is what let the pre-shifted second copy be
deleted — and those 1,743 bytes are where the compiled glyphs now live.

### Compiled rotor rows — one routine per distinct picture

| | | |
|---|---|---|
| `&8857` | 1,810 | **`drD0_*`** — 28 draw routines, shift 0 |
| `&8F69` | 144 | **`drR0_*`** — 4 restore routines, shift 0 |
| `&8FF9` | 1,690 | **`drD1_*`** — 28 draw routines, shift 1 |
| `&9693` | 126 | **`drR1_*`** — 4 restore routines, shift 1 |

**28, not 168.** The bottom half of a droid is the top half in reverse row order, and rows
0/1/18/19 come from two-entry tables indexed by `phase >> 2` — seven distinct rows a phase plus
four end rows. A routine is the row with its transparency baked in, a transparent column emitting
nothing at all, and it ends with its own `SCANSTEP` and `RTS`.

Shift 1 is 120 bytes *smaller* than shift 0: shifting right turns some part-opaque bytes fully
opaque, and a fully opaque byte drops its `AND`/`ORA` for a plain `LDA #`/`STA`.

**Four restores against 28 draws** because a restore is keyed on the *set of columns touched*, not
on the artwork — putting the background back does not care what was drawn over it.

### Dispatch — finding a row one at a time

| | | |
|---|---|---|
| `&9711` | 160 + 160 | **`drSeqLo`/`Hi`** — the ten drawn rotor rows in drawing order, indexed `shift*80 + phase*10 + n` |
| `&9851` | 160 + 160 | **`drRSeqLo`/`Hi`** — the same for restores |

The ten rows are a property of `(shift, phase)` — sixteen sequences — and not of the sprite, so the
fallback walks the list with one index and needs no row→slot lookup or add. Ten and not seven
because the bottom half visits the shared rows in reverse with the two end rows swapped.

### The fast path proper

| | | |
|---|---|---|
| `&9991` | 1,340 | **`drRHalf<shift>_<arr>_<half>`** — 8 routines, five rows of restore inlined each |
| `&9ECD` | 1,072 | **`drPrg<shift>_<phase>`** — 16 straight-line draw programs |
| `&A2FD` | 688 | **`drRPrg<shift>_<phase>`** — 16 restore programs |
| `&A5AD` | 640 | **`drPrgLo`/`Hi`, `drRPrgLo`/`Hi`** — program entry addresses |
| `&A82D` | 21 + 8 | **`drSeqIdx`, `drMul10`** — sprite row → sequence position (`&FF` = not a rotor row), and phase × 10. Fallback only |

A draw program is the whole sprite as straight-line code: ten row calls in order, `SCANSTEP` for
blank row 5, `JSR SprDigitBlock` for rows 6–13, `SCANSTEP` for blank row 14. No index, no counter,
no end test, and the last call is a `JMP` — a tail call written the long way, 9 cycles instead of 18.

A restore program is five instructions, because the halves absorbed the rest: a restore depends
only on the column set and the column set only on `(shift, phase >> 2)`, so eight routines cover
all sixteen sequences and 8 of the 10 `JSR`/`RTS` pairs disappear. The draw cannot have this —
its ten rows are ten *different* routines, and merging them would need a per-phase copy of the rows
that are currently shared.

The entry tables are indexed by the same `sprSeqBase` the fallback uses, so entering a program is
one table read and a poke with no arithmetic. Only every tenth entry is reachable; the rest is
padding to keep the stride identical to the row tables.

### The digit block

| | | |
|---|---|---|
| `&A84A` | 1,926 | **`drGlyph0_*`** — ten compiled glyphs, unshifted |
| `&AFD0` | 2,131 | **`drGlyph1_*`** — ten compiled glyphs, shifted |
| `&B823` | 35 | **`drBlkSave6`** — column 6's save, eight rows |
| `&B846` | 20 + 20 | **`drGlyphLo`/`Hi`** — dispatch, `shift*10 + digit` |
| `&B86E` | 24 × 3 | **`drDigit0`/`1`/`2`** — each type's hundreds, tens and units as glyph numbers |

Ten glyphs cover all 24 types because a droid number is three independent 8-pixel glyphs and the
*position* rides in X (`LDY drYcol0,X`) rather than being generated three times over.

The 205-byte difference between the two shifts is the third column — the spill — which the
exporter used to truncate away. `drBlkSave6` is the other half of that fix, and it is in the bank
rather than in `sprite.asm` only because main RAM had 46 bytes free and the bank had 1.9 K.

## Where the sprite work actually lands — measured 2026-08-15

The flicker item above had never been instrumented; it was a reasonable inference from the order of
the main loop. It is now a measurement, and it says something sharper than the inference did.

**Method, and it is cheap enough to repeat.** `ruptState` names which rupture fire is expected next,
so it also says where the beam is: **`ruptState == 2` means fire 2 has happened and fire 3 has not —
the play area is on screen.** Four one-byte histograms indexed by `ruptState`, bumped either side of
the two pool calls, cost about 20 bytes of main RAM and no cycles worth counting. Over 128 passes,
deck 1, one droid visible:

| | state 0 | state 1 | **state 2 (play area displaying)** | state 3 (off-display) |
|---|---:|---:|---:|---:|
| entering `SprRestoreAll` | 0 | 0 | **0** | 128 |
| entering `SprDrawAll` | 8 | 9 | **111** | 0 |
| leaving `SprDrawAll` | 0 | 3 | **120** | 5 |

**The restore is inside the window and the draw is almost never in it.** Every pass restores while
the play area is blanked, and then 120 passes out of 128 are still *drawing* sprites while the beam
is over them. That is the flicker: a sprite is erased at the top of the pass and put back while the
beam is passing its rows, so for one field the eye sees background where the droid was.

The order is not an accident — `SprDrawAll` has to follow `DoRedraws` so the save picks up settled
background, and by then the next field's play cycle has started.

**The cheap fix does not exist, and this is what rules it out.** The obvious move is to spend the
idle time *before* the draw rather than after it: wait for the next off-display window and draw
inside it. But the window is stated on `rt_drawok` itself — "deadline for the redraw is the play
cycle starting again, **184 scanlines away**" — which is 11,776 cycles. Seven sprites cost 36,274
and the draw half alone is about 24,000. **The work is two to three times the window, so no
scheduling of it can fit.**

That leaves the real thing: ordering the pool against the beam, updating each sprite in the gap
after the beam has passed its own rows, which means restoring and drawing a sprite as one unit. And
that breaks the invariant the whole file is built on — restore *all*, then draw *all*, because
drawing one sprite while another is still on screen captures the second one's pixels into the
first one's save area, and restoring it later stamps them into the buffer permanently. The
overlap problem is the same one that killed round-robin below, and it has to be solved *first*, not
alongside.

So the shape of the remaining work is: an overlap test between slots (Layer 6 now has one —
`DrCollide`'s box test — though this needs the exact 7 × 21 footprint, not a feel-based box), a
slot order sorted by screen Y, and a beam position finer than `ruptState`. None of it is hard; all
of it is easy to get subtly wrong, and the failure mode is permanent corruption of the play buffer
rather than a flicker.

## Why not round-robin

Every earlier note here treated round-robin as the next step and the biggest remaining lever. It
is neither, and the reason is the work above. **The loop spends 39,212 of its 79,872 cycles idle
— 49% of the pass** with all seven sprites live. Round-robin would buy back ~20K of a budget that
already has 39K spare.

It is also not free, which the earlier notes never costed:

- **Overlap.** The order — restore *all*, scroll, draw *all* — exists because drawing one sprite
  while another is still on screen captures the second one's pixels into the first one's save
  area, and restoring it later stamps them permanently into the buffer. Round-robin breaks that
  invariant by construction, and the corruption is permanent rather than transient.
- **Scroll bands.** A sprite left undrawn keeps its correct world position — the buffer is
  circular and the world moves with it — but if `DoRedraws` repaints a band over it, its saved
  background is stale and restoring it writes old pixels over new. That only shows while
  scrolling, which is where the oracle is weakest.
- **Visible cost.** At four slots of seven a pass, droids animate and move at ~14 Hz against the
  player's 25.

If a later layer does eat the headroom, measure first: `RunDroids`, pathfinding and slot
allocation are budgeted at ~14,000 cycles on the C64, which would still leave ~25K spare. The
cheap half-step, if it is ever needed, is not round-robin but **skipping a sprite that provably
cannot have changed** — same screen position, same rotor phase, no scroll, no overlapping sprite
redrawn. That is correct with no visual cost at all, though it only pays when droids are
stationary or low-energy, since `SPR_SPIN = 0` advances a full-energy rotor every pass.

> **Measuring across builds.** Average over ~128 passes, not 16: the rotor phase cycles every 8
> and the per-phase spread is a few hundred cycles, so a short average is biased by which phases
> it caught. There is also a ±50-cycle floor between builds from `abs,X` lookups landing on
> different sides of a page boundary once the code shifts.

> **Drive the scroll by patching `ReadKeys`, not by holding a key.** A keypress injected at a
> fixed cycle count lands a pass earlier or later once the code speed changes, and the two runs
> then diverge for reasons that have nothing to do with the change under test. Half an hour went
> into a 38-byte difference that was entirely this.

> **Check `code_end` against the stub address after every build.** The measurement and input
> stubs live between `code_end` and the tile map at `&2C00`. Step 3a moved `code_end` from `&2B7B`
> to `&2BA4`, and a stub left at `&2BA0` lands on `vsyncCount` and `oldIrq1V` — which reads
> exactly like a sprite bug that only appears when scrolling.

> **Anchor the rotor phase before the counted passes.** The oracle parks the game after N passes
> by patching the `JMP` at the bottom of the main loop, but that patch is installed at a fixed
> cycle count — and once the code speed changes, the two builds are not in the same pass when it
> lands. Step 4's builds parked **three passes apart**. The signature is unmistakable once seen:
> every rotor row of every sprite differs and the digit rows match exactly, because the rotor
> depends on phase and the digits on type. Zero `sprFrame` and `sprDelay` before the counted
> passes. Safe to do mid-run — the restore replays `sprTabBaseS`, which records the phase the
> draw actually used.
>
> **And anchor it at a LOGICAL point, not a cycle count.** Zeroing `sprFrame` mid-pass lands
> either side of `SprAnimateAll` depending on where that build happens to be, so the two runs
> still come out one phase apart — the same signature, and step 5 hit it after step 4 had already
> established the rule. Park first, zero while parked, then resume: write `JMP` *the park
> routine's own resume path* over the self-park, run ~2000 cycles to let the CPU out, and put the
> self-park back. Check afterwards that `sprFrame` is exactly `passes MOD 8`.
