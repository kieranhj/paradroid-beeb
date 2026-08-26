# The C64 intro on the BBC — plan

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md). Status: **v1 BUILT
2026-08-26**, same day as the plan — screen, flash, split, and the boot chain all verified in
jsbeeb (§5's checks: depack diffed byte-for-byte, forced-peak screenshots, full boot → key →
game). The C64 side — what the intro is and how its effect works — is [`graphics.md`](graphics.md)
§10; the rip it builds on is `tools/rip_intro.py` and the analysis in its docstring. §7 records
what the build changed against this plan and the traps it found.*

A separate, standalone executable that reproduces the CE loading intro — the three-robots
picture with the credits — in MODE 1, with the 'flashing lightning' effect. Scoped with KC
2026-08-26:

| Question | Answer |
|---|---|
| Boot role | **First thing `!BOOT` runs**: intro shows, loops with the effect, **any keypress exits and the game load proceeds** (the rest of `!BOOT` continues when `PINTRO` returns). **A build option, default OFF** — KC 2026-08-26: "I don't want to have to go through it every time I want to test the game." §4 |
| Colours | **One palette split mid-screen** (scarybeasts has budgeted for it, 2026-08-26 — supersedes the same-day "one static palette" answer): the picture region and the credits region each get their own 4-colour palette. No per-row recolouring beyond that |
| Secondary animations | **None for now** — the lightning flash only; no pulsing eyes, no console sparkle, no per-cell glow *animation* (but see [DECISION 2] for what comes free). May grow back — see §6 |
| Sound | **Silent for now** — scarybeasts is providing a cycle-counted 15 kHz MOD player to play a tune during the intro; its exact spare-cycle budget is TBC, and the animation level gets revisited against it. §6 |

The design principle that makes this cheap: **on the BBC the whole effect is palette
animation.** The C64 flashes three background registers; MODE 1 has four programmable logical
colours. Convert the picture so that the flashing C64 layers land on dedicated logical colours,
and the 15-frame flash becomes at most a dozen ULA writes per frame — no screen memory is
touched after the initial draw, ever.

## 1. The colour model

The C64 picture at rest is silhouettes: `D021/D022/D023` all black, only the sky (solid
`11`-pixels through colour RAM) and the eyes carrying colour. Everything that lights up during
a flash is a `00`/`01`/`10`-pixel or a glow cell. With the split, each region maps onto MODE
1's four logical colours exactly. **Picture region** (C64 rows 0–15, the mirror of the C64's
own raster split at line `$B2`):

| Logical | Carries | At rest | During a flash |
|---|---|---|---|
| 0 | C64 background (`00`-pixels), floor/machine `11`-pixels | black | follows the colourway's `D021` ramp — see [DECISION 3] |
| 1 | `D022` pixels (`01`) | black | follows the `D022` ramp |
| 2 | `D023` pixels (`10`) **and the 27 glow cells' `11`-pixels** | black | follows the `D023` ramp |
| 3 | Sky (`11` on the `$0E` rows) and the eyes | blue | unchanged |

**Credits region** (C64 rows 16–24): logical 0 black, logicals 1–3 three fixed foreground
colours, never flashed — the C64 holds its bottom section on black through every flash, and
the split reproduces that for free. See [DECISION 4] for how seven C64 row colours become
three.

- **[DECISION 1] Eyes are static, drawn in the sky colour** (logical 3). The C64 pulses them
  through an 8-colour ring; "flash only" drops the pulse, and logical 3 is the only colour lit
  at rest, so it is the only way for them to read as *on* in a silhouette. Deviation from the
  original, accepted for the minimal build.
- **[DECISION 2] The glow cells fold into logical 2 at conversion time.** On the C64 the 27
  torso/machine cells get a separate glow colour written per flash step; per-cell colour does
  not exist in MODE 1, but mapping those cells' `11`-pixels to logical 2 makes them black at
  rest (faithful — their rest colour RAM is `$08` → black) and light up with every flash. Most
  of the glow effect, zero runtime cost. The glow column of the colourway blocks goes unused;
  glow follows the `D023` ramp instead.
- **[DECISION 3] The `D021` component of the flash is IN** *(revised same day: the original
  static-palette plan dropped it because logical 0 was shared with the credits background;
  the split removes the objection)*. The picture region's logical 0 follows the colourway's
  `D021` ramp — it only lights at the 3 peak-hold frames, exactly the C64's whole-sky flare —
  and the credits region's logical 0 stays black below the split, as the C64's does.
