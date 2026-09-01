\ ============================================================
\ briefman.asm — the briefing's bank-5 half, beside its text
\ ============================================================
\ LAYER 11f. Assembled into the PARMAN block, after the record lists.
\ These routines run WITH BANK 5 PAGED — which is the briefing's
\ resting state — and exist because the PARBRF overlay at &0400 has a
\ HARD CEILING AT &0800: the page above it, &0800-&08FF, is the MOS's
\ sound workspace, channel buffers and printer buffer, and the MOS IRQ
\ writes into it while it still owns the machine (the title's loads
\ run under it). A PARBRF that spilled past &0800 was measured to die
\ exactly there: the code verified byte-perfect at load, and by the
\ first paint the MOS had chewed it and the CPU wandered into the
\ paged bank. So anything of the briefing's that does not have to be
\ main RAM lives here, in a bank with eleven K spare.
\
\ WHAT MAY LIVE HERE: code that touches only main RAM and THIS bank.
\ Bank code may read and write main RAM freely; what it must never do
\ is call into another bank, because paging itself out pulls the rug.
\ Everything below reads PARBRF's own state bytes (&04xx-&07xx labels,
\ resolved across the blocks) and the strip, and writes this bank's
\ records — nothing pages.
bmp = chp                       \ the record pointer, briefing.asm's brp

\ ---- the portrait's geometry, shared with briefing.asm ------
\ ON THE LEFT (KC, 2026-08-22), and it is the C64's own position:
\ BuildIntroSprites puts the briefing droid at sprite X = 40, which is
\ 16 px in from the visible edge — unit 4. Text columns 2-7; the score
\ table's text starts at column 10, so nothing overlaps.
BR_PO_UNIT = 4                  \ text columns 2-7: 48 px, the width
BR_PO_OFS  = BR_PO_UNIT * UNIT_BYTES
BR_PO_ROW0 = DB_IMG_ROW         \ PoDraw's own rows, unmoved
BR_PO_ROWS = 11                 \ 84 scanlines and the row they end in
BR_PO_SPAN = 12 * UNIT_BYTES    \ one row's slice of the rectangle

\ ============================================================
\ BmPatch — the live table into page 5's two lines
\ ============================================================
\ UpdateTextScore ($E5AC) moved to the read side [11f DECISION 7]: the
\ C64 writes the score into the packed text and the text persists;
\ ours is reloaded from disc each time, so the patch happens on the
\ fresh copy, before anything draws it. The layout is the original's:
\ eight BCD digits at glyph offsets 0-7 with leading zeros as spaces
\ (the last digit never blanked), initials at 11-13. BrTimeout has
\ already ferried bank 7's fourteen bytes into brSc and paged this
\ bank in; the records patched are THIS bank's, two pages back.
.BmPatch
  LDA #LO(br_hiscore+1)         \ +1: past the record's column byte
  STA bmp
  LDA #HI(br_hiscore+1)
  STA bmp+1
  LDX #0                        \ brSc: the high score's 4+3
  JSR BmPatchLine
  LDA #LO(br_loscore+1)
  STA bmp
  LDA #HI(br_loscore+1)
  STA bmp+1
  LDX #7                        \ and the low score's, by falling in
.BmPatchLine
  LDA #0
  STA brT2                      \ still in the leading zeros
  LDY #0
.bmp_byte
  LDA brSc,X                    \ one BCD byte, two digits
  PHA
  LSR A : LSR A : LSR A : LSR A
  JSR bm_dig
  PLA
  AND #&0F
  JSR bm_dig
  INX
  CPY #8
  BCC bmp_byte
  INY                           \ glyphs 8-10 are ' - ', left alone
  INY
  INY
.bmp_ini
  LDA brSc,X                    \ a letter index 0-26, 26 the space
  CMP #26
  BCC bmp_letter
  LDA #PN_SPACE                 \ which is ZERO, so no BNE-always here —
  JMP bmp_iput                  \ that mistake shipped once
.bmp_letter
  CLC
  ADC #PN_UPPER_A
.bmp_iput
  STA (bmp),Y
  INX
  INY
  CPY #14
  BCC bmp_ini
  RTS

.bm_dig                         \ A = the digit, Y = the glyph position
  BNE bmd_show
  LDA brT2                      \ a zero: blanked while leading, except
  BNE bmd_zero                  \ the last digit, which always shows
  CPY #7
  BEQ bmd_zero
  LDA #PN_SPACE                 \ ZERO — a BNE-always here never branches
  JMP bmd_put
.bmd_zero
  LDA #PN_DIGIT0
  BNE bmd_put                   \ always
.bmd_show
  STA brT
  LDA #1
  STA brT2
  LDA brT
  CLC
  ADC #PN_DIGIT0
.bmd_put
  STA (bmp),Y
  INY
  RTS

\ ============================================================
\ BmSnap — the freshly drawn portrait into SPR_SAVE
\ ============================================================
\ BrPortrait has had PoDraw render into the parked strip at unit 68,
\ rows BR_PO_ROW0..+10, and paged this bank back; the rectangle is
\ carried to SPR_SAVE — dead outside a game, LoadDeck rebuilds it —
\ so BmBand can put its rows back as the page paints and scrolls.
.BmSnap
  LDA #0
  STA brT2
