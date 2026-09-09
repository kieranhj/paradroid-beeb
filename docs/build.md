# The build — `build.ps1` and the Makefile

Two implementations of one pipeline. `build.ps1` is the Windows build and has been since the
port started; the `Makefile` is the same thing as a dependency graph, added 2026-09-09 for
hexwab's issue #3 so that the project builds on a POSIX system, does only the work a change
actually requires, and can use more than one core.

**They produce the same disc.** `make check-ps1` proves it — `tools/compare_ssd.py` compares the
two images per file out of the DFS catalogue, masking `!BOOT`'s build timestamp, which is the
one thing two builds of an unchanged tree are meant to differ in. Measured 2026-09-09, debug and
`-Release` both: **identical, 8 and 12 files.**

```
make                 debug build -> build/PARADROID.SSD
make -j4             the same, four compressors at once
make release         intro on, every DEBUG_ flag off
make run             build, then launch an emulator (EMU= to choose)
make data            regenerate src/data/ from paradroid_ce.lst
make world           data, then all
make help            every target
```

## What the Makefile assumes

Tools come from `$PATH` unless overridden, and **nothing in the build writes a `.exe` suffix any
more** — the platforms that need one supply it:

```
PYTHON=python3   BEEBASM=beebasm   ZX0=zx0   EMU=   BUILD=build
```

so `make BEEBASM=./bin/beebasm ZX0=./bin/zx0` uses a checked-out local build. `tools/zx0tool.py`
resolves the compressor the same way for the five Python tools that shell out to it — `$ZX0`,
then `bin/`, then `$PATH` — which is how the same tree serves both builds with neither knowing
which is running. `build.ps1` reads `$env:PYTHON` / `$env:BEEBASM` for the same reason, and
`make check-ps1` uses that to hand its own tools over.

Portability target is POSIX.1-2024 make: `?=`, `+=`, `.PHONY`, `.NOTPARALLEL` and `-j` are all in
Issue 8, and GNU make and bmake have had them for years. No `$(wildcard)`, no `ifeq`, no `%`
pattern rules — every source is listed explicitly, which is what the issue asked for and what
makes a partial build correct. Paths use `/`, and every filename is written in the case it has
on disc.

**Adding a file to `src/` means adding it to `ASM` in the Makefile.** There is no wildcard,
deliberately: a build that silently ignores a new source is worse than one that has to be told.

## Three things in the pipeline that are not a DAG, and what was done about each

**The pack loop is a fixpoint.** Two of the things bank 6 carries are assembled code copied down
to run elsewhere — the `PARBRF` driver at `&0400`, the low overlay at `&0E00` — and beebasm
cannot compress its own output. `main.asm` `SAVE`s each under an X-name, `pack_overlays.py` reads
them back out, ZX0s them and writes a generated file for the *next* assembly; a stream that
changes size has moved the bank around under the very block it came from. It settles by
iterating and says so with exit 10, so it stays a shell loop inside the `$(RAW)` recipe. In the
steady state it is one assembly. `src/data/brfimg.asm`, `lowimg.asm` and `krimg.asm` are
therefore **not prerequisites of anything** — list them and every build would find the raw image
stale against its own output and assemble for ever.

**`RELEASE` and `INTRO` change what beebasm emits but touch no file make can see.** The fix is a
phony `config` target that records them and *deletes* `$(RAW)` when they change, ordered ahead of
everything by the recursion in `all`. It was a stamp file first, and that was wrong in a way
worth writing down: **make counts a target whose recipe RAN as updated, whether or not the recipe
changed the file**, so a stamp regenerated every build made everything downstream stale every
build — a no-op `make` reassembled and recompressed the lot. With the phony check, a no-op
`make` is 0.23 s.

**Several exporters write more than one file from one run,** and make treats a multi-target rule
as one rule per target. Run serially it re-stats and the exporter runs once; under `-j4` all four
of `export_bbc.py`'s targets were found out of date at once and **four copies ran concurrently
over the same output files** (measured). There is no portable "one command makes all of these" —
GNU make's grouped targets (`&:`) are 4.3 and later, bmake has nothing — so `mk/data.mk` declares
`.NOTPARALLEL:`. It costs nothing: the whole regeneration is a few seconds and it is not in the
default build.

## Parallel compression

Compression was 5.0 s of a 7.9 s build: five serial `zx0` runs inside one `make_disc.py` process.
It is now three steps make can spread over its jobs — `make_disc.py --extract-file` drops one
bank out of the raw image as `build/pack/NAME.bin`, an inference rule (`.bin.zx0`) turns each
into a stream, and `--packed-dir` consumes them.

| | |
|---|---|
| `build.ps1` | 7.9 s |
| `make` (serial, from clean) | 18.2 s |
| `make -j4` (from clean) | **9.2 s** |
| `make`, nothing changed | **0.23 s** |
| `make`, one `src/*.asm` touched | 3.1 s |

Serial `make` is slower than `build.ps1` because it starts eight Python processes where the
PowerShell build starts three; `-j4` more than pays that back, and the incremental figures are
the ones that matter day to day.

**A stream from `--packed-dir` is not trusted.** It goes through the same `zx0.py` round-trip
against *this* build's bytes and the same in-place margin test as one the tool compressed itself,
so a stale `.zx0` is a build failure rather than a broken disc. That check is the reason the two
paths can be claimed identical rather than assumed so.

## `make data` is not part of the default build

`src/data` is committed (CLAUDE.md, KC 2026-08-27) so the tree assembles with no listing and no
Pillow, and so an exporter change shows up as a reviewable diff. The rules live in
`mk/data.mk` rather than in the Makefile because they *cannot* be allowed to creep into the
default graph — the first version put them in the Makefile and adding one new tool file made
`make` try to regenerate all the artwork.

`paradroid_ce.lst` **is committed as of 2026-09-09** (KC, on issue #3), which is what makes
`make data` and `make world` possible at all. `make data` needs Pillow.

**It immediately earned its keep.** The first real `make data` run reverted a hand edit in
`src/data/sndchat.asm`: `BR_CHAT_PRE` moved to `main.asm` on 2026-09-09 (no-load step 5) and its
old home was changed by hand to `ASSERT BR_CHAT_PRE == 5`, but `export_sound.py` was never
updated, so it still emitted the definition. Regenerating would have given beebasm the symbol
twice. The exporter now emits the `ASSERT`; every other one of the 22 generated files came back
byte-identical to what was committed, which is also the first proof that the exporters are
deterministic and that the committed data really does match the listing.

## `make.bat` and `make.sh`

Still thin wrappers over `build.ps1`, and still KC's entry point on Windows. They are not
wrappers over this Makefile and do not need to be: on Windows `build.ps1` is the build, and on a
POSIX box `make` is.

## Known rough edge

`make check-ps1` cannot run under MSYS2's make on this machine, because a PowerShell launched
from MSYS `sh` cannot execute the Microsoft Store Python alias — `& $python` returns without
setting `$LASTEXITCODE` and `build.ps1` reports a failure that did not happen. It works from a
normal Windows shell, or with a non-Store Python. The equivalence it checks was verified by hand
instead (above).
