\ ============================================================
\ Paradroid — BBC Model B port
\ LAYER 4: the player droid — sprite, controls, collision
\ ============================================================
\ Z / X       move left / right
\ K / M       move up / down
\ UP / DOWN   previous / next deck
\ SPACE       force a full redraw (debug oracle)
\
\ Movement is the C64's own model: keys feed a direction, the
\ direction feeds an accelerating 8.8 speed. Walls stop it.
\ The camera has a DEAD ZONE. The C64 pins the player dead centre
\ because its hardware scroll is 1 pixel; ours is 4, and a rigid
\ camera makes the world lurch at low speed. So the player moves
\ through the world at 1 pixel and the view only follows once the
\ player leaves a window around the centre — see player.asm.
\
\ Play area 320 x 120 px, in a 10K circular buffer at &5800.
\ See screen.asm for the addressing scheme and scroll.asm for
\ how a pixel position turns into work.
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

\ ---- sideways RAM -------------------------------------------
\ ROMSEL selects which 16K bank appears at &8000-&BFFF. Only one is
\ visible at a time, so paging our RAM in displaces whatever ROM was
\ there — BASIC, usually. ROMSHAD is the MOS's own copy: the MOS
\ restores ROMSEL from it after a service call, so writing one
\ without the other leaves the two disagreeing and the next OS call
\ pages something unexpected back in. Always write both.
\
\ Measured in jsbeeb (B-DFS1.2): banks 0-7 are RAM, 8-15 ROM.
\
\ We use 4 and 5 rather than 0 and 1 because a Master 128's own
\ sideways RAM is banks 4-7, so the same numbers work on both
\ machines and the port stays Master-compatible for free. A Model B
\ SWRAM board is jumpered to whichever banks you like, so nothing is
\ lost by picking these.
\
\ Eventually this wants probing at boot rather than hard-coding —
\ write a byte, read it back, take the first bank that holds it —
\ but a fixed pair is fine while the machine is a known quantity.
ROMSEL     = &FE30
ROMSHAD    = &F4
SWRAM_DATA = 4                  \ bank holding PARADAT
SWRAM_CODE = 5                  \ reserved: paged code, Layers 9-11
SWRAM_BASE = &8000

CHAR_BYTES = 16                 \ a character is 16 bytes: two 8-byte halves

\ ---- frame lock ---------------------------------------------
\ TV fields per game-loop iteration. 2 gives a fixed 25 Hz, which is
\ the rate the C64's GameLoop actually runs at and the rate every
\ movement constant in player.asm is expressed in — see WaitVSync for
\ why this is locked rather than free-running.
\
\ Changing it changes how fast the game plays unless PLY_ITER_FRAMES
\ moves with it: player.asm scales the C64's per-iteration speeds by
\ FRAME_LOCK / PLY_ITER_FRAMES, so the two cancel at 2 and 2.
FRAME_LOCK = 2

MAP_COLS   = 64                 \ tile map is 64 x 16 tiles
MAP_ROWS   = 16
MAP_CHAR_W = MAP_COLS * 4       \ 256 characters across
MAP_CHAR_H = MAP_ROWS * 4       \ 64 character rows

\ ---- debug build options ------------------------------------
\ DEBUG_RASTER tints the background at entry to each rupture
\ interrupt, so the scanline each one lands on is visible:
\   magenta  from the VSync IRQ
\   green    from fire 1 (panel cycle setup)
\   normal   from fire 2 (play cycle setup)
\   blue     from fire 3 (play area off-display)
\ The boundaries between bands ARE the interrupt points. It also
\ SUPPRESSES the R8 blanking, since a blanked band shows black
\ whatever the palette says — which is exactly what is needed to
\ calibrate T1_TUNE, because fires 2 and 3 sit inside the regions
\ that blanking would otherwise hide.
DEBUG_RASTER = FALSE

