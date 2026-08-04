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
  RTS

\ ============================================================
\ DrawRow — redraw one character row, all 80 columns
\   rCount = the row
\ ============================================================
.DrawRow
  LDA #0 : STA uCount
.dr_loop
  JSR SetCell

  CLC
  LDA mapHX   : ADC uCount : STA halfX
  LDA mapHX+1 : ADC #0     : STA halfX+1
  CLC
  LDA mapYr : ADC rCount : STA cellY
  JSR DrawHalf

  INC uCount
  LDA uCount
  CMP #PLAY_UNITS
  BNE dr_loop
  RTS

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
  JSR SetCRTCStart
  LDA #PLAY_UNITS-1             \ the column that just appeared
  STA uCount
  JSR DrawColumn
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
  JSR SetCRTCStart
  LDA #0
  STA uCount
  JSR DrawColumn
.sl_no
  RTS

\ ============================================================
\ ScrollDown — view moves down by 8 px
\ ============================================================
.ScrollDown
  LDA mapYr
  CMP #MAX_Y
  BCS sd_no
  INC mapYr
  SCROLL_ADD ROW_BYTES
  JSR SetCRTCStart
  LDA #PLAY_ROWS-1
  STA rCount
  JSR DrawRow
.sd_no
  RTS

\ ============================================================
\ ScrollUp — view moves up by 8 px
\ ============================================================
.ScrollUp
  LDA mapYr
  BEQ su_no
  DEC mapYr
  SCROLL_SUB ROW_BYTES
  JSR SetCRTCStart
  LDA #0
  STA rCount
  JSR DrawRow
.su_no
  RTS
