# Layer 13b/13c — Sideways RAM detection, and machine compatibility

**Status: planned, not started.** 13a, the RAM pass, is done and written up separately in
[`layer-13-ram-pass.md`](layer-13-ram-pass.md).

**Until Layer 13, RAM was not a constraint worth designing around** — KC's ruling of 2026-08-16:
where a layer needed room, take a fourth sideways bank and move on. 13a paid that off in one pass.
What is left is making the build honest about the machine it is running on.

## 13b — Sideways RAM detection at boot

There is **no detection at all today**: the build assumes banks 4–7 are RAM and writes into them
regardless. Needed: the standard write/read-back probe over all 16 banks at boot, bank assignments
chosen from the result rather than hard-coded, and an honest message and a stop when there are not
enough.

## 13c — Machine compatibility testing

The port has only ever run on jsbeeb's `B-DFS1.2` and b-em. This pass runs it on the machines
people actually have: B with DFS 1.2 and 2.26, B+, Master 128 (shadow RAM and a different `PAGE`),
and second processors, which the IRQ takeover and the rupture are both likely to dislike. Each
combination either works, or is documented as unsupported with the reason.

**Entry condition:** Layer 12 done, so memory needs are final. **Exit condition:** a build that
detects what it is running on, says so, and either runs correctly or refuses honestly.
