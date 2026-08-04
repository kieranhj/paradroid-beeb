\ ============================================================
\ zeropage.asm — Zero page layout for Paradroid CE BBC port
\ ============================================================
\ Matching C64 layout where possible ($00–$CF).
\ BBC OS uses $00–$01 (NMI) and $FC (IRQ A save) — avoid these.
\ BBC-specific HAL variables use $D0–$EF.

\ ---- Sprite parameter passing (C64 $02–$0E) ----
ORG 0
SKIP 2                          \ $00–$01: avoid (OS NMI / tmp)
.byte_0_2     SKIP 1            \ $02: sprite bit mask
.byte_0_3     SKIP 1            \ $03: sprite bit mask inverse
.SpriteNum    SKIP 1            \ $04: current sprite slot (0–7)
.SpriteX      SKIP 2            \ $05–$06: sprite X (16-bit pixel pos)
.SpriteY      SKIP 1            \ $07: sprite Y pixel pos
.SpriteEna    SKIP 1            \ $08: sprite enable flag
.SpriteYExp   SKIP 1            \ $09: (C64 Y-expand; unused on BBC)
.SpritePri    SKIP 1            \ $0A: (C64 priority; unused on BBC)
.SpriteMC     SKIP 1            \ $0B: (C64 multicolour; unused on BBC)
.SpriteXExp   SKIP 1            \ $0C: (C64 X-expand; unused on BBC)
.SpriteColor  SKIP 1            \ $0D: sprite colour index (0–15)
.SpriteImage  SKIP 1            \ $0E: sprite image index

\ ---- General temporaries ----
.tmp1         SKIP 1            \ $0F
.currentIdx   SKIP 1            \ $10
.xfer_cpuSpriteX SKIP 1         \ $11
.ptr_12       SKIP 2            \ $12–$13: general pointer
.ptr_14       SKIP 2            \ $14–$15: general pointer

\ ---- Joystick/input ($16–$18) ----
.joyYDir      SKIP 1            \ $16: -1=up, 0=none, +1=down
.joyXDir      SKIP 1            \ $17: -1=left, 0=none, +1=right
.joyFire      SKIP 1            \ $18: non-zero = fire pressed

\ ---- Misc ($19–$2B) ----
.FKeys        SKIP 1            \ $19: function key state
.src          SKIP 2            \ $1A–$1B: source pointer
.dest         SKIP 2            \ $1C–$1D: dest pointer
.dest2        SKIP 2            \ $1E–$1F: dest2 pointer
.tmp2         SKIP 1            \ $20
.Score        SKIP 4            \ $21–$24: BCD score (4 digits)
.notInDeck    SKIP 1            \ $25: non-zero when between decks (lift)
.scoreAdd     SKIP 1            \ $26: points to add this frame
.scoreSub     SKIP 1            \ $27: points to subtract this frame
.xSpd         SKIP 2            \ $28–$29: player X speed (16-bit fp)
.ySpd         SKIP 2            \ $2A–$2B: player Y speed (16-bit fp)
.bgColor      SKIP 1            \ $2C: background colour (was Irq1bgColor)

\ ---- Scroll / level position ($2D–$34) ----
.ScreenPosX   SKIP 2            \ $2D–$2E: viewport X (pixels, 16-bit)
.ScreenPosY   SKIP 2            \ $2F–$30: viewport Y (pixels, 16-bit)
.byte_0_31    SKIP 1            \ $31: tile column in map (DrawScreen)
.byte_0_32    SKIP 1            \ $32: tile row in map (DrawScreen)
.deckNum      SKIP 1            \ $33: current deck number (0–based)
.DecelerationNeg SKIP 1         \ $34: deceleration value (negative)
.Acceleration SKIP 1            \ $35: acceleration value
.MaxSpd       SKIP 1            \ $36: max speed cap

\ ---- Mode / state ($37–$43) ----
.moveMode     SKIP 1            \ $3A: 0=walk, non-zero=console
.consoleState SKIP 1            \ $3C: console/transfer state
.droidEnergy  SKIP 1            \ $40 (mapped as AD $40 $03 in orig)
\ NOTE: droidEnergy is actually at $0340 in C64 (not ZP); accessed via ABS
\ ZP $40 is free on BBC — no direct mapping needed for droidEnergy

