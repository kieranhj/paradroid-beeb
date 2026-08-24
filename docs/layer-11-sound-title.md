# Layer 11 — Title, the 001 screen, game over, and sound

**Status: 11a, 11b and ALL of 11c built — the game-over → title loop landed 2026-08-20,
verified in jsbeeb over two consecutive game overs. 11d and 11e are not built.** Scoped with KC
2026-08-18. Decisions KC might want to revisit are marked **[DECISION]** and collected in §7;
things deliberately left out are in §8. 2026-08-20 also restored [DECISION 6]: the title is the
`PARTITL` disc overlay again, not a bank 7 resident — see §11c.

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
| 48 × 84 portrait | **Ported 2026-08-20** — the pool is 4,032 B verbatim and `PoDraw` expands at draw time; the 24 K figure was a mistake. See [DECISION 3] and `layer-9-hud.md` §6f. 11d only has to point `NewShipInfo` at it with its own rectangle |
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
A title palette is Layer 14's to settle — and it did, 2026-08-24: the front end inherits the
last deck's text palette and picks a random deck at a cold boot. See layer-14 DECISION 5.

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

**`DEBUG_RESTART` existed so this was testable at all** — R restarted the game, and it sat **above**
the console / transfer / lift-view blocks in the main loop, each of which ends its pass with
`JMP ml_passend`. Below them it could not be reached from exactly the states worth testing from,
which are exactly the states a game can end in.

**It was removed 2026-08-21 and ESCAPE replaces it** (Layer 11d). ESCAPE self-destructs, which
reaches the same boot split by the long way round — the death, the wash, the 999 page, the title —
and therefore tests strictly more than R did. It sits **below** the modal blocks for the opposite
reason to R's: a player-facing quit has no business firing while the console or a half-finished
transfer owns the machine.

**Verified in jsbeeb.** Every field poked dirty — `conActive` 1, `liftMode` 2, `moveMode` 0,
`plyDying` 1, `maxEnergy` 5, `weaponType` 3, `alertLvl` `$C0`, score `12345678`, `shipLevel` 5,
`drType` 17, `drEnergy` 1, `losTurn` 0, and the speed clamp at `$07FF` — then R. All of it came back
clean: energy `$40` (ageing to `$3F`), `moveMode` `$80`, `mmDelay` 8, score zero, `shipLevel` 1,
`drType` 0, clamp `$0800`/`$F800`, `losTurn` walking again, `drCount` 9. Fifteen restarts in
succession with the key held did not disturb it, the deck re-rolls, and the play buffer and panel
still hold their content 800 frames later.

### 11b-1 — Death is a game over, and the cloud — DONE 2026-08-18

**One test was the whole of it.** `$144D`: `drType != 0` keeps the existing `BlowInto001` path,
`drType == 0` ends the game. `CbCheckDeath` now branches there, and `overPhase` gates the rest.

**The waypoint-0 respawn is gone** — `DECISION 4`. `BlowInto001` (`$1573`) does not move the player,
so neither do we; falling back to a 001 leaves you where you died. That also takes BUGS.md #10's
cause, a teleport breaking `COPYCHAR`'s parity rule, out of this path for good.

**The cloud is `$1465`-`$14CA`.** `GoTick` lights one more slot a pass at a jittered copy of the
player's position, `overTick` running 6 down to `$F0`, and advances every effect slot one frame,
switching off any that runs past the end of the set — so the last sprites are still burning when the
first have gone out. Slot 7 is the bullet's, and the C64 reuses its sprite 0 the same way.

**The ship stops while it plays.** `$14A8` and `$14C5` call `RunGame` and *not* `RunDroids`, so the
main loop gates `ReadKeys`/`CalcSpeed`/`CheckWalls`, the fire block, `DoMoveMode`/`MovePlyFire` and
`DroidsUpdate` on `overPhase`. The fire gate is not optional: leave `MovePlyFire` running and it
puts slot 7 out again the pass after the cloud lights it.

