# Memory map, as actually built

Every address here comes from a `beebasm -dd -labels` dump of the current build, not from a plan.
Regenerate it after any change that moves a region:

```powershell
./bin/beebasm.exe -i src/main.asm -do PARADROID.SSD -boot PARA -dd -labels PARADROID.labels
```

`PLAN.md` keeps the one-line summary; this file is the detail behind it.

> Headline figures below were re-verified against the build on **2026-08-25, after the RAM
> recovery pass** ([`ram-pass.md`](ram-pass.md)). The **internal** layout tables are older
> snapshots and several are known to be shifted — the bank-4 data table below is marked where it
> is wrong; regenerate with the command above before trusting a mid-bank address.

## Main RAM

| Range | Size | Contents |
|---|---|---|
| `&0000–&008F` | 144 B | Zero page — **all of it used**. Breakdown below; the authority is the map in `main.asm` |
| `&0090–&00FF` | 112 B | OS zero page |
| `&0100–&01FF` | 256 B | Stack |
| `&0200–&03FF` | 512 B | OS vectors and workspace. We own `IRQ1V` at `&0204` outright |
| `&0400–&0C8F` | 2,192 B | MODE 1 charset, rebuilt at every deck load — reclaimed OS workspace. **Two boot-time tenants get here first:** `PARSWR` leaves the four sideways-bank numbers at `&0A00` (magic `&A5`, then DATA/SPR/SPR2/XFER) for `.start` to copy into `swBank`, and on an intro build `PINTRO` unpacks its advance tables over `&0400–&1BFF`. Both are finished long before the charset is built |
| `&0C90–&0CF8` | 105 B | `lowbss` — the low overlay's state. `SKIP`ped, not shipped. **"Everything in it is written before it is read" is only true INSIDE a game**: `disrFlash` is read by `SetPalPlay` from the first title onwards and cost two white-screen bugs (2026-08-28, 2026-08-30). Read `src/lowbss.asm`'s header before adding a byte |
| `&0CF9–&0CFF` | **7 B free** | |
| `&0D00–&0D5F` | 96 B | **NMI handler and its workspace. NOT OURS** — one spurious NMI through a page of somebody else's 6502 would be unrecoverable |
| `&0D60–&0DE9` | 138 B | `lowcode2` — the low overlay's second chunk, in Econet/mouse workspace and the extended vector table. The disruptor's helpers, the collision matrix's two damage arms, `DrCollMode` |
| `&0DEA–&0DEF` | **6 B free** | (2026-08-25; the 36 quoted here before was stale) |
| `&0DF0–&0DFF` | 16 B | **The sideways ROMs' private-workspace page bytes. NOT OURS**, and the reason `PageLowIn` copies in two pieces rather than one |
| `&0E00–&10FE` | 766 B | `lowcode` — `DrawTileCells`, the animated-tile scan and repaint, the alert lamp, the `CollisionType` table. Staged through `LOW_STAGE` and copied down **after the last `*LOAD`**: this is DFS's own workspace while the filing system is running |
| `&10FF` | **1 B free** | (2026-08-25) |
| `&1100–&2FF9` | 7,930 B | Code (`PARA`), starting below DFS's `PAGE` of `&1900`. The level draw and droid AI are in bank 4; the RAM recovery pass then moved the effect blitter to bank 5, the boot loop to `PARDEPK` and pulled the `PAGEBANK`/`PNMIRROR` expansions into subroutines. Also carries the one copy of the droid icon data (`droidicon.asm`), read from banks 6 and 7 |
| `&2FFA–&2FFF` | 6 B | `keyTab` — the six redefinable controls, as INKEY bytes, in `CTL_*` order. **The last six bytes of the image, and the only main-RAM home that is resident at every moment a control is tested** — see [`layer-11f-frontend.md`](layer-11f-frontend.md) §8a |
| — | **0 B free** | `code_end` is `&3000` exactly. The RAM recovery pass of 2026-08-25 ([`ram-pass.md`](ram-pass.md)) had taken this to 639 B; Layer 13b and Layer 11f's `keyTab` spent all of it. **`ram-pass.md`'s reserve list is what pays for the next thing that needs main RAM** |
| `&3000–&366F` | 1,648 B | Layer 9's text font, `PARAFNT` — 103 glyphs × **16 B, 1bpp**, the C64's own bytes, expanded by `FontCell` as it draws. Layer 13a TASK 3 |
| `&3670–&36CF` | 96 B | The status box's twelve border cells, same file, also 1bpp |
| `&36D0–&3CD5` | 1,542 B | `constrings` — the `$C000` string table, **one copy**, read by the console in bank 6 and the droid database in bank 7 alike. Same `PARAFNT` file. Layer 13a TASK 7 |
| `&3CED–&3DB5` | 201 B | `FontCell`, `fontExpand`, `fontMask` — the 1bpp decoder — `DoScore` (2026-08-20) and `KeyDownIx` (2026-08-30). Main RAM that does not have to be the code image. Layer 13a TASK 8; take the exact addresses from the symbol dump, this row has been stale before |
| `&3DB6–&3DE5` | 48 B | `PN_TABS` — **two** droid tables (`pnTabCent`, `pnTabNum`), mirrored out of bank 4 for banks 6 and 7. The other two mirrors were never read and were deleted (RAM pass 1) |
| `&3DE6–&3DFF` | **26 B free** | Was ~49 before `KeyDownIx`, and 8 when `PN_TABS` was 96 B — `BUGS.md` #18's "check `PN_TABS` first" lesson still applies, with the new sizes |
| `&3E00–&45FF` | 2,048 B | Sprite background save areas, 8 slots × 256 — slot 7 (`&4500`) is the player's bullet. Ends exactly at the tile map. **Doubles as `UnpackChars`' depack scratch** (Layer 11e): the 1,352 B of char bitmaps + `charRemap` land here at `LoadDeck`, boot and the GoTitle rebuild — dead space at all three moments because every slot is re-dealt before anything restores |
| `&4600–&49FF` | 1,024 B | Tile map, 64 × 16, page-aligned, fixed home. Ends exactly at the panel |

