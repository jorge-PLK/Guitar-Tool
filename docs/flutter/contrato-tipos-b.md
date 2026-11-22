# Contrato del puente: tipos y métodos de `study` y `tab` (+ `tab.songsterr`)

ESTADO: COMPLETO salvo huecos anotados al final.

Complementa `docs/flutter/contrato.md` (mismo formato y reglas de codificación). Rutas: `AC/` = `Packages/AppCore/Sources/AppCore/`. Reglas que valen para todo este fichero:

- Ningún DTO de `Study*.swift` ni `Tab*.swift` implementa `encode(to:)` a mano: todos son sintetizados, así que un `Optional` nil **omite la clave** (nunca sale `null`). Solo hay un `init(from:)` a mano en un parámetro de entrada (`StudyUpdateSectionParams`, ver abajo).
- Tiempos en segundos (Double) de la canción; ganancias en dB (Double).
- Todos los métodos `study.*` salvo `open`/`close` fallan con `not-open` si no hay tema abierto.

## study

### Métodos

Ejecutan en `@MainActor`. Los métodos que cambian estado devuelven el estado ya actualizado y además provocan un evento `study.state` (coalescido por turno).

| método | qué hace | params | result | register |
|---|---|---|---|---|
| `study.open` | Abre el tema (cierra el anterior), carga stems y análisis; si está separado y sin análisis vigente lo pide a la cola. | `StudyOpenParams` | `StudyOpenResult` | `AC/StudyMethods.swift:233` |
| `study.close` | Para, guarda lo pendiente y suelta ficheros. No falla si no hay tema. | `Empty` | `Empty` | `:234` |
| `study.play` | Da a play; falla si la salida no abre. | `Empty` | `StudyTransport` | `:235` |
| `study.pause` | Pausa. | `Empty` | `StudyTransport` | `:238` |
| `study.seek` | Salta a `seconds` (se recorta a `0...duration`). | `StudySeekParams` | `StudyTransport` | `:239` |
| `study.setRate` | Velocidad (recorta a `0.5...2.0`). | `StudyRateParams` | `StudyTransport` | `:242` |
| `study.setTranspose` | Semitonos (recorta `-12...12`) y/o cents finos (recorta `-50...50`); cada campo ausente no cambia. | `StudyTransposeParams` | `StudyTransport` | `:245` |
| `study.setCapo` | Cejilla (recorta `0...12`); solo cambia diagramas. | `StudyCapoParams` | `StudyTransport` | `:251` |
| `study.setLoop` | Fija el bucle `start...max(start,end)`; si falta `start` o `end` (o no son finitos) lo **quita**. | `StudyLoopParams` | `StudyTransport` | `:254` |
| `study.setMix` | Ganancia/mute/solo de un canal (campos ausentes no cambian; ganancia recorta a `-60...6` dB). | `StudyMixParams` | `StudyTransport` | `:259` |
| `study.setMaster` | Volumen master en dB (recorta `-60...6`); se guarda en el perfil con rebote. | `StudyMasterParams` | `StudyTransport` | `:266` |
| `study.setMetronome` | Metrónomo on/off y/o ganancia (recorta `-60...6`). | `StudyMetronomeParams` | `StudyTransport` | `:269` |
| `study.snapshot` | Foto completa del tema abierto (lo que devolvió `open`). Es lo que se relee al llegar `study.guitars`. | `Empty` | `StudyOpenResult` | `AC/StudyEdits.swift:122` |
| `study.analyze` | Pide el análisis (tempo, compases, acordes, tonalidad) a la cola. | `Empty` | `StudyEditState` | `:123` |
| `study.setKey` | Corrige la tonalidad (`"C:maj"`, `"A:min"`); `key` ausente/nil quita la corrección. Se normaliza (`Db:maj` pasa a `C#:maj`). | `StudySetKeyParams` | `StudyEditState` | `:124` |
| `study.setChord` | Fija el acorde de un tramo: indicar `index` **o** `label` (solo uno). | `StudySetChordParams` | `StudyEditState` | `:125` |
| `study.removeChordOverrides` | Quita las correcciones de acorde dentro de `start...end`. | `StudyChordRangeParams` | `StudyEditState` | `:126` |
| `study.clearChordOverrides` | Quita todas las correcciones de acorde. | `Empty` | `StudyEditState` | `:134` |
| `study.splitChord` | Parte en dos el acorde que contiene `at`, por el pulso más cercano (margen 50 ms a los extremos). | `StudySplitChordParams` | `StudyEditState` | `:137` |
| `study.markSection` | Crea una sección; `added` del resultado trae su id. | `StudyMarkSectionParams` | `StudyEditState` | `:138` |
| `study.updateSection` | Cambia nombre, solo, color y/o bordes de una sección, con ajuste opcional. | `StudyUpdateSectionParams` | `StudyEditState` | `:139` |
| `study.previewSectionEdge` | Vista previa de arrastrar un borde, sobre una copia: no cambia estado, no emite `study.state`, no guarda. | `StudyPreviewSectionEdgeParams` | `StudyPreviewSections` | `:142` |
| `study.nudgeSectionEdge` | Mueve un borde al límite de acorde (o de compás con `bar`) anterior/siguiente. | `StudyNudgeSectionParams` | `StudyEditState` | `:145` |
| `study.deleteSection` | Borra una sección. | `StudyDeleteSectionParams` | `StudyEditState` | `:152` |
| `study.applySections` | Aplica ya las secciones pendientes (guarda y, si procede, relanza el reparto de guitarras). | `Empty` | `StudyEditState` | `:158` |
| `study.discardSections` | Descarta los cambios de secciones sin aplicar. | `Empty` | `StudyEditState` | `:164` |
| `study.renameGuitar` | Renombra una guitarra (queda pendiente hasta aplicar; nombre vacío = nombre por defecto). | `StudyRenameGuitarParams` | `StudyEditState` | `:167` |
| `study.setGuitarStereo` | Activa/desactiva el reparto estéreo de guitarras; guarda y relee. | `StudyGuitarStereoParams` | `StudyEditState` | `:176` |