**Two deviations, both recorded in the source.** The jitter is `(rnd AND 7) - 4` pixels vertically,
as `$1498` has it, but horizontally it moves whole 4-pixel CRTC units — our sprite X is a unit plus
a shift, and a pixel-exact offset needs 16-bit arithmetic and a re-split. And a sprite whose jitter
would put it off the view is dropped rather than clamped.

**Where it went.** `GoStart`/`GoSeed`/`GoTick` are in **bank 7**, with the transfer game and the lift
view — the other two screens that take the play area over, and where 11b-2's wash and banner will
want the shadow screen and glyph renderer. Bank 4 had 147 bytes free and the block was 147, so it
had to move anyway. Main RAM paid for the shims (`GoStart7`/`GoTick7`, the `XferTick` pattern) by
sending `ccd_reset`'s body the other way, to bank 4 as `CbReset001` — every field it writes but the
three sprite ones already lives there. **The randoms are drawn on the main-RAM side** and passed in:
`DrRandom` is bank 4's and its LFSR must stay one sequence.

**Verified in jsbeeb.** Fall-back arm: `drType` 5 with energy 0 came back as type 0, energy 7, no
game over, and **the play buffer byte-identical before and after** — no teleport, no re-frame.
Game-over arm: `overPhase` 1, the pool filling with effects at staggered frames
(`8,2,3,4,5,6,7,8` mid-cloud), **droid positions byte-identical over eight passes** — the ship
really does stop — and then a fresh game with the score cleared and `shipLevel` back to 1.

### 11b-2 — `EndGame`'s screen — DONE 2026-08-18

`overPhase` 2, and it is **modal**: it owns the play buffer the way the console and the transfer
game do, so the main loop gives it a block of its own that ends the pass — which is also what keeps
`PanelTick` off the line the message is on. Phase 1 could not do that, because the cloud needs the
sprite pool erased and drawn like any other frame.

The view is flattened first — `scrollS` and `line` to zero, the CRTC re-parked — exactly as
`XferEnter4` does before the board, so the buffer addresses as a plain 16 × 640 array and bank 7's
`xfRowAdrLo/Hi` apply. All 640 cells are painted in one pass at entry, as `XfRepaintAll`'s are; the
frame lock is a floor.

**[DECISION 7] — three departures, all recorded in `xfer.asm`.**

1. **The four wash characters are ours, and not by choice.** `$379F` picks `(rnd AND 3) + $7A` out
   of the deck charset, and **`$7A`-`$7D` are not in the ported set**: `export_bbc.py` converts only
   the characters some tile references, and those four are used by `EndGame` and nothing else, so
   `CHAR_PTR_LO/HI` clamp all four to entry 0 and the first build of the wash came out blank. Four
   16-byte patterns in bank 7 stand in — solid, half, quarter and sparse **black**, because `$37A6`
   writes colour `$F0`, low nibble 0, so the C64's wash is a dissolve into darkness rather than
   white noise, and logical 1 is black under the port's fixed slot roles. **TODO: export the real
   four.**
2. **No charset animation.** `AnimAllInsideFont` (`$38C4`) is the same self-modifying machinery as
   `AnimateIntoFont`, which Layer 10 already declined; this follows it. The wash boils by being
   repainted one row a pass instead, so the screen churns every sixteen.
3. **The message is on the panel line**, not on a hires screen — decisions 6-8 of Layer 10 again,
   and [DECISION 3] had already taken the 999 portrait the C64 draws behind those two strings.

**Two traps, both about the same random number generator.** `XfRand`'s seed is `XfStart`'s to set
and the game over never goes through `XfStart`; a zero seed locks the LFSR, so every cell of the
wash came out the same pattern until `GoWashStart` seeded it from the pass's own random. And then it
still came out the same pattern everywhere but the left-hand column, because **`XfRand`'s tap was
`$B4`, which is not primitive** — the low two bits of its output are always zero and its period is
65. One byte, `$B4` → `$1D`, and it also un-skews the transfer board and revives a branch of
`XfPutRandom` that had never once been taken. **BUGS.md #14**, found by KC from the first play.

