#!/bin/sh
# BUILD-FROM-SOURCE installer (macFUSE + Homebrew + Xcode tools). For developers; everyone else uses install.sh.
# Idempotent: it only does what is missing. Messages are in English or Spanish, following your Mac's
# language (force one with NTFSMOUNT_LANG=en or NTFSMOUNT_LANG=es).
#
#   sh install.sh            install whatever is missing, build the app and open it
#   sh install.sh --check    only report the state of every piece; changes nothing
#   sh install.sh --yes      don't ask questions (also creates the signing certificate and trusts the tap)
#   sh install.sh --no-sign  don't offer the local signing certificate
set -u
cd "$(dirname "$0")" || exit 1
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH

LANG_PREF=${NTFSMOUNT_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z][a-z]\).*/\1/p')}
T() { if [ "$LANG_PREF" = es ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }   # T "English" "Español"

CHECK=0; YES=0; SIGN=ask
for a in "$@"; do
    case "$a" in
        --check) CHECK=1 ;;
        --yes|-y) YES=1 ;;
        --no-sign) SIGN=no ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "$(T 'unknown option' 'opción desconocida'): $a" >&2; exit 2 ;;
    esac
done

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
todo() { printf '  • %s\n' "$*"; }
die()  { printf '\n✗ %s\n' "$*" >&2; exit 1; }
ask()  { [ $YES -eq 1 ] && return 0; printf '%s [y/N] ' "$1"; read -r r; case "$r" in y|Y|yes|YES|s|S|si|SI|sí) return 0 ;; *) return 1 ;; esac; }

PENDING=""
need() { PENDING="$PENDING $1"; }

say "$(T 'NTFS Mount — installation' 'NTFS Mount — instalación')"
say ""

# --- macOS ---------------------------------------------------------------------------------
major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -ge 13 ]; then ok "macOS $(sw_vers -productVersion)"
else die "$(T "macOS 13 or later is required (you have $(sw_vers -productVersion))." "Hace falta macOS 13 o posterior (tienes $(sw_vers -productVersion)).")"; fi

# --- Xcode command line tools ---------------------------------------------------------------
if xcode-select -p >/dev/null 2>&1 && command -v swiftc >/dev/null 2>&1; then
    ok "$(T 'Xcode command line tools' 'Herramientas de línea de comandos de Xcode')"
else
    todo "$(T 'The Xcode command line tools (Swift compiler) are missing' 'Faltan las herramientas de línea de comandos de Xcode (compilador de Swift)')"; need xcode
fi

# --- Homebrew -------------------------------------------------------------------------------
if command -v brew >/dev/null 2>&1; then ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
else todo "$(T 'Homebrew is missing (https://brew.sh)' 'Falta Homebrew (https://brew.sh)')"; need brew; fi

# --- macFUSE --------------------------------------------------------------------------------
if [ -d /Library/Filesystems/macfuse.fs ]; then
    ok "macFUSE $(defaults read /Library/Filesystems/macfuse.fs/Contents/Info CFBundleShortVersionString 2>/dev/null)"
else todo "$(T 'macFUSE is missing' 'Falta macFUSE')"; need macfuse; fi

# --- ntfs-3g --------------------------------------------------------------------------------
if [ -x /opt/homebrew/bin/ntfs-3g ] || [ -x /usr/local/bin/ntfs-3g ]; then ok "ntfs-3g"
else todo "$(T 'ntfs-3g is missing (gromgit/fuse/ntfs-3g-mac)' 'Falta ntfs-3g (gromgit/fuse/ntfs-3g-mac)')"; need ntfs3g; fi

# --- signing --------------------------------------------------------------------------------
if security find-identity -p codesigning 2>/dev/null | grep -q "NTFS Mount Local"; then
    ok "$(T 'Local signing certificate “NTFS Mount Local”' 'Certificado local de firma «NTFS Mount Local»')"
else
    todo "$(T 'No local signing certificate (macOS will ask for its permissions again after every build)' 'Sin certificado de firma local (los permisos de macOS se pedirán de nuevo tras cada compilación)')"; need sign
fi

# --- the app --------------------------------------------------------------------------------
APP="$HOME/Applications/NTFS Mount.app"
if [ -d "$APP" ]; then ok "$(T 'App installed in ~/Applications' 'App instalada en ~/Applications')"
else todo "$(T 'The app is not installed' 'La app no está instalada')"; need app; fi

