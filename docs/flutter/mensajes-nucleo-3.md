# Mensajes del núcleo (parte 3: Tab y Montaje)

BORRADOR PARCIAL. Hechos: TabService, MontageMethods, TabSongsterr, TakeViewMethods, TabMethods, MontageController, RecordController. Pendientes: ver `Temp/flutter/state-mensajes-3.md`.
Notación como en `mensajes-nucleo.md`. Ruta: `Packages/AppCore/Sources/AppCore/`. `(kit)` = texto de otro paquete vía `BackingController.describe(e)` (`StudyBacking.swift:87`: `errorDescription ?? "\(error)"`).

## TabService.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 157 | bad-params | core_project_id_not_uuid | «projectId» no es un UUID. | - | error de tab.open |
| 161 | not-open | tab_cannot_open_song | No se pudo abrir el tema. | - | error de tab.open |
| 224 | not-open | tab_not_open | No hay ninguna tablatura abierta. | - | error de métodos tab.* |
| 280 | sin código | tab_notice_redone | Se han rehecho: \(redone). Su audio cambió, así que se perdieron las ediciones de esas pistas. | redone:String (nombres de pista unidos con «, »; son nombres, no traducibles) | `tab.state.notices[]` |
| 289 | sin código | (kit) tab_phase_failed | \(describe(error)) | error:String (kit) | `tab.state.error` (phase "failed") |
| 323 | bad-params | tab_bad_source | «source» debe ser «automatic» o «songsterr». | - | error de tab.setSource |
| 325 | unsupported | tab_no_library | No hay biblioteca donde guardar la fuente. | - | error |
| 327 | internal | tab_source_save_failed | No se pudo guardar la fuente: \(error) | error:String (técnico) | error |
| 347 | not-ready | tab_no_score | Aún no hay partitura. | - | error |
| 350, 358, 656, 1097, 1105 | bad-params | tab_unknown_track | Pista desconocida: \(track). | track:String (id) | error de métodos con «track» |
| 400 | not-ready | tab_not_ready_transcribe | La tablatura no está lista para transcribir. | - | error de tab.transcribe |
| 403 | bad-params | tab_track_not_transcribable | La pista «\(track)» no se puede transcribir. | track:String (id) | error |
| 430-434 | sin código | (kit) tab_transcribe_failed | \(describe(error)) | error:String (kit) | `tab.progress.error` (state "failed") y `tab.state.tracks[].error` |
| 445-447 | sin código | tab_notice_transcription | Transcripción: \(parts unidos con « y »). Partes: «\(shifted) notas fuera del registro de la afinación se subieron o bajaron una octava» y «\(dropped) se quitaron por no caber en las cuerdas» | shifted:Int, dropped:Int (cada parte solo si >0; pasar como args numéricos y componer en Dart) | `tab.state.notices[]` |
| 623 | bad-params | tab_unknown_span_action | Acción de tramo desconocida: \(action). | action:String | error de tab.span |
| 660 | bad-params | tab_position_not_in_score | Esa posición no está en la partitura. | - | error |
| 42 (577, 612) | sin código | tab_span_loop_name | Selección | - | nombre del bucle A-B en `audio.state.loopName` (decisión de Jorge: valor sentinel comparado en 186/604; no traducir por texto, usar código) |
| 686 | sin código | tab_selection_place | Compás \(bar), pulso \(beat) | bar:Int, beat:Int | `tab.state.selection.summary` |
| 689 | sin código | tab_selection_no_hits | \(place) · sin golpes | place | `selection.summary` |
| 689, 700 | sin código | tab_drum_kick / snare / hihat / openhihat / tom / crash | bombo / caja / charles / charles abierto / tom / platos | - | `selection.summary` (lista unida con «, ») |
| 691 | sin código | tab_selection_string_fret | \(place) · cuerda \(string), traste \(fret) | string:Int, fret:Int | `selection.summary` |
| 692 | sin código | tab_selection_string_no_note | \(place) · cuerda \(string), sin nota | string:Int | `selection.summary` |
| 737 | sin código | tab_edit_nothing_selected | No hay nada seleccionado. | - | `tab.state.flash` |
| 738 | sin código | tab_edit_wrong_track_kind | Esa edición no vale para esta pista. | - | `flash` |
| 739 | sin código | tab_edit_no_string | No hay otra cuerda en esa dirección. | - | `flash` |
| 740 | sin código | tab_edit_fret_range | El traste saldría de 0–24. | - | `flash` |
| 741 | sin código | tab_edit_string_occupied | Ya hay una nota en esa cuerda en ese punto. | - | `flash` |
| 742 | sin código | tab_edit_invalid_position | Esa posición no está en la rejilla de la pista. | - | `flash` |
| 743 | sin código | tab_edit_invalid_duration | Esa duración no cabe. | - | `flash` |
| 744 | sin código | tab_edit_no_tie_origin | No hay una nota anterior igual en esa cuerda a la que ligarla. | - | `flash` |
| 835 | sin código | tab_flash_no_hits | No hay golpes seleccionados. | - | `flash` |
| 839 | sin código | tab_flash_no_notes | No hay ninguna nota seleccionada. | - | `flash` |
| 892 | sin código | tab_flash_tuning_report | \(shifted) notas se movieron una octava y \(dropped) se quitaron por no caber en la afinación. | shifted:Int, dropped:Int | `flash` |
| 899 | sin código | tab_tuning_standard | Estándar | - | `tab.state.tuning.name` |
| 900 | sin código | tab_tuning_half_down | Medio tono abajo | - | `tuning.name` |
| 901 | sin código | tab_tuning_whole_down | Un tono abajo | - | `tuning.name` |
| 902 | sin código | tab_tuning_drop_d | Drop D | - (nombre propio) | `tuning.name` |
| 903 | sin código | tab_tuning_custom | Personalizada | - | `tuning.name` |
| 981 | not-ready | tab_not_ready | La tablatura no está lista. | - | error de tab.edit |
| 985 | bad-params | tab_value_not_digit | «value» debe ser un dígito. | - | error |
| 992 | bad-params | tab_unknown_drum_piece | Pieza de batería desconocida: \(piece). | piece:String | error |
| 997 | bad-params | tab_unknown_ornament | Adorno desconocido: \(name). | name:String | error |
| 1005 | bad-params | tab_missing_track_preset | Faltan «track» y «preset» válidos. | - | error |
| 1014 | bad-params | tab_unknown_edit_op | Operación de edición desconocida: \(op). | op:String | error |
| 1044 | sin código | tab_flash_save_failed | No se pudo guardar la tablatura: \(error) | error:String (localizedDescription) | `flash` |
| 1180 | sin código | tab_flash_synth_failed | No se pudo sintetizar la pista: \(error) | error:String (localizedDescription) | `flash`; además `tab.state.tracks[].synth` = "failed" (1178 guarda el texto en SynthState.failed, sin salir) |
| 1218 | not-ready | tab_no_score_to_export | Aún no hay partitura que exportar. | - | error de tab.export |
| 1220 | bad-params | tab_bad_base64 | «data» no es base64 válido. | - | error |
| 1229 | internal | tab_export_save_failed | No se pudo guardar \(file): \(error) | file:String (nombre), error:String | error |

