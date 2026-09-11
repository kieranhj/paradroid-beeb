---
name: beeb-buffer-oracle
description: Diff the BBC Micro port's play buffer byte for byte against an independent redraw of what it should contain, at the awkward scroll positions - odd and even mapHX, non-zero line, the diagonals, using jsbeeb MCP breakpoints and memory dumps. Use when a scroll, tile writer or sprite change needs proving, when a commit wants its "0 of N" figure, or when a screenshot looks fine and that is not good enough.
---

# The buffer oracle

The strongest check either port has. An **oracle** is an independent rendering of what the play
buffer should contain; the check is a byte-for-byte diff against what the game actually drew.
Paradroid's is `RedrawAll` on a debug key and nearly every commit from Layer 3 on ends
"0 of 10,240". Edge Grinder never built its redraw oracle and its layer docs say so from Layer 3
to Layer 5. **Build yours in Layer 3, before the scroll is trusted.**

**Pass mark:** 0 bytes different
**Settle time:** ~1,500,000 cycles before freezing, so no scroll is in flight
**NOP:** `&EA` = 234; a `JSR` site is three of them

## This project's parameters

| Parameter | Paradroid |
|---|---|
| Oracle | `RedrawAll` on **CTRL+R**, which needs `DEBUG_REDRAW` - on in every dev build, off in RELEASE (plain R until 2026-08-31, SPACE before 2026-08-26) |
| Buffer | `&5800`, **10,240 bytes** (16 rows x 640), the circular strip under the 10K hardware wrap |
| Draw sites - **all three** | `JSR SprDrawTr` (`src/main.asm:1931`), `JSR SprDrawAll` (`:1934`), the second `JSR SprDrawTr` (`:2149`) - line numbers as of 2026-09-11; take the run-time addresses from `build/paradroid.lst` |
| Banks | One. No shadow RAM on a Model B, so step 6's ACCCON half does not apply |
| Positions to vary | odd and even `mapHX`, non-zero `line`, and the diagonals - every scrolling bug so far has hidden in one of those |
| Addresses | the symbol dump, every build: `./bin/beebasm.exe -i src/main.asm -do build/symbols.ssd -D RELEASE=0 -d \| tr ',' '\n' \| grep "'RedrawAll'"` |
| Legitimate diffs | doors animating under droids. `docs/ram-pass.md` section "The oracle recipe changed" is the full checklist |

## Steps

1. **Drive the view to an awkward position and let it settle.** Every scrolling bug so far
   hid in an odd `mapHX`, a non-zero scanline offset or a diagonal. Poke the position rather
   than hold keys, then `run_for_cycles session_id, cycles: 1500000`.

2. **Freeze with the player at rest.** Restores replay every pass while draws are off, so a
   freeze taken mid-deceleration stamps stale tiles into a scrolled buffer on every later pass.

3. **Disable every writer.** Poke **all three** draw sites to NOPs - the `JSR SprDrawAll` and
   **both** `JSR SprDrawTr`s. NOPing only the first was enough until the tranche split; after it
   the split path kept drawing and the diff showed a player-shaped block of false corruption. Let a pass or two run so the restores take
   every sprite off the buffer. If the scene cannot be made quiet (a door animating, an enemy
   spawning), NOP the update call too.

   ```
   write_memory  session_id, address: <JSR site 1>, bytes: [234, 234, 234]
   write_memory  session_id, address: <JSR site 2>, bytes: [234, 234, 234]
   write_memory  session_id, address: <JSR site 3>, bytes: [234, 234, 234]
   run_frames    session_id, count: 4
   ```

4. **Take both dumps inside ONE pass.** Break on the redraw `JSR` itself, dump (A); clear that
   breakpoint, break on the instruction after it, run, dump (B). The redraw can take over
   500,000 cycles, so if the run did not reach the second breakpoint run again rather than
   concluding it was missed. The trap in the obvious method - dump, press the key, run 800,000
   cycles, dump - is twenty passes, and anything that animates in between is a diff with nothing
   to do with the change under test: it reported 35 and 196 wrong bytes on two correct builds.

   ```
   key_down          session_id, key: "CTRL"      key_down session_id, key: "R"
   set_breakpoint    session_id, address: <JSR redraw>
   run_for_cycles    session_id, cycles: 200000
   save_memory       session_id, address: <base>, length: <size>, path: "<scratchpad>/a.bin"
   clear_breakpoint  session_id, id: <that id>
   set_breakpoint    session_id, address: <JSR redraw + 3>
   run_for_cycles    session_id, cycles: 600000
   save_memory       session_id, address: <base>, length: <size>, path: "<scratchpad>/b.bin"
   key_up            session_id, key: "R"         key_up session_id, key: "CTRL"
   ```

   With an **off-machine** oracle, B is the renderer's output for the scroll position read from
   the game's own variables at the moment of dump A. **Read the variables the hardware was given,
   not the ones the game has got to**: a frame-locked port parks the next scroll position in the
   main loop and the VSync hook takes it fields later, so `scroll`/`line` run up to a game tick
   ahead of `crtc_live`/`line_live`, which are what is on the screen. 1942 scored 57,284 of 57,344
   pixels wrong on a correct build by feeding the parked pair (2026-09-07, jsbeeb 1.25.0, Master).
   The same goes for any other state the hook latches at VSync: bank parity, palette, display wrap.

5. **Diff, and report "N of <size>".** `cmp -l a.bin b.bin | wc -l`, or three lines of Python
   printing offsets. Anything sprite-shaped: resume draws, let the overlap heal, re-freeze
   somewhere quiet. Anything column-shaped is the scroll.

6. **Repeat at every parity.** There is no second display bank here, so the sweep is odd and
   even `mapHX`, `line` zero and non-zero, and the diagonals. One position passing means nothing.

   (Kit note, for a Master: `save_memory` reads through the machine's own memory map, so the
   other display bank wants ACCCON's X bit - `&FE34` bit 2 - flipped from the guest first. Since
   jsbeeb-mcp 3.4.0 `read_memory` and `save_memory` also take `bank:` / `shadow:` directly and
   put the map back afterwards, which is the better route.)

   Where the check renders a *view* rather than a buffer, count the lit scanlines in the
   framebuffer as well: one unbroken run of the expected height, nothing else lit. It is one extra
   pass and it catches frame-shape errors a play-area diff cannot see - if a CRTC cycle stops
   displaying where it should not, the run is short, and in a scanline scroll the shortfall moves
   with the scroll (1942: `224x272, one run`, 2026-09-08).

7. **Record the figure in the commit body and the layer doc** with the positions tested. "0 of
   16,384, both banks, scroll phase odd and even" is the shape.
