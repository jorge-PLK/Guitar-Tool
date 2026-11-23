# P9 · Viabilidad de la interfaz Flutter

**Estado: en ejecución (23/11/2026). Pruebas 1, 2, 3 y 6 (Mac) pasadas; prueba 4 (Mac) cerrada en lo medible: `keys` medido el 23/11, las dos candidatas incumplen con el WebView enfocado (fallo abierto de Flutter, flutter/flutter#184557) y las dos cumplen con el diseño «WebView sin foco»; elección de paquete pendiente de Windows; prueba 5 medida en el Mac: gana el reproductor nativo (provisional, falta Windows); en el PC x64 pasan 7b y 7e, 7d está decidido (vía 1) y la textura externa funciona con Impeller en los dos caminos y está medida (0-3 descartes por minuto en `gpu` y `pixel`; umbral de 0 pendiente de decisión de Jorge). Pendiente: resto de la 7 (WebView, vídeo, `listener` contra puerto con el PC quieto, RSS largo de vía 1, STA tras Media Foundation).** Primera parte de la Fase 7f. Decide si se mantienen las decisiones marcadas (P9) en [ADR-021](../adr/ADR-021.md). Código en `Probes/P9-flutter/` (fuera de la puerta de tests); resultados, en este fichero, debajo de cada prueba.

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

### Prueba 7 · PC x64 — primera pasada, en curso

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

- **Pendiente en el resto de la 7:** `listener` contra puerto con el PC quieto, RSS de vía 1 en ejecución larga, STA tras Media Foundation.

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

#### 7f · Textura externa con Impeller — FUNCIONAN LOS DOS CAMINOS; 0-3 DESCARTES POR MINUTO EN AMBOS (umbral de 0: pregunta a Jorge)

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
- **Pendiente de Jorge:** si se acepta un umbral de ≤ 3 descartes por minuto en Windows (latest-wins) y se queda `GpuSurfaceTexture`, o se exige 0.
- Copia BGRA en Windows: funciona (10 s a 720p: 271 / 271, 0 descartes, CPU 1,736 %).
- **Juicio visual del orquestador** (capturas de pantalla con `CopyFromScreen`, `Temp/p9-flutter/pc/p3-solid-gpu.png`, `p3-solid-pixel.png`, `p3-gpu-720.png`): orden de canales correcto en los dos caminos (fondo rojo puro, cuadrado azul arriba a la izquierda, sin volteo vertical ni horizontal); en `gpu` 720 la barra blanca tiene bordes nítidos, sin franjas ni fotograma a medias. Una captura suelta no descarta el desgarro. Sin mirar: `p3-pixel-720.png` y las capturas de la segunda tanda.
- El build de `AppCoreFFI.dll` con el código de la prueba 5 sigue compilando en Windows (26 exportaciones antes de esta parte; `VideoProbe.swift` va bajo `canImport(AVFoundation)`).
