#!/usr/bin/env python3
"""
compare_ssd.py - are these two disc images the same build?

Two builds of an unchanged tree differ in exactly one place: main.asm
stamps the wall-clock time into !BOOT, so the minutes and seconds move.
That is three or four bytes at an offset that shifts with the catalogue,
which makes `cmp` useless for the question anyone actually asks - did
anything REAL change?

So compare per FILE, out of the catalogue, and mask !BOOT's stamp:

    python tools/compare_ssd.py A.ssd B.ssd

Exit 0 and "identical" if every file matches once the timestamp is
blanked; exit 1 and a per-file report otherwise. Catalogue metadata -
load and exec addresses, and the physical order the files are laid out
in - is compared too, because make_disc.py's boot-order layout is part
of what the loader depends on.

Written for `make check-ps1`, which uses it to prove the Makefile and
build.ps1 produce the same disc, and useful on its own for the
beeb-identical-build check after a change meant to be mechanical.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_disc import read_catalogue                      # noqa: E402

# "REM BUILD 09 Sep 2026 15:37:15" - the one line that is meant to differ.
STAMP = re.compile(rb"REM BUILD [^\r\n]*")


def normalise(name, data):
    return STAMP.sub(b"REM BUILD", data) if name == "!BOOT" else data


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    a_path, b_path = Path(sys.argv[1]), Path(sys.argv[2])
    a = read_catalogue(a_path.read_bytes())
    b = read_catalogue(b_path.read_bytes())

    problems = []
    for name in sorted(set(a) | set(b)):
        if name not in a:
            problems.append(f"  {name:8s} only in {b_path.name}")
            continue
        if name not in b:
            problems.append(f"  {name:8s} only in {a_path.name}")
            continue
        fa, fb = a[name], b[name]
        da = normalise(name, fa["data"])
        db = normalise(name, fb["data"])
        if len(da) != len(db):
            problems.append(f"  {name:8s} {len(da)} B vs {len(db)} B")
        elif da != db:
            n = sum(1 for x, y in zip(da, db) if x != y)
            first = next(i for i, (x, y) in enumerate(zip(da, db)) if x != y)
            problems.append(f"  {name:8s} {n} byte(s) differ, first at "
                            f"{first} ({first:#06x})")
        for key in ("load", "exec"):
            if fa[key] != fb[key]:
                problems.append(f"  {name:8s} {key} {fa[key]:#06x} vs "
                                f"{fb[key]:#06x}")

    # File order is the boot access order make_disc.py lays out; the
    # loader reads the disc in it, so a reshuffle is a real difference
    # even when every file's bytes match.
    if list(a) != list(b):
        problems.append("  file order differs:\n    %s\n    %s"
                        % (" ".join(a), " ".join(b)))

    if problems:
        print(f"DIFFER: {a_path} vs {b_path}")
        print("\n".join(problems))
        return 1
    print(f"identical: {a_path} and {b_path} "
          f"({len(a)} files, bar !BOOT's build timestamp)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
