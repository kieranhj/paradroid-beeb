\ ============================================================
\ rupture.asm — three CRTC cycles per frame
\ ============================================================
\ panel (static) / play (scrolled) / tail (VSync, nothing shown).
\ Reprogramming R4 mid-frame ends a cycle early; the next cycle
\ reloads VMA from R12/R13, so each cycle has its own screen start.
\ Geometry and timing constants live in main.asm — see the note
\ there for the frame layout and why there are three cycles.
\
\ Smooth vertical scrolling rides on this: R5 gives the play cycle
\ `line` extra scanlines and takes them back from the panel cycle,
\ so the play cycle starts `line` scanlines earlier and the picture
\ scrolls by less than a character row. The scanlines either side
\ of the intended 128 are real and wrong, so R8 blanks them.
\
\ WHEN EACH REGISTER MUST BE WRITTEN — they are not all the same,
\ and getting this wrong is silent:
\
\   R4   inside its own cycle, before C4 reaches the new value.
\        Not earlier: the previous cycle would trip over it.
\   R7   inside the PREVIOUS cycle. Writing it at the row it is
\        meant to fire on is too late — that row's compare has
\        already happened, VSync never comes, and the CRTC
\        free-runs on whatever the last cycle shape was.
\   R6   inside the PREVIOUS cycle. The vertical display enable is
\        a flip-flop cleared when the row counter reaches R6; once
\        cleared, raising R6 does not bring it back for that cycle.
\   R12/13  inside the PREVIOUS cycle — latched at cycle start.
\   R5   any time before the cycle's END, where it is sampled.
\ ============================================================

\ Blanking is suppressed under DEBUG_RASTER so the timing bands
\ stay visible — see main.asm.
IF DEBUG_RASTER
  R8_OFF = R8_ON
ELSE
  R8_OFF = R8_BLANK
ENDIF

\ NEVER write R5 near the END of a cycle. The vertical adjust
\ counts up and compares against R5; changing R5 once the count has
\ passed the new value means the match never happens and the adjust
\ runs on until the 5-bit counter wraps — ~29 extra scanlines. That
\ is why the play cycle's R5 is written at fire 3 and not at fire 2:
\ fire 2 sits within a scanline of the panel cycle's adjust ending,
\ and landing the wrong side of it stretched the panel cycle from
\ 64 scanlines to 85. R5's legal window is the whole cycle, so
\ there is no reason to write it anywhere near the edge.

\ ============================================================
\ RuptInit
\ ============================================================
.RuptInit
  LDA #0
  STA ruptState
  STA line
  STA iline
  RTS

\ ============================================================
\ RuptVSync — IRQ on CA1, at P+272, row 8 of the tail cycle
\ ============================================================
.RuptVSync
IF DEBUG_RASTER
  LDA #5 : JSR DbgSetBg         \ magenta from here down
ENDIF
\ The tail cycle's own R4 and R5. It is 8 rows in, so R4 = 12 is
\ still ahead of C4. Its R6 and R7 were set at fire 3, last cycle.
  LDA #4  : STA CRTC_ADDR : LDA #TAIL_R4 : STA CRTC_DATA
  LDA #5  : STA CRTC_ADDR : LDA #0       : STA CRTC_DATA

\ R6 for the PANEL cycle, which starts in 40 scanlines. The tail
\ displays nothing, so raising it now costs nothing there.
  LDA #6  : STA CRTC_ADDR : LDA #PANEL_ROWS : STA CRTC_DATA

\ Unblank for the panel, which starts in 40 scanlines. Safe to do
\ now: the tail displays nothing either way.
  LDA #8  : STA CRTC_ADDR : LDA #R8_ON   : STA CRTC_DATA

\ R12/R13 for the panel cycle, latched when it starts at P+312.
  LDA #12 : STA CRTC_ADDR : LDA #HI(PANEL_START) : STA CRTC_DATA
  LDA #13 : STA CRTC_ADDR : LDA #LO(PANEL_START) : STA CRTC_DATA

\ Restart T1 (writing T1C-H transfers the latch and starts it), then
\ immediately re-latch with the NEXT interval, which the counter
\ picks up when it reloads at fire 1.
  LDA #LO(T1_I1) : STA SYS_VIA_T1LL
  LDA #HI(T1_I1) : STA SYS_VIA_T1CH
  LDA #LO(T1_I2) : STA SYS_VIA_T1LL
  LDA #HI(T1_I2) : STA SYS_VIA_T1LH

  LDA #0
  STA ruptState
  RTS

