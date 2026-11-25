# Contrato del puente (AppCore) para la interfaz Flutter

Contenido: introducción, recuento, tablas de métodos y eventos de todas las áreas (fichero:línea del `register`/`emit`) y apéndice de tipos de `app`, `host`, `library`, `import`, `jobs`, `settings`, `models`, `video.settings`. El resto de tipos, los servicios de anfitrión y los hilos están en `contrato-tipos-a.md`, `contrato-tipos-b.md`, `contrato-tipos-c.md` y `contrato-anfitrion-hilos.md`. Fuente complementaria: `Temp/win/step8-contract.md` (pasos 8.x; manda el código).

Rutas de código: `Packages/AppCore/Sources/AppCore/` (abreviado `AC/`).

## Recuento real

- Métodos: **192** (`grep -rhoE 'register\("[a-zA-Z.]+"'` en AC/ = 192 líneas, 192 nombres únicos). Coincide con la estimación.
- Eventos: **31 nombres literales** de `emit("...")` + `frames.<canal>` dinámico (canales con relevo: `camera`, `montage`) = 32 familias. La estimación (27) se queda corta. Los eventos `host.filesDropped` y similares los emite el anfitrión, no AppCore.
- Incoherencia con `arquitectura.md`: habla de canales `camera`, `preview`, `montage`; en el núcleo `video.preview.*` reutiliza el canal `camera` (`AC/RecordMethods.swift:712`, `cameraChannel = "camera"` en `:224`). No existe canal `preview`.
- Incoherencia con `arquitectura.md` regla 6 (`{code, message, args}`): `RPCError` hoy solo tiene `code` y `message` (`AC/Router.swift:4-11`; sobre de error en `:96-106`). No hay `args`.

## Introducción

- Petición `{"id":Int,"method":"ns.nombre","params":{...}}`; `params` ausente = `{}` (`AC/Router.swift:74`). `id` debe ser entero (`:66-68`).
- Respuesta `{"id":N,"result":...}` o `{"id":N,"error":{"code","message"}}` (`:81`, `:102-106`). El `result` es el JSON del DTO devuelto.
- Evento `{"event":"nombre","payload":...}` (`AC/Router.swift:90-94`); lo emite `Bridge.emit` (`AC/Bridge.swift:129`) o el `emit` privado de cada servicio (Audio, Study, Tab, TakeView, Settings, Record, Montage) que acaba en `Bridge.send`.
- `Empty` = `{}` (`AC/Router.swift:14`), parámetros y resultado vacíos.
- Registro: `Router.register<P: Decodable&Sendable, R: Encodable&Sendable>(_ method, handler)` (`AC/Router.swift:41`); cada servicio expone `register(on: Router)` y `Bridge.registerMethods` los encadena (`AC/Bridge.swift:133-188`).
- Codificación: encoder `iso8601` (sin fracciones: `2026-01-02T03:04:05Z`) y `withoutEscapingSlashes` (`AC/Router.swift:28-39`). `UUID` sale en mayúsculas. Un `Optional` nil de un DTO sintetizado **se omite** (clave ausente, no `null`); solo salen `null` los DTO con `encode(to:)` a mano (`encode` sobre el opcional) y los construidos con `SJ` (`AC/SettingsMethods.swift:155-181`). Dart debe tratar «ausente» y `null` igual al decodificar.
- Regla general en los DTO de Dart: una clave ausente y un `null` se leen igual; al enviar, Dart omite la clave.
- Rutas de medios (`cover`, `audio`, `video`, `path`...): relativas a la carpeta de proyectos con `/`.

### Códigos de `RPCError` que existen (literales `code:`)

