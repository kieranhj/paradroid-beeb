\ ============================================================
\ lowcode.asm — resident code in the reclaimed DFS workspace
\ ============================================================
\ ASSEMBLED AT &0E00 AND STAGED THROUGH &3000. Nothing here may be
\ loaded in place: &0E00-&10FF is the sideways-ROM shared workspace and
\ DFS is using it while it delivers this very file. main.asm's LOW_ADDR
\ header has the argument and the page-&0D exclusion.
\
\ THE RULES FOR WHAT MAY LIVE HERE:
\   - it is MAIN RAM, so bank 4 may JSR in and so may the code image;
\   - it may read bank 4 (drType, tiledefs, LUTs, charSrc) only where
\     SWRAM_DATA is paged, which is the resting state and therefore true
\     everywhere in the main loop — but NOT inside SprDrawAll and NOT at
\     boot before PARADAT lands. Same one-way rule as bufcore.asm's;
\   - it is DEAD until PageLowIn has run, which is after the four banks
\     and before PARAFNT. Nothing may call in before that.
\
\ It exists because main RAM &1100-&3000 was down to 48 free bytes and
\ bank 4 to 10, and the two banks with room are both paged out during
\ play. See docs/layer-12-anim-disruptor.md.

\ ============================================================
\ DrawTileCells — repaint some of one 4x4 tile's characters
\ ============================================================
\ The generic form of what DrawDoorTile used to be, and it now serves
\ both: the scroll only ever draws the leading edge, so anything that
\ changes while the view is still — a door opening, a recharger's
\ pointers turning, the alert lamp changing colour — has to repaint
\ itself. Cells outside the view are skipped; they come out right
\ whenever they scroll in, because the band and column paths read the
\ same definitions and the same charset.
\
\ Cold code. Each half-character is copied separately with a wrap
\ between, which sidesteps the "a wrap must not fall inside a character"
\ condition COPYCHAR depends on.
\
\ Inputs, all set by the caller:
\   dtcCol   tile column, 0-63
\   dtcRow   tile row, 0-15
\   dtcDefOp+1/+2   -> the 16 character codes (a tile definition, or a
\                      door's patched copy of one)
\   dtcListOp+1/+2  -> the cell indices to draw, 0-15, &FF terminated
.DrawTileCells
  LDA dtcCol
  ASL A : ASL A                 \ tile column * 4 = character column
  STA dtcCharX
  LDA dtcRow
  ASL A : ASL A
  STA dtcCharY
  LDA #0
  STA dtcIdx

.dtc_next
  LDY dtcIdx
.dtcListOp
  LDA &FFFF,Y
  BMI dtc_done
  STA dtcCell
  INC dtcIdx

  LSR A : LSR A                 \ cell >> 2 = its row within the tile
  CLC
  ADC dtcCharY
  SEC
  SBC mapYr                     \ mapYr is SIGNED and the row may be off
  CMP #PLAY_ROWS                \ the map; one unsigned test catches both
  BCS dtc_next
  STA rCount

  LDA dtcCell
  AND #3                        \ and its column within the tile
  CLC
  ADC dtcCharX
  STA dtcTmp
  LDA #0
  STA dtcTmp+1
  ASL dtcTmp : ROL dtcTmp+1     \ characters -> units
  SEC
  LDA dtcTmp   : SBC mapHX   : STA dtcTmp
  LDA dtcTmp+1 : SBC mapHX+1
  BNE dtc_next                  \ left of the view, or past 255
  LDA dtcTmp
  CMP #PLAY_UNITS-1
  BCS dtc_next                  \ the right half would fall outside
  STA uCount

  LDY dtcCell
.dtcDefOp
  LDA &FFFF,Y
  TAX
  LDA CHAR_PTR_LO,X : STA chp
  LDA CHAR_PTR_HI,X : STA chp+1

  JSR SetCell                   \ left half
  LDY #7
.dtc_l
  LDA (chp),Y : STA (bufp),Y
  DEY
  BPL dtc_l

  CLC                           \ right half, eight bytes on
  LDA chp : ADC #8 : STA chp
  BCC dtc_nc
  INC chp+1
.dtc_nc
  JSR BufNextUnit
  LDY #7
.dtc_r
  LDA (chp),Y : STA (bufp),Y
  DEY
  BPL dtc_r
  JMP dtc_next

.dtc_done
  RTS

\ ---- the cell lists ----------------------------------------
\ A door repaints all sixteen. The recharger's eight are the cells of
\ TILE 20 that hold characters 76-79, and the alert lamp's two are the
\ cells of TILE 22 that hold character $16 — both read straight off the
\ C64's tile definitions, not chosen by eye.
.dtcCellsAll
  EQUB 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, &FF
.dtcCellsRech
  EQUB 1, 2, 4, 7, 8, 11, 13, 14, &FF
.dtcCellsLamp
  EQUB 9, 10, &FF

\ ---- CollisionType ($6D6D), transcribed whole --------------
\ IT IS HERE AND NOT IN BANK 4 because bank 4 had seven bytes left. Its
\ reader, DrCollided, is bank-4 code and reads it as plain main RAM.
\ Index = the mode of the party being acted on, times eight, plus the
\ mode of the other: 0 a droid, 1 an enemy bullet, 2 an explosion, 3 the
\ player's shot. Modes 4-7 cannot happen and are the original's own
\ padding.
\   $80 nothing      $40 explode        $20 friendly fire
\   $10 free it      $08 reverse/pause  $04 player fire     $02 nothing
.drCollType
  EQUB 8,   &20, &20, 4,   &80, &80, &80, &80  \ a DROID, hit by...
  EQUB &10, &40, &40, &40, &80, &80, &80, &80  \ an enemy BULLET
  EQUB &80, &80, &80, &80, &80, &80, &80, &80  \ an EXPLOSION: nothing
  EQUB 2,   2,   2,   &80, &80, &80, &80, &80  \ the PLAYER'S shot

\ ============================================================
\ AnimTick / AnimPaint — the animated tiles, once a pass
\ ============================================================
\ Port of AnimAllInsideFont ($38C4), which the C64 calls from GameLoop
\ at $1401. There it rotates four consecutive character bitmaps inside
\ the font every other frame and the screen follows for free, because
\ the font IS the screen's source. Ours is not: characters are blitted
\ into the play buffer when they scroll in, so the rotation has to be
\ followed by repainting whatever is on screen already. That is the one
\ mechanical difference, and it is forced.
\
\ ChrAnimData1 ($6C23) names TWO groups, at $7A60 and $7BD0: characters
\ 76-79 and 122-125. Only the first is ported, because 122-125 are not
\ referenced by any of the 32 tile definitions and so are not in the
\ 137-character set export_bbc.py builds. 76-79 are the four turning
\ pointers around the recharge pad, tile 20.
\
\ THE ROTATION IS DONE TO THE CHARSET, not to the character codes in
\ the map, so every draw path agrees automatically: a pad that scrolls
\ in mid-animation comes in at the phase everything else is showing, and
\ RedrawAll stays a valid oracle.
\
\ SPLIT IN THREE, and WHERE each piece runs is the whole point.
\
\ THE SCAN IS THE EXPENSIVE ONE and it used to run at the front of
\ window A. Measured 2026-08-20: 10,060 cycles of a 24,576-cycle window,
\ on a pass where it found nothing at all — 41% of the only window the
\ drawing has, spent reading the map. So AnimScanPass runs AFTER the
\ draw, in the play area's own display period, and fills the list for
\ the NEXT pass. One pass of latency, the same trade the droid AI took;
\ see docs/raster-timing.md.
\
\ AnimTick is what is left in the window: the rotation, and nothing
\ else. It has to stay ahead of every draw because it changes the
\ charset the draws read.
\
\ AnimPaint runs after the level draw, inside the same window everything
\ else writes the buffer in, over the list the last pass built.
\
\ THE LAMP WENT WITH THE SCAN, because whether the lamp has moved is
\ what decides whether the signs need scanning, and that question has to
\ be answered on the same side of the draw as the scan it gates. What it
\ costs is that BuildLampChar now rebuilds the character after this
\ pass's level draw rather than before it, so a sign scrolling in on the
\ pass the lamp changes shows the old colour for one pass and AnimPaint
\ corrects it on the next. 40 ms, once per change of alert state.
.AnimTick
  LDA gameTick                  \ $38C4: every other frame, and on the
  AND #1                        \ C64 that is every other ITERATION
  BNE ant_done
  JSR AnimRotate
.ant_done
  LDA animDirty                 \ what the LAST pass's scan found
  RTS

\ ---- AnimScanPass — build the list for the next pass --------
\ The parity is inverted against AnimTick's on purpose: this runs at the
\ end of the pass BEFORE the one that will rotate, so it asks whether
\ gameTick is odd rather than even.
.AnimScanPass
  LDA #0
  STA animCount
  STA animDirty

  LDA gameTick
  AND #1
  BEQ asp_lamp
  LDA #20                       \ the recharge pad
  STA animWant
  JSR AnimScan

.asp_lamp
  JSR AnimLamp                  \ has the alert lamp's colour moved?
  BEQ asp_done
  LDA #22                       \ the ALERT sign
  STA animWant
  JSR AnimScan
.asp_done
  RTS

\ ---- AnimPaint — repaint what AnimScan found ---------------
\ Two cell lists, because the two tiles animate in different places.
\ animKind separates them: 0 = a recharger, 1 = a sign.
.AnimPaint
  LDA animCount
  BEQ anp_x
.anp_loop
  DEC animCount
  LDX animCount
  LDA animCol,X : STA dtcCol
  LDA animRow,X : STA dtcRow

  LDA animKind,X
  BNE anp_lamp
  LDA #LO(dtcCellsRech) : STA dtcListOp+1
  LDA #HI(dtcCellsRech) : STA dtcListOp+2
  LDA #LO(tiledefs + 20 * 16) : STA dtcDefOp+1
  LDA #HI(tiledefs + 20 * 16) : STA dtcDefOp+2
  JMP anp_go
.anp_lamp
  LDA #LO(dtcCellsLamp) : STA dtcListOp+1
  LDA #HI(dtcCellsLamp) : STA dtcListOp+2
  LDA #LO(tiledefs + 22 * 16) : STA dtcDefOp+1
  LDA #HI(tiledefs + 22 * 16) : STA dtcDefOp+2
.anp_go
  JSR DrawTileCells
  LDA animCount
  BNE anp_loop
.anp_x
  RTS

\ ---- AnimScan — which tiles of type animWant are in view ----
\ Eleven tile columns from the left edge and all sixteen rows: the
\ column arithmetic wraps and the row arithmetic does not, so the rows
\ are cheaper to test inside DrawTileCells than to prefilter here.
\ 176 map bytes read on a tick pass, which is 1.6% of a pass amortised
\ over the two.
\
\ THE LIST IS BOUNDED. Eight entries covers the worst deck in view —
\ deck 11 has seven pads and deck 10 six signs, none of them clustered
\ within one window — and an overflow drops the extra tile rather than
\ scribbling past the array.
.AnimScan
  LDA mapHX+1                   \ mapHX >> 3: units -> tiles
  STA dtcTmp+1
  LDA mapHX
  STA dtcTmp
  LSR dtcTmp+1 : ROR dtcTmp
  LSR dtcTmp+1 : ROR dtcTmp
  LSR dtcTmp+1 : ROR dtcTmp
  LDA dtcTmp
  AND #MAP_COLS-1
  STA ansCol

  LDA #11
  STA ansLeft
.ans_col
  LDA #MAP_ROWS-1
  STA ansRow
.ans_row
  LDX ansRow                    \ tilemap + row * 64 + col. maprow is the
  LDA mapRowLo,X : STA maprow   \ band draw's own zero-page pointer and is
  LDA mapRowHi,X : STA maprow+1 \ dead here — AnimTick runs ahead of it
  LDY ansCol
  LDA (maprow),Y
  CMP animWant
  BNE ans_next

  LDX animCount
  CPX #ANIM_MAX
  BCS ans_next
  LDA ansCol : STA animCol,X
  LDA ansRow : STA animRow,X
  LDA animWant
  CMP #22
  BEQ ans_sign
  LDA #0
  BEQ ans_kind
.ans_sign
  LDA #1
.ans_kind
  STA animKind,X
  INC animCount
  LDA #1
  STA animDirty

.ans_next
  DEC ansRow
  BPL ans_row
  INC ansCol
  LDA ansCol
  AND #MAP_COLS-1               \ the map wraps horizontally
  STA ansCol
  DEC ansLeft
  BNE ans_col
  RTS

\ ---- AnimRotate — the four recharger characters, forward ----
\ $38D3's pointer set, unrolled: character n+3 takes n+2, n+2 takes
\ n+1, n+1 takes n, and n takes what n+3 held. The C64 patches eight
\ absolute operands to do it because its four are consecutive in the
\ font; ours are wherever charRemap put them, so the addresses come out
\ of CHAR_PTR_LO/HI — which BuildCharPtrs fixed at startup and nothing
\ has moved since.
.AnimRotate
  LDX #RECH_CHAR + 3            \ stash the last one
  JSR AnimSetSrc
  LDY #CHAR_BYTES-1
.anr_save
  LDA (chp),Y
  STA animSave,Y
  DEY
  BPL anr_save

  LDX #RECH_CHAR + 2 : LDY #RECH_CHAR + 3 : JSR AnimCopy
  LDX #RECH_CHAR + 1 : LDY #RECH_CHAR + 2 : JSR AnimCopy
  LDX #RECH_CHAR + 0 : LDY #RECH_CHAR + 1 : JSR AnimCopy

  LDX #RECH_CHAR                \ and the stash into the first
  JSR AnimSetDst
  LDY #CHAR_BYTES-1
.anr_put
  LDA animSave,Y
.anrStOp
  STA &FFFF,Y
  DEY
  BPL anr_put
  RTS

\ X = source character code, Y = destination character code.
.AnimCopy
  TYA                           \ the stack, not a byte of lowbss: &0C90 is
  PHA                           \ 112 bytes and DEBUG_ENERGY's mirror wanted
  JSR AnimSetSrc                \ the last one
  PLA
  TAX
  JSR AnimSetDst
  LDY #CHAR_BYTES-1
.anc_loop
  LDA (chp),Y
.ancStOp
  STA &FFFF,Y
  DEY
  BPL anc_loop
  RTS

\ chp = the charset bytes for character X. chp is the draw path's own
\ pointer and is dead here: AnimTick runs before any of it.
.AnimSetSrc
  LDA CHAR_PTR_LO,X : STA chp
  LDA CHAR_PTR_HI,X : STA chp+1
  RTS

\ and the destination, into both self-modified stores.
.AnimSetDst
  LDA CHAR_PTR_LO,X
  STA ancStOp+1
  STA anrStOp+1
  LDA CHAR_PTR_HI,X
  STA ancStOp+2
  STA anrStOp+2
  RTS

\ ============================================================
\ AnimLamp / BuildLampChar — the ALERT sign's indicator
\ ============================================================
\ BUGS.md #13. Character $16 is the lamp inside the ALERT sign, and it
\ appears twice in row 2 of tile 22. On the C64 its colour does not come
\ from the deck's scheme at all:
\
\     InitColors      $2835  LDA Alert / ROL A x3 / AND #3 / TAY
\                     $283D  LDA AlertColors,Y
\                     $2840  STA CharColor+$16
\     DoAlertAndAging $3E38  the same again, live, as Alert moves
\
\ AlertColors ($6D45) is E5 E7 E8 E2 — green, yellow, orange, red — so
\ the lamp runs up a four-step ramp as the ship gets angrier. Ours read
\ the slot the C64 leaves lying past the end of its 12-byte record and
\ clamped it, which is the incidental behaviour rather than the
\ deliberate one, and the lamp was dead.
\
\ [DECISION] MODE 1 HAS NO FOURTH COLOUR TO GIVE IT. The port's four
\ logicals have fixed roles — 0 the deck's background, 1 black, 2 the
\ deck's highlight, 3 white — and every one of them is already spoken
\ for by the artwork and the sprites, so green/yellow/orange/red cannot
\ all exist at once. What the lamp CAN have is its own logical, because
\ character $16 is the only user of its colour slot. So the ramp is
\ ported as four states rather than four hues:
\
\     Alert >> 6   C64        here
\     0            green      logical 1, black — the lamp is unlit
\     1            yellow     logical 2, the deck's highlight
\     2            orange     logical 3, white
\     3            red        white, BLINKING against black every 8 passes
\
\ The blink is the deviation that buys the fourth state, and it is the
\ one thing here that is not in the original. Ratify or replace — a flat
\ three-state ramp is one line (drop the level-3 arm).
.AnimLamp
  LDA alertLvl
  ROL A : ROL A : ROL A         \ $2835 exactly: Alert >> 6, in three
  AND #3                        \ rotates and a mask
  TAX
  LDA lampInk,X
  STA lampWant
  CPX #3
  BNE anl_test
  LDA gameTick                  \ red alert blinks — see the decision above
  AND #8
  BEQ anl_test
  LDA #LAMP_OFF
  STA lampWant
.anl_test
  LDA lampWant
  CMP lampHave
  BEQ anl_none
  STA lampHave
  JSR BuildLampChar
  LDA #1                        \ and the sign wants repainting
  RTS
.anl_none
  LDA #0
  RTS

\ ---- AnimReset — a new deck has rebuilt the charset ---------
\ Called from LoadDeck, after BuildCharset. That put character $16 back
\ on its clamped slot colour, so whatever the lamp last held is no
\ longer what is in the charset and the comparison above would skip the
\ rebuild. &FF is a colour no ramp entry can be.
\ IT ALSO EMPTIES THE LIST. That did not matter while the scan and the
\ paint were in the same pass; now the list is built at the end of one
\ pass and painted in the next, so a deck load between the two would
\ repaint the old deck's cells onto the new one's map.
.AnimReset
  LDA #&FF
  STA lampHave
  LDA #0
  STA animCount
  STA animDirty
  RTS

\ ---- BuildLampChar — one character, one chosen logical ------
\ BuildCharset's inner loop for a single character, reusing the deck's
\ LUTs (which it left behind) and its zero-page pointers (which are the
\ deck-load and band-draw temporaries, both dead this early in a pass).
\   A = the logical colour, 0-3
.BuildLampChar
  ASL A : ASL A : ASL A : ASL A \ the LUT for that foreground colour
  STA bcLutOfs

  LDX #ALERT_LAMP_CHAR          \ the source bitmap: charSrc + index * 8
  LDA charRemap,X
  STA lampTmp
  LDA #0
  STA lampTmp+1
  ASL lampTmp : ROL lampTmp+1
  ASL lampTmp : ROL lampTmp+1
  ASL lampTmp : ROL lampTmp+1
  CLC
  LDA lampTmp   : ADC #LO(charSrc) : STA bcSrc
  LDA lampTmp+1 : ADC #HI(charSrc) : STA bcSrc+1

  LDX #ALERT_LAMP_CHAR          \ and the destination, both halves
  LDA CHAR_PTR_LO,X : STA bcDst
  LDA CHAR_PTR_HI,X : STA bcDst+1
  CLC
  LDA bcDst   : ADC #8 : STA bcDst2
  LDA bcDst+1 : ADC #0 : STA bcDst2+1

  LDY #7
.blc_row
  LDA (bcSrc),Y
  PHA
  LSR A : LSR A : LSR A : LSR A \ high nibble -> the left half
  CLC : ADC bcLutOfs
  TAX
  LDA LUTs,X
  STA (bcDst),Y
  PLA
  AND #&0F                      \ low nibble -> the right half
  CLC : ADC bcLutOfs
  TAX
  LDA LUTs,X
  STA (bcDst2),Y
  DEY
  BPL blc_row
  RTS

ALERT_LAMP_CHAR = &16           \ CharColor+$16, the two dots in tile 22
LAMP_OFF = 1                    \ logical 1 is black on every deck

.lampInk    EQUB 1, 2, 3, 3     \ by alert level; 3 also blinks

\ The mutable state is NOT here. It is in src/lowbss.asm at &0C90 —
\ another piece of the same reclaimed workspace, and uninitialised, so
\ it costs the PARALOW file nothing. Everything in it is written before
\ it is read: AnimTick clears the counters, AnimReset seeds lampHave.
