\ ============================================================
\ rupture.asm — three CRTC cycles per frame
\ ============================================================
\ panel (static) / play (scrolled) / tail (VSync, nothing shown).
\ Reprogramming R4 mid-frame ends a cycle early; the next cycle
\ reloads VMA from R12/R13, so each cycle has its own screen start.
\ Geometry and timing constants live in main.asm — see the note
\ there for the frame layout and why there are three cycles.
\
\ Smooth vertical scrolling rides on this: R5 gives the play cycle
\ `line` extra scanlines and takes them back from the panel cycle,
\ so the play cycle starts `line` scanlines earlier and the picture
\ scrolls by less than a character row. The scanlines either side
\ of the intended 128 are real and wrong, so R8 blanks them.
\
\ WHEN EACH REGISTER MUST BE WRITTEN — they are not all the same,
\ and getting this wrong is silent:
\
\   R4   inside its own cycle, before C4 reaches the new value.
\        Not earlier: the previous cycle would trip over it.
\   R7   inside the PREVIOUS cycle. Writing it at the row it is
\        meant to fire on is too late — that row's compare has
\        already happened, VSync never comes, and the CRTC
\        free-runs on whatever the last cycle shape was.
\   R6   inside the PREVIOUS cycle. The vertical display enable is
\        a flip-flop cleared when the row counter reaches R6; once
\        cleared, raising R6 does not bring it back for that cycle.
\   R12/13  inside the PREVIOUS cycle — latched at cycle start.
\   R5   any time before the cycle's END, where it is sampled.
\ ============================================================

\ Blanking is suppressed under DEBUG_RASTER so the timing bands
\ stay visible — see main.asm.
IF DEBUG_RASTER
  R8_OFF = R8_ON
ELSE
  R8_OFF = R8_BLANK
ENDIF

\ NEVER write R5 near the END of a cycle. The vertical adjust
\ counts up and compares against R5; changing R5 once the count has
\ passed the new value means the match never happens and the adjust
\ runs on until the 5-bit counter wraps — ~29 extra scanlines. That
\ is why the play cycle's R5 is written at fire 3 and not at fire 2:
\ fire 2 sits within a scanline of the panel cycle's adjust ending,
\ and landing the wrong side of it stretched the panel cycle from
\ 64 scanlines to 85. R5's legal window is the whole cycle, so
\ there is no reason to write it anywhere near the edge.

\ ============================================================
\ THE PANEL HAS ITS OWN PALETTE
\ ============================================================
\ The panel and the play area are separate CRTC cycles, so they can be
\ separate palettes too: sixteen ULA writes at each boundary, and the
\ status box gets the C64's colours instead of the deck's.
\
\ It has to. The deck palettes share only logical 0 (blue) and logical 1
\ (white) across all sixteen decks — 2 and 3 vary, and are BLACK on some
\ of them, so a panel drawn in either would vanish on those decks. That
\ is the open item PLAN.md listed as "panel shares the play palette".
\
\ WHERE THE TWO WRITES GO, and why neither is anywhere else:
\
\   the panel's, at the END of RuptVSync. The tail cycle displays
\   nothing and the panel starts 64 scanlines later, so there is no
\   deadline — but it must come AFTER the T1 restart, because delaying
\   that would shift every fire in the frame by however long this takes.
\
\   the deck's, at the END of fire 1. The panel's display ended at P+32
\   and the play cycle starts at P+64-line, so the whole window is free;
\   putting it last means R4 and the T1 latch are already written and
\   nothing that IS timing-critical moves. ~210 cycles, three scanlines.
\
\ &FE21 takes (logical << 4) | (physical EOR 7), and in a 4-colour mode
\ the CAM compares only bits 7 and 5 — so all sixteen entries are written
\ and four of them land on each logical colour. SetPalette has the
\ derivation; these tables are that arithmetic done at assembly time.

