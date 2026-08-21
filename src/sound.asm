\ ============================================================
\ sound.asm — the SN76489 driver.  BANK 4, called from the IRQ.
\ ============================================================
\ Layer 11e stage 2 — docs/layer-11e-sound.md §4, a transliteration
\ of the C64's Sound ($0500) game-FX path onto the SN76489.
\
\ CALLED FROM THE IRQ, ONCE PER FIELD (50 Hz), by the paging shim
\ in IrqHandler: the shim saves ROMSHAD, pages SWRAM_DATA, calls
\ SndTick, and restores what it found — the one sanctioned breach
\ of "the IRQ reads neither bank". Everything here — code, tables,
\ state, scratch — is therefore bank 4 or hardware, EXCEPT the four
\ request bytes (sndFx1/sndFx2/sndState/sndVolume), which are main
\ RAM so that console (bank 6), transfer (bank 7) and low-overlay
\ code can trigger sounds with a plain STA.
\
\ NO ZERO PAGE ANYWHERE IN THIS FILE. ZP is fully allocated to the
\ game and this code interrupts it at arbitrary points; scratch
\ lives in bank-4 absolutes (snCv*, snWr*), which the main loop
\ never sees.
\
\ The sequencer is the C64's, on the C64's own bytes (sounddata.asm
\ records are verbatim minus the pulse fields): per tick add the
\ 16-bit slide MOD 65536 — the wrap is musical, see the exporter —
\ and at each segment boundary either negate the slide or reset the
\ frequency, for snCount segments, then optionally chain. A chain
\ posts to sndFx1 ALWAYS, voice 1, as the C64 does at $0680.
\ Frequencies convert to SN periods only at chip-write time,
\ through sndFreqLo/Hi (normalise-and-lookup, ±0.5%).
\
\ What the SID gave and this replaces:
\  - ADSR       → snLevel/snPhase, per-instrument linear steps at
\                 50 Hz, gate dropped after snGate ticks
\  - waveforms  → tone channels 0/1 for voices 0/1; a NOISE
\                 instrument plays on the noise channel clocked by
\                 silenced tone 2 (verified stage 0), latest claim
\                 wins the one noise channel [DECISION 3]
\  - $D418      → sndVolume 0-15 as extra attenuation
\
\ Chip access batches the stage-0-verified sequence: DDRA and ORA
\ saved ONCE per tick around all writes (SndWrOpen/SndWrClose), so
\ an interrupted OSBYTE &81 keyboard scan resumes intact. Writes
\ are diffed against per-channel caches; a silent, idle tick does
\ no bus traffic at all.
\ ============================================================

\ ---- per-voice state, indexed X = voice 0/1 ----------------
\ DECLARATION ORDER IS LOAD-BEARING twice over: snFreqLo..snResetHi
\ mirror record bytes 1-10 and snInstFl..snGate mirror instrument
\ bytes 0-5, so SndCopy can walk them as base + field*2 + voice with
\ one stride-2 self-modified store. Insert nothing inside either run.
.snFreqLo  EQUB 0,0             \ C64 snd_C0/C1 — 16-bit SID frequency
.snFreqHi  EQUB 0,0
.snSlideLo EQUB 0,0             \ C2/C3 — added every tick, signed
.snSlideHi EQUB 0,0
.snTimer   EQUB 0,0             \ C4 — segment ticks left (0 wraps as 256)
.snReload  EQUB 0,0             \ C5 — later segments' length
.snCount   EQUB 0,0             \ C6 — segments left; 0 = voice idle
.snMode    EQUB 0,0             \ CB — 1 = reset frequency, else negate slide
.snResetLo EQUB 0,0             \ CC/CD
.snResetHi EQUB 0,0
.snActive  EQUB 0,0             \ C64 sndActive1/2: playing effect number;
                                \ bit 7 set = uninterruptible (the disruptor)
