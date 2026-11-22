# Contrato de anfitrión: servicios y hilos (Fase 7f)

Completa las secciones parciales «Servicios de anfitrión» e «Hilos» de `docs/flutter/contrato.md:198-207` (ese fichero no se toca). Todo lo de abajo está leído del código el 2026-11-22; lo marcado «no verificado» no se ha ejecutado.

## 1. Servicios de anfitrión

### 1.1 Protocolo `HostServices` (`Packages/AppCore/Sources/AppCore/ImportMethods.swift:6-55`)

`HostServices: Sendable, HiddenPageLoading`. Todos los requisitos son `async` (ninguno síncrono). AppCore los llama desde un contexto async sin actor (pool cooperativo de Swift), salvo `saveFile`, que se llama desde el `@MainActor` de `TabService` (ver «hilo»). El anfitrión debe poder atenderlos desde cualquier hilo.

| # | Requisito (firma) | Fichero:línea | Por omisión (extensión) | Hilo desde el que AppCore lo llama | Quién lo usa |
|---|---|---|---|---|---|
| 1 | `func pickFile(types: [String]) async -> URL?` (extensiones sin punto; nil = cancelado) | ImportMethods.swift:8 | requisito, sin defecto | pool cooperativo (closure del router) | `host.pickAudioFile` (:204-208) con `JobEngine.importExtensions` ordenadas |
| 2 | `func pickFiles(types: [String]) async -> [URL]` | :10 | uno solo vía `pickFile` (:44) | pool | `host.pickAudioFiles` (:209-213) |
| 3 | `func pickFolder() async -> URL?` | :12 | requisito, sin defecto | pool | solo por el defecto de #4 |
| 4 | `func pickFolder(initial: URL?) async -> URL?` | :15 | `pickFolder()` (:45) | pool | `Bridge.requestFolder` (:296-300), único punto: `host.chooseFolder` (:245) y `host.pickProjectsFolder` (:273). `TF_TEST_PICK_FOLDER` lo salta (:296-299), solo pruebas |
| 5 | `func projectsFolderChanged(_ url: URL) async -> Bool` (re-servir `mediaBase`; false = no pudo) | :18 | `true` (:46) | pool | `library.relocate` (:268; tras mover/apuntar) y `host.pickProjectsFolder` en primer arranque (:287, resultado ignorado) |
| 6 | `func saveFile(suggestedName: String, types: [String]) async -> URL?` | :20 | `nil` (:47) | **hilo principal**: `TabService` es `@MainActor` (`TabService.swift:33`), llamada en `TabService.swift:1225` | `tab.export` (`TabMethods.swift:60`) solo si la página no pasa `path`; `types: ["gp"]` |
| 7 | `func openURL(_ url: URL) async -> Bool` (false = nada la abre) | :22 | `false` (:48) | pool | `host.openURL` (:216-224): prueba cada URL en orden, solo esquemas `spotify`, `http`, `https` (`Bridge.openableSchemes`, :308) |
| 8 | `func showPreview(url: URL, rect: PreviewRect) async -> Bool` (`rect` en píxeles CSS; el anfitrión aplica la escala del monitor) | :26 | `false` (:49) → AppCore responde `unsupported` (:235-237) | pool | `host.preview.show` (:226): AppCore valida antes https + songsterr.com (:227) y rect finito, w/h >= 1 (:230) |
| 9 | `func hidePreview() async` (idempotente) | :28 | no-op (:50) | pool | `host.preview.hide` (:240) |
| 10 | `func load(url:userAgent:readyScript:timeout:) async throws -> HiddenPage` (de `HiddenPageLoading`, `TabSongsterr.swift:64`) | ImportMethods.swift:52 | lanza `HiddenPageError.unsupported` (:53) | tarea del `@MainActor` `SongsterrSheet` (`TabSongsterr.swift:351,429`; el `await` sale del actor) | `tab.songsterr.open/search` (`TabSongsterr.swift:762-765`) vía `HiddenPageSongsterrLoader` (:82-91, :404) |

