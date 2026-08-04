\ ============================================================
\ Paradroid — BBC Model B port
\ LAYER 3a: map browser — scroll by character, switch decks
\ ============================================================
\ Z / X       scroll left / right   (one character = 8 pixels)
\ K / M       scroll up / down      (one character = 8 scanlines)
\ UP / DOWN   previous / next deck
\
\ Full-screen redraw per step. No hardware scroll yet — this chunk
\ proves DrawScreen renders correctly from an arbitrary map origin,
\ which is the prerequisite for the CRTC scroll in 3b. Expect
\ tearing: the redraw takes ~2.5 frames and is not display synced.
\ ============================================================

CPU 0                           \ plain 6502 — Model B

OSWRCH    = &FFEE
OSBYTE    = &FFF4
OSCLI     = &FFF7
CRTC_ADDR = &FE00
CRTC_DATA = &FE01

SCREEN    = &4000

CHAR_BYTES = 16                 \ a character is 16 contiguous bytes
ROW_BYTES  = 640                \ one character row
SCR_COLS   = 40                 \ characters across
SCR_ROWS   = 25                 \ character rows

MAP_COLS   = 64                 \ tile map is 64 x 16 tiles
MAP_ROWS   = 16
MAP_CHAR_W = MAP_COLS * 4       \ 256 characters across
MAP_CHAR_H = MAP_ROWS * 4       \ 64 character rows

MAX_X      = MAP_CHAR_W - SCR_COLS   \ 216
MAX_Y      = MAP_CHAR_H - SCR_ROWS   \ 39
NUM_DECKS  = 16

\ Shared C64 play-area colours. Only the low nibble of each $D02x
\ register is used; these index the per-deck colourMap.
D021_COLOUR = 14                \ background — the floor
D022_COLOUR = 1                 \ multicolour 01 — white
D023_COLOUR = 0                 \ multicolour 10 — black
REC_LEN     = 12                \ colour slots per scheme record

\ ---- negative INKEY codes, as unsigned bytes ---------------
KEY_Z      = &9E                \ -98
KEY_X      = &BD                \ -67
KEY_K      = &B9                \ -71
KEY_M      = &9A                \ -102
KEY_UP     = &C6                \ -58
KEY_DOWN   = &D6                \ -42

\ ---- zero page (user area &70-&8F) -------------------------
scr      = &70                  \ screen destination        (2)
chp      = &72                  \ charset source            (2)
tdp      = &74                  \ tile definition source    (2)
src      = &76                  \ RLE read pointer          (2)
mapptr   = &78                  \ tile map write pointer    (2)
rptTile  = &7A                  \ tile being repeated
rptLen   = &7B                  \ repeat count
rowscr   = &7C                  \ current row's screen base (2)
maprow   = &7E                  \ current row's map base    (2)
cy       = &80                  \ character row counter
cx       = &81                  \ character column counter
tilecol  = &82                  \ tile column within the row
subcol   = &83                  \ character column within tile, 0-3
subbase  = &84                  \ (mapY AND 3) * 4
mapY     = &85                  \ map character row being drawn
tileRow  = &86                  \ mapY >> 2
charX    = &87                  \ viewport origin, characters
charY    = &88
deck     = &89                  \ current deck, 0-15
dirty    = &8A                  \ redraw needed
prevUp   = &8B                  \ deck keys, previous state (edge detect)
prevDn   = &8C

\ BuildCharset pointers. It runs before BuildLevel and DrawScreen,
\ so it can borrow their zero page rather than claim more.
bcSrc    = src                  \ read pointer into charSrc     (2)
bcDst    = mapptr               \ write pointer, left halves    (2)
bcDst2   = tdp                  \ write pointer, right halves   (2)

MACRO CRTC reg, val
  LDA #reg : STA CRTC_ADDR : LDA #val : STA CRTC_DATA
ENDMACRO

MACRO ADDPTR ptr, val
  CLC
  LDA ptr   : ADC #LO(val) : STA ptr
  LDA ptr+1 : ADC #HI(val) : STA ptr+1
ENDMACRO

\ DFS reserves &1100-&18FF for random-access file buffers, which simple
\ *LOAD / OSFILE loads never touch. So we start at &1100, not PAGE.
ORG &1100
.start

\ ---- select MODE 1, cursor off -----------------------------
  LDA #22 : JSR OSWRCH
  LDA #1  : JSR OSWRCH
  LDA #23 : JSR OSWRCH
  LDA #1  : JSR OSWRCH
  LDX #8
  LDA #0
.cursoff
  JSR OSWRCH
  LDA #0
  DEX
  BNE cursoff

\ (palette is set per deck, in LoadDeck)

\ ---- CRTC: 320x200 based at &4000 --------------------------
  CRTC 6,  25
  CRTC 7,  31
  CRTC 12, &08
  CRTC 13, &00

