#!/bin/sh
# NTFS Mount installer: one command, nothing to compile.
#
#   curl -fsSL https://raw.githubusercontent.com/Juanalfaros/ntfs-mount/main/install.sh | sh
#
# What it does: installs FUSE-T (from its authors' notarized installer) if you do not have it, downloads the
# prebuilt app and ntfs-3g from this project's latest GitHub release, checks their checksums, installs the
# privileged helper and puts the app in ~/Applications. It asks for your password once (sudo).
# Files downloaded with curl are not quarantined by macOS, so Gatekeeper has nothing to block.
#
# Messages are in English or Spanish, following your Mac's language (NTFSMOUNT_LANG=en|es to force one).
# Options (after "sh -s --" when piping):
#   --check          only report the state of every piece; changes nothing
#   --yes            do not ask questions
#   --uninstall      remove the app, the helper and the private ntfs-3g copy (FUSE-T stays)
#   --backend NAME   fuse-t (default, no kernel extension) or macfuse (needs Homebrew and macFUSE)
#   --from-source    build from a clone of the repository instead (see install-from-source.sh)
#   --no-sign        do not offer the local signing certificate
set -u
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH

REPO=Juanalfaros/ntfs-mount
BASE="${NTFSMOUNT_BASE_URL:-https://github.com/$REPO/releases/latest/download}"
ASSET_DIR="${NTFSMOUNT_ASSET_DIR:-}"          # tests: take the assets from a local folder instead of downloading
FUSET_VERSION=1.2.9
FUSET_URL="https://github.com/macos-fuse-t/fuse-t/releases/download/$FUSET_VERSION/fuse-t-macos-installer-$FUSET_VERSION.pkg"
FUSET_SHA256=a1b893740ded8ea034f1acc522ded1144f4a567a1f416daef8c1441cf2662f7f
FUSET_TEAM=6DY7Z4SVDZ                          # the Developer ID that signs FUSE-T's installer

LANG_PREF=${NTFSMOUNT_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z][a-z]\).*/\1/p')}
T() { if [ "$LANG_PREF" = es ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }   # T "English" "Español"

CHECK=0; YES=0; UNINSTALL=0; SIGN=ask; BACKEND=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --yes|-y) YES=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --no-sign) SIGN=no ;;
        --backend) shift; BACKEND="${1:-}" ;;
        --from-source) shift; DIR=$(cd "$(dirname "$0")" && pwd); exec sh "$DIR/install-from-source.sh" "$@" ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "$(T 'unknown option' 'opción desconocida'): $1" >&2; exit 2 ;;
    esac
    shift
done
case "$BACKEND" in ""|fuse-t|macfuse) ;; *) echo "$(T 'unknown backend' 'backend desconocido'): $BACKEND" >&2; exit 2 ;; esac

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
todo() { printf '  • %s\n' "$*"; }
die()  { printf '\n✗ %s\n' "$*" >&2; exit 1; }
# the script usually arrives through a pipe, so questions are read from the terminal
ask()  { [ $YES -eq 1 ] && return 0; [ -r /dev/tty ] || return 1; printf '%s [y/N] ' "$1" >/dev/tty; read -r r </dev/tty; case "$r" in y|Y|yes|YES|s|S|si|SI|sí) return 0 ;; *) return 1 ;; esac; }
sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

LIBEXEC=/usr/local/libexec
APPS="$HOME/Applications"; APP="$APPS/NTFS Mount.app"
FUSET_OK=0; [ -x "/Library/Application Support/fuse-t/bin/go-nfsv4" ] && FUSET_OK=1
MACFUSE_OK=0; [ -d /Library/Filesystems/macfuse.fs ] && MACFUSE_OK=1
# the backend: what you asked for, else what the installed copy already uses, else whatever is installed
if [ -z "$BACKEND" ]; then
    BACKEND=$(cat "$LIBEXEC/ntfsmount/BACKEND" 2>/dev/null)
    if [ -z "$BACKEND" ]; then
        if [ $FUSET_OK -eq 1 ]; then BACKEND=fuse-t
        elif [ $MACFUSE_OK -eq 1 ]; then BACKEND=macfuse
        else BACKEND=fuse-t; fi
    fi
fi

