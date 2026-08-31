# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

A port of the C64 game *Paradroid* (Andrew Braybrook, 1985) to the **BBC Micro Model B**, in
6502 assembly for the **BeebASM** assembler. A C64 disassembly has been reverse-engineered and
annotated, and the port plays: a deck scrolls eight ways under a droid you steer, with a pool of
eight sprite slots and a static panel above.

**Source material:** `paradroid_ce.lst` is a disassembly of the **1985 Hewson original / 1986
Competition Edition** lineage — verified by unpacking all four C64 releases and diffing them
against the listing (see `docs/decisions.md`). It is **not** Paradroid Redux and not
Heavy Metal, both of which relocate everything and match the listing at ~1–3%. `ANNOTATION.md`,
`docs/graphics.md` and everything extracted by `tools/` are therefore original-lineage data, and
may be described as "the original" without hedging.

The original and the Competition Edition share their game code, graphics, level data and — notably
— their movement constants byte for byte. CE is faster because it runs more game-loop iterations
per second, not because it moves droids further per iteration. On this port that dial is
`PLY_ITER_FRAMES` in `src/player.asm`.

**`PLAN.md` is the live planning document.** Read it before starting work — it records the state of
the port, the memory map, decisions taken, and one paragraph per layer. Update it as layers land.

**Completed layers keep their working notes in `docs/`**, one file per layer, plus `decisions.md`
and `master-extensions.md`. `PLAN.md` links to all of them. That is where the measurements, the
dead ends and the hardware facts bought the hard way live — read the relevant one before
optimising or re-litigating anything in that layer, because several of them record options that
were costed and deliberately *rejected*. When a layer's detail stops being needed to make the next
decision, move it out of `PLAN.md` rather than letting it accumulate.

## Working approach

**The C64 original is the specification. Go and read it before planning anything.** Every feature
starts by finding what the original does — the routine in `paradroid_ce_annotated.asm`, the data
table it reads, the exact layout it produces — and the port reproduces that. Prefer taking the
original's code, constants, data and layout **verbatim** over writing something equivalent: a
transliterated routine and a copied table are faithful by construction, and an "equivalent" one is
only faithful until the first thing it gets subtly wrong. When the C64 hardware forces a change
(a different display mode, a different sprite model, a smaller screen), port the *decision* the
original made, not just the effect.

**Rewrites and deviations must be agreed with KC before they are built, and written down after.**
That includes anything the original does not have, anything it has that the port drops, and any
place the port's geometry or timing forces a different arrangement. Raise it as an explicit
decision, get an answer, then record it in the layer's `docs/` file with the reason — the numbered
**[DECISION]** lists in `docs/layer-9-hud.md` and `docs/layer-10-transfer.md` are the pattern.
Do not quietly substitute a design of your own for the original's.

**No hardware abstraction layer.** An earlier iteration of this project designed a HAL up front;
that was explicitly rejected. Build one layer at a time, get each working and visible in the
emulator before starting the next, and revise `PLAN.md` as you go.

**Do not write hardware code from recalled facts.** The jsbeeb MCP is connected — set the
registers, look at the screen, read memory back, confirm, then build on it. The deleted
`src/hal_video.asm` is what happens otherwise: unverified CRTC arithmetic with `TODO: verify in
emulator` comments and a half-finished derivation in the middle of it. It survived in the tree for
months looking like working code.

**Verify against the buffer, not the screenshot.** Screenshots have repeatedly said "fine" when it
was not. Diff the play buffer against `RedrawAll` at the same position (**CTRL+R**, which needs
`DEBUG_REDRAW` — on in every dev build, off in RELEASE. Plain R until 2026-08-31, when every
debug key gained the modifier; SPACE before 2026-08-26) byte for byte, over
**odd and even** `mapHX`, **non-zero `line`** and **diagonals** — every scrolling bug so far has
hidden in one of those. Let the view settle ~1,500,000 cycles first, and poke **all three** draw
call sites to NOPs — the `JSR SprDrawAll` **and both `JSR SprDrawTr`s** near the top of the main
loop. NOPing only the first has been insufficient since the tranche split: the split path keeps
drawing and the diff shows a player-shaped block of false "corruption". Freeze with the player at
REST (restores replay every pass while draws are off, so a freeze mid-deceleration stamps stale
tiles into a scrolled buffer), and expect legitimate diffs from doors animating under droids —
`docs/ram-pass.md` §"The oracle recipe changed" has the full checklist.