\ ---- load the data file ------------------------------------
\ Must follow the mode change: VDU 22 clears &3000-&7FFF.
  LDX #LO(loadcmd)
  LDY #HI(loadcmd)
  JSR OSCLI

\ ---- cursor keys return codes, not cursor editing -----------
  LDA #4 : LDX #1 : JSR OSBYTE

\ ---- initial state -----------------------------------------
  LDA #1 : STA deck
  LDA #0 : STA charX
  STA charY
  STA prevUp
  STA prevDn
  JSR LoadDeck

\ ============================================================
\ Main loop
\ ============================================================
.mainloop
  LDA #0
  STA dirty

  LDX #KEY_Z                    \ scroll left
  JSR keydown
  BNE ml_notZ
  LDA charX
  BEQ ml_notZ
  DEC charX
  INC dirty
.ml_notZ

  LDX #KEY_X                    \ scroll right
  JSR keydown
  BNE ml_notX
  LDA charX
  CMP #MAX_X
  BCS ml_notX
  INC charX
  INC dirty
.ml_notX

  LDX #KEY_K                    \ scroll up
  JSR keydown
  BNE ml_notK
  LDA charY
  BEQ ml_notK
  DEC charY
  INC dirty
.ml_notK

  LDX #KEY_M                    \ scroll down
  JSR keydown
  BNE ml_notM
  LDA charY
  CMP #MAX_Y
  BCS ml_notM
  INC charY
  INC dirty
.ml_notM

  \ Deck keys are edge triggered: one press steps one deck, however
  \ long it is held. A blocking wait-for-release would deadlock if the
  \ other deck key went down before the first was let go.
  LDX #KEY_UP                   \ previous deck
  JSR keydown
  BNE ml_upOff
  LDA prevUp
  BNE ml_notUp                  \ already down last time — not an edge
  LDA #1
  STA prevUp
  LDA deck
  BEQ ml_notUp
  DEC deck
  JSR LoadDeck
  JMP ml_notUp
.ml_upOff
  LDA #0
  STA prevUp
.ml_notUp

  LDX #KEY_DOWN                 \ next deck
  JSR keydown
  BNE ml_dnOff
  LDA prevDn
  BNE ml_notDn
  LDA #1
  STA prevDn
  LDA deck
  CMP #NUM_DECKS-1
  BCS ml_notDn
  INC deck
  JSR LoadDeck
  JMP ml_notDn
.ml_dnOff
  LDA #0
  STA prevDn
.ml_notDn

  LDA dirty
  BEQ ml_nodraw
  JSR DrawScreen
.ml_nodraw
  JMP mainloop

.loadcmd
  EQUS "LOAD PARADAT"
  EQUB 13

\ Physical colours come from deckPalette in colours.asm, indexed
\ deck*4 + logical colour.

\ ============================================================
\ LoadDeck — decode the current deck and redraw from the origin
\ ============================================================
.LoadDeck
  LDA deck
  JSR BuildCharset              \ charset is deck specific — see below
  JSR SetPalette
  LDA deck
  JSR BuildLevel
  JSR CentreOnDeck
  JSR DrawScreen
  RTS

\ ============================================================
\ SetPalette — physical colours for this deck's logical 0-3
\ ============================================================
.SetPalette
  LDA deck
  ASL A : ASL A                 \ deck * 4
  STA bcTmp
  LDX #0
.sp_loop
  LDA #19 : JSR OSWRCH
  TXA     : JSR OSWRCH          \ logical colour
  TXA
  CLC : ADC bcTmp
  TAY
  LDA deckPalette,Y : JSR OSWRCH
  LDA #0  : JSR OSWRCH
  LDA #0  : JSR OSWRCH
  LDA #0  : JSR OSWRCH
  INX
  CPX #4
  BNE sp_loop
  RTS

\ ============================================================
\ BuildCharset — convert the C64 characters to MODE 1 for a deck
\   A = deck number
\
\ A character's MODE and COLOUR both depend on the deck: the C64
\ picks hires or multicolour per cell from bit 3 of the colour
\ RAM nibble, which NewCharColors rewrites per deck from a
\ 12-slot record. Shipping 16 converted charsets would cost 64K,
\ so we ship the C64 bitmaps plus the colour metadata (~1.9K)
\ and convert on entering a deck.
\
\ Both modes consume a nibble of the source byte per output byte:
\ hires  — 4 pixels, background or the cell colour
\ multi  — 2 pixels, each doubled, from a 4-entry palette
\ so the inner loop is identical and only the lookup table
\ differs. LUTs are rebuilt per deck by BuildLUTs.
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

  CLC : LDA bcCmapBase : ADC #D021_COLOUR : TAX
  LDA colourMap,X : STA bcBg
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

  CLC                           \ next character
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

