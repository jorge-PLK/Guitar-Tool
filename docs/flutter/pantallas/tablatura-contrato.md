# Ficha de pantalla · Tablatura · apartados 5 y 9

Apartados 5 (contrato que usa) y 9 (desvíos detectados) de la ficha de Tablatura (`_PLANTILLA.md`). El resto de la ficha va en `tablatura.md`.

Rutas abreviadas: `AC/` = `Packages/AppCore/Sources/AppCore/`; `Web/` = `WinApp/Web/`; `App/` = `App/Sources/`.

Tipos completos: `docs/flutter/contrato-tipos-b.md`, sección «tab y tab.songsterr». El detalle de campos vive allí; aquí solo los campos que la pantalla lee.

Recuento: **35 métodos** (20 `tab.*` en `AC/TabMethods.swift:7-60` + 15 `tab.songsterr.*` en `AC/TabSongsterr.swift:762-782`) y **5 eventos** del núcleo (`tab.state`, `tab.progress`, `tab.selection`, `tab.range`, `tab.songsterr.state`). Además la pantalla usa `study.*` (transporte) y `host.preview.show/hide`.

## 5. Contrato que usa

### 5.1 Métodos `tab.*`

Todos devuelven `TabState` (ver `contrato-tipos-b.md`, «DTO de `tab`») salvo los indicados. Error `not-open` si no hay tablatura abierta (`AC/TabMethods.swift:9, 66`: `tab.state` y `requireOpen`); `tab.songsterr.*` sin `tab.open` previo también da `not-open`.

