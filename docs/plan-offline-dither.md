# Plan: moving the tile dither offline (issue #5)

Written 2026-09-12 on branch `dither`, answering `docs/prompt-offline-dither.md`.
**A plan, not an implementation.** Nothing in `src/` was changed to produce it.

Every number below was measured today, on this branch's build (`build 12 Sep 2026 21:46:58`,
`DEBUG: XFERWIN DECK KILL REDRAW`), either from the beebasm listing, from the exporters, or in
the jsbeeb MCP. Where a number contradicts a comment in the tree, that is called out.

---

## 0. The headline, before the detail

Three things the brief did not know, all measured:

1. **The dither costs 52 ms of a 192 ms deck load, not the ~5 ms `src/level.asm` claims.**
   `BuildCharset` end to end is **384,261 cycles** (breakpoints at `&A56D` and `&A693`,
   elapsed 30,872,492 → 31,256,753). One `DitherChar` body is **769 cycles** (`&A6AD` → `&A6CD`),
   and it runs 133 times, so the dither alone is **~102,300 cycles ≈ 51 ms**, 27% of the load.
   The comment at `src/level.asm:419` is wrong by an order of magnitude and should be corrected
   whatever else happens.

2. **The "central problem" is almost not a problem.** The brief frames the deck dependence as
   fatal to pre-rendering. It is real but tiny: a pixel is logical 0 iff the source bit is clear,
   **or** the character's ink merged onto logical 0 — and across all 16 decks that second case
   touches **7 characters of 137**, 3 or 7 on any given deck. It stays free anyway, because the
   runtime `AND` against `SPR_MASKTAB` already answers it and does not have to go away.

3. **Shipping a full per-pixel plane costs +29 bytes of stream and 1,096 bytes of staging, and
   the staging exists** — but not where the first draft of this plan looked. Appending a
   per-character 8-byte dither bitmap to the `chardata` ZX0 stream costs **+29 bytes packed**
   (809 → 838; raw 1,352 → 2,448) — nothing. `SPR_SAVE` alone is `&3E00–&45FF`, 2,048 bytes with
   1,352 spent (1,096 bitmaps + 256 remap), so 696 free and the plane wants 1,096. **But the
   TILE MAP at `&4600–&4A00` is dead scratch at that moment and is contiguous with it** (§2e), so
   the window is 3,072 bytes against 2,448 needed. Interleaving the two planes is worse (packs
   to 962); append, do not interleave.

So the shape that wins is **the bake** — ship a second bit-plane saying "dither here", per pixel,
per character, decided offline (§2e). The `DitherChar` pass, both class tests and the ALERT
constant all go. The fallback, if the tilemap claim does not survive verification, is a
per-character index into a small table of 8×8 patterns (§2b), which produces **byte-identical
output** for every scheme anyone has proposed and costs 69 bytes of staging instead of 1,096.

---

## 1. What the port does today, precisely

| | |
|---|---|
| `src/level.asm:282-375` | `bc_char`, the per-character loop: reads the C64 colour slot from `charSlotP`, looks the colour up through `schemes` and `colourMap`, and expands each source nibble through `LUTs` into the 16 MODE 1 bytes at `(bcDst)` / `(bcDst2)` |
| `src/level.asm:261-271` | the deck-level gate: `dcBase` = `&05` only where `deckPalette+1` is physical black, else 0 |
| `src/level.asm:328-346` | the ALERT exception: charset indices 52-55 skipped, `ALERT_IDX0 = 52`, guarded by `ASSERT NUM_CHARS = 137` |
| `src/level.asm:347-359` | **the branch's experiment (e9226c0)**: `bcSlot < 2` → `DitherFloor`, else `DitherWall` |
| `src/level.asm:432-464` | `DitherWall` (13 B), `DitherFloor` (12 B), `DitherChar` (33 B) |
| `src/lowcode.asm:510` | `BuildLampChar` re-dithers character `$16` during play via `JMP DitherWall` |
| `tools/export_bbc.py:489` | `dither_charset()`, the byte-for-byte Python oracle — **now stale**: it still models the single 2×2 checker and knows nothing about `DitherFloor` |

