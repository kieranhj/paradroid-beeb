\ ============================================================
\ lowcode2.asm — the low overlay's page-&0D half, at &0D60
\ ============================================================
\ 144 bytes of Econet workspace, mouse workspace and extended vector
\ table, none of which this machine has a use for. It is loaded and
\ copied by the same file and the same routine as src/lowcode.asm, and
\ the same rules apply — main.asm's LOW2_ADDR header has the argument,
\ including why &0D00-&0D5F and &0DF0-&0DFF are left alone.
\ It holds the disruptor's helpers. They are here rather than beside
\ CbDisruptor in combat.asm for one reason: the code image had 90 free
\ bytes and the routine wanted 245.

\ ---- CbDisrImmune — DisruptorImmune ($6E5B) ----------------
\ Z SET means immune. Five types: 8, 17, 18, 20 and 23 — which includes
\ both of the droids that carry the thing.
.CbDisrImmune
  LDY #4
.cdi_loop
  CMP cbDisrImm,Y
  BEQ cdi_x
  DEY
  BPL cdi_loop
  LDY #&FF                      \ not immune: Z clear on the way out
.cdi_x
  RTS

.cbDisrImm  EQUB 8, 17, 18, 20, 23

\ ============================================================
\ The two damage arms of the collision matrix
\ ============================================================
\ DrCollPair and its table are in bank 4 with the droid table they read.
\ These two are not, because the bank ran out — they are called from
\ DrCollAct there, and bank code may call main RAM freely. DrFreeEntry
\ has a second caller in DrBullet's own death arm.

\ ---- DrEnemyFireEnemy — port of $1BF6 ----------------------
\ FRIENDLY FIRE, which the original very much has: a droid's shot, and
\ a droid's explosion, hurt whatever else they touch. The damage is the
\ TARGET's own weakness — 2 * (40 - type) — so a 001 caught in a 999's
\ crossfire dies instantly and the 999 barely notices. Nothing scales it
\ by who fired, which is why a fight between two droids you have annoyed
\ is worth standing back and watching.
.DrEnemyFireEnemy
  LDX drIdx
  LDA #40
  SEC
  SBC drType,X
  ASL A
  STA drDmg
  LDA drEnergy,X
  SEC
  SBC drDmg
  BEQ dee_kill
  BMI dee_kill
  STA drEnergy,X
  RTS
.dee_kill
  JMP DrKillDroid

\ ---- DrFreeEntry — port of FreeSpriteTmp2 ($1C82) ----------
\ Zero energy is what the compaction in DroidsUpdate reads as dead, and
\ the slot goes back to the pool. Factored out of DrBullet's own death
\ arm, which is the same three stores.
.DrFreeEntry
  LDX drIdx
  LDA #0
  STA drEnergy,X
  LDY drSprNum,X
  STA drSprNum,X
  BEQ dfe_x
  STA sprActive,Y
  STA sprKind,Y
  STA drSlotOwner,Y
.dfe_x
  RTS





\ ---- CbEnemyDisruptor — DoEnemyFire's arm, $34A1 -----------
\ A 711 or a 742 that can see you fires one, on a draw against the ship
\ level — but from a mask of $7F rather than the bullet path's $1F, so
\ even on ship 8 it is a one-in-thirty-two event rather than one in
\ four. The owner is set NON-ZERO, which is what stops the player being
\ paid for whatever it kills.
.CbEnemyDisruptor
  JSR DrRandom
  AND #&7F
  CMP shipLevel
  BCS ced_x
  LDA disruptorCnt
  BNE ced_x
  LDA #DISR_FRAMES
  STA disruptorCnt
  STA disruptorOwner            \ $34B2 stores the same 4 into both
.ced_x
  RTS


\ ---- DrCollMode — SprNumber >> 5, off our own types --------
\ The C64 reads the sprite's number byte and shifts it five: a droid is
\ 0 (type < $20), an enemy bullet 1 ($25), an explosion 2 ($40) and the
\ player's shot 3 ($60). Our types are the same numbers, so the same
\ shift gives the same answer without a second table.
.DrCollMode
  LDA drType,X
  LSR A : LSR A : LSR A : LSR A : LSR A
  RTS

\ ============================================================
\ The debug readouts' shims — page bank 6 in, call, page back
\ ============================================================
\ The routines themselves are in src/dbgpanel.asm, in bank 6. These are
\ here rather than in the code image for the reason everything else in
\ this file is: the code image is the one region that is genuinely full,
\ and a shim is twenty bytes it does not have.
\
\ PanelTick's idiom exactly — and safe for the same reason: the
\ interrupt reads neither bank, and every call site is in the main loop
\ with SWRAM_DATA resting.

IF DEBUG_VSYNC OR DEBUG_POS
.DbgFrameCount
  PAGEBANK SWRAM_SPR2
  JSR Dbg6FrameCount
  PAGEBANK SWRAM_DATA
  RTS
ENDIF

IF DEBUG_POS
.DbgPosOut
  PAGEBANK SWRAM_SPR2
  JSR Dbg6PosOut
  PAGEBANK SWRAM_DATA
  RTS
ENDIF

IF DEBUG_ENERGY
\ THE MIRROR IS THE WHOLE REASON THIS IS NOT A BARE PAGEBANK. drType and
\ drEnergy are entry 0 of the droid table and live in BANK 4; read them
\ with bank 6 paged and you get the panel's artwork instead. Copy them
\ here, while the data bank is still in, and let the readout print the
\ copies. DEBUG_MAPGUARD's five bytes are in bank 4 too.
.DbgEnergyOut
  LDA drType   : STA dbgEnMirror+0
  LDA drEnergy : STA dbgEnMirror+1
IF DEBUG_MAPGUARD
  LDX #5                        \ mgHit..mgWant are six consecutive bytes,
.dbg_mg                         \ so copy the run and let the source table
  LDA mgHit,X                   \ step over mgPhase rather than skipping it
  STA dbgEnMirror+2,X           \ here
  DEX
  BPL dbg_mg
ENDIF
  PAGEBANK SWRAM_SPR2
  JSR Dbg6EnergyOut
  PAGEBANK SWRAM_DATA
  RTS
ENDIF
