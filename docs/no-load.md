# The no-load plan — everything resident, loading once at boot

Working notes for the `no-load` branch. The goal is hexwab's, from
[issue #2](https://github.com/kieranhj/paradroid-beeb/issues/2): get the game small enough that
loading happens once at boot and never again. The reply on that issue carries the full measured
analysis; this file is the working copy, kept current as the branch lands.

**Read the arena rule below before touching `&4600`.** It is the only invariant on the branch and
it has already been broken twice.

---

## 1. The problem, in one table

The disc is a 41K read-only store the game pages from. "No loading" means holding, in RAM, every
byte it supplies *after boot* — including the restorations, which are the expensive part:

| stream supplied after boot | packed | when |
|---|---|---|
| PARMAN | 3,595 | briefing entry |
| PARASPR | 3,512 | briefing exit — the blitter back into bank 5 |
| PARTITL | 1,597 | every title |
| PARAFNT | 1,947 | after the title, after the briefing |
| PARBRF | 770 | every title |
| PARALOW | 730 | after the title |
| **total** | **12,151** | |

Free SWRAM at the start of the branch was **1,237 B** and the code image had 14.

Compression alone cannot close that: packing only helps content that has somewhere to be
*depacked to*, and no bank is free during play. One constraint shapes everything — **only one bank
is visible at a time**, so a stream in bank 7 cannot be depacked into bank 5. Every cross-bank
depack needs a main-RAM transit buffer, which is what `DEPK_STREAM = &3200` is, and why PARAFNT
gets destroyed and reloaded.

**Loads come off one at a time, each costing its packed size resident, forever.** Only the
briefing's three are a bundle. That is what makes the work schedulable.

---

## 2. THE ARENA RULE

The unlock is the **tile map**, `&4600–&4A00`, 1,024 contiguous bytes.

`door.asm` gives each open door a private copy of its tile's 16 definition bytes rather than
patching the map, and nothing else writes `&4600–&4A00` after `BuildLevel`. So **the map is a pure
function of the deck number** and can be rebuilt in ~40k cycles (0.02 s) at any time. That makes it
scratch for the whole of any modal screen.

The rule has two halves and both are load bearing:

> **Leaving a modal screen puts the map back** — `RedrawAll` rebuilds it, below `PalBlack`, before
> anything reads it (`screen.asm`).
>
> **Any screen that READS the map ensures it for itself on the way in** — the console's deck-plan
> page does, at `ct_trydeck` in `main.asm`.

The second half exists because two console pages in a row never pass through `RedrawAll`: the
console does not return to the deck until it closes. Cleaning up in whichever screen dirtied the
arena would work today and rot the moment another user appears; ensuring on the read side is one
rule that holds however many users it gains.

**Who reads the map while a modal screen is up:** only `ConDeck7`, the console deck-plan page.
Everything else — transfer, lift, information, game over — leaves it idle, because the modal arms
all `JMP ml_modalend` (`main.asm:1552–1625`) ahead of the level draw, `AnimTick` and
`AnimScanPass`; `MapGuardSnap` is `DEBUG_MAPGUARD` only.

**Three users share `&4600` and never collide**, because each depacks its own on entry and no two
can be up together:

| user | bytes | screens |
|---|---|---|
| `XB_BASE` — transfer board | 876 | the transfer game |
| `SV_BASE` — lift artwork | 966 | lift screen, console ship page |
| `PO_BASE` — portrait pool, one chunk | 512 | information, database, briefing page 5 |

The lift view and the transfer game are the same screen machinery and cannot coexist.

---

## 3. The per-screen arena table

Measured from source. Regions: charset `&0400–&0C90` (2,192) · PARAFNT `&3000–&3E00` (3,584) ·
`SPR_SAVE` `&3E00–&4600` (2,048) · tile map `&4600–&4A00` (1,024) · panel `&4A00–&5400` (2,560) ·
LUTs `&5400–&5800` (1,024) · strip `&5800–&8000` (10,240).

Every modal screen uses the strip as its framebuffer and keeps the panel up, so neither is ever
available. `SPR_SAVE` is largely spoken for too — `xsScr`/`xsCram`/`xsStage`/`xsGlyphOf` are
**1,920 of the 2,048** on the in-game screens (`xfer.asm:2229`), leaving 128 at `&4080` and 128 at
`&4580`; the briefing's portrait snapshot is 1,056. At title time `TI_BASE = &4000` runs 16,000
bytes to `&7E80`, so the tile map, panel and LUTs are all framebuffer and **there is no arena at
the title at all**.

| screen | best contiguous arena |
|---|---|
| transfer / lift / console ship / information / game over | **1,024** (the map) |
| console — deck plan | 512, fragmented (the map is live) |
| briefing | 3,196 (map + `SPR_SAVE` tail + charset tail) |
| title | ~1,969, and **not** the map |

---

## 4. What has landed

Branch `no-load`, off `main` at `eabeffe`.

| commit | what | bank 7 free |
|---|---|---|
| `25f52e7` | the tile map becomes an arena (`RedrawAll` rebuilds) | 7 |
| `bb656d3` | `poLut`: two tables of 256 were one of 16 — **489** | 263 |
| `b852e43` | transfer board packed, 876 → 288 — **588** | 1,031 |
| `73494a2` | lift screen packed, 966 → 409 — **557** | 1,485 |
| `ed96465` | the plan page rebuilds the map it reads | |
| `2c97f43` | portrait pool packed, 8 images a chunk — **1,661** | **3,021** |
| `b385cd6` | the board depacks before the palette moves | |
| `7c0c4d5` | BUGS.md 23 and 24 | |

**Step 2 is complete: bank 7 went from 7 bytes free to 3,021.** Content saving 3,295.

`poLut` is the one that beat its estimate by not being a packing job at all: both 256-byte tables
were one 16-byte table written out longhand, `left = poLut[b >> 4]`, `right = poLut[b AND 15]`.
**Ask "is this generatable?" before reaching for ZX0.** `xferboard` was checked the same way and
is not — its three glyph sets use logicals {0,3}, {0,1,3} and {0,2,3}, so the recolour is partial
and the subset is artwork, not a rule.

---

## 5. What is left

Order below is the posted one, with corrections found since.

**Step 3 — `hsfont` dedup + PARTITL relocation.** See §6; it is the next thing.

**Step 4 — the individual loads**, cheapest first, as space allows.

**Step 5 — the briefing page split.** The text is 4,608 raw / 2,438 as one stream; as five page
streams **2,805 (+367)**, and the buffer needed is **1,082**, the largest page, against the
briefing's 3,196 of arena. Bank 5 is then never evicted, which kills PARASPR's 3,512-byte
restoration — the single biggest item — and every depack becomes bank → main RAM, so the `&3200`
transit buffer goes and `&3000` survives the briefing.

**Step 6 — reclaim the DFS space.** Measured at **869 bytes**: `SaveDfsWs`/`RestoreDfsWs` 74,
post-boot OSCLI strings 52, their call sites ~40, `UnpackBankIn`+`BootBanks`+strings 113,
`PageCopyAt`/`PageLowIn` 65, `.start` 30, `&0300–&03DF` 224, `&0D01–&0D8F` 143 (free because no
disc means no NMI), stack page 128. **It is in six pieces, the largest 374**, and no stream needing
a home is smaller than 379 — treat it as ~500 usable.

**Step 7 — zx02, last.** It changes nothing: all fifteen streams in the plan are **byte-for-byte
identical in size** under ZX0 and zx02. The format differences only bite on the large bank files
(11 bytes on 15,832) and nothing in the plan is that big. Its win is the decompressor — ours is 263
bytes, `zx02-optim` 132 — so ~140 bytes of code image plus decode speed, against a new format
(`zx0.py`, `make_disc.py`'s round-trip and `in_place_delta`, `FNT_STREAM`). Doing it early would
swap the depacker at the base of the programme and re-derive `FNT_STREAM` twice.

**Step 8 — drop the Master requirement.** Not a step; the pass/fail.

### Ruled out, with the measurement

- **A runtime generator for the compiled shifts.** They pack to **12.6%** — all four are 2,375
  bytes as one stream — so ZX0 already exploits the redundancy a generator would, for a
  decompressor we have already paid for. The joined stream is only 210 bytes smaller than the two
  separate ones, so shifts 2/3 are not derivable from 0/1 in any way a compressor can see.
- **The Master cache (issue #2 step 2).** Every number here was obtained statically, and steps
  1–3 build and verify with the disc loading still in place.
- **`BuildMulTabs` as separable init.** `ts_loads` calls it, `BuildCharPtrs` and `SprBuildMask` on
  **every** title, because `TI_BASE` sits on top of those tables at `&5400`. Step 1's yield is
  `.start`, the bank loader and the paging helpers, ~208 bytes.

---

## 6. Step 3 in detail

**What it is:** delete `hsGlyphs` and relocate PARTITL off `&3000`, so the text font survives the
title.

`hsfont` is `HS_GLYPHS = 72` × 16 = 1,152 bytes, and **all 72 glyphs are byte-identical to glyphs
already in `textfont`** — permuted, not contiguous, which is why a block diff misses them.
`export_portraits.py`'s pattern applies: emit a 72-byte remap and assert the identity over all
inputs every run. Packed, the dedup is worth 315; raw, 1,080 off the overlay.

`HsGlyph` is the only place the font base appears, and `HsWide` does all its arithmetic in **index
space** before calling it — `CMP #HS_UPPER_R`, `ADC #HS_UPPER_R`, the `HS_LOWER_M`/`HS_W_RIGHT`
sentinels. So the change is `TAX` / `LDA hsRemap,X` and one base swap: **+4 bytes of code**, and
every wide-capital path inherits it.

**The precondition is the relocation**, and they are one change, not two: `hsfont` exists only
because PARTITL is assembled *over* `textfont`.

PARTITL is `&3000–&3CEB`. With `hsGlyphs` gone it is 2,227 raw and splits by kind:

| | raw | needs |
|---|---|---|
| `title.asm` driver | 341 | main RAM (code) |
| `highscore.asm` | 607 | main RAM (code) |
| `data/title.asm` artwork | 1,140 | nothing — an RLE stream read into `TI_BASE` |
| remap + hs strings | 139 | nothing — data |

- **The code, 948 + 139, goes to the charset tail** `&07F4–&0C90` (1,180). PARBRF is `&0400–&07F4`
  and arrives *later*, inside `TiShow` via `TiLoadBrf`, after `TiBootPal` and `HsEntry` have run —
  so they never overlap, and both die at the next `BuildCharset`.
- **The artwork goes to bank 7 raw, 1,140**, read in place by `TiPaint` with the bank paged. It
  cannot be packed: there is no arena at title time (§3).
- Neither `title.asm` nor `highscore.asm` has an `ALIGN` or a hardcoded `&3xxx`; every
  self-modification is `HI(label)`/`LO(label)` and the only absolute tables are `BUF_BASE`-relative.
  **Both relocate by changing the ORG.**

**Trap:** PARTITL ends `&3CEB` and `FontCell` starts `&3CED`. That two-byte clearance is
deliberate — it is how `highscore.asm` can call `FontCell` today. The title destroys `textfont`,
`panelframe` and `strings` but *not* the 201 bytes of font code.

**CORRECTION to the posted plan: step 3 does not remove the PARAFNT reload on its own.**
`ts_loads` is shared three ways — boot, game-over, briefing exit — and the briefing destroys
`&3000` independently: `BrTimeout` stages PARMAN at `DEPK_STREAM = &3200`, inside the font block.
`&3000` has two destroyers; step 3 removes one and **step 5 removes the other**. Neither alone
removes the load. So step 3 today is a ~1,140-byte spend with a deferred payoff, taken because it
is a prerequisite and bank 7 now has room.

---

## 7. Traps this branch has already paid for

- **A depack is a field of work (~34k cycles) and must never sit between a palette change and the
  redraw that justifies it.** Cost two bugs: the transfer *exit* flashed the board in the deck's
  palette (`BuildLevel` ahead of `PalBlack`), and the *entry* flashed the information screen in the
  board's palette (`XfBoardIn` inside `XferEnter`'s gap). Both fixed by moving the depack out of
  the gap — below `PalBlack` on the way out, ahead of `XferEnter4` on the way in.
- **Check the register contract of any routine you change.** `PoImgPtr` was three shifts and two
  adds and touched no index register, so `pod_ybase` keeps its loop counter in X across it.
  `Zx0Unpack` destroys X and Y. That presented as the whole game hanging on a black screen for
  fifty seconds; it was not hanging, it was depacking in a runaway loop. Reading the depacker's
  zero page (`zxofs`, `zxlen` healthy mid-stream) is what ruled out corruption.
- **`(slot AND 7) * 64` is a nine-bit number** and the `ROR` chain leaves the top bit in carry. The
  flat pool never met it because it took the page from `slot DIV 4` separately.
- **beebasm resolves constants in file order.** A generated data file that defines constants must
  be `INCLUDE`d *before* the code that reads them — `xferboard.asm` and `sideview.asm` both had to
  move ahead of their consumers. The other way round the two passes disagree; `console.asm`'s
  header describes the same trap.
- **The `ALIGN` quantisation is real and cuts both ways.** Savings before `plandata.asm`'s `ALIGN`
  are recovered in whole pages; the remainder sits in the pad until the next change collects it.
  The gauge moved 256 / 768 / 454 / 1,536 for content savings of 489 / 588 / 557 / 1,661. **Quote
  a bank's pad and tail as a pair.**

## 8. How to verify a packing change

1. **Offline, and it is the strong one:** decompress the emitted stream and compare byte-for-byte
   against the data the old file held, taken from `git show HEAD:src/data/<file>.asm`, at *every*
   offset the exporter emits. All four packing commits did this and it caught nothing — but it is
   what makes a runtime failure interpretable, because the data path is already known good.
2. **In jsbeeb**, reach the screen and look. This is the expensive half and the one that found
   every real defect on the branch.

**Emulator navigation notes**, learnt the hard way: the title needs one `L`; the game-start 001
screen is ~165 frames after it and is the cheapest portrait test. The console opens by pressing
fire while *standing on* `CHAR_CONSOLE` (`combat.asm`'s `dcu_console`), not by walking onto it.
`type_input` is too fast for the direct keyboard scan — use discrete `key_down`/`run_frames`/
`key_up`. jsbeeb has no key name for `[` or `]`, so `DEBUG_DECK` cannot be driven.

## 9. Outstanding verification

- **A droid type whose four portrait slots straddle a chunk boundary.** Types **12** (slots 15, 37,
  38, 39), **13** (55–58) and **17** (7, 8, 11, 9, 10). The droid database shows them. *(KC checked
  the droid info page 2026-09-07 and it is good; the straddling types specifically are still
  unconfirmed.)*
- **The lift's no-load exit** — take a lift, return to the same deck. The one path where
  `sideview`'s depack trashes the map and `RedrawAll` must restore it. *(Lift screen and console
  ship page confirmed good by KC 2026-09-07; the no-load exit specifically was not called out.)*

## 10. State of the tree

**The code image is exactly full** — `code_end == FONT_ADDR == &3000`, zero bytes free, as of
`b385cd6`. Bank 4 has 8. Bank 7 has 3,021.

Three things all want the same first move — a few bytes back in the code image: step 3, BUGS.md
**#23** (the transfer entry flash, 3 bytes) and **#24** (the pause word). Step 3 reorganises main
RAM anyway, so it is the natural place to find them.
