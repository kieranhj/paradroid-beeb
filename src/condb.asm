\ ============================================================
\ condb.asm â€” the console's droid database, con_DroidInfo ($2CC6)
\ ============================================================
\ LAYER 9, in SWRAM BANK 7 with the transfer game, the lift screen and
\ the deck plan. The console's second menu entry â€” the "?" emblem.
\
\ IT IS NOT A STATIC PAGE like the ship view and the deck plan. Those are
\ drawn once and wait for fire; this one is a browser, so ConsoleTick
\ calls DbTick every pass and the page decides what to do, exactly as
\ GameLoop calls con_DroidInfo every frame. The five sub-pages and their
\ dispatch are dInfoPgJump_t's ($6BE9):
\
\   0  DrInfo0  ($2D79)  clear, reset the print position, go to 1
\   1  DrInfo1  ($2CF0)  the browser: up/down walk the type, the image and
\                        the name redraw every frame, left/right to 2
\   2  DrInfo2  ($2D34)  print stat lines until the screen is full, then 3
\   3  DrInfo3  ($2D40)  "More..." in the status line; left/right resumes
\   4  DrInfo4  ($2D6A)  the end: any stick goes back to 0
\
\ THE CLAMP IS THE RULE OF THE PAGE. DrInfo1 walks dType between 0 and
\ droidType â€” the player's own class â€” and wraps at both ends: you cannot
\ read up on a droid better than the one you are wearing. Ported exactly,
\ against pmType, which is drType's main-RAM mirror.
\
\ WHY BANK 7. The page needs the $C000 string table and a glyph printer;
\ both are in bank 6, which had 63 bytes free, and only one bank is
\ visible at a time. Main RAM had 53 bytes and bank 4 about 300, so
\ neither could take the page either. Bank 7 had 6K, so the page lives
\ here — beside portrait.asm and the pool it draws the droid's picture
\ from. (The string table moved to main RAM in Layer 13a, and the
\ droid-icon second copy went with the rotor-and-digits stand-in when
\ the real portrait landed.) See docs/layer-9-hud.md.
\
\ WHAT IT CAN AND CANNOT REACH. Main RAM freely â€” the font at FONT_ADDR,
\ the droid tables at PN_TABS, the play buffer, the panel, keydown. Bank
\ 4's drType, drCount and shipLevel not at all; pmType is the mirror.

DB_TYPES = 24
DB_STATS = 8
DB_INK   = PN_INK_WHITE         \ white: logical 3 on every deck

\ ---- the page's geometry ------------------------------------
\ A glyph is 8 x 16, so a text line is TWO buffer rows and the console's
\ fifteen hold seven lines. The C64 puts the name at screen row 10 and
\ steps the content lines 12, 14 ... 22 â€” six of them, because $2DC4
\ stops at 24 â€” so its page and ours are the same shape line for line,
\ and no line had to be dropped or moved.
DB_LINES      = 7
DB_LINE_LAST  = 6               \ $2DC4's "prntY < 24"
DB_LINE_FIRST = 1               \ byte_0_46, the first content line
DB_COL_NAME   = 2               \ UnitType_txt's own prntX
DB_COL_LABEL  = 9               \ $2D94
DB_COL_MARGIN = 12              \ byte_0_45: where a wrapped line restarts
DB_COL_CONT   = 11              \ $2DDF: where a continued description does
DB_COL_LAST   = 39              \ $0C19 and ClearEOL ($3199)

\ ---- the counter, and what it selects ------------------------
\ sub_0_2DA0+1 is a self-modifying immediate that runs 13 to 23. It is
\ BOTH the label's token number AND, less seven, the record byte the
\ value comes from â€” which is why the ten labels are tokens 13-22 and the
\ record's stat bytes are 6-15. At 23 the stats are done and $2D9E
\ switches to the description.
DB_CNT_FIRST = 13
DB_CNT_DESC  = 23
DB_TOK_COLON = 24               \ ": ", printed after every label
DB_TOK_SEP   = 50               \ "- ", the name line's separator
DB_TOK_CLASS = 10               \ robot / droid / cyborg
DB_TOK_DEV   = 55               \ "device", for the 001 alone

DB_VAL_ENTRY  = 6               \ the four values PrintDroidInfo computes
DB_VAL_CLASS  = 7               \ rather than reading as a token
DB_VAL_HEIGHT = 8
DB_VAL_WEIGHT = 9

DB_DESC_BREAK = &FE             \ a sentence break: a full stop, then a capital
DB_DESC_END   = &FF

\ ---- the droid portrait -------------------------------------
\ Sprite X 40 is 16 pixels in, which is unit 4, and sprite Y 144 puts
\ the 48 x 84 picture level with the content lines — buffer rows 2-12,
\ units 4-15 — clear of the stat text, which starts at column 9.
\ portrait.asm draws it; these two anchor its rectangle.
DB_IMG_ROW  = 2
DB_IMG_UNIT = 4

