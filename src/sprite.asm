\ ============================================================
\ sprite.asm — the player droid, blitted into the play buffer
\ ============================================================
\ The player does not move on screen. Paradroid keeps it dead
\ centre and scrolls the deck underneath, so the sprite's SCREEN
\ position is a constant and only its BUFFER address changes, as
\ scrollS and line move under it.
\
\ C64 PlayerSprite_dat ($6A2E) puts sprite 7 at VIC (172, 172),
\ which is screen (148, 122) — 148 is exactly (320-24)/2, and 122
\ centres the sprite in the C64's 136-pixel play area. 148 is a
\ multiple of 4, so the sprite lands on a CRTC unit boundary and
\ needs no shifting: PLY_XU = 37.
\
\ Vertically we have 120 visible pixels rather than 136, so the
\ sprite sits at y = 50: rows 6-9 of the strip. That matters more
\ than it looks. The sprite never touches display row 0 or row 15,
\ which are the two rows the scroll redraws write — so the blit and
\ the edge redraws can never collide, and the split row's hazard
\ (PLAN.md, Layer 3d) does not apply here.
\
\ Order within a frame is fixed and load-bearing:
\   1  PlyRestore   put back the background, at the OLD address
\   2  scroll state, SetCRTCStart, DoRedraws
\   3  PlyDraw      save the new background, then blit
\ Restoring after the scroll would write the old pixels at the new
\ position; saving before it would save the wrong cells.
\
\ ADJACENT 4-PIXEL COLUMNS ARE 8 BYTES APART, not 1. A sprite row
\ is 6 columns, so its six destination bytes are at +0, +8, ... +40
\ — consecutive bytes within a column are consecutive SCANLINES.
\ Blitting them as 6 consecutive addresses draws the sprite one
\ column wide and 6 scanlines deep, which is exactly what the first
\ build did.
\ ============================================================

PLY_XU = 37                     \ CRTC units from the left edge  (148 px)
PLY_Y  = 50                     \ scanlines from the top of the view
PLY_BYTES = PLY_W * PLY_H       \ background save area, 126 bytes

\ A row's 6 columns span 41 bytes, so the fast path needs the whole
\ span to sit below the end of the strip.
PLY_SPAN   = (PLY_W - 1) * UNIT_BYTES
PLY_WRAPLIM = BUF_END - PLY_SPAN

\ ============================================================
\ PlyCalcAddr — bufp = the sprite's top-left byte, plyScan = its
\ scanline within that character row
\ ============================================================
\ The sprite starts PLY_Y scanlines below the top of the view, and
\ the view starts `line` scanlines into display row 0, so the offset
\ from the top of the buffer strip is line + PLY_Y. That is at most
\ 57, and the sprite is 21 tall, so it spans rows 6-9 and can never
\ reach the row 15/0 wrap.
.PlyCalcAddr
  CLC
  LDA line
  ADC #PLY_Y
  TAX
  AND #7
  STA plyScan
  TXA
  LSR A : LSR A : LSR A
  STA rCount
  LDA #PLY_XU
  STA uCount
  JSR SetCell
  CLC
  LDA bufp : ADC plyScan : STA bufp
  BCC pca_x
  INC bufp+1
.pca_x
  RTS

\ ============================================================
\ PlyNextScan — advance bufp by one scanline
\ ============================================================
\ Within a character column consecutive scanlines are consecutive
\ bytes. Crossing into the next row costs 640 - 7, and can carry
\ bufp past the end of the strip.
.PlyNextScan
  LDA plyScan
  CMP #7
  BEQ pns_row
  INC plyScan
  INC bufp
  BNE pns_x
  INC bufp+1
  RTS
.pns_row
  LDA #0
  STA plyScan
  CLC
  LDA bufp   : ADC #LO(ROW_BYTES-7) : STA bufp
  LDA bufp+1 : ADC #HI(ROW_BYTES-7) : STA bufp+1
  JSR WrapBufFwd
.pns_x
  RTS

\ ============================================================
\ PlyFetchRow — plyRowBuf = the 12 bytes of sprite row plyRow
\ ============================================================
\ 6 data bytes then 6 mask bytes, copied out of the tables so the
\ blit can index them absolutely — the 6502 has one index register
\ to spare and the destination needs it.
\
\ plyRowSrc encodes which of four banks a row comes from, so that
\ the 21-row sprite is stored as 13 distinct rows plus a blank: the
\ bottom of the rotor is the top in reverse row order, and the digit
\ block is the same in all 8 phases.
.PlyFetchRow
  LDX plyRow
  LDA plyRowSrc,X
  BMI pfr_dig                   \ &80-&87
  CMP #&40
  BCS pfr_bot                   \ &40-&41
  CMP #&20
  BCS pfr_blank                 \ &20
  TAX                           \ &00-&04: the current phase's ring
  LDA plyMulRow,X
  CLC
  ADC plyRingBase   : STA psrc
  LDA plyRingBase+1 : ADC #0 : STA psrc+1
  JMP pfr_copy
