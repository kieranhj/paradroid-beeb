\ ============================================================
\ Paradroid — BBC Model B port
\ LAYER 4: the player droid — sprite, controls, collision
\ ============================================================
\ Z / X       move left / right
\ K / M       move up / down — and, in a lift, choose the deck
\ L           fire. On a lift platform it steps in and out
\ UP / DOWN   previous / next deck (debug free hop, outside a lift)
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
SWRAM_DATA = 4                  \ tiles, levels, palettes, droid game data
SWRAM_SPR  = 5                  \ the blitter, shifts 0 and 1 px
SWRAM_SPR2 = 6                  \ the same again for shifts 2 and 3 px
SWRAM_BASE = &8000

\ ---- two banks, swapped twice a pass ------------------------
\ The blitter outgrew what was left of one bank once every rotor row
\ and every glyph became compiled code, so the sprite half moved out
\ on its own. Only one bank is visible at a time, which is workable
\ because the two halves are never wanted at once: DoRedraws reads the
\ tile data, the blitter reads none of it, and the two run at
\ different points in the pass.
\
\ SprRestoreAll and SprDrawAll page SWRAM_SPR in and SWRAM_DATA back
\ out around themselves, so the data bank is what everything else
\ sees and no caller has to know. Two swaps a pass, 8 cycles each.
\
\ The IRQ is the thing that would break this, and does not: RuptVSync
\ and RuptTimer touch the CRTC, the VIA and their own variables, and
\ read nothing out of either bank. Checked, because an interrupt that
\ read tile data would corrupt at random with the sprite bank in.
MACRO PAGEBANK bank
  LDA #bank
  STA ROMSHAD                   \ both, always — see the note above
  STA ROMSEL
ENDMACRO

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
\ Three bands — the sprites, the level draw and everything else are
\ separate budgets, and the two that matter are the ones that grow
\ with what is happening rather than with the code:
\
\   magenta  SprRestoreAll, then SprAnimateAll + SprDrawAll. Two
\            bands, one either side of the redraw, because that is
\            genuinely where the sprite work happens — restore has
\            to precede any change to the scroll state, and the draw
\            has to follow the redraw so the save picks up settled
\            background. Restore is about a third of the sprite cost,
\            so leaving it untinted would flatter the total.
\   yellow   DoRedraws — the level draw, and the only band that
\            changes with which way the view is moving. Nothing when
\            standing still; a thin band for horizontal, since a
\            column is 16 cells; a much fatter one on the pass that
\            crosses a character row, which brings in a whole row of
\            40. Its width IS the cost of a scroll direction, so
\            steering while watching it is the cheapest way to see
\            the asymmetry between the axes.
\   cyan     everything else between the sprite bands: keys,
\            movement, wall probes and SetCRTCStart. This one should
\            barely move — if it grows, the growth is in code that
\            runs every pass regardless.
DEBUG_DRAW   = FALSE

\ DEBUG_POS prints the state needed to RETURN TO A SPOT along the top of
\ the panel, as hex, every pass: deck, plyX, posX, posY, mapHX, mapYr,
\ line, numDoors, then doors 0 and 1 as col/row/state.
\ It exists because reproducing a reported bug meant re-walking the
\ route - a dozen emulator round trips for BUGS.md #5. Read the digits
\ off the screen or a screenshot, poke them back, and the spot is
\ reachable in one step. See DbgPosOut in rupture.asm.
\ Not compatible with DEBUG_VSYNC: both write the top-left digit.
DEBUG_POS    = FALSE

\ DEBUG_VSYNC writes the number of FIELDS the last main-loop iteration
\ consumed as a single digit in the top-left corner of the panel — the
\ static half of the screen, so it does not scroll away and does not
\ have to be restored under a sprite.
\
\ FRAME_LOCK is the nominal reading: a 2 means the iteration fitted its
\ two fields. A 3 or more means it overran and WaitVSync found the flag
\ already set, so the rate degraded to 16.7 Hz, 12.5 Hz and so on. This
\ is the cheap always-on companion to DEBUG_DRAW: that one shows WHICH
\ work overruns, this one shows THAT it did, without a screenshot.
\
\ Deliberately tiny — a 4x5 digit is one MODE 1 byte per scanline, so
\ drawing it is five unmasked stores and the whole thing costs ~80
\ cycles of the 80,000 in a pass. Anything that had to mask, or that
\ spanned more than one byte per row, would start measuring itself.
\
\ It costs 117 bytes of main RAM. That used to be nearly all of what was
\ left; since the tile map was given a fixed home at &3800 the code has
\ room to &3000, so it is off by default out of tidiness rather than
\ necessity.
DEBUG_VSYNC  = TRUE

