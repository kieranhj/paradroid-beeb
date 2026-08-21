# Layer 2 — Static deck render ✅ DONE

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

`BuildLevel` RLE-decodes a deck into a tile map; `DrawScreen` renders the viewport from it.

> **Superseded in one respect, 2026-08-20 (Layer 13d):** the RLE and its decoder are gone. The
> maps now ship ZX0-compressed (decoded offline by `export_bbc.py`, byte-identical) and
> `BuildLevel` is pointer setup in front of `Zx0Unpack`. Everything below about the RLE is the
> historical record; the tile map it produces is unchanged. See
> [`layer-13d-space.md`](layer-13d-space.md) §3.

**Divergence from the C64 — the map buffer.** The original expands every tile into a 256×64
*character* map at `$8000` (16K) and `DrawScreen` just copies characters from it to screen RAM.
We keep only the **64×16 tile map (1K)** and expand tiles to characters at draw time:

```
tile      = tilemap[(cy>>2)*64 + (cx>>2)]
character = tiledefs[tile*16 + (cy AND 3)*4 + (cx AND 3)]
```

Two extra lookups per character against a ~100-cycle 16-byte copy — roughly 25% more work when
drawing, for a **15K saving**. Not a close call on a Model B. Scrolling only redraws the leading
edge, so the overhead lands on a column of 25 characters, not the full screen.

**Memory layout — code and data must be split across two disc files.** `VDU 22` makes the OS clear
what it still believes is its screen, `&3000–&7FFF`. Anything loaded above `&3000` is wiped before
it can be read. So:

| File | Contents |
|---|---|
| `PARA` | code, plus reserved space for the tile map and charset built at runtime |
| `PARADAT` | C64 char data, colour schemes, tile defs, deck RLE — `*LOAD`ed *after* the mode change |

Current addresses are in the memory budget above; they move as the code grows, so read them from
the `beebasm` output rather than from here.

This bites again at every later layer that adds data. The eventual fix is to stop using `VDU 22`
and program the video ULA and CRTC directly, which we need anyway to keep the OS from clearing or
scrolling our screen. Note `*LOAD` must also happen **before** `InstallIrq` — taking over IRQ1V
stops the MOS servicing the filing system.

**Verified:** `verify_bbc.py --tilemap <dump> <deck>` diffs a tile map dumped from the emulator
against a fresh Python RLE decode. Deck 1 (226 non-empty tiles) and deck 3 (498) both match all
1024 bytes, and both counts agree with `level_stats.txt`. Deck 3 was chosen deliberately — its RLE
lives at `&3393`, above `&3000`, so it exercises the clear-on-mode-change bug above.

*Note:* deck 1 masked that bug entirely. Its RLE sits at `&2DC0`, below `&3000`, so it rendered
identically before and after the fix. Screenshot comparison alone would not have caught it.
