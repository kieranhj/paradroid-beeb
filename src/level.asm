\ ============================================================
\ level.asm — deck decode, charset build, palette, framing
\ ============================================================

\ ============================================================
\ SetPalette — physical colours for this deck's logical 0-3
\ ============================================================
\ Writes the video ULA palette register directly rather than going
\ through VDU 19, so nothing here touches the OS.
\
\ &FE21 takes (logical << 4) | (physical EOR 7). The logical field is
\ a content-addressable match, and in a 4-colour mode only bits 7 and
\ 5 of the byte are compared — bits 6 and 4 must be written in every
\ combination or the colour comes out split. So all 16 entries are
\ written, each mapped back to its logical colour:
\
\     logical = ((n AND 8) >> 2) OR ((n AND 2) >> 1)
\
\ which gives four entries per logical colour, covering 0-15 exactly.
\
\ IT BUILDS palPlay RATHER THAN WRITING THE ULA, because the panel now
\ has a palette of its own and the rupture swaps between the two three
\ times a frame — see the header in rupture.asm. palPlay is in main RAM
\ for the same reason: this routine is in bank 4 and the interrupt that
\ reads the table cannot see bank 4 while a sprite is being blitted.
.SetPalette
  LDA deck
  ASL A : ASL A                 \ deck * 4 -> index into deckPalette
  STA palBase
  LDX #15
.sp_loop
  TXA                           \ logical colour for this entry
  AND #8
  LSR A : LSR A
  STA palTmp
  TXA
  AND #2
  LSR A
  ORA palTmp
  CLC : ADC palBase
  TAY
  LDA deckPalette,Y             \ physical colour, 0-7
  EOR #7                        \ the ULA wants it inverted
  STA palTmp
  TXA
  ASL A : ASL A : ASL A : ASL A \ logical selector in the top nibble
  ORA palTmp
  STA palPlay,X
  DEX
  BPL sp_loop
  JMP SetPalPlay                \ live immediately, not at the next fire 1

\ ============================================================
\ BuildLevel — RLE-decode a deck into the tile map
\   A = deck number (0-15)
\
\ RLE format, unchanged from the C64:
\   bit 7 clear -> one tile, index in bits 0-4
\   bit 7 set   -> tile index in bits 0-4, next byte is the count
\ Stops when the map is full. A count of 0 means 256, which falls
\ out of decrementing after the store.
\ ============================================================
.BuildLevel
  TAY
  CLC
  LDA deckOffsetLo,Y : ADC #LO(leveldata) : STA src
  LDA deckOffsetHi,Y : ADC #HI(leveldata) : STA src+1

  LDA #LO(tilemap) : STA mapptr
  LDA #HI(tilemap) : STA mapptr+1

.bl_next
  LDY #0
  LDA (src),Y
  STA rptTile
  BPL bl_single
  INY                           \ bit 7 set: a count byte follows
  LDA (src),Y
  STA rptLen
  ADDPTR src, 2
  JMP bl_fill
.bl_single
  LDA #1
  STA rptLen
  ADDPTR src, 1
.bl_fill
  LDA rptTile
  AND #&1F
  STA rptTile
  LDY #0
.bl_put
  LDA rptTile
  STA (mapptr),Y
  INC mapptr
  BNE bl_nohi
  INC mapptr+1
.bl_nohi
  LDA mapptr+1                  \ map full?
  CMP #HI(tilemap_end)
  BNE bl_more
  LDA mapptr
  CMP #LO(tilemap_end)
  BEQ bl_done
.bl_more
  DEC rptLen
  BNE bl_put
  JMP bl_next
.bl_done
  RTS

