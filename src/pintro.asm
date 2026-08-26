\ ============================================================
\ pintro.asm — PINTRO, the loading-intro executable
\ ============================================================
\ A SEPARATE BUILD, not part of main.asm's: build.ps1 -Intro assembles
\ this file in a second beebasm pass and make_disc.py lays PINTRO at
\ the front of the disc with "*RUN PINTRO" patched into !BOOT ahead of
\ "*RUN PARA". Default builds contain no trace of it. Plan and the
\ colour-model decisions: docs/intro.md. The C64 original it
\ reproduces: docs/graphics.md §10 and tools/rip_intro.py.
\
\ WHAT IT DOES: MODE 1, palette all black, depack the converted intro
\ picture (src/data/introscr.zx0, from tools/export_intro.py) onto the
\ screen, then loop at one iteration per frame:
\
\   vsync  ->  write the PICTURE palette (16 ULA bytes, the flash
\              lives in its logical-0/1/2 entries)
\   busy-wait to the split row  ->  write the CREDITS palette
\   IntroFxTick  ->  advance the lightning
\   any keypress  ->  MODE 7, flush, RTS — !BOOT's EXEC carries on
\              into the game load
\
\ The whole effect is palette animation: the screen is never written
\ again after the depack. IntroFxTick and the split write are the two
\ bounded, OS-free calls that move onto scarybeasts' MOD player
\ schedule when it arrives (docs/intro.md §6); OSBYTE 19 and the
\ busy-wait are v1's stand-in timekeeping.
\
\ THE FLASH, transliterated from the C64 loop at $E000: idle until a
\ trigger (checked every 32nd frame, gated on free-running timer
\ entropy — the C64 gates on a CIA timer the same way), then 15 frames
\ stepping through one of four colourway blocks along the envelope
\ attack 4 / hold 2 / decay 9. The colourway tables arrive from the
\ exporter pre-mapped to ULA register form; this code does no colour
\ arithmetic at all.
\
\ RAM: the file sits at &1900 (plain DFS PAGE — none of the game's
\ low-RAM tricks belong here), GUARDed against &3000. Zero page is
\ BASIC's user range &70-&8F, dead on exit. Nothing survives into the
\ game load.

CPU 0

OSWRCH = &FFEE
OSBYTE = &FFF4
VIDEO_ULA_PAL = &FE21
SYSVIA_T1CL = &FE44             \ free-running timer low byte: entropy

