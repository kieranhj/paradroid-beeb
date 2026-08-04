# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

A port of the C64 game *Paradroid* (Andrew Braybrook, 1985) to the **BBC Micro Model B**, in
6502 assembly for the **BeebASM** assembler. A C64 disassembly has been reverse-engineered and
annotated; the port itself is at an early stage.

**Source-of-truth caveat:** `paradroid_ce.lst` — and therefore `ANNOTATION.md`, `GRAPHICS.md`, and
everything extracted by `tools/` — is a disassembly of **Paradroid Redux**, a community-extended
version, *not* the 1985 Hewson original. All ported data and logic currently derives from Redux.
Where behaviour or data might have been changed by Redux, say so rather than describing it as "the
original". The original release's `.prg` can be disassembled separately if a clean reference is
needed.

**`PLAN.md` is the live planning document.** Read it before starting work — it records decisions
taken, per-layer status, and hardware facts confirmed by measurement. Update it as layers land.

## Working approach

**No hardware abstraction layer.** An earlier iteration of this project designed a HAL up front;
that was explicitly rejected. Build one layer at a time, get each working and visible in the
emulator before starting the next, and revise `PLAN.md` as you go.

**Do not write hardware code from recalled facts.** The jsbeeb MCP is connected — set the
registers, look at the screen, read memory back, confirm, then build on it. The retired
`src/hal_video.asm` is what happens otherwise: unverified CRTC arithmetic with `TODO: verify in
emulator` comments and a half-finished derivation in the middle of it.

## Target

| | |
|---|---|
| Machine | BBC Model B / B+ with 2 × 16K sideways RAM banks |
| Display | MODE 1, 320×200, 4 colours, 16K wrap based at `&4000` |
| CPU | Plain 6502 — `CPU 0` in BeebASM, no 65C12 opcodes |

## Build

```powershell
.\build.ps1          # assemble to PARADROID.SSD
.\build.ps1 -Run     # assemble and launch in b-em
```

DFS filenames are max 7 characters — the executable on disc is `PARA`.

Note: beebasm writes its success message to stderr, which PowerShell renders as an error. Check
the exit code, not the presence of stderr output.

## Confirmed hardware facts (measured, not assumed)

- **CRTC start address = screen address ÷ 8.** Base `&4000` → R12/R13 = `&0800`.
- Screen geometry: R6 = 25 rows, R7 = 31; R4 = 38 / R5 = 0 left alone to preserve 312
  scanlines at 50 Hz. Screen occupies exactly `&4000–&7E7F` (16000 bytes).
- Pixel address: `addr = &4000 + (y DIV 8)*640 + (x DIV 4)*8 + (y MOD 8)`.
- MODE 1 byte encoding: pixel *n* takes bit `7-n` (high colour bit) and bit `3-n` (low bit).
  Solid colour 0/1/2/3 = `&00`/`&0F`/`&F0`/`&FF`.
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

## Memory budget

| Region | Size | Contents |
|---|---|---|
| ZP (`&00–&8F`, `&A8–&AF`) | ~150 B | hot variables. C64 used ~206 B; the excess demotes to page 4 |
| `&0400–&0CFF` | ~2.2 K | reclaimed OS workspace: BASIC, sound/printer buffers, UDK, UDC |
| `&1100–&3FFF` | 11.75 K | main code + resident data — **code can start at `&1100`, not `&1900`** |
| `&4000–&7E7F` | 16 K | MODE 1 screen |
| SWRAM bank 0 | 16 K | converted tiles, sprites, level RLE, metadata |
| SWRAM bank 1 | 16 K | paged code: transfer minigame, console screens, side view |

`&3000–&3FFF` is reclaimed by rebasing the screen — verified free.

## Source organisation (`src/`)

Single-pass flat build, everything included from `main.asm`. No linker.

Currently `main.asm` contains Layer 0 only (screen geometry test). `hardware.asm`,
`zeropage.asm` and `macros.asm` are inherited scaffolding pending rework for the Model B budget.
`hal_video.asm` and `hal_irq.asm` are **retired** — they target the Master 128 in MODE 2 with
shadow-RAM double buffering. Do not build on them.

## Reference documents

- `PLAN.md` — the live plan; decisions, layers, status
- `ANNOTATION.md` — analysis of the C64 original: memory map, subroutines, hardware, data tables
- `GRAPHICS.md` — graphics extraction reference for the MODE 1 conversion
- `C:\Users\khcon\OneDrive\BEEB\Projects\llm-beeb-wiki` — BBC hardware knowledge base; consult for
  hardware queries rather than parsing a PDF of the Advanced User Guide
- `paradroid_ce.lst` — raw C64 disassembly (not in the repo; supply locally)
- `paradroid_ce_annotated.asm` — annotated disassembly, generated by `annotate.py`

## Assembly conventions

- BeebASM syntax: labels prefixed with `.`, comments with `\`, hex with `&`
- Plain 6502 only (`CPU 0`)
- Where practical, keep variable names matching `ANNOTATION.md` for cross-referencing against
  the C64 original
