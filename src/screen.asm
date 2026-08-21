\ ============================================================
\ screen.asm — 10K play buffer, CRTC hardware scrolling
\ ============================================================
\ Play area: 320 x 128 px = 10 x 4 tiles, matching the C64's
\ 9.5 x 4 rounded up so both axes wrap cleanly.
\
\ 320 x 128 = 10240 bytes = exactly 16 rows of 640, and the BBC
\ supports a 10K wrap natively (the MODE 4/5 setting): System VIA
\ addressable latch lines 4 and 5 both high select subtract &2800
\ with restart &5800.
\
\ The buffer is a CIRCULAR STRIP, not a flat grid. Display cell
\ (row, unit) lives at:
\
\     BUF_BASE + ((scrollS + row*640 + unit*8) MOD 10240)
\
\ Scrolling is then just moving scrollS and filling in whatever
\ became exposed:
\   horizontal, 4 px  — scrollS +/- 8    -> 16 cells to redraw
\   vertical,   8 px  — scrollS +/- 640  -> 80 cells to redraw
\
\ A CRTC unit in MODE 1 is one byte per scanline = 4 pixels, and
\ characters are stored as two 8-byte halves, so a 4-pixel column
\ is exactly one stored half-character. No pre-shifted data.
\ ============================================================

\ Geometry constants live in main.asm — beebasm resolves constant
\ assignments in file order, and rupture.asm needs them too.

\ SetupMode/SetupRupture, SetCRTCStart and WrapBufFwd are NOT here: they are in
\ bufcore.asm, in main RAM, because they run either before this bank
\ is loaded or while the sprite bank is paged in. Its header has the
\ rule. Everything below runs with SWRAM_DATA in, which is the
\ resting state.

\ ============================================================
\ DrawHalf — write one 4-pixel column cell
\   halfX = map position in half-characters (16 bit)
\   cellY = map character row
\   bufp  = destination
\ ============================================================
.DrawHalf
  JSR HalfPtr
  LDY #7
.dh_loop
  LDA (chp),Y
  STA (bufp),Y
  DEY
  BPL dh_loop
  RTS

\ DrawHalfScan and DrawHalfPart lived here: single-scanline and
\ partial-cell writes, both of them only ever used to repair the
\ split row. The strip holds whole map rows now, so there is no
\ split row and nothing needs repairing — see DoRedraws.

\ ============================================================
\ BuildCharPtrs — character code -> its address in the charset
\ ============================================================
\ charRemap packs the used-character index into one byte and every
\ lookup then unpacked it into a 16-bit pointer: PHA, AND, four ASLs,
\ PLA, four LSRs, ADC. Forty-one cycles of address arithmetic per
\ character drawn, which was more than the tile-map lookup it follows
\ (that one is cached three calls in four and costs ~11 amortised).
\
\ Precomputing both bytes turns it into two indexed loads and two
\ stores, 16 cycles. It is a pure function of charRemap and the
\ charset base, both fixed for the whole run, so it is built once at
\ startup rather than per deck — BuildCharset rewrites the charset's
\ CONTENTS per deck, never its address.
\
\ Costs 512 bytes of the scratch between the panel and the strip.
\ Nothing else wanted that space and every character drawn pays for
\ it, on both the band and the column paths.
\ charRemap ships inside the packed char stream since layer-11e stage 3,
\ so this depacks first and reads the scratch copy. Both call sites —
\ boot, and GoTitle's rebuild — are moments the sprite save areas hold
\ nothing (and LoadDeck depacks again for itself moments later).
.BuildCharPtrs
  JSR UnpackChars
  LDX #0
.bcp_loop
  LDA SPR_SAVE + CHARSRC_SIZE,X
  PHA
  AND #&0F
  ASL A : ASL A : ASL A : ASL A
  STA CHAR_PTR_LO,X
  PLA
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #HI(charset)
  STA CHAR_PTR_HI,X
  INX
  BNE bcp_loop
  RTS

