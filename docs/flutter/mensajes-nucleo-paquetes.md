# Mensajes de los paquetes que llegan a la interfaz (ADR-021 §16)

Estado: casi completo. Hechos: Store, SourceKit, ModelKit, NativeKit, AudioKit, TabKit. Parcial (solo la parte que llega a la interfaz, detalles `invalidInput`/`Failure` sin enumerar uno a uno): StemKit, VideoKit, StudyKit. AnalysisKit, HeadRushKit, MatchKit y Tone3000Kit: 0 literales con acento (no revisados sin acento). `tf-audio`/`tf-video` (CLI de pruebas, no usado por AppCore): excluidos.
Los textos de `AppCore` (`SourceMessages`, `RPCError` propios, `SeparationFailure`) los inventaría `mensajes-nucleo.md`. Números con coma decimal: «(coma)».

## Recuento por paquete

| Paquete | Textos que llegan | Sin confirmar |
|---|---|---|
| Store | 12 + 4 casos de error + 5 conductos de fallo | 2 |
| SourceKit | 22 | 0 |
| ModelKit | 8 | 0 |
| NativeKit | 8 | 8 |
| AudioKit | 33 (16 `AudioSessionError`, 10 `RecordBlock`, 3 WASAPI, 4 otros) | 6 |
| TabKit | 11 | 1 |
| StemKit | 1 familia (`SeparationError`) | 1 |
| VideoKit | 1 familia | 1 |
| StudyKit | 1 familia | 1 |

## Store

| fichero:línea | caso | código | texto (es) | args | llega por |
|---|---|---|---|---|---|
| Store/Guitars.swift:13-16 | `GuitarRole.defaultName` | `store_guitar_rhythm` / `_left` / `_right` / `_lead` | Guitarra rítmica / Guitarra izq. / Guitarra der. / Guitarra solista | — | `StudyEdits.swift:173`, `StudySession.swift:59` → DTO guitarras y `project.json` |
| Store/SectionEditor.swift:33 | sección por defecto | `store_section_default` | Sección {n} | n:int | `StudyEdits.swift:278` (`editSections`) → DTO secciones |
| Store/SectionEditor.swift:30-31 | solo | `store_section_solo` / `store_section_solo_n` | Solo / Solo {n} | n:int ≥2 | ídem |
| Store/Recording.swift:67 | `channelName` | `store_take_channel` | Tú · {partName} | partName:string (usuario) | `RecordMethods.swift:695` |
| Store/Recording.swift:174 | `reconstructedRecording` | `store_part_recovered` | Parte recuperada {n} | n:int | `RecordController.swift:290`, `project.json` |
| Store/TabSources.swift:46 | `TabSource.name` | `store_tabsource_bass` / `_drums` | Bajo / Batería | — | `TabService.swift:237` |
| Store/Files.swift:326 | nombre de montaje | `store_untitled` | Sin título | — | `MontageController.swift:916` |
| Store/Files.swift:349 | `FolderNaming` | `store_untitled` | Sin título | — | **sin confirmar** (no aparece en AppCore) |

Los nombres por defecto se persisten en español en `project.json`; `SectionEditor.isDefaultName` (SectionEditor.swift:36-38) los detecta por literal. Decisión de Jorge: guardar español y traducir al mostrar, o guardar traducido (rompe la detección).

Conductos de fallo con texto de otro paquete (`error.localizedDescription`): `separationFailed` (Library.swift:489-500, también `project.json` `separation.error`) → `JobQueue.swift:221`; `analysisFailed` (Library.swift:834,853) → `JobQueue.swift:234`; `guitarSplitFailed` (Library.swift:988-990) → `JobQueue.swift:241-248`; `rateMigrationFailed` (Library.swift:1026) → `JobQueue.swift:252` (**sin confirmar** que se muestre); `SkippedProject.reason = String(describing: error)` (LibraryIndex.swift:95) → `LibraryMethods.swift:172` (volcado Swift: `store_index_skipped` {folderName, detail}). Decisión de Jorge: `AppCore` conserve el `code` del error de origen en `args.cause` en vez de aplanar a string; si no, Dart solo puede mostrar el `message` en español.

