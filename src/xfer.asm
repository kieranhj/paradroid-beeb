\ ============================================================
\ xfer.asm — Layer 10: the transfer minigame, in SWRAM bank 7
\ ============================================================
\ A transliteration of the C64's subgame — Capture ($229D),
\ SubGameSelectSide ($E016), doSubGame ($2166), xfer_DoColumn ($1EB6) and
\ every routine around them — onto a machine with no character screen and
\ no colour RAM. The trick that keeps the code verbatim is a SHADOW of
\ both: XS_SCR is the C64's character screen (the board's 16 rows of 40),
\ XS_CRAM its colour RAM, at the fixed offset XS_COFF the way $D800 sat
\ $9000 above $4800. The game logic reads and writes the shadows with the
\ original's own pointer arithmetic, and a small set of write helpers
\ repaint the one MODE 1 cell a shadow write changed. Reads never repaint,
\ and writes that do not change the byte do not either — which is what
\ makes the steady state cheap.
\
\ OWNERSHIP IS A CHARACTER SET, NOT COLOUR RAM (route A, agreed with KC):
\ three copies of the 17 board characters — neutral, player, CPU — drawn
\ in logical 3, 1 and 2. A cell's colour token picks the set; the tokens
\ themselves stay the C64's own bytes ($FF, $FC, $F8, $F2...) so every
\ CMP in the game logic is the original instruction.
\
\ THE BOARD IS ALL 16 PLAY ROWS. The C64 board is rows 9-24 of its
\ screen — 16 rows — and the play area displays 16 rows whenever the
\ scroll is flat, the 16th normally hidden only by the R8 blank at fire 3
\ (agreed with KC: use all 16). main.asm's t1i3 variable moves that blank
\ down one row while the game runs. C64 row r lives at shadow row r-9.
\
\ WHAT IS NOT HERE: the shim. Entry, exit, the palette swap, the outcome
\ applied to the droid tables (bank 4 is invisible from this bank) and
\ the score all live in main RAM — see XferEnter/XferTickMain in
\ main.asm. This bank reads only main RAM (font, PN_TABS mirrors, keys)
\ and reports the result through xfmResult.
\
\ NOT PORTED, deliberately (see docs/layer-10-transfer.md when updated):
\ ShowXferInfo's two robot-info screens before the game, the droid
\ sprites sliding during side select (the panel line carries the two
\ numbers instead), AnimateIntoFont's charset animation, and the sounds.

\ ---- zero page, borrowed -----------------------------------
\ The C64 uses five pointer pairs and zero page here is full. The
\ transfer runs with the deck, the level draw and the sprites all
\ suspended, so their pointers are free: every one of these is re-derived
\ by its owner before its next use, and ReframeView on exit redraws
\ everything they fed. The IRQ touches none of them.
xdest  = bufp                   \ C64 `dest`   — shadow screen pointer
xdest2 = chp                    \ C64 `dest2`  — shadow colour pointer
xsrc   = src                    \ C64 `src`    — pulser-count stage pointer
xptr14 = tdp                    \ C64 `ptr_14` — the NEXT stage's counts
xptr12 = mapptr                 \ C64 `ptr_12` — saved dest across a gate
xgs    = psrc                   \ the renderer's glyph source
xgd    = svp                    \ and its buffer destination

XS_COFF = &0300                 \ shadow colour sits 3 pages above shadow
                                \ screen, as $D800 sat $9000 above $4800

\ The result window: colour RAM $D9A3 = row 10 col 19 on the C64, which
\ is shadow row 1 col 19 — the 2x2 of blocks in the top frame that shows
\ who is winning.
XS_RESULT_OFS = 1 * 40 + 19

ASSERT PLAY_VIS_ROWS + 1 == 16  \ the board needs all 16 rows

\ ============================================================
\ XfStart — one-time entry, from XferEnter with this bank paged
\ ============================================================
\ Capture ($229D) up to the top of its _1 loop: clear the subgame state,
\ build the board, and settle into the fire-release wait that stands in
\ for WaitNoFire ($22AA) — the button that started the transfer is still
\ down, and the select phase would read it as an instant confirm.
.XfStart
  JSR XfBuildGlyphOf

  LDA USR_VIA_T1CL              \ free-running, sampled at an arbitrary
  EOR fieldCount                \ moment — the same well DrRandom's seed
  BNE xst_seed                  \ is drawn from. Zero locks the LFSR.
  LDA #&A5
.xst_seed
  STA xfSeed

  JSR XfClearSubGame
  JSR XfSelectSide              \ the board, into the shadows
  JSR XfRepaintAll              \ and once onto the screen
  JSR XfTextClear
  LDA #9                        \ Capture's entry pair: $22C1 on voice 2
  STA sndFx2                    \ and $22C8 on voice 1
  LDA #&1B
  STA sndFx1
  LDA #XF_PH_RELEASE
  STA xfPhase
  RTS

\ ============================================================
\ XfTick — one pass, from XferTickMain with this bank paged
\ ============================================================
\ Returns A = 0 while the game runs. Anything else is over and has been
\ written to xfmResult for the shim: 1 the player took the droid, 2 the
\ player lost. Ties never come out — Capture's _1 loop replays them, and
\ so does XF_PH_REPLAY.
.XfTick
  JSR XfReadInput
  LDA xfPhase
  CMP #XF_PH_SELECT
  BEQ xtk_select
  CMP #XF_PH_PLAY
  BEQ xtk_play
  CMP #XF_PH_END
  BEQ xtk_end
  CMP #XF_PH_REPLAY
  BEQ xtk_replay

\ ---- XF_PH_RELEASE: WaitNoFire ($22AA) ----------------------
  LDA xfFire
  BEQ xtk_run                   \ still held
  LDA #&99                      \ SubGameSelectSide's select countdown
  STA xfTime
  LDA #XF_PH_SELECT
  STA xfPhase
  JSR XfTimeText
  JSR XfSelectText
.xtk_run
  LDA #0
  RTS

\ ---- the keys, as the C64 reads its joystick ----------------
\ ReadJoystick's stand-in. Called at the top of the tick AND from
\ XfGetMove's human arm, because the CPU's half-turn overwrites joyYDir
\ and xfFire — exactly why the original re-reads at $214F.
.XfReadInput
  JSR ReadKeys                  \ joyXDir/joyYDir, main RAM
  LDX #KEY_L                    \ joyFire, IN THE C64'S SENSE: the CIA is
  JSR keydown                   \ active low, so 0 means PRESSED and the
  BEQ xri_down                  \ transliterated tests below are verbatim
  LDA #&10
  BNE xri_fire
.xri_down
  LDA #0
.xri_fire
  STA xfFire
  RTS

.xtk_select
  JMP XfSelectTick
.xtk_play
  JMP XfPlayTick
.xtk_end
  JMP XfEndTick
.xtk_replay
  JMP XfReplayTick

XF_PH_RELEASE = 0
XF_PH_SELECT  = 1
XF_PH_PLAY    = 2
XF_PH_END     = 3
XF_PH_REPLAY  = 4

\ ============================================================
\ XfSelectTick — one iteration of SubGameSelectSide's _14 loop
\ ============================================================
\ The original paces this with DelayScore(80) per iteration; ours runs
\ one iteration a pass and ticks the countdown every other one, which
\ lands the 99 ticks near the original's wall-clock. The droid sprites
\ that slide left and right are the panel line's two numbers instead —
\ the human's number sits on the side the stick last chose.
.XfSelectTick
  LDX xfLeftColor
  LDA joyXDir
  BEQ xsl_17
  BMI xsl_15
  LDX xfCpuColor                \ stick right: the human plays the right
  BNE xsl_16                    \ side, so the LEFT keeps the CPU colour
.xsl_15
  LDX xfPlyColor
.xsl_16
  STX xfLeftColor
.xsl_17
  JSR XfDrawResult              \ X = LeftColor: the default verdict
  JSR XfDrawPulserCols
  JSR XfSelectText

  LDA xfFire
  BNE xsl_18
  LDA #1                        \ fire pressed: confirm now
  STA xfTime
  BNE xsl_tick
.xsl_18
  INC xfFrame                   \ half the original's iteration rate
  LDA xfFrame
  AND #1
  BNE xsl_x
.xsl_tick
  SED
  SEC
  LDA xfTime
  SBC #1
  STA xfTime
  CLD
  JSR XfTimeText
  LDA xfTime
  BNE xsl_x
  LDA #&99                      \ $E21D: the game clock starts full
  STA xfTime
  LDA #XF_PH_PLAY
  STA xfPhase
  JSR XfTextClear
  JSR XfTimeText
  JSR XfSelectText              \ the two numbers stay up through play
.xsl_x
  LDA #0
  RTS

\ ============================================================
\ XfPlayTick — one iteration of doSubGame ($2166)
\ ============================================================
\ The original spends one 50 Hz frame on each half-turn; a pass here is
\ two fields, so one full iteration a pass is the same rate. The
\ AnimateIntoFont calls are the C64's background charset animation and
\ are not ported.
.XfPlayTick
  INC xfFrame

  JSR XfGetMove                 \ the LEFT half-turn
  LDA #LO(xsStage + &00) : STA xsrc
  LDA #HI(xsStage + &00) : STA xsrc+1
  JSR XfDoMove
  JSR XfPlayLeft
  LDA #LO(xsStage + &30) : STA xsrc
  LDA #HI(xsStage + &30) : STA xsrc+1
  LDY #14
  JSR XfDrawCBar                \ ...which ends by swapping the sides

  LDA xfGrace                   \ $218A: in the last moment of the grace
  CMP #1                        \ period the right half-turn is skipped
  BNE xpl_right                 \ half the time
  JSR XfRand
  BMI xpl_3
