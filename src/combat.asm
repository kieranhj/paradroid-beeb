\ ============================================================
\ combat.asm — the player's own combat state: energy, score, alert
\ ============================================================
\ LAYER 7a. Main RAM, deliberately: everything here is read or written
\ from BOTH sides of the bank split. droid.asm (bank 4) pays the
\ deck-cleared bonus through AddScore, and the fire code to come is in
\ main RAM. Bank code may call main RAM freely — the rule is one-way,
\ and it is stated in bufcore.asm's header — so main RAM is the only
\ home that works for both. Nothing here reads the play buffer.
\
\ ---- entry 0 of the droid table IS THE PLAYER ---------------
\ droid.asm's header calls entry 0 a sentinel, which is true of
\ everything Layers 5 and 6 do: DroidsUpdate starts at index 1 and its
\ deck-cleared test is `CMP #2` on the count, the C64's `CPY #1`. But
\ the original reads droidEnergy, droidType and droidFireDelay
\ UNINDEXED all through the combat code, and unindexed is index 0 —
\ that is the player's energy, the player's type and the player's fire
\ delay. BlowInto001 ($1573) writes exactly those three.
\
\ So from this layer on, entry 0 is real:
\
\   drType[0]       the droid the player is currently riding, 0 = 001
\   drEnergy[0]     his energy, 0-maxEnergy
\   drFireDelay[0]  counts down between shots
\
\ and DroidsInit no longer clears them on a deck change. Nothing
\ iterates over index 0 — di_loop, dru_loop and the compaction all stop
\ above it — so making it live costs nothing anywhere else.
\
\ ---- what ages, and why it is not the same as damage --------
\ maxEnergy is the CEILING and it only ever falls. DoAlertAndAging
\ ($3E32) takes one off it on a period set by the droid's class, so the
\ droid you are riding wears out whether or not anything shoots at you,
\ and a recharge pad can only fill you to what is left. That is the
\ clock the whole game runs against: you transfer upward because the
\ droid you are in is dying.
\
\ THE PERIODS ARE PER GAME-LOOP ITERATION, NOT PER FRAME. The C64's
\ frameCount is bumped once per iteration and an iteration is 2 fields
\ here as it is there, so gameTick is the same clock and the masks
\ transfer unchanged. Read the speed-model section of
\ docs/layer-4-player.md before assuming that of any other constant.
\ ============================================================

\ Full energy at the start of a life, and the ceiling a fresh droid
\ gets: $40, from StartGame ($1345) and xferInitDroid ($2245). It is
\ the same number as droid.asm's DR_ENERGY, from the same place —
\ asserted there, because beebasm resolves constants in file order and
\ droid.asm is included after this file.
CB_ENERGY_FULL = &40

\ ============================================================
\ CombatInit — the player's state at the start of a game
\ ============================================================
\ StartGame ($1345) puts both energy and its ceiling at $40 and drops
\ the player into droid 001. Called once at boot, after NewShipDroids
\ and before the first LoadDeck, so DroidsInit's placement runs over a
\ table whose entry 0 is already the player's.
.CombatInit
  LDA #0
  STA drType                    \ droid 001 — the influence device's
  STA drFireDelay               \ weakest host
  STA alertLvl
  STA scoreAdd
  STA scoreSub
  STA score+0
  STA score+1
  STA score+2
  STA score+3
  STA gameTick

  LDA #CB_ENERGY_FULL
  STA drEnergy
  STA maxEnergy

  LDY drType                    \ the weapon comes with the droid, as
  LDA drWeapon,Y                \ xferInitDroid ($224C) takes it
  STA weaponType
  RTS

