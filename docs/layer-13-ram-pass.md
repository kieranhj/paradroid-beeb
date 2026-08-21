# Layer 13a — The RAM pass

**Status: in progress, started 2026-08-19.** Scoped with KC after the Layer 11 notes recorded that
main RAM had 30 bytes, bank 4 fifteen and bank 6 forty, and that 11c's loop, 11d and 11e were all
blocked on room rather than on design.

The analysis that opened it is in §1. Each task below is a **[TASK]** with what it freed, how it
was verified, and — where it changes an arrangement the original did not have — the reasoning that
made it safe. Tier 1 is the set that costs no cycles and changes no behaviour.

## 1. Where the 96 K goes, and why 64 K on the C64 held more

Measured from a label dump of the 2026-08-19 build, not from a plan.

| Region | Used | Free |
|---|---|---|
| main RAM | 30.6 K | 1,416 (1,136 at `&0C90`, 24 at `&2FE8`, 256 at `&5400`) |
| bank 4 `PARADAT` | 16.4 K span, ~9.4 K data + ~6.2 K code | 15, plus 739 in internal alignment holes |
| bank 5 `PARASPR` | 12.4 K blitter + 2,748 effects | 1,033 |
| bank 6 `PARSPR2` | 12.7 K blitter + ~3.6 K Layer 9 | 40 |
| bank 7 `PARXFER` | ~12 K + a 2 K runtime shadow buffer | 282 |

**The port pays five costs the C64 does not**, and they come to about 44 K — which is why 96 K
holds less game than the C64's 64 K:

1. **The compiled blitter, ~25.1 K** across banks 5 and 6, against the C64's ~2–3 K of sprite data
   and no code at all: the VIC does positioning, masking and restore in silicon. Net **+22.5 K**.
   It earns it — seven sprites went from 68 K cycles a pass to 40.7 K of 79,872.
2. **Screen memory, ≈ +10 K.** The C64 game is character-mapped: a 1 K screen matrix (2 K
   double-buffered), colour RAM in separate silicon, and the pixels living once in a shared 2 K
   1bpp charset that VSP scrolls for free. The CRTC scrolls *addresses*, so the play area must hold
   real pixels — 10 K strip, 2.5 K panel, and a 1 K tile map **as well as** the pixels it expands
   to, where the C64's screen RAM *is* its tile map.
3. **2bpp doubling, ≈ +5 K.** MODE 1 doubles the charset (2,192 against 1,096, and the 1bpp source
   is kept too, to rebuild per deck), the text font, the effect artwork and every bank-7 glyph set.
4. **The bank tax, ≈ +4–5 K.** One bank visible at a time, so `constrings7`, `droidicon7` (both
   since gone — TASK 7 took the strings to one main-RAM copy, and 13d deleted `droidicon7` with
   the portrait stand-in) and
   `conDrDigits7` are literal second copies (~1.8 K); the transfer and lift glyph sets ship
   pre-recoloured variants (~1.1 K); the shadow screen was 2 K of bank rather than a reuse; plus
   shims, paging and ~900 bytes of alignment holes.
5. **The side costs of having no hardware sprites, +2.8 K** — save areas 2,048, `SPR_MASKTAB` 256,
   `CHAR_PTR` 512.

Against that the port has *dropped* C64 content — the 48 × 84 portraits, the intro manual, the high
score table, the tape loader and the SID engine — which is the problem rather than the relief: the
rest of the game has to fit in what is left.

## 2. Tier 1 — no cycle cost, no behaviour change

### [TASK 1] The transfer and lift shadow buffers move onto the sprite save areas — **+2,048 bank 7**

`xfer.asm`'s four `SKIP` blocks — `xsScr` (768, of which 640 is screen and the rest is the fixed
`XS_COFF` offset that makes the C64's "add $90 to the high byte" into "add 3"), `xsCram` (640),
`xsStage` (256) and `xsGlyphOf` (256) — were 1,920 bytes of bank 7 plus its `ALIGN &100` padding.
They are now **constants pointing at `SPR_SAVE`**, in main RAM, and cost the bank nothing:

```
xsScr     = SPR_SAVE
xsCram    = xsScr + XS_COFF
xsStage   = xsCram + &280
xsGlyphOf = xsStage + &100
```

The relative layout is unchanged, so `xsStage` keeps the same non-page-aligned offset it always had
— it sat at base + `&580` in the bank, and only `xsScr` was ever aligned.

**Why it is safe, and it is not a new idea.** `ConDeckEnter4` already stages the deck's RLE stream
at `SPR_SAVE` on exactly this reasoning, which its own comment states: *"the sprite background saves
are scratch while the console is up, because ReframeView throws them away on the way out
(rv_unsave)"*. The three screens that use the shadow buffers are the same kind of thing:

- **All three are modal.** `overPhase == 2`, `xferActive` and `liftMode == 2` each take an arm in
  the main loop that ends the pass with `JMP ml_passend`, and all three arms are **above**
  `SprRestoreAll` and `SprDrawAll`. The pool is frozen for the whole time any of them is up, so
  nothing reads a save area while it is being overwritten.
- **Every way out goes through `ReframeView`**, whose `rv_unsave` clears all eight `sprSaved` flags
  before anything can restore, and whose `RedrawAll` repaints the buffer:
  transfer → `XferExit4` → `ReframeView`; lift view → `ReframeView`, or `LoadDeck` → `ReframeView`;
  game over → `GameStart` → `SprInit` (which clears `sprSaved`) and `LoadDeck` → `ReframeView`;
  console → `ConsoleClose` → `ReframeView`.
- **The console and these three are mutually exclusive** and both re-stage on every entry, so
  sharing the region with `ConDeckEnter4` costs neither of them anything.

1,920 of the 2,048 bytes are used, and an `ASSERT` holds it inside the save areas.

Note that the entry happens *after* `SprDrawAll` in the pass — the sprites really have drawn and
`sprSaved` really is set when the board takes the buffer over. That is fine, and the main loop's own
comment says why: *"the board draw is about to overwrite everything the tranches would have
repaired."*

**Verified in jsbeeb**, on a running game with a deck loaded and the pool live:

- Transfer: poking `xferDroid` entered it, the shadow screen at `&3E00` filled with real board glyph
  codes (`&FB`, `&F5`, `&D0`, `&F8`, `&D1`), and on exit the play buffer was **byte-identical to a
  forced `RedrawAll` — 0 diffs of 10,240**, with `SprDrawAll`/`SprDrawTr` poked to `RTS` so a
  spinning rotor could not pollute the comparison.
- Game over: `drType`/`drEnergy` to zero gave the cloud (`overPhase` 1), then `EndGame`'s wash
  (phase 2) writing its wash characters through `&3E00`, then a fresh game — and the buffer after
  the whole cycle was again **0 diffs of 10,240** against a forced redraw.
- Lift view: `liftMode` 1 brought the side view up (`liftMode` 2) with its own glyph codes in the
  shadow screen at `&3E00`.

### [TASK 2] The lift view's second glyph set was 592 bytes to change three glyphs — **+544 bank 7**

`sideview.asm` shipped `svChars1` and `svChars2`, two full 37-glyph sets at 16 bytes each, the
second being what colour RAM `$F9` does to the first down a marked shaft. **They differ in 20 bytes
of 592, and all 20 are in glyphs 33, 34 and 35** — codes `&A5`, `&A6`, `&A7`, the shaft rungs.

That is not a coincidence and it is the reason the saving is safe to take: `$F9` forces
multicolour and promotes `01` pairs to white, so it changes a glyph **only where the glyph has
`01` pairs to promote**. Every other character in the set has none, so for all of them `svChars1`
already *is* the marked artwork, byte for byte.

`tools/export_sideview.py` now emits `svCharsMk` — only the run of glyphs that actually differ —
with `SV_MARK0` and `SV_MARK_N` beside it, and asserts both that the run is non-empty and that it
*is* a run, so a future charset change cannot silently break `LvCell`'s range test. `LvCell` gained
seven instructions: pen 2 below `SV_MARK0` or at/above `SV_MARK0 + SV_MARK_N` uses `svChars1`, and
between them it subtracts `SV_MARK0` and takes pen 3, `svCharsMk`. The pen table grew by one entry
and entry 2 now points at `svChars1`.

