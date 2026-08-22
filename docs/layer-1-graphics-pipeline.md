# Layer 1 — Graphics data pipeline ✅ DONE

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

`tools/export_bbc.py` emits BeebASM sources into `src/data/` (gitignored — converted game
artwork). `tools/verify_bbc.py` round-trips them back and diffs against the listing.
`src/main.asm` renders all 32 tile definitions as an 8×4 sheet.

| Output | Size | Contents |
|---|---|---|
| `charset.asm` | 4096 B | 256 chars × 16 bytes, MODE 1 |
| `tiledefs.asm` | 512 B | 32 tiles × 4×4 char codes, byte-identical |
| `levels.asm` | 3335 B | 16 deck maps RLE + offsets + metadata, byte-identical |

> **Corrected three times, and the third correction is the one that matters.** The first version
> read the charset as 1bpp hires with a nibble split — wrong in its mechanics. The second called
> the whole charset multicolour — also wrong. The third decided both modes were in use, selected
> per cell by bit 3 of the colour nibble, and **that is wrong too**. It stood from Layer 1 until
> 2026-08-18.

## The play area is HIRES

`$D016` bit 4 is the multicolour flag, and the self-modifying `_d016Mode` routine at `$6F1B`
patches its own `LDA` operand. Entering the game goes through `_reenter_game` (`$1532`), which
writes **`$C0`** — bit 4 clear — along with `$D018 = $2F`, the `$7800` tile charset, and jumps to
`EnterGame`. `$D0` is written in exactly two places and neither is gameplay: `$22AD`, after
`ShowXferInfo`, for the transfer board, and `$3092` in `DrawSideview` for the ship cross-section.

So **bit 3 of the colour nibble is part of the colour, not a mode selector.** A cell is eight
1-bit pixels: a set bit takes the cell's colour from colour RAM using the full four-bit value
(0–15), a clear bit takes `$D021`. `$D022`/`$D023` never apply to the deck at all — `DrawSideview`
sets them for its own screen and they simply persist.

**`ref/c64_deck5.png` is the evidence**, and it is unambiguous in three ways at once: the floor is
light grey (slot 0), the crosshairs are **orange** — colour 8, bit 3 set, drawn as a solid
single-pixel pattern — and **`ALERT.` is crisp**. Under the bit-3 theory that cell was multicolour,
the crosshairs would be four fat pixels of the wrong colours, and the lettering would join.
`c64_deck0a.png` and `c64_deck4.png` say the same on their decks.

**What the old model cost.** Every cell whose colour was 8–15 — orange, dark grey, light grey,
light green, light blue, which is most of the ship's structure — was drawn as four doubled pixels
in `$D021`/`$D022`/`$D023`. The ALERT lettering was mangled on eight decks, and that was written
up *as faithful*, twice, on the strength of the theory rather than a screenshot. The lesson is the
project's own rule: the C64 is the specification, and a screenshot of it beats a model of it.

**What it bought back.** `BuildCharset` loses its mode branch and `BuildLUTs` its multicolour half
— 305 bytes of bank 4 — and the conversion is one path instead of two.

**Logical colour assignment.** MODE 1's four colours are global, but the C64 draws on a 12-slot
per-deck palette with a colour per cell. `export_bbc.py` counts how often each colour appears and
fills four slots that now have **fixed roles**:

| logical | role | bits |
|---|---|---|
| 0 | the deck's background (`$D021`, slot 0 of its record) | `%00`, also transparent |
| 1 | its darker foreground | `%01`, the low plane |
| 2 | its lighter foreground | `%10`, the high plane |
| 3 | **white**, and the sprites | `%11`, both planes |

Counted honestly, **every deck wants exactly the background plus three colours.** Deck 5 is light
grey, white, orange, dark grey; deck 0 light grey, white, dark grey, blue; deck 4 light green,
light grey, white, green. The fourth-most-used colour is used 2 to 40 times against the third's
hundreds or thousands, so **nothing is merged** — the old model's worry about decks needing more
than four foregrounds was an artefact of counting `$D022` and `$D023` as if they were on screen.

Black is not a deck colour at all: 2 to 42 pixels a deck. It was a role in the first version of
this scheme only because the multicolour reading made `$D023` look ubiquitous.

Two consequences worth carrying forward:
- **Per-deck recolour is free.** Colour is not baked into the tiles; a deck's scheme is a palette
  change (`VDU 19` / palette register), mirroring how the C64 recoloured via its `CharColor` table.
- **A character is 16 contiguous bytes** — BBC screen memory groups 4 px × 8 scanlines into 8
  consecutive bytes, so an 8×8 char is the left half's 8 scanlines then the right half's.
  Plotting one is a flat 16-byte copy, no shifting or masking. `plot_char` is 12 instructions.

