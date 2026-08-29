# Layer 15 — the endgame: clearing a ship, and the next one

**BUILT AND VERIFIED 2026-08-24.** This began as a scoping document, and §§1–3 are that scoping,
kept because they are the analysis the build followed. §4 is the space pass that unblocked it;
§5 is what was built. **The port now has a win condition and a ship progression; before this it
had neither, and `shipNumDroids` was maintained and never read.** It exists because KC asked whether the
"all decks complete" screen was in, and the answer turned out to be bigger than a screen: **the port
has no win condition and no ship progression at all.** `shipNumDroids` is maintained and never read.

Read [`layer-14-visual.md`](layer-14-visual.md) DECISION 6 first — the cleared-**deck** floor landed
on 2026-08-24 and put the first link of this chain in place.

---

## 1. What the C64 does, end to end

Five links, and the port has one and a half of them.

| | C64 | what it does | port |
|---|---|---|---|
| 1 | `RunDroids` `$17D5` | deck clear: `InitColors`, `AddScore` 250 twice, `sndFx1 = $17`, and `INC notInDeck` if `shipNumDroids` is zero too | **hook exists**, colour only |
| 2 | `GameLoop` `$1440` | `notInDeck` non-zero → `JMP _lift` | absent |
| 3 | `_lift` `$134F` | `shipNumDroids` zero → `JMP _shipclean` | absent |
| 4 | `_shipclean` `$1272` | `AddScore` 200 **ten times**, `FindStrings`, `sndFx1 = $B`, `JSR ShowShipClear`, then falls through | absent |
| 5 | `_entership` `$1289` | reset speeds/alert/sprites, `NextLevel`, `moveMode = $80`, player energy and type, `numDeckDroids = 2`, pick a deck, `LoadDeck` | **fused into `GameStart`** |

The payouts are **500 for a deck** and **2,000 for a ship**, and **clearing a ship does not end the
game**: `_shipclean` falls straight into `_entership`, which calls `NextLevel` and starts the next
ship. That is the whole progression loop, and it is why `shipLevel` exists.

### The screen itself is the small part

`ShowShipClear` `$3816` is nine instructions:

```
3816  JSR GotoHires
3819  LDA #$F5 / JSR ClearGameScreen
381E  LDA droidType / STA dType / JSR ShowRobotType   ; the "Unit type NNN - name" line
3826  JSR BuildIntroSprites                           ; the droid, as hardware sprites
3829  LDX #$CE / LDY #$6D / JSR PrintTokenString      ; ShipClear_txt at $6DCE
```

`ShipClear_txt` is ten bytes — `$DD $3F $33 $DF $DE $2C $66 $0A $50 $FE` — which the listing itself
decodes as **"congratulations! ship is now clear of all robot activity"**.

**That is the same screen `infoscr.asm` already builds three of.** Its header lists `NewShipInfo`,
`ShowXferInfo` (twice) and `EndGame`: the play area cleared, one droid pictured, a paragraph of
token numbers beside it, `IsPrint` being `PrintTokenString`'s own body, and the geometry already at
`prntX 9 / prntY 12`. `ShowShipClear` is a **fourth screen of exactly that shape**, and it is the
cheapest thing in this document.

---

## 2. What the port has, precisely

- **`shipNumDroids`** — built by `NewShipDroids`, decremented by `DrRemoveShip`, **read nowhere**.
  Confirmed by grep over the whole of `src/`.
- **`notInDeck` does not exist.** On the C64 it is a shared "leave the current loop" flag that the
  lift, the console and the transfer game all use; the port reaches those exits by other means, so
  there is no existing flag to hang the ship-clear on.
- **`NewShipDroids` is `NextLevel`'s roster half only.** The `INC shipLevel` is not in it —
  `GameStart` writes `shipLevel = 1` instead (`droid.asm:288`, and its comment says so).
- **`GameStart` is `StartGame` plus `_entership`, fused.** The C64 keeps them as a fall-through
  precisely so the second half can be re-entered.
- **Sound effects `$B` and `$17` are both already in the port's table** (`SND_NUM_FX = 29`), so they
  cost nothing but the two stores.
