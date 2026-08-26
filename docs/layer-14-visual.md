# Layer 14 — The visual pass

**Status: started 2026-08-22 — the floor dither is in (DECISION 1 below); the palettes are still
KC's to settle.** `PLAN.md` carries the summary.


Asked for by KC, 2026-08-16. Everything is drawn by now and has been seen on real hardware; this is
the pass that settles how it **looks**, as one deliberate sitting. Two strands:

1. **The final palettes, for every deck and every game screen.** MODE 1 gives four colours against
   the C64's sixteen, so a deck's palette here is a choice, not a transcription. This pass sets all
   sixteen decks together, plus the panel, the console, the transfer board and the title, so they
   read as one game. The original's own per-deck colours are the starting point, not the answer.
   **Include the deck plan page (KC, 2026-08-17)**: re-judge `planInk` (built by `export_bbc.py`
   with two legibility overrides) and layer-9 §6e decision 1 alongside the deck palettes.

   **The four logical colours now carry fixed roles** (KC, 2026-08-17): 0 = the deck's background,
   1 = black, 2 = the deck's highlight, 3 = white. Chosen for the sprites — logical 3 is `%11`, so
   a sprite byte is its own mask and `AND &0F` / `AND &F0` recolour it to black or the highlight
   in place. Allocation runs in priority order 3, 1, 0, 2, which puts white on all 16 decks and
   black on all 16. Anything drawing on the deck's palette must follow the roles; the console
   already had to be moved. See [`docs/layer-1-graphics-pipeline.md`](docs/layer-1-graphics-pipeline.md).

   **The tool for it is `tools/palette_lab.py`** (2026-08-17): every deck rendered in the C64's own
   colours beside the port's MODE 1 render, with both the palette and the colour *merge* editable
   live, and a 320 × 120 window showing what actually fits on screen. It writes
   `tools/deck_palettes.json`, which `export_bbc.py` reads as an override when it regenerates
   `colours.asm` — so a decision made by eye lands in the build without hand-editing generated
   data. Verified: its BBC render is byte-identical to `convert_charset` (what `BuildCharset`
   reproduces) over all 2,192 characters of all 16 decks.
2. **Redrawing graphics characters that fight the palette.** Where a tile or glyph only works
   because of a colour MODE 1 cannot give it, the honest fix is to change the artwork — a
   **deviation from the original's graphics, agreed case by case** under the usual rule.

**Why last:** judging a palette wants the finished screens and a real display — 13c is what puts
the build in front of one. **Exit condition:** every deck and screen has a palette recorded in the
source with a comment saying why, and every redrawn character has a decision entry.

---

## [DECISION 1] The floor dither — logical 0 at half intensity

**KC, 2026-08-22.** The BBC's palette is fully saturated where the C64's is not, so a deck whose
floor is red, magenta, green or cyan reads far harsher here than the original ever did. **Half the
floor's pixels take logical 1 instead, in a 2×2 checker**, and the floor comes out at half
intensity. This is strand 2 of this layer: a deliberate deviation from the original's graphics,
which has a solid floor.

Previews were rendered from `tools/palette_lab.py`'s own chain before the decision — solid against
checker, vertical stripes and horizontal scanlines, on decks 1, 3, 4 and 13. The **checker** was
chosen. Horizontal stripes were rejected because the pattern is baked into the charset and the
vertical scroll is one scanline, so they would invert on every line of scroll and strobe; vertical
stripes are the most stable but read as a grille rather than as texture.

### Why it costs almost nothing

`build_logical_map` puts the deck's background on **logical 0** by construction, and logical 0 is
`%00` — so every background pixel in the charset is already a pair of clear plane bits, and the
floor colour is purely `deckPalette[deck * 4]`. Shading a floor pixel therefore means setting the
**low** colour plane on it: logical 0 → logical 1, which is physical black on the decks this runs
on. No palette change, no fifth colour, nothing the hardware cannot do.

`DitherChar` (`src/level.asm`) does it over the 16 bytes of each character, called from
`BuildCharset`'s own loop — which already walks the charset a character at a time, so there is no
second pass. Which pixels are logical 0 is exactly the question `SPR_MASKTAB` already answers:
`SprBuildMask` fills it with the sprite transparency mask, "this pixel has no colour", duplicated
into both nibbles. The dither mask is low nibble only, so a pixel with any colour in it is left
alone — which matters, because setting the low plane on a **logical 2** pixel would turn a
highlight white.

