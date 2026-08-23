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