**Verified in jsbeeb** end to end: death as a 001 → cloud → `overPhase` 2 with a mixed-pattern wash
in the buffer and "game over" rendered on the panel text line → 88 passes later a new game, with
the deck redrawn and `overPhase` back to 0.

`DEBUG_INVULN` landed with it: energy pinned at full at the top of `CbCheckDeath`, in `DEBUG_ANY`
and in `!BOOT`'s stamp. **[DECISION 5]**

> **Open and cosmetic:** the wash draws in logical 1 and renders **blue** on the deck tested, so it
> reads as blue static rather than the C64's dissolve into darkness (`$37A6` writes colour `$F0`,
> low nibble 0, black). Layer 14's, with the caveat that it may mean logical 1 is not black on
> every deck.

### 11c — The title screen — DONE 2026-08-18; the loop back DONE 2026-08-20

**The title itself is built and verified.** `src/title.asm` — since 2026-08-20 assembled at
`TITLE_ADDR = &3000` and shipped as the **`PARTITL` disc overlay**, [DECISION 6] restored: bank 7's
free space went to the droid portrait plan instead. `TitleSeq` (main RAM) *LOADs it over PARAFNT's
ground, runs `TiShow` in place — it is all main RAM now, no paging anywhere in it — then reloads
`PARAFNT` and `PARALOW` over it and rebuilds everything the title's framebuffer sat on. It runs with
the CRTC in `SetupMode`'s plain single-cycle shape and the MOS's IRQ in place, because the loads
need VSync and the filing system and `TiWait`'s keydown needs OSBYTE.

R6 alone cuts the height to 25 rows; R4, R5 and R7 keep `SetupMode`'s 39-row, 312-line, 50 Hz frame,
so the picture sits at the **top** of the frame rather than centred. Centring is R7's and is left to
Layer 14 with the rest of the look.

**The wait is `$2907`-`$291F`: fire, or a timeout.** The timeout is the original's own behaviour and
it is also the escape hatch — a title that could only be left by a keypress is a title that a
mis-read key turns into a hang. Ours counts loop iterations rather than fields, because there is no
IRQ yet to count fields with; a 16-bit wrap comes out at a few seconds.

**And it is where the randomness finally arrives.** `TiWait` leaves its dwell in `overRnd0` and
`GameStart` stirs `drSeed` with it, in bank 4 where the LFSR lives. The starting deck is no longer
the same on every cold boot, which is what `docs/layer-8-doors-lifts.md` said the title owed the
game.

**[DECISION 8] — the title carries its own glyphs.** Twelve of its thirty-six characters — `$52`
`$53` `$DF` `$E0`-`$E7` `$FF` — are **not in the ported charset**, because `export_bbc.py` converts
only what a tile definition references and those twelve are used by the title screen and nothing
else. `tools/export_title.py` converts the thirty-six it needs into 576 bytes of glyphs plus 564 of
RLE and touches nothing else. **Adding them to the shared charset is the better fix** and would also
give `EndGame` its four wash characters back — but it changes `NUM_CHARS` and the code→index remap
that every deck's rendering depends on, so it wants KC and a careful regeneration, not a passing
edit.

**[DECISION 9] — white on black, for now. SUPERSEDED 2026-08-24, layer-14 DECISION 5.** Every
glyph was rendered in logical 3 on logical 0, which made the logo one flat colour where the C64's
is embossed. It is now coloured per glyph from `CharColor` `$0800`'s slot, the front end picks a
random deck's palette at a cold boot, and the emboss is back for no extra bytes. The description
of the C64's colours that stood here — "two-tone yellow/brown outlines with purple panel text" —
was a guess and is wrong; the measurement is in
[`docs/layer-14-visual.md`](layer-14-visual.md) DECISION 5.

