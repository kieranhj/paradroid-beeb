# A VideoNuLA build of the port — plan

**Status: proposal, nothing built. A SEPARATE DELIVERABLE, out of scope for the current plan**
— settled by KC 2026-08-21. It ships as a **second executable on the same disc**, not as a second
disc and not as a change to the port (§5). Written 2026-08-21 against the VideoNuLA User Guide v1.0
(July 2017, `BEEB/Manuals/VideoNuLA manual.pdf`) and the port as it stands at `6f6dd61`. This
document does not modify any existing file; if the plan is taken up, its decisions move into
`PLAN.md` and a `docs/layer-N` file in the usual way.

The short version: **NuLA fixes two of the port's three known display deviations from the C64 —
the 4-pixel horizontal scroll step and the eight fixed hues — and it fixes them cheaply, in the
display path, without touching the buffer, the blitter or the tile data.** It does not fix the
four-colours-per-deck merge, and everything it does fix costs a machine that most people do not
have.

---

## 1 What the hardware actually offers

Measured/verified, not recalled. Registers are **write-only**; there is no read-back of anything.

| Register | What it is |
|---|---|
| `&FE22` | auxiliary control: `(control code << 4) | parameter` |
| `&FE23` | auxiliary palette: **two writes per colour** — `(index << 4) | red`, then `(green << 4) | blue` |

Control codes that matter here:

| Code | Function | Parameter |
|---|---|---|
| 1 | palette mode: 0 = physical (via `&FE21`), 1 = **logical → 12-bit direct** | 1 bit |
| 2 | **horizontal scroll offset** — delays the display in 1-bit steps, **½ pixel in MODE 1** | 0–7 |
| 3 | **left blanking** — blanks *n* bytes at the left, **4 px units in MODE 1** | 0–15 |
| 4 | reset all extended features | — |
| 5 | disable NuLA until power-on (maps `&FE22/23` onto `&FE20/21`) | — |
| 6 | attribute modes on/off | 1 bit |
| 8, 9 | flash flags for logical 8–15 | 4 bits |

Palette: 4096 colours, 4 bits per channel. The manual notes it can be rewritten **many times per
scanline**, which the port's rupture already has the machinery for.

Attribute mode, MODE 1 flavour: 3 pixels + 2 attribute bits per byte → **240 × 256**, four
palettes of four colours, i.e. 16 on screen. See §6 for why this is not the v1 answer.

### 1a Two things that are *not* in the manual and matter more

**The registers alias on a stock machine.** `&FE20/21` are not fully decoded, so on a Beeb without
the mod, writes to `&FE22` land on the **ULA control register** and writes to `&FE23` land on the
**ULA palette register**. A NuLA build run on stock hardware does not degrade gracefully — it
rewrites the pixel clock and the mode bits every frame. **KC has a runtime detection method that
works on real hardware** (2026-08-21); it needs writing down here before anything is built, because
its ordering constraints — what may be written before the answer is known, and what the negative
path must never touch — are the boot sequence's design (§5).

**Emulator support is uneven, and uneven in exactly the wrong place.** Checked in the sources, not
assumed:

| | palette (`&FE23`) | flash | palette mode (code 1) | **scroll offset (code 2)** | left blank (code 3) | attribute (code 6/7) |
|---|---|---|---|---|---|---|
| **b2** (`Repos/b2`, tom-seddon — KC's emulator of choice) | ✅ | ✅ | ✅ `m_direct_palette` | ✅ `m_scroll_offset` | ✅ `m_blanking_counter` | ✅ all five emitters |
| b-em `42f6597` (what `build.ps1 -Run` launches) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| jsbeeb (`Repos/jsbeeb`, the MCP's build) | ✅ | ✅ | ❌ stored, ignored | ❌ **stored, ignored** | ❌ stored, ignored | ❌ stored, ignored |

b2 is a full implementation and is the reference: `VideoULA.cpp` applies `m_scroll_offset` as the
write index into the pixel buffer in every `EmitNMHz`, decrements `m_blanking_counter` and forces
black in `EmitPixels`, and dispatches attribute modes through `EMIT_MFNS`. b-em's binary carries the
matching symbols (`nula_horizontal_offset`, `nula_left_blank`, `nula_left_cut`, `nula_left_edge`,
`nula_palette_mode`, `nula_attribute_mode`). jsbeeb parses every control code into `NulaState` and
the renderer reads only `collook`/`flash` — `horizontalOffset`, `leftBlank`, `attributeMode` and
`paletteMode` have no consumer outside `snapshotState`.

Confirmed live: `?&FE23=&1F : ?&FE23=&F0` in jsbeeb turns physical 1 from red to yellow. The
scroll-offset test (`?&FE22=&27` over a striped MODE 1 screen) produced **no shift**, consistent
with the source reading.

**Consequence for how this project works.** The automated oracle — jsbeeb over MCP, buffer diffs,
`DEBUG_TIME` — stays valid for everything *behind* the display, because NuLA changes nothing in the
buffer. But the headline features are invisible to it, so the tooling has to move for this
deliverable:

- **b2 is the verification vehicle**, and its debug build carries an HTTP API. **`peek` is the
  important one**: it preserves the project's strongest rule, *verify against the buffer, not the
  screenshot*, on the emulator that renders NuLA correctly. A `RedrawAll` diff driven over HTTP is
  the same test the MCP does today.

  **The API is documented** — `doc/Debug-version.md` in the b2 tree, and
  <https://github.com/tom-seddon/b2/blob/master/doc/Debug-version.md>. **Read it first**; this
  section was originally written by reading strings out of the binary, which got the port wrong and
  missed half the endpoints.

  | | |
  |---|---|
  | port | **48075** (`0xbbcb`), localhost only, debug build only |
  | window name | `b2` for the first window, `*` for the most recent |
  | numbers | hex or C-style — `ffff`, `0xffff`, `0177777` |
  | `peek/WIN/BEGIN/END` | binary `application/octet-stream`; END exclusive, or `BEGIN/+SIZE` |
  | `poke/WIN/ADDR` | binary body |
  | `s=SUFFIX` on both | selects the memory view: `m` main, `s` shadow, `r`/`0`-`f` paged ROM, `n` ANDY, `h` HAZEL, `o` OS, **`i` standard I/O `$fc00-$feff`**, `p`/`q` parasite |
  | `reset/WIN?config=CONFIG&boot=1` | power-on reset, optionally into a named config, SHIFT held |
  | `load-disc/WIN?path=…&drive=N`, `mount/WIN`, `run/WIN`, `paste/WIN`, `launch?path=` | the rest |
  | screenshot | **none** |

  **Tried, 2026-08-21**, against `b2_Debug.exe` build `20260322-193052-51e70d7`, the port booted
  from `PARADROID-200K.SSD` on a `B/Acorn 1770 w/ NULA` config:

  | | |
  |---|---|
  | `peek` fidelity | ✅ `&1100`–`&1120` byte-identical to `PARA` extracted from the SSD |
  | machine live | ✅ ZP `&15`, `&20`, `&21` tick between peeks 2 s apart |
  | `poke` to RAM | ✅ round-trips |
  | **`poke` to I/O (`&FE23`)** | ❌ no effect — and this is expected, see below |

  The docs say why: *"host memory-mapped I/O is not particularly well supported — if you view the
  I/O region, it'll show up as unreadable bytes."* **`poke` writes emulated memory, not the bus.**
  The `i` suffix exists and is worth one test on a current build, but the supported route for a
  register-level test is **`paste` the BASIC in** and let the 6502 do the write:

      curl --data-binary '?&FE22=&27
      ' http://localhost:48075/paste/b2

  So the split is: **`peek` automates the buffer half of every test, `paste` drives the register
  half, and the display half needs eyes on the window** because there is no screenshot endpoint.
  That is enough — the buffer is the half this project trusts anyway.

  Note also `reset?config=` and `load-disc?path=`: an already-running b2 can be pointed at a config
  and a disc over HTTP. There is no need to kill and relaunch the application to change either.
- Optionally **patch jsbeeb's renderer** (~20 lines: a shift of the pixel output plus a left cut)
  to keep the existing MCP workflow honest; `Repos/jsbeeb-kieranhj` is already a fork on disk.
  Worth it only if the b2 HTTP route proves awkward.
- b-em stays as a second opinion, and one measurement on **real hardware** should settle the
  offset's sign and the left-edge behaviour before the design is locked.

---

## 2 Smooth scrolling — the big win

### What is wrong today

`docs/layer-4-player.md` records it plainly: the CRTC addresses in 8-byte units and a MODE 1
character is 16 bytes, so the horizontal step is **4 px**, and the loop runs every 2 fields. The
camera can therefore only move 0, 4, 8 … px a pass. The C64's top speed of 7 does not divide 4, so
the camera dithers **8, 8, 8, 4** — and that periodic hiccup is why `CAM_TOPSPD` was set to 8 and
`CAM_SLOWSPD` to 4, the only two movement numbers in the port not taken from the original
(`PLAN.md`, `plySpdTab`). The port is 14 % fast on purpose because the hardware could not be smooth
at the right speed.

### What NuLA changes

Control code 2 delays the display in ½-pixel steps in MODE 1. Offsets `0, 2, 4, 6` are exactly
`0, 1, 2, 3` pixels — precisely the four positions between two CRTC units. **The horizontal step
becomes 1 px**, matching the C64's `$D016` fine scroll, with the same 3.5 px of headroom left over
if a half-pixel jitter is ever wanted.

`posX` is already a 16-bit **pixel** position (`scroll.asm`: `mapHX = posX >> 2` — the low two bits
are simply thrown away today). So the whole change is: stop throwing them away.

    unit   = (posX + 3) >> 2            \ round UP to the next CRTC unit
    offset = ((-posX) AND 3) * 2        \ 0,2,4,6 — push the picture back right

Round **up**, not down, because the offset can only delay (move the picture right), never advance
it. `SetCRTCStart` computes `scrollS` from the rounded-up unit and parks a third byte beside
`crtcHi`/`crtcLo`/`pline`; the IRQ picks it up in the same breath, exactly as it already does for
`pline`.

**The sign is a hypothesis until it is measured in b2.** The manual says incrementing moves the
screen right; confirm before building anything on it.

### Where the register write goes

The panel and the play area are separate CRTC cycles but share one NuLA offset register, so a
static panel under a scrolling play area needs the register written twice a frame — which is
exactly what `rupture.asm` already does for `&FE21`:

| Fire | Existing work | Added |
|---|---|---|
| `RuptVSync` | panel R12/13, T1 restart, `SetPalPanel` | `LDA #&20 : STA &FE22` — offset 0 for the panel |
| fire 1 (P+44) | blank, latch `pline`→`iline`, play R12/13, `SetPalPlay` | latch `pnula` → `inula` beside `iline` |
| **fire 2 (P+64)** | R8 on, R4 — *lands in horizontal blanking* | `LDA inula : STA &FE22` — offset for the play cycle |

Fire 2 is the right home: it is the visible top edge, it is already required to land in horizontal
blanking, and everything above it is blanked by R8. Cost: **~8 cycles a frame.** Nothing else in
the frame moves.

### Left blanking

Shifting the display right by up to 3 px exposes up to one unit of whatever precedes the display
start at the left edge. Control code 3 blanks whole 4 px units at the left without changing the
memory layout — so blank **one unit for the play cycle, zero for the panel**, written at the same
two points as the offset. The play area becomes 316 px of 320 visible; the strip geometry, the
80-unit row, the 10K wrap and the blitter are all untouched.

If the leading edge turns out to be clean without it (worth measuring — the buffer is a ring, so
the byte to the left is a real, already-drawn column, not garbage), drop the blanking and keep the
full 320.

### What it costs in the game code

1. `SetCRTCStart` (`bufcore.asm`): round up, derive and park the offset. ~12 bytes, ~15 cycles.
2. `rupture.asm`: two stores plus a latch. ~10 bytes.
3. One new zero-page byte pair (`pnula`, `inula`) — **and ZP is fully allocated (`&00–&8F`)**, so
   this needs a scalar found or a byte stolen. See §7.
4. **Explore returning the droid speeds to the original's values** — KC 2026-08-21, and it is an
   exploration, not a foregone conclusion. `CAM_TOPSPD` = 8 and `CAM_SLOWSPD` = 4 exist *only*
   because of the 4 px grid (`plySpdTab` = `0,4,4,0,8,0,0,0,8` where the C64 has 7s, a 5 and a 6),
   so with the grid gone the reason for the deviation is gone. Two things to establish before
   changing them: that the original's table is genuinely smooth at 1 px granularity across the
   whole `PlayerSpeed_t` range, and what the ~14 % speed drop does to a game that has been balanced
   and played at 8 for months (`docs/layer-12-balance.md` was written against 8). Enemy `DSpeed_t`
   is already the original's and is not in question. If the answer is "keep 8", the scroll work is
   still worth it on its own — the dither disappears at any speed.

### The one real correctness risk

Rounding the unit **up** means the rightmost visible column is one unit further right than it is
today, so the leading edge must be drawn one column earlier. `DrawColumn` already copes with up to
two columns a pass, and `mapHX` still drives *which* column to draw — but the ordering (draw the
new column, *then* display it) has to hold at the new boundary. This is the same class of bug as
the abandoned half-step experiment in `docs/layer-3-scroll.md` §"It does not work, and the strip is
why", and it is caught the same way: **diff the buffer against `RedrawAll` at odd and even `mapHX`,
non-zero `line`, and diagonals**, not by looking at the picture. The buffer check is unaffected by
NuLA, so the project's strongest verification tool still applies to the only part that can be
silently wrong.

---

## 3 The C64 palette — the cheap win

### What is wrong today

`tools/palette_lab.py` states the chain exactly:

    C64 view:  index -> C64_RGB[index]
    BBC view:  index -> colourMap[index] -> deckPalette[logical] -> BBC_RGB[]

Two lossy steps, and they are different kinds of loss:

- **the merge** — `colourMap`, 16 C64 colours onto 4 logical slots. Information gone; no palette
  recovers it.
- **the approximation** — `BBC_RGB`, four slots onto the BBC's eight saturated hues by
  nearest-RGB. C64 `$0B` dark grey becomes black, `$0C`/`$0F` greys become white, the browns become
  red or yellow.

**NuLA removes the second step entirely and leaves the first exactly as it is.** That is the honest
claim: the decks get their real colours, not more of them.

### How

Every palette in the port already funnels through one macro and two loops — `PALENT` in
`rupture.asm`, `SetPalPanel`/`SetPalPlay`, and `SetPalette` in `level.asm` which builds `palPlay`.
The tables are `palPanel`, `deckPalette`, `palXfer`, `palLift`, the ship-page and portrait palettes
in `droid.asm`/`portrait.asm`, and the title's. Change the macro and the two writers and the whole
game changes colour.

**Use logical palette mode (control code 1).** In physical mode you keep the `&FE21` CAM dance —
16 entries written per swap because only bits 7 and 5 are compared, four landing on each logical
colour, which is what `SetPalette`'s comment derives at length. In logical mode `&FE23` maps
logical colours straight to 12-bit RGB, and MODE 1 has four of them. So a palette becomes:

|  | today | NuLA logical mode |
|---|---|---|
| bytes per palette table | 16 | **8** (4 colours × 2 writes) |
| writes per rupture swap | 16 | **8** |
| cycles per swap | ~208 | **~104** |
| `SetPalette`'s CAM arithmetic | ~50 bytes | **gone** |

Both `palPlay` and `palPanel` halve, in main RAM, where 47 bytes below `&3000` is the binding
constraint. The rupture gets ~200 cycles a frame back. **The NuLA colour path is smaller and
faster than the one it replaces** — which is the opposite of what a new feature normally does, and
worth confirming early precisely because it sounds too good.

### The per-deck data, at zero net cost

`deckPalette` is 16 decks × 4 physicals = 64 bytes in bank 4, which has **51 bytes free** (post-RAM-pass, 2026-08-25). The
replacement is not bigger:

- `c64Rgb` — the 16 C64 colours as NuLA byte pairs, shared: **32 bytes**
- `deckC64` — 4 C64 colour indices per deck, nibble-packed 2 per byte: **32 bytes**

64 bytes, replacing 64 bytes. `SetPalette` unpacks a nibble, indexes `c64Rgb`, writes two bytes,
four times. `export_bbc.py` already knows each deck's four C64 colours — it is what `schemes` and
the automatic assignment are made of — so the exporter emits indices instead of nearest-match
physicals and the `PREFERRED` aesthetic fudges (`{14: 4, 7: 5}`) can be deleted, along with the
comment admitting they "want re-judging in the lab".

### Two things this makes possible that are currently impossible

- **The panel gets grey.** `rupture.asm` says it outright: *"The C64's status area is grey on white
  … The BBC has no grey, so the frame and the mode word take black."* With NuLA it takes C64 `$0C`
  and the panel matches the original.
- **Per-region palettes anywhere the screen is static.** The rupture already proves mid-frame
  palette swaps work. On the non-scrolling pages — console, deck plan, droid database, portraits,
  title, game over — extra raster splits are free real estate: four *more* colours per band, no
  attribute clash, no resolution loss. The droid portrait pool in bank 7 is the obvious customer.

### The sharp edge

**`&FE23` is a two-write state machine with a toggle flag, and the port writes palettes from both
the main loop and the IRQ.** If the rupture IRQ lands between the two halves of a pair written by
`SetPalette` at deck load, the flag desyncs *permanently* — every subsequent pair in the game is
red-swapped-with-green-and-blue. Nothing on the BBC will tell you why. Rules, non-negotiable:

1. every pair written outside the IRQ is bracketed `SEI`/`CLI`, or
2. all `&FE23` writing happens inside the IRQ, or
3. the main-line writer sets a flag and the IRQ does the work at the next fire.

(3) is the cheapest and fits the existing `palPlay` pattern — main-line code fills the table, the
IRQ writes it out. `SetPalette`'s "live immediately, not at the next fire 1" `JMP SetPalPlay` tail
call is the one place that would have to change.

---

## 4 What NuLA does *not* fix

Worth stating so the plan is not oversold:

- **The four-colour merge.** Only attribute mode touches that (§6).
- **Vertical granularity.** Already 1 scanline, via R4/R5 — NuLA has no vertical feature.
- **The 16-row ceiling.** That is the 10K hardware wrap in the address translator, not the ULA.
- **The 25 Hz loop, the 8 sprite slots, the RAM.** Untouched. NuLA is a display device.
- **Sprite positioning.** Nothing changes and nothing needs to: the offset is applied after the
  buffer is fetched, so sprites blitted into the buffer shift with the world for free. The four
  compiled shifts in banks 5 and 6 are unaffected — which is the main reason this is a cheap plan
  rather than an expensive one.

---

## 5 Shipping it — a second executable on the same disc

**Decided by KC, 2026-08-21.** The NuLA version is a separate deliverable and out of scope for the
current plan, but it ships **on the same disc as a second executable**, selected at boot by the
runtime detection KC has. So there is no second SSD, no menu, and no user choice to get wrong.

The disc has room. Measured from `build/PARADROID.SSD`:

| | now | ceiling |
|---|---|---|
| catalogue entries | 10 | 31 |
| highest sector used | 161 — **40.25 K** | 800 — 200 K |

**160 K free and 21 catalogue slots.** Even a wholly duplicated file set fits several times over.

**Which files actually differ**, given where the changed code assembles:

| File | Bank / home | NuLA build |
|---|---|---|
| `PARA` | main RAM — `bufcore.asm` (`SetCRTCStart`), `rupture.asm` (the fires, `palPanel`, `SetPalPlay`) | **differs** |
| `PARADAT` | bank 4 — `level.asm` `SetPalette`, `data/colours.asm`, `droid.asm`'s transfer/lift/ship palettes and `plySpdTab` | **differs** |
| `PARXFER` | bank 7 — transfer, lift view, console pages, portraits | differs *if* their palettes convert (they should) |
| `PARSPR2` | bank 6 — panel/console draw | differs only if a palette table lives there; check before assuming |
| `PARTITL` | title overlay | differs (its palette) |
| `PARASPR`, `PARAFNT`, `PARDEPK`, `PARALOW` | blitter, font, depacker, low overlay | **byte-identical — share them** |

So the second set is roughly `PARAN` + `PARANDT` + `PARANX` (+ `PARANS2`, `PARANTL` if needed):
call it 25–30 K compressed against 160 K free. DFS names are 7 characters, and `tools/make_disc.py`
already lays the disc out physically in boot access order — **two interleaved boot orders on one
disc is the one real complication**, because the loader's whole compression scheme depends on that
physical ordering. Lay the shared files down once and give each variant's private files their own
contiguous run.

**Boot sequence, and the ordering rule that matters.** `!BOOT` chains a small selector (or `PARA`
detects and re-`*RUN`s), the detection runs, and the machine is committed to one of two executables
that never test again. Two constraints on that code:

1. **Detect before anything writes `&FE22`/`&FE23`** — on a stock machine the first such write has
   already damaged the ULA control register.
2. **The negative path must never touch either register**, including in error handling, and
   including control code 5. `?&FE22=&50` looks like a safety net — "turn NuLA off" — but on stock
   hardware that write *is* a ULA control write, and on NuLA it is irreversible until power-off.

The build side is the port's existing mechanism: a `NULA` constant in `main.asm` alongside the
eleven debug flags, one tree, both targets built every run (§ risks — the variant nobody builds is
the variant that rots), and the boot banner naming it exactly as a debug build names its flags.

### Other risks

| Risk | Severity | Mitigation |
|---|---|---|
| `&FE23` write-flag desync between main loop and IRQ | **high** — silent, permanent, undiagnosable on hardware | rule (3) in §3; assert in review that no `&FE23` write exists outside the IRQ |
| The detection is wrong on some machine, or a `&FE22` write escapes ahead of it | **high** — a stock Beeb showing garbage is the worst possible failure mode | document the method here, and enforce the two ordering rules in §5 as a review checklist item |
| The MCP's jsbeeb cannot see the scroll offset | medium — a tooling move, not a defect | verify on b2, buffer diffs over its HTTP `peek`; patch the jsbeeb fork if that proves awkward |
| Rounding `unit` up shifts which column must be drawn first | medium | buffer diff vs `RedrawAll` over odd/even `mapHX`, non-zero `line`, diagonals |
| Zero page is 100 % allocated; the offset needs a byte | medium | see §7 |
| Original speeds change the game's feel and ~14 % of its pace | medium | it is an exploration (§2.4), and the scroll work stands without it |
| Two builds diverge — the NuLA one is the one nobody tests | medium | one `IF NULA` tree, never a branch; build both every run; the shared disc means both are always in front of a player |
| Two boot orders on one disc break the loader's physical layout assumption | medium | shared files once, each variant's private files in their own contiguous run (§5) |
| Real hardware differs from b2 on offset sign, blanking edge, or the scanline a register takes effect | medium | one measurement on a real modded machine before the design is locked |
| Colour choices need re-judging deck by deck once the hues are exact | low, but it is real work | `palette_lab.py`'s BBC pane becomes a NuLA pane — the same 16-entry table swap, so it stays instant |

---

## 6 Attribute mode — parked, with reasons

MODE 1 attribute mode gives 240 × 256 and 16 simultaneous colours as four palettes of four. It is
the only thing that attacks the *merge*, and it should be rejected for the play area and considered
for the static pages.

**Why not the play area:**

- 320 px is exactly 2 BBC pixels per C64 multicolour pixel, which is the foundation of the whole
  graphics pipeline (`export_bbc.py`, the 16-byte character, the four compiled sprite shifts).
  240 px is 1.5 per C64 pixel — either the scale becomes non-integer or the view loses a quarter of
  its width. Both are worse than the thing being fixed.
- The attribute cell is **3 pixels, byte-aligned**, not character-aligned. Every sprite crossing a
  byte boundary would have to adopt the underlying tile's palette group — Spectrum clash, on a game
  whose droids move over patterned floors.
- The blitter's four compiled shifts become shifts over a 6-bit field with 2 bits that must be
  preserved and merged. That is a rewrite of banks 5 and 6, which have 602 and 114 bytes free (2026-08-25).
- The tile charset, `chardata.asm`, `CHAR_PTR_LO/HI`, the row geometry and the 10K wrap arithmetic
  all move.

**Where it might genuinely pay:** the full-screen static pages — droid database and portraits, deck
plan, title, game over. No blitter, no scrolling, data drawn straight from what the exporter
produces, and 16 colours instead of 4 would transform the portraits in particular. Enabling it is
one register write; the cost is a second geometry in the exporters and in `portrait.asm`. Worth its
own spike **after** §2 and §3 are done, not before.

Note also: per-scanline `&FE23` rewriting on a static page gives more colours than attribute mode
does, with no resolution loss and no clash — just raster time. On pages where the game is doing
nothing, that is the better tool.

---

## 7 The RAM question

Main RAM has 639 B below `&3000` since the RAM recovery pass, bank 4 has 51, and zero page is fully
allocated. The plan's net effect, best estimate — every line of it needs confirming against the
build's own fuel gauge before anything is promised:

| | main RAM | bank 4 | ZP |
|---|---|---|---|
| `palPlay` 16 → 8 | **+8** | | |
| `palPanel` 16 → 8 | **+8** | | |
| `SetPalPanel`/`SetPalPlay` loops shorter | +2 | | |
| `SetPalette` CAM arithmetic deleted | | **+~50** | |
| `deckPalette` 64 → `c64Rgb` 32 + `deckC64` 32 | | 0 | |
| scroll offset: park, latch, two stores | −~25 | | **−2** |
| disruptor override 4 writes → 2 | +4 | | |
| **net** | **≈ −3** | **≈ +50** | **−2** |

So the feature is roughly RAM-neutral in main RAM, **gives bank 4 about 50 bytes back**, and needs
**two zero-page bytes it does not have**. The two bytes are the only genuine blocker, and the
cheapest source is the `palTmp`/`palBase` pair in `level.asm` — they belong to `SetPalette`, whose
CAM loop this plan deletes.

That is also the reason to sequence it as below: the colour work pays for the scroll work.

---

## 8 Suggested sequence

Each step is separately shippable and separately verifiable, in the project's usual style.

1. **Spike, one afternoon.** In **b2**, on the current build, poke `&FE23` by hand to recolour one
   deck to its true C64 colours, and poke `&FE22` code 2 to confirm the offset's sign, range and
   the left-edge behaviour with and without blanking. Compare against `ref/`. **Nothing is designed
   until this has been seen.**
2. **Get b2's HTTP API into the verification loop** — `peek` for the `RedrawAll` buffer diff,
   `paste` for the register writes, `reset?config=`/`load-disc?path=` to drive a running instance.
   All of it works on the build to hand; read `doc/Debug-version.md` before writing the harness.
   Without this the scroll work is verified by eye, which is the thing this project has learned not
   to do.
3. **`NULA` build constant, second executable on the disc, boot banner, and KC's detection routine
   written down and tested on a stock machine as well as a modded one.** Nothing behind the flag
   yet — this is the seam, and it is the part that can hurt someone else's hardware, so it goes
   first and alone.
4. **Colour, part 1** — logical palette mode, `PALENT` and the two writers converted, `palPanel` in
   real C64 greys. Play area still on `deckPalette`'s eight hues. Confirms the `&FE23` protocol,
   the IRQ atomicity rule and the RAM saving on the smallest possible surface.
5. **Colour, part 2** — `c64Rgb`/`deckC64` from `export_bbc.py`, `palette_lab.py`'s BBC pane
   becomes a NuLA pane, all sixteen decks re-judged by eye, then the transfer/lift/console/portrait
   palettes.
6. **Scroll** — `SetCRTCStart` rounds up and parks the offset, the rupture writes it at fire 2,
   left blanking on the play cycle. Verify by buffer diff *and* by the patched jsbeeb.
7. **Explore the original droid speeds** — `plySpdTab` back to the C64's numbers, played and timed
   against the 8 px build, recorded either way.
8. **Optional, later** — per-scanline `&FE23` on the static pages; attribute mode spike for the
   portraits.

## 9 Open questions for KC

1. **What is the detection method?** It needs writing into §1a/§5 before step 3, because its
   ordering constraints are the boot sequence's design, and because the negative path is what
   protects other people's machines.
2. Share the byte-identical files (`PARASPR`, `PARAFNT`, `PARDEPK`, `PARALOW`) between the two
   executables, or duplicate everything for a simpler disc layout? There is space for either;
   sharing is cheaper, duplicating keeps `make_disc.py`'s boot-order assumption simple.
3. Does the NuLA build get its own entry in `PLAN.md`, or its own document only? It is out of scope
   for the current plan but it lives in the same tree behind `IF NULA`.
4. Does anyone have the mod on real hardware? b2 is a full implementation, but the whole plan still
   rests on one emulator for its headline feature until something real has been looked at.