Nota: `study.snapshot`, `setKey`, etc. no exigen nada más que tema abierto. `study.analyze` además exige cola de análisis y separación terminada.

### Eventos

| evento | cuándo | payload | emit |
|---|---|---|---|
| `study.state` | Cambia el transporte o una edición; coalescido por turno; también si `playing` cambia desde fuera (fin del tema). | `StudyTransport` | `AC/StudyMethods.swift:380` |
| `study.position` | Posición del reproductor; máx. ~30 Hz (separación mínima 0.9/30 s); emite si suena o si la posición/`playing` cambió. | `StudyPositionEvent` | `:468` |
| `study.levels` | Medidores por canal; máx. ~30 Hz; solo si suena o hubo sonido en la emisión anterior (al callar sale una última a -120 dB y se para). | `StudyLevelsEvent` | `:477` |
| `study.analysis` | Cambia el estado del análisis (se deduplica por proyecto+estado+error). | `StudyAnalysisEvent` | `AC/StudyEdits.swift:315` |
| `study.guitars` | Cambia el trabajo de reparto de guitarras; la página relee `study.snapshot`. | `StudyAnalysisEvent` (campos `state`: `idle|processing|failed`) | `:399` |

`StudyErrorEvent` (`StudyMethods.swift:158`) está declarado pero **no se emite en ningún sitio** (grep `StudyErrorEvent` solo da la declaración): no existe evento `study.error`.

### DTO (todos sintetizados; optional nil = clave ausente)

Parámetros (solo `Decodable`):

