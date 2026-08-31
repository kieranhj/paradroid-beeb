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
  LDA #6                        \ blank the display for the loads: the
  STA CRTC_ADDR                 \ title picture is still up and the low
  LDA #0                        \ overlay stages inside its framebuffer.
  STA CRTC_DATA                 \ VSync carries on, which they need
  LDA #8                        \ and R8, which is what actually blanks
  STA CRTC_ADDR                 \ it: R6 = 0 leaks row 0, measured
  LDA #R8_BLANK                 \ 2026-08-31. Every blank in the port is
  STA CRTC_DATA                 \ R8 now; the rupture IRQ unblanks
  LDA #1
  STA brFlag
  LDX #LO(brLoadMan)
  LDY #HI(brLoadMan)
  JSR OSCLI
\ PARMAN SHIPS ZX0 NOW, 2026-08-29. It used to be the one uncompressed
\ overlay and BrTimeout copied it up page by page; with the depacker
\ resident it unpacks like any bank file, 20 sectors down to 11 and
\ ~0.6 s off this seam. UnpackBankIn does its own paging, so the PgSpr
\ that used to stand here is gone with the copy.
  LDA swBank+SWRAM_SPR
  JSR UnpackBankIn
  JSR BrPatchScores
  JMP PgData     \ tail: its RTS is ours

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
\ Only the ferry lives here: the write half is BmPatch in bank 5,
\ beside the records it patches, because this overlay has a hard
\ ceiling at &0800 — see briefman.asm's header for what the page above
\ costs.
.BrPatchScores
  JSR PgXfer   
  LDX #13
.bps_copy
  LDA hsHigh,X
  STA brSc,X
  DEX
  BPL bps_copy
  JSR PgSpr   
  JMP BmPatch                   \ bank 5's, now paged — and its RTS

\ ============================================================
\ RuptAlign — put the frame boundary under SetupRupture's writes
\ ============================================================
\ MEASURED 2026-08-31: establishing the rupture costs THREE malformed
\ fields, and they are a phase problem. Frame lengths in cycles across
\ the briefing exit, stepped one field at a time:
\
\   39,936  39,936 | 38,378  49,154  6,168 | 39,938  39,936
\   plain, blanked   300 ln  384 ln  48 ln   rupture, locked
\
\ The 384-line field is the diagnosis: SetupRupture writes R4 = TAIL_R4
\ = 12 wherever the main loop happens to be, and the plain frame is 39
\ rows, so the row counter is usually PAST 12 -- the 6845 then runs on
\ toward its wrap before the compare matches.
\
\ So: wait for VSync, then wait out the rest of the frame, and let the
\ writes land in rows 0-1 of a fresh one, where R4 = 12 is AHEAD of the
\ counter and matches at row 12 like any other cycle. VSync is at
\ PLAIN_R7 = 31 of the 39, so 8 rows = 8,192 cycles remain, and the
\ landing window runs from there to row 12, another 11,264 -- nowhere
\ near a knife edge. 8 x 256 x ~5 = ~10,250 lands about two rows in.
\
\ IT WAS TRIED, REVERTED AND TRIED AGAIN. First time (this same code)
\ KC judged it worse by eye -- but the blanks still leaked a row then,
\ so a stripe of the play buffer sat on screen through the whole seam
\ and swamped it. With every blank on R8 the alignment stands on its
\ own. docs/raster-timing.md has both rounds.
\
\ WHY IT IS HERE: it wants ~16 bytes of main RAM that need no paging,
\ and the code image has seven. PARBRF is resident and valid on every
\ route into ts_loads -- TiShow loads it before each title, and
\ BrDispatch's own fire exit is in this file. It is NOT valid at
\ HsEntry (a game has rebuilt the charset over &0400 by then), which is
\ why the call is in ts_loads and not inside SetupRupture.
.RuptAlign
  LDA #19
  JSR OSBYTE                    \ returns just after the VSync at row 31
  LDX #8
.ra_out
  LDY #0
.ra_in
  DEY
  BNE ra_in
  DEX
  BNE ra_out
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

\ The teardown is GoTitle's own, and now including its SndSilence: the
\ chatter HAS been sounding, and UninstallIrq stops the ticks, so
\ whatever the chip holds would drone through the loads and into the
\ game or the title behind them. Silence it here, masked so no tick
\ interleaves the port A save/restore, with SWRAM_DATA paged — both
\ of BrRun's exits page it before they return. UninstallIrq CLIs at
\ its end, exactly as it does for GoTitle.
  LDA #0
  STA sndState
  SEI
  JSR SndSilence
  JSR UninstallIrq
  JSR SetupPlain                \ bank 4; BrRun left SWRAM_DATA paged.
                                \ The plain frame is BLANK now — R6 = 0
                                \ in its own table — so the reload shows
                                \ nothing; SetupRupture (fire) or TiCRTC
                                \ (title) gives the display back
  JSR RestoreDfsWs

