\ ============================================================
\ portrait.asm — the 48 x 84 droid portrait, BuildIntroSprites ($3629)
\ ============================================================
\ LAYER 13d, in SWRAM BANK 7 beside the droid database that shows it.
\ Composes the C64's own picture from the pool in portraits.asm: eight
\ 24 x 21 sprites in a 2 x 4 grid — record bytes name the left column,
\ the right column is an explicit image or a runtime mirror, exactly
\ MirrorSprite's ($3AE8) job here as there.
\
\ THE GRID OVERLAPS AND THE UPPER SPRITE WINS. Byte 63 of each LEFT
\ image is bit 7 = multicolour, bits 0-4 = rptLen — how many scanlines
\ below this row-pair the next one starts. rptLen < 21 makes pairs
\ overlap, and on the VIC the lower-numbered (upper) sprite has
\ priority. So this draws BOTTOM-UP with transparency: each pair only
\ writes its opaque pixels, and the pairs above it, drawn later,
\ overwrite where they are solid and let it show where they are not.
\ Transparency is SPR_MASKTAB's rule — a pixel is transparent exactly
\ when both its bits are clear — and that table is main RAM, readable
\ from here.
\
\ PIXELS: a multicolour pair is double-wide, so one source byte (4 mc
\ pixels) is 8 MODE 1 pixels = 2 bytes, through poLutL/poLutR, each
\ 2-bit value landing as logical colour v. A hires byte (two images
\ in the pool) is 8 single-wide pixels drawn in logical 2 — the same
\ colour multicolour's "10" lands in — so left = b AND &F0 and
\ right = b << 4, no table. One 4-colour palette for the whole page;
\ the C64's per-type sprite colour themes are Layer 14's problem.
\
\ THE TARGET is DbImage's own rectangle: buffer rows 2-12, units 4-15,
\ which is where the C64 puts it — sprite X=40 is 16 px in from the
\ visible edge = unit 4, and its Y=144 puts the picture level with the
\ content lines, clear of the stat text at column 9. The rectangle is
\ cleared first: composition is transparent, so whatever the last type
\ left there would otherwise show through.

\ ---- zero page, borrowed (the xfer/title argument: nothing that owns
\ these can run while the console has the machine) ------------
posrc = src                     \ -> the image being drawn
podst = svp                     \ -> the buffer byte column

PO_DST0 = BUF_BASE + DB_IMG_UNIT * UNIT_BYTES  \ scanline 0 of the rect's row
PO_H    = 84                    \ 4 x 21 nominal; rptLen only shrinks it

