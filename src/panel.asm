\ ============================================================
\ panel.asm — the text engine, and the in-game HUD
\ ============================================================
\ LAYER 9. In SWRAM BANK 6, with console.asm. It started in bank 4, next
\ to the droid tables, and the console pushed that bank 224 bytes past
\ &C000 — see the note by the INCLUDE in main.asm.
\ **THIS FILE CANNOT READ BANK 4.** drType, drEnergy, drCount, shipLevel
\ and the four droid tables all live there. main.asm's PanelTick mirrors
\ the scalars into pmType/pmEnergy/pmCount/pmShip before paging this bank
\ in, and PageTabsIn copies the tables to PN_TABS at boot. Everything
\ else here reads main RAM directly. See docs/layer-9-hud.md.
\
\ ---- the font is 8 x 16, and that decides the layout --------
\ The C64 text charset at $7000 stores a glyph's TOP half at code c and
\ its BOTTOM half at c + $80. A MODE 1 character cell is 8 px by 8
\ scanlines and 16 bytes, so a glyph is TWO STACKED CELLS, 32 bytes.
\
\ The panel is PANEL_ROWS = 5 character rows, so it holds exactly TWO
\ lines of 40 characters with one row spare. The C64's eight status rows
\ hold four such lines. That is geometry, not effort: the 5-row panel was
\ fixed in Layer 3 by the rupture and the 10K wrap.
\
\ ---- why the panel is easy where the play area is not -------
\ The panel does not scroll and nothing is blitted over it, so:
\   - there is no circular strip and no wrap test;
\   - a cell address is a flat PANEL_ADDR + row*640 + col*16;
\   - nothing has to be saved or restored.
\ A glyph is therefore two 16-byte copies to fixed addresses, which is
\ the same flat copy the tile draw makes and for the same reason.
\
\ ---- the font lives in MAIN RAM ----------------------------
\ At FONT_ADDR, copied out of bank 6 at boot by PageFontIn. It has to:
\ this code is in bank 4, the font ships in bank 6 and only one bank is
\ visible at a time. Reading it from main RAM costs no paging here and
\ leaves it reachable from Layer 10 as well.

\ ---- the two pointers are BORROWED zero page ----------------
\ (pnSrc),Y and (pnDst),Y need zero page and zero page has been full
\ since Layer 5, so they take swSrc and swDst — the startup bank-copy
\ pointers, dead from LoadDeck onwards. MapGuard borrows the same pair
\ for the same reason and is now off; the debug readouts borrow swDst
\ and are replaced by this file. **Nothing may call the panel engine
\ from inside PageBankIn or PageFontIn**, which is the only window where
\ they are live, and both run once at boot.
pnSrc = swSrc
pnDst = swDst

\ Glyph indices, as tools/export_font.py emits them.
PN_SPACE    = 0
PN_DIGIT0   = 1
PN_UPPER_A  = 11                \ the LEFT half; the right is +PN_WIDE_OFS
PN_UPPER_Z  = 36
PN_WIDE_OFS = 26
PN_LOWER_A  = 63
PN_DOT      = 89
PN_BAR_ON   = 90
PN_BAR_OFF  = 91

\ ---- CAPITALS ARE TWO CELLS WIDE ---------------------------
\ DrawChar ($0C5F) writes the code, then tests it:
\   AND #$7F : CMP #$3A : BCC _1 : CMP #$5A : BCS _1  \ "see if it was wide"
\   LDY #1 : ADC #$20 : STA (cpyDest),Y ... : INC prntX
\ so a capital's right half is at C64 code + $20 and it occupies two
\ character cells. The export splits each into two glyphs and PnStr
\ draws the second whenever the first is a capital — the same test, in
\ the same place. Lowercase and digits stay one cell.

PN_COLS    = 40                 \ characters across the panel
PN_LINES   = PANEL_ROWS DIV 2   \ 8x16 glyphs: two character rows each
ASSERT PN_LINES == 2

