\ ============================================================
\ scroll.asm — move the view, fill in what appeared
\ ============================================================
\ The view is a 16-bit PIXEL position (posX, posY), owned by
\ player.asm. Everything here derives from it:
\
\   mapHX = posX >> 2     4-pixel units — the horizontal grain
\   mapYr = posY >> 3     character row
\   line  = posY AND 7    scanline within it, applied by the CRTC
\
\ The player moves up to 7 pixels in a frame, so a step is no longer
\ one unit or one scanline: it is up to 2 columns and up to 7
\ scanlines, and either may be zero.
\
\ Where a scanline lives
\ ----------------------
\ Absolute map pixel row A, unit u, is at
\
\   BUF_BASE + ((scrollS + ((A>>3) - mapYr)*640 + u*8 + (A AND 7))
\               MOD BUF_SIZE)
\
\ and that expression is invariant under scrolling: substitute the
\ new scrollS and mapYr after a move and it names the same byte. So
\ nothing already drawn ever has to move — only the leading edge is
\ drawn. ((A>>3) - mapYr) is taken AND 15, and that is precisely
\ what makes display row 16 and display row 0 the same row: the
\ split row.
\ ============================================================

\ ---- offset tables -----------------------------------------
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

\ ============================================================
\ ScrollAddS — scrollS += sDelta, signed, kept in [0, BUF_SIZE)
\ ============================================================
\ sDelta is dUnits*8 + dRows*640, so at most +/-656 — one wrap
\ correction either way is always enough.
.ScrollAddS
  CLC
  LDA scrollS   : ADC sDelta   : STA scrollS
  LDA scrollS+1 : ADC sDelta+1 : STA scrollS+1
  LDA scrollS+1
  BMI sas_neg
  CMP #HI(BUF_SIZE)
  BCC sas_x
  BNE sas_sub
  LDA scrollS
  CMP #LO(BUF_SIZE)
  BCC sas_x
.sas_sub
  SEC
  LDA scrollS   : SBC #LO(BUF_SIZE) : STA scrollS
  LDA scrollS+1 : SBC #HI(BUF_SIZE) : STA scrollS+1
  RTS
.sas_neg
  CLC
  LDA scrollS   : ADC #LO(BUF_SIZE) : STA scrollS
  LDA scrollS+1 : ADC #HI(BUF_SIZE) : STA scrollS+1
.sas_x
  RTS

\ ============================================================
\ SetCell — point bufp at display cell (rCount, uCount)
\   bufp = BUF_BASE + ((scrollS + rCount*640 + uCount*8) MOD SIZE)
\ ============================================================
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

\ ============================================================
\ DrawColumn — redraw one 4-pixel column, all 16 rows
\   uCount = the column
\ ============================================================
\ halfX is constant down a column, so the lookup is set up once and
\ the row walk is a 640-byte pointer add rather than a fresh SetCell
\ per row.
.DrawColumn
  CLC                           \ halfX = mapHX + uCount
  LDA mapHX   : ADC uCount : STA halfX
  LDA mapHX+1 : ADC #0     : STA halfX+1
  JSR ColSetup

  LDA #0 : STA rCount
  JSR SetCell                   \ only once: row 0 of this column
  LDA mapYr : STA cellY
.dc_loop
  JSR ColCharPtr
  LDY #7
.dc_copy
  LDA (chp),Y
  STA (bufp),Y
  DEY
  BPL dc_copy

  CLC                           \ next row of the strip
  LDA bufp   : ADC #LO(ROW_BYTES) : STA bufp
  LDA bufp+1 : ADC #HI(ROW_BYTES) : STA bufp+1
  LDA bufp+1                    \ BUF_END is page aligned, so the low
  CMP #HI(BUF_END)              \ byte never needs testing
  BCC dc_nowrap
  SEC
  LDA bufp   : SBC #LO(BUF_SIZE) : STA bufp
  LDA bufp+1 : SBC #HI(BUF_SIZE) : STA bufp+1
.dc_nowrap

  INC cellY
  INC rCount
  LDA rCount
  CMP #PLAY_ROWS
  BNE dc_loop
  RTS