\ ---- Movement helpers ($41–$49) ----
.dPosX        SKIP 2            \ $41–$42
.dPosY        SKIP 2            \ $43–$44
.byte_0_45    SKIP 1            \ $45
.byte_0_46    SKIP 1            \ $46
.sndVolume    SKIP 1            \ $47: master volume (0–$0F)
.hScroll      SKIP 1            \ $48: fine H scroll (0–7 for C64 compat)
.vScroll      SKIP 1            \ $49: fine V scroll (0–7 for C64 compat)
.frameCount   SKIP 1            \ $4A: frame counter (incremented each frame)
.irqToggle    SKIP 1            \ $4B: toggled by VSYNC IRQ (game loop sync)
.plyMapPos    SKIP 2            \ $4C–$4D: player map position pointer
.charUnder    SKIP 1            \ $4E: tile char under player
.SprSprCollision SKIP 1         \ $4F: sprite-sprite collision bitmask

\ ---- Misc flags ($50–$77) ----
.blkWhte      SKIP 1            \ $50: black/white flag
.plyFireSpdX  SKIP 1            \ $51: player fire bolt X speed
.plyFireSpdY  SKIP 1            \ $52: player fire bolt Y speed
.byte_0_53    SKIP 1            \ $53
.weaponType   SKIP 1            \ $54: weapon type
.byte_0_55    SKIP 1            \ $55: temp frameCount save
.rptChar      SKIP 1            \ $56: RLE repeat char (DrawPacked)
.rptLen       SKIP 1            \ $57: RLE repeat length
.dType        SKIP 1            \ $58: droid type temp
.numDeckDroids SKIP 1           \ $59: droids on current deck
.bgColorAlt   SKIP 1            \ $5A: alternate background colour
.dInfoPage    SKIP 1            \ $5B: droid info page
.droidInfoData SKIP 2           \ $5C–$5D
.deltaX       SKIP 2            \ $5E–$5F: line-of-sight delta X
.deltaY       SKIP 2            \ $60–$61: line-of-sight delta Y
.liftPos      SKIP 1            \ $62: lift position
.liftNum      SKIP 1            \ $63: lift number
.Alert        SKIP 1            \ $64: alert level
.prevDeck     SKIP 1            \ $65: previous deck number
.maxEnergy    SKIP 1            \ $66: max energy value
.shipLevel    SKIP 1            \ $67: ship/level number
.shipNumDroids SKIP 1           \ $68: total droids on ship
.collision1mode SKIP 1          \ $69: collision mode 1
.collision2mode SKIP 1          \ $6A: collision mode 2
.xferDroid    SKIP 1            \ $6B: transfer minigame: target droid
.byte_0_6C    SKIP 1            \ $6C
.DroidSpdNeg  SKIP 1            \ $6D: droid speed (negative)
SKIP 1                          \ $6E: DroidSpd0 (unused)
.DroidSpd     SKIP 1            \ $6F: droid speed
.DeltaX_t     SKIP 3            \ $70–$72: pathfind delta X table
.DeltaY_t     SKIP 3            \ $73–$75: pathfind delta Y table
.MapPos       SKIP 2            \ $76–$77: bullet map position

\ ---- Transfer sub-game ZP ($78–$8F) ----
.xfer_plySpriteX    SKIP 1      \ $78: player sprite X in transfer anim
.byte_0_79          SKIP 1      \ $79
.xfer_DeltaX        SKIP 2      \ $7A–$7B
.xfer_WinningSide   SKIP 1      \ $7C
.xfer_CpuPulserChar SKIP 1      \ $7D
.xfer_LeftColor     SKIP 1      \ $7E
.xfer_PlyColor      SKIP 1      \ $7F
.xfer_nLeftPulsers  SKIP 1      \ $80
.xfer_PlyY          SKIP 1      \ $81
.xfer_PlyPulserChar SKIP 1      \ $82
.xfer_CpuLevel      SKIP 1      \ $83
.xfer_nRightPulsers SKIP 1      \ $84
.xfer_CpuY          SKIP 1      \ $85
.xfer_CpuX          SKIP 1      \ $86
.xfer_CpuColor      SKIP 1      \ $87
.xfer_PlyLevel      SKIP 1      \ $88
.byte_0_89          SKIP 1      \ $89
.subGameTimeCount   SKIP 1      \ $8A
.xfer_WinningColor  SKIP 1      \ $8B
.xfer_PlyWireChar   SKIP 1      \ $8C
.xfer_CpuWireChar   SKIP 1      \ $8D
.xfer_PlyX          SKIP 1      \ $8E
.xfer_yWant         SKIP 1      \ $8F

