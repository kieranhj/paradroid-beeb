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
4. **The bank tax, ≈ +4–5 K.** One bank visible at a time, so `constrings7`, `droidicon7` and
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