\ ============================================================
\ COPYCELL — one 4-pixel column cell: 8 bytes, chp -> bufp
\ ============================================================
\ Unrolled, and the loop counter goes with it. A cell is ALWAYS the
\ whole 8 scanlines now, so the run and the offset that CopyRun took
\ as variables are both constants, and paying 18 cycles a byte to
\ support a case that no longer occurs was the single largest waste
\ in the band: 13 a byte is the floor for (zp),Y on both sides.
\
\ Y is walked with INY rather than reloaded per byte. Both come to 13
\ cycles a byte — LDY #n is 2 and so is INY — but the walk is 5 bytes
\ a copy against 6, and in the loop that difference is what keeps the
\ branch at the bottom in range.
MACRO COPYCELL
  LDY #0
  FOR n, 0, 7
    LDA (chp),Y
    STA (bufp),Y
    IF n < 7
      INY
    ENDIF
  NEXT
ENDMACRO

\ ============================================================
\ COPYCHAR — a WHOLE character: both halves, 16 bytes, in one run
\ ============================================================
\ A character's two halves are 16 consecutive bytes in the charset,
\ and the two units they go to are 16 consecutive bytes in the strip.
\ So one Y running 0-15 addresses both, and the `chp + 8` and the
\ BufNextUnit that used to sit between the halves are simply gone —
\ 46 cycles a character for nothing.
\
\ THE ONE CONDITION: the strip's wrap must not fall BETWEEN the two
\ halves, or the second half would be written 8 bytes past &8000, into
\ sideways RAM. It never does, and that is a property of the geometry
\ rather than luck:
\
\   Units from the row start to the wrap is W = 1280 - off/8, where
\   off = (scrollS + rCount*640) MOD 10240. rCount*640 is 80 units, so
\   W = -scrollS/8 = scrollS/8  (mod 2).
\
\   Characters begin at even units when mapHX is even and at odd units
\   when it is odd — unit 0 is then a right half on its own. So the
\   wrap lands on a character boundary exactly when
\
\       scrollS/8 == mapHX  (mod 2)
\
\   and that is INVARIANT. Both sides move by dUnits on a horizontal
\   step; a vertical step moves scrollS/8 by 80 and mapHX not at all,
\   and 80 is even. scrollS wraps at 1280 units, also even. sDelta is
\   computed FROM the mapHX difference, so even a clamp that stops
\   mapHX moves scrollS by exactly as much.
\
\ LoadDeck establishes it — see the scrollS parity there. It is set
\ explicitly rather than inherited from CentreOnDeck happening to
\ produce an even mapHX, because this loop writes out of the buffer if
\ it is ever false, and that should not depend on another routine's
\ arithmetic staying the way it is.
MACRO COPYCHAR
  LDY #0
  FOR n, 0, 15
    LDA (chp),Y
    STA (bufp),Y
    IF n < 15
      INY
    ENDIF
  NEXT
ENDMACRO

\ ============================================================
\ DrawBandRows — ONE display row, full width, all 8 scanlines
\   rCount   = display row
\   cellY    = map character row to take it from
\ ============================================================
\ Walks CHARACTERS, not units. Two adjacent units are the two halves
\ of one character, so looking the character up once and drawing
\ both halves halves the tile and character lookups — and removes
\ half of the per-unit bookkeeping, which turned out to cost more
\ than the lookups did.
\
\ mapHX can be odd, in which case unit 0 is a right half and unit 79
\ a left half, with 39 whole characters between them.
\
\ Everything the loop touches is inline. This is the hottest code in
\ the port: it runs 40 times a pass on 7 passes in 8, and its cost is
\ what the scroll rate is made of.
\
\ The two copies in the loop are inlined and the two edge cases call
\ CopyCell, because they run once a pass against the loop's 40 and
\ the 12 cycles of call are not worth 48 bytes each.
.DrawBandRows
  JSR BandSetRow                \ cellY is fixed for the whole pass
  LDA #0
  STA uCount
  JSR SetCell                   \ bufp = display row rCount, unit 0

  LDA mapHX+1                   \ cellX = mapHX >> 1
  LSR A
  STA cellX+1
  LDA mapHX
  ROR A
  STA cellX

  LDA mapHX
  AND #1
  STA dbOdd
  BEQ dbr_whole

  JSR BandCharPtr               \ leading right half, on its own
  CLC
  LDA chp : ADC #8 : STA chp
  BCC dbr_l1
  INC chp+1
