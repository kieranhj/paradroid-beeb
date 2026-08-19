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
| `&0C90–&10FF` | **1,136 B free** | The rest of the reclaimed workspace |
| `&1100–&2F6C` | 7,789 B | Code (`PARA`), starting below DFS's `PAGE` of `&1900`. The level draw and droid AI are in bank 4; Layers 7–10's main-RAM halves refilled the room they made |
| `&2F6D–&2FFF` | **148 B free** | The binding constraint. It was 24, then 30; Layer 13a's TASK 6 moved the 192 bytes of `rowMul`/`unitMul` out to `&5400` and built them at startup instead. Anything new here still wants displacing into a bank first |
| `&3000–&3CDF` | 3,296 B | Layer 9's text font, `PARAFNT` — 103 glyphs × 32 B, `*LOAD`ed here after the bank copies. **Moved down from `&3C00` by Layer 11** |
| `&3CE0–&3D9F` | 192 B | The status box's twelve border cells, same file |
| `&3DA0–&3DFF` | 96 B | The four droid tables, mirrored out of bank 4 for the panel in bank 6 — ends exactly at the save areas |
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
| `&54C0–&54FF` | **64 B free** | `PnClear` used to wipe this whole page past the panel — see Layer 13a, TASK 6 |
| `&5500–&55FF` | 256 B | `CHAR_PTR_LO` — character code → charset address, built at startup |
| `&5600–&56FF` | 256 B | `CHAR_PTR_HI` |
| `&5700–&57FF` | 256 B | `SPR_MASKTAB` — data byte → transparency mask, built at startup |
| `&5800–&7FFF` | 10,240 B | Play buffer: circular strip, 16 rows × 640, inside a 10K hardware wrap |
| `&8000–&BFFF` | 16 K | Sideways bank window — one of the FOUR banks below, never more |
| `&C000–&FFFF` | 16 K | MOS |

Free main RAM totals **1,348 bytes** (2026-08-19): 1,136 in the reclaimed OS workspace, 148 below
`&3000`, and 64 above the panel. **The 148 is the number that matters** — `&1100`–`&3000` is the
only region in the machine that is genuinely full, and it was 30 before Layer 13a's TASK 6. The
other two are buffer space: nothing loaded with the code can go in either. The room the level draw and `droid.asm` made when they moved into bank 4
(2026-08-14/15) has since been spent by Layers 7–10's main-RAM halves.

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

`&8000–&BED9`, **15 free** (2026-08-19) — and 111 of its apparent alignment holes are not real, see Layer 13a TASK 5. Tiles, decks, palettes, droid game
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

`&8000–&BFC5`, **47 free** (2026-08-19) — still effectively full; the 7 it gained came from `PnClear`'s assembled-away tail, Layer 13a TASK 6. The other two shifts, laid out
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

`&8000–&B4C6`, **2,874 free** (2026-08-19) — it was 282 before Layer 13a. TASK 1 moved the 2 K shadow screen onto the sprite save areas and TASK 2 deleted 544 bytes of duplicated lift-view glyphs. **This is what unblocks 11d**, whose token-string printer would not fit in 282 bytes. Layer 10's transfer game and
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
