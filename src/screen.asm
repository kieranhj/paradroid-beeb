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
\ ============================================================
\ DoorTdp — point tdp at this tile's patched copy, if it has one
\ ============================================================
\ A = tile column, doorTileRow = tile row. Carry set on return means
\ tdp was rewritten. The caller has ALREADY built the ordinary tdp, so
\ a miss costs only the search and leaves it alone.
\
\ Callers test `LDA numDoors : BEQ` first, so the common case — no door
\ open anywhere on the deck — never reaches here at all.
\
\ dtOfs is added to the base: the band folds its sub-row offset into
\ tdp, the column path and MapChar do not.
\ X IS PRESERVED, and that is not tidiness: ProbeGroup keeps the probe
\ index in X across its call to MapChar, which is one of the callers.
.DoorTdp
  STA dtCol
  STX dtSaveX
  LDX numDoors
  DEX
.dt_find
  LDA doorCol,X
  CMP dtCol
  BNE dt_next
  LDA doorRow,X
  CMP doorTileRow
  BEQ dt_hit
.dt_next
  DEX
  BPL dt_find
  LDX dtSaveX
  CLC
  RTS

.dt_hit
  CLC
  LDA doorMul16,X               \ <= 96, plus dtOfs <= 12: cannot carry
  ADC dtOfs
  ADC #LO(doorDef)
  STA tdp
  LDA #HI(doorDef)
  ADC #0
  STA tdp+1
  LDX dtSaveX
  SEC
  RTS

\ ============================================================
\ DoorCopyDef — door.asm's, rehoused here 2026-08-29
\ ============================================================
\ IT IS HERE FOR THE RAM, NOT FOR THE TIDINESS: the code image had to
\ find 51 bytes for the resident ZX0 depacker (main.asm's .Zx0Unpack,
\ which replaced both the bank-4 copy and the PARDEPK one), and this
\ routine is exactly 51. It is beside tdpLo/tdpHi deliberately — those
\ are what it reads, they are bank 4's, and so it could never have run
\ with another bank paged anyway. Its one caller is door.asm's dp_new,
\ main-RAM play-path code with SWRAM_DATA resting. door.asm keeps the
\ header explaining where it went.
.DoorCopyDef
  STX dpSlot
  LDY dpRow
  LDA mapRowLo,Y : STA maprow
  LDA mapRowHi,Y : STA maprow+1
  LDY dpCol
  LDA (maprow),Y                \ tile number
  TAY
  LDA tdpLo,Y : STA tdp
  LDA tdpHi,Y : STA tdp+1

  LDA doorMul16,X
  CLC
  ADC #15
  TAX                           \ destination index, walking down
  LDY #15
.dcd_loop
  LDA (tdp),Y
  STA doorDef,X
  DEX
  DEY
  BPL dcd_loop
  RTS

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
\ DbgRedrawKey — CTRL+R: the oracle redraw
\ ============================================================
\ The main loop's debug redraw, moved out of the code image on
\ 2026-08-31 and given a CTRL. Both halves matter:
\ IT NEEDS CTRL because the six play controls are redefinable now
\ (Layer 11f) and R is a key like any other: bind LEFT to R and every
\ step left would repaint the whole viewport. Every debug key took the
\ same treatment — C, [, ] and W — and CTRL costs nothing to test,
\ keydown asking the matrix about one key at a time.
\ IT IS UNDER DEBUG_REDRAW as of 2026-08-31, which is the agreed
\ decision the previous version of this note said it would take (KC).
\ The flag is DEV, so the oracle is still there in every ordinary
\ build -- it is what every scrolling bug so far has been found with --
\ and a RELEASE build has no way to reach it at all. main.asm's flag
\ block is where the recipe for using it lives.
IF DEBUG_REDRAW
.DbgRedrawKey
  LDX #KEY_CTRL
  JSR keydown
  BNE dbr_x
  LDX #KEY_R
  JSR keydown
  BNE dbr_x
  JMP RedrawAll                 \ and its RTS
.dbr_x
  RTS
ENDIF

