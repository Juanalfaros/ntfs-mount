#!/bin/sh
# Builds ntfs-3g and ntfsfix against FUSE-T for the release assets, so people installing NTFS Mount
# need neither Homebrew nor the Xcode tools. Universal (arm64 + x86_64), libntfs-3g linked in statically.
#
#   sh release/build-ntfs3g.sh [output-dir]      (default: ./dist-release)
#
# Output: <out>/ntfs-3g-fuse-t-universal.tar.gz, containing bin/ntfs-3g, bin/ntfsfix and the licenses,
#         plus the exact upstream source tarball it was built from (GPL: the source goes with the binary).
#
# Nothing here is modified: ntfs-3g is upstream's release tarball, built as is. Only the FUSE-T headers and
# library (from FUSE-T's official, notarized installer) are needed to build; FUSE-T itself is NOT included.
set -eu

NTFS3G_VERSION=2026.9.28
NTFS3G_URL="https://tuxera.com/opensource/ntfs-3g_ntfsprogs-$NTFS3G_VERSION.tgz"
NTFS3G_SHA256=350d9415c59f7c3fa74e23985ad2d56423c6a168337368f672e2e362d8f295c8
FUSET_VERSION=1.2.9
FUSET_URL="https://github.com/macos-fuse-t/fuse-t/releases/download/$FUSET_VERSION/fuse-t-macos-installer-$FUSET_VERSION.pkg"
FUSET_SHA256=a1b893740ded8ea034f1acc522ded1144f4a567a1f416daef8c1441cf2662f7f

OUT="$(mkdir -p "${1:-dist-release}" && cd "${1:-dist-release}" && pwd)"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
sha() { [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$2" ] || { echo "checksum mismatch for $1" >&2; exit 1; }; }

echo "Fetching ntfs-3g $NTFS3G_VERSION and FUSE-T ${FUSET_VERSION}…"
# The exact upstream tarball is kept in this repository (release/sources): tuxera.com refuses downloads from
# some servers, and the GPL wants the source to travel with the binary anyway.
LOCAL_SRC="$(cd "$(dirname "$0")" && pwd)/sources/ntfs-3g_ntfsprogs-$NTFS3G_VERSION.tgz"
if [ -f "$LOCAL_SRC" ]; then cp "$LOCAL_SRC" "$W/ntfs-3g.tgz"; else curl -fsSL -o "$W/ntfs-3g.tgz" "$NTFS3G_URL"; fi
sha "$W/ntfs-3g.tgz" "$NTFS3G_SHA256"
curl -fsSL -o "$W/fuse-t.pkg" "$FUSET_URL";    sha "$W/fuse-t.pkg" "$FUSET_SHA256"

# FUSE-T headers and library, taken out of the installer without installing it. The path must not contain spaces.
pkgutil --expand "$W/fuse-t.pkg" "$W/pkg"
mkdir "$W/payload" && (cd "$W/payload" && gunzip -dc "$W/pkg/fuse-t-core.pkg/Payload" | cpio -id 2>/dev/null)
FT="$W/ft"; mkdir -p "$FT"
cp -R "$W/payload/Library/Application Support/fuse-t/include" "$W/payload/Library/Application Support/fuse-t/lib" "$FT/"
ln -sf "libfuse-t-$FUSET_VERSION.dylib" "$FT/lib/libfuse-t.dylib"

mkdir "$W/src" && tar -xzf "$W/ntfs-3g.tgz" -C "$W/src" --strip-components=1
cd "$W/src"
ARCH="-arch arm64 -arch x86_64"
# no pkg-config on a clean Mac: give configure the flags directly
PKG_CONFIG=/usr/bin/true ./configure --prefix="$W/prefix" --with-fuse=external --enable-ntfsprogs \
    --disable-shared --enable-static --disable-ldconfig --disable-mount-helper --disable-plugins \
    FUSE_MODULE_CFLAGS="-I$FT/include/fuse -D_FILE_OFFSET_BITS=64" FUSE_MODULE_LIBS="-L$FT/lib -lfuse-t" \
    CFLAGS="-O2 $ARCH -mmacosx-version-min=13.0" LDFLAGS="$ARCH" >"$W/configure.log" 2>&1 || { tail -20 "$W/configure.log"; exit 1; }
make -C libntfs-3g >"$W/make.log" 2>&1 && make -C src ntfs-3g >>"$W/make.log" 2>&1 && make -C ntfsprogs ntfsfix >>"$W/make.log" 2>&1 \
    || { tail -30 "$W/make.log"; exit 1; }

NAME="ntfs-3g-fuse-t-$NTFS3G_VERSION-universal"
B="$W/$NAME"; mkdir -p "$B/bin"
cp src/ntfs-3g ntfsprogs/ntfsfix "$B/bin/"
# FUSE-T's library names itself @rpath/…: point at the place its installer puts it, so install-root.sh can find it
# (and copy it into the root-owned folder) like any other dependency
for f in "$B"/bin/*; do
    install_name_tool -change @rpath/libfuse-t.dylib /usr/local/lib/libfuse-t.dylib "$f"
    codesign --force --sign - "$f" >/dev/null 2>&1
done
cp COPYING COPYING.LIB "$B/"
cat > "$B/README-SOURCE.txt" <<EOF
ntfs-3g $NTFS3G_VERSION, built unmodified from the upstream release tarball:
  $NTFS3G_URL  (sha256 $NTFS3G_SHA256)
The same tarball is attached to the release this file came from. Built by release/build-ntfs3g.sh in
https://github.com/Juanalfaros/ntfs-mount against FUSE-T $FUSET_VERSION's headers (FUSE-T itself is not included).
Licenses: ntfs-3g GPL-2.0-or-later (COPYING), libntfs-3g LGPL-2.0-or-later (COPYING.LIB, linked statically).
EOF

echo "Checking the result…"
for f in "$B"/bin/*; do
    lipo -info "$f" | sed 's/^/  /'
    otool -L "$f" | awk '/^[ \t]/ {print "    " $1}' | grep -v -E '/usr/lib/|/System/' || true
done
tar -C "$W" -czf "$OUT/ntfs-3g-fuse-t-universal.tar.gz" "$NAME"
cp "$W/ntfs-3g.tgz" "$OUT/ntfs-3g_ntfsprogs-$NTFS3G_VERSION.tgz"
( cd "$OUT" && shasum -a 256 ntfs-3g-fuse-t-universal.tar.gz "ntfs-3g_ntfsprogs-$NTFS3G_VERSION.tgz" > SHA256SUMS-ntfs3g.txt )
echo "Done: $OUT/ntfs-3g-fuse-t-universal.tar.gz (ntfs-3g $NTFS3G_VERSION)"
