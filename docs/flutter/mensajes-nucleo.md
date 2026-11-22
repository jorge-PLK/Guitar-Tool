# Mensajes del núcleo (parte 1: `Packages/AppCore`)

BORRADOR PARCIAL (se reescribe completo al terminar). Ficheros hechos aquí: Router, Bridge, ImportMethods, JobQueue, LibraryMethods, SettingsMethods, LinkMethods, LinkImportSession, AudioMethods, AudioController, StudyEdits, RecordMethods. El inventario continúa en `mensajes-nucleo-3.md` y en `mensajes-nucleo-paquetes.md` y `mensajes-nucleo-paquetes-2.md` (paquetes). Pendiente de unificar: recuentos globales al principio y textos repetidos al final.

## Hoy

`RPCError` (`Router.swift:4-11`) solo tiene `code: String` y `message: String`; viaja como `{"error":{"code","message"}}` (`Router.swift:96-104`). No hay `args`. Los fallos de trabajos viajan como `JobInfo.error: String` (texto suelto, sin código) y `LinkFinished.error: {code,message}` (`LinkMethods.swift:97`). Los textos de los kits (SourceKit, RecordKit, LibraryKit...) entran en `message` vía `describe(e)` / `localizedDescription` / `String(describing:)`: no están en AppCore y van aparte (parte 2).

Notación de las tablas: `#` = número formateado con coma decimal; `[u]` = unidad pegada al texto; `(kit)` = el texto o parte viene de otro paquete.

## Códigos `code:` ya existentes (literales en AppCore)

bad-params (80), internal (24), not-found (21), not-open (19), not-ready (11), unsupported (6), busy (6), load-failed (4), audio-unavailable (3), save-failed (2), no-projects-folder (2), no-offset (2), cannot-split (2), cancelled (2), analysis-unavailable (2), work-in-progress, unsafe-deletion, unknown-method, trash-failed, spotify-offline, section-not-created, record-blocked, not-separated, no-video, no-playlist, no-frame, no-analysis, in-library, empty-title, delete-failed, bad-request, bad-json.
Códigos no literales: `SourceMessages.code(for:)` (`LinkImportSession.swift:206-228`): offline, unsupported-link, spotify-unreadable, age-restricted, region, private-video, removed, no-audio-format, extractor-broken, ffmpeg-failed, helper-missing, launch-failed, http-status, timed-out, cancelled, checksum-mismatch, update-failed, rate-limited, no-audio-produced. `LinkMethods.swift:198-204`: spotify-missing-credentials, spotify-rejected, spotify-rate-limited, spotify-offline, spotify-bad-response.

## Router.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 47 | bad-params | core_bad_params | Parámetros no válidos para \(method): \(error) | method:String, error:String (técnico) | error de cualquier método |
| 64 | bad-json | core_bad_json | El mensaje no es un objeto JSON. | - | respuesta con id null |
| 68 | bad-request | core_bad_request | Falta «id» entero o «method». | - | error |
| 72 | unknown-method | core_unknown_method | Método desconocido: \(method) | method:String | error |
| 77 | bad-params | core_bad_params_json | «params» no es JSON válido. | - | error |
| 85 | internal | core_internal | \(error) | error:String (técnico, sin texto propio) | error |

## Bridge.swift

| línea | code | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 167, 178 | bad-params | core_id_not_uuid | «id» no es un UUID. | - | error (library/projects open-folder y afines) |
| 171 | not-found | library_folder_missing | La carpeta del tema no existe. | - | error |
| 184 | bad-params | core_ids_not_uuid | «\(first)» y «\(second)» deben ser UUID. | first:String, second:String (nombres de parámetro; aquí `id`, `takeId`) | error |
| 200 | internal | core_open_folder_failed | No se pudo abrir la carpeta: \(error) | error:String | error |
| 208 | no-projects-folder | library_no_projects_folder | No hay carpeta de proyectos configurada. | - | error |
| 212 | no-projects-folder | library_projects_folder_missing | La carpeta de proyectos no existe: \(root.path) | path:String | error |