- **[DECISION 4] The credits get three fixed foreground colours** *(revised same day from
  "one colour, shared with the sky")*. The C64 draws the four text elements two-tone —
  logo `$0A/$0A`, "Competition Edition" `$06/$0E`, "by" `$03/$0D`, "Andrew Braybrook"
  `$05/$07`, one shade per char row. Three foreground logicals cannot keep the row-pair
  gradients, so the conversion maps each text row to the nearest of three chosen physicals —
  starting point: 1 = magenta (the logo), 2 = cyan (the blues), 3 = green (the greens, with
  yellow auditioning for the last row) — losing the gradients but keeping the elements
  distinct. Assignment is data in the exporter; tune by eye like the flash table.
- The console-sparkle cells (dropped animation) fall out of the colour-RAM rule with no
  special handling: their base row colour is `$0E`, so their `11`-pixels land on logical 3 —
  the machine-top lamps read as permanently lit, close to what the C64 shows mid-sparkle.

**Physical colour choices.** The BBC's 8 physicals have no grey, orange, purple or brown, so
each C64 colour in the ramps needs a nearest-physical call. Starting table — **tune by eye in
jsbeeb against `tools/output/intro_flash_*.png` before recording it as final**:

| C64 | BBC | Used by |
|---|---|---|
| `$06` blue | blue — audition magenta too; the C64's blue renders purple-ish and BBC blue is dark | sky / eyes / credits |
| `$0B/$0C/$0F` greys | blue → cyan → white | colourway 1 (the true lightning) |
| `$09/$08/$07` brown/orange/yellow | red → red → yellow | colourway 2 (the ref screenshot) |
| `$02/$0A` red/pink | red → magenta | colourway 3 |
| `$05/$03/$0D` greens | green → cyan → green | colourway 4 |

## 2. Conversion — `tools/export_intro.py`

