\ ============================================================
\ briefman.asm — the briefing's bank-5 half, beside its text
\ ============================================================
\ LAYER 11f. Bank-resident since no-load step 5; it was in PARMAN, a
\ disc file loaded over this bank for the briefing.
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
ASSERT BR_PO_UNIT == 4                  \ text columns 2-7: 48 px, the width
ASSERT BR_PO_OFS  == BR_PO_UNIT * UNIT_BYTES
ASSERT BR_PO_ROW0 == 3          \ PoDraw's own rows, unmoved. It was
                                \ `= DB_IMG_ROW` until this file went
                                \ bank-resident; main.asm's header owns
                                \ it now and condb.asm checks it
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
  LDA #LO(BR_HISCORE+1)         \ +1: past the record's column byte
  STA bmp
  LDA #HI(BR_HISCORE+1)
  STA bmp+1
  LDX #0                        \ brSc: the high score's 4+3
  JSR BmPatchLine
  LDA #LO(BR_LOSCORE+1)
  STA bmp
  LDA #HI(BR_LOSCORE+1)
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


\ ============================================================
\ BmDepackPrep — set up the depack of brPage's row lists
\ ============================================================
\ no-load step 5. The briefing's text is five ZX0 streams distributed
\ across the banks by the table below; nothing spans a bank and each
\ depacks whole into BR_RECS. THIS HALF IS HERE AND THE PAGING IS
\ BrDepack's, in PARBRF, because code in a bank cannot page another
\ bank in without swapping itself out — so all this may do is fill in
\ src and mapptr and hand the bank number back in A.
\ The table holds SLOT indices, not bank numbers: PARSWR probes for the
\ four banks at boot and they are not assumed to be 4-7 (Layer 13b).
.BmDepackPrep
  LDX brPage
  LDA bmStrLo,X    : STA src
  LDA bmStrHi,X    : STA src+1
  LDA #LO(BR_RECS) : STA mapptr
  LDA #HI(BR_RECS) : STA mapptr+1
  LDA bmStrSlot,X
  TAX
  LDA swBank,X                  \ main RAM, readable with any bank up
  RTS

\ Where each page's stream lives. WHICH BANK IS NOT ARBITRARY: this
\ bank is kept for keyredef's 776 and the briefing's own code, and what
\ was left then decided the other three -- docs/no-load.md 17.
.bmStrSlot
  EQUB SWRAM_SPR2               \ page 1
  EQUB SWRAM_XFER               \ page 2, the largest
  EQUB SWRAM_SPR                \ page 3
  EQUB SWRAM_SPR                \ page 4
  EQUB SWRAM_SPR2               \ page 5, whole again since 2026-09-09
.bmStrLo
  EQUB LO(brStream_0), LO(brStream_1), LO(brStream_2)
  EQUB LO(brStream_3), LO(brStream_4)
.bmStrHi
  EQUB HI(brStream_0), HI(brStream_1), HI(brStream_2)
  EQUB HI(brStream_3), HI(brStream_4)

\ ============================================================
\ BmRowScan — the two pointer tables, from the page itself
\ ============================================================
\ The streams carry the row lists and NOTHING ELSE. Shipping the
\ 114-byte pointer pair inside each one was measured at 2,798 packed
\ against 2,466, so the five pages pay 332 bytes to save this loop
\ (KC, 2026-09-09; docs/no-load.md 15c).
\ THE WALK IS UNAMBIGUOUS because the record format already reserves
\ its sentinels: $FF ends a row, $FE ends a record, and neither a
\ column byte (42 at most) nor a glyph index (107 at most) can reach
\ either. Fifty-seven rows over ~1,000 bytes, once per page turn, on a
\ modal screen where the depack in front of it costs more.
\ tools/verify_brstreams.py runs this same walk in Python over every
\ emitted stream and checks all 285 pointers against beebasm's own.
.BmRowScan
  LDA #LO(BR_RECS) : STA bmp
  LDA #HI(BR_RECS) : STA bmp+1
  LDX #0
  LDY #0                        \ bmp is advanced, so Y stays 0 and a
.bmrs_row                       \ long row cannot outrun an 8-bit index
  LDA bmp   : STA BR_BUF,X
  LDA bmp+1 : STA BR_BUF+BR_ROWS,X
.bmrs_byte
  LDA (bmp),Y
  INC bmp
  BNE bmrs_1
  INC bmp+1
.bmrs_1
  CMP #&FF
  BNE bmrs_byte
  INX
  CPX #BR_ROWS
  BCC bmrs_row

