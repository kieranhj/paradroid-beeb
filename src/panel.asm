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
\ THE PANEL IS THE C64's STATUS BOX AND NOTHING ELSE. PANEL_ROWS = 4,
\ 32 scanlines, which is exactly the height of the ink in the original's
\ status area — see the note by PANEL_ADDR in main.asm for the derivation
\ from $6900/$6917/$6937/$693C. The four rows are:
\
\   row 0     the top border      panelframe cells 0-5
\   rows 1-2  ONE line of 40      the box bars, the mode word, the logo,
\                                 the score — nothing else
\   row 3     the bottom border   panelframe cells 6-11
\
\ Everything the port used to show here that the C64 does not — the droid
\ number, the energy bar, the ceiling, the deck, the alert level and the
\ droids-left count — is gone. See docs/layer-9-hud.md.
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
PN_LOGO0    = 90                \ the seven logo cells, 90-96
PN_BOXBAR   = 97                \ $7C, the box's vertical bar

\ ---- INK, as a mask ANDed into every glyph byte ------------
\ A MODE 1 byte carries four pixels: bits 7-4 are their HIGH colour bits
\ and bits 3-0 their LOW ones, so a logical colour is high*2 + low. The
\ font is exported with both planes set — logical 3 — and dropping one
\ plane recolours a glyph for the cost of an AND per byte:
\
\   &FF  logical 3    the frame and the mode word   (black)
\   &F0  logical 2    the logo and the score        (red)
\   &0F  logical 1
\
\ which is how the original's status area is coloured: it is grey on
\ white with the logo and the score in red. Grey is not a BBC colour, so
\ the frame and the text take black. See docs/layer-9-hud.md.
PN_INK_TEXT = &FF
PN_INK_RED  = &F0

\ ---- CAPITALS ARE TWO CELLS WIDE ---------------------------
\ DrawChar ($0C5F) writes the code, then tests it:
\   AND #$7F : CMP #$3A : BCC _1 : CMP #$5A : BCS _1  \ "see if it was wide"
\   LDY #1 : ADC #$20 : STA (cpyDest),Y ... : INC prntX
\ so a capital's right half is at C64 code + $20 and it occupies two
\ character cells. The export splits each into two glyphs and PnStr
\ draws the second whenever the first is a capital — the same test, in
\ the same place. Lowercase and digits stay one cell.

PN_COLS     = 40                \ characters across the panel
PN_TEXT_ROW = 1                 \ the text line sits between the borders
ASSERT PN_TEXT_ROW + 2 == PANEL_ROWS - 1

\ The text line's base address, used by PnAt and by nothing else. The
\ panel has ONE line now, so pnLine is not read here — it still exists
\ because console.asm's ConAt has seven lines and uses it.
PN_TEXT_ADDR = PANEL_ADDR + PN_TEXT_ROW * ROW_BYTES

\ ============================================================
\ PnAt — point pnDst at text cell pnCol on the panel's one line
\ ============================================================
\ The glyph's top cell; its bottom cell is ROW_BYTES further on, which
\ the draw adds as it goes rather than keeping a second pointer.
\
\ IT ALSO RESETS THE INK. Every caller that wants red sets pnMask after
\ this returns, so there is no restore to forget and no path that leaves
\ the panel — or the console, whose ConAt does the same — drawing in a
\ colour the previous field chose.
.PnAt
  LDA #PN_INK_TEXT
  STA pnMask

  LDA pnCol                     \ col * 16
  ASL A : ASL A : ASL A : ASL A
  STA pnDst
  LDA pnCol
  LSR A : LSR A : LSR A : LSR A \ the carry out of col*16
  STA pnDst+1

  CLC
  LDA pnDst   : ADC #LO(PN_TEXT_ADDR) : STA pnDst
  LDA pnDst+1 : ADC #HI(PN_TEXT_ADDR) : STA pnDst+1
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
  AND pnMask                    \ the ink — see PN_INK_TEXT above
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
  AND pnMask
  STA (pnDst),Y
  DEY
  BPL pn_bot

  SEC                           \ back up, then on to the next column
  LDA pnDst   : SBC #LO(ROW_BYTES - 16) : STA pnDst
  LDA pnDst+1 : SBC #HI(ROW_BYTES - 16) : STA pnDst+1
  RTS

