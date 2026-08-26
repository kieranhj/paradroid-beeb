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
the *implementation* of the four adoptions and the bug-behaviour list, plus the fidelity
questions below:

- **Adopted**: (1) the disruptor and bullets no longer restart an explosion — bullets still
  absorbed; (2) randomise droid-droid collision priority to break the three-droid deadlock,
  **conditional on first reproducing the deadlock in our port**; (3) exclude lift-adjacent
  waypoints from droid starting points, so arriving by lift is safer — a per-deck exclusion at
  `InitDeckDroids`; (4) the high-score entry seeds from the previous game's initials.
- **Damage tables stay CE's in full** — the laser 1/2 swap, the friendly-fire asymmetry and the
  explosion damage are preserved as ported behaviour (KC 2026-08-26, closing the decisions.md
  contradiction).
- **Rejected for 1.0**: droid AI pack, radar, security doors, Redux scoring, the transfer
  pulser link, the other map/spawn changes (randomised starts, separate spawn point, deck
  sections), disc-saved high scores, F7/F8 ship carryover, Competition Mode, F3 statistics,
  and a shipped cheat mode (the DEBUG_* builds stay the cheat surface).

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

