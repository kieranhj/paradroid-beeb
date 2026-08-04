\ ============================================================
\ macros.asm — BeebASM helper macros for Paradroid CE BBC port
\ ============================================================

\ Write a byte to a CRTC register
MACRO CRTC_WRITE reg, val
  LDA #reg
  STA CRTC_ADDR
  LDA #val
  STA CRTC_DATA
ENDMACRO

\ Write a value in A to a CRTC register number in X
MACRO CRTC_WRITE_A reg
  LDX #reg
  STX CRTC_ADDR
  STA CRTC_DATA
ENDMACRO

\ Set ACCCON, preserving flags
MACRO ACCCON_SET mask
  LDA bbcAcccon
  ORA #mask
  STA ACCCON
  STA bbcAcccon
ENDMACRO

MACRO ACCCON_CLR mask
  LDA bbcAcccon
  AND #(mask EOR &FF)
  STA ACCCON
  STA bbcAcccon
ENDMACRO

\ Write to SN76489 via System VIA port A
MACRO SN_WRITE
  \ A = byte to write
  STA SND_DATA
ENDMACRO
