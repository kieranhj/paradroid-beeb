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
- **The boot** loads PARDEPK once, then `BootBanks` runs the four
  load-and-unpack pairs: `*LOAD` drops each compressed stream at
  `&3200`, and `UnpackBankIn` writes ROMSHAD+ROMSEL and JMPs `&3000`.
  **Since RAM pass 3a (2026-08-25), `BootBanks`, `UnpackBankIn` and the
  PARADAT/PARSPR2/PARXFER strings live INSIDE the PARDEPK overlay** —
  every caller runs with it resident — while `loaddepk` and `loadspr`
  stay in main RAM because the briefing exit OSCLIs both before its
  reload. `PageCopyAt` survives in main RAM for `PageLowIn` and the
  DFS-workspace snapshot. Depack ZP is the level draw's scratch, idle
  at boot; the loads all precede `InstallIrq`, so only the MOS IRQ runs
  during depack and it touches no bank.
- PARDEPK shares PARAFNT/PARTITL's ground and dies when PARTITL loads.
  **One thing DOES reload a bank afterwards**: the briefing exit
  re-`*LOAD`s PARDEPK and the PARASPR stream to bring the blitter home
  (`layer-11f-frontend.md`) — which is exactly why the overlay can hold
  `UnpackBankIn`. The game-over seam reloads only PARTITL/PARAFNT/PARALOW.
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
  byte counts): PARDEPK had ~240 B slack below `&3200`; RAM pass 3a's
  `BootBanks` move spent it down to **~144 B**, so an unrolled variant
  now has much less to work with. Re-cost before pursuing — raise it if
  boot time still grates.

## Where the disc time actually goes — measured 2026-08-29

KC asked for options to reduce the number of files loaded. The measurements say **the file count
is not the lever** — and they corrected an earlier reading in `layer-11f-frontend.md` §3d that
said it was.

Timed in jsbeeb with execute breakpoints on the `JSR &FFF7` sites and `read_registers`'
`elapsed_cycles` (`cycles_run` returns the *requested* count when a breakpoint fires — never use
it as a delta). Sizes from the SSD catalogue.

| file | bytes | sectors | measured | s/sector | when |
|---|---|---|---|---|---|
| `PARDEPK` | 368 | 2 | **0.181 s** | 0.091 | boot, disc already spinning |
| `PARDEPK` | 368 | 2 | **0.902 s** | 0.451 | briefing exit, first access after idle |
| `PARTITL` | 3,241 | 13 | 0.600 s | 0.046 | boot |
| `PARBRF` | 971 | 4 | 0.279 s | 0.070 | boot |
| `PARASPR` | 3,098 | 13 | 0.699 s | 0.054 | briefing exit |
| `PARAFNT` | 3,503 | 14 | 1.067 s | 0.076 | briefing exit |
| `PARALOW` | 927 | 4 | 0.279 s | 0.070 | briefing exit |
| `PARMAN` | 5,016 | 20 | 1.942 s | 0.097 | title exit, first access after idle |

**The same 368-byte file costs 0.181 s or 0.902 s depending on nothing but context.** That is a
controlled comparison — same file, same size, same two sectors — so the 0.72 s difference is not
`PARDEPK`. It is **the first disc access after the drive has been idle**, which is consistent with
motor spin-up, and it is paid once per path by whatever happens to go first. `PARMAN`'s 0.097
s/sector has the same shape: it is also a first-after-idle load.

**So the model is `~0.07 s a sector, plus ~0.7 s once per path.`** Every load that is not first
sits in 0.046–0.091 s/sector with **no measurable per-file overhead**. Two consequences, and the
second reverses what §3d concluded:

1. **Merging files buys nothing.** `PARAFNT`+`PARALOW` are always loaded together and
   `PARTITL`+`PARBRF` nearly so, but a merge only saves per-file overhead and there isn't any.
   Ruled out on the data rather than on taste.
2. **Removing a file only saves its sectors** — and if it was the *first* file on its path, the
   0.7 s wake-up simply moves to whatever is now first. Dropping `PARDEPK` from the briefing exit
   is worth its 2 sectors (~0.18 s), not the 0.902 s the stopwatch appears to show.

**Corrected value of §3d's three eliminations.** Dropping `PARDEPK`, `PARAFNT` and `PARALOW`
leaves the wake-up plus `PARASPR`: 0.72 + 0.699 + 0.755 depack ≈ **2.17 s against today's 3.702 s,
a saving of ~1.53 s** — not the 2.248 s the first pass claimed, because that pass credited the
wake-up to `PARDEPK`. The bulk of it is `PARAFNT`'s 1.067 s, and that one needs only a depacker
that does not land on `&3000`.

### The options, ranked by measured value

