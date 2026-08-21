\ ============================================================
\ sndtest.asm — Layer 11e stage 0: verify the SN76489 facts
\ ============================================================
\ STANDALONE — not part of the game build. Verifies, in the
\ emulator, the recalled facts the sound driver would otherwise
\ be built on (docs/layer-11e-sound.md §5 stage 0):
\
\   1. the write sequence: System VIA port A + the slow-bus
\      strobe (addressable latch bit 0), latch byte 1cctdddd,
\      data byte 00dddddd
\   2. noise clocked by tone channel 2, white and periodic
\   3. sound writes from an IRQ interleaving with OSBYTE &81
\      keyboard polls, with DDRA/ORA saved and restored
\
\ Assemble (from anywhere disposable — it SAVEs a loose file):
\   ./bin/beebasm.exe -i tools/sndtest.asm -v
\ then poke the SNDTEST binary into the machine at &2000.
\
\ Entry points, from BASIC:
\   CALL &2000   silence all four channels
\   CALL &2003   tone 0 = period 284 (~440 Hz), attenuation 0
\   CALL &2006   white noise, /512 rate, attenuation 0
\   CALL &2009   pitched-noise sweep: noise clocked by tone 2
\                (tone 2 itself silenced), period swept 1023->64;
\                leaves noise running at the last pitch
\   CALL &200C   contention test, ~8192 OSBYTE &81 polls of SPACE
\                with a sound write on every MOS 100 Hz IRQ.
\                Results:  &2100/1 polls done (lo/hi)
\                          &2102/3 polls that saw SPACE down
\                          &2104/5 IRQ sound writes performed
\                Ends with tone 0 attenuation = 7 for a register
\                check, and the old IRQ1V restored.
\
\ The write primitive is the production shape: PHP/SEI, save
\ DDRA and ORA, write, strobe, restore, PLP. If test 3 shows
\ clean key reads AND correct chip state, that save/restore is
\ what the driver ships with.
\ ============================================================

OSBYTE   = &FFF4
IRQ1V    = &0204
PORTB    = &FE40                \ addressable latch: bit0 = sound /WE
DDRA     = &FE43
ORA_NH   = &FE4F                \ port A, no handshake

ORG &2000

.entry0  JMP Silence
.entry1  JMP Tone440
.entry2  JMP NoiseWhite
.entry3  JMP NoiseSweep
.entry4  JMP Contention

\ ---- results block for the contention test ----
ORG &2100
.resPolls  EQUW 0
.resDown   EQUW 0
.resIrqWr  EQUW 0

ORG &2110

\ ------------------------------------------------------------
\ SndWr — one byte to the SN76489.  A = the byte.
\ Preserves the keyboard's port A state around itself, which is
\ the production requirement: the driver runs in the IRQ and
\ may interrupt an OSBYTE &81 matrix scan mid-sequence.
\ ------------------------------------------------------------
.savA    EQUB 0
.savDdra EQUB 0
.savOra  EQUB 0

.SndWr
  STA savA
  PHP
  SEI                           \ foreground callers: no IRQ mid-strobe
  TXA : PHA
  LDA DDRA   : STA savDdra
  LDA ORA_NH : STA savOra       \ output bits read back the register
  LDA #&FF   : STA DDRA         \ all lines ours
  LDA savA   : STA ORA_NH
  LDA #0     : STA PORTB        \ sound /WE low — chip samples the bus
  LDX #6
.swDly
  DEX : BNE swDly               \ ~31 cycles ≈ 15 µs; chip needs ~8
  LDA #8     : STA PORTB        \ /WE high again
  LDA savOra : STA ORA_NH       \ keyboard column back first,
  LDA savDdra: STA DDRA         \ then the direction it had
  PLA : TAX
  PLP
  RTS

\ ------------------------------------------------------------
.Silence
  LDA #&9F : JSR SndWr          \ tone 0 attenuation 15
  LDA #&BF : JSR SndWr          \ tone 1
  LDA #&DF : JSR SndWr          \ tone 2
  LDA #&FF : JSR SndWr          \ noise
  RTS

\ ------------------------------------------------------------
\ Tone 0, period 284 -> 4e6/(32*284) = 440.1 Hz if the recalled
\ encoding and the 4 MHz clock are both right.
\ ------------------------------------------------------------
.Tone440
  JSR Silence
  LDA #&8C : JSR SndWr          \ latch: tone 0, low 4 bits of 284 (&11C)
  LDA #&11 : JSR SndWr          \ data: high 6 bits
  LDA #&90 : JSR SndWr          \ tone 0 attenuation 0 (loudest)
  RTS

