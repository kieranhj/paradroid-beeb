# ===========================================================================
# mk/data.mk - regenerate src/data/ from paradroid_ce.lst.
#
# Run as `make data` or `make world` from the top-level Makefile, never on
# its own path in the default build. THAT SEPARATION IS DELIBERATE: the
# converted data is committed (CLAUDE.md, KC 2026-08-27) so that the tree
# assembles without a local listing and without Pillow, and so that an
# exporter change shows up as a diff in src/data rather than as a silent
# rebuild. Keeping the rules in a second makefile is what stops them
# becoming prerequisites of the disc image by accident - which is exactly
# what happened the first time they lived in the Makefile.
#
# Dependencies are tracked all the same, so `make data` after editing one
# exporter runs that exporter and no other. Each exporter writes several
# files; only the first carries the recipe and the rest are named beside
# it, because make has no portable way to say "one command makes all of
# these" and a stamp file would be worse - a stamp touched after the files
# it stands for makes them look stale for ever.
#
# NEEDS Pillow (the exporters render and compare artwork) and a local
# paradroid_ce.lst, which is committed as of issue #3.
# ===========================================================================

PYTHON ?= python3
ZX0    ?= zx0

LST = paradroid_ce.lst

# Every exporter reaches the listing through rip_graphics.parse_listing and
# several pack with zx0.py, so both count as inputs to all of them.
# Over-approximating a dependency costs a needless rerun; missing one ships
# stale data, which is the failure this build has actually had.
EXPDEPS = $(LST) tools/rip_graphics.py tools/zx0.py tools/zx0tool.py

DATA =   src/data/chardata.asm src/data/colours.asm src/data/conicons.asm   src/data/droidgame.asm src/data/droidicon.asm src/data/droidinfo.asm   src/data/droids.asm src/data/droids2.asm src/data/effects.asm   src/data/hsremap.asm src/data/levels.asm src/data/plandata.asm   src/data/portraits.asm src/data/sideview.asm src/data/sndchat.asm   src/data/sounddata.asm src/data/strings.asm src/data/svdecks6.asm   src/data/textfont.asm src/data/tiledefs.asm src/data/title.asm   src/data/xferboard.asm

# SERIAL, and this one is measured. Most exporters write SEVERAL files
# from one run, and make treats a multi-target rule as one rule per
# target: run serially it re-stats and the exporter runs once, but under
# -j4 all four of export_bbc.py's targets were found out of date at once
# and four copies ran concurrently over the same output files. There is
# no portable "one command makes all of these" - GNU make's grouped
# targets (&:) are 4.3 and later and bmake has nothing - so the fix is to
# refuse the parallelism. It costs nothing: the whole regeneration is a
# few seconds, and it is not in the default build.
.NOTPARALLEL:

.PHONY: all
all: $(DATA)
	@echo "src/data regenerated from $(LST)"

src/data/chardata.asm src/data/colours.asm src/data/levels.asm \
src/data/plandata.asm src/data/tiledefs.asm: \
    tools/export_bbc.py tools/deck_palettes.json $(EXPDEPS)
	$(PYTHON) tools/export_bbc.py

src/data/droids.asm src/data/droids2.asm src/data/droidgame.asm: \
    tools/export_droids.py $(EXPDEPS)
	$(PYTHON) tools/export_droids.py

src/data/droidicon.asm: tools/export_droidicon.py $(EXPDEPS)
	$(PYTHON) tools/export_droidicon.py

src/data/droidinfo.asm: tools/export_droidinfo.py $(EXPDEPS)
	$(PYTHON) tools/export_droidinfo.py

src/data/effects.asm: tools/export_effects.py $(EXPDEPS)
	$(PYTHON) tools/export_effects.py

src/data/textfont.asm: tools/export_font.py $(EXPDEPS)
	$(PYTHON) tools/export_font.py

# hsremap.asm is a 72-byte remap INTO textfont, and export_hsremap.py
# reads textfont.asm to build it - the one edge between two exporters.
src/data/hsremap.asm: tools/export_hsremap.py src/data/textfont.asm $(EXPDEPS)
	$(PYTHON) tools/export_hsremap.py

src/data/conicons.asm: tools/export_icons.py $(EXPDEPS)
	$(PYTHON) tools/export_icons.py

src/data/portraits.asm: tools/export_portraits.py $(EXPDEPS)
	$(PYTHON) tools/export_portraits.py

src/data/sideview.asm src/data/svdecks6.asm: tools/export_sideview.py $(EXPDEPS)
	$(PYTHON) tools/export_sideview.py

src/data/sounddata.asm src/data/sndchat.asm: tools/export_sound.py $(EXPDEPS)
	$(PYTHON) tools/export_sound.py

src/data/strings.asm: tools/export_strings.py $(EXPDEPS)
	$(PYTHON) tools/export_strings.py

src/data/title.asm: tools/export_title.py $(EXPDEPS)
	$(PYTHON) tools/export_title.py

src/data/xferboard.asm: tools/export_xfer.py $(EXPDEPS)
	$(PYTHON) tools/export_xfer.py

