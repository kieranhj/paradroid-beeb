\ ============================================================
\ scroll.asm — move the CRTC start and fill in what appeared
\ ============================================================
\ Horizontal steps are one CRTC unit (8 bytes = 4 px) and expose
\ one 4-pixel column: 16 cells. Vertical steps are one character
\ row (640 bytes = 8 px) and expose one row: 80 cells.
\ ============================================================

\ ---- offset tables -----------------------------------------
\ SetCell used to add 640 in a loop, which for DrawRow meant a
\ constant 15 iterations x 80 cells — about 1200 redundant 16-bit
\ adds per vertical step, and the reason vertical scrolling
\ overran the frame. Both offsets are now table lookups.
.rowMulLo
  FOR n, 0, PLAY_ROWS-1
    EQUB LO(n * ROW_BYTES)
  NEXT
.rowMulHi
  FOR n, 0, PLAY_ROWS-1
    EQUB HI(n * ROW_BYTES)
  NEXT
.unitMulLo
  FOR n, 0, PLAY_UNITS-1
    EQUB LO(n * UNIT_BYTES)
  NEXT
.unitMulHi
  FOR n, 0, PLAY_UNITS-1
    EQUB HI(n * UNIT_BYTES)
  NEXT

\ ---- helpers -----------------------------------------------
\ Add/subtract from scrollS, keeping it in [0, BUF_SIZE).
MACRO SCROLL_ADD val
  CLC
  LDA scrollS   : ADC #LO(val) : STA scrollS
  LDA scrollS+1 : ADC #HI(val) : STA scrollS+1
  LDA scrollS+1
  CMP #HI(BUF_SIZE)
  BCC skip
  BNE do
  LDA scrollS
  CMP #LO(BUF_SIZE)
  BCC skip
.do
  SEC
  LDA scrollS   : SBC #LO(BUF_SIZE) : STA scrollS
  LDA scrollS+1 : SBC #HI(BUF_SIZE) : STA scrollS+1
.skip
ENDMACRO

MACRO SCROLL_SUB val
  SEC
  LDA scrollS   : SBC #LO(val) : STA scrollS
  LDA scrollS+1 : SBC #HI(val) : STA scrollS+1
  BCS skip
  CLC
  LDA scrollS   : ADC #LO(BUF_SIZE) : STA scrollS
  LDA scrollS+1 : ADC #HI(BUF_SIZE) : STA scrollS+1
.skip
ENDMACRO

\ ============================================================
\ SetCell — point bufp at display cell (rCount, uCount)
\   bufp = BUF_BASE + ((scrollS + rCount*640 + uCount*8) MOD SIZE)
\ ============================================================
.SetCell
  LDX rCount                    \ scrollS + rCount*640, from a table
  CLC
  LDA scrollS   : ADC rowMulLo,X : STA bufp
  LDA scrollS+1 : ADC rowMulHi,X : STA bufp+1

  LDX uCount                    \ + uCount*8, likewise
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
  CLC                           \ + BUF_BASE
  LDA bufp   : ADC #LO(BUF_BASE) : STA bufp
  LDA bufp+1 : ADC #HI(BUF_BASE) : STA bufp+1
  RTS

\ ============================================================
\ DrawColumn — redraw one 4-pixel column, all 16 rows
\   uCount = the column
\ ============================================================
.DrawColumn
  LDA #0 : STA rCount
.dc_loop
  JSR SetCell

  CLC                           \ halfX = mapHX + uCount
  LDA mapHX   : ADC uCount : STA halfX
  LDA mapHX+1 : ADC #0     : STA halfX+1
  CLC                           \ cellY = mapYr + rCount
  LDA mapYr : ADC rCount : STA cellY
  JSR DrawHalf

  INC rCount
  LDA rCount
  CMP #PLAY_ROWS
  BNE dc_loop

\ Display row 0 is the SPLIT row: scanlines line..7 are the top of
\ the view and belong to map row mapYr, which the loop above just
\ wrote — but scanlines 0..line-1 belong to map row mapYr+16 and
\ have just been clobbered. They are invisible now, so the damage
\ does not show until `line` wraps and this row rotates round to the
\ bottom of the window. That is the mess a diagonal scroll leaves.
  LDA line
  BEQ dc_done
  STA scanY
  LDA #0
  STA rCount
  JSR SetCell                   \ back to display row 0, same column
  CLC
  LDA mapHX   : ADC uCount : STA halfX
  LDA mapHX+1 : ADC #0     : STA halfX+1
  CLC
  LDA mapYr : ADC #PLAY_ROWS : STA cellY
  JSR DrawHalfPart
.dc_done
  RTS

\ `DrawRow` lived here. Vertical scrolling now moves a scanline at
\ a time and never redraws a whole row, so it is gone — and with it
\ the defect recorded in PLAN.md, which it produced three times.
\ ============================================================
\ ScrollRight — view moves right by 4 px
\ ============================================================
.ScrollRight
  LDA mapHX+1                   \ at the right edge already?
  CMP #HI(MAX_HX)
  BCC sr_ok
  BNE sr_no
  LDA mapHX
  CMP #LO(MAX_HX)
  BCS sr_no
.sr_ok
  INC mapHX
  BNE sr_nohi
  INC mapHX+1
.sr_nohi
  SCROLL_ADD UNIT_BYTES
  LDA #1
  STA needCol79                 \ redrawn later, by DoRedraws
.sr_no
  RTS

