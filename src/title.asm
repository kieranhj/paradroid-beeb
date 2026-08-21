\ ============================================================
\ title.asm — the title screen, the PARTITL disc overlay
\ ============================================================
\ ShowTitle ($2879) copies Title_dat ($CC00) — a raw 40 x 25 character
\ screen — into screen RAM, colours it out of CharColor, and then waits
\ 256 frames or a press of fire before TitleLoop goes on to the intro
\ manual. The manual is deferred (§8 of docs/layer-11-sound-title.md);
\ what is here is the logo screen and the wait.
\
\ IT IS 25 ROWS ON A DISPLAY OF ITS OWN. [DECISION 2] The play area is
\ 16 rows under a 4-row panel, driven by the three-cycle rupture; the
\ title is neither, so the rupture is simply not up yet when this runs
\ and the CRTC is left in the plain single-cycle shape SetupMode gave
\ it, with R6 cut to 25 rows and R12/R13 pointed at TI_BASE. 25 x 640
\ is 16,000 bytes and the window ends 48 CRTC units short of MA12, so no
\ hardware wrap is involved at all.
\
\ WHERE THE 16,000 BYTES COME FROM: the title's buffers and the game's
\ never coexist. At title time no deck is loaded, so the sprite save
\ areas, the tile map, the panel and the play buffer are all idle — and
\ PARAFNT moved to &3000 in Layer 11 so that the only thing which WOULD
\ have been in the way sits below the framebuffer instead. §4 of the
\ layer document has the map.
\
\ THE GLYPHS ARE THE TITLE'S OWN, not the deck charset's, because twelve
\ of its thirty-six characters are not in the ported set — see the
\ header of tools/export_title.py, and [DECISION 8].
\
\ A DISC OVERLAY, NOT A BANK RESIDENT. Layer 13d restored [DECISION 6]:
\ this file assembles at TITLE_ADDR = &3000, over PARAFNT's ground, and
\ TitleSeq *LOADs it when the title is wanted — at boot, and again on
\ the way back from a game over — then reloads PARAFNT over it. The two
\ are never wanted at once. Everything here is main RAM, so there is no
\ paging anywhere in it; bank 7's free space went to the droid portrait
\ pool instead.

TI_BASE = &4000                 \ 25 rows x 640; ends &7E7F, clear of &8000
ASSERT TI_BASE + TITLE_COLS * TITLE_ROWS * 16 <= &8000
ASSERT (TI_BASE AND &07) == 0   \ CRTC addresses in 8-byte units

\ ---- zero page, borrowed ------------------------------------
\ The same argument xfer.asm's borrowing makes, and a stronger one: at
\ title time the deck, the level draw and the sprites do not merely
\ happen to be suspended, they have never run.
tisrc = src                     \ the RLE stream
tigs  = psrc                    \ the glyph being copied
tigd  = svp                     \ and where it lands

\ ============================================================
\ TiShow — the whole title, with this bank paged
\ ============================================================
.TiShow
  JSR TiPal
  JSR TiCRTC
  JSR TiPaint
  JMP TiWait                    \ and its RTS

\ ---- the palette, and why it is here now --------------------
\ [DECISION 9] said white on black "for now", on the grounds that the
\ title runs before any deck is loaded so MODE 1's DEFAULT palette gives
\ it that for free. That was true only because SetupMode's VDU 22 reset
\ the ULA on the way in. Layer 11f took the VDU 22 out of the game-over
\ path — it was clearing &3000-&7FFF and destroying the 999 page the
\ high-score entry draws on — so nothing resets the palette any more and
\ the title would come up in whatever colours the last deck left.
\ So the title states its own, which is what Layer 14 wants of every
\ screen anyway. The values ARE the OS's MODE 1 default: black, red,
\ yellow, white. Grouped four ULA entries to a logical colour, exactly
\ as palPanel is.
.TiPal
  LDX #15
.tipl_loop
  LDA tiPal,X
  STA VIDEO_ULA_PAL
  DEX
  BPL tipl_loop
  RTS

.tiPal
  PALENT  0, 0 : PALENT  1, 0 : PALENT  4, 0 : PALENT  5, 0
  PALENT  2, 1 : PALENT  3, 1 : PALENT  6, 1 : PALENT  7, 1
  PALENT  8, 3 : PALENT  9, 3 : PALENT 12, 3 : PALENT 13, 3
  PALENT 10, 7 : PALENT 11, 7 : PALENT 14, 7 : PALENT 15, 7