\ ============================================================
\ CentreOnDeck — put the viewport over the deck's contents
\
\ Decks occupy varying regions of the 64x16 grid and are padded
\ with empty tiles, so a (0,0) origin usually lands in blank
\ space. Derived from the map itself rather than the per-deck
\ metadata tables, which hold side-view positions, not extents.
\
\ Uses the centroid of non-empty tiles, not the bounding box.
\ Several decks are two clusters far apart (deck 0 especially) —
\ the midpoint of the extremes then falls in the gap between
\ them, showing nothing. The centroid is pulled toward whichever
\ cluster holds more of the map.
\
\ The quotient cannot exceed 63, so repeated subtraction costs
\ at most 64 iterations; this runs once per deck change.
\ ============================================================
.CentreOnDeck
  LDA #0
  STA sumColLo : STA sumColHi
  STA sumRowLo : STA sumRowHi
  STA cntLo    : STA cntHi
  STA cdRow

  LDA #LO(tilemap) : STA mapptr
  LDA #HI(tilemap) : STA mapptr+1

.cd_row
  LDY #0
.cd_col
  LDA (mapptr),Y
  BEQ cd_next

  INC cntLo                     \ count++
  BNE cd_c1
  INC cntHi
.cd_c1
  TYA                           \ sumCol += column
  CLC
  ADC sumColLo
  STA sumColLo
  BCC cd_c2
  INC sumColHi
.cd_c2
  LDA cdRow                     \ sumRow += row
  CLC
  ADC sumRowLo
  STA sumRowLo
  BCC cd_next
  INC sumRowHi

.cd_next
  INY
  CPY #MAP_COLS
  BNE cd_col

  ADDPTR mapptr, MAP_COLS
  INC cdRow
  LDA cdRow
  CMP #MAP_ROWS
  BNE cd_row

  LDA cntLo                     \ empty deck: park at the origin
  ORA cntHi
  BNE cd_have
  LDA #0
  STA charX
  STA charY
  RTS

.cd_have
  LDA sumColLo : STA dvLo       \ charX = avgCol*4 + 2 - 20
  LDA sumColHi : STA dvHi
  JSR divide
  LDA quot
  ASL A : ASL A
  CLC
  ADC #2
  SEC
  SBC #SCR_COLS/2
  BCS cd_xpos
  LDA #0                        \ clamped left
.cd_xpos
  CMP #MAX_X+1
  BCC cd_xset
  LDA #MAX_X                    \ clamped right
.cd_xset
  STA charX

  LDA sumRowLo : STA dvLo       \ charY = avgRow*4 + 2 - 12
  LDA sumRowHi : STA dvHi
  JSR divide
  LDA quot
  ASL A : ASL A
  CLC
  ADC #2
  SEC
  SBC #SCR_ROWS/2
  BCS cd_ypos
  LDA #0
.cd_ypos
  CMP #MAX_Y+1
  BCC cd_yset
  LDA #MAX_Y
.cd_yset
  STA charY
  RTS

\ ============================================================
\ divide — quot = (dvHi:dvLo) / (cntHi:cntLo), by subtraction
\ Destroys the dividend. Quotient is small here (<= 63).
\ ============================================================
.divide
  LDA #0
  STA quot
.dv_loop
  LDA dvHi                      \ dividend < divisor?
  CMP cntHi
  BCC dv_done
  BNE dv_sub
  LDA dvLo
  CMP cntLo
  BCC dv_done
.dv_sub
  SEC
  LDA dvLo : SBC cntLo : STA dvLo
  LDA dvHi : SBC cntHi : STA dvHi
  INC quot
  JMP dv_loop
.dv_done
  RTS

\ ============================================================
\ keydown — is a key held?
\   X = negative INKEY code as an unsigned byte
\   Returns Z set if the key is down.
\ ============================================================
.keydown
  LDA #&81
  LDY #&FF
  JSR OSBYTE
  CPY #&FF
  RTS

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
\ DrawScreen — render the viewport at (charX, charY)
\
\ For each character cell, where mapX = charX+cx, mapY = charY+cy:
\   tile      = tilemap[(mapY>>2)*64 + (mapX>>2)]
\   character = tiledefs[tile*16 + (mapY AND 3)*4 + (mapX AND 3)]
\
\ tilemap is page aligned and 1K, so the row base is cheap:
\   lo = (tileRow AND 3) << 6,  hi = HI(tilemap) + (tileRow >> 2)
\ ============================================================
.DrawScreen
  LDA #LO(SCREEN) : STA rowscr
  LDA #HI(SCREEN) : STA rowscr+1
  LDA charY       : STA mapY
  LDA #0          : STA cy

