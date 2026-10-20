# Changelog

**English** · [Español](CHANGELOG.es.md)

## 2.0.0 (2026-10-20): Easy install

The big change: installing no longer means installing Homebrew, approving a kernel extension in Recovery, compiling
and typing commands. One line in Terminal does it all.

### Added

- **One-line installer** (`install.sh`): installs FUSE-T from its authors' notarized installer (checksum and
  signature verified), downloads the prebuilt universal app and ntfs-3g from the GitHub release (checksums
  verified), installs the privileged helper from a root-owned, re-verified copy, and opens the app. No Homebrew, no
  Xcode tools, no restart. `--check`, `--uninstall`, `--yes` and `--backend` options.
- **FUSE-T as the default mount layer**, so no kernel extension is needed. macFUSE remains available
  (`--backend macfuse`). Measured on a real USB disk: same speed as macFUSE, identical data, clean unmounts.
- **Prebuilt ntfs-3g for FUSE-T** (universal, arm64 + x86_64), built in GitHub Actions from the unmodified
  upstream source, which is kept in the repository and attached to each release.
- **Full Disk Access guide**: a fourth step in the Welcome window that checks the permission and opens the right
  System Settings pane.
- `ntfsmount://welcome` link; `NTFSMOUNT_SUDO` to ask for the password in a dialog.

### Improved

- Mounted volumes are found from the ntfs-3g process instead of the `mount` line, so it works with either layer.
- The helper no longer assumes ntfs-3g puts itself in the background, and waits up to 15 s for the mount.
- The app, Settings and Welcome name the layer in use (FUSE-T or macFUSE).

### Known limits

- With FUSE-T, extended attributes are not preserved when copying onto the disk, and a very fast SSD may be slower
  than with macFUSE. FUSE-T is free for non-commercial use only.
- Tested on one Mac (Apple Silicon, macOS 27); Intel and the macFUSE mode of 2.0 are lightly tested.

## 1.0.0 (2026-10-19): First public release

NTFS Mount becomes public: a menu bar app that mounts NTFS disks with write access on macOS, built on
ntfs-3g and macFUSE. This version was developed and tested on a single Mac (Apple Silicon, macOS 27.0.1,
macFUSE 5.4.0, ntfs-3g 2026.7.7).

### Added

- **English and Spanish interface**, following the Mac's language: menus, cards, settings, alerts,
  notifications and the macOS permission prompt. Any other language falls back to English. The terminal
  scripts (`install.sh`, `setup-signing.sh`, `build.sh`) speak both languages too, and the READMEs are in
  both.
- `NTFSMOUNT_LANG=en|es` to force the language of the terminal scripts, and `NTFSMOUNT_APP_DIR` to build the
  app somewhere else without touching the installed one.
- Tests that check every text has a Spanish translation with matching placeholders.
- MIT license, third-party notices and a documented way to install the privileged part by hand with `sudo`.

### Improved

- `install.sh` now asks before trusting the third-party Homebrew tap (`gromgit/fuse`) instead of doing it
  silently (use `--yes` to accept).
- The log, the diagnostics report and the messages of the privileged helper are in English, so they can be
  pasted into an issue and read by anyone.
- The privacy prompt for removable volumes is localized.

### Already in this version (developed privately before)

- Automatic mount with write access, one card per disk with usage, speed and a fill-up estimate, other
  volumes (exFAT, FAT, APFS), several disks at once, read-only per disk, mount/unmount/eject all.
- Notifications with actions, settings window, welcome screen, `ntfsmount://` links for Shortcuts.
- Unmount before sleep or shutdown, in-use detection naming the apps that hold files, errors with a way out
  (macOS permission, Windows hibernation or Fast Startup, `ntfsfix`, inactive macFUSE).
- Passwordless mounting through a sudoers rule limited to a validating helper that runs a root-owned private
  copy of ntfs-3g, a one-command installer and an uninstaller.
