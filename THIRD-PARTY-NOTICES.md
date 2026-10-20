# Third-party software / Software de terceros

**English.** NTFS Mount's own code is under the [MIT license](LICENSE). The repository's source contains **no
third-party code** except the unmodified ntfs-3g release tarball in `release/sources/` (kept with the binary, as the
GPL asks). The release also includes a build of ntfs-3g made from that tarball. FUSE-T and macFUSE are **not**
included or redistributed: you install them yourself, and the installer downloads FUSE-T from its authors.

**Español.** El código propio de NTFS Mount está bajo la [licencia MIT](LICENSE). El código fuente del repositorio
**no contiene código de terceros**, salvo el tarball sin modificar de ntfs-3g en `release/sources/` (guardado junto
al binario, como pide la GPL). La versión publicada incluye además una compilación de ntfs-3g hecha con ese
tarball. FUSE-T y macFUSE **no** se incluyen ni se redistribuyen: los instalas tú, y el instalador descarga FUSE-T
de sus autores.

| Software | What it is used for / Para qué se usa | License | Where it comes from / De dónde sale |
|---|---|---|---|
| [ntfs-3g](https://github.com/tuxera/ntfs-3g) (`ntfs-3g`, `ntfsfix`, `libntfs-3g`) | Reads and writes NTFS / Lee y escribe NTFS | GPL-2.0-or-later (programs), LGPL-2.0-or-later (libntfs-3g, linked statically) | Built unmodified from upstream's tarball (`release/sources/`, also attached to each release) with `release/build-ntfs3g.sh` / Compilado sin modificar del tarball original; en el modo macFUSE, `ntfs-3g-mac` de Homebrew ([gromgit/homebrew-fuse](https://github.com/gromgit/homebrew-fuse)) instalado por ti |
| [FUSE-T](https://github.com/macos-fuse-t/fuse-t) | User-space file systems without a kernel extension (default) / Sistemas de archivos en espacio de usuario sin extensión de kernel (por defecto) | **Free for non-commercial use**; commercial use or bundling needs a license from its authors (see its License.txt); libfuse part LGPL / **Gratis para uso no comercial**; el uso comercial o empaquetarlo exige licencia de sus autores | Its official, notarized installer, downloaded by `install.sh` on your Mac (checksum and signature verified) / Su instalador oficial y notarizado, descargado por `install.sh` en tu Mac |
| [macFUSE](https://macfuse.github.io) | Alternative layer, needs a kernel extension / Capa alternativa, necesita extensión de kernel | See [macFUSE's license](https://github.com/macfuse/macfuse/blob/master/LICENSE.txt) | Homebrew cask `macfuse`, installed by you / instalado por ti |
| [Homebrew](https://brew.sh) | Only in the macFUSE mode / Solo en el modo macFUSE | BSD-2-Clause | Installed by you / Instalado por ti |
| Apple frameworks and SF Symbols | The interface and system integration / La interfaz y la integración con el sistema | Part of macOS and the Xcode command line tools | Your Mac |

> **FUSE-T's license also applies to you as a user:** it is free for non-commercial use. If you use NTFS Mount in a
> business, get a license from FUSE-T's authors or use the macFUSE mode (`--backend macfuse`).
> **La licencia de FUSE-T también te alcanza a ti como usuario:** es gratis para uso no comercial. Si usas NTFS
> Mount en una empresa, consigue una licencia con los autores de FUSE-T o usa el modo macFUSE (`--backend macfuse`).

## What the installer does with them / Qué hace el instalador con ellos

`install-root.sh` copies, **on your Mac**, `ntfs-3g` and `ntfsfix` (the prebuilt ones from the release, or Homebrew's in
macFUSE mode) and the library they need (`libfuse-t`, copied from where FUSE-T's installer put it, owned by root)
to the root-owned folder `/usr/local/libexec/ntfsmount/`, rewrites their internal library paths with
`install_name_tool` and signs them again locally. Nothing else is modified.

`install-root.sh` copia, **en tu Mac**, `ntfs-3g` y `ntfsfix` (los precompilados de la versión, o los de Homebrew
en el modo macFUSE) y la biblioteca que necesitan (`libfuse-t`, copiada de donde la dejó el instalador de FUSE-T,
propiedad de root) a la carpeta de root `/usr/local/libexec/ntfsmount/`, reescribe sus rutas internas de
librerías con `install_name_tool` y los vuelve a firmar localmente. No se modifica nada más.

NTFS Mount is not affiliated with or endorsed by Tuxera, the ntfs-3g project, FUSE-T, macFUSE, Homebrew or Apple.
NTFS Mount no está afiliada ni respaldada por Tuxera, el proyecto ntfs-3g, FUSE-T, macFUSE, Homebrew ni Apple.
