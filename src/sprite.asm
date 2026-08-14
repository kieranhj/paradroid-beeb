\ ============================================================
\ sprite.asm — droid sprites blitted into the play buffer
\ ============================================================
\ The C64 pins the player dead centre and scrolls the deck under
\ it, which it can do because its hardware scroll is 1 pixel. Ours
\ is 4 — the CRTC addresses in 8-byte units and a MODE 1 row is 80
\ of them, so a step is always 1/80 of the screen width, in every
\ mode. At low speed that reads as the whole world jerking 4 pixels
\ every few frames.
\
\ So the camera has a DEAD ZONE. The player moves through the world
\ at 1 pixel and the view only follows when the player pushes the
\ edge of a window around the centre. player.asm owns that; this
\ file just draws sprites wherever they end up.
\
\ Every droid uses the same code. Slot 0 is the player; slots 1 up
\ are enemy droids, which is the C64's arrangement too — it has one
\ hardware sprite for the player and a pool of six for everything
\ else. Slots here are a software pool of the same shape, so the
\ same "no free slot" cases arise and the same rules apply.
\
\ Sprites land on 2-pixel boundaries, not 4. A 2 px shift spills
\ 24 px of sprite into SEVEN bytes, so every row is seven wide and
\ every piece of compiled code exists twice, unshifted and shifted —
\ immediates cannot be shifted at run time the way artwork can.
\
\ 2 px rather than 1 is not just thrift: a C64 multicolour pixel is
\ exactly two MODE 1 pixels, so the artwork has no detail finer
\ than that. 1 px would need four copies.
\
\ The STORED rows are a single unshifted copy, read only by the wrap
\ fallback; SprFetchRow shifts those few on the fly.
\
\ MASKS ARE NOT STORED. Every opaque pixel maps to logical colour
\ 1, 2 or 3 and never 0, so a pixel is transparent exactly when
\ both its bits are clear, and one 256-byte table recovers the mask
\ from the data. The row was being copied into a buffer anyway, so
\ deriving it there is free.
\
\ Order within a frame is load-bearing:
\   1  SprRestoreAll   put every slot's background back, OLD address
\   2  scroll state, SetCRTCStart, DoRedraws
\   3  SprDrawAll      save the new background, then blit
\ All slots restore before any draws. Two sprites may overlap, and
\ restoring one after another had already saved the same cells would
\ write stale pixels into the second one's save area.
\
\ ADJACENT 4-PIXEL COLUMNS ARE 8 BYTES APART, not 1. Consecutive
\ bytes within a column are consecutive SCANLINES. Blitting a row
\ to seven consecutive addresses draws the sprite one column wide
\ and seven scanlines deep, which is exactly what the first build
\ did.
\ ============================================================

SPR_SLOTS = 7                   \ slot 0 = player, 1-6 = the droid pool
SPR_W     = 7                   \ 24 px, plus one byte for the 2 px shift
SPR_H     = 21                  \ scanlines
SPR_BYTES = SPR_W * SPR_H       \ 147 bytes of background per slot

\ Not derived from droids.asm's DR_W/DR_H: beebasm resolves constant
\ assignments in file order and the data is included after the code,
\ so they are declared here and checked against the generated file
\ down there instead.

\ THE SAVE AREA MIRRORS SCREEN GEOMETRY. Within one character row a
\ byte is at col*8 + scan, so a slot's save block is laid out the
\ same way: SPR_BLOCK bytes per character row, blocks in order. The
\ point is that the SAME Y — always col*8 — addresses both the screen
\ through (bufp),Y and the save through (svp),Y. Nothing needs X, and
\ nothing needs the seven absolute addresses in each loop retargeted
\ per slot, which used to cost fifteen pokes every time a slot came
\ round.
\
\ That matters beyond tidiness: a compiled blitter cannot poke a save
\ address into every one of its ~72 stores, so an X-indexed save area
\ would rule compilation out entirely. This is the shape that lets the
\ immediates be baked in.
\
\ Save areas stay a page apart rather than packed into 224 bytes, so
\ a slot's base is just HI(SPR_SAVE) + slot with a zero low byte.
SPR_SAVE  = &3000
SPR_BLOCK = SPR_W * UNIT_BYTES  \ 56: one character row of save area
ASSERT (SPR_SAVE AND &FF) == 0
ASSERT SPR_SAVE + SPR_SLOTS * 256 <= PANEL_ADDR

\ 21 scanlines starting at scan 0-7 touch at most FOUR character rows,
\ so the furthest byte a slot can reach is block 3 + the widest Y +
\ the deepest scanline = 3*56 + 48 + 7 = 223. Slots are page-aligned
\ and 223 < 256, so svp never leaves its page and neither does
\ (svp),Y — which is why the advances in SCANSTEP carry nothing.
ASSERT 3 * SPR_BLOCK + (SPR_W - 1) * UNIT_BYTES + 7 < 256

\ A row's 7 columns span 49 bytes, so the fast path needs the whole
\ span to sit below the end of the strip.
SPR_SPAN    = (SPR_W - 1) * UNIT_BYTES
SPR_WRAPLIM = BUF_END - SPR_SPAN

\ ============================================================
\ THE ROTOR IS COMPILED CODE
\ ============================================================
\ Sprite rows 0-4 and 15-19 are not fetched and blitted; they are
\ drawn by generated 6502 in the data bank, one routine per distinct
\ row, with the pixels and their masks baked in as immediates. The
\ rotor averages 3.2 opaque bytes of 7, and a compiled routine costs
\ nothing at all for the transparent ones — where the interpreted path
\ pays 26 cycles to fetch and 27 to blit every byte regardless.
\
\ Normally a compiled sprite needs eight variants, one per vertical
\ alignment. This one needs one. Within a character row a byte is at
\ col*8 + scan; the scan part is carried by bufp, which SCANSTEP
\ advances in step with svp, so Y is always col*8 whatever the
\ alignment. That is the whole reason the save area was moved into
\ screen geometry first.
\
\ Two copies exist, not eight: unshifted and shifted 2 px, since the
\ immediates cannot be shifted at run time the way the artwork can.
\ SPR_SEQSHIFT is the stride between them in the dispatch tables —
\ declared here and checked against the generated DR_SEQSHIFT in
\ main.asm, the same way SPR_W and SPR_H are.
\
\ DISPATCH IS BY SEQUENCE, NOT BY SLOT. The ten rotor rows a sprite
\ draws are fixed once its shift and phase are known, so the whole
\ sequence is a property of (shift, phase) — sixteen of them — and not
\ of the sprite. drSeqLo/Hi list the ten addresses in drawing order,
\ so the fast path walks them with one index and needs no row->slot
\ lookup, no add, and no row counter. See SprRotor5.
SPR_SEQSHIFT = 80               \ 8 phases * 10 drawn rotor rows

