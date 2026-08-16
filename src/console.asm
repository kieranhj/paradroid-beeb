\ ============================================================
\ console.asm — the console, in the play area
\ ============================================================
\ LAYER 9c, in SWRAM BANK 6 with panel.asm whose text engine it uses.
\ Like that file it CANNOT READ BANK 4 — the droid tables it prints come
\ from the PN_TABS mirror and shipLevel/drCount from pmShip/pmCount.
\ Standing on a console character and pressing fire suspends the game and
\ turns the PLAY AREA into a text screen. L leaves.
\
\ IT IS NOT THE C64'S FULL-SCREEN CONSOLE, and that is decision 6 in
\ docs/layer-9-hud.md. There, conRedraw ($2C25) calls GotoHires, repaints
\ the whole display and draws the menu as hardware sprites. Ours is three
\ CRTC cycles with a scrolled 10K strip in the middle, and suspending
\ that is a bigger change than this layer should carry. Taking the play
\ area instead costs nothing: it is 40 characters by 15 rows, and the
\ original's five lines fit in thirteen of them with room to spare — see
\ the layout below. Leaving the panel up keeps the status visible, which
\ is what the C64 does too, since GotoHires does not touch its status
\ rows either.
\
\ THE PLAY BUFFER IS A CIRCULAR STRIP and the console does not want to
\ think about that, so ConsoleOpen forces scrollS and line to zero first.
\ Buffer row r is then flatly BUF_BASE + r * ROW_BYTES with no wrap, and
\ ConsoleClose calls ReframeView, which puts the scroll back under the
\ player and repaints the deck. Nothing else has to be undone — it is the
\ same call CbCheckDeath makes after a respawn, for the same reason.

\ 24, declared here because DR_TYPES lives in the SPRITE bank's generated
\ data and beebasm resolves constants in file order — bank 4 is assembled
\ first. main.asm asserts the two agree once both are known.
CON_TYPES = 24

\ ---- the layout, which is ConsoleMain's ($2955) --------------
\ The original draws five lines, and the strings carry their own prntY and
\ prntX — $6E00, $6E12, $6E1C, $6E26 and UnitType_txt at $6B77:
\
\   C64 row 10, col 2    " Unit type 001 - Influence Device"
\   C64 row 12, col 12   "Access granted."
\   C64 row 15, col 12   "Ship  : " + the ship name
\   C64 row 18, col 12   "Deck  : " + the deck name
\   C64 row 21, col 12   "Alert : " + the alert level
\
\ Its console area starts at screen row 8, so those are deck rows 2, 4, 7,
\ 10 and 13 — and rows 0 and 1 are empty. **KC: plot from the top row**,
\ so everything moves up by two and the five lines land on buffer rows
\ 0, 2, 5, 8 and 11 of our fifteen, with three to spare at the bottom.
\ The 2/3/3/3 spacing is the original's and is what leaves a blank row
\ between the lower four.
CON_ROW_UNIT  = 0
CON_ROW_ACC   = 2
CON_ROW_SHIP  = 5
CON_ROW_DECK  = 8
CON_ROW_ALERT = 11
ASSERT CON_ROW_ALERT + 2 <= PLAY_VIS_ROWS

CON_COL_UNIT  = 2               \ UnitType_txt's own prntX
CON_COL_TEXT  = 12              \ and $6E00's

\ ---- token numbers into the $C000 string table ---------------
\ ShowRobotType ($3149) and ConsoleMain ($2955) index it with these.
CON_TOK_SEP    = 50             \ "- ", between the number and the name
CON_TOK_CLASS  = 10             \ robot / droid / cyborg
CON_TOK_DEVICE = 55             \ "device", for the 001 alone
CON_TOK_SHIP   = 105            \ eight, by (shipLevel - 1) AND 7
CON_TOK_DECK   = 122            \ sixteen, by deck
CON_TOK_ALERT  = 208            \ green, yellow, amber, red

