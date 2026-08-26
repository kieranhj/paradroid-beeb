# Layer 11e — Sound: the SN76489 driver

**Status: stages 0–3 BUILT, 2026-08-21 — the game plays with sound.** Scoped with KC the same
day; the architecture decisions are in §7, each stage's results are inline in §5, and §8 holds
what stage 4 (the by-ear pass with KC) and later still owe. §1–§3 are the C64 analysis and the
mapping design, kept as written.

---

## 1. What the C64 does

`Sound` (`$0500`), called from `Irq_118` at 50 Hz. It is not a music player — Paradroid has no
music — it is a **two-voice effect sequencer**:

- **Requests.** Game code stores an effect number 1–31 into `sndFx1` (`$91`, voice 1) or `SndFx2`
  (`$92`, voice 2) and the next tick picks it up. A request whose **bit 7 is set** (only the
  disruptor's `$84`) makes the playing effect uninterruptible: while `sndActive` holds a negative
  value, new requests on that voice are discarded (`$05AB`).
- **Mode.** `sndState`: 0 = silence (full chip reset each tick), `$11` = title chatter,
  `$12` = game mode (each `$1x` value initialises and drops to `$0x`). `DoPause` writes 0 on
  pause and `$12` on resume. `TitleLoop` writes 0 then `$11`; `StartGame` writes `$12`.
- **Effect = 16-byte record** at `$C610 + (n-1)*16` (the annotation labels them `sfxN`,
  zero-based, so `sfx23` = effect `$18`). Byte 0 is an instrument number; bytes 1–15 load the
  per-voice state at `$C0`–`$CE`:

  | offset | ZP | meaning |
  |---|---|---|
  | 1–2 | `snd_C0/C1` | initial frequency, 16-bit SID value |
  | 3–4 | `snd_C2/C3` | frequency slide, added every tick |
  | 5 | `snd_C4` | segment timer (ticks) |
  | 6 | `snd_C5` | segment timer reload |
  | 7 | `snd_C6` | segment count — effect ends when it hits 0 |
  | 8–11 | `snd_C7–CA` | pulse width + pulse slide (SID-only) |
  | 12 | `snd_CB` | segment mode: 1 = reset frequency from CC/CD (sawtooth sweep), else negate the slide (triangle warble) |
  | 13–14 | `snd_CC/CD` | the reset frequency |
  | 15 | `snd_CE` | chain: effect to queue when this ends, 0 = none |

- **Instrument = 8 bytes** at `$EAA0`: seven raw SID registers (freq is overwritten at once, so
  effectively pulse width, control/waveform, ADSR) plus a **gate-hold duration** in ticks; after
  that many ticks the gate bit is dropped and the SID release runs.

**The game only ever sounds two voices.** Game-mode init writes `$D418 = $8F` — bit 7
*disconnects voice 3 from the output*. Voice 3 is set free-running at `$FFFF` as noise purely so
`$D41B` (oscillator readback) serves as a hardware random number generator — read by the chatter
mode, the game-over sprite jitter (`$1487`) and others. The port already has LFSRs for every one
of those readers.

**Per-deck ambience is one effect with three patched bytes.** Effect `$18` is re-triggered on
voice 2 by `DoAlertAndAging` (`$3E73`) whenever that voice is idle, on a 32-tick phase. At deck
entry (`$135F`), `deckBgSndVar1/2/3[deck]` (`$6E60/70/80`) are copied into `sfx23+5/6/7` —
segment timer, reload and count — so each deck's hum has its own rhythm and length.

**Volume.** `AdjustVolume` (`$0CB4`): F5 and SHIFT-F5 move `sndVolume` 0–15 on every fourth
frame, applied as the SID master volume nibble and printed as `Volume: nn`. **Called from
`TitleLoop` and nowhere else** — the C64's volume cannot be changed once a game has started,
and it has no mute. The port keeps the range, the clamp and the repeat rate and changes the
rest; §9.

## 2. The effect inventory — every trigger in the original

Voice 1 unless stated. Addresses are the `STA sndFx1`/`SndFx2` sites in
`paradroid_ce_annotated.asm`.

| # | Trigger site(s) | Sound |
|---|---|---|
| 1–4 | `DoFire` `$33E0` (= `weaponType+1`); `AddBullet` `$351F` (voice 2, = firing droid's weapon class +1) | Laser fire, one effect per weapon class |
| 4 as `$84` | `Disruptor` `$233C` | Disruptor blast — the only uninterruptible effect |
| 5 | `EndGame` `$3800` | "Game over" message |
| 6 | `StartGame` `$126D` | New-game start |
| 7 | `_entership` `$1334` | Deck materialise / game entry |
| 8 | `AnimateDroids` tail `$3E03` (voice 2, every 32 ticks while `droidEnergy < 8`) | Low-energy alarm |
| 9 | `Capture` `$22C1` (voice 2) | Transfer game entry |
| $A | `xfer_DoMove` `$1DED` | Transfer: fire a pulser |
| $B | `FinishTransfer1` `$2226`; `ShowXferInfo` `$374C`; `StartGame` `$1284` | Transfer result / info screen / ship announce |
| $C | `FinishTransfer1` `$21F6`; `ShowXferInfo` `$376D` | Transfer result 2 / info screen 2 |
| $D | `FinishTransfer1` `$2238` | Transfer result 3 |
| $E | `Capture` `$22DC` | Transfer failed |
| $F | `EndGame` `$37BF` | The dissolve wash |
| $10 | `ChangeDeck` `$271B` (v2) + `$2729` (v1) | Lift moving — one blip per deck passed, on both voices |
| $11 | `PlyFireEnemy` `$1C36` (voice 2) | Bullet hits droid, damage but no kill |
| $12 | `KillDroid` `$1C5A` (v2); `Disruptor` `$23FB`; `BlowInto001` `$15AE` | Droid explosion |
| $13 | `_gameover` `$146B` | Player death explosion |
| $14 | `DoCharUnder` `$2EAD` | Energiser recharge tick |
| $15 | `conRedraw` `$2C85`; `DrInfo1–4` `$2CF6/$2D31/$2D4D/$2D76` | Console beep / page flip |
| $16 | `con_Back2Main` `$2CB8/$2CC3`; `DoLift` `$2696` (v2); **console OPEN `$14E7` (v2)** | Mode-change chord |

> **`$14E7` was mis-attributed here as "the game-over seam", and the port acted on it.**
> The label above it is `_console`: `$14DD`-`$14EB` save the VIC state, switch the character
> base and set `consoleState` to `$C0`. It is the console opening, and nothing to do with
> `EndGame`. `GoWashStart` posted it on the way into the wash on the strength of this row,
> so the console's chord announced the game over; KC heard it and it is gone (2026-08-21,
> Layer 11d). **`EndGame` posts exactly two effects: `$F` at `$37BF` and 5 at `$37FE`.**
| $17 | `RunDroids` `$17EB` (with the +250 bonus) | Droid destroyed by ramming |
| $18 | `DoAlertAndAging` `$3E83` (voice 2, idle-retrigger) | **Per-deck background hum** |
| $19 | `DoCollision` `$1B17/$1B29` | Player collision damage |
| $1A | `DoCollision` `$1A7D` | Collision bump |
| $1B | `xferDoCounter` `$2106` (v2); `Capture` `$22C8` | Transfer time-up warning / start |
| $1C | `AnimateDroids` tail `$3E2F` (every 8 ticks in transfer move mode) | Two-droids-joined pulse |
| $1D–$1F | `Sound._chatter` `$0565` (pitch class picked by `$D41B` random) | The **briefing's** chatter blips, not the title's — built 2026-08-22, §8 |

## 3. SN76489 vs SID — what maps and what compromises

The BBC's SN76489 (4 MHz): 3 tone channels with 10-bit period (`f = 250000/(16*N)`, so nothing
below ~122 Hz on a tone), 1 noise channel (white or periodic, rates /512 /1024 /2048 **or clocked
by tone channel 3**), 4-bit attenuation per channel in 2 dB steps. No envelopes, no pulse width,
no filter, no readback. Written through System VIA port A + the slow-bus handshake — the same
port A the keyboard matrix uses, which drives §4's contention rules.

