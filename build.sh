#!/bin/zsh
set -e
cd "$(dirname "$0")"
# NTFSMOUNT_APP_DIR builds somewhere else (e.g. to test) without touching the installed app or closing it.
DEST_DIR="${NTFSMOUNT_APP_DIR:-$HOME/Applications}"
APP="$DEST_DIR/NTFS Mount.app"
# Build next to the destination and swap at the end, so a failed compile never leaves you without an app.
FINAL="$APP"
APP="$DEST_DIR/.NTFS Mount.build.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
trap 'rm -rf "$APP"' EXIT
cp ntfsmount-helper install-root.sh uninstall-root.sh "$APP/Contents/Resources/"
# Spanish texts (English is the built-in language: the keys in the code)
mkdir -p "$APP/Contents/Resources/es.lproj"
cp es.lproj/Localizable.strings es.lproj/InfoPlist.strings "$APP/Contents/Resources/es.lproj/"
swiftc -O -o "$APP/Contents/MacOS/NTFSMount" main.swift Parsing.swift Localization.swift
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
<key>CFBundleName</key><string>NTFS Mount</string>
<key>CFBundleIdentifier</key><string>local.ntfsmount</string>
<key>CFBundleExecutable</key><string>NTFSMount</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>NSRemovableVolumesUsageDescription</key><string>NTFS Mount needs access to your external disks to mount them with write access.</string>
<key>LSUIElement</key><true/>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>local.ntfsmount</string>
<key>CFBundleURLSchemes</key><array><string>ntfsmount</string></array>
</dict></array>
</dict></plist>
P
# A stable local identity (see setup-signing.sh) keeps macOS privacy permissions across rebuilds;
# without it we fall back to an ad hoc signature, which changes every build.
LANG_PREF=${NTFSMOUNT_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z][a-z]\).*/\1/p')}
IDENTITY="NTFS Mount Local"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    if [ "$LANG_PREF" = es ]; then echo "(firma ad hoc: ejecuta 'sh setup-signing.sh' para conservar los permisos entre compilaciones)"
    else echo "(ad hoc signature: run 'sh setup-signing.sh' to keep macOS privacy permissions between builds)"; fi
    codesign --force --sign - "$APP"
fi
[ -z "${NTFSMOUNT_APP_DIR:-}" ] && { pkill -x NTFSMount 2>/dev/null || true; }
rm -rf "$FINAL"; mv "$APP" "$FINAL"
echo "Built: $FINAL"
