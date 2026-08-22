\ ============================================================
\ highscore.asm — DoHighScore ($E4E5), in the title overlay
\ ============================================================
\ LAYER 11f. The C64's flow is
\
\   EndGame ($378B) ──> $3812 j_DoHighScore ──> JMP TitleLoop
\
\ so this runs in exactly one place: after the 999 page's hold, before
\ the title. TitleSeq calls HsEntry with PARTITL just loaded.
\
\ WHY IT IS AN OVERLAY, WHICH TOOK THREE ATTEMPTS TO GET RIGHT.
\ KC, twice: this is outside the game, so it should not be spending
\ resident RAM. Two things stood in the way and both turned out to be
\ removable:
\
\  1. The rupture stops VSync, so no filing-system call can load
\     anything while the 999 page is up.
\  2. GoTitle's SetupMode began with a VDU 22, and the OS answers that
\     by clearing &3000-&7FFF — taking the page and the font with it.
\
\ SetupPlain (screen.asm, bank 4) replaced the VDU 22 with the six CRTC
\ registers it was really there for. **The play buffer now survives the
\ teardown**, so the page is still on screen at the moment a load
\ becomes legal, and this can be an overlay after all. Measured in
\ jsbeeb: the 999 page displays, unruptured, while PARTITL loads.
\
\ WHAT IT COSTS RESIDENT: twenty-five bytes of bank 7 for the table
\ (hstable.asm — it has to remember between games) and three bytes of
\ main RAM for TitleSeq's JSR. Nothing else.
\
\ AND IT CARRIES ITS OWN ALPHABET, because PARTITL is assembled over the
\ text font's ground. src/data/hsfont.asm, generated — the same answer
\ the title screen already gives for its own 36 characters, layer-11
\ [DECISION 8]. What it does NOT duplicate is FontCell: that lives at
\ the top of the PARAFNT file, ABOVE this overlay's end, so the 1bpp →
\ MODE 1 expansion is the game's own routine. The ASSERT on titl_end in
\ main.asm is what keeps it that way.
\
\ IT SPINS, and that is the original's shape rather than the port's.
\ Every other modal screen here is a per-pass tick because the game is
\ running under it; this one runs when the game is over and the main
\ loop has already stopped, so GetInitial's two busy-waits port across
\ as busy-waits.
\
\ THE SCREEN IS THE 999 PAGE, NOT CLEARED. $E51D and $E524 draw straight
\ over it, and the original's own layout is what makes that legible:
\
\   "Great Score!"                row 10 col 13  over "Transmission" (12 at 13)
\   "Lowest Score of the Day!"    row 10 col  5  over the same, and wider
\   "Please enter your initials -" row 22 col 1  over "Terminated"  (10 at 14)
\
\ Both replacements cover what they land on, so no clear is needed and
\ none is done. C64 rows 10 and 22 are this port's buffer rows 1 and 13
\ — the two IsOverDraw already used — because the page is drawn on the
\ database table's lines and that table starts on buffer row 1.
\
\ THE INITIALS FIELD IS SIX CHARACTERS AND ONLY THREE ARE ENTERED. That
\ is the original's ($E6E8 is a six-character record) and it is not
\ padding: a capital is SIXTEEN pixels and a space is eight, so when a
\ wide letter is replaced by a space every character after it shifts one
\ cell left. The three trailing spaces are what covers the debris.
\
\ WHAT REPLACES THE JOYSTICK. $E574 reads `joyYDir ORA joyXDir` so
\ either axis walks the alphabet, and $094D makes UP -1: up goes
\ BACKWARDS. K and M are the port's up and down, so K steps back and M
\ steps on, which is the original's direction and not a coin toss.
\
\ AND THERE IS NO CapitalAlpha_t. The C64 needs a 27-byte table because
\ its capitals are not contiguous — capital I lives at $16, outside the
\ alphabet's run. export_hsfont.py has already straightened that out, so
\ index 0-25 IS the glyph and 26 is a space, by arithmetic.

HS_LETTERS  = 27                \ $E57D's #$1B: A-Z and a space
HS_SPACE_IX = 26