- `StudyOpenParams` (`StudyMethods.swift:163`): `projectId: String` (UUID como cadena; si no, `bad-params`).
- `StudySeekParams` :164 `{seconds: Double}`. `StudyRateParams` :165 `{rate: Double}`. `StudyCapoParams` :167 `{capo: Int}`. `StudyMasterParams` :170 `{gainDB: Double}`.
- `StudyTransposeParams` :166 `{semitones: Int?, fineCents: Double?}`.
- `StudyLoopParams` :168 `{start: Double?, end: Double?, name: String?}`.
- `StudyMixParams` :169 `{channel: String, gainDB: Double?, mute: Bool?, solo: Bool?}`. `channel` = `StudyChannel.id`.
- `StudyMetronomeParams` :171 `{on: Bool?, gainDB: Double?}`.
- `StudySetKeyParams` (`StudyEdits.swift:48`) `{key: String?}`.
- `StudySetChordParams` :49 `{start: Double, end: Double, index: Int?, label: String?}`. `index` 0...169 (0...167 acordes, 168 = «?», 169 = «N»: `AC/StudyEditsBridge.swift`); `label` tipo `C:min`, `F#:7`, `N`.
- `StudyChordRangeParams` :50 `{start, end: Double}`. `StudySplitChordParams` :51 `{at: Double}`.
- `StudyMarkSectionParams` :52 `{start: Double, end: Double, solo: Bool?, snap: String?}`; `snap` = `none` (por defecto) `|beat|bar`.
- `StudyDeleteSectionParams` :53 `{id: String}` (UUID de sección). `StudyPreviewSectionEdgeParams` :54 `{id: String, start: Bool, to: Double}` (`start` true = borde de inicio). `StudyNudgeSectionParams` :55 `{id: String, start: Bool, forward: Bool, bar: Bool?}`.
- `StudyRenameGuitarParams` :56 `{role: String, name: String}`; `role` = `rhythm|left|right|lead`. `StudyGuitarStereoParams` :57 `{on: Bool}`.
- `StudyUpdateSectionParams` :60 `{id: String, name: String?, start: Double?, end: Double?, solo: Bool?, snap: String?, color: Int?}` con `init(from:)` a mano: **`color` distingue ausente (no cambia) de `null` (automático)**; número `0...6` (paleta de 7: `SectionEditor.paletteCount`, `Store/SectionEditor.swift:89`). `snap` = `none` (por defecto) `|beat|bar|chord`. Si llegan `start` y `end` y `start` > inicio actual, mueve primero el final.

Resultados y payloads (`Codable`):

- `StudyTransport` (`StudyMethods.swift:47`): `playing: Bool`, `position: Double`, `duration: Double`, `rate: Double`, `transpose: Int`, `fineCents: Double`, `capo: Int`, `metronome: StudyMetronome`, `loop: StudyLoop?`, `masterGainDB: Double`, `channels: [StudyChannel]`, `anySolo: Bool`, `audioError: String?`, `outputName: String`.
- `StudyMetronome` :35 `{on: Bool, gainDB: Double, available: Bool}` (`available` = hay rejilla de pulsos).
- `StudyLoop` :41 `{start: Double, end: Double, name: String?}`.
- `StudyChannel` :25 `{id: String, kind: String, guitarRole: String?, name: String, gainDB: Double, muted: Bool, solo: Bool}`. `kind`: `vocals|drums|bass|guitar|piano|other` (orden y nombres fijos: Voz, Batería, Bajo, Guitarra, Piano, Resto). `id` = `kind` salvo guitarras separadas: `guitar_rhythm|guitar_L|guitar_R|guitar_lead` (con `guitarRole` = `rhythm|left|right|lead` y `name` el de la guitarra). Solo salen los canales que existen en el mezclador.
- `StudyOpenResult` :124: `projectId: String`, `title: String`, `artist: String?`, `duration: Double`, `sampleRate: Double`, `loadError: String?`, `audio: StudyAudioInfo`, `transport: StudyTransport`, `emptyStems: [StudyEmptyStem]`, `usesSeparatedGuitars: Bool`, `analysis: StudyAnalysisInfo`, `chordOverrides: [StudyOverrideInfo]`, `sections: [StudySectionInfo]`, `unappliedSections: Bool`, `loops: [StudySavedLoop]`, `guitars: StudyGuitarsInfo`.
- `StudyAudioInfo` :119 `{mode: String, outputName: String}`; `mode` = `simulated|device` (`AC/StudyAudio.swift:6`).
- `StudyEmptyStem` :91 `{kind: String, name: String}` (stem silencioso, sin WAV).
- `StudyAnalysisInfo` :80: `state: String` (`missing|analyzing|ready|failed`), `error: String?` (solo con `failed`), `beats: [Double]`, `downbeats: [Double]`, `bpm: Double?`, `beatsPerBar: Int?`, `chords: [StudyChord]`, `key: StudyKey`.
- `StudyChord` :65 `{start, end: Double, index: Int, name: String, overridden: Bool}` (`overridden` true = corregido a mano; son los acordes efectivos).
- `StudyKey` :73 `{detected: String?, override: String?, effective: String?, confidence: Double?}`.
- `StudyOverrideInfo` :96 `{start, end: Double, index: Int}`.
- `StudySectionInfo` :102 `{id: String, name: String, start: Double, end: Double, solo: Bool, color: Int?, paletteIndex: Int?}`. `color` ausente = automático; `paletteIndex` = índice de paleta efectivo (0...6).
- `StudySavedLoop` :112 `{id: String, name: String, start: Double, end: Double}`.
- `StudyGuitarsInfo` (`StudyEdits.swift:20`): `stereoSplit: Bool`, `usesSeparatedGuitars: Bool`, `names: [String: String]` (claves `rhythm|left|right|lead`, siempre las cuatro), `process: String` (`idle|processing|failed`), `error: String?`, `saveError: String?`.
- `StudyEditState` :32: `analysis: StudyAnalysisInfo`, `chordOverrides`, `sections`, `unappliedSections: Bool`, `loops`, `guitars: StudyGuitarsInfo`, `added: String?` (UUID de la sección recién creada; solo con `markSection`), `transport: StudyTransport`.
- `StudyPreviewSections` :30 `{sections: [StudySectionInfo]}`.
- `StudyPositionEvent` (`StudyMethods.swift:144`) `{seconds: Double, playing: Bool}`.
- `StudyLevelsEvent` :154 `{channels: [String: StudyMeter]}` (clave = `StudyChannel.id`); `StudyMeter` :149 `{rmsDB: Double, peakDB: Double}` (no finito se sustituye por -120).
- `StudyAnalysisEvent` (`StudyEdits.swift:43`) `{state: String, error: String?}`; en `study.analysis` `state` es `missing|analyzing|ready|failed`; en `study.guitars` es `idle|processing|failed`.

