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

`NumberFormatter(.decimal)` dio «1,234.5» en un Windows es-ES vía SSH. Comprobar el locale en una sesión gráfica antes de concluir nada.

## Prueba de viabilidad

Pendiente (paso 4 de la fase).