Contrato de #10 (`TabSongsterr.swift:58-66`): navegar a `url`, evaluar `readyScript` (expresión JS booleana) cada `SongsterrHiddenPage.pollMillis`, devolver `HiddenPage(status:, html: document.documentElement.outerHTML)`; errores `HiddenPageError` (`:27`: offline, readyTimeout, httpStatus, cancelled, unsupported). Debe respetar la cancelación de la tarea. `userAgent` puede ignorarse (WinApp lo hace: `main.swift:147`).

`PreviewRect {x, y, width, height: Double}` (`ImportMethods.swift:32`).

Sin `bridge.host`, los `host.*` dan `unsupported` (`Bridge.noHost`, `:311-313`); `tab.songsterr.open` sin host ni `services.songsterr` da `unsupported` (`TabSongsterr.swift:399-403`).

Cableado: `Bridge.host` es propiedad con lock (`Bridge.swift:64-67`); `tabService.hostProvider` lee `self.host` (`Bridge.swift:158`, `TabService.swift:75`). Se asigna antes de `bridge.start()` en WinApp (`main.swift:464-465`) y en webdev (`tf-webdev/main.swift:~329-330`).

### 1.2 Otros servicios que el anfitrión debe dar pero NO son `HostServices`

| Servicio | Mecanismo | Fichero:línea | Nota |
|---|---|---|---|
| Salida al JS (`send`) | `Bridge.send: @Sendable (String) -> Void`, lo asigna el anfitrión | Bridge.swift:69-73 | cualquier hilo (ver §2) |
| Entrada del JS (`receive`) | `Bridge.receive(_ json: String)` lo llama el anfitrión | Bridge.swift:121-126 | |
| Servir medios (`mediaBase`) | parámetro de `Bridge.init(options:mediaBase:)`; `Bridge.mediaFolder` = carpeta de proyectos | Bridge.swift:75-79 | WinApp: `https://media.toneforge/` mapeado con `tfhost_map_folder` (`main.swift:376,472-473`); webdev: esquema `tf-media://` |
| Arranque / cierre | `Bridge.start()`, `shutdownAsync()`, `shutdown()` | ImportMethods.swift:130-153 | ver §2 |
| Soltar ficheros | evento `host.filesDropped {paths}` emitido POR EL ANFITRIÓN, no AppCore | WinApp `main.swift:443-448` | la página lo consume; no hay requisito en AppCore |
| Mostrar en Explorador/Finder | NO pasa por el anfitrión: `Bridge.openFolder` lanza `Process` (`explorer.exe` / `/usr/bin/open`) | Bridge.swift:191-202; usado por `library.reveal` (:173) y `MontageService(reveal:)` (:106) | un anfitrión Flutter no necesita implementarlo; funciona en el proceso de AppCore. Decisión de Jorge si se quiere que pase por el anfitrión (p. ej. para seleccionar el fichero en vez de abrir la carpeta; el Mac de SwiftUI usa `activateFileViewerSelecting`, `App/Sources/AppModel.swift:920`) |
| Privacidad de cámara | NO anfitrión: `SystemCameraPrivacy` lanza `cmd /c start ms-settings:privacy-webcam` (Windows) o `open x-apple...` | CameraPreview.swift:32-48; método `video.openCameraPrivacy` (:78) | idem |
| Cámara (captura, `frames.camera`, `frames.montage`) | NO anfitrión: captura en AppCore (`CameraCapture`, Media Foundation en Windows) y los fotogramas salen como eventos por `send` vía `FrameRelay` | CameraPreview.swift:56-; FrameRelay.swift:49 | el anfitrión solo pinta lo que llega por el canal; no hay vista nativa de cámara |
| Audio, tablatura (render alphaTab), reproductor | NO anfitrión: dentro de AppCore (`AudioController`, `StudyAudio`) y la página (alphaTab) | | |

No hay en el código ningún servicio de «vista previa nativa de vídeo» ni «diálogo de guardar vídeo» en `HostServices`: el export de Montaje escribe en la carpeta del proyecto (no verificado fuera de la ausencia en el protocolo).

### 1.3 Implementaciones actuales

