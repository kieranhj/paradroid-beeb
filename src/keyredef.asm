\ ============================================================
\ keyredef.asm — CTRL+R on the briefing: redefine the six keys
\ ============================================================
\ LAYER 11f, and the port's own — the C64 reads a joystick and has
\ nothing of the kind. Six controls (LEFT, RIGHT, UP, DOWN, FIRE,
\ TRANSFER) live in keyTab, the last six bytes of the code image, and
\ every test of one goes through KeyDownIx; this screen is what writes
\ them. [11f DECISION 15, KC 2026-08-30]
\
\ WHERE IT RUNS FROM: BrWaitField, the one hook every loop in BrRun
\ passes through, tests CTRL+R and calls BmKrRun here. The trigger and
\ the return to the page are in briefing.asm; everything else is here,
\ in bank 5, for the reason briefman.asm's header gives — PARBRF has a
\ hard ceiling at &0800 and this is a screen's worth of code and text.
\
\ THE BANK RULE, and it is the delicate part: this file is bank 5 and
\ it calls PARBRF and the code image freely, which is legal. It calls
\ BrWaitField, which reaches BrChatter, which pages bank 4 IN and bank
\ 5 back OUT before it returns — legal too, because all of that happens
\ in main RAM and bank 5 is restored before the RTS lands back here.
\ Nothing below may page a bank itself.
\
\ IT DRAWS THROUGH THE BRIEFING'S OWN ENGINE: BrChar/BrCell/FontCell,
\ the same path the pages are painted with, into the same parked strip,
\ under the same palette. The only thing it adds is BmKrAscii, because
\ PnAscii is in bank 6 and only one bank is visible at a time — the
\ same duplication condb.asm's DbGlyph is, and for the same reason.
\ Having it means the prompts can be EQUS text rather than a table of
\ glyph numbers.
\
\ THE PANEL IS LEFT ALONE. It still says "Briefing" with the last
\ game's score beside it: the panel printer is bank 6's, this is bank
\ 5, and a paging excursion to change one word is not worth it.

\ ---- the layout, in strip rows and 8 px columns -------------
\ Rows 0-1 are the prompt line, 2 is blank, then the six controls two
\ rows apart, ending at 14. A glyph is 8 x 16 — two rows — which is
\ what every step of two here is.
KR_ROW_MSG  = 0
KR_ROW_CTL  = 3                 \ the first control's row
KR_COL_LBL  = 2
KR_COL_KEY  = 14
KR_COL_ASK  = 19                \ where "Press a key for" ends

KR_ESCAPE   = &70               \ ESCAPE's internal key number, not its
                                \ INKEY byte: the scan works in internal
                                \ numbers. &8F EOR &FF, and row 7 col 0
\ Fields a message stands for after the key that caused it is let go.
\ NOTHING IS READ DURING IT — a press inside the hold is dropped, which
\ is why it is not longer: 40 fields is 0.8 s, enough to read three
\ words and short enough that a fast player does not lose the key he
\ presses next. It was 60 while the screen was being built, and driving
\ it from a script at machine speed is what showed that up.
KR_MSG_HOLD = 40

\ ---- the two beeps -----------------------------------------
\ BOTH ARE THE GAME'S OWN EFFECTS, requested the way every other caller
\ requests one: sndFx1 is main RAM, so this bank writes it with no
\ paging at all and the driver walks to the record in bank 4 for
\ itself. $15 is the console menu's step beep, $2CF6's own — the same
\ sound the droid database makes moving down a list, which is exactly
\ what taking a key here is. $1A is the collision bump, and it answers
\ the three presses that change nothing: a duplicate, a key the font
\ cannot name, and ESCAPE.
\ BOTH ARE SHORT AND THAT IS WHY THESE TWO. The records carry their own
\ length in the segment timer, reload and count at offsets +5/+6/+7:
\ $15 is 8 ticks, one segment — 0.16 s — and $1A is four segments of
\ four, about a third of a second. The transfer's failure buzz ($0E)
\ was tried first and is 4 x 32 ticks, two and a half SECONDS of
\ warbling for a mistyped key; measured in jsbeeb, 103 chip writes
\ against the bump's handful, and rejected for it.
\ THE CHATTER IS OFF while this screen is up, so voice 1 is ours and a
\ beep is never cut short by a burble — see BrWaitField.
KR_SFX_OK   = &15               \ effect 21: console beep / page flip
KR_SFX_NO   = &1A               \ effect 26: collision bump