\ NO PARDEPK RELOAD. It used to come back here purely to put a
\ decompressor at &3000; the code image carries the only copy now, and
\ with nothing landing on &3000 the font survives too — which is what
\ lets ts_loads stop reloading PARAFNT. 2026-08-29
  LDX #LO(loadspr)              \ PARASPR's stream at DEPK_STREAM
  LDY #HI(loadspr)
  JSR OSCLI
  LDA swBank+SWRAM_SPR
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
\ Up, down and fire are the GAME's controls, through keyTab and
\ KeyDownIx — so a briefing scrolled after a CTRL+R uses whatever was
\ just set, which is the cheapest possible way to try them out.
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

\ The palette is NOT touched: the briefing inherits the last deck's
\ (KC, 2026-08-22). The rupture reapplies palPlay every frame, and
\ palPlay still holds what SetPalette built at the last deck load —
\ or, before any deck has ever loaded, its assembled default, which
\ rupture.asm now makes the MODE 1 set rather than zeros for exactly
\ this moment.

\ The box's content: bars, logo, "Briefing" in the mode-word field and
\ the last game's score — TitleLoop's $6917/$1193/$1151. PanelInit is
\ wanted as well as the text because only LoadDeck calls it: at a boot
\ no deck has ever loaded, and on the game-over path the low overlay's
\ staging has been over the panel since ts_loads. The printer is
\ bank 6's, so it gets its page before the text bank moves in.
  JSR PgSpr2   
  JSR PanelInit
  JSR PnBriefing

  JSR PgSpr   

\ ---- the chatter starts, $115B ------------------------------
\ The C64 writes $11 here; this port has no $11, because its chatter
\ is not inside the driver — BmChatter's header says why — so it asks
\ for the ordinary initialise ($12, which SndTick collapses to 2) and
\ drives the requests itself. [11f DECISION 11]
\
\ PARMAN IS RELOADED FROM DISC FOR EVERY BRIEFING — BrTimeout is the
\ only way here — so brChCnt arrives assembled at zero and needs no
\ store. The seed does: the same fresh load would otherwise hand every
\ briefing the same byte and the same burble. fieldCount has been
\ running since InstallIrq and carries the disc's own timing; ORA #1
\ because an LFSR that reaches zero stays there.
  LDA #&12
  STA sndState
  LDA fieldCount
  ORA #1
  STA brChSeed

\ ---- per page: $1184's block --------------------------------
\ THE BODY IS A ROUTINE because the redefine screen has to undo itself:
\ BrKeyRedef paints the page again when CTRL+R's screen is done, and
\ the four loops below simply carry on with the page back under them
\ and the travel started again from the top. See BrKeyRedef.
.br_page
  JSR BrPagePaint

\ the _4/_5 release wait: a held M must not eat the next page too
.br_deb
  JSR BrWaitField
  LDX #CTL_FIRE
  JSR KeyDownIx
  BNE br_nofire                 \ br_fire is past a branch's reach here
  JMP br_fire
.br_nofire
  LDX #CTL_DOWN
  JSR KeyDownIx
  BEQ br_deb

\ ---- the top dwell: _6/_7, 256 fields, down skips it --------
  LDA #0
  STA brDwell
.br_dw1
  JSR BrWaitField
  LDX #CTL_FIRE
  JSR KeyDownIx
  BEQ br_fire
  LDX #CTL_DOWN
  JSR KeyDownIx
  BEQ br_scroll
  INC brDwell
  BNE br_dw1

\ ---- the scroll: _8 to $1208 --------------------------------
.br_scroll
  JSR BrWaitField
  LDX #CTL_FIRE
  JSR KeyDownIx
  BEQ br_fire
  LDX #CTL_UP                    \ up: ySpd+1 becomes 0 — hold still
  JSR KeyDownIx
  BEQ br_scroll
  JSR BrStep
  LDX #CTL_DOWN                    \ down: $FF - 1 = -2 — a second step
  JSR KeyDownIx
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
  LDX #CTL_FIRE
  JSR KeyDownIx
  BEQ br_fire
  LDX #CTL_DOWN
  JSR KeyDownIx
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
  JSR PgData   
  LDA #BR_EXIT_OFF
  RTS
.br_fire
  JSR PgData   
  LDA #BR_EXIT_FIRE
  RTS

