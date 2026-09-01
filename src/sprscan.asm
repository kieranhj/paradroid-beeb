\ ============================================================
\ sprscan.asm -- the tranche decision's geometry, per slot
\ ============================================================
\ BANK 5. Split out of bank 6's sprsplit.asm on 2026-09-01: the class
\ machinery the window-B repaints need did not fit that bank's last 7
\ bytes, and the whole file (634 B) fits no bank's free space -- so the
\ geometry lives here and the component logic stays in bank 6, with
\ the per-slot answer carried across the page flip in sprCls (low
\ overlay, lowbss.asm).
\ SprScanCls runs FIRST: the SprSplitOK bridge in sprite.asm pages
\ this bank in, calls it, then pages bank 6 for SprSplitDecide. Every
\ byte read here is main RAM, zero page or the low overlay -- the
\ level draw's flags and `line` are zero page, the door table and the
\ sprite arrays are the code image's, and the animated-tile list is
\ the low overlay's -- so the split costs nothing but the two pages
\ the bridge was already paying one of.
\ ============================================================

\ ============================================================
\ SprScanCls -- fill sprCls: is each slot under this pass's writes?
\ ============================================================
\ sprCls,X = 1 if slot X stands under anything the pass will write to
\ the play buffer, else 0. Inactive slots read 0. SprAssignTr (bank 6)
\ ORs the byte over each overlap component to decide the forcing.
.SprScanCls
\ ---- once per pass: which writers exist at all? -------------
\ The commonest pass has NO buffer writer — no band, no column, no
\ dirty animated tile, no door moving — and used to pay the full
\ per-member geometry anyway, ~2,000-3,800 cycles at the front of
\ window A (docs/perf-audit-2026-08-31.md). The presence tests run
\ once here instead; the door predicate below is shd_doors' exactly,
\ so a door this loop calls static is one SprHitsDraw would have too.
  LDX numDoors
  BEQ sscw_nod
.sscw_dloop
  DEX
  LDA doorDirty,X               \ already opening, from this pass's probe
  BNE sscw_dyes
  LDA doorState,X
  AND #&40
  BNE sscw_dnext                \ held open: static this pass
  LDA doorState,X
  AND #7
  BNE sscw_dyes                 \ open and not held: closes a step
.sscw_dnext
  TXA
  BNE sscw_dloop
.sscw_nod
  LDA #0
  BEQ sscw_store                \ always
.sscw_dyes
  LDA #1
.sscw_store
  STA scnDoorW

  LDA animDirty                 \ anim presence is what AnimPaint tests:
  BEQ sscw_na                   \ dirty AND a non-empty list
  LDA animCount
.sscw_na
  ORA scnDoorW
  ORA bandDo
  ORA colCount
  STA scnAnyW

  LDX #SPR_SLOTS-1
.sscl_loop
  LDA #0
  STA sprCls,X
  LDA scnAnyW
  BEQ sscl_next                 \ nothing writes: every slot reads 0
  LDA sprActive,X
  BEQ sscl_next
  JSR SprHitsDraw
  STA sprCls,X                  \ the class byte, 0..3
.sscl_next
  DEX
  BPL sscl_loop
  RTS

\ Bank 5 is RAM: the two per-pass flags live beside the code that is
\ the only reader and writer of either.
.scnDoorW EQUB 0                \ some door repaints this pass
.scnAnyW  EQUB 0                \ any writer at all this pass
.shdCls   EQUB 0                \ SprHitsDraw's class accumulator

\ ============================================================
\ SprHitsDraw — is slot X under anything this pass will write?
\ ============================================================
\ Carry set if it is. X is preserved; SprAssignTr's count loop uses it.
\
\ FOUR WRITERS, and each reduces to a ONE-DIMENSIONAL test because of
\ what it covers:
\   the band     one display row, FULL WIDTH      -> scanlines only
\   the columns  4-pixel columns, FULL HEIGHT     -> units only
\   a door       one tile                         -> units only, rows
\   an anim tile one tile                            ignored (loose)
\ The two tile cases ignore rows because a map row is cheap to get
\ wrong and forcing a tranche is always the safe answer.
\ THE ANSWER IS A CLASS BYTE NOW, not a carry (2026-09-01): bit 0 for
\ the writers painted in window A (the band, the columns), bit 1 for
\ the writers painted in window B on a split pass (the animated
\ tiles). A sprite under a window-A writer must be in tranche A, one
\ under a window-B writer in tranche B, and one under both refuses
\ the split -- SprAssignTr acts on the bits. A = the byte on exit;
\ X is preserved.
.SprHitsDraw
  TXA
  PHA
  LDA #0
  STA shdCls

\ ---- the sprite's own two spans, both padded ----------------
\ Padded by eight either side: a pass can scroll the view eight units,
\ so a sprite that has not moved at all can still be eight units from
\ where its saved background was taken.
  LDA line                      \ scanlines below the top of the STRIP
  CLC
  ADC sprScrY,X
  STA shdT
  SEC
  SBC #8
  BCS shd_v0
  LDA #0
.shd_v0
  STA shdV0
  LDA shdT
  CLC
  ADC #SPR_H + 8
  STA shdV1

  LDA sprUnit,X
  SEC
  SBC #8
  BCS shd_u0
  LDA #0