\ DEBUG_TIME measures one routine in CYCLES, which DEBUG_DRAW cannot:
\ its bands are only visible where the CRTC is displaying something,
\ so they show where work FINISHES rather than how long it took.
\
\ jsbeeb breakpoints have never fired in this project, so the method
\ is a User VIA T1 bracket. T1 free-runs at 1 MHz whether or not its
\ interrupt is enabled, and USR_VIA_IER is cleared at boot, so nothing
\ else touches it. The System VIA is off limits — T1 there drives the
\ rupture.
\
\   cycles = 2 * ((before - after) AND &FFFF) - DBG_T_OVERHEAD
\
\ The counter runs DOWN and at half the CPU clock, hence the subtract
\ and the doubling. DBG_T_OVERHEAD is the bracket measuring itself,
\ confirmed by timing a pass with nothing to draw.
\
\ Two things make a reading mean something:
\
\ ONE CALL SITE AT A TIME. Instrumenting two reliably hangs the main
\ loop. Move the JSR inside TimeCall rather than adding a second.
\
\ DRIVE THE SCROLL BY POKING dbgSpdX/dbgSpdY, NOT BY HOLDING A KEY.
\ A keypress injected at a fixed cycle count lands a pass earlier or
\ later once the code speed changes, and two runs then diverge for
\ reasons that have nothing to do with the change under test. A poked
\ speed is exact, needs no acceleration ramp, and CheckWalls is
\ skipped while it is set so a wall cannot cut the run short. Both
\ zero gives the keys back.
\
\ dbgBands and dbgCols count the WORK, so cost per band pass and per
\ column comes out of one run rather than needing a controlled one.
\ Read the addresses out of the beebasm listing after every build —
\ they shift constantly.
\
\ Emulation is deterministic, so one sample is exact. Averaging still
\ matters for anything a sprite touches: the rotor phase cycles every
\ 8 passes and the per-phase spread is a few hundred cycles.
DEBUG_TIME   = FALSE
DBG_T_OVERHEAD = 46

\ TEST_DROIDS parks six static droids around the player at deck load,
\ so the sprite pool can be looked at and measured before droid.asm
\ exists. Scaffolding — see src/droidtest.asm.
TEST_DROIDS  = TRUE
TD_DECK      = 1                \ CentreOnDeck lands the player somewhere
                                \ walkable here; on some decks it does not,
                                \ see BUGS.md
DBG_SPR      = 5                \ magenta — the sprite pool
DBG_LEVEL    = 3                \ yellow  — DoRedraws, the level draw
DBG_REDRAW   = 6                \ cyan    — keys, movement, CRTC park

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
USR_VIA_T1CL = &FE64            \ free-running 1 MHz counter — DEBUG_TIME
USR_VIA_T1CH = &FE65

\ ---- scratch, above the panel and below the play buffer ----
\ &5480-&57FF is the ~900 bytes left over between the panel's last
\ row and the start of the 10K strip. Everything here is a pure
\ function of data we already have, so it is built at startup rather
\ than shipped. The 2 px shifted artwork used to be built here too,
\ but at 1743 bytes for 24 droid types it no longer fits — it ships
\ pre-shifted in sideways RAM instead. &5480-&54FF is free.
\
\ Both character tables are PAGE ALIGNED, so `LDA charPtrLo,X` never
\ crosses a page and always costs 4 cycles. They are read once per
\ character drawn — 40 times a band pass — so the extra cycle would
\ be worth more than the 128 bytes of alignment.
CHAR_PTR_LO = &5500             \ character code -> charset address
CHAR_PTR_HI = &5600
SPR_MASKTAB = &5700             \ data byte -> its transparency mask
ASSERT CHAR_PTR_LO >= PANEL_ADDR + PANEL_BYTES
ASSERT CHAR_PTR_HI == CHAR_PTR_LO + 256
ASSERT CHAR_PTR_HI + 256 <= SPR_MASKTAB

