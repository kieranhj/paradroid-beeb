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
the `LDY #-2` row bail-out and all — because the colour lives in the ARTWORK (decision
5): the lit variants carry their own magenta fill, so toggling the characters IS the
whole highlight. The one rendering rule left is the C64's own: a cell the shaft mark
coloured `$F9` draws from the forced-multicolour set. A step repaints only the two deck
rectangles, not the screen.

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
4. **[DECISION] The panel line shows "Lift" — and, since 2026-08-27, NOTHING ELSE.**
   It used to carry the deck number beside it, two digits of the engine's own 0–15,
   repainted by `LvTick7` on every step of the light. **KC: the C64 prints nothing there**
   — `DrawSideview` writes the view and leaves the status rows alone — so the number was
   this port's own addition and `LvNumText` is deleted with it. (The old note about deck
   *names* living in bank 6's token table, unreachable from bank 7, is moot: there is no
   number to name.) The word itself was **capitalised 2026-08-26** with the transfer game's
   own words (layer-10 DECISION 15): same panel field, same `XfGlyphAt`, and capital L is
   two cells so its right half is a fifth call. Five cells of the eleven; `XfTextClear`
   blanks the rest.
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

## 4a. The exit shows the deck you are going TO, 2026-08-29 — palette handling SUPERSEDED by 4b

**KC:** "when changing deck in the lift selection screen, the palette changes to the previous
deck briefly on exiting the lift, before then changing to the new deck palette and drawing the
screen. It should just change to the new deck."

`LvEnter4` saves `palPlay` into `xfPalSave` on the way in and installs `palLift`; `LvExit4` put
the save back. That save is **the deck being left**, and on a changed selection the new deck's
colours did not arrive until `RedrawAll`'s `SetPalette` at the far end of `LoadDeck` — a
charset build, a level decode and a full redraw later, with the rupture applying the wrong
table three times a field throughout. So the wrong-deck flash was the whole load, not a frame.

**The changed arm no longer restores anything.** It sets `deck`, `liftPlace` and `lvLoad` and
tail-calls `SetPalette` (same bank), so the new deck's palette is live before `LoadDeck` starts.
The save slot is simply abandoned — it is a slot, not live state, and the transfer game fills it
afresh. The unchanged arm still restores, and must: that palette **is** this deck's, cleared-floor
override and all.

**`deckClear` has to be cleared with it**, and that is not a detail: it still holds the *previous*
deck's answer until `DroidsInit` runs inside the load, and clearing a deck and taking the lift
onward is the ordinary way to play — so without it the new deck would come up **blue** for the
whole load (level.asm's cleared-floor arm) and we would have swapped one wrong palette for
another. A deck is presumed not cleared until `DroidsInit` says otherwise, which it does either
way, later in the same load.

**This is not layer-11d DECISION 4's `SetPalette` creeping back into `LoadDeck`.** That one had
to leave because an information screen is up across `LoadDeck` at `GameStart` and the deck's
colours overrode the text background `InfoCall` had just chosen. No screen is ever up on this
route — the lift is the only thing that had the machine — so the call belongs to the lift, not
to `LoadDeck`.

**Verified in jsbeeb**, riding a real lift (the player placed on lift 13, tile 8/7 of deck 6, by
`LiftPlace`'s own arithmetic — `plyX = col*32`, `posY = row*32-48`, `posX = plyX-148` — so
`CheckWalls` derived the reference cell 33/29 naturally and fire entered the lift for real).
Deck 6's floor is yellow and deck 5's is white, so `palPlay[0]` tells the whole story:
**`&03` (lift blue) → `&00` (deck 5 white) on the commit frame**, held through the load, with
deck 6's `&04` never appearing. The unchanged-selection exit still restores `&00`. 8 bytes of
bank 4, tail 33 → **25 B**.

## 4b. Every screen swap is hidden — black while drawing, 2026-09-01

**KC:** the 4a arrangement is odd the other way round — the *lift screen* recolours to the new
deck's palette a beat before the deck is drawn, and the drawing itself is watchable. Proposed
clearing to black and revealing the deck complete, via a play-area-only palette change.

**The C64 shows neither seam**, and that is the decision being ported: `ChangeDeck` ($2705)
calls `BuildLevel` *while the lift view is displayed* — the C64's lift screen is a separate VIC
screen, so the deck is built entirely off-screen and simply appears on exit. One shared play
buffer cannot build off-screen, so the port keeps the *effect*: **the player never sees the deck
plotted.**

The shape (superseding 4a's palette handling; its `deck`/`deckClear`/`liftPlace` ordering all
stands). **`PalBlack`** (screen.asm, bank 4) writes sixteen `palPlay` entries of physical black
(`&F7` down to `&07` by `&10`); a draw bracketed by `PalBlack` and a palette rebuild is
invisible, revealed complete by the next fire 1. Four places use it:

1. **`RedrawAll` starts with `JSR PalBlack` and ends with `JSR SetPalette`** (moved from its
   top; Layer-14 DECISION 4's reason — in the redraw so no exit path can forget it — is
   placement-agnostic). Every route BACK to the deck passes through it — the info screens'
   dismissal (the 001 start page included), the console's close, the transfer's and the lift's
   exits, `LoadDeck`, CTRL+R — so every deck replot is hidden.
2. **`LvExit4` does no palette work at all any more.** On a changed deck the lift screen simply
   stays up, static, across the charset build and level decode (exactly the C64's look), until
   `RedrawAll` blacks it and reveals the finished deck. Same-deck: straight to the redraw.
3. **The lift screen's own entry draw is hidden too** (KC's follow-up): `LvEnter4` ends in
   `PalBlack`, `LvStart7` draws the cross-section black, and `LvTick4` — every lift pass, so
   the first is the reveal and the rest are idempotent — installs `palLift` via
   `ConShipEnter4` (whose `palPlay` save nothing on the lift route reads back).
4. **So is the console's**: `ConMenuInit4` ends in `PalBlack` instead of `SetTextPal` (the
   2026-08-24 "palette before the draw" arrangement, now inverted), `ConsoleOpen` draws black,
   and `ConMenu4`'s top — every menu pass — runs `SetTextPal` as the reveal. Safe because
   `ConMenu4` runs only in the menu state, and the page arms set their own palettes AFTER it
   on the press pass.

NOT hidden (unchanged, candidates if wanted): the console pages' draws over the menu (ship,
deck plan, database — the plan deliberately draws in the deck's colours), the menu's redraw on
a page's close, and the transfer board's entry.

Net **−10 bytes of bank 4** across the whole change (11 → 19 free); main RAM untouched. The
panel is untouched throughout — `palPanel` is applied at VSync, `palPlay` at fire 1, so the
black covers exactly the play area.

**Verified in jsbeeb**, all on real routes: the lift ridden via the 4a recipe (same-deck exit,
and one step up with `deck`=5 confirmed mid-load), the console entered by fire on a real
console cell (map tile 16 at 10/2 of deck 6, reference cell 41/10) and exited to the deck, and
the 001 page dismissed into the first deck draw. In every case `palPlay` read back all-black
during the draw, the play area was a clean black rectangle under a live panel, and the finished
screen appeared in its own colours in one go.

## 5. For whoever touches this next

The console's ship page (`con_ShipInfo`, `$3062`) was built on this drawer the same day:
`LvShip7` is `LvStart7` minus the shaft mark and the panel text, reached through the console
menu (`ConMenu4`, droid.asm, bank 4) with `ConsoleTick` doing the paging and the lift palette
swapped in around it. See layer-9-hud.md section 6e.
