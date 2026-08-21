# Layer 11f — the front end: briefing scroller, high score, title sound

**Status: PLANNED, nothing built. Written 2026-08-21 from the listing.** This is the rest of
Layer 11 — everything the original does *outside* a game, which Layers 11a–11e left deferred:

- `DoHighScore` (`$E4E5`) — PLAN.md's "the last one"
- the **intro manual**, the five-page briefing the title falls into on a timeout
  (layer-11-sound-title.md §8)
- **title sound** — the chatter (`sndState $11`) from layer-11e-sound.md §8. **Pause and the ±
  volume keys are deferred** (KC, 2026-08-21) and stay where 11e left them

Every deviation is marked **[DECISION n]** and collected in §6. **4, 5, 6 and 9 were taken with
KC on 2026-08-21**; the rest are proposals, and this document is the thing to argue with rather
than a work order.

---

## 1. What the C64 does, in flow order

```
TitleLoop ($10D3)
    sndState = 0, Sound                     silence
    ShowTitle ($2879)                       logo screen; 256 frames, or fire
    fired ($53 != 0)? ─────────────────────> StartGame
    not fired:
        clear $4000/$4900, build the screen  the status BOX, drawn by four
        DrawString $6900/$6917/$6937/$693C   DrawStrings — the same box the game has
        scoreAdd/scoreSub + DoScore          HIGH and LOW score into the box
        sndState = $11, Sound                the chatter starts
        ScreenPosX/Y = 0, SetIntroColors
        per page ($1184 .. $123F):
            DrawString $6A16                 "Briefing" on the box's text line
            page 5? random dType,
                    BuildIntroSprites        a droid portrait on the last page
            scroll down over the canvas      RunGame + DoBlkWhte + AdjustVolume a field
            fire ─────────────────────────>  StartGame       (at ANY point)
            page += 320 px; page 6 ────────> back to TitleLoop
EndGame ($378B) ──> DoHighScore ($E4E5) ──> JMP TitleLoop
```

Two things bind the three pieces of work together:

1. **The high score table IS a page of the briefing.** `DoHighScore` does not draw a table;
   `UpdateTextScore` (`$E5AC`) writes the initials and the score **into the packed briefing text
   in place**, at `$DD89` and `$DDB4` — the `'    6809 - AEB'` and `'    6502 - BAD'` lines of
   page 5. So the score is *stored* by `DoHighScore` and *displayed* by the briefing.
2. **The briefing runs the game's own status box and its own scroll engine.** It is the game's
   screen, not a screen of its own — which is why the port needs no new display for it.

## 2. `DoHighScore` — the whole of it

`$E4E5`–`$E5AB`, ~200 bytes of C64. It is small, and it is completely specified:

| | |
|---|---|
| State | `HighScore` `$E70C` = `00 00 68 09` BCD, `LowScore` `$E710` = `00 00 65 02`, and the initials in `Initials_txt` — **AEB** and **BAD**. Braybrook's joke; ship the values verbatim |
| Test | Compare `Score` against `HighScore` MSB-first over 4 BCD bytes. Higher → new HIGH. Otherwise compare against `LowScore`; **lower → new LOW**. Equal to either, or in between → `RTS`, no screen |
| Screen | `DrawString $E733` = row 10 col 13 `"Great Score!"` (or `$E742` = row 10 col 5 `"Lowest Score of the Day!"`), then `$E714` = row 22 col 1 `"Please enter your initials -"` |
| Entry | `GetInitial` (`$E56D`) ×3. An index 0–26 walks `CapitalAlpha_t` = **A–Z then space**, moved by `joyYDir + joyXDir` (either axis), wrapping at both ends, redrawn each step at row 22 col 31 as `A..` → `AB.` → `ABC` (`Initials_txt+3/+4` are pre-set to `.`), `DelayScore #$40` as the repeat rate. Fire commits; then it waits for fire to be **released** before the next initial |
| Publish | `UpdateTextScore` writes the three initials at offset 11–13 of the briefing line and the eight BCD digits at offset 0, suppressing leading zeros with spaces |

**Where it lands here.** Bank 7, beside `GoStart`/`GoTick` and the info screens — the game-over
seam is already there, and bank 7 survives a `GoTitle` (only `PARAFNT`, `PARTITL` and `PARALOW`
reload), so the table persists across games. Rows 10 and 22 are C64 play-area rows; the port's
play area starts at C64 row 8, so they are **port rows 2 and 14** of the sixteen — both on
screen, no re-fit. `PnStr`/`PnGlyph`'s glyph engine and `IsPrint`'s shadow screen already draw
this kind of text.