\ ============================================================
\ DbTick â€” con_DroidInfo ($2CC6), once a pass
\ ============================================================
\ The C64 tests joyFire FIRST and leaves the moment it is released, so
\ the page is only up while the button is held. OURS IS EDGE TRIGGERED â€”
\ a press leaves â€” which is the convention the ship page and the deck
\ plan already set (ConPageKeys4, droid.asm) and the only one that can
\ share a keyboard with the four browse keys.
\
\ GotoHires and the $F3 colour fill have no port: the console screen has
\ no multicolour to turn off, and its ink is white on every deck by
\ construction (ConAt, console.asm).
.DbTick
  LDA conDbReq
  CMP #1
  BNE db_running
  JSR DbEnter
.db_running
  LDX #KEY_L                    \ fire: back to the console main screen
  JSR keydown
  BNE db_fireUp
  LDA dbPrevF
  BNE db_page
  LDA #1
  STA dbPrevF
  LDA #0
  STA conDbReq                  \ ConsoleTick sees it and redraws the main
  RTS
.db_fireUp
  LDA #0
  STA dbPrevF

\ dInfoPgJump_t ($6BE9), as five jumps rather than a table: the table
\ costs ten bytes and a self-modified JMP, and this costs fourteen.
.db_page
  LDA dbPage
  BEQ db_j0
  CMP #1
  BEQ db_j1
  CMP #2
  BEQ db_j2
  CMP #3
  BEQ db_j3
  JMP DbPage4
.db_j0
  JMP DbPage0
.db_j1
  JMP DbPage1
.db_j2
  JMP DbPage2
.db_j3
  JMP DbPage3

\ ---- entry --------------------------------------------------
\ conRedraw ($2C37) sets dType from droidType before it draws the console
\ main screen, and con_DroidInfo never initialises it â€” so the database
\ opens on the player's own droid, which is also the top of its range.
\ The edges start armed because L is still down: it is the press that got
\ us here.
.DbEnter
  LDA pmType
  STA dbType
  LDA #0
  STA dbPage
  LDA #1
  STA dbPrevF
  STA dbPrevU
  STA dbPrevD
  STA dbPrevL
  STA dbPrevR
  LDA #2
  STA conDbReq
  RTS

\ ============================================================
\ DbPage0 â€” DrInfo0 ($2D79)
\ ============================================================
.DbPage0
  LDA #1
  STA dbPage
  JSR DbClear
  LDA #DB_COL_MARGIN            \ byte_0_45 and byte_0_46, which every
  STA dbCol                     \ later page starts from
  LDA #DB_LINE_FIRST
  STA dbLine
  RTS

\ ============================================================
\ DbPage1 â€” DrInfo1 ($2CF0), the browser
\ ============================================================
\ Up and down walk dType and WRAP, between 0 and droidType inclusive:
\ $2CFC-$2D0B increments and drops to 0 once past droidType, $2D0E-$2D1A
\ decrements and jumps to droidType at 0. The image and the name are
\ redrawn every pass, as the C64 redraws its sprites and ShowRobotType.
.DbPage1
  LDX #KEY_K                    \ up
  JSR keydown
  BNE db_p1_upOff
  LDA dbPrevU
  BNE db_p1_notUp
  LDA #1
  STA dbPrevU
  INC dbType
  LDA dbType
  CMP pmType
  BEQ db_p1_notUp               \ $2D00: equal is in range
  BCC db_p1_notUp
  LDA #0
  STA dbType
  BEQ db_p1_notUp               \ always
.db_p1_upOff
  LDA #0
  STA dbPrevU
.db_p1_notUp

  LDX #KEY_M                    \ down
  JSR keydown
  BNE db_p1_dnOff
  LDA dbPrevD
  BNE db_p1_notDn
  LDA #1
  STA dbPrevD
  LDA dbType
  BEQ db_p1_wrapDn
  DEC dbType
  JMP db_p1_notDn
.db_p1_wrapDn
  LDA pmType
  STA dbType
  JMP db_p1_notDn
.db_p1_dnOff
  LDA #0
  STA dbPrevD
.db_p1_notDn

  JSR DbImage                   \ BuildIntroSprites' place in the order
  LDA #DB_CNT_FIRST             \ $2D1F: the stat counter, rewound
  STA dbStatN
  JSR DbName                    \ ShowRobotType

  JSR DbSideways                \ $2D27: left or right starts the pages
  BCC db_p1_x
  LDA #2
  STA dbPage
.db_p1_x
  RTS