\ ============================================================
\ AddScore — port of AddScore ($3E94)
\ ============================================================
\ A = points to add. Four-byte BCD, and a DIRECT port: SED and CLD
\ behave identically on this 6502, which ANNOTATION.md listed as a
\ no-change candidate and it is.
\
\ THE ACCUMULATOR IS NOT A FRACTION OF A POINT. scoreAdd banks raw
\ points until they carry past 256, and the carry credits 255 to the
\ score and pushes the odd 1 back into the accumulator with the INC.
\ It looks like an off-by-one and is not: 255 out and 1 retained is
\ exactly the 256 that came in.
\
\ CLD AND INC BOTH LEAVE CARRY ALONE, which is what makes the second
\ BCC work — it is testing the carry out of the TOP BCD digit, four
\ instructions earlier, and saturating the score at 99999999 rather
\ than letting it wrap. Reordering those two instructions breaks it
\ silently and only after about half an hour of play.
.AddScore
  CLC
  ADC scoreAdd
  STA scoreAdd
  BCC as_x
  SED
  LDA score+3 : ADC #&54 : STA score+3
  LDA score+2 : ADC #&02 : STA score+2
  LDA score+1 : ADC #&00 : STA score+1
  LDA score+0 : ADC #&00 : STA score+0
  CLD
  INC scoreAdd
  BCC as_x
  LDA #&99
  STA score+0
  STA score+1
  STA score+2
  STA score+3
.as_x
  RTS

\ ============================================================
\ SubScore — port of SubScore ($3EC4)
\ ============================================================
\ A = points to take away. AddScore's mirror, down to the accumulator
\ trick and the saturate: its own scoreSub banks the debits, a wrap past
\ 256 takes 255 off the BCD score and pushes 1 back, and a borrow out of
\ the top digit floors the score at zero rather than letting it wrap to
\ 99999999.
\
\ The score is a RESOURCE in this game and not just a tally, which is
\ what this routine is for — the recharge pad below is the one thing
\ that spends it.
.SubScore
  CLC
  ADC scoreSub
  STA scoreSub
  BCC ss_x
  SED
  LDA score+3 : SBC #&55 : STA score+3
  LDA score+2 : SBC #&02 : STA score+2
  LDA score+1 : SBC #&00 : STA score+1
  LDA score+0 : SBC #&00 : STA score+0
  CLD
  INC scoreSub
  BCS ss_x                      \ no borrow: the score stood up to it
  LDA #0
  STA score+0
  STA score+1
  STA score+2
  STA score+3
.ss_x
  RTS

\ ============================================================
\ DoCharUnder — port of DoCharUnder ($2E7B), recharger arm
\ ============================================================
\ LAYER 7b. A dispatch on the CHARACTER the player is standing on — not
\ the tile. The original tests four things and this builds one of them:
\
\   char 20     RECHARGER. Built here.
\   chars 43-46 lift. NOT ported: the C64 gates this on moveMode, which
\               is to say on the fire button, and lift.asm already
\               enters a lift on the fire key. See docs/layer-7-combat.md
\   char 66     console. Layer 9, along with the consoleState countdown
\               that both of those arms need and this one does not.
\
\ CHARACTER 20 IS UNIQUELY THE RECHARGER, checked offline: &14 occurs
\ exactly once in all 32 tile definitions, as the 2x2 CENTRE of tile 20,
\ and level_stats.txt puts that tile on the 12 decks docs/graphics.md
\ claims. Being the centre of a 4x4-character tile is what stops a
\ four-iteration countdown triggering as you clip the corner of one: you
\ have to stand on the pad.
\
\ ENERGY IS NOT FREE. Each point costs 5 off the score, which is the
\ original's own rate and the reason SubScore exists at all.
\
\ CALLS INTO BANK 4. MapChar lives in screen.asm and main RAM may call
\ in only with SWRAM_DATA paged — true here, because this runs from the
\ main loop where the data bank is the resting state, and door.asm's
\ DoorScan already calls MapChar exactly this way from main RAM.
\
\ plyCX/plyCY are the player's reference cell, left by CheckWalls
\ earlier in the pass. plyCX is 16-bit and its high byte is dropped, as
\ DoorScan drops it: the map is 256 characters across.
CHAR_RECHARGE = 20

