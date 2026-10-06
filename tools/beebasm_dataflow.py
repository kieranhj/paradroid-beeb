"""
beebasm_dataflow.py - beebgame's tools/dataflow static analyses on a BEEBASM
build: the -v listing written out as the ld65 debug file they read, and the
analyses run on it.

beeb-port-kit: new 2026-10-06, written for Paradroid and Edge Grinder, the two
beebasm ports (docs/dataflow.md, "BeebASM projects"). baron_dbg.py is the Baron
equivalent; this is one file, converter and runner both, because a beebasm
project has none of the template's tools/ to sit beside.

FORKED from beeb-port-kit py/beeb_port_kit 2026-10-06, unchanged.

Fork it into the project's tools/ with a tools/dataflow_config.py beside it,
and run it from the project root (build first):

    python tools/beebasm_dataflow.py            report -> build/dataflow/report.md, abi.md
    python tools/beebasm_dataflow.py annotate   the whole-program range analysis:
                                          build/annotated/src/listing.s, summary.md
    python tools/beebasm_dataflow.py patterns   mechanical finds over the ranges

tools/dataflow_config.py names the listing (LISTING) and the source folders
(SOURCES) beside the analyses' own fields (ISR_ROOTS above all).

The analyses are Eben Upton's (github.com/ebenupton/beebgame, MIT), vendored
unmodified and hash-checked in beeb-port-kit (template/tools/dataflow), and run
through the kit's tools/analyse.py. Nothing of them is copied into the
project: $BEEB_PORT_KIT, else ../beeb-port-kit, is where they are read from.
$DATAFLOW_BUDGET sets the range analysis's step limit (upstream's
RANGES_BUDGET, 3,000,000 a run); a run that hits it says it is NOT sound.

WHAT THIS ADDS. The analyses read only ld65's debug file. The kit writes one
from a Baron build (baron_dbg.py); this writes one from a BEEBASM listing,
which is harder, because beebasm's -v listing prints RESOLVED operands
(`LDA &0A00`), not the source text:

  * Code and data come from the listing: a line with bytes and a mnemonic is
    an instruction, a line with bytes and nothing else is data. Paradroid's
    beebasm lists every byte; Edge Grinder's cuts an INCBIN to three and
    "...", which is taken to run to the next listed address and left as
    zeros (the report decodes instruction bytes only, so nothing reads them).
  * NO SOURCE LINE can be recovered. Findings point into build/dataflow-in/
    src/listing.s, a listing-shaped file written here (labels, then each
    statement in listing order); the routine name and the address are what
    to search the sources by.
  * Sections are not marked in a beebasm listing. A new one starts wherever
    the address goes backwards or jumps forward by more than a page; that
    recovers the memory map (code, the four banks, the overlays) - check the
    summary line against build/paradroid.lst's own map at its end.
  * Address-taken labels (dispatch tables, `LDA #LO(x)`) come from the
    SOURCES: a label named anywhere other than as the target of JSR, JMP or
    a branch counts as taken (1,368 of 3,219 in Paradroid, 2026-10-06). That
    over-approximates, which costs findings, never correctness. Local labels
    in different { } scopes share a name and so share the verdict.

Measured 2026-10-06: Paradroid (944578c) 22,556 instructions, 371 findings,
up to 274 bytes, ~9 s; Edge Grinder (0000aec) 4,051 instructions, 83
findings, 106 bytes, ~2 s, and its range analysis converged in 56 s.
"""

import collections
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIT = Path(os.environ.get("BEEB_PORT_KIT", ROOT.parent / "beeb-port-kit"))
KIT_TOOLS = KIT / "template" / "tools"

