\ ============================================================
\ Paradroid — BBC Model B port
\ LAYER 0: toolchain + custom MODE 1 screen geometry
\ ============================================================
\ Goal: boot to a 320x200 MODE 1 display based at &4000 using a
\ 16K screen wrap, and prove the geometry with a test pattern.
\
\ MODE 1 is normally 320x256 at &3000 (20K). We display 25 char
\ rows instead of 32 and rebase to &4000, giving 320x200 in
\ &4000-&7E7F (16000 bytes) and handing back &3000-&3FFF.
\
\ CRTC start address is in 8-byte units (physical = MA*8 + RA),
\ so screen base &4000 -> R12/R13 = &4000/8 = &0800.
\ ============================================================

CPU 0                           \ plain 6502 — Model B

OSWRCH    = &FFEE
CRTC_ADDR = &FE00
CRTC_DATA = &FE01

SCREEN    = &4000
SCR_BYTES = 16000               \ 25 rows x 640

ptr       = &70                 \ free user zero page
count     = &72

MACRO CRTC reg, val
  LDA #reg : STA CRTC_ADDR : LDA #val : STA CRTC_DATA
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

\ ---- reprogram CRTC for 320x200 based at &4000 -------------
  CRTC 6,  25                   \ vertical displayed = 25 rows (200 lines)
  CRTC 7,  31                   \ vsync position — nudged up to re-centre
  CRTC 12, &08                  \ start address high  (&0800 = &4000/8)
  CRTC 13, &00                  \ start address low

\ ---- fill the whole 16000 bytes with colour 1 --------------
\ If the geometry is right this is a solid rectangle with no
\ black bands (short) and no wrapped garbage (long).
  LDA #LO(SCREEN) : STA ptr
  LDA #HI(SCREEN) : STA ptr+1
  LDA #62         : STA count   \ 62 whole pages
  LDY #0
  LDA #&0F                      \ MODE 1 solid colour 1
.fillpage
  STA (ptr),Y
  INY
  BNE fillpage
  INC ptr+1
  DEC count
  BNE fillpage
.filltail                       \ + 128 bytes = 16000
  STA (ptr),Y
  INY
  CPY #128
  BNE filltail

\ ---- 1-pixel border in colour 3 ----------------------------
\ Proves the char-row-major address formula:
\   addr = SCREEN + (y DIV 8)*640 + (x DIV 4)*8 + (y MOD 8)

\ top edge: y=0  -> SCREEN + col*8
  LDA #LO(SCREEN) : STA ptr
  LDA #HI(SCREEN) : STA ptr+1
  JSR hline

\ bottom edge: y=199 -> SCREEN + 24*640 + col*8 + 7
  LDA #LO(SCREEN + 24*640 + 7) : STA ptr
  LDA #HI(SCREEN + 24*640 + 7) : STA ptr+1
  JSR hline

\ left edge: byte 0 of every scanline, leftmost pixel
  LDA #LO(SCREEN) : STA ptr
  LDA #HI(SCREEN) : STA ptr+1
  LDA #&88                      \ pixel 0 of the byte, colour 3
  JSR vline

\ right edge: byte 79 of every scanline, rightmost pixel
  LDA #LO(SCREEN + 79*8) : STA ptr
  LDA #HI(SCREEN + 79*8) : STA ptr+1
  LDA #&11                      \ pixel 3 of the byte, colour 3
  JSR vline

.halt
  JMP halt

\ ---- draw a vertical line down all 200 scanlines -----------
\ ptr = first byte, A = pixel pattern. Steps 1 per scanline
\ within a char row, then 640 to the next char row.
.vline
  STA pixel+1
  LDX #25                       \ 25 char rows
.vrow
  LDY #0
.vscan
.pixel
  LDA #0                        \ operand patched above
  STA (ptr),Y
  INY
  CPY #8
  BNE vscan
  CLC                           \ next char row
  LDA ptr   : ADC #LO(640) : STA ptr
  LDA ptr+1 : ADC #HI(640) : STA ptr+1
  DEX
  BNE vrow
  RTS

\ ---- draw a horizontal line of 80 bytes at ptr -------------
\ ptr points at the first byte; bytes are 8 apart.
.hline
  LDY #0
  LDX #80
.hl1
  LDA #&FF
  STA (ptr),Y
  TYA
  CLC
  ADC #8
  TAY
  BCC hl2
  INC ptr+1                     \ Y wrapped past 255 — carry into high byte
.hl2
  DEX
  BNE hl1
  RTS

.end

SAVE "PARA", start, end, start
