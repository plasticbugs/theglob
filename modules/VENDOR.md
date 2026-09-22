# Vendored modules

Third-party HDL cores copied into the tree — no submodules, so the build is
self-contained and reproducible. Each keeps its own LICENSE alongside.
`tools/vendor.sh <name>` fetches one from its upstream at a pinned commit,
with its licence; run it with no arguments to see what it knows about, or give
it a url and ref for anything else. `tools/gen_qip.sh` then lists everything
under `modules/` for Quartus.

| module | what it is | upstream | commit | licence |
|---|---|---|---|---|
| cpu-tv80 | Z80 (Guy Hutchison's Verilog translation of Daniel Wallner's T80). `tv80s.v`, `tv80n.v` and the SD-card test benches are removed; `rtl/z80_cpu.sv` is a copy of `tv80s.v` with the clock enable brought out | https://github.com/hutch31/tv80 (`rtl/core`) | 66a131c38d05ef58b3d8c4f1507a72e6e4aa5d65 | MIT |
| sound-jt49 | AY-3-8910 / YM2149 (Jose Tejada). `jt49_bus.v` removed (the core latches the AY address itself, as the 8912's mask-programmed chip select requires) | https://github.com/jotego/jt49 (`hdl`) | 47301ed51374d6d41db4db846b7643fecf75e417 | GPL-3.0 |

For each module record what it is, its upstream repository and the exact
commit, its licence, and anything it needs that is not obvious — jt12's
`hdl/` has to be taken whole, for instance, because `jt12_top` instantiates
its ADPCM files outside a generate guard, so they must exist even when ADPCM
is disabled.

Written here rather than vendored: the Tristar 8000's video (a raster
counter reading a 4-bit bitmap through a colour PROM, `rtl/theglob_video.sv`)
and its I/O, from MAME's `misc/epos.cpp` (`ref/mame/`, `docs/hardware.md`).

To update one: re-copy from upstream at the new commit and record it here.