**Verified in jsbeeb, byte for byte against the build before the change.** With `deck`, `liftNum`
and `liftMode` poked to the same values on both, the lift view's 10,240-byte render came out
**0 diffs**. In the render itself the marked rung pattern (`3F 0C 0C 3F …`) appears 8 times — down
the one chosen shaft — and the unmarked pattern (`0F 0C 0C 0F …`) 27 times, which is the split the
screen should have.

> **Costed and not taken: `xbCharsPly`/`xbCharsCpu`, 272 bytes.** The transfer board ships three
> 17-glyph sets — neutral, player, CPU — and the recolour there is *positional*, not a uniform
> mask: `&FF` maps to `&FF`, `&CF`, `&3F` and `&0F` in different places, because the frame pixels
> stay logical 3 while the wire pixels recolour. So the sideview trick does not apply. What is true,
> and measured, is that **the CPU set is exactly derivable from the other two** —
> `cpu = neutral AND NOT((neutral AND NOT ply) >> 4)` holds for all 272 bytes, and the reverse
> derivation holds too. That would buy 272 bytes for a per-byte computation in the board renderer.
> Left undone: it is the worst complexity-per-byte on the list and bank 7 is no longer the scarce
> bank. Recorded here so it does not have to be re-derived if that changes.

### [TASK 5] The "739 bytes of alignment holes" in bank 4 were not there — **+0**

Recorded because the first analysis of this pass claimed them and it was wrong.

A gap-finder over the beebasm listing reports six holes in bank 4 totalling 739 bytes. **Four of
them are `SKIP`-reserved working storage, not waste** — `doorDef` before `blankTileRow` (112),
`LUTs` before `bcDeck` (64), `drVis`/`drVisNew` before `losTurn` (196) and 256 more before
`XferEnter4`. `SKIP` emits nothing, so a listing-based gap detector cannot tell reserved storage
from padding. The same correction applies to main RAM's apparent 28- and 152-byte holes.

That leaves **111 bytes** of genuine `ALIGN &100` padding, before `charRemap` (47) and `colourMap`
(64). Both are safe to unalign — each is only ever read as `LDA table,X`, `colourMap` at deck load
and `charRemap` in a single 256-iteration startup loop that `main.asm` notes is "never touched
again" — but **removing them frees nothing**, and this was measured, not assumed: `tiledefs`
follows with an `ALIGN` of its own, and 111 bytes of padding removed upstream reappear as 111 bytes
of padding before it. Bank 4 free stayed at 15.

**`tiledefs`' alignment is load-bearing and must not be removed.** `screen.asm`'s `MapChar` builds
its pointer as low-nibble × 16 into `tdp` and high-nibble + `HI(tiledefs)` into `tdp+1`, with no
addition of `LO(tiledefs)` anywhere — which is only correct if `LO(tiledefs)` is zero. `scroll.asm`
does the same.

So the 111 bytes can only be recovered by *filling* the two holes with blocks of ≤ 47 and ≤ 64
bytes emitted from the right point in the include order, across three generated files. Not taken:
the return is small and bank 4 is no longer the only place to put things — see TASK 1.

### [TASK 6] The offset tables were 192 bytes of the one region that is full — **+118 main RAM, +7 bank 6**

**Main RAM went from 30 bytes free to 148**, which is what matters: `&1100-&3000` is the only
region in the machine that is genuinely full, and Layer 11c's loop needs 39 bytes of it.

`rowMulLo`/`rowMulHi` (16 each) and `unitMulLo`/`unitMulHi` (80 each) were `FOR`/`EQUB` blocks in
`bufcore.asm`, 192 bytes of the code image holding nothing but *n* × 640 and *n* × 8. They are now
addresses in the free page at `&5400`, written at startup by `BuildMulTabs` — two 16-bit running
additions, 74 bytes, so the code image nets 118 back.