.DoCharUnder
  LDA plyCX : STA cellX
  LDA #0    : STA cellX+1
  LDA plyCY : STA cellY
  JSR MapChar
  CMP #CHAR_RECHARGE
  BNE dcu_x

  LDA gameTick                  \ one point every 4th iteration
  AND #3
  BNE dcu_x
  LDA drEnergy
  CMP maxEnergy                 \ the ceiling holds, and it is a ceiling
  BCS dcu_x                     \ that DoAging is still lowering
  INC drEnergy
  LDA #5
  JMP SubScore
.dcu_x
  RTS

\ ============================================================
\ DoAging — port of DoAlertAndAging ($3E32)
\ ============================================================
\ Two unrelated clocks that the original runs off the same counter:
\
\   every 16 iterations   the alert level decays by one, and the level
\                         it decays THROUGH pays out drAlertScore
\   every drAgingMask+1   maxEnergy loses one, and energy follows it
\                         down if it was sitting at the ceiling
\
\ The mask is indexed by the droid's CLASS, not its type: drCent is the
\ hundreds digit of the droid number, so it rises with how dangerous
\ the droid is, and $7F for a 001 against $0F for a 999 means a better
\ droid burns out eight times faster. That is the game's whole economy.
\
\ Called once a pass from the main loop, after the drawing, beside
\ DroidsUpdate — it writes nothing into the play buffer.
\
\ The C64's `_5` arm is a background sound cue on the off-16s and is
\ Layer 11's; the alert COLOUR write ($3E4A) is the panel's and is
\ Layer 9's. Neither is here.
.DoAging
  LDA gameTick
  AND #&0F
  BNE da_aging                  \ the alert half runs on 1 iteration in 16

  LDA alertLvl
  BEQ da_level                  \ already clear: score the zero level
  DEC alertLvl
  LDA alertLvl
.da_level
  LSR A : LSR A : LSR A         \ level = Alert >> 6, so 0-3
  LSR A : LSR A : LSR A
  TAX
  LDA drAlertScore,X
  BEQ da_aging
  JSR AddScore

\ The ceiling wears down on its own clock, which is why this is not
\ inside the 1-in-16 arm.
.da_aging
  LDY drType                    \ the player's droid...
  LDX drCent,Y                  \ ...and the class it belongs to
  LDA gameTick
  AND drAgingMask,X
  BNE da_x

  LDA maxEnergy
  BEQ da_floor                  \ nothing left to take: pin energy at 0
  DEC maxEnergy
  LDA maxEnergy
  CMP drEnergy                  \ energy only follows the ceiling down
  BCS da_x                      \ if it was already at or above it
.da_floor
  STA drEnergy
.da_x
  RTS

\ ============================================================
\ DoMoveMode — port of DoMoveMode ($31B9)
\ ============================================================
\ LAYER 7d. Fire does not act on anything directly. It drives a
\ four-state machine, and the state decides what touching a droid means
\ and whether holding the button shoots:
\
\   $80  Mobile     the resting state, fire released
\    1   Weapon     HELD FIRE SHOOTS — DoFire's only caller
\    2   (settling) pressed with no direction; becomes Transfer
\    0   Transfer   touching a droid starts the transfer game
\
\ The strings at $697D/$698A/$6997 are what name them, and Layer 9 will
\ want them in the panel. DoCollision's _ply_droid arm ($1A6A) takes the
\ transfer branch only when moveMode is 0, so Layer 10 inherits this.
\
\ FIREDOWN IS TRUE-MEANS-PRESSED, the opposite of the C64's joyFire.
\ There, CIA port A is active low and `joyFire == 0` means the button is
\ DOWN — read it the other way round and this machine appears to run
\ backwards. The port normalises it at the key read instead, which is
\ why every test below is the inverse of the original's.
MM_MOBILE   = &80
MM_WEAPON   = 1
MM_SETTLE   = 2
MM_TRANSFER = 0
MM_DELAY    = 8                 \ DoMobile ($3835) loads 8

.DoMoveMode
  LDA moveMode
  BEQ mm_transfer
  BMI mm_mobile
  CMP #MM_SETTLE
  BEQ mm_settle

\ ---- Weapon: the trigger is live ---------------------------
  LDA fireDown
  BEQ mm_toMobile
  JMP DoFire

