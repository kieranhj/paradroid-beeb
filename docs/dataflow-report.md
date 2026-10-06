# Static analysis of the shipping code (2026-10-06)

**Paradroid's linked 6502 has about 270 bytes that static analysis says could go at no cycle
cost, 75 of them in the main code image.** These are leads, not edits. Every one is checked
against the source and goes through the buffer oracle before it lands. Paradroid has shipped, so
claim them only when something needs the room. When that happens, the main code image
(`&1100-&2FA5`) is where a byte is worth most: `sprite.asm`'s `SprSplitOK` header records it
once running down to eleven bytes.

The analyses are Eben Upton's (`tools/dataflow` in
[beebgame](https://github.com/ebenupton/beebgame), MIT). They were written for his engine and used
on Commando to take out about 400 bytes behind a replay gate. They run here unmodified, through
beeb-port-kit's vendored and hash-checked copy, and nothing of them is copied into this repo.

## Running it

```powershell
.\build.ps1                          # a fresh build/paradroid.lst
python tools/beebasm_dataflow.py     # ~9 s -> build/dataflow/
```

It needs Python 3 and beeb-port-kit at `../beeb-port-kit`, or wherever `$BEEB_PORT_KIT` points.
It reads `build/paradroid.lst` only and never reassembles. `build/` is gitignored, so
everything it writes is too.

| Output | What it is |
| --- | --- |
| `build/dataflow/report.md` | Findings ranked by bytes: address, routine, instruction, why, and the evidence (registers live after it, values known before it) |
| `build/dataflow/report.json` | The same, plus per-line liveness and known values for every instruction |
| `build/dataflow/abi.md` | Every routine reached by `JSR`: registers and flags read on entry, what it defines, what callers read after the return, and register values known at the call sites |
| `build/dataflow/annotated/src/listing.s.txt` | The whole program, every instruction prefixed with live-in, live-out and known values |
| `build/dataflow-in/src/listing.s` | The listing-shaped file the findings point into |

`tools/dataflow_config.py` names the interrupt (`IrqHandler`, the only thing ever stored in
`IRQ1V`). If another handler is ever installed, add it there. A handler left out is analysed
as ordinary code, and every claim about the bytes it writes is then wrong.

### What a beebasm build can't tell it

beeb-port-kit's converter works from Baron builds. This repo's `tools/beebasm_dataflow.py` is
the beebasm equivalent, and its header gives the details. Three limits matter when reading
the results:

- **No source lines.** beebasm's `-v` listing prints resolved operands (`LDA &0A00`), so a
  finding gives an **address and the nearest label** (`dp_x`, `RuptTimer`). Search `src/` by
  that label, or open `build/paradroid.lst` at the address.
- **"Address taken" is guessed from the sources.** Any label named other than as a
  `JSR`/`JMP`/branch target counts as possibly reached through a table (1,368 of 3,219). That
  errs on the safe side: it hides some findings rather than inventing any.
- **Sections are inferred** from address jumps. The 15 found match the listing's own memory map
  at its end, and the table below names them.

The whole-program range analysis (`annotate`, value ranges at every instruction) has not been
run here. It ran out of its step budget on puzzle-beeble, a program 40% of this size
([beebgame#2](https://github.com/ebenupton/beebgame/issues/2)). The tool can run it
(`python tools/beebasm_dataflow.py annotate`, then `patterns`). It converged on Edge Grinder
(4,051 instructions, 56 s), but expect it to run out of steps here and print a NOT-sound
warning. Setting `$env:DATAFLOW_BUDGET` raises the limit (upstream's is 3,000,000 steps a round).

## What it found

22,556 instructions (the listing's 22,549 of 2026-09-11, plus the commits since). 371 findings,
**up to 274 bytes**. The total is an upper bound, because findings overlap.

| Where | Range | Findings | Bytes |
| --- | --- | ---: | ---: |
| **Main code image** | `&1100-&2FA5` | 60 | **75** |
| Bank, slot 3: transfer game (`xfer`) | `&8000-&BFA6` | 71 | 84 |
| Bank, slot 0: data and code (`data`) | `&8000-&BF7F` | 65 | 66 |
| Bank, slot 2: `sprite2` | `&8000-&BED2` | 82 | 16 |
| Bank, slot 1: `sprite` | `&8000-&BF6A` | 70 | 10 |
| Overlays and loaders (`&0400`, `&0900`, `&0D60`, `&1900`, `&4572`) | | 23 | 23 |

| Category | Count | Bytes | What it is |
| --- | ---: | ---: | --- |
| `imm_load` | 39 | 78 | `LDr #v` when the register already holds `v` |
| `jmp_to_branch` | 42 | 42 | A `JMP` where a flag is known, which can be a branch |
| `dead_insn` | 18 | 39 | An instruction whose every result is unused |
| `branch_over_jmp` | 12 | 36 | `Bxx skip : JMP T`, which can be the inverted branch to `T` |
| `clc_sec` | 31 | 31 | `CLC`/`SEC` when the carry is already known |
| `reg_xfer` | 29 | 29 | `LDA m` when X or Y already holds it (`TXA`/`TYA`), and the reverse |
| `tail_call` | 133 | 9 | `JSR x : RTS` that can be `JMP x`. Only 9 save a byte; the rest share their `RTS` |
| `cmp_zero` | 4 | 8 | `CMP #0` when N and Z already reflect the register |
| `branch_never` | 1 | 2 | A conditional branch never taken |
| `branch_always` | 62 | 0 | Information only: mostly deliberate always-taken branches |

### Checked by hand

| Finding | Verdict |
| --- | --- |
| `ScrollAddS`: `BCC sas_x` after `CMP #LO(BUF_SIZE)` is never taken | **Correct, and a constant coincidence.** `BUF_SIZE` is 10,240, so the low byte is 0 and `CMP #0` always sets C. The low-byte half of the wrap test is dead today and would revive if `BUF_SIZE` changed. Leave it, or delete it with an `ASSERT LO(BUF_SIZE) = 0` beside it |
| `xfer.asm`: eight exits `LDA #0 : RTS` (`xtk_run`, `xtk_play`, `xpl_*`, `xfe_run`, `xfr_run`) | **Correct for today's callers.** None reads A after the return. It looks like a return value carried over from the C64 original that the port never uses. 16 bytes |
| `door.asm` `dp_x`: `LDX dpSaveX : RTS`, and the same at `dp_stepped` and `DrawDoorTile` | **Correct for today's callers.** X is restored for callers that never read it again |
| `sprite.asm` `SprSplitOK`: the final `LDA sprSplit` | **Correct, and the comments are stale.** The header says "the caller branches on these flags", but the only caller (`main.asm:2536`, "A = sprSplit, and one subtract maps it") returns at once, and nothing above it reads A |

None of the four is a bug. Paradroid shipped after a month of play, and it shows.

## Claiming the bytes

### First, the rules

1. **Never touch interrupt or raster code for bytes.** That's `IrqHandler`, `RuptTimer`,
   `SetupRupture` and everything they call. Most rewrites here change cycle counts on some
   path (`branch_over_jmp` takes one fewer branch, `jmp_to_branch` costs a cycle more across a
   page), and these routines' cycles are the rupture's position. `RuptTimer` has a 3-byte
   finding; leave it.
2. **One routine, or one category in one bank, per batch.** Findings overlap: removing a dead
   load can make the store before it dead too. Rebuild and rerun the analysis after every
   batch, because every address after the change moves.
3. **Read every finding against the source before editing.** Discard it if:
   - it rests on a **constant** whose value is a coincidence (`imm_load` and `branch_never`
     findings where the "known" value comes from an equate such as `LO(BUF_SIZE)`), unless
     you add the `ASSERT` that makes the coincidence a rule;
   - it sits in a routine whose register contract is **documented in a comment**, where the
     finding holds only for today's callers (`dead_insn` on a register restore). Update the
     comment as part of the change, so the next caller doesn't rely on what was removed;
   - it is in a **delay loop or a timed write sequence**;
   - it rewrites code transliterated from the C64 original where keeping the original's shape
     is the point, unless the bytes are actually needed. That's the four rules' "the original
     is the specification".
4. **Every edit is a decision.** Record it in `docs/decisions.md` with its byte count, like any
   other change from the original.

### The gate, for every batch

1. **Build both ways and compare:** `.\build.ps1`, then `make check-ps1`. The two builds must
   still agree.
2. **Run the listing stream** (`tools/listing_stream.py`) against the previous build. The
   instructions removed or changed must be exactly the ones the batch meant to change.
3. **Run the buffer oracle:** CTRL+R `RedrawAll`, byte for byte, at odd and even `mapHX`,
   non-zero `line` and a diagonal, with all three draw call sites NOPed and the view settled.
   Use the `beeb-buffer-oracle` skill and `docs/ram-pass.md`'s checklist. This is required for
   anything in the draw, scroll, sprite or door paths.
4. **Check frame drops** (`beeb-frame-drops`) for anything in the main loop.
5. **Check the sound** (`beeb-sound-verify`) for anything the sound player or transfer game
   reaches.
6. **Play it:** a deck, a lift, a transfer won and lost, and a game over. Then say in the
   commit how many bytes were freed and in which region, with the memory gauge from the build's
   summary.

### Where to start, if the room is needed

| Order | Batch | Bytes | Why this order |
| ---: | --- | ---: | --- |
| 1 | Main image `imm_load` | 26 | The largest group in the scarcest space. Each is one deleted instruction. Check each for a constant coincidence |
| 2 | Main image `dead_insn` | 14 | `dp_x`, `dp_stepped`, `DrawDoorTile`, `SprSplitOK` and others, all checked above. Update the routines' comments |
| 3 | Main image `jmp_to_branch` and `branch_over_jmp` | 18 | Mechanical, but each changes a path's cycles. Skip `RuptTimer`. Keep each branch in range and in its page, checked in the listing |
| 4 | Main image `reg_xfer`, `clc_sec`, `cmp_zero` | 13 | Small and mechanical |
| 5 | Banks, by need | 176 | Only for the bank that's short. The transfer bank's eight `LDA #0 : RTS` exits are 16 bytes on their own |

Each batch is one commit, and each commit passes the whole gate.

## Appendix: the main code image's findings with a byte to save

Generated 2026-10-06 from the build of `944578c`. Addresses move with every build, so rerun
the tool rather than trusting these. "Routine" is the nearest label above the instruction,
often a local one.

| Address | Routine | Instruction | Category | Bytes | Why |
| --- | --- | --- | --- | ---: | --- |
| `$14E3` | `InfoHigh` | `bne ih_ship` | branch_over_jmp | 3 | bne ih_ship / jmp GoTitle -> beq to the jmp's target (+52 from here; the target  |
| `$1898` | `RuptTimer` | `bne rt_none` | branch_over_jmp | 3 | bne rt_none / jmp rt_drawok -> beq to the jmp's target (+116 from here; the targ |
| `$2180` | `MovePlyFire` | `bcs mpf_kill` | branch_over_jmp | 3 | bcs mpf_kill / jmp mpf_delay -> bcc to the jmp's target (+8 from here; the targe |
| `$2415` | `dp_x` | `ldx $25B7` | dead_insn | 3 | its results (XNZ) are all dead |
| `$246F` | `dp_stepped` | `ldx $25B7` | dead_insn | 3 | its results (XNZ) are all dead |
| `$2590` | `DrawDoorTile` | `ldx $25BE` | dead_insn | 3 | its results (XNZ) are all dead |
| `$29CB` | `SprSplitOK` | `lda $2DF6` | dead_insn | 3 | its results (ANZ) are all dead |
| `$128E` | `PassPrep` | `lda #$00` | imm_load | 2 | A is already $00 |
| `$12C9` | `ml_xHeld` | `lda #$00` | imm_load | 2 | A is already $00 |
| `$1725` | `InstallIrq` | `lda #$7F` | imm_load | 2 | A is already $7F |
| `$175C` | `UninstallIrq` | `lda #$7F` | imm_load | 2 | A is already $7F |
| `$18B6` | `rt_panel` | `lda #$06` | imm_load | 2 | A is already $06 |
| `$1958` | `fp_tail` | `cpy #$00` | cmp_zero | 2 | N, Z already reflect Y; C dead |
| `$195C` | `fp_tail` | `lda #$00` | imm_load | 2 | A is already $00 |
| `$2029` | `mm_settle` | `lda #$00` | imm_load | 2 | A is already $00 |
| `$2106` | `df_have` | `lda #$01` | imm_load | 2 | A is already $01 |
| `$226C` | `ccd_start` | `lda #$00` | imm_load | 2 | A is already $00 |
| `$227E` | `ccd_start` | `lda #$01` | imm_load | 2 | A is already $01 |
| `$2793` | `sss_seq0` | `lda #$00` | imm_load | 2 | A is already $00 |
| `$27BB` | `ssc_loop` | `ldx $10` | dead_insn | 2 | its results (XNZ) are all dead |
| `$2B85` | `sr_loop` | `lda #$00` | imm_load | 2 | A is already $00 |
| `$2C46` | `saa_step` | `lda #$00` | imm_load | 2 | A is already $00 |
| `$12E8` | `ml_nofire` | `jsr SprSplitOK` | tail_call | 1 | jsr/rts -> jmp |
| `$1378` | `pli_byte` | `jmp pdi_page` | jmp_to_branch | 1 | Z is 0 here: bne reaches the target (-64, same page) |
| `$13DA` | `ConsoleEnter` | `jsr PgData` | tail_call | 1 | jsr/rts -> jmp |
| `$1519` | `GoTitle` | `lda #$00` | reg_xfer | 1 | X already holds this value: txa |
| `$1947` | `FillPanel` | `lda #$00` | reg_xfer | 1 | Y already holds this value: tya |
| `$1989` | `fp_tail` | `jsr fp_vline` | tail_call | 1 | jsr/rts -> jmp |
| `$1A51` | `SetupRupture` | `jsr RuptInit` | tail_call | 1 | jsr/rts -> jmp |
| `$1AEC` | `ReadKeys` | `ldx #$00` | reg_xfer | 1 | A already holds this value: tax |
| `$1C9F` | `ApplyMove` | `jmp am_haverow` | jmp_to_branch | 1 | Z is 0 here: bne reaches the target (+22, same page) |
| `$1D29` | `DeadZone` | `jmp dz_screen` | jmp_to_branch | 1 | C is 1 here: bcs reaches the target (+97, same page) |
| `$1D83` | `dz_high` | `jmp dz_screen` | jmp_to_branch | 1 | C is 1 here: bcs reaches the target (+7, same page) |
| `$1DE2` | `cx_high` | `jmp cx_stop` | jmp_to_branch | 1 | C is 1 here: bcs reaches the target (+7, same page) |
| `$1E0E` | `cy_high` | `jmp cy_stop` | jmp_to_branch | 1 | C is 1 here: bcs reaches the target (+21, same page) |
| `$1E88` | `SetPosFromWaypoint` | `jmp sfw_grid` | jmp_to_branch | 1 | Z is 1 here: beq reaches the target (+23, same page) |
| `$1F8A` | `DoCharUnder` | `jmp SubScore` | jmp_to_branch | 1 | C is 0 here: bcc reaches the target (-100, same page) |
| `$223C` | `CbFirePlace` | `clc` | clc_sec | 1 | C is already 0 |
| `$2346` | `cbd_next` | `lda #$00` | reg_xfer | 1 | X already holds this value: txa |
| `$2452` | `dp_horiz` | `clc` | clc_sec | 1 | C is already 0 |
| `$26A3` | `LiftPlace` | `jmp lp_grid` | jmp_to_branch | 1 | Z is 1 here: beq reaches the target (+23, same page) |
| `$2887` | `sfr_pass` | `ldy #$00` | reg_xfer | 1 | A already holds this value: tay |
| `$2974` | `spw_no` | `clc` | clc_sec | 1 | C is already 0 |
| `$2976` | `spw_yes` | `sec` | clc_sec | 1 | C is already 1 |
| `$29A2` | `SprDrawTr` | `ldx #$00` | reg_xfer | 1 | A already holds this value: tax |
| `$2E6E` | `zn_2` | `lda #$00` | reg_xfer | 1 | Y already holds this value: tya |