\ ---- the four menu icons ------------------------------------
\ conRedraw's sprite table at $6B94 puts them at Y $90, $AC, $C8 and $E0
\ and X $34, $34, $28, $28. Sprite Y 144 is 11.75 character rows down a
\ display whose first visible line is 50, and the four text lines are at
\ rows 12, 15, 18 and 21 — so each icon sits level with a line, three
\ rows apart, which is exactly the spacing of the four lower lines here.
\ They therefore go on OUR rows 2, 5, 8 and 11, one per line, and the
\ last ends at row 13 of fifteen.
\ X IS IN 4-PIXEL UNITS, not characters. Sprite X 52 and 40 are 28 and 16
\ pixels from the left edge, which is 7 and 4 units — not a whole number
\ of characters either way, and it does not need to be: the buffer's
\ natural step is the 8-byte 4-pixel column. The two indents are the
\ original's; a menu with its icons in one column would not be.
\ SPRITES 3 AND 4 ARE X-EXPANDED. SpriteXExp is byte 8 of their records
\ and it is $FF for both, 0 for the other two — the eleven bytes map onto
\ SpriteNum ($04) through SpriteImage ($0E), so the field is not a guess.
\ They are FORTY-EIGHT pixels wide on screen, not 24. SpriteMC is 0 on all
\ four, so none of them is multicolour, and SpriteYExp is 0, so all four
\ stay 21 scanlines.
\ THE DOUBLING HAPPENS AS THEY ARE DRAWN, not in the data. Baking it in
\ costs 288 bytes and bank 6 does not have them — it overflowed by the
\ time both wide icons were stored expanded. Doubling four pixels to
\ eight is two lookups in a sixteen-entry table, and an icon is drawn
\ once per console.
CON_ICON_COUNT = 3              \ of four — see conicons.asm
CON_ICON_ROWS  = 3              \ 21 scanlines, so three character rows
CON_ICON_RB    = 6 * UNIT_BYTES \ source bytes a row: six 4-pixel columns

\ ============================================================
\ ConAt — point pnDst at console text cell (conRow, pnCol)
\ ============================================================
\ The play buffer's flat form, valid only because ConsoleOpen zeroed the
\ scroll.
\
\ conRow IS A BUFFER ROW, NOT A TEXT LINE. The original's five lines are
\ 2, 3, 3, 3 rows apart, not 2 — an 8x16 glyph is two rows and the lower
\ four have a blank row between them — so a line-times-two index cannot
\ express the layout. The row step is a loop rather than a multiply
\ because it runs once per string, not once per glyph.
.ConAt
\ THE CONSOLE IS WHITE, and the panel's ink is not. Logical 1 is physical
\ 7 on every one of the sixteen decks, where logical 3 varies and is
\ BLACK on several of them — the console lives in the play area and takes
\ the deck's palette, so it is the only reliably light colour available.
\ Setting it here also stops the panel's red score leaking in.
  LDA #PN_INK_WHITE
  STA pnMask

  LDA pnCol                     \ col * 16
  ASL A : ASL A : ASL A : ASL A
  STA pnDst
  LDA pnCol
  LSR A : LSR A : LSR A : LSR A
  STA pnDst+1
  CLC
  LDA pnDst   : ADC #LO(BUF_BASE) : STA pnDst
  LDA pnDst+1 : ADC #HI(BUF_BASE) : STA pnDst+1

  LDX conRow
  BEQ con_at_x
.con_at_row
  CLC
  LDA pnDst   : ADC #LO(ROW_BYTES) : STA pnDst
  LDA pnDst+1 : ADC #HI(ROW_BYTES) : STA pnDst+1
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
\ L LEAVES, AND NOTHING ELSE HAPPENS. The original's four menu icons are
\ selectable — conWaitInput ($2C63) walks consoleState between $80 and
\ $83 with up/down, recolours the selected sprite and dispatches through
\ conJump_t on fire — and none of that is built. The icons are drawn and
\ inert. See docs/layer-9-hud.md.
\
\ The key is edge triggered on its own previous state and not on the main
\ loop's prevRet, which belongs to the lift and the weapon: sharing it
\ would make leaving the console fire the gun on the way out.
.ConsoleRun
  LDX #KEY_L
  JSR keydown
  BNE con_r_lup
  LDA conPrevL
  BNE con_r_x                   \ still held from opening, or from last pass
  LDA #1 : STA conPrevL
  JMP ConsoleClose
