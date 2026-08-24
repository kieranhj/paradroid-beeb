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
\ area instead costs nothing: it is 40 characters by 16 rows, and the
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
\ Its console area is screen rows 8-24 — ClearGameScreen ($2BA5) fills 17
\ rows from $4940, which is $4800 + 320, so row 8 — and those five lines
\ are therefore console rows 2, 4, 7, 10 and 13, with rows 0 and 1 empty.
\ The 2/3/3/3 spacing is the original's and is what leaves a blank row
\ between the lower four.
\
\ WE SIT ONE ROW ABOVE THAT. The layout was originally flattened to the
\ top row (0, 2, 5, 8, 11) because the area was fifteen rows and 13 + 2
\ did not fit. Sixteen rows since 2026-08-21 bought one back, and KC,
\ 2026-08-24, spent it here — layer-9 DECISION 17: everything moved
\ down one, to 1, 3, 6, 9 and 12.
\ **It is a row short of the C64's own 2, 4, 7, 10, 13** — that would
\ fit too, and KC chose one row rather than two with the choice in
\ front of them. Do not 'fix' it to two without asking.
\
\ EVERYTHING IN THE MENU MOVES TOGETHER: the four icons ride the lower
\ four rows and the marker bar sits one row into each icon, so the icon
\ destinations below are written as CON_ROW_* and the bar — bank 4's,
\ which cannot see them — is ASSERTed against them instead.
\
\ The pages that moved down a row at the sixteen-row change are the
\ ported ones — the database, the information screens and the game over
\ — because sixteen rows is what the C64 lays them out in. See
\ condb.asm's geometry block.
CON_ROW_UNIT  = 1
CON_ROW_ACC   = 3
CON_ROW_SHIP  = 6
CON_ROW_DECK  = 9
CON_ROW_ALERT = 12
ASSERT CON_ROW_ALERT + 2 <= PLAY_ROWS         \ the alert glyph, two rows

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
\ last ends at row 13 of sixteen.
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
\ ALL FOUR ARE STORED AS THE C64'S OWN SPRITE BYTES, three a row, and
\ converted as they are drawn. That is half the size of storing the MODE
\ 1 form and costs nothing: the icons are logical colour 1, which is the
\ LOW colour plane alone, so four pixels ARE one nibble. Bank 6 ran out
\ by 346 bytes with the converted form, which is what forced the
\ question — and the answer is smaller AND closer to the original.
\
\ The X-expansion happens there too, from a sixteen-entry nibble table.
CON_ICON_COUNT = 3              \ of four — see conicons.asm
CON_ICON_ROWS  = 3              \ 21 scanlines, so three character rows
CON_ICON_LINES = 21             \ scanlines: a C64 sprite is 21 tall
ASSERT CON_ROW_ALERT + CON_ICON_ROWS <= PLAY_ROWS  \ and its icon, three

\ The FIRST icon is the player's own droid and is composed, not copied —
\ see droidicon.asm. Same 24 x 21 as the rest, in the slot the other
\ three leave empty: row 2, unit 7.
CON_DRICON_W = 3                \ C64 sprite bytes a row
CON_DROID_D  = BUF_BASE + CON_ROW_ACC   * ROW_BYTES + 7 * UNIT_BYTES

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
\ ALL SIXTEEN ROWS. It used to be PLAY_VIS_ROWS, because the last row
\ was the smooth scroll's spare and never displayed; ConsoleOpen now
\ shows it (T1_I3X), so leaving it would put a strip of the deck along
\ the bottom of every console screen.
\ A ROW IS 640 BYTES, WHICH IS TWO PAGES AND A HALF — 2 x 256 + 128 —
\ and the first version cleared one page and the 128, left the last 256
\ of every row standing, and stepped 512 instead of 640. The deck showed
\ through the right-hand third of the console. Hence the explicit three
\ blocks and the row base kept in pnTmpW rather than walked.
.ConClear
  LDA #LO(BUF_BASE) : STA pnDst
  LDA #HI(BUF_BASE) : STA pnDst+1
  LDX #PLAY_ROWS
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
  LDA #&16                      \ $2CB8: the mode-change chord coming in
  STA sndFx1
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
  JSR SetCRTCStart

