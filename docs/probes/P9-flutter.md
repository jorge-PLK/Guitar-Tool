# P9 · Viabilidad de la interfaz Flutter

**Estado: cerrada (24/11/2026). Pasan las 7 pruebas.** Decisiones: puerto nativo (`Dart_PostCObject_DL`), vía 1 de hilos en Windows sin `tf_core_pump`, textura externa (Mac `CVPixelBuffer`, Windows `GpuSurfaceTexture`), `webview_all` 1.5.2 con «WebView sin foco de teclado», vídeo nativo (AVPlayer; Media Foundation con vsync 2) y `fvp` descartado. ABI y versiones fijadas en `docs/flutter/arquitectura.md`. Abiertos sin bloquear: arranque de WebView2 de 22-25 s con perfil nuevo, primer pintado lento y detector de desgarro a 150 %, cola de muestras adelantadas del vídeo en vsync 2 sin p05, sin probar a 144 Hz. Primera parte de la Fase 7f. Decide si se mantienen las decisiones marcadas (P9) en [ADR-021](../adr/ADR-021.md). Código en `Probes/P9-flutter/` (fuera de la puerta de tests); resultados, en este fichero, debajo de cada prueba.

## Reglas

- **Fallar rápido** y por orden: una prueba que incumple su umbral se para y se devuelve a Jorge como pregunta con alternativas (el respaldo previsto es la primera). No se completa el resto de casos de esa prueba.
- Nada de `Packages/`, `App/` ni `WinApp/` cambia de comportamiento. `AppCoreFFI` se crea aquí en su forma mínima y, si P9 pasa, es la base de la ola 0.
- Hardware y oído son de Jorge: los agentes devuelven números y el comando para repetir.
- Mac primero. El PC x64 se usa dos veces: en cuanto la prueba 2 esté verde en el Mac, la primera parte de la 7 (hilos de Windows y compilación de las candidatas de WebView), porque es el riesgo mayor y puede cambiar la arquitectura; al final, el resto de la 7 con todo verde en el Mac (cerrado en `docs/flutter/decisiones-interfaz.md`).
- Aviso: la documentación consultada es de Flutter 3.47, no 3.50, y no hay ninguna medida propia todavía. Notas en `Temp/research/7f-*.md` y prueba previa en `Temp/flutter-probe/RESULT.md` (no versionados).
- Siempre `--projects-folder` y `--support-dir` a una copia.

## Pruebas

| # | Prueba | Qué se hace | Umbral de paso | Respaldo si falla |
| --- | --- | --- | --- | --- |
| 1 | Entorno | FVM + Flutter 3.50.1 en el Mac; `flutter create` de escritorio (macOS, Windows) en `Probes/P9-flutter/app`; paso de argumentos de línea de comandos a `main(args)` en las dos plataformas; fuentes Inter y Space Grotesk cargadas. | Arranca con `open -g` sin robar foco y lee `--screen x`. | — |
| 2 | FFI e hilos (Mac) | `AppCoreFFI` mínimo (`tf_core_start/send/free/shutdown`, callback de mensajes). Dart llama a `library.list`, `settings.get`, `audio.devices` (pasa por `@MainActor`) y recibe eventos emitidos desde hilos de fondo (`jobs.progress` de una importación por fichero). Además: `NativeCallable.listener` contra puerto nativo (`Dart_PostCObject_DL` con `kExternalTypedData`), latencia mediana y p99 a 60 Hz con el isolate ocupado; µs por mensaje de JSON de 300 bytes, `jsonDecode(utf8.decode)` contra `utf8.decoder.fuse(json.decoder)`. | 1000 llamadas seguidas sin error ni fuga apreciable; ida y vuelta mediana < 5 ms y p99 < 16 ms; ningún bloqueo del hilo de UI > 16 ms; cierre limpio con `tf_core_shutdown` asíncrono (llega `core.shutdown`, sin procesos hijos vivos, sin bloqueo con un tema abierto en estudio). Nativo→Dart: gana el de menor p99 de latencia y jitter; si ninguno baja de 1 ms por mensaje o hay fotogramas perdidos, se evalúa isolate auxiliar o canal binario. | Proceso núcleo aparte. |
| 3 | Fotogramas | Cámara simulada (`--camera simulated`), textura externa (`CVPixelBuffer` en Mac; la registra el runner y pide el fotograma con `tf_frame_copy`, ver la tabla `tf_texture_host` de `arquitectura.md`) contra copia BGRA por FFI + `decodeImageFromPixels`, a 720p30 y 1080p30, 60 s cada una. Medir CPU del proceso, ms por fotograma en el hilo de UI y en el de raster, fotogramas descartados, memoria y número de copias. | 0 descartes a 720p30 y a 1080p30 con textura y memoria estable; entre las que pasan, gana la de menor CPU. | Copia BGRA + `decodeImageFromPixels`. |
| 4 | WebView (Mac) | Las dos candidatas de Mac (`webview_all`, `webview_flutter`) con los criterios de la prueba del 21/11 (base en `Temp/flutter-probe/`): `tab.html` + `tf-bridge.js` + alphaTab desde recursos locales (Bravura y SoundFont resueltos), mensajes JS↔Dart en las dos direcciones, teclado dentro de la partitura con el foco yendo y volviendo a un campo de texto de Flutter, redimensionado. Además: overlay de Flutter encima del WebView, WebView oculto de Songsterr con UA de Safari que devuelve su HTML, y comportamiento con la ventana tapada. | Todo funciona; ninguna tecla de edición se pierde ni llega duplicada. Entre las que pasan, la de mejor mantenimiento y menor coste (decide Jorge si empatan). | `flutter_inappwebview`. |
| 5 | Vídeo (Mac) | `fvp` con `onSync` contra reproductor nativo (`AVPlayer` esclavo del reloj de audio → `CVPixelBuffer` → textura), con una toma real (MOV HEVC 1080p30 y MP4 H.264, una con rotación 90°) y un reloj con la forma de `takeview.position` a 30 Hz. Medir el error A/V por fotograma a 50, 70 y 100 % de velocidad, tras un salto y en bucle, y el tiempo al primer fotograma correcto tras un salto con HEVC 1080p30. | Error ≤ medio fotograma en régimen; recuperación tras salto < 300 ms; rotación correcta. Gana el de menor error medido; si es el nativo, se anota el coste de Media Foundation en Windows. | La otra candidata. |
| 6 | Captura y tests | `--snapshot <png>` con `RepaintBoundary.toImage`; un golden con `matchesGoldenFile` y las fuentes reales, generado en el Mac; `flutter analyze` y `flutter test` desde `Tools/test.sh FlutterApp` con salida resumida. | PNG correcto sin ventana en primer plano; golden estable en dos ejecuciones. | Captura de ventana con la herramienta de la 7c. |
| 7 | PC x64 | `Tools/flutter/pc.sh`: pasa la rama por ssh, compila `AppCoreFFI.dll` y la app, copia junto al `.exe` las DLL del runtime de Swift, ONNX Runtime y DirectML, arranca y trae capturas. **Primero** hilos (vía 1: ventana y motor en hilo propio STA con el principal en `dispatchMain()`; vía 2: `tf_core_pump` con `MsgWaitForMultipleObjects` y `_dispatch_main_queue_callback_4CF`) y compilación de cada candidata de WebView con el Visual Studio del PC. Luego: textura con Impeller (`GpuSurfaceTexture`, respaldo `PixelBufferTexture`; vigilar «Could not create external texture»); WebView (fps y latencia de la captura a 100 y 150 % de DPI, teclas perdidas o duplicadas, foco con un `TextField`, repintado tras redimensionar con y sin el bucle rAF de la prueba previa); vídeo (HEVC y H.264, rotación). Repite 2 y comprueba que el hilo de UI sigue en STA tras iniciar Media Foundation. | Mismos umbrales que en el Mac. Una candidata de WebView que no compile con el VS del PC no pasa salvo parche pequeño y aislado. | Hilos: vía 2 y, si falla, proceso núcleo aparte (pregunta a Jorge). Textura: `PixelBufferTexture`, luego copia BGRA. WebView y vídeo: por prueba, las de arriba. |

## Reparto

Orquestador (Opus): escribe la mini-spec de cada prueba a partir de esta tabla y de `docs/flutter/contrato.md` («Hilos», «Servicios de anfitrión»), integra y decide si se sigue. `tf-implementer` (Sonnet): `AppCoreFFI` mínimo, entrega de fotogramas a la textura y, si gana, el reproductor nativo (pruebas 2, 3 y 5, lado Swift). `tf-flutter` (Sonnet): app de prueba y lado Dart de 2 a 6. `tf-implementer`: `Tools/flutter/pc.sh` (prueba 7). `web-researcher` solo si una prueba falla y hay que elegir respaldo. `tf-docs`: resultados en este fichero. Commit al cerrar P9.

## Qué fija P9 al terminar

ABI de `AppCoreFFI` congelada; mecanismo nativo→Dart (`listener` o puerto nativo); vía de hilos en Windows (1, 2 o proceso aparte) y, con ello, si existe `tf_core_pump`; textura externa o copia BGRA, y resolución y fps por canal; paquete de WebView por plataforma; motor de vídeo (`fvp` o nativo) y su umbral de error A/V; versiones exactas de los plugins en `pubspec.yaml`. Se anotan aquí y en `docs/flutter/arquitectura.md`.

**Fijado (24/11/2026):** ABI de `AppCoreFFI` congelada (`tf_core_init_dart_api`, `tf_core_set_texture_host`, `tf_core_start(optionsJSON, int64 port)`, `tf_core_send`, `tf_core_free`, `tf_core_shutdown`, `tf_core_run_main`, `tf_texture_create`, `tf_texture_dispose`, `tf_frame_copy`; canales camera 0, montage 1, take 2). Nativo→Dart: puerto nativo (`Dart_PostCObject_DL`, `kExternalTypedData`). Hilos en Windows: vía 1 (`tf_core_run_main`), sin `tf_core_pump`. Fotogramas: textura externa, `CVPixelBuffer` en Mac (0 descartes) y `GpuSurfaceTexture` en Windows (anillo de 3 y espera a la GPU, ≤ 3 descartes por minuto). WebView: `webview_all` 1.5.2 en Mac y Windows con el diseño «WebView sin foco de teclado». Vídeo: motor nativo (AVPlayer en Mac; Media Foundation `IMFSourceReader` con presentación vsync 2 en Windows, HEVC convertido a H.264 en el núcleo); `fvp` descartado. Versiones: Flutter 3.50.1 (FVM); el resto de plugins se fijan exactos al crear el `pubspec.yaml` en la ola 0.

## Resultados

### Prueba 1 · Entorno — PASA

- Entorno: FVM 4.3.2 (Homebrew), Flutter 3.50.1 estable (20/11/2026), Dart 3.14.0. Versión fijada en `Probes/P9-flutter/app/.fvmrc`. Commit `f72764a`.
- App: `flutter create --platforms=macos,windows` en `Probes/P9-flutter/app` (`tf_probe`).
- Umbral (arranca con `open -g` sin robar foco y lee `--screen x`): cumplido. 5 lanzamientos con informe (debug ×2, release ×3): la app frontal era la misma antes y 2 s después (medido con `osascript`, System Events), nunca `tf_probe`. `main(args)` recibió `["--screen","x","--report",<ruta>,"--exit-after","4"]`.
- Argumentos en macOS: la plantilla no los pasa. Se cablea en `macos/Runner/MainFlutterWindow.swift` con `FlutterDartProject.dartEntrypointArguments` = `CommandLine.arguments.dropFirst()`, filtrando `-psn_*`, `-NS*` y `-Apple*` con su valor. En Windows la plantilla ya los pasa (`windows/runner/main.cpp:22-25`, `GetCommandLineArguments` → `set_dart_entrypoint_arguments`); leído, sin compilar: se comprueba en la prueba 7.
- Fuentes: los 5 TTF de `App/Resources/Fonts/` (Inter 400/500/600, Space Grotesk 500/700) cargan tal cual como assets; sin conversión.
- Builds: debug 40 s la primera vez (con `pub get` y artefactos), release 25 s. `flutter analyze` limpio.
- Sandbox: la plantilla de macOS lo trae activado; con él la app no escribe fuera de su contenedor. Desactivado en los dos entitlements de la app de prueba. Para la ola 0: `FlutterApp/macos` necesita sandbox desactivado (como la app SwiftUI) para la carpeta de proyectos y los helpers.
- El primer lanzamiento tras cada build no dejó informe en esta prueba. No se reprodujo en la prueba 2 (3 lanzamientos tras recompilar, informe a los 0,54 s y 0,25 s). Hipótesis sin medir: `open` sin `-n` reutilizó una instancia anterior. Los scripts lanzan siempre con `open -g -n`.