- **`shipLevel` already threads through** the difficulty (`combat.asm:896`, `SBC shipLevel`) and the
  console's ship name (`CON_TOK_SHIP`, eight names by `(shipLevel - 1) AND 7`). The progression
  machinery is wired; nothing advances it.

---

## 3. The tasks

### T1 — the deck-clear payout (500 points, `sndFx1 = $17`)

The hook is already there from DECISION 6. Two `AddScore` calls and a store.

**Cost** ~12 B bank 4. **Risk** none. **Decisions** none — the values are the original's.

### T2 — ship-clear detection

At the same hook: if `shipNumDroids` is also zero, raise the state that leaves the deck.

**This is the design question**, because the port has no `notInDeck` and does not leave a deck the
way the C64 does:

- **(a) a dedicated `shipClear` flag**, tested where the main loop already tests for the lift and
  the console. Smallest, and does not pretend to be something it isn't.
- **(b) port `notInDeck` properly** as the shared exit flag it is, routing the lift and the console
  through it too. Faithful to the control flow, but it touches three working subsystems to buy no
  behaviour the port lacks.

**(a) recommended** unless the C64's control flow is wanted as such.

**Cost** ~15 B bank 4 plus a byte. **Risk** low.

### T3 — `_shipclean`: 2,000 points, `sndFx1 = $B`, call the screen

Ten `AddScore #200`, a store, and a call into bank 7.

**Cost** ~20 B bank 4 plus the paging shim. **Risk** low. **Note**: the C64 adds 200 ten times
rather than 2,000 once because `AddScore` is BCD and takes a byte — keep the loop.

### T4 — `ShowShipClear`, in `infoscr.asm`

A fourth `IS_SCR_*`, the ten-byte token list, and an entry that draws the droid and the paragraph —
all reusing what the three existing screens already share.

**Cost** ~50 B of **bank 7**, which has **314 free** — the only task with room to land in.
**Risk** low. **Decision**: the C64 uses `BuildIntroSprites`; the port would use the portrait pool
the briefing and the database already share. Confirm.

### T5 — ship progression

The structural one. Split `GameStart` into its two halves so `_entership` is callable alone, add the
`INC shipLevel` that `NewShipDroids` does not carry, and call the second half from T3.

**Cost** small in bytes — mostly a re-labelling — but it is surgery on the routine that every start
and restart goes through, including the game-over → title loop Layer 11 built. **Risk: the highest
here.** It wants its own verification pass: cold boot, a game over, a restart, and a ship
transition, all four still landing correctly.

**Decision**: eight ships, then what? The C64 wraps the *name* at `(shipLevel - 1) AND 7` and keeps
raising the difficulty. Confirm the port does the same rather than ending.

---

## 4. The memory problem — SOLVED 2026-08-24, bank 4 has 105 B

**The space pass ran on 2026-08-24 and the layer is no longer blocked.** The figures below are the
build's own, before and after; `docs/memory-map.md` §"Layer 15 space pass" carries the full detail.

| region | before | after |
|---|---|---|
| bank 4 (fuel gauge) | 8 B | **105 B** |
| `colourMap`'s alignment padding | 17 B | 17 B (untouched — the change is downstream of that `ALIGN`) |
| **bank-4 headroom in total** | **25 B** | **122 B** |
| main RAM | 3 B | 3 B |
| bank 6 | 4 B | 4 B |
| bank 7 | 314 B | 314 B |

§3's estimates for T1, T2, T3 and T5 come to roughly 50 bytes of bank 4. **There is now more than
twice that**, so all five tasks can be built without a further hunt, and T4 still lands in bank 7's
314.

### What was taken

**112 bytes of per-deck tables that nothing read** — `deckOffsetLo`/`Hi`, `deckY`, `deckX`,
`deckHeight`, `deckWidth`, `deckColour`. Of the C64's eight tables at `$F120` only `deckDroids` has
a reader in the port; the offsets indexed the RLE stream Layer 13d deleted, the four geometry tables
are duplicated in bank 7 where the deck plan can actually see them (`sideview.asm`), and
`deckColour` predates `colours.asm`. Confirmed by word-boundary grep over `src/` and `tools/` before
the change, and the build would have failed on an unresolved label had one been missed.