\ SIXTEEN ROWS FOR THE WHOLE SESSION. The play area displays 16 and the
\ R8 blank at fire 3 hides the last one, which is the smooth scroll's
\ spare; with the scroll flattened above it is real buffer, so the
\ console takes it — as the transfer board, the lift's deck select and
\ the information screens do. It covers the two pages as well, which is
\ why the deck plan no longer switches it for itself. ReframeView puts
\ it back when the console closes. See T1_I3X in main.asm.
  LDA #HI(T1_I3X)               \ the high byte alone — see T1_I3X
  STA t1i3Hi
  JMP ConDraw

\ THE MENU IS NOT HERE. conWaitInput's port — the $80-$83 selection,
\ the marker, the conJump_t dispatch, and closing the console — is
\ ConMenu4 in droid.asm, BANK 4, because this bank is full (23 bytes
\ free when it was built) and everything the menu touches is main RAM:
\ the keys, the play buffer, conActive and the conShipReq flag. The
\ old ConsoleRun (L leaves, nothing else) went with it — leaving is
\ the menu's top entry now, as it is the C64's.

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
\ ToUpper CLEARS byte_0_248 on the way out ($2E75), whether it
\ capitalised anything or not, so ONE word is capitalised per INC and no
\ more. This was missing, and it showed: the name line drew "Influence
\ Device" where the C64 draws "Influence device" — $316F sets the flag
\ once and the class word that follows the class NAME is lowercase.
\ Found while porting the droid database, which prints the same two
\ tokens from bank 7.
  LDA #0
  STA conCap
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
  STX conTmp
  LDA conIconDstLo,X : STA pnDst
  LDA conIconDstHi,X : STA pnDst+1
  LDA conIconSrcLo,X : STA ci_get+1
  LDA conIconSrcHi,X : STA ci_get+2
  LDA conIconExp,X   : STA conWide
  LDA conInkT+1,X    : STA csn_mask+1   \ conSel 1-3: THE COLOUR, chosen
                                        \ before a pixel is drawn, so the
                                        \ icon never appears in the wrong
                                        \ one. conInkT is main RAM because
                                        \ conSel is bank 4's and this file
                                        \ cannot read it. KC, 2026-08-24
  LDA #LO(ConIconRow) : STA cs_get+1
  LDA #HI(ConIconRow) : STA cs_get+2
  JSR ConSprite
  LDX conTmp
  DEX
  BPL ci_icon
  RTS

\ Three C64 sprite bytes for row conDrR, or nothing past row 20.
.ConIconRow
  LDX #2
  LDA conDrR
  CMP #CON_ICON_LINES
  BCS cir_blank
  ASL A                         \ row * 3
  CLC : ADC conDrR
  CLC : ADC #2                  \ and the loop fills 2 down to 0
  TAY
  LDA #2
  STA conTmp3
.cir_copy
  LDX conTmp3
.ci_get
  LDA &FFFF,Y
  STA conSrcRow,X
  DEY
  DEC conTmp3
  BPL cir_copy
  RTS
.cir_blank
  LDA #0
.cir_bl
  STA conSrcRow,X
  DEX
  BPL cir_bl
  RTS

\ ============================================================
\ ConDroid — the first icon: the player's own droid
\ ============================================================
\ BuildDroidSprite ($3C77) and AnimateDroids ($3CFB) together, which is
\ what the C64 leaves in the dynamic sprite area at $53C0 for conRedraw to
\ draw. The rotor and the digits are stored separately and composed a row
\ at a time -- see droidicon.asm for why this cannot be the port's own
\ droid artwork.
.ConDroid
  LDY pmType                    \ the number, as three separate digits
  LDA pnTabCent,Y
  STA conDrDig+0
  LDA pnTabNum,Y
  LSR A : LSR A : LSR A : LSR A
  STA conDrDig+1
  LDY pmType
  LDA pnTabNum,Y
  AND #&0F
  STA conDrDig+2

  LDA #LO(CON_DROID_D) : STA pnDst
  LDA #HI(CON_DROID_D) : STA pnDst+1
  LDA #0 : STA conWide
  LDA conInkT : STA csn_mask+1  \ conSel 0, the player's own droid
  LDA #LO(ConDroidRow) : STA cs_get+1
  LDA #HI(ConDroidRow) : STA cs_get+2
  JMP ConSprite                 \ and its RTS

\ ---- one row of the droid ----------------------------------
\ Rows 0-4 rotor top, 6-13 the digits, 15-19 rotor bottom. Rows 5, 14 and
\ 20 are written by neither routine, so they stay transparent, and 21-23
\ are past the sprite; blanking first makes all of them fall out.
.ConDroidRow
  LDA #0
  LDX #2
