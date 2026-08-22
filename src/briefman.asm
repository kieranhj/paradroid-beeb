\ ============================================================
\ briefman.asm — the briefing's bank-5 half, beside its text
\ ============================================================
\ LAYER 11f. Assembled into the PARMAN block, after the record lists.
\ These routines run WITH BANK 5 PAGED — which is the briefing's
\ resting state — and exist because the PARBRF overlay at &0400 has a
\ HARD CEILING AT &0800: the page above it, &0800-&08FF, is the MOS's
\ sound workspace, channel buffers and printer buffer, and the MOS IRQ
\ writes into it while it still owns the machine (the title's loads
\ run under it). A PARBRF that spilled past &0800 was measured to die
\ exactly there: the code verified byte-perfect at load, and by the
\ first paint the MOS had chewed it and the CPU wandered into the
\ paged bank. So anything of the briefing's that does not have to be
\ main RAM lives here, in a bank with eleven K spare.
\
\ WHAT MAY LIVE HERE: code that touches only main RAM and THIS bank.
\ Bank code may read and write main RAM freely; what it must never do
\ is call into another bank, because paging itself out pulls the rug.
\ Everything below reads PARBRF's own state bytes (&04xx-&07xx labels,
\ resolved across the blocks) and the strip, and writes this bank's
\ records — nothing pages.
bmp = chp                       \ the record pointer, briefing.asm's brp

\ ---- the portrait's geometry, shared with briefing.asm ------
\ ON THE LEFT (KC, 2026-08-22), and it is the C64's own position:
\ BuildIntroSprites puts the briefing droid at sprite X = 40, which is
\ 16 px in from the visible edge — unit 4. Text columns 2-7; the score
\ table's text starts at column 10, so nothing overlaps.
BR_PO_UNIT = 4                  \ text columns 2-7: 48 px, the width
BR_PO_OFS  = BR_PO_UNIT * UNIT_BYTES
BR_PO_ROW0 = DB_IMG_ROW         \ PoDraw's own rows, unmoved
BR_PO_ROWS = 11                 \ 84 scanlines and the row they end in
BR_PO_SPAN = 12 * UNIT_BYTES    \ one row's slice of the rectangle

\ ============================================================
\ BmPatch — the live table into page 5's two lines
\ ============================================================
\ UpdateTextScore ($E5AC) moved to the read side [11f DECISION 7]: the
\ C64 writes the score into the packed text and the text persists;
\ ours is reloaded from disc each time, so the patch happens on the
\ fresh copy, before anything draws it. The layout is the original's:
\ eight BCD digits at glyph offsets 0-7 with leading zeros as spaces
\ (the last digit never blanked), initials at 11-13. BrTimeout has
\ already ferried bank 7's fourteen bytes into brSc and paged this
\ bank in; the records patched are THIS bank's, two pages back.
.BmPatch
  LDA #LO(br_hiscore+1)         \ +1: past the record's column byte
  STA bmp
  LDA #HI(br_hiscore+1)
  STA bmp+1
  LDX #0                        \ brSc: the high score's 4+3
  JSR BmPatchLine
  LDA #LO(br_loscore+1)
  STA bmp
  LDA #HI(br_loscore+1)
  STA bmp+1
  LDX #7                        \ and the low score's, by falling in
.BmPatchLine
  LDA #0
  STA brT2                      \ still in the leading zeros
  LDY #0
.bmp_byte
  LDA brSc,X                    \ one BCD byte, two digits
  PHA
  LSR A : LSR A : LSR A : LSR A
  JSR bm_dig
  PLA
  AND #&0F
  JSR bm_dig
  INX
  CPY #8
  BCC bmp_byte
  INY                           \ glyphs 8-10 are ' - ', left alone
  INY
  INY
.bmp_ini
  LDA brSc,X                    \ a letter index 0-26, 26 the space
  CMP #26
  BCC bmp_letter
  LDA #PN_SPACE                 \ which is ZERO, so no BNE-always here —
  JMP bmp_iput                  \ that mistake shipped once
.bmp_letter
  CLC
  ADC #PN_UPPER_A
.bmp_iput
  STA (bmp),Y
  INX
  INY
  CPY #14
  BCC bmp_ini
  RTS

.bm_dig                         \ A = the digit, Y = the glyph position
  BNE bmd_show
  LDA brT2                      \ a zero: blanked while leading, except
  BNE bmd_zero                  \ the last digit, which always shows
  CPY #7
  BEQ bmd_zero
  LDA #PN_SPACE                 \ ZERO — a BNE-always here never branches
  JMP bmd_put
.bmd_zero
  LDA #PN_DIGIT0
  BNE bmd_put                   \ always
.bmd_show
  STA brT
  LDA #1
  STA brT2
  LDA brT
  CLC
  ADC #PN_DIGIT0
.bmd_put
  STA (bmp),Y
  INY
  RTS

\ ============================================================
\ BmSnap — the freshly drawn portrait into SPR_SAVE
\ ============================================================
\ BrPortrait has had PoDraw render into the parked strip at unit 68,
\ rows BR_PO_ROW0..+10, and paged this bank back; the rectangle is
\ carried to SPR_SAVE — dead outside a game, LoadDeck rebuilds it —
\ so BmBand can put its rows back as the page paints and scrolls.
.BmSnap
  LDA #0
  STA brT2
.bms_row
  LDA brT2
  CLC
  ADC #BR_PO_ROW0
  TAX
  CLC
  LDA brRowBLo,X : ADC #LO(BR_PO_OFS) : STA swSrc
  LDA brRowBHi,X : ADC #HI(BR_PO_OFS) : STA swSrc+1
  LDX brT2
  LDA brPoLo,X : STA swDst
  LDA brPoHi,X : STA swDst+1
  LDY #BR_PO_SPAN-1
.bms_b
  LDA (swSrc),Y
  STA (swDst),Y
  DEY
  BPL bms_b
  INC brT2
  LDA brT2
  CMP #BR_PO_ROWS
  BCC bms_row
  RTS

\ ============================================================
\ BmBand — the portrait's slice of the row just painted
\ ============================================================
\ BrPaintRow tail-calls this after every row. On page 5, a row inside
\ the rectangle gets its 96-byte band copied back over columns 34-39 —
\ which is how the picture scrolls with the page. A plain copy, no
\ transparency: those columns are empty on every page-5 row (checked
\ against briefing.txt) and the picture's background is the page's
\ own black.
.BmBand
  LDA brPage
  CMP #BR_PAGES-1
  BNE bmb_x
  LDA brRow
  SEC
  SBC #BR_PO_ROW0
  BCC bmb_x
  CMP #BR_PO_ROWS
  BCS bmb_x
  TAX
  LDA brPoLo,X : STA swSrc
  LDA brPoHi,X : STA swSrc+1
  LDX brStrip
  CLC
  LDA brRowBLo,X : ADC #LO(BR_PO_OFS) : STA swDst
  LDA brRowBHi,X : ADC #HI(BR_PO_OFS) : STA swDst+1
  LDY #BR_PO_SPAN-1
.bmb_b
  LDA (swSrc),Y
  STA (swDst),Y
  DEY
  BPL bmb_b
.bmb_x
  RTS

\ ---- the snapshot's row bases -------------------------------
.brPoLo
  FOR n, 0, BR_PO_ROWS-1
    EQUB LO(SPR_SAVE + n * BR_PO_SPAN)
  NEXT
.brPoHi
  FOR n, 0, BR_PO_ROWS-1
    EQUB HI(SPR_SAVE + n * BR_PO_SPAN)
  NEXT