\ ============================================================
\ RedrawAll — fill the whole viewport from the current position
\ ============================================================
.RedrawAll
  JSR SetPalette                \ THE DECK'S OWN COLOURS BACK. The console
                                \ and the information screens swap logical 0
                                \ for a text background (SetTextPal), and
                                \ every way back to the deck ends in a full
                                \ redraw — ReframeView's JMP here. Putting it
                                \ at the top of the redraw rather than in each
                                \ exit path costs one JSR and cannot be
                                \ forgotten by a new one. Layer 14 DECISION 4
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

\ ============================================================
\ SetupPlain — the rupture down, WITHOUT a VDU 22
\ ============================================================
\ LAYER 11f. GoTitle used to call SetupMode, whose first act is a
\ VDU 22 — and the OS answers that by clearing &3000-&7FFF. That threw
\ away the 999 page and the font, which is why PARAFNT had to be
\ reloaded and why the high-score entry could not be an overlay: there
\ was no instant at which the page was on screen AND a load was legal.
\
\ KC, 2026-08-21: the mode change does not need the OS. The palette,
\ the CRTC and the wraparound latch are all ours already and are set
\ once at boot; VDU 22 was only ever supplying R4-R7 and R12/R13, and
\ clearing screen RAM as a side effect we did not want. So this is
\ those six registers and nothing else. **The play buffer and the font
\ both survive it**, and VSync comes back, so the filing system works.
\
\ IT IS IN BANK 4 AND THAT IS FREE: GoTitle already runs with
\ SWRAM_DATA paged — it calls SndSilence two instructions earlier — so
\ `JSR SetupMode` simply became `JSR SetupPlain` and main RAM, which
\ has five bytes left, paid nothing.
\
\ R0-R3, R8 and R9 are NOT touched. Nothing has changed them since
\ boot's own VDU 22: the rupture rewrites R4-R7 and R12/R13 every
\ field and leaves the rest alone.
\ A TABLE, not six CRTC macros: the macro is ten bytes a register and
\ bank 4 had sixty left. Ascending register order, because R6, R7 and
\ R12/R13 are latched for the NEXT cycle and should be in step with the
\ R4/R5 that defines it.
.SetupPlain
  LDX #0
.sp_reg
  LDA spReg,X : STA CRTC_ADDR
  LDA spVal,X : STA CRTC_DATA
  INX
  CPX #7
  BNE sp_reg

\ AND THE LAST DECK'S PALETTE, deliberately: the front end inherits it
\ (KC, 2026-08-22). Without this the ULA holds whichever REGION palette
\ the rupture wrote last before UninstallIrq — palPanel or palPlay by
\ raster luck — so the 999 page, the entry screen and the title were
\ mostly deck-coloured and occasionally panel-coloured. This makes it
\ always the deck's. palPlay is main RAM (rupture.asm) and survives the
\ teardown; its assembled default covers the path before any deck has
\ loaded.
  LDX #15
.sp_pal
  LDA palPlay,X
  STA VIDEO_ULA_PAL
  DEX
  BPL sp_pal
  RTS

\ R8 IS IN HERE AND IT IS NOT OPTIONAL. The rupture blanks rows with it
\ — GoWashStart's note about "the R8 blank at fire 3" hiding the
\ sixteenth row is the same register — so a teardown that leaves it set
\ gives a black screen with everything else perfectly correct. Measured:
\ without this entry the 999 page was in the buffer, the CRTC was
\ pointed at it, and nothing displayed at all.
.spReg
  EQUB 4, 5, 6, 7, 8, 12, 13
.spVal
  EQUB PLAIN_R4                 \ a plain 39-row, 312-line, 50 Hz frame
  EQUB 0
  EQUB 0                        \ R6 = 0: the frame is BLANK (KC,
                                \ 2026-08-22). Nothing wants this display
                                \ visible any more — the entry screen
                                \ brings its own rupture — and a plain
                                \ window over the strip showed each
                                \ load's wreckage. SetupRupture or
                                \ TiCRTC give the display back
  EQUB PLAIN_R7                 \ VSync alive, which the loads need
  EQUB 0                        \ R8: no blanking, no interlace
  EQUB HI(BUF_BASE / 8)         \ R12/13 park on the play buffer; moot
  EQUB LO(BUF_BASE / 8)         \ while R6 shows nothing
