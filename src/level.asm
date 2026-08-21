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
\ BuildLevel — decompress a deck into the tile map
\   A = deck number (0-15)
\
\ Layer 13d: the C64's RLE and its decoder are GONE. export_bbc.py
\ decodes each deck offline — the RLE semantics BuildLevel used to
\ implement, byte-identical maps — and zx0-compresses the result, and
\ this is now just the pointer setup in front of Zx0Unpack, which
\ writes the 1,024 tiles straight into the map. The decoded map is
\ what it always was; only the packaging changed. See zx0depack.asm.
\ ============================================================
.BuildLevel
  TAY
  CLC
  LDA deckPackLo,Y : ADC #LO(deckPack) : STA src
  LDA deckPackHi,Y : ADC #HI(deckPack) : STA src+1

  LDA #LO(tilemap) : STA mapptr
  LDA #HI(tilemap) : STA mapptr+1
  JMP Zx0Unpack                 \ and its RTS

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
  STA bcColour                  \ EVERY CELL IS HIRES. Bit 3 of the colour
  CLC : ADC bcCmapBase          \ nibble is part of the COLOUR, not a mode
  TAX                           \ flag: the play area runs with $D016 bit 4
  LDA colourMap,X               \ CLEAR ($C0, written by _reenter_game at
  ASL A : ASL A : ASL A : ASL A \ $1532). This branched on AND #8 until
  STA bcLutOfs                  \ 2026-08-18 and drew every orange, grey or
                                \ light-grey cell as four fat pixels of the
                                \ wrong colours. See ref/c64_deck5.png.
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
\ LUTs+0..63   4 tables of 16, indexed by the cell colour's logical
\ Every cell is hires, so there is one table per foreground logical
\ colour and the old multicolour half of this table is gone.
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

  RTS

\ ---- working storage ---------------------------------------
\ Zero page is full. These are touched once per deck change, so
\ absolute addressing costs nothing that matters.
\ LUTs is NOT here any more: 64 bytes at &54C0, declared in main.asm.
\ Bank 4 ran out and this was the cheapest thing in it to move.
.bcDeck    EQUB 0
.bcRecOfs  EQUB 0
.bcCmapBase EQUB 0
.bcBg      EQUB 0
.bcColour  EQUB 0
.bcLutOfs  EQUB 0
.bcIndex   EQUB 0
.bcF       EQUB 0
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
