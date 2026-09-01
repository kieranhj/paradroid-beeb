\ ============================================================
\ lift.asm — lifts, and the deck change that goes with them
\ ============================================================
\ Stand on a lift platform, press FIRE (L), and the up/down movement
\ keys move through the decks that lift's SHAFT serves. FIRE again
\ steps out.
\
\ ---- the tables ---------------------------------------------
\ Thirty-one stops, indexed 1-30, exported by tools/export_bbc.py as the
\ TILE each platform occupies. The C64 stores them as the view origin
\ instead, with the platform at origin tile + (5, 2) — the exporter
\ applies that so the offset never appears here. See the header there,
\ and docs/layer-8-doors-lifts.md for how it was found, because it is
\ not written down anywhere in the listing.
\
\ A SHAFT IS A CONTIGUOUS RUN OF INDICES, and the decks it serves are
\ not adjacent — shaft 0 runs decks 0, 2, 3, 14, 15. So "up a deck" is
\ meaningless: stepping walks the index and reads the deck out of the
\ table. Index 0 and 31 carry shaft 8, which matches no real shaft
\ (0-7), and that single fact is what stops a lift at each end of its
\ run. ChangeDeck ($2705) does exactly this and the sentinels are why
\ it needs no bounds test.
\
\ ---- the side view, and how the mode flag stages it ---------
\ DoLift ($267A) spins a modal loop over the ship cross-section. Ours
\ rides the pass structure the way the console and the transfer do,
\ with liftMode as a three-state:
\
\   0  no lift
\   1  ENTERING — set by LiftEnter in the fire block, consumed later
\      the same pass at the hook after DroidsUpdate, which runs the
\      full entry (LiftViewEnter below) and short-circuits the pass
\   2  THE VIEW IS UP — the main loop's lift arm runs one
\      LiftViewTick a pass and nothing else moves
\
\ The display is liftview.asm in bank 7 on Layer 10's machinery; the
\ stepping and the machine-state swap are LvEnter4/LvTick4/LvExit4 in
\ droid.asm, bank 4, where the stop tables live. K/M walk the selection
\ along the shaft — the deck does NOT load per step, unlike the C64's
\ per-step BuildLevel, because our LoadDeck draws into the play buffer
\ the side view is occupying. Fire commits: one load if the selection
\ moved, a plain reframe if it did not. [DECISION — layer-8b doc]
\ ============================================================

LIFT_FIRST = 1                  \ index 0 is a sentinel
LIFT_LAST  = 30                 \ and so is 31

\ ============================================================
\ LiftFind — is the player standing on a lift on this deck?
\ Carry clear = yes, and liftPos / liftNum are set.
\ ============================================================
\ Matches on the TILE the player's reference cell is in, not on the view
\ origin the way FindLift does. The C64 can use the origin because its
\ player is pinned at a fixed offset from it; ours is not — the play
\ area is 15 rows to its 17, and the horizontal dead zone means the
\ player moves independently of the view. The tile the player is
\ standing on is the same question asked in a way that survives both.
\
\ plyCX / plyCY are the reference cell, left by CheckWalls earlier in
\ the pass. Lift mode suppresses CheckWalls, but this only ever runs on
\ the way IN, when it has just been called.
.LiftFind
  LDA plyCX
  LSR A : LSR A
  STA lfCol
  LDA plyCY
  LSR A : LSR A
  STA lfRow

  LDX #LIFT_LAST
.lf_loop
  LDA liftDeck,X
  CMP deck
  BNE lf_next
  LDA liftTileCol,X
  CMP lfCol
  BNE lf_next
  LDA liftTileRow,X
  CMP lfRow
  BEQ lf_hit
.lf_next
  DEX
  BNE lf_loop                   \ index 0 is the sentinel, never a match
  SEC
  RTS

.lf_hit
  STX liftPos
  LDA liftShaft,X
  STA liftNum
  CLC
  RTS

\ ============================================================
\ LiftEnter — fire, edge triggered: stage the view for this pass
\ ============================================================
.LiftEnter
  JSR LiftFind
  BCS le_x                      \ not standing on one
  LDA #1
  STA liftMode                  \ ENTERING: the hook after DroidsUpdate
                                \ finishes the job this same pass
  LDA #0                        \ stop dead, so ApplyMove has nothing to
  STA xSpd : STA xSpd+1         \ apply while the lift has the machine
  STA ySpd : STA ySpd+1
.le_x
  RTS

\ ============================================================
\ LiftViewEnter / LiftViewTick — the bank trampolines
\ ============================================================
\ The pattern is XferEnter/XferTick's, for XferEnter's reason: bank-4
\ code cannot page bank 7 in under its own feet, and LoadDeck and
\ PanelSetup reach bank 6, so both belong to main RAM.
.LiftViewEnter
  JSR LvEnter4                  \ bank 4: flatten, palette, t1i3, mirrors
  JSR PgXfer   
  JSR LvStart7
  JMP PgData     \ tail: its RTS is ours

