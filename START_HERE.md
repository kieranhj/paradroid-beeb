# Paradroid: start here

A faithful port of Andrew Braybrook's Paradroid (C64, 1985) to the BBC Micro Model B / B+ / Master with 4 x 16K sideways RAM. 6502, beebasm. A game port; v1.0 released 2026-09-13.

| | |
|---|---|
| GitHub | https://github.com/kieranhj/paradroid-beeb (public) |
| Upstream | Original: Paradroid (C64), from the C64 disassembly `paradroid_ce.lst` (not redistributed) |
| Local path | D:\beeb\mine\Paradroid (moved from OneDrive\BEEB\Repos\Paradroid on 2026-11-22) |
| Branch | main; others: dither (2026-09-13), master-2px-scroll (2026-08-13), swram-beebem-writethrough (2026-09-18), stash/layer10-xfer-repeat-2026-08-25 |
| Last commit | 2026-10-06: tools/beebasm_dataflow.py: the kit runs beebgame's analyses unpatched now |

## What's in here
- `src/`: the port (`main.asm` includes everything); `src/data/`: C64 data converted mechanically (committed).
- `tools/`: Python exporters, `make_disc.py`, `pack_overlays.py`, ZX0 (`zx0src/`), analysis tools.
- `pdloader/`: scarybeasts' loading intro (PINTRO), vendored.
- `docs/`: layer write-ups, `build.md`; `PLAN.md` (status, what is left, rules), `BUGS.md` (numbered defects), `CLAUDE.md` (rules for Claude), `ANNOTATION.md`.
- `build.ps1` (the Windows build), `Makefile` + `mk/data.mk` (POSIX build), `make.bat` / `make.sh` (wrappers).
- Ignored local material: `paradroid_ce*.lst/.asm`, `prgs/`, `ref/`, `extracted/`, `bin/` (beebasm.exe, zx0.exe), `redux.zip`.

## Build and run
- `make`: on Windows, `GNUmakefile` (added 2026-11-22) runs `build.ps1`; `make release`, `make intro`, `make clean`, `make run` pass the matching switch (`run` launches the emulator), `make help` lists them. On Linux/macOS the POSIX `Makefile` is used unchanged.
- Works: `.\make.bat` or `.\build.ps1` -> `build\paradroid.ssd`, `build\paradroid-200k.ssd` (for jsbeeb), `build\paradroid.lst`. `.\build.ps1 -Release` is the build for other people; `-Run` launches b-em (path updated to D:\tools\beeb\B-Em on 2026-11-22).
- Tools: `bin\beebasm.exe`, `bin\zx0.exe`, Python 3.

## Local changes
- `build.ps1`: b-em path changed from OneDrive to D:\tools\beeb\B-Em\b-em-42f6597-w64 (2026-11-22 tidy, uncommitted).
- One git stash (`stash@{0}`, Layer 10 transfer score sweep, needs ~26 B of main RAM); the same is pushed as branch `stash/layer10-xfer-repeat-2026-08-25`.
- Stale OneDrive paths remain in `CLAUDE.md`, `.claude/skills/*`, `annotate.py` and `tools/rip_*.py` (the C64 originals' location `OneDrive\Projects\Paradroid`, which did not move).

## Status and next steps
- PLAN.md: everything is built except Layer 12 (balance, fidelity, feel) and real-hardware testing on Model B / B+ (Layer 13c). Tested on a real Master.
- Open defects in BUGS.md (e.g. #23, transfer info-screen palette flash). Static analysis pass 2026-10-06.
- Side branches: `dither` (offline plan), `master-2px-scroll` (Master 2 px scroll write-up), `swram-beebem-writethrough` (#22).

## See also
- `README.md`, `PLAN.md`, `BUGS.md`, `CLAUDE.md`, `docs/build.md`; D:\beeb\mine\beeb-port-kit, D:\beeb\mine\llm-beeb-wiki.