.con_r_lup
  LDA #0 : STA conPrevL
.con_r_x
  RTS

\ ============================================================
\ ConTok — print string A from the $C000 table at pnDst
\ ============================================================
\ PrCapitalString ($2E1E) and sub_0_BE9 ($0BE9), together.
\
\ A LEADING SPACE IS PART OF EVERY TOKEN. $0BF1 draws one before the
\ string, unconditionally, which is where the gaps between the words of a
\ name come from — "influence" and "device" carry none of their own.
\
\ conCap IS ToUpper's byte_0_248: zero prints the token as stored, which
\ is lowercase, and non-zero capitalises the first letter. ShowRobotType
\ prints the separator with it clear and then sets it, so the name is
\ capitalised and the dash is not.
\
\ CAPITALISING IS ONE SUBTRACT HERE and three special cases on the C64.
\ ToUpper ($2E4B) has to test for $54, $42 and $12 because the charset
\ puts lowercase m, lowercase w and capital I out of alphabetical order;
\ our glyph indices are two positional runs, so a-z to A-Z is a constant
\ difference for every letter including those three.
\
\ THE POINTER IS A PATCHED ABSOLUTE, not zero page. There is no third
\ zero-page pointer to borrow — pnSrc and pnDst are the two that were
\ free, and PnGlyph reloads pnSrc from the glyph index on every call, so
\ nothing can be held there across one. This file is in RAM, so the
\ operand can be written the way the blitter writes its own.
.ConTok
  STA conTmp
  LDA #LO(constrings) : STA ctk_get+1
  LDA #HI(constrings) : STA ctk_get+2
  LDA conTmp
  BEQ ctk_at                     \ token 0 starts at the first byte
\ THE SCAN IS INLINE, the character reader is not. Reaching token 208
\ walks about 1,300 bytes and this runs six times a screen, so the
\ pointer step is written out here rather than costing a JSR and an RTS
\ per byte. The C64 pays none of it: FindStrings indexes the table once
\ at startup into 249 pointers, and 498 bytes is more than bank 6 has.
.ctk_find
  INC ctk_get+1
  BNE ctk_f1
  INC ctk_get+2
.ctk_f1
  JSR ConTokGet
  BPL ctk_find                   \ bit 7 marks a string's first character
  DEC conTmp
  BNE ctk_find

.ctk_at
  LDA #PN_SPACE                 \ $0BF1, before the string proper
  JSR PnGlyph

  JSR ConTokGet
  AND #&7F
  LDX conCap
  BEQ ctk_first
  CMP #PN_LOWER_A
  BCC ctk_first
  CMP #PN_LOWER_Z+1
  BCS ctk_first
  SEC
  SBC #PN_LOWER_A - PN_UPPER_A
.ctk_first
  JSR PnWide

.ctk_more
  JSR ConTokNext
  JSR ConTokGet
  BMI ctk_x                      \ the next string's first character
  JSR PnWide
  JMP ctk_more
.ctk_x
  RTS

.ConTokGet
.ctk_get
  LDA &FFFF
  RTS

.ConTokNext
  INC ctk_get+1
  BNE ctk_nx
  INC ctk_get+2
.ctk_nx
  RTS

