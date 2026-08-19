# Layer 14 — The visual pass

**Status: planned, not started, and deliberately last.** `PLAN.md` carries the summary.


Asked for by KC, 2026-08-16. Everything is drawn by now and has been seen on real hardware; this is
the pass that settles how it **looks**, as one deliberate sitting. Two strands:

1. **The final palettes, for every deck and every game screen.** MODE 1 gives four colours against
   the C64's sixteen, so a deck's palette here is a choice, not a transcription. This pass sets all
   sixteen decks together, plus the panel, the console, the transfer board and the title, so they
   read as one game. The original's own per-deck colours are the starting point, not the answer.
   **Include the deck plan page (KC, 2026-08-17)**: re-judge `planInk` (built by `export_bbc.py`
   with two legibility overrides) and layer-9 §6e decision 1 alongside the deck palettes.

   **The four logical colours now carry fixed roles** (KC, 2026-08-17): 0 = the deck's background,
   1 = black, 2 = the deck's highlight, 3 = white. Chosen for the sprites — logical 3 is `%11`, so
   a sprite byte is its own mask and `AND &0F` / `AND &F0` recolour it to black or the highlight
   in place. Allocation runs in priority order 3, 1, 0, 2, which puts white on all 16 decks and
   black on all 16. Anything drawing on the deck's palette must follow the roles; the console
   already had to be moved. See [`docs/layer-1-graphics-pipeline.md`](docs/layer-1-graphics-pipeline.md).

   **The tool for it is `tools/palette_lab.py`** (2026-08-17): every deck rendered in the C64's own
   colours beside the port's MODE 1 render, with both the palette and the colour *merge* editable
   live, and a 320 × 120 window showing what actually fits on screen. It writes
   `tools/deck_palettes.json`, which `export_bbc.py` reads as an override when it regenerates
   `colours.asm` — so a decision made by eye lands in the build without hand-editing generated
   data. Verified: its BBC render is byte-identical to `convert_charset` (what `BuildCharset`
   reproduces) over all 2,192 characters of all 16 decks.
2. **Redrawing graphics characters that fight the palette.** Where a tile or glyph only works
   because of a colour MODE 1 cannot give it, the honest fix is to change the artwork — a
   **deviation from the original's graphics, agreed case by case** under the usual rule.

**Why last:** judging a palette wants the finished screens and a real display — 13c is what puts
the build in front of one. **Exit condition:** every deck and screen has a palette recorded in the
source with a comment saying why, and every redrawn character has a decision entry.
