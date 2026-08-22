# Paradroid — BBC Micro

A port of Andrew Braybrook's *Paradroid* (Commodore 64, 1985) to the BBC Micro Model B.

It plays, start to finish. The title screen comes up, the deck hardware-scrolls eight ways under a
droid you steer, a pool of eight sprites runs over it, doors open as you walk into them and lifts
carry you between decks — so the whole ship is traversable. Droids patrol it, shoot at you and can
kill you; you shoot back, and score. They kill *each other* too, because a droid's shot and a
droid's explosion hurt whatever else they touch. The 711 and the 742 carry the disruptor — an area
weapon that hits everything on screen at once and costs the firer as well — and so do you, once you
have taken one. Recharge pads turn under you and the ALERT signs light as the ship gets angrier.
The status line and the console are the original's, down to the deck being called `Reactor` rather
than `5`, and the console carries the ship diagram, the deck plan and the droid database. The
transfer minigame plays too: prime with fire, touch a droid, pick a side and fight the circuit board
for it — win and you *are* that droid, with its weapon and speed. It has a voice, through an
SN76489 driver with every in-game trigger wired. And it has the droid information screens the
original opens and closes on: the 001 briefing that starts a game, the two pages the transfer shows
you before the board, and the 999 Command Cyborg behind "Transmission / Terminated" when the ship
burns out under a dissolve. The front end is the original's too: a great (or terrible) score gets
the three-initial entry under a panel reading "game over", the table survives into the next game,
and leaving the title alone drops into the five-page intro manual — smooth-scrolled at the C64's
own speeds and dwells, with the live score table and a random droid portrait on its last page. The
manual's text is hand-editable (`src/data/briefing.txt`), and every front-end screen wears the
palette of the last deck played.

**What is left** is the balance and visual passes, and trimming the front end's disc loads. See [`PLAN.md`](PLAN.md) for the layered build plan, the memory map, decisions taken
and current status.

## Target

