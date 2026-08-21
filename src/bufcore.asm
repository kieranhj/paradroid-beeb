\ ============================================================
\ bufcore.asm — the parts of the screen code that CANNOT be banked
\ ============================================================
\ screen.asm, scroll.asm, level.asm and droid.asm live in SWRAM_DATA,
\ next to the tile, deck and waypoint data they read. Four routines and
\ one pair of tables cannot go with them, for two different reasons.
\
\ RUN BEFORE THE BANK EXISTS. SetupMode is the first thing `start`
\ calls — before the *LOAD of PARADAT, let alone the copy up into
\ the bank. SetupRupture runs between the loads and InstallIrq, and
\ SetCRTCStart comes with them, because SetupRupture calls it.
\
\ RUN WHILE SWRAM_SPR IS PAGED IN. SprDrawAll and SprRestoreAll page
\ the sprite bank in around themselves, and inside that window:
\   - SprScanRow tail-calls WrapBufFwd, and SCANSTEP is inlined into
\     every compiled row in the bank, so this is reached from bank
\     code as well as from sprite.asm;
\   - SprCalcAddr calls SetCell, which reads rowMul/unitMul — so the
\     tables have to stay too, all 192 bytes of them.
\ A JSR from here into SWRAM_DATA while that bank is out reaches
\ whatever the sprite bank has at the same address, which is
\ compiled sprite rows. There is no diagnostic for that, so the rule
\ is worth stating twice: **nothing in this file may call into
\ screen.asm, scroll.asm, level.asm or droid.asm.**
\
\ The other direction is always safe. Bank code calling main RAM is
\ fine, and so is main-RAM code calling the bank while SWRAM_DATA is
\ paged in — which is the resting state, so the main loop, LoadDeck,
\ door.asm and lift.asm need no paging of their own.
\ ============================================================

\ ============================================================
\ SetupMode / SetupRupture — MODE 1 geometry with a 10K wrap
\ at &5800, IN TWO HALVES WITH THE DISC LOADS BETWEEN THEM
\ ============================================================
\ THE SPLIT IS NOT COSMETIC. **No filing-system call may happen once
\ R7 has been given the rupture's tail-cycle value.** R7 = TAIL_R7 is
\ deliberately behind the row it should fire on, so VSync never
\ happens and the CRTC free-runs — which is what makes the rupture
\ lock on the first field. The MOS's disc code needs VSync: with it
\ stopped, `*LOAD` issues its 8271 command and then spins forever in
\ the status poll at DFS's `BIT &FE80 / BMI`, command-busy set,
\ nothing ever completing.
\
\ Measured, by bisecting SetupScreen a write at a time under the
\ emulator with the three loads patched to return afterwards:
\
\   through R6 (R1, R8, R4, R5, R6 all set)   all three loads complete
\   R7 as well                                the SECOND load hangs
\
\ The first load survives because the drive is already selected; the
\ second needs a seek, and that is what never finishes.
\
\ So this is the same rule as InstallIrq's, one step earlier, and it
\ is stated in both places: **the loads sit between these two calls.**
\ SetupMode leaves an ordinary MODE 1 frame running — R1 and R8 only
\ change the width and the interlace — so VSync carries on throughout.
.SetupMode
  LDA #22 : JSR OSWRCH          \ MODE 1 (OS sets 20K / 16K wrap)
  LDA #1  : JSR OSWRCH

  LDA #23 : JSR OSWRCH          \ cursor off
  LDA #1  : JSR OSWRCH
  LDX #8
  LDA #0
.ss_cursoff
  JSR OSWRCH
  LDA #0
  DEX
  BNE ss_cursoff

  LDA #4 : LDX #1 : JSR OSBYTE  \ cursor keys return codes

\ Re-point the wraparound at the 10K / &5800 window. The latch takes
\ PB0-PB2 = line index, PB3 = value, so &08 OR n sets line n high.
  LDA #&08 OR 4                 \ C0 = 1
  STA VIA_PORTB
  LDA #&08 OR 5                 \ C1 = 1  -> subtract &2800, restart &5800
  STA VIA_PORTB

  CRTC 1,  PLAY_UNITS           \ 80 units = 320 px displayed

\ R8 = 0: non-interlaced. The OS leaves MODE 1 at R8=1 (interlace
\ sync), which offsets VSync by half a scanline on alternate fields.
\ Our rupture timers are fixed intervals from VSync, so that half
\ line makes the split land in a different place every other field
\ — an intermittent glitch along the top of the play area.
  CRTC 8,  0
  RTS

\ ---- the second half: after the loads, before InstallIrq ----
\ Everything from here stops VSync, so nothing may touch the filing
\ system again — see the header.
.SetupRupture
\ Start in the TAIL cycle's shape. The picture rolls until the IRQ
\ takes over, but the first VSync then arrives with C4 exactly
\ where the steady state expects it — TAIL_R7 rows into a 13-row
\ cycle, 4 since FRAME_DROP_ROWS and 8 before it — so the rupture
\ locks on the first field instead of thrashing for several.
\ Handing it a normal 39-row frame instead means VSync arrives at
\ C4 = 34 and the handler writes R4 = 12 behind it. Both registers
\ come from the constants, so moving the picture keeps them in step.
  CRTC 4,  TAIL_R4
  CRTC 5,  0
  CRTC 6,  0
  CRTC 7,  TAIL_R7

  LDA #0                        \ start at the bottom of the buffer
  STA scrollS
  STA scrollS+1
  JSR SetCRTCStart

  LDA #12 : STA CRTC_ADDR : LDA crtcHi : STA CRTC_DATA
  LDA #13 : STA CRTC_ADDR : LDA crtcLo : STA CRTC_DATA

  JSR RuptInit                  \ FillPanel is deliberately NOT here: the
  RTS                           \ PARADAT staging area runs through &4800,
                                \ so the panel has to be drawn after
                                \ PageDataIn has finished with it