Diferencias de Flutter 3.50.1 frente a la documentación de 3.47:

| Tema | En 3.50.1 | Efecto |
| --- | --- | --- |
| Material | `package:flutter/material.dart` sale deprecado en `analyze` («Use package:material_ui/material_ui.dart», deprecado tras v3.47.0-0.0.pre): Material pasa a un paquete aparte. | Afecta a `app.dart` (`MaterialApp`) y al kit de `FlutterApp/`. Decidir en la ola 0: paquete `material_ui` (dependencia nueva, pregunta a Jorge) o solo `widgets.dart` con kit propio. La app de prueba usa solo `widgets.dart`. |
| macOS, dependencias nativas | Swift Package Manager por defecto: sin Podfile, 16 referencias `SwiftPackage` en el `.pbxproj`. | No hace falta CocoaPods. |
| macOS, despliegue mínimo | 12.0 (lo sube el build: «Updating minimum macOS deployment target to 12.0»). | `AppCore` exige macOS 15: subirlo en el runner de `FlutterApp`. |
| macOS, runner | `AppDelegate` con `@main`; `MainFlutterWindow` con `FlutterViewController()` sin argumentos. | Los argumentos de arranque se cablean a mano (arriba). |
| `analysis_options.yaml` | `pub get` lo actualiza para excluir `build` y las carpetas de plataforma. | Ninguno. |
| Windows, runner | `main.cpp` con `CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)` en la línea 18 y paso de argumentos. | Coincide con lo previsto en `arquitectura.md` («Hilos»). |
| Impeller e hilos fusionados | Ni `Info.plist` ni `main.cpp` traen clave alguna. | Sin verificar por la plantilla; la prueba 2 mide en qué hilo corre el isolate de UI. |

### Prueba 2 · FFI e hilos (Mac) — PASA

Código: `Probes/P9-flutter/AppCoreFFI/` (paquete Swift propio con dependencia por ruta a `Packages/AppCore`; nada de `Packages/` cambió) y `Probes/P9-flutter/app/lib/ffi/tf_core.dart` + `probe2*.dart`. Commits `86a74be`, `57d280a`, `f4f949d`. Repetir: `Probes/P9-flutter/run-probe2.sh [listener|port] [ffi|ffi-study]` (informes en `Temp/p9-flutter/p2-<sink>-<probe>-<n>.json`) y, sin Flutter, `Probes/P9-flutter/AppCoreFFI/.build/release/ffi-smoke --projects-folder Temp/p9-flutter/run/projects --support-dir Temp/p9-flutter/run/support`. Build release, audio simulado, carpeta de proyectos de prueba vacía (y una copia de un tema de 1 GB para el cierre), `--support-dir` sin modelos.

- **Hilos:** `pthread_main_np()` llamado desde Dart devuelve 1: en Flutter 3.50.1 el isolate de UI corre en el hilo principal del proceso sin configurar nada. El bucle de AppKit drena `DispatchQueue.main` y `@MainActor`; `audio.devices` responde.
- **Nada `public` faltó en `AppCore`.**

| Umbral | Medido (`listener` · `port`, dos ejecuciones cada uno) | |
| --- | --- | --- |
| 1000 llamadas seguidas sin error | 8000 idas y vueltas por ejecución (`app.info`, `library.list`, `settings.get`, `audio.devices`), 0 errores | pasa |
| Sin fuga apreciable | RSS 109-129 MB al empezar, 130-131 MB tras 4000, 131-132 MB tras 8000 | pasa |
| Ida y vuelta mediana < 5 ms | 0,049-0,051 ms · 0,051 ms | pasa |
| Ida y vuelta p99 < 16 ms | 0,12-0,14 ms (máx 4,05) · 0,09 ms (máx 4,5) | pasa |
| Ningún bloqueo del hilo de UI > 16 ms | vigilante de 5 ms durante las llamadas: máx 0,68-0,76 ms · 1,6-3,2 ms; build máx 0,4 ms | pasa |
| Cierre limpio y asíncrono | `core.shutdown` a los 22-28 ms, `clean: true`, sin procesos hijos | pasa |
| Cierre con un tema abierto en estudio | 29 ms · 28 ms, `clean: true`; vigilante máx 3,8 ms · 1,9 ms | pasa |

Sin Dart (`ffi-smoke`, Swift → C → Swift): mediana 0,038 ms, p99 0,07-0,09 ms, retraso del hilo principal 1,3 ms.

Eventos desde hilos de fondo: `import.file` de un WAV de 2 s → `import:running`, `import:done` (40-56 ms), `separation:queued`, `separation:running`, `separation:failed` (sin modelos, a propósito) y `library.changed`; llegan todos, el isolate sigue vivo.

Nativo → Dart (emisor sintético `tf_debug_emit`, mensajes de 300 bytes, latencia medida con reloj monótono compartido):

| Medida | `NativeCallable.listener` | Puerto nativo (`Dart_PostCObject_DL`, `kExternalTypedData`) |
| --- | --- | --- |
| 60 Hz, isolate libre: mediana / p99 / máx (µs) | 132-141 / 524-530 / 605-620 | 133-140 / 494-519 / 687-713 |
| 60 Hz, isolate libre: jitter (desv. típica del intervalo, ms) | 1,44-1,55 | 1,34-1,55 |
| 60 Hz, isolate ocupado (8 ms de CPU cada 16 ms): mediana (µs) | 97-482 | 76-304 |
| 60 Hz, isolate ocupado: p99 / máx (µs) | 8090 / 8112-13977 | 8086-8090 / 13060-27680 |
| Ráfaga de 5000: µs por mensaje / p99 (µs) | 6,3-6,5 / 37-44 | 6,65-6,7 / 98-105 |
| Pérdidas / fuera de orden | 0 / 0 | 0 / 0 |
| Búferes vivos tras 8000 llamadas | 0 (liberación explícita con `tf_core_free`) | 107-120 (los libera el finalizador cuando corre el GC; RSS plano) |

- Los dos cumplen el objetivo (< 1 ms por mensaje, 0 pérdidas): **no hace falta isolate auxiliar ni canal binario.** Con el isolate ocupado la latencia de ~8 ms es la espera a la tarea de CPU de Dart, igual en los dos.
- Empate técnico en latencia y jitter (diferencias dentro del ruido entre ejecuciones). **Elección provisional: puerto nativo**, por robustez: orden de entrega garantizado (el de `listener` no está documentado, aunque no se desordenó nada en 5000 mensajes), el núcleo sabe si el envío falló (`Dart_PostCObject_DL` devuelve `false` y libera) y Dart no puede olvidarse de liberar. Coste: `tf_core_init_dart_api` + `tf_core_start_port` en la ABI y las cabeceras `dart_api_dl` (API DL 2.7) copiadas en el paquete; la memoria se libera con el GC, no al instante. Se confirma con la misma medida en el PC x64 (prueba 7).
- Decodificación de un mensaje de 300 bytes: `jsonDecode(utf8.decode(bytes))` 0,89 µs; `utf8.decoder.fuse(json.decoder)` 0,41-0,43 µs (2,1 veces más rápido). `CoreClient` usa la fusionada.
- Aviso para la ola 0: una ráfaga de 5000 eventos seguidos ocupa el isolate ~30 ms (vigilante máx 27,8 ms en esa fase). Los eventos reales van a decenas por segundo; si alguno llegara en ráfaga, se agrupa en el núcleo.
- No cubierto aquí: Windows, audio real y biblioteca grande (`library.list` con carpeta vacía).

ABI usada en la prueba (candidata; se congela al cerrar P9): `tf_core_start`, `tf_core_start_port`, `tf_core_init_dart_api`, `tf_core_send`, `tf_core_free`, `tf_core_shutdown`; `optionsJSON` = `{"args": [...]}` que pasa por `LaunchOptions.parse`; códigos de `start`: 0 bien, 1 ya arrancado, 2 opciones inválidas, 3 falló `Bridge.init`. `tf_debug_live_buffers`, `tf_debug_now_ns` y `tf_debug_emit` son solo de la prueba.

### Prueba 3 · Fotogramas (Mac) — PASA

Código: `Probes/P9-flutter/AppCoreFFI/Sources/AppCoreFFI/Frames.swift` (generador sintético BGRA), `app/macos/Runner/TfTextureHost.swift`, `app/lib/probe3_frames.dart` y `Probes/P9-flutter/run-probe3.sh`. Commits `1ff5935` (lado nativo) y `0f0d1ba` (lado Dart). Repetir: `Probes/P9-flutter/run-probe3.sh all` (con `SKIP_BUILD=1` no recompila); informes en `Temp/p9-flutter/p3-<modo>-<tamaño>.json`.

- **Condiciones:** 60 s por combinación, ventana 800×600, dpr 1.0, medido tras el primer segundo. Fotogramas a 30 fps.

| Combinación | Producidos / presentados | Descartes | CPU % de un núcleo (getrusage; `ps`) | RSS a 5 / 30 / 60 s (MB) | Vigilante máx (ms) |
| --- | --- | --- | --- | --- | --- |
| textura · 720 | 1770 / 1770 | 0 | 12,0 (12,4) | 114,2 / 117,1 / 118,3 | 14,8 |
| textura · 1080 | 1770 / 1770 | 0 | 12,7 (12,3) | 123,2 / 126,1 / 127,2 | 15,1 |
| BGRA · 720 | 1770 / 1770 | 0 | 28,7 (26,2) | 126,2 / 127,6 / 128,2 | 17,0 |
| BGRA · 1080 | 1770 / 1770 | 0 | 42,3 (38,2) | 148,4 / 150,8 / 142,8 | 16,3 |

- **BGRA:** build p99 0,24 / 0,27 ms (720 / 1080); raster p99 1,27 / 2,54 ms; 0 de 1801 fotogramas por encima de 16,7 ms; copia FFI p50/p99 0,59/0,66 ms (720) y 1,32/1,53 ms (1080); decode p50/p99 3,03/3,49 ms (720) y 5,74/6,48 ms (1080); hueco máximo de secuencia 1.
- **Generador sintético:** 394-870 µs por fotograma.
- **Copias por fotograma:** textura, 0 hacia Dart; BGRA, 3 en CPU más la subida a GPU.
- **Humo de 3a** (`ffi-smoke --frames`): 30,00 y 29,98 fps; generador 0,39 y 0,75 ms; copia BGRA 0,45 y 1,11 ms.
- **Resultado: gana textura externa (provisional; falta Windows).** Las dos pasan 0 descartes con memoria estable; la textura cuesta menos de la mitad de CPU a 720p y casi una cuarta parte a 1080p.
- **Sin medir:** raster de la textura (`FrameTiming` no la cubre: 0 fotogramas de framework); hueco de secuencia en textura; ±1 de borde al parar (último fotograma producido y no copiado). El vigilante de 14,8-17,0 ms queda sin investigar (roza 16 ms).
- Juicio visual del orquestador (captura de `texture 720` a los 8 s, `Temp/p9-flutter/p3-texture-720.png`): correcto. Fotograma 16:9 centrado con bandas en la ventana 800×600, fondo liso, barra blanca de bordes nítidos, sin desgarro ni franjas. Sin verificar a la vista: orden de canales (el fondo rota de color; una captura no distingue BGRA de RGBA). Se comprueba con un color fijo en la prueba de textura de Windows.

### Prueba 4 · WebView (Mac) — PASA CON EL WEBVIEW SIN FOCO DE TECLADO; CANDIDATAS EMPATADAS

Código: `Probes/P9-flutter/webview/wv_all` y `Probes/P9-flutter/webview/wv_flutter` (una app por candidata, con `shim.js`, `probe.js`, `tab.html` y `ctx.dart` comunes). Commits `a867b60`, `bdada29` (`webview_all`), `fa88e6d` (`webview_flutter`) y `9a1839c` (modos ocultos de Songsterr). Repetir: `Probes/P9-flutter/run-probe4.sh <wv_all|wv_flutter> <caso|all>` con `caso` = `tab`, `messages`, `overlay`, `resize`, `songsterr`, `occluded`; informes en `Temp/p9-flutter/p4-<candidata>-<caso>.json`. `keys` se lanza aparte y en primer plano (ver el bloque `keys` al final de la sección). Un `keys` anterior de `wv_flutter` se lanzó sin pulsar teclas y no cuenta.

