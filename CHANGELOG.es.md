# Registro de cambios

[English](CHANGELOG.md) · **Español**

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