\ ============================================================
\ BuildCharset — convert the C64 characters to MODE 1 for a deck
\   A = deck number
\
\ A character's MODE and COLOUR both depend on the deck: the C64
\ picks hires or multicolour per cell from bit 3 of the colour
\ RAM nibble, which NewCharColors rewrites per deck from a
\ 12-slot record. Shipping 16 converted charsets would cost 64K,
\ so we ship the C64 bitmaps plus colour metadata (~1.9K) and
\ convert on entering a deck.
\
\ Both modes consume one source nibble per output byte — hires
\ gives 4 pixels, multicolour 2 pixels each doubled — so the
\ inner loop is identical and only the lookup table differs.
\ ============================================================
.BuildCharset
  STA bcDeck
  TAY
  LDA deckScheme,Y              \ recOfs = scheme * 12
  ASL A : ASL A
  STA bcTmp
  ASL A
  CLC : ADC bcTmp
  STA bcRecOfs

  LDA bcDeck                    \ colourMap is indexed deck*16 + colour
  ASL A : ASL A : ASL A : ASL A
  STA bcCmapBase

  LDY bcDeck                    \ $D021 is PER DECK — slot 0 of its colour
  LDA deckBg,Y                  \ record, not a constant. Only decks 2 and 7
  CLC : ADC bcCmapBase : TAX    \ are the light blue this used to assume for
  LDA colourMap,X : STA bcBg    \ all sixteen. See tools/export_bbc.py.
  CLC : LDA bcCmapBase : ADC #D022_COLOUR : TAX
  LDA colourMap,X : STA bcD022L
  CLC : LDA bcCmapBase : ADC #D023_COLOUR : TAX
  LDA colourMap,X : STA bcD023L

  JSR BuildLUTs

  LDA #LO(charSrc) : STA bcSrc
  LDA #HI(charSrc) : STA bcSrc+1
  LDA #LO(charset) : STA bcDst
  LDA #HI(charset) : STA bcDst+1
  CLC
  LDA bcDst   : ADC #8 : STA bcDst2
  LDA bcDst+1 : ADC #0 : STA bcDst2+1
  LDA #0 : STA bcIndex

.bc_char
  LDX bcIndex                   \ colour = schemes[recOfs + slot]
  LDA charSlot,X
  CMP #REC_LEN                  \ a few characters carry a slot beyond the
  BCS bc_slot_oob               \ 12-byte record — the C64 reads past the end
  CLC : ADC bcRecOfs            \ of clr0_top_d020 into adjacent variables, so
  TAX                           \ its behaviour there is incidental. Clamp to
  LDA schemes,X                 \ a defined value instead.
  JMP bc_got_colour
.bc_slot_oob
  LDA #0
.bc_got_colour
  STA bcColour
  AND #8
  BEQ bc_hires

  LDA bcColour                  \ multicolour: LUT from the 11 colour
  AND #7
  CLC : ADC bcCmapBase
  TAX
  LDA colourMap,X
  ASL A : ASL A : ASL A : ASL A
  CLC : ADC #64                 \ multicolour LUTs follow the hires ones
  STA bcLutOfs
  JMP bc_rows

.bc_hires
  LDA bcColour                  \ hires: LUT from the cell colour
  CLC : ADC bcCmapBase
  TAX
  LDA colourMap,X
  ASL A : ASL A : ASL A : ASL A
  STA bcLutOfs

.bc_rows
  LDY #7
.bc_row
  LDA (bcSrc),Y
  PHA
  LSR A : LSR A : LSR A : LSR A \ high nibble -> left half
  CLC : ADC bcLutOfs
  TAX
  LDA LUTs,X
  STA (bcDst),Y
  PLA
  AND #&0F                      \ low nibble -> right half
  CLC : ADC bcLutOfs
  TAX
  LDA LUTs,X
  STA (bcDst2),Y
  DEY
  BPL bc_row

  CLC
  LDA bcSrc    : ADC #8  : STA bcSrc
  LDA bcSrc+1  : ADC #0  : STA bcSrc+1
  CLC
  LDA bcDst    : ADC #16 : STA bcDst
  LDA bcDst+1  : ADC #0  : STA bcDst+1
  CLC
  LDA bcDst2   : ADC #16 : STA bcDst2
  LDA bcDst2+1 : ADC #0  : STA bcDst2+1

  INC bcIndex
  LDA bcIndex
  CMP #NUM_CHARS
  BEQ bc_done
  JMP bc_char
.bc_done
  RTS

\ ============================================================
\ BuildLUTs — nibble -> MODE 1 byte tables for this deck
\
\ LUTs+0..63   hires,       4 tables of 16, indexed by cell colour
\ LUTs+64..127 multicolour, 4 tables of 16, indexed by the 11 colour
\
\ A MODE 1 byte is a nibble of high colour bits then a nibble of
\ low bits, so each entry is built as H<<4 | L.
\ ============================================================
.BuildLUTs
  LDA #0
  STA bcLutOfs
  STA bcF

  LDA bcBg                      \ background masks are constant
  AND #2 : BEQ bl_g0
  LDA #&0F : BNE bl_g1