.pfr_bot
  AND #1
  TAX
  LDA plyMulRow,X
  CLC
  ADC plyBotBase   : STA psrc
  LDA plyBotBase+1 : ADC #0 : STA psrc+1
  JMP pfr_copy
.pfr_dig
  AND #7
  TAX
  LDA plyMulRow,X
  CLC
  ADC #LO(plyDigits) : STA psrc
  LDA #HI(plyDigits) : ADC #0 : STA psrc+1
  JMP pfr_copy
.pfr_blank
  LDA #LO(plyBlank) : STA psrc
  LDA #HI(plyBlank) : STA psrc+1
.pfr_copy
  LDY #PLY_ROWBYTES-1
.pfr_loop
  LDA (psrc),Y
  STA plyRowBuf,Y
  DEY
  BPL pfr_loop
  RTS

\ ============================================================
\ PlyWraps — does this row's 41-byte span cross the end of the
\ strip?  Carry set = yes, take the slow path.
\ ============================================================
.PlyWraps
  LDA bufp+1
  CMP #HI(PLY_WRAPLIM)
  BCC pw_no
  BNE pw_yes
  LDA bufp
  CMP #LO(PLY_WRAPLIM)
  BCS pw_yes
.pw_no
  CLC
  RTS
.pw_yes
  SEC
  RTS

\ ============================================================
\ PlyDraw — save the background, then blit the sprite over it
\ ============================================================
\ The starting address and scanline are kept so PlyRestore can walk
\ exactly the same path next frame. Replaying the walk is cheaper
\ and less error-prone than storing 21 addresses, and it cannot
\ drift: the row-crossing pattern depends only on the starting
\ scanline, which is saved with it.
.PlyDraw
  LDX plyFrame                  \ phase bases, once per blit
  LDA plyRingLo,X : STA plyRingBase
  LDA plyRingHi,X : STA plyRingBase+1
  LDA plyBotLo,X  : STA plyBotBase
  LDA plyBotHi,X  : STA plyBotBase+1

  JSR PlyCalcAddr
  LDA bufp     : STA plyPtr0
  LDA bufp+1   : STA plyPtr0+1
  LDA plyScan  : STA plyScan0
  LDA #1       : STA plySaved

  LDA #0
  STA plyRow
  STA plySaveIdx
.pd_row
  JSR PlyFetchRow
  JSR PlyWraps
  BCS pd_slow

  LDX plySaveIdx                \ 0, 6, 12 ... 120
  LDY #0*UNIT_BYTES
  LDA (bufp),Y : STA plySave+0,X : AND plyRowBuf+6 : ORA plyRowBuf+0 : STA (bufp),Y
  LDY #1*UNIT_BYTES
  LDA (bufp),Y : STA plySave+1,X : AND plyRowBuf+7 : ORA plyRowBuf+1 : STA (bufp),Y
  LDY #2*UNIT_BYTES
  LDA (bufp),Y : STA plySave+2,X : AND plyRowBuf+8 : ORA plyRowBuf+2 : STA (bufp),Y
  LDY #3*UNIT_BYTES
  LDA (bufp),Y : STA plySave+3,X : AND plyRowBuf+9 : ORA plyRowBuf+3 : STA (bufp),Y
  LDY #4*UNIT_BYTES
  LDA (bufp),Y : STA plySave+4,X : AND plyRowBuf+10 : ORA plyRowBuf+4 : STA (bufp),Y
  LDY #5*UNIT_BYTES
  LDA (bufp),Y : STA plySave+5,X : AND plyRowBuf+11 : ORA plyRowBuf+5 : STA (bufp),Y
  JMP pd_next

\ The row straddles the end of the strip, so the six columns are not
\ 8 bytes apart in address order any more. Two passes, because each
\ needs the index register the other is using. About one row in
\ fifty; speed does not matter, correctness does.
.pd_slow
  LDA bufp   : STA plyTmpPtr
  LDA bufp+1 : STA plyTmpPtr+1
  LDX plySaveIdx
  LDA #0 : STA plyUnit
