# Memory map, as actually built

Every address here comes from a `beebasm -dd -labels` dump of the current build, not from a plan.
Regenerate it after any change that moves a region:

```powershell
./bin/beebasm.exe -i src/main.asm -do PARADROID.SSD -boot PARA -dd -labels PARADROID.labels
```

`PLAN.md` keeps the one-line summary; this file is the detail behind it.

> Headline figures below were re-verified against the build on **2026-08-17** (after the droid
> database landed). The **internal** layout tables for bank 4 and the sprite banks are older
> snapshots — the data blocks at the front of bank 4 have not moved, but its code tail has grown
> through Layers 7–10 and the shims; regenerate with the command above before trusting a
> mid-bank address.

## Main RAM

| Range | Size | Contents |
|---|---|---|
| `&0000–&008F` | 144 B | Zero page — **all of it used**. Breakdown below; the authority is the map in `main.asm` |
| `&0090–&00FF` | 112 B | OS zero page |
| `&0100–&01FF` | 256 B | Stack |
| `&0200–&03FF` | 512 B | OS vectors and workspace. We own `IRQ1V` at `&0204` outright |
| `&0400–&0C8F` | 2,192 B | MODE 1 charset, rebuilt at every deck load — reclaimed OS workspace |
| `&0C90–&0CF8` | 105 B | `lowbss` — the low overlay's state. `SKIP`ped, not shipped: everything in it is written before it is read |
| `&0CF9–&0CFF` | **7 B free** | |
| `&0D00–&0D5F` | 96 B | **NMI handler and its workspace. NOT OURS** — one spurious NMI through a page of somebody else's 6502 would be unrecoverable |
| `&0D60–&0DCB` | 108 B | `lowcode2` — the low overlay's second chunk, in Econet/mouse workspace and the extended vector table. The disruptor's helpers, the collision matrix's two damage arms, `DrCollMode` |
| `&0DCC–&0DEF` | **36 B free** | |
| `&0DF0–&0DFF` | 16 B | **The sideways ROMs' private-workspace page bytes. NOT OURS**, and the reason `PageLowIn` copies in two pieces rather than one |
| `&0E00–&10F1` | 753 B | `lowcode` — `DrawTileCells`, the animated-tile scan and repaint, the alert lamp, the `CollisionType` table. Staged through `LOW_STAGE` and copied down **after the last `*LOAD`**: this is DFS's own workspace while the filing system is running |
| `&10F2–&10FF` | **15 B free** | |
| `&1100–&2F6C` | 7,789 B | Code (`PARA`), starting below DFS's `PAGE` of `&1900`. The level draw and droid AI are in bank 4; Layers 7–10's main-RAM halves refilled the room they made |
| `&2FCA–&2FFF` | **54 B free** | The binding constraint, and the region Layer 11e's sound driver must live in because the IRQ reads no bank. It was 24, then 30, then 148. TASK 6 moved 192 bytes of `rowMul`/`unitMul` out to `&5400`; TASK 3 spent 82 of that on `FontCell` and TASK 8 moved those 82 into the font region. The sprite colour work then spent 94: `SprSetColour`, `sprColPat`, `sprColour` and the player's colour arms in `SprAnimateAll`, all of which have to be resident because the blitter calls them with a sprite bank paged in |
| `&3000–&366F` | 1,648 B | Layer 9's text font, `PARAFNT` — 103 glyphs × **16 B, 1bpp**, the C64's own bytes, expanded by `FontCell` as it draws. Layer 13a TASK 3 |
| `&3670–&36CF` | 96 B | The status box's twelve border cells, same file, also 1bpp |
| `&36D0–&3CD5` | 1,542 B | `constrings` — the `$C000` string table, **one copy**, read by the console in bank 6 and the droid database in bank 7 alike. Same `PARAFNT` file. Layer 13a TASK 7 |
| `&3CD6–&3D97` | 194 B | `FontCell`, `fontExpand`, `fontMask` — the 1bpp decoder — and, since 2026-08-20, `DoScore`. Main RAM that does not have to be the code image. Layer 13a TASK 8 |
| `&3D98–&3DF7` | 96 B | The four droid tables, mirrored out of bank 4 for the panel in bank 6 |
| `&3DF8–&3DFF` | **8 B free** | What is left of the room TASK 3 freed, after `DoScore` |
| `&3E00–&45FF` | 2,048 B | Sprite background save areas, 8 slots × 256 — slot 7 (`&4500`) is the player's bullet. Ends exactly at the tile map |
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