\ ============================================================
\ HalfPtr — chp = charset bytes for the cell at (halfX, cellY)
\ ============================================================
.HalfPtr
  JSR HalfPtrLeft
  LDA halfX                     \ right half is 8 bytes further on
  AND #1
  BEQ hp_done
  CLC
  LDA chp : ADC #8 : STA chp
  BCC hp_done
  INC chp+1
.hp_done
  RTS

\ ============================================================
\ HalfPtrLeft — chp = the LEFT half of the character containing
\ halfX, whichever half halfX itself names
\ ============================================================
\ Split out because a character is two 4-pixel halves and a
\ full-width draw visits both in succession. Keeping chp on the left
\ half lets the odd unit reuse it as chp+8, halving the number of
\ tile and character lookups a band costs — and lookups, not the
\ copying, are what a band spends its time on.
.HalfPtrLeft
  LDA halfX+1                   \ cellX = halfX >> 1, without disturbing halfX
  LSR A
  STA cellX+1
  LDA halfX
  ROR A
  STA cellX

  JSR MapChar                   \ -> A = character code

  TAX                           \ straight to its charset address
  LDA CHAR_PTR_LO,X : STA chp
  LDA CHAR_PTR_HI,X : STA chp+1
  RTS

\ ============================================================
\ Address tables — tile number and tile row to their base addresses
\ ============================================================
\ Both of these were being computed by hand at every use: PHA, AND,
\ four or six ASLs, PLA, matching LSRs, ADC. Thirty-five cycles to
\ multiply by 16 and thirty to multiply by 64, when the operands run
\ over 32 and 16 values respectively.
\
\ They are pure functions of `tiledefs` and `tilemap`, both fixed at
\ assembly time, so unlike CHAR_PTR_LO/HI they need no builder and no
\ RAM — 96 bytes of the code image and beebasm fills them in.
\
\ Not aligned: at 32 and 16 entries a page boundary costs one cycle on
\ the entries past it, and only on paths that already run once every
\ four rows or once a tile. Alignment would cost more bytes than the
\ cycles are worth.
.tdpLo
  FOR t, 0, 31
    EQUB LO(tiledefs + t * 16)
  NEXT
.tdpHi
  FOR t, 0, 31
    EQUB HI(tiledefs + t * 16)
  NEXT
\ blankTileRow — the 64 zero bytes an off-map row is drawn from — lives
\ in the DATA BANK, not here. Every path that reads it (BandSetRow, and
\ the draw that follows) runs with SWRAM_DATA paged in, which is the
\ resting state; only the blitter ever swaps it out, and the blitter
\ never draws a map row. See the bank section in main.asm.
.mapRowLo
  FOR r, 0, MAP_ROWS-1
    EQUB LO(tilemap + r * MAP_COLS)
  NEXT
.mapRowHi
  FOR r, 0, MAP_ROWS-1
    EQUB HI(tilemap + r * MAP_COLS)
  NEXT

\ ============================================================
\ BandSetRow / BandCharPtr — the same lookup as HalfPtrLeft, with
\ everything that depends only on cellY hoisted out
\ ============================================================
\ A band draws one map row across all 80 units, so cellY is constant
\ for the whole pass: the tile-map row base and the sub-row offset
\ within a tile can be computed once instead of 40 times. And the
\ tile number only changes every 4 characters — every 8 units — so
\ the tile-definition pointer is cached and recomputed on 1 call in
\ 4.
\
\ This matters because a band's cost is almost entirely lookups. At
\ the top speed of 7 px/frame a move exposes scanlines in two
\ character rows, so the play area pays for two full passes of 40
\ lookups to draw 7 scanlines — and that, not the copying, was
\ pushing the redraw into the visible picture.
\ OFF THE MAP IS A ROW OF TILE 0. Map rows are 0-63, so `AND &C0`
\ catches both a negative row (the view scrolled above the top) and one
\ past 63 (below the bottom) in a single test. Pointing maprow at 64
\ zero bytes makes every tile on the row tile 0, whose definition is 16
\ zero bytes — so the whole of the rest of the draw runs unchanged and
\ produces blank. Nothing downstream needs to know.
.BandSetRow
  LDA cellY
  AND #&C0
  BNE bsr_blank

  LDA cellY                     \ row base: tilemap + (cellY>>2)*64
  LSR A : LSR A
  TAX
  STA doorTileRow               \ which tile row the band is drawing, for
                                \ the door lookup in DrawBandRows
  LDA mapRowLo,X : STA maprow
  LDA mapRowHi,X : STA maprow+1

  LDA cellY                     \ (cellY AND 3) * 4, the row within a tile
  AND #3
  ASL A : ASL A
  STA subRowOfs

  LDA #&FF                      \ no tile column can match: force a miss
  STA tileCol
  RTS

