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
\ ============================================================
\ CbReset001 — BlowInto001's reset half ($158D-$15E3)
\ ============================================================
\ IN BANK 4 because every field it writes but the three sprite ones is
\ here: drType, drEnergy and drFireDelay are entry 0 of the droid table,
\ maxEnergy and weaponType are combat.asm's but reachable, and the speed
\ clamps are this file's own. Called from ccd_reset in main RAM, mid-pass,
\ with SWRAM_DATA paged.
\
\ THE ENERGY IS SEVEN and that is not CombatInit's $40. $12A5 and $158D
\ both load 7; the $40 at $1345 is what the entry animation ENDS on and
\ belongs to the start of a ship, not to coming back from a death. So
\ GameStart does not share this routine — see its own note.
.CbReset001
  LDA #0
  STA drType                    \ back to droid 001
  STA drFireDelay
  STA xSpd : STA xSpd+1         \ stop dead, as $15A5 does
  STA ySpd : STA ySpd+1
  LDA #7                        \ $158D
  STA drEnergy
  LDA maxEnergy                 \ $1594: the ceiling only ever falls, so
  CMP #7                        \ this is a floor and not an assignment
  BCS cb1_ceiling
  LDA #7
  STA maxEnergy
.cb1_ceiling
  LDY drType                    \ $15E0: the weapon comes with the droid
  LDA drWeapon,Y
  STA weaponType

  LDA #LO(PLY_MAXSPD) : STA plyMaxLo  \ $15D2, and the clamp is a variable
  LDA #HI(PLY_MAXSPD) : STA plyMaxHi  \ because Layer 10 rewrites it per
  LDA #LO(PLY_MAXNEG) : STA plyNegLo  \ transfer
  LDA #HI(PLY_MAXNEG) : STA plyNegHi

  LDA #MM_MOBILE : STA moveMode
  RTS

\ ============================================================
\ LoadDeck — decode a deck, build its charset, frame and draw it
\ ============================================================
\ IN BANK 4 since Layer 11, for main RAM rather than for tidiness: it is
\ nothing but calls, and all but three of them are into this bank
\ already. Every caller runs with SWRAM_DATA paged — GameStart and the
\ lift are in here, the two debug deck keys are in the main loop where
\ the data bank is the resting state.
.LoadDeck
\ deckClear is DroidsInit's, below: it is the only thing that knows
\ whether this deck has any droids left on it. It used to be zeroed
\ here because ReframeView ran first and built the palette; now
\ DroidsInit runs first and sets it either way. Layer-15 DECISION 6
  LDA deck
  JSR BuildCharset              \ charset is deck specific
  JSR AnimReset                 \ ...which puts the alert lamp back on its
                                \ default colour, so the lamp must rebuild

\ NO SetPalette HERE ANY MORE. RedrawAll does it, and RedrawAll is where
\ the deck is actually drawn — ReframeView below ends in it. The call
\ here fought the text-screen palette: the 001 screen is up across this
\ LoadDeck (it holds the redraw back, see infoscr.asm), so setting the
\ deck's colours here overrode the text background InfoCall had just
\ chosen, every time. ReframeView returns early while a screen is up, so
\ the deck's palette now lands exactly when the deck does. DECISION 4.

\ The deck's own hum: three bytes into effect 24's record, exactly the
\ C64's $135F writes into sfx23+5/6/7 — segment timer, reload, count.
\ The record is in THIS bank, so the patch is three plain stores.
  LDX deck
  LDA sndBgVar1,X
  STA sndFxTab + 23*SND_FX_LEN + 5
  LDA sndBgVar2,X
  STA sndFxTab + 23*SND_FX_LEN + 6
  LDA sndBgVar3,X
  STA sndFxTab + 23*SND_FX_LEN + 7
  LDA deck
  JSR BuildLevel

\ Where we arrive. A lift knows exactly where it puts you; everything
\ else arrives on WAYPOINT 0, which is the one waypoint InitDeckDroids
\ never places a droid on and is there for exactly this. It replaces
\ CentreOnDeck, whose centroid framed the deck without ever asking
\ whether the cell under the player was walkable — BUGS.md #4.
  LDA liftPlace
  BEQ ld_spawn
  LDA #0
  STA liftPlace
  JSR LiftPlace
  JMP ld_placed
.ld_spawn
  JSR DrSpawnPoint              \ -> cellX / cellY, characters
  JSR SetPosFromWaypoint        \ the pixel position is the authority from
                                \ here on
.ld_placed
  JSR DoorInit                  \ a door left open on the deck we are
                                \ leaving would patch a tile position on
                                \ the one we are entering
  JSR DroidsInit                \ the deck's droids, on its waypoints.
                                \ ABOVE ReframeView since Layer 15:
                                \ ReframeView ends in RedrawAll, which
                                \ calls SetPalette, and DroidsInit is now
                                \ what decides whether this deck is
                                \ already clear. Layer-15 DECISION 6
  JSR ReframeView
IF NOT(DEBUG_ENERGY)
  JSR PanelSetup                \ Layer 9: the static words and the deck
                                \ number. AFTER DroidsInit, so the droid
                                \ count PanelUpdate reads is this deck's
ENDIF
IF DEBUG_MAPGUARD
  JSR MapGuardSnap              \ LAST: the map as the finished load left it
ENDIF
  RTS

\ ============================================================
\ GameStart — StartGame ($1242) and _entership ($1289)
\ ============================================================
\ EVERYTHING A NEW GAME NEEDS, and nothing a cold boot needs. main.asm's
\ boot used to run straight through this into the main loop, so all of
\ it could lean on beebasm's assembled initial values; from Layer 11 on
\ the game is startable more than once and every one of those defaults
\ has to be written out loud. That is the whole of this routine: the
\ C64's two entry points, plus the state the port keeps that they have
\ no equivalent for.
\
\ IN BANK 4, next to NewShipDroids and the droid tables it seeds, and
\ called from main RAM with SWRAM_DATA paged — the resting state, and
\ true at boot from the PAGEBANK before the seed. See bufcore.asm.
\
\ It does NOT reload the banks, rebuild the charset pointers or the
\ sprite mask table, or touch the CRTC: those are the cold-boot half and
\ they survive a restart. What does not survive is anything the game
\ writes, which is what follows.
.GameStart
\ ---- what the title screen was for -------------------------
\ $12B6 reads $D41B — free-running SID noise — AFTER however long the
\ player left the title up, and that wait is what makes the starting
\ deck unpredictable. TiWait leaves its dwell in overRnd0 and this is
\ where it meets the LFSR, because drSeed lives in this bank. A zero
\ result would lock the LFSR for ever, so it is refused twice over.
  LDA overRnd0
  BEQ gs_seeded
  EOR drSeed
  BEQ gs_seeded
  STA drSeed
.gs_seeded

  LDA #0                        \ $10DB and $13D0: no burst is running, and
  STA disruptorCnt              \ nobody is owed the kills of one
  STA disruptorOwner
  STA cbNoScore
  STA disrFlash

  LDA #0
  STA shipLevel                 \ $1255 ZEROES IT, and EnterShip4's INC
                                \ below is NextLevel's at $129E. The port
                                \ used to write 1 here because the two
                                \ halves were fused and there was nothing
                                \ to do the increment; now that the split
                                \ is real this is the original's own value

  JSR CombatInit                \ $1345, the energy the entry animation
                                \ ends on, and $1259-$1263's weapon, score
                                \ and type. Entry 0 of the droid table is
                                \ the PLAYER, and this seeds it — before
                                \ LoadDeck, because DroidsInit places
                                \ droids around it

\ ============================================================
\ EnterShip4 -- _entership ($1289), and it is callable alone
\ ============================================================
\ LAYER 15, T5. Everything below this label is the SECOND of the
\ C64's two entry points, and the split is the original's own: $1242
\ StartGame falls through into $1289 _entership, and $1286
\ ShowShipClear falls into it too. The port had them fused because
\ until now nothing could reach the second half by itself.
\
\ WHAT IS ABOVE AND WHAT IS BELOW IS NOT A JUDGEMENT CALL. Above is
\ what a NEW GAME needs and a new SHIP must not have: the title's
\ seed, the disruptor state, shipLevel back to zero, and CombatInit
\ -- which zeroes the SCORE. Call that on a ship transition and the
\ two thousand points just awarded are wiped, along with everything
\ else the player earned. That is why the C64 keeps the halves apart
\ and it is the whole reason this task existed.
\
\ WHAT CARRIES OVER, and it surprises: $1289 does NOT reset
\ droidType. The player keeps the droid they captured into the next
\ ship. $12A5-$12AA then drop energy to 7 and $12A1 sets the
\ materialise mode, so they arrive weak but still riding it.
\
\ IT IS REACHED FROM InfoCall, not from here, when the ship-clear
\ screen is dismissed -- IS_ACT_NEWSHIP. GameStart still falls
\ straight through, which is $1242's own behaviour.
.EnterShip4

\ ---- the eighth ship is the last one -----------------------
\ [DECISION 5] The C64 never ends: NextLevel caps shipLevel at 8, the
\ console wraps the name at (shipLevel - 1) AND 7, and the player
\ clears ship after ship until they die. KC chose an ENDING instead --
\ eight ships cleared is a win -- so that is a deviation, and the only
\ one in the layer.
\
\ THE TEST IS NOT HERE. It is in InfoHigh, main.asm: both things it
\ does on the last ship -- raise hsArmed and go to GoTitle -- are main
\ RAM, and InfoHigh already holds the JMP GoTitle it would need. So
\ this routine is only ever reached when there IS a next ship, and
\ shipLevel therefore runs 1 to 8 and needs no cap of its own.

  INC shipLevel                 \ $129E NextLevel's own increment

  JSR NewShipDroids             \ $129E: the ship's complement, generated
                                \ once and then owned by the decks — it
                                \ reads shipLevel, so it follows it



\ ---- nothing modal owns the machine ------------------------
\ None of this matters on the first game, when the assembled defaults are
\ already zero. On the second it is the point: a game that ended with the
\ console up, a lift half-entered or a transfer still holding its verdict
\ would otherwise start the next one there.
  LDA #0
  STA conActive
  STA conDbReq
  STA xferActive
  STA xferDroid
  STA xfmDone
  STA xfmResult
  STA liftMode
  STA liftPlace
  STA lvCommit
  STA lvLoad
  STA overPhase                 \ and the game over that brought us here

\ ---- and no key is half-pressed ----------------------------
\ Every edge latch in the game, because the restart itself is a keypress
\ and the key that caused it may still be down.
  STA prevRet
  STA prevLU
  STA prevLD
  STA lvPrevFire
  STA fireDown
  STA fireEaten
  STA lDown
  STA prevUp
  STA prevDn
  STA joyXDir
  STA joyYDir

