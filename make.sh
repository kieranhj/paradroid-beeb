#!/bin/sh
# Build Paradroid (BBC Model B) -> PARADROID.SSD
#
#   ./make.sh          assemble to PARADROID.SSD
#   ./make.sh run      assemble and launch in b-em
#
# Override the tool locations with the BEEBASM and BEM environment variables.

set -e
root=$(dirname "$0")
ssd="$root/PARADROID.SSD"

# Prefer the checked-out bin/ copy, fall back to whatever is on PATH.
if [ -z "$BEEBASM" ]; then
    if [ -x "$root/bin/beebasm" ]; then
        BEEBASM="$root/bin/beebasm"
    elif [ -x "$root/bin/beebasm.exe" ]; then
        BEEBASM="$root/bin/beebasm.exe"
    else
        BEEBASM=beebasm
    fi
fi
: "${BEM:=b-em}"

if ! command -v "$BEEBASM" >/dev/null 2>&1; then
    echo "ERROR: beebasm not found ($BEEBASM)." >&2
    echo "Build it from https://github.com/stardot/beebasm, put it in bin/ or on PATH," >&2
    echo "or set the BEEBASM environment variable to its location." >&2
    exit 1
fi

if [ ! -f "$root/src/data/levels.asm" ]; then
    echo "ERROR: src/data/ is missing - it is generated, not committed." >&2
    echo "Supply paradroid_ce.lst in the project root and run:" >&2
    echo "    python tools/export_bbc.py" >&2
    echo "    python tools/export_droids.py" >&2
    exit 1
fi

"$BEEBASM" -i "$root/src/main.asm" -do "$ssd" -boot PARA -v > compile.txt
echo "Built $ssd"

if [ "$1" = "run" ]; then
    "$BEM" -m3 "$ssd"
fi