The parity is free: a character is 16 bytes, the left half's 8 scanlines then the right half's, so
bit 0 of the byte index **is** the scanline parity in both halves. 16, 8 and 8 are all even, so the
phase carries across characters, across cells and across the whole map with no seams.

Roughly 5 ms across a deck load. **Nothing in the main loop pays anything.**

### Three things that fell out of it

1. **It dithers logical 0 wherever it lands, ink as well as floor.** A cell whose C64 colour merged
   onto logical 0 is invisible against the floor today; dithering only the floor would have made it
   appear as a solid patch. This keeps it invisible.
2. **`BuildLampChar` calls `DitherChar` too.** It rebuilds character `$16` during play from the
   LUTs, and would otherwise leave that one cell solid against a dithered floor. Reaching bank 4
   from `lowcode.asm` is legal there for the reason its header gives — `SWRAM_DATA` is the resting
   state and `AnimTick` is in the main loop.
3. **Contrast cost, accepted.** Logical 1 is also the wall and detail ink on most decks, so
   black-on-floor detail loses half its contrast. Visible in the previews; judged to read.

### The enable rule, and the three decks it exists for

Decks 0, 5 and 9 had a logical 0 that was **already black** and a logical 1 that was a colour, so
dithering them would have painted colour *onto* black — louder, not quieter. `BuildCharset` sets
`dcMask` to zero unless `deckPalette[deck * 4 + 1]` is physical black, which makes `DitherChar` a
no-op with no second code path in either caller. One test is enough: the four physicals are
distinct (`verify_bbc.py` asserts it), so logical 1 being black means logical 0 is not.

**KC re-picked all three, and all sixteen decks now dither** — logical 1 is black on every one of
them, which finally makes `lowcode.asm`'s long-standing `LAMP_OFF = 1` comment ("logical 1 is black
on every deck") true. The rule stays regardless: a deck that wants a solid floor keeps one.

### [DECISION 2] The dither is a fifth tone, and decks 0 and 9 spend it

**KC, 2026-08-22, after seeing it in game.** Decks 0 and 9 are scheme 0, whose C64 floor is **light
grey** — a colour MODE 1 does not have, and the thing this port has never been able to reproduce.
Their palette is now `[7, 0, 4, 7]`: **logical 0 is WHITE**, dithered to grey, and logical 3 is
white as well.

That is a deliberate collision, and it works because a dithered logical 0 is displayed as a **50%
blend with black** — a tone no solid palette entry can be. So the dither does not merely soften the
floor; it *adds* a fifth tone to a four-colour mode, and on these two decks that fifth tone is
exactly the colour the original wanted. The sprites stay legible because they are solid white
against a 50% white floor.

**The consequence for the checks:** "four distinct physical colours" is no longer the right rule,
and both places that enforced it now test **four distinct TONES** instead — a collision is legal
only when it involves logical 0 on a dithered deck. `verify_bbc.py` says which decks share and why;
`palette_lab.py` says the same in the palette panel. A collision that does not involve logical 0,
or any collision on a deck with a solid floor, is still a real failure and still loses detail for
good.

The 6502 is unaffected: `DitherChar`'s enable test reads logical 1 alone. If logical 0 were black
as well the dither would blend black with black and simply not show, so the only case the test has
to catch is the harmful one — a coloured logical 1.

### The invariant it depends on, now enforced

`export_bbc.py` **refuses to write `colours.asm`** if any deck's background does not land on
logical 0. It was true by construction, but `colourMap` is hand-editable in the lab, so the
invariant could be edited away — and both `BuildLUTs` and `DitherChar` would then be wrong in ways
that look like artwork bugs. `palette_lab.py` warns about it in the merge panel as well, so it is
caught before the build.

### What it paid for itself with

Stating that invariant made two things dead, and removing them more than covered the dither:

- `BuildLUTs`' background masks. `bcBg`, `bcGH` and `bcGL` computed a background contribution that
  could only ever be zero, and the inner loop `ORA`'d that zero in twice per entry.
- `.deckBg`, 16 bytes of `colours.asm`. Its only reader was the lookup above. Nothing is lost — it
  is slot 0 of `schemes[deckScheme[d] * 12]`, both still shipped.

