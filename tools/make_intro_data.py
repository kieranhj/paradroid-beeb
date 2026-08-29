#!/usr/bin/env python3
"""
make_intro_data.py - the loading intro's two compressed streams.

The intro (pdloader/, scarybeasts', vendored) shipped its data as eleven
loose files: seven samples, the song, two lookup tables and a 20K screen,
35,448 bytes in all and eleven catalogue entries. This builds two:

  PINTDAT   the whole 16K sideways-RAM image - samples, song and lookup
            tables laid out at the offsets init_metadata's page constants
            expect - ZX0-compressed. The intro *LOADs the stream at &4000
            and depacks it STRAIGHT INTO THE BANK, so his 16K copy loop
            goes as well.
  PINTSCR   the 20,480-byte MODE 1 picture, ZX0-compressed, depacked from
            &1100 (DFS buffer space, untouched by a simple *LOAD) to &3000.

ADVTAB is left alone: 1,536 bytes that are already a 2-bits-per-byte
packing, and it loads to &1C00 in main RAM rather than into the bank.

THE LAYOUT TABLE BELOW IS THE COUPLING. It came from the load addresses in
his own OSCLI strings (`LOAD BDRUM 4000` and friends), which were all
&4000-based and copied up by +&4000, so bank offset = load address -
&4000. Those strings are gone now, so if a future drop moves a sample this
table has to move with it - `init_metadata`'s `addr_sample_starts` pages
are the cross-check, and they are page numbers in the BANK (&80 = &8000 =
offset 0). The overlap and size assertions below catch the gross cases.

Usage: python tools/make_intro_data.py [outdir]     (default: build/)
"""

import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import zx0

BANK_SIZE = 0x4000
BANK_BASE = 0x8000

# file -> offset in the 16K bank image. See the docstring: this is his
# `LOAD <name> <addr>` minus &4000, and the bank page it lands on.
LAYOUT = {
    "sample.bdrum":    0x0000,      # bank &8000, sample 1
    "sample.sdrum":    0x0B00,      # bank &8B00, sample 2
    "sample.shaker":   0x1600,      # bank &9600, sample 3
    "sample.bass128":  0x1A00,      # bank &9A00, sample 4
    "sample.bright":   0x1C00,      # bank &9C00, sample 5
    "sample.tri32":    0x2800,      # bank &A800, sample 6
    "sample.guitar":   0x2A00,      # bank &AA00, sample 7
    "conv.out":        0x3B00,      # bank &BB00, addr_song_start
    "lookup_tables.out": 0x3E00,    # bank &BE00, addr_lookup_tables
}
SCREEN = "screen"


def compress(zx0_exe, raw, name):
    """bin/zx0.exe, round-trip-verified through tools/zx0.py. Same rule as
    make_disc.py: the reference compressor writes it, our decoder proves
    it, and src/zx0depack.asm is what reads it on the Beeb."""
    with tempfile.TemporaryDirectory() as td:
        src, dst = Path(td) / "in.bin", Path(td) / "out.zx0"
        src.write_bytes(raw)
        subprocess.run([str(zx0_exe), "-f", str(src), str(dst)],
                       check=True, capture_output=True)
        packed = dst.read_bytes()
    if zx0.decompress(packed) != raw:
        raise SystemExit(f"{name}: zx0.exe stream fails the zx0.py round-trip")
    return packed


def build_bank(src_dir):
    """The 16K image, with every slot checked against its neighbour."""
    img = bytearray(BANK_SIZE)
    placed = []
    for name, off in sorted(LAYOUT.items(), key=lambda kv: kv[1]):
        data = (src_dir / name).read_bytes()
        end = off + len(data)
        if end > BANK_SIZE:
            raise SystemExit(f"{name}: {len(data)} B at {off:#06x} runs past "
                             f"the end of the bank")
        for pname, pstart, pend in placed:
            if off < pend and pstart < end:
                raise SystemExit(f"{name} at {off:#06x}..{end:#06x} overlaps "
                                 f"{pname} at {pstart:#06x}..{pend:#06x}")
        img[off:end] = data
        placed.append((name, off, end))
        print(f"  {name:20s} {BANK_BASE + off:#06x} - {BANK_BASE + end:#06x}"
              f"  {len(data):6d} B")
    return bytes(img)


def main():
    root = Path(__file__).parent.parent
    src_dir = root / "pdloader"
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "build"
    out_dir.mkdir(parents=True, exist_ok=True)

    zx0_exe = root / "bin" / "zx0.exe"
    if not zx0_exe.exists():
        raise SystemExit(f"{zx0_exe} missing - build it from tools/zx0src/")

    print("make_intro_data: the sideways-RAM image")
    bank = build_bank(src_dir)
    packed_bank = compress(zx0_exe, bank, "PINTDAT")

    screen = (src_dir / SCREEN).read_bytes()
    if len(screen) != 20480:
        raise SystemExit(f"{SCREEN}: {len(screen)} B, expected a 20K MODE 1 "
                         "screen")
    packed_screen = compress(zx0_exe, screen, "PINTSCR")

    # Where the intro *LOADs each stream, and what it would collide with.
    # PINTDAT lands at &4000 and depacks into the bank, so it only has to
    # stay out of the sideways window. PINTSCR lands at &0400 and depacks to
    # &3000-&7FFF: it cannot be inside the picture it writes (ZX0 decodes
    # forwards and the writer runs 19K ahead of the reader by the end), and
    # it must stop short of &1C00, where ADVTAB is sitting by then.
    if 0x4000 + len(packed_bank) > 0x8000:
        raise SystemExit("PINTDAT stream would not fit at &4000")
    if 0x1100 + len(packed_screen) > 0x1C00:
        raise SystemExit("PINTSCR stream at &1100 would reach ADVTAB at &1C00")

    (out_dir / "PINTDAT").write_bytes(packed_bank)
    (out_dir / "PINTSCR").write_bytes(packed_screen)

    was = sum((src_dir / n).stat().st_size for n in LAYOUT) + len(screen)
    now = len(packed_bank) + len(packed_screen)
    print(f"  PINTDAT   {BANK_SIZE:6d} -> {len(packed_bank):6d}")
    print(f"  PINTSCR   {len(screen):6d} -> {len(packed_screen):6d}")
    print(f"  intro data {was:6d} -> {now:6d} bytes on disc "
          f"({(was - now) / 5600:.1f} s of DFS)")


if __name__ == "__main__":
    main()