.bsr_blank
  LDA #LO(blankTileRow) : STA maprow
  LDA #HI(blankTileRow) : STA maprow+1
  LDA #0
  STA subRowOfs
  LDA #&FF                      \ and no door can be on a row off the map
  STA doorTileRow
  STA tileCol
  RTS

\ BandCharPtr works from cellX directly. A band walks the map one
\ character at a time and draws both of its 4-pixel halves, so it
\ counts characters, not units, and never needs halfX.
.BandCharPtr
  LDA cellX+1
  LSR A
  LDA cellX
  ROR A
  LSR A                         \ tile column = cellX >> 2
  CMP tileCol
  BEQ bcp_hit
  STA tileCol
  TAY
  LDA (maprow),Y                \ tile number -> its tiledefs base
  TAX
  LDA tdpLo,X : STA tdp
  LDA tdpHi,X : STA tdp+1
.bcp_hit
  LDA cellX
  AND #3
  CLC
  ADC subRowOfs
  TAY
  LDA (tdp),Y                   \ character code

  TAX                           \ -> its charset address, precomputed
  LDA CHAR_PTR_LO,X : STA chp
  LDA CHAR_PTR_HI,X : STA chp+1
  RTS

\ subRowOfs and tileCol are in zero page — see the level draw block in
\ main.asm for why.

\ ============================================================
\ ColSetup / ColCharPtr — the mirror image, for a column
\ ============================================================
\ Down a column cellX is constant and cellY changes, so the tile
\ COLUMN and the character's column within its tile are fixed, and
\ the tile itself only changes every 4 rows. Same idea as
\ BandSetRow, hoisting the other axis.
.ColSetup                       \ from halfX
  LDA halfX+1
  LSR A
  STA cellX+1
  LDA halfX
  ROR A
  STA cellX

  LDA cellX+1                   \ tile column = cellX >> 2
  LSR A
  LDA cellX
  ROR A
  LSR A
  STA colTileCol
  LDA cellX
  AND #3
  STA colSubX
  LDA halfX                     \ which half of the character, as the 0
  AND #1                        \ or 8 that gets added to its address —
  ASL A : ASL A : ASL A         \ constant for the whole column, so the
  STA colHalf                   \ row loop adds it instead of testing it
  LDA #&FF
  STA colTileRow                \ no tile row can match: force a miss
  RTS

\ ColCharPtr lived here. It had one caller and ran 16 times a column,
\ so it is inlined into DrawColumn — with the tile-row miss out of
\ line, which is what keeps that loop's branch in range.

\ colTileCol, colSubX, colHalf and colTileRow are in zero page — the
\ last three are read once per row of every column drawn.

\ ============================================================
\ MapChar — character code at map cell (cellX, cellY)
\   tile      = tilemap[(cellY>>2)*64 + (cellX>>2)]
\   character = tiledefs[tile*16 + (cellY AND 3)*4 + (cellX AND 3)]
\ ============================================================
\ Off the map vertically is character 0: blank, and bit 7 clear, so the
\ wall probes read it as walkable and only the deck's own edge wall
\ stops the player — which is exactly what the original does, since its
\ plyMapPos simply runs off the top of the character map.
\ X is preserved on this path as on the other, because ProbeGroup keeps
\ the probe index there across the call.
.MapChar
  LDA cellY
  AND #&C0
  BEQ mc_onmap
  LDA #0
  RTS
