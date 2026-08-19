# Layer 7 — Combat

**Status: DONE — 7a–7f all landed, 2026-08-15/16.** Each stage's section below carries its own
completion note; the plan text is kept as written. This is the layer that makes the port a game rather than a
walkthrough: the player shoots, droids shoot back, things die, the score moves, the Alert level
rises, and standing on a recharge pad puts energy back.

The C64 routines it covers:

| | | |
|---|---|---|
| `DoMoveMode` | `$31B9` | the Mobile / Weapon / Transfer machine the fire button drives |
| `DoFire` | `$33B5` | the player pulls the trigger — bullet sprite, direction, fire delay |
| `MovePlyFire` | `$32D9` | the player's bullet, one pass: move, animate, wall test |
| `SpriteHitWall` | `$336F` | a bullet's own wall test, in sprite coordinates |
| `DoEnemyFire` | `$3450` | a droid fires: a new droid-table entry in mode 1 |
| `dMd1_bullet` | `$1849` | a bullet's pass — ages, animates, dies on a wall |
| `dMd2_explosion` | `$17F4` | twelve frames, drifting, then the slot is freed |
| `DoCollision` | `$19EA` | picks the pair, then the player arms: bump damage, bullet, explosion |
| `DoCollision2` | `$1B51` | the `CollisionType` matrix `$6D6D` and its six arms |
| `PlyFireEnemy` | `$1C0F` | player bullet damage, scaled by `weaponType` against droid type |
| `EnemyFireEnemy` | `$1BF6` | friendly fire, which the original very much has |
| `KillDroid` | `$1C41` | raise Alert, score by type, hand over to `ExplodeSprite` |
| `ExplodeSprite` | `$1BCA` | type := `$40`, off the ship roster, into mode 2 |
| `AddScore` | `$3E94` | 4-byte BCD with the `scoreAdd` accumulator |
| `DoAlertAndAging` | `$3E32` | Alert decays, `maxEnergy` ages down by droid class |
| `DoCharUnder` | `$2E7B` | the recharge pad, and the fire-gated lift and console countdowns |
| `Disruptor` | `$1B37` … | weapon type 3, the area weapon |

---

## Five things that shape the whole layer

**1. Droid-table entry 0 is the PLAYER, not a sentinel.** `droid.asm`'s header says "entry 0 is a
sentinel", which is true of everything Layers 5 and 6 do — `RunDroids` starts at index 1 and its
deck-cleared test is `CPY #1`. But the C64 reads `droidEnergy`, `droidType` and `droidFireDelay`
*unindexed* all through the combat code, and unindexed is index 0: that is the player's energy, the
player's type and the player's fire delay. `BlowInto001` (`$1573`) writes exactly those three.
Layer 7 is where entry 0 stops being spare and starts being the player. **Correct the header when
this lands** — it is the kind of note that is right until it silently is not.

**2. The C64 has eight sprites and we have seven.** Slot 7 is the player, slot 0 is *the player's
bullet*, slots 1–6 are the pool `FindFreeSprite` (`$32A8`) searches. Our pool is
`SPR_SLOTS = 7`, slot 0 the player and 1–6 the droids — faithful for everything up to here, one
short from now on. **`SPR_SLOTS` goes to 8, and slot 7 becomes the player's bullet**, which is not
a droid-table entry on the C64 and should not be one here. The save area for it is
`SPR_SAVE + 7*256 = &3700`, which the memory map already lists as free and is exactly the page
needed — `ASSERT SPR_SAVE + SPR_SLOTS * 256 <= PANEL_ADDR` still passes.

**3. Bullets and explosions cost no extra sprites.** An enemy bullet is a droid-table entry with
type `$25` and an explosion is one with type `$40`; the mode is the top bits of the type and
`DroidRun`'s dispatch already decodes it and returns early for modes 1 and 2. Both draw out of the
same pool of six, so **a bullet takes a droid's slot** — the pool never grows and the sprite count
per pass is unchanged. What changes is the cost *per* slot, which is finding 4.

**4. Explosions cannot be compiled.** Twelve frames (`SpriteImage $39`→`$44`, artwork `$4E40`–
`$50FF`), dense across the full 24 × 21 — the late frames are a filled starburst. A compiled dense
row is ~10 bytes of 6502 a byte, so one frame is ~1.4 K a shift and twelve frames across four
shifts is far past a bank, never mind two. So effect sprites go on a **generic interpreted path**
with a per-frame bounding box, and that path is the single largest piece of new code in the layer.
Sprite banks 5 and 6 stay exactly as they are.

**5. The damage arms attach where the movement arms already are.** `DrCollide`/`DrCollided` in
`droid.asm` is `DoCollision`'s movement half, written in Layer 6 with the damage deliberately left
out and the note saying so. Layer 7 does not restructure it; it adds the arms and the
`CollisionType` matrix that selects between them.

---

## The work

Each stage ends with something visible, as the layer rule requires.

### 7a — Entry 0 becomes the player ✅ **DONE 2026-08-15**

`src/combat.asm`, in **main RAM** — not in bank 4 beside the droid table, because both sides of the
bank split reach it: `droid.asm` pays the deck-cleared bonus through `AddScore` and the fire code to
come is in main RAM, and bank code may call main RAM freely while the reverse holds only with
`SWRAM_DATA` paged.

What landed:

- **`drType[0]`, `drEnergy[0]` and `drFireDelay[0]` are the player's**, seeded by `CombatInit` from
  `StartGame` (`$1345`): droid 001, energy and ceiling both `$40`, `weaponType` from `drWeapon[0]`.
  `maxEnergy`, `weaponType`, `alertLvl`, `scoreAdd` and the 4-byte BCD `score` are scalars alongside.
- **`AddScore`** (`$3E94`), a direct port — `SED`/`CLD` behave identically here.
- **`DoAging`** (`DoAlertAndAging`, `$3E32`): alert decay and its payout on 1 iteration in 16, and
  `maxEnergy` ageing on `drAgingMask[drCent[type]]` with energy following it down.
- **`gameTick`**, a new main-RAM counter bumped once per iteration and never reset — the C64's
  `frameCount`. `drTick` was the obvious candidate and is wrong: `DroidsInit` zeroes it on every
  deck load, which would restart the ageing phase every time you change deck.
