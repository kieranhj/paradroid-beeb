\ ============================================================
\ infoscr.asm — the droid information screens
\ ============================================================
\ LAYER 11d, in SWRAM BANK 7 beside the database page whose machinery it
\ borrows. Four screens, all the same shape: the play area becomes a
\ picture of one droid with a paragraph of text beside it, and the
\ paragraph is a list of TOKEN NUMBERS into the $C000 string pool.
\
\   NewShipInfo   ($36B9)  the 001 you start a ship as, and the ship's
\                          name — "prepare to board Robo-Freighter ..."
\   ShowXferInfo  ($3734)  TWO pages before the transfer game: the unit
\                          you currently control, then the one you wish to
\   EndGame       ($378B)  the 999 behind "Transmission / Terminated"
\
\ THE PRINTER IS ALREADY BUILT. PrintTokenString ($36DB) is a loop over a
\ token list around PrCapitalString ($2E1E), and Layer 9 ported both for
\ the database page's description: DbTok prints one token with the wrap
\ and the capitalisation, and reports a full screen in the carry. So this
\ file is the LOOP and the SCREENS, not a second text engine. IsPrint is
\ PrintTokenString's own body; everything under it is condb.asm's.
\
\ THE GEOMETRY IS THE DATABASE PAGE'S, and that is exact rather than
\ convenient: the C64 puts the name at screen row 10 and steps the
\ content lines 12, 14 ... 22, which is condb's seven lines, and
\ PrintTokenString's prntX 9 / prntY 12 is line 1, column 9. See the
\ geometry block in condb.asm. [DECISION 1]
\
\ WHAT IT CAN AND CANNOT REACH: main RAM freely — the font, the PN_TABS
\ droid mirrors, the play buffer, keydown — and bank 4 not at all. The
\ screen id and the two droid types come in through main RAM, the way
\ the transfer game's do.

\ ---- the four screens ---------------------------------------
IS_SCR_001   = 0                \ NewShipInfo
IS_SCR_XFER1 = 1                \ ShowXferInfo, the unit you control
IS_SCR_XFER2 = 2                \ ShowXferInfo, the unit you want
IS_SCR_OVER  = 3                \ EndGame's page

\ ---- what happens when the screen is dismissed ---------------
\ Left in infoAct for the main-RAM half to act on, because all three
\ continuations are things this bank cannot do: ReframeView redraws the
\ deck from BANK 4, XferEnter and GoTitle page banks, and no bank may
\ page itself out from under its own feet.
\
\ The transfer's page turn is NOT one of them — IsDone chains straight
\ into the second page, which needs no paging at all.
IS_ACT_GAME  = 0                \ back to the deck
IS_ACT_BOARD = 1                \ on into the transfer game
IS_ACT_TITLE = 2                \ the game over: on to the title

\ ---- the hold ------------------------------------------------
\ $371F counts 72 down, each iteration a ReadJoystick and a
\ DelayScore(32) — two nested busy loops, about 41,000 cycles, so the
\ hold is 72 * 0.04 s ≈ 2.9 seconds and fire cuts it short. At 25 Hz
\ 72 PASSES is 2.88 s, so the count ports across unchanged and lands on
\ the same wall clock by arithmetic rather than by luck. [DECISION 3]
IS_HOLD = 72

IS_TOK_BREAK = &FE              \ a full stop, and a capital next
IS_TOK_END   = &FF

\ $36E5's prntX. The database page's own DB_COL_LABEL is the same 9, and
\ this is deliberately a second name for it rather than a reuse: the two
\ are equal in the original and nothing says they must stay so.
DB_COL_TOKEN = 9

IS_OVER_TYPE = 23               \ $37E4: dType = $17, the 999

IS_BLANK = &FF                  \ IsEntry's third door, and not a screen

