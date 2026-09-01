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

Those are the pass's own figures and stay as they were. For what the banks hold **today**,
read the build gauges — the pass has been overtaken twice since, by the tranche split
(2026-09-01) and then by the SCANSTEP deferred carry, which alone put banks 5 and 6 well
above anything this table records.

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

## The stack page has 128 bytes free — measured 2026-08-31

**`&0100-&017F` was not written by anything in a 40-second play session**, and it is the only
contiguous main-RAM space left larger than the 16-byte fragment in the `PARAFNT` block. Found
while looking for 16 bytes for the lift's cleared-deck table (layer-12 DECISION 6).

**NOTHING IS IN IT.** That feature was built on it, measured, and then reverted whole when the
drawing half would not fit bank 7 — so this is a reserve, not a tenant. If that ever changes, say
so here and in `CLAUDE.md`, because the next person to chase a corruption bug needs to know
whether the stack page is carrying anything.

*How it was measured, and it is the seed-and-check the jsbeeb notes prescribe:* `&A5` written over
`&0100-&017F` from the emulator once the game was running, then play, a `CTRL+]` deck load, the
console main page and the droid database page, then read back. **All 128 bytes survived**, so the
stack never descended below `&0180` and the deepest push used at most 128 of the page.

*What was NOT exercised, and must be before anything relies on this:* the transfer minigame, the
lift's deck-selection screen, the game over, and the briefing. **Boot is a separate question** —
the loader's `*LOAD`s go through the MOS and DFS, which are heavy stack users, and the seed was
written after boot so that depth is unmeasured. `GoTitle`'s reloads make filing-system calls
mid-session for the same reason.

*So what it is safe for today:* state that is (re)initialised after boot and does not have to
survive a filing-system call — which is most per-game state, including anything cleared at
`StartGame` or on a new ship. Take it from the BOTTOM, `&0100` upward, which is 128 bytes away
from the deepest use ever observed.

*And what it is not:* a general-purpose region. Nothing should go here until its own path has been
seeded and checked, and a comment at the site should say which paths were.

## Held in reserve (next time RAM runs out)

- **`sprsplit.asm` → bank 5** (634 B out of bank 6, zero cycles): one
  `PAGEBANK` constant and the include moves. Its header already certifies
  it reads nothing bank-resident.
- **SCANSTEP tail folding in `tools/export_droids.py`** (~1,050 B in EACH
  of banks 5 and 6 for ~480 cycles/pass, ~1% of the blit window): the 70
  compiled rows per bank ending `SCANSTEP:RTS` can end `JMP ScanStepRts`
  instead. The mechanical-diff check cannot validate it — use the oracle.
  **Cheaper and less needed since 2026-09-01:** the deferred carry below
  left a cycle surplus this would spend out of, and took the two banks to
  674 B and 925 B, so the pressure that made it attractive is off.
- **`door.asm` → bank 4** (~610 B of main RAM, high effort): most of
  `door.asm` is called only from bank-4 code and reads `doorDef`; it needs
  ~650 B free in bank 4 first, which SCANSTEP folding (via bank 5 taking
  bank-4-resident, bank-independent code) could provide.
- **SCANSTEP's page carry — SPENT 2026-09-01** (hexwab, issue #1; commit
  833b640). `INC bufp` no longer tests for its own carry: the scanline IS
  `bufp AND 7`, so a low byte that has just wrapped to zero always takes the
  crossing branch, and `SprScanRow` can do the `INC bufp+1` once instead of
  335 expansions testing for it every step. **+668 B in bank 5, +656 B in
  bank 6, +12 B of code image, and ~3 cycles a step FASTER** — the only
  entry here that paid in both directions. Not a mechanical change, so the
  listing-diff check could not validate it; verified exhaustively instead
  (all 65,536 `bufp` values, comparing svp/bufp/A/carry/control flow),
  structurally (the patched instruction stream re-expands to baseline
  exactly) and at runtime (headless jsbeeb A/B, 400 frames, both `mapHX`
  parities and all eight `line` values). `src/sprite.asm`'s macro header
  carries the invariant — read it before touching SCANSTEP again.
- **`hsfont.asm` ≡ `textfont.asm`** (1,152 B, byte-identical): deletable
  if the high-score entry runs while `PARAFNT` is resident (move
  `highscore.asm`, ~655 B, to bank 5). Buys `PARTITL` headroom and load
  time, not scarce RAM — needs a boot-sequence decision first.