\ ============================================================
\ ScrollLeft — view moves left by 4 px
\ ============================================================
.ScrollLeft
  LDA mapHX
  ORA mapHX+1
  BEQ sl_no
  LDA mapHX
  BNE sl_nohi
  DEC mapHX+1
.sl_nohi
  DEC mapHX
  SCROLL_SUB UNIT_BYTES
  LDA #1
  STA needCol0
.sl_no
  RTS

\ ============================================================
\ DrawScanline — one scanline strip across all 80 units
\   scanY  = scanline within the character row, 0-7
\   cellY  = map character row to take it from
\   rCount = display row to write
\ ============================================================
.DrawScanline
  LDA #0
  STA uCount
  JSR SetCell                   \ bufp = display row rCount, unit 0

.ds_loop
  CLC                           \ halfX = mapHX + uCount
  LDA mapHX   : ADC uCount : STA halfX
  LDA mapHX+1 : ADC #0     : STA halfX+1
  JSR DrawHalfScan

  CLC                           \ next 4-pixel column, wrapping the strip
  LDA bufp : ADC #UNIT_BYTES : STA bufp
  BCC ds_nohi
  INC bufp+1
.ds_nohi
  JSR WrapBufFwd

  INC uCount
  LDA uCount
  CMP #PLAY_UNITS
  BNE ds_loop
  RTS

\ ============================================================
\ ScrollDown — view moves down by ONE SCANLINE
\ ============================================================
\ Buffer row 0 is split: scanlines line..7 hold map row mapYr (the
\ top of the view), scanlines 0..line-1 hold map row mapYr+16 (the
\ sliver that display row 16 shows at the bottom). Moving down one
\ scanline hands scanline `line` over from the first to the second,
\ so exactly one scanline strip has to be rewritten.
\
\ When line wraps, the row that was split becomes an ordinary full
\ row — and the 7 scanlines it needs are already right, because
\ they were written on the way here. The scanline written on the
\ wrapping step completes it. No special case.
\ Like the column scrolls, this only updates state and records what
\ needs drawing. DoRedraws does the drawing, AFTER SetCRTCStart has
\ parked the new position — see the note there.
.ScrollDown
  LDA mapYr
  CMP #MAX_Y
  BCS sd_no

  LDA line                      \ hand this scanline to map row mapYr+16
  STA scanY
  CLC
  LDA mapYr : ADC #PLAY_ROWS : STA scanCellY
  LDA #0
  STA scanRow

  INC line                      \ then advance
  LDA line
  CMP #8
  BNE sd_flag
  LDA #0
  STA line
  INC mapYr
  SCROLL_ADD ROW_BYTES
  LDA #PLAY_ROWS-1              \ the strip moved: the row just handed over
  STA scanRow                   \ is the BOTTOM display row now, not the top
.sd_flag
  LDA #1
  STA needScan
.sd_no
  RTS

\ ============================================================
\ ScrollUp — view moves up by ONE SCANLINE
\ ============================================================
\ The mirror image: retreat first, then claim scanline `line` back
\ for map row mapYr.
.ScrollUp
  LDA line
  BNE su_dec
  LDA mapYr                     \ already at the top?
  BEQ su_no
  LDA #8                        \ borrow a row
  STA line
  DEC mapYr
  SCROLL_SUB ROW_BYTES
.su_dec
  DEC line

  LDA line                      \ claim this scanline for map row mapYr
  STA scanY
  LDA mapYr
  STA scanCellY
  LDA #0                        \ retreat happens first, so it is the top row
  STA scanRow
  LDA #1
  STA needScan
.su_no
  RTS

.scanY     EQUB 0
.scanCellY EQUB 0
.scanRow   EQUB 0
.needScan  EQUB 0

\ ============================================================
\ DoRedraws — redraw whatever the scroll routines flagged
\
\ Split out from the Scroll* routines so that SetCRTCStart can be
\ called ONCE, before any drawing. Previously each routine parked
\ the address itself, so on a diagonal move the second one's park
\ landed after the first one's redraw — about 19 rows into the
\ window, i.e. past frame row 3 where the IRQ latches R12/R13.
\ The CRTC then used an address missing one axis while the buffer
\ held the combined position: one frame of wrong graphics on the
\ trailing edge.
\
\ EVERYTHING is deferred to here, including the single scanline a
\ vertical step needs. Drawing it inside ScrollUp/ScrollDown looked
\ harmless — it is only 80 bytes — but the strip costs ~75
\ scanlines, which pushed SetCRTCStart past VSync. `line` is latched
\ by the IRQ at VSync and the parked address is not read until fire
\ 1, so the two landed in different frames: a one-frame row jump at
\ every borrow going up, and a wrongly-exposed top scanline going
\ down. Park first, then draw.
\
\ The scanline strip goes first — it is the split row, which is
\ displayed at both the top and bottom of the play area.
\ ============================================================
.DoRedraws
  LDA needScan
  BEQ dor_ns
  LDA scanRow   : STA rCount
  LDA scanCellY : STA cellY
  JSR DrawScanline
  LDA #0 : STA needScan
.dor_ns

  LDA needCol0
  BEQ dor_nc0
  LDA #0 : STA uCount
  JSR DrawColumn
  LDA #0 : STA needCol0
.dor_nc0

  LDA needCol79
  BEQ dor_nc79
  LDA #PLAY_UNITS-1 : STA uCount
  JSR DrawColumn
  LDA #0 : STA needCol79
.dor_nc79
  RTS

.needCol0  EQUB 0
.needCol79 EQUB 0