| Requisito | `WinApp` (`WinApp/Sources/ToneForge/main.swift`, clase `WindowsHostServices` :65-197) | `Tools/webdev` (`tf-webdev/main.swift`, `PanelHost` :244-291) | App SwiftUI (`App/`) |
|---|---|---|---|
| pickFile | :79; hilo nuevo (`Thread.detachNewThread`, :68-77) → `tfhost_pick_file` → `SendMessage(WM_TF_PICK/OPEN)` al hilo de UI → `IFileOpenDialog` modal | :258; `MainActor.run` + `NSOpenPanel.runModal` | no usa `HostServices`; `NSOpenPanel` directo (`AppModel.swift:386,555,1020`) |
| pickFiles | :90; búfer 1 MiB, rutas separadas por `\n`; rc<0 = cancelado | :268; `NSOpenPanel` múltiple | idem |
| pickFolder() | :135 | :278 | idem |
| pickFolder(initial:) | :128 (`tfhost_pick_folder_at`) | defecto → `pickFolder()` (ignora `initial`) | idem |
| projectsFolderChanged | :119; `tfhost_map_folder(host,"media.toneforge",ruta)` (SendMessage al hilo de UI si hace falta, `CWebView2Host.cpp:~940-946`); rc==0 → true | defecto `true` (no remapea; sin servicio) | n/a |
| saveFile | **NO implementado** → defecto nil. La exportación `.gp` por diálogo no funciona en Windows hoy (hueco, ver §3); solo con `path` explícito | **NO implementado** → nil | `NSSavePanel` directo en `TabController.swift:1330` |
| openURL | :109; `tfhost_open_url` → `ShellExecuteEx "open"` en el hilo de UI | **NO implementado** → false | `NSWorkspace.shared.open` (`LinkImportSheet.swift:196`) |
| showPreview / hidePreview | :187-196; `tfhost_preview_show/hide` (PostMessage a la ventana; WebView2 hijo, escala del monitor en el shim); `showPreview` devuelve `true` siempre si hay `host` | :252-256; `PreviewPanel` (`@MainActor`) | n/a |
| load (navegador oculto) | :148-183; segundo WebView2 InPrivate en el shim; `AsyncMutex` serializa cargas (:143,149); `withTaskCancellationHandler` → `tfhost_hidden_cancel`; timeout ajustado a 1-600 s (:171); ignora `userAgent` | :249-250; `HiddenBrowser` (`@MainActor`) | n/a (Songsterr en la app SwiftUI no pasa por aquí) |

La app SwiftUI no importa `HostServices` (ningún acierto en `App/`); no usa `Bridge` para nada de esto: sus equivalentes son llamadas directas a AppKit. `PanelHost` de webdev implementa 6 de los 10 requisitos propios (pickFile, pickFiles, pickFolder, showPreview, hidePreview, load) y hereda los defectos de los demás.

### 1.4 Tabla final: servicio → qué tiene que hacer un anfitrión nuevo (Flutter)

| Servicio | Obligatorio | Qué hace el anfitrión | Valor de retorno en cancelación / fallo |
|---|---|---|---|
| pickFile | sí (importar tema) | diálogo de abrir fichero, filtro por extensiones sin punto (`wav,flac,mp3,…`), un fichero | `nil` |
| pickFiles | sí (importar varios) | igual, selección múltiple | `[]` (nunca lanza) |
| pickFolder / pickFolder(initial:) | sí (carpeta de proyectos, primer arranque, mover biblioteca) | diálogo de carpeta abriendo en `initial` | `nil` |
| projectsFolderChanged | sí (si el anfitrión sirve los medios por origen/URL propio) | volver a servir `mediaBase` desde la carpeta nueva ANTES de devolver; si no sirve medios desde la carpeta (p. ej. AppCore los entrega por otra vía) basta `true` | `false` si no pudo (la página avisa) |
| saveFile | recomendado (exportar `.gp`) | diálogo de guardar con nombre sugerido y extensión `gp` | `nil` (→ `saved:false`) |
| openURL | sí («Oír en Spotify») | abrir con la app del sistema para el esquema (`spotify:`, `http(s):`) | `false` |
| showPreview / hidePreview | opcional (solo Songsterr visible) | panel/vista web sobre la ventana en `rect` (px CSS, aplicar escala de DPI), navegar si `url` cambió; ocultar y detener la página; `hidePreview` idempotente | `showPreview` false → la página recibe `unsupported` |
| load (navegador oculto) | opcional (Songsterr: búsqueda y lectura) | cargar `url` en un navegador sin ventana y sin estado (InPrivate), sondear `readyScript` hasta true o `timeout`, devolver `status` y `outerHTML`; una carga a la vez, cancelable | lanzar `HiddenPageError` (sin él, `unsupported`) |
| send / receive | sí | ver §2 | |
| mediaBase | sí | servir la carpeta de proyectos en la URL que se pasó a `Bridge.init` | |
| Eventos propios del anfitrión | recomendado | `host.filesDropped` | |
| Mostrar en Explorador, privacidad de cámara, cámara | no | AppCore lo hace solo | |

