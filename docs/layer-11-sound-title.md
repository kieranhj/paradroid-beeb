# Layer 11 — Title, the 001 screen, game over, and sound

**Status: 11a built 2026-08-18; 11b-11e planned.** Scoped with KC 2026-08-18. Decisions KC might want to revisit
are marked **[DECISION]** and collected in §7; things deliberately left out are in §8.

The layer's shape came out of reading the listing rather than the plan: the flow this builds is the
original's own, `Restart0` → `TitleLoop` → `StartGame` → the game → `EndGame` → `TitleLoop`, and
three of its four screens turn out to fit machinery the port already has.

---

## 1. What the C64 does

```
Restart0 ($1078) ──> TitleLoop ($10D3)
    ShowTitle ($2879)          the logo screen; 256 frames, or fire
    fired?  ──> StartGame
    not fired ──> the intro manual: 5 pages scrolled over a 15.5 K text
                  canvas, fire starts the game at any point
StartGame ($1242)              shipLevel / weaponType / Score / droidType = 0
    _entership ($1289)         NextLevel, random deck 4-7, NewShipInfo, BuildLevel
        ──> the game
EnterGame ($142E), droidEnergy = 0 at $143B:
    droidType != 0  ──> BlowInto001 ($1573)   fall back to a 001, keep playing
    droidType == 0  ──> _gameover ($1455)     the explosion burst, then
        EndGame ($378B) ──> DoHighScore ──> JMP TitleLoop
```

Three findings shape everything below.

**Death is only a game over when you are already a 001.** `$144D` is the whole test. The other
branch is `BlowInto001`, which we already have: `CbCheckDeath` in `combat.asm` is a port of it
minus its modal loop. So this is one branch, not a rewrite.

**`BlowInto001` does not move the player.** Our teleport to waypoint 0 is entirely ours. Once a 001
death ends the game the teleport has no job left, and dropping it takes BUGS.md #10's cause — a
teleport breaking `COPYCHAR`'s parity rule — out of the respawn path for good.

**`NewShipInfo` (`$36B9`) *is* the 001 screen.** `StartGame` zeroes `droidType`, `_entership` copies
it into `dType` at `$12B1`, and `NewShipInfo` draws `ShowRobotType` plus the 48 × 84 portrait plus
a token string with the ship number patched into `NewShip_txt+$D`. It runs at the start of every
ship; on the first one you are a 001, so that is what it shows.

## 2. The four screens, in the original

| | | |
|---|---|---|
| **Title** | `ShowTitle` `$2879` | Copies `Title_dat` (`$CC00`, a raw 40 × 25 character screen, 1,000 B) to `$4800`; colours come from looking each code up in `CharColor`. Waits 256 frames or fire. 36 unique characters: block letters built from the level tile characters, two bordered panels in the `$7000` text font, the Hewson branding |
| **Intro manual** | `TitleLoop` `$10D3` | `UpackText` unpacks `$D000` into a 15.5 K character canvas at `$8000`; `ScreenPosX/Y` then pan the game's own scroll engine over it, 5 pages of 320 px. The page at `ScreenPosX+1 == 5` picks a random `dType` and calls `BuildIntroSprites` |
| **001 screen** | `NewShipInfo` `$36B9` | `GotoHires`, `ClearGameScreen` `$F2`, `ShowRobotType`, `BuildIntroSprites`, `PrintTokenString` of `NewShip_txt`. Draws rows 8-24 only — the play area |
| **Game over** | `$1455` then `EndGame` `$378B` | In-game: seven extra explosion sprites scattered ±4 px around the player (`$1487` reads `$D41B` twice per sprite), all eight animated to image `$44` then disabled. Then `EndGame`: a wash of random characters `$7A`-`$7D` over the play rows, an `AnimAllInsideFont` dissolve for 128 frames with `vScroll` running, then hires, `ClearGameScreen` `$F3`, `dType = $17` — the **999**, type 23 of 24 — with `loc_0_365E+1` patched from 40 to `$A0` to centre the portrait, two `DrawString`s, an 88-tick pause, `DoHighScore` |

`NewShipInfo`, `EndGame` and `ShowXferInfo` are all **play-area-only** screens — C64 rows 8-24,
seventeen rows — which is the shape Layer 10's shadow screen already has. Only the title is a full
25-row screen, and that is the one thing here that needs a display of its own.