For a change meant to be purely mechanical, there is a faster check that is also stronger: reduce
both builds' beebasm listings to a stream of (mnemonic, addressing class) and compare. A match
proves no instruction was added, removed or reordered.

## Target

| | |
|---|---|
| Machine | BBC Model B / B+ with **4 × 16K sideways RAM banks**, **probed at boot by `PARSWR` and no longer assumed to be 4-7** (Layer 13b — the four are taken highest-first, and the slots below are what the code calls them: slot 0 = data + level draw + droid AI + combat + the SN76489 sound driver, slots 1 and 2 = the blitter's four compiled shifts plus Layer 9's panel/console in slot 2, slot 3 = the transfer minigame, lift screen and console pages) |
| CPU | Plain 6502 — `CPU 0` in BeebASM, no 65C12 opcodes |
| Display | MODE 1, 4 colours. **Not a plain frame:** a 4-row static panel at `&4A00` above a 320 × 120 scrolled play area, driven by a three-cycle vertical rupture |
| Play area | 10K circular strip at `&5800`, **10K hardware wrap**, scrolled by the CRTC — 4 px horizontally, 1 scanline vertically |
| Game loop | `FRAME_LOCK` = 2 fields a pass, 25 Hz — a floor, not a fixed length: a pass that overruns carries on rather than waiting out another field |

## Build

```powershell
.\build.ps1           # assemble into build/
.\build.ps1 -Run      # assemble and launch in b-em
.\build.ps1 -Intro    # + scarybeasts' loading intro (pdloader/, docs/intro.md §8)
.\build.ps1 -Release  # THE BUILD FOR OTHER PEOPLE: -Intro, every DEBUG_ flag off
```

**`RELEASE` is a beebasm command-line symbol and every build passes it.** beebasm has no
`IFDEF` and refuses a symbol defined twice, so `main.asm` cannot carry a default of its own:
`build.ps1` passes `-D RELEASE=0`, or `-D RELEASE=1` on `-Release`, and `main.asm`'s `DEV` is
what `DEBUG_XFERWIN`/`DEBUG_DECK`/`DEBUG_KILL` read. **A bare `beebasm` invocation has to pass
it too** — the symbol dump below does — or assembly stops at `DEV` with *Symbol not defined*.
An `ASSERT DEBUG_ANY = 0` under `RELEASE` catches a readout left on by hand.

**`make.bat` and `make.sh` are thin wrappers over `build.ps1`** — KC uses them, so keep them
working. They map `make run` to `-Run` and pass everything else through; the pipeline itself
lives only in `build.ps1`.

**Everything the build produces goes in `build/`, which is gitignored:**

| | |
|---|---|
| `build/PARADROID-raw.ssd` | beebasm's direct output — **NOT bootable**, see below |
| `build/PARADROID.SSD` | the disc image, post-processed by `tools/make_disc.py` |
| `build/PARADROID-200K.SSD` | the same, padded — **give this one to jsbeeb** |
| `build/PARADROID.lst` | beebasm's `-v` listing, ~870 KB |

DFS filenames are max 7 characters — the executable on disc is `PARA`.

**The build is two stages: beebasm, then `tools/make_disc.py`.** The tool ZX0-compresses the four
bank files **and `PARMAN` and `PARAFNT`** with `bin/zx0.exe` (sources and build line in `tools/zx0src/`; round-trip-verified
through `tools/zx0.py` every build), moves their catalogue load address to `DEPK_STREAM`, and lays
the disc out physically in boot access order. The loader (`UnpackBankIn`, resident in the code
image) only understands that layout, so **`PARADROID-raw.ssd` hangs at the first bank load** — never hand
it to an emulator. Boot measured 14.4 s → 10.4 s; `docs/loader-compression.md` has the numbers.

**jsbeeb will not boot an unpadded SSD.** It hangs in the DFS FDC poll, because an image that ends
mid-track leaves jsbeeb refusing to read the last partial one. `build.ps1` (via `make_disc.py`)
writes the padded copy for you; pad before handing any hand-built image to an emulator or
publishing it.

**beebasm writes its progress and success messages to stderr.** In PowerShell that renders as an
error, and if you pipe or redirect *that stream* under `$ErrorActionPreference = 'Stop'` it raises
`NativeCommandError` and `build.ps1` throws even though the assembly succeeded. Check the exit
code. Redirecting **stdout** alone is safe, which is how `build.ps1` captures the listing; it is
`2>&1` that does the damage. From the Bash tool, `./bin/beebasm.exe ... 2>&1` is fine.

