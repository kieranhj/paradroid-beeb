# Layer 13b/13c — Sideways RAM detection, and machine compatibility

**Status: 13b BUILT 2026-08-29. 13c under way** — a real Master 128 (2026-09-06) and issue #18's
portability fixes (2026-09-10), below. 13a, the RAM pass, is done and written up
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
at the game-over seam (gone since no-load step 5, 2026-09-09) — go through `ROMSEL` alone, so a board needing the latches would pass a
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

**A real Master 128 runs it — KC, 2026-09-06.** That is the first time the port has run on
hardware rather than jsbeeb's `B-DFS1.2` or b-em, and it clears the machine this pass expected
to be the awkward one: shadow RAM, a different `PAGE`, and the 65C12 the port deliberately does
not use. The README lists the Master as a supported machine on the strength of it. **Real B and
B+ hardware, DFS 2.26, and second processors are still untested.**

This pass runs it on the machines people actually have: B with DFS 1.2 and 2.26, B+, Master 128 (shadow RAM and a different `PAGE`),
and second processors, which the IRQ takeover and the rupture are both likely to dislike. Each
combination either works, or is documented as unsupported with the reason.

**Entry condition:** Layer 12 done, so memory needs are final. **Exit condition:** a build that
detects what it is running on, says so, and either runs correctly or refuses honestly.

### Issue #18 (hexwab's portability list) — KC's rulings, 2026-09-10

Test what jsbeeb has; **other DFSs (Opus, Watford, Solidisk) are not a priority**; second
processors go only as far as **loading into the host**; `!BOOT` without `*EXEC` is lower priority;
**shadow screen correct on Master and B+** (third-party boards out of scope); **write all the CRTC
registers**; **claim the NMI** and **the Master's "LK18/LK19" message**, both tested; a **softloaded
FS in sideways RAM is not supported** unless reported in the wild (**reversed 2026-09-10**, when
hexwab pointed out that ZMMFS is exactly that and common on a model B — see the last paragraph of
this section); **investigate the intro's
`*TAPE`**; respecting the OS's `*TV` settings is **won't fix**. One issue, one commit per fix.

### What jsbeeb runs, 2026-09-10

The dev build, booted with SHIFT+BREAK, then fire at the title and ~300 frames: "in play" means
`fieldCount` rising, the player's reference cell and `deck` set, `infoActive` 0.

| Machine | Before | After the host load address |
|---|---|---|
| B, DFS 1.2 | plays | plays |
| B, DFS 0.9 | plays | — |
| B, Acorn 1770 DFS | plays | — |
| Master 128 (MOS 3.20, 1770 DFS) | plays | — |
| B + 65C02 second processor | **refused**: "NEEDS 4 x 16K … FOUND 1" | **plays** |
| Master + 65C102 second processor | **refused**, the same | **plays** |

The two ADFS-only models cannot read a DFS image and were not tried.

**Second processors — every file now loads and runs in the HOST.** The catalogue's load and exec
addresses carried bits 16-17 = 0, because beebasm writes 16-bit addresses, and with a Tube attached
0 means the parasite: `PARSWR` loaded and ran over there, probed the parasite's own RAM at `&8008`
and found one "bank". `make_disc.py` now writes 3 in both fields, `&FFFFxxxx`, for every file — the
one place the catalogue is written, so `build.ps1`, the Makefile and `-Intro` all get it; without a
Tube the bits are ignored. **The game then overwrites the Tube host code** (`&0400-&07FF`, zero
page) as it takes the machine, which is harmless only because nothing after `.start` makes a
filing-system call — the same invariant the low overlay already depends on. jsbeeb reports ~40,130
cycles a frame on both Tube machines against 39,936 without; `fieldCount` advances normally, so
this is recorded rather than chased.

