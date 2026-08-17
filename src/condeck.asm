\ ============================================================
\ condeck.asm — the console's deck plan page, in bank 7
\ ============================================================
\ con_DeckInfo ($3001): the current deck's map, one CHARACTER per tile,
\ drawn once and static, with the player's cell marked in white. It is
\ DrawPacked ($30A0) again — the same decoder the ship page runs over
\ svData — but over the LEVEL RLE, with no ORA offset where the ship's
\ codes gain $80, and the deck's own palette kept where the ship page
\ swaps one in: con_DeckInfo takes its background from the deck record,
\ which is what our logical 0 already is.
\
\ THE PAGE IS HIRES, NOT MULTICOLOUR — and getting that wrong was the
\ CharColor trap's second bite (the first is layer-8b decision 5). The
\ console screen is conRedraw's, which calls GotoHires ($31A4): $C0
\ into _d016Mode, so EVERY cell renders hires with colour RAM's full
\ 4-bit value as its foreground — the multicolour flag is just a colour
\ bit here. con_ShipInfo puts $D0 BACK for the side view, which is why
\ the ship page's multicolour handling is right and this page must not
\ share it. The first build drew from the play-area charset, where
\ BuildCharset honours the flag, and the flagged characters came out
\ with multicolour fringes — the red left edges KC caught.
\
\ WHAT THE C64 DOES, and where each piece lands here:
\   src = lvPtr[deckNum]        ConDeckEnter4 (droid.asm, bank 4) — the
\                               RLE lives in bank 4, so a copy of the
\                               deck's stream is staged at SPR_SAVE,
\                               scratch while the console is up
\   DrawPacked, ORA #0          cd7_next below: the 64-wide grid clipped
\                               to columns 3-41, rows 0-15
\   hires render, CharColor     ConDeckCell: each code's 8 source rows
\                               (planChars, this bank) expand to a MODE 1
\                               cell with foreground planInk[deck*32 +
\                               code] over background 0. The ink table is
\                               built at EXPORT time from the C64's whole
\                               chain — CharColor slot -> deck record ->
\                               the deck's logical — with slots 12-15
\                               reading 0, which is what the C64's own
\                               zeroed block at $0221 gives it
\   the $29 -> blank test       NOT PORTED, because it cannot fire: no
\                               level stream contains $29 (all 16 decks
\                               checked) — it is svData's blank
\   char $A0, colour $F1        cd7_mark: a solid cell of logical 3 —
\                               white on every deck — at the tile under
\                               plyMapPos, the same reference cell
\                               CheckWalls uses (plyX+11, posY+63)
\
\ TWO DEVIATIONS, both KC's ruling 2026-08-17 and both baked into the
\ export's planInk: the console characters $10-$13 draw in C64 red, not
\ their slot's black-or-brown; and a glyph whose nearest logical would
\ be 0 — the background — takes the nearest of 1-3 instead, because the
\ C64 shows those low-contrast and four colours would show nothing.
\
\ COLUMN 39 IS OUTSIDE THE MAP: DrawPacked writes columns 0-38 and the
\ C64's rightmost column keeps the cleared screen. Ours is plotted as
\ code 0 — the blank character — once per row, saving and restoring the
\ run in flight, because a run crosses row boundaries.
\
\ THE MARKER IS CLIPPED where the C64's is not: decks 2, 14 and 15 have
\ map beyond column 41, and a player standing there would send the C64's
\ unclipped store past the row's end into the next row's colour RAM. We
\ skip the marker instead of reproducing the overwrite.

.ConDeck7
  LDA #LO(SPR_SAVE) : STA xsrc  \ the staged stream, not lvPtr
  LDA #HI(SPR_SAVE) : STA xsrc+1
  LDA deck                      \ the deck's ink row: planInk + deck*32
  LSR A : LSR A : LSR A         \ high bit of the *32
  CLC : ADC #HI(planInk)
  STA xdest2+1
  LDA deck
  ASL A : ASL A : ASL A : ASL A : ASL A
  STA xdest2                    \ planInk is page aligned
  LDA #0
  STA lvPos                     \ ptr_14: the grid column, 0-63
  STA lvRow                     \ ptr_14+1
.cd7_next
  LDY #0
  LDA (xsrc),Y
  BPL cd7_single
  AND #&7F
  STA lvChar
  INY
  LDA (xsrc),Y
  STA lvLen
  CLC
  LDA xsrc   : ADC #2 : STA xsrc
  LDA xsrc+1 : ADC #0 : STA xsrc+1
  JMP cd7_run
.cd7_single
  STA lvChar
  LDA #1
  STA lvLen
  CLC
  LDA xsrc   : ADC #1 : STA xsrc
  LDA xsrc+1 : ADC #0 : STA xsrc+1
