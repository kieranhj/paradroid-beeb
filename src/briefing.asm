\ ============================================================
\ briefing.asm — the briefing driver, the PARBRF overlay at &0400
\ ============================================================
\ LAYER 11f. The intro manual: the five-page briefing the C64 title
\ falls into on a timeout ($1184-$123F), rendered from the record lists
\ in bank 5 (PARMAN, src/data/briefing.asm) instead of the C64's 15.5 K
\ canvas. docs/layer-11f-frontend.md is the plan; §3 is this screen.
\
\ WHY &0400: outside a game, &0400-&0C90 — the MODE 1 charset — holds
\ nothing anyone wants. It is built at deck load and GameStart ->
\ LoadDeck rebuilds it before anything reads it again, so at title and
\ briefing time it is 2,192 bytes of free lower RAM, loaded into
\ directly by *LOAD (KC, 2026-08-22: it is language workspace, no
\ language is resident, and DFS writes into it no problem). PARBRF is
\ loaded by TiShow on EVERY title, so its entry points are always valid
\ when the dispatch below can be reached; it dies at the next deck load
\ and is reloaded at the next title.
\
\ WHY THE DRIVER IS MAIN RAM AND THE TEXT IS A BANK: the driver has to
\ page — bank 5 for the text, bank 7 for the page-5 portrait to come,
\ the data bank for the rebuild — and code cannot page itself out.
\ Bank 5 is evicted for the briefing [DECISION 4]: no sprite runs on a
\ modal screen, so 16 K of compiled blitter has no business being
\ resident, and both exits reload it below.
\
\ THE SCREEN IS THE GAME'S OWN: the rupture, the panel, the strip. The
\ briefing runs after ts_loads has rebuilt all of it, in exactly the
\ environment GameStartInfo would inherit, and scribbles only on ground
\ GameStart and LoadDeck rebuild.
\
\ ZERO PAGE, BORROWED: swSrc/swDst are FontCell's own interface, and
\ chp walks the record lists — the level draw's charset pointer, idle
\ outside a game. The rupture IRQ and the sound tick touch none of them
\ (checked 2026-08-22: no swSrc/swDst/chp in rupture.asm or sound.asm).
brp = chp                       \ record-list walk pointer

\ What BrRun hands back to BrDispatch.
BR_EXIT_FIRE  = 0               \ fire: start the game
BR_EXIT_OFF   = 1               \ off the end of the last page: the title

\ ============================================================
\ BrTimeout — TiWait timed out: fetch the text, mark the turn
\ ============================================================
\ Reached by JMP from TiWait's wrap, with TiShow's return address on
\ the stack — so the RTS here lands at TitleSeq's ts_loads exactly as
\ TiWait's own RTS would have. Runs BEFORE PageLowIn, so filing calls
\ are legal; PARMAN's stream lands at DEPK_STREAM over the title
\ overlay we have just left for good, and is copied up into bank 5
\ before loadfnt reclaims &3000.
.BrTimeout
  LDA #1
  STA brFlag
  LDX #LO(brLoadMan)
  LDY #HI(brLoadMan)
  JSR OSCLI
  PAGEBANK SWRAM_SPR
  LDA #LO(DEPK_STREAM) : STA swSrc
  LDA #HI(DEPK_STREAM) : STA swSrc+1
  LDA #LO(SWRAM_BASE)  : STA swDst
  LDA #HI(SWRAM_BASE)  : STA swDst+1
  LDX #PARMAN_PAGES
  JSR PageCopyAt
  JSR BrPatchScores
  PAGEBANK SWRAM_DATA
  RTS

.brLoadMan
  EQUS "LOAD PARMAN"
  EQUB 13