\ ---- zero page (&70-&8F, BASIC's user range) ----------------
\ The first six names are what zx0depack.asm's aliases resolve to —
\ it borrows the game's level-draw scratch names, so this file
\ provides them; only the layout below matters.
src        = &70                \ depacker: the compressed stream (2)
mapptr     = &72                \ depacker: the output pointer (2)
sDelta     = &74                \ depacker zxofs (2)
subRowOfs  = &76                \ depacker zxlen (2, with tileCol)
tileCol    = &77
colTileCol = &78                \ depacker zxbit
rptTile    = &79                \ depacker zxwrk (2, with rptLen)
rptLen     = &7A

fxFrame    = &7B                \ free-running frame counter
fxIdx      = &7C                \ envelope frames left, 0 = idle
fxWay      = &7D                \ current colourway table offset
fxTmp      = &7E
fxSeed     = &7F                \ the PRNG state, stepped every frame

\ ---- tuning ----------------------------------------------------
\ Trigger probability per 64-frame check: &A0/256 = 62.5%, one flash
\ every ~2.3 s on average with starts never closer than 1.28 s. The
\ check GRID matters as much as the probability: on a 32-frame grid
\ (measured with a trigger log in jsbeeb) the geometric distribution
\ chains minimum-spacing flashes — 15 frames lit, 17 dark, four in a
\ row — which reads as constant lightning even at a 2 s mean. The
\ 64-frame grid buys a guaranteed dark gap instead of a longer mean.
\ THE GATE BYTE IS AN LFSR, NOT A BARE &FE44 READ. The first builds
\ compared System VIA T1's low byte against this threshold, and that
\ is not random from a vsync-locked loop: T1 runs the 100 Hz tick, so
\ its 20,000-cycle period divides the 40,000-cycle frame EXACTLY and
\ the same T1 phase comes round at the same spot every frame. The
\ sampled byte only drifted with interrupt jitter — whenever it
\ drifted below the threshold the gate passed EVERY 32-frame check
\ (KC: "almost constant"), then nothing through the droughts, and the
\ threshold barely mattered. The Galois LFSR in IntroFxTick steps
\ once per frame, is seeded and unsticks from the timer, and makes
\ the probability real.
TRIG_PROB   = &A0

\ The two per-frame busy-waits, CALIBRATED IN JSBEEB, not computed.
\ One outer loop pass is 1287 cycles; a display line is 128.
\
\ WHY THE PICTURE PALETTE IS NOT WRITTEN AT VSYNC: everything outside
\ the drawn image is logical 0, and the picture palette's logical 0
\ carries the D021 flash — written at vsync it painted the THREE
\ BLANK ROWS above the picture red at every flash peak (seen in
\ jsbeeb, first build). The C64 never shows this because its blank
\ areas are colour-RAM-black PIXELS, immune to D021; ours are
\ background. So the picture write waits for the raster to reach the
\ picture's top row — the blank rows keep the previous split write's
\ credits palette, whose logical 0 is always black.
\
\ WAIT A: vsync to inside the three blank rows' display lines 0-23
\   (a ~3 ms window; aim mid-window). Too early = red band above the
\   sky at flash peak; too late = the sky's first lines go credits-
\   green. Both checked by screenshot at a forced peak (poke fxIdx).
\ WAIT B: on to the all-black C64 row 16 at display lines 152-159,
\   aimed EARLY in the row: firing late leaves those lines on the
\   picture palette, a red sliver at flash peak. (1-2 lines of that
\   at worst survive OS interrupt jitter; docs/intro.md §3 accepts
\   it.) Too early = the floor's last lines take credits colours.
\ Each wait is OUTER passes of 1287 cycles plus FINE passes of 5 —
\ the fine term steers by single scanlines (26 ≈ one line).
SPLITA_OUTER = 4
SPLITA_FINE  = 88
SPLITB_OUTER = 12
SPLITB_FINE  = 170

ORG &1900
GUARD &3000

.start
    \ MODE 1, cursor off, palette all black — the depack happens on an
    \ invisible screen and the first frame's palette writes reveal it.
    LDX #0
.st_vdu
    LDA vduInit,X
    JSR OSWRCH
    INX
    CPX #vduInitEnd-vduInit
    BNE st_vdu
    LDX #15
.st_black
    TXA
    ASL A
    ASL A
    ASL A
    ASL A
    ORA #7                      \ (entry<<4) OR (0 EOR 7): physical black
    STA VIDEO_ULA_PAL
    DEX
    BPL st_black

    LDX #15                     \ the live palette starts at rest
.st_rest
    LDA palPicRest,X
    STA palPicBuf,X
    DEX
    BPL st_rest

    LDA #<stream                \ depack the picture onto the screen
    STA src
    LDA #>stream
    STA src+1
    LDA #0
    STA mapptr
    STA fxFrame
    STA fxIdx
    LDA #&30
    STA mapptr+1
    LDA SYSVIA_T1CL             \ per-boot PRNG seed: the timer varies
    ORA #1                      \ with load timing (0 is the LFSR's
    STA fxSeed                  \ fixed point, hence the ORA)
    JSR Zx0Unpack

\ ---- one iteration per frame --------------------------------
.frame
    LDA #19
    JSR OSBYTE                  \ wait for vsync

    LDY #SPLITA_OUTER           \ burn down to the blank rows above
.fa_wo                          \ the picture...
    LDX #0
.fa_wi
    DEX
    BNE fa_wi
    DEY
    BNE fa_wo
    LDX #SPLITA_FINE
.fa_fi
    DEX
    BNE fa_fi

    LDX #15                     \ ...then the picture palette, flash
.fr_pic                         \ included
    LDA palPicBuf,X
    STA VIDEO_ULA_PAL
    DEX
    BPL fr_pic

    LDY #SPLITB_OUTER           \ burn down to the split row
.fb_wo
    LDX #0
.fb_wi
    DEX
    BNE fb_wi
    DEY
    BNE fb_wo
    LDX #SPLITB_FINE
.fb_fi
    DEX
    BNE fb_fi

    LDX #15                     \ credits palette, constant
