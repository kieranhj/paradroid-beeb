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
| the font | **its own disc file, `PARAFNT`** | 103 glyphs × 32 B = 3,296 B **+ 192 B of border cells** (`FONT_GLYPHS`; 98 when this was written), catalogue load address `&3C00`, so `*LOAD` puts it exactly where it runs |
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

**[DECISION 5 — superseded 2026-08-19]** The sprite flash below energy 8 was **not** built, and
the reason given here was that it could not be: MODE 1 has no per-slot palette, so we would have
had to re-blit the player in a different logical colour or flash the whole palette. **It is built.**
The premise was wrong in an interesting way — a compiled sprite *can* be told its colour, because
the artwork is stored at logical 3 and choosing a colour is choosing a nibble. The eleven distinct
pixel patterns live in zero page and `SprSetColour` rewrites them. See `docs/layer-5-blitter.md`
§ "Colour is not baked in" and the [DECISION] there.

With the energy bar gone (decision 4) this was the only energy readout the port was missing, so it
is also the thing that decision most needed.

## 6. The console

**[DECISION 6]** The console takes over the **play area**, not the whole screen, and the panel
stays. The C64 switches the whole display to hires and repaints it; our display is three CRTC
cycles with a scrolled 10K strip in the middle, and suspending that is a much larger change than
this layer should carry. Leaving the panel up means the status stays visible exactly as it does on
the C64, whose panel rows are also untouched by `GotoHires`.

Entry is `DoCharUnder`'s missing arm: character 66, the console tile, plus fire. **L leaves.**

### 6a. The screen is `ConsoleMain`'s, line for line

**Rebuilt 2026-08-16 at KC's request.** `ConsoleMain` (`$2955`) and `ShowRobotType` (`$3149`) draw
five lines, and the strings carry their own `prntY`/`prntX`:

| C64 screen | C64 console row | ours | |
|---|---|---|---|
| row 10, col 2 | 2 | row 1 | `Unit type 001 - Influence Device` |
| row 12, col 12 | 4 | row 3 | `Access granted.` |
| row 15, col 12 | 7 | row 6 | `Ship  : Paradroid` |
| row 18, col 12 | 10 | row 9 | `Deck  : Staterooms` |
| row 21, col 12 | 13 | row 12 | `Alert : Green` |

**The C64's console area is screen rows 8-24.** `ClearGameScreen` (`$2BA5`) fills 17 rows from
`$4940` — that is `$4800 + 320`, so row 8 — at 40 bytes a row (`FillCRAM`, `$0A52`). Its five lines
are therefore console rows 2, 4, 7, 10 and 13, with rows 0 and 1 empty. The 2/3/3/3 spacing is the
original's, and is what leaves a blank row between the lower four. `ConAt` therefore takes a
**buffer row** and not a text line — a line-times-two index cannot express 6, 9, 12.

**Ours sat two rows above that until 2026-08-24.** The layout was originally flattened to the top
row (0, 2, 5, 8, 11) because the play area was fifteen rows and 13 + 2 did not fit. Sixteen rows
since 2026-08-21 bought one back, and **[DECISION 17] KC, 2026-08-24: spend it on the menu** —
everything moves down one, to 1, 3, 6, 9 and 12.

**That is still a row short of the C64's own 2, 4, 7, 10, 13, and deliberately so.** Two rows
also fits (the alert glyph would land on 13-14 and its icon on 13-15, filling the area exactly);
KC was shown both and chose one. Do not "correct" it to two without asking.

**The whole menu moves as one.** The four icons ride the lower four lines and the marker bar sits
one row into each icon's three, so the icon destinations in `console.asm` are now written as
`CON_ROW_SHIP`/`DECK`/`ALERT` rather than literals, and the bar — `CON_MARK0-3` in `droid.asm`,
bank 4, which is assembled first and cannot see those constants — is `ASSERT`ed against them from
`console.asm` instead. They had been three independent sets of literals.

**Verified in the buffer** (not the screenshot), 2026-08-24: row 0 empty, text on 1-2, 3-4, 6-7,
9-10 and 12-13, icons at 3-5, 6-8, 9-11 and 12-14, the marker bar at row 4 unit 1, and row 15
clear — so nothing clips the bottom.

### 6b. The names are real, and they cost 1,542 bytes

`$C000` holds a count and 1,541 bytes of strings in which **the first character of each string has
bit 7 set**. There is no length byte and no terminator: string N starts at the Nth bit-7 byte and
runs to just before the next. `FindStrings` (`$2BCA`) walks it once at startup into 249 pointers;
we scan instead, because 498 bytes of index is more than bank 6 has and the console draws once.

`tools/export_strings.py` translates it to **our glyph indices** rather than the C64's charset
codes, so the 6502 printer is a straight copy with no code arithmetic, and appends one bit-7
sentinel so the last string terminates without a bounds check.