.bms_row
  LDA brT2
  CLC
  ADC #BR_PO_ROW0
  TAX
  CLC
  LDA brRowBLo,X : ADC #LO(BR_PO_OFS) : STA swSrc
  LDA brRowBHi,X : ADC #HI(BR_PO_OFS) : STA swSrc+1
  LDX brT2
  LDA brPoLo,X : STA swDst
  LDA brPoHi,X : STA swDst+1
  LDY #BR_PO_SPAN-1
.bms_b
  LDA (swSrc),Y
  STA (swDst),Y
  DEY
  BPL bms_b
  INC brT2
  LDA brT2
  CMP #BR_PO_ROWS
  BCC bms_row
  RTS

\ ============================================================
\ BmBand — the portrait's slice of the row just painted
\ ============================================================
\ BrPaintRow tail-calls this after every row. On page 5, a row inside
\ the rectangle gets its 96-byte band copied back over columns 34-39 —
\ which is how the picture scrolls with the page. A plain copy, no
\ transparency: those columns are empty on every page-5 row (checked
\ against briefing.txt) and the picture's background is the page's
\ own black.
.BmBand
  LDA brPage
  CMP #BR_PAGES-1
  BNE bmb_x
  LDA brRow
  SEC
  SBC #BR_PO_ROW0
  BCC bmb_x
  CMP #BR_PO_ROWS
  BCS bmb_x
  TAX
  LDA brPoLo,X : STA swSrc
  LDA brPoHi,X : STA swSrc+1
  LDX brStrip
  CLC
  LDA brRowBLo,X : ADC #LO(BR_PO_OFS) : STA swDst
  LDA brRowBHi,X : ADC #HI(BR_PO_OFS) : STA swDst+1
  LDY #BR_PO_SPAN-1
.bmb_b
  LDA (swSrc),Y
  STA (swDst),Y
  DEY
  BPL bmb_b
.bmb_x
  RTS

\ ---- the snapshot's row bases -------------------------------
.brPoLo
  FOR n, 0, BR_PO_ROWS-1
    EQUB LO(SPR_SAVE + n * BR_PO_SPAN)
  NEXT
.brPoHi
  FOR n, 0, BR_PO_ROWS-1
    EQUB HI(SPR_SAVE + n * BR_PO_SPAN)
  NEXT

\ ============================================================
\ BmChatter — the briefing's soundtrack, Sound._chatter ($054A)
\ ============================================================
\ THE "TITLE CHATTER" IS THE BRIEFING'S. TitleLoop zeroes sndState at
\ $10E1 and only writes $11 at $115B — AFTER ShowTitle has returned —
\ so the C64's logo screen is silent and the burbling belongs to the
\ scrolling manual. ShowTitle's own wait ($2907) calls Sound every
\ field with the state still 0, which is why the driver is listed as
\ one of its callers. [11f DECISION 10]
\
\ Twenty lines of C64, on a counter that runs down every field:
\
\   AND $7F = 0   pick one of three blips by a random third and post
\                 it on voice 1 — a 125-tick downward zipper whose
\                 slide wraps mod 65536 every ten ticks or so
\   AND $3F = $22 or $30   post $10, the lift blip, on voice 2
\   AND $0F = 8   nudge voice 1's frequency slide by a signed random
\                 +-16. THIS is the chatter: it keeps changing the
\                 zipper's rate, so the burble never repeats
\
\ WHY THE WORK IS SPLIT ACROSS TWO FILES. The blips are effect records
\ and the driver reads records from bank 4, which had 15 bytes free
\ against the 33 the three of them need. So bank 4 holds ONE scratch
\ slot (sndFxChat) and the three real records live here, next to the
\ text; this half picks and copies, and BrChatter — main RAM, and so
\ allowed to page — lands the copy in the slot and posts it. The rule
\ in this file's header is intact: nothing below pages anything.
\
\ RANDOMNESS IS AN LFSR HERE, where the C64 read the voice-3
\ oscillator ($D41B). bank 4's DrRandom must stay one sequence for the
\ deck's sake, so the chatter has its own. [11f DECISION 13]
\
\ Returns, for BrChatter to act on with the data bank paged:
\   A = 0            nothing to do this field
\   A = SND_FX_CHAT  brChRec holds a record; land it and post it
\   A = $FF          nudge voice 1's slide by X
.BmChatter
  DEC brChCnt
  LDA brChSeed                  \ the LFSR advances every field, not
  ASL A                         \ per draw, so the two consumers below
  BCC bmch_nofb                 \ sample uncorrelated bytes
  EOR #&1D
.bmch_nofb
  STA brChSeed

  LDA brChCnt
  AND #&7F
  BNE bmch_mid