### Códigos de `RPCError` de study

- `not-open`: sin tema abierto (`StudyMethods.swift:343`; `StudyEdits.swift:195,203,308,319,460,485`); tema cerrado durante la operación (`StudyEdits.swift:207,327`).
- `bad-params`: `projectId` no UUID (`StudyMethods.swift:279`); canal desconocido (`:262`); `StudyEdits.swift:129` (rango), `:170` (role), `:268` (id no UUID), `:408` (key), `:420`, `:426`, `:431`, `:435` (setChord), `:443` (at), `:466`, `:473` (markSection), `:488` (to), `:498`, `:501` (color), `:505` (snap).
- `internal`: no se pudo leer `project.json` (`StudyMethods.swift:284`).
- `load-failed`: `loadError` del reproductor, o sin stems que reproducir (`AC/StudyBacking.swift:127,128`; solo en `study.play`).
- `audio-unavailable`: la salida de audio no abre (`StudyBacking.swift:135`; solo `study.play`).
- `not-found`: no hay sección con ese id (`StudyEdits.swift:270`).
- `save-failed`: no se pudo guardar opciones de guitarras (`StudyEdits.swift:161`, `:183`).
- `not-separated`: tema sin separación terminada (`:323`). `analysis-unavailable`: sin cola de análisis (`:321`) o sin analizador/aún en cola de separación (`:338`). `analyze` también puede devolver los códigos de `JobEngine.map(error)` (`:326`; ver `contrato.md`, import/cola).
- `no-analysis`: `setKey` sin análisis (`:411`).
- `cannot-split`: sin acorde en `at` (`:446`) o el pulso cae a < 50 ms de un extremo (`:450`).
- `section-not-created`: la sección empieza dentro de otra o dura menos de `SectionEditor.minLength` = 0.5 s (`:476`).

Pendiente del área: ninguno.

## tab y tab.songsterr

`TS/` = `AC/TabService.swift`; `TM/` = `AC/TabMethods.swift`; `TT/` = `AC/TabTypes.swift`; `SS/` = `AC/TabSongsterr.swift`. Todos los DTO son sintetizados (nil = clave ausente). La partitura para alphaTab sale de `tab.score` (campo `json`, esquema `tf-score` v1 descrito en la cabecera de `App/Resources/alphaTab/tf-bridge.js:1-19`); las pistas se indexan allí por posición (`trackIDs`).

### Métodos `tab.*` (register en `TM/`)