\ ============================================================
\ DbPage2 â€” DrInfo2 ($2D34) and sub_0_2D92 ($2D92)
\ ============================================================
\ One screen of stat lines, printed in one pass and not one a frame: the
\ C64 loops here until the screen is full and only then gives the stick
\ back, which is why DrInfo2 sets dInfoPage itself and never returns to
\ the dispatcher in between.
.DbPage2
  LDA #DB_LINE_FIRST            \ prntY = byte_0_46, prntX = byte_0_45
  STA dbLine
  LDA #DB_COL_MARGIN
  STA dbCol

.DbStatLine                     \ sub_0_2D92
  LDA #DB_COL_LABEL             \ $2D94: the labels are at column 9
  STA dbCol
  LDA #1                        \ $2D96: and are capitalised
  STA dbCap
  LDA dbStatN
  CMP #DB_CNT_DESC
  BEQ DbDesc                    \ $2D9E: the stats are done

  JSR DbAt
  LDA dbStatN                   \ the label IS the counter
  JSR DbTok
  LDA #DB_TOK_COLON
  JSR DbTok
  JSR DbBackOne                 \ $2DAA: DEC prntX
  JSR DbValue                   \ PrintDroidInfo ($2F57)

  INC dbStatN
  LDA dbStatN
  CMP #DB_CNT_DESC
  BCS db_more                   \ $2DB7
  LDA #0                        \ $2DB9: the description starts from its
  STA dbDescIx                  \ beginning after every stat line
  INC dbLine                    \ prntY += 2
  LDA dbLine
  CMP #DB_LINE_LAST+1
  BCC DbStatLine
.db_more
  LDA #3
  STA dbPage
  RTS

\ ============================================================
\ DbDesc â€” sub_0_2DCD ($2DCD), the description text
\ ============================================================
\ A list of token numbers with two control codes: $FE ends a sentence
\ with a full stop and capitalises the next word, $FF ends the text. The
\ index is the C64's self-modifying loc_0_2DE8+1, which is why a screen
\ that fills mid-sentence can resume exactly where it stopped â€” DbTok
\ reports a full screen WITHOUT printing, so the word is still pending.
.DbDesc
  LDA dbDescIx
  BNE db_d_cont
  JSR DbAt
  LDA #DB_CNT_DESC              \ $2DD4: token 23 is "notes", and A still
  JSR DbTok                     \ holds the counter that selected it
  LDA #DB_TOK_COLON
  JSR DbTok
  JMP db_d_loop
.db_d_cont
  LDA #DB_COL_CONT              \ $2DDF: a continued description indents
  STA dbCol                     \ to 11, and starts mid-sentence
  LDA #0
  STA dbCap
  JSR DbAt

.db_d_loop
  JSR DbDescGet
  CMP #DB_DESC_BREAK
  BEQ db_d_break
  CMP #DB_DESC_END
  BEQ db_d_end
  JSR DbTok
  BCS db_more                   \ $2DF7: the screen filled; the word waits
  INC dbDescIx
  LDA dbDescIx
  CMP #DB_DESC_MAX
  BCC db_d_loop
.db_d_end
  LDA #PN_DOT                   \ $2E05: the closing full stop
  JSR DbGlyph
  LDA #4
  STA dbPage
  RTS
.db_d_break
  LDA #PN_DOT                   \ $2E11: and a sentence's own
  JSR DbGlyph
  LDA #1                        \ $2E18: the next word is capitalised
  STA dbCap
  INC dbDescIx
  JMP db_d_loop

DB_DESC_MAX = &38 - &10         \ sub_0_2DCD's own bound, rebased to 0

\ The description byte at dbDescIx, from this type's packed record.
.DbDescGet
  LDX dbType
  LDA dbiDescLo,X
  STA db_dg+1
  LDA dbiDescHi,X
  STA db_dg+2
  LDY dbDescIx
.db_dg
  LDA &FFFF,Y
  RTS

\ ============================================================
\ DbPage3 â€” DrInfo3 ($2D40), the "More..." prompt
\ ============================================================
\ IT GOES IN THE STATUS LINE, not in the console area. More_txt ($6C08)
\ carries prntY 2, prntX 2 â€” the mode word's own field, where "Console"
\ is â€” and $2D4F puts Console_txt back when the stick continues. The
\ transfer game already writes that field from this bank (XfGlyphAt), and
\ PanelUpdate will not fight for it: it rewrites the field only when the
\ mode CHANGES, and nothing changes while the console is up.
\
\ Leaving the page from here leaves "More..." standing, which is the
\ original's behaviour too â€” ConsoleMain does not repaint the field
\ either. PanelSetup puts it right on the way out of the console.
.DbPage3
  LDA #LO(dbTxtMore) : LDY #HI(dbTxtMore)
  JSR DbPanelStr

  JSR DbSideways
  BCC db_p3_x
  LDA #LO(dbTxtConsole) : LDY #HI(dbTxtConsole)
  JSR DbPanelStr                \ $2D4F
  LDA #2
  STA dbPage
  JSR DbClear                   \ $2D5A: ClearGameScreen, then the name
  JSR DbImage                   \ again â€” the C64's sprites survive its
  JSR DbName                    \ clear, and ours have to be redrawn
