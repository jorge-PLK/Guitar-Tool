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

## Prueba de viabilidad (paso 4)

Resultado (18/11/2026): **ningún bloqueo duro**. Todo lo probado compila y corre en ARM64 y en x64 emulada. Los riesgos están en el audio dúplex, el time-stretch del reproductor, el desfase del AAC de Media Foundation, `Process.terminate` con nietos, los timers de 15,6 ms y la velocidad de la separación. La decisión de alcance es de Jorge (ADR-020).

### Barrido de compilación

`Tools/win/build.sh --package Packages/<Kit> --no-run`, Swift 6.4.2, VM Win11 ARM64. Logs en `Temp/win/sweep/<Kit>-arm64.txt`.

| Paquete | arm64 | x64 | Primer error |
|---|---|---|---|
| `AnalysisKit` | OK 4,2 s | OK 3,2 s | — (1 fichero, esqueleto) |
| `HeadRushKit` | OK 2,3 s | OK 2,5 s | — (esqueleto) |
| `MatchKit` | OK 2,3 s | OK 2,5 s | — (esqueleto) |
| `Tone3000Kit` | OK 2,0 s | OK 2,7 s | — (esqueleto) |
| `AudioKit` | fallo | — | `AlignmentCheck.swift:1` no such module `Accelerate` |
| `ModelKit` | fallo | — | `CoreMLCompiler.swift:1` no such module `CoreML` |
| `SourceKit` | fallo | — | `ProcessRunning.swift:1` no such module `Darwin` |
| `StemKit` | fallo | — | `tf-memhog/MemHog.swift:14` cannot find `arc4random_buf` |
| `Store` | fallo | — | `Library.swift:1` no such module `CryptoKit` |
| `StudyKit` | fallo | — | `Audio/MonoResampler.swift:1` no such module `AVFoundation` |
| `TabKit` | fallo | — | `Audio/MonoAudio.swift:1` no such module `AVFoundation` |
| `VideoKit` | fallo | — | (vía `AudioKit`) `AlignmentCheck.swift:1` `Accelerate` |

Ningún fallo es del toolchain: todos son el primer `import` de Apple. Los cuatro que compilan son esqueletos de un fichero, así que no demuestran nada sobre el código real.

### Inventario de Apple

Fuentes sin `Tests/`. Total de paquetes: 170 ficheros, 88 atados a Apple y 82 puros. `App`: al menos 33 de 57 atados.

| Paquete | Ficheros | Atados | Frameworks y APIs | Veredicto |
|---|---|---|---|---|
| `AnalysisKit`, `HeadRushKit`, `MatchKit`, `Tone3000Kit` | 1 c/u | 0 | — | portable |
| `AudioKit` | 33 | 29 | AVFoundation, Accelerate, CoreAudio HAL, os, Observation, CryptoKit, `mach_absolute_time`, DispatchSource, Synchronization | reescribir |
| `ModelKit` | 4 | 3 | CoreML, CryptoKit, `Process` + `/usr/bin/ditto`, `URLSessionDownloadDelegate` | reescribir |
| `SourceKit` | 27 | 9 | Darwin (`kill`, `pid_t`), `Process`, DispatchSource, CryptoKit, Compression, Observation | casi |
| `StemKit` | 16 | 11 | Accelerate, AVFoundation, CoreML, Darwin, `Process`, DispatchSource (SIGTERM), Synchronization | reescribir |
| `Store` | 15 | 3 | SwiftData (`LibraryIndex`), CryptoKit, CoreGraphics | casi |
| `StudyKit` | 14 | 7 | CoreML (pulso, acordes), AVFoundation, Accelerate (LogMel, CQT, remuestreo) | reescribir |
| `TabKit` | 34 | 8 | Accelerate, CoreML (Basic Pitch, batería), AVFoundation, AudioToolbox (`TabSynthRenderer`) | casi |
| `VideoKit` | 23 | 18 | AVFoundation, CoreMedia, CoreVideo, CoreImage, CoreText, Metal, Vision (`GuitarFramer`), ImageIO, CryptoKit | reescribir |
| `App` | 57 | ≥33 | SwiftUI, AppKit, AVFoundation, Observation, WebKit (`TabWebHost`), UTType | reescribir |