| Acción o momento | Método | Params -> resultado (Swift, fichero:línea) | Cómo lo usa `WinApp/Web` |
| --- | --- | --- | --- |
| Entrar en la pantalla con un tema | `tab.open` | `TabOpenParams` (ver `contrato-tipos-b.md`, «DTO de `tab`», Params) -> `TabState` (ídem). Abre `study` por dentro si no es el actual (`TabService.swift:156-160`) | `Web/tab/store.js:162` tras `openStudy` (`study.open`, `:159`); `reopenTab` `:188` al terminar el análisis (`Web/screens/tab.js`, efecto `waitingAnalysis`) |
| Salir de la pantalla | `tab.close` | `Empty` -> `Empty` (`TabMethods.swift:12`; guarda lo editado, `TabService.swift:171`) | `Web/tab/store.js:181` |
| Consultar estado | `tab.state` | `Empty` -> `TabState` (`TabMethods.swift:8`) | No se llama; solo se usa el evento del mismo nombre |
| Fuente «Transcripción automática» | `tab.setSource {source:"automatic"}` | `TabSourceParams` (ver tipos-b, «DTO de `tab`», Params) -> `TabState` (`TabService.swift:315`) | `Web/tab/store.js:212`; menú `Web/screens/tab.js:77-91` |
| Fuente «Songsterr» | `tab.setSource {source:"songsterr"}` abre la hoja (`TabService.swift:317-320`); la fuente se guarda con `tab.songsterr.accept` | igual | La web no lo usa: abre la hoja con `tab.songsterr.open` (`Web/tab/songsterr-sheet.js:57`, menú `Web/screens/tab.js:80`) |
| Pedir la partitura | `tab.score {track?}` | `TabTrackParams` (ver tipos-b, Params) -> `TabScoreResult` (ver tipos-b, «DTO de `tab`») (`json`, `trackIndex`, `trackIDs`, `revision`) | `Web/tab/store.js:123`; caché por `revision` + pistas listas (`:110`) |
| Cambiar de pista visible | `tab.selectTrack {track}` | `TabTrackParams` -> `TabState` | `Web/tab/store.js:207`; automático si `selectedTrack` no está lista (`:118`) |
| Lanzar transcripción | `tab.transcribe {track?}` | `TabTrackParams` -> `TabQueuedResult` (ver tipos-b, «DTO de `tab`»). Solo en fase `ready` (`TabService.swift:400`) | `Web/tab/store.js:104` (pistas `queued`, una vez por pista y apertura) y `:220` (por pista) |
| Cancelar transcripción | `tab.cancel` | `Empty` -> `CancelResult` (ver tipos-b, fila `tab.cancel`) | `Web/tab/store.js:225` |
| Clic en pulso | `tab.beatClick {track,bar,beat,shift}` | `TabClickParams` (ver tipos-b, Params) -> `TabState` | `Web/tab/store.js:66` (evento `beatClick`) |
| Arrastre en pulso | `tab.beatDrag {track,bar,beat}` | `TabClickParams` -> `TabState` | `Web/tab/store.js:72-81`: una petición a la vez, solo se conserva la última pendiente |
| Clic en nota | `tab.noteClick {track,bar,beat,string,shift}` | `TabClickParams` -> `TabState` | `Web/tab/store.js:68-71`; ignora `shift` (lo trata `beatClick`) |
| Seleccionar punto por programa | `tab.select {track,beat,tick,string?}` | `TabSelectParams` (ver tipos-b, Params) -> `TabState` | No se llama (solo `AppCoreTests/TabTests.swift:278`) |
| Tramo: limpiar, aplicar bucle, ampliar | `tab.span {action}`: `clear`, `apply`, `extendForward`, `extendBack` (`TabService.swift:616-623`) | `TabSpanParams` (ver tipos-b, Params y valores de `action`) -> `TabState` | `Web/tab/store.js:216`; `Web/screens/tab.js:291-292`; Esc con tramo `Web/tab/keys.js:15` |
| Silenciar / solo pista | `tab.toggleMute`, `tab.toggleSolo {track}` | `TabTrackParams` -> `TabState` | `Web/tab/store.js:208-209` |
| Escuchar transcripción | `tab.setListening {track,on}`, `tab.setAllListening {on}` | `TabListeningParams` (ver tipos-b, Params) -> `TabState` | `Web/tab/store.js:210-211` |
| Editar (barra y teclado) | `tab.edit {op,...}`. `op`: `digit`, `moveString`, `delete`, `duration`, `hit`, `ornament`, `key`, `addNote`, `move`, `tuning`, `undo`, `redo`, `editMode`, `deselect` (`TabService.swift:984-1013`) | `TabEditParams` (ver tipos-b, Params y `op` con sus campos) -> `TabState` (con `handled` en `op:"key"`) | `Web/tab/store.js:213-215`; botones `Web/screens/tab.js:255-264`; teclas `Web/tab/keys.js:11-25` |
| Deshacer / rehacer | `tab.edit {op:"undo"}` / `{op:"redo"}`; `canUndo`, `canRedo` en `TabState` | igual | Botones `Web/screens/tab.js:255-256`; teclado: Ctrl+Z y Ctrl+Mayús+Z por `op:"key"` (`TabService.swift:947`); Ctrl+Y solo web (`Web/tab/keys.js:19`) |
| Nombre del `.gp` | `tab.exportName` | `Empty` -> `TabExportNameResult` (ver tipos-b, «DTO de `tab`») | No se llama |
| Exportar `.gp` | `tab.export {data(base64), path?}` | `TabExportParams` (ver tipos-b, Params) -> `TabExportResult` (ver tipos-b, «DTO de `tab`») (`saved`, `path?`). `not-ready` si no hay fase `ready` o partitura (`TabService.swift:1217`); `bad-params` si la base64 no vale (`:1220`) | `Web/tab/store.js:231-237`; sin `path`; timeout 10 min (`:12`) |

En `TabClickParams`, `track`, `bar`, `beat` y `string` son `Int` (índices de alphaTab/JSON; `track` = posición en `trackIDs`); `shift` es `Bool?` (ausente = false); `string` ausente en `noteClick` = 0. Ojo: `tab.select.track`, `tab.selectTrack.track`, `toggleMute/Solo.track` y `setListening.track` son `String` (id de pista).

### 5.2 Métodos `tab.songsterr.*`

Todos devuelven `SongsterrSheetState` (ver tipos-b, «DTO de Songsterr»; `open:false` = hoja cerrada) salvo `accept` y `automatic` (`TabState`). Registro en `AC/TabSongsterr.swift:762-782` (ver tipos-b, «Métodos `tab.songsterr.*`»).