\ ============================================================
\ ConIcons — the menu down the left-hand side
\ ============================================================
\ THREE FLAT 48-BYTE COPIES AN ICON, because the six 4-pixel columns of a
\ 24 px sprite are 48 consecutive bytes within one character row — see
\ conicons.asm. No shifting, no masking, and nothing to save: ConClear
\ has just blanked the area and ConsoleClose repaints the deck.
\ THE TOP SLOT IS EMPTY, and that is the one thing here that is not the
\ original's. Its sprite image is built at run time by BuildDroidSprite
\ from the player's own droid, and the artwork for that is in the SPRITE
\ bank behind the compiled blitter, not in a table this file can copy.
\ See docs/layer-9-hud.md, decision 16.
.ConIcons
  LDX #CON_ICON_COUNT-1
.ci_icon
  LDA conIconDstLo,X : STA pnDst
  LDA conIconDstHi,X : STA pnDst+1
  LDA conIconSrcLo,X : STA ci_get+1 : STA ci_wget+1
  LDA conIconSrcHi,X : STA ci_get+2 : STA ci_wget+2
  LDA conIconExp,X
  STA ci_wide+1                 \ patched, so the row loop tests nothing
  STX conTmp

\ THE ROW COUNT IS IN MEMORY, NOT X. The wide path needs X for the source
\ index and again for the doubling-table lookup, so a row counter left in
\ it survives the narrow copy and is destroyed by the other one — which
\ showed as the console clearing and then drawing nothing at all.
  LDA #CON_ICON_ROWS
  STA conIconRow
.ci_row
.ci_wide
  LDA #0                        \ operand patched above: 0 narrow, else wide
  BNE ci_w

\ ---- 24 px: 48 bytes straight across -----------------------
  LDY #CON_ICON_RB-1
.ci_n
.ci_get
  LDA &FFFF,Y
  AND #PN_INK_WHITE             \ exported as logical 3, drawn as 1 — the
  STA (pnDst),Y                 \ same recolour PnGlyph does, and for the
  DEY                           \ same reason: 3 is black on some decks
  BPL ci_n
  JMP ci_rowend

\ ---- 48 px: every source byte becomes two ------------------
\ conTmp2 holds the source index while X does the table lookup, because
\ Y is the destination and there is no third index register.
.ci_w
  LDX #0
.ci_wb
\ THE DESTINATION IS NOT 2 * THE SOURCE INDEX. A source byte is ONE
\ SCANLINE of ONE 4-pixel column — the column's eight bytes are eight
\ consecutive scanlines — so doubling it produces the same scanline of
\ TWO columns, which are eight bytes apart, not adjacent. Source index
\ u*8 + s therefore goes to u*16 + s and u*16 + s + 8. Writing it to
\ 2k and 2k+1 instead interleaves the scanlines of every column with its
\ neighbour's, which looks exactly like noise, and did.
  TXA
  AND #&F8                      \ the column, doubled: u * 16
  ASL A
  STA conTmp3
  TXA
  AND #7                        \ plus the scanline within it
  ORA conTmp3
  TAY
  STX conTmp2
.ci_wget
  LDA &FFFF,X
  AND #PN_INK_WHITE             \ white is the LOW plane, so one nibble
  TAX                           \ carries all four pixels
  LDA conDblHi,X
  STA (pnDst),Y
  TYA
  CLC
  ADC #UNIT_BYTES               \ the next 4-pixel column, eight bytes on
  TAY
  LDA conDblLo,X
  STA (pnDst),Y
  LDX conTmp2
  INX
  CPX #CON_ICON_RB
  BNE ci_wb

\ ---- on to the next character row --------------------------
.ci_rowend
  CLC                           \ the source is 48 bytes a row either way,
  LDA ci_get+1 : ADC #CON_ICON_RB : STA ci_get+1   \ and the two loops
  LDA ci_get+2 : ADC #0           : STA ci_get+2   \ read it through
  LDA ci_get+1 : STA ci_wget+1                     \ their own operand
  LDA ci_get+2 : STA ci_wget+2
  CLC
  LDA pnDst    : ADC #LO(ROW_BYTES) : STA pnDst
  LDA pnDst+1  : ADC #HI(ROW_BYTES) : STA pnDst+1
  DEC conIconRow
  BNE ci_row

  LDX conTmp
  DEX
  BMI ci_done                   \ JMP, not BPL: ci_icon is 142 bytes back
  JMP ci_icon
