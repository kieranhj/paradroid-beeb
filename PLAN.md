# Paradroid → BBC Micro Model B: Port Plan

Living document. Revised as each layer lands.

## Decisions taken

| Decision | Choice | Date |
|---|---|---|
| Target machine | BBC Model B / B+ with **2 × 16K sideways RAM banks** | 2026-08-04 |
| Screen mode | MODE 1, 320×200, 4 colours, 16K wrap at `&4000–&7FFF` | 2026-08-04 |
| Scrolling | **Undecided** — to be proven by spike in Layer 3 | 2026-08-04 |
| Architecture | No HAL. Build one working layer at a time, verified in the emulator before moving on. | 2026-08-04 |

### Why MODE 1

The C64 map graphics are 1bpp hires line art at the full 320px width (see `tools/output/tiles.png`),
and the sprites are multicolour with 2-screen-pixel-wide logical pixels. MODE 1 maps both 1:1:

| | C64 | MODE 1 |
|---|---|---|
| Map character | 8×8 px, 1bpp | 8×8 px, 1:1 |
| Tile (4×4 chars) | 32×32 px | 32×32 px, 1:1 |
| Multicolour sprite pixel | 2 screen px | exactly 2 px |
| Display | 320×200 | 320×200 |

Consequence: tiles, sprites, title screen and transfer board all convert **mechanically** from the
ripped C64 data. No artwork is redrawn. The cost is a 4-colour budget where 5 are wanted
(background + map colour + 3 sprite tones); resolved by sharing the map colour with a sprite tone,
or by reprogramming the palette at the HUD split.

MODE 2 was rejected: 8 colours the game barely uses, in exchange for redrawing every tile at half
width and breaking the 32×32 tile aspect ratio.

## Source material: which Paradroid?

The listing this port is built from (`paradroid_ce.lst`) is a disassembly of **Paradroid Redux**, a
community-extended version — **not** the 1985 Hewson original. Everything downstream of it inherits
that: `ANNOTATION.md`, `GRAPHICS.md`, and all data extracted by `tools/` (sprites, charsets, the 16
deck maps, tile definitions, side view, title screen, transfer board).

Practically this means the port currently reproduces *Redux*. Not a problem for Layers 0–4, which
are pipeline and rendering work where any version would do. It could matter later:

| Layer | Possible divergence |
|---|---|
| 2 — deck render | Redux may have altered or added deck maps |
| 6 — droids | droid roster, stats, AI tuning |
| 7 — combat | scoring tables, alert behaviour |
| 10 — transfer | circuit-puzzle rules or board layout |

**If a clean reference is needed:** obtain the original release's `.prg` and disassemble it
separately, then diff the data tables against the Redux extraction. Not required yet — noted so
that an unexpected difference from remembered C64 behaviour is diagnosed rather than debugged.

Decide explicitly before Layer 6 whether the target is Redux fidelity or original fidelity.

## Memory budget

| Region | Size | Contents |
|---|---|---|
| ZP (`&00–&8F`, `&A8–&AF`) | ~150 B | hot game variables. C64 used ~206 B — the excess demotes to page 4. |
| `&0100–&01FF` | 256 B | stack |
| `&0400–&0CFF` | ~2.2 K | reclaimed OS workspace: BASIC, sound/printer buffers, UDK, UDC |
| `&0E00–&3FFF` | 12.5 K | main code + resident data (requires DFS displaced after load) |
| `&4000–&7FFF` | 16 K | MODE 1 screen, 320×200 |
| SWRAM bank 0 | 16 K | converted tiles, sprites, level RLE, metadata |
| SWRAM bank 1 | 16 K | paged code: transfer minigame, console/info screens, side view |

Open risk: sprite data in MODE 1 with pre-shifted copies runs 30–60K depending on how many shift
variants and whether masks are stored or generated. May force a third bank or runtime shifting.
Quantify at Layer 4.

## Layers

Each layer ends with something visibly working in b-em. Nothing moves on until it does.

### Layer 0 — Toolchain and a booting screen ✅ DONE
`bin/beebasm.exe`, `build.ps1` (`-Run` launches b-em), jsbeeb MCP for in-loop verification.
`src/main.asm` boots to a 320×200 MODE 1 screen at `&4000` and draws a fill + 1-px border.

**Confirmed empirically:**
- **CRTC start address = screen address ÷ 8.** Base `&4000` → R12/R13 = `&0800`. The 16K wrap holds.
- Geometry: R6 = 25 rows, R7 = 31, everything else at MODE 1 defaults. R4 = 38 / R5 = 0 is left
  alone to preserve 312 scanlines / 50 Hz.