The saving is in `tools/export_bbc.py`, not in `src/data/` — that directory is generated, and
**`build.ps1` does not run the exporters**, so `python tools/export_bbc.py` is part of the change.
Re-emitting any dropped table is a one-line edit and the exporter says so.

**15 bytes went back out**, and this is the part worth remembering. Removing 112 bytes upstream
shifted `sound.asm`'s 38-byte voice-state block across a page boundary and broke
`ASSERT HI(snFreqLo) == HI(snPhase+1)` — `SndCopy`'s stride-2 self-modified store steps the low byte
only. The assert had no padding behind it, so **any** bank-4 edit of the wrong size could break it.
It now has a conditional pad (`IF HI(P%) <> HI(P% + 37) : SKIP 256 - (P% AND 255) : ENDIF`), at most
37 bytes and often none. **A future bank-4 change can therefore move the gauge by up to 37 bytes on
its own** — read it, never infer it.

### What was rejected

- **Turning `DEBUG_KILL` off.** It was the cheapest source on the list (~45 B) and KC asked for it
  specifically on 2026-08-24 to test the cleared-deck floor. **It was not needed and is still on.**
  (Correction, 2026-08-25: its ~45 B ride in `colourMap`'s `ALIGN` pad — `layer-14-visual.md` has
  the right reading — so turning it off grows the *pad*, not the gauge.)
- **Deleting `colourMap`'s `ALIGN`.** Already measured and rejected on 2026-08-24 — `tiledefs.asm`
  aligns next and pads by the same amount. Not re-tried.
- **Moving anything between banks.** Would have been a deviation needing KC's agreement, and the
  dead data made it unnecessary.

### What is left

- **17 B of `colourMap` padding**, free to anything assembled before that `ALIGN` — the
  `src/consolesel.asm` / `src/dbgkill.asm` trick. Past 162 B the `ALIGN` rounds up and costs 256.
- **`DEBUG_KILL` off, ~45 B of pad budget** (not gauge bytes — see the correction above), KC's call.
- **Bank 7's 314 B**, reachable from bank 4 only through a paging shim — which the console already
  has, so the pattern is proven. T4 wants ~50 of it.
- **Main RAM was 3 B at the time** and the tightest region in the machine. **The RAM recovery
  pass (2026-08-25, [`ram-pass.md`](ram-pass.md)) has since taken it to 639 B** — the reserves
  listed here are recorded history, not the current hunt list.

### Verified

- **The instruction stream is unchanged**: both builds' beebasm listings reduced to
  (mnemonic, addressing class) and diffed — 22,954 instructions, **zero differences**. The change is
  pure data removal plus padding.
- Regenerating `src/data/` left `chardata.asm`, `colours.asm`, `tiledefs.asm` and `plandata.asm`
  byte-identical; only `levels.asm` changed.
- Main RAM, banks 5, 6 and 7 all ended exactly where they did at the time. (Post-RAM-pass they end `&2D81`, `&BDA6`, `&BF8E`, `&BFF9` — measure, do not quote this line.)
- **In jsbeeb, end to end**: boot → title → briefing → play; a diagonal scroll with the play buffer
  diffed against a forced `RedrawAll` (`SprDrawAll` and BOTH `SprDrawTr` call sites poked out — three JSRs), **0 diffs of
  10,240**; **C** clearing the deck through `DrKillDroid` with the cleared-deck recolour and the 500
  showing on the panel; a debug deck hop; the console opened from a console tile, all three of its
  pages drawn (droid database with portrait, deck plan off the tile map, ship cutaway) and closed
  through entry 0; a lift ride to another deck; **ESCAPE** to game over, the high-score entry, and
  back round through the title to the briefing — which exercises the DFS-workspace seam and all
  seven disc loads after the change.
- **`DEBUG_MAPGUARD` no longer blows the one-page assert** (the conditional pad fixed that), but it
  still does not build: it is now honestly **19 bytes over bank 4**. Recorded rather than chased —
  `PLAN.md`'s broken-debug-builds row can be narrowed by that much, and it is close enough to be
  worth another look when convenient.

## 5. What was built

All five tasks, in one sitting, after §4's space pass. **Order taken: the enabling bank move, then
T4 (the screen), then T1/T2/T3 (the hook), then T5 (the split).** The doc's original suggestion put
T4 first for its own sake; in the event the main-RAM move had to come first, because nothing else
would fit.

