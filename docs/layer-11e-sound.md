# Layer 11e — Sound: the SN76489 driver

**Status: PLANNED, not built.** Scoped with KC 2026-08-21; the four architecture decisions in §7
were taken before any code. This document is the spec and the implementation plan. Nothing below
has been verified in the emulator yet except where a measurement is cited from another layer's
notes — and §5 stage 0 exists precisely because the SN76489 write sequence itself is a recalled
fact (`layer-11-sound-title.md` §6) that the standing rules forbid building on unverified.

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

**Volume.** `AdjustVolume` (`$0CB4`): +/− keys move `sndVolume`, applied as the SID master
volume nibble.

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
| $16 | `con_Back2Main` `$2CB8/$2CC3`; `DoLift` `$2696` (v2); game-over seam `$14E7` (v2) | Mode-change chord |
| $17 | `RunDroids` `$17EB` (with the +250 bonus) | Droid destroyed by ramming |
| $18 | `DoAlertAndAging` `$3E83` (voice 2, idle-retrigger) | **Per-deck background hum** |
| $19 | `DoCollision` `$1B17/$1B29` | Player collision damage |
| $1A | `DoCollision` `$1A7D` | Collision bump |
| $1B | `xferDoCounter` `$2106` (v2); `Capture` `$22C8` | Transfer time-up warning / start |
| $1C | `AnimateDroids` tail `$3E2F` (every 8 ticks in transfer move mode) | Two-droids-joined pulse |
| $1D–$1F | `Sound._chatter` `$0565` (pitch class picked by `$D41B` random) | Title chatter blips — **deferred**, §8 |

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
| Master volume (`$D418` nibble) | Attenuation offset added per channel; +/− keys as on the C64 |
| Frequencies | `N = 2129000 / F_SID`, computed **offline** per record — [DECISION 2]. Sub-122 Hz content clamps to N=1023; the exporter reports every effect's range so offenders can be reviewed (moving them to periodic noise is the usual cure) |

A SID linear-in-frequency slide is not linear in SN period. The exporter converts per segment:
compute the segment's start and end frequency, convert both, and emit a linear period slide
between them. Over one segment of one effect the curvature difference is inaudible; it keeps the
runtime free of division.

## 4. The driver

**`SndTick` runs at 50 Hz from the IRQ, and lives in bank 4 with all its data.** [DECISION 1]
The IRQ pages the bank itself: save `ROMSHAD` (`&F4` — already written by every `PAGEBANK`, so
it always names the bank in the window), `PAGEBANK SWRAM_DATA`, tick, restore the saved bank to
both `ROMSHAD` and `ROMSEL`. ~60–80 cycles of overhead on top of the tick proper. This **amends
the standing rule** — "the IRQ reads neither bank" becomes "the IRQ pages explicitly and
restores what it found" — and `bufcore.asm`'s header, `main.asm`'s rupture note and `CLAUDE.md`
must all be updated when it lands. The rule audit it depends on: nothing may ever write `ROMSEL`
without `ROMSHAD` (true today — `PAGEBANK` and `PageBankIn` are the only writers) and nothing
may run with them disagreeing across an STA pair — the macro's order (shadow first) already
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

### Stage 1 — `tools/export_sound.py`

Reads `prgs/` (original release), extracts the 31 × 16 records at `$C610` and the 8 × 8
instruments at `$EAA0`, converts per §3, emits `src/data/sounddata.asm` (gitignored, regenerated
like the rest). Also emits a human-readable dump — effect number, instrument, waveform,
frequency range, segment structure, chain — which is how each inventory row in §2 gets its
sound checked against what the data says it should be. Reports every sub-122 Hz clamp.

### Stage 2 — the driver core

`src/sound.asm`, assembled into the `PARADAT` block beside its data. `SndTick`, `SndReset`
(the `sndState` machine), the register-write layer with the port A save/restore, the envelope.
The IRQ shim (save `ROMSHAD` / page / `JSR SndTick` / restore) in `main.asm`. First audible
milestone: poke `sndFx1` from the debugger, hear effect `$12`.

### Stage 3 — the triggers

Every §2 site has a port-side home already (`DoFire`, `KillDroid`, `CbCheckDeath`, `DoCollision`,
`ChangeDeck`, the console, the transfer game, `GameStart`, the game-over seam, the energiser,
the alarm ticks in the animate tail). Wire each as a `STA` of the original's number, verbatim,
including `$84` for the disruptor and the `weaponType+1` arithmetic. `LoadDeck` gains the
three-byte `deckBgSndVar` patch into the effect-`$18` record — which now lives in bank 4, where
`LoadDeck` already runs. Pause writes `sndState` 0/`$12`; +/− volume keys port `AdjustVolume`.

### Stage 4 — verification

Per effect: trigger in game, `start_sound_capture`, compare register traffic against the
exporter's dump of what the record should do. Whole-game: a played pass over a deck with
combat, lift, console and transfer, listening for the per-deck hum changing between decks.
`DEBUG_TIME` the tick at the worst case again with everything wired.

## 6. Where the RAM comes from

| | budget | note |
|---|---|---|
| Driver code, bank 4 | 550–700 B | transliterated `Sound` + register layer + envelope |
| Effect records, bank 4 | 372 B | 31 × 12 (16 minus the four pulse bytes) |
| Instruments + envelopes, bank 4 | ~100 B | 8 instruments |
| Sequencer state, bank 4 BSS | ~48 B | |
| **bank 4 total** | **~1,070–1,220 B** | **against 1,161 B free** |
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

## 8. Deferred

- **Title chatter** — [DECISION 4]. Needs a `TiWait` tick throttled by VSync and an LFSR in
  place of `$D41B`. The three effect records can ship with the rest when wanted.
- **Sub-122 Hz effects** — any effect the exporter reports clamping hard gets reviewed
  individually (periodic noise is the usual voice for a deep rumble), rather than solved
  generically now.
