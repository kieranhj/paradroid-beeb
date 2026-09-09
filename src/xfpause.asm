\ ============================================================
\ xfpause.asm — the panel line, restored after a pause
\ ============================================================
\ SWRAM BANK 7, and BEHIND plandata.asm's ALIGN on purpose — the same
\ rule as xfericon.asm next door, whose header states it: everything
\ assembled in FRONT of that ALIGN rides its padding for nothing, and
\ one byte past the pad rolls it a whole page and costs the bank 256.
\ This block is 37 bytes against a 33-byte pad, so it was 4 bytes over
\ and the bank overflowed — measured, on the first build of it. That
\ is the only reason it is not at the foot of xfer.asm with the rest
\ of the panel-line engine it calls.
\
\ BUGS.md #24 (KC, 2026-09-07): pausing inside the transfer game and
\ letting go posted "Transfer" over the board's own word.
\
\ DoPause paints "Pause" into the mode-word field and its exit repaints
\ that field from panel.asm's pnTxtTab, indexed by the game's mode. That
\ is right for the deck, the weapon and the console. It is positively
\ WRONG for the two screens that write the field themselves and are in
\ no table: with a transfer running the mode is still 2, so the repaint
\ posted the generic "Transfer" over "Colour? 88", and the line stayed
\ wrong until the game next wrote it for itself.
\
\ THE OWNER REPAINTS — the rule settled everywhere else on the no-load
\ branch. Both owners live in this bank, so DoPause pages once either
\ way and the choice is made here rather than at the call site.
\
\ NOT THE THIRD OWNER, and that is deliberate: IsStart posts "Captured"
\ into the same field for the two information screens in front of the
\ board, where xferActive is still 0 and liftMode is 0, so DoPause does
\ not route here at all. BUGS.md #24 carries it as the remaining case.

.XfPauseWord
  LDA liftMode                  \ main RAM, and 2 is the side view up
  CMP #2
  BNE XfPanelWord
  JMP LvPanelWord               \ the lift's "Lift" — liftview.asm split
                                \ a label off LvStart7b's panel half for
                                \ this, which is all it cost

\ ---- the transfer's own word ---------------------------------
\ Whatever XfMessage last posted, and XfMessage ALREADY REMEMBERS IT:
\ it writes the pointer into its own xmg_get before walking the string,
\ so reading that operand back costs nothing and covers every phase —
\ "Colour?" and "Finish" through the two clocked ones, both verdicts
\ and the tie's "Short circuit".
.XfPanelWord
  JSR XfTextClear
  LDA xmg_get+1
  LDY xmg_get+2
  JSR XfMessage

\ ---- and the countdown, only where there is one --------------
\ XF_COL_TIME is inside the eleven cells XfTextClear just blanked, so
\ the digits went with the word. XF_PH_SELECT and XF_PH_PLAY are the
\ only phases that put any there — 1 and 2, hence the range test — and
\ the verdicts and the tie show the word alone, as the C64 does.
  LDA xfPhase
  BEQ xpw_x                     \ 0, XF_PH_RELEASE: nothing clocked yet
  CMP #XF_PH_PLAY+1
  BCS xpw_x                     \ END and REPLAY: the verdict alone
  JMP XfTimeText                \ tail: its RTS is ours
.xpw_x
  RTS