| SID feature | Port |
|---|---|
| Voice 1 / voice 2 | SN tone channels 0 and 1, like for like |
| Noise-waveform instruments (explosions, disruptor) | **SN noise channel, clocked by silenced tone 3** — pitched, sweepable noise, the SID's frequency-swept explosions almost exactly. Tone 3 is otherwise unused |
| Two simultaneous noise effects | **Latest wins** on the one noise channel — [DECISION 3] |
| ADSR envelope | Software: attack step / decay step / sustain level / release step per instrument, one attenuation write per tick, derived offline from the SID ADSR nibbles and rate tables |
| Pulse width + pulse slide | Dropped — bytes 8–11 of each record are not carried |
| Voice 3 as RNG (`$D41B`) | The port's existing LFSRs (`DrRandom`, `XfRand`) |
| Master volume (`$D418` nibble) | Attenuation offset added per channel, clamped to 15; cursor UP/DOWN and Q, §9 |
| Frequencies | Records stay in **SID-frequency space, verbatim**; the driver converts to an SN period **at chip-write time** through a generated 128-entry normalise-and-lookup table (`N = tab[(F<<s)>>8] >> (8-s)`, ±0.5%, ~60 cycles). See below for why — a stage-1 discovery amended [DECISION 2]'s mechanism |

**Why frequency-space records (stage 1 finding).** The plan first called for offline conversion
to period space with fitted linear period slides. The exporter's trajectory simulation killed
that: the C64 sequencer adds the slide to a 16-bit frequency **mod 65536** (`$05E0`), and
several effects depend on the wrap — fx9 slides −8192/tick from F=11520, wrapping every 8
ticks, and the sound *is* that repeating downward zipper (fx5 wraps 39 times). No linear period
slide can express it. Keeping the C64's own arithmetic on the C64's own bytes is both more
faithful (records are verbatim minus the four pulse bytes) and simpler; the price is a 256-byte
conversion table and ~60 cycles per changed frequency, which the budget absorbs. [DECISION 2]'s
intent — offline tool, mechanical derivation, no runtime division — stands; the division became
a table.

## 4. The driver

**`SndTick` runs at 50 Hz from the IRQ, and lives in bank 4 with all its data.** [DECISION 1]
The IRQ pages the bank itself: save `ROMSHAD` (`&F4` — already written by every `PAGEBANK`, so
it always names the bank in the window), `PAGEBANK SWRAM_DATA`, tick, restore the saved bank to
both `ROMSHAD` and `ROMSEL`. ~60–80 cycles of overhead on top of the tick proper. This **amends
the standing rule** — "the IRQ reads neither bank" becomes "the IRQ pages explicitly and
restores what it found" — and `bufcore.asm`'s header, `main.asm`'s rupture note and `CLAUDE.md`
must all be updated when it lands. The rule audit it depends on: nothing may ever write `ROMSEL`
without `ROMSHAD` (true today — the `PAGEBANK` macro and, since RAM pass 5, its subroutine forms
`PgData`/`PgSpr`/`PgSpr2`/`PgXfer` keep the pair adjacent and shadow-first inside the helper;
`PAGESPRBANK`, `SprFetchRow`, the low overlay and the IRQ itself stay inline) and nothing
may run with them disagreeing across an STA pair — the shadow-first order already
guarantees the IRQ sees a consistent claim.

**Placement within the field**: appended to the `RuptVSync` path, after its CRTC work, so it
never sits between a T1 deadline and its write. The rupture's own stages stay untouched. The
tick's cycles come out of whatever main-loop phase is running — the same budget a main-loop tick
would spend, and window A's measured slack is 2,959 cycles/pass (`raster-timing.md`), so the
tick must stay cheap: target ≤ 400 cycles typical (envelope steps + a few register writes),
≤ 1,000 worst case (effect start, 10+ register writes with their 8 µs holds). Measure with
`DEBUG_TIME` before calling it done.

**State**: all sequencer and envelope state is bank 4 BSS (~48 B). Only the request interface is
main RAM — `sndFx1`, `sndFx2`, `sndState`, `sndVolume` — so console (bank 6), transfer (bank 7),
low-overlay and main-RAM code all trigger sounds with a plain `STA`, the existing mirror pattern.
Zero page is full; four absolute bytes in one of the existing main-RAM holes.

**Port A contention**: the keyboard is scanned by OSBYTE `&81` from the main loop, and it
manipulates DDRA (`&FE43`) and ORA (`&FE4F`) — the same registers a sound write uses. The IRQ's
register-write layer therefore **saves and restores both around its writes**. The addressable
latch is safe untouched: a sound strobe writes only bit 0 (`&00`/`&08` to `&FE40`), never the
keyboard-enable bit. This is a recalled analysis, not a fact — stage 0 verifies it with a held
key while effects play.

**The sequencer is a transliteration of `Sound`**: same request pickup, same bit-7 priority,
same segment timer / negate-or-reset / count-down / chain structure, same gate-hold-then-release
instrument shape — with the SID register image replaced by (SN period, noise flags, envelope
state) and the pulse fields gone. Faithful by construction where the hardware allows it.

