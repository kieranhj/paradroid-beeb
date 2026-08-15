\ ============================================================
\ droid.asm — the deck's droids: roster, waypoints, movement
\ ============================================================
\ ASSEMBLES INTO SWRAM BANK 4, not main RAM — it is included from
\ inside the PARADAT block, beside the waypoints, speeds and deck
\ data it reads and next to MapChar, which it calls on every wall
\ probe. The rule that makes that safe is in bufcore.asm's header:
\ bank code may call main RAM freely (this file calls DoorProbe and
\ writes sprite.asm's slot arrays), and main RAM may call in only
\ while SWRAM_DATA is paged. All four entry points satisfy that —
\ NewShipDroids and DroidsInit/DrSpawnPoint from startup and
\ LoadDeck, DroidsUpdate from the main loop, all with the data bank
\ as the resting state.
\ ============================================================
\ Layer 5 proper, replacing droidtest.asm. Ported from the C64:
\
\   NextLevel        $15E8  builds the SHIP's droid roster
\   InitDeckDroids   $1664  places this deck's droids on waypoints
\   GetWaypoints     $1700  / FindWaypoint $170D
\   RunDroids        $174B  the driver and its compaction loop
\   dMd0_droid       $18CA  one droid's pass
\   MoveDroid        $1987
\   GetNewDir        $1CAD  pick an exit from a waypoint's mask
\   AdvanceMapPos    $1D0D  / CheckDroidAdvance $1D30
\   Regenerate       $1D45
\   DroidNear        $321E  / FindFreeSprite $32A8
\
\ THE TABLE IS INDEXED 1-13 AND ENTRY 0 IS THE PLAYER. Every loop here
\ stops above it — di_loop, dru_loop and the compaction all end on a
\ BNE — which is the C64's arrangement and the reason RunDroids' "deck
\ cleared" test is `CPY #1` rather than a test for zero. Keeping it
\ means the compaction loop ports across unchanged.
\
\ Up to Layer 6 entry 0 was empty and this header called it a sentinel.
\ It never was one: the original reads droidType, droidEnergy and
\ droidFireDelay UNINDEXED throughout the combat code, and unindexed is
\ index 0. Layer 7a made it live — see combat.asm's header — so nothing
\ may clear it on a deck change.
\
\ A DROID'S POSITION IS ITS REFERENCE CELL, not its top-left pixel.
\ drPosX/drPosY are world pixels, and the map cell the droid occupies
\ is (drPosX >> 3, drPosY >> 3) — which is what lets FindWaypoint
\ compare against the waypoint's own character coordinates with no
\ arithmetic at all, exactly as the original does. The sprite is drawn
\ at
\
\   left = drPosX - PLY_REFX   (11)      top = drPosY - DR_REFY  (13)
\
\ so a droid sits on the same part of its sprite as the player sits on
\ his — see the reference-cell note in player.asm. The C64 offsets by
\ 12 for the same reason: the cell over the digit block is the middle
\ of the droid.
\
\ WAYPOINTS ARE TILE CENTRES. A record is (charX, charY, exit mask)
\ and the char coordinates are always 2 mod 4, so pixel position mod 32
\ is 16 on both axes — which is exactly the test dMd0 makes before it
\ bothers to search:
\
\   (drPosXlo OR drPosYlo) AND $1F == $10
\
\ Every droid speed (1, 2, 4, 8) divides 16, so a droid walking a
\ corridor cannot step over a waypoint without landing on it.
\
\ THE ONE DELIBERATE SUBSTITUTION IS THE RANDOM SOURCE. The C64 reads
\ SID register $D41B — oscillator 3's noise output, free-running — in
\ NextLevel and again in GetNewDir. There is no equivalent on this
\ machine, so DrRandom is an 8-bit maximal LFSR. It never returns 0,
\ which matters nowhere: both callers mask it to 2 or 4 bits.
\ ============================================================

\ Set FALSE to freeze the pool where it spawns — placement and slot
\ allocation without any movement, which is how this file was brought
\ up. Everything else still runs.
DR_MOVES = TRUE

DR_SLOTS  = 14                  \ index 1-13; 0 is the sentinel
DR_REFY   = 13                  \ reference cell below the sprite top
DR_NEAR_X = SPR_MAX_UNIT * 4 + 3    \ furthest left edge that still draws
DR_ENERGY = &40                 \ a droid's full energy, from $16AA
ASSERT DR_ENERGY == CB_ENERGY_FULL  \ the player's is the same number,
                                    \ from StartGame ($1345). combat.asm
                                    \ declares it because it is included
                                    \ first and beebasm is single-pass on
                                    \ constant assignments
DR_999    = 23                  \ the influence device

\ The collision box, in screen pixels. Smaller than the 24 x 21 sprite
\ on purpose — see DrCollide. Tune by eye.
DR_COL_W  = 18
DR_COL_H  = 14

\ Steps the sight line will walk before giving up and calling it clear.
\ The window is 40 characters across and 15 down, and the scaled step
\ covers at least half a character, so 96 is well past the diagonal.
DR_LOS_MAX = 96

\ The C64 places droids from waypoint 1 upward, one record per table
\ index whether or not that index holds a droid, so droid 13 gets
\ waypoint 1 and droid 1 gets waypoint 13. At most twelve are ever
\ placed — the roster fills indices 12 down to 1 — so the walk wants
\ waypoints 1-13 at worst. Checked deck by deck against deckDroids and
\ wpCount before relying on it: the tightest is deck 2, 5 waypoints
\ against 3 droids, which reaches waypoint 4.

\ ============================================================
\ DrRandom — 8-bit LFSR, standing in for SID $D41B
\ ============================================================
.DrRandom
  LDA drSeed
  ASL A
  BCC drr_x
  EOR #&1D                      \ x^8 + x^4 + x^3 + x^2 + 1, maximal
.drr_x
  STA drSeed
  RTS

\ ============================================================
\ NewShipDroids — port of NextLevel ($15E8)
\ ============================================================
\ The ship's whole complement, 16 bytes a deck, generated rather than
\ shipped: deckDroidBase[deck] + shipLevel sets the class of droid a
\ deck gets, and the roster is filled from index 12 downwards.
\
\ The two halves of the fill are not the same rule, and the difference
\ is the difficulty curve:
\
\   indices 12-6   base + rnd AND 3      the deck's own droids
\   indices 5-1    a random type BELOW base+3, found by halving a
\                  4-bit random until it fits — so the tail of the
\                  roster is weaker, and weighted low
\
\ A deck gets deckDroids-1 of them. Deck 1 index 13 is then set to type
\ 23, droid 999, the influence device: the one fixed entry in the
\ table.
.NewShipDroids
  LDA #0
  TAY
.nsd_clear
  STA shipDroids,Y              \ Y = 0 first, then 255 down to 1
  DEY
  BNE nsd_clear

  LDA #1
  STA shipNumDroids

  LDA #LO(shipDroids + 15 * 16) \ decks are filled 15 down to 0
  STA mapptr
  LDA #HI(shipDroids + 15 * 16)
  STA mapptr+1

  LDX #15
.nsd_deck
  STX nsdDeck
  CLC
  LDA deckDroidBase,X
  ADC shipLevel
  CMP #20
  BCC nsd_base
  LDA #19
.nsd_base
  STA nsdBase

  LDA deckDroids,X
  SEC
  SBC #1
  STA nsdLeft
  BEQ nsd_next

  LDY #12
.nsd_strong
  JSR DrRandom
  AND #3
  CLC
  ADC nsdBase
  STA (mapptr),Y
  INC shipNumDroids
  DEC nsdLeft
  BEQ nsd_next
  DEY
  CPY #6
  BCS nsd_strong

  CLC                           \ the weak half is drawn from below
  LDA nsdBase                   \ base + 3
  ADC #3
  STA nsdBase

.nsd_weak
  JSR DrRandom
  AND #&0F
.nsd_halve
  LSR A
  BEQ nsd_none                  \ halved away to nothing: leave it empty
  CMP nsdBase
  BCS nsd_halve
  STA (mapptr),Y
  INC shipNumDroids
.nsd_none
  DEC nsdLeft
  BEQ nsd_next
  DEY
  BNE nsd_weak

.nsd_next
  SEC
  LDA mapptr
  SBC #16
  STA mapptr
  BCS nsd_nohi
  DEC mapptr+1
.nsd_nohi
  LDX nsdDeck
  DEX
  BPL nsd_deck

  LDA #DR_999                   \ 999 on deck 1: the one fixed entry
  STA shipDroids + &1D
  RTS

\ ============================================================
\ DroidsInit — port of InitDeckDroids ($1664)
\ ============================================================
\ Called from LoadDeck. Fills the deck table from the ship roster and
\ stands each droid on a waypoint.
\
\ drCount is left at DR_SLOTS rather than at the number placed: the
\ table has holes in it, and DroidsUpdate's compaction squeezes them
\ out on its first run because a hole has zero energy. That is how the
\ original arrives at its own numDeckDroids too.
.DroidsInit
  JSR DrWaypoints               \ src -> waypoint 0, the player's spawn,
  ADDPTR src, 3                 \ so the droids start at waypoint 1

  LDA deck                      \ this deck's row of the ship roster
  ASL A : ASL A : ASL A : ASL A
  STA drDeckBase
  CLC
  ADC #LO(shipDroids)
  STA mapptr
  LDA #0
  ADC #HI(shipDroids)
  STA mapptr+1

  LDY #DR_SLOTS-1
.di_loop
  STY diIdx
  LDA (mapptr),Y
  BNE di_place

\ NO DROID AT THIS INDEX, AND THE ENTRY HAS TO BE EMPTIED RATHER THAN
\ SKIPPED. It holds the LAST deck's droid — its type, its energy and,
\ fatally, its position — and `drCount` is set to the whole table below
\ on the assumption that a hole has zero energy so the compaction drops
\ it. Leave the energy alone and the hole is a live droid standing at
\ the previous deck's coordinates inside this deck's walls.
\
\ It survives a cold boot because the table starts zeroed, so the first
\ deck entered is always clean and only the second one shows it.
  LDA #0
  STA drEnergy,Y
  STA drType,Y
  STA drSprNum,Y
  BEQ di_next                   \ always
.di_place

  STA drType,Y
  TYA
  CLC
  ADC drDeckBase                \ where it lives in the ship roster, so
  STA drShipIdx,Y               \ killing it removes it from the SHIP
  LDA #DR_ENERGY : STA drEnergy,Y
  LDA #0
  STA drSprNum,Y
  STA drVis,Y
  STA drVisNew,Y
  STA drSpdX,Y
  STA drSpdY,Y
  STA drState,Y
  STA drFireDelay,Y

  LDY #0                        \ the waypoint under src: char -> pixels
  LDA (src),Y
  JSR DrCharToPix
  LDY diIdx
  LDA dcpLo : STA drPosXlo,Y
  LDA dcpHi : STA drPosXhi,Y

  LDY #1
  LDA (src),Y
  JSR DrCharToPix
  LDY diIdx
  LDA dcpLo : STA drPosYlo,Y
  LDA dcpHi : STA drPosYhi,Y

.di_next
  ADDPTR src, 3                 \ one record per INDEX, occupied or not
  LDY diIdx
  DEY
  BNE di_loop

  LDA #DR_SLOTS
  STA drCount
  LDA #0
\ ENTRY 0 IS THE PLAYER FROM LAYER 7a ON, and this used to clear it —
\ "the sentinel is always empty". It is not a sentinel: drType[0] is the
\ droid the player is riding and drEnergy[0] is his energy, and clearing
\ them here would reset both on every deck change and lift ride. Only
\ drSprNum is still cleared, because the player's sprite is slot 0 and
\ the droid table's copy of it is unused. See combat.asm's header.
  STA drSprNum
  STA drTick
  LDX #SPR_SLOTS-1              \ nothing holds a sprite slot yet
.di_free
  STA sprActive,X
  STA drSlotOwner,X
  DEX
  BNE di_free                   \ slot 0 is the player's; leave it
  STA drSlotOwner               \ but nothing owns it in the droid sense
  RTS

\ ============================================================
\ DrCharToPix — A = character coordinate, dcpLo/Hi = world pixels
\ ============================================================
.DrCharToPix
  STA dcpLo
  LDA #0
  STA dcpHi
  ASL dcpLo : ROL dcpHi
  ASL dcpLo : ROL dcpHi
  ASL dcpLo : ROL dcpHi
  RTS

\ ============================================================
\ DrWaypoints — src = this deck's waypoint records
\ ============================================================
\ Port of GetWaypoints ($1700). The offsets are in BYTES, not records.
.DrWaypoints
  LDY deck
  CLC
  LDA wpOfsLo,Y : ADC #LO(wpData) : STA src
  LDA wpOfsHi,Y : ADC #HI(wpData) : STA src+1
  RTS

\ ============================================================
\ DrSpawnPoint — the player's spawn: waypoint 0 of this deck
\ ============================================================
\ Waypoint 0 is never used by InitDeckDroids, which starts placing at
\ waypoint 1; tools/export_droids.py says plainly what it is for and
\ asserts every deck has one. Waypoints are walkable by construction —
\ droids patrol between them — which is what makes this a fix for
\ BUGS.md #4 rather than another guess at a safe cell.
\
\ Returns the character coordinates in cellX / cellY.
.DrSpawnPoint
  JSR DrWaypoints
  LDY #0
  LDA (src),Y : STA cellX
  LDA #0      : STA cellX+1
  LDY #1
  LDA (src),Y : STA cellY
  RTS

\ ============================================================
\ DroidsUpdate — port of RunDroids ($174B)
\ ============================================================
\ One pass over the table. X walks the source and Y the destination,
\ so a droid whose energy has reached zero is not copied down and the
\ table closes over it. drCount ends as the new high-water mark, and 1
\ means the deck is clear.
\
\ Runs BEFORE DoRedraws, which is not where the scaffolding it
\ replaces sat. Two reasons: a droid opening a door must have probed it
\ before DoorsUpdate closes whatever nothing touched this pass, and the
\ view has settled by then, so the screen positions computed here are
\ the ones the draw will use.
\
\ The view origin plus the reference offsets is a constant across the
\ whole pass, so it is formed once here rather than thirteen times in
\ DrScreen.
.DroidsUpdate
  INC drTick
  CLC
  LDA posX   : ADC #PLY_REFX : STA drOrgX
  LDA posX+1 : ADC #0        : STA drOrgX+1
  CLC
  LDA posY   : ADC #DR_REFY  : STA drOrgY
  LDA posY+1 : ADC #0        : STA drOrgY+1

  LDX losTurn                   \ whose sight line gets tested this pass
  INX
  CPX #SPR_POOL_LAST+1          \ the droid pool only — slot 7 is the bullet
  BCC dru_turn
  LDX #1
.dru_turn
  STX losTurn

  LDA drCount
  CMP #2
  BCS dru_go
  RTS                           \ nothing left on this deck
.dru_go
  LDX #1
  LDY #1
.dru_loop
  STX drIdx
  STY drDst
  LDA drEnergy,X
  BEQ dru_skip

  JSR DroidRun

  LDX drIdx
  LDY drDst
  CPX drDst
  BEQ dru_kept
  LDA drType,X      : STA drType,Y
  LDA drSprNum,X    : STA drSprNum,Y
  LDA drEnergy,X    : STA drEnergy,Y
  LDA drSpdX,X      : STA drSpdX,Y
  LDA drSpdY,X      : STA drSpdY,Y
  LDA drFireDelay,X : STA drFireDelay,Y
  LDA drPosXlo,X    : STA drPosXlo,Y
  LDA drPosXhi,X    : STA drPosXhi,Y
  LDA drPosYlo,X    : STA drPosYlo,Y
  LDA drPosYhi,X    : STA drPosYhi,Y
  LDA drState,X     : STA drState,Y
  LDA drShipIdx,X   : STA drShipIdx,Y
  LDA drVis,X       : STA drVis,Y
  LDA drVisNew,X    : STA drVisNew,Y

  LDA drSprNum,X                \ the slot points back at the droid, so a
  BEQ dru_kept                  \ droid that moves down the table has to
  STX drTmp                     \ tell its slot where it went
  TAX
  TYA
  STA drSlotOwner,X
  LDX drTmp
.dru_kept
  INY
.dru_skip
  LDX drIdx
  INX
  CPX drCount
  BCS dru_done
  JMP dru_loop                  \ the copy-down block grew past a branch
.dru_done
  STY drCount
  JMP DrCollide

\ ============================================================
\ DrCollide — port of DoCollision ($19EA) and DoCollision2, movement half
\ ============================================================
\ THE C64 READS A REGISTER FOR THIS. `SprSprCollision` ($D01E) is the
\ VIC's sprite-to-sprite collision latch: hardware, pixel-exact, and
\ free. We have neither the hardware nor the pixels — a software
\ blitter knows what it wrote, not what it overlapped — so this is the
\ one place in the droid work with no faithful port available, and a
\ box test is what replaces it.
\
\ The box is DELIBERATELY SMALLER THAN THE SPRITE. A droid is 24 x 21,
\ but most of the corners are the rotor's transparent gaps, so a full
\ 24 x 21 box collides where the VIC would not — droids bouncing off
\ each other with clear space between them. DR_COL_W/H are a judgement
\ about where two droids look like they have touched, and they are
\ meant to be tuned by eye.
\
\ ONE PAIR A PASS, which is not a shortcut: DoCollision picks the two
\ lowest set bits out of the register and handles that pair alone.
\
\ WHAT HAPPENS, from DoCollision2's table ($6D6D, entry 08 = "reverse
\ dir") and the _ply_droid arm of DoCollision:
\
\   droid v droid    the first reverses, the second pauses 16 iterations
\   player v droid   the droid pauses 16 AND reverses; the player's own
\                    speed is negated and doubled — the bounce
\
\ Damage, scoring, Alert and the transfer game all hang off the same
\ two arms in the original and are Layer 7's; this is the movement half
\ on its own.
\
\ Only DRAWN slots take part, which falls out of the C64 using a
\ display register: a droid hidden behind a wall has no sprite lit and
\ cannot collide with anything.
.DrCollide
  LDA drCollHit                 \ the debounce, from byte_0_6C: one reverse
  STA drCollWas                 \ per episode, not one per pass
  LDA #0
  STA drCollHit

  LDA #0
  STA dcOuter
.dc_outer
  LDX dcOuter
  LDA sprActive,X
  BEQ dc_onext
  JSR DrSlotXY
  LDA dcX : STA dcX2
  LDA dcY : STA dcY2

  LDY #SPR_SLOTS-1
.dc_inner
  CPY dcOuter
  BEQ dc_inext
  BCC dc_inext                  \ each pair once: only Y above X
  LDA sprActive,Y
  BEQ dc_inext
  STY dcInner
  TYA : TAX
  JSR DrSlotXY

  LDA dcX                       \ |dx| < DR_COL_W ?
  SEC
  SBC dcX2
  JSR DrAbsA
  CMP #DR_COL_W
  BCS dc_inext2
  LDA dcY
  SEC
  SBC dcY2
  JSR DrAbsA
  CMP #DR_COL_H
  BCS dc_inext2

  JMP DrCollided                \ one pair a pass, as the original does

.dc_inext2
  LDY dcInner
.dc_inext
  DEY
  BNE dc_inner
.dc_onext
  LDX dcOuter
  INX
  STX dcOuter
  CPX #SPR_SLOTS-1
  BCC dc_outer
  RTS

\ dcOuter and dcInner are the two slots; act on the droids behind them.
.DrCollided
  LDA #&FF
  STA drCollHit                 \ something touched: hold the debounce

  LDA dcOuter                   \ slot 0 is the player, and the pairs are
  BEQ dc_player                 \ ordered so he can only be the outer one

  LDY dcOuter                   \ droid v droid: the first reverses...
  LDA drSlotOwner,Y
  BEQ dc_x
  TAX
  JSR DrReverse
  LDY dcInner                   \ ...and the second stands still
  LDA drSlotOwner,Y
  BEQ dc_x
  TAX
  JMP DrPause16

\ ---- the player has walked into a droid ---------------------
.dc_player
  LDY dcInner
  LDA drSlotOwner,Y
  BEQ dc_x
  TAX
  JSR DrPause16
  JSR DrReverse

  LDA drCollWas                 \ the bounce is once per episode too, or
  BNE dc_x                      \ the player sticks to the droid shaking

  LDX #0                        \ the C64 negates the whole-pixel part of
  JSR DrBounce                  \ each speed, forces it to at least 1, and
  LDX #2                        \ doubles it
  JSR DrBounce
.dc_x
  RTS

\ X = 0 for xSpd, 2 for ySpd.
\
\ THE DOUBLING IS CLAMPED HERE AND IS NOT ON THE C64. Ours brings in
\ one character row per pass and no more — the ASSERT on PLY_MAXSPD in
\ player.asm — so a bounce that doubled 8 px/pass into 16 would skip a
\ row, leave a stale one in the strip, and show it later as a band of
\ the wrong deck. The C64 scrolls a pixel at a time and has no such
\ ceiling.
.DrBounce
  LDA xSpd+1,X
  EOR #&FF
  CLC
  ADC #1                        \ negated
  BNE db_nz
  LDA #1                        \ standing still: bounce anyway, as $1A8E
.db_nz
  BMI db_neg

  ASL A                         \ positive: double, then clamp
  BCS db_posmax
  CMP #CAM_TOPSPD+1
  BCC db_store
.db_posmax
  LDA #CAM_TOPSPD
  BNE db_store                  \ always

.db_neg
  EOR #&FF                      \ negative: double the magnitude instead,
  CLC                           \ so the clamp has something to compare
  ADC #1
  ASL A
  BCS db_negmax
  CMP #CAM_TOPSPD+1
  BCC db_negok
.db_negmax
  LDA #CAM_TOPSPD
.db_negok
  EOR #&FF
  CLC
  ADC #1
.db_store
  STA xSpd+1,X
  RTS

\ X = the droid index.
.DrPause16
  LDA #16                       \ PauseDroidFor16 ($1C39)
  STA drState,X
  RTS

\ ReverseDroidDir ($1C5F), without its own debounce — DrCollide holds
\ that for both arms.
.DrReverse
  SEC
  LDA #0 : SBC drSpdX,X : STA drSpdX,X
  SEC
  LDA #0 : SBC drSpdY,X : STA drSpdY,X
  RTS

\ Screen position of slot X, in pixels: the unit is 4 px and the shift
\ is the pixel within it, which is exactly how the blitter took them
\ apart.
.DrSlotXY
  LDA sprUnit,X
  ASL A
  ASL A
  CLC
  ADC sprShift,X
  STA dcX
  LDA sprScrY,X
  STA dcY
  RTS

\ ============================================================
\ DroidRun — one droid's pass. Port of dMd0_droid ($18CA)
\ ============================================================
\ X = the droid's index on entry, and everything called from here
\ either preserves it or reloads it from drIdx.
\
\ Combat is not here. The original's line-of-sight test and DoEnemyFire
\ sit between the sprite update and the waypoint search; Layer 7 puts
\ them back at that point.
.DroidRun
  LDA drType,X                  \ mode from the top bits of the type, as the
  LSR A : LSR A : LSR A : LSR A \ C64's DroidModeJump does: 0 droid, 1 bullet,
  AND #6                        \ 2 explosion. Bullets and explosions arrive
  BEQ dr_mode0                  \ with Layer 7; until then a type that claims
  RTS                           \ to be one is simply not run

.dr_mode0
IF DR_MOVES
  JSR DrMove
ENDIF
  LDX drIdx
  JSR DrCharPos                 \ the cell the droid is standing on — before
                                \ DrScreen, which needs it for the sight line
  JSR DrScreen                  \ near test, sprite slot, screen position

  LDX drIdx

IF DR_MOVES
  LDA drState,X
  BEQ dr_waypoint
  DEC drState,X                 \ paused: no new direction, and DrMove
  JMP dr_advance                \ has already held it still

.dr_waypoint
  LDA drPosXlo,X                \ on a tile centre in BOTH axes?
  ORA drPosYlo,X
  AND #&1F
  CMP #&10
  BNE dr_advance
  JSR DrFindWaypoint
  BCC dr_advance

  LDX drIdx                     \ the speed this type walks at, and its
  LDY drType,X                  \ negation, so a direction is an index
  LDA drSpeed,Y
  STA drSpdPos
  EOR #&FF
  ADC #0                        \ carry is set: FindWaypoint found one
  STA drSpdNeg
  JSR DrNewDir
ENDIF

\ The original probes three cells: the one the droid stands on and the
\ two ahead of it. Two cells is one pass's movement at the top droid
\ speed, which is what the lookahead is for.
.dr_advance
  JSR DrCheckAdvance
  JSR DrAdvancePos
  JSR DrCheckAdvance
  JSR DrAdvancePos
  JSR DrCheckAdvance
  JMP DrRegenerate

\ ============================================================
\ DrMove — port of MoveDroid ($1987)
\ ============================================================
\ Position += speed, sign-extended. A paused droid adds nothing, which
\ is the whole of what a pause is.
.DrMove
  LDX drIdx
  LDA drState,X
  BNE dm_noy
  LDA drSpdX,X
  BEQ dm_nox
  JSR DrSignA
  CLC
  LDA drPosXlo,X : ADC drSpdA   : STA drPosXlo,X
  LDA drPosXhi,X : ADC drSpdA+1 : STA drPosXhi,X
.dm_nox
  LDA drSpdY,X
  BEQ dm_noy
  JSR DrSignA
  CLC
  LDA drPosYlo,X : ADC drSpdA   : STA drPosYlo,X
  LDA drPosYhi,X : ADC drSpdA+1 : STA drPosYhi,X
.dm_noy
  RTS

\ A signed byte in A, sign-extended into drSpdA. X is preserved.
.DrSignA
  STA drSpdA
  LDA #0
  BIT drSpdA
  BPL ds_pos
  LDA #&FF
.ds_pos
  STA drSpdA+1
  RTS

\ ============================================================
\ DrCharPos — port of GetDroidCharPos ($299A)
\ ============================================================
\ The droid's own cell, and the reason the position is kept as the
\ reference cell rather than the sprite corner: this is three shifts
\ and nothing else. X = the droid's index.
\
\ THE HIGH BYTE HAS TO BE SHIFTED THREE TIMES, not once. Holding it in
\ A across all three `LSR A : ROR dcpLo` pairs is what carries bits 8,
\ 9 and 10 down into the result; shifting it once and rotating the low
\ byte the rest of the way gives the cell modulo 512, which is right
\ for the first quarter of a 2,048-pixel deck and wrong everywhere
\ else. Every droid past x=512 then looked up the wrong map cell, so
\ FindWaypoint missed and CheckDroidAdvance found walls that were not
\ there — the whole deck froze except the one droid near the origin.
\ This is the C64's own idiom at GetDroidCharPos ($299A), and it is
\ written that way for exactly this reason.
.DrCharPos
  LDA drPosXlo,X : STA dcpLo
  LDA drPosXhi,X
  LSR A : ROR dcpLo
  LSR A : ROR dcpLo
  LSR A : ROR dcpLo
  LDA dcpLo : STA drCX

  LDA drPosYlo,X : STA dcpLo
  LDA drPosYhi,X
  LSR A : ROR dcpLo
  LSR A : ROR dcpLo
  LSR A : ROR dcpLo
  LDA dcpLo : STA drCY
  RTS

\ ============================================================
\ DrFindWaypoint — port of FindWaypoint ($170D)
\ ============================================================
\ Carry set and src on the record if the droid's cell is a waypoint. A
\ deck's records are sorted by Y ascending, so the search gives up the
\ moment it passes the droid's row — which is why the exporter asserts
\ the sort.
.DrFindWaypoint
  JSR DrWaypoints
  LDY deck
  LDA wpCount,Y
  STA fwCount
.fw_loop
  LDY #1
  LDA (src),Y
  CMP drCY
  BCC fw_next                   \ record is above the droid: keep going
  BNE fw_fail                   \ past it, and they are sorted
  DEY
  LDA (src),Y
  CMP drCX
  BNE fw_next
  SEC
  RTS
.fw_next
  ADDPTR src, 3
  DEC fwCount
  BNE fw_loop
.fw_fail
  CLC
  RTS

\ ============================================================
\ DrNewDir — port of GetNewDir ($1CAD)
\ ============================================================
\ Byte 2 of the waypoint is a mask of permitted exits, one bit per
\ compass direction. The first THREE set bits, scanned from bit 7 down,
\ become candidates 2, 1 and 0; the rest of the mask is ignored and any
\ candidate slot left over is zeroed.
\
\ One of the three is then chosen at random. Choosing a zeroed slot is
\ not a bug and not a wasted draw — it is how a droid comes to stand
\ still for eight iterations at a junction with only one or two exits,
\ which is most of what makes them look like they are thinking.
\
\   bit  7   6   5   4   3   2   1   0
\   dx   0   0   1   2   2   2   1   0
\   dy   1   2   2   2   1   0   0   0
\        W  SW   S  SE   E  NE   N  NW
\
\ with 0 = -speed, 1 = 0, 2 = +speed. The C64's two delta tables
\ overlap in memory by six bytes; ours do not, because six bytes are
\ not worth the puzzle.
.DrNewDir
  LDY #2
  LDA (src),Y
  STY drCand                    \ next candidate slot to fill: 2, 1, 0
  LDY #8
.dnd_loop
  ASL A
  DEY
  BMI dnd_fill
  BCC dnd_loop
  PHA
  LDX drDirX,Y
  LDA drSpdNeg,X
  LDX drCand
  BMI dnd_pull                  \ three already
  STA drDeltaX,X
  LDX drDirY,Y
  LDA drSpdNeg,X
  LDX drCand
  STA drDeltaY,X
  DEC drCand
.dnd_pull
  PLA
  JMP dnd_loop

.dnd_fill
  LDX drCand
  BMI dnd_pick
.dnd_zero
  LDA #0
  STA drDeltaX,X
  STA drDeltaY,X
  DEC drCand
  LDX drCand
  BPL dnd_zero

.dnd_pick
  LDY #0
  JSR DrRandom
  CMP #&AA
  BCS dnd_got
  INY
  CMP #&55
  BCS dnd_got
  INY
.dnd_got
  LDX drIdx
  LDA drDeltaX,Y
  STA drSpdX,X
  LDA drDeltaY,Y
  STA drSpdY,X
  ORA drSpdX,X
  BNE dnd_x
  LDA #8                        \ nowhere to go: wait, and ask again
  STA drState,X
.dnd_x
  RTS

\ Negative / zero / positive speed, addressed as one three-entry table.
\ The C64 keeps its three in consecutive zero page for exactly this.
.drSpdNeg  EQUB 0
.drSpdZero EQUB 0
.drSpdPos  EQUB 0

.drDirX    EQUB 0, 1, 2, 2, 2, 1, 0, 0
.drDirY    EQUB 0, 0, 0, 1, 2, 2, 2, 1

\ ============================================================
\ DrAdvancePos — port of AdvanceMapPos ($1D0D)
\ ============================================================
\ Step the probe cell one character in the direction of travel.
.DrAdvancePos
  LDX drIdx
  LDA drSpdX,X
  BEQ dap_y
  BMI dap_xdec
  INC drCX
  JMP dap_y
.dap_xdec
  DEC drCX
.dap_y
  LDA drSpdY,X
  BEQ dap_x
  BMI dap_ydec
  INC drCY
  RTS
.dap_ydec
  DEC drCY
.dap_x
  RTS

\ ============================================================
\ DrCheckAdvance — port of CheckDroidAdvance ($1D30)
\ ============================================================
\ A solid cell ahead stops the droid for two iterations rather than
\ turning it round: the original leaves turning to the waypoints, and
\ so do we. An approach pad opens its door through the same DoorProbe
\ the player's own probes use, which is what lets a droid walk through
\ a door and hold it open while it does.
.DrCheckAdvance
  LDA drCX : STA cellX
  LDA #0   : STA cellX+1
  LDA drCY : STA cellY
  JSR MapChar
  BMI dca_wall
  CMP #DOOR_PAD
  BEQ dca_door
  RTS
.dca_wall
  LDX drIdx
  LDA #2
  STA drState,X
  RTS
.dca_door
  JMP DoorProbe                 \ preserves X, which is not live here

\ ============================================================
\ DrRegenerate — port of Regenerate ($1D45)
\ ============================================================
\ Energy comes back a point every fourth pass, up to $40. Type 23 —
\ droid 999, the influence device — DOUBLES its energy on the same
\ tick instead, which is why it is never worth leaving alone.
\ The fire delay counts down here whether or not there is anything to
\ fire at; Layer 7 is what reads it.
\
\ The C64 reads frameCount, one tick per GameLoop iteration. Ours is
\ drTick, bumped once a pass by DroidsUpdate — the same thing, and not
\ vsyncCount, which counts fields and would run at twice the rate.
.DrRegenerate
  LDX drIdx
  LDA drFireDelay,X
  BEQ drg_energy
  DEC drFireDelay,X
.drg_energy
  LDA drTick
  AND #3
  BNE drg_x
  LDA drType,X
  CMP #DR_999
  BEQ drg_999
  LDA drEnergy,X
  CMP #DR_ENERGY
  BCS drg_x
  INC drEnergy,X
.drg_x
  RTS
.drg_999
  LDA drEnergy,X
  ASL A
  CMP #DR_ENERGY
  BCC drg_set
  LDA #DR_ENERGY
.drg_set
  STA drEnergy,X
  RTS

\ ============================================================
\ DrScreen — port of DroidNear ($321E) and the slot allocation
\ ============================================================
\ A droid that is on screen owns one of the six sprite slots; one that
\ is not owns none. The C64's pool is six hardware sprites and ours is
\ six software ones, so the same case arises in the same place and
\ takes the same decision — including the harsh one at the end of
\ FindFreeSprite: a seventh droid coming into view with nothing free is
\ DESTROYED, not queued. That is the original's behaviour and it is
\ kept deliberately; our window is 320x120 against the C64's 320x200,
\ so it fires less often here than there.
\
\ CULLED, NOT CLIPPED, like every other sprite in this port — see
\ SprSetSlot. The test here only has to keep the arithmetic in range;
\ the blitter culls again on its own limits.
\ Out of range, and out of branch range of the tests below — the sight
\ line pushed the body of this routine past 127 bytes.
.drs_far
  JMP drs_off

.DrScreen
  LDX drIdx

  SEC                           \ screen Y first: one subtract, and it
  LDA drPosYlo,X : SBC drOrgY   \ rejects most of a deck
  STA drSy
  LDA drPosYhi,X : SBC drOrgY+1
  BNE drs_far                   \ above the view, or more than 255 below
  LDA drSy
  CMP #SPR_MAX_Y + 1
  BCS drs_far                   \ below it, or too low to draw whole

  SEC
  LDA drPosXlo,X : SBC drOrgX
  STA drSx
  LDA drPosXhi,X : SBC drOrgX+1
  STA drSx+1
  BMI drs_far                   \ left of the view
  BEQ drs_near                  \ 0-255 across: inside the limit by
  CMP #1                        \ construction, since DR_NEAR_X is 295
  BNE drs_far                   \ 512 or more to the right
  LDA drSx
  CMP #LO(DR_NEAR_X + 1)
  BCS drs_far

.drs_near
  LDA drSprNum,X                \ already holding a slot?
  BNE drs_place
  JSR DrFindSlot
  BEQ drs_nofree
  LDX drIdx
  STA drSprNum,X
  TAY
  TXA
  STA drSlotOwner,Y             \ the slot is OWNED from here until the droid
                                \ leaves the window, whether or not it is drawn
  LDA #1 : STA drVisNew,X       \ test the sight line at once, not in turn
  LDA #0 : STA sprDelay,Y
  TXA                           \ stagger the rotors, or a room full of
  AND #7                        \ droids spins in lockstep and reads as one
  STA sprFrame,Y

.drs_place
  LDY drSprNum,X
  LDA drType,X : STA sprType,Y  \ the type can change: 999 blows into 001
  LDA drSx
  AND #3                        \ the pixel within the 4 px CRTC unit is
  STA sprShift,Y                \ the shift; all four are compiled
  LDA drSx+1
  LSR A
  LDA drSx
  ROR A
  LSR A                         \ sx >> 2 = the unit
  STA sprUnit,Y
  LDA drSy
  STA sprScrY,Y

\ ---- and is it actually in sight? ---------------------------
\ The C64 keeps the sprite allocated and clears SpriteEna, so a droid
\ behind a wall holds its hardware sprite while being invisible. Ours
\ does the same with the two halves separated: drSlotOwner keeps the
\ slot, sprActive says whether the blitter draws it.
\
\ ONE SIGHT LINE A PASS, not one per droid. The C64 tests every near
\ droid every iteration and can afford to: the walk is the only thing
\ it does per droid that costs more than a few hundred cycles, and it
\ has no software blitter to pay for. Measured here, six of them cost
\ about 8,600 cycles a pass — more than a tenth of the whole pass, on a
\ question whose answer changes when a droid walks through a doorway
\ and not otherwise.
\
\ So the slots take turns, and a droid that has just come into view is
\ tested at once rather than waiting its turn. Worst case a droid that
\ steps behind a wall stays drawn for five more passes, a fifth of a
\ second. The alternative was a budget that does not fit.
  LDA drVisNew,X
  BNE drs_los                   \ just allocated: no answer to reuse
  LDY drSprNum,X
  CPY losTurn
  BNE drs_keepvis
.drs_los
  JSR DrLineOfSight
  LDX drIdx                     \ DrLineOfSight uses X as a scratch register
  LDA #0                        \ in the scaling loop — it does NOT come back
  BCS drs_hidden                \ carry set: a wall is in the way
  LDA #1
.drs_hidden
  STA drVis,X
  LDA #0
  STA drVisNew,X
.drs_keepvis
  LDA drVis,X
  LDY drSprNum,X
  STA sprActive,Y
  RTS

\ Nothing free. The C64 takes the droid off the ship entirely.
.drs_nofree
  LDX drIdx
  LDA #0
  STA drEnergy,X
  JMP DrRemoveShip

\ Off screen: give the slot back if it holds one.
.drs_off
  LDX drIdx
  LDA drSprNum,X
  BEQ drs_x
  TAY
  LDA #0
  STA sprActive,Y
  STA drSlotOwner,Y
  STA drSprNum,X
.drs_x
  RTS

\ ============================================================
\ DrFindSlot — port of FindFreeSprite ($32A8). A = 0 if none free
\ ============================================================
\ Slots 6 down to 1; slot 0 is the player's and is never in the pool.
\ OWNERSHIP, not sprActive: a droid hidden behind a wall is not drawn
\ but still holds its slot, exactly as the C64 keeps a hardware sprite
\ allocated with SpriteEna clear.
\ SPR_POOL_LAST, not SPR_SLOTS-1: slot 7 belongs to the player's bullet
\ and a droid may never be given it. The two were the same number until
\ Layer 7c added the eighth slot.
.DrFindSlot
  LDY #SPR_POOL_LAST
.dfs_loop
  LDA drSlotOwner,Y
  BEQ dfs_got
  DEY
  BNE dfs_loop
.dfs_got
  TYA
  RTS

\ ============================================================
\ DrLineOfSight — port of LineOfVisibility ($24AE)
\ ============================================================
\ Walk the character grid from the PLAYER's cell towards the droid's
\ and answer whether anything solid is in the way. Carry set = blocked.
\
\ The walk is a DDA with an 8.8 step: `CalcDeltaAdd` ($25AF) scales the
\ delta pair up — doubling while both fit in a byte, then adding the
\ original until one would overflow — so the longer axis advances
\ between half a character and a whole one per step and the shorter
\ one keeps its proportion. No division, which is the point of it.
\
\ The original tracks its position as a POINTER into the 16K character
\ map, so the two axes are the two bytes of one address and it can test
\ "have we passed the target" by comparing the pointer. We have no such
\ map — MapChar computes a character from the tile map — so the two
\ coordinates are held apart and the walk stops when the DOMINANT axis
\ reaches its target. The dominant axis is monotonic by construction,
\ so that is the same test written differently.
\
\ Reads plyCX/plyCY, which CheckWalls computed from the player's
\ position BEFORE this pass's move. One pass stale; the C64's
\ plyMapPos is the same.
\
\ **X IS NOT PRESERVED** — the scaling loop uses it to hold a tentative
\ value, the way CalcDeltaAdd does. The caller reloads drIdx. Losing
\ this cost an hour: the droid index became whatever the scale loop
\ left behind, `sprActive,Y` was then written through a Y read from the
\ wrong array, and slots nobody owned were switched on with no position
\ ever written into them. The player vanished because the pool was
\ drawing three slots of rubbish.
.DrLineOfSight
  LDA drCX
  CMP plyCX
  BNE dls_go
  LDA drCY
  CMP plyCY
  BNE dls_go
  CLC                           \ standing on the player: visible
  RTS

.dls_go
  SEC                           \ the deltas, and their absolute values
  LDA drCX : SBC plyCX : STA lsDx
  JSR DrAbsA
  STA lsAx
  SEC
  LDA drCY : SBC plyCY : STA lsDy
  JSR DrAbsA
  STA lsAy

  LDA lsAx                      \ which axis is the long one — it is the
  CMP lsAy                      \ one the walk is finished by
  BCS dls_xdom
  LDA #1
  BNE dls_setdom                \ always
.dls_xdom
  LDA #0
.dls_setdom
  STA lsDom

\ ---- scale the pair so the long axis steps ~1 character ----
\ Straight from CalcDeltaAdd: double while BOTH still fit in a byte,
\ then add the originals while both still fit. Neither half is ever
\ committed until the other has been tried, which is what keeps the
\ two in proportion.
  LDA lsAx : STA lsSx
  LDA lsAy : STA lsSy
.dls_dbl
  LDA lsSx
  ASL A
  BCS dls_add
  TAX
  LDA lsSy
  ASL A
  BCS dls_add
  STA lsSy
  STX lsSx
  JMP dls_dbl
.dls_add
  LDA lsSx
  CLC
  ADC lsAx
  BCS dls_scaled
  TAX
  LDA lsSy
  ADC lsAy                      \ carry is clear: the BCS above did not take
  BCS dls_scaled
  STA lsSy
  STX lsSx
  JMP dls_add
.dls_scaled

\ ---- signs: the integer part of a negative step is $FF ------
  LDA #0 : STA lsIx : STA lsIy
  LDA lsDx
  BPL dls_xpos
  LDA #0 : SEC : SBC lsSx : STA lsSx    \ -frac, with $FF carried in
  LDA #&FF : STA lsIx
.dls_xpos
  LDA lsDy
  BPL dls_ypos
  LDA #0 : SEC : SBC lsSy : STA lsSy
  LDA #&FF : STA lsIy
.dls_ypos

  LDA #0 : STA lsFx : STA lsFy
  LDA plyCX : STA lsCX
  LDA plyCY : STA lsCY
  LDA #DR_LOS_MAX
  STA lsCount

.dls_loop
  CLC
  LDA lsFx : ADC lsSx : STA lsFx
  LDA lsCX : ADC lsIx : STA lsCX
  CLC
  LDA lsFy : ADC lsSy : STA lsFy
  LDA lsCY : ADC lsIy : STA lsCY

  LDA lsCX : STA cellX
  LDA #0   : STA cellX+1
  LDA lsCY : STA cellY
  JSR MapChar
  BMI dls_blocked

  LDA lsDom                     \ has the long axis arrived?
  BNE dls_testy
  LDA lsCX
  CMP drCX
  BEQ dls_clear
  BNE dls_next                  \ always
.dls_testy
  LDA lsCY
  CMP drCY
  BEQ dls_clear
.dls_next
  DEC lsCount
  BNE dls_loop
.dls_clear
  CLC
  RTS
.dls_blocked
  SEC
  RTS

\ |A|, flags set from the result.
.DrAbsA
  BPL dab_x
  EOR #&FF
  CLC
  ADC #1
.dab_x
  RTS

\ ============================================================
\ DrRemoveShip — port of RemoveShipDroid ($1C9D)
\ ============================================================
\ Take the droid out of the ship's roster, not just off this deck, so
\ it does not come back when the deck is re-entered.
.DrRemoveShip
  LDX drIdx
  LDY drShipIdx,X
  LDA shipDroids,Y
  BEQ drm_x
  LDA #0
  STA shipDroids,Y
  DEC shipNumDroids
.drm_x
  RTS

\ ============================================================
\ state
\ ============================================================
\ Absolute, not zero page: every one of these is reached through X or
\ Y, and LDA abs,X and LDA zp,X are both 4 cycles. See the note in
\ main.asm — the only things worth moving down are scalars read inside
\ a loop, and these are read once a droid.
.drType      SKIP DR_SLOTS
.drEnergy    SKIP DR_SLOTS
.drSpdX      SKIP DR_SLOTS      \ signed pixels per pass
.drSpdY      SKIP DR_SLOTS
.drState     SKIP DR_SLOTS      \ non-zero: paused, and counting down
.drSprNum    SKIP DR_SLOTS      \ sprite slot 1-6, 0 = not on screen
.drShipIdx   SKIP DR_SLOTS      \ where it lives in the ship roster
.drFireDelay SKIP DR_SLOTS
.drPosXlo    SKIP DR_SLOTS
.drPosXhi    SKIP DR_SLOTS
.drPosYlo    SKIP DR_SLOTS
.drPosYhi    SKIP DR_SLOTS

.drVis       SKIP DR_SLOTS      \ last sight-line answer, per droid
.drVisNew    SKIP DR_SLOTS      \ needs one now, having just been allocated
.losTurn     EQUB 1             \ the slot whose turn it is

.drSlotOwner SKIP SPR_SLOTS     \ droid index holding each sprite slot, 0 free

.drCount     EQUB 0             \ high-water mark; 1 means the deck is clear
.drIdx       EQUB 0
.drDst       EQUB 0
.drTick      EQUB 0
.drCX        EQUB 0
.drCY        EQUB 0
.drSx        EQUW 0
.drSy        EQUB 0
.drOrgX      EQUW 0             \ view origin + the reference offsets,
.drOrgY      EQUW 0             \ formed once a pass
.drSpdA      EQUW 0
.drCand      EQUB 0
.drDeltaX    SKIP 3
.drDeltaY    SKIP 3
.fwCount     EQUB 0
.dcpLo       EQUB 0
.dcpHi       EQUB 0
.diIdx       EQUB 0
.drTmp       EQUB 0
.drDeckBase  EQUB 0             \ deck * 16, the roster row
.drSeed      EQUB &A5

.lsDx        EQUB 0             \ DrLineOfSight: the delta, and its size
.lsDy        EQUB 0
.lsAx        EQUB 0
.lsAy        EQUB 0
.lsSx        EQUB 0             \ the scaled step: fraction of a character
.lsSy        EQUB 0
.lsIx        EQUB 0             \ and its integer part, 0 or &FF
.lsIy        EQUB 0
.lsFx        EQUB 0             \ the fraction accumulators
.lsFy        EQUB 0
.lsCX        EQUB 0             \ where the walk has got to
.lsCY        EQUB 0
.lsDom       EQUB 0             \ 0 = X is the long axis, 1 = Y
.lsCount     EQUB 0

.dcOuter     EQUB 0             \ DrCollide: the pair of slots in hand
.dcInner     EQUB 0
.dcX         EQUB 0
.dcY         EQUB 0
.dcX2        EQUB 0
.dcY2        EQUB 0
.drCollHit   EQUB 0             \ something touched this pass
.drCollWas   EQUB 0             \ and had last pass — the debounce
.nsdDeck     EQUB 0
.nsdBase     EQUB 0
.nsdLeft     EQUB 0
.shipNumDroids EQUB 0
.shipLevel   EQUB 1             \ ship 1; NextLevel raises it, capped at 8
.shipDroids  SKIP 256
