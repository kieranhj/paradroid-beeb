# Memory map, as actually built

Every address here comes from a `beebasm -dd -labels` dump of the current build, not from a plan.
Regenerate it after any change that moves a region:

```powershell
./bin/beebasm.exe -i src/main.asm -do PARADROID.SSD -boot PARA -dd -labels PARADROID.labels
```

`PLAN.md` keeps the one-line summary; this file is the detail behind it.

## Main RAM

| Range | Size | Contents |
|---|---|---|
| `&0000–&008F` | 144 B | Zero page — **all of it used**. Breakdown below; the authority is the map in `main.asm` |
| `&0090–&00FF` | 112 B | OS zero page |
| `&0100–&01FF` | 256 B | Stack |
| `&0200–&03FF` | 512 B | OS vectors and workspace. We own `IRQ1V` at `&0204` outright |
| `&0400–&0C8F` | 2,192 B | MODE 1 charset, rebuilt at every deck load — reclaimed OS workspace |
| `&0C90–&10FF` | **1,136 B free** | The rest of the reclaimed workspace |
| `&1100–&2654` | 5,461 B | Code (`PARA`), starting below DFS's `PAGE` of `&1900`. The level draw is no longer here — see bank 4 |
| `&2655–&2FFF` | **2,475 B free** | |
| `&3000–&36FF` | 1,792 B | Sprite background save areas, 7 slots × 256 |
| `&3700–&37FF` | **256 B free** | |
| `&3800–&3BFF` | 1,024 B | Tile map, 64 × 16, page-aligned, fixed home |
| `&3C00–&47FF` | **3,072 B free** | Usable, with the staging rule below |
| `&4800–&547F` | 3,200 B | Panel — 5 rows × 640, displayed by rupture cycle 1 |
| `&5480–&54FF` | **128 B free** | |
| `&5500–&55FF` | 256 B | `CHAR_PTR_LO` — character code → charset address, built at startup |
| `&5600–&56FF` | 256 B | `CHAR_PTR_HI` |
| `&5700–&57FF` | 256 B | `SPR_MASKTAB` — data byte → transparency mask, built at startup |
| `&5800–&7FFF` | 10,240 B | Play buffer: circular strip, 16 rows × 640, inside a 10K hardware wrap |
| `&8000–&BFFF` | 16 K | Sideways bank window — one of the two banks below, never both |
| `&C000–&FFFF` | 16 K | MOS |

Free main RAM totals **7,067 bytes**, of which 2,475 are below `&3000` — the level draw moved
into bank 4 on 2026-08-14 and took 2,437 bytes of code with it.

### The boot-time staging overlay

`*LOAD` stages both banks at `DATA_LOAD` = `&3000` and the copy-up runs from there, because the MOS
has the DFS ROM paged in at `&8000` during a filing-system call. So:

| File | Staged over |
|---|---|
| `PARADAT` | `&3000–&5D2F` |
| `PARASPR` | `&3000–&68B5` |

Everything from `&3000` to `&68B5` is written through during boot — the save areas, the tile map,
the free 3K, the panel and the bottom 4K of the play buffer. That is why boot shows a moment of
garbage in the play area.

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

`&8000–&AD30`, 11,568 bytes used, **4,816 free**. Tiles, decks, palettes, droid game data — and, since
2026-08-14, the level-draw code that reads them. This bank is the resting state of the latch, so a
call into it from the main loop needs no paging at all.

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
| `&A3AB` | 2,437 | **Code**: `screen.asm`, `scroll.asm`, `level.asm` — `DrawHalf`, `HalfPtr`, `BandSetRow`, `BandCharPtr`, `ColSetup`, `MapChar`, `RedrawAll`, `BuildCharPtrs`, `DrawColumn`, `DrawBandRows`, `DoRedraws`, `BuildLevel`, `BuildCharset`, `BuildLUTs`, `SetPalette`, `CentreOnDeck` |

