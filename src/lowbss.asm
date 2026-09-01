\ ============================================================
\ lowbss.asm — lowcode.asm's mutable state, at &0C90
\ ============================================================
\ &0C90-&0CFF is the tail of the reclaimed OS workspace the charset
\ already lives in: the BBC's font for ASCII 128-159, which nothing here
\ uses because nothing here goes through the OS to print. 112 bytes.
\
\ SEPARATE FROM lowcode.asm FOR ONE REASON: the PARALOW file has to fit
\ in &0E00-&10FF, and the state does not have to be in a file at all.
\ Everything below is written before it is read — AnimTick clears the
\ counters at the top of every pass and LoadDeck's AnimReset seeds
\ lampHave — so it is SKIPped rather than shipped.
\ WHICH MEANS THIS BLOCK IS OS LEFTOVERS UNTIL A GAME STARTS, and the
\ claim above is only true of code that runs inside one. ANYTHING THE
\ RUPTURE IRQ READS IS NOT, because the IRQ is live through the title,
\ the high-score entry and the briefing — a game away from GameStart's
\ resets. disrFlash was exactly that and gave KC a white briefing
\ scroller on cold boots (2026-08-28); ts_loads zeroes it just before
\ InstallIrq, and main.asm's comment there has the full story.
\ IT CAME BACK ON 2026-08-30, as a white-on-white TITLE, because that
\ clear is too late for the first title of a cold boot: TiShow paints it
\ before ts_loads runs, and TiBootPal's SetTextPal ends in SetPalPlay,
\ which reads this byte. TitleSeq clears it at its top as well now.
\ disrFlash is the ONLY byte here the IRQ reads today. Add a second and
\ it needs the same treatment — jsbeeb will not catch it for you, since
\ it powers up with RAM zeroed.
\ AND IT IS NOT ONLY THE IRQ: SetPalPlay reads it from ordinary code, on
\ every SetPalette and SetTextPal. The test for "does this byte need
\ initialising" is READ BEFORE WRITTEN OUTSIDE A GAME, not "read by the
\ interrupt" — that is what the 2026-08-30 one turned on.
\ AND THE INTRO MAKES THE LEFTOVERS REAL: pdloader unpacks its advance
\ tables over &0400-&1BFF, so on any boot through it this block holds
\ sample-table junk rather than the OS's. That is the configuration to
\ test an lowbss change against; it is the one jsbeeb's zeroed RAM
\ cannot fake.
\
\ It is NOT contiguous with the code, and it must not become so: page
\ &0D between them is the NMI handler, its workspace, the extended
\ vector table and the sideways ROMs' private-workspace bytes. See
\ LOW_ADDR in main.asm.
ORG LOWBSS_ADDR
.lowbss_start

\ ---- DrawTileCells ------------------------------------------
.dtcCol     SKIP 1
.dtcRow     SKIP 1
.dtcCharX   SKIP 1
.dtcCharY   SKIP 1
.dtcCell    SKIP 1
.dtcIdx     SKIP 1
.dtcTmp     SKIP 2

\ ---- the animated-tile scan ---------------------------------
.animCol    SKIP ANIM_MAX
.animRow    SKIP ANIM_MAX
.animKind   SKIP ANIM_MAX
.animCount  SKIP 1
.animWant   SKIP 1
.animDirty  SKIP 1              \ SprSplitOK reads this: buffer work to do
.animSave   SKIP CHAR_BYTES     \ the character the rotation carries round
.ansCol     SKIP 1
.ansRow     SKIP 1
.ansLeft    SKIP 1

\ ---- three droid-table arrays, evicted from bank 4 ----------
\ Pure state, read only by droid.asm, and absolute addressing costs the
\ same either side of the bank boundary. See droid.asm.
.drVis      SKIP DR_SLOTS       \ last sight-line answer, per droid
.drVisNew   SKIP DR_SLOTS       \ needs one now, having just been allocated
.drBulFrm   SKIP DR_SLOTS       \ an enemy bullet's effect frame

\ ---- the alert lamp -----------------------------------------
.lampWant   SKIP 1
.lampHave   SKIP 1
\ lampTmp (2 B) freed 2026-08-21: BuildLampChar now reads the lampSrc
\ cache in bank 4 instead of computing a charSrc offset here.

\ ---- the disruptor -----------------------------------------
.disruptorCnt   SKIP 1          \ counts 4 down to 0 while a burst runs
.disruptorOwner SKIP 1          \ 0 the player's, non-zero a droid's
.cbNoScore      SKIP 1          \ DrKillDroid: this kill pays nobody
.disrFlash      SKIP 1          \ SetPalPlay forces logical 0 white

\ ---- Layer 11d's information screens -----------------------
\ The only two bytes of theirs that main RAM has to see: the loop tests
\ one and the trampoline acts on the other. Everything else is in bank 7
\ with infoscr.asm. HERE rather than beside xferActive because main RAM
\ below &3000 is down to its last few dozen bytes.
.infoActive     SKIP 1          \ non-zero: a screen owns the play area
.infoAct        SKIP 1          \ IS_ACT_*: what to do when it is dismissed

\ ---- the tranche decision's per-slot answer ----------------
\ Written by SprScanCls (bank 5), read by SprAssignTr (bank 6): the
\ two halves of the split decision can never see each other, so the
\ answer crosses the page flip here. Rewritten whole every pass before
\ it is read, so it needs no seeding. This took lowbss's last 8 bytes
\ (2026-09-01).
.sprCls         SKIP 8          \ SPR_SLOTS, declared after this file

IF DEBUG_ENERGY
\ The bank-4 bytes DbgEnergyOut cannot read for itself: bank 6 is paged
\ while it runs. Its shim in lowcode2.asm fills these first.
.dbgEnMirror
IF DEBUG_MAPGUARD
  SKIP 8                        \ drType, drEnergy, then mgHit..mgWant whole
ELSE
  SKIP 2
ENDIF
ENDIF

.lowbss_end
ASSERT lowbss_end <= LOWBSS_LIMIT
