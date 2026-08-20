\ ============================================================
\ dbgpanel.asm — the debug readouts, in BANK 6
\ ============================================================
\ Everything that prints numbers onto the status panel: the frame
\ counter, the position bookmark, the combat line, and the 4x5 digit
\ font all three share.
\ IT IS IN BANK 6 BECAUSE IT DID NOT FIT ANYWHERE ELSE. DEBUG_VSYNC
\ alone is 143 bytes and the code image has eleven, so for weeks the
\ flag silently pushed `PARA` past &3000 and into the first bytes of
\ PARAFNT — a corrupt player sprite and an unreadable digit, and no
\ assembly error, because `CLEAR FONT_ADDR, ...` had released the
\ overwrite guard over exactly that range. See the GUARD in main.asm.
\ Bank 6 is the right home rather than merely a free one: this draws on
\ the panel, and the panel's own code is here. The shims that page it in
\ are in src/lowcode2.asm.
\ THE ONE RULE: nothing here may read BANK 4, because bank 6 is what is
\ paged while it runs. Everything below reads main RAM or zero page —
\ except DbgEnergyOut's droid type and energy, which are entry 0 of the
\ droid table in bank 4 and reach it through dbgEnMirror, filled by the
\ shim before it pages. DEBUG_MAPGUARD's five bytes go the same way.

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
.Dbg6FrameCount
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
\ swSrc/swDst are borrowed. They are NOT dead outside the startup bank
\ copy, which this comment used to claim: panel.asm aliases them as
\ pnSrc/pnDst for every string it prints, and droid.asm takes them as
\ mgSrc/mgRef under DEBUG_MAPGUARD. What makes the borrow safe is that
\ all of them are transient scratch inside one routine, and this runs
\ from the MAIN LOOP and not the IRQ, so no two uses interleave.
\ Anything wanting to hold a value in them across a call would break.
\
\ NOT COMPATIBLE WITH DEBUG_VSYNC — both write the top-left digit.
.Dbg6PosOut
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
.Dbg6EnergyOut
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
  EQUB LO(dbgEnMirror+0), LO(dbgEnMirror+1), LO(maxEnergy)
  EQUB LO(weaponType), LO(alertLvl)
  EQUB LO(score+0), LO(score+1), LO(score+2), LO(score+3)
IF DEBUG_MAPGUARD
  EQUB LO(dbgEnMirror+2), LO(dbgEnMirror+4), LO(dbgEnMirror+5), LO(dbgEnMirror+6), LO(dbgEnMirror+7)
ENDIF
.dbgEnSrcHi
  EQUB HI(dbgEnMirror+0), HI(dbgEnMirror+1), HI(maxEnergy)
  EQUB HI(weaponType), HI(alertLvl)
  EQUB HI(score+0), HI(score+1), HI(score+2), HI(score+3)
IF DEBUG_MAPGUARD
  EQUB HI(dbgEnMirror+2), HI(dbgEnMirror+4), HI(dbgEnMirror+5), HI(dbgEnMirror+6), HI(dbgEnMirror+7)
ENDIF
.dbgEnGap
  EQUB 1, 1, 1
  EQUB 1, 1
  EQUB 0, 0, 0, 1
IF DEBUG_MAPGUARD
  EQUB 1, 0, 1, 0, 1
ENDIF
IF DEBUG_MAPGUARD
DBG_EN_N = 14
ELSE
DBG_EN_N = 9
ENDIF
ENDIF
