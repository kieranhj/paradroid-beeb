\ ============================================================
\ console.asm — the console, in the play area
\ ============================================================
\ LAYER 9c, in SWRAM BANK 6 with panel.asm whose text engine it uses.
\ Like that file it CANNOT READ BANK 4 — the droid tables it prints come
\ from the PN_TABS mirror and shipLevel/drCount from pmShip/pmCount.
\ Standing on a console character and pressing fire suspends the game and
\ turns the PLAY AREA into a text screen. Up/down move through the pages,
\ L leaves.
\
\ IT IS NOT THE C64'S FULL-SCREEN CONSOLE, and that is decision 6 in
\ docs/layer-9-hud.md. There, conRedraw ($2C25) calls GotoHires, repaints
\ the whole display and draws the menu as hardware sprites. Ours is three
\ CRTC cycles with a scrolled 10K strip in the middle, and suspending
\ that is a bigger change than this layer should carry. Taking the play
\ area instead costs nothing: it is 40 characters by 15 rows, which is
\ SEVEN lines of the 8 x 16 font, and leaving the panel up keeps the
\ status visible — which is what the C64 does too, since GotoHires does
\ not touch its status rows either.
\
\ THE PLAY BUFFER IS A CIRCULAR STRIP and the console does not want to
\ think about that, so ConsoleOpen forces scrollS and line to zero first.
\ Buffer row r is then flatly BUF_BASE + r * ROW_BYTES with no wrap, and
\ ConsoleClose calls ReframeView, which puts the scroll back under the
\ player and repaints the deck. Nothing else has to be undone — it is the
\ same call CbCheckDeath makes after a respawn, for the same reason.

CON_LINES = PLAY_VIS_ROWS DIV 2 \ 15 rows of two-row glyphs
ASSERT CON_LINES == 7

CON_PAGES = 2                   \ the ship, then the droid database

\ 24, declared here because DR_TYPES lives in the SPRITE bank's generated
\ data and beebasm resolves constants in file order — bank 4 is assembled
\ first. main.asm asserts the two agree once both are known.
CON_TYPES = 24

\ ============================================================
\ ConAt — point pnDst at console text cell (pnLine, pnCol)
\ ============================================================
\ The play buffer's flat form, valid only because ConsoleOpen zeroed the
\ scroll. Line n starts at buffer row 2n. The row step is a loop rather
\ than a multiply because there are seven of them and it runs once per
\ string, not once per glyph.
.ConAt
  LDA #PN_INK_TEXT              \ as PnAt does: the panel's red fields must
  STA pnMask                    \ not leak into the console's text

  LDA pnCol                     \ col * 16
  ASL A : ASL A : ASL A : ASL A
  STA pnDst
  LDA pnCol
  LSR A : LSR A : LSR A : LSR A
  STA pnDst+1
  CLC
  LDA pnDst   : ADC #LO(BUF_BASE) : STA pnDst
  LDA pnDst+1 : ADC #HI(BUF_BASE) : STA pnDst+1

  LDX pnLine
  BEQ con_at_x
.con_at_row
  CLC
  LDA pnDst   : ADC #LO(2*ROW_BYTES) : STA pnDst
  LDA pnDst+1 : ADC #HI(2*ROW_BYTES) : STA pnDst+1
  DEX
  BNE con_at_row
.con_at_x
  RTS

\ ConStr — PnStr against the console instead of the panel.
\ The two differ only in which At routine they call, and duplicating
\ eighteen bytes is cheaper than threading a target through PnStr.
.ConStr
  LDA pnStrLo : STA con_s_get+1
  LDA pnStrHi : STA con_s_get+2
  JSR ConAt
  LDA #0
  STA pnTmp
.con_s_loop
  LDY pnTmp
.con_s_get
  LDA &FFFF,Y
  BEQ con_s_x
  JSR PnAscii
  JSR PnWide
  INC pnTmp
  BNE con_s_loop
.con_s_x
  RTS

\ ConNum — PnNum against the console. PnDigits is PnNum's tail, split out
\ so the two share the repeated-subtraction loop.
.ConNum
  STA pnVal
  JSR ConAt
  JMP PnDigits

