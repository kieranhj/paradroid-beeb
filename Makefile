# ===========================================================================
# Makefile - Paradroid for the BBC Model B, built on any POSIX system.
#
# Issue #3 (hexwab). The build itself has always been build.ps1, which is
# PowerShell and therefore Windows in practice; this is the same pipeline
# expressed as a dependency graph, so that a partial build does only the
# part that changed and `make -j4` runs the five bank compressors at once.
# Measured: 18.2 s serial from clean, 9.2 s with -j4, 0.23 s when nothing
# has changed. docs/build.md has the rest of the numbers.
#
#   make            assemble and build build/paradroid.ssd (debug flags on)
#   make -j4        the same, four compressors in parallel
#   make release    the build for other people: intro on, every DEBUG_ off
#   make run        build, then launch an emulator (autodetected, or EMU=)
#   make data       regenerate src/data/ from paradroid_ce.lst
#   make world      data, then all - the whole thing from the listing
#   make help       every target, with a line each
#
# WHAT IT ASSUMES. beebasm and python come from $PATH unless overridden;
# the ZX0 compressor is BUILT, not assumed, because its source is vendored
# here. Nothing writes a `.exe` suffix - the platforms that need one
# supply it:
#
#   PYTHON=python3   BEEBASM=beebasm   ZX0=bin/zx0   MAKE=make   EMU=
#
# so `make BEEBASM=./bin/beebasm` uses a checked-out local assembler.
# tools/zx0tool.py resolves the compressor the same way for the Python
# tools ($ZX0, then bin/, then $PATH), which is how the same tree works
# from here and from build.ps1 with neither knowing which.
#
# PORTABILITY. POSIX.1-2024 make: `?=`, `+=`, `.PHONY` and `-j` are all in
# Issue 8, and GNU make and bmake have had them for years. No $(wildcard),
# no ifeq, no `%` pattern rules - every source is listed explicitly, which
# is what the issue asked for and what makes a partial build correct. Two
# inference rules do the compression. Paths use `/` throughout and every
# filename is written in the case it has on disc, so a case-sensitive
# filesystem and a case-preserving one see the same build.
#
# build.ps1 IS STILL THE WINDOWS BUILD and still works; the two produce
# byte-identical images (`make check-ps1` proves it). Keep them in step -
# a change to the pipeline has to land in both, and docs/build.md says so.
# ===========================================================================

PYTHON  ?= python3
BEEBASM ?= beebasm
MAKE    ?= make
EMU     ?=

# ZX0 IS NOT AN EXTERNAL TOOL AND THE BUILD MAKES IT (hexwab, issue #3).
# beebasm and python are things you install; the compressor's source is
# vendored here in tools/zx0src/, it is Einar Saukas' reference ZX0 built
# unmodified, and src/zx0depack.asm decodes exactly what it emits - so it
# belongs to this project the way the assembler does not. It is built into
# bin/ by the rule near the bottom and everything that compresses depends
# on it, so a fresh clone needs no separate step.
#
# An override must name an EXISTING file, not a bare command: it is a
# prerequisite, so `ZX0=zx0` would leave make with nothing to build.
ZX0     ?= bin/zx0

BUILD   ?= build
PACK     = $(BUILD)/pack

# Set by the `release` and `intro` targets through a recursive make; do
# not set them by hand unless you know why. RELEASE is a beebasm
# command-line symbol on EVERY build - main.asm has no default for it and
# stops at DEV with "Symbol not defined" if it is missing. See CLAUDE.md.
RELEASE  ?= 0
INTRO    ?= 0
# The disc's *OPT 4 value, and it MUST follow the !BOOT shape main.asm
# assembles (issue #18 item 4): 3 *EXECs the dev build's text !BOOT, 2
# *RUNs the 6502 stub a RELEASE build assembles instead, which needs no
# language ROM. build.ps1 does the same; make_disc.py carries it through.
# It is set on the `release` target's own recursion, not with an ifeq:
# POSIX make has no conditionals and this Makefile uses none.
BOOTOPT  ?= 3
INTRO_DEP =
INTRO_ARG =

RAW      = $(BUILD)/paradroid-raw.ssd
SSD      = $(BUILD)/paradroid.ssd
PADDED   = $(BUILD)/paradroid-200k.ssd
LISTING  = $(BUILD)/paradroid.lst
SYMBOLS  = $(BUILD)/symbols.ssd
INTRO_RAW = $(BUILD)/pintro-raw.ssd

