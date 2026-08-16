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

Main RAM is the binding constraint: `code_end` is `&2F03` against `SPR_SAVE` at `&3000`, so
about 250 bytes. This moved twice while the layer was built, and the final arrangement is:

| | | |
|---|---|---|
| the font | **its own disc file, `PARAFNT`** | 92 glyphs × 32 B = 2,944 B, catalogue load address `&3C00`, so `*LOAD` puts it exactly where it runs |
| the font, at run time | **`&3C00-&477F`**, main RAM | readable with no paging from main RAM, bank 4 and bank 6 alike |
| the four droid tables | **`&4780-&47DF`**, main RAM | `drCent`, `drNum`, `drWeapon`, `drSpeed`, copied out of bank 4 at boot by `PageTabsIn` |
| the panel engine, the HUD and the console | **bank 6** | with a main-RAM bridge for the live state |

**[DECISION 1]** The font is a **fourth disc file** rather than bank data copied down. It started
shipped in bank 6 with a `PageFontIn` copy, which was pointless once it turned out it had to live
in main RAM anyway: a disc file with a catalogue load address does the same job with no code at
all. It must be `*LOAD`ed **after all three bank loads**, because `PARADAT`'s staging area runs
from `&3000` past `&7000` and straight over `&3C00`.

**[DECISION 8]** The panel and the console are in **bank 6**, not bank 4 where they started.
The console pushed bank 4 to `&C0E0`, 224 bytes past the end, and there is nothing left in that
bank to move: the obvious candidate, `chardata`, is read by `BuildCharset`, which also reads
`deckScheme`, `colourMap`, `schemes` and `charSlot`, so it cannot be separated from them.

**The price is that neither file can read bank 4**, where `drType`, `drEnergy`, `drCount`,
`shipLevel` and the four droid tables live. Main RAM carries them across in two pieces: the tables
are constant and are copied once at boot; the four scalars move and are mirrored per call by
`PanelTick`, `PanelSetup`, `ConsoleEnter` and `ConsoleTick` in `main.asm`, each of which fills the
mirror **before** paging bank 6 in. `conActive` is in main RAM for the same reason — `ConsoleTick`
has to read it after paging bank 6 back out, because leaving the console means `ReframeView`, which
calls `RedrawAll` in bank 4.

**[DECISION 2]** `DEBUG_MAPGUARD` is **off**, and now has to be: its 1K snapshot lived at `&3C00`
and the only 1K left below the panel starts at `&4440` and runs 64 bytes past it. `droid.asm`'s
asserts say what to move to turn it back on. BUGS.md #10, which it was written for, is fixed.
`DEBUG_VSYNC` is off too — it wrote its digit over the HUD's droid number — and `DEBUG_ENERGY`,
which owns the same panel row; turning that one on suppresses the HUD rather than colliding.

## 4. The glyph set, and how strings are written

92 glyphs, indexed:

```
    0        space
    1-10     digits 0-9
    11-36    capitals A-Z, LEFT half
    37-62    capitals A-Z, RIGHT half
    63-88    lowercase a-z
    89       full stop
    90       bar cell, full        \  synthesised, not in the C64 font
    91       bar cell, empty       /
```

**CAPITALS ARE 16 PIXELS WIDE**, which `DrawChar` (`$0C5F`) states outright. Having written the
code and `code | $80` for the glyph's two rows it tests

```
    AND #$7F : CMP #$3A : BCC _1 : CMP #$5A : BCS _1   ; "see if it was wide"
    LDY #1 : ADC #$20 : STA (cpyDest),Y ... : INC prntX
```

so a capital's right half is at code `+ $20` and it occupies two character cells. Each is exported
as two glyphs and `PnStr` draws the second whenever the first is in the capital range — the same
test in the same place. Lowercase and digits stay one cell. **Columns therefore count cells, not
letters**: `Deck` is 5 wide, `Alert` 6, `Droids` 7, `Transfer` 9.

**[DECISION 3]** The two bar cells are **synthesised, not ported.** The C64 has no energy bar to
take them from — see §1 — so there is nothing to be faithful to. They are a solid 6 × 12 block and
an outline of the same, drawn to sit on the same baseline as the letters.

Source strings are written as ordinary `EQUS "Mobile"` and converted at draw time by `PnAscii`,
twenty bytes of code, so the assembly reads as text rather than as a table of glyph numbers.

## 5. What the panel shows

Two lines of 40. Static labels are drawn once by `PanelInit` at deck load; only the fields change.

```
 line 0   001 ########  062  Mobile          00000000
 line 1   Deck 01   Alert ####   Droids 11
```

| field | source | updated |
|---|---|---|
| droid number | `drType[0]` through `drCent` + `drNum` | on change |
| energy bar, 8 cells | `drEnergy[0]`, **one cell per 8** | on change |
| the ceiling | `maxEnergy`, three digits | on change |
| mode | `moveMode` | on change, as `DoMoveMode` does |
| score | `score`, 4 bytes BCD | on change, as `DoScore` does |
| deck | `deck` | at deck load |
| alert bar, 4 cells | `alertLvl` bits 6-7 | on change |
| droids left | `drCount` | on change |

**[DECISION 9]** The energy bar is **absolute, one cell per 8**, not a fraction of `maxEnergy`.
It needs no divide, and 8 is the number the C64 itself treats as the danger line — `AnimateDroids`
starts flashing the player's sprite below it — so **one cell lit is exactly that warning**. A full
`CB_ENERGY_FULL` of `$40` fills all eight. The cost is that the bar does not shrink as the ceiling
ages, which the number beside it shows instead.

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
| 6 | Console in the play area, not full screen | the C64's is full screen and has a different shape; ours fits seven lines where theirs fits eleven |
| 8 | Panel, HUD and console in bank 6, with a main-RAM bridge | it is a bank boundary in the middle of one layer's code. If bank 4 ever gets 1.4K back they could all move home and the bridge would go |
| 9 | Energy bar absolute, one cell per 8 | it does not track the ceiling as it ages |
| 10 | Console pages are Ship and Droids | the C64 has the **deck map** (`DrawPacked` over the level RLE) and the **ship side view** (`SideView_dat`, `$F180`, 201 B of RLE into a 64 × 16 grid). Both need real data ported and are the honest remainder of this layer |
| 7 | Panel palette still shared with the deck | `PLAN.md` flagged this. The panel's colours change per deck, so the text could read badly on some schemes. Fixing it means a palette write in the rupture IRQ, per cycle — deferred, and the text colour is checked by eye across decks instead |
