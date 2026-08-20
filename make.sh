#!/bin/sh
# Build Paradroid (BBC Model B) -> build/PARADROID.SSD
#
#   ./make.sh          assemble into build/
#   ./make.sh run      assemble and launch in b-em
#
# Override the tool locations with the BEEBASM and BEM environment variables.

set -e
root=$(dirname "$0")
build="$root/build"
ssd="$build/PARADROID.SSD"
padded="$build/PARADROID-200K.SSD"
mkdir -p "$build"

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

# NO -boot HERE. main.asm SAVEs its own !BOOT, with the build stamp and the
# debug-flag lines, so -boot tries to write a second one and beebasm stops with
# "File already exists on DFS disc image" - even into a brand new image.
# -opt 3 sets the boot option so SHIFT+BREAK *EXECs it.
"$BEEBASM" -i "$root/src/main.asm" -do "$ssd" -opt 3 -title PARADROID -v \
    > "$build/PARADROID.lst"
echo "Built $ssd"

# A 200K copy for emulators. jsbeeb will not boot an unpadded image: beebasm's
# ends mid-track and jsbeeb refuses to read the last partial one, so the DFS FDC
# poll hangs loading PARASPR.
cp "$ssd" "$padded"
dd if=/dev/zero bs=1 count=1 seek=204799 of="$padded" conv=notrunc status=none
echo "       $padded   padded, for jsbeeb"

if [ "$1" = "run" ]; then
    "$BEM" -m3 "$ssd"
fi