.mc_onmap
  LDA cellY                     \ row base: tilemap + (cellY>>2)*64
  LSR A : LSR A
  STA mcTmp
  AND #3
  ASL A : ASL A : ASL A : ASL A : ASL A : ASL A
  STA maprow
  LDA mcTmp
  LSR A : LSR A
  CLC : ADC #HI(tilemap)
  STA maprow+1

  LDA cellX+1                   \ tile column = cellX >> 2
  LSR A
  LDA cellX
  ROR A
  LSR A
  TAY
  LDA (maprow),Y                \ tile number

  PHA                           \ tdp = tiledefs + tile*16
  AND #&0F
  ASL A : ASL A : ASL A : ASL A
  STA tdp
  PLA
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #HI(tiledefs)
  STA tdp+1

  LDA cellY                     \ (cellY AND 3)*4 + (cellX AND 3)
  AND #3
  ASL A : ASL A
  STA mcTmp
  LDA cellX
  AND #3
  CLC : ADC mcTmp
  TAY

\ An open door replaces the tile definition, so the probes see the
\ doorway as passable at exactly the moment the draw shows it open —
\ same substitution, same source, so the two cannot disagree.
\ DoorTdp preserves X, which ProbeGroup is relying on.
  LDA numDoors
  BEQ mc_nodoor
  STY mcTmp                     \ the character index within the tile
  LDA cellY : LSR A : LSR A : STA doorTileRow
  LDA #0    : STA dtOfs
  LDA cellX : LSR A : LSR A     \ tile column; cellX+1 is always 0 here
  JSR DoorTdp
  LDY mcTmp
.mc_nodoor
  LDA (tdp),Y
  RTS

\ ============================================================
\ RedrawAll — fill the whole viewport from the current position
\ ============================================================
.RedrawAll
  LDA #0 : STA rCount
  LDA mapYr : STA cellY

.ra_row
  CLC                           \ row start = BUF_BASE + scrollS + row*640
  LDA scrollS   : ADC rowOfs   : STA bufp
  LDA scrollS+1 : ADC rowOfs+1 : STA bufp+1
  CLC
  LDA bufp   : ADC #LO(BUF_BASE) : STA bufp
  LDA bufp+1 : ADC #HI(BUF_BASE) : STA bufp+1
  JSR WrapBufFwd

  LDA mapHX   : STA halfX
  LDA mapHX+1 : STA halfX+1
  LDA #0 : STA uCount

.ra_unit
  JSR DrawHalf
  INC halfX
  BNE ra_nohx
  INC halfX+1
.ra_nohx
  CLC                           \ next 4-pixel column
  LDA bufp : ADC #UNIT_BYTES : STA bufp
  BCC ra_nohi
  INC bufp+1
.ra_nohi
  JSR WrapBufFwd
  INC uCount
  LDA uCount
  CMP #PLAY_UNITS
  BNE ra_unit

  CLC                           \ next character row
  LDA rowOfs   : ADC #LO(ROW_BYTES) : STA rowOfs
  LDA rowOfs+1 : ADC #HI(ROW_BYTES) : STA rowOfs+1
  INC cellY
  INC rCount
  LDA rCount
  CMP #PLAY_ROWS
  BEQ ra_done
  JMP ra_row
.ra_done
  LDA #0 : STA rowOfs : STA rowOfs+1

\ Sixteen whole rows from mapYr IS the strip's invariant now — display
\ row r holds map row mapYr+r entire — so this is a true repair at any
\ scroll position and needs no split-row pass after it. That makes it
\ a valid oracle to diff the incremental scrolling against at any
\ value of `line`, which it was not while the strip aliased map rows
\ mapYr and mapYr+16 into display row 0.
  RTS