| método | qué hace | params | result | línea |
|---|---|---|---|---|
| `tab.open` | Abre la tablatura de un tema (abre el estudio si no lo está) y la carga. | `TabOpenParams` | `TabState` | :7 |
| `tab.state` | Estado actual; `not-open` si no hay tablatura. | `Empty` | `TabState` | :8 |
| `tab.close` | Guarda lo editado y cierra (el estudio sigue abierto). | `Empty` | `Empty` | :12 |
| `tab.setSource` | `"automatic"` guarda la fuente; `"songsterr"` abre la hoja (se guarda con `tab.songsterr.accept`). | `TabSourceParams` | `TabState` | :13 |
| `tab.score` | JSON de la partitura para la página. | `TabTrackParams` (`track` opcional; por defecto la seleccionada) | `TabScoreResult` | :15 |
| `tab.selectTrack` | Selecciona pista (borra selección y tramo). `track` obligatorio. | `TabTrackParams` | `TabState` | :16 |
| `tab.transcribe` | Pone en cola la pista (o todas las pendientes/fallidas) y transcribe en segundo plano. | `TabTrackParams` | `TabQueuedResult` | :20 |
| `tab.cancel` | Cancela la transcripción en curso. | `Empty` | `CancelResult {cancelled: Bool}` (`AC/ImportMethods.swift:70`) | :21 |
| `tab.beatClick` | Clic de la página en un pulso (con `shift` extiende el tramo). | `TabClickParams` | `TabState` | :22 |
| `tab.beatDrag` | Arrastre sobre pulsos: extiende el tramo. | `TabClickParams` | `TabState` | :26 |
| `tab.noteClick` | Clic en una nota (`string` base 0 del JSON; se convierte). Ignorado con `shift`. | `TabClickParams` | `TabState` | :30 |
| `tab.select` | Selecciona un punto de la rejilla (`beat` índice global, `tick` 0..<`TabScore.ticksPerBeat`) y salta el reproductor. | `TabSelectParams` | `TabState` | :34 |
| `tab.span` | Acción sobre el tramo seleccionado. | `TabSpanParams` | `TabState` | :37 |
| `tab.toggleMute` | Mute de la pista (`track` obligatorio). | `TabTrackParams` | `TabState` | :38 |
| `tab.toggleSolo` | Solo de la pista (`track` obligatorio). | `TabTrackParams` | `TabState` | :43 |
| `tab.setListening` | Oír la transcripción sintetizada de una pista (`track` obligatorio). | `TabListeningParams` | `TabState` | :48 |
| `tab.setAllListening` | Igual para todas (`on` true = «Transcripción», false = «Stems»); `track` se ignora. | `TabListeningParams` | `TabState` | :54 |
| `tab.edit` | Operación de edición/teclado (ver `op`). | `TabEditParams` | `TabState` (con `handled` en `op:"key"`) | :58 |
| `tab.exportName` | Nombre sugerido «Artista - Título.gp». | `Empty` | `TabExportNameResult` | :59 |
| `tab.export` | Guarda el `.gp` generado por la página (`data` base64) en `path` o donde elija el diálogo del anfitrión. | `TabExportParams` | `TabExportResult` | :60 |

`TabEditParams.op` y sus campos: `digit` (`value` 0...9), `moveString` (`up`, por defecto true), `delete`, `duration` (`sign` <0 acorta, si no alarga), `hit` (`piece`: `kick|snare|hiHat|openHiHat|tom|crash`), `ornament` (`name`: `palmMute|letRing|hammerPull|slide|bend|vibrato|whammyVibrato|dead|ghost|accent|heavyAccent|staccato|naturalHarmonic|artificialHarmonic|grace|tapping|tie|pickDown|pickUp|flam`), `key` (`key` = `KeyboardEvent.key`, más `shift`,`ctrl`,`alt`), `addNote`, `move` (`forward`, por defecto true), `tuning` (`track` y `preset`: `standard|halfStepDown|wholeStepDown|dropD|custom`), `undo`, `redo`, `editMode` (`on`, por defecto true), `deselect` (`TS/:979-1015`). `TabSpanParams.action`: `clear|apply|extendForward|extendBack` (`TS/:619-622`). `tab.edit` exige `phase == "ready"`.

### Eventos `tab.*`

| evento | cuándo | payload | emit |
|---|---|---|---|
| `tab.state` | Cualquier cambio (coalescido por turno). | `TabState` | `TS/:1245` |
| `tab.progress` | Transcripción: `transcribing` (fracción), `done`, `failed`, `cancelled`. | `TabProgressEvent` | `TS/:434,439,462,500,509` |
| `tab.selection` | Cambia la selección; `bar:-1` = sin selección. | `TabSelectionEvent` | `TS/:550,556` |
| `tab.range` | Cambia el tramo; todo `-1`/0 = sin tramo. | `TabRangeEvent` | `TS/:632,634` |
| `tab.songsterr.state` | Cambia la hoja de Songsterr abierta. | `SongsterrSheetState` | `SS/:437` |

### DTO de `tab` (`TT/`)