\ ============================================================
\ THE DIGITS ARE COMPILED TOO, BUT PER GLYPH
\ ============================================================
\ Rows 6-13 are the droid's number. They are dense where the rotor is
\ sparse — 42.7 opaque bytes of 56 — so almost nothing is saved by
\ skipping transparent bytes; the win is deleting SprFetchRow.
\
\ Per-TYPE code would be ~1K a type and 24 types do not fit. But the
\ number is three independent 8-pixel glyphs and there are only ten
\ glyphs, so ten routines serve all 24 types and the three POSITIONS
\ are reached by offsetting bufp, not by generating three copies.
\ See SprBlkGlyph.
SPR_DIG_GLYPHS = 10              \ stride between the two shifts

\ Fully on screen means every column and every scanline lands in the
\ play area. Anything else is culled rather than clipped for now, so
\ a droid pops in and out at the edges — see the note by SprSetSlot.
SPR_MAX_UNIT = PLAY_UNITS - SPR_W       \ 80 - 7 = 73
SPR_MAX_Y    = PLAY_VIS_ROWS * 8 - SPR_H \ 120 - 21 = 99

\ ============================================================
\ SprBuildMask — data byte to transparency mask
\ ============================================================
\ The only table still built at run time. A MODE 1 byte holds four
\ pixels, each as a high bit in
\ the top nibble and a low bit in the bottom. A pixel is transparent
\ when BOTH are clear, so fold the low nibble onto the high, invert,
\ and spread the answer back across both nibbles: AND with that and
\ the opaque pixels are cleared ready for the sprite to be ORed in.
ASSERT SPR_MASKTAB + 256 <= BUF_BASE

\ ============================================================
\ PAGESPRBANK — page in the bank that owns shift A, and remember it
\ ============================================================
\ A COMPILED SHIFT IS CODE, so the four shifts do not fit in one 16K
\ bank: shifts 0 and 1 are in SWRAM_SPR, 2 and 3 in SWRAM_SPR+1, and
\ which one a sprite needs is a property of the sprite. So the pool
\ pages per SLOT rather than once around the loop — ~16 cycles a slot
\ against a pass with ~39,000 spare.
\
\ Entered with the shift in A, which is where both callers already have
\ it: SprSetSlot has just read sprShift for the draw, and SprRestoreSlot
\ sprShiftS for the restore. LSR sets carry from bit 0, hence the CLC.
\
\ sprBank is kept because SprFetchRow pages SWRAM_DATA in over the top
\ and has to put THIS slot's bank back, not a fixed one.
MACRO PAGESPRBANK
  LSR A                         \ shift >> 1 picks the bank
  CLC                           \ LSR left carry = the shift's bit 0
  ADC #SWRAM_SPR
  STA sprBank
  STA ROMSHAD
  STA ROMSEL
ENDMACRO

.SprBuildMask
  LDX #0
.sbm_loop
  TXA
  LSR A : LSR A : LSR A : LSR A \ low nibble up to meet the high
  STA mcTmp
  TXA
  ORA mcTmp                     \ a set bit = this pixel has some colour
  AND #&0F
  EOR #&0F                      \ now a set bit = transparent
  STA mcTmp
  ASL A : ASL A : ASL A : ASL A
  ORA mcTmp                     \ same nibble top and bottom
  STA SPR_MASKTAB,X
  INX
  BNE sbm_loop
  RTS

\ ============================================================
\ SprSetSlot — point the blitter at slot X
\ ============================================================
\ Loads the per-slot state into the working variables and retargets
\ the seven save addresses in both the draw and restore fast paths.
\ Carry set on return means the slot is not drawable this frame.
\
\ CULLED, NOT CLIPPED. A sprite whose 7 columns or 21 scanlines do
\ not all fall inside the play area is skipped entirely, so droids
\ appear and disappear a sprite's width from the edge. The C64's
\ hardware sprites clip properly; ours will need the slow path
\ taught a column range and a row range to match. Deliberate for
\ this layer — it keeps the fast path exactly as fast while the
\ per-sprite cost is being measured.
.SprSetSlot
  STX sprSlot
  LDA sprActive,X
  BNE sss_live
.sss_no
  SEC
  RTS
.sss_live
  LDA sprUnit,X
  CMP #SPR_MAX_UNIT + 1
  BCS sss_no                    \ off the left or right (unsigned: also
                                \ catches the wrapped negative case)
  STA uCount
  LDA sprScrY,X
  CMP #SPR_MAX_Y + 1
  BCS sss_no                    \ off the top or bottom
  STA sprY

\ ONE COPY OF THE ARTWORK, not two. The shifted copy used to be built
\ into the bank at startup and chosen here by base address; now both
\ shifts exist as compiled code, and the stored rows are read only by
\ the wrap fallback — about one row in fifty. Shifting those few on
\ the fly in SprFetchRow costs nothing that matters and gives back the
\ 1,743 bytes the second copy occupied, which is where the compiled
\ digits live.
  LDX sprSlot
  LDA sprShift,X
  STA sprShiftW
  STA sprShiftS,X               \ the restore needs the DRAW's shift
  PAGESPRBANK                   \ and the bank the DRAW used — before the
                                \ drDigit read below, which is in it
  LDY sprType,X                 \ where this type's number block lives
  CLC
  LDA drDigitLo,Y : ADC #LO(drSprData) : STA sprDigit
  LDA drDigitHi,Y : ADC #HI(drSprData) : STA sprDigit+1

  LDA drDigit0,Y : STA sprDig+0 \ the three glyphs, once per sprite
  LDA drDigit1,Y : STA sprDig+1
  LDA drDigit2,Y : STA sprDig+2
