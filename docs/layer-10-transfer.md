# Layer 10 — the transfer minigame

**Status: BUILT 2026-08-17 on branch `layer10-transfer`.** The whole subgame plays: side
select, the pulser game against the CPU, the verdict, and all three outcomes applied to the
droid the player is riding. Entered the original's way — touching a droid with `moveMode`
0 — and verified in jsbeeb end to end: entry from a real collision, a takeover (001 →
476, speed/weapon/energy/score all moved), a loss as a 001, a tie's short-circuit replay,
and the return to the deck with palette, panel and view restored.

The research that preceded this (where every routine lives in the C64, the rule set, the
colour-RAM problem) is in §2–§4 below, kept because the decisions reference it.

---

## 1. What was built, and where it lives

| Piece | File | Bank |
|---|---|---|
| The game itself — `SubGameSelectSide`, `doSubGame`, `xfer_DoColumn` and every `xfer_*` routine, transliterated | `src/xfer.asm` | **7** (`PARXFER`, the fourth SWRAM bank) |
| Board characters ×3 ownership sets + layout, generated | `src/data/xferboard.asm` via `tools/export_xfer.py` | 7 |
| Entry/exit — Capture's front half, `FinishTransfer1/2`, `xferInitDroid`, the transfer palette | end of `src/droid.asm` (`XferEnter4` / `XferExit4`) | 4 |
| The paging trampolines and the main-RAM mirrors (`xferDroid`, `xferActive`, `xfm*`) | `main.asm` (`XferEnter` / `XferTick`) | main RAM |
| The collision arm — `$1A6A`'s `moveMode == 0` gate | `src/droid.asm`, `dc_player` | 4 |
| The 16th-row switch — fire 3 as a variable interval | `rupture.asm` (`t1i3Lo/Hi`), `T1_I3X` in `main.asm` | main RAM |

### How the C64 code survived verbatim: the shadows

The game logic reads and writes a character screen and colour RAM, neither of which exists
here. Bank 7 carries a **shadow of both**: `xsScr` is the board's 16 rows of 40 bytes in
the C64's own character codes, `xsCram` its colour RAM at the fixed page offset `XS_COFF`
(+3 pages) the way `$D800` sat `$9000` above `$4800`. Every `CMP #$F5`, every `(dest),Y`,
every `Scr2ColorRAM` in the transliteration is the original instruction against the
shadow. A small set of write helpers (`XfWScr`/`XfWCol`) route the LIVE stores: write the
shadow, and repaint the one MODE 1 cell — 16 bytes at `BUF_BASE + row*640 + col*16` —
**only if the byte changed**, which is what keeps a steady-state half-turn cheap. Board
setup writes the shadows directly and repaints everything once (`XfRepaintAll`), which is
why the gate-placement routines (`xfer_PutSplitter` and friends) are byte-shaped like the
original's.

The `xfPhase` state machine replaces the C64's modal loops, one iteration per pass on the
console's `conActive` pattern: `doSubGame` spent one 50 Hz frame per half-turn, and a pass
is two fields, so one full iteration a pass is the same wall-clock rate for free.

## 2. Where it all is in the C64 (the research)

| | | |
|---|---|---|
| `Capture` | `$229D` | entered from `GameLoop+6D` when `xferDroid` is set by `DoCollision`'s `_ply_droid` arm at `moveMode == 0` |
| `SubGameSelectSide` | `$E016` | draws the board and picks the colours |
| `doSubGame` | `$2166` | the loop: one player half-turn, one CPU half-turn, per iteration |
| `xfer_GetMove` / `xfer_DoMove` | `$2109` / `$1D75` | the cursor, and committing a pulser |
| `xfer_PlayLeft` / `xfer_PlayRight` | `$1E06` / `$1E5E` | three `xfer_DoColumn` calls each |
| `xfer_DoColumn` | `$1EB6` | **the whole rule set** — 12 rows of one wire column |
| `xferDrawCBar` | `$2057` | the central control bar, who is winning, and the side swap |
| `xferDoCounter` / `xferCheckEnd` | `$20DA` / `$2153` | the countdown and the grace period |
| `FinishTransfer1/2` | `$21CF` / `$2260` | take the droid, or burn out |
| Board data | `$E613/$E68B/$E6B3` | 3 rows + ONE row ×12 + 1 row, 200 bytes |