Plus two genuinely dead variables in the same block (`bcA`, `bcB`, `bcPal`, `bcColour`), and
`lampInk` moved to bank 4 beside `lampSrc` to buy the low overlay back the two bytes
`BuildLampChar`'s `JMP DitherChar` cost it.

**Net: bank 4 went from 4 bytes free to 26, and the low overlay from 2 to 4.** Main RAM is
unchanged at `&2FFE`.

### Verified

Built and run in jsbeeb. The charset at `&0400` shows the checker (`05 0A 05 0A …` for the blank
character, and `&38`-style bytes with their logical-2 pixels untouched); the play buffer at `&6800`
shows it on screen; deck 5, which is not dithered, has an all-zero blank character and a solid
black floor. Walked diagonally to force both scroll axes and pressed SPACE for the `RedrawAll`
oracle at a mid-scroll position — the buffer is **byte-identical** across the two draw paths.

---

## [DECISION 4] A solid text-screen background, per deck — and DECISION 3 reverted

**KC, 2026-08-23, having looked at it in game.** The dither is right on the deck and wrong behind
text: it costs readability and the screens come out messy. **DECISION 3 is reverted in full** —
`DitherCell`, `DitherBuf`, the portrait's dithered clear and `IsBlank`'s guard are all gone, and
`dcMask` went back to bank 4. The deck itself keeps the dither (DECISIONS 1 and 2).

The real problem it was trying to solve stands, though, and is worse than the dither: **several
deck floors are far too bright to read white text on** — yellow, cyan, and the white of decks 0, 5
and 9. So the static text screens get **a solid background colour of their own, chosen per deck**.

### The mechanism, which touches no drawing code at all

Those screens already draw their background as **logical 0**. So nothing about the drawing changes:
only what logical 0 *looks like* while they are up.

`export_bbc.py` emits **`.deckTextPal`** — the deck's four physicals with logical 0 replaced —
immediately after `.deckPalette`. The two tables are therefore **64 bytes apart**, so `SetTextPal`
is `SetPalette` with `palBase` 64 higher: no second table lookup, no test in the loop, and the
restore is the existing `SetPalette`. `main.asm` asserts the adjacency.

**The 64 bytes cost nothing.** `colourMap` is `ALIGN &100` and there were 226 bytes of padding in
front of it; the new table rides in that. Worth remembering — the fuel gauge does not count it, and
it is the only slack left in bank 4.

Where it is applied and taken away:

- **In**: `ConMenuInit4` for the console (which covers the deck plan and the database, both opened
  inside it), and `InfoCall` for the information screens.
- **Out**: `RedrawAll`. Every way back to the deck ends in a full redraw — `ReframeView` jumps
  straight to it — so putting the restore at the top of the redraw cannot be forgotten by a new
  exit path, and costs one `JSR`.
- **`LoadDeck` no longer calls `SetPalette`.** It used to, at the top, and that was what fought
  this: the 001 screen is up *across* that `LoadDeck` (it holds the redraw back), so the deck's
  colours overrode the text background every time. `ReframeView` returns early while a screen is
  up, so the deck's palette now lands exactly when the deck does.

**Total: 19 bytes of bank 4 and 3 of the low overlay**, leaving 10 and 1.

### Two things that bit, both worth keeping in mind

1. **`IsEntry` takes its screen selector in X**, and `SetPalette` ends its loop with `X = $FF`,
   which is `IS_BLANK`. Calling `SetTextPal` *before* `JSR IsEntry` therefore turned every
   information screen into the blank one — a screen that cleared and drew nothing. The call goes
   **after**, where X is spent. `IsEntry`'s own header warns about exactly this register.
2. **The MCP screenshot is the last PAINTED frame.** Twice it showed a blank or stale screen while
   memory said the page was drawn correctly, and twice that nearly sent me after a bug that was not
   there. Read the buffer; screenshot only to judge how it looks.

### Choosing them

`palette_lab.py` has a fifth picker, **T**, beside the four logical colours, and a **text screen**
checkbox in the header that shows the deck through that palette. Colours already used by logicals
1–3 are disabled: the portrait and the deck plan draw in those, and anything drawn in the
background colour vanishes into it. `export_bbc.py` refuses a collision outright.

