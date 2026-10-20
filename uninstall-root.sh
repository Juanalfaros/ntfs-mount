#!/bin/sh
# Run as root by NTFS Mount (through the macOS admin prompt).
# Removes everything install-root.sh installed: the sudoers rule first (so no NOPASSWD access
# survives a partial run), then the helper and the private ntfs-3g copy.
#
# test: LIBEXEC=/some/dir SUDOERS=/some/file sh uninstall-root.sh   (no root needed)
PATH=/usr/bin:/bin:/usr/sbin:/sbin
LIBEXEC="${LIBEXEC:-/usr/local/libexec}"
SUDOERS="${SUDOERS:-/etc/sudoers.d/ntfsmount}"

rm -f "$SUDOERS"
[ -e "$SUDOERS" ] && { echo "could not delete $SUDOERS" >&2; exit 1; }
rm -rf "$LIBEXEC/ntfsmount" "$LIBEXEC/ntfsmount.new" "$LIBEXEC/ntfsmount.old"
rm -f "$LIBEXEC/ntfsmount-helper"
rmdir "$LIBEXEC" 2>/dev/null   # only if we left it empty
exit 0