\ ---- Transfer: held for as long as the button is ------------
.mm_transfer
  LDA fireDown
  BNE mm_x
.mm_toMobile
  LDA #MM_MOBILE : STA moveMode
  LDA #MM_DELAY  : STA mmDelay
.mm_x
  RTS

\ ---- Mobile: a press with a direction draws the weapon -----
.mm_mobile
  LDA fireDown
  BEQ mm_x
  LDA joyXDir
  ORA joyYDir
  BEQ mm_toSettle
.mm_toWeapon
  JSR DoFire
  LDA #MM_WEAPON : STA moveMode
  LDA #MM_DELAY  : STA mmDelay
  RTS
.mm_toSettle
  LDA #MM_SETTLE : STA moveMode
  RTS

\ ---- pressed with no direction: settle into Transfer -------
.mm_settle
  LDA joyXDir
  ORA joyYDir
  BNE mm_toWeapon
  DEC mmDelay
  BNE mm_x
  LDA #MM_TRANSFER : STA moveMode
  LDA #MM_DELAY    : STA mmDelay
  RTS

\ ============================================================
\ DoFire — port of DoFire ($33B5)
\ ============================================================
\ The player's bullet is SLOT 7 and is not a droid-table entry: on the
\ C64 it is hardware sprite 0, driven straight out of the VIC registers
\ by MovePlyFire, while the droid pool is 1-6. Ours keeps its world
\ position in plyFireX/Y for the same reason the droids keep theirs —
\ the camera moves independently, so a screen-space bullet would drift.
\ That is also why this needs none of the original's `+ ySpd` fudge at
\ $32EA: the C64 compensates a screen-space position for the scroll,
\ and a world-space one has nothing to compensate.
\
\ ONE BULLET AT A TIME. The C64 tests sprite 0's enable bit ($33BA);
\ ours tests the slot.
.DoFire
  LDA drFireDelay               \ entry 0 is the player's
  BNE df_no
  LDA sprActive+PLY_FIRE_SLOT
  BNE df_no
  LDA joyXDir
  ORA joyYDir
  BEQ df_no                     \ a bullet needs a direction to go in
  LDA weaponType
  CMP #3
  BNE df_go                     \ the disruptor is not a bullet — Layer 7f
.df_no
  RTS
.df_go

\ The direction index, exactly as $33E7 derives it from the pair:
\   0  Y == X, both non-zero   the "\" diagonal
\   1  X == 0                  vertical
\   2  Y and X differ, neither zero   the "/" diagonal
\   3  Y == 0                  horizontal
  LDA weaponType
  ASL A : ASL A
  STA cbTmp
  LDA joyYDir
  BEQ df_d3
  CMP joyXDir
  BEQ df_d0
  LDA joyXDir
  BEQ df_d1
  LDA #2 : BNE df_have          \ always
.df_d0
  LDA #0 : BEQ df_have          \ always
.df_d1
  LDA #1 : BNE df_have          \ always
.df_d3
  LDA #3
.df_have
  CLC
  ADC cbTmp
  TAY

\ efBullet replaces BulletSprite_t and is already resolved to our frame
\ numbering; efAlt gives the frame it animates against, so MovePlyFire
\ can flip between two bytes instead of looking anything up. Both are in
\ BANK 5 with the artwork, so page it in and the data bank back out —
\ once per shot, not per pass.
  PAGEBANK SWRAM_SPR
  LDA efBullet,Y
  STA plyFireF0
  TAY
  LDA efAlt,Y
  STA plyFireF1
  PAGEBANK SWRAM_DATA

\ BulletDisplacement_t ($6E58) is BOTH the spawn offset and the speed:
\ $33FB stores it as plyFireSpdY and then adds it to the position once.
  LDX joyXDir
  INX
  LDA cbDisp,X : STA plyFireDX
  LDX joyYDir
  INX
  LDA cbDisp,X : STA plyFireDY