\ ============================================================
\ IsBlank — black the play area before the rupture shows it
\ ============================================================
\ THE TITLE'S FRAMEBUFFER IS &4000-&7E7F AND THE PLAY BUFFER IS INSIDE
\ IT. TitleSeq rebuilds the panel and the &5400 tables over their share
\ of that ground, but nothing owns &5800-&7FFF until something draws
\ there — and with the 001 screen now holding LoadDeck's redraw back,
\ that is not until the page is printed. In between, SetupRupture starts
\ displaying the strip, and what it displays is the title, smeared.
\
\ So TitleSeq blanks it on the way past, and the page prints onto black.
\ It is DbClear because DbClear is already exactly this — and because the
\ page is about to call it again anyway, which costs 60,000 cycles once
\ and buys not having a second clear in main RAM, where there is no room
\ for one.
\
\ infoAct IS SET so that InfoCall's continuation reads $FF and does
\ nothing. At this point in the boot the byte has never been written —
\ lowbss is SKIPped, not loaded — and a garbage 0 there would send the
\ shim into ReframeView before there is a deck to draw.
.IsBlank
  LDA #&FF
  STA infoAct
  JMP DbClear                   \ and its RTS

\ ============================================================
\ IsEntry — one door, because paging is expensive in BYTES
\ ============================================================
\ InfoCall is in the low overlay and every PAGEBANK there costs 8 bytes
\ of main RAM the port does not have. So the two entry points share one
\ paged region and this picks between them: X = 0 is a tick, anything
\ else is screen id + 1.
\
\ IT IS X AND NOT A BECAUSE PAGEBANK IS `LDA #bank`. The selector has to
\ survive the paging that happens between the caller setting it and this
\ reading it, and A does not — passed in A, every tick arrived as 7 and
\ redrew screen 6 instead, forever.
\
\ X = $FF is a third door, and it opens no screen: it is the blank the
\ rupture needs — see IsBlank.
.IsEntry
  TXA
  BNE is_en_start
  JMP IsTick
.is_en_start
  CPX #IS_BLANK
  BNE is_en_scr
  JMP IsBlank
.is_en_scr
  SEC
  SBC #1
                                \ falls into IsStart

\ ============================================================
\ IsStart — draw one screen and arm the wait
\ ============================================================
\   A = screen id
\ The type each screen shows is not a parameter: three of the four are
\ fixed and the fourth pair comes from the transfer's own mirrors, which
\ XferEnter4 filled before any of this could run.
.IsStart
  STA isScr
  TAX
  LDA isTypeFor,X
  BPL is_st_fixed               \ a literal type, or $FF/$FE for a mirror
  CMP #&FF
  BNE is_st_tgt
  LDA pmType                    \ the player's own, PanelTick's mirror —
  JMP is_st_fixed               \ NOT a BNE, because type 0 is the 001 and
.is_st_tgt                      \ that is most of the game
  LDA xfmTgtType
.is_st_fixed
  STA dbType

\ ---- flatten the strip, ConsoleOpen's own -------------------
\ The page addresses the buffer as a plain 16 x 640 array through
\ dbLineLo/Hi, so the scroll has to be parked first — exactly what
\ ConsoleOpen and XferEnter4 do before the console and the board, and
\ for exactly the same reason.
\
\ IT IS HERE, IN BANK 7, and not in either of theirs: every one of these
\ is a main-RAM variable and SetCRTCStart is main RAM too (bufcore.asm,
\ which exists so that bank code can reach it), so this bank can do the
\ whole thing itself — and main RAM below &3000 has nothing left to
\ spend on a fourth copy of it.
  LDA #0
  STA scrollS : STA scrollS+1
  STA line
  STA iline
  STA bandDo
  STA colCount
  JSR SetCRTCStart

  JSR DbClear                   \ $36BE ClearGameScreen, and it resets
                                \ poLastType so the portrait repaints

  LDA isScr
  CMP #IS_SCR_OVER
  BNE is_st_norm                \ the game over has no name line and no
  JMP IsOverDraw                \ tokens — two plain strings instead
.is_st_norm

  JSR DbName                    \ $36C1 ShowRobotType
  JSR DbImage                   \ $36C4 BuildIntroSprites

  LDA isScr
  CMP #IS_SCR_001
  BNE is_st_tok
  JSR IsShip                    \ $36C7: the ship's name into the string

.is_st_tok
  LDX isScr                     \ the token list, and NewShipInfo's own
  LDA isTokLo,X : STA is_tk_get+1
  LDA isTokHi,X : STA is_tk_get+2
  JSR IsPrint
.IsArm
  LDA #0                        \ $371C WaitNoFire: the press that opened
  STA isPhase                   \ the screen is still down
  LDA #IS_HOLD
  STA isHold
  LDA #1
  STA infoActive
  LDA #&FF                      \ "no continuation yet" — InfoCall reads
  STA infoAct                   \ this ONE byte rather than two
  RTS

