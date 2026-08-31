# Layer 12 — Balance, fidelity and feel

**Status: planned, not started.** `PLAN.md` carries the one-paragraph summary; this is the detail.

**Entry condition:** Layer 11 done, so the pass measures the finished game.
**Exit condition:** the fidelity table complete, the Redux list triaged, and a build KC is happy to
put in front of someone else.

Not a feature layer. Everything is built by now; this is the pass that decides whether it plays
like Paradroid. Four strands, and the order matters — verify before tuning, or a fidelity bug gets
"balanced" around instead of fixed.

## 12a — Fidelity audit against the C64

**Every gameplay routine walked against `paradroid_ce.lst`, one at a time, and each one either
confirmed identical or the departure written down with its reason.** Layer 7 twice shipped a
constant read out of the listing without following where its input came from (`AddBullet`'s
normalised direction, BUGS.md #11; the collision debounce applied to three arms instead of one).
Those are not the kind of thing playtesting finds; they need the listing open beside the source.

The output is a table, one row per routine: C64 address, our label, **identical / deviates /
not ported**, and for a deviation the reason. Candidates already known to deviate, so the audit
starts with them:

| | |
|---|---|
| collision | the VIC's register is pixel-exact and free; ours is a box test tuned by eye. **No faithful port exists** |
| the sight line | the C64 tests every near droid every iteration; ours tests one a pass (`losTurn`). A droid that steps behind a wall stays drawn up to five passes longer |
| speed | `PLY_ITER_FRAMES` and the CE's faster loop, written up in `docs/layer-4-player.md` — confirm the movement constants still transfer byte for byte |
| the death respawn | the C64 does not move the player; ours teleports to waypoint 0 and re-frames |
| the death explosion | the C64 draws the player's droid *under* the explosion; ours replaces it |
| culling | sprites are culled, not clipped, so a droid pops in and out a sprite's width from the edge. The C64's hardware clips |

## 12b — The Redux fix list

**TRIAGED WITH KC, 2026-08-26** — every added feature on https://paradro.id/ was ruled on
(the decision table in `decisions.md` has the one-paragraph record). What remains for 12b is
the *implementation* of the adoptions and the bug-behaviour list, plus the fidelity
questions below. **The numbered decisions below record what each one came to** — (1) is closed
without code and (3) is deferred, so read those before starting on any of them.

- **Adopted**: (1) the disruptor and bullets no longer restart an explosion — bullets still
  absorbed; (2) randomise droid-droid collision priority to break the three-droid deadlock,
  **conditional on first reproducing the deadlock in our port**; (3) exclude lift-adjacent
  waypoints from droid starting points, so arriving by lift is safer — a per-deck exclusion at
  `InitDeckDroids`; (4) the high-score entry seeds from the previous game's initials; (5) the console menu shows
  droids remaining on the current deck and across the ship — `pmCount` already mirrors the deck
  count for the panel, the ship count wants the same mirror; (6) the lift's deck-selection
  screen colours completed decks differently — Layer 15's per-deck cleared state read by the
  side-view draw, the colour settled in Layer 14's palette pass. (5) and (6) are Redux
  behaviours KC observed in play, 2026-08-26 — they are not on the page's own list.
- **Damage tables stay CE's in full** — the laser 1/2 swap, the friendly-fire asymmetry and the
  explosion damage are preserved as ported behaviour (KC 2026-08-26, closing the decisions.md
  contradiction).
- **Rejected for 1.0**: droid AI pack, radar, security doors, Redux scoring, the transfer
  pulser link, the other map/spawn changes (randomised starts, separate spawn point, deck
  sections), disc-saved high scores, F7/F8 ship carryover, Competition Mode, statistics (both the intro's F3 page and a console stats page),
  and a shipped cheat mode (the DEBUG_* builds stay the cheat surface).

### The numbered decisions

**[DECISION 1] — (1) explosions restarted by the disruptor or bullets: ADOPTED, and the port
already satisfies it. No code was written. 2026-08-31.**

The adoption was built as a guard in `cbd_loop` (`src/combat.asm`) excluding both
`DR_TYPE_XPLODE` and `DR_TYPE_BULLET` from the disruptor's sweep, and then **reverted, because
the defect it defends against cannot occur**. Recorded here so it is not re-litigated.

*The arithmetic.* An explosion's `drEnergy` is set to `DR_TYPE_XPLODE` — 64 — by
`DrExplodeSprite`, and never changes while it burns. The sweep's damage is `2 * (40 - drType)`,
and for a type of 64 that inner subtract underflows: `40 - 64` is `&E8`, doubled to 208.
`64 - 208` borrows to `&70`, which is **positive**, so `BPL` takes `cbd_next` and the explosion
is never killed. A bullet is the same story from the other end: `AddBullet` gives it
`drEnergy = &25` = 37 against a damage of 6-16, so it survives too. `cbd_kill` is therefore
unreachable for both, `DrKillDroid` is never called on either, and `ExplodeSprite`'s
`STA sprType` — which would stamp `EF_EXPLODE`, frame 0, over an animation in flight — is never
reached from this path.

*Every other route to `DrExplodeSprite` is closed as well.* `DrBulletHit` skips any entry with
`drType >= DR_TYPE_BULLET` before the box test; `drCollType`'s explosion row (`src/lowcode.asm`)
is `&80` across, so nothing in the collision matrix ever takes an explosion as its target;
`DrEnemyFireEnemy` and `DrPlyFireEnemy` are only ever dispatched onto droids; and the player's
own death explosion is single-shot behind `plyDying`. The port arrives at Redux's fix by having
transcribed the collision table verbatim rather than by guarding for it.

*How it was verified, because the arithmetic alone was not trusted.* In jsbeeb: into a game,
**CTRL+C** (`DEBUG_KILL`) to fill the screen with explosions, then `disruptorCnt` (`&0CF2`)
poked to 4 to fire a burst mid-animation, reading `sprType` (`&2D29`) for the exploding slots
across the pass. Frames advanced 2 -> 3. The four bytes of the guard were then **NOPed out at
`&2370` in the running machine**, restoring the unguarded behaviour, and the same test repeated:
2 -> 3 again, with `disruptorCnt` falling 4 -> 3 to prove the sweep had actually run and reached
those slots. Same result with and without the guard, which is what says the guard is dead code.

*Why it was not kept as insurance.* It costs four bytes of the code image, which is the binding
constraint at 7 bytes free, to defend against a hypothetical future change to bullet or
explosion energy — and no `ASSERT` can express the condition. KC, 2026-08-31: recording it is
enough.

**[DECISION 2] — (3) lift-adjacent waypoints excluded from droid starts: DEFERRED, not
rejected. KC, 2026-08-31: "I'm not sure this is an issue until I've seen it in play testing."**
It returns to 12c's session log as a question to answer from play, not a change to make in
advance. The mechanism if it is wanted: `DroidsInit` walks one waypoint record per table index
from waypoint 1 up, and `LiftFind`'s `liftDeck` / `liftTileCol` / `liftTileRow` are in the same
bank, so the test is the waypoint's character coordinates shifted to tiles against this deck's
lift tiles. It must degrade to placing the droid anyway when the exclusion exhausts the table —
deck 2 is 5 waypoints against 3 droids.

**Paradroid Redux is a different codebase** — `docs/decisions.md` has the evidence — so its fixes
cannot be lifted as code. What it is good for is a **list of what Braybrook himself thought was
wrong**, each one then a question to ask of our own port: does the same defect exist here, and do
we want it fixed or preserved? Two of the original's own bugs are already ported deliberately as
the precedent: `dhp_bullet`'s type1/type2 damage mix-up, and `AddBullet`'s logical shift making a
leftward bullet one pixel a pass faster. Both invisible in play; removing them would be a silent
divergence.

## 12c — Playtesting and balance

The dials, all already isolated:

| | |
|---|---|
| `PLY_ITER_FRAMES` | `src/player.asm` — the CE speed dial, and the one that changes the game most |
| `DR_COL_W/H`, `BUL_COL_W/H` | the collision boxes, explicitly "meant to be tuned by eye" |
| `SPR_OVL_U/Y` | the tranche overlap test, deliberately loose |
| `drAgingMask` | the economy: how fast the droid you are riding wears out |
| the `random AND $1F` vs `shipLevel` draw | the difficulty curve |

Feedback goes into a session log — what deck, what was happening, what felt wrong — because
"feels wrong" is not actionable and "the 872s on deck 8 corner me because they fire before I can
see them" is.

## 12d — Performance and graceful degradation

`docs/raster-timing.md` has the method. Two questions:

1. **Is the feel consistent?** `FRAME_LOCK` is a floor: a pass that overruns carries on, so a busy
   deck runs at a different rate from an empty one. Measure `vsyncCount` against the pass count
   across the worst decks — and remember the standing rule that judder in an emulator is 60 Hz
   beat, not the code. Measure, do not watch.
2. **Does an overrun degrade gracefully?** The known cliff is the level draw's 22,016-cycle window
   before the CRTC latch at fire 1. The tranche split is the existing relief valve; nothing is
   built for a pass that overruns anyway — it currently just runs long. Redux's answer — pause
   out-of-view droids when the frame is running out (it later removed the feature) — is one
   option to cost alongside the others. Another Redux note that is probably N/A here: it
   teleports droids away to avoid losing one to sprite starvation, but our Layer 6 slot
   OWNERSHIP already keeps an undrawn droid alive — verify rather than port. Options to cost: dropping
   the rotor animation, thinning the sight-line budget, skipping a tranche.