| Acción | Método | Params / DTO (fichero:línea) | Uso en `Web/tab/songsterr-sheet.js` |
| --- | --- | --- | --- |
| Abrir hoja (búsqueda por «Artista · Título») | `open` | `SongsterrSheet.open` (ver tipos-b, fila `open`) | `:57`; solo se abre sola con fase `choosingSource` (`Web/screens/tab.js`, efecto `choosing`) |
| Releer estado | `state` | `SongsterrSheetState` | No se llama; solo evento |
| Cerrar / Cancelar | `close` | igual | `:58` |
| Nueva búsqueda | `search` | `Empty` -> `SongsterrSheetState` | No se llama |
| Reintentar búsqueda o lectura | `retry` | igual | `IssueBox`, `act('tab.songsterr.retry')` |
| Marcar resultado | `select {songId}` | `SongsterrSelectParams` (ver tipos-b, fila `select`) | clic en fila; el cliente abre además la vista previa (`previewOpen`) |
| Pegar enlace | `link {link}` | `SongsterrLinkParams` (ver tipos-b, fila `link`) | botón «Usar enlace» |
| Usar la marcada | `use` | `useSelected` (ver tipos-b, fila `use`); habilitado con `canUse` | botón «Usar esta» |
| Cambiar emparejamiento | `review` | `reviewPairing` (ver tipos-b, fila `review`) | menú Fuente (`Web/tab/songsterr-sheet.js:59`, `Web/screens/tab.js:81`) |
| Reintentar importación | `retryImport` | igual | `IssueBox`, etapa `failed` |
| Volver / Atrás | `back` | igual | etapas `working`, `failed`, `pairing` |
| Asignar pista Songsterr a stem o solo | `assign {stemId: String, track?: Int, solo?: Int}`; `solo` es el índice de la sección de solo (Int), no Bool | `SongsterrAssignParams` (ver tipos-b, fila `assign`) | selectores de `pairing` |
| Todo automático | `allAutomatic` | igual | etapa `pairing` |
| Aceptar emparejamiento | `accept` | -> `TabState` (ver tipos-b, fila `accept`) | `:66-68`; luego `applyTabState` (lanza `tab.transcribe` de las `queued`) y cierra la hoja en el cliente |
| «Transcribir automáticamente» desde la hoja | `automatic` | -> `TabState` | `:62-65` |

Tipos auxiliares de la hoja: `SongsterrIssueInfo`, `SongsterrTrackInfo`, `SongsterrResultInfo` (`previewUrl`), `SongsterrSongInfo`, `SongsterrSearchInfo`, `SongsterrChoiceInfo`, `SongsterrSoloRowInfo`, `SongsterrSlotInfo`, `SongsterrPairingInfo` (campos en tipos-b, «DTO de Songsterr»). Etapas (`stage`): `choosing`, `working`, `pairing`, `failed`.

### 5.3 Eventos del núcleo

| Evento | Payload (fichero:línea) | Emitido en | Uso en WinApp/Web |
| --- | --- | --- | --- |
| `tab.state` | `TabState` (ver tipos-b, «DTO de `tab`») | `AC/TabService.swift:1245` (`markChanged`, coalescido por turno) | `Web/tab/store.js:241`: `apply` si hay tema abierto |
| `tab.progress` | `TabProgressEvent` (ver tipos-b, «DTO de `tab`») `{state, track: String, fraction: Double (0...1), error: String?}` (`state`: transcribing, done, failed, cancelled; `track` = id de pista) | `TabService.swift:434, 439, 462, 500, 509` | `Web/tab/store.js:242-251`: actualiza la pista en sitio (done->ready, cancelled->queued) |
| `tab.selection` | `TabSelectionEvent` (ver tipos-b) (`bar`, `fraction`; `bar:-1` = sin selección) | `TabService.swift:550, 556` | `Web/tab/store.js:252` -> `setSelection` del lienzo |
| `tab.range` | `TabRangeEvent` (ver tipos-b) `{startBar: Int, startFraction: Double, endBar: Int, endFraction: Double}`; todo -1/0 = sin tramo | `TabService.swift:632, 634` | `Web/tab/store.js:253` -> `setRange` |
| `tab.songsterr.state` | `SongsterrSheetState` (ver tipos-b, «DTO de Songsterr») | `AC/TabSongsterr.swift:437` (solo con hoja abierta) | `Web/tab/songsterr-sheet.js:48` (solo con la hoja montada) |

No hay evento de cursor de la tablatura: se usa `study.position` (máx. 30 por segundo, `AC/StudyMethods.swift:11`, emitido en `:468`) -> `Web/tab/store.js:255-262` (`setCursorTime`). El transporte (play, posición, bucle) es de `study.*` (`backing/store.js`).

### 5.4 Canal del lienzo alphaTab (fuera del puente)