\ ============================================================
\ IsPrint — PrintTokenString ($36DB), the loop
\ ============================================================
\ $36E5-$36ED set prntX 9 and prntY 12 AND the margins byte_0_45/46 that
\ a wrapped line returns to; ours are dbCol/dbLine and DB_COL_MARGIN,
\ which is 12 and NOT 9 — the database page's own margin, kept because
\ DbTok reads it and because a wrapped line indenting past the label
\ column is what the C64 does on both screens.
\
\ $36E0's `STA byte_0_248` capitalises the first word: A arrives holding
\ whatever the caller left, which is never zero at either call site.
\ We say so instead of relying on it.
\
\ A FULL SCREEN IS DROPPED, not continued. DbTok returns carry set when
\ the text runs off line 6 and the database page uses that to paginate;
\ these screens have no "More...", and none of the three paragraphs comes
\ close — the longest is nineteen tokens over six lines. The carry is
\ still honoured so an over-long string truncates instead of scribbling.
.IsPrint
  LDA #DB_COL_TOKEN
  STA dbCol
  LDA #DB_LINE_FIRST
  STA dbLine
  JSR DbAt
  LDA #1
  STA dbCap
  LDA #0
  STA isIx

.is_tk_loop
  LDY isIx
.is_tk_get
  LDA &FFFF,Y
  CMP #IS_TOK_END
  BEQ is_tk_x
  CMP #IS_TOK_BREAK
  BNE is_tk_word

  LDA #PN_DOT                   \ $36FB: the sentence's full stop, and
  JSR DbGlyph                   \ $3716 capitalises what follows
  LDA #1
  STA dbCap
  JMP is_tk_next

.is_tk_word
  JSR DbTok
  BCS is_tk_x                   \ the screen filled
.is_tk_next
  INC isIx
  BNE is_tk_loop                \ 256 tokens is the C64's own bound
.is_tk_x
  RTS

\ ============================================================
\ IsOverDraw — EndGame's page ($37DC-$37FB)
\ ============================================================
\ dType $17 and TWO PLAIN STRINGS, not tokens: "Transmission" at the
\ C64's prntY 10 / prntX 13 and "Terminated" at prntY 22 / prntX 14 —
\ which are our lines 0 and 6, the name line and the last content line,
\ with the portrait between them. The 999 is the only droid in the game
\ the player has not necessarily seen, and that is the point of it.
\
\ $37E8's `STA loc_0_365E+1` IS THE SPRITE'S X, not a colour: 160 in
\ place of BuildIntroSprites' own 40, which is 136 px in from the first
\ visible column and puts the 48 px picture dead centre. So the 999 is
\ centred and the other three pages are not — poBase carries it, and
\ PoDraw's own header has the arithmetic.
.IsOverDraw
  LDA #LO(PO_DSTMID)
  STA poBase
  LDA #HI(PO_DSTMID)
  STA poBase+1
  LDA dbType                    \ NOT DbImage: that sets the database
  STA poLastType                \ page's rectangle back again
  JSR PoDraw

  LDA #0
  STA dbLine
  LDA #IS_OVER_COL1
  STA dbCol
  JSR DbAt
  LDA #LO(isTxtTrans) : LDY #HI(isTxtTrans)
  JSR DbStr

  LDA #DB_LINE_LAST
  STA dbLine
  LDA #IS_OVER_COL2
  STA dbCol
  JSR DbAt
  LDA #LO(isTxtTerm) : LDY #HI(isTxtTerm)
  JSR DbStr
  JMP IsArm

\ ============================================================
\ IsTick — the wait, one pass ($371C-$3733)
\ ============================================================
\ Two phases, the C64's two: WaitNoFire holds while the button that got
\ here is still down, then the 72-count runs and a press inside it ends
\ the screen early. Ours is the same shape with keydown in place of
\ ReadJoystick — and no debounce count, because the port's pages are
\ edge triggered and every one of them reads the release this way.
.IsTick
  LDX #KEY_L
  JSR keydown                   \ Z set = the key is DOWN
  PHP
  LDA isPhase
  BNE is_tk_armed

  PLP
  BEQ is_tk_x2                  \ still down: this is the press that
  LDA #1                        \ opened the screen, so it does not close it
  STA isPhase
  RTS

.is_tk_armed
  PLP
  BEQ IsDone                    \ $3731: a press inside the count leaves
  DEC isHold
  BEQ IsDone
