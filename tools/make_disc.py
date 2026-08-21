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
COMPRESSED = ["PARADAT", "PARASPR", "PARSPR2", "PARXFER"]

# Physical layout, first file at sector 2. Boot access order: !BOOT,
# PARA, then PARDEPK and the four banks, then the title, then (after
# the title is dismissed) the font and the low overlay.
LAYOUT = ["!BOOT", "PARA", "PARDEPK", "PARADAT", "PARASPR", "PARSPR2",
          "PARXFER", "PARTITL", "PARAFNT", "PARALOW"]

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
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    raw_path, out_path = Path(sys.argv[1]), Path(sys.argv[2])
    padded_path = Path(sys.argv[3]) if len(sys.argv) > 3 else None

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

    report = []
    for name in COMPRESSED:
        raw = files[name]["data"]
        packed = compress(zx0_exe, raw, name)
        files[name]["data"] = packed
        files[name]["load"] = DEPK_STREAM
        files[name]["exec"] = DEPK_STREAM
        report.append(f"  {name:7s} {len(raw):5d} -> {len(packed):5d}")

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
