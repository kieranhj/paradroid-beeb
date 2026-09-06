\ ============================================================
\ sprsplit.asm — may the sprite pool be split this pass?
\ ============================================================
\ BANK 5 (bank 6 until 2026-09-01, when this outgrew its last 7 bytes),
\ reached through the SprSplitOK bridge in sprite.asm. It lives
\ here because it grew past what the code image had left, and it CAN
\ live here because every byte it reads is outside bank 4: the level
\ draw's flags and `line` are zero page, the door table and the sprite
\ arrays are in the code image's own state, and the animated-tile list
\ is in the low overlay at &0C90.
\
\ ---- what the split is for ---------------------------------
\ Restoring the whole pool and redrawing it costs about 5,200 cycles a
\ sprite, and an off-display window is 24,576. Four sprites fill one.
\ So the pool is cut in two and each half is erased AND redrawn inside
\ its own window — window A at the top of the pass, window B after the
\ droid AI — which is the condition for a sprite never to be displayed
\ erased. A pass that cannot be split erases everything at the top and
\ does not finish redrawing for 40,000 cycles, which is longer than a
\ field, so every sprite is missing for one field in two. That is the
\ flicker.
\
\ ---- what used to stop it, and what stops it now -----------
\ The invariant the whole file rests on is that every buffer write
\ happens while all sprites are erased — DoRedraws' own comment says it:
\ a door repaint "must happen between SprRestoreAll and SprDrawAll ...
\ or it stamps pixels into a sprite's saved background". Split the pool
\ and tranche B is still ON SCREEN while the level draw runs.
\
\ So the split used to be refused outright on any pass with a band, a
\ column, a moving door or an animated tile to repaint — which is EVERY
\ PASS THE PLAYER MOVES, and every other pass with a recharge pad in
\ view. Measured 2026-08-20, that is most of play, and the flicker with
\ it.
\
\ [DECISION, 2026-08-20] THE GLOBAL VETO IS REPLACED BY A LOCAL TEST.
\ What the level draw writes this pass is known before it runs: whole
\ display rows (a band, full width), whole 4-pixel columns (full
\ height), and single tiles (doors, rechargers, ALERT signs). So instead
\ of refusing the split, any sprite standing under one of those writes
\ is FORCED INTO TRANCHE A — the tranche that is already erased when the
\ level draw runs. Tranche B is then disjoint from everything this pass
\ writes, by construction, and the invariant holds without the veto.
\ [DECISION, 2026-09-01] THE WRITERS HAVE TWO CLASSES NOW. The band
\ and the columns are latch-bound and paint in window A: a sprite
\ under them is forced into tranche A, erased while they land. The
\ single-tile writers -- a moving door, the recharger, the ALERT sign
\ -- paint in window B on a split pass (DoorAnimPaint, between
\ tranche B's restore and its draw): a sprite under one is forced
\ into tranche B. A component under BOTH classes has no safe tranche
\ and the split is refused for the pass. SprScanCls (bank 5,
\ src/sprscan.asm) computes the per-slot class byte; this file
\ consumes it. "FORCED INTO TRANCHE A" above should be read as
\ "forced into the writer's window's tranche" throughout.
\
\ Overlap components make that sound: forcing is applied to a whole
\ component, so a sprite overlapping a forced one is forced with it.
\
\ ---- why the test is loose ---------------------------------
\ A tranche-B sprite's SAVED BACKGROUND was taken last pass, so the test
\ has to cover where it was drawn LAST pass as well as where it will be
\ drawn this one. Both spans are therefore padded by eight — a pass's
\ worth of scroll, which is the most any sprite's view position can
\ shift — and the tile tests ignore rows entirely and compare columns
\ only. Every one of those errs towards forcing tranche A, which costs a
\ split that could have been taken and never costs correctness.
\ ============================================================

\ ============================================================
\ SprSplitDecide — the answer, in sprSplit. Non-zero = split
\ ============================================================
\ A slot that is no longer drawable but still holds a saved background
\ has to be restored at the position it was DRAWN at, and nothing here
\ knows that position — so the overlap test cannot see it and the pass
\ is drawn whole instead. It happens on the one pass a droid leaves the
\ window, and it is the one veto left.
.SprSplitDecide
  LDX #SPR_SLOTS-1
.ssd_stale
  LDA sprSaved,X
  BEQ ssd_snext
  LDA sprActive,X
  BEQ ssd_no
.ssd_snext
  DEX
  BPL ssd_stale

  JSR SprAssignTr               \ and its answer is ours
  STA sprSplit
  RTS
.ssd_no
  LDA #0
  STA sprSplit
  RTS

\ ============================================================
\ SprAssignTr — put the slots in two tranches. A = 1 always
\ ============================================================
\ Overlapping sprites HAVE to share a tranche, so the tranches are
\ unions of connected components of the overlap graph. Eight slots
\ makes the naive algorithm free: label every slot with its own index,
\ merge labels across each overlapping pair, then hand whole components
\ to whichever tranche is emptier.
\
\ Slot 0 is looked at first and a tie goes to A, so the player is
\ always in the window drawn first — the one thing on screen the eye is
\ actually tracking.
\
\ A COMPONENT WITH ANYTHING UNDER THIS PASS'S DRAWING GOES TO A whatever
\ the balance says. That is the Phase 2 change; see the header.
\
\ IT NEVER REFUSES ON BALANCE, and it used to. A window has room for
\ four sprites restored and drawn, so an earlier version gave up when a
\ tranche came out bigger than that and drew the pool whole — which is
\ the wrong trade. An oversized tranche is doing exactly what the whole
\ pool does today, and the OTHER tranche still gets a clean window, so
\ an unbalanced split is strictly better than none. The degenerate case
\ falls out of the same rule: if everything overlaps everything it is
\ one component, it all goes to A, tranche B is empty and the pass
\ behaves as it did before any of this.
.SprAssignTr
  LDX #SPR_SLOTS-1              \ label: own index, or &FF if inactive
.sat_init
  LDA #&FF
  STA sprTr,X
  LDY sprActive,X
  BEQ sat_initset
  TXA
.sat_initset
  STA sprComp,X
  DEX
  BPL sat_init

  LDA #0                        \ merge across every overlapping pair
  STA satI
.sat_i
  LDX satI
  LDA sprActive,X
  BEQ sat_inext
  LDA satI
  CLC
  ADC #1
  STA satJ
.sat_j
  LDA satJ
  CMP #SPR_SLOTS
  BCS sat_inext
  TAY
  LDA sprActive,Y
  BEQ sat_jnext
  LDX satI
  JSR SprOverlapXY
  BCC sat_jnext
  LDX satJ                      \ relabel everything in J's component
  LDA sprComp,X
  STA satOld
  LDX satI
  LDA sprComp,X
  STA satNew
  LDX #SPR_SLOTS-1
.sat_merge
  LDA sprComp,X
  CMP satOld
  BNE sat_mnext
  LDA satNew
  STA sprComp,X
.sat_mnext
  DEX
  BPL sat_merge
.sat_jnext
  INC satJ
  JMP sat_j
.sat_inext
  INC satI
  LDA satI
  CMP #SPR_SLOTS
  BNE sat_i

  LDA #0                        \ hand out whole components
  STA satNA
  STA satNB
  STA satI
.sat_asg
  LDX satI
  LDA sprComp,X
  CMP #&FF
  BNE sat_live                  \ inactive: in neither tranche. The
  JMP sat_asgnext               \ player-refuse block pushed the label
.sat_live                       \ out of branch range (2026-09-01)
  LDA sprTr,X
  CMP #&FF
  BEQ sat_place                 \ its component is already placed
  JMP sat_asgnext
.sat_place
  LDX satI
  LDA sprComp,X
  STA satNew
  LDA #0
  STA satCount
  STA satForce
  LDX #SPR_SLOTS-1
.sat_cnt
  LDA sprComp,X
  CMP satNew
  BNE sat_cntnext
  INC satCount
  LDA sprCls,X                  \ under this pass's writes? SprScanCls
  AND #3                        \ (bank 5) answered before we were paged:
  ORA satForce                  \ bit 0 window-A writers, bit 1 window-B.
  STA satForce                  \ Bit 2 of sprCls[0] is the view-moved
                                \ flag, masked off here
.sat_cntnext
  DEX
  BPL sat_cnt

  LDA satForce                  \ under a window-A writer it MUST be in
  CMP #3                        \ tranche A (erased while the band and
  BEQ sat_refuse                \ columns paint); under a window-B one it
  LSR A                         \ MUST be in tranche B (erased while the
  BCS sat_toA                   \ tiles repaint); under BOTH no tranche
  LDA satForce                  \ is safe and the pass is drawn whole
  AND #2
  BEQ sat_bal
