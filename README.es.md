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
> - Se desarrolló y probó en **un solo Mac**: Apple Silicon, macOS 27.0.1, macFUSE 5.4.0, ntfs-3g
>   2026.7.7. Otras versiones de macOS y los Mac con Intel no están probados. Si la pruebas,
>   [abre un issue](../../issues) y cuéntanos cómo te fue.
> - Depende de la **extensión de kernel de macFUSE**, que en Apple Silicon obliga a bajar la seguridad de
>   arranque del Mac y aprobar la extensión (mira [Instalación](#instalación)). Apple podría bloquearla en
>   un macOS futuro.
> - No hay una descarga lista para abrir: la app se compila en tu Mac con `install.sh` (nada va firmado ni
>   notarizado por Apple, porque eso exige una cuenta de desarrollador de pago).

Requiere macOS 13 o posterior (usa `SMAppService`).

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

**Atajo:** `sh install.sh` hace los pasos 1, 3 y 6 que falten (instala macFUSE y ntfs-3g con Homebrew, crea el
certificado de firma si quieres, compila y abre la app) y te dice qué queda por hacer a mano (pasos 2, 4 y 5).
Es idempotente. `sh install.sh --check` solo informa del estado de cada pieza, sin cambiar nada. Sus
mensajes siguen el idioma de tu Mac (fuerza uno con `NTFSMOUNT_LANG=en` o `NTFSMOUNT_LANG=es`).

Los pasos a mano:

1. **macFUSE y ntfs-3g** (necesitas [Homebrew](https://brew.sh); en Homebrew 5 o posterior, además
   `brew trust --formula gromgit/fuse/ntfs-3g-mac` antes del último `brew install`, porque es una fórmula de
   terceros):

   ```sh
   brew install --cask macfuse
   brew tap gromgit/homebrew-fuse
   brew install ntfs-3g-mac
   ```

2. **Aprobar la extensión de macFUSE** en Ajustes del Sistema → Privacidad y seguridad. En Apple Silicon
   suele exigir reiniciar en Recuperación, elegir «Seguridad reducida», permitir extensiones de kernel y
   reiniciar. Sin esto no hay escritura.

3. **Compilar e instalar la app** (necesita las herramientas de línea de comandos de Xcode,
   `xcode-select --install`):

   ```sh
   ./build.sh
   open ~/Applications/"NTFS Mount.app"
   ```

4. **Dar permisos la primera vez**, cuando macOS los pida:
   - *Volúmenes extraíbles* → Permitir.
   - *Acceso total al disco* → Ajustes del Sistema → Privacidad y seguridad → Acceso total al disco → `+`
     → NTFS Mount. Sin esto `ntfs-3g` falla con `Operation not permitted`.

5. **Activar el montaje sin contraseña:** menú → **Activar montaje sin contraseña…** (o desde la bienvenida).
   Pide la contraseña de administrador una sola vez. Sin esto la app funciona, pero pide contraseña en cada
   acción y no puede montar automáticamente.

6. *(Recomendado)* **Firma estable:** `sh setup-signing.sh` crea un certificado local en tu llavero y
   `build.sh` lo usa. Así macOS no vuelve a pedir los permisos del paso 4 cada vez que recompilas. La primera
   vez, macOS te pedirá la contraseña (marcar el certificado como de confianza) y puede preguntar si
   `codesign` puede usar la llave («Permitir siempre»). El certificado nunca sale de tu Mac.

### Instalar tú mismo la parte privilegiada

El paso 5 ejecuta `install-root.sh` como root desde dentro del paquete de la app, que es de tu usuario (mira
el [modelo de seguridad](#modelo-de-seguridad)). Si prefieres no confiar en eso, lee el script y ejecútalo tú
desde la carpeta del proyecto:

```sh
sudo sh install-root.sh ntfsmount-helper "$USER"
```

Después abre la app: detecta que el montaje sin contraseña ya está activo.

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
| `install.sh` | Instalador de todo: dependencias, firma, compilación y primer arranque |
| `package.sh` | Genera `dist/NTFS-Mount-<versión>.dmg` para llevar la app a otro Mac |
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

Lo recomendado es lo mismo que aquí: copia la carpeta del proyecto y ejecuta `sh install.sh` en el otro Mac,
que compila la app allí (una app compilada localmente no lleva la cuarentena de macOS, así que no salen
avisos de Gatekeeper).

`sh package.sh` también genera `dist/NTFS-Mount-<versión>.dmg` con la app, un acceso directo a Aplicaciones y
un `README.txt`. En el otro Mac sigues necesitando macFUSE y ntfs-3g. La app va firmada con tu identidad
local, no con un Developer ID, así que Gatekeeper la bloqueará la primera vez:
`xattr -dr com.apple.quarantine "/Applications/NTFS Mount.app"`.

## Mantenimiento

- **`brew upgrade ntfs-3g-mac`:** la copia privada queda desfasada pero sigue funcionando. El menú muestra
  **Actualizar copia de ntfs-3g (viejo → nuevo)…** para refrescarla.
- **macFUSE:** Ajustes → Avanzado → **Buscar actualizaciones de macFUSE…** (la única vez que la app usa la red, y solo
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

1. Ajustes → Avanzado → **Desinstalar componentes privilegiados…** (quita sudoers, helper y copia
   privada, y el inicio de sesión). Expulsa antes los discos montados.
2. Salir de la app y borrar lo demás:

   ```sh
   rm -rf ~/Applications/"NTFS Mount.app"
   defaults delete local.ntfsmount
   rm -f ~/Library/Logs/NTFSMount.log
   security delete-certificate -c "NTFS Mount Local"   # solo si creaste el certificado
   brew uninstall ntfs-3g-mac && brew uninstall --cask macfuse   # opcional
   ```

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

## Licencia

[MIT](LICENSE). NTFS Mount no incluye ni redistribuye ntfs-3g ni macFUSE: usa las copias que tú instalas.
Mira [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). No está afiliada a Tuxera, al proyecto ntfs-3g, a
macFUSE ni a Apple.

Si te ahorró un viaje a un PC con Windows y quieres dar las gracias, hay una página «paga lo que quieras» en
Gumroad (también con descarga gratuita), nunca obligatoria.
