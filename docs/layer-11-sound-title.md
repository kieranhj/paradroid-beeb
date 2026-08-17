# Layer 11 — Sound, title, polish

**Status: planned, nothing built.** This file exists to hold two pieces of groundwork that were
recorded before the layer started, so they are not lost between now and then.

## The SN76489 encoding — recovered, NOT verified

The sound driver replaces the C64's SID engine with the Beeb's SN76489. The chip is written
through System VIA port A with handshake at `&FE41`; a latch byte is `1 cc r nnnn` and a data byte
`0 0 nnnnnn`, so a tone is `&80 | (chan << 5) | (freq AND &0F)` followed by `freq >> 4`, and an
attenuation is `&90 | (chan << 5) | (15 - vol)`.

**That came out of the deleted `hardware.asm` and was never verified on hardware or in the
emulator.** Check it against the BBC hardware wiki before building on it, per the standing rule
about recalled facts. It is the only surviving content of that file.

## The randomness debt the title screen owes the game

The C64's random source is `$D41B`, free-running SID noise, and what makes the starting deck
genuinely unpredictable is that `$12B6` samples it after however long the player left the title
up. We have no noise source, so `drSeed` is currently taken from the User VIA's T1 counter at
boot — which varies on hardware and **not at all under an emulator**, where two cold boots land on
the same deck. Stir `drSeed` once a frame while the title waits for fire and that goes away, by
the original's own mechanism. The full write-up is in
[`layer-8-doors-lifts.md`](layer-8-doors-lifts.md), "The seed, and why it is not random yet".

## Also queued for this layer

- The transfer game's two droid info screens (`ShowXferInfo`, `$3734`) — deferred from Layer 10
  because the token-string presentation machinery this layer builds is what they need. See
  `layer-10-transfer.md` decision 8.
- Every `sndFx1` write stubbed out of the console and transfer code — see `layer-9-hud.md` and
  `layer-10-transfer.md`.