## 3. Where each piece lands here

**What the port already has.** Bank 7's shadow character screen and colour shadow (`xsScr`/`xsCram`),
the code-to-glyph page, the row tables, the zero-page aliases and the panel-line text engine —
shared by the transfer game, the lift view and the console pages, and play-area-shaped. The `$C000`
string table, copies in banks 6 and 7. The 8 × 16 font, reachable from every bank — at `&3C00`
today, and at `&3000` from 11c on, see §4. The
31 effect frames in bank 5. `CbCheckDeath`. `ReframeView`, `LoadDeck` and the deck-entry path.

**What is missing.**

| | |
|---|---|
| 48 × 84 portrait | ~1,008 B **per type** in MODE 1 (12 bytes × 84 rows), × 24 = 24 K. Not being ported — see [DECISION 3] |
| Title screen | `Title_dat`'s 1,000-byte character map, and a display to put it on |
| Intro manual | the 15.5 K canvas and a scroll engine that reads a character map. Deferred — §8 |
| `PrintTokenString` | `$36DB`, deferred from Layer 10 decision 8; `NewShipInfo` needs it |
| A way to start the game twice | `main.asm` runs one linear boot straight into the game loop |
| Room | main RAM 24 B, bank 4 294 B, bank 5 1,033 B, bank 6 **full**, bank 7 ~2.0 K |

## 4. The title's memory map — how 25 rows fit

25 rows × 640 = **16,000 contiguous bytes**, and the port's main RAM is nominally full. It fits
anyway, because **the title's buffers and the game's never coexist**. At title time no deck is
loaded, so the sprite background save areas (2,048 B), the tile map (1,024 B), the panel (2,560 B),
the character-address and mask tables (768 B) and the 10 K play buffer are all idle — `&3000`-`&7FFF`
is 20,480 B of which only `PARAFNT` (`&3C00`-`&49FF`, 3,584 B) is genuinely wanted, and it is
wanted in the middle.

**So `PARAFNT` moves to `&3000` permanently**, and the sprite save areas and the tile map move up
behind it. It packs exactly: 3,584 + 2,048 + 1,024 = 6,656, which is `&3000` to `&4A00` —
`PANEL_ADDR`, where the map is unchanged from there down. **[DECISION 1]**

```
  game:                                       title:
  &3000-&3DFF   3,584 B   PARAFNT             &3000-&3DFF   PARAFNT, where it always is
  &3E00-&45FF   2,048 B   sprite save areas   &3E00-&3FFF   idle
  &4600-&49FF   1,024 B   tile map            &4000-&7E7F   TITLE SCREEN, 25 rows x 640
  &4A00-        unchanged from here down      &7E80-&7FFF   free
```

The font ends up permanently **below** the framebuffer, so the title needs no relocation and no
second load: one home, used from both modes. An earlier draft of this plan proposed `*LOAD PARAFNT
3000` for the title alone and left the game's map untouched; KC's arrangement is better, and the
objection raised against it was wrong. What `PLAN.md` records about the tile map is that **floating
it after `code_end`** once drifted it over the save areas — an argument for a fixed home, not
against a different fixed one.

**Nothing here is load-bearing on the old addresses**, which is why the move is three constants and
two asserts:

- `SPR_SAVE` requires only page alignment (`ASSERT (SPR_SAVE AND &FF) == 0`) and `code_end <=
  SPR_SAVE`. **The blitter does not bake it in**: `SprSetSave` builds `svp` at runtime from
  `HI(SPR_SAVE) + sprSlot` and the compiled stores go through `(svp),Y` — the indirection that made
  compilation possible in the first place, per `sprite.asm`'s header.
- The tile map has no alignment requirement at all: `mapRowLo`/`mapRowHi` are assembled from
  `tilemap + r * MAP_COLS`.
- `FONT_ADDR` and everything derived from it (`PN_FRAME_ADDR`, `PN_TABS`) are constants resolved in
  file order, and `SAVE "PARAFNT", ..., FONT_ADDR, FONT_ADDR` carries the catalogue address with them.
- Boot ordering is unchanged: `PARAFNT` loads last because the bank staging runs over `&3000`
  upward, which was already true at `&3C00`.
- `ASSERT SPR_SAVE + SPR_SLOTS * 256 <= &3800` becomes the same test against the new tile map base.