> **Why the three moved, 2026-08-18.** Layer 11's title screen is 25 rows × 640 = **16,000
> contiguous bytes**, and it fits because the title's buffers and the game's never coexist: at title
> time no deck is loaded, so the save areas, the tile map, the panel and the play buffer are all
> idle. The only thing standing in the middle of `&3000`–`&7FFF` was `PARAFNT`, so it went to the
> bottom and the other two moved up behind it. The three now pack exactly onto `PANEL_ADDR`
> (3,584 + 2,048 + 1,024 = 6,656 = `&3000` to `&4A00`), the framebuffer takes `&4000`–`&7E7F`, and
> the font sits **below** it — one home, no second load. Nothing depended on the old addresses: the
> blitter builds its save pointer at runtime from `HI(SPR_SAVE)` and stores through `(svp),Y`, and
> `mapRowLo`/`mapRowHi` are assembled from `tilemap + r * MAP_COLS`. See
> [`layer-11-sound-title.md`](layer-11-sound-title.md) §4, [DECISION 1].
| `&4A00–&53FF` | 2,560 B | Panel — 4 rows × 640, displayed by rupture cycle 1 |
| `&5400–&54BF` | 192 B | `rowMul`/`unitMul` — the row and unit offset tables, built at startup by `BuildMulTabs`. Moved out of the code image by Layer 13a, TASK 6 |
| `&54C0–&54FF` | 64 B | `LUTs` — `BuildCharset`'s four nibble tables, evicted from bank 4 on 2026-08-20 to make room for the collision matrix. It was the 64 free bytes `PnClear` used to wipe |
| `&5500–&55FF` | 256 B | `CHAR_PTR_LO` — character code → charset address, built at startup |
| `&5600–&56FF` | 256 B | `CHAR_PTR_HI` |
| `&5700–&57FF` | 256 B | `SPR_MASKTAB` — data byte → transparency mask, built at startup |
| `&5800–&7FFF` | 10,240 B | Play buffer: circular strip, 16 rows × 640, inside a 10K hardware wrap |
| `&8000–&BFFF` | 16 K | Sideways bank window — one of the FOUR banks below, never more |
| `&C000–&FFFF` | 16 K | MOS |

