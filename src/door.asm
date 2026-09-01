\ ============================================================
\ door.asm — doors, as bit 7 of the character code
\ ============================================================
\ A door is one 4x4 tile. Opening it CLEARS BIT 7 on the cells it
\ uncovers, which does two jobs at once: bit 7 is the wall bit that
\ CheckWalls already tests, and it also selects the open-door glyph,
\ because the charset holds the open and closed art 128 codes apart.
\ One bit, both effects — the C64's idea, kept exactly.
\
\ THE TRIGGER IS CHARACTER $20, not a tile number. GetNearChar tests
\ the probed cell for $20 and calls OpenDoor; we do the same in
\ ProbeGroup. Nothing has to be scanned at deck load and no table of
\ door positions is shipped: a door is discovered by walking into it.
\ $20 appears in only three of the 32 tiles (1 vertical door, 2
\ horizontal, 23 the lift entrance) and a deck map is built only from
\ tiles, so $20 can never turn up in open floor.
\
\ ---- where the patched characters live ----------------------
\ The C64 writes the cleared bit straight into its expanded 256x64
\ character map at $8000. WE HAVE NO SUCH MAP — Layer 2 kept the 64x16
\ tile map and expands to characters at draw time, which is worth 15K
\ and is not worth reversing for doors.
\
\ So each open door gets a PRIVATE COPY of its tile's 16 definition
\ bytes, and the patch is applied to that. This works because the draw
\ already picks a tile definition ONCE PER TILE:
\
\   LDA tdpLo,X : ADC subRowOfs : STA tdp
\
\ Pointing tdp at the private copy instead costs nothing per character
\ — only the choice of pointer, eleven times a band pass rather than
\ forty. That is the whole reason this scheme was picked over a door
\ list consulted per character.
\
\ MapChar takes the same substitution, so the wall probes and the draw
\ can never disagree about whether a doorway is passable.
\
\ ---- state encoding, unchanged from the C64 -----------------
\   bit 7   1 = horizontal door, 0 = vertical
\   bit 6   opened this pass — set by DoorProbe, cleared by DoorsUpdate
\   bits 0-2  animation step, 0 to 4
\
\ Orientation comes from WHICH COLUMN of the tile the pad is in:
\ columns 0 and 3 mean vertical, 1 and 2 mean horizontal. That is
\ `MapPos AND 3` in the original, and the tile data agrees with it —
\ tile 1's pads are at columns 0 and 3, tile 2's at 1 and 2.
\
\ A step uncovers two characters:
\   vertical    row = step,  columns 1 and 2
\   horizontal  rows 1 and 2, column = step
\ Four steps open a 2x4 or 4x2 passage through the tile.
\ ============================================================

DOOR_SLOTS = 7                  \ the C64's cap, and it compacts on close

\ ============================================================
\ DoorInit — forget every door
\ ============================================================
\ Called from LoadDeck. A door left open on the deck being left would
\ otherwise keep patching a tile position on the deck being entered.
.DoorInit
  LDA #0
  STA numDoors
  RTS

\ ============================================================
\ DoorScan — look for an approach pad anywhere in the diamond
\ ============================================================
\ The same twelve cells CheckWalls probes, but walked in full every
\ pass and with no early exit — see the note at the call site in
\ CheckWalls for why nothing less will do.
\ plyCX / plyCY are the reference cell, already computed by CheckWalls.
\ cellX and cellY are scratch here: ProbeGroup rebuilds them per probe.
.DoorScan
  LDX #11
.ds_loop
  STX dsIdx
  CLC
  LDA plyCX : ADC nearXoffset,X : STA cellX
  LDA #0    : STA cellX+1
  CLC
  LDA plyCY : ADC nearYoffset,X : STA cellY
  JSR MapChar
  CMP #DOOR_PAD
  BNE ds_next
  LDX dsIdx
  JSR DoorProbe
.ds_next
  LDX dsIdx
  DEX
  BPL ds_loop
  RTS