**The display.** Start address `&4000` ÷ 8 = `&0800`. The window is 2,000 CRTC units and MA12 goes
high at unit 4,096, so it ends at 4,048 — 48 units of margin, and **no hardware wrap is involved at
all**. R6 = 25 with R4/R5 unchanged keeps the 39-row, 312-line, 50 Hz frame; R7 centres the 200
displayed lines. A plain single-cycle display: **the rupture is torn down for the title** and
rebuilt on the way into the game. **[DECISION 2]**

**Drawing it.** The title is drawn once and is then static, so it needs no speed and no lookup
tables: a small plotter in bank 7 computing character addresses arithmetically, rather than the
game's `CHAR_PTR_LO/HI` — which would otherwise have to live under the framebuffer. The block
letters come from the MODE 1 charset built at `&0400` by `BuildCharset` (bank 4 data, independent
of any deck map, so it can run before a deck exists); the two info panels come from `PARAFNT`.
A title palette is Layer 14's to settle.

## 5. Staging

Not KC's listed order — the loop cannot close until the pieces exist, and one precondition comes
first. Each step ends with something visible.

### 11a — Split boot into "once" and "per game" — DONE 2026-08-18

`GameStart` in `droid.asm`, bank 4, beside `NewShipDroids` and the droid tables it seeds: the C64's
`StartGame` (`$1242`) and `_entership` (`$1289`) in one routine, ending on the random deck 4-7 and
`LoadDeck`. `main.asm`'s boot keeps the cold half — mode, disc, banks, `BuildCharPtrs`,
`SprBuildMask`, `SetupRupture`, `InstallIrq`, the seed — and then just calls it. Main RAM shrank 20
bytes to `&2FD3` in the process, and bank 4 paid the 147.

**The work is the defaults, not the plumbing.** Boot used to lean on beebasm's assembled initial
values for everything, so a second game inherits whatever the first left: a console still up, a
lift half-entered, a transfer holding its verdict, a half-pressed key's edge latch, the top speed of
whatever droid you were riding. `GameStart` writes all of it out loud, in five groups the source
names. Two ordering traps are recorded there: `CombatInit`'s `$40` energy (`$1345`, what the entry
animation *ends* on) must not be overwritten by `BlowInto001`'s 7, which is why `ccd_reset`'s
identical speed-clamp block is deliberately *not* shared; and `SprInit` moved out of boot to here,
because it resets state where `SprBuildMask` beside it builds a table.

**`DEBUG_RESTART` exists so this is testable at all** — R restarts the game — and it sits **above**
the console / transfer / lift-view blocks in the main loop, each of which ends its pass with
`JMP ml_passend`. Below them it could not be reached from exactly the states worth testing from,
which are exactly the states a game can end in.

**Verified in jsbeeb.** Every field poked dirty — `conActive` 1, `liftMode` 2, `moveMode` 0,
`plyDying` 1, `maxEnergy` 5, `weaponType` 3, `alertLvl` `$C0`, score `12345678`, `shipLevel` 5,
`drType` 17, `drEnergy` 1, `losTurn` 0, and the speed clamp at `$07FF` — then R. All of it came back
clean: energy `$40` (ageing to `$3F`), `moveMode` `$80`, `mmDelay` 8, score zero, `shipLevel` 1,
`drType` 0, clamp `$0800`/`$F800`, `losTurn` walking again, `drCount` 9. Fifteen restarts in
succession with the key held did not disturb it, the deck re-rolls, and the play buffer and panel
still hold their content 800 frames later.

### 11b — Death is a game over

The `$144D` branch in `CbCheckDeath`: `drType != 0` keeps the existing `BlowInto001` path,
`drType == 0` goes to the game over. Drop `DrSpawnPoint` / `SetPosFromWaypoint` / `ReframeView`
from the fall-back path, as the original does. **[DECISION 4]**

Then the C64's own sequence: the explosion burst (`$1478`, seven extra effect sprites scattered
±4 px around the player, all eight animated to the end of the set), then `EndGame`'s character
wash and dissolve, then a banner on bank 7's shadow screen. `DEBUG_INVULN` arrives here for testing,
and must be added to `DEBUG_ANY` and to `!BOOT`'s stamp as well as defined, or the build can lie
about itself. **[DECISION 5]**

