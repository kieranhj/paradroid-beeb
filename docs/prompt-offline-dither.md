# Agent brief: plan moving the tile dithering offline

Written 2026-09-12 for a FRESH agent with no context of the session that produced it. Paste
everything below the rule as the whole prompt. It asks for a PLAN, not an implementation.

---

Plan (do NOT implement) moving Paradroid's tile dithering from run time to the build, so that
which pixels are dithered and with what pattern becomes a per-pixel decision made offline by a
tool, instead of the per-character-class decision the 6502 makes at deck load.

Project: C:\Users\khcon\OneDrive\Projects\Paradroid — a BBC Micro port of the C64 Paradroid,
6502/beebasm. READ CLAUDE.md FIRST and follow it, in particular: the C64 original is the
specification; rewrites and deviations must be agreed with KC BEFORE they are built and written
down after as a numbered [DECISION] in the layer doc; do not write hardware facts from memory —
measure them in the jsbeeb MCP; verify against the play buffer, not screenshots; the two builds
(build.ps1 and the POSIX Makefile) must stay in step.

ORIGIN. hexwab, GitHub issue #5 (kieranhj/paradroid-beeb, use `gh issue view 5`): "Why on earth
are we dithering tiles at runtime? We never need to plot undithered tiles ... Preprocess the tiles
to add the dithering and remove all the dithering code. Bonus: we get much more fine-grained
control over what's dithered (and how) and what's not." KC wants the PRECISION argument taken
seriously — per-pixel, per-pattern control — rather than the code-removal argument alone.

WHAT EXISTS TODAY, and where to read it:

- docs/layer-14-visual.md — the dither is layer 14's DECISION 1; read the whole file.
- src/level.asm — BuildCharset converts the C64 bitmaps into MODE 1 at DECK LOAD (a character's
  colour depends on the deck's scheme, which is why the charset is built per deck and not shipped
  converted), and DitherChar makes half of every LOGICAL 0 pixel take logical 1 in a 2x2 checker.
  It finds the logical-0 pixels through SPR_MASKTAB and ORs only the low plane. dcMask is the
  two-byte mask pair, by scanline parity.
- src/lowcode.asm — BuildLampChar rebuilds one character DURING PLAY and must dither it to match.
- tools/export_bbc.py — convert_charset(), dither_charset() (a byte-for-byte Python oracle of
  DitherChar), deck_dithers() (the deck-level skip: only where logical 1 is physical black),
  build_logical_map(), and the chardata ZX0 stream (C64 bitmaps + a code->index remap, unpacked at
  deck load into the sprite save areas as staging by UnpackChars). charSlot ships separately,
  nibble-packed.
- tools/dither_lab.py (UNCOMMITTED, in the working tree) — a gallery tool written for issue #5: it
  renders each deck as the BBC draws it under nine dithering options and writes
  tools/output/dither_lab.html. Read its header: it documents how floor and wall are told apart
  (by the character's C64 COLOUR SLOT, not by position in the tile — slot 0/1 is the open deck and
  its grid pattern, everything else is a structure, including the area inside a wall's light/dark
  border and the dimple).
- THE WORKING TREE IS DIRTY: src/level.asm and src/lowcode.asm carry an UNCOMMITTED experiment
  (KC, 2026-09-12) that splits the runtime pass into DitherWall (2x2) and DitherFloor (quarter
  density) chosen per character from its colour slot. Decide in your plan whether it is superseded
  by going offline, folded in, or reverted — and say so explicitly. Run `git diff` before you start.

THE CENTRAL PROBLEM, which your plan must solve rather than skate over:

The charset is built per deck because a character's COLOUR comes from the deck's scheme, and
whether a given pixel ends up logical 0 (the dither's only target) therefore varies by deck — a
character's ink can merge onto logical 0 on one deck and not another. So "pre-dither the tiles"
cannot simply mean shipping pre-rendered charsets: that would need one converted charset per deck
(137 chars x 16 bytes = 2,192 bytes each, 16 decks) and there is nowhere near that much room.

Cost at least these shapes, with real numbers:

  (a) export a per-character 16-byte dither MASK carried inside the existing chardata ZX0 stream,
      unpacked into the same staging, and ANDed at deck load with the runtime's logical-0 mask —
      offline precision, runtime keeps one cheap AND/ORA per byte;
  (b) the same but compressed (per-character pattern id plus a small pattern table; or per-pixel
      2-bit pattern selection);
  (c) keep the runtime pass but drive its mask pair from exported per-character data (the cheapest
      change, least precision);
  (d) pre-dither offline only where the answer is deck-INDEPENDENT, leaving the rest at runtime.

For each: bytes (and IN WHICH REGION — take live figures from the build's gauges, not from any
document), deck-load cycles, what it removes from the 6502, and what precision it buys.

CONSTRAINTS AND TRAPS to check and state:

- RAM is the binding constraint. Read the build's own gauges. At the time of writing: bank 4 has
  25 bytes free WITH the uncommitted experiment (64 without), bank 6 255, bank 7 84 plus a 29-byte
  ALIGN pad, main RAM 39. The ALIGN pads in bank 4 (colourMap) and bank 7 (plandata) are
  load-bearing — CLAUDE.md explains.
- The dither currently has TWO documented exceptions that any new scheme must still express: the
  deck-level skip (logical 1 not black), and the ALERT lettering (ALERT_IDX0 in level.asm, guarded
  by ASSERT NUM_CHARS = 137, issue #5's original bug — the letters dissolved into their own
  background). Offline data could express both as data; say how.
- BuildLampChar rebuilds a character mid-play. If the dither data lives in staging that has been
  reused by then, that path breaks. Check what SPR_SAVE holds during play before assuming.
- src/data/ is committed exporter output: the build does NOT run the exporters, so a data format
  change means running the tool and committing its output, and the diff is the review.
- export_bbc.py's dither_charset() is currently the byte-for-byte oracle for the 6502's
  DitherChar. If the runtime pass changes or disappears, say what replaces that oracle.
- Adding a src/ file means adding it to ASM in the Makefile; a pipeline change lands in both builds.

ALSO PLAN THE DESIGN LOOP, because precision is the point: how does a human choose the pattern per
character (or per pixel), and how does that choice reach src/data? dither_lab.py currently picks
from nine whole-deck options. Consider extending it (or a sibling tool) into the authoring tool —
per-character or per-region painting, a preview rendered exactly as the game draws it, and a
committed data file the exporter reads, in the way tools/deck_palettes.json already feeds
export_bbc.py from tools/palette_lab.py. Read those two for the established pattern.

DELIVERABLE: a written plan, no source changes and no commits. Include:

  1. what the port does today, precisely, with file:line;
  2. the options above, each with measured byte/cycle costs and what it buys;
  3. a recommendation, and what you would NOT do;
  4. the exceptions and traps, and how the chosen shape expresses them;
  5. the authoring-tool half: format, where it lives, how it is regenerated and reviewed;
  6. a verification strategy — what proves the converted charset is right (the existing Python
     oracle, the CTRL+R buffer diff per .claude/skills/beeb-buffer-oracle, a deck-by-deck render
     comparison), and what would prove no visual regression on all 16 decks;
  7. the open questions for KC, listed separately — including whether this is worth doing at all,
     given the runtime cost today is ~5 ms per deck load and nothing in the main loop pays for it.

Write the plan to docs/ as a new file (do not edit the existing layer docs) and print a summary.