\ ---- envelope, from the instrument --------------------------
.snInstFl  EQUB 0,0             \ bit 7 = noise voice
.snAtk     EQUB 0,0             \ level step per tick, 0-255 space
.snDec     EQUB 0,0
.snSus     EQUB 0,0             \ level to hold after decay
.snRel     EQUB 0,0
.snGate    EQUB 0,0             \ ticks until release; 0 = no auto-release
.snLevel   EQUB 0,0             \ 0-255; attenuation nibble = 15 - (level>>4)
.snPhase   EQUB 0,0             \ 0 attack, 1 decay/sustain, 2 release

\ ---- chip-state caches: what the SN76489 currently holds ----
\ &FF = unknown, forces the first write. Tone periods cached as
\ lo/hi of N so the diff is two byte compares.
.snChPerL  EQUB &FF,&FF,&FF     \ tone channels 0-2
.snChPerH  EQUB &FF,&FF,&FF
.snChAtt   EQUB &FF,&FF,&FF,&FF \ channels 0-3
.snNzCtl   EQUB &FF             \ last noise control byte
.snNzOwn   EQUB &FF             \ which voice owns the noise channel; &FF none
.snQuiet   EQUB 0               \ state-0 silence already done

\ ---- scratch (IRQ-only, so safe as absolutes) ---------------
.snCvL     EQUB 0               \ SndConv in/out: frequency in, period out
.snCvH     EQUB 0
.snCvNz    EQUB 0               \ nonzero = noise scaling (>>4 more)
.snWrD     EQUB 0               \ SndWrOpen's DDRA/ORA saves
.snWrO     EQUB 0
.snTmp     EQUB 0
.snTm2     EQUB 0

\ ============================================================
\ SndTick — one 50 Hz update.  The IRQ shim has paged us in.
\ ============================================================
.SndTick
  LDA sndState
  BNE stk_on
  LDA snQuiet                   \ state 0: silence the chip once, then
  BNE stk_x                     \ free-run silent — the C64 ResetSIDs
  JMP SndSilence                \ every tick, ours needs only the once
.stk_on
  CMP #2
  BEQ stk_go                    \ running: the common case
  JSR SndSilence                \ any other nonzero value is an init
  DEC snQuiet                   \ request — the C64's $1x shape ($0526),
  LDA #2                        \ collapsed to its one surviving value:
  STA sndState                  \ $12 is all there is until the chatter
                                \ lands [DECISION 4]. The DEC undoes the
                                \ snQuiet=1 SndSilence just set: state 2
                                \ is only ever entered HERE, so the next
                                \ state-0 tick must silence anew
.stk_x
  RTS
.stk_go

\ ---- request pickup, both voices ($05A0-$05CB) --------------
  LDX #0
  JSR stk_req
  LDX #1
  JSR stk_req
  JMP SndRun

.stk_req
  LDA sndFx1,X                  \ sndFx1/sndFx2 are adjacent, as $91/$92 were
  BNE stkr_1
  RTS
.stkr_1
  LDY snActive,X
  BMI stkr_drop                 \ uninterruptible effect playing: discard
  STA snActive,X
  JSR SndStart
.stkr_drop
  LDA #0
  STA sndFx1,X
  RTS

\ ============================================================
\ SndStart — load effect A (bit 7 = priority tag, ignored here)
\ into voice X.  StartSfx ($069B) + StartInstrument ($06F7).
\ ============================================================
.SndStart
  AND #&7F
  SEC
  SBC #1                        \ record index 0-30
  TAY
  LDA #LO(sndFxTab)
  STA snsLd+1
  LDA #HI(sndFxTab)
  STA snsLd+2
  TYA
  BEQ sns_ptrok                 \ walk the pointer up index * SND_FX_LEN —
.sns_ptrstep                    \ ≤ 500 cycles, and only at effect start
  CLC
  LDA snsLd+1
  ADC #SND_FX_LEN
  STA snsLd+1
  BCC sns_ptrnc
  INC snsLd+2
.sns_ptrnc
  DEY
  BNE sns_ptrstep
