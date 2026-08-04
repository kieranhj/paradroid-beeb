\ ============================================================
\ hal_video.asm — CRTC init, MODE 2 virtual buffer, shadow RAM,
\                 double-buffer swap, CRTC scroll
\ ============================================================

\ ============================================================
\ HAL_InitCRTC
\ Configure 6845 CRTC for virtual scroll buffer and HUD split.
\
\ MODE 2 with virtual buffer (192 × 208 px, 96 bytes/scanline):
\   R0  = 63    total horizontal characters - 1 (64 µs/line)
\   R1  = 48    displayed characters (96 bytes/line at 2 bytes/CRTC char)
\               NOTE: standard MODE 2 OS sets R1=40; we use 48 for virtual buf
\               The extra 8 chars (16 px) fall in right border — harmless
\   R2  = 49    horizontal sync position (standard)
\   R3  = $24   H/V sync widths (standard)
\   R4  = 38    vertical total - 1 (39 character rows)
\   R5  = 0     vertical total adjust
\   R6  = 32    vertical displayed rows (256 scanlines = 32 × 8)
\   R7  = 34    vertical sync position (standard)
\   R8  = $00   interlace off
\   R9  = 7     max scan line (8 lines per character row)
\   R10 = $20   cursor off (bits 5–6 = 01 = cursor invisible)
\   R11 = 0     cursor end
\   R12 = $00   start address high (SCREEN_BASE / 8 / 256 = 0)
\   R13 = $00   start address low
\
\ IMPORTANT: After testing in emulator, these values may need adjustment.
\ The key values to verify are R1 (virtual buffer width) and R12/R13.
\ ============================================================
.HAL_InitCRTC
  \ Wait for any pending CRTC writes to settle
  LDA #CRTC_R0 : STA CRTC_ADDR : LDA #63    : STA CRTC_DATA
  LDA #CRTC_R1 : STA CRTC_ADDR : LDA #48    : STA CRTC_DATA \ virtual buf width
  LDA #CRTC_R2 : STA CRTC_ADDR : LDA #49    : STA CRTC_DATA
  LDA #CRTC_R3 : STA CRTC_ADDR : LDA #&24   : STA CRTC_DATA
  LDA #CRTC_R4 : STA CRTC_ADDR : LDA #38    : STA CRTC_DATA
  LDA #CRTC_R5 : STA CRTC_ADDR : LDA #0     : STA CRTC_DATA
  LDA #CRTC_R6 : STA CRTC_ADDR : LDA #32    : STA CRTC_DATA
  LDA #CRTC_R7 : STA CRTC_ADDR : LDA #34    : STA CRTC_DATA
  LDA #CRTC_R8 : STA CRTC_ADDR : LDA #0     : STA CRTC_DATA
  LDA #CRTC_R9 : STA CRTC_ADDR : LDA #7     : STA CRTC_DATA
  LDA #CRTC_R10: STA CRTC_ADDR : LDA #&20   : STA CRTC_DATA \ cursor off
  LDA #CRTC_R11: STA CRTC_ADDR : LDA #0     : STA CRTC_DATA

  \ Set start address: CRTC 0 → SCREEN_BASE
  \ With physical = SCREEN_BASE + CRTC_addr * 2 + RA * VBUF_BYTES,
  \ CRTC_addr = 0 maps to SCREEN_BASE as required.
  LDA #0
  STA bbcCrtcHi
  STA bbcCrtcLo
  LDA #CRTC_R12 : STA CRTC_ADDR : LDA #0    : STA CRTC_DATA
  LDA #CRTC_R13 : STA CRTC_ADDR : LDA #0    : STA CRTC_DATA

  \ Calculate HUD start address (after virtual scroll buffer):
  \ HUD starts at row 200 (= 200 scanlines from top).
  \ Virtual buffer top offset (1 row × VBUF_BYTES = 96 padding) skipped.
  \ Display viewport starts at CRTC_addr = 96/2 = 48 (1 row of virtual padding).
  \ HUD start = viewport_start + 200 scanlines.
  \ CRTC for 200 scanlines = (200 * VBUF_BYTES) / 2 = 200 * 48 = 9600 = &2580
  \ But HUD is outside virtual buffer (fixed), so it starts at:
  \   SCREEN_BASE + VBUF_BYTES * VBUF_ROWS * 8 (total virtual buf bytes ÷ 8 scanlines)
  \ Wait — HUD is appended after virtual buffer in screen memory.
  \ Virtual buffer: VBUF_BYTES * (VBUF_ROWS * 8) = 96 * 208 = 19968 bytes
  \ HUD starts at physical: SCREEN_BASE + 19968 = &3000 + &4E00 = &7E00
  \ CRTC_addr for HUD = 19968 / 2 = 9984 = &2700
  \ R12 = &2700 >> 8 = &27, R13 = &00
  LDA #&27
  STA bbcHudCrtcHi
  LDA #&00
  STA bbcHudCrtcLo

  RTS

