# Layer 13b/13c — Sideways RAM detection, and machine compatibility

**Status: 13b BUILT 2026-08-29. 13c not started.** 13a, the RAM pass, is done and written up
separately in [`layer-13-ram-pass.md`](layer-13-ram-pass.md).

**Until Layer 13, RAM was not a constraint worth designing around** — KC's ruling of 2026-08-16:
where a layer needed room, take a fourth sideways bank and move on. 13a paid that off in one pass.
What is left is making the build honest about the machine it is running on.

## 13b — Sideways RAM detection at boot — BUILT 2026-08-29

Before this, the build assumed banks 4–7 were RAM and wrote into them regardless: a machine
jumpered anywhere else loaded a game that was never there and hung with nothing on screen.

### The shape of it

**`PARSWR` is a new disc file and a new boot step.** `!BOOT` runs it before `PARA`:

```
*RUN PARSWR
*RUN PARA
```

It probes, prints one line — `SWRAM BANKS 4 5 6 7` — writes five bytes at `SWR_HAND` and RTSes,
and BASIC feeds the exec file's next line. On a machine it will not drive it prints why and closes
the exec file behind itself, so `*RUN PARA` is never reached and the RTS lands on the BASIC prompt
with the message still up. `src/swram.asm`, assembled into the build after `SAVE "PARA"` — it runs
at `&1900`, inside the code image, so its bytes land on `PARA`'s in beebasm's 64K image and the
order of the two is load bearing.

**The game reads four bytes and otherwise does not care.** `SWRAM_DATA`/`SPR`/`SPR2`/`XFER` are
indices 0–3 into `swBank`, a four-byte table in the code image; `PAGEBANK` reads it instead of
carrying an immediate. `.start` copies the handover over the table before `BootBanks`, and only if
the magic byte is there.

### The probe

**The method is stnicc-beeb's** (`src/loader.bas`, the Bitshifters repo), transliterated. Its three
stages exist to survive two things a write-and-read-back probe gets wrong: **bank aliasing** (a
board decoding three select bits answers for N and N+8 with the same RAM, so one probe value
reports double the banks — sixteen DISTINCT values catch it) and **write-enable latches** (a
Solidisk board wants the index in the User VIA and `&FE32` too, or its RAM reads back as ROM).

Two deliberate departures, both in `src/swram.asm`'s header in full:

- **It only probes banks the MOS found no ROM in** (`&02A1`, the ROM type table). Probing writes a
  byte at `&8008`; doing that to a live utility ROM or a sideways-RAM filing system is how you hang
  a machine that was working. It also means we never *choose* one and blow it away at `BootBanks`,
  which matters more.
- **It saves the right byte.** stnicc's stage 1 reads its original with the bank from the end of
  the inner loop selected, so it saves bank 0's byte sixteen times and stage 3 restores bank 0's
  byte into every RAM bank. Inert there and inert for the four banks we take; not inert for a spare
  one we probe and hand back. `STY ROMSEL` before the read.

### [DECISION 1] The top four, and 4–7 by preference

KC, 2026-08-29: take the **four highest-numbered** RAM banks. Highest because the banks that matter
to other people sit low, and because on a machine with exactly banks 4–7 — a Master, and this
desk — the answer is 4, 5, 6, 7, which is what every measurement in `docs/` was taken on.
Verified: jsbeeb's `B-DFS1.2` has eight RAM banks and picks 4–7; a Master picks 4–7.

### [DECISION 2] Solidisk is detected and refused, not supported

KC, 2026-08-29: "let's not support solidisk for now — just report if detected at boot and warn
it's unsupported." The game's own writes into sideways RAM — `UnpackBankIn` at boot, `SaveDfsWs`
at the game-over seam — go through `ROMSEL` alone, so a board needing the latches would pass a
latched probe and then fail to hold the game. **The second, latched pass runs only when the first
has already failed to find four banks**, so an ordinary machine never writes the User VIA at all.

### [DECISION 3] No detector means 4–7, silently

KC, 2026-08-29: a bare `*RUN PARA` — every debugging session — finds no magic byte and keeps the
assembled defaults, so it behaves exactly as the port did before this existed. The failure paths
write no magic, so a refused machine cannot leave a half-written handover behind either (verified:
`&0A00` reads `FF` after both).

### The handover: five bytes at `&0A00`

Magic `&A5`, then DATA, SPR, SPR2, XFER. The printer buffer, chosen because it has to survive three
things: BASIC dispatching the next exec line, DFS loading `PARA` over `&1100-&2FFF`, and MODE 1's
clear of `&3000-&7FFF`. The charset that eventually covers it is built at deck load, long after
`.start` has read it.

**`&1900`, not `&1100`.** `!BOOT` is an open `*EXEC` file and DFS keeps its buffer in the
random-access space at `&1100` — which is safe for `PARA` precisely because `PARA` is the last
thing the exec file ever asks for. `PARSWR` runs while that file still has lines to give.

### What it cost

| | |
|---|---|
| Main RAM code image | **37 B** — `code_end` `&2FCF` → `&2FF5`, 11 B left under the GUARD |
| Low overlay | **gained** — its eight raw `PAGEBANK`s became `JSR Pg*`, 3 bytes against 7 |
| `PARSWR` on disc | 535 B, one catalogue entry, first in `make_disc.py`'s boot order |
| Every `PAGEBANK` | +1 byte, **+2 cycles** (`LDA abs` for `LDA #imm`) |
| `PAGESPRBANK` | byte-neutral, **+2 cycles** — `LSR/TAY/LDA swBank+SWRAM_SPR,Y` for `LSR/CLC/ADC #`. The two banks are adjacent in the TABLE now; the hardware promises nothing |

**Per pass, worst case ~150 cycles** against the ~39,000 spare: 16 `PAGESPRBANK`s (8 slots, draw
and restore), `SprFetchRow`'s entry at its documented one-row-in-fifty, under ten `Pg*` helper
calls, and the IRQ's sound tick twice. **If that ever needs to be zero**, the sites can go back to
immediates and be patched from `swBank` at boot out of a table in bank 4 — byte- and
cycle-neutral against the old build, at the price of a hand-maintained address list. Not built.

### Verified in jsbeeb

- `B-DFS1.2`: reports `SWRAM BANKS 4 5 6 7`, handover `A5 04 05 06 07`, boots through title,
  briefing and into play.
- **Relocated**: handover forced to 0,1,2,3 — briefing scroller, briefing exit (which reloads
  `PARASPR` into the borrowed bank), deck draw, panel, and the blitter across both shift groups all
  correct. This is the test that proves the port is no longer bank-number-bound.
- Master: reports `SWRAM BANKS 4 5 6 7`.
- Both refusal messages, by patching the `CMP #4` thresholds in a loaded copy — which is also how
  to re-test them.

## 13c — Machine compatibility testing

The port has only ever run on jsbeeb's `B-DFS1.2` and b-em. This pass runs it on the machines
people actually have: B with DFS 1.2 and 2.26, B+, Master 128 (shadow RAM and a different `PAGE`),
and second processors, which the IRQ takeover and the rupture are both likely to dislike. Each
combination either works, or is documented as unsupported with the reason.

**Entry condition:** Layer 12 done, so memory needs are final. **Exit condition:** a build that
detects what it is running on, says so, and either runs correctly or refuses honestly.
