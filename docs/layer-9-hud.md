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
this layer should carry. Leaving the panel up means the status stays visible exactly as it does on
the C64, whose panel rows are also untouched by `GotoHires`.

Entry is `DoCharUnder`'s missing arm: character 66, the console tile, plus fire. **L leaves.**

### 6a. The screen is `ConsoleMain`'s, line for line

**Rebuilt 2026-08-16 at KC's request.** `ConsoleMain` (`$2955`) and `ShowRobotType` (`$3149`) draw
five lines, and the strings carry their own `prntY`/`prntX`:

| C64 | ours | |
|---|---|---|
| row 10, col 2 | row 0 | `Unit type 001 - Influence Device` |
| row 12, col 12 | row 2 | `Access granted.` |
| row 15, col 12 | row 5 | `Ship  : Paradroid` |
| row 18, col 12 | row 8 | `Deck  : Staterooms` |
| row 21, col 12 | row 11 | `Alert : Green` |

The C64's console area starts at screen row 8, so those are deck rows 2, 4, 7, 10 and 13 with rows
0 and 1 empty. **KC: plot from the top row**, so everything moves up two and lands on buffer rows
0, 2, 5, 8 and 11 of our fifteen, three to spare. The 2/3/3/3 spacing is the original's, and is
what leaves a blank row between the lower four. `ConAt` therefore takes a **buffer row** and not a
text line — a line-times-two index cannot express 5, 8, 11.

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
droid-database page stayed gone — it was never the C64's.

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
pieces instead: one rotor phase, 10 rows × 3 bytes, and the ten digit glyphs at 8 rows × 1 byte.
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


## 6e. The menu and the sub-pages — PARTLY BUILT (2026-08-17)

**The selection is built, and one of the three pages.** `conWaitInput`'s port is `ConMenu4` in
droid.asm — BANK 4, not bank 6, which was full; everything the menu touches (the keys, the play
buffer, `conActive`, the page-request flag) is main RAM, so it can be. `conSel` walks 0–3 with
K/M exactly as `consoleState` walks `$80`–`$83` — clamped, not wrapped — and fire dispatches as
`conJump_t` does: entry 0 exits to the game, entry 3 shows the **ship's side view** (below),
entries 1 and 2 are still unbuilt and the press does nothing. The C64 recolours the selected
icon's *sprite*; our icons are logical 1 because 2 and 3 are black on several deck palettes, so
the indicator is a white marker bar beside the selected icon (`ConMarker4`), drawn from bank 4
into the buffer directly. The old `ConsoleRun` ("L leaves, nothing else") is deleted — leaving
is the menu's top entry now — which put bank 6 back to 62 bytes free.

**The ship page is `con_ShipInfo` (`$3062`) faithfully**: the side view drawn once and STATIC —
the current deck lit, no shaft mark — and fire returns to the console main screen with the
selection kept (`con_Back2Main`'s `$C0` redraw, as `ConsoleTick`'s redraw path). It is Layer 8b's
drawer reused whole: `LvShip7` in bank 7 is `LvStart7` minus the shaft mark and the panel text,
with the lift palette swapped in around it (`ConShipEnter4/Exit4`). The console's 15 visible rows
lose nothing — the view's rows 13–15 are blank — so the 16th-row `t1i3` trick is not needed.
`ConsoleTick` (main.asm) is the conductor, since only main RAM can page: bank 4 for the menu,
bank 7 for the page, bank 6 for `ConDraw` on the way back.

**Still missing** — the two pages that need real work:

| icon | routine | what it draws | what it needs |
|---|---|---|---|
| 2, the `?` emblem | `con_DroidInfo` (`$2CC6`) | the **droid database** — one page per type, walked with up/down, `dInfoPage` selecting among five sub-pages through `dInfoPgJump_t` (`$6BE9`) | `PrintDroidInfo` (`$3172`), and the per-type stat tables, which are already in bank 4 and mirrored to `PN_TABS` |
| 3, the circular badge | `con_DeckInfo` (`$3061`) | the **deck plan** — the current deck's map, drawn by `DrawPacked` over the level RLE | a second decoder over `leveldata`, which is already ported; it draws to a different scale from the play area |

**Both need real data or code ported**, which is the honest measure of what is left: the deck
plan needs a second use of the level RLE, the droid database only code and tables already here.
The way in and the way back exist now — follow the ship page's shape in ConsoleTick, and note
neither page's CODE can go in bank 6 (62 bytes free): bank 4 for logic that reads main RAM,
bank 7 for anything that wants the shadow-screen renderer.

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
| 10 | Console pages are Ship and Droids | half-reversed 2026-08-17: the menu selection and the **ship side view** page are built (see 6e), riding Layer 8b's drawer in bank 7. The **deck map** and the C64's droid database remain |
| 11 | The surround is **black**, where the C64's is grey | new. The original fills all eight status rows with the surround colour and puts the box in the middle 32 scanlines; we draw the box alone and leave the rest CRTC-blanked. Covering it needs all eight rows displayed — 5,120 bytes against a 7-row panel cycle |
| 12 | The box sits at the **top** of the display; the C64's is 8 scanlines down | new, and cosmetic given 11: the same 32 scanlines of box, 8 px higher against black. Matching it exactly means displaying 5 rows with the first blank, which costs 640 bytes and a second `PANEL_ADDR` |