## MontageMethods.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 371 | bad-params | montage_bad_layout | «layout» no es un layout de montaje: \(layout) | layout:String | error de montage.setLayout |
| 412 | bad-params | montage_bad_codec | «codec» no es hevc ni h264: \(codec) | codec:String | error de montage.setExport |
| 416 | bad-params | montage_bad_container | «container» no es mov ni mp4: \(container) | container:String | error |
| 419 | bad-params | montage_bad_resolution | «resolution» no es válida. | - | error |
| 420, 470 | bad-params | montage_bad_fps | «fps» no es válido. | - | error |
| 435 | bad-params | montage_bad_framing_mode | «mode» no es fixed ni follow: \(mode) | mode:String | error |
| 466 | bad-params | montage_bad_seconds | «seconds» no es válido. | - | error |
| 476 | not-ready | montage_no_video_takes | No hay tomas con vídeo que montar. | - | error de montage.export |
| 477 | not-ready | montage_export_running | Ya hay una exportación en curso. | - | error |
| 477 | not-ready | montage_framing_pending | El análisis de encuadre aún no ha terminado. | - | error |
| 489 | not-open | montage_not_open | No hay ningún tema abierto en Montaje. | - | error de cualquier montage.* |
| 381, 401, 492 | bad-params | core_param_not_uuid | «\(name)» no es un UUID. | name:String (nombre de parámetro: id, to, partId) | error |
| 536 | bad-params | core_project_id_not_uuid | «projectId» no es un UUID. (repetido de TabService:157) | - | error de montage.open |
| 540 | internal | montage_project_read_failed | No se pudo leer project.json: \(error) | error:String (técnico) | error |
| 647 | sin código | (controller) montage_export_failed | \(m) (texto de MontageController, ver su tabla) | m:String | `montage.export` evento, campo `message` (phase "failed") |
| 646 | sin código | (controller) montage_export_stage | \(stage) (texto de MontageController) | stage:String | evento montage.export campo `stage` |

