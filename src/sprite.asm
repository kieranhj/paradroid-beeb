\ ============================================================
\ sprite.asm — droid sprites blitted into the play buffer
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
\ edge of a window around the centre. player.asm owns that; this
\ file just draws sprites wherever they end up.
\
\ Every droid uses the same code. Slot 0 is the player; slots 1 up
\ are enemy droids, which is the C64's arrangement too — it has one
\ hardware sprite for the player and a pool of six for everything
\ else. Slots here are a software pool of the same shape, so the
\ same "no free slot" cases arise and the same rules apply.
\
\ Sprites land on 2-pixel boundaries, not 4. A 2 px shift spills
\ 24 px of sprite into SEVEN bytes, so every row is stored seven
\ wide and there are two whole copies of the artwork, unshifted and
\ shifted. Both ship in sideways RAM and are indexed by the same
\ offsets, so choosing between them is choosing a base address.
\
\ 2 px rather than 1 is not just thrift: a C64 multicolour pixel is
\ exactly two MODE 1 pixels, so the artwork has no detail finer
\ than that. 1 px would need four copies.
\
\ MASKS ARE NOT STORED. Every opaque pixel maps to logical colour
\ 1, 2 or 3 and never 0, so a pixel is transparent exactly when
\ both its bits are clear, and one 256-byte table recovers the mask
\ from the data. The row was being copied into a buffer anyway, so
\ deriving it there is free.
\
\ Order within a frame is load-bearing:
\   1  SprRestoreAll   put every slot's background back, OLD address
\   2  scroll state, SetCRTCStart, DoRedraws
\   3  SprDrawAll      save the new background, then blit
\ All slots restore before any draws. Two sprites may overlap, and
\ restoring one after another had already saved the same cells would
\ write stale pixels into the second one's save area.
\
\ ADJACENT 4-PIXEL COLUMNS ARE 8 BYTES APART, not 1. Consecutive
\ bytes within a column are consecutive SCANLINES. Blitting a row
\ to seven consecutive addresses draws the sprite one column wide
\ and seven scanlines deep, which is exactly what the first build
\ did.
\ ============================================================

SPR_SLOTS = 7                   \ slot 0 = player, 1-6 = the droid pool
SPR_W     = 7                   \ 24 px, plus one byte for the 2 px shift
SPR_H     = 21                  \ scanlines
SPR_BYTES = SPR_W * SPR_H       \ 147 bytes of background per slot

\ Not derived from droids.asm's DR_W/DR_H: beebasm resolves constant
\ assignments in file order and the data is included after the code,
\ so they are declared here and checked against the generated file
\ down there instead.

\ Save areas are a page apart rather than packed into 147 bytes, so
\ a slot's base differs only in its high byte and the blit's seven
\ absolute addresses can be retargeted by poking seven bytes. Packed
\ bases would need a 16-bit multiply per slot and a slower inner
\ loop. 7 pages against 147*7 = 1029 bytes costs 763 bytes, out of
\ the 5.8K that moving PARADAT to sideways RAM released.
SPR_SAVE  = &3000
ASSERT (SPR_SAVE AND &FF) == 0
ASSERT SPR_SAVE + SPR_SLOTS * 256 <= PANEL_ADDR

\ A row's 7 columns span 49 bytes, so the fast path needs the whole
\ span to sit below the end of the strip.
SPR_SPAN    = (SPR_W - 1) * UNIT_BYTES
SPR_WRAPLIM = BUF_END - SPR_SPAN

\ Fully on screen means every column and every scanline lands in the
\ play area. Anything else is culled rather than clipped for now, so
\ a droid pops in and out at the edges — see the note by SprSetSlot.
SPR_MAX_UNIT = PLAY_UNITS - SPR_W       \ 80 - 7 = 73
SPR_MAX_Y    = PLAY_VIS_ROWS * 8 - SPR_H \ 120 - 21 = 99