\ Spawn on the player's own sprite corner, plus that displacement. The
\ player's sprite sits at plyX across and PLY_Y below the view top, so
\ its world Y is posY + PLY_Y.
  LDA plyFireDX : JSR CbSignExt
  CLC
  LDA plyX   : ADC plyFireDX : STA plyFireX
  LDA plyX+1 : ADC cbSgn     : STA plyFireX+1
  CLC
  LDA posY   : ADC #PLY_Y : STA plyFireY
  LDA posY+1 : ADC #0     : STA plyFireY+1
  LDA plyFireDY : JSR CbSignExt
  CLC
  LDA plyFireY   : ADC plyFireDY : STA plyFireY
  LDA plyFireY+1 : ADC cbSgn     : STA plyFireY+1

\ Fired straight into a wall: no bullet, but the delay still applies —
\ $341C does exactly this, so shooting at a wall costs the shot.
  JSR CbFireCell
  JSR MapChar
  BMI df_delay

  LDA #1 : STA sprActive+PLY_FIRE_SLOT
  LDA #1 : STA sprKind+PLY_FIRE_SLOT
  LDA plyFireF0 : STA sprType+PLY_FIRE_SLOT
  JSR CbFirePlace
  BCC df_delay
  LDA #0 : STA sprActive+PLY_FIRE_SLOT   \ spawned off view

\ 32 - 2 * the droid's class: a better droid shoots faster.
.df_delay
  LDY drType
  LDA #32
  SEC : SBC drCent,Y
  SEC : SBC drCent,Y
  STA drFireDelay
.df_x
  RTS

\ ============================================================
\ MovePlyFire — port of MovePlyFire ($32D9)
\ ============================================================
\ One pass of the bullet: move, animate, die on a wall or off the view.
\ Runs before SprSplitOK so the tranche assignment sees this pass's slot
\ state, which is the same reason the movement was moved above the erase.
.MovePlyFire
  LDA sprActive+PLY_FIRE_SLOT
  BEQ mpf_delay

  LDA plyFireDX : JSR CbSignExt
  CLC
  LDA plyFireX   : ADC plyFireDX : STA plyFireX
  LDA plyFireX+1 : ADC cbSgn     : STA plyFireX+1
  LDA plyFireDY : JSR CbSignExt
  CLC
  LDA plyFireY   : ADC plyFireDY : STA plyFireY
  LDA plyFireY+1 : ADC cbSgn     : STA plyFireY+1

\ The flicker at $3344: swap the pair. Frames that do not animate have
\ efAlt pointing back at themselves, so this is a no-op for them and
\ needs no test — which is why the weapon-0 bullets sit still.
  LDA plyFireF0
  LDX plyFireF1
  STX plyFireF0
  STA plyFireF1
  LDA plyFireF0
  STA sprType+PLY_FIRE_SLOT

  JSR CbFireCell                \ SpriteHitWall ($336F)
  JSR MapChar
  BMI mpf_kill
  JSR CbFirePlace
  BCS mpf_kill
  JMP mpf_delay
.mpf_kill
  LDA #0
  STA sprActive+PLY_FIRE_SLOT

\ The countdown runs whether or not a bullet is in the air — $3366.
.mpf_delay
  LDA drFireDelay
  BEQ mpf_x
  DEC drFireDelay
.mpf_x
  RTS

\ ============================================================
\ CbFireCell — the map cell the bullet is over
\ ============================================================
\ The CENTRE of the nominal 24 x 21, not the corner. The C64 tests the
\ sprite's own X/Y less $AC ($336F), which is a hardware-coordinate
\ origin and lands wherever it lands; a bullet's opaque pixels are near
\ the middle of its box, so the middle is what should hit a wall.
CB_FIRE_CX = 12
CB_FIRE_CY = 10

.CbFireCell
  CLC
  LDA plyFireX   : ADC #CB_FIRE_CX : STA cellX
  LDA plyFireX+1 : ADC #0          : STA cellX+1
  LSR cellX+1 : ROR cellX
  LSR cellX+1 : ROR cellX
  LSR cellX+1 : ROR cellX
  CLC
  LDA plyFireY   : ADC #CB_FIRE_CY : STA cbTmpW
  LDA plyFireY+1 : ADC #0          : STA cbTmpW+1
  LSR cbTmpW+1 : ROR cbTmpW
  LSR cbTmpW+1 : ROR cbTmpW
  LSR cbTmpW+1 : ROR cbTmpW
  LDA cbTmpW
  STA cellY
  RTS