Errores sin `errorDescription` (`JobQueue.swift:362-380`): `LibraryError.destinationNotEmpty(URL)` (Library.swift:94) y `.sizeMismatch(String)` (:95) caen en `internal` con volcado Swift → `store_destination_not_empty` {path}, `store_size_mismatch` {detail}; `.busy` solo se mapea en `cleanup` (JobQueue.swift:334), decisión de Jorge: mapear en `map`; `ProjectFileError.unsupportedSchema(found:supported:)` (Files.swift:102) sale en `No se pudo leer project.json: \(error)` (`StudyMethods.swift:284`, `TakeViewMethods.swift:308`, `MontageMethods.swift:540`) → `store_unsupported_schema` {found:int, supported:int}; `AudioSettingsError` (3 casos, AudioSettings.swift:121-126) → `bad-params` con `RecordBlock.invalidChannels.message` (`AudioMethods.swift:312`), se pierde el caso; `CocoaError` «MoveFileEx error {GetLastError}» (WindowsFileMove.swift:13) vía `describe` (técnico en inglés). `projectNotFound`, `workInProgress`, `unsafeDeletion`, `emptyTitle`, `takeNotFound`: texto de AppCore.

## SourceKit

`SourceError` → `SourceMessages.text(for:)` (AppCore).

| fichero:línea | caso | código | texto (es) | args | llega por |
|---|---|---|---|---|---|
| Spotify/SpotifySearchError.swift:13-17 | 5 casos | `source_spotify_missing_credentials` / `_rejected` / `_rate_limited` / `_offline` / `_bad_response` | Búsqueda en Spotify no disponible: falta la clave (.env) / Spotify ha rechazado la clave / Spotify pide esperar {n} s / Sin conexión con Spotify / Spotify ha devuelto una respuesta inesperada | n:int s (solo rate_limited) | `LinkMethods.swift:197-205` (`RPCError.message = e.localizedDescription`; el código ya es `spotify-…`) |
| Songsterr/SongsterrLookup.swift:40-44 | `SongsterrIssue` | `source_songsterr_no_results` / `_rate_limited` / `_offline` / `_format_changed` / `_invalid_link` | No está en Songsterr. / Songsterr está limitando las peticiones. Espera un poco y vuelve a intentarlo. / No se pudo conectar con Songsterr. Comprueba la conexión. / Songsterr ha cambiado su formato. / Ese enlace no es de Songsterr. | — | `TabSongsterr.swift:227` (`message = issue.message`) |
| :33 | `.other` HTTP≠429 | `source_songsterr_http` | Songsterr respondió con el error {c}. | c:int | ídem |
| :35 | `.other(localizedDescription)` | `source_songsterr_other` | texto del sistema | detail:string | ídem, tal cual |
| YtDlpClient.swift:147,163,178 | detail de `extractorBroken` | `source_ytdlp_json_unreadable` / `_search_json_unreadable` / `_list_json_unreadable` | JSON de yt-dlp ilegible / JSON de búsqueda ilegible / JSON de lista ilegible | — | `SourceMessages.text` → `detail` |
| :212 | cola stderr yt-dlp | `source_ytdlp_stderr` | (inglés, no controlado) | tail:string | ídem |
| AudioTranscoder.swift:21 | `ffmpegFailed` | `source_ffmpeg_no_output` | ffmpeg no dejó {file} | file:string | `SourceMessages.text` → `lastLines` |
| :18 | stderr ffmpeg | `source_ffmpeg_stderr` | (inglés) | detail:string | ídem |
| YtDlpUpdater.swift:42,56 | `updateFailed` | `source_update_asset_missing` / `_not_runnable` | {sums} no lista {asset} / el yt-dlp descargado no arranca | sums,asset:string fijos | ídem |
| ProcessRunning.swift:118; PlaylistImporter.swift:387; SourceImporter.swift:255 | `launchFailed(localizedDescription)` | `source_launch_failed` | texto del sistema | detail:string | ídem |

## ModelKit

Llegan por `ModelState.failed(error.localizedDescription)` (ModelStore.swift:297,347) → `SettingsMethods.swift:360` (`message`); `modelsDelete` (`SettingsMethods.swift:401-404`) usa `errorDescription`.