\ ============================================================
\ PnCell — draw border cell A at pnDst, then advance one column
\ ============================================================
\ HALF a glyph: 16 bytes, one character row, because the border rows
\ contribute only their inner 8 scanlines to the box. Twelve cells at 16
\ bytes is 192, so the index times 16 stays in one byte and the pointer
\ arithmetic is a shift and one add rather than PnGlyph's shift-and-roll.
.PnCell
  ASL A : ASL A : ASL A : ASL A \ * 16, and 11 * 16 = 176: no carry out
  CLC
  ADC #LO(PN_FRAME_ADDR) : STA pnSrc
  LDA #0
  ADC #HI(PN_FRAME_ADDR) : STA pnSrc+1

  LDY #15
.pn_c_loop
  LDA (pnSrc),Y
  AND pnMask
  STA (pnDst),Y
  DEY
  BPL pn_c_loop

  CLC
  LDA pnDst : ADC #16 : STA pnDst
  BCC pn_c_x
  INC pnDst+1
.pn_c_x
  RTS

\ ============================================================
\ PnFrame — the box's top and bottom borders, rows 0 and 3
\ ============================================================
\ $6900 draws the top as $55 + 18 x $56 + $57 and $693C the bottom as
\ $58 + 18 x $59 + $7A $7B. $55-$59 are wide, so each contributes two
\ cells, and $7A and $7B are one each — which makes BOTH rows the same
\ shape: two cells, eighteen pairs, two cells. One loop draws either,
\ with X the first of its six panelframe entries.
.PnFrame
  LDA #PN_INK_TEXT : STA pnMask

  LDA #LO(PANEL_ADDR) : STA pnDst
  LDA #HI(PANEL_ADDR) : STA pnDst+1
  LDX #0
  JSR pn_f_row

  LDA #LO(PANEL_ADDR + (PANEL_ROWS-1) * ROW_BYTES) : STA pnDst
  LDA #HI(PANEL_ADDR + (PANEL_ROWS-1) * ROW_BYTES) : STA pnDst+1
  LDX #6
.pn_f_row
  STX pnTmp
  TXA
  JSR PnCell
  LDA pnTmp : CLC : ADC #1 : JSR PnCell

  LDX #18
.pn_f_mid
  STX pnCount
  LDA pnTmp : CLC : ADC #2 : JSR PnCell
  LDA pnTmp : CLC : ADC #3 : JSR PnCell
  LDX pnCount
  DEX
  BNE pn_f_mid

  LDA pnTmp : CLC : ADC #4 : JSR PnCell
  LDA pnTmp : CLC : ADC #5 : JMP PnCell

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
\ PnDigits — print pnDigits decimal digits of pnVal at pnDst
\ ============================================================
\ THE CONSOLE'S, not the panel's: ConNum points pnDst with its own ConAt
\ and then jumps in here. The panel has no decimal field left — its one
\ number is the score, which is BCD and blanks its leading zeros, so it
\ has its own loop in PanelUpdate exactly as DoScore does.
\
\ Leading zeros are PRINTED here, because every console field is fixed
\ width and a blanked digit would have to be erased when the number grows
\ again.
\
\ Repeated subtraction, not a divide: the widest field is three digits
\ and a value of 255, so the inner loop runs at most 2 + 5 + 9 times.
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
.pnLine   EQUB 0                \ console.asm's ConAt only; the panel has one line
.pnCol    EQUB 0
.pnMask   EQUB PN_INK_TEXT      \ the ink, ANDed into every glyph byte
.pnDigits EQUB 0
.pnVal    EQUB 0
.pnStep   EQUB 0
.pnCount  EQUB 0
.pnTmp    EQUB 0
.pnTmpW   EQUW 0                \ ConClear's row base