\ ---- every 128 fields: a new blip, $0552-$0567 --------------
  LDX #0                        \ the random third, on the C64's own
  LDA brChSeed                  \ thresholds
  CMP #&55
  BCC bmch_pick
  INX
  CMP #&AA
  BCC bmch_pick
  INX
.bmch_pick
  LDA bmChOff,X
  TAX
  LDY #0
.bmch_copy
  LDA brChatTab,X               \ this bank's records into PARBRF's
  STA brChRec,Y                 \ mailbox — main RAM, so it survives
  INX                           \ the page to bank 4
  INY
  CPY #BR_CHAT_PRE
  BNE bmch_copy
  LDA #SND_FX_CHAT
  RTS

.bmch_mid
  LDA brChCnt                   \ $0571-$057B: the lift blip, twice a
  AND #&3F                      \ 64-field cycle, on voice 2
  CMP #&22
  BEQ bmch_blip
  CMP #&30
  BNE bmch_nudge
.bmch_blip
  LDA #&10
  STA sndFx2                    \ main RAM: no paging needed
  LDA #0
  RTS

.bmch_nudge
  LDA brChCnt                   \ $057D-$059E: every 16 fields, walk
  AND #&0F                      \ the slide's high byte
  CMP #8
  BNE bmch_none
  LDA brChSeed
  BMI bmch_neg
  LSR A : LSR A : LSR A         \ 0..+15
  BPL bmch_del                  \ always: A <= 15
.bmch_neg
  SEC : ROR A                   \ SEC before each: the ones shifted in
  SEC : ROR A                   \ sign-extend it to -16..-1
  SEC : ROR A
.bmch_del
  STA brChRec                   \ the mailbox's first byte carries it —
  LDA #&FF                      \ BrChatter reads it with bank 4 up
  RTS
.bmch_none
  LDA #0
  RTS

.bmChOff
  EQUB 0, BR_CHAT_PRE, 2 * BR_CHAT_PRE

\ ---- state: only this file touches it -----------------------
.brChCnt  EQUB 0                \ the C64's snd_9C, counted down
.brChSeed EQUB 1                \ reseeded by BrRun; never zero

\ ============================================================
\ BmPalHide / BmPalReveal — the page paint, in invisible ink
\ ============================================================
\ KC, 2026-09-01, the screen-swap pass's briefing arm: the per-page
\ block paint was watchable — sixteen rows of text arriving over a
\ few fields. The deck screens hide their plots behind PalBlack, but
\ the briefing inherits whatever palette the last deck left in
\ palPlay, so black is wrong here: instead every logical takes
\ LOGICAL 0's OWN physical — text drawn in the background's colour is
\ invisible on it — and the reveal puts the saved sixteen back.
\ Bracketed around BrPagePaint (briefing.asm), which also swallows
\ the OLD page's text on the way in: it vanishes in one clean field,
\ the new page paints unseen, and the finished block appears in one
\ go.
\ THE HIDE WAITS TWO FIELDS before returning: palPlay reaches the
\ ULA at fire 1, and fieldCount is bumped at fire 3 — so the first
\ tick can arrive with the old colours still up (a write landing
\ between a field's fire 1 and its fire 3), and only the second
\ guarantees a fire 1 has run on the hidden table. Without it the
\ paint's first rows show for a field, flick off, and reappear.
\ Plain fieldCount polling, not BrWaitField: its chatter and CTRL+R
\ hooks have no business inside the paint bracket.
\ IN THIS BANK for the ceiling reason at the top of this file: the
\ bracket costs PARBRF six bytes, the machinery none.
.BmPalHide
  LDA palPlay                   \ logical 0's entry: the low nibble is
  AND #&0F                      \ its physical, ULA-inverted — reused
  STA bmPalTmp                  \ as-is under all sixteen selectors
  LDX #15
.bmph_loop
  LDA palPlay,X
  STA bmPalSave,X
  TXA
  ASL A : ASL A : ASL A : ASL A
  ORA bmPalTmp
  STA palPlay,X
  DEX
  BPL bmph_loop
  LDA fieldCount
  CLC
  ADC #2
.bmph_wait
  CMP fieldCount
  BNE bmph_wait
  RTS

.BmPalReveal
  LDX #15
.bmpr_loop
  LDA bmPalSave,X
  STA palPlay,X
  DEX
  BPL bmpr_loop
  RTS

.bmPalSave SKIP 16
.bmPalTmp  EQUB 0

\ ============================================================
\ BmStartDown — Z set when FIRE or TRANSFER is down
\ ============================================================
\ KC, 2026-09-01 [11f DECISION 16]: either button leaves the briefing
\ into the game — they are the two thumbs a player rests on. One
\ helper because BrRun asks in four loops; here rather than PARBRF for
\ the ceiling reason at the top of this file, and the shrunken call
\ sites pay PARBRF back. Called only from those loops, whose resting
\ bank is this one; KeyDownIx and keyTab are main RAM.
.BmStartDown
  LDX #CTL_FIRE
  JSR KeyDownIx
  BEQ bmsd_x
  LDX #CTL_XFER
  JSR KeyDownIx
.bmsd_x
  RTS