| fichero:línea | caso | código | texto (es) | args |
|---|---|---|---|---|
| Downloading.swift:19 | `httpStatus` | `model_http_status` | El servidor respondió con el código HTTP {s}. | s:int |
| ModelStore.swift:25 | `bundledResourceMissing` | `model_bundled_missing` | No se encuentra {n} entre los recursos de la app. | n:string |
| :26 | `unknownModel` | `model_unknown` | Modelo desconocido: {id}. | id:string |
| :27 | `hashMismatch` | `model_hash_mismatch` | La suma SHA-256 no coincide (esperada {e}…, obtenida {a}…). | e,a:string (12 hex) |
| :28 (+:422) | `unzipFailed` | `model_unzip_failed` | No se pudo descomprimir el modelo: {tool} terminó con código {status}. {stderr} | tool:string, status:int, stderr:string (inglés) |
| :29 | `packageNotFound` | `model_package_not_found` | El archivo descargado no contiene {n}. | n:string |
| :33 | `busy` | `model_busy` | El modelo {id} se está instalando. | id:string; en `modelsDelete` AppCore lo cambia por `busy` |
| ModelDescriptor.swift:118 | `displayName` | `model_name_separation` | Separación de stems | — (`SettingsMethods.swift:364`; solo el modelo `separatorBSRoformerSW`) |

## NativeKit

AppCore no referencia `PlatformError|AudioFileError|OnnxError` (grep sin resultados): llegarían por los conductos genéricos `describe`/`localizedDescription`. Todos «sin confirmar».

| fichero:línea | caso | código | texto (es) | args |
|---|---|---|---|---|
| NativeAudioFile.swift:101-102 | `AudioFileError.unreadable/unwritable` | `native_audio_unreadable` / `_unwritable` | No se puede leer el audio: {s} / No se puede escribir el audio: {s} | s:string |
| AudioFileIO.swift:61,235,278 | detalles | `native_audio_seek_out_of_range` / `_no_buffer` | posición {frame} fuera de 0...{frameCount} / sin búfer para {format} | frame,frameCount:int; format:string |
| PlatformError.swift:9 | `.unsupported` | `native_platform_unsupported` | No disponible en este sistema: {what} | what:string |
| NativeONNX.swift:101,201,289 | `OnnxError.runtime` (no `LocalizedError`: `localizedDescription` da el texto genérico de Foundation y pierde el detalle) | `native_onnx_runtime` | ruta no válida: {path} / salida {name} vacía / sin onnxruntime.dll, o más antigua que las cabeceras (API {n}) | path,name:string; n:int |

## AudioKit

`AudioSessionError.errorDescription` llega por `AudioController.swift:431` (`sessionError`), `:613` (calibración `.error`), `:687` («No se pudo empezar a grabar: …»), `:704` («No se pudo guardar la toma: …»). `RecordBlock.message` (AppLogic.swift:37-50): usado en AppCore vía `RecordingGate` (`AudioController.swift`) y `RecordBlock.invalidChannels.message` (`AudioMethods.swift:313`). Frecuencias en kHz con coma: `khz()` (AudioSession.swift:72-74) y `khzText` (AppLogic.swift:12) → «44,1 kHz», «48 kHz».