| | |
|---|---|
| Machine | BBC Model B / B+ with 4 × 16K sideways RAM banks (banks 4–7, the Master's own numbering) |
| CPU | Plain 6502 (`CPU 0` — no 65C12 opcodes) |
| Display | MODE 1, 4 colours. A 4-row static panel at `&4A00` above a 320 × 120 play area, driven by a three-cycle vertical rupture. The panel has its own palette, swapped at the cycle boundary |
| Play area | 10K circular strip at `&5800` with a 10K hardware wrap, scrolled by the CRTC — 4 px horizontally, 1 scanline vertically |
| Game loop | Locked to 2 fields a pass, 25 Hz |
| Assembler | [BeebASM](https://github.com/stardot/beebasm) |

MODE 1 was chosen because it maps the C64 original 1:1 at 320 pixels across with four colours. The
C64 mixes hires and multicolour cells on the same screen — multicolour is selected per cell by bit
3 of the colour RAM nibble — and MODE 1 accommodates both, having no attribute constraints. Artwork
converts mechanically from the ripped data with nothing redrawn.

## Controls

| | |
|---|---|
| Z / X | left / right |
| K / M | up / down — and, on the lift screen, move along the shaft. On the high-score entry they walk the alphabet; on the intro manual K pauses the scroll and M doubles it and skips the dwells |
| L | fire; on a lift platform it opens the ship's deck-selection screen, and fire again commits. It commits an initial on the entry, and starts the game from anywhere in the manual |
| Cursor up/down | debug deck hop |
| ESCAPE | self-destruct — ends the game. The port's own; the C64 has no abort |
| SPACE | force a full redraw (also the verification oracle) |

Some keys are debug builds only and are listed by `!BOOT` when they are compiled in — see the
`DEBUG_*` flags at the top of `src/main.asm`.

## Approach

No hardware abstraction layer. The port is built one layer at a time, each verified running in an
emulator before the next begins:

0. **Toolchain and screen geometry** — ✅ done
1. **Graphics data pipeline** — ✅ done
2. **Static deck render** — ✅ done
3. **Scroll** — ✅ done; *the key design decision*
4. **Player movement** — ✅ done
5. **Droid movement** — ✅ done; a compiled sprite blitter across two banks
6. **Droids** — ✅ done
7. **Combat** — ✅ done; including the disruptor, friendly fire and the animated deck tiles
8. **Doors, lifts, decks** — ✅ done, taken ahead of 6 and 7 so droid AI has a ship to route through
9. **HUD and console** — ✅ done
10. **Transfer minigame** — ✅ done; in a fourth sideways bank, with its two pre-game info screens
11. **Title, game over, sound and the droid screens** — ✅ done: the title, the death and game-over
    sequence, the SN76489 sound driver, the four information screens, and the front end — the
    high-score entry and the scrolling intro manual, which burbles to itself as it scrolls just
    as the original's does. A faster reload out of the manual is the piece outstanding
12. Balance, fidelity and feel
13. **Memory and machine compatibility** — the RAM pass ✅ done; sideways-RAM detection and
    testing on real machines outstanding
14. Visual pass — the final palettes

Each completed layer keeps its working notes in [`docs/`](docs/) — the measurements, the dead ends
and the hardware facts bought the hard way, including several options that were costed and
deliberately rejected.

## Building

Put `beebasm.exe` in `bin/`, then:

```powershell
.\build.ps1          # assemble into build/
.\build.ps1 -Run     # assemble and launch in b-em
```

Everything it produces goes in `build/`: `PARADROID.SSD`, a 200K-padded copy for emulators, and
beebasm's assembly listing. `make.bat` and `make.sh` are thin wrappers over the same script
(`make run` works), for cmd and sh respectively.

**The build is three stages and all of them matter**: `tools/make_briefing.py` converts the
hand-editable intro-manual text (`src/data/briefing.txt` — edit it freely and rebuild), beebasm
assembles a *raw* image, and `tools/make_disc.py` ZX0-compresses the sideways-RAM bank files and
lays the disc out for the loader. **beebasm's direct output is not bootable** — the loader expects
the compressed layout and hangs at the first bank load — so there is no meaningful way to build
with beebasm alone; use the scripts.

`main.asm` assembles its own `!BOOT`, carrying the build stamp and the list of debug flags that
are on, so nothing may pass `-boot`. The rest of `src/data/` is converted game artwork and so is
not in the repository — generate it with the `tools/export_*.py` scripts (see below) before
assembling.

The result is a bootable DFS disc image. Note that DFS filenames are limited to 7 characters, so
the executable on disc is `PARA`.

> **jsbeeb will not boot an unpadded SSD.** It hangs in the DFS FDC poll, because an image that
> ends mid-track leaves jsbeeb refusing to read the last partial one. The build writes the padded
> `PARADROID-200K.SSD` for you — give jsbeeb that one.

## Repository layout

```
src/            BBC Micro 6502 source (BeebASM); src/data/ is generated and gitignored,
                except briefing.txt — the hand-editable intro-manual text, which is tracked
tools/          Python data-extraction and conversion tools (see below)
annotate.py     Generates the annotated C64 disassembly
docs/           Per-layer working notes, plus graphics.md — the C64 data reference
PLAN.md         Layered build plan, memory map, and status
BUGS.md         Open defects, with the evidence and what has been ruled out
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
>
> The two lineages also share their movement constants byte for byte: the Competition Edition is
> faster because it runs more game-loop iterations per second, not because droids move further per
> iteration.

With that in place:

```
python annotate.py              # -> paradroid_ce_annotated.asm
python tools/rip_graphics.py    # sprites and character sets
python tools/rip_levels.py      # all 16 deck maps and tile definitions
python tools/rip_sideview.py    # ship cross-section
python tools/rip_screens.py     # title screen and transfer minigame board
```

Those write to `tools/output/` and are for inspection. The two that feed the build write BeebASM
source into `src/data/`:

```
python tools/export_bbc.py        # tiles, decks, palettes -> src/data/
python tools/export_droids.py     # droid sprites and game data -> src/data/
python tools/export_effects.py    # bullet and explosion frames -> src/data/
python tools/export_font.py       # the $7000 text font and the status box -> src/data/
python tools/export_strings.py    # the $C000 name table -> src/data/
python tools/export_icons.py      # the console's menu icons -> src/data/
python tools/export_droidicon.py  # the console's droid icon -> src/data/
python tools/export_xfer.py       # the transfer board, three ownership sets -> src/data/
python tools/export_sideview.py   # the lift screen's ship cross-section -> src/data/
python tools/export_droidinfo.py  # the droid database's stats and descriptions -> src/data/
python tools/export_title.py      # the title screen's own glyphs and RLE -> src/data/
python tools/export_portraits.py  # the 48 x 84 droid portrait pool -> src/data/
python tools/export_sound.py      # the effect and instrument tables -> src/data/
```

The tools require Python 3 and Pillow. Regenerate `src/data/` rather than editing it.

## Credits

*Paradroid* was written by Andrew Braybrook and published by Hewson Consultants in 1985. This port
is an unaffiliated hobbyist project.
