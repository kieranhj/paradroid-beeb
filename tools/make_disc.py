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
hand build/paradroid.ssd (or the padded copy) to an emulator, never
beebasm's direct output.

It also lays the files out physically in BOOT ACCESS ORDER, so the head
never seeks backwards during a load: DFS files are contiguous, and
beebasm's own order (SAVE statement order) put !BOOT and PARA at the END
of the disc, costing a full-disc seek out and back at boot.

The compressor is the reference ZX0 by Einar Saukas, built from
tools/zx0src/ (see the README there) and located by tools/zx0tool.py -
$ZX0, then bin/, then $PATH, with no `.exe` written down anywhere. Its
output is byte-identical to tools/zx0.py, which is the format
src/zx0depack.asm decodes; zx0.py verifies every stream by decompression
before the image is written, whoever compressed it.

Usage: python tools/make_disc.py RAW.ssd OUT.ssd [PADDED.ssd]
                                 [--intro PINTRO.ssd] [--zx0 PATH]
                                 [--packed-dir DIR]
       python tools/make_disc.py --extract-file NAME DIR RAW.ssd

--extract-file and --packed-dir are the two halves of ONE compression,
split so that a make -j build can run the five compressors at once:
--extract-file drops a bank out of the raw image as DIR/NAME.bin, make
turns each .bin into a .zx0 by its own inference rule, and --packed-dir
takes those streams instead of compressing. The result is byte-identical
either way, and it is checked - a stream from --packed-dir goes through
the same zx0.py round-trip and the same in-place margin test, so a stale
.zx0 is a build failure rather than a broken disc.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import zx0
import zx0tool

DEPK_STREAM = 0x3200            # must match main.asm
FNT_STREAM  = 0x3700            # must match main.asm
# Compressed files, and where each one's STREAM is *LOADed to. Four of
# them decompress into a sideways bank, so their stream can sit at the
# shared staging address; PARAFNT decompresses into MAIN RAM at &3000,
# under itself, so its stream has to land where its own output will not
# overtake it -- see in_place_delta() and FNT_STREAM in main.asm.
COMPRESSED = {"PARADAT": DEPK_STREAM, "PARASPR": DEPK_STREAM,
              "PARSPR2": DEPK_STREAM, "PARXFER": DEPK_STREAM,
              "PARAFNT": FNT_STREAM}

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
# PARMAN IS GONE TOO (no-load step 5, 2026-09-09): the briefing's text
# ships as five ZX0 page streams inside the banks, its code is
# bank-resident and its redefine screen is another stream, so nothing
# is loaded for it at all. PARAFNT is the one post-boot load left.
# THREE FILES USED TO SIT WITH IT AND ARE GONE. PARTITL first (no-load
# step 4, 2026-09-07): the title overlay is carried inside PARXFER and
# copied down by TiResident. Then PARBRF and PARALOW (2026-09-09), the
# same way, out of PARSPR2 -- see main.asm's brfImg/lowImg. Each is
# dropped from LAYOUT rather than left in it, because the list doubles
# as the required-file check below and would otherwise fail every build.
# On an --intro build, PINTRO slots in after !BOOT: it is the first
# thing !BOOT runs (docs/intro.md §4).
LAYOUT = ["!BOOT", "PARSWR", "PARA", "PARADAT", "PARASPR", "PARSPR2",
          "PARXFER", "PARAFNT"]

SECTOR = 256

# Build-only SAVEs that must NEVER reach the disc: main.asm writes each
# block of assembled code that ships PACKED under an X-name so that
# tools/pack_overlays.py can read the bytes back out, and briefing.asm's
# old record layout under XREC so that verify_brstreams.py has an oracle.
# THEY ARE DROPPED HERE EXPLICITLY, and that is not belt and braces: the
# first attempt relied on build_image keeping only the names in LAYOUT,
# and it does not -- it appends anything unexpected, which is what lets
# an --intro build carry PINTRO's data files. The four shipped, 7,444
# bytes of them, until the catalogue was actually looked at.
BUILD_ONLY = {"XBRF", "XLOW", "XKR", "XREC"}


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


def check_stream(packed, raw, name):
    """The two guards every stream passes, however it was produced.

    They are HERE and not in the compressor call because --packed-dir
    takes streams the Makefile compressed in a separate process: a stream
    handed in from outside gets exactly the same scrutiny as one this
    tool made itself, including the case that matters most - a stale
    .zx0 left over from a previous build, which decompresses perfectly
    well but not to THIS build's bank.
    """
    if zx0.decompress(packed) != raw:
        raise SystemExit(f"{name}: stream does not decompress to this "
                         "build's file - stale .zx0, or a compressor whose "
                         "output is not the format zx0depack.asm decodes")
    if DEPK_STREAM + len(packed) > 0x8000:
        raise SystemExit(f"{name}: compressed stream overruns main RAM")
    return packed


def compress(zx0_exe, raw, name):
    return check_stream(zx0tool.run_zx0(zx0_exe, raw), raw, name)