.xpl_right
  JSR XfGetMove                 \ the RIGHT half-turn
  LDA #LO(xsStage + &70) : STA xsrc
  LDA #HI(xsStage + &70) : STA xsrc+1
  JSR XfDoMove
  JSR XfPlayRight
  LDA #LO(xsStage + &40) : STA xsrc
  LDA #HI(xsStage + &40) : STA xsrc+1
  LDY #25
  JSR XfDrawCBar
  JSR XfDoCounter
.xpl_3
  JSR XfCheckEnd
IF DEBUG_XFERWIN
\ W hands the player the board — see main.asm. AFTER XfCheckEnd, so this
\ writes the same two things a won game leaves behind and the verdict
\ below cannot tell the difference: the human's colour won, and the game
\ is over. xfLeftColor is the human's, which is $21CF's own test.
  LDX #KEY_W
  JSR keydown
  BNE xpl_nowin
  LDA xfLeftColor
  STA xfWinColor
  LDA #1
  STA xfNotInDeck
.xpl_nowin
ENDIF
  LDA xfNotInDeck
  BNE xpl_over
  LDA #0
  RTS

\ ---- the game is over: Capture's verdict --------------------
\ WinningColor $F8 is a tie — "Short circuit" and play again, which is
\ Capture's _1 loop. Anything else is FinishTransfer1's test: the human
\ wins if the winning colour is the one they picked at select.
.xpl_over
  LDA xfWinColor
  CMP #&F8
  BNE xpl_decided
  JSR XfTextClear
  LDA #LO(xfTxtShort) : LDY #HI(xfTxtShort)
  JSR XfMessage
  LDA #&B                       \ the tie — provisional mapping of
  STA sndFx1                    \ FinishTransfer1's three posts, to be
                                \ A/B'd against VICE in stage 4
  LDA #XF_REPLAY_PASSES
  STA xfEndCtr
  LDA #XF_PH_REPLAY
  STA xfPhase
  LDA #0
  RTS
.xpl_decided
  JSR XfTextClear
  LDA xfWinColor
  CMP xfLeftColor               \ $21CF: LeftColor is the human's colour
  BNE xpl_lost
  LDA #1
  STA xfmResult
  LDA #&C                       \ won — provisional, see the tie's note
  STA sndFx1
  LDA #LO(xfTxtDone) : LDY #HI(xfTxtDone)
  JSR XfMessage
  JMP xpl_endphase
.xpl_lost
  LDA #2
  STA xfmResult
  LDA #&D                       \ lost — provisional
  STA sndFx1
  LDA #LO(xfTxtFail) : LDY #HI(xfTxtFail)
  JSR XfMessage
.xpl_endphase
  LDA #XF_END_PASSES            \ FinishTransfer2's sweep, as a hold
  STA xfEndCtr
  LDA #XF_PH_END
  STA xfPhase
  LDA #0
  RTS

XF_END_PASSES    = 50           \ ~2 s at 25 Hz
XF_REPLAY_PASSES = 50

\ ---- the result holds on screen, then the shim takes over ---
\ Done is a MAIN-RAM flag rather than a return value, because the shim's
\ bank restore runs through A before it could look at one.
.XfEndTick
  DEC xfEndCtr
  BNE xfe_run
  LDA #1
  STA xfmDone
.xfe_run
  LDA #0
  RTS

\ ---- a tie holds, then the whole subgame restarts -----------
.XfReplayTick
  DEC xfEndCtr
  BNE xfr_run
  JSR XfClearSubGame
  JSR XfSelectSide
  JSR XfRepaintAll
  JSR XfTextClear
  LDA #&99
  STA xfTime
  LDA #XF_PH_SELECT
  STA xfPhase
.xfr_run
  LDA #0
  RTS

\ ============================================================
\ XfClearSubGame — ClearSubGameData ($377E)
\ ============================================================
\ The C64 zeroes the FindStrings pointer pages, which double as the
\ pulser-count stage arrays. Ours is one page of its own.
.XfClearSubGame
  LDA #0
  TAY
.xcs_1
  STA xsStage,Y
  INY
  BNE xcs_1
  RTS

\ ============================================================
\ XfSelectSide — SubGameSelectSide ($E016), the setup half
\ ============================================================
\ Board and colours into the SHADOWS ONLY — every store in here is
\ direct, and XfRepaintAll paints the lot in one go afterwards. That is
\ why the gate-placement routines below it can stay verbatim.
\
\ The C64 clears its row 8 first; that row is above the board and does
\ not exist here. Its rows 9-24 are shadow rows 0-15 exactly.
.XfSelectSide
  LDA #LO(xsScr) : STA xdest
  LDA #HI(xsScr) : STA xdest+1
  LDY #119                      \ three top rows in one loop, as $E03D
.xss_top
  LDA xbTop,Y
  STA (xdest),Y
  DEY
  BPL xss_top
  CLC
  LDA xdest   : ADC #120 : STA xdest
  LDA xdest+1 : ADC #0   : STA xdest+1

  LDA #12                       \ twelve identical wire rows
  STA xfTmp2
.xss_5
  LDY #39
.xss_6
  LDA xbMid,Y
  STA (xdest),Y
  DEY
  BPL xss_6
  CLC
  LDA xdest   : ADC #40 : STA xdest
  LDA xdest+1 : ADC #0  : STA xdest+1
  DEC xfTmp2
  BNE xss_5

  LDY #39                       \ and the bottom
.xss_8
  LDA xbBottom,Y
  STA (xdest),Y
  DEY
  BPL xss_8

\ ---- the colours: $E077 on -----------------------------------
  LDA #&FF
  STA xfPlyColor
  LDA #&FC
  STA xfCpuColor

  LDA #LO(xsCram) : STA xdest   \ FillCRAM: the whole board neutral
  LDA #HI(xsCram) : STA xdest+1
  LDA #16
  STA xfTmp2
.xss_fill
  LDA #&F8
  LDY #39
.xss_f1
  STA (xdest),Y
  DEY
  BPL xss_f1
  CLC
  LDA xdest   : ADC #40 : STA xdest
  LDA xdest+1 : ADC #0  : STA xdest+1
  DEC xfTmp2
  BNE xss_fill

  LDA #LO(xsCram) : STA xdest   \ buses and the bar's even split, $E096
  LDA #HI(xsCram) : STA xdest+1
  LDA #16
  STA xfTmp2
.xss_9
  LDA xfPlyColor
  LDY #3
  STA (xdest),Y
  LDY #18
  STA (xdest),Y
  LDY #21
  LDA xfCpuColor
  STA (xdest),Y
  LDY #36
  STA (xdest),Y
  LDX xfPlyColor
  LDA xfTmp2
  AND #1
  BNE xss_10
  LDX xfCpuColor
.xss_10
  TXA
  LDY #19
  STA (xdest),Y
  INY
  STA (xdest),Y
  CLC
  LDA xdest   : ADC #40 : STA xdest
  LDA xdest+1 : ADC #0  : STA xdest+1
  DEC xfTmp2
  BNE xss_9

\ ---- the random gates: $E0CF on ------------------------------
\ dest starts at C64 $49EA — row 12 col 10, shadow row 3 col 10 — and
\ walks the twelve wire rows placing gates at columns 10/14 on the left
\ wire and 25/29 on the right, sides swapped around each pair.
  LDA #LO(xsScr + 3*40 + 10) : STA xdest
  LDA #HI(xsScr + 3*40 + 10) : STA xdest+1
  JSR XfGetCRAMptr
  LDA #12
  STA xfTmp2
  LDA #&FD
  STA xfPlyPulser
  LDA #&F3
  STA xfCpuPulser
  LDA #&F1
  STA xfPlyWire
  LDA #&F2
  STA xfCpuWire
  LDA #1
  STA xfDeltaX
  LDA #0
  STA xfDeltaX+1
.xss_12
  LDY #0
  JSR XfPutRandom
  LDY #4
  JSR XfPutRandom
  JSR XfSwitchSides
  LDY #19
  JSR XfPutRandom
  LDY #15
  JSR XfPutRandom
  JSR XfSwitchSides
  CLC
  LDA xdest : ADC #40 : STA xdest : STA xdest2
  LDA xdest+1 : ADC #0 : STA xdest+1
  STA xdest2+1                  \ $E11B keeps dest2 tracking dest; the
  CLC                           \ colour offset is re-derived below
  LDA xdest2+1 : ADC #HI(XS_COFF) : STA xdest2+1
  DEC xfTmp2
  BNE xss_12

\ ---- the rest of the state: $E123 on -------------------------
\ The two sprite blocks ($E12B-$E175) put the droids beside the board;
\ ours shows the numbers on the panel line instead — see XfSelectText.
  LDA #5
  STA xfPlyX
  LDA #&22
  STA xfCpuX
  LDA #&99                      \ $E178: the select countdown
  STA xfTime
  LDA #&55
  STA xfGrace
  LDA #0
  STA xfPlyY
  STA xfCpuY
  STA xfYWant
  STA xfNotInDeck
  STA xfFrame
  STA xfNLeft
  STA xfNRight
  STA xfWinColor
  LDA xfPlyColor
  STA xfLeftColor
  LDY xfmPlyType                \ $E18C: the class digits set the pulser
  LDA pnTabCent,Y               \ counts — read through the main-RAM
  STA xfPlyLevel                \ mirror, since bank 4 is invisible
  LDY xfmTgtType
  LDA pnTabCent,Y
  STA xfCpuLevel
  RTS

