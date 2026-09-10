\ ============================================================
\ sprsplit.asm - may the sprite pool be split this pass?
\ ============================================================
\ BANK 6, reached through the SprSplitOK bridge in sprite.asm. It can
\ live in a bank at all because every byte it reads is outside bank 4:
\ the level draw's flags and `line` are zero page, the door table and the
\ sprite arrays are the code image's own state, and the animated-tile
\ list is in the low overlay at &0C90.
\
\ IT WAS TWO FILES IN TWO BANKS FROM 2026-09-01 TO 2026-09-09. The whole
\ thing is 634 bytes, it fitted no bank's free space, and this bank had
\ seven left - so the GEOMETRY half went to bank 5 as src/sprscan.asm and
\ the per-slot answer crossed the page flip in sprCls (low overlay).
\ Unfolding this bank's SCANSTEP tail brought sprscan.asm home (no-load
\ 11m) and the two files sat side by side in one bank for a day; the
\ split was never a design, so they are one file again (no-load 21e).
\ What that bought when it came home stands: SprSplitOK used to page
\ bank 5, call the geometry, page bank 6 and call the decision - now it
\ pages this bank once and calls both, A PAGE FLIP LESS THAN THE SPLIT.
\ The two halves still run in that order and SprScanCls is still first
\ in the file, which is what keeps the assembled bytes identical.

\ ============================================================
\ PART ONE - the tranche decision's geometry, per slot
\ ============================================================

\ ============================================================
\ SprScanCls -- fill sprCls: is each slot under this pass's writes?
\ ============================================================
\ sprCls,X = 1 if slot X stands under anything the pass will write to
\ the play buffer, else 0. Inactive slots read 0. SprAssignTr (bank 6)
\ ORs the byte over each overlap component to decide the forcing.
.SprScanCls
\ ---- once per pass: which writers exist at all? -------------
\ The commonest pass has NO buffer writer — no band, no column, no
\ dirty animated tile, no door moving — and used to pay the full
\ per-member geometry anyway, ~2,000-3,800 cycles at the front of
\ window A (docs/perf-audit-2026-08-31.md). The presence tests run
\ once here instead; the door predicate below is shd_doors' exactly,
\ so a door this loop calls static is one SprHitsDraw would have too.
  LDX numDoors
  BEQ sscw_nod
.sscw_dloop
  DEX
  LDA doorDirty,X               \ already opening, from this pass's probe
  BNE sscw_dyes
  LDA doorState,X
  AND #&40
  BNE sscw_dnext                \ held open: static this pass
  LDA doorState,X
  AND #7
  BNE sscw_dyes                 \ open and not held: closes a step
.sscw_dnext
  TXA
  BNE sscw_dloop
.sscw_nod
  LDA #0
  BEQ sscw_store                \ always
.sscw_dyes
  LDA #1
.sscw_store
  STA scnDoorW

  LDA animDirty                 \ anim presence is what AnimPaint tests:
  BEQ sscw_na                   \ dirty AND a non-empty list
  LDA animCount
.sscw_na
  ORA scnDoorW
  ORA bandDo
  ORA colCount
  STA scnAnyW