.cdr_blank
  STA conSrcRow,X
  DEX
  BPL cdr_blank

  LDA conDrR
  CMP #5
  BCC cdr_rotor                 \ 0-4, and the index is the row
  CMP #6
  BCC cdr_x
  CMP #14
  BCC cdr_digits
  CMP #15
  BCC cdr_x
  CMP #20
  BCS cdr_x
  SEC                           \ 15-19 are rotor rows 5-9
  SBC #10

.cdr_rotor
  STA conTmp3                   \ index * 3
  ASL A
  CLC : ADC conTmp3
  TAY
  LDX #0
.cdr_rcopy
  LDA conDrRotor,Y
  STA conSrcRow,X
  INY
  INX
  CPX #3
  BNE cdr_rcopy
.cdr_x
  RTS

\ Each glyph is EIGHT ROWS OF ONE BYTE, because BuildDroidSprite writes
\ each digit into a byte column of its own -- so the three go straight
\ into the three bytes of the row with no packing at all.
.cdr_digits
  SEC
  SBC #6                        \ the row within the glyph, 0-7
  STA conTmp3
  LDX #0
.cdr_dloop
  STX conTmp2
  LDA conDrDig,X                \ digit * 8 bytes a glyph
  ASL A : ASL A : ASL A
  CLC : ADC conTmp3
  TAY
  LDX conTmp2
  LDA conDrDigits,Y
  STA conSrcRow,X
  INX
  CPX #3
  BNE cdr_dloop
  RTS

\ ============================================================
\ ConSprite -- 21 rows of a 24 px sprite, transposed into the buffer
\ ============================================================
\ ONE ROUTINE FOR ALL FOUR ICONS. Each supplies its own row through the
\ patched JSR at cs_get, which fills conSrcRow with THREE C64 SPRITE
\ BYTES -- the form the original stores every one of them in, the droid
\ included, since BuildDroidSprite writes into a sprite too.
\
\ THE SOURCE IS ROW MAJOR AND THE BUFFER IS NOT. A 4-pixel column's eight
\ bytes are eight consecutive SCANLINES, so row r column u goes to
\ (r DIV 8) * 640 + u * 8 + (r MOD 8). The compiled blitter gets that
\ transpose for nothing by being compiled; this pays for it in a loop,
\ which is affordable because it runs once per console.
.ConSprite
  LDA #0
  STA conDrR
.cs_crow
  LDA #0
  STA conRowY
.cs_row
.cs_get
  JSR ConIconRow                \ operand patched by the caller
  JSR ConSprRow

  INC conDrR
  INC conRowY
  LDA conRowY
  CMP #8
  BNE cs_row

  CLC
  LDA pnDst   : ADC #LO(ROW_BYTES) : STA pnDst
  LDA pnDst+1 : ADC #HI(ROW_BYTES) : STA pnDst+1
  LDA conDrR
  CMP #CON_ICON_ROWS * 8
  BNE cs_crow
  RTS

\ ---- one row: three C64 bytes to six or twelve MODE 1 -------
\ A HIRES SPRITE BYTE IS EIGHT 1-BIT PIXELS, and the icons are drawn in
\ logical colour 1, which is the LOW colour plane alone -- so four pixels
\ ARE one nibble and the conversion is a shift and a mask, with no table
\ and no stored MODE 1 copy. That is what halves the data.
\
\ X-expanded, a nibble becomes two bytes instead of one, and conDblHi and
\ conDblLo below are the sixteen entries that do it.
.ConSprRow
  LDA conRowY                   \ the scanline is the offset within a
  STA conDrTmp                  \ column, and columns are eight apart
  LDX #0
.csr_byte
  STX conTmp2
  LDA conSrcRow,X
  LSR A : LSR A : LSR A : LSR A \ pixels 0-3
  JSR ConSprNib
  LDX conTmp2
  LDA conSrcRow,X
  AND #&0F                      \ pixels 4-7
  JSR ConSprNib
  LDX conTmp2
  INX
  CPX #3
  BNE csr_byte
  RTS

.ConSprNib
  TAX
  LDA conWide
  BNE csn_wide
  TXA                           \ narrow: the nibble IS the pattern
  JSR csn_put
  JMP ConSprAdv
.csn_wide
  LDA conDblHi,X
  JSR csn_put
  JSR ConSprAdv
  LDA conDblLo,X
  JSR csn_put