.cd7_run
  LDA lvPos
  CMP #42
  BCS cd7_skip
  CMP #3
  BCC cd7_skip
  SBC #3                        \ carry set: the screen column
  JSR ConDeckCell
.cd7_skip
  INC lvPos
  LDA lvPos
  CMP #64
  BCC cd7_more
  LDA lvChar                    \ the row is done: its 40th column is
  PHA                           \ code 0, around the run in flight
  LDA #0
  STA lvChar
  LDA #39
  JSR ConDeckCell
  PLA
  STA lvChar
  LDA #0
  STA lvPos
  INC lvRow
  LDA lvRow
  CMP #16
  BCS cd7_mark
.cd7_more
  DEC lvLen
  BNE cd7_run
  BEQ cd7_next

\ ---- the player's cell, $3032-$305D -------------------------
\ Tile column = plyMapPos/4 and the C64's plyMapPos is our reference
\ cell (player.asm): char column (plyX+PLY_REFX)>>3, char row
\ (posY+PLY_REFY)>>3 — so five shifts of each. Then the map's -3, the
\ clip, and sixteen bytes of solid logical 3 where the C64 stores an
\ inverse space in colour 1.
.cd7_mark
  CLC
  LDA plyX   : ADC #LO(PLY_REFX) : STA xgd
  LDA plyX+1 : ADC #HI(PLY_REFX) : STA xgd+1
  FOR n, 1, 5
    LSR xgd+1 : ROR xgd
  NEXT
  LDA xgd
  SEC
  SBC #3
  BMI cd7_x                     \ off the plan's left edge
  CMP #39
  BCS cd7_x                     \ or its right — the C64 does not clip
  STA xfColV
  CLC
  LDA posY   : ADC #PLY_REFY : STA xgs
  LDA posY+1 : ADC #0        : STA xgs+1
  FOR n, 1, 5
    LSR xgs+1 : ROR xgs
  NEXT
  LDX xgs                       \ the tile row, 0-15 by construction
  LDA xfColV
  ASL A : ASL A : ASL A : ASL A \ col*16 into the row's base
  STA xgd
  LDA xfColV
  LSR A : LSR A : LSR A : LSR A
  STA xgd+1
  CLC
  LDA xgd   : ADC xfRowAdrLo,X : STA xgd
  LDA xgd+1 : ADC xfRowAdrHi,X : STA xgd+1
  LDA #&FF                      \ solid logical 3: white on every deck
  LDY #15
.cd7_mfill
  STA (xgd),Y
  DEY
  BPL cd7_mfill
.cd7_x
  RTS

\ ---- one cell: lvChar at (lvRow, A) -------------------------
\ The hires conversion, done as the cell is plotted: each of the 8
\ source rows is two nibbles, and a nibble expands to a MODE 1 byte by
\ landing in the high plane, the low, both or neither as the ink's two
\ bits say — background 0, so clear pixels are clear bytes. 640 cells
\ of this once per page open; speed is not a consideration.
.ConDeckCell
  STA xfColV
  ASL A : ASL A : ASL A : ASL A \ dst = BUF_BASE + row*640 + col*16
  STA xgd
  LDA xfColV
  LSR A : LSR A : LSR A : LSR A
  STA xgd+1
  LDX lvRow
  CLC
  LDA xgd   : ADC xfRowAdrLo,X : STA xgd
  LDA xgd+1 : ADC xfRowAdrHi,X : STA xgd+1

  LDY lvChar                    \ the ink, 0-3, into two nibble masks
  LDA (xdest2),Y
  AND #2
  BEQ cd7_mh0
  LDA #&0F
.cd7_mh0
  STA cdMH
  LDA (xdest2),Y
  AND #1
  BEQ cd7_ml0
  LDA #&0F
.cd7_ml0
  STA cdML

  LDA lvChar                    \ planChars + code*8, byte indexed —
  ASL A : ASL A : ASL A         \ codes stop at $1E so it stays a byte
  TAX
  LDY #0
.cd7_row
  LDA planChars,X
  PHA
  LSR A : LSR A : LSR A : LSR A \ left half from the high nibble
  JSR cd7_expand
  STA (xgd),Y
  PLA
  AND #&0F                      \ right half from the low
  JSR cd7_expand
  PHA
  TYA : CLC : ADC #8 : TAY      \ the right half sits 8 bytes on
  PLA
  STA (xgd),Y
  TYA : SEC : SBC #8 : TAY
  INX
  INY
  CPY #8
  BNE cd7_row
  RTS

.cd7_expand                     \ A = source nibble -> MODE 1 byte
  STA cdNib
  AND cdMH
  ASL A : ASL A : ASL A : ASL A
  STA cdTmp
  LDA cdNib
  AND cdML
  ORA cdTmp
  RTS

.cdMH  EQUB 0                   \ the ink's high plane: &0F or 0
.cdML  EQUB 0                   \ and its low
.cdNib EQUB 0
.cdTmp EQUB 0
