\ ============================================================
\ Paradroid — BBC Model B port
\ LAYER 1: graphics data pipeline
\ ============================================================
\ Renders all 32 tile definitions as an 8x4 sheet, to verify:
\   - the C64 -> MODE 1 charset conversion
\   - the tile definition data
\   - the character plotter Layer 2 will build on
\
\ Compare the result against tools/output/tiles.png.
\ ============================================================

CPU 0                           \ plain 6502 — Model B

OSWRCH    = &FFEE
CRTC_ADDR = &FE00
CRTC_DATA = &FE01

SCREEN    = &4000
SCR_BYTES = 16000               \ 25 rows x 640

\ Character cell = 16 contiguous bytes (left 4px x 8 rows, then right 4px x 8)
CHAR_BYTES = 16
ROW_BYTES  = 640                \ one character row
TILE_BYTES = 4 * CHAR_BYTES     \ a tile is 4 chars wide
TILE_ROW   = 4 * ROW_BYTES      \ a tile is 4 chars tall

\ Sheet origin: character column 4, character row 3
SHEET = SCREEN + 3*ROW_BYTES + 4*CHAR_BYTES

\ ---- zero page (user area &70-&8F) -------------------------
scr     = &70                   \ screen destination      (2)
chp     = &72                   \ charset source          (2)
tdp     = &74                   \ tile definition source  (2)
tdi     = &76                   \ index within tile def, 0-15
tnum    = &77                   \ tile number being drawn
colcnt  = &78                   \ draw_tile inner column counter
rowscr  = &79                   \ draw_tile row origin    (2)
tileorg = &7B                   \ sheet row origin        (2)
tilecur = &7D                   \ current tile position   (2)
sheetcol= &7F                   \ sheet column counter
sheetrow= &80                   \ sheet row counter

MACRO CRTC reg, val
  LDA #reg : STA CRTC_ADDR : LDA #val : STA CRTC_DATA
ENDMACRO

\ Add a 16-bit constant to a zero page pointer
MACRO ADDPTR ptr, val
  CLC
  LDA ptr   : ADC #LO(val) : STA ptr
  LDA ptr+1 : ADC #HI(val) : STA ptr+1
ENDMACRO

ORG &1900
.start

\ ---- select MODE 1 -----------------------------------------
  LDA #22 : JSR OSWRCH
  LDA #1  : JSR OSWRCH

\ ---- cursor off: VDU 23,1,0;0;0;0; -------------------------
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
\ The charset stores its foreground as logical colour 1, so a deck's
\ colour scheme is just a palette change — as the C64 did via CharColor.
  LDA #19 : JSR OSWRCH
  LDA #1  : JSR OSWRCH          \ logical colour 1
  LDA #6  : JSR OSWRCH          \ physical cyan
  LDA #0  : JSR OSWRCH
  LDA #0  : JSR OSWRCH
  LDA #0  : JSR OSWRCH

\ ---- reprogram CRTC for 320x200 based at &4000 -------------
\ CRTC start address is the screen address / 8, so &4000 -> &0800.
  CRTC 6,  25                   \ vertical displayed = 25 rows (200 lines)
  CRTC 7,  31                   \ vsync position
  CRTC 12, &08                  \ start address high
  CRTC 13, &00                  \ start address low

\ ---- clear the screen --------------------------------------
  LDA #LO(SCREEN) : STA scr
  LDA #HI(SCREEN) : STA scr+1
  LDX #62                       \ 62 whole pages
  LDY #0
  LDA #0
.clrpage
  STA (scr),Y
  INY
  BNE clrpage
  INC scr+1
  DEX
  BNE clrpage
.clrtail                        \ + 128 = 16000 bytes
  STA (scr),Y
  INY
  CPY #128
  BNE clrtail

\ ---- draw the 32 tiles as an 8 x 4 sheet -------------------
  LDA #LO(SHEET) : STA tileorg
  LDA #HI(SHEET) : STA tileorg+1
  LDA #0         : STA tnum
  LDA #4         : STA sheetrow
.sheet_row
  LDA tileorg   : STA tilecur
  LDA tileorg+1 : STA tilecur+1
  LDA #8        : STA sheetcol
.sheet_col
  LDA tilecur   : STA scr
  LDA tilecur+1 : STA scr+1
  JSR draw_tile
  INC tnum
  ADDPTR tilecur, TILE_BYTES
  DEC sheetcol
  BNE sheet_col
  ADDPTR tileorg, TILE_ROW
  DEC sheetrow
  BNE sheet_row

.halt
  JMP halt

\ ============================================================
\ draw_tile — plot one 4x4 character tile
\   tnum = tile number (0-31), scr = top-left screen address
\ ============================================================
.draw_tile
  \ tdp = tiledefs + tnum*16   (tiledefs is page aligned)
  LDA tnum
  AND #&0F
  ASL A : ASL A : ASL A : ASL A
  STA tdp
  LDA tnum
  LSR A : LSR A : LSR A : LSR A
  CLC : ADC #HI(tiledefs)
  STA tdp+1

  LDA scr   : STA rowscr
  LDA scr+1 : STA rowscr+1
  LDA #0    : STA tdi
  LDX #4                        \ 4 character rows
.dt_row
  LDA rowscr   : STA scr
  LDA rowscr+1 : STA scr+1
  LDA #4       : STA colcnt
.dt_col
  LDY tdi
  LDA (tdp),Y
  JSR plot_char
  INC tdi
  ADDPTR scr, CHAR_BYTES
  DEC colcnt
  BNE dt_col
  ADDPTR rowscr, ROW_BYTES
  DEX
  BNE dt_row
  RTS

\ ============================================================
\ plot_char — copy one 16-byte character to the screen
\   A = character code, scr = destination (preserved)
\ ============================================================
.plot_char
  \ chp = charset + A*16   (charset is page aligned)
  PHA
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

\ ============================================================
\ Generated data
\ ============================================================
INCLUDE "src/data/charset.asm"
INCLUDE "src/data/tiledefs.asm"

.end

SAVE "PARA", start, end, start