\ BIT 0 OF THE SHIFT, NOT THE SHIFT. Bit 1 chose the bank a moment ago;
\ what is left picks which of that bank's two shifts, so both of these
\ indices stay inside a byte where four shifts' worth would not:
\ 4 * DR_SEQSHIFT is 320.
  LDA sprShiftW
  AND #1
  BEQ sss_g0
  LDA #SPR_DIG_GLYPHS           \ the odd shift's half of the glyph table
.sss_g0
  STA sprGlyphBase

\ Where this slot's rotor SEQUENCE starts: shift picks the half of the
\ table, phase picks the run of ten within it. Kept per slot as well as
\ in the working variable, because RESTORE runs a frame later — by which
\ time the phase has advanced and the shift may have changed, and the
\ background must be put back the way it was taken.
  LDA sprShift,X
  AND #1
  BEQ sss_seq0
  LDA #SPR_SEQSHIFT
  BNE sss_seq                   \ always
.sss_seq0
  LDA #0
.sss_seq
  LDY sprFrame,X
  CLC
  ADC drMul10,Y
  STA sprSeqBase
  STA sprSeqBaseS,X
  CLC
  RTS

\ ============================================================
\ SprCalcAddr — bufp = the sprite's top-left byte, sprScan = its
\ scanline within that character row
\ ============================================================
\ The sprite starts sprY scanlines below the top of the view and the
\ view starts `line` scanlines into display row 0, so the offset from
\ the top of the strip is line + sprY. Culling keeps sprY <= 99, and
\ line <= 7, so the last scanline is at most 99 + 7 + 20 = 126 — one
\ short of the 128-scanline strip, so a sprite can never wrap the
\ row 15/0 boundary. That is what keeps the blit and the scroll
\ redraws from colliding, and it is why the cull limit is a limit
\ rather than a nicety.
.SprCalcAddr
  CLC
  LDA line
  ADC sprY
  TAX
  AND #7
  STA sprScan
  TXA
  LSR A : LSR A : LSR A
  STA rCount
  JSR SetCell                   \ uCount was set by SprSetSlot
  CLC
  LDA bufp : ADC sprScan : STA bufp
  BCC sca_x
  INC bufp+1
.sca_x

\ Can ANY of this sprite's 21 rows straddle the end of the strip?
\ Testing that per row cost a JSR and ~27 cycles, 42 times a sprite.
\ It only depends on where the sprite starts: the walk advances at
\ most 3 row-crossings, so the furthest byte touched is under
\ 3*ROW_BYTES + SPR_SPAN beyond bufp. If that clears SPR_WRAPLIM the
\ whole sprite is safe and every row can take the fast path blind.
\ True about 80% of the time; the rest fall back to the per-row test.
  LDA #0
  STA sprNoWrap
  CLC
  LDA bufp   : ADC #LO(3*ROW_BYTES + SPR_SPAN) : TAX
  LDA bufp+1 : ADC #HI(3*ROW_BYTES + SPR_SPAN)
  BCS sca_may                   \ ran past &FFFF, so certainly past the end
  CMP #HI(SPR_WRAPLIM)
  BCC sca_safe
  BNE sca_may
  CPX #LO(SPR_WRAPLIM)
  BCS sca_may
.sca_safe
  INC sprNoWrap
.sca_may
  RTS

\ Rows 5, 14 and 20 are transparent for EVERY droid: the C64's
\ BuildDroidSprite and AnimateDroids simply never write them, so the
\ exporter points them at the one all-blank row. A row that writes
\ nothing needs no background saved and none restored, so all three
\ are skipped in both passes — 14% of the rows, for the price of one
\ table lookup on the other 18.
\
\ THE LAST ROW IS ONE OF THEM, so both loops stop at SPR_LASTROW
\ rather than SPR_H. Row 20 costs an iteration that tests a table,
\ writes nothing and then advances the pointers to a scanline no one
\ reads — and the row 19 → 20 advance is dead for the same reason.
\ Hence the walk in the loop tails sits AFTER the end test, not
\ before it: the last row drawn does not step off the end.
.sprBlankRow
  EQUB 0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1
SPR_LASTROW = SPR_H - 1         \ ...because that entry is the 1 at the end

\ ============================================================
\ SprNextScan — advance bufp AND svp by one scanline
\ ============================================================
\ Both walk the same shape, which is the whole point: one scanline on
\ is +1 within a character row, and crossing into the next row is
\ +(stride - 7), where the stride is ROW_BYTES for the screen and
\ SPR_BLOCK for the save. Keeping them in step is what lets one Y
\ address both, and it is what absorbs the vertical alignment that
\ would otherwise need eight compiled variants of every sprite.
\
\ svp needs no carry handling — see the assert at the top of the file.
\
\ THE SCANLINE IS IN bufp, so it is not counted separately. Every term
\ of bufp is a multiple of 8 — BUF_BASE is &5800, a row is 640 bytes, a
\ column is 8, and the wrap subtracts 10240 — except the scanline
\ itself, so `bufp AND 7` IS the scanline, always. Advance first and
\ ask afterwards: landing on a multiple of 8 means the row just ended.
\ That is one byte of state and five cycles a step cheaper than keeping
\ a counter in step with the thing it could be read from. The same
\ holds for svp (a save block is 56 bytes, a column 8), so either
\ pointer could answer; bufp is the one already in hand.
\ IT IS A MACRO, NOT A SUBROUTINE. Only four places walk with svp in
\ hand — the two row loops and the two block passes — so there are four
\ expansions of seventeen bytes, and a JSR/RTS pair costs 12 of the 33
\ cycles a step used to take. The glyphs do not walk at all — see
\ SprBuildRowPtrs.
\
\ The row crossing stays out of line. It is taken on one step in six,
\ it is 23 bytes, and putting it behind a JSR keeps the macro small
\ enough to be worth expanding four times.
\
\ P%+4 and P%+5 skip the following instruction rather than name a
\ label: a macro body cannot declare one, because the second expansion
\ would redefine it. 4 = the 2-byte BNE plus the 2-byte zero-page INC;
\ 5 = the 2-byte BNE plus the 3-byte JSR.
\
\ Not called NEXTSCAN: NEXT is a BeebASM keyword (FOR..NEXT), and a
\ macro whose name starts with it fails at the invocation with a bare
\ "Bad expression" pointing at the use, not the definition.
MACRO SCANSTEP
  INC svp
  INC bufp
  BNE P%+4
  INC bufp+1
  LDA bufp
  AND #7
  BNE P%+5                      \ still inside this character row
  JSR SprScanRow