Free main RAM totals **77 bytes** (2026-08-20), in five pieces: 11 below `&3000`, 15 at the top of
`lowcode`, 36 in `lowcode2`, 7 in `lowbss` and 8 in the `PARAFNT` tail. **This is the tightest the
port has ever been**, and the reason is the disruptor: 245 bytes of new main-RAM code against a
code image with 90 free.

**The 1,136 free bytes at `&0C90` are gone**, spent on the low overlay, and with them the 64 above
the panel (`LUTs`) and 112 of the `PARAFNT` tail (`DoScore`). What made that possible is that
`&0E00–&10FF` is DFS's shared workspace and dead from the last `*LOAD` on — but **nothing may be
LOADED there**, which is why `PARALOW` is staged at `LOW_STAGE` and copied down, and why it must be
the last filing-system call in the boot sequence. Do it earlier and the next `*LOAD` hangs in the
8271 poll with the ROM's variables underneath it.

**Layer 11e's sound driver has to be resident and there are 77 bytes.** The reservoirs left are:
`&0D60`'s 36 and `lowcode`'s 15 (both already main RAM, no work); bank 4's 12; and evicting more
`SKIP`ped state from bank 4 into `lowbss` — `drState`, `drShipIdx` and `drFireDelay` are 14 bytes
each and cost nothing to move. Beyond that it means moving a real routine into bank 6 or 7, which
the paging rule mostly forbids.

### The boot-time staging overlay

`*LOAD` stages both banks at `DATA_LOAD` = `&3000` and the copy-up runs from there, because the MOS
has the DFS ROM paged in at `&8000` during a filing-system call. So:

All four bank files stage there in turn — `PARADAT` (to `&6ED9`), `PARASPR` (`&6BF6`),
`PARSPR2` (`&6FC5`) and `PARXFER` (`&67E5`), at their 2026-08-17 sizes.

Everything from `&3000` to about `&6FC5` is written through during boot — the save areas, the tile
map, the font region, the panel and the bottom of the play buffer. That is why boot shows a moment
of garbage in the play area.

**The rule this imposes:** anything living in that span must be *built at runtime after*
`PageDataIn`, never loaded with the code. The tile map, the panel, `CHAR_PTR` and `SPR_MASKTAB` all
already satisfy it.

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

`&8000–&BFF3`, **12 free** (2026-08-20) — and 111 of its apparent alignment holes are not real, see Layer 13a TASK 5. 2026-08-20 took `LUTs` (64 B) out to `&54C0` and `drVis`/`drVisNew`/`drBulFrm` (42 B) out to `&0C90`, and spent all of it and more on `DrCollPair`, the collision matrix and `DrCollAct`. Tiles, decks, palettes, droid game
data — and the code that reads them: the level draw (2026-08-14), the droid AI (2026-08-15),
Layer 7's combat and kill chain, Layers 10 and 8b's entry/exit shims, `CalcAxis`/`CalcSpeed`, and
the console menu and page shims. This bank is the resting state of the latch, so a call into it
from the main loop needs no paging at all.

The data blocks below are still where the table says; the code tail from `&A3AB` has grown well
past the 2,437 bytes recorded — regenerate before trusting a code address.

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
| `&8A00` | 128 | Per-deck metadata: `deckOffsetLo`/`Hi`, `deckY`, `deckX`, `deckHeight`, `deckWidth`, `deckColour`, `deckDroids` |
| `&8A80` | 128 | *free — alignment gap* |
| `&8B00` | 3,207 | `leveldata` — RLE deck maps, all 16 |
| `&9787` | 1,743 | `drSprData` — the droid artwork, 249 rows × 7 bytes. Moved here 2026-08-14: only `SprFetchRow` reads it, and the sprite bank is the scarce one |
| `&9E56` | 336 | `drOfsLo`/`Hi` — offset into `drSprData` per (phase, row) |
| `&9FA6` | 120 | `drSpeed`, `drSpeedF`, `drSpeedFHi`, `wpCount`, `wpOfsLo`/`Hi` |
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

