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

> **Corrected twice.** First version: treated the charset as 1bpp hires, converted with a nibble
> split — wrong, `ref/start screen.png` shows four colours per cell. Second version: called the
> whole charset multicolour — also wrong, because ALERT keeps single-pixel letter spacing, which
> a 4-pixel-wide multicolour character cannot produce. The truth is that both modes are in use.

**The C64 mixes hires and multicolour cells on the same screen.** `$D016` bit 4 enables
multicolour text mode globally (the `_d016Mode` routine at `$6F1B` is self-modifying, patching its
own `LDA` operand between `$D0` and `$C0`), but in that mode the choice is made **per cell** by
bit 3 of the colour RAM nibble:

| colour RAM | cell renders as |
|---|---|
| `0`–`7` | hires — 8 pixels, background + that colour |
| `8`–`15` | multicolour — 4 double-width pixels, 4 colours |

**For deck 1 the split is 930 hires cells to 190 multicolour** — the play area is mostly hires,
with multicolour used for shading. That is why the ALERT lettering stays crisp while the floor
and walls carry four colours.

The mode is driven per character code, and it is **deck dependent**:

```
CharColor[code]  upper nibble = palette slot (0-11)
NewCharColors    rewrites the lower nibble per deck from a 12-slot record
                 at $6A44, chosen by deckColorScheme ($F160)
BuildLevel       writes that byte to colour RAM; the VIC uses the low nibble
```

Only slot 5 is multicolour in every scheme and only slot 11 is hires in every scheme; the rest
vary, so **a character's mode genuinely changes between decks**. `tools/analyse_charmode.py`
dumps this; `tools/rip_deck_mixed.py` renders a deck the way the C64 displays it.

A multicolour character byte is four 2-bit pixel pairs, each two screen pixels wide:

| bits | source | in the artwork |
|---|---|---|
| `00` | `$D021` background | floor |
| `01` | `$D022` | |
| `10` | `$D023` | |
| `11` | colour RAM, per cell | |

**MODE 1 handles both modes**, because it has no attribute constraints: 4 colours freely per pixel
at 320 across. A hires cell converts to 8 MODE 1 pixels of background + one colour; a multicolour
cell converts to 4 doubled pixels using all four. Either way a character is **16 bytes**, so
`plot_char` is unchanged.

MODE 1 pixel *n* takes bit `7-n` as its high colour bit and bit `3-n` as its low.

**Logical colour assignment.** MODE 1's four colours are global, but the C64 draws on a 12-slot
per-deck palette. `export_bbc.py` counts how often each C64 colour is actually used across the
tile set and assigns logical 0 = background plus the three most-used; anything left over maps to
the nearest by luminance. For deck 1 that gives:

| logical | C64 | role | uses |
|---|---|---|---|
| 0 | light blue | floor | background |
| 1 | white | highlight | 272 |
| 2 | red | shadow | 220 |
| 3 | yellow | grid lines | 78 |

Three foregrounds is enough for deck 1. **This needs checking per deck** — a deck needing four or
more distinct foregrounds would lose one to the nearest-luminance fallback.

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
values are emitted as **`.deckBg`** and `BuildCharset` indexes `colourMap` with them.

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
