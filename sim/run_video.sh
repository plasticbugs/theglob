#!/bin/sh
# The frozen-state gate for rtl/theglob_video.sv: every state in sim/states
# is rendered by tools/render_model.py and by the RTL, and the pens must be
# identical.  Every change to RTL that draws pixels goes through this before
# it is committed.
#
#   sim/run_video.sh [rom]        (rom: the built image, for the PROM; default .build/theglob.rom)
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
rom=${1:-$root/.build/theglob.rom}
cd "$here"
verilator --cc --exe --build -j "${JOBS:-8}" -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
    --top-module tb_video_top -Mdir obj_video \
    "$root"/rtl/theglob_video.sv tb_video_top.sv tb_video.cpp > obj_video.log 2>&1 \
    || { tail -40 obj_video.log; exit 1; }
out="$root/.build/video"
mkdir -p "$out"
python3 "$root/tools/render_model.py" "$rom" "$root"/sim/states/state_*.bin -o "$out" > "$out/model.log" \
    || { cat "$out/model.log"; echo "the model itself no longer matches MAME"; exit 1; }
fail=0
for s in "$root"/sim/states/state_*.bin; do
    n=$(python3 -c "import struct,sys; print('%05d' % struct.unpack('<I', open(sys.argv[1],'rb').read()[8:12])[0])" "$s")
    ./obj_video/Vtb_video_top "$s" "$out/pens_$n.bin" "$out/rtl_$n.pens" || fail=1
done
[ $fail = 0 ] && echo "video gate: PASS" || { echo "video gate: FAIL"; exit 1; }