\ The player is a droid like any other, in slot 0. Its screen Y never
\ changes: vertical scrolling is 1 scanline, so the C64's arrangement
\ survives here and the view carries the player rather than the other
\ way round. Only its X moved, because of the dead zone.
PLY_SLOT = 0
PLY_Y    = 50                   \ scanlines below the top of the view

\ The character that marks the walkable approach pad in front of a
\ door. Walking onto one opens the door — GetNearChar's `CMP #$20` in
\ the original, and the only trigger there is. See src/door.asm.
DOOR_PAD = &20

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
KEY_L      = &A9                \ -87, the fire button

\ ---- zero page ---------------------------------------------
\ &70-&8F was the original allocation and is full. With BASIC not
\ running and the MOS reduced to OSBYTE &81, the whole of &00-&8F
\ is ours, so the sprite blitter extends downwards from &68.
\ The digit block's eight scanlines, one pointer each, so the compiled
\ glyphs address every byte as (rowp+2r),Y and never walk. Built once
\ per block by SprBuildRowPtrs; see the header in sprite.asm.
\ ---- level draw ---------------------------------------------
\ &00-&3F is untouched language workspace and these are all read
\ inside loops, which is the only reason they are here: an absolute
\ read is 4 cycles against 3, and colSubX, colHalf and colTileRow are
\ read once per row of every column drawn, dbTile and dbSub once per
\ tile of every band. The rest are their neighbours and cost nothing
\ to bring along.
subRowOfs = &00                 \ (cellY AND 3)*4, the row within a tile
tileCol   = &01                 \ BandCharPtr's cached tile column
colTileCol = &02                \ DrawColumn: its fixed tile column
colSubX   = &03                 \ and character within the tile
colHalf   = &04                 \ 0 or 8: which half of the character
colTileRow = &05                \ cached tile row, changes every 4
dbTile    = &06                 \ DrawBandRows: tile column being walked
dbSub     = &07                 \ first character within it
dbOdd     = &08                 \ mapHX odd: row starts on a right half
bandDo    = &09                 \ a character row was crossed
bandRow   = &0A                 \ which map character row
bandRc    = &0B                 \ and which display row it lands in
colFirst  = &0C                 \ first column exposed by the move
colCount  = &0D                 \ how many
sDelta    = &0E                 \ scrollS delta for the move       (2)

\ ---- what is worth moving here, and what is not --------------
\ &10-&3F, &60-&63 and &65 were the last of the free space, and they
\ went to the SCALARS the per-pass code reads and writes directly.
\ The rule that decided every case:
\
\   LDA abs is 4 cycles and LDA zp is 3 — but LDA abs,X and LDA zp,X
\   are BOTH 4.
\
\ So an indexed table gains nothing at all, and none of the per-slot
\ sprite arrays (sprActive, sprUnit, sprFrame and the eleven others,
\ 98 bytes between them) moved. They are only ever reached through X.
\ The same goes for the offset tables in scroll.asm, tdpLo/tdpHi,
\ nearXoffset and the droid-test position arrays.
\
\ Read-modify-write is where it pays most: INC/LSR/ROR on zero page is
\ 5 cycles against 6, and CheckWalls alone does twelve shifts on
\ plyCX/plyCY every pass.
\
\ NOT moved, on measurement rather than taste: everything in level.asm
\ (bcSrc..palTmp and the rest) runs at deck load and nothing else, so
\ 40-odd bytes of zero page would buy a few hundred cycles once every
\ few minutes. Same for BuildCharPtrs and FillPanel.

\ ---- sprite blitter, one sprite at a time --------------------
\ Every one of these is touched per SLOT, so the cost is 14x a pass
\ once the pool is full — seven draws and seven restores.
sprSlot   = &10                 \ the slot being drawn or restored
sprIter   = &11                 \ SprDrawAll/SprRestoreAll's own index
sprNoWrap = &12                 \ the whole sprite clears the strip end
sprY      = &13                 \ scanlines below the top of the view
sprRowIdx = &14                 \ fallback: phase*21 + row
sprSeqBase = &15                \ where this (shift, phase) sequence starts
sprShiftW = &16                 \ the shift this draw or restore is using
sprGlyphBase = &17              \ 0 or 10: which half of the glyph table
sprDigit  = &18                 \ this type's number block          (2)
sprDig    = &1A                 \ its three glyph numbers           (3)
sprTmpPtr = &1D                 \ bufp saved across a walked row    (2)
sfrCarry  = &1F                 \ SprFetchRow's 2 px shift carry

