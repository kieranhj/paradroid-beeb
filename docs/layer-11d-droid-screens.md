# Layer 11d — the droid information screens

`NewShipInfo` (`$36B9`), `ShowXferInfo` (`$3734`) and `EndGame`'s hires page (`$37DC`): the four
full-screen pages that show one droid's picture beside a paragraph of the original's own prose.

**Status: all four are built and verified in jsbeeb, 2026-08-21**, and the loop closes — game over,
the wash, the 999 page, the title, a new game, the 001 page.

## 1. The printer was already here

The plan said this layer needed `PrintTokenString` first, and that was out of date. Layer 9's
database page had already ported the whole of it for the droid descriptions:

| C64 | ours | where |
|---|---|---|
| `PrCapitalString` (`$2E1E`) + `ToUpper` (`$2E3D`) | `DbTok` | `condb.asm`, bank 7 |
| the wrap at `$0C19`, the margin at `$0C1D` | `DbTok`'s own | same |
| `ShowRobotType` (`$3149`) | `DbName` | same |
| `BuildIntroSprites` | `PoDraw` / `DbImage` | `portrait.asm` |
| the `$C000` string pool, 248 strings | `constrings` | main RAM, `src/data/strings.asm` |

So `infoscr.asm` is the **loop and the screens**, not a second text engine. `IsPrint` is
`PrintTokenString`'s body and everything under it is `condb.asm`'s. The token strings are the
C64's bytes verbatim from `$6DA0`, `$6DB5` and `$6DBF` — `export_strings.py` translates the
*glyphs* and preserves the numbering, so the sentences come out in the original's words with no
re-authoring.

## 2. Decisions

1. **[DECISION] The geometry is the database page's** (KC, 2026-08-21). Not a convenience: the C64
   puts the name at screen row 10 and steps the content lines 12, 14 ... 22, which is `condb`'s
   seven lines exactly, and `PrintTokenString`'s `prntX` 9 / `prntY` 12 is line 1, column 9. The
   name line, the portrait at unit 4 and the seven text lines are shared with the console's
   database page, which is what the two are on the C64 as well.
2. **[DECISION] The game-over page is built** (KC, 2026-08-21), reversing half of layer-11
   [DECISION 7]. That decision put GAME OVER on the panel line *because the port had no portrait*;
   the portrait landed 2026-08-20, so `EndGame`'s real page — the 999 behind "Transmission" and
   "Terminated" — is back. The wash is unchanged and still ends it.
3. **[DECISION] The dismissal is faithful** (KC, 2026-08-21): fire, or an automatic advance.
   `$371F` counts 72 down over a `ReadJoystick` and a `DelayScore(32)` — two nested busy loops,
   about 41,000 cycles — so the hold is ≈2.9 s and fire cuts it short. At 25 Hz **72 passes is
   2.88 s**, so the count ports across unchanged and lands on the same wall clock by arithmetic
   rather than by luck.
4. **[DECISION] The page comes up before the deck is drawn** (KC, 2026-08-21). `StartGame` reaches
   `$12C7` before `DoNewDeck`, so the C64 shows the 001 screen on an empty screen. Ours does it by
   setting `infoActive` **before** `GameStart`, which makes `LoadDeck`'s own `ReframeView` a no-op
   (there is a guard on `ReframeView` saying so); the deck is drawn when the screen is dismissed,
   by the `ReframeView` in `InfoCall`'s `IS_ACT_GAME` arm. Without it the level appeared, the page
   covered it, and the level came back.
5. **[DECISION] ESCAPE self-destructs and ends the game** (KC, 2026-08-21). **The C64 has no
   equivalent** — its only abort is the RUN/STOP that `DoPause` reads, and that pauses — so this is
   the port's own feature and is recorded as such. It replaces `DEBUG_RESTART`'s R, which threw the
   game away and jumped to `GameStart`; this ends it properly instead, through everything a real
   death runs, which also makes it a stronger test of Layer 11a's boot split than R was.
   - **It kills him as a 001**, whatever he was riding: `CbCheckDeath`'s `$144D` arm already says
     "a captured droid falls back to a 001, a 001 has nothing to fall back on and the game is
     over", so forcing `drType` to 0 alongside `drEnergy` is how *end the game* is spelled in that
     language. Nothing else is added — the explosion, the sound, the wash, the 999 page and the
     title all follow.
   - **It sits BELOW the four modal arms**, unlike the R it replaces. R was above them so a restart
     could be reached from the console, the lift view or the transfer; a player-facing quit wants
     the opposite, because those states have their own way out and a half-finished transfer
     applying its outcome to a player who is already dead is a tangle with no reason to exist.
   - **ESCAPE is made an ordinary key** with `OSBYTE 229, 1` in `GameStartInfo`. Without it the MOS
     raises an escape *condition* on the same press, and the next filing-system call — which is
     `GoTitle`'s own `*LOAD`s, on the way out of the game ESCAPE just ended — fails with Escape.
