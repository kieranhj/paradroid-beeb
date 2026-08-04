\ ============================================================
\ hal_irq.asm — BBC Master interrupt handlers
\
\ Replaces the C64's 4-stage raster IRQ chain with:
\   1. VSYNC IRQ  (System VIA CA1, fires at end of each frame)
\   2. Timer 1 IRQ (User VIA T1, fires at scanline 200 for HUD split)
\ ============================================================

\ ============================================================
\ BBC_IRQ_Handler — top-level IRQ dispatcher
\ Called by BBC MOS through IRQ1V ($0204/$0205).
\ MOS has already saved A at $FC and PC/P on stack before calling us.
\ We must save X, Y ourselves.
\ ============================================================
.BBC_IRQ_Handler
  TXA
  PHA
  TYA
  PHA

  \ Check User VIA IFR first (Timer 1 = mid-frame rupture)
  LDA USR_VIA_IFR
  AND #USR_IFR_T1
  BNE irq_timer1

  \ Check System VIA IFR for VSYNC (CA1)
  LDA SYS_VIA_IFR
  AND #SYS_IFR_CA1
  BNE irq_vsync

  \ Not our interrupt — chain to old handler
  PLA
  TAY
  PLA
  TAX
  JMP (bbcOldIrqLo)             \ indirect jump via our saved vector

.irq_vsync
  \ --- VSYNC interrupt handler ---

  \ 1. Acknowledge System VIA CA1 interrupt
  LDA #SYS_IFR_CA1
  STA SYS_VIA_IFR

  \ 2. Update CRTC scroll position for game viewport
  \    (must be done immediately at VSYNC for clean display)
  JSR HAL_UpdateCRTCFromPos
  JSR HAL_SetCRTCScroll

  \ 3. Swap display buffers (show the frame we just drew)
  JSR HAL_SwapBuffers

  \ 4. Signal game loop: new frame available
  INC irqToggle

  \ 5. Sprite-sprite collision detection (replaces C64 Irq_246 $D01E read)
  JSR HAL_CollisionScan

  \ 6. Arm User VIA Timer 1 for mid-frame fire at ~scanline 200
  \    Timer counts at 1 MHz; latch = (200 - 3) * 64 = 12608 = &3140
  \    Subtract latency: ~3 scanlines * 64 = 192 cycles
  LDA #LO(TIMER1_LATCH)
  STA USR_VIA_T1LL
  LDA #HI(TIMER1_LATCH)
  STA USR_VIA_T1LH
  \ Write to T1CH starts the timer (one-shot)
  LDA #HI(TIMER1_LATCH)
  STA USR_VIA_T1CH

  JMP irq_done

.irq_timer1
  \ --- Timer 1 IRQ: mid-frame rupture (scanline ~200) ---

  \ 1. Acknowledge User VIA T1 interrupt by reading T1CL
  LDA USR_VIA_T1CL

  \ 2. Repoint CRTC at HUD buffer (vertical rupture)
  JSR HAL_SetHUDScroll

  \ fall through to irq_done

.irq_done
  PLA
  TAY
  PLA
  TAX
  \ MOS will pull A from $FC and RTI
  LDA &FC                       \ restore A that MOS saved
  RTI

\ ============================================================
\ HAL_CollisionScan — software bounding-box collision detection
\ Replaces C64 Irq_246 read of VIC-II $D01E.
\ Scans all active sprite pairs for overlap; writes result
\ bitmask to SprSprCollision ($4F), matching C64 format.
\
\ C64 $D01E: bit N set if sprite N collided with any other sprite.
\ We produce the same: if sprite A and sprite B overlap, set bit A
\ and bit B in SprSprCollision.
\
\ Sprite slots: 0–7, each with:
\   sprActive[N]  at SPR_STATE + N * SPR_SLOT_SZ + 0
\   sprX[N]       at SPR_STATE + N * SPR_SLOT_SZ + 1 (lo)
\   sprX+1[N]     at SPR_STATE + N * SPR_SLOT_SZ + 2 (hi)
\   sprY[N]       at SPR_STATE + N * SPR_SLOT_SZ + 3
\ ============================================================
.HAL_CollisionScan
  LDA #0
  STA SprSprCollision

  \ Outer loop: sprite A = 0..6
  LDX #0