\ ---- the player, standing still ----------------------------
  STA plyDying                  \ $15A5, and the explosion that set it
  STA xSpd : STA xSpd+1         \ $1289
  STA ySpd : STA ySpd+1
  STA posXf                     \ the sub-pixel remainders with them
  STA posYf

\ ---- per-pass bookkeeping ----------------------------------
  STA sprSplit
  STA rowOfs
  STA rowOfs+1
  STA drCollHit                 \ byte_0_6C: no collision episode is open
  LDA #1
  STA losTurn                   \ the sight line's turn, and it is 1-based

\ ---- back to the 001's speed and mode ----------------------
\ The clamp is a variable because Layer 10 rewrites it per transfer, so a
\ game that ended riding a fast droid would hand its top speed to the
\ next one. Same four stores as CbCheckDeath's ccd_reset, deliberately
\ not shared with it: that routine also drops energy to BlowInto001's 7,
\ which must not land on top of CombatInit's $40.
  LDA #MM_MOBILE : STA moveMode \ $12A1
  LDA #MM_DELAY  : STA mmDelay
  LDA #LO(PLY_MAXSPD) : STA plyMaxLo
  LDA #HI(PLY_MAXSPD) : STA plyMaxHi
  LDA #LO(PLY_MAXNEG) : STA plyNegLo
  LDA #HI(PLY_MAXNEG) : STA plyNegHi

  JSR SprInit                   \ the pool, and the player back in slot 0.
                                \ BEFORE LoadDeck, whose DroidsInit hands
                                \ slots out. SprBuildMask stays at boot:
                                \ it builds a table, this resets state

\ ---- the deck the game starts on ---------------------------
\ $12B6, verbatim: `LDA $D41B : AND #3 : CLC : ADC #4 : STA deckNum`.
\ FOUR decks, 4 to 7 — the middle of the ship, so there is somewhere to
\ go in both directions and the deck you start on is not the one holding
\ the Influence Device's own class of droid.
\
\ The C64's next two instructions, `EOR #$FF : STA prevDeck`, are not
\ ported. prevDeck exists so that GameLoop's enter-deck block at $1359
\ can skip the per-deck setup when the lift did not actually move you,
\ and seeding it to the complement of deckNum guarantees the first deck
\ always sets up. Our LoadDeck does that work unconditionally, so there
\ is nothing to gate.
  JSR DrRandom
  AND #3
  CLC
  ADC #DECK_START_LO
  STA deck

  LDA #&12                      \ $1250: the driver into game-FX mode.
  STA sndState                  \ $1334's deck materialise USED to be here
                                \ too; 11d moved it, because the 001 screen
                                \ now stands between GameStart and the deck
                                \ and the alert has to land when the DECK
                                \ does, not before the screen. IsDone posts
                                \ it. fx $B is the screen's own
  JMP LoadDeck                  \ and its RTS

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

\ $1377/$138E: THE DECK IS ASSUMED CLEAR UNTIL SOMETHING IS PLACED.
\ The C64 writes 15 to numDeckDroids here and overrides it with 1 at
\ $138E when InitDeckDroids placed nothing; ours reaches the same two
\ values from the other end, which is cheaper and needs no counter.
\
\ A COUNT OF 1 IS WHAT MAKES THE EVENT FIRE ONCE. It makes
\ DroidsUpdate's guard return every pass, so the compaction never runs
\ and the deck-clear arm is never reached -- which is exactly what
\ $138E-$1390 buys by skipping RunDroids outright. Without it, walking
\ back onto a deck already cleared re-ran the whole event: the sound,
\ the colour AND another 500 points, every time. Layer-15 DECISION 6.
  LDA #1
  STA drCount
  STA deckClear
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
  LDA #DR_SLOTS                 \ and it is NOT clear. DR_SLOTS because
                                \ the roster row is walked from 15 down
                                \ and the occupied slots are not
                                \ contiguous, so the compaction has to
                                \ scan the whole table. A is free here --
                                \ TYA overwrites it two lines below
  STA drCount
  LDA #0
  STA deckClear
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
  BEQ di_loopend
  JMP di_loop                   \ Layer 15 grew the block past a branch,
                                \ the same way the copy-down in
                                \ DroidsUpdate did
.di_loopend

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
IF DEBUG_KILL
  JSR DbgKill4                  \ the C key, and it costs BANK 4 three
                                \ bytes rather than main RAM's last
                                \ three. Above the guard below, so it
                                \ still answers on a cleared deck
ENDIF
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
  LDA drBulFrm,X    : STA drBulFrm,Y

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
\ ---- the deck is clear -------------------------------------
\ $17D7: CPY #1 / BEQ, and it fires exactly ONCE because the guard
\ at the top of this routine returns early from the next pass on --
\ drCount is 1 and never reaches here again.
\
\ ALL OF $17DC IS HERE NOW. It was the colour alone when Layer 14
\ landed the floor; Layer 15 added the rest of the event in the
\ original's own order -- InitColors, AddScore twice with 250,
\ sndFx1 = $17, and the shipNumDroids test that decides whether the
\ whole SHIP has just been cleared as well.
  CPY #1
  BNE dru_notclear
  STY deckClear                 \ Y is 1: the deck is clear, and the
  JSR SetPalette                \ floor turns blue until DroidsInit
                                \ says otherwise

\ ---- $17DF: FIVE HUNDRED POINTS, and the effect -----------
\ TWO CALLS OF 250 AND NOT ONE OF 500, because AddScore takes a
\ BYTE. $17DF and $17E4 are the same instruction twice and this is
\ that, not an equivalent. The points are PENDING, not scored:
\ DoScore drains scoreAdd one point a pass, so the panel climbs
\ over the next twenty seconds rather than jumping. Layer-15 T1.
  LDA #250 : JSR AddScore
  LDA #250 : JSR AddScore
  LDA #&17                      \ $17E9, the deck-cleared chord
  STA sndFx1

\ ---- $17ED: and is the whole SHIP clear? ------------------
\ The C64 tests shipNumDroids here and does INC notInDeck, its
\ shared "leave this loop" flag. The port has no notInDeck and
\ reaches the lift, the console and the transfer by other means,
\ so this raises a dedicated byte that the main loop tests beside
\ them. Layer-15 DECISION 4, and T2.
\
\ IT FIRES ONCE, for the same reason the deck clear does: the
\ guard at the top of DroidsUpdate returns early from the next
\ pass on, so this code is never reached twice.
  LDA shipNumDroids
  BNE dru_notclear

\ ---- $1272 _shipclean: TWO THOUSAND POINTS ---------------
\ Ten calls of 200 and a counter, $1274-$127D verbatim, and again
\ because AddScore takes a byte. $127F FindStrings has no port --
\ the string table is scanned rather than indexed, see infoscr.asm
\ -- and $1282 sndFx1 = $B is IsStart's, posted from isSndFor when
\ the screen goes up. So what is left of _shipclean is the bonus
\ and the flag. Layer-15 T3.
  LDX #10                       \ $1272: tmp2
.dru_shipbonus
  LDA #200 : JSR AddScore
  DEX
  BNE dru_shipbonus
  INC shipClear                 \ $1286: and ShowShipClear next
.dru_notclear
  JSR DrBulletHit               \ before the pair loop — see its header
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
\n\ drCollHit IS NOT CLEARED AT THE TOP OF THE PASS. byte_0_6C is written
\ only by ReverseDroidDir and cleared only at _x_none ($1A3E) — the exit
\ taken when no colliding pair was found at all — so the latch survives
\ for as long as the pair stays touching. Clearing it here instead let
\ the reverse re-arm every other pass, which is half of BUGS.md #7a.
.DrCollide
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
  LDA #0                        \ _x_none ($1A3E): a pass with NO collision at
  STA drCollHit                 \ all, and the only thing that releases it
  RTS

\ dcOuter and dcInner are the two slots; act on the droids behind them.
\ THE DEBOUNCE IS HELD BY DrReverse, not here. byte_0_6C is written in
\ ReverseDroidDir ($1C67) and nowhere else, so on the C64 it latches on
\ a BUMP and not on mere contact. Setting it here instead meant a bullet
\ parked inside the droid that fired it — which, before the speed fix
\ above, was every bullet — held the debounce down for as long as it
\ lived and suppressed the player's own bounce with it.
.DrCollided
  LDA dcOuter                   \ slot 0 is the player, and the pairs are
  BNE dc_matrix                 \ ordered so he can only be the outer one
  JMP dc_player
.dc_matrix
\
\ DoCollision2 ($1B51) and CollisionType ($6D6D), which the port carried
\ as two hard-coded arms — reverse the first, pause the second — until
\ the friendly-fire work needed the rest of the table. The player's own
\ collisions are NOT in it: $1A43 branches to _ply_droid and friends
\ before DoCollision2 is ever reached, which is dc_player below.
\ THE PLAYER'S BULLET IS NOT IN IT EITHER, and on the C64 it is: sprite
\ 0 is the player's shot and it takes column 3 of the table. Ours is
\ slot 7, has no droid-table entry, and is handled by DrBulletHit before
\ this loop runs — so mode 3 never arises here. The table ships whole
\ anyway, because a 32-byte transcription is faithful by construction
\ and a trimmed one is faithful until the first thing it gets wrong.
  LDY dcOuter
  LDA drSlotOwner,Y
  BEQ dc_none
  STA dcIdxA
  LDY dcInner                   \ an explosion still owns its slot, so it
  LDA drSlotOwner,Y             \ turns up here — and the table is what
  BNE dc_gotpair                \ says it may not be shoved about
.dc_none
  RTS
.dc_gotpair
  STA dcIdxB

  LDX dcIdxA : JSR DrCollMode : STA dcModeA
  LDX dcIdxB : JSR DrCollMode : STA dcModeB

\ Index = the TARGET's mode * 8 + the other one's, which is what
\ GetCollisionType's collision2mode/collision1mode pair comes to once
\ $1B68's swap is unwound. Two passes, one per party, exactly as the
\ swap-and-repeat at _1 does.
  LDA dcModeA
  ASL A : ASL A : ASL A
  CLC : ADC dcModeB
  TAX
  LDA drCollType,X
  LDX dcIdxA
  LDY #0                        \ arm 1: $08 means reverse
  JSR DrCollAct

  LDA dcModeB
  ASL A : ASL A : ASL A
  CLC : ADC dcModeA
  TAX
  LDA drCollType,X
  LDX dcIdxB
  LDY #1                        \ arm 2: $08 means stand still
  JMP DrCollAct

