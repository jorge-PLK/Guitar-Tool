# P8 · Port a Windows

Fecha: 2026-11-18 · Fase 7c · Rama `fase-7c`

## Objetivo

Decidir si ToneForge puede llevarse a Windows (ARM64 y x64) y con qué alcance. La prueba de viabilidad (qué paquetes compilan, interfaz, modelos, audio, cámara y helpers) está pendiente; esta primera sección solo documenta el entorno de la VM (pasos 1-2 de la fase).

## Entorno de la VM (pasos 1-2)

### Máquina

- UTM 5.0.9. VM `/Volumes/SSD Mac/VMs/ToneForge-Win11.utm` (29 GB tras instalar el toolchain).
- QEMU aarch64 con hipervisor, UEFI, TPM, 4 núcleos, 8 GB, disco NVMe de 100 GiB.
- Windows 11 Pro 26300 ARM64 es-ES, sin activar, cuenta local `tf`.
- Instantáneas: `windows-limpio` y `toolchain`.

### Control desde el Mac

- OpenSSH Server: alias `tf-win`, clave `~/.ssh/tf-win`, PowerShell 5.1 por defecto, IP 192.168.64.2.
- Reserva: agente QEMU vía AppleScript de UTM (`execute ... with output capturing`).
- Para crear la VM por AppleScript hace falta el permiso de Automatización (claude → UTM).

### Versiones

- Visual Studio 2022 Build Tools con MSVC 14.44.35207 (bin Hostarm64, Hostx64 y Hostx86) y Windows SDK 10.0.22621.0.
- Swift 6.4.2-RELEASE (Asserts) con SDK de Windows para aarch64, x86_64 e i686.
- Los `rtl.shared` y `rtl.static` `.msm` de amd64, arm64 y x86 están en `Redistributables\6.4.2`.
- `vc_redist` arm64 y x64 instalados (no fueron la causa del error 14001, pero quedan).

### Tropiezos y remedios

- (a) La regla de firewall de OpenSSH solo cubría el perfil Private y la red estaba en Public. Remedio: regla a Any y red a Private.
- (b) ExecutionPolicy. Remedio: `RemoteSigned` en LocalMachine.
- (c) `winget` falla en sesión SSH (0x8a15000f «Data required by the source is missing»): el índice AppX no se registra fuera de una sesión interactiva. Remedio: instaladores directos, `aka.ms/vs/17/release/vs_BuildTools.exe` y el `.exe` de swift.org.
- (d) Build Tools devuelve 3010 (pide reinicio). Remedio: reiniciar.
- (e) `swift-build.exe` falla con 14001 (`ERROR_SXS_CANT_GEN_ACTCTX`): al toolchain 6.4.2 ARM64 le faltan los ensamblados privados `FoundationXML` y `swiftRegexBuilder` en `Toolchains\6.4.2+Asserts\usr\bin\`. Remedio: copiar las DLL de `Runtimes\6.4.2\usr\bin\` a una subcarpeta con su nombre y, a `swiftRegexBuilder`, que no lleva manifiesto incrustado, darle un `swiftRegexBuilder.manifest` externo (`assemblyIdentity` win32, 6.4.2.0, arm64, más `<file>`). Hay que repetirlo si se reinstala Swift.

### Prueba «hola mundo» SwiftPM con Foundation

- ARM64 nativo: compila en unos 7-13 s.
- x64: `swift build --arch x86_64`. `--triple` no sirve, SwiftPM 6.4 lo ignora y saca ARM64.
- Con `--static-swift-stdlib` los dos ejecutables son autónomos (unos 60 MB cada uno, con Foundation e ICU estáticos), PE 0xAA64 y 0x8664, y los dos arrancan sin Swift en el PATH (el x64 bajo la emulación de Windows ARM).
- Sin estático, el x64 falla con 0xC000007B porque carga el runtime ARM64; el instalador ARM64 no instala runtime x64.

### Observación pendiente

Resuelta en parte en el paso 3: ver «Locale» en la sección siguiente.

## Compilar, instalar y arrancar en la VM (paso 3)

### Script

- Uso, desde el Mac: `Tools/win/build.sh [--package <ruta del repo>] [--product <nombre>] [--arch arm64|x64|both] [--gui] [--no-run] [--clean] [--stop]`. Por defecto usa el paquete `Tools/win/smoke`, las dos arquitecturas y arranque en consola.
- Códigos de salida: 0 bien, 1 falla el programa, 2 falla la compilación, 3 VM o ssh inaccesibles.
- Log completo en `Temp/logs/win-<fecha>.log`; con `--gui`, la salida y las capturas quedan en `Temp/win/`.
- Los `.ps1` remotos están en `Tools/win/remote/` y llegan con el repo a `C:\tf`. El resultado se instala en `C:\ToneForge\<arch>\`.
- Si la VM está parada la arranca (`utmctl start ToneForge-Win11`); `--stop` la apaga al acabar.

### Tiempos y verificación

- Compilación incremental: 2,7 s en ARM64 y 1,3 s en x64.
- Los ejecutables son PE 0xAA64 y 0x8664; los dos imprimen y salen con 0.
- `--gui` saca la ventana en el escritorio del usuario `tf` y trae la captura al Mac.

### Inicio de sesión automático

- `Tools/win/remote/setup-autologin.ps1`, por ssh: `powershell -NoProfile -ExecutionPolicy Bypass -File setup-autologin.ps1 -Password <contrasena>`. La contraseña se pasa con `-Password` y no va en el repo.
- Deja al usuario `tf` con la sesión iniciada al arrancar, sin bloqueo ni suspensión.

### Tropiezos y remedios del paso 3

- (f) `true` no existe en PowerShell. Remedio: para probar ssh usar `echo ok`.
- (g) SwiftPM saca códigos ANSI por ssh. Remedio: `build.sh` los quita.
- (h) Lanzar procesos en el escritorio interactivo. `schtasks /IT` funciona gracias al inicio de sesión automático, y la captura de pantalla se hace dentro de la propia tarea, que es la que vive en la sesión interactiva.

### Locale

`NumberFormatter(.decimal)` da locale `en_001` y «1,234.5» también en la sesión gráfica de un Windows es-ES, así que no lo causa ssh. Queda abierto para la prueba de viabilidad.

### Cambios respecto a la mini-spec del paso 3

- `--gui` arranca solo en el escritorio, no además en consola.
- Los ficheros borrados del repo siguen en `C:\tf` hasta usar `--clean`.

### Pendiente

- No se ha probado `--gui` sin sesión iniciada (debe salir con 3).
- Queda abierta en la VM una ventana «Administrador: C:\WINDOWS…»; habrá que cerrarla desde el script si reaparece con cada `--gui`.

## Prueba de viabilidad

Pendiente (paso 4 de la fase).