\ NOTE: dest2 tracking above re-adds the colour offset after copying
\ dest, because unlike the C64 ours are not a fixed $9000 apart in one
\ address space — XS_COFF is the whole difference.

\ ============================================================
\ XfPutRandom — xfer_PutRandom ($E222) and the five gates
\ ============================================================
\ Setup only: every store is a direct shadow write, painted later by
\ XfRepaintAll. This is what keeps xfer_PutSplitter and friends verbatim.
.XfPutRandom
  LDA (xdest),Y
  BEQ xpr_3
  CMP #&F3
  BCS xpr_x
  JSR XfRand
  AND #&F
  CMP #5
  BCC xpr_1
  LDA #5
.xpr_1
  ASL A
  TAX
  LDA xfWireJmp,X
  STA xpr_2+1
  LDA xfWireJmp+1,X
  STA xpr_2+2
.xpr_2
  JMP xpr_x                     \ operands patched: one of the six gates
.xpr_3
  LDA xfTmp2
  CMP #3
  BCC xpr_4
  JSR XfRand
  AND #&F
  CMP #3
  BEQ xpr_1
.xpr_4
  JSR XfClearWire4
.xpr_x
  RTS

.xfWireJmp
  EQUW XfPutAutoPulser
  EQUW XfPutTerminator
  EQUW XfPutSwitcher
  EQUW XfPutSplitter
  EQUW XfPutJoiner
  EQUW xpr_x                    \ xfer_PutNOP

.XfPutAutoPulser
  LDA xfPlyPulser
  STA (xdest),Y
  LDA xfPlyColor
  STA (xdest2),Y
  RTS

.XfPutTerminator
  CPY #0
  BEQ xpt_x
  CPY #19
  BEQ xpt_x
  LDA xfCpuPulser
  STA (xdest),Y
  LDA xfPlyColor
  STA (xdest2),Y
  JSR XfClearWire4
.xpt_x
  RTS

.XfPutSwitcher
  CPY #0
  BEQ xpt_x
  CPY #19
  BEQ xpt_x
  LDA #&F4
  STA (xdest),Y
  LDA xfCpuColor
  STA (xdest2),Y
  RTS

\ xfer_PutSplitter ($E287): probe the wire either side, and only fit the
\ splitter where the geometry allows one.
.XfPutSplitter
  STY xfColTmp
  LDX xdest
  LDY xdest+1
  STX xptr12
  STY xptr12+1
  LDA xfTmp2
  CMP #3
  BCC xps_4
  LDY xfColTmp
  JSR XfAdvanceWire
  LDA (xdest),Y
  CMP xfPlyWire
  BNE xps_4
  JSR XfRetreatWire
  JSR XfRetreatWire
  LDA (xdest),Y
  BEQ xps_1
  JSR XfRetreatWire
  JSR XfRetreatWire
  JSR XfRetreatWire
  LDA (xdest),Y
  CMP #&F5
  BCC xps_1
  CMP #&F8
  BCC xps_4
.xps_1
  LDX xptr12
  LDY xptr12+1
  STX xdest
  STY xdest+1
  LDY xfColTmp
  JSR XfPutVBar
  JSR XfPutBackPulser
  CLC
  LDA xdest : ADC #40 : STA xdest
  BCC xps_2
  INC xdest+1
.xps_2
  JSR XfClearWire4
  CLC
  LDA xdest : ADC #40 : STA xdest
  BCC xps_3
  INC xdest+1
.xps_3
  JSR XfPutBackPulser
.xps_4
  LDX xptr12
  LDY xptr12+1
  STX xdest
  STY xdest+1
  RTS

\ xfer_PutJoiner ($E2F4): the mirror probe, ahead instead of behind.
.XfPutJoiner
  STY xfColTmp
  LDX xdest
  LDY xdest+1
  STX xptr12
  STY xptr12+1
  LDA xfTmp2
  CMP #3
  BCC xpj_4
  LDY xfColTmp
  JSR XfAdvanceWire
  LDA (xdest),Y
  BEQ xpj_1
  JSR XfAdvanceWire
  JSR XfAdvanceWire
  JSR XfAdvanceWire
  LDA (xdest),Y
  CMP #&F5
  BCC xpj_1
  CMP #&F8
  BCC xpj_4
.xpj_1
  LDX xptr12
  LDY xptr12+1
  STX xdest
  STY xdest+1
  LDY xfColTmp
  JSR XfPutVBar
  JSR XfClearWire4
  CLC
  LDA xdest : ADC #40 : STA xdest
  BCC xpj_2
  INC xdest+1
.xpj_2
  JSR XfPutBackPulser
  CLC
  LDA xdest : ADC #40 : STA xdest
  BCC xpj_3
  INC xdest+1
.xpj_3
  JSR XfClearWire4
.xpj_4
  LDX xptr12
  LDY xptr12+1
  STX xdest
  STY xdest+1
  RTS

\ xfer_ClearWire4 ($E355): break the wire for four cells ahead.
.XfClearWire4
  STY xfColTmp
  LDX xdest
  LDY xdest+1
  STX xsrc
  STY xsrc+1
  LDY xfColTmp
  LDX #3
.xcw_1
  JSR XfAdvanceWire
  LDA #0
  STA (xdest),Y
  DEX
  BNE xcw_1
  JSR XfAdvanceWire
  LDA (xdest),Y
  CMP xfPlyWire
  BNE xcw_2
  LDA #0
  STA (xdest),Y
.xcw_2
  LDX xsrc
  LDY xsrc+1
  STX xdest
  STY xdest+1
  LDY xfColTmp
  RTS

\ sub_0_E385: clear four cells BEHIND, and cap a cut wire with an
\ opposing pulser. The colour write through ptr_14 is the C64 reaching
\ colour RAM by address arithmetic; ours reaches the shadow the same way.
.XfPutBackPulser
  STY xfColTmp
  LDX xdest
  LDY xdest+1
  STX xsrc
  STY xsrc+1
  LDY xfColTmp
  LDX #3
.xpb_1
  JSR XfRetreatWire
  LDA #0
  STA (xdest),Y
  DEX
  BNE xpb_1
  JSR XfRetreatWire
  LDA (xdest),Y
  BEQ xcw_2                     \ shared restore, as the original's is
  CMP #&F5
  BEQ xcw_2
  CMP #&F6
  BEQ xcw_2
  CMP #&F7
  BEQ xcw_2
  LDA xfCpuPulser
  STA (xdest),Y
  LDA xdest
  STA xptr14
  CLC
  LDA xdest+1
  ADC #HI(XS_COFF)
  STA xptr14+1
  LDA xfPlyColor
  STA (xptr14),Y
  JMP xcw_2

\ xfer_PutVBar ($E3EE): the three cells of a splitter/joiner bus.
.XfPutVBar
  TYA
  CLC
  ADC #40
  TAY
  LDA #&F6
  STA (xdest),Y
  LDA xfPlyColor
  STA (xdest2),Y
  TYA
  CLC
  ADC #40
  TAY
  LDA #&F7
  STA (xdest),Y
  LDA xfPlyColor
  STA (xdest2),Y
  LDY xfColTmp
  LDA #&F5
  STA (xdest),Y
  LDA xfPlyColor
  STA (xdest2),Y
  RTS

\ ============================================================
\ XfSwitchSides — xfer_SwitchSides ($E413) / xferSwapSide ($2017)
\ ============================================================
\ The two are byte-identical in the original; one copy serves both.
.XfSwitchSides
  LDA xfPlyWire
  LDX xfCpuWire
  STX xfPlyWire
  STA xfCpuWire
  LDA xfPlyPulser
  LDX xfCpuPulser
  STX xfPlyPulser
  STA xfCpuPulser
  LDA xfPlyColor
  LDX xfCpuColor
  STX xfPlyColor
  STA xfCpuColor
  LDA xfPlyY
  LDX xfCpuY
  STX xfPlyY
  STA xfCpuY
  LDA xfNLeft
  LDX xfNRight
  STX xfNLeft
  STA xfNRight
  LDA xfPlyX
  LDX xfCpuX
  STX xfPlyX
  STA xfCpuX
  LDA xfDeltaX+1
  EOR #&FF
  STA xfDeltaX+1
  LDA xfDeltaX
  EOR #&FF
  CLC
  ADC #1
  STA xfDeltaX
  RTS

\ ============================================================
\ XfGetMove — xfer_GetMove ($2109)
\ ============================================================
\ The half-turn whose colour matches the human's choice reads the keys;
\ the other side is the CPU, walking its cursor to a random target row
\ and firing when it arrives. The SID noise register becomes XfRand.
.XfGetMove
  LDA xfPlyColor
  CMP xfLeftColor
  BEQ xgm_human
  LDA xfFrame
  AND #1
  BNE xgm_nop
  LDA xfYWant
  CMP xfPlyY
  BEQ xgm_fire
  BCS xgm_3
.xgm_up
  LDA #&FF
  STA joyYDir
  RTS
.xgm_nop
  LDA #0
  STA joyYDir
  LDA #&10
  STA xfFire
  RTS
.xgm_3
  LDX xfPlyY
  BNE xgm_down
  CMP #7
  BCS xgm_up
.xgm_down
  LDA #1
  STA joyYDir
  RTS
.xgm_fire
  LDA #0
  STA joyYDir
  STA xfFire
  JSR XfRand
  AND #&F
  CLC
  ADC #1
  CMP #13
  BCC xgm_6
  SBC #8
