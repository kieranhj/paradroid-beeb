\ ============================================================
\ player.asm — reading the controls and moving the view
\ ============================================================
\ Ported from the C64: ReadJoystick ($091A), CalcSpeed ($39F9) and
\ DoMove ($3849). The player never moves on screen — it is pinned
\ at the centre and the deck scrolls underneath — so "moving the
\ player" is moving the view, and the speed model belongs here.
\
\ Speed is 8.8 signed fixed point. The low byte is the fraction the
\ acceleration accumulates into; the high byte is whole pixels, and
\ is what actually moves the view.
\
\ THE C64 NUMBERS ARE PER GameLoop ITERATION, NOT PER FRAME, AND AN
\ ITERATION IS NOT A FRAME. This is the whole reason the constants
\ below are not the ones in the listing, and taking the listing's
\ numbers literally made the player move at twice the speed of the
\ original.
\
\ GameLoop ($13DA) has five reads of irqToggle that look like frame
\ waits. Three of them — $13DC, $13F5, $13FC — assemble as D0 00 and
\ F0 00: branch offset zero, falling through to the next instruction.
\ Redux patched them out and the listing marks them "!! remove". Only
\ _w4 ($1417, F0 FC) and EnterGame ($1430, D0 FC) really spin, one on
\ each edge of irqToggle, which Irq_254 sets and the raster handler
\ at $6FB1 clears. So the loop is bounded by ONE rising and ONE
\ falling edge — one frame, IF the work fits in a frame.
\
\ It does not. DrawScreen ($391A) copies 17 rows of 39 characters to
\ screen RAM and colour RAM, and its inner loop is 26 cycles:
\
\   LDA $4940,Y 4 / STA (dest),Y 6 / TAX 2 /
\   LDA CharColor,X 4 / STA $D940,Y 5 / DEY 2 / BPL 3
\
\ 663 characters x 26 = ~17,250 cycles, against roughly 18,300 usable
\ in a PAL frame once badline and sprite DMA are taken out. DrawScreen
\ alone very nearly fills a frame, before RunDroids, DoCollision,
\ AnimateDroids or the sound driver have run. An iteration is 2 to 3
\ frames, drifting towards 3 as a deck fills with droids.
\
\ The game loop is locked to FRAME_LOCK = 2 fields, so ONE pass of it
\ is one C64 iteration and the original's constants apply unchanged:
\ 7 px per iteration, 208/256 accel, 176/256 decel, 0.34 s from a
\ standing start to top speed. Same motion, same cadence.
\
\ It did not start that way. The loop used to run every field with
\ everything halved — 3.5 px per field, quarter acceleration — which
\ sampled the same motion at 50 Hz and was genuinely smoother than the
\ original. That is the better-looking option and it was given up for
\ a reason: with a full sprite pool the loop no longer fits in a
\ field, so free-running quietly stretched to 1.25 fields an iteration
\ and the player moved 20% slower with droids on screen than without.
\ Speed that depends on what is visible is worse than speed that is
\ merely chunkier, so the rate is now fixed and the smoothness is what
\ pays for the droids.
\
\ Two numbers set the feel, and they scale together:
\   FRAME_LOCK       fields per pass of our loop     (main.asm)
\   PLY_ITER_FRAMES  fields the C64 spends per iteration
\ Raise FRAME_LOCK alone and the game speeds up while the rate drops;
\ raise PLY_ITER_FRAMES alone and everything slows together, keeping
\ the acceleration curve's shape.
\
\ Top speed comes from PlayerSpeed_t ($6D97) indexed through
\ DSpeed_t ($EA40) by droid type. The player starts as droid 001,
\ type 0: DSpeed_t[0] = 4, PlayerSpeed_t[4] = 7 — the fastest thing
\ in the game. 001 is quick and fragile, which is the point of it.
\
\ The C64's accelerate-negative path is one 256th weaker than its
\ positive one, an artefact of the SEC/ADC idiom it uses to subtract.
\ We subtract properly, so both directions match.
\ ============================================================