\ ============================================================
\ ConClear — blank the play area
\ ============================================================
\ PLAY_VIS_ROWS rows, not the strip's 16: the last row is the one the
\ smooth vertical scroll uses and it is never displayed at line = 0,
\ which ConsoleOpen has just forced.
\ A ROW IS 640 BYTES, WHICH IS TWO PAGES AND A HALF — 2 x 256 + 128 —
\ and the first version cleared one page and the 128, left the last 256
\ of every row standing, and stepped 512 instead of 640. The deck showed
\ through the right-hand third of the console. Hence the explicit three
\ blocks and the row base kept in pnTmpW rather than walked.
.ConClear
  LDA #LO(BUF_BASE) : STA pnDst
  LDA #HI(BUF_BASE) : STA pnDst+1
  LDX #PLAY_VIS_ROWS
.con_c_row
  LDA pnDst   : STA pnTmpW
  LDA pnDst+1 : STA pnTmpW+1
  LDY #0
  LDA #0
.con_c_b0
  STA (pnDst),Y
  INY
  BNE con_c_b0
  INC pnDst+1
.con_c_b1
  STA (pnDst),Y
  INY
  BNE con_c_b1
  INC pnDst+1
.con_c_b2
  STA (pnDst),Y
  INY
  CPY #LO(ROW_BYTES)
  BNE con_c_b2
  CLC                           \ next row from the base, not from here
  LDA pnTmpW   : ADC #LO(ROW_BYTES) : STA pnDst
  LDA pnTmpW+1 : ADC #HI(ROW_BYTES) : STA pnDst+1
  DEX
  BNE con_c_row
  RTS

\ ============================================================
\ ConsoleOpen — take the play area
\ ============================================================
\ Called from DoCharUnder's console arm, which is the C64's own trigger:
\ character 66 under the player, and fire.
.ConsoleOpen
  LDA #1
  STA conActive
  LDA #0
  STA conPage
  STA scrollS                   \ flatten the strip for ConAt
  STA scrollS+1
  STA line
  STA iline
  STA xSpd : STA xSpd+1         \ he is standing at a console, not walking
  STA ySpd : STA ySpd+1
  STA bandDo                    \ nothing the last move exposed is wanted
  STA colCount
  LDA #1
  STA conPrevL                  \ the press that opened it is still down
  JSR SetCRTCStart
  JMP ConDraw

\ ============================================================
\ ConsoleClose — give it back
\ ============================================================
.ConsoleClose
  LDA #0
  STA conActive
  JMP ReframeView

\ ============================================================
\ ConsoleRun — one pass with the console up
\ ============================================================
\ Up and down step the page, L leaves. All three are edge triggered on
\ their own previous state and not on the main loop's prevRet/prevUp,
\ which belong to the lift, the weapon and the debug deck hop — sharing
\ them would make leaving the console fire the gun on the way out.
.ConsoleRun
  LDX #KEY_L
  JSR keydown
  BNE con_r_lup
  LDA conPrevL
  BNE con_r_down                \ still held from opening, or from last pass
  LDA #1 : STA conPrevL
  JMP ConsoleClose
.con_r_lup
  LDA #0 : STA conPrevL
.con_r_down

  LDX #KEY_DOWN
  JSR keydown
  BNE con_r_dup
  LDA conPrevD
  BNE con_r_up
  LDA #1 : STA conPrevD
  LDA conPage
  CLC : ADC #1
  CMP #CON_PAGES
  BCC con_r_set
  LDA #0
  BEQ con_r_set                 \ always
.con_r_dup
  LDA #0 : STA conPrevD
.con_r_up

  LDX #KEY_UP
  JSR keydown
  BNE con_r_uup
  LDA conPrevU
  BNE con_r_x
  LDA #1 : STA conPrevU
  LDA conPage
  BNE con_r_dec
  LDA #CON_PAGES
.con_r_dec
  SEC : SBC #1
.con_r_set
  STA conPage
  JMP ConDraw
.con_r_uup
  LDA #0 : STA conPrevU
.con_r_x
  RTS

\ ============================================================
\ ConDraw — repaint the current page
\ ============================================================
.ConDraw
  JSR ConClear
  LDA conPage
  BEQ ConDrawShip
  JMP ConDrawDroids

