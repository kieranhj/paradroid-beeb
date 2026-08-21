\ ============================================================
\ zx0depack.asm — a ZX0 (v2) decompressor, in SWRAM bank 4
\ ============================================================
\ LAYER 13d. Decodes the format Einar Saukas' ZX0 emits in its DEFAULT
\ mode — forwards, interlaced Elias gamma, INVERTED new-offset-MSB
\ payload bits — which is exactly what tools/zx0.py produces and
\ round-trip-verifies. Written from the reference compressor's source
\ (BSD-3, https://github.com/einar-saukas/ZX0), not from a recalled
\ depacker, and verified in jsbeeb by diffing every deck's unpacked
\ tile map against the offline decode.
\
\ THE FORMAT, as the stream reader sees it:
\   - the stream opens in a literal run (no flag bit);
\   - after literals, flag 0 = copy from the LAST offset, 1 = new offset;
\   - after any copy,  flag 0 = literals,                1 = new offset;
\   - a length is interlaced gamma: pairs of (continue=0, payload) bits,
\     terminated by a 1, building the value MSB-first from an implicit
\     leading 1;
\   - a new offset is gamma MSB (payload bits INVERTED; the value 256
\     is the end marker), then one byte: (127 - low7) << 1, whose bit 0
\     is the FIRST control bit of the following gamma, which encodes
\     length - 1;
\   - offset = MSB * 128 - (LSB >> 1).
\
\ CALLERS: BuildLevel, with SWRAM_DATA paged — the streams live in this
\ bank and the tile map is main RAM. It is deck-load code: correctness
\ and size over speed, ~40k cycles for a 1,024-byte map.
\
\ ZERO PAGE, borrowed from the level draw's scratch, idle until the
\ level draw runs (which is after this returns):
\   src     -> the compressed stream (the caller's)
\   mapptr  -> the output (the caller's)
\   zxofs     the current offset          (sDelta, 2)
\   zxlen     gamma accumulator / count   (subRowOfs+tileCol, 2)
\   zxbit     the bit buffer, sentinel-marked (colTileCol)
\   zxwrk   -> the copy source            (rptTile/rptLen, 2)

zxofs = sDelta
zxlen = subRowOfs
zxbit = colTileCol
zxwrk = rptTile

.Zx0Unpack
  LDA #1
  STA zxofs
  LDA #0
  STA zxofs+1
  LDA #&80                      \ empty buffer: first ASL empties it and
  STA zxbit                     \ forces a refill

\ ---- a literal run ------------------------------------------
.zx_literals
  JSR zx_gamma                  \ zxlen = run length
.zl_loop
  LDY #0
  LDA (src),Y
  STA (mapptr),Y
  INC src
  BNE zl_1
  INC src+1
.zl_1
  INC mapptr
  BNE zl_2
  INC mapptr+1
.zl_2
  JSR zx_declen
  BNE zl_loop
  JSR zx_getbit
  BCS zx_newofs

\ ---- copy from the last offset ------------------------------
  JSR zx_gamma
  JSR zx_copy
  JSR zx_getbit
  BCC zx_literals

\ ---- a new offset -------------------------------------------
.zx_newofs
  JSR zx_gammai                 \ MSB, inverted payload
  LDA zxlen+1
  BNE zx_done                   \ 256: the end marker
  \ offset = MSB*128 - (LSB>>1) = (MSB>>1)*256 + (MSB AND 1)*128 - (LSB>>1)
  LDA zxlen
  LSR A
  STA zxofs+1
  LDA #0
  ROR A                         \ (MSB AND 1) << 7, C now clear
  STA zxofs
  LDY #0
  LDA (src),Y                   \ the LSB byte
  INC src
  BNE zn_1
  INC src+1
.zn_1
  TAX                           \ keep it: bit 0 is the next control bit
  LSR A                         \ LSB >> 1
  STA zxwrk
  SEC
  LDA zxofs   : SBC zxwrk : STA zxofs
  BCS zn_2
  DEC zxofs+1
.zn_2
  \ length - 1, gamma whose first control bit is X's bit 0
  LDA #1
  STA zxlen
  LDA #0
  STA zxlen+1
  TXA
  LSR A                         \ C = the backtracked control bit
  BCS zn_len1
  JSR zx_gpair                  \ 0: a payload bit follows, then carry on
.zn_len1
  JSR zx_inclen                 \ length = gamma + 1
  JSR zx_copy
  JSR zx_getbit
  BCS zx_newofs
  BCC zx_literals               \ always
.zx_done
  RTS

\ ---- gamma, plain payload -----------------------------------
\ zxlen = the value. Pairs of (continue, payload), terminator 1.
.zx_gamma
  LDA #1
  STA zxlen
  LDA #0
  STA zxlen+1
.zg_loop
  JSR zx_getbit
  BCS zg_done
.zx_gpair                       \ entered here when the control bit was
  JSR zx_getbit                 \ consumed elsewhere (the LSB backtrack)
  ROL zxlen
  ROL zxlen+1
  JMP zg_loop
.zg_done
  RTS

\ ---- gamma, INVERTED payload (the new-offset MSB) -----------
.zx_gammai
  LDA #1
  STA zxlen
  LDA #0
  STA zxlen+1
.zgi_loop
  JSR zx_getbit
  BCS zg_done                   \ shares the RTS above
  JSR zx_getbit
  BCS zgi_zero
  SEC                           \ payload 0 -> inverted 1
  BCS zgi_put
.zgi_zero
  CLC                           \ payload 1 -> inverted 0
.zgi_put
  ROL zxlen
  ROL zxlen+1
  JMP zgi_loop

\ ---- one bit ------------------------------------------------
\ C = the bit. zxbit carries the byte with a sentinel 1 below it;
\ when the sentinel falls out the buffer refills from the stream.
.zx_getbit
  ASL zxbit
  BNE zb_x
  LDY #0
  LDA (src),Y
  INC src
  BNE zb_1
  INC src+1
.zb_1
  SEC                           \ the new sentinel
  ROL A
  STA zxbit
.zb_x
  RTS

\ ---- copy zxlen bytes from mapptr - zxofs -------------------
.zx_copy
  SEC
  LDA mapptr   : SBC zxofs   : STA zxwrk
  LDA mapptr+1 : SBC zxofs+1 : STA zxwrk+1
.zc_loop
  LDY #0
  LDA (zxwrk),Y
  STA (mapptr),Y
  INC zxwrk
  BNE zc_1
  INC zxwrk+1
.zc_1
  INC mapptr
  BNE zc_2
  INC mapptr+1
.zc_2
  JSR zx_declen
  BNE zc_loop
  RTS

\ ---- count zxlen down; Z clear while bytes remain -----------
.zx_declen
  LDA zxlen
  SEC
  SBC #1
  STA zxlen
  BCS zd_1
  DEC zxlen+1
.zd_1
  LDA zxlen
  ORA zxlen+1
  RTS

.zx_inclen
  INC zxlen
  BNE zi_1
  INC zxlen+1
.zi_1
  RTS