PLY_ITER_FRAMES = 2             \ TV frames per C64 GameLoop iteration

C64_ACCEL  = 208                \ Acceleration_    $6955, per iteration
C64_DECEL  = 176                \ DecelerationNeg_ $6954, per iteration
C64_MAXSPD = 7                  \ PlayerSpeed_t[DSpeed_t[0]], px per iteration

\ The C64's numbers are per ITERATION; ours are applied once per
\ game-loop pass, which is FRAME_LOCK fields long. So the scale factor
\ is FRAME_LOCK / PLY_ITER_FRAMES — fields we get per pass over fields
\ the C64 takes per iteration. Velocity scales by it once, acceleration
\ twice. At FRAME_LOCK = 2 the two cancel and these are the C64's own
\ values, unmodified.
PLY_ACCEL  = (C64_ACCEL * FRAME_LOCK * FRAME_LOCK) / (PLY_ITER_FRAMES * PLY_ITER_FRAMES)
PLY_DECEL  = (C64_DECEL * FRAME_LOCK * FRAME_LOCK) / (PLY_ITER_FRAMES * PLY_ITER_FRAMES)
PLY_MAXSPD = (C64_MAXSPD * 256 * FRAME_LOCK) / PLY_ITER_FRAMES  \ 8.8
PLY_MAXNEG = 65536 - PLY_MAXSPD

\ The redraw brings in ONE whole character row per pass, because a
\ pass can cross at most one row boundary. At 8 px or more it could
\ cross two, the second would never be drawn, and the strip would
\ hold a stale row that only shows once it scrolls into view — so
\ this is a hard ceiling on the vertical speed, not a preference.
ASSERT PLY_MAXSPD <= 8 * 256

MAX_PX_X = (MAP_CHAR_W * 8) - 320       \ 1728, view origin
MAX_PX_Y = MAX_Y * 8                    \ 384; mapYr must not pass MAX_Y,
                                        \ or the split row reads map row 64
MAX_PLY_X = (MAP_CHAR_W * 8) - 24       \ 2024, sprite left edge

\ The camera window. The sprite's home is the C64's, 148 px from the
\ left of the view: PlayerSprite_dat puts sprite 7 at VIC x 172,
\ which is screen 148, and that is exactly (320-24)/2.
PLY_HOME_X   = 148
PLY_DEADZONE = 8
PLY_DZ_MIN   = PLY_HOME_X - PLY_DEADZONE
PLY_DZ_MAX   = PLY_HOME_X + PLY_DEADZONE

\ ============================================================
\ ReadKeys — joyXDir / joyYDir, each -1, 0 or +1
\ ============================================================
\ Opposite keys cancel, which falls out of the DEC/INC pair rather
\ than needing a test. That matters: the previous build had to make
\ up and down mutually exclusive by hand because both recorded into
\ one deferred-draw slot, and the second overwrote the first.
.ReadKeys
  LDA #0
  STA joyXDir
  STA joyYDir

  LDX #KEY_Z
  JSR keydown
  BNE rk_notZ
  DEC joyXDir
.rk_notZ
  LDX #KEY_X
  JSR keydown
  BNE rk_notX
  INC joyXDir
.rk_notX

  LDX #KEY_K
  JSR keydown
  BNE rk_notK
  DEC joyYDir
.rk_notK
  LDX #KEY_M
  JSR keydown
  BNE rk_notM
  INC joyYDir
.rk_notM
  RTS

\ ============================================================
\ CalcAxis — one axis of CalcSpeed
\   spd    = 16-bit signed speed, 8.8
\   axDir  = -1, 0 or +1
\ ============================================================
.CalcAxis
  LDA axDir
  BEQ ca_coast
  BMI ca_neg
  CLC                           \ accelerate positive
  LDA spd   : ADC #LO(PLY_ACCEL) : STA spd
  LDA spd+1 : ADC #HI(PLY_ACCEL) : STA spd+1
  JMP ca_clamp