The twelve middle rows are all the same row: a wire from the player's bus at column 3
along 4–17 into the central bar at 19–20, mirrored from column 36. `xfer_DoColumn`
dispatches per row on the pulser count in the stage array and then on the **character in
the cell** — pulser chars annihilate, `$F5` joins, `$F6` splits, anything else is claimed
(`xfer_Colorize4`) and advanced. The colours: `$FF` the player's identity, `$FC` the
CPU's, `$F8` neutral, `$F2` a doused stock cell (red on red — invisible). The `Ply*`/
`Cpu*` variable sets swap every half-turn, so "Ply" means "the side moving now";
`xfer_LeftColor` is the HUMAN's colour, fixed at select, and `FinishTransfer1`'s verdict
is `WinningColor == LeftColor`.

## 3. Decisions

1. **[DECISION] Ownership is a character set** (route A of the research). MODE 1 has no
   colour RAM, so the 17 board characters ship in three copies — neutral, player, CPU —
   drawn in logical 3, 1 and 2, and a cell's colour token picks the set. 816 bytes.
2. **[DECISION] Structural pixels stay neutral.** The multicolour `01`/`10` pairs are the
   C64's fixed `$D022/$D023` registers — the same whoever owns the cell — so they render
   logical 3 in *every* set. The first cut mapped them to logical 1/2 and the buses read
   as owned; measured in the emulator, fixed in the exporter.
3. **[DECISION] The board is all 16 rows** (KC, 2026-08-16 — over the research's
   11-wire option). The play area always *displays* 16 rows; the R8 blank at fire 3 is
   all that hides the smooth scroll's spare row. The rupture's fire-2→fire-3 interval is
   now the variable `t1i3Lo/Hi`; `XferEnter4` sets it to `T1_I3X` (16 rows) and exit puts
   it back. The board maps C64 rows 9–24 onto buffer rows 0–15 exactly, all twelve wires.
4. **[DECISION] A fourth SWRAM bank** (KC, 2026-08-16): bank 7, `PARXFER`, fifth `*LOAD`
   at boot staged through `&3000` like the others. Banks 4–7 is the Master's own sideways
   RAM numbering. ~9.8 K of it was free at the time; the lift screen and the console's three
   pages have since taken it to ~2.0 K (see `layer-9-hud.md` §6e–6f).
5. **[DECISION] The palette** (KC, 2026-08-17): background blue, the board's structure
   and unclaimed wire BLACK, the left side's pieces yellow, the right side's magenta.
   "Left" and "right" because the `$FF`/`$FC` identity tokens belong to the *sides* —
   the human is whichever side the stick chose at select. Lives in `palXfer`
   (droid.asm), one table to change. (The first cut was red/white/cyan/yellow.)
6. **[DECISION] Status text on the panel line.** The C64 draws its counter, the two robot
   numbers and the verdicts into screen rows above the board; ours has no rows above the
   board, so they go on the panel's text line via a bank-7 copy of `PnGlyph` (bank 6 is
   unreachable — one bank at a time). PanelTick is skipped while the game runs;
   `PanelSetup` repaints on exit. Verdicts read "transfer done / transfer failed / short
   circuit" in lowercase (wide capitals need the two-cell machinery).
7. **[DECISION] The side-select droids are numbers, not sprites.** The original slides
   the two droid sprites left and right; there is no sprite engine under the board, so
   the panel line shows the human's number on the side the stick last chose. The stock
   columns on the board itself still show the two sides' colours, as the original's do.
8. **[DECISION] Not ported**: `ShowXferInfo`'s two robot-info screens before the board
   (Layer 11-adjacent presentation), `AnimateIntoFont`'s background charset animation,
   `FinishTransfer2`'s sprite-slide sweep (a ~2 s hold stands in), and the sounds (no
   sound layer exists yet). The pre-game info screens are worth revisiting with Layer 11.
9. **[DECISION] Per-type player speed is real now.** `CalcAxis`'s clamp was assembly-time
   constants; it now clamps against `plyMaxLo/Hi`, written by `xferInitDroid`'s port from
   `PlayerSpeed_t` (`0,5,6,0,7,0,0,0,7`) — with 7 mapped to `CAM_TOPSPD` (8) exactly as
   the 001's always was. `ccd_reset` restores the 001's on death.
10. **[DECISION] Code placement bought with a move.** Main RAM hit its `&3000` ceiling;
    the fix is the established one — move code to bank 4. `XferEnter4`/`XferExit4`/
    `xferInitDroid` belong there anyway (they touch the droid tables), and `CalcAxis`/
    `CalcSpeed` moved with them (main-loop-only callers, resting state). Only the paging
    trampolines and six mirror bytes stay in main RAM: **bank-4 code cannot page bank 7
    in under its own feet**, and `PanelSetup` (a bank-6 trampoline) is likewise called
    from main RAM after `XferExit4` returns.