Free main RAM (2026-08-30): **0 B below `&3000`** — `code_end` is `&3000` exactly — 26 in the
`PARAFNT` tail, 1 at the top of `lowcode`, 6 in `lowcode2`, 8 after `lowbss`: about 40 B in four
pieces, none of them the one that matters. The 639 B this line quoted after the 2026-08-25
recovery pass went to Layer 13b's bank probe and Layer 11f's `keyTab`.
The seam code (`TitleSeq`, `GoTitle`, `UninstallIrq`, `SaveDfsWs`/`RestoreDfsWs`) stays resident
of necessity, because it pages banks and runs while the MOS owns the machine.

**The 1,136 free bytes at `&0C90` are gone**, spent on the low overlay, and with them the 64 above
the panel (`LUTs`) and 112 of the `PARAFNT` tail (`DoScore`). What made that possible is that
`&0E00–&10FF` is DFS's shared workspace and dead from the last `*LOAD` on — but **nothing may be
LOADED there**, which is why `PARALOW` is staged at `LOW_STAGE` and copied down, and why it must be
the last filing-system call in the boot sequence. Do it earlier and the next `*LOAD` hangs in the
8271 poll with the ROM's variables underneath it.

**Layer 11e's sound driver landed in bank 4, not here** — the IRQ pages the bank for `SndTick`
(the one sanctioned breach of the bank rule, `CLAUDE.md`), so main RAM paid only the request
bytes and the shim. Since the RAM recovery pass the reservoir IS the code image's 639 B;
the further reserves (`sprsplit.asm` to bank 5, SCANSTEP tail folding, `door.asm` to bank 4)
are costed in [`ram-pass.md`](ram-pass.md) §"Held in reserve".

### The boot-time staging overlay

`*LOAD` stages both banks at `DATA_LOAD` = `&3000` and the copy-up runs from there, because the MOS
has the DFS ROM paged in at `&8000` during a filing-system call. So:

All four bank files stage there in turn — since the loader compression they land ZX0-packed at
`DEPK_STREAM` = `&3200` and unpack straight into the bank, driven by the **`PARDEPK` overlay at
`&3000`**, which since RAM pass 3a also carries `UnpackBankIn`, the boot's `BootBanks` loop and
three of the load strings (`loaddepk` and `loadspr` stay in main RAM: the briefing exit OSCLIs
both). Everything in the overlay runs only while it is resident.

Everything from `&3000` up through the staged streams is written through during boot — the save
areas, the tile
map, the font region, the panel and the bottom of the play buffer. That is why boot shows a moment
of garbage in the play area.

**The rule this imposes:** anything living in that span must be *built at runtime after*
`PageDataIn`, never loaded with the code. The tile map, the panel, `CHAR_PTR` and `SPR_MASKTAB` all
already satisfy it.

Three more files load after the bank staging, in TitleSeq's order: `PARTITL` straight to `&3000`
(the title, run in place and then buried), `PARAFNT` straight to `&3000` over it, and `PARALOW`
staged on the panel and copied down last — see the boot code and `layer-11-sound-title.md` §11c.

### Zero page, by group