\ DEBUG_DRAW tints the background for exactly as long as the main
\ loop spends on a piece of work, so the band shows which scanlines
\ that work occupies. It must all fit between the play area going
\ off-display (frame row 27) and being drawn again (row 8 of the
\ next frame) — if a band reaches into the play area, that work is
\ overrunning its window.
\
\ Two bands, because the sprites and the edge redraw are separate
\ budgets and the sprite pool is the one still being cut down:
\
\   magenta  SprRestoreAll, then SprAnimateAll + SprDrawAll. Two
\            bands, one either side of the redraw, because that is
\            genuinely where the sprite work happens — restore has
\            to precede any change to the scroll state, and the draw
\            has to follow the redraw so the save picks up settled
\            background. Restore is about a third of the sprite cost,
\            so leaving it untinted would flatter the total.
\   cyan     everything between: keys, movement, SetCRTCStart and
\            the edge redraw.
DEBUG_DRAW   = FALSE

\ TEST_DROIDS parks six static droids around the player at deck load,
\ so the sprite pool can be looked at and measured before droid.asm
\ exists. Scaffolding — see src/droidtest.asm.
TEST_DROIDS  = TRUE
TD_DECK      = 1                \ CentreOnDeck lands the player somewhere
                                \ walkable here; on some decks it does not,
                                \ see BUGS.md
DBG_SPR      = 5                \ magenta
DBG_REDRAW   = 6                \ cyan

\ ---- screen geometry ---------------------------------------
\ These live here rather than in screen.asm/rupture.asm because
\ beebasm resolves constant assignments in file order, and both
\ of those files need them.
BUF_BASE   = &5800              \ 10K play buffer, wraps at &8000
BUF_SIZE   = 10240              \ 16 rows x 640
BUF_END    = BUF_BASE + BUF_SIZE
PLAY_UNITS = 80                 \ CRTC units across (4 px each) = 320 px
PLAY_ROWS  = 16                 \ character rows = 128 px
UNIT_BYTES = 8
ROW_BYTES  = 640
VIA_PORTB  = &FE40

\ ---- vertical rupture: three CRTC cycles per frame ----------
\ Three, not two, so that smooth vertical scrolling can borrow
\ scanlines with R5 without the panel moving. R5 appends extra
\ scanlines to the END of a cycle, so with only two cycles the
\ variable adjust necessarily lands between VSync and the panel
\ and the panel slides up to 7 scanlines while scrolling. With a
\ third (tail) cycle carrying VSync, both variable adjusts sit
\ after the panel, where they cancel.
\
\ P = start of the panel cycle. Frame layout:
\
\   panel   P            7 rows,  5 displayed, R5 = 8-line
\   play    P+64-line   18 rows, 17 displayed, R5 = line
\   tail    P+208       13 rows,  0 displayed, R5 = 0, VSync at row 8
\                       ------
\                       38 rows x 8 + 8 adjust = 312 scanlines
\
\ Visible play area: P+64 to P+192, and VSync at P+272 — the same
\ geometry Layer 3c had, so nothing moves and no RAM changes.
PANEL_ADDR  = &4800             \ below &5800, clear of the play buffer
PANEL_ROWS  = 5                 \ rows of title
PANEL_BYTES = PANEL_ROWS * ROW_BYTES
PANEL_START = PANEL_ADDR / 8    \ what R12/R13 wants

PANEL_CYC_ROWS = 7
PLAY_CYC_ROWS  = 18
TAIL_CYC_ROWS  = 13
PANEL_R4 = PANEL_CYC_ROWS - 1   \ 6
PLAY_R4  = PLAY_CYC_ROWS - 1    \ 17
TAIL_R4  = TAIL_CYC_ROWS - 1    \ 12
TAIL_R7  = 8                    \ VSync at P+208+64 = P+272