ENDMACRO

\ The crossing tail. Entered with bufp already advanced onto what would
\ be scanline 8, so both pointers move on by stride-8 rather than
\ stride-7, and WrapBufFwd's RTS returns to the macro site.
.SprScanRow
  CLC
  LDA svp    : ADC #SPR_BLOCK-8     : STA svp
  CLC
  LDA bufp   : ADC #LO(ROW_BYTES-8) : STA bufp
  LDA bufp+1 : ADC #HI(ROW_BYTES-8) : STA bufp+1
  JMP WrapBufFwd

\ ============================================================
\ SprNextUnit — bufp on to the next 4-pixel column, wrapping
\ ============================================================
.SprNextUnit
  CLC
  LDA bufp : ADC #UNIT_BYTES : STA bufp
  BCC snu_nc
  INC bufp+1
.snu_nc
  JMP WrapBufFwd

\ ============================================================
\ SprFetchRow — sprRowBuf = this row's 7 data bytes and their masks
\ ============================================================
\ Rows 6-13 are the droid's number and depend on its TYPE; every
\ other row is rotor or blank and depends on the PHASE. One table
\ indexed by both would be 24 types x 8 phases x 21 rows, so there
\ are two, and this is where they meet.
\
\ THIS IS THE ONLY THING THAT READS THE STORED ARTWORK, so the artwork
\ lives in SWRAM_DATA and this routine pages it in and the sprite bank
\ back out around itself. It runs about one row in fifty — plus all
\ eight digit rows of a sprite that wraps — so ~24 cycles a call is
\ nothing, and it buys 2,079 bytes of the sprite bank, which is the
\ scarce one. The two exits both page back: the caller is inside the
\ blitter's window and expects the sprite bank in.
\
\ A clobbers over both PAGEBANKs; nothing here returns a value in it.
.SprFetchRow
  PAGEBANK SWRAM_DATA
  LDA sprRow
  CMP #DR_DIGIT0
  BCC sfr_phase
  CMP #DR_DIGIT0 + DR_DIGITN
  BCS sfr_phase
  SEC                           \ digit row: sprDigit + (row-6)*7
  SBC #DR_DIGIT0
  TAY
  CLC
  LDA sprMul7,Y : ADC sprDigit   : STA psrc
  LDA #0        : ADC sprDigit+1 : STA psrc+1
  JMP sfr_copy
.sfr_phase
  LDX sprRowIdx
  CLC
  LDA drOfsLo,X : ADC #LO(drSprData) : STA psrc
  LDA drOfsHi,X : ADC #HI(drSprData) : STA psrc+1
\ Copy the row, then shift it one pixel at a time — sprShiftW passes of
\ the same loop, 0 to 3. A per-shift routine would be faster and this is
\ the wrong place to spend: it is one row in fifty, and correctness over
\ four shifts matters more than the ~90 cycles a pass costs.
\
\ Forwards, not backwards: the pixel falling off the right of a byte is
\ the next byte's leftmost, so the carry runs left to right and the
\ seventh byte exists to catch the last of it. A MODE 1 pixel is bits
\ 7-n and 3-n, so one pixel is `AND #&EE` shifted down one with `&11`
\ carried up three — both nibbles moving together.
\
\ The masks are derived after the shifting rather than during it,
\ because a partly-shifted byte's mask is meaningless.
.sfr_copy
  LDY #SPR_W-1
.sfr_loop
  LDA (psrc),Y
  STA sprRowBuf,Y
  DEY
  BPL sfr_loop

  LDX sprShiftW
  BEQ sfr_mask
.sfr_pass
  LDA #0
  STA sfrCarry
  LDY #0
.sfr_sloop
  LDA sprRowBuf,Y
  PHA
  AND #&EE
  LSR A
  ORA sfrCarry
  STA sprRowBuf,Y
  PLA
  AND #&11
  ASL A : ASL A : ASL A
  STA sfrCarry
  INY
  CPY #SPR_W
  BNE sfr_sloop
  DEX
  BNE sfr_pass

.sfr_mask
  LDY #SPR_W-1
.sfr_mloop
  LDA sprRowBuf,Y
  TAX
  LDA SPR_MASKTAB,X
  STA sprRowBuf+SPR_W,Y
  DEY
  BPL sfr_mloop
  LDA sprBank : STA ROMSHAD : STA ROMSEL
  RTS

.sprMul7 EQUB 0,7,14,21,28,35,42,49

\ ============================================================
\ SprSetSave — svp = slot sprSlot's save area, at scanline sprScan
\ ============================================================
\ Slots are a page apart with a zero low byte, so the base is one
\ addition. The sprite's first row sits at scanline sprScan of block
\ 0, and SprNextScan walks on from there — draw and restore call this
\ with the same scanline and therefore trace the same path.
.SprSetSave
  LDA sprScan
  STA svp
  LDA #HI(SPR_SAVE)
  CLC
  ADC sprSlot
  STA svp+1
  RTS

\ Y offsets of the seven columns, for the wrapped paths where the
\ column index has to live in X.
.sprMul8 EQUB 0,8,16,24,32,40,48