\ The C64's status area is grey on white with the logo and the score in
\ red. The BBC has no grey, so the frame and the mode word take black.
PN_PHYS_PAPER = 7               \ white — the inside of the box
PN_PHYS_BAR   = 2               \ green — LAYER 9 DECISION 20's energy bar,
                                \ and the whole of what it costs the palette:
                                \ logical 1 was the panel's unused colour, so
                                \ the bar takes a fourth ink without moving the
                                \ paper, the logo, the score or the frame
PN_PHYS_RED   = 1               \ the logo and the score
PN_PHYS_INK   = 0               \ black — the frame and the mode word

MACRO PALENT n, phys
  EQUB (n * 16) OR (phys EOR 7)
ENDMACRO

\ Grouped by logical colour rather than by entry: the four entries that
\ share one are the four that have to agree, and the ULA does not care
\ what order they arrive in.
.palPanel
  PALENT  0, PN_PHYS_PAPER : PALENT  1, PN_PHYS_PAPER
  PALENT  4, PN_PHYS_PAPER : PALENT  5, PN_PHYS_PAPER
  PALENT  2, PN_PHYS_BAR   : PALENT  3, PN_PHYS_BAR
  PALENT  6, PN_PHYS_BAR   : PALENT  7, PN_PHYS_BAR
  PALENT  8, PN_PHYS_RED   : PALENT  9, PN_PHYS_RED
  PALENT 12, PN_PHYS_RED   : PALENT 13, PN_PHYS_RED
  PALENT 10, PN_PHYS_INK   : PALENT 11, PN_PHYS_INK
  PALENT 14, PN_PHYS_INK   : PALENT 15, PN_PHYS_INK

\ The deck's sixteen, built by SetPalette at deck load. IT IS HERE, IN
\ MAIN RAM, and not in bank 4 with SetPalette: the interrupt reads it
\ three times a frame and may fire with bank 5 or 6 paged in.
\ The ASSEMBLED DEFAULT is the OS's MODE 1 set, not zeros: the front
\ end inherits the last deck's palette (KC, 2026-08-22), and at a cold
\ boot the briefing can run under the rupture before any deck has ever
\ loaded — an all-zero table wrote only logical 0, and wrote it white.
.palPlay
  PALENT  0, 0 : PALENT  1, 0 : PALENT  4, 0 : PALENT  5, 0
  PALENT  2, 1 : PALENT  3, 1 : PALENT  6, 1 : PALENT  7, 1
  PALENT  8, 3 : PALENT  9, 3 : PALENT 12, 3 : PALENT 13, 3
  PALENT 10, 7 : PALENT 11, 7 : PALENT 14, 7 : PALENT 15, 7

\ The transfer game's own palette is written INTO palPlay by XferEnter4
\ (saved and restored around it), so these three fires need no fourth
\ case. The tables live in droid.asm — bank 4, where the writer is —
\ because main RAM below &3000 is full; palPlay itself must stay here.

.SetPalPanel
  LDX #15
.spp_loop
  LDA palPanel,X
  STA VIDEO_ULA_PAL
  DEX
  BPL spp_loop
  RTS

\ THE DISRUPTOR OVERRIDES LOGICAL 0 HERE, after the table rather than in
\ it. $239C forces the C64's background white for the three frames of a
\ burst; doing it by writing palPlay would be saved and restored by the
\ transfer game and the lift view along with the deck's own colours, so
\ the flash is an override that stores nothing. Logical 0's four ULA
\ entries are 0, 1, 4 and 5, and white is physical 7, so each is its own
\ index in the top nibble. Four cycles a fire when no burst is running.
.SetPalPlay
  LDX #15
.spl_loop
  LDA palPlay,X
  STA VIDEO_ULA_PAL
  DEX
  BPL spl_loop
  LDA disrFlash
  BEQ spl_x
  LDA #&00 : STA VIDEO_ULA_PAL
  LDA #&10 : STA VIDEO_ULA_PAL
  LDA #&40 : STA VIDEO_ULA_PAL
  LDA #&50 : STA VIDEO_ULA_PAL