.db_p3_x
  RTS

\ ============================================================
\ DbPage4 â€” DrInfo4 ($2D6A), the end of the entry
\ ============================================================
\ Any direction at all goes back to page 0, which clears and returns to
\ the browser. $2D6A ORs the two axes; ours is the four keys.
.DbPage4
  JSR DbSideways
  BCS db_p4_go
  LDX #KEY_K
  JSR keydown
  BEQ db_p4_go
  LDX #KEY_M
  JSR keydown
  BEQ db_p4_go
  RTS
.db_p4_go
  LDA #0
  STA dbPage
  LDA #1                        \ the key that got us here must be
  STA dbPrevU                   \ released before the browser sees it
  STA dbPrevD
  RTS

\ ---- left or right, edge triggered --------------------------
\ joyXDir's two keys. Carry set if either has just gone down.
.DbSideways
  LDX #KEY_Z
  JSR keydown
  BNE db_sw_lUp
  LDA dbPrevL
  BNE db_sw_tryR
  LDA #1
  STA dbPrevL
  SEC
  RTS
.db_sw_lUp
  LDA #0
  STA dbPrevL
.db_sw_tryR
  LDX #KEY_X
  JSR keydown
  BNE db_sw_rUp
  LDA dbPrevR
  BNE db_sw_no
  LDA #1
  STA dbPrevR
  SEC
  RTS
.db_sw_rUp
  LDA #0
  STA dbPrevR
.db_sw_no
  CLC
  RTS

\ ============================================================
\ DbName â€” ShowRobotType ($3149), the top line
\ ============================================================
\ "Unit type 001 - Influence device", for the type being read about
\ rather than the player's. The C64 patches the digits into UnitType_txt
\ and draws the lot; we draw the words, then the digits, which lands in
\ the same place. The name is two tokens: the hundreds digit picks the
\ first, and the second is "device" when that digit is 0 and
\ ((digit - 1) >> 2) + 10 otherwise â€” robot, droid, cyborg.
\
\ ClearEOL ($3193) IS ported here, where the console main screen could
\ skip it: the name changes under the browser and a shorter one has to
\ wipe the tail of the longer one it replaces.
.DbName
  LDA #0
  STA dbLine
  LDA #DB_COL_NAME
  STA dbCol
  JSR DbAt
  LDA #LO(dbTxtUnit) : LDY #HI(dbTxtUnit)
  JSR DbStr

  LDY dbType
  LDA pnTabCent,Y
  CLC : ADC #PN_DIGIT0
  JSR DbGlyph
  LDY dbType
  LDA pnTabNum,Y
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #PN_DIGIT0
  JSR DbGlyph
  LDY dbType
  LDA pnTabNum,Y
  AND #&0F
  CLC : ADC #PN_DIGIT0
  JSR DbGlyph

  LDA #0                        \ the separator is not a word
  STA dbCap
  LDA #DB_TOK_SEP
  JSR DbTok
  JSR DbBackOne                 \ $3172: DEC prntX

  LDA #1                        \ $316F: the name is capitalised
  STA dbCap
  LDY dbType
  LDA pnTabCent,Y
  PHA
  JSR DbTok
  PLA
  BEQ db_n_device
  SEC : SBC #1
  LSR A : LSR A
  CLC : ADC #DB_TOK_CLASS
  BNE db_n_class                \ always: DB_TOK_CLASS is 10
.db_n_device
  LDA #DB_TOK_DEV
.db_n_class
  JSR DbTok

.DbClearEOL                     \ $3193
  LDA dbCol
  CMP #DB_COL_LAST
  BCS db_eol_x
  LDA #PN_SPACE
  JSR DbGlyph
  JMP DbClearEOL
.db_eol_x
  RTS

\ ============================================================
\ DbValue â€” PrintDroidInfo ($2F57), the right-hand side of a stat line
\ ============================================================
\ The counter less seven is the record byte the value comes from, 6 to
\ 15. Four of them are not bytes at all: 6 is the entry number, computed;
\ 7 is the class word, from the hundreds-digit table; 8 and 9 are the
\ height and the weight, which have their own layouts. 10 to 15 â€” drive,
\ brain, armament and three sensors â€” are plain token numbers.
\
\ OUR RECORD STARTS AT THE ORIGINAL'S BYTE 8, because bytes 0-7 are the
\ intro portrait's sprite images and the port has no portrait. So value
\ index v reads dbiStats[type * 8 + v - 8].
.DbValue
  LDA dbStatN
  SEC
  SBC #7
  CMP #DB_VAL_ENTRY
  BEQ db_v_entry
  CMP #DB_VAL_CLASS
  BEQ db_v_class
  CMP #DB_VAL_HEIGHT
  BEQ db_v_height
  CMP #DB_VAL_WEIGHT
  BEQ db_v_weight
  JSR DbStatByte                \ 10-15: a token number, printed as a word
  JMP DbTok