\ DrCollMode is in src/lowcode2.asm. Bank 4 had three bytes left.

\ ---- DrCollAct — one entry of the table, one party ---------
\   A = the action byte, X = the droid it happens to, Y = which arm
\ The bit order is $1B56's own ASL chain, and the two arms differ in
\ exactly one place: $08 reverses the first party and stops the second.
.DrCollAct
  STX drIdx
  STY dcArm
  BMI dca_x                     \ $80: nothing happens to this one
  ASL A : BMI dca_explode       \ $40
  ASL A : BMI dca_efire         \ $20
  ASL A : BMI dca_free          \ $10
  ASL A : BMI dca_bump          \ $08
  ASL A : BMI dca_pfire         \ $04
.dca_x
  RTS                           \ $02 is a no-op in both arms
.dca_explode
  JMP DrExplodeSprite
.dca_efire
  JMP DrEnemyFireEnemy
.dca_free
  JMP DrFreeEntry
.dca_bump
  LDA dcArm
  BNE dca_pause
  JMP DrReverse
.dca_pause
  JMP DrPause16
.dca_pfire
  JMP DrPlyFireEnemy

\ ---- the player has walked into a droid ---------------------
\ THE DEBOUNCE IS THE DROID ARM'S ALONE, and putting it in front of all
\ three arms was BUGS.md #11's second half: a bullet could pass through
\ the player doing nothing, because something else had touched in the
\ previous pass. The C64 tests byte_0_6C at $1A77, inside _ply_droid and
\ before the pause, the reverse and the bounce — while _ply_bullet
\ ($1AF1) and _ply_xplosion ($1B1A) test nothing at all. They do not
\ need to: a bullet frees its own sprite the moment it lands, so it can
\ only ever be counted once, and standing in an explosion is meant to
\ hurt every pass.
.dc_player
  LDY dcInner
  LDA drSlotOwner,Y
  BEQ dc_x
  TAX
  STX dcHit                     \ the thing he touched, for the damage arm
  LDA drType,X
  CMP #DR_TYPE_BULLET
  BCS dc_hurt                   \ a bullet or an explosion: no shove, no
                                \ bounce, and no debounce

\ ---- Transfer mode: touching a droid IS the transfer --------
\ $1A6A's own gate, BEFORE the debounce: moveMode 0 and a droid means
\ Capture, so the index goes to main RAM for the main loop to see —
\ this code is bank 4 and cannot start the bank-7 game itself. No
\ bounce, no damage: the C64's arm is STY xferDroid, RTS, nothing else.
  LDA moveMode
  BNE dc_notransfer
  STX xferDroid
  RTS
.dc_notransfer

  LDA drCollHit                 \ $1A77: once per episode, or he sticks to the
  BNE dc_x                      \ droid shaking — drained in a second
  LDA #&1A                      \ $1A7D: the bump, on the episode edge
  STA sndFx1
  JSR DrPause16
  JSR DrReverse
  LDX #0                        \ the C64 negates the whole-pixel part of
  JSR DrBounce                  \ each speed, forces it to at least 1, and
  LDX #2                        \ doubles it
  JSR DrBounce
.dc_hurt
  LDX dcHit
  JMP DrHurtPlayer
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

\ ReverseDroidDir ($1C5F). IT HOLDS THE DEBOUNCE ITSELF, tested at $1C63
\ and latched at $1C67, and that guard is load-bearing rather than a
\ duplicate of the caller's. It was left out here on the grounds that
\ both call sites had already made the test; only dc_player had. The
\ droid-droid arm therefore reversed EVERY pass while two droids
\ overlapped, so the outer droid jittered on the spot with no net drift
\ while the inner one had its 16 renewed under it and never got to walk
\ away — a permanent lock, and BUGS.md #7a. On the C64 the second and
\ later passes do nothing: the first droid keeps the direction it was
\ given and clears the overlap. Restored 2026-08-18.
\n\ Being the only writer of the latch is what keeps contact that does not
\ BUMP — a bullet, an explosion — from arming it.
.DrReverse
  LDA drCollHit                 \ $1C63, and it is not optional: the
  BNE drv_x                     \ droid-droid call site makes no test of its own
  LDA #&FF
  STA drCollHit
  SEC
  LDA #0 : SBC drSpdX,X : STA drSpdX,X
  SEC
  LDA #0 : SBC drSpdY,X : STA drSpdY,X
.drv_x
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
  AND #6                        \ 2 explosion, 3 player fire
  BEQ dr_mode0
  CMP #4
  BEQ dr_xplode                 \ mode 2, and out of branch range of it
  CMP #2
  BEQ dr_bullet                 \ mode 1, an enemy bullet
  RTS                           \ mode 3 is the player's, and is not here
.dr_xplode
  JMP DrExplode
.dr_bullet
  JMP DrBullet

.dr_mode0
IF DR_MOVES
  JSR DrMove
ENDIF
  LDX drIdx
  JSR DrCharPos                 \ the cell the droid is standing on — before
                                \ DrScreen, which needs it for the sight line
  JSR DrScreen                  \ near test, sprite slot, screen position

\ SHOOTING IS GATED ON THE SPRITE BEING LIT, which is the C64's own
\ gate — DoEnemyFire sits inside dMd0's SpriteEna arm, so a droid that
\ cannot see the player does not shoot at him. DrScreen has just
\ settled that for this pass.
  LDX drIdx
  LDY drSprNum,X
  BEQ dr_nofire
  LDA sprActive,Y
  BEQ dr_nofire
  JSR DrEnemyFire
.dr_nofire

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
  LDA #0
  STA sprKind,Y                 \ the slot may last have held an explosion,
                                \ and sprType means a FRAME to an effect slot
  STA sprDelay,Y
  TXA                           \ stagger the rotors, or a room full of
  AND #7                        \ droids spins in lockstep and reads as one
  STA sprFrame,Y

.drs_place
  LDY drSprNum,X
  LDA drType,X : STA sprType,Y  \ the type can change: 999 blows into 001

\ AN ENEMY DROID IS BLACK. dMd0_droid's _new arm ($18FA) writes $F0 —
\ C64 colour 0 — into SpriteColor the moment a droid is given a sprite,
\ and nothing changes it again while it lives. Only the player is ever
\ another colour, and the player is entry 0, which this loop starts
\ past. Set every pass rather than once at allocation: a slot that has
\ been round the pool as an effect comes back with the right colour
\ without anyone having to remember to put it back.
  LDA #SPR_COL_BLACK
  STA sprColour,Y
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

  JSR DrScaleDelta              \ -> (lsSx,lsIx) and (lsSy,lsIy)

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

\ ============================================================
\ DrScaleDelta — port of CalcDeltaAdd ($25AF), plus the sign restore
\ ============================================================
\ In:  lsDx / lsDy, the signed deltas; lsAx / lsAy, their magnitudes.
\ Out: (lsSx, lsIx) and (lsSy, lsIy) — a 16-bit signed pair each,
\      scaled together until the LONGER of the two is in [128, 255].
\
\ Double while BOTH still fit in a byte, then add the originals while
\ both still fit. Neither half is ever committed until the other has
\ been tried, which is what keeps the two in proportion.
\
\ THIS IS THE DIRECTION VECTOR, and it is why the sight line and the
\ enemy bullet share it. The C64 computes it once in LineOfVisibility
\ and DoEnemyFire then runs AddBullet off whatever it left in
\ deltaX/deltaY — so the bullet's velocity is a NORMALISED direction and
\ has nothing to do with how far away the player is. Ours tests one
\ sight line a pass rather than all six, so the deltas in hand belong to
\ some other droid; DrAddBullet calls this again for its own.
\
\ **X IS NOT PRESERVED** — the loops use it to hold a tentative value,
\ the way CalcDeltaAdd does. Both callers reload drIdx afterwards.
\
\ lsAx and lsAy must not BOTH be zero or the doubling never terminates.
\ Both callers check: LineOfVisibility returns early when the droid is
\ standing on the player, and DrAddBullet declines the shot.
.DrScaleDelta
  LDA lsAx : STA lsSx
  LDA lsAy : STA lsSy
.dsd_dbl
  LDA lsSx
  ASL A
  BCS dsd_add
  TAX
  LDA lsSy
  ASL A
  BCS dsd_add
  STA lsSy
  STX lsSx
  JMP dsd_dbl
.dsd_add
  LDA lsSx
  CLC
  ADC lsAx
  BCS dsd_scaled
  TAX
  LDA lsSy
  ADC lsAy                      \ carry is clear: the BCS above did not take
  BCS dsd_scaled
  STA lsSy
  STX lsSx
  JMP dsd_add
.dsd_scaled

\ ---- signs: the integer part of a negative step is $FF ------
  LDA #0 : STA lsIx : STA lsIy
  LDA lsDx
  BPL dsd_xpos
  LDA #0 : SEC : SBC lsSx : STA lsSx    \ -frac, with $FF carried in
  LDA #&FF : STA lsIx
.dsd_xpos
  LDA lsDy
  BPL dsd_ypos
  LDA #0 : SEC : SBC lsSy : STA lsSy
  LDA #&FF : STA lsIy
.dsd_ypos
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
\ LAYER 7e — the player's bullet kills things
\ ============================================================
\ Here rather than in combat.asm because every byte it touches is a
\ droid-table byte and DrCollided, which it sits beside, is already
\ here. It calls out to main RAM for AddScore and alertLvl, which is the
\ direction the bank rule allows.
\
\ NO CollisionType MATRIX YET. The C64 dispatches every pair through
\ $6D6D, which earns its keep once bullets, explosions and enemy fire
\ can all hit each other — Layer 7f. With only player-fire-hits-droid
\ implemented, a direct test is smaller and says what it means.
\
\ THE BULLET IS TESTED BEFORE THE PAIR LOOP, not inside it. DrCollide
\ acts on ONE pair a pass, which the original does too, and a bullet
\ that loses the draw would pass straight through a droid. There is at
\ most one bullet and six droids, so testing it first costs six box
\ tests and removes the question.
DR_TYPE_BULLET = &20            \ droid types below this are real droids;
DR_TYPE_XPLODE = &40            \ these two are the mode markers

\ A bullet's box, smaller than a droid's: its opaque pixels are a streak
\ through the middle of a mostly empty 24 x 21. Tune by eye, as with
\ DR_COL_W/H.
BUL_COL_W = 12
BUL_COL_H = 10