.ci_done
  RTS

\ ---- doubling a nibble to a byte ---------------------------
\ The icons are drawn white, which is logical 1, which is the LOW colour
\ plane alone — so all four pixels of a byte live in one nibble and the
\ table is sixteen entries and not two hundred and fifty-six. conDblHi
\ takes the nibble's top two pixels to a whole byte and conDblLo its
\ bottom two, so one source byte becomes the two the VIC's X-expansion
\ would have produced.
\
\ Bits 3-0 are pixels 0-3, so entry n of conDblHi is p0 p0 p1 p1 and of
\ conDblLo is p2 p2 p3 p3.
.conDblHi
  EQUB %0000, %0000, %0000, %0000, %0011, %0011, %0011, %0011
  EQUB %1100, %1100, %1100, %1100, %1111, %1111, %1111, %1111
.conDblLo
  EQUB %0000, %0011, %1100, %1111, %0000, %0011, %1100, %1111
  EQUB %0000, %0011, %1100, %1111, %0000, %0011, %1100, %1111

\ Rows 5, 8 and 11 at units 7, 4 and 4 — the top slot, row 2 unit 7, is
\ the droid image and is not drawn. Held as whole addresses because the
\ row multiply would otherwise be three 16-bit shifts for a table that
\ never changes.
CON_ICON_D0 = BUF_BASE +  5 * ROW_BYTES + 7 * UNIT_BYTES
CON_ICON_D1 = BUF_BASE +  8 * ROW_BYTES + 4 * UNIT_BYTES
CON_ICON_D2 = BUF_BASE + 11 * ROW_BYTES + 4 * UNIT_BYTES
.conIconDstLo EQUB LO(CON_ICON_D0), LO(CON_ICON_D1), LO(CON_ICON_D2)
.conIconDstHi EQUB HI(CON_ICON_D0), HI(CON_ICON_D1), HI(CON_ICON_D2)
.conIconSrcLo EQUB LO(conicons + CON_ICON0_OFS), LO(conicons + CON_ICON1_OFS), LO(conicons + CON_ICON2_OFS)
.conIconSrcHi EQUB HI(conicons + CON_ICON0_OFS), HI(conicons + CON_ICON1_OFS), HI(conicons + CON_ICON2_OFS)
.conIconExp   EQUB 0, &FF, &FF  \ SpriteXExp, per icon

\ ============================================================
\ ConUnitType — ShowRobotType ($3149), the top line
\ ============================================================
\ "Unit type 001 - Influence Device". The C64 patches the three digits
\ into UnitType_txt ($6B77) and draws the lot in one DrawString; we draw
\ the words and then the digits, which lands in the same place because
\ DrawString and PnStr both leave the cursor after the text, and does not
\ need the string to be writable.
\
\ THE NAME IS TWO TOKENS. $317E: the hundreds digit indexes the first —
\ influence, disposal, servant, messenger, maintenance, crew, sentinel,
\ battle, security, command — and the second is "device" when that digit
\ is 0 and ((digit - 1) >> 2) + 10 otherwise, which is robot for 1-4,
\ droid for 5-8 and cyborg for 9.
\
\ ClearEOL ($3193) is not ported: it blanks from the cursor to column 39
\ after the name, and ConClear has already blanked the whole area.
.ConUnitType
  LDA #CON_ROW_UNIT : STA conRow
  LDA #CON_COL_UNIT : STA pnCol
  LDA #LO(conTxtUnit) : STA pnStrLo
  LDA #HI(conTxtUnit) : STA pnStrHi
  JSR ConStr

  LDY pmType                    \ the hundreds, then the packed BCD tens
  LDA pnTabCent,Y               \ and units — the panel's old droid number
  CLC : ADC #PN_DIGIT0          \ read the same two tables
  JSR PnGlyph
  LDY pmType
  LDA pnTabNum,Y
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #PN_DIGIT0
  JSR PnGlyph
  LDY pmType
  LDA pnTabNum,Y
  AND #&0F
  CLC : ADC #PN_DIGIT0
  JSR PnGlyph

  LDA #0 : STA conCap           \ the separator is not a word
  LDA #CON_TOK_SEP
  JSR ConTok