Puntos sueltos: `mach_absolute_time` en `CoreAudioIO.swift:107,358`, `StudyPlayer.swift:331` y `HostTimeMap.swift:14`; `Synchronization` (`Mutex`) en `AudioKit` y `StemKit`; `@Observable` en `StudyPlayer` y `SourceKit`. Helpers externos: yt-dlp, deno, ffmpeg, `tf-separate` y `ditto`, bajo `Application Support/ToneForge/Helpers`.

### Señal, audio y vídeo

Las cuatro pruebas compilan y corren en ARM64 y x64 (misma cifra salvo donde se dice).

- **a · runtime** (`tf-p8-runtime`, `tf-p8-signal`): `Mutex` y `Atomic` bien (800000/800000); `@Observable` bien (`onChange` 1 vez). QPC a 24 MHz, resolución 42 ns. `makeSignalSource(SIGTERM)` compila y se crea en ARM64. `DispatchSourceTimer` de 20 ms: media 20,3 ms, con desvíos de hasta 16 ms (tic de Windows de 15,6 ms; `timeBeginPeriod(1)` no lo mejora en Dispatch). `Process`: argumentos con espacios, comillas, barras finales y «canción ñ €» llegan 7/7. `terminate()` con hijo directo: `waitUntilExit` en 54-64 ms; con `cmd→ping`, 29 s porque espera al nieto (hace falta un Job Object, p. ej. yt-dlp→ffmpeg). Un cuelgue inicial 0xC0000005 fue fallo de la prueba (`Atomic`/`Mutex` locales capturados en cierres que escapan), no de Windows.
- **b · FFT** (`tf-p8-fft`, pocketfft C BSD-3; `ref_data.c` generado con vDSP en el Mac): frente a `vDSP_DFT_zrop` de 4096 (convención empaquetada ×2), error relativo 6,6e-8 (tolerancia 1e-5). Correlación analítica de `SignalMath` (n = 65536, double): pico en 12345, subamuestra idéntica (Δ 0,0; tolerancia 1e-6 muestras), envolvente con error 2,7e-17. 9,4 µs por FFT en ARM64 y 12,1 µs en x64.
- **c · miniaudio 0.11.26** (`tf-p8-miniaudio`): el contexto WASAPI inicializa con 0 dispositivos (la VM no tiene audio) y el dúplex devuelve −1, como se esperaba. Hilo de audio → Swift: 203-204 periodos de 10 ms en 2 s, media 10,01-10,04 ms. dr_wav (24 bits), dr_mp3 y dr_flac dan las mismas muestras que `AVAudioFile` (Δ 0), RMS ≤ 4e-6, primera muestra en el mismo índice. Un WAV con ruta no ASCII se escribe y relee bien.
- **d · Media Foundation** (`tf-p8-mf`, shim C con `MFStartup` + `IMFSinkWriter`, H.264 + AAC): hr 0 y 46104 bytes en las dos arquitecturas (878 y 450 ms). AVFoundation lo abre en el Mac: 2,000 s, avc1 + aac, 60 fotogramas. **El clic sale 44,0 ms (2112 muestras) antes que el fotograma blanco**, escritos los dos en t = 1,000 s: es determinista y supera medio fotograma; el encoder AAC añade retardo y el MP4 queda sin edit list, así que hay que compensarlo o escribir la edit list. HEVC: hr 0 y 4347 bytes, contenido sin verificar.

