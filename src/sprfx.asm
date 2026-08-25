\ ============================================================
\ sprfx.asm — the effect blitter, IN BANK 5 (PARASPR)
\ ============================================================
\ Layer 7c's interpreted effect path, moved out of the &1100-&3000
\ code image (RAM pass 2). It can live here because it ONLY ever runs
\ with THIS bank paged in:
\
\   - SprSetSlot's effect arm pages SWRAM_SPR in FROM MAIN RAM and
\     then jumps to SprEfSetup below;
\   - sd_go's JMP SprEfDraw runs after that setup, same pass, and
\     nothing between them touches ROMSEL;
\   - sr_go pages SWRAM_SPR itself before SprEfBox / SprEfRestore.
\
\ Everything it READS outside this bank is main RAM or zero page —
\ sprRowBuf, SPR_MASKTAB, sprMul8, bufp/svp, and the SprNextUnit /
\ SprScanRow calls — which is the always-legal direction. The efR0..
\ efData tables it indexes are this bank's own (effects.asm above).
\
\ LOAD-BEARING INVARIANT: no effect blit may run while the briefing
\ has PARMAN in this bank. True today — the briefing runs its own
\ loop and never calls the blitter, and both exits reload PARASPR —
\ but it is now this file that makes that a rule rather than a habit.
\ The narrative for the effect FORMAT stays in sprite.asm, where the
\ droid path it shadows lives.
\ ---- SprEfSetup — SprSetSlot's tail for an effect slot -----
\ sprType holds the FRAME for an effect, where it holds the droid type
\ for a droid. Entered from SprSetSlot with X = sprSlot and THIS BANK
\ ALREADY PAGED by the caller's arm; must return with carry clear,
\ like the path it replaces.
.SprEfSetup
  LDA sprType,X
  STA sprEfFrmS,X               \ the restore needs the frame the DRAW used
  JSR SprEfBox
  CLC
  RTS

\ ---- SprEfBox — A = frame, unpack its box and data pointer -
\ Reads bank 5, so the caller must have paged it in.
.SprEfBox
  TAY
  LDA efR0,Y : STA efRow0
  LDA efH,Y  : STA efHgt
  LDA efC0,Y : STA efCol0
  LDA efW,Y  : STA efWid
  CLC
  ADC #1
  STA efWid1                    \ the data columns plus the shift's spill
  CLC
  LDA efDataLo,Y : ADC #LO(efData) : STA efSrc
  LDA efDataHi,Y : ADC #HI(efData) : STA efSrc+1
  RTS

\ ---- SprEfSkip — down efRow0 scanlines to the top of the box
\ Both passes start with it, and both must take the SAME walk, because
\ SCANSTEP moves bufp and svp together and the save area only lines up
\ with the screen if they stay in step.
.SprEfSkip
  LDX efRow0
  BEQ efs_x
.efs_loop
  SCANSTEP
  DEX
  BNE efs_loop
.efs_x
  RTS

\ ---- SprEfFetch — one row of artwork, shifted, plus its masks
\ sprRowBuf[0..efWid] is the data and sprRowBuf[SPR_W..] the masks, the
\ same layout SprFetchRow leaves for the droid path. efSrc advances a
\ row, so the rows come out in order without an index.
\
\ The shift is the same one-pixel-at-a-time pass SprFetchRow uses and
\ for the same reason — a MODE 1 pixel is bits 7-n and 3-n, so `AND
\ #&EE` down one and `&11` carried up three moves both nibbles
\ together, and the carry runs left to right into the spill byte.
.SprEfFetch
  LDY efWid
  LDA #0
  STA sprRowBuf,Y               \ the spill byte starts empty
  DEY
.eff_copy
  LDA (efSrc),Y
  STA sprRowBuf,Y
  DEY
  BPL eff_copy

  CLC                           \ on to the next row's bytes
  LDA efSrc : ADC efWid : STA efSrc
  BCC eff_nc
  INC efSrc+1
.eff_nc

  LDX sprShiftW
  BEQ eff_mask
.eff_pass
  LDA #0
  STA sfrCarry
  LDY #0
.eff_sloop
  LDA sprRowBuf,Y
  PHA
  AND #&EE
  LSR A
  ORA sfrCarry
  STA sprRowBuf,Y
  PLA
  AND #&11
  ASL A : ASL A : ASL A
  STA sfrCarry
  INY
  CPY efWid1
  BNE eff_sloop
  DEX
  BNE eff_pass