**Every CRTC register is written, once, after boot's `VDU 22`.** R0, R2, R3, R9, R10 and R11 used to
be whatever the MOS left, and R4/R5 until the rupture started. `SetupModeRegs` (bank 4, beside
`SetupPlain`) now writes all twelve, reached from `SetupMode`'s tail through `PgData`. **The values
are MOS 1.20's MODE 1 row, measured**: a write breakpoint on `&FE00` stopped the MOS in its CRTC
loop at `&CBB0` (`LDA &C46E,X`, indexed from `&C469,Y`), and `&C46E-&C479` read
`7F 50 62 28 26 00 20 22 01 07 67 08`; R7 = 34 agrees with `title.asm`'s `MODE1_R7`. Three are
ours on purpose: R1 = `PLAY_UNITS`, R8 = `R8_BLANK` (interlace bits clear) and R10 = `&20`, the
cursor off. Main RAM **+15** (`code_end` `&2FCA` → `&2FBB`, the two `CRTC` macros it replaced);
bank 4 −29. **Verified**: plain B plays; a Master given `*CONFIGURE TV 252,0` and a hard reset
boots, plays, and holds the rupture — 300 frames at exactly 39,936 cycles, `fieldCount` 39 → 139
over 100 frames.

**The NMI is claimed once the last load is done.** Straight after `UnpackFont` in `.start` — the
last filing-system call the game ever makes — OSBYTE 143 with X = 12 asks the filing system to
hand the NMI over, and `&40` (`RTI`) goes at `&0D00`. hexwab's method: the filing system can
claim it back if anything ever loads again, which `*TAPE` would have prevented; only Econet
suffers. 14 bytes of main RAM (`code_end` `&2FBB` → `&2FC9`). **Verified**: `&0D00` reads `40` at
the title and the plain B plays.

**A Master 128 short of banks is told about the links.** `PARSWR`'s refusal adds "(SET LK18 AND
LK19 WEST?)" when OSBYTE 0 with X = `&FF` returns 3 — the Master 128 alone, not the Compact or ET,
whose sideways RAM is not those links. hexwab's wording, from *Stunt Car*. In the loader, so the
game pays nothing. **Verified** by the method above (both `CMP #4` thresholds, now at `&190C` and
`&1928`, patched to 9 in a `*LOAD`ed copy, then `CALL &1900`): the Master printed the refusal and
the links line; the plain B printed the refusal alone.

**`*SHADOW` no longer hides the game.** On a Master (or B+) set to `*SHADOW`, the game's `VDU 22`
came up with the display in shadow RAM while the game writes main RAM: **measured** on jsbeeb's
Master after `*SHADOW` and a soft reset, ACCCON read `&1B` — D and E set, X clear — against `&18`
normally, and nothing the game drew could be seen. `PARSWR`'s success path now calls OSBYTE 114
with X = 1, which makes the MOS's *next* mode change non-shadow; the next one is `SetupMode`'s,
and nothing between changes mode. On a model B's OS 1.20 the unknown OSBYTE goes to the ROMs and
is ignored. In the loader, so the game pays nothing; a bare `*RUN PARA` does not get it, which is
the debugging path. hexwab's fuller dance (OSBYTE 133 first, then zeroing `&FE34`) exists for
third-party shadow boards, which KC ruled out of scope. **Verified**: the same `*SHADOW` + soft
reset gave ACCCON `&18` at the title and in play, and the Master played; the plain B plays.