\ ============================================================
\ RuptTimer — IRQ on T1
\ ============================================================
.RuptTimer
  LDA ruptState
  BEQ rt_panel
  CMP #1
  BEQ rt_play
  CMP #2
  BNE rt_none
  JMP rt_drawok
.rt_none
  RTS                           \ any later fire: nothing to do

\ ---- fire 1, P+44: inside the panel cycle -------------------
.rt_panel
IF DEBUG_RASTER
  LDA #2 : JSR DbgSetBg         \ green from here down
ENDIF
\ Blank first. From here to fire 2 the play cycle may already have
\ started (it does, by up to 7 scanlines) and what it shows in that
\ sliver is the wrong map row.
  LDA #8  : STA CRTC_ADDR : LDA #R8_OFF     : STA CRTC_DATA

\ Take the sub-row offset from the same park as R12/R13, at the same
\ moment R12/R13 is read, so the two can never come from different
\ frames. Holds for the rest of this frame: fire 3 uses it too.
  LDA pline
  STA iline

  LDA #4  : STA CRTC_ADDR : LDA #PANEL_R4 : STA CRTC_DATA

\ No VSync in the panel or play cycles. The panel's own display
\ ended 4 scanlines ago, so R6 is free to become the play cycle's.
  LDA #7  : STA CRTC_ADDR : LDA #255      : STA CRTC_DATA
  LDA #6  : STA CRTC_ADDR : LDA #PLAY_R6  : STA CRTC_DATA

\ R5 for the panel cycle, sampled at its end 12 scanlines from now.
\ Computed straight into the data register — sTmp belongs to
\ SetCRTCStart, which this interrupt can land in the middle of.
  LDA #5  : STA CRTC_ADDR
  SEC
  LDA #8
  SBC iline
  STA CRTC_DATA

\ R12/R13 for the play cycle, latched when it starts at P+64-line.
  LDA #12 : STA CRTC_ADDR : LDA crtcHi : STA CRTC_DATA
  LDA #13 : STA CRTC_ADDR : LDA crtcLo : STA CRTC_DATA

  LDA #LO(T1_I3) : STA SYS_VIA_T1LL
  LDA #HI(T1_I3) : STA SYS_VIA_T1LH

  LDA #1
  STA ruptState
  RTS

\ ---- fire 2, P+64: the visible top edge ---------------------
\ Must land in horizontal blanking — see T1_TUNE.
.rt_play
  LDA #8  : STA CRTC_ADDR : LDA #R8_ON     : STA CRTC_DATA
IF DEBUG_RASTER
  LDA deck                      \ restore this deck's real background
  ASL A : ASL A
  TAY
  LDA deckPalette,Y
  JSR DbgSetBg
ENDIF
\ R4 only. The play cycle's R5 goes at fire 3, well clear of the
\ panel cycle's vertical adjust, which ends within a scanline of
\ here. R4 is safe either side of that boundary: written during an
\ adjust it just sits waiting for the next cycle.
  LDA #4  : STA CRTC_ADDR : LDA #PLAY_R4 : STA CRTC_DATA

  LDA #2
  STA ruptState
  RTS

\ ---- fire 3, P+192: the visible bottom edge -----------------
\ The play area stops displaying exactly here, so this is both the
\ bottom blank and the earliest safe moment to release the main
\ loop. Deadline for the redraw is the play cycle starting again,
\ 184 scanlines away.
.rt_drawok
  LDA #8  : STA CRTC_ADDR : LDA #R8_OFF    : STA CRTC_DATA
IF DEBUG_RASTER
  LDA #4 : JSR DbgSetBg         \ blue from here down
ENDIF
\ R5 for the PLAY cycle, whose adjust is 8 scanlines away — close
\ enough to be this frame's, far enough not to be a knife edge.
  LDA #5  : STA CRTC_ADDR : LDA iline     : STA CRTC_DATA

\ R6 and R7 for the TAIL cycle, which starts in 2 rows. R7 must be
\ set here and not at VSync: by the time the tail reaches row 8 the
\ compare that generates VSync has already been made.
  LDA #6  : STA CRTC_ADDR : LDA #0        : STA CRTC_DATA
  LDA #7  : STA CRTC_ADDR : LDA #TAIL_R7  : STA CRTC_DATA