| Range | Contents |
|---|---|
| `&00–&0F` | Level-draw and scroll scratch — `subRowOfs`, `tileCol`, `DrawColumn` and `DrawBandRows` state, `colFirst`/`colCount`, `sDelta` |
| `&10–&1F` | Blitter working set — `sprSlot`, `sprIter`, `sprNoWrap`, `sprShiftW`, `sprGlyphBase`, `sprDigit`, `sprDig`, `sfrCarry` |
| `&20–&26` | Rupture and CRTC state — `ruptState`, `drawFlag`, `crtcHi`/`crtcLo`, `line`, `pline`, `iline` |
| `&27–&3F` | View and player — `posX`, `posY`, `plyX`, `xSpd`, `ySpd`, `cwU`, `plyCX`/`plyCY`, `dzSx`, `dzD`, `oldHX`, `plyXf` |
| `&40–&4F` | `rowq` — the digit block's eight rows in the save area |
| `&50–&5F` | `rowp` — the same eight rows in the play buffer |
| `&60–&6F` | `ApplyMove`/`CalcAxis` scratch, `sprScan`, `pgCount`, `swSrc`/`swDst`, `psrc`, `svp` |
| `&70–&8F` | Pointers and viewport — `bufp`, `chp`, `tdp`, `src`, `mapptr`, `scrollS`, `mapHX`, `mapYr`, `cellX`/`cellY`, `deck`, counters |

> `LDA abs` is 4 cycles and `LDA zp` is 3 — but `LDA abs,X` and `LDA zp,X` are both 4. Zero page went
> to scalars for that reason; indexed tables gained nothing by moving and are all in main RAM.

## SWRAM bank 4 — `PARADAT`

`&8000–&BFCC`, **51 free** (2026-08-25, after the RAM recovery pass deleted `drSpeedF`/`drSpeedFHi`
— 48 B nothing read; before that 3, after Layer 15's endgame spent the space pass's 105 and DECISION 6's cleared-deck fix took the rest — the
deck and ship payouts, the `shipClear` flag, the `GameStart`/`EnterShip4` split, and `DEBUG_DECK`'s
69-byte arm moved in from main RAM. The space pass itself — see §"Layer 15 space pass" below.
Before it, 8. It was 3 on 2026-08-21, layer-11e stage 3, when this was THE FULLEST REGION IN THE MACHINE:
the sound driver (908 B), its data, the trigger posts, `SndAmbient` and the hum tables took
Layer 13d's 1,161 and every squeeze after it. Paid by ZX0-packing the char bitmaps AND
`charRemap` into one stream (`UnpackChars` → the sprite save areas; `lampSrc` caches the ALERT
lamp's 8 bytes for live re-colours), nibble-packing `charSlot`, quartering the sound frequency
table and rewriting the driver's flush. `main.asm` PRINTs this bank's fuel gauge on every
build — trust that over this line.)
Layer 13d's own note: `leveldata`'s
3,503 RLE bytes became `deckPack`'s 2,183 plus a ~230-byte depacker, and the RLE decoder left
`BuildLevel` — see [`layer-13d-space.md`](layer-13d-space.md) §3). Before that it was 12 free — and 111 of its apparent alignment holes are not real, see Layer 13a TASK 5. 2026-08-20 took `LUTs` (64 B) out to `&54C0` and `drVis`/`drVisNew`/`drBulFrm` (42 B) out to `&0C90`, and spent all of it and more on `DrCollPair`, the collision matrix and `DrCollAct`. Tiles, decks, palettes, droid game
data — and the code that reads them: the level draw (2026-08-14), the droid AI (2026-08-15),
Layer 7's combat and kill chain, Layers 10 and 8b's entry/exit shims, `CalcAxis`/`CalcSpeed`, and
the console menu and page shims. This bank is the resting state of the latch, so a call into it
from the main loop needs no paging at all.

**The table below is a 2026-08-17-era snapshot and everything from `charRemap` down is shifted
512 B LOW of where it now sits** (audited 2026-08-25: `colourMap` is at `&8500`, `tiledefs` at
`&8600` — the shift ran through the whole tail). Sizes and order are still right except where
marked; regenerate before trusting any address in it.

