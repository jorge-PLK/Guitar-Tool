# Fase 7f · Arquitectura de la interfaz Flutter

Decisiones en [ADR-021](../adr/ADR-021.md). Este fichero dice **cómo** se construye; qué se construye en cada pantalla está en `pantallas/`.

## Regla de oro

- **Comportamiento = `Packages/AppCore`.** Flutter solo habla con el puente (`Bridge`/`Router`). No hay lógica de negocio en Dart: un store refleja el estado que publica el núcleo y envía intenciones.
- **Aspecto = `App/Sources` (SwiftUI).** Tokens de `Theme.swift`, medidas y composición de cada vista. Su lógica (`AppModel`, controladores) no se porta ni se consulta como fuente de comportamiento.
- `WinApp/Web` sirve de ejemplo de **cómo se usa cada método del puente** (qué llama, en qué orden, qué eventos escucha). No es referencia visual.
- Si SwiftUI hace algo que `AppCore` no ofrece: es un desvío, va a [desvios.md](desvios.md) y se trata según su regla.

## Piezas

```
FlutterApp (Dart, un solo código Mac + Windows)
  features/<área>  pantalla + store Riverpod
  core/            CoreClient · FrameChannel · HostServices · MockCore
        │ dart:ffi  (JSON UTF-8) + texturas externas (fotogramas)
AppCoreFFI (biblioteca dinámica: .dylib en Mac, .dll en Windows)
  ABI C sobre Bridge de AppCore; mismo proceso que Flutter
        │
AppCore → Store, AudioKit, VideoKit, StudyKit, TabKit, StemKit, SourceKit, ModelKit, NativeKit
```

Un proceso. Los helpers (yt-dlp, ffmpeg, Deno, `tf-separate`) siguen siendo procesos hijos del núcleo.

## AppCoreFFI (Swift)

Producto nuevo `AppCoreFFI` (`type: .dynamic`) en `Packages/AppCore`, objetivo `Sources/AppCoreFFI/` (Swift, `@_cdecl`) más un objetivo C `CAppCoreFFI` con la cabecera `tf_core.h` (API DL de Dart y envío por puerto). Solo traduce; no añade comportamiento. Base: `Probes/P9-flutter/AppCoreFFI`, sin los `tf_debug_*`.

**ABI congelada al cerrar P9 (24/11/2026).** Cambiarla (añadir, quitar o cambiar una firma) es una pregunta a Jorge. Exportación: `TF_API` = `__declspec(dllexport)` en Windows (siempre, también al compilar la propia DLL) y `visibility("default")` en Mac.

| Función C | Quién la llama | Qué hace |
| --- | --- | --- |
| `intptr_t tf_core_init_dart_api(void *data)` | Dart, una vez, antes de `tf_core_start` | `Dart_InitializeApiDL(NativeApi.initializeApiDLData)`. 0 = bien. |
| `void tf_core_set_texture_host(const tf_texture_host *host)` | Runner, antes de que arranque Dart | Registra la tabla de texturas del runner; nulo = sin texturas (respaldo BGRA y tests). |
| `int32_t tf_core_start(const char *optionsJSON, int64_t port)` | Dart, una vez | `optionsJSON` = `{"args":[...]}` (argumentos de `LaunchOptions`). Crea el `Bridge` y fija como sumidero el puerto nativo de Dart. `AppCoreFFI` asigna `send` y `host` **antes** de `Bridge.start()` (en `WinApp` `send` se asigna después: hueco 4 de `contrato-anfitrion-hilos.md`). 0 bien; 1 ya arrancado; 2 opciones inválidas; 3 falló `Bridge.init`. |
| `void tf_core_send(const uint8_t *utf8, int32_t len)` | Dart | Entrega `{id, method, params}` o `{hostResponse}` a `Bridge.receive`. No bloquea; copia los bytes antes de volver (el búfer es de Dart). `Bridge` y `Router` no son `@MainActor` y `send` no reencola: el reencolado es trabajo de `AppCoreFFI`. |
| `void tf_core_free(const uint8_t *ptr)` | Finalizador del `Uint8List` externo | Libera un búfer que el núcleo entregó por el puerto. |
| `void tf_core_shutdown(int32_t timeoutMs)` | Dart | **Asíncrono**: vuelve enseguida; al acabar `shutdownAsync`, o al vencer el tope (que cubre el cierre entero, no solo `jobs.shutdown()`), emite `{event: "core.shutdown", payload: {clean}}` y Dart cierra la ventana. No puede ser síncrono: en el Mac el hilo de Dart es el principal y `closeStudy` salta a `@MainActor`. |
| `void tf_core_run_main(void)` | Runner de Windows, hilo principal | Vía 1 de hilos (ver abajo): `dispatchMain()`, no vuelve. En Mac no se usa. No existen `tf_core_pump` ni `tf_core_main_queue_handle`. |
| `int64_t tf_texture_create(int32_t channel)` | Dart, hilo de plataforma | Pide al runner (`register_texture`) que registre la textura del canal; devuelve su id (`Texture.textureId`) o −1 sin tabla. El tamaño lo lleva cada fotograma. |
| `void tf_texture_dispose(int32_t channel)` | Dart, hilo de plataforma | `unregister_texture` y, en Windows, libera las texturas D3D11 del canal. |
| `void *tf_frame_copy(int32_t channel)` | Textura del runner, al pintar (cualquier hilo) | Último fotograma del canal o nulo. Mac: `CVPixelBufferRef` retenido (+1, lo suelta Flutter). Windows: HANDLE DXGI compartido (`kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`) de la textura publicada del anillo. |