\ ---- rupture / CRTC state -----------------------------------
\ Read and written inside the interrupt handler, three fires a frame,
\ so this is latency as well as throughput — and the note in PLAN.md
\ about a missed deadline hanging the ruptState machine is reason
\ enough to make the handler shorter wherever it is free.
ruptState = &20                 \ which rupture stage the next T1 fire is
drawFlag  = &21                 \ set when the play area is off-display
crtcHi    = &22                 \ play-area start for the play cycle,
crtcLo    = &23                 \ latched by the IRQ
line      = &24                 \ sub-row scroll offset, 0-7 — the live value
pline     = &25                 \ parked with crtcHi/Lo by SetCRTCStart
iline     = &26                 \ latched from pline at fire 1, used all frame

\ ---- player: position, speed, the wall probes ----------------
\ One pass through these per game loop, but it is a long pass: the
\ position and speed pairs are read by CalcSpeed, CheckWalls,
\ ApplyMove, DeadZone and both clamps.
posX      = &27                 \ view origin, map pixels           (2)
posY      = &29                 \                                   (2)
plyX      = &2B                 \ the player itself — the authority
xSpd      = &2D                 \ 8.8 signed, px per pass           (2)
ySpd      = &2F                 \                                   (2)
spd       = &31                 \ CalcAxis works on this pair       (2)
cwU       = &33                 \ CheckWalls' reference quantity    (2)
plyCX     = &35                 \ and the reference cell            (2)
plyCY     = &37                 \                                   (2)
dzSx      = &39                 \ DeadZone: where the sprite sits   (2)
dzD       = &3B                 \ and how far the view must follow  (2)
oldHX     = &3D                 \ what the pass is moving from      (2)
plyXf     = &3F                 \ sub-pixel fraction of plyX
amTmp     = &60                 \ ApplyMove's shift accumulator     (2)
axDir     = &62                 \ CalcAxis: -1, 0 or +1
mvSign    = &63                 \ &00 or &FF, sign-extending a speed
pgCount   = &65                 \ ProbeGroup's countdown of three

rowp     = &50                  \ &50-&5F: 8 pointers, one per block row
rowq     = &40                  \ &40-&4F: the same eight rows in the SAVE
                                \ area, so a glyph can save what it draws

sprScan  = &64                  \ sprite's STARTING scanline in its char row;
                                \ the walk reads its position from bufp AND 7
swSrc    = &66                  \ sideways-RAM copy source  (2)
psrc     = &68                  \ sprite row, pixel data    (2)
swDst    = &6A                  \ sideways-RAM copy dest    (2)
sprRow   = &6C                  \ sprite row being blitted
dbIdx    = &6D                  \ DrawBandRows: character within the tile row
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
dbN      = &88                  \ DrawBandRows: characters left in this tile
uCount   = &89
rCount   = &8A
deck     = &8B
dbCount  = &8C                  \ DrawBandRows: characters left in the row
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
  LDA #SWRAM_DATA               \ PARADAT lands at &3000 and is copied up
  LDX #DATA_PAGES               \ into SWRAM; the staging area is free after
  JSR PageBankIn

  LDX #LO(loadspr)              \ and again for the sprite bank, staged over
  LDY #HI(loadspr)              \ the same &3000. The filing system pages
  JSR OSCLI                     \ DFS in and out around its own call and
  LDA #SWRAM_SPR                \ restores from ROMSHAD, which PageBankIn
  LDX #SPR_PAGES                \ has kept honest, so the second load is no
  JSR PageBankIn                \ different from the first

  LDX #LO(loadspr2)             \ and a third: shifts 2 and 3 px live in a
  LDY #HI(loadspr2)             \ bank of their own, because four compiled
  JSR OSCLI                     \ shifts do not fit in one
  LDA #SWRAM_SPR2
  LDX #SPR2_PAGES
  JSR PageBankIn

  PAGEBANK SWRAM_DATA           \ the data bank is the resting state

  JSR FillPanel                 \ after the staging area is done with: it
                                \ reaches past &4800, over the panel

  JSR BuildCharPtrs             \ needs the data bank in, and the staging
                                \ copy finished — it reaches past &5500
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
IF DEBUG_VSYNC
  JSR DbgFrameCount             \ the boundary has just happened, so this