## ImportMethods.swift

| línea | code | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 170 | bad-params | core_id_not_uuid | «id» no es un UUID. | - | error |
| 228 | bad-params | import_songsterr_url_invalid | «url» debe ser una página https de songsterr.com. | - | error de la vista previa |
| 231 | bad-params | import_preview_rect_invalid | El rectángulo de la vista previa no es válido. | - | error |
| 236 | unsupported | host_no_preview | El anfitrión no tiene vista previa. | - | error |
| 253 | bad-params | library_move_mode_invalid | «mode» debe ser «move» o «point». | - | error (cambio de carpeta) |
| 255 | bad-params | library_path_empty | «path» está vacío. | - | error |
| 312 | unsupported | host_no_dialogs | El anfitrión no ofrece diálogos nativos. | - | error |
| 323 | internal | library_save_folder_failed | No se pudo guardar la carpeta de proyectos: \(error) | error:String | error |

## JobQueue.swift

| línea | code | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 133 | sin código | job_text_import | Importando… \(n) % | n:Int (fracción×100, redondeo) | `JobInfo.text` en evento `jobs.changed`/lista |
| 135 | sin código | job_text_queued | En cola | - | `JobInfo.text` (stage separation) |
| 136 | sin código | job_text_separating | Separando… \(n) % | n:Int | `JobInfo.text` |
| 137 | sin código | job_text_guitars | Separando guitarras | - | `JobInfo.text` |
| 138 | sin código | job_text_analysis_queued | En cola para análisis | - | `JobInfo.text` |
| 139 | sin código | job_text_analyzing | Analizando… | - | `JobInfo.text` |
| 264 | unsupported | import_format_unsupported | Formato no admitido (wav, flac o mp3): \(name) | name:String (nombre de fichero) | error de import.file; si falla dentro del trabajo: `JobInfo.error` (:285) |
| 267 | not-found | import_file_missing | No existe el fichero: \(path) | path:String | error |
| 318 | not-found | take_not_found | No hay ninguna toma con id \(uuid). | id:String | error |
| 334 | busy | project_busy | El tema está ocupado (separando o migrando). | - | error |
| 356 | delete-failed | library_delete_failed | No se pudo eliminar del disco: \(describe(e)) | detail:String (kit) | error |
| 358-359 | trash-failed | library_trash_failed | No se pudo mover a la Papelera: \(describe(e)) No se ha borrado nada; te queda «Eliminar del disco». | detail:String (kit) | error |
| 369 | cancelled | job_cancelled | Cancelado. | - | error / `LinkFinished.error` |
| 373 | not-found | library_project_not_found | No hay ningún tema con id \(uuid). | id:String | error |
| 374 | empty-title | library_title_empty | El título no puede quedar vacío. | - | error (rename) |
| 376 | unsafe-deletion | library_unsafe_deletion | No se borra: no es un tema de la biblioteca (\(path)). | path:String | error |
| 378-379 | work-in-progress | library_work_in_progress | Hay trabajo en curso. Espera a que terminen las separaciones y vuelve a cambiar la carpeta. | - | error |
| 380, 383 | internal | core_internal | String(describing: LibraryError) / describe(e) | detail:String (kit) | error |
| 397 | busy | library_folder_change_busy | Ya se está cambiando la carpeta. | - | error |
| 221-248 | sin código | job_error_kit | `JobInfo.error` = mensaje del kit (`separationFailed`, `analysisFailed`, `guitarSplitFailed`) | detail:String (kit) | `JobInfo.error` en `jobs.*` |

Los textos de `JobInfo.text` van en español hoy y sin código: Dart puede derivarlos de `stage`+`state`+`fraction` (ya viajan) en vez de recibir texto; propuesta: eliminar `text` y traducir en Dart (decisión de Jorge). `JobInfo.error` sí necesita `{code,message,args}`.

## LibraryMethods.swift

| línea | code | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 178, 191, 226 | not-found | library_project_not_found | No hay ningún tema con id \(uuid). | id:String | error (library.detail y similares) |
| 232 | not-found | library_take_no_audio | La toma no existe o no tiene audio procesado. | - | error |

