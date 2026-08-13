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
IF TARGET_MASTER
SPR_RECS  = SPR_SLOTS * 2       \ one draw record per slot PER BUFFER
ELSE
SPR_RECS  = SPR_SLOTS
ENDIF
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
\ (svp),Y — which is why the advances in SprNextScan carry nothing.
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
\ col*8 + scan; the scan part is carried by bufp, which SprNextScan
\ advances in step with svp, so Y is always col*8 whatever the
\ alignment. That is the whole reason the save area was moved into
\ screen geometry first.
\
\ Two copies exist, not eight: unshifted and shifted 2 px, since the
\ immediates cannot be shifted at run time the way the artwork can.
\ SPR_TABSHIFT is the stride between them in the dispatch tables —
\ declared here and checked against the generated DR_TABSHIFT in
\ main.asm, the same way SPR_W and SPR_H are.
SPR_TABSHIFT = 56               \ 8 phases * 7 distinct rows

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
  SETREC
  LDA sprActive,X
  BNE sss_live
.sss_no
  SEC
  RTS
.sss_live
  LDA sprUnit,X
  LDY sprShift,X
IF TARGET_MASTER
\ Buffer B holds the world 2 px further on, so the sprite has to sit
\ 2 px further LEFT in it to stay at the same place in the world. In
\ 4-pixel units with a 2 px shift on top, subtracting 2 px is:
\
\   shift 1  ->  shift 0, same unit
\   shift 0  ->  shift 1, one unit back
\
\ so the two buffers genuinely use different compiled shifts, and at
\ unit 0 the borrow makes the unit &FF, which the cull below catches
\ as an unsigned compare — the sprite really has left the screen in
\ that buffer and not in the other.
  LDX drawShift
  BEQ sss_pos
  CPY #0
  BNE sss_bshift
  SEC
  SBC #1
  LDY #1
  BNE sss_pos                   \ always: unit 0 borrows to &FF
.sss_bshift
  LDY #0
.sss_pos
  LDX sprSlot
ENDIF
  STY sprShiftW                 \ this buffer's shift, not the slot's
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
  RECX
  LDA sprShiftW
  STA sprShiftS,X               \ the restore needs the DRAW's shift
  LDX sprSlot
  LDY sprType,X                 \ where this type's number block lives
  CLC
  LDA drDigitLo,Y : ADC #LO(drSprData) : STA sprDigit
  LDA drDigitHi,Y : ADC #HI(drSprData) : STA sprDigit+1

  LDA drDigit0,Y : STA sprDig+0 \ the three glyphs, once per sprite
  LDA drDigit1,Y : STA sprDig+1
  LDA drDigit2,Y : STA sprDig+2
  LDA sprShiftW
  BEQ sss_g0
  LDA #10                       \ the shifted half of the glyph table
.sss_g0
  STA sprGlyphBase

\ Where this slot's compiled rotor rows live: shift picks the half of
\ the table, phase picks the group of seven within it. Kept per slot as
\ well as in the working variable, because RESTORE runs a frame later —
\ by which time the phase has advanced and the shift may have changed,
\ and the background must be put back the way it was taken.
  LDA sprShiftW
  BEQ sss_tab0
  LDA #SPR_TABSHIFT
  BNE sss_tab                   \ always
.sss_tab0
  LDA #0
.sss_tab
  LDY sprFrame,X
  CLC
  ADC drMul7,Y
  STA sprTabBase
  RECX
  STA sprTabBaseS,X
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
.sprBlankRow
  EQUB 0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1

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
.SprNextScan
  LDA sprScan
  CMP #7
  BEQ sns_row
  INC sprScan
  INC svp
  INC bufp
  BNE sns_x
  INC bufp+1
.sns_x
  RTS
.sns_row
  LDA #0
  STA sprScan
  CLC
  LDA svp    : ADC #SPR_BLOCK-7     : STA svp
  CLC
  LDA bufp   : ADC #LO(ROW_BYTES-7) : STA bufp
  LDA bufp+1 : ADC #HI(ROW_BYTES-7) : STA bufp+1
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
.SprFetchRow
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
.sfr_copy
  LDA sprShiftW
  BNE sfr_shifted
  LDY #SPR_W-1