\ ============================================================
\ SprBuildMask — data byte to transparency mask
\ ============================================================
\ Only the mask is built at run time now; the shifted artwork is
\ shipped. A MODE 1 byte holds four pixels, each as a high bit in
\ the top nibble and a low bit in the bottom. A pixel is transparent
\ when BOTH are clear, so fold the low nibble onto the high, invert,
\ and spread the answer back across both nibbles: AND with that and
\ the opaque pixels are cleared ready for the sprite to be ORed in.
ASSERT SPR_MASKTAB + 256 <= BUF_BASE

\ ============================================================
\ SprBuildShift — the 2 px shifted copy of every stored row
\ ============================================================
\ A 2-pixel right shift in MODE 1: pixel n moves to n+2, so within a
\ byte bits (7,3)<-(5,1) and (6,2)<-(4,0), which is (b AND &CC) >> 2;
\ the pixels falling off the right reappear as the next byte's pixels
\ 0 and 1, which is (b AND &33) << 2. The seventh byte of every row
\ is empty in the source precisely so the spill has somewhere to go,
\ and the carry is cleared at the start of each row so one row never
\ bleeds into the next.
\
\ Source and destination are both in the bank, which is already
\ paged in by the time this runs.
.SprBuildShift
  LDA #LO(drSprData)  : STA psrc
  LDA #HI(drSprData)  : STA psrc+1
  LDA #LO(SPR_SHIFT2) : STA swDst         \ borrowed: PageDataIn has finished
  LDA #HI(SPR_SHIFT2) : STA swDst+1       \ with it, and it is in zero page
  LDA #LO(DR_ROWS) : STA sbsRows
  LDA #HI(DR_ROWS) : STA sbsRows+1
.sbs_row
  LDA #0
  STA sbsCarry
  LDY #0
.sbs_byte
  LDA (psrc),Y
  PHA
  AND #&CC
  LSR A : LSR A
  ORA sbsCarry
  STA (swDst),Y
  PLA
  AND #&33
  ASL A : ASL A
  STA sbsCarry
  INY
  CPY #SPR_W
  BNE sbs_byte

  CLC
  LDA psrc     : ADC #SPR_W : STA psrc
  BCC sbs_p
  INC psrc+1
.sbs_p
  CLC
  LDA swDst    : ADC #SPR_W : STA swDst
  BCC sbs_d
  INC swDst+1
.sbs_d
  LDA sbsRows
  BNE sbs_dec
  DEC sbsRows+1
.sbs_dec
  DEC sbsRows
  LDA sbsRows
  ORA sbsRows+1
  BNE sbs_row
  RTS

.sbsRows  EQUW 0
.sbsCarry EQUB 0

.SprBuildMask
  LDX #0
.sbm_loop
  TXA
  LSR A : LSR A : LSR A : LSR A \ low nibble up to meet the high
  STA mcTmp
  TXA
  ORA mcTmp                     \ a set bit = this pixel has some colour
  AND #&0F
  EOR #&0F                      \ now a set bit = transparent
  STA mcTmp
  ASL A : ASL A : ASL A : ASL A
  ORA mcTmp                     \ same nibble top and bottom
  STA SPR_MASKTAB,X
  INX
  BNE sbm_loop
  RTS

\ ============================================================
\ SprSetSlot — point the blitter at slot X
\ ============================================================
\ Loads the per-slot state into the working variables and retargets
\ the seven save addresses in both the draw and restore fast paths.
\ Carry set on return means the slot is not drawable this frame.
\
\ CULLED, NOT CLIPPED. A sprite whose 7 columns or 21 scanlines do
\ not all fall inside the play area is skipped entirely, so droids
\ appear and disappear a sprite's width from the edge. The C64's
\ hardware sprites clip properly; ours will need the slow path
\ taught a column range and a row range to match. Deliberate for
\ this layer — it keeps the fast path exactly as fast while the
\ per-sprite cost is being measured.
.SprSetSlot
  STX sprSlot
  LDA sprActive,X
  BNE sss_live
.sss_no
  SEC
  RTS