ENDIF                           \ counts the iteration that has finished
IF DEBUG_POS
  JSR DbgPosOut                 \ where we are, for getting back here
ENDIF
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
IF DEBUG_TIME
  JSR DbgSpeedOverride          \ a poked speed takes the controls over
  BNE ml_poked                  \ and skips the walls; zero gives them back
ENDIF
  LDA liftMode                  \ the lift has the controls: no movement,
  BNE ml_nomove                 \ and UP/DOWN mean something else below
  JSR ReadKeys
  JSR CalcSpeed
  JSR CheckWalls                \ before the move, as the C64 does: it
.ml_poked                       \ zeroes the speed the move would apply
.ml_nomove
  JSR ApplyMove

  \ Park the CRTC address ONCE, with every axis accounted for, and
  \ before any drawing — the IRQ latches it at frame row 3, only a
  \ few rows into this window.
  JSR SetCRTCStart
IF DEBUG_DRAW
  LDA #DBG_LEVEL : JSR DbgSetBg \ the level draw on its own: it is the
ENDIF                           \ band that varies with the direction
IF DEBUG_TIME
  JSR TimeCall                  \ TimeCall calls DoRedraws — see its header
ELSE
  JSR DoRedraws
ENDIF
IF DEBUG_DRAW
  LDA #DBG_REDRAW : JSR DbgSetBg
ENDIF

  \ Deck keys are edge triggered: one press steps one deck however
  \ long it is held. A blocking wait-for-release deadlocks if the
  \ other deck key goes down before the first is released.
\ L is fire, and fire steps into a lift and back out of it. Edge
\ triggered, or holding it would toggle every pass.
  LDX #KEY_L
  JSR keydown
  BNE ml_retOff
  LDA prevRet
  BNE ml_notRet
  LDA #1 : STA prevRet
  LDA liftMode
  BNE ml_getout
  JSR LiftEnter
  JMP ml_notRet
.ml_getout
  JSR LiftExit
  JMP ml_notRet
.ml_retOff
  LDA #0 : STA prevRet
.ml_notRet

\ UP and DOWN belong to the lift while it has the controls. Outside one
\ they stay the debug free hop, which is worth keeping until every deck
\ is reachable by lift and can be tested that way instead.
  LDA liftMode
  BEQ ml_debugdeck
  JSR LiftControl
  JMP ml_notDn

.ml_debugdeck
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
.loadspr
  EQUS "LOAD PARASPR"
  EQUB 13
.loadspr2
  EQUS "LOAD PARSPR2"
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
\ The data bank stays selected from here on. Every character drawn
\ reads `tiledefs` through it, so it cannot be paged out during play.
\ (`charRemap` used to be read every frame too; it is now folded into
\ CHAR_PTR_LO/HI at startup and never touched again.) That displaces
\ BASIC, which we
\ never return to, and not DFS, which lives in its own socket and
\ which the MOS pages in and back out around each of its own calls.
\ Called twice, once per bank: A selects it, X is the page count.
.PageBankIn
  STA ROMSHAD                   \ both, always — see the note at the top
  STA ROMSEL

  LDA #LO(DATA_LOAD) : STA swSrc
  LDA #HI(DATA_LOAD) : STA swSrc+1
  LDA #LO(SWRAM_BASE): STA swDst
  LDA #HI(SWRAM_BASE): STA swDst+1
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

\ Where we arrive. A lift knows exactly where it puts you; CentreOnDeck
\ only frames the deck and has been known to land the player inside a
\ wall, so it is now the fallback rather than the rule.
  LDA liftPlace
  BEQ ld_centre
  LDA #0
  STA liftPlace
  JSR LiftPlace
  JMP ld_placed
.ld_centre
  JSR CentreOnDeck
  JSR SetPosFromMap             \ the pixel position is the authority from
                                \ here on; CentreOnDeck works in characters
