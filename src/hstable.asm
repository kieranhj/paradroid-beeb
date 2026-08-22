\ ============================================================
\ hstable.asm — the high score itself, and nothing else
\ ============================================================
\ LAYER 11f, in SWRAM BANK 7. The high-score SCREEN is in the PARTITL
\ overlay (src/highscore.asm) because it runs outside the game and has
\ no business holding resident RAM. This is the part that cannot go with
\ it: PARTITL is loaded from disc every time it is wanted, so anything
\ in it is back to its assembled value at every title, and a high score
\ that forgets itself between games is not a high score.
\
\ BANK 7 IS THE ONE KIND OF RAM THAT REMEMBERS. GoTitle reloads PARAFNT,
\ PARTITL and PARALOW and nothing else, so a bank-7 variable keeps its
\ value from one game to the next without being saved anywhere. Twenty-
\ five bytes, and the overlay pages this bank in to reach them.
\
\ The defaults are the original's: $E70C is 00 00 68 09 and $E710 is
\ 00 00 65 02 — 6809 and 6502, Braybrook's joke — and the initials that
\ go with them are AEB and BAD, which the C64 keeps in the briefing text
\ rather than in a table, because only a NEW record ever writes them.
\
\ THE INITIALS ARE LETTER INDICES, 0-25 for A-Z and 26 for a space, not
\ glyph numbers: that is what GetInitial's own index is ($E56D counts
\ 0-$1A through CapitalAlpha_t), and it keeps this table independent of
\ how the overlay happens to number its alphabet.

.hsHigh   EQUB &00, &00, &68, &09
.hsHiIni  EQUB 0, 4, 1                  \ AEB
.hsLow    EQUB &00, &00, &65, &02
.hsLoIni  EQUB 1, 0, 3                  \ BAD

\ Set by IsDone when the 999 page is dismissed, cleared by the overlay
\ when it has run. It is what stops the entry firing at BOOT, where
\ TitleSeq runs the same sequence with a score of zero — which would
\ otherwise beat the low score and ask a player who has not played for
\ their initials. Zero here is the assembled value, so boot is safe by
\ construction.
.hsArmed  EQUB 0