```c
typedef struct {
  int64_t (*register_texture)(int32_t channel);   // hilo de plataforma
  void (*frame_available)(int64_t id);            // cualquier hilo; el runner reencola si hace falta
  void (*unregister_texture)(int64_t id);         // hilo de plataforma
} tf_texture_host;

#define TF_CHANNEL_CAMERA  0   // Grabar y vista previa de Ajustes · Vídeo
#define TF_CHANNEL_MONTAGE 1   // vista previa de Montaje
#define TF_CHANNEL_TAKE    2   // vídeo de la toma (Ver toma), reproductor nativo
```

Texturas, por qué una tabla y no el registro de Flutter: si `AppCoreFFI` recibiera el registro tendría que enlazar `FlutterMacOS.framework` y `flutter_windows.dll`; con la tabla el paquete Swift no depende del motor y una subida de Flutter no toca el núcleo. Coste: una clase de textura pequeña en cada runner (Swift en Mac, C++ en Windows) que llama a `tf_frame_copy`. Medido en P9 (pruebas 3 y 7f).

Mensajes del núcleo a Dart (cualquier hilo):

- **Puerto nativo** (decisión de Jorge, 23/11/2026): cada mensaje (respuesta `{id, result|error}`, evento `{event, payload}` o petición `{hostRequest: {id, method, params}}`) es un búfer UTF-8 sin terminador enviado con `Dart_PostCObject_DL` como `kExternalTypedData` (Uint8, sin copia), con `tf_core_free` de finalizador. Si el puerto no lo acepta, el núcleo lo libera. Orden garantizado. Medido (P9 2 y 7d): ida y vuelta mediana 0,18-0,19 ms, p99 0,30-0,33 ms en Windows; `NativeCallable.listener` empataba en latencia pero su orden no está documentado.
- Dart decodifica con `utf8.decoder.fuse(json.decoder)`. Sin isolate auxiliar ni canal binario.
- Los fotogramas no pasan por mensajes: el núcleo los entrega a la textura (ver «Canal de fotogramas»).

Hilos:

- En Flutter ≥ 3.35 el hilo de plataforma y el de UI de Dart son el mismo. En Mac es el hilo principal del proceso, así que lo `@MainActor` de `AppCore` puede correr ahí. **En Windows, decisión cerrada (P9, 22/11/2026): vía 1.** El `wWinMain` del runner crea la ventana y el motor en un hilo propio STA y el hilo principal queda en `tf_core_run_main()`, como ya hace `WinApp`; medido en `docs/probes/P9-flutter.md` (7d). La vía 2 (`tf_core_pump` sobre símbolos privados `_4CF` de libdispatch) se descarta por frágil ante cambios de toolchain, y el proceso núcleo aparte ya no hace falta.
- Regla heredada de la 7c (spec): el hilo de UI queda en STA **antes** de crear el `Bridge` y nada nativo de audio o vídeo síncrono corre en él. El runner de Windows de Flutter ya hace `CoInitializeEx(APARTMENTTHREADED)`; medido en P9 (7d): sigue en STA tras iniciar Media Foundation.
- Ninguna llamada FFI puede bloquear el hilo principal más de un fotograma (16 ms). Lo largo es un trabajo (`jobs.*`) o un evento.