\ 18 rows but only 16 displayed, so row 16 turns display off by
\ ordinary means. Displaying more would leave R6 > R4, where the
\ VADJ scanlines themselves are displayed — behaviour we would then
\ be depending on.
\
\ R6 CANNOT BE 17, and this is a hard limit rather than a choice.
\ The display window must fit inside ONE hardware wrap: the address
\ translator subtracts its mode amount once, when MA12 goes high
\ (IC 39), and does not iterate. 17 rows is 10880 bytes over a
\ 10240-byte wrap span, so at high scrollS the bottom rows need a
\ second subtract, do not get one, and fetch from &8000 upwards —
\ ROM. It shows as garbage across the bottom row, and only past
\ scrollS = 9608, which is why it looked intermittent.
\
\ The strip period must equal the wrap span, and 10240 bytes with
\ 80-unit rows is exactly 16 rows, so 16 is the ceiling. Smooth
\ vertical scrolling therefore costs one character row of play
\ area: 16 rows are displayed, 15 are visible, and the 16th carries
\ the sub-row fraction at both ends.
PLAY_R6       = PLAY_ROWS       \ 16 displayed — see above
PLAY_VIS_ROWS = PLAY_ROWS - 1   \ 15 visible = 120 px

ASSERT (PLAY_ROWS * PLAY_UNITS) * UNIT_BYTES <= BUF_SIZE

ASSERT PANEL_CYC_ROWS + PLAY_CYC_ROWS + TAIL_CYC_ROWS == 38

\ Screen blank via CRTC R8's display-skew bits: 3 = "non-display",
\ which gates the chip's own display enable rather than delaying it,
\ so the transition is clean mid-frame. Interlace bits stay 0.
R8_ON    = &00
R8_BLANK = &30

\ System VIA T1 in CONTINUOUS mode drives the rupture stages.
\
\ T2 was the wrong choice: it is one-shot only, so the interval
\ starts when the handler writes T2C-H and every interrupt's
\ service latency feeds straight into the next interval — jitter
\ accumulates. T1 continuous auto-reloads from its latch at
\ underflow, so the period is exact however late we are serviced.
\
\ Three fires per frame, at wildly different spacings, so the latch
\ is rewritten one fire ahead each time: T1 reloads its counter from
\ the latch at underflow, so a latch write takes effect one reload
\ later. T1 is restarted only at VSync, so all three fires in a
\ frame share ONE jitter offset instead of accumulating three.
\
\ Positions relative to P (start of the panel cycle), in scanlines:
\
\   fire 1  P+44   panel cycle regs, R5 = 8-line, blank, park play
\   fire 2  P+64   play cycle R4, unblank — the visible TOP edge
\   fire 3  P+184  play cycle R5, blank, release the main loop —
\                  the visible BOTTOM edge, 15 rows below the top
\
\ Fire 1's window is only [P+40, P+48]: it cannot blank before P+40
\ or it clips the panel, and it must write R4 = 6 before C4 reaches
\ 6 at P+48. Fires 2 and 3 must land inside horizontal blanking —
\ MODE 1 displays 80 of 128 character times, so ~24 us of the 64 us
\ line is available and a write in the displayed part cuts that
\ scanline part-way across.
\
\ VSync (P+272) -> fire 1 (P+312+44) is 84 scanlines.
SL = 64                         \ 1 scanline = 64 us = 64 T1 ticks
\ -4 scanlines: the VSync CA1 interrupt is serviced about 4 scanlines
\ after the vsync edge, so every fire needs shifting back by that.
\ Was -6, which put fire 2's unblank at P+62 instead of P+64 and so
\ exposed two scanlines of the NEXT map row above the top of the
\ view. Erring late is harmless — it just starts the view a couple
\ of scanlines further down the map — but erring early shows content
\ that belongs at the bottom of the window at the top of it.
\ -22 us: the sub-scanline phase. Measured with T1_PROBE below — the
\ R8 write was landing 9 us into the 40 us displayed part of the
\ scanline, which cuts that scanline part-way across. MODE 1 shows
\ 80 of 128 character times, so blanking is us 40-63; -22 us puts
\ fire 1's write at us 51, fire 2 at ~53 and fire 3 at ~55 (they
\ differ by the length of RuptTimer's dispatch). All three land in
\ horizontal blanking, so a whole scanline is either shown or not.
T1_TUNE = -4 * SL - 22