- **`tools/export_droids.py`** now emits `drCent`, `drWeapon`, `drAgingMask` and `drAlertScore`,
  56 bytes, checked against the listing byte for byte.

**`DroidsInit` no longer clears entry 0.** It used to, under a comment reading "the sentinel is
always empty" — which would have reset the player's droid and energy on every deck change and every
lift ride from this layer on. Only `drSprNum[0]` is still cleared; the player's sprite is slot 0 and
the table's copy of it is unused.

#### Measured in jsbeeb

| | |
|---|---|
| `CombatInit` | `maxEnergy` `$40`, `drType[0]` 0, `drEnergy[0]` `$40`, weapon 0, score 0 |
| Ageing rate | `maxEnergy` `$3F`→`$3B` over ~530 iterations = 4 points, against 530/128 = 4.1 for the class-0 mask `$7F`. Energy tracked it down |
| **Deck change** | after a hop to deck 2, `drType[0]` = 0 and `drEnergy[0]` = `$3F` **survive** — the regression the `DroidsInit` fix exists to prevent |
| Frame lock | `DEBUG_VSYNC` still reads 2 |
| Cost | `DoAging` is negligible; `DbgEnergyOut` is ~800 cycles, 1% of a pass, and runs after the drawing where it touches no buffer |
| Space | main RAM `&1100–&2922`, **1,758 B free**; bank 4 ends `&B5FB`, **2,565 B free** |

> **Reading bank-4 state from the MCP needs `&F4` checked first.** `drType`/`drEnergy` are at
> `&B3F7`/`&B405`, and `read_memory` returns whatever bank is paged at that instant. A sample taken
> inside `SprDrawAll` returns bank 5's empty space — all zeros — which reads exactly like the player
> having been wiped. It cost one false alarm here. Sample, check `&F4` is 4, and re-run a few
> thousand cycles if it is not.

*Visible:* `DEBUG_ENERGY` on the second panel row — `type energy maxEnergy weapon alert score` as
hex, `00 3B 3B 00 00 00000000` after twenty seconds on deck 2. Row 1 rather than row 0, so
`DEBUG_VSYNC`'s frame digit and `DEBUG_POS` still fit alongside. It defaults **on**: the panel is
Layer 9's and every remaining stage of this layer is unverifiable by eye without it.

### 7b — `DoCharUnder`: the recharge pad ✅ **DONE 2026-08-15**

One C64 routine (`$2E7B`) delivers both, and it is a plain test on the **character code** under the
player — not the tile index. `charUnder` is read from the expanded character map at the player's own
cell; here that is `MapChar` at `plyCX`/`plyCY`, which `CheckWalls` has already set earlier in the
pass.

- **char 20 → recharger.** Every 4th iteration, if `drEnergy[0] < maxEnergy`, add one and
  **subtract 5 from the score**. Energy is not free in this game.
- **chars 43–46 → lift.** `consoleState` counts down from 5 and the lift takes the deck over when it
  reaches zero — **but only while `moveMode` is not `$80`, which is to say only once fire has been
  pressed.** See below.
- **char 66 → console.** Same countdown, ending in a negative `consoleState`, which is what
  `GameLoop` tests at `$1427` to branch into the console. Layer 9.
- **anything else** resets `consoleState` to 5.

#### The fire button IS the lift trigger, through `moveMode`

`DoCharUnder`'s lift and console arms both open with `LDA moveMode : BMI _2` — bail out and reset the
countdown when `moveMode` is negative. `moveMode` is `$80` whenever fire is **not** held, so the
countdown runs only after a press. **Pressing fire on a lift platform is what opens the deck
selection, in the original as well as here**, and `lift.asm`'s L-to-enter was right all along.

The gate is indirect because fire does not act directly on anything — it drives a four-state mode
machine in `DoMoveMode` (`$31B9`), whose strings name it:

| `moveMode` | | fire does |
|---|---|---|
| `$80` | `Mobile_txt` `$698A` | the resting state, fire released. Pressing it moves on |
| `1` | `Weapon_txt` `$6997` | **held fire shoots** — this is `DoFire`'s only caller with the trigger down |
| `2` | — | pressed with no direction; settles to Transfer after `moveModeDelay` |
| `0` | `Transfer_txt` `$697D` | touching a droid starts the **transfer game** instead of bumping it |

So one key genuinely does everything, and **no tiebreak rule is needed** — which is just as well,
because the one this document proposed on first reading was invented to solve a conflict that does
not exist. Standing on a lift and pressing fire runs the countdown whether you were shooting or not;
five iterations later the lift takes over.

> **`joyFire` is ACTIVE LOW and the whole reading turns on it.** `ReadJoystick` (`$0958`) does
> `AND #$10` on CIA port A, so **`joyFire == 0` means pressed**. Read it the other way and
> `DoCharUnder` appears to make lifts automatic and `DoMoveMode` appears to run backwards. The
> unambiguous check is `DoMoveMode`'s weapon arm: `LDA joyFire : BNE _mobile` falls through to
> `JSR DoFire`, so zero has to be the trigger down. `WaitNoFire` (`$2864`) agrees — it restarts its
> count of 8 whenever `joyFire` is zero.

**`DoMoveMode` therefore belongs in this layer**, in 7d, and it is not just plumbing for the fire
key: it is the gate on the transfer game as well, so Layer 10 inherits it. The port has one key
rather than a stick, and the machine needs press and release edges, which the `prevRet` idiom in
the main loop already provides.

**`lift.asm` keeps its trigger unchanged.** Only the **recharger** arm of `$2E7B` is new work here;
the lift arm is a faithfulness improvement that can follow once `moveMode` exists, and the console
arm is Layer 9's. `consoleState` is not needed until one of those two lands, so it does not exist
yet.

`SubScore` (`$3EC4`) came with it — AddScore's mirror, with its own `scoreSub` accumulator and a
**saturate at zero** where AddScore saturates at 99999999.