# an address, then optionally bytes and text; a bare address is a SKIP or a
# zero-page variable (Edge Grinder's listing prints "     0070" for one)
ADDR = re.compile(r"^\s+([0-9A-F]{4})(?:   ((?:[0-9A-F]{2}(?: |$))*)\s*(.*))?\s*$")
LABEL = re.compile(r"^\.([A-Za-z_][A-Za-z_0-9]*)\s*$")
MNEM = re.compile(r"^[A-Za-z]{3}\b")
DIRECT = re.compile(r"^\s*(?:\.\w+\s+)?(JSR|JMP|B(?:PL|MI|VC|VS|CC|CS|NE|EQ))\s+([A-Za-z_]\w*)\s*$", re.I)
IDENT = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")


def convert(listing, srcdirs, out):
    (out / "src").mkdir(parents=True, exist_ok=True)
    text_lines, segs, emits, labels = [], [], [], []
    seg, prev, pending = None, None, None
    for raw in listing.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        m = ADDR.match(raw)
        if not m:
            s = raw.strip()
            lab = LABEL.match(s)
            if lab:
                text_lines.append(lab.group(1) + ":")
                labels.append([lab.group(1), None, None])     # the next line's address
            elif s.startswith("Macro ") or s.startswith("End macro"):
                text_lines.append("; " + s)
            elif s.startswith("Saving file"):
                # a SAVE: whatever comes next is another file's, so another
                # section, and a cut-short INCBIN cannot run past it
                seg, pending = None, None
            continue
        addr = int(m.group(1), 16)
        data = bytes(int(b, 16) for b in (m.group(2) or "").split())
        txt = (m.group(3) or "").strip()
        if pending is not None:
            # the line before was an INCBIN the listing cut short ("00 00 00 ...
            # INCBIN"): it runs to this address. Its bytes are unknown and stay
            # zero, which the report does not read (it decodes only instruction
            # bytes); the length is what keeps the section in one piece.
            e, g = pending
            if e[1] < addr <= e[1] + 0x5000:
                e[2] = addr - e[1]
                g["hi"] = max(g["hi"], addr)
                prev = addr
            pending = None
        if not data:
            # an address with no bytes (a SKIP, a zero-page variable): it places
            # the labels above it, and says nothing about where a section is
            for lab in labels:
                if lab[1] is None:
                    lab[1], lab[2] = addr, None
            continue
        if seg is None or addr < prev or addr > prev + 256:
            seg = dict(lo=addr, hi=addr, image={})
            segs.append(seg)
        for lab in labels:
            if lab[1] is None:
                lab[1], lab[2] = addr, len(segs) - 1
        for k, b in enumerate(data):
            seg["image"][addr + k] = b
        seg["hi"] = max(seg["hi"], addr + len(data))
        prev = addr + len(data)
        if txt and MNEM.match(txt):
            text_lines.append("    " + txt.lower())
            kind = "insn"
        else:
            text_lines.append("    .byte " + ",".join("$%02X" % b for b in data)
                              + (" ; " + txt if txt.startswith("...") else ""))
            kind = "data"
        emits.append([len(segs) - 1, addr, len(data), len(text_lines), kind])
        if txt.startswith("..."):
            pending = (emits[-1], seg)

    names = {lab[0] for lab in labels}
    taken = set()
    for f in (f for d in srcdirs for f in d.rglob("*.asm")):
        for line in f.read_text(encoding="latin-1").splitlines():
            code = re.split(r"[\\;]", line, maxsplit=1)[0]
            for st in (s.strip() for s in code.split(":")):
                # a label may share the line with a statement (".table EQUW sub"):
                # the label is a definition, what follows it is not
                st = re.sub(r"^\.[A-Za-z_][A-Za-z_0-9]*\s*", "", st)
                if not st or DIRECT.match(st):
                    continue
                taken.update(w for w in IDENT.findall(st) if w in names)

    src_path = out / "src" / "listing.s"
    src_path.write_text("\n".join(text_lines) + "\n", encoding="latin-1")
    recs = ["version\tmajor=2,minor=0"]
    for i, g in enumerate(segs):
        data = bytearray(g["hi"] - g["lo"])
        for a, b in g["image"].items():
            data[a - g["lo"]] = b
        fn = "seg%02d_%04X.bin" % (i, g["lo"])
        (out / fn).write_bytes(bytes(data))
        recs.append('seg\tid=%d,name="S%02d_%04X",start=0x%06X,size=0x%04X,addrsize=absolute,'
                    'type=rw,oname="%s",ooffs=0' % (i, i, g["lo"], g["lo"], len(data), fn))
    nil = len(segs)              # no image: a reference into it is "a non-code use", so taken
    recs.append('seg\tid=%d,name="REFS",start=0x00F000,size=0x0001,addrsize=absolute,type=bss' % nil)
    recs.append('file\tid=0,name="src/listing.s",size=%d,mtime=0x0,mod=0' % src_path.stat().st_size)
    spans, lines = [], []
    for si, addr, size, n, kind in emits:
        spans.append("span\tid=%d,seg=%d,start=%d,size=%d" % (len(spans), si, addr - segs[si]["lo"], size))
        lines.append("line\tid=%d,file=0,line=%d,type=0,count=0,span=%d" % (len(lines), n, len(spans) - 1))
    spans.append("span\tid=%d,seg=%d,start=0,size=1" % (len(spans), nil))
    ref_line = len(lines)
    lines.append("line\tid=%d,file=0,line=1,type=0,count=0,span=%d" % (ref_line, len(spans) - 1))
    recs += lines + spans
    for k, (name, addr, si) in enumerate(labels):
        if addr is not None:
            recs.append('sym\tid=%d,name="%s",addrsize=absolute,val=0x%04X,%stype=lab%s'
                        % (k, name, addr, "" if si is None else "seg=%d," % si,
                           (",ref=%d" % ref_line) if name in taken else ""))
    (out / "game.dbg").write_text("\n".join(recs) + "\n", encoding="ascii", errors="replace")
    print("%d statements (%d instructions), %d labels (%d address-taken), %d sections: %s"
          % (len(emits), sum(1 for e in emits if e[4] == "insn"), len(labels), len(taken),
             len(segs), ", ".join("&%04X-&%04X" % (g["lo"], g["hi"]) for g in segs)), flush=True)
    return dict(statements=len(emits), instructions=sum(1 for e in emits if e[4] == "insn"),
                labels=len(labels), taken=len(taken), sections=[(g["lo"], g["hi"]) for g in segs])


