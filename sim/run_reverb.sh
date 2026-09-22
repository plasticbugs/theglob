#!/bin/sh
# The cabinet reverb's port, held to its bit-exact model (tools/reverb_model.py)
# sample for sample in all four modes, on this core's own audio: the
# Pocket-level signal of a WAV the system bench wrote (default
# artifacts/audio/rtl_play.wav, sim/run_system.sh -wav).
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
exec python3 - "$wav" "$root" <<'PY'
import os, struct, subprocess, sys
wav, root = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, 'tools'))
from compare_audio import read_wav
import reverb_model as rm
x, _ = read_wav(wav)
p = [(v + 12288) >> 1 for v in x]           # the Pocket level (rtl/ay8912.sv)
tmp = os.path.join(root, '.build'); os.makedirs(tmp, exist_ok=True)
open(f'{tmp}/rv_in.raw', 'wb').write(struct.pack(f'<{len(p)}h', *p))
bad = 0
for mode in range(4):
    subprocess.run(['./obj_reverb/Vtheglob_reverb', f'{tmp}/rv_in.raw', f'{tmp}/rv_out.raw', str(mode)], check=True)
    d = open(f'{tmp}/rv_out.raw', 'rb').read()
    rtl = list(struct.unpack(f'<{len(d)//2}h', d))
    ref = rm.run(p, mode)
    diff = sum(1 for a, b in zip(rtl, ref) if a != b) + abs(len(rtl) - len(ref))
    rails = sum(1 for v in rtl if v >= 32767 or v <= -32768)
    print(f'mode {mode}: {len(rtl)} samples, {diff} differ from the model, {rails} at the rails')
    bad += diff
print('reverb gate:', 'PASS' if bad == 0 else 'FAIL')
sys.exit(1 if bad else 0)
PY