\ Forced to tranche B - unless this is the PLAYER's component on a
\ pass the view moved. A tranche-B image lags the scroll by one field,
\ invisible on a droid but a 25 Hz judder on the one sprite the eye
\ holds against the screen frame, so his component refuses the split
\ instead (2026-09-01). Bit 2 of sprCls[0] is SprScanCls's view-moved
\ flag; standing still (recharging on a pad) keeps the split.
  LDA satNew
  CMP sprComp+0
  BNE sat_toB
  LDA sprCls+0
  AND #4
  BNE sat_refuse
  BEQ sat_toB                   \ always
.sat_bal
  LDA satNA                     \ otherwise the emptier tranche takes it,
  CMP satNB                     \ and a tie goes to A, which is how slot 0
  BCC sat_toA                   \ ends up there
  BEQ sat_toA
.sat_toB
  CLC
  LDA satNB
  ADC satCount
  STA satNB
  LDA #1
  BNE sat_mark                  \ always
.sat_toA
  CLC
  LDA satNA
  ADC satCount
  STA satNA
  LDA #0
.sat_mark
  STA satWhich
  LDX #SPR_SLOTS-1
.sat_mk
  LDA sprComp,X
  CMP satNew
  BNE sat_mknext
  LDA satWhich
  STA sprTr,X
