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
both builds' beebasm listings to a stream of one entry per emitted instruction and compare. A
match proves no instruction was added, removed or reordered. **`tools/listing_stream.py` is that
reducer** — checked in 2026-09-08, after being written inline and thrown away every time it was
wanted, so no two runs were comparable. Today's tree is **23,528 instructions**. It is blind to
an operand's VALUE by design (a constant changed 8 → 4 diffs clean), so compare the disc images
byte for byte first and reach for the stream only when the addresses were MEANT to move.

**The verification procedures are skills, in `.claude/skills/beeb-*`.** They came from
`C:\Users\khcon\OneDrive\BEEB\Repos\beeb-port-kit` — KC's kit distilled from this port and
Edge Grinder — and were adapted to this project on 2026-09-08: `beeb-smoke-test`,
`beeb-buffer-oracle`, `beeb-cycle-timing`, `beeb-frame-drops`, `beeb-identical-build`,
`beeb-measure-fact`, `beeb-key-numbers`, `beeb-sound-verify`, `beeb-bss-bugs`,
`beeb-cross-emulator`, `beeb-close-layer`. Each is the checklist with the exact MCP calls and
this project's parameters filled in; read the relevant one before measuring something rather than
reconstructing the method from the prose here. **The kit itself has moved to the Baron assembler
and this project has not** — ignore Baron, `--check` and `tools/listing.py` in anything read
from the kit; beebasm is what is tried and tested here. The kit is upstream: a genuine
improvement goes back to it too.

**jsbeeb-mcp is on 3.4.0 and two long-standing complaints are fixed** (both measured here
2026-09-08, on the shipping image):

- **`read_memory` / `write_memory` / `save_memory` take `bank:` (0-15)** and sample that bank
  whatever ROMSEL says, putting the map back afterwards and reporting the `paging` they read
  through. So a bank-4 variable can be read mid-pass while the blitter has bank 5 up —
  `bank: 7` returned PARXFER's head while `paging.romsel` read 5. Without `bank:`, a read above
  `&8000` is still whatever happens to be paged.
- **The screenshot no longer misrenders the rupture.** Title, briefing and play all captured
  correctly (the capture is taken in the `paint_ext` vsync callback now). It is good enough for
  "did it boot and is the frame the right shape" and nothing more: the buffer is still the
  oracle, for the older and separate reason that screenshots have said "fine" when it was not.

Also worth knowing: `run_frames` steps painted frames and is what to use for anything
frame-oriented (`run_for_cycles` drifts, a field being 39,936 cycles and the MOS frame 40,000);
`save_state` / `restore_state` snapshot the whole machine server-side, so a prepared machine can
be reached once and restored between attempts — but **the keyboard is not in the snapshot**, so
release what you were holding; and `key_down` takes `internal:` / `inkey:` / `col`+`row` as well
as a name, and reports the matrix key that moved, which measures a key number in one call.

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

