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
was not. Diff the play buffer against `RedrawAll` at the same position (SPACE) byte for byte, over
**odd and even** `mapHX`, **non-zero `line`** and **diagonals** — every scrolling bug so far has
hidden in one of those. Let the view settle ~1,500,000 cycles first, and poke `JSR SprDrawAll` to
NOPs so a spinning rotor cannot pollute the diff.

For a change meant to be purely mechanical, there is a faster check that is also stronger: reduce
both builds' beebasm listings to a stream of (mnemonic, addressing class) and compare. A match
proves no instruction was added, removed or reordered.

## Target

| | |
|---|---|
| Machine | BBC Model B / B+ with **4 × 16K sideways RAM banks** (4 = data + level draw + droid AI + combat + the SN76489 sound driver, 5 and 6 = the blitter's four compiled shifts plus Layer 9's panel/console in 6, 7 = the transfer minigame, lift screen and console pages) |
| CPU | Plain 6502 — `CPU 0` in BeebASM, no 65C12 opcodes |
| Display | MODE 1, 4 colours. **Not a plain frame:** a 4-row static panel at `&4A00` above a 320 × 120 scrolled play area, driven by a three-cycle vertical rupture |
| Play area | 10K circular strip at `&5800`, **10K hardware wrap**, scrolled by the CRTC — 4 px horizontally, 1 scanline vertically |
| Game loop | `FRAME_LOCK` = 2 fields a pass, 25 Hz — a floor, not a fixed length: a pass that overruns carries on rather than waiting out another field |

## Build

```powershell
.\build.ps1          # assemble into build/
.\build.ps1 -Run     # assemble and launch in b-em
```

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
bank files with `bin/zx0.exe` (sources and build line in `tools/zx0src/`; round-trip-verified
through `tools/zx0.py` every build), moves their catalogue load address to `DEPK_STREAM`, and lays
the disc out physically in boot access order. The loader (`UnpackBankIn` + the `PARDEPK` overlay)
only understands that layout, so **`PARADROID-raw.ssd` hangs at the first bank load** — never hand
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
`PARALOW`, `PARTITL` and `PARDEPK`
in the project root. They are gitignored. Two things follow: a `-do` path that cannot be written leaves a
build that *looks* like it worked, and the symbol dump below litters unless you give it one.

Symbol addresses come from