.ca_neg
  SEC                           \ accelerate negative
  LDA spd   : SBC #LO(PLY_ACCEL) : STA spd
  LDA spd+1 : SBC #HI(PLY_ACCEL) : STA spd+1
  JMP ca_clamp

\ Coasting. Decelerate towards zero and STOP there rather than
\ overshooting into a crawl the other way — the sign of the high
\ byte flipping is the test, exactly as the C64 does it.
.ca_coast
  LDA spd+1
  BMI ca_coastneg
  ORA spd
  BEQ ca_clamp                  \ already stopped
  SEC
  LDA spd   : SBC #LO(PLY_DECEL) : STA spd
  LDA spd+1 : SBC #HI(PLY_DECEL) : STA spd+1
  LDA spd+1
  BPL ca_clamp
  JMP ca_stop
.ca_coastneg
  CLC
  LDA spd   : ADC #LO(PLY_DECEL) : STA spd
  LDA spd+1 : ADC #HI(PLY_DECEL) : STA spd+1
  LDA spd+1
  BMI ca_clamp
.ca_stop
  LDA #0
  STA spd
  STA spd+1
  RTS

\ The clamp is 16-bit. The C64's was a byte compare against the whole
\ pixel count, which it could afford because its top speed was a
\ whole number of pixels per iteration; ours is 3.5 per frame, so the
\ fraction is part of the limit rather than something to throw away.
\
\ Both sides of the negative compare are above &8000, so an unsigned
\ comparison orders them the same way a signed one would.
.ca_clamp
  LDA spd+1
  BMI ca_clampneg
  CMP #HI(PLY_MAXSPD)
  BCC ca_x
  BNE ca_setmax
  LDA spd
  CMP #LO(PLY_MAXSPD)
  BCC ca_x
  BEQ ca_x
.ca_setmax
  LDA #LO(PLY_MAXSPD) : STA spd
  LDA #HI(PLY_MAXSPD) : STA spd+1
  RTS
.ca_clampneg
  CMP #HI(PLY_MAXNEG)
  BCC ca_setmin
  BNE ca_x
  LDA spd
  CMP #LO(PLY_MAXNEG)
  BCS ca_x
.ca_setmin
  LDA #LO(PLY_MAXNEG) : STA spd
  LDA #HI(PLY_MAXNEG) : STA spd+1
.ca_x
  RTS

\ ============================================================
\ CalcSpeed — both axes
\ ============================================================
\ CalcAxis works on one pair of zero page bytes, so each axis is
\ copied in and out. Twice a frame, for about 40 cycles.
.CalcSpeed
  LDA xSpd   : STA spd
  LDA xSpd+1 : STA spd+1
  LDA joyXDir : STA axDir
  JSR CalcAxis
  LDA spd   : STA xSpd
  LDA spd+1 : STA xSpd+1

  LDA ySpd   : STA spd
  LDA ySpd+1 : STA spd+1
  LDA joyYDir : STA axDir
  JSR CalcAxis
  LDA spd   : STA ySpd
  LDA spd+1 : STA ySpd+1
  RTS

