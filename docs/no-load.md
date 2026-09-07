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
| *step 3* | title artwork to bank 7 | 1,881 |
| *step 3* | `hsGlyphs` deleted, high-score screen to bank 7, PARTITL to `&0900` | 1,181 |
| *step 4* | the title overlay itself into bank 7 — **PARTITL stops being a disc file** | **759** |

**Step 2 is complete: bank 7 went from 7 bytes free to 3,021.** Content saving 3,295.

**Step 3 is complete and it SPENDS 1,840 of that**, as §6 said it would. What it buys is
stated there: `&3000` is now free of the title, which is the precondition for ever dropping
the `PARAFNT` reload, and `PARTITL` fell from 3,307 raw bytes to **397**.

`poLut` is the one that beat its estimate by not being a packing job at all: both 256-byte tables
were one 16-byte table written out longhand, `left = poLut[b >> 4]`, `right = poLut[b AND 15]`.
**Ask "is this generatable?" before reaching for ZX0.** `xferboard` was checked the same way and
is not — its three glyph sets use logicals {0,3}, {0,1,3} and {0,2,3}, so the recolour is partial
and the subset is artwork, not a rule.

---

## 5. What is left

Order below is the posted one, with corrections found since.

**Step 3 — `hsfont` dedup + PARTITL relocation. DONE 2026-09-07.** See §6, which is now the
record of what was built rather than the plan for it.

**Step 4 — the individual loads**, cheapest first, as space allows. **The title overlay is done,
2026-09-07** — see §4a. Five post-boot streams are left and **none of them fits**; §4b is the
measurement.

### 4b. THE WALL — measured 2026-09-07, after step 4's first item

**Steps 4, 5 and 6 are all blocked on the same thing: there is no bank space left.** This section
is the arithmetic, so it does not have to be re-derived.

Free bank space, from the build gauges: **bank 4 = 8, bank 5 = 665, bank 6 = 552, bank 7 = 759**,
total 1,984. They cannot be pooled — only one bank is visible at a time, so a stream has to fit
inside a single one, and bank 4's 8 bytes are unusable for anything.

**The five remaining post-boot streams:**

| stream | raw | packed | when |
|---|---|---|---|
| PARMAN | 6,093 | 3,595 | briefing entry |
| PARASPR | 15,719 | 3,510 | briefing exit |
| PARAFNT | 3,510 | 1,947 | after the title, after the briefing |
| PARBRF | 1,012 | **769** | every title |
| PARALOW | 919 | **730** | after the title |

**Step 4 has exactly one candidate left and it is a bad trade.** `PARALOW` packed is 730 against
bank 7's 759 — which leaves 29, and its depack stub is most of that, so the machine would end with
**about four spare bytes in its last flexible bank** to remove the second-smallest of five loads.
`PARBRF` at 769 misses bank 7 by **ten bytes** and fits nothing else. Everything above 1,947 is out
by a factor of two or more. *Left for KC: spend bank 7 down to nothing on `PARALOW`, or not.*

**Step 5 is short by ~2,300, and the posted figure did not count the half that has to move.** If
bank 5 is never evicted then `PARMAN` cannot land in it, so BOTH halves need permanent homes:

| what | bytes | note |
|---|---|---|
| the five page streams | 2,805 | §5's own figure |
| `keyredef.asm` | **1,014** | the CTRL+R redefine screen |
| `briefman.asm` | 456 | |
| `sndchat.asm` | 15 | |
| **needed** | **4,290** | against **1,976** in banks 5-7 |

And it is worse than the total suggests: **`keyredef.asm` alone, at 1,014, exceeds the largest free
block (759)**, so step 5 does not even start.

**The one big held reserve does not close it.** `docs/ram-pass.md`'s **SCANSTEP tail folding** is
~1,050 B in EACH of banks 5 and 6, which would make 4,076 available — still ~214 short before any
fragmentation, for ~480 cycles a pass (~1% of the blit window) and a change the mechanical
listing-diff explicitly cannot validate. `door.asm` → bank 4 buys main RAM, not bank space, and
wants ~650 B free in bank 4 first.

