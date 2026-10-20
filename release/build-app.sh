#!/bin/sh
# Builds the universal NTFS Mount.app for the release assets (ad hoc signed: install.sh re-signs it on each Mac
# with a local certificate, so macOS keeps the privacy permission between updates).
#
#   sh release/build-app.sh [output-dir]      (default: ./dist-release)   ->  <out>/NTFS-Mount-app.zip
set -eu
cd "$(dirname "$0")/.."
OUT="$(mkdir -p "${1:-dist-release}" && cd "${1:-dist-release}" && pwd)"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
NTFSMOUNT_APP_DIR="$W" NTFSMOUNT_UNIVERSAL=1 NTFSMOUNT_ADHOC=1 ./build.sh
lipo -info "$W/NTFS Mount.app/Contents/MacOS/NTFSMount"
rm -f "$OUT/NTFS-Mount-app.zip"
ditto -c -k --keepParent "$W/NTFS Mount.app" "$OUT/NTFS-Mount-app.zip"
echo "Done: $OUT/NTFS-Mount-app.zip ($(cat VERSION))"