.bl_g0
  LDA #0
.bl_g1
  STA bcGH
  LDA bcBg
  AND #1 : BEQ bl_g2
  LDA #&0F : BNE bl_g3
.bl_g2
  LDA #0
.bl_g3
  STA bcGL

.bl_f                           \ ---- hires tables ----
  LDA bcF
  AND #2 : BEQ bl_f0
  LDA #&0F : BNE bl_f1
.bl_f0
  LDA #0
.bl_f1
  STA bcFH
  LDA bcF
  AND #1 : BEQ bl_f2
  LDA #&0F : BNE bl_f3
.bl_f2
  LDA #0
.bl_f3
  STA bcFL

  LDY #0
.bl_n
  TYA : AND bcFH : STA bcTmp    \ set pixels take the foreground
  TYA : EOR #&0F : AND bcGH     \ clear pixels take the background
  ORA bcTmp
  ASL A : ASL A : ASL A : ASL A
  STA bcTmp2
  TYA : AND bcFL : STA bcTmp
  TYA : EOR #&0F : AND bcGL
  ORA bcTmp
  ORA bcTmp2
  STA bcTmp
  TYA : CLC : ADC bcLutOfs : TAX
  LDA bcTmp
  STA LUTs,X
  INY
  CPY #16
  BNE bl_n

  LDA bcLutOfs : CLC : ADC #16 : STA bcLutOfs
  INC bcF
  LDA bcF : CMP #4
  BNE bl_f

  LDA #0                        \ ---- multicolour tables ----
  STA bcP3
.bl_p
  LDA bcBg    : STA bcPal
  LDA bcD022L : STA bcPal+1
  LDA bcD023L : STA bcPal+2
  LDA bcP3    : STA bcPal+3

  LDY #0
.bl_mn
  TYA : LSR A : LSR A : TAX     \ first C64 pixel
  LDA bcPal,X : STA bcA
  TYA : AND #3 : TAX            \ second C64 pixel
  LDA bcPal,X : STA bcB

  LDA #0 : STA bcTmp2           \ H: each pixel doubled
  LDA bcA : AND #2 : BEQ bl_h1
  LDA #%1100 : ORA bcTmp2 : STA bcTmp2
.bl_h1
  LDA bcB : AND #2 : BEQ bl_h2
  LDA #%0011 : ORA bcTmp2 : STA bcTmp2
.bl_h2
  LDA bcTmp2 : ASL A : ASL A : ASL A : ASL A : STA bcTmp2

  LDA #0 : STA bcTmp            \ L
  LDA bcA : AND #1 : BEQ bl_l1
  LDA #%1100 : ORA bcTmp : STA bcTmp
.bl_l1
  LDA bcB : AND #1 : BEQ bl_l2
  LDA #%0011 : ORA bcTmp : STA bcTmp
.bl_l2
  LDA bcTmp2 : ORA bcTmp
  STA bcTmp
  TYA : CLC : ADC bcLutOfs : TAX
  LDA bcTmp
  STA LUTs,X
  INY
  CPY #16
  BNE bl_mn

  LDA bcLutOfs : CLC : ADC #16 : STA bcLutOfs
  INC bcP3
  LDA bcP3 : CMP #4
  BEQ bl_mcdone
  JMP bl_p
.bl_mcdone
  RTS

\ ---- working storage ---------------------------------------
\ Zero page is full. These are touched once per deck change, so
\ absolute addressing costs nothing that matters.
.LUTs      SKIP 128             \ 4 hires + 4 multicolour nibble tables
.bcDeck    EQUB 0
.bcRecOfs  EQUB 0
.bcCmapBase EQUB 0
.bcBg      EQUB 0
.bcD022L   EQUB 0
.bcD023L   EQUB 0
.bcColour  EQUB 0
.bcLutOfs  EQUB 0
.bcIndex   EQUB 0
.bcF       EQUB 0
.bcP3      EQUB 0
.bcFH      EQUB 0
.bcFL      EQUB 0
.bcGH      EQUB 0
.bcGL      EQUB 0
.bcA       EQUB 0
.bcB       EQUB 0
.bcTmp     EQUB 0
.bcTmp2    EQUB 0
.bcPal     SKIP 4
.palBase   EQUB 0
.palTmp    EQUB 0