\ ============================================================
\ HAL_SwapBuffers
\ Toggle which buffer is displayed (ACCCON bit 3 = SHADOW).
\ The back buffer (CPU writes to) alternates between shadow and main RAM.
\ Called at VSYNC after frame draw is complete.
\ ============================================================
.HAL_SwapBuffers
  LDA bbcDisplayPage
  EOR #1
  STA bbcDisplayPage
  BNE hab_show_shadow

  \ Show main RAM (ACCCON SHADOW = 0)
  LDA bbcAcccon
  AND #(ACCCON_SHADOW EOR &FF)
  STA bbcAcccon
  STA ACCCON
  RTS

.hab_show_shadow
  \ Show shadow RAM (ACCCON SHADOW = 1)
  LDA bbcAcccon
  ORA #ACCCON_SHADOW
  STA bbcAcccon
  STA ACCCON
  RTS

\ ============================================================
\ HAL_SetBackBuffer
\ Point CPU at the back (hidden) buffer for drawing.
\ If shadow RAM is currently displayed (bbcDisplayPage = 1),
\ CPU must write to main RAM (ACCCON_CPU = 0).
\ If main RAM is displayed (bbcDisplayPage = 0),
\ CPU must write to shadow RAM (ACCCON_CPU = 1).
\ ============================================================
.HAL_SetBackBuffer
  LDA bbcDisplayPage
  BNE hab_back_is_main
  \ Shadow is back buffer: enable CPU shadow write
  ACCCON_SET ACCCON_CPU
  RTS
.hab_back_is_main
  \ Main RAM is back buffer: disable CPU shadow
  ACCCON_CLR ACCCON_CPU
  RTS

\ ============================================================
\ HAL_ClearBackBuffer
\ Clear the entire back buffer to colour 0 (black).
\ Assumes CPU is already pointing at back buffer.
\ ============================================================
.HAL_ClearBackBuffer
  JSR HAL_SetBackBuffer
  LDA #LO(SCREEN_BASE)
  STA dest
  LDA #HI(SCREEN_BASE)
  STA dest+1
  LDA #0
  LDY #0
  LDX #(20480 / 256)            \ 20K / 256 = 80 pages
.hcb_loop
  STA (dest),Y
  INY
  BNE hcb_loop
  INC dest+1
  DEX
  BNE hcb_loop
  ACCCON_CLR ACCCON_CPU
  RTS

\ ============================================================
\ HAL_SetCRTCScroll
\ Write new scroll position to CRTC R12/R13.
\ Called from VSYNC IRQ to set viewport top-left.
\
\ Input: bbcCrtcHi, bbcCrtcLo = target CRTC start address
\        (computed by HAL_UpdateCRTCFromPos)
\ ============================================================
.HAL_SetCRTCScroll
  LDA #CRTC_R12
  STA CRTC_ADDR
  LDA bbcCrtcHi
  STA CRTC_DATA
  LDA #CRTC_R13
  STA CRTC_ADDR
  LDA bbcCrtcLo
  STA CRTC_DATA
  RTS

