# HANDOVER — no-load step 5: the briefing goes resident

**Your job: remove the last three post-boot disc loads, starting with the briefing's two.**
Branch `no-load`. Written 2026-09-09 by the session that did §11-§14 of `docs/no-load.md`, which
ran low on context. Everything below is measured; nothing in it needs re-deriving.

**STAGE 1 IS DONE — see `docs/no-load.md` §15 before this file.** It confirms 2B off the table,
corrects §3's page-4 figure below (435 -> 469), and records a decision that changes the design:
the pointer tables are NOT carried inside the streams but rebuilt at run time, worth 332 bytes.
§15e restates the budget, which §14c had 17 bytes short before any code.

**Read first, in this order:** `CLAUDE.md` (the rules; it is loaded for you automatically),
`docs/no-load.md` **§14** (the design and its measurements), then **§12a, §13, §11j**. `§1`–`§10`
are history and two of their tables are superseded — §1a says which.

---

## 1. Where the branch is

| | |
|---|---|
| post-boot loads | **3**: `PARAFNT`, `PARMAN`, `PARASPR` |
| disc files | 9 |
| free bank space | bank 4 **225** · bank 5 **2,650** · bank 6 **442** · bank 7 **775** = **4,092** |
| main-RAM code image | **28 B** free, `code_end` `&2FE4` |
| last five commits | `23ec207` §14 · `28121fe` PARBRF/PARALOW resident · `4304843` interning · `bd6a4f3` tail folding · `dc62e8c` the re-audit |

Take live figures from the build's own gauges, never from this file.

## 2. The decisions, already taken by KC

From `docs/no-load.md` §12a, KC chose **1C, 2B and 3A**. Measuring them (§14) changed one:

- **1C — the text depacks to main RAM**, so the briefing's code and its text need not share a
  bank. Page streams are distributed across banks by a per-page bank byte; nothing spans a bank.
- **2B — NOT NEEDED, and this is the finding.** §5's "buffer needed is 1,082" is a page *with* its
  114-byte pointer tables. Records alone top out at **967**, inside the 1,024-byte map. **The
  briefing keeps its five pages**, exactly as the original has them. *(Confirm with KC before you
  build on it — it reverses his explicit pick, on measurement.)*
- **3A — `keyredef` packed** (776), depacked into the same arena on CTRL+R and run from there.
  It is 1,014 unpacked, so **`ASSERT` it against the arena size**; the margin is what 3B was
  meant to remove.

## 3. The numbers you do not need to re-measure

Per page, from the generated `src/data/briefing.asm`: 57 row records plus a 114-byte pointer pair
(`brRowLo_p`/`brRowHi_p`).

| page | records | + tables | ZX0 with tables |
|---|---|---|---|
| 0 | 624 | 738 | 474 |
| 1 | **967** | **1,081** | 671 |
| 2 | 962 | 1,076 | 643 |
| 3 | 932 | 1,046 | 634 |
| 4 | 435 | 549 | 356 |
| | 3,920 | 4,490 | **2,778** |

**The budget: 2,778 (text) + 471 (`briefman` 456 + `sndchat` 15, unpacked because they run) + 776
(`keyredef` packed) = 4,025 against 4,092 free. 67 spare.** If you need more, the next **432** are
in packing `brfImg`/`lowImg` — §13 stores them raw (1,012 and 919 against 769 and 730 packed) —
which needs the two-pass build of §12a option 4C. **Measure before you spend; three estimates in
this document have been checked against reality and two came in low.**

## 4. The arena, and the one thing nobody has explained

Seeded `&4220-&460F` with `&A5` at the title, ran the briefing, read it back: **296 bytes written,
all of them `&4220-&4347`. `&4348-&4600` untouched**, and contiguous with the tile map, so the
briefing's arena is **`&4348-&4A00`, 1,720 bytes**.

`BmSnap`'s rectangle is `BR_PO_ROWS` 11 x `BR_PO_SPAN` 96 = 1,056 from `SPR_SAVE` `&3E00`, which
ends *exactly* at `&4220`. **The 296 bytes past it are unexplained.** The design therefore puts the
buffer at **`BR_BUF = &4500`** — 440 bytes clear of the high-water mark, still 199 spare on the
largest page. **If you can find out what writes `&4220-&4347`, do; if you cannot, do not move the
buffer down to reclaim it.** A `write` breakpoint at `&4300` during the briefing is the quick way.

## 5. The design

- **One ZX0 stream a page, with its pointer tables inside it**, assembled by the exporter *as if
  it lived at `BR_BUF`* — so the absolute addresses in `brRowLo_p`/`brRowHi_p` are correct by
  construction and nothing is relocated at run time. This is worth 337 bytes over keeping the
  tables bank-resident, and it is the whole reason the budget closes.
- **The renderer walks main RAM** for text and needs no paging at all — simpler than today.
- **`keyredef` shares the arena** with the page buffer: CTRL+R depacks over the current page, and
  the briefing re-depacks the page on return (it already repaints).
- **`briefman` + `sndchat` stay bank-resident code**; the streams go wherever they fit.

## 6. Build it in these stages, committing each one green

