\ ============================================================
\ liftview.asm — the lift's deck-selection screen, in bank 7
\ ============================================================
\ DoLift's display half ($267A): the ship cross-section, the chosen
\ lift's shaft marked down its length, and the selected deck lit. The
\ STEPPING half — walking liftPos along the shaft — stays in bank 4
\ (LvTick4, droid.asm) because the stop tables live there; this file
\ only draws what the main-RAM mirrors say.
\
\ It rides on Layer 10's machinery wholesale, which it can because the
\ transfer game and the lift screen can never be up at once: the same
\ shadow character screen and colour shadow (xsScr/xsCram), the same
\ code->glyph page (xsGlyphOf, rebuilt on entry by whichever screen is
\ opening), the same row tables, zero-page aliases and panel-line text
\ engine, and the same 16-row display trick — the board is C64 rows
\ 9-24, all sixteen play rows, with fire 3 moved down via t1i3.
\
\ WHAT THE C64 DOES, and where each piece lands here:
\   DrawSideview ($3069)        LvStart7 — mode/palette setup is the
\                               bank-4 shim's; the draw is LvDrawPacked
\   DrawPacked ($30A0)          LvDrawPacked — the 201-byte RLE into a
\                               64-wide grid clipped to columns 3-41,
\                               each code ORA #$80, code $29 the blank.
\                               The C64 interleaves colour RAM writes
\                               from CharColor; our colour is baked into
\                               the glyph sets at export time
\   FindLift's tail ($2757)     LvShaftMark — colour $F9 down the shaft
\   lift_HighlightDeck ($240C)  LvHighlight — the +/-$10 character swap
\                               over the deck's rectangle, verbatim,
\                               including the odd LDY #-2 row bail-out
\
\ THE COLOUR IS IN THE ARTWORK: the C64's emboss — white 01 pairs on a
\ box's top and left, black 10s on its bottom and right — and the lit
\ variants' 11-pair fill (magenta) convert plane-for-plane at export,
\ so toggling the characters IS the whole highlight and LvHighlight
\ stays a pure transliteration. The one rendering rule left is the
\ C64's own: a cell the shaft mark coloured $F9 draws from the
\ forced-multicolour set — which is what turns the fine hires ladders
\ chunky and white down the chosen shaft, exactly as colour RAM bit 3
\ does on the C64.

\ ============================================================
\ LvStart7 — entry, with this bank paged (from LiftViewEnter)
\ ============================================================
.LvStart7
  JSR LvBuildGlyphOf
  JSR LvClearShadows
  JSR LvDrawPacked
  JSR LvShaftMark
  LDA deck                      \ light the deck we are standing on
  STA lvShown
  JSR LvHighlight
  JSR LvRepaintAll

  JSR XfTextClear               \ the panel line: "lift" and the deck
  LDA #XF_COL_MSG
  STA xfTxtCol
  LDA #XF_LC+11                 \ l
  JSR XfGlyphAt
  LDA #XF_LC+8                  \ i
  JSR XfGlyphAt
  LDA #XF_LC+5                  \ f
  JSR XfGlyphAt
  LDA #XF_LC+19                 \ t
  JSR XfGlyphAt
  JMP LvNumText                 \ and its RTS

\ ============================================================
\ LvShip7 — the CONSOLE's ship page (from ConsoleTick)
\ ============================================================
\ con_ShipInfo ($3062): DrawSideview minus the lift — the cross-section
\ with the CURRENT deck lit and NO shaft mark, drawn once and static.
\ The console has already flattened the scroll AND taken the sixteenth
\ row (ConsoleOpen), so this page draws the same sixteen the lift's does
\ and needs no display work of its own; the panel line stays the
\ console's. Rows 13-15 of the view are blank either way.
.LvShip7
  JSR LvBuildGlyphOf
  JSR LvClearShadows
  JSR LvDrawPacked
  LDA deck
  STA lvShown
  JSR LvHighlight
  JMP LvRepaintAll              \ and its RTS

\ ============================================================
\ LvTick7 — one pass (from LiftViewTick, after LvTick4 stepped)
\ ============================================================
\ The bank-4 half has already moved liftPos and lvSelDeck; all this does
\ is move the light: toggle the old deck off, the new on, and repaint
\ exactly those two rectangles — a step costs ~a hundred cells, not the
\ whole screen.
.LvTick7
  LDA lvSelDeck
  CMP lvShown
  BEQ lvt7_x
  LDA lvShown
  JSR LvHighlight               \ off — the toggle is its own inverse
  LDY lvShown
  JSR LvPaintRect
  LDA lvSelDeck
  STA lvShown
  JSR LvHighlight               \ on
  LDY lvShown
  JSR LvPaintRect
  JMP LvNumText                 \ and its RTS