\ ...and the score line, on the one page that carries it. It has to be
\ here rather than at the briefing entry because the record only exists
\ while its page is depacked; brSc was ferried across once, by
\ BrFerryScores.
  LDA brPage
  CMP #BR_SCORE_PAGE
  BNE bmrs_nosc
  JSR BmPatch

\ ...and the six key fields, on the page that carries THEM — issue
\ #20, and the same argument: the record is the arena's and only
\ lives as long as its page. BmPatchKeys reads keyTab, which is the
\ code image's and outlives everything.
.bmrs_nosc
  LDA brPage
  CMP #BR_KEY_PAGE
  BNE bmrs_x
  JMP BmPatchKeys
.bmrs_x
  RTS


\ ============================================================
\ THE KEY NAMES — shared by CTRL+R and the briefing's page 1
\ ============================================================
\ ALL OF THIS WAS keyredef.asm's UNTIL 2026-09-12 (issue #20). It has
\ to be HERE, resident in the bank, because the redefine screen is a
\ ZX0 stream that depacks over BR_RECS — so while a briefing page is
\ up the screen does not exist, and BmPatchKeys below needs to name a
\ key with the page in front of it. The redefine screen calls in from
\ main RAM with this bank paged, which is what it already did for
\ BrChar and brExtra; nothing here pages anything.
\ ============================================================
\ BmKrAscii — A = ASCII, out = glyph index
\ ============================================================
\ PnAscii, transcribed. Bank 6 owns the original and only one bank is
\ visible at a time; this is the same duplication DbGlyph is. Anything
\ unmapped comes out as a space rather than as a wild index.
.BmKrAscii
  CMP #'a'
  BCC bka_upper
  CMP #'z'+1
  BCS bka_bad
  SEC : SBC #'a'
  CLC : ADC #PN_LOWER_A
  RTS
.bka_upper
  CMP #'A'
  BCC bka_digit
  CMP #'Z'+1
  BCS bka_bad
  SEC : SBC #'A'
  CLC : ADC #PN_UPPER_A
  RTS
.bka_digit
  CMP #'0'
  BCC bka_punct
  CMP #'9'+1
  BCS bka_punct
  SEC : SBC #'0'
  CLC : ADC #PN_DIGIT0
  RTS
.bka_punct
  CMP #'.'
  BNE bka_dash
  LDA #PN_DOT
  RTS
.bka_dash
  CMP #'-'
  BNE bka_colon
  LDA #PN_DASH
  RTS
.bka_colon
  CMP #':'
  BNE bka_bad
  LDA #PN_COLON
  RTS
.bka_bad
  LDA #PN_SPACE
  RTS

\ ============================================================
\ bmKeyChar — internal key number &10-&7F -> how to name it
\ ============================================================
\ THE MATRIX, ROW BY ROW. An entry is either a printable ASCII code
\ (>= 33, printed as itself), 1-10 for f0-f9, 11 and up for a name in
\ bmKrNames, or 0 for "this key cannot be bound".
\
\ ZERO NOW MARKS ONLY THE HOLES: columns 10-15 do not exist in the
\ matrix at all. The nine punctuation keys — ^ _ [ ] @ ; , / \ — were
\ zeros until 2026-09-01, refused because the shared glyph set cannot
\ DRAW them; KC ruled that too many ('/' is a common fire button), so
\ they carry spelled-out names from bmKrNames instead, exactly as
\ Space and Return always have. Every physical key &10-&7F is
\ bindable now; SHIFT (internal 0) is bindable through BmKrChar's
\ special case, and the only refusals left are ESCAPE (the game's
\ self-destruct, and this screen's own cancel) and CTRL (never
\ scanned — it gates the pause, the mute, the volume and the debug
\ keys). [11f DECISION 15, revised]
\
\ THE LAYOUT IS CONFIRMED BY OUR OWN CONSTANTS, not recalled: KEY_Z,
\ KEY_X, KEY_K, KEY_M, KEY_L, KEY_SPACE, KEY_P, KEY_Q, KEY_R, KEY_C,
\ KEY_W, KEY_LBRK, KEY_RBRK, KEY_UP, KEY_DOWN and KEY_ESCAPE all EOR
\ &FF to exactly the positions below.
.bmKeyChar
  EQUB 'Q', '3', '4', '5', 5, '8', 8, '-', 24, 21  \ &10: Q 3 4 5 f4 8 f7 - ^ LEFT
  EQUB 0, 0, 0, 0, 0, 0                            \ columns 10-15: no key
  EQUB 1, 'W', 'E', 'T', '7', 'I', '9', '0', 25, 20 \ &20: f0 W E T 7 I 9 0 _ DOWN
  EQUB 0, 0, 0, 0, 0, 0
  EQUB '1', '2', 'D', 'R', '6', 'U', 'O', 'P', 26, 19 \ &30: 1 2 D R 6 U O P [ UP
  EQUB 0, 0, 0, 0, 0, 0
  EQUB 17, 'A', 'X', 'F', 'Y', 'J', 'K', 28, ':', 12  \ &40: CAPS A X F Y J K @ : RETURN
  EQUB 0, 0, 0, 0, 0, 0
  EQUB 18, 'S', 'C', 'G', 'H', 'N', 'L', 29, 27, 13   \ &50: SHFTLK S C G H N L ; ] DELETE
  EQUB 0, 0, 0, 0, 0, 0
  EQUB 15, 'Z', 11, 'V', 'B', 'M', 30, '.', 31, 14    \ &60: TAB Z SPACE V B M , . / COPY
  EQUB 0, 0, 0, 0, 0, 0
  EQUB 16, 2, 3, 4, 6, 7, 9, 10, 32, 22               \ &70: ESC f1 f2 f3 f5 f6 f8 f9 \ RIGHT
  EQUB 0, 0, 0, 0, 0, 0