.spl_x
  RTS

\ ============================================================
\ RuptInit
\ ============================================================
.RuptInit
  LDA #0
  STA ruptState
  STA line
  STA iline
  RTS

\ Fire 2 -> fire 3, as a variable — see the note at the write in fire 1.
\ Main RAM, read inside the interrupt, so it must never move into a bank.
\
\ ONLY t1i3Hi IS A VARIABLE. The two intervals differ by one character
\ row, which is &200 ticks, so the low byte is the same for both and the
\ ASSERT beside T1_I3X in main.asm says so. t1i3Lo is read every frame
\ and written by nothing.
.t1i3Lo EQUB LO(T1_I3)
.t1i3Hi EQUB HI(T1_I3)

\ ============================================================
\ RuptVSync — IRQ on CA1, at P+248, row TAIL_R7 of the tail cycle
\ (row 5 since FRAME_DROP_ROWS moved the picture down; it was row 8,
\ P+272, and moving it is what drops the picture on the tube)
\ ============================================================
.RuptVSync
IF DEBUG_RASTER
  LDA #5 : JSR DbgSetBg         \ magenta from here down
ENDIF
\ The tail cycle's own R4 and R5. It is 8 rows in, so R4 = 12 is
\ still ahead of C4. Its R6 and R7 were set at fire 3, last cycle.
  LDA #4  : STA CRTC_ADDR : LDA #TAIL_R4 : STA CRTC_DATA
  LDA #5  : STA CRTC_ADDR : LDA #0       : STA CRTC_DATA

\ R6 for the PANEL cycle, which starts in 64 scanlines — 40 plus the
\ 24 FRAME_DROP_ROWS moved VSync back by. The tail displays nothing,
\ so raising it now costs nothing there.
  LDA #6  : STA CRTC_ADDR : LDA #PANEL_ROWS : STA CRTC_DATA

\ R7 = 255 for the PANEL cycle: no VSync in the panel or the play
\ cycle, only in the tail. IT IS HERE AND NOT AT FIRE 1, and that is
\ what FRAME_DROP_ROWS cost. Fire 1 is at P+44, row 5 of the 7-row
\ panel cycle, and writing R7 there worked only while TAIL_R7 was 8 —
\ a 7-row cycle can never reach row 8, so the stale value was harmless
\ for five rows. Once TAIL_R7 drops to 7 or below it is NOT: at 4 the
\ panel cycle reaches row 4 at P+32 and at 5 it reaches row 5 at P+40,
\ both of them before fire 1, and it fires a VSync of its own. That
\ re-enters this handler mid-frame, which restarts T1 and zeroes
\ ruptState, so fire 1 never runs, the play cycle is never set up or
\ unblanked, and the play area is simply BLACK with the panel sitting
\ alone on a rolling picture. Measured at 4, not reasoned about.
\
\ Here it is safe by the file's own rule: the tail cycle is the panel's
\ PREVIOUS cycle, and the panel does not start for another 64
\ scanlines. The tail's own VSync has already fired — that is why we
\ are in this handler — and the 6845 counts the pulse out of R3
\ independently of R7.
  LDA #7  : STA CRTC_ADDR : LDA #255        : STA CRTC_DATA

\ Unblank for the panel, which starts in 64 scanlines. Safe to do
\ now: the tail displays nothing either way.
  LDA #8  : STA CRTC_ADDR
.rvR8
  LDA #R8_ON   : STA CRTC_DATA  \ the operand is patched -- see r2R8

\ R12/R13 for the panel cycle, latched when it starts at P+312.
  LDA #12 : STA CRTC_ADDR : LDA #HI(PANEL_START) : STA CRTC_DATA
  LDA #13 : STA CRTC_ADDR : LDA #LO(PANEL_START) : STA CRTC_DATA