\ ============================================================
\ BrPatchScores — the live table into page 5's two lines
\ ============================================================
\ UpdateTextScore ($E5AC) moved to the read side [11f DECISION 7]: the
\ C64 writes the score into the packed text at $DD89/$DDB4 and the text
\ persists; ours is reloaded from disc each time, so the patch happens
\ here, on the fresh copy in bank 5, before anything draws it. The
\ layout is the original's: eight BCD digits at glyph offsets 0-7 with
\ leading zeros as spaces (the last digit never blanked), initials at
\ 11-13. make_briefing.py labels the two records br_hiscore/br_loscore.
\
\ The table is bank 7's and the text is bank 5's, so the fourteen bytes
\ go through brSc in this overlay — the same one-bank-at-a-time dance
\ as everything else. hsHigh..hsLoIni are contiguous: 4+3+4+3.
.BrPatchScores
  PAGEBANK SWRAM_XFER
  LDX #13
.bps_copy
  LDA hsHigh,X
  STA brSc,X
  DEX
  BPL bps_copy
  PAGEBANK SWRAM_SPR
  LDA #LO(br_hiscore+1)         \ +1: past the record's column byte
  STA brp
  LDA #HI(br_hiscore+1)
  STA brp+1
  LDX #0                        \ brSc: the high score's 4+3
  JSR BrPatchLine
  LDA #LO(br_loscore+1)
  STA brp
  LDA #HI(br_loscore+1)
  STA brp+1
  LDX #7                        \ and the low score's
.BrPatchLine
  LDA #0
  STA brT2                      \ still in the leading zeros
  LDY #0
.bpl_byte
  LDA brSc,X                    \ one BCD byte, two digits
  PHA
  LSR A : LSR A : LSR A : LSR A
  JSR bpl_dig
  PLA
  AND #&0F
  JSR bpl_dig
  INX
  CPY #8
  BCC bpl_byte
  INY                           \ glyphs 8-10 are ' - ', left alone
  INY
  INY
.bpl_ini
  LDA brSc,X                    \ a letter index 0-26, 26 the space
  CMP #26
  BCC bpl_letter
  LDA #PN_SPACE                 \ which is ZERO, so no BNE-always here —
  JMP bpl_iput                  \ that mistake shipped once
.bpl_letter
  CLC
  ADC #PN_UPPER_A
.bpl_iput
  STA (brp),Y
  INX
  INY
  CPY #14
  BCC bpl_ini
  RTS

.bpl_dig                        \ A = the digit, Y = the glyph position
  BNE bpld_show
  LDA brT2                      \ a zero: blanked while leading, except
  BNE bpld_zero                 \ the last digit, which always shows
  CPY #7
  BEQ bpld_zero
  LDA #PN_SPACE                 \ ZERO — a BNE-always here never branches
  JMP bpld_put
.bpld_zero
  LDA #PN_DIGIT0
  BNE bpld_put                  \ always
.bpld_show
  STA brT
  LDA #1
  STA brT2
  LDA brT
  CLC
  ADC #PN_DIGIT0
.bpld_put
  STA (brp),Y
  INY
  RTS

\ ============================================================
\ BrDispatch — where TitleSeq's callers land instead of the game
\ ============================================================
\ Both post-title sites (boot's JSR and GoTitle's JMP) come here in
\ place of GameStartInfo. brFlag says how the title ended: 0 fired ->
\ the game, 1 timed out -> the briefing, and afterwards either exit
\ reloads PARASPR into the bank the text borrowed — BOTH exits, because
\ a fire at the NEXT title would otherwise start a game whose blitter
\ is briefing text. The reload is the PARDEPK dance boot does, legal
\ here because the teardown has put the MOS back in charge; ~0.7 s,
\ accepted as the naive form (KC: get it working, optimise the loading
\ after — [DECISION 6], and §3d has the one-load trim for later).
.BrDispatch
  LDA brFlag
  BNE brd_brief
  JMP GameStartInfo
.brd_brief
  LDA #0
  STA brFlag
  JSR BrRun
  PHA                           \ BR_EXIT_FIRE or BR_EXIT_OFF