- Screen occupies exactly `&4000–&7E7F` (16000 bytes). `&7E80+` untouched.
- **`&3000–&3FFF` is genuinely reclaimed** — verified still zero after the fill.
- Pixel address formula verified: `addr = &4000 + (y DIV 8)*640 + (x DIV 4)*8 + (y MOD 8)`.
- MODE 1 byte encoding: pixel *n* takes bit `7-n` (high colour bit) and bit `3-n` (low bit).
  Solid colour 0/1/2/3 = `&00`/`&0F`/`&F0`/`&FF`.
- DFS filenames are max 7 chars — the disc file is `PARA`, not `PARADROID`.

Outstanding niggle: the display sits slightly low; R7 wants a nudge. Deferred — final geometry
changes at Layer 9 anyway (see below).

**RAM reclaim opportunity (from KC):** Paradroid's layout is a static title bar at the top, a gap,
then the active play area. The play area needs far fewer than 25 char rows, so R6 can shrink
further and hand back more of `&4000–&7E7F`. Quantify once the HUD split is designed; it may
relieve the sprite-data budget without touching the mode choice.

### Layer 1 — Graphics data pipeline
Extend the Python rippers to emit BeebASM source: `$7800` charset converted 1bpp→MODE 1 2bpp,
the 32 tile definitions, level RLE, deck metadata, palette mapping. **Proves:** conversion is
correct — display the tile sheet on screen and compare against `tools/output/tiles.png`.

### Layer 2 — Static deck render
Port `BuildLevel` (RLE → tile buffer) and enough of `DrawScreen` to paint one deck. **Proves:**
level data and tile pipeline are sound. Output: deck 1 on screen, motionless.

### Layer 3 — Scroll spike ← *the decision point*
Wide virtual buffer, CRTC R12/R13 hardware scroll, keyboard-driven. **Decide the scroll model here
and record it in this document.** Everything downstream depends on the map buffer layout.

Horizontal granularity is **4 pixels**, not 8. CRTC R12/R13 addresses in 8-byte units, and a MODE 1
character cell is 16 bytes (8 px × 2bpp = 2 bytes/row × 8 rows), so one CRTC increment is half a
cell:

| Mode | bytes/char cell | 1 CRTC unit |
|---|---|---|
| MODE 0 | 8 | 8 px |
| MODE 1 | 16 | **4 px** |
| MODE 2 | 32 | 2 px |

4 px = 1/80 of screen width, and exactly 2 logical C64 multicolour sprite pixels. This may be smooth
enough unaided — that is what the spike measures.

To compare:
- 4-px horizontal (CRTC only) vs. 1-scanline vertical (R4/R5/R12 trick) vs. flip-screen.

**Parked option — 2-px horizontal, Master only.** Keep a second 16K buffer in shadow RAM holding a
copy of the map offset by 2 px, and alternate which buffer is displayed to halve the granularity.
Significant added complexity, and a Model B has no room for the second buffer — revisit only if the
target moves back to the Master.

### Layer 4 — Sprite blitter
MODE 1 software sprites, 24×21, background save/restore, pre-shifted variants. One player droid
drawn over the scrolling map. **Proves:** the frame budget. Measure cycles; this is where the port
either performs or doesn't.

### Layer 5 — Player movement
Port `GetNewDir`, `CalcSpeed`, `SpriteHitWall`, rotation animation tables. Player walks the deck
and is stopped by walls.

### Layer 6 — Droids
`RunDroids`, `dMd0_droid`, sprite slot allocation, pathfinding. Droids move and chase.

### Layer 7 — Combat
`dMd1_bullet`, `dMd2_explosion`, `DoCollision`/`DoCollision2`, `DoScore`, `KillDroid`,
`DoAlertAndAging`. The core game is playable at this point.

### Layer 8 — Doors, lifts, decks
`OpenDoor`, `CloseDoors`, `DoLift`, `FindLift`, `ChangeDeck`. The whole ship becomes traversable.

### Layer 9 — HUD and console
Status bar via the mid-frame split, `Console`, `con_DroidInfo`, `con_DeckInfo`, `con_ShipInfo`,
side view.

### Layer 10 — Transfer minigame
`SubGameSelectSide` and the circuit puzzle. Paged from SWRAM bank 1.

### Layer 11 — Sound, title, polish
SN76489 driver replacing the SID engine, title screen, attract mode.

## Fate of the existing `src/`

| File | Fate |
|---|---|
| `zeropage.asm` | Keep, rework for the ~150-byte Model B ZP budget |
| `hardware.asm` | Keep, strip Master-only registers (ACCCON, shadow RAM) |
| `macros.asm` | Keep `CRTC_WRITE`, `SN_WRITE`; drop `ACCCON_*` |
| `main.asm` | Rewrite — assumes Master, MODE 2, shadow double-buffering |
| `hal_video.asm` | Retire — MODE 2 CRTC arithmetic, unverified, carries `TODO`s |
| `hal_irq.asm` | Retire — assumes Master shadow RAM and a HAL structure we're not building |
