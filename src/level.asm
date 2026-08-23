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
\ ---- TWO PALETTES PER DECK, one offset apart ---------------
\ The static text screens — the console and its pages, and the droid
\ information screens — draw their background in LOGICAL 0, which is the
\ deck's FLOOR. A floor chosen to look right underfoot is often far too
\ bright to read white text on (yellow, cyan, the dithered white of decks
\ 0 and 9), so those screens swap logical 0 for a colour of their own.
\ KC, 2026-08-23; the dither was tried there first and lost the text.
\
\ deckTextPal is the deck's four with logical 0 replaced, emitted
\ IMMEDIATELY after deckPalette, so the two differ by one offset and this
\ needs no second table lookup and no test in the loop. main.asm asserts
\ the adjacency; export_bbc.py refuses a text background that collides
\ with logicals 1-3.
.SetTextPal
  LDA #64                       \ deckTextPal - deckPalette
  BNE stp_go                    \ always
.SetPalette
  LDA #0
.stp_go
  STA palBase
  LDA deck
  ASL A : ASL A                 \ deck * 4 -> index into the chosen table
  CLC : ADC palBase
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

\ The ALERT lamp character's raw C64 bitmap, cached out of the packed
\ stream by BuildCharset for lowcode.asm's live re-colours.
.lampSrc
  SKIP 8

\ The ALERT lamp's ink by alert level, read by AnimNextLamp — in this bank
\ for the room rather than beside it in lowcode.asm. Level 3 also blinks.
.lampInk
  EQUB 1, 2, 3, 3