**Step 6 does not help either.** Its ~500 usable bytes are main-RAM low workspace in six pieces,
and bank content cannot live there.

**So the next move is a decision, not a task.** The options, none of which is obviously right:

1. **Spend bank 7 on `PARALOW`** and accept ~4 bytes free — one load fewer, no room for anything
   after it.
2. **SCANSTEP tail folding**, for ~2,100 B of bank space at ~1% of the blit window, verified
   against the oracle rather than the listing diff. Still leaves step 5 ~214 short.
3. **Change step 5's shape.** `keyredef.asm` is the single biggest obstacle and CTRL+R is the
   rarest screen in the game — making it an on-demand overlay of its own trades a rare load for
   1,014 bytes and unblocks the rest.
4. **Hunt for another packing pass** the way step 2 did. **Bank 4 was tried, 2026-09-07, and it
   yielded 217 bytes — see §4c. It is not a second step 2.**
5. **Stop.** The branch has already halved the front end's load cost and freed the code image.

### 4c. The bank 4 pass, 2026-09-07 — 217 bytes, and why not more

Bank 4 had **8 bytes free**. It now has **225**. That is the whole yield, and the reason it is not
thousands is structural rather than a failure of searching.

**Packing bank 4 is not possible, and this is the finding that matters.** Bank 7's 3,295 bytes came
from streams that are read ONCE, on a modal screen, with the tile map free as an arena to depack
into. Bank 4 is the resting bank during play and everything in it is read while the game runs, so
there is nowhere to depack to — and the disc already ZX0s the whole bank (16,376 → 10,780), so
packing a block inside it buys nothing there either. Measured anyway, for the record:

| block | raw | ZX0 | would save | why it cannot be taken |
|---|---|---|---|---|
| `drSprData` | 1,743 | 565 | 1,178 | read by `SprFetchRow`, the wrap fallback, during play |
| rest of `droidgame` | 1,247 | 907 | 340 | waypoints and type tables, read by the AI |
| `sounddata` | 521 | 374 | 147 | read by the sound driver every tick |
| `colours` | 506 | 211 | 295 | see below |
| `tiledefs` | 512 | 318 | 194 | read by the level draw |
| `levels` | 2,439 | 2,308 | 95 | **already ZX0** — `BuildLevel` is pointer setup in front of `Zx0Unpack` |

`levels` is the one worth calling out: it looks like the biggest data block in the bank and it is
already compressed, so a second pass over it recovers 4%. Measuring first is what stopped that
becoming a day's work.

**What DID pay was redundancy, not compression** — step 2's own lesson. `drSprData` stores 249
rows of seven bytes and only **173 are distinct**, despite the exporter's header claiming "every
distinct row". The rotor's 40 rows are 26 pictures and its 16 end rows are 2, because the bottom
half of the rotor is the top half in reverse row order and the ends alternate; `build_rotor_code`
has always known this (its "28 distinct rotor rows"), but the flattening that builds `drSprData`
did not. **Interning them took 249 rows to 218: 217 bytes.**

Only half the table can be interned, and the split is the blitter's:

- `drOfs[]` is an explicit byte offset per (phase, row), so duplicate rotor and end rows share one
  copy and the table points twice at it. **Safe.**
- `drDigit[type]` is a BASE the blitter adds `(row-6)*7` to, so a type's eight digit rows must stay
  contiguous and in order. Interning them would break the arithmetic, and would not pay: 45
  duplicate digit rows (315 bytes) against 384 for the per-row offset table needed to reach them.

`export_droids.py` now re-derives the expected picture from the C64 listing and asserts it against
what `drOfs` and `drDigit` point at, for all 168 (phase, row) and 192 (type, digit row) pairs, on
every run.

#### Costed and REJECTED — do not re-run these

