# Layer 0 — Toolchain and a booting screen ✅ DONE

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

`bin/beebasm.exe`, `build.ps1` (`-Run` launches b-em), jsbeeb MCP for in-loop verification.
`src/main.asm` boots to a 320×200 MODE 1 screen at `&4000` and draws a fill + 1-px border.

**Confirmed empirically:**
- **CRTC start address = screen address ÷ 8.** Base `&4000` → R12/R13 = `&0800`. The 16K wrap holds.
- Geometry: R6 = 25 rows, R7 = 31, everything else at MODE 1 defaults. R4 = 38 / R5 = 0 is left
  alone to preserve 312 scanlines / 50 Hz.
- Screen occupies exactly `&4000–&7E7F` (16000 bytes). `&7E80+` untouched.
- **`&3000–&3FFF` is genuinely reclaimed** — verified still zero after the fill.
- Pixel address formula verified: `addr = &4000 + (y DIV 8)*640 + (x DIV 4)*8 + (y MOD 8)`.
- MODE 1 byte encoding: pixel *n* takes bit `7-n` (high colour bit) and bit `3-n` (low bit).
  Solid colour 0/1/2/3 = `&00`/`&0F`/`&F0`/`&FF`.
- DFS filenames are max 7 chars — the disc file is `PARA`, not `PARADROID`.

> Superseded by Layers 3b–3d. The screen is no longer a 16K MODE 1 frame at `&4000`: it is a 10K
> circular strip at `&5800` with a panel at `&4800`, driven by a three-cycle rupture. The
> "RAM reclaim opportunity" noted here was taken — shrinking the displayed area handed back
> `&3000–&57FF`, which is where the level data and panel now live.
