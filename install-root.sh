#!/bin/sh
# Run as root by NTFS Mount (through the macOS admin prompt).
#
# Installs, all root-owned:
#   * a private copy of ntfs-3g/ntfsfix and the Homebrew libraries they need, under
#     /usr/local/libexec/ntfsmount, so the NOPASSWD helper never executes code that a
#     normal user process could modify (Homebrew's prefix is user-writable);
#   * the privileged helper and the sudoers rule that allows only that helper.
#
# usage: install-root.sh <helper-source> <username>
# test:  LIBEXEC=/some/dir ONLY_COPY=1 sh install-root.sh x x   (no root needed)
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin

SRC_HELPER="${1:?helper}"; USER_NAME="${2:?user}"
LIBEXEC="${LIBEXEC:-/usr/local/libexec}"
DEST="$LIBEXEC/ntfsmount"
NEW="$DEST.new"
IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1

die() { echo "$*" >&2; exit 1; }
# install_name_tool warns that it invalidates the signature (we re-sign below); keep the rest
int() { install_name_tool "$@" 2>&1 | grep -v 'invalidate the code signature' >&2 || true; }

NTFS=""
for p in /opt/homebrew/bin/ntfs-3g /usr/local/bin/ntfs-3g; do
    if [ -x "$p" ]; then NTFS="$p"; break; fi
done
[ -n "$NTFS" ] || die "ntfs-3g is not installed"
REAL=$(readlink -f "$NTFS")
SRCBIN=$(dirname "$REAL")

# Root-owned files are only as safe as the folder that holds them: whoever can write the folder
# can delete and replace them. Refuse a user-writable /usr/local/libexec when running as root.
mkdir -p "$LIBEXEC"
if [ $IS_ROOT -eq 1 ]; then
    chown root:wheel "$LIBEXEC" && chmod 755 "$LIBEXEC" || die "could not secure $LIBEXEC"
fi

rm -rf "$NEW"
mkdir -p "$NEW/bin" "$NEW/lib"
cp "$SRCBIN/ntfs-3g" "$SRCBIN/ntfsfix" "$NEW/bin/"
chmod u+w "$NEW"/bin/*

# Copy every non-system dependency and point the binaries at the copies.
fix_deps() {
    local f dep base rel   # recursive: must not clobber the caller's variables
    f="$1"
    # dependency lines start with a tab; universal binaries also print one header line per arch
    otool -L "$f" | awk '/^[ \t]/ {print $1}' | sort -u | while read -r dep; do
        case "$dep" in
        /usr/lib/*|/System/*) ;;
        @*) ;;
        *)
            if [ ! -e "$dep" ]; then   # weak dependency that isn't installed (e.g. libfuse -> MFMount)
                echo "warning: skipping missing dependency $dep" >&2
                continue
            fi
            # Anything else (Homebrew libs, macFUSE's libfuse in the user-owned /usr/local/lib...)
            # is copied. Outside Homebrew's prefix the file must currently belong to root, so a
            # file already swapped by a user process is rejected.
            case "$dep" in
            /opt/homebrew/*|/usr/local/Cellar/*|/usr/local/opt/*) ;;
            *) [ "$(stat -f %u "$(readlink -f "$dep")")" = "0" ] \
                   || die "$dep is not owned by root; it is not safe to copy it with privileges" ;;
            esac
            base=$(basename "$dep")
            if [ ! -f "$NEW/lib/$base" ]; then
                cp "$(readlink -f "$dep")" "$NEW/lib/$base"
                chmod u+w "$NEW/lib/$base"
                int -id "@loader_path/$base" "$NEW/lib/$base"
                fix_deps "$NEW/lib/$base"
            fi
            case "$f" in
            "$NEW"/bin/*) rel="@executable_path/../lib/$base" ;;
            *)            rel="@loader_path/$base" ;;
            esac
            int -change "$dep" "$rel" "$f"
            ;;
        esac
    done
}
for f in "$NEW"/bin/*; do fix_deps "$f"; done

# ntfs-3g dlopen()s plugins, and gettext reads catalogs, from paths compiled into them (inside
# Homebrew's user-writable Cellar). Point both at root-owned locations, keeping the string length.
for f in "$NEW"/bin/* "$NEW"/lib/*; do
    perl -0777 -pi -e '
        my $dir = "/usr/local/libexec/ntfsmount/no-plugins";
        # same-length replacements (padded with NULs) so offsets inside the binary do not move
        sub pad { my ($new, $old) = @_; length($new) <= length($old) ? $new . "\0" x (length($old) - length($new)) : $old }
        s{/opt/homebrew/[^\0]*?/lib/ntfs-3g/ntfs-plugin-%08lx\.so}{ pad("$dir/ntfs-plugin-%08lx.so", $&) }ge;
        s{/opt/homebrew/[^\0\n]*?/lib/ntfs-3g(?=[\n\0])}{ pad($dir, $&) }ge;
        s{/opt/homebrew/[^\0]*?/share/locale}{ pad("/usr/local/libexec/ntfsmount/locale", $&) }ge;   # gettext catalogs
    ' "$f"
done
if strings -a "$NEW"/bin/* "$NEW"/lib/* | grep -q 'ntfs-3g/ntfs-plugin'; then
    echo "warning: a plugin path was left unreplaced" >&2
fi

# install_name_tool and the patch invalidate the signature (required on Apple Silicon)
for f in "$NEW"/lib/* "$NEW"/bin/*; do codesign --force --sign - "$f" >/dev/null 2>&1 || die "could not sign $f"; done
# a failure inside the dependency loop is otherwise silent: verify nothing still points outside
for f in "$NEW"/bin/* "$NEW"/lib/*; do
    bad=$(otool -L "$f" | awk '/^[ \t]/ {print $1}' | grep -v -E '^(@|/usr/lib/|/System/)' || true)
    # libfuse's weak MFMount reference (framework not installed) is the only absolute path allowed
    bad=$(printf '%s\n' "$bad" | grep -v -F 'macfuse.fs/Contents/Frameworks/MFMount.framework' | grep -v '^$' || true)
    [ -z "$bad" ] || die "$f still depends on: $bad"
done
printf '%s\n' "$REAL" > "$NEW/SOURCE"

chmod -R go-w "$NEW"
[ $IS_ROOT -eq 1 ] && chown -R root:wheel "$NEW"
rm -rf "$DEST.old"
[ -d "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$NEW" "$DEST"
rm -rf "$DEST.old"

[ -n "${ONLY_COPY:-}" ] && exit 0

install -o root -g wheel -m 755 "$SRC_HELPER" "$LIBEXEC/ntfsmount-helper"
T=$(mktemp)
printf '%s ALL=(root) NOPASSWD: %s\n' "$USER_NAME" "$LIBEXEC/ntfsmount-helper" > "$T"
visudo -cf "$T" >/dev/null || { rm -f "$T"; die "invalid sudoers rule"; }
install -o root -g wheel -m 440 "$T" /etc/sudoers.d/ntfsmount
rm -f "$T"