The starting value is automatic — the darkest BBC colour the deck is not already using — which
lands on blue for most decks and red for the few whose logical 2 is blue. **That is a starting
point, not the answer**; it is a judgement by eye, like the palettes themselves.

Verified in jsbeeb: the 001 screen on a cyan/white deck comes up with a solid red field, white
text and a blue portrait, and the deck's own colours return when it is dismissed.

### DECISION 4a — the deck plan keeps the DECK's colours

**KC, 2026-08-24.** The console's deck plan is a picture of the deck, not a page of text, so it
wears the deck's own palette. Only the menu, the droid database and the information screens take
the text background.

The switch rides on **`ConMarker4`**: every path that puts the console MENU on screen ends by
drawing the selection marker — `ConsoleEnter`, the return from a page (`ct_back`), and `ConMenu4`'s
own up/down steps — and **none of the pages does**, so it is the one place that means "the menu is
up" without a flag. `SetTextPal` moved there out of `ConMenuInit4`, which cost bank 4 nothing.
`ct_trydeck` ends `JMP SetPalette` instead of `RTS`, which puts the deck's colours on for the plan
and returns through it.

The ship page is unaffected: `ConShipEnter4` saves `palPlay` and installs `palLift`, and
`ConShipExit4` puts back whatever it found — the text palette or the deck's, either is correct.

**MAIN RAM WAS EXACTLY FULL at this point** — the code image ended at `&3000`, on the `GUARD`,
with 0 bytes free. (Superseded: the RAM recovery pass of 2026-08-25 took the image to 639 B free,
[`ram-pass.md`](ram-pass.md) — the hunt this paragraph proposed is moot.)

### DECISION 4b — the palette changes BEFORE the screen it belongs to

**KC, 2026-08-24.** All four switches were set *after* their draw, so each screen was painted in
the outgoing palette and only corrected once it was finished — a visible wrong-coloured pass on
every transition. They now run **immediately before** the draw, which meant moving each one to the
routine that *decides* the transition rather than the one that completes it:

| Transition | Was | Now |
|---|---|---|
| open the console | `ConMarker4`, after `ConsoleOpen` drew | `ConMenuInit4`, which `ConsoleEnter` now calls **first** |
| menu → deck plan | `ct_trydeck`, after `ConDeck7` drew | `ConMenu4`'s `cm4_deck` arm, on the press |
| page → menu | `ConMarker4`, after `ConDraw` drew | `ConPageKeys4`'s leave arm, on the press |
| any information screen | `InfoCall`, after `IsEntry` drew | `InfoCall`, before it pages bank 7 |
| back to the deck | `RedrawAll` — already before its own draw | unchanged |

Each is a **tail call** (`RTS` → `JMP SetTextPal` / `JMP SetPalette`) on an arm that already ended
in `RTS`, so three of the four cost two bytes rather than three, and `ConMarker4` gave three back.

**`ConsoleEnter` now calls `ConMenuInit4` before the bank-6 block.** That is a reorder of game
code, and it is safe because `ConMenuInit4` only writes flags — `conSel` and the key edges — and
nothing in `ConsoleOpen` reads them; the marker is drawn separately, afterwards, as it always was.

**`SetPalette` and `SetTextPal` now preserve X.** `InfoCall` calls one before it pages bank 7, and
`IsEntry` takes its screen selector in X. `SetPalPlay`'s own loop clobbers X as well, so the save
has to outlive it — which is why the routine ends in `JSR SetPalPlay` and an `RTS` rather than the
`JMP` it used to. Costs five bytes and removes the trap that had already caught this once.

**Both tight regions were at 2 bytes free at the time**: main RAM ended at `&2FFE`, bank 4 at
`&BFFE`. (DECISION 5 below gave main RAM four back. All since superseded by the RAM recovery
pass — 639 B and 51 B, [`ram-pass.md`](ram-pass.md).)

## [DECISION 5] The logo screen is embossed, and the front end picks a deck at boot

**Found 2026-08-24, KC:** the C64 logo screen is embossed and the port's was one flat colour.