\ ============================================================
\ PnAt — point pnDst at text cell (pnLine, pnCol)
\ ============================================================
\ The glyph's top cell; its bottom cell is ROW_BYTES further on, which
\ the draw adds as it goes rather than keeping a second pointer.
\
\ pnLine * 2 * ROW_BYTES is 1280 per line, and there are only two lines,
\ so the multiply is a shift and an add rather than a table.
.PnAt
  LDA pnCol                     \ col * 16
  ASL A : ASL A : ASL A : ASL A
  STA pnDst
  LDA pnCol
  LSR A : LSR A : LSR A : LSR A \ the carry out of col*16
  STA pnDst+1

  CLC
  LDA pnDst   : ADC #LO(PANEL_ADDR) : STA pnDst
  LDA pnDst+1 : ADC #HI(PANEL_ADDR) : STA pnDst+1

  LDA pnLine
  BEQ pn_at_x
  CLC                           \ line 1 is 2 * ROW_BYTES down
  LDA pnDst   : ADC #LO(2*ROW_BYTES) : STA pnDst
  LDA pnDst+1 : ADC #HI(2*ROW_BYTES) : STA pnDst+1
.pn_at_x
  RTS

\ ============================================================
\ PnGlyph — draw glyph A at pnDst, then advance one column
\ ============================================================
\ 32 bytes: the top cell at pnDst, the bottom cell one character row on.
\ A glyph index times 32 needs 11 bits, so the multiply is done into
\ pnSrc as a 16-bit value rather than through a table — 66 glyphs would
\ need a 132-byte pair of tables to save eight cycles.
.PnGlyph
  STA pnSrc
  LDA #0
  STA pnSrc+1
  ASL pnSrc : ROL pnSrc+1       \ * 32
  ASL pnSrc : ROL pnSrc+1
  ASL pnSrc : ROL pnSrc+1
  ASL pnSrc : ROL pnSrc+1
  ASL pnSrc : ROL pnSrc+1
  CLC
  LDA pnSrc   : ADC #LO(FONT_ADDR) : STA pnSrc
  LDA pnSrc+1 : ADC #HI(FONT_ADDR) : STA pnSrc+1

  LDY #15                       \ the top cell
.pn_top
  LDA (pnSrc),Y
  STA (pnDst),Y
  DEY
  BPL pn_top

  CLC                           \ down one character row for the bottom
  LDA pnDst   : ADC #LO(ROW_BYTES) : STA pnDst
  LDA pnDst+1 : ADC #HI(ROW_BYTES) : STA pnDst+1
  CLC
  LDA pnSrc   : ADC #16 : STA pnSrc
  LDA pnSrc+1 : ADC #0  : STA pnSrc+1

  LDY #15
.pn_bot
  LDA (pnSrc),Y
  STA (pnDst),Y
  DEY
  BPL pn_bot

  SEC                           \ back up, then on to the next column
  LDA pnDst   : SBC #LO(ROW_BYTES - 16) : STA pnDst
  LDA pnDst+1 : SBC #HI(ROW_BYTES - 16) : STA pnDst+1
  RTS

\ ============================================================
\ PnAscii — A = ASCII, out = glyph index
\ ============================================================
\ Four compares, which is why the exported table is contiguous rather
\ than indexed by C64 code. It exists so the source can say
\ `EQUS "Mobile"` instead of carrying a table of glyph numbers, and the
\ strings stay readable.
\
\ Anything unmapped comes out as a space rather than as a wild index —
\ a bad index would read past the font and draw whatever follows it.
.PnAscii
  CMP #'a'
  BCC pn_a_upper
  CMP #'z'+1
  BCS pn_a_bad
  SEC : SBC #'a'
  CLC : ADC #PN_LOWER_A
  RTS
.pn_a_upper
  CMP #'A'
  BCC pn_a_digit
  CMP #'Z'+1
  BCS pn_a_bad
  SEC : SBC #'A'
  CLC : ADC #PN_UPPER_A
  RTS
.pn_a_digit
  CMP #'0'
  BCC pn_a_punct
  CMP #'9'+1
  BCS pn_a_bad
  SEC : SBC #'0'
  CLC : ADC #PN_DIGIT0
  RTS
