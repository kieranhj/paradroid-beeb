# Layer 11f handover — 2026-08-22

Written at the end of a long session. **Read `docs/layer-11f-frontend.md` first** — it is the
plan, and §4a/§4b/§4c are what was built and what was learned. This file is the state and the
next step only.

## What is in the build and working

| | |
|---|---|
| **`SetupPlain`** (`src/screen.asm`, bank 4) | Replaces `SetupMode` on the `GoTitle` path. Six CRTC registers instead of a `VDU 22` — so the OS no longer clears `&3000`–`&7FFF` and **the play buffer and the font survive a mode change**. This is the change everything else rests on |
| **`TiPal`** (`src/title.asm`) | The title now sets its own palette, because nothing resets the ULA any more. The values are the OS's MODE 1 default, which is what [DECISION 9] had been relying on `VDU 22` to supply |
| **F1 — `DoHighScore`** | In the `PARTITL` overlay, with its alphabet from `tools/export_hsfont.py` and its 25-byte table in bank 7 (`src/hstable.asm`). Verified end to end in jsbeeb: both arms, the K/M walk, three initials committed, table written, `hsArmed` cleared, on to the title |
| **F3 — the briefing text** | `tools/export_briefing.py` → `src/data/briefing.asm`. 112 records, five pages, 4,399 B. **Not included by any build yet** — F4 is what includes it |

Free space after all of it: main RAM **2 B** (`code_end` `&2FFE`), bank 4 **26 B**, bank 5 1,033 B,
bank 6 53 B, bank 7 314 B, `PARTITL` **112 B** (its ceiling is `FONTCODE_ADDR`, not `TI_BASE`, so
that `FontCell` survives the overlay — there is an `ASSERT`).

## Two things that cost a lot to learn

1. **`font_end` is not the end of that region.** `PARAFNT` ends at `&3D98`, `PN_TABS`' 96 bytes
   follow it and `SPR_SAVE` is at `&3E00` — so the gap is **8 free bytes, not 104**. Putting data
   there silently collides with the mirrored droid tables. `BUGS.md` #18 is the whole story; it
   presented as a hang two game-overs later and took a write watch to find.
2. **R8 is not optional in a CRTC teardown.** The rupture blanks rows with it. Leave it set and
   you get a black screen with every other register perfectly correct.

## The next step: F4

**The goal:** `PARMAN` in bank 5, a row painter, and one static briefing page on the strip. No
scrolling yet — that is F5.

**The blocker is solved but unverified.** [DECISION 4] (evict bank 5 for the briefing, reload
`PARASPR` on the way into the game) stands. What stalled it was that *entering* the briefing needs
main-RAM bytes that do not exist. KC's answer, and §4c has the reasoning:

> **`&0400`–`&0C90` — the MODE 1 charset — is 2,192 bytes of free lower RAM outside a game.**
> It is built at deck load and `GameStart` → `LoadDeck` rebuilds it, so at title and briefing time
> it holds nothing anyone wants. Nothing in the front end reads it: the title carries its own
> glyphs and the briefing uses `PARAFNT`'s text font.

So the briefing's **driver** lives at `&0400` — not merely a shim — and bank 5 holds only the
4,399 bytes of text. Ideally the driver is a disc file with a catalogue load address of `&0400`,
so `*LOAD` puts it where it runs.

**Verify this before building on it.** DFS's workspace is `&0E00`–`&10FF` and the cassette/serial
buffers are `&0900`–`&0BFF`; the port owns `&0400`–`&0C90` during a game, but a `*LOAD` *into* it
while DFS is running has never been tried. `PARALOW` has to be staged rather than loaded for
exactly this class of reason. Load something there, read it back, and only then build on it.

## Follow-on prompt

> Continue Layer 11f of the Paradroid BBC port at F4. Read `docs/layer-11f-frontend.md` (especially
> §4a–§4c), `docs/HANDOVER-11f.md`, and `BUGS.md` #18 before touching anything.
>
> F4 is: `PARMAN` in bank 5 carrying `src/data/briefing.asm`, a row painter, and one static
> briefing page drawn on the strip. No scrolling — that is F5.
>
> **Start by verifying the premise**, because it is unverified and everything rests on it: that a
> `*LOAD` can put a file at `&0400`–`&0C90` (the MODE 1 charset area, dead outside a game) and have
> it arrive intact while DFS is running. If it cannot, the driver has to be staged and copied the
> way `PARALOW` is, and the shim comes out of `PARTITL`'s 112 spare bytes instead.
>
> Then: the driver at `&0400`, the text in bank 5 (evicted — `PARASPR` is reloaded on the way into
> the game), and `TitleSeq` entering it with a `JSR` when `TiWait` times out rather than fires.
> The painter draws canvas row *r* from that row's record list top-half and row *r−1*'s
> bottom-half — `briefing.asm`'s index is by canvas row because the C64's lines are NOT evenly
> spaced. Glyph indices `>= BR_COMMA` are plotted from `brExtra`, not the font. Use main RAM's
> `FontCell` for the 1bpp → MODE 1 expansion; do not write a second one.
>
> Standing rules that bit this session: measure free space from the build's own `PRINT`s rather
> than from any document; `font_end + 96` is `PN_TABS`; verify CRTC work in jsbeeb rather than
> reasoning about it; and when a screen misbehaves two game-overs later, suspect a stray write and
> use a write breakpoint rather than reading code.
