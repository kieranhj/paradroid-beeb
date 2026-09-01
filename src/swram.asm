\ ============================================================
\ PARSWR — sideways RAM detection, the pre-load step
\ ============================================================
\ Runs from !BOOT, BEFORE *RUN PARA, and hands the game the four bank
\ numbers it should use. Everything here is dead by the time the game
\ starts: it detects, it reports, it writes five bytes and it returns to
\ BASIC, which reads the next !BOOT line.
\
\ THE METHOD IS stnicc-beeb's (src/loader.bas in the Bitshifters repo),
\ transliterated. Its three stages exist to survive two things a naive
\ write-and-read-back probe gets wrong:
\
\   BANK ALIASING. A board that decodes three select bits puts the same
\   16K at banks N and N+8. Write one probe value to every bank and read
\   it back and both copies answer correctly, so a 2-bank board reports
\   4. Sixteen DISTINCT probe values, one per bank, catch it: the alias
\   holds whichever was written last, so only one of the pair matches.
\
\   WRITE-ENABLE LATCHES. A Solidisk board needs the bank index in the
\   User VIA port B and &FE32 as well as in ROMSEL before a write lands.
\   Probe without them and its RAM reads back as ROM.
\
\ WHAT THIS ADDS TO IT, and why:
\
\   1. IT ONLY PROBES BANKS THE MOS FOUND NO ROM IN. The ROM type table
\      at &02A1 has a non-zero byte for every bank that answered the
\      boot-time ROM scan, which is every real ROM and every ROM IMAGE
\      someone has loaded into their sideways RAM. Probing writes a byte
\      into &8008; doing that to a live filing system or utility ROM is
\      how you hang a machine that was working. Skipping them also means
\      we never CHOOSE one and blow it away at BootBanks, which matters
\      more — a DFS in sideways RAM would take the next *LOAD with it.
\
\   2. IT SAVES THE RIGHT BYTE. stnicc's stage 1 reads its original at
\      &8008 with the bank from the END of the inner loop selected, so it
\      saves bank 0's byte sixteen times and stage 3 restores bank 0's
\      byte into every RAM bank. Inert there (it fills all its RAM
\      immediately) and inert here for the four banks we take, but not
\      for a spare one we probe and hand back. `STY ROMSEL` before the
\      read is the fix.
\
\ SOLIDISK IS DETECTED AND REFUSED, not supported (KC, 2026-08-29): the
\ game's own writes into sideways RAM — UnpackBankIn at boot, SaveDfsWs
\ at the game-over seam — go through ROMSEL alone, so a board that needs
\ the latches would pass detection and then fail to hold the game. The
\ second probe runs ONLY when the first has already failed to find four
\ banks, so an ordinary machine never touches the User VIA at all.
\
\ THE ADDRESS IS &1900, NOT &1100. !BOOT is an open *EXEC file and DFS
\ keeps its buffer in the random-access space at &1100 — the space the
\ game itself later loads into, which is safe for PARA precisely because
\ PARA is the last thing the exec file ever asks for. This runs while
\ that file still has lines left to give, so it stays out. &1900 is
\ BASIC's program area, empty, and untouched by the dispatch of a `*`
\ command from EXEC.
\ ============================================================

OSASCI    = &FFE3               \ OSWRCH, but 13 comes out as CR AND LF —
                                \ without it the BASIC prompt lands back on
                                \ top of the report
TSTADDR   = &8008               \ probed byte: past a ROM header's vectors
ROMTYPE   = &02A1               \ MOS ROM type table, one byte per bank
RAMSEL    = &FE32               \ Solidisk write-select
USR_ORB   = &FE60               \ Solidisk bank index
USR_DDRB  = &FE62

swValues  = &70                 \ 16: each bank's original byte
swUnique  = &80                 \ 16: each bank's probe value
swStr     = &70                 \ the message pointer, OVER swValues: the
                                \ probe is finished and its two arrays are
                                \ dead before a word is printed
                                \ &70-&8F is the user zero page; BASIC,
                                \ which we return to, does not use it

CLEAR SWR_ADDR, SWR_ADDR + &400
ORG SWR_ADDR
.swr_start

.SwrMain
  SEI                           \ the MOS's IRQ path pages ROMs in for
                                \ service calls; nothing may select a
                                \ bank behind us. Held to the restore.
  LDA #0
  STA swSolid
  JSR SwrProbe

  LDA swCount
  CMP #4
  BCS swr_found

\ ---- not four: is it a board we deliberately do not drive? ----
  LDA #&FF                      \ the Solidisk pass. Only ever reached
  STA swSolid                   \ here, so an ordinary machine's User VIA
  LDA #&0F                      \ is never written at all
  STA USR_DDRB
  JSR SwrProbe
  LDA #0
  STA USR_DDRB

  JSR SwrRestore
  LDA swCount
  CMP #4
  BCC swr_short                 \ genuinely short, either way

  LDX #LO(swMsgSolid)
  LDY #HI(swMsgSolid)
  JSR SwrPrint
  JMP SwrAbort

.swr_short
  LDX #LO(swMsgShort)
  LDY #HI(swMsgShort)
  JSR SwrPrint
  LDA swCount
  JSR SwrDigit
  LDA #13
  JSR OSASCI
  JMP SwrAbort

\ ---- four or more: hand the top four to the game ------------
\ swBanks is highest first, so this fills the handover lowest first and
\ the game's DATA/SPR/SPR2/XFER come out ascending — 4,5,6,7 on a
\ machine that has them, which is what every measurement in docs/ was
\ taken on.
.swr_found
  JSR SwrRestore
  LDX #3
  LDY #0