.fr_cred
    LDA palCred,X
    STA VIDEO_ULA_PAL
    DEX
    BPL fr_cred

    JSR IntroFxTick

    LDA #&7A                    \ SCAN the keyboard (X = internal key
    LDX #0                      \ number of any key held; no-key is 0
    LDY #0                      \ in NAUG's account and &FF on the
    JSR OSBYTE                  \ MOS measured in jsbeeb — treat both
    CPX #0                      \ as idle. NOT INKEY: at boot the OS
    BEQ frame                   \ is EXECing !BOOT, and INKEY reads
    CPX #&FF                    \ the EXEC stream — the first build
    BEQ frame                   \ ate the '*' of "*RUN PARA" and
                                \ exited with no key pressed at all.
.exit
    LDA #&7E                    \ if the key was ESCAPE the OS has set
    JSR OSBYTE                  \ the escape flag — acknowledge it or
                                \ it aborts the EXEC we return into
    LDA #15                     \ flush the input buffer so nothing
    LDX #1                      \ typed during the intro leaks onward
    JSR OSBYTE
    LDA #22
    JSR OSWRCH
    LDA #7                      \ MODE 7: leave the OS as we found it
    JSR OSWRCH
    RTS                         \ back to the CLI; !BOOT's EXEC resumes

\ ---- the lightning ------------------------------------------
\ Bounded, OS-free, ~150 cycles worst case. Updates palPicBuf only;
\ the buffer reaches the ULA at the next frame's vsync write.
.IntroFxTick
    INC fxFrame
    LDA fxSeed                  \ step the 8-bit Galois LFSR every
    LSR A                       \ frame — see the TRIG_PROB comment
    BCC fx_s1                   \ for why &FE44 alone is NOT random
    EOR #&B8
.fx_s1
    STA fxSeed
    BNE fx_s2
    LDA SYSVIA_T1CL             \ 0 is the fixed point: reseed
    ORA #1
    STA fxSeed
.fx_s2
    LDA fxIdx
    BNE fx_active
    LDA fxFrame                 \ idle: consider a trigger every
    AND #63                     \ 64th frame (the C64 checks every
    BNE fx_done                 \ 32nd; see the TRIG_PROB comment)
    LDA fxSeed
    EOR SYSVIA_T1CL             \ timer jitter folded on top
    CMP #TRIG_PROB
    BCS fx_done
    AND #3                      \ the same byte picks the colourway
    TAX
    LDA cwBase,X
    STA fxWay
    LDA #15
    STA fxIdx                   \ first step lands next frame
.fx_done
    RTS
.fx_active
    DEC fxIdx
    LDX fxIdx
    LDA envStep,X               \ envelope step 0-3 for this frame
    ASL A
    ASL A                       \ step*4
    STA fxTmp
    ASL A                       \ step*8
    ADC fxTmp                   \ step*12: 12 palette bytes per step
    ADC fxWay
    TAX
    LDY #0
.fx_copy
    LDA cwSteps,X
    STA palPicBuf,Y
    INX
    INY
    CPY #12                     \ logicals 0-2; entry 12 on, logical 3
    BNE fx_copy                 \ (the sky), never changes
.fx_done2
    RTS

\ ---- data ---------------------------------------------------
.vduInit
    EQUB 22, 1                              \ MODE 1
    EQUB 23, 1, 0, 0, 0, 0, 0, 0, 0, 0      \ cursor off
.vduInitEnd

\ The envelope, indexed by fxIdx AFTER its DEC (14 = first flash
\ frame): the C64's offset sequence 0,4,8,C,C,C,8,8,8,8,4,4,4,4,0
\ ($E204) as step numbers, in reverse.
.envStep
    EQUB 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 2, 1, 0

.cwBase
    EQUB 0, 48, 96, 144         \ colourway -> cwSteps offset

.palPicBuf                      \ the live picture palette — st_rest
    EQUB 0,0,0,0,0,0,0,0       \ copies palPicRest over it at startup,
    EQUB 0,0,0,0,0,0,0,0       \ and a flash step rewrites bytes 0-11

INCLUDE "src/data/introfx.asm"  \ palPicRest, palCred, cwSteps
INCLUDE "src/zx0depack.asm"     \ the ZX0_DEPACKER macro + .Zx0Unpack

.stream
INCBIN "src/data/introscr.zx0"
.stream_end
.pintro_end

SAVE "PINTRO", start, pintro_end, start
