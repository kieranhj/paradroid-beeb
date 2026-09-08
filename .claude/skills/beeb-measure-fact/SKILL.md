---
name: beeb-measure-fact
description: Measure a BBC Micro hardware fact - a register, a paging bit, a display wrap size, an emulator capability - by probing it in the jsbeeb MCP from BASIC or from poked machine code, and record the readback verbatim in the layer doc and decisions.md. Use when about to write code that depends on how a register or bit behaves, when a doc says "measured" without numbers, or when anyone claims something cannot be measured.
---

# Measuring a hardware fact by probe

**Do not write hardware code from recalled facts.** Set the register, read the effect back,
record the readback verbatim, then build on it. The deleted `src/hal_video.asm` is what happens
otherwise - unverified CRTC arithmetic with `TODO: verify in emulator` comments that survived in
the tree for months looking like working code. A fact that cannot say which probe produced it is
a recollection.

**Check `CLAUDE.md`'s "Confirmed hardware facts" list first**, and the kit's
`docs/hardware-facts.md` (`C:\Users\khcon\OneDrive\BEEB\Repos\beeb-port-kit`) - most of what
this port needs is already measured, with the readback. Re-measure only what is not there, or a
number that has no measurement behind it.

**Probe first with:** BASIC, if the thing under test leaves BASIC standing
**Probe with machine code when:** the thing under test is the ROM BASIC lives in (`&8000-&BFFF`), or needs cycle-exact timing
**Record:** the prediction, the pokes, the readback, the emulator, the date

## Steps

1. **Write the claim down as a prediction before touching anything.** "With line 4 low and
   line 5 high the display wraps to `&3000`." "Bit 7 of ROMSEL overlays 4K at `&8000`." A probe
   without a prediction confirms whatever it finds.

2. **Boot a `B-DFS1.2` machine** - the target is a Model B / B+ with four sideways RAM banks.
   The MOS and the memory map differ between models, and a fact measured on a Master is a fact
   about a different machine (which is a Layer 13 compatibility question, not this one).
   `run_until_prompt` to the BASIC prompt.

3. **BASIC route.** Fastest way to poke a register and print a byte. Edge Grinder's four
   display-wrap sizes and the NuLA grey (`?&FE23=&78:?&FE23=&88`) were measured this way.

   ```
   type_input        session_id, text: "?&FE40=4:?&FE40=13"
   type_input        session_id, text: "PRINT ~?&3000"
   run_until_prompt  session_id                       # the printed text comes back
   ```

   `type_input` sends RETURN for you. For a register that changes what is *displayed*, poke a
   pattern and `screenshot`, measuring distances between marks rather than absolute position
   (the MCP screenshot crops to the active area; `active_only: false` for the raw field).

4. **Machine-code route, when BASIC would be paged out from under itself.** ANDY overlays
   `&8000` and BASIC *is* the ROM at `&8000`: paging ANDY in from a BASIC statement removes the
   interpreter mid-statement and hangs. Poke a few bytes of 6502 into main RAM, have it leave
   its results in RAM, and CALL it. Edge Grinder's ANDY probe, and its whole readback:

   ```
   &FE30 = 4     write &AA to &8000, &BB to &9000
   &FE30 = &84   write &55 to &8000, &CC to &9000
   &FE30 = &84   &8000 reads &55    &9000 reads &CC
   &FE30 = 4     &8000 reads &AA    &9000 reads &CC
   ```

   ```
   write_memory   session_id, address: 0x0A00, bytes: [<the probe>]
   disassemble    session_id, address: 0x0A00, count: 20      # read it back as code first
   type_input     session_id, text: "CALL &A00"
   run_until_prompt session_id
   read_memory    session_id, address: 0x0A80, length: 4      # the probe's own results
   ```

   Read the disassembly back before running: a hand-assembled byte wrong by one has mimicked a
   hang and cost two sessions (`beeb-cycle-timing`, step 6).

5. **Vary the input and probe again.** One reading confirms one setting. The four wrap sizes
   came from all four latch combinations; ANDY's 4K window from a second address the overlay
   did *not* cover. The negative case is half the fact.

6. **Record the readback verbatim**, with the date and the emulator, in the layer doc
   (`docs/layer-N-*.md`), and as a numbered [DECISION] there if it changes a decision. Add the
   one-line form to `CLAUDE.md`'s "Confirmed hardware facts (measured, not assumed)" list.
   "Measured" without the numbers cannot be re-checked - and several of that list's entries
   ("this cost a build", "R5's legal window is the whole cycle") are there because the first
   version was a recollection.

7. **"I cannot measure this" is itself a claim, and it wants testing.** Edge Grinder's decision
   63 shipped an unverified assumption about NuLA indexing because it believed jsbeeb had no NuLA
   to test against. It did (decision 67, measured three ways on 2026-09-05), and the bug reached
   real hardware first. Before writing "untestable", try the probe.

8. **Then, because emulators disagree, `beeb-cross-emulator`** for anything that switches the
   display bank, changes CRTC shape mid-frame or displays memory the MOS would not - which here
   means anything touching the rupture. jsbeeb reported healthy field lengths throughout the
   handover fault that b2 showed at once.
