# The RAM recovery pass (2026-08-25)

Working notes for the five-commit `ram-recovery` pass that bought back the
room for the final features. Every figure here was measured from the build
output on 2026-08-25 evening; take current numbers from `PRINT "code"` and
the bank gauges, never from this file.

## What it bought

| Region | Before | After | Gained |
|---|---|---|---|
| Main RAM code image | ends `&2FFE`, **2 B** | ends `&2D81`, **639 B** | +637 |
| Bank 4 (`PARADAT`) | 3 B (+17 pad) | **51 B** (+17 pad) | +48 |
| Bank 5 (`PARASPR`) | 1,033 B | 602 B | −431 (spent on the effect blitter) |
| Bank 6 (`PARSPR2`) | 4 B | **114 B** | +110 |
| Bank 7 (`PARXFER`) | 7 B tail + 66 B pad | 7 B tail + **~176 B pad** | +110 |
| `PARBRF` overlay | 3 B | **56 B** | +53 |
| `PARDEPK` overlay | 239 B | 144 B | −95 (took the boot loop) |
| `PARAFNT` block | ~1 B | ~49 B | +48 |

Cycle cost of the whole pass: **~57 cycles per 79,872-cycle pass** (0.07%),
all of it from decision 5's helpers; nothing inside the blitter's inner
loops, the compiled shifts or the rupture was touched.

## The decisions

**[DECISION 1] Dead data deleted.** `drSpeedF`/`drSpeedFHi` (48 B, bank 4)
were emitted by `tools/export_droids.py` for an 8.8 per-frame speed that was
never wired up; nothing read either label. `pnTabWeapon`/`pnTabSpeed` (48 B
of `PN_TABS` + 12 B of copy loop) were mirrored by `PageTabsIn` and never
read by any bank. Both deleted at the exporter/source. `PN_TABS` is 48 B
now — the ASSERTs moved with it.

**[DECISION 2] The effect blitter lives in bank 5** (`src/sprfx.asm`).
`SprEfSetup/Box/Skip/Fetch/Draw/Restore` (431 B) only ever run with
`PARASPR` paged in — effects exist only in that bank, whatever the slot's
shift — so `SprSetSlot`'s effect arm pages bank 5 from main RAM and jumps
in; `sd_go` and `sr_go` already run under it. Zero cycles: the bank was
already selected on every entry. **Load-bearing invariant, stated in
`sprfx.asm`'s header: no effect blit may run while the briefing's `PARMAN`
occupies bank 5.** True today (the briefing runs its own loop and never
calls the blitter; both exits reload `PARASPR`), but it is a rule now, not
a habit.

**[DECISION 3a] The boot bank loop lives in `PARDEPK`.** `BootBanks` (the
four load-and-unpack blocks), `UnpackBankIn` and the `PARADAT`/`PARSPR2`/
`PARXFER` command strings ride in the overlay they depend on — every caller
runs with it resident, including the briefing exit, which OSCLIs `loaddepk`
again before its `PARASPR` reload. `loaddepk` and `loadspr` therefore stay
in main RAM. 92 B.