.dbr_l1
  JSR CopyCell
  JSR BufNextUnit
  JSR CellXInc
  LDA #(PLAY_UNITS/2)-1
  BNE dbr_setn
.dbr_whole
  LDA #PLAY_UNITS/2
.dbr_setn
  STA dbCount

\ ---- the tile walk ------------------------------------------
\ A TILE IS FOUR CHARACTERS WIDE AND THOSE FOUR CODES ARE FOUR
\ CONSECUTIVE BYTES of tiledefs. BandCharPtr did not use that: it
\ derived the tile column from cellX, compared it against a cache, and
\ rebuilt (cellX AND 3) + subRowOfs as an index, every character —
\ about 40 cycles of rediscovering where it already was.
\
\ So the row is walked as tiles of four instead. The tile's row within
\ tiledefs is folded into tdp when it is built, which leaves the four
\ characters at Y = 0..3 and costs nothing: (tile AND 15)*16 is at
\ most 240 and subRowOfs at most 12, so the add cannot carry.
\
\ A 40-character row starting anywhere covers eleven tiles with a
\ partial one at each end, so each tile draws min(4 - sub, remaining)
\ characters and every tile after the first starts at sub 0.
\
\ cellX is no longer maintained across the row — the trailing half
\ recomputes it — so the INC that used to run per character is gone
\ with everything else.
  LDA cellX+1                   \ tile column = cellX >> 2
  LSR A
  LDA cellX
  ROR A
  LSR A
  STA dbTile
  LDA cellX                     \ first character within that tile
  AND #3
  STA dbSub

.dbr_tile
  LDY dbTile                    \ tile number -> tdp, row folded in
  LDA (maprow),Y
  PHA
  AND #&0F
  ASL A : ASL A : ASL A : ASL A
  CLC : ADC subRowOfs           \ <= 240 + 12: cannot carry
  STA tdp
  PLA
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #HI(tiledefs)
  STA tdp+1
  INC dbTile

  SEC                           \ n = min(4 - sub, remaining)
  LDA #4
  SBC dbSub
  CMP dbCount
  BCC dbr_n
  LDA dbCount
.dbr_n
  STA dbN
  LDA dbCount
  SEC
  SBC dbN
  STA dbCount
  LDA dbSub
  STA dbIdx
  LDA #0
  STA dbSub                     \ every later tile starts at its first

.dbr_char
  LDY dbIdx
  LDA (tdp),Y                   \ character code
  TAX                           \ -> its charset address, precomputed
  LDA CHAR_PTR_LO,X : STA chp
  LDA CHAR_PTR_HI,X : STA chp+1
  COPYCHAR                      \ both halves, one run

  CLC                           \ on two units, to the next character
  LDA bufp : ADC #CHAR_BYTES : STA bufp
  BCC dbr_nc
  INC bufp+1
.dbr_nc
  LDA bufp+1                    \ BUF_END is page aligned, and the wrap
  CMP #HI(BUF_END)              \ lands on a character boundary, so bufp
  BCS dbr_wrap                  \ arrives exactly ON it, never past
.dbr_now
  INC dbIdx
  DEC dbN
  BNE dbr_char

  LDA dbCount
  BEQ dbr_tail
  JMP dbr_tile

.dbr_tail
  LDA dbOdd
  BEQ dbr_done
  CLC                           \ the trailing left half is the character
  LDA cellX   : ADC #(PLAY_UNITS/2)-1 : STA cellX   \ 39 past the first
  LDA cellX+1 : ADC #0 : STA cellX+1                \ whole one
  LDA #&FF                      \ dbTile has moved on without it, so make
  STA tileCol                   \ BandCharPtr's cache miss rather than
  JSR BandCharPtr               \ trust a stale column
  JSR CopyCell