.sss_live
  LDA sprUnit,X
  CMP #SPR_MAX_UNIT + 1
  BCS sss_no                    \ off the left or right (unsigned: also
                                \ catches the wrapped negative case)
  STA uCount
  LDA sprScrY,X
  CMP #SPR_MAX_Y + 1
  BCS sss_no                    \ off the top or bottom
  STA sprY

  LDA #HI(SPR_SAVE)             \ slot N's save page
  CLC
  ADC sprSlot
  STA sd_s0+2 : STA sd_s1+2 : STA sd_s2+2 : STA sd_s3+2
  STA sd_s4+2 : STA sd_s5+2 : STA sd_s6+2
  STA sr_s0+2 : STA sr_s1+2 : STA sr_s2+2 : STA sr_s3+2
  STA sr_s4+2 : STA sr_s5+2 : STA sr_s6+2
  STA sslow+2                   \ the slow path's single indexed access

  LDX sprSlot                   \ which artwork, and which of the two copies
  LDA sprShift,X
  BEQ sss_flat
  LDA #LO(SPR_SHIFT2) : STA sprBank
  LDA #HI(SPR_SHIFT2) : STA sprBank+1
  JMP sss_digits
.sss_flat
  LDA #LO(drSprData) : STA sprBank
  LDA #HI(drSprData) : STA sprBank+1
.sss_digits
  LDY sprType,X                 \ where this type's number block lives
  CLC
  LDA drDigitLo,Y : ADC sprBank   : STA sprDigit
  LDA drDigitHi,Y : ADC sprBank+1 : STA sprDigit+1
  CLC
  RTS

\ ============================================================
\ SprCalcAddr — bufp = the sprite's top-left byte, sprScan = its
\ scanline within that character row
\ ============================================================
\ The sprite starts sprY scanlines below the top of the view and the
\ view starts `line` scanlines into display row 0, so the offset from
\ the top of the strip is line + sprY. Culling keeps sprY <= 99, and
\ line <= 7, so the last scanline is at most 99 + 7 + 20 = 126 — one
\ short of the 128-scanline strip, so a sprite can never wrap the
\ row 15/0 boundary. That is what keeps the blit and the scroll
\ redraws from colliding, and it is why the cull limit is a limit
\ rather than a nicety.
.SprCalcAddr
  CLC
  LDA line
  ADC sprY
  TAX
  AND #7
  STA sprScan
  TXA
  LSR A : LSR A : LSR A
  STA rCount
  JSR SetCell                   \ uCount was set by SprSetSlot
  CLC
  LDA bufp : ADC sprScan : STA bufp
  BCC sca_x
  INC bufp+1
.sca_x
  RTS

\ ============================================================
\ SprNextScan — advance bufp by one scanline
\ ============================================================
.SprNextScan
  LDA sprScan
  CMP #7
  BEQ sns_row
  INC sprScan
  INC bufp
  BNE sns_x
  INC bufp+1
  RTS
.sns_row
  LDA #0
  STA sprScan
  CLC
  LDA bufp   : ADC #LO(ROW_BYTES-7) : STA bufp
  LDA bufp+1 : ADC #HI(ROW_BYTES-7) : STA bufp+1
  JSR WrapBufFwd
.sns_x
  RTS

\ ============================================================
\ SprNextUnit — bufp on to the next 4-pixel column, wrapping
\ ============================================================
.SprNextUnit
  CLC
  LDA bufp : ADC #UNIT_BYTES : STA bufp
  BCC snu_nc
  INC bufp+1
.snu_nc
  JMP WrapBufFwd

\ ============================================================
\ SprFetchRow — sprRowBuf = this row's 7 data bytes and their masks
\ ============================================================
\ Rows 6-13 are the droid's number and depend on its TYPE; every
\ other row is rotor or blank and depends on the PHASE. One table
\ indexed by both would be 24 types x 8 phases x 21 rows, so there
\ are two, and this is where they meet.
.SprFetchRow
  LDA sprRow
  CMP #DR_DIGIT0
  BCC sfr_phase
  CMP #DR_DIGIT0 + DR_DIGITN
  BCS sfr_phase
  SEC                           \ digit row: sprDigit + (row-6)*7
  SBC #DR_DIGIT0
  TAY
  CLC
  LDA sprMul7,Y : ADC sprDigit   : STA psrc
  LDA #0        : ADC sprDigit+1 : STA psrc+1
  JMP sfr_copy
