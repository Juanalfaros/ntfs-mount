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
> - It was developed and tested on **one Mac**: Apple Silicon, macOS 27.0.1, macFUSE 5.4.0, ntfs-3g
>   2026.7.7. Other macOS versions and Intel Macs are untested. If you try it, please
>   [open an issue](../../issues) and tell us how it went.
> - It depends on **macFUSE's kernel extension**, which on Apple Silicon means lowering the Mac's startup
>   security and approving the extension (see [Install](#install)). Apple may block it in a future macOS.
> - There is no ready-to-open download: the app is built on your Mac by `install.sh` (nothing is signed or
>   notarized by Apple, because that requires a paid developer account).

Requires macOS 13 or later (it uses `SMAppService`).

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

**Shortcut:** `sh install.sh` does steps 1, 3 and 6 for whatever is missing (installs macFUSE and ntfs-3g
with Homebrew, creates the signing certificate if you want, builds and opens the app) and tells you what is
left to do by hand (steps 2, 4 and 5). It is idempotent. `sh install.sh --check` only reports the state of
each piece and changes nothing. Its messages follow your Mac's language (force one with
`NTFSMOUNT_LANG=en` or `NTFSMOUNT_LANG=es`).

The steps by hand:

1. **macFUSE and ntfs-3g** (you need [Homebrew](https://brew.sh); with Homebrew 5 or later you also have to
   trust the third-party formula with `brew trust --formula gromgit/fuse/ntfs-3g-mac` before the last
   `brew install`):

   ```sh
   brew install --cask macfuse
   brew tap gromgit/homebrew-fuse
   brew install ntfs-3g-mac
   ```

2. **Approve the macFUSE extension** in System Settings → Privacy & Security. On Apple Silicon this
   usually means restarting into Recovery, choosing "Reduced Security" and allowing kernel extensions, then
   restarting. Without this there is no write access.

3. **Build and install the app** (needs the Xcode command line tools, `xcode-select --install`):

   ```sh
   ./build.sh
   open ~/Applications/"NTFS Mount.app"
   ```

4. **Grant permissions the first time**, when macOS asks:
   - *Removable volumes* → Allow.
   - *Full Disk Access* → System Settings → Privacy & Security → Full Disk Access → `+` → NTFS Mount.
     Without it `ntfs-3g` fails with `Operation not permitted`.

5. **Turn on passwordless mounting:** menu → **Turn on passwordless mounting…** (or from the Welcome
   screen). It asks for your administrator password once. Without it the app works, but asks for the
   password on every action and cannot mount automatically.

6. *(Recommended)* **Stable signing:** `sh setup-signing.sh` creates a local certificate in your keychain
   and `build.sh` uses it, so macOS does not ask for the step 4 permissions again every time you rebuild.
   The first time, macOS will ask for your password (to trust the certificate) and may ask whether
   `codesign` can use the key ("Always Allow"). The certificate never leaves your Mac.

### Installing the privileged part yourself

Step 5 runs `install-root.sh` as root from inside the app bundle, which belongs to your user (see
[Security model](#security-model)). If you would rather not trust that, read the script and run it yourself
from the project folder:

```sh
sudo sh install-root.sh ntfsmount-helper "$USER"
```

Then open the app: it detects that passwordless mounting is already on.

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
| `install.sh` | Installs everything: dependencies, signing, build and first launch |
| `package.sh` | Builds `dist/NTFS-Mount-<version>.dmg` to move the app to another Mac |
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

The recommended way is the same as here: copy the project folder and run `sh install.sh` on the other Mac,
which builds the app there (a locally built app is not quarantined by macOS, so there are no Gatekeeper
warnings).

`sh package.sh` also builds `dist/NTFS-Mount-<version>.dmg` with the app, a shortcut to Applications and a
`README.txt`. On the other Mac you still need macFUSE and ntfs-3g. The app is signed with your local
identity, not a Developer ID, so Gatekeeper blocks it the first time:
`xattr -dr com.apple.quarantine "/Applications/NTFS Mount.app"`.

## Maintenance

- **`brew upgrade ntfs-3g-mac`:** the private copy becomes outdated but keeps working. The menu shows
  **Update ntfs-3g copy (old → new)…** to refresh it.
- **macFUSE:** Settings → Advanced → **Check for macFUSE updates…** (the only time the app uses the network,
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

1. Settings → Advanced → **Uninstall privileged components…** (removes sudoers, helper and private copy,
   and the login item). Eject mounted disks first.
2. Quit the app and delete the rest:

   ```sh
   rm -rf ~/Applications/"NTFS Mount.app"
   defaults delete local.ntfsmount
   rm -f ~/Library/Logs/NTFSMount.log
   security delete-certificate -c "NTFS Mount Local"   # only if you created the certificate
   brew uninstall ntfs-3g-mac && brew uninstall --cask macfuse   # optional
   ```

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

## License

[MIT](LICENSE). NTFS Mount does not include or redistribute ntfs-3g or macFUSE: it uses the copies you
install yourself. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Not affiliated with Tuxera, the
ntfs-3g project, macFUSE or Apple.

If it saved you a trip to a Windows PC and you want to say thanks, there is a "pay what you want" page on
Gumroad (a free download too) — never required.
