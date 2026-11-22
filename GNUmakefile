# GNU make reads this file before Makefile.
# The Makefile is POSIX (sh, and tools such as baron/zx02 on PATH). On Windows,
# where make runs recipes with cmd.exe, `make` calls build.ps1 instead, which
# finds the tools itself (see local.ps1). Everywhere else the Makefile is used unchanged.
ifeq ($(OS),Windows_NT)
BUILD := pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1

.PHONY: all release intro clean run help
all:
	$(BUILD)

release:
	$(BUILD) -Release

intro:
	$(BUILD) -Intro

clean:
	$(BUILD) -Clean

run:
	$(BUILD) -Run

help:
	@echo make          - build (build.ps1)
	@echo make release   - build.ps1 -Release
	@echo make intro     - build.ps1 -Intro
	@echo make clean     - build.ps1 -Clean
	@echo make run       - build.ps1 -Run (builds, then launches the emulator)
	@echo On Linux/macOS the POSIX Makefile is used: see README.md.
else
include Makefile
endif