.sns_ptrok

  LDA #LO(snFreqLo)             \ record bytes 1-10 → the ten state
  LDY #HI(snFreqLo)             \ fields — pairs, stride 2, this voice
  JSR snsSetDst
  LDY #1
  LDA #11
  JSR SndCopy

  LDY #0                        \ record byte 0: the instrument, *6
  JSR snsLd
  ASL A
  STA snTm2
  ASL A
  CLC
  ADC snTm2
  ADC #LO(sndInstTab)
  STA snsLd+1
  LDA #0
  ADC #HI(sndInstTab)
  STA snsLd+2
  LDA #LO(snInstFl)
  LDY #HI(snInstFl)
  JSR snsSetDst
  LDY #0
  LDA #6
  JSR SndCopy

  LDA #0                        \ restart the envelope from silence — the
  STA snLevel,X                 \ C64's ResetVoice test-bit + fresh gate
  STA snPhase,X

  LDA snInstFl,X
  BMI sns_noise
  CPX snNzOwn                   \ a tone effect on the voice that owned the
  BNE sns_x                     \ noise channel releases it
  LDA #&FF
  STA snNzOwn
.sns_x
  RTS
.sns_noise
  STX snNzOwn                   \ latest claim wins [DECISION 3]
  RTS

ASSERT HI(snFreqLo) == HI(snPhase+1)   \ one page: the copy walk below
                                       \ steps without carry handling
\ ---- the copy machinery: everything is self-modified because ---
\ no zero page exists for this file (see the header). snsLd's
\ operand is the source block; snsSt's is destination base + X,
\ stepped by 2 so each stride-2 field pair lands on this voice.
.snsSetDst
  CLC
  STX snTm2
  ADC snTm2
  STA snsSt+1
  STY snsSt+2                   \ no carry: the ASSERT above holds the
  RTS                           \ whole state block on one page

.SndCopy                        \ Y = first source byte, A = end + 1
  STA snTm2
.snc_loop
  JSR snsMove
  INC snsSt+1                   \ stride 2, same page per the ASSERT
  INC snsSt+1
  INY
  CPY snTm2
  BNE snc_loop
  RTS

\ one byte, source to state, both operands patched
.snsMove
.snsLd
  LDA &FFFF,Y                   \ operand patched: record or instrument
.snsSt
  STA &FFFF                     \ operand patched: the state field
  RTS

\ ============================================================
\ The per-tick voice update ($05D5-$0699) and the chip flush.
\ ============================================================
.SndRun
  LDX #0
  JSR SndVoice
  LDX #1
  JSR SndVoice
  JMP SndFlush

.SndVoice
  LDA snCount,X
  BNE snv_live
  RTS                           \ idle: NOTHING runs — the C64 cuts the
                                \ voice at effect end (ResetVoice, $0678:
                                \ test bit + waveform 0), so there is no
                                \ post-effect tail to envelope. The only
                                \ release that sounds is a mid-effect
                                \ gate expiry, on the live path below
.snv_live
  CLC                           \ frequency += slide, MOD 65536 — the wrap
  LDA snFreqLo,X                \ is load-bearing, see the exporter header
  ADC snSlideLo,X
  STA snFreqLo,X
  LDA snFreqHi,X
  ADC snSlideHi,X
  STA snFreqHi,X

  LDA snGate,X                  \ gate-hold: 0 = never auto-release, as the
  BEQ snv_seg                   \ C64 has it at $0624
  DEC snGate,X
  BNE snv_seg
  LDA #2
  STA snPhase,X                 \ gate off → release
.snv_seg
  DEC snTimer,X                 \ 0 wraps to 255: reload 0 = 256, as C64
  BNE SndEnv
  LDA snReload,X
  STA snTimer,X
  LDA snMode,X
  CMP #1
  BEQ snv_reset
  SEC                           \ negate the slide — the bounce
  LDA #0
  SBC snSlideLo,X
  STA snSlideLo,X
  LDA #0
  SBC snSlideHi,X
  STA snSlideHi,X
  JMP snv_count