**Verified in jsbeeb**: the rendered title matches `tools/output/title_screen_7800.png` cell for
cell, fire skips it into the game, and the timeout falls through into the game on its own.

#### The loop back to the title — DONE 2026-08-20, and what it took

`GoTick7` now ends a game with `JMP GoTitle`: `UninstallIrq`, `SetupMode`, `RestoreDfsWs`, then the
same `TitleSeq` boot uses — load `PARTITL`, `TiShow`, reload `PARAFNT` and `PARALOW`, `PageLowIn`,
`PageTabsIn`, `SetupRupture`, `FillPanel`, `BuildMulTabs`, `BuildCharPtrs`, `SprBuildMask`,
`InstallIrq` — and hands what comes back to `GameStart`. Verified in jsbeeb: boot → title → game →
death as a 001 → wash → title → fire → new game, twice consecutively. ~187 bytes of main RAM,
affordable because the raster-timing pass had freed 323.

**`UninstallIrq` restores more than the vector.** `InstallIrq` now saves the MOS's System VIA IER,
ACR and **T1 latches** (read via `&FE46`/`&FE47`) before clobbering them, and `UninstallIrq` hands
all of it back — the latches matter because the rupture reprograms them every field and the MOS's
100 Hz events (the keyboard scan OSBYTE `&81` reads, the clock, the disc timeouts) run off what it
left there. Writing the LATCH registers only, never `T1C-H`: T1 is continuous and picks the value
up on its next underflow. Measured clean-boot values for reference: T1L `&270E`, ACR `&60`, IER
enabled bits `&73`.

**The hard bug: the low overlay sits on what the filing system needs.** The first attempt hung the
game-over `*LOAD` in the DFS retry loop and then crashed through zero page, and `*DISC` did not
recover it. Two regions are the reason: `&0E00`-`&10FF` is DFS's own workspace (under `lowcode`),
and `&0D9F`+ is the MOS's **extended vector table** (under `lowcode2`) — which is how DFS 1.2
routes FILEV into its ROM, so `*LOAD` was jumping through our code bytes. Boot never sees this
because its loads all run before the first `PageLowIn`. The fix is `SaveDfsWs`/`RestoreDfsWs`:
`TitleSeq` snapshots the two buried spans — `&0D60`-`&0DEF` and `&0E00`-`&10FF` — into **bank 6**
(`dfsSave`, 912 B, SKIPped; bank 6 was the free space nothing else could use, and it keeps banks 5
and 7 clear for the flicker and the portraits) right after its last `*LOAD`, and `GoTitle`
restores them byte for byte before the game-over loads — a state the MOS and DFS were actually in,
extended vectors, catalogue cache and all. `&0D00`-`&0D5F` (NMI) and `&0DF0`-`&0DFF` (ROM
workspace bytes) are not in the snapshot: nothing of ours ever writes them.

### 11d — The 001 screen — NOT BUILT

`NewShipInfo` (`$36B9`) on bank 7's shadow screen: `PrintTokenString` (`$36DB`, the machinery Layer
10 deferred), `ShowRobotType`, and the runtime-composed rotor-and-digits droid where the C64 draws
the portrait. **[DECISION 3]**

**Not started, and it needs room first.** Bank 7 has 282 bytes and bank 4 has 15. The token-string
printer alone is bigger than either. See §9.

### 11e — Sound — PLANNED, not built

**Scoped with KC 2026-08-21 — the spec, the full C64 effect inventory, the SN76489 mapping, the
four architecture decisions and the staging live in [`layer-11e-sound.md`](layer-11e-sound.md).**
In one line: an IRQ-driven 50 Hz `SndTick` in bank 4, paged in by the IRQ itself, fed by offline-
converted copies of the original's `$C610` effect records. See §6 below for the raw chip encoding
— **still unverified, and stage 0 of that plan verifies it first**. It was not verified in this session either: checking it means driving the System VIA
by hand from a test harness, and a driver built on a recalled encoding is exactly what `CLAUDE.md`
forbids. Verify first, build second.