## TabSongsterr.swift

`SongsterrIssue.message` (`kind` noResults/rateLimited/offline/formatChanged/invalidLink/other) viene de SongsterrKit (parte 2), salvo los dos `.other` de abajo.

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 41 | sin código | songsterr_load_unsupported | Este programa no puede leer páginas de Songsterr. | - | `LocalizedError` del fetcher; llega vía `describe` a `SongsterrIssue.message` (kit) |
| 42 | sin código | songsterr_load_offline | No se pudo cargar la página. | - | ídem |
| 43 | sin código | songsterr_load_timeout | La página tardó demasiado en cargar. | - | ídem |
| 44 | sin código | songsterr_load_http | La página respondió con el error \(c). | c:Int | ídem |
| 45 | sin código | songsterr_load_cancelled | Carga cancelada. | - | ídem |
| 169, 356 | sin código | songsterr_downloading | Descargando pistas de Songsterr… | - | `songsterr.state.workingText` (stage "working") |
| 172 | sin código | songsterr_aligning | Alineando con el audio… | - | `workingText` (vía `input.progress`) |
| 355 | sin código | songsterr_reading | Leyendo Songsterr… | - | `workingText` |
| 353 | sin código | songsterr_suggest_automatic | Puedes transcribir el tema automáticamente. | - | `SongsterrIssueInfo.suggestion` (en `search.issue`, `detailIssue`, `linkIssue`, `failure`) |
| 354 | sin código | songsterr_pairing_intro | Qué pista de Songsterr va con cada stem. La confianza es el parecido medido con el audio. | - | `pairing.intro` |
| 402 | unsupported | songsterr_host_unsupported | Este anfitrión no puede leer páginas de Songsterr. | - | error de songsterr.open |
| 426 | not-open | songsterr_sheet_not_open | La hoja de Songsterr no está abierta. | - | error de songsterr.* |
| 448 | not-open | tab_not_open | No hay ninguna tablatura abierta. (repetido de TabService:224) | - | error |
| 484 | not-ready | songsterr_no_song_selected | No hay ningún tema marcado. | - | error de songsterr.import |
| 492 | not-ready | songsterr_tab_not_songsterr | La tablatura no usa Songsterr. | - | error |
| 501 | not-ready | songsterr_nothing_to_retry | No hay ninguna importación que repetir. | - | error de songsterr.retry |
| 547 | sin código | songsterr_issue_nothing_to_align | Ninguna pista de guitarra o bajo de Songsterr se pudo medir con el audio del tema. | - | `songsterr.state.failure.message` (kind "other") |
| 555 | sin código | songsterr_issue_no_beat_grid | El tema aún no tiene análisis de pulso. | - | `failure.message` (kind "other") |
| 616, 622 | not-ready | songsterr_no_pairing | No hay emparejamiento abierto. | - | error de songsterr.pair* |
| 630 | not-ready | songsterr_no_pairing_to_accept | No hay emparejamiento que aceptar. | - | error de songsterr.accept |
| 633 | unsupported | tab_no_library | No hay biblioteca donde guardar la fuente. (repetido de TabService:325) | - | error |
| 648 | internal | songsterr_grid_save_failed | No se pudo guardar la rejilla de Songsterr: \(error) | error:String (técnico) | error |
| 653 | internal | tab_source_save_failed | No se pudo guardar la fuente: \(error) (repetido de TabService:327) | error:String | error |
| 725 | sin código | songsterr_percent | \(n) % | n:Int (redondeado, sin decimales; espacio antes de %) | `choice.label` = «nombre (n %)» y `slots[].confidenceText` |
| 740, 746 | sin código | songsterr_unmeasured | sin medir | - | `slots[].confidenceText` |
| 753 | sin código | songsterr_extra_tracks | Pistas extra, sin stem: \(extra). Entran en la tablatura y en el .gp y solo suenan con «Oír transcripción». | extra:String (nombres unidos con «, »; mejor pasar `extraNames` y componer en Dart) | `pairing.extraNote` (campo junto a `intro`; confirmar nombre en 751) |
| 95 | sin código | (técnico) | sin script de estado (dentro de `SongsterrError.unknownFormat`) | - | solo aparece en `SongsterrIssue(.other)` si el kit lo describe; no traducir |