JS->vista: `ready {alphaTab: String}`, `rendered`, `beatClick`, `beatDrag`, `noteClick` (trae además `fret: Int`, que se descarta al reenviar), `cursor {bar, x, y}` (px de la página), `error {message}` (`Web/tab/store.js:61-83`, `Web/tab/frame.js:30`). Vista->JS: `load(json, trackIndex)`, `setCursorTime`, `setSelection`, `setRange`, `exportGpBase64`; existen además `selectTrack(index)` y `setCursor(bar, fraction, follow)` en `window.TF`, que el flujo de la pantalla no usa (`Web/tab/frame.js:99-119`).

### 5.5 Orden de llamadas por flujo

**Abrir**
1. `study.open {projectId}` si el estudio no es ya el del tema (`Web/tab/store.js:159`). `tab.open` también lo hace por dentro (`TabService.swift:158`): la llamada del cliente es redundante, pero deja listo el transporte compartido.
2. `tab.open {projectId}` -> `TabState` (`store.js:162`). Fases: `waitingAnalysis`, `empty`, `choosingSource`, `working`, `ready`, `failed` (`TabService.swift:46`).
3. `choosingSource`: `tab.songsterr.open` (flujo Songsterr). `waitingAnalysis`: al llegar el análisis (`study.analysis.state == ready`) repetir `tab.open` (`Web/screens/tab.js`).
4. Con `working` o `ready` y pistas `queued`: `tab.transcribe {}` una vez por pista (`store.js:98-108`). Ver D10.
5. Con una pista `ready`: `tab.selectTrack` si `selectedTrack` no está lista (`:118`), `tab.score {track}` (`:123`) y `load(json, índice)` en el lienzo (`:142`). Se repite al cambiar `revision` o el conjunto de pistas listas (`:110-120`).
6. Eventos activos: `tab.state`, `tab.progress`, `tab.selection`, `tab.range`, `study.position`.

**Transcribir**
1. `tab.transcribe {track?}` -> `TabQueuedResult`; la fase debe ser `ready`.
2. Eventos `tab.progress` `transcribing` (fracción), luego `done` o `failed`; `tab.state` con `transcription` por pista.
3. Con `done` la pista pasa a `ready`; el cliente pide `tab.score` cuando el `tab.state` trae `revision` nueva.
4. Cancelar: `tab.cancel` -> `tab.progress cancelled` (la pista vuelve a `queued`); el cliente la marca como pedida para no relanzarla (`store.js:224-228`).

**Editar**
1. `tab.edit {op:"editMode", on:true}` (`store.js:214`). La barra solo aparece con `editMode` y fase `ready`.
2. Clic en el lienzo: `tab.beatClick` / `tab.noteClick` / `tab.beatDrag` -> `TabState` + evento `tab.selection`.
3. Operaciones: `tab.edit {op:"digit"|"moveString"|"delete"|"duration"|"hit"|"ornament"|"addNote"|"move"|"tuning"}`.
4. Cada edición emite `tab.state` con `revision` nueva; el cliente pide `tab.score` y recarga el lienzo.
5. Teclado: `tab.edit {op:"key", key, shift, ctrl, alt}` con `KeyboardEvent.key` (`Web/tab/keys.js:22`); la respuesta trae `handled`.

**Deshacer / rehacer**
1. `tab.edit {op:"undo"}` / `{op:"redo"}`; botones deshabilitados con `!canUndo` / `!canRedo` (`Web/screens/tab.js:255-256`).
2. Misma cadena que una edición: `tab.state` con `revision` nueva -> `tab.score` -> `load`.

**Exportar `.gp`**
1. `exportGpBase64` en el lienzo (alphaTab genera los bytes; `Web/tab/frame.js:118`).
2. `tab.export {data}` sin `path`. El núcleo llama al anfitrión `saveFile(suggestedName, ["gp"])` (`TabService.swift:1223-1226`); si da `nil`, responde `saved:false`.
3. El «Guardado X.gp.» (`TabService.swift:1231`) llega como `flash` del siguiente `tab.state`; el fallo lo pinta el cliente (`flashLocal`, `store.js:236`).
4. Alternativa de Flutter: diálogo propio y `path` explícito (D6).