.hcs_outer
  \ Load sprite A active flag
  LDA SPR_STATE, X              \ base offset for slot X = X * SPR_SLOT_SZ
  \ (We can't index SPR_STATE by X directly since SPR_SLOT_SZ=160;
  \  use ptr_12 as pointer to sprite A slot)

  \ Build pointer to sprite A: ptr_12 = SPR_STATE + X * SPR_SLOT_SZ
  LDA #LO(SPR_STATE)
  STA ptr_12
  LDA #HI(SPR_STATE)
  STA ptr_12+1
  \ Add X * 160 = X * 128 + X * 32
  TXA
  ASL A : ASL A : ASL A : ASL A : ASL A \ X * 32
  CLC : ADC ptr_12 : STA ptr_12
  BCC hcs_a_noc1 : INC ptr_12+1
.hcs_a_noc1
  TXA
  ASL A : ASL A : ASL A : ASL A : ASL A : ASL A : ASL A \ X * 128
  CLC : ADC ptr_12 : STA ptr_12
  BCC hcs_a_noc2 : INC ptr_12+1
.hcs_a_noc2

  \ Check if sprite A is active
  LDY #0
  LDA (ptr_12), Y
  BEQ hcs_next_a               \ skip inactive sprites

  \ Load sprite A position into tmp1 (X8), tmp2 (Y8)
  INY : LDA (ptr_12), Y : STA byte_0_2  \ sprXlo_A
  INY : LDA (ptr_12), Y : STA byte_0_3  \ sprXhi_A (not needed for 8-bit check)
  INY : LDA (ptr_12), Y : STA tmp1      \ sprY_A

  \ Inner loop: sprite B = X+1..7
  STX currentIdx                \ save outer index
  INX
  CPX #8
  BCS hcs_next_a

.hcs_inner
  \ Build pointer to sprite B: dest = SPR_STATE + X * SPR_SLOT_SZ
  LDA #LO(SPR_STATE)
  STA dest
  LDA #HI(SPR_STATE)
  STA dest+1
  TXA
  ASL A : ASL A : ASL A : ASL A : ASL A
  CLC : ADC dest : STA dest
  BCC hcs_b_noc1 : INC dest+1
.hcs_b_noc1
  TXA
  ASL A : ASL A : ASL A : ASL A : ASL A : ASL A : ASL A
  CLC : ADC dest : STA dest
  BCC hcs_b_noc2 : INC dest+1
.hcs_b_noc2

  \ Check sprite B active
  LDY #0
  LDA (dest), Y
  BEQ hcs_next_b

  \ Load sprite B X (lo), Y
  INY : LDA (dest), Y : STA xfer_DeltaX      \ sprXlo_B
  INY : INY
  LDA (dest), Y : STA xfer_DeltaX+1          \ sprY_B

  \ Bounding box check (16 × 16 sprites):
  \ Overlap if: |Ax - Bx| < 16 AND |Ay - By| < 16
  \ X axis (8-bit comparison using low bytes only)
  SEC
  LDA byte_0_2
  SBC xfer_DeltaX
  BCS hcs_ax_ok
  EOR #&FF                      \ abs
  INC A
.hcs_ax_ok
  CMP #16
  BCS hcs_next_b                \ no X overlap

  \ Y axis
  SEC
  LDA tmp1
  SBC xfer_DeltaX+1
  BCS hcs_ay_ok
  EOR #&FF
  INC A
.hcs_ay_ok
  CMP #16
  BCS hcs_next_b                \ no Y overlap

  \ Collision! Set bits for sprite A (currentIdx) and sprite B (X) in SprSprCollision
  LDY currentIdx
  LDA bits_table, Y
  ORA SprSprCollision
  STA SprSprCollision
  LDA bits_table, X
  ORA SprSprCollision
  STA SprSprCollision

.hcs_next_b
  INX
  CPX #8
  BCC hcs_inner

.hcs_next_a
  LDX currentIdx
  INX
  CPX #7
  BCC hcs_outer

  RTS

\ bits_table: bit N set in byte N (matches C64 'bits' array at $095E)
.bits_table
  EQUB &01, &02, &04, &08, &10, &20, &40, &80
