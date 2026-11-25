# Contrato del puente: tipos de `record`, `takeview` y `montage`

ESTADO: COMPLETO para `record`, `takeview` y `montage`.

Rutas: `AC/` = `Packages/AppCore/Sources/AppCore/`. Convenciones del contrato general (`docs/flutter/contrato.md`): los DTO Codable sintetizados omiten la clave si el opcional es nil (Dart: ausente = `null`); UUID como cadena en mayúsculas (los de Record son `String` ya formateados con `.uuidString`); `Date` ISO-8601 sin fracciones; rutas de medios relativas a la carpeta de proyectos, con `/`. dB = decibelios; `gainDB` es ganancia en dB, `rmsDB`/`peakDB` son niveles dBFS (-120 = silencio).

---

## record

Pantalla Grabar del tema abierto en Backing. Requiere `study.open` previo (`not-open` si no). Todos los métodos salvo `open`/`close` devuelven `RecordSnapshot` completo (mismo DTO que el evento `record.state`).

### 1. Métodos y eventos

Fichero: `AC/RecordMethods.swift`.

| Nombre | Params | Result | register | Qué hace |
|---|---|---|---|---|
| `record.open` | `RecordOpenParams` | `RecordSnapshot` | :262 (impl. :431) | Abre Grabar: pausa Backing, aloja el reproductor, abre cámara y relevo `frames.camera`. Idempotente si ya está abierta con la misma sesión. |
| `record.close` | `Empty` | `Empty` | :263 | Cierra Grabar y devuelve el reproductor a Backing. |
| `record.state` | `Empty` | `RecordSnapshot` | :264 | Lee el estado actual. |
| `record.start` | `Empty` | `RecordSnapshot` | :265 | Inicia toma (cuenta atrás o grabación según ajustes). |
| `record.stop` | `Empty` | `RecordSnapshot` | :272 | Para la toma en curso y la guarda. |
| `record.cancel` | `Empty` | `RecordSnapshot` | :273 | Cancela la toma en curso sin guardar. |
| `record.selectPart` | `RecordPartParams` | `RecordSnapshot` | :274 | Elige la parte activa. |
| `record.addPart` | `RecordAddPartParams` | `RecordSnapshot` | :282 | Añade una parte (solo en `idle`). |
| `record.setStartSection` | `RecordSectionParams` | `RecordSnapshot` | :293 | Sección desde la que arranca la toma (sin `sectionId` = desde el principio). |
| `record.setCountIn` | `RecordOnParams` | `RecordSnapshot` | :303 | Activa o desactiva la cuenta atrás. |
| `record.setPreRoll` | `RecordBarsParams` | `RecordSnapshot` | :304 | Compases de pre-roll (0...2). |
| `record.setPunch` | `RecordPunchParams` | `RecordSnapshot` | :312 | Configura el punch (activar, entrada, salida, borrar). Si la fase no es `idle`, no hace nada y devuelve el estado. |
| `record.startPunch` | `RecordTakeParams` | `RecordSnapshot` | :324 | Graba el punch sobre la toma indicada. |
| `record.selectTake` | `RecordTakeParams` | `RecordSnapshot` | :327 | Elige toma (sin `takeId` = deselecciona). |
| `record.markBest` | `RecordTakeParams` | `RecordSnapshot` | :332 | Marca la toma como mejor de su parte. |
| `record.deleteTake` | `RecordTakeParams` | `RecordSnapshot` | :335 (impl. :372) | Borra la toma y sus ficheros. |
| `record.setCamera` | `RecordCameraParams` | `RecordSnapshot` | :338 | Elige cámara (`cameraId` ausente = por defecto). |
| `record.rotate` | `Empty` | `RecordSnapshot` | :341 | Gira la cámara (`camera.rotation`). |
| `record.adjustOffset` | `RecordTakeParams` | `RecordSnapshot` | :342 | Abre la hoja de desfase de la toma (`offset` pasa a no nil, fase `adjusting`). |
| `record.setOffset` | `RecordOffsetParams` | `RecordSnapshot` | :350 | Cambia el desfase de la hoja: absoluto (`valueMs`) y/o relativo (`deltaMs`, `frames`). |
| `record.finishOffset` | `RecordFinishOffsetParams` | `RecordSnapshot` | :357 | Cierra la hoja guardando o descartando. |
| `record.setMix` | `RecordMixParams` | `RecordSnapshot` | :361 | Ganancia, mute o solo de un canal (stem, guitarra o `take-<partId>`). |
| `record.setMaster` | `StudyMasterParams` | `RecordSnapshot` | :364 | Ganancia maestra (dB). |
| `record.prepareViewTake` | `Empty` | `RecordAllowedResult` | :367 (impl. :384) | Prepara el paso al visor de toma: pausa y suelta el audio; `allowed:false` si no se puede. |