**What the C64 does.** The screen is hires (`Irq1` `$2922` writes `$D016 = $C8`, bit 4 clear), so a
cell is the shared background plus one foreground colour — and `ShowTitle` `$2879` makes a *second*
pass over the same 1,000 codes, writing `$D800` from `CharColor` `$0800`. **Colour is a property of
the character code, not of the cell.** `CharColor`'s high nibble is a fixed SLOT; `NewCharColors`
`$3577` patches the low nibble per deck from the current colour scheme. Slot is artwork, physical
is palette — the same split this port already has.

Matching all 1,000 cells of `Title_dat` against `ref/c64-logo-screen.png` on a fitted grid, the
whole screen is five slots and no more:

| slot | cells | measured ink | what it is | port |
|---|---|---|---|---|
| 0 | 484 | (162,142,229) | code `$00`, blank — background shows through | logical 0 |
| 9 | 247 | (241,238,251) | white highlight strokes, top-left of every box | logical 3 |
| 7 | 249 | (100, 79,180) | dark violet shadow strokes, bottom-right | logical 1 |
| 4 | 17 | ( 23, 15, 61) | the BY ANDREW / BRAYBROOK lettering | logical 1 |
| E | 3 | green | the three blobs | logical 2 |

**The highlight and its shadow are about three character cells apart and never share one**, so none
of it needs per-pixel colour. `tools/export_title.py` bakes the slot's logical colour into each of
the 36 glyphs — `SLOT_LOGICAL` — and that is the whole change: **the file is still 1,140 bytes**,
`TiCell` is untouched, the RLE stream is untouched. It replaces layer-11 [DECISION 9], the
white-on-black placeholder that deferred this here.

**The four fixed slot roles ARE the four tones the logo wants** (0 the deck background, 1 black,
2 the deck highlight, 3 white), so the only substitution is slot E's green taking the deck
highlight — three decorative cells. The one place the port is not the C64 is the shadow: the C64's
is a dark tint *of* its background and ours is black.

### The random boot deck

KC, same day: **the front end inherits the last deck's palette, and at a cold boot it picks one at
random.** Before this the boot title ran on the OS's MODE 1 default, where logical 0 is black and
logical 1 is red — which *inverts* a fresh emboss, because the shadow strokes come out brighter
than the background they sit under. Verified in jsbeeb, and it looked exactly as bad as that
sounds. Any deck palette has the relationship the artwork wants.

`TiBootPal` (`src/title.asm`, and so in `PARTITL`) does it, and it takes the **text** palette
rather than the play one — that is what the game-over path arrives on, since `InfoCall` runs
`SetTextPal` before every front-end screen (DECISION 4 above), so boot and the loop back now agree.
It also dodges decks 0, 5 and 9, whose logical 0 *is* white and would swallow the white
highlights; their text background is not.

**It absorbed the boot seed.** `main.asm`'s `LDA USR_VIA_T1CL / BEQ / STA drSeed` moved into it —
the deck and the LFSR seed are the same sample of the same free-running counter, so they belong in
one place. Same caveat as before: deterministic under an emulator, varying on real hardware where
the disc loads above take a different time. Real entropy still arrives with `TiWait`'s dwell.

**`bootPal` is why it is boot-only.** An assembled `1` in main RAM that `TiBootPal` clears, so the
game-over path falls straight through and keeps what it inherited. It cannot live in `PARTITL`:
that overlay is reloaded from disc on every title and would bring the flag back set.

**And it must page bank 4 itself.** Boot's last act before `TitleSeq` is `UnpackBankIn` on
`SWRAM_XFER`, so `SWRAM_DATA` is *not* the resting state on arrival, and both `SetTextPal` and
`drSeed` are bank 4's. Leaving it paged is safe — `HsEntry` is next and pages `SWRAM_XFER` for
itself in its first instruction.

**Net −4 bytes of main RAM** (the 8-byte seed block out, a `JSR` and the flag in): the code image
ends at `&2FFA`, **6 bytes free**. `PARTITL` spent 32 of its 89 and has 58. Bank 4 unchanged.

**Verified in jsbeeb 2026-08-24:** cold boot lands on deck 11's text palette (`bootPal` reads 0,
`deck` reads 11, palette `[4,0,5,7]`) and the logo shows blue ground, white highlights top-left,
black shadows bottom-right, dark panel lettering, magenta blobs — the same relationships as
`ref/c64-logo-screen.png`.

## [DECISION 6] A cleared deck's floor turns blue

**KC, 2026-08-24:** the deck background goes blue once nothing but the player is left on it.

