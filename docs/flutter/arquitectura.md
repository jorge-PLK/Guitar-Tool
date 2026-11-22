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

Producto nuevo `AppCoreFFI` (`type: .dynamic`) en `Packages/AppCore`, objetivo `Sources/AppCoreFFI/`. Solo traduce; no añade comportamiento. ABI propuesta (se congela al cerrar P9):

| Función C | Qué hace |
| --- | --- |
| `int32_t tf_core_start(const char *optionsJSON, tf_message_cb onMessage, const tf_texture_host *textures)` | Crea el `Bridge` con `LaunchOptions` y registra el callback de mensajes. `textures` es una tabla de tres punteros a función C que implementa el runner (`register(channel) → int64_t id`, `frame_available(id)`, `unregister(id)`); nulo = sin texturas (respaldo BGRA y tests). `AppCoreFFI` asigna `send` y `host` **antes** de `Bridge.start()` (en `WinApp` `send` se asigna después: hueco 4 de `contrato-anfitrion-hilos.md`). Se llama una vez; la segunda devuelve error. Devuelve 0 o un código de error. |
| `void tf_core_send(const uint8_t *utf8, int32_t len)` | Entrega un mensaje `{id, method, params}` (o una respuesta de anfitrión) a `Bridge.receive`. No bloquea. El núcleo copia los bytes antes de volver: el búfer es de Dart. `Bridge` y `Router` no son `@MainActor` y `send` no reencola: el reencolado al hilo que haga falta es trabajo de `AppCoreFFI`. |
| `void tf_core_free(const uint8_t *ptr)` | Libera un búfer que el núcleo entregó por callback. Con `NativeCallable.listener`, Dart la llama tras decodificar, siempre (también si la decodificación falla); con puerto nativo la llama el finalizador. |
| `int64_t tf_texture_create(int32_t channel)` | Pide al runner, por la tabla, que registre la textura del canal y devuelve su id (`int64`, como `Texture.textureId`). El tamaño lo lleva cada fotograma. En Mac se llama desde el hilo de plataforma. |
| `void *tf_frame_copy(int32_t channel)` | La llama la textura del runner al pintar: último fotograma del canal, o nulo. Mac: `CVPixelBuffer` retenido (+1, lo suelta Flutter). Windows: HANDLE compartido de la textura D3D11. |
| `void tf_core_shutdown(int32_t timeoutMs)` | **Asíncrono**: vuelve enseguida; al acabar `shutdownAsync`, o al vencer el tope (que cubre el cierre entero, no solo `jobs.shutdown()`), emite `{event: "core.shutdown", payload: {clean}}` y Dart cierra la ventana. No puede ser síncrono: en el Mac el hilo de Dart es el principal y `closeStudy` salta a `@MainActor`. |
| `void tf_core_pump(void)` | Vía 2 de hilos en Windows (ver abajo): drena la cola principal de Swift desde el bucle del runner. Solo existe si la vía 1 falla en P9. |

Texturas, por qué una tabla y no el registro de Flutter: si `AppCoreFFI` recibiera el registro tendría que enlazar `FlutterMacOS.framework` y `flutter_windows.dll`; con la tabla el paquete Swift no depende del motor y una subida de Flutter no toca el núcleo. Coste: una clase de textura pequeña en cada runner (Swift en Mac, C++ en Windows) que llama a `tf_frame_copy`. Alternativa si P9 (prueba 3) la mide mejor: pasar el registro (`registrar(forPlugin:).textures` en Mac; `GetRegistrarForPlugin` en Windows, nulo hasta que arranca el motor) y registrar desde el núcleo.

Callback de mensajes (lo invoca el núcleo desde cualquier hilo):

