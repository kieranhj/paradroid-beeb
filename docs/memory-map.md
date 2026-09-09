# Memory map, as actually built

Every address here comes from a `beebasm -dd -labels` dump of the current build, not from a plan.
Regenerate it after any change that moves a region:

```powershell
./bin/beebasm.exe -i src/main.asm -do paradroid.ssd -boot PARA -dd -labels paradroid.labels
```

`PLAN.md` keeps the one-line summary; this file is the detail behind it.

> **Headline figures below were re-verified against the build on 2026-09-09**, on the `no-load` branch after [`no-load.md`](no-load.md) §19 put `drYcol0/1/2` into zero page — main RAM, the zero page, all four banks and the `PARAFNT` block. Rows carrying an older date in their own text are that row's own last measurement and were left alone. The **internal** layout tables are still older snapshots and several are known to be shifted; regenerate with the command above before trusting a mid-bank address.
> recovery pass** ([`ram-pass.md`](ram-pass.md)). The **internal** layout tables are older
> snapshots and several are known to be shifted — the bank-4 data table below is marked where it
> is wrong; regenerate with the command above before trusting a mid-bank address.

## Main RAM

| Range | Size | Contents |
|---|---|---|
| `&0000–&008F` | 144 B | Zero page — **all of it used**. Breakdown below; the authority is the map in `main.asm` |
| `&0090–&009F` | 16 B | OS zero page, and it stays the OS's |
| `&00A0–&00A8` | 9 B | `drYcol0/1/2` — the first claim on the second half of the zero page (2026-09-09, `no-load.md` §19). Seeded by `SprSeedYcol` from `ts_loads`; not loadable, and not assumed to survive the front end |
| `&00A9–&00E6` | **62 B free** | hexwab's issue #2 answer: ours with no filing call, no `OSWRCH` and no `OSRDCH` in flight, which the `no-load` branch makes true after boot. `&E8–&E9`, `&F2–&F3` and `&F6–&F7` too — 6 B more. `&F4` is `ROMSHAD` and already in use. Measure the range you want with the `beeb-bss-bugs` method before spending it |
| `&0100–&017F` | 128 B | Stack — **and MEASURED FREE, 2026-08-31**. `&A5` seeded with the game running, then play, a deck load, the console and its pages, and the whole game over including `GoTitle`'s `*LOAD`s; all 128 survived, so the stack has never been seen below `&0180`. **The only contiguous main-RAM space left bigger than 16 B.** Nothing is in it yet. Read [`ram-pass.md`](ram-pass.md)'s section first — it lists the paths NOT exercised, and code cannot simply live here because page 1 is not loadable from disc |
| `&0180–&01FF` | 128 B | Stack, the part that is actually used |
| `&0200–&03FF` | 512 B | OS vectors and workspace. We own `IRQ1V` at `&0204` outright |
| `&0400–&0C8F` | 2,192 B | MODE 1 charset, rebuilt at every deck load — reclaimed OS workspace. **Two boot-time tenants get here first:** `PARSWR` leaves the four sideways-bank numbers at `&0A00` (magic `&A5`, then DATA/SPR/SPR2/XFER) for `.start` to copy into `swBank`, and on an intro build `PINTRO` unpacks its advance tables over `&0400–&1BFF`. Both are finished long before the charset is built |
| `&0C90–&0CFF` | 112 B | `lowbss` — the low overlay's state, **full: 0 B free** (`sprCls` took the last 8 on 2026-09-01, and the "`&0CF9–&0CFF` 7 B free" this table used to carry below it went with them). `SKIP`ped, not shipped. **"Everything in it is written before it is read" is only true INSIDE a game**: `disrFlash` is read by `SetPalPlay` from the first title onwards and cost two white-screen bugs (2026-08-28, 2026-08-30). Read `src/lowbss.asm`'s header before adding a byte |
| `&0D00–&0D5F` | 96 B | **NMI handler and its workspace. NOT OURS** — one spurious NMI through a page of somebody else's 6502 would be unrecoverable |
| `&0D60–&0DEC` | 141 B | `lowcode2` — the low overlay's second chunk, in Econet/mouse workspace and the extended vector table. The disruptor's helpers, the collision matrix's two damage arms, `DrCollMode`, `GameStartInfo` |
| `&0DED–&0DEF` | **3 B free** | (2026-09-09; the 6 B quoted here from 2026-08-25 was stale, and the 36 before that) |
| `&0DF0–&0DFF` | 16 B | **The sideways ROMs' private-workspace page bytes. NOT OURS**, and the reason `PageLowIn` copies in two pieces rather than one |
| `&0E00–&10F6` | 759 B | `lowcode` — `DrawTileCells`, the animated-tile scan and repaint, the alert lamp, the `CollisionType` table, `InfoCall`. Staged through `LOW_STAGE` and copied down by `LowResident` **out of bank 6, not off the disc** (2026-09-09): it lands on DFS's own workspace, which used to make it "after the last `*LOAD`" and now makes it vacuous, because there is no load after boot at all |
| `&10F7–&10FF` | **9 B free** | (2026-09-09; the 1 B quoted here from 2026-08-25 was stale — the two raw `PAGEBANK`s in this chunk became `JSR Pg*`) |
| `&1100–&2FA2` | 7,843 B | Code (`PARA`), starting below DFS's `PAGE` of `&1900`. The level draw and droid AI are in bank 4; the RAM recovery pass then moved the effect blitter to bank 5 and pulled the `PAGEBANK`/`PNMIRROR` expansions into subroutines. Also carries the one copy of the droid icon data (`droidicon.asm`), read from banks 6 and 7, and — since 2026-08-29 — the single resident ZX0 depacker with `UnpackBankIn` and `BootBanks` beside it |
| `&2FA3–&2FA8` | 6 B | `keyTab` — the six redefinable controls, as INKEY bytes, in `CTL_*` order. **It is no longer the last six bytes of the image** (that line was true until layer-12 [DECISION 6] put `DECK_DONE` and `DeckDoneClear` behind it); what matters about its home was never that it is last but that it is main RAM, resident at every moment a control is tested — see [`layer-11f-frontend.md`](layer-11f-frontend.md) §8a |
| `&2FA9–&2FC3` | 27 B | `DECK_DONE` (16 B) and `DeckDoneClear`, layer-12 [DECISION 6] |
| `&2FC4–&2FFF` | **60 B free** | `code_end` is `&2FC4`, measured 2026-09-09 — BUGS.md #24 spent 24 and [`no-load.md`](no-load.md) §20 gave 17 back. **It was `&3000` exactly — 0 B — from `b385cd6` until the `no-load` branch**, which gave it back in three pieces: 14 B when no-load step 4 deleted `loadtitl`'s OSCLI and its string, another 14 when `PARBRF` and `PARALOW` stopped being disc files and took theirs, and 38 from step 6's `BrDepackChain`; §19's `JSR SprSeedYcol` then spent 3. The RAM recovery pass of 2026-08-25 ([`ram-pass.md`](ram-pass.md)) had taken this to 639 B; Layer 13b and Layer 11f's `keyTab` spent all of it. **`ram-pass.md`'s reserve list is what pays for the next thing that needs main RAM** — and [`no-load.md`](no-load.md) §19a is the other list now, ~390 B of code image in absolute operands that zero page would shorten |
| `&3000–&367F` | 1,664 B | Layer 9's text font, `PARAFNT` — 104 glyphs × **16 B, 1bpp**, the C64's own bytes, expanded by `FontCell` as it draws. Layer 13a TASK 3. **Loaded once, in `.start`**, since no-load step 5 |
| `&3680–&36DF` | 96 B | The status box's twelve border cells, same file, also 1bpp |
| `&36E0–&3CEC` | 1,549 B | `constrings` — the `$C000` string table, **one copy**, read by the console in bank 6 and the droid database in bank 7 alike. Same `PARAFNT` file. Layer 13a TASK 7 |
| `&3CED–&3DB5` | 201 B | `FontCell`, `fc_left`/`fc_right`, `fontMask`/`fontExpand` — the 1bpp decoder — `DoScore` (`&3D3F`) and `KeyDownIx` (`&3DAF`). Main RAM that does not have to be the code image. Layer 13a TASK 8; addresses re-measured 2026-09-09 |
| `&3DB6–&3DE5` | 48 B | `PN_TABS` — **two** droid tables (`pnTabCent`, `pnTabNum`), mirrored out of bank 4 for banks 6 and 7. The other two mirrors were never read and were deleted (RAM pass 1) |
| `&3DE6–&3DEF` | 10 B | `CN_STRS` — the console's two droid-count strings, five bytes each: up to three ASCII digits, a terminator, and the plural suffix character. Bank 4 writes them, bank 6 draws them; layer-12 [DECISION 5] |
| `&3DF0–&3DFF` | **16 B free** | Was 26 before `CN_STRS`, ~49 before `KeyDownIx`, and 8 when `PN_TABS` was 96 B — `BUGS.md` #18's "check `PN_TABS` first" lesson still applies, with the new sizes |
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