.pn_a_punct
  CMP #'.'
  BNE pn_a_bad
  LDA #PN_DOT
  RTS
.pn_a_bad
  LDA #PN_SPACE
  RTS

\ ============================================================
\ PnStr — draw the string at pnStrLo/Hi at (pnLine, pnCol)
\ ============================================================
\ Terminated by a zero byte, because beebasm's EQUS emits raw ASCII and
\ 0 is the one code the font has no glyph for.
\ IT READS THE STRING THROUGH A PATCHED ABSOLUTE, not a third zero-page
\ pointer. There is no third to borrow — swSrc and swDst are the two
\ that were free — and this file assembles into bank 4, which is RAM,
\ so the operand can be written the way the blitter writes its own. The
\ index lives in pnTmp because PnGlyph uses Y for its two copies.
.PnStr
  LDA pnStrLo : STA pn_s_get+1
  LDA pnStrHi : STA pn_s_get+2
  JSR PnAt
  LDA #0
  STA pnTmp
.pn_s_loop
  LDY pnTmp
.pn_s_get
  LDA &FFFF,Y
  BEQ pn_s_x
  JSR PnAscii
  JSR PnWide                    \ one cell, or two if it is a capital
  INC pnTmp
  BNE pn_s_loop
.pn_s_x
  RTS

\ ============================================================
\ PnWide — draw glyph A, and its right half too if it is a capital
\ ============================================================
\ DrawChar's test, ported. Only PnStr needs it: every other caller draws
\ digits or bar cells, which are never wide.
.PnWide
  CMP #PN_UPPER_A
  BCC pn_w_one
  CMP #PN_UPPER_Z+1
  BCS pn_w_one
  PHA
  JSR PnGlyph
  PLA
  CLC
  ADC #PN_WIDE_OFS
.pn_w_one
  JMP PnGlyph                   \ and its RTS

