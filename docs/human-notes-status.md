# Kieran's Human Notes — reconciliation and status

**Moved out of `PLAN.md` on 2026-09-01** when the plan was pruned: nearly everything here is
closed, and the record matters more than the reminder. The source notes are
[`Kieran's Human Notes.txt`](Kieran's%20Human%20Notes.txt) (KC's own file, his DONE/NO marks
are the sign-off); this file is the port-side status of every item, with pointers to where
each fix or decision is written up. The handful still open are listed in `PLAN.md` — this
file is history.

Everything in [`Kieran's Human Notes.txt`](Kieran's%20Human%20Notes.txt) not marked
DONE or NO, added to the plan 2026-08-26, **reconciled against that file again on 2026-08-31**,
and closed out (bar the few items now in `PLAN.md`) on 2026-09-01. Where a note overlapped a row
in the old plan, the row was the home and the note cross-referenced it. KC's own DONE/NO marks
are the sign-off: an item struck through here is struck there.

**Transfer**

- ~~The score should go up **inside** the transfer game, before returning to the main game.~~
  **DONE 2026-08-27** — the transfer arm calls `DoScore` for itself, so a win counts up on the
  board rather than after it. It was marked NEEDS RAM; the RAM pass had provided it.
- The intro droid cards have a white background on the C64. *(New in the notes since 2026-08-26.)*

**Gameplay**

- ~~Sprite flicker (still).~~ **CLOSED by KC 2026-09-01** — considered fixed by the raster and
  tranche work.
- ~~**BUG:** shooting while at full tilt leaves a few pixels behind (KC, deck 476).~~ **CLOSED
  by KC 2026-09-01** — no longer observed on the current build.
- ~~**BUG:** droid sprite corruption when entering the console.~~ **FIXED 2026-08-31** as
  `BUGS.md` #12: the console opens mid-pass above tranche B, which stamped droids and bullets
  back over the freshly drawn page; `ConMenuInit4` clears `sprSplit`. (Since 2026-09-01 the
  console's entry draw is also hidden entirely — layer-8b §4b.)
- Explosion sprites in multicolour — the note asks whether it needs a new sprite plotter; the
  effect sprites run the interpreted path today, which is the same question as the enemy bullet's
  colour flicker row above. *(All three new in the notes since 2026-08-26.)*
- ~~Player 001 should flash on teleport-in at the start.~~ **DONE 2026-08-26.** It is not an entry
  effect: `_entership` holds him on SEVEN energy for 32 iterations, and the flash is the ordinary
  low-energy warning the port already had. `EntryHold` supplies the window; the same fix closed a
  live bug where the next-ship route set the 7 and nothing ever set it back.
  [`docs/layer-9-hud.md`](layer-9-hud.md) §7
- ~~Some of the decks have the lift tile missing?~~ **DONE 2026-08-26.** Decks 0, 5 and 9, and the
  tile was there — 4 of its 16 cells were drawn in a C64 colour that merged onto logical 0, which
  IS the floor on those three decks. The lift is **tile 3**, not tiles 23-27 as `graphics.md`'s
  table implies. [`docs/layer-14-visual.md`](layer-14-visual.md) [DECISION 10]
- ~~Lift selection does weird palette changes~~ (it showed the previous deck's briefly, then the
  new one). **DONE** — confirmed fixed by KC, 2026-08-31.
- ~~Separate key for transfer vs fire?~~ **DONE 2026-08-26.** SPACE goes straight to transfer mode
  and holds it, direction or no direction — the settle delay exists only to disambiguate a single
  button, so a dedicated one skips it. The fire route is untouched.
  [`docs/layer-7-combat.md`](layer-7-combat.md) [DECISION 12]
- ~~Getting into the lift just as the disruptor fires leaves the screen white.~~ **DONE
  2026-08-27** — a modal screen FROZE the burst instead of ending it, so `disrFlash` kept
  overriding the palette; `ml_modalend` ends it now. Confirmed by KC, 2026-08-31.

**Console**

- ~~Continually redrawing the top line when on the droid info page? Also the panel word?~~
  **CLOSED by KC 2026-09-01** — no longer observed.
- ~~The droid info screens are always on a white background with blue header and red text —
  should follow the deck?~~ **SATISFIED, KC 2026-09-01**: the background follows the deck
  (`deckTextPal`, layer-14 DECISION 4) and the fixed header/text colours are as wanted.

**Game over**

- ~~Improve the static — just B&W, and use the original's characters.~~ **DONE**, with the wash's
  length fixed at the same time ([`docs/layer-15-endgame.md`](layer-15-endgame.md) §6a).
- ~~"Game over" has a small g, and should be in red.~~ **DONE.**
- Nothing in this section of the notes is open any more.

**Front end**

- Update the scroll text wording.
- Add a Beeb page.
- ~~Why does it need to load after the Paradroid logo?~~ **ANSWERED, and accepted by KC
  2026-08-31.** The title is a disc overlay itself (`PARTITL`), and the manual's text (`PARMAN`,
  ~3.4 K compressed) is fetched only when the title times out, because it lands in bank 5 over the
  blitter and cannot be resident while a game might still start. `BrTimeout` is the load.
- ~~The briefing scroll speed is 2× the C64's — "OK as long as it is smooth on real hw/CRT, check
  the code again".~~ **CHECKED AND FIXED 2026-08-31.** The rate is one scanline a field exactly
  (100 scanlines in 100 fields, measured); the *motion* stalled a field and jumped two at every
  character row, because `BrPaintRow` is 90% of a field and the CRTC park came after it. Parking
  first fixed it. [`docs/layer-11f-frontend.md`](layer-11f-frontend.md) §4e-2
- The top line of the briefing scroller flickers a bit more on real hardware. *(New in the notes
  since 2026-08-26; the same §4e-2 measurement method applies — sample `iline`, not the counters.)*
- ~~The copyright symbol is missing.~~ **DONE** — it is a `glyph @` record in `briefing.txt`, the
  shared font having none, and it prints in "© Graftgold Ltd. 1986."
- ~~After exiting the game back to the front end there's a quiet sequence of tones that rise in
  pitch?!~~ **DONE 2026-08-26.** The MOS was playing the charset. `&0800-&08FF` — its sound
  workspace, channel queues and envelopes — sits inside the charset at `&0400-&0C90`, and
  `UninstallIrq` handed the machine back with the queues full of character bitmaps. `GoTitle`
  flushes the buffers first now. [`docs/layer-11e-sound.md`](layer-11e-sound.md) §11

**Niceties**

- Redux bug fixes and feature additions — triaged 2026-08-26; the bug list is adopted as behaviour in `docs/decisions.md` and the six adoptions (droid counts on the console included) are a Features row above.
- ~~Pause~~ — **built 2026-08-26**, P both ways, [`docs/layer-11e-sound.md`](layer-11e-sound.md) §10.
- ~~Volume~~ — **built 2026-08-26**, [`docs/layer-11e-sound.md`](layer-11e-sound.md) §9.
- ~~What's Cheese?~~ **Obsolete** — closed by KC 2026-09-01.
- ~~Redefine keys.~~ **BUILT 2026-08-30** — CTRL+R on the briefing, all six controls, everywhere
  they are read. [`docs/layer-11f-frontend.md`](layer-11f-frontend.md) §8 and [DECISION 15].
- ~~Pressing Z, X, K, M and L together on real hardware triggers C and clears the deck — check
  once the debug flags are off.~~ **ADDRESSED 2026-08-31**, and worth knowing why: the BBC's
  keyboard matrix has no diodes, so five keys held at once can phantom a sixth, and `keydown`
  asking about one key at a time does not save you from it. Every debug key needs CTRL now, so a
  phantom C is not enough to fire one — and a RELEASE build has none of them compiled in at all.
  **Still worth a look on hardware**: a phantom that lands on a *control* rather than a debug key
  is a different matter, and nothing about the redefinition changes it.

**Attention to detail**

- ~~Palette change timing.~~ **CLOSED 2026-09-01**: `palPlay` is applied only at the rupture's
  fire 1 (2026-08-31, the panel-flash fix) and every screen swap now hides its drawing behind
  `PalBlack` / invisible ink — layer-8b §4b–4d.
- TV resync — the rupture-mid-frame hazard row below is the home for this.
- ~~Single-line scroll flicker — move keys off OSBYTE?~~ **DONE 2026-08-26, and the guess in the
  note was right.** `keydown` drives the System VIA matrix directly instead of calling OSBYTE
  `&81`: 243 cycles down to 69, ~2,175 a pass across a dozen keys. KC confirms the flicker is
  gone. [`docs/raster-timing.md`](raster-timing.md)
- ~~Blanking during load.~~ **DONE** — KC's note adds a caveat rather than closing it: it is
  aggressive, and there may be too many black screens.
- ~~Show the screen only after the frame is drawn — return from console, between briefing
  pages~~ — **DONE 2026-09-01, and more**: every full repaint of the deck (info-page dismissal,
  console close, transfer and lift exits, deck loads) plots under a black `palPlay` and is
  revealed complete by `RedrawAll`'s closing `SetPalette`; the lift screen's and console's own
  entry draws hide behind the same `PalBlack`; the briefing's page paints in invisible ink (text
  in the background's colour) and appears in one go. The lift's deck load holds the lift screen
  static across the build, exactly as the C64 does. [`docs/layer-8b-lift-view.md`](layer-8b-lift-view.md)
  §4b–4d is the ledger. The high-score → logo seam was the one not treated, and **KC considers
  it fine as it is (2026-09-01)**.
- The lift commit plays a confirmation chord (`&16`, the mode-change chord) since 2026-09-01 —
  a KC addition, the C64's own exit being silent. Layer-8b §4c.

**Loader**

- ~~SWRAM detection~~ — **built 2026-08-29** as Layer 13b: `PARSWR` probes all sixteen banks
  before the game loads, takes the top four, and refuses a machine it cannot drive.
  [`docs/layer-13-compatibility.md`](layer-13-compatibility.md).
- ~~MODE 7 splash to hide loading?~~ — overtaken by the intro below, which is what the boot now
  shows.
- ~~Robot intro with Chris's music~~ — **built 2026-08-30**. `pdloader/`, vendored verbatim: our
  picture and colourways over his three-channel sample player, ~15.6 kHz a channel, samples in one
  sideways bank. Its data is two ZX0 streams — 33,912 bytes down to 5,451, about 5 s off every
  boot. Six port changes and the two bugs it found are in [`docs/intro.md`](intro.md) §8.
- **Still open:** the silent gap. The music stops at the keypress and the game then loads for
  10.4 s with nothing playing — unavoidable with a player that owns the CPU with interrupts off.
  Accepted by KC 2026-08-29.