- **`colourMap` deduplication, and it measures +1 byte.** The table is 16 deck rows of 16 and only
  **7 are distinct**, so sharing them saves 144 and costs a 16-byte index; the read does not even
  change, only its base (`cmapBase[deck]` replacing four `ASL`s, a byte shorter). It was built, and
  the bank gauge moved from 225 to **226**. **`tiledefs.asm` opens with its own `ALIGN &100`**, so
  every byte `colourMap` gives up is swallowed by the next pad — CLAUDE.md's standing rule, "the
  next ALIGN pads by the same amount", holding exactly. Reverted. The first attempt also put
  `cmapBase` in FRONT of `colours.asm`'s `ALIGN` and **overflowed the bank by 30 bytes**, which is
  the other half of the same rule: bank 4's pad is spent, so 16 bytes in front of it cost 256.
- **2-bit packing of `colourMap`** (it holds only 0-3): saves 192, costs ~28 bytes of bank-4 code
  for the variable shift, and lands in the same `tiledefs` pad. Worse than the dedup on every axis.
- **`tiledefs` row indexing**: 128 four-byte rows, 86 distinct — 472 bytes against 512, and one
  duplicate tile is 16 more. ~40 net, in a table read by the level draw. Not worth the indirection.

**The pass does not unblock anything.** 225 bytes is short of `keyredef`'s 1,014 (§4b) and short of
the ~650 `door.asm` → bank 4 wants (`docs/ram-pass.md`). It is banked because bank 4 had eight
bytes, not because it moves the branch on.

### 4a. Step 4's first item: the title overlay, 2026-09-07

Step 3 left `PARTITL` at **397 bytes**, which made it the cheapest post-boot stream by a factor of
two — so it is the first one to go resident. The image lives in bank 7 at `titlImg`; `TiResident`
copies it down to `TITLE_ADDR`; the disc file is gone.

**The overlay is still ASSEMBLED at `&0900`** because it runs there and is not
position-independent. beebasm's **`COPYBLOCK`** moves the assembled bytes into the bank, which is
what makes "assembled at one address, stored at another" possible in a single pass. Two
consequences worth knowing before touching it:

- `SAVE "PARXFER"` had to move **below** the PARTITL block, so that it writes the bank *after* the
  `COPYBLOCK` has filled `titlImg`. It is the last thing in that block now.
- `TITL_BYTES` is **hand-maintained**, with `ASSERT titl_end - titl_start == TITL_BYTES` to keep it
  honest — the bank block reserves the space long before the overlay is assembled, and beebasm
  resolves constants in file order. `CON_STR_BYTES` and `FONTCODE_BYTES` are the same arrangement.

`TiResident` copies **exactly `TITL_BYTES`**, one full page then a tail, rather than two whole
pages: a page-granular copy would read past the image, and at the tail of a bank that is the MOS
ROM. It ends in main RAM's `PgData`, whose `RTS` is `TitleSeq`'s — a `PAGEBANK` executed in the
bank would swap the `RTS` out from under itself.

| | before | after |
|---|---|---|
| **main-RAM code image free** | **0** | **14 B** (`code_end` `&2FF2`) |
| bank 7 free | 1,181 | **759** (397 image + 25 `TiResident`) |
| post-boot loads | 6 | **5** |
| disc files | 12 | 11 |
| disc image, packed | 46,848 | 46,592 |

**The 14 bytes of code image are the point, and they were the surprise.** `LDX`/`LDY`/`JSR OSCLI`
(7 bytes) became `JSR PgXfer` / `JSR TiResident` (6), and `loadtitl`'s `EQUS "LOAD PARTITL"` + `CR`
(13) went entirely. §10 said step 3 would find the bytes BUGS.md #23 needs and was wrong; step 4
found them instead, and #23 wants three of the fourteen.