\ ---- and the rectangle MOVES, because the C64's does ---------
\ loc_0_365E+1 is BuildIntroSprites' own `LDA #40 / STA SpriteX`, and it
\ is PATCHED per screen: $36B3 puts 40 back for the database and the
\ information pages, and EndGame's $37E8 writes 160 for the game over.
\ 160 - 24 (the C64's first visible column) = 136 px in, which on a 320
\ px screen puts a 48 px picture exactly in the middle.
\
\ 136 px is unit 34 here, so poBase carries what was a constant. Every
\ caller sets it; DbImage sets the database page's, and it is set rather
\ than defaulted because the game over would otherwise inherit whatever
\ the last page left.
PO_UNIT_MID = 34
PO_DSTMID = BUF_BASE + PO_UNIT_MID * UNIT_BYTES

\ ============================================================
\ PoDraw — the whole portrait for type A
\ ============================================================
.PoDraw
  ASL A : ASL A : ASL A
  STA poIdxOfs                  \ type * 8, the record's slice of poIdx

\ ---- the four y bases, from the left images' rptLen ---------
  LDA #0
  STA poYs
  LDX #0
.pod_ybase
  LDY poIdxOfs
  LDA poIdx,Y                   \ the left image's slot...
  JSR PoImgPtr
  LDY #63
  LDA (posrc),Y                 \ ...and its metadata byte
  AND #&1F
  CLC
  ADC poYs,X
  STA poYs+1,X
  INC poIdxOfs
  INC poIdxOfs
  INX
  CPX #3
  BNE pod_ybase
  LDA poIdxOfs                  \ back to the record's start
  SEC : SBC #6
  STA poIdxOfs

\ ---- clear the rectangle ------------------------------------
\ 12 units x 84 scanlines of logical 0, rows 2-12. Row 12 only its
\ top 4 scanlines, but clearing all 8 is fewer instructions and the
\ 4 below the picture are blank page anyway.
  LDA #DB_IMG_ROW
  STA poRow
.pod_crow
  LDX poRow
  CLC
  LDA rowMulLo,X : ADC poBase   : STA podst
  LDA rowMulHi,X : ADC poBase+1 : STA podst+1
  LDA #0
  LDY #(12 * UNIT_BYTES) - 1
.pod_cbyte
  STA (podst),Y
  DEY
  CPY #&FF
  BNE pod_cbyte
  INC poRow
  LDA poRow
  CMP #DB_IMG_ROW + 11
  BNE pod_crow

\ ---- the four row-pairs, bottom-up --------------------------
  LDA #3
  STA poPair
.pod_pair
  LDA poPair                    \ the pair's y base
  TAX
  LDA poYs,X
  STA poYB

  TXA : ASL A                   \ record byte 2i: the left image
  CLC : ADC poIdxOfs
  TAY
  STY poRecIx
  LDA poIdx,Y
  STA poLeft
  JSR PoImgPtr
  LDA #0
  STA poColOfs
  JSR PoSprite                  \ left half

  LDY poRecIx                   \ record byte 2i+1: the right image...
  INY
  LDA poIdx,Y
  CMP #PO_MIRROR
  BNE pod_right
  LDA poLeft                    \ ...or the left's mirror, built fresh
  JSR PoImgPtr
  JSR PoMirror
  LDA #LO(poMirBuf) : STA posrc
  LDA #HI(poMirBuf) : STA posrc+1
  JMP pod_draw2
.pod_right
  JSR PoImgPtr
.pod_draw2
  LDA #6 * UNIT_BYTES
  STA poColOfs
  JSR PoSprite                  \ right half

  DEC poPair
  BPL pod_pair
  RTS

\ ============================================================
\ PoImgPtr — posrc = poPool + A * 64
\ ============================================================
.PoImgPtr
  STA poTmp
  LSR A : LSR A                 \ slot DIV 4 -> pages
  CLC : ADC #HI(poPool)
  STA posrc+1
  LDA poTmp
  AND #3
  LSR A : ROR A : ROR A         \ (slot AND 3) * 64, into bits 7-6
  CLC : ADC #LO(poPool)
  STA posrc
  BCC pip_x
  INC posrc+1
.pip_x
  RTS

\ ============================================================
\ PoMirror — poMirBuf = posrc flipped left-for-right
\ ============================================================
\ MirrorSprite: each 3-byte row reverses byte order AND each byte
\ reverses within itself — pixel pairs for multicolour, bits for
\ hires, byte 63 telling which. Byte 63 goes through unchanged.
.PoMirror
  LDY #63
  LDA (posrc),Y
  STA poMirBuf + 63
  STA poMeta
  LDY #60                       \ the last row's first byte
.pom_row
  LDX #2
.pom_byte
  STX poX                       \ the hires path needs X for itself
  LDA (posrc),Y
  BIT poMeta
  BPL pom_hires
  \ multicolour: [p0p1p2p3] -> [p3p2p1p0]
  STA poTmp
  AND #&03 : ASL A : ASL A : ASL A : ASL A : ASL A : ASL A : STA poB
  LDA poTmp : AND #&0C : ASL A : ASL A : ORA poB : STA poB
  LDA poTmp : LSR A : LSR A : AND #&0C : ORA poB : STA poB
  LDA poTmp : LSR A : LSR A : LSR A : LSR A : LSR A : LSR A : ORA poB
  JMP pom_put
.pom_hires
  STA poTmp                     \ reverse the eight bits through carry
  LDA #0
  STA poB
  LDX #8
.pom_bit
  LSR poTmp
  ROL poB
  DEX
  BNE pom_bit
  LDA poB
.pom_put
  LDX poX
  STA poMir3,X                  \ bytes 0,1,2 reversed into 2,1,0...
  INY
  DEX
  BPL pom_byte
  \ Y is now rowstart+3; poMir3 goes back at rowstart, and reading it
  \ 0,1,2 as Y ascends is what reverses the BYTE order too
  TYA
  SEC : SBC #3
  TAY
  LDX #0
.pom_copy
  LDA poMir3,X
  STA poMirBuf,Y
  INY
  INX
  CPX #3
  BNE pom_copy
  \ Y is rowstart+3 again; the row above starts six back
  TYA
  SEC : SBC #6
  TAY
  BPL pom_row                   \ row 0 starts at Y=0; below that, done
  RTS

\ ============================================================
\ PoSprite — one 24 x 21 image at (poColOfs, poYB), transparent
\ ============================================================
.PoSprite
  LDY #63
  LDA (posrc),Y
  STA poMeta                    \ bit 7 = multicolour
  LDA #0
  STA poR
  STA poSrcIx
.posp_row
  \ dst = BUF_BASE + rowMul[s DIV 8] + DB_IMG_UNIT*8 + poColOfs + (s MOD 8)
  \ where s = the absolute scanline, DB_IMG_ROW*8 + poYB + poR
  CLC
  LDA poYB
  ADC poR
  ADC #DB_IMG_ROW * 8
  STA poS
  LSR A : LSR A : LSR A
  TAX
  CLC
  LDA rowMulLo,X : ADC poBase   : STA podst
  LDA rowMulHi,X : ADC poBase+1 : STA podst+1
  LDA poS
  AND #7
  CLC
  ADC poColOfs                  \ <= 55: cannot carry, so one CLC serves
  ADC podst                     \ both adds
  STA podst
  BCC posp_sub
  INC podst+1
.posp_sub

  LDY #0                        \ dst offset: 0,8 then 16,24 then 32,40
  STY poK
.posp_byte
  LDY poSrcIx
  LDA (posrc),Y
  INC poSrcIx
  STA poB                       \ posp_put spends X, so keep the source
  BIT poMeta
  BPL posp_hires
  TAX
  LDA poLutL,X
  LDY poK
  JSR posp_put
  LDX poB
  LDA poLutR,X
  JMP posp_r
.posp_hires
  AND #&F0
  LDY poK
  JSR posp_put
  LDA poB
  ASL A : ASL A : ASL A : ASL A
.posp_r
  LDY poK
  INY : INY : INY : INY : INY : INY : INY : INY
  JSR posp_put
  CLC
  LDA poK
  ADC #16
  STA poK
  CMP #48
  BNE posp_byte

  INC poR
  LDA poR
  CMP #21
  BEQ posp_x
  JMP posp_row
.posp_x
  RTS

\ ---- one expanded byte, through the mask --------------------
\ A = the MODE 1 byte, Y = the offset from podst. SPR_MASKTAB turns it
\ into its own transparency mask: opaque pixels never map to colour 0,
\ so a pixel is transparent exactly when both its bits are clear.
.posp_put
  STA poE
  TAX
  LDA SPR_MASKTAB,X
  AND (podst),Y
  ORA poE
  STA (podst),Y
  RTS

\ ---- state, in this bank: it is RAM -------------------------
.poLastType
  EQUB &FF                      \ what the rectangle shows; &FF = nothing.
                                \ DbImage's guard, invalidated by DbClear
.poBase   EQUW PO_DST0        \ the rectangle's top-left, per screen
.poIdxOfs EQUB 0
.poYs     EQUB 0, 0, 0, 0       \ each pair's first scanline
.poPair   EQUB 0
.poRecIx  EQUB 0
.poLeft   EQUB 0
.poColOfs EQUB 0
.poYB     EQUB 0
.poRow    EQUB 0
.poR      EQUB 0
.poS      EQUB 0
.poK      EQUB 0
.poSrcIx  EQUB 0
.poMeta   EQUB 0
.poTmp    EQUB 0
.poX      EQUB 0
.poB      EQUB 0
.poE      EQUB 0
.poMir3   EQUB 0, 0, 0
.poMirBuf SKIP 64
