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

**[DECISION 3] — (2) the three-droid deadlock randomisation: NOT REPRODUCED, held open as a
playtesting question. No code written. 2026-08-31.**

The triage made this one conditional on reproducing the deadlock here first. A deliberate harness
could not, but it did not clear the port either, and the reasons are worth keeping.

*The mechanism, read out of the code rather than assumed.* `DrCollide` services **one pair a
pass** in a fixed order -- outer slot ascending from 0, inner descending from 7 -- so the pair
chosen is always the lowest outer with the highest inner. That pair's arms are `DrReverse` on the
lower slot and `DrPause16` on the higher, so the higher slot is re-paused every pass for as long
as it stays the serviced pair. The dangerous part is `drCollHit`: `DrReverse` latches on it and
**only a pass with no contact anywhere on screen clears it**, so one continuing contact suppresses
every reversal, including ones that would break a different jam. What saves it in practice is that
the reversed droid does get away -- it turns, walks, contact breaks, the latch clears. A permanent
lock needs the reversed droid walled in AND the middle droid unable to leave.

*The harness, so it does not have to be invented again.* Two temporary edits, neither committed:

  1. `DroidsInit`'s per-index `ADDPTR src, 3` removed, so every droid on the deck is placed on
     **waypoint 0** -- the player's own spawn, so the pile is in view from the first pass.
     Waypoints are corridor and junction cells by construction, so this is a stacked pile in the
     geometry the deadlock needs and more crowded than play produces.
  2. A run-length counter in `DrCollide`: `dbgLockRun` incremented on every pass that services a
     pair and zeroed at the `_x_none` exit -- the same pass that clears `drCollHit` -- with
     `dbgLockMax` as the high-water mark, read from the emulator. A permanent deadlock saturates
     it at 255; a jam that clears leaves its length in passes, at 25 Hz.

  `DEBUG_INVULN` is required: spawning inside the pile otherwise kills the player in about a
  second, which it did on the first attempt.

*THE COUNTER MUST IGNORE THE PLAYER'S PAIRS, and the first version did not.* `DrCollided` reaches
`dc_player` whenever `dcOuter` is 0 and the outer loop starts there, so **a droid leaning on the
parked player wins over every droid-droid pair in the same pass** and holds the latch down by
itself. That read 141 and 98 passes -- 4 to 6 seconds -- and looked like a hit. It was not one.
With the player's pairs treated as breaking the run, the honest figures over 60 s a deck are:

| Deck | Longest droid-droid contact |
|---|---|
| 0 | 35 passes (1.4 s) |
| 1 | 16 passes |
| 4 | 18 passes |

Nothing near saturation. A stack of six disperses within seconds -- on deck 0 the initial pile had
three droids on an exact shared position (`sprUnit` 37, `sprScrY` 42, slots 3, 4 and 5) and was
gone inside ten seconds.

*Why it is held open rather than closed.* Seconds-long jams demonstrably happen, so the mechanism
is present and only its permanence is unproven; and the coverage is three decks of sixteen, on
ship 1, with the player standing still. **The untested case is the likely one**: the player
shepherding droids into a dead end, which is normal play and which a parked-player harness
structurally excludes. It therefore belongs in 12c's session log beside DECISION 2 -- if droids
are seen to stick in play, the harness above is two small diffs and can be re-run on that deck.

**[DECISION 2] — (3) lift-adjacent waypoints excluded from droid starts: DEFERRED, not
rejected. KC, 2026-08-31: "I'm not sure this is an issue until I've seen it in play testing."**
It returns to 12c's session log as a question to answer from play, not a change to make in
advance. The mechanism if it is wanted: `DroidsInit` walks one waypoint record per table index
from waypoint 1 up, and `LiftFind`'s `liftDeck` / `liftTileCol` / `liftTileRow` are in the same
bank, so the test is the waypoint's character coordinates shifted to tiles against this deck's
lift tiles. It must degrade to placing the droid anyway when the exclusion exhausts the table —
deck 2 is 5 waypoints against 3 droids.

**[DECISION 4] — (4) the high-score entry seeds from the previous initials: BUILT.
2026-08-31.**

`GetInitial` ($E56D) starts every initial at index 0, 'A', and so did this port — so entering a
third set of initials meant walking the alphabet from A again for each letter. Redux starts you
at what you typed last time.