# ALL LOWERCASE, and the extension is not a style question: b2 refuses a
# disc image called .SSD outright - "unknown extension: .SSD" - so the old
# build/PARADROID.SSD was unopenable in one of the emulators this port is
# checked against (hexwab, issue #3). The basename came with it on KC's
# call. 52 references across docs/, .claude/skills/, build.ps1 and tools/
# moved at the same time.
#
# THE DFS NAMES INSIDE THE IMAGE ARE UNTOUCHED and must stay uppercase:
# PARA, PARADAT, PARASPR, PARSPR2, PARXFER, PARAFNT, PARSWR, PINTRO and
# !BOOT are catalogue entries, and !BOOT does *RUN PARA. That is why the
# .bin/.zx0 intermediates below keep their uppercase stems - they are
# named after the DFS file each one came out of - with the lowercase
# extension the issue asked for.

# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------
# Everything in src/ is in the build and main.asm INCLUDEs all of it; the
# single-pass flat assembly has no linker and no partial objects, so the
# whole list is one prerequisite set. Adding a file to src/ means adding
# it here - there is no wildcard, deliberately: a build that silently
# ignores a new source is worse than one that has to be told about it.

ASM = \
  src/main.asm \
  src/briefing.asm src/briefman.asm src/bufcore.asm src/combat.asm \
  src/condb.asm src/condeck.asm src/console.asm src/consolesel.asm \
  src/dbgdeck.asm src/dbgkill.asm src/dbgpanel.asm src/door.asm \
  src/droid.asm src/highscore.asm src/hstable.asm src/infoscr.asm \
  src/keyredef.asm src/level.asm src/lift.asm src/liftview.asm \
  src/lowbss.asm src/lowcode.asm src/lowcode2.asm src/panel.asm \
  src/player.asm src/portrait.asm src/ruptalign.asm src/rupture.asm \
  src/screen.asm src/scroll.asm src/sound.asm src/sprfx.asm \
  src/sprite.asm src/sprsplit.asm src/swram.asm \
  src/title.asm src/xfer.asm src/xfericon.asm src/zx0depack.asm

# Converted C64 data, committed so the tree assembles without a local
# paradroid_ce.lst. The `data` target below regenerates it.
DATA = \
  src/data/chardata.asm src/data/colours.asm src/data/conicons.asm \
  src/data/droidgame.asm src/data/droidicon.asm src/data/droidinfo.asm \
  src/data/droids.asm src/data/droids2.asm src/data/effects.asm \
  src/data/hsremap.asm src/data/levels.asm src/data/plandata.asm \
  src/data/portraits.asm src/data/sideview.asm src/data/sndchat.asm \
  src/data/sounddata.asm src/data/strings.asm src/data/svdecks6.asm \
  src/data/textfont.asm src/data/tiledefs.asm src/data/title.asm \
  src/data/xferboard.asm

# The briefing's generated half. Its source is src/data/briefing.txt,
# which is hand-edited - the one exporter input that is not the listing.
BRIEF = \
  src/data/briefing.asm src/data/briefconst.asm src/data/brextra.asm \
  src/data/brstream0.asm src/data/brstream1.asm src/data/brstream2.asm \
  src/data/brstream3.asm src/data/brstream4.asm

# src/data/brfimg.asm, lowimg.asm and krimg.asm are NOT listed anywhere as
# prerequisites, and that is the point: they are written by the pack loop
# inside the $(RAW) recipe, out of the image that same recipe produced.
# List them and every build would find the raw image stale against its own
# output and assemble forever.

LST = paradroid_ce.lst

# Every exporter reaches the listing through rip_graphics.parse_listing
# and several pack with zx0.py, so both count as inputs to all of them.
# Over-approximating a dependency costs a needless rerun; missing one
# ships stale data, which is the failure this build has actually had.
EXPDEPS = $(LST) tools/rip_graphics.py tools/zx0.py tools/zx0tool.py

# ---------------------------------------------------------------------------
# Default build
# ---------------------------------------------------------------------------

.PHONY: all config debug release intro run data world clean \
        distclean help symbols listing zx0 check-ps1

all:
	@$(MAKE) config
	@$(MAKE) $(SSD)

debug: all

release:
	@$(MAKE) RELEASE=1 INTRO=1 BOOTOPT=2 \
	    INTRO_DEP=$(INTRO_RAW) INTRO_ARG="--intro $(INTRO_RAW)" all
	@echo "RELEASE build: intro on, every DEBUG_ flag off"