Eventos (emisor `RecordService.emit`, :257; canal global del bridge):

| Evento | Payload | emit | Cadencia |
|---|---|---|---|
| `record.state` | `RecordSnapshot` (con `position` = posición en ese instante) | :531 | No periódico. Una vez por turno tras cualquier cambio (`stateChanged`, :519), solo si cambió algo distinto de `position` (comparación de JSON con `position=0`, :535). También al cambiar `playing` o `phase` (:563). |
| `record.position` | `RecordPositionEvent` | :573 | Periódico, 30 Hz como máximo: ticker a 30 Hz (`StudyConstants.eventHz`, `AC/StudyMethods.swift:11`) con separación mínima 0,9/30 s = 30 ms (`:13`). Se emite si `playing` o si `seconds` cambió. |
| `record.levels` | `RecordLevelsEvent` | :581 | Periódico, mismo ritmo (30 Hz, ≥30 ms). Solo si `playing` o los medidores aún superaban -119 dB en el envío anterior (`silentDB`, `:15`); al quedar en silencio emite un último paquete y calla. Solo incluye canales de `mix.channels` y `mix.takeChannels`. |

Además, mientras Grabar está abierta, los fotogramas de cámara van por el canal binario `frames.camera` (15 fps, 640 px según comentario `:705`; ver apartado `frames` del contrato general).

### 2. DTO

**Params** (`Decodable`; sin `encode`):

- `RecordOpenParams` (:196): `projectId: String?`. Si viene debe ser el UUID del tema abierto en Backing.
- `RecordPartParams` (:197): `partId: String` (UUID).
- `RecordAddPartParams` (:198): `name: String`, `replaces: String?` (rol de guitarra: `rhythm|left|right|lead`, `Store.GuitarRole`, `Store/Guitars.swift:8`).
- `RecordSectionParams` (:199): `sectionId: String?` (UUID; ausente = limpiar).
- `RecordOnParams` (:200): `on: Bool`.
- `RecordBarsParams` (:201): `bars: Int` (0...2, `Store/Recording.swift:85`).
- `RecordTakeParams` (:202): `takeId: String?` (UUID; en todos los métodos salvo `selectTake` es obligatorio de facto: ausente da `bad-params`).
- `RecordPunchParams` (:203-211): `enabled: Bool?`, `entry: Double?` (clave JSON **`in`**, segundos de canción), `exit: Double?` (clave JSON **`out`**, s), `clearIn: Bool?`, `clearOut: Bool?`, `free: Bool?` (sin ajustar a compás; defecto false). CodingKeys manual: Dart debe enviar `in`/`out`, no `entry`/`exit`. Orden de aplicación: `enabled`, luego (solo si el punch está activo) `clearIn`, `clearOut`, `in`, `out`.
- `RecordCameraParams` (:212): `cameraId: String?`.
- `RecordOffsetParams` (:213): `valueMs: Double?` (ms, absoluto, se aplica antes), `deltaMs: Double?` (ms), `frames: Double?` (fotogramas, relativo). Rango final -500...500 ms (`RecordController.offsetRangeMs`, `AC/RecordController.swift:195`; se recorta).
- `RecordFinishOffsetParams` (:214): `save: Bool` (obligatorio), `makeDefault: Bool?` (defecto true: recuerda el desfase como el de la cámara).
- `RecordMixParams` (:215): `channel: String`, `gainDB: Double?`, `mute: Bool?`, `solo: Bool?`. `channel` = id de `mix.channels[].id` (`vocals|drums|bass|guitar|piano|other` o, con guitarras separadas, `guitar_rhythm|guitar_L|guitar_R|guitar_lead`) o de `mix.takeChannels[].id` (`take-<partId>`). En un canal `forcedMuted`, `mute` y `solo` se ignoran; `gainDB` sí.
- `StudyMasterParams` (`AC/StudyMethods.swift:170`): `gainDB: Double`.

**Results**:

- `RecordAllowedResult` (:216): `allowed: Bool`.
- `RecordSnapshot` (:147-184). Codable sintetizado: opcionales nil = clave ausente.