Sizes in bank 4 today, from `build/paradroid.lst`:

| | bytes |
|---|---|
| `DitherWall` + `DitherFloor` + `DitherChar` (`&A694`–`&A6CD`) | 58 |
| the class test (`&A64F`–`&A65E`) | 16 |
| the ALERT test (`&A645`–`&A64E`) | 10 |
| `STA bcSlot` in the loop | 3 |
| `dcBase`, `bcSlot`, `dcMask` (2) | 4 |
| **total** | **91** |

Bank 4 free on this branch: **25 B** (`bank4 ends &BFE7`) — 64 B on `main`, the experiment having
spent 39. Main RAM 39 B (`code_end &2FD9`), bank 6 254 B, bank 7 84 B. This branch is one commit
behind `main` (66f82c3), which is why bank 5 reads 342 B here and 148 B there; irrelevant to this
work, but rebase before quoting bank 5 anywhere.

---

## 2. The options, costed

Common to all: the data rides in the existing `chardata` ZX0 stream where it can, because that
stream is bank 4's and bank 4 is the tight one. Staging is `SPR_SAVE` with 696 bytes spare —
and, if §2e's claim holds, the tilemap's 1,024 on top of that.

### (a) per-character 16-byte MODE 1 dither mask, ANDed at deck load

Precision: total. Cost: **+29 B** of packed stream, **+2,192 B of staging** (a MODE 1 mask is 16
bytes a character, twice the source plane's 8), and it does not remove `DitherChar`, only its mask
arithmetic — you still pay the 769-cycle pass. **Superseded by (e)**, which gets the same precision
from half the staging by keeping the mask in SOURCE form. The two escapes considered before (e)
was found, both worse:

- a **second stream** depacked over the bitmaps after they are consumed. Works (the bitmaps are
  dead once the charset is built), but needs a second `Zx0Unpack` call, a second walk of the
  charset, and it keeps ~769 cycles a character. It also cannot be folded into `bc_row`, which is
  where the cycles actually are.
- the **play buffer** as scratch. `LoadDeck` (`src/droid.asm:186`) runs `BuildCharset` before
  `BuildLevel`, and `ReframeView`/`RedrawAll` repaints the whole strip afterwards, so `&5800–&7FFF`
  is logically dead — **but it is on display throughout**, and `src/lift.asm:41` says so in as many
  words ("our LoadDeck draws into the play buffer the side view is occupying"). 1,096 bytes of
  mask would be a visible garbage stripe for ~192 ms. **Do not.**

### (b) per-character pattern index + a small pattern table — the fallback

An 8-byte pattern is one bit per pixel of an 8×8 cell, **in exactly the source bitmap's layout**,
so it needs no expansion table at all: in MODE 1 the low-plane bits for pixels 0-3 *are* bits 3-0
of the byte, which is what the source nibble already is. The dither nibble drops straight into the
`ORA`.

Measured: **the current scheme needs 3 distinct patterns** — `55aa55aa55aa55aa` (the 2×2 checker),
`0055005500550055` (the quarter), `0000000000000000` (none, for ALERT).

| | bytes |
|---|---|
| pattern indices, nibble-packed like `charSlotP`, **carried in the ZX0 stream** | 69 raw into staging (fits in 696); packed cost ≈ 10-20 B of bank 4 |
| pattern table, 8 B each, resident in bank 4 | 24 B for today's three; 8 B per pattern added |
| the fold into `bc_row` (see §3) | ~55 B |
| **removed** | **−91 B** |
| **net bank 4** | **≈ −12 B, i.e. about 12 bytes recovered** |

Cycles: the separate 769-cycle pass disappears; the row loop grows by roughly 25 cycles a byte
across 16 bytes, so ~400 a character against 769 plus loop overhead. **Deck load drops by
~40 ms of 192.**

Precision bought: **any 8×8 pattern, chosen per character.** That is the whole of the precision
argument in issue #5 — vertical stripes on the wall, quarter on the floor, a different phase on the
grid, nothing on the lettering — and it is per-pixel *within* a character. What it does not buy is
a different pattern for two instances of the *same* character in different tiles; see §6.

### (c) keep `DitherChar`, drive `dcMask` from exported per-character data

Cheapest diff: replace the class test with a table lookup, indices in the stream, a 2-byte mask
pair per pattern. Removes the 16-byte class test and the two prologues (~41 B), adds ~20 B.
Keeps the 51 ms and keeps the pass. Restricted to patterns with vertical period 2 — which covers
all nine of `dither_lab.py`'s options, so it is not as limiting as it sounds. **This is the
fallback if §3's fold turns out to cost more bank-4 bytes than it saves.**

### (d) pre-dither offline only where the answer is deck-independent

Would mean pre-rendering 130 of the 137 characters and running the pass on 7 — but the
pre-rendered form is *MODE 1*, and MODE 1 depends on the deck's colours, not just on which pixels
are logical 0. So this collapses to (a) with extra steps. **Reject.**

### (e) BAKE IT INTO THE TILE DATA — RECOMMENDED

KC, on reading the above: *"Can't we just bake the dither pattern into the tiles at build time?"*
Yes — with one structural correction, and then it is the best of these.

**What does not work: editing the bitmaps the port already ships.** `chardata.asm` carries the C64
characters at **1 bit per pixel**, and a set bit does not mean "black" or "logical 1" — it means
*this cell's ink*, whatever colour the deck gives it. The dither wants a **third** value the format
cannot spell: not background, not ink, but background-shaded-to-logical-1. Setting the bit would
paint the character's own ink there, which is precisely the ALERT bug from issue #5 — the letters
dissolving into their own background — applied deliberately to every tile on the ship. So the bake
cannot be a rewrite of the existing plane; it has to **grow the source a second plane**.

**What that costs, measured:**

| | |
|---|---|
| a second 8-byte-per-character plane, appended to the `chardata` stream | **+29 B packed** (809 → 838) |
| staging to unpack it into | +1,096 B — see below |
| `bcDthSrc`, a second source pointer walking in lockstep with `bcSrc` | ~14 B of code |
| the fold into `bc_row` (§3) | ~40 B |
| the lamp's 8 dither bytes cached beside `lampSrc` | 8 B |
| **removed** | **−91 B** |
| **net bank 4** | **≈ −29 B recovered** |

It needs no pattern table, no index nibbles, no per-character setup and no 16-pattern ceiling —
the plane simply walks alongside the bitmap, eight bytes a character, the same shape `bcSrc`
already has. It is **smaller in code than (b)** and strictly more general.

**The staging, which is the whole question.** `SPR_SAVE` has 696 free, and the plane wants 1,096.
But `LoadDeck` (`src/droid.asm:181-210`) is `BuildCharset` → `AnimReset` → three sound stores →
`BuildLevel`, and:

- `BuildLevel` (`src/level.asm:153-161`) is a **bare ZX0 unpack straight into `tilemap`** — no
  merge, no partial write, all 1,024 bytes replaced unconditionally on every deck load;
- `AnimReset` (`src/lowcode.asm:464-470`) writes `lampHave`, `animCount`, `animDirty` and returns;
- nothing between the two reads the map, and the display never does — the CRTC reads the play
  buffer, and the map is only ever *source* data for a draw, all of which happen after.

So `&4600–&4A00` is dead scratch across `BuildCharset`, and it is **contiguous with `SPR_SAVE`'s
`&45FF`**. The staging window becomes `&3E00–&4A00`, **3,072 bytes for 2,448 needed** (1,096
bitmaps + 1,096 dither + 256 remap), and the existing single `UnpackChars` call still does it in
one go with one destination.

**This is read from the source, not yet measured**, and it is the one claim the whole option rests
on. §5 says how to prove it. If it fails, fall back to (b) — which draws the same pixels.

---

## 3. The recommended shape, concretely

**Fold the dither into `bc_row` and delete `DitherChar`.** The row loop already holds, per output
byte, the source nibble and the finished MODE 1 byte. Add, per half:

    LDA (bcDthSrc),Y      \ the pattern's scanline, both halves in one byte
    <the same nibble split the bitmap gets>
    AND dcEnable          \ &FF, or 0 on a deck that keeps a solid floor
    STA bcDth
    LDA LUTs,X            \ as now
    TAX
    LDA SPR_MASKTAB,X     \ set bit = this pixel is logical 0
    AND bcDth
    STX bcTmp : ORA bcTmp \ or keep the byte in a scratch as DitherChar does
    STA (bcDst),Y

Under **(e)** `bcDthSrc` is a second source pointer advanced by 8 alongside `bcSrc` at the foot of
the character loop — no per-character setup at all. Under **(b)** it is set per character from the
pattern index instead; everything else is identical.

The per-byte `AND SPR_MASKTAB` is retained deliberately: it is what keeps the 7 merged-ink
characters correct without any deck-dependent data, and it is what makes the whole scheme
deck-independent. **This is the reason the bake is a bake of the SOURCE and not of the output** —
the offline tool decides *where* the dither goes, the 6502 still decides *whether* that pixel
turned out to be logical 0 on this deck, and neither has to know about the other.

**The three exceptions become data or a gate:**

| exception | today | under (b) |
|---|---|---|
| the deck-level skip (logical 1 not black) | `dcBase` = 0 makes both mask entries 0 | `dcEnable` = 0, one `AND` in the row loop. Same test at `level.asm:261`, unchanged |
| the ALERT lettering (indices 52-55) | a 10-byte range test, `ALERT_IDX0`, `ASSERT NUM_CHARS = 137` | **eight zero bytes in those characters' dither plane** (under (b), pattern index 0). The test, the constant and the tripwire all go away, and the fragility the comment warns about ("if the set moves, recompute") goes with them — the exporter works in C64 codes, not charset indices |
| floor vs structure (this branch's experiment) | `bcSlot < 2` at run time | the exporter's **default assignment rule**, by colour slot, written into the data file. The rule is kept; the 6502 stops evaluating it |

**`BuildLampChar` (`src/lowcode.asm:456-511`).** It rebuilds character `$16` during play, when the
staging is long gone — the same problem `lampSrc` already solves for the bitmap. Cache the
**pattern index** for that one character at deck load, beside `lampSrc` (1 byte), and let
`BuildLampChar` run the same fold against the resident pattern table. Reaching bank 4 from there is
already legal and already done. `$16`'s slot is 14, so it takes the wall pattern today and will
take whatever the data says tomorrow — which is a small improvement in itself, since it is
currently hard-wired to `DitherWall` in a comment.

**What to do with e9226c0.** **Fold it in, do not revert it and do not build on it.** Its *choice*
— quarter on the floor, 2×2 on everything else — is KC's and survives verbatim as the exporter's
default rule. Its *code* is exactly what (b) deletes: `DitherWall`, `DitherFloor`, `bcSlot` and the
class test are all in the 91 bytes. Keeping it as a stepping stone means writing 39 bytes of bank 4
that the next commit removes. If the offline work is not going to happen soon, the experiment
should be measured, `[DECISION]`-ed and merged on its own terms; if it is, it should stay parked
here and land as part of the offline change.

---

## 4. The authoring half

Follow the `tools/palette_lab.py` → `tools/deck_palettes.json` → `export_bbc.py` pattern exactly,
because it is established, reviewed and understood here.

**`tools/dither_map.json`** — hand-editable, committed, the source of truth:

```json
{
  "patterns": {
    "none":    ["........", "........", ...],
    "checker": [".X.X.X.X", "X.X.X.X.", ...],
    "quarter": ["........", ".X.X.X.X", ...]
  },
  "default_by_slot": { "0": "quarter", "1": "quarter", "*": "checker" },
  "by_code": { "0x63": "none", "0x64": "none", "0x65": "none", "0x66": "none" }
}
```

Keyed by **C64 character code**, never by charset index — that is what retires `ALERT_IDX0` and
its `ASSERT`. `default_by_slot` carries e9226c0's rule so the file states the decision rather than
hiding it in assembly. Eight-row ASCII art so a pattern is legible in a diff, which is the whole
point of committing exporter output.

**`tools/dither_lab.py`** becomes the editor rather than a gallery: it already renders a deck
exactly as the BBC draws it (it imports `convert_charset` and `build_logical_map` from
`export_bbc`, so there is one definition of the rule, as `palette_lab.py` does). Extend it to read
`dither_map.json`, render the *current* map alongside the nine fixed options, and let a human
reassign a character or a slot and write the file back. Its floor/wall docstring is already the
right classification and should move into the JSON as `default_by_slot` and stop being prose.

`export_bbc.py` reads the JSON and, under **(e)**, resolves code → pattern → **eight bytes**,
appending 137 × 8 to the `chardata` stream after the bitmaps and before the remap. Nothing else
changes: one stream, one `UnpackChars`, one destination. `CHARSRC_SIZE` gains a sibling
(`CHARDTH_OFS`) so the assembler can address the plane, and the existing
`ASSERT XFER_STREAM >= &3E00`-style bound gains one for the new staging top against `&4A00`.

Under **(b)** it instead dedupes the pattern set, emits index nibbles into the stream and a
`.dtherPat` table beside `charSlotP`, and must **fail the build** if the set exceeds 16 patterns —
a loud stop, not a clamp. Unlike a size `ASSERT` on a packed overlay this one cannot deadlock a
build, because the exporter is not the assembler.

Note that under (e) the JSON's `patterns` are an **authoring convenience only** — the shipped form
is per-pixel, so a human who wants to hand-paint one character can, and the file grows a
`by_code` entry with eight rows of ASCII art instead of a pattern name. That is the precision
argument delivered literally.

Nothing new goes in `src/`, so the `Makefile`'s `ASM` list is untouched; `mk/data.mk` already
regenerates `src/data` via `make data` and gains nothing. `build.ps1` does not run the exporters,
so the workflow is unchanged and stated in §6.

---

## 5. Verification

The oracle question is the one the brief is right to press on: `dither_charset()` is currently the
byte-for-byte model of `DitherChar`, and under (b) `DitherChar` does not exist. **The replacement
is stronger, not weaker, and it is a direct comparison rather than a model of a routine.**

1. **Charset dump per deck, all 16.** The finished MODE 1 charset is at `&0400–&0C90`, exactly
   137 × 16 = 2,192 bytes, in main RAM, undisplayed. The exporter can produce the expected charset
   for a deck from data it already has (`convert_charset` + the resolved pattern map). So: boot,
   `CTRL+]` through the decks, `save_memory &0400 2192` at each, diff against Python. **Sixteen
   exact byte-for-byte comparisons of the actual artefact.** That is a better oracle than today's,
   which only ever modelled one routine and never checked the conversion.
2. **The buffer oracle** (`.claude/skills/beeb-buffer-oracle`, CTRL+R) for the *drawing* path,
   which this change does not touch — so it is a regression check, run once at the end, over odd
   and even `mapHX`, non-zero `line` and the diagonals, with all three draw call sites NOPed and
   the player at REST.
3. **`beeb-identical-build`** is *not* applicable: instructions are deliberately removed and data
   changes. Compare disc images only to confirm nothing unrelated moved.
4. **No visual regression on 16 decks**: `dither_lab.py` renders every deck before and after; the
   "as shipped" column against the new map is the review artefact, and the diff of
   `src/data/chardata.asm` is the data review.
5. **Cycles**: re-run the two breakpoints (`&A56D`, `&A693`) and quote the new `BuildCharset`
   total against today's 384,261.
6. **The lamp**: `BuildLampChar` runs on the alert; check character `$16` in the charset dump after
   an alert fires, against the same Python model.
7. **The tilemap-as-scratch claim, which option (e) rests on** — and it must be *proved*, not
   reasoned about, because it is exactly the class of thing `.claude/skills/beeb-bss-bugs` exists
   for. Two checks: (i) seed `&4600–&4A00` with `&A5`, load a deck, and confirm the map that comes
   out matches a reference load — proving `BuildLevel` really does replace all 1,024 bytes; (ii)
   set a **read** breakpoint across `&4600–&4A00` and step from `BuildCharset` entry to
   `BuildLevel` entry, confirming nothing reads it in the window. Also check the two non-`LoadDeck`
   callers of `UnpackChars` (`BuildCharPtrs` at boot and at the `GoTitle` rebuild) — they do not
   need the dither plane, but they will now write it, so confirm the map is dead there too or make
   them unpack a bitmaps-only stream. And confirm `DEBUG_MAPGUARD`'s `&3C00` snapshot is taken
   after `BuildLevel`, or the flag will report the scratch as corruption.

---

## 6. Traps, restated with what was checked

- **Staging is 696 bytes in `SPR_SAVE`, plus 1,024 more in the tilemap if §5.7 holds.**
  `SPR_SAVE` `&3E00–&45FF` less 1,096 bitmaps less 256 remap. 69 index bytes fit either way;
  1,096 plane bytes need the tilemap.
- **A 1bpp source cannot say "dither".** A set bit means the cell's ink, not logical 1, so baking
  into the plane the port already ships would paint each character's own colour into half its
  background — issue #5's ALERT bug, everywhere. The bake needs a second plane.
- **The play buffer is displayed during `BuildCharset`.** Confirmed from `src/lift.asm:41` and the
  `LoadDeck` order in `src/droid.asm:181-210`. Not scratch.
- **`dither_charset()` is already stale on this branch** — it models the pre-e9226c0 single
  checker. Whatever happens, it is currently lying.
- **`src/level.asm:419`'s "~5 ms" is wrong**; measured 51 ms.
- **`src/data/` is committed exporter output** and `build.ps1` does not run the exporters, so the
  change is: edit `dither_map.json`, run `export_bbc.py`, commit `chardata.asm` — and the diff of
  the nibble table is the review.
- **A character is a character.** The same code in two tiles gets the same pattern. If a wall's
  interior and the open deck ever need to differ *and* share a code, this scheme cannot say it —
  but they do not: the classification is by colour slot precisely because `$D8` (the enclosed area)
  carries slot 9 and the open deck carries slot 0. Worth stating as a limit, not a defect.
- **Phase across cells.** Today's checker relies on 16 being even so the phase carries across
  characters, and on 8×8 cells so it carries across the map. An 8-row pattern table preserves both
  by construction — the pattern is indexed by scanline within the cell, exactly as now.

---

## 7. Open questions for KC

1. **Is it worth doing at all?** The runtime cost is 51 ms *per deck load*, nothing in the main
   loop pays a cycle, and the bank-4 saving is about twelve bytes. The case is **precision and the
   retirement of `ALERT_IDX0`**, not performance and not space. Given #20 just landed and bank 4
   has 25 bytes on this branch, is this the right next thing?
2. **Is spending the tilemap as staging acceptable at all?** Option (e) needs it, and it makes a
   second region load-bearing at deck load in a way nothing else in the port does. The cost of
   saying no is (b): the same pixels, 20 more bytes of code, a 16-pattern ceiling, and no new
   invariant to remember. This is the real decision in this document.
3. **How much precision do you actually want?** If the answer is "quarter floor, 2×2 elsewhere, and
   I am done", then (c) — or even just merging e9226c0 with a `[DECISION]` — is the honest
   proportionate change, and the authoring tool is not worth building. §4's editor is only worth it
   if you expect to keep tuning per character.
4. **Does e9226c0's choice stand?** The plan assumes it does and encodes it as the default rule.
   It has not been agreed or measured, by its own commit message.
5. **The 7 merged-ink characters** keep their dither today because the runtime finds logical 0
   wherever it lands. Under (b) they still do. Confirm that is wanted — the alternative (dither
   only what the artwork calls floor) is now expressible for the first time, and `level.asm:398`
   records the original argument for *not* doing it.
6. **Correct the 5 ms comment now**, independently of everything else?
7. `PLAN.md` and `docs/layer-14-visual.md` DECISION 1 will both need amending; this change would
   be **layer-14 DECISION 12**. Confirm the numbering before anything is built.
