# Layer 10 — the transfer minigame

**Status: researched and planned 2026-08-16 on branch `layer10-transfer`, off `layer9-hud`.
Nothing of the game logic is built.** This document is the research, which is the expensive half:
where the code and data are, what the rules actually are, and the one problem that has no
straightforward answer on this machine.

---

## 1. Where it all is

| | | |
|---|---|---|
| `Capture` | `$229D` | entered from `GameLoop+6D` when `xferDroid` is set by `DoCollision`'s `_ply_droid` arm at `moveMode == 0` |
| `SubGameSelectSide` | `$E016` | draws the board and picks the colours |
| `doSubGame` | `$2166` | the loop: one player half-turn, one CPU half-turn, per iteration |
| `xfer_GetMove` | `$2109` | reads the stick into `xfer_yWant` |
| `xfer_DoMove` | `$1D75` | moves the pulser cursor, `xferRemovePulser` / `xferDrawPulser` |
| `xfer_PlayLeft` / `xfer_PlayRight` | `$1E06` / `$1E5E` | three `xfer_DoColumn` calls each |
| `xfer_DoColumn` | `$1EB6` | **the whole rule set** — 12 rows of one wire column |
| `xferDrawCBar` | `$2057` | the central control bar, and who is winning |
| `xferDoCounter` | `$20DA` | the countdown that ends it |
| `xferCheckEnd` | `$2153` | |
| `FinishTransfer1/2` | `$21CF` / `$2260` | you take the droid, or you are burnt out |

Board data, all confirmed present in the listing:

| | | |
|---|---|---|
| `SubGameTopLines_dat` | `$E613` | 120 bytes — three rows of 40 |
| `SubGameLine_dat` | `$E68B` | 40 bytes — **one row, repeated twelve times** |
| `SubGameBottomLine_dat` | `$E6B3` | 40 bytes |

## 2. The board

The twelve middle rows are all the same row, which is the thing to understand first:

```
 col   0  1  2  3  4 ...17 18 19 20 21 22 ...35 36 37 38 39
       .  FD .  F6 F1...F1 F9 F8 F8 FA F2...F2 F6 .  F3 .
             ^^          ^^ ^^^^^ ^^          ^^
             player      |  the    |          CPU
             bus         |  centre |          bus
```

so each of the twelve rows is a wire running from the player's vertical bus at column 3, right
along columns 4-17, into the central result bar at 19-20, and the mirror of that from the CPU's bus
at column 36. `SubGameSelectSide` colours column 3 and 18 in the player's colour, 21 and 36 in the
CPU's, and 19-20 alternately, which is the bar's starting even split.

**Fifteen distinct characters**, all from the **`$7800` charset** — the same one the deck tiles use,
confirmed by rendering them: `$F1`/`$F2` are short horizontal wire stubs, `$F5`/`$F6`/`$F7` the top,
middle and bottom of a vertical bus, `$F8` a solid block, `$F9`/`$FA` junctions, `$D0`/`$D1`/`$FB`-
`$FE` the counter and frame pieces around the top.

`xfer_PlayLeft` calls `xfer_DoColumn` with Y = **6, 10 and 14**, and `xfer_PlayRight` with the
mirror. Those are the three **stages** along each wire: a pulser advances one stage per turn and
reaches the centre from stage 14. `dest` starts at `$49E0`, which is screen row 12, and the routine
walks *down* twelve rows. `src` is a 16-byte array per stage (`$4400`, `$4410`, `$4420`, `$4430`
for the player; `$4470` and neighbours for the CPU) holding a **pulser count per row**.

## 3. The rules, from `xfer_DoColumn`

The whole game is in one routine. Per row, with `(src),Y` the count at that row:

| | |
|---|---|
| count `= 0` | nothing on this row |
| count `< 0` | `_6`, the other side's |
| the cell already holds **your** pulser char | `_auto` |
| otherwise | decrement the count and dispatch on the **character in the cell** |

and the dispatch is the gate set:

| character | |
|---|---|
| the other side's pulser char | `_terminator` — the two annihilate |
| `$F5` vbar top | `_joiner` |
| `$F6` vbar middle | `_splitter` — `xfer_PutSplitter`, which is what makes one pulser become two |
| `$F7` vbar bottom | `_joiner`, already handled |
| anything else | `xfer_Colorize4` then `xfer_put1` — **claim the segment and advance** |