**Cargar de Songsterr**
1. `tab.songsterr.open` -> `SongsterrSheetState` (`stage: choosing`; `search.phase` idle, searching, results, failed).
2. Eventos `tab.songsterr.state` con `results`.
3. `tab.songsterr.select {songId}` (lee pistas) o `tab.songsterr.link {link}`; opcional `host.preview.show {url: String, x: Double, y: Double, width: Double, height: Double}` -> `{shown: Bool}` (`host.preview.hide` -> `{hidden: Bool}`; Resuelto: píxeles lógicos y en Flutter no coloca nada (decisiones-interfaz.md)) (`Web/tab/songsterr-sheet.js:89`) y `host.preview.hide` al cerrar.
4. `tab.songsterr.use` -> `stage: working` -> `pairing` (o `failed` + `retryImport` / `back`).
5. En `pairing`: `assign`, `allAutomatic`, `back`.
6. `tab.songsterr.accept` -> `TabState`; el cliente cierra la hoja, aplica el estado y lanza `tab.transcribe` de las `queued`. Alternativa: `tab.songsterr.automatic`.
7. La lectura de páginas usa el navegador oculto del anfitrión (`HiddenPageLoading.load`, `AC/TabSongsterr.swift:67`): ver D7.

## 9. Desvíos detectados

Clasificación según `docs/flutter/desvios.md:1-15`.

