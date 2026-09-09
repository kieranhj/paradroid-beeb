# The no-load plan — everything resident, loading once at boot

Working notes for the `no-load` branch. The goal is hexwab's, from
[issue #2](https://github.com/kieranhj/paradroid-beeb/issues/2): get the game small enough that
loading happens once at boot and never again. The reply on that issue carries the full measured
analysis; this file is the working copy, kept current as the branch lands.

**Read the arena rule below before touching `&4600`.** It is the only invariant on the branch and
it has already been broken twice.

**STATUS, 2026-09-09: `docs/HANDOVER-step5.md` IS THE BRIEF FOR THE NEXT SESSION.** §14 is the
design and the measurements behind it; the handover turns them into staged work with the
verification recipes and the traps. §12 is the earlier handover and is now history.

**STATUS, 2026-09-09: §12 was the handover.** Four commits on the night of
2026-09-08 took free bank space from 2,201 to **6,081**, so **step 5 fits for the first time** and
space is no longer the blocker. What is left is architectural and §12a lists the three choices it
needs.

**STATUS, 2026-09-08: RESUMED, and §10's test list is cleared** (all but real hardware, the
transfer's lose path and a systematic rotor walk). **§11 is the current plan** — the goal is reachable; §1a's
"~1,200 short" missed two supplies worth ~1,800 (`dfsSave`'s 912 bytes of bank 6, and main-RAM
reclaim being convertible to bank space after all). Read §11 before §4b and §5, both of which it
supersedes on ordering and on "the next move is a decision, not a task".

**STATUS, 2026-09-07: PAUSED, AND NOT READY FOR `main`.** Steps 2, 3 and the first item of step 4
have landed — one post-boot load fewer and 14 bytes of code image back. The rest is blocked, and
**§1a is the important read**: the founding table in §1 was wrong in both directions, and adding
supply against demand for the first time puts the goal ~1,200 bytes out of reach. §10 has the
state of play and **the list of what must be tested before this merges** — several screens that
KC signed off earlier in the branch have not been looked at since bank 7 was rearranged under
them.

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

> **THAT SENTENCE IS WRONG, AND SO IS THE TOTAL ABOVE. See §1a.** The table is kept as written
> because every step from 2 to 4 was planned against it and the commits quote it.

---

## 1a. The ledger was wrong — corrected 2026-09-07

The table above was never re-derived after the branch learnt what the streams actually are. It is
wrong in **both directions**, which is why it survived four steps: the two errors partly cancel.

**A restoration costs nothing resident.** `PARASPR` is the blitter, which is *already* resident in
bank 5; its 3,512 is the price of putting it back after the briefing evicts it. `PARAFNT` is the
font, *already* resident at `&3000`; its 1,947 is the price of putting it back after the title or
the briefing destroys it. Neither needs a home — each needs its **destroyer** removed, which is
exactly what steps 3 and 5 do. §1 counted them as "the expensive part" when they are the free part.
**Overstated by 5,459.**

**Content that is CODE costs its UNPACKED size, and content read in place cannot be packed at
all.** A stream only costs its packed size if it is depacked somewhere on demand. Two of the six
are not like that:

- `PARMAN`'s 1,485 of `briefman` + `keyredef` + `sndchat` is code that runs during the briefing,
  and its text as five page streams is 2,805 rather than 2,438. True residency **4,290**, not
  3,595 — understated by 695.
- `PARTITL` was 1,597 packed. Its artwork (1,140) is read in place by `TiPaint` and **cannot be
  packed — there is no arena at title time (§3)** — and the high-score screen is code. Measured by
  building it: step 3 spent **1,840** of bank 7 and step 4 a further **422**. True residency
  **2,262** — understated by 665.

### The corrected ledger

| stream | §1 said | actually needs resident | why |
|---|---|---|---|
| PARASPR | 3,512 | **0** | restoration; step 5 removes the eviction |
| PARAFNT | 1,947 | **0** | restoration; steps 3+5 remove the destroyers |
| PARTITL | 1,597 | **2,262** *(SPENT)* | artwork unpackable, high-score screen is code |
| PARMAN | 3,595 | **4,290** | 2,805 page streams + 1,485 of code, unpacked |
| PARBRF | 770 | 769 | packed, depacked to `&0400` when wanted |
| PARALOW | 730 | 730 | packed, depacked to the staging area |
| **total** | **12,151** | **8,051** | of which **5,789** is still to find |

### And the supply was totalled as a pool, which it is not

"Free SWRAM at the start of the branch was 1,237 B" adds four banks together. **Nothing can span a
bank** — §1 states that constraint one sentence later and then the arithmetic ignores it. Today
there are 2,201 "free" bytes (225 / 665 / 552 / 759) and the largest single block is **759**, while
the largest indivisible item is `keyredef` at **1,014 unpacked, 776 packed**. It fits nowhere, and
no amount of total is going to change that.

### Supply against demand, added up for the first time

| supply, bank bytes | |
|---|---|
| free at branch start | 1,237 |
| step 2, the bank 7 packing pass | 3,295 |
| the bank 4 pass (§4c) | 217 |
| SCANSTEP tail folding, the one big held reserve | 2,100 |
| **total the plan can ever reach** | **6,849** |

Against **8,051** of demand. **The branch falls about 1,200 bytes short of its goal even after
spending the reserve it hoped not to need** — and steps 6 and 7 do not help, because step 6's ~500
is main-RAM low workspace (bank content cannot live there) and step 7's ~140 is code image.

**Nobody ever added these two columns together.** §1 showed 12,151 against 1,237 — a ten-to-one
gap that reads as "obviously needs work" rather than "compute whether this is possible" — and then
step 2 delivered 3,295, which felt like progress against an unquantified target.

### What this changes

1. **The goal is ~1,200 bytes out of reach, not hopeless and not close.** That is a much more
   useful number than "blocked", and it is small enough that one concession closes it: dropping
   `PARBRF` from the plan (769) and keeping one load at the title leaves ~430 to find.
2. **SCANSTEP tail folding is no longer optional.** It is 2,100 of the 6,849, so nothing finishes
   without it — and it is also what gives banks 5 and 6 a block big enough for `keyredef`.
   `docs/ram-pass.md` files it as a reserve for "next time RAM runs out"; that time is now.
3. **`keyredef` is the shape of the problem, not just its biggest item.** At 776 packed it exceeds
   every free block. One idea the plan never considered: the redefine screen is a modal screen
   *inside* a modal screen, so it could be depacked into the briefing's own 3,196-byte arena and
   run from there — which drops it from 1,014 unpacked to 776 packed and removes the need for it to
   sit anywhere permanently in unpacked form.
4. **The step order spent what step 5 needed.** Step 2 left bank 7 with 3,021; step 5's page
   streams are 2,805 and would have fitted exactly. Steps 3 and 4 spent 2,262 of it first. This was
   not decisive — `keyredef` blocked step 5 either way — but the sequence was never checked against
   the demand, because the demand was never computed.

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
is the arithmetic, so it does not have to be re-derived. **§1a is why it was never going to
close** — read that first; this section is the local detail, that one is the ledger.

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
`key_up`. ~~jsbeeb has no key name for `[` or `]`, so `DEBUG_DECK` cannot be driven.~~
**Out of date since jsbeeb-mcp 3.4.0**: `key_down` takes `inkey:` (or `internal:`, or `col`+`row`),
so any key the game's own `KEY_` constants name can be pressed directly — `[` is `inkey: -57` and
`]` is `-89`, and `DEBUG_DECK` is drivable.

## 9. Outstanding verification

**BOTH CLOSED 2026-09-08 in jsbeeb** — see §10's checklist, which is where the detail is. They
were outstanding from step 2, and the KC sign-offs quoted in them pre-dated steps 3 and 4 and the
bank 4 pass; the runs on 2026-09-08 are against the current build.

- **A droid type whose four portrait slots straddle a chunk boundary.** Types **12** (slots 15, 37,
  38, 39), **13** (55–58) and **17** (7, 8, 11, 9, 10). **DONE 2026-09-08**: all three drawn from
  the console's database page (493, 516 and 615), clean, by poking `dbType` in bank 7.
- **The lift's no-load exit** — take a lift, return to the same deck. The one path where
  `sideview`'s depack trashes the map and `RedrawAll` must restore it. **DONE 2026-09-08**: the
  view drew, fire committed, and the deck came back fully redrawn with the player intact. Reached
  by poking `liftMode` = 1, so `LiftFind` — the lift *selection* — was not exercised.

## 10. WHERE WE ARE — paused 2026-09-07, NOT READY TO MERGE

**The branch works and is one load lighter. It has not been tested widely enough to go to `main`.**

### What landed

| | |
|---|---|
| Post-boot loads | **6 → 5** — `PARTITL` is gone; the title overlay is carried in bank 7 and copied down |
| Main-RAM code image | **0 → 14 B** free, the first the branch has given back |
| `&3000` at the title | **survives** — which is the precondition for ever dropping the `PARAFNT` reload |
| Bank 7 | 25 → 3,021 (step 2) → **759** after steps 3 and 4 |
| Bank 4 | 8 → **225** |
| Disc image, packed | 48,896 → **46,336**; 12 files → 11 |
| `hsGlyphs` | deleted — 1,152 bytes became a 72-byte remap into `textfont` |

Steps 2, 3 and the first item of step 4 are complete. **Steps 4 (the rest), 5 and 6 are blocked**
— §4b for the local arithmetic, **§1a for why it was never going to close**.

### What has been verified, and in what

**2026-09-08: the list below was cleared in jsbeeb** — see the checklist at the end of this
section. Everything except real hardware, the transfer's lose path and a systematic rotor-phase
walk has now been looked at on the current build.

In jsbeeb, repeatedly, after each of steps 3 and 4: cold boot → title → game → ESCAPE → game over
→ high-score entry (walking the alphabet, capital I, three initials committed) → title → briefing
timeout → briefing → fire exit → game. Plus, for the bank 4 pass, 900 frames scrolling right and
700 down, which is what drives `SprFetchRow` across the buffer wrap.

Offline, and these are the strong ones: the `hsRemap` identity is re-derived from the C64 listing
and compared against the committed `textfont.asm` on every build; `drSprData`'s intern is likewise
re-checked against the listing every run, and was compared through both index tables (360 reachable
rows, zero mismatches); the moved high-score code was diffed as a (mnemonic, addressing class,
length) stream against `HEAD` and differs by exactly the two instructions `HsGlyph` gained; and
`&0900` was read back from a running machine and matched the overlay byte for byte after a full
title dwell.

### WHAT STILL NEEDS TESTING BEFORE THIS MERGES

**The concern is bank 7 and the sprites, and it is specific.** KC checked the lift screen, the
console's ship page, the deck plan and the droid info page on 2026-09-07 — *before* steps 3 and 4
and the bank 4 pass. Those three changes moved bank 7's whole layout (the transfer game, the lift,
the console pages and the portrait pool all live there), rewrote `drSprData` (every droid sprite),
and shifted the code image by 14 bytes. **None of those screens has been looked at since.**

