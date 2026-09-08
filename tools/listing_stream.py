#!/usr/bin/env python3
"""
listing_stream.py — reduce a beebasm `-v` listing to one entry per emitted
instruction, so that a change meant to be purely mechanical can be PROVED to
have added, removed or reordered nothing.

WHY IT EXISTS.  CLAUDE.md has promised this check since the blitter pass
("reduce both builds' beebasm listings to a stream of (mnemonic, addressing
class) and compare"), and every time it was wanted the reducer was written
inline and thrown away, so no two runs were comparable.  This is the checked-in
one.  Brought over from beeb-port-kit's `py/beeb_port_kit/listing.py`, which is
Baron's; beebasm's listing is a different shape and much easier, see below.

WHAT IT PARSES.  beebasm's `-v` listing contains ONLY instructions and labels —
EQUB/EQUS/INCBIN emit nothing to it, which is what makes this exact rather than
heuristic.  Measured on build/PARADROID.lst, 2026-09-08: 57,255 lines, of which
53,102 are instructions, 3,185 are labels and the rest are macro banners.

    .start                                  a label:      column 0
         1100   AD 00 0A   LDA &0A00        an instruction: 5 spaces, address
    Macro PAGEBANK:                         a macro banner

WHAT AN ENTRY IS.  The opcode byte and the operand LENGTH — never the operand's
VALUE, because under a legitimate move every address-shaped operand changes.
So:

    a build against itself          0 differences
    one instruction inserted        1 difference   (measured here 2026-09-08:
                                    a synthetic NOP line spliced into
                                    build/PARADROID.lst gives exactly one)
    a constant changed 8 -> 4       0 differences  (kit, on its own template)

The last is the point to understand.  The stream proves the SHAPE of the code,
not its constants.  Compare the disc images byte for byte FIRST (they are
identical for a truly mechanical change); reach for the stream only when the
addresses were MEANT to move — a data removal, a relocation, a width change —
and read a clean diff as "the same instructions in the same order", not as
"the same program".  A change that intentionally alters instructions fails this
by design; that is the buffer oracle's job.

USAGE

    python tools/listing_stream.py build/PARADROID.lst > new.txt
    diff old.txt new.txt && echo "stream identical, $(wc -l < new.txt) entries"

    python tools/listing_stream.py --mnemonics build/PARADROID.lst
        adds the mnemonic to each entry — easier to read in a diff, and no
        weaker, since the mnemonic is a function of the opcode byte.
"""

import re
import sys
from pathlib import Path

# 5 spaces, four hex digits of address, 3 spaces, the emitted bytes, the source
INSN = re.compile(r"^ {5}([0-9A-F]{4}) {3}((?:[0-9A-F]{2} )+) *(\S+)")


def stream(path, mnemonics=False):
    """Yield one string per emitted instruction: opcode, operand length."""
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        m = INSN.match(line)
        if not m:
            continue                    # a label, a macro banner, the BOM line
        by = m.group(2).split()
        entry = f"{by[0]} {len(by) - 1}"
        if mnemonics:
            entry += f" {m.group(3).upper()}"
        yield entry


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("-")]
    if len(args) != 1:
        print(__doc__.strip().split("USAGE")[1].strip(), file=sys.stderr)
        return 2
    mnem = "--mnemonics" in argv
    n = 0
    for entry in stream(args[0], mnem):
        print(entry)
        n += 1
    print(f"{n} instructions", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