- **Versiones:** `webview_all` 1.5.2 (`webview_all_wkwebview` 1.5.2) y `webview_flutter` 4.14.1 (`webview_flutter_wkwebview` 3.27.2). Las dos exponen `loadFlutterAsset`, `loadFile`, `setUserAgent` y `setOnConsoleMessage`; solo `webview_all` tiene `OffscreenWebViewSession` (`isOffscreenWebViewSupported=true`; en `webview_flutter`, `n/a`).
- **Condiciones:** release, ventana 800×600, partitura de prueba servida con `loadFlutterAsset` (`file://`, lectura concedida a la carpeta del asset), una ejecución por caso. La prueba corre desde una copia en `/private/tmp/p9p4`.
- **`jsErrors`, `webErrors` y `badMessages`:** 0 en todos los informes de las dos candidatas.

| Caso | Medida (campo) | `webview_all` | `webview_flutter` |
| --- | --- | --- | --- |
| `tab` | `ok` · `bravuraLoaded` | sí · sí (familia «alphaTab») | sí · sí (familia «alphaTab») |
| `tab` | `timeToReadyMs` · `scoreLoadToRenderedMs` | 176 · 131 | 185 · 135 |
| `messages` | `timeToReadyMs` | 158 | 163 |
| `messages` | ida y vuelta de 1000 (`rttMs`): mediana / p99 / máx (ms) | 0,182 / 0,811 / 9,141 | 0,125 / 0,661 / 4,209 |
| `messages` | ida y vuelta: perdidos / duplicados / fuera de orden | 0 / 0 / 0 | 0 / 0 / 0 |
| `messages` | ráfaga JS → Dart de 1000 (`totalMs`) y perdidos / duplicados / fuera de orden | 1117 ms · 0 / 0 / 0 | 1049 ms · 0 / 0 / 0 |
| `messages` | ráfaga Dart → JS de 1000 (`issueMs`) y perdidos / duplicados / fuera de orden | 38 ms · 0 / 0 / 0 | 48 ms · 0 / 0 / 0 |
| `overlay` | `ok` · `scoreLoadToRenderedMs` | sí · 127 | sí · 141 |
| `resize` | `allInnerMatch` · `alphaTabRerenderedEveryStep` | sí · sí | sí · sí |
| `resize` | `scoreLoadToRenderedMs` · anchos de `surfaceWidth` (800, 560, 400) | 126 · 783 / 543 / 383 | 125 · 783 / 543 / 383 |
| `songsterr` visible | `secondsToPageFinished` · `htmlBytesAtFinish` · `htmlBytesAfter4s` | 1,379 s · 228.417 · 230.390 | 1,251 s · 202.765 · 229.964 |
| `songsterr` oculto `offstage` | `msToPageReady` · `htmlBytes` · `jsTicksIn2s` | 1418 · 230.706 · 7 | 1390 · 230.278 · 7 |
| `songsterr` oculto `zero` | `msToPageReady` · `htmlBytes` · `jsTicksIn2s` | 1529 · 230.707 · 19 | 1365 · 230.278 · 19 |
| `songsterr` oculto `offscreen` | `msToPageReady` · `htmlBytes` · `jsTicksIn2s` | 1485 · 230.706 · 7 | sin medir (no existe en esta candidata) |
| `occluded` visible | `rafFps` · `ticksPerSecond` (esperado 10) | 72,09 · 9,65 | 71,96 · 9,65 |
| `occluded` oculta (retardo de 8 s) | `rafFps` · `ticksPerSecond` · `vis` | 0,0 · 0,94 · `hidden` | 0,0 · 0,95 · `hidden` |

- **Songsterr:** en las dos candidatas y en todos los modos devolvió su HTML (título «Guitar Tabs with Rhythm | Songsterr», `readyState` `complete` en los modos ocultos), con el UA de Safari fijado (`uaMatches: true`, `Version/17.5 Safari/605.1.15`). El JS sigue vivo en los tres modos ocultos (`jsAlive: true`). El informe `songsterr` usa el modo `none`; los demás modos van con `--mode`. `hiddenModesLocalTest` (página local) también pasa en los cuatro modos de las dos (48-161 ms).
- **Teclado y foco:** medido el 23/11 (bloque `keys` al final de la sección). Con el WebView enfocado las dos incumplen «ninguna tecla de edición perdida ni duplicada»; con el diseño «WebView sin foco» cumplen.
- **Aspecto de las capturas:** `internalSnapshot` (captura de `RepaintBoundary`) no recoge el contenido del WebView (`webContentCaptured: false`, 0 píxeles distintos del fondo salvo en `overlay`, 522 de la caja naranja). Que la caja naranja queda encima de la partitura se juzga con la captura externa (`p4-<candidata>-overlay.png`); esa mirada no consta aquí.

Hallazgos para la ola 0:

- **`shim.js` es necesario.** El plugin entrega `message.body.toString()`, así que el JS debe enviar `JSON.stringify(...)` o llega texto no JSON. Con el shim, `shimOk: true` y 0 mensajes no JSON en las dos. El canal `webkit.messageHandlers.tf` existe en `WKWebView` y el shim no cambió entre candidatas.
- **`fetch` y XHR de `file://` a `file://` fallan en `WKWebView`** (`TypeError: Load failed` / `onerror`), tanto para `font/Bravura.woff2` como para `soundfont/sonivox.sf2`. `@font-face` sí carga (`document.fonts`: familia «alphaTab», estado `loaded`; no aparece como «Bravura»). Los recursos que alphaTab pide con `fetch` (SoundFont) hay que entregarlos por otra vía (bytes por el canal Dart ↔ JS o esquema propio); no se ha probado ninguna.
- **TCC de volumen extraíble.** Lanzada con `open` desde `/Volumes/SSD Mac`, la app queda parada en el arranque con el diálogo «quiere acceder a los archivos de un volumen extraible»; sin conceder, Dart ni arranca y no hay informe. Por eso la prueba corre desde `/private/tmp/p9p4`. Tras reconstruir cambia la firma ad hoc y TCC puede volver a preguntar.
- **Ventana tapada y oculta:** con `vis: hidden`, `rafFps` cae a 0 y los temporizadores a 0,94-0,95 por segundo (los de 100 ms pasan a ~1 s; hasta ~2 s entre muestras al final). Un reloj de reproducción en JS no sirve con la ventana oculta; la sincronía la debe llevar Dart o el núcleo. Con la ventana visible: rAF ~72 y 9,65 tics/s de 10.
- **La oclusión no siempre se aplica.** Una ejecución de `all` dio `rafFps` 72 en `occluded-hidden` (oclusión no efectiva); repetido solo dio 0 en las dos. El informe que consta es el repetido.
- **`material_ui`** aparece en el `pubspec` de las dos apps; el código de la prueba solo usa `widgets.dart`. Sin comprobar si lo añadió `flutter create`.

Diferencias entre candidatas (de los números):

- Rendimiento prácticamente igual: tiempos de arranque y de render dentro de ~10 ms, mismo comportamiento con la ventana tapada y mismo redimensionado.
- `webview_flutter` tiene la ida y vuelta algo menor (mediana 0,125 frente a 0,182 ms; máx 4,2 frente a 9,1 ms), con una sola ejecución cada una: no se distingue del ruido sin repetir.
- `webview_all` tiene `OffscreenWebViewSession` y un cuarto modo oculto (`offscreen`); `webview_flutter` no. Los modos `offstage` y `zero` ya bastan en las dos para obtener el HTML de Songsterr.
- En `songsterr` visible, el HTML al terminar la carga fue menor en `webview_flutter` (202.765 frente a 228.417 bytes), pero a los 4 s casi igual (229.964 frente a 230.390): la página aún se estaba rellenando.

Sin decidir: `keys` no desempata (las dos se comportan igual); la candidata se elige tras la pasada de Windows (DPI, repintado, teclado). Si empatan, decide Jorge.

Sin medir: teclado y foco en Windows; Windows; retardo con la ventana minimizada; carga de la SoundFont por una vía que funcione; versión de Flutter con la que se compiló cada app de `webview/` (`fvm flutter --version` desde la raíz da 3.44.5 y no 3.50.1; hay que confirmar el `.fvmrc` de cada una).

**`keys` (23/11/2026, Jorge al teclado).**

- Código: `--keys-mode raw|prevent|handled|flutter` y `--reclaim makeFirstResponder` en `webview/<app>/lib/case_keys.dart`; detector de tormenta en el informe (`storm`, `maxDownsPerKey`, `jsKeyTotal`, `flutterKeyTotal`, `mouseDowns`, `reclaimCalls`, `reclaimResults`); canal `tf/focus` (`reclaim` → `window.makeFirstResponder(flutterViewController.view)`) en `macos/Runner/MainFlutterWindow.swift`. Commit `4f39a94`. Repetir (primer plano, desde la copia en `/private/tmp/p9p4`): `/private/tmp/p9p4/<app>.app/Contents/MacOS/<app> --case keys --keys-mode <modo> [--reclaim makeFirstResponder] --report <json> --exit-after 45`. Informes en `Temp/p9-flutter/p4-<app>-keys.json` (modo `raw`) y `Temp/p9-flutter/keys-<app>-<modo>.json`.
- **Modo `raw` (el caso original): las dos candidatas incumplen el umbral.** Con el WKWebView como primer respondedor, cada tecla rebota en bucle. `webview_all`: 13.672 eventos de tecla en 86 s; lado JS `1` = 1.044 `keydown` y 1 `keyup`, ráfaga de 368 `keydown` en 0,12 s (~3.000/s). `webview_flutter`: 29.833 eventos; `q` = 738 `keydown` y 1 `keyup` (~1.700/s). El lado Flutter recibe cientos de pares down/up sintéticos con el mismo instante. Con el foco en el `EditableText` de Flutter cada tecla llega una vez y al JS no le llega nada.
- Es un fallo conocido y abierto: flutter/flutter#184557 (P2, `p: webview-keyboard`, macOS). Diagnóstico del mantenedor según la búsqueda (`Temp/research/7f-webview-keys-macos.md`, no versionado): Flutter y WebKit procesan las teclas de forma asíncrona y al redespacharse el evento la guarda de WebKit ya está limpia; sin arreglo ni PR. `flutter_inappwebview` (respaldo) también es WKWebView: se asume igual, sin probar.
- Variantes con `webview_flutter` (45 s cada una; pasos: foco al WebView, `1 2 3`, clic de ratón en la página, `4 5 6`, foco al campo, `hola`):

| Modo | Qué hace | Tormenta | Teclas JS / Flutter | Resultado |
| --- | --- | --- | --- | --- |
| `flutter` + `makeFirstResponder` | El WebView nunca toma el foco; un `Focus` de Flutter captura y reenvía cada tecla al JS; tras cada `mousedown` de la página el runner devuelve el primer respondedor a la vista de Flutter | no | 104 / 140 | pasa |
| `handled` | El handler de `HardwareKeyboard` devuelve `true` con el WebView enfocado | sí | 30.379 / 60.749 (`1` y `2`: 10.175 `down`) | falla |
| `prevent` | La página hace `preventDefault()` y `stopPropagation()` | no | 60 / 30 | no rebota, pero unas teclas llegan solo a la página y otras a los dos lados según el primer respondedor |

- Modo `flutter`, detalle: `webview_flutter` 4 clics de ratón, 4 `reclaim` con resultado `true`; `q` 19 en Flutter y 19 en JS, `w` 6 y 6, `e` 5 y 5; campo `hola`. `webview_all`: sin tormenta, 154 / 264, 5 clics y 5 `reclaim` `true`; dígitos Flutter/JS `1` 13/9, `2` 14/10, `3` 15/11, `4` 11/9, y la diferencia coincide con lo tecleado en el campo y con el grupo anterior a que el nodo tuviera el foco. Las letras de `webview_all` no se cuadraron una a una.
- `FocusNode.requestFocus()` solo, sin `makeFirstResponder`: sin probar.
- **Conclusión para la ola 2 (Tablatura):** `TfWebView` no toma nunca el foco de teclado en macOS; Flutter captura atajos y edición y los reenvía por el canal a `tf-bridge.js` (coincide con «Atajos por tecla lógica» de `docs/flutter/decisiones-interfaz.md`); tras cada clic en la partitura el runner hace `makeFirstResponder` de la vista de Flutter. Coste: sin IME ni copiar/pegar nativos dentro de la página.
- Las dos candidatas siguen empatadas; la elección queda para la pasada de Windows (prueba 7).
- Límites: una pasada por modo; `handled` y `prevent` solo en `webview_flutter`; nada en Windows.
- Arreglo del probe: `applicationShouldTerminateAfterLastWindowClosed` devuelve `false` en las dos apps (cerrar la ventana mataba la app antes de escribir el informe; tres intentos sin informe por eso).