.swr_hand
  LDA swBanks,X
  STA SWR_HAND+1,Y
  INY
  DEX
  BPL swr_hand
  LDA #SWR_MAGIC
  STA SWR_HAND

  LDX #LO(swMsgOK)
  LDY #HI(swMsgOK)
  JSR SwrPrint
  LDY #0
.swr_show
  LDA SWR_HAND+1,Y
  JSR SwrDigit
  LDA #' '
  JSR OSASCI
  INY
  CPY #4
  BNE swr_show
  LDA #13
  JSR OSASCI
  RTS

\ ---- the failure exit --------------------------------------
\ Close the exec file and the *RUN PARA line below us is never read, so
\ the RTS lands on the BASIC prompt with the message still on screen.
.SwrAbort
  LDX #LO(swCmdExec)
  LDY #HI(swCmdExec)
  JMP OSCLI

\ ---- put the machine back ----------------------------------
.SwrRestore
  LDA ROMSHAD                   \ the MOS's own idea of what is paged;
  STA ROMSEL                    \ we have been bashing ROMSEL alone
  CLI
  RTS

\ ============================================================
\ SwrProbe — the three stages. swCount, swBanks (highest first)
\ ============================================================
.SwrProbe

\ ---- stage 0: candidates are the banks with no ROM in them ----
  LDX #15
.sp_cand
  LDA ROMTYPE,X
  STA swCand,X                  \ zero = ours to probe
  LDA #0
  STA swUnique,X                \ so stage 1's "distinct from every
  DEX                           \ unique already chosen" test starts from
  BPL sp_cand                   \ known values rather than BASIC's litter

\ ---- stage 1: a distinct probe value per bank, originals saved ----
\ Distinct from what every candidate bank holds AND from every value
\ already chosen. One running counter across all the banks, so the
\ search cannot cycle: at most 32 values are excluded out of 256.
  LDA #15
  STA swProbe
  LDY #15
.sp_nb
  LDA swCand,Y
  BNE sp_nb_next
.sp_nv
  INC swProbe
  LDX #15
.sp_ns
  LDA swCand,X
  BNE sp_ns_next
  STX ROMSEL
  LDA swProbe
  CMP TSTADDR
  BEQ sp_nv
  CMP swUnique,X
  BEQ sp_nv
.sp_ns_next
  DEX
  BPL sp_ns
  LDA swProbe
  STA swUnique,Y
  STY ROMSEL                    \ BANK Y, not whatever the loop left —
  LDA TSTADDR                   \ see the header: this is stnicc's bug
  STA swValues,Y
.sp_nb_next
  DEY
  BPL sp_nb

\ ---- stage 2: write every probe, COUNTING UP ----------------
\ Up rather than down because a Solidisk board indexes with three bits:
\ walking down, bank 15's write would land in bank 7 and be overwritten
\ by bank 7's own before anything is read back.
  LDX #0
.sp_sw
  LDA swCand,X
  BNE sp_sw_next
  JSR SwrSelW
  LDA swUnique,X
  STA TSTADDR
.sp_sw_next
  INX
  CPX #16
  BNE sp_sw

\ ---- stage 3: read back top down, restore, and record -------
\ Top down so the list comes out highest first, which is the order the
\ four are taken in; and so that a bank whose value has changed to
\ something that is not its own is simply not counted here — if it is an
\ alias of a lower bank, that lower bank still answers for itself.
  LDA #0
  STA swCount
  LDX #15
.sp_tr
  LDA swCand,X
  BNE sp_tr_next
  STX ROMSEL
  LDA TSTADDR
  CMP swUnique,X
  BNE sp_tr_next
  LDY swCount
  CPY #16
  BEQ sp_tr_next                \ cannot happen; the array is 16 long
  TXA
  STA swBanks,Y
  INC swCount
  JSR SwrSelW
  LDA swValues,X
  STA TSTADDR
.sp_tr_next
  DEX
  BPL sp_tr
  RTS

\ ---- select bank X for WRITING ------------------------------
\ ROMSEL always, because the read-back needs it too. The two latches
\ only on the Solidisk pass — see the header.
.SwrSelW
  STX ROMSEL
  BIT swSolid
  BPL ssw_x
  STX USR_ORB
  STX RAMSEL
.ssw_x
  RTS

\ ---- one hex digit of A, and a string at X/Y ----------------
.SwrDigit
  CMP #10
  BCC swd_num
  ADC #6                        \ carry set: +7 total, '9'+1 to 'A'
.swd_num
  ADC #'0'
  JMP OSASCI

.SwrPrint
  STX swStr
  STY swStr+1
  LDY #0
.swp_l
  LDA (swStr),Y
  BEQ swp_x
  JSR OSASCI
  INY
  BNE swp_l
.swp_x
  RTS

.swMsgOK
  EQUS "Detected SWRAM slots: ", 0
.swMsgShort
  EQUS 13, "PARADROID NEEDS 4 x 16K SIDEWAYS RAM", 13, "BANKS - FOUND ", 0
.swMsgSolid
  EQUS 13, "SIDEWAYS RAM FOUND, BUT ON A BOARD WITH", 13
  EQUS "SOLIDISK-STYLE WRITE SELECT, WHICH THIS", 13
  EQUS "GAME DOES NOT DRIVE.", 13, 0
.swCmdExec
  EQUS "EXEC", 13

.swProbe  EQUB 0
.swSolid  EQUB 0                \ &FF on the Solidisk pass
.swCount  EQUB 0
.swCand   SKIP 16               \ ROM type per bank; zero = probe it
.swBanks  SKIP 16               \ the RAM banks found, highest first

.swr_end
ASSERT swr_end <= SWR_ADDR + &400
PRINT "PARSWR  ", ~swr_start, "-", ~swr_end
SAVE "PARSWR", swr_start, swr_end, swr_start