## TakeViewMethods.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 24 | not-found (311, 315, 363) | takeview_no_audio | Esta toma no tiene audio que reproducir. | - | error de takeview.open / offset.open |
| 25, 278 | not-open | takeview_not_open | No hay ninguna toma abierta en el visor. | - | error de takeview.* |
| 28, 361 | no-offset | takeview_no_offset_sheet | No hay ninguna hoja de desfase abierta. | - | error de offset.* |
| 175-177 | audio-unavailable | takeview_audio_unavailable | No se pudo reproducir: la salida de audio no abre (\(error)). | error:String (kit, `describe`) | error de takeview.play |
| 270 | bad-params | takeview_bad_seconds | «seconds» no es un número. | - | error de takeview.seek |
| 302 | bad-params | core_ids_not_uuid | «\(first)» y «\(second)» deben ser UUID. | first:String, second:String (nombres de parámetro; aquí `projectId`, `takeId`). Mismo código que en `mensajes-nucleo.md` | error de takeview.open |
| 308 | internal | montage_project_read_failed | No se pudo leer project.json: \(error) (repetido de MontageMethods:540) | error:String | error |
| 348, 372 | load-failed | takeview_prepare_failed | No se pudo preparar la toma (\(error)). | error:String (kit) | error de takeview.open / offset.open |
| 404 | sin código | takeview_output_failed | No se pudo abrir la salida de audio (\(error)). | error:String (kit) | `takeview.state.audioError` (campo en 101/295) |

## TabMethods.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 9, 66 | not-open | tab_not_open | No hay ninguna tablatura abierta. (repetido de TabService:224) | - | error de métodos tab.* |
| 17, 39, 44, 49 | bad-params | tab_missing_track | Falta «track». | - | error |

## MontageController.swift

`(error)` = `"\(error)"` de Swift, texto técnico sin traducir.

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 555 | sin código | montage_preview_failed | No se pudo preparar la vista previa (\(error)). | error:String (técnico) | `montage.state.preview.error` |
| 584-585 (571, 716) | sin código / audio-unavailable (718) | montage_audio_play_failed | No se pudo reproducir: la salida de audio no abre (\(error)). | error:String (`errorDescription` o descripción) | `montage.state.audio.error` / `audioError`; error de método con code audio-unavailable (718: mensaje = audioError) |
| 672 | sin código | montage_audio_mix_failed | No se pudo mezclar el audio de la vista previa (\(error)). | error:String | `audio.error` |
| 688 | sin código | montage_audio_open_failed | No se pudo abrir el audio de la vista previa (\(error)). | error:String | `audio.error` |
| 832 | not-found | montage_take_no_video | La toma no tiene vídeo. | - | error de montage.frame |
| 837 | internal | montage_frame_read_failed | No se pudo leer el fotograma de la toma (\(error)). | error:String | error |
| 840 | no-frame | montage_take_no_frame | La toma no tiene imagen en ese instante. | - | error |
| 847 | internal | montage_frame_save_failed | No se pudo guardar el fotograma (\(error)). | error:String | error |
| 491 | sin código | montage_framing_failed | \(error) (sin texto propio) | error:String (técnico) | evento montage.framing campo `error` (status "failed") |
| 881, 941 | sin código | montage_stage_mixing | Mezclando el audio | - | evento montage.export campo `stage` (phase "running"); mejor emitir `stage` como código |
| 948 | sin código | montage_stage_encoding | Codificando el vídeo | - | evento montage.export campo `stage` |
| 968 | sin código | montage_export_failed | No se pudo exportar el vídeo (\(error)). | error:String (técnico) | evento montage.export campo `message` (phase "failed") |