| Pieza | Apple hoy | Sustituto | Esfuerzo | Riesgo |
|---|---|---|---|---|
| FFT y DSP | Accelerate (`vDSP_DFT` zrop/zop, conv, desamp, biquad, ~45 funciones vDSP, vImage 16F) | pocketfft C (BSD-3) + capa DSP en Swift puro | M | bajo (b) |
| Remuestreo | `AVAudioConverter` Mastering | libsoxr (LGPL) o r8brain (MIT) | M | medio: revalidar con los fixtures de Python (BTC, pulso) |
| Decodificación | `AVAudioFile` (wav, flac, mp3) | dr_wav, dr_mp3, dr_flac | S | bajo (c) |
| E/S en vivo | HAL (`CoreAudioIO.swift:144`, IOProc con `mSampleTime`/`mHostTime`), agregado privado, latencias declaradas | WASAPI propio (`IAudioClient3` o exclusivo, por eventos) o miniaudio | L | **alto**: miniaudio dúplex no da marcas por búfer y no garantiza n − y entre reinicios; conviene WASAPI propio con `u64DevicePosition`/`u64QPCPosition` en captura e `IAudioClock::GetPosition` en salida |
| Reproductor | `AVAudioEngine` + `TimePitch`/`Varispeed` (`StudyPlayer.swift:96-99`) | mezclador propio + Signalsmith Stretch (MIT) | L | **alto**: no hay equivalente del time-stretch de Apple |
| Sintetizador | `AVAudioUnitSampler` (`TabSynthRenderer.swift:656`) | TinySoundFont (MIT) | M | medio |
| Reloj | `mach_absolute_time` | QPC en 100 ns (escala de WASAPI y `MFSampleExtension_DeviceReferenceSystemTime`) | S | bajo (a) |
| Cámara | `AVCaptureSession`, `CMClockGetHostTimeClock` | MF SourceReader con marca QPC del dispositivo | M | medio: marcas del driver sin medir |
| Escritura y exportación | `AVAssetWriter` HEVC, `MontageExporter.swift:168` | `IMFSinkWriter` (d), H.264 por defecto | M | medio: desfase AAC de 44 ms; HEVC depende del equipo |
| Composición | CoreImage + Metal + CoreText (`MontageCompositor.swift`) | Direct2D + DirectWrite (shim C) o filtros de ffmpeg | L | medio |
| Encuadre | Vision `VNDetectHumanBodyPoseRequest`, 10 articulaciones | MoveNet o RTMPose (Apache-2) en ONNX Runtime | M | medio, depende de tf-ml |
| Runtime | Synchronization, Observation, Dispatch, `Process`, CryptoKit | todo existe salvo CryptoKit → swift-crypto (sin probar) | S–M | `Process` con nietos → Job Object; timers con tic de 15,6 ms |

Riesgos altos: la E/S dúplex y el time-stretch. Los medidos: desfase AAC de 44 ms, `Process.terminate` con nietos (29 s) y timers con desvíos de 16 ms.

### Modelos con ONNX Runtime

Estado parcial: solo la separación está medida; el resto quedó sin medir por presupuesto de turnos.

**ort-smoke** (`Probes/P8-windows/ort-smoke/`, API C de ORT desde Swift):

- ORT 1.32.0 (API 32), del NuGet oficial `Microsoft.ML.OnnxRuntime`, con el SHA-512 de NuGet comprobado. Hoy GitHub `microsoft/onnxruntime` devolvía 404 (repo, API y releases).
- Compila y arranca en ARM64 y en x64 emulada. Proveedores en las dos: `AzureExecutionProvider` y `CPUExecutionProvider`.
- `onnxruntime.dll` pesa 19,1 MB en arm64 y 20,6 MB en x64; `onnxruntime_providers_shared.dll` (21 KB) solo hace falta para EP de plugin. Licencia MIT (más ThirdPartyNotices). El exe pesa 62-64 MB por la stdlib y Foundation estáticas, no por ORT.
- Integración: target C en SwiftPM con `onnxruntime_c_api.h`; la import lib se enlaza con `#pragma comment(lib, ...)` por `_M_ARM64`/`_M_X64`, sin `unsafeFlags`. Swift llama a la tabla `OrtApi` (`api.Run!(...)`) y la ruta del modelo pasa a `wchar_t` en C. La interfaz `MaskModel` de StemKit cabe tal cual con otro layout de entrada (`spec_real`/`spec_imag`).
- **`onnxruntime.dll` va junto al exe**: System32 trae otra `onnxruntime.dll` (stub de Windows ML) que se carga antes que el PATH. El probe imprime la ruta de la DLL cargada.
- Proveedores: CPU como base. QNN no aplica en la VM (sin NPU Hexagon); es el plugin `onnxruntime-qnn`, solo ARM64. DirectML está en mantenimiento. Windows ML (EP descargables) exige identidad de paquete (MSIX).

Tiempos orientativos (VM de 4 vCPU virtuales, x64 emulada), fragmento fijo de T1:

| Modelo | ONNX · tamaño · opset | ARM64 | x64 emulada | Core ML en el Mac | Veredicto |
|---|---|---|---|---|---|
| BS-RoFormer SW (separación) | sí, publicado por elicwhite, FP32, trozo de 4 s (T=345) · 701 MB | 5,9-6,2 s/trozo = 177-185 s/min (3× tiempo real; 11,3 s con la VM cargada) · pico 5,4-5,6 GB · frente a ORT del Mac máx. 3,5e-4, SNR 118 dB; frente a PyTorch 115 dB | 7,4-8,3 s/trozo = 221-250 s/min · pico 5,6 GB · 119 dB / 115 dB | gridshift CPU+GPU: 2,08 s por trozo de 13,35 s = 18,7 s/min (ORT CPU en el Mac: 230 s/min con la VM en marcha; P4: 143-151) | **viable pero lento (~10× el Mac)**; fiel a ORT y a PyTorch |
| Lead/rhythm (Mel-Band) | export propio TorchScript a T=301, a la primera en 3,8 s · 339 MB · opset 17 | sin medir | sin medir | — | exportable; falta ejecutarlo |
| Beat This! (pulso) | publicado `musetric/beat-this-onnx` (final0, MIT, estático a 1500 tramas) · 190 MB · opset 17 | sin medir | sin medir | — | candidato directo |
| BTC (acordes) | exportable (3 M parámetros; envoltorio en `prepare.py`) | sin medir | sin medir | — | — |
| Basic Pitch | `nmp.onnx` dentro del paquete pip (referencia de P4) · <1 MB | sin medir | sin medir | — | — |
| ADTOF (batería) | exportable (GRU → GRU de ONNX; export en `prepare.py`) | sin medir | sin medir | — | — |

**Por qué es lenta (aclaración, 18/11/2026).** No es principalmente la VM: la VM ARM64 corre casi nativa con el hipervisor de Apple. El mismo ONNX con ORT CPU en el propio Mac midió 143-151 s/min en P4 (230 con la VM en marcha) frente a 177-185 en la VM, del mismo orden. El «~10×» es frente a Core ML con GPU (18,7 s/min): la diferencia es CPU frente a GPU. La VM solo resta núcleos (4) y la x64 emulada cuesta ~25 %. Acelerar en Windows pide GPU/NPU (DirectML en mantenimiento, WebGPU, CUDA solo NVIDIA, QNN en Snapdragon), no comprobable en la VM: queda como prueba de PC.

**Calidad de la separación (SDR).** El trozo de 4 s pierde 0,3-0,7 dB frente a los stems reales (guitarra 7,90 frente a 8,23). Frente a la salida de la app: guitarra 17,1 dB, bajo 20,4, batería 21,2 y voz 24,8. Para escuchar: `Probes/P8-windows/ort-models/out/bs_roformer/T1_guitar_60-85s_onnx.wav` frente a `…_coreml.wav` (stem de guitarra, 25 s).

**Riesgos:**

- Velocidad: un tema de 4 min tardaría unos 12 min en la VM ARM64.
- Memoria: pico de 5,6 GB con 8 GB en la VM.
- Trozo corto: el ONNX de trozo largo (T=1151, el de la app) no se pudo exportar en P4 (48 GB). Alternativas: export dynamo, T intermedio o BSRoformer.cpp/GGML en CPU (respaldo de P4).

### Interfaz, helpers, instalador y locale

Recomendaciones de la investigación web (notas en `Temp/research/windows-port.md`; las marcadas allí como no verificadas siguen sin probar).

- **Interfaz:** WebView2 + UI web + núcleo Swift. El runtime evergreen viene en Win11 (ARM64 y x64) y `canvas`, Web Audio y `<video>` resuelven forma de onda, tablatura y reproductor. Las interfaces nativas en Swift son inmaduras: swift-winui (Windows App SDK 1.5-preview1 en su README, sin canvas ni vídeo demostrados), SwiftCrossUI con backend WinUI (docs no accesibles) y SwiftOpenUI (Win32/Direct2D, suspendido el 19/09/2026). SwiftUI y AppKit no existen en Windows.
- **Helpers:** Deno con build oficial ARM64 desde 2.7.0 (yt-dlp pide 2.3.0 como mínimo); ffmpeg de BtbN `FFmpeg-Builds` en variante LGPL `winarm64` (como proceso aparte basta aviso de licencia y enlace a la fuente); yt-dlp ARM64 solo en nightly (`yt_dlp_arm64.exe`), el estable es x64. Sin verificar todavía: el build ARM64 de Deno y el yt-dlp ARM64 solo en nightly vienen de las notas web marcadas como no comprobadas; se confirman al montar `Tools/helpers/fetch.sh` para Windows.
- **Instalador:** Inno Setup sin firma. SmartScreen avisa («Más información → Ejecutar de todos modos»); aceptable para un círculo pequeño. MSIX exige certificado. Con `--static-swift-stdlib` no hacen falta los `.msm` del runtime.
- **Locale:** `Locale.current` no lee el sistema fuera de Darwin y cae a `en_001` (medido en la VM es-ES, ver «Locale»). Remedio: `GetUserDefaultLocaleName` (kernel32) y `Locale(identifier:)` explícito; `en_US_POSIX` para guardar números y ficheros.
- **ASIO:** fuera de la v1. El SDK es desde oct/2025 de doble licencia (propietaria o GPLv3), y un driver ASIO x64 no carga en un host ARM64 salvo Arm64EC o Arm64X.
- **Evitar `FoundationXML`:** hay un crash conocido en Windows 11 ARM64 con Swift 6.4 (ver tropiezo (e)).