\ ============================================================
\ BmKrRun — the whole screen
\ ============================================================
.BmKrRun
  LDX #CTL_COUNT-1              \ ESCAPE puts these back
.bkr_save
  LDA keyTab,X
  STA bmKrSave,X
  DEX
  BPL bkr_save

\ Park the scroll exactly as br_page does — CTRL+R can be pressed in
\ the middle of a page's travel — and clear all sixteen rows.
  LDA #0
  STA scrollS
  STA scrollS+1
  STA line
  JSR SetCRTCStart
  LDA #15
  STA brStrip
.bkr_clr
  JSR BrClearRow                \ PARBRF's, on brStrip
  DEC brStrip
  BPL bkr_clr

\ The six labels and what each is bound to now.
  LDA #0
  STA bmKrCur
.bkr_lab
  JSR BmKrLabel
  JSR BmKrShow
  INC bmKrCur
  LDA bmKrCur
  CMP #CTL_COUNT
  BNE bkr_lab

\ CTRL and R are still down; nothing is asked until everything is up.
  JSR BmKrWaitUp

  LDA #0
  STA bmKrCur
.bkr_ask
  JSR BmKrPrompt
.bkr_wait
  JSR BrWaitField               \ one scan a field, and the chatter and
  JSR BmKrScan                  \ the volume keys keep running
  CMP #&FF
  BEQ bkr_wait
  CMP #KR_ESCAPE
  BEQ bkr_esc
  TAX
  LDA bmKeyChar-&10,X           \ can the font name it? if not it is not
  BEQ bkr_bad                   \ bindable — see the table's header
  TXA
  EOR #&FF                      \ keyTab holds INKEY bytes, as keydown
  STA bmKrKey                   \ wants them

  LDX bmKrCur                   \ taken by one already set THIS run? the
  BEQ bkr_take                  \ ones still on their defaults are fair
  DEX                           \ game — they may be about to change
.bkr_dup
  LDA keyTab,X
  CMP bmKrKey
  BEQ bkr_used
  DEX
  BPL bkr_dup

.bkr_take
  LDX bmKrCur
  LDA bmKrKey
  STA keyTab,X
  LDA #KR_SFX_OK
  STA sndFx1
  JSR BmKrShow
  JSR BmKrWaitUp
  INC bmKrCur
  LDA bmKrCur
  CMP #CTL_COUNT
  BNE bkr_ask

  LDA #LO(bmKrTxDone)           \ "Keys set", and out
  LDY #HI(bmKrTxDone)
  JMP BmKrMsg                   \ its RTS

\ ESCAPE is never a binding: it abandons the run and gives the six back,
\ with the same buzz the other two refusals get. The page repaints over
\ all of this on the way out.
.bkr_esc
  LDA #KR_SFX_NO
  STA sndFx1
  LDX #CTL_COUNT-1
.bkr_undo
  LDA bmKrSave,X
  STA keyTab,X
  DEX
  BPL bkr_undo
  JMP BmKrWaitUp                \ and its RTS: the press must not carry
                                \ on into the page behind us
.bkr_used
  LDA #LO(bmKrTxUsed)
  LDY #HI(bmKrTxUsed)
  BNE bkr_msg                   \ always
.bkr_bad
  LDA #LO(bmKrTxBad)
  LDY #HI(bmKrTxBad)
.bkr_msg
  LDX #KR_SFX_NO                \ X, not A: A and Y carry the message
  STX sndFx1
  JSR BmKrMsg
  JMP bkr_ask                   \ which redraws the prompt over it

\ ============================================================
\ BmKrScan — which key is down?  A = internal number, or &FF
\ ============================================================
\ keydown tests a key we NAME; this asks the other question, by naming
\ all of them. 112 tests at 55 cycles is ~6,200 a field on a screen
\ with no draw budget to protect, so it borrows keydown rather than
\ driving the matrix a second time.
\
\ IT STARTS AT &10, NOT 0, and that is not tidiness: internal numbers
\ &02-&09 are the KEYBOARD DIP LINKS, which read as pressed or not
\ according to how the machine is strapped, and 0 and 1 are SHIFT and
\ CTRL. The MOS's own OSBYTE &7A scans from 16 for exactly this reason.
\ It also settles the modifiers: SHIFT and CTRL cannot be bound because
\ they are never looked at. [11f DECISION 15]
\
\ Y IS NOT THE COUNTER — keydown loads its own Y for the latch.
.BmKrScan
  LDA #&10
  STA bmKrN