.dbr_done
  RTS

\ Out of line, and not only to keep the loop's branch in range: it
\ fires once a row against 39 misses, so the common path is now a
\ not-taken BCS at 2 cycles rather than a taken BCC at 3.
.dbr_wrap
  SEC
  LDA bufp   : SBC #LO(BUF_SIZE) : STA bufp
  LDA bufp+1 : SBC #HI(BUF_SIZE) : STA bufp+1
  JMP dbr_now

\ ---- band inner helpers ------------------------------------
\ The callable form, for the two edge halves only.
.CopyCell
  COPYCELL
  RTS

\ BUF_END is page aligned, so the wrap test is one compare on the
\ high byte and costs 5 cycles when it does not fire — which is
\ 159 times out of 160.
.BufNextUnit
  CLC
  LDA bufp : ADC #UNIT_BYTES : STA bufp
  BCC bnu_nc
  INC bufp+1
.bnu_nc
  LDA bufp+1
  CMP #HI(BUF_END)
  BCC bnu_x
  SEC
  LDA bufp   : SBC #LO(BUF_SIZE) : STA bufp
  LDA bufp+1 : SBC #HI(BUF_SIZE) : STA bufp+1
.bnu_x
  RTS

.CellXInc
  INC cellX
  BNE cxi_x
  INC cellX+1
.cxi_x
  RTS

\ ============================================================
\ DoRedraws — draw whatever the move exposed
\ ============================================================
\ The band goes first: it is the top or bottom edge of the strip,
\ which the raster reaches soonest, and on a diagonal it and the
\ columns have to share one window.
\
\ Everything is deferred to here rather than done inside the move,
\ because SetCRTCStart has to park the address BEFORE any drawing.
\ A band costs most of the window; drawing first pushed the park
\ past VSync and split the line/scrollS pair across two frames.
\
\ WHOLE ROWS, NOT EXPOSED SCANLINES. A band's cost is almost entirely
\ its 40-character lookup walk — ~10,950 cycles against ~1,371 for a
\ scanline of copying across the width — and drawing only what the
\ move exposed paid that walk on every pass that moved at all, twice
\ whenever the exposed scanlines straddled a character boundary,
\ which is 7 passes in 8 at top speed. Measured at 2.03 walks per map
\ row against a floor of 1.
\
\ So the strip holds WHOLE map rows: display row r is map row
\ mapYr+r, all eight scanlines, and the only thing that exposes new
\ vertical content is mapYr itself changing. The row that has to be
\ drawn is the one the move vacated, and it is vacated exactly when
\ its replacement's first scanline becomes visible — see ApplyMove.
\
\ That also retires the split row: no display row holds two map rows
\ any more, so DrawColumn and RedrawAll no longer need their repair
\ passes, and a full redraw is a valid oracle at any value of `line`.
.DoRedraws
  LDA bandDo
  BEQ dor_nb
  LDA #0
  STA bandDo
  LDA bandRow : STA cellY
  LDA bandRc  : STA rCount
  JSR DrawBandRows
.dor_nb

  LDA colCount
  BEQ dor_nc
  LDA colFirst
  STA uCount
.dor_col
  JSR DrawColumn
  INC uCount
  DEC colCount
  BNE dor_col
.dor_nc
  RTS

.bandDo    EQUB 0               \ a character row was crossed: draw one
.bandRow   EQUB 0               \ which map character row
.bandRc    EQUB 0               \ and which display row it lands in
.colFirst  EQUB 0
.colCount  EQUB 0
.dbOdd     EQUB 0               \ mapHX odd: the row starts on a right half
.dbTile    EQUB 0               \ tile column being walked
.dbSub     EQUB 0               \ first character within it, 0 after the first
\ dbN and dbCount are in zero page — they are read and written several
\ times a tile and dbN once more a character. They took the slots
\ halfSel and dirty had been holding since before either was retired.
.sDelta    EQUW 0
