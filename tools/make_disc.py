#!/usr/bin/env python3
"""
make_disc.py - post-process beebasm's SSD into the shipping disc image.

beebasm assembles and SAVEs every file uncompressed; this tool rewrites
the image so that the four 16K sideways-RAM bank files (PARADAT, PARASPR,
PARSPR2, PARXFER) are ZX0-compressed, with their catalogue load address
moved to DEPK_STREAM where the boot depacker (the PARDEPK overlay,
src/zx0depack.asm via main.asm) expects the stream. Measured in jsbeeb:
the four raw banks took 22.9M cycles (11.4 s) to load and copy up;
compressed they are 25.2K instead of 63.6K on disc.

THE RAW IMAGE IS NOT BOOTABLE. UnpackBankIn JMPs the PARDEPK depacker at
every bank load, so the loader only works on this tool's output - always
hand build/PARADROID.SSD (or the padded copy) to an emulator, never
beebasm's direct output.

It also lays the files out physically in BOOT ACCESS ORDER, so the head
never seeks backwards during a load: DFS files are contiguous, and
beebasm's own order (SAVE statement order) put !BOOT and PARA at the END
of the disc, costing a full-disc seek out and back at boot.

The compressor is bin/zx0.exe - the reference ZX0 by Einar Saukas, built
from tools/zx0src/ (see the README there). Its output is byte-identical
to tools/zx0.py, which is the format src/zx0depack.asm decodes; zx0.py
verifies every stream by decompression before the image is written.

Usage: python tools/make_disc.py RAW.SSD OUT.SSD [PADDED.SSD]
"""

import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import zx0

DEPK_STREAM = 0x3200            # must match main.asm
FNT_STREAM  = 0x3700            # must match main.asm
# Compressed files, and where each one's STREAM is *LOADed to. Four of
# them decompress into a sideways bank, so their stream can sit at the
# shared staging address; PARAFNT decompresses into MAIN RAM at &3000,
# under itself, so its stream has to land where its own output will not
# overtake it -- see in_place_delta() and FNT_STREAM in main.asm.
COMPRESSED = {"PARADAT": DEPK_STREAM, "PARASPR": DEPK_STREAM,
              "PARSPR2": DEPK_STREAM, "PARXFER": DEPK_STREAM,
              "PARMAN":  DEPK_STREAM, "PARAFNT": FNT_STREAM}

# Where each compressed file's output goes, for the in-place check. Only
# the ones whose stream and output share memory actually need it.
UNPACK_DEST = {"PARAFNT": 0x3000}


def in_place_delta(packed, raw):
    """max(write_index - input bytes consumed) over the whole decode.

    ZX0 unpacks forwards, so a stream that shares memory with its own
    output is safe only while the writer stays behind the reader. The
    margin is a property of THIS stream, not of the compression ratio:
    a literal run copies 1:1 plus its flag bits, so the gap can grow
    locally however good the average is. Walk the decode and measure it.
    Landing address must be >= dest + delta + 1.
    """
    out = bytearray(); pos = 0; bit_mask = 0; bit_byte = 0
    backtrack = [None]; worst = -1 << 30

    def note():
        nonlocal worst
        g = (len(out) - 1) - pos
        if g > worst:
            worst = g

    def bit():
        nonlocal bit_mask, bit_byte, pos
        if backtrack[0] is not None:
            b = backtrack[0] & 1
            backtrack[0] = None
            return b
        if not bit_mask:
            bit_byte = packed[pos]
            pos += 1
            bit_mask = 128
        b = 1 if (bit_byte & bit_mask) else 0
        bit_mask >>= 1
        return b

    def gamma(invert):
        v = 1
        while not bit():
            d = bit()
            if invert:
                d ^= 1
            v = (v << 1) | d
        return v

    last_offset = zx0.INITIAL_OFFSET
    state = "literals"
    while True:
        if state == "literals":
            for _ in range(gamma(False)):
                out.append(packed[pos]); pos += 1; note()
            state = "new" if bit() else "copy"
        elif state == "copy":
            for _ in range(gamma(False)):
                out.append(out[-last_offset]); note()
            state = "new" if bit() else "literals"
        else:
            msb = gamma(True)
            if msb == 256:
                break
            lsb = packed[pos]; pos += 1
            last_offset = msb * 128 - (lsb >> 1)
            backtrack[0] = lsb
            for _ in range(gamma(False) + 1):
                out.append(out[-last_offset]); note()
            state = "new" if bit() else "literals"
    if bytes(out) != raw:
        raise SystemExit("in_place_delta: decode disagrees with the source")
    return worst + 1

