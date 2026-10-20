# NTFS Mount

[English](README.md) · **Español**

App de barra de menú para macOS que monta discos NTFS **con escritura**, usando
[`ntfs-3g`](https://github.com/tuxera/ntfs-3g) y [macFUSE](https://macfuse.github.io). Una alternativa
libre y abierta a los controladores NTFS comerciales: una sola app en Swift (`main.swift`), sin código de
terceros dentro.

La interfaz habla **español e inglés** y sigue el idioma de tu Mac.

> **Lee esto antes de usarla**
>
> - Escribir en NTFS desde el espacio de usuario es cómodo, pero puede dañar un disco si se desconecta mal
>   o si algo falla. **Respalda lo que te importe** y usa la app bajo tu propia responsabilidad (mira la
>   [licencia](LICENSE)).
> - Se desarrolló y probó en **un solo Mac**: Apple Silicon, macOS 27.0.1, FUSE-T 1.2.9, ntfs-3g 2026.9.28
>   (y, para el modo macFUSE, macFUSE 5.4.0). Los Mac con Intel y otras versiones de macOS no están probados.
>   Si la pruebas, [abre un issue](../../issues) y cuéntanos cómo te fue.
> - **No está firmada ni notarizada por Apple** (eso exige una cuenta de desarrollador de pago). El
>   instalador de una línea evita los avisos que macOS muestra con las apps descargadas; mira
>   [Instalación](#instalación).

Requiere macOS 13 o posterior.

## Qué hace

- **Monta solo, con escritura.** Al conectar un disco NTFS, macOS lo monta en solo lectura; la app lo
  desmonta y lo vuelve a montar con `ntfs-3g`, sin pedir contraseña.
- **Tarjeta por disco en el menú:** estado, % libre, barra de uso (verde → naranja → rojo, con marca al
  90 %), velocidad en vivo, minigráfico del último minuto con su pico y, mientras copias, cuánto falta para
  llenarlo. Botones en la propia tarjeta (Finder, Expulsar, Montar); clic en la tarjeta abre el disco.
  Lo menos frecuente (desmontar sin expulsar, solo lectura, reparar, detalles) está en «Más opciones».
- **Otros volúmenes:** los discos exFAT, FAT o APFS externos aparecen en un submenú con la misma tarjeta,
  solo informativa (macOS ya los gestiona), con Finder y Expulsar.
- **Varios discos a la vez**, incluso con el mismo nombre (el segundo se monta como «nombre 1»).
- **Solo lectura por disco:** «Siempre en solo lectura» lo recuerda por UUID de partición.
- **Montar todos con escritura** y **Desmontar todos sin expulsar** (aparecen con dos o más discos),
  **Expulsar** (desmonta todas las particiones del disco), **Expulsar todos los discos** (⌘E) y aviso
  «Ya puedes desconectar…». Si el disco está en uso, dice **qué apps** tienen archivos abiertos y ofrece
  cerrarlas y reintentar.
- **Notificaciones con botones:** montaje automático (Abrir / Expulsar), disco desconectado sin expulsar
  (Qué hacer), menos de 5 % libre (Abrir).
- **Ajustes (⌘,)** en una ventana: General, Montaje, Discos recordados y Avanzado (estado, diagnóstico,
  registro, macFUSE, desinstalar). **Bienvenida** con los pasos de instalación la primera vez que falta algo.
- **Enlaces** `ntfsmount://expulsar` y `ntfsmount://ajustes`, para usarlos desde Atajos.
- Icono monocromo en la barra (en color solo si algo requiere atención), velocidad de ancho fijo en la
  barra, VoiceOver en las tarjetas y respeto de «Reducir movimiento».
- **Desmonta antes de dormir o apagar**, para no dejar volúmenes NTFS «sucios».
- **Errores con salida:** permiso de macOS, hibernación o Inicio rápido de Windows (montar descartando
  la hibernación), sistema de archivos sin cerrar (`ntfsfix`) y macFUSE inactivo.
- **Salud de macFUSE:** avisa si la extensión no está aprobada o cargada (típico tras actualizar macOS) y
  puede consultar si hay una versión nueva.
- **Diagnóstico y registro:** Ajustes → Avanzado → «Copiar diagnóstico» con todo lo útil para depurar, y
  un registro en `~/Library/Logs/NTFSMount.log` (siempre en inglés, para poder pegarlo en un issue).
- Evita que Spotlight indexe los discos, opción de nombres compatibles con Windows y «Abrir al iniciar
  sesión».

## Instalación

Abre **Terminal** y pega esta única línea:

```sh
curl -fsSL https://raw.githubusercontent.com/Juanalfaros/ntfs-mount/main/install.sh | sh
```

Te pide la contraseña una vez y luego:

1. instala **FUSE-T** (con el instalador notarizado de sus propios autores, tras comprobar su suma de
   verificación y su firma) si no lo tienes;
2. descarga la app y ntfs-3g de la última versión de este proyecto y comprueba sus sumas de verificación;
3. instala el helper privilegiado que permite montar discos sin pedir contraseña;
4. deja **NTFS Mount** en `~/Applications` y la abre.

No hay nada que compilar, ni Homebrew, ni reinicio. Los archivos descargados con `curl` no llevan la
cuarentena de macOS, así que Gatekeeper no tiene nada que bloquear.

**El único paso que no puede hacer por ti** es el *Acceso total al disco*, que macOS solo deja conceder a la
propia persona. La ventana de Bienvenida que se abre te guía: agrega **NTFS Mount** a la lista en *Ajustes del
Sistema → Privacidad y seguridad → Acceso total al disco* y actívalo. (Ni root, ni un demonio, ni una ventana de
contraseña lo evitan: macOS lo pide a cualquier programa que abra un disco directamente.) El instalador además
ofrece crear un certificado local de firma para que macOS recuerde ese permiso entre actualizaciones.

Opciones (agrégalas después de `sh -s --`): `--check` informa del estado sin cambiar nada, `--yes` no hace
preguntas, `--uninstall` lo quita todo, `--backend macfuse` usa macFUSE en vez de FUSE-T y `--from-source`
compila desde una copia de este repositorio. Sus mensajes siguen el idioma de tu Mac (`NTFSMOUNT_LANG=en` o `es`).

### Dos formas de montar: FUSE-T (por defecto) o macFUSE

| | **FUSE-T** (por defecto) | macFUSE |
|---|---|---|
| Instalación | Un comando, sin reiniciar | Extensión de kernel: en Apple Silicon hay que bajar la seguridad de arranque en Recuperación y aprobarla |
| Velocidad | Igual que macFUSE en un disco USB en nuestra prueba (abajo); más lento en un SSD muy rápido | La más rápida |
| Atributos extendidos | No se conservan al copiar | Emulados |
| Licencia | Gratis para uso **no comercial**; una empresa necesita licencia de los autores de FUSE-T | Libre de usar |

En un disco USB de 1 TB medimos escribir 1 GB a 22,6 MB/s con FUSE-T y 23,7 MB/s con macFUSE, y leer a 73,9 y
56,5 MB/s, con datos idénticos y desmontajes limpios en ambos. Su backend NFS es más lento en SSD muy rápidos
(usuarios reportan ~20 frente a ~700 MB/s); el backend SMB de FUSE-T falló nuestras pruebas de creación de
archivos y no se usa.

El modo macFUSE es el de la versión 1 (el `ntfs-3g-mac` de Homebrew); sigue funcionando con
`--backend macfuse`, pero ha tenido bastante menos pruebas en la 2.0. FUSE-T y macFUSE no están pensados para
instalarse juntos: pisan un archivo de biblioteca compartido (`libfuse3`).

### Compilarla tú

`sh install-from-source.sh` compila la app en tu Mac (necesita Homebrew, macFUSE y las herramientas de línea de
comandos de Xcode; es el flujo de la versión 1). `sh build.sh` solo recompila la app.

### Instalar tú mismo la parte privilegiada

El instalador ejecuta `install-root.sh` como root desde una copia de root cuya suma de verificación comprobó. Si
prefieres leerlo y ejecutarlo tú:

```sh
sudo sh install-root.sh ntfsmount-helper "$USER"          # modo macFUSE (necesita el ntfs-3g de Homebrew)
sudo NTFSMOUNT_BACKEND=fuse-t NTFSMOUNT_SRC_BIN=/ruta/a/ntfs-3g-fuse-t/bin sh install-root.sh ntfsmount-helper "$USER"
```

## Cómo funciona

```
NTFS Mount.app (usuario)  ──sudo -n──▶  /usr/local/libexec/ntfsmount-helper (root)
        │                                        │ valida cada argumento
        │                                        ▼
        │                         /usr/local/libexec/ntfsmount/bin/ntfs-3g  (copia privada, root)
        │                                        │
        └── DiskArbitration (eventos), IOKit (velocidad), statfs (espacio)
```

| Archivo | Para qué |
|---|---|
| `main.swift` + `Parsing.swift` | La app (y sus funciones puras, con pruebas): menú, tarjetas, eventos, monitorización, errores |
| `Localization.swift` + `es.lproj/` | Traducciones. Las claves en el código son los textos en inglés; el español está en `es.lproj/Localizable.strings` |
| `ntfsmount-helper` | Script `sh` que corre como root: `mount`, `unmount`, `eject`, `fix`, `cleanup`, `noindex`, `loadfuse`. Valida todo lo que recibe |
| `install-root.sh` | Lo ejecuta la app como root: instala el helper, la regla de sudoers y la copia privada de ntfs-3g |
| `uninstall-root.sh` | Deshace lo anterior |
| `setup-signing.sh` | Crea el certificado local de firma |
| `build.sh` | Compila, arma el `.app` en `~/Applications` y lo firma |
| `install.sh` | El instalador de una línea: descarga y verifica los archivos de la versión, instala FUSE-T, el helper y la app |
| `install-from-source.sh` | El instalador de la versión 1: compila la app en tu Mac (Homebrew + macFUSE) |
| `Backend.swift` | Qué capa FUSE se usa (FUSE-T o macFUSE) y cómo detectarla |
| `release/` | Scripts que construyen los archivos de la versión (app universal, ntfs-3g para FUSE-T) y el código fuente fijado de ntfs-3g |
| `test.sh` | Pruebas sin root, sin disco y sin red |

### Modelo de seguridad

El montaje sin contraseña es una regla de sudoers (`/etc/sudoers.d/ntfsmount`) que permite a tu usuario
ejecutar **solo** `ntfsmount-helper` como root. Para que eso no sea una puerta a root:

- El helper está en una carpeta de root y valida todos sus argumentos (dispositivo `diskNsM`, puntos de
  montaje solo bajo `/Volumes`, sin saltos de línea ni `..`, nombres sin comas que inyecten opciones).
- Homebrew vive en una carpeta tuya, así que un proceso con tu usuario podría reemplazar su `ntfs-3g`. Por
  eso el instalador **copia `ntfs-3g`, `ntfsfix` y sus librerías** (`libntfs-3g`, `libintl`, `libfuse`,
  `MFMount`) a `/usr/local/libexec/ntfsmount/`, propiedad de root, reescribe sus rutas internas, apunta
  las rutas de plugins y de idiomas a carpetas de root y vuelve a firmar. `/usr/local/lib` también es de
  tu usuario en esta instalación, por eso `libfuse` se copia en vez de usarse desde ahí.
- El único camino que usa el `ntfs-3g` de Homebrew es el de contraseña (sin helper instalado), activado con
  `NTFSMOUNT_UNSAFE_BIN=1`; `sudo` descarta esa variable, así que el camino sin contraseña nunca lo usa.

Límite conocido: el instalador corre desde el paquete de la app, que es tuyo. Un proceso malicioso con tu
usuario podría alterarlo justo antes de que pulses el botón y pongas la contraseña. Si te preocupa, instala
a mano con `sudo` como se explica [arriba](#instalar-tú-mismo-la-parte-privilegiada). Para informar de un
problema de seguridad, usa el reporte privado de vulnerabilidades de GitHub de este repositorio en vez de un
issue público.

## Llevarla a otro Mac

Ejecuta el mismo instalador de una línea en el otro Mac. (`sh package.sh` todavía puede generar un `.dmg`, pero un
`.dmg` descargado activa Gatekeeper; el instalador no.)

## Mantenimiento

- **Actualizar NTFS Mount:** vuelve a ejecutar el instalador. Reemplaza la app, el helper y ntfs-3g, y si creaste el
  certificado local macOS conserva tu permiso de Acceso total al disco.
- **Modo macFUSE:** `brew upgrade ntfs-3g-mac` deja la copia privada desfasada pero sigue funcionando; el menú muestra
  **Actualizar copia de ntfs-3g (viejo → nuevo)…** para refrescarla.
- **FUSE-T / macFUSE:** Ajustes → Avanzado → **Buscar actualizaciones de …** (la única vez que la app usa la red, y solo
  si lo pides). Tras actualizar hay que aprobar la extensión otra vez y reiniciar.
- **Si cambias el helper o los scripts:** vuelve a pulsar «Activar…»; la app detecta que la copia
  instalada difiere de la del paquete.

## Solución de problemas

| Síntoma | Causa y arreglo |
|---|---|
| `Operation not permitted` al abrir `/dev/diskNsM` | Falta *Acceso total al disco* para NTFS Mount (o cambió la firma). Concédelo y reinicia la app |
| «macFUSE no está activo» en el menú | La extensión no está aprobada o cargada. Ajustes → Privacidad y seguridad; a veces hay que reiniciar |
| «Hibernación o Inicio rápido de Windows» | Windows dejó el disco a medias. Lo ideal: iniciar Windows y apagarlo del todo. O «Montar igualmente» (descarta la sesión hibernada, no tus archivos) |
| «Necesita reparación» | El volumen quedó sin cerrar. `ntfsfix` lo intenta; para casos serios usa `chkdsk` en Windows |
| «El disco está en uso» | La app lista qué programas tienen archivos abiertos; ciérralos o pulsa «Cerrar … y reintentar». Si no lista ninguno, suele ser Spotlight o un proceso del sistema: espera unos segundos y reintenta |
| Pide permisos de nuevo tras recompilar | Estás con firma ad hoc: ejecuta `sh setup-signing.sh` (una vez) |
| No aparece «Siempre en solo lectura» | El disco no expone UUID de partición; es raro, mira Ajustes → Avanzado |
| Algo raro y no sabes qué | Ajustes → Avanzado → *Copiar diagnóstico*, o **Ver registro** |

## Desinstalar

```sh
curl -fsSL https://raw.githubusercontent.com/Juanalfaros/ntfs-mount/main/install.sh | sh -s -- --uninstall
```

quita la app, el helper, la regla de sudoers y la copia privada de ntfs-3g. FUSE-T se queda (se quita con
`"/Library/Application Support/fuse-t/uninstall.sh"`). Expulsa antes tus discos. Para limpiar el resto:

```sh
defaults delete local.ntfsmount
rm -f ~/Library/Logs/NTFSMount.log
security delete-certificate -c "NTFS Mount Local"   # solo si creaste el certificado
```

Después quita **NTFS Mount** de *Acceso total al disco* en Ajustes del Sistema.

## Desarrollo

```sh
sh test.sh      # sintaxis, typecheck, validaciones del helper, copia privada, desinstalador, firma, traducciones
./build.sh      # recompila (cierra la app si estaba abierta)
```

`NTFSMOUNT_APP_DIR=/otra/carpeta ./build.sh` compila en otro lugar sin tocar la app instalada.

`test.sh` no monta nada ni usa privilegios: prueba el instalador y el desinstalador en carpetas temporales
(`LIBEXEC=… ONLY_COPY=1`, `LIBEXEC=… SUDOERS=…`) y comprueba que cada texto del código tenga su traducción al
español con los mismos marcadores. Lo que no se puede probar así (montaje real como root, hibernación de
Windows, varios discos, inicio de sesión tras reiniciar) hay que verlo a mano.

### Añadir o corregir una traducción

Cada texto visible es `L("Texto en inglés", args…)` en `main.swift`; `{0}`, `{1}`… se reemplazan por los
argumentos. Para añadir un idioma, copia `es.lproj` a `<código>.lproj`, traduce el lado derecho de cada línea
de `Localizable.strings` (y `InfoPlist.strings`), agrega el idioma a `CFBundleLocalizations` en `build.sh` y a
la línea `cp` que copia la carpeta `.lproj`, y ejecuta `sh test.sh`.

## Limitaciones

- Solo NTFS; no formatea ni crea particiones, y no renombra volúmenes (el ntfs-3g de Homebrew no trae
  `ntfslabel`).
- `ntfs-3g` en espacio de usuario es más lento que el driver nativo, sobre todo con muchos archivos pequeños.
- No sustituye a `chkdsk`: si un disco está dañado, repáralo en Windows.
- Se apoya en la extensión de kernel de macFUSE, que Apple puede desaprobar en cualquier actualización.
- Los volúmenes cifrados con BitLocker no están soportados.
- Con FUSE-T no se conservan los atributos extendidos (algunas etiquetas del Finder y marcas de cuarentena) al copiar archivos al disco.
- El Acceso total al disco es obligatorio y el instalador no puede concederlo.

## Licencia

[MIT](LICENSE). La versión incluye una compilación de ntfs-3g (GPL) con su código fuente exacto; FUSE-T y macFUSE no
se incluyen: los instalas tú (el instalador descarga FUSE-T de sus autores).
Mira [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). No está afiliada a Tuxera, al proyecto ntfs-3g, a
macFUSE ni a Apple.

Si te ahorró un viaje a un PC con Windows y quieres dar las gracias, hay una página «paga lo que quieras» en
Gumroad (también con descarga gratuita), nunca obligatoria.