## 5. Staging

### Stage 0 — verify the hardware facts (nothing built on recall)

**Items 1–3 DONE 2026-08-21, in jsbeeb, via `tools/sndtest.asm`** — a standalone harness poked
to `&2000` (or `build/SNDTEST.SSD`, `*RUN SNDTEST` then the `CALL`s in its header). Item 4 needs
the game build and moves to the head of stage 2, where the IRQ shim it measures is written.

1. **The write sequence — VERIFIED.** Latch byte `1 cc t dddd`, data byte `0 0 dddddd`,
   attenuation `1 cc 1 aaaa`; DDRA `&FF`, data to `&FE4F`, /WE strobed through addressable
   latch bit 0 (`&00`/`&08` to `&FE40`), ~15 µs hold. `read_sound_state` after `CALL &2003`:
   CH0 tone = 284 = **440.1 Hz**, which also confirms the 4 MHz chip clock and
   `N = 125000 / f` exactly.
2. **Noise — VERIFIED.** `&E4` = white /512 (register reads 4). `&E7` = white clocked by tone
   2 (register reads 7): with tone 2 written but silenced and its period swept 1023 → 79, the
   capture shows every two-byte tone write latching correctly and the noise pitch tracking —
   the explosion voice works as designed. Periodic (`FB=0`) is the same register path, taken
   on trust from the verified encoding.
3. **Port A contention — VERIFIED, the save/restore is sufficient.** The harness's `SndWr`
   saves and restores DDRA and ORA around the strobe, exactly the production shape. With a
   sound write on every MOS 100 Hz IRQ against 8,192 foreground OSBYTE `&81` polls of SPACE:
   key up, **0 of 8,192** polls read down (no phantoms, 225 IRQ writes interleaved); key held,
   **8,192 of 8,192** read down (no misreads, 192 writes interleaved); and CH0's attenuation
   ended at exactly the 7 the IRQ was writing both times.
4. IRQ placement: tick stub in `RuptVSync`, `DEBUG_TIME` the cost, confirm the rupture stays
   clean over the worst pass (full sprite pool + level draw). **Moved to stage 2**, whose shim
   is the thing being measured.

### Stage 1 — `tools/export_sound.py` — DONE 2026-08-21

Reads `paradroid_ce.lst` via `rip_levels.parse_listing` (the same source as every exporter,
with a hard fail if either table range is unfilled), and emits `src/data/sounddata.asm`
(gitignored, regenerated): the 31 records verbatim-minus-pulse at 12 bytes each (372 B), **12**
instruments — not 8; the records name 0–11 — converted to envelope steps (72 B), and the
128-entry frequency→period table (256 B). **700 B of data, assembles clean.**
`tools/output/sound_dump.txt` (gitignored) is the review dump: per effect, the decoded record
*and a simulation of the C64 sequencer's actual trajectory* — Hz range, wrap count, SN period
range, share of ticks below the tone floor.

**Findings that fed back into the design:**

- **The wrap discovery** (§3): slides run mod 65536 and the zipper effects depend on it —
  records therefore stay in frequency space and the driver converts at write time.
- **The per-deck hum survives intact.** fx24 spends only 7% of its ticks below the SN tone
  floor — its rising ramps live mostly above 122 Hz.
- **The review list** (§8): six tone effects spend ≥40% of their time below the floor and will
  play flat-at-122 Hz until treated: **fx04 the disruptor (100%!)**, fx26 collision bump
  (100%), fx23 ramming kill (73%), fx16 lift blip (48%), fx17 bullet-hit (41%), fx06 new-game
  (40%). Periodic noise clocked by tone 2 reaches ~15× lower and is the likely cure, but it
  competes with the explosion noise — stage 4's call, with KC, by ear.
- All three weapon-fire noise sweeps and both explosions land comfortably in range.

### Stage 2 — the driver core — DONE 2026-08-21

`src/sound.asm` (1,018 B) in the `PARADAT` block beside its 508 B of data; the IRQ shim
(save `ROMSHAD` / page bank 4 / `JSR SndTick` / restore both) at the end of `IrqHandler`'s
VSync branch; `sndFx1/sndFx2/sndState/sndVolume` as main-RAM request bytes. **Verified in
jsbeeb**: boot → title → game with the tick live throughout, effect `$12` poked into `sndFx1`
produced the full droid explosion on the capture — noise claimed with `&E7`, period starting
at N=263 (the maths says 260) sweeping to 487 as the pitch falls, instant attack, 8-tick gate
hold, release stepping one attenuation every 4 ticks: instrument 5's exact shape.

**Making it fit — where §6's overrun went.** The budget said 150–300 over; reality was 629.
Three moves closed it, in order of size:

1. **`chardata`'s bitmaps ship ZX0-packed** (1,096 → 640 B). `BuildCharset` unpacks them into
   the sprite background save areas — dead at every `LoadDeck`, its only caller — with the
   depacker already in the bank, then converts from there. The ALERT lamp's live re-colours
   (`BuildLampChar`, lowcode) read an 8-byte `lampSrc` cache BuildCharset fills, since the
   scratch is gone by play time; that also deleted the lamp's offset arithmetic and freed
   `lampTmp`. Emission order matters: `charRemap` (page-aligned) now leads the file, because
   trailing it cost 200 B of `ALIGN` padding once the bitmaps packed. **Verified**: title,
   first deck and a `DEBUG_DECK` hop all render correctly from the packed set.
2. **The chain byte and its code path are gone** (11-byte records): no record in the data
   chains — `export_sound.py` asserts it stays true.