# Physical layout, first file at sector 2. Boot access order: !BOOT,
# PARSWR (the sideways RAM detector, src/swram.asm -- !BOOT runs it
# before the game), PARA, then the four banks (PARDEPK is gone -- the depacker is resident
# in the code image since 2026-08-29), then the title, then (after
# the title is dismissed) the font and the low overlay.
# PARBRF (the briefing driver, loaded by TiShow on every title) and
# PARMAN (the briefing text, loaded only when the title times out) sit
# with PARTITL: the three are all title-time loads. Layer 11f.
# On an --intro build, PINTRO slots in after !BOOT: it is the first
# thing !BOOT runs (docs/intro.md §4).
LAYOUT = ["!BOOT", "PARSWR", "PARA", "PARADAT", "PARASPR", "PARSPR2",
          "PARXFER", "PARTITL", "PARBRF", "PARMAN", "PARAFNT", "PARALOW"]

SECTOR = 256


def read_catalogue(img):
    files = {}
    for i in range(img[0x105] // 8):
        e = 8 * (i + 1)
        name = img[e:e + 7].decode("ascii").rstrip()
        dirc = chr(img[e + 7] & 0x7F)
        a = 0x100 + e
        load = img[a] | (img[a + 1] << 8)
        exe = img[a + 2] | (img[a + 3] << 8)
        extra = img[a + 6]
        length = (img[a + 4] | (img[a + 5] << 8)) | (((extra >> 4) & 3) << 16)
        load |= (((extra >> 2) & 3) << 16)
        exe |= (((extra >> 6) & 3) << 16)
        start = (img[a + 7] | ((extra & 3) << 8)) * SECTOR
        files[name] = {"dir": dirc, "load": load, "exec": exe,
                       "data": bytes(img[start:start + length])}
    return files


def compress(zx0_exe, raw, name):
    with tempfile.TemporaryDirectory() as td:
        src = Path(td) / "in.bin"
        dst = Path(td) / "out.zx0"
        src.write_bytes(raw)
        subprocess.run([str(zx0_exe), "-f", str(src), str(dst)],
                       check=True, capture_output=True)
        packed = dst.read_bytes()
    if zx0.decompress(packed) != raw:
        raise SystemExit(f"{name}: zx0.exe stream fails zx0.py round-trip")
    if DEPK_STREAM + len(packed) > 0x8000:
        raise SystemExit(f"{name}: compressed stream overruns main RAM")
    return packed


def build_image(files, title, cycle, opt):
    order = [n for n in LAYOUT if n in files]
    order += [n for n in files if n not in order]   # anything unexpected
    if len(order) > 31:
        raise SystemExit("more than 31 files")

    sector = 2
    placed = []                                     # (name, start_sector)
    data = bytearray()
    for name in order:
        f = files[name]
        placed.append((name, sector))
        data += f["data"]
        pad = -len(f["data"]) % SECTOR
        data += bytes(pad)
        sector += (len(f["data"]) + SECTOR - 1) // SECTOR

    img = bytearray(2 * SECTOR + len(data))
    img[0:8] = title[:8].ljust(8, b"\0")
    img[0x100:0x104] = title[8:12].ljust(4, b"\0")
    img[0x104] = cycle
    img[0x105] = len(placed) * 8
    total = 800                                     # 80 tracks, as beebasm
    img[0x106] = (opt & 3) << 4 | (total >> 8)
    img[0x107] = total & 0xFF

    # catalogue entries in descending start-sector order, as DFS keeps them
    for i, (name, start) in enumerate(reversed(placed)):
        f = files[name]
        e = 8 * (i + 1)
        img[e:e + 7] = name.encode("ascii").ljust(7)
        img[e + 7] = ord(f["dir"])
        a = 0x100 + e
        length = len(f["data"])
        img[a + 0] = f["load"] & 0xFF
        img[a + 1] = (f["load"] >> 8) & 0xFF
        img[a + 2] = f["exec"] & 0xFF
        img[a + 3] = (f["exec"] >> 8) & 0xFF
        img[a + 4] = length & 0xFF
        img[a + 5] = (length >> 8) & 0xFF
        img[a + 6] = (((f["exec"] >> 16) & 3) << 6 | ((length >> 16) & 3) << 4
                      | ((f["load"] >> 16) & 3) << 2 | (start >> 8) & 3)
        img[a + 7] = start & 0xFF

    img[2 * SECTOR:] = data
    return img


def main():
    argv = sys.argv[1:]
    intro_path = None
    if "--intro" in argv:                   # docs/intro.md §4: -Intro builds
        i = argv.index("--intro")
        intro_path = Path(argv[i + 1])
        del argv[i:i + 2]
    if len(argv) < 2:
        raise SystemExit(__doc__)
    raw_path, out_path = Path(argv[0]), Path(argv[1])
    padded_path = Path(argv[2]) if len(argv) > 2 else None

    root = Path(__file__).parent.parent
    zx0_exe = root / "bin" / "zx0.exe"
    if not zx0_exe.exists():
        raise SystemExit(f"{zx0_exe} missing - build it from tools/zx0src/ "
                         "(see the README there)")

    img = raw_path.read_bytes()
    files = read_catalogue(img)
    missing = [n for n in LAYOUT if n not in files]
    if missing:
        raise SystemExit(f"raw image lacks {missing} - loader and disc "
                         "would disagree")

    if intro_path:
        # Splice the intro build in: PINTRO from its own beebasm pass,
        # laid after !BOOT, and "*RUN PINTRO" patched in front of
        # "*RUN PARA" so it runs (and exits into) the boot sequence.
        # The default build takes this branch never — no PINTRO on the
        # disc and an untouched !BOOT, so the option cannot half-apply.
        intro_files = read_catalogue(intro_path.read_bytes())
        if "PINTRO" not in intro_files:
            raise SystemExit(f"{intro_path} lacks PINTRO")
        files["PINTRO"] = intro_files["PINTRO"]
        LAYOUT.insert(1, "PINTRO")
        boot = files["!BOOT"]["data"]
        marker = b"*RUN PARA\r"
        if marker not in boot:
            raise SystemExit("!BOOT lacks '*RUN PARA' - cannot wire PINTRO")
        files["!BOOT"]["data"] = boot.replace(
            marker, b"*RUN PINTRO\r" + marker, 1)
        print("make_disc: INTRO build - PINTRO wired into !BOOT")

    report = []
    for name, stream in COMPRESSED.items():
        raw = files[name]["data"]
        packed = compress(zx0_exe, raw, name)
        dest = UNPACK_DEST.get(name)
        note = ""
        if dest is not None:
            need = dest + in_place_delta(packed, raw)
            if stream < need:
                raise SystemExit(
                    f"{name}: stream at {stream:#06x} would be overtaken by "
                    f"its own output at {dest:#06x} - needs {need:#06x} or "
                    f"higher. Raise FNT_STREAM in main.asm AND here.")
            note = f"  (in place, {stream - need} B of margin)"
        files[name]["data"] = packed
        files[name]["load"] = stream
        files[name]["exec"] = stream
        report.append(f"  {name:7s} {len(raw):5d} -> {len(packed):5d}{note}")

    out = build_image(files, img[0:8] + img[0x100:0x104], img[0x104],
                      (img[0x106] >> 4) & 3)
    out_path.write_bytes(out)
    if padded_path:
        padded_path.write_bytes(out.ljust(200 * 1024, b"\0"))

    print("make_disc: banks compressed")
    print("\n".join(report))
    print(f"  image   {len(img):6d} -> {len(out):6d}")


if __name__ == "__main__":
    main()
