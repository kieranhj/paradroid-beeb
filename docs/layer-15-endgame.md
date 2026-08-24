# Layer 15 — the endgame: clearing a ship, and the next one

**Scoping document, 2026-08-24. Nothing here is built — except §4's space pass, which ran the same
day and unblocked the rest.** It exists because KC asked whether the
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
  specifically on 2026-08-24 to test the cleared-deck floor. **It was not needed and is still on**;
  those 45 bytes remain in reserve if bank 4 is ever squeezed again.
- **Deleting `colourMap`'s `ALIGN`.** Already measured and rejected on 2026-08-24 — `tiledefs.asm`
  aligns next and pads by the same amount. Not re-tried.
- **Moving anything between banks.** Would have been a deviation needing KC's agreement, and the
  dead data made it unnecessary.

### What is left

- **17 B of `colourMap` padding**, free to anything assembled before that `ALIGN` — the
  `src/consolesel.asm` / `src/dbgkill.asm` trick. Past 162 B the `ALIGN` rounds up and costs 256.
- **`DEBUG_KILL` off, ~45 B**, KC's call.
- **Bank 7's 314 B**, reachable from bank 4 only through a paging shim — which the console already
  has, so the pattern is proven. T4 wants ~50 of it.
- **Main RAM is still 3 B** and is now by a wide margin the tightest region in the machine. Nothing
  in this layer should want it.

### Verified

- **The instruction stream is unchanged**: both builds' beebasm listings reduced to
  (mnemonic, addressing class) and diffed — 22,954 instructions, **zero differences**. The change is
  pure data removal plus padding.
- Regenerating `src/data/` left `chardata.asm`, `colours.asm`, `tiledefs.asm` and `plandata.asm`
  byte-identical; only `levels.asm` changed.
- Main RAM, banks 5, 6 and 7 all end exactly where they did (`&2FFD`, `&BBF7`, `&BFFC`, `&BEC6`).
- **In jsbeeb, end to end**: boot → title → briefing → play; a diagonal scroll with the play buffer
  diffed against a forced `RedrawAll` (`SprDrawAll`/`SprDrawTr` poked to `RTS`), **0 diffs of
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

## 5. Suggested order

1. **T4**, the screen — bank 7 has room, it reuses three existing siblings, and it is the visible
   half of what was asked about.
2. ~~**The space pass**~~ — **DONE 2026-08-24**, bank 4 has 105 B. See §4.
3. **T1 + T2 + T3** — one hook, one flag, one payout each; a single sitting once there is room.
4. **T5** — last, alone, with its own verification.

---

## 6. Open decisions

1. **Does clearing the ship advance to the next one (as the C64 does) or end the game?** Everything
   else follows from this. The port can currently be neither won nor advanced.
2. **T2's flag**: a dedicated `shipClear`, or `notInDeck` ported as the shared exit flag?
3. **T4's picture**: the existing portrait pool?
4. **After ship 8** — keep raising the difficulty with the name wrapping, as the C64 does?
5. ~~**`DEBUG_KILL` off to pay for it?**~~ — **closed 2026-08-24: not needed.** The space pass found
   the room elsewhere and `DEBUG_KILL` stays on. See §4.