.is_tk_x2
  RTS

\ ---- the screen is over: what follows it --------------------
\ The transfer's two pages chain HERE rather than in the caller, because
\ only this side knows which of them was up — and because the turn then
\ costs no paging and no main-RAM arm.
.IsDone
  LDA #0
  STA infoActive
  LDX isScr
  CPX #IS_SCR_XFER1
  BNE is_dn_act
  LDA #IS_SCR_XFER2
  JMP IsStart
.is_dn_act
  LDA isActFor,X
  STA infoAct
  RTS

\ ============================================================
\ The tables and the token lists
\ ============================================================
\ THE TOKEN BYTES ARE THE C64'S, byte for byte from $6DA0, $6DB5 and
\ $6DBF. They index the same pool in the same order — export_strings.py
\ translates the GLYPHS and preserves the numbering — so nothing here had
\ to be re-authored, and the sentences come out in the original's words.

.isTokLo
  EQUB LO(isTok001), LO(isTokXf1), LO(isTokXf2), 0
.isTokHi
  EQUB HI(isTok001), HI(isTokXf1), HI(isTokXf2), 0

\ $FF is the player's own type, from PanelTick's pmType mirror, and $FE
\ the transfer target's, which the trigger site gathers because only main
\ RAM can see bank 4's drType. Anything else is a literal type.
.isTypeFor
  EQUB 0, &FF, &FE, IS_OVER_TYPE

\ Entry 1 is never read: the first transfer page chains inside IsDone.
.isActFor
  EQUB IS_ACT_GAME, IS_ACT_GAME, IS_ACT_BOARD, IS_ACT_TITLE

\ "This is the unit that you currently control. Prepare to board
\  Robo-<ship> influence to eliminate all rogue robots."
\
\ THE SHIP'S NAME IS PATCHED IN, as $36C7 patches it: NewShip_txt+$D is
\ the fourteenth token of this very string, and it takes 104 + shipLevel
\ — tokens 105 upward are Paradroid, Metahawk, Hewstromo, Graftgold and
\ the rest of the eight. isShipTok is that byte.
.isTok001
  EQUB &2A, &33, &29, &5D, &5E, &5F, &60, &54, &FE
  EQUB &62, &2E, &63, &64
.isShipTok
  EQUB &00                      \ $6DAD: 104 + shipLevel, written by IsShip
  EQUB &2E, &65, &66, &67, &68, &FE, &FF

\ "This is the unit that you currently control."
.isTokXf1
  EQUB &2A, &33, &29, &5D, &5E, &5F, &60, &54, &FE, &FF

\ "This is the unit that you wish to control. Prepare to transfer."
.isTokXf2
  EQUB &2A, &33, &29, &5D, &5E, &5F, &72, &2E, &54, &FE
  EQUB &62, &2E, &71, &FE, &FF

\ ---- IsShip — the patch, from the main-RAM mirror -----------
\ shipLevel is bank 4's and this bank cannot see it; pmShip is the
\ mirror the console already keeps for the same reason.
.IsShip
  LDA pmShip
  CLC
  ADC #IS_TOK_SHIP0
  STA isShipTok
  RTS

IS_TOK_SHIP0 = 104              \ $36CA's own constant

\ ---- EndGame's two strings ($6E30, $6E3F) -------------------
IS_OVER_COL1 = 13               \ their prntX, unchanged
IS_OVER_COL2 = 14

.isTxtTrans                     \ "Transmission"
  EQUB DB_UC+19, DB_LC+17, DB_LC+0, DB_LC+13, DB_LC+18, DB_LC+12
  EQUB DB_LC+8, DB_LC+18, DB_LC+18, DB_LC+8, DB_LC+14, DB_LC+13, &FF
.isTxtTerm                      \ "Terminated"
  EQUB DB_UC+19, DB_LC+4, DB_LC+17, DB_LC+12, DB_LC+8, DB_LC+13
  EQUB DB_LC+0, DB_LC+19, DB_LC+4, DB_LC+3, &FF

\ ---- state, all of it this bank's ---------------------------
.isScr    EQUB 0
.isPhase  EQUB 0                \ 0 waiting for the release, 1 counting
.isHold   EQUB 0                \ $3721's 72
.isIx     EQUB 0                \ xfer_plySpriteX, the token index