.pds_save
  LDY #0
  LDA (bufp),Y
  STA plySave,X
  INX
  JSR PlyNextUnit
  INC plyUnit
  LDA plyUnit
  CMP #PLY_W
  BNE pds_save

  LDA plyTmpPtr   : STA bufp
  LDA plyTmpPtr+1 : STA bufp+1
  LDX #0
.pds_blit
  LDY #0
  LDA (bufp),Y
  AND plyRowBuf+PLY_W,X
  ORA plyRowBuf,X
  STA (bufp),Y
  JSR PlyNextUnit
  INX
  CPX #PLY_W
  BNE pds_blit
  LDA plyTmpPtr   : STA bufp
  LDA plyTmpPtr+1 : STA bufp+1

.pd_next
  CLC
  LDA plySaveIdx : ADC #PLY_W : STA plySaveIdx
  JSR PlyNextScan
  INC plyRow
  LDA plyRow
  CMP #PLY_H
  BEQ pd_done
  JMP pd_row
.pd_done
  RTS

\ ============================================================
\ PlyNextUnit — bufp on to the next 4-pixel column, wrapping
\ ============================================================
.PlyNextUnit
  CLC
  LDA bufp : ADC #UNIT_BYTES : STA bufp
  BCC pnu_nc
  INC bufp+1
.pnu_nc
  JMP WrapBufFwd

\ ============================================================
\ PlyRestore — put the saved background back
\ ============================================================
.PlyRestore
  LDA plySaved
  BNE pr_go
  RTS
.pr_go
  LDA plyPtr0   : STA bufp
  LDA plyPtr0+1 : STA bufp+1
  LDA plyScan0  : STA plyScan
  LDA #0
  STA plyRow
  STA plySaveIdx
.pr_row
  JSR PlyWraps
  BCS pr_slow

  LDX plySaveIdx
  LDY #0*UNIT_BYTES : LDA plySave+0,X : STA (bufp),Y
  LDY #1*UNIT_BYTES : LDA plySave+1,X : STA (bufp),Y
  LDY #2*UNIT_BYTES : LDA plySave+2,X : STA (bufp),Y
  LDY #3*UNIT_BYTES : LDA plySave+3,X : STA (bufp),Y
  LDY #4*UNIT_BYTES : LDA plySave+4,X : STA (bufp),Y
  LDY #5*UNIT_BYTES : LDA plySave+5,X : STA (bufp),Y
  JMP pr_next

.pr_slow
  LDA bufp   : STA plyTmpPtr
  LDA bufp+1 : STA plyTmpPtr+1
  LDX plySaveIdx
  LDA #0 : STA plyUnit
.prs_loop
  LDY #0
  LDA plySave,X
  STA (bufp),Y
  INX
  JSR PlyNextUnit
  INC plyUnit
  LDA plyUnit
  CMP #PLY_W
  BNE prs_loop
  LDA plyTmpPtr   : STA bufp
  LDA plyTmpPtr+1 : STA bufp+1

.pr_next
  CLC
  LDA plySaveIdx : ADC #PLY_W : STA plySaveIdx
  JSR PlyNextScan
  INC plyRow
  LDA plyRow
  CMP #PLY_H
  BEQ pr_x
  JMP pr_row
.pr_x
  RTS

\ ============================================================
\ PlyAnimate — step the rotor
\ ============================================================
\ The C64 spins a droid faster the healthier it is: AnimateDroids
\ reloads a countdown with (64 - energy) >> 3, so a full-energy
\ droid advances a phase every frame and a dying one every 8. With
\ no energy model yet the player runs at full health.
.PlyAnimate
  LDA plyDelay
  BEQ pa_step
  DEC plyDelay
  RTS
.pa_step
  LDA #PLY_SPIN
  STA plyDelay
  LDA plyFrame
  CLC
  ADC #1
  AND #7
  STA plyFrame
  RTS

PLY_SPIN = 0                    \ frames between phases; full energy = 0

.plyPtr0      EQUW 0            \ where PlyDraw started, for PlyRestore
.plyTmpPtr    EQUW 0
.plyScan0     EQUB 0
.plySaved     EQUB 0            \ 0 until the first PlyDraw
.plyFrame     EQUB 0
.plyDelay     EQUB 0
.plySaveIdx   EQUB 0
.plyUnit      EQUB 0
.plyRingBase  EQUW 0
.plyBotBase   EQUW 0
.plyRowBuf    SKIP PLY_ROWBYTES
.plySave      SKIP PLY_BYTES