Everything is in there: the ten droid class words, `robot`/`droid`/`cyborg`, the eight ship names,
the sixteen deck names — `observation`, `bridge`, `airlock`, `reactor`, `research`, `stores`,
`staterooms`, `repairs`, `quarters`, `robo-stores`, `upper cargo`, `mid cargo`, `vehicle hold`,
`shuttle bay`, `engineering`, `maintenance` — and `green`, `yellow`, `amber`, `red`.

**[DECISION 13]** KC asked for `Ship : Paradroid` fixed and the deck and alert as numbers. Porting
the table for the droid name — which was asked for — makes the other three free, because
`ConsoleMain` indexes the same table for all four. So all of them are the original's, and there
are no placeholders to come back to.

`ShowRobotType` builds the droid name from three tokens: token 50, the hundreds digit as a token,
and then `device` if that digit is 0 or `((digit - 1) >> 2) + 10` otherwise — `robot` for 1-4,
`droid` for 5-8, `cyborg` for 9. Every token carries a **leading space**, which `$0BF1` draws
before the string and which is where the gaps between the words come from; `$3172`'s `DEC prntX`
closes the double gap after the separator, and is ported as a 16-byte subtract.

**[DECISION 14]** The separator is the original's `$2E`, a dash, and not the colon the request
described. It is the same glyph as in `Blk-Whte` and the deck name `robo-stores`.

### 6c. What is not built

**[DECISION 15 — superseded 2026-08-17]** The four menu icons were **drawn and inert** when this
layer closed; `conWaitInput`'s selection and dispatch are BUILT now (see 6e) — K/M walk the
marker, fire dispatches, entry 0 exits and entry 3 shows the ship's side view. The port's own
droid-database page stayed gone — it was never the C64's. (The C64's own database page landed
later, in §6f.)

The icons themselves are sprites 1-4 in `conRedraw`'s table at `$6B94`, at Y `$90`, `$AC`, `$C8`,
`$E0` and image pointers `$4F`, `$50`, `$A1`, `$A2`. **Three are built** — static hires artwork at
`$5400`, `$6840` and `$6880`: the droid `?` emblem, a circular ship-plan badge and a ship side
view, exported by `tools/export_icons.py`.

Sprite Y 144 is 11.75 character rows down a display whose first visible line is 50, and the four
text lines are at rows 12, 15, 18 and 21 — so **each icon sits level with a line**, three rows
apart, which is exactly the spacing of the four lower lines here. They go on our rows 2, 5, 8 and
11, one per line, and the last ends at row 13 of fifteen. X is in **4-pixel units**, not
characters: sprite X 52 and 40 are 28 and 16 pixels from the left edge, 7 and 4 units, and the
buffer's natural step is the 8-byte 4-pixel column so it does not need to be a whole character.
The two different indents are the original's.

**Two of them are X-expanded.** The eleven bytes of a record map onto `SpriteNum` (`$04`) through
`SpriteImage` (`$0E`), so byte 8 is `SpriteXExp` — and it is `$FF` for the ship plan and the side
view, `0` for the other two. They are **48 pixels wide on screen, not 24**. `SpriteMC` is `0` in
all four records, so none of them is multicolour, and `SpriteYExp` is `0`, so all four stay 21
scanlines.

The doubling happens **as they are drawn**, not in the data: baking it in costs 288 bytes and bank
6 does not have them — it overflowed the moment both wide icons were stored expanded. Doubling
four pixels to eight is two lookups in a **sixteen**-entry table, not 256, because the icons are
drawn white and white is logical 1, which is the low colour plane alone — so all four pixels of a
byte live in one nibble.

A narrow icon is **three flat 48-byte copies**: the six 4-pixel columns of a 24 px sprite are 48
consecutive bytes within one character row, and 21 scanlines is three rows. Nothing has to be
saved, because `ConClear` has just blanked the area.

> **The destination is not twice the source index**, and assuming it was produced convincing
> noise. A source byte is one *scanline* of one 4-pixel column — a column's eight bytes are eight
> consecutive scanlines — so doubling it produces the same scanline of **two columns**, which are
> eight bytes apart, not adjacent. Source `u*8 + s` goes to `u*16 + s` and `u*16 + s + 8`.

**The console is drawn in logical colour 1, not 3.** It lives in the play area and takes the
*deck's* palette, where logical 1 is physical 7 on all sixteen decks while 2 and 3 vary and are
black on several — so white is the only reliably light ink it has. `ConAt` sets `pnMask` to
`PN_INK_WHITE` for the text and `ConIcons` ANDs the same mask into every icon byte.

**[DECISION 16]** The top icon is the **player's own droid**, and it is composed rather than
copied. `$53C0` is blank in ROM: it is where `BuildDroidSprite` (`$3C77`) writes the three-digit
number and `AnimateDroids` (`$3CFB`) the rotor, which is why `conRedraw` sets `dType` from
`droidType` before it draws.