## 2. Hilos

### 2.1 Qué es `@MainActor` en AppCore

- **`Bridge` y `Router` NO son `@MainActor`**: `Bridge` es `public final class … @unchecked Sendable` (`Bridge.swift:21`) y `Router` igual (`Router.swift:20`). `Bridge.swift` y `Router.swift` no contienen ningún `@MainActor` (grep). Estado compartido protegido con `NSLock` (`host`, `send`, hooks: `Bridge.swift:50-52,64-73`).
- **Controladores y servicios con estado sí lo son** (grep `@MainActor` en `Packages/AppCore/Sources/AppCore`): `AudioController` (`AudioController.swift:111,171`), `AudioService` (`AudioMethods.swift:174`), `CameraPreviewService` (`CameraPreview.swift:56`), `ExternalSources` (`ExternalSources.swift:19`), `LinkImportSession` (`LinkImportSession.swift:53`), `MontageController` (`MontageController.swift:13`), `MontageService` (`MontageMethods.swift:304`), `MontageAudioPlaying`/`ClockMontageAudio`/`StudyMontageAudio` (`MontageServices.swift:23,165,197`), `PlaylistSession` (`PlaylistSession.swift:8`), `PlaylistMethods` (`:110`), `RecordController` (`RecordController.swift:29,186`), `RecordService` (`RecordMethods.swift:221`), `StudyAudio` (`StudyAudio.swift:15`), `StudySession` (`StudySession.swift:104`), `StudyBacking` (`StudyBacking.swift:8`), `StudyService`/salida de eventos (`StudyMethods.swift:182`), `TabService` (`TabService.swift:33`), `SongsterrSheet` (`TabSongsterr.swift:351`), `TakeViewService` (`TakeViewMethods.swift:120,217`).
- Consecuencia: el reproductor, la grabación, el montaje y la tablatura corren en el actor principal de Swift. Los handlers del router no están aislados: los que tocan esos controladores saltan al principal con `await MainActor.run`/`await self.método()` (p. ej. `AudioMethods.swift:258-289`, `LinkMethods.swift:277,359`).
- Los `ticker`/`meterTask` de posición y niveles son `Task { @MainActor }` (`RecordMethods.swift:549`, `StudyMethods.swift:468,477`) y llaman a `emit` desde el principal.

### 2.2 `Bridge.receive`

- `Bridge.swift:121-126`: `receive` hace `Task { [router] in let response = await router.handle(json); self.send(response) }`. No está aislado a actor, por lo que `Task {}` en un contexto no aislado corre en el pool cooperativo, no en el hilo que llama.
- **Hilo esperado: cualquiera.** No hay ninguna aserción de hilo (`dispatchPrecondition`, `assumeIsolated`) en `receive`, `Router.handle` ni `emit`. Si se llama desde un hilo distinto del que el anfitrión usa para su UI no pasa nada en AppCore; lo que hay que cuidar es el `send` que sale (ver abajo).
- No hay garantía de orden entre respuestas: cada mensaje es una `Task` independiente. El orden de llegada de las respuestas depende de cada handler; la correlación es por `id` (`Router.swift:60-66`).
- Hoy: WinApp lo llama en el **hilo de UI Win32** (`on_message`, `main.swift:432-437`, invocado desde el manejador de WebView2 en `CWebView2Host.cpp:370`); webdev lo llama en el **hilo principal** (`handler.onBridge = { b.receive($0) }`, `tf-webdev/main.swift:338`).