> ### `DoScore` was missing, and the accumulators are why nobody noticed
>
> **Fixed 2026-08-16, reported by KC: the score did not move when you shot a droid.**
>
> `AddScore` and `SubScore` do not touch the BCD score. They bank into `scoreAdd` and `scoreSub`,
> and the only path that reaches the score is their **overflow** — a wrap past 256 credits 255 and
> pushes 1 back. What actually spends the accumulators is **`DoScore` (`$0A7D`)**, which `GameLoop`
> calls every iteration at `$13E3`: one point off `scoreAdd` and one point onto the score, per pass.
> That routine had never been ported.
>
> So a kill worth 20 banked 20 invisible points and the display sat still until thirteen more kills
> pushed the accumulator past 256, at which point it jumped by 255. It also cost the original's
> feel, which is a score that *climbs* over the passes after an award rather than stepping.
>
> **Every test in this document measured `scoreAdd` or `scoreSub` rather than `score`** — the
> `SubScore` BCD row above says so outright — so all of them passed against a routine that was
> half-built. Measuring the accumulator proves the arithmetic and says nothing about whether
> anything drains it.
>
> `DoScore` is now in `combat.asm` and called from the main loop *before* the `conActive` test,
> because `$13E3` runs before `GameLoop`'s `consoleState` test at `$1427`. Verified in jsbeeb over
> all four paths: 20 credits → score 20; `scoreAdd` 7 with `scoreSub` 17 → the sevens cancel and the
> score falls by 10; 50 debits against a score of 10 → floored at 0 with `scoreSub` cleared, which
> is `$0AD3`. The 99999999 saturate is the C64's own code and is untested — it needs 100M points.

#### Measured in jsbeeb

The pad is `MapChar` at `plyCX`/`plyCY`, so the mechanism can be tested without walking to one:
poke the tile under the player to 20 and the identical code path runs. The player happened to spawn
at character (22, 6) — tile (5,1), offset (2,2), which is the centre 2×2 where character 20 lives.

| | |
|---|---|
| Rate | energy 48 → 58 in **exactly 40 iterations**, `scoreSub` 0 → 50. Ten points at 4 iterations each, ten debits of 5 |
| Ceiling | drained to 0 and left to fill: stopped **exactly at `maxEnergy`** (61, having aged down from 64) |
| `SubScore` BCD | 61 points × 5 = 305 debits from a poked score of 1000 → **745** (`00 00 07 45`), one wrap of 255, and `scoreSub` = 305−256+1 = **50**. Both exact |
| Saturate | score BCD 10 with 250 already banked → next wrap floored it at **0**, not 99999999 |
| Control | tile restored to 21: over 50 iterations energy sat at 40 and `scoreSub` did not move. Only `maxEnergy` aged |
| Real pads | deck 2's live tile map holds tile 20 at (30,4), (32,4), (30,6) and (32,6). Deck 1 has none, which matches `level_stats.txt` |
| Space | main RAM `&1100–&2993`, **1,645 B free** |

That closes the chain end to end: the shipped map contains tile 20, tile 20's centre 2×2 is
character 20, and character 20 drives the recharger.

*Visible:* stand on the pad and energy climbs while the score falls.

**Character 20 is the recharger in our charset — checked 2026-08-15, and the test ports verbatim.**
The worry was that graphics.md lists *tile* 20 as the console/recharge station while the C64 tests
*character* 20, two numbering spaces colliding on the same digit. They are genuinely different
numbers that genuinely agree here:

- `&14` occurs **exactly once in all 32 tile definitions**, in tile 20, and nowhere else — so a
  character-20 match cannot be anything but a recharger.
- It is the **2 × 2 centre** of that tile: `00 4C 4D 00 / 4F 14 14 4E / 4E 14 14 4F / 00 4D 4C 00`.
  The pad is the middle of a 4 × 4-character tile, which answers the obvious worry about a
  five-iteration countdown — you cannot trigger it by clipping a corner, you have to stand on it.
- Every character in the tile has bit 7 clear, so the whole tile is floor and none of it is a door.
- `tools/output/level_stats.txt`: **tile 20 is used in 12 decks**, matching graphics.md exactly.

So the port's test is `MapChar` at `plyCX`/`plyCY` compared against 20, with no translation layer.

The recharger's animated icon (`ChrAnimData2`, `$6C28`, 8 frames) is a **character** animation, and
our charset is built once at deck load. Animating it means re-poking 16 bytes of charset a pass.
Cheap, but it is polish — do the function first, and it can ride along with Layer 9's panel work.

*Visible:* stand on the pad, energy climbs and the score drops.

### 7c — Effect sprites: the second sprite class ✅ **DONE 2026-08-15**

The one piece of genuinely new machinery. Twenty effect sprites at `$4C00`–`$50FF`: bullets in the
low frames, the twelve-frame explosion from `$4E40`. `tools/export_droids.py` grows a second half
(or a sibling) that converts them to MODE 1 the same way the droid rows are converted, and emits
**a bounding box per frame** — first and last opaque row, first and last opaque column.

The blitter does *not* grow a compiled path. It grows a generic one, which is the existing wrap
fallback (`sd_slow`/`SprFetchRow`) generalised: fetch a row, derive the mask from `SPR_MASKTAB`, blit
it, bounded by the box rather than by 7 × 21. Everything else is shared — the same slot arrays, the
same page-per-slot save area, the same restore-before-draw ordering, the same tranche assignment.

Two constraints to design against, both already written down elsewhere:

- **The save must cover the box, and the restore must replay the box the draw used.** `sprShiftS` and
  friends already exist for exactly this reason; the box joins them as saved-at-draw state.
- **`SprAssignTr`'s overlap test assumes 7 units by 21 scanlines.** A bullet is much smaller and the
  loose test will merge components that do not touch, which costs splits, not correctness. Leave it
  loose to begin with and tighten only if the split refusal rate says to — `raster-timing.md`
  records what tightening it bought last time.

#### The artwork — exported ✅ **2026-08-15**, `tools/export_effects.py`

**It goes in bank 5 with the blitter, not bank 4 with `drSprData`, and no frames had to be cut.**
That reverses this document's own first answer, and the measurement is why.

| | frames | bytes |
|---|---|---|
| Explosion, multicolour, `$39`–`$43` | 11 | 945 |
| Bullets, hires | 20 | 1,803 |
| Tables (`efR0`/`efH`/`efC0`/`efW`/`efData*`/`efAlt`/`efBullet`) | | 198 |
| | **31** | **2,946** — against 4,557 unclipped |

