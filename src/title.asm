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
  JSR TiLoadBrf                 \ Layer 11f: the briefing driver, FIRST —
                                \ a filing call, so before any of the
                                \ display work and long before PageLowIn
  JSR TiCRTC
  JSR TiPaint
  JMP TiWait                    \ and its RTS

\ ---- the briefing driver, loaded on every title -------------
\ PARBRF lands at &0400 — the MODE 1 charset's ground, dead outside a
\ game — and carries BrDispatch, which every post-title path now runs
\ through, so it must be valid even when the title FIRES. Loading it
\ here, unconditionally, is what makes that true; it is ~1 K, and the
\ timed-out path loads PARMAN separately (BrTimeout). The OSCLI is this
\ overlay's rather than main RAM's because main RAM has two bytes left.
.TiLoadBrf
  LDX #LO(tiLoadBrf)
  LDY #HI(tiLoadBrf)
  JMP OSCLI                     \ and its RTS
.tiLoadBrf
  EQUS "LOAD PARBRF"
  EQUB 13

\ ============================================================
\ TiBootPal — the front end's palette at a COLD BOOT
\ ============================================================
\ KC, 2026-08-24: the front end inherits the palette of the last deck
\ the player played, and at a cold boot there is no such deck, so one
\ is PICKED AT RANDOM. Before this the boot title ran on the OS's MODE
\ 1 default, where logical 0 is black and logical 1 is red — and with
\ the logo now embossed out of CharColor's slots (tools/export_title.py)
\ that inverts it: the shadow strokes came out BRIGHTER than the
\ background they are meant to sit under. Any deck palette has the
\ relationship the artwork wants, because the fixed slot roles give it
\ one: logical 0 a mid colour, logical 1 black under it, logical 3
\ white over it.
\ IT IS THE TEXT PALETTE, not the play one, because that is what the
\ game-over path arrives on — InfoCall runs SetTextPal before every
\ front-end screen (layer-14 DECISION 4), so boot and the loop back
\ now agree. It also dodges decks 0, 5 and 9, whose logical 0 IS white
\ and would swallow the white highlights; their text background is not.
\ AND IT IS WHERE THE SEED IS NOW SET. This used to sit in main.asm
\ after TitleSeq; it wants to be here anyway, because the deck it picks
\ and the LFSR's seed are the same sample of the same free-running
\ counter. Reading the USER VIA's T1C-L clears an interrupt flag
\ nothing in this game uses; the SYSTEM VIA's would eat a rupture
\ interrupt, so do not read that one. A ZERO SEED LOCKS THE LFSR at
\ zero for ever, so it is refused and the assembled default stands —
\ the deck still takes the zero, which is deck 0 and perfectly legal.
\ UNDER AN EMULATOR IT IS STILL DETERMINISTIC: everything before it
\ takes the same time on every boot, so the same deck comes up. On
\ real hardware the disc loads above vary by up to a revolution. The
\ same caveat the seed always carried; real entropy arrives with
\ TiWait's dwell, which GameStart stirs into drSeed.
\ BOOT ONLY. bootPal (main.asm) is an assembled 1 and this is the only
\ thing that clears it, so the game-over path falls straight through
\ and keeps the palette it inherited. The flag cannot live in here:
\ PARTITL is reloaded from disc on every title, so anything it held
\ would come back set.
\ THE BANK IS NOT SWRAM_DATA ON ARRIVAL — boot's last act before
\ TitleSeq is UnpackBankIn on SWRAM_XFER — and SetTextPal and drSeed
\ are both bank 4's, so page it. Leaving it paged is safe: HsEntry is
\ next and pages SWRAM_XFER for itself in its first instruction.
.TiBootPal
  LDA bootPal
  BEQ tbp_x
  DEC bootPal                   \ 1 -> 0, once in the life of the machine
  PAGEBANK SWRAM_DATA
  LDA USR_VIA_T1CL
  BEQ tbp_deck                  \ zero would lock the LFSR — keep the
  STA drSeed                    \ assembled seed, take the deck anyway