- `TabState` (:48): `projectId: String`, `phase: String` (`waitingAnalysis|empty|working|ready|failed|choosingSource`), `error: String?` (solo `failed`), `header: String?` («4/4 · 120 BPM»), `source: String?` (`automatic|songsterr`; ausente = sin elegir), `tracks: [TabTrackInfo]`, `selectedTrack: String?`, `notices: [String]`, `canUndo`, `canRedo`, `editMode`, `graceMode: Bool`, `listenMode: String` (`stems|transcription|mixed`), `anySolo: Bool`, `selection: TabSelectionInfo?`, `span: TabSpanInfo?`, `revision: Int`, `flash: String?`, `handled: Bool?` (solo `tab.edit op:"key"`).
- `TabTrackInfo` (:12): `id`, `name`, `kind` (`guitar|bass|drums|vocal`), `tuning: TabTuningInfo?`, `customTuning: TabTuningInfo?`, `origin` (`songsterr|stem|extra`), `playerTrack: String?` (id del canal de `study`), `transcription` (`ready|queued|transcribing|missing|failed`), `progress: Double?`, `error: String?`, `fingerprint: TrackSourceFingerprint?` (`{path: String, size: Int64, modifiedMillis: Int64, modelVersion: String, parametersVersion: Int}`, TabKit), `noteCount: Int`, `muted`, `solo`, `dimmed`, `listening: Bool`, `synth: String?` (`rendering|ready|failed`).
- `TabTuningInfo` (:6) `{preset: String, name: String, strings: [Int]}` (MIDI de la cuerda 1, la más aguda, a la última).
- `TabSelectionInfo` (:25) `{track: String, beat: Int, tick: Int, string: Int?, summary: String?, barRange: TabBarRange?}`; `TabBarRange` (:35) `{bar: Int (0-based), start: Double, end: Double}`. `TabSpanInfo` (:41) `{startTick: Int, endTick: Int}`.
- `TabScoreResult` (:70) `{json: String (cadena JSON), trackIndex: Int, trackIDs: [String], revision: Int}`.
- `TabProgressEvent` (:78) `{state: String (transcribing|done|failed|cancelled), track: String, fraction: Double, error: String?}`.
- `TabSelectionEvent` (:85) `{bar: Int, fraction: Double}`; `TabRangeEvent` (:86) `{startBar: Int, startFraction: Double, endBar: Int, endFraction: Double}`.
- `TabQueuedResult {queued: [String]}`; `TabExportNameResult {fileName}`; `TabExportResult {saved: Bool, path: String?}` (`saved:false` sin `path` = diálogo cancelado).
- Params: `TabOpenParams {projectId}`, `TabTrackParams {track: String?}`, `TabSourceParams {source}`, `TabClickParams {track: Int, bar: Int, beat: Int, shift: Bool?, string: Int?}` (índices de alphaTab/JSON), `TabSelectParams {track: String, beat: Int, tick: Int, string: Int?}`, `TabSpanParams {action}`, `TabListeningParams {track: String?, on: Bool}`, `TabExportParams {data: String (base64), path: String?}`, `TabEditParams {op: String, value: Int?, up: Bool?, sign: Int?, piece: String?, name: String?, key: String?, shift: Bool?, ctrl: Bool?, alt: Bool?, forward: Bool?, track: String?, preset: String?, on: Bool?}`.

### Métodos `tab.songsterr.*` (register `SS/:762-782`)

Todos devuelven `SongsterrSheetState` salvo `accept` y `automatic` (`TabState`). Params `Empty` salvo indicado. Sin `tab.open` previo, `not-open`.

| método | qué hace | línea |
|---|---|---|
| `open` | Abre la hoja (búsqueda automática por artista/título). | :762 |
| `state` / `close` | Estado actual / cierra la hoja. | :763 / :764 |
| `search` | Repite la búsqueda. | :765 |
| `retry` | Reintenta el paso fallido. | :766 |
| `select` (`SongsterrSelectParams {songId: Int}`) | Marca un tema de los resultados y carga su detalle. | :767 |
| `link` (`SongsterrLinkParams {link: String}`) | Usa un enlace de Songsterr pegado. | :770 |
| `use` | Usa el tema marcado: lee la tablatura y propone el emparejamiento (`stage` pasa a `working` y luego `pairing`). | :773 |
| `review` | Abre el emparejamiento para revisar. | :774 |
| `retryImport` | Repite la última importación. | :775 |
| `back` | Vuelve de `pairing`/`failed` a `choosing`. | :776 |
| `assign` (`SongsterrAssignParams {stemId: String, track: Int?, solo: Int?}`) | Asigna una pista de Songsterr a un stem; `track` ausente/null = automática (o «ninguna» en un solo); `solo` = índice de la sección de solo (ausente = stem entero). | :777 |
| `allAutomatic` | Todo el emparejamiento en automático. | :780 |
| `accept` | Acepta: guarda rejilla y fuente y sustituye la partitura. Devuelve `TabState`. | :781 |
| `automatic` | Elige transcripción automática y cierra la hoja. Devuelve `TabState`. | :782 |