| | what landed | where |
|---|---|---|
| T1 | 500 for a deck, `sndFx1 = $17` | `DroidsUpdate`'s clear hook, bank 4 |
| T2 | `shipClear`, raised at the hook, acted on in the main loop | bank 4 + the code image |
| T3 | 2,000 for a ship, ten `AddScore #200` | the same hook |
| T4 | `ShowShipClear` as `IS_SCR_CLEAR`, a fifth information screen | `infoscr.asm`, bank 7 |
| T5 | `GameStart` split at the C64's own seam so `EnterShip4` is callable | `droid.asm`, bank 4 |

### T4 cost almost nothing, and that is the point

`ShowShipClear` (`$3816`) is `GotoHires`, `ClearGameScreen`, `ShowRobotType`, `BuildIntroSprites`,
`PrintTokenString` — which is `IsStart`'s `is_st_norm` path instruction for instruction. So the
screen is **five table entries and a token list**, and not one line of drawing code.

**The token list is sixteen bytes, not the ten §1 claimed.** `$6DCE` is two sentences: the listing
prints the first as one `.BYTE` run ending `$FE`, the second (`$6DD8`) as another, and the `$FF`
that ends the list is at `$6DDD`. The full text is *"congratulations! ship is now clear of all robot
activity. bonus of 2000 awarded."* — the second sentence is what announces T3's payout.

### T5 was a re-labelling, exactly as §3 hoped

`GameStart` now writes `shipLevel = 0` — **`$1255`'s own value**, where the port used to write 1 —
and falls through into `.EnterShip4`, whose first act is the `INC` that is `NextLevel`'s at `$129E`.
The split point is not a judgement call: **above it is what a new game needs and a new ship must not
have**, and the decisive member of that set is `CombatInit`, *which zeroes the score*. Call it on a
ship transition and the two thousand points just awarded go with everything else the player earned.
That is why the C64 keeps `StartGame` and `_entership` apart, and it is the whole reason T5 existed.

**`_entership` falls straight into `NewShipInfo` at `$12C7`, before `BuildLevel`** — which §1 did not
record. So a ship transition shows the "prepare to board Robo-*&lt;ship&gt;*" screen too, and the port
already had it as `IS_SCR_001`. `InfoHigh`'s new-ship arm reproduces `GameStartInfo`'s sequence for
it: `infoActive` first so `LoadDeck`'s `ReframeView` is a no-op, then `pmShip` by hand.

**What carries over, and it surprises:** `$1289` does *not* reset `droidType`. The player keeps the
droid they captured into the next ship, at energy 7 and in the materialise mode.

### Two bugs found on the way, both pre-existing

1. **The string table was one string short.** `export_strings.py` stopped at `count - 1` on the
   stated reasoning that the C64 never prints its last string. It does: **string 248 is "awarded"**,
   the last word of `ShipClear_txt`, and this screen is the first thing in the port to ask for it.
   Token `$F8` was landing on the sentinel, so the screen read *"Bonus of 2000 ."* with a
   word-shaped hole in it. `CON_STR_COUNT` 248 → 249, `CON_STR_BYTES` 1542 → 1549.
   **Regenerating needs `export_strings.main()` called explicitly — the script has no `__main__`
   block, and `build.ps1` does not run the exporters anyway.**
2. **`hsArmed` is bank 7's, and the first attempt wrote it from bank 4.** `hstable.asm` assembles
   into the `PARXFER` block, so `hsArmed` lives at `&B525` *of bank 7*. `InfoHigh` runs in main RAM
   with **bank 4** paged — `InfoCall` puts it back before the dispatch — so `STA hsArmed` there
   corrupted a byte of bank-4 code and armed nothing: the game ended straight onto the title with no
   high-score entry, silently. **Moved into `IsDone`, in bank 7, where the game over already arms
   it.** This is precisely the failure `bufcore.asm`'s header warns about, and nothing diagnoses it.

### The numbers after