.ds_row
  LDA mapY                      \ subbase = (mapY AND 3) * 4
  AND #3
  ASL A : ASL A
  STA subbase

  LDA mapY                      \ tileRow = mapY >> 2
  LSR A : LSR A
  STA tileRow

  AND #3                        \ maprow = tilemap + tileRow*64
  ASL A : ASL A : ASL A : ASL A : ASL A : ASL A
  STA maprow
  LDA tileRow
  LSR A : LSR A
  CLC : ADC #HI(tilemap)
  STA maprow+1

  LDA charX                     \ tilecol = charX >> 2
  LSR A : LSR A
  STA tilecol
  LDA charX                     \ subcol = charX AND 3
  AND #3
  STA subcol

  LDA rowscr   : STA scr
  LDA rowscr+1 : STA scr+1
  LDA #0       : STA cx

.ds_col
  LDY tilecol                   \ tile = maprow[tilecol]
  LDA (maprow),Y

  PHA                           \ tdp = tiledefs + tile*16
  AND #&0F
  ASL A : ASL A : ASL A : ASL A
  STA tdp
  PLA
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #HI(tiledefs)
  STA tdp+1

  LDA subbase                   \ character within the tile
  CLC
  ADC subcol
  TAY
  LDA (tdp),Y
  JSR plot_char

  ADDPTR scr, CHAR_BYTES
  INC subcol                    \ every 4 characters, step a tile
  LDA subcol
  CMP #4
  BNE ds_nextcol
  LDA #0
  STA subcol
  INC tilecol
.ds_nextcol
  INC cx
  LDA cx
  CMP #SCR_COLS
  BNE ds_col

  ADDPTR rowscr, ROW_BYTES
  INC mapY
  INC cy
  LDA cy
  CMP #SCR_ROWS
  BEQ ds_done
  JMP ds_row
.ds_done
  RTS

\ ============================================================
\ plot_char — copy one 16-byte character to the screen
\   A = character code, scr = destination (preserved)
\ ============================================================
.plot_char
  TAX                           \ only characters the tiles use are
  LDA charRemap,X               \ converted, so map the code to an index
  PHA                           \ chp = charset + index*16
  AND #&0F
  ASL A : ASL A : ASL A : ASL A
  STA chp
  PLA
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #HI(charset)
  STA chp+1

  LDY #CHAR_BYTES-1
.pc_copy
  LDA (chp),Y
  STA (scr),Y
  DEY
  BPL pc_copy
  RTS

\ ---- BuildCharset working storage ---------------------------
\ Rebuilt once per deck change, so absolute addressing is fine.
.LUTs      SKIP 128             \ 4 hires + 4 multicolour nibble tables
.bcDeck    EQUB 0
.bcRecOfs  EQUB 0               \ scheme record offset (scheme * 12)
.bcCmapBase EQUB 0              \ deck * 16, base into colourMap
.bcBg      EQUB 0               \ logical colour of the background
.bcD022L   EQUB 0
.bcD023L   EQUB 0
.bcColour  EQUB 0               \ this character's C64 cell colour
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

\ ---- CentreOnDeck working storage ---------------------------
\ Zero page &70-&8C is full. These are touched once per deck
\ change, so absolute addressing costs nothing that matters.
.sumColLo EQUB 0
.sumColHi EQUB 0
.sumRowLo EQUB 0
.sumRowHi EQUB 0
.cntLo    EQUB 0
.cntHi    EQUB 0
.dvLo     EQUB 0
.dvHi     EQUB 0
.quot     EQUB 0
.cdRow    EQUB 0

.code_end

\ ---- tile map: 64 x 16, one byte per tile -------------------
\ Below &3000, so it survives the mode change. Built at runtime.
ALIGN &100
.tilemap
  SKIP MAP_COLS * MAP_ROWS
.tilemap_end

\ ---- MODE 1 charset, built at deck-load time ----------------
\ Page aligned so plot_char can index it with shifts. Only the
\ characters the tiles reference are converted, so this is
\ NUM_CHARS*16 rather than 4K. Sits below the loaded data.
ALIGN &100
.charset
  SKIP 137 * CHAR_BYTES         \ NUM_CHARS, defined in chardata.asm
.charset_end

\ ============================================================
\ Generated data — loaded separately, after the mode change
\ ============================================================
ORG &2600
.data_start
INCLUDE "src/data/chardata.asm"
INCLUDE "src/data/colours.asm"
INCLUDE "src/data/tiledefs.asm"
INCLUDE "src/data/levels.asm"
.data_end

ASSERT charset_end - charset == NUM_CHARS * CHAR_BYTES

PRINT "code    ", ~start, "-", ~code_end
PRINT "tilemap ", ~tilemap, "-", ~tilemap_end
PRINT "data    ", ~data_start, "-", ~data_end
PRINT "charset ", ~charset, "-", ~charset_end, " (", NUM_CHARS, " chars)"

SAVE "PARA",    start,      code_end, start
SAVE "PARADAT", data_start, data_end
