# Third-party software / Software de terceros

**English.** NTFS Mount's own code is under the [MIT license](LICENSE). The repository contains **no
third-party code**. The app works by calling the programs below, which *you* install on your own Mac;
this project does not bundle or redistribute them.

**Español.** El código propio de NTFS Mount está bajo la [licencia MIT](LICENSE). El repositorio **no
contiene código de terceros**. La app funciona llamando a los programas de abajo, que *tú* instalas en tu
propio Mac; este proyecto no los incluye ni los redistribuye.

| Software | What it is used for / Para qué se usa | License | Where it comes from / De dónde sale |
|---|---|---|---|
| [ntfs-3g](https://github.com/tuxera/ntfs-3g) (`ntfs-3g`, `ntfsfix`, `libntfs-3g`) | Reads and writes NTFS / Lee y escribe NTFS | GPL-2.0-or-later (programs), LGPL-2.0-or-later (libntfs-3g), as declared by the Homebrew formula | Homebrew tap [gromgit/homebrew-fuse](https://github.com/gromgit/homebrew-fuse), formula `ntfs-3g-mac`, installed by you |
| [macFUSE](https://macfuse.github.io) | Lets macOS use user-space file systems / Permite a macOS usar sistemas de archivos en espacio de usuario | See [macFUSE's license](https://github.com/macfuse/macfuse/blob/master/LICENSE.txt) | Homebrew cask `macfuse`, installed by you |
| [Homebrew](https://brew.sh) | Installs the two above / Instala los dos anteriores | BSD-2-Clause | Installed by you |
| Apple frameworks and SF Symbols | The interface and system integration / La interfaz y la integración con el sistema | Part of macOS and the Xcode command line tools | Your Mac |

## What the installer does with them / Qué hace el instalador con ellos

`install-root.sh` copies, **on your Mac**, the `ntfs-3g` and `ntfsfix` programs and the libraries they need
from your own Homebrew installation to the root-owned folder `/usr/local/libexec/ntfsmount/`, rewrites
their internal library paths with `install_name_tool` and signs them again locally. The programs are not
otherwise modified. The source code of ntfs-3g is available from the upstream project linked above, and
the Homebrew formula records the exact version you installed.

`install-root.sh` copia, **en tu Mac**, los programas `ntfs-3g` y `ntfsfix` y las librerías que necesitan
desde tu propia instalación de Homebrew a la carpeta de root `/usr/local/libexec/ntfsmount/`, reescribe sus
rutas internas de librerías con `install_name_tool` y los vuelve a firmar localmente. Los programas no se
modifican de otra forma. El código fuente de ntfs-3g está en el proyecto original enlazado arriba, y la
fórmula de Homebrew registra la versión exacta que instalaste.

NTFS Mount is not affiliated with or endorsed by Tuxera, the ntfs-3g project, macFUSE, Homebrew or Apple.
NTFS Mount no está afiliada ni respaldada por Tuxera, el proyecto ntfs-3g, macFUSE, Homebrew ni Apple.