\ ============================================================
\ DoorProbe — the probed cell held $20: open or register a door
\ ============================================================
\ Called from ProbeGroup with cellX / cellY on the pad. X holds the
\ probe index and must survive; cellX and cellY are recomputed by the
\ next iteration, so they are free.
\
\ maprow and tdp are borrowed — MapChar has finished with them by the
\ time we get here and rebuilds both on its next call.
.DoorProbe
  STX dpSaveX

  LDA cellX
  LSR A : LSR A
  STA dpCol
  LDA cellY
  LSR A : LSR A
  STA dpRow

  LDX numDoors                  \ already tracking this one?
  BEQ dp_new
  DEX
.dp_find
  LDA doorCol,X
  CMP dpCol
  BNE dp_next
  LDA doorRow,X
  CMP dpRow
  BEQ dp_step
.dp_next
  DEX
  BPL dp_find

\ ---- register it --------------------------------------------
.dp_new
  LDX numDoors
  CPX #DOOR_SLOTS
  BCS dp_x                      \ seven already open; the eighth waits
  INC numDoors
  LDA dpCol : STA doorCol,X
  LDA dpRow : STA doorRow,X
  LDA #0    : STA doorDirty,X
  JSR DoorCopyDef               \ the private copy, still all closed
  LDX dpSlot

  LDA cellX                     \ column within the tile picks the axis
  AND #3
  BEQ dp_vert                   \ 0 -> vertical
  CMP #3
  BEQ dp_vert                   \ 3 -> vertical
  LDA #&C0                      \ 1 or 2 -> horizontal
  BNE dp_setst                  \ always
.dp_vert
  LDA #&40
.dp_setst
  STA doorState,X
.dp_x
  LDX dpSaveX
  RTS

\ ---- advance one step ---------------------------------------
.dp_step
  LDA doorState,X
  AND #&40
  BNE dp_x                      \ already stepped this pass
  LDA doorState,X
  ORA #&40
  STA doorState,X
  BMI dp_horiz
  CMP #&44
  BCS dp_x                      \ fully open

  AND #7                        \ vertical: row = step, columns 1 and 2
  ASL A : ASL A
  CLC
  ADC doorMul16,X
  TAY
  INY
  LDA doorDef,Y : AND #&7F : STA doorDef,Y
  INY
  LDA doorDef,Y : AND #&7F : STA doorDef,Y
  JMP dp_stepped

.dp_horiz
  CMP #&C4
  BCS dp_x                      \ fully open
  AND #7                        \ horizontal: rows 1 and 2, column = step
  CLC
  ADC doorMul16,X
  TAY
  LDA doorDef+4,Y : AND #&7F : STA doorDef+4,Y
  LDA doorDef+8,Y : AND #&7F : STA doorDef+8,Y

.dp_stepped
  INC doorState,X
  LDA #1
  STA doorDirty,X
  LDX dpSaveX
  RTS

\ ============================================================
\ DoorCopyDef LIVES IN BANK 4 NOW — see screen.asm
\ ============================================================
\ Moved 2026-08-29 to pay for the resident depacker (main.asm's
\ .Zx0Unpack): the code image needed 51 bytes and this routine is
\ exactly 51. It was the safest thing in this file to move, because it
\ ALREADY could not run without SWRAM_DATA paged — it reads tdpLo/tdpHi
\ and the tile definition through them, and those are screen.asm's, in
\ bank 4. So being in bank 4 adds no precondition it did not already
\ have, and its one caller (dp_new above) is main-RAM play-path code
\ where SWRAM_DATA is the resting state.
\ ============================================================
\ DoorTdp LIVES IN BANK 4 NOW — see screen.asm
\ ============================================================
\ Moved 2026-08-29, and it is a better home than this one was: ALL
\ THREE CALLERS ARE BANK 4 ALREADY — screen.asm's MapChar and
\ scroll.asm's band and column paths — so every call was crossing the
\ boundary out of bank 4 and straight back in. In bank 4 they are
\ ordinary local calls. It reads door.asm's variables, which is main
\ RAM, and bank code may read main RAM freely.
\ The 56 bytes paid for the PARAFNT unpack in the code image, which had
\ none left after the resident depacker.
\ ============================================================
\ DoorsUpdate — close what was not touched, redraw what moved
\ ============================================================
\ Once a pass, from DoRedraws. Doors the player is still standing at
\ have bit 6 set and are held open; everything else closes one step,
\ and a door that reaches step 0 is dropped from the list.
\
\ THE LIST IS COMPACTED as it goes, which is what keeps seven slots
\ enough for a whole deck. X walks the source, Y the destination.
\
\ The C64 clears bit 6 on the SOURCE entry after copying it down, so a
\ compacted door carries its bit 6 into the next pass and skips one
\ close step. We clear it on the destination instead — the intent is
\ plainly per-door and not per-slot, and a door that closes a step
\ later than it should is a visible difference for no benefit.
.DoorsUpdate
  LDA numDoors
  BNE du_go
  JMP du_gate                   \ out of BEQ range once the close arms grew
