# Registro de cambios

[English](CHANGELOG.md) · **Español**

## 2.0.0 (2026-10-20): Instalación fácil

El gran cambio: instalar ya no significa instalar Homebrew, aprobar una extensión de kernel en Recuperación,
compilar y escribir comandos. Una línea en Terminal lo hace todo.

### Añadido

- **Instalador de una línea** (`install.sh`): instala FUSE-T con el instalador notarizado de sus autores (suma de
  verificación y firma comprobadas), descarga de la versión en GitHub la app universal y ntfs-3g ya compilados
  (sumas comprobadas), instala el helper privilegiado desde una copia de root vuelta a verificar, y abre la app.
  Sin Homebrew, sin herramientas de Xcode, sin reiniciar. Opciones `--check`, `--uninstall`, `--yes` y `--backend`.
- **FUSE-T como capa de montaje por defecto**, así que no hace falta extensión de kernel. macFUSE sigue disponible
  (`--backend macfuse`). Medido en un disco USB real: misma velocidad que macFUSE, datos idénticos, desmontajes
  limpios.
- **ntfs-3g precompilado para FUSE-T** (universal, arm64 + x86_64), construido en GitHub Actions desde el código
  original sin modificar, que se guarda en el repositorio y se adjunta a cada versión.
- **Guía del Acceso total al disco**: un cuarto paso en la ventana de Bienvenida que comprueba el permiso y abre el
  panel correcto de Ajustes del Sistema.
- Enlace `ntfsmount://welcome`; `NTFSMOUNT_SUDO` para pedir la contraseña en una ventana.

### Mejorado

- Los volúmenes montados se detectan por el proceso ntfs-3g en vez de por la línea de `mount`, así que funciona con
  cualquiera de las dos capas.
- El helper ya no supone que ntfs-3g se pone solo en segundo plano, y espera hasta 15 s a que aparezca el montaje.
- La app, Ajustes y Bienvenida nombran la capa en uso (FUSE-T o macFUSE).

### Límites conocidos

- No se conservan los atributos extendidos al copiar a un disco NTFS (igual con las dos capas), y un SSD muy rápido
  puede ir más lento con FUSE-T que con macFUSE. FUSE-T es gratis solo para uso no comercial.
- Probada en un solo Mac (Apple Silicon, macOS 27), incluida una instalación desde cero, la desinstalación y el modo
  macFUSE; las partes de Intel solo se ejecutaron con Rosetta.

## 1.0.0 (2026-10-19): Primera versión pública

NTFS Mount se hace pública: una app de barra de menú que monta discos NTFS con escritura en macOS, construida
sobre ntfs-3g y macFUSE. Esta versión se desarrolló y probó en un solo Mac (Apple Silicon, macOS 27.0.1,
macFUSE 5.4.0, ntfs-3g 2026.7.7).

### Añadido

- **Interfaz en español e inglés**, según el idioma del Mac: menús, tarjetas, ajustes, alertas,
  notificaciones y el aviso de permisos de macOS. Cualquier otro idioma muestra inglés. Los scripts de
  terminal (`install.sh`, `setup-signing.sh`, `build.sh`) también hablan los dos idiomas, y los README
  están en ambos.
- `NTFSMOUNT_LANG=en|es` para forzar el idioma de los scripts de terminal, y `NTFSMOUNT_APP_DIR` para compilar
  la app en otro lugar sin tocar la instalada.
- Pruebas que comprueban que cada texto tiene su traducción al español con los mismos marcadores.
- Licencia MIT, avisos de terceros y una forma documentada de instalar a mano la parte privilegiada con
  `sudo`.

### Mejorado

- `install.sh` ahora pregunta antes de confiar en el tap de terceros de Homebrew (`gromgit/fuse`) en vez de
  hacerlo en silencio (usa `--yes` para aceptar).
- El registro, el informe de diagnóstico y los mensajes del helper privilegiado están en inglés, para poder
  pegarlos en un issue y que cualquiera los lea.
- El aviso de privacidad de volúmenes extraíbles está localizado.

### Ya incluido en esta versión (desarrollado antes en privado)

- Montaje automático con escritura, una tarjeta por disco con uso, velocidad y estimación de llenado, otros
  volúmenes (exFAT, FAT, APFS), varios discos a la vez, solo lectura por disco, montar/desmontar/expulsar todos.
- Notificaciones con acciones, ventana de ajustes, bienvenida, enlaces `ntfsmount://` para Atajos.
- Desmontaje antes de dormir o apagar, detección de disco en uso con el nombre de las apps que tienen
  archivos abiertos, errores con salida (permiso de macOS, hibernación o Inicio rápido de Windows, `ntfsfix`,
  macFUSE inactivo).
- Montaje sin contraseña mediante una regla de sudoers limitada a un helper que valida y ejecuta una copia
  privada de ntfs-3g propiedad de root, instalador de un comando y desinstalador.