| Address | Size | Contents |
|---|---|---|
| `&8000` | 1,096 | `charSrc` — C64 character bitmaps |
| `&8448` | 184 | `charSlot` |
| `&8500` | 256 | `charRemap` |
| `&8600` | 96 | `schemes` — colour schemes |
| `&8660` | 16 | `deckScheme` |
| `&8670` | 144 | `deckPalette` |
| `&8700` | 256 | `colourMap` |
| `&8800` | 512 | `tiledefs` — 16-byte tile definitions |
| `&8A00` | 16 | Per-deck metadata: `deckPackLo`/`Hi` (offsets into `deckPack`) and `deckDroids`. **The other seven C64 tables were dropped by Layer 15's space pass** — 112 B, none of them read anywhere in `src/` |
| — | 2,183 | `deckPack` — the 16 deck maps, decoded offline and ZX0-compressed; `Zx0Unpack` rebuilds the tile map straight from them. Replaced `leveldata`'s 3,207 B of RLE (Layer 13d) |
| `&9787` | 1,743 | `drSprData` — the droid artwork, 249 rows × 7 bytes. Moved here 2026-08-14: only `SprFetchRow` reads it, and the sprite bank is the scarce one |
| `&9E56` | 336 | `drOfsLo`/`Hi` — offset into `drSprData` per (phase, row) |
| `&9FA6` | 72 | `drSpeed`, `wpCount`, `wpOfsLo`/`Hi` — `drSpeedF`/`drSpeedFHi` (48 B, never read) were deleted by RAM pass 1 |
| `&A01E` | 717 | `wpData` — 239 waypoint records |
| `&A2EB` | 16 | `deckDroidBase` |
| `&A2FB` | 112 | `doorDef` — patched tile definitions for open doors |
| `&A36B` | 64 | `blankTileRow` |
| `&A3AB` | 2,437 | **Code**: `screen.asm`, `scroll.asm`, `level.asm` — `DrawHalf`, `HalfPtr`, `BandSetRow`, `BandCharPtr`, `ColSetup`, `MapChar`, `RedrawAll`, `BuildCharPtrs`, `DrawColumn`, `DrawBandRows`, `DoRedraws`, `BuildLevel`, `BuildCharset`, `BuildLUTs`, `SetPalette` |

What could **not** come with it is in `src/bufcore.asm`, 480 bytes in main RAM: `SetupMode`/`SetupRupture` and
`SetCRTCStart` run before this bank is loaded, and `WrapBufFwd`, `SetCell` and the `rowMul`/`unitMul`
tables are reached while the *sprite* bank is paged in — `SprScanRow` tail-calls the first and
`SprCalcAddr` calls the second. A JSR from there into this bank would land in compiled sprite rows,
and nothing would diagnose it.

### Layer 15 space pass — bank 4, 8 B → 105 B free (2026-08-24)

One saving, one cost, measured off the build's own fuel gauge either side of the change.

| | bytes |
|---|---|
| `deckOffsetLo`/`Hi`, `deckY`, `deckX`, `deckHeight`, `deckWidth`, `deckColour` deleted | **+112** |
| `sound.asm`'s new conditional page pad (that build's instance; **0 B in the current build** — it moves with any bank-4 edit) | −15 |
| **net on the gauge, that build** | **+97** |

**What went.** `export_bbc.py` emitted all eight of the C64's per-deck tables from `$F120`, 16 bytes
each, plus the two `deckOffset` tables that indexed the RLE stream. **Only `deckDroids` has a reader
in the port**, and that was confirmed by word-boundary grep over the whole of `src/` and `tools/`
before anything was touched:

- `deckOffsetLo`/`Hi` indexed `leveldata`, which **Layer 13d deleted** when the decks became ZX0
  streams (`deckPackLo`/`Hi` replaced them). Dead since 2026-08-20.