\ ---- the display -------------------------------------------
\ R6 sets the picture's height and R7 sets where it sits; R4 and R5 keep
\ the 39-row, 312-line, 50 Hz frame SetupMode set up.
\
\ THE TITLE HAS TO MOVE WITH THE GAME. The rupture's picture is placed by
\ FRAME_DROP_ROWS — see the note beside it in main.asm — and this display
\ is not the rupture, so nothing there reaches it. Aligned by arithmetic
\ rather than by eye:
\
\   game   VSync is TAIL_R7 rows into the 13-row tail cycle, and the
\          panel starts when that cycle ends, so the gap is
\          TAIL_CYC_ROWS - TAIL_R7  =  5 + FRAME_DROP_ROWS rows
\   title  VSync is at row R7 of a 39-row frame and the display starts
\          at row 0 of the next, so the gap is  39 - R7  rows
\
\ Equate them and R7 = 34 - FRAME_DROP_ROWS. At zero that is 34, which is
\ the OS's own MODE 1 value — which is exactly why the two pictures were
\ level before the game's moved, and why the title was left behind when
\ it did. This closes the "centring is R7's job" note that stood here.
\
\ THE 25-ROW PICTURE IS WHAT MAKES IT POSSIBLE. The OS leaves R6 at 32
\ with VSync at 34, two blank rows of headroom, so R7 could not drop far
\ without VSync landing inside the displayed rows. TITLE_ROWS is 25, so
\ there are fourteen — the ASSERT is what says so, and what will fail if
\ the title ever grows past the room its own sync leaves it.
\
\ VSYNC STILL HAPPENS, which matters more here than anywhere: TitleSeq
\ *LOADs PARAFNT and PARALOW AFTER this runs, and the MOS's disc code
\ spins forever in the 8271 poll without VSync. R7 = 31 is well inside a
\ 39-row frame, so the sync arrives every field exactly as before; it is
\ only the rupture's tail value that stops it. SetupRupture puts R7 back.
MODE1_R7 = 34                   \ what the OS leaves MODE 1 at
TITLE_R7 = MODE1_R7 - FRAME_DROP_ROWS
ASSERT TITLE_R7 >= TITLE_ROWS   \ VSync must fall after the last row shown

.TiCRTC
  CRTC 6, TITLE_ROWS
  CRTC 7, TITLE_R7
  CRTC 12, HI(TI_BASE / 8)
  CRTC 13, LO(TI_BASE / 8)
  RTS

\ ---- the picture -------------------------------------------
\ The 25 rows are 640 bytes each and contiguous, so the screen is one
\ linear run of 1,000 cells and the RLE never has to care about a row
\ end. A token below $80 is a literal glyph index; $80+n is a run of
\ n+1 cells whose index follows; $FF ends it.
.TiPaint
  LDA #LO(titleRLE) : STA tisrc
  LDA #HI(titleRLE) : STA tisrc+1
  LDA #LO(TI_BASE)  : STA tigd
  LDA #HI(TI_BASE)  : STA tigd+1

.tip_tok
  JSR TiNext
  CMP #&FF
  BEQ tip_done
  BPL tip_one                   \ $00-$7E: one cell of this index
  AND #&7F
  STA tiRun                     \ a run, and the index follows
  JSR TiNext
  JMP tip_run
.tip_one
  LDX #0
  STX tiRun
.tip_run
  STA tiIdx
.tip_cell
  JSR TiCell
  DEC tiRun
  BPL tip_cell                  \ tiRun counts n down through 0 to $FF,
  JMP tip_tok                   \ so a token of n paints n+1 cells
.tip_done
  RTS

\ A = the next stream byte, pointer advanced.
.TiNext
  LDY #0
  LDA (tisrc),Y
  INC tisrc
  BNE tin_x
  INC tisrc+1
.tin_x
  RTS

\ One cell of glyph tiIdx at tigd, which then advances. 36 glyphs of 16
\ bytes is 576, so the offset is 16-bit and cannot be done in A.
.TiCell
  LDA tiIdx
  STA tigs
  LDA #0
  STA tigs+1
  ASL tigs : ROL tigs+1
  ASL tigs : ROL tigs+1
  ASL tigs : ROL tigs+1
  ASL tigs : ROL tigs+1
  CLC
  LDA tigs   : ADC #LO(titleGlyphs) : STA tigs
  LDA tigs+1 : ADC #HI(titleGlyphs) : STA tigs+1
  LDY #15
.tic_copy
  LDA (tigs),Y
  STA (tigd),Y
  DEY
  BPL tic_copy
  CLC
  LDA tigd : ADC #16 : STA tigd
  BCC tic_x
  INC tigd+1
.tic_x
  RTS

\ ---- the wait ----------------------------------------------
\ $2907-$291F: read the joystick, and go on when fire is pressed or the
\ frame count wraps. Ours counts iterations rather than frames — there
\ is no IRQ yet at boot, so there is nothing to count fields with — and
\ a 16-bit wrap comes out at a few seconds, which is the same order as
\ the original's 256 frames.
\
\ THE TIMEOUT IS NOT DECORATION. It is the original's own behaviour and
\ it is also the escape hatch: a title that could only be left by a
\ keypress would be a title that a mis-read key turns into a hang.
\
\ AND IT IS WHERE THE RANDOMNESS COMES FROM. $12B6 samples $D41B after
\ however long the player left the title up, which is what makes the
\ starting deck unpredictable; drSeed is stirred from this counter by
\ GameStart, in bank 4 where the LFSR lives.
\
\ keydown is main RAM and goes through OSBYTE, which pages the OS ROM in
\ and restores from ROMSHAD — which UnpackBankIn keeps honest, and which
\ is why the main loop can call it with a bank up too.
.TiWait
  LDA #0
  STA tiLo
  STA tiHi
.tiw_loop
  LDX #KEY_L
  JSR keydown
  BEQ tiw_done                  \ Z set: fire is down
  INC tiLo
  BNE tiw_loop
  INC tiHi
  BNE tiw_loop
.tiw_done
  LDA tiLo                      \ hand the dwell out for the seed
  EOR tiHi
  STA overRnd0
  RTS

.tiIdx  EQUB 0
.tiRun  EQUB 0
.tiLo   EQUB 0
.tiHi   EQUB 0