.xgm_6
  STA xfYWant
  RTS
.xgm_human
  JMP XfReadInput               \ $214F: the joystick, re-read — the CPU
                                \ half-turn has been through these vars

\ ============================================================
\ XfDoMove — xfer_DoMove ($1D75)
\ ============================================================
\ Move the pulser cursor on the bus, and on fire, commit a pulser to the
\ wire: mark the stage count, take one off the stock and blank a cell of
\ the stock column.
.XfDoMove
  LDA xfNLeft
  BNE xdm_go                    \ (the original's BEQ _x is out of range
  RTS                           \ here — the helpers pad the middle)
.xdm_go
  LDA xfPlyY
  JSR XfGetLine
  LDA joyYDir
  BEQ xdm_3
  JSR XfRemovePulser
  LDA joyYDir
  BMI xdm_1
  INC xfPlyY
  LDA xfPlyY
  CMP #13
  BCC xdm_3
  LDA #1
  STA xfPlyY
  BNE xdm_3
.xdm_1
  DEC xfPlyY
  BMI xdm_2
  BNE xdm_3
.xdm_2
  LDA #12
  STA xfPlyY
.xdm_3
  LDA xfPlyY
  JSR XfGetLine
  JSR XfDrawPulser
  LDA xfFire
  BNE xdm_x
  JSR XfAdvanceWire
  LDY xfPlyX
  LDA (xdest),Y
  CMP xfPlyWire
  BNE xdm_x
  LDA #&A                       \ $1DED: a pulser committed to the wire
  STA sndFx1
  JSR XfScr2CRAM
  JSR XfDrawPulser
  JSR XfRetreatWire
  JSR XfScr2CRAM
  JSR XfRemovePulser
  LDA #13
  SEC
  SBC xfPlyY
  TAY
  LDA #&B0                      \ the committed pulser's stage marker
  STA (xsrc),Y
  LDA #0
  STA xfPlyY
  DEC xfNLeft
  LDA xfNLeft
  JSR XfGetLine
  LDX #4
.xdm_4
  JSR XfRetreatWire
  DEX
  BNE xdm_4
  JSR XfScr2CRAM
  LDA #&F2                      \ one cell of the stock column goes out
  LDY xfPlyX
  JSR XfWCol
.xdm_x
  RTS

\ xferRemovePulser ($1DF0) / xferDrawPulser ($1DFB). LIVE writes: these
\ go through the helpers so the cell repaints.
.XfRemovePulser
  LDY xfPlyX
.XfRemovePulserY                \ loc_0_1DF2, reached from XfDoColumn
  LDA xfPlyWire
  JSR XfWScr
  LDA #&F8
  JMP XfWCol                    \ and its RTS

.XfDrawPulser
  LDY xfPlyX
  LDA xfPlyPulser
  JSR XfWScr
  LDA xfPlyColor
  JMP XfWCol

\ ============================================================
\ XfPlayLeft / XfPlayRight — $1E06 / $1E5E
\ ============================================================
\ Three stage columns each: the pulser wave advances one stage a turn,
\ outermost first so a pulser cannot be advanced twice in one turn.
.XfPlayLeft
  LDA #LO(xsScr + 3*40) : STA xdest    \ C64 $49E0, row 12 col 0
  LDA #HI(xsScr + 3*40) : STA xdest+1
  LDA #LO(xsStage + &00) : STA xsrc
  LDA #HI(xsStage + &00) : STA xsrc+1
  LDA #LO(xsStage + &10) : STA xptr14
  LDA #HI(xsStage + &10) : STA xptr14+1
  LDY #6
  JSR XfDoColumn
  LDA #LO(xsStage + &10) : STA xsrc
  LDA #HI(xsStage + &10) : STA xsrc+1
  LDA #LO(xsStage + &20) : STA xptr14
  LDA #HI(xsStage + &20) : STA xptr14+1
  LDA #LO(xsScr + 3*40) : STA xdest
  LDA #HI(xsScr + 3*40) : STA xdest+1
  LDY #10
  JSR XfDoColumn
  LDA #LO(xsStage + &20) : STA xsrc
  LDA #HI(xsStage + &20) : STA xsrc+1
  LDA #LO(xsStage + &30) : STA xptr14
  LDA #HI(xsStage + &30) : STA xptr14+1
  LDA #LO(xsScr + 3*40) : STA xdest
  LDA #HI(xsScr + 3*40) : STA xdest+1
  LDY #14
  JMP XfDoColumn                \ and its RTS

.XfPlayRight
  LDA #LO(xsScr + 3*40) : STA xdest
  LDA #HI(xsScr + 3*40) : STA xdest+1
  LDA #LO(xsStage + &70) : STA xsrc
  LDA #HI(xsStage + &70) : STA xsrc+1
  LDA #LO(xsStage + &60) : STA xptr14
  LDA #HI(xsStage + &60) : STA xptr14+1
  LDY #33
  JSR XfDoColumn
  LDA #LO(xsStage + &60) : STA xsrc
  LDA #HI(xsStage + &60) : STA xsrc+1
  LDA #LO(xsStage + &50) : STA xptr14
  LDA #HI(xsStage + &50) : STA xptr14+1
  LDA #LO(xsScr + 3*40) : STA xdest
  LDA #HI(xsScr + 3*40) : STA xdest+1
  LDY #29
  JSR XfDoColumn
  LDA #LO(xsStage + &50) : STA xsrc
  LDA #HI(xsStage + &50) : STA xsrc+1
  LDA #LO(xsStage + &40) : STA xptr14
  LDA #HI(xsStage + &40) : STA xptr14+1
  LDA #LO(xsScr + 3*40) : STA xdest
  LDA #HI(xsScr + 3*40) : STA xdest+1
  LDY #25
  JMP XfDoColumn

\ ============================================================
\ XfDoColumn — xfer_DoColumn ($1EB6): THE RULE SET
\ ============================================================
\ Twelve rows of one stage column. Per row, (xsrc),Y is the pulser count
\ at that row: 0 nothing, negative the committed marker, positive a live
\ pulser to advance — and the character in the CELL decides what
\ advancing means. This routine is the whole game and is line-for-line
\ the original's, with the screen stores routed through the helpers.
.XfDoColumn
  STY xfColTmp
  LDA #12
  STA xfTmp2
.xdc_1
  LDY xfTmp2
  LDA (xsrc),Y
  BEQ xdc_5
  BMI xdc_6
  LDY xfColTmp
  LDA (xdest),Y
  CMP xfPlyPulser
  BEQ xdc_auto
  LDY xfTmp2
  LDA (xsrc),Y
  SEC
  SBC #1
  STA (xsrc),Y
  LDY xfColTmp
  LDA (xdest),Y
  CMP xfCpuPulser
  BEQ xdc_terminator
  CMP #&F5
  BEQ xdc_joiner
  CMP #&F6
  BNE xdc_2
  JMP xdc_splitter
.xdc_2
  CMP #&F7
  BEQ xdc_next
  JSR XfColorize4
  LDY xfTmp2
  JSR XfPut1
.xdc_next
  CLC
  LDA xdest
  ADC #40
  STA xdest
  BCC xdc_4
  INC xdest+1
.xdc_4
  DEC xfTmp2
  BNE xdc_1
  RTS
.xdc_5
  LDY xfColTmp
  JSR XfBlack4
  JMP xdc_next
.xdc_6
  LDY xfColTmp
  JSR XfColorize4
  LDY xfTmp2
  JSR XfPut1
  LDY xfTmp2
  JSR XfPut1
  LDA (xsrc),Y
  CLC
  ADC #1
  STA (xsrc),Y
  BNE xdc_next
  LDY xfColTmp
  JSR XfScr2CRAM
  JSR XfRemovePulserY
  JMP xdc_next
.xdc_auto
  JSR XfColorize4
  LDY xfTmp2
  JSR XfPut1
  LDA #&10
  STA (xsrc),Y
  JMP xdc_next
.xdc_terminator
  LDY xfTmp2
  LDA #0
  STA (xsrc),Y
  JMP xdc_next
.xdc_joiner
  LDY xfTmp2
  DEY
  DEY
  LDA (xsrc),Y
  BEQ xdc_next
  INY
  LDA #1
  STA (xsrc),Y
  JSR XfPut1
  LDX xdest
  LDY xdest+1
  STX xptr12
  STY xptr12+1
  CLC
  LDA xdest
  ADC #40
  STA xdest
  BCC xdc_10
  INC xdest+1
.xdc_10
  LDY xfColTmp
  JSR XfColorize4
  LDX xptr12
  LDY xptr12+1
  STX xdest
  STY xdest+1
  JMP xdc_next
.xdc_11
  LDA #0
  STA (xsrc),Y
  JMP xdc_next
.xdc_splitter
  LDY xfTmp2
  DEY
  LDA (xsrc),Y
  BNE xdc_11
  JSR XfPut1
  LDA #1
  STA (xsrc),Y
  INY
  INY
  JSR XfPut1
  LDX xdest
  LDY xdest+1
  STX xptr12
  STY xptr12+1
  CLC
  LDA xdest
  ADC #40
  STA xdest
  BCC xdc_13
  INC xdest+1
.xdc_13
  LDY xfColTmp
  JSR XfColorize4
  LDA xdest
  SEC
  SBC #80
  STA xdest
  LDA xdest+1
  SBC #0
  STA xdest+1
  JSR XfColorize4
  LDX xptr12
  LDY xptr12+1
  STX xdest
  STY xdest+1
  JMP xdc_next