## SettingsMethods.swift

| línea | code | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 119-125 | sin código | (formato, no traducible) | 720p / 1080p / 4K / \(w)×\(h) | w,h:Int | `label` en `resolutions[]` y fila de cámara |
| 128-132 | sin código | settings_fps_label | \(fps) fps (hasta 2 decimales, punto decimal: String(format:"%.2f")) | fps:Double (punto, no coma) | `label` en lista de fps; `fpsLabel` (:448, :459) |
| 310 | internal | settings_profile_read_failed | No se pudo leer el perfil: \(error) | error:String | error |
| 331 | bad-params | core_id_not_uuid | «id» no es un UUID. | - | error |
| 373 | not-found | settings_model_not_found | No hay ningún modelo con id \(id). | id:String | error |
| 402 | busy | settings_model_downloading | El modelo se está descargando. | - | error |
| 403, 404 | internal | settings_model_delete_failed | No se pudo borrar el modelo: \(detail) | detail:String (kit) | error |
| 478 | bad-params | settings_resolution_invalid | «resolution» no es válida. | - | error |
| 480 | bad-params | settings_fps_invalid | «fps» no es válido. | - | error |
| 483 | bad-params | settings_codec_invalid | «export.codec» es hevc o h264. | - | error |
| 487 | bad-params | settings_export_resolution_invalid | «export.resolution» no es válida. | - | error |
| 494 | bad-params | settings_camera_required | No hay ninguna cámara a la que aplicarlo: indica «cameraId». | - | error |
| 505 | bad-params | settings_offset_invalid | «offset.ms» no es válido. | - | error |
| 518 | internal | settings_profile_save_failed | No se pudo guardar el perfil: \(error) | error:String | error |

## LinkMethods.swift

| línea | code | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 178, 216 | bad-params | link_url_empty | «url» está vacía. | - | error (link.resolve, link.classify...) |
| 194 | bad-params | link_query_empty | «query» está vacía. | - | error (link.search) |
| 205 | spotify-* | link_spotify_error (5 códigos ya existentes) | `SpotifySearchError.localizedDescription` | detail (kit) | error |
| 207 | cancelled | job_cancelled | Cancelado | - | error |
| 209 | spotify-offline | link_spotify_offline | Sin conexión con Spotify | - | error |
| 280-281 | not-found | link_candidate_stale | Ese candidato no está en la última resolución; vuelve a resolver el enlace. | - | error (link.start) |
| 286-287 | bad-params | link_spotify_needs_candidate | Con «url» solo se admite un vídeo de YouTube; para Spotify hace falta «candidateId». | - | error |
| 291 | bad-params | link_candidate_or_url_required | Hace falta «candidateId» o «url». | - | error |
| 298 | sin código | job_text_queued | En cola | - | `JobInfo.text` (stage download) |
| 342 | sin código | job_text_downloading | Descargando audio… | - | `JobInfo.text` |
| 364 | sin código | job_text_converting | Convirtiendo a WAV… | - | `JobInfo.text` |
| 366 | sin código | job_text_downloading_pct | Descargando audio… \(n) % | n:Int | `JobInfo.text` |
| 373 | sin código | link_notice (kit) | `source.notices[].message` | texto (kit) | `LinkFinished.notices: [String]` (sin código) |
| 395-401 | ver LinkImportSession | | `rpc.code`/`rpc.message`; el trabajo guarda solo el detalle (2.ª línea) en `JobInfo.error` | | `LinkFinished.error`, `JobInfo.error` |
| 452 | internal | link_ytdlp_revert_failed | No se pudo volver a la embebida: \(detail) | detail:String (kit) | error (tools.revertYtDlp) |

## LinkImportSession.swift (`SourceMessages.text(for:)`, líneas 170-203)

El `message` viaja como `"<título>\n<detalle>"` (`rpc`, :237); sin detalle, solo el título. El código ya es el de `code(for:)`.