3. **The conversion table halved to 64 entries** (midpoint divisors, max pitch error 0.78%,
   under the chip's own quantisation at the top end).

Bank 4 ends `&BFB2` — **78 B free**, and `main.asm` now PRINTs the bank-4 fuel gauge on
every build.

**One real bug caught by the first capture**: `SndConv`'s F<2048 clamp shortcut is a *tone*
rule, and it flattened the (noise) explosion to N=1023. Noise voices now pre-scale F×16 with
saturation and take the tone path — smaller and correct.

**Measured tick costs** (breakpoint pairs over the shim, per `raster-timing.md`'s method):
**475 cycles idle**, **1,161 active** (explosion playing: convert + two tone writes + the
occasional attenuation), **2,425 on the effect-start tick** (request pickup + record and
instrument copy, one-off). All far inside the VSync → fire 1 gap of ~10,700; against window
A's 2,959 spare the active tick leaves ~1,800, and the idle cost is the permanent price of
having ears. If that ever pinches, the first optimisations are `SndWrByte`'s generous ~15 µs
hold (the chip needs ~8) and the flush's three-channel scan.

### Stage 3 — the triggers — DONE 2026-08-21

Every in-game site from §2 is wired as a `STA` of the original's number: `DoFire`
(`weaponType+1`), `CbDisruptor`'s `$84`, `DrAddBullet` (the firing droid's class+1, voice 2),
`DrPlyFireEnemy`'s hit/`DrKillDroid`'s kill (the disruptor's kills route through it, covering
`$23FB`), the collision bump on the episode edge, `DrHurtPlayer`'s three damage arms, the
ram-kill, the energiser tick, `CbCheckDeath`'s two deaths (`$12` fallback / `$13` game over),
`GameStart` (`sndState = $12`, fx 6 — with fx 7 moved to voice 2 so both sound; our start is
instantaneous where the C64's countdown loop separated them), the lift's entry chord and
per-deck blips, the console's open/close chords and menu/page beeps, the transfer's entry
pair, pulser commit, time-up churn and three verdicts (win `$C` / lose `$D` / tie `$B` —
**provisional**, to be A/B'd against VICE in stage 4), the wash's message, chord and
recurring roar — and `GoTitle` silences the chip under SEI before `UninstallIrq` stops the
ticks. `LoadDeck` patches `deckBgSndVar` into effect 24's record, in-bank.

**`SndAmbient`** (bank 4, called once a pass beside `DoAging`) is the port of the two C64
sound tails: the hum re-post whenever voice 2 is fully idle, the low-energy alarm, and the
transfer-mode pulse — pass-rate masks at half the C64's frame masks, gated on `overPhase`
and, by call position, on the modal screens.

**Deliberately not wired**, recorded here: fx `$E` and `$B`'s `ShowXferInfo`/ship-announce
moments (their screens are not ported — they arrive with 11d/`PrintTokenString`); and pause
(the port has no pause feature at all — porting `DoPause` is its own small
piece of work, listed in §8). The ± volume keys were on this list too and came off it: §9.

**The RAM battle, round two.** The sites, `SndAmbient` and the 48-byte hum tables wanted ~185
more bank-4 bytes against 78. Paid by: `charRemap` folded into the ZX0 char stream (read only
in the depack windows; `UnpackChars` now serves `BuildCharset` and `BuildCharPtrs`, +87);
`charSlot` nibble-packed (+56); the flush rewritten from desire-arrays to direct diffed
writes (−66 B of driver, and `SndWrByte`'s hold became NOPs so Y survives as the channel
number); the conversion table quartered to 32 entries (±1.6% worst, on sweeping effects);
and a page-boundary `ASSERT` on the driver state block that buys carry-free copy stepping —
**if a regeneration ever fires that assert, nudge the state block, don't widen the copy.**
Bank 4 ends `&BFFD`: **3 bytes free**, the fullest region in the machine.

**Verified in jsbeeb**: `sndState` reads 2 in-game unpoked; effect 24's record holds a real
`deckBgSndVar` triple after deck load; 594 chip writes captured over five seconds of play —
the hum sustaining at its correct attenuation on channel 1, the fire's noise sweep on
channels 2+3, and a rising tone sweep from a collision cue — all from unpoked gameplay.

### Stage 4 — the by-ear pass with KC — largely DONE 2026-08-21

Ran as a live loop: KC played on accurate emulators and reported; each report was diagnosed
against a register capture, fixed, verified in the capture, and committed — ten rounds, all
described under stage 3's hum/explosion notes. **Signed off by KC's ear**: the per-deck hum
(wee and wubs), droid explosions, the collision bump, the disruptor, the ram-kill, the
bullet-hit, the lift sounds, and the game start.

**Still open, KC's list:**

- **The game-over set** (fx 5, $F, $13, $16) — was "needs work but leave for now"; **done
  2026-08-21 with Layer 11d**: $F alone on the wash (noise, instrument 4), 5 with the 999 page as
  `$37FE` posts it, and $16 removed from the seam entirely — see the note on the $16 row above.
- The transfer-verdict mapping (win/lose/tie → `$C`/`$D`/`$B`) is still the stage-3 guess —
  A/B against VICE or the real thing when convenient.
- The noise scale factor (`NOISE_SHIFT`) and the periodic ≈ pitch/15 approximation have
  passed the ear test in practice; a VICE A/B remains available if anything ever sounds
  transposed.
- fx06 (new game) was called pedestrian before it was parked with the start-smear fix; it
  returns — and gets its treatment — with the 001 screen (11d).

## 6. Where the RAM comes from

**As built (stage 2, 2026-08-21):**

| | measured | note |
|---|---|---|
| Driver code + state, bank 4 | 1,018 B | `sound.asm`, state and scratch included |
| Effect records, bank 4 | 308 B | 28 × 11 — chatter and chain dropped, see stage 2 |
| Instruments, bank 4 | 72 B | 12 × 6 |
| Frequency→period table, bank 4 | 128 B | 64 entries, midpoint divisors |
| `chardata` bitmaps repack | **−456 B** | + ~−200 B of `ALIGN` padding, see stage 2 |
| Request bytes + IRQ shim, main RAM | ~29 B | `sndFx1/2`, `sndState`, `sndVolume`, the shim |
| **bank 4 after all of it** | ends `&BFB2` | **78 B free** — the build PRINTs this now |

The original estimate was 150–300 over and reality was 629 (the driver ran 1,090 B, not
550–700, and the align padding ate part of the chardata win until the reorder). KC chose the
ZX0-chardata route over force-fitting on 2026-08-21 — full precision was kept until the last
128 B, and the bank keeps a real margin.
| Request bytes, main RAM | 4 B | in an existing hole |
| IRQ shim, main RAM | ~40 B | 110 B exist below `&3000` in pieces; the shim is the only new main-RAM code |

It fits bank 4 only if the estimate holds and nothing else claims the bank first. Contingencies,
in order: the three chatter effects' records need not ship (36 B); the exporter can pack records
tighter once real ranges are known (segment fields are mostly small); after that it is
`layer-13-ram-pass.md`'s candidate list again. **Bank 4's 1,161 B was the last liquid RAM in the
machine — this layer spends effectively all of it**, and anything after 11e needs a new source.

## 7. Decisions

All taken with KC on 2026-08-21, before building.

**[DECISION 1]** The driver is **IRQ-driven at 50 Hz** — the C64's own cadence, immune to
overrun passes — and lives **in bank 4, paged in by the IRQ around `SndTick`** via a
`ROMSHAD` save/page/restore. KC's call between three costed options (main-loop ticks at the
field waits; all-main-RAM; this). The all-main-RAM form was rejected as needing a ~1 K hunt in
a main RAM that has 161 B; the main-loop form was rejected in favour of the guaranteed cadence.
The standing bank rule is amended, not broken: the IRQ pages explicitly and restores.

**[DECISION 2]** Effects and instruments are **converted offline** by `tools/export_sound.py`
into SN-native records — mechanical derivation from `$C610`/`$EAA0`, the same faithfulness model
as the graphics exporters, no runtime division.

**[DECISION 3]** One noise channel, **latest wins**. Overlapping explosions merge; nothing goes
permanently silent.

**[DECISION 4]** **In-game sound first.** Title chatter (`sndState $11`, effects `$1D`–`$1F`)
is deferred: the title runs under the MOS IRQ with no pass structure, so it needs its own tick
plumbing in `TiWait`, and it should follow once the driver is proven, not gate it.
*(Discharged 2026-08-22, and the reasoning about `TiWait` was mistaken — see §8's first bullet.
The port has no `sndState $11`: 11f [DECISION 11].)*

## 8. Deferred

- ~~**Title chatter** — [DECISION 4]. Needs a `TiWait` tick throttled by VSync and an LFSR in
  place of `$D41B`. The three effect records can ship with the rest when wanted.~~
  **BUILT 2026-08-22 — `docs/layer-11f-frontend.md` §4f.** Both halves of that sentence were
  wrong. It is **not the title's**: `TitleLoop` zeroes `sndState` before `ShowTitle` and only
  writes `$11` after it returns, so the logo screen is silent and the chatter plays under the
  briefing — which runs after `InstallIrq` and was already being ticked at 50 Hz, so `TiWait`
  needed nothing. And the records did not ship with the rest: bank 4 carries **one rewritable
  scratch slot** (`sndFxChat`, effect 29) and the three real records live in bank 5 beside the
  briefing text. `SndTick` is unchanged — it walks to effect 29 like any other. The LFSR is
  bank 5's `brChSeed`.
- ~~**The ± volume keys — WANTED, KC 2026-08-22: "we'll definitely want that volume control."**~~
  **BUILT 2026-08-26 — see §9 below.** Promoted out of this list on the strength of the
  chatter's loudness rounds: three of them went into turning one effect down, and some of "too
  loud" is really "no way to turn it down". It landed **before** any further eared level
  deviations, deliberately, because a working master volume may make some of them unnecessary —
  `FX_LEVEL`'s fx16 entry above is the first thing to re-listen to now that it exists.

- ~~**Pause.**~~ **BUILT 2026-08-26 — §10 below.** `DoPause` (`$3B7C`) writes `sndState` 0/`$12`
  around itself and the driver already honoured both, which is most of why it was cheap. It was
  deferred through 11f and unbundled from the volume keys, which were wanted sooner; it followed
  them by an hour in the end.
- **Sub-122 Hz effects** — stage 1's review list: fx04 disruptor (100% of its ticks below the
  floor), fx26 (100%), fx23 (73%), fx16 (48%), fx17 (41%), fx06 (40%). **All but fx06 are now
  treated; the list the exporter prints is down to fx06 and fx17** (fx17 is muted rather than
  clamped, which was its cure).

  **Round eleven — fx16 goes periodic, and the chatter is what found it** (KC, 2026-08-22:
  the briefing's "background two tones are too loud and too monotonous... perhaps try periodic
  bass instead"). fx16 is the lift blip and the chatter reuses it on voice 2 (`$056A`), which
  plays it for **54 fields in every 64** — sparse in a lift, near-continuous under the briefing,
  and that exposure is the only reason a 48% sub-floor effect signed off in stage 4 came back.
  Its bounce **straddles the floor**: F 1840–2960 is 108–174 Hz, so the clamp collapsed a bass
  warble into an alternation between N=1023 and N=967 — two notes, 122 and 134 Hz, at
  attenuation 0. Exactly what KC described, and audible in the capture as a repeating 967/1023
  pair on CH1. `FX_PERIODIC` gains 16: instrument 10 is **cloned** rather than moved, because
  fx21 (the console beep, 254–346 Hz) shares it and is right as a tone. Now N 44–72 on the noise
  channel, **sub-floor 0%**, and the flush's round-eight rule silences CH1 so the old drone is
  gone rather than layered under. Verified in the capture: noise register 3, the pitch on
  silenced CH2 sweeping N 58–72, CH1 at attenuation 15.

  **The clone cost no RAM, which is why it could land at all** — bank 4 has four bytes and an
  instrument is six. `export_sound.py` now allocates clones into instrument slots **no record
  references** before extending the table: the C64's table has gaps (nothing names instrument 1)
  and a contiguous emitted table pays for them either way. The fx23 clone moved into slot 1 and
  fx16's took the slot it vacated at the end.

  **Round eleven, part two — and the level, which is a new mechanism.** KC on the rebuild: the
  pitch was right, "still too loud", and — asked directly — the in-game lift may go quieter with
  it. The C64 sustains fx16 at full (SR nibble `F`), which put it at **attenuation 0, 6 dB above
  the chatter blips it is supposed to sit behind**. `FX_LEVEL`, the second sanctioned place
  ported sound data may differ from the C64's bytes, sets its sustain instead: **nibble 9 =
  attenuation 6**, so it now sits 6 dB *below* them — a 12 dB swing from what KC heard. The
  100 ms attack ramp is untouched, so the blip keeps its swell — captured on CH3 as
  **12, 9, 6, 3, 0, then 6**.

  **A third round went further and was reverted.** Nibble 6 (attenuation 9, another 6 dB) on
  KC's "turn it down some more" put it 12 dB below the chatter, and KC took it back the same
  evening: too far. **Nibble 9 is the eared value** and the range either side of it is now known
  — 0 too loud, 9 too quiet. Do not drift it downwards again without asking.

  **If it ever reads as loud again, the transient is the thing to look at, not the body**: at
  attenuation 6 sustained, the one 20 ms tick at 0 is the loudest part by 12 dB. It is
  structural — the envelope climbs in `snAtk` steps until it overflows, so the peak is always
  full level, and the only way to lose it is an instant attack (`atk` 255), which lands straight
  on the sustain and costs the swell. KC's call if it comes to that.

  **`FX_LEVEL` is keyed by EFFECT, not by instrument**, and that is load-bearing: clone
  allocation moves instrument indices, so an index-keyed table would silently retarget the next
  time `FX_PERIODIC` changes. The exporter resolves the effect's instrument at emit time and
  **asserts every other effect sharing it asks for the same level**, so an override cannot leak
  into a sibling — the failure mode `FX_PERIODIC`'s cloning exists to prevent, caught at build
  time instead.

  **The in-game consequence, verified in the registers 2026-08-22.** `ChangeDeck` posts fx16 on
  **both** voices, and two noise claims share the one noise channel ([DECISION 3], latest wins),
  so the lift's doubled blip becomes a single one. Tested directly rather than reasoned about —
  `sndFx1` and `sndFx2` both poked to 16 during play, which is what `$271B`/`$2729` do:

  - the hum's tone channel went to attenuation 15 the moment the noise voice took its voice over
    (round eight's rule), and CH0 needed no write because it was already silent
  - one `Noise: 3` control write, one envelope on CH3 — **12, 9, 6, 3, 0, then 6** — and CH2
    sweeping the pitch for the full 27 ticks
  - **attenuation 15 on CH3 at the end: nothing left stuck**, and the per-deck hum re-posted on
    CH1 immediately after

  So the mechanism is sound, and the taste question — one blip per deck instead of a doubled one,
  quieter, at its real pitch — went to KC on a real lift ride: **"in-game lift sounds fine",
  2026-08-22.** Re-signed off, and fx16 is closed. **KC 2026-08-21:
  periodic noise clocked by tone 2 is the preferred cure** — it reaches ~15× below the tone
  floor and is an iconic BBC sound. Tuned by ear in stage 4, effect by effect, minding that it
  shares the one noise channel with the explosions.
  **The hum's story, 2026-08-21, two rounds.** KC's first play found its opening segment
  clamped into a loud flat 122 Hz drone over the throb (F starts at 256 = 15 Hz). Round one
  rendered the whole hum as periodic noise — **reverted by KC**: the tone hum was right, only
  the drone was wrong (`dd108a2` keeps the periodic machinery for stage 4). Round two, from
  the wiki's sn76489 page: **N=1 is a 125 kHz square, out of audible range and stripped by
  the LM324N** — a sanctioned in-period-domain mute. Instrument 3 is `MUTE_SUBFLOOR` in the
  exporter (flags bit 6): its sub-floor content MUTES, so the hum fades in as its sweep
  crosses the floor and each segment reset gets a one-tick articulation gap. Effects living
  *entirely* below the floor (the disruptor) must NOT take this flag — they would vanish;
  they keep the 1023 buzz pending stage 4.
  **Round three (same day): the mute must be the VOLUME, not the period.** Writing N=1 with
  the envelope live still clicked on real-accuracy emulators — each attenuation write shifts
  the chip's volume-derived DC offset, which is literally the chip's sample-playback
  mechanism (the wiki page's own explanation), and the hum's instant attack was a one-sample
  PCM pop. `SndConv` now signals "muted" in carry and the flush routes it into the existing
  silent-voice path: attenuation 15, period untouched. Unmuting writes the period before the
  volume, so the tone re-enters cleanly. Verified in the capture: the reset tick is a single
  `atten=15`, the return is period-then-`atten=10`, and the muted opening writes nothing at
  all.
  **Rounds four and five (same day)**: the wee itself was fading in mid-glide — its first
  seven C64 ticks are sub-floor — so `FX_OVERRIDES` in the exporter (the one sanctioned home
  for eared data deviations, each with its reason) re-bases fx24's F0 at 1836, putting the
  whole 20-tick glide above the floor: 122 → ~380 Hz, peaking well over the wubs. And the
  short low blip left in front of it was envelope tick quantisation: an
  instant-attack-instant-decay instrument held its attenuation-0 peak for a full 20 ms tick
  where the SID's peak lasts milliseconds. The attack-completing tick now falls straight into
  its first decay step (a branch retarget — zero bytes), so such instruments open at their
  sustain level. Captured: the full-length wee opens at `atten=10`, and no attenuation-0
  write exists anywhere in the hum.
  **Round six — the orphaned noise channel** (KC: the droid explosion "left on a note until
  the next sound cancels it"). The explosion's release was fading correctly until the hum —
  same voice — re-posted: a tone effect taking over the owner voice releases noise ownership,
  and with no owner nothing ever wrote channel 3 again, leaving the hiss frozen at its last
  attenuation. The flush now ends with a tail rule: **an unowned noise channel is silenced**,
  cache-diffed so it costs nothing steady-state. Funded by three driver trims (idle voices
  branch straight to the envelope; SndSilence no longer clears request bytes — every entry to
  state 2 passes through it anyway; a second `snf_att` entry taking A directly). Verified:
  CH3 reads attenuation 15 the moment the hum takes the voice. **Bank 4 is at 0 bytes free.**
  **Round seven — the cut, not the tail.** The remaining held note was the release draining
  *past* the sequencer's end with the frequency frozen — a 0.6 s constant-pitch fade the C64
  never plays: `ResetVoice` (`$0678`) writes the TEST bit then control 0 — **no waveform — an
  instant cut** at effect end. The port now does the same (level to 0, no envelope step on
  the way out), and idle voices run nothing at all — the only release that sounds is a
  mid-effect gate expiry, exactly the C64's semantics. Byte-neutral. Captured: the explosion
  fades through its sweep and chops dead on its final tick.
  **Round eight — the tone-side orphan** (KC: "after the white noise ends there's a tone, so
  it cannot be on the same channel?" — exactly right). The explosion takes over the voice the
  HUM was playing as a tone on channel 1, and a noise voice's flush never visits its own tone
  channel — so CH1 held the hum's last note at full level under the whole explosion, exposed
  when the noise cut. The mirror of round six. A noise voice's flush arm now silences its own
  tone channel (cache-diffed, before the owner gate — a non-owner has the same stale
  channel), funded by folding `SndAmbient`'s two energy tests and dropping a provably
  redundant `AND #&3F`. Verified: mid-explosion CH1 reads attenuation 15, and after the cut
  all four channels are silent until the hum re-posts.
  **Round nine — the disruptor and the bump go periodic** (KC: both "very pedestrian, a dull
  bong" — they share instrument 11, 100% sub-floor, so both clamped to a flat 122 Hz).
  `PERIODIC_BASS = {11}`: the pulse-train fundamental under the /16 noise scale lands within
  7% of the SID pitch, so both play their real 60–105 Hz warble. The driver's noise-control
  byte comes from the instrument flags again (`&E7` white / `&E3` periodic), funded by the
  request-pickup sharing its exit RTS and **dropping the attenuation clamp — safe ONLY while
  `sndVolume` is pinned at 15; AdjustVolume's port must restore it** (noted at its §8
  bullet). *(Restored 2026-08-26, six bytes, as the volume keys' first prerequisite,
  DECISION 15 in §9.)* Verified: noise register 3, CH2 warbling N 76–109, clean release, the hum
  untouched on CH1 throughout. Bank 4: 4 bytes free.
  **Round ten — three more from KC's playtest.** The ram-kill (fx23, 73% sub-floor) goes
  periodic via a new exporter mechanism, `FX_PERIODIC`: its instrument is shared with the
  transfer zippers (right as tones), so the exporter **clones** the instrument with periodic
  flags and retargets just that record — the dive now plays 177 Hz down to ~8 Hz pulse
  clicks. The bullet-hit's droning down-stroke: instrument 2 joins `MUTE_SUBFLOOR`, ending
  the chirp crisp (its sibling, the collision-damage riser, gains hum-style one-tick gaps at
  its resets). And the game-start smear — fx6 and fx7 played simultaneously where the C64
  spreads fx6/$B/7 across seconds of countdown and screens we lack — is cut to **fx7 alone**;
  6 and $B return with the 001 screen (11d). Verified: fx23 on noise register 3, CH2 climbing
  through the dive. Bank 4: 3 free (the 13th instrument cost 6).
  **The same session found a real driver bug**: `SndConv` counted its shifts in X, and the
  flush picks the channel from X after converting — every in-range voice-1 tone was landing
  on channel 0. The hum had escaped because its clamp path skips the shift loops. Counters
  moved to `snTm2`; the capture now shows the hum's whole cycle on channel 1.
- **PWM bass as an extension possibility** (KC 2026-08-21): a higher-frequency timer toggling
  one channel's volume gives crude PWM below the floor — but it steals gameplay cycles, so it
  is a costed extension for later, not part of this layer. Belongs beside
  `docs/master-extensions.md`'s entries if it is ever wanted.

## 9. The volume keys and the mute — built 2026-08-26

`AdjustVolume` is one of the few C64 routines this port does not take verbatim. Everything
that could be kept was: the 0–15 range, the clamp at both ends, and the every-fourth-frame
repeat gate, which lands on the same wall-clock rate here by different arithmetic. What
changed, changed because KC asked for it (this conversation) or because the BBC's shape forced
it.

**[DECISION 12] The keys are cursor UP and DOWN, not F5 and SHIFT-F5.** The C64 reads its
function-key row directly (`ReadFKeys`, `$0B23`) and folds the shift state into bit 7 of the
same byte; nothing about that survives the move to `OSBYTE &81` on a different matrix. The
cursors were free once the debug deck hop was moved, they are the obvious pair for "more" and
"less", and they collide with nothing: the lift steps on the movement keys K/M, not on these.

**[DECISION 13] It runs everywhere, not on the title alone.** `AdjustVolume` is called from
`TitleLoop` and from no other site, so on the C64 the volume is fixed for the duration of a
game. That is a limitation, not a design, and the loudness rounds above are what made it worth
overriding. Three call sites cover every state the port has:

| Site | Gate | Rate | Covers |
|---|---|---|---|
| `ml_passend` (main loop) | `gameTick AND 1` | 12.5 Hz | play, console, transfer, lift view, information screens, the game-over wash — every modal arm `JMP`s to this label |
| `BrWaitField` (briefing) | `fieldCount AND 3` | 12.5 Hz | the briefing, where the chatter is |
| `tiw_loop` (`TiWait`) | the `tiLo` carry, 1 in 256 | 26 Hz held | the title |

The high-score entry (`HsGet`) is **deliberately not wired**: it is a short modal, it is silent
(it runs from `TitleSeq`, after `GoTitle` has handed the IRQ back), and its loop has the same
free-running hazard as `TiWait` for no benefit.

**The title site is the awkward one, and it needed measuring.** `TiWait` is not field-locked:
its iteration count *is* the timeout, and `tiLo EOR tiHi` *is* the seed for the starting deck.
Its body is a single `keydown`, so polling three more keys every time round would nearly
quadruple it. Hanging the call on the `tiLo` carry costs nothing to test and pays for `VolKeys`
once per 256. Measured in jsbeeb: idle the loop turns **3,654 times a second** (so the 16-bit
wrap is a **17.9 s** timeout — it already was, and the gate costs it under 1%), and with a key
actually held it turns **6,720 times a second**, the MOS's key test being quicker when it finds
one. The repeat therefore lands at **26 Hz**, or 0.58 s from 0 to 15. A first cut gated 1 in
1024 and gave 3.6 Hz — four seconds end to end, unusable.

**[DECISION 14] Q mutes, and mute is `sndVolume` 0 with the old level stashed.** The C64 has no
mute at all. Volume 0 is already total silence by construction — `snf_voice` computes
`30 - levelNibble - sndVolume`, so at volume 0 every voice lands at or past attenuation 15 —
which is why this needs no driver support whatever. The alternative, `sndState` 0/`$12`, was
rejected: the briefing and `GoTitle` both write that byte for their own reasons and a mute flag
hidden in it would fight them. `sndVolume` is written by nothing else in the game.

`sndVolSave` holds the silenced level; Q on an already-silent chip restores it, or goes to 15
if the level was walked down to 0 by hand — either way Q is a request to hear something. Q is
edge-latched (`volQPrev`) where the cursors repeat.

**The setting outlives a game.** `sndVolume` and its two companions live in the resident code
image, which is loaded once at boot and never reloaded over, so a level set or a mute toggled
at the title is still in force in the game that follows and in every game after it. That is the
whole point of wiring the title at all, given there is no sound there to hear.

**[DECISION 15] The clamp round nine deleted is back, in the C64's 6-byte form.** This was the
prerequisite, not a nicety: `snf_voice`'s `30 - levelNibble - sndVolume` is 0–30 the moment
`sndVolume` can be less than 15, and an unclamped 16–30 wraps into the latch's channel bits.
`CMP #16 / BCC / LDA #15`, six bytes of bank 4's 51. §8's costed 4-byte alternative
(`CMP #16 / BCS snfv_off`) was **rejected on inspection**: it skips the period write as well as
the attenuation, so a voice quiet at a low volume freezes its pitch and jumps when the volume
comes back up.

**[DECISION 16] No readout anywhere.** The C64 prints `Volume: nn` on the title. The port shows
nothing: the panel's text line is already contended for by the messages and the transfer
counter, and the effect of the key is audible. `Volume_txt`'s port stays unwritten. KC,
2026-08-26: "Don't worry about indicating the volume change for now."

**`VolKeys` is main RAM, not bank 4**, although the driver it steers is bank 4's. Everything it
touches — `sndVolume`, `sndVolSave`, `volQPrev`, `keydown` — is main RAM, so it carries no
paging contract at all and each of its three call sites can use it from whatever bank happens
to be resting. That is what makes the briefing site free: bank 5 stays paged across it.

**Cost.** 6 B bank 4 (51 → 45), 98 B of the code image (`&2D81` → `&2DE3`), 3 B of `PARBRF`
(56 → 53), 11 B of `PARTITL` (855 free after). ~800 cycles every other pass in game, at
`ml_passend`, below every draw — measured no effect on the pass rate, which stays at exactly
25.0 Hz.

**Verified in jsbeeb, 2026-08-26.** Volume steps and clamps at both ends at the title, in the
briefing and in play; the level survives title → game; Q toggles exactly once across 13
consecutive poll rounds with the key held; muted, all four channels read attenuation 15 and
unmuting brings them back (CH0 6, CH3 9 under the chatter). The clamp itself was caught in the
act: at volume 2 with `snLevel[0]` = 85 (nibble 5) the unclamped value would be 23, and
`snChAtt` reads 15. `[` and `]` step the deck one press at a time and cursor UP no longer
touches it.

## 10. Pause — built 2026-08-26

KC asked for "pause/unpause button on P" the hour after the volume keys landed, and it shares
their call site and their key-poll machinery, which is why it is written up here rather than in
a layer doc of its own.

**What the C64 does.** `DoPause` (`$3B7C`), called from `GameLoop` at `$13E6` — **above** the
`consoleState` test at `$1427`, so the console, the transfer game and the lift are all pausable.
RUN/STOP enters. Inside, it draws `Pause_txt` (`$0BCF`) at the mode word's own `prntX`, writes
`sndState` 0, waits for the release, and spins. The manual (which the port's briefing reproduces
verbatim, `src/data/briefing.txt`) states the exits: *"fire - restarts, run-stop - restarts,
clr-home - quits game"*. On the way out it repaints, calls `InitColors`, restores `frameCount`
from `$55` and writes `sndState` `$12`.

**[DECISION 17] A blocking loop, not a flag the pass tests.** This is the one structural choice
and it went the C64's way after the alternative was costed. A `paused` flag checked in the main
loop looks tempting — the pass would keep drawing, so the picture would stay alive for free —
but the pass has five modal arms (console, transfer, lift view, information screen, game over)
that each end it at their own point, so the flag would need honouring in six places and the
console would still be answering its own keys while "paused". A loop freezes all six by standing
in front of them. That is why the original is written this way, and porting the decision means
porting the shape.

**The port's differences, all deliberate:**

| | C64 | Port |
|---|---|---|
| Enter | RUN/STOP | **P** |
| Leave | RUN/STOP or fire | **P only** |
| Quit from pause | CLR-HOME | not ported — ESCAPE is always available and ends a game properly |
| Message | `DrawString` of `Pause_txt` | the panel's own mode field |
| On exit | repaint, `InitColors` | repaint; no `InitColors` — nothing recolours it, the port has no `DoBlkWhte` |
| `frameCount` | saved and restored | nothing to do; see below |

Resuming on **fire** was dropped on purpose: it would fire the weapon on the way out, which is
exactly what the C64's wait-for-release dance at `$3BEB` exists to prevent, and one key meaning
one thing beats two that need choreography.

**The message costs almost nothing, because the panel was already built for it.** `PanelUpdate`
picks a mode word by index and repaints only when a shadow byte says the index moved — so
"Pause" is a fifth entry in `pnTxtTab`, chosen ahead of all four others when `paused` is set,
and *both* the paint and the repaint fall out of the existing compare. `paused` is main RAM for
`conActive`'s reason exactly: bank 6's `PanelUpdate` reads it and cannot see bank 4's. The five
trailing spaces in `"Pause     "` are the C64's own count — `Pause_txt` is five glyphs then five
`$30`s, and a capital is two cells there as it is here.

**`frameCount` needs no save/restore here.** The C64 increments it inside its pause loop and so
must put it back; `gameTick` counts passes and the pause happens inside one, so it does not move
at all. The C64's pair is a no-op in the port rather than an omission — worth stating, because
"the original does two things we don't" usually means something was missed.

**[DECISION 18] The picture freezes solid, and the C64's does not.** Its pause loop goes on
calling `AnimateDroids` (`$3CFB`) and the font animation, so the player's rotor keeps spinning
and the animated deck tiles keep cycling behind a frozen game. Reproducing that means running
the erase/animate/draw triple and the tile paint inside the pause loop, which means reproducing
the sprite pool's window and tranche handling outside the main loop. That is real work and not
to be done blind, so it is **recorded as wanted, not built**.

**The volume and the mute stay live while paused** — a small liberty, and an obvious one: pause
is when you reach for the volume. `VolKeysBrf` is reused unchanged, its `fieldCount` gate suiting
the pause loop's one-field cadence exactly.

**The bug the first build had, and the invariant behind it.** `WaitNextPass` waits for
`passF0 + FRAME_LOCK`, a target stamped at the top of the pass — and `DoPause` is called from
`ml_passend`, just above it. `WaitUntilField`'s distance is signed and good for 127 fields
either way; its own header said *"which is 2.5 seconds, and nothing here waits that long"*, which
was true until this routine existed. Hold the game longer and `fieldCount` laps the target into
the negative half, so the wait sits out up to 128 more fields. **Measured: after a seven-second
pause the game came back and then did not move for two seconds.** The fix is two instructions —
re-date `passF0` from `fieldCount` on the way out — and the invariant is now stated at
`WaitUntilField` itself, where the next person to block the pass will read it.

**No pause during a death.** `overPhase` gates the whole routine. The C64 never reaches `DoPause`
during its game over either (`EndGame` runs its own loop), and without the guard a pause taken
under the wash would write `sndState` `$12` on the way out and restart the sound mid-death.

**Cost.** 93 B of the code image, 22 B of bank 6, two main-RAM state bytes. One OSBYTE a pass
while unpaused.

**Verified in jsbeeb, 2026-08-26.** "Pause" appears in the mode field in red where "Mobile" was;
`gameTick` frozen across a seven-second hold; `sndState` 0 and all four channels at attenuation
15 while held; the volume keys still stepping (15 → 12) with the game frozen; P again restores
the word, `sndState` 2 and the sound, and the loop resumes at exactly 25.0 Hz within 0.2 s (50
passes in the next 4,000,000 cycles). P held for two seconds during a death does not pause, and
the death, the game over and the high-score entry run through untouched. **Not exercised: pause
with the console, the transfer game or the lift view up** — the call site is common to all of
them by construction, but it has not been driven there.