.snv_reset
  LDA snResetLo,X
  STA snFreqLo,X
  LDA snResetHi,X
  STA snFreqHi,X
.snv_count
  DEC snCount,X
  BNE SndEnv
  LDA #0                        \ effect over: CUT, as ResetVoice does —
  STA snActive,X                \ level to zero, voice freed, and no
  STA snLevel,X                 \ envelope step on the way out (a stale
  RTS                           \ phase must not resurrect the level).
                                \ The C64 would test the chain byte here
                                \ ($0680); no record uses it, so neither
                                \ field nor code path exists —
                                \ export_sound.py asserts that stays true
\ ---- envelope ----------------------------------------------
.SndEnv
  LDA snPhase,X
  BEQ sne_atk
  CMP #2
  BEQ sne_rel
  LDA snLevel,X                 \ decay toward sustain, hold there
.sne_decayA                     \ (A = the level to decay from)
  SEC
  SBC snDec,X
  BCC sne_toSus
  CMP snSus,X
  BCS sne_store
.sne_toSus
  LDA snSus,X
.sne_store
  STA snLevel,X
  RTS
.sne_atk
  LDA snLevel,X
  CLC
  ADC snAtk,X
  BCC sne_store
  LDA #1                        \ peak: into decay — ON THIS SAME TICK.
  STA snPhase,X                 \ The SID's peak lasts milliseconds; a
  LDA #255                      \ full 20 ms tick of it played the hum's
  BNE sne_decayA                \ lowest note at attenuation 0 — KC's
                                \ "blip". An instant-decay instrument now
                                \ opens straight at its sustain level
.sne_rel
  LDA snLevel,X
  SEC
  SBC snRel,X
  BCS sne_store
  LDA #0
  BEQ sne_store                 \ always

\ ============================================================
\ SndFlush — each voice written straight to its channel, diffed
\ against the chip caches, one bus transaction.
\ Voice X sounds on tone X; a noise voice sounds on channel 3
\ with its pitch on silenced tone 2 — whose attenuation nothing
\ here ever raises: SndSilence wrote it 15 and no path writes
\ another value, so it needs no per-tick defaulting.
\ ============================================================
.SndFlush
  JSR SndWrOpen
  LDX #0
  JSR snf_voice
  LDX #1
  JSR snf_voice
  LDA snNzOwn                   \ an UNOWNED noise channel is silenced:
  BPL snf_done                  \ a tone effect taking over the owner
  LDA #15                       \ voice releases ownership mid-release,
  LDY #3                        \ and the fading hiss was left frozen at
  JSR snf_attA                  \ its last attenuation until the next
.snf_done                       \ noise claim — KC heard the explosion
  JMP SndWrClose                \ tail hang. Cache-diffed: free in the
                                \ steady state

.snf_voice
  LDA snLevel,X
  BNE snfv_on
.snfv_off
  LDA #15                       \ silent: the channel to attenuation 15,
  STA snTmp                     \ once — the cache eats the repeats
  LDA snInstFl,X
  BMI snfv_offnz
  TXA
  TAY
  JMP snf_att
.snfv_offnz
  CPX snNzOwn
  BNE snfv_x
  LDY #3
  BNE snf_att                   \ always
.snfv_on
  LSR A
  LSR A
  LSR A
  LSR A
  STA snTmp                     \ level nibble 0-15
  LDA #30                       \ (15 - level) + (15 - volume); the SEC
  SEC                           \ holds through both subtracts — the
  SBC snTmp                     \ first result is >= 15 so the second
  SBC sndVolume                 \ can never borrow
  CMP #16
  BCC snfv_a2
  LDA #15