intro:
	@$(MAKE) INTRO=1 \
	    INTRO_DEP=$(INTRO_RAW) INTRO_ARG="--intro $(INTRO_RAW)" all

# ---------------------------------------------------------------------------
# Assembly, and the pack loop
# ---------------------------------------------------------------------------
# THE PACK LOOP IS NOT A DAG AND CANNOT BE ONE. Two of the things bank 6
# carries are assembled code copied down to run elsewhere (the PARBRF
# briefing driver at &0400, the low overlay at &0E00) and beebasm cannot
# compress its own output. main.asm SAVEs each under an X-name;
# pack_overlays.py reads them back out, ZX0s them and writes a generated
# file for the NEXT assembly. A stream that changes SIZE has moved the
# bank around under the very block it came from, so this is a fixpoint,
# not a dependency - it settles by iterating and says so with exit 10.
# IN THE STEADY STATE IT IS ONE ASSEMBLY: the first pass extracts what is
# already there, finds it unchanged and exits 0.
#
# TWO THINGS HERE ARE FOR `sh -e` (hexwab on #3, OpenBSD make). POSIX has
# make run every recipe with -e in effect, and BSD make does; GNU make
# does not unless the makefile says .POSIX. Under -e the exit 10 above
# kills the shell before `rc=$$?` can read it, so the status is taken
# with `|| rc=$$?`, which -e leaves alone. And the passes assemble into
# $(RAW).new, renamed only once the overlays have settled: a loop that
# dies in pass 1 would otherwise leave an image built against the STUBS,
# newer than everything it depends on, and the next make would ship it.

$(RAW): $(ASM) $(DATA) $(BRIEF) $(ZX0)
	@mkdir -p $(BUILD)
	$(PYTHON) tools/pack_overlays.py --zx0 $(ZX0) --ensure $(RAW)
	@rm -f $(RAW); pass=1; while :; do \
	    echo "  beebasm (pass $$pass)"; \
	    $(BEEBASM) -i src/main.asm -do $(RAW).new -opt $(BOOTOPT) -title PARADROID \
	        -D RELEASE=$(RELEASE) -v > $(LISTING) || \
	        { rm -f $(RAW).new; exit 1; }; \
	    rc=0; $(PYTHON) tools/pack_overlays.py --zx0 $(ZX0) $(RAW).new || \
	        rc=$$?; \
	    if [ $$rc -eq 0 ]; then break; fi; \
	    if [ $$rc -ne 10 ]; then rm -f $(RAW).new; exit $$rc; fi; \
	    pass=`expr $$pass + 1`; \
	    if [ $$pass -gt 4 ]; then \
	        echo "pack_overlays did not settle in 4 passes - the" \
	             "overlays' own bytes depend on the bank layout their" \
	             "size decides" >&2; \
	        rm -f $(RAW).new; exit 1; \
	    fi; \
	done; \
	mv $(RAW).new $(RAW)

listing: $(RAW)

# RELEASE and INTRO change what beebasm emits but touch no file make can
# see, so `make release` after `make` would otherwise ship a debug image.
#
# THIS IS A PHONY CHECK THAT DELETES $(RAW), NOT A STAMP FILE IN THE
# GRAPH, and the difference is not academic: make counts a target whose
# recipe RAN as updated, whether or not the recipe changed the file, so a
# stamp regenerated every build made everything downstream of it stale
# every build - a no-op `make` reassembled and recompressed the lot. The
# recursion in `all` above is what orders this before anything reads the
# image; it is the one place a plain prerequisite could not do the job.
config:
	@mkdir -p $(BUILD)
	@echo "RELEASE=$(RELEASE) INTRO=$(INTRO)" > $(BUILD)/config.new
	@cmp -s $(BUILD)/config.new $(BUILD)/config 2>/dev/null || { \
	    echo "  config: RELEASE=$(RELEASE) INTRO=$(INTRO) (rebuilding)"; \
	    cp $(BUILD)/config.new $(BUILD)/config; rm -f $(RAW); }
	@rm -f $(BUILD)/config.new

