\ ============================================================
\ dbgkill.asm — DEBUG_KILL's clear-the-deck key, in bank 4
\ ============================================================
\ A FILE OF ITS OWN FOR THE REASON src/consolesel.asm IS: bank 4
\ had 45 bytes and this wanted about as many again as the cleared-
\ deck floor left it. Included BEFORE colours.asm, so what remains
\ of colourMap's ALIGN &100 padding absorbs it and the bank does
\ not grow -- read consolesel.asm's header for the whole rule, and
\ for the 162-byte limit the two of them now share.
\
\ It sits outside droid.asm so that a build without the flag leaves
\ no hole in the middle of the droid code.

IF DEBUG_KILL
\ ============================================================
\ DbgKill4 — DEBUG_KILL: C kills every droid on the deck
\ ============================================================
\ KC, 2026-08-24, to exercise the cleared-deck floor without
\ having to shoot a deck empty.
\
\ IT DRIVES THE REAL KILL PATH, one droid at a time through
\ DrKillDroid, rather than zeroing drEnergy behind its back. That
\ is the point of it: the explosion sound, the alert rise, the
\ score by class, DrRemoveShip and the sprite slot all happen
\ exactly as they do when you shoot the thing, so what it tests is
\ the mechanism and not a shortcut past it. The entries become
\ explosions and the compaction reaps them a few passes later,
\ which is what drops drCount to 1 and fires the colour change.
\
\ SLOT 0 IS THE PLAYER and the loop stops above it. keydown is main
\ RAM and this is bank 4, which is the legal direction.
.DbgKill4
  LDX #KEY_CTRL                 \ CTRL+C, 2026-08-31: see DbgRedrawKey.
  JSR keydown                   \ dk_off is the key-up path and clears
  BNE dk_off                    \ dkPrev, so the press edge rearms
  LDX #KEY_C
  JSR keydown
  BNE dk_off
  LDA dkPrev                    \ one clear per press, not per pass
  BNE dk_x
  LDA #1
  STA dkPrev
  LDX drCount
.dk_loop
  DEX
  BEQ dk_x                      \ slot 0 is the influence device
  STX drIdx                     \ DrKillDroid takes its index there
  JSR DrKillDroid
  LDX drIdx                     \ it clobbers X, so read it back
  JMP dk_loop
.dk_off
  LDA #0
  STA dkPrev
.dk_x
  RTS
.dkPrev EQUB 0
ENDIF