\ COUNT the window rather than flagging it. A flag is a boolean and
\ boolean state coalesces: work that runs past two of these sets it
\ twice and the loop can only see one, so it consumes a stale release
\ and then blocks for the next — turning a small overrun into a whole
\ extra field. A counter cannot lose one, and the loop compares
\ against it rather than consuming it. See WaitUntilField.
  INC fieldCount
  LDA #3
  STA ruptState
  RTS

\ ============================================================
\ FillPanel — placeholder title area: a bordered box
\ Real artwork comes with the title/HUD layer.
\ ============================================================
.FillPanel
  LDA #LO(PANEL_ADDR) : STA bufp
  LDA #HI(PANEL_ADDR) : STA bufp+1
  LDY #0
  LDA #0
  LDX #HI(PANEL_BYTES)          \ clear whole pages
.fp_page
  STA (bufp),Y
  INY
  BNE fp_page
  INC bufp+1
  DEX
  BNE fp_page
.fp_tail
  STA (bufp),Y                  \ + the remainder
  INY
  CPY #LO(PANEL_BYTES)
  BNE fp_tail

\ top and bottom edges of the box
  LDA #LO(PANEL_ADDR) : STA bufp
  LDA #HI(PANEL_ADDR) : STA bufp+1
  JSR fp_hline
  LDA #LO(PANEL_ADDR + (PANEL_ROWS-1)*ROW_BYTES + 7) : STA bufp
  LDA #HI(PANEL_ADDR + (PANEL_ROWS-1)*ROW_BYTES + 7) : STA bufp+1
  JSR fp_hline

\ left and right edges
  LDA #LO(PANEL_ADDR) : STA bufp
  LDA #HI(PANEL_ADDR) : STA bufp+1
  LDA #&88                      \ leftmost pixel of the byte
  JSR fp_vline
  LDA #LO(PANEL_ADDR + 79*8) : STA bufp
  LDA #HI(PANEL_ADDR + 79*8) : STA bufp+1
  LDA #&11                      \ rightmost pixel
  JSR fp_vline
  RTS

.fp_hline                       \ 80 units, 8 bytes apart
  LDY #0
  LDX #PLAY_UNITS
.fh_loop
  LDA #&FF
  STA (bufp),Y
  TYA
  CLC : ADC #8
  TAY
  BCC fh_nohi
  INC bufp+1
.fh_nohi
  DEX
  BNE fh_loop
  RTS

.fp_vline                       \ A = pixel pattern, down all panel rows
  STA fv_pat+1
  LDX #PANEL_ROWS
.fv_row
  LDY #0
.fv_scan
.fv_pat
  LDA #0                        \ operand patched above
  STA (bufp),Y
  INY
  CPY #8
  BNE fv_scan
  CLC
  LDA bufp   : ADC #LO(ROW_BYTES) : STA bufp
  LDA bufp+1 : ADC #HI(ROW_BYTES) : STA bufp+1
  DEX
  BNE fv_row
  RTS

IF DEBUG_RASTER OR DEBUG_DRAW
\ ============================================================
\ DbgSetBg — background (logical 0) to physical colour A
\ Four entries because in a 4-colour mode the palette CAM only
\ matches bits 7 and 5, so bits 6 and 4 need every combination.
\ ============================================================
.DbgSetBg
  EOR #7                        \ the ULA wants it inverted
  STA dbgTmp
  LDA #&00 : ORA dbgTmp : STA VIDEO_ULA_PAL
  LDA #&10 : ORA dbgTmp : STA VIDEO_ULA_PAL
  LDA #&40 : ORA dbgTmp : STA VIDEO_ULA_PAL
  LDA #&50 : ORA dbgTmp : STA VIDEO_ULA_PAL
  RTS
.dbgTmp EQUB 0

\ Back to the deck's own background, ending whichever band was open.
.DbgDeckBg
  LDA deck
  ASL A : ASL A
  TAY
  LDA deckPalette,Y
  JMP DbgSetBg
ENDIF

