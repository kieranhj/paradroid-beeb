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
   RAM numbering. ~9.8 K of it is still free.
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
11. Small timing stand-ins, faithful in rate if not mechanism: the select countdown ticks
    every other pass (~8 s for 99 BCD, near the original's `DelayScore(80)` pacing); the
    play counter every other iteration as `$20DA` does; `DoScore` keeps dribbling banked
    points during the game where the C64's modal loop froze them.

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