.eff_mask
  LDY efWid                     \ efWid1 bytes, so efWid down to 0
.eff_mloop
  LDA sprRowBuf,Y
  TAX
  LDA SPR_MASKTAB,X
  STA sprRowBuf+SPR_W,Y
  DEY
  BPL eff_mloop
  RTS

\ ---- SprEfDraw — save the background and blit the box ------
\ Entered after SprCalcAddr and SprSetSave, exactly where the droid
\ path starts, with bufp and svp on the sprite's top-left.
\
\ WHOLE-SPRITE WRAP DECISION, not per row. The droid path tests each
\ row because only some of a wrapping sprite's rows actually straddle
\ the end of the strip and the compiled rows cannot express a walk. The
\ walked path here is correct whether or not the row wraps, so one test
\ up front is enough; it costs a slower blit on the ~20% of sprites
\ that could wrap and saves a test on every row of the rest.
.SprEfDraw
  JSR SprEfSkip
  LDA efHgt
  STA efCount
.efd_row
  JSR SprEfFetch
  LDA sprNoWrap
  BEQ efd_slow

  LDX #0
.efd_fcol
  TXA
  CLC
  ADC efCol0
  TAY
  LDA sprMul8,Y
  TAY
  LDA (bufp),Y                  \ the background
  STA (svp),Y                   \ save it — same Y addresses both
  AND sprRowBuf+SPR_W,X
  ORA sprRowBuf,X
  STA (bufp),Y
  INX
  CPX efWid1
  BNE efd_fcol
  JMP efd_next

\ The row may straddle the end of the strip, so the columns are not
\ eight bytes apart in address order and bufp has to be walked. The
\ SAVE side never wraps, so it keeps its Y offset while the screen side
\ uses Y = 0 against a walking pointer — the same split sd_slow makes.
.efd_slow
  LDA bufp   : STA sprTmpPtr
  LDA bufp+1 : STA sprTmpPtr+1
  LDY efCol0                    \ walk across to the box's first column
  BEQ efd_s0
.efd_sskip
  JSR SprNextUnit
  DEY
  BNE efd_sskip
.efd_s0
  LDX #0
.efd_sloop
  TXA
  CLC
  ADC efCol0
  TAY
  LDA sprMul8,Y
  STA efYofs
  LDY #0
  LDA (bufp),Y
  LDY efYofs
  STA (svp),Y
  AND sprRowBuf+SPR_W,X
  ORA sprRowBuf,X
  LDY #0
  STA (bufp),Y
  JSR SprNextUnit
  INX
  CPX efWid1
  BNE efd_sloop
  LDA sprTmpPtr   : STA bufp    \ back to the row's first column
  LDA sprTmpPtr+1 : STA bufp+1

.efd_next
  DEC efCount
  BEQ efd_done
  SCANSTEP
  JMP efd_row
.efd_done
  RTS

\ ---- SprEfRestore — put the box's background back ----------
\ The mirror of SprEfDraw with the fetch and the mask gone: the saved
\ bytes go back exactly as they were taken. Walks the same box, from
\ the frame the DRAW used, so it puts back what it saved even if the
\ effect has since animated or moved.
.SprEfRestore
  JSR SprEfSkip
  LDA efHgt
  STA efCount
.efr_row
  LDA sprNoWrap
  BEQ efr_slow

  LDX #0
.efr_fcol
  TXA
  CLC
  ADC efCol0
  TAY
  LDA sprMul8,Y
  TAY
  LDA (svp),Y
  STA (bufp),Y
  INX
  CPX efWid1
  BNE efr_fcol
  JMP efr_next

.efr_slow
  LDA bufp   : STA sprTmpPtr
  LDA bufp+1 : STA sprTmpPtr+1
  LDY efCol0
  BEQ efr_s0
.efr_sskip
  JSR SprNextUnit
  DEY
  BNE efr_sskip
.efr_s0
  LDX #0
.efr_sloop
  TXA
  CLC
  ADC efCol0
  TAY
  LDA sprMul8,Y
  TAY
  LDA (svp),Y
  LDY #0
  STA (bufp),Y
  JSR SprNextUnit
  INX
  CPX efWid1
  BNE efr_sloop
  LDA sprTmpPtr   : STA bufp
  LDA sprTmpPtr+1 : STA bufp+1

.efr_next
  DEC efCount
  BEQ efr_done
  SCANSTEP
  JMP efr_row
.efr_done
  RTS