| region | before the layer | after |
|---|---|---|
| bank 4 | 105 B | **3 B** |
| main RAM | 3 B | **2 B** (26 before DECISION 5 was revised) |
| bank 7 | 314 B | **314 B** (the screen fell into `planInk`'s `ALIGN` hole) |
| bank 5 / bank 6 | 1,033 / 4 | unchanged |

Main RAM took DECISION 1's 69 bytes back from `DEBUG_DECK` and has now spent nearly all of them:
the ship-clear arm, `InfoHigh`, and DECISION 5's cap and name counter.

### Verified in jsbeeb

The ship clear was reached by poking `shipNumDroids` to the deck's own droid count and pressing
**C**, so `DrKillDroid` takes the count to zero through the real kill path rather than a shortcut.

- **The deck payout**: the score climbs 500 over the following passes, `$17` posted.
- **The ship-clear screen**: the C64's full sentence, with the player's droid from the portrait pool.
- **The progression**: `shipLevel` 1 → 2, a fresh 119-droid roster from `NewShipDroids`, the
  "prepare to board" screen, and ship 2's first deck playing — with the score carried, not reset.
- **Ship 8 and beyond** (DECISION 5): with `shipLevel` and `shipName` both forced to 8, clearing
  the ship left `shipLevel` at **8** (the cap held), cycled `shipName` to **1**, built a fresh
  119-droid roster and played on. The game did not end.
- **`shipLevel` = 1 on a cold start**, so the `STA #0` + `INC` split reproduces the old value.
- **The relocated deck hop**: deck 5 → 6 → 5, drawing correctly both ways.

---

## 6. Decisions

1. **`DEBUG_DECK`'s arm moves to bank 4** (`src/dbgdeck.asm`), because T2's main-loop arm wants ~18
   bytes of `&1100-&3000` and the default build had 3. A shipping build has 72 — `DEBUG_DECK` alone
   costs 69 — so without this the layer would have been unbuildable in the one configuration that
   can reasonably test it: clearing a ship means clearing all sixteen decks, and without the hop
   that is minutes of lift rides per attempt. The same trade `dbgkill.asm` made, one size up.
   **NOT in `colourMap`'s padding**: 69 more would push the `ALIGN` past the page and cost 256 at a
   stroke, so it is assembled after the aligns and simply spends the bank's own free space.
2. **The ship-clear screen is a fifth `IS_SCR_*`**, reusing `infoscr.asm`'s printer, geometry and
   the portrait pool, with `isTypeFor = $FF` — the player's own droid, as `$381E` does.
3. **`InfoCall` gains a fourth continuation, `IS_ACT_NEWSHIP`**, and its dispatch tail moved to
   `InfoHigh` in the code image: the low overlay had one byte free and the arm wanted six, so the
   overlay JMPs out — a JMP for a JMP, costing that region nothing.
4. **A dedicated `shipClear` byte, not a ported `notInDeck`.** The port reaches the lift, the console
   and the transfer by other means, so there was no shared exit flag to hang this on, and inventing
   one would have meant surgery on three working subsystems for no behaviour the port lacks.
5. **The game never ends; the difficulty stops at ship 8 and the names cycle.** *KC 2026-08-25,
   replacing an earlier decision to end the game after eight ships — that was built, verified and
   then reversed, and nothing of it remains.*

   **What the C64 does, exactly.** `NextLevel` `$15E8` increments `shipLevel` and takes it straight
   back if it reached 9:

   ```
   15F1  INC shipLevel
   15F3  LDA shipLevel
   15F5  CMP #9
   15F7  BCC _2
   15F9  DEC shipLevel      ; hard cap at 8
   ```

   So the level — and with it the difficulty: `NewShipDroids`' `ADC shipLevel`, `combat.asm`'s
   `SBC shipLevel` and the fire rate's `CMP shipLevel` — stops at 8, and the game runs for ever.

   **One deliberate improvement on it.** Because the C64 pins `shipLevel`, and the console's ship
   name is `(shipLevel - 1) AND 7`, *the name is pinned too*: on the original the eighth ship and
   every ship after it carries the same name. KC asked for the names to keep cycling under the
   frozen difficulty, so the port splits what the C64 conflates:

   - **`shipLevel`** caps at 8 and drives the difficulty, exactly as `$15F5` does.
   - **`shipName`** counts 1-8 and wraps back to 1, and is the only thing that names the ship.

   `PanelTick`'s `pmShip` mirror now carries `shipName` rather than `shipLevel`, so both readers —
   the console's ship line and `IsShip`'s token patch on the "prepare to board" screen — cycle with
   no change of their own. Holding `shipName` in 1-8 is what makes that free: the console already
   masks with `AND 7`, and `IsShip`'s unmasked `+ 104` stays inside the eight names.

   **The cap is applied in main RAM, not in `EnterShip4`.** `EnterShip4` INCs `shipLevel`, so
   `InfoHigh` pulls it back to 7 when it is already 8 and the INC lands on 8 again. It must happen
   *before* the call, because `NewShipDroids` reads `shipLevel` to pick the droid classes — and it
   is on that side because bank 4 has two bytes left and the code image had room.

6. **An already-cleared deck shows the cleared floor but does NOT replay the event.** KC heard the
   power-down effect on every deck entry in playtesting, and asked whether the C64 does that. It
   does not, and the original is explicit about it — `$1359`, the deck-entry path:

   ```
   1375  LDX #$F / STX numDeckDroids   ; the whole table, like our DR_SLOTS
   1385  JSR InitDeckDroids            ; place the deck's droids
   1388  LDA xfer_plySpriteX           ; how many were placed
   138A  BNE _ed_2
   138C  LDA #1 / STA numDeckDroids    ; NONE: force 1...
   1390  BNE _ed_3                     ; ...and SKIP RunDroids entirely
   _ed_2:
   1392  JSR RunDroids
   _ed_3:
   1395  JSR InitColors                ; unconditional
   ```

   So the two halves are deliberately separated. **`InitColors` runs on every deck entry and reads
   `numDeckDroids`** (`$27F1`), which is why a deck that is already clear comes up in the cleared
   colours — KC's blue floor is faithful. But the payout, the effect and the colour *change* all
   live inside `RunDroids`, and the C64 skips `RunDroids` outright when nothing was placed, so the
   event fires once when the last droid dies and never again.

   The port had no equivalent test: `DroidsInit` set `drCount = DR_SLOTS` unconditionally, so the
   next pass's compaction landed on 1 and re-ran everything — the sound, the colour **and another
   500 points**, every time you walked back onto a cleared deck. A scoring exploit as well as a
   noise.

   **The fix, and it is cheaper than the original's.** `DroidsInit` now assumes the deck is clear
   (`drCount = 1`, `deckClear = 1`) and lets the first placement say otherwise (`drCount =
   DR_SLOTS`, `deckClear = 0`). A count of 1 makes `DroidsUpdate`'s guard return every pass, so the
   compaction never runs and the arm is never reached — the same outcome as skipping `RunDroids`,
   without needing `InitDeckDroids` to report a count.

   Two consequences worth knowing:
   - **`DroidsInit` moved ABOVE `ReframeView` in `LoadDeck`**, because `ReframeView` ends in
     `RedrawAll` which calls `SetPalette`, and `DroidsInit` is now what decides the floor. The
     `deckClear = 0` that layer 14 put at the top of `LoadDeck` is gone with it — `DroidsInit` owns
     the flag either way now, which is simpler than the ordering dance it replaced.
   - **`di_loop`'s branch went out of range** and is now `BEQ` + `JMP`, the same way the copy-down
     block in `DroidsUpdate` already had to.

   **Verified**: a populated deck enters with its own colours and no event; clearing one fires once
   (score 0 → 975 on that deck, floor blue); leaving and returning leaves the score at **975
   unchanged** with the floor still blue and no effect. Bank 4 is down to **2 bytes**.

7. **The ship reset, audited against `_entership` line by line.** KC found a new ship starting on
   red alert, and asked what else the reset was missing. `$1289`-`$12CD`, every store:

   | C64 | port | |
   |---|---|---|
   | `$128B`-`$1291` xSpd/ySpd = 0 | the "standing still" block | ok |
   | `$1293` **Alert = 0** | **was missing** | **fixed** |
   | `$1295` droidSpriteImage[0] = 0 | `SprInit` puts the player back in slot 0 | n/a |
   | `$1298`/`$129B` droidEnergy[1], droidSprNum[1] = 0 | `DroidsInit` rebuilds the table | ok |
   | `$129E` NextLevel | `INC shipLevel` + `NewShipDroids` | ok |
   | `$12A1` moveMode = `$80` | `MM_MOBILE` = `&80` | ok |
   | `$12A7` **droidEnergy[0] = 7** | **was missing** | **fixed** |
   | `$12AA` droidSprNum[0] = 7 | player is slot 0; `drSprNum[0]` unused | n/a |
   | `$12AF` numDeckDroids = 2 | `DroidsInit` sets `drCount` | ok |
   | `$12B4` dType = droidType | `pmType` mirror | ok |
   | `$12BE` deckNum random 4-7 | `DrRandom AND 3 + DECK_START_LO` | ok |
   | `$12C2` prevDeck = `EOR $FF` | not ported; `LoadDeck` is unconditional | documented |
   | `$12C4` FindStrings, `$12CA` ClearSubGameData | the port scans; it has no string index | n/a |
   | `$12CD` BuildLevel | `LoadDeck` | ok |

   **Both misses have the same cause**: `CombatInit` does them, and `CombatInit` is above the T5
   split. It zeroes `alertLvl` and sets `drEnergy` to `CB_ENERGY_FULL` on a new game — so a *ship*
   transition, which must not call it (it would wipe the score), inherited the last deck's alert and
   the last ship's energy.

   Two names in the annotated listing needed checking rather than trusting. `droidSprNum` looked
   like it might be `maxEnergy`, since `$12A5` sets it and `droidEnergy` to 7 together — `$158F`
   shows it is not, and `maxEnergy` is genuinely untouched here, so the player arrives on 7 against
   whatever ceiling the droid they are riding has. And `ClearSubGameData` sounds like it clears
   transfer state; `$377E` shows it only zeroes the `FindStrings` index, which the port has no
   equivalent of.

   **`droidType` is NOT reset**, on the C64 or here: the droid captured on the last ship comes with
   you, at 7 energy. KC 2026-08-25 confirmed porting `$12A7` as it stands.

   **Where they live.** The alert reset joined `EnterShip4`'s existing A = 0 run in bank 4 (three
   bytes); the energy went into `InfoHigh`'s `ih_ship` in main RAM, because bank 4 had three bytes
   left and it needed five. `DroidsInit` deliberately leaves entry 0 alone, so after the call is as
   correct as inside it.

   **Paid for by two provable rewrites**, both of a `LDA #n : STA` where the flag's value was
   already known from the branch immediately above: `dbgdeck.asm`'s two latch sets became `INC`
   (+4 bank 4), and the main loop's `shipClear` clear became `DEC` (+2 main RAM).

   **Verified**: `alertLvl` forced to `&C0` and the ship cleared reads **0** on the new ship;
   energy 62 before, **7** after, with `maxEnergy` unchanged at 58; `shipLevel` 2 and a fresh
   119-droid roster.

