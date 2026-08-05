\ ============================================================
\ sprite.asm — the player droid, blitted into the play buffer
\ ============================================================
\ The C64 pins the player dead centre and scrolls the deck under
\ it, which it can do because its hardware scroll is 1 pixel. Ours
\ is 4 — the CRTC addresses in 8-byte units and a MODE 1 row is 80
\ of them, so a step is always 1/80 of the screen width, in every
\ mode. At low speed that reads as the whole world jerking 4 pixels
\ every few frames.
\
\ So the camera has a DEAD ZONE. The player moves through the world
\ at 1 pixel and the view only follows when the player pushes the
\ edge of a window around the centre. Walk slowly and the world
\ holds still while the droid glides; walk fast and the window
\ saturates and the view scrolls as before. player.asm owns that;
\ this file just draws the sprite wherever it ends up.
\
\ Two consequences here:
\
\ 1. The sprite's screen position is no longer constant, so the
\    unit and the sub-unit shift are computed every frame.
\ 2. It needs to land on 2-pixel boundaries, not 4. A 2 px shift
\    spills 24 px of sprite into SEVEN bytes, so every row is
\    stored seven wide and there are two copies of the whole sprite
\    — unshifted from the disc, shifted built at startup.
\
\ 2 px rather than 1 is not just thrift: a C64 multicolour pixel is
\ exactly two MODE 1 pixels, so the artwork has no detail finer
\ than that. 1 px would need four copies, 1820 bytes, which is more
\ than is free below &3000 until PARADAT moves to sideways RAM.
\
\ MASKS ARE NOT STORED. Every opaque pixel maps to logical colour
\ 1, 2 or 3 and never 0, so a pixel is transparent exactly when
\ both its bits are clear, and one 256-byte table recovers the mask
\ from the data. The row was being copied into a buffer anyway, so
\ deriving it there is free.
\
\ Order within a frame is load-bearing:
\   1  PlyRestore   put back the background, at the OLD address
\   2  scroll state, SetCRTCStart, DoRedraws
\   3  PlyDraw      save the new background, then blit
\ Restoring after the scroll would write the old pixels at the new
\ position; saving before it would save the wrong cells.
\
\ ADJACENT 4-PIXEL COLUMNS ARE 8 BYTES APART, not 1. Consecutive
\ bytes within a column are consecutive SCANLINES. Blitting a row
\ to seven consecutive addresses draws the sprite one column wide
\ and seven scanlines deep, which is exactly what the first build
\ did.
\ ============================================================

PLY_Y  = 50                     \ scanlines from the top of the view
PLY_BYTES = PLY_W * PLY_H       \ background save area, 147 bytes

\ A row's 7 columns span 49 bytes, so the fast path needs the whole
\ span to sit below the end of the strip.
PLY_SPAN    = (PLY_W - 1) * UNIT_BYTES
PLY_WRAPLIM = BUF_END - PLY_SPAN

\ ============================================================
\ PlyBuildTables — the shifted copy and the mask table
\ ============================================================
\ Both are constant, so they are built once at startup rather than
\ shipped. They live above the panel and below the play buffer, in
\ the ~900 bytes that were left over there.
\
\ A 2-pixel right shift in MODE 1: pixel n moves to n+2, so within a
\ byte bits (7,3)<-(5,1) and (6,2)<-(4,0), which is (b AND &CC) >> 2;
\ the pixels falling off the right reappear as the next byte's
\ pixels 0 and 1, which is (b AND &33) << 2.
ASSERT PLY_SHIFT2 + PLY_DATASIZE <= PLY_MASKTAB
ASSERT PLY_MASKTAB + 256 <= BUF_BASE
ASSERT PLY_SHIFT2 >= PANEL_ADDR + PANEL_BYTES

.PlyBuildTables
  LDA #LO(plySprData) : STA psrc
  LDA #HI(plySprData) : STA psrc+1
  LDA #LO(PLY_SHIFT2) : STA pdst
  LDA #HI(PLY_SHIFT2) : STA pdst+1
  LDA #PLY_ROWS
  STA pbtRows
.pbt_row
  LDA #0
  STA pbtCarry                  \ nothing spills into the first byte
  LDY #0
.pbt_byte
  LDA (psrc),Y
  PHA
  AND #&CC
  LSR A : LSR A
  ORA pbtCarry
  STA (pdst),Y
  PLA
  AND #&33
  ASL A : ASL A
  STA pbtCarry
  INY
  CPY #PLY_W
  BNE pbt_byte

  CLC
  LDA psrc : ADC #PLY_W : STA psrc
  BCC pbt_s1
  INC psrc+1
.pbt_s1
  CLC
  LDA pdst : ADC #PLY_W : STA pdst
  BCC pbt_s2
  INC pdst+1
.pbt_s2
  DEC pbtRows
  BNE pbt_row

\ The mask. A pixel is transparent when both of its bits are clear,
\ so fold the low nibble onto the high one to get "this pixel has
\ some colour", invert it, and spread it back across both nibbles.
  LDX #0
.pbt_mask
  TXA
  AND #&0F
  ASL A : ASL A : ASL A : ASL A
  STA mcTmp
  TXA
  ORA mcTmp                     \ high nibble: pixel is opaque
  AND #&F0
  EOR #&F0                      \ high nibble: pixel is transparent
  STA mcTmp
  LSR A : LSR A : LSR A : LSR A
  ORA mcTmp                     \ both bits of each transparent pixel
  STA PLY_MASKTAB,X
  INX
  BNE pbt_mask
  RTS

.pbtRows  EQUB 0
.pbtCarry EQUB 0