.DrBulletHit
  LDA sprActive+PLY_FIRE_SLOT
  BEQ dbh_x
  LDX #PLY_FIRE_SLOT
  JSR DrSlotXY
  LDA dcX : STA dcX2
  LDA dcY : STA dcY2

  LDY #SPR_POOL_LAST
.dbh_loop
  STY dcInner
  LDA sprActive,Y
  BEQ dbh_next
  LDA drSlotOwner,Y
  BEQ dbh_next
  TAX
  LDA drType,X                  \ an explosion is not a target
  CMP #DR_TYPE_BULLET
  BCS dbh_next

  LDY dcInner
  TYA : TAX
  JSR DrSlotXY
  LDA dcX
  SEC : SBC dcX2
  JSR DrAbsA
  CMP #BUL_COL_W
  BCS dbh_next
  LDA dcY
  SEC : SBC dcY2
  JSR DrAbsA
  CMP #BUL_COL_H
  BCS dbh_next

  LDY dcInner                   \ a hit: the bullet is spent either way
  LDA drSlotOwner,Y
  STA drIdx
  LDA #0
  STA sprActive+PLY_FIRE_SLOT
  JMP DrPlyFireEnemy
.dbh_next
  LDY dcInner
  DEY
  BNE dbh_loop
.dbh_x
  RTS

\ ---- DrPlyFireEnemy — port of PlyFireEnemy ($1C0F) ---------
\ Damage is the weapon measured against the droid's TYPE, not its class:
\ a droid too strong for the weapon takes nothing at all, which is what
\ makes the early decks' weapons useless on the later ones and the whole
\ reason to transfer upward. The arithmetic is the original's, carry
\ included — the ADC #8 deliberately picks up the carry out of the
\ second ASL.
.DrPlyFireEnemy
  LDX drIdx
  LDA weaponType
  CLC
  ADC #2
  ASL A : ASL A
  ADC #8
  SEC
  SBC drType,X
  BMI dpf_x                     \ out of this weapon's league
  ASL A : ASL A
  CLC
  ADC #&10
  STA drDmg
  LDA drEnergy,X
  SEC
  SBC drDmg
  BEQ DrKillDroid
  BMI DrKillDroid
  STA drEnergy,X
  LDA #&11                      \ $1C36: hit but not killed, voice 2
  STA sndFx2
.dpf_x
  RTS

\ ---- DrKillDroid — port of KillDroid ($1C41) ---------------
\ Killing something makes the ship angrier by exactly the type killed,
\ and the score is by CLASS, so a 999 is worth ten times a 001.
.DrKillDroid
  LDA #&12                      \ $1C5A: the droid explosion, voice 2 —
  STA sndFx2                    \ and the disruptor's kills come through
  LDX drIdx                     \ here too, covering $23FB
  CLC
  LDA alertLvl
  ADC drType,X
  BCC dkd_alert
  LDA #&FF                      \ saturate rather than wrap
.dkd_alert
  STA alertLvl
  LDY drType,X
  LDX drCent,Y
  LDA cbNoScore                 \ $23ED: a droid's disruptor pays nobody
  BNE dkd_noscore
  LDA drShootScore,X
  JSR AddScore
.dkd_noscore
\ falls through

\ ---- DrExplodeSprite — port of ExplodeSprite ($1BCA) -------
\ The droid does not die and get replaced; its own table entry BECOMES
\ the explosion, keeping the sprite slot it already holds. Type $40 is
\ what DroidRun's dispatch reads as mode 2 from the next pass on, and
\ the drift it had is kept and decayed rather than zeroed.
.DrExplodeSprite
  LDX drIdx
  LDA drType,X
  CMP #DR_TYPE_BULLET
  BCS des_mark
  JSR DrRemoveShip              \ off the SHIP, not just this deck
.des_mark
  LDX drIdx
  LDA #DR_TYPE_XPLODE
  STA drType,X
  STA drEnergy,X                \ non-zero, or the compaction drops it
  LDY drSprNum,X
  BEQ des_x
  LDA #1          : STA sprKind,Y
  LDA #EF_EXPLODE : STA sprType,Y
  LDA #1          : STA sprActive,Y
.des_x
  RTS

\ ============================================================
\ DrExplode — mode 2, port of dMd2_explosion ($17F4)
\ ============================================================
\ Eleven frames, drifting on the dead droid's last speed with that speed
\ halved each pass, then the slot goes back to the pool.
.DrExplode
  JSR DrMove
  LDX drIdx
  LDA drSprNum,X
  BEQ dxp_dead
  JSR DrExpScreen
  BCS dxp_dead

  LDX drIdx                     \ next frame, or done
  LDY drSprNum,X
  LDA sprType,Y
  CLC
  ADC #1
  CMP #EF_EXPLODE + EF_EXPLODE_N
  BCS dxp_dead
  STA sprType,Y

\ Halve each speed, keeping its sign, and let -1 fall to 0 rather than
\ sticking there — $1826 does this with a ROL to recover the sign into
\ carry and a ROR to bring it back down.
  LDX drIdx
  LDA drSpdX,X : ROL A
  LDA drSpdX,X : ROR A
  CMP #&FF
  BNE dxp_sx
  LDA #0
.dxp_sx
  STA drSpdX,X
  LDA drSpdY,X : ROL A
  LDA drSpdY,X : ROR A
  CMP #&FF
  BNE dxp_sy
  LDA #0
.dxp_sy
  STA drSpdY,X
  RTS

.dxp_dead
  LDX drIdx
  LDA #0
  STA drEnergy,X                \ the compaction squeezes the entry out
  LDY drSprNum,X
  STA drSprNum,X
  BEQ dxp_x
  STA sprActive,Y               \ A is still 0
  STA sprKind,Y
  STA drSlotOwner,Y
.dxp_x
  RTS

\ ---- DrExpScreen — is the explosion still on screen? -------
\ Carry set = no. The same test DrScreen opens with, duplicated rather
\ than shared: DrScreen's copy runs into its slot allocation and its
\ sight line, neither of which an explosion wants, and the branches in
\ there are already at their limit.
.DrExpScreen
  LDX drIdx
  SEC
  LDA drPosYlo,X : SBC drOrgY
  STA drSy
  LDA drPosYhi,X : SBC drOrgY+1
  BNE dxs_off
  LDA drSy
  CMP #SPR_MAX_Y + 1
  BCS dxs_off

  SEC
  LDA drPosXlo,X : SBC drOrgX
  STA drSx
  LDA drPosXhi,X : SBC drOrgX+1
  STA drSx+1
  BMI dxs_off
  BEQ dxs_on
  CMP #1
  BNE dxs_off
  LDA drSx
  CMP #LO(DR_NEAR_X + 1)
  BCS dxs_off

.dxs_on
  LDY drSprNum,X
  LDA drSx
  AND #3
  STA sprShift,Y
  LDA drSx+1
  LSR A
  LDA drSx
  ROR A
  LSR A
  STA sprUnit,Y
  LDA drSy
  STA sprScrY,Y
  CLC
  RTS
.dxs_off
  SEC
  RTS

\ ============================================================
\ LAYER 7f — the droids shoot back
\ ============================================================
\ An enemy bullet is a DROID-TABLE ENTRY in mode 1, type $25, sharing
\ the same pool of six sprites as the droids — so a deck full of bullets
\ is a deck with fewer droids drawn, exactly as on the C64, and the
\ per-pass sprite cost does not grow.
\
\ NOT PORTED YET, and all of it deliberate: the disruptor (weapon 3, an
\ area effect rather than a bullet), EnemyFireEnemy's friendly fire, and
\ the bullet's per-pass colour flicker — that last one needs efAlt, which
\ is in bank 5, and a second per-entry field to carry the paired frame.

\ ---- DrEnemyFire — port of DoEnemyFire ($3450) -------------
\ Called only for a droid whose sprite is actually lit, which is the
\ C64's own gate: DoEnemyFire sits inside dMd0's `SpriteEna` arm, so a
\ droid that cannot see the player does not shoot at it.
.DrEnemyFire
  LDX drIdx
  LDY drType,X
  LDA drWeapon,Y
  BEQ def_x                     \ unarmed
  CMP #3
  BEQ def_disr                  \ the disruptor is not a bullet: $345C
  LDA drFireDelay,X
  BNE def_x
  LDA drCount
  CMP #DR_SLOTS
  BCS def_x                     \ no room in the table

\ THE RANDOM DRAW IS THE DIFFICULTY CURVE. `random AND $1F` against
\ shipLevel means ship 1 fires on 1 draw in 32 and ship 8 on 8 — the
\ same droids get steadily deadlier as the game goes on.
  JSR DrRandom
  AND #&1F
  CMP shipLevel
  BCS def_x

  JSR DrFindSlot
  BEQ def_x                     \ every sprite is busy
  STA drNewSlot
  JMP DrAddBullet
.def_x
  RTS
.def_disr
  JMP CbEnemyDisruptor          \ main RAM, with the rest of the weapon

\ ---- DrAddBullet — port of AddBullet ($34B5) ---------------
\ THE SPEED IS A DIRECTION, NOT A DISTANCE, and that is the whole point
\ of this routine. AddBullet reads deltaX/deltaY, which look like the
\ raw droid-to-player offset and are not: LineOfVisibility computed them
\ in CHARACTERS and then ran them through CalcDeltaAdd, which scales the
\ pair up together until the longer of the two sits in [128, 255]. So
\ `>> 5` turns a NORMALISED vector into a speed of 4-7 px an iteration
\ on the dominant axis, whatever the range.
\
\ Reading it as a raw distance — which is what this used to do, off the
\ pixel offset — makes a bullet fired from two characters away move one
\ pixel a pass, or none at all, and a point-blank shot is exactly when a
\ droid fires. That is BUGS.md #11: lasers that crawl, and that the
\ player can walk through because a bullet with speed 0 never arrives.
\
\ CHARACTERS, NOT PIXELS, for the same reason: the original aims at
\ character resolution, so a droid one cell above you fires straight up
\ rather than at a slight angle. Pixel deltas would make the droids
\ measurably better shots than they are on the C64.
\
\ THE SHIFT IS LOGICAL AND THE RESULT IS NEGATED. $34BE is `LSR A / ROR`
\ — not the arithmetic shift a signed value wants — and $3560 then takes
\ the two's complement of both speeds. deltaX is droid MINUS player, so
\ the negation is what points the bullet at him; the logical shift makes
\ a negative delta round the other way, so a bullet flying left travels
\ one pixel a pass faster than the mirror-image one flying right. Both
\ are the original's and both are kept.
.DrAddBullet
  LDX drIdx
  LDY drType,X                  \ $351F: the shot sounds as the firing
  LDA drWeapon,Y                \ droid's weapon class, voice 2 — the
  CLC                           \ mirror of DoFire's weaponType+1
  ADC #1
  STA sndFx2
  SEC                           \ droid - player, in characters: exactly
  LDA drCX : SBC plyCX : STA lsDx  \ what LineOfVisibility differences
  JSR DrAbsA
  STA lsAx
  SEC
  LDA drCY : SBC plyCY : STA lsDy
  JSR DrAbsA
  STA lsAy
  ORA lsAx
  BNE dab_aim                   \ standing on him: no direction to fire in,
  RTS                           \ and DrScaleDelta would never terminate
