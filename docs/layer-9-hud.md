# Layer 9 — HUD and console

**Status: planned 2026-08-16, built on branch `layer9-hud` off `layer7-combat`.**
Every decision KC might want to revisit is marked **[DECISION]** and collected in §7.

---

## 1. What the C64 actually does

Two separate things, and the plan in `PLAN.md` ran them together:

**The in-game status area is eight character rows at the top of the screen.** `DrawScreen`
(`$391A`) writes the deck to `$4940`, which is 320 bytes — eight rows of 40 — into the `$4800`
screen, and draws 17 rows. So rows 0-7 are status and rows 8-24 are the deck.

What is written there during play is much less than the space suggests:

| | |
|---|---|
| `DoScore` (`$0A7D`) | the score, at `prntY = 2`, `prntX = 30` — and **only when it changes** |
| `DoMoveMode` (`$31B9`) | `Mobile_txt` / `Weapon_txt` / `Transfer_txt` at row 2, column 2 — **only on the transition**, not every frame |

**There is no energy bar.** Energy is shown by the player's own sprite: `AnimateDroids` (`$3DE5`)
flashes sprite colour `$D02E` through `LowNrgColor_t` once `droidEnergy < 8`, and beeps. That is
the whole energy readout.

**The console is a separate full-screen mode**, not part of the status area. `Console` (`$2C04`)
dispatches through `conJump_t`; `conRedraw` calls `GotoHires`, `ClearGameScreen`, draws seven
sprites as the menu icons and then `ConsoleMain`. `con_DroidInfo`, `con_DeckInfo` and
`con_ShipInfo` each repaint the whole screen. It is entered from `consoleState`, which
`DoCharUnder` sets from character 66.

## 2. The font, and the constraint that follows from it

The text font is the charset at **`$7000`**, and it is **8 × 16, not 8 × 8**: the glyph's top half
is at code `c` and its bottom half at code `c + $80`. Rendered, codes `$00-$09` are the digits,
`$0A-$23` lowercase `a-z`, `$30` space, `$31-$37` frame pieces, `$3A-$53` capitals `A-Z`, and
`$2E` a full stop. `Mobile_txt` reads `$46 $18 $0B $12 $15 $0E` = `M o b i l e`, which confirms it.

**A MODE 1 character cell is 8 px × 8 scanlines = 16 bytes, so an 8 × 16 glyph is 32 bytes in two
stacked cells.** Our panel is `PANEL_ROWS = 5` rows of 640 bytes, so:

> **The panel holds exactly two lines of 40 characters, with one character row spare.**

The C64's eight rows hold four such lines. That is the single biggest constraint on this layer and
it is geometry, not effort — the 5-row panel was fixed in Layer 3 by the rupture and the 10K wrap.

## 3. Where it all lives

Main RAM is the binding constraint: `code_end` is `&2F24` against `SPR_SAVE` at `&3000`, so
**220 bytes**. Bank 4 has ~1,300 free, bank 6 ~3,687.

| | | |
|---|---|---|
| the font, shipped | `PARSPR2`, bank 6 | 66 glyphs × 32 B = 2,112 B. Bank 6 has the room and the blitter half of it is never wanted at the same time as the HUD |
| the font, at run time | **`&3C00`**, main RAM | copied up once at boot. Readable with no paging from anywhere, which is what makes the panel engine cheap and lets Layer 10 reuse it |
| the panel engine and the HUD | bank 4 | next to the game state it reads. `SWRAM_DATA` is the resting state, so the main loop calls it with no paging |

**[DECISION 1]** The font is copied to `&3C00-&443F` in main RAM rather than read from a bank.
`docs/memory-map.md` lists `&3C00-&47FF` as free-for-runtime-built-data, and the boot staging that
runs through it is finished long before the copy. It costs 2,112 bytes of a 3,072-byte hole and
buys: no paging in the panel engine, no paging in Layer 10's transfer game, and a font readable
from main RAM, bank 4 and bank 6 alike.

**[DECISION 2]** `MG_COPY`, `DEBUG_MAPGUARD`'s snapshot buffer, is moved from `&3C00` to `&4400`
because the font now occupies `&3C00`. The guard is a debug build option and BUGS.md #10 is fixed,
so it is also switched **off** by default — the code stays.

