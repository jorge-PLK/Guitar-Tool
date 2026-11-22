# Contrato de tipos A: link (con tools), playlist, audio, frames, video.preview

ESTADO: COMPLETO para las cinco áreas (34 métodos, 7 familias de evento, 49 tipos). Recuento: link 6 métodos + tools 3; playlist 14; audio 8; frames 1; video.preview 2. Eventos: `link.finished`, `playlist.changed`, `audio.levels`, `audio.calibration`, `audio.devicesChanged`, `audio.state`, `frames.<canal>`. Fuera de las cinco áreas pero en el mismo fichero: `video.openCameraPrivacy` (`AC/CameraPreview.swift:82`, `Empty` → `CameraPrivacyResult {opened: Bool}`, `:54`).

Rutas: `AC/` = `Packages/AppCore/Sources/AppCore/`. Convenciones de `contrato.md` (líneas 14-26): encoder `iso8601` sin fracciones (`AC/Router.swift:28`); un DTO sintetizado omite la clave si es nil; `null` solo con `encode(to:)` a mano (**en estas cinco áreas no hay ninguno**: todo opcional nil = clave ausente). Dart: ausente == `null`. Ningún DTO usa `CodingKeys`: clave JSON = nombre del campo Swift. Los números `Int`/`Double` salen como números JSON.

---

## link (incluye tools)

### Métodos

| método | params | result | register | qué hace |
|---|---|---|---|---|
| link.classify | LinkURLParams | LinkClassifyResult | `AC/LinkMethods.swift:431` | clasifica la URL sin leerla (síncrono, no falla) |
| link.resolve | LinkURLParams | LinkResolveResult | `:432` | resuelve título y candidatos de YouTube; si la URL es lista o álbum abre `playlist` y devuelve `playlist` relleno |
| link.cancel | LinkCancelParams | CancelledResult | `:433` | con `jobId` cancela esa descarga; sin él cancela la resolución viva (y la lectura de lista) |
| link.search | LinkSearchParams | LinkSearchResult | `:437` | busca temas en Spotify por texto |
| link.addManual | LinkAddManualParams | LinkAddManualResult | `:438` | añade un vídeo de YouTube pegado a mano a los candidatos de la última resolución |
| link.import | LinkImportParams | LinkJobResult | `:439` | encola la descarga (trabajo `link-N`) y vuelve; el progreso va por `jobs.progress`, el final por `link.finished` |
| tools.info | Empty | ToolsInfoResult | `:441` | versiones de yt-dlp, deno, ffmpeg |
| tools.updateYtDlp | Empty | UpdateYtDlpResult | `:442` | actualiza yt-dlp |
| tools.revertYtDlp | Empty | RevertedResult | `:450` | vuelve al yt-dlp embebido |

### Eventos

| evento | payload | emit | cuándo |
|---|---|---|---|
| link.finished | LinkFinished | `AC/LinkMethods.swift:427` (sink; `finish` en `:329-332`, llamadas `:353`, `:387`, `:390`, `:400`) | uno por cada `link.import` al terminar (ok, duplicado, error o cancelado) |

Las descargas se serializan (una a la vez, `LinkMethods.swift:299`). El `jobId` es `link-<N>` (`keyPrefix` + contador, `:296`).

### DTO (`AC/LinkMethods.swift`)

Params:
- `LinkURLParams` :9 `{url: String}`.
- `LinkCancelParams` :17 `{jobId: String?}`.
- `LinkSearchParams` :24 `{query: String}`.
- `LinkAddManualParams` :25 `{url: String}`.
- `LinkImportParams` :18 `{candidateId: String?, url: String?, title: String?, artist: String?}`. Hace falta `candidateId` (id de la última resolución) o `url` (solo vídeo de YouTube). `title`/`artist` sustituyen a los resueltos; `artist: ""` borra el artista (`:294`); `title` vacío se ignora (`:293`).