.du_go
  LDX #0
  LDY #0
.du_loop
  LDA doorState,X
  AND #&40
  BNE du_keep                   \ held open this pass
  LDA doorState,X
  AND #7
  BEQ du_drop                   \ fully closed: let it fall out of the list

  DEC doorState,X               \ close one step, then use the NEW step

\ Y IS THE COMPACTION DESTINATION AND BOTH CLOSE ARMS ARE ABOUT TO USE
\ IT AS AN INDEX INTO doorDef. Losing it means du_keep compares X
\ against a tile-definition offset, copies entries to a wild slot, and
\ finally stores that offset as numDoors — after which everything the
\ list touches is out of range. It cost an afternoon.
\ CloseDoors saves Y across exactly these two arms too (into
\ xfer_cpuSpriteX, which is what those otherwise baffling stores are
\ for). Carrying that over would have avoided the whole thing.
  STY duSaveY

  LDA doorState,X
  BMI du_hclose

  AND #7                        \ vertical: row = step, columns 1 and 2
  ASL A : ASL A
  CLC
  ADC doorMul16,X
  TAY
  INY
  LDA doorDef,Y : ORA #&80 : STA doorDef,Y
  INY
  LDA doorDef,Y : ORA #&80 : STA doorDef,Y
  JMP du_closed

.du_hclose
  AND #7                        \ horizontal: rows 1 and 2, column = step
  CLC
  ADC doorMul16,X
  TAY
  LDA doorDef+4,Y : ORA #&80 : STA doorDef+4,Y
  LDA doorDef+8,Y : ORA #&80 : STA doorDef+8,Y

.du_closed
  LDY duSaveY
  LDA #1
  STA doorDirty,X

.du_keep
  STY duDst                     \ compact: move entry X down to Y
  CPX duDst
  BEQ du_same
  LDA doorCol,X   : STA doorCol,Y
  LDA doorRow,X   : STA doorRow,Y
  LDA doorState,X : STA doorState,Y
  LDA doorDirty,X : STA doorDirty,Y
  JSR DoorMoveDef
.du_same
  LDA doorState,Y               \ bit 6 lives for one pass only
  AND #&BF
  STA doorState,Y
  INY
.du_drop
  INX
  CPX numDoors
  BCS du_done
  JMP du_loop                   \ the close arms put this out of BCC range
.du_done
  STY numDoors

\ ---- redraw whatever changed --------------------------------
\ After the band and the columns, so a door inside a freshly drawn
\ band is written over the top of it rather than under. ON A SPLIT
\ PASS THE REPAINT BELONGS TO WINDOW B (2026-09-01): the state above
\ ran in window A (it writes doorDef, which this pass's band and
\ column draws read, and no buffer), and the main loop's window-B
\ block calls DoorAnimPaint between tranche B's restore and its draw
\ -- SprScanCls forced any sprite under a moving door into tranche B,
\ so the tiles land on an erased patch and the draw's save picks them
\ up. The tail is the animated tiles' repaint, same class, same
\ window, so one call serves both.
.du_gate
  LDA sprSplit
  BEQ DoorAnimPaint             \ whole pass: repaint here, in window A
  RTS
.DoorAnimPaint
  LDA numDoors
  BEQ du_anim
  LDX #0
.du_dloop
  LDA doorDirty,X
  BEQ du_dnext
  LDA #0
  STA doorDirty,X
  JSR DrawDoorTile
  LDX ddSlot
.du_dnext
  INX
  CPX numDoors
  BCC du_dloop
