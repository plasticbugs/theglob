# The board

Epos **Tristar 8000**, as MAME 0.288 describes it in `src/mame/misc/epos.cpp`
(`tristar8000_state`), with the AY from `src/devices/sound/ay8910.cpp/.h`. All
three files are in `ref/mame/`, fetched verbatim from tag `mame0288`, which is
the version of the `mame` binary every probe here was run with.

`theglob` is a clone of `suprglob` and shares its machine config, its input
ports and its colour PROM (`82s123.u66`, which lives in the parent set). It is
**not** `theglobp`, the Pac-Man-board conversion (`pacman/pacman.cpp`), which
is a different romset on different hardware.

## 1. Parts and clocks

One 11 MHz crystal. Everything divides it (driver notes; IGMO schematic).

| part | type | clock | notes |
|---|---|---|---|
| main CPU | Z80 | 11 MHz / 4 = **2.75 MHz** | the only CPU |
| sound | AY-3-8912A | 11 MHz / 16 = **687.5 kHz** | three channels summed to one speaker at 1.0 each; its one I/O port is unused |
| video | discrete bitmap + 32x8 PROM | dot 11 MHz / 2 = **5.5 MHz**, HTOTAL 352, VTOTAL 258 | visible 272 x 236, 0,0 at the start of each; **60.562 Hz** (5.5e6 / 90816) |
| I/O | LS-series latches | | coin latch is a 74LS74 set by the coin edge |

Measured: MAME runs 1817 frames in 30 s of emulated time (60.57 Hz, probe in
§9). Audio pacing: the AY's own clock sets the pitch; tempo is the game's
frame-locked code (IRQ once per frame). There is no sound CPU, so §5.3 of the
methodology (a CPU as the sample clock) does not apply.

## 2. Memory map — main CPU

`tristar8000_state::prg_map`. No wait states, no mirrors.

| range | size | what | R/W |
|---|---|---|---|
| 0000-77FF | 30 KB | program ROM: u10 u9 u8 u7 u6 u5 u4 (4 KB each), u11 (2 KB) at 7000 | R |
| 7800-7FFF | 2 KB | work RAM | RW |
| 8000-FFFF | 32 KB | video RAM (the bitmap), CPU read and write | RW |

## 3. I/O ports, inputs and DIP switches

`io_map`: `global_mask(0xff)`, so only A7-A0 decode.

| port | read | write |
|---|---|---|
| 00 | DSW | watchdog reset (see §4) |
| 01 | SYSTEM | outputs: D0 start lamp 1, D1 start lamp 2, D2 coin counter, **D3 palette bank** |
| 02 | INPUTS | AY data |
| 03 | — | clear the coin latch (any value) |
| 06 | — | AY address |

Reads of any other port are unmapped (never done by this program, §9).

**SYSTEM (port 01)**, from `megadon` with `suprglob`'s modifications:

| bit | meaning | polarity |
|---|---|---|
| 0 | coin latch 1 (74LS74, set on the coin's rising edge, cleared by OUT 03) | active high |
| 1 | coin latch 2 (not hooked up; always 0) | active high |
| 2 | start 1 | active low |
| 3 | start 2 | active low |
| 4 | service ("diagnostics"), non-toggle | active low |
| 5 | unused | reads 1 |
| 6 | protection: **must read 0** (`IPT_CUSTOM` active high, no handler) | 0 |
| 7 | protection: **must read 1** (`IPT_CUSTOM` active low, no handler) | 1 |

The driver notes that each game checks bits 6-7 and halts if they are wrong.

**INPUTS (port 02)**, all active low: 0 right, 1 left, 2 button 1, 3 button 2,
4 up, 5 down, 6-7 unused (read 1). There is one control set; the two players
alternate on it (no cocktail mode, per the driver notes).

**DSW (port 00)**, one bank of eight. The MAME default is **0x00** (every
switch off). The bits are scrambled against the switch numbers:

| mask | switch | meaning | values |
|---|---|---|---|
| 01 | SW1:1 | coinage | 00 1C/1C, 01 1C/2C |
| 50 | SW1:2,3 | lives | 00 3, 10 4, 40 5, 50 6 |
| 26 | SW1:4,5,6 | difficulty 1-8 | 00 1, 02 2, 20 3, 22 4, 04 5, 06 6, 24 7, 26 8 |
| 08 | SW1:7 | bonus life | 00 10000 + difficulty x 10000, 08 90000 + difficulty x 10000 |
| 80 | SW1:8 | demo sounds | 00 on, 80 off |

## 4. Interrupts

One source: `set_vblank_int("screen", irq0_line_hold)`. INT is asserted at the
start of vblank (the first line after the visible 236, i.e. line 236 of 0-257)
and held until the CPU acknowledges it. The program runs in **IM 1** (probe,
§9), so the data bus during the acknowledge is irrelevant and the handler is
at 0038.

`WATCHDOG_TIMER(config, "watchdog")` is configured with neither a time nor a
vblank count, which in MAME means it never fires. The game writes port 00
(values 00-0F, 23, 25, 5B, 80, FF seen), so it kicks it. The core counts the
kicks for the panel and does not reset on a missing one, matching MAME.

## 5. Main CPU to sound CPU

None. The Z80 writes the AY directly: OUT 06 selects a register, OUT 02 writes
it. The AY is never read (port 02 reads the joystick).

## 6. Sound

AY-3-8912A at 687.5 kHz, `add_route(ALL_OUTPUTS, "mono", 1.0)`: the three
channel outputs of MAME's default (legacy, per-channel) mode summed with equal
weight. No filtering in the driver. The 8912's I/O port A is unconnected.

## 7. Video

`epos_base_state::screen_update`, `tristar8000_state::palette`.

1. The bitmap is VRAM 8000-FFFF, 136 bytes per line, top line first. Byte
   `offs` is at `y = offs / 136`, `x = (offs % 136) * 2`.
2. The **low nibble is the left pixel** (`x`), the high nibble the right
   (`x + 1`).
3. The pixel's pen is `(palette_bank << 4) | nibble`. `palette_bank` is port
   01 bit 3, reset to 0 by `video_reset`.
4. The pen indexes the 32-byte PROM. Its byte is RGB 3-3-2:
   R = bits 7,6,5 weighted 0x92, 0x4A, 0x23; G = bits 4,3,2 the same;
   B = bit 1 x 0xAD + bit 0 x 0x52.
5. Only lines 0-235 and pixels 0-271 are visible. 32768 / 136 puts 240 full
   lines and 128 bytes of a 241st in VRAM; the rest are never shown.

The whole bitmap is drawn at `screen_update`, i.e. once per frame from the
current VRAM contents; there are no layers, sprites or scroll. The monitor is
rotated (`ROT270`). Flip screen is not implemented for this board (the
`flip_screen()` branch never runs on Tristar 8000).

The PROM's two halves are identical for this set (`xxd` of `82s123.u66`), so
the palette bank changes nothing visible here; it is implemented anyway.

## 8. ROMs

| file | CRC32 | size | region | offset |
|---|---|---|---|---|
| globu10.bin | 08fdb495 | 4096 | maincpu | 0000 |
| globu9.bin  | 827cd56c | 4096 | maincpu | 1000 |
| globu8.bin  | d1219966 | 4096 | maincpu | 2000 |
| globu7.bin  | b1649da7 | 4096 | maincpu | 3000 |
| globu6.bin  | b3457e67 | 4096 | maincpu | 4000 |
| globu5.bin  | 89d582cd | 4096 | maincpu | 5000 |
| globu4.bin  | 7ee9fdeb | 4096 | maincpu | 6000 |
| globu11.bin | 9e05dee3 | 2048 | maincpu | 7000 |
| 82s123.u66  | f4f6ddc5 | 32   | proms   | 0000 (from parent `suprglob`) |

No interleave, no encryption (the Tristar 9000 decryption in the same driver
does not apply to this board).

## 9. What the program actually uses

Probe: MAME with a Lua tap on the whole I/O space, 30 s of attract mode from
power-on (1817 frames):

- IN from ports 00, 01, 02 only.
- OUT to 00 (watchdog), 01 (only the value 00 was seen, so palette bank 0 and
  lamps off throughout attract), 02 and 06 (AY), 03 (coin latch clear).
- Interrupt mode 0 at reset, then IM 1 for the rest of the run.

Not exercised by that probe, and so not yet evidence: gameplay, the service
mode, a palette-bank write of 1.

## 10. Open questions

- Whether the game ever sets the palette bank. It makes no visible difference
  with this PROM either way.
- The monitor orientation on the Pocket (`rotation` in `video.json`) is a
  prediction until someone looks at it on hardware.