Results:
- `LinkClassifyResult` :11 `{kind: String, source: String?}`. `kind`: `playlist|track|unsupported`. `source`: `youtube|spotify`; ausente si `unsupported`.
- `LinkResolveResult` :80 `{link: String, pastedURL: String, title: String, artist: String?, album: String?, duration: Double?, thumbnail: String?, existing: LinkTrackInfo?, possibleDuplicate: LinkTrackInfo?, noCloseCandidate: Bool, candidates: [LinkCandidateInfo], playlist: PlaylistSnapshot?}`.
  - `link`: `youtube|spotify|playlist` (`playlist` solo en el desvío de lista, `PlaylistMethods.swift:166`). `duration` en segundos. `thumbnail` URL https.
  - Si `existing` viene, el tema ya está en la biblioteca: `candidates: []` y `noCloseCandidate: false` (`:233-235`). Si la resolución no trae datos: `title: ""`, `candidates: []` (`:237-239`).
  - `candidates`: el primero es la confirmación (`isClose: true`, `difference` ausente) si la hay (`:247-250`).
  - `playlist`: ver `PlaylistSnapshot` (sección playlist).
- `LinkCandidateInfo` :66 `{id: String, title: String, artist: String?, duration: Double?, thumbnail: String?, source: String, url: String, isClose: Bool, isLive: Bool, difference: Double?, inLibrary: LinkTrackInfo?}`. `id` = id de vídeo de YouTube. `source` siempre `"youtube"`. `duration` y `difference` en segundos (`difference` = diferencia de duración respecto al tema; ausente en la confirmación). `inLibrary` presente = ese vídeo ya está en la biblioteca (no seleccionable).
- `LinkTrackInfo` :59 `{id: String (UUID en mayúsculas), title: String, artist: String?}`.
- `LinkSearchResult` :44 `{query: String (recortado), tracks: [LinkSpotifyTrack]}`.
- `LinkSpotifyTrack` :28 `{id: String, name: String, artists: [String], album: String, year: Int?, durationText: String, imageURL: String?, trackURL: String, appURL: String}`. `durationText` ya formateado por SourceKit; `trackURL`/`appURL` son URL absolutas en cadena.
- `LinkAddManualResult` :49 `{added: String, selectable: Bool, resolution: LinkResolveResult}`. `added` = id del vídeo (ya primero en `resolution.candidates`); `selectable: false` si ya está en la biblioteca.
- `LinkJobResult` :57 `{jobId: String}`.
- `CancelledResult` :105 `{cancelled: Bool}` (`false` si el `jobId` no existe o no había resolución).
- `ToolsInfoResult` :108 `{ytDlpVersion: String?, ytDlpOrigin: String?, denoVersion: String?, ffmpegVersion: String?}`. `ytDlpOrigin`: `updated|embedded`.
- `UpdateYtDlpResult` :124 `{version: String, origin: String (updated|embedded), alreadyLatest: Bool}`. `alreadyLatest = (origin != updated)` (`:448`).
- `RevertedResult` :106 `{reverted: Bool}` (siempre `true` si no lanza).

Payload de evento:
- `LinkFinished` :96 `{jobId: String, id: String?, duplicate: Bool, notices: [String], error: Failure?}`. `id` = UUID del proyecto (importado o duplicado existente); ausente si hay `error`. `notices` = avisos no fatales de la descarga. Si se canceló, `error.code == "cancelled"`.
  - `Failure` :97 `{code: String, message: String}`; `message` = `"<título>\n<detalle>"` o solo título.

### Códigos de `RPCError` (link y tools)

- `bad-params`: `LinkMethods.swift:178` (resolve, url vacía), `:194` (search, query vacía), `:216` (addManual), `:286` (import: `url` no es YouTube), `:291` (import sin `candidateId` ni `url`).
- `not-found`: `:280` (import: `candidateId` no está en la última resolución).
- `cancelled`: `:207` (search cancelada). También en `link.finished.error`.
- `spotify-missing-credentials`, `spotify-rejected`, `spotify-rate-limited`, `spotify-offline`, `spotify-bad-response`: `:199-203` (de `SpotifySearchError`, emitidos en `:205`); `spotify-offline` también por defecto en `:209`.
- `internal`: `:452` (revertYtDlp).
- `no-projects-folder`: `Bridge.swift:208`, `:212` vía `Bridge.service` (llamada en `LinkMethods.swift:179`, `:270`).
- `resolve`, `addManual`, `updateYtDlp` y `link.finished.error` pasan por `SourceMessages.rpc` (`AC/LinkImportSession.swift:234-243`). Códigos de `SourceMessages.code(for:)` (`:209-231`; el `RPCError` se construye en `:236`): `offline`, `unsupported-link`, `spotify-unreadable`, `age-restricted`, `region`, `private-video`, `removed`, `no-audio-format`, `extractor-broken`, `ffmpeg-failed`, `helper-missing`, `launch-failed`, `http-status`, `timed-out`, `cancelled`, `checksum-mismatch`, `update-failed`, `rate-limited`, `no-audio-produced`. Los errores ajenos a SourceKit pasan por `JobEngine.map` (`AC/JobQueue.swift:367-383`): `cancelled` (:369), `not-found` (:373), `empty-title` (:374), `unsafe-deletion` (:376), `work-in-progress` (:378), `internal` (:380, :383).