- [x] **The transfer minigame** — entry, both info screens, the board, play, **win**, exit.
      Bank 7's biggest tenant. *(2026-09-08. The LOSE path is still untested.)*
- [x] **The lift**, including the no-load exit: the view, then fire, then back to the same deck
      with the tile map restored. The §9 item, now also a bank-7 regression check.
- [x] **The console** — main screen, droid database, deck plan, ship page, **and the exit back to
      the deck**. The deck plan was opened twice in a row without passing through `RedrawAll`,
      which is the case §2's second half exists for.
- [x] **A droid type whose portrait slots straddle a chunk boundary** — types 12 (493), 13 (516)
      and 17 (615) all drew clean. §9's first outstanding item, closed.
- [~] **Droid sprites at every rotor phase and several types.** Seen in play across the 001 and
      476 sprites and several AI droids, animating, with no corruption — but not walked
      systematically through all eight phases and 24 types. The offline proof remains the strong
      one.
- [x] **CTRL+R, the redefine screen** — reached from the briefing, the table drew, and rebinding
      Left to `A` took and advanced the prompt to Right.
- [~] **Sound.** Not listened to; *captured*. 77 SN76489 writes over 25 fields during a shot:
      one group a field, a coherent two-channel descending sweep, `atten=15` at the end of the
      effect and a new effect opening at `atten=10`. That says the driver, its bank-4 data and
      the IRQ tick are all correct; it does not say the effects SOUND right, which still wants
      KC's ears.
- [x] **The `-Release` build booted**, not merely built: `Release Candidate #5` in the boot stamp
      (and no `DEBUG:` line), `PINTRO` ran, a keypress chained it, and the title and play came up.
- [ ] **Real hardware.** Everything here is jsbeeb.

**How this sweep was driven, because it is reusable.** Walking to a console or a droid by
holding keys is slow and unreliable; every screen above was reached by poking the game's own
trigger and then playing it normally:

| screen | lever |
|---|---|
| transfer | `xferDroid` (`&148A`) = a live droid index; the next pass takes the arm |
| console | the tile under the player read from a breakpoint at the `CMP #CHAR_CONSOLE` site (`&1F92`, A = 65), then that operand poked to 65 so fire opens it where you stand |
| lift | `liftMode` (`&2720`) = 1 — note this SKIPS `LiftFind`, so the lift *selection* is not exercised, only the view, the arena and the exit |
| database type | `dbType` (`&9D9E`, **bank 7** — `write_memory` with `bank: 7`) set to N-1, then DOWN |
| transfer win | `DEBUG_XFERWIN`'s CTRL+W, **after** a side has been chosen — it does nothing on the "Colour?" prompt |

`key_down` takes `inkey:` numbers, so the game's own `KEY_` constants drive it directly
(Z -98, X -67, K -71, M -102, L -87) and **`DEBUG_DECK`'s CTRL+`[` / CTRL+`]` are drivable after
all** — §8's note that jsbeeb has no key name for them is out of date.

**The honest caveat this branch inherited still applies**: three of its first four defects were
found at runtime, after static analysis said the change was sound, and all of them at the seams
between screens rather than inside a change. The offline compares here are stronger than that
branch's were — they check identity against the C64 listing rather than against the previous
build — but they still buy interpretability, not confidence.

---

## 10a. State of the tree

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

---

## 11. THE PLAN AS IT STANDS NOW — re-audited 2026-09-08

**The goal is reachable. §1a's "~1,200 short" was pessimistic by about 1,800 bytes**, because the
supply column never counted two things — one of them sitting in bank 6 with a comment on it. This
section supersedes §4b's "the next move is a decision, not a task" and §5's ordering; §1a's
*demand* arithmetic survives unchanged and is still the ledger to argue with.

### 11a. The byte map, measured 2026-09-08

Before anything else, this is where the machine's RAM actually is. Taken by assembling a copy of
`main.asm` with a `PRINT "MARK <file>", ~P%` after every `INCLUDE`, so the assembler reports where
each included file ended; differences between consecutive marks are the file's size. Thirty
seconds of work and the first byte map the port has had — **do this again rather than reasoning
about sizes from source.**

| bank | free | what is in it |
|---|---|---|
| 4 (data) | **225** | `droid` 5,262 · `droidgame` 2,773 · `levels` 2,359 · `screen` 928 · `sound` 925 · `chardata` 878 · `scroll` 698 · `level` 565 · `sounddata` 521 · `tiledefs` 512 · `colours` 506 |
| 5 (spr) | **665** | **`droids.asm` 11,727** · `effects` 2,977 · `sprscan` 538 · `sprfx` 419 · `ruptalign` 58 |
| 6 (spr2) | **552** | **`droids2.asm` 12,050** · `console` 1,391 · **`dfsSave` 912** · `panel` 918 · `sprsplit` 372 · `conicons` 189 |
| 7 (xfer) | **759** | `xfer` 4,060 · `portraits` 2,579 · `condb` 1,559 · `title` artwork 1,140 · `plandata` 1,032 · `liftview` 922 · `droidinfo` 711 · `portrait` 676 · `highscore` 561 · `infoscr` 505 |
| code image | **14** | `&1100–&2FF2` |

**The compiled shifts are 23,777 bytes — 24% of the machine's RAM — and they hold about 2,400
bytes of entropy** (§5 measured the four shifts packing to 12.6%). That is where the RAM went, and
§11d says why touching it is still not the answer.

### 11b. Two supplies the ledger never counted

**1. `dfsSave` is 912 bytes of bank 6 and it is pure load-support.** `main.asm:4094`, a `SKIP` at
the tail of the bank holding the DFS workspace snapshot (`&0D60–&0DEF` and `&0E00–&10FF`) that
`SaveDfsWs` takes before `PageLowIn` and `RestoreDfsWs` puts back for the game-over loads. **No
post-boot filing call means no snapshot**: the buffer goes, and its two helpers (74 bytes of code
image) with it. §6 measured the *main-RAM* DFS reclaim carefully and never looked at the bank.

It is a **terminal dividend** — it only pays when the LAST load goes, not the first — and that
changes the shape of the endgame: **the plan may be ~900 bytes short right up to the final step
and still land**, provided the final step is the one that removes every remaining filing call.

**2. "Bank content cannot live in main RAM" (§4b) is wrong, and it writes off ~869 bytes.** Main
RAM is visible from every bank; **bank code may call and read main RAM freely** — the one-way rule
in `CLAUDE.md` is the other direction, main RAM calling *into* a bank. So freeing main RAM
converts to bank space at **1:1**, by relocating a bank routine out of a bank and into the freed
image. Candidates of the right size are already in the byte map above: `panel.asm` 918,
`sprsplit` 372, `condeck` 361, `xfericon` 307 — and a move like that usually *saves* a few bytes
by shedding a `PAGEBANK` pair.

The reason this looked worthless is real but temporary: main RAM has **14 bytes** today, so there
is nothing to relocate *into*. The conversion only exists after step 6 — which is precisely why
step 6 has to move to the front of the queue rather than staying at the back of it.

### 11c. The revised arithmetic

| supply | bytes |
|---|---|
| free now, four banks (225 / 665 / 552 / 759) | 2,201 |
| ~~SCANSTEP tail folding, ~1,050 in each of banks 5 and 6~~ **SPENT 2026-09-08, and it was 756 each, not 1,050** (§11j) | ~~2,100~~ **1,512** |
| `dfsSave`, **terminal** | 912 |
| step 6's main-RAM reclaim, via relocation (§11b) | ~869 |
| **total** | **~6,080** |

against **~5,790** of demand — §1a's 8,051, less the 2,262 already spent on the PARTITL
relocation.

**It closes by roughly 300 bytes, not misses by 1,200.** **Both corrections since have gone the
wrong way** — §11h took 628 off step 6 and §11j 588 off the folding — so on today's measurements
the sum is about **540 SHORT** rather than 300 over, and §1a's concession (keep one load at the
title, 769) is what closes it. That is still a different problem from "~1,200 short before the
reserve is even spent". Every figure except the first row was an estimate; the two that have since
been measured both came in low, which is the pattern to expect from the rest.