### 11c — The title screen, and the loop

Rupture down, IRQ1V back to the MOS, plain MODE 1 as §4 describes, `*LOAD PARAFNT 3000`, build the
charset, draw `Title_dat`, wait for fire — **stirring `drSeed` once a frame while it waits**, which
is the original's own entropy mechanism (`$12B6` samples `$D41B` after however long the player left
the title up) and what kills the deterministic starting deck under emulation. Fire re-runs the boot
loads, `SetupMode`, `SetupRupture`, the table rebuild and `InstallIrq`, then 11a's per-game init.
Game over returns here.

### 11d — The 001 screen

`NewShipInfo` (`$36B9`) on bank 7's shadow screen: `PrintTokenString` (`$36DB`, the machinery Layer
10 deferred), `ShowRobotType`, and the runtime-composed rotor-and-digits droid where the C64 draws
the portrait. **[DECISION 3]**

### 11e — Sound

The SN76489 driver replacing the SID engine, and the `sndFx1`/`sndState` writes stubbed out of the
console, transfer and this layer's code. See §6.

## 6. The SN76489 encoding — recovered, NOT verified

The chip is written through System VIA port A with handshake at `&FE41`; a latch byte is
`1 cc r nnnn` and a data byte `0 0 nnnnnn`, so a tone is `&80 | (chan << 5) | (freq AND &0F)`
followed by `freq >> 4`, and an attenuation is `&90 | (chan << 5) | (15 - vol)`.

**That came out of the deleted `hardware.asm` and was never verified on hardware or in the
emulator.** Check it against the BBC hardware wiki before building on it, per the standing rule
about recalled facts. It is the only surviving content of that file.

## 7. Decisions

All taken with KC on 2026-08-18, before building.

**[DECISION 1]** `PARAFNT` **moves permanently to `&3000`**, with the sprite save areas at `&3E00`
and the tile map at `&4600`. KC's call, and the right one: the font then sits below the title's
framebuffer at `&4000`, so it has one address in both modes instead of being reloaded low for the
title. Three constants and two asserts; §4 has the evidence that nothing depends on the old
addresses.

**[DECISION 2]** The title is a **25-row character map on a plain single-cycle display**, not a
pre-rendered bitmap and not the full 32 rows. KC's call: it keeps the original's own composition —
block letters out of the level tile characters — so Layer 14 tunes it as artwork and a palette
rather than as a picture. The rupture is torn down for it and rebuilt on the way into the game.

**[DECISION 3]** The 48 × 84 droid portrait is **not ported**. `NewShipInfo` and the game-over
screen draw the **runtime-composed rotor-and-digits droid** instead — the same substitution the
console's droid database already makes (`layer-9-hud.md` §6f decision 2). 24 K in MODE 1 is the
reason; a partial port of types 0 and 23 alone would be ~2 K and is the fallback if the substitution
reads badly. TODO in §8.

**[DECISION 4]** The **waypoint-0 respawn is dropped**. `BlowInto001` (`$1573`) does not move the
player and neither will we: falling back to a 001 leaves you where you died. This is a *removal* of
a port-only divergence, and it takes BUGS.md #10's cause out of the respawn path.

**[DECISION 5]** A `DEBUG_INVULN` build flag replaces the respawn as the way to test deep in the
ship without playing there.

**[DECISION 6]** The title screen is a **separate disc file**, loaded on the way in and discarded
by the first deck load, and re-loaded on the way back from a game over. No fifth sideways bank.

## 8. Deferred — TODOs, agreed 2026-08-18

- **The 48 × 84 droid portrait.** Blocks the faithful `NewShipInfo` and `EndGame`, `ShowXferInfo`'s
  two droid info screens (deferred from Layer 10), and the intro manual's random-droid page.
  ~1,008 B per type in MODE 1; 24 K for all 24, ~2 K for types 0 and 23 alone.
- **The intro manual.** `UpackText`'s 15.5 K canvas, five pages, panned by the game's own scroll
  engine. Wants the rupture back *and* the scroll engine reading a character map instead of a tile
  map — the two are the same machinery on the C64 and are not here.
- **`DoHighScore` (`$E4E5`).** HIGH and LOW score, three-initial entry, and it sits between
  `EndGame` and `TitleLoop` in the original's flow, so the seam for it is built even though the
  screen is not.