| fichero:línea | caso | código | texto (es) | args |
|---|---|---|---|---|
| AudioSession.swift:77 | `noInputDevice` | `audio_no_input_device` | No hay dispositivo de entrada elegido. | — |
| :78 | `noGuitarInput` | `audio_no_guitar_input` | Falta asignar la entrada de guitarra. | — |
| :79 | `invalidChannels` | `audio_invalid_channels` | Canales no válidos: {s}. | s:string |
| :80 | `notConnected` | `audio_not_connected` | El dispositivo no está conectado. | — |
| :81-82 | `sampleRateMismatch` | `audio_rate_mismatch` | El dispositivo está a {device} kHz y la frecuencia de trabajo es {working} kHz | device,working: kHz (coma) |
| :83 | `notOpen` | `audio_not_open` | El dispositivo no está abierto. | — |
| :84 | `busy` | `audio_busy` | Hay una calibración o una grabación en marcha. | — |
| :85 | `notRecording` | `audio_not_recording` | No se está grabando. | — |
| :86 | `noPlayback` | `audio_no_playback` | El backing no estaba sonando por el dispositivo. | — |
| :87 | `unsupportedRate` | `audio_unsupported_rate` | Solo se graba a velocidad 100 %. | — |
| :88 | `interrupted(.disconnected)` | `audio_disconnected` | Se desconectó el dispositivo. | — |
| :89 | `interrupted(.sampleRateChanged)` | `audio_rate_changed` | El dispositivo cambió a {r} kHz. | r: kHz (coma) |
| :90 | `nothingRecorded` | `audio_nothing_recorded` | No se grabó nada. | — |
| :91 | `device` | `audio_device_error` | Error del dispositivo: {s}. | s:string (técnico) |
| :92 | `write` | `audio_write_failed` | No se pudo escribir la toma: {s}. | s:string |
| AppLogic.swift:38 | `RecordBlock.noInputDevice` | `record_block_no_input` | Elige un dispositivo de entrada en Ajustes · Audio. | — |
| :39 | `noGuitarInput` | `record_block_no_guitar` | Asigna la entrada de guitarra en Ajustes · Audio. | — |
| :40 | `invalidChannels` | `record_block_invalid_channels` | Los canales elegidos se repiten: revisa Ajustes · Audio. | — |
| :42 / :43 | `inputDisconnected` / `outputDisconnected` | `record_block_input_disconnected` / `_output_disconnected` | El dispositivo de entrada no está conectado. / El dispositivo de salida no está conectado. | — |
| :44-45 | `rateMismatch` | `record_block_rate_mismatch` | El dispositivo está a {device} y la frecuencia de trabajo es {working} (la unidad la pone `khzText`) | device,working: kHz (coma) |
| :46 | `sessionUnavailable` | `record_block_session_unavailable` | {s} (texto de `AudioSessionError`) | s:string |
| :47 | `speed` | `record_block_speed` | Solo se graba a velocidad 100 %: pon el tempo al 100 %. | — |
| :48 | `loop` | `record_block_loop` | Solo se graba sin bucle: quita el bucle. | — |
| :49 | `busy` | `record_block_busy` | Hay una calibración o una grabación en marcha. | — |
| WASAPIAudioIO.swift:345-347 | pista en `AudioIOError.device` (Windows) | `audio_wasapi_exclusive` / `_format_unsupported` / `_invalidated` | · el dispositivo está en uso en exclusivo por otra aplicación / · formato no admitido / · dispositivo invalidado (desconectado) | — (acompaña a `wasapi_open ({paso}): {hr hex}` en :338) |
| CoreAudioIO.swift:297 | `device` | `audio_aggregate_no_channels` | el agregado privado no publicó sus canales | — |
| AudioImporter.swift:229 | `AudioImportError.unreadable` detalle | `audio_import_conversion_failed` | conversión fallida | — (**sin confirmar**: `AudioImportError` no aparece en AppCore) |

## TabKit

Avisos del plan de importación de Songsterr: `SongsterrImportPlan.warnings` (SongsterrImportPlan.swift:226-269) → `TabSongsterr.swift:657` (`let warnings = plan.warnings`, mostrados en la hoja de importación).

| fichero:línea | caso | código | texto (es) | args |
|---|---|---|---|---|
| :231 | compases de más | `tab_warn_bars_extra` | Compás {bar} ({at}): la grabación tiene {n} compás/compases de más que la tablatura de Songsterr. | bar:int; at:«m:ss»; n:int (singular/plural: compás/compases) |
| :232 | compases de menos | `tab_warn_bars_missing` | Compás {bar} ({at}): a la grabación le faltan {n} compás/compases respecto a la tablatura de Songsterr. | ídem |
| :237 | pulsos de más | `tab_warn_beats_extra` | Compás {bar} ({at}): la grabación tiene {n} pulso/pulsos de más. | ídem (pulso/pulsos) |
| :238 | pulsos de menos | `tab_warn_beats_missing` | Compás {bar} ({at}): a la grabación le faltan {n} pulso/pulsos. | ídem |
| :259 | adornos | `tab_warn_ornaments` | {n} notas con adornos que la tablatura aún no representa se importaron sin ellos: {detalle}. | n:int; detalle: lista «{etiqueta} {k}» separada por «, » |
| :275-280 | etiquetas (`label`) | `tab_ornament_grace_note` / `_unknown_slide` / `_unknown_harmonic` / `_unknown_tremolo` / `_drum_technique` / `_other` | notas de adorno sin nota principal (se quitan) / slides de tipo desconocido / armónicos de tipo desconocido / trémolos de púa de figura desconocida / técnicas en golpes de batería / otros | k:int; en `unknownKey` se añade «({clave} {k}, …)» |
| :263 | percusión | `tab_warn_unknown_drums` | {n} golpes de percusión sin pieza equivalente se omitieron. | n:int |
| :268 | notas fuera | `tab_warn_dropped_notes` | {n} notas quedaron fuera del audio del tema y se quitaron. | n:int |
| Score/TabTrackNames.swift:9-12 | `defaultName(for:)` | `tab_track_guitar` / `_bass` / `_drums` / `_vocal` | Guitarra / Bajo / Batería / Voz | — (**sin confirmar** la ruta a la interfaz: `TabTrackNames` no aparece en AppCore; el nombre se persiste en la partitura) |