### Prueba 5 · Vídeo (Mac) — PASA EL NATIVO; fvp NO CUMPLE EL ERROR A/V

Código nativo: `Probes/P9-flutter/AppCoreFFI/Sources/AppCoreFFI/VideoProbe.swift` (`AVPlayer` esclavo de un reloj externo → `AVPlayerItemVideoOutput` → `CVPixelBuffer` BGRA → textura), exports `tf_debug_video_{open,state,close,clock,loop,info,stats}` en `Exports.swift`, `app/lib/probe5_video.dart` y `app/lib/probe5_measure.dart`. fvp: `Probes/P9-flutter/video/vp_fvp/` (fvp 0.40.0, mdk 0.40.1). Commits `5f6adeb`, `db75682`, `8c7a79f`, `d8503d6`, `6c2e319` y `e01fea4`. Repetir: `bash Probes/P9-flutter/run-probe5.sh <native|fvp> all` (con `SKIP_BUILD=1` el nativo no recompila); humo sin Flutter: `ffi-smoke --video <fichero> --case steady`. Informes en `Temp/p9-flutter/p5-<candidata>-<caso>-<fichero>.json`.

- **Condiciones:** las dos se lanzan desde una copia en `/private/tmp/p9p5` (TCC de volumen extraíble, como la prueba 4). Vídeos: `code-hevc.mov` y `code-h264.mp4` (1080p30, 30 s, sintéticos con el número de fotograma incrustado; son los únicos en los que se mide el error A/V) y, de toma real, `take-hevc.mov`, `take-hevc-rot90.mov` y `take-h264-rot90.mp4` (sin índice incrustado: error A/V no medible).
- **Resultado: gana el nativo (provisional; falta Windows).** Cumple todos los umbrales. fvp no cumple el error en régimen (mediana 17-20 ms, p95 de ~1 fotograma) ni, con VideoToolbox, la recuperación tras salto (hasta 505 ms).
- **Aviso de método:** las dos medidas no son idénticas. El nativo mide en el núcleo, por entrega de fotograma; fvp se muestrea con `toImage` sobre lo pintado, y la CPU de ~50 % de sus casos `steady`/`seek`/`loop` incluye ese muestreo (por eso su CPU válida es la del caso `cpu`).

Error A/V en ms (mediana / p95 / máx; umbral ≤ 16,7 en régimen, recuperación < 300):

| Caso | Nativo HEVC | Nativo H.264 | fvp HEVC | fvp H.264 |
| --- | --- | --- | --- | --- |
| Régimen 100 % | 8,06 / 13,16 / 15,14 | 7,65 / 12,56 / 14,03 | 19,4 / 34,6 / 38,5 | 19,8 / 34,9 / 39,0 |
| Régimen 70 % | 5,44 / 9,16 / 12,47 | 5,54 / 9,19 / 10,06 | 17,6 / 32,5 / 35,1 | 17,7 / 32,7 / 35,0 |
| Régimen 50 % | 3,9 / 6,46 / 7,2 | 3,93 / 6,57 / 7,38 | 17,1 / 32,1 / 34,1 | 17,2 / 32,1 / 34,1 |
| En bucle | 7,48 / 12,66 / 14,21 | 7,57 / 12,84 / 14,63 | 19,7 / 34,7 / 38,7 | 19,5 / 34,6 / 37,4 |
| Recuperación tras salto (ms) | 15-76 | 21-133 | 41-470 | 61-505 |
| Recuperación en la vuelta del bucle (ms) | 0-20,9 | 0-20,9 | 47-462 | 49-494 |
| Repetidos / saltados (régimen) | 0 / 0 | 0 / 0 | sin dato | sin dato |
| CPU % de un núcleo | 11,9 régimen; 16,5 salto; 17,1 bucle | 12,7; 16,8; 16,6 | 14,3 (caso `cpu`, VT) | sin medir aparte |
| Vigilante máx del hilo de UI (ms) | 18,9 régimen; 10,9 salto; 6,7 bucle | 14,0; 23,8; 2,5 | sin dato | sin dato |

- **Tomas reales, nativo:** `take-hevc-rot90.mov` rotación 270°, 1080×1920, PTS inicial 0, primera entrega 39 ms, vigilante 2,0 ms, CPU 15 %; `take-h264-rot90.mp4` 270°, 1080×1920, PTS 0, 38 ms, 1,8 ms, 14 %; `take-hevc.mov` 0°, 1920×1080, PTS inicial 155,547 s (edición vacía inicial, resuelta con el segmento no vacío), primera entrega 61 ms, vigilante 1,6 ms.
- **Tomas reales, fvp:** mdk da `rotation=270` y textura 1080×1920 en los dos `rot90`.
- **Juicio visual del orquestador:** rotación del nativo correcta en `take-hevc-rot90.mov`: la captura `Temp/p9-flutter/p5-native-rotation-take-hevc-rot90.png` tiene la misma orientación que la miniatura de Quick Look del fichero. Sin mirar: el H.264 girado y las capturas de fvp.

Lo aprendido de fvp:

- El fotograma congelado con una sola llamada a `onSync` eran dos fallos del probe: `SeekFlag.frame` hace que la posición sean fotogramas (el salto caía tras el final y mdk se paraba); con `minInterval=0` mdk no espera al reloj (30 s en 0,9 s), con 10 lo sigue a 105-126 Hz desde un hilo que no es el principal.
- Decodificador: con `VT,FFmpeg` HEVC baja de 45,6 % a 14,3 % de CPU; con solo FFmpeg la recuperación tras salto era 75-183 ms y el error igual (`Temp/p9-flutter/ffmpeg-run/`).
- En Windows el callback tendría que ser un shim C de ~30 líneas en el runner (`NativeCallable.isolateGroupBound` exige `--experimental-shared-data`); sin probar.

Hallazgos para la ola 0 (nativo):

- **La apertura tiene que ser asíncrona.** La primera versión sondeaba `item.status` con `Thread.sleep` y dentro de Flutter devolvía fallo (el isolate de UI es el hilo principal); con apertura asíncrona y estado abriendo/listo/fallo abre. La causa no se midió antes del arreglo: el resultado la respalda sin probarla. `setClock`/`setLoop` anteriores a «listo» se guardan y se aplican al abrir.
- **Defecto del probe arreglado:** sin índice incrustado la mediana era NaN, `jsonEncode` lanzaba y el temporizador de `--exit-after` no llegaba a `exit()` (app colgada 9 min, hilo principal ocioso). Ahora NaN → `null` y la salida es incondicional.
- **Coste en Windows:** pipeline propio de Media Foundation (`IMFMediaEngine` no admite reloj externo), como ya dice `docs/flutter/arquitectura.md` («Vídeo de tomas»). Sin estimar ni probar; es del resto de la prueba 7.

Sin medir / sin explicar: vigilante de 18,9 ms (régimen HEVC) y 23,8 ms (salto H.264), por encima de los 16 ms de la prueba 2, sin investigar; error A/V con tomas reales; `openMs`; repetidos/saltados y vigilante en fvp; `open -g -n` de fvp desde la copia local (el script lo usa y dejó informes, no se comprobó aparte); nada en Windows.

### Prueba 6 · Captura y tests (Mac) — PASA

Adelantada a la primera pasada del PC porque es Dart puro y no depende de la vía de hilos. Código: `Probes/P9-flutter/app/lib/probe6_snapshot.dart`, `app/test/` y `Probes/P9-flutter/test-probe.sh`. Commit `53559df`. Repetir: `open -g -n -W <tf_probe.app> --args --snapshot <png>` (build release) y `bash Probes/P9-flutter/test-probe.sh`.

- **Umbral** (PNG correcto sin ventana en primer plano; golden estable en dos ejecuciones): cumplido. El orquestador miró la captura y el golden: fuentes reales, bordes de 1 px, radios, degradado y trazos finos correctos.
- **`--snapshot`** con `RepaintBoundary.toImage`: PNG de 1440×900 exactos; 4 capturas idénticas byte a byte (SHA1 `5d851888…`), incluidas una con la ventana totalmente tapada por otra y una con la app oculta (`set visible false`). Minimizada, sin probar. La app frontal no cambió. 2,45-2,71 s desde `open` hasta el PNG, con el retardo de 2,0 s.
- **`pixelRatio` fijo a 1.0** y contenido de tamaño lógico fijo (`SizedBox` de 1440×900, o `--window WxH`) dentro del `RepaintBoundary`, con un `FittedBox` para verlo en pantalla: la captura no depende del monitor ni del tamaño real de la ventana. `--window` no puede fijar la ventana sin plugin (`window_manager` llega en la ola 0).
- **Golden** con `matchesGoldenFile`: estable en dos ejecuciones. Carga los TTF reales con `FontLoader` (sin ellos `flutter test` pinta cuadrados) y fija `devicePixelRatio` 1.0 y 1440×900. El render de test es por software, no depende del monitor. Sin probar en otra máquina; se generan solo en el Mac, como ya dice `arquitectura.md`.
- **El golden y la captura de la app no son idénticos byte a byte** (hashes distintos: motor real frente a render de test), aunque a la vista coinciden. Son dos referencias distintas: los goldens protegen de regresiones en tests; las capturas `--snapshot` son las que se comparan con la referencia de SwiftUI.
- **`test-probe.sh`** (lo que será el paso `FlutterApp` de `Tools/test.sh`): `flutter analyze` + `flutter test --reporter=json`, log completo a `Temp/logs/p9-flutter-test.log`, resumen de 3 líneas en verde (`analyze: 0 avisos` / `tests: 5 pasados, 0 fallados, 0 saltados`) y una línea `fichero:línea mensaje` por fallo. Códigos comprobados: 0 verde, 1 test fallado o avisos, 2 error de compilación. `flutter test`: ~3 s en caliente, 7,4 s la primera vez. Depende de `python3` para resumir el JSON.

### Prueba 7 · PC x64 — PASA

#### 7b · AppCoreFFI.dll y humo sin Flutter — PASA

Código: `Probes/P9-flutter/pc.sh` (`sync`, `core`, `smoke`, `fetch`) y `Probes/P9-flutter/win/*.ps1` (`common.ps1`, `core.ps1`). Commits `765a251` (código de hilos de Windows escrito a ciegas en el Mac), `d2ed623` (Dart portable a Windows y medidas de hilos) y `1310404` (`pc.sh`). Repetir: `Probes/P9-flutter/pc.sh sync && Probes/P9-flutter/pc.sh core && Probes/P9-flutter/pc.sh smoke`.

