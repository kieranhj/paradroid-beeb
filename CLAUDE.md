# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

A port of the C64 game *Paradroid* (Andrew Braybrook, 1985) to the **BBC Micro Model B**, in
6502 assembly for the **BeebASM** assembler. A C64 disassembly has been reverse-engineered and
annotated, and the port plays: a deck scrolls eight ways under a droid you steer, with a pool of
seven sprites and a static panel above.

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
| Machine | BBC Model B / B+ with **3 × 16K sideways RAM banks** (4 = data + level draw, 5 and 6 = the blitter's four compiled shifts) |
| CPU | Plain 6502 — `CPU 0` in BeebASM, no 65C12 opcodes |
| Display | MODE 1, 4 colours. **Not a plain frame:** a 5-row static panel at `&4800` above a 320 × 120 scrolled play area, driven by a three-cycle vertical rupture |
| Play area | 10K circular strip at `&5800`, **10K hardware wrap**, scrolled by the CRTC — 4 px horizontally, 1 scanline vertically |
| Game loop | `FRAME_LOCK` = 2 fields a pass, 25 Hz — a floor, not a fixed length: a pass that overruns carries on rather than waiting out another field |

## Build

```powershell
.\build.ps1          # assemble to PARADROID.SSD
.\build.ps1 -Run     # assemble and launch in b-em
```

DFS filenames are max 7 characters — the executable on disc is `PARA`.

**beebasm writes its progress and success messages to stderr.** In PowerShell that renders as an
error, and if you pipe or redirect it under `$ErrorActionPreference = 'Stop'` it raises
`NativeCommandError` and `build.ps1` throws even though the assembly succeeded. Check the exit
code. The reliable way to capture a build log is `./bin/beebasm.exe ... 2>&1` from the Bash tool,
not from PowerShell.

**jsbeeb will not boot an unpadded SSD.** It hangs in the DFS FDC poll loading `PARASPR`, because
beebasm's image ends mid-track and jsbeeb will not read the last partial one. Pad a copy to 200K
before handing it to an emulator or publishing it.

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

**`PLAN.md` holds the authoritative map — read it there, and take the addresses from the `beebasm`
output rather than from any document.** In outline:

| Region | Contents |
|---|---|
| ZP `&00–&8F` | All used. The map is in `main.asm`. `&90` up belongs to the OS |
| `&0400–&0C90` | MODE 1 charset, built at deck load — reclaimed OS workspace |
| `&1100–…` | Code (`PARA`), starting below DFS's `PAGE`. Ends `&27DA`; `&27DA–&3000` is free |
| `&3000–&36FF` | Sprite background save areas, one page per slot |
| `&3800–&3C00` | Tile map |
| `&4800–&547F` | Panel — 5 rows × 640, displayed by rupture cycle 1 |
| `&5500–&57FF` | Character-address and sprite-mask tables, built at startup |
| `&5800–&7FFF` | Play buffer: circular strip, 16 rows × 640 |
| SWRAM bank 4 | `PARADAT` — tiles, levels, palettes, droid game data, **the level-draw code and the droid AI** |
| SWRAM bank 5 | `PARASPR` — the blitter, shifts 0 and 1 px |
| SWRAM bank 6 | `PARSPR2` — shifts 2 and 3 px, same layout |

**Only one bank is visible at a time.** `SprRestoreAll` and `SprDrawAll` page their own bank in and
the data bank back out around themselves, so `SWRAM_DATA` is the resting state. This is safe only
because the two halves are never wanted at once and **the IRQ reads neither** — check that again
before putting anything else in a bank.

Both banks are staged through `&3000` by `*LOAD` and copied up, because the MOS has the DFS ROM
paged in at `&8000` during a filing-system call. `*LOAD` must also happen **before** `InstallIrq` —
taking over IRQ1V stops the MOS servicing the filing system.

## Source organisation (`src/`)

Single-pass flat build, everything included from `main.asm`. No linker.

`main.asm` holds the constants, the zero page map, the main loop and the IRQ dispatch, and includes
everything else. **Everything in `src/` is in the build** — the five inherited Master/HAL files that
were not have been deleted, so nothing there is dead. Keep it that way.

**Four files assemble into SWRAM bank 4, not main RAM**: `screen.asm`, `scroll.asm`, `level.asm` and
`droid.asm` are included from inside the `PARADAT` block, next to the tile, deck and waypoint data
they read. That costs no
paging, because the data bank is the resting state. The rule it depends on is one-way and undiagnosed
if broken — bank code may call main RAM freely, but main RAM may call *in* only with `SWRAM_DATA`
paged, which is false at startup before the bank is loaded and inside `SprDrawAll`/`SprRestoreAll`.
`bufcore.asm` holds exactly what those two cases need — `SetupScreen`, `SetCRTCStart`, `WrapBufFwd`,
`SetCell` and the `rowMul`/`unitMul` tables — and its header states the rule. **Read it before moving
anything else across.**

Geometry and hardware constants live in `main.asm` rather than beside the code that uses them,
because beebasm resolves constant assignments in file order and the included files need them.

`src/data/` is generated by `tools/export_bbc.py` and `tools/export_droids.py` and is gitignored —
it is converted game artwork. Regenerate it rather than editing it.

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
  `DEBUG_VSYNC`, `DEBUG_TIME`, `DEBUG_POS`, `DEBUG_ENERGY`. Each carries a header explaining what it shows and
  how to read it; `DEBUG_TIME` in particular documents how to take a cycle measurement that means
  something, including why only one call site may be instrumented at a time.