\ PHASE PROBE, normally 0. Set to 24 * SL to drag fire 1 back into
\ the panel's displayed rows, giving the time straight back to fire
\ 2 so fires 2 and 3 stay put and only the blank moves. The blank
\ then cuts the solid panel box, and the horizontal position of the
\ step IS the sub-scanline phase of every fire — read it off, adjust
\ T1_TUNE, and the step becomes a clean full-width line when the
\ write has moved into horizontal blanking.
\
\ This is the only way found to measure the phase. Screenshots of
\ the play area edges cannot show it: one scanline is 2 pixels in
\ the framebuffer, and the crop scales differently per build.
T1_PROBE = 0

T1_I1 = 84 * SL - 2 + T1_TUNE - T1_PROBE
T1_I2 = 20 * SL - 2 + T1_PROBE  \ fire 1 -> fire 2, P+44 -> P+64
T1_I3 = PLAY_VIS_ROWS * 8 * SL - 2   \ fire 2 -> fire 3, the visible height

SYS_VIA_T1CL = &FE44
SYS_VIA_T1CH = &FE45
SYS_VIA_T1LL = &FE46
SYS_VIA_T1LH = &FE47            \ latch only — does not reload the counter
SYS_VIA_ACR  = &FE4B
SYS_VIA_IER  = &FE4E
USR_VIA_IER  = &FE6E

\ ---- sprite scratch, above the panel and below the play buffer ----
\ &5480-&57FF is the ~900 bytes left over between the panel's last
\ row and the start of the 10K strip. Only the mask table lives here
\ now: it is a pure function of a byte, so building it at startup is
\ cheaper than shipping it. The 2 px shifted artwork used to be built
\ here too, but at 1743 bytes for 24 droid types it no longer fits —
\ it ships pre-shifted in sideways RAM instead. &5480-&56FF is free.
SPR_MASKTAB = &5700             \ data byte -> its transparency mask

\ The player is a droid like any other, in slot 0. Its screen Y never
\ changes: vertical scrolling is 1 scanline, so the C64's arrangement
\ survives here and the view carries the player rather than the other
\ way round. Only its X moved, because of the dead zone.
PLY_SLOT = 0
PLY_Y    = 50                   \ scanlines below the top of the view

\ There is no longer a shifted copy of the artwork. It used to be
\ built into spare bank RAM at startup and cost 1,743 bytes; both
\ shifts now exist as compiled code, and the stored rows are read
\ only by the wrap fallback, which shifts the few it needs on the
\ fly. Those 1,743 bytes are where the compiled digits live.

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
KEY_SPACE  = &9D                \ -99

\ ---- zero page ---------------------------------------------
\ &70-&8F was the original allocation and is full. With BASIC not
\ running and the MOS reduced to OSBYTE &81, the whole of &00-&8F
\ is ours, so the sprite blitter extends downwards from &68.
sprScan  = &64                  \ sprite's STARTING scanline in its char row;
                                \ the walk reads its position from bufp AND 7
swSrc    = &66                  \ sideways-RAM copy source  (2)
psrc     = &68                  \ sprite row, pixel data    (2)
swDst    = &6A                  \ sideways-RAM copy dest    (2)
sprRow   = &6C                  \ sprite row being blitted
\ &6D free
svp      = &6E                  \ sprite background save pointer (2)

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

  LDX #LO(loadcmd)              \ must follow the mode change: VDU 22
  LDY #HI(loadcmd)              \ clears what the OS thinks is its screen
  JSR OSCLI

  JSR PageDataIn                \ PARADAT lands at &3000 and is copied up
                                \ into SWRAM; the staging area is free after

  JSR FillPanel                 \ after the staging area is done with: it
                                \ reaches past &4800, over the panel

  JSR SprBuildMask              \ AFTER the mode change: VDU 22 clears
  JSR SprInit                   \ &3000-&7FFF, mask table included

  JSR InstallIrq                \ after the load: taking over the IRQ stops
                                \ the MOS servicing the filing system

IF TEST_DROIDS
  LDA #TD_DECK : STA deck
ELSE
  LDA #1 : STA deck
ENDIF
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
  \ Released once the play area is off-display, not at VSync. The
  \ edge redraw and the R12/R13 park both have to land before the
  \ play area is drawn again.
  JSR WaitVSync
