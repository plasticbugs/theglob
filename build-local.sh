#!/bin/sh
# Compile the The Glob Pocket core with Quartus 18.1 in Docker (x86 emulation on ARM Macs).
#
#   ./build-local.sh          full compile + package
#   ./build-local.sh map      analysis & synthesis only (~a couple of minutes)
#
# Run the map check before every push: it catches syntax and inference errors
# without paying for a full fit, and a broken push costs a whole CI cycle.
set -e
cd "$(dirname "$0")"
FLOW=${1:-compile}
case "$FLOW" in
    map) CMD="quartus_map --read_settings_files=on projects/theglob_pocket.qpf -c theglob_pocket" ;;
    compile) CMD="quartus_sh --flow compile projects/theglob_pocket.qpf" ;;
    *) echo "usage: $0 [map|compile]"; exit 2 ;;
esac
docker run --rm --platform linux/amd64 \
    -v "$PWD":/build -w /build \
    raetro/quartus:pocket \
    $CMD
[ "$FLOW" = compile ] && python3 package-pocket.py || true