# --- private components ---------------------------------------------------------------------
if [ -x /usr/local/libexec/ntfsmount/bin/ntfs-3g ] && [ -x /usr/local/libexec/ntfsmount-helper ]; then
    if cmp -s ntfsmount-helper /usr/local/libexec/ntfsmount-helper; then ok "$(T 'Passwordless mounting is on' 'Montaje sin contraseña activo')"
    else todo "$(T 'Passwordless mounting is out of date (click “Turn on…” in the app menu)' 'Montaje sin contraseña desactualizado (pulsa «Activar…» en el menú de la app)')"; fi
else todo "$(T 'Passwordless mounting is not on yet (turn it on from the app menu)' 'Montaje sin contraseña sin activar (se activa desde el menú de la app)')"; fi

if [ $CHECK -eq 1 ]; then
    say ""
    if [ -z "$PENDING" ]; then say "$(T 'Everything is in place.' 'Todo está en su sitio.')"
    else say "$(T 'Pending:' 'Pendiente:')$PENDING"; fi
    exit 0
fi

say ""

# --- fix what is missing --------------------------------------------------------------------
case "$PENDING" in *xcode*)
    say "$(T 'Installing the Xcode tools: accept the dialog that appears and run this script again when it finishes.' 'Instalando las herramientas de Xcode: acepta el cuadro que aparece y vuelve a ejecutar este script al terminar.')"
    xcode-select --install 2>/dev/null
    exit 0 ;;
esac
case "$PENDING" in *brew*)
    die "$(T 'Install Homebrew from https://brew.sh and run this script again.' 'Instala Homebrew desde https://brew.sh y vuelve a ejecutar este script.')" ;;
esac

reboot_hint=0
case "$PENDING" in *macfuse*)
    say "$(T 'Installing macFUSE (it will ask for your password)…' 'Instalando macFUSE (pedirá tu contraseña)…')"
    brew install --cask macfuse || die "$(T 'Could not install macFUSE.' 'No se pudo instalar macFUSE.')"
    reboot_hint=1 ;;
esac
case "$PENDING" in *ntfs3g*)
    say "$(T 'Installing ntfs-3g…' 'Instalando ntfs-3g…')"
    brew tap gromgit/homebrew-fuse || die "$(T 'Could not add the gromgit/fuse tap.' 'No se pudo añadir el tap gromgit/fuse.')"
    # Homebrew 5+ only loads third-party formulae you explicitly trust. That is your decision, so ask.
    if brew trust --help >/dev/null 2>&1; then
        if ask "$(T 'ntfs-3g-mac comes from a third-party tap (gromgit/fuse). Trust that one formula?' 'ntfs-3g-mac viene de un tap de terceros (gromgit/fuse). ¿Confiar solo en esa fórmula?')"; then
            brew trust --formula gromgit/fuse/ntfs-3g-mac >/dev/null 2>&1
        else
            die "$(T 'Cannot install ntfs-3g-mac without trusting it.' 'No se puede instalar ntfs-3g-mac sin confiar en ella.')"
        fi
    fi
    brew install ntfs-3g-mac || die "$(T 'Could not install ntfs-3g-mac.' 'No se pudo instalar ntfs-3g-mac.')"
    ;;
esac
case "$PENDING" in *sign*)
    if [ "$SIGN" != no ] && ask "$(T 'Create the local signing certificate? (macOS will ask for your password once)' '¿Crear el certificado local de firma? (macOS pedirá tu contraseña una vez)')"; then
        sh ./setup-signing.sh || say "  $(T 'could not create the certificate; the app will be signed ad hoc.' 'no se pudo crear el certificado; se firmará ad hoc.')"
    fi ;;
esac

say "$(T 'Building the app…' 'Compilando la app…')"
./build.sh || die "$(T 'The build failed.' 'Falló la compilación.')"

say ""
say "$(T 'Done. Next steps:' 'Listo. Siguientes pasos:')"
n=1
if [ $reboot_hint -eq 1 ]; then
    say "  $n. $(T 'Approve the macFUSE extension in System Settings → Privacy & Security and restart.' 'Aprueba la extensión de macFUSE en Ajustes del Sistema → Privacidad y seguridad y reinicia.')"; n=$((n+1))
fi
say "  $n. $(T 'Open “NTFS Mount” and grant the permissions it asks for (removable volumes; Full Disk Access).' 'Abre «NTFS Mount» y concede los permisos que pida (volúmenes extraíbles; Acceso total al disco).')"; n=$((n+1))
say "  $n. $(T 'In the menu: “Turn on passwordless mounting…” (just once).' 'En el menú: «Activar montaje sin contraseña…» (una sola vez).')"
say ""
open "$APP" 2>/dev/null