That margin is thin enough to be wrong in
either direction, and every figure in it except the first row is an estimate. What has changed is
the *sign*, and with it the answer to "is this possible": yes, on paper, without the PARBRF
concession — and with the concession (§1a's option, one load kept at the title) there is about a
thousand bytes of slack instead of three hundred.

### 11d. What NOT to do, with the measurement

**Do not build a runtime generator for the compiled shifts.** It is tempting — 23,777 bytes of
almost pure redundancy, and the emit pattern is regular enough to make it genuinely feasible: 373
identical fifteen-byte groups per bank (`LDY #imm` / `LDA (bufp),Y` / `STA (svp),Y` / `AND #imm` /
`ORA colPix+n` / `STA (bufp),Y`), plus `SCANSTEP` tails and `RTS`. Counted 2026-09-08.

It does not pay, and the reason is worth stating because the temptation will recur. A generator
would make banks 5 and 6 *regenerable*, which removes the cost of restoring bank 5 after the
briefing evicts it. But **the demand is dominated by STORING the briefing's content**, which is
irreducible however bank 5 is restored: the content has to exist somewhere resident whether it is
depacked into an evicted bank 5 or lives unpacked in banks 6 and 7. Netted out, the generator
saves ~200-300 bytes against step 5's shape, for a rewrite of the one area `docs/ram-pass.md`
tells us not to re-litigate. **Keep it as a reserve; it is the largest single lever in the machine
and it is the wrong lever for this problem.**

(§5's own "ruled out" entry rejected the generator on *disc size* — "ZX0 already exploits the
redundancy a generator would". That argument does not apply to residency, so it was rejected for
the wrong reason and needed re-answering. This is the re-answer.)

### 11e. Two changes to step 5's shape

**`keyredef` depacks into the tile map and runs there.** At 1,014 unpacked it exceeds every free
block in the machine and always will; that single fact is what §4b means by "step 5 does not even
start". Packed it is 776, and **the map is 1,024** — so it is stored packed wherever there is
room, depacked into the arena on CTRL+R, and run from there. This is the branch's own arena rule
(§2) applied to *code* for the first time, and the screen qualifies on both halves of it: nothing
reads the map while the redefine screen is up, and `RedrawAll` rebuilds it on the way out.

**Every briefing depack goes through the map, not through `DEPK_STREAM`.** Store each piece as its
own stream of at most 1,024 packed — five text pages at ~561 each, `keyredef` 776, `briefman`
~350, `sndchat` 15 — and transit bank → map → destination. `&3200` staging is what destroys
`&3000` at briefing entry, and it is `PARAFNT`'s **second** destroyer (§6a's correction: step 3
removed the first). Doing this means `PARAFNT`'s reload dies inside step 5 rather than needing a
step of its own.

### 11f. The order, and what funds what

1. **Clear §10's test list.** Seven screens have not been looked at since bank 7 was rearranged
   under them and every droid sprite row was re-interned. Building further on that is compounding
   risk. Cheaper now than it was: the `beeb-*` skills are installed, and jsbeeb-mcp's `key_down`
   takes internal key numbers, so **`DEBUG_DECK`'s CTRL+`[` is drivable at last** — §8's note that
   it is not, is out of date.
2. ~~**Step 6, the DFS reclaim — moved to the FRONT.**~~ **WRONG, and §11h is the measurement.**
   Step 6 yields **241** bytes today, not 869: most of its rows are load-support that cannot go
   until the last load does. It goes back to the endgame, with `dfsSave`'s 912. **SCANSTEP tail
   folding takes its place at the front** — ~2,100 bytes, available today, nothing needed first,
   and it is what funds step 5. **DONE 2026-09-08, and it gave 1,512 rather than 2,100 — §11j.**
3. **Step 5, with §11e's two changes.** The big one: it removes both of `&3000`'s destroyers and
   the bank-5 eviction, which is 5,459 of the original ledger.
4. **SCANSTEP tail folding.** No longer optional (§1a). ~480 cycles a pass, ~1% of the blit
   window. `beeb-buffer-oracle` is the check — the mechanical listing diff explicitly cannot
   validate it — and `beeb-frame-drops` confirms 50/100 still holds afterwards.
5. **`PARBRF` and `PARALOW`**, funded in part by `dfsSave`'s 912 falling out as the last load goes.
6. **zx02, last, as posted.** Its ~130 bytes of code image now convert to bank space under step 6,
   and its decode speed matters more in a design that depacks on every screen transition.

**Fallback if the margin evaporates:** §1a's concession — keep one load at the title (`PARBRF`,
769) and take everything else resident. One load, at a screen the player is already waiting on.

### 11g. Where the estimates could be wrong

- **The ~869 of step 6 is in six pieces, the largest 374.** Relocation needs a bank routine that
  fits a piece; the byte map says several do, but each move is its own small job and the last
  hundred bytes may not be spendable.
- **SCANSTEP folding's ~1,050 per bank is `ram-pass.md`'s estimate**, not a measurement of today's
  tree, and the deferred carry has changed the code it folds.
- **`briefman` and the text pages are quoted packed at ratios not yet measured** on the actual
  streams.
- **Fragmentation is not in the totals.** Nothing can span a bank (§1a), and the arithmetic above
  is a sum.

### 11h. Step 6 measured, 2026-09-08 — it yields 241 bytes today, not 869

**§11f put step 6 at the front because it funds everything after it. That was too optimistic and
the seed run says so.** Most of §5's 869 bytes only come back when the LAST load goes, and the
three main-RAM spans were quoted as whole spans without checking what is in them.

Measured by `beeb-bss-bugs`'s recipe on the DEV build: hard reset to BASIC, seed `&0100-&017F`,
`&0300-&03DF` and `&0D01-&0D8F` with `&A5`, **soft** reset with SHIFT, then boot → title → the
briefing on its timeout (which loads `PARMAN`) → fire out of the briefing (which reloads
`PARASPR`, `PARAFNT` and `PARALOW`) → play. So every post-boot load is exercised before the
readback.

| span | §5 claimed | measured free | what is in the rest |
|---|---|---|---|
| `&0100-&017F` stack page | 128 | **128** | nothing — every byte still `&A5` |
| `&0300-&03DF` | 224 | **96** | `&0300-&037E` is the MOS's VDU workspace and is comprehensively written. `&037F-&03DF` survives, **except one byte at `&03D1`** (read back as 25) |
| `&0D01-&0D8F` | 143 | **17** | `&0D01-&0D4E` is DFS's NMI handler, written when DFS claims NMI. `&0D60` up is **already the game's own `lowcode2`** — §5 counted space the port has spent |
| | **495** | **241** | |

The other six rows of §5's table (`SaveDfsWs`/`RestoreDfsWs` 74, the OSCLI strings 52, their call
sites ~40, `UnpackBankIn`+`BootBanks`+strings 113, `PageCopyAt`/`PageLowIn` 65, `.start` 30 = 374)
are all code image, and **all of them are load-support that cannot go while any post-boot load
remains**. `UnpackBankIn` in particular is not boot-only: the briefing exit calls it.

**So step 6 is not the funding step and cannot come first.** What is genuinely boot-only and
evictable today is `.start` (30 B) and `BootBanks` (124 B) — hexwab's step 1, ~154 bytes — plus
these 241 of scattered workspace, and the largest contiguous piece of any of it is the stack
page's 128, which is not loadable from disc and would have to be copied down.

**The stack-page measurement did get stronger, though.** `docs/ram-pass.md` lists the transfer,
the lift and the briefing as paths its 2026-08-31 run never exercised. This run went through the
briefing and both of its loads, and all 128 bytes came back `&A5`.

**Revised order:** SCANSTEP tail folding (§11f step 4) moves to the FRONT. It is ~2,100 bytes,
it is available today, it needs nothing else first, and it is what actually funds step 5 — which
was always its role in §1a. Step 6 moves back to where §5 had it, as part of the endgame with
`dfsSave`'s 912.

### 11i. The briefing's pieces, packed — measured, not estimated

From the raw SSD (`build/PARADROID-raw.ssd`, whose `PARMAN` is uncompressed) through
`bin/zx0.exe`, 2026-09-08:

| piece | raw | ZX0 | |
|---|---|---|---|
| briefing text + `sndchat` (`&8000-&920F`) | 4,623 | **2,474** | 53.5% — as ONE stream; §5's five page streams cost **2,805**, so splitting costs 331 and buys a 1,082-byte buffer instead of a 4,623-byte one |
| `briefman` (`&920F-&93D7`) | 456 | **374** | 82.0% |
| `keyredef` (`&93D7-&97CD`) | 1,014 | **776** | 76.5% — confirms §1a's figure exactly |
| `PARMAN` whole | 6,093 | **3,595** | 59.0% — confirms §4b |

**Step 5's storage demand, stored as separable streams: 2,805 + 374 + 776 = 3,955 bytes**, against
§1a's 4,290 for the same content held unpacked. The two ways of holding it are 335 apart, which
is the measured version of §11d's "the generator saves ~200-300": it is the packing that saves,
not where the depack lands.

### 11j. SCANSTEP tail folding — as built, 2026-09-08. +1,512 bytes

**The first move of §11f, and `docs/ram-pass.md`'s held reserve is now spent.**

Every compiled rotor row used to end with the `SCANSTEP` macro expanded inline and its own `RTS`:

```
  INC svp : INC bufp : LDA bufp : AND #7 : BNE P%+5 : JSR SprScanRow   \ 13 bytes
  RTS                                                                  \  1
```

They end `JMP <tail>` instead — 3 bytes — and each bank carries one copy of the tail. **70 sites a
bank**, so 70 × 11 = 770 back, less 14 for the tail: **756 a bank, 1,512 in all.**

| | before | after |
|---|---|---|
| bank 5 (`spr`) | ends `&BD67`, **665** free | ends `&BA73`, **1,421** free |
| bank 6 (`spr2`) | ends `&BDD8`, **552** free | ends `&BAE4`, **1,308** free |

**Not the ~2,100 `ram-pass.md` promised.** That entry predates the SCANSTEP deferred carry
(2026-09-01), which took the macro from 15 bytes to 13 and therefore took 2 bytes off what each
fold could give back. The estimate was never re-derived; 756 a bank is the measured figure.

Where the 70 come from: 28 draw rows + 4 restore rows per shift, two shifts a bank, is 64 — plus
**6 `drRHalf` blocks whose last row emits a `SCANSTEP` immediately before the block's `RTS`**. The
emitter buffers each `drRHalf` block now so it can see whether it ends that way; the other ten end
on a restore and keep their own `RTS`.