- `tf_message_cb(const uint8_t *utf8, int32_t len)`: respuestas `{id, result|error}`, eventos `{event, payload}` y peticiones al anfitrión `{hostRequest: {id, method, params}}`. El búfer es del núcleo hasta `tf_core_free`.
- Mecanismo nativo→Dart por decidir en P9: `NativeCallable.listener` (encola al isolate principal; el orden entre llamadas no está documentado) o puerto nativo con `Dart_PostCObject_DL` y `kExternalTypedData` (cualquier hilo, sin copia, finalizador garantizado). Se queda el que gane en latencia y jitter. Sin isolate auxiliar ni canal binario para eventos calientes salvo que P9 mida > 1 ms por mensaje o fotogramas perdidos.
- Los fotogramas ya no pasan por callback: el núcleo los entrega a la textura (ver «Canal de fotogramas»).

Hilos:

- En Flutter ≥ 3.35 el hilo de plataforma y el de UI de Dart son el mismo. En Mac es el hilo principal del proceso, así que lo `@MainActor` de `AppCore` puede correr ahí. **En Windows no está resuelto** (riesgo alto, primera prueba de P9 en el PC): hoy `WinApp` deja el hilo principal en `dispatchMain()` y corre la UI en un hilo propio (`main.swift:506-507`, `:359-362`); el runner de Flutter ocupa el hilo principal con su bucle y nadie drena `DispatchQueue.main` ni `@MainActor`. Vías, en este orden: (1) como `WinApp`: el `wWinMain` del runner crea la ventana y el motor en un hilo propio (STA) y el principal queda en `dispatchMain()`; (2) bombeo desde el bucle del runner: `MsgWaitForMultipleObjects` sobre el HANDLE de `_dispatch_get_main_queue_handle_4CF` y llamada a `_dispatch_main_queue_callback_4CF` (símbolos privados de libdispatch) = `tf_core_pump`. Plan B si fallan las dos: proceso núcleo aparte, previa pregunta.
- Regla heredada de la 7c (spec): el hilo de UI queda en STA **antes** de crear el `Bridge` y nada nativo de audio o vídeo síncrono corre en él. El runner de Windows de Flutter ya hace `CoInitializeEx(APARTMENTTHREADED)`; P9 confirma que Media Foundation no lo cambia.
- Ninguna llamada FFI puede bloquear el hilo principal más de un fotograma (16 ms). Lo largo es un trabajo (`jobs.*`) o un evento.

Servicios de anfitrión (`HostServices` de `AppCore`: diálogos, abrir URL, mostrar en Finder/Explorador, vista previa y carga oculta de Songsterr): `AppCoreFFI` los implementa reenviando `{hostRequest}` a Dart, que responde con `{hostResponse: {id, result|error}}` usando plugins de Flutter. Los métodos `host.*` del puente no cambian.

Ficheros de proyecto (audio, vídeo, fotos): Flutter los abre por ruta de fichero. No hay host virtual `media.toneforge`.

## Canal de fotogramas

Sustituye en Flutter a `frames.<canal>` en JPEG (ADR-021, decisión 8). Canales: `camera` (Grabar y la vista previa de Ajustes · Vídeo, que la reutiliza) y `montage` (vista previa de Montaje). El núcleo entrega cada fotograma al registro de texturas de Flutter y Dart lo pinta con el widget `Texture`; no hay copia de píxeles a Dart.