.ld_placed
\ Start the strip at the buffer base — vertically, at least. `line` is
\ zeroed so buffer row 0 is not a split row, which RedrawAll needs
\ because it writes whole rows.
\
\ HORIZONTALLY the strip starts one unit in when mapHX is odd, and
\ that is load bearing: DrawBandRows copies a whole character as one
\ 16-byte run and would write past the end of the buffer if the strip's
\ wrap ever fell between a character's two halves. It cannot, provided
\ scrollS/8 and mapHX agree in parity — see COPYCHAR in scroll.asm for
\ why that is then preserved for the rest of the deck. This is where it
\ becomes true.
\
\ CentreOnDeck happens to produce an even mapHX today (it is charX * 2),
\ so this is a no-op as things stand. It is written out anyway because
\ the consequence of it being false is a write into sideways RAM rather
\ than a wrong pixel, and that should not rest on another routine's
\ arithmetic staying as it is.
  LDA mapHX
  AND #1
  ASL A : ASL A : ASL A         \ 0 or 8
  STA scrollS
  LDA #0
  STA scrollS+1
  STA line
  STA iline
  JSR DoorInit                  \ a door left open on the deck we are
                                \ leaving would patch a tile position on
                                \ the one we are entering
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
INCLUDE "src/bufcore.asm"       \ what screen/scroll could not leave behind
INCLUDE "src/player.asm"
INCLUDE "src/door.asm"
INCLUDE "src/lift.asm"
INCLUDE "src/sprite.asm"
IF TEST_DROIDS
INCLUDE "src/droidtest.asm"
ENDIF

IF DEBUG_TIME
\ ============================================================
\ TimeCall — bracket ONE routine with the User VIA T1 counter
\ ============================================================
\ To measure something else, change the JSR below and move the call
\ site in the main loop. Do not add a second bracket — see the note
\ on DEBUG_TIME.
\
\ The 16-bit read is not atomic: if the low byte wraps between the two
\ reads the high byte is one too high, worth 1024 cycles. That is a
\ ~1% chance per reading and 0.1% of a typical total, so it is left
\ alone rather than paid for on every pass.
\
\ Reading it out, per run:
\   dbgAcc / dbgN     ticks per pass; cycles = 2*ticks - DBG_T_OVERHEAD
\   dbgBands, dbgCols what that bought — band passes and columns drawn
\
\ Zero dbgAcc..dbgCols to start a run, poke dbgSpdX/Y, let it run a
\ known number of passes, read them back.
.TimeCall
  LDA bandDo                    \ the work this pass is about to do
  CLC : ADC dbgBands : STA dbgBands
  BCC tc_b
  INC dbgBands+1
.tc_b
  LDA colCount
  CLC : ADC dbgCols : STA dbgCols
  BCC tc_c
  INC dbgCols+1
.tc_c
  LDA USR_VIA_T1CL : STA dbgT0
  LDA USR_VIA_T1CH : STA dbgT0+1

  JSR DoRedraws                 \ <-- the routine under test

  LDA USR_VIA_T1CL : STA dbgT1
  LDA USR_VIA_T1CH : STA dbgT1+1
  SEC                           \ the counter runs down
  LDA dbgT0   : SBC dbgT1   : STA dbgD
  LDA dbgT0+1 : SBC dbgT1+1 : STA dbgD+1
  CLC                          \ 24-bit: 16 would wrap in ~10 passes
  LDA dbgAcc   : ADC dbgD   : STA dbgAcc
  LDA dbgAcc+1 : ADC dbgD+1 : STA dbgAcc+1
  LDA dbgAcc+2 : ADC #0     : STA dbgAcc+2
  INC dbgN
  RTS

\ ============================================================
\ DbgSpeedOverride — a poked speed instead of the controls
\ Z set if nothing is poked, in which case the keys still work.
\ ============================================================
.DbgSpeedOverride
  LDA dbgSpdX
  ORA dbgSpdX+1
  ORA dbgSpdY
  ORA dbgSpdY+1
  BEQ dso_x
  LDA dbgSpdX   : STA xSpd
  LDA dbgSpdX+1 : STA xSpd+1
  LDA dbgSpdY   : STA ySpd
  LDA dbgSpdY+1 : STA ySpd+1
  LDA #1                        \ Z clear: the caller skips CheckWalls
.dso_x
  RTS