**The cost is 3 cycles per compiled row DRAWN**, and nothing else — the JMP is on a path that was
already a JSR from its caller. Ten rotor rows drawn and ten restored per sprite makes 20 a sprite a
pass: ~120 cycles with two sprites up, ~480 with a full pool of eight. Against a 79,872-cycle pass
that is **0.6% at worst**, and the frame lock is unchanged: **50 passes in 100 fields on both
builds**, measured the same way on each.

#### How it was verified, and the trap that makes it work

The mechanical listing diff cannot validate this (it changes instructions by design), and the
buffer oracle checks the TILE layer with the sprite draws NOPed — so it cannot see this either.
The check that fits is an **A/B differential against the previous build**: same ship, same pass,
compare what was drawn.

**The trap: two builds do not play the same game.** `TiBootPal` seeds `drSeed` from `TiWait`'s
title dwell, and the two builds boot at different speeds because their disc images differ in size —
so the same key presses at the same frame counts give a different seed, a different starting deck
and a different droid layout. The first attempt scored **1,672 of 10,240** on a build that is
provably correct, entirely from that.

The recipe that works, and it is worth keeping:

1. Boot both, **breakpoint at `gs_seeded`** (`&A795`, bank 4 — `droid.asm`, just past the LFSR
   mix), press fire at the title and let each machine stop there.
2. **Poke `drSeed` to the same constant in both** (`&B5B6`, `write_memory` with `bank: 4`), then
   continue. Both then generate the identical ship — confirmed by reading `drType` back through
   `bank: 4` and comparing.
3. Drive both with the same input sequence, then **align on `gameTick` (`&2E4C`), never on frames**:
   the counter starts at the game, so equal `gameTick` means equal passes played.
4. **Stop both at the top of the main loop** (`&111E`) so the dumps are taken at the same point
   within the pass, and confirm the sprite pool (`sprActive`/`sprUnit`/`sprShift`/`sprScrY`/
   `sprFrame`, `&2CFC`) matches before trusting the buffer.
5. `save_memory` and `cmp`.

**The result: three checkpoints, zero differences.**

| checkpoint | region | bytes | differences |
|---|---|---|---|
| at rest, 2 sprites up, shift 1 | play buffer `&5800` | 10,240 | **0** |
| after 150 frames right + 110 down, player at shift 2 (so bank 6's compiled code) | play buffer | 10,240 | **0** |
| after a further 63 frames left | `&3E00–&8000` — sprite save areas, tile map, panel, LUTs and the strip | 18,944 | **0** |

The third is the one that also proves the **restore** path: `SPR_SAVE` is what the restore routines
write, and 32 of the 70 folded routines are restores.

### 11k. Interning the duplicate compiled blocks, 2026-09-08 — +2,368 bytes, no cycles

Straight after §11j, and it is the bigger of the two. **Every compiled block is reached only
through a dispatch table**, so pointing two table entries at one copy costs nothing at all: no
indirection, no cycles, just a different byte in a table that was always going to be there. It is
§4c's bank-4 finding — *what pays is redundancy, not compression* — applied to the compiled code.

`emit_rotor_code` now writes every block through a pool keyed on the block's own text, and hands
back the label that already holds an identical body. What that catches:

| | |
|---|---|
| **The two shifts' restore halves are identical** | a 1 px shift does not change WHICH columns a row touches, and a restore is keyed on the column set. 8 `drRHalf` blocks a bank become 4 |
| **The eight restore programs of a shift are two** | the sequence depends on `phase >> 2`, so phases 0–3 share one and 4–7 the other |
| **and then the programs collapse across shifts too** | once the halves are shared the two shifts' `drRPrg` bodies are textually identical. The saving compounds — which is why it came out at 2,368 rather than the 2,318 the duplicate-body scan predicted |
| a handful of blank draw rows | all now a bare `JMP <tail>`, so they are one block |

| | before (post-fold) | after |
|---|---|---|
| bank 5 | ends `&BA73`, 1,421 free | ends **`&B5A6`, 2,650 free** (+1,229) |
| bank 6 | ends `&BAE4`, 1,308 free | ends **`&B671`, 2,447 free** (+1,139) |

**Free bank space is now 225 / 2,650 / 2,447 / 759 = 6,081**, and step 5's 3,955 fits with room
for the first time.

**Verified the same way as §11j, and against the PRE-FOLD baseline**, so the two changes are
proved together: seed pinned at `gs_seeded`, aligned on `gameTick`, both stopped at `&111E`, and
`&3E00–&8000` (18,944 bytes — sprite save areas, tile map, panel, LUTs, strip) compared at two
checkpoints. **0 differences at both.** Frame lock still **50 passes in 100 fields**.

---

### 11l. Selling bank 6's tail fold back, 2026-09-09 — −613 bytes, +3 cycles a compiled row

**§11j's numbers are wrong and had been since the day they were written.** It records 70 sites a
bank and **756 bytes**; §11k's interning landed the same day, collapsed 13 of those sites onto
shared copies, and nobody netted the two off. Counted and then measured on 2026-09-09:

| | sites a bank | bytes a bank |
|---|---|---|
| §11j as recorded | 70 | 756 |
| **actual, after §11k** | **57** | **613** |

Measured, not derived: the exporter was unfolded wholesale, the bank-limit `ASSERT`s commented
out, and the gauge read. Bank 5 `&BFA8` → `&C21B` and bank 6 `&BB9A` → `&BE0D`, both **627** —
which is 613 plus the 14-byte tail that is then dead. 57 × 11 = 627 exactly.

**The cycle side is unchanged by any of this**, because interning changed which copies exist and
not how many rows execute: 3 cycles per compiled row **drawn**, 20 rows a sprite a pass, so ~120
with two sprites up and **~480 with a full pool of eight** — 0.6% of a 79,872-cycle pass.

#### The decision (KC, 2026-09-09): unfold bank 6, keep bank 5 folded

`tools/export_droids.py` grows a `FOLD_TAIL` tuple of bank indices; it is `(0,)`. The two banks
are asymmetric because their free space is:

| | free before | free after | fold |
|---|---|---|---|
| bank 5, `droids.asm`, shifts 0/1 px | 88 | **88** | kept — unfolding is 613 and there are 88 |
| bank 6, `droids2.asm`, shifts 2/3 px | 1,126 | **513** | **sold back** |

A sprite picks its bank on sub-pixel X, so about half the pool draws through the faster copy:
**~240 cycles a pass at eight slots** rather than the ~480 unfolding both would give.

**Nothing in the blitter cares which way a bank went.** The tails were already per-bank (a `JMP`
cannot reach the other bank), every compiled block is entered through a dispatch table, and the
tables are the same size in both files by construction — which is what `main.asm`'s address
asserts check, and they pass.

#### Why unfolding bank 5 as well does not fit, and what would make it

Bank 5 needs **525** more than it has. Its only movable content is a briefing page stream —
`brstream2` (574 packed) or `brstream3` (566) — and moving one gives bank 5 654, so it unfolds
with 41 to spare. **The evicted stream then has nowhere to land**: bank 6 after its own unfold has
513, bank 7 has 171, bank 4 has 225. `brstream3` is **53 bytes too big for the largest hole.**

That is a bin-packing failure and not a space one — total machine slack after unfolding both banks
is 384 bytes. Fifty-three bytes moved out of bank 6 into bank 7 or bank 4 closes it (`svdecks6.asm`
is 64 B and a candidate, subject to which bank is paged when it is read). The alternative is to let
`make_briefing.py` split a page into two streams that depack back-to-back into `BR_RECS`, which
turns the packing into arithmetic but costs the clean *no stream may span a bank* invariant.

**It was not done, and the reason is worth keeping:** the port holds 50 passes in 100 fields, so
240 more cycles a pass buys headroom and nothing visible. Taking banks 5 and 6 back to 41 and ~0
bytes — the state this whole branch spent three weeks climbing out of — is not worth 240 cycles
until something specific wants them.

#### How it was verified

Not by the buffer oracle (which NOPs the sprite draws and so cannot see this) and not by the
listing stream (which changes instructions by design). **By textual equivalence, which is stronger
than either**: expand every `JMP xScanStepRts` in the OLD `droids2.asm` into `SCANSTEP` + `RTS`,
drop the now-dead tail, and diff against the new file. 2,388 lines → 2,442, and **identical to the
new file's 2,442**. The generated code is provably the same program.

`droids.asm` is byte-identical to before, which git confirms. Then built and played: title, into a
deck, and a long run right with the deck scrolling clean behind the droid — bank 6's shifts draw
and restore correctly.


### 11m. Step 6 — unfolding bank 5 too, 2026-09-09. Both banks now unfolded

§11l left bank 5 folded because unfolding costs 613 and it had 88. This found the 525, and the
interesting part is **why it was hard**, because the reason is structural and will recur.

#### The constraint that actually binds

**Bank code cannot page another bank in** — it would page itself out mid-instruction. So bank 5's
contents divide three ways:

| stuck in bank 5 | free to move anywhere | borderline |
|---|---|---|
| `droids.asm` 9,742 | `krimg` 774 | `sprscan.asm` 538 |
| `effects.asm` 2,977 + `sprfx.asm` 419 | `brstream2` 574, `brstream3` 566 | |
| | `sndchat` 15, `brextra` 64 | |

The streams and `krimg` are pure data depacked by main-RAM code, so they can live in any bank.
**And every one of them was bigger than the largest hole in the machine (bank 6's 513.)** That one
fact is why nothing could move: 774, 574 and 566 against holes of 513, 225 and 171.

The arithmetic is also better stated the other way round. Banks 5 and 6 had **1,214** free between
them and the two unfolds cost **1,226**, so the requirement was never "find 525" — it was **export
12 bytes net out of banks 5+6, and be able to shuffle across the 5/6 boundary**. Everything hard
was granularity, not space.

#### What was done, in three parts

**1. `sprscan.asm` went home to bank 6 (538 out of bank 5).** It was split out of `sprsplit.asm`
on 2026-09-01 only because bank 6 had seven bytes left; the two halves are one 634-byte file that
fitted nowhere. It is bank *code*, but it is called from a main-RAM bridge and reads only main RAM,
zero page and the low overlay — which is what made it movable then and now. **It costs a page flip
less than the split did**: `SprSplitOK` paged bank 5, called the geometry, paged bank 6 and called
the decision; it now pages bank 6 once and calls both. Three bytes of code image back too.

**2. Page 5 of the briefing was cut in two (313 out of bank 6).** A page is one ZX0 stream and no
stream may span a bank, so a page can only live where a hole fits the whole of it — page 5 whole is
313 and neither bank 4 (225) nor bank 7 (171) could take it. Cut, it is **175 + 154**.

Cutting is nearly free, because `Zx0Unpack` leaves `mapptr` past its last byte: chunk B depacks
straight on from where chunk A stopped, with no offset arithmetic. **The cut may fall anywhere** —
the chunks are consecutive bytes of one blob, not rows — so `make_briefing.py` searches every cut
and takes the smallest pair. Measured cost of a two-way split, all five pages: **+54, +74, +65, +73,
+23**. Page 5 is the cheapest by some way, and at the chosen cut (270) it is **+16**.

The search is 29 seconds and the build is eight, so the chosen cut and a hash of the page are
written into the generated file's header and read back. Edit a word of page 5 and the hash misses
and it re-searches; touch anything else and it does not. **That is why the cut is not a constant** —
a constant would go stale silently on the one edit that invalidates it.

**3. Both chunks were placed to cost as little as possible.** Chunk A (175) went into **bank 7 in
front of `plandata.asm`'s `ALIGN`**, which had **208 bytes of padding doing nothing** (measured):
it rides the pad, so bank 7's tail is **unchanged at 171**. Chunk B (154) went to bank 4's tail,
because bank 4's own `colourMap` pad is down to **10 bytes** and there is no free ride there.

#### Where it landed

| | before step 6 | after |
|---|---|---|
| code image | 108 | **70** (`BrDepackChain`, 38 B) |
| bank 4 | 225 | **71** |
| bank 5 | 88 | **15** — unfolded |
| bank 6 | 513 | **294** |
| bank 7 | 171 | **171** (its `ALIGN` pad 208 → 33) |

**Both banks are now unfolded: ~480 cycles a pass at a full pool of eight, up from ~240.**

#### The safety valve, which is the point of leaving the machinery in

`export_droids.py`'s `FOLD_TAIL` is now empty, and the folding code stays. **Put a bank index back
in it and that bank gets 613 bytes at 3 cycles a compiled row** — the cheapest large block of space
left in the machine and the only one that can be taken without moving anything. Bank 5 has 15 bytes,
so it is the likely customer. A partial fold (some blocks folded, some not) was considered and
rejected: it works, but it makes the exporter's output depend on a budget that has to be retuned
whenever anything else in the bank changes, and a byte added elsewhere would silently refold a
block. All-or-nothing per bank is a knob that cannot rot.

#### How it was verified

- **The unfold, by textual equivalence**, as in §11l: expand every `JMP ScanStepRts` in the old
  `droids.asm` to `SCANSTEP` + `RTS`, drop the dead tail, diff. 2,326 lines → 2,380, identical to
  the new file's 2,380.
- **The split page, by `verify_brstreams.py`** — which now decompresses *both* chunks and
  concatenates them, exactly as `BrDepackChain` does, before diffing against beebasm's own bytes.
  All five pages match byte for byte and all 285 pointers scan back correctly, page 5 included.
- **By eye**: the whole briefing run through to page 5 (the split one) renders correctly, and a
  game started out of it plays with the deck scrolling clean behind the droid.
- Debug and `-Release` both assemble.

#### What was ruled out on the way, with the measurement

- **Interning the compiled glyph code.** It bypasses the pool §11k used on the rotor — but 20 blocks
  a bank, **20 distinct, 0 duplicates**. Nothing there.
- **`conicons` (189) out of bank 6.** Illegal: `console.asm` executes from bank 6 and reads it by
  address.
- **Moving `sprfx.asm` (419).** Tied to `effects.asm` (2,977), which fits no hole.
- **Bank 4's `colourMap` pad as a source.** Ten bytes left; the 11th costs 256.


## 12. WHERE THE NIGHT OF 2026-09-08 GOT TO — read this first

Four commits, each verified and each with its own section above. **The branch is in a good state:
it builds, it plays, and every change is proved byte-identical in what it draws.**

| | |
|---|---|
| `dc62e8c` | §11: the plan re-audited. §10's test list cleared in jsbeeb |
| `7236ba2` | §11h/§11i: step 6 measured (241 bytes, not 869) and the briefing's pieces packed |
| `bd6a4f3` | §11j: SCANSTEP tail folding — **+1,512** |
| `4304843` | §11k: interning the duplicate compiled blocks — **+2,368**, and free |

**Free bank space went from 2,201 to 6,081 in a night**, all of it in the two sprite banks and
**none of it costing a cycle** except the folding's 3-per-row (0.6% of a pass at worst; the frame
lock still measures 50 passes in 100 fields).

| bank | at the start of the night | now |
|---|---|---|
| 4 (data) | 225 | 225 |
| 5 (spr) | 665 | **2,650** |
| 6 (spr2) | 552 | **2,447** |
| 7 (xfer) | 759 | 759 |
| **total** | **2,201** | **6,081** |

### The ledger, restated

**Step 5's demand is 3,955** (§11i, measured: 2,805 of page streams + 374 `briefman` + 776
`keyredef`) **against 6,081 of supply. It fits for the first time, with 2,126 to spare.** Space is
no longer what blocks the no-load goal.