**The explosion was never the expensive half.** The bullets are, at nearly twice the size: 12
`BulletSprite_t` entries, and every image `>= $56` animates as a pair, so 20 frames ship for 12
table slots. Thinning explosion frames would have cut the wrong thing.

2,946 into **bank 4's** 2,565 free does not fit — which is what the frame-thinning decision was for.
Into **bank 5's** 4,010 it fits with 1,064 to spare, and bank 5 is the better home on its own merits:

- **Paging.** `drSprData` is in bank 4 because `SprFetchRow` reads it on about one row in fifty and
  can afford to page around itself. An effect sprite is drawn *entirely* by the interpreted path, so
  its rows are read on every row of every frame — paging per row would cost more than the blit. An
  effect never uses a compiled shift, so it does not care which sprite bank is up and can live in
  whichever one the slot has already selected.
- **Scarcity has swapped.** Bank 4 became the tighter of the two when the level draw and the droid
  AI moved into it. The note in `export_droids.py` calling the sprite bank "the scarce one" was true
  when it was written and is not any more.

So **KC's frame-thinning decision does not bite** and the twelve-iteration indirection table is not
needed. It stays on the record in case bank 5 tightens later.

**Every opaque pixel becomes logical colour 1**, and on the explosion that is a real loss — it is
multicolour on the C64 and has three. The deck palettes decide it: logical 1 is white on all 16
decks, logical 2 is black on fourteen, and **logical 3 is black on decks 4 and 11**, so an explosion
drawn in 3 would be invisible on two of them. Same argument that put the droids on logical 1. The
C64's own sprite multicolour registers cannot settle it either way — `$D025`/`$D026` are never
written by the game and the listing's dump has text data overlaying `$D022` upwards.

**Verified by round-trip**: each frame rebuilt from its stored box and compared against an opacity
grid computed independently from the C64 bytes — **31 frames, 0 mismatches**. `efAlt` is self-inverse
over all 31, every `efBullet` entry points at a bullet frame rather than an explosion frame, and
every box fits inside 21 rows × 6 byte columns.

Bank 5 now ends `&BBF7`, **1,033 B free**, and `PARASPR` grew 49 → 60 pages. It still boots: the
boot staging reaches ~`&6C00` instead of `&68B5`, further into the play buffer, which is safe for
the same reason it always was — `PageBankIn` runs before anything there is read again.

#### The blitter — built ✅ **2026-08-15**

Six routines in `sprite.asm`, ~550 bytes of main RAM, sharing every part of the slot machinery and
differing only in how pixels get there:

| | |
|---|---|
| `SprEfSetup` | `SprSetSlot`'s tail for an effect: no digit block, no rotor sequence, and **bank 5 forced** rather than `PAGESPRBANK`'s shift-derived choice |
| `SprEfBox` | frame → `efRow0`/`efHgt`/`efCol0`/`efWid`/`efWid1` and the row pointer |
| `SprEfSkip` | down `efRow0` scanlines; both passes take the identical walk |
| `SprEfFetch` | one row, shifted, plus masks — `SprFetchRow`'s one-pixel-a-pass idiom |
| `SprEfDraw` | save the background and blit the box |
| `SprEfRestore` | the mirror, from the frame the **draw** used |

**Forcing bank 5 is load-bearing.** `PAGESPRBANK` selects bank 5 or 6 from the shift, because the
compiled shifts are split across them. The effect artwork is only in bank 5, so an effect at shift
2 or 3 would otherwise read its rows out of bank 6 and draw whatever happened to be there.

**`efSrc` borrows `psrc`.** It has to be in zero page for `(efSrc),Y` and zero page has been full
since Layer 5, so it shares the droid fetch's own row pointer — whose only user is `SprFetchRow`. A
slot is either a droid or an effect and slots are drawn one at a time, so the two can never collide.

**Three saved-at-draw fields, not one.** `sprKindS` and `sprEfFrmS` join `sprShiftS`/`sprNoWrapS`/
`sprSeqBaseS` for the same reason those exist: the restore runs a frame later, by which time the
slot may have animated, moved, or been freed and handed to a droid. It has to put back what it took.

**One wrap decision per sprite, not per row.** The droid path tests every row because only some rows
of a wrapping sprite actually straddle the end of the strip and a compiled row cannot express a
walk. The walked path here is correct either way, so one test up front is enough.

##### `SPR_SLOTS` 7 → 8, and a bug it introduced

Slot 7 is the player's bullet, save page `&3700` — which fills the gap up to the tile map at `&3800`
exactly, so a ninth slot would overwrite the map. The assert now says that rather than the looser
`<= PANEL_ADDR`.

**`DrFindSlot` started at `SPR_SLOTS-1` and would have handed slot 7 to a droid.** The C64's
`FindFreeSprite` (`$32A8`) searches 6 down to 1 for precisely this reason. `SPR_SLOTS-1` and the
last pool slot were the same number until this change and silently stopped being one; `DroidsUpdate`'s
line-of-sight round robin had the same bug. Both now use a named `SPR_POOL_LAST = 6`.

##### Measured

| | |
|---|---|
| Draw | explosion frame 5 **at shift 3**, the hardest case: **224 opaque pixels in 21 rows, an exact pixel-for-pixel match** against the frame computed independently from the C64 bytes |
| Restore | **0 of 10240** bytes different from the pre-draw buffer |
| Oracle | after ~75 passes scrolling vertically with an effect live throughout, then removed: **0 of 10240** against a forced `RedrawAll` |
| Space | main RAM `&1100–&2BBC`, **1,092 B free** |

> **`save_memory` pauses wherever the cycle count lands, which is often mid-blit.** Three snapshots
> a few thousand cycles apart showed 12 rows, 9 rows and then all 21. The first two look exactly
> like a blitter dropping rows, and cost a real detour chasing a bug that was not there — the
> screenshot showing the sprite drawn correctly is what broke the deadlock. **Sample until two
> readings agree, or verify against the pixel count rather than the picture.** Same class of trap
> as the `&F4` bank check in 7a.

The walked path was not proven to have executed — it depends on where the sprite lands in the
circular strip — but over that many scroll positions it is very unlikely to have been missed, and
the oracle covers it if it ran.

