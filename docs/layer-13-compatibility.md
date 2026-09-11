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
