---
name: beeb-cycle-timing
description: Measure exactly how many 2 MHz cycles a 6502 routine or interrupt handler takes in the running BBC Micro port, using a pair of jsbeeb MCP breakpoints and the elapsed cycle counter, with nothing added to the build. Use when the user asks how long something takes, whether an optimisation helped, or whether a phase fits its raster window.
---

# Breakpoint-pair cycle timing

How long a routine takes, exactly, with the build untouched: an execute breakpoint at the entry
and one at the return site, and the difference of two `elapsed_cycles` readings. Emulation is
deterministic, so one sample is exact for that state.

**Clock:** the MCP counts **2 MHz** CPU cycles. VIA timers count at 1 MHz (half that), a scanline is 128 cycles, a 50 Hz field is **39,936** with interlace off (the MOS default frame is 40,000)
**Read this:** `elapsed_cycles` from `read_registers` - correct on every version
**On jsbeeb-mcp >= 3.4.0:** `cycles_run` is the cycles actually run, and a breakpoint stop reports the registers with `elapsed_cycles`, so the second call goes away
**Never read this:** `cycles_run` on jsbeeb-mcp <= 3.3.0 - when a breakpoint fires it reports the number *requested*, not run (jsbeeb-mcp#25, fixed in 3.4.0)

## Steps

1. **Take the addresses from the symbol dump, never from memory or an old note.** Main-RAM
   addresses move on every build. `-do` is there only to stop beebasm dropping its ten loose
   `SAVE` files in the project root, and `-D RELEASE=0` is not optional - without it assembly
   stops at `DEV` with *Symbol not defined*.

   ```bash
   ./bin/beebasm.exe -i src/main.asm -do build/symbols.ssd -D RELEASE=0 -d | tr ',' '\n' | grep "'SprDrawAll'"
   ```

   `build/PARADROID.lst` is the other source, and the one that shows the emitted bytes.

   You want the `JSR` site (or handler entry) and the instruction after it (the return site).
   **For code in a sideways bank the address is only meaningful while that bank is paged in**,
   and most of this game is in a bank: bank 4 is the resting state, but `SprDrawAll` and
   `SprRestoreAll` page 5 and 6 in and out around themselves. An execute breakpoint at a bank-5
   address will fire on whatever bank 4 holds at that address too, so bracket a bank routine
   from its main-RAM caller wherever you can.

2. **Snapshot the state once you are in it.** `save_state` returns an ID; `restore_state` puts
   the machine back exactly - memory, registers and `elapsed_cycles` - so every later
   measurement starts from the same instant instead of being re-reached. Release any key you
   were holding after the restore: the keyboard is NOT in the snapshot (measured 2026-09-07).
   Reaching the state the first time still wants the rule below.

3. **Get the game into a repeatable state by poking, not by holding keys.** An injected
   keypress lands a pass earlier or later once code speed changes, and two runs then diverge for
   reasons unrelated to the change. Poke a speed (`dbgSpdX`) rather than holding a direction;
   `DEBUG_DECK`'s CTRL+`[` and CTRL+`]` reach a deck without playing the lift. Boot with `beeb-smoke-test`, `run_frames` to the state, then `write_memory` the
   inputs. `save_state` here so the same state can be restored for the "after" build.

4. **Set both breakpoints up front, then walk them one per run.** A run that starts with PC
   already on a breakpoint returns immediately with 0 cycles, so the sweep is: read, *clear the
   breakpoint that just fired*, run to the next. Breakpoints fire under `run_for_cycles` (an
   older note said only `run_frames`; both ports carry the correction).

   ```
   set_breakpoint    session_id, address: <entry>,  type: "execute"     # note the id
   set_breakpoint    session_id, address: <return>, type: "execute"
   run_for_cycles    session_id, cycles: 1000000            # stops at the entry
   read_registers    session_id                              # note elapsed_cycles (A)
   clear_breakpoint  session_id, id: <entry bp id>
   run_for_cycles    session_id, cycles: 1000000            # stops at the return
   read_registers    session_id                              # elapsed_cycles (B); cost = B - A
   ```

   `clear_breakpoint id: 0` clears them all when you are done.

5. **Average about 128 passes for anything a sprite touches.** One busy pass is not a typical
   one (Paradroid's rotor phase cycles every 8). Re-set the entry breakpoint after each pair
   and repeat; anchor the timeline on something that recurs (a field counter increment) so the
   samples are comparable. Report min, typical and max, and say which pass the max was.

6. **One site at a time if you patch stubs instead of using breakpoints.** Instrumenting two
   sites at once reliably hung Paradroid's main loop.

7. **Optional: the zero-byte stub, for "where against the raster does this phase end, over
   many passes"** - which is how this build gets an instrument when the code image has 14 bytes
   free. It lives in `&0130-&017E`, measured untouched rather than assumed (seed `&A5`, play,
   read back; `beeb-bss-bugs`, and `docs/ram-pass.md` lists the paths that measurement did NOT
   exercise). Hand-assemble per site: `JSR <real routine>`, `LDX <state byte>`,
   `INC counter,X`, `RTS`; repoint the `JSR` operand at the stub (two-byte poke, keep the
   originals); zero the counters; run 128 passes *scrolling* (a stationary player gives the
   drawer nothing to do); read the histogram back. **Disassemble the stub and read it back as
   code before the first run**: a branch two bytes short executed `JSR &6001` from
   mid-instruction, mimicked a game hang and wrecked two sessions before it was found.

   ```
   write_memory   session_id, address: 0x0100, bytes: [0, 0, ... 48 zeros]
   write_memory   session_id, address: 0x0140, bytes: [<stub bytes>]
   disassemble    session_id, address: 0x0140, count: 20        # the parameter is count, not length
   write_memory   session_id, address: <JSR operand>, bytes: [0x40, 0x01]
   run_for_cycles session_id, cycles: 10223616                  # 128 passes at 2 fields each
   read_memory    session_id, address: 0x0100, length: 48
   ```

8. **Record the number with its units and its state** in the layer doc: "6,155 cycles a sprite,
   restore + draw, stationary, DEV build, 2026-09-03". A frame meter in microseconds is half the
   cycle count - say which. An in-guest bracket on the User VIA T1 is
   `cycles = 2 * ((before - after) AND &FFFF) - 46` (the 46 is the bracket's own cost).
