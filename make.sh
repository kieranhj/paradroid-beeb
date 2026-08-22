#!/bin/sh
# make.sh - the build, for `./make.sh` from Git Bash or another POSIX
# shell. A thin wrapper over build.ps1, which is the build itself
# (briefing convert, beebasm, make_disc); nothing here needs keeping
# in step beyond the argument mapping. `./make.sh run` (this script's
# old convention) and `./make.sh -Run` both assemble and launch b-em.
# make.bat is the same wrapper for cmd.
cd "$(dirname "$0")" || exit 1
if [ "$1" = "run" ]; then
    set -- -Run
fi
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 "$@"
