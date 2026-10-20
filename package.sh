#!/bin/sh
# Builds a .dmg with the app, to move NTFS Mount to another Mac without compiling there.
#   sh package.sh        -> dist/NTFS-Mount-<version>.dmg
#
# The app inside is signed with your local identity (or ad hoc), not with an Apple Developer ID, so on
# another Mac Gatekeeper will refuse the first launch: see README.txt inside the image.
set -eu
cd "$(dirname "$0")"
APP="$HOME/Applications/NTFS Mount.app"

./build.sh
VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)
OUT="dist/NTFS-Mount-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/NTFS Mount.app"          # ditto keeps the signature and attributes intact
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/README.txt" <<TXT
NTFS Mount $VERSION
===================

[English]
Mounts NTFS disks with write access (macFUSE + ntfs-3g). Personal use, at your own risk.

1. Before opening the app, on this Mac:
     brew install --cask macfuse
     brew tap gromgit/homebrew-fuse
     brew install ntfs-3g-mac
   and approve the macFUSE extension in System Settings > Privacy & Security (it may ask you to restart).
   Shortcut, if you have the project folder:  sh install.sh

2. Drag "NTFS Mount" to Applications.

3. The first time, macOS will block it (it is not notarized). Open a terminal and run:
     xattr -dr com.apple.quarantine "/Applications/NTFS Mount.app"

4. Grant the permissions it asks for (removable volumes; Full Disk Access) and, in the menu bar item,
   click "Turn on passwordless mounting…" once.

More information: the project's README.md.

[Español]
Monta discos NTFS con escritura (macFUSE + ntfs-3g). Uso personal, bajo tu responsabilidad.

1. Antes de abrir la app necesitas, en este Mac:
     brew install --cask macfuse
     brew tap gromgit/homebrew-fuse
     brew install ntfs-3g-mac
   y aprobar la extensión de macFUSE en Ajustes del Sistema > Privacidad y seguridad (puede pedir reiniciar).
   Atajo, si tienes la carpeta del proyecto:  sh install.sh

2. Arrastra «NTFS Mount» a Aplicaciones.

3. La primera vez macOS la bloqueará (no está notarizada). Abre una terminal y ejecuta:
     xattr -dr com.apple.quarantine "/Applications/NTFS Mount.app"

4. Concede los permisos que pida (volúmenes extraíbles; Acceso total al disco) y, en el menú de la barra,
   pulsa «Activar montaje sin contraseña…» una vez.

Más información: README.md del proyecto.
TXT

mkdir -p dist
rm -f "$OUT"
hdiutil create -quiet -volname "NTFS Mount" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
echo "Created: $OUT ($(du -h "$OUT" | cut -f1))"
