# Layer 7 — Combat

**Status: planned, nothing built.** This is the layer that makes the port a game rather than a
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

### 7d — The player fires

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

### 7e — Damage, kills, explosions and score

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

1. Slot 0 goes to explosion artwork and plays the full twelve iterations — the player's own death is
   the one explosion nothing can interrupt, so it does not need a droid-table entry and can be a
   flag on slot 0.
2. Type := 0 (droid 001), `drEnergy[0]` := 7, `maxEnergy` floored at 7 — the original raises it to 7
   if it is lower and otherwise leaves it, so an aged player does *not* get their ceiling back.
3. `weaponType` := `DWeapon_t[0]`, speeds zeroed, and `SetPosFromWaypoint` to waypoint 0 — the same
   call Layer 5 already uses for a deck arrival, so no new placement code.
4. The deck's droids are left exactly as they are. Dying is a setback, not a reset.

**There is no game over**, deliberately: the title screen and attract mode are Layer 11's and there
is nothing to return to. `shipLevel`, the score and the ship roster all survive, so the run
continues. Whether death should eventually cost something more than the droid you were riding is a
Layer 11 question, not this one.

*Visible:* shoot a droid, watch it flash, explode and vanish; the score moves and Alert jumps. Walk
into enough fire and the player explodes and comes back as 001 on the deck's first waypoint.

### 7f — Enemy fire

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
| Low-energy colour flashing | `LowNrgColor_t`/`LowNrgXferCol_t` cycle a sprite's colour per frame. Our compiled sprites bake colour into the immediates and cannot; the interpreted effect path *could*, at a cost. Bullets get one fixed colour, and this goes on the list as a real limitation of a compiled blitter rather than an oversight |

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