\ $E599 passes DelayScore(#$40) and the C64 runs at ~1 MHz; this runs at
\ 2, so the same count would step the alphabet twice as fast. Measured
\ in jsbeeb before the doubling: six letters in fourteen fields, against
\ the original's twelve a second. The conversion IS_HOLD took.
HS_DELAY    = &80

HS_INK      = &FF               \ logical 3: both colour planes set, which
                                \ is white under the port's fixed slot
                                \ roles. IsOverDraw's two words are drawn
                                \ in it and these replace them

HS_ROW_TOP  = 1                 \ C64 row 10, the name line
HS_ROW_BOT  = 13                \ C64 row 22, the last content line
HS_COL_GREAT  = 13              \ $E733's prntX
HS_COL_LOWEST = 5               \ $E742's
HS_COL_PROMPT = 1               \ $E714's
HS_COL_INI    = 31              \ $E6E8's

\ ============================================================
\ HsEntry — TitleSeq's door
\ ============================================================
\ Bank 7 holds the table AND the arm flag, so one paging pair covers the
\ whole screen; nothing in here wants bank 4. At boot hsArmed is zero —
\ the assembled value — so the sequence runs straight through.
\ AND IT WEARS THE GAME'S OWN FRAME (KC, 2026-08-22): the entry used
\ to run on SetupPlain's bare strip — no header. The rupture gives the
\ 4-row panel, the gap and the 16-row window for free, and it is legal
\ here because HsRun makes no filing call: loadtitl is done, the next
\ load is TiShow's, and the teardown below restores VSync first. The
\ panel still holds the finished game's box — Mobile, logo, the final
\ score — which is exactly the right header for this screen. The IRQ
\ must come with it (the rupture is IRQ-driven), and that is safe with
\ the low overlay absent: the handler and its sound shim live in the
\ code image and page bank 4 for themselves.
.HsEntry
  PAGEBANK SWRAM_XFER
  LDA hsArmed
  BEQ hs_en_x
  LDA #0
  STA hsArmed
  JSR SetupRupture              \ panel + gap + window; scroll is parked
  JSR InstallIrq
  JSR HsRun
  JSR UninstallIrq              \ and back to a frame with VSync, BEFORE
  PAGEBANK SWRAM_DATA           \ the title's loads — SetupPlain is
  JMP SetupPlain                \ bank 4's, so the data bank first. Its
                                \ frame is BLANK (R6 = 0 in its table)
                                \ until TiCRTC shows the title — and RTS
.hs_en_x
  PAGEBANK SWRAM_DATA
  RTS

\ ============================================================
\ HsRun — $E4E5: the test, and the screen if it passes
\ ============================================================
\ The compares are MSB-first over four BCD bytes, which is the whole of
\ $E4EF-$E50E. Equal to the high score falls through to the low test and
\ equal to that returns — a score has to BEAT one end or the other.
.HsRun
  LDX #0
.hs_hi_l
  LDA score,X
  CMP hsHigh,X
  BCC hs_trylow
  BNE hs_ishigh
  INX
  CPX #4
  BCC hs_hi_l

.hs_trylow
  LDX #0
.hs_lo_l
  LDA score,X
  CMP hsLow,X
  BEQ hs_lo_n
  BCC hs_islow
  RTS                           \ $E508: between the two, and no screen
.hs_lo_n
  INX
  CPX #4
  BCC hs_lo_l
  RTS                           \ $E50E: it only EQUALS the low score

.hs_ishigh
  LDX #3                        \ $E50F-$E518
.hs_cph
  LDA score,X : STA hsHigh,X
  DEX : BPL hs_cph
  LDA #0
  STA hsWhich
  LDX #HS_COL_GREAT
  LDA #HS_ROW_TOP
  JSR HsAt
  LDA #LO(hsTxtGreat) : LDY #HI(hsTxtGreat)
  JSR HsStr
  JMP hs_prompt

.hs_islow
  LDX #3                        \ $E546-$E54F
.hs_cpl
  LDA score,X : STA hsLow,X
  DEX : BPL hs_cpl
  LDA #1
  STA hsWhich
  LDX #HS_COL_LOWEST
  LDA #HS_ROW_TOP
  JSR HsAt
  LDA #LO(hsTxtLowest) : LDY #HI(hsTxtLowest)
  JSR HsStr

.hs_prompt
  LDX #HS_COL_PROMPT            \ $E520/$E557: the prompt, always the same
  LDA #HS_ROW_BOT
  JSR HsAt
  LDA #LO(hsTxtEnter) : LDY #HI(hsTxtEnter)
  JSR HsStr

\ ---- $E536: three initials, and then it is over -------------
\ $E4E7 sets the second and third slots to full stops; $E56D starts every
\ initial at index 0, which is 'A', so the slot being entered always
\ shows a letter and the ones after it show dots.
  LDA #HS_DOT
  STA hsIni+1
  STA hsIni+2
  LDA #0
  STA hsIdx
.hs_next
  JSR HsGet
  INC hsIdx
  LDA hsIdx
  CMP #3
  BCC hs_next

\ ---- $E52A/$E561: the initials into the table ---------------
\ The C64 hands them to UpdateTextScore, which writes them into the
\ briefing text. The port's briefing does not exist yet and its text
\ will be an overlay reloaded every time, so the table is written here
\ and the briefing's score page will read it. [11f DECISION 7]
  LDX #2
  LDA hsWhich
  BNE hs_c_low
.hs_c_hi
  LDA hsSelFor,X : STA hsHiIni,X
  DEX : BPL hs_c_hi
  RTS
.hs_c_low
  LDA hsSelFor,X : STA hsLoIni,X
  DEX : BPL hs_c_low
  RTS

\ ============================================================
\ HsGet — GetInitial ($E56D)
\ ============================================================
\ $E571-$E5A0 is the walk and $E5A2-$E5A8 the release.
.HsGet
  LDX hsIdx                     \ $E56F: every initial starts at 'A'
  LDA #0
  STA hsSelFor,X
  JSR HsPut

.hs_g_loop
  JSR HsShow
  JSR HsWait

\ The index is carried in A through both arms and stored once.
  LDX #KEY_M                    \ down: $0954's +1, on through the alphabet
  JSR keydown                   \ Z set = the key is DOWN
  BNE hs_g_up
  LDX hsIdx
  LDA hsSelFor,X
  CLC
  ADC #1
  CMP #HS_LETTERS
  BCC hs_g_set
  LDA #0                        \ $E581
  BEQ hs_g_set                  \ always

.hs_g_up
  LDX #KEY_K                    \ up: $094D's -1, backwards
  JSR keydown
  BNE hs_g_fire
  LDX hsIdx
  LDA hsSelFor,X
  SEC
  SBC #1
  BPL hs_g_set
  LDA #HS_LETTERS-1             \ $E585

.hs_g_set
  LDX hsIdx
  STA hsSelFor,X
  JSR HsPut

.hs_g_fire
  LDX #KEY_L                    \ $E59E: fire commits this initial
  JSR keydown
  BNE hs_g_loop
.hs_g_rel
  LDX #KEY_L                    \ $E5A2: and then wait for the release
  JSR keydown
  BEQ hs_g_rel
  RTS

\ ---- the letter index into the display record ---------------
\ CapitalAlpha_t, by arithmetic: HS_UPPER is 0, so a letter index IS its
\ glyph, and 26 is the space on the end of the C64's table.
.HsPut
  LDX hsIdx
  LDA hsSelFor,X
  CMP #HS_SPACE_IX
  BCC hs_p_letter
  LDA #HS_SPACE
.hs_p_letter
  STA hsIni,X
  RTS

\ ============================================================
\ HsShow / HsWait — $E592's redraw, and $E599's delay
\ ============================================================
.HsShow
  LDX #HS_COL_INI
  LDA #HS_ROW_BOT
  JSR HsAt
  LDA #LO(hsIni) : LDY #HI(hsIni)
  JMP HsStr                     \ and its RTS

.HsWait
  LDY #HS_DELAY
.hs_w_y
  LDX #0
.hs_w_x
  DEX
  BNE hs_w_x
  DEY
  BNE hs_w_y
  RTS

\ ============================================================
\ The plotter — DbGlyph's shape, on this overlay's alphabet
\ ============================================================
\ The buffer is a flat 16 x 640 array here: IsStart parked the scroll
\ before it drew the 999 page and nothing has moved it since. So a cell
\ is BUF_BASE + row*640 + col*16, and a glyph is two of them, one row
\ apart — which is exactly what FontCell expands, eight source bytes at
\ a time.
\
\   A = row, X = column
.HsAt
  TAY
  LDA hsRowLo,Y : STA swDst
  LDA hsRowHi,Y : STA swDst+1
  TXA                           \ col * 16, split
  ASL A : ASL A : ASL A : ASL A
  STA hsTmp
  TXA
  LSR A : LSR A : LSR A : LSR A
  STA hsTmp2
  CLC
  LDA swDst   : ADC hsTmp  : STA swDst
  LDA swDst+1 : ADC hsTmp2 : STA swDst+1
  RTS

\ A = glyph index. Draws one cell column and steps on.
.HsGlyph
  STA swSrc
  LDA #0
  STA swSrc+1
  ASL swSrc : ROL swSrc+1       \ * 16 — two 8-byte packed cells
  ASL swSrc : ROL swSrc+1
  ASL swSrc : ROL swSrc+1
  ASL swSrc : ROL swSrc+1
  CLC
  LDA swSrc   : ADC #LO(hsGlyphs) : STA swSrc
  LDA swSrc+1 : ADC #HI(hsGlyphs) : STA swSrc+1

  LDA #HS_INK
  STA fontMask
  JSR FontCell                  \ the top cell

  CLC                           \ the bottom cell, one character row on
  LDA swDst   : ADC #LO(ROW_BYTES) : STA swDst
  LDA swDst+1 : ADC #HI(ROW_BYTES) : STA swDst+1
  CLC
  LDA swSrc   : ADC #8 : STA swSrc
  LDA swSrc+1 : ADC #0 : STA swSrc+1

  JSR FontCell

  SEC                           \ back up, then on to the next column
  LDA swDst   : SBC #LO(ROW_BYTES - 16) : STA swDst
  LDA swDst+1 : SBC #HI(ROW_BYTES - 16) : STA swDst+1
  RTS

\ ---- WIDE IS NOT THE SAME AS CAPITAL -----------------------
\ DrawChar's own test, and export_hsfont.py's header has the why: the
\ wide set is the capitals minus I, plus lowercase m and w.
.HsWide
  CMP #HS_LOWER_M
  BEQ hs_w_m
  CMP #HS_LOWER_W
  BEQ hs_w_w
  CMP #HS_UPPER_R               \ 26: above it is not a capital
  BCS hs_w_one
  CMP #HS_UPPER_I
  BEQ hs_w_one
  PHA
  JSR HsGlyph
  PLA
  CLC
  ADC #HS_UPPER_R
.hs_w_one
  JMP HsGlyph
.hs_w_m
  JSR HsGlyph
  LDA #HS_M_RIGHT
  JMP HsGlyph
.hs_w_w
  JSR HsGlyph
  LDA #HS_W_RIGHT
  JMP HsGlyph

\ A = string low, Y = string high. Glyph indices, $FF terminated.
.HsStr
  STA hs_s_get+1
  STY hs_s_get+2
  LDA #0
  STA hsIx
.hs_s_loop
  LDY hsIx
.hs_s_get
  LDA &FFFF,Y
  CMP #&FF
  BEQ hs_s_x
  JSR HsWide
  INC hsIx
  BNE hs_s_loop
.hs_s_x
  RTS

\ ---- the row bases -----------------------------------------
.hsRowLo
  FOR n, 0, 15
    EQUB LO(BUF_BASE + n * ROW_BYTES)
  NEXT
.hsRowHi
  FOR n, 0, 15
    EQUB HI(BUF_BASE + n * ROW_BYTES)
  NEXT

\ ---- state, all of it this overlay's ------------------------
\ $E6E8: three initials and the three spaces that cover their shrink.
.hsIni
  EQUB 0, HS_DOT, HS_DOT, HS_SPACE, HS_SPACE, HS_SPACE, &FF

.hsSelFor EQUB 0, 0, 0          \ xfer_cpuSpriteX, one per initial: the
                                \ LETTER index 0-26, which is what goes
                                \ into the table
.hsWhich  EQUB 0                \ 0 the high score, 1 the low
.hsIdx    EQUB 0                \ currentIdx
.hsIx     EQUB 0
.hsTmp    EQUB 0
.hsTmp2   EQUB 0