IF DEBUG_VSYNC OR DEBUG_POS
\ ============================================================
\ DbgFrameCount — fields per main-loop iteration, top-left of the panel
\ ============================================================
\ vsyncCount is already bumped once per field by IrqHandler's CA1 arm,
\ so the reading is just the difference across one iteration. Called
\ immediately after WaitField returns, where that boundary has just
\ happened, so the digit describes the iteration that has finished.
\
\ ONE BYTE PER SCANLINE IS THE WHOLE TRICK. A MODE 1 byte is four
\ pixels and consecutive bytes within a character cell are consecutive
\ scanlines, so a 4x5 digit is five bytes at five consecutive
\ addresses — five loads and five stores, no masking, no row stride,
\ and nothing to save or restore because the panel does not scroll.
\
\ Nine or more all read as 9: the point is to notice an overrun, and by
\ the time an iteration is taking nine fields the exact number is not
\ the interesting part.
.DbgFrameCount
  LDA vsyncCount
  TAX                           \ this iteration's mark, for next time
  SEC
  SBC dbgLastVs
  STX dbgLastVs
  CMP #10
  BCC dfc_digit
  LDA #9
.dfc_digit
  TAX
  LDA dbgMul5,X
  TAX
  LDA dbgFont+0,X : STA PANEL_ADDR+0
  LDA dbgFont+1,X : STA PANEL_ADDR+1
  LDA dbgFont+2,X : STA PANEL_ADDR+2
  LDA dbgFont+3,X : STA PANEL_ADDR+3
  LDA dbgFont+4,X : STA PANEL_ADDR+4
  RTS

.dbgLastVs EQUB 0
ENDIF

IF DEBUG_VSYNC OR DEBUG_POS OR DEBUG_ENERGY
\ The digit font, shared by all three readouts — DbgFrameCount above,
\ DbgHexDigit below. Guarded separately from DbgFrameCount so that a
\ DEBUG_ENERGY-only build does not assemble the frame counter it never
\ calls.
.dbgMul5   EQUB 0,5,10,15,20,25,30,35,40,45,50,55,60,65,70,75

\ 4x5 digits, one row per byte. A row is four pixels: bit 3 is the
\ leftmost. Logical colour 3 wants both of a pixel's bits set, and
\ those sit four apart in a MODE 1 byte, so the pattern goes in both
\ nibbles — which is exactly what multiplying by 17 does.
DBG_PX = 17
.dbgFont
  EQUB %1111 * DBG_PX, %1001 * DBG_PX, %1001 * DBG_PX, %1001 * DBG_PX, %1111 * DBG_PX
  EQUB %0100 * DBG_PX, %1100 * DBG_PX, %0100 * DBG_PX, %0100 * DBG_PX, %1110 * DBG_PX
  EQUB %1111 * DBG_PX, %0001 * DBG_PX, %1111 * DBG_PX, %1000 * DBG_PX, %1111 * DBG_PX
  EQUB %1111 * DBG_PX, %0001 * DBG_PX, %0111 * DBG_PX, %0001 * DBG_PX, %1111 * DBG_PX
  EQUB %1001 * DBG_PX, %1001 * DBG_PX, %1111 * DBG_PX, %0001 * DBG_PX, %0001 * DBG_PX
  EQUB %1111 * DBG_PX, %1000 * DBG_PX, %1111 * DBG_PX, %0001 * DBG_PX, %1111 * DBG_PX
  EQUB %1111 * DBG_PX, %1000 * DBG_PX, %1111 * DBG_PX, %1001 * DBG_PX, %1111 * DBG_PX
  EQUB %1111 * DBG_PX, %0001 * DBG_PX, %0010 * DBG_PX, %0100 * DBG_PX, %0100 * DBG_PX
  EQUB %1111 * DBG_PX, %1001 * DBG_PX, %1111 * DBG_PX, %1001 * DBG_PX, %1111 * DBG_PX
  EQUB %1111 * DBG_PX, %1001 * DBG_PX, %1111 * DBG_PX, %0001 * DBG_PX, %1111 * DBG_PX