| línea | code actual (= propuesto con prefijo `link_` si no lo tiene) | título | detalle | args |
|---|---|---|---|---|
| 172 | offline | Sin conexión | No se ha podido conectar. Comprueba la red y reintenta. | - |
| 173 | unsupported-link | Enlace no admitido | `supportedLinks` (:168): Se admiten enlaces de un vídeo de YouTube (youtube.com/watch, youtu.be, music.youtube.com) y de una canción de Spotify (open.spotify.com/track o spotify:track), además de listas de YouTube (youtube.com/playlist) y listas o álbumes de Spotify (open.spotify.com/playlist, open.spotify.com/album). Episodios no. | - |
| 175-176 | spotify-unreadable | No se han podido leer los datos de Spotify | Pega un enlace de YouTube del tema en su lugar. | - |
| 178-179 | age-restricted | Vídeo con restricción de edad | Vídeo con restricción de edad: no se puede descargar sin cuenta. | - |
| 180 | region | No disponible en tu región | Este vídeo no está disponible en tu país. | - |
| 181 | private-video | Vídeo privado | Este vídeo es privado. | - |
| 182 | removed | Vídeo no disponible | Este vídeo se ha retirado o ya no está disponible. | - |
| 183 | no-audio-format | Sin audio descargable | Este vídeo no ofrece audio descargable. | - |
| 185-186 | extractor-broken | yt-dlp puede estar desactualizado[ (versión \(v))] | texto de yt-dlp (kit) o «YouTube ha cambiado algo y yt-dlp no sabe leerlo.» | v:String? , d:String (kit) |
| 187 | ffmpeg-failed | Falló la conversión | últimas 4 líneas de ffmpeg (kit) | m:String |
| 189 | helper-missing | Falta un componente | No se encuentra «\(n)» dentro de la app. Reinstala ToneForge. | n:String |
| 190 | launch-failed | No se pudo lanzar el proceso | últimas 4 líneas (kit) | m:String |
| 191 | http-status | Respuesta inesperada | El servidor respondió con el código \(c). | c:Int |
| 192 | timed-out | Tiempo agotado | El servidor tarda demasiado en responder. Reintenta. | - |
| 193 | cancelled | Cancelado | (vacío) | - |
| 195 | checksum-mismatch | Actualización rechazada | La suma SHA-256 del yt-dlp descargado no coincide. No se ha instalado nada. | - |
| 196 | update-failed | No se pudo actualizar yt-dlp | últimas 4 líneas (kit) | m:String |
| 198-199 | rate-limited | YouTube ha limitado las peticiones | YouTube ha limitado las peticiones; espera unos minutos y reintenta. | - |
| 200 | no-audio-produced | Sin audio | yt-dlp terminó pero no dejó ningún fichero de audio. | - |

Nota: título y detalle van fundidos en un `message`; con `{code,message,args}` conviene un código por error (ya lo hay) y los args solo `v`,`n`,`c`,`d`,`m`.

## AudioMethods.swift

