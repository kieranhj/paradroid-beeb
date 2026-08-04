\ ============================================================
\ rupture.asm — vertical rupture: static panel + scrolled play area
\ ============================================================
\ Two CRTC cycles per TV frame. Reprogramming R4 mid-frame ends a
\ cycle early; the next cycle reloads VMA from R12/R13, so each
\ cycle has its own screen start.
\
\   cycle 1  static panel     R4=7   8 rows   R6=5   R7=255
\   cycle 2  scrolled play    R4=30  31 rows  R6=16  R7=26
\                                    -------
\                                    39 rows = 312 scanlines
\
\ Cycle 1 shows 5 rows of panel then 3 blank rows — the gap the
\ C64 has between its status panel and the play area.
\
\ VSync lands at frame row 8+26 = 34, which is MODE 1's default
\ R7, so the TV sees an identically phased frame and stays locked.
\
\ Timing is generous: one tick = 1us, a scanline is 64 and a char
\ row 512. The interrupts only have to land somewhere inside their
\ cycle before C4 reaches the target R4 — there are whole char
\ rows of slack, unlike single-scanline rupture work.
\ ============================================================

\ Constants live in main.asm — see the note there.

\ ============================================================
\ RuptInit — arm the T2 interrupt used to stage the cycles
\ ============================================================
.RuptInit
  LDA #0
  STA ruptState
  RTS

\ ============================================================
\ RuptVSync — called from the IRQ on CA1
\ We are inside cycle 2, five rows from its end. Point R12/R13 at
\ the panel so the next cycle boundary starts cycle 1 there.
\ ============================================================
.RuptVSync
IF DEBUG_RASTER
  LDA #5 : JSR DbgSetBg         \ magenta from here down
ENDIF
  LDA #12 : STA CRTC_ADDR : LDA #HI(PANEL_START) : STA CRTC_DATA
  LDA #13 : STA CRTC_ADDR : LDA #LO(PANEL_START) : STA CRTC_DATA

\ Restart T1 so the stage timing is phase-locked to VSync. Writing
\ T1C-H transfers the latch into the counter and starts it; in
\ continuous mode it then reloads itself, so the second stage is
\ exactly one period later however late this handler ran.
  LDA #LO(T1_PERIOD) : STA SYS_VIA_T1LL
  LDA #HI(T1_PERIOD) : STA SYS_VIA_T1CH
  LDA #0
  STA ruptState
  RTS

\ ============================================================
\ RuptTimer — called from the IRQ on T2
\ ============================================================
.RuptTimer
  LDA ruptState
  BEQ rt_cycle1
  CMP #1
  BEQ rt_cycle2
  RTS                           \ later fires in the frame: nothing to do

.rt_cycle1

\ ---- just inside cycle 1: the static panel -------------------
IF DEBUG_RASTER
  LDA #2 : JSR DbgSetBg         \ green from here down
ENDIF
  LDA #4  : STA CRTC_ADDR : LDA #CYCLE1_R4  : STA CRTC_DATA
  LDA #6  : STA CRTC_ADDR : LDA #PANEL_ROWS : STA CRTC_DATA
  LDA #7  : STA CRTC_ADDR : LDA #255        : STA CRTC_DATA

  LDA #12 : STA CRTC_ADDR : LDA crtcHi : STA CRTC_DATA
  LDA #13 : STA CRTC_ADDR : LDA crtcLo : STA CRTC_DATA

  LDA #1                        \ T1 reloads itself — nothing to re-arm
  STA ruptState
  RTS

\ ---- just inside cycle 2: the scrolled play area -------------
.rt_cycle2
IF DEBUG_RASTER
  LDA deck                      \ restore this deck's real background
  ASL A : ASL A
  TAY
  LDA deckPalette,Y
  JSR DbgSetBg
