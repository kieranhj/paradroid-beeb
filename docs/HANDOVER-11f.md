# Layer 11f handover — morning report, 2026-08-22 (overnight session)

**Read `docs/layer-11f-frontend.md` first** — §4a–§4e are what is built and what was learned.
This file is the state, what happened overnight, and what is left.

## TL;DR

**F1, F3, F4 and F5 are built and verified in jsbeeb. The briefing works end to end**: the title
times out into it, all five pages scroll smoothly under the rupture at the C64's own speeds and
dwells, fire starts a game from anywhere in it (blitter reloaded, deck playable), falling off
page 5 returns to the title, and page 5 shows the **live** high-score table. The F1 "loose end"
is closed — not a defect. Everything is committed on branch **`layer-11f-frontend`** (four
commits: F1, F4, F5, docs).

## What was done overnight

1. **Committed the F1 work** you left in the tree (`79d9022`).
2. **Closed the loose end**: `hsHigh` not matching a poked `score` was `scoreAdd`/`scoreSub`
   pending points draining through `DoScore` during the death sequence (`DoAging` banks alert
   payouts too). Poked a score *with the queues zeroed*, self-destructed: `hsHigh` came back
   byte-exact. The original's own architecture; no code change.
3. **Reworked the text pipeline per your steer**: `export_briefing.py` now decodes the C64 text
   ONCE into **`src/data/briefing.txt`** — hand-editable, verbatim (pause-key legend included),
   refuses to overwrite without `--force` — and the new `make_briefing.py` converts it every
   build (`build.ps1` runs it), validating characters and page widths and round-tripping the
   output against the input. **Edit briefing.txt, rebuild, done.** Note it is gitignored with
   the rest of `src/data/` (copyright), so your edits live outside git.
4. **F4** (`8d752e5`): `PARBRF` at `&0400` (driver, 1,004 B of 2,192 — loaded by `TiShow` on
   every title), `PARMAN` in evicted bank 5 (text, 4,596 B of 16 K). Net resident main-RAM cost
   of the whole layer: **zero** — the hooks are a `JMP` retarget in `TiWait`, two
   `GameStartInfo` calls retargeted to `BrDispatch`, and the `.ts_loads` label so the exit can
   re-enter TitleSeq's own tail instead of copying it. Both exits reload `PARASPR`.
5. **F5** (`683f3de`): the scroll — the C64 loop transcribed, speeds decoded from the listing
   (`MoveScreen` SUBTRACTS `ySpd+1 = $FF - joyYDir`): 1 scanline/field centred, **M** = 2×/skip
   dwells, **K** = pause, **L** = fire. 15-row window, staged 16th row painted as it scrolls in,
   45 rows of travel (= the C64's own $168). Page 5's score lines patched live from bank 7
   ([DECISION 7]) — verified with a real game: `Worst score of the day: 0 - AAA`.

## Numbers (from the build's own PRINTs, 2026-08-22)

> **Superseded by the RAM recovery pass (2026-08-25)** — main RAM 639 B, bank 4 51 B, PARBRF
> 56 B; see [`ram-pass.md`](ram-pass.md). The figures below are the 11f-era record.

Main RAM `code_end` = `&2FFE` (2 B free — unchanged by all of this). Bank 4: 26 B. Bank 5:
PARASPR unchanged; PARMAN uses 4,596 of its 16 K when swapped in. PARBRF: ~~1,188 B spare at
`&0400`~~ **81 B** — that figure was measured to `&0C90` and PARBRF's ceiling is `&0800`, the
page above being the MOS's sound workspace (§4c's own hard lesson). PARTITL: ~85 B spare after
`TiLoadBrf`.

**After the chatter, 2026-08-22**: bank 4 **4 B**, PARBRF **3 B**, PARMAN 4,985 B used, main RAM
unmoved.

## Decisions you may want to revisit in the morning

1. ~~The page-5 droid portrait~~ **DONE** (KC chose: scroll it with the text; commit `4c8c007`):
   `PoDraw` renders a random type into the strip at text cols 34–39 beside the score table, the
   rectangle is snapshotted to `SPR_SAVE`, and the painter composites its bands as the rows
   paint and scroll. **Hard lesson bought on the way:** `PARBRF`'s ceiling is `&0800` — the page
   above is the MOS's sound workspace, and its IRQ writes there through the title's loads; a
   1,208-byte overlay died of it. The briefing's bank-half (`src/briefman.asm`, bank 5) now
   carries everything that need not be main RAM.
2. ~~The panel during the briefing~~ **DONE** (follow-up commit `9de9fe5`): the box now carries
   bars, logo, "Briefing" and the last game's score — `PanelInit` + the new `PnBriefing` in
   bank 6, called from `BrRun`. NB the C64 shows the *one* score there (the last game's, zero at
   boot), not HIGH and LOW — the layer doc's §1 was wrong and §4e carries the correction.
3. **`briefing.txt` wording** — the C64 text is verbatim, including `your C64 remote terminal`
   (page 4) and the whole pause-key legend (RUN/STOP, CLR/HOME, f7 cheese, f8) which is untrue
   of the port. All yours to edit now, in the text file.
4. **The `w Graftgold Ltd. 1986.` oddity** in briefing.txt: the C64 code there is $54, the wide
   glyph pair — which renders as the **©** mark on screen (confirmed in jsbeeb), so the display
   is faithful; only the decoded text file shows it as `w`. Don't "fix" it to `(c)` without
   checking what the glyphs draw.

## Still open in the layer

| | |
|---|---|
| Portrait + panel box | the two decisions above |
| ~~**F2** title chatter~~ | **BUILT AND VERIFIED 2026-08-22** — layer doc §4f. The block dissolved: it is the *briefing's* sound, not the title's (`TitleLoop` writes `$11` after `ShowTitle` returns), so the 50 Hz tick was already running; and one rewritable scratch slot in bank 4 serves all three records, which live in bank 5. **Signed off by your ear the same day**, after three rounds on the lift blip it reuses (periodic bass, then 6 dB down, then a fourth round reverted as too far). The in-game lift and both briefing exits re-heard and fine. Nothing outstanding |
| **The ± volume keys** | **WANTED 2026-08-22** (KC: "we'll definitely want that volume control"), promoted out of 11e §8's deferred list after three rounds spent turning the lift blip down. Blocked on the clamp round nine deleted (4–6 B in a bank 4 with 4) and a home for the key poll in a machine whose every region is full. Costed in 11e §8; it should land before any more eared level tuning |
| **F6** exit-load trim | deferred per "optimise loading later". Naive costs: ~1.1 s briefing→game, ~0.6 s briefing→title, one PARMAN load (~0.5 s) on the timed-out path only. §3d has the one-load plan |
| Held-L skips the 001 page? | untested nit: L held from the briefing may fall through the info screen's wait. Check by hand once |

## Things that cost something to learn (kept from the last session, still true)

1. **`font_end` is not the end of the region — `PN_TABS` follows it** (BUGS.md #18). At the time 96 B of tables / 8 B gap; since RAM pass 1 it is 48 B / ~49 B. The lesson holds, the numbers moved.
2. **R8 is not optional in a CRTC teardown** — the rupture blanks rows with it.
3. New this session: **`LDA #PN_SPACE : BNE always` never branches** — `PN_SPACE` is zero. It
   shipped once (leading zeros printed as `0`) and is called out in `briefing.asm`.
4. **`$DD89`/`$DDB4` in §1 were not the score records' addresses** — the exporter labels them by
   text match now.
