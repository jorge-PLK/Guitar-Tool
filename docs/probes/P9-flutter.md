# P9 · Viabilidad de la interfaz Flutter

**Estado: en ejecución (22/11/2026). Pruebas 1, 2, 3 y 6 (Mac) pasadas; en el PC x64 pasan 7b y 7e y 7d está decidido (vía 1); pendientes 4, 5 y el resto de la 7.** Primera parte de la Fase 7f. Decide si se mantienen las decisiones marcadas (P9) en [ADR-021](../adr/ADR-021.md). Código en `Probes/P9-flutter/` (fuera de la puerta de tests); resultados, en este fichero, debajo de cada prueba.

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