IF DEBUG_DRAW
  LDA #DBG_SPR : JSR DbgSetBg   \ the restore is sprite time too, and it is
ENDIF                           \ a third of it — it gets the sprite colour
  JSR SprRestoreAll             \ before anything moves: the saved pixels
                                \ belong at the address they were taken from
IF DEBUG_DRAW
  LDA #DBG_REDRAW : JSR DbgSetBg
ENDIF

  \ Z / X left-right, K / M up-down. The keys feed a direction pair
  \ and the direction pair feeds an accelerating speed, so the view
  \ position moves by 0-7 pixels a frame rather than a fixed step.
  JSR ReadKeys
  JSR CalcSpeed
  JSR CheckWalls                \ before the move, as the C64 does: it
  JSR ApplyMove                 \ zeroes the speed the move would apply

  \ Park the CRTC address ONCE, with every axis accounted for, and
  \ before any drawing — the IRQ latches it at frame row 3, only a
  \ few rows into this window.
  JSR SetCRTCStart
  JSR DoRedraws

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

IF DEBUG_DRAW
  JSR DbgDeckBg                 \ back to the deck's real background
ENDIF

  LDX #KEY_SPACE                \ DEBUG: force a full redraw, to compare
  JSR keydown                   \ the incremental edge draws against it
  BNE ml_notSpc
  JSR RedrawAll
.ml_notSpc

IF DEBUG_DRAW
  LDA #DBG_SPR : JSR DbgSetBg   \ magenta over the sprite draw
ENDIF

IF TEST_DROIDS
  JSR TestDroidsUpdate          \ after the view has settled, before the draw
ENDIF
  JSR SprAnimateAll             \ last: the buffer is settled, so the save
  JSR SprDrawAll                \ picks up the background the frame will show

IF DEBUG_DRAW
  JSR DbgDeckBg
ENDIF

  JMP mainloop

.loadcmd
  EQUS "LOAD PARADAT"
  EQUB 13

\ ============================================================
\ PageDataIn — move PARADAT from &3000 into sideways RAM bank 0
\ ============================================================
\ PARADAT is assembled at &8000 but its catalogue load address is
\ DATA_LOAD, so *LOAD puts it in main RAM and this copies it up.
\ It cannot be loaded straight into the bank: while the filing
\ system is working, the MOS has the DFS ROM paged in at &8000, so
\ the bytes would land in the ROM socket and be discarded.
\
\ The data bank stays selected from here on. MapChar reads
\ `tiledefs` and DrawHalf reads `charRemap` every frame, so it
\ cannot be paged out during play. That displaces BASIC, which we
\ never return to, and not DFS, which lives in its own socket and
\ which the MOS pages in and back out around each of its own calls.
.PageDataIn
  LDA #SWRAM_DATA
  STA ROMSHAD                   \ both, always — see the note at the top
  STA ROMSEL

  LDA #LO(DATA_LOAD) : STA swSrc
  LDA #HI(DATA_LOAD) : STA swSrc+1
  LDA #LO(SWRAM_BASE): STA swDst
  LDA #HI(SWRAM_BASE): STA swDst+1
  LDX #DATA_PAGES
.pdi_page
  LDY #0
.pdi_byte
  LDA (swSrc),Y
  STA (swDst),Y
  INY
  BNE pdi_byte
  INC swSrc+1
  INC swDst+1
  DEX
  BNE pdi_page
  RTS

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
\ Waits until the play area has finished being displayed, not until
\ VSync — see rt_drawok. Everything the main loop does after this
\ (edge redraw, parking R12/R13) must land before the play area is
\ drawn again, so starting 7 rows earlier is 7 rows more headroom.
\
\ FRAME_LOCK fields are consumed per iteration, not one, so the loop
\ runs at a FIXED 25 Hz rather than free-running. That is the C64's
\ own cadence — its GameLoop iterates every 2-3 fields — and it is
\ what the movement constants have always been expressed in.
\
\ Free-running was the worse of the two. The loop does not fit in a
\ field once the sprite pool is full, so it quietly took 1.25 fields
\ an iteration and the player moved 20% slower with droids on screen
\ than without: the speed became a function of how much was visible.
\ Locking makes the cost of a droid show up as headroom spent rather
\ than as movement slowing down.
\
\ If an iteration overruns its two fields the flag is already set on
\ arrival, so it is consumed at once and the next boundary is one
\ field later. The rate degrades but never exceeds 25 Hz.
.WaitVSync
  LDX #FRAME_LOCK