### DTO de Songsterr (`SS/:210-345`)

- `SongsterrSheetState` (:315): `open: Bool`, `stage: String` (`choosing|working|pairing|failed`), `query: String?` («Artista · Título»), `search: SongsterrSearchInfo?`, `results: [SongsterrResultInfo]`, `selected: SongsterrSongInfo?`, `loadingSongId: Int?`, `detailIssue: SongsterrIssueInfo?`, `linkIssue: SongsterrIssueInfo?`, `busy: Bool`, `canUse: Bool`, `workingText: String?` (con `working`), `failure: SongsterrIssueInfo?` (con `failed`), `pairing: SongsterrPairingInfo?` (con `pairing`). Cerrada: solo `open:false`, `stage` y los arrays vacíos (nil omitidos).
- `SongsterrSearchInfo` (:264) `{phase: String (idle|searching|results|failed), issue: SongsterrIssueInfo?}`.
- `SongsterrIssueInfo` (:210) `{kind: String (noResults|rateLimited|offline|formatChanged|invalidLink|other), message: String, canRetry: Bool, suggestion: String?}`.
- `SongsterrResultInfo` (:244) `{songId: Int, artist, title: String, selected: Bool, loading: Bool, previewUrl: String?}`.
- `SongsterrSongInfo` (:255) `{songId: Int, revisionId: Int, artist, title: String, tracks: [SongsterrTrackInfo], previewUrl: String?}`; `SongsterrTrackInfo` (:234) `{partId: Int, name, instrument: String, tuning: [Int]?, tuningText: String}` («E A D G B E», «-» en batería).
- `SongsterrPairingInfo` (:306) `{intro: String, slots: [SongsterrSlotInfo], extraNames: [String], extraText: String?, warnings: [String]}`.
- `SongsterrSlotInfo` (:291) `{stemId, name, kind, role: String, track: Int?, confidence: Double?, confidenceText: String?, choices: [SongsterrChoiceInfo], solos: [SongsterrSoloRowInfo]}` (`role`: `lead` para guitarra solista, si no el raw de `SongsterrStemRole`; `solos` solo se rellena en el slot lead).
- `SongsterrSoloRowInfo` (:278) `{index: Int, start: Double, end: Double, clock: String, track: Int?, confidence: Double?, confidenceText: String?, choices: [SongsterrChoiceInfo]}`.
- `SongsterrChoiceInfo` (:270) `{track: Int, name: String, similarity: Double?, label: String}`.

### Códigos de `RPCError` de tab

- `not-open`: `TM/:9,66`, `TS/:224` (sin tablatura o el estudio cambió), `TS/:161` (no se pudo abrir el tema); Songsterr `SS/:426` (hoja cerrada), `SS/:448`.
- `bad-params`: `projectId` (`TS/:157`), `source` (`:323`), pista desconocida (`:350,358,403,656,1097,1105`), `«track»` ausente (`TM/:17,39,44,49`), acción de tramo (`:623`), posición fuera (`:660`), `value` (`:985`), `piece` (`:992`), `name` de adorno (`:997`), tuning (`:1005`), `op` (`:1014`), base64 (`:1220`).
- `not-ready`: `TS/:347,400,981,1218`; Songsterr `SS/:484,492,501,616,622,630`.
- `unsupported`: `TS/:325` (sin biblioteca), `SS/:402` (el anfitrión no lee Songsterr), `SS/:633`.
- `internal`: `TS/:327,1229`; `SS/:648,653`.
- `tab.transcribe`/`tab.cancel` no lanzan códigos propios más allá de los anteriores.

### Protocolo página (`tab.html` + `tf-bridge.js`) <-> anfitrión

