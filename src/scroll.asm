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
IF TARGET_MASTER
  LDA drawShift
  BNE dc_shift
ENDIF
  JSR ColCharPtr
  LDY #7
.dc_copy
  LDA (chp),Y
  STA (bufp),Y
  DEY
  BPL dc_copy
IF TARGET_MASTER
  JMP dc_after
\ Buffer B's column needs the column to its right as well, and the
\ Col* hoisting holds state for one halfX only — so this drops back to
\ the generic two-lookup path rather than carrying a second set of it.
\ 16 cells paying an uncached MapChar each is the obvious thing to fix
\ if the column redraw becomes the binding cost; the band, which runs
\ far more often, already avoids it.
.dc_shift
  JSR DrawHalfShift             \ halfX and cellY are both already set
.dc_after
ENDIF

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

\ ============================================================
\ DrawBandRows — bandRun scanlines of ONE display row, full width
\   rCount   = display row
\   bandScan = first scanline within it
\   bandRun  = how many, 1..8, never crossing the row
\   cellY    = map character row to take them from
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
\ the port: at the top speed of 7 px a frame it runs twice, 40 times
\ each, every frame.
.DrawBandRows
IF TARGET_MASTER
  LDA drawShift
  BNE DrawBandRowsS
ENDIF
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
  JSR CopyRun
  JSR BufNextUnit
  JSR CellXInc
  LDA #(PLAY_UNITS/2)-1
  BNE dbr_setn
.dbr_whole
  LDA #PLAY_UNITS/2
.dbr_setn
  STA dbCount

.dbr_char
  JSR BandCharPtr
  JSR CopyRun                   \ left half
  JSR BufNextUnit
  CLC
  LDA chp : ADC #8 : STA chp
  BCC dbr_l2
  INC chp+1
.dbr_l2
  JSR CopyRun                   \ right half
  JSR BufNextUnit
  JSR CellXInc
  DEC dbCount
  BNE dbr_char

  LDA dbOdd
  BEQ dbr_done
  JSR BandCharPtr               \ trailing left half
  JSR CopyRun
.dbr_done
  RTS

IF TARGET_MASTER
\ ============================================================
\ DrawBandRowsS — the same band, shifted 2 px, for buffer B
\ ============================================================
\ Every output unit needs its own source AND the next one along, so
\ the naive form looks up each character twice and doubles the cost of
\ the hottest routine in the port. It does not have to: two adjacent
\ units are the two halves of one character, so of the two units a
\ character produces, only the RIGHT one reaches past it — and what it
\ reaches for is the next character, which the loop is about to look
\ up anyway.
\
\ So the loop keeps ONE character in hand and looks one ahead:
\
\   left  unit u   = f(cur, cur+8)      both halves of this character
\   right unit u+1 = f(cur+8, next)     next character's left half
\
\ 41 lookups for 80 units, against A's 40. The extra one is the
\ character past the right edge of the view, which is what MAX_HX is
\ pulled in by a character to keep inside the tile map.
\
\ BandCharPtr writes its result to chp, so the current character has
\ to be parked across the lookahead — that is what sbCur is for.
.DrawBandRowsS
  JSR BandSetRow
  LDA #0
  STA uCount
  JSR SetCell                   \ bufp = display row rCount, unit 0

  LDA mapHX+1                   \ cellX = mapHX >> 1
  LSR A
  STA cellX+1
  LDA mapHX
  ROR A
  STA cellX

  JSR BandCharPtr               \ chp = character containing unit 0

  LDA mapHX
  AND #1
  STA dbOdd
  BEQ dbs_whole

\ mapHX odd: unit 0 is this character's RIGHT half on its own, and its
\ partner is already in the next character.
  JSR dbs_look                  \ sbNext = next character
  CLC
  LDA chp   : ADC #8 : STA chp
  LDA chp+1 : ADC #0 : STA chp+1
  LDA sbNext   : STA chp2
  LDA sbNext+1 : STA chp2+1
  JSR CopyRunShift
  JSR BufNextUnit
  LDA sbNext   : STA chp       \ that next character is now the current one
  LDA sbNext+1 : STA chp+1
  LDA #(PLAY_UNITS/2)-1
  BNE dbs_setn
.dbs_whole
  LDA #PLAY_UNITS/2
.dbs_setn
  STA dbCount