.snfv_a2
  STA snTmp                     \ the attenuation this voice wants
  LDA snFreqLo,X
  STA snCvL
  LDA snFreqHi,X
  STA snCvH
  LDA snInstFl,X                \ 0 = tone; bit 7 = noise, and then the
  STA snCvNz                    \ low bits are the SN noise-control bits
  BMI snfv_nz                   \ (7 white, 3 periodic bass)
  JSR SndConv
  BCS snfv_off                  \ muted sub-floor: VOLUME off, period
  TXA                           \ untouched — the silent path is exactly
  TAY                           \ the mute the DC offset needs
  JSR snf_per
  JMP snf_att
.snfv_nz
  CPX snNzOwn                   \ only the owner drives the noise channel
  BNE snfv_x
  JSR SndConv
  LDY #2                        \ pitch on (silent) tone 2
  JSR snf_per
  LDA #&E7                      \ white noise, clocked by tone 2 — stage 0.
  CMP snNzCtl                   \ (Periodic bass would be &E3 via the flag
  BEQ snfv_nc                   \ low bits; no instrument uses it since KC
  STA snNzCtl                   \ reverted the hum — dd108a2 has the code.)
  JSR SndWrByte                 \ Cached hard: a noise-register write
                                \ resets the chip LFSR mid-hiss
.snfv_nc
  LDY #3
\ fall through: the noise attenuation

\ ---- attenuation snTmp -> channel Y, diffed -----------------
.snf_att
  LDA snTmp
.snf_attA
  CMP snChAtt,Y
  BEQ snfv_x
  STA snChAtt,Y
  ORA snChanB,Y
  ORA #&90                      \ attenuation latch: 1 cc1 aaaa
  JSR SndWrByte
.snfv_x
  RTS

\ ---- period snCvL/H -> tone channel Y, diffed ---------------
\ SndWrByte no longer touches Y (the NOP hold), so Y survives
\ across both writes.
.snf_per
  LDA snCvH
  CMP snChPerH,Y
  BNE snfp_wr
  LDA snCvL
  CMP snChPerL,Y
  BEQ snfp_x
.snfp_wr
  LDA snCvL
  STA snChPerL,Y
  AND #&0F                      \ latch byte: 1 cc0 dddd, low 4 bits of N
  ORA snChanB,Y
  ORA #&80
  JSR SndWrByte
  LDA snCvH
  STA snChPerH,Y
  ASL A
  ASL A
  ASL A
  ASL A
  STA snTm2
  LDA snCvL
  LSR A
  LSR A
  LSR A
  LSR A
  ORA snTm2
  AND #&3F                      \ data byte: N bits 4-9
  JSR SndWrByte
.snfp_x
  RTS

.snChanB
  EQUB &00,&20,&40,&60          \ channel number in latch bits 5-6

\ ============================================================
\ SndSilence — every channel to attenuation 15, caches reset.
\ Also the state-0 idle and the $1x initialiser ($074C's job).
\ ============================================================
.SndSilence
  JSR SndWrOpen
  LDX #3
.sns_hush
  LDA snChanB,X                 \ channel bits | attenuation-15 latch
  ORA #&9F
  JSR SndWrByte
  DEX
  BPL sns_hush
  JSR SndWrClose
  LDX #11                       \ every cache byte to &FF = "unknown":
.sns_cache                      \ snChPerL..snNzOwn are contiguous, and
  LDA #&FF                      \ &FF also reads as attenuation-unknown,
  STA snChPerL,X                \ which forces the next real write through
  DEX
  BPL sns_cache
  LDA #0
  STA snActive+0 : STA snActive+1
  STA snCount+0  : STA snCount+1
  STA snLevel+0  : STA snLevel+1
  LDA #1                        \ (requests are NOT cleared: nothing reads
  STA snQuiet                   \ them in state 0, and every entry into
  RTS                           \ state 2 comes through this silence)

