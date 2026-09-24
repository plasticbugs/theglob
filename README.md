# The Glob / Super Glob — Analogue Pocket core (openFPGA)

**The Glob** and **Super Glob** (Epos Corporation, 1983) on the Epos
**Tristar 8000** board, as
MAME's `misc/epos.cpp` describes it: a Z80 at 2.75 MHz, a 272 × 236,
4-bit-per-pixel bitmap resolved through a 32-byte colour PROM, and an
AY-3-8912. The whole board is in the gateware and in block RAM; the Pocket's
SDRAM and SRAM are not used.

Two games, one board: MAME's `theglob` and its parent `suprglob` share the
machine, the inputs, the DIP switches and the colour PROM, and differ only in
their program, so the gateware is the same for both. Choosing Run on the
Pocket lists them by name (one instance JSON each, the Pleiads core's pattern);
each loads its own image. These are **not** the Pac-Man conversion kits
`theglobp` / `sprglobp`, which are different romsets on different hardware.

> **ROMs are not included and never will be.** You supply your own MAME
> romset; the core reads one image built from it (below).

| board part | implementation | verified by |
|---|---|---|
| Z80 @ 2.75 MHz | tv80 (`modules/cpu-tv80`) behind a clock-enabled wrapper (`rtl/z80_cpu.sv`), with the refresh register R compiled in | every CPU write held to MAME's, in order, from reset: 862,289 of 862,289 over 1500 frames of attract and play, apart from 4 bytes of uninitialised registers and short clusters where the vblank IRQ lands one instruction apart (`sim/run_system.sh -trace`, `tools/compare_trace.py`) |
| bitmap video + colour PROM | `rtl/theglob_video.sv` | 0 differing pens against `tools/render_model.py` on 8 frozen MAME states (boot, attract, play, service menu, colour table) — and the renderer 0 pixels from MAME on 22 frames (`sim/run_video.sh`); whole machine 0 RGB pixels from MAME at frames 500 and 800 |
| AY-3-8912 @ 687.5 kHz | `rtl/ay8912.sv`, written from MAME's `ay8910.cpp` | all 16 volume levels measured in MAME to a flat 0.994; whole core against MAME's recording over 25 s of play, level per second within 0.99–1.03 in every second with sound (`tools/audio_seconds.py`) |
| Pocket audio path | `rtl/dc_block.sv`, `rtl/lowpass.sv`, `rtl/theglob_reverb.sv` in `target/pocket/core_top.sv` | each bit-exact to its Python model on 1,188,898 samples of this game's audio, every mode; reverb never at the rails (`sim/run_reverb.sh`) |
| ROM, 30 KB + PROM | block RAM, loaded by `target/pocket/theglob_mem.sv` | both images byte-identical to MAME's regions (`tools/verify_rom.py`); download at the loader's rate, strobe held 1, 4 and 7 clocks, every byte back and checksum EF35 / 94E5 (`sim/run_mem.sh`) |
| Super Glob | the same gateware, `suprglob.mra` | write trace from reset equal in count to MAME's (879,403), the first 497,070 exactly, then only IRQ-timing clusters; boot, attract, play and a 10-entry service mode rendered 0 px from MAME; service mode 0 px in the core. Where Super Glob writes VRAM mid-frame the core tears as the board does and MAME does not (`docs/hardware.md` 11) |
| timing | 88 MHz (8 × the board's 11 MHz), 5.5 MHz dot clock | closed at every corner in a local Quartus 18.1 compile |

## Status

**It runs on a Pocket.** Builds have been played on hardware throughout, and
the 0.1.0 bitstream is the exact file flashed for the last round of testing
(md5 `677049b3400324451691601d0796593e`), not a rebuild. Super Glob is new
since then and has been checked in simulation only.

What the hardware found that no bench had:

* **Enemies that stood still or camped at the left edge.** tv80 leaves the
  Z80's refresh register behind a build switch this core did not set, so
  `LD A,R` read 0 and the enemies' random numbers were always the same. With
  it on, the game at frame 4800 of a scripted session has MAME's score, lives
  and enemies within a step or two (it cannot be exact: R counts cycles).
* **Ticks and thumps in the jump sound.** They are the board's — the edges of
  a 42 Hz square wave, and the level shifting as it starts and stops — and
  MAME has them too. The core now blocks DC on the Pocket's output and offers
  a low-pass (Audio Filter, Light by default; Off is MAME's sound).

Not implemented, and why that is safe: the palette bank bit is built but was
never seen set (the PROM's halves are identical for this set anyway); the
watchdog is counted but, as in MAME, never resets the board; there is no
flip screen or cocktail mode on this board.

## Playing it

| Pocket | game |
|---|---|
| D-pad | move |
| A / Y | energy (button 1) |
| B / X | button 2 |
| Select | coin |
| Start | 1 player start |
| R shoulder | 2 players start |

The Interact menu carries the board's DIP switches (lives, difficulty, bonus
life, coinage, demo sounds), Audio Filter (Off / Light / Heavy), Cabinet
Reverb (Off / Light / Medium / Heavy), screen shape, scanlines and shadow
mask, and the Service Switch for the game's own diagnostics — including a
colour table and a convergence crosshatch.

## Building the ROM images

```sh
python3 mra_build.py theglob.mra  theglob.zip                 # -> theglob.rom
python3 mra_build.py suprglob.mra suprglob.zip                # -> suprglob.rom
python3 mra_build.py theglob.mra  theglob.zip suprglob.zip    # The Glob from a split set
```

A merged `suprglob.zip` carries its clones too, so it builds both images on
its own: `python3 mra_build.py theglob.mra suprglob.zip`.

The builder needs only Python 3. It reads the MAME zip (or a directory of
loose files), checks every ROM's CRC32, and verifies the finished image
against a known md5. The colour PROM belongs to the parent set `suprglob`: a
merged or non-merged `theglob.zip` has it, a split one does not, and then the
builder names the missing file — give it the parent zip too. Copy the
results to `Assets/theglob/common/` on the SD card as `theglob.rom` and
`suprglob.rom`; either one alone is enough for its own game.

## Building the core

`./build-local.sh` compiles with Quartus 18.1 in Docker and leaves the SD-card
package in `release/pocket/`. `./build-local.sh map` runs analysis and synthesis
only — a couple of minutes, and it catches what Verilator cannot.

## Checking it

```sh
sim/lint.sh           # every module on its own
sim/run_mem.sh        # the ROM download at the loader's real rate
sim/run_video.sh      # the video against the reference renderer, frozen states
sim/run_system.sh     # the whole machine; -trace, -wav, -snap for MAME comparisons
sim/run_reverb.sh     # the Pocket audio path against its models
```

`docs/hardware.md` is the board, from MAME and the ROM; `METHODOLOGY.md` is how
this was built.

## Credits

`CREDITS.md` is the full list. The short of it:

* **MAME** — Zsolt Vasvari's Epos driver (`epos.cpp`) and Couriersud's AY-3-8910
  model (`ay8910.cpp`), with Matthew Westcott's measurements of a real chip,
  from which this core's AY and its volume table are derived.
* **Guy Hutchison** — tv80, the Verilog Z80, from **Daniel Wallner**'s T80.
* **Marcus Andrade**
  ([@boogermann](https://github.com/boogermann),
  [OpenGateware](https://github.com/opengateware) /
  [Raetro](https://github.com/raetro)) wrote everything between the arcade
  hardware and the Pocket — `platform/pocket/` is OpenGateware's
  `gateman-pocket` platform, `projects/` came from his Gateman CLI,
  `target/pocket/core_top.sv` starts from his template, and every build here
  runs in his `raetro/quartus:pocket` Docker image.
* The cabinet reverb is the one from this author's Pleiads/Phoenix core (by way
  of Punch-Out!! and Cloak & Dagger), the DC blocker's form from the BBC Micro
  core.
* Analogue, for the APF.
