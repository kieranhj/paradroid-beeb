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

Main RAM `code_end` = `&2FFE` (2 B free — unchanged by all of this). Bank 4: 26 B. Bank 5:
PARASPR unchanged; PARMAN uses 4,596 of its 16 K when swapped in. PARBRF: 1,188 B spare at
`&0400`. PARTITL: ~85 B spare after `TiLoadBrf`.

## Decisions you may want to revisit in the morning

1. **The page-5 droid portrait** — a genuine design question, not a task: the C64 floats it as a
   *hardware sprite over the scroll*, and the port has no sprites during the briefing (bank 5 IS
   the text). Options: (a) scroll it with the text — integrate `PoDraw` into the row painter, a
   visible deviation; (b) redraw over the buffer each field — costly; (c) drop it. Not built.
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
| **F2** title chatter | deferred by you; still blocked on 33 B of effect records vs bank 4's 26 |
| **F6** exit-load trim | deferred per "optimise loading later". Naive costs: ~1.1 s briefing→game, ~0.6 s briefing→title, one PARMAN load (~0.5 s) on the timed-out path only. §3d has the one-load plan |
| Held-L skips the 001 page? | untested nit: L held from the briefing may fall through the info screen's wait. Check by hand once |

## Things that cost something to learn (kept from the last session, still true)

1. **`font_end` + 96 is `PN_TABS`** — the gap above the font is 8 bytes, not 104 (BUGS.md #18).
2. **R8 is not optional in a CRTC teardown** — the rupture blanks rows with it.
3. New this session: **`LDA #PN_SPACE : BNE always` never branches** — `PN_SPACE` is zero. It
   shipped once (leading zeros printed as `0`) and is called out in `briefing.asm`.
4. **`$DD89`/`$DDB4` in §1 were not the score records' addresses** — the exporter labels them by
   text match now.
