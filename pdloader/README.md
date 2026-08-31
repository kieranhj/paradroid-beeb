# pdloader — the loading intro, by Chris Evans (scarybeasts)

**This directory is a vendored drop and is kept VERBATIM.** It is his source, his style
(`\\` comments, his labels, his layout) and his binaries, so that the next version he sends
is a clean diff against this one. Do not restyle it, do not tidy it, and do not put anything
in here that could live in the game instead.

`build.ps1 -Intro` (and `-Release`, which implies it) assembles `paradroid_intro.asm` in a
second beebasm pass **from inside this directory** — the `PUTFILE` paths at the bottom of the
file are relative to the working directory, and from the project root they resolve to nothing
and the disc comes out with `PINTRO` on it and none of its samples. `tools/make_disc.py`
then splices `PINTRO` and its three data files onto the game's disc behind `PARSWR`.

## What it is

A full-screen MODE 1 picture with the lightning flash, over a **three-channel sample player**
running from zero page at `&40-&FF`: cycle-exact, interrupts off, ~15.6 kHz a channel written
straight at the SN76489's attenuation registers (measured in jsbeeb: 938 writes in 40,000
cycles). Samples, song and lookup tables arrive as one ZX0 stream and are depacked straight
into **one sideways RAM bank**, which the game overwrites with `PARADAT` afterwards.

It owns the machine while it runs — `*TAPE` unloads DFS, System VIA interrupts are off, and
zero page and `&0D00` are backed up and put back. The tune loops until a key is pressed
(KC, 2026-08-29), then it silences the chip, restores what it saved, `*DISC`s and chains.

## Our changes to his file

Seven, each marked `\ PORT:` at the site and listed in the file's own header:

1. **The sideways bank is `PARSWR`'s answer, not 4.** `src/swram.asm` probes the machine before
   any of this runs and leaves the four banks it found at `&0A00`. We borrow the first.
2. **It chains to `PARA`**, not back to itself.
3. **It closes the `*EXEC` file first**, because `!BOOT` is still open as one when it starts and
   `*TAPE` takes the filing system apart underneath it.
4. **It keeps the handover safe across its own run** — see below.
5. **Its data is compressed**: two ZX0 streams instead of eleven loose files, and the bank
   image depacks straight into the bank — see below.
6. **It puts the VIAs back** — see below.
7. **It leaves a MODE 7 "Loading..." screen behind it** (KC, 2026-08-31): the keypress exit
   used to hand the game the abandoned MODE 1 picture, which `PARA`'s own `VDU 22` then
   blanked for the ten seconds of bank loading. `PortLoading` prints `VDU 22,7`, cursor off,
   and the message twice in double height at columns 15 of rows 11 and 12, through `OSWRCH`
   after `restore_os` and before the `*DISC`. The game's mode change is the last thing it
   does before the title now (`../docs/loader-compression.md`), so the message stays up for
   the whole load. **It starts a page lower — `&2600` — to pay for it**: his block ran
   `&2700-&3000` with not one byte spare, and `&2500-&26FF` is free at load time
   (`ADVTAB` is `&1C00-&21FF`, the zero page and `&0D00` backups are `&2200-&23FF`).

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

## PORT 5 — the compressed data

`tools/make_intro_data.py` (run by `build.ps1 -Intro`) builds two streams from the binaries in
this directory:

| | | |
|---|---|---|
| `PINTDAT` | 16,384 → **4,195** | the whole sideways-RAM image — samples, song, lookup tables — laid out at the offsets `init_metadata`'s page constants expect |
| `PINTSCR` | 20,480 → **1,256** | the MODE 1 picture |

**33,912 bytes became 5,451**, eleven catalogue entries became two, and the disc image went from
85,760 to 56,064. At this project's measured DFS rate that is about **5 s off every boot**.

`../src/zx0depack.asm` — the game's own decoder — is INCLUDEd rather than copied, so there is
one of it; it wants six zero-page pointers under the game's names, and `&20-&3F` is free here
between the player's variables and its loop. **His 16K copy loop is gone**: the bank stream
lands at `&4000` and the depacker writes straight into the bank, which is also why the stream
cannot simply be loaded there — a filing-system call has the DFS ROM paged in at `&8000`.

### Where a stream may land, and the trap that is not obvious

- **Not inside `&3000-&7FFF`** for the screen: ZX0 decodes forwards, and at 16:1 the writer is
  19K ahead of the reader by the end, so the stream would be overtaken by its own output.
- **Not at `&0400` either.** That is where the screen stream went first, and 1,256 bytes from
  there reach `&08E7` — through **`&0800-&08FF`, the MOS's sound workspace**. Its 100 Hz
  interrupt still owns the machine at load time and services the channel queues in there; one
  byte written into the stream mid-decode sends the depacker off a wrong offset. It showed up
  as a band of garbage across the credits with correct picture either side of it — 542 wrong
  bytes between `&6A50` and `&754C`, found by diffing the depacked screen against `screen`
  rather than by looking at it. **`&1100` is the home**: DFS's random-access buffer space,
  untouched by a simple `*LOAD` (the same fact that lets the game's code start there), clear of
  every MOS buffer, and free again before `init_player` wants `&0400-&1BFF`.

`ADVTAB` stays raw: 1,536 bytes that are already a two-bits-per-byte packing, and it belongs in
main RAM rather than the bank.

## PORT 6 — the VIAs go back

`init_hardware` retunes both VIAs and nothing put them back. That matters for one thing, and it
is not obvious: the game's `TiBootPal` picks the front end's cold-boot palette (and the LFSR
seed) from **User VIA T1C-L**, expecting the free-running 1 MHz counter the MOS leaves behind.
We handed it over in **continuous mode with a `&00FF` latch**, so it only spans 0-255 and
reloads every 257 µs — phase-locked to a deterministic boot instead of free-running. It landed
on the same value every time and the title came up on the same deck every boot (KC, 2026-08-30).

`PortSaveVia` takes the seven registers we change (both ACRs, System VIA DDRA, both T1 latch
pairs) plus the two IERs at entry; `restore_os` puts them back. **The same save covers a second
one that had not bitten yet**: the game's `InstallIrq` captures the System VIA's ACR and T1
latches to hand back at `UninstallIrq`, so without this the game-over seam would have given the
MOS *our* timer setup rather than the MOS's own.

### And the bug underneath it, which was the game's

Fixing the entropy revealed the real cause of the white title: **`SetPalPlay` reads `disrFlash`
and forces logical 0 to white when it is non-zero**, and `disrFlash` lives in `lowbss`, which is
uninitialised OS leftovers at boot. The game cleared it at `ts_loads` — *after* `TiShow` has
painted the first title. jsbeeb powers up with RAM zeroed so it never showed; **this intro
writes over `&0400-&21FF`, `disrFlash` included**, and made the leftovers real. `TitleSeq`
clears it at its top now. `src/lowbss.asm`'s header carries the rule.

## Still open

- **The gap is silent.** The music stops at the keypress and the game then loads with nothing
  playing. Nothing can be done with this player — it owns the CPU with interrupts off, so no
  disc access can happen underneath it. Accepted by KC, 2026-08-29.