**What the C64 does, and it is more than a colour.** `RunDroids` (`$174B`) ends its compaction with
`STY numDeckDroids`, and if the count has reached **1** — the player alone — it runs a whole
deck-cleared event:

```
17D5  STY numDeckDroids
17D7  CPY #1 / BEQ _6 / RTS
_6:
17DC  JSR InitColors           ; the colour
17DF  LDA #250 / JSR AddScore
17E4  LDA #250 / JSR AddScore  ; five hundred points
17E9  LDA #$17 / STA sndFx1    ; a sound effect
17ED  LDA shipNumDroids / BNE _7
17F1  INC notInDeck            ; the whole SHIP is clear
_7:   RTS
```

**It fires exactly once**, because `RunDroids` early-outs while the count is below 2 and so never
reaches this code again. The port's `DroidsUpdate` already mirrors that guard, so the hook needs no
shadow byte.

**The colour is `InitColors` (`$27E5`) forcing colour scheme 7**, not a background poke:

```
27F1  LDA numDeckDroids
27F3  CMP #1
27F5  BNE _1
27F7  LDA #7          ; the scheme, instead of deckColorScheme[deckNum]
```

and `ColorSets` entry 7 at `$6A98` carries the listing's own label — **`; 7 - deck cleared`**. So
the C64 swaps all twelve colour slots, and its floor (slot 0) becomes C64 colour **`$B`, dark
grey**. Every other scheme's slot 0 is light grey, light blue, yellow, light green, light red or
cyan.

**MODE 1 has no grey, so blue is KC's substitution** — and only logical 0 changes, not the deck's
other three. Verified in `palPlay`: all four logical-0 ULA entries become physical 4 while logical
1 stays black, 2 red and 3 white.

### The state is a flag, not `drCount` — and why

**KC, on the first build:** *"the deck background stays blue when I move to a new deck in the lift
that still has droids on it."*

`LoadDeck` runs `ReframeView` — which ends in `RedrawAll`, which calls `SetPalette` — **before**
`DroidsInit`. Arriving from a cleared deck, the palette was therefore built while `drCount` was
still 1, and nothing rebuilt it afterwards. The C64 reads `numDeckDroids` directly and gets away
with it because its `InitColors` is called *from* `RunDroids`, after the count is right.

So the port keeps an explicit **`deckClear`** byte: the compaction sets it, and **the top of
`LoadDeck` clears it** — first, before anything draws. Putting the reset in `DroidsInit` was tried
and is wrong by exactly one routine: the flag was correct (`drCount` 10, `deckClear` 0) and the
floor was still blue, because the palette had already been built. The ordering is now impossible to
get wrong from either end.

**`drCount == 1` is what sets it, and that is the original's** — the port's own comment on `drCount`
already read *"1 means the deck is clear"*, which is `numDeckDroids == 1` exactly.

**It lives in `SetPalette`** (`level.asm`), not in a one-off poke, so every path that re-applies the
palette keeps it: the deck redraw, the console exit, a lift arrival. **The text palette is exempt** —
`palBase` is `deck*4` there, or that plus 64 for `deckTextPal`, and `deck*4` cannot reach 64, so
`>= 64` cleanly identifies the text screens, whose logical 0 is DECISION 4's legibility choice and
not the floor at all.

### Still missing, and worth a decision

The port does **none** of the rest of the C64's event: the **500 points**, the **`$17` sound**, and
the `notInDeck` arm for a wholly cleared ship. Only the colour was asked for. The score in
particular is a real gameplay difference — clearing a deck pays nothing in the port.

### DEBUG_KILL

`C` kills every droid on the deck, so the floor can be reached without shooting one empty.
`src/dbgkill.asm`, bank 4, called from the top of `DroidsUpdate` — **from bank 4, so it costs the
bank three bytes rather than main RAM's last three.**

It drives the **real** kill path, one droid at a time through `DrKillDroid`, rather than zeroing
`drEnergy` behind its back: the explosion, the sound, the alert rise, the score by class and
`DrRemoveShip` all happen exactly as they do when you shoot the thing, and the compaction reaps the
explosions a few passes later. What it tests is the mechanism, not a shortcut past it.

**It rides the same padding as `consolesel.asm`** and for the same reason — bank 4 overshot by 24
with it in `droid.asm`. That is now two files in `colourMap`'s 162 bytes; watch the fuel gauge.

