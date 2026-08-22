#!/usr/bin/env python3
"""
export_sound.py - Convert the C64 sound tables to SN76489-ready BeebASM data.

Layer 11e stage 1 (docs/layer-11e-sound.md [DECISION 2]). Reads the effect
records at $C610 and the instrument table at $EAA0 out of paradroid_ce.lst
(the same source every other exporter uses; decisions.md carries the evidence
that the listing matches the original/CE releases byte for byte) and emits:

  src/data/sounddata.asm     - the shipped effect records (SID-frequency
                               space, verbatim minus the pulse fields), the
                               instruments as envelope steps, and the
                               frequency->period conversion table
  src/data/sndchat.asm       - the three chatter records, for the PARMAN
                               bank rather than bank 4; see the note below
  tools/output/sound_dump.txt- the review dump: each effect's simulated
                               frequency trajectory, wraps and all, in both
                               SID and SN terms, plus the sub-floor list

The chatter records live OUTSIDE the driver's table
---------------------------------------------------
Effects 29-31 are the chatter blips the C64 plays under the scrolling
briefing (TitleLoop writes sndState $11 at $115B, AFTER ShowTitle returns -
the logo screen is silent). Bank 4 had 15 bytes free when this landed and
three records are 33, so they are emitted into src/data/sndchat.asm and
assembled into PARMAN - bank 5, beside the briefing's text - while bank 4
carries ONE 11-byte scratch slot: .sndFxChat, effect number 29. BmChatter
(bank 5) copies its chosen blip into a main-RAM mailbox and BrChatter
(PARBRF) pages the data bank in and lands it in the slot before posting the
request. The driver is untouched by any of it: it starts effect 29 through
the ordinary sndFxTab walk and neither knows nor cares that the slot's
contents change. docs/layer-11f-frontend.md section 4f.

The scratch slot ships holding blip A verbatim, so a build that never runs
the chatter still has a valid record there.

Why the records stay in SID-frequency space
-------------------------------------------
The sequencer adds the slide to a 16-bit frequency every tick MOD 65536
($05E0), and several effects depend on the wrap: fx9's slide of -8192/tick
from F=11520 wraps every 8 ticks, and the sound IS that repeating downward
zipper. A pre-converted linear period slide cannot express it. So the
driver runs the C64's own arithmetic on the C64's own bytes - wrap, bounce
and reset included - and converts frequency to an SN period only at the
moment of writing the chip, through sndFreqLo/Hi below:

  normalize F to F' = F<<s in [$8000,$FFFF]  (s = leading-zero count)
  m = F'>>8 (128..255), T = table[m-128] = round(2128693/m), 16-bit
  N = T >> (8-s)   (s>8 never survives the 1..1023 clamp)

2128693 = 125000 * 2^24 / 985248: SID PAL Hz on top, the BBC chip's
125000/N (measured in stage 0: N=284 -> 440.1 Hz) underneath. Accuracy is
within +/-1 period step across the range (~0.5%). NOISE-instrument voices
shift 4 more: the SID noise LFSR shifts at ~16x the tone formula (bit 19
of the phase accumulator vs bit 23), and SN noise shifts at roughly the
driving tone's rate. First-principles estimate, tuned by ear in stage 4.

C64 model (Sound, $0500 - see docs/layer-11e-sound.md section 1)
----------------------------------------------------------------
Effect record, 16 bytes at $C610 + (n-1)*16, loaded into ZP $C0-$CE:
  [0]     instrument number
  [1-2]   initial frequency, 16-bit SID value        (C0/C1)
  [3-4]   frequency slide, added every 50 Hz tick    (C2/C3, signed)
  [5]     segment timer, first segment (0 = 256)     (C4)
  [6]     segment timer reload, later segments       (C5)
  [7]     segment count - effect ends at 0           (C6)
  [8-11]  pulse width + pulse slide - SID-only       (C7-CA, DROPPED)
  [12]    mode: 1 = reset frequency each segment,    (CB)
          else negate the slide (bounce)
  [13-14] the reset frequency                        (CC/CD)
  [15]    chain: effect to start when this ends      (CE)

Instrument, 8 bytes at $EAA0 + n*8 (StartInstrument, $06F7):
  [0-3]   freq/pulse placeholders (overwritten at once - dropped)
  [4]     SID control register: waveform bits, gate ORd in
  [5]     attack/decay nibbles
  [6]     sustain/release nibbles
  [7]     gate-hold duration in ticks

Emitted record, 11 bytes (offsets +5/+6/+7 kept = the C64's patch targets
for effect 24's per-deck deckBgSndVar values, which are used unconverted):
  [0]     instrument number
  [1-2]   initial frequency, SID 16-bit, verbatim
  [3-4]   slide, verbatim
  [5]     segment timer     [6] reload     [7] count
  [8]     mode              [9-10] reset frequency, verbatim
The C64's chain byte [15] is NOT carried: no record in the original or CE
data uses it (asserted below), so the driver has no chain path either.
If a different release ever chains, this assert is where it surfaces.

Emitted instrument, 6 bytes:
  [0]     flags: 0 = tone voice. Bit 7 = noise voice (SN channel 3 +
          silenced tone 2), with the SN noise-control low bits in bits
          0-2: 7 = white, 3 = PERIODIC - the buzzy bass that renders a
          sub-floor SID tone at pitch (fundamental ~ tone/15, within 6%
          of the white-noise scale, so one conversion path serves both).
          PERIODIC_BASS below lists which instruments take it.
  [1]     attack step, level-per-tick in 0-255 space (255 = instant)
  [2]     decay step
  [3]     sustain level, 0-255
  [4]     release step
  [5]     gate-hold duration in ticks

Requires: Python 3 only.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_ASM = PROJECT / 'src' / 'data' / 'sounddata.asm'
OUT_CHAT = PROJECT / 'src' / 'data' / 'sndchat.asm'
OUT_DUMP = PROJECT / 'tools' / 'output' / 'sound_dump.txt'

FX_BASE = 0xC610
NUM_FX = 31                   # in the C64 table
SHIP_FX = 28                  # in-game records, in bank 4's sndFxTab
CHAT_FX = (29, 30, 31)        # the briefing chatter's blips: NOT in the
                              # bank-4 table - they go to sndchat.asm and
                              # are copied into the scratch slot at run
                              # time (see the header)
CHAT_SLOT = 29                # the scratch slot's effect number, and so
                              # the driver's table length
CHAT_PRE = 5                  # bytes of a blip record that actually vary
                              # (instrument, F0, slide) - the rest is
                              # common and ships in the slot; asserted
INST_BASE = 0xEAA0

SID_CLOCK = 985248            # PAL
CONV_NUM = 2128693            # = 125000 * 2^24 / 985248, see header
NOISE_SHIFT = 4               # noise voices: N >> 4 more (= /16) - TUNABLE
TONE_FLOOR_HZ = 125000 / 1023  # ~122.2 Hz - lowest SN tone

TICK_MS = 20                  # 50 Hz driver tick

# Instruments rendered as PERIODIC noise (a 1/15 duty-cycle pulse train
# per the wiki's sn76489 page - a buzz, not a hiss). Tried for the hum
# and REVERTED by KC (the tone hum was right); ADOPTED by KC 2026-08-21
# for instrument 11 - the disruptor (fx04, 60-102 Hz) and the
# zero-damage collision bump (fx26, 90-98 Hz), both living entirely
# below the tone floor and both a flat 122 Hz bong as clamped tones.
# The pulse-train fundamental (tone/15) under the /16 noise scale lands
# within 7% of the SID pitch, so both play their real warble.
PERIODIC_BASS = {11}

# Per-effect record overrides - the ONLY place ported sound data is
# allowed to differ from the C64's bytes, each entry a deliberate,
# eared decision with its reason here.
#
# fx24 (the hum) initial frequency: the C64 starts its long first
# segment - the characteristic rising "wee" - at F=256 (15 Hz) and
# sweeps 20-odd ticks up to ~300 Hz. Our tone floor is 122 Hz, so
# started verbatim the first 7 ticks fell below it and the wee faded
# in mid-glide, reading as just another wub (KC). Re-basing the start
# just under the floor keeps the whole 20-tick glide audible:
# 122 Hz up to ~395 Hz, peaking clearly above the wubs' ~220 Hz.
# 1836 = 2081 (the floor's F) minus one tick of slide. Tune by ear.
FX_OVERRIDES = {24: {'f0': 1836}}

# Effects voiced as periodic bass WITHOUT moving their siblings: the
# effect's instrument is CLONED with periodic-noise flags and the record
# retargeted at the clone. fx23 (ram-kill) dives 165 Hz into the
# subsonic - 73% sub-floor, a flat bong as a clamped tone (KC) - but its
# instrument 9 is shared with the transfer-entry and time-up zippers,
# which are right as tones. As periodic bass the dive plays 177 Hz down
# to ~8 Hz pulse clicks: a machine winding down.
FX_PERIODIC = {23}

# Tone instruments whose sub-floor content MUTES instead of clamping.
# The wiki's sn76489 page: N=1 is a 125 kHz square - out of audible
# range, effectively silent, and the LM324N strips the carrier - so the
# driver clamps these to N=1 where others pin at N=1023 (~122 Hz).
# Instrument 3 is the per-deck hum's (effect 24 only): its opening
# segment sweeps up from 15 Hz, and the 1023-clamp played that as a
# loud flat drone layered over the throb (KC, first play). Muted, the
# hum fades in as the sweep crosses the floor, and the near-floor
# segment resets (F=2048, 120 Hz) still sound via the ordinary clamp.
# Instrument 2 (fx17 bullet-hit, fx25 collision damage): the hit's
# down-stroke fell through the floor and droned (KC); muted it ends
# crisp, and the damage riser gains hum-style one-tick gaps at its
# sub-floor segment resets.
# Effects that live ENTIRELY below the floor must NOT go here - they
# would vanish; they go periodic (PERIODIC_BASS / FX_PERIODIC) instead.
MUTE_SUBFLOOR = {2, 3}

# SID envelope rate tables, ms for the full 0->peak / peak->0 ramp
ATTACK_MS = [2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800,
             1000, 3000, 5000, 8000]
DECAY_MS = [6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400,
            3000, 9000, 15000, 24000]

# The section-2 inventory, 1-based
FX_NAMES = {
    1: "fire, weapon class 0 (player and droids)",
    2: "fire, weapon class 1",
    3: "fire, weapon class 2",
    4: "fire, weapon class 3 / the disruptor ($84 = uninterruptible)",
    5: "game over message",
    6: "new game start",
    7: "deck materialise / game entry",
    8: "low-energy alarm (voice 2, 32-tick phase)",
    9: "transfer game entry (voice 2)",
    10: "transfer: fire a pulser",
    11: "transfer result / info screen / ship announce",
    12: "transfer result 2 / info screen 2",
    13: "transfer result 3",
    14: "transfer failed",
    15: "endgame dissolve wash",
    16: "lift: one blip per deck passed (both voices)",
    17: "bullet hits droid, no kill (voice 2)",
    18: "droid explosion",
    19: "player death explosion",
    20: "energiser recharge tick",
    21: "console beep / page flip",
    22: "mode-change chord (console, lift entry, game-over seam)",
    23: "droid destroyed by ramming",
    24: "per-deck background hum (deckBgSndVar patches +5/+6/+7)",
    25: "player collision damage",
    26: "collision bump",
    27: "transfer time-up warning / start",
    28: "transfer-mode pulse (8-tick phase)",
    29: "briefing chatter blip A (triangle)",
    30: "briefing chatter blip B (sawtooth)",
    31: "briefing chatter blip C (pulse)",
}

WAVE_NAMES = {0x8: 'NOISE', 0x4: 'pulse', 0x2: 'saw', 0x1: 'triangle'}


def sid_hz(f):
    return f * SID_CLOCK / 16777216.0


def s16(lo, hi):
    v = lo | (hi << 8)
    return v - 65536 if v >= 32768 else v


def freq_to_period(f_sid, noise):
    """The runtime conversion, exactly as the driver will do it."""
    if f_sid <= 0:
        return 1023
    f = f_sid
    s = 0
    while f < 0x8000:
        f <<= 1
        s += 1
    t = round(CONV_NUM / (f >> 8))
    shift = (8 - s) + (NOISE_SHIFT if noise else 0)
    n = t >> shift if shift >= 0 else t << -shift
    return min(1023, max(1, n))


def env_step(ms):
    ticks = max(1, round(ms / TICK_MS))
    return min(255, -(-255 // ticks))     # ceil


def convert_instrument(idx, raw):
    ctrl, ad, sr, dur = raw[4], raw[5], raw[6], raw[7]
    noise = bool(ctrl & 0x80) or idx in PERIODIC_BASS
    if noise:
        flags = 0x80 | (3 if idx in PERIODIC_BASS else 7)
    else:
        flags = 0x40 if idx in MUTE_SUBFLOOR else 0
    return {
        'idx': idx, 'raw': raw, 'ctrl': ctrl, 'noise': noise,
        'flags': flags,
        'atk': env_step(ATTACK_MS[ad >> 4]),
        'dec': env_step(DECAY_MS[ad & 15]),
        'sus': (sr >> 4) * 17,
        'rel': env_step(DECAY_MS[sr & 15]),
        'dur': dur,
    }


def simulate(e, noise, max_ticks=600):
    """Run the C64 sequencer arithmetic; report what the effect does."""
    f = e['f0']
    slide = e['slide']
    timer = e['timer'] or 256
    reload_ = e['reload'] or 256
    count = e['count']
    freqs, wraps, ticks = [], 0, 0
    while count and ticks < max_ticks:
        for _ in range(timer):
            nf = (f + slide) & 0xFFFF
            if slide and ((slide > 0) != (nf > f)) and nf != f:
                wraps += 1
            f = nf
            freqs.append(f)
            ticks += 1
            if ticks >= max_ticks:
                break
        if e['mode'] == 1:
            f = e['fr']
        else:
            slide = -slide
        timer = reload_
        count -= 1
    if not freqs:
        return None
    lo, hi = min(freqs), max(freqs)
    sub = sum(1 for x in freqs
              if not noise and sid_hz(x) < TONE_FLOOR_HZ)
    return {'ticks': ticks, 'flo': lo, 'fhi': hi, 'wraps': wraps,
            'nlo': freq_to_period(hi, noise), 'nhi': freq_to_period(lo, noise),
            'sub_pct': 100 * sub // len(freqs)}


def convert_effect(n, raw, instruments):
    ov = FX_OVERRIDES.get(n, {})
    if 'f0' in ov:
        raw = bytes(raw[:1]) + bytes([ov['f0'] & 0xFF, ov['f0'] >> 8]) \
            + bytes(raw[3:])
    e = {
        'n': n, 'raw': raw, 'inst': raw[0],
        'f0': raw[1] | (raw[2] << 8), 'slide': s16(raw[3], raw[4]),
        'timer': raw[5], 'reload': raw[6], 'count': raw[7],
        'mode': raw[12], 'fr': raw[13] | (raw[14] << 8), 'chain': raw[15],
    }
    e['noise'] = instruments[e['inst']]['noise']
    e['sim'] = simulate(e, e['noise'])
    assert raw[15] == 0, \
        f"fx{n}: chain byte is {raw[15]} - the driver has no chain path"
    e['bytes'] = [raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6],
                  raw[7], raw[12], raw[13], raw[14]]
    return e


def main():
    mem, filled = parse_listing(LST_FILE)

    for base, size, what in ((FX_BASE, NUM_FX * 16, 'effect records'),
                             (INST_BASE, 8, 'instrument 0')):
        missing = [hex(base + i) for i in range(size) if not filled[base + i]]
        if missing:
            sys.exit(f"FATAL: {what}: listing has no data at {missing[:8]}...")

    fx_raw = [bytes(mem[FX_BASE + i * 16: FX_BASE + (i + 1) * 16])
              for i in range(NUM_FX)]

    # instrument table size = highest instrument any record names
    n_inst = max(r[0] for r in fx_raw) + 1
    missing = [hex(INST_BASE + i) for i in range(n_inst * 8)
               if not filled[INST_BASE + i]]
    if missing:
        sys.exit(f"FATAL: instrument table: no data at {missing[:8]}...")
    instruments = [convert_instrument(i, bytes(mem[INST_BASE + i * 8:
                                                   INST_BASE + (i + 1) * 8]))
                   for i in range(n_inst)]

    # FX_PERIODIC: clone the effect's instrument as periodic bass and
    # retarget the record, sharing one clone per source instrument
    clones = {}
    for n in sorted(FX_PERIODIC):
        src_i = fx_raw[n - 1][0]
        if src_i not in clones:
            c = dict(instruments[src_i])
            c['idx'] = len(instruments)
            c['noise'] = True
            c['flags'] = 0x80 | 3
            instruments.append(c)
            clones[src_i] = c['idx']
        fx_raw[n - 1] = bytes([clones[src_i]]) + fx_raw[n - 1][1:]
    n_inst = len(instruments)

    effects = [convert_effect(i + 1, fx_raw[i], instruments)
               for i in range(NUM_FX)]

    # the per-deck hum parameters ($6E60/$6E70/$6E80): 16 bytes each of
    # segment timer / reload / count, patched into effect 24's record at
    # offsets +5/+6/+7 by LoadDeck, exactly as $135F does
    bg_vars = [bytes(mem[a:a + 16]) for a in (0x6E60, 0x6E70, 0x6E80)]
    for a in (0x6E60, 0x6E70, 0x6E80):
        assert all(filled[a + i] for i in range(16)), \
            f"deckBgSndVar at {a:04X} unfilled"

    # the conversion table, QUARTERED to 32 entries (bank 4 pressure,
    # layer-11e section 6): index = (m-128)>>2, divisor = the quad's
    # midpoint. Max pitch error ~1.6% - a quarter semitone, on effects
    # that sweep; stage 4's ear is the arbiter.
    conv_tab = [round(CONV_NUM / (m + 1.5)) for m in range(128, 256, 4)]

    # ---- src/data/sounddata.asm ----
    lines = [
        "\\ ============================================================",
        "\\ sounddata.asm",
        "\\ GENERATED by tools/export_sound.py - do not edit by hand.",
        "\\ Source: paradroid_ce.lst ($C610 effects, $EAA0 instruments)",
        f"\\ {SHIP_FX} in-game effects x 11 bytes (SID-frequency space,",
        "\\ verbatim minus pulse and the never-used chain) plus the",
        f"\\ chatter's scratch slot, {n_inst} instruments x 6 bytes, and",
        "\\ the 32-entry frequency->period table. Formats and conversion:",
        "\\ the exporter's header, docs/layer-11e-sound.md.",
        "\\ Effect n's record is sndFxTab + (n-1)*11; offsets +5/+6/+7",
        "\\ are the per-deck patch targets for effect 24, as on the C64.",
        "\\ ============================================================",
        "",
        "SND_NUM_FX = " + str(CHAT_SLOT),
        "SND_FX_CHAT = " + str(CHAT_SLOT) + "   \\ the scratch slot's number",
        "SND_FX_LEN = 11",
        "SND_NOISE_SHIFT = " + str(NOISE_SHIFT),
        "",
        ".sndFxTab",
    ]
    for e in effects[:SHIP_FX]:
        lines.append("  EQUB " + ",".join(f"&{b:02X}" for b in e['bytes'])
                     + f"  \\ {e['n']:2d}: {FX_NAMES[e['n']]}")
    lines += [
        "",
        "\\ THE CHATTER'S SCRATCH SLOT - effect " + str(CHAT_SLOT) + ", the only",
        "\\ record in this table whose contents change at run time. BrChatter",
        "\\ (PARBRF) copies one of sndchat.asm's three blips here and posts",
        "\\ the effect number; the driver walks to it like any other. Ships",
        "\\ holding blip A, so it is valid even if nothing ever writes it.",
        ".sndFxChat",
    ]
    lines.append("  EQUB " + ",".join(f"&{b:02X}"
                                      for b in effects[CHAT_FX[0] - 1]['bytes'])
                 + f"  \\ {CHAT_SLOT}: scratch (blip A as shipped)")
    lines += [
        "",
        "\\ effect 24's per-deck patch values, indexed by deck 0-15:",
        "\\ segment timer / reload / count -> sndFxTab + 23*11 + 5/6/7.",
        "\\ (Not nibble-packable: decks 9 and 12 carry counts of $12/$11.)",
        ".sndBgVar1",
        "  EQUB " + ",".join(f"&{b:02X}" for b in bg_vars[0]),
        ".sndBgVar2",
        "  EQUB " + ",".join(f"&{b:02X}" for b in bg_vars[1]),
        ".sndBgVar3",
        "  EQUB " + ",".join(f"&{b:02X}" for b in bg_vars[2]),
    ]
    lines += ["", ".sndInstTab"]
    for i in instruments:
        b = [i['flags'], i['atk'], i['dec'], i['sus'], i['rel'], i['dur']]
        wave = WAVE_NAMES.get(i['ctrl'] >> 4 & 0xF, f"ctrl={i['ctrl']:02X}")
        lines.append("  EQUB " + ",".join(f"&{x:02X}" for x in b)
                     + f"  \\ {i['idx']}: {wave}, AD={i['raw'][5]:02X} "
                       f"SR={i['raw'][6]:02X} hold={i['dur']}")
    lines += [
        "",
        "\\ N = sndFreq[(F<<s)>>8 - 128] >> (8-s), s = shifts to normalise",
        "\\ F into [$8000,$FFFF]; noise voices shift SND_NOISE_SHIFT more.",
        "\\ Split lo/hi for indexed access.",
        ".sndFreqLo",
    ]
    for o in range(0, 32, 16):
        lines.append("  EQUB " + ",".join(f"&{t & 0xFF:02X}"
                                          for t in conv_tab[o:o + 16]))
    lines.append(".sndFreqHi")
    for o in range(0, 32, 16):
        lines.append("  EQUB " + ",".join(f"&{t >> 8:02X}"
                                          for t in conv_tab[o:o + 16]))
    lines.append("")
    OUT_ASM.parent.mkdir(parents=True, exist_ok=True)
    OUT_ASM.write_text("\n".join(lines), newline="\n")

    # ---- src/data/sndchat.asm ----
    # The blips are ordinary records; they simply live in the briefing's
    # overlay instead of bank 4. Their instruments must already be in the
    # bank's table, because the driver looks them up there - true by
    # construction (n_inst spans all NUM_FX records), asserted anyway.
    for n in CHAT_FX:
        e = effects[n - 1]
        assert e['inst'] < n_inst, \
            f"fx{n}: instrument {e['inst']} is outside the shipped table"
        assert not e['noise'], \
            f"fx{n}: chatter blips are tone voices; instrument " \
            f"{e['inst']} has become a noise voice, which would put the " \
            f"briefing on the noise channel"
    # Only the first CHAT_PRE bytes differ between the three blips -
    # instrument, initial frequency and slide. Everything from the
    # segment timer on (7D 00 01 00 00 00: one 125-tick segment, no
    # bounce, no reset) is common, and the scratch slot ships holding
    # it, so the run-time ferry carries the prefix alone. That is what
    # made the whole thing fit PARBRF's &0800 ceiling. Asserted, not
    # assumed: a release whose blips differ in the tail lands here.
    tails = {tuple(effects[n - 1]['bytes'][CHAT_PRE:]) for n in CHAT_FX}
    assert len(tails) == 1, \
        "the chatter blips no longer share a common record tail - " \
        "BrChatter ferries only the first %d bytes" % CHAT_PRE
    chat = [
        "\\ ============================================================",
        "\\ sndchat.asm - the briefing chatter's three blips",
        "\\ GENERATED by tools/export_sound.py - do not edit by hand.",
        "\\ ============================================================",
        "\\ Effects 29-31, in sndFxTab's record format but assembled into",
        "\\ PARMAN - bank 5, beside the briefing text - rather than bank 4,",
        "\\ which had 15 bytes free. BmChatter copies the blip it picks",
        "\\ into brChRec and BrChatter lands it in the sndFxChat scratch",
        f"\\ slot, then posts effect {CHAT_SLOT}. Every instrument named here is",
        "\\ already in sndInstTab.",
        "\\",
        f"\\ ONLY THE FIRST {CHAT_PRE} BYTES OF A RECORD ARE HERE - instrument,",
        "\\ initial frequency and slide. The three blips share every byte",
        "\\ from the segment timer on ("
        + " ".join(f"{b:02X}" for b in effects[CHAT_FX[0] - 1]['bytes'][CHAT_PRE:])
        + "), the exporter",
        "\\ asserts they do, and sndFxChat ships holding them.",
        "\\ ============================================================",
        "",
        "BR_CHAT_PRE = " + str(CHAT_PRE),
        "",
        ".brChatTab",
    ]
    for n in CHAT_FX:
        e = effects[n - 1]
        s = e['sim']
        chat.append("  EQUB " + ",".join(f"&{b:02X}"
                                         for b in e['bytes'][:CHAT_PRE])
                    + f"  \\ {e['n']:2d}: {FX_NAMES[e['n']]}")
        if s:
            chat.append(f"     \\ F {s['flo']}..{s['fhi']}, {s['wraps']} wraps,"
                        f" sub-floor {s['sub_pct']}%")
    chat.append("")
    OUT_CHAT.write_text("\n".join(chat), newline="\n")

    # ---- tools/output/sound_dump.txt ----
    d = ["Paradroid sound tables - review dump (tools/export_sound.py)",
         f"{NUM_FX} effects at $C610, {n_inst} instruments at $EAA0",
         f"SN tone floor {TONE_FLOOR_HZ:.1f} Hz; 'sub%' = share of the",
         "effect's ticks a TONE voice spends below it (period clamped 1023).",
         ""]
    d.append("INSTRUMENTS")
    for i in instruments:
        wave = WAVE_NAMES.get(i['ctrl'] >> 4 & 0xF, f"ctrl ${i['ctrl']:02X}")
        d.append(f"  {i['idx']:2d}: {wave:9s} "
                 f"voice={'NOISE' if i['noise'] else 'tone '}"
                 f" ADSR raw {i['raw'][5]:02X}/{i['raw'][6]:02X}"
                 f" -> atk {i['atk']}/t, dec {i['dec']}/t,"
                 f" sus {i['sus']}, rel {i['rel']}/t, hold {i['dur']}t")
    d.append("")
    d.append("EFFECTS")
    review = []
    for e in effects:
        segs = (f"{e['count']} segs x {e['reload'] or 256}t"
                f" (first {e['timer'] or 256}t)")
        modes = 'reset' if e['mode'] == 1 else 'bounce'
        d.append(f"  {e['n']:2d}: {FX_NAMES[e['n']]}")
        d.append(f"      inst {e['inst']} ({'NOISE' if e['noise'] else 'tone'}),"
                 f" F0={e['f0']} ({sid_hz(e['f0']):7.1f} Hz),"
                 f" slide {e['slide']:+d}/t, {segs}, {modes}"
                 + (f" to F={e['fr']} ({sid_hz(e['fr']):.1f} Hz)"
                    if e['mode'] == 1 else "")
                 + (f", chain -> {e['chain']}" if e['chain'] else ""))
        s = e['sim']
        if s:
            d.append(f"      sim: {s['ticks']}t, F {s['flo']}..{s['fhi']}"
                     f" ({sid_hz(s['flo']):.1f}..{sid_hz(s['fhi']):.1f} Hz),"
                     f" {s['wraps']} wraps, SN N {s['nlo']}..{s['nhi']},"
                     f" sub-floor {s['sub_pct']}%")
            if s['sub_pct'] >= 40 and not e['noise']:
                review.append((e['n'], s['sub_pct']))
        d.append(f"      raw {' '.join(f'{b:02X}' for b in e['raw'])}")
    d.append("")
    d.append("REVIEW - tone effects spending >=40% of their time below the")
    d.append("SN floor (candidates for periodic-noise bass or an octave up,")
    d.append("stage 4, with KC - docs/layer-11e-sound.md section 8):")
    for n, pct in review:
        d.append(f"  fx{n:02d} ({pct}% sub-floor): {FX_NAMES[n]}")
    if not review:
        d.append("  none")
    d.append("")
    OUT_DUMP.parent.mkdir(parents=True, exist_ok=True)
    OUT_DUMP.write_text("\n".join(d), newline="\n")

    total = CHAT_SLOT * 11 + n_inst * 6 + 256
    print(f"sounddata.asm: {SHIP_FX} of {NUM_FX} effects + the chatter "
          f"scratch slot, {n_inst} instruments, 256 B conversion table "
          f"= {total} B of data")
    print(f"sndchat.asm:   {len(CHAT_FX)} chatter prefixes x {CHAT_PRE} = "
          f"{len(CHAT_FX) * CHAT_PRE} B, in PARMAN (bank 5)")
    print(f"review list (sub-floor tone effects): "
          f"{', '.join('fx%02d' % n for n, _ in review) or 'none'}")


if __name__ == '__main__':
    main()
