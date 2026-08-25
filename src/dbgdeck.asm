\ ============================================================
\ dbgdeck.asm — DEBUG_DECK's free deck hop, in bank 4
\ ============================================================
\ A FILE OF ITS OWN FOR THE REASON src/dbgkill.asm IS, and it is the
\ same trade one size up: the arm was 69 bytes of &1100-&3000, which is
\ the tightest region in the machine, and Layer 15's ship-clear arm
\ needed eighteen of them. Moved here it costs BANK 4 those 69 out of
\ the 105 the Layer 15 space pass found, and main RAM gets 66 back --
\ the JSR that replaces it is the only thing left behind.
\ Layer-15 DECISION 1.
\
\ IT IS NOT IN colourMap's ALIGN PADDING, and that is deliberate:
\ consolesel.asm and dbgkill.asm have spent all but 17 of the 162, and
\ 69 more would push the ALIGN past the page and cost 256 at a stroke
\ (see CLAUDE.md's padding note). So this is assembled AFTER the align,
\ where it simply spends the bank's own free space.
\
\ NOTHING ABOUT THE ARM CHANGED. It is the same instructions in the same
\ order, and it works from here because both halves of what it touches
\ already reach across: keydown is main RAM, which bank code may call
\ freely, and LoadDeck is this bank's -- the old site called it from
\ main RAM only because SWRAM_DATA is the main loop's resting state.
\
\ WHERE IT IS CALLED FROM is unchanged too: the same point in the pass,
\ after AnimPaint and inside the window the level draw just used.

IF DEBUG_DECK
\ ============================================================
\ DbgDeck4 — UP and DOWN hop one deck, no lift
\ ============================================================
\ Deck keys are edge triggered: one press steps one deck however long it
\ is held. A blocking wait-for-release deadlocks if the other deck key
\ goes down before the first is released.
\
\ UP and DOWN belong to the lift while it has the controls, so the
\ liftMode test is part of the block rather than around it: nothing else
\ in the pass wants either key, and a build without the hop should not
\ be reading them at all. Two OSBYTEs a pass.
.DbgDeck4
  LDA liftMode                  \ entering the lift: the debug hop keeps
  BNE dd_notDn                  \ its hands off the deck this pass

  LDX #KEY_UP
  JSR keydown
  BNE dd_upOff
  LDA prevUp
  BNE dd_notUp
  LDA #1 : STA prevUp
  LDA deck
  BEQ dd_notUp
  DEC deck
  JSR LoadDeck
  JMP dd_notUp
.dd_upOff
  LDA #0 : STA prevUp
.dd_notUp

  LDX #KEY_DOWN
  JSR keydown
  BNE dd_dnOff
  LDA prevDn
  BNE dd_notDn
  LDA #1 : STA prevDn
  LDA deck
  CMP #NUM_DECKS-1
  BCS dd_notDn
  INC deck
  JSR LoadDeck
  JMP dd_notDn
.dd_dnOff
  LDA #0 : STA prevDn
.dd_notDn
  RTS
ENDIF