### 2.3 `emit` / `send`

- `Bridge.emit` (`Bridge.swift:~128-131`) codifica y llama a `send(...)` directamente; no reencola a ningún hilo. `send` es la propiedad que fija el anfitrión (`:69-73`), documentada «se puede llamar desde cualquier hilo».
- Hilos reales desde los que se llama a `send`: pool cooperativo (respuesta de `receive`, `Bridge.swift:124`), actor principal (tickers y `*.state` de controladores: `RecordMethods.swift:531,573,581`, `StudyMethods.swift:380,468,477`, `MontageMethods.swift:696-743`), cola de GCD del relevo de fotogramas `ToneForge.FrameRelay.<canal>` (`FrameRelay.swift:111`), callbacks del motor de trabajos (`jobs.progress`, `library.changed`: `ImportMethods.swift:~160-163`), y `Task.detached` de ajustes (`video.camerasChanged`, `SettingsMethods.swift:~303`). Además los manejadores de dispositivos de audio y cámara (no verificado el hilo exacto de cada uno).
- **El anfitrión es responsable de reencolar al hilo de UI.** WinApp: `bridge.send = { tfhost_post(app.host, $0) }` (`main.swift:468-470`); `tfhost_post` copia a `std::wstring` y hace `PostMessageW(WM_TF_POST)` a la ventana (`CWebView2Host.cpp:950-956`), que `PostWebMessageAsString` en el hilo de UI (`:730-735`). Es seguro desde cualquier hilo. webdev: `DispatchQueue.main.async { evaluateJavaScript(...) }` (`tf-webdev/main.swift:343`). Un anfitrión nuevo con UI en un solo hilo (Flutter: hilo de plataforma/UI) debe hacer el equivalente; llamar a la API de Flutter desde otro hilo (en particular desde la cola de GCD de los fotogramas a 15 fps) es un error.
- Frecuencia: `frames.camera` hasta 15 fps y `study.position`/`levels`, `record.position`/`levels` con tickers; todo por `send` como JSON de texto. No hay canal binario (no verificado el tamaño de los eventos de fotograma en el JSON).

### 2.4 Cómo drena hoy el anfitrión Win32 la cola principal de Swift

Diseño en `WinApp/Sources/ToneForge/main.swift:359-362` (comentario) y `:505-507`:

1. **Hilo principal del proceso**: `Thread.detachNewThread { runUI() }` (`:506`) y a continuación **`dispatchMain()`** (`:507`). `dispatchMain()` nunca vuelve y es lo que drena `DispatchQueue.main` y el ejecutor de `@MainActor` de AppCore. No hay `RunLoop.main.run`, ni `MsgWaitForMultipleObjects` en este hilo, ni `GetMessage` en él (comentario `:360-361`: un `GetMessage` en el hilo principal no drenaría la cola de Swift).
2. **Hilo de UI propio** (`runUI`, `:366-503`): STA, crea la ventana WebView2 y ejecuta el bucle de mensajes Win32: `tfhost_run` → `while (GetMessageW(&m, nullptr, 0, 0) > 0) { TranslateMessage; DispatchMessageW }` (`CWebView2Host.cpp:979-982`). Durante `tfhost_create` hay un bombeo previo: `PeekMessageW(PM_REMOVE)` + `MsgWaitForMultipleObjects(0, nullptr, FALSE, 50, QS_ALLINPUT)` hasta que el controlador de WebView2 esté listo, con tope de 60 s (`CWebView2Host.cpp:~920-931`).
3. **Autoprueba** `--selftest-mainactor` (`main.swift:264-296, 337-340`): confirma que `Task { @MainActor }` y `DispatchQueue.main.async` se ejecutan con `dispatchMain()` (3 s de tope).
4. No hay temporizador de bombeo ni hilo extra para la cola principal. Los hilos auxiliares solo son: vigilante de arranque (`:345-354`, solo QA), `Thread.detachNewThread` por cada diálogo (`:70,93,111,120`), y los de `--snapshot`/`--eval-file`.
5. Salida: `PostQuitMessage` tras `on_close` (`CWebView2Host.cpp:808-818`); `tfhost_run` vuelve, `runUI` cierra el estudio con `Task.detached` + semáforo de 3 s (`main.swift:493-502`) y llama a `exit(...)` desde el hilo de UI. El hilo principal sigue en `dispatchMain()` hasta el `exit`.