.XfPut1                         \ xfer_put1 ($1FC7): the NEXT stage's count
  LDA #1
  STA (xptr14),Y
  RTS

\ xsub_Black4 ($1FCC) / xfer_Colorize4 ($1FD4): sweep four cells of the
\ wire ahead in this side's colour — or back to neutral for an empty row.
.XfBlack4
  JSR XfScr2CRAM
  LDA #&F8
  JMP xcz_1
.XfColorize4
  JSR XfScr2CRAM
  LDA (xdest2),Y
  ORA #&F0
.xcz_1
  STA xfSprCol
  LDX #3
.xcz_2
  JSR XfAdvanceWire
  JSR XfScr2CRAM
  LDA xfSprCol
  JSR XfWCol
  DEX
  BNE xcz_2
  JSR XfAdvanceWire
  JSR XfScr2CRAM
  LDA (xdest),Y
  CMP xfPlyWire
  BNE xcz_3
  LDA xfSprCol
  JSR XfWCol
.xcz_3
  LDX #4
.xcz_4
  JSR XfRetreatWire
  DEX
  BNE xcz_4
  RTS

\ ============================================================
\ pointer plumbing — $2005/$2302/$2310/$2795/$E3E2
\ ============================================================
.XfGetLine                      \ xferGetLine: A = cursor row 1-12
  CLC
  ADC #11
  TAY
  LDA xsLineHi,Y
  STA xdest+1
  LDA xsLineLo,Y
  STA xdest
  JMP XfScr2CRAM                \ and its RTS

.XfGetLinePtr                   \ xfer_GetLinePtr ($E4D3)
  CLC
  ADC #11
  TAY
  LDA xsLineHi,Y
  STA xdest+1
  LDA xsLineLo,Y
  STA xdest
  JMP XfGetCRAMptr

.XfAdvanceWire
  LDA xdest
  CLC
  ADC xfDeltaX
  STA xdest
  LDA xdest+1
  ADC xfDeltaX+1
  STA xdest+1
  RTS

.XfRetreatWire
  LDA xdest
  SEC
  SBC xfDeltaX
  STA xdest
  LDA xdest+1
  SBC xfDeltaX+1
  STA xdest+1
  RTS

.XfScr2CRAM                     \ Scr2ColorRAM ($2795) and GetCRAMptr
.XfGetCRAMptr                   \ ($E3E2) — identical here, one offset
  LDA xdest
  STA xdest2
  LDA xdest+1
  CLC
  ADC #HI(XS_COFF)
  STA xdest2+1
  RTS

\ ============================================================
\ XfDrawCBar — xferDrawCBar ($2057): the verdict, then swap sides
\ ============================================================
\ Consume the final stage's counts into the centre bar, count who holds
\ more of it, paint the result window, and swap the sides for the other
\ half-turn.
.XfDrawCBar
  STY xfColTmp
  LDA #12
  STA xfTmp2
  LDA #0
  STA xfWinSide
  LDA #LO(xsScr + 3*40) : STA xdest
  LDA #HI(xsScr + 3*40) : STA xdest+1
  JSR XfScr2CRAM
.xcb_1
  LDY xfTmp2
  LDA (xsrc),Y
  PHA
  LDA #0
  STA (xsrc),Y
  PLA
  BEQ xcb_2
  LDY xfColTmp
  LDA (xdest2),Y
  LDY #19
  JSR XfWCol
  INY
  JSR XfWCol
.xcb_2
  LDY #19
  LDA (xdest2),Y
  ORA #&F0
  CMP xfPlyColor
  BNE xcb_3
  INC xfWinSide
.xcb_3
  CLC
  LDA xdest
  ADC #40
  STA xdest
  BCC xcb_4
  INC xdest+1
.xcb_4
  JSR XfScr2CRAM
  DEC xfTmp2
  BNE xcb_1
  LDX xfCpuColor
  LDA xfWinSide
  CMP #6
  BEQ xcb_tie
  BCC xcb_cpu
  LDX xfPlyColor
.xcb_cpu
  JSR XfDrawResult
  JSR XfSwitchSides
  RTS
.xcb_tie
  LDX #&F8
  BNE xcb_cpu

\ xfer_DrawResult ($E453) / xferPutResultColor ($20C0): X = the colour,
\ into the 2x2 result window and the verdict variable.
.XfDrawResult
  LDA #LO(xsCram + XS_RESULT_OFS)
  STA xdest2
  LDA #HI(xsCram + XS_RESULT_OFS)
  STA xdest2+1
  TXA
  LDY #0
  JSR XfWCol
  INY
  JSR XfWCol
  LDY #40
  JSR XfWCol
  INY
  JSR XfWCol
  STA xfWinColor
  RTS

\ ============================================================
\ XfDrawPulserCols — xfer_DrawPulserCols ($E46D)
\ ============================================================
\ The two stock columns: level+3 pulsers for the human, level+4 for the
\ CPU, lit in each side's colour and doused ($F2 — invisible against the
\ background, exactly the C64's red-on-red) above the count.
.XfDrawPulserCols
  LDX xfPlyLevel
  INX
  INX
  INX
  LDY xfCpuLevel
  INY
  INY
  INY
  INY
  LDA xfLeftColor
  CMP xfPlyColor
  BEQ xdp_1
  STX xfNRight
  STY xfNLeft
  JMP xdp_2
.xdp_1
  STX xfNLeft
  STY xfNRight
.xdp_2
  LDA #1
  JSR XfGetLinePtr
  LDA #12
  STA xfTmp2
  LDA #13
  SEC
  SBC xfNLeft
  STA xfTmp1
  LDA #13
  SEC
  SBC xfNRight
  STA xfCurIdx
.xdp_3
  LDY #1
  LDA xfTmp1
  CMP xfTmp2
  BCC xdp_4
  LDA #&F2
  BNE xdp_5
.xdp_4
  LDA xfPlyColor
.xdp_5
  JSR XfWCol
  LDY #38
  LDA xfCurIdx
  CMP xfTmp2
  BCC xdp_6
  LDA #&F2
  BNE xdp_7
.xdp_6
  LDA xfCpuColor
.xdp_7
  JSR XfWCol
  CLC
  LDA xdest2
  ADC #40
  STA xdest2
  BCC xdp_8
  INC xdest2+1
.xdp_8
  DEC xfTmp2
  BNE xdp_3
  RTS

\ ============================================================
\ XfDoCounter / XfCheckEnd — $20DA / $2153
\ ============================================================
.XfDoCounter
  LDA xfFrame
  AND #1
  BNE xct_x
  LDA xfTime
  BEQ xct_x                     \ already out: NOTHING — $20E0's own early
  SED                           \ exit, and it matters: the time-up posts
  SEC                           \ exactly ONCE, below
  SBC #1
  STA xfTime
  CLD
  JSR XfTimeText
  LDA xfTime
  BNE xct_x
  LDA #&1B                      \ $2104: the countdown JUST hit zero — one
  STA sndFx2                    \ post, one zipper, which then fades out
                                \ over its ~3 s release. A first port of
                                \ this posted it every other pass from the
                                \ already-zero arm: full volume forever, no
                                \ fade — KC heard both the intensity and
                                \ the missing fade
.xct_x
  RTS

.XfCheckEnd
  LDA xfTime
  BNE xce_x
  LDA #0
  STA xfNLeft
  STA xfNRight
  DEC xfGrace
  LDA xfGrace
  BNE xce_x
  INC xfNotInDeck
.xce_x
  RTS

\ ============================================================
\ XfRand — the SID noise register ($D41B), as DrRandom's LFSR
\ ============================================================
\ DrRandom itself is in bank 4 and invisible from here, so this is its
\ own copy of the same maximal 8-bit LFSR, on its own seed. Two seeds on
\ one polynomial are two independent sequences; that part was always
\ fine.
\ THE POLYNOMIAL WAS NOT. It said $B4 and called itself maximal, and $B4
\ is not a primitive tap for a LEFT-shifting Galois LFSR at all: the
\ feedback has to reach bit 0, and $B4 = %10110100 has its low two bits
\ CLEAR. So bit 0 of every output is 0 for ever, bit 1 becomes 0 one
\ step later, and the period is 65 rather than 255.
\ What that cost, before it was found:
\   AND #3   gave 0 nearly always      — EndGame's wash came out one flat
\                                        colour, BUGS.md #14
\   AND #$F  gave only 0,4,5,8,12,14   — so XfPutRandom's `CMP #3 : BEQ`
\                                        at $551 could never be taken, and
\                                        the board is less varied than the
\                                        original's
\ $1D is droid.asm's own, x^8 + x^4 + x^3 + x^2 + 1, and is primitive:
\ period 255, and all sixteen values out of AND #$F.
.XfRand
  LDA xfSeed
  ASL A
  BCC xrn_1
  EOR #&1D                      \ the same polynomial DrRandom uses
.xrn_1
  STA xfSeed
  RTS

\ ============================================================
\ THE RENDERER — what the VIC-II did for free
\ ============================================================
\ A shadow cell is (row 0-15, col 0-39); its MODE 1 cell is 16 bytes at
\ BUF_BASE + row*640 + col*16. The character token picks the glyph, the
\ colour token picks WHICH SET: pen 1 the player's, 2 the CPU's, 3
\ neutral, 0 invisible (a doused stock cell — drawn as blank).