.wv_field
  LDA drawFlag
  BEQ wv_field
  LDA #0
  STA drawFlag
  DEX
  BNE wv_field
  RTS

\ ============================================================
\ IrqHandler — front of the IRQ1V chain
\ The MOS saves the interrupted A in &FC before dispatching, so A
\ is free here as long as it is restored before chaining on.
\ ============================================================
\ We own IRQ1V outright — nothing is passed on to the MOS, so its
\ handler never adds latency ahead of ours. Cost: the MOS 100 Hz
\ tick stops, which takes its sound with it. Keyboard still works
\ (OSBYTE &81 scans the matrix directly) and the filing system is
\ only used before we take over.
\
\ The MOS saves the interrupted A in &FC before dispatching but
\ does NOT save X or Y, so we must.
.IrqHandler
  TXA : PHA
  TYA : PHA

  LDA SYS_VIA_IFR
  AND #&40                      \ T1 — the rupture stage timer
  BEQ ih_notT1
  LDA SYS_VIA_T1CL              \ acknowledge
  JSR RuptTimer
  JMP ih_done
.ih_notT1
  LDA SYS_VIA_IFR
  AND #2                        \ CA1 — vsync
  BEQ ih_done
  LDA #2
  STA SYS_VIA_IFR               \ acknowledge
  INC vsyncCount
  JSR RuptVSync

.ih_done
  PLA : TAY
  PLA : TAX
  LDA &FC                       \ restore the interrupted accumulator
  RTI


\ ============================================================
\ InstallIrq — put IrqHandler at the head of IRQ1V
\ ============================================================
.InstallIrq
  SEI
  LDA #&7F : STA SYS_VIA_IER    \ silence every interrupt source on both
  LDA #&7F : STA USR_VIA_IER    \ VIAs — anything we do not service would
                                \ hold the IRQ line asserted forever
  LDA IRQ1V   : STA oldIrq1V
  LDA IRQ1V+1 : STA oldIrq1V+1
  LDA #LO(IrqHandler) : STA IRQ1V
  LDA #HI(IrqHandler) : STA IRQ1V+1

  LDA SYS_VIA_ACR               \ T1 continuous, no PB7 output
  AND #&3F
  ORA #&40
  STA SYS_VIA_ACR

  LDA #&7F : STA SYS_VIA_IFR    \ clear anything pending
  LDA #&C2 : STA SYS_VIA_IER    \ enable CA1 (vsync) + T1
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
  JSR SetPosFromMap             \ the pixel position is the authority from
                                \ here on; CentreOnDeck works in characters
  LDA #0                        \ start the strip at the buffer base,
  STA scrollS                   \ on a character row boundary — RedrawAll
  STA scrollS+1                 \ writes whole rows, so buffer row 0 must
  STA line                      \ not be a split row
  STA iline
  LDX #SPR_SLOTS-1              \ the saved backgrounds belong to the deck
  LDA #0                        \ we are leaving; RedrawAll replaces them
.ld_unsave
  STA sprSaved,X
  DEX
  BPL ld_unsave
  JSR SetCRTCStart
  JSR RedrawAll
IF TEST_DROIDS
  JSR TestDroidsInit
ENDIF
  RTS

INCLUDE "src/rupture.asm"
INCLUDE "src/screen.asm"
INCLUDE "src/scroll.asm"
INCLUDE "src/level.asm"
INCLUDE "src/player.asm"
INCLUDE "src/sprite.asm"
IF TEST_DROIDS
INCLUDE "src/droidtest.asm"
ENDIF