.sfr_loop
  LDA (psrc),Y
  STA sprRowBuf,Y
  TAX
  LDA SPR_MASKTAB,X
  STA sprRowBuf+SPR_W,Y
  DEY
  BPL sfr_loop
  RTS

\ The 2 px shift, done here instead of from a second copy of the
\ artwork. Forwards, not backwards: the pixels falling off the right
\ of a byte are the next byte's low two, so the carry runs left to
\ right and the seventh byte exists to catch the last of it.
.sfr_shifted
  LDA #0
  STA sfrCarry
  LDY #0
.sfr_sloop
  LDA (psrc),Y
  PHA
  AND #&CC
  LSR A : LSR A
  ORA sfrCarry
  STA sprRowBuf,Y
  TAX
  LDA SPR_MASKTAB,X
  STA sprRowBuf+SPR_W,Y
  PLA
  AND #&33
  ASL A : ASL A
  STA sfrCarry
  INY
  CPY #SPR_W
  BNE sfr_sloop
  RTS

.sfrCarry EQUB 0

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
\ Three glyph routines draw it, called with bufp and svp offset by 0,
\ 16 and 32: adjacent 4-pixel columns are 8 bytes apart and a glyph is
\ 8 pixels wide, so a position is two columns along. That is why ten
\ routines serve 24 droid types — the position is in the pointer, not
\ in the code.
\
\ Each glyph walks its own eight rows, so the block is three walks over
\ the same eight scanlines plus one for the save. SprBlkSave and
\ SprBlkRest are the generic passes; the glyphs never save anything.
\
\ Only taken when the whole sprite cleared the wrap test. Otherwise all
\ eight rows go the interpreted way, as they always did.
SPR_GLYPH_STEP = 2 * UNIT_BYTES

\ Save bufp/svp/sprScan, and put them back. The block runs the same
\ eight scanlines four times over, so it needs a mark and a return.
.SprBlkMark
  LDA bufp   : STA blkPtr
  LDA bufp+1 : STA blkPtr+1
  LDA svp    : STA blkSvp
  LDA sprScan: STA blkScan
  RTS
.SprBlkReset
  LDA blkPtr   : STA bufp
  LDA blkPtr+1 : STA bufp+1
  LDA blkSvp   : STA svp
  LDA blkScan  : STA sprScan
  RTS

\ All seven columns of all eight rows. Column 6 is only ever written by
\ a shifted glyph's spill, but saving it unconditionally costs 8 reads
\ and removes the need to remember which way it went.
.SprBlkSave
  LDX #8
.sbk_row
  LDY #0*UNIT_BYTES : LDA (bufp),Y : STA (svp),Y
  LDY #1*UNIT_BYTES : LDA (bufp),Y : STA (svp),Y
  LDY #2*UNIT_BYTES : LDA (bufp),Y : STA (svp),Y
  LDY #3*UNIT_BYTES : LDA (bufp),Y : STA (svp),Y
  LDY #4*UNIT_BYTES : LDA (bufp),Y : STA (svp),Y
  LDY #5*UNIT_BYTES : LDA (bufp),Y : STA (svp),Y
  LDY #6*UNIT_BYTES : LDA (bufp),Y : STA (svp),Y
  JSR SprNextScan
  DEX
  BNE sbk_row
  RTS

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
  JSR SprNextScan
  DEX
  BNE sbr_row
  RTS

\ SprBlkGlyph — draw digit position X (0-2). The glyph numbers and the
\ shift were worked out once per sprite in SprSetSlot; the restore
\ never comes here, because putting the background back does not care
\ what was drawn over it.
.SprBlkGlyph
  STX sprDigPos
  JSR SprBlkReset
  LDX sprDigPos
  LDA sprMulStep,X              \ the position, as a byte offset
  BEQ sbg_at                    \ position 0 needs no adjustment
  CLC
  ADC svp : STA svp             \ svp cannot leave its page — see the
  CLC                           \ assert at the top of the file
  LDA sprMulStep,X
  ADC bufp : STA bufp
  BCC sbg_at
  INC bufp+1