Servicios de anfitrión (`HostServices` de `AppCore`: diálogos, abrir URL, mostrar en Finder/Explorador, vista previa y carga oculta de Songsterr): `AppCoreFFI` los implementa reenviando `{hostRequest}` a Dart, que responde con `{hostResponse: {id, result|error}}` usando plugins de Flutter. Los métodos `host.*` del puente no cambian.

Ficheros de proyecto (audio, vídeo, fotos): Flutter los abre por ruta de fichero. No hay host virtual `media.toneforge`.

## Canal de fotogramas

Sustituye en Flutter a `frames.<canal>` en JPEG (ADR-021, decisión 8). Canales: `camera` (Grabar y la vista previa de Ajustes · Vídeo, que la reutiliza) y `montage` (vista previa de Montaje). El núcleo entrega cada fotograma al registro de texturas de Flutter y Dart lo pinta con el widget `Texture`; no hay copia de píxeles a Dart.

- Mac: `FlutterTexture.copyPixelBuffer` con `CVPixelBuffer` (32BGRA o NV12). `textureFrameAvailable` y el registro, solo desde el hilo de plataforma.
- Windows: `GpuSurfaceTexture` con textura D3D11 compartida (aviso desde cualquier hilo); respaldo `PixelBufferTexture`. Riesgo: Impeller es el motor por defecto desde 3.47 y hay un fallo reportado «Could not create external texture» (jakky1/video_player_win#54). Medido en P9 (7f, 23/11/2026): funciona con Impeller; no apareció el fallo. Umbral en Windows: ≤ 3 descartes por minuto (Jorge, 23/11/2026). La textura compartida va en anillo de 3 y el handle se publica solo cuando la GPU confirma la subida (`D3D11_QUERY_EVENT`): sin esa espera, 2-10 % de fotogramas partidos; con ella, 0 a 720p y 1080p, 2-4 ms de espera en el hilo productor (P9 7f, 23/11/2026; decisión de Jorge).
- Respaldo de toda la decisión: copia BGRA por FFI y `ui.decodeImageFromPixels` en un `RawImage`, con confirmación por fotograma (el último gana, como `FrameRelay.latestWins`). En Windows no sirve: 120 descartes por minuto a 1080p y 71 a 720p (P9 7f).

Resolución y fps por canal los decide el núcleo: `camera` y `montage` a 720p30 o 1080p30 (las dos medidas en P9), «el último gana»; umbral de descartes 0 en Mac y ≤ 3 por minuto en Windows. `take` va a la resolución y fps del fichero. `FrameRelay` en JPEG se conserva en `AppCore` mientras existan las UIs viejas y se borra con ellas.

## Estructura de `FlutterApp/`

Versiones fijadas en P9: Flutter **3.50.1** por FVM (`.fvmrc` en la raíz; el Dart que trae fija `sdk:` en `pubspec.yaml`); `webview_all` **1.5.2** y `webview_all_windows` **1.5.2** (dependencia directa: `ensureEnvironment` para la carpeta de datos). Sin plugin de vídeo. El resto de plugins permitidos (regla 9) se fija con versión exacta, sin `^`, al crear `pubspec.yaml` en la ola 0, con la última estable que resuelva con Flutter 3.50.1, y `pubspec.lock` se versiona. Subir Flutter o un plugin es una pregunta a Jorge.

```
FlutterApp/
  pubspec.yaml            versiones exactas; pubspec.lock versionado
  analysis_options.yaml   flutter_lints + reglas estrictas (sin dynamic implícito)
  l10n.yaml
  lib/
    main.dart             argumentos de arranque → LaunchOptions → ProviderScope
    app.dart              MaterialApp, tema, idioma, carcasa
    core/                 ffi_bindings.dart, core_client.dart, frame_channel.dart,
                          host_services.dart, mock_core.dart, launch_options.dart
    contract/<área>.dart  DTO a mano (fromJson/toJson), uno por área del puente
    theme/                tokens.dart, typography.dart, tf_theme.dart
    widgets/              kit compartido (ver tokens-componentes.md)
    features/<área>/      <área>_store.dart, <área>_screen.dart, widgets/, sheets/
    l10n/                 app_es.arb (plantilla), app_en.arb
  test/
    contract/             cada DTO decodifica sus fixtures
    features/<área>/      stores con MockCore, widgets, goldens
  integration_test/       app real contra AppCore con carpeta de proyectos de prueba
  macos/  windows/        runners; solo cableado de build y argumentos
Contract/fixtures/<área>/ JSON dorado: <método>.params.json, <método>.result.json, <evento>.event.json
```

Áreas = prefijos del puente: `library`, `import` (+ `link`, `playlist`), `study`, `tab`, `record`, `takeview`, `montage`, `audio`, `video`, `settings` (+ `models`, `tools`), `jobs`, `host`, `app`.

## Reglas de Dart (las llevan los agentes `tf-flutter` y `tf-flutter-mech`)

1. **Sin generación de código** salvo `gen-l10n`: nada de `build_runner`, `freezed`, `json_serializable` ni `riverpod_generator`. DTO y providers a mano.
2. **Riverpod 3.x**: un `Notifier` por área. Estado inmutable. El store se suscribe a los eventos `*.state` de su área y expone métodos que llaman a `CoreClient.call`. Ningún widget llama al puente.
3. **`CoreClient`** es la única puerta: `Future<T> call<T>(String method, Object? params, T Function(Json) decode)` y `Stream<T> on<T>(String event, …)`. Límite por llamada: 15 s por defecto, como `bridge.js`; las excepciones viven en una sola tabla por método (`core/call_timeouts.dart`), nunca en el sitio de la llamada. Valores de `WinApp/Web`: `link.classify` 3 s; hoja de Songsterr (`tab.songsterr.*`) 10 s; `link.search` y hoja de lista 30 s; `audio.calibrate` 60 s; `link.resolve` y `link.addManual` 120 s (`link.resolve` de una lista, 300 s); `tools.updateYtDlp` 200 s; `tab.export` 10 min; `import.file` y `library.relocate` 60 min. Las que esperan a un diálogo del usuario (`host.pickAudioFile(s)`, `host.chooseFolder`, `host.pickProjectsFolder`) van **sin límite**: el diálogo es de Dart y siempre termina (la web ponía 10 min y perdía la elección si se tardaba más). Una respuesta que llega tras vencer el límite se descarta. En tests se sustituye por `MockCore`, que responde con los fixtures.
4. **Tokens, nunca literales**: ningún color, tipografía, radio ni espaciado fuera de `theme/`. Los hex sueltos que tiene SwiftUI fuera de `TF` se convierten en tokens con nombre.
5. **Textos, nunca literales**: todo texto visible sale de `AppLocalizations`. Clave = `<área>_<elemento>` en camelCase. Español copiado literal de SwiftUI; inglés traducido.
6. **Errores del núcleo**: `{code, message, args}`. Dart traduce por `code` (`error_<code>` en ARB) y cae a `message` si no conoce el código.
7. **Dibujo propio** con `CustomPainter` (rejilla de acordes, diagramas, medidores, líneas de tiempo); nada de paquetes de gráficos.
8. **Un fichero ≤ ~300 líneas.** Una pantalla grande se parte en `widgets/`.
9. **Plugins permitidos** (versión exacta en `pubspec.yaml`; añadir otro es una pregunta a Jorge): `flutter_riverpod`, `file_selector`, `url_launcher`, `path_provider`, `desktop_drop`, `window_manager`, `shared_preferences` (solo el idioma, con la API `SharedPreferencesAsync`). WebView: `webview_all` + `webview_all_windows` (P9); vídeo: ninguno (motor nativo en el núcleo). Los goldens usan `matchesGoldenFile` con fuentes reales y se generan solo en el Mac.

## WebView (Tablatura y Songsterr)

Widget propio `TfWebView` (`lib/widgets/tf_web_view.dart`) que oculta el paquete: **`webview_all` 1.5.2 en Mac y Windows** (decisión de Jorge, 23/11/2026: misma API en las dos; `webview_flutter_windows` es un fork con API propia). En Windows es captura a textura de WebView2, porque Flutter no tiene platform views (flutter#31713). Usos: alphaTab visible (carga `tab.html` + `tf-bridge.js` de los recursos, mensajes JS↔Dart reenviados a `tab.*`), carga oculta de Songsterr y su vista previa visible.

- **WebView sin foco de teclado** (P9 prueba 4): el foco de teclado se queda siempre en Flutter, que recibe las teclas de edición de la partitura (cómo llegan a alphaTab: ficha de Tablatura). Con el WebView enfocado se pierden o duplican teclas en el Mac (flutter/flutter#184557, abierto).
- Carpeta de datos de WebView2 una vez por proceso, antes del primer controlador (`webview_all_windows.ensureEnvironment`), bajo `--support-dir`.
- Abiertos de P9 (7g): arranque ocasional de 22-25 s con perfil nuevo (riesgo en el primer arranque tras instalar); primer pintado más lento a 150 %; sin dato de desgarro a 150 %.

## Vídeo de tomas

**Reproductor nativo en el núcleo** (ADR-021, decisión 9; cerrado en P9 pruebas 5 y 7h). `fvp`, `video_player` y `video_player_win` descartados. El audio suena en el núcleo; el vídeo va en silencio, esclavo del mismo reloj (`takeview.position {seconds, playing, at, epoch, rate}`), y se pinta por el canal `take` de la textura. Dart no controla el vídeo por FFI: solo los métodos `takeview.*` del puente y el widget `Texture`.

- Mac: `AVPlayer.setRate(_:time:atHostTime:)` + `AVPlayerItemVideoOutput` → `CVPixelBuffer`.
- Windows: `IMFSourceReader` con decodificación D3D11 (base `tf_mfvideo.c` del probe), subida al anillo de texturas con espera a la GPU, y **presentación al vblank siguiente a la próxima copia del motor** (modo 2 del probe). `IMFMediaEngine` no sirve: no admite reloj externo. MF entrega la textura ya girada: Dart no gira.
- HEVC: Media Foundation no la abre sin las HEVC Video Extensions; en Windows el núcleo convierte HEVC→H.264 con `VideoConversion` (GOP de 1 s, `-g 30 -bf 0`) y Flutter recibe solo H.264.
- Umbrales (los de P9): error A/V ≤ medio fotograma (|mediana| y |p95|) a 50, 70 y 100 %; recuperación tras salto < 300 ms; rotación correcta. Medido en Windows con monitor de 60 Hz: mediana 0,18 / p95 6,15 ms; salto 6 de 6 < 300 ms; bucle −9,08 / −5,21 ms. Abierto: muestras sueltas adelantadas (mín −28 ms) sin p05 medido; sin probar a 144 Hz.

## Arranque, capturas y desarrollo

- Argumentos como `AppCore.LaunchOptions` (`--projects-folder`, `--support-dir`, `--screen`, `--project`, `--snapshot`, `--snapshot-delay`, `--window`, `--audio`, `--camera`) más `--mock` (usa `MockCore`) y `--locale es|en`.
- `--snapshot <png>`: la app pinta la pantalla pedida, la vuelca con `RepaintBoundary.toImage` y sale. Se lanza sin robar foco (`open -g` en Mac).
- **Nunca probar con la carpeta real de proyectos**: siempre `--projects-folder` y `--support-dir` a una copia.
- Scripts (salida resumida, logs en `Temp/logs/`): `Tools/flutter/build-core.sh` (compila `AppCoreFFI` y lo deja donde el runner lo recoge), `Tools/flutter/run.sh` (arranca con argumentos y captura), `Tools/flutter/pc.sh` (pasa la rama al PC x64 por ssh, compila, prueba y trae capturas). `Tools/test.sh` gana el paso `FlutterApp`.

## Empaquetado

- **Mac**: `FlutterApp/macos` copia a `Runner.app` el `.dylib` de `AppCoreFFI` (`Contents/Frameworks`), `tf-separate`, helpers, modelos, alphaTab, SoundFont y fuentes (`Contents/Resources`, con los mismos nombres que busca hoy `Bundle.main`).
- **Windows**: junto al `.exe`, `AppCoreFFI.dll`, las DLL del runtime de Swift (`swiftCore`, `swiftCRT`, `swiftDispatch`, `swiftWinSDK`, Foundation), ONNX Runtime y DirectML, helpers y recursos.
- El instalador y el actualizador son fases posteriores (7d y la del instalador).
