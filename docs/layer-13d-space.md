# Layer 13d — the space pass: title overlay, the portrait, ZX0 decks

**Built and verified in jsbeeb 2026-08-20, all in one session.** Four tasks KC ratified from the
bank-7 costing (see PLAN's portrait row for the numbers that drove it), in order. The detail for
the first two lives where their layers live — this file carries the ZX0 work, the measurements,
and the one plan reversal.

| Task | Where the detail is | Net effect |
|---|---|---|
| 1. Title → `PARTITL` disc overlay, and the game-over → title loop | [`layer-11-sound-title.md`](layer-11-sound-title.md) §11c | bank 7 +1,345; the game loops for the first time |
| 2. ~~sideview → bank 5~~ REVERSED → `dfsSave` → bank 6 | §2 below | bank 7 +1,024, bank 6 −912 |
| 3. The 48 × 84 droid portrait, raw pool | [`layer-9-hud.md`](layer-9-hud.md) §6f decision 2 | bank 7 −4,864; the database page is faithful |
| 4. ZX0 deck maps | §3 below | **bank 4 12 → 1,161 free** |

## 1. The numbers, before and after

| | before | after |
|---|---|---|
| main RAM | 389 B | **161 B** (the seam's `TitleSeq`/`GoTitle`/`UninstallIrq`/snapshot helpers) |
| bank 4 | 12 B | **1,161 B** |
| bank 5 | 1,033 B | 1,033 B (untouched — the bullet flicker's) |
| bank 6 | 975 B | **63 B** (`dfsSave`) |
| bank 7 | 4,410 B | **826 B** (title out, portrait in) |

## 2. [DECISION] sideview does NOT move to bank 5 — the plan said it would

KC approved "sideview → bank 5" on the session's costing, which had mislabelled `sideview.asm` as
the console's self-contained ship page. It is not: it is the **lift screen's data**, read by
`liftview.asm` in bank 7, which itself runs on `xfer.asm`'s shared shadow-screen machinery — and
only one bank is visible at a time, so the data cannot leave its readers. The same bytes were
freed a safer way: the `dfsSave` snapshot (task 1's DFS-workspace fix) is pure data touched only
by main-RAM helpers that page a bank around the copy, so it is bank-agnostic — it moved to
bank 6, shrunk to its minimal 912 bytes (`&0D60–&0DEF` + `&0E00–&10FF`; the NMI page and the ROM
workspace bytes are never written by us). Bank 5 stays whole for the flicker. **Standing for KC
to veto.**

## 3. ZX0 for the deck maps — and the RLE is gone entirely

**The shape.** Rather than compressing the C64's RLE streams, `export_bbc.py` now decodes each
deck offline — `BuildLevel`'s exact old semantics, including decks 1 and 2 legitimately running
past their stream into the next deck's data — and ZX0-compresses the **decoded 1,024-byte maps**.
That beats compressing the RLE (zlib said 2,266 vs 3,048-ish), needs **no scratch anywhere**
(`Zx0Unpack` writes straight into the tile map), and deletes the RLE decoder from `BuildLevel`
and the RLE walker from the deck-plan page. The decoded maps are byte-identical to the C64's;
only the packaging changed.

| | bytes |
|---|---|
| `leveldata` (RLE, deleted) | 3,503 |
| `deckPack` (16 ZX0 streams) | 2,183 |
| `zx0depack.asm` | ~230 |
| net bank 4 | **+~1,100** |

**The compressor** is `tools/zx0.py` — a line-for-line Python port of Einar Saukas' reference
(BSD-3, github.com/einar-saukas/ZX0) in its default mode: forwards, interlaced Elias gamma,
inverted new-offset-MSB payload. It carries its own decompressor and every emitted stream is
round-trip-verified at export time. **The depacker** is `src/zx0depack.asm` in bank 4, written
from the reference compressor's source, not from a recalled depacker; ~40k cycles for a
1,024-byte map, deck-load-time only. Format notes are in its header.

**Verified**: all 16 decks unpacked in jsbeeb via a `BuildLevel` trampoline and diffed against
the offline decode — 16 × 1,024 bytes, **zero mismatches** — plus a normal boot playing on its
decompressed deck.

**Two consumers changed with it:**
- `BuildLevel` (level.asm) is now pointer setup + `JMP Zx0Unpack`.
- The console's **deck plan** (`condeck.asm`) used to decode a staged copy of the deck's RLE at
  `SPR_SAVE`; it now walks **the tile map itself** — main RAM, static after `BuildLevel`,
  readable from bank 7 in place — and `ConDeckEnter4` (droid.asm) lost its 512-byte staging
  copy, keeping only the t1i3 row-16 work. Cell values and order are identical by construction;
  **the page still wants an in-game play-check**, same as the database page's portrait.

**Where else ZX0 could pay, when wanted**: the title RLE (on disc now, no need), the intro
manual's 15.5 K text (Layer 14), and nothing else measured worth a depacker call.

## 4. Owed from this pass

- An in-game play-check of the console's droid database (the portrait) and deck plan pages.
- `PoDraw`'s rectangle parameterised so `NewShipInfo`, `ShowXferInfo` and the game-over 999 can
  share it — 11d's first move.
- The game-over seam on real hardware someday: `UninstallIrq`'s VIA restore is measured against
  jsbeeb's MOS 1.2 only.