\ ---- the one key below the table's floor --------------------
\ X = internal number -> A = the char code, Z set on unbindable.
\ SHIFT is internal 0 and the table starts at &10, so the two callers
\ (the accept test and BmKrShow) come through here rather than index
\ &10 below the label.
.BmKrChar
  CPX #0
  BNE bkc_tab
  LDA #23                       \ SHIFT: its name
  RTS
.bkc_tab
  LDA bmKeyChar-&10,X
  RTS

\ Codes 11 up, in order, each terminated. ESCAPE's entry is here for
\ completeness only — bkr_wait catches it before the table is read.
.bmKrNames
  EQUS "Space"   : EQUB 0        \ 11
  EQUS "Return"  : EQUB 0        \ 12
  EQUS "Delete"  : EQUB 0        \ 13
  EQUS "Copy"    : EQUB 0        \ 14
  EQUS "Tab"     : EQUB 0        \ 15
  EQUS "Escape"  : EQUB 0        \ 16
  EQUS "Caps"    : EQUB 0        \ 17
  EQUS "Shiftlk" : EQUB 0        \ 18
  EQUS "Up"      : EQUB 0        \ 19
  EQUS "Down"    : EQUB 0        \ 20
  EQUS "Left"    : EQUB 0        \ 21
  EQUS "Right"   : EQUB 0        \ 22
  EQUS "Shift"   : EQUB 0        \ 23 — BmKrChar's, not the table's
  EQUS "Caret"   : EQUB 0        \ 24: ^
  EQUS "Underline" : EQUB 0      \ 25: _
  EQUS "LBracket" : EQUB 0       \ 26: [
  EQUS "RBracket" : EQUB 0       \ 27: ]
  EQUS "At"      : EQUB 0        \ 28: @
  EQUS "Semicolon" : EQUB 0      \ 29: ;
  EQUS "Comma"   : EQUB 0        \ 30: ,
  EQUS "Slash"   : EQUB 0        \ 31: /
  EQUS "Backslash" : EQUB 0      \ 32: \ — and the ASCII boundary is
                                 \ 33 for it, see BmKrShow

\ ============================================================
\ BmKrNameCtl — X = a control index, out = bmp on its key's name
\ ============================================================
\ Was the middle of BmKrShow. Both readers want the same three cases
\ and one of them cannot see that screen's code, so the dispatch is
\ here and BmKrShow is three instructions.
\ The answer is a zero-terminated ASCII string, either bmKrBuf (a
\ one-character name, or f0-f9 built into it) or a pointer into
\ bmKrNames.
.BmKrNameCtl
  LDA keyTab,X                  \ the INKEY byte back to a key number,
  EOR #&FF                      \ which is what the name table indexes
  TAX
  JSR BmKrChar
  CMP #33                       \ >= 33: it prints as itself. 33, not
  BCS bks_one                   \ 32 — code 32 is Backslash's name and
                                \ no entry is ASCII space (the space
                                \ KEY is name 11), so the boundary
                                \ moved up one for a tenth name
  CMP #11
  BCS bks_named                 \ 11 and up: a name from the list

  CLC                           \ 1-10 are f0-f9: 'f' and the digit
  ADC #'0'-1
  TAY
  LDA #'f'
  STA bmKrBuf
  STY bmKrBuf+1
  LDA #0
  STA bmKrBuf+2
  BEQ bks_buf                   \ always