.lvt7_x
  RTS

\ ---- both shadows clear: chars blank, colours 0 (no mark) ---
.LvClearShadows
  LDA #0
  TAY
.lvc_clr
  STA xsScr,Y
  STA xsScr+&100,Y
  STA xsScr+&200,Y
  STA xsCram,Y
  STA xsCram+&100,Y
  STA xsCram+&200,Y
  INY
  BNE lvc_clr
  LDY #&7F                      \ the last half page of each
.lvc_clr2
  STA xsScr+&280,Y
  STA xsCram+&280,Y
  DEY
  BPL lvc_clr2
  RTS

\ ============================================================
\ LvDrawPacked — DrawPacked ($30A0), into the shadow screen
\ ============================================================
\ The stream: high bit set means "code AND $7F, repeated by the next
\ byte", clear means one of this code. The virtual grid is 64 wide and
\ only columns 3-41 exist on screen; rows 0-15 are C64 screen rows 9-24,
\ which is shadow rows 0-15 exactly. Code $29 is the blank; everything
\ else gains $80, selecting the charset's upper half.
.LvDrawPacked
  LDA #LO(svData) : STA xsrc
  LDA #HI(svData) : STA xsrc+1
  LDA #LO(xsScr)  : STA xdest
  LDA #HI(xsScr)  : STA xdest+1
  LDA #0
  STA lvPos                     \ ptr_14: the grid column, 0-63
  STA lvRow                     \ ptr_14+1
.lvd_next
  LDY #0
  LDA (xsrc),Y
  BPL lvd_single
  AND #&7F
  STA lvChar
  INY
  LDA (xsrc),Y
  STA lvLen
  CLC
  LDA xsrc   : ADC #2 : STA xsrc
  LDA xsrc+1 : ADC #0 : STA xsrc+1
  JMP lvd_run
.lvd_single
  STA lvChar
  LDA #1
  STA lvLen
  CLC
  LDA xsrc   : ADC #1 : STA xsrc
  LDA xsrc+1 : ADC #0 : STA xsrc+1
.lvd_run
  LDA lvPos
  CMP #42
  BCS lvd_skip
  CMP #3
  BCC lvd_skip
  SBC #3                        \ carry set: the screen column
  TAY
  LDA lvChar
  CMP #&29                      \ the blank
  BNE lvd_ink
  LDA #0
  BEQ lvd_put
.lvd_ink
  ORA #&80
.lvd_put
  STA (xdest),Y
.lvd_skip
  INC lvPos
  LDA lvPos
  CMP #64
  BCC lvd_more
  LDA #0
  STA lvPos
  CLC
  LDA xdest   : ADC #40 : STA xdest
  LDA xdest+1 : ADC #0  : STA xdest+1
  INC lvRow
  LDA lvRow
  CMP #16
  BCS lvd_x
.lvd_more
  DEC lvLen
  BNE lvd_run
  BEQ lvd_next
.lvd_x
  RTS

\ ============================================================
\ LvShaftMark — FindLift's tail ($2757): colour the chosen shaft
\ ============================================================
\ liftNum is lift.asm's, set by LiftFind on the way in. The SEC before
\ the ADC is the C64's own off-by-one: the shaft column is svShaftX + 1.
.LvShaftMark
  LDY liftNum
  LDA svShaftY,Y
  CLC
  ADC #10                       \ table rows are C64 screen row - 10
  TAX
  LDA xsLineLo,X
  SEC
  ADC svShaftX,Y
  STA xdest
  LDA xsLineHi,X
  ADC #0
  STA xdest+1
  JSR XfScr2CRAM
  LDA svShaftH,Y
  AND #&F
  TAX
  LDY #0
.lvm_row
  LDA #&F9
  STA (xdest2),Y
  CLC
  LDA xdest2   : ADC #40 : STA xdest2
  LDA xdest2+1 : ADC #0  : STA xdest2+1
  DEX
  BNE lvm_row
  RTS