That also means **further byte-hunting is no longer the priority** — it was, right up until
tonight. What remains is architectural, and §12a is the part that wants a decision rather than
more measuring.

### 12a. What is left, and what it needs from KC

**Step 5 is a real rearrangement and it is where I stopped.** The shape is §11e's and the space is
now there, but every option below changes where things live and how the briefing is fed, and
`CLAUDE.md` says that is agreed before it is built rather than after. The choices:

1. **Where each piece lives.** `briefman` (456, must be unpacked to run) and the five page streams
   (2,805 packed) and `keyredef` (776 packed) have to be distributed across banks 5 and 6, and
   nothing may span a bank. There is room for several arrangements; the one that matters is
   whether the briefing's code and the text it walks end up in the SAME bank, because only one is
   visible at a time.
2. **Which buffer the pages depack into.** The tile map is 1,024 and §5's largest page is 1,082 —
   **56 bytes too big**. Either the exporter splits the text into six or seven streams instead of
   five (costing a little more packed size but fitting the map exactly), or the buffer becomes the
   map plus something else, which is not contiguous. My recommendation is more, smaller streams:
   it keeps the arena rule (§2) intact and unchanged.
3. **`keyredef` runs from the map.** 1,014 unpacked against the map's 1,024 — ten bytes of margin,
   and it grows if the redefine screen ever gains a line.

**`PARBRF` and `PARALOW` looked like the easy pair and they are not.** Both would now fit in a bank
raw (1,012 and 919, and there is room), which would take the post-boot loads from five to three
without touching the briefing at all. The obstacle is mechanical: `PARTITL` rides in bank 7 via
`COPYBLOCK`, which works **only because bank 7's block is the last one assembled**, so nothing
overwrites `&8000` before its `SAVE`. Bank 6's `SAVE` cannot be deferred the same way — bank 7's
block re-uses the same addresses immediately after it. Options are to reorder the bank blocks (the
`ALIGN` pads and `xfericon.asm`'s position are load-bearing, so this is not free), to assemble the
low overlay inside bank 6's block before the `COPYBLOCK` (beebasm resolves constants in file order,
so this risks a forward-reference tangle), or to add a two-pass build step. **Each is a build
change and none should be picked unattended.**

### 12b. What was NOT done, and is still true from §10

Real hardware. The transfer's LOSE path. A systematic walk of all eight rotor phases and 24 types
(the A/B differential covers what is drawn far better than eyes would, but only for the sprites
that happened to be on screen).

### 12c. Two things worth keeping from the method

**The A/B differential recipe (§11j) is now the tool for anything that changes the compiled code**,
and it is cheap to re-run: pin the seed at `gs_seeded`, align on `gameTick`, stop both machines at
`&111E`, compare `&3E00-&8000`. It found nothing wrong tonight in four checkpoint pairs, but the
first attempt — before the seed was pinned — reported 1,672 wrong bytes on a provably correct
build, which is exactly the false positive that would have cost a session.

**The estimates in this document have been running low.** Three have now been measured against
their guesses: step 6 (869 -> 241), the tail folding (2,100 -> 1,512) and the duplicate-block
interning (2,318 -> 2,368, the only one that came in high, and only because the saving compounds).
Treat the rest of §11c the same way: measure before spending.

---

## 13. PARBRF AND PARALOW GO RESIDENT — 2026-09-09. Post-boot loads 5 → 3

§12a said this pair "looked like the easy pair and are not", and named the obstacle: `PARTITL`'s
`COPYBLOCK` works only because bank 7 is the LAST bank block assembled, and bank 6's `SAVE` cannot
be deferred the same way. **The 4A experiment answered it, and the answer was yes.**

### 13a. The experiment

Move the two overlays' assembly ABOVE bank 6's block, so bank 6 can `COPYBLOCK` them and still
`SAVE` before bank 7 reuses `&8000`. beebasm resolves constant assignments in file order, so the
question was how many constants the overlays use that are defined later.

**Answer: six** — and a static probe found them in one pass rather than by rebuilding six times.
`BR_EXIT_FIRE`, `BR_EXIT_OFF`, `BR_TRAVEL`, `LAMP_OFF` and `ALERT_LAMP_CHAR` looked late but are
defined *inside the overlays themselves*, so they travel with them.