**[DECISION 3b] One droid icon copy, in main RAM.** `droidicon.asm` moved
from bank 6 into the code image beside `sprite.asm`; `droidicon7.asm`
(layer-10 DECISION 14's second copy) is deleted, along with its arm of
`tools/export_droidicon.py`. `console.asm` (bank 6) and `xfericon.asm`
(bank 7) read the same main-RAM labels — main RAM is visible from every
bank, so no copy discipline and no exporter-drift hazard. 110 B each in
banks 6 and 7 for 110 B of main RAM, taken because the pass had just made
the code image the *least* tight of the three.

**[DECISION 4] `LiftPlace`'s two byte-identical unrolled ×32 shifts became
`LpMul32`** (a loop, Y-indexed because X holds `liftPos`). 50 B for ~45
cycles a call, paid once per lift arrival. The OSCLI string table costed in
the plan was dropped: 3a had already moved three of the eight strings into
`PARDEPK`, and the remaining five net under ~20 B — not worth the churn.

**[DECISION 5] `PAGEBANK` and `PNMIRROR` became subroutines.**
`PgData`/`PgSpr`/`PgSpr2`/`PgXfer` in main RAM; 36 code-image sites and 13
`PARBRF` sites are `JSR` (or `JMP` where the pair was a routine's tail).
The shadow-first store pair stays adjacent inside the helper, so the IRQ
contract is unchanged — between the `JSR` and the `LDA` both `ROMSHAD` and
`ROMSEL` still name the old bank, which is consistent. **Excluded and still
inline: `PAGESPRBANK` (per-slot, 16-cycle budget), `SprFetchRow`'s pair
(~64 calls a pass inside the saturated blit window), the low overlay and
the IRQ.** `PNMIRROR`'s four expansions became `PnMirror` (must be called
with `SWRAM_DATA` paged). ~57 cycles a pass, from `SprRestoreAll`/
`SprDrawAll` tails, `SprSplitOK` and `PanelTick` — everything else
converted is transition code.

## The oracle recipe changed — this matters for every future diff

`CLAUDE.md` used to say "poke `JSR SprDrawAll` to NOPs so a spinning rotor
cannot pollute the diff". **That has been insufficient since the tranche
split**: when the split engages, draws go through the two `JSR SprDrawTr`
call sites instead, and a diff taken with only `SprDrawAll` NOPed shows a
player-sprite-shaped block of "corruption" that is nothing of the kind.
NOP **all three** JSRs (find them in the listing: `JSR` to `SprDrawAll`
and both `JSR`s to `SprDrawTr`, all near the top of the main loop).

Two more artefacts of the frozen state, learned the hard way during this
pass's verification:

- Restores replay every pass while draws are off (`sprSaved` is only
  cleared by a draw), so freeze **with the player at rest** — a freeze
  taken while the view is still decelerating stamps stale tiles into a
  scrolled buffer on every subsequent pass.
- A freeze taken while two sprites overlap preserves the overlap ghost
  that normal running heals on the next draw. Anything droid-shaped in
  the diff: resume draws, let it heal, re-freeze somewhere quiet.

A door animating under a loitering droid, and the cleared-deck floor
sequence after a `DEBUG_KILL`, are *legitimate* world changes that also
show up as diffs; freeze `JSR DroidsUpdate` too if the deck cannot be
made quiet.

## Costed and rejected (do not re-litigate)

- **The three `ALIGN`s recover nothing.** `tiledefs` and `planInk` have
  `LO()==0` baked into pointer arithmetic; `colourMap`'s pad just moves to
  `tiledefs`' ALIGN if deleted. Confirmed by geometry 2026-08-25.
- **Rolling the blitter's unrolls** (`sd_fastrow`/`sr_fastrow`, compiled
  restore): +8,000–10,700 cycles/pass for 0.1–2.3 K. No.
- **Computing `palPanel`**: +640 cycles/pass inside the IRQ. No.
- **`blankTileRow` to "the &8A80 gap"**: that gap does not exist —
  `deckDroids` runs straight into `deckPackHi`; the memory-map entry
  claiming it was stale.

## Held in reserve (next time RAM runs out)

- **`sprsplit.asm` → bank 5** (634 B out of bank 6, zero cycles): one
  `PAGEBANK` constant and the include moves. Its header already certifies
  it reads nothing bank-resident.
- **SCANSTEP tail folding in `tools/export_droids.py`** (~1,050 B in EACH
  of banks 5 and 6 for ~480 cycles/pass, ~1% of the blit window): the 70
  compiled rows per bank ending `SCANSTEP:RTS` can end `JMP ScanStepRts`
  instead. The mechanical-diff check cannot validate it — use the oracle.
- **`door.asm` → bank 4** (~610 B of main RAM, high effort): most of
  `door.asm` is called only from bank-4 code and reads `doorDef`; it needs
  ~650 B free in bank 4 first, which SCANSTEP folding (via bank 5 taking
  bank-4-resident, bank-independent code) could provide.
- **`hsfont.asm` ≡ `textfont.asm`** (1,152 B, byte-identical): deletable
  if the high-score entry runs while `PARAFNT` is resident (move
  `highscore.asm`, ~655 B, to bank 5). Buys `PARTITL` headroom and load
  time, not scarce RAM — needs a boot-sequence decision first.