\ ============================================================
\ SndConv — SID frequency (snCvL/H) to SN period (snCvL/H).
\ N = sndFreq[(F<<s)>>8 - 128] >> (8-s), clamped to 1..1023;
\ snCvNz nonzero shifts 4 more (the noise scaling, exporter hdr).
\ ============================================================
\ COUNTERS LIVE IN snTm2, NOT X — X is the caller's voice number and
\ must survive this routine: the first flush build counted its shifts
\ in X and sent every in-range voice-1 tone to CHANNEL 0, because the
\ flush picks the channel from X after converting. (Y is clobbered
\ freely — both callers set their channel after the call.)
.SndConv
  LDA snCvNz                    \ 0 / &40 = tone; bit 7 = noise, which
  BPL snc_tone                  \ divides by 16F — the tone maths on F*16
  LDA #4
  STA snTm2
.snc_nzsc
  ASL snCvL
  ROL snCvH
  BCC snc_nzok
  LDA #&FF                      \ saturate: F >= &1000 means N <= 32, and
  STA snCvL                     \ a saturated &FFFF converts to N=32 too
  STA snCvH
  BNE snc_tone                  \ always
.snc_nzok
  DEC snTm2
  BNE snc_nzsc
.snc_tone
  LDA snCvH
  CMP #8                        \ F < 2048 can only clamp: skip the maths.
  BCS snc_go                    \ (2048-2080 also land on 1023 — exact)
.snc_max
  BIT snCvNz                    \ flags bit 6 (V after BIT) = mute the
  BVS snc_mute                  \ sub-floor instead — the hum's instrument
  LDA #&FF                      \ the audible clamp: N=1023, ~122 Hz
  STA snCvL
  LDA #3
  STA snCvH
  CLC
  RTS
.snc_mute
  SEC                           \ muted: NO period, and the caller must
  RTS                           \ hold the VOLUME at 15 too. The first cut
                                \ wrote N=1 (ultrasonic, silent per the
                                \ wiki's sn76489 page) with the envelope
                                \ live — and each attenuation step shifted
                                \ the chip's volume-derived DC offset,
                                \ which IS the chip's sample-playback
                                \ mechanism: KC heard the click
.snc_go
  LDA #8                        \ snTm2 = 8 - s, counted down as we
  STA snTm2                     \ normalise
.snc_norm
  LDA snCvH
  BMI snc_look
  ASL snCvL
  ROL snCvH
  DEC snTm2
  BNE snc_norm                  \ hi >= 8 → at most 4 shifts, so >= 4 left
.snc_look
  LDA snCvH
  SEC
  SBC #128
  LSR A                         \ 32-entry table: four m values share an
  LSR A                         \ entry cut at their midpoint (exporter)
  TAY
  LDA sndFreqHi,Y
  STA snCvH
  LDA sndFreqLo,Y
  STA snCvL
.snc_sh
  LSR snCvH
  ROR snCvL
  DEC snTm2
  BNE snc_sh
  LDA snCvH
  CMP #4                        \ > 1023?
  BCS snc_max
  CLC                           \ carry protocol: clear = play the period,
  RTS                           \ set = muted (snc_mute alone sets it)

\ ============================================================
\ The chip bus — the stage-0-verified sequence, batched: DDRA
\ and ORA saved once per transaction so an interrupted keyboard
\ scan (OSBYTE &81 manipulates both) resumes intact.
\ ============================================================
.SndWrOpen
  LDA SND_DDRA
  STA snWrD
  LDA SND_ORA
  STA snWrO
  LDA #&FF
  STA SND_DDRA
  RTS

.SndWrByte
  STA SND_ORA
  LDA #0
  STA SND_PORTB                 \ sound /WE low — the chip samples the bus
  NOP : NOP : NOP : NOP         \ 16 cycles + the LDA/STA around them is
  NOP : NOP : NOP : NOP         \ ~12 µs of hold; the chip needs ~8. NOPs
  LDA #8                        \ rather than a loop so Y SURVIVES — the
  STA SND_PORTB                 \ flush holds its channel number in it
  RTS

.SndWrClose
  LDA snWrO
  STA SND_ORA
  LDA snWrD
  STA SND_DDRA
  RTS