.sat_mknext
  DEX
  BPL sat_mk
.sat_asgnext
  INC satI
  LDA satI
  CMP #SPR_SLOTS
  BEQ sat_done                  \ the component walk grew past a branch's
  JMP sat_asg                   \ reach when the forcing test went in

.sat_done
  LDA #1                        \ always: see the note on balance above
  RTS
.sat_refuse
  LDA #0                        \ a component under both windows' writers:
  RTS                           \ sprTr is half-written but a whole pass
                                \ never reads it

\ ============================================================
\ SprOverlapXY — slots X and Y close enough to share a tranche
\ ============================================================
\ Deliberately loose — 7 wide plus 2 units of a pass's movement, and 21
\ scanlines plus 8 — because it has to cover where the other tranche was
\ drawn LAST pass as well as this one.
SPR_OVL_U = SPR_W + 2
SPR_OVL_Y = SPR_H + 8

.SprOverlapXY
  LDA sprUnit,X
  SEC
  SBC sprUnit,Y
  JSR SprAbsA
  CMP #SPR_OVL_U
  BCS sov_no
  LDA sprScrY,X
  SEC
  SBC sprScrY,Y
  JSR SprAbsA
  CMP #SPR_OVL_Y
  BCS sov_no
  SEC
  RTS
.sov_no
  CLC
  RTS

\ |A|, which the overlap test wants both ways round.
.SprAbsA
  BPL sab_x
  EOR #&FF
  CLC
  ADC #1
.sab_x
  RTS