**THERE IS A SECOND IMPLEMENTATION OF THE SAME PIPELINE AND BOTH MUST BE KEPT IN STEP.** The
`Makefile` (hexwab's issue #3, 2026-09-09) builds the project on any POSIX system - `make`,
`make -j4`, `make release`, `make run`, `make data`, `make world`, `make help` - and produces a
byte-identical disc, which `make check-ps1` proves through `tools/compare_ssd.py` (per file out
of the DFS catalogue, masking `!BOOT`'s timestamp). `docs/build.md` is the whole story: what is
overridable, the three parts of the pipeline that are NOT a DAG and what was done about each,
and the timings (`make -j4` from clean 9.2 s against build.ps1's 7.9; a no-op `make` 0.23 s).
**A change to the pipeline has to land in both**, and **adding a file to `src/` means adding it
to `ASM` in the Makefile** - there is no wildcard, deliberately.

Tools come from `$PATH` unless overridden (`PYTHON`, `BEEBASM`, `ZX0`, `EMU`, `BUILD`), and
**nothing writes a `.exe` suffix any more**: `tools/zx0tool.py` resolves the compressor for all
five Python tools that shell out to it (`$ZX0`, then `bin/`, then `$PATH`), and `build.ps1` reads
`$env:PYTHON` / `$env:BEEBASM`. `make.bat` and `make.sh` are unchanged and still wrap `build.ps1`.

**`paradroid_ce.lst` IS COMMITTED as of 2026-09-09** (KC, on issue #3) - `make data` regenerates
`src/data` from it and `make world` does that and then builds. **Neither is part of the default
build**: the rules live in `mk/data.mk` precisely so they cannot creep into it, and `src/data`
stays committed for the reasons in the gitignore. `make data` needs Pillow. It has already paid
for itself - the first real run caught `src/data/sndchat.asm` carrying a hand edit that
`export_sound.py` did not know about, which would have defined `BR_CHAT_PRE` twice.


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
| `build/paradroid-raw.ssd` | beebasm's direct output — **NOT bootable**, see below |
| `build/paradroid.ssd` | the disc image, post-processed by `tools/make_disc.py` |
| `build/paradroid-200k.ssd` | the same, padded — **give this one to jsbeeb** |
| `build/paradroid.lst` | beebasm's `-v` listing, ~870 KB |

DFS filenames are max 7 characters — the executable on disc is `PARA`.

**The build is a PACK LOOP and then `tools/make_disc.py` (no-load step 5, 2026-09-09).** Some of
what bank 6 carries is assembled code copied down to run elsewhere — the `PARBRF` briefing driver
at `&0400` and the low overlay at `&0E00` — and **beebasm cannot compress its own output**, so
`main.asm` `SAVE`s each block under an X-name, `tools/pack_overlays.py` reads them back out of the
image, ZX0s them and writes `src/data/brfimg.asm` / `lowimg.asm` for the NEXT assembly, and
`build.ps1` assembles again if anything changed (exit 10). **In the steady state that is still one
assembly**; from a cold start it is two, and the loop is what makes convergence a build-time fact
rather than an assumption — a stream that changes size moves the bank around under the very block
it came from. **The X-files are dropped from the disc by `make_disc.py`'s `BUILD_ONLY` set, and
that is explicit for a reason** — `build_image` appends any file it does not recognise (which is
how an `-Intro` build carries PINTRO's data), so the four shipped, 7,444 bytes of them, until the
catalogue was actually looked at. **There is deliberately no size `ASSERT`** — one was tried, and a stale assert makes a
*changed* overlay unbuildable, because the assembly that would produce the new bytes is the one it
stops; the loop's byte comparison is the guard and the stronger check. A bare `beebasm` run
outside `build.ps1` can therefore assemble a stale overlay silently, which is harmless because
nothing boots that image. This pass exists because `keyredef` cannot ship packed without it —
`docs/no-load.md` §16.

**Then `tools/make_disc.py`.** The tool ZX0-compresses the four
bank files **and `PARAFNT`** with `bin/zx0.exe` (sources and build line in `tools/zx0src/`; round-trip-verified
through `tools/zx0.py` every build), moves their catalogue load address to `DEPK_STREAM`, and lays
the disc out physically in boot access order. The loader (`UnpackBankIn`, resident in the code
image) only understands that layout, so **`paradroid-raw.ssd` hangs at the first bank load** — never hand
it to an emulator. Boot measured 14.4 s → 10.4 s; `docs/loader-compression.md` has the numbers.

**Pad an SSD to 200K before handing it to an emulator or publishing it.** jsbeeb WILL boot an
unpadded image, so this is robustness and convention rather than a hard requirement (KC,
2026-09-01, correcting an earlier absolute here which claimed it would not boot at all and
blamed a hang in the DFS FDC poll). `build.ps1` (via `make_disc.py`) writes the padded copy for
you, and every image published to the Bitshifters wip folder is the 204,800-byte one, so match
that: a published size that differs from the previous publish is a useful signal that the wrong
file went out.

**beebasm writes its progress and success messages to stderr.** In PowerShell that renders as an
error, and if you pipe or redirect *that stream* under `$ErrorActionPreference = 'Stop'` it raises
`NativeCommandError` and `build.ps1` throws even though the assembly succeeded. Check the exit
code. Redirecting **stdout** alone is safe, which is how `build.ps1` captures the listing; it is
`2>&1` that does the damage. From the Bash tool, `./bin/beebasm.exe ... 2>&1` is fine.

**beebasm's `SAVE` writes a loose host file whenever it has no disc image to put it in**, so any
run without a working `-do` drops `PARA`, `PARADAT`, `PARASPR`, `PARSPR2`, `PARXFER`, `PARAFNT`,
`PARSWR` in the project root, plus the build-only `XBRF`/`XLOW`/`XKR`/`XREC` (`PARTITL` was one of them until no-load step 4
stopped `SAVE`ing it, and `PARBRF` and `PARALOW` until 2026-09-09 did the same). They are gitignored. Two things follow: a `-do` path that cannot be written leaves a
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
  `SetupMode` then leaves the frame blank with **R1 = 0** so that the title-time loads cannot be
  seen either — `TiCRTC` restores `R1 = PLAY_UNITS` with the title. (`PARTITL` was the load this
  was written for; it is a bank-7 copy since no-load step 4, but `TiShow` still `*LOAD`s `PARBRF`
  and the blank is still doing its job.)
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
addresses from the `beebasm` output rather than from any document.** The table below went stale
in four rows at once on 2026-09-09 and was corrected from the gauge; assume it is stale again. In outline:

| Region | Contents |
|---|---|
| ZP `&00–&8F` | All used. The map is in `main.asm`. **`&A0–&A8` is used too** — `drYcol0/1/2`, the first thing taken out of the second half of the zero page hexwab opened up in issue #2 (`docs/no-load.md` §19). With no filing call, no `OSWRCH` and no `OSRDCH` in flight, `&A0–&E6` plus `&E8–&E9`, `&F2–&F3`, `&F6–&F7` are ours — 77 bytes, of which 9 are spent. **Nothing up there is assumed to survive the front end**, which hands the machine back: seed it in `ts_loads`, as `SprSeedYcol` does. `&90–&9F` and `&E7` up stay the OS's |
| `&0400–&0C90` | MODE 1 charset, built at deck load — reclaimed OS workspace, and **the front end's two overlays live here instead**: `PARBRF` at `&0400–&0800` and (since no-load step 3) `PARTITL` at `&0900–&0A8D`. **`&0800–&08FF` between them is the MOS's sound workspace, channel queues and envelopes**: safe only while we own IRQ1V, so ANY path that hands the machine back must flush the buffers first (`OSBYTE &0F, X=0`) or the MOS plays the charset as notes — and **nothing loaded may sit there at all**, because the MOS owns IRQ1V through every load the front end makes and chews it (measured: a `PARBRF` reaching `&08B8` BRKed). `GoTitle` flushes; `docs/layer-11e-sound.md` §11 |
| `&0C90–&10FF` | **The low overlay** (`PARALOW`) — resident code and state in reclaimed DFS/OS workspace. `&0D00–&0D5F` (NMI) and `&0DF0–&0DFF` (ROM private workspace) are **excluded**. Nothing may be *loaded* here; it is staged and copied, and that copy **must be the last filing-system call** |
| `&1100–…` | Code (`PARA`), starting below DFS's `PAGE`. Also carries the one copy of the droid icon data (`droidicon.asm`), read from banks 6 and 7 |
| `&3000–&3DFF` | The `PARAFNT` block: text font, panel frame, the shared string table, `FontCell`/`DoScore` and the `PN_TABS` mirrors (48 B) |
| `&3E00–&45FF` | Sprite background save areas, one page per each of the eight slots; doubles as depack/staging scratch |
| `&4600–&49FF` | Tile map |
| `&4A00–&53FF` | Panel — 4 rows × 640, displayed by rupture cycle 1 |
| `&5400–&57FF` | Row/unit multiply (`&5400`), **`LUTs` — `BuildCharset`'s four nibble tables at `&54C0`** — character-address and sprite-mask tables, built at startup. **Packed exactly, no slack**: the 64 bytes that look free below `CHAR_PTR_LO` are `LUTs`, and the `ASSERT` that seems to permit a gap does not |
| `&5800–&7FFF` | Play buffer: circular strip, 16 rows × 640 |
| SWRAM bank 4 | `PARADAT` — tiles, levels, palettes, droid game data, **the level-draw code, the droid AI, Layer 10's entry/exit and Layer 11e's sound driver**. The char bitmaps ship ZX0-packed; `BuildCharset` unpacks them into the idle sprite save areas at deck load |
| SWRAM bank 5 | `PARASPR` — the blitter, shifts 0 and 1 px, **the effect blitter (`src/sprfx.asm`, RAM pass DECISION 2) and the rupture handover (`src/ruptalign.asm`), and the tranche prescan (`src/sprscan.asm`, 2026-09-01 — the split decision's geometry half, feeding `sprCls` in lowbss)**. **NOT evicted any more** (no-load step 5, 2026-09-09): it also holds the briefing's resident half — `briefman.asm`, `sndchat`, `brExtra`, `keyredef` as a ZX0 stream and two of the five page streams — where `PARMAN` used to be loaded over it, and neither briefing exit reloads anything |
| SWRAM bank 6 | `PARSPR2` — shifts 2 and 3 px, same layout, plus Layer 9's panel/console, Layer 11f's `PnBriefing`, two of the briefing's five page streams and the tranche decision's component half (`src/sprsplit.asm` — its geometry moved to bank 5's `sprscan.asm`, 2026-09-01) |
| SWRAM bank 7 | `PARXFER` — Layer 10's transfer minigame, Layer 8b's lift screen, the console's ship, deck-plan and droid-database pages, and Layer 11's game over. Since no-load step 3 it also holds **the title's artwork** (`src/data/title.asm`, raw — `TiPaint` reads it in place) and **the whole high-score screen below `HsEntry`** (`highscore.asm` + `hsremap.asm`). The droid icons are main RAM's |

**RAM was the binding constraint until the RAM recovery pass of 2026-08-25**
(`docs/ram-pass.md`) bought back room across every region. **Measured from that build** — and
take live figures from `PRINT "code"` and the bank gauges in the build output, never from this
paragraph:

| Region | Free (measured 2026-09-02, after layer-9 DECISION 20 and layer-12 DECISION 6) |
|---|---|
| Main RAM code image | **69 B** on the `no-load` branch — `code_end` `&2FBB`, measured 2026-09-10 after issue #18's `SetupModeRegs` moved `SetupMode`'s two CRTC writes into bank 4 and gave 15 back. It was **54 B** — `code_end` `&2FCA`, measured 2026-09-10 after issue #11's pre-clear in `SetupMode` took 18 (`docs/loader-compression.md`, "The mode change itself no longer shows memory"). It was **72 B** — `code_end` `&2FB8`, measured 2026-09-10 after layer-7 DECISION 13 (issue #12: the transfer key takes lifts and consoles) gave 12 back by collapsing `PassPrep`'s fire block. It was **60 B** — `code_end` `&2FC4`, measured 2026-09-10 after `PassPrep` and `prepDone` took 27 (`docs/raster-timing.md`). It was **87 B** — `code_end` `&2FA9`, measured 2026-09-09. `docs/no-load.md` §21 gave 27 back by putting briefing page 5 together again (`BrDepackChain` was 33 bytes and `BrDepackPage` is six); §20 gave 17 before it. The game-over seam gave 17 back (`docs/no-load.md` §20: `GoTitle` stopped tearing the rupture down and lost more than `HsEntry` gained, and `HsEntry` is the title overlay’s, not the image’s); BUGS.md #24 had just spent 24 on `xfpause.asm`’s call site, and §19’s `JSR SprSeedYcol` 3 before that. It was 70 (`&2FBA`) It was 70 (`&2FBA`) after no-load step 6's `BrDepackChain` (38 B), and 108 (`&2F94`) before that. It was 28 B (`&2FE4`) after `PARBRF` and `PARALOW` stopped being disc files that day and took their OSCLI strings with them, and 14 B (`&2FF2`) before. It was **0** from `b385cd6` until no-load step 4, which deleted `loadtitl`'s OSCLI and its string and gave 14 back; that is what funds BUGS.md #23. The pre-branch history: **25 B**, `code_end` `&2FE7`. hexwab's `sTmp` `EQUB` gave 1 back on 2026-09-03. Layer-9 DECISION 20's energy bar took 7 on 2026-09-02 (`pmEnergy` and its mirror); 31 B before. Layer-12 DECISION 6 took 51 the same day (two bank-6 trampolines, the 16-byte `DECK_DONE` and its clear); it was 82 B after hexwab's two patches and **3 B** before them. Historically the binding constraint |
| Bank 4 | **166 B** — measured 2026-09-10 (`bank4 ends &BF5A`), after issue #18's `SetupModeRegs` (every CRTC register, in `screen.asm`) took 29. It was **195 B** (`bank4 ends &BF3D`), after layer-14 DECISION 11 (issue #5: the ALERT lettering skips the floor dither) took 10. It was **205 B** — measured 2026-09-09, after `docs/no-load.md` §21 brought briefing page 5's second chunk (154) home to bank 6. It was **51** after §19's `SprSeedYcol` and its nine-byte seed took 20. It was 71: no-load step 6 put briefing page 5's second chunk (154) at its tail, and **its `colourMap` `ALIGN` pad is down to 10 bytes**, so there is no free ride left here — and `SprSeedYcol` is deliberately assembled AFTER `colours.asm` for that reason. It was 225 on the `no-load` branch — the pass of 2026-09-07 interned `drSprData`'s duplicate rotor and end rows for **+217** (`docs/no-load.md` §4c); it had **8**. **Packing bank 4 is not possible**: everything in it is read during play, so there is nowhere to depack to, and the disc already ZX0s the whole bank. `colourMap` dedup was built and measured **+1** — `tiledefs.asm`'s own `ALIGN` swallows every byte it frees — and reverted. Pre-branch history: 13 B on the gauge (2026-09-03) + `colourMap` `ALIGN` pad, **which is SPENT** (200 B in front of it cost the bank 259, measured; 16 B in front of it overflowed it in 2026-09-07's first attempt) |
| Bank 5 | **344 B** — measured 2026-09-09, and **it is not the tightest region in the machine any more**: §19 moved `drYcol0/1/2` into zero page, turning 320 `LDY drYcol,X` from abs,X into zp,X and deleting the bank's own copy of the table, for **+329 at no cycle cost whatever**. It was **15 B**. It is **UNFOLDED** (no-load step 6, `docs/no-load.md` §11m): `sprscan.asm` went home to bank 6 and paid for it. **The 613 bytes are still recoverable at 3 cycles a compiled row** by putting `0` back in `export_droids.py`'s `FOLD_TAIL` — independent of §19, and now not the first thing to reach for. Earlier (2026-09-08: **+1,229** from interning the duplicate compiled blocks, `docs/no-load.md` §11k, and before it **+756** from SCANSTEP tail folding, 70 compiled rows ending `JMP <tail>` rather than an inline `SCANSTEP` + `RTS`; `docs/no-load.md` §11j. It was 665 on the gauge before it) (2026-09-01: **+668** from the SCANSTEP deferred carry, 168 expansions at 4 B apiece; it was **6 B** immediately before that, the tightest region in the machine) |
| Bank 6 | **286 B** — measured 2026-09-10, after `SprAssignTr`'s rewrite took 53 (`docs/raster-timing.md`, "SprAssignTr made cheaper"); it was **338 B**, measured 2026-09-09, after the window-A budget took 63 (`satCapA` and the budget arms in `sprsplit.asm`, `docs/raster-timing.md` DECISION 2026-09-09); it was 401 after §21 took briefing page 5 back whole (313), and **714** before that, and still the largest hole in the machine. §19's `drYcol` move gave **+420** here (411 sites plus the table; bank 6 has the extra 91 because only a shifted glyph spills into column 2). It was 294. **UNFOLDED** (§11l): —613 for the unfold; then no-load step 6 took `sprscan.asm` back (—538) and gave up briefing page 5 (+313). Earlier (2026-09-09: —2,005 for `brfImg` and `lowImg`, the two front-end overlays and their copiers, which is what made them resident) (2026-09-08: **+1,139** from the same interning as bank 5, and **+756** before it from the tail folding) (2026-09-06: —112 for layer-12 DECISION 6's character filter, the cleared-deck stipple fix; 664 on the gauge before it) (2026-09-02: —75 for layer-9 DECISION 20's `PnEnergy`, and before it —183 for layer-12 DECISION 6 — `LvClearedMark`, the 64 B of `svdecks6.asm` and its scratch; 931 B before). **The bank with room, and the reason DECISION 6 could be built at all** |
| Bank 7 | **105 B, and the `ALIGN` pad is 18** — measured 2026-09-10 (`planChars` ends &B0EE), after issue #6's wash row order (`goOrder`, 24 B in `xfer.asm`) rode the pad; the tail did not move. It was **105 B with a pad of 42** (`xfer_end` &BF97), after layer-11f DECISION 19 (issue #16, typed initials) took 25 from the tail and gave the pad `hsPrev`'s 3. It was **130 B with a pad of 39** (`xfer_end` &BF7E), after layer-11f DECISION 18 (issue #17, two-cell initials) took 36 from the tail; `highscore.asm` is behind the `ALIGN`. It was **166 B with the same pad of 39** (`planChars` ends &B0D9, `planInk` &B100), after layer-9 DECISION 21 (issue #9, the database's back key) rode the pad for 134. It was **166 B with a pad of 173** — measured 2026-09-09, after §21 took briefing page 5 out of the pad (33 -> 208) and let `xfpause.asm` fold back into `xfer.asm` in front of it, riding the pad for nothing; it was 131 with a 33-byte pad, after BUGS.md #24’s `xfpause.asm` (35) and §20’s five bytes of title overlay; it was **171**, **and 33 B of `plandata.asm`'s `ALIGN` pad on top of it**: the pad was 208 and no-load step 6 put briefing page 5's first chunk (175) in it for nothing, exactly as `consolesel.asm` does in bank 4. it was 759 before the briefing's `brstream1` (604 packed) went in. The `no-load` branch's packing pass took it from 25 B to 3,021 (transfer board, lift screen, portrait pool, `poLut`; `docs/no-load.md` §4); step 3 SPENT 1,840 on the title artwork and the high-score screen, and step 4 a further 422 on the title overlay's image and `TiResident`. Before the branch it was 25 B, measured 2026-09-02 by bisecting a `SKIP` at `.LvStart7` |
| `PARBRF` (`&0400`, hard ceiling `&0800`) — **no longer a disc file, 2026-09-09: it rides in bank 6 as `brfImg` and `BrfResident` copies it down** | **12 B** (36 B before `BrTimeout`'s R8 blank, 56 B before the CTRL+R hook) |
| The title overlay (`&0900`, ceiling `&0C90` = `LOWBSS_ADDR`) | **526 B** — the overlay is 386 (`TITL_BYTES`, hand-maintained, and the `ASSERT` is what keeps it honest) and the region is 912. §20 grew it by 5, taking `GoTitle`’s teardown in. `&0800–&08FF` is NOT in it; see the note under the disc files below. Not a disc file since no-load step 4: the image is bank 7's |
| `PARAFNT` block | **16 B** before `SPR_SAVE` (`KeyDownIx` took 7, DECISION 5's `CN_STRS` 10) |
| Low overlay | `lowcode` **9 B** (its two raw `PAGEBANK`s became `JSR Pg*`), `lowcode2` 3 B, `lowbss` **0 B** (`sprCls` took the last 8, 2026-09-01) |
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
ALIGNs), and what is held in reserve for the next squeeze — `sprsplit.asm` to bank 5 (SPENT 2026-09-01, as the sprscan.asm split), SCANSTEP
tail folding (**SPENT 2026-09-08 at +756 a bank; that figure is now WRONG — §11k's interning collapsed 13 of the 70 sites the same day, so the fold is worth 613 a bank, and bank 6's was SOLD BACK on 2026-09-09, `docs/no-load.md` §11l**), `door.asm` to bank 4, the `hsfont` dedup (SPENT 2026-09-07, no-load step 3).

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

The four bank files **and `PARAFNT`** ship ZX0-compressed on disc (written by
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

**`PARALOW` AND `PARBRF` ARE NOT DISC FILES ANY MORE (2026-09-09), and both ship ZX0-packed
(§16's pack pass).** Both ride in bank 6 —
`lowImg` and `brfImg` — and `LowResident` / `BrfResident`, which live in that bank like
`TiResident` lives in bank 7, copy them down. **THERE ARE NO LOADS AFTER BOOT AT ALL** (no-load step 5, `docs/no-load.md` §17-§18):
`PARMAN` and the briefing's `PARASPR` reload went, and `PARAFNT` is loaded once in `.start`,
between `SetupMode` (whose `VDU 22` would clear it) and `TitleSeq` (which needs the MOS still to
own the machine). What made THAT
possible is that both overlays are **assembled ABOVE bank 6's block**, so the pack pass can take
their bytes and bank 6 can hold the stream: only the last bank block can be filled after the fact,
because each block `CLEAR`s and re-`ORG`s the same `&8000`, and bank 7 (the last) had 759 bytes
against the 1,931 these needed raw. The move cost **eight** constants their homes — beebasm
resolves constant assignments in file order — so `BR_PAGES`/`BR_ROW_LO`/`BR_ROW_HI`/`BR_XTRA0` are
generated into **`src/data/briefconst.asm`**, which `main.asm` includes from its header, and
`BR_CHAT_PRE`/`BR_PO_UNIT`/`BR_PO_OFS`/`BR_PO_ROW0` sit beside `UNIT_BYTES` with `ASSERT`s at
their old homes (`BR_PO_ROW0` is step 5's, when `briefman.asm` went bank-resident and its
`= DB_IMG_ROW` started reaching forward into bank 7).

The low overlay still lands on DFS's own workspace at `&0E00–&10FF` **and, via `lowcode2`, on the
MOS's extended vector table at `&0D9F+` — the route DFS 1.2's FILEV takes into its ROM**, so the
rule still holds: make ANY filing-system call after `PageLowIn` and it crashes through the
trampled vectors. **Nothing has to obey it any more, because nothing makes one** — every load is
in `.start`, before the first `PageLowIn`. `SaveDfsWs`, `RestoreDfsWs` and the 912-byte `dfsSave`
snapshot in bank 6 are gone with the loads they protected (step 5, 2026-09-09). `PARALOW` still stages on the panel at `LOW_STAGE` — the copier writes there and
`PageLowIn` takes it down from there, exactly as when `*LOAD` filled it.

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

**The title screen's DRIVER is a 397-byte overlay at `&0900`, and it is NOT a disc file** —
no-load step 4 (2026-09-07) put the image in bank 7 at `titlImg` and `TitleSeq` calls `TiResident`
to copy it down, at boot and again on the way back from a game over. It is still *assembled* at
`&0900` (beebasm's `COPYBLOCK` moves the bytes into the bank), because it runs there and is not
position-independent, and `TITL_BYTES` in `main.asm` is the hand-maintained size the `ASSERT`
guards. **It went to `&0900` from `&3000` in no-load step 3** — in the MODE 1 charset's ground, above `PARBRF`
at `&0400–&0800` and deliberately clear of `&0800–&08FF`, which is the MOS's sound workspace and is
chewed while the MOS owns IRQ1V (the PARBRF block in `main.asm` has the measurement). `&3000` and
the text font therefore survive the title now, which is what let the high-score screen's private
1,152-byte alphabet become a 72-byte remap into `textfont`. **The invariant that replaces it, and
no `ASSERT` can check it: `PARAFNT` must be resident whenever `HsRun` runs.** It is — only a
finished game arms it, and `GoTitle` reaches `TitleSeq` through `SetupPlain` rather than
`SetupMode` precisely so the `VDU 22` does not clear `&3000–&7FFF`. `docs/no-load.md` §6.

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
`bufcore.asm` holds exactly what those two cases need — `SetupMode`/`SetupRupture`, `SetCRTCStart`,
`SetCell` and the `rowMul`/`unitMul` tables — and its header states the rule. (`WrapBufFwd` was one of
them until 2026-09-02, when the strip's `LO(BUF_BASE) == 0` / `BUF_END == &8000` asserts reduced it to
a `BPL` and one `SBC` and it was inlined away; `bufcore.asm`'s header has the derivation.) **Read it before moving
anything else across.**

Geometry and hardware constants live in `main.asm` rather than beside the code that uses them,
because beebasm resolves constant assignments in file order and the included files need them.

**Three files in `src/data/` are gitignored and everything else there is committed:**
`brfimg.asm`, `lowimg.asm` and `krimg.asm` are the pack pass's output — compiler output, not
exporter output, and they differ between a DEV build and a `-Release` one, so committing them
left `git status` dirty after every release build. A fresh clone gets stubs from
`pack_overlays.py --ensure` and the loop fills them in; that is measured, not assumed.

The rest of `src/data/` is generated by the exporters in `tools/` — `export_bbc.py`, `export_droids.py`,
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
- `docs/build.md` — the two builds (`build.ps1` and the `Makefile`), what is overridable,
  the parts of the pipeline that are not a DAG, and the timings
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
  it — otherwise a build can lie about itself. **A RELEASE build prints `VERSION_LINE` in that
  line's place** ("Release Candidate #3" as of 2026-09-03) — the string is defined beside `DEV`
  at the top of `main.asm`; bump the number per candidate, and change it to "Release Version
  1.0" at ship.
