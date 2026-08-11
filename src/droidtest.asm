\ ============================================================
\ droidtest.asm — static droids, for feel and for the budget
\ ============================================================
\ SCAFFOLDING, not the game. Layer 5 proper gives droids state,
\ waypoints and movement (src/droid.asm, when it exists); this puts
\ six of them on screen standing still, so the pool can be looked at
\ and measured before any of that is written.
\
\ They are static in the WORLD, not on the screen: each holds a world
\ pixel position and is mapped through the view every frame, so the
\ deck scrolls past them the way it will when they move. That mapping
\ is the part worth keeping — it is what droid.asm will need, and it
\ is the same arithmetic DeadZone does for the player, minus the dead
\ zone itself.
\
\ Delete this file and TEST_DROIDS together once droids move.
\
\ The room: TD_DECK spawns the player in a 40 x 15 character view that
\ is 544/600 open, the most open spawn of any deck — measured off the
\ level data rather than picked by eye, so six droids can stand around
\ the player without any of them inside a wall.

TD_COUNT = SPR_SLOTS - 1        \ slot 0 is the player; the rest are ours

\ Offsets from the player's own spawn position, in world pixels. Chosen
\ to spread across the visible window: the player sits at screen Y 50
\ and somewhere near the middle in X, so ±40 in Y lands at screen rows
\ 10 and 90 (the sprite is 21 tall, and the cull limit is 99) and ±120
\ in X keeps every one of them inside the 320 px width.
.tdDXlo EQUB LO(-120), LO(-60), LO(60), LO(120), LO(-90), LO(90)
.tdDXhi EQUB HI(-120), HI(-60), HI(60), HI(120), HI(-90), HI(90)
.tdDYlo EQUB LO(-40), LO(40), LO(-40), LO(40), 0, 0
.tdDYhi EQUB HI(-40), HI(40), HI(-40), HI(40), 0, 0

\ ============================================================
\ TestDroidsInit — pin six droids around wherever the player landed
\ ============================================================
\ Called from LoadDeck once the pixel position is settled. Relative to
\ the player rather than absolute, so changing deck with UP/DOWN still
\ puts the six somewhere sensible instead of off the map.
.TestDroidsInit
  CLC                           \ the player's own world Y: the view top
  LDA posY   : ADC #PLY_Y : STA tdTmp
  LDA posY+1 : ADC #0     : STA tdTmp+1

  LDX #TD_COUNT-1
.tdi_loop
  CLC
  LDA plyX      : ADC tdDXlo,X : STA tdXlo,X
  LDA plyX+1    : ADC tdDXhi,X : STA tdXhi,X
  CLC
  LDA tdTmp     : ADC tdDYlo,X : STA tdYlo,X
  LDA tdTmp+1   : ADC tdDYhi,X : STA tdYhi,X

  LDY deck                      \ a different number on each, so the
  LDA deckDroidBase,Y           \ digit glyphs get exercised too
  STA tdTmp2
  TXA
  CLC
  ADC tdTmp2
  CMP #DR_TYPES
  BCC tdi_type
  SBC #DR_TYPES
.tdi_type
  STA sprType+1,X

  TXA                           \ stagger the rotors, or six droids spin
  AND #7                        \ in lockstep and it reads as one object
  STA sprFrame+1,X

  DEX
  BPL tdi_loop
  RTS

\ ============================================================
\ TestDroidsUpdate — world position through the view, once a frame
\ ============================================================
\ Runs after the view has settled and before the sprites are drawn.
\ Anything that does not land wholly on screen has its slot cleared;
\ SprSetSlot culls again on its own limits, so this only has to keep
\ the arithmetic in range.
\
\ sx is 16-bit because the map is 2048 px wide, and the halving is
\ done 16-bit for the same reason DeadZone does it — sx reaches 296 at
\ the right-hand edge. After the shift everything fits in a byte.
.TestDroidsUpdate
  LDX #TD_COUNT-1
.tdu_loop
  STX tdIdx

  SEC                           \ screen Y first: it is one subtract, and
  LDA tdYlo,X : SBC posY   : STA tdSy    \ it rejects most of the deck
  LDA tdYhi,X : SBC posY+1
  BNE tdu_off                   \ non-zero high byte: above, or past 255

  LDX tdIdx
  SEC
  LDA tdXlo,X : SBC posX   : STA tdSx
  LDA tdXhi,X : SBC posX+1 : STA tdSx+1
  BMI tdu_off                   \ left of the view
  CMP #2
  BCS tdu_off                   \ 512 px right of it: nowhere near

  LSR A                         \ (sx >> 1), 0-255 — the 2 px unit
  LDA tdSx
  ROR A
  STA tdTmp
  AND #1
  LDX tdIdx
  STA sprShift+1,X              \ odd 2 px step: the shifted code
  LDA tdTmp
  LSR A
  STA sprUnit+1,X
  LDA tdSy
  STA sprScrY+1,X
  LDA #1
  STA sprActive+1,X
  JMP tdu_next

.tdu_off
  LDX tdIdx
  LDA #0
  STA sprActive+1,X

.tdu_next
  LDX tdIdx
  DEX
  BPL tdu_loop
  RTS

.tdXlo  SKIP TD_COUNT
.tdXhi  SKIP TD_COUNT
.tdYlo  SKIP TD_COUNT
.tdYhi  SKIP TD_COUNT
.tdSx   EQUW 0
.tdSy   EQUB 0
.tdIdx  EQUB 0
.tdTmp  EQUW 0
.tdTmp2 EQUB 0