| Campo | Tipo | Opc. | Notas |
|---|---|---|---|
| `projectId` | String (UUID) | no | |
| `title` | String | no | Título del tema. |
| `phase` | String | no | `idle`, `counting`, `recording`, `finishing`, `adjusting` (`AC/RecordController.swift:103-109`). |
| `countBeat` | Int | sí | Pulso de la cuenta (1...`beatsPerBar`); solo en `counting`. |
| `beatsPerBar` | Int | no | |
| `barSeconds` | Double (s) | no | |
| `bpm` | Double | no | `60/beatSeconds`. |
| `downbeats` | [Double] (s) | no | Inicios de compás. |
| `duration` | Double (s) | no | Duración del tema. |
| `position` | Double (s) | no | Posición del reproductor. En `record.state` es la del instante del emit; la comparación de cambios la ignora. |
| `busy` | Bool | no | |
| `blockReason` | String | sí | Si no nil, `record.start` da `record-blocked`. |
| `loadError` | String | sí | |
| `messages` | [String] | no | |
| `notices` | [String] | no | Avisos de la última toma del dispositivo. |
| `takeSaveError` | String | sí | |
| `countIn` | Bool | no | |
| `preRollBars` | Int | no | 0...2. |
| `startSectionId` | String | sí | |
| `startTime` | Double (s) | no | |
| `plannedStop` | Double (s) | sí | |
| `sections` | [StudySectionInfo] | no | Ver abajo. |
| `guitarRoles` | [RecordGuitarRole] | no | |
| `parts` | [RecordPartInfo] | no | |
| `activePartId` | String | sí | |
| `nextTakeNumber` | Int | no | |
| `selectedTakeId` | String | sí | |
| `punch` | RecordPunchInfo | no | |
| `mix` | RecordMixInfo | no | |
| `camera` | RecordCameraInfo | no | |
| `offset` | RecordOffsetInfo | sí | Presente solo con hoja de desfase abierta. |
| `audio` | RecordAudioInfo | no | |

**Payload de eventos**:

- `RecordPositionEvent` (:186): `seconds: Double` (s), `playing: Bool`, `phase: String` (mismos valores que `RecordSnapshot.phase`).
- `RecordLevelsEvent` (:192): `channels: {String: StudyMeter}`, clave = id de canal (`mix.channels[].id` o `take-<partId>`).
- `StudyMeter` (`AC/StudyMethods.swift:149`): `rmsDB: Double`, `peakDB: Double` (dBFS; no finitos se envían como -120).

**Tipos anidados** (todos `Codable` sintetizado, sin CodingKeys salvo indicado):

- `StudySectionInfo` (`AC/StudyMethods.swift:102`): `id: String`, `name: String`, `start: Double` (s), `end: Double` (s), `solo: Bool`, `color: Int?`, `paletteIndex: Int?`.
- `RecordGuitarRole` (:11): `role: String` (`rhythm|left|right|lead`), `name: String`.
- `RecordPartInfo` (:53): `id`, `name`, `replaces: String?` (rol), `isLead: Bool`, `status: String` (`pending|recording|done`, `RecordPartStatus`, `AC/RecordController.swift:129`), `bestTakeId: String?`, `takes: [RecordTakeInfo]`.
- `RecordTakeInfo` (:33): `id: String`, `number: Int` (1..., posición en la parte), `createdAt: Date`, `best`, `selected`, `discarded: Bool`, `durationSeconds: Double?` (s), `songStart: Double?` (s), `hasVideo: Bool`, `videoPath: String?`, `videoOffsetMs: Double?` (ms; positivo = la imagen llega tarde), `videoRotation: Int` (grados), `videoFormat: RecordTakeFormat?`, `audioPath: String?` (el audio procesado), `punches: [RecordPunchTake]`.
- `RecordTakeFormat` (:25): `cameraId: String`, `cameraName: String`, `width: Int`, `height: Int` (px), `fps: Double`.
- `RecordPunchTake` (:16): `start: Double` (s), `end: Double` (s), `hasVideo: Bool`, `videoPath: String?`, `videoOffsetMs: Double?` (ms; en tomas usa el del punch o, si no, el de la toma).
- `RecordPunchInfo` (:64): `enabled: Bool`, `in: Double?` (s), `out: Double?` (s), `ready: Bool` (hay toma elegida con audio alineado y entrada y salida). Claves JSON `in` y `out`.
- `RecordMixInfo` (:94): `masterGainDB: Double`, `channels: [RecordMixChannel]`, `takeChannels: [RecordTakeChannel]`, `anySolo: Bool`, `outputName: String`.
- `RecordMixChannel` (:72): `id: String`, `kind: String` (`vocals|drums|bass|guitar|piano|other`), `guitarRole: String?` (solo con guitarras separadas), `name: String`, `gainDB: Double`, `muted: Bool` (incluye `forcedMuted`), `solo: Bool`, `forcedMuted: Bool` (la guitarra de la parte que se graba; no reactivable). Orden: voz, batería, bajo, guitarra(s), piano, resto (`AC/StudyMethods.swift:17`).
- `RecordTakeChannel` (:84): `id: String` (`take-<partId>`), `partId: String`, `name: String` («Tú · nombre de la parte»), `gainDB: Double`, `muted: Bool`, `solo: Bool`.
- `RecordCameraInfo` (:107): `state: String` (`idle|none|denied|simulated|failed|live`, `AC/RecordController.swift:117-124`), `message: String?`, `name: String?`, `label: String?`, `width: Int?`, `height: Int?` (px), `fps: Double?`, `rotation: Int` (grados), `defaultOffsetMs: Double?` (ms, redondeado), `cameras: [RecordCameraEntry]`, `chosenId: String?`.
- `RecordCameraEntry` (:102): `id: String`, `name: String`.
- `RecordOffsetInfo` (:122): `takeId: String`, `isNew: Bool`, `videoPath: String`, `audioPath: String` (relativas a la carpeta de proyectos; cadena vacía si no hay), `songStart: Double` (s), `fps: Double`, `frameMs: Double` (`1000/max(fps,1)`), `cameraId`, `cameraName: String`, `initialMs: Double` (ms redondeado), `valueMs: Double` (ms), `minMs: Double` (-500), `maxMs: Double` (+500), `rotation: Int`, `punches: [RecordPunchTake]`.
- `RecordAudioInfo` (:140): `sessionOpen: Bool`, `hosting: Bool`, `recording: Bool`, `outputName: String`.