---

## playlist

Flujo (de `PlaylistSnapshot.step`, `AC/PlaylistMethods.swift:255-264`): `link.resolve` con URL de lista/álbum abre la sesión y devuelve `step: tracks` dentro de `LinkResolveResult.playlist`; luego `continue` (→ `searching`/`review` según el motor), `search`, `start` (→ `running`), `cancel`/`resume` (→ `stopped`), `close`. Toda acción devuelve la instantánea posterior y además la emite como `playlist.changed` (sondeo cada 250 ms, solo si cambió, `:113`, `:337-340`).

### Métodos (todos en `AC/PlaylistMethods.swift`)

| método | params | result | register | qué hace |
|---|---|---|---|---|
| playlist.state | Empty | PlaylistSnapshot | :394 | instantánea actual |
| playlist.select | PlaylistSelectParams | PlaylistSnapshot | :395 | marca o desmarca un tema |
| playlist.selectAll | Empty | PlaylistSnapshot | :401 | marca todos |
| playlist.selectNone | Empty | PlaylistSnapshot | :402 | desmarca todos |
| playlist.choose | PlaylistChooseParams | PlaylistSnapshot | :403 | elige otro candidato de YouTube para un tema |
| playlist.skip | PlaylistItemParams | PlaylistSnapshot | :415 | quita el candidato del tema (no se descarga) |
| playlist.continue | Empty | PlaylistSnapshot | :421 | pasa del paso 1 (temas) al siguiente |
| playlist.search | Empty | PlaylistSnapshot | :422 | busca candidatos de YouTube para los marcados |
| playlist.start | Empty | PlaylistSnapshot | :423 | arranca la cola de descargas (un tema a la vez) |
| playlist.cancel | Empty | PlaylistSnapshot | :424 | para la cola |
| playlist.resume | Empty | PlaylistSnapshot | :425 | reanuda tras parada |
| playlist.updateAndRetry | Empty | PlaylistSnapshot | :426 | actualiza yt-dlp y reintenta (tras `extractor-broken`) |
| playlist.retryFailed | Empty | PlaylistSnapshot | :427 | reintenta los fallidos |
| playlist.close | PlaylistCloseParams | **PlaylistCloseResult** | :428 | cierra la lista; si hay trabajo vivo y no `force`, no cierra |

Nota: `contrato.md` dice que todos devuelven `PlaylistSnapshot`; `playlist.close` devuelve `PlaylistCloseResult`.

### Eventos

| evento | payload | emit |
|---|---|---|
| playlist.changed | PlaylistSnapshot | `AC/PlaylistMethods.swift:387` (sink) desde `tick` `:339` |

### DTO (`AC/PlaylistMethods.swift`)

Params:
- `PlaylistItemParams` :104 `{id: String}` (id de tema de la lista).
- `PlaylistSelectParams` :105 `{id: String, selected: Bool}`.
- `PlaylistChooseParams` :106 `{id: String, candidateId: String}`.
- `PlaylistCloseParams` :107 `{force: Bool?}` (ausente = `false`, `:428`).

Results:
- `PlaylistCloseResult` :108 `{closed: Bool, live: Bool}`. Sin sesión: `closed:false, live:false` (`:230`). Viva sin `force`: `closed:false, live:true`. Con `force` cancela la cola.
- `PlaylistSnapshot` :78 `{step: String, searchDone: Int?, searchTotal: Int?, error: PlaylistErrorInfo?, name: String, source: String, kind: String, mayBeTruncated: Bool, isLive: Bool, indicator: String?, totals: PlaylistTotalsInfo, summary: PlaylistSummaryInfo, progress: Double, update: PlaylistUpdateInfo, warnings: [String], items: [PlaylistItemInfo]}`.
  - `step`: `loading|tracks|searching|review|running|stopped|summary|error`.
  - `searchDone`/`searchTotal`: solo con `searching`. `error`: solo con `stopped` y `error`.
  - `source`: `spotify|youtube`. `kind`: `playlist|album`. `mayBeTruncated`: la lista puede estar cortada. `isLive`: hay trabajo en marcha o parado (la lista se conserva al cerrar la hoja). `indicator`: texto del indicador de Biblioteca. `progress`: 0...1 de la cola. `warnings`: avisos no fatales (p. ej. «No se pudo separar …», `:194`).
  - También viaja en `AppInfo.playlist` y en `LinkResolveResult.playlist`.