- **PC:** Swift 6.4.3, VS Build Tools 2022 17.14 (VCTools, CMake, SDK 26100; sin ATL), Flutter 3.50.1 en `Temp\p9\flutter` (sin PATH). Todo dentro de `D:\Personal\Guitar-Tool\Temp\p9\`; ningún git en ese checkout.
- **Humo sin Flutter** (`ffi-smoke-win.exe`, hilo principal en `tf_core_run_main()` = vía 1 fuera de Flutter): 4000 idas y vueltas, 0 errores; mediana 0,15 ms, p99 0,22-0,24 ms, máx 0,33-0,38 ms; `probe.mainactor` con los dos `true`; cierre `clean:true` en 25-32 ms; búferes vivos 0.
- **Compilación:** el código de Windows escrito a ciegas compiló sin cambios; la DLL exporta las 17 `tf_*`; los símbolos `_4CF` de la vía 2 enlazan.
- **Salida:** `AppCoreFFI.dll` (47 MB) más 19 DLL (16 del runtime de Swift de `D:\tf-rtl-x64`, 3 de `D:\tf-ort\x64`) en `Temp\p9\out\core\`, calculadas por cierre de importaciones (`win/core.ps1`).
- **Flags:** `-c release --arch x86_64` y `--cache-path`/`--config-path`/`--security-path` dentro de `Temp\p9\swiftpm`; `win/common.ps1` pone `USERPROFILE`/`HOME`/`TEMP`/`TMP` dentro de `Temp\p9`. Primera compilación 245 s, incremental 13-26 s.
- **Sin medir todavía:** retraso del hilo principal y procesos hijos en Windows; `pc.sh fetch` sin probar; `P9_STATIC=1` sin probar; DLL cargada desde un hilo que no es el principal (el caso de Flutter; lo cubre 7d).
- **Escape fuera de la carpeta:** `C:\Users\Jorge\.swiftpm\` (`configuration\` vacía, `security\fingerprints\` con 2 JSON, `cache` como enlace a `Temp\p9\tmp\org.swift.swiftpm`). Jorge (22/11): se deja como está.

#### 7d · App Flutter en el PC e hilos — PASAN LAS DOS VÍAS; DECIDIDO: VÍA 1

Código: `Probes/P9-flutter/pc.sh` (`app`, `run`, `threads`), `win/app.ps1`, `win/run.ps1` (tarea programada interactiva `tf-p9-run`, se crea, ejecuta y borra en cada uso) y `pc-table.py`. Commit `534bb12`. Repetir: `Probes/P9-flutter/pc.sh sync && Probes/P9-flutter/pc.sh app && Probes/P9-flutter/pc.sh threads` (10-25 min). Informes en `Temp/p9-flutter/pc/p2-<threads>-<sink>.json`.

- **Build** de `tf_probe` en el PC: 71,5 s la primera vez (con `pub get`); `Release\` de 166 MB con 20 DLL (`AppCoreFFI.dll` + 19). Sin parches al código de la prueba. `flutter.bat` con `PUB_CACHE`, `APPDATA` y `LOCALAPPDATA` dentro de `Temp\p9` (`Set-FlutterEnv` en `win/common.ps1`): ninguna escritura de Flutter ni Dart fuera de la carpeta.
- **`--threads none`** (plantilla de Flutter sin cambios): falla como se esperaba. `@MainActor` no se ejecuta (2999 ms) y `audio.devices` da timeout. Hace falta una vía.
- **Hilos:** la vía 1 deja el isolate fuera del hilo principal del proceso (`isMainThread=0`); la vía 2 lo deja en él (`=1`). Apartamento COM 3 (STA) antes, tras arrancar y tras las llamadas, en las dos.
- **Tabla** (dos tandas; cuando hubo informe, 4000 idas y vueltas, 0 errores, mediana 0,17-0,21 ms):

| Combinación | Tanda A (20:14) | Tanda B (20:28-20:48) |
| --- | --- | --- |
| vía 1 · puerto | p99 0,33 ms, máx 1,98; vigilante 30,6 ms; cierre 33 ms limpio; informe completo | cuelgue (sin informe, 124) |
| vía 1 · `listener` | p99 0,30, máx 20,9; vigilante 18,8 ms; cierre 32 ms limpio | `@MainActor` timeout; p99 6,06, máx 8369; vigilante 5792 ms |
| vía 2 · puerto | p99 0,32, máx 3,0; vigilante 18,6 ms; cierre 31 ms limpio | p99 14,8, máx 3313; vigilante 5313 ms; cierre 7531 ms no limpio; RSS +9 MB |
| vía 2 · `listener` | p99 0,51, máx 15,7; vigilante 6,1 ms; cierre 10 ms limpio; RSS +12 MB entre 4000 y 8000 | p99 28,1, máx 9822; vigilante 5861 ms; cierre 6416 ms limpio |

- **Único informe completo** (vía 1 · puerto, tanda A): nativo→Dart a 60 Hz libre p99 199 µs, ocupado p99 8066 µs; ráfaga de 5000 a 10,1 µs por mensaje; 0 pérdidas, 0 fuera de orden; RSS 78 → 108 MB; eventos de fondo de `import.file` recibidos (5 de progreso, 6 `library.changed`). En el resto, el probe para en el primer umbral que falla y no llega a esas fases.
- **Defectos conocidos del lanzador:** `run.ps1` espera 300 s y devuelve 125 aunque la app muriera con 124; un informe local viejo no se sobrescribe si la ejecución no dejó informe.

**Diagnóstico (22/11 21:40, PC quieto, carga 0-9 %).** `--sink port`, 4000 llamadas, 3 ejecuciones por vía; el probe ya no para en el primer umbral (`--no-fail-fast`) y el vigilante anota la fase de cada pico.

- **Resultado: las dos vías pasan 3 de 3.** 0 errores, `threadsOk`, 0 pérdidas ni desorden, cierre limpio en 23-35 ms en las seis.
- **Ida y vuelta (med / p99 / máx, ms):** vía 1, 0,18 / 0,30-0,32 / 1,51-1,75; vía 2, 0,18-0,19 / 0,34-0,36 / 1,88-3,01.
- **`watchdogMaxExclBusy` (ms, umbral 16):** vía 1, 6,3 / 13,7 / 10,0; vía 2, 11,8 / 11,4 / 5,7. El máximo global, 172-191 ms, cae siempre en la fase `decode` (banco síncrono, esperado).
- **Nativo→Dart:** 60 Hz libre, p99 141-251 µs; ocupado, ~8080-8099 µs; ráfaga, 9,6-12,8 µs por mensaje.
- **RSS:** 74 → 102-105 MB. El criterio extra «RSS > +8 MB entre 4000 y 8000» falla en via1-1 (+11) y via1-2 (+10) y no en vía 2: con puerto los búferes los libera el GC. Sin concluir; se vigila con una ejecución larga.
- **Picos por fase:** los mayores en `idle` (~1,5 s) y `free_60hz`, nunca por encima de 14 ms; ninguno en `startup`.
- **Conclusión:** los bloqueos de ~5 s de la tanda B eran carga del PC (Jorge lo usaba), no de la vía.
- **Repetir:** `Probes/P9-flutter/pc.sh diag [extra]` (con `run.ps1 -NoRedirect`); informes en `Temp/p9-flutter/pc/diag-<via>-<n>.json`. La DLL del PC ya incluye las funciones de fotogramas (26 `tf_*`).

**Decisión de Jorge (22/11): vía 1.** Motivo: empate en números, y la vía 2 depende de símbolos privados `_4CF` de libdispatch, frágiles ante cambios de toolchain; la vía 1 es la de `WinApp` (probada en la 7c). Consecuencia: la ABI no lleva `tf_core_pump` ni `tf_core_main_queue_handle`; el principal queda en `tf_core_run_main()`.

**Medidas con el PC quieto (23/11, vía 1).** Commit `2c700bf`. Repetir: `pc.sh diag sink`, `pc.sh soak 660`, `pc.sh mf`. Informes en `Temp/p9-flutter/pc/` (`sink-*`, `soak-via1.json`, `mf-via1.json`).

- `listener` contra puerto, 3 ejecuciones de cada, alternadas, carga previa 1-16 % (una de `port` sin carga leída): ida y vuelta mediana 0,18-0,19 ms, p99 0,30-0,33 ms, máx 1,4-2,9 ms en las seis; vigilante 2,0-14,8 ms; nativo→Dart 60 Hz libre p99 138-260 µs, ocupado 8066-8089 µs; ráfaga 9,7-13,0 µs por mensaje; 0 pérdidas y 0 desorden; cierre limpio 21-34 ms. Diferencia: búferes vivos 0 con `listener`; con puerto 114-257 durante la prueba y 12-17 al final (los libera el GC); RSS 79 → 93-99 → 103-106 MB en los dos, pero `port` crece 9 y 13 MB entre 4000 y 8000 en 2 de 3 (umbral del probe 8 MB) y `listener` no pasa de 8. Empate en latencia; decisión de mecanismo pendiente de Jorge (propuesta: puerto, por orden garantizado).
- RSS largo, vía 1 con puerto: 660 s, 3.921.800 idas y vueltas, 0 errores, cierre limpio. RSS (MB): inicio 80,1, 25 % 103,9, 50 % 53,0, 75 % 38,1, fin 37,3 (mín 36,0, máx 104,2); pendiente de los últimos 5 min −1,47 MB/min; búferes vivos 6-278. Pasa: dientes de sierra, sin techo creciente. Sin explicar: un pico de ida y vuelta de 666 ms.
- STA tras Media Foundation: apartamento del hilo de UI 3 (STA) antes, tras `MFStartup`, tras `MFCreateAttributes` + `MFEnumDeviceSources` (1 dispositivo, sin abrir) y tras `MFShutdown`; `audio.devices`, `@MainActor` y `dispatchMain` responden antes y después. Pasa. Export de depuración `tf_debug_mf_step`, probes `--probe ffi-soak` y `--probe ffi-mf`.

#### 7e · Compilación de las candidatas de WebView — PASAN LAS TRES (una con ajustes de entorno)

Código: `Probes/P9-flutter/webview/{wv_all,wv_flutter,wv_inapp}` (app mínima con el widget WebView y `--exit-after`), `pc.sh webview [candidata]` y `win/webview.ps1`. Repetir: `Probes/P9-flutter/pc.sh sync && Probes/P9-flutter/pc.sh webview`; una sola: `pc.sh webview wv_all|wv_flutter|wv_inapp-short`. Solo mide que compila y arranca; el comportamiento es del resto de la prueba 7.

- **Tabla** (Flutter 3.50.1, Windows x64 release; ninguna obliga a Material; `analyze` con 0 avisos en las tres):

| Candidata | Versiones (paquete / implementación de Windows) | Compila | Build (s) | Arranque (`--exit-after 5`) | Tamaño | Requisitos |
| --- | --- | --- | --- | --- | --- | --- |
| `webview_all` | 1.5.2 / `webview_all_windows` 1.5.2 | sí | 138 | código 0, 28,8 s | 25,3 MB | ninguno |
| `webview_flutter` | 4.14.1 / `webview_flutter_windows` 1.3.1 | sí | 175,3 | código 0, 90,6 s | 23,8 MB | ninguno |
| `flutter_inappwebview` (respaldo) | 6.1.5 / `flutter_inappwebview_windows` 0.6.0 | con ajustes de entorno | 208,3 | código 0, 10,5 s | 24,5 MB | `nuget.exe` en el PATH y ruta de proyecto corta; 8 avisos de build |

- Las tres añaden `WebView2Loader.dll` y la DLL de su plugin. ATL no hizo falta en ninguna. Runtime de WebView2 del PC: 158.0.4370.33 (ya instalado).
- **`flutter_inappwebview_windows`:** con la ruta normal falla `MSB3491` (ruta demasiado larga en `..._DEPENDENCIES_DOWNLOAD...lastbuildstate`); con ruta corta y sin NuGet falla `MSB3073: NUGET-NOTFOUND` (WIL, `Microsoft.Web.WebView2` 1.0.2792.45, `nlohmann.json` 3.11.2): el plugin espera `nuget.exe` en el PATH y no lo descarga. La prueba copia el proyecto a `Temp\p9\w\wv_inapp` y usa un `nuget.exe` suelto en `Temp\p9\tools` (nada instalado en el sistema; paquetes en `Temp\p9\nuget`).
- **Sin explicar:** el arranque de `webview_flutter` tardó 90,6 s con `--exit-after 5` (hipótesis sin medir: inicialización de WebView2). Se mira en el resto de la prueba 7.
- **Escritura fuera de `Temp\p9`:** `C:\Users\Jorge\AppData\Local\webview_all_windows\wv_all\EBWebView\` (datos de usuario de WebView2, 22/11 20:57), creada por `webview_all` al arrancar con el perfil real. Para la app: fijar la carpeta de datos de usuario de WebView2 dentro de `--support-dir`.
- `pc.sh sync` excluye ahora `ephemeral` (enlaces simbólicos a rutas del Mac que hacían fallar la extracción).
- **Sin comprobar:** que el WebView pinte el HTML; build para macOS de estas apps mínimas; `pc.sh webview` entero de una sola vez con los últimos cambios (se validó por tandas).

#### 7f · Textura externa con Impeller — PASA CON `GpuSurfaceTexture` (umbral de Windows: ≤ 3 descartes por minuto, decisión de Jorge)

- Código: `AppCoreFFI/Sources/AppCoreFFI/Frames+Windows.swift` (generador BGRA sin CoreVideo; `TF_P9_SOLID=1` = rojo puro con cuadrado azul 200×200), `FrameRegistry.swift`, `CAppCoreFFI/tf_d3d.c` (dispositivo D3D11 propio, textura `B8G8R8A8` compartida por canal con `D3D11_RESOURCE_MISC_SHARED`, handle clásico de `GetSharedHandle`, sin mutex ni doble búfer), `app/windows/runner/tf_texture_host.{h,cpp}` (`--texture-kind gpu|pixel`), `win/shot.ps1`, `pc.sh frames [--no-fail-fast]` y `pc-frames-table.py`; exports nuevos `tf_debug_frames_extra`, `tf_debug_frames_reset` y `tf_hr_sleep_ns`; `TF_P9_PRECISE=1` (generador con reloj de alta resolución). Commits `49e2113`, `f4d7861` y `a7438bf`. Repetir: `Probes/P9-flutter/pc.sh sync && Probes/P9-flutter/pc.sh core && Probes/P9-flutter/pc.sh app && Probes/P9-flutter/pc.sh frames`; informes y capturas en `Temp/p9-flutter/pc/p3-<kind>-<size>.json|png`.
- Impeller activo en Windows: el log del motor dice `Using the Impeller rendering backend (OpenGLESSDF)`. «Could not create external texture» no apareció.
- Cabeceras de Flutter 3.50.1 (leídas en el PC): `gpu` = `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`, pide el HANDLE de `IDXGIResource::GetSharedHandle` (`flutter_texture_registrar.h:35-38, 77-80`), formato BGRA8888 opcional; `pixel` = `FlutterDesktopPixelBuffer` sin campo de formato, el motor lo trata como RGBA y el runner convierte BGRA→RGBA por fotograma. `flutter::FlutterEngine` no expone `texture_registrar()`: se saca con `GetRegistrarForPlugin` + `FlutterDesktopRegistrarGetTextureRegistrar` (API C). `MarkTextureFrameAvailable` se puede llamar desde cualquier hilo (`texture_registrar.h:83-84`); se llama desde el hilo del generador, leído y no probado con carreras.
- Primera medida (conteo desigual, descartada): `gpu` 720 1770/1766, `pixel` 720 1770/1770.
- Segunda medida, con conteo por número de secuencia en los tres caminos (fotogramas distintos entregados), 60 s cada una, vía 1, Impeller:

| Combinación | Producidos / distintos | Descartes | Copias duplicadas | CPU % de un núcleo | RSS 5 / 30 / 60 s (MB) | Vigilante máx (ms) | Productor p99 / máx (ms) | Peticiones p99 / máx (ms) | Carga del PC antes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gpu` 720 | 1770 / 1769 | 1 | 15 | 0,689 | 119,5 / 120,3 / 121,6 | 15,4 | 47,5 / 52,9 | 61,5 / 71,0 | 4 % |
| `gpu` 1080 | 1771 / 1768 | 3 | 12 | 0,742 | 132,5 / 133,4 / 134,5 | 20,1 | 47,3 / 61,5 | 57,0 / 71,3 | 85 % |
| `pixel` 720 | 1770 / 1770 | 0 | 0 | 0,609 | 133,0 / 131,3 / 132,5 | 13,2 | 47,3 / 48,0 | 56,5 / 61,9 | 3 % |
| `pixel` 1080 | 1771 / 1768 | 3 | 0 | 2,463 | 167,3 / 161,3 / 162,4 | 30,7 | 47,5 / 54,4 | 58,2 / 65,6 | 4 % |
| `bgra` 720 | 1770 / 1771 | 2 | 0 | 0,609 | 118,9 / 119,1 / 121,3 | 13,4 | 47,5 / 48,1 | 5,5 / 112,1 | 100 % |
| `bgra` 1080 | 1721 / 1603 | 120 | 0 | 7,071 | 146,0 / 147,2 / 147,9 | 29,6 | 62,7 / 82,7 | 10,7 / 2298,7 | 7 % |
| `gpu` 720, reloj preciso | 1770 / 1771 | −1 | 14 | 0,238 | 119,3 / 120,2 / 121,3 | 15,7 | 33,8 / 49,0 | 48,3 / 54,8 | 8 % |
| `pixel` 720, reloj preciso | 1771 / 1769 | 2 | 0 | 0,477 | 132,4 / 130,7 / 131,9 | 9,1 | 33,8 / 49,2 | 48,2 / 65,7 | 4 % |