Router: `bad-json` (`Router.swift:64`), `bad-request` (`:68`), `unknown-method` (`:72`), `bad-params` (`:47`, `:77` y en cada método), `internal` (`:85`). Bridge: `no-projects-folder` (`Bridge.swift:208`, `:212`), `not-found` (`:171`, `LibraryMethods.swift:178`), `bad-params` (`:167`), `internal` (`:200`). Import/cola: `unsupported` (`ImportMethods.swift:236`, `:312`; `JobQueue.swift:264`), `busy` (`JobQueue.swift:334`, `:397`; `SettingsMethods.swift:402`), `cancelled` (`:369`), `empty-title` (`:374`), `unsafe-deletion` (`:376`), `work-in-progress` (`:378`), `delete-failed` (`:356`), `trash-failed` (`:358`). Ajustes: `model-failed` (en `models.changed.error`, `SettingsMethods.swift:391`). Los códigos de Link, Study, Tab, Record, TakeView, Montage, Audio (`not-open`, `audio-unavailable`, `load-failed`, `offline`, `unsupported-link`, etc.) están por inventariar: `grep -rn 'RPCError(code:' AC/`.

## Áreas

Formato: método · params · result · register · qué hace.

### app

| método | params | result | register | qué hace |
|---|---|---|---|---|
| app.info | Empty | AppInfo | Bridge.swift:138 | versión, plataforma, mediaBase, carpeta de proyectos, argumentos de arranque y lista viva |

### host

| método | params | result | register | qué hace |
|---|---|---|---|---|
| host.pickAudioFile | Empty | PickedFileResult | ImportMethods.swift:204 | selector de un fichero wav/flac/mp3 |
| host.pickAudioFiles | Empty | PickedFilesResult | ImportMethods.swift:209 | selector múltiple |
| host.openURL | OpenURLParams | OpenURLResult | ImportMethods.swift:216 | abre la primera URL spotify/http/https que el sistema acepte |
| host.preview.show | PreviewShowParams | PreviewShowResult | ImportMethods.swift:226 | panel nativo de Songsterr sobre la ventana |
| host.preview.hide | Empty | PreviewHideResult | ImportMethods.swift:240 | oculta ese panel |
| host.chooseFolder | Empty | ChosenFolderResult | ImportMethods.swift:245 | selector de carpeta (no aplica) |
| host.pickProjectsFolder | Empty | PickedFolderResult | ImportMethods.swift:273 | elige y guarda la carpeta de proyectos |

Sin `bridge.host` todos dan `unsupported` (`ImportMethods.swift:311`). Las tablas de eventos de `host` no existen en AppCore (`host.filesDropped` es del anfitrión web).

### library

| método | params | result | register | qué hace |
|---|---|---|---|---|
| library.list | Empty | LibraryListResult | Bridge.swift:147 | resúmenes ordenados por título, con estado vivo de la cola |
| library.project | ProjectIDParams | ProjectDetailResult | Bridge.swift:176 | detalle de un tema |
| library.reveal | ProjectIDParams | RevealResult | Bridge.swift:165 | abre la carpeta en el explorador |
| library.takeBacking | TakeBackingParams | TakeBackingResult | Bridge.swift:182 | pistas de acompañamiento de Ver toma |
| library.artistPhoto | ArtistPhotoParams | ArtistPhotoResult | ArtistPhotoMethods.swift:33 | foto como URL `data:` o `null` explícito (el DTO tiene `encode(to:)` a mano: la clave sale siempre) |
| library.separate | ProjectIDParams | QueuedResult | ImportMethods.swift:180 | encola separación y análisis |
| library.rename | RenameParams | RenameResult | ImportMethods.swift:184 | cambia título y artista |
| library.deleteTake | DeleteTakeParams | RemovedResult | ImportMethods.swift:189 | borra una toma |
| library.trash | ProjectIDParams | RemovedResult | ImportMethods.swift:195 | tema a la papelera; antes cierra la sesión del tema abierto (`Bridge.closeProjectFilesIfOpen`, 71a46fa) |
| library.delete | ProjectIDParams | RemovedResult | ImportMethods.swift:199 | borra del disco; también cierra antes la sesión del tema abierto (71a46fa) |
| library.markBest | MarkBestParams `{id, takeId}` (Swift: `DeleteTakeParams`) | `{marked: true}` | ImportMethods.swift:204 (71a46fa) | fija la mejor toma de su parte sin sesión de Grabar; avisa al estudio si el tema está abierto |
| library.relocate | RelocateParams | RelocateResult | ImportMethods.swift:251 | mueve o reapunta la carpeta de proyectos |
| library.usage | Empty | SJ (objeto) | SettingsMethods.swift:289 | uso de disco |
| library.cleanupInfo | OptionalIDParams | CleanupInfoResult | SettingsMethods.swift:290 | bytes que liberaría limpiar |
| library.cleanup | OptionalIDParams | CleanupResult | SettingsMethods.swift:291 | limpia (id nulo = toda la biblioteca) |

