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
SWRAM_XFER = 7                  \ Layer 10: the transfer minigame
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
\ The IRQ is the thing that would break this, and mostly does not:
\ RuptVSync and RuptTimer touch the CRTC, the VIA and their own
\ variables, and read nothing out of either bank. THE ONE SANCTIONED
\ BREACH is Layer 11e's sound tick: the VSync branch of IrqHandler
\ saves ROMSHAD, pages SWRAM_DATA, runs SndTick and restores what it
\ found — legal precisely BECAUSE every PAGEBANK writes the shadow
\ first, so the shadow always names the bank the interrupted code
\ intends, even between the pair's two stores.
MACRO PAGEBANK bank
  LDA #bank
  STA ROMSHAD                   \ both, always — see the note above:
  STA ROMSEL                    \ the IRQ restores from the SHADOW
ENDMACRO

CHAR_BYTES = 16                 \ a character is 16 bytes: two 8-byte halves

\ ---- frame lock ---------------------------------------------
\ TV fields per game-loop iteration. 2 gives a fixed 25 Hz, which is
\ the rate the C64's GameLoop actually runs at and the rate every
\ movement constant in player.asm is expressed in — see WaitField for
\ why this is locked rather than free-running.
\
\ Changing it changes how fast the game plays unless PLY_ITER_FRAMES
\ moves with it: player.asm scales the C64's per-iteration speeds by
\ FRAME_LOCK / PLY_ITER_FRAMES, so the two cancel at 2 and 2.
FRAME_LOCK = 2

\ ---- top speed, and why it is a camera setting --------------
\ The CRTC scrolls in 4 px units and the loop runs once per 2 fields,
\ so the camera can only move 0, 4, 8 ... px a pass. At the C64's top
\ speed of 7 the world must average 7, which no sequence of 4s and 8s
\ hits exactly — it settles into 8, 8, 8, 4, and that periodic 4 px
\ hiccup is the jerk. The average is forced by arithmetic, so no
\ deadzone or camera policy can remove it; only a top speed that the
\ 4 px step divides can.
\
\   7  the original's, and the Competition Edition's — see the table
\      note in player.asm. Camera dithers 8, 8, 8, 4. Correct, jerky.
\   8  uniform 8 px a pass, 200 px/s. The dither vanishes. 14 % fast
\      against the original, and it lands exactly on the
\      one-row-per-pass ceiling asserted in player.asm.
\   4  uniform 4 px a pass, 100 px/s. Also dither-free, and half the
\      step size, so the smoothest of the three — but 43 % slower
\      than the original, which is a large fidelity cost.
\
\ Anything else is legal and will simply dither again: 6 gives 8, 4,
\ 8, 4 and 5 gives 4, 4, 8, 4. Acceleration and deceleration are NOT
\ scaled with it — they stay the C64's, so a lower top speed is also
\ reached sooner. That is why 4 is not the free win it looks: it lands
\ within 15 % of the 1985 release's 117 px/s, but reaches it in 0.20 s
\ against the original's 0.52 s, so it plays snappier than it moves.
\ Matching the original properly is PLY_ITER_FRAMES, not this — see
\ the header in player.asm, which records what that setting was like.
\
\ 8 is what is kept. It is the one movement number in the port not
\ taken from the C64, and it is here because a uniform scroll was
\ judged worth 14 % of fidelity.
CAM_TOPSPD = 8

\ ---- the SLOW ride, same argument one step down --------------
\ CAM_TOPSPD fixes the 001 and every other DSpeed_t 4 or 8 droid, but
\ PlayerSpeed_t's other two entries dither for exactly the same reason:
\ 5 settles into 4, 4, 8, 4 and 6 into 8, 4, 8, 4. Riding a slow droid
\ was therefore JERKIER than riding a fast one, which is backwards.
\ 4 is the only dither-free value below 8, so both collapse onto it.
\ KC's call (2026-08-21): smoothness over the 5/6 distinction. The
\ cost is that DSpeed_t 1 and 2 droids now feel identical under the
\ player, and the 1s are 20 % faster than the C64 makes them. Enemy
\ droids are untouched — they move in whole pixels, not by scrolling
\ the camera, so they never dithered. [DECISION]
CAM_SLOWSPD = 4

\ ---- Layer 7 effect frames ---------------------------------
\ The explosion's frames are 0 to EF_EXPLODE_N-1 of the effect set, in
\ order, so stepping it is an INC. Declared HERE rather than in the
\ generated effects.asm because droid.asm needs them and beebasm
\ resolves constants in file order — effects.asm is in the sprite bank,
\ which is assembled last. The exporter emits ASSERTs against these.
EF_EXPLODE   = 0
EF_EXPLODE_N = 11

MAP_COLS   = 64                 \ tile map is 64 x 16 tiles
MAP_ROWS   = 16
MAP_CHAR_W = MAP_COLS * 4       \ 256 characters across
MAP_CHAR_H = MAP_ROWS * 4       \ 64 character rows

\ ---- debug build options ------------------------------------
\ **WHICH OF THESE ACTUALLY BUILD, 2026-08-20.** The code image ends at
\ FONT_ADDR and has 11 spare bytes, so a debug flag that adds more than
\ that does not fit — and until the GUARD went in below, it did not SAY
\ so: `CLEAR FONT_ADDR, ...` releases beebasm's overwrite check over
\ exactly the range the overrun lands in, so the build succeeded, `PARA`
\ scribbled on the front of the text font, and the PARAFNT load scribbled
\ back over the code's tail. That is what a corrupt player sprite and an
\ illegible frame digit were. Four flags were doing it.
\   DEBUG_VSYNC    ok    the readouts moved to bank 6 — src/dbgpanel.asm
\   DEBUG_POS      ok    same
\   DEBUG_ENERGY   ok    same, plus a mirror for its two bank-4 bytes
\   DEBUG_INVULN   ok
\   DEBUG_XFERWIN  ok    on by default
\   DEBUG_DECK     ok    on by default
\   DEBUG_RASTER   ok    was 59 bytes over the code image
\   DEBUG_DRAW     ok    was 83 over
\   DEBUG_TIME     ok    was 154 over
\   DEBUG_MAPGUARD ok    was out of room while bank 4 had 12 bytes
\ THE FIRST THREE CAME BACK ON 2026-08-20 with the raster-timing pass,
\ which moved the tranche decision into bank 6 and gave the code image
\ 323 free bytes against eleven, and MAPGUARD on 2026-08-21 with Layer
\ 13d's ZX0 deck maps, which gave bank 4 the 1 K its MG_COPY needs.
\ RASTER has been built and RUN since, and draws its four bands
\ correctly; DRAW, TIME and MAPGUARD have been assembled but not run,
\ so read their headers before trusting them. DEBUG_POS + DEBUG_ENERGY
\ together still do not build (a low-region overlap); each alone does.
\ READING RASTER'S BANDS: fire 2's band is the deck's OWN background, so
\ on a deck whose background happens to be green it cannot be told from
\ fire 1's, and on a blue deck it cannot be told from fire 3's. Deck 1
\ is blue and deck 2 is green, which covers both cases. Hop to a deck
\ with a different scheme before concluding a fire is missing.
\ COMBINATIONS matter too, because each readout's shim costs 20 bytes of
\ src/lowcode2.asm's 36: VSYNC, POS and ENERGY each build alone, but
\ POS+ENERGY does not. The fix is a shared enter/leave pair instead of a
\ shim apiece — 18 bytes once and 9 each — and it was left undone rather
\ than done half-asleep. It fails at build time now, which is the point.
\ The last four are NOT a regression from the debug code — they are the
\ RAM situation, and they need main-RAM room found before they can come
\ back. DEBUG_RASTER's and DEBUG_DRAW's instrumentation cannot move to a
\ bank at all: the interrupt and the blitter call it, and neither may
\ page. See docs/memory-map.md for where the next bytes could come from.
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
\ THE RULE IS NOT "NO BAND MAY TOUCH THE PLAY AREA". Three of the four
\ belong in a window and reaching the play area means they overran; the
\ RED one is display-period work by design and is supposed to be there.
\ What matters for red is that it ENDS before the window B tranche.
\ Four bands — the sprites, the level draw, the per-pass overhead and
\ the display-period work are separate budgets, and the two that matter
\ are the ones that grow with what is happening rather than with the
\ code:
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
\   red      the droid AI, the animated-tile scan, the collisions, the
\            aging and the panel — everything after the draw. None of
\            it writes the play buffer, which is why it is allowed to
\            run while the play area is displayed. IT ENDS AT THE WORK
\            AND NOT AT THE WAIT, so whatever is left untinted before
\            the window B tranche is genuine slack.
\ THE SECOND MAGENTA BAND USED TO SWALLOW THE RED ONE. Until 2026-08-20
\ the tint set before SprAnimateAll ran on until the tranche-B block at
\ the far end of the pass, so the sprite band reported the droid AI, the
\ panel and the idle as sprite work and reached deep into the play area
\ on every pass. It broke when Step 1 of docs/raster-timing.md moved
\ DroidsUpdate below the draw and the closing tint stayed where it was;
\ Phase 1 of the same document then put AnimScanPass in the same gap.
\ Reported by KC, who was reading the band and seeing an overrun that
\ was not there.
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
\ two fields. A 3 or more means it overran and WaitField found the flag
\ already set, so the rate degraded to 16.7 Hz, 12.5 Hz and so on. This
\ is the cheap always-on companion to DEBUG_DRAW: that one shows WHICH
\ work overruns, this one shows THAT it did, without a screenshot.
\
\ Deliberately tiny — a 4x5 digit is one MODE 1 byte per scanline, so
\ drawing it is five unmasked stores and the whole thing costs ~80
\ cycles of the 80,000 in a pass. Anything that had to mask, or that
\ spanned more than one byte per row, would start measuring itself.
\
\ It costs 143 bytes, and it does NOT cost them in the code image any
\ more: DbgFrameCount and the digit font are in bank 6, in
\ src/dbgpanel.asm, with a shim in src/lowcode2.asm to page them in.
\ They had to be. The code image has eleven spare bytes and this flag
\ wanted 143 of them, which for weeks it took SILENTLY — see the GUARD
\ at FONT_ADDR below, and BUGS.md #17.
\
\ THE DIGIT IS NOT AT PANEL_ADDR any more either. That is the status
\ box's rounded corner, drawn in the same logical 3 the digit is, so it
\ was black on black with the corner's own artwork destroyed underneath
\ it. It goes at DBG_PANEL_TL instead — scanline 3 of unit 4, the first
\ clean paper inside the box's top border. Off by default out of
\ tidiness now, not necessity.
DEBUG_VSYNC  = FALSE

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

\ DEBUG_ENERGY prints the player's combat state as hex on the SECOND
\ panel row, every pass:
\
\   type  energy  maxEnergy  weapon  alert  score(4, BCD)
\
\ The panel is Layer 9's and there is nowhere else to show any of this,
\ so until then Layer 7 is untestable without it — energy falling,
\ a recharge pad filling it, the alert level rising off a kill and
\ decaying back down are all invisible otherwise. Row 1 rather than row
\ 0, so it coexists with DEBUG_VSYNC's frame digit and with DEBUG_POS.
\
\ Same mechanism as DbgPosOut and the same cost: a digit is five bytes
\ at five consecutive addresses, the panel does not scroll, and there
\ is nothing to save or restore.
\ OFF since Layer 9: the real HUD lives on the same panel row and the
\ two would fight. It is kept for the next time a raw hex readout is
\ wanted — turning it on suppresses PanelUpdate rather than colliding.
DEBUG_ENERGY = FALSE

\ DEBUG_MAPGUARD watches the TILE MAP for anything scribbling on it, and
\ exists because KC saw the map itself go bad in play — collision data
\ included — on deck 8 when a droid fired, surviving until the deck was
\ reloaded. Two attempts to reproduce it left the map byte-identical, so
\ this catches the event instead of hunting it by inspection.
\
\ A snapshot goes to &3C00 at deck load and a quarter of the map is
\ compared each pass, ~4,000 cycles, so a corruption is caught within
\ four passes. The FIRST hit is kept and checking then stops.
\
\ Read it off the DEBUG_ENERGY line, which grows five bytes on the end:
\   hit  quarter  offset  got  want
\ hit is 01 once it has fired; quarter and offset give the map byte as
\ tilemap + quarter*256 + offset, which is map row (that/64), column
\ (that MOD 64). got is what is there now and want what the deck load
\ put there.
\ OFF since Layer 9: the text font took &3C00 and the guard's 1K
\ snapshot no longer fits below the panel. droid.asm's asserts say what
\ to move to turn it back on. BUGS.md #10, which it was written for, is
\ fixed.
DEBUG_MAPGUARD = FALSE

\ DEBUG_XFERWIN gives the player the transfer minigame: hold W during the
\ play phase and the game ends as a WIN on the next pass. It is there so
\ droid behaviour and everything else downstream of a capture — the new
\ type's speed and weapon, the AI, the alert level, the score — can be
\ reached without playing the subgame properly first.
\
\ IT WINS THROUGH THE REAL VERDICT PATH and does not shortcut it. All it
\ does is what a won board does: put the human's own colour in xfWinColor
\ and set xfNotInDeck, both AFTER XfCheckEnd has had its say. Everything
\ after that — the "transfer done" message, xfmResult, the end-phase
\ hold, and XferExit4's FinishTransfer1/2 applying the outcome to the
\ droid tables — runs exactly as it does on a genuine win, which is the
\ point: the code under test is the code that ships.
\
\ Losing on purpose needs no key: stop steering.
DEBUG_XFERWIN = TRUE

\ DEBUG_RESTART IS GONE, 2026-08-21. R threw the game away and started
\ another, which was how Layer 11a's boot split got tested before there
\ was a game over to test it with. ESCAPE replaces it — a real feature
\ rather than a debug key, and a stronger test besides, because it goes
\ through the whole of the death, the wash, the 999 page and the title
\ rather than jumping straight back to GameStart. See the loop.

\ DEBUG_DECK is the third: cursor UP and DOWN hop the player straight to
\ the deck above or below, one deck a press, without a lift. It predates
\ Layer 8's lifts and 8b's deck-selection screen, and it is what made
\ every deck reachable while they were being built.
\ IT IS NOT A READOUT, so it belongs off in anything a player will see:
\ the whole ship is walkable now and a hop past a locked deck is not
\ something the C64 can do. Left ON while the decks past 1 are still
\ being brought up, because reaching deck 11 by lift to look at one tile
\ is several minutes a time.
\ The keys are the LIFT'S while liftMode is non-zero, which is why the
\ arm below tests it first: with the flag off that test goes with it,
\ because nothing else here wants UP or DOWN.
DEBUG_DECK = TRUE

\ DEBUG_KILL is the fourth that changes what the GAME does: C kills
\ every droid on the deck, one at a time through DrKillDroid, so the
\ cleared-deck floor (layer-14 DECISION 6) can be reached without
\ shooting a deck empty. It is the REAL kill path -- explosions,
\ sound, score, alert and DrRemoveShip all happen -- so what it tests
\ is the mechanism, not a shortcut past it. src/droid.asm.
DEBUG_KILL = TRUE

\ DEBUG_INVULN pins the player's energy at full, so a run can be taken
\ deep into the ship without a 001's death ending it. Asked for by KC
\ alongside 11b, which is what took the free respawn away: the port used
\ to put you back on waypoint 0 for ever and testing leaned on that.
\
\ IT IS A PIN, NOT A SHIELD. Damage, ageing and the transfer's costs all
\ land as they normally do and are then overwritten at the top of the
\ next CbCheckDeath, so everything downstream of taking a hit still runs
\ -- only the consequence is removed. The panel therefore reads full
\ energy always, which is how you can tell the build from a clean one
\ without reading !BOOT.
DEBUG_INVULN = FALSE