## RecordController.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 292 | sin código | record_default_part_name | Guitarra | - (nombre por defecto de la primera parte; se persiste en project.json: decisión de Jorge si se traduce al crear) | `record.state` partes |
| 298 | sin código | record_notice_unindexed_takes | Este proyecto tiene tomas en disco sin índice; no se ha modificado. Restaura `project.json` desde la copia `.bak`. | - | `record.state.messages[]` |
| 317 | sin código | record_notice_profile_save_failed | No se pudo guardar el perfil (\(error)). | error:String | `messages[]` |
| 522 | sin código | record_load_stems_failed | No se pudieron cargar los stems (\(error)). | error:String | `record.state.loadError` |
| 526 | sin código | record_load_output_failed | No se pudo abrir la salida de audio (\(error)). | error:String (kit) | `loadError` |
| 579 | sin código | record_load_takes_failed | No se pudieron cargar tus tomas anteriores (\(error)). | error:String | `loadError` |
| 592 | sin código | record_fps_integer | \(n) fps | n:Int | `camera.label` (junto a la resolución, separada por « · ») |
| 592 | sin código | record_fps_fractional | \(fps) fps | fps:# (2 decimales, coma: «29,97») | `camera.label` |
| 629, 636 | sin código | record_camera_none | No hay ninguna cámara conectada. | - | `camera.message` (se le antepone cámara + record_camera_audio_only) |
| 636 | sin código | record_camera_chosen_missing | La cámara elegida en Ajustes no está conectada. | - | `camera.message` |
| 670 | sin código | record_camera_open_failed | No se pudo abrir la cámara (\(error)). | error:String | `camera.message` |
| 694 | sin código | record_camera_disconnected | Se desconectó la cámara: se grabará solo el audio. | - (ya incluye el sufijo; sin duplicar) | `camera.message` |
| 701 | sin código | record_camera_audio_only | \(m) Se grabará solo el audio. | m:String (uno de los textos anteriores) | `camera.message` (mejor: código de estado + sufijo en Dart) |
| 704 | sin código | record_camera_denied_windows | Sin permiso de cámara: se grabará solo el audio. Concédelo en Configuración de Windows > Privacidad y seguridad > Cámara. | - | `camera.message` (variante por plataforma: en Dart) |
| 706 | sin código | record_camera_denied_macos | Sin permiso de cámara: se grabará solo el audio. Concédelo en Ajustes del Sistema > Privacidad > Cámara. | - | `camera.message` |
| 718 | record-blocked | record_block_no_part | Elige una parte. | - | `record.state.blockReason`; error de record.start (RecordMethods:267) |
| 720 | record-blocked | record_block_no_take_punch | Elige la toma sobre la que hacer el punch-in. | - | `blockReason` / error |
| 721 | record-blocked | record_block_no_punch_range | Marca la entrada y la salida del punch-in en la línea de tiempo. | - | `blockReason` / error |
| 790 | sin código | record_device_not_open | El dispositivo no está abierto. | - | `messages[]` (vía RecordFailure 866) |
| 816 | sin código | record_start_failed | No se pudo empezar a grabar. (prioridad: `audio.takeNotices.first`, texto del kit) | notice:String? (kit) | `messages[]` |
| 829 | sin código | record_save_take_failed | No se pudo guardar la toma. (idem, `takeNotices.first`) | notice:String? (kit) | `messages[]` |
| 831 | sin código | record_notice_take_cut | La toma se detuvo y se guardó lo grabado. | - | `messages[]` |
| 848 | sin código | record_notice_no_frames | No llegaron fotogramas de la cámara: la toma es solo de audio. | - | `messages[]` |
| 866 | sin código | record_take_failed | No se pudo grabar la toma (\(error)). | error:String (si no es RecordFailure) | `messages[]` |
| 1059 | sin código | record_delete_take_failed | No se pudo borrar la toma (\(error)). | error:String | `messages[]` y valor devuelto de record.deleteTake |
| 1092 | sin código | record_punch_take_missing | No se encontró la toma del punch. | - | `messages[]` (vía RecordFailure) |

