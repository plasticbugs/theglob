# Frozen machine states

Dumped from MAME 0.288 by `tools/dump_state.lua` (format in its header):
VRAM, work RAM and the palette bank, with MAME's own pixels for the frame
they produced. RAM, not ROM. `tools/render_model.py` renders each and must
match MAME's pixels exactly; the RTL video bench loads each and must match
the renderer's pens exactly.

| file | what | how it was reached |
|---|---|---|
| state_00200 | boot self-test ("SCRATCHPAD", "U12 OK") | power-on |
| state_01000, state_01400 | attract ("MEET THE GLOB") | power-on |
| state_02400, 03600, 04800 | gameplay, level 1, enemies on screen | COIN=2000 START=2060, scripted joystick |
| state_svc_00600 | service-mode menu | SERVICE=1 |
| state_ctab_01100 | service mode colour table, pen 08 | SERVICE=1, PRESS as in the commit that added it |
| state_sg_01400 | Super Glob attract ("PUSH CALL BUTTON TO RIDE ELEVATORS") | GAME=suprglob, power-on |
| state_sg_svc_00600 | Super Glob service menu (10 entries) | GAME=suprglob SERVICE=1 |

The two games share the board and the colour PROM, so every state renders with
either image's PROM (`sim/run_video.sh` uses .build/theglob.rom's).