New exporter, reading `extracted/intro_ram.bin` (**not** the listing — the intro is the
loader's, see `graphics.md` §10). It renders the screen the way `rip_intro.py` does, but to
logical colours under §1's model instead of RGB:

- One C64 multicolour pixel = two MODE 1 pixels, 320 wide exactly; the hires credits map 1:1.
- 25 C64 rows = 200 scanlines, centred in MODE 1's 256: 3 blank rows above, 4 below. Blank
  rows are near-free after compression.
- Output is a **full 20K MODE 1 bitmap, ZX0-compressed** (`bin/zx0.exe`, round-trip verified
  through `tools/zx0.py` like the banks), written to `src/data/introscr.zx0`. No charset, no
  cell model, no draw code on the BBC side — the picture is data. **Measured: 20,480 →
  1,256 bytes**; the whole `PINTRO` file is ~2.3K.
- The credits rows are drawn in logicals 1–3 per [DECISION 4]'s row→colour map; the picture
  region per §1's model. The exporter emits both regions into the one bitmap — the split
  changes only which palette is live, not the data.
- Also emits the effect tables as `src/data/introfx.asm`: the 15-entry envelope
  (`00 04 08 0C 0C 0C 08 08 08 08 04 04 04 04 00`, transcribed verbatim from `$E204`), the
  per-colourway `D021`/`D022`/`D023` ramps **already mapped to BBC physical + ULA form** (so
  the runtime does no translation), and the two 16-byte region palettes for the split writes.
- `build.ps1` does not run exporters; changing the mapping table means re-running the tool.
- A verification renderer in the same tool writes `tools/output/intro_bbc_rest.png` and
  `intro_bbc_flash_N.png` — the *expected* BBC output, to eyeball against the C64 renders and
  against jsbeeb.

## 3. The executable — `src/pintro.asm`

A separate BeebASM top file — **not** included from `main.asm`, no interaction with the game
build's GUARDs, banks or zero page. Assembled by a second, tiny beebasm pass in `build.ps1`.

- **File layout:** one `*RUN` file, `PINTRO`, load/exec `&1900` (plain DFS `PAGE` — none of
  the game's `&1100` tricks are needed or wanted here). Code + the `ZX0_DEPACKER` macro from
  `src/zx0depack.asm` (reused as source, assembled into this exe) + the INCBIN'd compressed
  stream. Whole file ~3–4.5K.
- **Startup:** `VDU 22,1` (the OS clears `&3000–&7FFF`, which is about to be overwritten
  anyway), cursor off, ULA palette to the rest state (logicals 0–2 black, 3 blue), then
  depack the image straight into `&3000`. Depacking downwards into the screen the stream sits
  below is ZX0-safe forwards; the stream at `&1900`+ and the target at `&3000` never overlap.
- **Main loop, one iteration per frame:** `OSBYTE 19` (vsync wait — the OS is alive and doing
  the timing for us; no IRQ takeover, no event handlers, nothing resident), then
  **`IntroFxTick`** — the effect state machine as ONE self-contained, bounded call, so the MOD
  player can later become the timekeeper and call it from its spare-cycle window without
  restructuring (§6). It is a transliteration of the C64 loop at `$E000`:
  - free-running frame counter; when idle, every 32nd frame, if the counter's 256-phase is in
    `$50–$CF`, gate on a random byte (System VIA timer 1 low, `&FE44` — the same trick as the
    C64's CIA read) → start a flash: colourway = random `AND 3`, step = 15.
  - when flashing: step down through the envelope, look up the colourway's mapped
    `D022`/`D023` values, write logicals 1 and 2 to the ULA — 8 palette writes (4 entries per
    logical in MODE 1), ~100 cycles. Idle frames write nothing.
- **The palette split:** two full 16-register ULA palette rewrites per frame (~200 cycles the
  pair). **As built, BOTH are mid-frame writes** — the picture palette is NOT written in the
  vsync shadow as first planned, because everything outside the drawn image is logical 0 and
  the picture palette's logical 0 carries the `D021` flash: written at vsync it painted the
  blank rows above the picture red at every flash peak. So the picture write waits for the
  raster to reach the picture's top row (the blank rows keep the credits palette's black),
  and the credits write lands early in the all-black C64 row 16. v1 timing is two calibrated
  busy-waits after `OSBYTE 19` (`SPLITA_*`/`SPLITB_*` in `pintro.asm`, screenshot-calibrated
  in jsbeeb, with OS interrupt jitter absorbed by the blank rows); under the MOD player they
  become two hook calls on the player's cycle-counted schedule (§6). **Accepted artifact:**
  at the 3 peak frames of a flash, up to ~3 scanlines bordering each write point show the
  wrong palette's background — a brief red sliver above the picture and below the floor. The
  C64 is immune (its blank areas are colour-RAM-black PIXELS, not background); the MOD
  player's exact timing will shrink it to nothing.
- **Exit:** any keypress, detected by `OSBYTE &7A` keyboard SCAN — **NOT by INKEY/OSRDCH,
  which read the EXEC stream while `!BOOT` is running: the first build's INKEY ate the `*`
  of the `*RUN PARA` line and exited with no key pressed** (§7). On a key: acknowledge any
  ESCAPE, flush the keyboard buffer so nothing leaks into the game, restore MODE 7, RTS to
  the OS — `!BOOT`'s `EXEC` then carries on into the existing game load sequence untouched.
  Everything the intro used is reclaimed by that load; it must simply leave the OS and DFS
  exactly as it found them, which nothing in this design disturbs (no IRQ takeover, no
  workspace writes — the hazards in `CLAUDE.md`'s loader rules never arise this early).
- **Cycle cost:** ~350 cycles a frame of real work — `IntroFxTick` (~150 worst case: counter
  logic plus updating the picture palette's flash entries) and the two split palette writes
  (~200) — plus v1's throwaway busy-wait. **RAM cost:** nothing survives exit; while
  running, the file below `&3000` and the screen.

## 4. Disc and build — an OPT-IN build switch

**The intro on the front of the disc is a build option, default OFF** — the everyday test
build boots straight into the game as it does today. `.\build.ps1 -Intro` (passed through by
the `make` wrappers like `-Run`) produces the disc with the intro wired in. On an intro
build:

- `build.ps1` runs a second, tiny beebasm pass for `src/pintro.asm` before `make_disc.py`.
  The game pass is untouched either way.
- `!BOOT` gains `*RUN PINTRO` as its first action, before the mode change and the loads.
  **The wiring is `make_disc.py --intro`, which patches the line in front of the literal
  `*RUN PARA`** (and fails loudly if that marker ever changes — the note sits in `main.asm`'s
  `!BOOT` header). The plan's first idea, a beebasm `-D` symbol driving a conditional `EQUS`,
  was dropped during the build: beebasm has no way to default an undefined symbol, so it
  would have broken the documented bare `beebasm -i src/main.asm` symbol-dump command.
- `tools/make_disc.py --intro <PINTRO-raw.ssd>` also takes `PINTRO` from the second pass's
  image and lays it into the physical boot order right after `!BOOT`. `PINTRO` ships
  uncompressed (its image stream is already ZX0 inside the file; there is no loader yet to
  depack a whole exe).

A default build must not merely skip the wiring but contain no `PINTRO` and no `!BOOT`
reference to it, so the option can never half-apply. For bring-up before the `!BOOT` wiring
works, `*RUN PINTRO` from the prompt on an intro-build disc is the whole test harness.

## 5. Verification

1. `export_intro.py`'s expected-output PNGs against `rip_intro.py`'s C64 renders — the
   conversion decisions, before any BBC code runs.
2. In jsbeeb: depacked `&3000–&7FFF` diffed byte-for-byte against the exporter's raw
   (uncompressed) bitmap — proves the depack, the way the game verifies against the buffer
   rather than the screenshot.
3. Screenshot at rest and mid-flash against the PNGs from step 1. The flash can be forced by
   poking the state variables rather than waiting on the random gate.

## 6. Later — the MOD player, and the animation budget

scarybeasts is providing a **cycle-counted 15 kHz MOD player** to play a high-quality tune
under this intro. Its exact spare-cycle budget is TBC (KC will confirm); until then, v1 gets
the screen and the flash working on `OSBYTE 19` timing and stays deliberately tiny. What the
plan already provides for:

- **The effect is two bounded calls**: `IntroFxTick` (~150 cycles worst case, most frames far
  less) and the split's palette write (~100). scarybeasts has already budgeted the split
  (2026-08-26); when the player arrives it becomes the timekeeper — a cycle-counted player
  owns the CPU, so the tick moves into its once-per-frame spare window, the split write onto
  its cycle-counted schedule at the boundary scanline (retiring v1's busy-wait), and
  `OSBYTE 19` and probably the OS itself go away. Keeping both calls free of OS dependence is
  a hard rule for exactly this reason; the keypress test likewise becomes a direct
  keyboard-hardware scan.
- **RAM for the MOD is available at intro time**: the intro precedes every game load, so main
  RAM above the exe and **all four sideways banks** are free for the player and its module —
  the game reloads the banks afterwards regardless. The exe's own footprint (~4K at `&1900`)
  and the 20K screen are the only reservations.
- **The dropped animations are the adjustable dial.** In cost order once the budget is known:
  pulsing eyes (6 cells × 16 B rewritten every 4th frame, ~600 cycles when it fires), console
  sparkle (7 cells, same shape), true per-step glow (27 cells × 16 B per envelope step — the
  expensive one, and [DECISION 2] already fakes most of it for free). Each is independent and
  each mirrors a documented C64 behaviour (`graphics.md` §10), so they can be added back one
  at a time against the measured spare cycles.

## 7. As built — what changed against the plan, and the traps

Built and verified the same day, `src/pintro.asm` + `tools/export_intro.py`. Deltas from the
plan above, each folded back into the section it touches:

1. **INKEY reads the EXEC stream** (§3). At boot the OS is EXECing `!BOOT`, and character
   input comes from the file, not the keyboard: the first build's INKEY(0) consumed the `*`
   of `*RUN PARA`, the intro exited instantly, and BASIC threw `Syntax error` on `RUN PARA`.
   The exit test is now the `OSBYTE &7A` hardware scan. Second trap inside the fix: NAUG
   documents the no-key return as X=0, but the MOS in jsbeeb returns &FF — the code treats
   both as idle rather than trusting either account.
2. **The picture palette write moved off vsync** (§3): at vsync it painted the blank rows
   above the picture with the flashed logical-0 red. Both palette writes are now raster-
   positioned, and the residual ~3-line peak-only slivers at the two write points are the
   accepted artifact, pending the MOD player's exact timing.
3. **The `!BOOT` wiring is a `make_disc.py --intro` patch, not a `-D`/`EQUS` conditional**
   (§4): beebasm 1.11 cannot default an undefined symbol, and requiring `-D` on every pass
   would have broken the documented bare symbol-dump invocation of `main.asm`.
4. **Numbers**: the bitmap compresses 20,480 → 1,256 bytes; `PINTRO` is ~2.3K all in;
   assembling it adds ~0.1 s to an `-Intro` build. The calibrated waits sit in `pintro.asm`
   as `SPLITA_OUTER/FINE` and `SPLITB_OUTER/FINE` with the calibration recipe in the comment
   above them.
5. **Verified** per §5: the depacked screen diffs byte-for-byte against the exporter's
   bitmap; rest and all four forced-peak states screenshot-checked against the expected
   PNGs; the full chain — SHIFT+BREAK boot → intro → random flash observed → keypress →
   game load → title — runs clean, and a default build's disc carries no trace of any of it.

One deliberate deviation the plan already carried, restated for the record: the ULA palette
write itself can glitch a few displayed pixels at the beam position on the write lines
(visible as short dashes at flash peaks only, over black). Real-hardware behaviour, shared
with every mid-frame palette split; invisible at rest because black-to-black writes change
nothing on screen.