| constant | was defined in | now |
|---|---|---|
| `BR_PAGES`, `BR_ROW_LO`, `BR_ROW_HI`, `BR_XTRA0` | `src/data/briefing.asm` (generated) | **`src/data/briefconst.asm`**, a second generated file `main.asm` includes from its header |
| `BR_CHAT_PRE` | `src/data/sndchat.asm` (generated) | `main.asm`, beside `UNIT_BYTES`; the old home `ASSERT`s it |
| `BR_PO_UNIT`, `BR_PO_OFS` | `src/briefman.asm` | the same, with `ASSERT`s |

A first attempt moved the whole PARMAN block up instead, to bring the `BR_*` constants with it.
That failed on `BR_PO_ROW0 = DB_IMG_ROW`, which reaches into **bank 7** (`condb.asm`) — so the
dependency chain would have dragged bank 7 up too, defeating the point. Splitting the four
generated constants into their own file is what avoids that: `BR_PO_ROW0` stays in `briefman.asm`,
late, where it is happy.

**The move itself was proved inert before anything was built on it:** with the blocks moved and
the constants hoisted, **every file in the disc catalogue was byte-identical** to the build before
it — `PARA`, `PARADAT`, `PARASPR`, `PARSPR2`, `PARXFER`, `PARAFNT`, `PARMAN`, `PARSWR`, and
`PARBRF` and `PARALOW` themselves — with `!BOOT` the only difference, which carries the build
stamp. That is `beeb-identical-build`'s step 4, and it is the strongest thing that could be said
about a pure reordering.

### 13b. What was then built

`brfImg` and `lowImg` are `SKIP brf_end - brf_start` and `SKIP low_end - low2_start` at the tail
of bank 6, filled by `COPYBLOCK`. **No hand-maintained size constant** — the overlays are assembled
before the bank now, so the assembler knows their lengths; `PARTITL` could not do that and pays for
it with `TITL_BYTES`.

`BrfResident` and `LowResident` live **in bank 6**, like `TiResident` lives in bank 7, so they cost
the code image nothing; both end in main RAM's `PgData` for `TiResident`'s reason — a `PAGEBANK`
executed in the bank would swap the `RTS` out from under itself. Three whole pages then a tail,
because neither image is a round number of pages and over-copying either would be a write into
somebody's live memory.

Call sites: `TiShow` (`JSR PgSpr2` / `JSR BrfResident` in place of `TiLoadBrf`) and `ts_loads`
(the same pair in place of the `*LOAD PARALOW` OSCLI).

| | before | after |
|---|---|---|
| post-boot loads | 5 | **3** — `PARAFNT`, `PARMAN`, `PARASPR` |
| disc files | 11 | **9** |
| disc image, packed | 46,336 | **45,568** |
| main-RAM code image free | 14 | **28** (the two OSCLI strings and their call sites) |
| bank 6 free | 2,447 | **442** |
| bank 7 free | 759 | **775** (the title overlay lost `TiLoadBrf`: 397 → 381 bytes, so `titlImg` shrank) |

**Verified in jsbeeb, the whole front-end loop on the shipping image:** cold boot → title →
fire → game (which is `LowResident`; the low overlay carries the IRQ, the rupture and the keyboard,
so a bad copy does not get as far as a screen) → ESCAPE → death → game over → high-score entry →
three initials → **title again** → briefing on the timeout → fire → game. The second title is the
one that matters for `BrfResident`: it arrives through `GoTitle`, after `RestoreDfsWs`, and
`BrDispatch` — which every post-title path runs through — lives in the bytes it copies.

### 13c. What is left

**Two loads and the briefing.** `PARMAN` and `PARASPR` are step 5's, and `PARAFNT` becomes
boot-only once step 5 stops staging at `DEPK_STREAM`. The decisions in §12a stand unchanged; only
decision 4 is now answered and spent.

Bank 6 has 442 left, bank 5 has 2,650, bank 7 775, bank 4 225 — **4,092 free**, against step 5's
~4,360 under §12a's recommended shape (2B + 3B). **That is ~270 short**, so step 5 wants either
the packed `keyredef` (3A, which gives back 238 and reinstates the ten-byte margin) or ~300 bytes
from somewhere. `dfsSave`'s 912 is still the terminal dividend and still cannot be spent early.

---

## 14. STEP 5, MEASURED AND DESIGNED — 2026-09-09

KC chose **1C, 2B and 3A** from §12a. The measurements below settle the design, and **one of the
three turns out to be unnecessary**.

### 14a. The pages are not the size §5 said

Measured from the generated `src/data/briefing.asm`, per page: 57 row records plus a 114-byte
pair of pointer tables (`brRowLo_p` / `brRowHi_p`).

| page | records | + tables | ZX0 (records only) | ZX0 (with tables) |
|---|---|---|---|---|
| 0 | 624 | 738 | 409 | 474 |
| 1 | **967** | **1,081** | 604 | 671 |
| 2 | 962 | 1,076 | 574 | 643 |
| 3 | 932 | 1,046 | 566 | 634 |
| 4 | 435 | 549 | 292 | 356 |
| | 3,920 | 4,490 | **2,445** | **2,778** |

**§5's "the buffer needed is 1,082" is the page WITH its pointer tables.** The records alone top
out at 967, which already fits the 1,024-byte map — so **2B's split is not needed**, and the
briefing keeps its five pages exactly as the original has them. What to do with the 114-byte
tables is the only real question, and it is worth 337 bytes: 2,445 + 5 x 114 = 3,015 resident if
they stay in a bank, against **2,778** if each page is ONE stream with its tables inside it.

The tables hold absolute addresses, so the second only works if the depack lands at a **fixed
base** — which it does. The exporter assembles each page as if it lived at the buffer, so the
pointers are correct by construction and nothing has to be relocated at run time.

### 14b. The arena is bigger than the map, measured

Seeded `&4220-&460F` with `&A5` at the title, ran the briefing, read it back:
**296 bytes written, all of them `&4220-&4347`; `&4348-&4600` came back untouched.** That span is
contiguous with the tile map, so the briefing's arena is **`&4348-&4A00`, 1,720 bytes** rather
than the map's 1,024.

The 296 is more than `BmSnap`'s rectangle (`BR_PO_ROWS` 11 x `BR_PO_SPAN` 96 = 1,056, ending at
`&4220`) and **has not been explained**, so the design does not spend to the line: the buffer
starts at **`&4500`**, 440 bytes clear of the observed high-water mark, and still holds the
largest page (1,081) with 199 to spare.

### 14c. The budget, and it fits

| | bytes |
|---|---|
| five page streams, tables inside (14a) | 2,778 |
| `briefman` + `sndchat`, unpacked because they run | 471 |
| `keyredef` packed (3A), depacked into the arena on CTRL+R | 776 |
| **demand** | **4,025** |
| free: bank 4 225 + bank 5 2,650 + bank 6 442 + bank 7 775 | **4,092** |
| **spare** | **67** |

Thin, and every figure in it is now measured rather than estimated. If it needs more, the next
432 are in **packing `brfImg` and `lowImg`** (§13 stores them raw: 1,012 and 919 against 769 and
730 packed) — which needs the build pass of §12a's option 4C.

### 14d. The design that follows

- **The text is main RAM's during the briefing.** One ZX0 stream a page, assembled at `&4500`,
  depacked there on each page turn. The renderer walks main RAM and needs no paging at all for
  text, which is simpler than today.
- **`keyredef` shares the same arena** (3A): 1,014 unpacked into `&4500`, which the page it
  replaces was using. CTRL+R already repaints on return, so the page is simply re-depacked.
- **`briefman` and `sndchat` stay bank-resident code**, and the page streams are distributed
  across banks 4-7 by a per-page bank byte (1C) — nothing spans a bank.
- **Both loads go**: `BrTimeout` stops loading `PARMAN` and `BrDispatch` stops reloading
  `PARASPR`, because bank 5 is never evicted. `PARAFNT` then has no destroyer left and can
  become boot-only, which is the third and last load.

---

## 15. STEP 5 STAGE 1 — the data pipeline, 2026-09-09

**KC confirmed §14a's finding: the briefing keeps its five pages, 2B is off the table.**

### 15a. What was built

`tools/make_briefing.py` now lays each briefing page out **twice**. It still writes
`src/data/briefing.asm` — the bank-5 `PARMAN` records the old renderer walks, unchanged — and it
additionally assembles each page **in Python**, as the bytes it will be in main RAM, with every
record address resolved as if the page lived at `BR_RECS`. Each blob is ZX0'd through
`bin/zx0.exe`, round-tripped through `tools/zx0.py` (the format the 6502 depacker eats) and
written to `src/data/brstreamN.asm`.

The tool also emits, into `src/data/briefconst.asm`: `BR_BUF_ASSUMED` (its copy of the depack
address, which `main.asm` asserts against), `BR_PAGE_MAX` (the largest page's row lists, for the
arena assert) and `BR_HISCORE` / `BR_LOSCORE` / `BR_SCORE_PAGE` — the two records `BmPatch`
writes, as the addresses they will have in the depacked page. It refuses to build if the two
score records ever land on different pages, because only the page that is currently depacked can
be patched.

**Nothing reads the streams yet.** The old path is untouched and this stage is pure data.

### 15b. The check, and it is the strong one

`tools/verify_brstreams.py` decompresses each emitted stream and diffs it against **the bytes
beebasm actually emitted**, pulled out of `PARMAN` in `build/PARADROID-raw.ssd` using beebasm's
own `-d` symbol dump — not against `make_briefing`'s idea of them, so a slip in the blob builder
cannot survive.

```
page 0: 624 record bytes identical, 57 pointers scanned back from &4572
page 1: 967 record bytes identical, 57 pointers scanned back from &4572
page 2: 962 record bytes identical, 57 pointers scanned back from &4572
page 3: 932 record bytes identical, 57 pointers scanned back from &4572
page 4: 469 record bytes identical, 57 pointers scanned back from &4572
verify_brstreams: all 5 pages match beebasm byte for byte
```