\ ============================================================
\ LvHighlight — lift_HighlightDeck ($240C), verbatim
\ ============================================================
\ A = the deck. Every character in the deck's rectangle swaps with its
\ +/-$10 partner — lit and unlit hull are adjacent halves of the
\ charset — so calling this twice puts the board back. Two arms: the
\ multi-row loop for the tall engine decks, and the single-row arm with
\ its own wider set of swappable codes. The magic constants are the
\ C64's own; do not rationalise them.
.LvHighlight
  TAY
  LDA svDeckH,Y
  STA xfCurIdx
  LDA svDeckY,Y
  CLC
  ADC #10
  TAX
  LDA xsLineLo,X
  SEC
  ADC svDeckX,Y                 \ +1, the same off-by-one as the shaft
  STA xdest
  LDA xsLineHi,X
  ADC #0
  STA xdest+1
  LDA svDeckW,Y
  STA xfColTmp
  LDA xfCurIdx
  CMP #1
  BEQ lvh_8
.lvh_1
  LDY #0
.lvh_2
  LDA (xdest),Y
  BPL lvh_5
  CMP #&9E
  BCS lvh_5
  CMP #&90
  BCS lvh_3
  ADC #&10                      \ carry clear: exactly +$10
  STA (xdest),Y
  JMP lvh_4
.lvh_3
  PHA
  SBC #&10                      \ carry set: exactly -$10
  STA (xdest),Y
  PLA
.lvh_4
  CMP #&92
  BEQ lvh_7
  CMP #&95
  BEQ lvh_7
  CMP #&98
  BEQ lvh_7
  CMP #&9B
  BEQ lvh_7
.lvh_5
  INY
  CPY xfColTmp
  BCC lvh_2
  CLC
  LDA xdest   : ADC #40 : STA xdest
  LDA xdest+1 : ADC #0  : STA xdest+1
  DEC xfCurIdx
  BNE lvh_1
  RTS
.lvh_7
  LDY #&FE                      \ $2475's LDY #-2: INY twice lands on
  JMP lvh_5                     \ $FF >= width, which ends the row
.lvh_8
  LDY #0
.lvh_9
  LDA (xdest),Y
  BPL lvh_12
  CMP #&9C
  BEQ lvh_11
  CMP #&9D
  BEQ lvh_11
  CMP #&93
  BCS lvh_12
  CMP #&90
  BCS lvh_11
  CMP #&8E
  BCS lvh_12
  CMP #&8C
  BCS lvh_10
  CMP #&83
  BCS lvh_12
.lvh_10
  CLC
  ADC #&10
  STA (xdest),Y
  JMP lvh_12
.lvh_11
  SBC #&10                      \ carry set by the compares that got here
  STA (xdest),Y
.lvh_12
  INY
  CPY xfColTmp
  BCC lvh_9
  RTS

\ ============================================================
\ LvPaintRect — repaint one deck's highlight rectangle
\ ============================================================
\ Y = the deck. The rectangle LvHighlight just walked: shadow rows
\ svDeckY+1 for svDeckH rows, columns svDeckX+1 for svDeckW.
.LvPaintRect
  LDA svDeckY,Y
  CLC
  ADC #1
  STA lvRow
  LDA svDeckH,Y
  STA lvLen
  LDA svDeckX,Y
  CLC
  ADC #1
  STA lvCol0
  LDA svDeckW,Y
  STA lvWid
.lvr_row
  LDA lvCol0
  STA lvPos
.lvr_col
  LDX lvRow
  LDA lvPos
  JSR LvCellPaint
  INC lvPos
  DEC lvWid
  BNE lvr_col
  LDY lvShown                   \ Y is clobbered by the paint; the width
  LDA svDeckW,Y                 \ reloads from whichever deck this is —
  STA lvWid                     \ see the caller: lvShown is always it
  INC lvRow
  DEC lvLen
  BNE lvr_row
  RTS

\ ============================================================
\ LvRepaintAll / LvCellPaint — the renderer
\ ============================================================
\ XfCellPaint's twin with the lift's rules: the glyph comes from
\ xsGlyphOf as there, but the PEN is decided here — lit characters
\ ($90-$9D) draw yellow, cells the shaft mark coloured $F9 draw
\ magenta, everything else white. Same zero page, same row tables.
.LvRepaintAll
  LDX #0
.lva_row
  LDA #0
.lva_col
  STA lvPos
  STX lvRow
  JSR LvCellPaint
  LDX lvRow
  LDA lvPos
  CLC
  ADC #1
  CMP #40
  BNE lva_col
  INX
  CPX #16
  BNE lva_row
  RTS

.LvCellPaint                    \ X = row 0-15, A = col 0-39
  STA xfColV
  CPX #16
  BCC lvc_on
  RTS