.sbg_at
  LDA sprDig,X
  CLC
  ADC sprGlyphBase              \ shift picks the half of the table
  TAX
  LDA drGlyphLo,X : STA sbg_call+1
  LDA drGlyphHi,X : STA sbg_call+2
.sbg_call
  JMP &FFFF                     \ tail call: the glyph ends in RTS

.sprMulStep EQUB 0, SPR_GLYPH_STEP, 2*SPR_GLYPH_STEP

\ SprDigitBlock — save the eight rows, then draw the three glyphs over
\ them. Four walks of the same scanlines, so the position after the
\ block is taken from the save pass and put back at the end; the glyph
\ passes each rewind to the mark.
.SprDigitBlock
  JSR SprBlkMark
  JSR SprBlkSave
  LDA bufp    : STA blkEnd
  LDA bufp+1  : STA blkEnd+1
  LDA svp     : STA blkEndSvp
  LDA sprScan : STA blkEndScan
  LDX #0
.sdb_glyph
  JSR SprBlkGlyph
  LDX sprDigPos
  INX
  CPX #3
  BNE sdb_glyph
  LDA blkEnd     : STA bufp
  LDA blkEnd+1   : STA bufp+1
  LDA blkEndSvp  : STA svp
  LDA blkEndScan : STA sprScan
  RTS

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
.SprRestoreAll
  LDX #SPR_SLOTS-1
.sra_loop
  STX sprIter
  JSR SprRestoreSlot
  LDX sprIter
  DEX
  BPL sra_loop
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
  RECX                        \ culled: make sure the stale background
  LDA #0                        \ is not put back somewhere it never came
  STA sprSaved,X                \ from. Culling is per buffer: at the edge
  RTS                           \ a slot can be off one and on the other
.sd_go
  JSR SprCalcAddr
  RECX
  LDA bufp    : STA sprPtr0Lo,X
  LDA bufp+1  : STA sprPtr0Hi,X
  LDA sprScan : STA sprScan0,X
  LDA #1      : STA sprSaved,X
  LDA sprNoWrap : STA sprNoWrapS,X

  JSR SprSetSave                \ svp = this slot's block 0, scanline sprScan

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
\ row alone drops back to the interpreted slow path. See SprCalcAddr:
\ four sprites in five clear the whole test up front.
.sd_notblank
  LDA drRotSlot,X
  BMI sd_digit
  CLC
  ADC sprTabBase                \ the index, worked out before the wrap test
  TAX                           \ so it survives in X — SprWraps touches only A
  LDA sprNoWrap
  BNE sd_comp
  JSR SprWraps
  BCC sd_comp
  JSR SprFetchRow               \ clobbers X, but sd_slow reloads it
  JMP sd_slow
.sd_comp
  LDA drDrawLo,X : STA sd_call+1
  LDA drDrawHi,X : STA sd_call+2
.sd_call
  JSR &FFFF
  JMP sd_next

\ ---- the digit block ---------------------------------------
\ Taken whole when the sprite cleared the wrap test, which is four
\ times in five. Otherwise the eight rows go one at a time down the
\ interpreted path, exactly as they always did — the block's glyph
\ routines address their columns as (bufp),Y and cannot walk a row
\ that straddles the end of the strip.
.sd_digit
  LDA sprNoWrap
  BEQ sd_digrow
  LDA sprRow
  CMP #DR_DIGIT0
  BNE sd_digrow                 \ only the first row opens the block
  JSR SprDigitBlock
  CLC
  LDA sprRowIdx : ADC #DR_DIGITN : STA sprRowIdx
  CLC
  LDA sprRow    : ADC #DR_DIGITN : STA sprRow
  CMP #SPR_H
  BNE sd_blkmore
  JMP sd_done
.sd_blkmore
  JMP sd_row

.sd_digrow
  JSR SprFetchRow               \ fetched and blitted as before
  LDA sprNoWrap
  BNE sd_fastrow
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
  LDA sprTmpPtr   : STA bufp
  LDA sprTmpPtr+1 : STA bufp+1

