# Master-only extensions

*Part of the Paradroid BBC Micro port. Start at [`../PLAN.md`](../PLAN.md).*

Things the port could do on a Master 128 that a Model B cannot host, kept together so the Model B
path stays readable. **None of these are on the critical path.** `PLAN.md`'s target is a Model B
with two sideways RAM banks; anything here either forks the rendering path or makes the port
Master-only, and that is a decision not yet taken.

## ⏸ 2 px horizontal scrolling, via shadow RAM

The scheme Layer 4a rules out on a Model B — two 10K circular strips, a second copy of the map
offset by 2 px, alternating which one R12/R13 points at. It fails there because a circular strip's
period must equal the hardware wrap span and only one wrap region exists. It is not a compromise
version of that idea; it is the *same* idea, which the Master can actually host.

**The mechanism.** Both buffers sit at the same address, `&5800–&7FFF`: one in main RAM, one in
shadow. Same 10K wrap, same R12/R13, same scroll arithmetic, same everything — the only difference
between displaying A and displaying B is one bit of ACCCON (`&FE34`): `D` selects which RAM the
video fetches from, `X` selects which one the CPU sees at `&3000–&7FFF`. So none of the addressing
problems that kill it on a Model B arise; we are not fitting two strips into one wrap region, we are
using the same region twice over. Flip `D` in the VSync handler and the view is 2 px further along.

**Confirmed by KC, not assumed:**
- The Master's screen wrap is driven the same way as the Model B's — the System VIA addressable
  latch — so the 10K/`&5800` setting and everything derived from it carries over unchanged.
- Writing ACCCON's `D` bit takes effect **instantly**, including mid-scanline. Per-field switching
  is therefore trivially safe; mid-scanline switching is a whole other technique and a conversation
  for another day.

**Why it is parked: cost, not feasibility.** Either buffer might be the one displayed next field, so
both must be current at all times. Every edge redraw and every sprite blit happens twice.

- It is cheaper than a straight doubling. B's exposed edges can be produced by *shifting bytes out
  of A* rather than redrawing from the tile map, which skips the tile → character → charset
  lookups — and those are the expensive half of a band, not the copying. Call it +60–80% on the
  drawing rather than +100%.
- Even so that is roughly +12–16K cycles a frame against about 5K spare. It needs the optimisation
  backlog at the end of [Layer 4](layer-4-player.md) spent (~14K identified) or a smaller play
  area, or both.

**Revisit when** the frame budget has real headroom — most likely after `PARADAT` moves to sideways
RAM and [Layer 4](layer-4-player.md)'s inlining work is done — or if the target ever moves to the Master. The dead-zone
camera already fixes the case that actually looked bad (the world lurching when you creep), so this
buys smoothness at moderate speeds rather than curing a defect.