What could **not** come with it is in `src/bufcore.asm`, 480 bytes in main RAM: `SetupScreen` and
`SetCRTCStart` run before this bank is loaded, and `WrapBufFwd`, `SetCell` and the `rowMul`/`unitMul`
tables are reached while the *sprite* bank is paged in — `SprScanRow` tail-calls the first and
`SprCalcAddr` calls the second. A JSR from there into this bank would land in compiled sprite rows,
and nothing would diagnose it.

## SWRAM bank 5 — `PARASPR`

`&8000–&B097`, 12,439 bytes used, **3,945 free**. The whole blitter: artwork, compiled rows,
compiled programs, glyphs. `SprRestoreAll` and `SprDrawAll` page this in and the data bank back out
around themselves.

**What each block is for is in [`layer-5-blitter.md`](layer-5-blitter.md)**, under "What is in the
bank, block by block" — including the division that explains the shape of this table: the compiled
fast path reads none of the artwork, and the wrap fallback is the only thing that does.

| Address | Size | Contents |
|---|---|---|
| `&8000` | 56 | `drMulRows`, `drDigitLo`/`Hi` — the small lookups that stayed |
| `&8038` | 1,810 | `drD0_*` — compiled rotor draw rows, shift 0 |
| `&874A` | 144 | `drR0_*` — compiled restore rows, shift 0 |
| `&87DA` | 1,690 | `drD1_*` — draw rows, shift 1 (2 px) |
| `&8E74` | 126 | `drR1_*` — restore rows, shift 1 |
| `&8EF2` | 320 | `drSeqLo`/`drSeqHi` — draw sequence, 16 × 10 rows |
| `&9032` | 320 | `drRSeqLo`/`drRSeqHi` — restore sequence |
| `&9172` | 1,340 | `drRHalf<shift>_<arr>_<half>` — the eight restore halves |
| `&96AE` | 1,072 | `drPrg0_0…` — 16 straight-line draw programs, one per (shift, phase) |
| `&9ADE` | 688 | `drRPrg0_0…` — 16 restore programs |
| `&9D8E` | 640 | `drPrgLo`/`Hi`, `drRPrgLo`/`Hi` — program entry addresses |
| `&A00E` | 29 | `drSeqIdx`, `drMul10` — sprite row → sequence position, and phase × 10 |
| `&A02B` | 1,926 | `drGlyph0_*` — ten unshifted digit glyphs |
| `&A7B1` | 2,131 | `drGlyph1_*` — ten shifted glyphs. Larger because of the spill column |
| `&B004` | 35 | `drBlkSave6` — the digit block's column 6 save |
| `&B027` | 112 | `drGlyphLo`/`Hi`, `drDigit0`/`1`/`2` — dispatch and per-type digits |

The 3,945 bytes free here are the room the second compiled shift needs. `drSprData` and `drOfs` left
for bank 4 to make it, which is step A of the 1 px work — see
[`layer-5-blitter.md`](layer-5-blitter.md).

## Two things this map says that the summaries do not

**The constraint was code space, and moving code fixed it.** "Main RAM is full" always meant "the
`PARA` image cannot grow past `&3000`" — there was 4.6 K free, just none of it where code could go.
Since a bank can hold code as easily as data, the level draw went to live beside the tile and deck
data it reads, and `&3000` is now 2,496 bytes away rather than 39.

The other free regions still cannot hold anything *loaded*: `&3700–&37FF` and `&3C00–&47FF` are
under the staging overlay, so they take only what is built at runtime — which is what `CHAR_PTR` and
`SPR_MASKTAB` already are.

**1 px sprite positioning is bank-5-bound, not main-RAM-bound.** Since the blitter was compiled a
shift is *code*, ~4,632 bytes of it, so two more shifts want ~9.3 K against the 1,866 free here. The
9.3 K going spare in bank 4 is no help: only one bank is visible at a time, and the blitter needs its
own. The costing is in [`layer-5-blitter.md`](layer-5-blitter.md); why it matters is in
[`layer-4-player.md`](layer-4-player.md).