\ $3172: DEC prntX. Every token carries a leading space, so the separator
\ and the name that follows it would sit two apart; backing up one column
\ is how the original closes that. One column is 16 bytes.
  SEC
  LDA pnDst   : SBC #16 : STA pnDst
  LDA pnDst+1 : SBC #0  : STA pnDst+1

  LDA #1 : STA conCap           \ $316F: INC byte_0_248, and the name
  LDY pmType                    \ is capitalised from here
  LDA pnTabCent,Y
  PHA
  JSR ConTok
  PLA
  BEQ cu_device
  SEC : SBC #1
  LSR A : LSR A
  CLC : ADC #CON_TOK_CLASS
  BNE cu_class                  \ always: CON_TOK_CLASS is 10
.cu_device
  LDA #CON_TOK_DEVICE
.cu_class
  JMP ConTok                    \ and its RTS

\ ============================================================
\ ConDraw — ConsoleMain ($2955), the whole screen
\ ============================================================
\ Called from ConsoleOpen. There is one page, so nothing repaints it.
.ConDraw
  JSR ConClear
  JSR ConIcons
  JSR ConUnitType

  LDA #CON_ROW_ACC : STA conRow
  LDA #LO(conTxtAccess) : LDY #HI(conTxtAccess)
  JSR ConLine

\ ---- the ship, by shipLevel --------------------------------
  LDA #CON_ROW_SHIP : STA conRow
  LDA #LO(conTxtShip) : LDY #HI(conTxtShip)
  JSR ConLine
  LDA pmShip
  SEC : SBC #1
  AND #7
  CLC : ADC #CON_TOK_SHIP
  JSR ConTok

\ ---- the deck ----------------------------------------------
  LDA #CON_ROW_DECK : STA conRow
  LDA #LO(conTxtDeck) : LDY #HI(conTxtDeck)
  JSR ConLine
  LDA deck
  CLC : ADC #CON_TOK_DECK
  JSR ConTok

\ ---- the alert level, its top two bits ---------------------
\ $298C's own arithmetic: three ROLs and AND 3.
  LDA #CON_ROW_ALERT : STA conRow
  LDA #LO(conTxtAlert) : LDY #HI(conTxtAlert)
  JSR ConLine
  LDA alertLvl
  ROL A : ROL A : ROL A
  AND #3
  CLC : ADC #CON_TOK_ALERT
  JMP ConTok                    \ and its RTS

\ A/Y = the label, conRow already set. Leaves pnDst after it, so the
\ token that follows continues on the same line, and sets conCap because
\ every name after a label is capitalised.
.ConLine
  STA pnStrLo
  STY pnStrHi
  LDA #CON_COL_TEXT : STA pnCol
  JSR ConStr
  LDA #1 : STA conCap
  RTS

\ ---- the labels --------------------------------------------
\ $6E00, $6E12, $6E1C and $6E26, with their own spacing: "Ship" and
\ "Deck" are padded to the width of "Alert" so the colons line up, which
\ is the original's doing and not ours.
.conTxtUnit   EQUS " Unit type "  : EQUB 0
.conTxtAccess EQUS "Access granted." : EQUB 0
.conTxtShip   EQUS "Ship  :"      : EQUB 0
.conTxtDeck   EQUS "Deck  :"      : EQUB 0
.conTxtAlert  EQUS "Alert :"      : EQUB 0

.conRow    EQUB 0
.conCap    EQUB 0
.conTmp    EQUB 0
.conTmp2   EQUB 0
.conIconRow EQUB 0
.conTmp3   EQUB 0
.conPrevL  EQUB 0
