\ ============================================================
\ ruptalign.asm — hand the display over to the rupture WITHOUT
\ a short field
\ ============================================================
\ LIVES IN BANK 5, and only because of size: it wants ~50 bytes of
\ code that no other bank has room for, the code image has four, and
\ PARBRF (where the first version lived) has two. The bank the blitter
\ is in is resident and valid on every route into ts_loads -- boot,
\ the briefing exits, and the game-over seam all have PARASPR up. It
\ is called with the bank paged in and pages the data bank back itself.
\
\ ============================================================
\ THE PROBLEM, and why the first two attempts did not fix it
\ ============================================================
\ The rupture's 312-line frame is three CRTC cycles -- panel 7 rows,
\ play 18, tail 13 -- and VSync happens TAIL_R7 = 5 rows into the tail.
\ A CRTC left free-running in the tail's shape therefore VSyncs every
\ 13 rows: 104 lines, not 312. So the instant SetupRupture writes the
\ tail shape, the NEXT VSync is early, and the display rolls until the
\ IRQ has taken over and restored the three-cycle structure.
\
\ ROUND 1 (2026-08-31) wrote the shape wherever the main loop happened
\ to be, and R4 = TAIL_R4 = 12 landed behind the row counter about
\ three times in four: the 6845 ran on toward its wrap and the field
\ came out 384 lines. Measured: 300, 384 and 48-line fields.
\ ROUND 2 waited for VSync and spun out the rest of the frame so the
\ writes landed at row 0-1, where R4 = 12 is ahead of the counter.
\ That fixed the wrap -- every field 39,93x in jsbeeb -- and KC still
\ saw the picture displaced on b2, which is the more exact 6845. Of
\ course: an aligned write still starts a 13-row cycle at line 64, so
\ its VSync arrives 104 lines after the last one. jsbeeb does not show
\ that; b2 does; ref/beeb-paradroid-to-001-resync.png is what it looks
\ like.
\
\ ============================================================
\ WHAT THIS DOES
\ ============================================================
\ Suppress VSync until the cycle that ends up in the right place, and
\ let the first one the handler sees arrive exactly 312 lines after the
\ last one the old frame produced. Lines are counted from that VSync:
\
\    0      VSync of the last plain frame (row PLAIN_R7 = 31 of 39)
\   64      the plain frame ends; a fresh one starts
\   ~80     we land here: OSBYTE 19 + a spin of 8 rows. SetupRupture
\           writes the tail shape, and R7 = 255 goes straight over its
\           R7 so this cycle and the next fire no VSync at all
\   64-168  cycle A, 13 rows
\  168-272  cycle B, 13 rows.  R7 = TAIL_R7 goes in at ~240, PAST its own
\           row 5 at line 216, so it cannot fire a VSync in B itself
\  272-376  cycle C, 13 rows -- and its row 5 is line 312, EXACTLY one
\           frame after the VSync at 0. The handler is installed by
\           then and takes it as an ordinary tail-cycle VSync
\
\ So the display sees one unbroken 312-line field across the handover,
\ and the IRQ inherits the phase the steady state expects: C4 = 5 in a
\ 13-row cycle, which is what RuptVSync's own header assumes.
\
\ THE R7 = TAIL_R7 WRITE LANDS LATE IN CYCLE B ON PURPOSE, and that is
\ round four (KC's ref/beeb-paradroid-to-001-resync3.png: the panel down
\ at the bottom of the screen, so MORE displaced than round three, not
\ less). It went in at ~line 180 before, which is cycle B's row 1 -- and
\ whether that fires a VSync in B or only in C depends on something this
\ port has a measured rule for and the emulators evidently disagree on:
\ "R6, R7 and R12/R13 must be written during the PREVIOUS cycle". If the
\ write takes effect in the cycle it is made in, R7 = 5 at row 1 fires
\ VSync at B's own row 5, line 208 -- a 208-line field, then a 104-line
\ one when C fires too. Which is exactly a picture displaced further.
\ So put it past row 5 of cycle B (line 216) and the two readings agree:
\ too late to match in B, in time to be latched for C. ~line 240 leaves
\ 32 lines of slack behind it and 72 in front.
\ THE MARGINS ARE ROWS, NOT CYCLES. The R7 = 255 write has ~20 lines
\ to beat the row-5 compare, and the R7 = TAIL_R7 write has the whole
\ of cycle B, 104 lines, to land in. InstallIrq follows immediately and
\ needs only to be armed before line 312, which is 130 lines away.
\ The display is blanked throughout (R6 = 0 and R8_BLANK), so none of
\ the intermediate cycles show anything.
\
\ HsEntry STILL CALLS SetupRupture DIRECTLY and is not aligned: it is
\ a front-end screen that comes and goes, this bank is paged out under
\ it, and nobody has complained about that seam.
.RuptAlign
  LDA #19
  JSR OSBYTE                    \ returns just after the VSync at row 31

  LDX #8                        \ ~10,250 cycles: the 64 lines left in the
  JSR raDelay                   \ old frame, and two rows into the new one

  JSR SetupRupture              \ main RAM; the tail shape, R12/R13 and
                                \ RuptInit -- and its own R7 = TAIL_R7,
                                \ which the next four instructions cancel
                                \ before the row counter can reach it
  LDA #7  : STA CRTC_ADDR
  LDA #255 : STA CRTC_DATA      \ no VSync in cycle A or cycle B

  LDX #16                       \ ~20,500 cycles: into cycle B, and PAST
  JSR raDelay                   \ ITS OWN ROW 5 -- see the note below

  LDA #7  : STA CRTC_ADDR
  LDA #TAIL_R7 : STA CRTC_DATA  \ cycle C fires VSync at line 312

\ ---- and the display stays off until there is something on it
\ KC, 2026-08-31: the rupture starts here, but the deck is still to
\ load and the first screen still to draw, so what it would show is
\ IsBlank's cleared strip in the front end's palette and the panel as
\ a bare white box. Patch the IRQ's two unblanks to R8_BLANK -- see
\ rupture.asm at r2R8 -- and let IsArm or BrRun's first page put them
\ back when there is a picture worth showing.
  LDA #R8_BLANK
  STA rvR8+1
  STA r2R8+1

  JMP PgData                    \ the data bank is the resting state, and
                                \ this is main RAM so it can page us out;
                                \ its RTS is ours

\ X = 1,280-cycle units, and it is a subroutine because there are two
\ of them and this bank is not short of anything except reasons.
.raDelay
  LDY #0
.rad_in
  DEY
  BNE rad_in
  DEX
  BNE raDelay
  RTS