\ ============================================================
\ The digit block — sprite rows 6-13, all eight at once
\ ============================================================
\ Three glyph routines draw it. Adjacent 4-pixel columns are 8 bytes
\ apart and a glyph is 8 pixels wide, so a position is two columns
\ along. That is why ten routines serve 24 droid types — the position
\ is not in the code.
\
\ THE GLYPHS DO NOT WALK. The block is eight known scanlines, so
\ SprBuildRowPtrs works out all eight addresses once and each compiled
\ row addresses its own: row r is (rowp+2r),Y. Three glyph passes over
\ eight rows used to cost 21 calls to a scanline-advance routine, which
\ was the largest single item left in a sprite; now they cost one build.
\
\ THE POSITION IS IN Y, NOT IN THE POINTER. Y = pos*16 + col*8, which
\ tops out at 40 and so still fits the one save-area page. The glyph
\ therefore holds the position in X across its whole body and loads
\ `LDY drYcol0,X` where it used to load an immediate — two cycles more
\ per column, against offsetting eight pointers per position. It is
\ also why the three positions can share one set of pointers, and why
\ the shifted glyphs' spill into a shared column still lands on the
\ right byte: position p column 2 and position p+1 column 0 both come
\ out at Y = (p+1)*16.
\
\ Only taken when the whole sprite cleared the wrap test. Otherwise all
\ eight rows go the interpreted way, as they always did.

\ Y for column 0, 1 and 2 of each of the three digit positions. Column 2
\ is the shifted glyph's SPILL, and it is not optional: a digit is 7
\ pixels wide in an 8 pixel cell, so shifted 2 px right its last pixel
\ column lands in the next position's first byte. The exporter used to
\ drop that column on the floor — the artwork was truncated to two bytes
\ before it was shifted — which took a column out of the right edge of
\ every glyph but 1, at odd 2 px positions only.
.drYcol0 EQUB 0, 16, 32
.drYcol1 EQUB 8, 24, 40
.drYcol2 EQUB 16, 32, 48

\ ============================================================
\ SprBuildRowPtrs — the block's eight scanline addresses
\ ============================================================
\ Called with bufp on the block's first row, and leaves it there. The
\ walk is the same one SCANSTEP does, minus svp: this runs before
\ SprBlkSave, which walks svp itself. Eight rows starting anywhere in a
\ character row cross into the next one at most once, so the expensive
\ arm is taken once per block rather than once per row.
\ BOTH SETS, AND THE ADVANCE IS THE ORDINARY ONE. rowq is the same eight
\ rows in the save area, which the glyphs need because they now save the
\ bytes they draw rather than leaving it to a pass of their own. The
\ save area mirrors screen geometry, so the same Y addresses both — that
\ is the property the whole blitter is built on, and it is why one loop
\ can fill both tables with one SCANSTEP between rows.
\
\ It walks bufp and svp all eight rows and does NOT put them back: eight
\ steps from row 6 leaves them on row 14, which is exactly where the
\ caller wants them. The separate save pass used to do that walking.
.SprBuildRowPtrs
  LDX #0
.brp_row
  LDA bufp   : STA rowp,X
  LDA bufp+1 : STA rowp+1,X
  LDA svp    : STA rowq,X
  LDA svp+1  : STA rowq+1,X
  SCANSTEP
  INX
  INX
  CPX #16
  BNE brp_row
  RTS

\ SEVEN columns, not six. Column 6 is only ever written by the last
\ position's spill under a shift, but it is restored unconditionally
\ because the save is unconditional too — see SprDigitBlock.
.SprBlkRest
  LDX #8
.sbr_row
  LDY #0*UNIT_BYTES : LDA (svp),Y : STA (bufp),Y
  LDY #1*UNIT_BYTES : LDA (svp),Y : STA (bufp),Y
  LDY #2*UNIT_BYTES : LDA (svp),Y : STA (bufp),Y
  LDY #3*UNIT_BYTES : LDA (svp),Y : STA (bufp),Y
  LDY #4*UNIT_BYTES : LDA (svp),Y : STA (bufp),Y
  LDY #5*UNIT_BYTES : LDA (svp),Y : STA (bufp),Y
  LDY #6*UNIT_BYTES : LDA (svp),Y : STA (bufp),Y
  SCANSTEP
  DEX
  BNE sbr_row
  RTS

\ SprBlkGlyph — draw digit position X (0-2). The glyph numbers and the
\ shift were worked out once per sprite in SprSetSlot; the restore
\ never comes here, because putting the background back does not care
\ what was drawn over it.
\
\ X SURVIVES INTO THE GLYPH and is the position it draws at, so the
\ table index goes in Y instead. Nothing here touches bufp: the glyph
\ addresses the row pointers, and the position is an offset in Y.
.SprBlkGlyph
  LDA sprDig,X
  CLC
  ADC sprGlyphBase              \ shift picks the half of the table
  TAY
  LDA drGlyphLo,Y : STA sbg_call+1
  LDA drGlyphHi,Y : STA sbg_call+2
.sbg_call
  JMP &FFFF                     \ tail call: the glyph ends in RTS

\ SprDigitBlock — save column 6, then draw the three glyphs, which save
\ the six columns they own as they go. SprBuildRowPtrs is the only thing
\ here that walks, so it is also what leaves bufp and svp on row 14 for
\ the caller; the glyphs run off the row pointers and disturb neither.
\
\ THE POSITIONS ARE DRAWN 2, 1, 0 AND THE ORDER IS LOAD-BEARING. Shifted,
\ each glyph spills its last pixel column into the next position's first
\ byte — position p's column 2 and position p+1's column 0 are the same
\ byte — and a glyph does not know its own position, so it cannot know
\ whether it is the first to touch a shared column. Descending order
\ settles it without asking: the owner of each shared column has already
\ saved it clean by the time the spill arrives. The spill is then merged
\ into what the owner drew, not stored over it.
\
\ Column 6 is the exception — the last position spills past every owner —
\ so it is saved by drBlkSave6. Unconditionally, even at shift 0 where
\ nothing writes it, because SprBlkRest restores it either way and a
\ stale save byte would be drawn as background. That routine is generated
\ into the sprite bank with the glyphs, not written here, because main
\ RAM is the binding constraint and the bank is not.
.SprDigitBlock
  JSR SprBuildRowPtrs           \ and leaves bufp/svp on row 14
  JSR drBlkSave6
  LDX #2
.sdb_glyph
  JSR SprBlkGlyph               \ X survives: the glyph indexes drYcolN,X
  DEX
  BPL sdb_glyph
  RTS