Transporte hoy (macOS): JS->anfitrión con `window.webkit.messageHandlers.tf.postMessage(obj)` (objeto, no cadena; `post` en `tf-bridge.js:370`); si falla se ignora. Anfitrión->JS: llamadas a `window.TF.<fn>(...)` (`App/Sources/TabWebHost.swift:92-113`). Para Flutter hay que reemplazar ese canal (decisión de diseño pendiente; no hay equivalente en el repo). Todos los mensajes JS->anfitrión llevan `event`.

JS->anfitrión (`TabWebHost.swift:66-77` los decodifica):

| `event` | campos | cuándo | línea JS |
|---|---|---|---|
| `ready` | `alphaTab: String` (`typeof alphaTab`, «object» si cargó) | al cargar `tab.html` | `tab.html:29` |
| `rendered` | ninguno | tras cada `postRenderFinished` (re-aplica rango, selección y cursor pendientes) | `tf-bridge.js:412` |
| `beatClick` | `track: Int`, `bar: Int`, `beat: Int`, `shift: Bool` | `beatMouseDown` | `:423` |
| `beatDrag` | `track`, `bar`, `beat` (Int) | `beatMouseMove` con botón pulsado, solo al cambiar de pulso | `:430` |
| `noteClick` | `track`, `bar`, `beat`: Int, `string: Int` (base 0, cuerda grave = 0), `fret: Int`, `shift: Bool` | `noteMouseDown` | `:436` |
| `cursor` | `bar: Int`, `x: Number`, `y: Number` (px de la página; sin `h`) | en cada `setCursor` que coloca el cursor (se omite en el log) | `:522` |
| `error` | `message: String` (con pila) | `api.error`, excepciones de funciones protegidas, `window.onerror`, `unhandledrejection`, fallo de init | `:418`, `:586`, `tab.html:13-31` |

`track` = índice de pista en el JSON de `tab.score` (se traduce a `trackIDs[track]`); el anfitrión reenvía `beatClick/beatDrag/noteClick` a los métodos `tab.*` homónimos con los mismos campos (`fret` se descarta: `TabClickParams` no lo tiene).

Anfitrión->JS (`window.TF`, `tf-bridge.js:583-590`; todas con `guarded`: una excepción sale como `error`):

| función | argumentos | efecto |
|---|---|---|
| `load(json, trackIndex)` | `json`: cadena (o objeto) = `TabScoreResult.json`; `trackIndex: Int` | Construye la partitura y pinta la pista; la primera vez crea alphaTab. Conserva el scroll. |
| `selectTrack(index)` | `Int` | Repinta otra pista sin reconstruir. |
| `setCursor(bar, fraction, follow)` | `Int`, `0..1`, `Bool` opcional | Cursor en compás/fracción; `follow` desplaza la página. Si no hay render aún se guarda y se aplica tras `rendered`. |
| `setCursorTime(seconds, follow)` | `Double`, `Bool` | Convierte segundos a compás/fracción con `bars[].start` del JSON (lineal dentro del compás). |
| `setSelection(bar, fraction)` | `Int`, `0..1` | Marca de selección; `bar < 0` la oculta. Diferida igual que el cursor. |
| `setRange(startBar, startFraction, endBar, endFraction)` | `Int, Double, Int, Double` | Rectángulo(s) del tramo, uno por compás; `startBar < 0` lo oculta. Se repinta tras cada render. |
| `exportGpBase64(options)` | objeto (hoy `{}`) | Devuelve (síncrono) el `.gp` en base64; `TabWebHost` usa `callAsyncJavaScript`. Si falla relanza la excepción además del `error`. |

Mapeo con eventos del núcleo: `tab.selection {bar, fraction}` -> `setSelection(bar, fraction)`; `tab.range {startBar,...}` -> `setRange`; la posición `study.position.seconds` -> `setCursorTime`.

## Huecos

- Nombre de `SongsterrStemRole` (valores crudos de `role`/`kind` en `SongsterrSlotInfo`) y de `kind` del slot: no volcados (en `SS/:568,744`, `slotKind`/`role(of:)`).
- Semántica fina de `fraction` en `tab.selection` (`local tick / (beatCount*ticksPerBeat)`, `TS/:556`) y de `ticksPerBeat` (constante de TabKit): valor numérico no leído.
- Orden/frecuencia exactos de `tab.progress` `fraction` (:509) y los textos `flash`/`notices`: no volcados.
- Esquema `tf-score` solo referenciado, no copiado.
- `TabWebHost.swift` (macOS) fue leído solo por grep; el comportamiento de reintento de `load` antes de `ready` no está verificado.