def load_packed(packed_dir, raw, name):
    """A stream the caller compressed for us - the Makefile's `-j` path."""
    path = Path(packed_dir) / (name + ".zx0")
    if not path.exists():
        raise SystemExit(f"{path} missing - --packed-dir wants one .zx0 per "
                         "compressed file, made from --extract-file's .bin")
    return check_stream(path.read_bytes(), raw, name)


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
        # EVERY FILE LOADS AND RUNS IN THE HOST: load and exec bits 16-17
        # are 3, i.e. &FFFFxxxx, the only two of the high sixteen bits DFS
        # keeps. beebasm writes 16-bit addresses, so they used to be 0 -
        # and with a second processor attached, 0 means THE SECOND
        # PROCESSOR: PARSWR loaded and ran over there, probed its RAM for
        # sideways banks and reported "FOUND 1" (measured in jsbeeb on a
        # B + 65C02 and a Master + 65C102, issue #18). Without a Tube the
        # bits are ignored, so nothing changes on a plain machine.
        img[a + 6] = (3 << 6 | ((length >> 16) & 3) << 4
                      | 3 << 2 | (start >> 8) & 3)
        img[a + 7] = start & 0xFF

    img[2 * SECTOR:] = data
    return img


def extract_file(name, out_dir, raw_path):
    """Write ONE compressed-file-to-be out of the raw image, uncompressed.

    One file per invocation rather than all five at once, so that each
    .bin is a make target with its own rule and no stamp file stands
    between the raw image and the compressor. Reading a DFS catalogue
    costs nothing; a stamp file would cost correctness, because a stamp
    touched after the files it describes makes them look stale forever.
    """
    if name not in COMPRESSED:
        raise SystemExit(f"{name} is not one of the compressed files: "
                         + ", ".join(COMPRESSED))
    files = read_catalogue(raw_path.read_bytes())
    if name not in files:
        raise SystemExit(f"{raw_path} lacks {name}")
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / (name + ".bin")).write_bytes(files[name]["data"])


def main():
    argv = sys.argv[1:]
    zx0_arg = zx0tool.take_zx0_arg(argv)
    packed_dir = None
    if "--packed-dir" in argv:              # streams compressed elsewhere
        i = argv.index("--packed-dir")
        packed_dir = argv[i + 1]
        del argv[i:i + 2]
    if "--extract-file" in argv:            # one raw file out, then stop
        i = argv.index("--extract-file")
        if len(argv) < i + 4:
            raise SystemExit("--extract-file NAME DIR RAW.ssd")
        extract_file(argv[i + 1], argv[i + 2], Path(argv[i + 3]))
        return
    intro_path = None
    if "--intro" in argv:                   # docs/intro.md §4: -Intro builds
        i = argv.index("--intro")
        intro_path = Path(argv[i + 1])
        del argv[i:i + 2]
    if len(argv) < 2:
        raise SystemExit(__doc__)
    raw_path, out_path = Path(argv[0]), Path(argv[1])
    padded_path = Path(argv[2]) if len(argv) > 2 else None

    # Only needed when we are doing the compressing ourselves; with
    # --packed-dir there may be no compressor on this machine at all.
    zx0_exe = None if packed_dir else zx0tool.find_zx0(zx0_arg)

    img = raw_path.read_bytes()
    files = read_catalogue(img)
    dropped = sorted(n for n in files if n in BUILD_ONLY)
    for n in dropped:
        del files[n]
    missing = [n for n in LAYOUT if n not in files]
    if missing:
        raise SystemExit(f"raw image lacks {missing} - loader and disc "
                         "would disagree")

    if intro_path:
        # Splice the intro build in: scarybeasts' PINTRO and ALL of its data
        # (pdloader/, its own beebasm pass), laid after PARSWR, and
        # "*RUN PINTRO" patched in front of "*RUN PARA".
        #
        # AFTER PARSWR, NOT BEFORE IT: the intro borrows a sideways bank for
        # its samples and takes the number from PARSWR's handover, so the
        # probe has to have run first. PINTRO chains to PARA itself, which is
        # why it closes the exec file before *TAPE -- see pdloader's header.
        # The !BOOT line below is then never read, and is left in as the
        # fallback if the intro is ever changed to exit by returning.
        #
        # The default build takes this branch never — no PINTRO on the
        # disc and an untouched !BOOT, so the option cannot half-apply.
        intro_files = read_catalogue(intro_path.read_bytes())
        if "PINTRO" not in intro_files:
            raise SystemExit(f"{intro_path} lacks PINTRO")
        at = LAYOUT.index("PARSWR") + 1
        for name, entry in intro_files.items():
            if name in files:
                raise SystemExit(f"intro file {name} collides with the game's")
            files[name] = entry
            LAYOUT.insert(at, name)
            at += 1
        if len(files) > 31:
            raise SystemExit(f"{len(files)} files - a DFS catalogue holds 31")
        boot = files["!BOOT"]["data"]
        marker = b"*RUN PARA\r"
        if marker not in boot:
            raise SystemExit("!BOOT lacks '*RUN PARA' - cannot wire PINTRO")
        files["!BOOT"]["data"] = boot.replace(
            marker, b"*RUN PINTRO\r" + marker, 1)
        print(f"make_disc: INTRO build - PINTRO + {len(intro_files) - 1} data "
              "files wired into !BOOT")

    if dropped:
        print("make_disc: dropped build-only " + ", ".join(dropped))
    report = []
    for name, stream in COMPRESSED.items():
        raw = files[name]["data"]
        packed = (load_packed(packed_dir, raw, name) if packed_dir
                  else compress(zx0_exe, raw, name))
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

    print("make_disc: banks compressed"
          + (" (streams from %s)" % packed_dir if packed_dir else ""))
    print("\n".join(report))
    print(f"  image   {len(img):6d} -> {len(out):6d}")


if __name__ == "__main__":
    main()