\ TEST_DROIDS and src/droidtest.asm are gone: six static droids, put
\ there so the sprite pool could be measured before there was anything
\ to put in it. src/droid.asm is what they were standing in for.
DBG_SPR      = 5                \ magenta — the sprite pool
DBG_LEVEL    = 3                \ yellow  — DoRedraws, the level draw
DBG_REDRAW   = 6                \ cyan    — keys, movement, CRTC park
DBG_AI       = 1                \ red     — the droid AI and the rest of the
                                \ display-period work. THIS ONE IS SUPPOSED TO
                                \ BE OVER THE PLAY AREA; see the header

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
\   panel   P            7 rows,  4 displayed, R5 = 8-line
\   play    P+64-line   18 rows, 17 displayed, R5 = line
\   tail    P+208       13 rows,  0 displayed, R5 = 0, VSync at row
\                       TAIL_R7 — 5 since FRAME_DROP_ROWS, was 8
\                       ------
\                       38 rows x 8 + 8 adjust = 312 scanlines
\
\ Visible play area: P+64 to P+192, and VSync at P+248 — the geometry
\ Layer 3c had except for where VSync falls, which is what puts the
\ picture on the tube. See FRAME_DROP_ROWS. No RAM changes either way.
\ ---- Layer 9's text font, in main RAM -----------------------
\ IT IS IN MAIN RAM RATHER THAN A BANK because the panel engine lives in
\ bank 4 and the font in bank 6, and only one bank is visible at a time.
\ Main RAM is reachable from both, and from Layer 10's transfer game.
\ See docs/layer-9-hud.md, decision 1.
\ IT MOVED FROM &3C00 TO &3000 FOR LAYER 11, and the sprite save areas
\ and the tile map moved up behind it. The title screen is 25 rows of
\ 640 bytes and wants 16,000 CONTIGUOUS bytes; the only thing standing
\ in the middle of &3000-&7FFF was this font, since at title time no
\ deck is loaded and the save areas, the tile map, the panel and the
\ play buffer are all idle. Below the framebuffer it needs no second
\ home and no second load. The three blocks pack exactly onto
\ PANEL_ADDR: 3,584 + 2,048 + 1,024 = 6,656 = &3000 to &4A00.
\ [DECISION 1] in docs/layer-11-sound-title.md.
\ ---- the low-RAM overlay: resident code below DFS's PAGE ----
\ &0E00-&10FF is the sideways-ROM shared workspace, which on this machine
\ is DFS's and DFS's alone. It is live for as long as the filing system
\ is, and dead the moment the last *LOAD returns — which is the same
\ argument the charset at &0400 already relies on, one page higher up.
\ Nothing may be LOADED here (DFS is using it while it works), so the
\ block is staged high (at LOW_STAGE, on the panel) and copied down.
\
\ PAGE &0D IS DELIBERATELY EXCLUDED. &0D00-&0D5F is the NMI handler and
\ its workspace, &0D9F-&0DEF the extended vector table and &0DF0-&0DFF
\ the sideways ROMs' private-workspace page bytes. The disc is idle so
\ no NMI is expected, but "expected" is not a guarantee and one spurious
\ NMI through a page of 6502 would be unrecoverable. See KC's
\ BEEB/Manuals/AllMem.txt.
\
\ WHY IT EXISTS: main RAM &1100-&3000 was down to 48 free bytes and bank
\ 4 to 10, and the four features of this branch need neither of the two
\ banks that have room, because both are paged out during play. This is
\ the only main RAM left that a bank-4 routine and a main-RAM routine can
\ both call. Layer 11e's sound driver is the other obvious tenant.
\ lowcode.asm's two constants, declared here because beebasm resolves
\ them in file order and src/lowbss.asm is reached first.
DR_SLOTS  = 14                  \ droid table: index 1-13, 0 the player.
                                \ Here rather than in droid.asm because
                                \ lowbss.asm holds three of its arrays now
DISR_FRAMES = 4                 \ Disruptor's own count, $3447
ANIM_MAX  = 8                   \ animated tiles tracked in one view
RECH_CHAR = 76                  \ ChrAnimData1's second group, $7A60

LOWBSS_ADDR  = &0C90            \ and its state, in the tail of the same
LOWBSS_LIMIT = &0D00            \ workspace the charset sits in
\ ---- and the rest of page &0D, below the NMI workspace ------
\ &0D00-&0D5F is the NMI handler and its workspace and is left strictly
\ alone: the disc is idle so no NMI is expected, but one spurious NMI
\ through a page of somebody else's 6502 would be unrecoverable.
\ &0D60-&0DEF is Econet and mouse workspace and the extended vector
\ table — no Econet, no mouse, and nothing here claims an extended
\ vector. &0DF0-&0DFF, the sideways ROMs' private-workspace page bytes,
\ is skipped as well, which is why the copy comes in two pieces.
\ It is ONE FILE with the &0E00 block: the image runs &0D60-&10FF with a
\ hole at &0DF0, so the second copy's source is simply the staging
\ address plus &A0.
LOW2_ADDR  = &0D60
LOW2_LIMIT = &0DF0
LOW2_BYTES = LOW2_LIMIT - LOW2_ADDR
LOW2_SKIP  = &0E00 - LOW2_ADDR  \ what the file holds before the &0E00 half

LOW_ADDR  = &0E00
LOW_LIMIT = &1100
LOW_PAGES = 3
\ Staged on the PANEL rather than at DATA_LOAD, because PARAFNT owns
\ DATA_LOAD and has to be loaded before this one — see the boot code.
\ The panel is not filled until PanelSetup, long after.
LOW_STAGE = &4A00

\ ---- the title screen overlay -------------------------------
\ PARTITL is a seventh disc file, not a resident of bank 7 — [DECISION 6]
\ of docs/layer-11-sound-title.md, restored in Layer 13d: bank 7's free
\ space is spoken for by the droid portrait pool. It loads over PARAFNT's
\ ground, runs there, and is destroyed by PARAFNT's reload the moment the
\ title is done — the two are never wanted at once. It must end below its
\ own framebuffer, TI_BASE = &4000 (defined in title.asm, asserted at the
\ SAVE).
TITLE_ADDR = &3000

\ ---- the boot depacker overlay ------------------------------
\ PARDEPK is an eighth disc file: the ZX0 decompressor (the same macro
\ bank 4 instantiates for BuildLevel — see zx0depack.asm) with a stub
\ that points it at DEPK_STREAM -> SWRAM_BASE. The four bank files ship
\ ZX0-compressed on disc with a catalogue load address of DEPK_STREAM
\ (written by tools/make_disc.py, not by the SAVEs below), and the boot
\ loads PARDEPK once at DEPK_ADDR and JSRs it after paging each bank in.
\ It shares PARAFNT/PARTITL's ground and dies when PARTITL loads; by
\ then all four banks are up and nothing wants it again — the game-over
\ seam reloads no bank.
DEPK_ADDR   = &3000
DEPK_STREAM = &3200

FONT_ADDR = &3000
\ Declared here rather than taken from the generated file, because
\ beebasm resolves constants in file order and droid.asm's MG_COPY
\ assert needs the size before src/data/textfont.asm is reached. The
\ generated file checks itself against both — see the ASSERTs by its
\ INCLUDE. This is the same arrangement SPR_W and SPR_H have.
FONT_GLYPHS = 103               \ 26 capitals are two glyphs each
FONT_BYTES  = FONT_GLYPHS * 16  \ 16, not 32: the font ships 1bpp — see
                                \ FontCell below and export_font.py

\ ---- the status box border, twelve cells --------------------
\ HALF glyphs, 8 packed bytes each: the box is 32 scanlines tall and the
\ border rows contribute only their inner 8 — see PANEL_ADDR below and the
\ header of tools/export_font.py. Loaded as part of PARAFNT, straight
\ after the glyphs.
PN_FRAME_ADDR  = FONT_ADDR + FONT_BYTES
PN_FRAME_CELLS = 12
PN_FRAME_BYTES = PN_FRAME_CELLS * 8

\ ---- the four droid tables, mirrored out of bank 4 ----------
\ panel.asm and console.asm are in bank 6 and cannot read bank 4, so
\ PageTabsIn copies these here at boot. 96 bytes in the tail of the same
\ hole the font sits in — PARAFNT is one block of 3,584 bytes ending at
\ SPR_SAVE, and this is its tail.
\ ---- the $C000 string table, in main RAM --------------------
\ Every name the console prints — the droid classes, the eight ships, the
\ sixteen decks, the four alert levels. It USED TO EXIST TWICE, 1,542
\ bytes in bank 6 for the console main screen and 1,542 more in bank 7
\ for the droid database, because only one bank is visible at a time and
\ each reader could only see its own. Both readers patch a self-modifying
\ absolute with the table's base, so neither cares where it is — and main
\ RAM is visible from both. One copy, in the room the 1bpp font freed.
\ Loaded as part of PARAFNT, straight after the border cells.
\
\ Declared here for the same reason FONT_BYTES is: beebasm resolves
\ constants in file order and PN_TABS below needs the size.
CON_STR_COUNT = 248
CON_STR_BYTES = 1542            \ 1,541 plus the terminating sentinel
CON_STR_ADDR  = PN_FRAME_ADDR + PN_FRAME_BYTES

\ ---- and the font's own decoder -----------------------------
\ FontCell, its 16-byte expansion table and its ink byte, in the PARAFNT
\ file rather than in `&1100`-`&3000`. It has to be MAIN RAM, so that
\ both banks can call it; it does not have to be the CODE IMAGE, which
\ is the only full region and which Layer 11e needs. Declared as a size
\ here for the reason FONT_BYTES is, and ASSERTed against the real one
\ where it is assembled — if it grows, this is the number to bump.
FONTCODE_ADDR  = CON_STR_ADDR + CON_STR_BYTES
FONTCODE_BYTES = 194            \ FontCell, its table, and DoScore


PN_TABS     = FONTCODE_ADDR + FONTCODE_BYTES
pnTabCent   = PN_TABS + 0
pnTabNum    = PN_TABS + 24
pnTabWeapon = PN_TABS + 48
pnTabSpeed  = PN_TABS + 72
ASSERT PN_TABS + 96 <= PANEL_ADDR
ASSERT PN_TABS + 96 <= SPR_SAVE  \ the whole PARAFNT block sits below
                                 \ the save areas now, not above the map

\ ---- the panel is FOUR rows, because the C64's box is 32 scanlines ----
\ The C64 status area is eight character rows, but the artwork inside it
\ is not. StartGame draws four strings ($6900, $6917, $6937, $693C) of
\ 8 x 16 glyphs into screen rows 0-5, and the ink they carry runs from
\ scanline 8 to scanline 39 — a rounded box exactly 32 scanlines tall,
\ with solid surround above it and below. So the box maps onto FOUR BBC
\ character rows:
\
\   row 0   the BOTTOM halves of $55/$56/$57   top border and corners
\   row 1   the text line, top cells           bars, mode, logo, score
\   row 2   the text line, bottom cells
\   row 3   the TOP halves of $58/$59/$7A/$7B  bottom border and corners
\
\ Dropping from 5 rows to 4 is R6 ALONE — it is written at VSync for the
\ panel cycle and nothing else moves. The panel cycle stays 7 rows, the
\ play cycle still starts at P+64-line, and no T1 interval changes. What
\ grows is the gap below the box, from 24-line scanlines to 32-line,
\ which is the C64's own 32-line gap between the box and the deck.
\
\ THE C64 FILLS THAT GAP WITH THE SURROUND COLOUR and we leave it blank,
\ because covering it would need all 8 rows displayed — 5120 bytes, and
\ the panel cycle is only 7 rows long. See docs/layer-9-hud.md.
\
\ PANEL_ADDR moved up from &4800 when the panel shrank: the 640 bytes
\ that freed go to the font, which needs another 448 for the logo and
\ frame glyphs and had only 32 spare below the old panel.
PANEL_ADDR  = &4A00             \ below &5800, clear of the play buffer
PANEL_ROWS  = 4                 \ rows of status box = 32 scanlines
PANEL_BYTES = PANEL_ROWS * ROW_BYTES
PANEL_START = PANEL_ADDR / 8    \ what R12/R13 wants

PANEL_CYC_ROWS = 7
PLAY_CYC_ROWS  = 18
TAIL_CYC_ROWS  = 13
PANEL_R4 = PANEL_CYC_ROWS - 1   \ 6
PLAY_R4  = PLAY_CYC_ROWS - 1    \ 17
TAIL_R4  = TAIL_CYC_ROWS - 1    \ 12

\ ---- WHERE THE PICTURE SITS ON THE TUBE ---------------------
\ The television locks to VSync and counts down from it, so moving VSync
\ EARLIER in our frame moves the picture DOWN: everything after it is
\ then further from the sync the set is measuring against. The frame is
\ still 312 scanlines and the three cycles are untouched — all that
\ changes is how the 120 scanlines of blanking are split between the
\ front porch (picture bottom -> VSync) and the back porch (VSync ->
\ panel top).
\
\ At 0 the panel top is 40 scanlines after VSync and the picture sits
\ high, with the black stacked under it. KC, 2026-08-21: four rows down,
\ then back up one — four looked LOW. That leaves 56 scanlines of front
\ porch and 64 of back — both far beyond PAL's ~5 and ~25, so the set has
\ no trouble with either.
\
\ TWO constants move together and this is why they are one: the T1 chain
\ is restarted at VSync, so every fire in the frame is measured from it.
\ Shift VSync without shifting T1_I1 and the whole rupture — the panel's
\ registers, the play cycle's blank and unblank — arrives a rowful of
\ scanlines into the wrong part of the frame.
FRAME_DROP_ROWS = 3             \ character rows the picture moves DOWN

\ Layer 11f: the plain frame SetupPlain restores, which is what the OS's
\ own VDU 22 leaves MODE 1 at, less the drop. title.asm's MODE1_R7 is the
\ same 34 and is declared there because TiCRTC needs it in that file.
PLAIN_R4 = 38                   \ 39 rows of 8 = 312 lines
PLAIN_R7 = 34 - FRAME_DROP_ROWS

TAIL_R7  = 8 - FRAME_DROP_ROWS  \ VSync at P+208+40 = P+248
ASSERT TAIL_R7 >= 0
ASSERT TAIL_R7 <= TAIL_R4       \ it has to fall inside the tail cycle

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
\ Fire 1's window is [P+32, P+48]: it cannot blank before P+32, where
\ the panel's four displayed rows end, and it must write R4 = 6 before C4 reaches
\ 6 at P+48. Fires 2 and 3 must land inside horizontal blanking —
\ MODE 1 displays 80 of 128 character times, so ~24 us of the 64 us
\ line is available and a write in the displayed part cuts that
\ scanline part-way across.
\
\ VSync -> fire 1 is 84 scanlines with the picture where the CRTC's own
\ geometry puts it, and 8 more for every row FRAME_DROP_ROWS moves it
\ down: VSync comes earlier, the panel does not move, so the gap grows.
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

T1_I1 = (84 + FRAME_DROP_ROWS * 8) * SL - 2 + T1_TUNE - T1_PROBE
T1_I2 = 20 * SL - 2 + T1_PROBE  \ fire 1 -> fire 2, P+44 -> P+64
T1_I3 = PLAY_VIS_ROWS * 8 * SL - 2   \ fire 2 -> fire 3, the visible height

