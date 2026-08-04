\ ============================================================
\ Paradroid — BBC Model B port
\ LAYER 3b: CRTC hardware scrolling with edge redraw
\ ============================================================
\ Z / X       scroll left / right   (4 px, one CRTC unit)
\ K / M       scroll up / down      (8 px, one character row)
\ UP / DOWN   previous / next deck
\
\ Play area 320 x 128 px = 10 x 4 tiles, in a 10K circular
\ buffer at &5800. See screen.asm for the addressing scheme.
\ ============================================================

CPU 0                           \ plain 6502 — Model B

OSWRCH    = &FFEE
OSBYTE    = &FFF4
OSCLI     = &FFF7
CRTC_ADDR     = &FE00
CRTC_DATA     = &FE01
VIDEO_ULA_PAL = &FE21           \ palette register, write only
SYS_VIA_IFR   = &FE4D
IRQ1V         = &0204

CHAR_BYTES = 16                 \ a character is 16 bytes: two 8-byte halves

MAP_COLS   = 64                 \ tile map is 64 x 16 tiles
MAP_ROWS   = 16
MAP_CHAR_W = MAP_COLS * 4       \ 256 characters across
MAP_CHAR_H = MAP_ROWS * 4       \ 64 character rows

VIEW_CHARS = 40                 \ 320 px / 8
MAX_HX     = (MAP_CHAR_W - VIEW_CHARS) * 2      \ 432 half-characters
MAX_Y      = MAP_CHAR_H - 16                    \ 48 rows
NUM_DECKS  = 16

\ Shared C64 play-area colours; only the low nibble of each $D02x
\ is used. These index the per-deck colourMap.
D021_COLOUR = 14                \ background — the floor       [assumed]
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

\ ---- zero page (user area &70-&8F, all 32 bytes used) ------
bufp     = &70                  \ buffer write pointer      (2)
chp      = &72                  \ charset source            (2)
tdp      = &74                  \ tile definition source    (2)
src      = &76                  \ RLE read pointer          (2)
mapptr   = &78                  \ tile map write pointer    (2)
rptTile  = &7A                  \ tile being repeated
rptLen   = &7B                  \ repeat count
maprow   = &7C                  \ tile map row base         (2)
scrollS  = &7E                  \ CRTC start, 0..BUF_SIZE-1 (2)
mapHX    = &80                  \ viewport X, half-chars    (2)
halfX    = &82                  \ working X, half-chars     (2)
cellX    = &84                  \ working X, characters     (2)
mapYr    = &86                  \ viewport Y, character rows
cellY    = &87                  \ working Y, character rows
halfSel  = &88                  \ 0 = left half, 1 = right
uCount   = &89
rCount   = &8A
deck     = &8B
dirty    = &8C
prevUp   = &8D
prevDn   = &8E
mcTmp    = &8F

\ BuildCharset borrows zero page from routines that have finished.
bcSrc    = src
bcDst    = mapptr
bcDst2   = tdp

MACRO CRTC reg, val
  LDA #reg : STA CRTC_ADDR : LDA #val : STA CRTC_DATA
ENDMACRO

MACRO ADDPTR ptr, val
  CLC
  LDA ptr   : ADC #LO(val) : STA ptr
  LDA ptr+1 : ADC #HI(val) : STA ptr+1
ENDMACRO

\ DFS reserves &1100-&18FF for random-access file buffers, which
\ simple *LOAD / OSFILE loads never touch. So we start at &1100.
ORG &1100
.start

  JSR SetupScreen
  JSR InstallIrq

  LDX #LO(loadcmd)              \ must follow the mode change: VDU 22
  LDY #HI(loadcmd)              \ clears what the OS thinks is its screen
  JSR OSCLI

  LDA #1 : STA deck
  LDA #0
  STA prevUp
  STA prevDn
  STA rowOfs
  STA rowOfs+1
  JSR LoadDeck

\ ============================================================
\ Main loop
\ ============================================================
.mainloop
  \ Sync to vsync before touching the CRTC. R12/R13 form a 14-bit
  \ value across two writes: if the chip samples between them the
  \ display shows one frame at a half-updated address. Doing the
  \ writes and the edge redraw in the blanking window avoids that,
  \ and paces scrolling to one step per frame.
  JSR WaitVSync

  LDX #KEY_Z                    \ scroll left, 4 px
  JSR keydown
  BNE ml_notZ
  JSR ScrollLeft
.ml_notZ

  LDX #KEY_X                    \ scroll right, 4 px
  JSR keydown
  BNE ml_notX
  JSR ScrollRight
.ml_notX

  LDX #KEY_K                    \ scroll up, 8 px
  JSR keydown
  BNE ml_notK
  JSR ScrollUp
.ml_notK

  LDX #KEY_M                    \ scroll down, 8 px
  JSR keydown
  BNE ml_notM
  JSR ScrollDown