\ ============================================================
\ SetCRTCStart — program R12/R13 from scrollS
\ CRTC start = physical address / 8.
\ ============================================================
\ With rupture running, R12/R13 belong to the IRQ — it latches the
\ panel address at VSync and the play address one cycle later. So
\ this only computes the value and parks it for the IRQ to pick up.
\ SEI around the store: the IRQ reads the pair ~5 rows after VSync
\ and must not see a half-updated address.
.SetCRTCStart
  CLC                           \ addr = BUF_BASE + scrollS
  LDA scrollS   : ADC #LO(BUF_BASE) : STA sTmp
  LDA scrollS+1 : ADC #HI(BUF_BASE) : STA sTmp+1

  LDX #3                        \ addr / 8
.sc_shift
  LSR sTmp+1
  ROR sTmp
  DEX
  BNE sc_shift

\ `line` is parked here too, and under the same SEI. The address and
\ the sub-row offset are one position between them — latched at
\ different points in the frame (fire 1 and, formerly, VSync), so
\ letting the IRQ see one updated and not the other shows a frame
\ at a position that never existed.
  SEI
  LDA sTmp+1 : STA crtcHi
  LDA sTmp   : STA crtcLo
  LDA line   : STA pline
  CLI
  RTS

\ ============================================================
\ WrapBufFwd — bufp past the end of the strip? bring it back
\ bufp is always a real address in [BUF_BASE, BUF_END).
\ ============================================================
\ Reached from the compiled rows in SWRAM_SPR, through SCANSTEP and
\ SprScanRow, which is why it is here and not in screen.asm.
.WrapBufFwd
  LDA bufp+1                    \ past the end? subtract the buffer size
  CMP #HI(BUF_END)
  BCC wbf_done
  BNE wbf_sub
  LDA bufp
  CMP #LO(BUF_END)
  BCC wbf_done
.wbf_sub
  SEC
  LDA bufp   : SBC #LO(BUF_SIZE) : STA bufp
  LDA bufp+1 : SBC #HI(BUF_SIZE) : STA bufp+1
.wbf_done
  RTS

\ ---- offset tables -----------------------------------------
\ Read by SetCell, which runs with the sprite bank paged in, so they
\ have to be main RAM's — but NOT the code image's. They used to be
\ 192 bytes of FOR/EQUB sitting in &1100-&3000, which is the only
\ region in the machine that is genuinely full; they are 192 bytes of
\ the free page at &5400 now, written once by BuildMulTabs. Startup
\ pays two short loops and the code image gets the 192 back.
rowMulLo  = ROWMUL_LO
rowMulHi  = ROWMUL_HI
unitMulLo = UNITMUL_LO
unitMulHi = UNITMUL_HI

\ ============================================================
\ BuildMulTabs — n * ROW_BYTES and n * UNIT_BYTES, at startup
\ ============================================================
\ Running 16-bit addition rather than multiplication, so the step is
\ the only thing that differs between the two halves. bufp is the
\ accumulator: it is SetCell's own pointer and nothing is using it
\ this early. MUST run after the bank staging AND after the title —
\ both write straight over &5400. See the call site in main.asm.
.BuildMulTabs
  LDA #0
  STA bufp
  STA bufp+1
  TAX
.bmt_row
  LDA bufp   : STA rowMulLo,X
  LDA bufp+1 : STA rowMulHi,X
  CLC
  LDA bufp   : ADC #LO(ROW_BYTES) : STA bufp
  LDA bufp+1 : ADC #HI(ROW_BYTES) : STA bufp+1
  INX
  CPX #PLAY_ROWS
  BNE bmt_row

  LDA #0
  STA bufp
  STA bufp+1
  TAX
.bmt_unit
  LDA bufp   : STA unitMulLo,X
  LDA bufp+1 : STA unitMulHi,X
  CLC
  LDA bufp   : ADC #LO(UNIT_BYTES) : STA bufp
  LDA bufp+1 : ADC #HI(UNIT_BYTES) : STA bufp+1
  INX
  CPX #PLAY_UNITS
  BNE bmt_unit
  RTS

\ ============================================================
\ SetCell — point bufp at display cell (rCount, uCount)
\   bufp = BUF_BASE + ((scrollS + rCount*640 + uCount*8) MOD SIZE)
\ ============================================================
\ Called by SprCalcAddr inside the sprite bank's window, as well as
\ by the level draw — hence its home here.
.SetCell
  LDX rCount
  CLC
  LDA scrollS   : ADC rowMulLo,X : STA bufp
  LDA scrollS+1 : ADC rowMulHi,X : STA bufp+1

  LDX uCount
  CLC
  LDA bufp   : ADC unitMulLo,X : STA bufp
  LDA bufp+1 : ADC unitMulHi,X : STA bufp+1

  LDA bufp+1                    \ wrap into [0, SIZE)
  CMP #HI(BUF_SIZE)
  BCC sc_nowrap
  BNE sc_wrap
  LDA bufp
  CMP #LO(BUF_SIZE)
  BCC sc_nowrap
.sc_wrap
  SEC
  LDA bufp   : SBC #LO(BUF_SIZE) : STA bufp
  LDA bufp+1 : SBC #HI(BUF_SIZE) : STA bufp+1
.sc_nowrap
  CLC
  LDA bufp   : ADC #LO(BUF_BASE) : STA bufp
  LDA bufp+1 : ADC #HI(BUF_BASE) : STA bufp+1
  RTS
