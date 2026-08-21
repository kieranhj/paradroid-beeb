#!/usr/bin/env python3
"""
export_sound.py - Convert the C64 sound tables to SN76489-ready BeebASM data.

Layer 11e stage 1 (docs/layer-11e-sound.md [DECISION 2]). Reads the effect
records at $C610 and the instrument table at $EAA0 out of paradroid_ce.lst
(the same source every other exporter uses; decisions.md carries the evidence
that the listing matches the original/CE releases byte for byte) and emits:

  src/data/sounddata.asm     - 31 effect records (SID-frequency space,
                               verbatim minus the pulse fields), the
                               instruments as envelope steps, and the
                               frequency->period conversion table
  tools/output/sound_dump.txt- the review dump: each effect's simulated
                               frequency trajectory, wraps and all, in both
                               SID and SN terms, plus the sub-floor list

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

Emitted record, 12 bytes (offsets +5/+6/+7 kept = the C64's patch targets
for effect 24's per-deck deckBgSndVar values, which are used unconverted):
  [0]     instrument number
  [1-2]   initial frequency, SID 16-bit, verbatim
  [3-4]   slide, verbatim
  [5]     segment timer     [6] reload     [7] count
  [8]     mode              [9-10] reset frequency, verbatim
  [11]    chain

Emitted instrument, 6 bytes:
  [0]     flags: bit 7 = noise voice (SN channel 3 + silenced tone 2),
          low bits = SID waveform nibble (ctrl>>4) for reference
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
OUT_DUMP = PROJECT / 'tools' / 'output' / 'sound_dump.txt'

FX_BASE = 0xC610
NUM_FX = 31
INST_BASE = 0xEAA0

SID_CLOCK = 985248            # PAL
CONV_NUM = 2128693            # = 125000 * 2^24 / 985248, see header
NOISE_SHIFT = 4               # noise voices: N >> 4 more (= /16) - TUNABLE
TONE_FLOOR_HZ = 125000 / 1023  # ~122.2 Hz - lowest SN tone

TICK_MS = 20                  # 50 Hz driver tick

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
    29: "title chatter blip A (deferred with the chatter mode)",
    30: "title chatter blip B (deferred)",
    31: "title chatter blip C (deferred)",
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
    noise = bool(ctrl & 0x80)
    return {
        'idx': idx, 'raw': raw, 'ctrl': ctrl, 'noise': noise,
        'flags': (0x80 if noise else 0) | (ctrl >> 4),
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
    e = {
        'n': n, 'raw': raw, 'inst': raw[0],
        'f0': raw[1] | (raw[2] << 8), 'slide': s16(raw[3], raw[4]),
        'timer': raw[5], 'reload': raw[6], 'count': raw[7],
        'mode': raw[12], 'fr': raw[13] | (raw[14] << 8), 'chain': raw[15],
    }
    e['noise'] = instruments[e['inst']]['noise']
    e['sim'] = simulate(e, e['noise'])
    e['bytes'] = [raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6],
                  raw[7], raw[12], raw[13], raw[14], raw[15]]
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

    effects = [convert_effect(i + 1, fx_raw[i], instruments)
               for i in range(NUM_FX)]

    # the conversion table: T[m-128] = round(CONV_NUM / m), m = 128..255
    conv_tab = [round(CONV_NUM / m) for m in range(128, 256)]

    # ---- src/data/sounddata.asm ----
    lines = [
        "\\ ============================================================",
        "\\ sounddata.asm",
        "\\ GENERATED by tools/export_sound.py - do not edit by hand.",
        "\\ Source: paradroid_ce.lst ($C610 effects, $EAA0 instruments)",
        f"\\ {NUM_FX} effects x 12 bytes (SID-frequency space, verbatim",
        f"\\ minus the pulse fields), {n_inst} instruments x 6 bytes, and",
        "\\ the 128-entry frequency->period table. Formats and the",
        "\\ conversion: the exporter's header, docs/layer-11e-sound.md.",
        "\\ Effect n's record is sndFxTab + (n-1)*12; offsets +5/+6/+7",
        "\\ are the per-deck patch targets for effect 24, as on the C64.",
        "\\ ============================================================",
        "",
        "SND_NUM_FX = " + str(NUM_FX),
        "SND_FX_LEN = 12",
        "SND_NOISE_SHIFT = " + str(NOISE_SHIFT),
        "",
        ".sndFxTab",
    ]
    for e in effects:
        lines.append("  EQUB " + ",".join(f"&{b:02X}" for b in e['bytes'])
                     + f"  \\ {e['n']:2d}: {FX_NAMES[e['n']]}")
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
    for o in range(0, 128, 16):
        lines.append("  EQUB " + ",".join(f"&{t & 0xFF:02X}"
                                          for t in conv_tab[o:o + 16]))
    lines.append(".sndFreqHi")
    for o in range(0, 128, 16):
        lines.append("  EQUB " + ",".join(f"&{t >> 8:02X}"
                                          for t in conv_tab[o:o + 16]))
    lines.append("")
    OUT_ASM.parent.mkdir(parents=True, exist_ok=True)
    OUT_ASM.write_text("\n".join(lines), newline="\n")

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

    total = NUM_FX * 12 + n_inst * 6 + 256
    print(f"sounddata.asm: {NUM_FX} effects, {n_inst} instruments, "
          f"256 B conversion table = {total} B of data")
    print(f"review list (sub-floor tone effects): "
          f"{', '.join('fx%02d' % n for n, _ in review) or 'none'}")


if __name__ == '__main__':
    main()