.ConSprAdv
  LDA conDrTmp
  CLC : ADC #UNIT_BYTES
  STA conDrTmp
  RTS

\ ---- one four-pixel pattern, in the icon's colour ----------
\ A = the pattern in its LOW nibble, and the high nibble is built from
\ it: zero for logical 1 (black) or a copy for logical 3 (white). The
\ SAME transform ConIconSel4 uses on an icon already drawn - see
\ src/consolesel.asm - which is why the two agree by construction.
\ IT REPLACED A conNib3 TABLE of sixteen n*&11 entries, and paid for
\ itself: the table was 16 bytes, this is 7 more of code shared by all
\ three stores below, and it is where the colour arrives. Bank 6 had
\ sixteen bytes free when this was written and the colour had to fit in
\ them - a second set of black tables would have wanted forty-eight.
.csn_put
  STA conNibT
  ASL A : ASL A : ASL A : ASL A
.csn_mask
  AND #&00                      \ patched per icon: &00 black, &F0 white
  ORA conNibT
  LDY conDrTmp
  STA (pnDst),Y
  RTS

\ ---- doubling a nibble to a byte ---------------------------
\ Four pixels to eight, for the two X-expanded icons. Sixteen entries and
\ not 256, because a pixel is either the ink or nothing. Bits 3-0 of the
\ index are pixels 0-3, so entry n of conDblHi is p0 p0 p1 p1 and of
\ conDblLo is p2 p2 p3 p3.
\ LOW NIBBLE ONLY: these are the PATTERN, not a finished byte. csn_put
\ builds the high colour plane from it, and that is where the icon's
\ colour is decided. They held the pattern in BOTH nibbles while every
\ icon was logical 3, and in one alone before that, when white was
\ logical 1 - so this is the third time these sixteen bytes have moved.
.conDblHi
  EQUB %00000000, %00000000, %00000000, %00000000
  EQUB %00000011, %00000011, %00000011, %00000011
  EQUB %00001100, %00001100, %00001100, %00001100
  EQUB %00001111, %00001111, %00001111, %00001111
.conDblLo
  EQUB %00000000, %00000011, %00001100, %00001111
  EQUB %00000000, %00000011, %00001100, %00001111
  EQUB %00000000, %00000011, %00001100, %00001111
  EQUB %00000000, %00000011, %00001100, %00001111

\ One icon per line, on the SAME rows as the lower four - so these are
\ CON_ROW_SHIP/DECK/ALERT, not literals, and the droid is CON_ROW_ACC.
\ They drifted from the text once; deriving them is what stops it.
\ Held as whole addresses because the row multiply would otherwise be
\ three 16-bit shifts for a table that never changes.
CON_ICON_D0 = BUF_BASE + CON_ROW_SHIP  * ROW_BYTES + 7 * UNIT_BYTES
CON_ICON_D1 = BUF_BASE + CON_ROW_DECK  * ROW_BYTES + 4 * UNIT_BYTES
CON_ICON_D2 = BUF_BASE + CON_ROW_ALERT * ROW_BYTES + 4 * UNIT_BYTES

\ ConIconSel4 (src/consolesel.asm) recolours these four in place. It is
\ assembled into bank 4 long BEFORE this file, so it cannot see the
\ destinations above and holds its own literals. Tie the two together
\ HERE, where both are known - CON_SEL0 is the player's own droid.
ASSERT CON_SEL0 == CON_DROID_D
ASSERT CON_SEL1 == CON_ICON_D0
ASSERT CON_SEL2 == CON_ICON_D1
ASSERT CON_SEL3 == CON_ICON_D2
ASSERT CON_SEL_ROWS == CON_ICON_ROWS
\ and that its fixed width covers the widest icon without reaching the
\ text: the narrow icons start at unit 7, the wide ones at unit 4.
ASSERT 7 + CON_SEL_UNITS <= CON_COL_TEXT * 2
ASSERT 4 + CON_SEL_UNITS <= CON_COL_TEXT * 2
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
  JSR ConDroid
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
.conDrR    EQUB 0
.conDrSL   EQUB 0
.conDrTmp  EQUB 0
.conDrDig  EQUB 0, 0, 0
.conSrcRow EQUB 0, 0, 0
.conRowY   EQUB 0
.conWide   EQUB 0
.conNibT   EQUB 0              \ csn_put's, one pattern deep