**Verified.** Offline: the 397 bytes `COPYBLOCK` placed in the bank were extracted from the raw SSD
and compared against beebasm's own listing of `&0900–&0A8D` — identical across the 383 bytes the
listing renders as code. Against the *previous* build's `PARTITL` file they differ in exactly eight
bytes, and all eight are 16-bit operands pointing into the code image, each moved down by 13 or 14
— the shift `loadtitl`'s deletion caused, not corruption. In jsbeeb: cold boot title (first copy),
game, ESCAPE, game over, high-score entry, title again (**second copy, from the game-over path** —
which is why `TitleSeq` pages `SWRAM_XFER` explicitly rather than relying on the bank it arrives
on; boot arrives with it up, the game-over seam does not), briefing timeout, briefing, fire exit,
game. All correct.

**`tools/make_disc.py`'s `LAYOUT` lost `PARTITL`**, and that list doubles as the required-file
check — which is what caught the first build of this change, exactly as it should have.

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

## 6. Step 3 — as built, 2026-09-07

**What it was:** delete `hsGlyphs` and relocate PARTITL off `&3000`, so the text font survives
the title. Done, and verified in jsbeeb over the whole front-end loop. **The placement changed
during the work and the reason is §6a below — read that before trusting the addresses here.**

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

- **The artwork goes to bank 7 raw, 1,140**, read in place by `TiPaint` with the bank paged. It
  cannot be packed: there is no arena at title time (§3). `TiShow` gains `JSR PgXfer` / `JSR PgData`
  around `TiPaint` and nothing else — the bank on arrival is always `SWRAM_DATA`, because `HsEntry`
  runs immediately before it and *both* its arms end on the data bank.
- Neither `title.asm` nor `highscore.asm` has an `ALIGN` or a hardcoded `&3xxx`; every
  self-modification is `HI(label)`/`LO(label)` and the only absolute tables are `BUF_BASE`-relative.
  **Both relocate by changing the ORG**, which is what made the three-way split cheap.

**The `FontCell` trap is gone with the move.** PARTITL used to end `&3CEB` against `FontCell` at
`&3CED`, and that two-byte clearance was load bearing. The overlay is nowhere near `&3xxx` now, so
`ASSERT titl_end <= FONTCODE_ADDR` has been deleted along with it.

### 6a. THE CHARSET TAIL IS 912 BYTES, NOT 1,180 — and why the split is three ways

The plan above put the code at **`&07F4–&0C90`**. That address is wrong and the evidence was
already in the tree: **`&0800–&08FF` is the MOS's sound workspace, and the MOS owns IRQ1V through
every load the title makes.** `main.asm`'s PARBRF block records the measurement — a PARBRF that
reached `&08B8` *verified byte-perfect immediately after its load* and was chewed by the time the
briefing painted, running the corrupted `&08xx` into the paged bank and BRKing at `&800E`. `&0400–
&07FF` really is free; the page above is not.

So PARBRF keeps `&0400–&0800` and the title gets **`&0900–&0C90`, 912 bytes**, with the MOS's page
stepped over between them. 912 does not hold 1,087, and the answer is to split three ways rather
than two — **agreed with KC before it was built, 2026-09-07**:

| piece | bytes | where | why it can go there |
|---|---|---|---|
| `title.asm` driver + `HsEntry` | **397** | PARTITL, `&0900` | `TitleSeq` is main RAM and calls `TiBootPal`, `HsEntry` and `TiShow` directly; main RAM may only call *into* a bank with that bank paged, so the three doors must stay outside one |
| artwork (`titleGlyphs` + `titleRLE`) | 1,140 | bank 7, raw | `TiPaint` is the only reader and reads it once |
| `hsRemap` + the three strings | 139 | bank 7 | data, read under `HsEntry`'s paging |
| everything from `.HsRun` down | ~570 | bank 7 | **`HsEntry` already paged `SWRAM_XFER` around the whole screen**, for `hsArmed` and `hstable.asm`. So the screen runs with the bank it always ran with, and calls `FontCell`, `keydown`, `score` and `textfont` out in main RAM — which bank code may do freely. **No trampoline anywhere, and not one byte of code image.** |