Nota: los avisos de compases mezclan plural en el texto; en inglés Dart necesita plural ICU (`bar`/`bars`, `beat`/`beats`). `SongsterrFormatError(reason:)` (SongsterrTrackConverter.swift:471) no llega (se resume en «Songsterr ha cambiado su formato»).

## StemKit, VideoKit, StudyKit (parcial)

| fichero | caso | código | texto (es) | args | llega por |
|---|---|---|---|---|---|
| (AppCore) `Services.swift:181-190` traduce `SeparationError` | `memoryLimitExceeded` | `stem_memory_limit` | La separación superó el límite de memoria ({gb} GB). | gb: decimal con `%g` (**ojo**: punto decimal, no coma) | `SeparationFailure.message` → `separationFailed` → job `error` (texto de AppCore, listar también en `mensajes-nucleo.md`) |
| ídem | `helperFailed` | `stem_helper_failed` | El helper de separación falló (código {code}). {tail} | code:int; tail:string | ídem |
| ídem | `invalidInput` | `stem_invalid_input` | Entrada no válida: {m} | m: detalles de StemKit (MaskModel.swift:50,53,70,134,152; AudioIO.swift:52,58): «se esperaba audio estéreo y tiene {n} canales», «el audio está vacío», «máscara con forma …» | ídem |
| VideoKit (MP4EditList.swift:112; MediaFoundation.swift:146,151,251; GuitarFramer+Onnx.swift:46; VideoTakeWriter.swift:85) | `Failure.malformed`, `MF.check(…,"abrir vídeo"/"leer vídeo"/"escribir vídeo")`, `GuitarFramerError.noVideo`, `cannotCreate` | `video_failure` (genérico) | «tamaño…», «abrir vídeo», «leer vídeo», «escribir vídeo», «sin vídeo», «no se puede añadir…» | detail:string | **sin confirmar**: `MontageController.swift:491,968` los envuelve en `.failed("\(error)")` / «No se pudo exportar el vídeo ({error}).» |
| StudyKit (ChordAudio.swift:11; MonoResampler.swift:59) | `ChordError.unreadableAudio("lista de stems vacía")`, `Failure(message: "remuestreo falló: …")` | `study_chord_unreadable` / `study_resample_failed` | lista de stems vacía / remuestreo falló: {detail} | detail:string | **sin confirmar** |

Pendiente (no hecho por tope de contexto): enumerar los 8 `invalidInput` de StemKit y las ~10 cadenas de VideoKit con su línea exacta; revisar sin acento AnalysisKit, HeadRushKit, MatchKit, Tone3000Kit.

## Textos que NO llegan a la interfaz

| Paquete | Recuento |
|---|---|
| Store | 2 comentarios con acento; 0 literales solo-log |
| SourceKit | 11 detalles de `SongsterrError.unknownFormat` (SongsterrReader.swift:32,51,60,65,91,98,119,121,127; SongsterrClient.swift:51,83), reducidos a mensaje fijo en SongsterrLookup.swift:31 |
| ModelKit | 10: 5 `displayName` de otros modelos y 5 `license` (ModelDescriptor.swift:125-228) |
| NativeKit | 2: ProviderChoice.swift:265 (solo `engineSummary` de StemKit, diagnóstico) y precondición NativeResample.swift:73 |
| AudioKit | ~52 en `tf-audio` (CLI) + precondiciones; sin recuento exacto |
| TabKit | 1 (SongsterrTrackConverter.swift:471) |
| StemKit | ≥12 (`fatalError`/`precondition` en SpectralTransform.swift:52,166; `engineSummary`) |
| VideoKit | ~50 en `tf-video` (CLI) + precondiciones (MediaFoundation.swift:248, FramePixelBuffer.swift:31) y «Cámara simulada» (CameraDevice.swift:69, **sin confirmar**) |
| StudyKit | 0 confirmados |
