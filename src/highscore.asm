\ ============================================================
\ highscore.asm — DoHighScore ($E4E5), in SWRAM bank 7
\ ============================================================
\ LAYER 11f. The C64's flow is
\
\   EndGame ($378B) ──> $3812 j_DoHighScore ──> JMP TitleLoop
\
\ so this runs in exactly one place: after the 999 page's hold, before
\ the title. TitleSeq calls HsEntry, which is in the PARTITL overlay.
\
\ WHY IT WAS AN OVERLAY, WHICH TOOK THREE ATTEMPTS TO GET RIGHT — and
\ it is bank 7's now instead (no-load step 3, below). That does not
\ undo any of the argument: SetupPlain is still what makes the screen
\ possible at all, and it is now ALSO what keeps PARAFNT alive under
\ it, which is what lets the glyphs be textfont's.
\ KC, twice: this is outside the game, so it should not be spending
\ resident MAIN RAM. Two things stood in the way and both turned out
\ to be removable:
\
\  1. The rupture stops VSync, so no filing-system call can load
\     anything while the 999 page is up.
\  2. GoTitle's SetupMode began with a VDU 22, and the OS answers that
\     by clearing &3000-&7FFF — taking the page and the font with it.
\
\ SetupPlain (screen.asm, bank 4) replaced the VDU 22 with the six CRTC
\ registers it was really there for. **The play buffer now survives the
\ teardown**, so the page is still on screen at the moment a load
\ becomes legal, and this could be an overlay after all. Measured in
\ jsbeeb: the 999 page displays, unruptured, while PARTITL loads.
\
\ AND THAT WHOLE ARGUMENT IS HISTORY AS OF 2026-09-09, though the
\ conclusion stands. There is no load between the 999 page and this
\ screen any more, so GoTitle no longer tears the rupture down in
\ front of it and SetupPlain no longer runs before it: HsEntry
\ inherits the rupture the game over left up, draws on it, and does
\ the teardown ITSELF on the way out, for the title. **SetupPlain is
\ not what makes this screen possible any more - it is what closes
\ it.** docs/no-load.md 20 has the seam and the measurement.
\
\ WHAT IT COSTS IN MAIN RAM: three bytes, TitleSeq's JSR, and that has
\ not changed through either arrangement. The screen itself is ~570
\ bytes of bank 7 now rather than ~655 bytes of a disc overlay, beside
\ the twenty-five of hstable.asm it already had to be near.
\
\ IT CARRIED ITS OWN ALPHABET UNTIL 2026-09-07, and no-load step 3 is
\ what ended that: PARTITL used to be assembled over the text font's
\ ground, so the screen brought 72 glyphs of its own — and all 72 were
\ byte-identical to glyphs already in textfont. The overlay is at &0900
\ now, the font survives the title, and what is left is a 72-byte remap
\ in src/data/hsremap.asm. See HsGlyph, and tools/export_hsremap.py for
\ the identity check that runs every build.
\
\ THE PRECONDITION THAT REPLACED THE ALPHABET: PARAFNT MUST BE RESIDENT
\ WHENEVER THIS RUNS. It is — HsEntry only calls HsRun when hsArmed is
\ set, which only a finished game sets, and GoTitle reaches TitleSeq
\ through SetupPlain rather than SetupMode precisely so that the VDU 22
\ does not clear &3000-&7FFF. A cold boot never gets here.
\
\ AND THIS FILE IS IN BANK 7 NOW, everything below HsEntry — which
\ stayed behind in the title overlay, because TitleSeq calls it from
\ main RAM. HsEntry has always paged SWRAM_XFER around the whole
\ screen, so nothing here needed a trampoline: it calls FontCell,
\ keydown, score and textfont out in main RAM, which bank code may do.
\ FontCell is not duplicated and never was: it lives in the PARAFNT
\ file, so the 1bpp → MODE 1 expansion is the game's own routine.
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
\ EVERY INITIAL IS TWO CELLS WIDE HERE, and that is not the original's
\ (layer-11f DECISION 18, issue #17 from hexwab's #4, KC 2026-09-10).
\ $E6E8 is a six-character record drawn as one string: a capital is
\ SIXTEEN pixels and the dot and the space eight, so the dots slid right
\ as each letter replaced one, and three trailing spaces covered the
\ debris when a wide letter gave way to a narrow one. HsShow draws the
\ three slots at fixed columns instead, padding anything narrow -- the
\ dot, the space, capital I -- with a space, so no slot ever moves.
\
\ WHAT REPLACES THE JOYSTICK. $E574 reads `joyYDir ORA joyXDir` so
\ either axis walks the alphabet, and $094D makes UP -1: up goes
\ BACKWARDS. K and M are the port's up and down, so K steps back and M
\ steps on, which is the original's direction and not a coin toss.
\
\ AND THERE IS NO CapitalAlpha_t. The C64 needs a 27-byte table because
\ its capitals are not contiguous — capital I lives at $16, outside the
\ alphabet's run. export_hsremap.py has already straightened that out, so
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
\ REMEMBERED BEFORE THEY ARE FILED, and for both ends of the table:
\ what the next entry starts from is what you last typed, not what the
\ high score happens to hold. [DECISION 4]
  LDX #2
.hs_c_prev
  LDA hsSelFor,X : STA hsPrev,X
  DEX : BPL hs_c_prev

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
  LDX hsIdx                     \ $E56F starts every initial at 'A'; Redux
  LDA hsPrev,X                  \ starts it at the one you typed last time,
  STA hsSelFor,X                \ layer-12 [DECISION 4]. hsPrev is bank 7's
  JSR HsPut                     \ and assembles as zero, so the first entry
                                \ of a session is still 'A' -- see hstable.asm

.hs_g_loop
  JSR HsShow
  JSR HsWait

\ The index is carried in A through both arms and stored once.
  LDX keyTab+CTL_DOWN                    \ down: $0954's +1, on through the alphabet
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
  LDX keyTab+CTL_UP                    \ up: $094D's -1, backwards
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
  LDX keyTab+CTL_FIRE                    \ $E59E: fire commits this initial
  JSR keydown
  BNE hs_g_loop
.hs_g_rel
  LDX keyTab+CTL_FIRE                    \ $E5A2: and then wait for the release
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
  LDA #0
  STA hsSlot
.hs_sh_slot
  LDA hsSlot                    \ slot n starts at HS_COL_INI + 2n,
  ASL A                         \ whatever the slots before it hold
  CLC
  ADC #HS_COL_INI
  TAX
  LDA #HS_ROW_BOT
  JSR HsAt
  LDX hsSlot
  LDA hsIni,X
  PHA
  JSR HsWide                    \ a wide capital fills both cells
  PLA
  CMP #HS_UPPER_I               \ HsWide's own narrow test, for the
  BEQ hs_sh_pad                 \ glyphs a slot can hold: I, and
  CMP #HS_UPPER_R               \ anything past the capitals -- the
  BCC hs_sh_next                \ dot and the space
.hs_sh_pad
  LDA #HS_SPACE                 \ the second cell, blanked: it covers
  JSR HsGlyph                   \ the right half of whatever was here
.hs_sh_next
  INC hsSlot
  LDA hsSlot
  CMP #3
  BCC hs_sh_slot
  RTS

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
\ THE GLYPHS ARE textfont's NOW, THROUGH hsRemap (no-load step 3).
\ This screen carried its own 72-glyph alphabet until PARTITL came off
\ &3000, because the text font was the thing PARTITL was loaded over.
\ All 72 were byte-identical to glyphs already in textfont -- permuted,
\ which is why a block diff missed them -- so what is left is a 72-byte
\ remap and these four bytes. tools/export_hsremap.py re-derives both
\ tables from the C64 listing every run and compares all 1,152 bytes.
\ A IS AN INDEX IN THIS SCREEN'S SPACE, not textfont's, and it must
\ stay that way: HsWide does every one of its tests and its wide-half
\ arithmetic (CMP #HS_UPPER_R, ADC #HS_UPPER_R, the HS_LOWER_M and
\ HS_W_RIGHT sentinels) before it gets here, so the translation has to
\ be the LAST thing that happens to the index.
\ X IS DESTROYED, and was already: FontCell is called twice below.
.HsGlyph
  TAX
  LDA hsRemap,X
  STA swSrc
  LDA #0
  STA swSrc+1
  ASL swSrc : ROL swSrc+1       \ * 16 — two 8-byte packed cells
  ASL swSrc : ROL swSrc+1
  ASL swSrc : ROL swSrc+1
  ASL swSrc : ROL swSrc+1
  CLC
  LDA swSrc   : ADC #LO(textfont) : STA swSrc
  LDA swSrc+1 : ADC #HI(textfont) : STA swSrc+1

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
\ DrawChar's own test, and export_hsremap.py's header has the why: the
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
\ $E6E8's three initials. Its three trailing spaces are gone: they
\ covered the shrink of a one-string field, and HsShow's slots do not
\ shrink (DECISION 18).
.hsIni
  EQUB 0, HS_DOT, HS_DOT

.hsSelFor EQUB 0, 0, 0          \ xfer_cpuSpriteX, one per initial: the
                                \ LETTER index 0-26, which is what goes
                                \ into the table
.hsWhich  EQUB 0                \ 0 the high score, 1 the low
.hsIdx    EQUB 0                \ currentIdx
.hsIx     EQUB 0
.hsTmp    EQUB 0
.hsTmp2   EQUB 0
.hsSlot   EQUB 0                \ HsShow's slot, 0-2