They **must** stay in main RAM: `SetCell` reads them with the *sprite* bank paged in, which is
`bufcore.asm`'s whole reason for existing. `&5400` is under both the bank staging overlay and the
title's framebuffer, so the call sits with `BuildCharPtrs` and `SprBuildMask`, after both.

**It found a real bug in `PnClear`, which is why `&5400` looked free and was not.** The routine
clears `HI(PANEL_BYTES)` whole pages and then a tail of `LO(PANEL_BYTES)` bytes — but
`LO(4 × 640)` is **zero**, and the tail is `STA (pnDst),Y : INY : CPY #0 : BNE`, which with Y
already zero compares equal only after Y has wrapped. So it cleared a whole extra page,
`&5400-&54FF`, every time `PanelInit` ran. Invisible while nothing lived there; the tables landed
in it and came back zeroed. The fix is `IF LO(PANEL_BYTES) > 0` around the tail, so it is assembled
away at four rows and still assembled in for a `PANEL_ROWS` that does leave a remainder — and bank 6
gets 7 bytes back.

**Verified in jsbeeb:**

- All 192 bytes read back exactly right: `rowMulLo` `00 80 00 80 …`, `rowMulHi` `00 02 05 07 … 25`,
  `unitMulLo` counting by 8 and wrapping every 32, `unitMulHi` 32 × `00`, 32 × `01`, 16 × `02`.
- Unchanged after scrolling, and a **write breakpoint on the table page stayed silent** for 60
  frames of play and 90 frames of scrolling — nothing writes them once built.
- A **read breakpoint on `&54D0`** — the part of the page past the tables that `PnClear` used to
  zero and now nobody initialises — also stayed silent, over 120 frames of play and 90 of
  scrolling. Nothing was relying on that region being zero.
- The play buffer matched a forced `RedrawAll` — **0 diffs of 10,240** — stationary, after
  horizontal scrolling, and after diagonal scrolling in both directions, with
  `SprDrawAll`/`SprDrawTr` poked to `RTS`.

> **One oracle failure, not explained, and probably not this change — see BUGS.md #15.** On one
> deck, after a diagonal scroll, 176 bytes differed, settling to 7 over 3 M cycles. It sat on
> `doorRow[0]` with `doorState` showing a door at step 2 of its animation, and it did not reproduce
> on two other decks or on the other diagonal. The tables were read back byte-perfect in that same
> state, so `SetCell` was computing the same addresses it always did. Logged rather than dismissed.

## 3. Tier 1's last two — costed, NOT built, waiting on KC

Both were in the original tier-1 list. Both turned out to need a decision rather than an
afternoon, and the reason is the same in each case: what tier 1 has already freed changed what
they are worth.

### [TASK 3] The text font in 1bpp — **BUILT 2026-08-19. +1,744 in the font region, +20 bank 6, −82 main RAM**

**The packed byte is the C64's own font byte, and that is the whole point.** The artwork is two
colour — logical 0 and logical 3 — so a MODE 1 byte holding it comes out as `n<<4 | n`: four pixels
in eight bits. Pair a cell's byte *i* with its byte *i+8*, the same scanline's left and right
halves, and you get back `(left<<4) | right`, which is the C64's own 8-pixels-per-byte scanline.
So this is not an encoding the port invented; it is the **removal** of one, and `export_font.py`
now emits `glyph_rows` straight out rather than converting.

| | Was | Now |
|---|---|---|
| `textfont`, 103 glyphs × 2 cells | 3,296 | 1,648 |
| `panelframe`, 12 cells | 192 | 96 |

`PARAFNT` is 1,744 bytes instead of 3,488, and **`&3730`–`&3E00` — 1,744 bytes — is free**. That is
buffer space under the staging overlay, so it takes runtime-built tables or a file `*LOAD`ed after
the bank copies, which is exactly what `PARAFNT` itself is. `constrings` is 1,731 and now fits, with
13 to spare — [TASK 7] below.