```bash
./bin/beebasm.exe -i src/main.asm -do build/symbols.ssd -d | tr ',' '\n' | grep "'score'"
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
  above `&3000` is wiped before it can be read — hence the split `PARA` / `PARADAT` disc files,
  with `PARADAT` `*LOAD`ed after the mode change.
- **`LDA abs` is 4 cycles and `LDA zp` is 3 — but `LDA abs,X` and `LDA zp,X` are both 4.** Zero
  page is fully allocated (`&00–&8F`) and went to scalars; indexed tables gained nothing by moving.
  Worth knowing before costing a zero-page change.

## Memory budget

**`docs/memory-map.md` is the detailed map and `PLAN.md` keeps the outline — and take the
addresses from the `beebasm` output rather than from any document.** In outline:

| Region | Contents |
|---|---|
| ZP `&00–&8F` | All used. The map is in `main.asm`. `&90` up belongs to the OS |
| `&0400–&0C90` | MODE 1 charset, built at deck load — reclaimed OS workspace |
| `&0C90–&10FF` | **The low overlay** (`PARALOW`) — resident code and state in reclaimed DFS/OS workspace. `&0D00–&0D5F` (NMI) and `&0DF0–&0DFF` (ROM private workspace) are **excluded**. Nothing may be *loaded* here; it is staged and copied, and that copy **must be the last filing-system call** |
| `&1100–…` | Code (`PARA`), starting below DFS's `PAGE`. Ends just short of `&3000` — 47 B free, the binding constraint |
| `&3000–&37FF` | Sprite background save areas, one page per each of the eight slots |
| `&3800–&3BFF` | Tile map |
| `&3C00–&49FF` | Layer 9's text font (`PARAFNT`), border cells and mirrored droid tables |
| `&4A00–&53FF` | Panel — 4 rows × 640, displayed by rupture cycle 1 |
| `&5500–&57FF` | Character-address and sprite-mask tables, built at startup |
| `&5800–&7FFF` | Play buffer: circular strip, 16 rows × 640 |
| SWRAM bank 4 | `PARADAT` — tiles, levels, palettes, droid game data, **the level-draw code, the droid AI, Layer 10's entry/exit and Layer 11e's sound driver**. The char bitmaps ship ZX0-packed; `BuildCharset` unpacks them into the idle sprite save areas at deck load |
| SWRAM bank 5 | `PARASPR` — the blitter, shifts 0 and 1 px. **Evicted for the briefing**, which loads `PARMAN` over it: the manual's text, `briefman.asm` and the chatter's effect records. Both exits reload the blitter |
| SWRAM bank 6 | `PARSPR2` — shifts 2 and 3 px, same layout, plus Layer 9's panel/console, Layer 11f's `PnBriefing` and the 912 B `dfsSave` snapshot — **full** (16 B) |
| SWRAM bank 7 | `PARXFER` — Layer 10's transfer minigame, Layer 8b's lift screen, the console's ship, deck-plan and droid-database pages, and Layer 11's game over. The title is NOT here any more — it is the `PARTITL` disc overlay. **5,690 B free, reserved for the droid portrait pool** |

**RAM is the binding constraint. Measured from the build of 2026-08-24**, not remembered: the
main-RAM code image ends at `&2FFD`, so **3 bytes** below `&3000`, and **bank 4 has 105 B** after
Layer 15's space pass — any figure elsewhere claiming 2, 8, 47 or 60 is stale. The pass deleted
112 bytes of per-deck tables that nothing read and spent 15 back on a self-healing page pad in
`sound.asm`; `docs/memory-map.md` §"Layer 15 space pass" has the detail, and the pad means a
future bank-4 edit can move the gauge by up to 37 bytes on its own — read it, do not infer it. Both moved that day: the title's random boot deck
gave main RAM 4 back (`docs/layer-14-visual.md` DECISION 5) and the console's icon selection gave
bank 4 46 (`docs/layer-9-hud.md` DECISION 18). **Main RAM is by a wide margin the tightest thing in the
project**, and the padding note below is the other reason bank 4 is not.
Bank 4 went to 26 B when Layer 14's floor dither paid for itself, and spent it again on the text
palettes. **Bank 4 also has alignment padding in front of `colourMap` that the fuel gauge does not count — 17 B of the original 162 are left, `consolesel.asm` and `dbgkill.asm` having spent the rest, and anything — CODE or data — assembled ANYWHERE before that `ALIGN` rides there for nothing** (`src/consolesel.asm` is the worked example). **Deleting the `ALIGN` recovers nothing**: `tiledefs.asm` aligns next and pads by the same amount — measured, 2026-08-24. Past 162 B the `ALIGN` rounds to the next page and costs 256 at a stroke. See `docs/layer-9-hud.md` DECISION 18 and `docs/layer-14-visual.md`.
Layer 11f's front end spent bank 4's margin down again (the sixteen-row change had bought it back
to 60 by collapsing three copies of the `t1i3` restore into one in `ReframeView` — see
`docs/layer-9-hud.md` §6g). The build PRINTs bank 4's fuel gauge every run; the other three come
from `&C000` minus the end addresses it also PRINTs — **bank 5 1,033 B, bank 6 4 B, bank 7 314 B**
as of 2026-08-24, the low overlay 1 B and `lowcode2` 8 B.

**The `PARBRF` overlay at `&0400` has a hard ceiling of `&0800` and 3 bytes free**, and the
ceiling is measured, not caution: `&0800-&08FF` is the MOS's sound workspace and its IRQ writes
there through the front end's loads. Anything of the briefing's that need not be main RAM belongs
in `src/briefman.asm`, bank 5. Documents quoting ~1,188 B spare there measured to `&0C90` and are
wrong by a factor of fifteen. Banks 5, 6 and 7 are all paged out during play, so none of their
spare is reachable from the main loop. Anything new needs
something moved first — `docs/memory-map.md`'s free-RAM section lists what is left and where it can
come from.

**Every debug build except `DEBUG_INVULN` currently fails to assemble**, and that is the RAM above
rather than the flags: `RASTER`/`DRAW`/`TIME` hit the main-RAM `GUARD`, `POS`/`VSYNC`/`ENERGY` blow
bank 6's `spr2_end` assert, `MAPGUARD` blows bank 4's one-page assert in `sound.asm`. The three that
ship ON — `XFERWIN`, `RESTART`, `DECK` — build, which is why the default build is fine. Accepted by
KC 2026-08-21; they come back when space does. Do not chase one as a bug in the flag.

**Only one bank is visible at a time.** `SprRestoreAll` and `SprDrawAll` page their own bank in and
the data bank back out around themselves, so `SWRAM_DATA` is the resting state. This is safe
because the two halves are never wanted at once and the IRQ pages for itself: **the one thing the
IRQ does with banks is Layer 11e's sound tick**, which saves `ROMSHAD`, pages `SWRAM_DATA` around
`SndTick` and restores what it found — legal because `PAGEBANK` writes the shadow first. Anything
else in the IRQ must still read no bank; check that again before putting anything else in one.

All four bank files ship ZX0-compressed on disc (written by `tools/make_disc.py`, not by the
SAVEs): `*LOAD` drops each stream at `DEPK_STREAM = &3200` and `UnpackBankIn` decompresses it
straight into the bank via **`PARDEPK`, an eighth disc file** — the `ZX0_DEPACKER` macro from
`zx0depack.asm` again, loaded once at `&3000` before the banks and dead once `PARTITL` lands on
it. They cannot be loaded at `&8000` even uncompressed, because the MOS has the DFS ROM paged in
there during a filing-system call. `*LOAD` must also happen **before** `InstallIrq` — taking over
IRQ1V stops the MOS servicing the filing system. See `docs/loader-compression.md`.

**`PARALOW` is a sixth disc file and is loaded LAST, after `PARAFNT`.** It carries the low overlay,
which lands on DFS's own workspace at `&0E00–&10FF` **and, via `lowcode2`, on the MOS's extended
vector table at `&0D9F+` — the route DFS 1.2's FILEV takes into its ROM**. Copy it down before the
last `*LOAD` and that load hangs in the 8271 poll; make ANY filing-system call after `PageLowIn`
and it crashes through the trampled vectors. The game-over → title seam does exactly that, which is
why `SaveDfsWs` snapshots `&0D60–&0DEF` and `&0E00–&10FF` into bank 6 (`dfsSave`, 912 B) right
before `PageLowIn` and `GoTitle` restores them before its loads. `PARALOW` stages on the panel rather than at `&3000`,
because `PARAFNT` owns `&3000` and has to load first.

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

**Six files assemble into SWRAM bank 4, not main RAM**: `screen.asm`, `scroll.asm`, `level.asm`,
`zx0depack.asm`, `droid.asm` and `consolesel.asm` are included from inside the `PARADAT` block, next
to the tile, deck and waypoint data they read. **`consolesel.asm`'s position in that block is load
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
`export_title.py` and the rest — and is gitignored: it is converted game artwork. Regenerate it
rather than editing it. **`build.ps1` does not run them**, so a tool change means running the tool.

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
  SPACE debug redraw was wrong on the split row when `line != 0`; the split row no longer exists,
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
  `DEBUG_INVULN`, `DEBUG_DECK`. Each carries a header explaining what it shows and
  how to read it; `DEBUG_TIME` in particular documents how to take a cycle measurement that means
  something, including why only one call site may be instrumented at a time. **Two change what the
  GAME does rather than what it draws**. `DEBUG_XFERWIN`: W wins the transfer minigame outright, so
  droid behaviour after a capture can be reached without playing it. `DEBUG_DECK`: cursor up/down hop the player one
  deck at a time with no lift — the ship is walkable without it, but reaching deck 11 by lift to
  look at one tile costs minutes a time.
  `DEBUG_RESTART` was removed 2026-08-21: **ESCAPE** is a real game feature that ends the game
  through the whole death sequence, and it tests the boot split better than R's jump to
  `GameStart` did.
- **A debug build says so at boot.** `!BOOT` names every flag that is on (`REM DEBUG: XFERWIN`),
  built from conditional `EQUS` directives beside the build stamp, and a clean build prints no
  such line. Adding a flag means adding it to that block and to `DEBUG_ANY` as well as defining
  it — otherwise a build can lie about itself.