\ ============================================================
\ PlyCalcAddr — bufp = the sprite's top-left byte, plyScan = its
\ scanline within that character row
\ ============================================================
\ The sprite starts PLY_Y scanlines below the top of the view, and
\ the view starts `line` scanlines into display row 0, so the offset
\ from the top of the buffer strip is line + PLY_Y. That is at most
\ 57, and the sprite is 21 tall, so it spans strip rows 6-9 and can
\ never reach the row 15/0 wrap — which is what keeps the blit and
\ the scroll redraws structurally unable to collide.
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
  LDA plyUnit                   \ set by PlyScreenPos, not a constant now
  STA uCount
  JSR SetCell
  CLC
  LDA bufp : ADC plyScan : STA bufp
  BCC pca_x
  INC bufp+1
.pca_x
  RTS

\ ============================================================
\ PlyScreenPos — plyUnit and plyBank from the sprite's screen X
\ ============================================================
\ DeadZone has already split the sprite's screen X into plyUnit (the
\ CRTC column) and plyShift (whether the odd 2 pixels are in play);
\ all that is left is choosing which copy of the sprite to read.
.PlyScreenPos
  LDA plyShift
  BNE psp_shifted
.psp_flat
  LDA #LO(plySprData) : STA plyBank
  LDA #HI(plySprData) : STA plyBank+1
  RTS
.psp_shifted
  LDA #LO(PLY_SHIFT2) : STA plyBank
  LDA #HI(PLY_SHIFT2) : STA plyBank+1
  RTS

\ ============================================================
\ PlyNextScan — advance bufp by one scanline
\ ============================================================
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
\ PlyFetchRow — plyRowBuf = row plyRow's 7 data bytes and their
\ 7 derived masks
\ ============================================================
\ plyOfs indexes by phase*21 + row, so the 21 sprite rows map onto
\ the 65 distinct stored rows: the bottom of the rotor is the top in
\ reverse row order, the digit block is shared by every phase, and
\ the three blank rows point at one all-transparent row.
.PlyFetchRow
  LDX plyRowIdx
  CLC
  LDA plyOfsLo,X : ADC plyBank   : STA psrc
  LDA plyOfsHi,X : ADC plyBank+1 : STA psrc+1
  LDY #PLY_W-1
.pfr_loop
  LDA (psrc),Y
  STA plyRowBuf,Y
  TAX
  LDA PLY_MASKTAB,X
  STA plyRowBuf+PLY_W,Y
  DEY
  BPL pfr_loop
  RTS

\ ============================================================
\ PlyWraps — does this row's span cross the end of the strip?
\ Carry set = yes, take the slow path.
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
  JSR PlyScreenPos
  JSR PlyCalcAddr
  LDA bufp     : STA plyPtr0
  LDA bufp+1   : STA plyPtr0+1
  LDA plyScan  : STA plyScan0
  LDA #1       : STA plySaved

  LDX plyFrame
  LDA plyMulRows,X
  STA plyRowIdx                 \ phase*21; the row walk increments it
  LDA #0
  STA plyRow
  STA plySaveIdx
.pd_row
  JSR PlyFetchRow
  JSR PlyWraps
  BCS pd_slow

  LDX plySaveIdx                \ 0, 7, 14 ... 140
  LDY #0*UNIT_BYTES
  LDA (bufp),Y : STA plySave+0,X : AND plyRowBuf+7  : ORA plyRowBuf+0 : STA (bufp),Y
  LDY #1*UNIT_BYTES
  LDA (bufp),Y : STA plySave+1,X : AND plyRowBuf+8  : ORA plyRowBuf+1 : STA (bufp),Y
  LDY #2*UNIT_BYTES
  LDA (bufp),Y : STA plySave+2,X : AND plyRowBuf+9  : ORA plyRowBuf+2 : STA (bufp),Y
  LDY #3*UNIT_BYTES
  LDA (bufp),Y : STA plySave+3,X : AND plyRowBuf+10 : ORA plyRowBuf+3 : STA (bufp),Y
  LDY #4*UNIT_BYTES
  LDA (bufp),Y : STA plySave+4,X : AND plyRowBuf+11 : ORA plyRowBuf+4 : STA (bufp),Y
  LDY #5*UNIT_BYTES
  LDA (bufp),Y : STA plySave+5,X : AND plyRowBuf+12 : ORA plyRowBuf+5 : STA (bufp),Y
  LDY #6*UNIT_BYTES
  LDA (bufp),Y : STA plySave+6,X : AND plyRowBuf+13 : ORA plyRowBuf+6 : STA (bufp),Y
  JMP pd_next

\ The row straddles the end of the strip, so the seven columns are
\ not 8 bytes apart in address order any more. Two passes, because
\ each needs the index register the other is using. About one row in
\ fifty; speed does not matter, correctness does.
.pd_slow
  LDA bufp   : STA plyTmpPtr
  LDA bufp+1 : STA plyTmpPtr+1
  LDX plySaveIdx
  LDA #0 : STA plyCol
.pds_save
  LDY #0
  LDA (bufp),Y
  STA plySave,X
  INX
  JSR PlyNextUnit
  INC plyCol
  LDA plyCol
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
  INC plyRowIdx
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
  LDY #6*UNIT_BYTES : LDA plySave+6,X : STA (bufp),Y
  JMP pr_next

.pr_slow
  LDA bufp   : STA plyTmpPtr
  LDA bufp+1 : STA plyTmpPtr+1
  LDX plySaveIdx
  LDA #0 : STA plyCol
.prs_loop
  LDY #0
  LDA plySave,X
  STA (bufp),Y
  INX
  JSR PlyNextUnit
  INC plyCol
  LDA plyCol
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
.plyCol       EQUB 0
.plyRowIdx    EQUB 0
.plyBank      EQUW 0
.plyRowBuf    SKIP PLY_W * 2
.plySave      SKIP PLY_BYTES