- `PlaylistItemInfo` :25 `{id: String, title: String, artist: String, duration: Double?, kind: String, selected: Bool, status: String, stage: String?, progress: Double?, error: PlaylistErrorInfo?, inLibrary: LinkTrackInfo?, possible: LinkTrackInfo?, candidates: [LinkCandidateInfo], chosen: LinkCandidateInfo?}`.
  - `kind`: `spotify|youtube`. `duration` en segundos. `artist` siempre presente (puede ser `""`).
  - `status`: `pending|searching|proposed|doubtful|downloading|imported|skipped|inLibrary|failed` (`:269-282`).
  - `stage`: solo `downloading`: `download|convert`. `progress` 0...1: solo `downloading` en `download` (ausente = indeterminado; en `convert` siempre ausente, `:276-277`).
  - `error`: solo `failed`. `inLibrary`: el propio tema ya está en la biblioteca. `possible`: «Puede que ya lo tengas» (mismo título y artista, otro id).
- `PlaylistErrorInfo` :10 `{code: String, title: String, detail: String, suggestsUpdate: Bool}`. `code` = mismos códigos de `SourceMessages.code` (lista en link). `suggestsUpdate` true con `extractor-broken` (página ofrece «Actualizar y reintentar»).
- `PlaylistTotalsInfo` :48 `{total, selected, imported, skipped, failed, inLibrary, remaining, queued, duplicates: Int}`. `queued` = marcados con candidato y sin terminar (el `n` de «Descargar y procesar (n)»). `duplicates` ⊂ `imported`.
- `PlaylistSummaryInfo` :63 `{imported, skipped, inLibrary, failed, remaining: Int, cancelled: Bool}`. Duplicados ya repartidos: `imported = totals.imported - duplicates`, `inLibrary = totals.inLibrary + duplicates` (`:301`).
- `PlaylistUpdateInfo` :72 `{updating: Bool, alreadyLatest: Bool, error: String?}`.

### Códigos de `RPCError` (playlist)

- `no-playlist`: `PlaylistMethods.swift:204` (cualquier acción o `state` sin lista abierta; `close` no lo lanza).
- `not-found`: `:407` (candidato no es de ese tema), `:432` (tema no está en la lista; `select`, `choose`, `skip`).
- `in-library`: `:410` (`choose` con un vídeo ya en la biblioteca).
- Apertura (`link.resolve`): `SourceMessages.rpc` en `:157`, `:162` (códigos de SourceKit, ver link) y `no-projects-folder` (`:146`).

---

## audio

El controlador se crea al primer método (`AudioMethods.swift:218-237`). `audio.calibrate` espera a que acabe la medición y devuelve el estado final (no lanza por fallo de medida: el fallo va en `outcome`).

### Métodos (todos en `AC/AudioMethods.swift`)

| método | params | result | register | qué hace |
|---|---|---|---|---|
| audio.devices | Empty | AudioDevicesResult | :257 | entradas y salidas conectadas, más la salida del sistema |
| audio.settings | Empty | AudioSettingsResult | :260 | perfil de audio con opciones de los desplegables, calibración y bloqueos |
| audio.setSettings | AudioSetSettingsParams | AudioSettingsResult | :263 | cambia dispositivo, canales o frecuencia de trabajo; guarda el perfil; devuelve los ajustes nuevos |
| audio.state | Empty | AudioStateResult | :266 | estado de sesión, grabación y calibración |
| audio.setMeters | AudioMetersParams | AudioStateResult | :269 | enciende o apaga los medidores de entrada (`audio.levels`) |
| audio.calibrate | Empty | AudioCalibrationState | :276 | mide la latencia de ida y vuelta (10 pitidos, ~5 s); progreso por `audio.calibration` |
| audio.cancelCalibration | Empty | AudioCalibrationState | :281 | cancela la medición |
| audio.dismissCalibration | Empty | AudioCalibrationState | :288 | cierra el resultado (vuelve a `idle`) |

