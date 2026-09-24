#!/bin/sh
# Publish a release of a specific, hardware-verified bitstream.
#
# Usage: cut-release.sh <tag> <run-id | path/to/bitstream.rbf_r>
#        cut-release.sh v1.0.0 32214080417
#        cut-release.sh v0.1.0 release/pocket/Cores/plasticbugs.theglob/bitstream.rbf_r
#
# Takes the bitstream from that CI run, or that file, rather than recompiling,
# so the release ships the exact gateware that was tested on hardware -- which,
# when it was flashed from a local build, is that local file.  A rebuild is a
# twin, never the binary that was tested (METHODOLOGY 5.6).  Everything outside
# the bitstream (JSON definitions, ROM recipe, README) comes from the working
# tree, which is how a definition-only change can be released without a
# rebuild.
#
# Creating the tag triggers the Compile Core workflow; it sees the release
# already exists and skips publishing, leaving this artifact in place.
set -e
TAG="$1"
RUN="$2"
[ -n "$TAG" ] && [ -n "$RUN" ] || { echo "usage: cut-release.sh <tag> <run-id | bitstream.rbf_r>"; exit 1; }
case "$RUN" in /*) ;; *) [ -f "$RUN" ] && RUN="$PWD/$RUN" ;; esac
cd "$(dirname "$0")/.."

command -v gh >/dev/null || { echo "gh CLI required"; exit 1; }
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "release $TAG already exists; delete it first or pick another tag"; exit 1
fi
if [ -n "$(git status --porcelain pkg target rtl modules platform projects)" ]; then
    echo "working tree has uncommitted core changes; commit them so the tag matches"; exit 1
fi
# The Pocket shows core.json's version, not the tag (METHODOLOGY 5.5), so the
# two must agree.
VER=$(python3 -c "import json;print(json.load(open('pkg/pocket/Cores/plasticbugs.theglob/core.json'))['core']['metadata']['version'])")
[ "$TAG" = "v$VER" ] || { echo "tag $TAG disagrees with core.json version $VER"; exit 1; }
[ -f docs/release-notes.md ] || { echo "no docs/release-notes.md"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

if [ -f "$RUN" ]; then
    echo "bitstream from $RUN"
    mkdir -p "$STAGE/local/plasticbugs.theglob"
    cp "$RUN" "$STAGE/local/plasticbugs.theglob/bitstream.rbf_r"
else
    echo "fetching bitstream from run $RUN ..."
    gh run download "$RUN" -D "$STAGE" || { echo "download failed"; exit 1; }
fi
# One bitstream per core, each under its own Cores/<id>/ folder.
CORES=$(find "$STAGE" -name 'bitstream.rbf_r' -exec dirname {} \; | xargs -n1 basename | sort -u)
[ -n "$CORES" ] || { echo "no bitstream in $RUN"; exit 1; }
for c in $CORES; do
    RBF=$(find "$STAGE" -path "*/$c/bitstream.rbf_r" | head -1)
    SIZE=$(wc -c < "$RBF")
    [ "$SIZE" -gt 500000 ] || { echo "$c bitstream only $SIZE bytes, looks truncated"; exit 1; }
done

# Assemble the package: definitions from the tree, bitstream from the run.
OUT="$STAGE/release/pocket"
rm -rf "$OUT"; mkdir -p "$OUT"
# A ROM may sit in pkg/pocket/Assets locally (gitignored); never ship it.
tar -cf - --exclude '.DS_Store' --exclude '*.rom' --exclude '*.zip' \
    -C pkg/pocket . | tar -xf - -C "$OUT"
for c in $CORES; do
    RBF=$(find "$STAGE" -path "*/$c/bitstream.rbf_r" | head -1)
    [ -d "$OUT/Cores/$c" ] || { echo "a bitstream for $c but the tree has no such core"; exit 1; }
    cp "$RBF" "$OUT/Cores/$c/bitstream.rbf_r"
done
# A core folder with no bitstream would be one the Pocket cannot load.
for d in "$OUT"/Cores/*/; do
    [ -f "$d/bitstream.rbf_r" ] || { echo "no bitstream for $(basename "$d")"; exit 1; }
done
for extra in theglob.mra suprglob.mra README.md tools/mra_build.py; do
    [ -f "$extra" ] && cp "$extra" "$OUT/$(basename "$extra")"
done

# Sanity-check the package before it goes out.
for c in $CORES; do
    for f in core.json input.json interact.json data.json; do
        [ -e "$OUT/Cores/$c/$f" ] || { echo "package missing Cores/$c/$f"; exit 1; }
    done
    plat=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['core']['metadata']['platform_ids'][0])" \
           "$OUT/Cores/$c/core.json")
    [ -e "$OUT/Platforms/$plat.json" ] || { echo "package missing Platforms/$plat.json"; exit 1; }
    # The platform image is the user's artwork, supplied when it is ready;
    # the Pocket shows the core without one.
    [ -e "$OUT/Platforms/_images/$plat.bin" ] || echo "note: no Platforms/_images/$plat.bin (artwork not supplied yet)"
done
for j in "$OUT"/Cores/*/*.json "$OUT"/Platforms/*.json; do
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$j" || { echo "bad json: $j"; exit 1; }
done
if find "$OUT" -name '*.rom' -o -name '*.zip' | grep -q .; then
    echo "refusing to publish: a ROM or romset is in the package"; exit 1
fi

ZIP="$PWD/theglob-pocket-$TAG.zip"
rm -f "$ZIP"
(cd "$OUT" && zip -qr "$ZIP" .)
echo "package $VER, zip $(wc -c < "$ZIP") bytes"
for c in $CORES; do
    echo "  $c  md5 $(md5 -q "$OUT/Cores/$c/bitstream.rbf_r" 2>/dev/null || md5sum "$OUT/Cores/$c/bitstream.rbf_r" | cut -d' ' -f1)"
done

# Pre-release decided by the tag, not hard-coded (METHODOLOGY 5.6).
PRE=""
case "$TAG" in *-*) PRE="--prerelease" ;; esac
gh release create "$TAG" $PRE \
    --title "The Glob for Analogue Pocket $TAG" \
    --notes-file docs/release-notes.md \
    "$ZIP"
rm -f "$ZIP"
echo "published $TAG"
