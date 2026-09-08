---
name: beeb-frame-drops
description: Measure whether the BBC Micro port is holding its frame rate by counting loop passes against fields over exactly 100 fields in the jsbeeb MCP, in each scenario that loads the game. Use when the user asks whether the game is dropping frames, whether a change slowed it down, or when a scroll "looks" smooth or juddery in an emulator.
---

# Frame-lock and drop check by counting

Whether the game is holding its rate, *measured*. "It looks smooth" is not evidence: the emulator
runs at the host's ~60 Hz, not the Beeb's 50, so a 5:6 judder is baked in before the code gets a
say. Paradroid sent a session chasing a regression that counting showed was a 31 % improvement.

**Sample:** exactly **100 fields** = **3,993,600** cycles (39,936 a field, interlace off)
**Counters:** `gameTick` (loop passes) and `fieldCount` (zero page `&21`, bumped by the IRQ)
**Expected:** `fieldCount` +100, `gameTick` **+50** - `FRAME_LOCK` is 2, so the game is 25 Hz
**Fewer passes than that:** dropped frames. More fields than 100: the IRQ is not healthy

## Steps

1. **Take both addresses from the symbol dump, never from an old note** - main-RAM addresses
   move every build:

   ```bash
   ./bin/beebasm.exe -i src/main.asm -do build/symbols.ssd -D RELEASE=0 -d | tr ',' '\n' | grep -E "'(gameTick|fieldCount)'"
   ```

   Both are zero page here, so the bank trap does not bite. It would if a counter lived above
   `&8000`: `read_memory` returns whichever bank is paged *at that instant* unless you pass
   `bank:`, and `SprDrawAll` pages banks mid-pass.

   **`FRAME_LOCK` is a floor, not a fixed pass length.** A pass that overruns two fields carries
   on rather than waiting out another field, so an overrun costs itself and not a whole extra
   field - which is exactly what this count is measuring.

2. **Boot into the scenario under test** (`beeb-smoke-test`, then play or poke to the state).
   Do not measure straight after heavy single-stepping: a 62-in-100 transient seen once after
   a debugger session and never again is recorded in Paradroid's audit as "flagged, not
   concluded". Measurements with the debugger in the loop can perturb the thing measured.

3. **Read, run 100 fields, read.**

   ```
   read_memory     session_id, address: <pass counter>,  length: 1
   read_memory     session_id, address: <field counter>, length: 1
   run_for_cycles  session_id, cycles: 3993600
   read_memory     session_id, address: <pass counter>,  length: 1
   read_memory     session_id, address: <field counter>, length: 1
   ```

   The counters are single bytes and wrap; subtract modulo 256. Use `run_for_cycles` here, not
   `run_frames`: the question is what the game did in a fixed span of real time.

4. **Read the result.** `fieldCount` +100 says the interrupt is healthy under load;
   `gameTick` +50 says no pass overran. The recorded table is 50/100 stationary, 50/100
   scrolling, 50/100 on a nine-droid deck; `docs/raster-timing.md` holds the budget the pass
   has to fit into.

5. **Repeat in every scenario that loads the game**: stationary, scrolling, a busy deck,
   firing, a door opening under a droid, the death sequence. Record a row per scenario. One
   scenario passing says nothing about the others.

6. **`DEBUG_TIME` and `DEBUG_RASTER` are this project's in-guest instruments** - read their
   headers in `src/main.asm` first, in particular why only one call site may be instrumented at
   a time. Both may fail to assemble on today's tree (the RAM squeeze, not the flag); try before
   assuming. (Kit note, from Edge Grinder, for anyone building a VIA-timer meter instead: three
   traps caught its meter before a single number was good: the two timer bytes are read one after the other and can roll between them (throw
   away a sample that goes backwards); a frame longer than 65.5 ms wraps the counter outright,
   which deaths and mode changes do (one measured 234 fields); and a phase *maximum* includes
   any interrupt that landed inside it, six a frame, so read maxima as upper bounds and take
   typical cost from single frames.)

7. **Record the table in the layer doc** with the build (DEV or RELEASE, flags), the date, and
   the scenario. "50/100 scrolling, DEV, 2026-09-04" is the shape; put the headline in the
   commit body.