IF DEBUG_TRCHK
\ ============================================================
\ SprTrCheck — DEBUG_TRCHK: does the split ever break its own rule?
\ ============================================================
\ THE INVARIANT UNDER TEST. Within a pass the order is restore A, draw
\ A, ..., restore B, draw B. So if a tranche-B sprite overlaps a
\ tranche-A one, B's saved background is taken with A already drawn
\ into it, and next pass B's restore stamps an A-shaped fragment back
\ at B's OLD position — sprite pixels left behind. SprAssignTr exists
\ to stop that: overlapping sprites must share a tranche.
\
\ This walks every pair AFTER both tranches are drawn, with sprUnit and
\ sprScrY still holding the positions the pass actually drew at (the
\ movement pipeline writes the next pass's below).
\
\ IT TESTS THE UNION OF THIS PASS'S AND LAST PASS'S FOOTPRINTS, and it
\ has to. The hazard is not only two overlapping sprites drawn in
\ opposite tranches this pass: a tranche-B sprite's saved background
\ was taken LAST pass, so a bullet that was over a droid last pass and
\ has since moved 12 px away still stamps that droid's pixels back
\ when it is restored. So each slot keeps the position it was drawn at
\ last pass and the test is union against union — which is exactly
\ what SprOverlapXY's 8 px pad is trying to approximate, and the point
\ of the exercise is whether 8 px is enough.
\
\ The test here is EXACT — no pad — because this is the condition the
\ invariant is stated in. A non-zero count says the assignment let a
\ pair into opposite tranches whose footprints do meet, which cannot be
\ anything but a hole in the padding or in SprAssignTr itself.
\
\ Reads out as three hex bytes at the top left of the panel: the hit
\ count (saturating at FF), then the two slot numbers of the last pair.
\ NOT COMPATIBLE WITH DEBUG_POS OR DEBUG_VSYNC — same digits.
.dbgTrHits EQUB 0
.dbgTrI    EQUB 0
.dbgTrJ    EQUB 0
.trcI      EQUB 0
.trcJ      EQUB 0
.trcULo    SKIP SPR_SLOTS        \ the union box, per slot: min and max
.trcUHi    SKIP SPR_SLOTS        \ of last pass's drawn position and
.trcYLo    SKIP SPR_SLOTS        \ this one's
.trcYHi    SKIP SPR_SLOTS
.trcUOld   SKIP SPR_SLOTS        \ what it was drawn at last pass; &FF
.trcYOld   SKIP SPR_SLOTS        \ in trcTrOld means "not drawn"
.trcTrOld  SKIP SPR_SLOTS

.SprTrCheck
\ ---- the union box, and this pass's positions kept for the next -----
  LDX #SPR_SLOTS-1
.trc_box
  LDA sprTr,X
  CMP #&FF                      \ not drawn this pass: no box, and
  BEQ trc_boxnone               \ nothing to carry forward
  LDA trcTrOld,X
  CMP #&FF
  BEQ trc_boxnew                \ not drawn last pass: the box is just
                                \ this pass's position
  LDA sprUnit,X
  CMP trcUOld,X
  BCC trc_uold                  \ this < last
  LDA trcUOld,X : STA trcULo,X
  LDA sprUnit,X : STA trcUHi,X
  JMP trc_boxy
.trc_uold
  LDA sprUnit,X : STA trcULo,X
  LDA trcUOld,X : STA trcUHi,X
.trc_boxy
  LDA sprScrY,X
  CMP trcYOld,X
  BCC trc_yold
  LDA trcYOld,X : STA trcYLo,X
  LDA sprScrY,X : STA trcYHi,X
  JMP trc_boxnext
.trc_yold
  LDA sprScrY,X : STA trcYLo,X
  LDA trcYOld,X : STA trcYHi,X
  JMP trc_boxnext
.trc_boxnew
  LDA sprUnit,X : STA trcULo,X : STA trcUHi,X
  LDA sprScrY,X : STA trcYLo,X : STA trcYHi,X
.trc_boxnext
  LDA sprUnit,X : STA trcUOld,X
  LDA sprScrY,X : STA trcYOld,X
.trc_boxstore
  LDA sprTr,X   : STA trcTrOld,X
  DEX
  BMI trc_pairs
  JMP trc_box
.trc_boxnone
  LDA #&FF : STA trcTrOld,X     \ and leave the old position alone
  DEX
  BMI trc_pairs                 \ out of a branch's reach
  JMP trc_box

\ ---- every pair in opposite tranches whose boxes meet --------------
.trc_pairs
  LDA #0
  STA trcI
.trc_i
  LDX trcI
  LDA sprTr,X
  CMP #&FF
  BEQ trc_inext
  LDA trcI
  CLC
  ADC #1
  STA trcJ
.trc_j
  LDA trcJ
  CMP #SPR_SLOTS
  BCS trc_inext
  TAY
  LDA sprTr,Y
  CMP #&FF
  BEQ trc_jnext
  LDX trcI
  CMP sprTr,X                   \ A is sprTr,Y — same tranche is legal
  BEQ trc_jnext

\ Boxes overlap when each low edge is inside the other's extent. The
\ sprite is SPR_W units by SPR_H scanlines, so the extent is the box
\ plus that less one.
  LDA trcUHi,Y
  CLC
  ADC #SPR_W-1
  CMP trcULo,X
  BCC trc_jnext                 \ j ends left of i
  LDA trcUHi,X
  CLC
  ADC #SPR_W-1
  CMP trcULo,Y
  BCC trc_jnext
  LDA trcYHi,Y
  CLC
  ADC #SPR_H-1
  CMP trcYLo,X
  BCC trc_jnext
  LDA trcYHi,X
  CLC
  ADC #SPR_H-1
  CMP trcYLo,Y
  BCC trc_jnext

.trc_hit                        \ THE BREAKPOINT: reached only on a
  LDA trcI : STA dbgTrI         \ violation, so a jsbeeb execute
  LDA trcJ : STA dbgTrJ         \ breakpoint here is the whole proof
  LDA dbgTrHits
  CMP #&FF
  BEQ trc_jnext
  INC dbgTrHits
.trc_jnext
  INC trcJ
  JMP trc_j
.trc_inext
  INC trcI
  LDA trcI
  CMP #SPR_SLOTS
  BEQ trc_out
  JMP trc_i
.trc_out
  LDA #LO(DBG_PANEL_TL) : STA swDst
  LDA #HI(DBG_PANEL_TL) : STA swDst+1
  LDA dbgTrHits : JSR DbgHexByte
  LDA dbgTrI    : JSR DbgHexByte
  LDA dbgTrJ    : JSR DbgHexByte
  RTS
ENDIF