\ ---- the entry number, in BCD -------------------------------
\ $2F74: a space, then 1 + dType counted up in decimal mode. Two digits,
\ and the leading one is not blanked â€” entry 01 prints as 01.
.db_v_entry
  LDA #PN_SPACE
  JSR DbGlyph
  LDA #1
  LDX dbType
  SED
.db_v_bcd
  CPX #0
  BEQ db_v_bcdx
  CLC
  ADC #1
  DEX
  JMP db_v_bcd
.db_v_bcdx
  CLD
  STA dbTmp
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #PN_DIGIT0
  JSR DbGlyph
  LDA dbTmp
  AND #&0F
  CLC : ADC #PN_DIGIT0
  JMP DbGlyph

\ ---- the class word -----------------------------------------
.db_v_class
  LDY dbType
  LDA pnTabCent,Y               \ DCent_t: influence, disposal, servant ...
  JMP DbTok

\ ---- the height ---------------------------------------------
\ Height_txt ($6C15) is "1", ".", two patched digits, " ", "m" â€” so every
\ droid is one point something metres and the record byte is the two
\ decimal places, packed as nibbles. It is drawn through sub_0_BE9, which
\ means it gets the same leading space and the same wrap test as a token.
.db_v_height
  LDA #DB_VAL_HEIGHT
  JSR DbStatByte
  PHA
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #PN_DIGIT0
  STA dbTxtHeight+2
  PLA
  AND #&0F
  CLC : ADC #PN_DIGIT0
  STA dbTxtHeight+3
  LDA #LO(dbTxtHeight) : LDY #HI(dbTxtHeight)
  JMP DbSpacedStr

\ ---- the weight ---------------------------------------------
\ $2FC0: hundreds and tens by repeated subtraction, into Weight_txt
\ ($6C1C) â€” three digits then " kg". LEADING ZEROS ARE NOT BLANKED, which
\ is the original's own doing: 27 kg prints as 027 kg.
.db_v_weight
  LDA #PN_DIGIT0
  STA dbTxtWeight+0
  STA dbTxtWeight+1
  LDA #DB_VAL_WEIGHT
  JSR DbStatByte
  CMP #100
  BCC db_v_w10
  LDX #PN_DIGIT0+1
  STX dbTxtWeight+0
.db_v_w100
  SEC
  SBC #100
  CMP #100
  BCC db_v_w10
  INC dbTxtWeight+0
  JMP db_v_w100
.db_v_w10
  CMP #10
  BCC db_v_wunit
  LDX #PN_DIGIT0+1
  STX dbTxtWeight+1
.db_v_w10loop
  SEC
  SBC #10
  CMP #10
  BCC db_v_wunit
  INC dbTxtWeight+1
  JMP db_v_w10loop
.db_v_wunit
  CLC : ADC #PN_DIGIT0
  STA dbTxtWeight+2
  LDA #LO(dbTxtWeight) : LDY #HI(dbTxtWeight)
  JMP DbSpacedStr

\ Record byte A (8-15) for the current type: dbiStats is eight a type.
.DbStatByte
  SEC
  SBC #8
  STA dbTmp
  LDA dbType
  ASL A : ASL A : ASL A
  CLC : ADC dbTmp
  TAY
  LDA dbiStats,Y
  RTS

\ ============================================================
\ DbTok â€” PrCapitalString ($2E1E) over sub_0_BE9 ($0BE9)
\ ============================================================
\ Print token A at the cursor, wrapping a whole word to the next line
\ rather than splitting it. Carry clear if it was printed; SET if the
\ wrap ran off the bottom of the page, in which case NOTHING was printed
\ and the caller's index still points at this word.
\
\ THE LEADING SPACE IS DRAWN BEFORE THE MEASURE and stays on the old line
\ when the word wraps â€” $0BF1 draws it unconditionally, and it is where
\ every gap between the words of a name comes from.
\
\ THE MEASURE COUNTS CELLS, NOT LETTERS: a capital is two, and so are
\ lowercase m and w. Capitalisation therefore has to be decided before
\ the measure, not during the draw, or a word starting with a capital
\ would be measured one cell short â€” $2E29 calls ToUpper first for the
\ same reason.
.DbTok
  JSR DbTokFind
  LDA #PN_SPACE
  JSR DbGlyph

  JSR DbMeasure
  CLC
  LDA dbCol
  ADC dbWidth
  CMP #DB_COL_LAST
  BCC db_tk_draw                \ $0C19: it fits on this line
  LDA #DB_COL_MARGIN            \ $0C1D: byte_0_45, and prntY += 2
  STA dbCol
  INC dbLine
  LDA dbLine
  CMP #DB_LINE_LAST+1
  BCS db_tk_full                \ $0C27: off the bottom
  JSR DbAt