Para Flutter: el runner de Windows de Flutter ya tiene su propio bucle de mensajes Win32 en el hilo principal del proceso. Si Swift/AppCore corre como biblioteca dentro de ese proceso, **el hilo principal NO está en `dispatchMain()`** y los `@MainActor` no se drenarían: hace falta o bien que Swift tenga su propio hilo-principal-de-Swift (como WinApp, que aquí es el hilo principal real del proceso, imposible en el runner de Flutter) o drenar la cola a mano (`_dispatch_main_queue_callback_4CF`/equivalente en swift-corelibs; no verificado en este repo y sin precedente en él). **Decisión de Jorge / sondeo pendiente**: cómo drenar `@MainActor` dentro del runner de Flutter (proceso separado con puente IPC; o `Thread` propio con `MainActor` desviado; o sondear en un `Timer` de Dart que llame a una función FFI). No hay prueba hecha en `docs/probes/`.

### 2.5 COM / STA y orden de inicialización

- Spec `docs/spec.md` (sección «COM y el hilo de UI»): Media Foundation hace `CoInitializeEx(MTA)`; si ocurre en el hilo de UI antes de WebView2, `CreateCoreWebView2Environment` falla con `0x80010106` (`RPC_E_CHANGED_MODE`). El hilo de UI se pone en STA lo primero (`tfhost_init_ui_thread`, antes de crear el `Bridge`) y nada nativo de audio o vídeo se llama de forma síncrona en él.
- Orden real en `runUI` (`main.swift`): (1) `tfhost_init_ui_thread()` → `CoInitializeEx(COINIT_APARTMENTTHREADED)` (`:370`; `CWebView2Host.cpp:1097-1101`, acepta `S_OK` y `S_FALSE`, sin `CoUninitialize`); (2) `Bridge(options:mediaBase:)` (`:376`), que ejecuta `registerMethods()` y en `SettingsService.register` difiere la enumeración de cámaras a `Task.detached` (`SettingsMethods.swift:298-301`); (3) `tfhost_create` (`:450`), que repite `CoInitializeEx(STA)` y falla con mensaje claro si el hilo ya estaba en MTA (`CWebView2Host.cpp:830-837`); (4) `bridge.host`, `bridge.start()` (`:464-465`); (5) `bridge.send` (`:468`), después de `start()`; (6) mapeo de `media.toneforge` (`:472`); (7) `tfhost_run`.
- Hueco menor: `bridge.send` se asigna DESPUÉS de `bridge.start()` (`:465` vs `:468`), así que un evento emitido por `start()` en ese intervalo iría al `send` por defecto (no verificado cuál es; ver `Bridge.swift:~44-48`).
- Media Foundation se usa en hilos del pool (MTA implícito) y en `Task.detached`, nunca en el hilo de UI. Un anfitrión nuevo debe garantizar que el hilo donde vive su UI/WebView se inicializa en STA antes de crear el `Bridge` (si lo exige el motor web) y que `Bridge.init` no hace trabajo COM síncrono en ese hilo. En el runner de Flutter el hilo principal ya es STA (Flutter lo inicializa); validar con una sonda que `Bridge.init` no lo cambia (pendiente de Jorge).

### 2.6 `shutdownAsync` y su tope

