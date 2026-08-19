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
.animTmp    SKIP 1
.animSave   SKIP CHAR_BYTES     \ the character the rotation carries round
.ansCol     SKIP 1
.ansRow     SKIP 1
.ansLeft    SKIP 1

\ ---- the alert lamp -----------------------------------------
.lampWant   SKIP 1
.lampHave   SKIP 1
.lampTmp    SKIP 2

.lowbss_end
ASSERT lowbss_end <= LOWBSS_LIMIT