6. **[DECISION] All four screens, and the wash, take the play area's sixteenth row** (KC,
   2026-08-21), with the ported pages moved down one row onto the C64's own. The full reasoning,
   the single restore point in `ReframeView` and the `t1i3Lo`-is-a-constant economy are in
   `docs/layer-9-hud.md` §6g, because the console family is the larger half of the same change.
   What it means here: `IsStart` sets `T1_I3X` and the `dbLineLo/Hi` shift puts the name line on
   buffer row 1 and the content on 3, 5 … 13 — which is `prntY` 10 and 12 … 22 exactly, so
   [DECISION 1]'s "the same shape line for line" is now the same *rows* as well. `IsOverDraw`'s two
   strings land on rows 1 and 13, and the portrait between them follows `DB_IMG_ROW`. The wash
   needed nothing but the switch: `GoWashRow` has always run X = 0–15, because the C64's fills its
   whole screen area, and the blank at fire 3 was the only thing hiding the last row.
7. **Not deviations, but worth recording:** the transfer's page turn happens *inside* bank 7
   (`IsDone` chains straight into page 2) because that needs no paging and no main-RAM arm; and the
   screens never write the panel, so — unlike the console — there is no `PanelSetup` on the way out.

## 3. Where it lives, and what it cost

| | |
|---|---|
| `src/infoscr.asm` | bank 7, after `condb.asm` and `portrait.asm` — it is built out of their constants |
| `InfoCall` | `lowcode.asm`, the low overlay: the paging and the three continuations |
| `GameStartInfo` | `lowcode2.asm` |
| `infoActive`, `infoAct` | `lowbss.asm`, two bytes |
| the `ReframeView` guard | `main.asm`, six bytes |

**Main RAM was the whole constraint.** `&1100`–`&3000` had 47 bytes free when this started. Three
economies came out of that and all three are load-bearing:

- **`IsEntry` is one door.** A tick and an open share one paged region, because a second pair of
  `PAGEBANK`s cost 16 bytes of main RAM at the time (since RAM pass 5 a pair is two 3-byte
  `JSR`s to the `PgXxx` helpers — which clobber A exactly as the macro does).
- **`infoAct` carries `$FF` for "still up"**, so the shim tests one byte rather than two.
- **The flatten is in bank 7.** `scrollS`, `line`, `bandDo`, `colCount` are main-RAM variables and
  `SetCRTCStart` is main RAM too (that is what `bufcore.asm` exists for), so bank 7 parks the
  scroll itself. `ConsoleOpen` and `XferEnter4` each have their own copy in bank 4; a fourth was
  not affordable.

## 4. Two bugs, both worth remembering

**`PAGEBANK` is `LDA #bank`, so it eats A.** The screen selector was passed in A, arrived as 7,
and every tick redrew screen 6 instead — forever, so the game never started. It goes in **X** now,
and the header on `IsEntry` says why. Anything else passing a parameter through a trampoline in the
low overlay has the same hazard.

**Fire cutting the wait short looks like a bug and is not.** Several test runs "dismissed
instantly" because L was still held from the title, or stuck down in the emulator harness. Test the
screens with something that is not fire: **ESCAPE** self-destructs and takes the whole chain — the
death, the wash, the 999 page, the title, a new game, the 001 screen. (`DEBUG_RESTART`'s R did this
more directly and was removed on 2026-08-21 when ESCAPE replaced it.) The transfer pages have a
shorter route still: poke `xferDroid`.

## 5. How the transfer reaches its two pages

`Capture` calls `ShowXferInfo` before `SubGameSelectSide`, so the pages go **in front of**
`XferEnter`, not inside it. The main loop's `xferDroid` trigger now opens page 1 instead of the
board, and the chain is:

```
  trigger  ->  gather drType[xferDroid] into xfmTgtType   (main RAM: the one
               place bank 4's table is still reachable)
           ->  page 1, the unit you control     (type from pmType)
           ->  page 2, the unit you want        (type from xfmTgtType)   IsDone chains it
           ->  IS_ACT_BOARD -> XferEnter -> XferEnter4 + XfStart
```

Two things fall out of that and both are deliberate. The **player's** type comes from `pmType`,
PanelTick's mirror, rather than from a gather — one fewer thing for main RAM to do. And
`XferEnter4` re-gathers both types a moment later, which is harmless: it is the same read of the
same table, and leaving it alone means Layer 10's entry is untouched.

Verified 2026-08-21 by poking `xferDroid` — the byte the loop tests is the whole trigger, so it is
also the whole test harness. Page 1 showed the 001, page 2 the 296 the poked index pointed at, and
the board came up behind them with the side-select counter running.