Ningún DTO de `record` tiene `encode(to:)` a mano: no hay `null` explícito.

### 3. Códigos de `RPCError`

| code | Dónde | Cuándo |
|---|---|---|
| `not-open` | `AC/RecordMethods.swift:389` (constante `notOpen`, usada en :379, :385, :392, :506, :510); :433 | Grabar no está abierta; o `open` sin tema en Backing (:433, «No hay ningún tema abierto en Backing»). |
| `bad-params` | :286, :307, :397, :404, :425, :436 | `replaces` no es rol; `bars` fuera de 0...2; `takeId` no UUID; `channel` desconocido; `projectId` distinto del tema abierto. |
| `not-found` | :277, :297, :398 | Parte, sección o toma inexistente. |
| `busy` | :268, :289, :345 | `start` con toma en curso; `addPart` o `adjustOffset` fuera de `idle`. |
| `record-blocked` | :267 | `start` con `blockReason` (el mensaje es el motivo). |
| `no-video` | :347 | `adjustOffset` en toma sin vídeo. |
| `no-offset` | :352 | `setOffset` sin hoja abierta. |
| `internal` | :374, :439, :453 | Fallo al borrar la toma (mensaje del controlador); sin servicio de audio; sin biblioteca. |

---

## takeview

Visor de tomas: una toma abierta a la vez, con su propia salida de audio. Tiempo del visor: 0 = inicio de la toma, hasta `duration`. El `<video>` de la interfaz sigue este reloj (ver `takeview.position`). Todos los métodos de transporte devuelven `TakeViewSnapshot`.

### 1. Métodos y eventos

Fichero: `AC/TakeViewMethods.swift`.

| Nombre | Params | Result | register | Qué hace |
|---|---|---|---|---|
| `takeview.open` | `TakeViewOpenParams` | `TakeViewSnapshot` | :258 (impl. :300) | Abre una toma de `project.json` (necesita `processedFile` y `songStart`), con su backing (`library.takeBacking`) si lo hay. Cierra la anterior y pausa Backing. |
| `takeview.openOffset` | `Empty` | `TakeViewSnapshot` | :259 (impl. :360) | Abre la toma de la hoja «Ajustar desfase» de Grabar (solo el audio de la toma, sin backing, `isOffset`). |
| `takeview.close` | `Empty` | `Empty` | :260 | Para y suelta audio y ficheros. |
| `takeview.snapshot` | `Empty` | `TakeViewSnapshot` | :261 | Estado actual. |
| `takeview.play` | `Empty` | `TakeViewSnapshot` | :262 | Reproduce (pausa antes lo demás; a menos de 0,1 s del final, o 1/30 s en la hoja de desfase, vuelve al principio). |
| `takeview.pause` | `Empty` | `TakeViewSnapshot` | :268 | Pausa. |
| `takeview.seek` | `TakeViewSeekParams` | `TakeViewSnapshot` | :269 | Salta a `seconds` (se recorta a 0...duración). |
| `takeview.setBacking` | `TakeViewBackingParams` | `TakeViewSnapshot` | :273 | Enciende o apaga las pistas de backing (silencia, no recarga). |

| Evento | Payload | emit | Cadencia |
|---|---|---|---|
| `takeview.position` | `TakeViewPositionEvent` | :500 (vía `publish` :487) | Periódico, ticker de **30 Hz** (`TakeViewConstants.positionHz`, :17; tick :448) mientras hay toma abierta. Sonando: cada tick. En pausa: solo si cambió `seconds` o `epoch` (el `at` no cuenta, :498). Además, uno forzado en cada discontinuidad (open, play, pause, seek, final de toma; :287, :414, :483). Sin evento de estado aparte: `playing` y `epoch` van aquí. |
| `takeview.video` | `TakeViewVideoEvent` | (ver `VideoConversion`, ADR-022) | Cambio del vídeo de la toma abierta: `{takeId, video?}`. `video` ausente = vídeo listo; si va, `{code, takeId, jobId, message, progress?}` con `code` `video-converting` (con `progress` 0…1, clave en `jobs.progress`) o `video-failed` (sin `progress`). Fixtures `takeview.video.{converting,error,ready}.event.json`. |