### Bloqueos duros

Ninguno.

### Pruebas que la VM no puede hacer (para Jorge, en un PC con Windows)

La de latencia (1 y 2) necesita antes portar `tf-audio` o escribir una prueba WASAPI propia.

1. Flex Prime con cable de vuelta: `tf-audio latency --restarts 5`, dispersión (spec ≤ 0,1 ms) y variación entre reinicios, en compartido y exclusivo.
2. `tf-audio verify` 60 s: error máximo por clic < 1 ms y pendiente.
3. Qué driver usa la Flex Prime (USB Audio Class 2 genérico o HeadRush Windows Audio Driver 1.0.3) y periodo mínimo en `IAudioClient3`.
4. Cámara por MF: jitter de las marcas QPC frente al audio (< medio fotograma).
5. Si hay codificador HEVC por hardware.
6. Abrir `Temp/win/p8/p8-mf-*.mp4` en el reproductor de Windows y en VLC: el clic debe sonar ~44 ms antes del destello.
7. Snapdragon X: `ort-smoke` con el trozo de separación en CPU (8-12 núcleos) y con el plugin QNN (FP32: ver si pasa al HTP o cae a CPU).
8. PC x64 Intel/AMD nativo: el mismo trozo.
9. Memoria con 16 GB y un tema entero.

### Probes

Todos en `Probes/P8-windows/`.

| Directorio | Producto |
|---|---|
| `runtime` | `tf-p8-runtime`, `tf-p8-signal`: `Mutex`/`Atomic`, `@Observable`, QPC, timers, `Process`, señales |
| `fft` | `tf-p8-fft`: pocketfft frente a vDSP y correlación de `SignalMath` |
| `miniaudio` | `tf-p8-miniaudio`: WASAPI, hilo de audio → Swift, dr_wav/dr_mp3/dr_flac |
| `mediafoundation` | `tf-p8-mf`: shim C con `IMFSinkWriter`, MP4 H.264/HEVC + AAC |
| `ort-smoke` | `ort-smoke <dir> [--runs N] [--threads N] [--dump]`: ejecuta un modelo ONNX con `manifest.txt` |
| `ort-models` | `prepare.py` y `out/<modelo>/` (bins, manifest, `mac.json`, WAV de escucha) con las referencias del Mac |
| `mac-ref` | scripts de referencia del Mac: `fftref`, `decref`, `mp4check` |

### Decisiones de Jorge (18/11/2026)

- **Tolerancia A/V en la exportación de Windows:** medio fotograma, como en la Fase 6. El desfase del AAC de Media Foundation es fijo (44 ms), así que primero se compensan esos 44 ms y la tolerancia de medio fotograma se aplica al resto.
- **PCs:** puede haber equipos ARM64 entre los de destino, así que se mantienen las dos arquitecturas. Jorge aún no tiene un PC con Windows; llegará más adelante. Hasta entonces quedan aplazadas las pruebas de PC real (latencia y driver de la Flex Prime, cámara, HEVC por hardware, QNN, velocidad nativa de la separación) y el alcance debe poder avanzar sin ellas, lo que refuerza «Windows 1 = herramienta de estudio, sin audio en vivo».

- **Interfaz:** opción A, WebView2 con UI web y núcleo Swift (ADR-020).
- **Alcance:** todo de una, sin etapas: estudio, fuentes externas, separación, tablatura, grabación con vídeo, montaje y lo que dependa de la Flex Prime, porque habrá que montarlo todo igualmente. Lo que depende de hardware real (E/S de audio en vivo y latencia con la Flex Prime, cámara, HEVC por hardware, GPU/NPU) se programa ya, pero se valida cuando Jorge tenga un PC con Windows; hasta entonces solo se verifica en la VM lo que la VM puede verificar.

### Pendiente

- Cuándo medir en un PC real, con la lista de pruebas anterior. Interfaz y alcance ya decididos: ADR-020 (aceptado).