11. **[DECISION] All four player speeds are dither-free** (KC, 2026-08-21 — amends 9).
    Decision 9 mapped `PlayerSpeed_t`'s two 7s onto `CAM_TOPSPD`; the 5 and the 6 were left
    alone and dithered for exactly the same reason. The camera scrolls in 4 px units once per
    2-field pass, so 5 settles into 4, 4, 8, 4 and 6 into 8, 4, 8, 4 — which made riding a
    **slow** droid jerkier than riding a fast one, backwards from what the speed suggests.
    4 is the only dither-free value below 8, so both collapse onto it: `CAM_SLOWSPD`, a new
    constant beside `CAM_TOPSPD` in `main.asm` and carrying the same argument. The table in
    `droid.asm` is now `0,4,4,0,8,0,0,0,8` and the C64's row is recorded above it.
    - **The cost, accepted:** `DSpeed_t` 1 and 2 are indistinguishable under the player — a
      123 rides like a 751 — and both are slower against the 001 than the C64 makes them
      (4 vs 8 where the original had 5 vs 7 and 6 vs 7). KC's reading is that "you either get
      a fast one or a slow one" is a fine model for the ride, and worth the judder going away.
    - Enemy droids are **untouched**. They move in whole pixels rather than by scrolling the
      camera, so `DSpeed_t` never dithered for them and stays verbatim.
    - `CAM_TOPSPD` and `CAM_SLOWSPD` are now the only movement numbers in the port not taken
      from the C64, and between them they replace every live `PlayerSpeed_t` entry.