### Eventos (`AC/AudioMethods.swift`)

| evento | payload | emit | cuándo |
|---|---|---|---|
| audio.levels | AudioLevelsEvent | :225 | 30 Hz (`meterRefreshHz`, `AudioController.swift:174`) mientras `metersVisible` y haya sesión abierta; una vez con arrays vacíos al perder la sesión o apagar medidores (`AudioController.swift:544`, `:558`) |
| audio.calibration | AudioCalibrationState | :229 | cada cambio de fase o de progreso de la calibración |
| audio.devicesChanged | AudioDevicesResult | :233 | cambia la lista de dispositivos |
| audio.state | AudioStateResult | :250 | cambia cualquier parte del estado (varios cambios del mismo turno se unen en uno) |

### DTO (`AC/AudioMethods.swift`)

Params (solo `Decodable`):
- `AudioSetSettingsParams` :144 `{outputDeviceUID: String??, inputDeviceUID: String??, backingOut: AudioChannelPair?, guitarIn: [Int]??, workingSampleRate: Double?}`. Semántica propia (`:145-166`): clave **ausente** = no se toca; clave con **`null`** = valor «nulo» (`outputDeviceUID: null` = salida del sistema, `inputDeviceUID: null` = sin entrada, `guitarIn: null` = «Sin asignar»). Dart debe distinguir ausente de `null` al codificar.
- `AudioMetersParams` :169 `{visible: Bool}`.
- `AudioChannelPair` :63 `{left: Int, right: Int}` (canales numerados desde 1).

Results y payloads:
- `AudioDeviceItem` :10 `{uid: String, name: String, channels: Int, label: String, connected: Bool, rate: Double?}`. `label` = «nombre · n can.» o «nombre · desconectado» (elegido no conectado: `channels: 0`, `connected: false`, `rate` ausente). `rate` en Hz.
- `AudioDevicesResult` :21 `{inputs: [AudioDeviceItem], outputs: [AudioDeviceItem], systemDefault: AudioDeviceItem?}`.
- `AudioRateOption` :28 `{rate: Double, label: String}` (valores 44100 y 48000).
- `AudioBackingChoice` :33 `{label: String, left: Int, right: Int}`.
- `AudioGuitarChoice` :39 `{label: String, channels: [Int]?}` (`channels` ausente = «Sin asignar»).
- `AudioRateMismatch` :45 `{deviceRate: Double, workingRate: Double, message: String, hint: String, canUseDeviceRate: Bool, useLabel: String}` (Hz; textos ya en español).
- `AudioCalibrationInfo` :55 `{calibrated: Bool, label: String, latencyMS: Double?, date: Date?}`. `label` «Sin calibrar» o «Calibrada · 2,05 ms · 3 feb 2026» (coma decimal, locale es). `date` ISO-8601 sin fracciones. `latencyMS` = `latencySamples / workingRate * 1000` (`:366`).
- `AudioSettingsResult` :68 `{outputDeviceUID: String?, inputDeviceUID: String?, backingOut: AudioChannelPair, guitarIn: [Int]?, workingSampleRate: Double, allowedSampleRates: [AudioRateOption], backingChoices: [AudioBackingChoice], guitarChoices: [AudioGuitarChoice], rateMismatch: AudioRateMismatch?, calibration: AudioCalibrationInfo, calibrateBlock: String?, calibrateInstructions: [String]}`. Aquí `outputDeviceUID`/`inputDeviceUID`/`guitarIn` ausentes = salida del sistema / sin entrada / sin asignar (no hay `null`). `calibrateBlock` = motivo por el que «Calibrar latencia» está desactivado; ausente si se puede. `calibrateInstructions`: 3 textos fijos (`:177-181`).
- `AudioStateResult` :85 `{sessionOpen: Bool, sessionError: String?, interruptionNote: String?, hostError: String?, hosting: Bool, metersVisible: Bool, recording: Bool, calibrationRunning: Bool, calibrationValid: Bool, calibrateBlock: String?, recordingNotices: [String], mismatchedRate: Double?, workingSampleRate: Double}`. `hosting` = el reproductor de estudio suena por la sesión (necesario para grabar). Frecuencias en Hz.
- `AudioCalibrationState` :126 `{phase: String, progress: Double?, outcome: String?, success: AudioCalibrationSuccess?, failure: AudioCalibrationFailure?, error: String?}`. `phase`: `idle|running|finished`. `progress` 0...1, solo `running` (empieza en 0). `outcome`: `success|failure|error`, solo `finished`; rellena a la vez `success`, `failure` o `error` respectivamente (`:420-449`).
- `AudioCalibrationSuccess` :102 `{latencyMS: Double, latencySamples: Double, spreadMS: Double, spreadSamples: Double, rigDelayMS: Double?, correctedTakes: Int, rows: [AudioCalibrationRow]}`. Muestras a la frecuencia de trabajo. `rigDelayMS` ausente = sin canal de referencia.
- `AudioCalibrationRow` :113 `{label: String, value: String}` (texto ya formateado: filas «Latencia», «Dispersión», «Retardo del rig», y «Tomas corregidas» si `correctedTakes > 0`).
- `AudioCalibrationFailure` :118 `{reason: String, spreadMS: Double, title: String, hint: String}`. `reason`: `noSignal|saturated|unstable` (`LatencyFailure` rawValue, `AudioKit/LatencyProbe.swift:5-11`).
- `AudioLevelsEvent` :137 `{levels: [Float], rmsDB: [Float], peakDB: [Float]}`. Un elemento por canal de entrada. `levels` 0...1 (derivado de `rmsDB` con suelo -60 dBFS, `AudioController.swift:176`); `rmsDB`/`peakDB` en dBFS (silencio = -120). Arrays vacíos = sin sesión.