\ ============================================================
\ CheckWalls — port of CheckPlyAdvance ($29C1) and GetNearChar
\ ============================================================
\ Twelve probe cells around the player, arranged as a diamond. The
\ comment in the listing at $6B52 draws it, x being the player:
\
\     . 0 . 1 .
\     6 . 2 . 9
\     . 7 x A .
\     8 . 3 . B
\     . 4 . 5 .
\
\ so 9-B guard the right, 6-8 the left, 3-5 below and 0-2 above. A
\ probe only counts if the player is moving that way, which is what
\ lets the player slide along a wall instead of sticking to it.
\
\ A cell is solid if its CHARACTER CODE has bit 7 set — the same
\ test the droid AI uses at CheckDroidAdvance. Hitting one kills
\ that axis's speed outright and snaps the view to the character
\ grid, so the player ends up flush against the wall rather than
\ embedded in it by however far the last step overshot.
\
\ The reference cell is the middle of the sprite: the C64 puts the
\ player at screen (148, 122) with plyMapPos at character column
\ origin+19, row origin+8, which is the cell covering sprite pixels
\ 4-11 across and 6-13 down — the digit block. PLY_REFX/Y place ours
\ on the same part of the sprite.
\
\ The +7 in the offsets is load-bearing and cost a bug. DrawScreen
\ ($391A) derives the character origin as (ScreenPosX + 7) >> 3 —
\ rounding UP — and plyMapPos is that plus 19. Round DOWN instead
\ and the snap moves the reference cell: snapping to a character
\ boundary tips (posX + 152) >> 3 over to the next cell, the whole
\ probe diamond shifts right by one, the wall drops out of the
\ probes, and the player drifts back into it next frame. It sat
\ against the wall visibly jittering one pixel.
\
\ With the +7 the snap cannot change the reference cell — it only
\ removes the sub-character remainder — which is the property the
\ whole scheme depends on.
\
\   159 = 148 (sprite left)  + 11
\    63 =  50 (sprite top)   + 13
\
\ putting the reference cell over the middle of the sprite, the same
\ part of it the C64 uses: the digit block.
PLY_REFX = 11                   \ from the sprite's left edge; 148 + 11 = 159
PLY_REFY = 63                   \ from the view's top edge, sprite top + 13

.CheckWalls
  CLC                           \ reference cell, from the SPRITE's own
  LDA plyX   : ADC #LO(PLY_REFX) : STA cwU    \ position now, not the view's
  LDA plyX+1 : ADC #HI(PLY_REFX) : STA cwU+1
  LDA cwU   : STA plyCX
  LDA cwU+1 : STA plyCX+1
  LSR plyCX+1 : ROR plyCX
  LSR plyCX+1 : ROR plyCX
  LSR plyCX+1 : ROR plyCX
  CLC
  LDA posY   : ADC #PLY_REFY : STA plyCY
  LDA posY+1 : ADC #0         : STA plyCY+1
  LSR plyCY+1 : ROR plyCY
  LSR plyCY+1 : ROR plyCY
  LSR plyCY+1 : ROR plyCY

  LDA xSpd+1
  BEQ cw_vert
  BMI cw_leftward
  LDX #9                        \ moving right: probes 9, A, B
  JSR ProbeGroup
  BCC cw_vert
  LDA cwU                       \ back to the near side of this cell
  AND #&F8
  CLC
  ADC #1
  STA cwU
  JSR CwUnRef
  JMP cw_xstop
.cw_leftward
  LDX #6                        \ moving left: probes 6, 7, 8
  JSR ProbeGroup
  BCC cw_vert
  LDA cwU                       \ to the far side of this cell
  ORA #7
  STA cwU
  JSR CwUnRef
.cw_xstop
  LDA #0
  STA plyXf                     \ the snap lands on a whole pixel
  STA xSpd
  STA xSpd+1

.cw_vert
  LDA ySpd+1
  BEQ cw_x
  BMI cw_upward
  LDX #3                        \ moving down: probes 3, 4, 5
  JSR ProbeGroup
  BCC cw_x
  LDA posY
  AND #&F8
  CLC
  ADC #1
  STA posY
  JMP cw_ystop
.cw_upward
  LDX #0                        \ moving up: probes 0, 1, 2
  JSR ProbeGroup
  BCC cw_x
  CLC
  LDA posY : ADC #7 : STA posY
  BCC cw_unc
  INC posY+1
.cw_unc
  LDA posY
  AND #&F8
  STA posY