\ Restart T1 (writing T1C-H transfers the latch and starts it), then
\ immediately re-latch with the NEXT interval, which the counter
\ picks up when it reloads at fire 1.
  LDA #LO(T1_I1) : STA SYS_VIA_T1LL
  LDA #HI(T1_I1) : STA SYS_VIA_T1CH
  LDA #LO(T1_I2) : STA SYS_VIA_T1LL
  LDA #HI(T1_I2) : STA SYS_VIA_T1LH

\ The panel's palette, AFTER the T1 restart — see the header. Not under
\ DEBUG_RASTER, whose bands are ULA writes of their own and which this
\ would overwrite twice a frame.
IF NOT(DEBUG_RASTER)
  JSR SetPalPanel
ENDIF

  LDA #0
  STA ruptState
  RTS

\ ============================================================
\ RuptTimer — IRQ on T1
\ ============================================================
.RuptTimer
  LDA ruptState
  BEQ rt_panel
  CMP #1
  BEQ rt_play
  CMP #2
  BNE rt_none
  JMP rt_drawok
.rt_none
  RTS                           \ any later fire: nothing to do

\ ---- fire 1, P+44: inside the panel cycle -------------------
.rt_panel
IF DEBUG_RASTER
  LDA #2 : JSR DbgSetBg         \ green from here down
ENDIF
\ Blank first. From here to fire 2 the play cycle may already have
\ started (it does, by up to 7 scanlines) and what it shows in that
\ sliver is the wrong map row.
  LDA #8  : STA CRTC_ADDR : LDA #R8_OFF     : STA CRTC_DATA

\ Take the sub-row offset from the same park as R12/R13, at the same
\ moment R12/R13 is read, so the two can never come from different
\ frames. Holds for the rest of this frame: fire 3 uses it too.
  LDA pline
  STA iline

  LDA #4  : STA CRTC_ADDR : LDA #PANEL_R4 : STA CRTC_DATA

\ R6 for the play cycle. The panel's own display ended 12 scanlines
\ ago (PANEL_ROWS = 4, so P+32), so R6 is free to become the play
\ cycle's. R7 IS NOT HERE any more — it is at VSync, and the note
\ there says why moving the picture down forced that.
  LDA #6  : STA CRTC_ADDR : LDA #PLAY_R6  : STA CRTC_DATA

\ R5 for the panel cycle, sampled at its end 12 scanlines from now.
\ Computed straight into the data register — sTmp belongs to
\ SetCRTCStart, which this interrupt can land in the middle of.
  LDA #5  : STA CRTC_ADDR
  SEC
  LDA #8
  SBC iline
  STA CRTC_DATA

\ R12/R13 for the play cycle, latched when it starts at P+64-line.
  LDA #12 : STA CRTC_ADDR : LDA crtcHi : STA CRTC_DATA
  LDA #13 : STA CRTC_ADDR : LDA crtcLo : STA CRTC_DATA

  LDA t1i3Lo : STA SYS_VIA_T1LL \ the HIGH byte is a variable, not the
  LDA t1i3Hi : STA SYS_VIA_T1LH \ constant: every screen that is not the
                                \ deck shows the 16th row by moving fire
                                \ 3 down a character row — see T1_I3X

\ The deck's palette, last of all — see the header. The panel stopped
\ displaying twelve scanlines ago and the play cycle is at least seven
\ away, so this whole window is free.
IF NOT(DEBUG_RASTER)
  JSR SetPalPlay
ENDIF

  LDA #1
  STA ruptState
  RTS

\ ---- fire 2, P+64: the visible top edge ---------------------
\ Must land in horizontal blanking — see T1_TUNE.
.rt_play
  LDA #8  : STA CRTC_ADDR