\ ------------------------------------------------------------
.NoiseWhite
  JSR Silence
  LDA #&E4 : JSR SndWr          \ noise: white (FB=1), rate /512
  LDA #&F0 : JSR SndWr          \ noise attenuation 0
  RTS

\ ------------------------------------------------------------
\ Noise clocked by tone 2: noise NF=%11, tone 2 sets the rate
\ but is itself silenced.  Sweep tone 2's period 1023 -> 64 in
\ steps of 16, ~2 frames a step: a rising roar, the explosion
\ voice the driver wants.
\ ------------------------------------------------------------
.sweepLo EQUB 0
.sweepHi EQUB 0

.NoiseSweep
  JSR Silence
  LDA #&E7 : JSR SndWr          \ noise: white, clocked by tone 2
  LDA #&F0 : JSR SndWr          \ noise attenuation 0
  LDA #&FF : STA sweepLo
  LDA #&03 : STA sweepHi        \ period = &3FF
.nsStep
  LDA sweepLo
  AND #&0F
  ORA #&C0 : JSR SndWr          \ latch: tone 2, low 4 bits
  LDA sweepLo                   \ data byte: bits 9-4
  LSR A : LSR A : LSR A : LSR A
  STA savA
  LDA sweepHi
  ASL A : ASL A : ASL A : ASL A
  ORA savA
  JSR SndWr
  JSR Delay2f
  SEC                           \ period -= 16
  LDA sweepLo : SBC #16 : STA sweepLo
  LDA sweepHi : SBC #0  : STA sweepHi
  BNE nsStep                    \ while >= 256
  LDA sweepLo
  CMP #64
  BCS nsStep
  RTS

.Delay2f                        \ ~80,000 cycles, two fields' worth
  LDY #100
.d2fOuter
  LDX #159
.d2fInner
  DEX : BNE d2fInner
  DEY : BNE d2fOuter
  RTS

\ ------------------------------------------------------------
\ Contention: hook the front of IRQ1V so every MOS 100 Hz tick
\ performs one sound write, then hammer OSBYTE &81 polls of
\ SPACE from the foreground.  With SPACE held, every poll must
\ still read it down; the chip must end with exactly what the
\ IRQ wrote.  8192 polls is a second or so — enough for ~100+
\ IRQ writes, many landing inside a poll.
\ ------------------------------------------------------------
.oldIrq  EQUW 0
.ctOut   EQUB 0                 \ NOT savA — the IRQ's SndWr trashes that

.Contention
  JSR Silence
  LDA #0
  STA resPolls   : STA resPolls+1
  STA resDown    : STA resDown+1
  STA resIrqWr   : STA resIrqWr+1
  SEI
  LDA IRQ1V   : STA oldIrq
  LDA IRQ1V+1 : STA oldIrq+1
  LDA #LO(irqHook) : STA IRQ1V
  LDA #HI(irqHook) : STA IRQ1V+1
  CLI

  LDA #32 : STA ctOut           \ 32 * 256 = 8192 polls
.ctOuter
  LDY #0
.ctLoop
  TYA : PHA
  LDA #&81
  LDX #&9D                      \ INKEY -99 = SPACE
  LDY #&FF
  JSR OSBYTE
  INC resPolls
  BNE ctP1
  INC resPolls+1
.ctP1
  CPY #&FF                      \ Y=&FF: key is down
  BNE ctNotDown
  INC resDown
  BNE ctNotDown
  INC resDown+1
.ctNotDown
  PLA : TAY
  INY
  BNE ctLoop
  DEC ctOut
  BNE ctOuter

  SEI
  LDA oldIrq   : STA IRQ1V
  LDA oldIrq+1 : STA IRQ1V+1
  CLI
  RTS

\ The MOS has already stashed the interrupted A in &FC; X and Y
\ are live.  SndWr preserves X, we preserve Y by not using it.
.irqHook
  TXA : PHA
  LDA #&97 : JSR SndWr          \ tone 0 attenuation 7 — checkable
  INC resIrqWr
  BNE ihX
  INC resIrqWr+1
.ihX
  PLA : TAX
  JMP (oldIrq)

.testEnd

SAVE "SNDTEST", entry0, testEnd