.bks_one
  STA bmKrBuf
  LDA #0
  STA bmKrBuf+1
.bks_buf
  LDA #LO(bmKrBuf) : STA bmp
  LDA #HI(bmKrBuf) : STA bmp+1
  RTS

\ 11 and up: walk the packed name list to the one wanted
.bks_named
  SEC
  SBC #11
  TAX
  LDA #LO(bmKrNames)
  STA bmp
  LDA #HI(bmKrNames)
  STA bmp+1
.bkn_next
  CPX #0
  BEQ bkn_x                     \ arrived
  LDY #0
.bkn_scan
  LDA (bmp),Y
  BEQ bkn_end
  INY
  BNE bkn_scan
.bkn_end
  INY                           \ past the terminator
  TYA
  CLC
  ADC bmp
  STA bmp
  BCC bkn_nc
  INC bmp+1
.bkn_nc
  DEX
  JMP bkn_next
.bkn_x
  RTS

.bmKrBuf   SKIP 3               \ a one- or two-character name

\ ============================================================
\ BmPatchKeys — the live bindings into page 1's six key fields
\ ============================================================
\ BmPatch's argument, for the keys instead of the scores: the record
\ only exists while its page is depacked, so the write happens on
\ every depack of BR_KEY_PAGE, from BmRowScan. The briefing named the
\ ASSEMBLED defaults until 2026-09-12 — hexwab, issue #20: "the
\ briefing screen should show the current keys not the default keys
\ (that's no use to anyone! what if the player before them changed
\ them?)". [11f DECISION 21]
\ EACH FIELD IS BR_KEY_FIELD GLYPH BYTES and the tool guarantees it by
\ padding the record (tools/make_briefing.py, KEY_FIELD), so this
\ writes a fixed count and never has to know what the source said.
\ The six records are NOT a fixed stride apart — the labels on the
\ same rows vary in length — so their addresses come from the table
\ below, which briefconst.asm generates the constants for.
\ bmKp IS swSrc, FontCell's own source pointer: nothing is being drawn
\ at depack time, and bmp is taken by the name walk.
bmKp = swSrc

.BmPatchKeys
  LDX #CTL_COUNT-1
.bpk_ctl
  STX brT2                      \ the control, kept across the name walk
  LDA bmKeyRecLo,X : STA bmKp
  LDA bmKeyRecHi,X : STA bmKp+1
  JSR BmKrNameCtl               \ X is still the control; bmp = the name
  LDY #0
.bpk_char
  LDA (bmp),Y
  BEQ bpk_pad                   \ the terminator: spaces to the end
  JSR BmKrAscii
  STA (bmKp),Y
  INY
  CPY #BR_KEY_FIELD
  BCC bpk_char
  BCS bpk_next                  \ always
.bpk_pad
  LDA #PN_SPACE
.bpk_fill
  STA (bmKp),Y
  INY
  CPY #BR_KEY_FIELD
  BCC bpk_fill
.bpk_next
  LDX brT2
  DEX
  BPL bpk_ctl
  RTS

\ Past each record's own column byte, in CTL_* order.
.bmKeyRecLo
  EQUB LO(BR_KEY0+1), LO(BR_KEY1+1), LO(BR_KEY2+1)
  EQUB LO(BR_KEY3+1), LO(BR_KEY4+1), LO(BR_KEY5+1)
.bmKeyRecHi
  EQUB HI(BR_KEY0+1), HI(BR_KEY1+1), HI(BR_KEY2+1)
  EQUB HI(BR_KEY3+1), HI(BR_KEY4+1), HI(BR_KEY5+1)

\ ============================================================
\ BmKrDepack — the redefine screen into the arena
\ ============================================================
\ krImg is THIS bank's, so nothing needs paging: only the addresses.
\ It lands on BR_RECS, over whichever page is up, and BrKeyRedef's
\ BrPagePaint depacks the page back afterwards.
.BmKrDepack
  LDA #LO(krImg)   : STA src
  LDA #HI(krImg)   : STA src+1
  LDA #LO(BR_RECS) : STA mapptr
  LDA #HI(BR_RECS) : STA mapptr+1
  JMP Zx0Unpack                 \ main RAM, and its RTS
