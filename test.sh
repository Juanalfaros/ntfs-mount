#!/bin/sh
# Offline checks for NTFS Mount: no root, no disk and no network needed.
#   sh test.sh
cd "$(dirname "$0")" || exit 1
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH
pass=0; fail=0; skip=0
ok()   { pass=$((pass+1)); echo "  ok    $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL  $1${2:+ — $2}"; }
skp()  { skip=$((skip+1)); echo "  skip  $1"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "Syntax"
for f in ntfsmount-helper install-root.sh uninstall-root.sh setup-signing.sh build.sh install.sh package.sh test.sh; do
    if sh -n "$f" 2>/dev/null; then ok "$f"; else bad "$f"; fi
done
if swiftc -typecheck main.swift Parsing.swift Localization.swift Backend.swift 2>"$TMP/swift.err"; then ok "main.swift (typecheck)"; else bad "main.swift" "$(head -3 "$TMP/swift.err")"; fi

echo "Swift functions (Parsing.swift)"
mkdir -p "$TMP/tm"
cat > "$TMP/tm/main.swift" <<'SW'
import Foundation
func check(_ c: Bool, _ m: String) { if !c { print("FAIL \(m)"); exit(1) } }
let ps = """
  501 123 /Applications/Foo.app/Contents/MacOS/Foo
/usr/local/libexec/ntfsmount/bin/ntfs-3g /dev/disk4s1 /Volumes/Backup (2) -o local,allow_other,auto_xattr
/usr/local/libexec/ntfsmount/bin/ntfs-3g /dev/disk5s1 /Volumes/Data on Mac -o rw,backend=nfs,volname=Data on Mac
/usr/local/libexec/ntfsmount/bin/ntfs-3g /dev/disk6s1 /Volumes/Gone -o rw
/usr/local/libexec/ntfsmount/bin/ntfs-3g /dev/disk7s2 /Volumes/NoOptions
sshfs host:/ /Volumes/remote
"""
let mnt = """
/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
/dev/disk4s1 on /Volumes/Backup (2) (macfuse, local, nodev, nosuid, synchronous, mounted by user)
fuse-t:/Data on Mac on /Volumes/Data on Mac (nfs, nodev, nosuid, mounted by user)
/dev/disk7s2 on /Volumes/NoOptions (macfuse, nodev)
"""
let m = parseNtfs3gMounts(ps: ps, mount: mnt)
check(m["disk4s1"] == "/Volumes/Backup (2)", "macFUSE, parenthesis in the name: \(m)")
check(m["disk5s1"] == "/Volumes/Data on Mac", "FUSE-T (no device in mount), ' on ' in the name: \(m)")
check(m["disk6s1"] == nil, "a process whose volume is not mounted is ignored")
check(m["disk7s2"] == "/Volumes/NoOptions", "no -o options")
check(m.count == 3, "only ntfs-3g volumes: \(m)")
check(fuseTVersion(fromBinaryNames: ["go-nfsv4", "go-nfsv4-1.2.9", "go-nfsv4-1.10.0"]) == "1.10.0", "FUSE-T version")
check(fuseTVersion(fromBinaryNames: ["go-nfsv4"]) == nil, "FUSE-T version without a suffix")
check(cellarVersion("/opt/homebrew/Cellar/ntfs-3g-mac/2026.7.7/bin/ntfs-3g") == "2026.7.7", "cellar")
check(isNewer("5.10", than: "5.9") && !isNewer("5.9", than: "5.10"), "isNewer numérico")
print("ok")
SW
if swiftc -o "$TMP/t" Parsing.swift "$TMP/tm/main.swift" 2>"$TMP/t.err" && "$TMP/t" >"$TMP/t.out" 2>&1 && grep -q '^ok' "$TMP/t.out"; then ok "parseNtfs3gMounts, fuseTVersion, cellarVersion, isNewer"; else bad "Parsing.swift" "$(cat "$TMP/t.err" "$TMP/t.out" | head -3)"; fi

echo "Helper validation (must refuse without touching anything)"
nl='
'
expect() {  # description, expected message fragment, helper args...
    desc="$1"; frag="$2"; shift 2
    out=$(NTFSMOUNT_UNSAFE_BIN=1 sh ./ntfsmount-helper "$@" 2>&1); rc=$?
    if [ $rc -ne 0 ] && printf '%s' "$out" | grep -qF "$frag"; then ok "$desc"; else bad "$desc" "rc=$rc salida='$out'"; fi
}
if [ -x /opt/homebrew/bin/ntfs-3g ] || [ -x /usr/local/bin/ntfs-3g ]; then
    expect "mount: whole disk instead of a partition"   "invalid device"  mount disk4 x
    expect "mount: injection in the device"        "invalid device"  mount "disk4s1;rm x" x
    expect "mount: device with a newline"     "invalid device"  mount "disk4s1${nl}x" x
    expect "mount: partition that is not NTFS"          "is not an NTFS volume" mount disk0s1 x
    expect "fix: partition that is not NTFS"            "is not an NTFS volume" fix disk0s1
    expect "unmount: outside /Volumes"                "invalid mount point" unmount /etc
    expect "unmount: with .."                           "invalid mount point" unmount /Volumes/../etc
    expect "unmount: two-line path"               "invalid mount point" unmount "/Volumes/ok${nl}/etc"
    expect "cleanup: two-line path"               "invalid mount point" cleanup "/Volumes/ok${nl}/etc"
    expect "noindex: two-line path"               "invalid mount point" noindex "/Volumes/ok${nl}/etc"
    expect "eject: partition instead of a disk"          "invalid disk"        eject disk4s1
    expect "eject: disk with a newline"           "invalid disk"        eject "disk4${nl}x"
    expect "unknown action"                        "usage:"                  bogus
else
    skp "helper validation (ntfs-3g is not installed)"
fi
if [ -x /usr/local/libexec/ntfsmount/bin/ntfs-3g ]; then
    skp "without a private copy the helper does not use Homebrew (the copy is already installed on this Mac)"
else
    out=$(env -u NTFSMOUNT_UNSAFE_BIN sh ./ntfsmount-helper mount disk999s9 test 2>&1)
    if printf '%s' "$out" | grep -q "secure ntfs-3g copy"; then ok "without a private copy the helper does not use Homebrew"; else bad "insecure fallback" "$out"; fi
fi

echo "Private ntfs-3g copy (install-root.sh in a temp folder)"
if [ -x /opt/homebrew/bin/ntfs-3g ] || [ -x /usr/local/bin/ntfs-3g ]; then
    LX="$TMP/lx"; mkdir -p "$LX"
    if LIBEXEC="$LX" ONLY_COPY=1 sh install-root.sh x x >"$TMP/inst.out" 2>&1; then ok "install-root.sh finishes"; else bad "install-root.sh" "$(tail -3 "$TMP/inst.out")"; fi
    D="$LX/ntfsmount"
    [ -x "$D/bin/ntfs-3g" ] && [ -x "$D/bin/ntfsfix" ] && ok "binaries copied" || bad "binaries copied"
    sig=0; for f in "$D"/bin/* "$D"/lib/*; do codesign -v "$f" 2>/dev/null || sig=1; done
    [ $sig -eq 0 ] && ok "valid signatures" || bad "valid signatures"
    abs=$(for f in "$D"/bin/* "$D"/lib/*; do otool -L "$f" | awk '/^[ \t]/{print $1}'; done \
          | grep -v -E '^(@|/usr/lib/|/System/)' | grep -v -F 'macfuse.fs/Contents/Frameworks/MFMount.framework' | sort -u)
    [ -z "$abs" ] && ok "no dependencies outside the system" || bad "external dependencies" "$abs"
    [ "$(strings -a "$D"/bin/* "$D"/lib/* | grep -c '/opt/homebrew/Cellar/ntfs-3g')" = 0 ] && ok "plugin path repointed" || bad "plugin path"
    "$D/bin/ntfs-3g" 2>&1 | grep -q "no-plugins" && ok "the copy starts and loads its libraries" || bad "the copy does not start"
    [ -s "$D/SOURCE" ] && ok "SOURCE stamp written" || bad "SOURCE stamp"
else
    skp "private copy (ntfs-3g is not installed)"
fi

echo "Uninstaller (temp folder)"
UX="$TMP/ux"; mkdir -p "$UX/ntfsmount/bin"; : > "$UX/ntfsmount-helper"; : > "$UX/ntfsmount/bin/ntfs-3g"; : > "$TMP/sudoers"
if LIBEXEC="$UX" SUDOERS="$TMP/sudoers" sh uninstall-root.sh; then
    [ ! -e "$TMP/sudoers" ] && ok "removes the sudoers rule" || bad "sudoers rule still there"
    [ ! -e "$UX" ] && ok "removes helper, copy and the empty folder" || bad "files left behind" "$(ls -A "$UX")"
else bad "uninstall-root.sh failed"; fi

echo "Installer"
if NTFSMOUNT_LANG=en sh install.sh --check >"$TMP/check.out" 2>&1 && grep -q "NTFS Mount — installation" "$TMP/check.out"; then ok "install.sh --check reports without changing anything"; else bad "install.sh --check" "$(tail -2 "$TMP/check.out")"; fi
sh install.sh --bogus >/dev/null 2>&1; [ $? -eq 2 ] && ok "install.sh rejects unknown options" || bad "install.sh --bogus"

echo "Local signing"
if DRY_RUN=1 sh setup-signing.sh >"$TMP/sign.out" 2>&1; then ok "setup-signing.sh (dry run)"; else bad "setup-signing.sh" "$(tail -2 "$TMP/sign.out")"; fi

echo "Translations (es.lproj)"
if command -v python3 >/dev/null 2>&1; then
    if python3 - >"$TMP/i18n.out" 2>&1 <<'PY'
import re, sys
code = open("main.swift", encoding="utf-8").read()
used = set(re.findall(r'\bL\("((?:[^"\\]|\\.)*)"', code))
es = dict(re.findall(r'^"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$', open("es.lproj/Localizable.strings", encoding="utf-8").read(), re.M))
ph = lambda s: sorted(re.findall(r"\{\d+\}", s))
problems  = ["missing in Spanish: " + k for k in sorted(used - set(es))]
problems += ["unused Spanish entry: " + k for k in sorted(set(es) - used)]
problems += ["placeholders differ: " + k for k in used & set(es) if ph(k) != ph(es[k])]
print("\n".join(problems[:8]) or "ok")
sys.exit(1 if problems else 0)
PY
    then ok "every L(\"…\") key has a Spanish translation with the same placeholders"; else bad "translations" "$(head -3 "$TMP/i18n.out")"; fi
    plutil -lint es.lproj/Localizable.strings es.lproj/InfoPlist.strings >/dev/null 2>&1 && ok "es.lproj files are valid" || bad "es.lproj files"
else
    skp "translation checks (python3 not found)"
fi

echo
echo "$pass passed, $fail failed, $skip skipped"
[ $fail -eq 0 ]