.cw_ystop
  LDA #0
  STA posYf
  STA ySpd
  STA ySpd+1
.cw_x
  RTS

\ ============================================================
\ ProbeGroup — are any of the 3 probe cells from X solid?
\ Carry set = blocked.
\ ============================================================
\ cellX stays 8-bit: the map is 256 characters wide, so cellX+1 is
\ always 0 and a probe that runs off an edge simply wraps. The view
\ is clamped well inside the map, so that never happens where it
\ could matter.
.ProbeGroup
  LDA #3
  STA pgCount
.pg_loop
  CLC
  LDA plyCX : ADC nearXoffset,X : STA cellX
  LDA #0    : STA cellX+1
  CLC
  LDA plyCY : ADC nearYoffset,X : STA cellY
  JSR MapChar
  BMI pg_wall
  INX
  DEC pgCount
  BNE pg_loop
  CLC
  RTS
.pg_wall
  SEC
  RTS

\ The probe offsets, straight from $6B52 / $6B5E.
.nearXoffset
  EQUB &FF, 1, 0, 0, &FF, 1, &FE, &FF, &FE, 2, 1, 2
.nearYoffset
  EQUB &FE, &FE, &FF, 1, 2, 2, &FF, 0, 1, &FF, 0, 1

\ The snap works on cwU = plyX + PLY_REFX, the same quantity the
\ reference cell is derived from, and the rule it must obey is that
\ SNAPPING MUST NOT MOVE THE CELL. Move it and the wall drops out of
\ the probes, the player drifts back into it, and it sits against the
\ wall jittering a pixel — which is exactly what happened the first
\ time, before the reference offset was fixed.
\
\ So both snaps stay inside the current cell and only strip the
\ sub-cell remainder, in whichever direction backs away from the
\ wall:
\
\   blocked going right   cwU = (cwU AND &F8) + 1   near side
\   blocked going left    cwU = cwU OR 7            far side
\
\ Both are idempotent, so holding against a wall is stable.
\
\ The C64 writes these as (X AND $F8)+1 and (X+7) AND $F8 on
\ ScreenPosX rather than on the reference quantity. That works there
\ only because its offset is 159 and 159 MOD 8 = 7, which makes the
\ two formulations coincide. Ours is 11, and rounding UP moves the
\ cell — the vertical snap below still uses the C64's form because
\ PLY_REFY is 63 and the coincidence holds.
.CwUnRef
  SEC
  LDA cwU   : SBC #LO(PLY_REFX) : STA plyX
  LDA cwU+1 : SBC #HI(PLY_REFX) : STA plyX+1
  RTS

.cwU       EQUW 0
.plyCX     EQUW 0
.plyCY     EQUW 0
.pgCount   EQUB 0

\ ============================================================
\ ApplyMove — integrate the speeds, work out what got exposed
\ ============================================================
\ Records the exposed edges for DoRedraws rather than drawing them,
\ so that SetCRTCStart can park the CRTC address first.
.ApplyMove
  LDA mapHX   : STA oldHX       \ what the frame is moving from
  LDA mapHX+1 : STA oldHX+1
  LDA mapYr   : STA oldMapYr
  LDA posY    : STA oldPosY
  LDA posY+1  : STA oldPosY+1