\ ============================================================
\ BrPortrait — page 5's droid picture, and how it scrolls
\ ============================================================
\ $119A-$11AD: the last page shows a random droid via
\ BuildIntroSprites. The C64 floats it as HARDWARE SPRITES fixed on
\ screen while the canvas scrolls beneath; this port has no sprites on
\ a modal screen — bank 5 IS the text — so the portrait SCROLLS WITH
\ THE PAGE instead (KC, 2026-08-22): it is composited into the strip
\ rows by the painter, exactly as the text is.
\
\ The mechanism: PoDraw (bank 7) renders type rnd AND $F into the
\ parked strip at its own rows — DB_IMG_ROW to +10, the C64's own
\ picture height — at unit 68, then the rectangle is snapshotted into
\ SPR_SAVE (dead outside a game, LoadDeck rebuilds it) and BrPaintRow
\ copies a 96-byte band back whenever it paints one of those canvas
\ rows. A plain copy, no transparency: text columns 34-39 are empty on
\ every page-5 row — checked against briefing.txt — and the picture's
\ own background is logical 0, the page's black. The rectangle sits
\ level with the score table, a mugshot beside the scores.
\
\ Only the paging dance is here; the snapshot (BmSnap), the per-row
\ band copy (BmBand) and the geometry are bank 5's, briefman.asm —
\ this overlay's &0800 ceiling again.
.BrPortrait
  JSR PgData              \ the LFSR lives in bank 4
  JSR DrRandom
  AND #&0F                      \ $11A3's own mask
  PHA
  JSR PgXfer              \ the pool and its state are bank 7's
  LDA #LO(BUF_BASE + BR_PO_OFS) : STA poBase
  LDA #HI(BUF_BASE + BR_PO_OFS) : STA poBase+1
  PLA
  JSR PoDraw
  JSR PgSpr               \ the text bank back — the resting state
  JMP BmSnap                    \ and its RTS

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

\ ---- PARK THE POSITION BEFORE PAINTING, and this is a timing fix ----
\ BrPaintRow is 35,850 cycles, measured -- 90% of a 39,936-cycle field
\ -- and br_scroll's own SetCRTCStart comes AFTER it. So on the one
\ field in eight that paints a row, the park landed after the rupture's
\ fire-1 latch, the display re-showed the position it had just shown,
\ and the field after that jumped TWO scanlines. The scroll averaged
\ exactly one scanline a field and still hitched 6.25 times a second;
\ KC saw it on real hardware, 2026-08-31.
\ Parking here fixes it because the position is complete by this point
\ -- line, scrollS and brTop are all updated above -- so the park is a
\ few hundred cycles after fire 3 and beats every fire 1. The paint
\ then overruns into the next field exactly as it did, but invisibly:
\ BrWaitField returns immediately afterwards, fieldCount having already
\ moved, so the cadence recovers with no field lost.
\ IT IS SAFE AGAINST TEARING because the row being painted is the
\ STAGED one, brTop+15, one below a 15-row window -- it is not on
\ display at any point during the paint.
\ br_scroll's SetCRTCStart stays: it is what parks the seven cheap
\ fields, and the second step of a held DOWN key.
  JSR SetCRTCStart

  LDA brTop
  CLC
  ADC #15
  JSR BrPaintRow
.brs_x
  RTS

\ ---- one field's edge on the rupture's counter --------------
\ EVERY loop in BrRun waits here, exactly once per field, which makes
\ it the one place the chatter can tick at the C64's own 50 Hz. The
\ page turns do not pass through it — BrDrawPage paints sixteen rows
\ without waiting — so the counter stalls for those few fields while
\ whatever blip is playing carries on; the driver is sequencing that
\ from the IRQ and neither notices.
.BrWaitField
  LDA fieldCount
.bwf_w
  CMP fieldCount
  BEQ bwf_w
\ The volume keys, on the one hook every loop in BrRun passes through —
\ and the briefing is where a master volume was most wanted, because
\ the chatter was the loudest thing in the game (it is level with the
\ bass bed since 11e round twelve). VolKeysBrf is main RAM
\ and touches only main RAM, so the text bank stays paged across it and
\ the bank-5-in-bank-5-out contract below is untouched.
  JSR VolKeysBrf
  JSR BrKeyRedef                \ CTRL+R: the redefine screen
\ THE CHATTER STOPS WHILE THAT SCREEN IS UP (KC, 2026-08-30). It is the
\ briefing's burble, not the machine's, and it has no business under a
\ screen whose whole content is short beeps that answer key presses —
\ they would land on the same voice and be swallowed. The blip already
\ sounding when CTRL+R lands plays itself out: SndTick is still running,
\ nothing new is requested, and BmKrRun's own beeps take voice 1 from
\ there. brRedef is clear again by the time BrKeyRedef returns at the
\ outer level, so the burble resumes with the page.
  LDA brRedef
  BNE brch_x
\ fall through into the chatter, and its RTS

