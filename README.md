# Paradroid — BBC Micro

A port of Andrew Braybrook's *Paradroid* (Commodore 64, 1985) to the BBC Micro Model B.

This is a work in progress at an early stage. See [`PLAN.md`](PLAN.md) for the layered build plan,
decisions taken so far, and current status.

## Target

| | |
|---|---|
| Machine | BBC Model B / B+ with 2 × 16K sideways RAM banks |
| Display | MODE 1, 320×200, 4 colours, 16K screen wrap based at `&4000` |
| Assembler | [BeebASM](https://github.com/stardot/beebasm) |

MODE 1 was chosen because it maps the C64 original 1:1 at 320 pixels across with four colours. The
C64 mixes hires and multicolour cells on the same screen — multicolour is selected per cell by bit
3 of the colour RAM nibble — and MODE 1 accommodates both, having no attribute constraints. Artwork
converts mechanically from the ripped data with nothing redrawn.

## Approach

No hardware abstraction layer. The port is built one layer at a time, each verified running in an
emulator before the next begins:

0. **Toolchain and screen geometry** — ✅ done
1. Graphics data pipeline
2. Static deck render
3. Scroll spike — *the key design decision*
4. Sprite blitter
5. Player movement
6. Droids
7. Combat
8. Doors, lifts, decks
9. HUD and console
10. Transfer minigame
11. Sound, title, polish

## Building

Put `beebasm.exe` in `bin/`, then:

```powershell
.\build.ps1          # assemble to PARADROID.SSD
.\build.ps1 -Run     # assemble and launch in b-em
```

Or, without PowerShell:

```
make.bat            :: assemble to PARADROID.SSD
make.bat run        :: assemble and launch in b-em
./make.sh           # same, for sh / Git Bash / Linux
```

Both honour `BEEBASM` and `BEM` environment variables if your tools live elsewhere.

Or directly:

```
beebasm -i src/main.asm -do PARADROID.SSD -boot PARA -v
```

The result is a bootable DFS disc image. Note that DFS filenames are limited to 7 characters, so
the executable on disc is `PARA`.

## Repository layout

```
src/            BBC Micro 6502 source (BeebASM)
tools/          Python data-extraction tools (see below)
annotate.py     Generates the annotated C64 disassembly
docs/           Per-layer working notes, plus graphics.md — the C64 data reference
PLAN.md         Layered build plan, memory map, and status
ANNOTATION.md   Analysis of the C64 original: memory map, subroutines, hardware
```

## Original game data

The C64 game's code and data are **not** included in this repository — they remain the copyright of
Andrew Braybrook and Hewson Consultants. To run the extraction tools you need to supply
`paradroid_ce.lst` in the project root.

> **Which version?** That listing is a disassembly of the **1985 Hewson original / 1986 Competition
> Edition** lineage — verified by unpacking all four C64 releases with `tools/unpack_prg.ps1` and
> diffing them against it. Everything ported so far — level data, tile definitions, sprites, game
> logic — is original-lineage. It is *not* Paradroid Redux or Heavy Metal, both of which relocate
> everything and match the listing at ~1–3 %. See [`docs/decisions.md`](docs/decisions.md).

With that in place:

```
python annotate.py              # -> paradroid_ce_annotated.asm
python tools/rip_graphics.py    # sprites and character sets
python tools/rip_levels.py      # all 16 deck maps and tile definitions
python tools/rip_sideview.py    # ship cross-section
python tools/rip_screens.py     # title screen and transfer minigame board
```

All output lands in `tools/output/`. The tools require Python 3 and Pillow.

## Credits

*Paradroid* was written by Andrew Braybrook and published by Hewson Consultants in 1985. This port
is an unaffiliated hobbyist project.