say "$(T 'NTFS Mount — installation' 'NTFS Mount — instalación')"
say ""

# --- state ----------------------------------------------------------------------------------
major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -ge 13 ]; then ok "macOS $(sw_vers -productVersion) ($(uname -m))"
else die "$(T "macOS 13 or later is required (you have $(sw_vers -productVersion))." "Hace falta macOS 13 o posterior (tienes $(sw_vers -productVersion)).")"; fi
ok "$(T 'Layer to use:' 'Capa a usar:') $([ "$BACKEND" = fuse-t ] && echo FUSE-T || echo macFUSE)"
if [ "$BACKEND" = fuse-t ]; then
    if [ $FUSET_OK -eq 1 ]; then ok "FUSE-T"; else todo "$(T 'FUSE-T is not installed (it will be installed)' 'FUSE-T no está instalado (se instalará)')"; fi
    if [ $MACFUSE_OK -eq 1 ]; then todo "$(T 'macFUSE is also installed: it works, but the two share some files; remove one if you see problems' 'macFUSE también está instalado: funciona, pero comparten algunos archivos; quita uno si ves problemas')"; fi
else
    if [ $MACFUSE_OK -eq 1 ]; then ok "macFUSE"; else todo "$(T 'macFUSE is not installed' 'macFUSE no está instalado')"; fi
    if command -v brew >/dev/null 2>&1; then ok "Homebrew"; else todo "$(T 'Homebrew is missing (https://brew.sh)' 'Falta Homebrew (https://brew.sh)')"; fi
fi
if [ -x "$LIBEXEC/ntfsmount/bin/ntfs-3g" ] && [ -x "$LIBEXEC/ntfsmount-helper" ]; then ok "$(T 'Helper and private ntfs-3g copy' 'Helper y copia privada de ntfs-3g')"
else todo "$(T 'Helper and private ntfs-3g copy not installed' 'Helper y copia privada de ntfs-3g sin instalar')"; fi
if [ -d "$APP" ]; then ok "$(T 'App' 'App') $(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
else todo "$(T 'The app is not installed' 'La app no está instalada')"; fi
if security find-identity -p codesigning 2>/dev/null | grep -q "NTFS Mount Local"; then ok "$(T 'Local signing certificate' 'Certificado local de firma')"
else todo "$(T 'No local signing certificate (macOS asks for its permission again after every update)' 'Sin certificado local de firma (macOS pide el permiso de nuevo tras cada actualización)')"; fi
[ $CHECK -eq 1 ] && { say ""; exit 0; }

# --- uninstall ------------------------------------------------------------------------------
if [ $UNINSTALL -eq 1 ]; then
    say ""
    ask "$(T 'Remove NTFS Mount (app, helper and private ntfs-3g copy)?' '¿Quitar NTFS Mount (app, helper y copia privada de ntfs-3g)?')" || die "$(T 'Cancelled.' 'Cancelado.')"
    osascript -e 'tell application "NTFS Mount" to quit' >/dev/null 2>&1; sleep 1
    if [ -f "$APP/Contents/Resources/uninstall-root.sh" ]; then
        R=$(mktemp -d); cp "$APP/Contents/Resources/uninstall-root.sh" "$R/"
        sudo sh "$R/uninstall-root.sh"; rm -rf "$R"
    else
        sudo rm -f /etc/sudoers.d/ntfsmount "$LIBEXEC/ntfsmount-helper"; sudo rm -rf "$LIBEXEC/ntfsmount"
    fi
    rm -rf "$APP"
    say "$(T 'Removed. FUSE-T stays installed (to remove it: "/Library/Application Support/fuse-t/uninstall.sh").' 'Listo. FUSE-T sigue instalado (para quitarlo: "/Library/Application Support/fuse-t/uninstall.sh").')"
    exit 0
fi