.dbs_char
  JSR dbs_look                  \ sbNext = the character after this one

  CLC                           \ left unit: this character's two halves
  LDA chp   : ADC #8 : STA chp2
  LDA chp+1 : ADC #0 : STA chp2+1
  JSR CopyRunShift
  JSR BufNextUnit

  LDA chp2   : STA chp          \ right unit: right half, then next character
  LDA chp2+1 : STA chp+1
  LDA sbNext   : STA chp2
  LDA sbNext+1 : STA chp2+1
  JSR CopyRunShift
  JSR BufNextUnit

  LDA sbNext   : STA chp
  LDA sbNext+1 : STA chp+1
  DEC dbCount
  BNE dbs_char

  LDA dbOdd
  BEQ dbs_done
  CLC                           \ trailing LEFT half, partnered by its own
  LDA chp   : ADC #8 : STA chp2 \ right half — no further lookahead needed
  LDA chp+1 : ADC #0 : STA chp2+1
  JSR CopyRunShift
.dbs_done
  RTS

\ sbNext = the next character's left half, chp left as it was.
.dbs_look
  LDA chp   : STA sbCur
  LDA chp+1 : STA sbCur+1
  JSR CellXInc
  JSR BandCharPtr
  LDA chp   : STA sbNext
  LDA chp+1 : STA sbNext+1
  LDA sbCur   : STA chp
  LDA sbCur+1 : STA chp+1
  RTS

\ bandRun shifted bytes at offset bandScan — see the derivation in
\ screen.asm. 41 cycles a byte against CopyRun's 13, which is the
\ whole of what buffer B costs over and above buffer A.
.CopyRunShift
  LDY bandScan
  LDX bandRun
.crs_loop
  LDA (chp2),Y
  LSR A : LSR A
  AND #&33
  STA shTmp
  LDA (chp),Y
  ASL A : ASL A
  AND #&CC
  ORA shTmp
  STA (bufp),Y
  INY
  DEX
  BNE crs_loop
  RTS

.sbCur  EQUW 0
.sbNext EQUW 0
ENDIF

\ ---- band inner helpers ------------------------------------
\ bandRun bytes at offset bandScan, from the charset to the buffer.
\ Source and destination are both 8-byte units indexed the same way,
\ so one Y serves both.
.CopyRun
  LDY bandScan
  LDX bandRun
.cr_loop
  LDA (chp),Y
  STA (bufp),Y
  INY
  DEX
  BNE cr_loop
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
\ DrawBand — bandN scanlines from absolute map pixel row bandA
\ ============================================================
\ Split into at most two character rows. bandN never exceeds the top
\ speed, so in practice that is one boundary at most, but the loop
\ does not depend on it.
.DrawBand
.db_loop
  LDA bandA+1 : STA dbTmp+1     \ M = bandA >> 3
  LDA bandA   : STA dbTmp
  LSR dbTmp+1 : ROR dbTmp
  LSR dbTmp+1 : ROR dbTmp
  LSR dbTmp+1 : ROR dbTmp
  LDA dbTmp
  STA cellY
  SEC                           \ display row = (M - mapYr) AND 15
  SBC mapYr
  AND #PLAY_ROWS-1
  STA rCount

  LDA bandA                     \ first scanline within that row
  AND #7
  STA bandScan

  LDA #8                        \ run = min(bandN, 8 - bandScan)
  SEC
  SBC bandScan
  CMP bandN
  BCC db_run
  LDA bandN
.db_run
  STA bandRun

  JSR DrawBandRows

  CLC                           \ on past what was drawn
  LDA bandA : ADC bandRun : STA bandA
  BCC db_nc
  INC bandA+1
.db_nc
  LDA bandN
  SEC
  SBC bandRun
  STA bandN
  BNE db_loop
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
.DoRedraws
  LDA bandN
  BEQ dor_nb
  JSR DrawBand                  \ leaves bandN at 0
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

.bandA     EQUW 0               \ absolute map pixel row, first exposed
.bandN     EQUB 0               \ scanlines to draw; 0 = nothing to do
.bandScan  EQUB 0
.scanY     EQUB 0               \ DrawColumn's split-row repair depth
.bandRun   EQUB 0
.colFirst  EQUB 0
.colCount  EQUB 0
.dbTmp     EQUW 0
.dbOdd     EQUB 0               \ mapHX odd: the row starts on a right half
.dbCount   EQUB 0
.sDelta    EQUW 0