## StudyMethods.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 18 | sin código | study_channel_vocals / drums / bass / guitar / piano / other | Voz / Batería / Bajo / Guitarra / Piano / Resto | - | `study.state.channels[].name` (y `record.state` canales, RecordMethods:680) |
| 262 | bad-params | study_bad_channel | «channel» no es un canal del mezclador: \(channel) | channel:String | error de study.setChannel |
| 279 | bad-params | core_project_id_not_uuid | «projectId» no es un UUID. (repetido) | - | error de study.open |
| 284 | internal | montage_project_read_failed | No se pudo leer project.json: \(error) (repetido de MontageMethods:540) | error:String | error |
| 343 | not-open | backing_not_open | No hay ningún tema abierto en Backing. (repetido) | - | error de study.* |

## PlaylistMethods.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 194 | sin código | playlist_warning_split_failed | No se pudo separar \(title): \(error) | title:String (nombre del tema), error:String (kit) | `playlist.state.warnings[]` |
| 204 | no-playlist | playlist_not_open | No hay ninguna lista abierta. | - | error de playlist.* |
| 354 | sin código | import_stage_converting | Convirtiendo a WAV… | - | `JobInfo.text` (stage "import") |
| 356 | sin código | import_stage_downloading | Descargando audio… | - | `JobInfo.text` (stage "download", sin progreso) |
| 356 | sin código | import_stage_downloading_pct | Descargando audio… \(n) % | n:Int (redondeado) | `JobInfo.text` |
| 407 | not-found | playlist_candidate_not_of_song | Ese candidato no es de este tema. | - | error |
| 410 | in-library | playlist_already_in_library | Ese vídeo ya está en la biblioteca. | - | error |
| 432 | not-found | playlist_song_not_in_list | Ese tema no está en la lista (\(id)). | id:String | error |

## StudyBacking.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 63 | sin código | record_load_stems_failed | No se pudieron cargar los stems (\(error)). (mismo texto que RecordController:522) | error:String | `study.state.loadError` |
| 70 | sin código | takeview_output_failed | No se pudo abrir la salida de audio (\(error)). (mismo que TakeViewMethods:404) | error:String (kit) | `study.state.audioError` |
| 127 | load-failed | (dinámico) | \(loadError) | loadError:String (el de 63) | error de study.play |
| 128 | load-failed | backing_no_stems | El tema no tiene stems que reproducir. | - | error de study.play |
| 133-135 | audio-unavailable | takeview_audio_unavailable | No se pudo reproducir: la salida de audio no abre (\(error)). (repetido de TakeViewMethods:175) | error:String (kit) | error de study.play |

## FrameRelay.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 252 | not-found | frames_no_relay | No hay relevo de fotogramas «\(channel)». | channel:String | error de frames.stats (diagnóstico) |

## CameraPreview.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 49 | internal | core_open_settings_failed | No se pudieron abrir los ajustes del sistema: \(error) | error:String | error de camera.openSettings |
| 59 (118, 150) | sin código | camera_denied | ToneForge no tiene permiso para usar la cámara. | - | `CameraPreviewResult.message` (state "denied") |
| 153 | sin código | record_camera_open_failed | No se pudo abrir la cámara (\(error)). (mismo que RecordController:670) | error:String | `message` (state "failed") |
| 172 | sin código | record_camera_none | No hay ninguna cámara conectada. (mismo que RecordController:629) | - | `message` (state "noCamera", sin cámara elegida) |
| 172 | sin código | camera_chosen_disconnected | La cámara elegida está desconectada. | - | `message` (state "noCamera") |