The port's own droid artwork could not be used. `export_droids.py` **compiles** it — 6502 with the
pixels baked in as immediates — so the compiled form cannot be read back, and it lives in the
sprite banks, which bank 6 cannot see. `tools/export_droidicon.py` emits a small copy of the two
pieces instead: one rotor phase, 10 rows × 3 bytes, and the ten digit glyphs at 8 rows × 1 byte —
**in main RAM since RAM pass 3b (2026-08-25)**, where bank 6's console and bank 7's transfer
icons both read it.
**110 bytes** against 1,743 for the full animated set at one shift. One phase, because the console
is a still screen — the C64's keeps spinning there only because its sprite is the same one the game
animates.

### 6d. All four are stored as the C64's own sprite bytes

Storing the MODE 1 conversion overflowed bank 6 by **346 bytes** once both wide icons and the droid
were in. Storing the original's 3-bytes-a-row form instead is **half the size and costs nothing to
undo**: a hires sprite byte is eight 1-bit pixels, the icons are drawn in logical colour 1, and
logical 1 is the *low colour plane alone* — so four pixels **are** one nibble, and a byte splits
into two output bytes with a shift and a mask. The X-expansion rides on the same nibble, through a
sixteen-entry table rather than 256.

That collapsed four icons onto one routine, `ConSprite`, each supplying its rows through a patched
`JSR` — because the droid is a sprite too, and `BuildDroidSprite` writes three bytes a row like
everything else.

> **The source is row major and the buffer is not.** A 4-pixel column's eight bytes are eight
> consecutive *scanlines*, so row `r` column `u` goes to `(r DIV 8)*640 + u*8 + (r MOD 8)`. The
> compiled blitter gets that transpose for nothing by being compiled; this pays for it in a loop,
> which is affordable because it runs once per console.

**Bank 6 now ends at `&BFE9` — 23 bytes free.** It is full, and Layer 13 or a fourth bank is the
next thing that touches it.


## 6e. The menu and the sub-pages — BUILT (2026-08-17)

**All of it is built now** — the selection, the ship plan, the deck plan, and (later the same
day) the droid database, which has its own section, §6f. The text below is as written when the
database was still open.

**The selection is built, and two of the three pages.** `conWaitInput`'s port is `ConMenu4` in
droid.asm — BANK 4, not bank 6, which was full; everything the menu touches (the keys, the play
buffer, `conActive`, the page-request flags) is main RAM, so it can be. `conSel` walks 0–3 with
K/M exactly as `consoleState` walks `$80`–`$83` — clamped, not wrapped — and fire dispatches as
`conJump_t` does: entry 0 exits to the game, entry 2 shows the **deck plan** and entry 3 the
**ship's side view** (both below); entry 1, the droid database, followed later the same day (§6f).
The selection is shown by **recolouring the icon**, as the C64 does — see DECISION 18 below. It
was a white marker bar until 2026-08-24, and that bar was ours, not the original's. The old
`ConsoleRun` ("L leaves, nothing else") is deleted — leaving is the menu's top entry now — which
put bank 6 back to 62 bytes free.

**The ship page is `con_ShipInfo` (`$3062`) faithfully**: the side view drawn once and STATIC —
the current deck lit, no shaft mark — and fire returns to the console main screen with the
selection kept (`con_Back2Main`'s `$C0` redraw, as `ConsoleTick`'s redraw path). It is Layer 8b's
drawer reused whole: `LvShip7` in bank 7 is `LvStart7` minus the shaft mark and the panel text,
with the lift palette swapped in around it (`ConShipEnter4/Exit4`). The console's 15 visible rows
lose nothing — the view's rows 13–15 are blank — so the 16th-row `t1i3` trick is not needed.
`ConsoleTick` (main.asm) is the conductor, since only main RAM can page: bank 4 for the menu,
bank 7 for the page, bank 6 for `ConDraw` on the way back.