.dbgSpdX   EQUW 0               \ 8.8 px per pass; &0700 is top speed
.dbgSpdY   EQUW 0
.dbgT0     EQUW 0
.dbgT1     EQUW 0
.dbgD      EQUW 0
.dbgAcc    EQUB 0
           EQUB 0
           EQUB 0               \ 24-bit sum of T1 ticks
.dbgN      EQUB 0               \ passes accumulated
.dbgBands  EQUW 0               \ band passes drawn over those passes
.dbgCols   EQUW 0               \ columns drawn
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
\
\ PLACED, NOT FLOATED. It used to sit at the next page boundary after
\ code_end, which was fine while the code was small and silently walked
\ into the sprite save areas at &3000 when it was not — a corruption
\ with no assert to catch it. &3700-&47FF is clear: the save areas end
\ at &36FF, SPR_MASKTAB is at &5700 and the panel starts at &4800. That
\ gives the code the whole of &1100-&3000 instead of whatever was left.
\
\ It is above DATA_LOAD, so the PARADAT staging copy runs straight over
\ it — harmless, because PageDataIn is done long before LoadDeck calls
\ BuildLevel to fill it in, the same argument the panel and the mask
\ table rely on.
ORG &3800
.tilemap
  SKIP MAP_COLS * MAP_ROWS
.tilemap_end
ASSERT tilemap >= SPR_SAVE + SPR_SLOTS * 256
ASSERT tilemap_end <= PANEL_ADDR
ASSERT code_end <= SPR_SAVE

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
INCLUDE "src/data/droidgame.asm"

\ ---- bank-resident working storage --------------------------
\ Main RAM below &3000 ran out during Layer 8b. These two are the
\ obvious things to move: neither is read in a hot loop, and both are
\ only ever touched with SWRAM_DATA paged in — which is the resting
\ state, swapped out only around the blitter, which touches neither.
\ Sideways RAM is RAM. doorDef is written at run time and its shipped
\ contents are irrelevant; blankTileRow must genuinely be zero, so it is
\ emitted rather than SKIPped.
.doorDef
  SKIP DOOR_SLOTS * 16

.blankTileRow
  FOR r, 0, MAP_COLS-1
    EQUB 0
  NEXT

\ ---- the level draw, next to the data it reads ---------------
\ CODE IN A BANK, not just data. These three files read nothing but
\ what is above them — tile definitions, deck RLE, the charset source,
\ the colour schemes — so putting them here costs no paging at all:
\ SWRAM_DATA is the resting state, so the main loop, LoadDeck, door.asm
\ and lift.asm call in with a plain JSR.
\
\ THE RULE IS ONE-WAY. Bank code may call main RAM freely; main RAM may
\ call in ONLY with SWRAM_DATA paged. The two places where that is false
\ are startup, before the bank is loaded, and the window inside
\ SprDrawAll/SprRestoreAll — which is exactly what bufcore.asm holds
\ back, and why its header states the rule at length. A stray call in
\ here with the sprite bank in would land in compiled sprite rows and
\ there is no diagnostic for that.
\
\ The IRQ is safe by inspection: it touches rupture.asm and the CRTC
\ registers, and nothing here. That was already the condition for
\ having two banks at all.
INCLUDE "src/screen.asm"
INCLUDE "src/scroll.asm"
INCLUDE "src/level.asm"
.data_end

\ SAVED HERE, NOT AT THE BOTTOM. SAVE writes out whatever the assembled
\ image holds at the time it runs, and the sprite bank below is about to
\ overwrite these same addresses — so a SAVE left until the end would
\ write the sprite bank's bytes into PARADAT. CLEAR releases beebasm's
\ overwrite guard; it does not give the two banks separate storage.
SAVE "PARADAT", data_start, data_end, DATA_LOAD, DATA_LOAD

\ ============================================================
\ The sprite bank — artwork and compiled blitter code
\ ============================================================
\ A second ORG at &8000: both banks appear at the same addresses, and
\ each label resolves to the address it will have when ITS bank is
\ paged in. Nothing here is reachable while SWRAM_DATA is selected,
\ which is why SprDrawAll and SprRestoreAll swap around themselves.
\
\ CLEAR is what lets the same addresses be assembled twice — beebasm
\ tracks which bytes have been written and refuses to overwrite them,
\ which is exactly the guard you want everywhere except here.
CLEAR SWRAM_BASE, SWRAM_BASE + &4000
ORG SWRAM_BASE
.spr_start
INCLUDE "src/data/droids.asm"
.spr_end
SAVE "PARASPR", spr_start, spr_end, DATA_LOAD, DATA_LOAD