\ ---- the write helpers -------------------------------------
\ Every LIVE screen store in the game logic comes through here: write
\ the shadow, and repaint the cell ONLY if the byte changed. A, X and Y
\ are preserved, so the call sites stay shaped like the STA (dest),Y
\ they replace.
.XfWScr                         \ A -> (xdest),Y as a SCREEN byte
  STA xfWval
  STX xfWsx
  STY xfWsy
  LDA (xdest),Y
  CMP xfWval
  BEQ xws_same
  LDA xfWval
  STA (xdest),Y
  LDA xdest   : STA xfWptr
  LDA xdest+1 : STA xfWptr+1
  JSR XfPaintScrPtr
.xws_same
  LDX xfWsx
  LDY xfWsy
  LDA xfWval
  RTS

.XfWCol                         \ A -> (xdest2),Y as a COLOUR byte
  STA xfWval
  STX xfWsx
  STY xfWsy
  LDA (xdest2),Y
  CMP xfWval
  BEQ xws_same
  LDA xfWval
  STA (xdest2),Y
  LDA xdest2   : STA xfWptr
  LDA xdest2+1 : STA xfWptr+1
  JSR XfPaintColPtr
  JMP xws_same

\ ---- pointer+Y -> (row, col) -> repaint ---------------------
.XfPaintScrPtr
  SEC
  LDA xfWptr   : SBC #LO(xsScr) : STA xfOffL
  LDA xfWptr+1 : SBC #HI(xsScr) : STA xfOffH
  JMP xpp_common
.XfPaintColPtr
  SEC
  LDA xfWptr   : SBC #LO(xsCram) : STA xfOffL
  LDA xfWptr+1 : SBC #HI(xsCram) : STA xfOffH
.xpp_common
  CLC
  LDA xfOffL : ADC xfWsy : STA xfOffL
  LDA xfOffH : ADC #0    : STA xfOffH
  LDX #0                        \ divide by 40: row in X, col in xfOffL
.xpp_div
  LDA xfOffH
  BNE xpp_sub
  LDA xfOffL
  CMP #40
  BCC xpp_done
.xpp_sub
  SEC
  LDA xfOffL : SBC #40 : STA xfOffL
  LDA xfOffH : SBC #0  : STA xfOffH
  INX
  BNE xpp_div
.xpp_done
  LDA xfOffL
  \ fall through: X = row, A = col

\ ---- XfCellPaint: repaint one cell --------------------------
\ X = row 0-15, A = col 0-39. Reads both shadows back, so it does not
\ matter which of the two the caller changed.
.XfCellPaint
  STA xfColV
  CPX #16
  BCC xcp_on                    \ off the board: nothing (guard)
  RTS
.xcp_on
  CLC
  LDA xsLineShLo,X : ADC xfColV : STA xgs
  LDA xsLineShHi,X : ADC #0     : STA xgs+1
  LDY #0
  LDA (xgs),Y                   \ the character token
  STA xfChar
  CLC
  LDA xgs+1 : ADC #HI(XS_COFF) : STA xgs+1
  LDA (xgs),Y                   \ the colour token -> a pen
  AND #&0F
  TAY
  LDA xfPenOf,Y
  STA xfPen

\ the destination: BUF_BASE + row*640 + col*16
  LDA xfColV                    \ col*16, 10 bits
  ASL A : ASL A : ASL A : ASL A
  STA xgd
  LDA xfColV
  LSR A : LSR A : LSR A : LSR A
  STA xgd+1
  CLC
  LDA xgd   : ADC xfRowAdrLo,X : STA xgd
  LDA xgd+1 : ADC xfRowAdrHi,X : STA xgd+1

  LDA xfPen
  BEQ xcp_blank                 \ pen 0: invisible, so wipe the cell
  TAY
  LDX xfChar                    \ token -> glyph index -> set base + *16
  LDA xsGlyphOf,X
  STA xgs
  LDA #0
  STA xgs+1
  ASL xgs : ROL xgs+1
  ASL xgs : ROL xgs+1
  ASL xgs : ROL xgs+1
  ASL xgs : ROL xgs+1
  CLC
  LDA xgs   : ADC xfSetLo,Y : STA xgs
  LDA xgs+1 : ADC xfSetHi,Y : STA xgs+1
  LDY #15
.xcp_copy
  LDA (xgs),Y
  STA (xgd),Y
  DEY
  BPL xcp_copy
.xcp_x
  RTS
.xcp_blank
  LDA #0
  LDY #15
.xcp_wipe
  STA (xgd),Y
  DEY
  BPL xcp_wipe
  RTS

\ ---- XfRepaintAll: the whole board, once --------------------
\ After XfSelectSide has built the shadows. 640 cells is a few fields'
\ worth of copying; it runs at entry and on a tie's replay, where the
\ original also repaints its whole screen.
.XfRepaintAll
  LDX #0
.xra_row
  LDA #0
.xra_col
  STA xfRAcol
  STX xfRArow
  JSR XfCellPaint
  LDX xfRArow
  LDA xfRAcol
  CLC
  ADC #1
  CMP #40
  BNE xra_col
  INX
  CPX #16
  BNE xra_row
  RTS

\ colour token low nibble -> pen. $FF player, $FC CPU, $F8 neutral,
\ $F2 doused/invisible, $F0 black; anything unexpected reads neutral.
.xfPenOf
  EQUB 0, 3, 0, 3, 3, 3, 3, 3
  EQUB 3, 3, 3, 3, 2, 3, 3, 1

.xfSetLo
  EQUB 0, LO(xbCharsPly), LO(xbCharsCpu), LO(xbChars)
.xfSetHi
  EQUB 0, HI(xbCharsPly), HI(xbCharsCpu), HI(xbChars)

\ shadow row bases, C64-row-indexed (0-24; rows 0-8 are above the board
\ and clamp to row 0, which nothing reaches) and shadow-row-indexed.
.xsLineLo
  FOR n, 0, 8
    EQUB LO(xsScr)
  NEXT
  FOR n, 9, 24
    EQUB LO(xsScr + (n-9)*40)
  NEXT
.xsLineHi
  FOR n, 0, 8
    EQUB HI(xsScr)
  NEXT
  FOR n, 9, 24
    EQUB HI(xsScr + (n-9)*40)
  NEXT
.xsLineShLo
  FOR n, 0, 15
    EQUB LO(xsScr + n*40)
  NEXT
.xsLineShHi
  FOR n, 0, 15
    EQUB HI(xsScr + n*40)
  NEXT
.xfRowAdrLo
  FOR n, 0, 15
    EQUB LO(BUF_BASE + n*ROW_BYTES)
  NEXT
.xfRowAdrHi
  FOR n, 0, 15
    EQUB HI(BUF_BASE + n*ROW_BYTES)
  NEXT

\ ---- token -> glyph index, built at XfStart -----------------
\ 256 bytes so the paint is one indexed load; unlisted tokens map to
\ glyph 0, which is blank.
.XfBuildGlyphOf
  LDA #0
  TAX
.xbg_clear
  STA xsGlyphOf,X
  INX
  BNE xbg_clear
  LDX #XB_CHARS-1
.xbg_fill
  LDA xbCode,X
  TAY
  TXA
  STA xsGlyphOf,Y
  DEX
  BPL xbg_fill
  RTS

\ ============================================================
\ THE PANEL LINE — counter, numbers and verdicts
\ ============================================================
\ The C64 draws its transfer strings into the status rows above the
\ board; ours go on the panel's text line, which PanelTick does not
\ touch while the transfer runs (the shim skips it) and PanelSetup
\ repaints on exit. This is a minimal copy of PnGlyph — bank 6 owns the
\ real one and only one bank is visible — reading the same font from
\ main RAM.
XF_COL_MSG   = 4                \ verdict messages
XF_COL_LNUM  = 12               \ the left side's droid number
XF_COL_RNUM  = 25               \ the right side's
XF_COL_TIME  = 19               \ the countdown, centre
ASSERT PN_TEXT_ADDR > 0         \ panel.asm's constants are visible here

.XfGlyphAt                      \ A = glyph, xfTxtCol = column; advances
\ ON swSrc/swDst AND NOT xgs/xgd, because the font is packed now and
\ FontCell — main RAM, shared with the panel and the droid database —
\ names that pair. They are free here: the boot copies are boot-only and
\ PanelTick does not run while this screen owns the panel line. The
\ board renderer keeps xgs/xgd; the two never overlap.
  STA swSrc
  LDA #0
  STA swSrc+1
  ASL swSrc : ROL swSrc+1       \ * 16 — two 8-byte cells
  ASL swSrc : ROL swSrc+1
  ASL swSrc : ROL swSrc+1
  ASL swSrc : ROL swSrc+1
  CLC
  LDA swSrc   : ADC #LO(FONT_ADDR) : STA swSrc
  LDA swSrc+1 : ADC #HI(FONT_ADDR) : STA swSrc+1

  LDA xfTxtCol                  \ col * 16
  ASL A : ASL A : ASL A : ASL A
  STA swDst
  LDA xfTxtCol
  LSR A : LSR A : LSR A : LSR A
  STA swDst+1
  CLC
  LDA swDst   : ADC #LO(PN_TEXT_ADDR) : STA swDst
  LDA swDst+1 : ADC #HI(PN_TEXT_ADDR) : STA swDst+1

  LDA #&FF                      \ this one draws in every plane it is
  STA fontMask                  \ given — it never had an ink mask
  JSR FontCell                  \ top cell
  CLC
  LDA swDst   : ADC #LO(ROW_BYTES) : STA swDst
  LDA swDst+1 : ADC #HI(ROW_BYTES) : STA swDst+1
  CLC
  LDA swSrc   : ADC #8 : STA swSrc
  LDA swSrc+1 : ADC #0 : STA swSrc+1
  JSR FontCell                  \ bottom cell
  INC xfTxtCol
  RTS

