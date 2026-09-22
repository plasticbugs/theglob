# The Glob — Analogue Pocket core (openFPGA)

The Glob (Epos, 1983) on the Epos "Tristar" bitmap board as MAME's
`misc/epos.cpp` describes it: a Z80 at 2.75 MHz, a 272x236 4-bit-per-pixel
framebuffer resolved through a 32-byte colour PROM, and an AY-3-8912. This is
the `theglob` set (`globu4`-`globu11` + `82s123.u66` from parent `suprglob`),
not the Pac-Man conversion kit `theglobp`, which is a different set on
different hardware.

> **ROMs are not included and never will be.** You supply your own MAME
> `theglob` romset; the core reads one image built from it.

| board part | implementation | verified by |
|---|---|---|
| *main CPU @ MHz* | *vendored core* | *which bench* |
| *sound CPU* | | |
| *sound chip* | | *band energy against MAME's recording, over what window* |
| *video chip* | `rtl/…` | *pixel-identical to MAME on N frozen states* |
| *ROM* | Pocket SDRAM (`target/pocket/theglob_mem.sv`) | `sim/run_mem.sh`; image byte-identical to MAME's regions |
| *tilemap RAM* | Pocket SRAM | self-test at reset |

One row per part of the board. The right-hand column is the point of the
table: write **"—"** where nothing verifies it, not nothing.

## Status

State plainly whether it has run on a Pocket. Then, as a list: what is proven
and by what; what the hardware found that no bench had; what is not
implemented. Keep the three apart. A reader deciding whether to trust the core
needs the second and third more than the first.

## Building the ROM image

```sh
python3 mra_build.py theglob.mra theglob.zip
```

The builder needs only Python 3. It reads the MAME zip (or a directory of loose
files), checks every ROM's CRC32, and verifies the finished image against a
known md5. Copy the result to `Assets/theglob/common/theglob.rom` on the SD card.

## Building the core

`./build-local.sh` compiles with Quartus 18.1 in Docker and leaves the SD-card
package in `release/pocket/`. `./build-local.sh map` runs analysis and synthesis
only — a couple of minutes, and it catches what Verilator cannot.

## Checking it

```sh
sim/lint.sh          # every module on its own
sim/run_mem.sh       # the Pocket's memory path, at the loader's real rate
```

Add the core's own gates here as they come to exist: the reference renderer
against MAME, the RTL against the renderer, the whole machine, the sound.

## Credits

`CREDITS.md` is the full list, and a core should extend it with its own. The
short of it: **Marcus Andrade**
([@boogermann](https://github.com/boogermann),
[OpenGateware](https://github.com/opengateware) /
[Raetro](https://github.com/raetro)) wrote everything between the arcade
hardware and the Pocket — `platform/pocket/` is OpenGateware's
`gateman-pocket` platform, 41 of its 63 files are his, `projects/` came from
his Gateman CLI, `target/pocket/core_top.sv` starts from his template, and
every build here runs in his `raetro/quartus:pocket` Docker image.

Then: MAME, for the driver and devices this was written against (`ref/mame/`);
the vendored cores and their authors (`modules/VENDOR.md`); Analogue, for the
APF; and anyone whose board photographs, schematics or measurements are in
`docs/hardware.md`.