*Where the memory lives, and why it needed no new disc file.* KC asked whether this wanted a file
of its own, since the bank files ship ZX0-compressed. It does not: compression only affects the
load, and after `UnpackBankIn` a bank is ordinary RAM. What matters is whether anything reloads
it, and **nothing reloads bank 7** — `BootBanks` `*LOAD`s `PARXFER` once, and the only later loads
are `PARASPR` on the briefing exit and `PARAFNT`/`PARALOW`/`PARTITL` at `GoTitle`. That is exactly
why `hstable.asm` exists and how `hsHigh` already survives between games, so `hsPrev` is three
more bytes in the same file. `HsEntry` already pages bank 7 for the whole of `HsRun`, so no new
paging either.

*It cost nothing.* The three bytes ride `plandata.asm`'s `ALIGN` pad — `hstable.asm` assembles
before it — so bank 7 still ends at `&BFF9`, and the code image is untouched at `&2FF9`.

*It remembers `hsSelFor`, not the table entry*, and is written before the initials are filed into
either end. What the next entry starts from is what you last typed, not what the high score
happens to hold — the two differ as soon as a low score is entered.

*Zero is the assembled value*, so the first entry of a session still starts at 'A' exactly as
before. Nothing changes until there genuinely is a previous set.

*Verified in jsbeeb, both arms of the table.* First game: ESCAPE to end it, the entry opens on
"Lowest Score of the Day!" showing `a..`, and D, G, Z entered. `hsPrev` read back as 3, 6, 25.
Second game, score poked past the 6809 default so it takes the OTHER arm: the entry opens on
"Great Score!" showing `D..`, and the second slot seeds to `G` on commit — so the seeding survives
the overlay being reloaded from disc in between, which is the whole point of it being in bank 7.

**[DECISION 5] — (5) the console shows droids remaining, on the deck and on the ship: BUILT.
2026-08-31.**

*The layout, and what it cost.* KC, 2026-08-31: "Redux removes the 'Access Granted' line in the
console menu and adds 'N droids' underneath the Ship name and Deck name lines", then, on seeing
it: put the Alert line at the top, align the counts with the ship and deck NAMES, and say "droid"
when there is one. A text line is **two** buffer rows, so two new lines want four rows out of a
sixteen-row area that had none spare. Deleting "Access granted." gives two; the other two are the
blank rows the layout carried. The final rows are

    0-1    Unit type 001 - Influence device
    2-4    [droid icon]  Alert : Green            text 2-3
    5-8    [ship icon]   Ship  : Paradroid        5-6
                         120 droids               7-8
    9-12   [deck icon]   Deck  : Repairs          9-10
                         9 droids                 11-12
    13-15  [alert icon]                           no text

and `consolesel.asm`'s `CON_SEL*` literals moved with them — the `ASSERT`s in `console.asm` tying
the two together are what caught them, which is what they are for.

**The unit line goes back to row 0, spending layer-9 DECISION 17's row again.** The arithmetic
leaves nothing over: 2 + 3 + 4 + 4 + 3 is exactly 16.

**THE ALERT LINE MOVED TO THE TOP; ITS ICON COULD NOT COME WITH IT.** The four icons are the
menu's selection targets and `ConMenu4` walks `conSel` 0-3 with up and down, so their rows must
ASCEND with `conSel` or the marker jumps about — and `conSel` 0 is "leave the console", which the
C64 puts at the top. The alert's icon is `conSel` 3, the ship's side view, and is therefore
necessarily the bottom one. The text is free and went; what that leaves is entry 0's icon with the
alert line beside it and entry 3's with nothing, where before it was entry 0 that had no label.
The three `ASSERT`s on the ascending rows are there so this cannot be undone by accident.

Text and icons never collide, which is what makes the move free: icons live in units 4-18 and
every text line starts at `CON_COL_TEXT`, unit 24. Only the unit-type line at `CON_COL_UNIT`
crosses the icon columns, which is why it has two rows to itself.