\ ============================================================
\ SprRotor5 / SprRestore5 — five rotor rows straight off the list
\ ============================================================
\ Entered with X on the first of five entries in drSeqLo/Hi, and leaves
\ it on the sixth — so the two halves of a sprite are two calls with
\ nothing in between but the index the first one left behind.
\
\ THE LIST IS INDEXED BY X, NOT Y, because the compiled rows use A and
\ Y and would eat an index kept in Y. X they never touch. The end test
\ compares X against a computed limit rather than counting down in a
\ second register, for the same reason.
\
\ Five rows, four walks: the caller walks into the block and out of it,
\ so this must not step past its last row. That is what keeps the two
\ halves composable and the last row of the sprite from walking off the
\ end — see the note by sprBlankRow.
\ ============================================================
\ SprWraps — does this row's span cross the end of the strip?
\ Carry set = yes, take the slow path.
\ ============================================================
.SprWraps
  LDA bufp+1
  CMP #HI(SPR_WRAPLIM)
  BCC spw_no
  BNE spw_yes
  LDA bufp
  CMP #LO(SPR_WRAPLIM)
  BCS spw_yes
.spw_no
  CLC
  RTS
.spw_yes
  SEC
  RTS

\ ============================================================
\ SprDrawAll / SprRestoreAll — every slot, in order
\ ============================================================
\ Restore walks slots backwards and draw walks forwards, so where
\ two sprites overlap the one drawn last is the one restored first
\ and the background comes back in the order it was covered.
\ THE SPRITE BANK IS PAGED IN HERE, not by the caller. Everything the
\ blitter reads out of sideways RAM — artwork, the compiled rows, the
\ glyphs, the sequence lists — is in SWRAM_SPR, and everything else in
\ the game reads SWRAM_DATA, so the swap belongs at the two doors into
\ the blitter rather than scattered up the call chain. 8 cycles each
\ way, twice a pass.
\ NEITHER LOOP PAGES ON THE WAY IN. Each slot pages its own bank, from
\ its own shift — see PAGESPRBANK — because with four compiled shifts
\ across two banks the right one is a property of the sprite and not of
\ the pool. Both still leave SWRAM_DATA in on the way out: that is the
\ resting state everything outside the blitter assumes.
.SprRestoreAll
  LDX #SPR_SLOTS-1
.sra_loop
  STX sprIter
  JSR SprRestoreSlot
  LDX sprIter
  DEX
  BPL sra_loop
  PAGEBANK SWRAM_DATA
  RTS

.SprDrawAll
  LDX #0
.sda_loop
  STX sprIter
  JSR SprDrawSlot
  LDX sprIter
  INX
  CPX #SPR_SLOTS
  BNE sda_loop
  PAGEBANK SWRAM_DATA
  RTS

\ ============================================================
\ SprDrawSlot — save the background for slot X, then blit over it
\ ============================================================
\ The starting address and scanline are kept so SprRestoreSlot can
\ walk exactly the same path next frame. Replaying the walk is
\ cheaper and less error-prone than storing 21 addresses, and it
\ cannot drift: the row-crossing pattern depends only on the
\ starting scanline, which is saved with it.
.SprDrawSlot
  JSR SprSetSlot
  BCC sd_go
  LDX sprSlot                   \ culled: make sure the stale background
  LDA #0                        \ is not put back somewhere it never came
  STA sprSaved,X                \ from
  RTS
.sd_go
  JSR SprCalcAddr
  LDX sprSlot
  LDA bufp    : STA sprPtr0Lo,X
  LDA bufp+1  : STA sprPtr0Hi,X
  LDA sprScan : STA sprScan0,X
  LDA #1      : STA sprSaved,X
  LDA sprNoWrap : STA sprNoWrapS,X

  JSR SprSetSave                \ svp = this slot's block 0, scanline sprScan

\ ---- the fast path -----------------------------------------
\ A sprite that cleared the wrap test up front has no row that can
\ straddle the end of the strip, so no row needs testing and the shape
\ of a sprite is a constant: five rotor rows, a blank, the digit block,
\ a blank, five more rotor rows. Writing that shape out removes the
\ row counter, the blank-row table lookup, the row->slot lookup and the
\ end test from all twelve iterations — everything the interpreted loop
\ below does to work out what it already knows.
\
\ Four sprites in five come through here. The fifth keeps the loop,
\ because only a per-row test can decide which rows fall back.
  LDA sprNoWrap
  BEQ sd_loop
  LDX sprSeqBase
  LDA drPrgLo,X : STA sd_prg+1
  LDA drPrgHi,X : STA sd_prg+2
.sd_prg
  JMP &FFFF                     \ tail call: the program ends in RTS

\ ---- the wrap fallback -------------------------------------
.sd_loop
  LDX sprSlot
  LDA sprFrame,X                \ phase*21, the row walk increments it
  TAY
  LDA drMulRows,Y
  STA sprRowIdx
  LDA #0
  STA sprRow
.sd_row
  LDX sprRow
  LDA sprBlankRow,X
  BEQ sd_notblank               \ transparent: nothing to save or draw
  JMP sd_next
\ ---- compiled rotor row ------------------------------------
\ The generated routine addresses each of its columns as (bufp),Y with
\ Y = col*8, so it needs the seven columns to be eight bytes apart in
\ address order. A row straddling the end of the strip is not, and
\ there is no way to express the walk in baked-in immediates — so that
\ row alone drops back to the interpreted slow path.
\
\ This loop only ever runs with sprNoWrap clear, so it does not test
\ it: the fast path above took every sprite that cleared the test.
\ For the same reason the digit block never opens here — all eight of
\ its rows go one at a time, exactly as they always did.
.sd_notblank
  LDA drSeqIdx,X
  BMI sd_digrow
  CLC
  ADC sprSeqBase                \ the index, worked out before the wrap test
  TAX                           \ so it survives in X — SprWraps touches only A
  JSR SprWraps
  BCC sd_comp
  JSR SprFetchRow               \ clobbers X, but sd_slow reloads it
  JMP sd_slow