.dab_aim

  JSR DrScaleDelta              \ -> (lsSx,lsIx) / (lsSy,lsIy), normalised

  LDY #5                        \ >> 5, LOGICAL, as $34BE-$34EA is
.dab_shift
  LSR lsIx : ROR lsSx
  LSR lsIy : ROR lsSy
  DEY
  BNE dab_shift
  LDA #0 : SEC : SBC lsSx : STA dbSpdX  \ $3560: negate, so it flies at him
  LDA #0 : SEC : SBC lsSy : STA dbSpdY

\ Which of the four bullet sprites, from the chain of subtracts at
\ $353E — and it is NOT the symmetric rule it looks like. Worked
\ through, it comes to:
\
\   |dy| >  |dx|          vertical      (the |dx| < |dy| arm always
\                                        lands on _6, because the
\                                        second SBC can never borrow)
\   |dx| >= 2 * |dy|      horizontal
\   otherwise             diagonal, by the sign of dx EOR dy
\
\ so the vertical case is much wider than the horizontal one. The
\ previous version used the symmetric "twice the other" test on both
\ axes and drew a diagonal through most of that band.
\
\ Measured on the SPEEDS, not the deltas — $3526 reads droidSpdY/X —
\ so |dx| and |dy| here are 0-7. The signs are read after the negation
\ rather than before it, which changes nothing: both flip together.
  LDA dbSpdX : JSR DrAbsA : STA dbAx
  LDA dbSpdY : JSR DrAbsA : STA dbAy
  LDA dbAx
  SEC
  SBC dbAy
  BCC dab_vert                  \ |dx| < |dy|
  SEC
  SBC dbAy                      \ |dx| - 2*|dy|
  BCC dab_diag
  LDA #3 : BNE dab_frame        \ always: horizontal
.dab_diag
  LDA dbSpdX
  EOR dbSpdY
  BMI dab_diag2                 \ signs differ: the "/" diagonal
  LDA #0 : BEQ dab_frame        \ always
.dab_diag2
  LDA #2 : BNE dab_frame        \ always
.dab_vert
  LDA #1
.dab_frame
  STA drTmp
  LDX drIdx
  LDY drType,X
  LDA drWeapon,Y                \ weapon * 4 + direction, as DoFire indexes it
  ASL A : ASL A
  CLC
  ADC drTmp
  JSR CbBulletFrame             \ NOT inline: efBullet is in bank 5 and this
  STA drTmp                     \ code is in bank 4 — see that routine

\ The new entry goes in at drCount, which DroidsUpdate's loop has not
\ reached yet, so it runs this same pass — RunDroids does the same.
  LDX drCount
  LDA #DR_TYPE_BULLET + 5       \ $25: counts down to $20, invisible on the way
  STA drType,X
  STA drEnergy,X
  LDA drTmp   : STA drBulFrm,X
  LDA dbSpdX  : STA drSpdX,X
  LDA dbSpdY  : STA drSpdY,X
  LDA #0
  STA drState,X
  STA drVis,X
  STA drVisNew,X
  STA drFireDelay,X
  STA drShipIdx,X               \ a bullet is not on the ship's roster
  LDA drNewSlot : STA drSprNum,X
  TAY
  TXA
  STA drSlotOwner,Y             \ the slot answers to the bullet now
  LDA #0
  STA sprActive,Y               \ not drawn until it arms

  LDY drIdx                     \ copy the firing droid's position
  LDA drPosXlo,Y : STA drPosXlo,X
  LDA drPosXhi,Y : STA drPosXhi,X
  LDA drPosYlo,Y : STA drPosYlo,X
  LDA drPosYhi,Y : STA drPosYhi,X
  INC drCount

  LDX drIdx                     \ and the shooter's own cooldown
  LDA #26
  SEC
  SBC drType,X
  STA drFireDelay,X
  JSR DrRandom                  \ it also pauses briefly, 1-4 iterations
  AND #3
  CLC
  ADC #1
  LDX drIdx
  STA drState,X
  RTS

\ ============================================================
\ DrBullet — mode 1, port of dMd1_bullet ($1849)
\ ============================================================
\ The type counts $25 down to $20 and the bullet is INVISIBLE while it
\ does, which is the muzzle delay: four passes inside the droid that
\ fired it, so it does not appear to be born already overlapping. At $20
\ it arms, becomes visible and stays $20 until it meets a wall — and
\ then it becomes an explosion in place, which is why DrExplodeSprite
\ takes it without a special case.
.DrBullet
  JSR DrMove
  LDX drIdx
  LDA drSprNum,X
  BEQ dbl_dead
  JSR DrExpScreen               \ same placement and off-view test
  BCS dbl_dead

  LDX drIdx
  LDY drSprNum,X
  LDA drType,X
  CMP #DR_TYPE_BULLET
  BEQ dbl_live                  \ already armed
  DEC drType,X
  CMP #DR_TYPE_BULLET + 1       \ the value BEFORE the DEC
  BEQ dbl_arm
  LDA #0                        \ still in the muzzle: not drawn
  STA sprActive,Y
  BEQ dbl_wall                  \ always
.dbl_arm
  LDA #1 : STA sprKind,Y
  LDA drBulFrm,X : STA sprType,Y
.dbl_live
  LDA #1 : STA sprActive,Y

.dbl_wall
  LDX drIdx
  JSR DrCharPos
  LDA drCX : STA cellX
  LDA #0   : STA cellX+1
  LDA drCY : STA cellY
  JSR MapChar
  BMI dbl_hitwall
  RTS
.dbl_hitwall
  JMP DrExplodeSprite           \ it dies as an explosion, as $18B7 does

.dbl_dead
  JMP DrFreeEntry               \ the same three stores, and $1C82's
                                \ FreeSpriteTmp2 wants them too

\ ============================================================
\ DrHurtPlayer — the arms of DoCollision that cost the player energy
\ ============================================================
\ X is the droid, bullet or explosion he has touched. Called from
\ DrCollided's player arm, on the episode edge only — the C64 debounces
\ the damage with the same test it debounces the bounce with ($1A77),
\ or standing against a droid would drain you in half a second.
.DrHurtPlayer
  LDA drType,X
  CMP #DR_TYPE_BULLET
  BCC dhp_droid                 \ a real droid: the arm below
  CMP #DR_TYPE_XPLODE
  BCC dhp_bullet
  JMP dhp_xplode
.dhp_droid

\ ---- a droid: the stronger one hurts the weaker -------------
\ droidType(player) + 2 - droidType(other), and the sign says who came
\ off worse. The player's is halved and the droid's doubled, so ramming
\ something below you is much better business than being rammed.
  LDA drType
  CLC
  ADC #2
  SEC
  SBC drType,X
  BPL dhp_hurtdroid

  EOR #&FF                      \ the player lost: magnitude / 2
  LSR A
  STA drDmg
  LDA drEnergy
  SEC
  SBC drDmg
  BPL dhp_setply
  LDA #0
.dhp_setply
  STA drEnergy
  LDA #&19                      \ $1B17/$1B29: the player pays energy
  STA sndFx1
  RTS

.dhp_hurtdroid
  ASL A
  STA drDmg
  LDA drEnergy,X
  SEC
  SBC drDmg
  BEQ dhp_kill
  BMI dhp_kill
  STA drEnergy,X
  RTS
.dhp_kill
  LDA #&17                      \ $17EB: rammed to death, with the bonus
  STA sndFx1
  STX drIdx
  LDX drIdx
  CLC
  LDA alertLvl
  ADC drType,X
  BCC dhp_al
  LDA #&FF
.dhp_al
  STA alertLvl
  LDY drType,X
  LDX drCent,Y
  LDA drBumpScore,X
  JSR AddScore
  JMP DrExplodeSprite

\ ---- an enemy bullet ---------------------------------------
\ The C64 takes 8 or 16 depending on the bullet's sprite image ($1AF8),
\ which the disassembly flags as a type1/type2 bug. We take the lower of
\ the two and leave the quirk alone.
.dhp_bullet
  LDA drEnergy
  SEC
  SBC #8
  BCS dhp_bset
  LDA #0
.dhp_bset
  STA drEnergy
  LDA #&19                      \ same damage cue as the droid arm
  STA sndFx1
  STX drIdx                     \ the bullet is spent
  LDX drIdx
  LDA #0
  STA drEnergy,X
  LDY drSprNum,X
  STA drSprNum,X
  BEQ dhp_bx
  STA sprActive,Y
  STA sprKind,Y
  STA drSlotOwner,Y
.dhp_bx
  RTS

\ ---- standing in an explosion ------------------------------
.dhp_xplode
  LDA drEnergy
  SEC
  SBC shipLevel
  BCS dhp_xset
  LDA #0
.dhp_xset
  STA drEnergy
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

IF DEBUG_MAPGUARD
\ ============================================================
\ MapGuard — catch whatever is scribbling on the tile map
\ ============================================================
\ KC reported the map itself going bad in play, collision data and all,
\ on deck 8 when a droid fired — and it survives until the deck is
\ reloaded. Two attempts to reproduce it (37 seconds of play on deck 8
\ with droids firing) left the map byte-identical, so this exists to
\ catch the event rather than to hunt it by inspection.
\
\ THE PRIME SUSPECT IS ADJACENCY. The sprite save areas were seven pages
\ and ran &3000-&36FF, with &3700 free below the map at &3800. Layer 7c
\ made them eight, so they now end at &37FF and the map is the very next
\ byte — any save-area overrun that used to land in a free page now
\ lands on the map. That is a hazard whether or not it is this bug.
\
\ A snapshot goes to &3C00 at deck load — 1K of the free block above the
\ map — and a QUARTER of the map is compared each pass, so the cost is
\ about 4,000 cycles rather than 16,000 and a corruption is caught
\ within four passes. The FIRST hit is kept and checking stops, so the
\ readout shows where it began rather than wherever it has spread to.
\ **THE FONT AND THE GUARD NO LONGER BOTH FIT.** Layer 9 put the text
\ font at &3C00-&443F, and the only 1K left below the panel at &4800
\ starts at &4440 and runs 64 bytes past it. The two asserts below say
\ so rather than letting a debug build quietly scribble on the panel.
\ DEBUG_MAPGUARD is therefore OFF by default — BUGS.md #10 is fixed and
\ this was written for it. To use it again, move FONT_ADDR up to &4400
\ and MG_COPY down to &3C00: the font is only read by the panel engine
\ and nothing else cares where it is.
MG_COPY = &4400
ASSERT MG_COPY >= FONT_ADDR + FONT_BYTES
ASSERT MG_COPY + 1024 <= PANEL_ADDR