**Seam.** `IsTick`'s `IS_ACT_TITLE` arm → `DoHighScore` → `GoTitle`, which is exactly where the
C64 puts it (`$3812`, between the 999 page and `TitleLoop`).

**Cost.** ~250 B of 6502 plus 14 B of state. **Bank 7 has 314 B free** — it should fit, with
nothing to spare. [DECISION 1] is whether to accept that or move something first.

**Two port-only questions**, both small:

- **Keys.** The C64 reads either joystick axis. The port has Z/X/K/M/L; use **K/M** to walk the
  alphabet and **L** to commit, matching the transfer game's own entry idiom.
- **Nothing displays the table until the briefing exists.** Built alone, `DoHighScore` records a
  score nobody can read. That is fine — it is the original's own architecture — but it means F1
  cannot be *seen* working except by poking memory, so its verification is a memory check, and
  the briefing is what makes it visible. [DECISION 2]

## 3. The briefing scroller

### 3a. The data, decoded

`$D000`–`$DED0`, **3,792 bytes, 119 records**, read by `UpackText` (`$3C14`). The format:

```
byte 0   canvas row      (AND $3F, OR $80 -> $80..$BF)
byte 1   canvas column
byte 2+  characters, terminated by a bit-7 byte
         a record that terminates before byte 4 ends the whole text
```

Each character is written **twice** — code `c` at `dest` and `c OR $80` at `dest+$100` — because
the text font is 8 × 16 and the canvas stride is 256. And `UpTextChar` (`$3C4E`) writes a
**second column** for any code in `$3A`–`$59`: **capitals are 16 px wide**, exactly as
`DrawChar` and `export_font.py` already have it.

Decoded, the canvas is:

| | |
|---|---|
| Stride | 256 bytes; a text line is **two** canvas rows |
| Rows used | `$82`–`$BB` — text lines 1 to 29 |
| Columns | 5 pages of 40, at column `2 + 40n` |
| Pages | 0 credits + controls, 1 the story, 2 the Influence Device, 3 the console and robot numbers, 4 **the score table**, the pause keys and the Braybrook/Turner credit |

The port needs no canvas at all: **render from the record list.** Sorted by row at export time
with a per-row index, "paint canvas row R" is a scan of one short list. That drops
`UpackText`, the 15.5 K canvas and the whole `$8000` staging — a *removal*, not a substitution.
[DECISION 3]

### 3b. Geometry — it is the game's display, unchanged

**The briefing screen is the game screen.** The C64 runs it under the status box with the game's
own scroll engine, so the port runs it under the rupture it already has: the 4-row panel, the
gap, and the scrolled area beneath. **15 rows, not 16** — the same as the deck, and for the same
reason: a view that scrolls cannot show the 16th row of a strip that has one hardware wrap.
Nothing about the display changes for the briefing, and nothing needs deciding about it. (An
earlier draft of this document offered a choice here. There was no choice; the entry is kept
only so the mistake is not made twice.)

Width matches exactly: a page is 40 characters of 8 px = **320 px**, which is the port's play
area. Height differs — the C64 scrolls 17 rows (its rows 8–24), the port 15 — so a page's 58
canvas rows take 43 rows of scrolling here against the original's 41. Same content, ~5 % more
travel, and the port's vertical scroll is **1 scanline** where the C64's is 1 pixel of a taller
character, so the motion is at least as smooth.

Horizontal is **not** a scroll: `ScreenPosX += $140` is a jump-cut to the next page top
(`$122B`, then `JMP _3`). So the port needs vertical scrolling only, over the strip it already
scrolls, with `SetCRTCStart`/`WrapBufFwd` from `bufcore.asm` and a row painter modelled on
`DrawBandRows` — reading briefing records where that reads the tile map.

The row painter is the only genuinely new drawing code, and it is simple: a canvas row is
either the **top** cells (even row) or the **bottom** cells (odd row) of a text line's glyphs,
each one MODE 1 cell of 16 bytes out of `PARAFNT`'s 32-byte glyphs. No partial glyphs, no
masking, no shifting.

### 3c. Three glyphs are missing