\ The teardown is GoTitle's own, minus SndSilence: the chatter is
\ deferred (F2), so nothing has sounded since the last silence and the
\ chip is already quiet. UninstallIrq first — the rupture IRQ rewrites
\ the CRTC every field — then the plain frame, then DFS's workspace
\ back before the first load.
  JSR UninstallIrq
  JSR SetupPlain                \ bank 4; BrRun left SWRAM_DATA paged
  JSR RestoreDfsWs

  LDX #LO(loaddepk)             \ the depacker at &3000, over the font —
  LDY #HI(loaddepk)             \ ts_loads reloads the font either way
  JSR OSCLI
  LDX #LO(loadspr)              \ PARASPR's stream at DEPK_STREAM
  LDY #HI(loadspr)
  JSR OSCLI
  LDA #SWRAM_SPR
  JSR UnpackBankIn              \ the blitter is home again

  PLA
  BNE brd_title
  JSR ts_loads                  \ font, low overlay, rupture, tables,
  JMP GameStartInfo             \ IRQ — TitleSeq's own tail — then play
.brd_title
  JSR TitleSeq                  \ the full title again; PARTITL lands on
  JMP BrDispatch                \ the dead depacker. It can time out again

\ ============================================================
\ BrRun — the briefing proper
\ ============================================================
\ Entered from BrDispatch with the rupture up, the IRQ running, the
\ font home at &3000 and SWRAM_DATA paged. Parks the scroll exactly as
\ IsStart does — the strip is addressed as a flat 16 x 640 array — then
\ pages the text in and stays on it; keydown is safe with a bank up
\ because OSBYTE restores from ROMSHAD.
\
\ THE SHAPE IS THE C64's OWN LOOP, $1184-$123F, transcribed:
\
\   per page:  reset the scroll, paint the window, then
\   _4/_5      wait for down to be RELEASED (the page-skip debounce)
\   _6/_7      dwell at the top — 256 fields, down skips it
\   _8..$1214  scroll a field at a time: ySpd+1 = $FF - joyYDir and
\              MoveScreen SUBTRACTS it, so centred is 1 px a field,
\              down ($1204's +1) is 2, up (-1) is 0 — a pause. The
\              travel ends at ScreenPosY = $168 = 360 scanlines, and
\              360 is exactly this port's (60 - 15) rows too
\   $120A      dwell at the bottom — 128 fields, down skips it
\   _12        next page; page 6 is the way out to the title
\   any fire   the game, from anywhere in all of that
\
\ K and M are the port's up and down, L is fire — the game's own keys.
\ One field here is one C64 field: the step waits on fieldCount, which
\ the rupture IRQ bumps at fire 3.
BR_TRAVEL = 45                  \ rows of scrolling: canvas row 0 to 45
                                \ at the top, 15 visible, content to 59

.BrRun
  LDA #0
  STA scrollS
  STA scrollS+1
  STA line
  STA iline
  STA bandDo
  STA colCount
  JSR SetCRTCStart
  STA brPage                    \ A is still 0: page 1

\ THE WINDOW IS 15 ROWS, the scrolled deck's own, because a window that
\ scrolls by scanlines spans a 16th partial row and the strip has only
\ 16. Every modal screen wants T1_I3X; the two paths here disagree
\ about what they left behind (boot never set it, a game over left the
\ wash's 16), so the briefing states its own. GameStartInfo -> IsStart
\ sets it back to 16 for the 001 page on the way out, and ReframeView
\ restores the deck's 15 after that, so nothing needs undoing.
  LDA #HI(T1_I3)
  STA t1i3Hi

\ The play area's palette is the briefing's to state: palPlay is built
\ by SetPalette at DECK LOAD, so at briefing time it holds whatever the
\ assembler left in it, and the rupture reapplies it every frame — the
\ ULA writes TiPal did are overwritten within a field. The values are
\ the OS's MODE 1 default, the same statement TiPal makes: black, red,
\ yellow, white, so fontMask &FF is white on black.
  LDX #15
.br_pal
  LDA brPal,X
  STA palPlay,X
  DEX
  BPL br_pal

  PAGEBANK SWRAM_SPR

\ ---- per page: $1184's block --------------------------------
.br_page
  LDA #0
  STA scrollS
  STA scrollS+1
  STA line
  STA brTop
  STA brBufRow
  JSR SetCRTCStart
  JSR BrDrawPage

\ the _4/_5 release wait: a held M must not eat the next page too
.br_deb
  JSR BrWaitField
  LDX #KEY_L
  JSR keydown
  BNE br_nofire                 \ br_fire is past a branch's reach here
  JMP br_fire
.br_nofire
  LDX #KEY_M
  JSR keydown
  BEQ br_deb

\ ---- the top dwell: _6/_7, 256 fields, down skips it --------
  LDA #0
  STA brDwell
.br_dw1
  JSR BrWaitField
  LDX #KEY_L
  JSR keydown
  BEQ br_fire
  LDX #KEY_M
  JSR keydown
  BEQ br_scroll
  INC brDwell
  BNE br_dw1

\ ---- the scroll: _8 to $1208 --------------------------------
.br_scroll
  JSR BrWaitField
  LDX #KEY_L
  JSR keydown
  BEQ br_fire
  LDX #KEY_K                    \ up: ySpd+1 becomes 0 — hold still
  JSR keydown
  BEQ br_scroll
  JSR BrStep
  LDX #KEY_M                    \ down: $FF - 1 = -2 — a second step
  JSR keydown
  BNE br_moved
  JSR BrStep
.br_moved
  JSR SetCRTCStart
  LDA brTop
  CMP #BR_TRAVEL
  BCC br_scroll
  LDA line
  BNE br_scroll

\ ---- the bottom dwell: $120A, 128 fields, down skips it -----
  LDA #&80
  STA brDwell
.br_dw2
  JSR BrWaitField
  LDX #KEY_L
  JSR keydown
  BEQ br_fire
  LDX #KEY_M
  JSR keydown
  BEQ br_turn
  INC brDwell
  BNE br_dw2

\ ---- _12: the next page, or out to the title ----------------
.br_turn
  INC brPage
  LDA brPage
  CMP #BR_PAGES
  BCS br_out
  JMP br_page
.br_out
  PAGEBANK SWRAM_DATA
  LDA #BR_EXIT_OFF
  RTS
.br_fire
  PAGEBANK SWRAM_DATA
  LDA #BR_EXIT_FIRE
  RTS

\ ---- one scanline down the canvas ---------------------------
\ line 0-7 within the row at scrollS; on the wrap the window's top row
\ advances and the row about to enter at the BOTTOM edge — brTop+15,
\ the staged 16th — is painted before any of it is displayed. Stops
\ dead once the travel is done so a second BrStep in the same field
\ cannot overshoot.
.BrStep
  LDA brTop
  CMP #BR_TRAVEL
  BCC brs_go
  RTS
.brs_go
  INC line
  LDA line
  CMP #8
  BCC brs_x
  LDA #0
  STA line
  CLC                           \ scrollS on a row, wrapped at the strip
  LDA scrollS   : ADC #LO(ROW_BYTES) : STA scrollS
  LDA scrollS+1 : ADC #HI(ROW_BYTES) : STA scrollS+1
  CMP #HI(BUF_SIZE)             \ BUF_SIZE is a whole number of pages
  BCC brs_row
  SEC
  LDA scrollS   : SBC #LO(BUF_SIZE) : STA scrollS
  LDA scrollS+1 : SBC #HI(BUF_SIZE) : STA scrollS+1
.brs_row
  INC brTop
  LDA brBufRow
  CLC
  ADC #1
  AND #15
  STA brBufRow
  ADC #15                       \ the staged row is 15 on from the top;
  AND #15                       \ carry is clear, 0-15 + 15 cannot wrap
  STA brStrip
  LDA brTop
  CLC
  ADC #15
  JSR BrPaintRow
.brs_x
  RTS

\ ---- one field's edge on the rupture's counter --------------
.BrWaitField
  LDA fieldCount
.bwf_w
  CMP fieldCount
  BEQ bwf_w
  RTS

\ ============================================================
\ BrDrawPage — the whole window of page brPage, scroll at 0
\ ============================================================
\ Sixteen buffer rows: the 15 the window shows and the staged 16th,
\ which the first BrStep of the scroll starts revealing.
.BrDrawPage
  LDA #0
  STA brStrip
.bdp_row
  LDA brStrip                   \ scroll parked: buffer row = canvas row
  JSR BrPaintRow
  INC brStrip
  LDA brStrip
  CMP #16
  BCC bdp_row
  RTS

\ ============================================================
\ BrPaintRow — canvas row A into buffer row brStrip
\ ============================================================
\ A canvas row is painted from ITS record list drawn top-half plus the
\ row above's drawn bottom-half, because a record occupies the row it
\ names and the one below: the top cells of its 8 x 16 glyphs, then
\ the bottom ones. That is UpTextChar's dest+$100, done at read time.
.BrPaintRow
  STA brRow
  JSR BrClearRow
  LDA #0                        \ top halves of this row's records
  STA brHalf
  LDA brRow
  JSR BrRowList
  LDA #8                        \ bottom halves of the row above's
  STA brHalf
  LDA brRow
  SEC
  SBC #1
  JMP BrRowList                 \ and its RTS

\ ---- one strip row to black --------------------------------
\ 640 bytes, 256 + 256 + 128. The record lists are sparse, so a page
\ turn must clear what the last page left.
.BrClearRow
  LDX brStrip
  LDA brRowBLo,X : STA swDst
  LDA brRowBHi,X : STA swDst+1
  LDA #0
  TAY
.bcr_1
  STA (swDst),Y
  INY
  BNE bcr_1
  INC swDst+1
.bcr_2
  STA (swDst),Y
  INY
  BNE bcr_2
  INC swDst+1
.bcr_3
  STA (swDst),Y
  INY
  CPY #&80
  BNE bcr_3
  RTS

\ ============================================================
\ BrRowList — draw one canvas row's records, one half
\ ============================================================
\   A = canvas row, brHalf = 0 (top cells) or 8 (bottom cells)
\ A row list is (col, glyphs..., $FE) per record, then $FF; an empty
\ row is the $FF alone, and a row outside BR_ROW_LO..HI has no list at
\ all — the range check is what stands in for it.
.BrRowList
  CMP #BR_ROW_LO
  BCC brl_x
  CMP #BR_ROW_HI+1
  BCS brl_x
  SEC
  SBC #BR_ROW_LO
  TAY
  LDX brPage                    \ the per-page split keeps every index
  LDA brPageLLo,X : STA brp     \ 8-bit: 57 rows a page, not 285
  LDA brPageLHi,X : STA brp+1
  LDA (brp),Y
  STA brT                       \ the row list's low byte
  LDA brPageHLo,X : STA brp
  LDA brPageHHi,X : STA brp+1
  LDA (brp),Y
  STA brp+1
  LDA brT
  STA brp                       \ brp -> the row list

.brl_rec
  LDY #0
  LDA (brp),Y                   \ a record's column, or $FF
  CMP #&FF
  BEQ brl_x
  STA brT                       \ swDst = row base + col * 16; col < 40
  LDA #0                        \ so the product needs nine bits
  ASL brT : ROL A
  ASL brT : ROL A
  ASL brT : ROL A
  ASL brT : ROL A
  STA brT2
  LDX brStrip
  CLC
  LDA brRowBLo,X : ADC brT  : STA swDst
  LDA brRowBHi,X : ADC brT2 : STA swDst+1
.brl_gl
  INY
  LDA (brp),Y
  CMP #&FE
  BEQ brl_adv
  JSR BrChar
  JMP brl_gl
.brl_adv
  INY                           \ step brp past this record to the next
  TYA
  CLC
  ADC brp
  STA brp
  BCC brl_rec
  INC brp+1
  JMP brl_rec
.brl_x
  RTS

\ ============================================================
\ BrChar — one character: a cell, or two if it is wide
\ ============================================================
\   A = glyph index; Y preserved for the caller's list walk
\ DrawChar's own rule ($0C82): capitals are 16 px — their right halves
\ at +PN_WIDE_OFS — EXCEPT capital I, a bare stem; and lowercase m and
\ w are wide too, their rights parked past the alphabet. The record
\ lists hold one index per character, so the expansion happens here.
.BrChar
  STY brY
  CMP #PN_LOWER_M
  BEQ brc_m
  CMP #PN_LOWER_W
  BEQ brc_w
  CMP #PN_UPPER_I
  BEQ brc_one
  CMP #PN_UPPER_A
  BCC brc_one
  CMP #PN_UPPER_Z+1
  BCS brc_one
  PHA
  JSR BrCell
  PLA
  CLC
  ADC #PN_WIDE_OFS
.brc_one
  JSR BrCell
  LDY brY
  RTS
.brc_m
  JSR BrCell
  LDA #PN_M_RIGHT
  BNE brc_one                   \ always
.brc_w
  JSR BrCell
  LDA #PN_W_RIGHT
  BNE brc_one                   \ always

\ ---- one cell through FontCell -----------------------------
\ An index below BR_XTRA0 is the shared font's, 16 packed bytes at
\ textfont + n*16; at or above it is one of the briefing's own three
\ (comma, apostrophe, semicolon) in brExtra — which is BANK 5, legal
\ because this whole path runs with the text bank paged. brHalf picks
\ the top or bottom 8 bytes, FontCell expands them into one MODE 1
\ cell at swDst, and swDst steps one cell on.
.BrCell
  CMP #BR_XTRA0
  BCS brcl_extra
  STA swSrc
  LDA #0
  STA swSrc+1
  ASL swSrc : ROL swSrc+1
  ASL swSrc : ROL swSrc+1
  ASL swSrc : ROL swSrc+1
  ASL swSrc : ROL swSrc+1
  CLC
  LDA swSrc   : ADC #LO(textfont) : STA swSrc
  LDA swSrc+1 : ADC #HI(textfont) : STA swSrc+1
  JMP brcl_half
.brcl_extra
  SEC
  SBC #BR_XTRA0
  ASL A : ASL A : ASL A : ASL A
  CLC
  ADC #LO(brExtra)
  STA swSrc
  LDA #0
  ADC #HI(brExtra)
  STA swSrc+1
.brcl_half
  CLC
  LDA swSrc
  ADC brHalf
  STA swSrc
  BCC brcl_ink
  INC swSrc+1
.brcl_ink
  LDA #&FF                      \ logical 3 — white under TiPal, which
  STA fontMask                  \ is still the palette here
  JSR FontCell
  CLC
  LDA swDst
  ADC #16
  STA swDst
  BCC brcl_x
  INC swDst+1
.brcl_x
  RTS

\ ---- the briefing's palette --------------------------------
.brPal
  PALENT  0, 0 : PALENT  1, 0 : PALENT  4, 0 : PALENT  5, 0
  PALENT  2, 1 : PALENT  3, 1 : PALENT  6, 1 : PALENT  7, 1
  PALENT  8, 3 : PALENT  9, 3 : PALENT 12, 3 : PALENT 13, 3
  PALENT 10, 7 : PALENT 11, 7 : PALENT 14, 7 : PALENT 15, 7

\ ---- the strip's row bases, scroll parked ------------------
.brRowBLo
  FOR n, 0, 15
    EQUB LO(BUF_BASE + n * ROW_BYTES)
  NEXT
.brRowBHi
  FOR n, 0, 15
    EQUB HI(BUF_BASE + n * ROW_BYTES)
  NEXT

\ ---- state, all of it this overlay's ------------------------
.brFlag  EQUB 0                 \ 0 the title fired; 1 it timed out and
                                \ PARMAN is in bank 5
.brPage  EQUB 0                 \ 0-4: which page is up
.brRow   EQUB 0                 \ the CANVAS row being painted
.brStrip EQUB 0                 \ the BUFFER row (0-15) it lands in
.brTop   EQUB 0                 \ canvas row at the window's top, 0-45
.brBufRow EQUB 0                \ buffer row holding brTop
.brDwell EQUB 0                 \ the dwell counter, C64 frameCount's role
.brHalf  EQUB 0                 \ 0 top cells, 8 bottom cells
.brT     EQUB 0
.brT2    EQUB 0
.brY     EQUB 0
.brSc    SKIP 14                \ BrPatchScores' ferry: bank 7's table on
                                \ its way to bank 5's text