.bks_l
  LDA bmKrN
  EOR #&FF                      \ internal number -> the INKEY byte
  TAX
  JSR keydown
  BEQ bks_hit
  INC bmKrN
  LDA bmKrN
  CMP #&80
  BNE bks_l
  LDA #&FF
  RTS
.bks_hit
  LDA bmKrN
  RTS

\ ---- and the wait for a clear keyboard ----------------------
.BmKrWaitUp
  JSR BrWaitField
  JSR BmKrScan
  CMP #&FF
  BNE BmKrWaitUp
  RTS

\ ============================================================
\ BmKrPrompt / BmKrMsg — the top line
\ ============================================================
.BmKrPrompt
  JSR BmKrClrMsg
  LDA #LO(bmKrTxAsk)
  LDY #HI(bmKrTxAsk)
  LDX #KR_COL_LBL
  JSR BmKrAt
  LDX #KR_COL_ASK               \ and the control's own name after it
  STX bmKrCol
  JMP BmKrLabelStr              \ its RTS

\ A/Y = the message. It stands for KR_MSG_HOLD fields, and until the
\ key that caused it is let go.
\ THE POINTER IS STASHED BEFORE THE CLEAR, not after it: BrClearRow
\ walks Y from 0 to &80 and hands back whatever it ends on, so an A/Y
\ pair held across it loses its high byte and the message is drawn from
\ a wild address. Caught in jsbeeb 2026-08-30, and it scribbled four
\ rows before it stopped.
.BmKrMsg
  STA bmp
  STY bmp+1
  JSR BmKrClrMsg
  LDX #KR_COL_LBL
  STX bmKrCol
  LDX #KR_ROW_MSG
  STX bmKrRow
  JSR BmKrStr
  JSR BmKrWaitUp
  LDX #KR_MSG_HOLD
.bkm_hold
  TXA
  PHA
  JSR BrWaitField
  PLA
  TAX
  DEX
  BNE bkm_hold
  RTS

.BmKrClrMsg
  LDA #KR_ROW_MSG
  STA brStrip
  JSR BrClearRow
  INC brStrip
  JMP BrClearRow                \ its RTS

\ ============================================================
\ BmKrLabel / BmKrShow — one control's line
\ ============================================================
\ Row 3 + cur * 2: the label on the left, the key it is bound to at
\ KR_COL_KEY. BmKrShow blanks twelve cells first, because the name it
\ is replacing may be longer than the one going in.
.BmKrLabel
  LDX #KR_COL_LBL
  STX bmKrCol
  JSR BmKrRowCur
  JMP BmKrLabelStr              \ its RTS

.BmKrLabelStr                   \ bmKrCol/bmKrRow set; label bmKrCur
  LDA bmKrCur
  ASL A
  TAX
  LDA bmKrLabels+0,X
  STA bmp
  LDA bmKrLabels+1,X
  STA bmp+1
  JMP BmKrStr                   \ its RTS

.BmKrShow
  JSR BmKrRowCur
  LDX #KR_COL_KEY
  STX bmKrCol
  LDA #LO(bmKrBlank)
  LDY #HI(bmKrBlank)
  JSR BmKrPut
  LDX bmKrCur                   \ the INKEY byte back to a key number,
  LDA keyTab,X                  \ which is what the name table indexes
  EOR #&FF
  TAX
  LDA bmKeyChar-&10,X
  CMP #32
  BCS bks_one                   \ >= 32: it prints as itself
  CMP #11
  BCS bks_named                 \ 11 and up: a name from the list

  CLC                           \ 1-10 are f0-f9: 'f' and the digit
  ADC #'0'-1
  TAY
  LDA #'f'
  STA bmKrBuf
  STY bmKrBuf+1
  LDA #0
  STA bmKrBuf+2
  BEQ bks_buf                   \ always

.bks_one
  STA bmKrBuf
  LDA #0
  STA bmKrBuf+1
.bks_buf
  LDA #LO(bmKrBuf)
  LDY #HI(bmKrBuf)
  JMP BmKrPut                   \ its RTS

\ 11 and up: walk the packed name list to the one wanted
.bks_named
  SEC
  SBC #11
  TAX
  LDA #LO(bmKrNames)
  STA bmp
  LDA #HI(bmKrNames)
  STA bmp+1
.bkn_next
  CPX #0
  BEQ BmKrStr                   \ arrived — and its RTS
  LDY #0