---

## 6a. The wash's length was the wrong loop's — fixed 2026-08-29

**KC:** "the game over static screen goes on for way too long. the C64 version is only a second
or so, if that." It was `GO_HOLD = 88` passes at 25 Hz — **3.5 s**.

**88 was EndGame's OTHER counter.** `$3802 LDA #$58` seeds `xfer_plySpriteX` for the `_5` loop at
`$3806`, which is the hold on the **GAME OVER / 999 page**, *after* the wash has burnt out — and
the port already has that one, as `infoscr.asm`'s `IS_HOLD`. The wash is `_3`, `$37C1`–`$37D9`,
and it counts in `frameCount`: `$37BB` seeds it with the paint loop's leftover `dest+1` = `$4C`
= 76 and the loop runs `INC`/`BMI` until bit 7 sets at 128, so the body runs **128 − 76 = 52
iterations**, always. The port had been giving the wash the page's counter.

**The conversion is [DECISION 3]'s, unchanged.** That note costs the 999 page's iteration —
`DelayScore(32)`, two nested busy loops — at about 41,000 cycles ≈ 0.04 s, which is why 72 of
them port to 72 passes at 25 Hz. The wash's `DelayScore` takes `Y = $10`, **exactly half**, so one
wash iteration is ~20,500 cycles ≈ 0.02 s — half a port pass. **52 half-passes = 26 passes =
1.04 s**, against the C64's 52 × 0.0208 = 1.08 s. Same route, same arithmetic, and it lands where
KC's ear put it.