*Visible:* poke a slot into explosion mode and watch twelve frames play out and free the slot.

### 7d — The player fires ✅ **DONE 2026-08-15**

`DoMoveMode` (`$31B9`) first — the Mobile/Weapon/Transfer machine from 7b, driven by L's press and
release edges. It is the only caller of `DoFire`, and getting it in now means the transfer arm in 7e
and Layer 10 both have the state they need.

`DoFire` (`$33B5`) then, gated by `drFireDelay[0]`, by whether slot 7 is already live, and by
there being a direction held. `BulletSprite_t` (`$6E4C`) picks the image from the direction pair and
`BulletDisplacement_t` (`$6E58`, `$F4, 0, $0C, 8`) offsets the spawn out of the player's own body.
The delay afterwards is `32 - 2*DCent_t[type]` — a better droid shoots faster.

`MovePlyFire` (`$32D9`) then runs the bullet each pass: **its own speed plus the player's speed**,
which is why a bullet fired while running keeps up. `SpriteHitWall` (`$336F`) turns the sprite's
screen position back into a map cell and tests bit 7, exactly as `CheckWalls` does for the player.

The player's bullet is slot 7 and **must be allocated before `SprSplitOK`** so the tranche assignment
sees it — that is the same ordering constraint the movement already satisfies.

Weapon type 3 is the **disruptor** and is not a bullet at all; it sets `disruptorCnt` and is handled
as an area effect. It can be stubbed in 7d and finished in 7f, since no droid the player starts as
carries one.

*Visible:* press L and a bullet flies, stops at walls, and dies at the edge of the view.

#### What landed

`combat.asm` gains `DoMoveMode`, `DoFire`, `MovePlyFire`, `CbFireCell`, `CbFirePlace` and
`CbSignExt`. Three decisions worth keeping:

- **`fireDown` is true-means-pressed**, the inverse of the C64's `joyFire`. The key read
  normalises it once, so every test in the mode machine reads the opposite way round to the
  original — which is the right trade, given that getting that polarity backwards is what made
  this document claim lifts were automatic.
- **The bullet's position is WORLD, not screen.** The C64 keeps it in the VIC sprite registers and
  compensates for the scroll by adding the player's speed at `$32EA`; a world-space bullet has
  nothing to compensate, so that fudge simply does not port. `CbFirePlace` converts to slot
  coordinates the same way `DrScreen` does for a droid.
- **The two animation frames are held, not looked up.** `DoFire` reads `efBullet` and then `efAlt`
  once, and `MovePlyFire` swaps the pair. Frames that do not animate have `efAlt` pointing at
  themselves, so the swap is a no-op and needs no test — which is why the weapon-0 bullets sit
  still and the others flicker.

**The L key is read once at the top of the pass** and the whole block moved up there from below the
level draw, because `DoFire` activates slot 7 and `SprSplitOK`'s tranche assignment has to see it.
The lift gets first refusal: `LiftEnter` is called on the press edge and, if it declines, the same
press goes to the weapon. Nothing in `LiftEnter`/`LiftExit` draws, so moving it is safe; the
deck-hop keys, which do draw, stayed where they were.

##### Measured

| | |
|---|---|
| Mode machine | Mobile → Weapon on a press with a direction held; `moveMode` = 1, `fireDown` = 1 |
| Direction | Z gave `plyFireDX` = `&F4` (−12) and X gave `+12`, both with frame **11** — which is `efBullet[3]`, the horizontal bullet |
| Flight | `plyFireX` 616 → 628 over exactly one pass: **+12, the C64's own `BulletDisplacement_t`** |
| Wall | fired into the wall the player was standing against: no bullet spawned, delay still charged, as `$341C` does |
| Rate | 32 iterations between shots, `32 − 2·drCent[type]` |
| Space | main RAM `&1100–&2E6D`, **403 B free** |

> **Main RAM is the constraint again.** 403 bytes, and 7e and 7f still to come. The next thing to
> move is not obvious — `combat.asm` calls into bank 4 already, so it *could* follow `droid.asm`
> across, but only if nothing in a sprite-bank-paged path needs it. Worth costing before 7e rather
> than after.

> **The lift/fire tiebreak was not re-tested in the emulator.** The logic is unchanged in substance
> and the weapon half is verified, but the branch where `LiftEnter` succeeds needs the player
> standing on a platform, which this session never did. Check it before trusting it.

### 7e — Damage, kills, explosions and score — **the kill chain DONE 2026-08-15**

> **Split from what was planned.** What landed is the half that needed the effect sprites:
> **a player bullet kills a droid, which explodes and scores**. The arms that damage the *player* —
> the bump, the enemy bullet, walking into an explosion — and the death that follows are deferred to
> 7f, because nothing can hurt him until enemy fire exists and they are all the same `DoCollision`
> arm. `CollisionType`, `BumpScore` and `EnemyFireEnemy` go with them.

The `CollisionType` matrix at `$6D6D` is sixteen bytes and is the entire decision table —
`$80` nop, `$40` explode, `$20` friendly-fire, `$10` free the sprite, `$08` reverse, `$04`
player-fire kill — indexed by `(mode2 << 3) + mode1`. Port it as data; `DoCollision2`'s two symmetric
halves become two passes over the same arms with the pair swapped, as they are in the original.

The arms:

- `PlyFireEnemy` — damage `(((weaponType+2)*4 + 8 - type) * 4) + 16`, and a type too strong for the
  weapon takes none at all. Zero or below → `KillDroid`.
- `EnemyFireEnemy` — `(40 - type) * 2`. Droids kill each other and it is not a bug.
- `KillDroid` — `Alert += type` saturating at 255, `ShootScore[DCent_t[type]]` banked into
  `byte_0_79` (paid out by `FreePlyBullet`, not immediately), then `ExplodeSprite`.
- `ExplodeSprite` — off the ship roster via `DrRemoveShip` (**already written**, Layer 5), type
  `$40`, sprite image `$39`, into mode 2.
- The **player-versus-droid bump** arm in `DrCollided`: energy difference by type either way,
  `Alert += type` and `BumpScore[DCent_t[type]]` if the droid dies of it. The movement half of this
  arm is already there.
- Player versus enemy bullet, and player versus explosion (`-shipLevel` energy).