\ ---- absolute working storage ------------------------------
.rowOfs    EQUW 0               \ row*640 accumulator for RedrawAll
.sTmp      EQUW 0
.vsyncCount EQUB 0              \ bumped by IrqHandler once per field
.oldIrq1V  EQUW 0

.code_end

\ ---- MODE 1 charset, built at deck-load time ----------------
\ In reclaimed OS workspace, not below &3000. Layer 4 filled that:
\ code plus the tile map plus the sprite data leaves under 1.5K, and
\ the charset alone is 2192 bytes.
\
\ &0400-&0CFF is 2.3K of MOS workspace that nothing here uses —
\ BASIC's variables, the sound and printer queues, the soft key and
\ user-defined character buffers. BASIC is not running (we are *RUN
\ from the boot file), we own IRQ1V so the MOS sound code never
\ executes, and the charset is built at deck load, which is after
\ the last filing-system call. DFS's own workspace is higher up.
\
\ The alternative was moving PARADAT into sideways RAM, which is the
\ right answer eventually but not the one that unblocks this layer.
ORG &0400
.charset
  SKIP 137 * CHAR_BYTES         \ NUM_CHARS, defined in chardata.asm
.charset_end
ORG code_end

\ ---- tile map: 64 x 16, one byte per tile -------------------
\ MapChar depends on this being page aligned and exactly 1K.
ALIGN &100
.tilemap
  SKIP MAP_COLS * MAP_ROWS
.tilemap_end

\ ============================================================
\ Generated data — in sideways RAM bank 0
\ ============================================================
\ Assembled at &8000 so every label resolves to its address in the
\ bank, but SAVEd with a catalogue load address of DATA_LOAD, so
\ *LOAD drops it in main RAM for PageDataIn to copy up. &3000 is a
\ safe staging area: the OS thinks the screen is &3000-&7FFF, but
\ the CRTC has been repointed at a 10K window starting &5800, so
\ only &5800-&7FFF is ever fetched for display — and the staging
\ copy is dead by the time anything is drawn.
\
\ Layer 5 spends the &3000-&4707 this frees on droid state and the
\ per-slot background save buffers.
DATA_LOAD = &3000
ORG SWRAM_BASE
.data_start
INCLUDE "src/data/chardata.asm"
INCLUDE "src/data/colours.asm"
INCLUDE "src/data/tiledefs.asm"
INCLUDE "src/data/levels.asm"
INCLUDE "src/data/droids.asm"
.data_end

ASSERT DR_W == SPR_W            \ sprite.asm declares these ahead of the
ASSERT DR_H == SPR_H            \ generated data; keep the two in step
ASSERT DR_TABSHIFT == SPR_TABSHIFT
ASSERT DR_GLYPHS == SPR_DIG_GLYPHS

DATA_PAGES = (data_end - data_start + 255) DIV 256
ASSERT data_end <= SWRAM_BASE + &4000

\ The staging copy overruns the panel, the mask table and the bottom
\ of the play buffer, and that is fine: PageDataIn is the FIRST thing
\ after the load, and FillPanel, SprBuildMask and LoadDeck all run
\ afterwards and rewrite everything above it. The one hard floor is
\ the code, which sits below &3000. Boot shows a moment of garbage in
\ the play area before the deck is drawn.
\
\ The limit that remains is the bank itself — staging more than 16K
\ would mean the data no longer fits where it is going.
ASSERT DATA_PAGES * 256 <= &4000
ASSERT DATA_LOAD + DATA_PAGES * 256 <= &8000

ASSERT charset_end - charset == NUM_CHARS * CHAR_BYTES

PRINT "code    ", ~start, "-", ~code_end
PRINT "tilemap ", ~tilemap, "-", ~tilemap_end
PRINT "charset ", ~charset, "-", ~charset_end
PRINT "data    ", ~data_start, "-", ~data_end, " (SWRAM bank", SWRAM_DATA, ",", DATA_PAGES, "pages )"

SAVE "PARA",    start,      code_end, start
SAVE "PARADAT", data_start, data_end, DATA_LOAD, DATA_LOAD