\ ---- how many sprites will window A hold this pass? ---------
\ THE TWO WINDOWS ARE NOT THE SAME SIZE, and until 2026-09-09 the
\ assignment behaved as though they were. Both are 24,576 cycles of
\ blanking, but window A also carries the pass preamble AND the level
\ draw; window B carries DoorAnimPaint and nothing else.
\ MEASURED 2026-09-09, seven slots live, three in each tranche, on a
\ pass with nothing for the level draw to do -- offsets from the
\ fire-3 that opens the window:
\        0 ->  6,720  ApplyMove, fire, AnimTick, SprSplitOK
\    6,720 -> 13,758  SprRestoreTr(A), three sprites, + SetCRTCStart
\   13,758 -> 14,441  DoRedraws, the debug keys, SprAnimateAll
\   14,441 -> 26,454  SprDrawTr(A), three sprites
\   24,576            the window shuts -- the draw was 1,878 LATE
\ so a restore and a draw is 6,350 a sprite and the fixed overhead was
\ 7,403 -- and 6,720 of that overhead was PassPrep, which LEFT WINDOW
\ A the next day (2026-09-10, main.asm's prepDone block). Re-measured
\ after: the restore starts 133 cycles into the window, a restore and
\ a draw is ~6,070, and what else window A pays is ~700. So it holds
\ (24,576 - 830 - level draw) / 6,070: THREE sprites on a quiet pass,
\ TWO behind a column draw (~4,900 -- 3.1, rounded down) and NONE
\ behind a band (~13,800-19,200). Window B holds SPR_CAP_B.
\ SprAssignTr used to hand components to whichever tranche was
\ emptier, which on the commonest crowd alternates A, B, A, B, A and
\ puts the MAJORITY in the window with least room. Measured over 100
\ diagonal passes with six slots live: nA = 3, nB = 2, and the
\ tranche-A draw ended with the play area already on display on 62
\ of them. See docs/raster-timing.md [DECISION, 2026-09-09].
  LDX #3                        \ nothing to draw: three fit
  LDA bandDo
  BNE sscw_cband
  LDA colCount
  BEQ sscw_ccap
  LDX #2                        \ a column pass: ~4,900 of the window gone
  BNE sscw_ccap                 \ always
.sscw_cband
  LDX #0                        \ a band: the window is spent, and the
.sscw_ccap                      \ player is pinned to A whatever this says
  STX satCapA

\ ---- did the view move this pass? ---------------------------
\ ApplyMove has already run, so oldHX/oldPosY against the live pair
\ says whether this pass scrolls. The answer rides to bank 6 as BIT 2
\ of sprCls[0]: a tranche-B sprite's buffer image lags the scroll by
\ one field, which is invisible on a droid but is a 25 Hz judder on
\ the PLAYER, the one sprite the eye holds against the screen frame -
\ so on a scrolling pass SprAssignTr refuses the split rather than
\ let his component take tranche B (2026-09-01, KC's judder report).
  LDY #0
  LDA mapHX   : CMP oldHX      : BNE sscv_mv
  LDA mapHX+1 : CMP oldHX+1    : BNE sscv_mv
  LDA posY    : CMP oldPosY    : BNE sscv_mv
  LDA posY+1  : CMP oldPosY+1  : BEQ sscv_st
.sscv_mv
  LDY #4
.sscv_st
  STY scnViewMv

  LDX #SPR_SLOTS-1
.sscl_loop
  LDA #0
  STA sprCls,X
  LDA scnAnyW
  BEQ sscl_next                 \ nothing writes: every slot reads 0
  LDA sprActive,X
  BEQ sscl_next
  JSR SprHitsDraw
  STA sprCls,X                  \ the class byte, 0..3
.sscl_next
  DEX
  BPL sscl_loop
  LDA sprCls+0                  \ bit 2: the view moved - see above.
  ORA scnViewMv                 \ Bank 6 masks the class bits back off
  STA sprCls+0                  \ before they reach satForce
  RTS

\ Bank 5 is RAM: the two per-pass flags live beside the code that is
\ the only reader and writer of either.
.scnDoorW EQUB 0                \ some door repaints this pass
.scnAnyW  EQUB 0                \ any writer at all this pass
.satCapA  EQUB 0                \ sprites window A has room for this pass
.scnViewMv EQUB 0               \ 4 when the view moved this pass
.shdCls   EQUB 0                \ SprHitsDraw's class accumulator
.shdR0    EQUB 0                \ the slot's padded char-row span
.shdR1    EQUB 0
.shdTR    EQUB 0                \ SprTileHit: the tile's row, set by caller
.shdRt    EQUB 0                \ SprTileHit: tile top, strip-relative

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
\ wrong and forcing a tranche is always the safe answer.
\ THE ANSWER IS A CLASS BYTE NOW, not a carry (2026-09-01): bit 0 for
\ the writers painted in window A (the band, the columns), bit 1 for
\ the writers painted in window B on a split pass (the animated
\ tiles). A sprite under a window-A writer must be in tranche A, one
\ under a window-B writer in tranche B, and one under both refuses
\ the split -- SprAssignTr acts on the bits. A = the byte on exit;
\ X is preserved.
.SprHitsDraw
  TXA
  PHA
  LDA #0
  STA shdCls

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

\ ...and the same two spans as CHARACTER ROWS, for the tile row test:
\ top inclusive, bottom exclusive, pads already inside shdV0/shdV1.
  LDA shdV0
  LSR A : LSR A : LSR A
  STA shdR0
  LDA shdV1
  CLC
  ADC #7
  LSR A : LSR A : LSR A
  STA shdR1

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
  BCC shd_cols
  LDA #1                        \ the band paints in window A
  STA shdCls

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
  BCC shd_anim
  LDA shdCls                    \ the columns paint in window A too
  ORA #1
  STA shdCls

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
  LDA animRow,X
  STA shdTR
  LDA animCol,X
  JSR SprTileHit
  BCS shd_ahit
  TXA
  BNE shd_aloop
  BEQ shd_doors                 \ always
.shd_ahit
  LDA shdCls                    \ an anim tile paints in window B on a
  ORA #2                        \ split pass -- the DoorAnimPaint window
  STA shdCls

\ ---- the doors DoorsUpdate will repaint ---------------------
\ A door only writes on a pass where it MOVES. One being held open —
\ bit 6, set by the probes in CheckWalls, which run before this — is
\ not decremented and not marked dirty by DoorsUpdate, so it repaints
\ nothing and is not a writer.
.shd_doors
  LDA scnDoorW                  \ hoisted: no door moves this pass, so
  BEQ shd_no                    \ skip the per-member walk entirely
  LDX numDoors
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
  LDA doorRow,X
  STA shdTR
  LDA doorCol,X
  JSR SprTileHit
  BCS shd_dhit2
.shd_dnext
  TXA
  BNE shd_dloop
  BEQ shd_no                    \ always
.shd_dhit2
  LDA shdCls                    \ a door repaint is window B's, like
  ORA #2                        \ the anim tiles: DoorAnimPaint runs
  STA shdCls                    \ between tranche B's restore and draw

.shd_no
  PLA
  TAX
  LDA shdCls
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
\ THE ROW TEST COMES FIRST (2026-09-01). The tile tests used to
\ ignore rows entirely - forcing was always safe when everything
\ forced tranche A, but a door ten rows away in the same columns now
\ costs a tranche-B forcing (or, for the player while scrolling, a
\ refused split), so the four char rows the tile covers are tested
\ against the slot's padded row span. All quantities are small
\ signed bytes, so plain SBC/BPL comparisons are safe.
  TAY                           \ keep the column
  LDA shdTR
  ASL A : ASL A                 \ tile row -> its top char row
  SEC
  SBC mapYr                     \ strip-relative, signed
  STA shdRt
  SEC
  SBC shdR1                     \ tile top at/below the span's bottom:
  BPL sth_rno                   \ miss
  LDA shdRt
  CLC
  ADC #4                        \ tile bottom (exclusive)
  SEC
  SBC shdR0                     \ at/above the span's top: miss
  BMI sth_rno
  BEQ sth_rno
  TYA                           \ the column, for the unit test below
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
.sth_rno
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
\ ---- the live slots, each labelled with its own index ---------
\ AND THE LIST OF THEM (2026-09-10). Every later walk runs over satLive
\ rather than all eight slots, which is most of what made this ~5,000
\ cycles a pass: the pair loop tested inactive slots 28 times over, and
\ each component was counted and then marked by a walk of all eight.
\ The per-label count and forcing are zeroed here for live slots only,
\ because a label is always a live slot's own index.
  LDY #0
  LDX #0
.sat_init
  LDA #&FF
  STA sprTr,X
  STA sprComp,X
  LDA sprActive,X
  BEQ sat_inext0
  TXA
  STA sprComp,X
  STA satLive,Y
  INY
  LDA #0
  STA satCnt,X
  STA satFrc,X
.sat_inext0
  INX
  CPX #SPR_SLOTS
  BNE sat_init
  STY satN

\ ---- merge across every overlapping pair -----------------------
\ THE OVERLAP TEST IS SprOverlapXY's, INLINED instruction for
\ instruction (the same SBC / BPL / EOR / ADC as SprAbsA, so the same
\ answer for every byte pair) — three JSR/RTS pairs a pair tested. The
\ padding and why it is loose: see SPR_OVL_U below.
  LDA #0
  STA satI
.sat_i
  LDX satI
  INX
  CPX satN
  BCS sat_mdone                 \ no J left above this I
  STX satJ
  DEX
  LDA satLive,X
  STA satSi                     \ slot I, reloaded for each J
.sat_j
  LDX satSi
  LDY satJ
  LDA satLive,Y
  TAY                           \ slot J
  LDA sprUnit,X
  SEC
  SBC sprUnit,Y
  BPL sat_du
  EOR #&FF
  CLC
  ADC #1
.sat_du
  CMP #SPR_OVL_U
  BCS sat_jnext
  LDA sprScrY,X
  SEC
  SBC sprScrY,Y
  BPL sat_dy
  EOR #&FF
  CLC
  ADC #1
.sat_dy
  CMP #SPR_OVL_Y
  BCS sat_jnext
  LDA sprComp,Y                 \ they overlap: J's component takes I's
  STA satOld                    \ label
  LDA sprComp,X
  CMP satOld
  BEQ sat_jnext                 \ already one component
  STA satNew
  LDY satN
.sat_merge
  DEY
  LDX satLive,Y
  LDA sprComp,X
  CMP satOld
  BNE sat_mnext
  LDA satNew
  STA sprComp,X
.sat_mnext
  TYA
  BNE sat_merge
.sat_jnext
  INC satJ
  LDA satJ
  CMP satN
  BCC sat_j
  INC satI
  JMP sat_i
.sat_mdone

\ ---- each component's size and forcing, in one walk -----------
\ A label is the index of a slot that is IN that component — a merge
\ either keeps a component's label or relabels every member away from
\ it — so satCnt/satFrc/sprTr indexed by label are per-component.
  LDY satN
  BEQ sat_aggx
.sat_agg
  LDX satLive-1,Y
  LDA sprCls,X                  \ under this pass's writes? SprScanCls
  AND #3                        \ answered: bit 0 window-A writers, bit 1
  STA satOld                    \ window-B. Bit 2 of sprCls[0] is the
  LDA sprComp,X                 \ view-moved flag, masked off here
  TAX
  INC satCnt,X
  LDA satFrc,X
  ORA satOld
  STA satFrc,X
  DEY
  BNE sat_agg
.sat_aggx

\ ---- hand out whole components, in slot order ------------------
\ The order and every input of the decision are what they were, so
\ every decision is: the component is met at its lowest live slot,
\ with satNA/satNB as the components before it left them.
  LDA #0
  STA satNA
  STA satNB
  STA satI
.sat_asg
  LDX satI
  CPX satN
  BCC sat_asg1
  JMP sat_done
.sat_asg1
  LDA satLive,X
  TAX
  LDA sprComp,X
  TAX                           \ the component's label
  LDA sprTr,X
  CMP #&FF
  BEQ sat_place                 \ not yet placed
  JMP sat_asgnext
.sat_place
  STX satNew
  LDA satCnt,X
  STA satCount
  LDA satFrc,X
  STA satForce

  LDA satForce                  \ under a window-A writer it MUST be in
  CMP #3                        \ tranche A (erased while the band and
  BEQ sat_refx                  \ columns paint); under a window-B one it
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
  BNE sat_refx
  BEQ sat_toB                   \ always
\ The budget block below put sat_refuse out of both branches' reach.
.sat_refx
  JMP sat_refuse
\ ---- otherwise, window A's BUDGET decides ------------------
\ [DECISION, 2026-09-09] THE TWO WINDOWS ARE NOT INTERCHANGEABLE, so
\ this is a budget and not a balance. See SprScanCls's satCapA block
\ for the arithmetic: window A pays for the pass preamble and the
\ level draw as well as its own tranche, so it holds three sprites on
\ a quiet pass, two behind a column draw and none behind a band,
\ while window B holds four. The old rule handed each component to
\ whichever tranche was emptier, which alternates A, B, A, B, A and
\ puts the majority in the window with least room.
\ THE PLAYER IS PINNED TO A EXPLICITLY, which the old rule only did
\ by accident: slot 0 is the first component looked at, so satNA and
\ satNB were both 0 and the tie went to A. With a budget that can be
\ zero the accident stops working, and the guarantee it was standing
\ in for is load-bearing -- a tranche-B image lags the scroll by one
\ field, which reads as judder on the one sprite the eye holds
\ against the screen frame (2026-09-01).
.sat_bal
  LDA sprActive+0
  BEQ sat_bnply
  LDA satNew
  CMP sprComp+0
  BEQ sat_toA                   \ the player's component, always window A
.sat_bnply
  LDA satNA                     \ does it still fit window A's budget?
  CLC
  ADC satCount
  CMP satCapA
  BCC sat_toA
  BEQ sat_toA
  LDA satNB                     \ no -- window B, if B has room for it
  CLC
  ADC satCount
  CMP #SPR_CAP_B
  BCC sat_toB
  BEQ sat_toB
  LDA satNA                     \ both over budget: the emptier one, and
  CMP satNB                     \ a tie goes to B, which is the window
  BCC sat_toA                   \ that is not also drawing the level
  BCS sat_toB                   \ always
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
  LDX satNew                    \ the component's answer, on its label
  STA sprTr,X                   \ slot; sat_done copies it to the rest
.sat_asgnext
  INC satI
  JMP sat_asg

.sat_done
  LDY satN                      \ every member takes its label's answer
  BEQ sat_ret
.sat_fill
  LDX satLive-1,Y
  LDA sprComp,X
  TAX
  LDA sprTr,X
  LDX satLive-1,Y
  STA sprTr,X
  DEY
  BNE sat_fill
.sat_ret
  LDA #1                        \ always: see the note on balance above
  RTS
.sat_refuse
  LDA #0                        \ a component under both windows' writers:
  RTS                           \ sprTr is half-written but a whole pass
                                \ never reads it

\ The overlap distances. Deliberately loose — 7 wide plus 2 units of a
\ pass's movement, and 21 scanlines plus 8 — because the test has to
\ cover where the other tranche was drawn LAST pass as well as this one.
\ (SprOverlapXY and SprAbsA, which held this test, were inlined into
\ the pair loop above on 2026-09-10 and are gone.)
SPR_OVL_U = SPR_W + 2
SPR_OVL_Y = SPR_H + 8

\ SprAssignTr's working bytes, beside it for the reason scnDoorW and its
\ neighbours are beside SprScanCls: this bank is RAM, nothing else reads
\ them, and the code image has 60 bytes left.
.satLive  SKIP SPR_SLOTS        \ the live slots, ascending
.satCnt   SKIP SPR_SLOTS        \ per label: members
.satFrc   SKIP SPR_SLOTS        \ per label: the OR of their class bits
.satN     EQUB 0                \ how many are live
.satSi    EQUB 0                \ slot I of the pair loop

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