**beebasm's `SAVE` writes a loose host file whenever it has no disc image to put it in**, so any
run without a working `-do` drops `PARA`, `PARADAT`, `PARASPR`, `PARSPR2`, `PARXFER`, `PARAFNT`,
`PARALOW`, `PARTITL`, `PARBRF`, `PARMAN` and `PARSWR` in the project root. They are gitignored. Two things follow: a `-do` path that cannot be written leaves a
build that *looks* like it worked, and the symbol dump below litters unless you give it one.

Symbol addresses come from

```bash
./bin/beebasm.exe -i src/main.asm -do build/symbols.ssd -D RELEASE=0 -d | tr ',' '\n' | grep "'score'"
```

which dumps every global label as one long line of `'name':decimal` — the quick way to find a
variable's runtime address for an emulator poke. `-do` is there only to stop the nine loose files.

## Confirmed hardware facts (measured, not assumed)

- **CRTC start address = screen address ÷ 8.** Base `&5800` → R12/R13 = `&0B00`.
- Pixel address within a row-aligned buffer:
  `addr = base + (y DIV 8)*640 + (x DIV 4)*8 + (y MOD 8)`.
- **Adjacent 4-pixel columns are 8 bytes apart, not 1.** Consecutive bytes within a column are
  consecutive *scanlines*. This cost a build.
- MODE 1 byte encoding: pixel *n* takes bit `7-n` (high colour bit) and bit `3-n` (low bit).
  Solid colour 0/1/2/3 = `&00`/`&0F`/`&F0`/`&FF`. A character is **16 bytes** — the left half's
  8 scanlines then the right half's — so plotting one is a flat copy, no shifting or masking.
- **CRTC registers have different write windows.** R4/R5 belong to the cycle that samples them;
  **R6, R7 and R12/R13 must be written during the *previous* cycle.** Writing R7 at the row it
  should fire on means VSync never happens and the chip free-runs.
- **Never write R5 near a cycle boundary.** The vertical adjust compares a rising count against R5;
  change it after the count has passed and the match never happens, so the adjust runs on to its
  5-bit wrap — ~29 extra scanlines. R5's legal window is the whole cycle; use the middle of it.
- **The display window must fit inside ONE hardware wrap.** The address translator subtracts its
  mode amount once, when MA12 goes high — it does not iterate. A window larger than the wrap span
  fetches from `&8000` upwards (ROM) at some scroll positions and shows garbage on the last rows.
  With the 10K wrap and 80-unit rows the strip is exactly 16 rows, so 16 displayed rows is the
  ceiling — and smooth vertical scrolling therefore costs one row of play area.
- **Horizontal scroll granularity is 4 pixels**, not 8. CRTC addresses in 8-byte units and a
  MODE 1 character cell is 16 bytes (8 px × 2bpp × 8 rows), so one CRTC step is half a cell.
- **Code can start at `&1100`, not DFS's `PAGE` of `&1900`.** `&1100–&18FF` is DFS random-access
  file buffer space, untouched by simple `*LOAD` / OSFILE loads. Worth 2K.
- `VDU 22` makes the OS clear `&3000–&7FFF` (what it still thinks is its screen). Data loaded
  above `&3000` is wiped before it can be read — hence the split `PARA` / `PARADAT` disc files.
  **The mode change is the LAST thing boot does before the title (2026-08-31)**: every bank load
  and copy-up happens in the MOS's boot mode, where nothing they touch is displayed, and
  `SetupMode` then leaves the frame blank with **R1 = 0** so that `TitleSeq`'s own `*LOAD` of
  `PARTITL` cannot be seen either — `TiCRTC` restores `R1 = PLAY_UNITS` with the title.
  `docs/loader-compression.md` has the note, including why R6 = 0 leaks a row and R1 does not.
- **`&FE44` read at a fixed point in a vsync-locked loop is NOT random.** System VIA T1 runs
  the 100 Hz tick: 20,000 cycles, exactly half a frame, so the sampled byte is near-constant
  and only drifts with interrupt jitter. Cost PINTRO its lightning randomness (docs/intro.md
  §7); anything wanting entropy per frame needs a stepped PRNG with the timer as seed only.