- `deckY`/`deckX`/`deckHeight`/`deckWidth` are the deck-plan geometry. Bank 7 has its **own copy**
  (`sideview.asm`'s `svDeckY`/`svDeckX`/`svDeckH`/`svDeckW`) because only one bank is visible at a
  time — bank 4's copy could never have been the one the plan page read.
- `deckColour` predates `colours.asm`'s per-deck scheme table.

`src/data/` is generated, so the change is in `tools/export_bbc.py`; re-emitting any of them is a
one-line change, and the exporter carries a comment saying so. **Regenerating needs
`python tools/export_bbc.py` — `build.ps1` does not run the exporters.** The run was checked to
leave `chardata.asm`, `colours.asm`, `tiledefs.asm` and `plandata.asm` byte-identical.

**Why the 15 bytes came back out.** Deleting 112 bytes upstream shifted everything after it and
broke `sound.asm`'s `ASSERT HI(snFreqLo) == HI(snPhase+1)` — the 38-byte voice-state block must not
cross a page, because `SndCopy`'s stride-2 self-modified store steps the low byte only. That assert
was unpadded, so **any** bank-4 edit of the wrong size could break it, and this one did. The block
now carries a conditional pad in front of it:

```
IF HI(P%) <> HI(P% + 37)
  SKIP 256 - (P% AND 255)
ENDIF
```

At most 37 bytes, often none, and self-healing across future bank-4 edits. It cost 15 in that
build and costs **0 in the current one** (the RAM pass's 48-byte deletion moved it again).
**A future bank-4 change can move that cost up or down by up to 37 bytes with nothing else
changing** — read the gauge, do not infer it.

**`colourMap`'s alignment padding is unchanged at 17 B** (`deckTextPal + 64` = `&84EF`,
`colourMap` = `&8500`), because the deletion happens in `levels.asm`, which is **after** that
`ALIGN`. Total bank-4 headroom is now **68 B**: 51 on the gauge (post-RAM-pass) plus 17 of pad
that anything assembled before `colourMap` rides in for nothing.

The instruction-stream check on the space pass: 22,954 instructions reduced to (mnemonic,
addressing class) and diffed against the pre-change listing, zero differences — pure data removal
plus padding. **On `DEBUG_KILL`**: turning it off would return its ~45 B of code, but that code
rides in `colourMap`'s `ALIGN` pad, so switching it off grows the *pad*, not the gauge —
`layer-14-visual.md` has the correct reading; an earlier note here claiming "45 B of padding
available" misread it.

## SWRAM bank 5 — `PARASPR` (shifts 0 and 1 px)

`&8000–&BDA5`, **602 free** (2026-08-25; was 1,033 until the RAM pass spent 431 of it). Two of
the four compiled shifts, Layer 7's effect artwork — 31 bullet and explosion frames, 2,946 B,
here because the interpreted effect path reads them every row — **and, since RAM pass 2, the
effect blitter itself** (`src/sprfx.asm`: `SprEfSetup/Box/Skip/Fetch/Draw/Restore`), which only
ever runs with this bank paged in. Its header carries the invariant: no effect blit while the
briefing's `PARMAN` occupies this bank.

## SWRAM bank 6 — `PARSPR2` (shifts 2 and 3 px)

`&8000–&BF8D`, **114 free** (2026-08-25; the RAM pass's icon dedup returned 110 — before it 4,
and the history back through `dfsSave` moving in, `sprsplit.asm` arriving and TASKs 3/6/7 is in
the layer docs). The other two shifts, laid out identically, plus Layer 9's panel engine, HUD and
console. The strings left with TASK 7 and the droid icon data with RAM pass 3b — `console.asm`
now reads `conDrRotor`/`conDrDigits` from **main RAM**.

**Both sprite banks share one layout**: a fixed section of tables at the same addresses in each,
then that bank's own code. That is what lets the blitter name one set of labels and read whichever
bank is paged; `main.asm` asserts all nineteen addresses agree. The fixed section, common to both:

| Address | Size | Contents |
|---|---|---|
| `&8000` | 8 | `drMulRows` — phase × 21 |
| `&8008` | 48 | `drDigitLo`/`Hi` — each type's digit rows in `drSprData` |
| `&8038` | 320 | `drSeqLo`/`Hi` — draw sequence, this bank's two shifts |
| `&8178` | 320 | `drRSeqLo`/`Hi` — restore sequence |
| `&82B8` | 640 | `drPrgLo`/`Hi`, `drRPrgLo`/`Hi` — program entry addresses |
| `&8538` | 29 | `drSeqIdx`, `drMul10` — fallback row → sequence position, phase × 10 |
| `&8555` | 35 | `drBlkSave6` — the digit block's column 6 save. Code, but in the fixed section because it is called by name |
| `&8578` | 40 | `drGlyphLo`/`Hi` — glyph dispatch |
| `&85A0` | 72 | `drDigit0`/`1`/`2` — per-type digits |

Then the code, whose sizes differ between the banks — in bank 5, `drD0_*` at `&85E8` (1,954),
`drD1_*` at `&8D8A`, the restore rows, halves and programs, then `drGlyph0_*` at `&A178` (1,926) and
`drGlyph1_*` at `&A8FE` (1,880). Bank 6 has the same shape for 2 and 3 px.

**What each block is for is in [`layer-5-blitter.md`](layer-5-blitter.md)**, under "What is in the
bank, block by block" — including the division that explains the shape: the compiled fast path
reads none of the artwork, and the wrap fallback is the only thing that does.

## SWRAM bank 7 — `PARXFER`

`&8000–&BFF8`, **7 B of tail + ~176 B of `planInk` `ALIGN` pad, ~183 B real** (2026-08-25 —
quote the pair, never the tail alone). The history: 826 free on 2026-08-20, spent by Layer 10's
tuning and DECISION 14, then the RAM pass's icon dedup grew the pad by 110. 2026-08-20 took the title
OUT (1,345 B — it is the `PARTITL` disc overlay at `&3000` again, [DECISION 6] restored) and spent
the room on what it was freed for: **the droid portrait** — `portraits.asm` (the 63-image pool,
the per-type index and the multicolour→MODE 1 tables, 5,240 B) and `portrait.asm` (`PoDraw`,
~530 B), with `droidicon7.asm` and the rotor-and-digits stand-in deleted against it. The `dfsSave` snapshot lives in bank 6, not here: 912 B of
`&0D60`–`&0DEF` + `&0E00`–`&10FF`, captured by `SaveDfsWs` after TitleSeq's last `*LOAD` and put
back by `RestoreDfsWs` for the game-over loads — without it the first filing call after
`PageLowIn` jumps through the low overlay's bytes where DFS's workspace and the MOS's extended
vector table used to be. Layer 10's transfer game and
Layer 8b's lift screen, sharing the shadow screen/colour RAM, the glyph page and the renderer
pattern; plus both glyph sets, the console's ship page, the deck plan (`condeck.asm`,
`plandata.asm`), and the droid database (`condb.asm`, `droidinfo.asm`). The droid icon it draws
is **main RAM's one copy** (`droidicon.asm`, RAM pass 3b) — the second copy this bank used to
carry is gone for good. The internal layout is in
[`layer-10-transfer.md`](layer-10-transfer.md) and [`layer-9-hud.md`](layer-9-hud.md) §6e–6f.