# ---------------------------------------------------------------------------
# Compression - the parallel half
# ---------------------------------------------------------------------------
# make_disc.py used to compress all five files itself, serially, inside
# one Python process; that was 5.0 s of a 7.9 s build. Split into three
# steps it is a graph make can spread over its jobs: --extract-file drops
# one bank out of the raw image, an inference rule turns each .bin into a
# .zx0, and --packed-dir consumes the streams. `make -j4` therefore runs
# four compressors at once. The image is identical either way, and it is
# CHECKED identical - every stream from --packed-dir goes through the same
# zx0.py round-trip against this build's bytes and the same in-place
# margin test, so a stale .zx0 fails the build instead of shipping.

BANKS   = PARADAT PARASPR PARSPR2 PARXFER PARAFNT
STREAMS = $(PACK)/PARADAT.zx0 $(PACK)/PARASPR.zx0 $(PACK)/PARSPR2.zx0 \
          $(PACK)/PARXFER.zx0 $(PACK)/PARAFNT.zx0

.SUFFIXES:
.SUFFIXES: .bin .zx0

.bin.zx0:
	$(ZX0) -f $< $@

$(PACK)/PARADAT.bin: $(RAW)
	@mkdir -p $(PACK)
	$(PYTHON) tools/make_disc.py --extract-file PARADAT $(PACK) $(RAW)
$(PACK)/PARASPR.bin: $(RAW)
	@mkdir -p $(PACK)
	$(PYTHON) tools/make_disc.py --extract-file PARASPR $(PACK) $(RAW)
$(PACK)/PARSPR2.bin: $(RAW)
	@mkdir -p $(PACK)
	$(PYTHON) tools/make_disc.py --extract-file PARSPR2 $(PACK) $(RAW)
$(PACK)/PARXFER.bin: $(RAW)
	@mkdir -p $(PACK)
	$(PYTHON) tools/make_disc.py --extract-file PARXFER $(PACK) $(RAW)
$(PACK)/PARAFNT.bin: $(RAW)
	@mkdir -p $(PACK)
	$(PYTHON) tools/make_disc.py --extract-file PARAFNT $(PACK) $(RAW)

$(PACK)/PARADAT.zx0: $(PACK)/PARADAT.bin $(ZX0)
$(PACK)/PARASPR.zx0: $(PACK)/PARASPR.bin $(ZX0)
$(PACK)/PARSPR2.zx0: $(PACK)/PARSPR2.bin $(ZX0)
$(PACK)/PARXFER.zx0: $(PACK)/PARXFER.bin $(ZX0)
$(PACK)/PARAFNT.zx0: $(PACK)/PARAFNT.bin $(ZX0)

# ---------------------------------------------------------------------------
# The disc image
# ---------------------------------------------------------------------------
# THE RAW IMAGE IS NOT BOOTABLE - UnpackBankIn expects a compressed stream
# at DEPK_STREAM, so beebasm's own output hangs at the first bank load.
# Always hand an emulator $(SSD) or $(PADDED), never $(RAW).

$(SSD): $(RAW) $(STREAMS) $(INTRO_DEP)
	$(PYTHON) tools/make_disc.py $(RAW) $(SSD) $(PADDED) \
	    --packed-dir $(PACK) $(INTRO_ARG)
	@echo "Built  $(SSD)"
	@echo "       $(PADDED)   padded, for jsbeeb"
	@echo "       $(LISTING)   assembly listing"

# ---------------------------------------------------------------------------
# The loading intro (scarybeasts' PINTRO, pdloader/)
# ---------------------------------------------------------------------------
# ITS BEEBASM PASS MUST RUN FROM INSIDE pdloader/: the PUTFILE paths are
# relative to the working directory, and from the project root they
# resolve to nothing, leaving a disc with PINTRO on it and none of its
# samples. Two of those PUTFILEs name ../build/ literally - pdloader is a
# vendored drop and is kept verbatim - so an intro build needs BUILD=build.
# A RELATIVE $(BEEBASM) has to be made absolute before that cd, which is
# what the case below does; a bare name is left alone and found on $$PATH.

INTRO_SRC = pdloader/paradroid_intro.asm
INTRO_IN = \
  pdloader/sample.bdrum pdloader/sample.sdrum pdloader/sample.shaker \
  pdloader/sample.bass128 pdloader/sample.bright pdloader/sample.tri32 \
  pdloader/sample.guitar pdloader/conv.out pdloader/lookup_tables.out \
  pdloader/screen