| # | Desvío | Evidencia SwiftUI | Qué hay en AppCore / Web | Clasificación |
| --- | --- | --- | --- | --- |
| D1 | Errores de alphaTab (`webError`) sin método en AppCore: el lienzo avisa de fallos de carga o JS y el pie muestra «alphaTab: …». | `App/TabController.swift:93, 649, 685` | No hay `tab.*` para ello. En la web es estado local (`Web/tab/store.js:27, 64`; `Web/screens/tab.js:220`). Estado de vista que no necesita persistir. | **interfaz** (Dart). Registrarlo en el núcleo sería un método nuevo: Resuelto: Dart lo muestra en el aviso de la pantalla (mensaje genérico traducido + texto de la página como detalle) (decisiones-interfaz.md) |
| D2 | Ctrl+Y rehacer solo existe en la web. | Mac solo ⇧⌘Z (`App/TabController.swift:1082`) | Núcleo: Ctrl+Mayús+Z en `handleKey` (`AC/TabService.swift:947`); Ctrl+Y es mapa de teclas de plataforma que la web traduce a `tab.edit {op:"redo"}` (`Web/tab/keys.js:19`). | **interfaz**: Flutter repite la tecla en Dart sin lógica de negocio |
| D3 | Cursor calculado en la vista con temporizador de 0,05 s. | `App/TabScreen.swift:57, 110-114`; `updateCursor` `App/TabController.swift:698` (umbral 1 ms) | Núcleo: `study.position` a 30 Hz máx. (`AC/StudyMethods.swift:11, 468`); la web lo consume sin temporizador (`Web/tab/store.js:255-262`). Mac 20 Hz frente a 30 Hz del núcleo. | **interfaz**: Resuelto: Flutter usa `study.position` (30 Hz del núcleo) interpolado en un `Ticker` por fotograma, sin temporizador propio (decisiones-interfaz.md) |
| D4 | Teclas por `keyCode` en SwiftUI y por `KeyboardEvent.key` en el núcleo (teclados no US). | `App/TabController.swift:1076-1096` (`keyCode` 53, 51, 117, 123-126; `charactersIgnoringModifiers`) | `AC/TabService.swift:941-975` ya trabaja con `key`. Flutter debe enviar el carácter lógico (`LogicalKeyboardKey.keyLabel`), no la tecla física. Ningún test usa un teclado no US. | **interfaz**; validar con teclado no US: pendiente de Jorge |
| D5 | Etiqueta «Fuente» calculada en cliente. | `App/TabController.swift:375-381`; `App/TabScreen.swift:162` | `TabState.source` = `songsterr`, `automatic` o ausente; la web lo traduce en `Web/screens/tab.js:77` con los mismos textos que Mac («Songsterr», «Transcripción automática», «Sin elegir»). | **interfaz** (clave ARB). Sin desvío de comportamiento |
| D6 | Exportación `.gp`: Mac abre `NSSavePanel` y escribe en la vista; el núcleo pide `saveFile` al anfitrión si no hay `path`, y WinApp y webdev no lo implementan. | `App/TabController.swift:1317-1347` (panel `:1327-1334`, escritura `:1339-1346`) | `AC/TabService.swift:1223-1228` (`saveFile` -> `nil` -> `saved:false`); `docs/flutter/contrato-anfitrion-hilos.md:57, 146`. La web llama sin `path` (`Web/tab/store.js:235`): en Windows hoy no guarda. | Resuelto (a): Dart abre el diálogo con `file_selector` (`getSaveLocation`) y llama a `tab.export` con `path`; no se implementa `saveFile` en el anfitrión (decisiones-interfaz.md) |
| D7 | Songsterr oculto: UA de Safari, sondeo cada 250 ms, tope de 30 s, una carga a la vez. | `App/SongsterrWebLoader.swift` (Mac; los valores se copiaron al núcleo, `AC/TabSongsterr.swift:69-79`) | **El núcleo fija los valores** (`loadTimeout = 30`, `pollMillis = 250`, `readyScript`, `userAgent`, `:69-79`) y los pasa en `HiddenPageLoading.load(url,userAgent,readyScript,timeout)` (`:67`). **El anfitrión ejecuta** el sondeo y el tope y serializa las cargas (contrato punto 5, `:55`; el núcleo puede lanzar dos). El cliente Dart no interviene. | **requisito de anfitrión**, no hueco de núcleo ni decisión: comprobar que WinApp (`tfhost_hidden_load`) y el anfitrión Flutter cumplen los puntos 1-6 del contrato (`:48-56`). El UA de Safari en un WebView de Windows lo puede ignorar el anfitrión (`:75-76`) |
| D8 | El lienzo no usa el SoundFont (`enablePlayer=false`). | `App/Resources/alphaTab/tf-bridge.js:400`; Bravura por `fontDirectory` `:397` | El audio lo da el sintetizador del núcleo (`ProductionTabSynth`, `AC/TabTranscribing.swift:75`). | **sin desvío** (diseño). Nota para el port: no cargar SoundFont en el WebView de Flutter |
| D9 | Los eventos del lienzo (`beatClick`, `beatDrag`, `noteClick`) se reenvían a `tab.*` con coalescencia en cliente (una petición viva de arrastre; `shift` descartado en `noteClick`). | `App/TabWebHost.swift:66-83` | `Web/tab/store.js:60-83`. Es política de transporte, no de negocio. | **interfaz** |
| D10 | `tab.open` deja las pistas en `queued` y no transcribe: el cliente debe llamar a `tab.transcribe {}`, tras `open`, `accept` y `automatic`. En Mac `start()` las transcribe sola. | `App/TabController.swift:181-187` (`start` -> `open()` -> cola) | `AC/TabService.swift:231-262` (`load()` no arranca la cola; solo `transcribe` crea `work`, `:412`). El cliente web lo suple en `Web/tab/store.js:98-108` con un conjunto `requested`, y `Web/tab/songsterr-sheet.js:66` tras `accept`. Es regla de cuándo arrancar el trabajo, que va en el núcleo (`desvios.md:11`, regla 5). | **hueco claro**: `tab.open`, `tab.songsterr.accept` y `tab.songsterr.automatic` deberían arrancar la cola como el Mac. Resuelto: va en el núcleo (decisiones-interfaz.md) |
| D11 | La hoja de Songsterr se cierra en el cliente tras `accept` y `automatic` porque devuelven `TabState`, sin `SongsterrSheetState`. | `App/TabController.swift:589-592` (`closeSourceSheet`) | `Web/tab/songsterr-sheet.js:62-68` pone `sheet = null`. `tab.songsterr.state` no emite `open:false` en esos casos. | **interfaz** (cerrar la hoja es estado de vista) |
| D12 | Métodos sin uso en Windows: `tab.state`, `tab.select`, `tab.exportName`, `tab.songsterr.state`, `tab.songsterr.search`. | n/a | `grep` en `Web/`: ningún `call`. `tab.exportName` sirve para D6. | **informativo** |

### Pendientes de Jorge (no son hallazgos)

- Teclado no US: probar `-`, `+`, `=`, dígitos y Alt+Y con distribución española o alemana (D4).
- Cursor (D3): resuelto, `study.position` interpolado en un `Ticker` (decisiones-interfaz.md); Jorge lo mira en la revisión de la ola 2.
- Vista previa de Songsterr (`host.preview.*`): resuelto, es un `TfWebView` dentro de la hoja, sin panel nativo superpuesto (decisiones-interfaz.md); se comprueba con pantalla real en la ola 2.