- Mac: `FlutterTexture.copyPixelBuffer` con `CVPixelBuffer` (32BGRA o NV12). `textureFrameAvailable` y el registro, solo desde el hilo de plataforma.
- Windows: `GpuSurfaceTexture` con textura D3D11 compartida (aviso desde cualquier hilo); respaldo `PixelBufferTexture`. Riesgo: Impeller es el motor por defecto desde 3.47 y hay un fallo reportado «Could not create external texture» (jakky1/video_player_win#54).
- Respaldo de toda la decisión: copia BGRA por FFI y `ui.decodeImageFromPixels` en un `RawImage`, con confirmación por fotograma (el último gana, como `FrameRelay.latestWins`).

Resolución y fps por canal los decide el núcleo con los umbrales que salgan de P9 (objetivo: 720p a 30 fps sin pérdidas). `FrameRelay` en JPEG se conserva en `AppCore` mientras existan las UIs viejas y se borra con ellas.

## Estructura de `FlutterApp/`

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
9. **Plugins permitidos** (versión exacta en `pubspec.yaml`; añadir otro es una pregunta a Jorge): `flutter_riverpod`, `file_selector`, `url_launcher`, `path_provider`, `desktop_drop`, `window_manager`, `shared_preferences` (solo el idioma, con la API `SharedPreferencesAsync`). WebView y vídeo: los que fije P9. Los goldens usan `matchesGoldenFile` con fuentes reales y se generan solo en el Mac.

## WebView (Tablatura y Songsterr)

Widget propio `TfWebView` (`lib/widgets/tf_web_view.dart`) que oculta el paquete, que fija P9 por plataforma (candidatas: `webview_all`, `webview_flutter` en Mac, `webview_flutter_windows` en Windows; una que no compile con el Visual Studio del PC no pasa). En Windows todas las vías son captura a textura, porque Flutter no tiene platform views (flutter#31713). Usos: alphaTab visible (carga `tab.html` + `tf-bridge.js` de los recursos, mensajes JS↔Dart reenviados a `tab.*`), carga oculta de Songsterr y su vista previa visible. Lo que debe cumplir está en la prueba P9.

## Vídeo de tomas

Motor por decidir en P9 (ADR-021, decisión 9); `video_player` y `video_player_win` están descartados. Candidatas: (a) `fvp` con su callback de reloj externo `onSync`; (b) reproductor nativo en el núcleo, esclavo del reloj de audio (`AVPlayer.setRate(_:time:atHostTime:)`, `AVPlayerItemVideoOutput` → `CVPixelBuffer` → textura del canal de fotogramas). En Windows, (b) exige un pipeline propio de Media Foundation, porque `IMFMediaEngine` no admite reloj externo. El audio suena en el núcleo; el vídeo va en silencio y sigue `takeview.position {seconds, playing, at, epoch, rate}`. Tolerancia: medio fotograma. El seguidor de reloj en Dart (`VideoFollower`) ya no es el plan.

## Arranque, capturas y desarrollo

- Argumentos como `AppCore.LaunchOptions` (`--projects-folder`, `--support-dir`, `--screen`, `--project`, `--snapshot`, `--snapshot-delay`, `--window`, `--audio`, `--camera`) más `--mock` (usa `MockCore`) y `--locale es|en`.
- `--snapshot <png>`: la app pinta la pantalla pedida, la vuelca con `RepaintBoundary.toImage` y sale. Se lanza sin robar foco (`open -g` en Mac).
- **Nunca probar con la carpeta real de proyectos**: siempre `--projects-folder` y `--support-dir` a una copia.
- Scripts (salida resumida, logs en `Temp/logs/`): `Tools/flutter/build-core.sh` (compila `AppCoreFFI` y lo deja donde el runner lo recoge), `Tools/flutter/run.sh` (arranca con argumentos y captura), `Tools/flutter/pc.sh` (pasa la rama al PC x64 por ssh, compila, prueba y trae capturas). `Tools/test.sh` gana el paso `FlutterApp`.

## Empaquetado

- **Mac**: `FlutterApp/macos` copia a `Runner.app` el `.dylib` de `AppCoreFFI` (`Contents/Frameworks`), `tf-separate`, helpers, modelos, alphaTab, SoundFont y fuentes (`Contents/Resources`, con los mismos nombres que busca hoy `Bundle.main`).
- **Windows**: junto al `.exe`, `AppCoreFFI.dll`, las DLL del runtime de Swift (`swiftCore`, `swiftCRT`, `swiftDispatch`, `swiftWinSDK`, Foundation), ONNX Runtime y DirectML, helpers y recursos.
- El instalador y el actualizador son fases posteriores (7d y la del instalador).
