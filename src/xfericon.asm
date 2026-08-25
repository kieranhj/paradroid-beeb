\ ============================================================
\ xfericon.asm — Layer 10 DECISION 14, in SWRAM BANK 7
\ ============================================================
\ ITS POSITION IN THE PARXFER BLOCK IS LOAD BEARING, the same way
\ src/consolesel.asm's is in bank 4 — but the OTHER way round.
\ plandata.asm's ALIGN &100 leaves padding that anything assembled
\ BEFORE it rides in for free, and after the Layer 10 glyph-pool pass
\ that padding was 126 B. The icons are 421 B all told, so they cannot
\ all ride: what does is droidicon7.asm's 110 B of rotor and digits and
\ the 14 B of state in xfer.asm, which together leave the padding at 2.
\ This file — the code, ~297 B — is therefore assembled BEHIND the
\ ALIGN, where it costs its own size and nothing more.
\ Move it in front and the padding rolls a page: 256 B of bank 7 gone
\ at a stroke, and the bank is 33 B from full. Measured 2026-08-25;
\ read docs/layer-10-transfer.md DECISION 14 before touching it.

\ ============================================================
\ XfIcons — the two droid number icons, DECISION 14
\ ============================================================
\ SubGameSelectSide puts two hardware sprites either side of the board:
\ sprite 7 with image $4F for the player ($E12B-$E14C) and the target's
\ with image droidSprNum+$48 ($E14F-$E175). $48*64 = $5200, the dynamic
\ sprite area, so these are the LIVE DROID SPRITES — rotor top and
\ bottom with the three-digit number between, exactly what
\ BuildDroidSprite ($3C77) and AnimateDroids ($3CFB) compose.
\
\ THEY DO NOT SLIDE. $E1B5-$E1C7 writes plySpriteX/cpuSpriteX as one of
\ two values, 88 or 255, and $E1F5-$E213 pushes those straight at the
\ sprite registers: the two icons SWAP SIDES when the stick changes its
\ mind, and each keeps its own colour throughout ($F1 white for the
\ player at $E144, 0 black for the target at $E165). KC, 2026-08-25,
\ correcting the first reading of this.
\
\ COLOUR: the transfer palette has no white, so the player's icon takes
\ the PLAYER's own colour — yellow, logical 1 — and the target's the
\ CPU's magenta, logical 2. KC's call, and it reads better than the
\ original's white/black on this palette anyway. The pens are the cell
\ painter's own, so nothing new had to be defined.
\
\ x=88 and x=255 are screen pixels 64 and 231 once the C64's 24-pixel
\ border offset comes off, which is board columns 8 and 28. Both sit in
\ the blank spans of the three-row top block -- xbTop has content only
\ at 19-20 (row 0), 3 and 18-21 and 36 (row 1), 3-5 and 18-21 and 34-36
\ (row 2) -- so the icons overlap no wire, and nothing repaints there:
\ XfDoColumn walks only the twelve wire rows, XfDrawCBar columns 19-20,
\ XfDrawResult row 1 columns 19-20, XfDrawPulserCols columns 1 and 38.
\ Drawn once at setup and again only on a side swap, they survive the
\ whole game. KC's observation, checked against the exported layout.
XI_LCOL = 8
XI_RCOL = 28
XI_ROWS = 21                    \ a C64 sprite, and rows 21-23 of the
                                \ three-cell block stay the blank board

\ Only the COLUMNS swap. The player's icon is always yellow and the
\ target's always magenta, the way the C64's keep their white and their
\ black, so the side is the only thing the stick changes.
.XfIcons
  LDX #XI_LCOL                  \ $FF is always the LEFT bus's colour, so
  LDA xfLeftColor               \ this is "is the human on the left" --
  CMP #&FF                      \ and NOT a test against xfPlyColor,
  BEQ xic_go                    \ which swaps every half-turn in play
  LDX #XI_RCOL
.xic_go
  LDA xfmPlyType
  LDY #&0F                      \ yellow: the LOW plane by itself
  JSR XfIcon

  LDA #XI_LCOL + XI_RCOL        \ the other column, from the one just
  SEC                           \ drawn: XfIcon leaves it in xiCol and
  SBC xiCol                     \ there are only ever these two, so this
  TAX                           \ costs four bytes less than keeping it
  LDA xfmTgtType
  LDY #&FF                      \ black: BOTH planes. KC, 2026-08-25 --
  JMP XfIcon                    \ magenta was the first cut, and black is
                                \ what the C64 gives the target anyway