**And then the boil rate went up with it, same day.** At one row a pass, 26 passes is only a
screen and a half of churn — KC: "increase the row-per-pass rate". `GO_ROWS` is that dial, now
**4**: the screen turns over every four passes, six and a half times across the wash, which is as
near the C64's every-cell-every-iteration as repainting gets.

**The frame lock is the ceiling, and it binds here in a way it does not elsewhere** — `overTick`
counts *passes*, so a pass that overruns two fields would stretch the 1.04 s straight back out.
The budget is a two-field pass at 2 MHz = **80,000 cycles**. `GoWashRow` is 40 cells, each an
`XfRand` and a 16-byte copy loop at ~19 cycles a byte — ~340 a cell, ~13,600 a row. Four rows
≈ 54,000, which fits alongside the rupture and the modal tail; eight would be ~109,000 and would
not. `GoWashStart`'s own 16-row paint is exempt: one-off at entry, and the lock is a floor there.

**That arithmetic was wrong twice before the emulator settled it** — first a per-row figure too
low, then a per-pass budget of 40,000 cycles instead of 80,000 (a 50 Hz field at 2 MHz is 40,000
cycles, and a pass is two of them). The measurement is the authority: on a real ESCAPE game over
`overTick` falls **11 → 1 across exactly 20 frames** — ten passes, two fields each, no overrun,
and the wash still 52 fields wall-clock. Signed off by KC's eye: "much better".