**One renderer, in main RAM, replacing four copies.** `PnGlyph` and `PnCell` (bank 6) and
`XfGlyphAt` and `DbGlyph` (bank 7) were the same loop four times. Packing breaks that loop shape —
the source index becomes a function of the output index and only Y can index indirectly — so rather
than solve it four times, `FontCell` solves it once and every site *shrinks*: **bank 6 gained 20
bytes and bank 7's sites gained about 25**, though bank 7 shows no net change because `planInk`'s
`ALIGN &100` absorbed it, the same way `tiledefs` absorbs bank 4's in [TASK 5].

`FontCell` costs **82 bytes of the code image** — KC's call, taken deliberately: main RAM drops from
148 to 66, which still covers 11c's 39, and it is what makes the freed region big enough for
`constrings`. It runs two passes over the 8 packed bytes, adding 8 to `swDst` between them, because
a third zero-page pointer does not exist to hold the second half's destination.

**Two things every future caller must know.** `fontMask` is a variable and **must be set before
every call** — `XfGlyphAt` had no mask at all and now sets `&FF` explicitly. And `XfGlyphAt` moved
off `xgs`/`xgd` onto `swSrc`/`swDst`, because `FontCell` names that pair; they are free there, as
`PageBankIn` is boot-only and `PanelTick` does not run while the transfer owns the panel line.

**Verified, in five ways:**

1. **At generation time, which is the real proof.** `export_font.py` asserts for every cell it emits
   that expanding the packed byte's two nibbles reproduces the MODE 1 pair exactly. All 103 glyphs
   and 12 border cells pass, so the data cannot be lossy by construction.
2. **Independently**, against the previous generated file: all 3,488 old bytes reconstruct from the
   1,744 new ones.
3. **The panel — `PnGlyph` and `PnCell` — is byte-identical to the pre-change build**: 0 diffs of
   2,560, same deck, covering all twelve border cells, the mode word, the logo, the score and the
   deck number.
4. **The console's text is byte-identical** to the pre-change build on the same deck. The only cells
   that differ in its 10,240 bytes are the 4 × 3 block holding the rotor-and-digits droid — which is
   drawn from `conDrRotor`/`conDrDigits` in bank 6 and never touches the font. It differs because it
   is state: two separate games on the *same* build differ there too.
5. **The two bank-7 sites render correctly**, checked as bitmaps: the transfer's panel line and the
   droid database's "Unit type" line both come out crisp, with the `y` and `p` descenders correctly
   spanning into the lower cell — which is precisely what a mis-paired packing would break.

And the play buffer is unaffected, as it should be: **0 diffs of 10,240** against a forced
`RedrawAll` after a clean boot and a diagonal scroll.

### [TASK 7] The string table existed twice — **BUILT 2026-08-19. +1,542 bank 6, +1,536 bank 7**

`constrings` was 1,542 bytes in bank 6 for the console main screen and `constrings7` was the same
1,542 in bank 7 for the droid database, because only one bank is visible at a time and neither
reader could see the other's copy.

**Neither reader cares where the table is.** Both patch a self-modifying absolute with its base —
`ConTok` writes `ctk_get+1/+2`, `DbTokFind` writes `db_get+1/+2` — and then scan for bit 7, because
the C64's `FindStrings` index is 249 pointers and 498 bytes was never worth it here. An absolute
address reaches main RAM from either bank, so **one copy in main RAM serves both**, and it goes in
the room TASK 3 freed: `PARAFNT` carries it straight after the border cells.

```
&3000  font        1,648      1bpp, TASK 3
&3670  panelframe     96
&36D0  constrings  1,542      <- TASK 7, one copy, loaded not paged
&3CD6  PN_TABS        96      runtime-filled by PageTabsIn
&3D36  free          202
&3E00  SPR_SAVE
```

`CON_STR_COUNT`/`CON_STR_BYTES` moved up beside `FONT_BYTES` for the reason that block already
gives — beebasm resolves constants in file order and `PN_TABS` needs the size. `export_strings.py`
stopped emitting the second copy and `src/data/strings7.asm` is gone.

Bank 7 gains 1,536 rather than 1,542; the missing 6 went into `planInk`'s `ALIGN`, as in TASK 5.

**Verified in jsbeeb:**