**The deck plan is BUILT (2026-08-17)** — `con_DeckInfo` (`$3001`), the circular-badge entry.
It is `DrawPacked` again, the decoder the ship page runs over `svData`, but over the **level
RLE** — the same stream `BuildLevel` decodes into the tile map, read at full 7-bit width where
the game masks it to 5. That difference is the whole page: the plan reaches 28 characters the
tiles never touch (all sixteen streams were scanned: codes run `$00`-`$1E`, and `$29` never
appears — the `$29`→blank test is `svData`'s and cannot fire here, so it is not ported). Each
code is placed as ONE CHARACTER, the 64-wide grid clipped to columns 3-41, and the player's
tile is overwritten with a solid cell — char `$A0` in colour 1 there, sixteen bytes of logical
1 here, white on every deck.

**THE PAGE IS HIRES, and the CharColor trap bit a second time.** The first build drew from the
`&0400` play-area charset, where `BuildCharset` honours each character's per-deck multicolour
flag — and the flagged characters came out with multicolour fringes: red left edges on plain
floor tiles, garbled recharge pads (KC caught both). The console screen is `conRedraw`'s, which
calls `GotoHires` (`$31A4`, `$C0` into `_d016Mode`) — so on the C64 EVERY plan cell renders
hires, with colour RAM's full 4-bit value as its foreground and the multicolour flag as nothing
but a colour bit. `con_ShipInfo` pointedly puts `$D0` BACK for the side view, which is why the
ship page's multicolour handling is right and the plan must not share it. So the plan now has
its own rendering: `src/data/plandata.asm` in bank 7 carries the 31 raw C64 bitmaps plus a
per-deck ink table (`planInk`, deck×32 + code → logical 0-3) built at export time from the
C64's whole chain — `CharColor` slot → deck record → the deck's logical, with slots 12-15
giving colour 0, which is what the C64's own zeroed block at `$0221` gives THEM — and
`ConDeck7` expands each cell hires at plot time over background 0. The play-area charset is
untouched and the export's `used` set stays at 137.

The split follows the menu's rule about who may page:

| piece | where | why |
|---|---|---|
| `ConDeckEnter4` / `ConDeckExit4` | bank 4, droid.asm | the RLE lives in bank 4; the enter shim stages 512 bytes of the deck's stream (longest is ~333) at `SPR_SAVE` — the sprite saves are scratch while the console is up, since `ReframeView` discards them on exit — and moves `t1i3` to `T1_I3X`; the exit shim moves it back |
| `ConDeck7` + `plandata.asm` | bank 7, **condeck.asm** | the decode, the hires cell conversion and the marker, reading only main RAM and its own bank: the staged stream, `planChars`/`planInk`, the play buffer, `plyX`/`posY` |
| the `ConsoleTick` arm | main RAM | the only place allowed to page; the ship and deck return paths share one tail (`ct_back`), and `ConShipKeys4` became `ConPageKeys4`, clearing both request flags — only one is ever set |

The decisions, numbered in the ship page's pattern:

1. **[DECISION] The palette is the deck's own, unswapped.** That is the original's: con_DeckInfo
   takes its background from the deck record where con_ShipInfo installs fixed colours — so the
   deck plan keeps `palPlay` and the ship page keeps its `palLift` swap. **[REVISIT, KC
   2026-08-17]: look at the plan's palette again when the deck palettes get their all-up
   revisit** — the ink table (`planInk`, rebuilt by `tools/export_bbc.py`) and this choice
   should be re-judged together then.
2. **[DECISION] All 16 rows are shown**, by the transfer game's `t1i3` trick. Decks 2, 10, 11
   and 12 have map in row 15 and the C64 displays it; the console main screen goes back to 15
   rows before `ConDraw` repaints.
3. **[DECISION] The marker is CLIPPED where the C64's is not.** Decks 2, 14 and 15 have map
   beyond column 41; a player standing there would send the C64's unclipped store past the row's
   end. We skip the marker rather than reproduce the overwrite.
4. **[DECISION] Column 39 is drawn as code 0** — the map is 39 columns wide and the C64's 40th
   column keeps its cleared screen; ours gets the blank character, once per row, saving the run
   in flight because runs cross row boundaries.
5. **[DECISION, KC 2026-08-17] The console characters `$10-$13` draw in C64 red** (colour 2
   through the deck's `colourMap`), not their slot's colour — black on decks 0/4/9/11 and brown
   elsewhere, illegible either way. Baked into `planInk` at export.
6. **[DECISION, KC implied 2026-08-17] A legibility guard on the 4-colour compromise**: a glyph
   whose C64 colour is not the background but whose nearest logical is 0 — our background —
   takes the nearest of logicals 1-3 instead. The C64 shows those cells low-contrast; four
   colours would show nothing at all (deck 2's light-grey lift and door glyphs, for instance).
7. **Recharge pads render dark** — their char `$16` reads record slot 14, which is the zeroed
   `$0221` block on the C64 too, so this is the original's own look. KC: to be made legible by
   ANIMATION later, as the C64 game screen does, not by a colour override now.

Verified in jsbeeb on three decks (different maps, palettes and tile styles): menu → plan →
fire → console main with the selection kept and `t1i3` restored → ship page still good → exit to
the game with the deck repainted; no multicolour fringes, consoles red, marker white. The marker
was checked against the buffer, not the screenshot: solid `&0F` × 16 at exactly
`BUF_BASE + row*640 + col*16` for the cell `(plyX+11)>>5 − 3, (posY+63)>>5` — the same reference
cell CheckWalls uses, which is the C64's `plyMapPos`.

## 6f. The droid database — BUILT (2026-08-17), and the console is complete

`con_DroidInfo` (`$2CC6`), the `?` emblem, entry 1. It is the **fourth** page and the only
interactive one: the ship view and the deck plan are drawn once and wait for fire, and this is a
browser, so `ConsoleTick` calls `DbTick` (`src/condb.asm`, bank 7) every pass and the page decides
what to do — which is exactly how `GameLoop` calls `con_DroidInfo`. The five sub-pages are
`dInfoPgJump_t`'s (`$6BE9`), ported one for one:

| C64 | ours | what it does |
|---|---|---|
| `DrInfo0` `$2D79` | `DbPage0` | clear, reset the print position, go to 1 |
| `DrInfo1` `$2CF0` | `DbPage1` | the browser: up/down walk the type, image and name redraw every pass, left/right start the pages |
| `DrInfo2` `$2D34` | `DbPage2` | stat lines until the screen is full, then 3 |
| `DrInfo3` `$2D40` | `DbPage3` | `More...` in the status line; left/right resumes |
| `DrInfo4` `$2D6A` | `DbPage4` | the end: any direction goes back to 0 |

**The clamp is the rule of the page and is ported exactly.** `$2CFC`-`$2D1A` walks `dType` between
0 and `droidType` — the player's own class — and **wraps at both ends**: up past your own class
drops to 001, down from 001 jumps to your own. You cannot read up on a droid better than the one
you are wearing. `pmType` is `drType`'s main-RAM mirror and stands in for `droidType`.

**The layout is the original's line for line, which was luck and worth recording.** The C64 puts
the name at screen row 10 and steps its content lines 12, 14 … 22 — six of them, because `$2DC4`
stops at 24. A glyph is 8 × 16 here, so a text line is two buffer rows and the console's fifteen
hold **seven**: the name on line 0 and **six** content lines. Nothing had to be dropped, moved or
rescaled, and the columns are the original's too — labels at 9 (`$2D94`), the wrap margin at 12
(`byte_0_45`), a continued description at 11 (`$2DDF`), all against the same 40-column screen.

**Word wrap is `sub_0_BE9`'s, including the two things about it that look like bugs.** The routine
draws its leading space *before* measuring, so a word that wraps leaves that space at the end of
the old line; and it measures **cells, not letters**, with a capital counting two — which is why
`ToUpper` runs *before* the measure and why our `DbTok` decides capitalisation before it measures
rather than while it draws. A word that will not fit on the last line is **not drawn and not
consumed**: the index still points at it, which is what lets `More...` resume mid-sentence.

The stat lines are `sub_0_2DA0`'s self-modifying counter, which is the one piece of the original
that has to be read twice to believe: `sub_0_2DA0+1` runs 13 to 23 and is **both** the label's
token number **and**, less seven, the record byte the value comes from. So the ten labels are
tokens 13-22 (`entry `, `class `, `height`, `weight`, `drive `, `brain `, `armament`,
`sensors  1`, `2`, `3`), each followed by token 24 (`: `), and `PrintDroidInfo` (`$2F57`) computes
four of the values and reads the other six as token numbers.

The decisions, in the pages' pattern:

1. **[DECISION] The page lives in BANK 7 and the string table is emitted TWICE.** It needs the
   `$C000` table (1,542 B) and a glyph printer; both are in bank 6, which had 63 bytes free, and
   only one bank is visible at a time. Main RAM had 53 bytes and bank 4 about 300, so neither
   could take the page either. The alternatives were costed: *staging* the table into `SPR_SAVE`
   through a bank-6 copier would save 1.5 K of bank 7 but spend ~30 bytes of main RAM and ~30 of
   bank 6 — the two scarce resources — and *moving* the whole console out of bank 6 would avoid
   the duplication but is a refactor of working code that still needs its own bank-7 printer.
   **Duplicating spends the resource there is most of.** `tools/export_strings.py` and
   `tools/export_droidicon.py` now emit `strings7.asm` and `droidicon7.asm` alongside their
   originals, from the same byte lists, so the copies cannot drift — the plandata.asm precedent.
   Cost: bank 7 goes from 6,170 bytes free to **2,074**; bank 6 and bank 4 are untouched, and
   main RAM pays 33 bytes for the conductor's arm and one flag.
   *(Since superseded on both counts: Layer 13a TASK 7 took the string table to ONE main-RAM
   copy in the `PARAFNT` file, and `droidicon7.asm` was deleted by Layer 13d, revived by
   layer-10 DECISION 14, then deleted for good by RAM pass 3b — the one icon copy is main
   RAM's now. The costing above is the historical record of why duplication was right when
   bank 7 was the plentiful resource.)*
2. **[DECISION — RESOLVED 2026-08-20: the page draws the C64's portrait.]** The revisit this
   entry used to carry is done: KC reversed the deferral, the title moved out to the `PARTITL`
   disc overlay to fund it, and `portrait.asm` + `portraits.asm` in bank 7 now compose
   `BuildIntroSprites`' (`$3629`) **48 × 84 portrait** in `DbImage`'s place. The costing that
   deferred it was wrong: only the LEFT column of the 2 × 4 sprite grid is stored (the right is
   `MirrorSprite`'s at runtime, ours as theirs), the 24 records share their images, and the
   unique pool is **63 sprites = 4,032 bytes verbatim** — not 6 K, and never 24 K, because one
   multicolour pair is exactly two MODE 1 pixels and `PoDraw` expands at draw time the way
   `FontCell` does. Byte 63 of each image is bit 7 = multicolour, bits 0-4 = `rptLen`, the
   stacking step ($3670$-$367C$); pairs overlap when it is under 21 and the upper sprite wins,
   so `PoDraw` composes bottom-up through `SPR_MASKTAB` transparency. The rectangle is the
   stand-in's own: rows 2-12, units 4-15 — sprite X 40 / Y 144, translated. **Verified
   byte-for-byte** against a Python replay of `BuildIntroSprites` (types 0, 14, 23 — mirror,
   explicit-right and hires paths — 0 of 1,008 bytes differing each). The rotor-and-digits
   stand-in and `droidicon7.asm` are deleted; `DbImage` is now a guard (repaint only when the
   type or a clear demands) in front of `PoDraw`. The page palette maps each 2-bit value to its
   logical colour; the C64's per-type sprite colour themes are Layer 14's with every other
   palette. Still owed: an in-game play-check of the page, and a parameterised rectangle so
   `NewShipInfo`, `ShowXferInfo` and the game-over 999 can share the renderer.
3. **[DECISION] `More...` goes in the STATUS LINE, as `More_txt` (`$6C08`) says.** Its own
   `prntY`/`prntX` are 2 and 2 — the mode word's field, where `Console` is — and `$2D4F` puts
   `Console_txt` back when the stick continues. Bank 7 already writes that field (the transfer
   game's `XfGlyphAt`), and `PanelUpdate` will not fight for it because it rewrites the field
   only when the mode *changes*. **Leaving the page while the prompt is up leaves `More...`
   standing**, which is the original's behaviour too — `ConsoleMain` does not repaint the field
   either, and `PanelSetup` puts it right on the way out of the console.
4. **[DECISION] Fire is EDGE triggered, as the other two pages are.** `$2CC6` tests `joyFire`
   *first* and returns to the console the moment it is **released** — the C64 expects you to hold
   the button down while you browse. That cannot share a keyboard with the four browse keys, and
   the ship page and the deck plan already made this deviation (`ConPageKeys4`). Keys are the
   console's own: K/M up and down, **Z/X left and right** — the game's own `joyXDir` keys, which
   is the axis `$2D27` reads — and L to leave.
5. **[DECISION] Heights really are "1.xx m".** `Height_txt` (`$6C15`) is `1`, `.`, two patched
   digits, ` `, `m`, and only `+2`/`+3` are ever written — so the record byte is the two decimal
   places and every droid in the game is one point something metres tall. Weights print with
   **leading zeros** (`027 kg`), which is `$2FC0`'s own doing: it writes digit glyphs, and unlike
   `DoScore` it never blanks them.
6. **No sound.** `sndFx1` is written at five points in these routines (`$2CF4`, `$2D2F`, `$2D4B`,
   `$2D76` and the entry). Sound is not ported at all yet, so they are dropped — **Layer 12**,
   with the low-energy flash.
7. **A bug fixed in the console main screen, found by building this.** `ConTok` never cleared
   `conCap`, where `ToUpper` (`$2E75`) clears `byte_0_248` on *every* call so that exactly one
   word is capitalised per `INC`. The name line therefore drew `Influence Device` where the C64
   draws `Influence device` — `$316F` sets the flag once and the class word after the class NAME
   is lowercase. Five bytes in bank 6 (63 free → 58), and the two screens now agree.

Verified in jsbeeb through the whole page: menu → database → the browser on the player's own type
→ sideways through both stat screens (entry, class, height, weight, drive, brain; then armament
and the three sensors) → the description, wrapping and paging with `More...` in the status line →
the closing full stop → fire back to the console main with the selection kept → exit to the game.
The clamp was checked at its boundary by poking the player's own type: with `drType` = 1, up from
002 wraps to 001 rather than reaching 003.

> **The debug console hook leaves a stray sprite.** Entering the console from `ml_debugdeck`
> instead of `DoCharUnder` runs it mid-pass, so the sprite code that follows saves a background
> from the console screen and draws the player over it; a later restore blanks a cell-sized block.
> One console glyph disappeared this way and was chased with a write watchpoint before the cause
> was found. It is an artefact of the hook, not of any page — but it will waste an hour again.

## 6g. Sixteen rows for the whole console — 2026-08-21

The play area **displays** sixteen rows and only fifteen are visible: the sixteenth carries the
smooth scroll's sub-row fraction, and the `R8` blank at fire 3 is all that hides it. With the
scroll flattened — which every screen that takes the buffer over does first — that row is real
buffer and can simply be shown, by moving fire 3 down one character row. `T1_I3X` in `main.asm` is
that interval; the transfer board (Layer 10), the lift's deck select (8b) and the deck plan (6e)
already used it.

13. **[DECISION] Every non-gameplay screen uses all sixteen rows** (KC, 2026-08-21). Only the
    scrolled deck wants fifteen. So the console — its main screen and all three pages — the four
    information screens and the game over's wash now take the sixteenth row too.
14. **[DECISION] The ported pages moved down one row onto the C64's own** (KC, 2026-08-21, over
    "extra row at the bottom, layouts untouched"). The C64's screen area is its rows 9–24; it puts
    the database's name line at row 10 and the content at 12, 14 … 22 — buffer rows 1 and 3, 5 …
    13. At fifteen rows this page had to start at row 0 and every line came out one row high.
    `DB_LINE_ROW0 = 1` in `condb.asm` carries the missing row into `dbLineLo/Hi`, and `DB_IMG_ROW`
    follows it, so the portrait moves with the text. The information screens and the game-over page
    ride on the same table and moved with it.
15. **[DECISION] The console main screen did NOT move.** KC's earlier rule is to plot from the top
    row (§6a) and the top row is still row 0; the recovered row is a fourth spare one at the
    bottom. This is the one place where the port and the original still differ by a row, and
    deliberately.

**Where the switch is set, and where it is put back.** The four instructions used to be copied into
each screen's *exit* — three of them in bank 4, which had three bytes free — and the deck plan's
had to be undone by the console's own the moment the page closed. They are now set on entry
(`XferEnter4`, `LiftViewEnter`, `ConsoleOpen`, `IsStart`, `GoWashStart`) and restored in **one**
place: `ReframeView`, which every path back to the deck goes through — the console's close, the
information screens' `IS_ACT_GAME`, the transfer's exit, the lift's both arms (the same-deck one
directly, the loading one through `LoadDeck`). `ConDeckEnter4`/`ConDeckExit4` are gone entirely.
That freed **47 bytes of bank 4**, which had none.

**Only the high byte of the interval is a variable**, and structurally so: the two intervals differ
by one character row, a row is 8 scanlines and a scanline is `SL = 64` ticks, so the difference is
exactly `&200` and the low byte is shared. `t1i3Lo` is now a constant the rupture reads and nobody
writes; `ASSERT LO(T1_I3) == LO(T1_I3X)` beside `T1_I3X` keeps that true. It halves each of the six
sites, which mattered: the main-RAM code image had **four** bytes left, and writing both bytes in
`ReframeView` took it to zero.

**The clears had to grow with the display.** `ConClear` and `DbClear` cleared `PLAY_VIS_ROWS`
because the last row was never shown; leaving them would have put a strip of the deck along the
bottom of every console screen. Both are `PLAY_ROWS` now. The wash needed no such change — it has
always painted all sixteen (`GoWashRow`, X = 0–15), because the C64's fills its whole screen area.

Verified in jsbeeb by walking to a console on deck 2 (tile 19 at map row 3, col 18): console main,
database browser and stats page, deck plan, then the close — `t1i3Hi` reads `&1F` throughout and
`&1D` again the moment `ReframeView` runs, and the bottom row is clean on every page.

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
| 10 | Console pages are Ship and Droids | mostly reversed 2026-08-17: the menu selection, the **ship side view** and the **deck plan** are built (see 6e). Only the C64's droid database remains |
| 11 | The surround is **black**, where the C64's is grey | new. The original fills all eight status rows with the surround colour and puts the box in the middle 32 scanlines; we draw the box alone and leave the rest CRTC-blanked. Covering it needs all eight rows displayed — 5,120 bytes against a 7-row panel cycle |
| 12 | The box sits at the **top** of the display; the C64's is 8 scanlines down | new, and cosmetic given 11: the same 32 scanlines of box, 8 px higher against black. Matching it exactly means displaying 5 rows with the first blank, which costs 640 bytes and a second `PANEL_ADDR` |

## [DECISION 18] The selection is the icon's colour, not a marker bar

**KC, 2026-08-24:** *"on the c64 the menu option is just indicated by changing the icon colour, not
with a selection marker."* Correct, and the port had invented a bar.

**What the C64 does.** `conWaitInput` (`$2C63`) writes `SpriteColor` `$F1` — VIC colour 1, white —
to the newly selected sprite, and puts `$FF` back on the one it left, reading that value from the
sprite table's own field at `$6B94+9` (colour 15, light grey). `WrSpriteState` (`$09B7`) `STA`s the
byte straight into `$D027,Y`. That is the entire indicator; nothing else marks the selection.

**Black and white, because MODE 1 has no grey.** KC was shown three ways to render the C64's
white-to-light-grey step — a 2×2 dither for a real grey, the deck's own highlight (logical 2), or
black (logical 1) — and took **black**. It is the same *kind* of change as the original's, a
brightness step, taken to its ends.

**It is a transform, not a redraw.** `ConIcons` plots every icon in logical 3, and an icon is
two-colour — ink or nothing — so its shape lives entirely in the **low nibble** of every byte.
Rebuilding the high nibble from the low is lossless in both directions: `high = 0` is black,
`high = low` is white, and one patched `AND` chooses. No second copy of the artwork, which neither
bank 6 nor main RAM had room for.

### Where the eighty bytes came from, and the thing that did not work

`ConIconSel4` is ~80 bytes and **bank 4 had two**. The first build overshot by 38.

`colourMap` is `ALIGN &100` with 162 bytes of padding in front of it, which `CLAUDE.md` names as
the only slack left in bank 4. **Deleting that `ALIGN` recovers nothing** — tried, measured: the
bank still ended at `&BFFE`, because `tiledefs.asm` aligns next and simply pads by the same amount.
The padding is not slack at the end of the bank; it is a hole, and a hole is only worth anything if
you put something in it.

So the routine lives in **`src/consolesel.asm`**, `INCLUDE`d between `chardata.asm` and
`colours.asm` — anywhere before that `ALIGN` will do, because the pad then shrinks by exactly what
was added and the page boundary does not move. It cannot live in `colours.asm` itself: `src/data/`
is generated by `export_bbc.py`.

**Bank 4 went from 2 bytes free to 48** — the routine cost nothing, and deleting `ConMarker4`,
`ConMarkClear` and `conMarkLo`/`conMarkHi` gave back 46.

**The rule this establishes, and the limit on it.** Anything assembled before `colourMap`'s `ALIGN`
is free until the total exceeds 162 bytes. Past that the `ALIGN` rounds to the next page and it
costs 256 at a stroke, so watch the fuel gauge if `consolesel.asm` grows.

### The colour is chosen before the draw, not fixed up after it

The first build recoloured the icons *after* `ConDraw`. KC: *"the icons all appear white before
then becoming black. when returning to the menu the icon should be drawn in the correct colour
once."* Right, and visibly so — `ConIcons` is the **second** thing `ConDraw` does and the recolour
ran after every line of text, so the icons sat white for the whole text draw.

So the ink is now chosen **before a pixel is plotted**. `ConIconInk4` fills `conInkT`, four bytes of
main RAM — `&F0` for the selected icon, `&00` for the rest — and `ConIcons` and `ConDroid` load it
into `csn_mask+1` per icon. It has to be main RAM because `conSel` is bank 4's and bank 6 cannot
read it; the same reason `PN_TABS` and `pmShip` exist.

**`ConSprNib` was restructured to pay for it**, because bank 6 had 16 bytes. Its three stores now
share one `csn_put`, which takes a four-pixel pattern in a **low nibble** and builds the high plane
from it — the same transform `ConIconSel4` uses, so the two agree by construction rather than by
being kept in step. That **deleted `conNib3`** (sixteen `n*&11` entries, now computed) and turned
`conDblHi`/`conDblLo` into low-nibble patterns rather than finished bytes. Net cost to bank 6: 7.
A second set of black tables would have wanted 48 and was never possible.

**The in-place transform is still needed**: a menu step does not redraw anything, so it recolours
the icons where they lie. Only the two paths that arrive after a full redraw are served by the
table alone, and their post-draw call is gone.

**Verified in the buffer, 2026-08-24**, stepping the emulator through the draw itself:

- mid-`ConIcons`, **before a single character of text**: ship 27 bytes of its final 46, deck and
  alert complete — every one black, **zero white bytes**;
- the next dump, still no text: 001 white at its full 76, the others black at 46/160/92. Each icon
  is drawn once, in its final colour, and never changes.
- after a menu step to `conSel` = 1: 001, deck and alert have every non-zero byte at `high = 0` and
  the ship every one at `high = low` — **zero malformed bytes**, counts unchanged, so the transform
  loses and gains nothing.
- the marker column (unit 1) is clear on all four rows.

## [DECISION 19] The panel's mode word is red, like the logo and the score

**KC, 2026-08-24:** *"the text on the left hand side of the top panel should be red, same as the
paradroid logo and the score in the rest of the panel."* Correct — it was `PN_INK_TEXT`.

**The C64 says so directly.** `LevelColors` (`$2844`) fills six rows of colour RAM with `bgColor`,
then overwrites **rows 2 and 3, columns 2 to 37** with `$F2` — low nibble 2, red:

```
2853  LDA #$F2
2855  LDY #35
2857  STA $D852,Y      ; $D800 + 82  = row 2, col 2
285A  STA $D87A,Y      ; $D800 + 122 = row 3, col 2
285D  DEY
285E  BPL _1           ; 36 cells, cols 2-37
```

The status line's fields are the mode word at col 2, the logo at 15–23 and the score at 30–37 —
**all inside cols 2–37, so all three are red on the original.** Ours had the logo and the score
right and the mode word wrong.

**Three routines write that field** and two of them needed changing:

| | who | now |
|---|---|---|
| `PnStr` (bank 6) | Mobile / Weapon / Transfer / Console, and `PnBriefing`'s "Briefing" | `PN_INK_RED` after `PnAt`, which resets the ink — the same two lines the logo and score already had |
| `DbPanelStr` (bank 7) | the droid database's "More" and "Console" | `DbGlyph`'s ink became a variable, `dbInk`: the page keeps `DB_INK` white, the panel field takes `DB_INK_PN` red, and `DbPanelStr` puts it back on the way out |
| `XfGlyphAt` (bank 7) | the transfer game's verdict messages, col 4 | **left alone** — a different screen with its own palette, and not what was asked for |

Cost: 5 bytes of bank 6 (now **4 free** — that bank is tight again) and about 14 of bank 7's 314.

**Verified in the panel buffer, 2026-08-24**, not from a screenshot: the mode word, the logo and the
score all come out **logical 2 and nothing else** — 71, 55 and 8 bytes with the high plane set and
**zero** bytes in any other plane. Checked on "Mobile" and on "Console".

**Not verified**: the droid database's own "More", which is written on its page 3. The change is
the same `dbInk` for both its strings and its "Console" write shares the path, but page 3 was not
reached in the emulator.