**Stage 1 — the data pipeline, no behaviour change.** `tools/make_briefing.py` emits the five
per-page ZX0 streams (tables inside, assembled at `BR_BUF`) plus a per-page bank/address table;
place them in the banks. The old path still runs. **Verify offline**: decompress each emitted
stream in Python and compare byte-for-byte against the page's current layout. Costs 2,778 bytes
while both exist, which fits.

**Stage 2 — the renderer reads the buffer.** Page turns depack into `BR_BUF`; the row walk reads
main RAM. `PARMAN` still loads and `briefman` is still inside it. **Verify**: the briefing paints
identically — compare the strip against the previous build with §11j's A/B recipe, at the same
page, or walk all five pages by eye.

**Stage 3 — the big one.** `briefman`/`sndchat` become bank-resident; `keyredef` becomes a packed
stream depacked into the arena; `BrTimeout` stops loading `PARMAN`; `BrDispatch` stops reloading
`PARASPR` (bank 5 is never evicted now); `PARMAN` leaves `make_disc.py`'s `LAYOUT` and its `SAVE`.
**Verify**: the whole front-end loop (§7), CTRL+R, and that the blitter still draws after a
briefing — that last one is what the `PARASPR` reload existed for.

**Stage 4 — `PARAFNT` becomes boot-only.** With nothing staging at `DEPK_STREAM` any more,
`&3000` has no destroyer left; `ts_loads` is shared three ways (boot, game-over, briefing exit) so
it needs a flag or a split. **That is the last load.**

**Stage 5 — the terminal dividend.** With no filing call after boot: `dfsSave` (912 B of bank 6),
`SaveDfsWs`/`RestoreDfsWs`, the OSCLI strings and `UnpackBankIn`/`BootBanks` become dead. §11h
measured what step 6 really yields (241 B of scattered main RAM, not 869) — read it before
believing the old figure.

## 7. How to verify, with the exact levers

**The front-end loop** (do this after every stage from 3 on): cold boot → title → fire → game →
ESCAPE → death → game over → high-score entry → three fires → **title again** → wait for the
briefing timeout → fire → game. The second title is the one that matters: it arrives through
`GoTitle` after `RestoreDfsWs`.

**The A/B differential** (§11j) is the tool for anything that should not change what is drawn, and
**it is worthless without the seed pin**: two builds do not play the same game, because
`TiBootPal` seeds `drSeed` from the title dwell and the images boot at different speeds. The first
attempt scored 1,672 wrong bytes on a provably correct build. The recipe:

1. breakpoint `gs_seeded` (`&A795`, bank 4), press fire at the title, let both stop there;
2. `write_memory` `drSeed` (`&B5B6`) = the same constant in both, **with `bank: 4`**;
3. drive both identically, then **align on `gameTick` (`&2E4C`), never on frames**;
4. stop both at the top of the main loop (`&111E`) so the dumps are at the same point in the pass;
5. confirm the sprite pool (`&2CFC`, 48 bytes) matches, then `save_memory` `&3E00-&8000` and `cmp`.

**Reaching screens** (from §10; all still work): transfer = poke `xferDroid` `&148A` to a live
droid index · console = breakpoint `&1F92`, read A (the tile under the player), poke that operand
· lift = poke `liftMode` `&2720` = 1 (skips `LiftFind`, so the *selection* is not exercised) ·
database type = `dbType` `&9D9E` **with `bank: 7`** · transfer win = CTRL+W *after* a side is
chosen. `key_down` takes `inkey:` numbers, so Z −98, X −67, K −71, M −102, L −87, ESCAPE −113,
`[` −57, `]` −89.

**Addresses move every build.** Re-dump them:
`./bin/beebasm.exe -i src/main.asm -do build/symbols.ssd -D RELEASE=0 -d | tr ',' '\n' | grep "'name'"`

## 8. Traps this branch has already paid for

- **beebasm resolves constants in file order.** §13's move needed six hoisted; four are generated,
  so `src/data/briefconst.asm` exists. If you move a block and get *Symbol not defined*, that is
  what it is — a static probe over the include order finds them all in one pass rather than six
  rebuilds.
- **Only the LAST bank block can be filled after the fact** (`COPYBLOCK`), because each block
  `CLEAR`s and re-`ORG`s the same `&8000`. This is why `PARBRF`/`PARALOW` went to bank 6 and why
  the overlays are assembled above it.
- **`PARBRF`'s ceiling is `&0800` and it is measured, not caution** — `&0800-&08FF` is the MOS's
  sound workspace and it is chewed while the MOS owns IRQ1V.
- **The arena rule** (§2): leaving a modal screen puts the map back; any screen that READS the map
  ensures it for itself. Applies to the new buffer too if it overlaps the map — and it does.
- **A depack is a field of work and must never sit between a palette change and the redraw that
  justifies it** (§7). Two bugs came from that.
- **Do not use `2>&1` on `build.ps1` from the PowerShell tool** — beebasm writes progress to
  stderr and it throws on a successful build. Plain `.\build.ps1` is fine; the Bash tool is fine
  either way.
- **`docs/ram-pass.md`'s rejected list is rejected** — do not re-cost the blitter unrolls,
  `palPanel` or the `ALIGN`s. The compiled-code seam was mined out on 2026-09-08 (§11j, §11k).

## 9. Open questions for KC

1. **2B is off the table by measurement** (§2 above) — confirm before building on it.
2. **What writes `&4220-&4347` during the briefing?** Designed around, not understood (§4).