| línea | code | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 178 | sin código | audio_calibrate_step_cable | Conecta con un cable una salida del dispositivo a su entrada de guitarra. | - | `AudioSettingsResult.calibrateInstructions[0]` |
| 179 | sin código | audio_calibrate_step_rig | Con una pedalera, carga un rig vacío y baja el volumen de salida: el bucle realimenta (entrada, rig, salida, cable, entrada). | - | `calibrateInstructions[1]` |
| 180 | sin código | audio_calibrate_step_test | La prueba son 10 pitidos agudos en unos 5 segundos. Mide el retardo de ida y vuelta, que es el desfase que tendrá una toma respecto al backing que se oye. | - | `calibrateInstructions[2]` |
| 300 | bad-params | audio_sample_rate_invalid | «workingSampleRate» debe ser 44100 o 48000. | - | error (audio.setSettings) |
| 303 | bad-params | audio_backing_out_invalid | «backingOut» numera los canales desde 1. | - | error |
| 315 | internal | audio_profile_save_failed | No se pudo guardar el perfil: \(error) | error:String | error |
| 323 | sin código | audio_device_label | \(name) · \(n) can. | name:String, n:Int | `AudioDeviceItem.label` |
| 333-334 | sin código | audio_device_chosen_default / audio_device_disconnected | Dispositivo elegido / \(name) · desconectado | name:String | `AudioDeviceItem.name`, `.label` |
| 367 | sin código | audio_calibrated_label | Calibrada · \(ms) ms · \(fecha) | ms:Double #(2 dec) , fecha:String (`d MMM yyyy`, locale es, p. ej. «3 nov 2026») | `AudioCalibrationInfo.label` |
| 370 | sin código | audio_not_calibrated | Sin calibrar | - | `AudioCalibrationInfo.label` |
| 376 | sin código | audio_rate_mismatch | El dispositivo está a \(a) y la frecuencia de trabajo es \(b) | a,b:String (rateText: «44,1 kHz» #, «48 kHz», «N Hz») | `AudioRateMismatch.message` |
| 377 | sin código | audio_rate_mismatch_hint | Grabar y calibrar quedan bloqueados; el backing suena igual. | - | `AudioRateMismatch.hint` |
| 379 | sin código | audio_rate_use_device | Usar \(a) como frecuencia de trabajo | a:String (rateText #) | `AudioRateMismatch.useLabel` |
| 385 | sin código | (formato) | rateText: «44,1 kHz» / «48 kHz» / «\(n) Hz» | hz:Double # | `AudioRateOption.label`, en varios textos |
| 409-410 | sin código | audio_calib_no_signal | No llegó la señal de prueba / Comprueba el cable de una salida del dispositivo a la entrada de guitarra, y que la entrada elegida sea esa. Después repite. | - | `AudioCalibrationFailure.title`, `.hint` (evento `audio.calibration`) |
| 412-413 | sin código | audio_calib_saturated | La señal llegó saturada / Baja el volumen de salida del dispositivo (con una pedalera, el del rig o el de la salida) y repite. | - | idem |
| 415-416 | sin código | audio_calib_unstable | Las medidas no coinciden entre sí (dispersión de \(x) ms) / Carga un rig vacío o sin delay ni reverb, cierra otras apps de audio y repite. | x:Double # (2 dec) ms | idem |
| 434 | sin código | audio_calib_row_latency | Latencia · \(ms) ms · \(n) muestras | ms:Double #(2), n:Double #(1) | `AudioCalibrationRow.label/.value` |
| 434 | sin código | audio_calib_row_spread | Dispersión · \(ms) ms · \(n) muestras | ms #(3), n #(1) | idem |
| 436 | sin código | audio_calib_row_rig_delay | Retardo del rig · \(ms) ms · se corregirá en cada toma | ms #(2) | idem |
| 438-439 | sin código | audio_calib_row_rig_none | Retardo del rig · sin canal de referencia: la latencia calibrada vale tal cual | - | idem |
| 442 | sin código | audio_calib_row_corrected | Tomas corregidas · \(n) de este tema, hechas sin calibrar | n:Int | idem |

`AudioCalibrationRow` manda etiqueta y valor ya con texto y números en coma decimal: con códigos, Dart debería recibir números crudos (`latencyMS`, `spreadMS`... ya van en `success`) y formatear él; las filas `rows` sobrarían (decisión de Jorge).

## AudioController.swift

| línea | code | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 155 | sin código | audio_channels_stereo | Salidas \(l) y \(r) · estéreo | l,r:Int | `AudioBackingChoice.label` |
| 163 | sin código | audio_channels_none | Sin asignar | - | `AudioGuitarChoice.label` |
| 164 | sin código | audio_channel_one / audio_channels_two | Entrada \(n) / Entradas \(a) y \(b) | n,a,b:Int | `AudioGuitarChoice.label` |
| 368, 379 | sin código | audio_device_not_open | El dispositivo no está abierto. (o `interruptionNote`) | - | `calibrateBlock`, `recordingBlock` (AudioStateResult.calibrateBlock) |
| 380 | sin código | audio_backing_not_hosted | El backing no está sonando por el dispositivo. (o `hostError`) | - | idem |
| 431 | sin código | audio_session_error | errorDescription de AudioSessionError (kit) o `\(error)` | detail:String (kit) | `AudioStateResult.sessionError` |
| 468 | sin código | audio_host_rate_mismatch | Este tema no está a la frecuencia de trabajo (\(rate)): no se puede grabar. | rate:String (rateText #) | `AudioStateResult.hostError` |
| 471 | sin código | audio_host_no_stems | Este tema no tiene stems para sonar de fondo: no se puede grabar. | - | `hostError` |
| 473 | sin código | audio_host_device_failed | No se pudo usar el dispositivo para el backing (\(error)). | error:String | `hostError` |
| 498, 704 | sin código | audio_take_save_failed | No se pudo guardar la toma: \(detail) | detail:String (kit) | `recordingNotices[]` |
| 503 | sin código | audio_take_interrupted | \(motivo) a mitad de la toma: se guardó lo grabado. (motivo kit; por defecto «Se cortó el dispositivo») | reason:String (kit) | `recordingNotices[]`; filtra por prefijo «La toma se detuvo» (:502) |
| 592 | sin código | (kit) | `RecordBlock.message` | - | `AudioCalibrationState.error` |
| 613 | sin código | audio_calibration_failed | errorDescription (kit) o `\(error)` | detail:String | `AudioCalibrationState.error` |
| 633 | sin código | audio_no_settings | No hay configuración de audio. | - | `AudioCalibrationState.error` |
| 638 | sin código | audio_calibration_save_failed | No se pudo guardar la calibración: \(error) | error:String | `AudioCalibrationState.error` |
| 687 | sin código | audio_record_start_failed | No se pudo empezar a grabar: \(detail) | detail:String (kit) | `recordingNotices[]` |
| 725 | sin código | audio_take_stopped | La toma se detuvo y se guardó lo grabado. | - | `recordingNotices[]` |
| 728 | sin código | audio_rig_delay_unreliable | No se pudo medir con fiabilidad el retardo del rig en esta toma (mucho delay o reverb): se usó el último valor bueno. | - | `recordingNotices[]` |
| 731 | sin código | audio_take_nowhere_to_save | No hay dónde guardar la toma. | - | `recordingNotices[]` |
| 751, 753 | sin código | audio_simulated_input / output | Entrada simulada / Salida simulada | - | `AudioDeviceItem.name` (solo `--audio simulated`; de pruebas) |

## StudyEdits.swift

Vía: error del método `study.*`/`backing.*` indicado (edición de secciones, acordes, tonalidad, guitarras, análisis).

| línea | code | propuesto | texto | args |
|---|---|---|---|---|
| 129 | bad-params | study_range_invalid | «start» y «end» deben ser tiempos con end >= start. | - |
| 161 | save-failed | study_guitar_options_error | `s.guitarOptionsError` (texto del kit) | detail |
| 170 | bad-params | study_guitar_role_invalid | «role» no es una guitarra (rhythm, left, right, lead): \(role) | role:String |
| 180-183 | save-failed | study_guitar_options_save_failed | No se pudieron guardar las opciones: \(error) | error:String |
| 195, 203, 308, 319, 460, 485 | not-open | study_not_open | No hay ningún tema abierto en Backing. | - |
| 207, 327 | not-open | study_closed | El tema se cerró. | - |
| 268 | bad-params | core_id_not_uuid | «id» no es un UUID. | - |
| 270 | not-found | study_section_not_found | No hay ninguna sección con id \(id). | id:String |
| 321 | analysis-unavailable | study_no_analysis_queue | No hay cola de análisis. | - |
| 323 | not-separated | study_not_separated | El tema no tiene la separación terminada: no se puede analizar. | - |
| 338-339 | analysis-unavailable | study_analysis_unavailable | No se puede analizar ahora: no hay analizador o el tema aún está en la cola de separación. | - |
| 408 | bad-params | study_key_invalid | «key» no es una tonalidad mayor o menor («C:maj», «A:min»): \(text) | text:String |
| 411 | no-analysis | study_no_analysis_key | Aún no hay análisis: la tonalidad no se puede corregir. | - |
| 420 | bad-params | study_range_invalid_strict | «start» y «end» deben ser tiempos con 0 <= start < end. | - |
| 426 | bad-params | study_chord_index_invalid | «index» fuera de 0...169: \(i) | i:Int |
| 431 | bad-params | study_chord_label_invalid | «label» no se reconoce como acorde («C:min», «F#:7», «N»): \(l) | l:String |
| 435 | bad-params | study_chord_index_or_label | Indica «index» o «label» (solo uno). | - |
| 443 | bad-params | study_at_invalid | «at» no es un tiempo. | - |
| 446 | cannot-split | study_no_chord_at | No hay ningún acorde en ese instante. | - |
| 450 | cannot-split | study_beat_outside_chord | El pulso más cercano cae fuera del acorde (a menos de 50 ms de un extremo). | - (50 ms fijo en el texto) |
| 466 | bad-params | study_section_range_invalid | «start» y «end» deben ser tiempos con 0 <= start < end <= duración. | - |
| 473 | bad-params | study_snap_invalid | «snap» debe ser none, beat o bar. | - |
| 476-477 | section-not-created | study_section_not_created | No se crea: empieza dentro de otra sección o queda más corta de \(minLength) s. | minLength:Double (unidad s; hoy interpola un Double con punto decimal, no coma) |
| 488 | bad-params | study_to_invalid | «to» debe ser un tiempo. | - |
| 498 | bad-params | study_times_invalid | «start» y «end» deben ser tiempos. | - |
| 501 | bad-params | study_color_invalid | «color» fuera de la paleta (0...\(n-1)). | n:Int |
| 505 | bad-params | study_snap_invalid_chord | «snap» debe ser none, beat, bar o chord. | - |

## RecordMethods.swift

Vía: error del método `record.*` indicado.

| línea | code | propuesto | texto | args |
|---|---|---|---|---|
| 267 | record-blocked | record_blocked | `c.blockReason` (texto de RecordKit/gate) | reason:String (kit) |
| 268 | busy | record_take_in_progress | Ya hay una toma en curso. | - |
| 277 | not-found | record_part_not_found | No hay ninguna parte con id \(id). | id:String |
| 286 | bad-params | record_replaces_invalid | «replaces» no es un papel de guitarra: \(r) | r:String |
| 289 | busy | record_busy_adding_part | No se puede añadir una parte grabando. | - |
| 297 | not-found | study_section_not_found | No hay ninguna sección con id \(s). | s:String |
| 307 | bad-params | record_bars_invalid | «bars» va de 0 a 2. | - |
| 345 | busy | record_busy_adjusting_offset | No se puede ajustar el desfase grabando. | - |
| 347 | no-video | record_take_no_video | Esa toma no tiene vídeo. | - |
| 352 | no-offset | record_no_offset_sheet | No hay ninguna hoja de desfase abierta. | - |
| 374 | internal | record_delete_take_failed | Ver `mensajes-nucleo-3.md` (`RecordController`, mismo código) | message:String |
| 389 | not-open | record_not_open | La pantalla Grabar no está abierta. | - |
| 397 | bad-params | core_take_id_not_uuid | «takeId» no es un UUID. | - |
| 398 | not-found | take_not_found | No hay ninguna toma con id \(s). | s:String |
| 404, 425 | bad-params | record_channel_invalid | «channel» no es un canal de Grabar: \(channel) | channel:String |
| 433 | not-open | study_not_open | No hay ningún tema abierto en Backing. | - |
| 436 | bad-params | record_project_mismatch | «projectId» no es el del tema abierto. | - |
| 439 | internal | record_no_audio_service | No hay servicio de audio. | - |
| 453 | internal | record_no_library | No hay biblioteca. | - |
| 624 | sin código | record_camera_message | `c.cameraMessage` (estado de cámara; texto del controlador, sin volcar) | - |

(`RecordMethods.swift:110`: campo `String?` de un DTO, texto por revisar en `RecordController`.)
