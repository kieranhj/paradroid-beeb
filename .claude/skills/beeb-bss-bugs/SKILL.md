---
name: beeb-bss-bugs
description: Reproduce a BBC Micro port bug caused by uninitialised RAM - reclaimed OS workspace, SKIPped BSS, a flag assumed clear - by seeding memory with a known byte in the jsbeeb MCP and soft-resetting into the game, since jsbeeb powers up with RAM zeroed and hides such bugs. Also proves a region free. Use when a bug is reported as "first boot only", "intermittent" or "only on real hardware", or when claiming the game never writes a region.
---

# Reproducing uninitialised-RAM bugs

**jsbeeb powers up with all RAM zeroed**, so a byte read before it is written is always 0 there
and the bug shows only on real hardware, as "first boot only" or "intermittent". Paradroid's
white-briefing bug (`disrFlash` in `lowbss`, confirmed 2026-08-28) is the model case. The fix
for the emulator's kindness is to seed the RAM yourself.

**Seed:** `&A5` = 165 - neither 0 nor `&FF`, unlikely to occur by accident, and visible in a dump
**Reset that keeps the seed:** a **soft** reset (`hard: false`). A hard reset zeroes RAM again
**Autoboot:** `reset autoboot: true` holds SHIFT for you

## Steps

1. **Suspect uninitialised state first** when the symptom is reported that way. This port took
   a lot of OS workspace, so the candidate list is long: every `SKIP` block, `lowbss` and the
   whole low overlay at `&0C90-&10FF` (DFS/OS workspace), the MODE 1 charset ground at
   `&0400-&0C90`, the code image starting at `&1100` below DFS's `PAGE`, the stack page's free
   `&0100-&017F`, and every flag that is only ever *cleared* by an event.
   `docs/memory-map.md` and `CLAUDE.md`'s memory budget say what sits where.

2. **Hard reset to the BASIC prompt** on the target model, so the machine is in the state a
   real one is in after power-on, minus the garbage.

   ```
   reset             session_id, hard: true
   run_until_prompt  session_id
   ```

3. **Seed the suspect byte, or the whole suspect region.** Write the seed over everything the
   game will later assume; a whole page at a time is fine. `write_memory` takes at most what
   fits in one call comfortably - a few hundred bytes - so seed a large region in chunks.

   ```
   write_memory   session_id, address: <suspect>, bytes: [165, 165, ... ]
   ```

4. **Soft reset with SHIFT held.** A soft reset does not clear RAM, so the seed survives into the
   game exactly as a real machine's leftovers would. The disc must already be in the drive
   (`load_disc` beforehand if this is a fresh machine).

   ```
   reset          session_id, hard: false, autoboot: true
   run_frames     session_id, count: 400
   ```

   `boot_disc` is a hard boot and would zero the seed - do not use it here.

5. **Play to the symptom.** If it reproduces, `read_memory` the suspect and confirm the seed is
   what the code read; the fix is an explicit initialisation at boot (or at the state
   transition the flag belongs to), and a `BUGS.md` entry naming the byte and the seed run.

6. **The same recipe proves a region *free*.** Seed it, play through every path that could
   touch it, `read_memory` it back: every byte still `&A5` says nothing wrote there. The
   stack-page measurement is exactly this - `&0100-&017F` seeded on 2026-08-31 and still `&A5`
   after play, a deck load, the console and its pages and a whole game over including
   `GoTitle`'s `*LOAD`s, which is the deepest path there is because the MOS and DFS are heavy
   stack users. (Those loads are gone since no-load step 5, 2026-09-09 - nothing loads after
   boot now - so the measurement describes a deeper path than today's game over.) **List the paths that were NOT exercised**: that measurement did not cover the
   transfer game, the lift or the briefing, `docs/ram-pass.md` says so, and anything that
   deepens the call graph invalidates it. A free-space claim without that list is incomplete.

   ```
   write_memory   session_id, address: 0x0100, bytes: [165 x 128]
   # ... play, through every path ...
   read_memory    session_id, address: 0x0100, length: 128
   ```

7. **Record** the seed, the reset sequence, what reproduced and what did not, in `BUGS.md`
   (fixed entries stay: they record what was ruled out) and the layer doc.