*Known loss:* the C64 gives each cell its own colour from a 12-slot palette; MODE 1's four logical
colours are global. Deck 1 only needs three foregrounds so nothing is lost there, but decks needing
more will have colours merged.

**The charset is built at deck-load time** ✅, since a character's mode *and* colour both depend on
the deck scheme. Shipping 16 converted charsets would have cost 64K.

| shipped | size | |
|---|---|---|
| `chardata.asm` | 1489 B | C64 bitmaps, palette slots, code→index remap |
| `colours.asm` | 432 B | 8 scheme records, deck→scheme, per-deck colour maps |
| generated at runtime | 2192 B | the MODE 1 charset |

Two things keep this small. Only the **137 characters the tiles actually reference** are converted
(of 256, spanning `$00`–`$F0`), via a 256-byte remap table that `plot_char` indexes through — so
the charset is 2192 bytes rather than 4K. And the per-deck C64→logical colour maps are precomputed
offline, so the 6502 needs no search.

`BuildLUTs` builds eight 16-entry nibble→byte tables per deck — four hires, four multicolour.
**Both modes consume one source nibble per output byte** (hires: 4 pixels; multicolour: 2 pixels
each doubled), so the conversion inner loop is identical for both and only the table pointer
differs.

*Bug found by verification:* a few characters carry a palette slot ≥ 12, past the end of a 12-byte
scheme record. The 6502 was indexing into the *next* record while Python clamped to 0, giving 12
differing bytes in character `$16`. The C64 reads out of range here too — `clr0_top_d020` is 12
bytes and it indexes 14 — so the original's behaviour is incidental; both sides now clamp.

**`$D023` is 0 (black), not 6.** The only character-mode writes to `$D022`/`$D023` are in
`DrawSideview` (`$308A`/`$308F`), setting `$F1`/`$F0`; the other writes to that area are `+3`/`+4`/
`+$C`, which are the *sprite* multicolour registers. Having `$D023` wrong corrupted every
multicolour cell on every deck.

**`$D021` is SOLVED, 2026-08-17: it is slot 0 of the deck's colour record, and it differs per
deck.** It was a hard-coded 14 (light blue) taken from a screenshot, which is right for decks 2 and
7 and wrong for the other fourteen — KC spotted that the backgrounds should include oranges and
greys.

The chain, traced through the listing:

| | |
|---|---|
| `InitColors` (`$27E5`) | picks the deck's record via `deckColorScheme[deckNum]` and copies its 12 slots to `clr0_top_d020` with `LDY #11 … DEY / BPL`. The loop ends with **Y = 0**, so the accumulator still holds **slot 0**, and `$2821` stores that in `Irq1bgColor` |
| `Irq_118` (`$6F4C`) | the gameplay raster chain's third stage: writes `Irq1bgColor` to `$D021` and sets `$D018 = $2F`, selecting the **`$7800` tile charset** — i.e. the play area, 128 scanlines of it |

Two near-misses that had confused this before. `SetIntroColors` (`$27A1`) does the same copy but
picks a **random** record (`$D41B AND 3` + 2), because it dresses the intro — hence "slot 3" looking
arbitrary. And `bgColor` really is slot 3, but it belongs to `Irq_91`, the band *above* the play
area; the status box itself is a fixed white (`Irq_254` writes `#$F1`).

Confirmed against `ref/c64_deck0.png`, a screenshot of the real game: deck 0 uses scheme 0, whose
slot 0 is light grey — and the floor in that screenshot is light grey, not light blue. The per-deck
values were emitted as **`.deckBg`** and `BuildCharset` indexed `colourMap` with them. **Both are
gone since 2026-08-22**: that lookup could only ever return logical 0, because the background is
logical 0 by construction, and `export_bbc.py` now asserts it rather than looking it up at run
time. See [`layer-14-visual.md`](layer-14-visual.md) DECISION 1. The values themselves are still
derivable — slot 0 of `schemes[deckScheme[d] * 12]`.

Only decks **2 and 7** are light blue. The rest: light grey (0, 5, 9), light red (1, 8, 10, 15),
yellow (3, 6, 12), light green (4, 11), cyan (13, 14).

**Multicolour ALERT lettering is faithful, not a bug.** Row 0 of tile 22 (`$63`–`$66`) is the
lettering and sits on slot 7, which is multicolour under 8 of the 16 deck schemes — 4 pixels wide,
so the single-pixel letter gaps cannot exist and the letters join. The C64 does exactly the same;
`tools/compare_tile.py` renders a tile side by side, C64 against port, to settle such questions.
Decided to stay faithful for now rather than force those characters to hires.