### Códigos de `RPCError` (audio)

Solo `audio.setSettings`:
- `bad-params`: `AudioMethods.swift:300` (`workingSampleRate` no es 44100 ni 48000), `:303` (`backingOut` con canal < 1), `:313` (`AudioSettingsError`: canales inválidos, texto de `RecordBlock.invalidChannels`).
- `internal`: `:315` (no se pudo guardar el perfil).
El resto de métodos de audio no lanzan; los errores de sesión, grabación y calibración van como texto en `AudioStateResult`/`AudioCalibrationState`.

---

## frames

### Método

| método | params | result | register | qué hace |
|---|---|---|---|---|
| frames.stats | FrameStatsParams | FrameRelayStats | `AC/FrameRelay.swift:250` (`register` en `:249`) | contadores del relevo vivo o, si ya no existe, los últimos que dejó |

### Evento `frames.<canal>`

| evento | payload | emit | canales |
|---|---|---|---|
| frames.camera | FrameEvent | `AC/FrameRelay.swift:197` (`eventName` `:120`, `Bridge.emit` en `:266`) | `camera`: relevo creado en `RecordMethods.swift:706` (Grabar) y `:712` (`video.preview.*`); nombre en `RecordService.cameraChannel`. Valores por defecto: 15 fps, 640 px, JPEG 0,7 |
| frames.montage | FrameEvent | `FrameRelay.swift:197` | `montage`: `MontageMethods.swift:773-774`, `maxFPS: 60` (`Bridge.montageRelayMaxFPS`, `:770`), `latestWins: true`, 640 px, calidad 0,7 |

Hecho: el canal de Montaje **no** es de 15 fps sino 60 fps con `latestWins` (el último fotograma rechazado se guarda y sale en cuanto se puede; uno nuevo lo sustituye).

Comportamiento (`FrameRelay.swift:40-48`, `:122-171`): `push` no bloquea; descarta si hay uno codificándose (`droppedBusy`) o es pronto para `maxFPS` (`droppedRate`, holgura ¼ de periodo); nunca hay cola salvo el hueco único de `latestWins`. `stop()` no emite el fotograma en curso. El canal `frames.camera` no tiene eventos de parada: la página sabe que terminó por `video.preview.stop`/estado de Grabar. Solo existen los canales `camera` y `montage`; `frames.stats` con otro nombre da `not-found`.

Reducción (`VideoKit/FrameJPEG.swift:74-78`, `:39-41`): ancho de salida `max(2, min(ancho, maxWidth) & ~1)`; alto proporcional redondeado a par; nunca amplía. JPEG base 4:2:0, calidad 0,7 (rango 0...1 → 1...100 en `percent`, `:81`).

### DTO (`AC/FrameRelay.swift`)

