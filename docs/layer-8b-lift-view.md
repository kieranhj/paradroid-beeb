# Layer 8b — the lift's deck-selection screen

**Status: BUILT 2026-08-17.** Fire on a lift platform pauses the game and shows the ship
cross-section — the C64's `DoLift` (`$267A`) display — with the chosen lift's shaft marked
down its length and the selected deck lit. K/M walk the selection along the shaft, fire
commits. Verified in jsbeeb: real entry from a platform, stepping with the highlight
moving deck to deck, commit loading the chosen deck and placing the player on its
platform, and an unmoved fire returning to the same spot with no load.

Layer 8 built the lift *mechanics* (stop table, shaft sentinels, `LiftPlace`); this is
the display they were waiting on.

## 1. What the C64 does

| | | |
|---|---|---|
| `DoLift` | `$267A` | the modal loop: draw, poll, commit |
| `DrawSideview` / `DrawPacked` | `$3069` / `$30A0` | `SideView_dat` (`$F180`, 201 B RLE) into a 64-wide grid clipped to 39 columns, 16 rows at screen rows 9–24. Codes gain `ORA #$80` — the upper half of the game charset — and code `$29` is the blank |
| `FindLift`'s tail | `$2757` | colour RAM `$F9` down the shaft's column, `liftShaftX/Y/Height` |
| `lift_HighlightDeck` | `$240C` | the deck's rectangle (`$F120–$F150`) swaps characters ±`$10` — lit and unlit hull are adjacent charset halves. Two arms: multi-row for the tall engine decks, single-row with a wider code set for the rest |
| `ChangeDeck` | `$2705` | step the stop index, bounded by the shaft sentinels, re-highlight — **and `BuildLevel` per step**, so the C64's exit is instant |

## 2. How it ports — Layer 10's machinery, reused wholesale

The side view is 16 rows × 40 of read-modify-write character logic — the transfer board's
exact shape — and the two screens can never be up at once. So `liftview.asm` lives in
**bank 7** beside `xfer.asm` and shares: the shadow screen and colour shadow
(`xsScr`/`xsCram`), the code→glyph page (`xsGlyphOf`, rebuilt by whichever screen opens),
the row-address tables, the zero-page aliases, the panel-line text engine
(`XfGlyphAt`/`XfTextClear`), the palette save slot (`xfPalSave`) and the 16-row `t1i3`
switch. The stepping half (`LvEnter4`/`LvTick4`/`LvStep`/`LvExit4`) is in **bank 4** with
the stop tables it reads; main RAM carries only the two trampolines in `lift.asm`.

`lift_HighlightDeck` transliterates **verbatim** against the shadow — magic constants,
the `LDY #-2` row bail-out and all — because the pen is a *rendering rule*, not stored
state: `LvCellPaint` draws lit characters (`$90–$9D`) from the yellow set, cells the
shaft mark coloured `$F9` from the magenta set, everything else white. Toggling the
characters IS the highlight and the colour follows by itself. A step repaints only the
two deck rectangles, not the screen.

`liftMode` became a three-state: 0 none; 1 *entering* — set by `LiftEnter` in the fire
block, consumed the same pass at the hook after `DroidsUpdate` (the transfer's entry
point), which flattens the scroll, swaps the palette and draws; 2 *view up* — the main
loop runs one `LiftViewTick` a pass and nothing else.

## 3. Decisions

1. **[DECISION] The deck loads ONCE, at commit** (KC, 2026-08-17) — not per step as the
   C64's `BuildLevel` does. Our `LoadDeck` draws into the play buffer the side view is
   occupying, so browsing is free and the commit costs one ordinary deck-load pause. An
   unmoved selection skips the load entirely: `ReframeView` + `PanelSetup` and you are
   standing where you were.
2. **[DECISION] Fire commits; there is no separate cancel** (KC) — the C64's own shape.
   Firing without moving *is* the cancel.
3. **[DECISION] The palette** (KC, revised 2026-08-17): blue field, the emboss in white
   and black, the lit deck's fill magenta — the C64's dark purple. The first cut (black
   field, pen-coloured shapes) flattened the `10` pairs into the background, which erased
   the black half of every embossed edge and read as stippling; the colour belongs IN the
   artwork, one logical colour per multicolour pair. `palLift` in droid.asm.
4. **[DECISION] The panel line shows "lift" and the deck number** (KC), two digits of
   the engine's own 0–15 — deck *names* live in bank 6's token table, unreachable from
   bank 7; noted in PLAN.md for Layer 13's reshuffle.
5. **[DECISION] Colour is baked into the glyphs at export**, one logical colour per
   multicolour pair — 00 blue, 01 white (`$D022`), 10 black (`$D023`) — and EVERY
   character converts as pairs; there is no hires path. The 11 plane's colour is per
   set and per slot: the hull's (slot 5) is the lit deck's magenta fill, an unmarked
   ladder's rungs render white so the shafts read neutral, and the MARKED shaft's rungs
   take the magenta — our reading of the colour-RAM `$F9` mark that singles out yours on
   the C64. Two sets total. **The mode trap, learned twice:** the runtime multicolour
   flag is colour RAM bit 3, rewritten per deck by `NewCharColors` — the static
   `CharColor` table's low nibble is 0, so reading *its* bit 3 rendered everything
   hires and dotted the hull lines; deciding by the upper nibble's palette slot then
   left the shaft characters hires and dotted the ladder end rungs. The art itself is
   drawn in pairs throughout — 2px rails, embossed shadows, solid rungs.
   `tools/export_sideview.py`, which also emits the RLE verbatim, the deck/shaft
   tables, and the decoded ship as ASCII for eyeballing.
6. The C64's per-step and commit sounds are skipped — no sound layer yet.
7. The old `LiftExit`/`LiftStep`/`LiftControl` in lift.asm are gone: exit-on-fire is the
   view's commit now, and the stepping moved to bank 4 as `LvStep`/`LvTick4`. The fire
   block's exit arm was deleted with them — `liftMode` can only be 0 when it runs.

## 4. Verified in jsbeeb (2026-08-17)

Entry poked and real; the cross-section renders against the exporter's ASCII decode;
shaft 2 marked magenta; deck 4 lit, stepped to deck 5 with both rectangles repainting
correctly; commit loaded deck 5 and placed the player on the platform (mode word,
palette and deck all restored); re-entry from that platform's genuine fire press; unmoved
fire returned without a load, droids resuming.

**Not yet verified**: the tall engine-deck rectangles (heights 2–3, `lvh_1`'s multi-row
arm) by eye, and shafts near the view's edges — wanted from play-testing across more of
the ship.

## 5. For whoever touches this next

The console's deferred ship page (`con_ShipInfo`, `$3062`) draws this same side view with
the same highlight — when Layer 13 builds it, `LvDrawPacked`/`LvHighlight`/the renderer
are already in bank 7; it needs only an entry that skips the shaft mark and a way in from
the console's bank-6 code (a trampoline through main RAM, as everything cross-bank is).