\ A-F, so a byte can be read straight off the screen as hex.
  EQUB %0110 * DBG_PX, %1001 * DBG_PX, %1111 * DBG_PX, %1001 * DBG_PX, %1001 * DBG_PX
  EQUB %1110 * DBG_PX, %1001 * DBG_PX, %1110 * DBG_PX, %1001 * DBG_PX, %1110 * DBG_PX
  EQUB %0111 * DBG_PX, %1000 * DBG_PX, %1000 * DBG_PX, %1000 * DBG_PX, %0111 * DBG_PX
  EQUB %1110 * DBG_PX, %1001 * DBG_PX, %1001 * DBG_PX, %1001 * DBG_PX, %1110 * DBG_PX
  EQUB %1111 * DBG_PX, %1000 * DBG_PX, %1110 * DBG_PX, %1000 * DBG_PX, %1111 * DBG_PX
  EQUB %1111 * DBG_PX, %1000 * DBG_PX, %1110 * DBG_PX, %1000 * DBG_PX, %1000 * DBG_PX
ENDIF

IF DEBUG_POS OR DEBUG_ENERGY
\ ============================================================
\ DbgHexDigit — A = 0-15, printed at swDst; swDst moves on one column
\ ============================================================
\ Shared by DbgPosOut and DbgEnergyOut. Successive digits are eight
\ bytes apart, which is the next 4-pixel column — see the note in
\ CLAUDE.md about adjacent columns being 8 bytes apart, not 1.
.DbgHexDigit
  TAX
  LDA dbgMul5,X
  TAX
  LDY #0
.dhd_row
  LDA dbgFont,X
  STA (swDst),Y
  INX
  INY
  CPY #5
  BNE dhd_row
  CLC
  LDA swDst : ADC #UNIT_BYTES : STA swDst
  BCC dhd_x
  INC swDst+1
.dhd_x
  RTS

\ A = the byte, printed as two digits.
.DbgHexByte
  PHA
  LSR A : LSR A : LSR A : LSR A
  JSR DbgHexDigit
  PLA
  AND #&0F
  JMP DbgHexDigit

.dbgIdx EQUB 0
ENDIF

\ ruptState, fieldCount, crtcHi/crtcLo and line/pline/iline are all in
\ zero page — see the block in main.asm. Everything here is read or
\ written inside the interrupt handler, three fires a frame, so it is
\ handler latency as much as throughput.

IF DEBUG_POS
\ ============================================================
\ DbgPosOut — the state needed to get back to a spot, in the panel
\ ============================================================
\ Reproducing a reported bug used to mean re-walking the route: about a
\ dozen emulator round trips for BUGS.md #5, far more than reading the
\ state would have cost. This is the position bookmark that entry asked
\ for, finally affordable — it waited on main RAM, and the level draw
\ moving into bank 4 freed 2.4K.
\
\ Eighteen bytes as thirty-six HEX digits along the top of the panel,
\ rewritten every pass. Read them straight off the screen or a
\ screenshot; no tooling either end, which is the point.
\
\   deck  plyX  posX  posY  mapHX  mapYr line  nDoor
\   then door 0 and door 1 as col,row,state
\
\ The panel does not scroll and nothing else draws there, so there is
\ nothing to save or restore. A digit is five bytes at five consecutive
\ addresses — one byte per scanline — and successive digits are eight
\ bytes apart, which is the next 4-pixel column.
\
\ swSrc/swDst are borrowed: they belong to the startup bank copy and
\ are dead from LoadDeck onwards. Nothing else in a pass touches them.
\
\ NOT COMPATIBLE WITH DEBUG_VSYNC — both write the top-left digit.
.DbgPosOut
  LDA #LO(PANEL_ADDR) : STA swDst
  LDA #HI(PANEL_ADDR) : STA swDst+1
  LDY #0
.dpo_next
  STY dbgIdx
  LDA dbgSrcLo,Y : STA swSrc
  LDA dbgSrcHi,Y : STA swSrc+1
  LDY #0
  LDA (swSrc),Y
  JSR DbgHexByte
  LDY dbgIdx
  LDA dbgSrcGap,Y               \ a blank column between fields
  BEQ dpo_nogap
  CLC
  LDA swDst : ADC #UNIT_BYTES : STA swDst
  BCC dpo_nogap
  INC swDst+1
.dpo_nogap
  LDY dbgIdx
  INY
  CPY #DBG_POS_N
  BNE dpo_next
  RTS

