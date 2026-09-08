---
name: beeb-key-numbers
description: Measure the BBC Micro's internal (keyboard matrix) key numbers in the jsbeeb MCP with OSBYTE 121 and INKEY, proving the scan on a known key first, so a port that reads the keyboard direct from the System VIA carries measured numbers. Use when adding or redefining a key, when a key number appears in source without a measurement behind it, or when SHIFT or CTRL needs a number.
---

# Measuring internal key numbers

Never recall a key number, but do not re-measure one either. Check, in order: this project's
own `docs/raster-timing.md` (the `keydown` mechanism, the bit patterns, and why `&FE4F` and not
`&FE41`), `src/keyredef.asm` for what Layer 11f already binds, and the kit's
`docs/hardware-facts.md` section 7 (thirty-five bindable keys plus SHIFT and CTRL) at
`C:\Users\khcon\OneDrive\BEEB\Repos\beeb-port-kit`. Use this skill only for a key that is in
none of them, or when a number in source has no measurement behind it.

**This port reads the keyboard direct from the System VIA** - latch line 3 down, `DDRA = &7F`,
the internal key number to `&FE4F`, PA7 read back; **69 cycles against the OS's 243**, both
measured. So the internal matrix number is what the code carries, and it must be right.
**Every debug key needs CTRL** since 2026-08-31, because the six play keys are redefinable and a
player who bound one to R, C, W, `[` or `]` would otherwise fire a debug function with it.

**Scan:** OSBYTE 121 (`A%=121`), X = first key to scan, returns the key held or `&FF`
**Floor:** OSBYTE 121 will not report keys 0-2, so **SHIFT (0) and CTRL (1) go through INKEY**
**INKEY to internal:** internal = the INKEY index less one (Z is INKEY -98 and internal 97)
**First:** `*FX229,1`, or BASIC eats ESCAPE before it can be measured
**Shortcut on jsbeeb-mcp >= 3.4.0:** `key_down` takes `key` (name), `internal`, `inkey`, or `col`
and `row`, and **reports the matrix keys that went down, with name and both numbers** - so a name
can be measured against its numbers in one call, without the BASIC scan below. Keep the scan for
what the *machine's own* scan sees, and to confirm the MCP's mapping. `keyboard_state` reports
what is held; `release_all_keys` clears it (jsbeeb-mcp#33, #34). Measured 2026-09-07 on 3.4.0:
`key_down key:"X"` -> `{col: 2, row: 4, name: "X", internal: 66, inkey: -67}`, agreeing with the
table in `docs/hardware-facts.md` section 7.

## Steps

1. **Boot the project's target model to BASIC** (`create_machine model:` from `CLAUDE.md`;
   `run_until_prompt`). A Master and a B share the matrix, but measure on the model the game
   ships for anyway; the number goes into the doc with the model beside it.

2. **Disable ESCAPE and enter the scan loop.** The loop scans from key 16 and prints on every
   change, so holding a key prints its number once.

   ```
   type_input   session_id, text: "*FX229,1"
   type_input   session_id, text: "10 A%=121:X%=16:Y%=0:K%=(USR(&FFF4) AND &FF00) DIV 256:IF K%<>L% PRINT K%:L%=K%"
   type_input   session_id, text: "20 GOTO 10"
   type_input   session_id, text: "RUN"
   ```

   This loop is reconstructed from the doc's description of the method, not copied from a
   saved program - which is why the next step exists.

3. **Prove the scan on a known key before trusting it.** Z is 97 in both ports' sources. Hold
   it, run, release, read the screen. If 97 does not print, the loop is wrong, not the key.

   ```
   key_down        session_id, key: "Z"
   run_for_cycles  session_id, cycles: 400000, clear: false      # keep the output
   key_up          session_id, key: "Z"
   run_for_cycles  session_id, cycles: 100000                     # the output comes back here
   ```

   `run_until_prompt` will not return while the loop runs; read the text from `run_for_cycles`
   (or `screenshot`). The MCP's key names are `A`-`Z`, `0`-`9`, `SPACE`, `RETURN`, `ESCAPE`,
   `DELETE`, `TAB`, `CAPS_LOCK`, the cursor keys, `F0`-`F9`, `SHIFT`, `CTRL`.

4. **Hold each key the project needs and note the number.** One key at a time; `key_up` before
   the next, because a key still held changes what the next scan reports (and a held key at
   BREAK breaks autoboot, `beeb-smoke-test` step 6). Edge Grinder's measured set: Z 97, X 66,
   K 70, M 101, L 86, P 55, Q 16, SPACE 98, ESCAPE 112 - cross-check against these, do not copy them.

5. **SHIFT and CTRL through INKEY**, calibrated on a known key in the same session. ESCAPE the
   loop first (`key_down ESCAPE`, run, `key_up`).

   ```
   type_input   session_id, text: "REPEAT:PRINT INKEY(-1),INKEY(-2),INKEY(-98):UNTIL FALSE"
   ```

   Hold Z: the third column goes to -1, proving INKEY -98 is Z, so internal 97 = INKEY index - 1.
   Then hold SHIFT and CTRL: SHIFT is INKEY -1 -> internal 0, CTRL INKEY -2 -> internal 1.

6. **Cross-check against every number the project already carries** (a `keyboard` source, the
   `KEY_` constants in the main source, a `bmKeyChar` table). Eight of Edge Grinder's cross-checked
   exactly against an earlier session, which is what says the method was right rather than
   merely repeatable. A disagreement means one measurement is wrong - find which before editing.

7. **Record in the layer doc**: the loop used, the model, the date, and the table of numbers.
   Put the constants in source as `KEY_Z = 97` with a comment saying "measured", not a lookup
   table copied from a manual.