**And the roar's re-post went with it.** `GoWashTick` re-posted fx `$F` every time the boil
wrapped, justified in a comment as "near the C64's every-76-frames refire" — but there is no
refire: `$37BD`/`$37BF` posts it **once**, before `_3`, and the loop never touches `sndFx1` again.
It was audible twice over, because `goBoil` leaves `GoWashStart` at `$FF` and the first tick
wrapped it to 0, restarting the roar one pass after `GoWashStart` had just posted it. One post
covers the wash regardless: effect 15 is a single 192-tick segment, 3.8 s at the 50 Hz sound tick.
Seven bytes of bank 7, absorbed by `plandata.asm`'s `ALIGN` pad — `PARXFER` is the same size.

**Verified in jsbeeb** on a real ESCAPE game over: `overTick` decrements exactly once per **2
fields** (8 → 1 across 14 frames), so 26 passes is **52 fields = 1.04 s**, and `overPhase` drops
to 0 with the 999 page drawing behind it.

## 7. Open

- ~~**The high-score entry overlaps the congratulations screen's name line.**~~ **Moot since DECISION 5 was revised**: clearing a ship no longer goes anywhere near the high-score entry, so it cannot be reached. Kept because the underlying fact still holds for anything else put in front of that screen — `HsRun` does not clear;
  it writes its title and prompt onto whatever page is already there, as `$E4E5` does. On the game
  over that works, because `EndGame`'s top line is the twelve characters of "Transmission" at column
  13 and the 24-character title covers it completely. **This page's top line is thirty-one
  characters** — "Unit type 001 ~ Influence device" — so its first and last few show and the screen
  reads *"U Lowest Score of the Day! ice"*. Everything else on it is correct.
  **A wipe of that row was tried and reverted.** Blanking buffer row 1 with forty `DbGlyph` spaces
  before arming left the *whole* play area blank and the entry hung waiting for initials, so the
  cause is not understood and the fix is not as simple as it looks. Reverted rather than shipped
  half-working; the overlap is cosmetic and only on the win.
- **The score drains at one point a pass**, which is `DoScore` and the original's own feel — but the
  port runs its loop at 25 Hz where the C64's runs faster, so 2,000 points take about 80 seconds to
  tick up on the panel. Faithful, and possibly too slow to read as a reward. KC's ear.
- **The deck payout's `$17` and the screen's `$B`** are posted back to back, as `$17E9` and `$1282`
  are. Not yet listened to.
- **Bank 4 had 3 bytes and main RAM 2 when this layer closed.** Superseded by the RAM recovery
  pass (2026-08-25): 51 and 639 — see [`ram-pass.md`](ram-pass.md) and `CLAUDE.md` for live figures.
- **A whole ship has never been cleared by playing.** Every run above forced the count; the honest
  end-to-end test is sixteen decks of real play.