ENDIF
  LDA #4 : STA CRTC_ADDR : LDA #CYCLE2_R4 : STA CRTC_DATA
  LDA #6 : STA CRTC_ADDR : LDA #PLAY_ROWS : STA CRTC_DATA
  LDA #7 : STA CRTC_ADDR : LDA #CYCLE2_R7 : STA CRTC_DATA
  LDA #2
  STA ruptState
  RTS

\ ============================================================
\ FillPanel — placeholder title area: a bordered box
\ Real artwork comes with the title/HUD layer.
\ ============================================================
.FillPanel
  LDA #LO(PANEL_ADDR) : STA bufp
  LDA #HI(PANEL_ADDR) : STA bufp+1
  LDY #0
  LDA #0
  LDX #HI(PANEL_BYTES)          \ clear whole pages
.fp_page
  STA (bufp),Y
  INY
  BNE fp_page
  INC bufp+1
  DEX
  BNE fp_page
.fp_tail
  STA (bufp),Y                  \ + the remainder
  INY
  CPY #LO(PANEL_BYTES)
  BNE fp_tail

\ top and bottom edges of the box
  LDA #LO(PANEL_ADDR) : STA bufp
  LDA #HI(PANEL_ADDR) : STA bufp+1
  JSR fp_hline
  LDA #LO(PANEL_ADDR + (PANEL_ROWS-1)*ROW_BYTES + 7) : STA bufp
  LDA #HI(PANEL_ADDR + (PANEL_ROWS-1)*ROW_BYTES + 7) : STA bufp+1
  JSR fp_hline

\ left and right edges
  LDA #LO(PANEL_ADDR) : STA bufp
  LDA #HI(PANEL_ADDR) : STA bufp+1
  LDA #&88                      \ leftmost pixel of the byte
  JSR fp_vline
  LDA #LO(PANEL_ADDR + 79*8) : STA bufp
  LDA #HI(PANEL_ADDR + 79*8) : STA bufp+1
  LDA #&11                      \ rightmost pixel
  JSR fp_vline
  RTS

.fp_hline                       \ 80 units, 8 bytes apart
  LDY #0
  LDX #PLAY_UNITS
.fh_loop
  LDA #&FF
  STA (bufp),Y
  TYA
  CLC : ADC #8
  TAY
  BCC fh_nohi
  INC bufp+1
.fh_nohi
  DEX
  BNE fh_loop
  RTS

.fp_vline                       \ A = pixel pattern, down all panel rows
  STA fv_pat+1
  LDX #PANEL_ROWS
.fv_row
  LDY #0
.fv_scan
.fv_pat
  LDA #0                        \ operand patched above
  STA (bufp),Y
  INY
  CPY #8
  BNE fv_scan
  CLC
  LDA bufp   : ADC #LO(ROW_BYTES) : STA bufp
  LDA bufp+1 : ADC #HI(ROW_BYTES) : STA bufp+1
  DEX
  BNE fv_row
  RTS

IF DEBUG_RASTER
\ ============================================================
\ DbgSetBg — background (logical 0) to physical colour A
\ Four entries because in a 4-colour mode the palette CAM only
\ matches bits 7 and 5, so bits 6 and 4 need every combination.
\ ============================================================
.DbgSetBg
  EOR #7                        \ the ULA wants it inverted
  STA dbgTmp
  LDA #&00 : ORA dbgTmp : STA VIDEO_ULA_PAL
  LDA #&10 : ORA dbgTmp : STA VIDEO_ULA_PAL
  LDA #&40 : ORA dbgTmp : STA VIDEO_ULA_PAL
  LDA #&50 : ORA dbgTmp : STA VIDEO_ULA_PAL
  RTS
.dbgTmp EQUB 0
ENDIF

.ruptState EQUB 0               \ 0 = next timer starts cycle 1, 1 = cycle 2
.crtcHi    EQUB 0               \ play-area start for cycle 2, latched by the IRQ
.crtcLo    EQUB 0