**A trap worth recording**: the first `INCLUDE` landed in the **bank 5** block by accident. It
assembled cleanly and the asserts passed — beebasm resolves the label either way and nothing checks
banks — so a `JSR` from bank 4 would have jumped into whatever bank 4 held at that address. Caught
by reading the build's include order, not by the build.

**Verified in jsbeeb, 2026-08-24**, all three cases:

1. press C — the droids explode, the score rises 0 → 612 through the ordinary scoring, `drCount`
   reads 1 and the floor is blue with the walls still red and white;
2. hop to a deck that still has droids — **it shows its own colours**, `drCount` 10 and
   `deckClear` 0. This is the case that was broken;
3. hop back to the cleared deck — blue again, `drCount` 1 and `deckClear` 1. The kills persisted on
   the ship roster, `DroidsInit` placed nothing, and the compaction fired the hook.

### [DECISION 10] The lift tile on decks 0, 5 and 9 — the price of [DECISION 2], paid down

**KC, 2026-08-26: "decks 0, 5 and 9 have no details in the lift tile — it's just empty."** Exactly
the three decks whose logical 0 and logical 3 are both physical 7, which is [DECISION 2]'s
deliberate collision. It was not a coincidence, and it was not the collision either.

**The lift is TILE 3.** Not tiles 23-27, which `docs/graphics.md`'s tile table calls "lift shaft"
elements — deck 0's map does not contain a single one of them. The lift is placed from
`liftTileCol`/`liftTileRow` (`src/data/levels.asm`), and the tile at that position is tile 3 on
deck 0 and on deck 1 alike. Half an hour went into the wrong tiles because the table's naming was
taken at face value; the map is the authority, at `tilemap + row * MAP_COLS + col`.

**Tile 3 has three colour groups, and on these decks two of them are white:**

| cells | role | decks 0 / 9 | deck 5 | deck 1 (for contrast) |
|---|---|---|---|---|
| 6 | structure | dk grey → blue | dk grey → black | red → black |
| 6 | highlight | white → **white** | white → **white** | white → white |
| 4 | detail | grey → **white** | yellow → **white** | purple → black |

10 of 16 cells land on the floor's own physical colour; on every other deck the count is **zero**.
The 6 highlight cells are [DECISION 2] working as intended — solid white on a 50% floor, and KC
confirms they read correctly. **The 4 detail cells are the defect**: C64 grey (decks 0/9) and C64
yellow (deck 5) merge onto **logical 0, which IS the floor**, so those cells are not low-contrast,
they are literally the floor colour.

**Fix — three bytes of `deck_palettes.json`:**

- decks 0, 9: C64 grey → logical 1 (black); the structure is already blue, so black separates from both
- deck 5: C64 yellow → logical 2 (red); the structure is already black there

**Blast radius measured before applying: 4 cells, all in tile 3, on those three decks only.**
Nothing else in the 32-tile set uses those colours on those schemes, and the floor is C64 light
grey (15), which is untouched. White is untouched too.

**A rejected fix worth recording, because it looked obvious and was wrong twice over.** The first
attempt re-pointed C64 **white** off logical 3 on those decks. It repainted **200 cells** — every
piece of white linework on the deck, since white is the main linework colour there — and it fixed
only 6 of the 10 dead cells, because the other 4 come through grey/yellow and never touched white
at all. KC: *"the white highlights were correct before, now they are red on deck 5 and the lift
details are still not visible."* Both halves of that are the lesson: **measure which colours the
failing cells actually use before moving any of them**, and the count of cells a `colourMap` edit
moves is not the count of cells it fixes.

**[DECISION 2]'s premise stands but is narrower than it read.** "The sprites stay legible because
they are solid white against a 50% white floor" is true of a solid sprite and of these highlights.
It says nothing about a colour that merges onto logical 0 itself — that one is not dithered
*against* the floor, it *is* the floor. `verify_bbc.py`'s "four distinct tones" check passes all
three decks and always will; it tests the palette, not what the artwork does with it.

**Still open:** deck 5 is scheme 6, not scheme 0, so [DECISION 2] — which is written about scheme
0's light-grey floor — never mentions it, yet it carries the same collision. Either intended and
undocumented, or it slipped in. Worth deciding.
