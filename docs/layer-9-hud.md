# Layer 9 — HUD and console

**Status: planned 2026-08-16, built on branch `layer9-hud` off `layer7-combat`.**
Every decision KC might want to revisit is marked **[DECISION]** and collected in §7.

---

## 1. What the C64 actually does

Two separate things, and the plan in `PLAN.md` ran them together:

**The in-game status area is eight character rows at the top of the screen.** `DrawScreen`
(`$391A`) writes the deck to `$4940`, which is 320 bytes — eight rows of 40 — into the `$4800`
screen, and draws 17 rows. So rows 0-7 are status and rows 8-24 are the deck.

**The artwork in it is four `DrawString` calls from `StartGame`, `$1135-$114E`:**

| addr | Y,X | contents |
|---|---|---|
| `$6900` | 0,0 | `$55` + 18 × `$56` + `$57` — the top border |
| `$6917` | 2,0 | `$7C`, 14 spaces, **the logo** `$31 $32 $33 $32 $34 $33 $35 $36 $37`, 6 spaces |
| `$6937` | 2,38 | space, `$7C` — the right edge |
| `$693C` | 4,0 | `$58` + 18 × `$59` + `$7A` `$7B` — the bottom border |

`$6917` runs on past its own end into `$6937`'s two header bytes and prints four cells of junk at
columns 30-33 — which is exactly where `DoScore` then writes, so nothing shows. The overlap is
deliberate, not a disassembly artefact.

`$55`-`$59` fall in `DrawChar`'s wide range, so each is 16 px and two cells; `$7A`, `$7B` and `$7C`
are 8 px and one. Both border rows therefore have the **same shape** — two cells, eighteen pairs,
two cells — which is why one loop draws either.

What changes during play is much less than the space suggests:

| | |
|---|---|
| `DoScore` (`$0A7D`) | the score, at `prntY = 2`, `prntX = 30`, **eight BCD digits with leading zeros blanked** — and only when it changes |
| `DoMoveMode` (`$31B9`) | `Mobile_txt` / `Weapon_txt` / `Transfer_txt` at row 2, column 2 — **only on the transition**, not every frame |
| `Console` (`$2C5B`) | `Console_txt` (`$69E4`) into the same field, on entering the console |

All four mode words are `prntY = 2`, `prntX = 2` and **11 cells wide**, padded with `$30`, so a
shorter one wipes a longer one behind it.

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
`$0A-$23` lowercase `a-z`, `$2E` a full stop, `$30` space, **`$31-$37` the Paradroid logo**,
`$3A-$53` capitals `A-Z`, and `$55-$59`, `$7A-$7C` the status box frame. `Mobile_txt` reads
`$46 $18 $0B $12 $15 $0E` = `M o b i l e`, which confirms it.

`export_font.py` used to call `$31-$37` "frame pieces (not exported)". They are not: rendered side
by side in `$6917`'s order they read `▌aradroid.` under an overline — the stylised logo. The frame
is `$55-$59`, `$7A`, `$7B` and `$7C`, and the two sets were transposed.

**A MODE 1 character cell is 8 px × 8 scanlines = 16 bytes, so an 8 × 16 glyph is 32 bytes in two
stacked cells.**

## 2a. Thirty-two scanlines, not sixty-four

The four strings fill screen rows 0-5, but **the ink does not**. Render them and scan for ink:

```
    scanlines  0-7    solid, all 40 cells        the surround above the box
    scanline   8      the corners start to curve
    scanline   10     the top edge
    scanlines  16-31  the text line
    scanline   37     the bottom edge
    scanline   39     the corners finish
    scanlines  40-63  solid, all 40 cells        the surround below it
```

> **The box is scanlines 8 to 39 — exactly 32 — inside a 64-scanline region that is otherwise
> flat surround.**

That maps onto **four** BBC character rows and not five, so `PANEL_ROWS` went 5 → 4:

```
    row 0     the BOTTOM halves of $55/$56/$57 and their right halves
    rows 1-2  ONE line of 40: the bars, the mode word, the logo, the score
    row 3     the TOP halves of $58/$59/$7A/$7B
```

**It cost one CRTC register.** The panel cycle is 7 rows and displays `PANEL_ROWS` of them via R6,
written at VSync; nothing else in the rupture moved, no T1 interval changed, and the play cycle
still starts at P+64−`line`. The gap below the box grew from 24−`line` scanlines to 32−`line`,
which is the original's own gap. `PANEL_ADDR` moved `&4800` → `&4A00` so the 640 bytes freed go to
the font, which needed another 448 for the logo and frame glyphs.

## 3. Where it all lives

Main RAM is the binding constraint: `code_end` is `&2F03` against `SPR_SAVE` at `&3000`, so
about 250 bytes. This moved twice while the layer was built, and the final arrangement is:

| | | |
|---|---|---|
| the font | **its own disc file, `PARAFNT`** | 98 glyphs × 32 B = 3,136 B **+ 192 B of border cells**, catalogue load address `&3C00`, so `*LOAD` puts it exactly where it runs |
| the font, at run time | **`&3C00-&48FF`**, main RAM | readable with no paging from main RAM, bank 4 and bank 6 alike |
| the four droid tables | **`&4900-&495F`**, main RAM | `drCent`, `drNum`, `drWeapon`, `drSpeed`, copied out of bank 4 at boot by `PageTabsIn` |
| the panel | **`&4A00-&53FF`**, 4 rows | moved up from `&4800` when it shrank; the 640 bytes went to the font |
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

**The price is that neither file can read bank 4**, where `drCount`, `shipLevel` and the four
droid tables live. Main RAM carries them across in two pieces: the tables
are constant and are copied once at boot; the two scalars move and are mirrored per call by
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

102 glyphs, indexed:

```
    0        space
    1-10     digits 0-9
    11-36    capitals A-Z, LEFT half
    37-62    capitals A-Z, RIGHT half
    63-88    lowercase a-z
    89       full stop                ($28)
    90-96    the logo, cells 0-6      ($31-$37)
    97       the box's vertical bar   ($7C)
    98       dash                     ($2E)
    99       colon                    ($2A)
    100-101  the RIGHT halves of m and w
```

### WIDE is not the same as CAPITAL

**Corrected 2026-08-16, while porting the console.** `ToUpper` (`$2E3D`) is the authority on the
code map, and it special-cases three codes before falling back to "capital = lowercase + `$30`":

```
2E4B  CMP #$54 : BEQ _1     ; 'w' is $54, and its capital is $50
2E4F  CMP #$42 : BEQ _2     ; 'm' is $42, and its capital is $46
2E53  CMP #$12 : BEQ _3     ; 'i' $12 -> capital I is $16, not $42
2E57  CMP #$16 : BEQ _x     ; and $16 is already that capital
2E5B  CMP #$A : BCC _x : CMP #$24 : BCS _x : ADC #$30
```

So **lowercase m and w are 16 px** and live at `$42` and `$54`, outside the a-z run; the `$16` and
`$20` slots the alphabet would give them hold **capital I**, which is narrow — a bare stem — and a
symbol. Render `$42` and `$46` side by side and they are the same double-arch shape, one lowercase
and one capital.

`export_font.py` had all three wrong, and the full stop as `$2E`. `$2E` is the **dash**: the
separator in `Blk-Whte` (`$69D8`), in the deck name `robo-stores`, and on the console's own
`Unit type 001 - Influence device` line. The full stop is `$28`, the low dot that the comma `$29`
and semicolon `$2B` are built from by adding a tail.

**None of it ever showed**, because no word the panel draws — `Mobile`, `Weapon`, `Transfer`,
`Console`, and before them `Deck`, `Alert`, `Droids` — contains m, w, capital I or a full stop.
`PnWide` now makes exactly the three exceptions the original makes.

plus a separate 192-byte `panelframe` table of **twelve 16-byte border cells** — half glyphs, not
whole ones, because the border rows contribute only their inner 8 scanlines to the box. Both ship
in `PARAFNT`, one after the other.

**Nothing is synthesised any more.** The two energy-bar cells that used to sit at 90 and 91 went
with the energy bar itself.

**CAPITALS ARE 16 PIXELS WIDE**, which `DrawChar` (`$0C5F`) states outright. Having written the
code and `code | $80` for the glyph's two rows it tests

```
    AND #$7F : CMP #$3A : BCC _1 : CMP #$5A : BCS _1   ; "see if it was wide"
    LDY #1 : ADC #$20 : STA (cpyDest),Y ... : INC prntX
```

so a capital's right half is at code `+ $20` and it occupies two character cells. Each is exported
as two glyphs and `PnStr` draws the second whenever the first is in the capital range — the same
test in the same place. Lowercase and digits stay one cell. **Columns therefore count cells, not
letters**: `Mobile` is 7 wide, `Transfer` 9, `Console` 8 — all padded to the original's 11.

Source strings are written as ordinary `EQUS "Mobile"` and converted at draw time by `PnAscii`,
twenty bytes of code, so the assembly reads as text rather than as a table of glyph numbers.

## 5. What the panel shows

**The C64's status line, cell for cell, and nothing else.** One line of 40 between the two border
rows. The frame, the two bars and the logo never move and are drawn once by `PanelInit` at deck
load; two fields change.

```
 |  Mobile        Paradroid.          335 |
 0  2             15                30  37 39
```

| field | column | source | updated |
|---|---|---|---|
| box bars | 0 and 39 | `$7C`, from `$6917` and `$6937` | never |
| mode | 2, 11 cells | `moveMode`, or `conActive` | on change, as `DoMoveMode` does |
| logo | 15-23, 9 cells | `$31-$37` in `$6917`'s order, in red | never |
| score | 30-37, 8 BCD digits | `score`, in red | on change, as `DoScore` does |

The score's **leading zeros are blanked and the last digit is not**, which is `DoScore`'s own rule
at `$0AE6`-`$0B01`: a "blank char" starts as `$30` and becomes `0` at the first non-zero digit.
Our glyph indices make that arithmetic rather than a branch — `PN_SPACE` is 0 and `PN_DIGIT0` is
1, so the blank char *is* the base the nibble is added to.