Eventos:

| evento | payload | emit | cuándo |
|---|---|---|---|
| library.changed | Empty | ImportMethods.swift:166 | tras cambios de tema, fin de trabajos, rename, borrado; sin límite de frecuencia |
| library.relocateProgress | RelocateProgress | ImportMethods.swift:264 | durante `library.relocate` con `move` |
| library.relocated | RelocateResult | ImportMethods.swift:269 | al terminar `library.relocate` |

### import / jobs

| método | params | result | register | qué hace |
|---|---|---|---|---|
| import.file | ImportFileParams | ImportResult (JobQueue.swift:259) | ImportMethods.swift:175 | importa wav/flac/mp3; duplicado no es error |
| jobs.list | Empty | JobsListResult | ImportMethods.swift:176 | trabajos vivos |
| jobs.cancel | ProjectIDParams | CancelResult | ImportMethods.swift:177 | cancela separación |

| evento | payload | emit | cuándo |
|---|---|---|---|
| jobs.progress | JobInfo | ImportMethods.swift:165 (origen `JobQueue.swift:175`) | cambios de etapa/estado siempre; fracción como mucho 4/s por trabajo (`progressInterval = 0.25`, `JobQueue.swift:27`) |

### link (incluye tools)

| método | params | result | register | qué hace |
|---|---|---|---|---|
| link.classify | LinkURLParams | LinkClassifyResult | LinkMethods.swift:431 | clasifica una URL |
| link.resolve | LinkURLParams | (engine.resolve) | LinkMethods.swift:432 | resuelve título y candidatos |
| link.cancel | LinkCancelParams | (inline) | LinkMethods.swift:433 | cancela resolución o descarga |
| link.search | LinkSearchParams | (engine.search) | LinkMethods.swift:437 | búsqueda en Spotify |
| link.addManual | LinkAddManualParams | (engine.addManual) | LinkMethods.swift:438 | añade vídeo de YouTube a candidatos |
| link.import | LinkImportParams | (engine.startImport) | LinkMethods.swift:439 | encola descarga |
| tools.info | Empty | ToolsInfoResult | LinkMethods.swift:441 | versiones de yt-dlp, deno, ffmpeg |
| tools.updateYtDlp | Empty | UpdateYtDlpResult | LinkMethods.swift:442 | actualiza yt-dlp |
| tools.revertYtDlp | Empty | RevertedResult | LinkMethods.swift:450 | vuelve a la embebida |

Evento: `link.finished` · payload (LinkFinished, `LinkMethods.swift:331` vía sink `:427`) · uno por cada `link.import` al terminar.

### playlist

Todos en `PlaylistMethods.swift`: `playlist.state` :394 (Empty), `playlist.select` :395 (PlaylistSelectParams), `selectAll` :401, `selectNone` :402, `choose` :403 (PlaylistChooseParams), `skip` :415 (PlaylistItemParams), `continue` :421, `search` :422, `start` :423, `cancel` :424, `resume` :425, `updateAndRetry` :426, `retryFailed` :427, `close` :428 (PlaylistCloseParams `{force?}`). Resultado: `PlaylistSnapshot` (también en `AppInfo.playlist`), salvo `playlist.close`, que devuelve `PlaylistCloseResult`. Evento `playlist.changed` · PlaylistSnapshot · `PlaylistMethods.swift:387` (sink; `:339` envío del motor).

### models, settings, video (ajustes)