`xfer_Colorize4` is the ownership write, and it is four bytes of **colour RAM**. That is the
problem in §5.

## 4. What has to be ported, in order

1. **The board data** — 200 bytes, byte-identical, plus the fifteen characters.
2. **The board render** — the static layout into the play area.
3. **`xfer_DoColumn`** and the six `xfer_Play*` calls around it. This is the game.
4. **`xfer_GetMove` / `xfer_DoMove`** — the cursor on your bus.
5. **`xferDrawCBar`**, **`xferDoCounter`**, **`xferCheckEnd`**.
6. **`FinishTransfer1/2`** — take the droid, or burn out into a 001.
7. **The CPU opponent.** `xfer_CpuLevel` against `xfer_PlyLevel`, both set at the end of
   `SubGameSelectSide` from the droid classes, is the difficulty.

## 5. The problem: ownership is COLOUR RAM, and MODE 1 has none

The C64 shows who owns a wire segment by writing **colour RAM per character cell** — yellow for the
player, purple for the CPU. `xfer_Colorize4` does exactly that and nothing else. In MODE 1 there are
four logical colours for the whole screen and no per-cell attribute at all, so this does not port.

Three ways out, and none is free:

| | |
|---|---|
| **A. Three copies of each character** | one per owner — neutral, player, CPU — drawn in logical colours 1, 2 and 3. 15 chars × 3 × 16 B = 720 B. Ownership becomes a **character change**, so `xfer_Colorize4` becomes a character write and the rest of the logic is unchanged. **This is the recommended route** |
| B. Palette split per column | the rupture already reprograms the ULA mid-frame; a fourth cycle could give the two halves different palettes. Does not work — ownership varies per *cell*, not per half |
| C. Give up the colour and show ownership by shape | a filled versus hollow wire. Cheapest, and loses the instant read that makes the game playable |

Route A also decides where the characters live: they are **not deck-coloured**, unlike the tile
charset, so they can be a fixed converted set shipped like Layer 9's text font rather than built by
`BuildCharset`. That keeps `charSlot` and the 137-character remap alone, which matters — extending
that set pushes the charset at `&0400` from 2,192 bytes to 2,432 and into `&0D00`, which is the
MOS's NMI area.

## 6. Geometry: the board is 16 rows and the play area is 15

`SubGameSelectSide` clears one row then writes 3 + 12 + 1 = **16 rows**, into screen rows 9-24.
Our play area is `PLAY_VIS_ROWS = 15`. Options, in preference order:

1. **Drop one of the twelve middle rows** — eleven wires instead of twelve. The rows are identical
   and the count is not referenced anywhere except `xfer_DoColumn`'s `LDA #12`, so this is a
   constant change. It makes the board slightly easier for whoever has fewer pulsers.
2. Use the panel's two text lines for the counter and the top frame, and the play area for the
   twelve wire rows plus the bottom. The two are not contiguous — there is a three-row gap between
   them — so the board would be visibly split.
3. Change `PLAY_VIS_ROWS`. It is fixed by the rupture and the 10K wrap; see `CLAUDE.md`. No.

**Recommendation: option 1**, and say so in the layer's own doc when it is built.

## 7. Where the code goes

Bank 6 has ~2,040 bytes free and already holds Layer 9's text engine, which the transfer game wants
for its counter and its end-of-game text. Bank 4 has ~1,400. Neither is enough for the whole
minigame, so this needs the same treatment Layer 9's console got — or, better, a **fourth bank**.
The target is "3 × 16K sideways RAM banks"; a fourth would be a target change and is KC's call.

**The cheapest answer is probably that the transfer game does not coexist with the blitter.** It
runs with the deck suspended and no sprites at all, so it could take over bank 5 or 6 wholesale if
it were a separate disc file `*LOAD`ed on entry and the sprite bank reloaded on exit. That costs a
disc access at each transfer, which is a real gameplay cost on a floppy, and is the thing to think
about first.

## 8. What was built on this branch

The plan, and nothing else. §5, §6 and §7 are all decisions that want KC's eye before code goes in,
and two of them — the ownership model and where the code lives — are large enough that guessing
wrong would waste a session.
