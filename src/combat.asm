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
\ state
\ ============================================================
\ The player's, and the ship's. drType/drEnergy/drFireDelay are NOT
\ here — they are entry 0 of the droid table in bank 4, for the reason
\ in the header.
.maxEnergy  EQUB CB_ENERGY_FULL \ the ceiling, which only falls
.weaponType EQUB 0              \ 0 unarmed, 3 the disruptor
.alertLvl   EQUB 0              \ the C64's Alert; the level is bits 6-7
.scoreAdd   EQUB 0              \ points banked below the BCD threshold
.score      SKIP 4              \ 4-byte BCD, most significant first