\ The position carries a fraction byte, so it is 16.8 and the speed
\ adds into it whole. The C64 only ever adds the whole-pixel part of
\ the speed and drops the fraction each frame, which it can afford
\ because its top speed is a whole number of pixels per iteration.
\ Ours is 3.5 per frame: truncating would move 3 and throw the half
\ away every single frame, 14% short. It also makes the first few
\ frames of acceleration move nothing at all, which reads as a sticky
\ start rather than a smooth one.
\
\ A 24-bit add of a sign-extended 16-bit value, so it works
\ unchanged for both directions.
  LDA xSpd+1
  JSR SignByte                  \ -> mvSign, &00 or &FF
  CLC
  LDA plyXf  : ADC xSpd   : STA plyXf
  LDA plyX   : ADC xSpd+1 : STA plyX
  LDA plyX+1 : ADC mvSign : STA plyX+1
  JSR ClampPlyX
  JSR DeadZone                  \ -> posX, and slot 0's unit / shift

  LDA ySpd+1
  JSR SignByte
  CLC
  LDA posYf  : ADC ySpd   : STA posYf
  LDA posY   : ADC ySpd+1 : STA posY
  LDA posY+1 : ADC mvSign : STA posY+1
  JSR ClampY

  LDA posX+1                    \ mapHX = posX >> 2; posX is always a
  LSR A                         \ multiple of 4, so nothing is lost
  STA mapHX+1
  LDA posX
  ROR A
  LSR mapHX+1
  ROR A
  STA mapHX

  LDA posY+1                    \ mapYr = posY >> 3, line = posY AND 7
  STA amTmp+1
  LDA posY
  STA amTmp
  LSR amTmp+1 : ROR amTmp
  LSR amTmp+1 : ROR amTmp
  LSR amTmp+1 : ROR amTmp
  LDA amTmp
  STA mapYr
  LDA posY
  AND #7
  STA line

\ scrollS moves by whole units horizontally and whole rows
\ vertically; the sub-row remainder is `line`, which the CRTC
\ applies with R5 and which costs nothing here.
  SEC                           \ dUnits = mapHX - oldHX
  LDA mapHX : SBC oldHX
  STA sDelta
  LDA mapHX+1 : SBC oldHX+1
  STA sDelta+1
  ASL sDelta : ROL sDelta+1     \ * UNIT_BYTES
  ASL sDelta : ROL sDelta+1
  ASL sDelta : ROL sDelta+1

\ dRows is also what says whether a character row has to be drawn, so
\ the band is recorded here rather than from the pixel delta. Crossing
\ a row boundary is the ONLY thing that exposes new vertical content:
\ within a row the strip already holds all 8 scanlines, drawn when the
\ row was brought in.
  LDA #0
  STA bandDo
  SEC                           \ dRows = mapYr - oldMapYr, in [-1, 1]
  LDA mapYr
  SBC oldMapYr
  BEQ am_norow
  BMI am_rowup
  CLC
  LDA sDelta   : ADC #LO(ROW_BYTES) : STA sDelta
  LDA sDelta+1 : ADC #HI(ROW_BYTES) : STA sDelta+1

  CLC                           \ down: the new bottom row, mapYr+15, into
  LDA mapYr : ADC #PLAY_ROWS-1  \ display row 15 — the one map row mapYr-1
  STA bandRow                   \ has just vacated
  LDA #PLAY_ROWS-1
  STA bandRc
  JMP am_haverow
.am_rowup
  SEC
  LDA sDelta   : SBC #LO(ROW_BYTES) : STA sDelta
  LDA sDelta+1 : SBC #HI(ROW_BYTES) : STA sDelta+1

  LDA mapYr                     \ up: the new top row, into display row 0
  STA bandRow
  LDA #0
  STA bandRc
.am_haverow
  LDA #1
  STA bandDo
.am_norow
  JSR ScrollAddS

\ ---- what became visible ------------------------------------
\ Horizontally, dUnits columns at whichever edge is leading.
  SEC
  LDA mapHX : SBC oldHX
  STA amDU                      \ -2..2; the high byte cannot differ by
  BEQ am_nocols                 \ more than this at 7 px a frame
  BMI am_left
  STA colCount
  LDA #PLAY_UNITS
  SEC
  SBC colCount
  STA colFirst                  \ the rightmost dUnits columns
  JMP am_nocols
.am_left
  EOR #&FF
  CLC
  ADC #1
  STA colCount
  LDA #0
  STA colFirst                  \ the leftmost |dUnits| columns