.ml_notM

  \ Deck keys are edge triggered: one press steps one deck however
  \ long it is held. A blocking wait-for-release deadlocks if the
  \ other deck key goes down before the first is released.
  LDX #KEY_UP
  JSR keydown
  BNE ml_upOff
  LDA prevUp
  BNE ml_notUp
  LDA #1 : STA prevUp
  LDA deck
  BEQ ml_notUp
  DEC deck
  JSR LoadDeck
  JMP ml_notUp
.ml_upOff
  LDA #0 : STA prevUp
.ml_notUp

  LDX #KEY_DOWN
  JSR keydown
  BNE ml_dnOff
  LDA prevDn
  BNE ml_notDn
  LDA #1 : STA prevDn
  LDA deck
  CMP #NUM_DECKS-1
  BCS ml_notDn
  INC deck
  JSR LoadDeck
  JMP ml_notDn
.ml_dnOff
  LDA #0 : STA prevDn
.ml_notDn

  JMP mainloop

.loadcmd
  EQUS "LOAD PARADAT"
  EQUB 13

\ ============================================================
\ keydown — is a key held?  X = negative INKEY code, Z set if down
\ ============================================================
.keydown
  LDA #&81
  LDY #&FF
  JSR OSBYTE
  CPY #&FF
  RTS

\ ============================================================
\ WaitVSync — block until the next field starts
\
\ Polling the System VIA IFR directly races the MOS: its own IRQ
\ handler services vsync and clears the flag, so the poll can miss
\ it. Instead we sit in front of IRQ1V, count fields, and chain on
\ to the OS so its timers and keyboard scan keep working.
\ ============================================================
.WaitVSync
  LDA vsyncCount
.wv_loop
  CMP vsyncCount
  BEQ wv_loop
  RTS

\ ============================================================
\ IrqHandler — front of the IRQ1V chain
\ The MOS saves the interrupted A in &FC before dispatching, so A
\ is free here as long as it is restored before chaining on.
\ ============================================================
.IrqHandler
  LDA SYS_VIA_IFR
  AND #2                        \ CA1 — vsync
  BEQ ih_chain
  INC vsyncCount
.ih_chain
  LDA &FC                       \ restore the interrupted accumulator
  JMP (oldIrq1V)

\ ============================================================
\ InstallIrq — put IrqHandler at the head of IRQ1V
\ ============================================================
.InstallIrq
  SEI
  LDA IRQ1V   : STA oldIrq1V
  LDA IRQ1V+1 : STA oldIrq1V+1
  LDA #LO(IrqHandler) : STA IRQ1V
  LDA #HI(IrqHandler) : STA IRQ1V+1
  CLI
  RTS

\ ============================================================
\ LoadDeck — decode a deck, build its charset, frame and draw it
\ ============================================================
.LoadDeck
  LDA deck
  JSR BuildCharset              \ charset is deck specific
  JSR SetPalette
  LDA deck
  JSR BuildLevel
  JSR CentreOnDeck
  LDA #0                        \ start the strip at the buffer base
  STA scrollS
  STA scrollS+1
  JSR SetCRTCStart
  JSR RedrawAll
  RTS

INCLUDE "src/screen.asm"
INCLUDE "src/scroll.asm"
INCLUDE "src/level.asm"

\ ---- absolute working storage ------------------------------
.rowOfs    EQUW 0               \ row*640 accumulator for RedrawAll
.sTmp      EQUW 0
.vsyncCount EQUB 0              \ bumped by IrqHandler once per field
.oldIrq1V  EQUW 0

.code_end

\ ---- tile map: 64 x 16, one byte per tile -------------------
ALIGN &100
.tilemap
  SKIP MAP_COLS * MAP_ROWS
.tilemap_end

\ ---- MODE 1 charset, built at deck-load time ----------------
ALIGN &100
.charset
  SKIP 137 * CHAR_BYTES         \ NUM_CHARS, defined in chardata.asm
.charset_end

\ ============================================================
\ Generated data — loaded separately, after the mode change
\ ============================================================
\ &3000-&57FF is free: the OS thinks the screen is &3000-&7FFF, but
\ we have repointed the CRTC at a 10K window starting &5800, so only
\ &5800-&7FFF is ever fetched for display.
ORG &3000
.data_start
INCLUDE "src/data/chardata.asm"
INCLUDE "src/data/colours.asm"
INCLUDE "src/data/tiledefs.asm"
INCLUDE "src/data/levels.asm"
.data_end

ASSERT charset_end - charset == NUM_CHARS * CHAR_BYTES

PRINT "code    ", ~start, "-", ~code_end
PRINT "tilemap ", ~tilemap, "-", ~tilemap_end
PRINT "charset ", ~charset, "-", ~charset_end
PRINT "data    ", ~data_start, "-", ~data_end

SAVE "PARA",    start,      code_end, start
SAVE "PARADAT", data_start, data_end
