#!/bin/sh
# The Pocket's audio after the AY, held to bit-exact models sample for sample
# on this core's own audio (the Pocket-level signal of a WAV the system bench
# wrote; default artifacts/audio/rtl_play.wav, sim/run_system.sh -wav):
#   rtl/dc_block.sv      against tools/dc_block_model.py
#   rtl/lowpass.sv       against tools/lowpass_model.py, all three modes, fed
#                        the DC blocker's output
#   rtl/theglob_reverb.sv against tools/reverb_model.py, all four modes, fed
#                        the Light filter's output (the default) as core_top
#                        feeds it
#
#   sim/run_reverb.sh [wav]
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
wav=${1:-$root/artifacts/audio/rtl_play.wav}
cd "$here"
verilator --cc --exe --build -j "${JOBS:-8}" -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
    --top-module theglob_reverb -Mdir obj_reverb \
    "$root"/rtl/theglob_reverb.sv tb_reverb.cpp > obj_reverb.log 2>&1 \
    || { tail -40 obj_reverb.log; exit 1; }
verilator --cc --exe --build -j "${JOBS:-8}" -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
    --top-module dc_block -Mdir obj_dcb \
    "$root"/rtl/dc_block.sv tb_dc_block.cpp > obj_dcb.log 2>&1 \
    || { tail -40 obj_dcb.log; exit 1; }
verilator --cc --exe --build -j "${JOBS:-8}" -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
    --top-module lowpass -Mdir obj_lp \
    "$root"/rtl/lowpass.sv tb_lowpass.cpp > obj_lp.log 2>&1 \
    || { tail -40 obj_lp.log; exit 1; }
exec python3 - "$wav" "$root" <<'PY'
import os, struct, subprocess, sys
wav, root = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, 'tools'))
from compare_audio import read_wav
import reverb_model as rm
import dc_block_model as dm
import lowpass_model as lm
x, _ = read_wav(wav)
a = [(v + 12288) >> 1 for v in x]           # the Pocket level (rtl/ay8912.sv)
tmp = os.path.join(root, '.build'); os.makedirs(tmp, exist_ok=True)
open(f'{tmp}/dcb_in.raw', 'wb').write(struct.pack(f'<{len(a)}h', *a))
subprocess.run(['./obj_dcb/Vdc_block', f'{tmp}/dcb_in.raw', f'{tmp}/dcb_out.raw'], check=True)
d = open(f'{tmp}/dcb_out.raw', 'rb').read()
p = list(struct.unpack(f'<{len(d)//2}h', d))
ref = dm.run(a)
bad = sum(1 for u, w in zip(p, ref) if u != w) + abs(len(p) - len(ref))
print(f'dc_block: {len(p)} samples, {bad} differ from the model, mean {sum(p)/max(1,len(p)):.1f} (in: {sum(a)/len(a):.1f})')
open(f'{tmp}/lp_in.raw', 'wb').write(struct.pack(f'<{len(p)}h', *p))
lp_in = p
for mode in (0, 2, 1):                       # 1, the default, last: it feeds the reverb
    subprocess.run(['./obj_lp/Vlowpass', f'{tmp}/lp_in.raw', f'{tmp}/lp_out.raw', str(mode)], check=True)
    d = open(f'{tmp}/lp_out.raw', 'rb').read()
    p = list(struct.unpack(f'<{len(d)//2}h', d))
    ref = lm.run(lp_in, mode)
    n = sum(1 for u, w in zip(p, ref) if u != w) + abs(len(p) - len(ref))
    print(f'lowpass mode {mode}: {len(p)} samples, {n} differ from the model')
    bad += n
open(f'{tmp}/rv_in.raw', 'wb').write(struct.pack(f'<{len(p)}h', *p))
for mode in range(4):
    subprocess.run(['./obj_reverb/Vtheglob_reverb', f'{tmp}/rv_in.raw', f'{tmp}/rv_out.raw', str(mode)], check=True)
    d = open(f'{tmp}/rv_out.raw', 'rb').read()
    rtl = list(struct.unpack(f'<{len(d)//2}h', d))
    ref = rm.run(p, mode)
    diff = sum(1 for a, b in zip(rtl, ref) if a != b) + abs(len(rtl) - len(ref))
    rails = sum(1 for v in rtl if v >= 32767 or v <= -32768)
    print(f'mode {mode}: {len(rtl)} samples, {diff} differ from the model, {rails} at the rails')
    bad += diff
print('audio gate:', 'PASS' if bad == 0 else 'FAIL')
sys.exit(1 if bad else 0)
PY