.db_tk_draw
  LDY #0
  JSR DbGet
  AND #&7F                      \ the string's first character marker
  LDX dbCap
  BEQ db_tk_put
  CMP #PN_LOWER_A
  BCC db_tk_put
  CMP #PN_LOWER_Z+1
  BCS db_tk_put
  SEC
  SBC #PN_LOWER_A - PN_UPPER_A
.db_tk_put
  LDY #0
  STY dbIx
  JSR DbWide
.db_tk_loop
  LDY dbIx
  INY
  STY dbIx
  JSR DbGet
  BMI db_tk_x                   \ the next token's first character
  JSR DbWide
  JMP db_tk_loop
.db_tk_x
  LDA #0
  STA dbCap                     \ ToUpper clears it whether it fired or not
  CLC
  RTS
.db_tk_full
  LDA #0
  STA dbCap
  SEC
  RTS

\ ---- find token A in the table ------------------------------
\ The C64 has FindStrings' 249 pointers; we scan, as ConTok does, because
\ 498 bytes of index is more than the saving is worth on a page that
\ prints a few dozen words when a key is pressed.
\
\ THE TABLE IS MAIN RAM'S, and shared with the console in bank 6. There
\ used to be a second copy in this bank because neither reader could see
\ the other's; both patch an absolute address, so one copy where they can
\ both reach it does instead — and this bank keeps the 1,542 bytes.
.DbTokFind
  STA dbTmp
  LDA #LO(constrings) : STA db_get+1
  LDA #HI(constrings) : STA db_get+2
  LDA dbTmp
  BEQ db_tf_x                   \ token 0 starts at the first byte
.db_tf_loop
  INC db_get+1
  BNE db_tf_1
  INC db_get+2
.db_tf_1
  LDY #0
  JSR DbGet
  BPL db_tf_loop                \ bit 7 marks a string's first character
  DEC dbTmp
  BNE db_tf_loop
.db_tf_x
  RTS

.DbGet                          \ Y = offset into the token, A = the byte
.db_get
  LDA &FFFF,Y
  RTS

\ ---- how many cells the token needs --------------------------
.DbMeasure
  LDA #0
  STA dbWidth
  LDY #0
  JSR DbGet
  AND #&7F
  LDX dbCap
  BEQ db_m_first
  CMP #PN_LOWER_A
  BCC db_m_first
  CMP #PN_LOWER_Z+1
  BCS db_m_first
  SEC
  SBC #PN_LOWER_A - PN_UPPER_A
.db_m_first
  JSR DbCells
  STA dbWidth
  LDY #1
.db_m_loop
  JSR DbGet
  BMI db_m_x
  JSR DbCells
  CLC
  ADC dbWidth
  STA dbWidth
  INY
  BNE db_m_loop
.db_m_x
  RTS

\ One cell, or two. DrawChar's test on our indices â€” see PnWide.
.DbCells
  CMP #PN_LOWER_M
  BEQ db_c_two
  CMP #PN_LOWER_W
  BEQ db_c_two
  CMP #PN_UPPER_A
  BCC db_c_one
  CMP #PN_UPPER_Z+1
  BCS db_c_one
  CMP #PN_UPPER_I               \ the one narrow capital
  BEQ db_c_one
.db_c_two
  LDA #2
  RTS
.db_c_one
  LDA #1
  RTS

\ ============================================================
\ DbStr / DbSpacedStr â€” a glyph string, $FF terminated
\ ============================================================
\ The strings this file owns are written as glyph indices rather than as
\ text, because PnAscii is in bank 6 with the panel. That is xfer.asm's
\ convention in this bank, for the same reason.
\
\ DbSpacedStr is the height and the weight: the C64 draws both through
\ sub_0_BE9, so they get a token's leading space and a token's wrap.
.DbSpacedStr
  STA db_s_get+1
  STY db_s_get+2
  LDA #PN_SPACE
  JSR DbGlyph
  JMP db_s_start
.DbStr
  STA db_s_get+1
  STY db_s_get+2
.db_s_start
  LDA #0
  STA dbIx
.db_s_loop
  LDY dbIx
.db_s_get
  LDA &FFFF,Y
  CMP #&FF
  BEQ db_s_x
  JSR DbWide
  INC dbIx
  BNE db_s_loop
.db_s_x
  RTS

\ ============================================================
\ DbPanelStr â€” a glyph string into the panel's mode field
\ ============================================================
\ The status line, which is not the play buffer: same stride, different
\ base. More_txt's prntX is 2, which is PN_COL_MODE.
.DbPanelStr
  STA db_p_get+1
  STY db_p_get+2
  LDA #LO(PN_TEXT_ADDR + PN_COL_MODE * 16) : STA pnDst
  LDA #HI(PN_TEXT_ADDR + PN_COL_MODE * 16) : STA pnDst+1
  LDA #0
  STA dbIx