Two more files load after the bank staging, in TitleSeq's order: `PARAFNT` straight to `&3000`,
and `PARALOW` staged on the panel and copied down last. (`PARTITL` was a third until no-load step
4, 2026-09-07: the title's driver still runs at **`&0900`**, in the charset's ground — it moved
off `&3000` in step 3 so the text font survives the title — but its image is carried in bank 7
and `TiResident` copies it down, so there is no load.) — see the boot code and `layer-11-sound-title.md` §11c.

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
| `&A0–&A8` | `drYcol0/1/2` — the digit block's three column tables, read ONLY as `LDY drYcolN,X` by the compiled glyphs. There for the byte, not the cycle: see the note below |

> `LDA abs` is 4 cycles and `LDA zp` is 3 — but `LDA abs,X` and `LDA zp,X` are both 4. Zero page went
> to scalars for that reason; indexed tables gained nothing by moving and are all in main RAM.
>
> **That is a CYCLE rule and it says nothing about bytes.** `abs,X` is three bytes and `zp,X` is two, so an indexed table moved into zero page still saves a byte at every site — which is the whole of why `drYcol0/1/2` moved (749 bytes across banks 5 and 6, `no-load.md` §19). When the binding constraint is space rather than time, count the sites, not the cycles.

## SWRAM bank 4 — `PARADAT`