.sfr_phase
  LDX sprRowIdx
  CLC
  LDA drOfsLo,X : ADC sprBank   : STA psrc
  LDA drOfsHi,X : ADC sprBank+1 : STA psrc+1
.sfr_copy
  LDY #SPR_W-1
.sfr_loop
  LDA (psrc),Y
  STA sprRowBuf,Y
  TAX
  LDA SPR_MASKTAB,X
  STA sprRowBuf+SPR_W,Y
  DEY
  BPL sfr_loop
  RTS

.sprMul7 EQUB 0,7,14,21,28,35,42,49

\ ============================================================
\ SprWraps — does this row's span cross the end of the strip?
\ Carry set = yes, take the slow path.
\ ============================================================
.SprWraps
  LDA bufp+1
  CMP #HI(SPR_WRAPLIM)
  BCC spw_no
  BNE spw_yes
  LDA bufp
  CMP #LO(SPR_WRAPLIM)
  BCS spw_yes
.spw_no
  CLC
  RTS
.spw_yes
  SEC
  RTS

\ ============================================================
\ SprDrawAll / SprRestoreAll — every slot, in order
\ ============================================================
\ Restore walks slots backwards and draw walks forwards, so where
\ two sprites overlap the one drawn last is the one restored first
\ and the background comes back in the order it was covered.
.SprRestoreAll
  LDX #SPR_SLOTS-1
.sra_loop
  STX sprIter
  JSR SprRestoreSlot
  LDX sprIter
  DEX
  BPL sra_loop
  RTS

.SprDrawAll
  LDX #0
.sda_loop
  STX sprIter
  JSR SprDrawSlot
  LDX sprIter
  INX
  CPX #SPR_SLOTS
  BNE sda_loop
  RTS

\ ============================================================
\ SprDrawSlot — save the background for slot X, then blit over it
\ ============================================================
\ The starting address and scanline are kept so SprRestoreSlot can
\ walk exactly the same path next frame. Replaying the walk is
\ cheaper and less error-prone than storing 21 addresses, and it
\ cannot drift: the row-crossing pattern depends only on the
\ starting scanline, which is saved with it.
.SprDrawSlot
  JSR SprSetSlot
  BCC sd_go
  LDX sprSlot                   \ culled: make sure the stale background
  LDA #0                        \ is not put back somewhere it never came
  STA sprSaved,X                \ from
  RTS
.sd_go
  JSR SprCalcAddr
  LDX sprSlot
  LDA bufp    : STA sprPtr0Lo,X
  LDA bufp+1  : STA sprPtr0Hi,X
  LDA sprScan : STA sprScan0,X
  LDA #1      : STA sprSaved,X

  LDA sprFrame,X                \ phase*21, the row walk increments it
  TAY
  LDA drMulRows,Y
  STA sprRowIdx
  LDA #0
  STA sprRow
  STA sprSaveIdx
.sd_row
  JSR SprFetchRow
  JSR SprWraps
  BCS sd_slow

  LDX sprSaveIdx                \ 0, 7, 14 ... 140
  LDY #0*UNIT_BYTES
  LDA (bufp),Y
.sd_s0
  STA SPR_SAVE+0,X
  AND sprRowBuf+7  : ORA sprRowBuf+0 : STA (bufp),Y
  LDY #1*UNIT_BYTES
  LDA (bufp),Y
.sd_s1
  STA SPR_SAVE+1,X
  AND sprRowBuf+8  : ORA sprRowBuf+1 : STA (bufp),Y
  LDY #2*UNIT_BYTES
  LDA (bufp),Y
.sd_s2
  STA SPR_SAVE+2,X
  AND sprRowBuf+9  : ORA sprRowBuf+2 : STA (bufp),Y
  LDY #3*UNIT_BYTES
  LDA (bufp),Y