### 2. DTO

- `TakeViewOpenParams` (:82): `projectId: String` (UUID), `takeId: String` (UUID). Ambos obligatorios.
- `TakeViewSeekParams` (:83): `seconds: Double` (s de la toma; no finito da `bad-params`).
- `TakeViewBackingParams` (:84): `on: Bool`.
- `TakeViewSnapshot` (:86, Codable sintetizado, opcionales omitidos si nil):

| Campo | Tipo | Opc. | Notas |
|---|---|---|---|
| `projectId`, `takeId` | String (UUID) | no | |
| `duration` | Double (s) | no | Duración de `processed.wav`. |
| `songStart` | Double (s) | no | Inicio de la toma en el tema; el vídeo busca PTS `songStart + seconds + desfase`. |
| `hasBacking` | Bool | no | Hay pistas de backing. |
| `backingOn` | Bool | no | Siempre false en `openOffset`. |
| `playing` | Bool | no | |
| `position` | Double (s) | no | Tiempo de la toma, sin alisar. |
| `epoch` | Int | no | Sube en cada discontinuidad (play, pausa, seek, final). |
| `outputName` | String | no | Salida de audio. |
| `audioError` | String | sí | Fallo al abrir/reproducir la salida. |
| `videoWidth`, `videoHeight` | Int | sí | FC1: tamaño del fotograma del vídeo de la toma; ausentes si no hay vídeo. |
| `videoRotation` | Int | sí | FC1: giro del vídeo en grados (p. ej. 90); ausente si no hay vídeo. |

- `TakeViewPositionEvent` (:105): `seconds: Double` (s de la toma que se oye en `at`; alisado por lazo de fase, :45-77), `playing: Bool`, `rate: Double` (1 = el reloj avanza; 0 = quieto, en pausa o esperando la primera muestra), `at: Double` (reloj de host del núcleo en s: QPC en Windows, `mach_absolute_time` en Mac; misma base para extrapolar `seconds + (ahora - at)`), `epoch: Int`. Todos obligatorios.

Ningún DTO de `takeview` tiene `encode(to:)` a mano.

### 3. Códigos de `RPCError`

| code | Dónde | Cuándo |
|---|---|---|
| `not-open` | `AC/TakeViewMethods.swift:278` | Transporte sin toma abierta («No hay ninguna toma abierta en el visor.»). |
| `bad-params` | :270, :302 | `seconds` no finito; `projectId`/`takeId` no UUID. |
| `not-found` | :311, :315, :363 | Toma sin audio (`processedFile`/`songStart` ausentes o duración 0): «Esta toma no tiene audio que reproducir.». Más los errores de `Bridge.service`/`lib.folder`/`takeBacking` (`no-projects-folder`, `not-found` del contrato general). |
| `internal` | :308 | No se pudo leer `project.json`. |
| `load-failed` | :348, :372 | No se pudieron cargar las pistas. |
| `no-offset` | :361 | `openOffset` sin hoja de desfase abierta en Grabar. |
| `audio-unavailable` | :177 | `play` y la salida de audio no abre (`audioError` queda puesto). |

---

## montage

Montaje del tema abierto (independiente de Backing). Los fotogramas de la vista previa van por `frames.montage` (JPEG en base64 por defecto; BGRA solo si el anfitrión registra `setMontageFrameSink`, `AC/MontageMethods.swift:762-766`; ≤60 fps según `previewFps`, `latestWins`, lado mayor `preview.maxDimension` = 640 px; PTS en ms de vídeo; relé `AC/MontageMethods.swift:768-775`). El audio manda el reloj. Todos los métodos devuelven `MontageSnapshot` salvo los indicados.

### 1. Métodos y eventos

Fichero: `AC/MontageMethods.swift`.