\ Zero page is full, so these borrow the startup bank-copy pointers —
\ dead from LoadDeck onwards, and the only other borrowers are the debug
\ readouts, which run at a different point in the pass.
mgSrc = swSrc
mgRef = swDst

.MapGuardSnap
  LDX #0
.mgs_loop
  LDA tilemap,X       : STA MG_COPY,X
  LDA tilemap+256,X   : STA MG_COPY+256,X
  LDA tilemap+512,X   : STA MG_COPY+512,X
  LDA tilemap+768,X   : STA MG_COPY+768,X
  INX
  BNE mgs_loop
  LDA #0
  STA mgHit
  STA mgPhase
  RTS

.MapGuardCheck
  LDA mgHit
  BNE mgc_x                     \ hold the first event
  LDA mgPhase
  AND #3
  TAY
  LDA mgQuarterLo,Y : STA mgSrc
  LDA mgQuarterHi,Y : STA mgSrc+1
  LDA mgCopyLo,Y    : STA mgRef
  LDA mgCopyHi,Y    : STA mgRef+1
  INC mgPhase
  LDY #0
.mgc_loop
  LDA (mgSrc),Y
  CMP (mgRef),Y
  BNE mgc_found
  INY
  BNE mgc_loop
.mgc_x
  RTS
.mgc_found
  STY mgOfs
  LDA mgPhase                   \ already incremented, so back one
  SEC
  SBC #1
  AND #3
  STA mgQtr
  LDA (mgSrc),Y : STA mgGot
  LDA (mgRef),Y : STA mgWant
  LDA #1
  STA mgHit
  RTS

.mgQuarterLo EQUB LO(tilemap), LO(tilemap+256), LO(tilemap+512), LO(tilemap+768)
.mgQuarterHi EQUB HI(tilemap), HI(tilemap+256), HI(tilemap+512), HI(tilemap+768)
.mgCopyLo    EQUB LO(MG_COPY), LO(MG_COPY+256), LO(MG_COPY+512), LO(MG_COPY+768)
.mgCopyHi    EQUB HI(MG_COPY), HI(MG_COPY+256), HI(MG_COPY+512), HI(MG_COPY+768)

.mgHit   EQUB 0                 \ 1 once the map has been seen to change
.mgPhase EQUB 0
.mgQtr   EQUB 0                 \ which 256-byte quarter it was in
.mgOfs   EQUB 0                 \ and where within it
.mgGot   EQUB 0                 \ what the map holds now...
.mgWant  EQUB 0                 \ ...against what the deck load put there
ENDIF

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

\ drVis, drVisNew and drBulFrm are in src/lowbss.asm, at &0C90: three
\ 14-byte arrays of pure state that cost the same to read from main RAM
\ as from the bank, and 42 bytes the bank did not have.
.losTurn     EQUB 1             \ the slot whose turn it is

.drSlotOwner SKIP SPR_SLOTS     \ droid index holding each sprite slot, 0 free

.drCount     EQUB 0             \ high-water mark; 1 means the deck is clear
.deckClear   EQUB 0             \ and THIS says the floor should be blue:
                                \ set by the compaction, cleared at the
                                \ top of LoadDeck. Layer-14 DECISION 6
.shipClear   EQUB 0             \ the C64's notInDeck, narrowed to the
                                \ one thing the port needs it for: the
                                \ main loop sees it, opens the ship-clear
                                \ screen and clears it. Layer-15 DECISION 4
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
.drDmg       EQUB 0             \ Layer 7e: damage worked out before it lands
.drNewSlot   EQUB 0
.dbSpdX      EQUB 0
.dbSpdY      EQUB 0
.dbAx        EQUB 0
.dbAy        EQUB 0
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

.dcIdxA      EQUB 0             \ DrCollided: the two droids behind the pair
.dcIdxB      EQUB 0
.dcModeA     EQUB 0             \ and their collision modes, 0-3
.dcModeB     EQUB 0
.dcArm       EQUB 0             \ 0 = the first party, 1 = the second
.dcHit       EQUB 0             \ what the player ran into, for the damage arm
.dcOuter     EQUB 0             \ DrCollide: the pair of slots in hand
.dcInner     EQUB 0
.dcX         EQUB 0
.dcY         EQUB 0
.dcX2        EQUB 0
.dcY2        EQUB 0
.drCollHit   EQUB 0             \ byte_0_6C: latched by DrReverse, cleared only
                                \ by a pass that finds no colliding pair at all
.nsdDeck     EQUB 0
.nsdBase     EQUB 0
.nsdLeft     EQUB 0
.shipNumDroids EQUB 0
.shipLevel   EQUB 1             \ ship 1; NextLevel raises it, capped at 8
.shipDroids  SKIP 256

\ ============================================================
\ Layer 10's bank-4 half: Capture's entry and FinishTransfer
\ ============================================================
\ The game itself is xfer.asm in BANK 7; the trampolines that page it in
\ are in main.asm. These two are everything the transfer needs from THIS
\ bank — the droid tables, the score tables, ReframeView — and they run
\ with the data bank paged, which is the resting state at both call
\ sites. Neither may page another bank: this code would vanish under
\ its own feet.

\ ---- XferEnter4 — Capture's front half ----------------------
\ Gather the two types into the main-RAM mirrors, stop the player, and
\ flatten the strip exactly as ConsoleOpen does and for the same reason:
\ the board draw wants a flat buffer shown from row 0. Then the deck's
\ palette makes way for the game's, and fire 3 moves down a row so the
\ 16th buffer row — normally the smooth scroll's hidden one — shows.
.XferEnter4
  LDX xferDroid
  LDA drType,X
  STA xfmTgtType
  LDA drType
  STA xfmPlyType
  LDA #0
  STA xfmResult
  STA xfmDone
  STA xSpd : STA xSpd+1
  STA ySpd : STA ySpd+1
  STA scrollS : STA scrollS+1
  STA line
  STA iline
  STA bandDo
  STA colCount
  JSR SetCRTCStart

  LDX #15
.xe4_pal
  LDA palPlay,X
  STA xfPalSave,X
  LDA palXfer,X
  STA palPlay,X
  DEX
  BPL xe4_pal

  LDA #HI(T1_I3X)               \ the high byte alone — see T1_I3X
  STA t1i3Hi
  LDA #1
  STA xferActive
  RTS

\ ---- XferExit4 — FinishTransfer1 ($21CF) and 2 ($2260) ------
\ Three arms, the original's: take the droid, drop back to a 001 with
\ the bump fine, or — already a 001 — burn out entirely. The caller
\ finishes with PanelSetup, which cannot be reached from this bank.
.XferExit4
  LDA xfmResult
  CMP #1
  BNE xx4_lost

  LDX xferDroid                 \ _ok: BECOME the target, keeping ITS
  LDA drEnergy,X                \ energy, and bank its shoot score
  STA drEnergy
  LDA xfmTgtType
  STA drType
  STA sprType+PLY_SLOT          \ the sprite the blitter draws for him
  TAY
  LDX drCent,Y
  LDA drShootScore,X
  JSR AddScore
  JSR XferInitDroid
  JMP xx4_consume

.xx4_lost
  LDA xfmPlyType
  BEQ xx4_burnt
  LDY xfmPlyType                \ had a droid: pay its bump score and
  LDX drCent,Y                  \ fall back to the 001 underneath
  LDA drBumpScore,X
  JSR SubScore
  LDA #0
  STA drType
  STA sprType+PLY_SLOT
  JSR XferInitDroid
  JMP xx4_consume

.xx4_burnt
  LDA #0                        \ a 001 that loses is finished —
  STA drEnergy                  \ CbCheckDeath takes it from here

\ FinishTransfer2: the target droid is consumed in EVERY outcome. Energy
\ 0 makes the compaction drop its table entry; the slot goes back to the
\ pool; DrRemoveShip takes it off the ship's roster for good.
.xx4_consume
  LDX xferDroid
  LDA #0
  STA drEnergy,X
  LDY drSprNum,X
  BEQ xx4_noslot
  STA sprActive,Y
.xx4_noslot
  LDX xferDroid
  STX drIdx
  JSR DrRemoveShip

  LDX #15                       \ and the machine goes back
.xx4_pal
  LDA xfPalSave,X
  STA palPlay,X
  DEX
  BPL xx4_pal
  LDA #0                        \ t1i3 is NOT put back here: the ReframeView
  STA xferActive                \ this ends on does it — see T1_I3X
  STA xferDroid
  STA xfmDone
  LDA #MM_MOBILE
  STA moveMode
  LDA #MM_DELAY
  STA mmDelay
  JMP ReframeView               \ and its RTS; PanelSetup is the caller's

\ ---- xferInitDroid ($223E) — the stats of the new ride ------
\ BuildDroidSprite is the sprType write above; the speed goes through
\ plyMaxLo/Hi, which is what CalcAxis clamps against — see player.asm.
.XferInitDroid
  LDA #&40
  STA maxEnergy
  LDY drType
  LDA drWeapon,Y
  STA weaponType
  LDX drSpeed,Y                 \ DSpeed_t, then PlayerSpeed_t — with all
  LDA plySpdTab,X               \ four entries mapped onto the camera's
  STA plyMaxHi                  \ dither-free speeds, as the 001's always was
  EOR #&FF
  CLC
  ADC #1
  STA plyNegHi
  LDA #0
  STA plyMaxLo
  STA plyNegLo
  RTS

\ PlayerSpeed_t ($6D97): 0,5,6,0,7,0,0,0,7 — indexed by DSpeed_t values
\ 1, 2, 4 and 8. EVERY entry is remapped here, because the camera steps
\ in 4s and 5, 6 and 7 all dither: the two 7s become CAM_TOPSPD (8) and
\ the 5 and the 6 become CAM_SLOWSPD (4). Both constants carry the
\ reasoning, in main.asm. This table is the whole deviation — the C64's
\ values are in the line above, and nothing else reads them.
.plySpdTab
  EQUB 0, CAM_SLOWSPD, CAM_SLOWSPD, 0, CAM_TOPSPD, 0, 0, 0, CAM_TOPSPD