.sd_s3
  STA SPR_SAVE+3,X
  AND sprRowBuf+10 : ORA sprRowBuf+3 : STA (bufp),Y
  LDY #4*UNIT_BYTES
  LDA (bufp),Y
.sd_s4
  STA SPR_SAVE+4,X
  AND sprRowBuf+11 : ORA sprRowBuf+4 : STA (bufp),Y
  LDY #5*UNIT_BYTES
  LDA (bufp),Y
.sd_s5
  STA SPR_SAVE+5,X
  AND sprRowBuf+12 : ORA sprRowBuf+5 : STA (bufp),Y
  LDY #6*UNIT_BYTES
  LDA (bufp),Y
.sd_s6
  STA SPR_SAVE+6,X
  AND sprRowBuf+13 : ORA sprRowBuf+6 : STA (bufp),Y
  JMP sd_next

\ The row straddles the end of the strip, so the seven columns are
\ not 8 bytes apart in address order any more. Two passes, because
\ each needs the index register the other is using. About one row in
\ fifty; speed does not matter, correctness does.
.sd_slow
  LDA bufp   : STA sprTmpPtr
  LDA bufp+1 : STA sprTmpPtr+1
  LDX sprSaveIdx
  LDA #0 : STA sprCol
.sds_save
  LDY #0
  LDA (bufp),Y
.sslow
  STA SPR_SAVE,X
  INX
  JSR SprNextUnit
  INC sprCol
  LDA sprCol
  CMP #SPR_W
  BNE sds_save

  LDA sprTmpPtr   : STA bufp
  LDA sprTmpPtr+1 : STA bufp+1
  LDX #0
.sds_blit
  LDY #0
  LDA (bufp),Y
  AND sprRowBuf+SPR_W,X
  ORA sprRowBuf,X
  STA (bufp),Y
  JSR SprNextUnit
  INX
  CPX #SPR_W
  BNE sds_blit
  LDA sprTmpPtr   : STA bufp
  LDA sprTmpPtr+1 : STA bufp+1

.sd_next
  CLC
  LDA sprSaveIdx : ADC #SPR_W : STA sprSaveIdx
  INC sprRowIdx
  JSR SprNextScan
  INC sprRow
  LDA sprRow
  CMP #SPR_H
  BEQ sd_done
  JMP sd_row
.sd_done
  RTS

\ ============================================================
\ SprRestoreSlot — put slot X's saved background back
\ ============================================================
\ Uses the slot's OWN saved pointer, not a recomputed one: by the
\ time this runs the sprite may have moved, and the pixels belong
\ where they were taken from.
.SprRestoreSlot
  LDA sprSaved,X
  BNE sr_go
  RTS
.sr_go
  STX sprSlot
  LDA #HI(SPR_SAVE)
  CLC
  ADC sprSlot
  STA sr_s0+2 : STA sr_s1+2 : STA sr_s2+2 : STA sr_s3+2
  STA sr_s4+2 : STA sr_s5+2 : STA sr_s6+2
  STA srslow+2

  LDA sprPtr0Lo,X : STA bufp
  LDA sprPtr0Hi,X : STA bufp+1
  LDA sprScan0,X  : STA sprScan
  LDA #0
  STA sprRow
  STA sprSaveIdx
.sr_row
  JSR SprWraps
  BCS sr_slow

  LDX sprSaveIdx
  LDY #0*UNIT_BYTES
.sr_s0
  LDA SPR_SAVE+0,X
  STA (bufp),Y
  LDY #1*UNIT_BYTES
.sr_s1
  LDA SPR_SAVE+1,X
  STA (bufp),Y
  LDY #2*UNIT_BYTES
.sr_s2
  LDA SPR_SAVE+2,X
  STA (bufp),Y
  LDY #3*UNIT_BYTES
.sr_s3
  LDA SPR_SAVE+3,X
  STA (bufp),Y
  LDY #4*UNIT_BYTES
