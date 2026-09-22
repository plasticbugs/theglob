-- Log every write the Z80 makes, in order, from power-on to frame FRAMES:
-- "M aaaa dd" for memory (work RAM and VRAM; the ROM is never written) and
-- "O aa dd" for I/O, and "F n" at each frame-done (the start of vblank) --
-- the format sim/tb_system.cpp -trace writes, so the
-- two can be diffed a transaction at a time (tools/compare_trace.py).
--
--   FRAMES=300 OUT=.build/mame_trace.txt tools/mame.sh -seconds_to_run 10 \
--       -autoboot_script tools/trace_writes.lua
--
-- The same controls as tools/dump_state.lua (COIN, START) when set.
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local out = assert(io.open(os.getenv("OUT") or "mame_trace.txt", "w"))
local LIMIT = tonumber(os.getenv("FRAMES") or "300")
local COIN  = tonumber(os.getenv("COIN")  or "-1")
local START = tonumber(os.getenv("START") or "-1")
local P = mac.ioport.ports
local frames, on = 0, true
local buf = {}
-- TIMES=1 appends the emulated time of each write, in CPU cycles since
-- power-on (2.75 MHz), as a fourth column
local TIMES = os.getenv("TIMES") == "1"
local function t() return TIMES and string.format(" %d", math.floor(emu.time():as_double() * 2750000 + 0.5)) or "" end
local function flush() out:write(table.concat(buf)); buf = {} end
_G.KEEP = {}
_G.KEEP.m = cpu.spaces["program"]:install_write_tap(0x7800, 0xffff, "wm", function(o, d, m)
  if on then buf[#buf + 1] = string.format("M %04x %02x%s\n", o, d, t()); if #buf > 4096 then flush() end end
end)
_G.KEEP.o = cpu.spaces["io"]:install_write_tap(0x00, 0xff, "wo", function(o, d, m)
  if on then buf[#buf + 1] = string.format("O %02x %02x%s\n", o & 0xff, d, t()); if #buf > 4096 then flush() end end
end)
-- "I" marks each fetch from 0038, the IM 1 vector: where the interrupt lands
_G.KEEP.i = cpu.spaces["program"]:install_read_tap(0x0038, 0x0038, "irq", function(o, d, m)
  if on then buf[#buf + 1] = "I\n" end
end)
_G.KEEP.f = emu.register_frame_done(function()
  frames = frames + 1
  if on then buf[#buf + 1] = string.format("F %d\n", frames) end
  P[":COIN"].fields["Coin 1"]:set_value((frames >= COIN and frames < COIN + 4) and 1 or 0)
  P[":SYSTEM"].fields["1 Player Start"]:set_value((frames >= START and frames < START + 4) and 1 or 0)
  if frames == LIMIT then on = false; flush() end
end)
_G.KEEP.s = emu.add_machine_stop_notifier(function()
  flush(); out:write(string.format("# frames %d\n", frames)); out:close()
end)