| | saves | costs | notes |
|---|---|---|---|
| **Read sectors faster** — DFS delivers ~14 sectors/s where one revolution a track would give ~50 | up to ~3.5× on **every** load, ~7 s of the ~11 s boot | a direct `OSWORD &7F` reader plus the catalogue lookup it replaces | Much the biggest lever, and it makes every other row here smaller. **Spike it before committing**: the 0.07 s/sector is jsbeeb's disc model, and the gain is only real if the model is faithful. Does *not* need DFS's `&1100` random-access workspace, which the code image has taken |
| **Skip `PARAFNT`/`PARALOW` on the briefing exit** (§3d) | **1.35 s** | a depacker that is not at `&3000`, plus snapshotting the low overlay | Biggest win that needs no new I/O code |
| **Resident depacker**, ~300–368 B of main RAM | 0.18 s directly | ~half the 639 B free below `&3000` | The *enabler*: unblocks the row above and both compressions, and drops `PARDEPK` from boot and from the exit |
| **Compress `PARAFNT`** 14 → 8 sectors (55%) | ~0.4 s per `ts_loads` — boot, every title, briefing exit | needs the resident depacker | Recurs on every path |
| **Compress `PARMAN`** 20 → 11 sectors (54%) | ~0.5 s of its 1.94 s | needs the resident depacker | Without one it is net zero: reloading `PARDEPK` to get a depacker costs about what the compression saves |
| ~~Merge `PARAFNT`+`PARALOW`~~ | **~0** | — | No per-file overhead to recover. Ruled out |
| ~~Merge `PARTITL`+`PARBRF`~~ | **~0** | — | Same |
| ~~One combined bank file~~ | — | — | The four streams are 105 sectors and only one fits in RAM at a time; and reading it in pieces wants DFS random access, whose `&1100`–`&18FF` workspace is the code image |

**The through-line: spend the effort on sectors and on how they are read, not on how many
catalogue entries there are.** Compression already bought the boot 14.4 s → 10.4 s by cutting
sectors; the same lever has not been applied to `PARMAN` or `PARAFNT`, and the read rate itself
has never been attacked at all.

## Built: one resident depacker, and PARDEPK is gone — 2026-08-29

KC, after the measurements above: *"we're not doing a raw sector reader. find a way to get a
single resident depacker and compress the additional files."*

**The way was that the depacker was already in memory twice.** `zx0depack.asm`'s macro was
instantiated in bank 4 for `BuildLevel`, and the `PARDEPK` overlay carried a second copy for the
loader — so a 273-byte routine occupied 546 bytes and was *loaded from disc twice per session*,
at boot and again on the briefing exit. Bank code may call main RAM freely, so **one copy in the
code image serves both**: `BuildLevel`'s `JSR Zx0Unpack` now resolves across the bank boundary,
and `PARDEPK` is deleted outright.

| | main RAM | bank 4 |
|---|---|---|
| depacker macro moved in / out | +257 | **−257** |
| `UnpackBankIn` (now sets its own src/dest) | +25 | |
| `BootBanks` + its three load strings | +90 | |
| `loaddepk` string, no longer needed | −14 | |
| `DoorCopyDef` moved out to pay the balance | **−51** | +51 |
| **result** | **`code_end` = `&3000` exactly, 0 B free** (was 296) | **231 B free** (was 25) |

**`DoorCopyDef` was the right 51 bytes** because it already could not run without `SWRAM_DATA`
paged — it reads `tdpLo`/`tdpHi` and the tile definition through them, and those are
`screen.asm`'s, in bank 4. Being *in* bank 4 adds no precondition it did not already have, and
its one caller (`door.asm`'s `dp_new`) is main-RAM play-path code where `SWRAM_DATA` rests.

**`PARMAN` ships ZX0 now**, 5,016 B / 20 sectors → 2,730 B / 11. `BrTimeout` calls
`UnpackBankIn` where it used to call `PageCopyAt` page by page. It was the free one to do: it
already lands at `DEPK_STREAM` and unpacks to bank 5, so nothing had to move.

**Measured**: boot to `TitleSeq` **10.96 s → 10.73 s** (that is `PARDEPK`'s 0.181 s and little
else — boot is dominated by the four big bank streams). The briefing seams get more: `PARMAN`'s
nine sectors are worth ~0.5 s inbound and the dropped `PARDEPK` ~0.18 s outbound.
**Verified in jsbeeb**: boots, the briefing text renders from the compressed stream, a deck draws
(which is `BuildLevel` decompressing its tile map through the cross-boundary call), and the view
scrolls.

### Still to do: PARAFNT

It is worth 6 sectors (14 → 8, ~0.42 s) on **every** `ts_loads` — boot, every title, and the
briefing exit — so it is the best of what is left. It was not done here because it needs a
landing address and that needs care: **`PARAFNT` unpacks to `&3000` and its stream cannot land at
`DEPK_STREAM`**, because the writer overtakes the reader. The arithmetic: with the stream at
`&3200` the output starts 512 B behind and gains 0.446 B per output byte, so it catches up after
~1,148 bytes of a 3,503-byte output and corrupts the rest.

**The fix is ZX0's standard in-place trick — land the stream so it ENDS where the output ends.**
At `&3700` the output only catches the input after ~4,017 bytes, which is past the 3,503 it will
ever write. That also puts the whole stream (`&3700`–`&3E93`) **below `&4000`**, outside the
displayed title framebuffer, so it needs no display blanking — the tail sits in `SPR_SAVE`, which
is scratch at that moment.

**Do not take `&3700` on the strength of that average, though.** ZX0 can expand locally (a
literal run copies 1:1 plus its flag bits), so the true minimum gap is a property of the actual
stream, not of the ratio. Compute the real delta by walking the decode and tracking
`max(out_pos − in_pos)`, and assert it in `make_disc.py` so a text edit that changes the
compression cannot silently break the boot.