.lvc_on
  CLC
  LDA xsLineShLo,X : ADC xfColV : STA xgs
  LDA xsLineShHi,X : ADC #0     : STA xgs+1
  LDY #0
  LDA (xgs),Y
  STA xfChar
  CLC
  LDA xgs+1 : ADC #HI(XS_COFF) : STA xgs+1
  LDA (xgs),Y                   \ the colour token

\ The colour is IN the artwork — the emboss's white and black edges,
\ the lit variants' magenta fill — so the only choice here is the
\ C64's own: a cell the shaft mark coloured $F9 draws from the
\ forced-multicolour set, everything else from the normal one.
  LDY #1
  CMP #&F9
  BNE lvc_set
  INY
.lvc_set
  STY xfPen

  LDA xfColV                    \ dst = BUF_BASE + row*640 + col*16
  ASL A : ASL A : ASL A : ASL A
  STA xgd
  LDA xfColV
  LSR A : LSR A : LSR A : LSR A
  STA xgd+1
  CLC
  LDA xgd   : ADC xfRowAdrLo,X : STA xgd
  LDA xgd+1 : ADC xfRowAdrHi,X : STA xgd+1

  LDA xfChar
  BEQ lvc_blank
  TAX
  LDA xsGlyphOf,X               \ glyph * 16 into the pen's set
  LDY xfPen                     \ ...but the shaft pen has a set of its own
  CPY #2                        \ only for the rungs. Colour RAM $F9 changes
  BNE lvc_pen                   \ a glyph only where it has 01 pairs to
  CMP #SV_MARK0                 \ promote, and outside SV_MARK0..+N none of
  BCC lvc_pen                   \ them do — so there svChars1 already IS the
  CMP #SV_MARK0 + SV_MARK_N     \ marked art, and the second copy of it that
  BCS lvc_pen                   \ svChars2 used to be was 592 bytes of bank
  SEC                           \ 7 saying nothing. svCharsMk is the three
  SBC #SV_MARK0                 \ glyphs that do differ, indexed from
  INY                           \ SV_MARK0, and pen 3 is its base.
.lvc_pen
  STA xgs
  LDA #0
  STA xgs+1
  ASL xgs : ROL xgs+1
  ASL xgs : ROL xgs+1
  ASL xgs : ROL xgs+1
  ASL xgs : ROL xgs+1
  CLC
  LDA xgs   : ADC lvSetLo,Y : STA xgs
  LDA xgs+1 : ADC lvSetHi,Y : STA xgs+1
  LDY #15
.lvc_copy
  LDA (xgs),Y
  STA (xgd),Y
  DEY
  BPL lvc_copy
  RTS
.lvc_blank
  LDA #0
  LDY #15
.lvc_wipe
  STA (xgd),Y
  DEY
  BPL lvc_wipe
  RTS

\ Pen 0 is the blank, 1 the normal art, 2 the shaft pen falling back to
\ the normal art, and 3 the shaft rungs' own three glyphs.
.lvSetLo
  EQUB 0, LO(svChars1), LO(svChars1), LO(svCharsMk)
.lvSetHi
  EQUB 0, HI(svChars1), HI(svChars1), HI(svCharsMk)

\ ---- code -> glyph, into the SHARED page --------------------
\ xsGlyphOf belongs to whichever screen is up: XfStart rebuilds it for
\ the transfer, this for the lift. Cheap, and the page is the scarce
\ thing, not the loop.
.LvBuildGlyphOf
  LDA #0
  TAX
.lvb_clear
  STA xsGlyphOf,X
  INX
  BNE lvb_clear
  LDX #SV_CHARS-1
.lvb_fill
  LDA svCode,X
  TAY
  TXA
  STA xsGlyphOf,Y
  DEX
  BPL lvb_fill
  RTS

\ ---- the panel line's deck number ---------------------------
\ Two decimal digits of lvSelDeck, 0-15 as the engine counts decks —
\ the same value the debug bookmark and the console page show.
.LvNumText
  LDA #XF_COL_TIME
  STA xfTxtCol
  LDA lvSelDeck
  LDX #PN_DIGIT0                \ the tens digit
  CMP #10
  BCC lvn_units
  SBC #10                       \ carry set
  INX
.lvn_units
  PHA
  TXA
  JSR XfGlyphAt
  PLA
  CLC
  ADC #PN_DIGIT0
  JMP XfGlyphAt

\ ---- state --------------------------------------------------
.lvShown  EQUB 0                \ the deck currently lit on the view
.lvPos    EQUB 0                \ LvDrawPacked's grid column / a col temp
.lvRow    EQUB 0
.lvChar   EQUB 0
.lvLen    EQUB 0
.lvCol0   EQUB 0
.lvWid    EQUB 0