.db_p_loop
  LDY dbIx
.db_p_get
  LDA &FFFF,Y
  CMP #&FF
  BEQ db_p_x
  JSR DbWide
  INC dbIx
  BNE db_p_loop
.db_p_x
  RTS

\ ============================================================
\ DbAt / DbGlyph / DbWide â€” the cursor and the glyphs
\ ============================================================
\ A minimal PnGlyph, as XfGlyphAt is: bank 6 owns the real one and only
\ one bank is visible. The font is main RAM and readable from here.
\ THE INK IS WHITE (logical 3) and not a variable â€” the console draws in logical 1 on
\ every deck, and nothing on this page draws in anything else.
.DbAt
  LDX dbLine
  LDA dbLineLo,X : STA pnDst
  LDA dbLineHi,X : STA pnDst+1
  LDA dbCol                     \ col * 16
  ASL A : ASL A : ASL A : ASL A
  STA dbTmp
  LDA dbCol
  LSR A : LSR A : LSR A : LSR A
  STA dbTmp2
  CLC
  LDA pnDst   : ADC dbTmp  : STA pnDst
  LDA pnDst+1 : ADC dbTmp2 : STA pnDst+1
  RTS

.DbGlyph
  STA pnSrc
  LDA #0
  STA pnSrc+1
  ASL pnSrc : ROL pnSrc+1       \ * 16 — two 8-byte packed cells
  ASL pnSrc : ROL pnSrc+1
  ASL pnSrc : ROL pnSrc+1
  ASL pnSrc : ROL pnSrc+1
  CLC
  LDA pnSrc   : ADC #LO(FONT_ADDR) : STA pnSrc
  LDA pnSrc+1 : ADC #HI(FONT_ADDR) : STA pnSrc+1

  LDA #DB_INK
  STA fontMask
  JSR FontCell                  \ the top cell

  CLC                           \ the bottom cell, one character row on
  LDA pnDst   : ADC #LO(ROW_BYTES) : STA pnDst
  LDA pnDst+1 : ADC #HI(ROW_BYTES) : STA pnDst+1
  CLC
  LDA pnSrc   : ADC #8 : STA pnSrc
  LDA pnSrc+1 : ADC #0 : STA pnSrc+1

  JSR FontCell

  SEC                           \ back up, then on to the next column
  LDA pnDst   : SBC #LO(ROW_BYTES - 16) : STA pnDst
  LDA pnDst+1 : SBC #HI(ROW_BYTES - 16) : STA pnDst+1
  INC dbCol
  RTS

\ Back up one column: $2DAA and $3172's DEC prntX, which closes the
\ double gap a token's own leading space would otherwise leave.
.DbBackOne
  SEC
  LDA pnDst   : SBC #16 : STA pnDst
  LDA pnDst+1 : SBC #0  : STA pnDst+1
  DEC dbCol
  RTS

.DbWide
  CMP #PN_LOWER_M
  BEQ db_w_m
  CMP #PN_LOWER_W
  BEQ db_w_w
  CMP #PN_UPPER_A
  BCC db_w_one
  CMP #PN_UPPER_Z+1
  BCS db_w_one
  CMP #PN_UPPER_I
  BEQ db_w_one
  PHA
  JSR DbGlyph
  PLA
  CLC
  ADC #PN_WIDE_OFS
.db_w_one
  JMP DbGlyph
.db_w_m
  JSR DbGlyph
  LDA #PN_M_RIGHT
  JMP DbGlyph
.db_w_w
  JSR DbGlyph
  LDA #PN_W_RIGHT
  JMP DbGlyph

\ ============================================================
\ DbClear â€” ClearGameScreen ($2763) over the console area
\ ============================================================
\ ConClear's twin, and the same three blocks for the same reason: a row
\ is 640 bytes, which is two pages and a half.
.DbClear
  LDA #&FF                      \ the portrait went with the screen:
  STA poLastType                \ DbImage's guard must not skip the repaint
  LDA #LO(BUF_BASE) : STA pnDst
  LDA #HI(BUF_BASE) : STA pnDst+1
  LDX #PLAY_VIS_ROWS
.db_cl_row
  LDA pnDst   : STA pnSrc
  LDA pnDst+1 : STA pnSrc+1
  LDY #0
  LDA #0
.db_cl_b0
  STA (pnDst),Y
  INY
  BNE db_cl_b0
  INC pnDst+1
.db_cl_b1
  STA (pnDst),Y
  INY
  BNE db_cl_b1
  INC pnDst+1