| Nombre | Params | Result | register | Qué hace |
|---|---|---|---|---|
| `montage.open` | `MontageOpenParams` | `MontageSnapshot` | :366 (impl. :535) | Abre el tema, prepara plan, análisis de encuadre y vista previa. |
| `montage.close` | `Empty` | `Empty` | :367 | Guarda el montaje y suelta audio y relevo. |
| `montage.snapshot` | `Empty` | `MontageSnapshot` | :368 | Estado actual. |
| `montage.setLayout` | `MontageLayoutParams` | `MontageSnapshot` | :369 | Cambia el layout. |
| `montage.setSingleRhythm` | `MontagePartParams` | `MontageSnapshot` | :375 | Parte rítmica del plano único (sin `partId` = automática). |
| `montage.setCutGaps` | `MontageBoolParams` | `MontageSnapshot` | :379 | Recortar huecos. |
| `montage.moveLane` | `MontageMoveLaneParams` | `MontageSnapshot` | :380 | Mueve una parte a la posición de otra en el orden. |
| `montage.setPartOrder` | `MontageOrderParams` | `MontageSnapshot` | :384 | Fija el orden de partes. |
| `montage.setCaption` | `MontageBoolParams` | `MontageSnapshot` | :388 | Título sobre el vídeo. |
| `montage.setShowPartLabels` | `MontageBoolParams` | `MontageSnapshot` | :389 | Etiquetas de parte. |
| `montage.setKeepVideoAspect` | `MontageBoolParams` | `MontageSnapshot` | :392 | Conservar el aspecto del vídeo (solo si `keepAspectApplies`). |
| `montage.addCut` | `MontageAddCutParams` | `MontageAddCutResult` | :395 (impl. :500) | Añade un corte del plano único; devuelve su id y el estado. |
| `montage.moveCut` | `MontageCutMoveParams` | `MontageSnapshot` | :396 | Mueve un corte. |
| `montage.setCutPart` | `MontageCutPartParams` | `MontageSnapshot` | :400 | Asigna parte a un corte (sin `partId` = automática). |
| `montage.removeCut` | `MontageIDParams` | `MontageSnapshot` | :404 | Borra un corte. |
| `montage.clearCuts` | `Empty` | `MontageSnapshot` | :408 | Borra todos los cortes. |
| `montage.setExport` | `MontageSetExportParams` | `MontageSnapshot` | :409 | Ajustes de exportación (parciales). |
| `montage.setFraming` | `MontageSetFramingParams` | `MontageSnapshot` | :433 | Encuadre de una toma (modo, caja manual, zoom/desplazamiento). |
| `montage.resetFraming` | `MontageTakeParams` | `MontageSnapshot` | :446 | Restablece el encuadre. |
| `montage.reanalyze` | `MontageTakeParams` | `MontageSnapshot` | :450 | Repite el análisis de encuadre. |
| `montage.rotateTake` | `MontageTakeParams` | `MontageSnapshot` | :454 | Gira la toma 90 grados. |
| `montage.framingFrame` | `MontageFramingFrameParams` | `MontageFramingFrameResult` | :458 (impl. :509; escritura PNG `AC/MontageController.swift:829-853`) | Escribe un PNG sin compresión (lado mayor 1280) del fotograma de la toma en `time` y devuelve su ruta y la caja efectiva. |
| `montage.play` | `Empty` | `MontageSnapshot` | :461 | Reproduce (pausa Backing antes). |
| `montage.pause` | `Empty` | `MontageSnapshot` | :464 | Pausa. |
| `montage.seek` | `MontageSeekParams` | `MontageSnapshot` | :465 | Salta a `seconds` en tiempo del **tema** (se recorta a `span`; `AC/MontageController.swift:743-751`). |
| `montage.setPreviewFps` | `MontageFPSParams` | `MontageSnapshot` | :469 | Ritmo de la vista previa (se recorta a 1...60; defecto 15). |
| `montage.startExport` | `Empty` | `MontageSnapshot` | :473 | Inicia la exportación (mezcla y codificación). |
| `montage.cancelExport` | `Empty` | `MontageSnapshot` | :482 | Cancela (fase `cancelled`). |
| `montage.dismissExport` | `Empty` | `MontageSnapshot` | :483 | Descarta el resultado/error (vuelve a `idle` si no hay exportación en curso). |
| `montage.reveal` | `Empty` | `MontageRevealResult` | :484 (impl. :517) | Abre la **carpeta** `video/` del tema (la crea si falta), no el fichero. |

| Evento | Payload | emit | Cadencia |
|---|---|---|---|
| `montage.state` | `MontageSnapshot` completo | :696 | No periódico. Coalescido por turno; solo si cambió algo salvo posición, progresos y estadísticas de vista previa (`stable`, :668). También al cambiar `playing` (:744). |
| `montage.export` | `MontageExportEvent` | :706 | Cambios de fase de exportación; en `running`, **máx. 4 Hz** (`progressInterval` = 0,25 s, `MontageConstants` :15; el último, `progress` 1, siempre sale). |
| `montage.framing` | `MontageFramingEvent` | :715 | Por toma; en `analyzing`, máx. 4 Hz por toma (0,25 s); resto de cambios siempre. |
| `montage.position` | `MontagePositionEvent` | :743 | Periódico, **30 Hz** máx. (ticker 30 Hz, `positionHz` :12, separación mínima 0,9/30 s). Se emite si `playing` o si cambió; en pausa solo al cambiar. |

### 2. DTO

Unidades: «tema» = segundos de la canción; «vídeo» = segundos del vídeo montado (reloj del audio de la mezcla). `MontageSnapshot.transport.position` es tema, `videoPosition` es vídeo. `montage.seek.seconds` y `MontagePositionEvent.seconds` son tema; `MontagePositionEvent.videoSeconds` es vídeo.