.XfTextClear
  LDA #0
  STA xfTxtCol
.xtc_1
  LDA #PN_SPACE
  JSR XfGlyphAt
  LDA xfTxtCol
  CMP #PN_COLS
  BNE xtc_1
  RTS

.XfTimeText                     \ the BCD countdown, two digits
  LDA #XF_COL_TIME
  STA xfTxtCol
  LDA xfTime
  LSR A : LSR A : LSR A : LSR A
  CLC
  ADC #PN_DIGIT0
  JSR XfGlyphAt
  LDA xfTime
  AND #&0F
  CLC
  ADC #PN_DIGIT0
  JMP XfGlyphAt

.XfNum3                         \ A = droid type, at xfTxtCol
  TAY
  LDA pnTabCent,Y
  CLC
  ADC #PN_DIGIT0
  STY xfTmp1
  JSR XfGlyphAt
  LDY xfTmp1
  LDA pnTabNum,Y
  LSR A : LSR A : LSR A : LSR A
  CLC
  ADC #PN_DIGIT0
  JSR XfGlyphAt
  LDY xfTmp1
  LDA pnTabNum,Y
  AND #&0F
  CLC
  ADC #PN_DIGIT0
  JMP XfGlyphAt

\ The select phase's stand-in for the two droid sprites: the human's
\ number sits on the side the stick chose, the target's on the other.
.XfSelectText
  LDA #XF_COL_LNUM
  STA xfTxtCol
  LDA xfLeftColor
  CMP xfPlyColor
  BNE xstx_swap
  LDA xfmPlyType
  JSR XfNum3
  LDA #XF_COL_RNUM
  STA xfTxtCol
  LDA xfmTgtType
  JMP XfNum3
.xstx_swap
  LDA xfmTgtType
  JSR XfNum3
  LDA #XF_COL_RNUM
  STA xfTxtCol
  LDA xfmPlyType
  JMP XfNum3

.XfMessage                      \ A/Y = a glyph string, $FF-terminated
  STA xmg_get+1
  STY xmg_get+2
  LDA #XF_COL_MSG
  STA xfTxtCol
  LDX #0
.xmg_loop
  STX xfTmp1
.xmg_get
  LDA &FFFF,X
  CMP #&FF
  BEQ xmg_x
  JSR XfGlyphAt
  LDX xfTmp1
  INX
  BNE xmg_loop
.xmg_x
  RTS

XF_LC = PN_LOWER_A
.xfTxtDone                      \ "transfer done"
  EQUB XF_LC+19, XF_LC+17, XF_LC+0, XF_LC+13, XF_LC+18, XF_LC+5, XF_LC+4, XF_LC+17
  EQUB PN_SPACE
  EQUB XF_LC+3, XF_LC+14, XF_LC+13, XF_LC+4, &FF
.xfTxtFail                      \ "transfer failed"
  EQUB XF_LC+19, XF_LC+17, XF_LC+0, XF_LC+13, XF_LC+18, XF_LC+5, XF_LC+4, XF_LC+17
  EQUB PN_SPACE
  EQUB XF_LC+5, XF_LC+0, XF_LC+8, XF_LC+11, XF_LC+4, XF_LC+3, &FF
.xfTxtShort                     \ "short circuit"
  EQUB XF_LC+18, XF_LC+7, XF_LC+14, XF_LC+17, XF_LC+19
  EQUB PN_SPACE
  EQUB XF_LC+2, XF_LC+8, XF_LC+17, XF_LC+2, XF_LC+20, XF_LC+8, XF_LC+19, &FF

\ ============================================================
\ state
\ ============================================================
.xfPlyY      EQUB 0             \ xfer_PlyY — the cursor row, 0 = none
.xfCpuY      EQUB 0
.xfYWant     EQUB 0             \ the CPU's target row
.xfPlyColor  EQUB 0             \ the side vars swap EVERY half-turn:
.xfCpuColor  EQUB 0             \ "Ply" means "the side moving now"
.xfPlyWire   EQUB 0
.xfCpuWire   EQUB 0
.xfPlyPulser EQUB 0
.xfCpuPulser EQUB 0
.xfDeltaX    EQUW 0             \ +1 or -1: which way this side advances
.xfNLeft     EQUB 0             \ pulser stock, this side / the other
.xfNRight    EQUB 0
.xfPlyX      EQUB 0             \ the cursor's screen column
.xfCpuX      EQUB 0
.xfLeftColor EQUB 0             \ the HUMAN's colour — see FinishTransfer1
.xfWinSide   EQUB 0
.xfWinColor  EQUB 0
.xfTime      EQUB 0             \ BCD, select and play both
.xfGrace     EQUB 0             \ byte_0_89: iterations after time out
.xfNotInDeck EQUB 0
.xfPlyLevel  EQUB 0
.xfCpuLevel  EQUB 0
.xfFire      EQUB 0             \ C64 joyFire: 0 = PRESSED
.xfFrame     EQUB 0
.xfSeed      EQUB &A5
.xfPhase     EQUB 0
.xfEndCtr    EQUB 0
.xfTmp1      EQUB 0
.xfTmp2      EQUB 0
.xfColTmp    EQUB 0             \ the C64 parks this in xfer_cpuSpriteX
.xfCurIdx    EQUB 0
.xfSprCol    EQUB 0             \ Colorize4 parks the colour here
.xfWval      EQUB 0             \ write-helper saves
.xfWsx       EQUB 0
.xfWsy       EQUB 0
.xfWptr      EQUW 0
.xfOffL      EQUB 0
.xfOffH      EQUB 0
.xfChar      EQUB 0
.xfPen       EQUB 0
.xfColV      EQUB 0
.xfRArow     EQUB 0
.xfRAcol     EQUB 0
.xfTxtCol    EQUB 0

\ ---- the shadows -------------------------------------------
\ Screen and colour at a fixed page offset, so the C64's "add $90 to the
\ high byte" becomes "add 3". The stage page is the C64's $4400: eight
\ 16-byte pulser-count arrays, cleared whole by XfClearSubGame.
\
\ THEY LIVE ON TOP OF THE SPRITE SAVE AREAS, in main RAM, and cost this
\ bank nothing. The three screens that use them — the transfer game, the
\ lift view and the game over — are all modal: each short-circuits the
\ pass with JMP ml_passend before SprRestoreAll and SprDrawAll, so the
\ pool is frozen the whole time one is up, and every way out of all
\ three goes through ReframeView, whose rv_unsave clears all eight
\ sprSaved flags and whose RedrawAll repaints the buffer. So nothing
\ ever reads a background this has overwritten. ConDeckEnter4 already
\ stages the deck RLE here on the same reasoning; the console and these
\ three are mutually exclusive, and both re-stage on every entry.
\
\ 1,920 bytes of the 2,048, so the layout is unchanged and xsStage
\ keeps the same non-page-aligned offset it had in the bank.
xsScr     = SPR_SAVE
xsCram    = xsScr + XS_COFF
xsStage   = xsCram + &280
xsGlyphOf = xsStage + &100
ASSERT xsGlyphOf + &100 <= SPR_SAVE + SPR_SLOTS * 256

\ ============================================================
\ GoStart / GoTick — _gameover ($1455) and its explosion cloud
\ ============================================================
\ THE C64 HAS NO RESPAWN. EnterGame tests droidEnergy at $143B and
\ splits at $144D: riding something, you blow back into a 001 and play
\ on; already a 001, the game ends here. The port only ever had the
\ first arm, so this is the second.
\
\ WHAT IT LOOKS LIKE, from $1465 down. Seven more sprites are lit one a
\ pass at jittered copies of the player's own position, each carrying
\ explosion frame $39; every pass after that advances EVERY sprite's
\ image by one and switches off any that runs past $44. The counter
\ starts at 6 and runs to $F0, so the cloud takes 22 iterations and the
\ last sprites are still burning when the first have gone out.
\
\ DROIDS ARE FROZEN while it plays. $14A8 and $14C5 call RunGame and
\ NOT RunDroids — the display keeps running and the ship stops. The main
\ loop gates its movement and DroidsUpdate on overPhase for that reason.
\
\ THE JITTER IS COARSER THAN THE ORIGINAL'S. $1487 and $1498 offset the
\ VIC's sprite X and Y by (rnd AND 7) - 4 pixels. Our sprite X is a
\ 4-pixel CRTC unit plus a shift within it, so a pixel-exact offset
\ needs 16-bit arithmetic and a re-split; the unit is jittered instead,
\ which quantises the horizontal scatter to 4 px. Y is the original's,
\ pixel for pixel, and both are dropped rather than clamped when they
\ would leave the view — a sprite of eight going missing at the edge of
\ the screen is cheaper than the clamp and reads the same.
\
\ THE RANDOMS COME IN, they are not drawn here. DrRandom is bank 4's and
\ its LFSR must stay one sequence, so GoTick's shim draws the pass's two
\ bytes before it pages this bank in and leaves them in overRnd0/1. A
\ second generator here would fork the sequence and be a second thing to
\ keep in step.
\n\ IN BANK 7, with the transfer game and the lift view — the two other
\ screens that take the play area over, and where 11b-2's wash and
\ banner will want their shadow screen and glyph renderer. It reaches
\ the sprite pool, which is main RAM, and nothing in bank 4; the shims
\ in main.asm page it in and the data bank back out, as XferTick does.
GO_TICK_END = &F0               \ $14CA

.GoStart
  LDA #1
  STA overPhase                 \ from here the loop stops moving anything
  LDA #6                        \ $1465
  STA overTick
  RTS