.db_cl_b2
  STA (pnDst),Y
  INY
  CPY #LO(ROW_BYTES)
  BNE db_cl_b2
  CLC
  LDA pnSrc   : ADC #LO(ROW_BYTES) : STA pnDst
  LDA pnSrc+1 : ADC #HI(ROW_BYTES) : STA pnDst+1
  DEX
  BNE db_cl_row
  RTS

\ ============================================================
\ DbImage â€” the droid being read about: the C64's own portrait
\ ============================================================
\ BuildIntroSprites ($3629) composes a 48 x 84 PORTRAIT here from four
\ sprite images the record names plus their mirrors, and since Layer 13d
\ so do we: PoDraw in portrait.asm, from the pool portraits.asm carries
\ verbatim. The rotor-and-digits stand-in this used to draw is gone,
\ and droidicon7.asm with it.
\
\ GUARDED, unlike the C64's call: theirs writes eight sprite registers,
\ ours repaints ~1K of buffer through a mask, so the browser only pays
\ when the type it shows changes. DbClear invalidates poLastType â€” a
\ cleared screen must repaint whatever the type â€” and page 3's re-entry
\ call comes through the same guard, after the same clear.
.DbImage
  LDA dbType
  CMP poLastType
  BEQ db_i_same
  STA poLastType
  JMP PoDraw                    \ bank 7 to bank 7: a plain JSR-less tail
.db_i_same
  RTS

\ ============================================================
\ The strings this page owns
\ ============================================================
DB_UC = PN_UPPER_A
DB_LC = PN_LOWER_A

.dbTxtUnit                      \ " Unit type "
  EQUB PN_SPACE, DB_UC+20, DB_LC+13, DB_LC+8, DB_LC+19, PN_SPACE
  EQUB DB_LC+19, DB_LC+24, DB_LC+15, DB_LC+4, PN_SPACE, &FF

\ Height_txt ($6C15): "1.HL m", the two digits patched in.
.dbTxtHeight
  EQUB PN_DIGIT0+1, PN_DOT, PN_DIGIT0, PN_DIGIT0, PN_SPACE, DB_LC+12, &FF

\ Weight_txt ($6C1C): "HTU kg", all three digits patched in.
.dbTxtWeight
  EQUB PN_DIGIT0, PN_DIGIT0, PN_DIGIT0, PN_SPACE, DB_LC+10, DB_LC+6, &FF

\ More_txt ($6C08), eleven cells: M is wide, so "More..." plus three
\ spaces fills the mode field exactly.
.dbTxtMore
  EQUB DB_UC+12, DB_LC+14, DB_LC+17, DB_LC+4
  EQUB PN_DOT, PN_DOT, PN_DOT, PN_SPACE, PN_SPACE, PN_SPACE, &FF

\ Console_txt ($69E4), padded to the same eleven so it wipes the prompt.
.dbTxtConsole
  EQUB DB_UC+2, DB_LC+14, DB_LC+13, DB_LC+18, DB_LC+14, DB_LC+11, DB_LC+4
  EQUB PN_SPACE, PN_SPACE, PN_SPACE, &FF

\ ---- the seven text lines, as buffer addresses ---------------
\ A line is two buffer rows. Held whole rather than multiplied, as the
\ console's icon destinations are.
.dbLineLo
FOR n, 0, DB_LINES-1
  EQUB LO(BUF_BASE + n * 2 * ROW_BYTES)
NEXT
.dbLineHi
FOR n, 0, DB_LINES-1
  EQUB HI(BUF_BASE + n * 2 * ROW_BYTES)
NEXT

ASSERT DB_LINE_LAST < DB_LINES
ASSERT (DB_LINE_LAST * 2) + 2 <= PLAY_VIS_ROWS
ASSERT DB_IMG_ROW + 11 <= PLAY_VIS_ROWS  \ the 84-scanline portrait: rows 2-12

\ ---- state --------------------------------------------------
\ conDbReq is in MAIN RAM with the console's other bridge bytes, because
\ ConsoleTick reads it with this bank paged out. Everything else is read
\ and written here alone.
.dbType    EQUB 0               \ the C64's dType, 0 to pmType
.dbPage    EQUB 0               \ dInfoPage
.dbStatN   EQUB 0               \ sub_0_2DA0+1, 13 to 23
.dbDescIx  EQUB 0               \ loc_0_2DE8+1, rebased to 0
.dbLine    EQUB 0               \ prntY, as a text line
.dbCol     EQUB 0               \ prntX
.dbCap     EQUB 0               \ byte_0_248: capitalise the next word
.dbWidth   EQUB 0
.dbIx      EQUB 0
.dbTmp     EQUB 0
.dbTmp2    EQUB 0
.dbPrevF   EQUB 0
.dbPrevU   EQUB 0
.dbPrevD   EQUB 0
.dbPrevL   EQUB 0
.dbPrevR   EQUB 0