The briefing uses **comma (`$29`)** and **apostrophe (`$2D`)**, and `export_font.py` exports
neither: the port's 102 glyphs stop at `!`. Semicolon (`$2B`) should be checked with them.
Adding them is three lines in the exporter — but `PARAFNT` runs `&3000`–`&3D98` and `SPR_SAVE`
is at `&3E00`, so there are **104 free bytes**: three 32-byte glyphs fit with 8 to spare. A
fourth would move `SPR_SAVE` and the tile map with it. Worth knowing before adding anything else
to that file.

### 3d. Where it runs, and the RAM problem — measured

The right place is **after `TitleSeq` returns and before `GameStart`**: the rupture is up, the
panel is built and drawn, the font is home at `&3000`, the tables are built and the IRQ — and
therefore the sound tick — is running. Everything the briefing scribbles on is ground
`GameStart` and `LoadDeck` rebuild anyway.

The overlay itself is a **ninth disc file, `PARMAN`**, loaded inside `TitleSeq` before
`PageLowIn` (the last filing-system call) and only when the title timed out — so the
fire-to-play path pays nothing. It lands on the sprite save areas and the tile map.

**The panel stays where it is and stays displayed**, and the briefing does not have to fit in
the gaps around it — because outside a game **there is no reason for the blitter to be in
memory**. KC's call, 2026-08-21, and it dissolves the whole squeeze:

> **Bank 5 is evicted for the briefing and reloaded on the way into the game.** `PARASPR` is
> 16 K of compiled blitter, paged only inside `SprDrawAll`/`SprRestoreAll`, and no sprite runs
> on a modal screen. The briefing gets a whole bank to itself. **[DECISION 4]**

Against that, the numbers stop being interesting: records in port form are **3,673 B** and the
driver ~700, so the briefing is **~4.4 K in a 16 K bank with ~12 K spare**. No page buffer, no
split across holes, no borrowing of `&5400`, nothing packed at rest, and **main RAM is not
touched at all** — the sprite save areas, the tile map and the three built tables are all left
alone.

**`PARMAN` is therefore a fifth bank file, not a main-RAM overlay**, and it ships the way the
other four do: `tools/make_disc.py` ZX0s it whole, `*LOAD` drops the stream at `DEPK_STREAM`
and `PARDEPK` unpacks it straight into the bank. So **the text is compressed on disc**, which is
where compression pays — it is load time, not RAM, that it buys. (KC, 2026-08-21: compress the
text screens for sure. Per-*page* streams and a runtime page buffer, which the old squeeze
needed, are no longer wanted for space; if they are ever wanted for another reason it is a
change to the exporter alone.) **[DECISION 5]**

**What it costs is a load on the way back**, and KC wants that minimised (2026-08-21). The naive
exit reloads four files — `PARDEPK`, the `PARASPR` stream, `PARAFNT` and `PARALOW`, 7,512 B and
about 1.1 s — but three of the four are avoidable, and what is left is **one load of 2,833 B,
≈ 0.4 s**:

| | | |
|---|---|---|
| `PARDEPK` | **not loaded** | The unpack needs a depacker in *main RAM* (only one bank is visible, so bank 4's copy cannot write bank 5). The briefing carries the `ZX0_DEPACKER` macro in its own 12 K of spare and **copies ~273 B of it into the strip** before it pages itself out. A third copy of a macro that already exists twice |
| `PARAFNT` | **not reloaded** | It only ever came back because `PARDEPK` lands at `&3000`, on the font. With no `PARDEPK` the font is never disturbed, and the stream can land in the strip too — 10 K, holding nothing but the briefing's last page, which `LoadDeck` is about to redraw |
| `PARALOW` | **not reloaded** | The low overlay is lost to the load only because DFS wants `&0E00`–`&10FF` back. Snapshot it into the strip and copy it home afterwards — the mirror image of what `SaveDfsWs`/`RestoreDfsWs` already do for DFS's side, same two spans (`&0D60`–`&0DEF`, `&0E00`–`&10FF`, 912 B) |
| `PARASPR` | **2,833 B, ≈ 0.4 s** | Irreducible: it is the thing that was evicted |

The load still cannot happen with the rupture up — `R7` stops VSync and a filing-system call
hangs in the 8271 poll — so the exit is still a teardown and rebuild: `SetupMode`,
`UninstallIrq`, `RestoreDfsWs`, the one load, the two copies home, `SetupRupture`, the table
builders, `InstallIrq`. **That is `GoTitle`'s tail with the loads swapped out**, and `GoTitle` is
built and proven, so the work is to factor it, not write it. Mind that the strip is being used
as scratch across it: nothing in that tail writes above `&5800` (`FillPanel` is the panel,
the three builders are `&5400`–`&57FF`), but `IS_BLANK` does, so it moves after the copies home.
**[DECISION 6]**

**Ordering on the way in.** `PARMAN` loads inside `TitleSeq` only when the title timed out, and
it can use `PARDEPK` and `DEPK_STREAM` exactly as boot does, because at that moment `PARTITL` is
dead on `&3000` and `PARAFNT` has not been loaded yet — so the inbound half costs one 2.5 K
stream and nothing else changes.

**The alternative is zero load, and it is available.** Compressing the text — which KC has
asked for anyway — makes the briefing fit *without* eviction: five per-page ZX0 streams
(2,475 B) plus a 910 B page buffer in the main-RAM holes at `&3E00`–`&49FF` and `&5400`–`&57FF`,
with the ~700 B driver in bank 5's existing 1,033 free bytes. No eviction, no reload, nothing
seen by the player. It costs the last of bank 5's spare permanently, borrows the three built
tables and re-runs their builders, adds a depack per page turn, and leaves the briefing text no
room to grow. **Recommended: take the eviction and the 0.4 s.** The squeeze is real work to
save four tenths of a second, once, on a path the player chose by *not* pressing fire.

### 3e. The rest of the behaviour

| | |
|---|---|
| Scroll | ~1 px a field, adjusted by the stick (`$11F5`: `ySpd` = `$FF`, hi = `$FF - joyYDir`). Transcribe the arithmetic at build time rather than trusting this line |
| Dwell | `frameCount` holds the top and bottom of each page for ~128 fields; pushing up skips it |
| Page 5 | `ScreenPosX+1 == 5` picks `dType = rnd AND $F` and calls `BuildIntroSprites` — the port has `PoDraw` and the whole portrait pool in bank 7, parameterised since Layer 11d. A page needs to hold a rectangle for it |
| Exit | Fire at **any** point starts the game; falling off page 5 goes back to the title |
| `DoBlkWhte` | the C64's monochrome-monitor toggle on the title. **Not ported**, no equivalent question in MODE 1 — noted so it is not mistaken for an omission later |
| The score lines | patched from bank 7's `HighScore`/`LowScore`/initials as page 5 is drawn, which is `UpdateTextScore`'s job moved to the read side. [DECISION 7] |

## 4. Front-end sound

Three pieces, all deferred rather than unknown, and layer-11e already costed them.

**Title chatter** — `sndState $11`, effects `$1D`–`$1F` and `$10`. `Sound._chatter` (`$054A`) is
20 lines: a counter, every 128 ticks pick one of three blips by a random third, at two counter
phases fire `$10` on channel 2, and every 16 ticks nudge channel 3's frequency slide by a
random amount. The three effect records were **dropped from the export** to save 36 B in bank 4
(11e stage 2) — they come back. `$D41B` becomes an LFSR; `DrRandom` is bank 4's and must stay
one sequence, so the chatter needs its own.

**The tick.** [DECISION 4 of 11e] deferred this because the title runs under the MOS IRQ with no
pass structure. Two fixes, and they are different for the two screens:

- The **title** (`TiShow`/`TiWait`) still runs before `InstallIrq`. Throttle `TiWait`'s loop on
  VSync and call `SndTick` with `SWRAM_DATA` paged — **not across the `*LOAD`s**, which need the
  bank out and the chip silent. Note that VSync-throttling changes the timeout: `TiWait`'s
  present escape is a 16-bit *iteration* wrap, and at 50 Hz that would be 21 minutes. Count
  **256 fields**, which is the C64's own `$291B` timeout, and keep a fast inner counter for the
  `drSeed` entropy `TiWait` currently supplies. [DECISION 8]
- The **briefing** runs after `InstallIrq` (§3d), so it gets the 50 Hz tick for free.

**Pause and the ± volume keys — DEFERRED.** KC, 2026-08-21: leave them, we look at them later.
They stay where 11e §8 put them, and nothing in this layer waits on them. Two consequences to
carry rather than forget:

- The briefing loop is where `AdjustVolume` belongs when it comes (`$11B6`, called every field
  of the manual loop), so the loop should have an obvious place to hang it.
- **Briefing page 5 names the keys** — `'To pause: press run-stop.'` and `'From pause mode
  only: fire - restarts, run-stop - restarts, clr-home - quits game, f7 - cheese, f8 - pause.'`
  None of those keys exist on a Beeb and none of that is true of the port today, so the page
  would print a lie. **The exporter takes a text-override table** keyed by record, so those two
  blocks can be replaced or dropped now and revised when pause lands. What the replacement text
  says is KC's, at the time, not now. [DECISION 9]

## 4a. F1 as built — `DoHighScore`, 2026-08-21

**BUILT AND VERIFIED.** It is an overlay, not resident code, and getting there took removing an
obstacle rather than finding bytes.

**`SetupPlain` is what unlocked it.** `GoTitle` used to call `SetupMode`, whose first act is a
`VDU 22` — and the OS answers that by clearing `&3000-&7FFF`, taking the 999 page and the font
with it. KC: the mode change does not need the OS, because the palette, the CRTC and the
wraparound latch are all ours and are set once at boot. So `SetupPlain` (`screen.asm`, **bank 4**,
where `GoTitle` already has the bank paged for `SndSilence`, so it cost no main RAM) writes the six
registers the `VDU 22` was really there for and nothing else. **The play buffer survives the
teardown**, so the 999 page is on screen at the moment a load becomes legal.

Two things that had to be measured rather than assumed:

- **R8 is not optional.** The rupture blanks rows with it, so a teardown that leaves it set gives a
  black screen with the CRTC otherwise perfectly correct. First attempt did exactly that.
- **The palette is no longer reset**, so the title states its own — `TiPal`, the OS's MODE 1
  default values, which is what [DECISION 9] was relying on `VDU 22` to supply. Layer 14 wants
  every screen explicit anyway.

**Where the parts live.**

| | | |
|---|---|---|
| The screen | `src/highscore.asm`, in the **PARTITL overlay** | 0 resident bytes |
| Its alphabet | `src/data/hsfont.asm`, from `tools/export_hsfont.py` | 72 glyphs, 1,152 B, in the overlay |
| The table | `src/hstable.asm`, **bank 7** | 25 B — it must outlive a title, and bank 7 is the only RAM that does |
| The call | `TitleSeq`, after the `PARTITL` load | 3 B of main RAM |

The overlay carries glyphs because PARTITL is assembled over the font's ground — the same answer
the title already gives for its own 36 characters. It does **not** carry `FontCell`: that sits at
the top of the `PARAFNT` file, above the overlay's end, so the 1bpp → MODE 1 expansion is the
game's own routine. `ASSERT titl_end <= FONTCODE_ADDR` is what keeps that true, and it fired once —
the full lowercase alphabet put the overlay 80 bytes over, which is why the exporter picks only the
letters the strings actually use.

**Verified in jsbeeb**, end to end: game → ESCAPE → wash → 999 page → the mode change with the page
still displayed → `PARTITL` loads → "Great Score!" and "Please enter your initials -" drawn over
"Transmission" and "Terminated", the 999 between them → `A` walked to `G` with M → three initials
committed with L → `hsHiIni` reads G, A, A, `hsArmed` cleared, the low table untouched → title.

**One loose end, not chased.** The score copied into `hsHigh` was not the value poked into `score`
before the self-destruct. The initials, the arm flag, the arm chosen and the low table were all
exactly right, so this is a question about **what `score` holds at a game over**, not about the
entry. Worth a look before F5 makes the number visible on the briefing's score page.

## 4b. F3 as built — the briefing text, 2026-08-21

`tools/export_briefing.py` → `src/data/briefing.asm`. **Not in any build yet** — F4 is what
includes it — but the data is decoded, converted and checked.

| | |
|---|---|
| Records | 112 kept, 7 dropped (see below), five pages, canvas rows 2–58 |
| Size | 3,797 B of text and row lists + 570 B of index + 32 B of glyphs = **4,399 B** |

**The lines are NOT evenly spaced**, which cost the first attempt: page 1 steps three canvas rows
a line and the later pages two, so there is no "text line" to index by. The emitted form is
indexed by **canvas row**, and a record occupies the row it names AND the one below — the top
cells of its 8 × 16 glyphs, then the bottom ones, which is what `UpTextChar`'s `dest+$100` does.
So painting row *r* is: that row's list drawn top-half, then row *r−1*'s drawn bottom-half.

**The two missing glyphs are carried in the data.** The shared font has 103 glyphs and neither a
comma nor an apostrophe, because `export_bbc.py` converts only what a TILE references. Rather
than extend `NUM_CHARS` — which moves the code→index remap every deck depends on — the briefing
brings its own two bitmaps and the renderer plots any index ≥ `BR_COMMA` from `brExtra`. That also
frees the eight spare bytes in `PARAFNT` that this was previously going to need.

**The pause-key legend is dropped, not translated.** Seven records name RUN/STOP, CLR/HOME, f7 and
f8, none of which exist here and none of which the port does. `OVERRIDES` drops them by address;
it takes replacement text just as easily, which is the mechanism [DECISION 9] asked for.

**Verified by round-trip**, and it earned its keep: the emitted glyph indices are decoded back to
ASCII through an inverse map and diffed against the C64's own text, record for record. It failed
first time on 44 records — and the fault was in the *reference* decoder, not the export: `$16` is
capital I sitting in lowercase m's arithmetic slot and `$42` is lowercase m in capital I's, so a
range check that runs before the special cases renders both swapped. "In addition" was decoding as
"mn addition". All 112 records now agree.

## 4c. F4 — where the plumbing bytes come from. KC, 2026-08-22

F4 stalled on the same wall F1 hit: **entering** the briefing needs ~19–40 bytes of main RAM for
a paging shim and two OSCLI strings, and the resident holes are `code_end` 2 B, `lowbss` 8 B,
`lowcode2` 8 B, `lowcode` 2 B — eighteen bytes in four pieces. KC's steer was that lower RAM must
have it. **It does, and it is not a hole — it is a whole region:**

> **`&0400`–`&0C90` is the MODE 1 charset, and it is BUILT AT DECK LOAD.** Outside a game it holds
> nothing anyone wants: at boot no deck exists, and after a game over the last deck's characters
> are stale and `GameStart` → `LoadDeck` rebuilds them before anything reads them again. That is
> **2,192 bytes of free lower RAM at title and briefing time** — the same argument the sprite save
> areas and the tile map make at `&3E00`, four times the size, and below `&1100`.

Nothing in the front end reads it: the title carries its own glyphs and the briefing uses
`PARAFNT`'s text font, neither of which is the deck charset.

**So [DECISION 4] stands and F4 gets simpler.** The briefing's DRIVER lives at `&0400`, not just a
shim — 2,192 bytes is far more than the ~700 it needs — and bank 5, evicted, holds only the
4,399 bytes of text. Entry from `TitleSeq` is a `JSR` to a fixed address, which is three bytes of
main RAM, and there are two. The driver can be a disc file whose catalogue load address IS `&0400`,
so `*LOAD` puts it where it runs and no staging or copying is needed at all.

**Check before relying on it:** DFS's own workspace is `&0E00`–`&10FF` and the cassette/serial
buffers are `&0900`–`&0BFF`. The port already treats `&0400`–`&0C90` as its own during a game, but
a `*LOAD` *into* part of it while DFS is running has not been tried — verify a load lands intact
before building on it, exactly as `PARALOW` had to be staged rather than loaded.

## 5. Staging

Each step ends with something visible, and the order is chosen so nothing waits on the big one.

| | | |
|---|---|---|
| **F1** | `DoHighScore` in bank 7, the `IS_ACT_TITLE` seam, the two default entries | PLAN.md's last unbuilt in-play item. Verified by memory check + the entry screen at a game over |
| **F2** | Title chatter: the tick in `TiWait`, the field timeout, the LFSR, the three effect records back into the export | **BLOCKED 2026-08-21**: the three records are 33 B (11 each) and bank 4 has 26. The chatter's *code* can live in the title overlay, which has 112 B, but `SndTick` reads its records from bank 4's table, so those 33 B must be resident. Seven short |
| **F3** | `tools/export_briefing.py` → `src/data/briefing.asm`, plus the comma/apostrophe glyphs | Offline; verified by decoding back to text and diffing against `$D000` |
| **F4** | `PARMAN` in bank 5: row painter, page draw, one static page on the strip, and the exit rebuild in its **naive four-load form** | The first thing seen. No scrolling yet, and slow coming back |
| **F5** | Scroll, dwell, page turns, fire-to-play, the page-5 portrait, the score lines | The briefing proper |
| **F6** | Trim the exit to **one file**: carry the depacker, land the stream in the strip, snapshot the low overlay instead of reloading it | KC: get it working first, optimise the loading after. §3d has the three eliminations |

Pause and the ± volume keys are **not in this layer** — deferred by KC, 2026-08-21, and left
where 11e §8 has them.

**Verification.** The briefing is a buffer-drawing feature, so `CLAUDE.md`'s rule applies: diff
the strip against a from-scratch redraw at the same scroll position, over odd and even rows and
with `line != 0`, not screenshots. The text itself has a stronger check — decode
`src/data/briefing.asm` back to ASCII in the exporter and diff it against the `$D000` decode, so
a glyph-mapping slip cannot survive.

## 6. Decisions for KC — none of these are taken

**[DECISION 1]** `DoHighScore` goes in bank 7 on its last 314 bytes, or something moves first.

**[DECISION 2]** F1 ships before anything can display the table, and is verified by memory
inspection until F5 lands.

**[DECISION 3]** The 15.5 K canvas and `UpackText` are dropped; the port renders rows straight
from the record list with a per-row index. A removal of C64 machinery the port has no use for,
in the same spirit as the ZX0 deck maps replacing the RLE.

**[DECISION 4]** **Bank 5 is evicted for the briefing and reloaded on the way into the game.**
KC's call, and it replaces two questions an earlier draft asked — "keep or drop the status box"
(a misreading: the briefing screen *is* the game screen, box and all) and how to squeeze 4.4 K
into 4,096 bytes of main-RAM holes. Outside a game there is no reason for 16 K of blitter to be
resident; the briefing gets the bank, main RAM is untouched, and the reload is the price.

**[DECISION 5]** `PARMAN` is a **fifth bank file**, ZX0-compressed on disc by `make_disc.py` like
the other four, holding the text uncompressed at rest in a bank with ~12 K spare. This is what
"compress the text screens" buys here: load time, which is the thing that costs.

**[DECISION 6]** The briefing's exit tears the rupture down and rebuilds, reusing `GoTitle`'s
tail, and **targets a single file load** (`PARASPR`, 2,833 B, ≈ 0.4 s) by carrying its own
depacker, landing the stream in the strip and snapshotting the low overlay rather than reloading
`PARDEPK`, `PARAFNT` and `PARALOW`. KC, 2026-08-21: prefer one file, but get it working first
and optimise the loading after — so F4 may ship the four-load form and F6 trims it.

**[DECISION 7]** `UpdateTextScore` moves to the read side — page 5 is drawn *from* the stored
table rather than the table being written *into* the text. Necessary here: the port's briefing
text is in a ROM-like overlay reloaded from disc every time, so a patch would not persist.

**[DECISION 8]** `TiWait`'s timeout becomes 256 fields (the C64's own) instead of a 16-bit
iteration wrap, with a fast inner counter kept for `drSeed`'s entropy.

