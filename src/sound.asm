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

\ ---- desired state, rebuilt each tick then diffed -----------
.snWantAtt EQUB 15,15,15,15

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
.stk_x
  RTS
.stk_on
  AND #&10                      \ $1x = (re)initialise, drop to $0x — the
  BEQ stk_run                   \ C64's _initGameFX shape ($0526)
  JSR SndSilence
  LDA sndState
  AND #&0F
  STA sndState
  RTS
.stk_run
  LDA sndState
  CMP #2                        \ only game-FX mode exists; state 1 is the
  BEQ stk_go                    \ title chatter, deferred [DECISION 4]
  RTS
.stk_go
  LDA #0                        \ chip is (about to be) live again, so the
  STA snQuiet                   \ NEXT state-0 tick must silence it anew

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
  STA snTmp
  ASL A
  STA snTm2                     \ *2
  ASL A
  ASL A                        \ *8 — max 240, no carry
  CLC
  ADC snTm2                     \ *10 — may carry
  STA snsLd+1
  LDA #0
  ADC #0
  STA snsLd+2
  CLC
  LDA snsLd+1
  ADC snTmp                     \ *11 — SND_FX_LEN
  STA snsLd+1
  LDA snsLd+2
  ADC #0
  STA snsLd+2
  CLC
  LDA snsLd+1
  ADC #LO(sndFxTab)
  STA snsLd+1
  LDA snsLd+2
  ADC #HI(sndFxTab)
  STA snsLd+2                   \ snsLd now reads this record

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

\ ---- the copy machinery: everything is self-modified because ---
\ no zero page exists for this file (see the header). snsLd's
\ operand is the source block; snsSt's is destination base + X,
\ stepped by 2 so each stride-2 field pair lands on this voice.
.snsSetDst
  CLC
  STX snTm2
  ADC snTm2
  STA snsSt+1
  TYA
  ADC #0
  STA snsSt+2
  RTS

.SndCopy                        \ Y = first source byte, A = end + 1
  STA snTm2
.snc_loop
  JSR snsLd
  JSR snsSt
  CLC
  LDA snsSt+1
  ADC #2
  STA snsSt+1
  BCC snc_nc
  INC snsSt+2
.snc_nc
  INY
  CPY snTm2
  BNE snc_loop
  RTS

.snsLd
  LDA &FFFF,Y                   \ operand patched: record or instrument
  RTS
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
  JMP SndEnv                    \ idle: the release tail still runs
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
  LDA #2                        \ effect over: release phase, free the
  STA snPhase,X                 \ voice ($0678-$0686). The C64 would test
  LDA #0                        \ the chain byte here ($0680); no record
  STA snActive,X                \ in the data uses it, so neither field
                                \ nor code path exists — export_sound.py
                                \ asserts that stays true
\ ---- envelope ----------------------------------------------
.SndEnv
  LDA snPhase,X
  BEQ sne_atk
  CMP #2
  BEQ sne_rel
  LDA snLevel,X                 \ decay toward sustain, hold there
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
  LDA #1                        \ peak: into decay
  STA snPhase,X
  LDA #255
  BNE sne_store                 \ always
.sne_rel
  LDA snLevel,X
  SEC
  SBC snRel,X
  BCS sne_store
  LDA #0
  BEQ sne_store                 \ always

\ ============================================================
\ SndFlush — desired chip state from both voices, diffed against
\ the caches, written in one bus transaction.
\ ============================================================
.SndFlush
  LDA #15                       \ default: everything silent
  STA snWantAtt+0
  STA snWantAtt+1
  STA snWantAtt+2               \ tone 2 is the noise clock and NEVER sounds
  STA snWantAtt+3

  LDX #0
  JSR snf_voice
  LDX #1
  JSR snf_voice
  JMP snf_write

\ one voice's contribution: an attenuation, and a period if audible
.snf_voice
  LDA snLevel,X
  BNE snfv_on
  RTS                           \ silent: leave the defaults
.snfv_on
  LSR A
  LSR A
  LSR A
  LSR A
  STA snTmp                     \ level nibble 0-15
  LDA #15
  SEC
  SBC snTmp
  STA snTmp                     \ 15 - level
  LDA #15
  SEC
  SBC sndVolume                 \ + (15 - master volume)
  CLC
  ADC snTmp
  CMP #16
  BCC snfv_att
  LDA #15
.snfv_att
  STA snTmp                     \ the attenuation this voice wants
  CMP #15
  BEQ snfv_x                    \ fully attenuated: nothing to place

  LDA snFreqLo,X
  STA snCvL
  LDA snFreqHi,X
  STA snCvH

  LDA snInstFl,X
  BMI snfv_noise
  LDA #0                        \ tone voice: channel = voice number
  STA snCvNz
  JSR SndConv
  LDA snCvL
  STA snWantPL,X
  LDA snCvH
  STA snWantPH,X
  LDA snTmp
  STA snWantAtt,X
.snfv_x
  RTS
.snfv_noise
  CPX snNzOwn                   \ only the owner drives the noise channel
  BNE snfv_x
  LDA #1
  STA snCvNz
  JSR SndConv
  LDA snCvL
  STA snWantPL+2                \ pitch on (silent) tone 2
  LDA snCvH
  STA snWantPH+2
  LDA snTmp
  STA snWantAtt+3
  RTS