# --- download -------------------------------------------------------------------------------
W=$(mktemp -d) || die "mktemp"; trap 'rm -rf "$W"' EXIT
fetch() {   # fetch <asset name> -> $W/<name>
    if [ -n "$ASSET_DIR" ]; then cp "$ASSET_DIR/$1" "$W/$1" 2>/dev/null || die "$(T "missing asset" "falta el archivo") $1"
    else curl -fsSL --retry 3 -o "$W/$1" "$BASE/$1" || die "$(T "could not download" "no se pudo descargar") $1"; fi
}
verified() {  # verified <asset name>: compare with the release's SHA256SUMS.txt
    want=$(grep " $1\$" "$W/SHA256SUMS.txt" | cut -d' ' -f1)
    [ -n "$want" ] && [ "$(sha256 "$W/$1")" = "$want" ] || die "$(T "checksum mismatch for" "la suma de verificación no coincide en") $1"
}
say ""
say "$(T 'Downloading NTFS Mount…' 'Descargando NTFS Mount…')"
fetch SHA256SUMS.txt
fetch NTFS-Mount-app.zip; verified NTFS-Mount-app.zip
ditto -x -k "$W/NTFS-Mount-app.zip" "$W/app" || die "unzip"
NEWAPP="$W/app/NTFS Mount.app"; RES="$NEWAPP/Contents/Resources"
[ -f "$RES/install-root.sh" ] || die "$(T 'the downloaded app is incomplete' 'la app descargada está incompleta')"
SRC_BIN=""
if [ "$BACKEND" = fuse-t ]; then
    fetch ntfs-3g-fuse-t-universal.tar.gz; verified ntfs-3g-fuse-t-universal.tar.gz
    mkdir "$W/n3g" && tar -xzf "$W/ntfs-3g-fuse-t-universal.tar.gz" -C "$W/n3g" --strip-components=1 || die "untar"
    SRC_BIN="$W/n3g/bin"
fi

# --- the FUSE layer -------------------------------------------------------------------------
if [ "$BACKEND" = fuse-t ] && [ $FUSET_OK -eq 0 ]; then
    say "$(T "Installing FUSE-T $FUSET_VERSION (from its authors; free for non-commercial use)…" "Instalando FUSE-T $FUSET_VERSION (de sus autores; gratis para uso no comercial)…")"
    PKG="${NTFSMOUNT_FUSET_PKG:-$W/fuse-t.pkg}"
    [ -n "${NTFSMOUNT_FUSET_PKG:-}" ] || curl -fsSL --retry 3 -o "$PKG" "$FUSET_URL" || die "$(T 'could not download FUSE-T' 'no se pudo descargar FUSE-T')"
    [ "$(sha256 "$PKG")" = "$FUSET_SHA256" ] || die "$(T 'FUSE-T checksum mismatch' 'la suma de verificación de FUSE-T no coincide')"
    pkgutil --check-signature "$PKG" 2>/dev/null | grep -q "$FUSET_TEAM" || die "$(T 'FUSE-T installer is not signed by its authors' 'el instalador de FUSE-T no está firmado por sus autores')"
    sudo installer -pkg "$PKG" -target / >/dev/null || die "$(T 'FUSE-T could not be installed' 'no se pudo instalar FUSE-T')"
elif [ "$BACKEND" = macfuse ]; then
    command -v brew >/dev/null 2>&1 || die "$(T 'Install Homebrew from https://brew.sh and run this again.' 'Instala Homebrew desde https://brew.sh y vuelve a ejecutar esto.')"
    if [ $MACFUSE_OK -eq 0 ]; then
        say "$(T 'Installing macFUSE (it will ask for your password)…' 'Instalando macFUSE (pedirá tu contraseña)…')"
        brew install --cask macfuse || die "$(T 'Could not install macFUSE.' 'No se pudo instalar macFUSE.')"
        say "$(T 'Approve the macFUSE extension in System Settings → Privacy & Security and restart, then run this again.' 'Aprueba la extensión de macFUSE en Ajustes del Sistema → Privacidad y seguridad y reinicia; luego vuelve a ejecutar esto.')"
    fi
    if ! [ -x /opt/homebrew/bin/ntfs-3g ] && ! [ -x /usr/local/bin/ntfs-3g ]; then
        brew tap gromgit/homebrew-fuse || die "tap"
        if brew trust --help >/dev/null 2>&1; then
            ask "$(T 'ntfs-3g-mac comes from a third-party tap (gromgit/fuse). Trust that one formula?' 'ntfs-3g-mac viene de un tap de terceros (gromgit/fuse). ¿Confiar solo en esa fórmula?')" \
                && brew trust --formula gromgit/fuse/ntfs-3g-mac >/dev/null 2>&1 || die "$(T 'Cannot install ntfs-3g-mac without trusting it.' 'No se puede instalar ntfs-3g-mac sin confiar en ella.')"
        fi
        brew install ntfs-3g-mac || die "$(T 'Could not install ntfs-3g-mac.' 'No se pudo instalar ntfs-3g-mac.')"
    fi
