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
| `&1100–&2FD8` | 7,897 B | Code (`PARA`), starting below DFS's `PAGE` of `&1900` |
| `&2FD9–&2FFF` | **39 B free** | |
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

Free main RAM totals **4,631 bytes**, of which only 39 are below `&3000`.

### The boot-time staging overlay

`*LOAD` stages both banks at `DATA_LOAD` = `&3000` and the copy-up runs from there, because the MOS
has the DFS ROM paged in at `&8000` during a filing-system call. So:

| File | Staged over |
|---|---|
| `PARADAT` | `&3000–&4B8B` |
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

`&8000–&9B8C`, 7,052 bytes used, **9,332 free**. Tiles, decks, palettes and droid game data. This is
the resting state of the bank latch.

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
| `&9787` | 72 | `drSpeed`, `drSpeedF`, `drSpeedFHi` — 24 droid types each |
| `&97CF` | 48 | `wpCount`, `wpOfsLo`, `wpOfsHi` |
| `&97FF` | 717 | `wpData` — 239 waypoint records |
| `&9ACC` | 16 | `deckDroidBase` |
| `&9ADC` | 112 | `doorDef` — patched tile definitions for open doors |
| `&9B4C` | 64 | `blankTileRow` |

## SWRAM bank 5 — `PARASPR`

`&8000–&B8B6`, 14,518 bytes used, **1,866 free**. The whole blitter: artwork, compiled rows,
compiled programs, glyphs. `SprRestoreAll` and `SprDrawAll` page this in and the data bank back out
around themselves.

**What each block is for is in [`layer-5-blitter.md`](layer-5-blitter.md)**, under "What is in the
bank, block by block" — including the division that explains the shape of this table: the compiled
fast path reads none of the artwork, and the wrap fallback is the only thing that does.

| Address | Size | Contents |
|---|---|---|
| `&8000` | 1,743 | `drSprData` — 249 stored rows × 7 bytes. Read only by the wrap fallback |
| `&86CF` | 344 | `drOfsLo`/`Hi`, `drMulRows`, `drDigitLo`/`Hi` — row and type lookups |
| `&8857` | 1,810 | `drD0_*` — compiled rotor draw rows, shift 0 |
| `&8F69` | 144 | `drR0_*` — compiled restore rows, shift 0 |
| `&8FF9` | 1,690 | `drD1_*` — draw rows, shift 1 (2 px) |
| `&9693` | 126 | `drR1_*` — restore rows, shift 1 |
| `&9711` | 320 | `drSeqLo`/`drSeqHi` — draw sequence, 16 × 10 rows |
| `&9851` | 320 | `drRSeqLo`/`drRSeqHi` — restore sequence |
| `&9991` | 1,340 | `drRHalf<shift>_<arr>_<half>` — the eight restore halves |
| `&9ECD` | 1,072 | `drPrg0_0…` — 16 straight-line draw programs, one per (shift, phase) |
| `&A2FD` | 688 | `drRPrg0_0…` — 16 restore programs |
| `&A5AD` | 640 | `drPrgLo`/`Hi`, `drRPrgLo`/`Hi` — program entry addresses, indexed by the same `sprSeqBase` the fallback uses |
| `&A82D` | 29 | `drSeqIdx`, `drMul10` — sprite row → sequence position, and phase × 10. Fallback only |
| `&A84A` | 1,926 | `drGlyph0_*` — ten unshifted digit glyphs |
| `&AFD0` | 2,131 | `drGlyph1_*` — ten shifted glyphs. Larger because of the spill column |
| `&B823` | 35 | `drBlkSave6` — the digit block's column 6 save, generated rather than written in `sprite.asm` |
| `&B846` | 112 | `drGlyphLo`/`Hi`, `drDigit0`/`1`/`2` — dispatch and per-type digits |

## Two things this map says that the summaries do not

**The binding constraint is code space, not main RAM.** There are 39 bytes below `&3000`, but 3.3 K
free above the tile map (`&3700–&37FF` and `&3C00–&47FF`) and 1.1 K at `&0C90`. None of it can hold
anything *loaded*, because the staging overlay runs straight through the first two — but it can hold
anything built at runtime, which is what `CHAR_PTR` and `SPR_MASKTAB` already are. Read "main RAM is
full" as "the `PARA` image cannot grow past `&3000`".

**1 px sprite positioning is bank-5-bound, not main-RAM-bound.** Since the blitter was compiled a
shift is *code*, ~4,632 bytes of it, so two more shifts want ~9.3 K against the 1,866 free here. The
9.3 K going spare in bank 4 is no help: only one bank is visible at a time, and the blitter needs its
own. The costing is in [`layer-5-blitter.md`](layer-5-blitter.md); why it matters is in
[`layer-4-player.md`](layer-4-player.md).