\ ============================================================
\ BrChatter — the bank-4 half of the briefing's soundtrack
\ ============================================================
\ BmChatter (bank 5, and its header is where the C64 routine is
\ explained) does everything that can be done without paging: the
\ counter, the LFSR, the lift blip on voice 2, and the choice of which
\ blip record to play. What is left needs the DATA bank, which is why
\ it is here in main RAM: bank code cannot page itself out.
\
\ NO SEI. The rupture's T1 stages are deadline-driven and this runs
\ every field, so blocking the IRQ across an eleven-byte copy is the
\ one thing that must not happen. Three races were considered and all
\ three are safe:
\   - ROMSHAD/ROMSEL: written shadow-first, so an IRQ that lands
\     between them sees a consistent claim and restores it — the same
\     argument the sound shim in IrqHandler already rests on
\   - the scratch slot: the request is posted AFTER the copy, and a
\     blip already playing has long since had the record loaded into
\     its voice state, so nothing reads the slot mid-copy
\   - the slide nudge: SndTick can negate the same byte between the
\     load and the store. One lost step of a random walk, once in a
\     while, on a deliberately random warble
\ THE BANK IS 5 ON THE WAY IN AND 5 ON THE WAY OUT, stated rather than
\ saved: BrWaitField is reached only from BrRun's loops, whose resting
\ state is the text bank — BrPortrait is the one excursion and it pages
\ 5 back itself before it returns.
.BrChatter
  JSR BmChatter
  BEQ brch_x                    \ 0 nothing, $FF nudge, else the blip
  PHA
  JSR PgData   
  PLA
  BMI brch_nudge

  LDY #BR_CHAT_PRE-1            \ the varying head of the record; the
.brch_copy                      \ tail is common to all three blips and
  LDA brChRec,Y                 \ the slot ships holding it (sndchat.asm)
  STA sndFxChat,Y
  DEY
  BPL brch_copy
  LDA #SND_FX_CHAT
  STA sndFx1                    \ voice 1, as $0565 does
  JMP BrChBack

.brch_nudge
  LDA brChRec                   \ BmChatter left the signed delta here
  CLC
  ADC snSlideHi                 \ voice 1's slide hi = the C64's $C3
  STA snSlideHi
.BrChBack
  JSR PgSpr   
.brch_x
  RTS

\ ============================================================
\ BrPagePaint — the current page, from the top
\ ============================================================
\ br_page's own prologue, called from there and from BrKeyRedef.
.BrPagePaint
  LDA #0
  STA scrollS
  STA scrollS+1
  STA line
  STA brTop
  STA brBufRow
  JSR SetCRTCStart
  LDA brPage                    \ $119A: the last page gets the droid
  CMP #BR_PAGES-1               \ portrait, rendered before the paint
  BNE br_pg_nopo                \ so the first window composites it
  JSR BrPortrait
.br_pg_nopo
  JMP BrDrawPage                \ and its RTS

\ ============================================================
\ BrKeyRedef — CTRL+R: the redefine screen, and the page back
\ ============================================================
\ Layer 11f's key redefinition [11f DECISION 15, KC 2026-08-30]. This
\ is only the trigger; the screen is BmKrRun, bank 5, src/keyredef.asm
\ — this overlay's &0800 ceiling again.
\ ON BrWaitField, so it is live in all four of BrRun's loops: the page
\ debounce, both dwells and the scroll. brRedef keeps it out of its own
\ way, because BmKrRun waits on fields through BrWaitField too and
\ would otherwise re-enter itself on the CTRL+R still being held.
\ NOTHING IS RESTARTED AFTERWARDS. The page is simply painted again
\ with the travel back at row 0, and whichever loop was running carries
\ on — a dwell counts out, the scroll scrolls the page again. That is
\ what a restart would have done, without four tests in BrRun and
\ without a branch that has to reach br_page from all of them.
\ CTRL NEEDS NOTHING SPECIAL: keydown asks the matrix about one key at
\ a time, so a modifier is just another query and there is no ghosting.
\ See the note by KEY_CTRL in main.asm.
.BrKeyRedef
  LDA brRedef
  BNE brkr_x                    \ the screen is up: this IS its field wait
  LDX #KEY_CTRL
  JSR keydown
  BNE brkr_x
  LDX #KEY_R
  JSR keydown
  BNE brkr_x
  INC brRedef
  JSR BmKrRun                   \ bank 5, and it is already paged
  JSR BrPagePaint
  LDA #0
  STA brRedef
.brkr_x
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
  JSR BrRowList
  JMP BmBand                    \ bank 5: the portrait's band, if this
                                \ row is page 5's rectangle — and its RTS

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
.brRedef EQUB 0                 \ non-zero while the redefine screen owns
                                \ the strip: BrKeyRedef's re-entry guard
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
.brChRec SKIP BR_CHAT_PRE       \ the chatter's mailbox: bank 5 fills it,
                                \ BrChatter empties it into bank 4. Main
                                \ RAM because neither bank can see the
                                \ other, and this is the ferry between.
                                \ Byte 0 doubles as the slide nudge