fi

# --- the privileged part --------------------------------------------------------------------
# Root first copies the files into a folder only root can touch, checks them against the hashes taken here, and
# only then runs them, so nothing can be swapped between the download and the install.
say "$(T 'Installing the helper (it asks for your password once)…' 'Instalando el helper (pide tu contraseña una vez)…')"
H_HELPER=$(sha256 "$RES/ntfsmount-helper"); H_INST=$(sha256 "$RES/install-root.sh")
H_N3G=""; H_FIX=""
[ -n "$SRC_BIN" ] && { H_N3G=$(sha256 "$SRC_BIN/ntfs-3g"); H_FIX=$(sha256 "$SRC_BIN/ntfsfix"); }
sudo env NTFSMOUNT_BACKEND="$BACKEND" sh -c '
    set -eu
    R=$(mktemp -d); chmod 700 "$R"; trap "rm -rf \"$R\"" EXIT
    cp "$1" "$R/ntfsmount-helper"; cp "$2" "$R/install-root.sh"
    chk() { [ "$(shasum -a 256 "$1" | cut -d" " -f1)" = "$2" ] || { echo "checksum mismatch: $1" >&2; exit 1; }; }
    chk "$R/ntfsmount-helper" "$3"; chk "$R/install-root.sh" "$4"
    if [ -n "$5" ]; then
        mkdir "$R/bin"; cp "$6/ntfs-3g" "$6/ntfsfix" "$R/bin/"
        chk "$R/bin/ntfs-3g" "$5"; chk "$R/bin/ntfsfix" "$7"
        NTFSMOUNT_SRC_BIN="$R/bin"; export NTFSMOUNT_SRC_BIN
    fi
    sh "$R/install-root.sh" "$R/ntfsmount-helper" "$8"
' sh "$RES/ntfsmount-helper" "$RES/install-root.sh" "$H_HELPER" "$H_INST" "$H_N3G" "${SRC_BIN:-/nonexistent}" "$H_FIX" "$(id -un)" \
    || die "$(T 'The helper could not be installed.' 'No se pudo instalar el helper.')"

# --- the app --------------------------------------------------------------------------------
osascript -e 'tell application "NTFS Mount" to quit' >/dev/null 2>&1; sleep 1; pkill -x NTFSMount 2>/dev/null
mkdir -p "$APPS"; rm -rf "$APP"; ditto "$NEWAPP" "$APP" || die "$(T 'could not copy the app' 'no se pudo copiar la app')"
# a local identity keeps macOS's privacy permission between updates (the downloaded app is only ad hoc signed)
if ! security find-identity -p codesigning 2>/dev/null | grep -q "NTFS Mount Local" && [ "$SIGN" != no ]; then
    if ask "$(T 'Create a local signing certificate so macOS remembers the permission you will grant? (macOS asks for your password once)' '¿Crear un certificado local de firma para que macOS recuerde el permiso que darás? (macOS pedirá tu contraseña una vez)')"; then
        sh "$APP/Contents/Resources/setup-signing.sh" || say "  $(T 'could not create the certificate; the app stays ad hoc signed.' 'no se pudo crear el certificado; la app sigue con firma ad hoc.')"
    fi
fi
security find-identity -p codesigning 2>/dev/null | grep -q "NTFS Mount Local" && codesign --force --sign "NTFS Mount Local" "$APP" >/dev/null 2>&1

say ""
say "$(T 'Done. Last step, once:' 'Listo. Último paso, una sola vez:')"
say "  $(T 'In the window that opens, follow “Allow Full Disk Access”: add NTFS Mount to the list and turn it on.' 'En la ventana que se abre, sigue «Permitir el Acceso total al disco»: agrega NTFS Mount a la lista y actívalo.')"
say ""
open "$APP"
sleep 2; osascript -e 'tell application "NTFS Mount" to activate' >/dev/null 2>&1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null
open "ntfsmount://welcome" 2>/dev/null
exit 0