`AddScore` (`$3E94`) is 4-byte BCD with a `scoreAdd` accumulator and is a **direct port** — `SED`/`CLD`
work identically. `DoScore`'s rendering is Layer 9's; keep the digits in memory and show them on the
debug line.

Two port-specific notes:

- **One pair a pass.** `DrCollide` inherits this from `DoCollision`, which handles the two lowest set
  bits of `$D01E` and returns. It is tolerable for bumps and bad for bullets — a bullet that is not
  the chosen pair passes straight through a droid. We scan all pairs anyway, so **prefer a pair
  involving a bullet** when one exists. It costs nothing and it is strictly closer to what the
  hardware latch would have caught.
- **`DR_COL_W`/`DR_COL_H` are droid-sized.** A bullet needs its own, smaller box. The Layer 6 note
  about the box being deliberately smaller than the sprite applies again and for the same reason.

The **deck-cleared bonus** already has its home: `DroidsUpdate`'s `dru_done` is `RunDroids`' own
`CPY #1` arm, which pays 250 + 250 and sets `notInDeck` when the ship is empty.

#### The player at zero energy — **KC's call, 2026-08-15**

**Explode, then respawn as 001 on waypoint 0.** Every arm that can take the player's energy down
already clamps at zero rather than wrapping, so the test is one `BEQ` on `drEnergy[0]` after the
collision pass. What follows is `BlowInto001` (`$1573`) with its modal loop taken out:

1. The explosion plays for `EF_EXPLODE_N` iterations, and **slot 0 becomes the effect** — `sprKind`
   1, the frame in `sprType`, back to a droid at the end. `plyDying` in `combat.asm` is the flag,
   and `DoFire` checks it so a burning droid does not shoot.

   **This is a deliberate divergence, tried the other way first.** The C64 draws both: `$1577`
   reads sprite 7's state (the player's), `$157C` retargets `SpriteNum` to 0 — the bullet sprite —
   and `$158A` writes the player's position back out as sprite 0 with the explosion image in it.
   Sprite 7 is never disabled, and `$15A9` rebuilds it as a 001, so on the original the explosion
   burns *on top of* the droid. Ported literally onto slot 7 it does not read: our player slot is
   drawn as a 001 whatever he is riding — nothing writes `sprType+PLY_SLOT` until Layer 10 — so a
   rotor spins through every transparent pixel of the explosion and the two sprites fight. KC
   called it on sight. Taking slot 0 also needs no position tracking, because the slot being
   animated is the one `DeadZone` and `PLY_Y` already place.
2. Type := 0 (droid 001), `drEnergy[0]` := 7, `maxEnergy` floored at 7 — the original raises it to 7
   if it is lower and otherwise leaves it, so an aged player does *not* get their ceiling back.
3. `weaponType` := `DWeapon_t[0]`, speeds zeroed, and `SetPosFromWaypoint` to waypoint 0 — the same
   call Layer 5 already uses for a deck arrival, so no new placement code — followed by
   `ReframeView`, which is **not optional**: see BUGS.md #10.

**The order is ours, not the original's.** `BlowInto001` resets the type, the energy and the weapon
*before* its loop and never moves the player at all, so it can afford to. We respawn on waypoint 0,
and exploding after that teleport would light him up somewhere he never died — so steps 2-4 are
held back to the last frame of the animation and only the speeds are zeroed up front.

**And the loop is a state machine, not a loop.** `$15B0` calls `RunGame` and `RunDroids` itself,
eleven times over. We cannot nest the main loop — the rupture, the two-window sprite split and the
field waits all live in it — so `CbCheckDeath` counts the same eleven iterations one per pass and
returns each time.
4. The deck's droids are left exactly as they are. Dying is a setback, not a reset.

**There is no game over**, deliberately: the title screen and attract mode are Layer 11's and there
is nothing to return to. `shipLevel`, the score and the ship roster all survive, so the run
continues. Whether death should eventually cost something more than the droid you were riding is a
Layer 11 question, not this one.

*Visible:* shoot a droid, watch it flash, explode and vanish; the score moves and Alert jumps. Walk
into enough fire and the player explodes and comes back as 001 on the deck's first waypoint.

#### What landed, and where

All of it is in **`droid.asm`, bank 4**, not `combat.asm`: every byte it touches is a droid-table
byte and `DrCollided` was already there. It calls out to main RAM for `AddScore` and `alertLvl`,
which is the direction the bank rule allows. Main RAM did not move at all — still 403 B free — and
bank 4 went to **2,104 B free**.

- **`DrBulletHit`** — the bullet is tested **before** the pair loop, not inside it. `DrCollide` acts
  on one pair a pass, which the original does too, and a bullet that lost the draw would pass
  straight through a droid. One bullet against six droids is six box tests, so the question is
  simply removed. `BUL_COL_W/H` are 12 × 10, smaller than a droid's box, because a bullet's opaque
  pixels are a streak through a mostly empty 24 × 21.
- **`DrPlyFireEnemy`** — the original's arithmetic including its carry, where the `ADC #8`
  deliberately picks up the carry out of the second `ASL`. A droid too strong for the weapon takes
  **nothing at all**, which is what makes an early weapon useless later and the whole reason to
  transfer upward.
- **`DrKillDroid`** → **`DrExplodeSprite`** — the droid does not die and get replaced; its own table
  entry *becomes* the explosion, keeping the slot it already holds. Type `$40` is what the mode
  dispatch reads from the next pass on.
- **`DrExplode`** (mode 2) — eleven frames, one a pass, drifting on the dead droid's last speed with
  that speed halved each pass, then the slot goes back to the pool.

**No `CollisionType` matrix yet.** The C64 dispatches every pair through `$6D6D`, which earns its
keep once bullets, explosions and enemy fire can all hit each other. With only
player-fire-hits-droid implemented a direct test is smaller and says what it means.

**Two slot-reuse guards came with it**, and both are the kind of thing that would have shown up as
garbage much later. `sprType` means a *droid type* to a droid slot and a *frame* to an effect slot,
so allocating a slot to a droid now clears `sprKind` — otherwise a slot that last held an explosion
draws a droid type as artwork. And an explosion still owns a slot and still has a table entry, so it
turns up in `DrCollide`'s pair loop and must not be shoved about like a droid.