- The table loads at `&36D0` with the source's own bytes (`C7 4C 44 4A 53 43 4C 41 43 C2 …`).
- **The droid database — the reader whose base address actually changed — prints correctly**:
  "Unit type 001" and "Influence Device", the C64's own tokens, rendered legibly.
- **The console main screen is byte-identical to the pre-change build** on the same deck. Thirteen
  cells of its 10,240 bytes differ and all thirteen are the rotor-and-digits droid image, which is
  drawn from `conDrRotor` in bank 6 and has nothing to do with the strings — twelve are the image
  and the thirteenth is its bottom scanline spilling into the row below.
- The play buffer is untouched by any of it, as expected.

### [TASK 8] The decoder did not have to be in the code image — **+82 main RAM**

`FontCell`, its 16-byte expansion table and its ink byte were 82 bytes of **`&1100`-`&3000`**, and
that is the one region in the machine that is genuinely full. They never needed to be there. What
they need is to be **main RAM**, so that bank 6 and bank 7 can both `JSR` to them — and the room
TASK 3 freed is main RAM too. So they moved into the `PARAFNT` file, after the string table:

```
&3000  font        1,648   1bpp
&3670  panelframe     96
&36D0  constrings  1,542   one copy, TASK 7
&3CD6  FontCell       82   TASK 8 — the decoder, with the font it decodes
&3D28  PN_TABS        96   runtime-filled by PageTabsIn
&3D88  free          120
&3E00  SPR_SAVE
```

**The code image goes back to 148 bytes**, which is where Layer 11e's sound driver has to live: the
IRQ reads no sideways bank, and the C64 calls its sound driver from the interrupt.

`FONTCODE_BYTES` is declared up front beside `FONT_BYTES` and `CON_STR_BYTES` — beebasm resolves
constants in file order and `PN_TABS` needs the size — and `ASSERT`ed against the assembled length,
which is what caught the first guess of 83. Nothing calls `FontCell` before `PARAFNT` loads:
`FillPanel` does not touch the font and the title carries its own glyphs.

**Verified in jsbeeb**, all four callers, with the decoder running from `&3CD6`:

- The panel is **0 diffs of 2,560 against the build from before TASK 3** — that is, against the
  original 2bpp font with no `FontCell` at all. `PnGlyph` and `PnCell` both.
- The droid database's text is byte-identical to the TASK 7 build — "Unit type 001", "Influence
  Device" and the stat lines. `DbGlyph` and the shared string table.
- The transfer's panel line renders crisp glyphs with correct descenders. `XfGlyphAt`.

> **Costed and NOT taken: the rest of TASK 8.** The two-cell wrapper is still duplicated three times
> — `PnGlyph` 87 B, `XfGlyphAt` 107 B, `DbGlyph` 89 B, sharing about 66 bytes of body — and a
> shared `FontGlyph` would buy roughly 63 bytes in bank 6 and 134 in bank 7 for ~66 of main RAM.
> The console droid icon is duplicated too, 110 bytes in each bank. **Both were worth doing when
> banks 6 and 7 had 47 and 282 bytes. They are not now they have 1,609 and 4,410** — the churn
> across four routines in two banks buys nothing scarce. Recorded so it need not be re-derived.

### [TASK 4] The title screen as a transient disc file — ~1,500 bytes of bank 7, and no longer needed

`titleGlyphs` (576), `titleRLE` (564) and the `Ti*`/`Go*` code sit in bank 7 permanently, even
though [DECISION 6] already agreed the title should be a separate file loaded on the way in and
discarded by the first deck load.

**Two things argue against building it now.** Bank 7 has gone from 282 bytes to 2,874, so the space
is no longer wanted — TASK 4 was on the list to unblock 11d, and TASK 1 unblocked it instead. And
the change needs a disc load *after* boot, which means tearing the rupture and the IRQ down and
building them back up: `docs/layer-11-sound-title.md` §5 leaves exactly that to KC, and `CLAUDE.md`
is explicit that rebuilding the display unverified is what `hal_video.asm` was. The 39 bytes of main
RAM that blocked 11c's loop are now there without touching any of it.