## Two things this map says that the summaries do not

**The constraint was code space, and moving code fixed it — repeatedly.** "Main RAM is full"
always meant "the `PARA` image cannot grow past `&3000`" — never that there was no RAM. Since a
bank can hold code as easily as data, the level draw went to live beside the tile and deck data it
reads, and `droid.asm` after it. Layers 7–10 then spent the room again, each paying its way in by
moving something else across. The RAM recovery pass (2026-08-25) is the largest application of
the same rule — `&3000` is 639 bytes away now, and displacing code into a bank remains the
standing answer when the room runs out again ([`ram-pass.md`](ram-pass.md) §"Held in reserve").

The free regions under the staging overlay cannot hold anything loaded *with the code*: they take
only what is built at runtime (`CHAR_PTR`, `SPR_MASKTAB`, the tile map, the panel) or `*LOAD`ed
after the bank copies, which is what `PARAFNT` is.

## Source layout — which file lands where

Moved here from `PLAN.md`, 2026-08-19. `CLAUDE.md` has the prose version and the rule that makes
the bank-4 files safe; this is the per-file table.

Single-pass flat build, everything included from `main.asm`. No linker. **Everything in `src/` is
in the build** — the five inherited HAL-era files that were not have been deleted (see
`docs/decisions.md`). Files assemble into main RAM or into a bank, as marked; the one-way rule
that makes the bank-4 files safe is in `bufcore.asm`'s header.