\ ============================================================
\ THE HUD
\ ============================================================
\ ONE line of 40, and it is the C64's, cell for cell. $6917, $6937,
\ DoMoveMode and DoScore between them put:
\
\   |  Mobile        Paradroid.          335 |
\   0  2             15                30  37 39
\
\ | the box bars | cols 0 and 39 | $6917 and $6937, $7C both |
\ | the mode word | col 2, 11 cells | DoMoveMode's own prntX |
\ | the logo | cols 15-23, 9 cells | $6917, in red |
\ | the score | cols 30-37, 8 BCD digits | DoScore's own prntX, in red |
\
\ EVERY FIELD IS DRAWN ONLY WHEN IT CHANGES, which is the original's own
\ arrangement — DoScore repaints the score only when the BCD moves, and
\ DoMoveMode writes Mobile/Weapon/Transfer on the transition and not per
\ frame. Two shadow bytes turn a repaint into two compares on a quiet pass.
\
\ The frame, the bars and the logo never move and are drawn once by
\ PanelInit at deck load.

\ COLUMNS COUNT CELLS, NOT LETTERS, because a capital is two cells. The
\ numbers are the C64's: prntX = 2 for the mode word, 30 for the score,
\ and the logo where $6917's fourteen spaces leave it.
PN_COL_BARL  = 0
PN_COL_MODE  = 2
PN_COL_LOGO  = 15
PN_COL_SCORE = 30
PN_COL_BARR  = 39

PN_LOGO_CELLS = 9               \ nine cells from seven glyphs
PN_SCORE_BYTES = 4              \ eight BCD digits

\ ============================================================
\ PanelInit — the box, the bars and the logo, all of them static
\ ============================================================
\ Called from LoadDeck, after the deck is framed. Also invalidates both
\ shadows so the first PanelUpdate repaints the two live fields.
.PanelInit
  JSR PnClear
  JSR PnFrame

\ ---- the box's two vertical bars, $6917 and $6937 ----------
  LDA #PN_COL_BARL : STA pnCol
  JSR PnAt
  LDA #PN_BOXBAR
  JSR PnGlyph

  LDA #PN_COL_BARR : STA pnCol
  JSR PnAt
  LDA #PN_BOXBAR
  JSR PnGlyph

\ ---- the logo, nine cells in red ---------------------------
\ $6917 draws $31 $32 $33 $32 $34 $33 $35 $36 $37 — seven glyphs, two of
\ them twice — so the order is a table rather than a run.
  LDA #PN_COL_LOGO : STA pnCol
  JSR PnAt
  LDA #PN_INK_RED : STA pnMask  \ after PnAt, which resets the ink
  LDX #0
.pi_logo
  STX pnTmp
  LDA pnLogoSeq,X
  CLC : ADC #PN_LOGO0
  JSR PnGlyph
  LDX pnTmp
  INX
  CPX #PN_LOGO_CELLS
  BNE pi_logo

  LDA #&FF                      \ both shadows invalid: repaint them
  STA pnShMode
  STA pnShScore
  RTS

.pnLogoSeq EQUB 0, 1, 2, 1, 3, 2, 4, 5, 6

\ ============================================================
\ PanelUpdate — the two fields that move. Once a pass, from the main loop
\ ============================================================
.PanelUpdate
\ ---- Mobile / Weapon / Transfer / Console ------------------
\ moveMode's four states collapse to the original's three words: $80
\ Mobile, 1 Weapon, 0 Transfer, and 2 is the settling state on its way to
\ Transfer, which the C64 does not name either. CONSOLE IS THE FOURTH and
\ does not come from moveMode at all — the C64 draws Console_txt ($69E4)
\ from Console itself, at $2C5B, into the same field.
\
\ The dispatch reduces to an INDEX first and compares second, which is
\ deliberate: the arm this replaced tested moveMode after a CMP and after
\ an LDY, and both clobber N. Both bugs read as "the mode never changes".
  LDA conActive
  BEQ pu_m_play
  LDA #3                        \ Console
  BNE pu_m_have                 \ always