.sd_comp
  LDA drSeqLo,X : STA sd_call+1
  LDA drSeqHi,X : STA sd_call+2
.sd_call
  JSR &FFFF
  JMP sd_nextnw

.sd_digrow
  JSR SprFetchRow               \ fetched and blitted as before
  JSR SprWraps
  BCS sd_slow
.sd_fastrow

  LDY #0*UNIT_BYTES
  LDA (bufp),Y : STA (svp),Y
  AND sprRowBuf+7  : ORA sprRowBuf+0 : STA (bufp),Y
  LDY #1*UNIT_BYTES
  LDA (bufp),Y : STA (svp),Y
  AND sprRowBuf+8  : ORA sprRowBuf+1 : STA (bufp),Y
  LDY #2*UNIT_BYTES
  LDA (bufp),Y : STA (svp),Y
  AND sprRowBuf+9  : ORA sprRowBuf+2 : STA (bufp),Y
  LDY #3*UNIT_BYTES
  LDA (bufp),Y : STA (svp),Y
  AND sprRowBuf+10 : ORA sprRowBuf+3 : STA (bufp),Y
  LDY #4*UNIT_BYTES
  LDA (bufp),Y : STA (svp),Y
  AND sprRowBuf+11 : ORA sprRowBuf+4 : STA (bufp),Y
  LDY #5*UNIT_BYTES
  LDA (bufp),Y : STA (svp),Y
  AND sprRowBuf+12 : ORA sprRowBuf+5 : STA (bufp),Y
  LDY #6*UNIT_BYTES
  LDA (bufp),Y : STA (svp),Y
  AND sprRowBuf+13 : ORA sprRowBuf+6 : STA (bufp),Y
  JMP sd_next

\ The row straddles the end of the strip, so the seven columns are no
\ longer 8 bytes apart in address order and bufp has to be walked.
\ The SAVE side is unaffected — it never wraps — so this is now one
\ pass rather than two: X indexes the row data and the save offset
\ through sprMul8, Y alternates between 0 for the walked bufp and
\ col*8 for svp, and A survives LDY so the background is read once.
\ About one row in fifty; correctness matters, speed does not.
.sd_slow
  LDA bufp   : STA sprTmpPtr
  LDA bufp+1 : STA sprTmpPtr+1
  LDX #0
.sds_loop
  LDY #0
  LDA (bufp),Y                  \ the background
  LDY sprMul8,X
  STA (svp),Y                   \ save it
  AND sprRowBuf+SPR_W,X
  ORA sprRowBuf,X
  LDY #0
  STA (bufp),Y
  JSR SprNextUnit
  INX
  CPX #SPR_W
  BNE sds_loop
  LDA sprTmpPtr   : STA bufp    \ back to the row's first column, NOT
  LDA sprTmpPtr+1 : STA bufp+1  \ advanced — so this needs the walking tail
  JMP sd_next

\ TWO TAILS, because a compiled row now walks on its own account — the
\ walk was moved inside the generated routines so the straight-line
\ programs need nothing between their calls. Rows that went through one
\ come here already advanced; blank rows and the interpreted paths do
\ not. The walk still sits after the end test either way, so the last
\ row does not step off the end.
\
\ THE INTERPRETED ROW USED TO FALL STRAIGHT INTO THE WRONG ONE. It puts
\ bufp back to where the row started, so it has not advanced, and it
\ landed in the tail for rows that have — every row after the first
\ wrapping one was then drawn on top of it. That is BUGS.md #5: the
\ sprite's lower half missing with stray pixels beside it, at fixed
\ positions, because a row only wraps at particular scroll offsets.
\ The restore mirrored the fault exactly, which is why diffing the
\ buffer against RedrawAll with the draw disabled reported no
\ difference for weeks.
.sd_nextnw                      \ the row walked itself
  INC sprRowIdx
  INC sprRow
  LDA sprRow
  CMP #SPR_LASTROW
  BEQ sd_done
  JMP sd_row
.sd_next
  INC sprRowIdx
  INC sprRow
  LDA sprRow
  CMP #SPR_LASTROW
  BEQ sd_done
  SCANSTEP
  JMP sd_row
.sd_done
  RTS

\ ============================================================
\ SprRestoreSlot — put slot X's saved background back
\ ============================================================
\ Uses the slot's OWN saved pointer, not a recomputed one: by the
\ time this runs the sprite may have moved, and the pixels belong
\ where they were taken from.
.SprRestoreSlot
  LDA sprSaved,X
  BNE sr_go
  RTS
.sr_go
  STX sprSlot
  LDA sprPtr0Lo,X : STA bufp
  LDA sprPtr0Hi,X : STA bufp+1
  LDA sprScan0,X  : STA sprScan
  LDA sprNoWrapS,X  : STA sprNoWrap   \ the draw's answers, not this frame's:
  LDA sprSeqBaseS,X : STA sprSeqBase  \ the sprite may since have moved, and
  LDA sprShiftS,X   : STA sprShiftW   \ the rotor has certainly turned
  PAGESPRBANK                   \ the DRAW's shift, so the DRAW's bank: the
                                \ compiled restore for this sprite is there
  JSR SprSetSave                \ replays the same walk the draw took

\ The same shape as the draw took, replayed — see SprDrawSlot.
  LDA sprNoWrap
  BEQ sr_loop
  LDX sprSeqBase
  LDA drRPrgLo,X : STA sr_prg+1
  LDA drRPrgHi,X : STA sr_prg+2
.sr_prg
  JMP &FFFF                     \ tail call: the program ends in RTS

.sr_loop
  LDA #0
  STA sprRow
.sr_row
  LDX sprRow
  LDA sprBlankRow,X
  BEQ sr_notblank               \ never saved, so nothing to put back
  JMP sr_next
\ The compiled draw saved only the columns it was going to cover, so
\ the restore must put back exactly those and no more. The generated
\ restore routines are keyed on the COLUMN SET rather than the
\ artwork — putting the background back does not care what was drawn
\ over it — which is why 28 draw routines share four restore ones.
\
\ The wrap answer is the draw's own, replayed: same start pointer,
\ same walk, so the same rows take the same path both times and the
\ save and the restore always agree.
\ As on the draw side, this loop only ever runs with sprNoWrap clear,
\ so it does not test it and the block never opens here.
.sr_notblank
  LDA drSeqIdx,X
  BMI sr_digrow
  CLC
  ADC sprSeqBase
  TAX
  JSR SprWraps
  BCS sr_slow