\ ---- UnpackChars — the char stream into the depack scratch --
\ Bitmaps at SPR_SAVE, the remap behind them. Callers: BuildCharset
\ (deck load) and BuildCharPtrs (boot, and GoTitle's rebuild — the
\ title's framebuffer sat on the scratch, so it must depack again).
\ Same zero-page loan as BuildLevel's use of the depacker: the level
\ draw is not running at any of those moments.
.UnpackChars
  LDA #LO(charSrcPak) : STA src
  LDA #HI(charSrcPak) : STA src+1
  LDA #LO(SPR_SAVE) : STA mapptr
  LDA #HI(SPR_SAVE) : STA mapptr+1
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

\ The bitmaps and the code→index remap ship as one ZX0 stream (layer-11e
\ stages 2-3 took the room for the sound driver), so unpack first — into
\ the sprite background save areas, dead here: SprInit or DroidsInit
\ re-deal every slot before anything restores, and the whole view is
\ redrawn before the next frame.
  JSR UnpackChars

\ And the ALERT lamp's 8 source bytes into lampSrc, because
\ BuildLampChar re-colours the lamp DURING PLAY, when this scratch is
\ long gone. lowcode.asm reads the cache, never the stream.
  LDX #ALERT_LAMP_CHAR
  LDA SPR_SAVE + CHARSRC_SIZE,X \ the depacked remap
  ASL A                         \ index * 8 — NUM_CHARS is 137, so the
  STA bcTmp                     \ 16-bit form matters
  LDA #0
  ROL A
  ASL bcTmp : ROL A
  ASL bcTmp : ROL A
  CLC
  ADC #HI(SPR_SAVE)
  STA bcSrc+1
  LDA bcTmp
  STA bcSrc                     \ SPR_SAVE is page-aligned: LO add is free
  LDY #7
.bc_lamp
  LDA (bcSrc),Y
  STA lampSrc,Y
  DEY
  BPL bc_lamp

  LDY bcDeck
  LDA deckScheme,Y              \ recOfs = scheme * 12
  ASL A : ASL A
  STA bcTmp
  ASL A
  CLC : ADC bcTmp
  STA bcRecOfs

  LDA bcDeck                    \ colourMap is indexed deck*16 + colour
  ASL A : ASL A : ASL A : ASL A
  STA bcCmapBase

\ THE DECK'S BACKGROUND IS ALWAYS LOGICAL 0, so it is not looked up here
\ any more. This used to read deckBg through colourMap into bcBg, and
\ BuildLUTs then computed background masks from it — arithmetic that could
\ only ever produce zero, because build_logical_map puts the background at
\ logical 0 by construction and logical 0 is %00. export_bbc.py now REFUSES
\ to write colours.asm if a hand-edited merge breaks that, so the whole
\ chain is gone and the bytes went to the dither.
  JSR BuildLUTs

\ ---- the floor dither's masks, for DitherChar -------------
\ DITHER ONLY WHERE LOGICAL 1 IS BLACK. On a deck whose logical 1 is a
\ COLOUR, shading with it would paint that colour onto the floor — louder,
\ not quieter. Testing logical 1 alone is enough: if logical 0 happened to
\ be black too the dither would blend black with black and simply not show,
\ so the only case the test has to catch is the harmful one.
  LDA bcDeck
  ASL A : ASL A : TAY
  LDA #&05                      \ even scanline: shade pixels 1 and 3
  LDX deckPalette+1,Y           \ logical 1's physical colour
  BEQ bc_dither
  LDA #0                        \ not black — leave this deck's floor solid
.bc_dither
  STA dcMask
  ASL A                         \ &05 -> &0A, the odd scanline's pixels 0 and
  STA dcMask+1                  \ 2; and 0 -> 0, so "off" needs no second path

  LDA #LO(SPR_SAVE) : STA bcSrc \ the bitmaps, unpacked above
  LDA #HI(SPR_SAVE) : STA bcSrc+1
  LDA #LO(charset) : STA bcDst
  LDA #HI(charset) : STA bcDst+1
  CLC
  LDA bcDst   : ADC #8 : STA bcDst2
  LDA bcDst+1 : ADC #0 : STA bcDst2+1
  LDA #0 : STA bcIndex

.bc_char
  LDA bcIndex                   \ colour = schemes[recOfs + slot]. The
  LSR A                         \ slots are nibble-packed two to a byte,
  TAX                           \ even char low — layer-11e stage 3 took
  LDA charSlotP,X               \ the spare nibbles for the sound triggers
  BCC bc_sloteven
  LSR A : LSR A : LSR A : LSR A
.bc_sloteven
  AND #&0F
  CMP #REC_LEN                  \ a few characters carry a slot beyond the
  BCS bc_slot_oob               \ 12-byte record — the C64 reads past the end
  CLC : ADC bcRecOfs            \ of clr0_top_d020 into adjacent variables, so
  TAX                           \ its behaviour there is incidental. Clamp to
  LDA schemes,X                 \ a defined value instead.
  JMP bc_got_colour
.bc_slot_oob
  LDA #0
.bc_got_colour
                                \ EVERY CELL IS HIRES. Bit 3 of the colour
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

  JSR DitherChar                \ Layer 14's floor dither, over the 16 bytes
                                \ just written. Here rather than in a pass of
                                \ its own because bcDst already walks the
                                \ charset a character at a time.
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
\ DitherChar — half-intensity floor, Layer 14
\ ============================================================
\ The BBC palette is fully saturated, so a floor of solid red or cyan is
\ far harsher than the C64's. Half the floor's pixels take LOGICAL 1
\ instead — physical black on the decks this runs on — in a 2x2 checker,
\ and the floor reads at half intensity. KC's decision, 2026-08-22; the
\ previews are in docs/layer-14-visual.md.
\
\ WHY IT IS A PASS OVER THE FINISHED CHARSET rather than a change to the
\ LUTs: the pattern alternates per SCANLINE and a LUT entry is indexed by
\ the source nibble alone, so building it in would have meant two LUT sets
\ and 64 more bytes of a region that has none. Here the parity is just bit
\ 0 of the byte index — a character is 16 bytes, the left half's 8
\ scanlines then the right half's, so Y bit 0 IS the scanline parity in
\ both halves, and the phase carries across characters because 16 is even.
\ Cell width and height are 8, both even, so it carries across the map
\ too and there are no seams.
\
\ It dithers logical 0 WHEREVER IT LANDS, ink as well as floor. A cell
\ whose colour merged onto logical 0 is invisible against the floor today;
\ dithering only the floor would have made it appear as a solid patch.
\
\ Which pixels are logical 0 is exactly the question SPR_MASKTAB answers —
\ SprBuildMask fills it with "this pixel has no colour", the sprite
\ transparency mask, duplicated into both nibbles. The dither mask is low
\ nibble only, so the ORA can only ever set the LOW colour plane: logical
\ 0 -> logical 1, and a pixel with any colour is left alone.
\
\ ONE CHARACTER AT A TIME, at (bcDst), called from BuildCharset's own loop
\ — which already walks the charset a character at a time, so the dither
\ costs no second walk. BuildLampChar (lowcode.asm) calls the same entry:
\ it rebuilds character $16 during play and would otherwise leave that one
\ cell solid against a dithered floor. Reaching this bank from there is
\ legal for the reason lowcode.asm's header gives — SWRAM_DATA is the
\ resting state, so the main loop can see bank 4.
\
\ dcMask is ZERO on a deck that keeps a solid floor, which makes this a
\ no-op without a second test in either caller. BuildCharset sets it.
\
\ ~5 ms across a deck load. Nothing in the main loop pays anything.
\ ============================================================
.DitherChar
  LDY #15
.dc_byte
  LDA (bcDst),Y
  STA bcTmp
  TAX
  LDA SPR_MASKTAB,X             \ set bit = this pixel is logical 0
  STA bcTmp2
  TYA
  AND #1                        \ the scanline's parity, in both halves
  TAX
  LDA dcMask,X
  AND bcTmp2
  ORA bcTmp
  STA (bcDst),Y
  DEY
  BPL dc_byte
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

\ THE BACKGROUND CONTRIBUTES NOTHING. It is logical 0 on every deck —
\ guaranteed by export_bbc.py, which refuses to write colours.asm
\ otherwise — and logical 0 is %00, so a clear source bit is already a
\ clear pair of plane bits. The bcBg/bcGH/bcGL arithmetic that used to
\ stand here computed zero, and its two ORA pairs in the inner loop
\ ORA'd zero in. Removed 2026-08-22; the bytes paid for DitherCharset.

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
  TYA : AND bcFH                \ set pixels take the foreground; clear ones
  ASL A : ASL A : ASL A : ASL A \ are logical 0 and want no bits at all
  STA bcTmp2
  TYA : AND bcFL
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
.bcLutOfs  EQUB 0
.bcIndex   EQUB 0
.bcF       EQUB 0
.bcFH      EQUB 0
.bcFL      EQUB 0
.dcMask    EQUB 0, 0            \ DitherCharset's shade masks, by scanline
                                \ parity. Both ZERO on a deck that keeps a
                                \ solid floor, which makes the pass a no-op.
.bcTmp     EQUB 0
.bcTmp2    EQUB 0
.palBase   EQUB 0
.palTmp    EQUB 0
