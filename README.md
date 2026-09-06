# Paradroid — BBC Micro

A port of Andrew Braybrook's *Paradroid* (Commodore 64, 1985) to the **BBC Micro Model B**,
written in 6502 assembly for [BeebASM](https://github.com/stardot/beebasm).

You are a service droid loose on a hostile starship. You can shoot the other droids, but you are
weak and they are not — so the real weapon is the **transfer**: touch a droid, win a duel on a
logic-circuit board, and you *become* it, with its weapon, its speed and its armour. Clear a deck,
clear the ship, move on to the next one. It runs until you die.

The port plays start to finish. The deck hardware-scrolls eight ways under you, droids patrol and
fight (each other as well as you), doors open and lifts run between the decks, the console carries
the ship diagram, deck plan and droid database, the transfer minigame plays, and the front end —
title, briefing, five-page scrolling manual, high-score table, game over — is the original's. Sound
is an SN76489 driver with every in-game trigger wired.

It is a faithful port rather than a remake: the C64 disassembly is the specification, and the
levels, tiles, sprites, text, droid statistics and movement constants are the original's data,
converted mechanically. Where the BBC's hardware forces a change, the aim is to port the *decision*
the original made rather than approximate the effect.

## Requirements

| | |
|---|---|
| Machine | BBC Model B, B+ or Master 128, with **4 × 16K sideways RAM banks** — any four; they are probed at boot, highest first (a Master has them at 4–7) |
| Display | MODE 1 |
| Media | A DFS disc (single-sided, 200K) |

Any emulator configured with four sideways RAM banks will run it. On a machine it cannot drive, the
loader says so and stops rather than crashing.

The port uses no 65C12 instructions and no Master-only hardware, so the Master runs the same code as
a B — and it has been **tested on a real Master**. Testing on real Model B and B+ hardware is still
outstanding; see [`PLAN.md`](PLAN.md).

## Building

There is no pre-built image in the repository. Put `beebasm.exe` in `bin/`, then:

```powershell
.\build.ps1           # assemble into build/
.\build.ps1 -Run      # assemble and launch in b-em
.\build.ps1 -Release  # the build to give to other people: loading intro, no debug flags
```

`make.bat` and `make.sh` are thin wrappers over the same script, for cmd and sh (`make run` works).
Python 3 and Pillow are needed for the build's data stages.

Everything lands in `build/`. Hand an emulator **`build/PARADROID-200K.SSD`** — the padded copy,
which is what every published build is.

> **beebasm's own output is not bootable.** The build is several stages: the intro-manual text is
> converted, beebasm assembles a raw image, and `tools/make_disc.py` then ZX0-compresses the
> sideways-RAM bank files and lays the disc out in the order the loader expects. Running beebasm by
> hand produces `build/PARADROID-raw.ssd`, which hangs at the first bank load. Use the scripts.

DFS filenames are limited to seven characters, so the executable on disc is `PARA`.

## Controls

| | |
|---|---|
| **Z** / **X** | left / right |
| **K** / **M** | up / down. On the lift screen they move along the shaft; on the high-score entry they walk the alphabet; on the intro manual **K** pauses the scroll and **M** doubles it |
| **L** | fire. On a lift platform it opens the deck-selection screen (fire again commits); it commits an initial on the high-score entry, and starts the game from the title or the manual |
| **SPACE** | transfer — hold it and a transfer triggers on contact without needing a direction. Also starts the game |
| **ESCAPE** | self-destruct, ending the game. The port's own addition; the C64 has no abort |
| **CTRL** + cursor up/down | volume. **CTRL+Q** mutes, **CTRL+P** pauses (**P** unpauses) |

The six play controls are **redefinable**: let the title time out into the intro manual and press
**CTRL+R**. It asks for a key for each of left, right, up, down, fire and transfer in turn, and the
choice holds everywhere — play, the console, the transfer game, the manual, the title. Everything
binds except ESCAPE and CTRL; ESCAPE abandons the run and puts the old set back. Definitions last
until the machine is BREAKed; nothing is written to disc.

Debug builds add further keys, all of them behind CTRL so a rebound control cannot fire one by
accident. `!BOOT` lists whichever are compiled in; the flags are at the top of `src/main.asm`.

## How it works

| | |
|---|---|
| Display | MODE 1, four colours: a 4-row static panel above a 320 × 120 play area, split by a **three-cycle vertical CRTC rupture**. The panel has its own palette, swapped at the cycle boundary |
| Play area | A 10K circular strip at `&5800` with a 10K hardware wrap, scrolled by the CRTC — 4 px horizontally, one scanline vertically |
| Sprites | A compiled blitter with four pre-shifted variants, spread across two sideways banks |
| Game loop | Locked to two fields a pass, 25 Hz |
| CPU | Plain 6502 (`CPU 0`) — no 65C12 opcodes |

MODE 1 was chosen because it maps the C64 1:1 at 320 pixels across with four colours. The C64 mixes
hires and multicolour cells on one screen; MODE 1 has no attribute constraints and accommodates
both, so the artwork converts mechanically with nothing redrawn. The BBC's palette is fully
saturated where the C64's is not, so deck floors are dithered to half intensity in a 2×2 checker —
which incidentally buys a fifth tone in a four-colour mode, and three decks spend it on the grey
their C64 floor actually is.

Main RAM is the binding constraint throughout: the code image runs to within a couple of dozen
bytes of its ceiling, and the four sideways banks carry the level data, the blitter, the panel and
console, the transfer game and the sound driver.

## Repository layout

```
src/               BBC Micro 6502 source (BeebASM). src/data/ is generated by tools/ but tracked,
                   so the tree assembles without a local copy of the C64 listing
pdloader/          The loading intro, by Chris Evans (scarybeasts) — a vendored drop, kept verbatim
tools/             Python extraction and conversion tools for the C64 data
annotate.py        Generates the annotated C64 disassembly
docs/              Per-layer working notes: the measurements, the dead ends, the hardware facts
docs/decisions.md  Why things are as they are, including which Paradroid the listing is
PLAN.md            The live plan — state of the port, memory map, what is outstanding
BUGS.md            Open defects, with the evidence and what has been ruled out
ANNOTATION.md      Analysis of the C64 original: memory map, subroutines, hardware, data tables
```

## The original game's data

**The C64 game's code and data are not in this repository.** They remain the copyright of Andrew
Braybrook and Hewson Consultants. What *is* committed is the converted output in `src/data/` — the
data the port needs, in BeebASM form — so the game builds without them.

To re-run the extraction tools yourself you must supply your own copy of `paradroid_ce.lst`, a
disassembly of the C64 binary, in the project root.

> **Which version?** That listing is the **1985 Hewson original / 1986 Competition Edition**
> lineage, verified by unpacking all four C64 releases and diffing them against it. It is *not*
> Paradroid Redux or Heavy Metal, both of which relocate everything and match at ~1–3%. The two
> lineages share their movement constants byte for byte — the Competition Edition is faster because
> it runs more game-loop iterations per second, not because droids move further per iteration. See
> [`docs/decisions.md`](docs/decisions.md).

With the listing in place:

```
python annotate.py              # -> paradroid_ce_annotated.asm
python tools/rip_graphics.py    # sprites and character sets
python tools/rip_levels.py      # deck maps and tile definitions
python tools/rip_sideview.py    # ship cross-section
python tools/rip_screens.py     # title screen and transfer board
```

Those write to `tools/output/` and are for inspection. The `tools/export_*.py` scripts are the ones
that feed the build, writing BeebASM source into `src/data/` — tiles, decks and palettes, droid
sprites and statistics, effects, fonts, strings, console icons, the transfer board, the lift
screen's cross-section, the droid database, the title screen, the droid portraits, the sound tables
and the loading intro's picture. `build.ps1` does **not** run them, so a tool or a palette edit
means running the tool and committing what it produces.

Two are special cases: `tools/export_briefing.py` decodes the C64's intro manual into
`src/data/briefing.txt`, which is tracked and hand-editable, and refuses to overwrite it without
`--force`; `tools/make_briefing.py` converts that text on every build, and `build.ps1` does run it.

[`docs/graphics.md`](docs/graphics.md) is the reference for where each piece of C64 data lives,
what format it is in, and which tool reads it.

## Status

The game is complete and playable. [`PLAN.md`](PLAN.md) is the live list of what remains — chiefly
the balance-and-fidelity pass and testing on real hardware — and each finished layer keeps its
working notes in [`docs/`](docs/), including several options that were costed and deliberately
rejected.

## Credits

*Paradroid* was written by **Andrew Braybrook** and published by **Hewson Consultants** in 1985. It
is his game; this is an unaffiliated hobbyist port, not endorsed by or connected with either.

The loading intro — the three-robots picture, the lightning and the three-channel sample player —
is by **Chris Evans (scarybeasts)**, vendored in [`pdloader/`](pdloader/) and kept verbatim so his
next version arrives as a clean diff. The changes this port makes to it are marked `\ PORT:` at
each site and listed in `pdloader/README.md`.

Compression is [ZX0](https://github.com/einar-saukas/ZX0) by Einar Saukas. The assembler is
[BeebASM](https://github.com/stardot/beebasm) by Rich Talbot-Watkins.

**How it was written.** The port's code is entirely the work of **Claude** (Anthropic's Claude
Code), written under the direction of **Kieran Connell** — the 6502 source in `src/`, the Python
extraction and conversion tools, the build scripts and the documentation alike. The direction,
the design decisions, the verification against the original and the playtesting are his; the
typing is Claude's. `pdloader/` is the exception, being Chris Evans' own work, vendored.

**There is deliberately no licence file.** This repository contains material that is not ours to
license — the converted game data in `src/data/`, the vendored loading intro in `pdloader/` — so no
licence is offered over the tree as a whole, and none should be inferred. It is published to be
read and built, not to be relicensed. See [`docs/decisions.md`](docs/decisions.md).
