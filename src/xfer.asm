\ ============================================================
\ xfer.asm — the transfer minigame's board
\ ============================================================
\ LAYER 10, and **only the board**. None of the game is here: no pulsers,
\ no gates, no CPU opponent, no control bar. What this file does is draw
\ the static layout, which is the one part of the minigame that needs no
\ decision taken first — and taking those decisions is KC's, not this
\ session's. docs/layer-10-transfer.md sets them out.
\
\ It is reachable as the console's third page so that it can be looked at
\ without a build flag. That is a scaffold, not a design: when the game
\ itself is built it will be entered from Capture ($229D) through
\ DoCollision's transfer arm, and the console will lose the page.
\
\ ---- what the board is -------------------------------------
\ SubGameSelectSide ($E016) writes three rows, then ONE row twelve times,
\ then one more. Each of the twelve is a wire running from the player's
\ vertical bus at column 3, right along columns 4-17 into the central
\ result bar at 19-20, and the mirror from the CPU's bus at column 36.
\
\ ELEVEN HERE, NOT TWELVE. The board is 16 rows and PLAY_VIS_ROWS is 15,
\ and dropping one of the identical middle rows is the cheapest of the
\ three ways out — see docs/layer-10-transfer.md section 6. It is this
\ constant and nothing else, so it is easy to put back if the board ends
\ up somewhere with the room.
XF_MID_ROWS = PLAY_VIS_ROWS - 4
ASSERT XF_MID_ROWS == 11

\ ============================================================
\ XferBoard — draw the static board into the play area
\ ============================================================
\ Entered with the scroll already flattened by ConsoleOpen, so a buffer
\ row is flatly BUF_BASE + row*ROW_BYTES and there is no wrap to think
\ about. A character is 8 px, which is 16 bytes and two CRTC units, so a
\ row is exactly 40 of them — the same flat copy the tile draw makes.
.XferBoard
  LDA #LO(BUF_BASE) : STA pnDst
  LDA #HI(BUF_BASE) : STA pnDst+1

  LDA #LO(xbTop) : STA xfSrc
  LDA #HI(xbTop) : STA xfSrc+1
  LDA #3
  JSR XfRows

  LDA #XF_MID_ROWS              \ the same row, over and over
  STA xfCount
.xf_mid
  LDA #LO(xbMid) : STA xfSrc
  LDA #HI(xbMid) : STA xfSrc+1
  LDA #1
  JSR XfRows
  DEC xfCount
  BNE xf_mid

  LDA #LO(xbBottom) : STA xfSrc
  LDA #HI(xbBottom) : STA xfSrc+1
  LDA #1
  JMP XfRows                    \ and its RTS

\ ---- A rows of 40 glyph indices from xfSrc, at pnDst ---------
\ ZERO PAGE IS FULL and this needs three pointers where there are two.
\ pnDst is swDst and the glyph pointer takes pnSrc, which is swSrc and
\ free here because PnGlyph is not running; the ROW pointer has none left
\ and is a patched absolute instead, exactly as PnStr's is and for the
\ same reason. This file assembles into bank 6, which is RAM.
.XfRows
  STA xfRows
.xf_row
  LDA xfSrc   : STA xf_get+1
  LDA xfSrc+1 : STA xf_get+2
  LDA #0
  STA xfCol
.xf_col
  LDY xfCol                     \ glyph index -> xbChars + index*16
.xf_get
  LDA &FFFF,Y
  ASL A : ASL A : ASL A : ASL A \ *16, and it cannot carry: XB_CHARS is 16
  CLC
  ADC #LO(xbChars) : STA pnSrc
  LDA #0
  ADC #HI(xbChars) : STA pnSrc+1

  LDY #15
.xf_byte
  LDA (pnSrc),Y
  STA (pnDst),Y
  DEY
  BPL xf_byte

  CLC                           \ on to the next character: 16 bytes
  LDA pnDst   : ADC #16 : STA pnDst
  LDA pnDst+1 : ADC #0  : STA pnDst+1

  INC xfCol
  LDA xfCol
  CMP #XB_COLS
  BNE xf_col

\ pnDst has walked exactly ROW_BYTES — 40 characters of 16 — so it is
\ already on the next row and needs no correction.
  CLC
  LDA xfSrc   : ADC #XB_COLS : STA xfSrc
  LDA xfSrc+1 : ADC #0       : STA xfSrc+1
  DEC xfRows
  BNE xf_row
  RTS

.xfSrc   EQUW 0
.xfRows  EQUB 0
.xfCol   EQUB 0
.xfCount EQUB 0