\ ---- THE TWO UNBLANKS ARE PATCHABLE (KC, 2026-08-31) --------
\ Coming out of the front end there is a window -- the rupture is
\ running, the deck is still loading, the first screen is not drawn --
\ in which the display shows IsBlank's cleared strip in whatever
\ palette the front end left, and the panel as the bare white box
\ FillPanel drew. KC: keep it blanked until the panel and the box are
\ drawn. So RuptAlign patches these two operands to R8_BLANK when it
\ starts the rupture, and IsArm (every information screen) and BrRun's
\ first page put them back to R8_ON.
\
\ AN OPERAND AND NOT A VARIABLE, because this one is fire 2 and fire 2
\ must land in horizontal blanking -- T1_TUNE's whole business. LDA abs
\ would move the write two cycles later; a patched immediate costs
\ nothing at all, here or at VSync.
.r2R8
  LDA #R8_ON     : STA CRTC_DATA
IF DEBUG_RASTER
  LDA deck                      \ restore this deck's real background
  ASL A : ASL A
  TAY
  LDA deckPalette,Y
  JSR DbgSetBg
ENDIF
\ R4 only. The play cycle's R5 goes at fire 3, well clear of the
\ panel cycle's vertical adjust, which ends within a scanline of
\ here. R4 is safe either side of that boundary: written during an
\ adjust it just sits waiting for the next cycle.
  LDA #4  : STA CRTC_ADDR : LDA #PLAY_R4 : STA CRTC_DATA

  LDA #2
  STA ruptState
  RTS

\ ---- fire 3, P+192: the visible bottom edge -----------------
\ The play area stops displaying exactly here, so this is both the
\ bottom blank and the earliest safe moment to release the main
\ loop. Deadline for the redraw is the play cycle starting again,
\ 184 scanlines away.
.rt_drawok
  LDA #8  : STA CRTC_ADDR : LDA #R8_OFF    : STA CRTC_DATA
IF DEBUG_RASTER
  LDA #4 : JSR DbgSetBg         \ blue from here down
ENDIF
\ R5 for the PLAY cycle, whose adjust is 8 scanlines away — close
\ enough to be this frame's, far enough not to be a knife edge.
  LDA #5  : STA CRTC_ADDR : LDA iline     : STA CRTC_DATA

\ R6 and R7 for the TAIL cycle, which starts in 2 rows. R7 must be
\ set here and not at VSync: by the time the tail reaches row 8 the
\ compare that generates VSync has already been made.
  LDA #6  : STA CRTC_ADDR : LDA #0        : STA CRTC_DATA
  LDA #7  : STA CRTC_ADDR : LDA #TAIL_R7  : STA CRTC_DATA

\ COUNT the window rather than flagging it. A flag is a boolean and
\ boolean state coalesces: work that runs past two of these sets it
\ twice and the loop can only see one, so it consumes a stale release
\ and then blocks for the next — turning a small overrun into a whole
\ extra field. A counter cannot lose one, and the loop compares
\ against it rather than consuming it. See WaitUntilField.
  INC fieldCount
  LDA #3
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

IF DEBUG_RASTER OR DEBUG_DRAW
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

\ Back to the deck's own background, ending whichever band was open.
.DbgDeckBg
  LDA deck
  ASL A : ASL A
  TAY
  LDA deckPalette,Y
  JMP DbgSetBg
ENDIF

\ ---- the panel READOUTS are not here any more ---------------
\ DbgFrameCount, DbgPosOut, DbgEnergyOut, the shared 4x5 digit font and
\ DbgHexDigit/DbgHexByte moved to src/dbgpanel.asm, which assembles into
\ BANK 6 beside the panel code they draw over. They cost 143 bytes of the
\ code image with DEBUG_VSYNC alone and there were eleven left; the GUARD
\ at FONT_ADDR in main.asm is what finally said so.
\ DbgSetBg and DbgDeckBg stay resident, and must: the blitter calls them
\ with a SPRITE bank paged in, so they cannot live in a bank at all.