**[DECISION 9]** Pause and the ± volume keys are **deferred** (KC, 2026-08-21) and stay in
11e §8. Because briefing page 5 prints the C64's key legend — RUN/STOP, CLR/HOME, f7, f8 —
and none of it is true here, the exporter carries a **text-override table** and those two blocks
are replaced or dropped until pause exists. The replacement wording is KC's, later.

## 7. RAM ledger

| | |
|---|---|
| `DoHighScore` + table | ~264 B, **bank 7** (314 free) |
| Chatter: three effect records + tick shim | ~36 B bank 4 (60 free) + ~40 B main RAM (5 free below `&3000`, ~50 in pieces) — **the main-RAM shim is the risk** |
| Briefing driver + text | **0 resident** — `PARMAN` lands on two holes that are rebuilt after it: `&3E00`–`&49FF` by `GameStart`/`LoadDeck`, `&5400`–`&57FF` by the three table builders. 3,385 B of data + ~711 B for the driver, in 4,096 |
| Three font glyphs | 96 B of `PARAFNT`'s 104 spare |
| Pause + volume | **not in this layer** — deferred, 11e §8 |

The briefing — the largest piece of work here — is the one that costs no resident RAM at all.
`DoHighScore` and the chatter's shim are the two that need space in a machine that has none, and
`docs/memory-map.md`'s free-RAM section is the place to go before either.