def main():
    if not (KIT_TOOLS / "analyse.py").exists():
        raise SystemExit("beeb-port-kit not found at %s: set BEEB_PORT_KIT" % KIT)
    sys.path.insert(0, str(KIT_TOOLS))
    import analyse
    up = analyse.vendored()                       # refuses a copy that is not the pin
    cfg_path = ROOT / "tools" / "dataflow_config.py"
    cfg = {}
    exec(cfg_path.read_text(encoding="utf-8"), cfg)
    listing = ROOT / cfg.get("LISTING", "build/paradroid.lst")
    if not listing.exists():
        raise SystemExit("%s is missing: build first" % listing.relative_to(ROOT))
    what = sys.argv[1] if len(sys.argv) > 1 else "report"
    jobs = {"report": ("dataflow.py", ["--out", str(ROOT / "build" / "dataflow")]),
            "annotate": ("annotate.py", ["--out", str(ROOT / "build" / "annotated")]),
            "patterns": ("patterns.py", [])}
    if what not in jobs:
        raise SystemExit("usage: python tools/beebasm_dataflow.py [report|annotate|patterns]")
    inp = ROOT / "build" / "dataflow-in"
    convert(listing, [ROOT / d for d in cfg.get("SOURCES", ("src",))], inp)
    tool, own = jobs[what]
    r = subprocess.run([sys.executable, "-X", "utf8", str(KIT_TOOLS / "analyse.py"), "--run-upstream",
                        str(up), tool, "--root", str(inp), "--build", str(inp),
                        "--config", str(cfg_path)] + own)
    sys.exit(r.returncode)


if __name__ == "__main__":
    main()