| File | Where | Contents |
|---|---|---|
| `main.asm` | main RAM | Constants, the zero page map, memory map, main loop and its two windows, IRQ dispatch. Geometry constants live here because beebasm resolves them in file order |
| `rupture.asm` | main RAM | Three-cycle vertical rupture, the T1 state machine, `FillPanel`, `DbgSetBg` |
| `bufcore.asm` | main RAM | What the level draw could not take into the bank: `SetupMode`/`SetupRupture`, `SetCRTCStart`, `WrapBufFwd`, `SetCell`, the `rowMul`/`unitMul` tables |
| `player.asm` | main RAM | `ReadKeys`, `CheckWalls`, `ApplyMove`, `DeadZone`, the clamps |
| `combat.asm` | main RAM | Layer 7a: energy, ceiling, weapon, alert, BCD score, `DoAging`. Main RAM because BOTH banks' code reaches it |
| `sprite.asm` | main RAM | The blitter front end: slot state, the tranche walk, `SprSplitOK`/`SprAssignTr`, the compiled-row dispatch and the wrap fallback |
| `sprfx.asm` | bank 5 | The effect blitter (RAM pass 2) — only ever runs with `PARASPR` paged in; read its header before touching it |
| `data/droidicon.asm` | main RAM | The one copy of the droid icon data, read by bank 6 (`console.asm`) and bank 7 (`xfericon.asm`) — RAM pass 3b |
| `sprsplit.asm` | bank 6 | The tranche decision, reached through `SprSplitOK`'s paging bridge; reads only main RAM and zero page |
| `door.asm` | main RAM | Door state, `DoorScan`, the patched tile definitions, `DoorsUpdate`, `DrawDoorTile` |
| `lift.asm` | main RAM | `LiftFind`, lift mode, stepping a shaft, `LiftPlace` |
| `screen.asm` | bank 4 | `DrawHalf`, `BuildCharPtrs`, `BandSetRow`, `ColSetup`, `MapChar`, `RedrawAll` |
| `scroll.asm` | bank 4 | `DrawColumn`, `DrawBandRows`, `CopyCell`, `ScrollAddS`, `DoRedraws` |
| `level.asm` | bank 4 | Deck decompress (`BuildLevel`), `BuildCharset`, `BuildLUTs`, `SetPalette` |
| `zx0depack.asm` | bank 4 | `Zx0Unpack` — the ZX0 (v2) decompressor `BuildLevel` tail-calls; format notes in its header, compressor in `tools/zx0.py` |
| `droid.asm` | bank 4 | The ship roster, waypoints, `DroidsUpdate`, line of sight, collision, the kill chain, `ConMenu4` |
| `panel.asm` | bank 6 | Layer 9's panel text engine and HUD |
| `console.asm` | bank 6 | The console screen, its strings and icons |
| `xfer.asm` | bank 7 | Layer 10's transfer minigame |
| `liftview.asm` | bank 7 | Layer 8b's deck-selection screen |
| `condeck.asm` | bank 7 | The console's deck plan page |
| `condb.asm` | bank 7 | The console's droid database page |
| `title.asm` | `PARTITL` at `&3000` | Layer 11's title screen — a disc overlay, loaded by `TitleSeq` at boot and after a game over, destroyed by `PARAFNT`'s reload |
| `portrait.asm` | bank 7 | `PoDraw` — the 48 × 84 droid portrait, composed from `portraits.asm`'s pool for the database page (Layer 13d) |

`src/data/` is generated by the exporters in `tools/` and is **tracked** (KC, 2026-08-27) —
regenerate it with the tool rather than editing it, and commit what the tool produces.