- `Bridge.shutdownAsync()` (`ImportMethods.swift:~144-153`): ejecuta los `shutdownHooks`, luego `closeMontage`, `closeTakeView`, `closeTab`, `closeStudy` (en el actor principal) y por último `jobs.shutdown()`.
- Tope: `JobEngine.shutdownBudget = 3` s (`JobQueue.swift:407`) aplicado solo a `jobs.shutdown()` (espera a que `Library` pare, sondeo de 20 ms, `:420-425`). **Los pasos anteriores no tienen tope** dentro de `shutdownAsync`.
- `Bridge.shutdown()` síncrono (`ImportMethods.swift:130-137`): lanza `Task.detached { await shutdownAsync(); signal }` y espera con `DispatchSemaphore` hasta `shutdownBudget + 0.5` = 3,5 s. Documentado: no llamar desde el hilo principal de Swift porque `closeStudy` salta al actor principal (:128-129).
- WinApp: `on_close` (hilo de UI, `main.swift:438-442`) llama a `bridge.shutdown()` síncrono → **bloquea el hilo de UI hasta 3,5 s** mientras la ventana se destruye (`CWebView2Host.cpp:815`); no bloquea el hilo principal (que está en `dispatchMain()`), por eso `closeStudy` puede avanzar. Después `runUI` repite `closeMontage`/`closeStudy` con 3 s más (`closeStudyBudget`, `main.swift:364,501`). Peor caso: ~6,5 s antes de `exit`.
- webdev: `applicationShouldTerminate` → `.terminateLater` + `Task { await b.shutdownAsync(); reply }` (`tf-webdev/main.swift:465-467`), sin tope global propio.

### 2.7 Llamadas que bloquean hoy un hilo de forma síncrona (detectadas)

| Dónde | Qué bloquea | Hilo | Gravedad |
|---|---|---|---|
| `Bridge.shutdown()` desde `on_close` (`main.swift:441`) | hasta 3,5 s | hilo de UI Win32 | baja (cierre) |
| `MontageServices.swift:127-138` (`MacMontageComposer.frame(atVideoTime:)`: `DispatchSemaphore.wait()` sin tope) | espera a `generateCGImageAsynchronously` | se llama desde `Task.detached` (`MontageController.swift:805-807`), no desde el principal | baja; solo Mac |
| `StudyAudio.swift:128-140` (`Thread.sleep(0.002)`) | bomba del reproductor simulado | hilo propio | n/a (tests) |
| Lógica síncrona de los controladores `@MainActor` (reproductor, montaje, tablatura) | bloquea el actor principal de Swift, no el hilo de UI Win32 (separados en Windows) | principal Swift | no medido; en SwiftUI de Mac el actor principal es el hilo de UI |
| `tfhost_map_folder` desde otro hilo hace `SendMessage` al hilo de UI y espera (`CWebView2Host.cpp:945`) | hilo auxiliar hasta que la UI responda | auxiliar | baja |
| Diálogos: `SendMessage(WM_TF_PICK/OPEN)` modal desde un hilo propio por llamada (`main.swift:68-77`) | ese hilo auxiliar, mientras el diálogo esté abierto; el bucle de la UI sigue bombeando dentro del diálogo modal | auxiliar | n/a (por diseño: no ocupa el pool) |

No he encontrado en `AppCore` ninguna llamada síncrona larga en `receive`/`Router.handle` ni en el hilo de UI (la enumeración de cámaras ya se movió a `Task.detached`).

## 3. Huecos (resumen)

1. `saveFile` no existe en WinApp ni en webdev: `tab.export` sin `path` devuelve `saved:false` (`TabService.swift:1225-1228`). Decisión de Jorge: implementarlo en cada anfitrión o exigir `path` desde la página.
2. `openURL` y `projectsFolderChanged` no están en webdev (defectos `false`/`true`).
3. Cómo se drena `@MainActor` dentro del runner de Flutter no tiene precedente ni sonda (§2.4).
4. `bridge.send` se fija después de `bridge.start()` en WinApp (§2.5).
5. `shutdownAsync` solo topa `jobs.shutdown()` (3 s); los cierres del estudio/montaje/tablatura/tomas no tienen tope propio (§2.6); el peor caso en WinApp son ~6,5 s.
6. «Mostrar en Explorador/Finder» y «privacidad de cámara» no pasan por el anfitrión: un anfitrión nuevo no los puede sustituir sin cambiar AppCore (decisión de Jorge).
7. Spec: la regla STA está en `docs/spec.md` («COM y el hilo de UI»); no hay regla escrita sobre el hilo de `receive`/`send` ni sobre el drenaje de la cola principal (propuesta: este documento §2.2-2.4; decisión de Jorge).