**Seen while testing, NOT investigated:** coming back out of a completed transfer leaves a band of
noise along the bottom of the play area — buffer row 15, the one `RedrawAll` does not draw and
`DbClear` does not clear. It looks like the transfer's `t1i3` (which moves fire 3 down a row so the
16th row shows) not being fully undone, which would make it Layer 10's and older than this work,
but that has not been confirmed either way.

## 6. The game over, and the state the wash had to give up

`EndGame` goes hires after the boil and draws the 999 behind two plain strings — `$6E30`
"Transmission" at `prntY` 10 / `prntX` 13, and `$6E3F` "Terminated" at 22 / 14, which are our
lines 0 and 6 with the portrait between them. No tokens and no name line: `$37DC`-`$37FB` calls
neither `ShowRobotType` nor `PrintTokenString`.

**`GoTick7` now clears `overPhase` when it opens the page**, and that is not tidiness. The wash's
arm sits *above* the screen's in the main loop and returns the pass, so with phase 2 still set the
page was drawn and then boiled over again every pass, and `IsTick` never ran — the wash simply
never ended. The C64 has no equivalent state to clear: `$37D9`'s loop just falls out of the bottom.
Anything else that gives the buffer to a screen from inside another modal arm has the same shape of
problem, and the order of the arms in the loop is the thing to check.

`IS_ACT_TITLE` then takes `GoTitle`, which is Layer 11c's path unchanged. Verified end to end:
death, wash, page, title, a new game, and the 001 screen on the new deck.

**The 999 is CENTRED, and that is the original's own doing.** `$37E8`'s `STA loc_0_365E+1` is not a
colour, as this file first guessed — `loc_0_365E` is `BuildIntroSprites`' `LDA #40 / STA SpriteX`,
and EndGame patches the 40 to **160**. Less the C64's first visible column at 24 that is 136 px in,
which puts a 48 px picture exactly in the middle of a 320 px screen; `$36B3` puts 40 back for every
other page. So `PO_DST0` became `poBase`, a variable the caller sets — `DbImage` writes the
database page's, `IsOverDraw` writes `PO_DSTMID` (unit 34 = 136 px). One trap on the way: **`PoDraw`
takes the droid type in A**, and `DbImage` used to fall into it straight off `STA poLastType`; the
two `poBase` stores in between ate the type and the portrait vanished from three of the four pages
until A was reloaded. Same family as the `PAGEBANK` clobber above — a register quietly carrying a
parameter across a fall-through.

## 7. The sound these screens carry

Layer 11e left fx `$B` and `$E`'s "`ShowXferInfo`/ship-announce moments" deliberately unwired,
because their screens did not exist. They exist now, so each screen announces itself the way the
original does — `isSndFor`, posted before the draw:

| screen | fx | the C64 |
|---|---|---|
| 001 | `$B` | `$1282`'s announce (posted for `ShowShipClear`; KC asked for it here too) |
| transfer 1 | `$B` | `$374A` |
| transfer 2 | `$C` | `$376B` |
| game over | `5` | `$37FE`, **with the 999 and not before it** |

**`$1334`'s deck materialise moved out of `GameStart`.** With the 001 screen now standing between
`GameStart` and the deck, posting it there put the alert *before* the screen. `IsDone` posts it
instead, so it lands when the deck does — KC's "the robot sound on the 001 screen before the ship
alert on gameplay start".

**`EndGame` posts exactly two effects, and `GoWashStart` was posting the wrong two.** fx 5 is the
999 page's, and as a triangle held for 128 ticks it sat on the voice so the wash's static never
spoke. And fx `$16` was there on the strength of a mis-attribution in `docs/layer-11e-sound.md` —
"game-over seam `$14E7`" — when `$14E7` is under `_console`, the console-OPENING path. So the
console's chord was announcing the game over, which is what KC heard. Both gone; the wash now posts
`$F` alone, which plays instrument 4 on the SN's noise channel. That table row is corrected.

**Verified from the chip**, not by ear: during the wash CH3 reads `noise=7 vol=3` with all three
tone channels at 15, and on the 999 page CH0 reads `vol=3` with the noise back at 15.

## 8. Still to do

- Verify the two transfer pages in play. The **game-over page is verified** (2026-08-21): ESCAPE →
  explosion → wash → 999 → title → new game → the 001 page, driven in jsbeeb.
- The deck-clear arm (`RunDroids` `$17DC`): `CPY #1`, the 250+250 bonus, `notInDeck`, and the
  cleared-deck repaint agreed on 2026-08-21. `dru_done` has none of it yet.
- `ShowShipClear` and the ship-complete path, deferred by KC on 2026-08-21.
- `DoHighScore`, which the game-over page now runs into.