- `FrameStatsParams` :271 `{channel: String}`.
- `FrameEvent` :6 `{seq: Int, width: Int, height: Int, ptsMs: Double, jpeg: String}`. Todos presentes. `seq` crece de uno en uno por fotograma **enviado** (por relevo; la página descarta los de `seq` menor que el último pintado). `width`/`height` del JPEG ya reducido, en píxeles. `ptsMs` en ms, marca de quien empuja: en `camera`, `hostSeconds * 1000` (`RecordMethods.swift:501`); en `montage`, el `ptsMs` del `MontageController.onPreviewFrame` (`MontageController.swift:159`; unidad: el nombre indica ms, no verificado el origen del cero). `jpeg`: JPEG en base64 estándar con relleno, **sin** prefijo `data:`.
- `FrameRelayStats` :16 `{channel: String, running: Bool, maxFPS: Double, maxWidth: Int, sent: Int, droppedBusy: Int, droppedRate: Int, failed: Int, encodeP50Ms: Double, encodeP95Ms: Double, totalP50Ms: Double, totalP95Ms: Double, meanBytes: Int, lastError: String?}`. Percentiles sobre los últimos 512 fotogramas (`statsWindow`, `:56`); `encode*` = conversión + reducción + JPEG; `total*` = además base64 y envío al puente. Todos presentes salvo `lastError`.

### Códigos de `RPCError` (frames)

- `not-found`: `FrameRelay.swift:252` (`frames.stats` de un canal sin relevo, ni vivo ni retirado).

---

## video.preview

Reutiliza el canal `camera` (no existe canal `preview`). Vista previa sin grabar, para Ajustes · Cámara y vídeo. Con Grabar abierta no abre otra captura: devuelve el estado de la cámara de Grabar con `fromRecord: true`.

### Métodos (`AC/CameraPreview.swift`)

| método | params | result | register | qué hace |
|---|---|---|---|---|
| video.preview.start | Empty | CameraPreviewResult | :80 | arranca (o rehace) la vista previa de la cámara efectiva; los fotogramas salen por `frames.camera` |
| video.preview.stop | Empty | CameraPreviewResult | :81 | la para; devuelve `state: "idle"` |

Sin eventos propios (los fotogramas son `frames.camera`, ver arriba).

### DTO

- `CameraPreviewResult` :10 `{state: String, message: String?, cameraId: String?, cameraName: String?, width: Int?, height: Int?, fps: Double?, rotation: Int, fromRecord: Bool}`.
  - `state`: `idle|live|simulated|noCamera|denied|failed` (`:12`). Con `fromRecord: true` el `state` es el de Grabar: `idle|live|simulated|denied|failed`, y `none` se traduce a `noCamera` (`:97`).
  - `message`: texto en español para `noCamera|denied|failed`; ausente si hay imagen. Textos: «ToneForge no tiene permiso para usar la cámara.» (`:59`), «No hay ninguna cámara conectada.» / «La cámara elegida está desconectada.» (`:172`), «No se pudo abrir la cámara (…).» (`:153`).
  - `cameraId`, `cameraName`: cámara efectiva. `width`, `height` (px), `fps`: formato abierto realmente; ausentes si no se abrió captura (`noCamera`, `denied` previo a abrir, `failed`).
  - `rotation`: grados horarios guardados para esa cámara (siempre presente; `0` si no hay cámara). Lo aplica la página; el JPEG llega sin girar.
  - `fromRecord`: Grabar abierta y ya manda su cámara por `frames.camera`.
- `stop` y arranque cancelado devuelven `{state:"idle", rotation:0, fromRecord:false}` (`:88`).

### Códigos de `RPCError` (video.preview)

- Ninguno en `start`/`stop`: los fallos van en `state`/`message`.
- `video.openCameraPrivacy` (mismo fichero): `internal` en `CameraPreview.swift:49`.

---

## Huecos y observaciones

- `contrato.md` (línea 109) da `PlaylistSnapshot` como resultado de `playlist.close`: es `PlaylistCloseResult`.
- `contrato.md` y el encargo hablan de «15 fps» para los canales de fotogramas: solo `camera` lo cumple; `montage` va a 60 fps con `latestWins`.
- Origen y unidad del `ptsMs` de `montage` sin confirmar en el controlador (el nombre del parámetro dice ms).
- Sin validar contra la pedalera ni de oído (pendiente de Jorge): latencias y textos de calibración con dispositivo real, y la cadencia real de `frames.camera` en cámaras físicas.