- **Ningún camino da 0 descartes en las dos resoluciones** (umbral de la prueba 3). `gpu`: 1 y 3; `pixel`: 0 y 3. `gpu` no pierde más que `pixel`. Memoria estable en los dos.
- **Causa de los descartes de `gpu`, medida:** todos (1 de 1 y 3 de 3) son secuencias saltadas entre dos peticiones del motor (`fetches.skippedSeqs`); 1 de 1 y 2 de 3 con la petición tardía (> 40 ms; máximo 61-71 ms). No hay ninguno sin explicar por cadencia: no hay indicio de carrera en la textura compartida. Las copias duplicadas (15 y 12) son el mismo fotograma pedido dos veces, no pérdida.
- **Generador:** con el reloj por defecto de Windows produce a ~31 ms de mediana con saltos de hasta 47 ms (mínimo 15,8 ms; ningún intervalo < 8 ms); con `TF_P9_PRECISE=1` la mediana es 33,33 ms y las peticiones > 50 ms bajan de 73-103 a 2. No quita los descartes (`pixel` 720: 2). El −1 de `gpu` preciso es el error de borde ±1 de la ventana de medida.
- **Supuesto, sin aislar:** que los 1-3 descartes por minuto sean tirones del hilo de raster del motor.
- **Copia BGRA por FFI no sirve a 1080p en Windows:** 120 descartes y una petición de 2,3 s. Queda como último respaldo solo a 720p.
- **No limpias:** `gpu` 1080 (carga 85 %) y `bgra` 720 (100 %) se midieron con el PC cargado; repetir con el PC libre.
- **Textura doble (dos texturas alternas):** no justificada por estos números; sin implementar.
- La CPU de Windows no es comparable con la del Mac: solo cuenta el proceso, no driver ni GPU.
- `fetchIntervalMs` se mide en el núcleo (`tf_frame_copy`), no en el runner.
- **Decisión de Jorge (23/11/2026):** en Windows se acepta un umbral de **≤ 3 descartes por minuto** (30 fps, «el último gana») para el canal de fotogramas y se queda `GpuSurfaceTexture` (handle DXGI compartido) como camino; respaldo `PixelBufferTexture`; la copia BGRA por FFI queda descartada a 1080p. El umbral de 0 descartes sigue valiendo en el Mac. Motivo: los descartes medidos (1 y 3 por minuto) son peticiones tardías del motor al pintar, iguales en `gpu` y en `pixel`; cambiar de camino no los quita. Sigue pendiente repetir `gpu` 1080 y `bgra` 720 con el PC libre (se midieron con carga del 85 % y 100 %); no condiciona la decisión.
- Copia BGRA en Windows: funciona (10 s a 720p: 271 / 271, 0 descartes, CPU 1,736 %).
- **Juicio visual del orquestador** (capturas de pantalla con `CopyFromScreen`, `Temp/p9-flutter/pc/p3-solid-gpu.png`, `p3-solid-pixel.png`, `p3-gpu-720.png`): orden de canales correcto en los dos caminos (fondo rojo puro, cuadrado azul arriba a la izquierda, sin volteo vertical ni horizontal); en `gpu` 720 la barra blanca tiene bordes nítidos, sin franjas ni fotograma a medias. Una captura suelta no descarta el desgarro. Sin mirar: `p3-pixel-720.png` y las capturas de la segunda tanda.
- El build de `AppCoreFFI.dll` con el código de la prueba 5 sigue compilando en Windows (26 exportaciones antes de esta parte; `VideoProbe.swift` va bajo `canImport(AVFoundation)`).
- Repetición con el PC libre (23/11): `gpu` 1080, carga 14 %, 1747 producidos / 1745 distintos, 2 descartes (pasa ≤ 3). `bgra` 720, carga 7 %, 1728 / 1659, **71 descartes**: la copia BGRA por FFI queda descartada también a 720p en Windows; el único respaldo de la textura es `PixelBufferTexture`. Repetir: `pc.sh frames --only gpu-1080,bgra-720`.
- **Desgarro visto por Jorge a ojo (23/11):** con `gpu` la barra aparece a veces partida. Corrige el juicio visual anterior («sin franjas ni fotograma a medias»): una captura suelta no lo detectaba. Causa supuesta: una sola textura compartida; el productor escribía con `UpdateSubresource` + `Flush` en la misma textura que el motor lee (el `Flush` ya existía). Arreglo escrito, sin medir todavía: anillo de 3 texturas por canal (el productor nunca escribe en la publicada ni en la última entregada; `Flush` y después publicación atómica), `TF_P9_RING=0` vuelve a la textura única; patrón `TF_P9_TEAR=1`; detector `win/tear.ps1` (ráfaga de capturas, x de la barra en 32 filas). `release_callback` de Flutter no se usa: solo avisa de que el handle se abrió. Commit `b6890b2`. Medida en curso (textura única contra anillo, 720 y 1080); si el anillo no da 0 fotogramas partidos, anillo de 4 y control con `pixel`.
- **Desgarro medido (23/11, tarde):** código `pc.sh tear --ring 0|1|2|3|4 --size 720|1080 --seconds 60 [--kind gpu|pixel]` (`--ring 1` = anillo de 3), `win/tear.ps1`, `pc-tear-table.py`; commit `906d490`. Informes y PNG en `Temp/p9-flutter/pc/tear-<modo>*`. Detector: 50-60 capturas de pantalla por segundo, 0 capturas sin barra; un fotograma partido de ejemplo: barra en x=844 hasta la fila ~620 y en x=814 debajo. Tabla (60 s por medida; modo · carga previa · capturas · partidas · producidos/distintos · descartes · vigilante máx ms):
  - textura única 720 · 1 % · 3475 · 107 (3,08 %) · 2188/2188 · 0 · 17,2
  - anillo 3, 720 · 1 % · 2984 · 71 (2,38 %) · 2190/2190 · 0 · 7,5
  - textura única 1080 · 2 % · 3588 · 372 (10,37 %) · 2190/2190 · 0 · 8,9
  - anillo 3, 1080 · 13 % · 3594 · 241 (6,71 %) · 2190/2189 · 1 · 4,2
  - textura única 720 (2ª) · 30 % · 3441 · 108 (3,14 %) · 2170/2168 · 2 · 13,9
  - anillo 3, 720 (2ª) · 1 % · 3511 · 103 (2,93 %) · 2168/2159 · 9 · 524,2
  - anillo 4, 720 · 14 % · 3582 · 340 (9,49 %) · 2185/2181 · 4 · 64,3
  - `pixel` 720 · 2 % · 3597 · **0** · 2190/2188 · 2 · 9,3
  - `pixel` 1080 · sin leer · 3595 · **0** · 2190/2189 · 1 · 6,0
  - El anillo (3 o 4) no quita el desgarro; `PixelBufferTexture` da 0 fotogramas partidos a 720 y 1080. Jorge lo ve igual a ojo: partida con `gpu` (con y sin anillo), limpia con `pixel`.
  - El desgarro está en las capturas de pantalla (fotograma ya compuesto): no es la salida al monitor. G-Sync descartado: Jorge lo desactivó y siguió pasando (monitor de 144 Hz).
  - A 1080p se parte unas tres veces más que a 720p. Hipótesis sin probar: `Flush()` envía la subida a la GPU pero no espera a que termine, y el motor muestrea la textura compartida a medio subir desde otro dispositivo D3D. Siguiente prueba: publicar el handle solo cuando la GPU confirme (`D3D11_QUERY_EVENT`), con anillo.
  - **La decisión de Jorge del 23/11 (`GpuSurfaceTexture` como camino) queda en revisión**: se tomó sin detector de desgarro. Si la espera a la GPU no da 0 fotogramas partidos, el camino pasa a ser `PixelBufferTexture` (pregunta a Jorge). Sin explicar: el 9,49 % del anillo de 4 (peor que el de 3) y el vigilante de 524 ms de una pasada. Resuelto con la espera a la GPU y decidido (bloque siguiente).