.am_nocols
  RTS

\ ============================================================
\ DeadZone — the view follows the player, but only when pushed
\ ============================================================
\ The C64 pins the player dead centre because its hardware scroll is
\ 1 pixel. Ours is 4 — the CRTC addresses in 8-byte units, 80 to a
\ row, so a step is 1/80 of the screen width in every mode — and at
\ low speed a rigid camera makes the whole world lurch 4 pixels
\ every few frames.
\
\ So the player moves through the world at 1 pixel and the view only
\ follows once the player leaves a window either side of the centre.
\ Walking slowly, the world holds perfectly still and only the droid
\ moves; at speed the window saturates and the view scrolls as
\ before. The cost is that the player is no longer pinned centre and
\ that reversing direction crosses the window before the world
\ reacts — about 5 frames at top speed.
\
\ posX stays a multiple of 4 so that mapHX = posX >> 2 loses
\ nothing, and the leftover 0-3 pixels are carried by the sprite:
\ plyShift picks the 2-pixel-shifted copy, plyUnit the CRTC column.
.DeadZone
  SEC                           \ sx = where the sprite sits on screen
  LDA plyX   : SBC posX   : STA dzSx
  LDA plyX+1 : SBC posX+1 : STA dzSx+1

  LDA dzSx+1
  BNE dz_right                  \ past 255: certainly right of the window
  LDA dzSx
  CMP #PLY_DZ_MAX+1
  BCS dz_right
  CMP #PLY_DZ_MIN
  BCC dz_left
  JMP dz_screen                 \ inside: the view holds still

.dz_right
  SEC                           \ how far out, rounded up to whole units
  LDA dzSx   : SBC #PLY_DZ_MAX : STA dzD
  LDA dzSx+1 : SBC #0          : STA dzD+1
  JSR DzRoundUnits
  CLC
  LDA posX   : ADC dzD   : STA posX
  LDA posX+1 : ADC dzD+1 : STA posX+1
  JMP dz_clamp
.dz_left
  SEC
  LDA #PLY_DZ_MIN : SBC dzSx   : STA dzD
  LDA #0          : SBC dzSx+1 : STA dzD+1
  JSR DzRoundUnits
  SEC
  LDA posX   : SBC dzD   : STA posX
  LDA posX+1 : SBC dzD+1 : STA posX+1

\ Both limits are multiples of 4, so clamping cannot knock posX off
\ the unit grid.
.dz_clamp
  LDA posX+1
  BMI dz_low
  CMP #HI(MAX_PX_X)
  BCC dz_screen
  BNE dz_high
  LDA posX
  CMP #LO(MAX_PX_X)
  BCC dz_screen
  BEQ dz_screen
.dz_high
  LDA #LO(MAX_PX_X) : STA posX
  LDA #HI(MAX_PX_X) : STA posX+1
  JMP dz_screen
.dz_low
  LDA #0
  STA posX
  STA posX+1

\ Where the sprite lands, now that the view has settled. sx reaches
\ 296 at the right-hand edge of the map, so the halving is 16-bit;
\ after it, everything fits in a byte.
.dz_screen
  SEC
  LDA plyX   : SBC posX   : STA dzSx
  LDA plyX+1 : SBC posX+1 : STA dzSx+1
  LDA dzSx+1
  LSR A
  LDA dzSx
  ROR A                         \ sx >> 1, 0-148
  STA amTmp
  AND #1
  STA sprShift+PLY_SLOT         \ odd half-pixel pair: use the shifted copy
  LDA amTmp
  LSR A
  STA sprUnit+PLY_SLOT
  RTS

\ dzD rounded up to a whole number of 4-pixel units.
.DzRoundUnits
  CLC
  LDA dzD : ADC #3 : STA dzD
  BCC dzr_1
  INC dzD+1
.dzr_1
  LDA dzD
  AND #&FC
  STA dzD
  RTS