\ EVERY NON-GAMEPLAY SCREEN'S fire 3, one character row later: with the
\ scroll flat, all 16 buffer rows are real content and the R8 blank at
\ fire 3 is the ONLY thing hiding the 16th — the display window is
\ already 16 rows (PLAY_R6). The rupture reads the interval from
\ t1i3Lo/Hi, so a screen that owns the buffer can move the bottom edge
\ down a row.
\
\ THE SCREENS SET IT AND ReframeView PUTS IT BACK. Only the scrolled deck
\ wants 15 rows; the transfer board, the lift's deck select, the console
\ and all its pages, the four information screens and the game over's
\ wash all want 16. So the sixteen-row state is set at each screen's
\ entry — XferEnter4, LiftViewEnter, ConsoleOpen, IsStart, GoWashStart —
\ and restored in ONE place, ReframeView, which every path back to the
\ deck goes through. The per-screen exits used to restore it themselves;
\ that was three copies of these four instructions in bank 4, which has
\ no bytes to spare, and one of them (the deck plan's) had to be undone
\ by the console's own the moment the page closed.
\ Agreed with KC 2026-08-21: all the non-gameplay screens use 16 rows.
T1_I3X = (PLAY_VIS_ROWS + 1) * 8 * SL - 2

\ ONLY THE HIGH BYTE OF THE INTERVAL EVER CHANGES, and that is structural
\ rather than lucky: the two differ by one character row, a row is 8
\ scanlines, and a scanline is SL = 64 ticks — so the difference is &200
\ exactly, and the low byte of every whole-row interval is the same. So
\ t1i3Lo is a constant the rupture reads and nobody writes, and switching
\ the bottom edge is five bytes instead of ten. That matters: there are
\ six sites, one of them in main RAM, which had FOUR bytes free when this
\ was built. The ASSERT is what keeps it true if SL or the row height
\ ever moves.
ASSERT LO(T1_I3) == LO(T1_I3X)

SYS_VIA_T1CL = &FE44
SYS_VIA_T1CH = &FE45
SYS_VIA_T1LL = &FE46
SYS_VIA_T1LH = &FE47            \ latch only — does not reload the counter
SYS_VIA_ACR  = &FE4B
SYS_VIA_IER  = &FE4E
USR_VIA_IER  = &FE6E
USR_VIA_T1CL = &FE64            \ free-running 1 MHz counter — DEBUG_TIME
USR_VIA_T1CH = &FE65

\ ---- the SN76489's route in: System VIA port A --------------
\ The same port the keyboard matrix uses, which is why sound.asm's
\ SndWrOpen/Close save and restore DDRA and ORA around every burst
\ of writes — verified against OSBYTE &81 in tools/sndtest.asm,
\ layer-11e stage 0. The strobe is addressable-latch bit 0 via
\ port B; writes 0/8 touch no other latch bit.
SND_PORTB = &FE40
SND_DDRA  = &FE43
SND_ORA   = &FE4F

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
\ ---- BuildCharset's nibble tables, out of bank 4 ------------
\ 64 bytes of deck-load scratch that used to sit in the data bank, moved
\ into the 64 free bytes below the character tables — the ones PnClear
\ used to wipe. Bank 4 is the tightest region in the machine and this is
\ read by nothing but BuildCharset and BuildLampChar, so the move costs
\ nothing and buys the bank a routine's worth of room.
LUTS_ADDR = &54C0
LUTs = LUTS_ADDR
ASSERT LUTS_ADDR >= UNITMUL_HI + PLAY_UNITS
ASSERT LUTS_ADDR + 64 <= CHAR_PTR_LO

CHAR_PTR_LO = &5500             \ character code -> charset address
CHAR_PTR_HI = &5600
SPR_MASKTAB = &5700             \ data byte -> its transparency mask
ASSERT CHAR_PTR_LO >= PANEL_ADDR + PANEL_BYTES

\ The row and unit offset tables live here too, and for the same
\ reason: n * 640 and n * 8 are pure arithmetic, so shipping 192 bytes
\ of them inside the code image was 192 bytes of the ONE region that
\ is actually scarce. BuildMulTabs writes them at startup instead.
\ They must stay in MAIN RAM whatever else moves — SetCell reads them
\ with the SPRITE bank paged in. See bufcore.asm's header.
MUL_TABS   = &5400
ROWMUL_LO  = MUL_TABS
ROWMUL_HI  = ROWMUL_LO + PLAY_ROWS
UNITMUL_LO = ROWMUL_HI + PLAY_ROWS
UNITMUL_HI = UNITMUL_LO + PLAY_UNITS
ASSERT MUL_TABS >= PANEL_ADDR + PANEL_BYTES
ASSERT UNITMUL_HI + PLAY_UNITS <= CHAR_PTR_LO
ASSERT CHAR_PTR_HI == CHAR_PTR_LO + 256
ASSERT CHAR_PTR_HI + 256 <= SPR_MASKTAB

\ The deck the game starts on: 4, 5, 6 or 7, chosen at random. $12B6
\ computes it as `random AND 3` plus this. See the startup block.
DECK_START_LO = 4

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
\
\ $D021 is NOT here, because it is not shared: the play area's
\ background is slot 0 of each deck's colour record. It was a
\ constant 14 until 2026-08-17, which is right for decks 2 and 7
\ only — see tools/export_bbc.py's deck_background(). The sixteen
\ values used to ship as a deckBg table; they are not shipped at
\ all now, because the only thing that read them looked up a
\ logical colour that is ALWAYS 0. See BuildCharset.
\ $D022/$D023 are NOT here either: the play area is hires, so the
\ multicolour pair never applies to it. DrawSideview sets them for
\ its own screen. Removed 2026-08-18 with the multicolour path.
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
KEY_W      = &DE                \ -34, DEBUG_XFERWIN only
KEY_C      = &AD                \ -83, DEBUG_KILL only
KEY_ESCAPE = &8F                \ -113, the self-destruct

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
\ THE ORDER WITHIN THE BLOCK IS LOAD-BEARING, and it was not always.
\ The five below are the ones whose value CROSSES A SPRITE DRAW:
\ SprSplitOK reads bandDo and colCount, and ReframeView clears the
\ pair after SprDrawAll has run, so they are live from one pass into
\ the next. The eleven after them are consumed no later than the end
\ of DoRedraws, which the main loop runs before SprDrawAll — so they
\ are dead at the moment the blitter starts, and sprite.asm's colour
\ table aliases the whole run at &05-&0F. See SprSetColour.
\ THE INVARIANT THAT BUYS THIS: nothing inside SprDrawAll's call tree
\ may run the level draw. It does not today — SprSetSlot's only call
\ out is SetCell, which touches rCount, uCount, scrollS and bufp and
\ nothing here. Break that and the symptom is a corrupted sprite
\ COLOUR, not a corrupted level, so it will not look like what it is.
bandDo    = &00                 \ a character row was crossed
colFirst  = &01                 \ first column exposed by the move
colCount  = &02                 \ how many
sDelta    = &03                 \ scrollS delta for the move       (2)

\ ---- &05-&0F: dead once DoRedraws has finished ---------------
subRowOfs = &05                 \ (cellY AND 3)*4, the row within a tile
tileCol   = &06                 \ BandCharPtr's cached tile column
colTileCol = &07                \ DrawColumn: its fixed tile column
colSubX   = &08                 \ and character within the tile
colHalf   = &09                 \ 0 or 8: which half of the character
colTileRow = &0A                \ cached tile row, changes every 4
dbTile    = &0B                 \ DrawBandRows: tile column being walked
dbSub     = &0C                 \ first character within it
dbOdd     = &0D                 \ mapHX odd: row starts on a right half
bandRow   = &0E                 \ which map character row
bandRc    = &0F                 \ and which display row it lands in

\ ---- and the same eleven bytes, wearing the other hat ---------
\ The compiled sprite code reaches its pixels through here rather than
\ as immediates, so one set of generated routines draws in any of the
\ three logical colours. SprSetColour rewrites them; export_droids.py
\ emits `ORA colPix+n` and picks n from the byte's opacity pattern.
colPix    = &05                 \ SPR_COLPATS bytes, through &0F

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
fieldCount = &21                \ windows opened, bumped by the IRQ at fire 3
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
\ GUARD, NOT JUST AN ASSERT. The code image ends where PARAFNT begins,
\ and beebasm's overwrite check does not catch the overrun on its own:
\ the `CLEAR FONT_ADDR, ...` further down releases the guard over
\ exactly the range the code would spill into, so an over-long image
\ assembles silently, `*RUN PARA` scribbles on the first bytes of the
\ text font, and the PARAFNT load then scribbles back over the code's
\ tail. **DEBUG_VSYNC did precisely that, unnoticed, for weeks** — the
\ only bound in the file was `code_end <= SPR_SAVE`, left over from when
\ the font lived at &3C00.
\ GUARD fires DURING assembly, at the instruction that crosses the line,
\ so it names the routine rather than a total at the end. The ASSERT by
\ `.code_end` is the belt to this pair of braces.
GUARD FONT_ADDR

ORG &1100
.start

\ MODE 1 ONLY. The rupture's CRTC shape is set AFTER the loads, in
\ SetupRupture, because R7 = TAIL_R7 stops VSync and the MOS's disc
\ code hangs without it — the same rule as InstallIrq's below, one
\ step earlier. bufcore.asm's header has the measurement.
  JSR SetupMode

  LDX #LO(loaddepk)             \ must follow the mode change: VDU 22
  LDY #HI(loaddepk)             \ clears what the OS thinks is its screen.
  JSR OSCLI                     \ The boot depacker, loaded once at
                                \ DEPK_ADDR and reused for all four banks

  LDX #LO(loadcmd)              \ PARADAT's ZX0 stream lands at DEPK_STREAM
  LDY #HI(loadcmd)              \ and is unpacked straight into SWRAM; the
  JSR OSCLI                     \ staging area is free after
  LDA #SWRAM_DATA
  JSR UnpackBankIn

  LDX #LO(loadspr)              \ and again for the sprite bank, staged over
  LDY #HI(loadspr)              \ the same DEPK_STREAM. The filing system
  JSR OSCLI                     \ pages DFS in and out around its own call
  LDA #SWRAM_SPR                \ and restores from ROMSHAD, which
  JSR UnpackBankIn              \ UnpackBankIn has kept honest, so the
                                \ second load is no different from the first

  LDX #LO(loadspr2)             \ and a third: shifts 2 and 3 px live in a
  LDY #HI(loadspr2)             \ bank of their own, because four compiled
  JSR OSCLI                     \ shifts do not fit in one
  LDA #SWRAM_SPR2
  JSR UnpackBankIn

  LDX #LO(loadxfer)             \ and a fourth bank: the transfer minigame,
  LDY #HI(loadxfer)             \ staged through DEPK_STREAM like the others
  JSR OSCLI
  LDA #SWRAM_XFER
  JSR UnpackBankIn

\ ---- the title, and everything that rebuilds after it ------
\ TitleSeq is shared with the game-over seam (GoTitle): load PARTITL,
\ show the title, reload PARAFNT and PARALOW over it, rebuild every
\ table under the title's framebuffer, raise the rupture and take the
\ IRQ. On this path the CRTC is already in SetupMode's plain shape and
\ the MOS still owns the machine, which is what its loads require.
  JSR TitleSeq

\ ---- the random seed --------------------------------------
\ It is TiBootPal's now (src/title.asm), taken from the same sample
\ of the same free-running counter as the random boot deck.

\ ---- everything above happens ONCE -------------------------
\ Restart0 ($1078) against the StartGame ($1242) that TitleLoop reaches:
\ the hardware, the disc, the banks and the tables above are the
\ cold-boot half and survive a restart. Everything a game writes belongs
\ to GameStart, which is in bank 4 beside the droid tables it seeds.
\ Layer 11 needs the game startable more than once — 11a in
\ docs/layer-11-sound-title.md.
  JSR BrDispatch                \ ...and the 001 screen in front of it.
                                \ Layer 11f: BrDispatch, not GameStartInfo
                                \ — if the title timed out this is where
                                \ the briefing runs first. PARBRF is
                                \ valid: TiShow loads it on every title

\ ============================================================
\ Main loop
\ ============================================================
.mainloop
  \ Released once the play area is off-display, not at VSync. The
  \ edge redraw and the R12/R13 park both have to land before the
  \ play area is drawn again.
    \ THE PASS IS DATED FROM THE WINDOW IT STARTS IN, and it takes its
  \ fields one at a time: this is the first of the two windows, and the
  \ second is taken further down after the drawing and the droid AI.
    \ Nothing is consumed here — the loop arrives already inside window
  \ A, because the wait at the bottom released it there. Stamping the
  \ counter is all that is needed, and a pass that overran simply
  \ starts from a later field with its full budget rather than being
  \ rounded up to the next boundary. See docs/raster-timing.md.
  LDA fieldCount
  STA passF0
  INC gameTick                  \ the C64's frameCount: one per ITERATION,
                                \ never reset, and the clock the aging and
                                \ recharge periods are expressed in
IF DEBUG_VSYNC
  JSR DbgFrameCount             \ the boundary has just happened, so this
ENDIF                           \ counts the iteration that has finished
IF DEBUG_POS
  JSR DbgPosOut                 \ where we are, for getting back here
ENDIF
\ ============================================================
\ The score and the disruptor — MOVED OUT OF THE WINDOW
\ ============================================================
\ Both used to run here, at the top of the pass, and both write no play
\ buffer at all: DoScore moves banked points onto the panel and
\ CbDisruptor writes the droid table and a flag the interrupt reads. The
\ window is 24,576 cycles and the drawing needs every one of them, so
\ they run below the draw now, at ml_afterdraw.
\
\ THEY STILL RUN IN EVERY STATE, which is what put them at the top of
\ the pass in the first place. GameLoop calls DoScore at $13E3 BEFORE it
\ tests consoleState at $1427, so it runs whether the console is up or
\ not; and a disruptor burst frozen by a modal state would leave our
\ flash on the screen. So ml_afterdraw sits immediately above ml_passend
\ — the one point EVERY arm of the pass converges on, the four modal
\ ones included — rather than beside the droid AI, which the modal arms
\ jump over.
\ ============================================================
\ ...or the game is over
\ ============================================================
\ Phase 2 only. Phase 1 is the explosion cloud and rides the ordinary
\ pass — it needs the sprite pool erased and drawn like any other frame,
\ and it is driven from CbCheckDeath near the end. Phase 2 is EndGame's
\ wash, which OWNS the play buffer the way the console and the transfer
\ do, so it takes their shape: one tick, then straight to the end of the
\ pass. That also keeps PanelTick off the line the message is on.
  LDA overPhase
  CMP #2
  BNE ml_noover
  JSR GoTick7
  JMP ml_passend
.ml_noover

\ ============================================================
\ The console has the machine, or it does not
\ ============================================================
\ GameLoop tests consoleState at $1427 and jumps past EnterGame's DoMove
\ and DrawScreen when it is set, which is exactly this: with the console
\ up nothing may move and nothing may write the play buffer, because the
\ console IS the play buffer. So the whole middle of the pass is skipped
\ and only the page keys are read.
\ The HUD still runs. The C64's status rows survive GotoHires too.
  LDA conActive
  BEQ ml_noconsole
  JSR ConsoleTick
  JSR PanelTick
  JMP ml_passend
.ml_noconsole

\ ============================================================
\ ...or one of Layer 11d's information screens
\ ============================================================
\ Same rule as the three above: the screen IS the play buffer, so
\ nothing moves and nothing else draws. No PanelTick — these screens do
\ not touch the panel, and the C64's status rows survive GotoHires too.
  LDA infoActive
  BEQ ml_noinfo
  LDX #0                        \ IsEntry's "tick" door — X, because
  JSR InfoCall                  \ PAGEBANK is LDA #bank and eats A
  JMP ml_passend
.ml_noinfo

\ ============================================================
\ The transfer game has the machine, or it does not
\ ============================================================
\ Layer 10, on the console's pattern: with the game up nothing moves and
\ nothing else writes the play buffer, because the board IS the play
\ buffer. NO PanelTick — the game owns the panel's text line for its
\ counter and its verdicts, and XferExit's PanelSetup repaints.
  LDA xferActive
  BEQ ml_noxfer
  JSR XferTick
  JMP ml_passend
.ml_noxfer

\ ============================================================
\ ...or the lift's deck-selection screen has it
\ ============================================================
\ Layer 8b, on the same pattern: liftMode 2 means the side view owns
\ the play buffer and the panel line, and one tick a pass is all that
\ runs. State 1 — the entering pass — falls through: it is consumed at
\ the hook after DroidsUpdate below.
  LDA liftMode
  CMP #2
  BNE ml_nolview
  JSR LiftViewTick
  JMP ml_passend
.ml_nolview

\ ============================================================
\ ESCAPE — the influence device destroys itself
\ ============================================================
\ A WAY OUT OF A GAME, and the port's own: the C64 has no equivalent —
\ its only abort is the RUN/STOP that DoPause reads, which pauses. KC
\ asked for one 2026-08-21 and it is a game feature, not a debug key.
\ It replaces DEBUG_RESTART's R, which threw the game away and started
\ another; this ends it properly, through everything a real death runs.
\
\ IT KILLS HIM AS A 001, whatever he was riding. CbCheckDeath's $144D
\ arm is the whole mechanism — a captured droid falls back to a 001 and
\ plays on, and a 001 has nothing to fall back on, so the game is over —
\ and forcing the type is how "end the game" is said in that language.
\ The explosion, the sound, the wash, the 999 page and the title all
\ follow from it with nothing else added.
\
\ BELOW the four modal arms, unlike the R it replaces: each of those
\ ends the pass, so this cannot fire while the console, the lift view,
\ the transfer game or an information screen owns the machine. That is
\ deliberate — those states have their own way out, and a half-finished
\ transfer applying its outcome to a player who is already dead is a
\ tangle with no reason to exist.
\
\ No edge latch. Both writes are idempotent, and once overPhase is set
\ the game-over arm above takes the pass before this is reached again.
  LDX #KEY_ESCAPE
  JSR keydown
  BNE ml_notEsc
  LDA #0
  STA drType
  STA drEnergy
.ml_notEsc

  \ Z / X left-right, K / M up-down. The keys feed a direction pair
  \ and the direction pair feeds an accelerating speed, so the view
  \ position moves by 0-7 pixels a frame rather than a fixed step.
IF DEBUG_TIME
  JSR DbgSpeedOverride          \ a poked speed takes the controls over
  BNE ml_poked                  \ and skips the walls; zero gives them back
ENDIF
  LDA overPhase                 \ the game is ending: $14A8 calls RunGame
  BNE ml_nomove                 \ and nothing else, so he stops where he
                                \ fell and the cloud burns over him
  LDA liftMode                  \ the lift has the controls: no movement,
  BNE ml_nomove                 \ and UP/DOWN mean something else below
  JSR ReadKeys
  JSR CalcSpeed
  JSR CheckWalls                \ before the move, as the C64 does: it
.ml_poked                       \ zeroes the speed the move would apply
.ml_nomove
  JSR ApplyMove

\ ============================================================
\ Fire — and the lift gets first refusal on the same key
\ ============================================================
\ L DOES DOUBLE DUTY, which is what the C64 does too: there, fire drives
\ the moveMode machine and DoCharUnder gates the lift countdown on it.
\ We keep lift.asm's explicit trigger instead, so the two have to be told
\ apart here — the lift takes the press when there is a lift to take it,
\ and the weapon gets it otherwise.
\
\ THIS BLOCK MOVED UP FROM BELOW THE LEVEL DRAW. DoFire activates slot 7,
\ and the tranche assignment in SprSplitOK has to see it, so everything
\ that changes slot state must happen before the erase — the same reason
\ the movement is up here. Nothing in LiftEnter/LiftExit draws; the
\ deck-hop keys, which do, stay where they were.
  LDA overPhase                 \ the game is ending: the C64's loop calls
  BNE ml_lDone                  \ RunGame and nothing else, so no fire, no
                                \ moveMode and no bullet. SLOT 7 IS THE
                                \ BULLET'S and the cloud lights it — leave
                                \ MovePlyFire running here and it puts the
                                \ slot out again on the next pass
  LDA #0
  STA fireDown
  LDX #KEY_L
  JSR keydown
  BNE ml_lUp
  LDA #1 : STA lDown
  LDA prevRet
  BNE ml_lHeld
  LDA #1 : STA prevRet          \ the press edge
\ liftMode can only be 0 here: with the view up the pass short-circuits
\ at the lift arm long before this block, so the old exit-on-fire arm is
\ gone — leaving the lift is LiftViewTick's commit now.
  JSR LiftEnter
  LDA liftMode                  \ did it take? if not, the press is the gun's
  BEQ ml_lHeld
  LDA #1 : STA fireEaten
  JMP ml_lDone
.ml_lHeld
  LDA fireEaten
  BNE ml_lDone
  LDA liftMode
  BNE ml_lDone
  LDA #1 : STA fireDown
  JMP ml_lDone
.ml_lUp
  LDA #0
  STA prevRet
  STA fireEaten
  STA lDown
.ml_lDone

  LDA overPhase
  BNE ml_nofire
  JSR DoMoveMode                \ and DoFire, when it decides to
  JSR MovePlyFire
.ml_nofire

\ ============================================================
\ Erase, and decide first whether the pool can be split
\ ============================================================
\ THE MOVEMENT RUNS BEFORE THE ERASE, which it did not used to. It is
\ what decides how much work DoRedraws has, and that decides whether
\ the pool may be split this pass — a question that has to be answered
\ before anything is restored, because the two paths erase different
\ sets of slots. Nothing is lost by the order: the restore replays the
\ addresses the DRAW recorded, so it does not care where anything has
\ moved to since.
\ ---- the animated tiles, ahead of every draw ----------------
\ AnimTick rotates the recharger's four characters inside the charset,
\ so it has to run before anything reads it — and its answer is whether
\ there is buffer work to do, which SprSplitOK needs before it decides.
\ AnimPaint, below, is the half that writes; AnimScanPass, after the
\ draw, is the half that COSTS — 10,060 cycles of the window until it
\ was moved out of it. See docs/raster-timing.md.
  JSR AnimTick

  JSR SprSplitOK
  STA sprSplit
  BEQ ml_whole

IF DEBUG_DRAW
  LDA #DBG_SPR : JSR DbgSetBg
ENDIF
  LDA #0
  JSR SprRestoreTr              \ tranche A only; B stays on screen, which
  JMP ml_erased                 \ is safe because nothing else writes the
                                \ buffer on a split pass
.ml_whole
IF DEBUG_DRAW
  LDA #DBG_SPR : JSR DbgSetBg
ENDIF
  JSR SprRestoreAll             \ the saved pixels belong at the address
.ml_erased                      \ they were taken from
IF DEBUG_DRAW
  LDA #DBG_REDRAW : JSR DbgSetBg
ENDIF

  \ Park the CRTC address ONCE, with every axis accounted for, and
  \ before any drawing — the IRQ latches it at frame row 3, only a
  \ few rows into this window.
  JSR SetCRTCStart
IF DEBUG_DRAW
  LDA #DBG_LEVEL : JSR DbgSetBg \ the level draw on its own: it is the
ENDIF                           \ band that varies with the direction
\ THE LEVEL DRAW RUNS ON A SPLIT PASS TOO, which it did not used to.
\ A split pass used to be DEFINED as one with no band, no columns and
\ no doors, so this was skipped; SprSplitDecide now forces any sprite
\ standing under the draw into tranche A instead, which is what makes
\ the two safe together. Skipping it here after that change would stop
\ the deck scrolling. See docs/raster-timing.md.
IF DEBUG_TIME
  JSR TimeCall                  \ TimeCall calls DoRedraws — see its header
ELSE
  JSR DoRedraws
ENDIF
\ The animated tiles that are on screen already. A no-op unless AnimTick
\ found some, and when it did the pass is not a split one — so this is
\ always inside the window the level draw just used.
  JSR AnimPaint
IF DEBUG_DRAW
  LDA #DBG_REDRAW : JSR DbgSetBg
ENDIF

  \ Deck keys are edge triggered: one press steps one deck however
  \ long it is held. A blocking wait-for-release deadlocks if the
  \ other deck key goes down before the first is released.
\ L was handled at the top of the pass, where it has to be: DoFire
\ activates a sprite slot and SprSplitOK must see it.

\ UP and DOWN belong to the lift while it has the controls. Outside one
\ they are DEBUG_DECK's free hop, one deck a press and no lift needed.
\ The whole block is the flag's, the liftMode test included: nothing
\ else in the pass wants either key, and a build without the hop should
\ not be reading them at all. Two OSBYTEs a pass, inside the window.
IF DEBUG_DECK
  LDA liftMode                  \ entering the lift: the debug hop keeps
  BNE ml_notDn                  \ its hands off the deck this pass

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
ENDIF

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

  JSR SprAnimateAll             \ last: the buffer is settled, so the save
  LDA sprSplit                  \ picks up the background the frame will show
  BEQ ml_drawall
  LDA #0
  JSR SprDrawTr
  JMP ml_drawn
.ml_drawall
  JSR SprDrawAll
.ml_drawn
IF DEBUG_DRAW
  LDA #DBG_AI : JSR DbgSetBg    \ THE MAGENTA BAND ENDS HERE, and until
ENDIF                           \ 2026-08-20 it did not: the tint set before
                                \ SprAnimateAll ran on until the tranche-B
                                \ block at the far end of the pass, so it was
                                \ reporting the droid AI, the panel and the
                                \ WaitWindowB idle as sprite work and reaching
                                \ well into the play area. Nothing was
                                \ overrunning. It went wrong when Step 1 moved
                                \ DroidsUpdate below the draw and left the
                                \ closing tint where it was.

\ ---- the animated-tile list, for the NEXT pass --------------
\ The window is shut and the beam is over the play area, which is where
\ a routine that reads the map and writes no buffer belongs. It rebuilds
\ the list only when the view has crossed a tile column, so most passes
\ pay twenty cycles for the test and nothing else.
\ ABOVE DroidsUpdate on purpose: it borrows `maprow`, which the band
\ draw owns and the droid AI also uses, and this is the gap between the
\ two where it is dead.
  JSR AnimScanPass

\ ============================================================
\ The droids run HERE, after the drawing, and that is deliberate
\ ============================================================
\ Everything above this line writes the play buffer and therefore has
\ to happen while the play area is off display — 192 scanlines, 24,576
\ cycles — and the level draw has only the 22,016 up to the CRTC latch
\ at fire 1. DroidsUpdate writes NOTHING into the buffer, and at
\ ~17,000 cycles it was the single largest thing standing between the
\ window opening and the level draw: measured, the work ahead of
\ DoRedraws came to 30,780 cycles against that 22,016 deadline, so the
\ newly exposed column was being written while the beam displayed it.
\n\ Moved down here it runs during the play area's own display, where a
\ routine that touches no buffer costs nothing visible, and the level
\ draw gets its window back. Measured over 128 passes scrolling on the
\ diagonal, entering DoRedraws with the play area on screen: 116 of
\ 128 before, 0 of 128 after. See docs/raster-timing.md.
\n\ WHAT IT COSTS IS ONE PASS OF LATENCY. The slot positions this writes
\ are the ones the NEXT pass draws, so a droid appears where it was
\ 40 ms ago. At 25 Hz and 1-8 px a pass that is not visible, and the
\ player is untouched — his movement stays above, because the scroll
\ depends on it.
\n\ Three things make it safe to run after the draw rather than before:
\   - the restore replays the DRAW's own addresses (sprPtr0/sprScan0),
\     not sprUnit, so moving a slot after it has been drawn is already
\     something the blitter expects;
\   - a slot freed here still has sprSaved set, so the next restore
\     puts its background back before SprDrawAll clears the flag;
\   - a door probed here is held open by the NEXT pass's DoorsUpdate,
\     one pass later than before but never closing under a droid that
\     is still standing at it.
  LDA overPhase                 \ $14A8/$14C5 call RunGame and NOT
  BNE ml_nodroids               \ RunDroids: the ship stops while the
  JSR DroidsUpdate              \ player burns
.ml_nodroids

\ ---- did the collision pass start a transfer? ---------------
\ GameLoop tests xferDroid straight after DoCollision ($13EF) and calls
\ Capture; ours enters here and the next pass takes the xferActive arm
\ above. The rest of this pass is skipped — the board draw is about to
\ overwrite everything the tranches would have repaired.
\ LAYER 11d PUTS TWO SCREENS IN FRONT OF THE BOARD — ShowXferInfo
\ ($3734), which is where the C64 shows them too: Capture calls it
\ before SubGameSelectSide. The target's TYPE is gathered here and not
\ in bank 7, because drType is bank 4's and this is one of the places
\ main RAM can still see it. The player's own comes from pmType.
\ IsDone chains page 2, and its IS_ACT_BOARD comes back to XferEnter.
  LDA xferDroid
  BEQ ml_noxstart
  TAX
  LDA drType,X
  STA xfmTgtType
  LDX #IS_SCR_XFER1+1
  JSR InfoCall
  JMP ml_passend
.ml_noxstart

\ ---- or did fire on a lift platform stage the side view? ----
\ LiftEnter set liftMode 1 in the fire block earlier this pass; the
\ sprites have drawn, so the board can take the buffer over now, the
\ way the transfer does. Next pass takes the liftMode 2 arm above.
  LDA liftMode
  CMP #1
  BNE ml_nolstart
  JSR LiftViewEnter
  JMP ml_passend
.ml_nolstart

  \ Alongside the AI and for the same reason: it writes no buffer. The
  \ droid the player is riding wears out here.
IF DEBUG_MAPGUARD
  JSR MapGuardCheck             \ has anything scribbled on the tile map?
ENDIF
  JSR CbCheckDeath              \ after the collisions that could cause it
  JSR DoAging
  JSR SndAmbient                \ Layer 11e: the hum, the low-energy alarm
                                \ and the transfer pulse — bank 4, resting
                                \ state, play path only
  JSR DoCharUnder               \ and a recharge pad puts it back, at 5
                                \ points of score each. Reads plyCX/plyCY,
                                \ which CheckWalls left earlier in the pass
IF DEBUG_ENERGY
  JSR DbgEnergyOut
ELSE
  JSR PanelTick                 \ Layer 9's HUD, through the bank-6 bridge.
                                \ Writes only the panel, which nothing scrolls
                                \ and nothing blits over, so it is outside
                                \ every window the play area needs
ENDIF

IF DEBUG_DRAW
  JSR DbgDeckBg                 \ the AI band ends at the work, not at the
ENDIF                           \ wait: what is left untinted is real slack

  \ The second window. Everything above ran in the first one and the
  \ display that follows it.
  JSR WaitWindowB

  \ Tranche B, erased and redrawn inside this window so that no field
  \ ever displays it missing. On a whole pass it was drawn up there
  \ with the rest and there is nothing to do here.
  LDA sprSplit
  BEQ ml_nob
IF DEBUG_DRAW
  LDA #DBG_SPR : JSR DbgSetBg
ENDIF
  LDA #1
  JSR SprRestoreTr
  LDA #1
  JSR SprDrawTr
IF DEBUG_DRAW
  JSR DbgDeckBg
ENDIF
.ml_nob

IF DEBUG_DRAW
  JSR DbgDeckBg
ENDIF

\ ---- the score and the disruptor ----------------------------
\ Below every draw in the pass, tranche B included, and above the point
\ all four modal arms converge on. Neither writes the play buffer.
.ml_afterdraw
  JSR DoScore
  JSR CbDisruptor

.ml_passend
IF DEBUG_DRAW
  JSR DbgDeckBg                 \ the four modal arms JMP here, over every
ENDIF                           \ other close: no band may outlive a pass
  \ The pass is not allowed to be shorter than FRAME_LOCK fields. It IS
  \ allowed to be longer: an overrun carries on from wherever it landed
  \ instead of being rounded up to the next boundary, so a heavy pass
  \ costs what it costs and the rate recovers on the next one. The
  \ movement model wants a fixed pass, so this is a trade — a brief
  \ overrun now shows as a brief speed-up rather than a step down to
  \ 16.7 Hz for as long as the load lasts.
  JSR WaitNextPass
  JMP mainloop

.loaddepk
  EQUS "LOAD PARDEPK"
  EQUB 13
.loadcmd
  EQUS "LOAD PARADAT"
  EQUB 13
.loadspr
  EQUS "LOAD PARASPR"
  EQUB 13
.loadspr2
  EQUS "LOAD PARSPR2"
  EQUB 13
.loadxfer
  EQUS "LOAD PARXFER"
  EQUB 13
.loadfnt
  EQUS "LOAD PARAFNT"
  EQUB 13
.loadlow
  EQUS "LOAD PARALOW"
  EQUB 13
.loadtitl
  EQUS "LOAD PARTITL"
  EQUB 13

\ ============================================================
\ UnpackBankIn — fill a sideways RAM bank from its ZX0 stream
\ ============================================================
\ The four bank files ship ZX0-compressed and *LOAD at DEPK_STREAM
\ (a catalogue address tools/make_disc.py writes). They cannot be
\ loaded straight into the bank even uncompressed: while the filing
\ system is working, the MOS has the DFS ROM paged in at &8000, so
\ the bytes would land in the ROM socket and be discarded. A selects
\ the bank; the PARDEPK overlay at DEPK_ADDR (loaded just before, and
\ resident until PARTITL lands on it) unpacks DEPK_STREAM -> &8000.
\ Boot-only, before InstallIrq: the MOS IRQ touches no bank.
\
\ The data bank stays selected from here on. Every character drawn
\ reads `tiledefs` through it, so it cannot be paged out during play.
\ (`charRemap` used to be read every frame too; it is now folded into
\ CHAR_PTR_LO/HI at startup and never touched again.) That displaces
\ BASIC, which we
\ never return to, and not DFS, which lives in its own socket and
\ which the MOS pages in and back out around each of its own calls.
.UnpackBankIn
  STA ROMSHAD                   \ both, always — see the note at the top
  STA ROMSEL
  JMP DEPK_ADDR                 \ its RTS returns to our caller

\ PageCopyAt — the staging copy: X = pages, swSrc and swDst set.
.PageCopyAt
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

\ ---- and the overlay, down to &0E00 rather than up to a bank ----
\ No ROMSEL: this one stays in main RAM. LOW_PAGES covers the whole
\ region rather than the block's own length, so the copy is three fixed
\ pages and the tail past low_end is stale staging bytes nobody reads.
.PageLowIn
  LDA #LO(LOW_STAGE) : STA swSrc     \ the page-&0D half first, by the byte
  LDA #HI(LOW_STAGE) : STA swSrc+1
  LDA #LO(LOW2_ADDR) : STA swDst
  LDA #HI(LOW2_ADDR) : STA swDst+1
  LDY #0
.pli_byte
  LDA (swSrc),Y
  STA (swDst),Y
  INY
  CPY #LOW2_BYTES
  BNE pli_byte

  LDA #LO(LOW_STAGE + LOW2_SKIP) : STA swSrc   \ then the &0E00 half, past
  LDA #HI(LOW_STAGE + LOW2_SKIP) : STA swSrc+1 \ the sixteen skipped bytes
  LDA #LO(LOW_ADDR)  : STA swDst
  LDA #HI(LOW_ADDR)  : STA swDst+1
  LDX #LOW_PAGES
  JMP PageCopyAt

\ ---- the DFS workspace snapshot -----------------------------
\ The low overlay buries TWO things the filing system cannot live
\ without: &0E00-&10FF is DFS's own workspace (under lowcode), and
\ lowcode2 at &0D60-&0DCB sits on the MOS's EXTENDED VECTOR TABLE at
\ &0D9F — which is how DFS 1.2 routes FILEV into its ROM. A
\ filing-system call made with the overlay down goes FILEV ->
\ extended-vector stub -> a vector made of our code bytes -> garbage;
\ measured in jsbeeb as a crash into zero page, and *DISC does not
\ recover it. So TitleSeq snapshots both spans into bank 6 (dfsSave,
\ 912 B) after its last *LOAD, and GoTitle puts them back before the
\ game-over loads: a byte-for-byte restore of a state the MOS and DFS
\ were actually in — extended vectors, ROM workspace bytes, catalogue
\ cache and all. &0D00-&0D5F (NMI) and &0DF0-&0DFF are NOT in the
\ snapshot: nothing of ours ever writes them. Bank 6 is paged around
\ the copy — safe here because neither routine runs from inside a bank.
DFSWS2_ADDR = &0D60             \ lowcode2's span, extended vectors under it
DFSWS2_LEN  = &0DF0 - &0D60     \ 144 bytes
DFSWS_ADDR  = &0E00
DFSWS_PAGES = 3                 \ &0E00-&10FF
.SaveDfsWs
  PAGEBANK SWRAM_SPR2
  LDY #0
.sdw_lo
  LDA DFSWS2_ADDR,Y
  STA dfsSave,Y
  INY
  CPY #DFSWS2_LEN
  BNE sdw_lo
  LDA #LO(DFSWS_ADDR) : STA swSrc
  LDA #HI(DFSWS_ADDR) : STA swSrc+1
  LDA #LO(dfsSave + DFSWS2_LEN) : STA swDst
  LDA #HI(dfsSave + DFSWS2_LEN) : STA swDst+1
  BNE dws_copy                  \ always: the HI is never zero

.RestoreDfsWs
  PAGEBANK SWRAM_SPR2
  LDY #0
.rdw_lo
  LDA dfsSave,Y
  STA DFSWS2_ADDR,Y
  INY
  CPY #DFSWS2_LEN
  BNE rdw_lo
  LDA #LO(dfsSave + DFSWS2_LEN) : STA swSrc
  LDA #HI(dfsSave + DFSWS2_LEN) : STA swSrc+1
  LDA #LO(DFSWS_ADDR) : STA swDst
  LDA #HI(DFSWS_ADDR) : STA swDst+1
.dws_copy
  LDX #DFSWS_PAGES
  JSR PageCopyAt
  PAGEBANK SWRAM_DATA
  RTS

\ ============================================================
\ Layer 9 lives in BANK 6 and cannot see bank 4 — the bridge
\ ============================================================
\ panel.asm and console.asm were pushed out of bank 4 by 224 bytes and
\ into bank 6, which is the only one with room now the font ships as its
\ own file. Bank 6 code cannot read drCent, drNum, drWeapon, drSpeed,
\ drCount or shipLevel, all of which are in bank 4.
\
\ So main RAM carries them across, in two pieces:
\   the four TABLES are constant and are copied once at boot, to PN_TABS;
\   the two SCALARS move, and are mirrored per pass by PanelTick below.
\
\ Everything else the panel and the console read is already main RAM —
\ the font, deck, moveMode, conActive, score, scrollS, line — so this is
\ the whole of the bridge. See docs/layer-9-hud.md, decision 8.

\ ---- the tables, once ---------------------------------------
\ Called at boot with SWRAM_DATA paged, which is where these live.
.PageTabsIn
  LDX #CON_TYPES-1
.pti_loop
  LDA drCent,X   : STA pnTabCent,X
  LDA drNum,X    : STA pnTabNum,X
  LDA drWeapon,X : STA pnTabWeapon,X
  LDA drSpeed,X  : STA pnTabSpeed,X
  DEX
  BPL pti_loop
  RTS

\ ---- the scalars, per call ----------------------------------
\ PAGES BANK 6 IN AND BANK 4 BACK OUT around the call, the same way
\ SprDrawAll does for the blitter. The mirror is filled BEFORE the page,
\ while bank 4 is still up, and read after it — which is the only order
\ that works.
\ THREE scalars. drEnergy went with the energy bar the HUD no longer
\ shows; drType came back for the console's "Unit type 001" line, which
\ ShowRobotType ($3149) indexes DCent_t and DNum_t with. drCount and
\ shipLevel are the console's deck and ship lines.
MACRO PNMIRROR
  LDA drType   : STA pmType
  LDA drCount  : STA pmCount
  LDA shipLevel: STA pmShip
ENDMACRO

.PanelTick
  PNMIRROR
  PAGEBANK SWRAM_SPR2
  JSR PanelUpdate
  PAGEBANK SWRAM_DATA
  RTS

.PanelSetup
  PNMIRROR
  PAGEBANK SWRAM_SPR2
  JSR PanelInit
  PAGEBANK SWRAM_DATA
  RTS

.ConsoleEnter
  PNMIRROR
  JSR ConMenuInit4              \ bank 4 — FIRST, and the resting bank, so
                                \ no paging. It ends in SetTextPal, and the
                                \ point of the order is that the palette is
                                \ in force BEFORE ConsoleOpen draws on it.
                                \ It only writes flags, so nothing here
                                \ depends on the draw having happened
  PAGEBANK SWRAM_SPR2
  JSR ConsoleOpen
  PAGEBANK SWRAM_DATA
  RTS                           \ no recolour tail: ConMenuInit4 above
                                \ set the ink table before the draw
                                \ had no room for any of this: 23 B free

\ The console's menu lives in BANK 4 (ConMenu4, droid.asm) — bank 6 is
\ full — and only the pieces that PAGE live here: ConDraw is bank 6,
\ LvShip7 and ConDeck7 bank 7, and no bank can pull another in under
\ itself. Both pages are their C64 selves: drawn once, static, fire
\ returns to the console main screen. The ship page swaps the palette
\ around itself; the deck plan keeps the deck's own, as con_DeckInfo
\ does. NEITHER touches the display any more: the whole console session
\ is sixteen rows from ConsoleOpen, so the plan's 16-row map needs no
\ switch of its own — see T1_I3X.
.ConsoleTick
  LDA conShipReq
  CMP #2
  BEQ ct_ship
  LDA conDeckReq
  CMP #2
  BEQ ct_deck
  LDA conDbReq
  BNE ct_db
  JSR ConMenu4                  \ bank 4: K/M selection, the marker, fire
  LDA conShipReq
  CMP #1
  BNE ct_trydeck
  JSR ConShipEnter4             \ bank 4: the side view's palette in
  PAGEBANK SWRAM_XFER
  JSR LvShip7                   \ bank 7: the cross-section, deck lit
  PAGEBANK SWRAM_DATA
  LDA #2
  STA conShipReq
  RTS
.ct_trydeck
  LDA conDeckReq
  CMP #1
  BNE ct_noship
  PAGEBANK SWRAM_XFER
  JSR ConDeck7                  \ bank 7: the plan, and the white marker
  PAGEBANK SWRAM_DATA
  LDA #2
  STA conDeckReq
  RTS                           \ the plan's palette is NOT set here any
                                \ more: ConMenu4 sets it on the press that
                                \ asks for the page, so ConDeck7 draws in
                                \ the colours it will be seen in
\ The database is NOT one of the static pages: it is a browser, so its
\ tick runs every pass and the page itself reads the keys — which it can,
\ because keydown is main RAM. There is no bank-4 shim and no enter
\ shim; DbTick's own conDbReq = 1 arm does the initialising, and 0 means
\ it has left, which lands on the pages' shared return tail.
.ct_db
  PAGEBANK SWRAM_XFER
  JSR DbTick                    \ bank 7: keys, state and draw together
  PAGEBANK SWRAM_DATA
  LDA conDbReq
  BEQ ct_back
  RTS
.ct_ship
  JSR ConPageKeys4              \ bank 4: the fire edge; clears the flag
  LDA conShipReq                \ on the press that leaves
  BNE ct_x
  JSR ConShipExit4              \ bank 4: the deck's palette back
  JMP ct_back
.ct_deck
  JSR ConPageKeys4
  LDA conDeckReq
  BNE ct_x
.ct_back
  PNMIRROR                      \ and the console main screen again
  JSR ConIconInk4               \ bank 4, and it is the RESTING bank
                                \ here: the icon colours BEFORE the
                                \ draw, so ConIcons plots them right
                                \ first time. Selection kept, as the
                                \ C64 keeps it
  PAGEBANK SWRAM_SPR2
  JSR ConDraw
  PAGEBANK SWRAM_DATA
  RTS
.ct_noship
  LDA conActive
  BNE ct_x
  JSR ReframeView
  JSR PanelSetup                \ the deck line and the shadows, as a load does
.ct_x
  RTS

.pmType   EQUB 0
.pmCount  EQUB 0
.pmShip   EQUB 0
.conActive EQUB 0               \ main RAM: the loop and the bridge both read it
.conDbReq  EQUB 0               \ 0 idle / 1 fire on entry 1 / 2 page up.
                                \ MAIN RAM because bank 4 sets it, bank 7
                                \ clears it and ConsoleTick reads it with
                                \ neither of them paged in

\ ============================================================
\ Layer 10 lives in BANK 7 and cannot see bank 4 — the shim
\ ============================================================
\ The game itself is xfer.asm, a transliteration of Capture ($229D) and
\ everything under it, in the fourth bank. What CANNOT be there is
\ anything that touches the droid tables, the score or bank 4's code —
\ XferEnter4 gathers the two droid types into the main-RAM mirrors
\ below, and XferExit4 applies FinishTransfer1/2's outcome; both live in
\ droid.asm, IN bank 4, because main RAM below &3000 is full. Only the
\ paging trampolines are here: code in bank 4 cannot page bank 7 in
\ under its own feet.

.xferDroid  EQUB 0              \ the droid index dc_player caught
.xferActive EQUB 0
.xfmPlyType EQUB 0              \ the player's droid type at entry
.xfmTgtType EQUB 0              \ and the target's
.xfmResult  EQUB 0              \ 1 = took the droid, 2 = lost
.xfmDone    EQUB 0              \ set by XfEndTick when the hold expires

.XferEnter
  JSR XferEnter4                \ bank 4: gather, flatten, palette, t1i3
  PAGEBANK SWRAM_XFER
  JSR XfStart
  PAGEBANK SWRAM_DATA
  RTS

\ ============================================================
\ GoStart7 / GoTick7 — the game-over shims
\ ============================================================
\ _gameover ($1455) lives in bank 7 with the transfer game and the lift
\ view; these are what CbCheckDeath, in main RAM, can reach. The pattern
\ is XferTick's below: page the bank in, run its tick, page the data
\ bank back, and act on what it left in main RAM.
\
\ THE RANDOMS ARE DRAWN FIRST, on this side of the swap. DrRandom is
\ bank 4's and its LFSR must stay one sequence — see GoTick's header.
\ ============================================================
\ TitleSeq — the title, and everything that rebuilds after it
\ ============================================================
\ Shared by boot and the game-over seam, because from here the two are
\ the same journey. The caller must have the CRTC in SetupMode's plain
\ single-cycle shape and the MOS's IRQ in place: the loads need VSync
\ and the filing system, TiWait's keydown needs OSBYTE, and a 25-row
\ picture wants the plain display.
\
\ PARTITL loads at TITLE_ADDR = &3000, over PARAFNT's ground — the two
\ are never wanted at once — and runs in place: it is main RAM, so no
\ paging. PARAFNT then reloads over it, and PARALOW is re-staged and
\ re-copied because every *LOAD here used &0E00-&10FF as DFS workspace.
\ PageLowIn stays the LAST filing-system call for exactly that reason.
\
\ Everything after the loads rebuilds what the title's framebuffer
\ (&4000-&7E7F) and the staging overlay sat on: the panel, the &5400
\ tables, CHAR_PTR and SPR_MASKTAB. SprInit is NOT here: it resets
\ state rather than building a table, so it belongs to GameStart —
\ which also rebuilds the tile map and the charset, so the deck's own
\ ground needs nothing from us.
.TitleSeq
  LDX #LO(loadtitl)
  LDY #HI(loadtitl)
  JSR OSCLI
  JSR TiBootPal                 \ KC 2026-08-24: at a COLD boot only, a
                                \ random deck text palette for the front
                                \ end to inherit, and the LFSR seed from
                                \ the same sample. It is PARTITL code, so
                                \ it must follow the load above; boot-only,
                                \ so it needs bootPal. See its header
  JSR HsEntry                   \ Layer 11f: the high-score entry, if the
                                \ game just ended on one. It draws on the
                                \ 999 page, which SetupPlain left on
                                \ screen, and it needs PARTITL loaded and
                                \ the title NOT yet painted over it
  JSR TiShow

\ Layer 11f: ts_loads is re-entered by the briefing's fire exit — the
\ teardown-and-rebuild after bank 5 is given back to the blitter runs
\ this same tail rather than carrying a copy. BrTimeout also RTSes to
\ here, because it is entered by JMP from TiWait with TiShow's return
\ address still on the stack. See briefing.asm.
.ts_loads
  LDX #LO(loadfnt)              \ the text font, straight back onto the
  LDY #HI(loadfnt)              \ ground the title borrowed
  JSR OSCLI

  LDX #LO(loadlow)              \ the low overlay, staged at LOW_STAGE;
  LDY #HI(loadlow)              \ its copy-down must be the last
  JSR OSCLI                     \ filing-system call — see PageLowIn

  JSR SaveDfsWs                 \ snapshot DFS's workspace (&0E00-&10FF)
                                \ into bank 7 while it is still DFS's:
                                \ PageLowIn is about to bury it, and
                                \ GoTitle needs it back for its loads
  JSR PageLowIn

  PAGEBANK SWRAM_DATA           \ the data bank is the resting state
  JSR PageTabsIn                \ and, with it up, the four droid tables the
                                \ panel needs and cannot reach from bank 6

  LDX #IS_BLANK                 \ Layer 11d: black the strip BEFORE the
  JSR InfoCall                  \ rupture starts showing it. &5800-&7FFF
                                \ still holds the title's framebuffer,
                                \ and with the 001 screen holding
                                \ LoadDeck's redraw back nothing else
                                \ writes there until the page prints

  JSR SetupRupture              \ NOW the CRTC goes into the rupture's
                                \ shape: it stops VSync, so it has to be
                                \ after the last filing-system call

  JSR FillPanel                 \ after the staging area is done with: it
                                \ reaches past &4800, over the panel

  JSR BuildMulTabs              \ &5400 is under the staging overlay AND
                                \ under the title's framebuffer, so it
                                \ cannot be written until both are done

  JSR BuildCharPtrs             \ needs the data bank in, and the staging
                                \ copy finished — it reaches past &5500
  JSR SprBuildMask              \ the title's framebuffer sat on the mask
                                \ table too
  JMP InstallIrq                \ take the IRQ back, and its RTS

\ ============================================================
\ GoTitle — a game is over; show the title, then start another
\ ============================================================
\ The other half of the boot seam: give the machine back to the MOS,
\ put the CRTC back in the plain shape TitleSeq requires, run the same
\ sequence boot does, and hand what comes back to GameStart. UninstallIrq
\ must come first — the rupture IRQ rewrites R6/R12/R13 every field, so
\ any display SetupMode set up would be overwritten within one.
.GoTitle
  LDA #0                        \ Layer 11e: UninstallIrq stops the sound
  STA sndState                  \ ticks, so whatever the chip holds would
  SEI                           \ drone through the whole title. Silence it
  JSR SndSilence                \ NOW — SWRAM_DATA is paged (GoTick7), and
                                \ masked so no tick interleaves the port A
                                \ save/restore. UninstallIrq CLIs at its end
  JSR UninstallIrq
  JSR SetupPlain                \ NOT SetupMode: its VDU 22 would clear
                                \ &3000-&7FFF and take the 999 page and
                                \ the font with it. Layer 11f
\ Put DFS's workspace back before the first load. The low overlay has
\ been sitting on &0E00-&10FF — DFS's own variables — since the last
\ PageLowIn, and a filing-system call against that garbage hangs in the
\ 8271 retry loop (measured; *DISC does not recover it either). TitleSeq
\ snapshotted the real thing into bank 7 just before PageLowIn trampled
\ it, so this is a byte-for-byte restore of a state DFS was actually in.
\ Boot does not need it: its loads all run before the first PageLowIn.
  JSR RestoreDfsWs
  JSR TitleSeq
  JMP BrDispatch                \ Layer 11f: the briefing if the title
                                \ timed out, GameStartInfo if it fired —
                                \ bank 4 either way, TitleSeq left
                                \ SWRAM_DATA paged

.GoStart7
  PAGEBANK SWRAM_XFER
  JSR GoStart
  PAGEBANK SWRAM_DATA
  RTS

.GoTick7
  JSR DrRandom : STA overRnd0
  JSR DrRandom : STA overRnd1
  PAGEBANK SWRAM_XFER
  JSR GoTick
  PAGEBANK SWRAM_DATA
  LDA overDone
  BEQ gt_x
  LDA #0
  STA overDone
  STA overPhase                 \ THE WASH'S OWN ARM IS ABOVE THE SCREEN'S
                                \ in the loop and returns the pass, so
                                \ leaving phase 2 set would repaint the
                                \ boil over the page every pass and IsTick
                                \ would never run. The C64 has no state to
                                \ clear here — $37D9's loop simply ends
  LDX #IS_SCR_OVER+1            \ $37DC: the wash has burnt out, and the
  JMP InfoCall                  \ 999 stands behind "Transmission /
                                \ Terminated". IS_ACT_TITLE then takes
                                \ the title, and GameStart clears
                                \ everything else after it
.gt_x
  RTS

.XferTick
  PAGEBANK SWRAM_XFER
  JSR XfTick
  PAGEBANK SWRAM_DATA
  LDA xfmDone
  BEQ xt_x
  JSR XferExit4                 \ bank 4: the outcome, and ReframeView
  JMP PanelSetup                \ the bank-6 trampoline — NOT callable
                                \ from inside bank 4, hence here
.xt_x
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
\ WaitField / WaitRest — the pass's fields, taken one at a time
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
\ If an iteration overruns its fields the flag is already set on
\ arrival, so it is consumed at once and the next boundary is one
\ field later. The rate degrades but never exceeds 25 Hz.
\ THE PASS TAKES ITS FIELDS ONE AT A TIME rather than consuming all of
\ them up front, because each field opens an off-display window and
\ every buffer write belongs inside one. The loop takes the first at
\ the top and WaitRest takes the remainder after the drawing, so the
\ second window is a point in the code the sprite pool can be split
\ across. See docs/raster-timing.md.
\ A = the window number to wait for. Returns at once if it has already
\ been and gone, which is the whole point: a pass that overruns its
\ window by a little should carry straight on into the next piece of
\ work rather than sit out a field it has already spent.
\ The subtract makes the comparison a SIGNED distance, so it is right
\ across the counter's 8-bit wrap for anything within 127 fields of
\ the target — which is 2.5 seconds, and nothing here waits that long.
.WaitUntilField
  STA wufTarget
.wuf_spin
  LDA fieldCount
  SEC
  SBC wufTarget
  BMI wuf_spin
  RTS

\ The pass's own two waits, in terms of the field it started on.
\ FRAME_LOCK stays the single dial: the pass is not allowed to be
\ shorter than that many fields, and is allowed to be longer.
ASSERT FRAME_LOCK >= 2
.WaitWindowB
  CLC
  LDA passF0
  ADC #1
  JMP WaitUntilField
.WaitNextPass
  CLC
  LDA passF0
  ADC #FRAME_LOCK
  JMP WaitUntilField

.wufTarget EQUB 0

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

\ ---- the sound tick: 50 Hz, bank 4, from inside the IRQ -----
\ Layer 11e [DECISION 1]. Safe on two measured facts: VSync to
\ fire 1 is 84 scanlines (~10,700 cycles), an order of magnitude
\ more than a worst-case tick; and ROMSHAD always names the bank
\ the interrupted code intends (PAGEBANK writes it first), so
\ save-shadow / page / restore-both is exact. T1 is continuous,
\ so the stage cadence is immune to however long this takes.
  LDA ROMSHAD
  PHA
  LDA #SWRAM_DATA
  STA ROMSHAD
  STA ROMSEL
  JSR SndTick
  PLA
  STA ROMSHAD
  STA ROMSEL

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
\ Save what the MOS had FIRST, before any of it is clobbered, so that
\ UninstallIrq can hand it all back for the game-over title. The T1
\ latches matter as much as the vector: the rupture reprograms them
\ every field, and the MOS's 100 Hz events — the keyboard scan OSBYTE
\ &81 reads, the clock, the disc timeouts — run off what it left there.
\ Reading &FE46/&FE47 reads the latches without touching the counter.
  LDA SYS_VIA_IER : AND #&7F : STA oldSysIer
  LDA USR_VIA_IER : AND #&7F : STA oldUsrIer
  LDA SYS_VIA_ACR : STA oldSysAcr
  LDA SYS_VIA_T1LL : STA oldSysT1L
  LDA SYS_VIA_T1LH : STA oldSysT1H

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
\ UninstallIrq — give the machine back to the MOS
\ ============================================================
\ The exact inverse, from the saves above: silence everything, put the
\ MOS's ACR and T1 latches back, restore IRQ1V, then re-enable what the
\ MOS had enabled. Writing the T1 LATCHES only — never T1C-H, which
\ would restart the counter mid-count — is enough: T1 is continuous and
\ reloads from the latch on its next underflow, so the MOS clock is at
\ most one rupture interval late.
\ Callable only after InstallIrq has run at least once; boot calls
\ InstallIrq first, so the saves are always populated.
.UninstallIrq
  SEI
  LDA #&7F : STA SYS_VIA_IER
  LDA #&7F : STA USR_VIA_IER
  LDA oldSysAcr : STA SYS_VIA_ACR
  LDA oldSysT1L : STA SYS_VIA_T1LL
  LDA oldSysT1H : STA SYS_VIA_T1LH
  LDA oldIrq1V   : STA IRQ1V
  LDA oldIrq1V+1 : STA IRQ1V+1
  LDA #&7F : STA SYS_VIA_IFR    \ nothing of ours may be left pending
  LDA oldSysIer : ORA #&80 : STA SYS_VIA_IER
  LDA oldUsrIer : ORA #&80 : STA USR_VIA_IER
  CLI
  RTS

\ ============================================================
\ ReframeView — put the strip back under the player, wherever he
\ has just been PUT rather than moved
\ ============================================================
\ ANY teleport must come through here. The incremental scroll keeps
\ scrollS in step with mapHX by adding the SAME delta to both; a
\ routine that assigns mapHX outright — SetMapFromPos, from a waypoint
\ spawn or a lift — breaks that link and nothing downstream repairs it.
\
\ Two things then go wrong, and only one of them is cosmetic:
\
\   - the buffer holds the deck at the OLD offset, so the view is
\     somewhere else entirely until something redraws it;
\   - the parity invariant `scrollS/8 == mapHX (mod 2)` is broken on
\     half of all teleports, and COPYCHAR in scroll.asm then writes its
\     second half 8 bytes past &8000 — into whatever sideways bank is
\     paged, which at level-draw time is SWRAM_DATA. The first bytes of
\     that bank are chardata, then colours, then tiledefs: exactly the
\     tile characters and the tile layout. It survives a deck change,
\     because BuildCharset and BuildLevel re-read the corrupted source.
\
\ That was BUGS.md #10 / docs/bug-map-corruption.md, and it is why the
\ tile map at &3800 always came back clean: nothing was ever writing
\ to it.
\
\ Start the strip at the buffer base — vertically, at least. `line` is
\ zeroed so buffer row 0 is not a split row, which RedrawAll needs
\ because it writes whole rows. Both callers place the player on a
\ whole character row, so SetMapFromPos has already made line 0 and
\ this only restates it.
\
\ HORIZONTALLY the strip starts one unit in when mapHX is odd, which is
\ what makes the wrap fall on a character boundary — see COPYCHAR for
\ the derivation, and for why the incremental scroll then preserves it.
\ ---- an information screen owns the buffer: do NOT redraw ---
\ LAYER 11d. StartGame calls NewShipInfo BEFORE the deck is on screen
\ ($12C7, and DoNewDeck comes after), and GameStartInfo does the same by
\ setting infoActive before GameStart — which makes LoadDeck's own
\ ReframeView a no-op, so the 001 screen is the first thing a game
\ shows. The deck is drawn when the screen is dismissed, by the
\ ReframeView in InfoCall's IS_ACT_GAME arm, with infoActive back to 0.
\ Without this the level appears, the page covers it, and the level
\ comes back — which is what KC saw.
.ReframeView
  LDA infoActive
  BEQ rv_go
  RTS
.rv_go
\ The deck is a FIFTEEN-row view and every screen that is not the deck is
\ a sixteen-row one, so this is where the bottom edge comes back up —
\ see T1_I3X. Every way back to the deck passes through here: the
\ console's close, the information screens' IS_ACT_GAME, the transfer's
\ exit, the lift's, and LoadDeck. The guard above is the reason it is
\ after the label and not before it: while an information screen is up
\ this returns early, and the screen must keep its sixteenth row.
  LDA #HI(T1_I3)                \ the high byte alone — see T1_I3X
  STA t1i3Hi

  LDA mapHX
  AND #1
  ASL A : ASL A : ASL A         \ 0 or 8
  STA scrollS
  LDA #0
  STA scrollS+1
  STA line
  STA iline
  STA bandDo                    \ the exposed edges belonged to the frame
  STA colCount                  \ we have just thrown away
  LDX #SPR_SLOTS-1              \ the saved backgrounds belong to the view
  LDA #0                        \ we are leaving; RedrawAll replaces them
.rv_unsave
  STA sprSaved,X
  DEX
  BPL rv_unsave
  JSR SetCRTCStart
  JMP RedrawAll                 \ and its RTS

INCLUDE "src/rupture.asm"
INCLUDE "src/bufcore.asm"       \ what screen/scroll could not leave behind
INCLUDE "src/player.asm"
INCLUDE "src/combat.asm"        \ main RAM: both banks' code reaches it
INCLUDE "src/door.asm"
INCLUDE "src/lift.asm"
INCLUDE "src/sprite.asm"

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
.sprSplit  EQUB 0               \ this pass is drawing the pool in two
.passF0    EQUB 0               \ the window this pass started in
.vsyncCount EQUB 0              \ bumped by IrqHandler once per field

\ ---- the sound driver's request interface -------------------
\ MAIN RAM on purpose: written by code in banks 6 and 7 (console,
\ transfer) as well as bank 4 and here, read by SndTick in bank 4.
\ sndFx1/sndFx2 MUST stay adjacent — SndTick indexes them by voice,
\ the same trick the C64 plays with $91/$92. Values are the C64's:
\ effect 1-31, bit 7 = uninterruptible; sndState 0 silent, $12 =
\ initialise game FX (drops to 2); sndVolume 0-15, 15 = full.
.sndFx1    EQUB 0
.sndFx2    EQUB 0
.sndState  EQUB 0
.sndVolume EQUB 15
.gameTick  EQUB 0               \ the C64's frameCount, once per ITERATION
.bootPal   EQUB 1               \ TiBootPal clears it: the random front-end
                                \ deck is picked ONCE, at a cold boot, and
                                \ every title after one inherits instead.
                                \ Main RAM because PARTITL is reloaded from
                                \ disc on every title and could not keep it
.conInkT   EQUB 0, 0, 0, 0     \ the console menu's four icon colours, one
                               \ per conSel: &F0 white for the selected,
                               \ &00 black for the rest. ConIconInk4 (bank
                               \ 4) fills it and ConIcons/ConDroid (bank 6)
                               \ read it -- MAIN RAM because conSel is bank
                               \ 4's and bank 6 cannot see it, which is the
                               \ same reason PN_TABS and pmShip exist
.oldIrq1V  EQUW 0
.oldSysIer EQUB 0               \ the MOS's VIA state, saved by InstallIrq
.oldUsrIer EQUB 0               \ and handed back by UninstallIrq for the
.oldSysAcr EQUB 0               \ game-over title's loads and keyreads
.oldSysT1L EQUB 0
.oldSysT1H EQUB 0

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
\
\ The deck plan does NOT draw from here, though its codes overlap the
\ tiles': its page is hires where this charset is built for the play
\ area's per-cell modes, so it converts its own 31 characters at plot
\ time in bank 7 — see condeck.asm and src/data/plandata.asm.
ORG &0400
.charset
  SKIP 137 * CHAR_BYTES         \ NUM_CHARS, defined in chardata.asm
.charset_end
ASSERT charset_end <= LOWBSS_ADDR
INCLUDE "src/lowbss.asm"        \ &0C90: the low overlay's state, uninitialised
ORG code_end

\ ---- tile map: 64 x 16, one byte per tile -------------------
\ MapChar depends on this being page aligned and exactly 1K.
\
\ PLACED, NOT FLOATED. It used to sit at the next page boundary after
\ code_end, which was fine while the code was small and silently walked
\ into the sprite save areas at &3000 when it was not — a corruption
\ with no assert to catch it. SPR_MASKTAB is at &5700 and the panel
\ starts at &4800, so &3800-&47FF is clear. That gives the code the whole
\ of &1100-&3000 instead of whatever was left.
\
\ THERE IS NO LONGER ANY GAP BELOW IT. The save areas were seven pages;
\ Layer 7c's eighth took the spare one, so they end at the very byte this
\ map begins on. The ASSERT below is exact rather than slack, and a
\ save-area overrun that used to land in dead space would now land on the
\ map — which is what DEBUG_MAPGUARD was written to catch.
\ LAYER 11 MOVED ALL THREE. PARAFNT went to &3000 so the title screen
\ could have 16,000 contiguous bytes from &4000; the save areas followed
\ it to &3E00 and this map to &4600, still ending exactly on PANEL_ADDR.
\ Nothing depended on the old addresses: the blitter builds its save
\ pointer at runtime from HI(SPR_SAVE) and stores through (svp),Y, and
\ mapRowLo/Hi are assembled from `tilemap + r * MAP_COLS`.
\
\ It is above DATA_LOAD, so the PARADAT staging copy runs straight over
\ it — harmless, because PageDataIn is done long before LoadDeck calls
\ BuildLevel to fill it in, the same argument the panel and the mask
\ table rely on.
ORG &4600
.tilemap
  SKIP MAP_COLS * MAP_ROWS
.tilemap_end
ASSERT tilemap >= SPR_SAVE + SPR_SLOTS * 256
ASSERT tilemap_end <= PANEL_ADDR
ASSERT code_end <= FONT_ADDR    \ the real bound: PARAFNT loads at &3000.
                                \ It used to read SPR_SAVE, which was
                                \ right when the font lived at &3C00 and
                                \ has been 3,584 bytes too slack since

\ ============================================================
\ Generated data — in sideways RAM bank 0
\ ============================================================
\ Assembled at &8000 so every label resolves to its address in the
\ bank. The SAVE's catalogue load address of DATA_LOAD is a relic the
\ shipping disc never sees: tools/make_disc.py replaces this file (and
\ the other three banks) with its ZX0 stream, loading at DEPK_STREAM
\ for UnpackBankIn to decompress straight into the bank. &3000 up is a
\ safe staging area either way: the OS thinks the screen is
\ &3000-&7FFF, but the CRTC has been repointed at a 10K window
\ starting &5800, so only &5800-&7FFF is ever fetched for display —
\ and the staged stream is dead by the time anything is drawn.
\
\ Layer 5 spends the &3000-&4707 this frees on droid state and the
\ per-slot background save buffers.
DATA_LOAD = &3000
ORG SWRAM_BASE
.data_start
INCLUDE "src/data/chardata.asm"
INCLUDE "src/consolesel.asm"    \ BEFORE colours.asm, so colourMap's
                                \ ALIGN &100 padding absorbs it and
                                \ the bank does not grow. Read its
                                \ header before moving it
INCLUDE "src/dbgkill.asm"       \ DEBUG_KILL only, and in the same
                                \ padding for the same reason. It must
                                \ be in BANK 4: DroidsUpdate calls it
INCLUDE "src/data/colours.asm"
INCLUDE "src/data/tiledefs.asm"
INCLUDE "src/data/levels.asm"
INCLUDE "src/data/droidgame.asm"
INCLUDE "src/data/sounddata.asm"

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
\ The IRQ touches rupture.asm and the CRTC registers — and, since
\ Layer 11e, THIS BANK: IrqHandler's VSync branch pages SWRAM_DATA
\ in around SndTick and restores the interrupted bank from ROMSHAD.
\ That is the one sanctioned breach of "the IRQ reads neither bank",
\ and it is why sound.asm and its data must stay in THIS bank.
INCLUDE "src/screen.asm"
INCLUDE "src/scroll.asm"
INCLUDE "src/level.asm"
INCLUDE "src/zx0depack.asm"    \ Layer 13d: BuildLevel's decompressor
INCLUDE "src/droid.asm"
.snd_code_start
INCLUDE "src/sound.asm"        \ Layer 11e: the SN76489 driver — IRQ-called
.data_end
\ Layer 11e filled this bank to the brim (docs/layer-11e-sound.md §6);
\ the line below is the fuel gauge, printed every build.
PRINT "bank4 ends", ~data_end, "- free", &C000-data_end, "B (sound", data_end-snd_code_start, "B)"

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

\ Layer 7's effect artwork rides in THIS bank rather than bank 4, and
\ only in this one. An effect sprite is drawn entirely by the
\ interpreted path, so its rows are read on every row of every frame
\ instead of one in fifty like drSprData — paging a different bank in
\ per row would cost more than the blit. An effect never uses a
\ compiled shift, so it does not care which sprite bank is up and can
\ live in the one the slot has already selected. Bank 4 is also the
\ scarcer of the two now that the level draw and the droid AI are in it.
INCLUDE "src/data/effects.asm"
ASSERT EF_SPRITE_ROWS == SPR_H
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

\ ---- Layer 9's panel and console ride here -----------------
\ NOT IN BANK 4, where they started. The console pushed that bank 224
\ bytes past &C000 and there is nothing left in it to move: chardata is
\ read by BuildCharset, which also reads deckScheme, colourMap, schemes
\ and charSlot, so the two cannot be separated. Bank 6 is where the room
\ is once the font ships as its own disc file.
\ THE PRICE IS THAT THEY CANNOT SEE BANK 4. Everything they read is
\ therefore in main RAM: the font at FONT_ADDR, the four droid tables
\ mirrored to PN_TABS by PageTabsIn, and four live scalars mirrored per
\ pass by PanelTick. See docs/layer-9-hud.md, decision 8.
INCLUDE "src/panel.asm"
INCLUDE "src/console.asm"
INCLUDE "src/dbgpanel.asm"     \ the debug readouts, beside the panel they draw on

\ ---- and the tranche decision ------------------------------
\ Nothing to do with the panel: it is here because bank 6 has the room
\ and because every byte it reads is main RAM or zero page, so it can
\ answer the question without bank 4. sprite.asm holds the bridge.
INCLUDE "src/sprsplit.asm"

\ The string table is NOT here any more: it is main RAM's, in PARAFNT,
\ because the droid database in bank 7 needed the same 1,542 bytes and
\ could not see this copy. See CON_STR_ADDR at the top of this file.
INCLUDE "src/data/conicons.asm"
INCLUDE "src/data/droidicon.asm"
\ The DFS workspace snapshot — the two spans the low overlay buries and
\ the filing system cannot live without: &0D60-&0DEF (the extended
\ vector table DFS 1.2 routes FILEV through, under lowcode2) and
\ &0E00-&10FF (DFS's own workspace, under lowcode). Captured by
\ SaveDfsWs after TitleSeq's last *LOAD, put back by RestoreDfsWs for
\ the game-over loads. In THIS bank because it is pure data touched
\ only by those two main-RAM helpers, which page the bank around the
\ copy — and bank 6 was the free space nothing else could use. Written
\ before it is read; it ships as zeroes and bank space is what it costs.
.dfsSave
  SKIP DFSWS2_LEN + DFSWS_PAGES * &100
.spr2_end
SAVE "PARSPR2", spr2_start, spr2_end, DATA_LOAD, DATA_LOAD

\ ---- the fourth bank: Layer 10, the transfer minigame -------
\ The minigame does not fit in what bank 4 or bank 6 has left, and it
\ never runs at the same time as the deck, the sprites or the panel's
\ per-pass tick — so it takes a bank of its own, loaded at boot like
\ the others rather than fetched from disc at each transfer. Bank 7
\ keeps the Master's 4-7 sideways RAM numbering intact.
CLEAR SWRAM_BASE, SWRAM_BASE + &4000
ORG SWRAM_BASE
.xfer_start
INCLUDE "src/xfer.asm"
INCLUDE "src/data/xferboard.asm"
\ Layer 8b's lift screen shares the bank AND the machinery — the shadow
\ screens, the glyph page, the row tables and the panel-line text are
\ all xfer.asm's, safe because the two can never be up at once.
INCLUDE "src/liftview.asm"
INCLUDE "src/condeck.asm"
\ The droid database. It needs the console's droid icon a second time —
\ that one still lives in bank 6 and only one bank is visible at a time —
\ but NOT the string table any more: that is main RAM's now, one copy,
\ read by both. See CON_STR_ADDR at the top of this file.
INCLUDE "src/condb.asm"
\ The title screen is NOT here any more: it is the PARTITL disc overlay,
\ assembled at TITLE_ADDR after the PARAFNT block below. Layer 13d took
\ it out to fund the droid portrait pool — which is this:
INCLUDE "src/data/portraits.asm"
INCLUDE "src/portrait.asm"

\ Layer 11d, AFTER condb.asm and portrait.asm: it is built out of their
\ printer, their geometry constants and PoDraw, and beebasm resolves
\ constants in file order.
INCLUDE "src/infoscr.asm"
INCLUDE "src/hstable.asm"       \ Layer 11f: 25 B that outlive a title
\ droidicon7.asm is gone with the rotor-and-digits stand-in: the
\ database draws the C64's own portrait now.
INCLUDE "src/data/droidinfo.asm"
INCLUDE "src/data/plandata.asm"
\ Layer 11f, placed HERE and not beside infoscr.asm: plandata carries an
\ ALIGN &100 for planInk, and whatever sits before it pays the padding.
\ Behind it, this block costs the bank its own size and nothing more.
INCLUDE "src/data/sideview.asm"
.xfer_end
SAVE "PARXFER", xfer_start, xfer_end, DATA_LOAD, DATA_LOAD

\ ---- the text font: its own file, straight to &3C00 ---------
\ It has no bank to belong to. Bank 4 is full, bank 6 now holds the panel
\ and the console, and the font is read by main-RAM addresses anyway — so
\ it is a fourth disc file with a catalogue load address of FONT_ADDR and
\ *LOAD puts it exactly where it runs. That is cheaper than shipping it
\ in a bank and copying it down, and it is why PageFontIn is gone.
\ LOADED LAST, after all three banks. The staging area for PARADAT runs
\ from &3000 through past &7000, straight over &3C00.
\ The twelve border cells are in the same file, straight after the glyphs:
\ they are read by the same code, from the same main RAM, and a separate
\ 192-byte disc file would buy nothing.
CLEAR FONT_ADDR, FONT_ADDR + FONT_BYTES + PN_FRAME_BYTES + CON_STR_BYTES + FONTCODE_BYTES
ORG FONT_ADDR
.font_start
INCLUDE "src/data/textfont.asm"
\ AND THE STRING TABLE, which is neither font nor frame but belongs in
\ the same file for the same reason they do: it is read by main-RAM
\ addresses from two different banks, so it has no bank to belong to.
INCLUDE "src/data/strings.asm"

\ AND THE DECODER, for the same reason again — it is called from both
\ banks, so it must be main RAM, but it need not be the code image.
.fontcode_start
\ ============================================================
\ FontCell — one packed font cell, expanded into the buffer
\ ============================================================
\ THE FONT SHIPS 1BPP, AND THAT IS THE C64'S OWN FORMAT. The artwork is
\ two colour — logical 0 and logical 3 — and a MODE 1 byte holding only
\ those comes out as n<<4 | n, four pixels in eight bits. Pair a cell's
\ byte i with its byte i+8, the same scanline's left and right halves,
\ and you get back (left<<4) | right: the C64's own 8-pixels-per-byte
\ scanline. So the port stopped shipping a converted copy of artwork it
\ can ship verbatim, and 3,488 bytes of PARAFNT became 1,744.
\
\ IT IS IN MAIN RAM BECAUSE FOUR CALLERS IN TWO BANKS NEED IT: PnGlyph
\ and PnCell in bank 6, XfGlyphAt and DbGlyph in bank 7. Only one bank
\ is visible at a time and bank code may call main RAM freely, so one
\ copy replaces what would have been the same loop four times.
\
\ AND IT IS IN THE PARAFNT FILE, NOT THE CODE IMAGE. It only has to be
\ main RAM, not `&1100`-`&3000` — which is the one region in the machine
\ that is genuinely full, and which Layer 11e's sound driver has to live
\ in because the IRQ reads no sideways bank. So it sits with the font it
\ decodes, in the room the 1bpp packing freed, and gives the code image
\ its 82 bytes back. Nothing calls it before PARAFNT loads: FillPanel
\ does not touch the font and the title carries its own glyphs.
\
\ swSrc -> the 8 packed bytes, swDst -> the 16-byte destination cell,
\ fontMask ANDed into every byte on the way out — that is the ink, and
\ every caller must set it, XfGlyphAt included with &FF for a plain copy.
\ swDst is left exactly where it was found, so the callers' own row
\ arithmetic is unchanged.
\
\ Two passes rather than one because the second half writes 8 bytes on
\ from the same source bytes, and with only Y available for indirect
\ indexing there is nowhere to keep a second destination — zero page is
\ full. It costs an add and a subtract per cell.
.FontCell
  LDY #7                        \ high nibbles -> the left half, bytes 0-7
.fc_left
  LDA (swSrc),Y
  LSR A : LSR A : LSR A : LSR A
  TAX
  LDA fontExpand,X
  AND fontMask
  STA (swDst),Y
  DEY
  BPL fc_left

  CLC                           \ the right half is eight bytes on
  LDA swDst   : ADC #8 : STA swDst
  LDA swDst+1 : ADC #0 : STA swDst+1

  LDY #7                        \ low nibbles -> the right half, bytes 8-15
.fc_right
  LDA (swSrc),Y
  AND #&0F
  TAX
  LDA fontExpand,X
  AND fontMask
  STA (swDst),Y
  DEY
  BPL fc_right

  SEC                           \ and hand swDst back as it was given
  LDA swDst   : SBC #8 : STA swDst
  LDA swDst+1 : SBC #0 : STA swDst+1
  RTS

.fontMask  EQUB &FF             \ the ink; set by every caller before the JSR
.fontExpand                     \ 4 pixel bits -> the MODE 1 byte for them
  FOR n, 0, 15
    EQUB (n << 4) OR n
  NEXT
\ ---- and DoScore, for the same reason -----------------------
\ It has to be main RAM — bank 4's DrKillDroid banks points through
\ AddScore and the main loop drains them here — but it does not have to
\ be `&1100`-`&3000`, and that is the region the disruptor emptied.
\ ============================================================
\ DoScore — port of DoScore ($0A7D), the arithmetic half
\ ============================================================
\ THE ACCUMULATORS ARE PENDING POINTS, AND THIS IS WHAT SPENDS THEM.
\ AddScore and SubScore only bank into scoreAdd and scoreSub; the score
\ itself moves ONE POINT A PASS, here, and GameLoop calls this every
\ iteration at $13E3. Without it the BCD score only moves on AddScore's
\ overflow path — once per 256 points banked — so shooting a droid worth
\ 20 changed nothing on screen and thirteen kills changed it by 255. That
\ is the bug KC reported; the routine had simply never been ported.
\
\ It also makes the score CLIMB rather than jump, which is the original's
\ feel: a kill ticks the display up over the following passes.
\
\ A CREDIT AND A DEBIT CANCEL WITHOUT TOUCHING THE SCORE. $0A83 takes one
\ off each and starts again, so a pass that owes 3 and is owed 3 does
\ nothing and costs three loops. That is why this is a loop and not a
\ pair of ifs.
\
\ Only the arithmetic is here. The C64 falls through into its own digit
\ draw at $0AD9; ours is PanelUpdate's, which repaints when score+3 moves
\ — see panel.asm.
.DoScore
.ds_again
  LDA scoreAdd
  BEQ ds_sub
  DEC scoreAdd
  LDA scoreSub
  BEQ ds_add
  DEC scoreSub                  \ they cancel: look for the next one
  JMP ds_again

.ds_add
  SED
  CLC
  LDA score+3 : ADC #1 : STA score+3
  LDX #2
.ds_addhi
  LDA score,X : ADC #0 : STA score,X
  DEX
  BPL ds_addhi
  BCC ds_x
  LDA #&99                      \ saturate rather than wrap
  STA score+0
  STA score+1
  STA score+2
  STA score+3
  BNE ds_x                      \ always: A is &99

.ds_sub
  LDA scoreSub
  BEQ ds_none
  DEC scoreSub
  SED
  SEC
  LDA score+3 : SBC #1 : STA score+3
  LDX #2
.ds_subhi
  LDA score,X : SBC #0 : STA score,X
  DEX
  BPL ds_subhi
  BCS ds_x
  LDA #0                        \ floor at zero, and drop the rest of the
  STA score+0                   \ debt with it, as $0AD3 does
  STA score+1
  STA score+2
  STA score+3
  STA scoreSub
.ds_x
  CLD
.ds_none
  RTS

.fontcode_end
.font_end
ASSERT textfont_end - font_start == FONT_BYTES
ASSERT panelframe == PN_FRAME_ADDR
ASSERT constrings == CON_STR_ADDR
ASSERT fontcode_start == FONTCODE_ADDR
ASSERT fontcode_end - fontcode_start == FONTCODE_BYTES
ASSERT font_end - font_start == FONT_BYTES + PN_FRAME_BYTES + CON_STR_BYTES + FONTCODE_BYTES
SAVE "PARAFNT", font_start, font_end, FONT_ADDR, FONT_ADDR

\ ============================================================
\ The title screen — the PARTITL disc overlay
\ ============================================================
\ [DECISION 6] of docs/layer-11-sound-title.md, restored: the title is
\ a disc file loaded when it is wanted, not a resident of bank 7 —
\ bank 7's free space is spoken for by the droid portrait pool. It
\ assembles over PARAFNT's ground at TITLE_ADDR: the two are never
\ wanted at once, and TitleSeq reloads PARAFNT the moment the title is
\ done. It must end below its own framebuffer at TI_BASE = &4000.
\ Its data comes before its code so the ASSERTs in title.asm can see
\ TITLE_COLS and TITLE_ROWS.
CLEAR TITLE_ADDR, &4000
ORG TITLE_ADDR
.titl_start
INCLUDE "src/data/title.asm"
INCLUDE "src/title.asm"
\ Layer 11f: DoHighScore runs from here, before the title paints.
\ Its alphabet comes with it because this block is assembled over
\ the text font's ground -- see highscore.asm's header.
INCLUDE "src/data/hsfont.asm"
INCLUDE "src/highscore.asm"
.titl_end
ASSERT titl_end <= TI_BASE
\ AND below FontCell, which highscore.asm calls rather than carrying a
\ copy of: PARAFNT is still resident when this overlay runs, and only
\ the part of it below titl_end has been overwritten.
ASSERT titl_end <= FONTCODE_ADDR
SAVE "PARTITL", titl_start, titl_end, TITLE_ADDR, TITLE_ADDR

\ ============================================================
\ The boot depacker — the PARDEPK disc file
\ ============================================================
\ The eighth disc file: the ZX0 decompressor macro from zx0depack.asm
\ again (bank 4 has the other copy, for BuildLevel), behind a stub that
\ aims it at DEPK_STREAM -> SWRAM_BASE. Loaded once at boot, before the
\ four compressed bank files; UnpackBankIn pages the target bank in and
\ JMPs here with the stream already loaded. It shares PARAFNT and
\ PARTITL's ground and must fit below DEPK_STREAM, where the streams
\ land. The ZP it borrows (the level draw's scratch, via zx0depack.asm's
\ aliases) is idle at boot.
CLEAR DEPK_ADDR, DEPK_STREAM
ORG DEPK_ADDR
.depk_start
  LDA #LO(DEPK_STREAM) : STA src
  LDA #HI(DEPK_STREAM) : STA src+1
  LDA #LO(SWRAM_BASE)  : STA mapptr
  LDA #HI(SWRAM_BASE)  : STA mapptr+1
  ZX0_DEPACKER
.depk_end
ASSERT depk_end <= DEPK_STREAM
SAVE "PARDEPK", depk_start, depk_end, DEPK_ADDR, DEPK_ADDR

\ ============================================================
\ The briefing text — the PARMAN disc file, bank 5's overlay
\ ============================================================
\ LAYER 11f [DECISION 4]: bank 5 is evicted for the briefing — no
\ sprite runs on a modal screen — and holds the intro manual's record
\ lists instead, ~4.6 K in 16 K. The file ships RAW for now and *LOADs
\ at DEPK_STREAM (over the dead title overlay, on the timed-out path
\ only); BrTimeout copies it up into the bank. Compressing it like the
\ four boot banks is the later optimisation, not the working form —
\ KC, 2026-08-22. Both briefing exits reload PARASPR; see briefing.asm.
\
\ The data is generated by tools/make_briefing.py from the hand-editable
\ src/data/briefing.txt — edit THAT, not the .asm. build.ps1 runs the
\ converter every build.
CLEAR SWRAM_BASE, SWRAM_BASE + &4000
ORG SWRAM_BASE
.man_start
INCLUDE "src/data/briefing.asm"
\ The briefing's bank-half: the score-patch writer, the portrait
\ snapshot and the band copy, which run with this bank paged and keep
\ PARBRF under its &0800 ceiling. See briefman.asm's header.
INCLUDE "src/data/sndchat.asm" \ the chatter's three records: 33 B, and
                               \ bank 4 had 15 — see BmChatter's header
INCLUDE "src/briefman.asm"
.man_end
SAVE "PARMAN", man_start, man_end, DEPK_STREAM, DEPK_STREAM
PARMAN_PAGES = (man_end - man_start + &FF) DIV &100
\ The raw stream must clear the panel at &4A00: everything below it —
\ the dead title overlay and the idle sprite save areas — is rebuilt
\ after the briefing, the panel is not.
ASSERT DEPK_STREAM + (man_end - man_start) <= PANEL_ADDR

\ ============================================================
\ The briefing driver — the PARBRF disc file, at &0400
\ ============================================================
\ Loaded where it runs: &0400-&0C90 is the MODE 1 charset, built at
\ deck load and dead outside a game — 2,192 bytes of free lower RAM at
\ title and briefing time. TiShow *LOADs this on every title, so
\ BrDispatch and BrTimeout are always valid where they are reached.
\ See briefing.asm's header, and §4c of docs/layer-11f-frontend.md.
\ THE CEILING IS &0800 AND IT IS MEASURED, NOT CAUTION. &0800-&08FF is
\ the MOS's sound workspace, channel buffers and printer buffer (NAUG
\ §6.6), and the MOS IRQ WRITES into it while it still owns the
\ machine — which it does through every load TiShow and BrTimeout make.
\ A PARBRF that reached &08B8 verified byte-perfect immediately after
\ its load and was chewed by the time the briefing painted: the CPU
\ ran the corrupted &08xx code into the paged bank and BRKed at &800E.
\ &0400-&07FF really is free — it is the language workspace and no
\ language is resident — but the page above belongs to a live MOS.
\ Overflow goes to briefman.asm in bank 5 instead.
BRF_ADDR = &0400
BRF_END  = &0800
CLEAR BRF_ADDR, BRF_END
ORG BRF_ADDR
GUARD BRF_END
.brf_start
INCLUDE "src/briefing.asm"
.brf_end
SAVE "PARBRF", brf_start, brf_end, BRF_ADDR, BRF_ADDR

\ ============================================================
\ The low-RAM overlay — resident code at &0E00
\ ============================================================
\ Assembled where it runs, but SAVEd with a catalogue load address of
\ DATA_LOAD so that *LOAD stages it and PageLowIn copies it down: DFS is
\ using &0E00-&10FF as its own workspace for the duration of the load
\ that delivers it, so it cannot be loaded in place. See LOW_ADDR.
\ It is main RAM, so bank 4 may call it and so may the code image, and
\ neither needs anything paged. That is the whole point of it.
ORG LOW2_ADDR
.low2_start
INCLUDE "src/lowcode2.asm"
.low2_end
ASSERT low2_end <= LOW2_LIMIT

\ The sixteen bytes PageLowIn does not copy. They are in the file so
\ that the two halves are one contiguous image and the second copy's
\ source is a constant; nothing ever reads them.
ORG LOW2_LIMIT
  SKIP &0E00 - LOW2_LIMIT

ORG LOW_ADDR
.low_start
INCLUDE "src/lowcode.asm"
.low_end
ASSERT low_end <= LOW_LIMIT
ASSERT low_end - low_start <= LOW_PAGES * 256
SAVE "PARALOW", low2_start, low_end, LOW_STAGE, LOW_STAGE

ASSERT CON_TYPES == DR_TYPES    \ console.asm is in bank 4 and cannot see
                                \ the sprite bank's count when it needs it
ASSERT DR_W == SPR_W            \ sprite.asm declares these ahead of the
ASSERT DR_H == SPR_H            \ generated data; keep the two in step
ASSERT DR_SEQSHIFT == SPR_SEQSHIFT
ASSERT DR_GLYPHS == SPR_DIG_GLYPHS
ASSERT DR_COLPAT_N == SPR_COLPATS

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
XFER_PAGES = (xfer_end - xfer_start + 255) DIV 256
ASSERT data_end <= SWRAM_BASE + &4000
ASSERT spr_end  <= SWRAM_BASE + &4000
ASSERT spr2_end <= SWRAM_BASE + &4000
ASSERT xfer_end <= SWRAM_BASE + &4000

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
ASSERT XFER_PAGES * 256 <= &4000
ASSERT DATA_LOAD + XFER_PAGES * 256 <= &8000

ASSERT charset_end - charset == NUM_CHARS * CHAR_BYTES
\ SetTextPal picks the text-screen palette by adding 64 to palBase, so the
\ two tables must be adjacent and in this order. export_bbc.py emits them
\ that way; this is what catches it if that ever changes.
ASSERT deckTextPal == deckPalette + 64

PRINT "code    ", ~start, "-", ~code_end
PRINT "tilemap ", ~tilemap, "-", ~tilemap_end
PRINT "charset ", ~charset, "-", ~charset_end
PRINT "data    ", ~data_start, "-", ~data_end, " (SWRAM bank", SWRAM_DATA, ",", DATA_PAGES, "pages )"
PRINT "sprite  ", ~spr_start, "-", ~spr_end, " (SWRAM bank", SWRAM_SPR, ",", SPR_PAGES, "pages )"
PRINT "sprite2 ", ~spr2_start, "-", ~spr2_end, " (SWRAM bank", SWRAM_SPR2, ",", SPR2_PAGES, "pages )"
PRINT "xfer    ", ~xfer_start, "-", ~xfer_end, " (SWRAM bank", SWRAM_XFER, ",", XFER_PAGES, "pages )"

SAVE "PARA",    start,      code_end, start
\ PARADAT and PARASPR are saved where they are assembled, above.

\ ------------------------------------------------------------------
\ !BOOT — EXECed at boot (disc option 3, set by build.ps1's -opt 3),
\ so each line is typed at the BASIC prompt. It prints the
\ assembly-time build stamp so any disc image can be dated, then
\ *RUNs the game — the same mechanism beebasm's -boot used before.
\ Assembled at a scratch address; only the saved bytes matter, and
\ nothing ever loads here.
\
\ IT ALSO NAMES THE DEBUG FLAGS THAT ARE ON, because a debug build looks
\ like a normal one until the thing you are testing behaves oddly. The
\ names are emitted by consecutive EQUS directives inside IFs, which
\ concatenate into one line — so a clean build says nothing at all and
\ a debug build says exactly what is different about it. Add a flag
\ above and add it here; DEBUG_ANY is what keeps the line off an
\ ordinary build.
\ ------------------------------------------------------------------
DEBUG_ANY1 = DEBUG_RASTER OR DEBUG_DRAW OR DEBUG_POS OR DEBUG_VSYNC
DEBUG_ANY2 = DEBUG_TIME OR DEBUG_ENERGY OR DEBUG_MAPGUARD OR DEBUG_XFERWIN
DEBUG_ANY3 = DEBUG_INVULN OR DEBUG_DECK OR DEBUG_KILL
DEBUG_ANY  = DEBUG_ANY1 OR DEBUG_ANY2 OR DEBUG_ANY3

CLEAR &7E00, &7F00
ORG &7E00
.boot_start
EQUS "*BASIC", 13
EQUS "CLS", 13
EQUS "REM PARADROID", 13
EQUS "REM BUILD ", TIME$("%d %b %Y %H:%M:%S"), 13
IF DEBUG_ANY
EQUS "REM DEBUG:"
IF DEBUG_RASTER
EQUS " RASTER"
ENDIF
IF DEBUG_DRAW
EQUS " DRAW"
ENDIF
IF DEBUG_POS
EQUS " POS"
ENDIF
IF DEBUG_VSYNC
EQUS " VSYNC"
ENDIF
IF DEBUG_TIME
EQUS " TIME"
ENDIF
IF DEBUG_ENERGY
EQUS " ENERGY"
ENDIF
IF DEBUG_MAPGUARD
EQUS " MAPGUARD"
ENDIF
IF DEBUG_XFERWIN
EQUS " XFERWIN"
ENDIF
IF DEBUG_INVULN
EQUS " INVULN"
ENDIF
IF DEBUG_DECK
EQUS " DECK"
ENDIF
IF DEBUG_KILL
EQUS " KILL"
ENDIF
EQUB 13
ENDIF
EQUS "*RUN PARA", 13
.boot_end
SAVE "!BOOT", boot_start, boot_end