- **Espera a la GPU antes de publicar (23/11, noche) — 0 FOTOGRAMAS PARTIDOS:** código `TF_P9_WAIT=1` en `CAppCoreFFI/tf_d3d.c` (tras `UpdateSubresource`: `ID3D11Query` `D3D11_QUERY_EVENT`, `End`, `Flush`, sondeo de `GetData` con `SwitchToThread`, tope 50 ms; solo entonces se publica el índice y se avisa `frame_available`); `pc.sh tear --ring 0|3 --wait 0|1 --size 720|1080 [--copy 1]`; estadísticas con `tf_d3d_wait_stats`; commit `17c1723`. Tabla (60 s; modo · tamaño · espera · carga previa · capturas · partidas · descartes · espera media/máx µs · vigilante máx ms):
  - anillo 3 · 720 · sí · 2 % · 3595 · 0 · 0 · 2360 / 10857 · 18,9
  - anillo 3 · 1080 · sí · sin leer · 3588 · 0 · 3 · 3333 / 77652 · 73,3
  - textura única · 1080 · sí · 1 % · 3597 · 0 · 0 · 3982 / 17454 · 9,2
  - anillo 3 (control) · 1080 · no · 22 % · 3595 · 296 (8,23 %) · 2 · — · 29,3
  - anillo 3 (repetición) · 720 · sí · 6 % · 3595 · 0 · 0 · 2221 / 18860 · 9,3
  - anillo 3 (repetición) · 1080 · sí · 37 % · 3591 · 0 · 1 · 3901 / 15768 · 22,8
  - 0 `waitTimeouts` en todas. Jorge, a ojo en las cuatro primeras: limpias las tres con espera, partida el control.
  - Causa confirmada: el handle se publicaba antes de que la GPU terminase la subida (`Flush` no espera). La espera cuesta 2,2-4,0 ms de media en el hilo productor (no en el de UI). Descartes ≤ 3 por minuto en todas.
  - Sin explicar: un pico de espera de 77,7 ms con vigilante de 73 ms en una pasada (carga previa sin leer); la carga de las repeticiones y del control no fue baja (6-37 %).
  - `CopyResource` desde textura privada (`TF_P9_COPY=1`) implementada y sin medir: no hizo falta. Con espera tampoco se parte la textura única; se mantiene el anillo porque impide que el productor escriba en la textura que el motor puede estar leyendo.
  - **Decisión de Jorge (23/11/2026, noche):** camino de Windows = `GpuSurfaceTexture` con anillo de 3 y espera a la GPU antes de publicar; respaldo `PixelBufferTexture`. Umbral: 0 fotogramas partidos y ≤ 3 descartes por minuto. Sustituye a la decisión de la mañana (textura única).

#### 7g · WebView en Windows — PASA; ELEGIDO `webview_all`

- Código: casos portados y nuevos en `webview/wv_all` y `webview/wv_flutter` (`capture`, `resize --raf-loop on|off`, `keys --keys-script`), `pc.sh wvrun <app> <caso|all> [--rebuild] [--tag x] [--keep-data]`, `win/keys.ps1` (inyector `SendInput`), `pc-wv-table.py`. Commits `063c404`, `81378ec`, `0c2aeb6`, `f6c9277`. Informes y capturas en `Temp/p9-flutter/pc/wv-<app>-<caso>.*`. Escala 100 % (`devicePixelRatio` 1.0), ventana ~1264×681.
- **`webview_flutter` no tiene implementación en Windows:** `webview_flutter_windows` 1.3.1 es un fork de `webview_windows` con API propia (`WebviewController`, widget `Webview`), no registra plataforma de `webview_flutter`. `wv_flutter` usa en Windows esa API directa (rama por `Platform.isWindows` en `probe_webview.dart`): dos caminos de código por plataforma y sin API de consola JS. `webview_all` usa la misma API en las dos.
- Tabla (wv_all · wv_flutter): `tab` pasa (Bravura sí, 0 `jsErrors`, carga→render 285 · 342 ms); `messages` 1000/1000 sin pérdidas, duplicados ni desorden, ida y vuelta mediana/p99 0,20/0,48 · 0,21/0,39 ms; `overlay` pasa (visto por el orquestador en captura: caja de Flutter encima de la partitura, en las dos); `resize` con rAF on y off: `innerWidth` 800/560/400/800 correcto y repintado en los 4 pasos en las dos (el bucle rAF no hace falta); `capture`: `rafFps` 60,0 en las dos, latencia JS→Dart mediana/p99 0,26/0,42 · 0,31/0,46 ms, 1201/1201; Songsterr visible: HTML 279 · 298 kB en 1,7 · 5,7 s, título y UA de Safari correctos; Songsterr oculto `offstage`/`zero`: HTML 205/205 · 204/203 kB, `jsAlive` false (2 tics en 2 s) · true (20 tics); `keys` modo `flutter` (WebView sin foco): Flutter sin pérdidas ni duplicados, sin tormenta, campo «hola», en las dos; `keys` modo `raw`: sin tormenta en Windows (no aparece el bucle de macOS), las teclas llegan solo al lado que tiene el foco.
- Arranque (`controllerCreated` / `pageFinished`, ms): `wv_all` 560-590 / 630-700; `wv_flutter` 580-1700 / 800-1950, con un `tab` recién compilado de 11916 / 13797 y un `pageFinished` de 6735. No se repitió el arranque de 90,6 s.
- `fetch` y XHR de la SoundFont y `fetch` de Bravura funcionan en Windows en las dos (host virtual `https`), a diferencia de macOS.
- **Correcciones a lo medido (aviso de Jorge, 23/11):** (1) Songsterr visible no se veía porque el probe **no montaba el WebView en modo visible** (`screen.dart` devolvía nulo para el modo `none`; cargaba fuera del árbol). Arreglado en `679122a`; en el Mac, con `webview_all`, el orquestador vio la página pintada en una captura de pantalla externa a los 12 s (buscador y lista de tabs, texto nítido) y el informe da `visibilityState` visible, `rafTicksIn2s` 145. Sin verificar: `wv_flutter` en el Mac y las dos en Windows. Los PNG del Mac de la prueba 4 son capturas internas (mismo tamaño en visible y oculto) y no prueban nada. (2) `--user-data-dir` **no se aplicó en ninguna de las dos** (`userDataDirApplied: false` en todos los informes): `wv_all` escribe en `%LOCALAPPDATA%\webview_all_windows\wv_all\EBWebView`; en `wv_flutter`, `initializeEnvironment` falla con `environment_already_initialized` (llamada tardía o repetida del probe). Arreglo del probe en curso (WebView visible hasta salir con prueba de pintado propia; carpeta de datos una vez por proceso antes del primer controlador; en `wv_all` vía `webview_all_windows.ensureEnvironment`). Arreglado en `679122a` (una vez por proceso, antes del primer controlador; `wv_all` vía `webview_all_windows.ensureEnvironment`, dependencia directa); sin probar en Windows. `shimVia` salía `null` por doble decodificación; arreglado, sin probar en Windows.
- **Sin explicar (pasada inicial):** `jsAlive=false` de `wv_all` en los modos ocultos; picos de arranque de `wv_flutter`. Lo que figuraba como sin medir (fps en pantalla, 150 %, arranque frío/caliente, ficheros escapados, `shimVia`) se midió después: ver abajo.
- **Decisión de Jorge (23/11/2026, noche): paquete `webview_all` (1.5.2) en Mac y Windows.** Motivo: misma API en las dos plataformas; `webview_flutter` en Windows es un fork con API propia.
- Arreglos de `679122a` verificados en Windows (tag `fix`, 100 %): Songsterr visible pintado en las dos (capturas al segundo 14 vistas por el orquestador: `wv_all` tab de Stairway to Heaven con texto nítido; `wv_flutter` buscador y aviso de cookies sobre la tab); `visibilityState` visible, `rafTicksIn2s` 118 · 121; HTML 299 kB en 3,6 s · 298 kB en 6,3 s; `userDataDirApplied` true en las dos, 0 carpetas nuevas bajo AppData; `shimVia` en `tab`: `window.tf` · `chrome.webview` (en `songsterr` sale `null` porque ese caso no carga el shim). Los «ficheros escapados» que lista el paso son `CryptnetUrlCache` de Windows y cachés de VS Code, ajenos a la app (comprobado en la pasada `fix`; no revisado en las pasadas `cold2`/`warm`/`cold3`: 1, 3 y 5).
- Arranque de `wv_all` (`controllerCreated` / `pageFinished`, ms), perfil borrado: 1908/2336 (songsterr), **25283/35346** (tab-fix), 1784/2182, 753/864, y a 150 % 627/920, 636/1282, 619/679, 632/714, 729/1041, 689/1795, 622/987, **22200/23074** (overlay); perfil conservado: 607/721 y 564/675. **Sin explicar:** dos arranques de 22-25 s de unos 15 con perfil recién borrado; ninguno con perfil conservado (2 casos). Riesgo abierto: primer arranque tras instalar.
- Fps real en pantalla (caso nuevo `fpsbar`: barra blanca que avanza por `requestAnimationFrame`; `pc.sh wvfps <app> [--seconds 30] [--tag s]`, detector `win/tear.ps1 -Series -TopLogical`, tabla `pc-wvfps-table.py`; commit `f66c084`; informes `Temp/p9-flutter/pc/wvfps-*`). 30 s por pasada, 100 %. Tabla (pasada · carga previa · capturas (por s) · distintos/s media / mín en 1 s · distintos/capturas · mayor parón ms · partidas · rafFps):
  - wv_all 1 · 5 % · 1793 (59,7) · 43,05 / 40 · 0,72 · 68 · 3 (0,17 %) · 60,0
  - wv_flutter 1 · 5 % · 1738 (57,9) · 39,66 / 20 · 0,68 · 515 · 3 (0,17 %) · 60,0
  - wv_all 2 (no limpia) · 19 % · 1790 (59,7) · 35,47 / 31 · 0,59 · 68 · 3 (0,17 %) · 60,0
  - wv_flutter 2 · 10 % · 1794 (59,8) · 45,95 / 36 · 0,77 · 67 · 4 (0,22 %) · 60,0
  - Sin umbral fijado; no separa a las candidatas. Son cotas inferiores: el detector muestrea a ~60/s sin sincronizar con la página y no se separa muestreo de fotogramas que no llegan. Control del detector (`pc.sh tear --kind pixel --size 720 --seconds 30 --series --tag ctl`): 1789 capturas, 29,87 distintos/s, 0 partidas; la fuente solo da ~30 fps, no demuestra que el detector vea 60; salió con código 1 sin investigar. Sin explicar: parón de 515 ms de `wv_flutter` (1 de 2) y las 3-4 capturas partidas por pasada (iguales en las dos; no se sabe si son del WebView o de la captura de pantalla). Capturas vistas por el orquestador: barra nítida, sin franjas.
- Escala 150 % (`devicePixelRatio` 1,5), solo `wv_all`, tag `s150` (commit `77b7429`, `P9_SHOT=<s>` para retrasar la captura): `tab` pasa (carga→render 356-436 ms; partitura pintada y nítida en captura al segundo 10, vista por el orquestador); `songsterr` pasa (298 kB en 5,8 s, pintada y nítida); `resize` 800/560/400/800 y repintado en los 4 pasos; `capture` rafFps 59,9, 1126/1126 sin pérdidas ni duplicados, latencia mediana 0,36 / p99 0,52 ms; `keys` modo `flutter` pasa (Flutter sin pérdidas ni duplicados, campo «hola», sin tormenta); `keys` modo `raw` como a 100 % (cada tecla llega solo al lado con foco, sin duplicados); `overlay`: informe `ok` y **visto bien por Jorge a ojo** (las capturas salieron antes del pintado o durante el cambio de escala: no valen). Fps en pantalla: 46,66 / mín 24, parón 246 ms (carga 21 %) y 40,76 / mín 33, parón 70 ms (carga 21 %).
  - **Sin medir / sin explicar a 150 %:** el detector marca el 100 % de las capturas como partidas (1608/1608 y 1749/1749): fallo del detector a esa escala (la captura mirada tiene la barra entera), sin depurar; no hay dato de desgarro a 150 %. Primer pintado más lento: a los 2 s `tab` dice «hecho» con la pantalla vacía (a 100 % a los 2 s ya está pintada); sin medir cuánto tarda.

#### 7h · Vídeo en Windows — PASA EL NATIVO (Media Foundation, vsync 2); `fvp` DESCARTADO