**Params** (`Decodable`, líneas de `AC/MontageMethods.swift`):
- `MontageOpenParams` :267 `projectId: String` (UUID).
- `MontageLayoutParams` :268 `layout: String`: `side|grid|stack|single|single-landscape` (`Store.MontageLayoutKind`).
- `MontagePartParams` :269 `partId: String?`.
- `MontageBoolParams` :270 `on: Bool`.
- `MontageMoveLaneParams` :271 `id: String`, `to: String` (ids de lane/parte).
- `MontageOrderParams` :272 `ids: [String]`.
- `MontageAddCutParams` :273 `time: Double` (tema, s), `partId: String?`, `exact: Bool?` (true = sin ajustar a compás y recortado al `span`; con `partId` también va por la vía exacta).
- `MontageCutMoveParams` :274 `id: String`, `time: Double` (tema, s).
- `MontageCutPartParams` :275 `id: String`, `partId: String?`.
- `MontageIDParams` :276 `id: String`.
- `MontageSetExportParams` :277 todos opcionales: `codec: String` (`hevc|h264`), `container: String` (`mov|mp4`), `resolution: MontageResolutionInfo` (ancho y alto >0), `fps: Double` (>0 finito), `normalize: Bool`, `limiter: Bool`, `trackWAVs: Bool`.
- `MontageTakeParams` :286 `takeId: String`.
- `MontageSetFramingParams` :287 `takeId: String`; opcionales: `mode: String` (`fixed|follow`), `manualBox: MontageBoxInfo`, `clearManualBox: Bool` (true borra la caja manual; se aplica antes que `manualBox`), `followZoom: Double` (>0 finito), `followOffset: MontageOffsetInfo`.
- `MontageFramingFrameParams` :296 `takeId: String`, `time: Double` (tema, s).
- `MontageSeekParams` :297 `seconds: Double` (tema, s). `MontageFPSParams` :298 `fps: Double`.

**Results**:
- `MontageAddCutResult` :248: `cutId: String`, `snapshot: MontageSnapshot`.
- `MontageFramingFrameResult` :253: `path: String` (relativa a la carpeta del tema, con `/`: `cache/montage/framing-<take>.png`; NO relativa a la carpeta de proyectos, a diferencia de otras rutas de medios), `width: Int`, `height: Int` (px), `time: Double` (s), `version: Int` (anti-caché), `box: MontageBoxInfo?` (normalizada 0...1 sobre la imagen ya girada; ausente si no hay).
- `MontageRevealResult` :265: `revealed: Bool`.

**MontageSnapshot** (:201; sintetizado, opcionales omitidos si nil):

| Campo | Tipo | Opc. | Notas |
|---|---|---|---|
| `projectId` | String | no | |
| `title` | String | no | |
| `artist` | String | sí | |
| `layout` | String | no | `side|grid|stack|single|single-landscape`. |
| `isPortrait`, `isSingleShot` | Bool | no | |
| `canvasLabel` | String | no | |
| `keepAspectApplies` | Bool | no | |
| `caption`, `showPartLabels`, `keepVideoAspect`, `cutGaps` | Bool | no | |
| `singleRhythmPartId` | String | sí | |
| `singleRhythmCandidates` | [String] | no | Ids de parte. |
| `hasPlan`, `hasVideo` | Bool | no | |
| `span` | MontageRangeInfo | no | Tramo del montaje (tema, s). |
| `barDuration` | Double (s) | no | |
| `songDuration` | Double (s) | no | 0 si se desconoce. |
| `anticipationLabel` | String | no | Texto, p. ej. «0,5 s». |
| `lanes` | [MontageLaneInfo] | no | |
| `audioOnlyParts`, `missingParts` | [String] | no | Nombres de parte. |
| `segments` | [MontageSegmentInfo] | no | |
| `sections` | [MontageSectionInfo] | no | |
| `cuts` | [MontageCutInfo] | no | |
| `cutCandidates` | [String] | no | Ids de parte. |
| `planeShots` | [MontagePlaneShotInfo] | no | |
| `framing` | [MontageFramingInfo] | no | Una por lane con vídeo. |
| `isAnalyzing` | Bool | no | |
| `export` | MontageExportInfo | no | |
| `exportStatus` | MontageExportEvent | no | |
| `preview` | MontagePreviewInfo | no | |
| `transport` | MontageTransportInfo | no | |