\ ---- page 0: the ship ---------------------------------------
\ ConsoleMain ($2955) draws "Access granted", then the ship name, the
\ deck name and the alert level. The ship and deck NAMES are token
\ strings out of $6900 that Layer 11 needs anyway; until those are
\ ported this shows the numbers behind them.
.ConDrawShip
  LDA #0 : STA pnLine
  LDA #2 : STA pnCol
  LDA #LO(conTxtAccess) : STA pnStrLo
  LDA #HI(conTxtAccess) : STA pnStrHi
  JSR ConStr

  LDA #2 : STA pnLine
  LDA #2 : STA pnCol
  LDA #LO(conTxtShip) : STA pnStrLo
  LDA #HI(conTxtShip) : STA pnStrHi
  JSR ConStr
  LDA #2  : STA pnLine
  LDA #12 : STA pnCol
  LDA #2  : STA pnDigits
  LDA pmShip
  JSR ConNum

  LDA #3 : STA pnLine
  LDA #2 : STA pnCol
  LDA #LO(conTxtDeck) : STA pnStrLo
  LDA #HI(conTxtDeck) : STA pnStrHi
  JSR ConStr
  LDA #3  : STA pnLine
  LDA #12 : STA pnCol
  LDA #2  : STA pnDigits
  LDA deck
  JSR ConNum

  LDA #4 : STA pnLine
  LDA #2 : STA pnCol
  LDA #LO(conTxtLeft) : STA pnStrLo
  LDA #HI(conTxtLeft) : STA pnStrHi
  JSR ConStr
  LDA #4  : STA pnLine
  LDA #12 : STA pnCol
  LDA #2  : STA pnDigits
  LDA pmCount
  BEQ con_d_lhave
  SEC : SBC #1                  \ entry 0 is the player, not a droid
.con_d_lhave
  JSR ConNum

  LDA #6 : STA pnLine
  LDA #2 : STA pnCol
  LDA #LO(conTxtKeys) : STA pnStrLo
  LDA #HI(conTxtKeys) : STA pnStrHi
  JMP ConStr

\ ---- page 1: the droid database -----------------------------
\ Every type the ship carries, with its number, its weapon class and its
\ speed. THIS IS THE PAGE THE GAME IS PLAYED FROM: the whole economy is
\ deciding what to transfer into next, and the three numbers that decide
\ it are all already in this bank.
\
\ Two columns of twelve, so the whole roster is one page rather than a
\ list that has to be scrolled. DR_TYPES is 24.
.ConDrawDroids
  LDA #0 : STA pnLine
  LDA #1 : STA pnCol
  LDA #LO(conTxtHdr) : STA pnStrLo
  LDA #HI(conTxtHdr) : STA pnStrHi
  JSR ConStr

  LDA #0
  STA conType
.con_d_loop
\ FOUR COLUMNS OF SIX, and the shape is forced: 24 types against six
\ usable lines. Two columns needs twelve lines and there are seven, so
\ the first version ran the last six entries off the bottom of the play
\ buffer and into sideways RAM. line = type/4 + 1 tops out at 6, which is
\ CON_LINES-1, and that is the whole bound.
  LDA conType
  LSR A : LSR A
  CLC : ADC #1
  STA pnLine
  LDA conType                   \ col = 10 * (type MOD 4)
  AND #3
  ASL A
  STA pnTmp
  ASL A : ASL A
  CLC : ADC pnTmp
  STA pnCol
  JSR ConAt

  LDY conType                   \ the three-digit number
  LDA pnTabCent,Y
  CLC : ADC #PN_DIGIT0
  JSR PnGlyph
  LDY conType
  LDA pnTabNum,Y
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #PN_DIGIT0
  JSR PnGlyph
  LDY conType
  LDA pnTabNum,Y
  AND #&0F
  CLC : ADC #PN_DIGIT0
  JSR PnGlyph

  LDA #PN_SPACE : JSR PnGlyph
  LDY conType                   \ weapon class, 0-3; 3 is the disruptor
  LDA pnTabWeapon,Y
  CLC : ADC #PN_DIGIT0
  JSR PnGlyph

  LDA #PN_SPACE : JSR PnGlyph
  LDY conType                   \ whole pixels a pass
  LDA pnTabSpeed,Y
  CLC : ADC #PN_DIGIT0
  JSR PnGlyph

  INC conType
  LDA conType
  CMP #CON_TYPES
  BNE con_d_loop
  RTS

.conTxtAccess EQUS "Access granted" : EQUB 0
.conTxtShip   EQUS "Ship"           : EQUB 0
.conTxtDeck   EQUS "Deck"           : EQUB 0
.conTxtLeft   EQUS "Droids"         : EQUB 0
.conTxtKeys   EQUS "Up Down page  L exits" : EQUB 0
.conTxtHdr    EQUS "Droid Weapon Speed" : EQUB 0

\ conActive is NOT here: it is in main.asm, because ConsoleTick has to
\ read it after paging this bank back out. See the bridge there.
.conPage   EQUB 0
.conType   EQUB 0
.conPrevL  EQUB 0
.conPrevU  EQUB 0
.conPrevD  EQUB 0