`&8000–&BFCC`, **51 free** (2026-09-09, after [`no-load.md`](no-load.md) §19's `SprSeedYcol` and its nine-byte `drYcol` seed took 20 — assembled AFTER `colours.asm` on purpose, because in front of `colourMap`'s `ALIGN` it would have rolled a page. It was **71** with the branch's tail full: step 6 put briefing page 5's second chunk (154) there and **the `ALIGN` pad is down to 10 bytes**, so there is no free ride left here either. It was 225 earlier on the branch, after 2026-09-07 interned `drSprData`'s duplicate rotor and end rows for +217; before that 8. **Packing this bank is not possible** — everything in it is read during play, so there is nowhere to depack to, and the disc already ZX0s the whole thing.) The pre-branch reading and its history: `&8000–&BFF4`, **11 free** (2026-08-31: layer-12 [DECISION 5]
took ~105 and BUGS #12's `sprSplit` clear 3, out of the 143 that were there. **`colourMap`'s
`ALIGN` pad is SPENT** — 200 bytes put in front of it cost the bank 259, because past the pad the
ALIGN rolls a whole page; `consolesel.asm`'s header warns of exactly this and it is now measured.
This bank is as tight as the code image. Earlier: 51 free 2026-08-25, after the RAM recovery pass
deleted `drSpeedF`/`drSpeedFHi`
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
`SetCRTCStart` run before this bank is loaded, and `SetCell` and the `rowMul`/`unitMul`
tables are reached while the *sprite* bank is paged in — `SprCalcAddr` calls it. (`WrapBufFwd` was
reached the same way until 2026-09-02, when it was inlined away to a `BPL` and one `SBC`.) A JSR from there into this bank would land in compiled sprite rows,
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

`&8000–&BEA8`, **344 free** (2026-09-09. **It was 15 B and the tightest region in the machine**; [`no-load.md`](no-load.md) §19 moved `drYcol0/1/2` into zero page, turning 320 `LDY drYcol,X` from `abs,X` into `zp,X` and deleting this bank's copy of the table — **+329 for no cycles at all**. It is **UNFOLDED**: §11m sold the SCANSTEP tail fold back (—613), which it could afford because `sprscan.asm` had just gone home to bank 6 and left 538 behind. Those 613 are still recoverable at 3 cycles a compiled row by putting `0` back in `export_droids.py`'s `FOLD_TAIL` — independent of §19, and no longer the first thing to reach for.) The pre-branch reading: `&8000–&BDA5`, **602 free** (2026-08-25; was 1,033 until the RAM pass spent 431 of it). Two of
the four compiled shifts, Layer 7's effect artwork — 31 bullet and explosion frames, 2,946 B,
here because the interpreted effect path reads them every row — **and, since RAM pass 2, the
effect blitter itself** (`src/sprfx.asm`: `SprEfSetup/Box/Skip/Fetch/Draw/Restore`), which only
ever runs with this bank paged in. **Its header's invariant — no effect blit while the briefing's `PARMAN` occupies this bank — is vacuous since no-load step 5**: `PARMAN` is gone, and the briefing's resident half (`briefman.asm`, `sndchat`, `brExtra`, `keyredef` and two page streams) lives here instead of being loaded over it.

## SWRAM bank 6 — `PARSPR2` (shifts 2 and 3 px)

`&8000–&BD35`, **714 free** (2026-09-09, and still the largest hole in the machine. §19's `drYcol` move gave **+420** here — 411 sites plus the table, the extra 91 over bank 5 because only a SHIFTED glyph spills into column 2 and this bank carries the 2 px and 3 px shifts. It was 294: also **UNFOLDED** (§11l), then step 6 took `sprscan.asm` back (—538) and gave up briefing page 5 (+313), and step 5 spent 2,005 on `brfImg` and `lowImg` — the two front-end overlays and their copiers, which is what made `PARBRF` and `PARALOW` resident.) The pre-branch reading: `&8000–&BFF8`, **7 free** (2026-08-31: layer-12 [DECISION 5]'s `ConCount`
lines took 32 of the 39 that were left; the 114 this line quoted from 2026-08-25 was two
generations stale. The RAM pass's icon dedup returned 110 — before it 4,
and the history back through `dfsSave` moving in, `sprsplit.asm` arriving and TASKs 3/6/7 is in
the layer docs). The other two shifts, laid out identically, plus Layer 9's panel engine, HUD and
console. The strings left with TASK 7 and the droid icon data with RAM pass 3b — `console.asm`
now reads `conDrRotor`/`conDrDigits` from **main RAM**.

**Both sprite banks share one layout**: a fixed section of tables at the same addresses in each, then that bank's own code. That is what lets the blitter name one set of labels and read whichever bank is paged; `main.asm` asserts all **nineteen** addresses agree. The addresses below were re-measured 2026-09-09 and are current — they are the same nineteen as before hexwab's issue #1, because §19 took `drYcol0/1/2` back out of the banks again and `drGlyphLo` and `drDigit0` moved back down the 9 bytes it had cost them. The fixed section, common to both:

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

Then the code, whose sizes differ between the banks. **Re-measured 2026-09-09**: bank 5 has `drD0_*` at `&85E8`, `drD1_*` at `&8CC8`, the restore rows and programs, then `drGlyph0_*` at `&998C` and `drGlyph1_*` at `&A072`; bank 6 has `drD2_*` at `&85E8`, `drD3_*` at `&8C4A`, `drGlyph2_*` at `&9872` and `drGlyph3_*` at `&A006`. The `&A178` / `&A8FE` this paragraph quoted were four generations stale.

**What each block is for is in [`layer-5-blitter.md`](layer-5-blitter.md)**, under "What is in the
bank, block by block" — including the division that explains the shape: the compiled fast path
reads none of the artwork, and the wrap fallback is the only thing that does.

## SWRAM bank 7 — `PARXFER`

`&8000–&BF7C`, **131 free, plus 33 B of `plandata.asm`'s `ALIGN` pad** (2026-09-09, after BUGS.md #24's `xfpause.asm` took 35 behind that pad and [`no-load.md`](no-load.md) §20 five more of the title overlay; it was **171**). The pad was 208 until no-load step 6 put briefing page 5's first chunk (175) in it for nothing, exactly as `consolesel.asm` does in bank 4 — **quote a bank's pad and tail as a pair, never the tail alone**. It was 759 before the briefing's `brstream1` (604 packed) went in; the branch's packing pass had taken it from 25 to 3,021 (transfer board, lift screen, portrait pool, `poLut`), and steps 3 and 4 then spent 2,262 of that on the title artwork, the high-score screen, the title overlay's image and `TiResident`. The pre-branch reading and the warning that goes with it: `&8000–&BFF8`, **7 B of tail + the `planInk` `ALIGN` pad — ~100-105 B all in, MEASURED
2026-08-31** by bisecting a `SKIP` in `liftview.asm` (100 assembles, 110 does not). **The
"~176 B of pad, ~183 B real" this line quoted from 2026-08-25 was stale**, and it cost layer-12
DECISION 6 a build to find out — quote the measurement, and re-measure rather than trusting this
line. **Nothing in `ram-pass.md`'s reserve list frees this bank**, which is the finding that
parked that decision: bank 7 carries the transfer game, the lift screen, three console pages and
the game over, and the next squeeze has no candidate here. **Two things in the history below have since been overtaken by the `no-load` branch**: the title is not a `PARTITL` disc overlay at `&3000` any more (step 3 put the artwork in this bank and step 4 the driver's image, and it runs at `&0900`), and the 912-byte `dfsSave` snapshot in bank 6 is gone with the loads it protected (step 5). The history: 826 free on 2026-08-20, spent by Layer 10's
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
| `bufcore.asm` | main RAM | What the level draw could not take into the bank: `SetupMode`/`SetupRupture`, `SetCRTCStart`, `SetCell`, the `rowMul`/`unitMul` tables (`WrapBufFwd` too, until it was inlined away 2026-09-02) |
| `player.asm` | main RAM | `ReadKeys`, `CheckWalls`, `ApplyMove`, `DeadZone`, the clamps |
| `combat.asm` | main RAM | Layer 7a: energy, ceiling, weapon, alert, BCD score, `DoAging`. Main RAM because BOTH banks' code reaches it |
| `sprite.asm` | main RAM | The blitter front end: slot state, the tranche walk, `SprSplitOK`/`SprAssignTr`, the compiled-row dispatch and the wrap fallback |
| `sprfx.asm` | bank 5 | The effect blitter (RAM pass 2) — only ever runs with `PARASPR` paged in; read its header before touching it |
| `data/droidicon.asm` | main RAM | The one copy of the droid icon data, read by bank 6 (`console.asm`) and bank 7 (`xfericon.asm`) — RAM pass 3b |
| `sprsplit.asm` | bank 6 | The tranche decision, reached through `SprSplitOK`'s paging bridge; reads only main RAM and zero page |
| `sprscan.asm` | bank 6 | The tranche PRESCAN, the geometry half of the split decision, feeding `sprCls` in `lowbss`. It was bank 5's from 2026-09-01 until no-load step 6 sent it back |
| `door.asm` | main RAM | Door state, `DoorScan`, the patched tile definitions, `DoorsUpdate`, `DrawDoorTile` |
| `lift.asm` | main RAM | `LiftFind`, lift mode, stepping a shaft, `LiftPlace` |
| `screen.asm` | bank 4 | `DrawHalf`, `BuildCharPtrs`, `BandSetRow`, `ColSetup`, `MapChar`, `RedrawAll` |
| `scroll.asm` | bank 4 | `DrawColumn`, `DrawBandRows`, `CopyCell`, `ScrollAddS`, `DoRedraws` |
| `level.asm` | bank 4 | Deck decompress (`BuildLevel`), `BuildCharset`, `BuildLUTs`, `SetPalette` |
| `zx0depack.asm` | bank 4 | `Zx0Unpack` — the ZX0 (v2) decompressor `BuildLevel` tail-calls; format notes in its header, compressor in `tools/zx0.py` |
| `droid.asm` | bank 4 | The ship roster, waypoints, `DroidsUpdate`, line of sight, collision, the kill chain, `ConMenu4`, and — since 2026-09-09 — `SprSeedYcol`, which copies `drYcol0/1/2` into `&A0`. **Assembled after `colours.asm` on purpose**, so it does not ride in `colourMap`'s `ALIGN` pad and roll it a page |
| `panel.asm` | bank 6 | Layer 9's panel text engine and HUD |
| `console.asm` | bank 6 | The console screen, its strings and icons |
| `xfer.asm` | bank 7 | Layer 10's transfer minigame |
| `liftview.asm` | bank 7 | Layer 8b's deck-selection screen |
| `condeck.asm` | bank 7 | The console's deck plan page |
| `condb.asm` | bank 7 | The console's droid database page |
| `title.asm` | assembled at **`&0900`**, kept in bank 7 | Layer 11's title screen driver plus `HsEntry` — an overlay copied down by `TiResident` at boot and after a game over, buried by the next `BuildCharset`. Not a disc file since no-load step 4. Its artwork is `src/data/title.asm`, also bank 7 (step 3) |
| `highscore.asm` | bank 7 | Layer 11f's high-score entry, everything below `HsEntry` — it moved out of the PARTITL overlay in no-load step 3 and its 1,152-byte alphabet became `hsremap.asm`, 72 bytes of indices into `textfont` |
| `portrait.asm` | bank 7 | `PoDraw` — the 48 × 84 droid portrait, composed from `portraits.asm`'s pool for the database page (Layer 13d) |

`src/data/` is generated by the exporters in `tools/` and is **tracked** (KC, 2026-08-27) —
regenerate it with the tool rather than editing it, and commit what the tool produces.
