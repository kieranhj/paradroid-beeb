#!/bin/sh
# make.sh - the build, for anyone who types `./make.sh` from Git Bash
# or another POSIX shell. A thin wrapper over build.ps1, which is the
# build itself; arguments pass through, so `./make.sh -Run` assembles
# and launches b-em exactly as `.\build.ps1 -Run` does. make.bat is
# the same wrapper for cmd. Keep all three in step.
cd "$(dirname "$0")" || exit 1
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 "$@"