##### Measured

Driven deterministically by placing a bullet exactly on a droid rather than trying to aim: droid 1,
type 4, full energy `$40`.

| | |
|---|---|
| Damage | `(0+2)·4+8 − 4 = 12`, `·4+16 = 64` — exactly its energy, so one shot |
| Alert | `alertLvl` 0 → **4**, the droid's own type |
| Score | `scoreAdd` 0 → **50** = `drShootScore[drCent[4]]`, banked below the BCD threshold |
| Explosion | `drType` → `$40`, slot 6 → `sprKind` 1, frame 0 |
| Frame rate | frame 1 → 6 over 5 passes: **exactly one a pass** |
| End | slot freed after 11 frames, `sprActive[6]` → 0 |
| Compaction | the entry vanished and the droid behind it moved down — `drType[1]` 4 → 2 |

### 7f — Enemy fire ✅ **DONE 2026-08-16**

`DoEnemyFire` slots into `DroidRun` **between the sight-line test and the waypoint search** — the
comment reserving that spot is already in `droid.asm`. Gated on `DWeapon_t[type]` being non-zero, on
a free sprite, on `drFireDelay`, on the droid table having room, and on a random draw against
`shipLevel` — later ships shoot more. The new entry goes in at `drCount` with type `$25`, energy
`$25`, and `drCount` increments.

`dMd1_bullet` (`$1849`) then ages it: type counts down from `$25`, the sprite flickers on the odd
frames, and it dies when `GetDroidCharPos` finds bit 7 set under it — a wall — at which point it
becomes an explosion in place.

Finally the disruptor arms for both sides.

*Visible:* stand in a corridor and get shot at.

#### What landed

`DrEnemyFire`, `DrAddBullet`, the mode-1 `DrBullet` and `DrHurtPlayer`, all in bank 4; the death
and respawn in `combat.asm`. An enemy bullet is a **droid-table entry in mode 1, type `$25`**,
sharing the same pool of six sprites — so a deck full of bullets is a deck with fewer droids drawn,
exactly as on the C64, and the per-pass sprite cost does not grow.

- **Shooting is gated on the sprite being lit**, which is the C64's own gate: `DoEnemyFire` sits
  inside `dMd0`'s `SpriteEna` arm, so a droid that cannot see the player does not shoot at him.
- **The random draw is the difficulty curve.** `random AND $1F` against `shipLevel` means ship 1
  fires on one draw in 32 and ship 8 on eight — the same droids get steadily deadlier.
- **The bullet's speed is a NORMALISED DIRECTION, not a distance** — 4-7 pixels an iteration on the
  dominant axis at any range. `AddBullet` shifts `deltaX`/`deltaY` down five, and those are not the
  raw offset: `LineOfVisibility` differenced the two *character* positions and then ran them through
  `CalcDeltaAdd`, which scales the pair up together until the longer sits in [128, 255]. The shift
  is logical rather than arithmetic and both speeds are then negated, which is what points the
  bullet at the player. `DrScaleDelta` is shared by `DrLineOfSight` and `DrAddBullet` for this;
  reading it as a raw pixel distance instead was BUGS.md #11, and made point-blank shots crawl.
- **The type counts `$25` down to `$20` and the bullet is invisible while it does** — four passes
  inside the droid that fired it, so it is not born already overlapping. At `$20` it arms and stays
  there until it meets a wall, and then becomes an explosion in place, which is why
  `DrExplodeSprite` takes it with no special case.
- **`DrHurtPlayer`** carries the three arms that cost him energy: a droid (the stronger hurts the
  weaker, his damage halved and theirs doubled), an enemy bullet, and standing in an explosion.
  **Only the droid arm is debounced**, and only it should be: the C64 tests `byte_0_6C` inside
  `_ply_droid` ($1A77) and nowhere else, because a bullet frees its own sprite when it lands and so
  can only count once, and standing in an explosion is meant to hurt every pass. The flag is
  latched by `DrReverse` — the C64 writes it in `ReverseDroidDir` — so it means "we bumped last
  pass" and not "something was touching". Debouncing all three arms was the other half of
  BUGS.md #11.

> **A bank-4 routine cannot page itself out, and this is where that bit.** `DrAddBullet` needs
> `efBullet`, which is in bank 5 with the artwork, and a `PAGEBANK SWRAM_SPR` there swaps bank 5 in
> at `&8000` *while the 6502 is executing from `&8000`* — the next instruction fetch comes out of
> the blitter. It crashed instantly, landing at `PC = &B3C9` with a ROM paged in. The fix is
> `CbBulletFrame`, a four-line lookup in **main RAM**, which may page freely and which bank code may
> call. The one-way rule in `bufcore.asm`'s header covers exactly this; it is just easy to walk into
> when the thing you want is a single byte.

##### Measured

Deck 2, one droid armed by hand (type 14, weapon 1) and `shipLevel` raised so the fire gate passes
often:

| | |
|---|---|
| Fire | a new entry appears at type `$25`, energy `$25` |
| Arming | seen at `$20` — counted down and visible |
| Damage | player `$3F` → `$27`: **24 lost, exactly three hits of 8** |
| Volume | three bullets in flight at once, two armed and one still in the muzzle |
| Death | energy 0 → respawn: energy **7**, and `plyX` **1038 → 805**, the waypoint-0 position |

##### Still deferred

The **disruptor** (weapon 3, an area effect rather than a bullet — `Disruptor` at `$1B37`);
**`EnemyFireEnemy`**, the friendly fire that lets droids kill each other; the enemy bullet's
per-pass **colour flicker**, which needs `efAlt` from bank 5 and a second per-entry field. The
player's own explosion is **done** (2026-08-16) — see the death section above. The `CollisionType`
matrix is still not needed: with friendly fire absent, every pair that can meet is handled directly.

---

## Budget and the raster

**The pool does not grow, so the sprite count per pass does not change** — seven drawn sprites
remains the ceiling and the tranche machinery is untouched. What changes is the cost of a slot that
holds an effect rather than a droid: the compiled droid is 5,814 cycles and the pre-compilation
interpreted path was 13,998 for a full 24 × 21, so an unclipped explosion frame is in that region and
a bullet, bounded to a few rows and columns, is a small fraction of it.

