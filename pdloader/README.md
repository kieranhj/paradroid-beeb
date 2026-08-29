# pdloader — the loading intro, by Chris Evans (scarybeasts)

**This directory is a vendored drop and is kept VERBATIM.** It is his source, his style
(`\\` comments, his labels, his layout) and his binaries, so that the next version he sends
is a clean diff against this one. Do not restyle it, do not tidy it, and do not put anything
in here that could live in the game instead.

`build.ps1 -Intro` (and `-Release`, which implies it) assembles `paradroid_intro.asm` in a
second beebasm pass **from inside this directory** — the `PUTFILE` paths at the bottom of the
file are relative to the working directory, and from the project root they resolve to nothing
and the disc comes out with `PINTRO` on it and none of its samples. `tools/make_disc.py`
then splices all twelve files onto the game's disc behind `PARSWR`.

## What it is

A full-screen MODE 1 picture with the lightning flash, over a **three-channel sample player**
running from zero page at `&40-&FF`: cycle-exact, interrupts off, ~15.6 kHz a channel written
straight at the SN76489's attenuation registers (measured in jsbeeb: 938 writes in 40,000
cycles). Samples, song and lookup tables are loaded to `&4000-&7FFF` and copied into **one
sideways RAM bank**, which the game overwrites with `PARADAT` afterwards.

It owns the machine while it runs — `*TAPE` unloads DFS, System VIA interrupts are off, and
zero page and `&0D00` are backed up and put back. The tune loops until a key is pressed
(KC, 2026-08-29), then it silences the chip, restores what it saved, `*DISC`s and chains.

## Our changes to his file

Four, each marked `\ PORT:` at the site and listed in the file's own header:

1. **The sideways bank is `PARSWR`'s answer, not 4.** `src/swram.asm` probes the machine before
   any of this runs and leaves the four banks it found at `&0A00`. We borrow the first.
2. **It chains to `PARA`**, not back to itself.
3. **It closes the `*EXEC` file first**, because `!BOOT` is still open as one when it starts and
   `*TAPE` takes the filing system apart underneath it.
4. **It keeps the handover safe across its own run** — see below.

### The trap PORT 4 exists for

`init_player` unpacks the advance tables to `&0400` and **`&0A00` is inside them**. It is
`advance_tables_len` × **256**, not × 64: the inner loop writes four bytes per packed byte, and
his own comment says so — *"Number of 256 byte tables to output."* So the tables cover
`&0400-&1BFF`, which is why the packed source loads at `&1C00`.

Left in place, the handover is overwritten with an `AND #3` value, the game misses the magic
byte, **falls back to banks 4,5,6,7** and dies on any machine whose sideways RAM is elsewhere —
after appearing to load every bank file correctly, because the `*LOAD`s succeed and only the
first call into bank code notices. It works on a machine that really does have 4-7, which is
how it passed here and failed on KC's (slots 0,1,2,3) on 2026-08-29.

`port_hand` is five bytes in this binary, which nothing here writes; entry copies the handover
into it and `do_exit` writes it back before chaining. **Anything else that needs to survive the
intro needs the same treatment — there is no free page under `&2200`.**

## The artwork is ours, and came back unchanged

`screen` is **byte-identical** to the depacked `src/data/introscr.zx0`, and his `cwSteps` is
`src/data/introfx.asm`'s rows padded from 12 bytes to 16 with our own sky entries — verified
2026-08-29. `tools/export_intro.py` is still where both come from, and those two files stay in
`src/data/` as the committed provenance even though nothing includes them now: the exporter
needs a local `paradroid_ce.lst` to run, which is exactly why generated data is committed.

**If the picture ever changes, it changes in the exporter** and the new `screen` comes from
there — not by editing this copy.

## Not done yet

- **`SCREEN` ships raw, 20,480 bytes.** We already hold it ZX0-packed at 1,256
  (`src/data/introscr.zx0`), and the game's depacker is a 257-byte macro. Doing it saves about
  3.4 s of every boot at this project's measured DFS rate.
- **The ten data files could be one 16K image**, laid out by page where `init_metadata`'s
  `&80`/`&8A`/`&9A`… constants expect it. One catalogue entry and one seek instead of ten.

Both were left out of the first integration deliberately: land the drop-in, then optimise.