.sr_s4
  LDA SPR_SAVE+4,X
  STA (bufp),Y
  LDY #5*UNIT_BYTES
.sr_s5
  LDA SPR_SAVE+5,X
  STA (bufp),Y
  LDY #6*UNIT_BYTES
.sr_s6
  LDA SPR_SAVE+6,X
  STA (bufp),Y
  JMP sr_next

.sr_slow
  LDA bufp   : STA sprTmpPtr
  LDA bufp+1 : STA sprTmpPtr+1
  LDX sprSaveIdx
  LDA #0 : STA sprCol
.srs_loop
  LDY #0
.srslow
  LDA SPR_SAVE,X
  STA (bufp),Y
  INX
  JSR SprNextUnit
  INC sprCol
  LDA sprCol
  CMP #SPR_W
  BNE srs_loop
  LDA sprTmpPtr   : STA bufp
  LDA sprTmpPtr+1 : STA bufp+1

.sr_next
  CLC
  LDA sprSaveIdx : ADC #SPR_W : STA sprSaveIdx
  JSR SprNextScan
  INC sprRow
  LDA sprRow
  CMP #SPR_H
  BEQ sr_x
  JMP sr_row
.sr_x
  RTS

\ ============================================================
\ SprAnimateAll — step every live rotor
\ ============================================================
\ The C64 spins a droid faster the healthier it is: AnimateDroids
\ reloads a countdown with (64 - energy) >> 3, so a full-energy
\ droid advances a phase every frame and a dying one every 8. With
\ no energy model yet everything runs at full health.
.SprAnimateAll
  LDX #SPR_SLOTS-1
.saa_loop
  LDA sprActive,X
  BEQ saa_next
  LDA sprDelay,X
  BEQ saa_step
  DEC sprDelay,X
  JMP saa_next
.saa_step
  LDA #SPR_SPIN
  STA sprDelay,X
  LDA sprFrame,X
  CLC
  ADC #1
  AND #7
  STA sprFrame,X
.saa_next
  DEX
  BPL saa_loop
  RTS

SPR_SPIN = 0                    \ frames between phases; full energy = 0

\ ============================================================
\ SprInit — clear the pool and put the player in slot 0
\ ============================================================
.SprInit
  LDX #SPR_SLOTS-1
  LDA #0
.si_loop
  STA sprActive,X
  STA sprSaved,X
  STA sprFrame,X
  STA sprDelay,X
  STA sprType,X
  STA sprShift,X
  DEX
  BPL si_loop

  LDA #1 : STA sprActive+PLY_SLOT
  LDA #0 : STA sprType+PLY_SLOT   \ droid 001
  LDA #PLY_Y : STA sprScrY+PLY_SLOT
  RTS

\ ---- per-slot state ----------------------------------------
.sprActive  SKIP SPR_SLOTS      \ 0 = slot free
.sprType    SKIP SPR_SLOTS      \ droid type 0-23, picks the number block
.sprUnit    SKIP SPR_SLOTS      \ CRTC column 0-79
.sprShift   SKIP SPR_SLOTS      \ 0 = flat copy, 1 = shifted 2 px
.sprScrY    SKIP SPR_SLOTS      \ scanlines below the top of the view
.sprFrame   SKIP SPR_SLOTS      \ rotor phase 0-7
.sprDelay   SKIP SPR_SLOTS
.sprSaved   SKIP SPR_SLOTS      \ 0 until the slot has been drawn once
.sprPtr0Lo  SKIP SPR_SLOTS      \ where the last draw started
.sprPtr0Hi  SKIP SPR_SLOTS
.sprScan0   SKIP SPR_SLOTS

\ ---- working, one sprite at a time --------------------------
.sprSlot    EQUB 0
.sprIter    EQUB 0
.sprY       EQUB 0
.sprTmpPtr  EQUW 0
.sprSaveIdx EQUB 0
.sprCol     EQUB 0
.sprRowIdx  EQUB 0
.sprBank    EQUW 0
.sprDigit   EQUW 0
.sprRowBuf  SKIP SPR_W * 2