The worst case worth rigging is **the player, five droids and a late explosion frame**, with the
droid AI's 17,000 on top of it. It has to be measured, not estimated, and the instrument is the
histogram in `raster-timing.md`'s last section — `LDX ruptState : INC dbgRsN,X` either side of the
call. Every buffer phase should still end in rupture state 3.

If it overruns: `FRAME_LOCK` is **a floor and not a fixed length**, so a heavy pass costs what it
costs and the rate recovers on the next one. That is the designed degradation and it is preferable
to capping the number of live effects, which would change behaviour. Step 3 in `raster-timing.md` —
moving `DoRedraws`' column half into window B — is the lever to pull first if it becomes chronic.

**Memory.** Main RAM has 2,086 bytes free and takes the generic blitter path plus `DoFire`/
`MovePlyFire`. Bank 4 has 2,621 and takes the effect artwork, the combat tables (`CollisionType` 16,
`DCent_t` 24, `DWeapon_t` 24, `ShootScore`, `BumpScore`, `AlertScore` 4, `AgingMask`,
`BulletSprite_t` 8, `BulletDisplacement_t` 4 — around 110 bytes all told) and the mode-1/mode-2
handlers next to `DroidRun`. All of `$EA00`–`$EA80`'s droid stats come out of the same block
`export_droids.py` already reads `DSpeed_t` from.

---

## Deliberately not in this layer

| | |
|---|---|
| The transfer minigame | Layer 10. `DoCollision`'s `_ply_droid` arm sets `xferDroid` when `moveMode` is 0 and bumps when it is not; Layer 7 builds the bump arm and leaves the transfer arm as the stub that sets the flag |
| Score, energy and Alert *displayed* | Layer 9. Kept in memory, shown on a debug line |
| The console (char 66) | Layer 9, though `DoCharUnder` will already be dispatching on it |
| Sound | Layer 11. `sndFx1`/`SndFx2` writes are the C64's; leave the values in comments so the driver has them |
| The recharger's 8-frame icon animation | Charset repoking; rides with Layer 9 |
| ~~Low-energy colour flashing~~ | **Built 2026-08-19.** This row said a compiled blitter could not do it, and that was wrong: the artwork is stored at logical 3, so choosing a colour is choosing a nibble, and eleven zero page bytes carry it. `docs/layer-5-blitter.md` § "Colour is not baked in" has the mechanism; the three decisions it forced are below. **Effect sprites still get one fixed colour** — bullets and explosions run the interpreted path and were left alone |

### Sprite colour, 2026-08-19

The C64 gives every sprite a colour register. Three things read it, and none of them was ported
until now.

| | C64 | ours |
|---|---|---|
| an enemy droid | `$F0`, black, written by `dMd0_droid`'s `_new` arm at `$18FA` when the droid takes a slot | logical 1, set in `drs_place` |
| the player | `$F1`, white, written every frame by `$3E06` | logical 3 |
| the player, transfer mode | `clr6_xfer`, written by `$3E21` when `moveMode` is 0 | logical 2 — see [DECISION 1] |
| the player, energy < 8 | `LowNrgColor_t` / `LowNrgXferCol_t`, 8 entries indexed by `frameCount AND 7` | a 4-field duty — see [DECISION 2] |

**[DECISION 1] — transfer mode is logical 2, the deck's highlight.** `clr6_xfer` (`$021B`) is never
written by any routine, which is what gives it away: `InitColors` (`$27C2`) copies **12 bytes** of
the deck's colour record into `clr0`-`clr11`, so it is **slot 6 of the same record Layer 1 took
`deckBg` from as slot 0**. Ripped across the seven schemes it is orange, yellow, dark grey, red,
blue, light blue and cyan — genuinely per-deck.

We cannot have it, and the obvious route fails badly. Pushing `clr6_xfer` through each deck's own
`colourMap` gives **logical 0 on decks 13 and 14** — the background, an invisible player — and
**logical 1, the enemy droids' black, on six more**. Clamping 0 up to 2 fixes the invisible case
and leaves the six. So transfer mode takes logical 2: the only ink not already meaning "enemy" or
"player", per-deck like the original's, and an exact colour match on 4 of 16 decks by luck. KC's
call, with these numbers in front of it.

**[DECISION 2] — the flash takes the rate, not the ramp.** Both tables are a symmetric pulse out of
the base colour and back, ending on white — greys down to black normally, yellow/orange/red in
transfer. Eight inks onto three, with two spoken for, cannot carry that. Rank-quantising each table
to three levels was costed and **rejected**: the transfer cycle's colours are all mid luminance, so
it comes out barely flashing at all, and that is the mode where the cue matters most. Pushing them
through the port's existing nearest-luminance merge is worse for the same reason. So it is the base
colour for four fields and black for four — bit 2 of the same 8-field cycle the C64 counts, at the
same rate — which reads at speed as the flash it is meant to be. KC's call.

**Watch for this before calling it a bug:** `BlowInto001` (`$1591`) gives the 001 you fall back to
**energy 7**, under the threshold of 8, so it flashes continuously until it reaches a recharge pad.
A fresh game starts at `$40` (`$1345`) and does not flash. Both are the original's.

---

## Decisions taken — all three settled 2026-08-15

| | |
|---|---|
| **Zero energy** | **Explode and respawn as 001 on waypoint 0**, `BlowInto001` without its modal loop and with `maxEnergy` floored at 7. No game over — Layer 11 owns the screen that would show one. Detail in 7e |
| **The fire key** | **L does double duty**, shoot and enter a lift — and this is what the original does, through the `moveMode` machine rather than through a tiebreak. `lift.asm`'s trigger is unchanged. Separate buttons stay open as a later option. Detail in 7b |
| **Explosion frames** | **Did not bite.** The decision was fit-what-fits with the length held by an indirection table; measuring found the *bullets* were the expensive half and that bank 5 holds all 31 frames with 1,064 B spare. Nothing cut. Detail in 7c |

**Nothing here is blocked and nothing is left to find out.** The one open question — whether
character 20 is the recharger in our charset numbering — was checked against `tiledefs.asm` on
2026-08-15 and it is, uniquely. See 7b.
