# Loader compression — the four banks ship ZX0 on disc

2026-08-21. Requested by KC after playtesting: boot spent most of its time
loading 4 × 16K bank files and copying them up. Layer 13d had already put a
ZX0 decompressor in the tree; this extends it to the disc files themselves.

## What ships

| File | Raw | ZX0 on disc |
|---|---|---|
| PARADAT | 16,381 | 10,466 (63.9%) |
| PARASPR | 15,351 | 2,833 (18.5%) |
| PARSPR2 | 16,326 | 3,720 (22.8%) |
| PARXFER | 15,558 | 8,161 (52.5%) |

The blitter banks collapse because four compiled shifts of the same sprites
are massively self-similar. PARADAT compresses worst because its deck maps
and char bitmaps are *already* ZX0 streams — you cannot compress them twice.
The other disc files were measured and deliberately left raw: PARA carries
the loader itself, PARTITL runs in place at its load address, PARAFNT and
PARALOW are small and are reloaded through the game-over seam, which this
change does not touch. Together they would have bought under a second.

## Measured (jsbeeb, breakpoints at SetupMode and TitleSeq)

| Phase | Before | After |
|---|---|---|
| Power-on → SetupMode (MOS boot, !BOOT, PARA) | 6.01M cycles (3.0 s) | 4.33M (2.2 s) |
| SetupMode → TitleSeq (the four banks) | 22.86M (11.4 s) | 16.47M (8.2 s) |
| **Power-on → title** | **28.9M (14.4 s)** | **20.8M (10.4 s)** |

Effective raw DFS throughput was ~5.6 KB/s, so the four banks' 38K of
saved disc reads dominate; the depack costs some of it back (the bank-4
decompressor is written for size, not speed — its ~40k cycles per 1K on
the deck maps rises on less compressible data). The first-phase saving is
the disc reorder alone: beebasm laid files in SAVE order, which put !BOOT
and PARA physically *last*, so every boot read the end of the disc and
seeked back to track 0.

## How it works

- **`src/zx0depack.asm` is now a macro** (`ZX0_DEPACKER`), instantiated
  twice with identical instructions: `Zx0Unpack` in bank 4 for BuildLevel
  as before, and again in **PARDEPK**, an eighth disc file at
  `DEPK_ADDR = &3000` behind a 16-byte stub that aims it at
  `DEPK_STREAM = &3200` → `SWRAM_BASE`. A second copy is needed because
  only one bank is visible at a time — bank-4 code cannot fill bank 5 —
  and the code image had no room (46 B free at the time).
- **The boot** loads PARDEPK once, then for each bank: `*LOAD` drops the
  compressed stream at `&3200`, and `UnpackBankIn` (which replaced
  `PageBankIn`) writes ROMSHAD+ROMSEL and JMPs `&3000`. The copy loop's
  bank-copy entries went with `PageBankIn`; `PageCopyAt` survives for
  `PageLowIn` and the DFS-workspace snapshot. Net **one byte of code
  saved** below `&3000` (46 → 47 free — the removed copy heads paid for
  the extra OSCLI, the string and the stub). Depack ZP is the level
  draw's scratch, idle
  at boot; the loads all precede `InstallIrq`, so only the MOS IRQ runs
  during depack and it touches no bank.
- PARDEPK shares PARAFNT/PARTITL's ground and dies when PARTITL loads —
  by then all four banks are up, and nothing reloads a bank afterwards
  (the game-over seam reloads only PARTITL/PARAFNT/PARALOW).
- **`tools/make_disc.py`** post-processes beebasm's image
  (`build/PARADROID-raw.ssd` → `PARADROID.SSD` + the 200K pad):
  compresses the four banks with `bin/zx0.exe` (the reference compressor,
  sources and build line in `tools/zx0src/` — the Python `tools/zx0.py`
  is byte-identical but takes ~60 s per bank), round-trip-verifies every
  stream through `zx0.py`, rewrites the catalogue load addresses to
  `DEPK_STREAM`, and lays the files out physically in **boot access
  order**: !BOOT, PARA, PARDEPK, the four banks, PARTITL, PARAFNT,
  PARALOW.

## Verified

- All four banks dumped from jsbeeb after the depacked boot (paging each
  in via ROMSEL) and byte-compared against the same build's raw images:
  **identical**, all four. Title shows, game starts and plays.
- The three offline ZX0 implementations agree: `zx0.exe` output equals
  `zx0.py` output, and `zx0.py` decompresses every shipped stream back to
  the raw file before the image is written — every build, not just once.

## The trap this creates

**beebasm's own image is no longer bootable.** `UnpackBankIn` expects a
compressed stream at `&3200`; the raw image's banks are uncompressed at
`&3000`, and handing `build/PARADROID-raw.ssd` to an emulator hangs the
first bank load. Always use `build/PARADROID.SSD` or the 200K pad, both
written by `make_disc.py`. `build.ps1` runs the whole chain.

## Rejected along the way

- **Prepending the depacker to each compressed bank file** (no separate
  PARDEPK): works, but a separate file loaded once is simpler in the
  post-processor and lets the streams share one load address.
- **Compressing PARA/PARAFNT/PARTITL/PARALOW**: under a second combined,
  and each has a complication (see above). Not worth it.
- **A faster boot depacker** (the macro is sized for bank 4, where every
  byte counts): PARDEPK has ~240 B slack below `&3200`, so an unrolled
  or self-modifying variant could claw back a chunk of the ~3.5 s the
  depack itself costs. Left on the table — raise it if boot time still
  grates.