.snWantPL  EQUB &FF,&FF,&FF     \ desired tone periods; &FF,&FF = "keep"
.snWantPH  EQUB &FF,&FF,&FF
.snChanB   EQUB &00,&20,&40     \ channel number in latch bits 5-6

\ ---- diff and write ----------------------------------------
.snf_write
  JSR SndWrOpen
  LDX #0
.snfw_tone
  LDA snWantPH,X
  CMP #&FF
  BEQ snfw_att                  \ no desire registered: leave the period
  CMP snChPerH,X
  BNE snfw_per
  LDA snWantPL,X
  CMP snChPerL,X
  BEQ snfw_att
.snfw_per
  LDA snWantPL,X                \ latch byte: 1 cc0 dddd, low 4 bits of N
  AND #&0F
  ORA snChanB,X                 \ channel bits 5-6, from the table below
  ORA #&80
  JSR SndWrByte
  LDA snWantPH,X                \ data byte: N bits 4-9
  ASL A
  ASL A
  ASL A
  ASL A
  STA snTmp
  LDA snWantPL,X
  LSR A
  LSR A
  LSR A
  LSR A
  ORA snTmp
  AND #&3F
  JSR SndWrByte
  LDA snWantPL,X
  STA snChPerL,X
  LDA snWantPH,X
  STA snChPerH,X
.snfw_att
  LDA snWantPH,X                \ desires are one-tick: reset to "keep"
  ORA #&FF
  STA snWantPH,X
  LDA snWantAtt,X
  CMP snChAtt,X
  BEQ snfw_next
  STA snChAtt,X
  ORA snChanB,X
  ORA #&90                      \ attenuation latch: 1 cc1 aaaa
  JSR SndWrByte
.snfw_next
  INX
  CPX #3
  BCC snfw_tone

  LDA snWantAtt+3               \ the noise channel: control, then volume
  CMP #15
  BEQ snfw_nzatt                \ silent: no need to touch the control
  LDA #&E7                      \ white noise, clocked by tone 2 — stage 0
  CMP snNzCtl
  BEQ snfw_nzatt
  STA snNzCtl
  JSR SndWrByte
.snfw_nzatt
  LDA snWantAtt+3
  CMP snChAtt+3
  BEQ snfw_done
  STA snChAtt+3
  ORA #&F0
  JSR SndWrByte
.snfw_done
  JMP SndWrClose

\ ============================================================
\ SndSilence — every channel to attenuation 15, caches reset.
\ Also the state-0 idle and the $1x initialiser ($074C's job).
\ ============================================================
.SndSilence
  JSR SndWrOpen
  LDX #3
.sns_hush
  LDA snsAtt15,X
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
  STA sndFx1
  STA sndFx2
  LDA #1
  STA snQuiet
  RTS
.snsAtt15
  EQUB &9F,&BF,&DF,&FF

\ ============================================================
\ SndConv — SID frequency (snCvL/H) to SN period (snCvL/H).
\ N = sndFreq[(F<<s)>>8 - 128] >> (8-s), clamped to 1..1023;
\ snCvNz nonzero shifts 4 more (the noise scaling, exporter hdr).
\ ============================================================
.SndConv
  LDA snCvNz                    \ a noise voice divides by 16F, which is
  BEQ snc_tone                  \ the tone maths on F*16 — pre-scale, and
  LDX #4                        \ saturate: F >= &1000 means N <= 32, and
.snc_nzsc                       \ a saturated &FFFF converts to N=32 too
  ASL snCvL
  ROL snCvH
  BCC snc_nzok
  LDA #&FF
  STA snCvL
  STA snCvH
  BNE snc_tone                  \ always
.snc_nzok
  DEX
  BNE snc_nzsc
.snc_tone
  LDA snCvH
  CMP #8                        \ F < 2048 can only clamp: skip the maths.
  BCS snc_go                    \ (2048-2080 also land on 1023 — exact)
.snc_max
  LDA #&FF
  STA snCvL
  LDA #3
  STA snCvH
  RTS
.snc_go
  LDX #8                        \ X = 8 - s, counted down as we normalise
.snc_norm
  LDA snCvH
  BMI snc_look
  ASL snCvL
  ROL snCvH
  DEX
  BNE snc_norm                  \ hi >= 8 → at most 4 shifts, X >= 4
.snc_look
  LDA snCvH
  SEC
  SBC #128
  LSR A                         \ 64-entry table: two m values share an
  TAY                           \ entry cut at their midpoint (exporter)
  LDA sndFreqHi,Y
  STA snCvH
  LDA sndFreqLo,Y
  STA snCvL
.snc_sh
  LSR snCvH
  ROR snCvL
  DEX
  BNE snc_sh
  LDA snCvH
  CMP #4                        \ > 1023?
  BCS snc_max
  RTS

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
  LDY #6
.snwb_dly
  DEY
  BNE snwb_dly                  \ ~31 cycles ≈ 15 µs; the chip needs ~8
  LDA #8
  STA SND_PORTB
  RTS

.SndWrClose
  LDA snWrO
  STA SND_ORA
  LDA snWrD
  STA SND_DDRA
  RTS