\ ---- the second sprite bank: shifts 2 and 3 px --------------
\ A compiled shift is ~5.5K of code and there are four of them, so they
\ do not fit in one bank. This one is laid out exactly like the last:
\ the same fixed table section first, at the same addresses, then its
\ own two shifts' code. PAGESPRBANK picks between them per sprite.
CLEAR SWRAM_BASE, SWRAM_BASE + &4000
ORG SWRAM_BASE
.spr2_start
INCLUDE "src/data/droids2.asm"
.spr2_end
SAVE "PARSPR2", spr2_start, spr2_end, DATA_LOAD, DATA_LOAD

ASSERT DR_W == SPR_W            \ sprite.asm declares these ahead of the
ASSERT DR_H == SPR_H            \ generated data; keep the two in step
ASSERT DR_SEQSHIFT == SPR_SEQSHIFT
ASSERT DR_GLYPHS == SPR_DIG_GLYPHS

\ THE TWO SPRITE BANKS MUST AGREE ON WHERE THEIR TABLES ARE. The blitter
\ names bank 5's labels and reads them with either bank paged, so a
\ layout change in one file that is not matched in the other would send
\ it into compiled sprite rows with no diagnostic at all. Every table the
\ blitter reaches by name is checked here.
ASSERT xdrMulRows == drMulRows
ASSERT xdrDigitLo == drDigitLo
ASSERT xdrDigitHi == drDigitHi
ASSERT xdrSeqLo   == drSeqLo
ASSERT xdrSeqHi   == drSeqHi
ASSERT xdrRSeqLo  == drRSeqLo
ASSERT xdrRSeqHi  == drRSeqHi
ASSERT xdrPrgLo   == drPrgLo
ASSERT xdrPrgHi   == drPrgHi
ASSERT xdrRPrgLo  == drRPrgLo
ASSERT xdrRPrgHi  == drRPrgHi
ASSERT xdrSeqIdx  == drSeqIdx
ASSERT xdrMul10   == drMul10
ASSERT xdrGlyphLo == drGlyphLo
ASSERT xdrGlyphHi == drGlyphHi
ASSERT xdrDigit0  == drDigit0
ASSERT xdrDigit1  == drDigit1
ASSERT xdrDigit2  == drDigit2
ASSERT xdrBlkSave6 == drBlkSave6

DATA_PAGES = (data_end - data_start + 255) DIV 256
SPR_PAGES  = (spr_end - spr_start + 255) DIV 256
SPR2_PAGES = (spr2_end - spr2_start + 255) DIV 256
ASSERT data_end <= SWRAM_BASE + &4000
ASSERT spr_end  <= SWRAM_BASE + &4000
ASSERT spr2_end <= SWRAM_BASE + &4000

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
ASSERT SPR_PAGES * 256 <= &4000
ASSERT DATA_LOAD + SPR_PAGES * 256 <= &8000
ASSERT SPR2_PAGES * 256 <= &4000
ASSERT DATA_LOAD + SPR2_PAGES * 256 <= &8000

ASSERT charset_end - charset == NUM_CHARS * CHAR_BYTES

PRINT "code    ", ~start, "-", ~code_end
PRINT "tilemap ", ~tilemap, "-", ~tilemap_end
PRINT "charset ", ~charset, "-", ~charset_end
PRINT "data    ", ~data_start, "-", ~data_end, " (SWRAM bank", SWRAM_DATA, ",", DATA_PAGES, "pages )"
PRINT "sprite  ", ~spr_start, "-", ~spr_end, " (SWRAM bank", SWRAM_SPR, ",", SPR_PAGES, "pages )"
PRINT "sprite2 ", ~spr2_start, "-", ~spr2_end, " (SWRAM bank", SWRAM_SPR2, ",", SPR2_PAGES, "pages )"

SAVE "PARA",    start,      code_end, start
\ PARADAT and PARASPR are saved where they are assembled, above.