\ ============================================================
\ PnNum — A = value, print pnDigits decimal digits at (pnLine, pnCol)
\ ============================================================
\ Leading zeros are PRINTED, not blanked: every field on the panel is
\ fixed width and a blanked digit would have to be erased when the number
\ grows again. The C64 blanks them (DoScore's `LDA #$30` for "empty
\ leading chars") because its score is eight digits wide and ours is a
\ two-digit deck number.
\
\ Repeated subtraction, not a divide: the widest field is three digits
\ and a value of 255, so the inner loop runs at most 2 + 5 + 9 times.
.PnNum
  STA pnVal
  JSR PnAt
\ ---- and the tail, which the console shares ----------------
\ Entered with pnDst already pointed and pnVal set, so ConNum can use
\ its own ConAt and then fall in here.
.PnDigits
  LDX pnDigits
  DEX
  STX pnTmp                     \ index into the power table
.pn_n_digit
  LDX pnTmp
  LDA pnPow10,X
  STA pnStep
  LDA #0
  STA pnCount
.pn_n_sub
  LDA pnVal
  CMP pnStep
  BCC pn_n_have
  SEC
  SBC pnStep
  STA pnVal
  INC pnCount
  JMP pn_n_sub
.pn_n_have
  LDA pnCount
  CLC
  ADC #PN_DIGIT0
  JSR PnGlyph
  DEC pnTmp
  BPL pn_n_digit
  RTS

.pnPow10 EQUB 1, 10, 100

\ ============================================================
\ PnBar — A = cells lit, pnDigits = cells total
\ ============================================================
\ The two bar glyphs are the only artwork in the port that is not the
\ C64's. There is nothing to port: the original has no energy bar at all
\ and shows low energy by flashing the player's sprite instead. See
\ docs/layer-9-hud.md, decisions 3 and 4.
.PnBar
  STA pnCount
  JSR PnAt
  LDX pnDigits
.pn_b_loop
  LDA pnCount
  BEQ pn_b_off
  DEC pnCount
  LDA #PN_BAR_ON
  BNE pn_b_put                  \ always
.pn_b_off
  LDA #PN_BAR_OFF
.pn_b_put
  STX pnTmp
  JSR PnGlyph
  LDX pnTmp
  DEX
  BNE pn_b_loop
  RTS

\ ============================================================
\ PnClear — blank the whole panel
\ ============================================================
\ Not FillPanel's bordered box: that was the Layer 3 placeholder and it
\ drew a frame this layer has no use for. Kept as a separate routine
\ because the console will want it too.
.PnClear
  LDA #LO(PANEL_ADDR) : STA pnDst
  LDA #HI(PANEL_ADDR) : STA pnDst+1
  LDX #HI(PANEL_BYTES)
  LDY #0
  LDA #0
.pn_c_page
  STA (pnDst),Y
  INY
  BNE pn_c_page
  INC pnDst+1
  DEX
  BNE pn_c_page
.pn_c_tail
  STA (pnDst),Y
  INY
  CPY #LO(PANEL_BYTES)
  BNE pn_c_tail
  RTS

\ ============================================================
\ state
\ ============================================================
\ pnSrc and pnDst are not here: they are swSrc and swDst — see the top.
.pnStrLo  EQUB 0
.pnStrHi  EQUB 0
.pnLine   EQUB 0
.pnCol    EQUB 0
.pnDigits EQUB 0
.pnVal    EQUB 0
.pnStep   EQUB 0
.pnCount  EQUB 0
.pnTmp    EQUB 0
.pnTmpW   EQUW 0                \ ConClear's row base

\ ============================================================
\ THE HUD
\ ============================================================
\ Two lines of 40, and what goes in them is set out in
\ docs/layer-9-hud.md §5 along with the two fields the C64 does not have.
\
\   line 0   001 ########  064  Mobile          00000000
\   line 1   Deck 01   Alert ####   Droids 12
\
\ EVERY FIELD IS DRAWN ONLY WHEN IT CHANGES, which is the original's own
\ arrangement — DoScore repaints the score only when the BCD moves, and
\ DoMoveMode writes Mobile/Weapon/Transfer on the transition and not per
\ frame. A shadow copy per field is a byte each and turns a 40-glyph
\ repaint into six compares on a quiet pass.
\
\ The static words are drawn once by PanelInit at deck load. Only the
\ values below move.

PN_L0 = 0
PN_L1 = 1

\ COLUMNS COUNT CELLS, NOT LETTERS, because a capital is two cells:
\ "Deck" is 5 wide, "Alert" 6, "Droids" 7, "Transfer" 9.
PN_COL_NUM   = 0                \ 001, three digits
PN_COL_BAR   = 4                \ energy, PN_BAR_CELLS cells
PN_COL_MAX   = 13               \ the ceiling, three digits
PN_COL_MODE  = 17               \ Mobile / Weapon / Transfer, 9 cells
PN_COL_SCORE = 32               \ eight BCD digits

PN_COL_DECKW = 0                \ the word Deck
PN_COL_DECK  = 6                \ and its two digits
PN_COL_ALERTW = 11              \ the word Alert
PN_COL_ALERT = 18               \ and its four cells
PN_COL_LEFTW = 25               \ the word Droids
PN_COL_LEFT  = 33               \ and its two digits

\ ENERGY IS SHOWN ABSOLUTELY, ONE CELL PER 8, not as a fraction of
\ maxEnergy. It needs no divide, and 8 is the number the C64 itself
\ treats as the danger line — AnimateDroids ($3DE5) starts flashing the
\ player's sprite below it — so ONE CELL LIT IS EXACTLY THAT WARNING.
\ CB_ENERGY_FULL is $40, so a fresh droid fills all eight.
PN_BAR_CELLS  = 8
PN_ALERT_CELLS = 4

\ ============================================================
\ PanelInit — clear the panel and draw everything that never moves
\ ============================================================
\ Called from LoadDeck, after the deck is framed. Also invalidates every
\ shadow so the first PanelUpdate repaints the lot.
.PanelInit
  JSR PnClear

  LDA #PN_L1 : STA pnLine
  LDA #PN_COL_DECKW : STA pnCol
  LDA #LO(pnTxtDeck) : STA pnStrLo
  LDA #HI(pnTxtDeck) : STA pnStrHi
  JSR PnStr

  LDA #PN_L1 : STA pnLine
  LDA #PN_COL_ALERTW : STA pnCol
  LDA #LO(pnTxtAlert) : STA pnStrLo
  LDA #HI(pnTxtAlert) : STA pnStrHi
  JSR PnStr

  LDA #PN_L1 : STA pnLine
  LDA #PN_COL_LEFTW : STA pnCol
  LDA #LO(pnTxtDroids) : STA pnStrLo
  LDA #HI(pnTxtDroids) : STA pnStrHi
  JSR PnStr

  LDA #PN_L1     : STA pnLine
  LDA #PN_COL_DECK : STA pnCol
  LDA #2         : STA pnDigits
  LDA deck                      \ AS-IS, not +1: BUGS.md, the docs and the
  JSR PnNum                     \ debug deck hop all name decks by this number

  LDA #&FF                      \ every shadow invalid: repaint it all
  STA pnShType
  STA pnShEnergy
  STA pnShMax
  STA pnShMode
  STA pnShAlert
  STA pnShLeft
  STA pnShScore
  RTS

\ ============================================================
\ PanelUpdate — the fields that move. Once a pass, from the main loop
\ ============================================================
.PanelUpdate
\ ---- the droid you are riding ------------------------------
  LDA pmType
  CMP pnShType
  BEQ pu_energy
  STA pnShType
  TAY
  LDA #PN_L0       : STA pnLine
  LDA #PN_COL_NUM  : STA pnCol
  JSR PnAt
  LDA pnTabCent,Y               \ hundreds
  CLC : ADC #PN_DIGIT0
  JSR PnGlyph
  LDY pnShType
  LDA pnTabNum,Y                \ tens and units, packed BCD
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #PN_DIGIT0
  JSR PnGlyph
  LDY pnShType
  LDA pnTabNum,Y
  AND #&0F
  CLC : ADC #PN_DIGIT0
  JSR PnGlyph

\ ---- energy, as PN_BAR_CELLS cells of 8 --------------------
.pu_energy
  LDA pmEnergy
  CLC : ADC #7                  \ any energy at all lights a cell
  LSR A : LSR A : LSR A
  CMP #PN_BAR_CELLS+1
  BCC pu_ehave
  LDA #PN_BAR_CELLS
.pu_ehave
  CMP pnShEnergy
  BEQ pu_max
  STA pnShEnergy
  LDA #PN_L0      : STA pnLine
  LDA #PN_COL_BAR : STA pnCol
  LDA #PN_BAR_CELLS : STA pnDigits
  LDA pnShEnergy
  JSR PnBar

\ ---- the ceiling, which only ever falls --------------------
.pu_max
  LDA maxEnergy
  CMP pnShMax
  BEQ pu_mode
  STA pnShMax
  LDA #PN_L0      : STA pnLine
  LDA #PN_COL_MAX : STA pnCol
  LDA #3          : STA pnDigits
  LDA pnShMax
  JSR PnNum

\ ---- Mobile / Weapon / Transfer ----------------------------
\ moveMode's four states collapse to the original's three words: $80
\ Mobile, 1 Weapon, 0 Transfer, and 2 is the settling state on its way
\ to Transfer, which the C64 does not name either.
.pu_mode
\ TWO WAYS TO LOSE THE FLAGS HERE, and this arm found both.
\
\ **CMP leaves N from the SUBTRACTION, not from the value.** The change
\ test has to happen first, so by the time the mode is dispatched on, N
\ describes `moveMode - pnShMode`. Going from $80 to 1 that is $81,
\ negative, so `BMI` took the Mobile arm on the very transition that was
\ meant to leave it. Hence the reload below.
\
\ **LDY sets N too.** Loading the string pointer before the branch means
\ `BMI` tests the string's high byte instead. That is why the dispatch
\ picks the pointer inside each arm rather than ahead of them.
\
\ Both bugs read as "the mode field never changes", and the shadow byte
\ says otherwise — pnShMode tracks moveMode correctly throughout.
  LDA moveMode
  CMP pnShMode
  BEQ pu_alert
  STA pnShMode
  LDA pnShMode                  \ reload: CMP above clobbered N
  BMI pu_mmob                   \ $80 Mobile
  CMP #MM_WEAPON
  BEQ pu_mwep
  LDX #LO(pnTxtXfer)   : LDY #HI(pnTxtXfer)   : JMP pu_mset
.pu_mwep
  LDX #LO(pnTxtWeapon) : LDY #HI(pnTxtWeapon) : JMP pu_mset
.pu_mmob
  LDX #LO(pnTxtMobile) : LDY #HI(pnTxtMobile)
.pu_mset
  STX pnStrLo : STY pnStrHi
  LDA #PN_L0       : STA pnLine
  LDA #PN_COL_MODE : STA pnCol
  JSR PnStr

\ ---- the alert level, its top two bits ---------------------
.pu_alert
  LDA alertLvl
  LSR A : LSR A : LSR A
  LSR A : LSR A : LSR A
  CMP pnShAlert
  BEQ pu_left
  STA pnShAlert
  LDA #PN_L1        : STA pnLine
  LDA #PN_COL_ALERT : STA pnCol
  LDA #PN_ALERT_CELLS : STA pnDigits
  LDA pnShAlert
  JSR PnBar

\ ---- droids left on the deck -------------------------------
\ drCount includes entry 0, the player, and any bullet or explosion
\ still in the table. The C64's own deck-cleared test is `CMP #2` on the
\ same count, so this is that number less the player and nothing more.
.pu_left
  LDA pmCount
  BEQ pu_lhave                  \ cannot happen; do not underflow if it does
  SEC : SBC #1
.pu_lhave
  CMP pnShLeft
  BEQ pu_score
  STA pnShLeft
  LDA #PN_L1       : STA pnLine
  LDA #PN_COL_LEFT : STA pnCol
  LDA #2           : STA pnDigits
  LDA pnShLeft
  JSR PnNum

\ ---- the score, four bytes of BCD --------------------------
\ Only the low byte is watched: it moves on every award, so a change
\ anywhere above it has always moved it too.
.pu_score
  LDA score+3
  CMP pnShScore
  BEQ pu_x
  STA pnShScore
  LDA #PN_L0        : STA pnLine
  LDA #PN_COL_SCORE : STA pnCol
  JSR PnAt
  LDX #0
.pu_sloop
  LDA score,X
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #PN_DIGIT0
  STX pnTmp
  JSR PnGlyph
  LDX pnTmp
  LDA score,X
  AND #&0F
  CLC : ADC #PN_DIGIT0
  STX pnTmp
  JSR PnGlyph
  LDX pnTmp
  INX
  CPX #4
  BNE pu_sloop
.pu_x
  RTS

\ ---- the words ---------------------------------------------
\ Mixed case, as the original's are: Mobile_txt at $698A reads
\ $46 $18 $0B $12 $15 $0E = M o b i l e. Each mode word is padded to
\ eight so a shorter one wipes a longer one behind it.
.pnTxtMobile EQUS "Mobile  " : EQUB 0   \ 7 cells + 2 pad = 9
.pnTxtWeapon EQUS "Weapon  " : EQUB 0   \ 7 cells + 2 pad = 9
.pnTxtXfer   EQUS "Transfer" : EQUB 0   \ 9 cells exactly
.pnTxtDeck   EQUS "Deck"     : EQUB 0
.pnTxtAlert  EQUS "Alert"    : EQUB 0
.pnTxtDroids EQUS "Droids"   : EQUB 0

.pnShType   EQUB &FF
.pnShEnergy EQUB &FF
.pnShMax    EQUB &FF
.pnShMode   EQUB &FF
.pnShAlert  EQUB &FF
.pnShLeft   EQUB &FF
.pnShScore  EQUB &FF