**Console is the fourth mode word.** `DoMoveMode` only writes three; the C64 draws `Console_txt`
from `Console` itself at `$2C5B`, into the same field. `PanelUpdate` dispatches on `conActive`
first and `moveMode` second, and `PanelTick` still runs while the console is up — as the C64's
status rows survive `GotoHires`.

### 5a. Colour: the panel has its own palette

The C64's status area is **grey on white with the logo and the score in red**. Our panel used to
share the deck's four colours, and those share only logical 0 (blue) and logical 1 (white) across
all sixteen decks — 2 and 3 vary, and are *black* on some, so a panel drawn in either would vanish
on those decks. This is the item `PLAN.md` carried as "panel shares the play palette", and it is
now closed.

The panel and the play area are separate CRTC cycles, so they are separate palettes: sixteen ULA
writes at each boundary, ~210 cycles each.

| logical | panel | drawn in it |
|---|---|---|
| 0 | white | the inside of the box |
| 1 | — | unused |
| 2 | red | the logo, the score |
| 3 | black | the frame, the mode word |

Where the two writes go is not free choice:

- **the panel's, at the END of `RuptVSync`.** The tail cycle displays nothing and the panel starts
  40 scanlines later, so there is no deadline — but it must come *after* the T1 restart, because
  delaying that shifts every fire in the frame.
- **the deck's, at the END of fire 1.** The panel stopped displaying at P+32 and the play cycle
  starts at P+64−`line`, so the window is free; last means R4 and the T1 latch are already written
  and nothing timing-critical moves.

`SetPalette` therefore builds a 16-byte `palPlay` table instead of writing the ULA, and that table
is **in main RAM** although `SetPalette` is in bank 4: the interrupt reads it three times a frame
and may fire with bank 5 or 6 paged in.

Recolouring is an **AND per byte**. A MODE 1 byte's bits 7-4 are its four pixels' high colour bits
and bits 3-0 their low ones, so the font — exported as logical 3 — becomes logical 2 with `AND
#&F0` and logical 1 with `AND #&0F`. `pnMask` carries it; `PnAt` and `ConAt` both reset it to
`&FF`, so a red field cannot leak into the next thing drawn.

**[DECISION 5]** The sprite flash below energy 8 is **not** built. It needs a per-slot palette,
which MODE 1 does not have — the C64 changes one sprite's colour register, we would have to
re-blit the player in a different logical colour or flash the whole palette. Left for Layer 12.
With the energy bar gone (decision 4), **this is now the only energy readout the port is missing**,
and the game has none at all until it lands.

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

Decisions 3, 4 and 9 are **reversed**, and 7 is **closed**, by KC's ruling of 2026-08-16: the
status line is to be the C64's exactly — the frame, the logo, the score and the mode word, and
nothing else. Kept below with the outcome, because the reasoning is the record of what was traded.

| # | Decision | Status |
|---|---|---|
| 1 | Font at `&3C00` in main RAM | **stands.** Now 3,328 B of a 3,584 B hole. It must be main RAM: bank 4 and bank 6 both read it and only one is visible at a time |
| 2 | `MG_COPY` moved, `DEBUG_MAPGUARD` off | stands; only matters if another map-corruption bug turns up |
| 3 | Bar cells synthesised | **reversed.** Gone with the energy bar. Every byte of panel artwork is now the C64's |
| 4 | Energy bar and droids-left shown, which the original does not | **reversed.** Both dropped. The cost is that the game has *no* energy readout at all until decision 5 is built — the C64's cue is the sprite flash, and that is Layer 12 |
| 5 | No low-energy sprite flash | stands, and matters more now: it is the only energy cue the port is missing rather than one of two |
| 6 | Console in the play area, not full screen | stands. The C64's is full screen and has a different shape; ours fits seven lines where theirs fits eleven |
| 7 | Panel palette shared with the deck | **closed.** The panel is a separate CRTC cycle and now has its own four colours — §5a. Sixteen ULA writes at each boundary, ~210 cycles, twice a frame |
| 8 | Panel, HUD and console in bank 6, with a main-RAM bridge | stands, and is now Layer 13's to unpick. The bridge shrank to two scalars when the droid number and energy bar went |
| 9 | Energy bar absolute, one cell per 8 | **reversed** with decision 4 |
| 10 | Console pages are Ship and Droids | stands. The C64 has the **deck map** (`DrawPacked` over the level RLE) and the **ship side view** (`SideView_dat`, `$F180`, 201 B of RLE into a 64 × 16 grid). Both need real data ported and are the honest remainder of this layer |
| 11 | The surround is **black**, where the C64's is grey | new. The original fills all eight status rows with the surround colour and puts the box in the middle 32 scanlines; we draw the box alone and leave the rest CRTC-blanked. Covering it needs all eight rows displayed — 5,120 bytes against a 7-row panel cycle |
| 12 | The box sits at the **top** of the display; the C64's is 8 scanlines down | new, and cosmetic given 11: the same 32 scanlines of box, 8 px higher against black. Matching it exactly means displaying 5 rows with the first blank, which costs 640 bytes and a second `PANEL_ADDR` |