## 6. The SN76489 encoding — VERIFIED 2026-08-21

**The encoding below was confirmed in jsbeeb by `tools/sndtest.asm`** (layer-11e stage 0): tone
284 measured 440.1 Hz, noise modes read back correctly, and the DDRA/ORA save-restore held up
against 16,384 OSBYTE `&81` polls with IRQ-driven writes. `layer-11e-sound.md` §5 stage 0 has
the numbers. The paragraph is kept as written for the history:

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

**[DECISION 3] — REVERSED 2026-08-20, with KC.** The 48 × 84 droid portrait **is ported**: the
costing that deferred it was wrong (the unique pool is 4,032 B verbatim, not 6 K, and never 24 K —
expansion happens at draw time), and `portrait.asm`/`portraits.asm` in bank 7 now draw it on the
console's database page, byte-for-byte against `BuildIntroSprites` (`layer-9-hud.md` §6f
decision 2 has the detail). `NewShipInfo` and the game-over screen still show the
rotor-and-digits droid ONLY because neither has been pointed at `PoDraw` yet — its rectangle is
anchored to the database page's and wants parameterising first. That is 11d's business.

**[DECISION 4]** The **waypoint-0 respawn is dropped**. `BlowInto001` (`$1573`) does not move the
player and neither will we: falling back to a 001 leaves you where you died. This is a *removal* of
a port-only divergence, and it takes BUGS.md #10's cause out of the respawn path.

**[DECISION 5]** A `DEBUG_INVULN` build flag replaces the respawn as the way to test deep in the
ship without playing there.

**[DECISION 6]** The title screen is a **separate disc file**, loaded on the way in and discarded
by the first deck load, and re-loaded on the way back from a game over. No fifth sideways bank.

## 8. Deferred — TODOs, agreed 2026-08-18

- ~~The 48 × 84 droid portrait~~ — **ported 2026-08-20**, see [DECISION 3]. What remains here is
  pointing `NewShipInfo`, `EndGame` and `ShowXferInfo` at `PoDraw` with a parameterised rectangle.
- **The intro manual.** `UpackText`'s 15.5 K canvas, five pages, panned by the game's own scroll
  engine. Wants the rupture back *and* the scroll engine reading a character map instead of a tile
  map — the two are the same machinery on the C64 and are not here.
- **`DoHighScore` (`$E4E5`).** HIGH and LOW score, three-initial entry, and it sits between
  `EndGame` and `TitleLoop` in the original's flow, so the seam for it is built even though the
  screen is not.


## 9. Where the RAM went — read this before starting anything

Layer 11 has taken the port from comfortable to full. As of 2026-08-18:

| | | |
|---|---|---|
| main RAM | ends `&2FE2` | **30 bytes** |
| bank 4 (`PARADAT`) | ends `&BFF1` | **15 bytes** |
| bank 5 (`PARASPR`) | ends `&BBF7` | 1,033 bytes |
| bank 6 (`PARSPR2`) | ends `&BFD8` | 40 bytes |
| bank 7 (`PARXFER`) | ends `&BEE6` | 282 bytes |

Three of the five are effectively full, and bank 5's 1,033 are hard to reach: it is the sprite bank,
paged only inside `SprDrawAll`/`SprRestoreAll`, so anything put there needs a main-RAM shim that
costs more than it saves unless what moves is large.

Two moves already paid for this layer — `ccd_reset`'s body into bank 4 as `CbReset001`, and
`LoadDeck` into bank 4 — and there is no third of that size waiting. **Layer 13's RAM pass has
stopped being optional and become the thing that unblocks 11c's loop, 11d and 11e.** Its own notes
already list the candidates: the bank-4/bank-6 split that exists only because bank 4 was 224 bytes
short at the time, and the 3 K font hole in main RAM.
