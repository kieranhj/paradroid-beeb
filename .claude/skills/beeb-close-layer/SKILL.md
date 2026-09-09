---
name: beeb-close-layer
description: Close out a layer of a BBC Micro port - the layer doc with what was measured and rejected, a numbered [DECISION] entry per deviation, PLAN.md and BUGS.md updated, the memory gauge read from the build into memory-map.md with the date, every debug flag combination assembling, the smoke test passing, and a commit with the measurement in its body. Use when a layer is working in the emulator and the user says it is done, or before starting the next layer.
---

# Close a layer

A layer is done when it is visible in the emulator *and* its doc, decision rows and plan update
are written. What is sacred in both ports is finishing a layer, with its doc, before the next
starts; the rejected options in the doc are the valuable half, because they are what stops the
next session re-litigating them.

**Layer doc:** `docs/layer-N-<name>.md`, linked from `PLAN.md`
**Decisions:** the numbered **[DECISION]** list in the layer's own doc is this project's pattern
(`docs/layer-9-hud.md`, `docs/layer-10-transfer.md`); `docs/decisions.md` carries the
cross-cutting ones and the evidence for which Paradroid the listing is
**Memory figures:** from the build's own `PRINT` lines and bank gauges, never from an earlier doc -
`CLAUDE.md`'s table is dated for exactly that reason and goes stale within a build
**Commit body:** the measurement ("0 of 16,384, both banks", "6,155 cycles a sprite", "byte-identical")

## Steps

1. **Write the layer doc** with what was measured (the numbers, the method by procedure name,
   the emulator, the date) and what was tried and rejected, with why. "Do not re-litigate the
   blitter unrolls" saved Paradroid's RAM pass from repeating itself. A doc that records only
   the winning design will be argued with.

2. **A numbered [DECISION] entry for every deviation from the original and every choice the
   hardware forced**, dated, with the reason - in the layer's doc, numbered on from its last
   one. **Rewrites and deviations are agreed with KC BEFORE they are built and written down
   after**; that includes anything the original does not have, anything it has that the port
   drops, and any place the port's geometry forces a different arrangement. If the layer
   reversed an earlier decision by measurement, that is a *new* entry saying so, not an edit to
   the old one.

3. **Update `PLAN.md`**: tick the layer's row, move the detail that no longer drives the next
   decision into the layer doc, and rewrite "where we are" and "what is left". It is the live
   planning document and it stays short - it went from 535 lines to 156 by moving detail out.

4. **Update `BUGS.md`**: mark what the layer fixed (with the layer name; fixed entries stay for
   what they ruled out), add anything found and not fixed with its evidence. A path the layer
   made reachable for the first time (`wave_manager`'s skip path, Edge `BUGS.md` #10) is a
   candidate for a new entry, not a note.

5. **Read the memory gauge from the build into `docs/memory-map.md` and `CLAUDE.md`, with the
   date.** The `PRINT "code"` line and the four bank gauges the build emits are the figures.

   ```powershell
   .\build.ps1
   Select-String -Path build\paradroid.lst -Pattern "code|bank|free" | Select-Object -Last 20
   ```

   Every free-space figure carries the date it was measured, because they move every build.
   Two standing rules when quoting one: **anything assembled before bank 4's `colourMap` ALIGN
   or bank 7's `plandata.asm` ALIGN rides in that pad for nothing**, and **spending one byte
   past a pad costs 256 at a stroke** - so quote a bank's pad and tail as a pair, never the tail
   alone.

6. **Every flag combination still assembles.** The project's `-D` symbols are in `CLAUDE.md`
   "Build"; loop over all of them. A combination nobody has built since the layer began is a
   build that may not exist any more (`GFX_CPC=1` did not assemble without `MUSIC_AKL=1` for
   two layers of Edge Grinder).

   ```bash
   for R in 0 1; do
     printf "RELEASE=%s | " $R
     ./bin/beebasm.exe -i src/main.asm -do build/flagtest.ssd -D RELEASE=$R 2>&1 | tail -1
   done
   ```

   `RELEASE` is the only command-line symbol; the `DEBUG_` flags are constants at the top of
   `main.asm`, so a flag sweep means editing them one at a time. **Some debug builds still fail
   to assemble** - from the RAM squeeze, not the flag - so a failure there is expected, not a
   bug to chase: `XFERWIN`, `DECK`, `KILL` and `REDRAW` are the four that ship on and build.
   Adding a flag means adding it to `DEBUG_ANY` and to the `!BOOT` stamp block as well as
   defining it, or a build can lie about itself; `RELEASE` asserts `DEBUG_ANY = 0`.

7. **The smoke test passes on the release build too** (`.\build.ps1 -Release`, which also
   builds the intro, then `beeb-smoke-test`). A DEV-only feature the release build silently
   lacks is found here or by a playtester - and RELEASE is the build other people get, so bump
   `VERSION_LINE` per candidate.

8. **Update `CLAUDE.md`** if the layer measured a new hardware fact (into "Confirmed hardware
   facts (measured, not assumed)", with the readback), changed the build, or moved a region. A
   rules file that is wrong is fixed the same day.

9. **Commit, one mechanism per commit, with the measurement in the body.** Doc-sync commits
   are separate and frequent. Confirm with the user before committing unless they already asked.

   ```
   Layer N: <what it does>

   <the measurement: "0 of 16,384 both banks at odd and even scroll phase",
    "50/100 scrolling", "byte-identical: Edge, BANK0", cycles before and after>
   ```

10. **Then, and only then, start the next layer** - and start it by reading what the C64
    original does: the routine in `paradroid_ce_annotated.asm`, the table it reads, the layout
    it produces. The original is the specification; a transliterated routine is faithful by
    construction and an "equivalent" one is faithful until the first thing it gets subtly wrong.