\ ---- Sound variables ($90–$CF) ----
.sndState     SKIP 1            \ $90: sound FSM state
.sndFx1       SKIP 1            \ $91: queued SFX channel 1
.SndFx2       SKIP 1            \ $92: queued SFX channel 2
.moveModeDelay SKIP 1           \ $93
.disruptorCnt SKIP 1            \ $94
.disruptorBgSave SKIP 1         \ $95
.snd_96       SKIP 1            \ $96
.snd_varOffset SKIP 1           \ $97: sound table offset (voice × 7)
.snd_RegOffset SKIP 1           \ $98: SID register offset for voice
.snd_99_voicenum SKIP 1         \ $99: current voice number (0–1)
.snd_9A       SKIP 2            \ $9A–$9B
.snd_9C       SKIP 1            \ $9C: chatter timing counter
.sndActive1   SKIP 1            \ $9D: SFX active flag ch0 (maps SID $9D)
SKIP 2                          \ $9E–$9F: (pad to $A0)
\ Sound voice tables: 3 voices × 7 bytes = $A0–$B4
.snd_C0_fLo   SKIP 1            \ $A0: voice 0 freq lo (C64 $C0)
.snd_C1_fHi   SKIP 1            \ $A1
.snd_C2_fslideLo SKIP 1         \ $A2
.snd_C3_fslideHi SKIP 1         \ $A3
.snd_C4       SKIP 1            \ $A4
.snd_C5       SKIP 1            \ $A5
.snd_C6       SKIP 1            \ $A6: voice active flag
.snd_C7_pLo   SKIP 1            \ $A7: (pulse lo for SID compat)
.snd_C8_pHi   SKIP 1            \ $A8
.snd_C9_pslideLo SKIP 1         \ $A9
.snd_CA_pslideHi SKIP 1         \ $AA
SKIP 5                          \ $AB–$AF: voice 0 remainder
.snd_v1_fLo   SKIP 1            \ $B0: voice 1 freq lo
.snd_v1_fHi   SKIP 1            \ $B1
.snd_v1_fslideLo SKIP 1         \ $B2
.snd_v1_fslideHi SKIP 1         \ $B3
.snd_v1_active SKIP 1           \ $B4
.snd_v1_pLo   SKIP 1            \ $B5
.snd_v1_pHi   SKIP 1            \ $B6
SKIP 9                          \ $B7–$BF
.snd_v2_fLo   SKIP 1            \ $C0: voice 2 freq lo
.snd_v2_fHi   SKIP 1            \ $C1
.snd_v2_fslideLo SKIP 1         \ $C2
.snd_v2_fslideHi SKIP 1         \ $C3
.snd_v2_active SKIP 1           \ $C4
.snd_v2_pLo   SKIP 1            \ $C5
.snd_v2_pHi   SKIP 1            \ $C6
.snd_AD_duration SKIP 2         \ $C7–$C8: voice AD duration (2 voices)
.snd_fxDuration  SKIP 2         \ $C9–$CA: SFX duration table
.snd_d404     SKIP 2            \ $CB–$CC: voice waveform register cache
SKIP 3                          \ $CD–$CF: pad

\ ---- BBC Master HAL variables ($D0–$EF) ----
.bbcDisplayPage  SKIP 1         \ $D0: 0=main RAM displayed, 1=shadow displayed
.bbcAcccon       SKIP 1         \ $D1: shadow ACCCON value (R/W)
.bbcCrtcHi       SKIP 1         \ $D2: CRTC R12 (start addr high)
.bbcCrtcLo       SKIP 1         \ $D3: CRTC R13 (start addr low)
.bbcHudCrtcHi    SKIP 1         \ $D4: CRTC R12 for HUD start (fixed)
.bbcHudCrtcLo    SKIP 1         \ $D5: CRTC R13 for HUD start
.bbcTimer1Hi     SKIP 1         \ $D6: User VIA T1 latch high byte
.bbcTimer1Lo     SKIP 1         \ $D7: User VIA T1 latch low byte
.bbcSprSaveLo    SKIP 1         \ $D8: temp lo ptr for sprite bg save
.bbcSprSaveHi    SKIP 1         \ $D9: temp hi ptr for sprite bg save
.bbcScrLo        SKIP 1         \ $DA: temp lo ptr for screen access
.bbcScrHi        SKIP 1         \ $DB: temp hi ptr for screen access
.bbcVirtBufBank  SKIP 1         \ $DC: which virtual buffer is back
.bbcOldIrqLo     SKIP 1         \ $DD: saved old IRQ1V lo
.bbcOldIrqHi     SKIP 1         \ $DE: saved old IRQ1V hi
.snd_snFreqIdx   SKIP 3         \ $DF–$E1: SN76489 freq reg per channel (3)
.snd_snVol       SKIP 3         \ $E2–$E4: SN76489 volume per channel (3)
.snd_snNoise     SKIP 1         \ $E5: SN76489 noise register value
SKIP 10                         \ $E6–$EF: reserved for future HAL use

\ ---- Sprite runtime state area starts at $0200 ----
\ (Sprite bg saves, x/y tables etc. — see hal_sprite.asm)