\ ============================================================
\ CbFirePlace — world position to slot position; carry set = off view
\ ============================================================
\ The same conversion DrScreen makes for a droid: subtract the view
\ origin, split the pixel into a 4 px CRTC unit and the shift within it.
\ The blitter would cull an off-view bullet anyway, but a culled bullet
\ is still flying — the C64 kills one that leaves the screen ($32F3) and
\ so does this, or the slot never comes free.
.CbFirePlace
  SEC
  LDA plyFireX   : SBC posX   : STA cbSx
  LDA plyFireX+1 : SBC posX+1 : STA cbSx+1
  LDA cbSx+1
  CMP #2
  BCS cbp_off                   \ negative reads as &FFxx, so this catches both

  LDA cbSx
  AND #3
  STA cbShift
  LDA cbSx+1 : STA cbTmp
  LSR cbTmp  : ROR cbSx
  LSR cbTmp  : ROR cbSx
  LDA cbSx
  CMP #SPR_MAX_UNIT+1
  BCS cbp_off

  SEC
  LDA plyFireY   : SBC posY   : STA cbSy
  LDA plyFireY+1 : SBC posY+1 : STA cbSy+1
  BNE cbp_off                   \ off the top reads as &FF, off the bottom > 255
  LDA cbSy
  CMP #SPR_MAX_Y+1
  BCS cbp_off

  LDA cbShift : STA sprShift+PLY_FIRE_SLOT
  LDA cbSx    : STA sprUnit+PLY_FIRE_SLOT
  LDA cbSy    : STA sprScrY+PLY_FIRE_SLOT
  CLC
  RTS
.cbp_off
  SEC
  RTS

\ A = a signed byte; cbSgn becomes its sign extension. A is preserved so
\ the caller can add the pair straight away.
.CbSignExt
  LDX #0
  CMP #&80
  BCC cse_x
  LDX #&FF
.cse_x
  STX cbSgn
  RTS

\ ============================================================
\ state
\ ============================================================
\ The player's, and the ship's. drType/drEnergy/drFireDelay are NOT
\ here — they are entry 0 of the droid table in bank 4, for the reason
\ in the header.
.maxEnergy  EQUB CB_ENERGY_FULL \ the ceiling, which only falls
.weaponType EQUB 0              \ 0 unarmed, 3 the disruptor
.alertLvl   EQUB 0              \ the C64's Alert; the level is bits 6-7
.scoreAdd   EQUB 0              \ points banked below the BCD threshold
.scoreSub   EQUB 0              \ and the same again for debits
.score      SKIP 4              \ 4-byte BCD, most significant first

\ ---- Layer 7d: the fire button and the player's bullet -----
.moveMode   EQUB MM_MOBILE
.mmDelay    EQUB MM_DELAY
.fireDown   EQUB 0              \ TRUE means pressed — see DoMoveMode
.fireEaten  EQUB 0              \ this press belonged to the lift
.lDown      EQUB 0              \ the key itself, read once a pass

.plyFireX   EQUW 0              \ the bullet's world position: its sprite's
.plyFireY   EQUW 0              \ top-left corner, as the C64 keeps it
.plyFireDX  EQUB 0              \ signed pixels a pass, and the spawn offset
.plyFireDY  EQUB 0
.plyFireF0  EQUB 0              \ the frame drawn, and the one it flickers
.plyFireF1  EQUB 0              \ against; equal when it does not animate

\ BulletDisplacement_t ($6E58), indexed by direction + 1.
.cbDisp     EQUB &F4, &00, &0C

.cbSx       EQUW 0
.cbSy       EQUW 0
.cbShift    EQUB 0
.cbSgn      EQUB 0
.cbTmp      EQUB 0
.cbTmpW     EQUW 0