## StudySession.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 253, 271 | sin código (save-failed en StudyEdits:161) | study_sections_save_failed | No se pudieron guardar las secciones: \(error) | error:String (localizedDescription) | `study.state.saveError`; `guitarOptionsError` -> `StudyEdits` `saveError` (216) y error `save-failed` (StudyEdits:161) |
| 355 | sin código | record_take_save_unsupported | No se pudo guardar la toma en el proyecto (este almacén no guarda tomas). | - | `record.state.takeSaveError` |
| 364 | sin código | record_take_save_failed | No se pudo guardar la toma en el proyecto (\(error)). | error:String | `takeSaveError` |
| 394 | sin código | study_save_failed | No se pudo guardar el estudio: \(error) | error:String | `saveError` |
| 402 | sin código | study_names_save_failed | No se pudieron guardar los nombres: \(error) | error:String | `guitarOptionsError` (ver arriba) |

## PlaylistSession.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 87 | sin código | playlist_indicator_loading | Leyendo la lista… | - | `playlist.state.indicator` |
| 88 | sin código | playlist_indicator_searching | Buscando \(i) de \(n) | i:Int, n:Int | `indicator` |
| 91 | sin código | playlist_indicator_running | Importando \(i) de \(n) | i:Int, n:Int | `indicator` |
| 92 | sin código | playlist_indicator_stopped | Importación detenida | - | `indicator` |
| 93 | sin código | playlist_indicator_finished | Importación terminada | - | `indicator` |
| 94 | sin código | playlist_indicator_cancelled | Importación cancelada | - | `indicator` |

## MontageServices.swift y MontageSimulation.swift

`MontageError.composition(String)` (kit); su descripción final llega en `montage.export.message` / `preview.error` dentro de `\(error)`. Son técnicos: no traducir, dejar como detalle.

| fichero:línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| MontageServices:65 | sin código | (técnico) | sin compositor de fotogramas en este sistema | - | detalle de montage_export_failed / montage_preview_failed |
| MontageServices:125 | sin código | (técnico) | sin fotograma | - | ídem |
| MontageServices:146 | sin código | (técnico) | sin búfer de \(w)×\(h) | w:Int, h:Int | ídem |
| MontageServices:153 | sin código | (técnico) | sin contexto de dibujo | - | ídem |
| MontageSimulation:52 | sin código | (técnico) | sin búfer | - | ídem |

## Services.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 162 | sin código | separation_helper_missing | No se encuentra el helper de separación (tf-separate) junto a la app. | - | `JobInfo.error` (job de separación) |
| 185 | sin código | separation_memory_limit | La separación superó el límite de memoria (\(gb) GB). | gb:# (formato `%g` con punto decimal: pasar como número y formatear con coma en Dart) | `JobInfo.error` |
| 188 | sin código | separation_helper_failed | El helper de separación falló (código \(code)).[ \(tail)] | code:Int, tail:String (cola del log del helper, opcional, técnico) | `JobInfo.error` |
| 190 | sin código | separation_invalid_input | Entrada no válida: \(m) | m:String (técnico) | `JobInfo.error` |
| 214 | sin código | separation_not_finished | El tema no tiene una separación terminada. | - | `LocalizedError` (error de método o job que usa la separación) |

## TabTranscribing.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 91 | sin código | tab_soundfont_missing | Falta el soundfont de la síntesis (\(path)). | path:String (ruta relativa) | `TabFailure.message` -> `tab.state.tracks[].synth` fallo / flash (tab_flash_synth_failed) |

## GuitarSplitter.swift

| línea | code actual | propuesto | texto | args | vía |
|---|---|---|---|---|---|
| 20 | sin código | guitar_lead_model_unavailable | Modelo de solista no disponible | - | `JobInfo.error` / `guitarSplitFailed` |
| 20 | sin código | guitar_lead_model_unavailable_detail | Modelo de solista no disponible: \(detail) | detail:String (técnico) | ídem |
