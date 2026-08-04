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

\ ---- logical colour 1 -> cyan ------------------------------
  LDA #19 : JSR OSWRCH
  LDA #1  : JSR OSWRCH
  LDA #6  : JSR OSWRCH
  LDA #0  : JSR OSWRCH
  LDA #0  : JSR OSWRCH
  LDA #0  : JSR OSWRCH

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

\ ============================================================
\ LoadDeck — decode the current deck and redraw from the origin
\ ============================================================
.LoadDeck
  LDA deck
  JSR BuildLevel
  JSR CentreOnDeck
  JSR DrawScreen
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
  PHA                           \ chp = charset + A*16
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

\ ============================================================
\ Generated data — loaded separately, after the mode change
\ ============================================================
ORG &2000
.data_start
INCLUDE "src/data/charset.asm"
INCLUDE "src/data/tiledefs.asm"
INCLUDE "src/data/levels.asm"
.data_end

PRINT "code    ", ~start, "-", ~code_end
PRINT "tilemap ", ~tilemap, "-", ~tilemap_end
PRINT "data    ", ~data_start, "-", ~data_end

SAVE "PARA",    start,      code_end, start
SAVE "PARADAT", data_start, data_end