- **The keyboard is read direct, not through `OSBYTE &81`** — `keydown` drives the System VIA
  matrix (latch line 3 down, `DDRA = &7F`, write the internal key number to `&FE4F`, read PA7
  back). **69 cycles against the OS's 243**, both measured; the pass tests a dozen keys. `&FE4F`
  not `&FE41` — the no-handshake register. The 26 masked cycles cost the rupture nothing, measured.
  `docs/raster-timing.md` has the numbers and the bit patterns.
- **`LDA abs` is 4 cycles and `LDA zp` is 3 — but `LDA abs,X` and `LDA zp,X` are both 4.** Zero
  page is fully allocated (`&00–&8F`) and went to scalars; indexed tables gained nothing by moving.
  Worth knowing before costing a zero-page change.

## Memory budget

**`docs/memory-map.md` is the detailed map and `PLAN.md` keeps the outline — and take the
addresses from the `beebasm` output rather than from any document.** In outline:

| Region | Contents |
|---|---|
| ZP `&00–&8F` | All used. The map is in `main.asm`. `&90` up belongs to the OS |
| `&0400–&0C90` | MODE 1 charset, built at deck load — reclaimed OS workspace. **`&0800–&08FF` inside it is the MOS's sound workspace, channel queues and envelopes**: safe only while we own IRQ1V, so ANY path that hands the machine back must flush the buffers first (`OSBYTE &0F, X=0`) or the MOS plays the charset as notes. `GoTitle` does; `docs/layer-11e-sound.md` §11 |
| `&0C90–&10FF` | **The low overlay** (`PARALOW`) — resident code and state in reclaimed DFS/OS workspace. `&0D00–&0D5F` (NMI) and `&0DF0–&0DFF` (ROM private workspace) are **excluded**. Nothing may be *loaded* here; it is staged and copied, and that copy **must be the last filing-system call** |
| `&1100–…` | Code (`PARA`), starting below DFS's `PAGE`. Also carries the one copy of the droid icon data (`droidicon.asm`), read from banks 6 and 7 |
| `&3000–&3DFF` | The `PARAFNT` block: text font, panel frame, the shared string table, `FontCell`/`DoScore` and the `PN_TABS` mirrors (48 B) |
| `&3E00–&45FF` | Sprite background save areas, one page per each of the eight slots; doubles as depack/staging scratch |
| `&4600–&49FF` | Tile map |
| `&4A00–&53FF` | Panel — 4 rows × 640, displayed by rupture cycle 1 |
| `&5400–&57FF` | Row/unit multiply (`&5400`), **`LUTs` — `BuildCharset`'s four nibble tables at `&54C0`** — character-address and sprite-mask tables, built at startup. **Packed exactly, no slack**: the 64 bytes that look free below `CHAR_PTR_LO` are `LUTs`, and the `ASSERT` that seems to permit a gap does not |
| `&5800–&7FFF` | Play buffer: circular strip, 16 rows × 640 |
| SWRAM bank 4 | `PARADAT` — tiles, levels, palettes, droid game data, **the level-draw code, the droid AI, Layer 10's entry/exit and Layer 11e's sound driver**. The char bitmaps ship ZX0-packed; `BuildCharset` unpacks them into the idle sprite save areas at deck load |
| SWRAM bank 5 | `PARASPR` — the blitter, shifts 0 and 1 px, **and the effect blitter (`src/sprfx.asm`, RAM pass DECISION 2)**. **Evicted for the briefing**, which loads `PARMAN` over it: the manual's text, `briefman.asm`, `keyredef.asm` (the CTRL+R key redefinition, Layer 11f) and the chatter's effect records. Both exits reload the blitter |
| SWRAM bank 6 | `PARSPR2` — shifts 2 and 3 px, same layout, plus Layer 9's panel/console, Layer 11f's `PnBriefing` and the 912 B `dfsSave` snapshot |
| SWRAM bank 7 | `PARXFER` — Layer 10's transfer minigame, Layer 8b's lift screen, the console's ship, deck-plan and droid-database pages, and Layer 11's game over. The title is the `PARTITL` disc overlay, and the droid icons are main RAM's now |

**RAM was the binding constraint until the RAM recovery pass of 2026-08-25**
(`docs/ram-pass.md`) bought back room across every region. **Measured from that build** — and
take live figures from `PRINT "code"` and the bank gauges in the build output, never from this
paragraph:

| Region | Free (measured 2026-08-30) |
|---|---|
| Main RAM code image | **4 B** — `code_end` `&2FFC` (7 B before `RuptAlign`'s call site). `keyTab` took the last six on 2026-08-30 and left it at zero; moving the debug redraw's key test into bank 4 (`DbgRedrawKey`) gave seven back on 2026-08-31. It was 48 B after the RAM pass; Layer 13b's `swBank` reads and handover copy took 37, and `TitleSeq`'s early `disrFlash` clear 5. **This is the binding constraint again** |
| Bank 4 | **11 B** on the gauge (2026-08-31: −105 for layer-12 DECISION 5's droid counting and conversion, −3 for BUGS #12's `sprSplit` clear; 143 B before those) + `colourMap` `ALIGN` pad, **which is SPENT** — 200 B put in front of it cost the bank 259, measured. **Now as tight as the code image** |
| Bank 5 | **602 B** |
| Bank 6 | **7 B** (2026-08-31: −32 for DECISION 5's `ConCount` and the count lines; 39 B before that. The 114 B here before 2026-08-30 was stale) |
| Bank 7 | 7 B tail + the `planInk` pad — **~100-105 B all in, MEASURED 2026-08-31** by bisecting a `SKIP` in `liftview.asm`. The "~176 B of pad" this table and `memory-map.md` used to quote was stale. **No held reserve frees bank 7**, which is what parked layer-12 DECISION 6 |
| `PARBRF` (`&0400`, hard ceiling `&0800`) | **2 B** — the tightest region after the code image (18 B before `RuptAlign`, 36 B before `BrTimeout`'s R8 blank, 56 B before the CTRL+R hook) |
| `PARAFNT` block | **16 B** before `SPR_SAVE` (`KeyDownIx` took 7, DECISION 5's `CN_STRS` 10) |
| `PARMAN` (bank 5's briefing load; the bound is `DEPK_STREAM + size <= PANEL_ADDR`) | **225 B** — the redefine screen took 893 |
| Low overlay | `lowcode` **9 B** (its two raw `PAGEBANK`s became `JSR Pg*`), `lowcode2` 3 B, `lowbss` 8 B |
| `PINTRO` (`pdloader/`, `-Intro` builds) | **0 B** — it fills to `&3000` exactly, where the picture lands. **It starts at `&2600` since 2026-08-31** (PORT 7's MODE 7 "Loading..." screen took the page it moved down for) and `&2500–&25FF` is what is left below it |

**THE STACK PAGE HAS 128 FREE BYTES AND NOTHING IS IN THEM YET.** `&0100-&017F` was measured
untouched on 2026-08-31 — `&A5` seeded with the game running, then play, a deck load, the console
and its pages, and the whole game over including `GoTitle`'s `*LOAD`s, which is the deepest path
there is because the MOS and DFS are heavy stack users. It is the only contiguous main-RAM space
left bigger than the `PARAFNT` block's 16 bytes. **Read `docs/ram-pass.md`'s section before using
it**: it lists the paths NOT exercised (the transfer game, the lift, the briefing), and anything
that deepens the call graph invalidates the measurement. Code cannot simply live there — page 1 is
not loadable from disc, so it would have to be copied down at boot.

Two standing rules about the `ALIGN` pads: **anything — CODE or data — assembled before bank 4's
`colourMap` `ALIGN` or bank 7's `plandata.asm` `ALIGN` rides in that pad for nothing**
(`src/consolesel.asm` and `src/xfericon.asm` are the worked examples, one each way), **deleting
either `ALIGN` recovers nothing** (the next ALIGN pads by the same amount; both low bytes are
load-bearing in pointer arithmetic), and spending one byte past a pad costs 256 at a stroke.
Quote a bank's pad and tail as a pair, never the tail alone. `docs/ram-pass.md` records what the
pass took, what it costed and rejected (do not re-litigate the blitter unrolls, `palPanel` or the
ALIGNs), and what is held in reserve for the next squeeze — `sprsplit.asm` to bank 5, SCANSTEP
tail folding, `door.asm` to bank 4, the `hsfont` dedup.

**The `PARBRF` ceiling is measured, not caution**: `&0800-&08FF` is the MOS's sound workspace and
its IRQ writes there through the front end's loads. Anything of the briefing's that need not be
main RAM belongs in `src/briefman.asm`, bank 5. Banks 5, 6 and 7 are all paged out during play,
so none of their spare is reachable from the main loop.

**Some debug builds still fail to assemble** — before the pass every one except `DEBUG_INVULN`
did, from the RAM squeeze rather than the flags: `RASTER`/`DRAW`/`TIME` hit the main-RAM `GUARD`,
`POS`/`VSYNC`/`ENERGY` blew bank 6's `spr2_end` assert, `MAPGUARD` blew bank 4's one-page assert
in `sound.asm`. The four that ship ON — `XFERWIN`, `DECK`, `KILL` and (since 2026-08-31) `REDRAW` — build,
which is why the default build is fine. Accepted by KC 2026-08-21; the pass's headroom may have brought others
back — try the flag before assuming, but do not chase a failure as a bug in the flag.

**Only one bank is visible at a time.** `SprRestoreAll` and `SprDrawAll` page their own bank in and
the data bank back out around themselves, so `SWRAM_DATA` is the resting state. This is safe
because the two halves are never wanted at once and the IRQ pages for itself: **the one thing the
IRQ does with banks is Layer 11e's sound tick**, which saves `ROMSHAD`, pages `SWRAM_DATA` around
`SndTick` and restores what it found — legal because `PAGEBANK` writes the shadow first. Anything
else in the IRQ must still read no bank; check that again before putting anything else in one.

The four bank files **and `PARMAN` and `PARAFNT`** ship ZX0-compressed on disc (written by
`tools/make_disc.py`, not by the SAVEs): `*LOAD` drops each stream at `DEPK_STREAM = &3200` and
`UnpackBankIn` decompresses it straight into the bank.

**THERE IS ONE DEPACKER AND IT IS RESIDENT** (KC, 2026-08-29). It used to be in memory twice —
`zx0depack.asm`'s macro instantiated in bank 4 for `BuildLevel`, and a second copy in a
`PARDEPK` disc overlay for the loader — and `PARDEPK` was therefore *loaded twice per session*,
at boot and again on the briefing exit. Bank code may call main RAM freely, so **one copy in the
code image** (`.Zx0Unpack`, with `UnpackBankIn` and `BootBanks` beside it) serves both, and
`PARDEPK` is gone: one fewer disc file everywhere, and nothing lands on `&3000` at the briefing
exit any more. It cost the code image its last bytes — **`code_end` is now exactly `&3000`** —
paid for by moving `DoorCopyDef` into bank 4, which the same change had just enriched by 257 B.
`docs/loader-compression.md` has the ledger and the measurements.

**`PARAFNT` unpacks IN PLACE and its landing address is checked every build.** It decompresses to
`&3000`, so its stream cannot use `DEPK_STREAM` — the output would overtake it. `FNT_STREAM =
&3700` is derived from the stream's true in-place delta (1,566 for today's font, measured by
`make_disc.py`'s `in_place_delta()`), and the build **fails** rather than shipping if a font or
briefing edit ever compresses worse than that address allows. Do not move `FNT_STREAM` without
reading that function. The banks cannot be loaded at `&8000` even
uncompressed, because the MOS has the DFS ROM paged in there during a filing-system call. `*LOAD`
must also happen **before** `InstallIrq` — taking over IRQ1V stops the MOS servicing the filing
system. See `docs/loader-compression.md`.

**`PARALOW` is a sixth disc file and is loaded LAST, after `PARAFNT`.** It carries the low overlay,
which lands on DFS's own workspace at `&0E00–&10FF` **and, via `lowcode2`, on the MOS's extended
vector table at `&0D9F+` — the route DFS 1.2's FILEV takes into its ROM**. Copy it down before the
last `*LOAD` and that load hangs in the 8271 poll; make ANY filing-system call after `PageLowIn`
and it crashes through the trampled vectors. The game-over → title seam does exactly that, which is
why `SaveDfsWs` snapshots `&0D60–&0DEF` and `&0E00–&10FF` into bank 6 (`dfsSave`, 912 B) right
before `PageLowIn` and `GoTitle` restores them before its loads. `PARALOW` stages on the panel rather than at `&3000`,
because `PARAFNT` owns `&3000` and has to load first.

**`pdloader/` IS A VENDORED DROP AND IS KEPT VERBATIM.** It is scarybeasts' loading intro and
its three-channel sample player — his source, his style, his binaries — so that his next version
is a clean diff. Our three changes to it are marked `\ PORT:` at the site and listed in its
header and in `pdloader/README.md`; do not restyle it and do not put anything there that could
live in the game. **Its beebasm pass must run from inside that directory** (`PUTFILE` paths are
relative to the working directory), which `build.ps1 -Intro` does. The picture and the lightning
colourways are OURS — `tools/export_intro.py` — and came back byte-identical, so
`src/data/introscr.zx0` and `src/data/introfx.asm` stay as the committed provenance even though
nothing includes them now. `docs/intro.md` §8.

**`PARSWR` is an eighth disc file and the FIRST thing `!BOOT` runs** — the sideways RAM
detector (`src/swram.asm`, Layer 13b). It probes all sixteen banks, takes the highest four, and
leaves them at `SWR_HAND = &0A00` for `.start` to copy into `swBank`; on a machine it will not
drive it says so and closes the exec file, so `*RUN PARA` never happens. **The bank numbers are a
run-time table now**: `SWRAM_DATA`/`SPR`/`SPR2`/`XFER` are indices 0-3, `PAGEBANK` reads `swBank`,
and nothing may assume the four are contiguous — `PAGESPRBANK` indexes the table for exactly that
reason. A bare `*RUN PARA` finds no magic byte and falls back to 4,5,6,7, so debugging is
unchanged. It is assembled AFTER `SAVE "PARA"` because it runs at `&1900`, inside the code image.
`docs/layer-13-compatibility.md`.

**`PARTITL` is a seventh disc file — the title screen**, assembled at `&3000` over `PARAFNT`'s
ground and loaded by `TitleSeq` when the title is wanted: at boot, and again on the way back from a
game over. `PARAFNT` reloads over it the moment it is done; the two are never wanted at once.

## Source organisation (`src/`)

Single-pass flat build, everything included from `main.asm`. No linker.

`main.asm` holds the constants, the zero page map, the main loop and the IRQ dispatch, and includes
everything else. **`lowcode.asm`, `lowcode2.asm` and `lowbss.asm` assemble below `&1100`**, into the
low overlay — read `lowcode.asm`'s header before putting anything there. `dbgpanel.asm` assembles
into bank 6, beside the panel its readouts draw on.

**`GUARD FONT_ADDR` guards the top of the code image and is not optional.** `CLEAR FONT_ADDR, ...`
releases beebasm's own overwrite check over exactly the range an over-long image spills into, so
without the GUARD an overrun assembles silently and corrupts `PARAFNT` at run time. A build that
stops with *Guard point hit* at `sprScan0` means the code image is full. **Everything in `src/` is in the build** — the five inherited Master/HAL files that
were not have been deleted, so nothing there is dead. Keep it that way.

**`src/xfericon.asm` assembles into bank 7 BEHIND `plandata.asm`'s `ALIGN`, and that
position is load bearing** — the same trap as `consolesel.asm` in bank 4, the other way
round. Read its header before moving it; in front of the ALIGN the padding rolls a page
and the bank overflows.

**Six files assemble into SWRAM bank 4 (eight with `DEBUG_KILL` and `DEBUG_DECK`), not main RAM**: `screen.asm`, `scroll.asm`, `level.asm`,
`zx0depack.asm`, `droid.asm`, `consolesel.asm` and (on a `DEBUG_KILL` build) `dbgkill.asm`
are included from inside the `PARADAT` block, next
to the tile, deck and waypoint data they read. **`consolesel.asm`'s and `dbgkill.asm`'s position in that block is load
bearing** — it must stay before `colours.asm` so `colourMap`'s `ALIGN` padding absorbs it; read its
header before moving it. That costs no
paging, because the data bank is the resting state. The rule it depends on is one-way and undiagnosed
if broken — bank code may call main RAM freely, but main RAM may call *in* only with `SWRAM_DATA`
paged, which is false at startup before the bank is loaded and inside `SprDrawAll`/`SprRestoreAll`.
`bufcore.asm` holds exactly what those two cases need — `SetupMode`/`SetupRupture`, `SetCRTCStart`, `WrapBufFwd`,
`SetCell` and the `rowMul`/`unitMul` tables — and its header states the rule. **Read it before moving
anything else across.**

Geometry and hardware constants live in `main.asm` rather than beside the code that uses them,
because beebasm resolves constant assignments in file order and the included files need them.

`src/data/` is generated by the exporters in `tools/` — `export_bbc.py`, `export_droids.py`,
`export_title.py` and the rest — and it **is committed** (KC, 2026-08-27; it was gitignored
before, as converted game artwork). Regenerate it with the tool rather than editing it, and
commit what the tool produces, so an exporter change shows up as a diff. **`build.ps1` does not
run them**, so a tool change means running the tool. `briefing.txt` is the exception in the other
direction: it is the hand-editable SOURCE of the briefing text, and `export_briefing.py` refuses
to overwrite it without `--force`.

**The shared charset holds only what a TILE references.** `export_bbc.py` builds `chardata.asm` from
the 137 characters the 32 tile definitions use, so a character the C64 draws from `$7800` for some
other purpose is simply not there and `CHAR_PTR_LO/HI` clamp it to entry 0 — silently, as a blank.
That has bitten twice: `EndGame`'s four wash characters and twelve of the title screen's thirty-six.
Both worked around locally; extending the shared set is the better fix and moves `NUM_CHARS`.

## Reference documents

- `PLAN.md` — the live plan; state of the port, memory map, layer summaries, open items
- `docs/` — per-layer working notes for everything already done, linked from `PLAN.md`.
  `decisions.md` also carries the evidence for which Paradroid the listing is
- `docs/graphics.md` — where the C64's graphics data lives, what format it is in, and which tool
  reads it. Each section says what has actually been ported and what has not
- `BUGS.md` — open defects, with the evidence and what has been ruled out. It used to warn that the
  forced debug redraw was wrong on the split row when `line != 0`; the split row no longer exists,
  so `RedrawAll` is a valid oracle at any scroll position — but read the entry's own caveat
- `ANNOTATION.md` — analysis of the C64 original: memory map, subroutines, hardware, data tables
- `C:\Users\khcon\OneDrive\BEEB\Projects\llm-beeb-wiki` — BBC hardware knowledge base; consult for
  hardware queries rather than parsing a PDF of the Advanced User Guide
- `paradroid_ce.lst` — raw C64 disassembly in the project root (gitignored; supply locally). The
  `_ce` suffix predates this project; the listing is original/CE lineage, so it is not misleading.
- `paradroid_ce_annotated.asm` — annotated disassembly, generated by `annotate.py`
- `prgs/*.prg` — the four C64 releases (gitignored). Unpack them with `tools/unpack_prg.ps1`
  when a data table needs checking against a different release.
- `ref/` — screenshots of the original running (gitignored), to check the port against.

## Assembly conventions

- BeebASM syntax: labels prefixed with `.`, comments with `\`, hex with `&`
- Plain 6502 only (`CPU 0`)
- Where practical, keep variable names matching `ANNOTATION.md` for cross-referencing against
  the C64 original
- Debug builds are switched by constants at the top of `main.asm` — `DEBUG_RASTER`, `DEBUG_DRAW`,
  `DEBUG_VSYNC`, `DEBUG_TIME`, `DEBUG_POS`, `DEBUG_ENERGY`, `DEBUG_MAPGUARD`, `DEBUG_XFERWIN`,
  `DEBUG_INVULN`, `DEBUG_DECK`, `DEBUG_KILL`, `DEBUG_REDRAW`. Each carries a header explaining what it shows and
  how to read it; `DEBUG_TIME` in particular documents how to take a cycle measurement that means
  something, including why only one call site may be instrumented at a time. **Three change what the
  GAME does rather than what it draws**. **EVERY DEBUG KEY NEEDS CTRL** since
  2026-08-31: the six play controls are redefinable (Layer 11f) and a player who bound one to R, C,
  W, `[` or `]` would otherwise be firing a debug function with it. `DEBUG_XFERWIN`: **CTRL+W** wins the transfer minigame outright, so
  droid behaviour after a capture can be reached without playing it. `DEBUG_KILL`: **CTRL+C** kills every droid on the deck, through the real `DrKillDroid` path, to
  reach the cleared-deck floor without shooting one empty (layer-14 DECISION 6).
  `DEBUG_DECK`: **CTRL+`[`** and **CTRL+`]`** hop the player one
  deck at a time with no lift — the ship is walkable without it, but reaching deck 11 by lift to
  look at one tile costs minutes a time.
  `DEBUG_RESTART` was removed 2026-08-21: **ESCAPE** is a real game feature that ends the game
  through the whole death sequence, and it tests the boot split better than R's jump to
  `GameStart` did.
- **A debug build says so at boot.** `!BOOT` names every flag that is on (`REM DEBUG: XFERWIN`),
  built from conditional `EQUS` directives beside the build stamp, and a clean build prints no
  such line. Adding a flag means adding it to that block and to `DEBUG_ANY` as well as defining
  it — otherwise a build can lie about itself.
