\ ============================================================
\ sprsplit.asm — may the sprite pool be split this pass?
\ ============================================================
\ BANK 6, reached through the SprSplitOK bridge in sprite.asm. It lives
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
  BEQ sat_asgnext               \ inactive: in neither tranche
  LDA sprTr,X
  CMP #&FF
  BNE sat_asgnext               \ its component is already placed
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
  JSR SprHitsDraw               \ is this member under this pass's writes?
  BCC sat_cntnext
  LDA #1
  STA satForce
.sat_cntnext
  DEX
  BPL sat_cnt

  LDA satForce                  \ under the level draw: it MUST be in the
  BNE sat_toA                   \ tranche that is erased while it runs
  LDA satNA                     \ otherwise the emptier tranche takes it,
  CMP satNB                     \ and a tie goes to A, which is how slot 0
  BCC sat_toA                   \ ends up there
  BEQ sat_toA
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

\ ============================================================
\ SprHitsDraw — is slot X under anything this pass will write?
\ ============================================================
\ Carry set if it is. X is preserved; SprAssignTr's count loop uses it.
\
\ FOUR WRITERS, and each reduces to a ONE-DIMENSIONAL test because of
\ what it covers:
\   the band     one display row, FULL WIDTH      -> scanlines only
\   the columns  4-pixel columns, FULL HEIGHT     -> units only
\   a door       one tile                         -> units only, rows
\   an anim tile one tile                            ignored (loose)
\ The two tile cases ignore rows because a map row is cheap to get
\ wrong and forcing tranche A is always the safe answer.
.SprHitsDraw
  TXA
  PHA

\ ---- the sprite's own two spans, both padded ----------------
\ Padded by eight either side: a pass can scroll the view eight units,
\ so a sprite that has not moved at all can still be eight units from
\ where its saved background was taken.
  LDA line                      \ scanlines below the top of the STRIP
  CLC
  ADC sprScrY,X
  STA shdT
  SEC
  SBC #8
  BCS shd_v0
  LDA #0
.shd_v0
  STA shdV0
  LDA shdT
  CLC
  ADC #SPR_H + 8
  STA shdV1

  LDA sprUnit,X
  SEC
  SBC #8
  BCS shd_u0
  LDA #0
.shd_u0
  STA shdU0
  LDA sprUnit,X
  CLC
  ADC #SPR_W + 8
  STA shdU1

\ ---- the band: one display row, full width ------------------
  LDA bandDo
  BEQ shd_cols
  LDA shdV0 : STA shdS0
  LDA shdV1 : STA shdS1
  LDA bandRc                    \ display row -> its eight scanlines
  ASL A : ASL A : ASL A
  STA shdA
  LDA #8
  STA shdLA
  JSR SprSpanHit
  BCS shd_yes

\ ---- the columns: 4-pixel columns, full height --------------
.shd_cols
  LDA shdU0 : STA shdS0         \ everything below is a unit test
  LDA shdU1 : STA shdS1

  LDA colCount
  BEQ shd_anim
  STA shdLA
  LDA colFirst
  STA shdA
  JSR SprSpanHit
  BCS shd_yes

\ ---- the animated tiles AnimPaint will repaint --------------
\ animDirty is what AnimPaint itself tests, so a list with nothing to do
\ this pass costs one branch.
.shd_anim
  LDA animDirty
  BEQ shd_doors
  LDX animCount
  BEQ shd_doors
.shd_aloop
  DEX
  LDA animCol,X
  JSR SprTileHit
  BCS shd_yes
  TXA
  BNE shd_aloop

\ ---- the doors DoorsUpdate will repaint ---------------------
\ A door only writes on a pass where it MOVES. One being held open —
\ bit 6, set by the probes in CheckWalls, which run before this — is
\ not decremented and not marked dirty by DoorsUpdate, so it repaints
\ nothing and is not a writer.
.shd_doors
  LDX numDoors
  BEQ shd_no
.shd_dloop
  DEX
  LDA doorDirty,X               \ already opening, from this pass's probe
  BNE shd_dhit
  LDA doorState,X
  AND #&40
  BNE shd_dnext                 \ held open: static this pass
  LDA doorState,X
  AND #7
  BEQ shd_dnext                 \ shut and staying shut
.shd_dhit
  LDA doorCol,X
  JSR SprTileHit
  BCS shd_yes
.shd_dnext
  TXA
  BNE shd_dloop

.shd_no
  PLA
  TAX
  CLC
  RTS
.shd_yes
  PLA
  TAX
  SEC
  RTS

\ ============================================================
\ SprTileHit — A = a tile column. Carry set if it hits the span
\ ============================================================
\ A tile is four characters, which is eight units. Its left edge in view
\ units is col * 8 - mapHX, and that is signed: the map is 64 tile
\ columns and the view is eleven of them.
\
\ THE THREE OUTCOMES. Wholly right of the view or wholly left of it,
\ miss. Straddling the left edge — the top byte &FF and the low byte in
\ -8..-1 — is reported as a hit at unit 0, which is conservative and
\ two instructions instead of a clamp. Preserves X.
.SprTileHit
  STA shdT
  LDA #0
  STA shdT+1
  ASL shdT : ROL shdT+1
  ASL shdT : ROL shdT+1
  ASL shdT : ROL shdT+1
  SEC
  LDA shdT   : SBC mapHX   : STA shdT
  LDA shdT+1 : SBC mapHX+1 : STA shdT+1

  BMI sth_left
  BNE sth_no                    \ high byte above zero: far to the right
  LDA shdT
  CMP #PLAY_UNITS
  BCS sth_no
  STA shdA
  LDA #8
  STA shdLA
  JMP SprSpanHit

.sth_left
  LDA shdT+1
  CMP #&FF
  BNE sth_no                    \ more than a page left of the view
  LDA shdT
  CMP #256 - 8
  BCC sth_no                    \ left of the view by a whole tile or more
  LDA #0                        \ straddling the left edge
  STA shdA
  LDA #8
  STA shdLA
  JMP SprSpanHit
.sth_no
  CLC
  RTS

\ ============================================================
\ SprSpanHit — [shdA, shdA+shdLA) against [shdS0, shdS1)
\ ============================================================
\ Carry set if they overlap. Both are unsigned and both fit in a byte:
\ the spans are clamped at zero and the widest is 94. Preserves X.
.SprSpanHit
  CLC
  LDA shdA
  ADC shdLA
  CMP shdS0
  BCC ssh_no                    \ the writer ends at or before the span
  BEQ ssh_no
  LDA shdA
  CMP shdS1
  BCS ssh_no                    \ and it starts at or after the end of it
  SEC
  RTS
.ssh_no
  CLC
  RTS

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
