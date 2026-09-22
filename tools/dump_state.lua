-- Dump theglob's whole video state at chosen frames, with MAME's own pixels
-- for the same frame, so tools/render_model.py can be checked against it
-- pixel for pixel and the RTL video bench can load it.
--
--   DUMPFRAMES=300,1200 DUMP_DIR=... tools/mame.sh -seconds_to_run 40 \
--       -autoboot_script tools/dump_state.lua
--
-- The game is driven from here: a coin at COIN, 1P start at START, then the
-- joystick and buttons move by a fixed pseudo-random script (PLAY=0 turns it
-- off), so a given frame number is the same state on every run.  SERVICE=1
-- holds the service switch from power-on.  DSW=<hex> sets the DIP bank.
-- PRESS="frame:field:frames,..." presses any :INPUTS or :SYSTEM field by its
-- MAME name, e.g. PRESS="700:P1 Down:4,760:P1 Button 1:4".
--
-- Frame alignment, measured (not assumed): in the frame-done callback,
-- screen:pixels() is the picture MAME drew from the VRAM as it stood at the
-- PREVIOUS frame-done callback.  Checked on five frames of gameplay: the
-- same-frame VRAM differs from those pixels by up to 496 pixels, the
-- previous frame's by none.  So a state for frame N holds the VRAM, RAM and
-- palette bank read at callback N-1 and the pixels read at callback N: the
-- two halves of the file describe the same picture.
--
-- One binary file per frame, little-endian:
--   magic "TGST", u32 version=1, u32 frame
--   u32 palette bank (port 01 bit 3, as last written)
--   u8  vram[32768]          8000-FFFF
--   u8  ram[2048]            7800-7FFF
--   u32 width, u32 height    of MAME's screen bitmap (272 x 236)
--   u32 pixels[h][w]         MAME's output, straight from screen:pixels()

local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local sp  = cpu.spaces["program"]
local iosp = cpu.spaces["io"]
local scr = mac.screens[":screen"]
local dir = os.getenv("DUMP_DIR") or "."

local want = {}
for n in string.gmatch(os.getenv("DUMPFRAMES") or "300", "%d+") do
  want[tonumber(n)] = true
end
local COIN  = tonumber(os.getenv("COIN")  or "120")
local START = tonumber(os.getenv("START") or "180")
local PLAY  = os.getenv("PLAY") ~= "0"

local P = mac.ioport.ports
local f_coin  = P[":COIN"].fields["Coin 1"]
local f_start = P[":SYSTEM"].fields["1 Player Start"]
local f_svc   = P[":SYSTEM"].fields["Service Mode"]
local dirs = {
  P[":INPUTS"].fields["P1 Up"],    P[":INPUTS"].fields["P1 Down"],
  P[":INPUTS"].fields["P1 Left"],  P[":INPUTS"].fields["P1 Right"],
}
local b1 = P[":INPUTS"].fields["P1 Button 1"]
local b2 = P[":INPUTS"].fields["P1 Button 2"]

if os.getenv("DSW") then
  local v = tonumber(os.getenv("DSW"), 16)
  for _, fld in pairs(P[":DSW"].fields) do
    fld:set_value((v & fld.mask) ~= 0 and 1 or 0)
  end
end
if os.getenv("SERVICE") == "1" then f_svc:set_value(1) end

_G.KEEP = {}
local palbank = 0
_G.KEEP.pb = iosp:install_write_tap(0x01, 0x01, "palbank", function(o, d, m)
  palbank = (d >> 3) & 1
end)

local function u32(f, v)
  f:write(string.char(v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff))
end

local function bytes(base, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.char(sp:read_u8(base + i)) end
  return table.concat(t)
end

-- the machine state, taken one callback before the pixels it produced
local held_state = nil
local function take()
  held_state = { palbank = palbank, vram = bytes(0x8000, 32768), ram = bytes(0x7800, 2048) }
end

local function dump(n)
  local f = io.open(string.format("%s/state_%05d.bin", dir, n), "wb")
  f:write("TGST"); u32(f, 1); u32(f, n); u32(f, held_state.palbank)
  f:write(held_state.vram)
  f:write(held_state.ram)
  local pix, w, h = scr:pixels()
  u32(f, w); u32(f, h)
  f:write(pix)
  f:close()
end

local presses = {}
for fr, name, len in string.gmatch(os.getenv("PRESS") or "", "(%d+):([^:,]+):(%d+)") do
  local fld = P[":INPUTS"].fields[name] or P[":SYSTEM"].fields[name]
  assert(fld, "no input field named " .. name)
  presses[#presses + 1] = { from = tonumber(fr), to = tonumber(fr) + tonumber(len), fld = fld }
end

local frames = 0
local lcg = 12345
local held = nil
_G.KEEP.fd = emu.register_frame_done(function()
  frames = frames + 1
  f_coin:set_value((frames >= COIN and frames < COIN + 4) and 1 or 0)
  f_start:set_value((frames >= START and frames < START + 4) and 1 or 0)
  if PLAY and frames > START + 30 and frames % 20 == 0 then
    lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
    if held then held:set_value(0) end
    held = dirs[(lcg >> 16) % 4 + 1]
    held:set_value(1)
    b1:set_value(((lcg >> 8) & 3) == 0 and 1 or 0)
    b2:set_value(((lcg >> 10) & 7) == 0 and 1 or 0)
  end
  for _, p in ipairs(presses) do
    if frames == p.from then p.fld:set_value(1) elseif frames == p.to then p.fld:set_value(0) end
  end
  if want[frames] and held_state then dump(frames) end
  held_state = nil
  if want[frames + 1] then take() end
end)

_G.KEEP.s = emu.add_machine_stop_notifier(function()
  local f = io.open(dir .. "/frames.txt", "w")
  f:write(frames .. "\n"); f:close()
end)