| método | params | result | register | qué hace |
|---|---|---|---|---|
| settings.get | Empty | SJ | SettingsMethods.swift:288 | carpeta de proyectos, activa, vídeo |
| models.list | Empty | SJ | :292 | lista (solo BS-RoFormer) |
| models.download | ModelIDParams | SJ `{started}` | :293 | inicia descarga |
| models.delete | ModelIDParams | SJ | :294 | borra |
| video.cameras | Empty | SJ | :295 | cámaras y formatos |
| video.settings | Empty | SJ | :296 | ajustes de vídeo |
| video.setSettings | SetVideoParams | SJ | :297 | cambia lo que venga |
| video.preview.start / stop | Empty | CameraPreviewResult | CameraPreview.swift:80-81 | vista previa de cámara |
| video.openCameraPrivacy | Empty | CameraPrivacyResult | CameraPreview.swift:82 | abre privacidad del sistema |

| evento | payload | emit | cuándo |
|---|---|---|---|
| models.progress | ModelProgress | SettingsMethods.swift:387 | un punto porcentual como mucho |
| models.changed | SJ `{models,error}` | :394 | fin de descarga (éxito o fallo) |
| video.camerasChanged | Empty | :303 | conecta/desconecta cámara |

### audio

`audio.devices` AudioMethods.swift:257 · `audio.settings` :260 · `audio.setSettings` :263 (AudioSetSettingsParams) · `audio.state` :266 · `audio.setMeters` :269 (AudioMetersParams) · `audio.calibrate` :276 · `audio.cancelCalibration` :281 · `audio.dismissCalibration` :288. Eventos (`AudioMethods.swift`): `audio.levels` :225, `audio.calibration` :229, `audio.devicesChanged` :233, `audio.state` :250.

### frames

`frames.stats` (FrameStatsParams → FrameRelayStats) `FrameRelay.swift:250`. Evento `frames.<canal>` (JPEG) `FrameRelay.swift:197`, canales `camera` (`RecordMethods.swift:706,712`; 15 fps) y `montage` (`MontageMethods.swift:774`; 60 fps con `latestWins`).

### study

Métodos (`StudyMethods.swift`): open :233, close :234, play :235, pause :238, seek :239, setRate :242, setTranspose :245, setCapo :251, setLoop :254, setMix :259, setMaster :266, setMetronome :269. Ediciones (`StudyEdits.swift`): snapshot :122, analyze :123, setKey :124, setChord :125, removeChordOverrides :126, clearChordOverrides :134, splitChord :137, markSection :138, updateSection :139, previewSectionEdge :142, nudgeSectionEdge :145, deleteSection :152, applySections :158, discardSections :164, renameGuitar :167, setGuitarStereo :176. Resultados: `StudyOpenResult`, `StudyTransport`, `StudyEditState`, `StudyPreviewSections`. Eventos: `study.state` StudyMethods.swift:380, `study.position` :468, `study.levels` :477, `study.analysis` StudyEdits.swift:315, `study.guitars` :399.

### tab y tab.songsterr

`TabMethods.swift`: open :7, state :8, close :12, setSource :13, score :15, selectTrack :16, transcribe :20, cancel :21, beatClick :22, beatDrag :26, noteClick :30, select :34, span :37, toggleMute :38, toggleSolo :43, setListening :48, setAllListening :54, edit :58, exportName :59, export :60. `TabSongsterr.swift`: open :762, state :763, close :764, search :765, retry :766, select :767, link :770, use :773, review :774, retryImport :775, back :776, assign :777, allAutomatic :780, accept :781, automatic :782. Eventos: `tab.progress` TabService.swift:434,439,462,500,509; `tab.selection` :550,556; `tab.range` :632,634; `tab.state` :1245; `tab.songsterr.state` TabSongsterr.swift:437.

### record

`RecordMethods.swift`: open :262, close :263, state :264, start :265, stop :272, cancel :273, selectPart :274, addPart :282, setStartSection :293, setCountIn :303, setPreRoll :304, setPunch :312, startPunch :324, selectTake :327, markBest :332, deleteTake :335, setCamera :338, rotate :341, adjustOffset :342, setOffset :350, finishOffset :357, setMix :361, setMaster :364, prepareViewTake :367. Eventos: `record.state` :531, `record.position` :573, `record.levels` :581.

