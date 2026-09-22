#!/bin/sh
# The whole machine through the Pocket's memory glue: theglob_core against
# theglob_mem, with the ROM image pushed through the download port at the
# APF loader's rate (one byte per 8 clocks, strobe held 4).  -fast loads it a
# byte a clock instead, for iterating on the game; the default is the gate to
# pass before a flash (METHODOLOGY section 5.16).
#
#   sim/run_system.sh [rom] [-frames N] [-snap a,b,c] [-o DIR] [-coin F]
#       [-start F] [-play] [-service] [-dsw HEX] [-trace F] [-wav F] [-fast]
#
# rom defaults to .build/theglob.rom (tools/mra_build.py theglob.mra <romset>).
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
cd "$here"
verilator --version >/dev/null 2>&1 || { echo "verilator not found" >&2; exit 2; }

. "$here/waivers.sh"
MODS=$(ls "$root"/modules/*/*.v "$root"/modules/*/*.sv 2>/dev/null || true)

verilator --cc --exe --build -j "${JOBS:-8}" -O3 \
    -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    -Wno-PINCONNECTEMPTY -Wno-TIMESCALEMOD --no-assert-case \
    -Wno-BLKSEQ -Wno-MULTIDRIVEN -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-SYNCASYNCNET \
    "$WAIVERS" --top-module tb_system_top -Mdir obj_system \
    "$root"/rtl/*.sv $MODS "$root"/target/pocket/theglob_mem.sv \
    tb_system_top.sv tb_system.cpp > obj_system.log 2>&1 \
    || { tail -40 obj_system.log; exit 1; }

case "$1" in -*|"") rom="$root/.build/theglob.rom" ;; *) rom=$1; shift ;; esac
mkdir -p "$root/artifacts/system"
exec ./obj_system/Vtb_system_top "$rom" -o "$root/artifacts/system" "$@"