.sr_comp
  LDA drRSeqLo,X : STA sr_call+1
  LDA drRSeqHi,X : STA sr_call+2
.sr_call
  JSR &FFFF
  JMP sr_nextnw

.sr_digrow
  JSR SprWraps
  BCS sr_slow
.sr_fastrow

  LDY #0*UNIT_BYTES
  LDA (svp),Y : STA (bufp),Y
  LDY #1*UNIT_BYTES
  LDA (svp),Y : STA (bufp),Y
  LDY #2*UNIT_BYTES
  LDA (svp),Y : STA (bufp),Y
  LDY #3*UNIT_BYTES
  LDA (svp),Y : STA (bufp),Y
  LDY #4*UNIT_BYTES
  LDA (svp),Y : STA (bufp),Y
  LDY #5*UNIT_BYTES
  LDA (svp),Y : STA (bufp),Y
  LDY #6*UNIT_BYTES
  LDA (svp),Y : STA (bufp),Y
  JMP sr_next

.sr_slow
  LDA bufp   : STA sprTmpPtr
  LDA bufp+1 : STA sprTmpPtr+1
  LDX #0
.srs_loop
  LDY sprMul8,X
  LDA (svp),Y
  LDY #0
  STA (bufp),Y
  JSR SprNextUnit
  INX
  CPX #SPR_W
  BNE srs_loop
  LDA sprTmpPtr   : STA bufp    \ not advanced — the walking tail, as on
  LDA sprTmpPtr+1 : STA bufp+1  \ the draw side
  JMP sr_next

.sr_nextnw                      \ the row walked itself — see sd_nextnw
  INC sprRow
  LDA sprRow
  CMP #SPR_LASTROW
  BEQ sr_x
  JMP sr_row
.sr_next
  INC sprRow
  LDA sprRow
  CMP #SPR_LASTROW
  BEQ sr_x
  SCANSTEP
  JMP sr_row
.sr_x
  RTS

\ ============================================================
\ SprAnimateAll — step every live rotor
\ ============================================================
\ The C64 spins a droid faster the healthier it is: AnimateDroids
\ reloads a countdown with (64 - energy) >> 3, so a full-energy
\ droid advances a phase every frame and a dying one every 8. With
\ no energy model yet everything runs at full health.
.SprAnimateAll
  LDX #SPR_SLOTS-1
.saa_loop
  LDA sprActive,X
  BEQ saa_next
  LDA sprDelay,X
  BEQ saa_step
  DEC sprDelay,X
  JMP saa_next
.saa_step
  LDA #SPR_SPIN
  STA sprDelay,X
  LDA sprFrame,X
  CLC
  ADC #1
  AND #7
  STA sprFrame,X
.saa_next
  DEX
  BPL saa_loop
  RTS

SPR_SPIN = 0                    \ frames between phases; full energy = 0

\ ============================================================
\ SprInit — clear the pool and put the player in slot 0
\ ============================================================
.SprInit
  LDX #SPR_SLOTS-1
  LDA #0
.si_loop
  STA sprActive,X
  STA sprSaved,X
  STA sprFrame,X
  STA sprDelay,X
  STA sprType,X
  STA sprShift,X
  DEX
  BPL si_loop

  LDA #1 : STA sprActive+PLY_SLOT
  LDA #0 : STA sprType+PLY_SLOT   \ droid 001
  LDA #PLY_Y : STA sprScrY+PLY_SLOT
  RTS

\ ---- per-slot state ----------------------------------------
.sprActive  SKIP SPR_SLOTS      \ 0 = slot free
.sprType    SKIP SPR_SLOTS      \ droid type 0-23, picks the number block
.sprUnit    SKIP SPR_SLOTS      \ CRTC column 0-79
.sprShift   SKIP SPR_SLOTS      \ 0 = flat copy, 1 = shifted 2 px
.sprScrY    SKIP SPR_SLOTS      \ scanlines below the top of the view
.sprFrame   SKIP SPR_SLOTS      \ rotor phase 0-7
.sprDelay   SKIP SPR_SLOTS
.sprSaved   SKIP SPR_SLOTS      \ 0 until the slot has been drawn once
.sprPtr0Lo  SKIP SPR_SLOTS      \ where the last draw started
.sprPtr0Hi  SKIP SPR_SLOTS
.sprScan0   SKIP SPR_SLOTS
.sprNoWrapS SKIP SPR_SLOTS      \ the draw's wrap answer, for the restore
.sprSeqBaseS SKIP SPR_SLOTS     \ the draw's rotor-sequence base
.sprShiftS  SKIP SPR_SLOTS      \ the draw's shift
.sprBank    EQUB SWRAM_SPR      \ the bank the slot in hand lives in, so
                                \ SprFetchRow can put it back after paging
                                \ SWRAM_DATA in over the top

\ The per-slot arrays STAY HERE. Every one of them is reached as
\ `LDA sprActive,X` and never any other way, and abs,X costs the same
\ four cycles as zp,X — so moving 98 bytes of them into zero page
\ would buy nothing but a byte per instruction. The working scalars
\ they feed are the ones that moved; see the zero page block in
\ main.asm.
\
\ ---- working, one sprite at a time --------------------------
\ sprSlot, sprIter, sprNoWrap, sprY, sprRowIdx, sprSeqBase, sprShiftW,
\ sprGlyphBase, sprDig, sprDigit, sprTmpPtr and sfrCarry are all in
\ zero page now. sprSeqEnd and sprSeqX were declared and never read by
\ anything — SprRotor5 stopped needing them when the sequence lists
\ arrived — so they are gone rather than promoted.
\
\ sprRowBuf stays absolute: the fast path never touches it (a compiled
\ row carries its own pixels as immediates) and the fallback reads it
\ as sprRowBuf,X, which zero page would not make faster.
.sprRowBuf  SKIP SPR_W * 2