\ ---- one icon: A = droid type, X = column, Y = pen ----------
.XfIcon
  STX xiCol
  STY xiMask                    \ &0F logical 1, &F0 logical 2, &FF logical 3

  TAY                           \ the type -> its three digits, ConDroid's
  LDA pnTabCent,Y               \ own sequence against the main-RAM mirrors
  STA xiDig+0
  LDA pnTabNum,Y
  LSR A : LSR A : LSR A : LSR A
  STA xiDig+1
  LDA pnTabNum,Y
  AND #&0F
  STA xiDig+2

  LDA xiCol                     \ col * 16, ten bits
  ASL A : ASL A : ASL A : ASL A
  STA xiBase
  LDA xiCol
  LSR A : LSR A : LSR A : LSR A
  STA xiBase+1

  LDA #0
  STA xiRow
.xi_row
  JSR XfIconRow                 \ three C64 sprite bytes into xiSrc
  LDA xiRow                     \ dst = rowAdr[s DIV 8] + col*16 + s MOD 8
  LSR A : LSR A : LSR A
  TAX
  CLC
  LDA xfRowAdrLo,X : ADC xiBase   : STA xgd
  LDA xfRowAdrHi,X : ADC xiBase+1 : STA xgd+1
  LDA xiRow
  AND #7
  CLC
  ADC xgd
  STA xgd
  BCC xi_nc
  INC xgd+1
.xi_nc

  LDY #0                        \ 0,8,16,24,32,40: three cells, each its
  LDX #0                        \ left half's 8 scanlines then its right's
.xi_byte
  LDA xiSrc,X
  AND #&F0                      \ the row's left four pixels...
  JSR XfIconPix
  STA (xgd),Y
  TYA : CLC : ADC #8 : TAY
  LDA xiSrc,X
  ASL A : ASL A : ASL A : ASL A \ ...and its right four, into the same
  JSR XfIconPix                 \ top-nibble form
  STA (xgd),Y
  TYA : CLC : ADC #8 : TAY
  INX
  CPX #3
  BNE xi_byte

  INC xiRow
  LDA xiRow
  CMP #XI_ROWS
  BNE xi_row
  RTS

\ ---- four pixels, in the icon's colour ----------------------
\ A holds them in the TOP nibble, one bit each. MODE 1 wants pixel n's
\ high plane in bit 7-n and its low plane in bit 3-n, so the top nibble
\ IS the high plane and the same nibble shifted down is the low one:
\ OR the two and the byte says logical 3, then AND with the icon's mask
\ to keep the planes it actually wants. &0F yellow, &F0 magenta, &FF
\ black -- one routine for any of the four logical colours, which is why
\ turning the target black cost two bytes here and gave six back at the
\ call sites.
.XfIconPix
  STA xiTmp2
  LSR A : LSR A : LSR A : LSR A
  ORA xiTmp2
  AND xiMask
  RTS

\ ---- one row of the droid — ConDroidRow, bank 6's, verbatim -
\ Rows 0-4 rotor top, 6-13 the digits, 15-19 rotor bottom. Rows 5, 14
\ and 20 are written by neither, so they stay blank -- and blank here
\ means logical 0, which is the board's own background.
.XfIconRow
  LDA #0
  LDX #2
.xir_blank
  STA xiSrc,X
  DEX
  BPL xir_blank

  LDA xiRow
  CMP #5
  BCC xir_rotor                 \ 0-4, and the index is the row
  CMP #6
  BCC xir_x
  CMP #14
  BCC xir_digits
  CMP #15
  BCC xir_x
  CMP #20
  BCS xir_x
  SEC                           \ 15-19 are rotor rows 5-9
  SBC #10
.xir_rotor
  STA xiTmp                     \ index * 3
  ASL A
  CLC : ADC xiTmp
  TAY
  LDX #0
.xir_rcopy
  LDA conDrRotor7,Y
  STA xiSrc,X
  INY
  INX
  CPX #3
  BNE xir_rcopy
.xir_x
  RTS

\ Each glyph is EIGHT ROWS OF ONE BYTE, because BuildDroidSprite writes
\ each digit into a byte column of its own -- so the three go straight
\ into the three bytes of the row with no packing at all.
.xir_digits
  SEC
  SBC #6                        \ the row within the glyph, 0-7
  STA xiTmp
  LDX #0
.xir_dloop
  STX xiTmp2
  LDA xiDig,X                   \ digit * 8 bytes a glyph
  ASL A : ASL A : ASL A
  CLC : ADC xiTmp
  TAY
  LDX xiTmp2
  LDA conDrDigits7,Y
  STA xiSrc,X
  INX
  CPX #3
  BNE xir_dloop
  RTS

\ ---- state, behind the ALIGN with its code ------------------
.xiCol       EQUB 0             \ DECISION 14's icons: column, mask as a
.xiMask      EQUB 0             \ BIT flag, col*16, the row and its three
.xiBase      EQUW 0             \ composed C64 sprite bytes, and the three
.xiRow       EQUB 0             \ digits of the number on it
.xiSrc       EQUB 0, 0, 0
.xiDig       EQUB 0, 0, 0
.xiTmp       EQUB 0
.xiTmp2      EQUB 0