12. Small timing stand-ins, faithful in rate if not mechanism: the select countdown ticks
    every other pass (~8 s for 99 BCD, near the original's `DelayScore(80)` pacing); the
    play counter every other iteration as `$20DA` does; `DoScore` keeps dribbling banked
    points during the game where the C64's modal loop froze them.

13. **[DECISION] The transfer cursor is edge-triggered with a hold-off** (KC, 2026-08-25).
    The only place the port's controls deliberately leave the original. KC's play-testing
    said the subgame was "too fast and a bit twitchy on the keyboard compared to the C64
    joystick"; the investigation that followed found the *clock* is faithful and the
    *input model* is the problem.

    - **The countdown is right, and 2 MHz does not touch it.** Mechanism is verbatim:
      BCD `xfTime` from `&99`, decremented on every other iteration (`xfFrame AND 1`,
      `$20DA`'s own test), then `xfGrace` = `&55` iterations of grace. The port runs one
      iteration per pass, and a pass is `FRAME_LOCK` = 2 fields — **measured in jsbeeb at
      79,886 cycles between consecutive `XfPlayTick` entries, i.e. 39.94 ms, exactly two
      fields with no overrun**, against a body costing 67,550 cycles (85% of the pass).
      So 99 x 2 x 2 fields = **7.92 s of countdown + 3.4 s of grace**.
    - **The C64 lands on the same 25 Hz, by a different route.** `doSubGame` ($2166) gates
      *each half-turn* on `irqToggle`, which the raster chain sets at line 246 and clears
      at line 118. Both waits are live (`F0 FC`) — worth noting that three of GameLoop's
      five equivalents were nopped to `D0 00` in this CE listing, with a `!! remove`
      comment beside them; that is the "CE runs more iterations per second" dial, and the
      subgame was left out of it. The gate is work-dependent, so it was costed: one
      half-turn is dominated by 3 x `xfer_DoColumn`, 12 rows each through
      `xsub_Black4`/`xfer_Colorize4`, ~21,000 cycles = ~21 ms, which exceeds one PAL frame
      (19,656). Each half-turn therefore takes its own frame: 2 frames an iteration, 25 Hz.
      **This half is an estimate from the listing, not a measurement** — there is no C64
      emulator in this toolchain — but the port's measured 67,550-cycle body corroborates
      it, being the same instruction stream plus the MODE 1 cell repaints the C64 has no
      need of. If the C64's half-turn were under ~11.7 ms the gate would pass two per frame
      and the original would be up to 2x faster than the port; the cycle count says it is
      not, comfortably.
    - **So the twitchiness is the input model, and it is the original's.** `xfer_DoMove`
      ($1D75) is level-triggered — any non-zero `joyYDir` moves exactly one row — and
      `ReadKeys` is a raw OSBYTE `&81` matrix scan, so the port's key state is level too.
      One row per 40 ms, 25 rows/s, the whole 12-wire bus in under half a second. That is
      playable on a self-centring microswitch stick, where a flick fits inside one 40 ms
      iteration; it is not playable on keys, where the shortest honest tap is two or three
      rows and single-row movement is impossible.
    - **What was built**, in `XfGetMove`'s human arm only (the CPU arm returns above it, so
      the CPU's own every-other-frame throttle is untouched): a new direction moves at once
      and then waits `XF_RPT_DELAY`+1 = 4 passes (160 ms); held after that, one row every
      `XF_RPT_RATE`+1 = 2 passes (80 ms, 12.5 rows/s); released, the edge re-arms. A
      reversal counts as a new direction and moves immediately. `XfStart` clears the two
      state bytes so a key still held from the deck cannot eat the first row.
    - **The hold-off was 6 passes (240 ms) on the first cut**; KC played it and asked for
      less, so `XF_RPT_DELAY` went 5 -> 3. 160 ms is the guarantee it buys: a tap shorter
      than that is exactly one row, and anything longer starts repeating.
    - **Verified in jsbeeb, 2026-08-25** (entered by poking the main-RAM `xferDroid`
      mirror). At the first cut's 240 ms: a 160 ms tap moved **1** row where it used to
      move 4, an 800 ms hold moved **9**, a reversal tap moved exactly 1 the other way,
      the countdown still ticked 99 -> 35 over 254 frames (256 predicted), and the game
      ran to its verdict clean. Re-measured at the shipped 160 ms: a 120 ms tap moves
      **1** row, a 200 ms hold moves **2** — the boundary sits where the constant says.
    - **The cost is 54 bytes, and the first telling of this said 256.** The tail figure
      does move `314 B -> 58 B` (`xfer_end` = `&BFC6`), because `plandata.asm`'s
      `ALIGN &100` had 26 bytes spare and the addition rolled `planInk` to the next page.
      But **the padding is usable space**, exactly as bank 4's is: anything assembled
      before `INCLUDE "src/data/plandata.asm"` rides in it for nothing, and there are now
      **228 B of it**. Real free space in bank 7 is 228 + 58 = **286 B**, and the filter
      took 54 of the 340 that were there before it. The correction matters because the
      256 figure was used to argue that DECISION 14's droid icons could not be afforded;
      on the true numbers they very nearly can.
    - **Not changed, deliberately**: the select countdown, which is the one real timing
      deviation found. `SubGameSelectSide`'s `_14` loop is paced by `DelayScore(80)` —
      ~103,000 cycles, ~105 ms a tick before badline steal — so the original takes ~11 s
      over 99 ticks where the port's every-other-pass tick takes 7.92 s, ~30-40% fast.
      Fire confirms immediately either way, so it only shows if the player dithers. Fixing
      it needs a mod-3 counter rather than the present `AND #1`. KC's call, left alone.

**Open item from 13 — CLOSED, and it was never worth doing.** Moving the repeat filter
behind `plandata.asm`'s `ALIGN` would have restored the *tail* figure while costing its 46
bytes 1:1 out of the tail, leaving real free space unchanged at 286 B and putting the routine
somewhere it reads worse. It stays where it is. What the exercise did produce is the bank-7
map below, which is the thing worth keeping.

## 6. Bank 7's map, measured 2026-08-25

| chunk | start | size |
|---|---|---|
| `xfer.asm` | `&8000` | 3,997 |
| `xferboard.asm` | `&8F9D` | 1,033 -> **876** (see below) |
| `liftview.asm` | `&93A6` | 867 |
| `condeck.asm` | `&9709` | 361 |
| `condb.asm` | `&9872` | 1,559 |
| `portraits.asm` | `&9E89` | **4,736** |
| `portrait.asm` | `&B109` | 559 |
| `infoscr.asm` | `&B338` | 534 |
| `hstable.asm` | `&B54E` | 15 |
| `droidinfo.asm` | `&B55D` | 711 |
| `plandata.asm` head | `&B824` | 248 |
| **`ALIGN` padding** | `&B91C` | **228 — free to anything before the plandata include** |
| `planInk` onwards | `&BA00` | 739 |
| `sideview.asm` | `&BBFF` | 966 |
| tail | `&BFC6` | **58 — free to anything** |

The portrait pool is 63 images at 64 B, already deduplicated by `export_portraits.py`, so
there is no cheap win in the biggest chunk.

### The glyph pool — 154 B found, 2026-08-25

`xferboard.asm` shipped the 17 board characters three times over, once per ownership set
(DECISION 1). **13 of those 51 cells were duplicates.** A character whose every logical-3
pixel is *structural* is byte-identical in all three sets — which is DECISION 2 showing up in
the data — and several others coincide pairwise. The identical-in-all-three ones are `$00`,
`$D0`, `$D1`, `$FB` and `$FC`: the blank, the two bar caps and the central bar's two ends.

`export_xfer.py` now emits one pool of the **38 distinct glyphs** plus a 51-byte `xbSlot`
table, and `XfCellPaint` reaches the glyph through it: `xsGlyphOf` gives 0..16, `xfSetOfs`
(a 4-byte pen -> run table, replacing `xfSetLo`/`xfSetHi`) picks the set's run, and `xbSlot`
names the pool entry. Six more instructions, ~8 cycles a repainted cell — nothing against a
pass with 12,000 spare — and **816 B of glyphs became 659**.

| | before | after |
|---|---|---|
| `ALIGN` padding | 228 B | **126 B** |
| tail | 58 B | **314 B** |
| **real free** | **286 B** | **440 B** |

**Verified, and not by the obvious method.** A straight before/after diff of the 10,240-byte
play buffer showed 758 bytes differing — confined to the twelve wire rows in the gate
columns, with the frame rows, buses and stock columns identical. That is the RNG moving, not
the glyphs: `XfStart` seeds from `USR_VIA_T1CL EOR fieldCount`, and six extra instructions a
cell shift the cycle at which it samples, so the gate placement changes. The seed makes a
before/after diff worthless here.

What proves it instead is an **independent reconstruction**: dump the shadow screen and
colour shadow (`xsScr`/`xsCram` at `SPR_SAVE = &3E00`, *not* `&3000`), and rebuild the whole
10,240-byte buffer on the host from `export_xfer.mode1_char` — the pre-dedup algorithm —
through `xfPenOf`. **All 10,240 bytes matched.** The exporter also asserts by construction
that `pool[slot[set][code]]` is the exact byte string the flat table held, for all 51 pairs.

`src/data/` is gitignored and `build.ps1` does not run the exporters, so a clean checkout
needs `python tools/export_xfer.py` before it will build.

## 4. The interfaces, for whoever touches this next

- `dc_player` (bank 4) sets `xferDroid` and returns — no bounce, no debounce, the
  original's own arm. The main loop enters `XferEnter` after `DroidsUpdate` and skips the
  rest of the pass; the next pass takes the `xferActive` arm, one `XfTick` per pass.
- Bank 7 sees ONLY main RAM: the font at `FONT_ADDR`, the `pnTab*` mirrors, `keydown`/
  `ReadKeys`, and the `xfm*` mirrors. `XferEnter4` fills `xfmPlyType/xfmTgtType` before
  the bank is paged; bank 7 answers through `xfmResult` (1 took it, 2 lost) and
  `xfmDone`. Ties never come out — the replay loops inside.
- `XferExit4` (bank 4, data paged) applies the outcome: takeover copies the target's type
  and energy, banks its shoot score and runs `xferInitDroid`; a loss with a droid pays
  `BumpScore` and falls back to the 001; a loss as a 001 zeroes `drEnergy` and lets
  `CbCheckDeath` do the rest. The target is consumed in **every** outcome
  (`FinishTransfer2`): energy 0, sprite slot freed, `DrRemoveShip`.
- Zero page: the game borrows `bufp/chp/tdp/src/mapptr` for the C64's five pointer pairs
  and `psrc/svp` for the renderer — all level-draw/startup pointers, idle while the deck
  is suspended, re-derived by their owners afterwards. The IRQ touches none of them.

## 5. Verified in jsbeeb (2026-08-17)

- Fifth `*LOAD` boots; bank 7 paged in reads back `XferBoard`'s own bytes; the deck runs.
- The board renders correct against the original's layout at all 16 rows, gates placed.
- Select: stick picks the side, fire confirms, countdown auto-confirms.
- Play: cursor moves and wraps, pulsers commit and drain the stock column, the CPU walks
  its cursor and fires, claimed wire recolours per side, the bar shifts, gates split and
  join, the counter runs, the grace period ends it.
- Outcomes: takeover verified end to end — 001 became a 476, panel and console agree,
  score banked, target consumed; the 476's larger stock (7 pulsers) showed in the next
  game. Loss as 001 exits clean. Tie rebuilt the board and replayed, twice.
- Exit restores palette, `t1i3`, mode word, view and panel; play continues.

**Not yet verified**: play-balance/difficulty feel against the real C64, the burn-out
explosion visuals frame by frame, and behaviour when the *last* droid on a deck is
consumed (deck-clear bonus interaction) — all wanted from KC's play-testing.
