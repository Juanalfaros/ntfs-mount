# NTFS Mount

**English** · [Español](README.es.md)

A menu bar app for macOS that mounts NTFS disks **with write access**, using
[`ntfs-3g`](https://github.com/tuxera/ntfs-3g) and [macFUSE](https://macfuse.github.io). A free, open
alternative to commercial NTFS drivers: one Swift app (`main.swift`), no third-party code inside it.

The interface speaks **English and Spanish** and follows your Mac's language.

> **Please read before using it**
>
> - NTFS write support from user space is convenient, but it can corrupt a disk if it is unplugged badly
>   or if something goes wrong. **Back up anything you care about** and use the app at your own risk
>   (see the [license](LICENSE)).
> - It was developed and tested on **one Mac**: Apple Silicon, macOS 27.0.1, FUSE-T 1.2.9, ntfs-3g
>   2026.9.28 (and, for the macFUSE mode, macFUSE 5.4.0). Intel Macs and other macOS versions are untested.
>   If you try it, please [open an issue](../../issues) and tell us how it went.
> - It is **not signed or notarized by Apple** (that needs a paid developer account). The one-line installer
>   avoids the warnings macOS shows for downloaded apps; see [Install](#install).

Requires macOS 13 or later.

## What it does

- **Mounts by itself, with write access.** When you plug in an NTFS disk, macOS mounts it read-only; the
  app unmounts it and mounts it again with `ntfs-3g`, without asking for a password.
- **A card per disk in the menu:** state, % free, a usage bar (green → orange → red, with a mark at 90 %),
  live speed, a mini graph of the last minute with its peak and, while you copy, how long until the disk
  is full. Buttons right on the card (Finder, Eject, Mount); clicking the card opens the disk. The rest
  (unmount without ejecting, read-only, repair, details) is under "More options".
- **Other volumes:** external exFAT, FAT or APFS disks show up in a submenu with the same card, for
  information only (macOS already handles them), with Finder and Eject.
- **Several disks at once**, even with the same name (the second one mounts as "name 1").
- **Read-only per disk:** "Always read-only" is remembered by partition UUID.
- **Mount all with write access** and **Unmount all without ejecting** (with two or more disks),
  **Eject** (unmounts every partition of the disk), **Eject all disks** (⌘E) and a "You can now
  disconnect…" notice. If a disk is busy it tells you **which apps** have files open and offers to close
  them and retry.
- **Notifications with buttons:** automatic mount (Open / Eject), disk unplugged without ejecting (What to
  do), less than 5 % free (Open).
- **Settings (⌘,)** in a window: General, Mounting, Remembered disks and Advanced (status, diagnostics,
  log, macFUSE, uninstall). A **Welcome** screen with the setup steps the first time something is missing.
- **Links** `ntfsmount://eject-all` and `ntfsmount://settings`, to use from Shortcuts.
- Monochrome menu bar icon (colored only when something needs attention), fixed-width speed readout,
  VoiceOver on the cards and "Reduce motion" support.
- **Unmounts before sleep or shutdown**, so NTFS volumes are not left "dirty".
- **Errors with a way out:** macOS permission, Windows hibernation or Fast Startup (mount discarding the
  hibernation), a file system that was not closed properly (`ntfsfix`) and macFUSE not active.
- **macFUSE health:** warns when the extension is not approved or loaded (typical after a macOS update)
  and can check whether a newer version exists.
- **Diagnostics and log:** Settings → Advanced → "Copy diagnostics" with everything useful for debugging,
  and a log at `~/Library/Logs/NTFSMount.log` (always in English, so it can be pasted into an issue).
- Keeps Spotlight from indexing the disks, an option for Windows-compatible file names and "Open at
  login".

## Install

Open **Terminal** and paste this single line:

```sh
curl -fsSL https://raw.githubusercontent.com/Juanalfaros/ntfs-mount/main/install.sh | sh
```

It asks for your password once, and then:

1. installs **FUSE-T** (from its authors' own notarized installer, after checking its checksum and signature) if
   you do not have it;
2. downloads the app and ntfs-3g from this project's latest release and checks their checksums;
3. installs the privileged helper that lets disks mount without a password prompt;
4. puts **NTFS Mount** in `~/Applications` and opens it.

There is nothing to compile, no Homebrew and no restart. Files downloaded with `curl` are not quarantined by
macOS, so Gatekeeper has nothing to block.

**The one step it cannot do for you** is *Full Disk Access*, which macOS only lets you grant yourself. The
Welcome window that opens guides you: add **NTFS Mount** to the list in *System Settings → Privacy &
Security → Full Disk Access* and turn it on. (Neither root, nor a daemon, nor a password prompt can skip it:
macOS asks for it for any program that opens a raw disk.) The installer also offers to create a local signing
certificate so macOS remembers that permission across updates.

Options (add them after `sh -s --`): `--check` reports the state without changing anything, `--yes` asks no
questions, `--uninstall` removes everything, `--backend macfuse` uses macFUSE instead, `--from-source` builds
from a clone of this repository. Its messages follow your Mac's language (`NTFSMOUNT_LANG=en` or `es`).

### Two ways to mount: FUSE-T (default) or macFUSE

| | **FUSE-T** (default) | macFUSE |
|---|---|---|
| Install | One command, no restart | Kernel extension: on Apple Silicon you must lower startup security in Recovery and approve it |
| Speed | Same as macFUSE on a USB disk in our test (see below); slower on a very fast SSD | The fastest |
| Extended attributes | Not preserved when copying | Emulated |
| License | Free for **non-commercial** use; a company needs a license from FUSE-T's authors | Free to use |

On a 1 TB USB disk we measured writing 1 GB at 22.6 MB/s with FUSE-T and 23.7 MB/s with macFUSE, reading at 73.9
and 56.5 MB/s, with identical data and clean unmounts in both. Its NFS backend is slower on very fast SSDs
(users report ~20 vs ~700 MB/s); FUSE-T's SMB backend failed our file-creation tests and is not used.

The macFUSE mode is what version 1 used (Homebrew's `ntfs-3g-mac`); it still works with `--backend macfuse` but
has had much less testing in 2.0. FUSE-T and macFUSE are not meant to be installed together: they overwrite one
shared library file (`libfuse3`).

### Building it yourself

`sh install-from-source.sh` builds the app on your Mac (needs Homebrew, macFUSE and the Xcode command line
tools; it is the version 1 flow). `sh build.sh` only rebuilds the app.

### Installing the privileged part yourself

The installer runs `install-root.sh` as root from a root-owned copy whose checksum it verified. If you would
rather read and run it yourself, do:

```sh
sudo sh install-root.sh ntfsmount-helper "$USER"          # macFUSE mode (needs Homebrew's ntfs-3g)
sudo NTFSMOUNT_BACKEND=fuse-t NTFSMOUNT_SRC_BIN=/path/to/ntfs-3g-fuse-t/bin sh install-root.sh ntfsmount-helper "$USER"
```

## How it works

```
NTFS Mount.app (your user)  ──sudo -n──▶  /usr/local/libexec/ntfsmount-helper (root)
        │                                          │ validates every argument
        │                                          ▼
        │                           /usr/local/libexec/ntfsmount/bin/ntfs-3g  (private copy, root)
        │                                          │
        └── DiskArbitration (events), IOKit (speed), statfs (space)
```

| File | What it is for |
|---|---|
| `main.swift` + `Parsing.swift` | The app (and its pure functions, with tests): menu, cards, events, monitoring, errors |
| `Localization.swift` + `es.lproj/` | Translations. The keys in the code are the English texts; Spanish lives in `es.lproj/Localizable.strings` |
| `ntfsmount-helper` | `sh` script that runs as root: `mount`, `unmount`, `eject`, `fix`, `cleanup`, `noindex`, `loadfuse`. Validates everything it receives |
| `install-root.sh` | Run as root: installs the helper, the sudoers rule and the private copy of ntfs-3g |
| `uninstall-root.sh` | Undoes the above |
| `setup-signing.sh` | Creates the local signing certificate |
| `build.sh` | Builds, assembles the `.app` in `~/Applications` and signs it |
| `install.sh` | The one-line installer: downloads and verifies the release files, installs FUSE-T, the helper and the app |
| `install-from-source.sh` | The version 1 installer: builds the app on your Mac (Homebrew + macFUSE) |
| `Backend.swift` | Which FUSE layer is in use (FUSE-T or macFUSE) and how to detect it |
| `release/` | Scripts that build the release files (universal app, ntfs-3g for FUSE-T) and the pinned ntfs-3g source |
| `test.sh` | Tests with no root, no disk and no network |

### Security model

Passwordless mounting is a sudoers rule (`/etc/sudoers.d/ntfsmount`) that lets your user run **only**
`ntfsmount-helper` as root. For that not to be a door to root:

- The helper lives in a root-owned folder and validates all its arguments (device `diskNsM`, mount points
  only under `/Volumes`, no newlines or `..`, no commas in names that could inject options).
- Homebrew lives in a folder your user owns, so a process running as you could replace its `ntfs-3g`. That
  is why the installer **copies `ntfs-3g`, `ntfsfix` and their libraries** (`libntfs-3g`, `libintl`,
  `libfuse`, `MFMount`) into `/usr/local/libexec/ntfsmount/`, owned by root, rewrites their internal paths,
  points the plugin and language paths to root-owned folders and signs them again. `/usr/local/lib` is
  also user-owned on this kind of install, which is why `libfuse` is copied instead of used from there.
- The only path that uses Homebrew's `ntfs-3g` is the password one (no helper installed), enabled with
  `NTFSMOUNT_UNSAFE_BIN=1`; `sudo` drops that variable, so the passwordless path never uses it.

Known limit: the installer runs from the app bundle, which is yours. A malicious process running as your
user could tamper with it right before you click the button and type your password. If that worries you,
install by hand with `sudo` as described [above](#installing-the-privileged-part-yourself). To report a
security problem, please use GitHub's private vulnerability reporting for this repository instead of a
public issue.

## Moving it to another Mac

Run the same one-line installer on the other Mac. (`sh package.sh` can still build a `.dmg`, but a downloaded
`.dmg` triggers Gatekeeper; the installer does not.)

## Maintenance

- **Updating NTFS Mount:** run the installer again. It replaces the app, the helper and ntfs-3g, and if you created the
  local certificate macOS keeps your Full Disk Access permission.
- **macFUSE mode:** `brew upgrade ntfs-3g-mac` makes the private copy outdated but it keeps working; the menu shows
  **Update ntfs-3g copy (old → new)…** to refresh it.
- **FUSE-T / macFUSE:** Settings → Advanced → **Check for … updates…** (the only time the app uses the network,
  and only when you ask). After updating you have to approve the extension again and restart.
- **If you change the helper or the scripts:** click "Turn on…" again; the app detects that the installed
  copy differs from the one in the bundle.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Operation not permitted` opening `/dev/diskNsM` | NTFS Mount lacks *Full Disk Access* (or the signature changed). Grant it and restart the app |
| "macFUSE is not active" in the menu | The extension is not approved or loaded. System Settings → Privacy & Security; sometimes a restart is needed |
| "Hibernated or Windows Fast Startup" | Windows left the disk half-closed. Best: start Windows and shut it down completely. Or "Mount anyway" (discards the hibernated session, not your files) |
| "Needs repair" | The volume was not closed properly. `ntfsfix` tries; for serious cases use `chkdsk` on Windows |
| "The disk is in use" | The app lists which programs have files open; close them or click "Close … and retry". If none is listed it is usually Spotlight or a system process: wait a few seconds and retry |
| Asks for permissions again after rebuilding | You are on an ad hoc signature: run `sh setup-signing.sh` (once) |
| "Always read-only" does not appear | The disk exposes no partition UUID; rare, see Settings → Advanced |
| Something odd and you do not know what | Settings → Advanced → *Copy diagnostics*, or **View log** |

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/Juanalfaros/ntfs-mount/main/install.sh | sh -s -- --uninstall
```

removes the app, the helper, the sudoers rule and the private ntfs-3g copy. FUSE-T stays (remove it with
`"/Library/Application Support/fuse-t/uninstall.sh"`). Eject your disks first. To clean the rest:

```sh
defaults delete local.ntfsmount
rm -f ~/Library/Logs/NTFSMount.log
security delete-certificate -c "NTFS Mount Local"   # only if you created the certificate
```

Then remove **NTFS Mount** from *Full Disk Access* in System Settings.

## Development

```sh
sh test.sh      # syntax, typecheck, helper validation, private copy, uninstaller, signing, translations
./build.sh      # rebuilds (closes the app if it was open)
```

`NTFSMOUNT_APP_DIR=/some/folder ./build.sh` builds somewhere else without touching the installed app.

`test.sh` mounts nothing and uses no privileges: it tests the installer and uninstaller in temporary
folders (`LIBEXEC=… ONLY_COPY=1`, `LIBEXEC=… SUDOERS=…`) and checks that every text in the code has a Spanish
translation with the same placeholders. What cannot be tested that way (a real mount as root, Windows
hibernation, several disks, login item after a restart) has to be checked by hand.

### Adding or fixing a translation

Every user-visible text is `L("English text", args…)` in `main.swift`; `{0}`, `{1}`… are replaced by the
arguments. To add a language, copy `es.lproj` to `<code>.lproj`, translate the right-hand side of each line
in `Localizable.strings` (and `InfoPlist.strings`), add the language to `CFBundleLocalizations` in
`build.sh` and to the `cp` line that copies the `.lproj` folder, and run `sh test.sh`.

## Limitations

- NTFS only; it does not format or partition, and it does not rename volumes (Homebrew's ntfs-3g has no
  `ntfslabel`).
- `ntfs-3g` in user space is slower than a native driver, especially with many small files.
- It does not replace `chkdsk`: if a disk is damaged, repair it on Windows.
- It relies on macFUSE's kernel extension, which Apple may disapprove in any update.
- BitLocker-encrypted volumes are not supported.
- With FUSE-T, extended attributes (some Finder tags and quarantine flags) are not preserved when copying files onto the disk.
- Full Disk Access is required and cannot be granted by the installer.

## License

[MIT](LICENSE). The release includes a build of ntfs-3g (GPL) with its exact source; FUSE-T and macFUSE are not
included: you install them yourself (the installer downloads FUSE-T from its authors). See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Not affiliated with Tuxera, the
ntfs-3g project, macFUSE or Apple.

If it saved you a trip to a Windows PC and you want to say thanks, there is a "pay what you want" page on
Gumroad (a free download too) — never required.