# make_intro_data.py ZX0s the intro's two streams, so $(ZX0) is a
# prerequisite here for the same reason as the briefing's below.
$(INTRO_RAW): $(INTRO_SRC) $(INTRO_IN) tools/make_intro_data.py $(ZX0)
	@test "$(BUILD)" = "build" || { echo "an intro build needs" \
	    "BUILD=build: pdloader PUTFILEs ../build/PINTDAT verbatim" >&2; \
	    exit 1; }
	ZX0="$(ZX0)" $(PYTHON) tools/make_intro_data.py
	@root=`pwd`; ba="$(BEEBASM)"; \
	 case $$ba in /*|?:*) ;; */*) ba="$$root/$$ba" ;; esac; \
	 cd pdloader && $$ba -i paradroid_intro.asm \
	     -do "$$root/$(INTRO_RAW)" -opt 0

# ---------------------------------------------------------------------------
# Generated data, from the C64 listing
# ---------------------------------------------------------------------------
# `make data` regenerates src/data/ from paradroid_ce.lst, and `make world`
# does that and then builds. THE DEFAULT BUILD DOES NEITHER, and the rules
# live in mk/data.mk rather than here so that they cannot creep into it.
#
# That is a project rule, not an oversight (CLAUDE.md, KC 2026-08-27): the
# converted data is COMMITTED, so the tree assembles with no listing and no
# Pillow, and an exporter change is meant to show up as a reviewable diff
# in src/data rather than as a silent rebuild of the artwork. mk/data.mk
# tracks the dependencies properly, so `make data` after touching one
# exporter reruns that exporter and no other.

data:
	@$(MAKE) -f mk/data.mk PYTHON="$(PYTHON)" ZX0="$(ZX0)"

world:
	@$(MAKE) -f mk/data.mk PYTHON="$(PYTHON)" ZX0="$(ZX0)"
	@$(MAKE) all

# The briefing IS part of the default build - unlike the exporters, its
# input is a hand-editable working file, so an edit to briefing.txt must
# reach the disc without anyone remembering to run a tool.
#
# TWO THINGS HERE BIT A FRESH CLONE UNDER -j4 (hexwab, issue #3), because
# a checkout gives every file much the same mtime and can leave the
# generated half looking older than briefing.txt:
#
# - It ZX0s its page streams, so it depends on $(ZX0) like every other
#   compression - without that, it ran before bin/zx0 existed and stopped
#   with "no ZX0 compressor found". ZX0 is passed in the environment so
#   an override reaches zx0tool.py too.
# - It writes all eight files in one run, and a multi-target rule is one
#   rule per target: four copies ran at once over the same outputs. So
#   ONE file owns the recipe and the other seven hang off it with an
#   empty one - the portable idiom, since grouped targets (&:) are GNU
#   4.3+ only. It is safe because the tool rewrites every output every
#   run, so all eight come out newer than their inputs together.
src/data/briefing.asm: \
    src/data/briefing.txt tools/make_briefing.py tools/zx0.py \
    tools/zx0tool.py $(ZX0)
	ZX0="$(ZX0)" $(PYTHON) tools/make_briefing.py
src/data/briefconst.asm src/data/brextra.asm \
src/data/brstream0.asm src/data/brstream1.asm src/data/brstream2.asm \
src/data/brstream3.asm src/data/brstream4.asm: src/data/briefing.asm
	@:

# ---------------------------------------------------------------------------
# Odds and ends
# ---------------------------------------------------------------------------

# Every global label as one long line of 'name':decimal - the quick way to
# find a variable's runtime address for an emulator poke. -do is there
# only to stop beebasm dropping its nine SAVEs as loose files in the root.
symbols:
	@mkdir -p $(BUILD)
	$(BEEBASM) -i src/main.asm -do $(SYMBOLS) -D RELEASE=$(RELEASE) -d

# The reference ZX0 by Einar Saukas, from tools/zx0src/, unmodified and
# BSD-3. `make zx0` builds it on its own; everything that compresses
# depends on $(ZX0) anyway, so a plain `make` builds it once on a fresh
# clone and never again. distclean leaves it alone - see the note there.
zx0: bin/zx0

bin/zx0: tools/zx0src/zx0_main.c tools/zx0src/zx0_compress.c \
         tools/zx0src/zx0_optimize.c tools/zx0src/zx0_memory.c \
         tools/zx0src/zx0.h
	@mkdir -p bin
	$(CC) $(CFLAGS) -O2 -o $@ tools/zx0src/zx0_main.c \
	    tools/zx0src/zx0_compress.c tools/zx0src/zx0_optimize.c \
	    tools/zx0src/zx0_memory.c

