\ ============================================================
\ Paradroid â€” BBC Model B port
\ LAYER 2: static deck render
\ ============================================================
\ Ports BuildLevel (RLE -> tile map) and renders a viewport of
\ the decoded deck.
\
\ Divergence from the C64: the original expands each tile into a
\ 256x64 character map at $8000 (16K). We keep only the 64x16
\ tile map (1K) and expand tiles to characters at draw time â€”
\ two extra lookups per character against a ~100 cycle 16-byte
\ copy, for a 15K saving we cannot do without on a Model B.
\ ============================================================

CPU 0                           \ plain 6502 â€” Model B

OSWRCH    = &FFEE
OSCLI     = &FFF7
CRTC_ADDR = &FE00
CRTC_DATA = &FE01

SCREEN    = &4000

CHAR_BYTES = 16                 \ a character is 16 contiguous bytes
ROW_BYTES  = 640                \ one character row
SCR_COLS   = 40                 \ characters across
SCR_ROWS   = 25                 \ character rows

MAP_COLS   = 64                 \ tile map is 64 x 16
MAP_ROWS   = 16

DECK       = 1                  \ deck to render

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
subcol   = &83                  \ character column within the tile, 0-3
subbase  = &84                  \ (cy AND 3) * 4

MACRO CRTC reg, val
  LDA #reg : STA CRTC_ADDR : LDA #val : STA CRTC_DATA
ENDMACRO

MACRO ADDPTR ptr, val
  CLC
  LDA ptr   : ADC #LO(val) : STA ptr
  LDA ptr+1 : ADC #HI(val) : STA ptr+1
ENDMACRO

ORG &1900
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

\ ---- logical colour 1 -> cyan (deck 1's scheme) ------------
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

\ ---- clear the screen --------------------------------------
  LDA #LO(SCREEN) : STA scr
  LDA #HI(SCREEN) : STA scr+1
  LDX #62
  LDY #0
  LDA #0
.clrpage
  STA (scr),Y
  INY
  BNE clrpage
  INC scr+1
  DEX
  BNE clrpage
.clrtail
  STA (scr),Y
  INY
  CPY #128
  BNE clrtail

\ ---- load the data file ------------------------------------
\ This MUST happen after the mode change. VDU 22 makes the OS clear
\ what it still believes is its screen, &3000-&7FFF, so any data
\ living above &3000 at load time is wiped before we can read it.
\ Code and the tile map sit below &3000 and survive; the converted
\ graphics and level data are loaded separately, afterwards.
  LDX #LO(loadcmd)
  LDY #HI(loadcmd)
  JSR OSCLI

\ ---- build and draw ----------------------------------------
  LDA #DECK
  JSR BuildLevel
  JSR DrawScreen

.halt
  JMP halt

.loadcmd
  EQUS "LOAD PARADAT"
  EQUB 13

\ ============================================================
\ BuildLevel â€” RLE-decode a deck into the tile map
\   A = deck number (0-15)
\
\ RLE format, unchanged from the C64:
\   bit 7 clear -> one tile, index in bits 0-4
\   bit 7 set   -> tile index in bits 0-4, next byte is the count
\ Decoding stops when the map is full. A count of 0 means 256,
\ which falls out of decrementing after the store.
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
\ DrawScreen â€” render the top-left of the tile map to the screen
\
\ For each character cell:
\   tile      = tilemap[(cy>>2)*64 + (cx>>2)]
\   character = tiledefs[tile*16 + (cy AND 3)*4 + (cx AND 3)]
\ ============================================================
.DrawScreen
  LDA #LO(SCREEN)  : STA rowscr
  LDA #HI(SCREEN)  : STA rowscr+1
  LDA #LO(tilemap) : STA maprow
  LDA #HI(tilemap) : STA maprow+1
  LDA #0           : STA cy

.ds_row
  LDA cy                        \ subbase = (cy AND 3) * 4
  AND #3
  ASL A : ASL A
  STA subbase

  LDA rowscr   : STA scr
  LDA rowscr+1 : STA scr+1
  LDA #0 : STA tilecol
  LDA #0 : STA subcol
  LDA #0 : STA cx

.ds_col
  LDY tilecol                   \ tile = maprow[tilecol]
  LDA (maprow),Y

  \ tdp = tiledefs + tile*16   (tiledefs is page aligned)
  PHA
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
  INC cy
  LDA cy
  AND #3                        \ every 4 character rows, step a map row
  BNE ds_samemap
  ADDPTR maprow, MAP_COLS
.ds_samemap
  LDA cy
  CMP #SCR_ROWS
  BEQ ds_done
  JMP ds_row
.ds_done
  RTS

\ ============================================================
\ plot_char â€” copy one 16-byte character to the screen
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

.code_end

\ ---- tile map: 64 x 16, one byte per tile -------------------
\ Below &3000, so it survives the mode change. Built at runtime,
\ so it is reserved rather than saved.
ORG &1C00
.tilemap
  SKIP MAP_COLS * MAP_ROWS
.tilemap_end

\ ============================================================
\ Generated data â€” loaded separately, after the mode change
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
PRINT "charset ", ~charset, " tiledefs ", ~tiledefs, " levels ", ~leveldata

SAVE "PARA",    start,      code_end, start
SAVE "PARADAT", data_start, data_end