**BLANK ROWS BETWEEN THE SHIP AND DECK GROUPS WERE ASKED FOR AND ARE NOT POSSIBLE**, and the
arithmetic above is why: entry 0's icon ends at row 4, so the ship cannot start before 5; the ship
needs four rows for two text lines, so the deck cannot start before 9; the same again puts the
alert icon at 13, and 13 + 3 is 16. Every row is spoken for. A gap needs one of: the counts moved
onto the name's own line (3 rows an entry, freeing two rows, but no longer *underneath*); one of
the four icons dropped, which costs a menu entry its marker; or the unit-type line shortened and
moved right so an icon can share rows 0-2, which changes the original's own text. **Not built —
KC's call.**

*Alignment and the plural.* The count lines start at `CON_COL_TEXT + 9`, which is where the names
begin: "Ship  :" is eight cells from the label column — a capital is two cells and everything in
"hip  :" is one — and `ConTok`'s leading space is the ninth. "Deck  :" and "Alert :" are padded to
the same width by the original, which is what lets one constant serve all three. The digits are
therefore **left**-justified, not blank-padded to three; an earlier version right-justified them,
which lined the two counts up with each other instead of with the names.

*Neither count was available as-is.* The deck count is **not** `drCount`: that is the table's
high-water mark and it counts bullets and explosions too, so it would tick up when something
fired. The table is walked instead, counting only types below `DR_TYPE_BULLET` with energy left.
The ship count **is** `shipNumDroids` untouched — it looks one too many because `NewShipDroids`
seeds it with 1, but that 1 is not the player: it pre-counts the 999 written to `$1D` of the
roster after the placing loop without an INC of its own.

*The split, and the failed first attempt.* Counting is bank 4's (the droid table is there),
drawing is bank 6's, and only one bank is visible at a time, so the answer crosses in main RAM —
eight bytes in the `PARAFNT` block, `PN_TABS`' own trick. **They are finished ASCII strings, not
numbers**, because bank 6 is the region with 39 bytes free: the conversion belongs on the side
with room, and the reader is then one `ConLine` call. `PnAscii` already maps `'0'`-`'9'`, so
nothing was needed to print them, and the word is the game's own token 11, "droid", plus an `s`.

The fifth byte of each five-byte block is the **plural suffix, and it is the character rather than
a flag**: `'s'`, or a space when the count is 1 so the line reads "1 droid". Bank 6 prints it
unconditionally — `PnAscii` maps `' '` to `PN_SPACE` and nothing follows it on the line — because a
branch is three bytes that bank did not have.

**`CnCounts4` was written into `consolesel.asm` first and had to be moved out.** That file sits in
front of `colourMap`'s `ALIGN` on the reasoning that the pad takes anything assembled there for
nothing. **The pad is spent**: 200 bytes put in it cost the bank 259, because past the pad the
ALIGN rolls a whole page. That is the trap `consolesel.asm`'s own header warns about, now
measured — treat the pad as full.

*What it cost, measured:*

| Region | Before | After |
|---|---|---|
| Bank 4 | 143 B | **14 B** |
| Bank 6 | 39 B | **7 B** |
| `PARAFNT` block | 26 B | 16 B |
| Code image | 7 B | 7 B — untouched |

**Both banks are now as tight as the code image.** Anything further in either needs one of
`ram-pass.md`'s held reserves cashed in first — `sprsplit.asm` to bank 5 is the cheapest.

*Verified in jsbeeb.* On a deck of nine droids the console read `Ship : Paradroid / 120 droids /
Deck : Repairs / 9 droids`. **CTRL+C** (`DEBUG_KILL`) then cleared the deck and the same console
read **111** and **0** — nine off both, the deck bonus in the score. Three-digit, two-digit and
one-digit cases all rendered and stayed aligned under the names. The singular was checked by
poking `shipNumDroids` to 1 and reopening: "1 droid" above "9 droids" on the same screen. (The console was reached by poking `DoCharUnder`'s
`CMP #CHAR_CONSOLE` to `LDA #0` in the running machine so fire opens it anywhere; a runtime patch
only, and a useful one to know for any future console work.)

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

**Two of the Redux adoptions are waiting on this log rather than on a decision** — DECISION 2's
lift-adjacent droid starts, and DECISION 3's droid-droid deadlock. Both have their answer written
down and neither should be built on spec. What to watch for: **droids that arrive at a lift the
moment you step out of one**, and **two or more droids stuck against each other for more than a
second or so**. The second one has a harness recorded in DECISION 3 and a measured baseline —
1.4 s is the longest jam seen without the player involved, so anything visibly longer than that is
new information and worth the deck number.

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