# Launch an emulator on the image. EMU= overrides the search; the order
# is the one this port is actually checked in - b-em first because it is
# what build.ps1 -Run uses, then the ones docs/ names for a second
# opinion. With none installed it falls back to jsbeeb in the browser,
# which needs nothing but the python the build already uses.
#
# EVERY LINE NAMES ITS MACHINE AND AUTOBOOTS (hexwab, issue #3). An
# emulator's default is whatever its user ran last, or a model B with no
# sideways RAM, and neither will run this. Each asks for a Master, which
# has the four banks: b-em's -m10 is a preset NUMBER from the user's own
# b-em.cfg, so it is the Master on a stock config and could be anything
# on an edited one - EMU=... with your own flags is the way round that.
# b2's -b autoboots but no flag picks its machine; mame is not told to
# autoboot. The jsbeeb URL is built by tools/run_jsbeeb.py.
run: $(SSD)
	@emu="$(EMU)"; \
	if [ -z "$$emu" ]; then \
	    for c in b-em b2 beebjit mame; do \
	        if command -v $$c > /dev/null 2>&1; then emu=$$c; break; fi; \
	    done; \
	fi; \
	if [ -z "$$emu" ]; then emu=jsbeeb; fi; \
	case $$emu in \
	    jsbeeb)    set -- $(PYTHON) tools/run_jsbeeb.py $(SSD) ;; \
	    *b-em*)    set -- $$emu -m10 -autoboot -disc $(SSD) ;; \
	    *beebjit*) set -- $$emu -master -autoboot -0 $(SSD) ;; \
	    *mame*)    set -- $$emu bbcm -flop1 $(SSD) ;; \
	    *b2*)      set -- $$emu -b -0 $(SSD) ;; \
	    *)         set -- $$emu $(SSD) ;; \
	esac; \
	echo "  $$*"; \
	exec "$$@"

# Prove this Makefile and build.ps1 agree. compare_ssd.py works per file
# out of the catalogue and masks !BOOT's build timestamp, which is the one
# thing two builds of an unchanged tree are MEANT to differ in. Windows
# only, obviously - it is the PowerShell build it is checking against.
# build.ps1 takes $PYTHON, $BEEBASM and $ZX0 from the environment so that
# both builds use the same tools. The `tr -d` is not decoration: Windows
# python prints a CR, backticks strip only the LF, and a path with a
# trailing CR launches nothing at all.
check-ps1: $(SSD)
	@cp $(SSD) $(BUILD)/make.ssd
	@py=`$(PYTHON) -c "import sys; print(sys.executable)" | tr -d "\r"`; PYTHON="$$py" BEEBASM="$(BEEBASM)" ZX0="$(ZX0)" powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1
	$(PYTHON) tools/compare_ssd.py $(BUILD)/make.ssd $(SSD)

clean:
	rm -rf $(BUILD)
	rm -f PARA PARADAT PARASPR PARSPR2 PARXFER PARAFNT PARSWR \
	      XBRF XLOW XKR XREC

# Also the pack loop's generated includes, which `make` puts back. It does
# NOT remove bin/zx0: the compressor is not this build's output, it is a
# tool someone put there, and on Windows `rm -f bin/zx0` deletes
# bin/zx0.exe - MSYS resolves the suffix - which is how the first version
# of this rule ate the compressor and broke the next build.
distclean: clean
	rm -f src/data/brfimg.asm src/data/lowimg.asm src/data/krimg.asm

help:
	@echo "Paradroid (BBC Model B) - targets:"
	@echo "  all        assemble and build $(SSD)  [default]"
	@echo "  release    the build for other people: intro on, DEBUG_ off"
	@echo "  intro      a debug build with the loading intro"
	@echo "  run        build, then launch an emulator (EMU= to choose)"
	@echo "  data       regenerate src/data/ from $(LST)"
	@echo "  world      data, then all - the whole thing from the listing"
	@echo "  listing    just assemble; leaves $(LISTING)"
	@echo "  symbols    dump every global label and its address"
	@echo "  zx0        build the reference compressor into bin/zx0"
	@echo "  check-ps1  prove this Makefile and build.ps1 agree"
	@echo "  clean      remove $(BUILD)/ and beebasm's loose SAVEs"
	@echo "  distclean  clean, plus the pack loop's generated includes"
	@echo ""
	@echo "Variables: PYTHON BEEBASM ZX0 EMU BUILD (see the header)"
	@echo "  make -j4   runs the five bank compressors in parallel"