.shd_u0
  STA shdU0
  LDA sprUnit,X
  CLC
  ADC #SPR_W + 8
  STA shdU1

\ ---- the band: one display row, full width ------------------
  LDA bandDo
  BEQ shd_cols
  LDA shdV0 : STA shdS0
  LDA shdV1 : STA shdS1
  LDA bandRc                    \ display row -> its eight scanlines
  ASL A : ASL A : ASL A
  STA shdA
  LDA #8
  STA shdLA
  JSR SprSpanHit
  BCC shd_cols
  LDA #1                        \ the band paints in window A
  STA shdCls

\ ---- the columns: 4-pixel columns, full height --------------
.shd_cols
  LDA shdU0 : STA shdS0         \ everything below is a unit test
  LDA shdU1 : STA shdS1

  LDA colCount
  BEQ shd_anim
  STA shdLA
  LDA colFirst
  STA shdA
  JSR SprSpanHit
  BCC shd_anim
  LDA shdCls                    \ the columns paint in window A too
  ORA #1
  STA shdCls

\ ---- the animated tiles AnimPaint will repaint --------------
\ animDirty is what AnimPaint itself tests, so a list with nothing to do
\ this pass costs one branch.
.shd_anim
  LDA animDirty
  BEQ shd_doors
  LDX animCount
  BEQ shd_doors
.shd_aloop
  DEX
  LDA animCol,X
  JSR SprTileHit
  BCS shd_ahit
  TXA
  BNE shd_aloop
  BEQ shd_doors                 \ always
.shd_ahit
  LDA shdCls                    \ an anim tile paints in window B on a
  ORA #2                        \ split pass -- the DoorAnimPaint window
  STA shdCls

\ ---- the doors DoorsUpdate will repaint ---------------------
\ A door only writes on a pass where it MOVES. One being held open —
\ bit 6, set by the probes in CheckWalls, which run before this — is
\ not decremented and not marked dirty by DoorsUpdate, so it repaints
\ nothing and is not a writer.
.shd_doors
  LDA scnDoorW                  \ hoisted: no door moves this pass, so
  BEQ shd_no                    \ skip the per-member walk entirely
  LDX numDoors
.shd_dloop
  DEX
  LDA doorDirty,X               \ already opening, from this pass's probe
  BNE shd_dhit
  LDA doorState,X
  AND #&40
  BNE shd_dnext                 \ held open: static this pass
  LDA doorState,X
  AND #7
  BEQ shd_dnext                 \ shut and staying shut
.shd_dhit
  LDA doorCol,X
  JSR SprTileHit
  BCS shd_dhit2
.shd_dnext
  TXA
  BNE shd_dloop
  BEQ shd_no                    \ always
.shd_dhit2
  LDA shdCls                    \ a door repaint is window A's (for
  ORA #1                        \ now: it joins the anim tiles in
  STA shdCls                    \ window B with the next change)

.shd_no
  PLA
  TAX
  LDA shdCls
  RTS

\ ============================================================
\ SprTileHit — A = a tile column. Carry set if it hits the span
\ ============================================================
\ A tile is four characters, which is eight units. Its left edge in view
\ units is col * 8 - mapHX, and that is signed: the map is 64 tile
\ columns and the view is eleven of them.
\
\ THE THREE OUTCOMES. Wholly right of the view or wholly left of it,
\ miss. Straddling the left edge — the top byte &FF and the low byte in
\ -8..-1 — is reported as a hit at unit 0, which is conservative and
\ two instructions instead of a clamp. Preserves X.
.SprTileHit
  STA shdT
  LDA #0
  STA shdT+1
  ASL shdT : ROL shdT+1
  ASL shdT : ROL shdT+1
  ASL shdT : ROL shdT+1
  SEC
  LDA shdT   : SBC mapHX   : STA shdT
  LDA shdT+1 : SBC mapHX+1 : STA shdT+1

  BMI sth_left
  BNE sth_no                    \ high byte above zero: far to the right
  LDA shdT
  CMP #PLAY_UNITS
  BCS sth_no
  STA shdA
  LDA #8
  STA shdLA
  JMP SprSpanHit

.sth_left
  LDA shdT+1
  CMP #&FF
  BNE sth_no                    \ more than a page left of the view
  LDA shdT
  CMP #256 - 8
  BCC sth_no                    \ left of the view by a whole tile or more
  LDA #0                        \ straddling the left edge
  STA shdA
  LDA #8
  STA shdLA
  JMP SprSpanHit
.sth_no
  CLC
  RTS

\ ============================================================
\ SprSpanHit — [shdA, shdA+shdLA) against [shdS0, shdS1)
\ ============================================================
\ Carry set if they overlap. Both are unsigned and both fit in a byte:
\ the spans are clamped at zero and the widest is 94. Preserves X.
.SprSpanHit
  CLC
  LDA shdA
  ADC shdLA
  CMP shdS0
  BCC ssh_no                    \ the writer ends at or before the span
  BEQ ssh_no
  LDA shdA
  CMP shdS1
  BCS ssh_no                    \ and it starts at or after the end of it
  SEC
  RTS
.ssh_no
  CLC
  RTS