### takeview

`TakeViewMethods.swift`: open :258, openOffset :259, close :260, snapshot :261, play :262, pause :268, seek :269, setBacking :273. Evento: `takeview.position` :500 (lleva también `rate`).

### montage

`MontageMethods.swift`: open :366, close :367, snapshot :368, setLayout :369, setSingleRhythm :375, setCutGaps :379, moveLane :380, setPartOrder :384, setCaption :388, setShowPartLabels :389, setKeepVideoAspect :392, addCut :395, moveCut :396, setCutPart :400, removeCut :404, clearCuts :408, setExport :409, setFraming :433, resetFraming :446, reanalyze :450, rotateTake :454, framingFrame :458, play :461, pause :464, seek :465, setPreviewFps :469, startExport :473, cancelExport :482, dismissExport :483, reveal :484. Eventos: `montage.state` :696, `montage.export` :706, `montage.framing` :715, `montage.position` :743.

## Apéndice Tipos

### app
`AppInfo` (`Bridge.swift:5`): `version: String`, `platform: String` ("macos"/"windows"), `mediaBase: String`, `projectsFolder: String?`, `proposedProjectsFolder: String` (carpeta que el núcleo propone en el primer arranque, por plataforma: `~/Music/ToneForge` en Mac, Known Folder Music\ToneForge en Windows; la misma que usa `host.pickProjectsFolder`, 83f61a5), `launch: {screen: String?, project: String?, snapshot: Bool}`, `playlist: PlaylistSnapshot?`. Opcionales nil = clave ausente.

### library
- `ProjectSummary` (`LibraryMethods.swift:6`): `id: UUID`, `title`, `artist: String?`, `folderName`, `duration: Double`, `sampleRate: Double`, `cover: String?`, `createdAt: Date`, `updatedAt: Date` (ISO-8601 sin fracción), `separationState: String` (`none|queued|running|done|failed`, rawValue de Store), `separationError: String?` (texto del fallo guardado; `null` en cola o corriendo; si el fallo es vivo, la interfaz usa `jobs.progress.error`; 71a46fa), `stemCount`, `takeCount`, `rigCount: Int`, `hasAnalysis: Bool`, `origin: String?` (`youtube|spotify`), `guitars: [String]`. Sin CodingKeys.
- `SkippedInfo` :27 `{folderName, reason}`. `LibraryListResult` :32 `{projects, skipped}`.
- `StemInfo` :37 `{kind: String (bass|drums|other|vocals|guitar|piano), bytes: Int64, isEmpty}`.
- `TakeInfo` :43 `{id: UUID, number: Int, createdAt: Date, discarded, isBest, hasVideo: Bool, punchCount: Int, duration: Double?, audio: String?, video: String?, songStart: Double?, videoOffsetMs: Double?, videoRotation: Int, punches: [TakePunchInfo]}`.
- `TakePunchInfo` :64 `{start, end: Double, videoPath: String?, videoOffsetMs: Double?}`.
- `PartInfo` :92 `{id: UUID, name, isLead: Bool, takes}`.
- `ProjectDetailResult` :100: codificación a mano **aplanada**: las claves de `ProjectSummary` más `separationError: String?` (aquí con `encode`: sale `null` si nil), `stems`, `parts`, `videoCount: Int` (`:114-121`).
- `TakeBackingParams {id, takeId: String}`, `TakeBackingResult` :73 `{takeStart: Double, takeVolume: Double (lineal), tracks: [{kind, path, volume: Double, mutedSpan: MontageRangeInfo?}]}`.
- `ProjectIDParams {id: String}` (UUID como cadena; no-UUID da `bad-params`). `RevealResult {revealed}`.
- `ArtistPhotoParams {name}`; `ArtistPhotoResult {photo: String?}` con `encode` a mano (`null` si nil): `data:image/(png|webp|jpeg);base64,...` (`ArtistPhotoMethods.swift:16-22,43-47`).