\ Slot X becomes explosion frame 0 at a jittered copy of the player's.
.GoSeed
  LDA #1          : STA sprActive,X
  LDA #1          : STA sprKind,X
  LDA #EF_EXPLODE : STA sprType,X
  LDA #0          : STA sprSaved,X   \ nothing of ITS background is held:
                                     \ the slot may have been free, and a
                                     \ stale save would be restored over
                                     \ the deck at the wrong address
  LDA sprShift+PLY_SLOT
  STA sprShift,X

  LDA overRnd0                  \ $1487, in units rather than pixels
  AND #3
  CLC
  ADC sprUnit+PLY_SLOT
  SEC
  SBC #1
  CMP #PLAY_UNITS               \ off the view either way: unsigned, so
  BCS go_seed_off               \ the wrap catches a negative too
  STA sprUnit,X

  LDA overRnd1                  \ $1498, pixel for pixel
  AND #7
  CLC
  ADC sprScrY+PLY_SLOT
  SEC
  SBC #4
  CMP #PLAY_VIS_ROWS * 8
  BCS go_seed_off
  STA sprScrY,X
  RTS
.go_seed_off
  LDA #0
  STA sprActive,X               \ it would have been off the view
  RTS

\ One pass of the cloud. Returns with overPhase still set until the
\ last frame has burnt out.
.GoTick
  LDA overPhase                 \ phase 2 is the wash, and the main loop
  CMP #2                        \ reaches it through its own modal block
  BNE go_cloud
  JMP GoWashTick
.go_cloud

  LDA overTick                  \ $1478: one more alight, while any left
  BMI go_anim
  CLC
  ADC #1                        \ 6..0 -> slots 7..1; slot 0 is the player
  TAX                           \ and was lit by ccd_start
  JSR GoSeed
.go_anim
  LDX #SPR_SLOTS-1              \ $14AF: every sprite, one image on
.go_a1
  LDA sprActive,X
  BEQ go_a2
  LDA sprKind,X
  BEQ go_a2                     \ a frozen droid, not part of the cloud
  LDA sprType,X
  CLC
  ADC #1
  CMP #EF_EXPLODE + EF_EXPLODE_N
  BCC go_a3
  LDA #0
  STA sprActive,X               \ $14BA: past the last frame, switch it off
  BEQ go_a2                     \ always
.go_a3
  STA sprType,X
.go_a2
  DEX
  BPL go_a1

  DEC overTick                  \ $14C8
  LDA overTick
  CMP #GO_TICK_END
  BNE go_x

\ ---- the cloud has burnt out: $14D0 JSR EndGame ------------
  JMP GoWashStart
.go_x
  RTS

\ ============================================================
\ GoWashStart / GoWashTick — EndGame's wash ($3797-$37D9)
\ ============================================================
\ The C64 fills its play rows with `(rnd AND 3) + $7A` — four characters
\ of the deck's own charset, which read as static — and then boils them
\ for 128 frames by ANIMATING THE CHARSET: AnimAllInsideFont ($38C4)
\ walks a table of self-modifying pointers over the font while vScroll
\ shakes the screen. Then it goes hires and draws GAME OVER over the 999.
\
\ WHAT IS DIFFERENT HERE, and why. [DECISION 7]
\
\ 1. NO CHARSET ANIMATION. AnimAllInsideFont is the same machinery as
\    AnimateIntoFont, which Layer 10 already declined to port; this
\    follows that. The wash boils by being REPAINTED instead — one row a
\    pass, so the whole screen churns every sixteen — which is the same
\    class of effect for a fraction of the cost and no new data.
\ 2. THE MESSAGE IS ON THE PANEL LINE, not a hires screen. That is
\    decisions 6-8 of Layer 10 again: this bank's text engine writes the
\    panel line and nothing else, and [DECISION 3] already took the 999
\    portrait the C64 draws behind those two strings.
\ 3. The whole 640-cell paint runs in one pass at entry, as
\    XfRepaintAll's does at the transfer's; the frame lock is a floor.
\
\ THE VIEW IS FLATTENED FIRST, exactly as XferEnter4 does before the
\ board: scrollS and line to zero and the CRTC re-parked, so the buffer
\ addresses as a plain 16 x 640 array and xfRowAdrLo/Hi apply.
GO_HOLD      = 88               \ $3802: xfer_plySpriteX counts 88 down

.GoWashStart
  LDA overRnd0                  \ XfRand's seed is XfStart's to set and the
  BNE gw_seed                   \ game over never goes through XfStart; a
  LDA #&A5                      \ ZERO SEED LOCKS THE LFSR, and every cell
.gw_seed                        \ of the wash came out the same pattern
  STA xfSeed

  LDX #SPR_SLOTS-1
  LDA #0
.gw_clr
  STA sprActive,X
  STA sprSaved,X                \ or the next SprRestoreAll puts the deck
  STA sprKind,X                 \ back over the wash
  DEX
  BPL gw_clr

  STA scrollS : STA scrollS+1   \ the flatten, XferEnter4's own
  STA line
  STA iline
  STA bandDo
  STA colCount
  JSR SetCRTCStart

  LDX #15
.gw_all
  STX goBoil
  JSR GoWashRow
  LDX goBoil
  DEX
  BPL gw_all
  STX goBoil                    \ leaves it $FF; the first tick wraps to 0

  JSR XfTextClear
  LDA #LO(goTxtOver)
  LDY #HI(goTxtOver)
  JSR XfMessage

  LDA #2
  STA overPhase
  LDA #GO_HOLD
  STA overTick
  LDA #5                        \ $3800: the GAME OVER message's cue, and
  STA sndFx1                    \ $14E7's transition chord on voice 2
  LDA #&16
  STA sndFx2
  RTS

\ One pass of the hold: boil one row, and count down to the restart.
.GoWashTick
  LDA xfSeed                    \ stirred from the pass's own random, so a
  EOR overRnd1                  \ short cycle cannot make the boil repeat
  BEQ gwt_noseed
  STA xfSeed
.gwt_noseed
  INC goBoil
  LDA goBoil
  CMP #16
  BNE gwt_row
  LDA #0
  STA goBoil
.gwt_row
  TAX
  BNE gwt_paint                 \ $37BF: the wash's roar, re-posted each
  LDA #&F                       \ time the boil wraps — every 16 passes,
  STA sndFx1                    \ near the C64's every-76-frames refire
.gwt_paint
  JSR GoWashRow

  DEC overTick
  BNE gwt_x
  LDA #1
  STA overDone                  \ $14D3 JMP TitleLoop, until 11c exists
.gwt_x
  RTS

\ X = row 0-15. Forty cells of static, straight into the flat buffer.
\
\ THE FOUR CHARACTERS ARE OURS, NOT THE C64'S — and not by choice.
\ $379F picks `(rnd AND 3) + $7A` out of the deck charset, and $7A-$7D
\ ARE NOT IN THE PORTED SET: export_bbc.py converts only the characters
\ some tile references, and those four are used by EndGame and nothing
\ else, so CHAR_PTR_LO/HI clamp all four to entry 0 and the wash came out
\ blank. Exporting them is a tools change and a data regeneration, so it
\ is a TODO rather than something done here.
\
\ What replaces them keeps the part that matters. $37A6 writes colour
\ $F0 — low nibble 0, BLACK — so the C64's wash is four black shapes
\ dissolving the deck into darkness, not white noise. Logical 1 is black
\ under the port's fixed slot roles, so these are four densities of it:
\ solid, half, quarter and sparse. A cell picks one at random and the
\ boil re-picks a row a pass, so it shimmers the way the animated font
\ does. [DECISION 7]
.GoWashRow
  LDA xfRowAdrLo,X : STA xgd
  LDA xfRowAdrHi,X : STA xgd+1
  LDA #40
  STA goCol
.gwr_cell
  JSR XfRand
  AND #3
  ASL A : ASL A : ASL A : ASL A \ pattern * 16
  TAX
  LDY #0
.gwr_copy
  LDA goWashPat,X
  STA (xgd),Y
  INX
  INY
  CPY #16
  BNE gwr_copy
  CLC
  LDA xgd : ADC #16 : STA xgd
  BCC gwr_nc
  INC xgd+1
.gwr_nc
  DEC goCol
  BNE gwr_cell
  RTS

\ Four 16-byte MODE 1 cells: left half's eight scanlines then the right
\ half's, as CLAUDE.md's layout note has it. &0F is four pixels of
\ logical 1 and &00 is four of the deck's background.
.goWashPat
  EQUB &0F,&0F,&0F,&0F,&0F,&0F,&0F,&0F   \ solid
  EQUB &0F,&0F,&0F,&0F,&0F,&0F,&0F,&0F
  EQUB &0F,&00,&0F,&00,&0F,&00,&0F,&00   \ half
  EQUB &00,&0F,&00,&0F,&00,&0F,&00,&0F
  EQUB &0F,&00,&00,&00,&0F,&00,&00,&00   \ quarter
  EQUB &00,&00,&0F,&00,&00,&00,&0F,&00
  EQUB &00,&00,&00,&0F,&00,&00,&00,&00   \ sparse
  EQUB &00,&0F,&00,&00,&00,&00,&00,&00

.goTxtOver                      \ "game over"
  EQUB XF_LC+6, XF_LC+0, XF_LC+12, XF_LC+4
  EQUB PN_SPACE
  EQUB XF_LC+14, XF_LC+21, XF_LC+4, XF_LC+17, &FF
.goCol       EQUB 0
.goBoil      EQUB 0             \ which row the boil repaints next