.bkn_scan
  LDA (bmp),Y
  BEQ bkn_end
  INY
  BNE bkn_scan
.bkn_end
  INY                           \ past the terminator
  TYA
  CLC
  ADC bmp
  STA bmp
  BCC bkn_nc
  INC bmp+1
.bkn_nc
  DEX
  JMP bkn_next

\ bmKrRow = the row of control bmKrCur
.BmKrRowCur
  LDA bmKrCur
  ASL A
  CLC
  ADC #KR_ROW_CTL
  STA bmKrRow
  RTS

\ ============================================================
\ BmKrAt / BmKrPut / BmKrStr — the text, through BrChar
\ ============================================================
\ BmKrAt takes A/Y = string and X = column and draws it on the message
\ row; BmKrPut takes A/Y with the row and column already set; BmKrStr
\ draws whatever bmp points at.
.BmKrAt
  STX bmKrCol
  LDX #KR_ROW_MSG
  STX bmKrRow
.BmKrPut
  STA bmp
  STY bmp+1
.BmKrStr
  LDA #0                        \ the top cells of every glyph...
  STA brHalf
  JSR bmks_line
  INC bmKrRow
  LDA #8                        \ ...then the bottom ones, a row down
  STA brHalf
  JSR bmks_line
  DEC bmKrRow
  RTS

\ One pass along the string. swDst = the row base + col * 16; brT/brT2
\ are PARBRF's own scratch, idle here — BrRowList is not running.
\ BrChar preserves Y, which is why the index can stay in it.
.bmks_line
  LDA bmKrCol
  STA brT
  LDA #0
  ASL brT : ROL A
  ASL brT : ROL A
  ASL brT : ROL A
  ASL brT : ROL A
  STA brT2
  LDX bmKrRow
  CLC
  LDA brRowBLo,X : ADC brT  : STA swDst
  LDA brRowBHi,X : ADC brT2 : STA swDst+1
  LDY #0
.bmks_l
  LDA (bmp),Y
  BEQ bmks_x
  JSR BmKrAscii
  JSR BrChar                    \ PARBRF's: the wide-capital rule, the
  INY                           \ cell, and swDst one column on
  BNE bmks_l
.bmks_x
  RTS

\ ============================================================
\ BmKrAscii — A = ASCII, out = glyph index
\ ============================================================
\ PnAscii, transcribed. Bank 6 owns the original and only one bank is
\ visible at a time; this is the same duplication DbGlyph is. Anything
\ unmapped comes out as a space rather than as a wild index.
.BmKrAscii
  CMP #'a'
  BCC bka_upper
  CMP #'z'+1
  BCS bka_bad
  SEC : SBC #'a'
  CLC : ADC #PN_LOWER_A
  RTS
.bka_upper
  CMP #'A'
  BCC bka_digit
  CMP #'Z'+1
  BCS bka_bad
  SEC : SBC #'A'
  CLC : ADC #PN_UPPER_A
  RTS
.bka_digit
  CMP #'0'
  BCC bka_punct
  CMP #'9'+1
  BCS bka_punct
  SEC : SBC #'0'
  CLC : ADC #PN_DIGIT0
  RTS
.bka_punct
  CMP #'.'
  BNE bka_dash
  LDA #PN_DOT
  RTS
.bka_dash
  CMP #'-'
  BNE bka_colon
  LDA #PN_DASH
  RTS
.bka_colon
  CMP #':'
  BNE bka_bad
  LDA #PN_COLON
  RTS
.bka_bad
  LDA #PN_SPACE
  RTS