**Tipos anidados** (líneas de `AC/MontageMethods.swift`):
- `MontageRangeInfo` :20 `{start, end: Double}` (s).
- `MontageLaneInfo` :25 `{id, takeId, partName: String, isSolo: Bool, replaces: String?, presence: [MontageRangeInfo], take: MontageRangeInfo, hasVideo: Bool, rotation: Int}`; `replaces` = rol (`rhythm|left|right|lead`); `rotation` ∈ 0, 90, 180, 270.
- `MontageSegmentInfo` :39 `{start, end: Double, fadeIn, fadeOut: Bool}`.
- `MontageSectionInfo` :46 `{id, name: String, start, end: Double, solo: Bool}`.
- `MontageCutInfo` :54 `{id: String, time: Double, partId: String?, covered: Bool, eligible: [String]}` (`partId` ausente = automático; `eligible` ordenado).
- `MontagePlaneShotInfo` :65 `{start, end: Double, partId: String?, black: Bool}`.
- `MontageBoxInfo` :72 `{x, y, width, height: Double}` (normalizada 0...1). `MontageOffsetInfo` :79 `{x, y: Double}` (rango -0,5...0,5 según la hoja del Mac).
- `MontageFramingInfo` :84 `{takeId: String, status: String (pending|analyzing|ready|failed), progress: Double (0...1), samples: Int?, detected: Int?, error: String?, mode: String (fixed|follow), manualBox: MontageBoxInfo?, followZoom: Double, followOffset: MontageOffsetInfo}`.
- `MontageResolutionInfo` :99 `{width, height: Int}` (px).
- `MontageExportOptions` :104 `{codecs: [String], containers: [String], resolutions: [MontageResolutionInfo], fps: [Double]}`; en Windows `codecs` solo `h264`.
- `MontageExportInfo` :127 `{codec, effectiveCodec, container: String, resolution: MontageResolutionInfo, size: MontageResolutionInfo (final según layout), fps: Double, normalize, limiter, trackWAVs: Bool, options: MontageExportOptions, canExport: Bool}`. `codec` = guardado (puede ser `hevc`); `effectiveCodec` = el que se usará.
- `MontageExportEvent` :144 `{phase: String (idle|running|done|failed|cancelled), stage: String? (solo running: «Mezclando el audio» o «Codificando el vídeo»), progress: Double (0...1; mezcla ocupa el primer 15 %), message: String? (solo failed), result: MontageExportResultInfo? (solo done)}`. También es `MontageSnapshot.exportStatus`.
- `MontageExportResultInfo` :112 `{path: String (ABSOLUTA, `r.url.path`, no relativa), tracksDirectory: String? (absoluta), finalLUFS: Double? (LUFS), finalTruePeakDB: Double (dBTP), normalized, limitedByPeak, limiterEnabled, limiterApplied: Bool, limiterMaxReductionDB: Double (dB), limiterOutOfTolerance: Bool, clippedFiles: [String], codec: String}`.
- `MontageFramingEvent` :153 `{takeId, status (como arriba), progress: Double, samples: Int?, detected: Int?, error: String?}`.
- `MontagePreviewInfo` :171 `{phase: String (none|preparing|ready|error), error: String?, audio: MontageAudioInfo, fps: Double, maxDimension: Int (640), width, height: Int (tamaño de fotogramas), duration: Double? (vídeo, s), delivered, skipped: Int, lastFrameMillis: Double (ms), frameP50Ms, frameP95Ms: Double (ms; 512 últimos)}`.
- `MontageAudioInfo` :162 `{phase: String (none|preparing|ready|silent|error), error: String?, progress: Double, file: String? (nombre del WAV en `cache/montage/`)}`.
- `MontageTransportInfo` :191 `{playing: Bool, position: Double (tema, s), videoPosition: Double (vídeo, s), span: MontageRangeInfo, audioError: String?}`.
- `MontagePositionEvent` :242 `{seconds: Double (tema), videoSeconds: Double (vídeo), playing: Bool}`.

Ningún DTO de `montage` tiene `encode(to:)` a mano: no hay `null` explícito.

### 3. Códigos de `RPCError`

| code | Dónde | Cuándo |
|---|---|---|
| `not-open` | `AC/MontageMethods.swift:489` | Método sin tema abierto en Montaje. |
| `bad-params` | :371, :412, :416, :419, :420, :435, :466, :470, :492, :536 | layout, codec, container, resolution, fps, mode o seconds inválidos; id no UUID. |
| `internal` | :540; `AC/MontageController.swift:837`, :847 | `project.json` ilegible; fallo leyendo o guardando el fotograma de encuadre. |
| `not-ready` | :476 | `startExport` sin plan («No hay tomas con vídeo que montar.»), con exportación en curso o con el análisis sin terminar. |
| `audio-unavailable` | `AC/MontageController.swift:718` | `play` con la salida de audio no disponible (mensaje = `audioError`). |
| `not-found` | `AC/MontageController.swift:832` | `framingFrame` en toma sin vídeo. También los de `Bridge.service`/`folder(id:)` en `open`. |
| `no-frame` | `AC/MontageController.swift:840` | `framingFrame` sin imagen en ese instante. |
