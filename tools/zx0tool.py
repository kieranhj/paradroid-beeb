#!/usr/bin/env python3
"""
zx0tool.py - find the ZX0 compressor, wherever this build is running.

Five tools shell out to the reference ZX0 (make_disc.py, pack_overlays.py,
make_briefing.py, make_intro_data.py, export_intro.py) and every one of
them used to name `bin/zx0.exe` literally. That is correct on Windows and
wrong everywhere else, and it is the reason issue #3 asks for no explicit
`.exe` anywhere: the suffix is the PLATFORM's business, not the build's.

Resolution order, first hit wins:

    1. an explicit path passed in (a tool's --zx0 option)
    2. $ZX0 in the environment          - what the Makefile sets
    3. bin/zx0.exe, then bin/zx0        - the checked-out local build
    4. `zx0` on $PATH                   - a system install

Steps 3 and 4 are what make the same tree work from build.ps1 (which has
always used bin/zx0.exe) and from the Makefile (which defaults ZX0 to
plain `zx0` and lets it be overridden), with neither one knowing which.

The compressor's output must be byte-identical to tools/zx0.py, which is
the format src/zx0depack.asm decodes - every caller round-trips its
stream through zx0.py before using it, so a WRONG zx0 on $PATH is caught
at the point of use rather than shipped. See tools/zx0src/README.md.
"""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent

_HELP = ("no ZX0 compressor found. Build one from tools/zx0src/ (see the "
         "README there), put it on $PATH, or set $ZX0 to it.")


def find_zx0(explicit=None):
    """Path (or bare command name) of the ZX0 compressor to run."""
    for cand in (explicit, os.environ.get("ZX0")):
        if cand:
            # An explicit choice is never second-guessed: if it is wrong
            # the caller wants to be told which one it asked for.
            return str(cand)
    for name in ("zx0.exe", "zx0"):
        p = PROJECT / "bin" / name
        if p.exists():
            return str(p)
    found = shutil.which("zx0")
    if found:
        return found
    raise SystemExit(_HELP)


def take_zx0_arg(argv):
    """Pull a `--zx0 PATH` option out of argv, returning the path or None.

    argv is modified in place. Written by hand rather than with argparse
    because these tools take positional paths in a fixed order and adding
    argparse to all five would change every one of their usage lines.
    """
    if "--zx0" in argv:
        i = argv.index("--zx0")
        if i + 1 >= len(argv):
            raise SystemExit("--zx0 needs a path")
        path = argv[i + 1]
        del argv[i:i + 2]
        return path
    return None


def run_zx0(zx0_exe, raw):
    """Compress `raw` with the reference compressor and return the stream.

    The caller round-trips it through zx0.py; this does the process side
    only. -f is 'force overwrite', which the temporary file needs because
    NamedTemporaryFile has already created it.
    """
    with tempfile.TemporaryDirectory() as td:
        src, dst = Path(td) / "in.bin", Path(td) / "out.zx0"
        src.write_bytes(raw)
        try:
            subprocess.run([str(zx0_exe), "-f", str(src), str(dst)],
                           check=True, capture_output=True)
        except FileNotFoundError:
            raise SystemExit("%s: not executable - %s" % (zx0_exe, _HELP))
        return dst.read_bytes()
