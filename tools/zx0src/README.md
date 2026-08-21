# zx0src — the reference ZX0 compressor

Einar Saukas' reference ZX0 (v2), BSD-3, from
https://github.com/einar-saukas/ZX0 — `main.c`, `compress.c`,
`optimize.c`, `memory.c` and `zx0.h`, renamed with a `zx0_` prefix.
Unmodified.

`tools/make_disc.py` runs the built `bin/zx0.exe` to compress the four
sideways-RAM bank files into the disc image at build time. Its output is
byte-identical to `tools/zx0.py` (the line-for-line Python port, which
`make_disc.py` uses to round-trip-verify every stream), and both emit
exactly the default-mode format `src/zx0depack.asm` decodes. **Change
any one of the three and you must change the other two.** The exe exists
because the Python optimal parser takes ~60 s per 16K bank; the C one
takes a fraction of a second.

Rebuild (MSYS2 UCRT64 gcc — note `ucrt64\bin` must be on PATH or gcc's
`cc1` dies silently with no diagnostic):

```
set PATH=C:\msys64\ucrt64\bin;%PATH%
gcc -O2 -static -o bin\zx0.exe tools\zx0src\zx0_main.c tools\zx0src\zx0_compress.c tools\zx0src\zx0_optimize.c tools\zx0src\zx0_memory.c
```

`-static` so the exe runs without the MinGW DLLs on PATH. `bin/` is
gitignored (like `beebasm.exe`), so a fresh clone builds it once with
the line above.