## SWRAM bank 5 — `PARASPR` (shifts 0 and 1 px)

`&8000–&BBF6`, 15,351 bytes used, **1,033 free** (2026-08-19, unchanged). Two of the four compiled shifts,
plus Layer 7's effect artwork — 31 bullet and explosion frames, 2,946 B, here because the
interpreted effect path reads them every row.

## SWRAM bank 6 — `PARSPR2` (shifts 2 and 3 px)

`&8000–&B9B7`, **1,609 free** (2026-08-19) — it was 40. TASK 6's `PnClear` fix gave 7, TASK 3's shared `FontCell` 20, and TASK 7's single string table the other 1,542. **No longer the tight bank**. The other two shifts, laid out
identically, plus Layer 9's panel engine, HUD, console, strings and icons.

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

`&8000–&AEC6`, **4,410 free** (2026-08-19) — it was 282 before Layer 13a. TASK 1 moved the 2 K shadow screen onto the sprite save areas and TASK 2 deleted 544 bytes of duplicated lift-view glyphs. **This is what unblocks 11d**, whose token-string printer would not fit in 282 bytes. Layer 10's transfer game and
Layer 8b's lift screen, sharing the shadow screen/colour RAM, the glyph page and the renderer
pattern; plus both glyph sets, the console's ship page, the deck plan (`condeck.asm`,
`plandata.asm`), and the droid database (`condb.asm`, `droidinfo.asm`) with its second copies of
the string table and the droid icon — second copies because the first ones live in bank 6 and only
one bank is visible at a time. The internal layout is in
[`layer-10-transfer.md`](layer-10-transfer.md) and [`layer-9-hud.md`](layer-9-hud.md) §6e–6f.

## Two things this map says that the summaries do not

**The constraint was code space, and moving code fixed it — repeatedly.** "Main RAM is full"
always meant "the `PARA` image cannot grow past `&3000`" — never that there was no RAM. Since a
bank can hold code as easily as data, the level draw went to live beside the tile and deck data it
reads, and `droid.asm` after it. Layers 7–10 then spent the room again, each paying its way in by
moving something else across; `&3000` is 24 bytes away, and displacing code into a bank remains
the standing answer.

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
| `door.asm` | main RAM | Door state, `DoorScan`, the patched tile definitions, `DoorsUpdate`, `DrawDoorTile` |
| `lift.asm` | main RAM | `LiftFind`, lift mode, stepping a shaft, `LiftPlace` |
| `screen.asm` | bank 4 | `DrawHalf`, `BuildCharPtrs`, `BandSetRow`, `ColSetup`, `MapChar`, `RedrawAll` |
| `scroll.asm` | bank 4 | `DrawColumn`, `DrawBandRows`, `CopyCell`, `ScrollAddS`, `DoRedraws` |
| `level.asm` | bank 4 | Deck decode, `BuildCharset`, `BuildLUTs`, `SetPalette` |
| `droid.asm` | bank 4 | The ship roster, waypoints, `DroidsUpdate`, line of sight, collision, the kill chain, `ConMenu4` |
| `panel.asm` | bank 6 | Layer 9's panel text engine and HUD |
| `console.asm` | bank 6 | The console screen, its strings and icons |
| `xfer.asm` | bank 7 | Layer 10's transfer minigame |
| `liftview.asm` | bank 7 | Layer 8b's deck-selection screen |
| `condeck.asm` | bank 7 | The console's deck plan page |
| `condb.asm` | bank 7 | The console's droid database page |

`src/data/` is generated by the exporters in `tools/` and is gitignored — regenerate it rather
than editing it.