.pu_m_play
  LDA moveMode
  BMI pu_m_mob                  \ $80 Mobile
  CMP #MM_WEAPON
  BEQ pu_m_wep
  LDA #2                        \ Transfer: moveMode 0, and 2 settling
  BNE pu_m_have                 \ always
.pu_m_wep
  LDA #1
  BNE pu_m_have                 \ always
.pu_m_mob
  LDA #0
.pu_m_have
  CMP pnShMode
  BEQ pu_score
  STA pnShMode
  ASL A
  TAX
  LDA pnTxtTab+0,X : STA pnStrLo
  LDA pnTxtTab+1,X : STA pnStrHi
  LDA #PN_COL_MODE : STA pnCol
  JSR PnStr

\ ---- the score, four bytes of BCD, in red ------------------
\ Only the low byte is watched: it moves on every award, so a change
\ anywhere above it has always moved it too.
\
\ LEADING ZEROS ARE BLANKED, which is DoScore's own behaviour and the
\ reason this does not go through PnDigits. $0AE6 starts a "blank char"
\ at $30 (space) and zeroes it at the first non-zero digit, so every
\ later zero prints as a digit; the LAST digit prints even when zero,
\ which is what `CPX #3 : BEQ _11` at $0B01 is for. Our glyph indices
\ make that arithmetic rather than a branch: PN_SPACE is 0 and PN_DIGIT0
\ is 1, so the blank char IS the base the nibble is added to.
.pu_score
  LDA score+3
  CMP pnShScore
  BEQ pu_x
  STA pnShScore

  LDA #PN_COL_SCORE : STA pnCol
  JSR PnAt
  LDA #PN_INK_RED : STA pnMask
  LDA #PN_SPACE
  STA pnStep                    \ DoScore's tmp1: the blank char
  LDX #0
.pu_s_byte
  LDA score,X
  LSR A : LSR A : LSR A : LSR A
  JSR pu_s_digit
  LDX pnTmp
  LDA score,X
  AND #&0F
  CPX #PN_SCORE_BYTES-1         \ the last digit is never blanked
  BNE pu_s_low
  LDY #PN_DIGIT0 : STY pnStep
.pu_s_low
  JSR pu_s_digit
  LDX pnTmp
  INX
  CPX #PN_SCORE_BYTES
  BNE pu_s_byte
.pu_x
  RTS

\ A = the nibble. Prints pnStep + A, and any non-zero nibble turns the
\ blank char into PN_DIGIT0 so nothing after it is blanked.
.pu_s_digit
  STX pnTmp
  CMP #0
  BEQ pu_sd_put
  LDY #PN_DIGIT0 : STY pnStep
.pu_sd_put
  CLC
  ADC pnStep
  JMP PnGlyph                   \ and its RTS

\ ---- the words ---------------------------------------------
\ Mixed case, as the original's are, and PADDED TO ELEVEN CELLS because
\ that is the width the C64 pads them to: Mobile_txt at $698A is
\ $46 $18 $0B $12 $15 $0E then four $30s, and Transfer_txt at $697D is
\ eight letters then two — eleven cells either way, so a shorter word
\ wipes a longer one behind it. Capitals are two cells each.
.pnTxtTab
  EQUW pnTxtMobile              \ 0
  EQUW pnTxtWeapon              \ 1
  EQUW pnTxtXfer                \ 2
  EQUW pnTxtConsole             \ 3

.pnTxtMobile  EQUS "Mobile    " : EQUB 0    \ 7 cells + 4 pad = 11
.pnTxtWeapon  EQUS "Weapon    " : EQUB 0    \ 7 cells + 4 pad = 11
.pnTxtXfer    EQUS "Transfer  " : EQUB 0    \ 9 cells + 2 pad = 11
.pnTxtConsole EQUS "Console   " : EQUB 0    \ 8 cells + 3 pad = 11

.pnShMode   EQUB &FF
.pnShScore  EQUB &FF
