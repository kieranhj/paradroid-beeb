---
name: beeb-identical-build
description: Prove that a change meant to be mechanical left the BBC Micro port's binary untouched - by comparing disc images and catalogue files byte for byte - or, where addresses legitimately moved, that no instruction was added, removed or reordered, by diffing the two beebasm listings reduced to opcode streams. Use when splitting a source file, reordering includes, changing the build script, widening a table, relocating data, or any change whose commit message wants to say "byte-identical".
---

# Byte-identical build and listing-stream diff

Two checks for a change that should not alter behaviour. The first is for a change that should
not alter the disc *at all*; the second is for a change that legitimately moves addresses and
must be proved to have done nothing else. Both are faster than the oracle and, for this class of
change, stronger.

**Baseline:** build the OLD tree first and keep its image and listing somewhere the new build will not overwrite
**Always differs:** `!BOOT`, which stamps the build - so compare per file, not per image, when it does
**Listing:** `build/PARADROID.lst`, which `build.ps1` writes with beebasm's `-v`
**Reducer:** `tools/listing_stream.py` (checked in 2026-09-08; beebasm's listing emits only instructions and labels, which is what makes it exact)

## Steps

1. **Build the old tree into a baseline and keep it.** Before touching the source, or from a
   `git stash` / `git worktree` of `HEAD`. Copy `build/` aside; the next build overwrites it.

   ```powershell
   .\build.ps1
   Copy-Item build build-old -Recurse
   ```

2. **Make the change and build again**, with the same flags. The `-D` symbols the project
   passes (`RELEASE`, `MUSIC_AKL`, `GFX_CPC`, ...) are in `CLAUDE.md` "Build"; a different flag
   set is a different binary and the comparison means nothing.

3. **Compare the images.** Identical is the pass and the end.

   ```bash
   cmp build-old/PARADROID.SSD build/PARADROID.SSD
   ```

   The disc is ZX0-compressed per file by `tools/make_disc.py`, which is deterministic, so an
   identical source really does give an identical image - but a one-byte source change moves a
   whole compressed stream, so this check answers "nothing at all changed" and nothing softer.

4. **If they differ only where they should, compare per file.** `!BOOT` carries the build
   stamp and the debug-flag line, so the image differs there whenever the stamp does. Extract
   the files that must not have changed (`PARA`, `PARADAT`, `PARASPR`, `PARSPR2`, `PARXFER`,
   `PARAFNT`, `PARALOW`, `PARMAN`, `PARSWR`) from both catalogues and compare those. There is no
   extractor checked in; it is a few lines over the DFS catalogue (sectors 0 and 1: names at
   `&0008`, load/exec/length/start sector at `&0108`, eight bytes a file), and
   `tools/make_disc.py` already writes that structure, so read it there rather than from a
   manual. Say in the commit which files were compared.

5. **When addresses legitimately moved - a width change, a data removal, a relocation - diff
   the listing streams instead.** The reducer is `tools/listing_stream.py`; read its header
   before trusting a result.

   ```bash
   python tools/listing_stream.py build-old/PARADROID.lst > old.txt
   python tools/listing_stream.py build/PARADROID.lst     > new.txt
   diff old.txt new.txt && echo "stream identical, $(wc -l < new.txt) entries"
   ```

   Today's tree reduces to **23,528 instructions** (2026-09-08, `no-load`, DEV flags). Data
   directives emit no instruction line at all, so a pure data change gives an identical stream
   by construction - which is the point, and also the limit.

   Each entry is one emitted instruction as its opcode and operand length. An identical stream
   proves no instruction was added, removed or reordered, so every difference in the image is a
   width change or data. Then the smoke test only has to confirm the new addresses do not
   collide - and on this project, that the bank gauges and `code_end` still fit.

6. **Know what it cannot validate.** Two things, and the first is measured (kit, 2026-09-07,
   on its own template, and the reducer here reproduces it): **the stream cannot see an
   operand's value.** A build against itself gives 0 differences, one inserted instruction gives
   1, and changing a constant from 8 to 4 gives 0.
   It proves the shape of the code, not its constants - which is why step 4's byte-for-byte
   comparison comes first and this is the fallback. Second, a change that *intentionally* alters
   instructions - Paradroid's SCANSTEP tail folding - fails the stream diff by design; that is
   the oracle's job (`beeb-buffer-oracle`). Do not weaken the reducer to make such a change
   pass.

7. **Apply the same check to generated data.** `src/data/` is committed exactly so that an
   exporter change shows up as a diff, and `build.ps1` does NOT run the exporters - so after
   running one, `git diff --stat src/data/` is the cheap form of this check and an unexpected
   file in it is the finding. (Edge Grinder caught a 28-byte move in every sprite bank that way,
   from two tables being emitted in the other order.)

8. **Put the result in the commit body**: "byte-identical" with the files compared, or
   "listing stream identical, N instructions" with the count.