The one thing that did NOT move is `HsEntry` itself: its `PAGEBANK` pair has to execute from
somewhere that does not vanish when it fires. It lives at the end of `src/title.asm` now.

**The invariant this creates, and no `ASSERT` can check it:** `PARAFNT` must be resident whenever
`HsRun` runs, because the glyphs are `textfont`'s now. It is — `HsRun` only runs when `hsArmed` is
set, which only a finished game sets, and `GoTitle` reaches `TitleSeq` through `SetupPlain`, which
exists precisely because `SetupMode`'s `VDU 22` would clear `&3000–&7FFF`. A cold boot never gets
there: `hsArmed` is zero, the assembled value.

**CORRECTION to the posted plan: step 3 does not remove the PARAFNT reload on its own.**
`ts_loads` is shared three ways — boot, game-over, briefing exit — and the briefing destroys
`&3000` independently: `BrTimeout` stages PARMAN at `DEPK_STREAM = &3200`, inside the font block.
`&3000` has two destroyers; step 3 removes one and **step 5 removes the other**. Neither alone
removes the load. So step 3 is a spend with a deferred payoff, taken because it
is a prerequisite and bank 7 now has room.

**What it actually cost and bought, measured 2026-09-07:**

| | before | after |
|---|---|---|
| bank 7 free | 3,021 | **1,181** |
| PARTITL, raw | 3,307 | **397** |
| main-RAM code image free | 0 | **0** — step 3 touches no code image at all |
| disc image, packed | 48,896 | 46,848 |

**How it was verified.** Offline: `tools/export_hsremap.py` re-derives both tables from the C64
listing and compares all 1,152 bytes against the *committed* `src/data/textfont.asm` on every run,
so a hand-edited or re-exported font is caught at build time. Mechanically: the beebasm listings
of `HsRun`→`hsTmp2` were reduced to a (mnemonic, addressing class, length) stream and diffed
against `HEAD`'s — 279 entries, and **the only difference is the two instructions `TAX` /
`LDA hsRemap,X` that `HsGlyph` gained**, which proves the move dropped and reordered nothing;
`TiShow`'s stream differs by exactly the two `JSR`s, and `HsEntry`'s is identical. In jsbeeb: cold
boot → title → game → ESCAPE → game over → high-score entry (walked A–J and back to capital I, the
one irregular remap entry, and committed three initials) → title → briefing timeout → briefing →
fire exit → game, all correct; and `&0900–&0A8D` read back **byte-for-byte identical to the
`PARTITL` file on disc** after a full title dwell, except for `tiRun`/`tiLo`/`tiHi`/`tiPage`, the
overlay's own counters. That last one is the measurement that says `&0900` is safe where `&0800`
is not. The `-Release` build (with the intro) was booted through to the title as well.

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

**The code image has 14 bytes** — `code_end` `&2FF2`, after step 4 deleted `loadtitl`. It was
exactly full (`code_end == FONT_ADDR == &3000`) from `b385cd6` until then. Bank 4 has 8. Bank 7 has
**759**. `PARBRF` ends `&07F4`; the title overlay runs `&0900–&0A8D`, so `&0A8D–&0C90` (515 bytes)
is the free tail of the charset region at title time.

**BUGS.md #23 (3 bytes) and #24 are now affordable and are still unfixed.** Step 3 did not free any
code image — everything it moved was overlay or bank content — and an earlier draft of this
section had assumed it would, which was wrong. **Step 4 is what paid**: removing a load removes its
OSCLI and its filename, and that is a pattern worth remembering for the four remaining streams.
`PARBRF`, `PARAFNT`, `PARALOW` and `PARMAN` each carry an `EQUS` of their own name plus a call
site; going resident reclaims those too.

**Five post-boot streams are left and the branch is out of bank space for all of them.** §4b has
the arithmetic and the five options; the short version is that `PARALOW` is the only stream that
fits anywhere, it would leave bank 7 with about four bytes, and step 5 is short by ~2,300 because
`keyredef.asm` has to move too and nothing can hold it.