\ ============================================================
\ SignByte — mvSign = &FF if A is negative, else &00
\ ============================================================
.SignByte
  LDX #0
  CMP #&80
  BCC sb_x
  LDX #&FF
.sb_x
  STX mvSign
  RTS

\ ============================================================
\ ClampX / ClampY — hold the view inside the map, and stop dead
\ ============================================================
\ Running into the edge of the map kills the speed rather than
\ leaving it wound up, so turning round is immediate instead of
\ waiting for a phantom 7 px/frame to decelerate.
.ClampPlyX
  LDA plyX+1
  BMI cx_low                    \ went below zero
  CMP #HI(MAX_PLY_X)
  BCC cx_x
  BNE cx_high
  LDA plyX
  CMP #LO(MAX_PLY_X)
  BCC cx_x
  BEQ cx_x
.cx_high
  LDA #LO(MAX_PLY_X) : STA plyX
  LDA #HI(MAX_PLY_X) : STA plyX+1
  JMP cx_stop
.cx_low
  LDA #0
  STA plyX
  STA plyX+1
.cx_stop
  LDA #0
  STA plyXf                     \ snapping or stopping lands on a whole
  STA xSpd                      \ pixel; a stale fraction would drift
  STA xSpd+1
.cx_x
  RTS

.ClampY
  LDA posY+1
  BMI cy_low
  CMP #HI(MAX_PX_Y)
  BCC cy_x
  BNE cy_high
  LDA posY
  CMP #LO(MAX_PX_Y)
  BCC cy_x
  BEQ cy_x
.cy_high
  LDA #LO(MAX_PX_Y) : STA posY
  LDA #HI(MAX_PX_Y) : STA posY+1
  JMP cy_stop
.cy_low
  LDA #0
  STA posY
  STA posY+1
.cy_stop
  LDA #0
  STA posYf
  STA ySpd
  STA ySpd+1
.cy_x
  RTS

\ ============================================================
\ SetPosFromMap — posX/posY from mapHX/mapYr after CentreOnDeck
\ ============================================================
\ CentreOnDeck frames a deck in character units; the pixel position
\ is the authority from then on, so it has to be seeded from it.
.SetPosFromMap
  LDA mapHX   : STA posX        \ posX = mapHX * 4
  LDA mapHX+1 : STA posX+1
  ASL posX : ROL posX+1
  ASL posX : ROL posX+1
  LDA mapYr                     \ posY = mapYr * 8
  STA posY
  LDA #0
  STA posY+1
  ASL posY : ROL posY+1
  ASL posY : ROL posY+1
  ASL posY : ROL posY+1
  CLC                           \ the player starts at the home position
  LDA posX   : ADC #LO(PLY_HOME_X) : STA plyX
  LDA posX+1 : ADC #HI(PLY_HOME_X) : STA plyX+1
  LDA #0
  STA xSpd : STA xSpd+1
  STA ySpd : STA ySpd+1
  STA posXf : STA posYf : STA plyXf
  STA line
  STA bandDo
  STA colCount
  RTS

.plyX      EQUW 0               \ the player itself, map pixels — the
.plyXf     EQUB 0               \ authority horizontally; posX follows
.dzSx      EQUW 0
.dzD       EQUW 0
.posX      EQUW 0               \ view origin, map pixels
.posY      EQUW 0
.xSpd      EQUW 0               \ 8.8 signed, px per frame
.ySpd      EQUW 0
.joyXDir   EQUB 0
.joyYDir   EQUB 0
.oldHX     EQUW 0
.oldPosY   EQUW 0
.oldMapYr  EQUB 0
.mvSign    EQUB 0
.posXf     EQUB 0               \ sub-pixel fraction of the position
.posYf     EQUB 0
.spd       EQUW 0               \ CalcAxis works on this pair
.axDir     EQUB 0
.amTmp     EQUW 0
.amDU      EQUB 0