- Jorge (23/11): medir `fvp` en Windows aunque prefiere el nativo. `Probes/P9-flutter/video/vp_fvp`: reloj externo por shim C++ en el runner (`windows/runner/tf_sync.cpp`: `tf_sync_set`, `tf_sync_cb` = `double(void*)`, reloj QPC, seqlock), `--decoders "MFT:d3d=11,D3D11,DXVA,CUDA,FFmpeg"`, informe con decodificador activo, repetidos/saltados y vigilante.
- Paso `pc.sh video [caso|all|build] [--rebuild] [--decoders ..] [--tag s] [--env "A=1;B=2"]`, `win/video.ps1`, `pc-video-table.py`; commit `f66c084`. `--rebuild` no sincroniza: antes `pc.sh sync`. `vp_fvp` compiló en el PC a la primera (99 s), sin parche; `DynamicLibrary.process()` encuentra los `__declspec(dllexport)` del `.exe`.
- **mdk no llama nunca a `tf_sync_cb` en Windows** (`syncStats.calls = 0`) con D3D11 y con `--decoders FFmpeg`; reproduce con su reloj a 1x. Medidas (no valen como sincronía), `code-hevc.mov`: 100 % mediana 14,3 / p95 28,8 / máx 32,5 ms (D3D11, CPU 5,7 %, vigilante 12,5 ms, carga previa 29 %), con FFmpeg mediana 12,5 / p95 29,1; 70 % mediana −1816 ms; 50 % −5577 ms. Incumple p95 ≤ 16,7 ms a 100 %.
- Descartado del lado propio: `VP_SELFTEST=1` (traza en `lib/clock.dart`) llama a `tf_sync_cb` desde Dart por el mismo puntero y da `calls = 1`; `onSync` apunta dentro de `mdk.dll`; probado registrar al abrir y al reproducir (`VP_ATTACH=play`), `minInterval` 0 y 10. Hipótesis sin comprobar: mdk 0.40.1 ignora `onSync` en Windows sin otra opción de reloj; struct `mdkSyncCallback` de 16 bytes mal pasado por valor en Win64; `mdk.dll` distinta de los bindings de fvp 0.40.0.
- Rotación con fvp en Windows: `take-hevc-rot90.mov` 270°, textura 1080×1920, D3D11, vigilante 19,3 ms; `take-h264-rot90.mp4` 270°, 1080×1920, MFT, vigilante 28,6 ms. Capturas `Temp/p9-flutter/pc/vid-fvp-rot-{hevc,h264}.png` vistas por el orquestador: misma orientación que la del nativo en el Mac.
- Sin medir: H.264, salto y bucle con fvp en Windows. Sin explicar: por qué la tira de código del banco aparece sobre una toma real en una foto de Jorge (el banco solo la dibuja en `steady`/`seek`/`loop`, que usan `code-*`).
- **Decisión de Jorge (23/11/2026, noche): `fvp` descartado** (ya incumplía en el Mac con el reloj funcionando). Motor de vídeo = nativo en las dos plataformas. Pendiente antes de cerrar P9: prueba mínima del nativo de Windows (Media Foundation, esclavo de reloj externo → textura): error A/V ≤ medio fotograma, recuperación tras salto < 300 ms, rotación.
- **Mano de obra de esa prueba (Jorge, 23/11/2026):** si hace falta, se sube a Opus (`tf-engineer`) solo para el reproductor nativo de Windows; excepción a la decisión 21 de ADR-021 acotada a esta prueba. Primero se intenta con `tf-implementer` y encargo acotado.
- Reproductor nativo: `Probes/P9-flutter/AppCoreFFI/Sources/CAppCoreFFI/tf_mfvideo.c` (source reader con decodificación D3D11, reloj externo, subida a anillo de texturas con espera a la GPU). Paso `pc.sh video <caso> --engine native [--tag s] [--env "TF_P9_VSYNC=0|1|2"]`; casos nuevos con GOP de 1 s (`steady|seek|loop-h264g30`, fichero `code-h264-g30.mp4`; `code-h264.mp4` tiene GOP de 250). Commits `ddea60b` a `02028e4`. Variables: `TF_P9_VSYNC` 0 = control (último fotograma cuyo PTS cubre la posición actual); 1 (por defecto) = visible en el próximo vblank de DWM + `TF_P9_VLEAD_MS` (un periodo por defecto); 2 = vblank siguiente a la próxima copia del motor (fase medida); `TF_P9_SEEKAIM_MS` (250 por defecto); `TF_P9_VSW=1` = decodificación por software.
- **HEVC no abre en el PC x64:** `videoOpen state=2`, `SetCurrentMediaType(ARGB32/RGB32) hr=0xC00D5212` (`MF_E_TOPO_CODEC_NOT_FOUND`: no están instaladas las HEVC Video Extensions). H.264 abre con decodificación por hardware (MF no da nombre del decodificador). `fvp` sí reproducía HEVC porque decodifica sin pasar por MF. Consecuencia (acordado con la sesión de la 7c, 24/11): en Windows Flutter recibe solo H.264 y el núcleo convierte HEVC→H.264 con `VideoConversion` (GOP de 1 s: `-g 30 -bf 0`); el visor sigue pidiendo la conversión.
- Tanda del 23/11 (commit `5aa48ec`, H.264 GOP 250; error A/V mediana/p95/máx en ms a 1,0x): control `vs0` 13,55 / 17,54 / 18,3 (incumple p95 ≤ 16,7) y repetición 10,09 / 14,21 / 24,6; vsync 1 (`vs1`) −1,08 / 3,1 / 3,96 y repetición −9,66 / 3,38 / 4,38; vsync 2 (`vs2`) 4,98 / 8,99 / 11,94. Salto con GOP 250: recuperación estable de 350 a 900 ms (y una de 2499 ms), incumple < 300 ms. Bucle en control: 14,93 / 17,71 (incumple); con vsync 1, −6,98 / −5,08.
- Tanda del 24/11 (commit `02028e4`, tag `v2a`/`v2c`; carga previa 0-7 % salvo bucle 31 %): steady H.264 vsync 1: 1,0x −13,99 / 2,66 / 3,89, 0,7x −9,67 / −4,57 / −3,59, 0,5x −6,96 / −1,17 / −0,84, 0 repetidos y 0 saltados, CPU 1,1 %. vsync 2: 1,0x −2,56 / 12,87 / 13,65, 0,7x −2,95 / 2,52 / 3,21, 0,5x −1,96 / 0,05 / 0,26. Pasan los dos (|error| ≤ medio fotograma). Sin explicar: la mediana de −14 ms (adelantado) de vsync 1 a 1,0x.
- Salto con GOP de 1 s (`seek-h264g30-v2a`; destino s · primer acierto ms · estable ms): 20 · 210 · **1054**; 8 · 166 · 230; 0 · 95 · 95; 25 · 293 · 293; 2 · 107 · 107; 28,064 · 523 · **523**. 4 de 6 por debajo de 300 ms. Con GOP 250 (`seek-h264-v2a`): 867, 494, 225, 89, 488 y 953 ms (2 de 6). En el salto a 20 s el núcleo publica el primer fotograma correcto a 38,7 ms (`seekLog.firstOkPub`) sin descartes tardíos; el lado Dart da el primer acierto a 210 ms. Traza añadida en `48c42ab` (`badTrace`, `badTotal`, `unreadable` por salto).
- Bucle con GOP de 1 s (`loop-h264g30-v2a`): pasa, error en bucle −6,06 / −4,6 / −4,1 ms.
- Rotación (`take-h264-rot90.mp4`): MF ya entrega la textura girada (`mfRotation` 270, `alreadyRotatedByMF` true, 1080×1920) y el probe no aplica giro (`quarterTurns` 0). **Sin verificar a ojo:** las capturas de los casos nativos no muestran el vídeo (steady: escritorio con un terminal delante; rotación: ventana en blanco; todas las PNG nativas pesan ~5 KB, también las del 23/11). `shot.ps1` trae ahora la ventana al frente (`48c42ab`); ver tanda v3.
- Tanda v3 (24/11, `48c42ab`, carga previa baja). Salto con GOP 1 s (destino s · primer acierto = estable, ms): 20 · 45,6; 8 · **344**; 0 · 60; 25 · 59; 2 · 58; 28,064 · 90. 5 de 6 por debajo de 300 ms. El de 8 s lo causa el decodificador: tarda 307 ms en dar la primera muestra tras `SetCurrentPosition` (13 descartes tardíos). Los de 1054 y 523 ms de v2a no se repiten: hay mucha varianza entre pasadas y hacen falta repeticiones. 0 lecturas fallidas. En el salto a 2 s, la primera muestra (9 ms) aún enseña un fotograma viejo (27,5 s). Error contra vblank en vsync 1 sistemáticamente negativo (fotograma adelantado): medianas de −4,8 a −14,9 ms, p05 de hasta −16,04 ms (salto a 25 s), al borde del medio fotograma; con vsync 2 la mediana de steady era −2,6 ms. **Pantalla:** con la ventana al frente, las capturas de `steady-h264-v3` (12 s) y `rot-h264-v3` (4 s) salen en blanco a pantalla completa, sin vídeo, aunque el núcleo lee bien la tira de código de la textura (readback). El vídeo nativo de Windows no se ha visto aún en pantalla; se investiga. La HEVC con GOP de 1 s de `VideoConversion` (`-g 30 -bf 0`) queda en línea con estos saltos (informado a la sesión de la 7c).
- Tanda v4 (24/11, `a1f9c27`: `shot.ps1` con `PrintWindow` `PW_RENDERFULLCONTENT`, estado de ventanas en `<tag>.info.txt`, fondo magenta detrás del `Texture`). `steady-h264-v4`: la ventana delante es la correcta (`tf_probe`, clase `FLUTTER_RUNNER_WIN32_WINDOW`, cliente 804×581, visible, no minimizada), pero **su cliente sale blanco, sin el magenta**: Flutter no presenta nada, aunque el núcleo sigue leyendo bien la tira de código de la textura. **La pantalla de 800×600 era la del PC sin monitor conectado**; con monitor (Jorge, 24/11: 1920×1080 a 60 Hz, no el de 144 Hz) Flutter presenta y el vídeo se ve. Los 60 Hz de los informes (`refreshMs` 16,667; uno 16,683) son reales para ese monitor. Las cifras de v2a-v4 se tomaron sin monitor (pantalla de 800×600); valen como referencia, no para decidir.
- Tanda v5 (24/11, monitor 1920×1080 a 60 Hz). **Vídeo visto en pantalla** (`PrintWindow` de `steady-h264-v5` y `rot-h264-v5`, mirados por el orquestador): toma con la tira de código; la rotación sale vertical con la misma orientación que la referencia del Mac (`vid-fvp-rot-h264.png`). MF entrega la textura ya girada (`alreadyRotatedByMF`) y el probe no gira (`quarterTurns` 0): **rotación pasa**.
- Steady H.264 con monitor (error mediana / p95 / mín ms a 1,0x; p95 a 0,7x y 0,5x): vsync 1 (antes por defecto) −21,25 / −16,91 / −25,86, **incumple** (cada fotograma ~1 vblank adelantado); vsync 2 0,18 / 6,15 / −28,48, p95 2,69 y 2,67, **pasa**; vsync 1 con `TF_P9_VLEAD_MS=0` −5,93 / 10,99 / máx 25,53, p95 12,19 y 5,69. El mínimo de −28 ms de vsync 2 son muestras sueltas (sin p05 en el informe para cuantificar la cola).
- Salto con GOP 1 s y monitor, vsync 1 (`v5`): 20 s estable a 878 ms por un único fotograma tardío (+22 ms contra vblank) 827 ms después del salto; 2 s sin estabilizarse por tres muestras a −16,8 ms 2,4 s después (el adelanto de vsync 1); el resto 45-97 ms. Con vsync 2 (`v5m2`): **6 de 6 por debajo de 300 ms** (72,7; 37,7; 54,0; 53,4; 234,9; 66,3); el de 235 ms es el decodificador (primera muestra a 202 ms). En varios saltos la primera muestra (0-11 ms) aún muestra el fotograma anterior al salto.
- Bucle con GOP 1 s y vsync 2 (`v5m2`): vueltas 0-34 ms, error en bucle −9,08 / −5,21 ms (mín −20,57): **pasa**.
- Cambios (`bf58c5b`): `TF_P9_VSYNC` por defecto = 2; `pc-video-table.py` juzga |mediana|, |p95| y |p05| (antes solo el lado positivo, y un −21 ms pasaba); `probe5_measure.dart` añade `p05` a `e_ms`.
- **Decisión de Jorge (24/11/2026): 7h cerrada con las medidas de la tanda v5** (monitor 1920×1080 a 60 Hz, vsync 2: steady mediana 0,18 / p95 6,15 ms; salto 6 de 6 por debajo de 300 ms; bucle −9,08 / −5,21 ms; rotación vista). La pasada de confirmación con vsync 2 por defecto y p05 (`bf58c5b`) se cortó antes de medir y no se repite. Abierto: cola de muestras sueltas adelantadas en vsync 2 (mín −28 ms), sin p05 medido; sin probar a 144 Hz. HEVC: MF no lo abre en el PC; en Windows el núcleo convierte a H.264 (`VideoConversion`, GOP de 1 s).