**Physical colours must be assigned per deck, greedily.** A fixed C64→BBC table cannot work:
several C64 colours share a nearest BBC match, so two logical colours collapse onto one physical
and whatever is drawn in the second becomes invisible. Light blue (the floor) and blue (shadow
detail) both mapped to BBC blue, which silently erased detail on **12 of the 16 decks** — including
the ALERT panel's frame, which is what made the lettering look wrong. `assign_palette` now picks
nearest-*unused* per deck, with preferences honoured while free (floor → blue, grid → magenta,
shadow → black).

This is the second time a bug hid in the stage *after* conversion. The conversion was correct in
both cases; the damage happened in colour assignment.

### The four slots have fixed ROLES, 2026-08-17

They used to be filled by frequency — background, then the three most-used colours in whatever
order their counts fell — which put black at logical 2 on eight decks and at logical 3 on the other
eight. Same four colours either way, in an order that meant nothing. KC's ordering:

| logical | role | bits | why |
|---|---|---|---|
| 0 | the deck's background | `%00` | also the transparent value |
| 1 | black (`$D023`) | `%01` | the low colour plane alone |
| 2 | the deck's highlight | `%10` | the high plane alone |
| 3 | white (`$D022`) | `%11` | **both planes** |

**The reason is the sprites.** Artwork exported at logical 3 has both bits set on every opaque pixel
and neither on a transparent one, so a sprite byte **is its own transparency mask**, and `AND &0F` /
`AND &F0` recolour it in place to logical 1 (black) or logical 2 (the highlight) from one set of
bytes. At logical 1 none of that is possible, which is why the port carries a 256-byte `SPR_MASKTAB`
to expand the mask — now derivable from the data itself, and removable whenever the blitter is
next opened. `DROID_COLOUR` and `EFFECT_COLOUR` are both 3.

The panel had been using the same trick all along: its glyphs are stored at `&FF` and `pnMask`
picks a plane, which is how it gets red text out of white artwork.

Giving up the frequency order cost nothing. On all 16 decks the three most-used non-background
colours are exactly {white, black, highlight}, so this reorders slots without changing which
colours a deck gets.

**Slot order and ALLOCATION order are different things**, and conflating them is what made the
C64's black come out green. `assign_palette` is greedy nearest-unused, so whoever picks first wins
a contested colour; picking in slot order let `PREFERRED`'s red→black take BBC black before the
C64's actual black asked for it. `SLOT_PRIORITY = (3, 1, 0, 2)` — the sprite colour, then black,
then the floor, then the highlight, which is the one already living with a compromise. Result:
white on 16/16 and black on 16/16, where black was previously green on decks 1, 8, 10, 15 and red
on 2 and 7.

The cost lands on the pale floors: light grey and light green no longer take BBC white and fall to
yellow. That is a judgement for the lab, not for a rule — and it is the first thing to look at.

**Anything drawing on the deck's palette must follow the roles.** The console does, and it broke
when this landed: it drew in logical 1 *because* that used to be white. Its ink, its two icon
expansions and the deck plan's player cell all moved to logical 3. `liftview` and the transfer game
install their own palettes and are unaffected.

**Both assignments are now editable by eye — `tools/palette_lab.py`.** The greedy rule above is a
starting point, and Layer 14 is where the answer is actually chosen. The lab renders every deck in
C64 colours beside the MODE 1 version and lets both stages be changed live: the **palette**
(logical 0-3 → BBC physical, i.e. `deckPalette`) and the **merge** (each C64 colour → a logical
slot, i.e. `colourMap`) — the second being where a deck wanting five colours loses one, which no
palette can undo. Saving writes `tools/deck_palettes.json`; `export_bbc.py` reads it as an override
and says so, and rejects a malformed one outright rather than quietly falling back.

**Verified:**
- `verify_bbc.py --charset <dump> <deck>` diffs the charset the BBC built against a Python
  conversion computed by a different route (direct, versus the 6502's lookup tables). Decks 1 and 2
  both match all 2192 bytes.
- `verify_bbc.py` asserts all 16 decks have four distinct physical colours, so the collision above
  cannot silently return.
- `tools/analyse_alert.py` checks per deck that the ALERT lettering stays hires and distinct from
  the background.

*Option not taken:* tiles could be stored in C64 form (2K instead of 4K) and expanded during the
blit. Worth revisiting only if the tile charset ever needs to compete for space with sprite data.

**Verified:** `verify_bbc.py` passes 5/5 — the charset round-trips to the original `$7800` bytes
*and* asserts every pixel pair is correctly doubled; tile defs, RLE, deck offsets and metadata all
byte-identical. `tools/rip_tiles_mc.py` renders the tile set as multicolour for direct comparison
against `ref/start screen.png`.