\ ---- the transfer game's palette ---------------------------
\ Written INTO palPlay around the game, so the rupture needs no fourth
\ case. KC's choice (2026-08-17): blue background, BLACK for the board's
\ structure and unclaimed wire, yellow for the left side's pieces and
\ magenta for the right's. "Left" and "right" because the identity
\ tokens belong to the SIDES — $FF is always the left bus's colour —
\ and the human is whichever side the stick chose. [DECISION]
XF_PHYS_BG   = 4                \ blue
XF_PHYS_PLY  = 3                \ yellow  — logical 1, the $FF (left) set
XF_PHYS_CPU  = 5                \ magenta — logical 2, the $FC (right) set
XF_PHYS_NEUT = 0                \ black   — logical 3, structure/unclaimed
.palXfer
  PALENT  0, XF_PHYS_BG   : PALENT  1, XF_PHYS_BG
  PALENT  4, XF_PHYS_BG   : PALENT  5, XF_PHYS_BG
  PALENT  2, XF_PHYS_PLY  : PALENT  3, XF_PHYS_PLY
  PALENT  6, XF_PHYS_PLY  : PALENT  7, XF_PHYS_PLY
  PALENT  8, XF_PHYS_CPU  : PALENT  9, XF_PHYS_CPU
  PALENT 12, XF_PHYS_CPU  : PALENT 13, XF_PHYS_CPU
  PALENT 10, XF_PHYS_NEUT : PALENT 11, XF_PHYS_NEUT
  PALENT 14, XF_PHYS_NEUT : PALENT 15, XF_PHYS_NEUT
.xfPalSave
  EQUB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

\ ============================================================
\ CalcAxis — one axis of CalcSpeed
\   spd    = 16-bit signed speed, 8.8
\   axDir  = -1, 0 or +1
\ ============================================================
.CalcAxis
  LDA axDir
  BEQ ca_coast
  BMI ca_neg
  CLC                           \ accelerate positive
  LDA spd   : ADC #LO(PLY_ACCEL) : STA spd
  LDA spd+1 : ADC #HI(PLY_ACCEL) : STA spd+1
  JMP ca_clamp
.ca_neg
  SEC                           \ accelerate negative
  LDA spd   : SBC #LO(PLY_ACCEL) : STA spd
  LDA spd+1 : SBC #HI(PLY_ACCEL) : STA spd+1
  JMP ca_clamp

\ Coasting. Decelerate towards zero and STOP there rather than
\ overshooting into a crawl the other way — the sign of the high
\ byte flipping is the test, exactly as the C64 does it.
.ca_coast
  LDA spd+1
  BMI ca_coastneg
  ORA spd
  BEQ ca_clamp                  \ already stopped
  SEC
  LDA spd   : SBC #LO(PLY_DECEL) : STA spd
  LDA spd+1 : SBC #HI(PLY_DECEL) : STA spd+1
  LDA spd+1
  BPL ca_clamp
  JMP ca_stop
.ca_coastneg
  CLC
  LDA spd   : ADC #LO(PLY_DECEL) : STA spd
  LDA spd+1 : ADC #HI(PLY_DECEL) : STA spd+1
  LDA spd+1
  BMI ca_clamp
.ca_stop
  LDA #0
  STA spd
  STA spd+1
  RTS

\ The clamp is 16-bit. The C64's was a byte compare against the whole
\ pixel count, which it could afford because its top speed was a
\ whole number of pixels per iteration; ours is 3.5 per frame, so the
\ fraction is part of the limit rather than something to throw away.
\
\ Both sides of the negative compare are above &8000, so an unsigned
\ comparison orders them the same way a signed one would.
\ THE LIMIT IS A VARIABLE SINCE LAYER 10: the C64's MaxSpeed is set per
\ droid type — xferInitDroid ($223E) rewrites it at every transfer — so
\ the immediates became plyMaxLo/Hi, with the assembly-time values as
\ the 001's defaults. XferInitDroid and ccd_reset are the only writers.
.ca_clamp
  LDA spd+1
  BMI ca_clampneg
  CMP plyMaxHi
  BCC ca_x
  BNE ca_setmax
  LDA spd
  CMP plyMaxLo
  BCC ca_x
  BEQ ca_x
.ca_setmax
  LDA plyMaxLo : STA spd
  LDA plyMaxHi : STA spd+1
  RTS
.ca_clampneg
  CMP plyNegHi
  BCC ca_setmin
  BNE ca_x
  LDA spd
  CMP plyNegLo
  BCS ca_x
.ca_setmin
  LDA plyNegLo : STA spd
  LDA plyNegHi : STA spd+1
.ca_x
  RTS

.plyMaxLo EQUB LO(PLY_MAXSPD)
.plyMaxHi EQUB HI(PLY_MAXSPD)
.plyNegLo EQUB LO(PLY_MAXNEG)
.plyNegHi EQUB HI(PLY_MAXNEG)

\ ============================================================
\ CalcSpeed — both axes
\ ============================================================
\ CalcAxis works on one pair of zero page bytes, so each axis is
\ copied in and out. Twice a frame, for about 40 cycles.
.CalcSpeed
  LDA xSpd   : STA spd
  LDA xSpd+1 : STA spd+1
  LDA joyXDir : STA axDir
  JSR CalcAxis
  LDA spd   : STA xSpd
  LDA spd+1 : STA xSpd+1

  LDA ySpd   : STA spd
  LDA ySpd+1 : STA spd+1
  LDA joyYDir : STA axDir
  JSR CalcAxis
  LDA spd   : STA ySpd
  LDA spd+1 : STA ySpd+1
  RTS

\ ============================================================

\ ============================================================
\ The lift screen's bank-4 half: DoLift's mechanics
\ ============================================================
\ The display is liftview.asm in BANK 7; the trampolines are in
\ main.asm. What lives HERE is everything that reads the stop tables —
\ liftDeck/liftShaft are this bank's — plus the machine-state swap the
\ transfer established: palette, t1i3, the flatten. Same rule as
\ Layer 10's shims: this code must not page banks.

\ ---- LvEnter4 — from LiftViewEnter, the pass after fire -----
\ LiftFind already ran (LiftEnter set liftMode=1), so liftPos and
\ liftNum are set. ConsoleOpen's flatten, the lift palette in, fire 3
\ down a row for the 16th, and the selection mirrors seeded.
\ ============================================================
\ SndAmbient — the recurring cues: the hum, the alarm, the pulse
\ ============================================================
\ The port of two C64 sound tails, called once a pass from the main
\ loop's play path (beside DoAging, whose C64 twin held one of them):
\
\   DoAlertAndAging's _5 arm ($3E73): re-post the per-deck hum
\   (effect $18) whenever voice 2 is FULLY idle, on a spaced phase —
\   this is what makes the hum continuous, and why a poked one plays
\   once and stops.
\   AnimateDroids' tail ($3DE5-$3E31): the low-energy alarm (fx 8,
\   every 32 frames below 8 energy) and the transfer-mode pulse
\   (fx $1C, every 8 frames while moveMode is 0).
\
\ Cadences read gameTick (25 Hz passes) at half the C64's frame
\ masks, which lands on the same wall-clock rates. IN BANK 4 because
\ it reads the driver's own snActive, and main RAM is the region
\ with 50 bytes left. Runs only in play: the modal screens end their
\ pass before the call site, and overPhase is checked here.
.SndAmbient
  LDA overPhase                 \ the C64's game over runs RunGame alone,
  BNE sam_x                     \ so no ambient cues under the cloud
  LDA gameTick
  AND #&0F
  TAY                           \ the pass phase, held for all three cues
  CPY #8                        \ the hum's phase, offset from the alarm's
  BNE sam_1
  LDA snActive+1
  ORA sndFx2
  BNE sam_1
  LDA #&18
  STA sndFx2
.sam_1
  LDA drEnergy                  \ entry 0: the player. Low energy sounds
  CMP #8                        \ the alarm in EITHER mode — the C64's
  BCC sam_alarm                 \ $3DE5 tail, its two arms folded
  LDA moveMode
  BNE sam_x                     \ mobile and healthy: nothing
  TYA
  AND #3                        \ transfer mode: every 4 passes = the
  BNE sam_x                     \ C64's 8 frames
  LDA #&1C
  STA sndFx1
  RTS
.sam_alarm
  TYA                           \ every 16 passes = the C64's 32 frames
  BNE sam_x
  LDA #8
  STA sndFx2
.sam_x
  RTS

.LvEnter4
  LDA deck
  STA lvSelDeck
  LDA liftPos
  STA lvEntryPos
  LDA #1
  STA lvPrevFire                \ the entering press is still down
  STA prevLU                    \ and so may the step keys be: require
  STA prevLD                    \ a release before the first step
  LDA #0
  STA lvCommit
  STA lvLoad
  STA xSpd : STA xSpd+1
  STA ySpd : STA ySpd+1
  STA scrollS : STA scrollS+1
  STA line
  STA iline
  STA bandDo
  STA colCount
  JSR SetCRTCStart

  LDX #15
.lve_pal
  LDA palPlay,X
  STA xfPalSave,X               \ shared with the transfer: the two
  LDA palLift,X                 \ screens can never be up at once
  STA palPlay,X
  DEX
  BPL lve_pal

  LDA #HI(T1_I3X)               \ the high byte alone — see T1_I3X
  STA t1i3Hi
  LDA #2                        \ liftMode 2: the view has the machine
  STA liftMode
  LDA #&16                      \ $2696: the lift screen's entry chord,
  STA sndFx2                    \ voice 2
  RTS

\ ---- LvTick4 — keys and stepping, before the bank-7 redraw --
\ LiftControl's edge pairs, driving LvStep instead of a deck load; and
\ the fire edge that commits. ChangeDeck ($2705) is the model: step the
\ index, and the shaft-sentinel mismatch is the whole bounds test.
.LvTick4
  LDX #KEY_K
  JSR keydown
  BNE lvt4_upOff
  LDA prevLU
  BNE lvt4_notUp
  LDA #1
  STA prevLU
  LDA #&FF                      \ up the shaft: one index back
  JSR LvStep
  JMP lvt4_notUp
.lvt4_upOff
  LDA #0
  STA prevLU
.lvt4_notUp
  LDX #KEY_M
  JSR keydown
  BNE lvt4_dnOff
  LDA prevLD
  BNE lvt4_notDn
  LDA #1
  STA prevLD
  LDA #1
  JSR LvStep
  JMP lvt4_notDn
.lvt4_dnOff
  LDA #0
  STA prevLD