\ ============================================================
\ bmKeyChar — internal key number &10-&7F -> how to name it
\ ============================================================
\ THE MATRIX, ROW BY ROW. An entry is either a printable ASCII code
\ (>= 32, printed as itself), 1-10 for f0-f9, 11 and up for a name in
\ bmKrNames, or 0 for "this key cannot be bound".
\
\ ZERO MEANS THE FONT CANNOT NAME IT, and that is the whole rule for
\ what is bindable: ^ _ [ ] @ ; , / and \ have no glyph in the shared
\ set, so a key bound to one would show as a blank and the player would
\ have no way to see what he had done. They are refused instead, with
\ "Not usable" [11f DECISION 15]. Columns 10-15 do not exist in the
\ matrix at all.
\
\ THE LAYOUT IS CONFIRMED BY OUR OWN CONSTANTS, not recalled: KEY_Z,
\ KEY_X, KEY_K, KEY_M, KEY_L, KEY_SPACE, KEY_P, KEY_Q, KEY_R, KEY_C,
\ KEY_W, KEY_LBRK, KEY_RBRK, KEY_UP, KEY_DOWN and KEY_ESCAPE all EOR
\ &FF to exactly the positions below.
.bmKeyChar
  EQUB 'Q', '3', '4', '5', 5, '8', 8, '-', 0, 21   \ &10: Q 3 4 5 f4 8 f7 - ^ LEFT
  EQUB 0, 0, 0, 0, 0, 0                            \ columns 10-15: no key
  EQUB 1, 'W', 'E', 'T', '7', 'I', '9', '0', 0, 20 \ &20: f0 W E T 7 I 9 0 _ DOWN
  EQUB 0, 0, 0, 0, 0, 0
  EQUB '1', '2', 'D', 'R', '6', 'U', 'O', 'P', 0, 19 \ &30: 1 2 D R 6 U O P [ UP
  EQUB 0, 0, 0, 0, 0, 0
  EQUB 17, 'A', 'X', 'F', 'Y', 'J', 'K', 0, ':', 12  \ &40: CAPS A X F Y J K @ : RETURN
  EQUB 0, 0, 0, 0, 0, 0
  EQUB 18, 'S', 'C', 'G', 'H', 'N', 'L', 0, 0, 13    \ &50: SHFTLK S C G H N L ; ] DELETE
  EQUB 0, 0, 0, 0, 0, 0
  EQUB 15, 'Z', 11, 'V', 'B', 'M', 0, '.', 0, 14     \ &60: TAB Z SPACE V B M , . / COPY
  EQUB 0, 0, 0, 0, 0, 0
  EQUB 16, 2, 3, 4, 6, 7, 9, 10, 0, 22               \ &70: ESC f1 f2 f3 f5 f6 f8 f9 \ RIGHT
  EQUB 0, 0, 0, 0, 0, 0

\ Codes 11 up, in order, each terminated. ESCAPE's entry is here for
\ completeness only — bkr_wait catches it before the table is read.
.bmKrNames
  EQUS "Space"   : EQUB 0        \ 11
  EQUS "Return"  : EQUB 0        \ 12
  EQUS "Delete"  : EQUB 0        \ 13
  EQUS "Copy"    : EQUB 0        \ 14
  EQUS "Tab"     : EQUB 0        \ 15
  EQUS "Escape"  : EQUB 0        \ 16
  EQUS "Caps"    : EQUB 0        \ 17
  EQUS "Shiftlk" : EQUB 0        \ 18
  EQUS "Up"      : EQUB 0        \ 19
  EQUS "Down"    : EQUB 0        \ 20
  EQUS "Left"    : EQUB 0        \ 21
  EQUS "Right"   : EQUB 0        \ 22

\ ---- the six, in CTL_* order -------------------------------
.bmKrLabels
  EQUW bmKrLbLeft
  EQUW bmKrLbRight
  EQUW bmKrLbUp
  EQUW bmKrLbDown
  EQUW bmKrLbFire
  EQUW bmKrLbXfer
.bmKrLbLeft   EQUS "Left"     : EQUB 0
.bmKrLbRight  EQUS "Right"    : EQUB 0
.bmKrLbUp     EQUS "Up"       : EQUB 0
.bmKrLbDown   EQUS "Down"     : EQUB 0
.bmKrLbFire   EQUS "Fire"     : EQUB 0
.bmKrLbXfer   EQUS "Transfer" : EQUB 0

.bmKrTxAsk    EQUS "Press a key for"  : EQUB 0
.bmKrTxUsed   EQUS "Already used"     : EQUB 0
.bmKrTxBad    EQUS "Not usable"       : EQUB 0
.bmKrTxDone   EQUS "Keys set"         : EQUB 0
.bmKrBlank    EQUS "            "     : EQUB 0   \ twelve cells of key field

\ ---- state, all of it this file's --------------------------
.bmKrSave  SKIP CTL_COUNT       \ what ESCAPE puts back
.bmKrCur   EQUB 0               \ which control is being asked for
.bmKrKey   EQUB 0               \ the INKEY byte of the answer
.bmKrN     EQUB 0               \ BmKrScan's counter
.bmKrRow   EQUB 0               \ the text cursor
.bmKrCol   EQUB 0
.bmKrBuf   SKIP 3               \ a one- or two-character name