.tbp_deck
  AND #15                       \ 16 decks, and the low bits are the
  STA deck                      \ noisiest end of a 1 MHz counter
  JMP SetTextPal                \ bank 4, and its RTS
.tbp_x
  RTS

\ ---- the palette is INHERITED, deliberately -----------------
\ TiPal used to state the MODE 1 default here; KC, 2026-08-22: the
\ front end inherits the palette from the last deck played instead.
\ At a cold boot SetupMode's VDU 22 has left the MODE 1 default; on
\ the game-over path SetupPlain applies palPlay — the deck's own —
\ deterministically, which also covers the 999 page and the entry
\ screen shown before this overlay paints. So there is nothing for
\ the title to set.

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
  BEQ tiw_time                  \ the 16-bit wrap: the timeout, below
\ THE VOLUME KEYS, and this is the awkward one of VolKeys' three call
\ sites. There is no sound at the title — GoTitle silenced the chip and
\ handed the IRQ back — so what is being set here is the level the
\ GAME will start at, which is exactly what KC asked for: mute at the
\ title and the game comes up silent, because sndVolume lives in the
\ resident code image and outlives every load between here and there.
\
\ IT IS GATED ON THIS LOOP'S OWN COUNTER, ONE ITERATION IN 1024, and
\ the reason there is a gate at all is that this loop is not field-
\ locked: its iteration count IS the timeout, and (tiLo EOR tiHi) IS
\ the seed for the starting deck. Polling three more keys every time
\ round would multiply the body and drag both with it.
\
\ THE DIVISOR HAS BEEN 1024, THEN 256, AND IS 1024 AGAIN, which is
\ worth spelling out because it tracks the cost of keydown and nothing
\ else. Measured in jsbeeb, idle:
\
\   keydown         loop rate     1-in-256    1-in-1024
\   OSBYTE &81      3,654/s        14 Hz        3.6 Hz
\   direct scan    11,508/s        45 Hz       11.2 Hz
\
\ 1024 was rejected on the OSBYTE build at 3.6 Hz — four seconds to
\ walk the volume end to end. The direct keydown made the loop 3.15x
\ faster (87 cycles a turn against 274), 256 became 45 Hz, and 1024
\ now lands at 11.2 Hz — which is where the other two call sites sit
\ and what $0CB4's every-fourth-frame comes to. Retune this if keydown
\ ever changes cost again.
\
\ AND THE TIMEOUT MOVED WITH IT: 65,536 turns is 5.7 s now, where it
\ was 17.9 s. That is NOT a regression — the C64's own timeout is 256
\ frames, 5.1 s, and this header has always claimed the wrap was "the
\ same order as the original's". It finally is. KC to say if the old
\ 18 s was preferred; restoring it means counting something other than
\ raw turns, not putting the OSBYTE back.
  LDA tiHi
  AND #3
  BNE tiw_loop
  JSR VolKeys
  JMP tiw_loop
.tiw_time
\ Layer 11f: the 16-bit wrap is the timeout, and the timeout is the
\ briefing — $291B's own arrangement. BrTimeout fetches PARMAN into
\ bank 5, arms brFlag for BrDispatch, and RTSes: the return address on
\ the stack is TiShow's caller, so it lands at TitleSeq's ts_loads
\ exactly as the RTS below would. It must be a JMP taken BEFORE this
\ overlay is overwritten — PARMAN's stream lands on top of it.
  JMP BrTimeout
.tiw_done
  LDA tiLo                      \ hand the dwell out for the seed
  EOR tiHi
  STA overRnd0
\ BLANK THE DISPLAY for the loads that follow (KC, 2026-08-22): the
\ low overlay stages at &4A00, INSIDE this title's visible framebuffer,
\ so ts_loads used to smear staging bytes across the picture. R6 = 0
\ shows nothing while VSync carries on — the loads need it — and
\ SetupRupture gives the display back once the ground is rebuilt. The
\ timed-out path gets the same blank from BrTimeout.
  CRTC 6, 0
  RTS

.tiIdx  EQUB 0
.tiRun  EQUB 0
.tiLo   EQUB 0
.tiHi   EQUB 0