.LiftViewTick
  JSR LvTick4                   \ bank 4: keys, step, the fire edge
  JSR PgXfer   
  JSR LvTick7                   \ bank 7: move the light, if it moved
  JSR PgData   
  LDA lvCommit
  BEQ lvt_x
  JSR LvExit4                   \ bank 4: palette black, deck set
  LDA lvLoad
  BNE lvt_load
  JSR ReframeView               \ same deck: the world was always there
  JMP PanelSetup
.lvt_load
  JMP LoadDeck                  \ new deck: liftPlace is set, and LoadDeck
                                \ ends with PanelSetup itself
.lvt_x
  RTS

\ ============================================================
\ LiftPlace — put the player on liftPos's platform
\ ============================================================
\ Called from LoadDeck in place of CentreOnDeck / SetPosFromMap.
\
\ The arithmetic is chosen so posY lands on a multiple of 8, because
\ LoadDeck forces `line` to 0 and a posY that disagreed with it would
\ jump a scanline on the next pass:
\
\   plyX = tileCol * 32          -> reference cell = tileCol*4 + 1
\   posY = tileRow * 32 - 48     -> reference row  = tileRow*4 + 1
\
\ both landing one character inside the platform rather than on its
\ edge. posY is negative for tileRow 0, which is fine — the view is
\ allowed PLY_VOID pixels off the map now.
.LiftPlace
  LDX liftPos

  LDA liftTileCol,X             \ plyX = tileCol * 32
  JSR LpMul32
  LDA lpTmp   : STA plyX
  LDA lpTmp+1 : STA plyX+1

  LDX liftPos
  LDA liftTileRow,X             \ posY = tileRow * 32 - 48
  JSR LpMul32
  SEC
  LDA lpTmp   : SBC #48 : STA posY
  LDA lpTmp+1 : SBC #0  : STA posY+1

  SEC                           \ posX puts the player at its home column
  LDA plyX   : SBC #LO(PLY_HOME_X) : STA posX
  LDA plyX+1 : SBC #HI(PLY_HOME_X) : STA posX+1
  LDA posX+1
  BPL lp_hi
  LDA #0                        \ a platform near the left edge
  STA posX
  STA posX+1
  JMP lp_grid
.lp_hi
  CMP #HI(MAX_PX_X)
  BCC lp_grid
  BNE lp_sethi
  LDA posX
  CMP #LO(MAX_PX_X)
  BCC lp_grid
  BEQ lp_grid
.lp_sethi
  LDA #LO(MAX_PX_X) : STA posX
  LDA #HI(MAX_PX_X) : STA posX+1
.lp_grid
  LDA posX                      \ posX must stay on the 4-pixel grid, or
  AND #&FC                      \ mapHX = posX >> 2 loses the remainder
  STA posX

  LDA #0                        \ arrive stopped, and on a whole pixel
  STA xSpd : STA xSpd+1
  STA ySpd : STA ySpd+1
  STA plyXf : STA posXf : STA posYf

  JMP SetMapFromPos             \ mapHX / mapYr / line, and its RTS

\ ---- state --------------------------------------------------
\ THE MOVEMENT KEYS DRIVE THE LIFT, not the cursor keys: ChangeDeck
\ ($2705) steps on joyYDir, the same control that walks the droid. The
\ edge pairs are the lift's own rather than prevUp/prevDn — those
\ belong to the debug hop, and sharing them means a key held on the
\ way in swallows the first press. LvTick4 (droid.asm) reads them now.
.liftMode   EQUB 0              \ 0 none / 1 entering / 2 view up
.liftPos    EQUB 0              \ index of the stop we are at, 1-30
.liftNum    EQUB 0              \ its shaft, so stepping cannot leave it
.liftPlace  EQUB 0              \ LoadDeck: place at liftPos, not centre
.prevRet    EQUB 0              \ fire edge
.prevLU     EQUB 0              \ and the lift's own up/down edges, kept
.prevLD     EQUB 0              \ apart from the debug hop's
.lfCol      EQUB 0
.lfRow      EQUB 0
\ lpTmp = A * 32, 16 bits. A loop, not an unroll: LiftPlace runs once
\ per deck load, so the ~45 extra cycles a call buy 25 bytes each of
\ the code image back (RAM pass 4). Y, not X — X holds liftPos.
.LpMul32
  STA lpTmp
  LDA #0
  STA lpTmp+1
  LDY #5
.lpm_loop
  ASL lpTmp : ROL lpTmp+1
  DEY
  BNE lpm_loop
  RTS

.lpTmp      EQUW 0
.lvSelDeck  EQUB 0              \ the deck the selection is on — bank 7
                                \ shows it, LvStep (bank 4) moves it
.lvEntryPos EQUB 0              \ liftPos on the way in: unmoved = no load
.lvPrevFire EQUB 0              \ the view's own fire edge
.lvCommit   EQUB 0              \ LvTick4 -> the trampoline: fire fell
.lvLoad     EQUB 0              \ LvExit4 -> the trampoline: load, or not