**§14a's page-4 figure is wrong and this is the correction.** It says 435 records; the generator
emits **469**, and its own byte count (3,954 bytes of lists) agrees with 624 + 967 + 962 + 932 +
469 and not with §14a's 3,920. Every other page in that table is right.

### 15c. The tables are NOT in the streams — KC, 2026-09-09

§14a compared two ways of holding a page's 114-byte pointer pair: inside the stream (2,798 packed
as measured, and the design §14d agreed) or bank-resident beside it (2,466 + 5 x 114 = 3,036).
**There is a third and it is the cheapest: ship neither, and rebuild the tables at run time.**
Re-packed both ways today:

| | packed |
|---|---|
| five streams, tables inside | 2,798 |
| five streams, **row lists only** | **2,466** |
| | **332 saved** |

The scan is unambiguous because the record format already reserves its two sentinels: `&FF` ends
a row and `&FE` ends a record, and neither a column byte (42 at most) nor a glyph index (107 at
most) can collide with either. Fifty-seven rows, one walk over ~1,000 bytes, once per page turn —
against ~40 bytes of code, and on a modal screen where the depack that precedes it costs more.

**KC took it**, so the layout is:

```
BR_BUF   &4500   brRowLo, 57 bytes    built by the driver, not shipped
         &4539   brRowHi, 57 bytes    likewise
BR_RECS  &4572   the depacked row lists, 967 at the largest
```

`main.asm` declares both and `ASSERT`s `BR_BUF == BR_BUF_ASSUMED` and
`BR_RECS + BR_PAGE_MAX <= PANEL_ADDR`. The record addresses the tool emits are still absolute and
still correct by construction; only the tables that point at them are built at run time.

**`verify_brstreams.py` runs that scan too**, in Python, over the decompressed stream, and checks
every pointer it derives against the bank's own `brRow_p_r`. All 285 pointers over the five pages
agree — so the algorithm the driver has to implement is proved at build time, before a line of
6502 is written for it.

### 15d. Where they were put, and why it is not arbitrary

| stream | packed | bank |
|---|---|---|
| page 2 | 604 | 5 |
| page 3 | 574 | 5 |
| page 4 | 566 | 5 |
| page 1 | 409 | **6** |
| page 5 | 313 | **7** |
| | **2,466** | |

**Bank 5 is being kept whole for `keyredef`.** Packed it is 776, and after this it is the ONLY
bank with a hole that big — bank 7 has 775, one byte short, which is the sort of coincidence that
decides a layout. Bank 7's 462 is `briefman`'s 456. Bank 4's 225 is `brExtra` (64) and `sndchat`
(15), the only two pieces small enough to use it at all. Measured from the gauges after:

| bank | before step 5 | now | stage 3 will put there |
|---|---|---|---|
| 4 | 225 | 225 | `brExtra` + `sndchat` (79) |
| 5 | 2,650 | **906** | `keyredef` packed (776) |
| 6 | 442 | **33** | — |
| 7 | 775 | **462** | `briefman` (456) |
| **total** | **4,092** | **1,626** | **1,311** |

### 15e. THE BUDGET, RESTATED — §14c totalled a pool and it is not one

§14c's 4,092-against-4,025 has two faults. The demand left out `brExtra` (64) and `sndchat` (15)
and used estimates for the rest; and the supply is four bins, not a pool. Measured from the
symbol dump (`man_start` &8000, `brExtra` &91C0, `BmPatch` &921F, `BmKrRun` &93D7, `man_end`
&97CD), the stage-3 demand as originally designed was:

| | bytes |
|---|---|
| five page streams, tables inside | 2,798 |
| `brExtra` | 64 |
| `sndchat` | 15 |
| `briefman` | 456 |
| `keyredef`, packed | 776 |
| **demand** | **4,109** |
| supply | **4,092** |

**Seventeen short before a byte of new code**, and worse in practice, because bank 4's 225 can
hold nothing but the smallest two pieces. §15c's 332 is what turns that into the 315-byte
surplus above.

**And 315 is fragile: 130 in bank 5, 33 in bank 6, 6 in bank 7, 146 in bank 4.** The driver, the
per-page bank/address table and `briefman`'s trampolines still have to come out of it — and **the
driver has to be MAIN RAM**, because a routine in a bank cannot page another bank in without
pulling the rug from under itself, so what it wants is `PARBRF`'s 12 bytes or the code image's 28
rather than any of this. §14c's `brfImg`/`lowImg` packing (+432, needing the two-pass build of
§12a option 4C) is the reserve if it does not close, and it lands in banks 6 and 7, which is
exactly where the fragility is.

### 15f. Verified

**Cold boot → title → briefing on the timeout, on the shipping image in jsbeeb, `B-DFS1.2`.**
The briefing paints and scrolls exactly as before, which is the whole of the check stage 1 can
carry: nothing reads the streams yet, so this is a build-time change and `verify_brstreams.py` is
where its proof lives.

---

## 16. THE BUILD GROWS A PACK PASS — 2026-09-09

**Two decisions from KC, both forced by measurement rather than chosen freely.**

### 16a. Stages 2 and 3 cannot be separated

The handover's stage 2 — "the renderer reads the buffer; `PARMAN` still loads and `briefman` is
still inside it" — **cannot be built**. `PARMAN` is loaded OVER bank 5, and three of the five page
streams have to live in bank 5, because bank 5 is the only bank with a hole big enough for
`keyredef`'s 776 and the streams are what keep the rest of it usable. The load that delivers the
renderer would evict the text the renderer reads.

So the page streams, the renderer change, the bank-residency of `briefman`/`sndchat`/`brExtra`/
`keyredef` and the removal of both loads all land in one step. **KC agreed 2026-09-09.**

### 16b. The budget is short again, and the fix was already required

Packing measured against the real bin sizes, and it does not fit. Bank 4's 225 can hold nothing
(the smallest stream is 313) and bank 6's 442 absorbs exactly one mid-size item, so at best
banks 6 and 7 together take ~1,013 of the 3,242 that can go anywhere, leaving bank 5 needing
2,229 of the 2,035 it has after `briefman` and friends. **194 short.**

**The fix is a build pass that step 5 needed anyway.** §12a's 3A — `keyredef` shipped packed —
is impossible inside one beebasm run: beebasm cannot compress its own output, and `keyredef` is
assembled code. So the extra pass was never optional; §14c's `brfImg`/`lowImg` packing is the
same mechanism applied to two more blocks, and it lands in banks 6 and 7, exactly where the
fragility is. **KC took it.**

### 16c. As built — the pack loop

`tools/pack_overlays.py`. `main.asm` `SAVE`s each block under an X-name (`XBRF`, `XLOW`); the
tool reads them back out of the disc image, ZX0s them with `bin/zx0.exe`, round-trips each
through `tools/zx0.py` and writes one generated file per overlay for the next assembly to
`INCLUDE`. `build.ps1` loops on its exit code — **0 nothing changed, 10 a stream was rewritten,
assemble again**.

**The loop is not belt and braces.** A stream that changes SIZE moves the bank around under the
very block it came from, so the extracted bytes could be from a layout that no longer exists.
The exit code makes convergence a build-time fact rather than an assumption. Measured from a
cold start (both generated files deleted): **stub, assemble, pack, assemble, unchanged — two
assemblies, and the second confirms the overlays' bytes did NOT depend on the bank layout.**
In the steady state it is **one** assembly: the first pass extracts what is already there.

Two details worth keeping:

- **The X-files never reach the disc.** `make_disc.py` writes only the names in its `LAYOUT`, so
  they are dropped for free and no rule had to be added.
- **The size `ASSERT` lives in the generated file, not in `main.asm`.** The bootstrap stub cannot
  know the size it will eventually hold, so it omits the assert and still assembles; every real
  stream carries `ASSERT BRF_IMG_UNPACKED == brf_end - brf_start`. A stale generated file still
  fails the build.

`BrfResident` and `LowResident` become depacks rather than three-page-and-a-tail copies — half
the code, and the tail arithmetic goes with it. `Zx0Unpack` is main RAM, so calling it from bank 6
is the ordinary direction and the stream it reads stays paged throughout.

### 16d. What it bought, and what it cost

| | before | after |
|---|---|---|
| `brfImg` | 1,012 | **769** |
| `lowImg` | 919 | **731** |
| bank 6 free | 33 | **494** |

**+461** — 431 from the packing and 30 from the shorter copiers.

**It costs disc space: the image went 47,872 -> 50,176, +2,304 bytes.** A ZX0 stream inside
`PARSPR2`'s own ZX0 stream compresses worse than the raw code did, which is the standard
double-compression penalty and the price of the bank bytes. Boot time was not re-measured.

### 16e. Verified

**The whole front-end loop, on the shipping image in jsbeeb, `B-DFS1.2`** — and it is the right
test, because `LowResident` delivers the IRQ, the rupture and the keyboard, and `BrfResident`
delivers `BrDispatch`, which every post-title path runs through:

cold boot -> title -> fire -> **game** (the panel reads "Mobile", the deck is drawn, the player
is on it) -> ESCAPE -> death -> game over -> high-score entry -> three initials -> **title
again**, through `GoTitle` after `RestoreDfsWs` -> **briefing on the timeout**, scrolling.

---

## 17. THE BRIEFING GOES RESIDENT — 2026-09-09. Post-boot loads 3 → 1

**`PARMAN` and the `PARASPR` reload are gone. `PARAFNT` is the only load left after boot.**

### 17a. What was built

| | |
|---|---|
| the text | five ZX0 page streams in the banks (§15), depacked one at a time to `BR_RECS` |
| the tables | built at `BR_BUF` by `BmRowScan`'s `$FF` walk, not shipped (§15c) |
| `briefman`, `sndchat`, `brExtra` | bank-resident in bank 5, the briefing's resting bank |
| `keyredef` | a ZX0 stream in bank 5, assembled at `BR_RECS` and depacked over the page |
| `BrTimeout` | no `*LOAD PARMAN`, no `UnpackBankIn` — just the score ferry |
| `BrDispatch` | no `PARASPR` reload on either exit |
| `PARMAN` | out of `make_disc.py`'s `LAYOUT` and `COMPRESSED`, and its `SAVE` gone |