### import / jobs / host (`ImportMethods.swift:57-108`)
- `ImportFileParams {path}`; `ImportResult {id: String, duplicate: Bool}`.
- `RenameParams {id, title, artist: String?}`; `RenameResult {id, title, artist}` (`artist` siempre presente, `null` si vacío).
- `CancelResult {cancelled}`, `QueuedResult {queued}`, `RemovedResult {removed}`, `DeleteTakeParams {id, takeId}`.
- `CleanupInfoResult {bytes: Int64}`, `CleanupResult {cleaned: Bool, bytes: Int64}`; `OptionalIDParams {id: String?}`.
- `PickedFileResult {path: String?}` (null explícito), `PickedFilesResult {paths: [String]}`, `ChosenFolderResult {path: String?}` (null explícito), `PickedFolderResult {path: String?, restartRequired: Bool}` (null explícito).
- `OpenURLParams {urls: [String]}`, `OpenURLResult {opened: String?}` (ausente si nil). `PreviewShowParams {url, x, y, width, height}`; `PreviewShowResult {shown}`; `PreviewHideResult {hidden}`.
- `RelocateParams {path, mode: "move"|"point"}`, `RelocateProgress {fraction}`, `RelocateResult {path, mediaRemapped: Bool}`.
- `JobInfo` (`JobQueue.swift:6`): `id: String` (UUID del tema, `import-N`, `link-N` o `playlist-<id de tema de la lista>`), `title`, `stage` (`import|separation|guitars|analysis|download`), `state` (`queued|running|done|failed|cancelled`), `fraction: Double?` (ausente si nil), `text: String`, `error: String?`. `JobsListResult {jobs}`.

### settings / models / video
Salen como objetos `SJ` con `null` explícito (`SettingsMethods.swift:314-473`); no hay DTO Codable. Claves:
- `settings.get`: `projectsFolder`, `activeProjectsFolder` (String|null), `video`.
- `library.usage`: `totalBytes`, `regenerableBytes` (Int), `projects[{id, folderName, bytes, regenerableBytes}]`.
- `models.list`: `models[{id, name, state (notInstalled|downloading|verifying|installing|installed|failed), fraction|null, bytes|null, archiveBytes, message|null, source ("store"|"folder"|null)}]`, `modelsBytes`. `models.changed`: `{models, error: null|{code:"model-failed", message}}`. `ModelProgress {id, fraction}`.
- `video.cameras`: `cameras[{id, name, kind, isDefault, resolutions[{width,height,label,fps[{value,label}]}]}]`, `defaultId|null`.
- `video.settings` (`:439-473`): `cameraUID|null`, `cameraConnected`, `cameraName|null`, `effectiveCameraId|null`, `noCamera`, `resolution{width,height,label}`, `fps`, `fpsLabel`, `shown|null{resolution,fps,fpsLabel}`, `offsetMs` (Int), `rotation` (Int), `offsetsMs{cameraId:Int}`, `rotations{cameraId:Int}`, `export{codec ("hevc"|"h264"), resolution, titleOverlay, exportStemWAVs, normalizeLUFS}`, `choices{codecs, exportResolutions, rotations, offsetRangeMs{min,max}}`.
- `SetVideoParams` (`:198-219`): decodificación a mano; `cameraUID` presente con `null` = «por defecto del sistema», ausente = no cambiar. Resto opcional: `resolution{width,height}`, `fps`, `offset{cameraId?, ms}`, `rotation{cameraId?, degrees}`, `export{codec?, resolution?, titleOverlay?, exportStemWAVs?}`.

### Pendientes (sin volcar)
Tipos de `link`, `playlist`, `audio`, `frames` y `video.preview`: `contrato-tipos-a.md`. Tipos de `study`, `tab` y `tab.songsterr`: `contrato-tipos-b.md`. Tipos de `record`, `takeview` y `montage`: `contrato-tipos-c.md`.

## Servicios de anfitrión

Ver `contrato-anfitrion-hilos.md`.

## Hilos

Ver `contrato-anfitrion-hilos.md`.
