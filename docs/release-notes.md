The Glob (Epos Corporation, 1983) for the Analogue Pocket: the Epos Tristar 8000 board — Z80, bitmap video through a colour PROM, AY-3-8912 — checked against MAME.

**ROMs are not included.** Build `theglob.rom` from your own MAME `theglob` romset with the included `mra_build.py` and `theglob.mra` (a split set also needs the parent `suprglob.zip` for the colour PROM), and copy it to `Assets/theglob/common/theglob.rom`.

What is in 0.1.0:

* The whole board in block RAM; video pixel-identical to MAME on every frozen state tested, and the CPU's writes held to MAME's one by one.
* Enemies that wander and pace as in the arcade: the Z80's refresh register, which the game uses for its random numbers, is in (earlier test builds had it off, and the enemies stood still or camped at the left).
* Sound from MAME's own AY model, level-matched to MAME's recording; a DC blocker on the Pocket's output; **Audio Filter** (Off / Light / Heavy, Light by default) to soften the ticks of the jump sound, and **Cabinet Reverb**.
* The board's DIP switches on the menu, and the Service Switch for the game's diagnostics.

Controls: D-pad move, A/Y energy, B/X button 2, Select coin, Start 1 player, R shoulder 2 players.

The bitstream is the exact file tested on hardware (md5 `677049b3400324451691601d0796593e`), not a rebuild.