\ What to print, in order. Low byte first would read backwards on
\ screen, so the 16-bit ones are listed high byte first.
.dbgSrcLo
  EQUB LO(deck)
  EQUB LO(plyX+1),  LO(plyX)
  EQUB LO(posX+1),  LO(posX)
  EQUB LO(posY+1),  LO(posY)
  EQUB LO(scrollS+1), LO(scrollS)
  EQUB LO(mapHX+1), LO(mapHX)
  EQUB LO(mapYr),   LO(line)
  EQUB LO(sprPtr0Hi), LO(sprPtr0Lo), LO(sprScan0), LO(sprNoWrapS)
  EQUB LO(numDoors)
  EQUB LO(doorCol),   LO(doorRow),   LO(doorState)
.dbgSrcHi
  EQUB HI(deck)
  EQUB HI(plyX+1),  HI(plyX)
  EQUB HI(posX+1),  HI(posX)
  EQUB HI(posY+1),  HI(posY)
  EQUB HI(scrollS+1), HI(scrollS)
  EQUB HI(mapHX+1), HI(mapHX)
  EQUB HI(mapYr),   HI(line)
  EQUB HI(sprPtr0Hi), HI(sprPtr0Lo), HI(sprScan0), HI(sprNoWrapS)
  EQUB HI(numDoors)
  EQUB HI(doorCol),   HI(doorRow),   HI(doorState)

\ 1 = leave a blank column after this byte, so the fields are readable
\ rather than one 42-digit run. Costs four pixels each and the strip
\ still fits: 42 digits and 11 gaps is 212 of the 320 across.
.dbgSrcGap
  EQUB 1
  EQUB 0, 1
  EQUB 0, 1
  EQUB 0, 1
  EQUB 0, 1
  EQUB 0, 1
  EQUB 1, 1
  EQUB 0, 0, 1, 1
  EQUB 1
  EQUB 0, 0, 1
DBG_POS_N = 21
ENDIF

IF DEBUG_ENERGY
\ ============================================================
\ DbgEnergyOut — the player's combat state, second panel row
\ ============================================================
\ Layer 7a. The panel is Layer 9's and holds a placeholder box, so
\ there is nowhere the game itself shows energy, alert or score — which
\ makes every stage of Layer 7 unverifiable by eye without this. Nine
\ bytes as eighteen hex digits:
\
\   type  energy maxEnergy  weapon  alert  score(4, BCD)
\
\ Row 1 of the panel rather than row 0, so DEBUG_VSYNC's frame digit
\ and DEBUG_POS's bookmark both stay readable alongside it. The panel
\ does not scroll and nothing else draws there, so there is nothing to
\ save or restore.
\
\ drType and drEnergy are entry 0 of the droid table, which lives in
\ BANK 4. Safe to read from main RAM here because SWRAM_DATA is the
\ resting state and this is called from the main loop, after
\ DroidsUpdate has already returned to it.
\
\ swSrc/swDst are borrowed exactly as DbgPosOut borrows them: they
\ belong to the startup bank copy and are dead from LoadDeck onwards.
.DbgEnergyOut
  LDA #LO(PANEL_ADDR + ROW_BYTES) : STA swDst
  LDA #HI(PANEL_ADDR + ROW_BYTES) : STA swDst+1
  LDY #0
.deo_next
  STY dbgIdx
  LDA dbgEnSrcLo,Y : STA swSrc
  LDA dbgEnSrcHi,Y : STA swSrc+1
  LDY #0
  LDA (swSrc),Y
  JSR DbgHexByte
  LDY dbgIdx
  LDA dbgEnGap,Y                \ a blank column between fields
  BEQ deo_nogap
  CLC
  LDA swDst : ADC #UNIT_BYTES : STA swDst
  BCC deo_nogap
  INC swDst+1
.deo_nogap
  LDY dbgIdx
  INY
  CPY #DBG_EN_N
  BNE deo_next
  RTS

.dbgEnSrcLo
  EQUB LO(drType), LO(drEnergy), LO(maxEnergy)
  EQUB LO(weaponType), LO(alertLvl)
  EQUB LO(score+0), LO(score+1), LO(score+2), LO(score+3)
.dbgEnSrcHi
  EQUB HI(drType), HI(drEnergy), HI(maxEnergy)
  EQUB HI(weaponType), HI(alertLvl)
  EQUB HI(score+0), HI(score+1), HI(score+2), HI(score+3)
.dbgEnGap
  EQUB 1, 1, 1
  EQUB 1, 1
  EQUB 0, 0, 0, 1
DBG_EN_N = 9
ENDIF