.lvt4_notDn
  LDX #KEY_L                    \ fire commits — an unmoved selection is
  JSR keydown                   \ the cancel, exactly the C64's shape
  BNE lvt4_fireOff
  LDA lvPrevFire
  BNE lvt4_x
  LDA #1
  STA lvPrevFire
  STA lvCommit
  RTS
.lvt4_fireOff
  LDA #0
  STA lvPrevFire
.lvt4_x
  RTS

\ ---- LvStep — LiftStep minus the load: selection only -------
.LvStep
  CLC
  ADC liftPos
  TAX
  LDA liftShaft,X
  CMP liftNum
  BNE lvst_x                    \ a sentinel: the end of the shaft
  STX liftPos
  LDA #&10                      \ $271B/$2729: one blip per deck passed,
  STA sndFx1                    \ on BOTH voices, as ChangeDeck posts it
  STA sndFx2
  LDA liftDeck,X
  STA lvSelDeck
.lvst_x
  RTS

\ ---- LvExit4 — commit: the machine back, and maybe a deck ---
\ LoadDeck cannot be called from this bank (it reaches PanelSetup, the
\ bank-6 trampoline), so lvLoad tells the main-RAM tail which ending
\ this is: a changed selection loads the chosen deck with liftPlace
\ set, an unchanged one just reframes what was always there.
.LvExit4
  LDX #15
.lvx_pal
  LDA xfPalSave,X
  STA palPlay,X
  DEX
  BPL lvx_pal
  LDA #0                        \ t1i3 is NOT put back here: both endings
  STA liftMode                  \ reach ReframeView — the same-deck arm
                                \ directly, the loading one through
                                \ LoadDeck — and that is where it goes
                                \ back. See T1_I3X
  LDA #MM_MOBILE
  STA moveMode
  LDA #MM_DELAY
  STA mmDelay
  LDX liftPos
  CPX lvEntryPos
  BEQ lvx_stay
  LDA liftDeck,X
  STA deck
  LDA #1
  STA liftPlace
  STA lvLoad
.lvx_stay
  RTS

\ The lift screen's palette: KC's choice — blue field, the emboss in
\ white and black, the lit deck's fill magenta (dark purple on the
\ C64). The art itself carries the colours — see export_sideview.py —
\ so these four are the whole look. [DECISION]
LV_PHYS_BG    = 4               \ blue
LV_PHYS_SHIP  = 7               \ white   — logical 1, the emboss's light side
LV_PHYS_DECK  = 0               \ black   — logical 2, its shadow side
LV_PHYS_SHAFT = 5               \ magenta — logical 3, the lit deck's fill
.palLift
  PALENT  0, LV_PHYS_BG    : PALENT  1, LV_PHYS_BG
  PALENT  4, LV_PHYS_BG    : PALENT  5, LV_PHYS_BG
  PALENT  2, LV_PHYS_SHIP  : PALENT  3, LV_PHYS_SHIP
  PALENT  6, LV_PHYS_SHIP  : PALENT  7, LV_PHYS_SHIP
  PALENT  8, LV_PHYS_DECK  : PALENT  9, LV_PHYS_DECK
  PALENT 12, LV_PHYS_DECK  : PALENT 13, LV_PHYS_DECK
  PALENT 10, LV_PHYS_SHAFT : PALENT 11, LV_PHYS_SHAFT
  PALENT 14, LV_PHYS_SHAFT : PALENT 15, LV_PHYS_SHAFT

\ ============================================================
\ The console's menu: conWaitInput ($2C63) and conJump_t
\ ============================================================
\ In THIS bank rather than bank 6 with the console it drives, because
\ bank 6 is full — and it can be, since everything it touches is main
\ RAM: the keys, the play buffer the marker draws into, conActive, and
\ the conShipReq flag ConsoleTick watches. The C64 walks consoleState
\ $80-$83 with the stick and dispatches the low nibble through
\ conJump_t on fire: 0 exit to the game, 1 droid info, 2 the deck
\ plan, 3 the ship's side view. Ours walks conSel 0-3 the same —
\ CLAMPED, not wrapped, as $2C6B/$2C8C do — and of the four, 0, 2
\ and 3 work; 1 is the droid database, not yet built, and the press
\ does nothing.
\
\ THE SELECTION IS THE ICON'S OWN COLOUR, as the C64's is, and there
\ is no marker bar. See src/consolesel.asm - the routine lives there
\ rather than here because it rides colourMap's alignment padding.

.ConMenuInit4                   \ from ConsoleEnter: top entry, edges
  LDA #0                        \ armed — the opening press is still down
  STA conSel
  STA conShipReq
  STA conDeckReq
  STA conDbReq
  LDA #1
  STA conMPrevL
  STA conPrevU
  STA conPrevD
\ AND THE MENU'S PALETTE, BEFORE ANYTHING IS DRAWN ON IT. ConsoleEnter
\ calls this first for exactly that reason — the console reads white text,
\ so logical 0 becomes the deck's text background, and the draw that
\ follows lands on the colours it will be seen in. Setting it afterwards
\ showed the menu in the deck's colours for as long as the draw took.
\ KC, 2026-08-24.
  JSR ConIconInk4               \ the icon colours BEFORE ConsoleOpen
                                \ draws them - KC 2026-08-24
  JMP SetTextPal                \ and its RTS

.ConMenu4
  LDX #KEY_K                    \ up the menu
  JSR keydown
  BNE cm4_upOff
  LDA conPrevU
  BNE cm4_notUp
  LDA #1
  STA conPrevU
  LDA conSel
  BEQ cm4_notUp                 \ clamped at the top, as $2C8C clamps
  DEC conSel
  LDA #&15                      \ $2CF6: the menu step's beep
  STA sndFx1
  JSR ConIconSel4               \ all four, from the new conSel
  JMP cm4_notUp
.cm4_upOff
  LDA #0
  STA conPrevU
.cm4_notUp
  LDX #KEY_M                    \ down the menu
  JSR keydown
  BNE cm4_dnOff
  LDA conPrevD
  BNE cm4_notDn
  LDA #1
  STA conPrevD
  LDA conSel
  CMP #3
  BCS cm4_notDn                 \ and at the bottom, as $2C6B does
  INC conSel
  LDA #&15                      \ and the same on the way down
  STA sndFx1
  JSR ConIconSel4               \ all four, from the new conSel
  JMP cm4_notDn
.cm4_dnOff
  LDA #0
  STA conPrevD
.cm4_notDn
  LDX #KEY_L                    \ fire: the conJump_t dispatch
  JSR keydown
  BNE cm4_lUp
  LDA conMPrevL
  BNE cm4_x
  LDA #1
  STA conMPrevL
  LDA conSel
  BNE cm4_notExit
  STA conActive                 \ entry 0: back to the game — A is 0
  LDA #&16                      \ $2CC3: the mode-change chord going out
  STA sndFx1
  RTS
.cm4_notExit
  LDA #&15                      \ $2C85: a page draw's beep, all three
  STA sndFx1
  LDA conSel
  CMP #3
  BEQ cm4_ship
  CMP #2
  BEQ cm4_deck
  LDA #1
  STA conDbReq                  \ entry 1: the droid database, in bank 7
  RTS
.cm4_deck
  LDA #1
  STA conDeckReq                \ entry 2: the deck plan
  JMP SetPalette                \ and its RTS. THE PLAN IS THE DECK, so it
                                \ wears the deck's colours — and set here,
                                \ on the press, rather than after ConDeck7
                                \ has drawn the whole page in the wrong ones
.cm4_ship
  LDA #1
  STA conShipReq                \ entry 3: the ship's side view
  RTS
.cm4_lUp
  LDA #0
  STA conMPrevL
.cm4_x
  RTS

\ ---- ConPageKeys4 — a page is up: fire returns --------------
\ con_ShipInfo's and con_DeckInfo's shared shape: the page is STATIC,
\ up/down do nothing, and fire goes back to the console main screen.
\ Edge triggered where the C64 oscillates on a held button. One
\ routine for both pages: only one flag is ever set, so clearing the
\ pair is which-page-agnostic and ConsoleTick keeps the distinction.
.ConPageKeys4
  LDX #KEY_L
  JSR keydown
  BNE csk_lUp
  LDA conMPrevL
  BNE csk_x
  LDA #1
  STA conMPrevL
  LDA #0
  STA conShipReq                \ ConsoleTick sees it and redraws the main
  STA conDeckReq
  JMP SetTextPal                \ and its RTS — the menu's colours back on
                                \ the press that leaves, before ct_back
                                \ redraws it
.csk_lUp
  LDA #0
  STA conMPrevL
.csk_x
  RTS

\ ---- the deck plan's way in and out -------------------------
\ con_DeckInfo ($3001) reads the level RLE on the C64; since Layer 13d
\ the port has no level RLE at all — the maps ship zx0-packed and the
\ depacker rebuilds the tile map at &4600, which is main RAM, static
\ after BuildLevel, and readable from bank 7 directly. So the staging
\ copy this shim used to make at SPR_SAVE is gone: ConDeck7 walks the
\ tile map in place, and this is only the display work.
\
\ THE PLAN IS 16 ROWS and so, since 2026-08-21, is the whole console:
\ ConsoleOpen sets t1i3 to T1_I3X for the session and ReframeView puts
\ it back on the way out, so the page needs no display work of its own
\ and ConDeckEnter4/ConDeckExit4 are gone with it — ConsoleTick calls
\ ConDeck7 directly. Decks 2, 10, 11 and 12 have map in row 15; the C64
\ shows it, and now so does every other console page.


\ ---- the ship page's palette, around LvShip7 ----------------
\ The side view's own colours in, the deck's back on return. The saved
\ copy shares xfPalSave with the transfer and the lift — no two of the
\ three can be up at once.
.ConShipEnter4
  LDX #15
.cse_pal
  LDA palPlay,X
  STA xfPalSave,X
  LDA palLift,X
  STA palPlay,X
  DEX
  BPL cse_pal
  RTS

.ConShipExit4
  LDX #15
.csx_pal
  LDA xfPalSave,X
  STA palPlay,X
  DEX
  BPL csx_pal
  RTS

.conSel     EQUB 0              \ the C64's consoleState low nibble, 0-3
.conShipReq EQUB 0              \ 0 idle / 1 fire on entry 3 / 2 page up
.conDeckReq EQUB 0              \ the same for entry 2, the deck plan
.conMPrevL  EQUB 0              \ the menu's own key edges — prevRet is
.conPrevU   EQUB 0              \ the weapon's, prevUp/Dn the debug hop's,
.conPrevD   EQUB 0              \ prevLU/LD the lift's
