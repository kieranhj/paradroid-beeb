# Known defects

Defects found by measurement, with the evidence for each. Fixed entries stay too, marked
**FIXED** in the heading, because they record what was *ruled out* as well as what was wrong —
and the ruled-out list is usually the expensive part to reproduce.

Defects 1–4 were found on 2026-08-10 while verifying the Layer 5 sprite save-geometry change
(`3f69b4d`); all of them predate that commit and reproduce identically on the build before it.
Later entries carry their own date.

Numbering is historical, not an order — 3 sits after 4 because it was added later, and the
sections below are in neither. **The table is the index; read it first.**

| | Defect | Status | |
|---|---|---|---|
| **1** | [`RedrawAll`'s split-row repair has no effect — the oracle disagrees at `line != 0`](#1-redrawalls-split-row-repair-has-no-effect--the-debug-oracle-is-wrong) | **Probably moot** | the split row it describes no longer exists; kept until its own tests are re-run |
| **2** | [Blank scanlines at the top of the window after stopping against a wall](#2-blank-scanlines-inside-the-visible-window-after-stopping-against-a-wall) | **Open** | the view retreats a pixel after the band is computed. Wants retesting |
| **3** | [Top line wrong for one frame when stopping after moving up at speed](#3-top-line-wrong-for-one-frame-when-stopping-after-moving-up-at-full-speed) | **Open** | never instrumented. Retest against the 2026-08-14 wrap fix first |
| **4** | [The player can spawn inside a wall and is then stuck](#4-the-player-can-spawn-inside-a-wall-and-is-then-stuck--fixed-2026-08-15) | **Fixed** 2026-08-15 | waypoint-0 spawn; `CentreOnDeck` deleted |
| **5** | [Player sprite's lower part missing at a doorway](#5-player-sprites-lower-part-missing-at-a-doorway--fixed-2026-08-14) | **Fixed** 2026-08-14 | the interpreted row fell into the walking tail |
| **6** | [The rotor restore leaves pixels behind, at both shifts](#6-the-rotor-restore-leaves-pixels-behind-at-both-shifts--fixed-2026-08-14-same-cause-as-5) | **Fixed** 2026-08-14 | same cause as #5 |
| **7** | [Droids lock together (7a); the player's bounce is heavy (7b)](#7-droids-can-lock-together-and-the-players-bounce-is-heavy--7a-fixed-2026-08-18) | **7a fixed** 2026-08-18, **7b open** | 7a was a missing debounce. What is left is the box SHAPE and the feel |
| **8** | [Droids from the last deck survive into the next one](#8-droids-from-the-last-deck-survive-into-the-next-one--fixed-2026-08-15) | **Fixed** 2026-08-15 |  |
| **9** | [One 4-pixel column is wrong down most of the strip after horizontal scrolling](#9-one-4-pixel-column-is-wrong-down-most-of-the-strip-after-horizontal-scrolling--2026-08-15) | **Open** | 58-62 bytes of 10,240, all in CRTC unit 0. Sprites ruled out; it is in the incremental column draw |
| **10** | [The level is corrupted when a droid's shot kills you](#10-the-level-is-corrupted-when-a-droids-shot-kills-you--fixed-2026-08-16) | **Fixed** 2026-08-16 | a teleport broke `COPYCHAR`'s parity rule |
| **11** | [Enemy lasers crawl, and the player can walk through them](#11-enemy-lasers-crawl-and-the-player-can-walk-through-them--fixed-2026-08-16) | **Fixed** 2026-08-16 | a direction was being read as a distance |
| **12** | [Lasers on screen when a console opens stay drawn over the console text](#12-lasers-on-screen-when-a-console-is-activated-stay-there-and-corrupt-the-console-text--2026-08-16) | **Open** | filed, not investigated. A missing pool teardown on modal entry — same shape as #15 |
| **13** | [The ALERT sign's lamp is dead; it should track the alert level](#13-the-alert-signs-lamp-is-dead--it-should-track-the-alert-level--2026-08-17) | **Fixed** 2026-08-20 | one character rebuilt when `Alert` crosses a threshold, and the sign repainted. The ramp is four *states*, not four colours — [DECISION 11] in `docs/layer-7-combat.md`, **not yet ratified** |
| **14** | [`XfRand` is not a maximal LFSR — its low two bits are always zero](#14-xfrand-is-not-a-maximal-lfsr--its-low-two-bits-are-always-zero--fixed-2026-08-19) | **Fixed** 2026-08-19 |  |
| **15** | [Incremental draw disagrees with `RedrawAll` beside an animating door](#15-incremental-draw-disagrees-with-redrawall-beside-an-animating-door--2026-08-19-unconfirmed) | **Open, unconfirmed** | did not reproduce in five clean runs. Correlates with poking a modal flag, not with the level draw |
| **18** | [`HS_STR_ADDR` was `PN_TABS`](#18-hs_str_addr-was-pn_tabs--fixed-2026-08-21) | **Fixed** 2026-08-21 | Layer 11f. Strings landed on the mirrored droid tables; a runaway `DbStr` then smashed bank 7. Root cause proven by write watch. **`font_end` + 96 is `PN_TABS` — the gap there is 8 bytes, not 104** |
| **17** | [Four debug flags silently push the code image past `&3000`](#17-four-debug-flags-silently-push-the-code-image-past-3000--partly-fixed-2026-08-20) | **Fixed** 2026-08-20, bar one | VSYNC, POS and ENERGY fixed and a `GUARD` added so it can never be silent again. RASTER, DRAW and TIME **fit again** since the raster-timing pass moved the tranche decision into bank 6 (code image 11 B free → 323); none has been run since. Only MAPGUARD still fails, on bank 4 |
| **16** | [Enemy droids draw a black rotor and a WHITE number](#16-enemy-droids-draw-a-black-rotor-and-a-white-number--fixed-2026-08-19) | **Fixed** 2026-08-19 | the wrap fallback blits digits interpreted and never sees `colPix` |

`## Delivered: DEBUG_POS` near the end is not a defect — it is the position bookmark that came out
of #5, kept with the defects because that is where it is looked for.

---

## 17. Four debug flags silently push the code image past `&3000` — **PARTLY FIXED 2026-08-20**

Reported by KC: *"the DEBUG_VSYNC flag no longer works correctly — the player sprite gets corrupted
and the vsync number is not legible."*

### The cause, and why nothing complained

`FONT_ADDR` is `&3000` and the code image runs up to it. `DEBUG_VSYNC` adds 143 bytes —
`DbgFrameCount`, the 16-digit 4x5 font and its ×5 table — and the image had **eleven** bytes spare.

beebasm did not object, and that is the interesting part. `CLEAR FONT_ADDR, ...`, further down
`main.asm`, releases the overwrite guard over **exactly the range an over-long code image spills
into** — so the assembler happily wrote code at `&3000`, `SAVE "PARA"` shipped it, and at run time
two things then happened in order: `*RUN PARA` scribbled the tail over the first bytes of the text
font, and the `*LOAD PARAFNT` a moment later scribbled the font back over the code's tail. A
corrupt player sprite and an unreadable digit is exactly what that looks like.

The only bound in the file was `ASSERT code_end <= SPR_SAVE`, and `SPR_SAVE` is `&3E00` — correct
when the font lived at `&3C00`, and 3,584 bytes too slack since Layer 11 moved it.

**Not caused by the 2026-08-20 features.** On the commit before them `DEBUG_VSYNC` overran by 105
bytes rather than 132; the flag has been broken for as long as the code image has been full.

### The fix

- **`GUARD FONT_ADDR`** before `ORG &1100`, plus `ASSERT code_end <= FONT_ADDR`. KC's suggestion,
  and the right one: `GUARD` fires *during* assembly, at the instruction that crosses the line, so
  it names the routine instead of a total at the end.
- The readouts moved to **bank 6**, in `src/dbgpanel.asm`, beside the panel code they draw over.
  The shims that page it in are in `src/lowcode2.asm`. `DbgEnergyOut` reads `drType` and
  `drEnergy` out of bank 4, so its shim mirrors those into main RAM before it pages.
- `DEBUG_VSYNC`, `DEBUG_POS` and `DEBUG_ENERGY` now each build and run.

### And then it still could not be read — a second, separate fault

With the corruption gone, KC: *"the frame rate text is not legible."* It was being drawn correctly
and was invisible anyway.

All three readouts started at `PANEL_ADDR`, and `PANEL_ADDR` is the top-left corner of the status
box — the **rounded** corner, drawn in the same logical 3 the digits use. A black digit on a black
corner, with the corner's own artwork destroyed underneath it. That is not a regression either:
Layer 9 put a real box there, and before Layer 9 the panel was a placeholder with a blank corner.

Panel row 0 reads `00 00 FF 00 00 00 00 00` for every unit from 3 onwards — the box's top border is
scanline 2 and scanlines 3-7 are clean paper, inside the box and above the text row. Unit 4 is the
first clear of the corner, so `DBG_PANEL_TL` is scanline 3 of unit 4 and all three readouts hang
off it. Verified in jsbeeb: the digit reads `FF 11 FF 88 FF` on paper, the box corner is back to
its own `FF FF CC 88 00 11 11 33`, and `DEBUG_ENERGY` prints `00 40 40 00 00 00000000` in the
clear.

### What is still broken, and it is the RAM and not the debug code

| | |
|---|---|
| `DEBUG_RASTER` | 59 bytes over. Its instrumentation is **inside the interrupt** and cannot move to a bank |
| `DEBUG_DRAW` | 83 bytes over. `DbgSetBg` is called **from inside the blitter**, with a sprite bank paged — it cannot move either |
| `DEBUG_TIME` | 154 bytes over |
| `DEBUG_MAPGUARD` | `MG_COPY` is 1 K and bank 4 has 12 bytes |
| `DEBUG_POS` + `DEBUG_ENERGY` | fits neither: two 20-byte shims and a mirror against `lowcode2`'s 36 free. A shared enter/leave pair — 18 bytes once, 9 each — fixes it |

All five now **fail the build with a message** instead of shipping a corrupt image, and the table
in `main.asm`'s debug header records which is which. They want main-RAM room found first; see the
free-RAM section of [`docs/memory-map.md`](docs/memory-map.md).

---

## 16. Enemy droids draw a black rotor and a WHITE number — **FIXED 2026-08-19**

Reported by KC on the first look at the new sprite colours: *"sometimes the enemy droid numbers
are white not black?"* Intermittent, and only the number block — the rotor above and below it was
correctly black.

### The cause

`SprDrawSlot` has two paths. A sprite that clears the up-front wrap test runs the **compiled**
program, whose pixels come from `colPix` and are therefore coloured. A sprite that does not —
about one in five, the ones whose 21 scanlines straddle the end of the circular strip — runs the
per-row fallback loop, and in that loop **the digit block never opens**: all eight of its rows go
through `SprFetchRow` and are blitted interpreted, one row at a time. `SprFetchRow` reads the
stored artwork out of `drSprData`, which is at **logical 3, white**, and nothing recoloured it.

So a wrapping sprite lost *every* digit row to white while keeping its compiled rotor rows black.
That asymmetry is why it read as "the numbers": a wrapping rotor row falls back too, but only the
rows that actually straddle, and usually none of them do.

### The fix

`SprFetchRow`'s mask loop already has the byte in X while it derives the mask, so the recolour is
`TXA : AND sprColCur : STA sprRowBuf,Y` in the same loop — 11 cycles a byte on a path already
chosen for correctness over speed. `sprColCur` is the right value there because `SprSetColour` runs
at `sd_droid`, ahead of the fallback loop, and leaves it equal to the slot's own colour on both
branches.

Order does not matter, incidentally: `SPR_MASKTAB` folds the low nibble onto the high, so a byte
carries the same opacity whichever plane is left in it and the mask comes out the same either way.

### How it was reproduced, and why that mattered

Waiting for a droid to wander onto a strip boundary is not a test. Patching `LDA sprNoWrap` to
`LDA #0` at the fast-path test forces **every** sprite down the fallback, which makes the defect appear on demand and on every droid. Same deck,
same droid, same frame count: before, a black rotor around a white `329`; after, all black. The
player stayed white throughout, which is the control.

The test site was `&2C48` in the fixed build and `&2C41` before it, but **do not reuse those
numbers** — it is in `sd_droid`, near the end of main RAM, so anything added to `sprite.asm` or
earlier moves it. Find it in the listing as `LDA &12` immediately after `JSR SprSetColour`.

### Not affected

**Effect sprites.** `SprEfDraw` builds its own rows and blits them itself — it never calls
`SprFetchRow` — so bullets and explosions keep their single fixed colour, deliberately. **The
restore path** never looks at a pixel; it replays saved background.

---

## 14. `XfRand` is not a maximal LFSR — its low two bits are always zero — **FIXED 2026-08-19**

Reported by KC from the first play of the game-over screen: **the wash was only visible in the
left-hand column** of the play area, not across the window.

**It looked like a drawing bug and was a random-number bug.** `GoWashRow` picks one of four
patterns per cell with `JSR XfRand : AND #3`, and `XfRand` said this of itself:

> its own copy of the same maximal 8-bit LFSR (taps $B4)

`$B4` is **not** a primitive tap for a left-shifting Galois LFSR. The feedback has to reach bit 0,
and `$B4` = `%10110100` has its low **two** bits clear, so:

- bit 0 of every output is 0 for ever;
- bit 1 is the previous output's bit 0, so it is 0 from the second step on;
- the period is **65**, not 255.

`AND #3` therefore returned 0 almost always and every cell came out pattern 0. The left-hand column
survived because `GoWashTick` stirs the seed once a pass (`EOR overRnd1`), which can put the low
bits back for exactly one cell before the shift clears them again — so the first cell of each
repainted row varied and the other thirty-nine did not.

Simulated from both seeds to be sure:

| tap | period | values from `AND #3` | values from `AND #$F` |
|---|---|---|---|
| `$B4`, as it was | 65 | 0, 1, 2 | 0, 4, 5, 8, 12, 14 |
| `$1D`, `DrRandom`'s | 255 | 0, 1, 2, 3 | all sixteen |

**The fix is one byte**: `EOR #&B4` → `EOR #&1D`, the polynomial `droid.asm` already uses and
documents (x^8 + x^4 + x^3 + x^2 + 1). Two seeds on one polynomial are two independent sequences,
which is all `XfRand` ever needed from being separate.

**It was not only the wash.** Three of `XfRand`'s four other callers mask with `AND #$F`, which
could only ever produce six of sixteen values:

- `XfPutRandom` `$551`: `AND #&F : CMP #3 : BEQ` — **3 was not in the set, so that branch had never
  been taken**, in any transfer game ever played on this port
- `XfPutRandom` `$531`: `AND #&F : CMP #5` — a coarse near-even split instead of a 5-in-16 chance
- `XfGetMove` `$874`: `AND #&F : CLC : ADC #1` — the CPU's target row could only be 1, 5, 9 or 13

So **the transfer board and the CPU opponent were both less varied than the original's**, invisibly,
since Layer 10. Worth a play now that they are not.

**Verified**: the wash covers the whole play area with a mix of all four densities, and the game
still restarts after the hold.

> **Still open, and cosmetic:** the wash draws in logical 1, which the port's fixed slot roles call
> black, and on the deck tested it renders **blue** — so the effect reads as blue static rather than
> the C64's dissolve into darkness (`$37A6` writes colour `$F0`). That is a palette question for
> Layer 14, and it may be that logical 1 is not black on every deck.

---

## 13. The ALERT sign's lamp is dead — it should track the alert level — **FIXED 2026-08-20**

Found while checking the deck colours against the listing, on KC's prompt that the ALERT text
should be legible. The lettering turned out to be faithful (see below); **the lamp is not.**

Character `$16` is the indicator inside the ALERT sign — it appears twice, in row 2 of tile 22,
as the two dots between the letters and the panel. On the C64 its colour is **not** taken from the
deck's colour scheme at all:

```
    InitColors      $2835  LDA Alert / ROL A x3 / AND #3 / TAY
                    $283D  LDA AlertColors,Y
                    $2840  STA CharColor+$16
    DoAlertAndAging $3E38  the same, live, as the alert level changes
```

`AlertColors` (`$6D45`) is `E5 E7 E8 E2` — low nibbles **5 green, 7 yellow, 8 orange, 2 red** — so
the lamp runs green → yellow → orange → red as the ship's alert rises, and `$E8` has bit 3 set, so
at level 2 the lamp is a *multicolour* cell where the others are hires.

**Ours is always black.** `charSlot[$16]` is 14, past the end of the 12-byte record, and both the
exporter and `BuildCharset` clamp an out-of-range slot to colour 0. The clamp is right — the C64
reads past the record there too — but it never applies on the original, because `InitColors`
**overwrites** `CharColor[$16]` immediately afterwards. We reproduce the incidental behaviour and
miss the deliberate one.

**Fixed 2026-08-20**, and it was a behaviour and not a table, exactly as this entry said. The
charset is built once per deck load, so the lamp needs character `$16` rebuilt when `Alert` crosses
a threshold: `BuildLampChar` in `src/lowcode.asm` is `BuildCharset`'s inner loop for one character,
`AnimLamp` decides when, and the same `AnimScan`/`DrawTileCells` machinery the recharge pad's
animation uses repaints the two cells of every ALERT sign in view. `LoadDeck` calls `AnimReset`,
because a rebuilt charset has put the character back on its clamped colour.

**MODE 1 HAS NO FOURTH COLOUR, so the ramp is four states rather than four hues** — black, the
deck's highlight, white, and white blinking. The blink is a deviation and is the only invented
thing in the fix; [DECISION 11] in [`docs/layer-7-combat.md`](docs/layer-7-combat.md) has the
reasoning and the one-line alternative. **KC has not ratified it.**

**The lettering, for the record, is faithful and was checked at the same time.** Characters
`$63`-`$66` sit on slot 7, which carries bit 3 in schemes 0, 2, 5 and 6 — so on decks
0, 3, 5, 6, 9, 12, 13 and 14 the C64 itself draws the hires letterforms through the multicolour
path, at 4 double-width pixels, and the letters thicken and join. All 16 decks contain the sign.
`tools/output/alert_check.png` renders the tile C64-against-BBC for every deck. Making those eight
decks legible means forcing those characters to hires, which is a deliberate deviation from the
original's appearance — **KC's call**, not a bug fix.

---

## 12. Lasers on screen when a console is activated stay there and corrupt the console text — **2026-08-16**

Reported by KC from play. Activate a console while enemy (or player) laser sprites are live on
screen, and the laser sprites remain drawn over the console display, breaking up the text.

**Not investigated — filed only.** The likely shape: the console takes over the screen without
tearing down the sprite pool, so the bullets' already-drawn pixels are left in the buffer, and
whatever restore/draw state they hold is stale against the console's own drawing. Compare with
the entry-path teardown `LoadDeck`/`ReframeView` does — dropping every `sprSaved` and redrawing —
which the console entry may not be doing.

Whether the bullets keep *updating* behind the console (i.e. moving, and writing more pixels) or
are simply frozen where they were is the first thing to establish; it decides between "clear the
pool on console entry" and "also stop the bullet update".

---

## 11. Enemy lasers crawl, and the player can walk through them — **FIXED 2026-08-16**

Reported by KC from play: "the lasers are sometimes very slow moving", and "the lasers don't
always hit the player if they are moving slowly, I can move through them". Both are real and they
are the same bug twice.

### The speed is a DIRECTION, not a distance

`AddBullet` ($34B5) reads `deltaX`/`deltaY` and shifts them down five. Those look like the raw
droid-to-player offset and are not:

1. `LineOfVisibility` ($24AE) differences the two **character** positions — `ptr_12` from
   `GetDroidCharPos`, `plyMapPos` — so the delta is in cells, not pixels;
2. it then calls **`CalcDeltaAdd` ($25AF)**, which doubles both, then adds the originals, until the
   **longer of the two sits in [128, 255]** — a normalised direction vector in 8-bit fixed point;
3. `DoEnemyFire` runs immediately after, in the same `dMd0_droid` arm, so `AddBullet` inherits the
   *scaled* pair.

`>> 5` of that is **4-7 pixels an iteration on the dominant axis, at any range**. Our port had read
the listing without following `deltaX` through `CalcDeltaAdd`, and used the raw **pixel** offset —
so speed was proportional to distance. A droid firing from two characters away produced a speed of
0 or 1, and a droid fires at exactly that range. Hence "very slow", and hence walking through them:
a bullet with both speeds 0 never arrives anywhere.

Two more details of `AddBullet` were missing, both load-bearing:

- **the shift is logical** (`LSR A / ROR`, $34BE) rather than arithmetic, so a negative delta
  rounds the other way;
- **both speeds are negated** at $3560, which is what turns droid-minus-player into a velocity
  *towards* the player.

### The bullet arm must not be debounced

`DoCollision`'s `_ply_droid` arm tests `byte_0_6C` at $1A77 and skips the whole episode if it
matches. **`_ply_bullet` ($1AF1) and `_ply_xplosion` ($1B1A) test nothing.** They do not need to: a
bullet frees its own sprite the instant it lands, so it can only count once, and standing in an
explosion is meant to hurt every pass.

Ours had the debounce in front of all three arms, so a bullet did nothing at all whenever anything
had touched in the previous pass. Worse, `drCollHit` was set on **any** colliding pair, and a bullet
crawling at zero speed sits inside the droid that fired it — so the flag was held down permanently
and the player's own bounce went with it. On the C64 `byte_0_6C` is written in `ReverseDroidDir`
($1C67) and nowhere else, i.e. on a *bump*, so that is where ours sets it now.

### Also corrected: the sprite choice

The chain of subtracts at $353E is not the symmetric rule it looks like. Worked through, on speeds
of 0-7:

```
    |dy| >  |dx|        vertical    the |dx| < |dy| arm always reaches _6,
                                    because the second SBC cannot borrow
    |dx| >= 2 * |dy|    horizontal
    otherwise           diagonal, by the sign of dx EOR dy
```

The vertical band is much wider than the horizontal one. Ours used "twice the other" on both axes
and drew a diagonal through most of it.

### Verified

Live in jsbeeb, deck 1 with `shipLevel` poked to 31 so the droids fire constantly:

| | |
|---|---|
| a spawned bullet's speeds | `drSpdX = +2`, `drSpdY = -7` — dominant 7, as the model predicts |
| `drEnergy[0]` from 64 over 75 passes | **down to 15** — six hits at 8 apiece, against ~0-1 from aging |

`DrScaleDelta` is now shared by `DrLineOfSight` and `DrAddBullet`, which is the same sharing the
C64 gets for free by leaving the vector in `deltaX`/`deltaY`. Ours has to recompute it because it
tests one sight line a pass rather than all six, so the pair in hand belongs to another droid.

## 10. The level is corrupted when a droid's shot kills you — **FIXED 2026-08-16**

> **[`docs/bug-map-corruption.md`](docs/bug-map-corruption.md) is the working document.** It is
> named for the wrong hypothesis: the tile map was never the thing being written.

Reported by KC from play, on **deck 8**, meeting a droid that fires: the laser sprite is left on
screen and the level goes wrong. Two later sessions sharpened it decisively — the corruption
**survived a deck hop to deck 7**, and individual **tile characters** turned into 4×4 blocks of red
vertical lines. That is not the tile map. It is the CHARSET SOURCE, which lives at `&8000` in
SWRAM bank 4 and which `BuildCharset` re-reads on every deck load.

### The cause

`CbCheckDeath` respawns the player with `DrSpawnPoint` + `SetPosFromWaypoint`, and stops there.
`SetPosFromWaypoint` ends in `SetMapFromPos`, which **assigns `mapHX` outright**. `scrollS` does not
follow it — the incremental scroll keeps the two in step by adding the same delta to both, and there
is no delta here.

`COPYCHAR` in `scroll.asm` depends on exactly that link. Its 16-byte run writes a character's two
halves in one go, which is only safe while the strip's wrap falls on a character boundary, i.e. while

```
    scrollS/8 == mapHX   (mod 2)
```

The teleport flips that parity whenever the spawn's `mapHX` parity differs from the view's, and the
band draw then writes its second half **8 bytes past `&8000`** — into whichever sideways bank is
paged, which during the level draw is `SWRAM_DATA`. Bank 4 begins with `chardata`, then `colours`, then `tiledefs`: precisely the tile
characters and the tile layout, in that order, and both of them re-read from the bank on every
subsequent deck load. `COPYCHAR`'s own header names this failure mode; nothing had ever violated it
before Layer 7f gave the player a way to be teleported mid-deck.

The stuck laser and the wrong-looking level are the same event: no `RedrawAll` and no `sprSaved`
clear, so the buffer still holds the old view and every slot's saved background belongs to it.

### The fix

`LoadDeck`'s re-framing block is now `ReframeView` in `main.asm` — scrollS parity from `mapHX`,
`line`/`iline` zeroed, `bandDo`/`colCount` cleared, every `sprSaved` dropped, `SetCRTCStart`,
`RedrawAll` — and `CbCheckDeath` tail-calls it. **Any teleport must go through it.**

### Why the guard read zero

`DEBUG_MAPGUARD` was right and the hypothesis it was built for was wrong: the tile map at
`&3800-&3BFF` is never written. The guard reported `hit = 00` through a live reproduction, which is
the result that pointed at the bank. It is verified in both directions (it fires correctly on a
poked byte, and does not false-positive on a clean boot) and is worth keeping for the next scribble.

### Superseded suspicion

The save areas ending exactly at the map (`&3000-&37FF`, map at `&3800`) was the leading theory and
is not implicated. It remains true and remains tight, so the `ASSERT` stays.

## 9. One 4-pixel column is wrong down most of the strip after horizontal scrolling — **2026-08-15**

Found while verifying Layer 7d, and it has **nothing to do with Layer 7**. Scroll horizontally for
a while, stop, let the view settle, and the play buffer no longer matches `RedrawAll`.

**With every sprite disabled and the droids removed, so the level draw is the only thing writing
the buffer: 58–62 of 10240 bytes differ**, depending on where you stop.

**It is all in CRTC unit 0 — the leftmost 4-pixel column of the view** — and it runs down almost
every one of the 16 rows. Nothing else in the buffer is touched.

### The column is displaced DOWN by one character row

Rendering unit 0 against `RedrawAll`, scrolling left, `scrollS = $0218`, `line = 4`:

```
          incremental   RedrawAll
  row 1.3    ....         ####     <-- WRONG
  row 2.3    ####         ....     <-- WRONG     the same #### one row lower

  row 4.3    ....         ****     <-- WRONG
  row 5.3    ****         ....     <-- WRONG     the same **** one row lower

  row 9.3    ....         ####     <-- WRONG
  row 10.3   ####         ....     <-- WRONG
```

and rows 5–8's vertical white line appears at rows 6–9. Every feature lands exactly one character
row too low, so this is **an off-by-one in the row origin of the newly-exposed column**, not
scattered damage and not a timing tear — a tear would leave the buffer correct and only look wrong
for a frame, and this survives 1.6 M cycles of settling.

**`line` was 4, i.e. non-zero.** CLAUDE.md's standing warning is that every scrolling bug so far
has hidden in non-zero `line`, odd/even `mapHX`, or a diagonal, and this fits the first. `DrawColumn`'s
starting map row is the place to look; the vertical scroll offset is the thing it is most likely
not to be accounting for.

> **2026-08-19, and it may not be unit 0 that matters.** Layer 13a's TASK 7 verification turned up
> the same *shape* at **unit 22**: 30 bytes, one column, but only in rows 0, 1, 14 and 15 — the
> buffer's wrap rows — after a **diagonal** scroll. It did not reproduce on the next sample from the
> same boot, and the change it was testing touches neither the level draw nor the scroll. If it is
> the same defect then the column at fault is *whichever one was newly exposed*, and unit 0 is
> simply where a purely horizontal scroll always leaves it. Worth testing that way round.

It is a **4-pixel column at the very edge of the play area, so it is close to invisible on screen**
— which is why it went unnoticed and why it needs the byte oracle rather than a screenshot.

### How it was found, and what is ruled out

| | |
|---|---|
| Player + droids + firing | 68–122 bytes — **contaminated**, see the note below |
| Droids removed (`drCount = 1`), player firing while scrolling | 81 bytes |
| Droids removed, player scrolling, **not** firing | 123 bytes |
| **No sprites drawn at all, no droids, scrolling** | **62 bytes** |

The last row is the one that matters: with nothing but `DoRedraws` touching the buffer the defect
is still there, so **sprites, the effect blitter, the eighth slot and the player's bullet are all
ruled out**. It is in the incremental column draw.

> **Zeroing `sprActive` is NOT enough to quiesce the pool for an oracle run.** `DrScreen`
> re-activates a droid's slot every pass from `drSlotOwner`, so the droids come straight back and
> their sprites show up as differences. That is what the 122-byte reading was. Set `drCount = 1`
> as well — or poke the three draw call sites to NOPs, which is what `docs/raster-timing.md` says
> and which does not depend on knowing that.

### Not yet established

Whether this predates Layer 7 entirely. It is independent of everything Layer 7 added, but the
build before Layer 7a has not been run against the same test — that is the first thing to do, and
it is cheap.

Whether the same displacement appears on the RIGHT edge when scrolling the other way. Only a
leftward scroll was rendered column by column; a rightward one also fails the oracle, but its
column was not identified.

## 8. Droids from the LAST deck survive into the next one — **FIXED 2026-08-15**

Reported by KC from play as "a couple of droids stuck in the wall", then refined to *stuck on a
wall rather than in one*, on **deck 8, two 247s**. The refinement is what cracked it: a duplicate
droid number is a ghost, not a pathfinding failure.

**The fault.** `DroidsInit` walks the ship roster and, at an index where the roster holds nothing,
skipped the table entry entirely — leaving the **previous deck's droid** in it: its type, its
energy and its position. `drCount` is then set to the whole table on the stated assumption that a
hole has zero energy so `DroidsUpdate`'s compaction drops it. A hole did not have zero energy. So
every deck after the first inherited the last one's droids, standing at the last one's coordinates
inside the new deck's geometry.

**Why it hid.** The table starts zeroed, so the **first deck entered is always clean** and only the
second one shows it — and every unattended test in Layer 5 and Layer 6 ran on deck 1 from a cold
boot. It was invisible to the whole verification suite by construction.

**The evidence that identified it.** On deck 8, four of the stuck droids stood on cells at rows 6,
18 and 26. Deck 8 has no waypoints on those rows. **Deck 1 does** — (54,6), (86,26), (98,18) are
deck 1 waypoints exactly. They had never moved since deck 1 placed them there.

**The fix** is four instructions on the skip path: zero `drEnergy`, `drType` and `drSprNum` for an
empty index, so the hole really is one. The comment on `drCount` is now true rather than aspirational.

**Measured, deck 8, same route from a cold boot:**

| | before | after |
|---|---|---|
| `drCount` (deck 8 holds 6 droids) | 14 | **7** — 6 placed, plus the sentinel |
| droids stuck over 10 s | 8 of 13 | **2 of 6**, and both explained: one mid-collision-pause, one oscillating between two waypoints |
| droids standing on a **solid** cell | 4 | **0** |
| droids on deck 1's waypoint rows | 4 | **0** |

Deck 2, which holds 3, now gives exactly 2 droids where it previously inherited two decks' worth.
The buffer oracle is still 0 of 10240 with the draw disabled.

> **The lesson worth keeping is about the test, not the code.** Every automated check ran on deck 1
> from a cold boot, and this bug cannot exist there. **Enter a second deck** before believing any
> droid result — and the debug deck hop (poke `deck`, press DOWN) makes that two tool calls.

---

## 7. Droids can lock together, and the player's bounce is heavy — **7a FIXED 2026-08-18**

Both reported by KC on 2026-08-15, from playing the Layer 6 build. Filed together because they are
the same three constants seen from two directions, and neither is a correctness fault: the buffer
oracle is clean and the frame lock holds. **This is tuning, and it should be done by eye in one
sitting rather than reasoned about here.**

### 7a. Two droids can stay stuck against each other — **FIXED 2026-08-18**

**Severity:** was filed as polish; it was a defect. Makes the ship harder to explore than it should
be, which is the actual complaint — the droids get in the way.

> **THE CAUSE: our droid-droid reverse was never debounced.** `ReverseDroidDir` (`$1C5F`) carries
> the `byte_0_6C` guard *inside itself*, tested at `$1C63` before it touches the speeds, and both
> C64 call sites reach it — `DoCollision2`'s `_08_1` (`$1BA6`) as well as `_ply_droid` (`$1A82`).
> `DrReverse` left the guard out on a note that both call sites had already made the test. Only
> `dc_player` had. So while two droids overlapped, the outer one reversed **every pass** — jittering
> on the spot with no net drift — while `DrPause16` renewed the inner one's 16 under it every pass
> so it never got to walk away. A permanent lock.
>
> Second half of the same fault: `byte_0_6C` is cleared at `_x_none` (`$1A3E`) alone, the exit taken
> when no colliding pair was found *at all*. Ours cleared it at the top of every pass and re-latched
> from `DrReverse`, so a suppressed pass re-armed the reverse for the pass after — half-rate
> oscillation, still stuck. Both halves are fixed: the guard is back inside `DrReverse`, and
> `drCollWas` is gone in favour of one persistent `drCollHit` cleared where the C64 clears it.
>
> **Measured, A/B, in jsbeeb.** Two droids held overlapping (slots 5 and 6, `|dx|` = 8, `|dy|` = 0),
> stepped a pass at a time, reading `drSpdX` at a breakpoint on `DrCollide`:
>
> | pass | before (HEAD) | after |
> |---|---|---|
> | 1 | `+1` → `-1` | `+1` → `-1` |
> | 2 | `-1` → `+1` | `-1` |
> | 3 | `+1` → `-1` | `-1` |
>
> and once the pair is separated, `drCollHit` returns to 0, so the next episode reverses again.
> Full write-up, including why the C64's latch is a *tag* and not a boolean, in
> [`docs/layer-6-droids-live.md`](docs/layer-6-droids-live.md) § "Collision fidelity".
>
> **What is left of #7a** is the box shape, not the debounce: `DR_COL_W`/`DR_COL_H` (18 x 14) fire
> at diagonal offsets like (17, 13) where two 24-wide droids are visibly clear, and those are the
> offsets a single reverse is least likely to escape. The agreed replacement is a generated
> minimum-`|dx|`-per-`|dy|` profile — **[DECISION 1]** in the same document. Not yet built.

**Why it can happen, from the code rather than from a repro.** Four properties of the original's
structure combine, and all four are ports rather than choices of ours:

1. **One pair a pass.** `DoCollision` resolves the two lowest set bits of `$D01E` and leaves the
   rest; ours stops at the first overlapping pair. A pile-up of three unwinds one pair at a time.
2. **`PauseDroidFor16` freezes the second droid for 16 iterations** — nearly a second at 25 Hz —
   and a frozen droid cannot move out of the way of the one that hit it.
3. **The reverse fires once per episode**, not once per pass: `ReverseDroidDir`'s `byte_0_6C` guard
   is only cleared on a pass with *no* collision at all. If the one reverse does not separate them,
   nothing reverses them again while they stay overlapped.
4. **Droids only change direction at waypoints.** A reversed droid walks back the way it came until
   the previous junction; it cannot route around anything.

~~**KC believes the C64 original does this too, which is consistent with 1–4 being inherited — but
that has NOT been verified here.**~~ **Answered by the listing, not by a C64 run: it is a port
artefact.** Points 1, 2 and 4 above are faithful and harmless on their own; point 3 was the one we
had not actually implemented, and it is what holds the other three together.

**The port-specific suspect, if it turns out we are worse:** our collision is a box and the C64's is
the VIC's pixel-exact `$D01E`. `DR_COL_W`/`DR_COL_H` (18 × 14) fire on overlaps the hardware would
not see at all, so droids "touch" earlier, more often, and at distances where a single reverse is
less likely to clear the overlap. Shrinking the box is the cheapest experiment.

**Levers, cheapest first:** `DR_COL_W`/`DR_COL_H` in `droid.asm`; the 16 in `DrPause16`; resolving
more than one pair a pass; clearing `drCollHit` when the pair *changes* rather than only when the
screen is clear.

### 7b. The player's bounce is aggressive

**Severity:** polish, gameplay feel.

**And it is already smaller than the original's.** `$1A85` negates the whole-pixel part of each
player speed, forces it to at least 1, and doubles it, with no ceiling — so the C64 can bounce the
player at 14 px an iteration. Ours clamps to `CAM_TOPSPD` = 8, because the band redraw brings in one
character row a pass and 16 px would skip one (see `docs/layer-6-droids-live.md`). One pass is one
C64 iteration here, so those are directly comparable numbers: **we are already the gentler of the
two.**

**So the feel probably is not the speed, and the first place to look is the camera.** A bounce that
pushes the player past the edge of the dead zone moves the *view*, and the view moves in 4-pixel
CRTC units. A nudge that would be a few pixels of sprite movement on the C64 can therefore lurch the
whole world sideways in one step here. That is a port-specific amplifier that has nothing to do with
the collision constants, and it would explain "aggressive" better than a speed that is 8 against 14.

**Cheap experiments, in order:** drop the doubling (`ASL A` in `DrBounce`) and see whether it still
reads as a bounce; clamp to 4 rather than `CAM_TOPSPD`; and check whether the same bounce with the
player away from the dead-zone edge feels different, which would confirm the camera as the cause.

**Not to be changed without noticing:** `DrBounce` leaves the speed *fraction* alone, as the C64
does, so a bounce inherits whatever sub-pixel remainder the player had.

---

## 1. `RedrawAll`'s split-row repair has no effect — the debug oracle is wrong

> **Probably moot as of 2026-08-13, not fixed.** The band now draws whole character rows, so no
> display row aliases two map rows, and both repair passes — `RedrawAll`'s and `DrawColumn`'s —
> were deleted along with `DrawHalfPart`. `RedrawAll` is now sixteen whole rows from `mapYr`, which
> *is* the strip's invariant, and it diffed byte-identical against incremental scrolling at
> `line` = 1, 3 and 4. The contradiction below was never resolved, so this entry stays until
> someone re-runs its own tests and confirms there is nothing left to explain.

**Severity:** does not affect the game. Affects verification only — but it affects *every*
layer's verification, which is why it is first.

**Symptom.** Diffing the play buffer against a SPACE-forced `RedrawAll` reports differences
whenever `line != 0`. They are always in the same place: display row 0, scanlines
`0..line-1` — the split character row.

**Who is wrong.** `RedrawAll`. The incremental scrolling is correct.

**Evidence.**

| Test | Result |
|---|---|
| `line == 0`, whole 10 K buffer | Incremental is **byte-identical** to `RedrawAll` — the band logic is sound |
| `line == 6` (`posY=94, mapYr=11`) | Exactly 6 scanlines differ, at display row 0 scans 0–5 |
| Repair reached? | **Yes** — a sentinel poked into `bandRun` was overwritten with `line` |
| Repair's output, `line == 2` | Display row 0 holds **69 non-blank cells, 0 splits** — every cell is one whole charset character |

That last one is the decisive, reference-free test. `RedrawAll` draws whole character rows
from `mapYr`, then the repair is supposed to overwrite scanlines `0..line-1` with character
row `mapYr+16`. If it worked, those cells would be a *split* of two different characters.
None of them is. The row is left entirely as character row `mapYr`.

The content is genuinely distinguishable — tilemap rows 2 and 6 (the tile rows behind
character rows 11 and 27) differ at several columns (`08`/`07`, `15`/`16`, …), so this is
not two rows that happen to render the same.

**Why the split row needs a repair at all.** The strip holds absolute rows
`[posY, posY+128)` and `posY = mapYr*8 + line`. Display row 0 scanline *s* therefore holds
map row `mapYr*8 + s` when `s >= line`, but `mapYr*8 + 128 + s` — character row
`mapYr+16` — when `s < line`. `LoadDeck` sidesteps this by zeroing `line` and `scrollS`
before its own `RedrawAll`; the SPACE debug key does not.

**Ruled out.**

- Not the parameters. `cellY = mapYr+16`, `bandScan = 0`, `bandRun = line`, `rCount = 0`
  are all correct in the assembled listing (`LDA &86 / ADC #&10 / STA &87 / JSR &1926`)
  and at runtime.
- Not the call target. `&1926` is `DrawBandRows`.
- Not `BandSetRow`'s arithmetic. `(tileRow AND 3)*64 + (tileRow>>2)*256` does equal
  `tileRow*64`, and it reads `&87`.
- Not placement by `SetCell`: `rCount = 0` gives `BUF_BASE + scrollS`, which is display
  row 0.
- Not overwritten afterwards — the repair is the last thing `RedrawAll` does, and nothing
  between it and the next frame's redraw touches that region.

So it executes, with correct inputs, through code that reads the addresses it should, and
produces the wrong character row. That contradiction is unresolved.

**Next step.** Separate *"wrote the wrong content"* from *"wrote to the wrong address"*:
poke a distinctive sentinel into the buffer at display row 0 scan 0, force the redraw, and
see whether the repair overwrites it. That is the fork the code reading could not close.

**Note for whoever picks this up:** jsbeeb breakpoints did not fire in any of these
sessions — not even on the main loop — so execution could not be traced. Memory sentinels
were the workaround and worked well.

---

## 2. Blank scanlines inside the visible window after stopping against a wall

**Severity:** visible, small.

**Symptom.** After scrolling **down** at speed and stopping against a wall
(`posY = 169`, `ySpd = 0`, `line = 1`), the buffer held **blank** scanlines at display row 0
scans 1 and 2. With `line = 1` the display starts at scan 1, so those are the top two
visible pixel rows, and they should hold in-window map rows 169–170.

Only scan 0 is a legitimate split-row scanline at `line = 1`, so this is *not* defect 1 —
scans 1 and 2 come from the main loop's reliable path.

**What it looks like.** The affected rows are mostly background, so the cost is a few
pixels of grid line missing from the top scanline. Easy to miss.

**Ruled out.**

- Not the map clamp. `MAX_PX_Y = 384`; the view stopped at 169 against a *wall*, nowhere
  near the limit.
- Not `ClampY` ordering — the band is computed from the post-`ClampY` `posY`.
- Not `CheckWalls` — it runs before `ApplyMove` and only zeroes the speed.

**Lead.** Stepping frame by frame, the view ran 167 → 168 → **170** → settled at **169**.
It moved *backwards* by a pixel. The band drawn while it read 170 covered rows 296–297;
the settled window `[169, 297)` excludes 297, leaving that scanline holding the strip's
blank bottom edge. Whatever retreats the view by one pixel after the band has been
computed is the thing to find.

---

## 4. The player can spawn inside a wall, and is then stuck — **FIXED 2026-08-15**

**Fixed exactly as the entry below predicted**, in Layer 5's droid work: the player arrives on
**waypoint 0** of the deck and `CentreOnDeck` is deleted. `SetPosFromWaypoint` (`player.asm`)
works backwards from the reference cell, so the cell the wall probes test is the waypoint itself.

Checked over the whole game rather than by sampling decks: `tools/rip_levels.py`'s RLE decoder
reproduces the port's tile map byte-for-byte, so the same decode answers it for all sixteen at
once — **0 of the 239 waypoints is in a wall, waypoint 0 included on every deck.** In the emulator,
the two decks named below now walk freely from the spawn: deck 5 moves 233 px right, deck 14 moves
364 px down. `TD_DECK` is gone with `droidtest.asm`.

See [`docs/layer-5-droids.md`](docs/layer-5-droids.md). Everything below is the evidence as it was
gathered.

**Severity:** blocks play on the affected decks.

**Symptom.** On some decks the player cannot move at all after `LoadDeck` — holding a direction
for 46 game-loop iterations moves `plyX` by 2 pixels and then nothing. Confirmed on **decks 5 and
14**; deck 1 is fine.

**Cause.** `CentreOnDeck` (`src/level.asm`) picks the view from the **centroid of the deck's
non-zero tiles**, and `SetPosFromMap` then drops the player at `posX + PLY_HOME_X`, `posY + PLY_Y`.
Nothing in that chain asks whether the resulting cell is walkable. On a deck whose tiles happen to
average out onto a wall — or onto a region the deck does not actually cover — the player lands
solid and `CheckWalls` zeroes the speed on every axis, every iteration.

**Ruled out.** Not the sprite pool: with `TestDroidsUpdate` NOPed out and slots 1-6 cleared, the
player is still stuck. Not a Layer 5 regression either — it is a property of `CentreOnDeck`, which
has not changed since Layer 3.

**The fix is already known and written down.** `tools/export_droids.py` records that **waypoint 0
of each deck is never used by `InitDeckDroids`** and is there to be the player's spawn point when
changing deck. Waypoints are walkable by construction, since droids patrol between them. Spawning
on waypoint 0 and centring the view on that replaces the centroid guess entirely, and the waypoint
data is already exported (`wpData`, `wpOfsLo/Hi`, `wpCount`). This belongs with the droid-state
work rather than the blitter.

~~**Workaround meanwhile:** `TD_DECK = 1` in `main.asm`.~~ **Gone** — `TD_DECK` went with
`droidtest.asm` when the fix landed, as the note at the top of this entry says. Left struck through
because the rest of this section is the evidence as it was gathered.

---

## 3. Top line wrong for one frame when stopping after moving up at full speed

**Severity:** visible, transient.

**Symptom** (reported from play, not yet instrumented): moving **upwards** at full speed
and then stopping, the top line of the play window is briefly incorrect — for a single
frame, then it corrects itself.

> **Retest this against the 2026-08-14 wrap fix first.** Defects 5 and 6 were both the
> interpreted row falling into the non-walking tail, and this entry has never been
> instrumented. A one-frame wrong top line is not obviously the same thing, but it costs one
> run to find out and the fix landed after this was last seen.

**Why it is probably not #2.** Opposite direction, and self-correcting. A buffer-content
error persists; this does not.

**Leading hypothesis: a raster race, not a logic error.** `SetCRTCStart` deliberately runs
*before* `DoRedraws`, and the IRQ latches the new start address at frame row 3. Moving up,
the newly exposed band is at the *top* of the strip — the part the raster reaches first. At
7 px/frame that is a 7-scanline band which must be drawn before the beam arrives. If the
band loses that race the display shows one frame of stale pixels, and the next frame is
clean. That matches the symptom exactly, including why it needs full speed to show.

If that is right, it belongs with the flicker work — it is the same class of problem as
the sprite tearing, and the same fix (ordering work against the raster) addresses both.

> Note the same hypothesis was raised for defect 5 and **rejected** there. That does not settle
> this one — different symptom, different direction, and this entry has never been instrumented —
> but do not treat "buffer correct, display wrong" as automatically meaning a raster race.

**Next step.** Reproduce headless: hold up at full speed, release, and dump the buffer on
consecutive frames. If the *buffer* is correct on the frame that looks wrong, it is a race
and not a content bug, which settles it immediately.

---

## 5. Player sprite's lower part missing at a doorway — **FIXED 2026-08-14**

**The interpreted row fell into the wrong tail.** `sd_slow` ends by putting `bufp` back to the
row's first column — so it has *not* advanced a scanline — and then ran straight into `sd_nextnw`,
the tail for rows that walked themselves. Every row after the first wrapping one was therefore
drawn on top of it. `sr_slow` had the same fall-through. One `JMP sd_next` and one `JMP sr_next`.

The two tails arrived when the compiled rows took over their own walking; the comment above them
even says "blank rows and the interpreted paths do not" advance, which is exactly the case that was
then left falling into the wrong one.

**Why it looked like a doorway bug.** A row only takes the interpreted path when its seven columns
straddle the end of the circular strip, which depends on `scrollS` — so it fires at particular
scroll offsets, which for a given route are the same map positions every time. Doors were a red
herring: KC's sightings were near doors because that is where you stop and look.

**Why the oracle never saw it.** The restore mirrored the fault exactly: it collapsed the same rows
onto the same scanlines it had drawn them at, so the background came back correctly. Diffing the
buffer against `RedrawAll` with the draw disabled therefore reported 0 differences for weeks. The
symptom was only ever in the *drawn* sprite, and every check we had disabled the draw.

**Reproduced and verified deterministically.** With the player at unit 37, `line` 0 and
`scrollS` = &17B0, seven of the sprite's 21 rows straddle the wrap. Before the fix the droid is a
one-row streak; after it, at the identical position, it draws in full.

> KC found it: "it's definitely at the wrap around point — if I poke zeros into RAM at &5800 and
> just below &8000 I can erase the smeared pixels." Pixels at *both* ends of the strip is the
> signature of a sprite whose rows are landing across the wrap, and that pointed straight at the
> interpreted path.

**Defect 6 may be the same root cause** — its debris was in rotor rows, at positions that varied,
and it survived a frozen rotor phase. It has not been re-tested since this fix. Do that before
spending anything else on it.

## 6. The rotor restore leaves pixels behind, at both shifts — **FIXED 2026-08-14, same cause as 5**

Closed by the `sd_slow`/`sr_slow` tail fix. The debris was the same collapsed rows: a sprite whose
row straddled the strip wrap drew its remaining rows on top of one another, and the leftovers that
showed up in a restore-only buffer were those rows sitting where nothing expected them. Everything
below is the evidence as it was gathered, kept because the ruled-out list cost more than the fix.

The two facts that pointed away from the real cause, for the record:

- **"It survives freezing the rotor phase."** True, and irrelevant — the fault is in the row walk,
  not the artwork, so the phase never mattered.
- **"A single sprite is clean, 0 of 10240."** True at the position tested, and misleading: that
  position had no row crossing the wrap. Sprite *count* was never the variable; scroll offset was.

The lesson worth keeping: both of those were sound measurements that supported a wrong conclusion,
because the thing being varied was not the thing that mattered. `DEBUG_POS` now prints `scrollS`
precisely so the variable that does matter is visible.

Found 2026-08-14 while verifying the glyph-spill fix, which is **not** its cause — see below.

**Severity:** visible as flicker/debris, transient. Probably the same thing as #3, and probably
what the raster-ordered sprite updating item in `PLAN.md` is really about.

**Symptom.** With `JSR SprDrawAll` poked to `RTS` so the pool only restores, the play buffer
differed from a SPACE-forced `RedrawAll` in **24 bytes of 10240**, all of them extra lit pixels
that the restore did not put back.

**Where they were.** Mapping every differing byte onto the seven slots' 21 × 7 footprints:

| slot | shift | sprite rows affected |
|---|---|---|
| 0 | 1 | 0, 1, 2, 4, 15, 17, 18, 19 |
| 1 | 0 | 18, 19 |
| 3 | 0 | 18, 19 |
| 4 | 0 | 0, 1 |
| 5 | 1 | 0, 1 |

**Every one is a rotor row, and rows 0, 1, 18 and 19 dominate.** Not one is in the digit block
(rows 6–13), and four of the five affected slots are at shift 0.

> **The phase hypothesis below is REFUTED, 2026-08-14.** Freezing the rotor — `SprAnimateAll` poked
> to `RTS`, so the draw and the restore see the same phase — still leaves 24 bytes. Whatever this is,
> it is not the phase advancing between the two. The same runs also showed the count varying with
> the player's position in one build (0, 6, 24 and 39 at four positions), so position, not phase, is
> the thing to vary when reproducing it. Everything below is kept because the row mapping is still
> good evidence.

**Leading hypothesis (refuted — see above): the end rows are restored under the wrong phase.** Rows 0/1/18/19 come from
two-entry tables indexed by `phase >> 2`, and the restore's column list is generated per
`(shift, phase >> 2)` — `drRHalf<shift>_<arr>_<half>`. The restore runs a frame after the draw, by
which time the phase has advanced; `sprTabBaseS` exists precisely to carry the draw's phase across,
so the question is whether the *halves* dispatch honours it or re-reads the current phase. Rows 2,
4, 15 and 17 on slot 0 are the same rows under the other half of the same table, which fits.

**Ruled out as the cause: the 2026-08-14 glyph-spill fix.** That change touches the digit block
only — the glyph code, `SprDigitBlock`'s draw order and `SprBlkRest`'s column count, all of which
address rows 6–13. Those rows show zero differences here, and the defect appears on shift-0 slots
where no spill exists at all.

**A single sprite is clean — 2026-08-14.** With the test droids deactivated and `TestDroidsUpdate`
NOPed, the player alone restores byte-exactly: **0 of 10240**. So this needs more than one sprite on
screen, or a position only reachable with them there. The save areas are not the mechanism either:
the worst case is 223 bytes of the 256-byte page (`scan0` = 7, three character-row crossings), and
`SprCalcAddr`'s no-wrap test covers the furthest byte a sprite touches — `bufp + 1964` against a
threshold of `bufp + 1968`, safe by four bytes and worth knowing.

**And see the oracle warning on defect 5**, which applies here too: if this turns out to be
door-shaped, the diff that found it is measuring the wrong thing.

**Next step.** Read the restore dispatch for the end rows against `sprTabBaseS`, then reproduce
with `DEBUG_POS` at a location KC has actually seen it, rather than hunting positions blind.

---

## Delivered: DEBUG_POS, the position bookmark

Asked for 2026-08-14 alongside defect 5, built the same day once the level draw moved into bank 4
and freed the main RAM it was waiting on.

`DEBUG_POS` in `main.asm` prints, as hex along the top of the panel and rewritten every pass:

```
deck  plyX  posX  posY  mapHX  mapYr  line  numDoors  d0 col/row/state  d1 col/row/state
 01   0264  01D0  0050   0074   0A     00      00        00 00 00          00 00 00
```

Read it off the screen or a screenshot and poke the values back to return to a spot in one step.
Verified against RAM: the panel and zero page agree.

**Not compatible with `DEBUG_VSYNC`** — both write the top-left digit. `DbgPosOut` is in
`rupture.asm` and borrows `swSrc`/`swDst`.

> **Corrected 2026-08-19.** This used to say those two are "dead from `LoadDeck` onwards", and they
> are not: `panel.asm` aliases them as `pnSrc`/`pnDst` for every string it prints, and `droid.asm`
> takes them as `mgSrc`/`mgRef` under `DEBUG_MAPGUARD`. It is safe anyway, but for a different
> reason — **all of them are transient scratch inside one routine, and `DbgPosOut` is called from
> the main loop (`main.asm`), not from the IRQ**, so no two uses can interleave. Anything that
> wants to hold a value in them ACROSS a call would break, and the old wording invited exactly
> that.

If you would rather read RAM directly: `deck` &8B, `plyX` &2B, `posX` &27, `posY` &29, `mapHX` &80,
`mapYr` &86, `line` &24, `scrollS` &7E, `plyCX` &35, `plyCY` &37 (all zero page, 16-bit except
`deck`, `mapYr` and `line`); `numDoors` &24B7, `doorCol` &249B, `doorRow` &24A2, `doorState` &24A9,
`doorDirty` &24B0, `tilemap` &4600; and in bank 4, which is the resting state, `doorDef` &A48D and
`tiledefs` &8800.

> **Take them from a fresh label dump after any build — they move, and every one of these had.**
> Checked 2026-08-19: the zero page addresses were all still right, and **every non-zero-page one
> was stale** — the five door variables by &63A, `doorDef` by &192, and `tilemap` from &3800 to
> &4600, which Layer 11 [DECISION 1] moved to make room for the title's framebuffer. The dump is
> one command, in `CLAUDE.md` under "Symbol addresses come from".

## 15. Incremental draw disagrees with `RedrawAll` beside an animating door — **2026-08-19, unconfirmed**

Found during Layer 13a's RAM pass, while running the buffer oracle after moving the row/unit offset
tables (`docs/layer-13-ram-pass.md`, TASK 6). **Not yet reproduced, and not yet shown to predate
that change** — logged so it is not lost.

Diagonal scroll (X + M, 45 frames), then settle. The play buffer differed from a forced `RedrawAll`
by **176 bytes of 10,240**, falling to 16 and then 7 as it settled over 3 M cycles, so it is not a
tear. The survivors were **row 7, units 7, 8, 10 and 11**.

`doorRow[0]` was **7** — the same row — and the door table read
`doorState = 44 44 40 C0 C2 00 00` with `numDoors` 4. `&C2` is a horizontal door at **step 2 of
five**, i.e. mid-animation, and `&40`/`&C0` are two more at step 0. So the disagreement sat exactly
on an animating door, in the rows a door patches through `doorDef`/`doorDirty`.

**What is ruled out.** It is not the offset tables the pass moved: they were read back byte-exact
in that same state, a write breakpoint on their page stayed silent through play and scrolling, and
a read breakpoint on the rest of the page — which `PnClear` used to zero and no longer does — never
fired. `SetCell` was therefore computing the same addresses it always has.

**It did not reproduce**: 0 diffs of 10,240 stationary, after horizontal scrolling, after the same
X + M diagonal on two other decks, and after the opposite Z + K diagonal — five clean runs against
the one failure.

**2026-08-19, and this is the useful part: it correlates with driving a modal screen by poking its
flag, not with any of Layer 13a's changes.** Chasing it during TASK 3 produced a 10-byte
disagreement at the player's own position — and the run that produced it had been forced in and out
of the console, the transfer and the droid database by writing `conActive`, `xferDroid`, `xfmDone`
and `conDbReq` directly, which **bypasses `ConsoleClose` and `XferExit4` and therefore skips
`ReframeView`**. A clean boot of the same build, scrolled the same way with nothing poked but the
sprite disable, came back **0 diffs of 10,240** — as did the pre-branch build at `20b0697`.

So the suspicion moves off the level draw and onto **what happens to a door whose state changes
while a modal screen owns the buffer**: the console arm ends the pass with `JMP ml_passend` before
anything draws, so a `doorDirty` set and consumed under it is never painted, and only a `RedrawAll`
shows it. That is the same shape as **#12**, where lasers drawn before a console opens stay on
screen — a missing teardown on modal entry. Worth fixing the two together.

**It is NOT #9.** That one is 58–62 bytes and every one of them is in CRTC unit 0, the leftmost
column. This is in units 7–11 and nowhere near the edge.

**Where to look:** `dp_step`'s `doorDirty` and whatever repaints from it, against what `RedrawAll`
builds from the patched `doorDef`. The reproduction wants a deck with a door in view, the player
close enough to hold it open, and the oracle run while `doorState` is between 1 and 3.


## 18. `HS_STR_ADDR` was `PN_TABS` — **FIXED 2026-08-21**

Layer 11f's `DoHighScore` put its three strings in the `PARAFNT` block at
`FONTCODE_ADDR + FONTCODE_BYTES`, on the argument that constant data with no bank of its own
belongs there beside `FontCell` and `DoScore`. **That expression is also the definition of
`PN_TABS`** — the four mirrored droid tables `PageTabsIn` copies down from bank 4 at boot and at
every title. The strings shipped, loaded, and were then overwritten by the tables.

**The chain, end to end.** `DbStr` read the droid table instead of a string, never found its
`&FF`, and printed some 272 glyphs. `DbGlyph` advances `pnDst` by 16 a glyph, so the print walked
out of the play buffer, past `&8000` and into **bank 7**, where it flattened `xfRowAdrLo/Hi`.
Nothing looked wrong yet. On the NEXT game over, `GoWashRow` loaded `xgd` from that table, got a
zero high byte, and wrote 640 bytes from `&00EE` — through zero page, the stack and the MOS
vectors. Hence: hang in phase 1, then BASIC.

**How it was found**, after the first hypothesis (an escape condition) was measured out — `&FF`
bit 7 was 0 at all four sampling points:

1. `overPhase`/`overTick` frozen at 1/`&F0`, and `&F0` is `GO_TICK_END` exactly.
2. Execute breakpoint on `GoWashStart` fires; write breakpoint on `overPhase` never does.
3. `goBoil` = 15, the first iteration's value → the first `GoWashRow` never returns.
4. `svp`/`xgd` = `&00EE`, and reading `xfRowAdrLo/Hi` out of bank 7 showed **font bytes**
   (`&88 &EE &CC &77 &33 &66` are all `fontExpand` outputs) where row addresses belong.
5. A **write breakpoint on the table itself** (`&8C1A`) caught it: `PC = &3D06`, inside
   `FontCell`. The stack gave the whole chain — main loop → `InfoCall` → `IsDone` → `&B58C`
   (highscore) → `DbStr` → `DbGlyph` → `FontCell`.

**The lesson worth keeping: `font_end` is NOT the end of the region.** `PARAFNT`'s file ends at
`&3D98`, but `PN_TABS`' 96 bytes follow it and `SPR_SAVE` is at `&3E00` — so the gap is **8 free
bytes, not 104**. Anything that reads "spare" there must check `PN_TABS` first.

**The fix, and it is not a smaller version of the same idea.** The strings did not move to another
resident hole — there was not one, and hunting for 77 bytes was the wrong instinct twice over. KC:
this screen runs outside the game, so it should hold no resident RAM at all. `SetupPlain` made that
possible (see `docs/layer-11f-frontend.md`), and `DoHighScore` is now in the **PARTITL overlay**,
carrying its own alphabet from `tools/export_hsfont.py`. What stayed resident is twenty-five bytes
of bank 7 for the table, which has to remember between games, and three bytes of main RAM for
`TitleSeq`'s `JSR`.

So `PN_TABS` is not written by anything of Layer 11f's any more, and the collision cannot recur.
**Verified in jsbeeb**: 999 page → "Great Score!" and the prompt drawn over it → `A` walked to `G`
→ three initials committed → `hsHiIni` reads G, A, A, `hsArmed` cleared, the low table untouched →
title.

**The measurement that is worth keeping** is the one in the "lesson" paragraph above: `font_end` is
not the end of that region, and the gap above it is 8 bytes rather than 104.