## 4. The glyph set, and how strings are written

66 glyphs, indexed:

```
    0        space
    1-10     digits 0-9
    11-36    capitals A-Z
    37-62    lowercase a-z
    63       full stop
    64       bar cell, full        \  synthesised, not in the C64 font
    65       bar cell, empty       /
```

**[DECISION 3]** The two bar cells are **synthesised, not ported.** The C64 has no energy bar to
take them from — see §1 — so there is nothing to be faithful to. They are a solid 6 × 12 block and
an outline of the same, drawn to sit on the same baseline as the letters.

Source strings are written as ordinary `EQUS "Mobile"` and converted at draw time by `PnAscii`,
twenty bytes of code, so the assembly reads as text rather than as a table of glyph numbers.

## 5. What the panel shows

Two lines of 40. Static labels are drawn once by `PanelFrame` at deck load; only the fields change.

```
 line 0   001 ##########  Mobile            Score 00000000
 line 1   Deck 01   Alert ####   Droids 12
```

| field | source | updated |
|---|---|---|
| droid number | `drType[0]` through `drNumber` | on change |
| energy bar, 10 cells | `drEnergy[0]` against `maxEnergy` | on change |
| mode | `moveMode` | on change, as `DoMoveMode` does |
| score | `score`, 4 bytes BCD | on change, as `DoScore` does |
| deck | `deck` | at deck load |
| alert bar, 4 cells | `alertLvl` bits 6-7 | on change |
| droids left | `drCount` | on change |

**[DECISION 4]** Two fields are shown that the C64 never displays in play: the **energy bar** and
**droids left**. Energy on the C64 is the sprite flash below 8 (§1), which is a fine cue for "about
to die" and useless for "should I transfer yet" — and the whole economy of the game is that
judgement. Droids-left is on the console's deck page there. Both are cheap and both make the game
readable; both are trivially removable if KC wants the original's austerity.

**[DECISION 5]** The sprite flash below energy 8 is **not** built. It needs a per-slot palette,
which MODE 1 does not have — the C64 changes one sprite's colour register, we would have to
re-blit the player in a different logical colour or flash the whole palette. Left for Layer 12.

## 6. The console

**[DECISION 6]** The console takes over the **play area**, not the whole screen, and the panel
stays. The C64 switches the whole display to hires and repaints it; our display is three CRTC
cycles with a scrolled 10K strip in the middle, and suspending that is a much larger change than
this layer should carry. The play buffer is 40 characters × 15 rows = **seven text lines**, which
is enough for the real pages, and leaving the panel up means the status stays visible exactly as it
does on the C64 (whose panel rows are also untouched by `GotoHires`).

Entry is `DoCharUnder`'s missing arm: character 66, the console tile, plus fire. Exit and page
selection follow `conWaitInput` — up/down move the selection, fire chooses, fire again returns.
Leaving restores the deck with `RedrawAll`.

Pages, in the order `conJump_t` has them: droid info, deck info, ship info. The **ship side view**
(`SideView_dat`, `$F180`, 201 bytes of RLE into a 64 × 16 character grid) is the fourth and is the
one piece of Layer 9 with real data still to port.

## 7. Decisions to revisit

| # | Decision | Why it might be wrong |
|---|---|---|
| 1 | Font copied to `&3C00` in main RAM | 2,112 B of a 3,072 B hole. If Layer 10 or 11 needs that hole more, the font can go back to being read from bank 6 at a cost of ~16 cycles a glyph |
| 2 | `MG_COPY` moved to `&4400`, `DEBUG_MAPGUARD` off | only matters if another map-corruption bug turns up |
| 3 | Bar cells synthesised | they are the only non-C64 artwork in the port |
| 4 | Energy bar and droids-left shown, which the original does not | it is a readability change, and readability changes are exactly what "preserve the gameplay" might not want |
| 5 | No low-energy sprite flash | a real cue is missing until Layer 12 |
| 6 | Console in the play area, not full screen | the C64's is full screen and has a different shape; ours will fit seven lines where theirs fits eleven |
| 7 | Panel palette still shared with the deck | `PLAN.md` flagged this. The panel's colours change per deck, so the text could read badly on some schemes. Fixing it means a palette write in the rupture IRQ, per cycle — deferred, and the text colour is checked by eye across decks instead |