\ ============================================================
\ HAL_SetHUDScroll
\ Restore CRTC R12/R13 to point at the fixed HUD buffer.
\ Called from Timer 1 IRQ at scanline 200.
\ ============================================================
.HAL_SetHUDScroll
  LDA #CRTC_R12
  STA CRTC_ADDR
  LDA bbcHudCrtcHi
  STA CRTC_DATA
  LDA #CRTC_R13
  STA CRTC_ADDR
  LDA bbcHudCrtcLo
  STA CRTC_DATA
  RTS

\ ============================================================
\ HAL_UpdateCRTCFromPos
\ Recompute bbcCrtcHi/Lo from ScreenPosX, ScreenPosY.
\
\ ScreenPosX: 16-bit pixel position; ScreenPosX+1 = integer pixels
\ ScreenPosY: 16-bit pixel position; ScreenPosY+1 = integer pixels
\
\ CRTC start address formula (for CRTC_R1 = 48, 2 bytes per CRTC char):
\   CRTC_addr = (ScreenPosY_px * VBUF_BYTES / 2) + (ScreenPosX_px / 2)
\             + virtual_top_pad (1 row = VBUF_BYTES / 2 = 48 CRTC units)
\             + virtual_left_pad (2 cols = 4 CRTC units, i.e., 2 tiles × 4 px/char... hmm)
\
\ TODO: Exact formula needs verification in emulator.
\ For now, compute a simplified version:
\   CRTC_addr = (ScreenPosY * 48) + (ScreenPosX / 2) + 48 + 4
\
\ ScreenPosX / 2: divide 16-bit pos by 2 (shift right 1)
\ ScreenPosY * 48: multiply — use 8-bit approximation for small levels
\ ============================================================
.HAL_UpdateCRTCFromPos
  \ Use high byte of ScreenPosX/Y as integer pixel positions.
  \ For simplicity, treat ScreenPosX/Y as tile-level:
  \ ScreenPosX+1 = integer X pixels
  \ ScreenPosY+1 = integer Y pixels (= scanlines to scroll)

  \ Compute CRTC_addr (16-bit) = Y_px * 48 + X_px/2 + (1 row + 2 tile padding)
  \ Use src as temp 16-bit accumulator

  \ --- Y * 48 ---
  \ 48 = 32 + 16 = ScreenPosY * (32 + 16)
  LDA ScreenPosY+1              \ integer scanline offset
  TAX
  \ src = X * 32
  ASL A
  ROL src+1
  ASL A
  ROL src+1
  ASL A
  ROL src+1
  ASL A
  ROL src+1
  ASL A
  ROL src+1
  STA src
  \ tmp = X * 16
  TXA
  ASL A
  ROL dest+1
  ASL A
  ROL dest+1
  ASL A
  ROL dest+1
  ASL A
  ROL dest+1
  STA dest
  \ src = X*32 + X*16 = X*48
  CLC
  LDA src
  ADC dest
  STA src
  LDA src+1
  ADC dest+1
  STA src+1

  \ --- Add X_px / 2 ---
  LDA ScreenPosX+1              \ integer X pixels
  LSR A                         \ / 2 = bytes from left edge
  CLC
  ADC src
  STA src
  BCC huc_noc
  INC src+1
.huc_noc

  \ --- Add top/left padding (1 row = 48, 2 tile cols = 4 units * 2 bytes = 4 CRTC) ---
  CLC
  LDA src
  ADC #(48 + 4)                 \ 1 row pad + 2-col left pad (4 CRTC chars)
  STA src
  BCC huc_noc2
  INC src+1
.huc_noc2

  \ Store into bbcCrtcHi/Lo
  LDA src+1
  STA bbcCrtcHi
  LDA src
  STA bbcCrtcLo
  RTS