.sd_next
  INC sprRowIdx
  JSR SprNextScan
  INC sprRow
  LDA sprRow
  CMP #SPR_H
  BEQ sd_done
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
  STX sprSlot
  SETREC
  RECX
  LDA sprSaved,X
  BNE sr_go
  RTS
.sr_go
  LDA sprPtr0Lo,X : STA bufp
  LDA sprPtr0Hi,X : STA bufp+1
  LDA sprScan0,X  : STA sprScan
  LDA sprNoWrapS,X  : STA sprNoWrap   \ the draw's answers, not this frame's:
  LDA sprTabBaseS,X : STA sprTabBase  \ the sprite may since have moved, and
  LDA sprShiftS,X   : STA sprShiftW   \ the rotor has certainly turned
  JSR SprSetSave                \ replays the same walk the draw took
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
.sr_notblank
  LDA drRotSlot,X
  BMI sr_digit
  CLC
  ADC sprTabBase
  TAX
  LDA sprNoWrap
  BNE sr_comp
  JSR SprWraps
  BCS sr_slow
.sr_comp
  LDA drRestLo,X : STA sr_call+1
  LDA drRestHi,X : STA sr_call+2
.sr_call
  JSR &FFFF
  JMP sr_next

\ The block restore does not need the glyphs at all — putting the
\ background back does not care what was drawn over it, so all seven
\ columns of all eight rows come back in one walk rather than three.
.sr_digit
  LDA sprNoWrap
  BEQ sr_digrow
  LDA sprRow
  CMP #DR_DIGIT0
  BNE sr_digrow
  JSR SprBlkRest
  CLC
  LDA sprRow : ADC #DR_DIGITN : STA sprRow
  CMP #SPR_H
  BEQ sr_x
  JMP sr_row

.sr_digrow
  LDA sprNoWrap
  BNE sr_fastrow
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
  LDA sprTmpPtr   : STA bufp
  LDA sprTmpPtr+1 : STA bufp+1

.sr_next
  JSR SprNextScan
  INC sprRow
  LDA sprRow
  CMP #SPR_H
  BEQ sr_x
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
  STA sprFrame,X
  STA sprDelay,X
  STA sprType,X
  STA sprShift,X
  DEX
  BPL si_loop

  LDX #SPR_RECS-1               \ both buffers' records on a Master
  LDA #0
.si_rec
  STA sprSaved,X
  DEX
  BPL si_rec

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
\ ---- the draw record, one set per buffer --------------------
\ Everything SprRestoreSlot replays. On a Master there are two sets,
\ indexed slot + sprRecOfs, because the two buffers hold the sprite
\ 2 px apart: different shift, sometimes a different unit, and at the
\ screen edge one may have culled the slot while the other drew it.
.sprSaved   SKIP SPR_RECS       \ 0 until the slot has been drawn once
.sprPtr0Lo  SKIP SPR_RECS       \ where the last draw started
.sprPtr0Hi  SKIP SPR_RECS
.sprScan0   SKIP SPR_RECS
.sprNoWrapS SKIP SPR_RECS       \ the draw's wrap answer, for the restore
.sprTabBaseS SKIP SPR_RECS      \ the draw's compiled-rotor table base
.sprShiftS  SKIP SPR_RECS       \ the draw's shift

\ ---- working, one sprite at a time --------------------------
.sprNoWrap  EQUB 0
.sprSlot    EQUB 0
.sprIter    EQUB 0
.sprY       EQUB 0
.sprTmpPtr  EQUW 0
.sprRowIdx  EQUB 0
.sprTabBase EQUB 0
.sprShiftW  EQUB 0              \ the shift this draw or restore is using
.sprGlyphBase EQUB 0            \ 0 or 10: which half of the glyph table
.sprDig     SKIP 3              \ the droid's three digits, as glyph numbers
.sprDigPos  EQUB 0
.blkPtr     EQUW 0              \ the digit block's start, for the rewinds
.blkSvp     EQUB 0
.blkScan    EQUB 0
.blkEnd     EQUW 0              \ and where the block leaves off
.blkEndSvp  EQUB 0
.blkEndScan EQUB 0
.sprDigit   EQUW 0
.sprRowBuf  SKIP SPR_W * 2