.du_anim
  JMP AnimPaint

\ Move a patched definition down with its entry. Sixteen bytes, and it
\ happens only when a door closes ahead of one still open.
\ THE INDICES START AT THE TOP OF EACH BLOCK, not the bottom. The loop
\ counts down, so starting at slot*16 walks straight off the front of
\ slot 0's block and wraps to index 255 — writing sixteen bytes of
\ someone else's tile definition over whatever follows doorDef, which
\ is code. That crashed the machine into BASIC, and only once enough
\ doors were open for a compaction to happen at all.
.DoorMoveDef
  STX duSrcSlot
  STY duDstSlot
  CLC
  LDA doorMul16,X : ADC #15 : STA duSrc
  CLC
  LDA doorMul16,Y : ADC #15 : STA duDst
  LDY #15
.dmd_loop
  LDX duSrc
  LDA doorDef,X
  LDX duDst
  STA doorDef,X
  DEC duSrc
  DEC duDst
  DEY
  BPL dmd_loop
  LDX duSrcSlot
  LDY duDstSlot
  RTS

\ ============================================================
\ DrawDoorTile — repaint slot X's 4x4 characters in the buffer
\ ============================================================
\ The door's half of what is now DrawTileCells, in the low-RAM overlay:
\ this works out the tile position and points the generic painter at
\ the door's own patched definition and at the all-sixteen cell list.
\ The body it used to have moved there so that the recharge pad and the
\ ALERT lamp could share it — same code, same argument for it, and 200
\ bytes back out of the one region that is genuinely full.
\ Cells outside the view are still skipped, and they still come out
\ right whenever they scroll in, because the band and column paths
\ consult the patched definition.
.DrawDoorTile
  STX ddSlot
  LDA doorCol,X : STA dtcCol
  LDA doorRow,X : STA dtcRow

  LDA doorMul16,X               \ doorDef + slot * 16, this door's copy
  CLC : ADC #LO(doorDef) : STA dtcDefOp+1
  LDA #0
  ADC #HI(doorDef) : STA dtcDefOp+2

  LDA #LO(dtcCellsAll) : STA dtcListOp+1
  LDA #HI(dtcCellsAll) : STA dtcListOp+2
  JSR DrawTileCells
  LDX ddSlot
  RTS

\ ---- state --------------------------------------------------
\ Absolute, not zero page: none of this is read inside a copy loop.
\ The only door work in a hot path is `LDA numDoors : BEQ`, and that is
\ four cycles a tile on a deck where nothing is open.
.doorCol    SKIP DOOR_SLOTS     \ tile column, 0-63
.doorRow    SKIP DOOR_SLOTS     \ tile row, 0-15
.doorState  SKIP DOOR_SLOTS
.doorDirty  SKIP DOOR_SLOTS     \ needs repainting this pass
.numDoors   EQUB 0
.doorTileRow EQUB 0             \ the tile row the caller is drawing
.dtOfs      EQUB 0              \ added to the patched base by DoorTdp
.dtCol      EQUB 0
.dtSaveX    EQUB 0
.dpCol      EQUB 0
.dpRow      EQUB 0
.dpSlot     EQUB 0
.dpSaveX    EQUB 0
.dsIdx      EQUB 0
.duSaveY    EQUB 0
.duDst      EQUB 0
.duSrc      EQUB 0
.duSrcSlot  EQUB 0
.duDstSlot  EQUB 0
.ddSlot     EQUB 0              \ the rest of DrawDoorTile's state went
                                \ with its body, into lowbss.asm

\ slot -> byte offset of its private definition
.doorMul16  EQUB 0, 16, 32, 48, 64, 80, 96

\ doorDef — the seven patched tile definitions — lives in the DATA BANK.
\ Sideways RAM is RAM, and every routine that reads or writes it runs
\ with SWRAM_DATA paged in: DoorProbe from CheckWalls, DoorTdp from the
\ draw, DoorsUpdate and DrawDoorTile from DoRedraws. The blitter is the
\ only thing that pages it out and it touches none of this. 112 bytes
\ of main RAM back, which is what let Layer 8b fit below &3000 at all.
\ See the bank section in main.asm.