The renderer is simpler than it was. `BrRowList`'s per-page table walk — four `LDA abs,X`/`STA zp`
pairs through `brPageLLo`/`LHi`/`HLo`/`HHi` to keep every index 8-bit across 285 rows — is **two
loads from main RAM**, because the depacked page carries one page's tables at a fixed address:

```
  LDA BR_BUF,Y          : STA brp
  LDA BR_BUF+BR_ROWS,Y  : STA brp+1
```

`PARBRF` shrank from 1,012 bytes to 967 on that alone.

**The score patch moved in time, not in place.** The records used to be bank 5's and persisted for
the whole briefing, so one `BmPatch` at entry did it. They are the arena's now and only the page
that is up exists — so `BrFerryScores` carries bank 7's fourteen bytes into `brSc` once, and
`BmRowScan` applies them on **every** depack of `BR_SCORE_PAGE`. The exporter emits `BR_HISCORE`,
`BR_LOSCORE` and `BR_SCORE_PAGE`, and refuses to build if the two records ever land on different
pages.

### 17b. THE BUG THAT WAS WORTH THE WHOLE TEST: the portrait shares the arena

Page 5 came up as pure noise. **`PoDraw` depacks a portrait chunk into `PO_BASE`, which is the
tile map at `&4600`** — straight through the middle of `BR_RECS`, which for page 5 runs
`&4572`–`&4747`. §14b measured the arena's high-water mark and put `BR_BUF` clear of it, and that
was right as far as it went; what it did not account for is that the briefing *itself* invokes a
screen that takes the map for its own arena.

The fix is an ordering one: **`BrDepack` runs after `BrPortrait`, not before it.** The portrait's
chunk is dead the moment `BmSnap` has copied the rendered rectangle to `SPR_SAVE`, so the page can
land on it afterwards. §7's rule about a depack between a palette change and its redraw does not
bite here — `BmPalHide`'s ink is invisible, so the gap shows nothing, and `BrPortrait` has always
carried a depack in exactly that gap.

**The lesson generalises: the arena rule applies to the briefing too.** It is the screen that
lives in the arena longest, which made it easy to think of the space as the briefing's.

### 17c. And one the catalogue caught

The build-only `SAVE`s — `XBRF`, `XLOW`, `XKR` and `XREC` — **shipped on the disc**, 7,444 bytes
of them. `make_disc.py`'s `build_image` does not keep only the names in `LAYOUT`; it appends
anything it does not recognise, which is how an `--intro` build carries PINTRO's data files. A
`BUILD_ONLY` set now drops them by name, and the tool prints what it dropped.

**Nothing in the emulator would have found this**, because a bigger disc still boots. It took
listing the catalogue.

### 17d. What it cost and what it bought

| | before step 5 | now |
|---|---|---|
| post-boot loads | 3 | **1** — `PARAFNT` |
| disc files | 9 | **8** |
| disc image | 47,872 | **45,312** |
| bank 4 | 225 | 225 |
| bank 5 | 2,650 | **88** |
| bank 6 | 442 | **212** |
| bank 7 | 775 | **171** |
| main-RAM code image | 28 | 28 |
| `PARBRF` | 12 free (1,012 used) | 57 free (967 used) |

**696 bytes of bank space left**, and the two briefing exits no longer make a filing-system call
at all — ~0.7 s off each.

Placement, and none of it is arbitrary: bank 5 holds the briefing's resident code and `keyredef`'s
776 (the only hole that big — bank 7 had 775, one byte short) plus pages 3 and 4; bank 6 holds
pages 1 and 5, which it could only do because §16 packed the two overlays above it; bank 7 holds
page 2, the largest. Bank 4's 225 still holds nothing of the briefing's — nothing is small enough.

### 17e. One constant had to be hoisted, for §13a's reason

`briefman.asm` moved from the very last block to bank 5's, and `BR_PO_ROW0 = DB_IMG_ROW` reaches
into **bank 7**, which is now later. §13a named this exact dependency as what defeated its first
attempt. `BR_PO_ROW0 = 3` lives in `main.asm`'s header with the other six now, and `condb.asm`
`ASSERT`s `DB_IMG_ROW == BR_PO_ROW0`, so the portrait cannot be moved on one side only.

`keyredef.asm` also had to be assembled **after** `briefman.asm`, which owns the `bmp` zero-page
alias: a forward reference to a zero-page constant is sized absolute on pass 1 and zero page on
pass 2, and beebasm stops with *the second assembler pass has generated different code to the
first*.

### 17f. Verified, in jsbeeb on the shipping image, `B-DFS1.2`

- cold boot → title → **fire → game** (deck drawn, sprites drawn, scrolls)
- title timeout → **briefing**, all five pages walked by eye: page 1, the controls page, the
  story page, the device page (which exercises `brExtra` — the apostrophes in "device's" and
  "'normal'"), and **page 5 with its portrait and both score lines patched**
- **CTRL+R** → the redefine screen depacked over the page, six keys taken, → back to page 5,
  re-depacked and re-patched with a fresh portrait
- **fire out of the briefing → game**, which is what the `PARASPR` reload existed for: the
  blitter draws, the deck scrolls, the score counts
- ESCAPE → death → game over → high-score entry → three initials → **title again** (through
  `GoTitle` after `RestoreDfsWs`) → briefing again
- **the off-the-end exit**: `brPage` poked to the last page, the travel run out, `br_out` →
  title → timeout → a fresh briefing

### 17g. What is left

**Step 5's stage 4: `PARAFNT` becomes boot-only.** Nothing stages at `DEPK_STREAM` any more, so
`&3000` has no destroyer left; `ts_loads` is shared three ways (boot, game-over, briefing exit)
and needs a flag or a split. **That is the last load**, and after it the terminal dividend of §11h
— `dfsSave`'s 912 bytes of bank 6, `SaveDfsWs`/`RestoreDfsWs`, the OSCLI strings and
`UnpackBankIn`/`BootBanks` — comes due.

---

## 18. NO LOADS AFTER BOOT — 2026-09-09. The goal of the branch

**`PARAFNT` is loaded once, in `.start`, and every filing-system call the game makes now happens
before the first `PageLowIn`.** Stages 4 and 5 landed together because stage 4 forces stage 5.

### 18a. The font goes boot-only

The load lived in `ts_loads`, which **every** route to the front end runs — boot, the game-over
title and the briefing's fire exit — and it lived there because the title overlay was MODE 1
artwork at `&3000` and ate the font every time it was shown. no-load step 3 moved that overlay to
`&0900`; step 5 took away the last thing that staged over `&3000`, which was `PARMAN`'s stream at
`DEPK_STREAM`. **Nothing has destroyed the font since**, so it is loaded once and lives for the
session.

It sits between `SetupMode` and `TitleSeq`, and each side is load-bearing: after `SetupMode`
because `VDU 22` clears `&3000-&7FFF`, after `BootBanks` because `PARADAT`'s stream stages from
`&3200` to `&5C0F` straight over it, and before `TitleSeq` because a filing call needs the MOS to
still own the machine. It also makes `PARAFNT` resident for `HsEntry`, which was an invariant no
`ASSERT` could check (`CLAUDE.md` says so) and is now trivially true.

### 18b. …which kills the DFS workspace snapshot, and it had to

`SaveDfsWs` had exactly one call site, in `ts_loads`, and removing it would have left
`RestoreDfsWs` restoring a snapshot nobody took — writing garbage over `&0D60-&0DEF` and
`&0E00-&10FF`. So the whole machinery goes together:

| gone | where it was |
|---|---|
| `SaveDfsWs`, `RestoreDfsWs`, the `DFSWS*` constants | the code image |
| the `RestoreDfsWs` calls | `GoTitle` and `BrDispatch` |
| `dfsSave` | **912 bytes of bank 6** |

The rule they enforced still holds — the low overlay does still bury DFS's workspace and the MOS's
extended vector table, and a filing call made after `PageLowIn` would still crash through them.
**Nothing has to obey it, because nothing makes one.** `UnpackBankIn` and `BootBanks` stay: they
are the boot loads themselves.

### 18c. The ledger

| | at §17 | now |
|---|---|---|
| **filing calls after boot** | 1 | **0** |
| disc files | 8 | 8 |
| disc image | 45,312 | 45,312 |
| main-RAM code image free | 28 | **108** (`code_end` `&2FE4` → `&2F94`) |
| bank 4 | 225 | 225 |
| bank 5 | 88 | 88 |
| bank 6 | 212 | **1,126** |
| bank 7 | 171 | 171 |

**+80 of code image and +914 of bank 6.** §11h estimated the terminal dividend at 241 bytes of
scattered main RAM; the 80 measured here is what it actually yields, because
`UnpackBankIn`/`BootBanks` and the `loadfnt` string all survive — the boot loads still need them.
The 912 in bank 6 is the figure that held up exactly.

### 18d. Verified

Two cold boots on the shipping image in jsbeeb, `B-DFS1.2`:

1. boot → title → **fire → game** → ESCAPE → death → game over → high-score entry → three
   initials → **title again** (through `GoTitle`, now with no `RestoreDfsWs` in front of it) →
   fire → **game again**, which runs `ts_loads` and `PageLowIn` a second time;
2. boot → **title → timeout → briefing**, which is `BrTimeout` RTSing into the font-less
   `ts_loads` — the seam stage 4 changed.

### 18e. What is left on the branch

Step 5 is complete. What §10's list still carries, and §12b restated, is unchanged and none of it
is about loading: **real hardware**, the transfer game's LOSE path, and a systematic walk of all
eight rotor phases and 24 droid types. `docs/no-load.md` §8's rule stands — the emulator half is
the expensive one and it is where every real defect on this branch was found, including both of
§17's.
