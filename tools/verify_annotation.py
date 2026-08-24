#!/usr/bin/env python3
"""
verify_annotation.py - does paradroid_ce_annotated.asm still contain all the
DATA that paradroid_ce.lst does?

WHY THIS EXISTS.  BUGS.md #19.  The C64 original is this project's
specification and the annotated listing is the copy of it everyone reads.
Looking up CharColor ($0800) there returned 76 bytes; the table is 256, and
the raw listing has all of it.  A data table that silently returns a fraction
of itself produces a port feature faithful to the part that survived - so this
compares the two files block by block and says where they disagree.

HOW.  The raw listing lays a .BYTE directive out in TAB-SEPARATED COLUMN
GROUPS, and prints the block's address on the FIRST line only - every
continuation line repeats it.  So the values of one block are the concatenation
of every tab field of every line that carries that address, and a running
offset is what turns them back into addresses.  Both files are read that way,
which is the point: if annotate.py drops a field, this sees a short block.

Run:  python tools/verify_annotation.py
"""

import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
RAW = PROJECT / 'paradroid_ce.lst'
ANN = PROJECT / 'paradroid_ce_annotated.asm'

ADDR_RE = re.compile(r'^([0-9A-Fa-f]{4})[\s\t]')
MNEMONIC_RE = re.compile(
    r'\b(LDA|STA|LDX|STX|LDY|STY|JSR|JMP|RTS|RTI|BEQ|BNE|BPL|BMI|BCS|BCC'
    r'|BVS|BVC|CLC|SEC|CLI|SEI|NOP|PHA|PLA|TAX|TAY|TXA|TYA|TSX|TXS|INX|INY'
    r'|DEX|DEY|INC|DEC|ADC|SBC|AND|ORA|EOR|CMP|CPX|CPY|ASL|LSR|ROL|ROR|BIT'
    r'|PHP|PLP|BRK|SED|CLD|CLV)\b')


def values_of(text):
    """Every numeric literal in a .BYTE operand list, across all tab fields.

    Stops at a ';' comment.  A field that is not a number ends the field, not
    the line - IDA writes trailing commas and the odd symbol.
    """
    text = re.sub(r';.*', '', text)
    out = []
    for tok in re.split(r'[,\t ]+', text.strip()):
        tok = tok.strip().rstrip(',')
        if not tok:
            continue
        try:
            out.append((int(tok[1:], 16) if tok.startswith('$') else int(tok)) & 0xFF)
        except ValueError:
            continue
    return out


def blocks(path):
    """{block_start_addr: [byte, ...]} for every .BYTE block in the file."""
    found = {}
    base = None
    with open(path, 'r', encoding='latin-1') as f:
        for line in f:
            m = ADDR_RE.match(line)
            if not m:
                continue
            addr = int(m.group(1), 16)
            bm = re.search(r'\.BYTE\s+(.*)', line, re.DOTALL)
            if not bm:
                # an instruction ends the block; a bare xref comment does not
                if MNEMONIC_RE.search(line):
                    base = None
                continue
            vals = values_of(bm.group(1))
            if not vals:
                continue
            if base is None or addr != base:
                base = addr
                found.setdefault(base, [])
            found[base].extend(vals)
    return found


def main():
    for p in (RAW, ANN):
        if not p.exists():
            sys.exit('ERROR: %s not found. See README.' % p)

    raw = blocks(RAW)
    ann = blocks(ANN)
    print('paradroid_ce.lst            %4d .BYTE blocks, %6d bytes'
          % (len(raw), sum(len(v) for v in raw.values())))
    print('paradroid_ce_annotated.asm  %4d .BYTE blocks, %6d bytes'
          % (len(ann), sum(len(v) for v in ann.values())))
    print()

    short, missing, mismatch, zp = [], [], [], []
    for addr in sorted(raw):
        r = raw[addr]
        if addr not in ann:
            # annotate.py emits zero page as an equate (`name = $XX`) rather
            # than a .BYTE, by design - so the ADDRESS survives and the
            # assembled initial value does not. Expected, and reported below
            # rather than counted as a failure.
            (zp if addr < 0x100 else missing).append((addr, len(r)))
            continue
        a = ann[addr]
        if len(a) < len(r):
            short.append((addr, len(r), len(a)))
        n = min(len(a), len(r))
        bad = [i for i in range(n) if a[i] != r[i]]
        if bad:
            mismatch.append((addr, len(bad), bad[0]))

    extra = sorted(set(ann) - set(raw))

    if zp:
        print('Zero-page bytes emitted as equates rather than .BYTE: %d'
              % len(zp))
        print('  Expected - annotate.py writes `name = $XX` below $0100. The'
              ' ADDRESS survives;')
        print('  the assembled initial value does not. Read those from'
              ' paradroid_ce.lst.')
        print()

    if missing:
        print('BLOCKS ABSENT from the annotated listing: %d' % len(missing))
        for addr, n in missing[:20]:
            print('  $%04X  %d bytes' % (addr, n))
        if len(missing) > 20:
            print('  ... and %d more' % (len(missing) - 20))
        print()

    if short:
        lost = sum(r - a for _, r, a in short)
        print('BLOCKS TRUNCATED in the annotated listing: %d  (%d bytes lost)'
              % (len(short), lost))
        for addr, r, a in short[:30]:
            print('  $%04X  raw %4d  annotated %4d   (%d dropped)'
                  % (addr, r, a, r - a))
        if len(short) > 30:
            print('  ... and %d more' % (len(short) - 30))
        print()

    if mismatch:
        print('BLOCKS WITH DIFFERING VALUES: %d' % len(mismatch))
        for addr, n, first in mismatch[:20]:
            print('  $%04X  %d bytes differ, first at offset %d' % (addr, n, first))
        print()

    if extra:
        print('Blocks only in the annotated listing: %d  (%s)'
              % (len(extra), ' '.join('$%04X' % a for a in extra[:10])))
        print()

    if not (missing or short or mismatch):
        print('OK - every .BYTE block matches the raw listing byte for byte.')
        return 0
    print('The annotated listing is NOT a faithful copy of the data. '
          'Take data tables from paradroid_ce.lst until this passes.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
