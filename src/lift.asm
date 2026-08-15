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
\ ---- why lift mode is a flag and not a loop -----------------
\ DoLift ($267A) spins its own loop: it saves the VIC state, switches to
\ hires, draws the side view, polls the joystick, and restores. That
\ works there because nothing else has to keep running.
\
\ Here the rupture, the sprite pool and the edge redraws all have to
\ keep going, so a modal loop would have to call WaitField, both sprite
\ passes and DoRedraws itself — i.e. reimplement the main loop. A flag
\ that suppresses movement and re-points UP/DOWN costs three tests in
\ the main loop and leaves everything else untouched.
\
\ THE SIDE VIEW BELONGS TO LAYER 9, and until it exists a lift has no
\ display of its own — you press fire, the whole deck changes under you,
\ and you press fire again. That is the only feedback there is, which is
\ why binding up/down to the wrong keys read as the lift being frozen
\ rather than as a missing key.
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
\ LiftEnter / LiftExit — fire, edge triggered
\ ============================================================
.LiftEnter
  JSR LiftFind
  BCS le_x                      \ not standing on one
  LDA #1
  STA liftMode
  LDA #0                        \ stop dead, so ApplyMove has nothing to
  STA xSpd : STA xSpd+1         \ apply while the lift has the controls
  STA ySpd : STA ySpd+1
.le_x
  RTS

.LiftExit
  LDA #0
  STA liftMode
  RTS

\ ============================================================
\ LiftStep — A = +1 or -1: move one stop along this shaft
\ ============================================================
\ The shaft test is the whole bounds check. Walking off either end lands
\ on a sentinel whose shaft is 8, which cannot match liftNum, so the
\ lift simply does not move.
.LiftStep
  CLC
  ADC liftPos
  TAX
  LDA liftShaft,X
  CMP liftNum
  BNE ls_x                      \ end of the shaft
  STX liftPos
  LDA liftDeck,X
  STA deck
  LDA #1                        \ LoadDeck places us on the platform
  STA liftPlace                 \ instead of calling CentreOnDeck
  JSR LoadDeck
.ls_x
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
  STA lpTmp
  LDA #0
  STA lpTmp+1
  ASL lpTmp : ROL lpTmp+1
  ASL lpTmp : ROL lpTmp+1
  ASL lpTmp : ROL lpTmp+1
  ASL lpTmp : ROL lpTmp+1
  ASL lpTmp : ROL lpTmp+1
  LDA lpTmp   : STA plyX
  LDA lpTmp+1 : STA plyX+1

  LDX liftPos
  LDA liftTileRow,X             \ posY = tileRow * 32 - 48
  STA lpTmp
  LDA #0
  STA lpTmp+1
  ASL lpTmp : ROL lpTmp+1
  ASL lpTmp : ROL lpTmp+1
  ASL lpTmp : ROL lpTmp+1
  ASL lpTmp : ROL lpTmp+1
  ASL lpTmp : ROL lpTmp+1
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

\ ============================================================
\ LiftControl — the controls, while the lift has them
\ ============================================================
\ THE MOVEMENT KEYS DRIVE THE LIFT, not the cursor keys. ChangeDeck
\ ($2705) steps on `joyYDir`, which is the joystick — the same control
\ that walks the droid — so in a lift, up and down are the up and down
\ you already have your fingers on. Binding this to the cursor keys was
\ simply wrong, and reads as the lift being broken.
\ Edge triggered on a pair of its own rather than prevUp/prevDn: those
\ belong to the debug cursor hop, and sharing them means a cursor key
\ held on the way in swallows the first press in here.
.LiftControl
  LDX #KEY_K
  JSR keydown
  BNE lc_upOff
  LDA prevLU
  BNE lc_notUp
  LDA #1
  STA prevLU
  LDA #&FF                      \ up the shaft: one index back
  JSR LiftStep
  JMP lc_notUp
.lc_upOff
  LDA #0
  STA prevLU
.lc_notUp

  LDX #KEY_M
  JSR keydown
  BNE lc_dnOff
  LDA prevLD
  BNE lc_notDn
  LDA #1
  STA prevLD
  LDA #1
  JSR LiftStep
  JMP lc_notDn
.lc_dnOff
  LDA #0
  STA prevLD
.lc_notDn
  RTS

\ ---- state --------------------------------------------------
.liftMode   EQUB 0              \ non-zero: the lift has the controls
.liftPos    EQUB 0              \ index of the stop we are at, 1-30
.liftNum    EQUB 0              \ its shaft, so stepping cannot leave it
.liftPlace  EQUB 0              \ LoadDeck: place at liftPos, not centre
.prevRet    EQUB 0              \ fire edge
.prevLU     EQUB 0              \ and the lift's own up/down edges, kept
.prevLD     EQUB 0              \ apart from the debug hop's
.lfCol      EQUB 0
.lfRow      EQUB 0
.lpTmp      EQUW 0
