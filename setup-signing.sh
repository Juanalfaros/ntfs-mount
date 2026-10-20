#!/bin/sh
# Creates a self-signed code-signing certificate ("NTFS Mount Local") in your login keychain.
# build.sh then signs every build with it, so macOS keeps the privacy permissions you granted
# (Full Disk Access, removable volumes) instead of asking again after each recompilation.
# No Apple Developer account needed; the certificate never leaves your Mac.
#
#   sh setup-signing.sh            create + import + trust (macOS asks for your password once)
#   DRY_RUN=1 sh setup-signing.sh  only generate and validate the files, touch nothing
set -eu
NAME="NTFS Mount Local"
KC="$HOME/Library/Keychains/login.keychain-db"
LANG_PREF=${NTFSMOUNT_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z][a-z]\).*/\1/p')}
T() { if [ "$LANG_PREF" = es ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }   # T "English" "Español"

if [ -z "${DRY_RUN:-}" ] && security find-certificate -c "$NAME" "$KC" >/dev/null 2>&1; then
    echo "$(T "“$NAME” already exists in your keychain. Nothing to do." "«$NAME» ya existe en tu llavero. Nada que hacer.")"
    exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat > "$T/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# /usr/bin/openssl is LibreSSL, whose default PKCS#12 encryption `security import` understands
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$T/cert.cnf" \
    -keyout "$T/key.pem" -out "$T/cert.pem" 2>/dev/null
PASS=$(/usr/bin/openssl rand -hex 12)
/usr/bin/openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" -out "$T/id.p12" \
    -name "$NAME" -passout "pass:$PASS"

if [ -n "${DRY_RUN:-}" ]; then
    /usr/bin/openssl x509 -in "$T/cert.pem" -noout -text | grep -q "Code Signing" \
        || { echo "$(T "the certificate does not have the “Code Signing” usage" "el certificado no tiene el uso «Code Signing»")" >&2; exit 1; }
    /usr/bin/openssl pkcs12 -in "$T/id.p12" -passin "pass:$PASS" -nokeys -noout \
        || { echo "$(T "the PKCS#12 file could not be read back" "el PKCS#12 no se pudo releer")" >&2; exit 1; }
    echo "$(T "dry run: files generated and valid; the keychain was not touched." "dry run: archivos generados y válidos; no se tocó el llavero.")"
    exit 0
fi

security import "$T/id.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "$(T "Certificate imported. macOS will ask for your password to trust it for code signing…" "Certificado importado. macOS pedirá tu contraseña para marcarlo como de confianza para firmar código…")"
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$T/cert.pem"
echo "$(T "Done. Build again with ./build.sh; the first time macOS may ask to let codesign use the key (“Always Allow”)." "Listo. Vuelve a compilar con ./build.sh; la primera vez macOS puede pedir permiso a codesign para usar la llave («Permitir siempre»).")"