**The intro's `*TAPE` — investigated, tested, not changed.** scarybeasts's `pdloader/` (the
`-Intro` build, which the release uses) calls OSBYTE 140 (`paradroid_intro.asm` line 966) "to
unload DFS before we trash its workspace" — his sample player runs from zero page `&40-&FF` with
interrupts off — and after the tune it backs zero page and `&0D00` out again, `*DISC`s, and
chains `PARA`. **Tested** on the `-Intro` build: the plain B and a Master under `*SHADOW` + soft
reset both go detector → intro → keypress → "Loading..." → title → play, and on the Master
ACCCON stayed `&18` through the intro, the title and play — OSBYTE 114 is a lasting state, not a
one-shot, so the intro's own `VDU 22` does not consume it. **What `*TAPE` costs is the `*DISC`
that has to follow it**: that forces DFS back even for someone who booted from another filing
system (hexwab's point).

**Then both removed — PORT 8 (KC, 2026-09-10).** Dropping the two calls alone hung DFS 1.2 in
its 8271 busy poll (`BIT &FE80` at `&ACAE`) on the chain to `PARA`, because `init_player`'s
advance tables (`&0400-&1BFF`) had flattened DFS's workspace underneath a DFS that still thought
it was live. So PORT 8 keeps `&0E00-&18FF` (11 pages) in the handover's second sideways bank —
idle until `PARA` loads `PARASPR` there — saved after the intro's last load and restored before
`RUN PARA`, both under `SEI`. The routines have to sit in PORT 7's `&2600` page: the first
attempt put them at `&2500`, which the player overwrites at run time, and `PortDfsRest` BRKed
("Bad program"). **Tested** on the `-Intro` build, fresh machines each: B/DFS 1.20, B/1770 and
the Master 128 all go intro → keypress → "Loading..." → title → play (fieldCount advancing one a
field, a deck up, the player placed). `pdloader/README.md` item 8 has the detail; it stays a
change to scarybeasts's drop, worth offering him upstream.

**A filing system softloaded into sideways RAM — item 9, reversed and BUILT (KC, 2026-09-10).**
hexwab: ZMMFS is common on a model B, because `PAGE` at `&0E00` beats more sideways RAM. It is MMFS
in a ROM socket whose bootloader (MMFS's `bootstrap.asm`, read) copies it into the **highest free
RAM bank** at power-up and CTRL-BREAK and **writes its type into the ROM table** at `&02A1`;
SWMMFS keeps its workspace in its own bank (`MA = &B700 - &0E00`), not at `&0E00`. `PARSWR` skips
every bank with a type, so a B with four banks and ZMMFS found three and refused. Now:

- **`PARSWR`** (`SwrImage`): only when exactly three clean banks are found, the highest bank that
  has a ROM type AND is RAM — MMFS's own test: flip `&8006`, read back, flip back, interrupts off —
  is taken as the **fourth slot, `SWRAM_XFER`**, and the report adds "(THE LAST HOLDS A ROM IMAGE,
  WHICH WILL BE OVERWRITTEN)". Four clean banks and nothing changes. The intro borrows only the
  first two slots, so it never touches it.
- **`.start`**: `PARXFER` is the **last load**, after the font, staged at `XFER_STREAM = &4000`
  (the font is on `DEPK_STREAM` by then). Then the NMI claim — the last call the image has to
  answer — then its ROM-table byte is **zeroed**, so the MOS never offers the bank another service
  call, and only then is it unpacked. `BootBanks` does three banks. The same order on every
  machine. `make_disc.py` writes `PARXFER`'s load address and puts it after `PARAFNT` on the disc.
  Code image **+9** (`code_end` `&2FC9` → `&2FD2`, 46 free).
- A soft BREAK afterwards gets the filing system back: ZMMFS's bootloader compares its RAM copy with
  its ROM on every BREAK and recopies it if they differ.

**Verified in jsbeeb**, which cannot run MMFS, by planting a fake ROM image in bank 7 of a Master
(exactly four banks) — a valid header and a service handler that counts its calls and records
the last one in the unused stack page — and marking it in `&02A8`. The pre-change image refused
("FOUND 3"). The new one reported `4 5 6 7` with the image line, played, and read: the image's
**last call was service 12** (the NMI claim), its ROM-table byte `00`, bank 7 holding `PARXFER`,
`&0D00` = `&40`. Through the `-Intro` build the image was still intact after the intro and the
same four facts held at the title. Plain B/DFS 1.20 and B/1770, with and without the intro, still
play. **A real ZMMFS machine has not been tried.**

## The report lists every bank found, in mixed case (2026-09-11, hexwab on #18)

hexwab tried several expansion boards in MAME and wanted to see what the probe **found**, not only
the four it took; on a board that misbehaves that is the useful half. `SwrList` prints
`Sideways RAM found:` and every bank in `swBanks` (highest first, `swCount` long) on all three
exits: before `Using banks:` on success, and ahead of the refusal on the short and Solidisk
paths, where it is the last pass's view. The messages are mixed case now; MODE 7 has lower case
and nothing here needs shouting. The older capitalised quotes above are records of those tests.

What his MAME runs showed, read from MAME's own board source rather than assumed:

- **Watford Electronics ROM/RAM board, "FOUND 0".** MAME routes every sideways write to a
  separate write-select register (`m_ramsel`), and nothing in its `weromram.cpp` ever sets it,
  so every write lands in one slot and no probe can succeed. That is a gap in MAME, and says
  nothing yet about a real board. Whether a real one needs a write-select too is unknown; if it
  does, it is refused for the same reason as Solidisk (DECISION 2).
- **Solidisk Twomeg 128K, "7 D E F", dies before the mode change.** In MAME's `stl2m128.cpp` its
  eight RAM banks (4-7, C-F) are distinct and written through ROMSEL alone, so the probe is right
  for it. But its shadow RAM IS those banks: with `&FE34` bit 7 set, CPU writes at `&3000`+ go to
  banks C/D (or E/F with bit 1). A boot `*LOAD` to `&3200` with shadow on would land in the
  game's own banks. That is a lead, not a measured cause, and KC has not asked for it to be
  chased.
- **Watford DDFS 1.53** died at `*RUN PARA` in b-em (`-m19`); KC has tested it in b2, where it
  runs.

## [DECISION 3] Every disc boots by `*RUN`, not `*EXEC` (issue #18 item 4)

**KC, 2026-09-11**, following `beeb-port-kit`'s `lib/boot_stamp.6502` (`BOOT_RUN`), whose own
RELEASE builds boot this way. An `*EXEC` `!BOOT` is typed at a LANGUAGE: on a B with no BASIC it
stops at "Language?", and under `*CONFIGURE LANG 11` it is typed into Edit. hexwab raised both, and
suggested `*OPT 4,2` with a `BRK` abort.

**It was RELEASE only, and is not any more (2026-09-13).** The dev build kept its `*EXEC` text
`!BOOT` as the readable record of which `DEBUG_` flags are on — until `OSBYTE 140` was added to
`.start` (DECISION 4 below) and the dev disc hung dead. **The game runs inside DFS's workspace:**
`&1100-&1900` is the random-access file buffer area, and living there works only because `*LOAD`
and `*RUN` never touch it. `*EXEC` does, and so does closing an exec file — so an `*EXEC` boot
cannot coexist with shutting the filing system down. Both discs are the stub now and both pass
`-opt 2`: `build.ps1` (`$bootOpt`) and the `Makefile` (`BOOTOPT`) set it unconditionally, and
`make_disc.py` carries the raw image's option through.

**The dev build loses nothing.** The stamp it used to `*TYPE` from `INFO` the stub prints itself,
from the same `BuildStamp` macro, `DEBUG_` line and all — and `INFO` is still a disc file, so
`*TYPE INFO` still answers at any prompt.

**The stub**, `main.asm`'s `!BOOT` block: print the stamp lines through OSASCI
(the same lines, without the `REM `s — `BOOT_PFX` is `""` or `"REM "`), `JSR OSCLI` "RUN PARSWR",
then `JMP OSCLI` "RUN PARA", which never returns. **It is assembled at `&0900`, not `&7E00`**: this
one RUNS, and `&7E00` is MODE 7's screen, so the stamp would scroll over the code printing it.
`&0900` is clear at boot — the title overlay lands there later, from bank 7 — and `PARSWR` (`&1900`)
and `PARA` (`&1100`) are both clear of it. `SAVE` gains the exec address, and an `ASSERT` keeps it
inside its page.

**`SwrAbort` closes the exec file AND `BRK`s.** The close is harmless when no exec file is open
(OSCLI "EXEC" with no filename closes whatever is current, and nothing is); the `BRK` is what stops
the stub, which OSCLIs the probe and would otherwise run `PARA` when it returned. The MOS prints
`Paradroid not started` even with no language ROM, which is half the point.

**`make_disc.py` knows both shapes** when it wires `PINTRO` in: the text `!BOOT` gains a line, the
stub's single command is renamed `PARA` -> `PINTRO`, and the intro chains to `PARA` itself.

**Verified in jsbeeb, 2026-09-11:**

| | |
|---|---|
| RELEASE disc, B/DFS 1.20 | option **2**, `!BOOT` load/exec `&0900`, 193 bytes; prints the stamp with no `REM`s, then `Sideways RAM found: 7 6 5 4 3 2 1 0` / `Using banks: 4 5 6 7`, and runs on into the intro and the game |
| `PINTRO` wiring | the stub's command reads `RUN PINTRO`, the probe's `RUN PARSWR` untouched |
| the refusal, under `*RUN` | banks marked occupied at the probe's entry until two were left: it printed `banks - found 2` and then **`Paradroid not started`**, and the game did not start |
| dev disc | still option **3**, text `!BOOT` at `&7E00` — now four `*` commands, one of them `*TYPE INFO` — boots to the briefing |

**Not settled: the BREAK beep.** The kit's own table leaves it open — a `*RUN` boot enters with
interrupts off (measured here too: `P` = `&35` at the probe's first instruction), so the MOS never
ends the beep it starts, and Edge silenced the chip in `install_irq` instead. OSBYTE 126 does not
help: no ESCAPE is pending. Our capture shows the game's driver idling silent long after boot, but
the first writes were not inspected, so whether a release disc beeps through its intro is untested.

### The stamp is a disc file, `INFO` (KC, 2026-09-11)

The build info was only ever readable in the seconds it scrolled past. It is a disc file now, so
`*TYPE INFO` gives it back at any prompt — the build time, the version line on a release, and every
`DEBUG_` flag that is on. **The dev `!BOOT` *TYPEs it** (`*BASIC`, `CLS`, `*TYPE INFO`, then the two
`*RUN`s: 44 bytes where it was 197). **The RELEASE stub prints its own copy** straight to the
screen, because it holds one OSCLI chain and nothing spare for a third command.

**`main.asm`'s `BuildStamp` macro emits the text once** and both use it, which is what stops them
drifting. It is named for beebasm, which refuses a macro whose name begins with a mnemonic —
`STAMP_TEXT` starts `STA`, and the build stops with *Macro name cannot start with an assembler
mnemonic*. `INFO` is assembled at the same `&7E00` scratch the text `!BOOT` uses (it is a file, not
code, and nothing loads it there) and sits right after `!BOOT` in `make_disc.py`'s `LAYOUT`, so it
is under the head when the boot reads it. Nine disc files now.

**Verified in jsbeeb, 2026-09-11:** `*TYPE INFO` works on DFS 1.20 — the dev disc printed
`PARADROID by ANDREW BRAYBROOK` ... `DEBUG: XFERWIN DECK KILL REDRAW` from the file, then probed
and ran the game.

## [DECISION 4] `OSBYTE 140` when the last load is done (issue #18)

**hexwab, 2026-09-13**, correcting this port. There are two problems and they have two different
answers, and until now the port gave the loader's answer to the game.

- **A loader** still needs to load, so it cannot shut the filing system down. It borrows the
  workspace, and the price is that it must **own the machine**: claim the NMI
  (`OSBYTE 143,12,255`, plus `RTI` at `&0D00`) and let no OS code whatever run, because regaining
  control is the only way the filing system can discover the theft.
- **A game that has finished loading** asks the filing system to go away. `OSBYTE 140` — what
  `*TAPE` ends up calling, without the OSCLI in the middle — has it detach every hook it holds and
  tell whatever hardware it was driving to stop raising NMIs. Only then is the workspace ours:
  `&B0-&CF` in the zero page, and `&0E00` up to OSHWM, where the low overlay lives.

The port is the second case and was behaving as the first **while making OS calls anyway** —
`OSBYTE 229` per game start, `OSBYTE &0F` at the game over, `OSBYTE 19` at every rupture align, all
after `PageLowIn` has buried the workspace. A filing system is *entitled* to hook those calls and
to find its workspace intact when it does. Acorn's DFS does not, which is the only reason this ever
ran; hexwab's Opus 1770 with DDOS 3.45 hung at the deck plan, and `044b42c` blamed the memory map
when the fault was the missing call. (That change stands — the deck plan's pointers cost nothing
where they are now — but its reasoning does not, and the note in `main.asm` is corrected.)

**Where it goes, and why it is the only place it can go.** In `.start`, immediately after the
`PARXFER` load — the last load on any path since no-load step 5 — and before the `OSBYTE 143` that
was already there. Every `JSR OSCLI` in the build is in `.start`, `BootBanks` or the `!BOOT` stub,
and the first byte of filing-system workspace to go is `PageLowIn`'s, inside `ts_loads`, which
`TitleSeq` reaches afterwards. **Nothing may ever load again**, which no-load had already paid for;
an ADFS version would have to move this call, not delete it.

**The NMI claim stays.** `OSBYTE 140` has the filing system stand its NMI hardware down, so what is
left is a *stray* NMI — noise, not an intentional interrupt. Eight bytes against an unrecoverable
jump through a page of stale 6502; hexwab calls it belt-and-braces rather than redundant.

**IT COST A HUNG MACHINE, AND THE CAUSE IS WORTH KNOWING.** `OSBYTE 140` on the dev disc hung dead:
boot reached `*RUN PARA` and went black, and jsbeeb found the CPU inside the DNFS ROM at `&ACB1`
with `ROMSEL` 14. **The game runs inside DFS's workspace.** `&1100-&1900` is the random-access file
buffer area, and loading there works only because `*LOAD` — and `*RUN`, which is `*LOAD` plus a
jump — never touches it. `*EXEC` does, and **so does closing an exec file**, which is an implicit
`*EXEC`: a first attempt put `OSBYTE 119` in front to close the file politely and hung identically,
because the close is itself a write into the region it was trying to make safe. The dev disc's
`*EXEC !BOOT` therefore had DFS scribble over the instructions executing the call. DECISION 3 above
is the fix: both discs boot by `*RUN` now.

**Verified in jsbeeb, 2026-09-13** (B/DFS 1.2). Release disc: `*RUN !BOOT`, intro, title. Dev disc,
SHIFT+BREAK autoboot: stamp with its `DEBUG:` line, probe, title, briefing, play. `&A9-&CF` seeded
with `&A5` in play and read back untouched after 800 frames. Without the call the title draws at
frame 745; with it and an `*EXEC` boot it never appears at all.

**Still open, and not part of this change:** `&0D9F` is the MOS's *extended vector table*, which
`lowcode2` lands on. That is not the filing system's — it is the route any sideways ROM takes when
it claims a vector — so `OSBYTE 140` does not make it ours, and the port makes three `OSBYTE` calls
after burying it. hexwab's broader warning belongs here too: *"We don't even know in advance that
filing system workspace only extends as far as `&1900`. It could be higher for other filing
systems."* Reading OSHWM at boot and refusing loudly, the way `PARSWR` refuses too few banks, is
the obvious guard and has not been built.

## [DECISION 5] Spending the reclaimed zero page (#18)

DECISION 4 made the second half of the zero page ours. This is what was put in it, why those
things and not others, and how far the claim has actually been measured.

**The rule that decides everything: `abs` → `zp` saves ONE BYTE PER REFERENCE always, and ONE
CYCLE only when the reference is not indexed** — `abs,X` and `zp,X` are both 4 cycles. So scalars
pay and arrays do not. Every absolute-mode data reference in the build was counted per operand and
attributed to the bank of the code making it; `drIdx` is 45 references in one byte (45:1) where
`drEnergy` is 51 references in fourteen (3.6:1). Three tiers were taken, in descending value,
one commit each:

| tier | what | zp | bought |
|---|---|---|---|
| 1 | the hot scalars — `sndFx1/2`, `joyYDir`, `numDoors`, `moveMode`, `drIdx`, `drCount`, `snCvH`, `snTm2`, `score` | 13 B | main RAM +70, bank 4 +104, PARAFNT +16 |
| 2 | bank 7's twelve — the transfer game, the droid database, the lift view, the portrait pool | 12 B | bank 7 **+231, nearly all of it in the `ALIGN` pad** |
| 3 | the panel printer — `pnTmp`, `pnCol` | 2 B | bank 6 +43 |

**405 bytes across five regions for 27 of zero page**, measured against `main` after the
branch was rebased off `dither` on 2026-09-13 — the earlier figures in the tier commits were
taken on the pre-`#20` base and are superseded by these. Main RAM went 39 → **100 B** and
bank 4 64 → **129 B**, which are the two that had been blocking work; bank 6 260 → 303,
bank 7 86 → 90 with its pad 5 → 236, bank 5 148 → 149.

**Tier 2's saving is nearly invisible in the tail, and that is the lesson.** `plandata.asm`'s
`ALIGN` absorbs anything assembled in front of it, so of Tier 2's 235 bytes the tail shows only
4: `planChars` went `&AFFF` → `&AF18` and the pad grew **5 → 236**. Quoting the tail alone would have reported the
change as worthless. CLAUDE.md's standing rule — quote a bank's pad and tail as a pair — is why
this was caught, and this is now its worked example.

**`ZpSeed` is the mechanism, and it is `SprSeedYcol` grown up.** Zero page is not loadable and is
not assumed to survive the front end, so every `EQUB` initial value these variables carried in the
code image is re-established at run time. The seeded variables are one contiguous run from
`drYcol0`, so a tier costs the seed table one byte per variable and no new code — `LDX #8` became
`#17`, `#29`, `#31`. `moveMode`'s `MM_MOBILE` is the only non-zero seed, which is why it is a table
and not a fill. **The seed table is bank 4's**, so every future tier is paid for there.

**`score` is at `&CC`, deliberately clear of the run.** It was `SKIP 4`, never an `EQUB`, so
`CombatInit` has always been its only initialiser. `ZpSeed` runs once per route into play and the
briefing's fire exit is one of those routes — seeding `score` there would be a silent wipe. Tier 1
parked it at `&B2` and had to stop the run short to step over it; Tier 2 moved it above the run so
the run can keep growing.

### `&D0-&E6` is free, and it was measured rather than argued

**KC, 2026-09-13:** the MOS's VDU driver workspace should be fine if the game owns IRQ and issues
no VDU command. `OSBYTE 140` does **not** free it — it is the VDU driver's, not the filing
system's — so the claim needed a measurement of its own rather than an inference from DECISION 4.

Seeded all 23 bytes with `&A5` and read back after the deepest path the game has: title → briefing
→ play; movement, firing and scrolling; a `CTRL+]` deck change (charset rebuild and full redraw);
ESCAPE → death sequence → game over; the high-score entry with initials typed; and back to the
title and briefing, which includes `GoTitle`'s `OSBYTE &0F`. **All 23 bytes came back untouched**,
and the same dump shows `&E7` upward carrying live, changing OS data — so the measurement also
confirms the boundary is where CLAUDE.md has always said it is.

    00D0  A5 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5
    00E0  A5 A5 A5 A5 A5 A5 A5 01 00 00 00 00 00 00 00 13
                              ^^ &E7 up, still the OS's

Two caveats worth carrying: this is Acorn DFS 1.2 with no other ROM claiming vectors, and the boot
`VDU 22` happens before `ZpSeed`, so anything placed here is only safe because it is seeded on
every route into play.

**The budget is therefore 35 proven free bytes** — `&C0-&CB` (12) and `&D0-&E6` (23).

### What was NOT done, and why

**Tier 4, the arrays, was costed and rejected**: `sprActive` 8 bytes for 37 references (4.6:1),
`drEnergy` 14 for 51, `drType` 14 for 49, `doorState` 7 for 17, `drSpdX` 14 for 16 (≈1:1). They are
indexed, so they buy bytes without cycles, and 35 bytes will not hold the useful ones anyway. The
case also weakened as the tiers landed: nothing is short of room now. **Do not re-litigate this
without a region that is actually tight again.**

**Two of Tier 2's screens were never driven** — the transfer minigame board (`xfTmp2`, `xfColTmp`,
`xfPlyColor`, `xfPlyY`, `xfColV`, `xfTime`) and the lift side view (`lvPos`, `lvRow`). The droid
database page was reached and is correct, which covers `dbType`, `dbCol`, `dbCap` and `poB`. The
residual risk is low — all twelve were `EQUB 0` and are seeded to 0, and references are by NAME, so
the addresses coinciding across banks in the analysis was an artefact of the scan and never of the
code — but those two screens should be played before this merges.
