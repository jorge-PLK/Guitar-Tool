# Mensajes de paquetes (parte 2, pendientes de `mensajes-nucleo-paquetes.md`)

Estado: COMPLETO. Hecho: StemKit, VideoKit, StudyKit, NativeKit, AnalysisKit/HeadRushKit/MatchKit/Tone3000Kit. Números con coma decimal: «(coma)». Rutas relativas a `Packages/<Kit>/Sources/`.

`AppCore` depende (Package.swift:13-26) de: Store, AudioKit, ModelKit, StemKit, StudyKit, SourceKit, TabKit, NativeKit (solo producto `NativeAudioFile`), VideoKit. NO depende de AnalysisKit, HeadRushKit, MatchKit ni Tone3000Kit.

## Recuento (contado por grep)

| Paquete | Textos | Llegan |
|---|---|---|
| StemKit | 31 `invalidInput` + 4 filas `SeparationError` + 7 filas stderr | 2 `invalidInput` directos; el resto solo como cola de `helperFailed` o vía `GuitarSplitting` |
| VideoKit | 37 filas de error + 10 pasos HRESULT + 1 nombre de cámara | sí (por `\(error)`) |
| StudyKit | 19 textos (+2 `PlatformError`) | llegan sin texto (ver sección) |
| NativeKit | 8 (ya listados en la parte 1) | no llegan, salvo uno probable |
| AnalysisKit, HeadRushKit, MatchKit, Tone3000Kit | 0 (1 fichero `.swift` cada uno, sin errores ni cadenas con texto) | no los usa `AppCore` |

## StemKit

Cómo llega: `SeparationRunner` → `Services.swift:175-190` (`translate`) → `SeparationFailure` (AppCore). Solo dos `invalidInput` nacen en la app (SeparationRunner:49,61) y llegan como «Entrada no válida: {m}» (`Services.swift:190`). Los demás nacen en el helper `tf-separate`, escriben en stderr y llegan SOLO dentro de `stderrTail` de `helperFailed` («El helper de separación falló (código N). {cola}», `Services.swift:188`), con prefijo `tf-separate: ` (y «entrada no válida: » el que pasa por `describe`). Los marcados (G) (`GuitarStemComposer`, `PanSplitter`, `RoformerLeadSeparator`) corren en proceso vía `PortableGuitarSplitter` y llegan por `GuitarSplitting` → `LeadModelUnavailable(detail: error.localizedDescription)` (`GuitarSplitter.swift:44`, solo si falla el separador de solista) o por el error crudo (sin confirmar). Opinión (decisión de Jorge): el helper devuelve `code` estable; Dart muestra el texto genérico y deja `message` como detalle técnico.

### Casos de `SeparationError` (SeparationRunner.swift:15-22)

| fichero:línea | caso | código | texto (es) | args | llega por |
|---|---|---|---|---|---|
| SeparationRunner.swift:17 | `memoryLimitExceeded` | `stem_memory_limit` | (lo pone AppCore: «La separación superó el límite de memoria ({gb} GB).») | gb: double `%g` (punto), GB | `Services.swift:185` (ya en `mensajes-nucleo.md`) |
| SeparationRunner.swift:19 | `helperFailed` | `stem_helper_failed` | (AppCore: «El helper de separación falló (código {code}).» + cola) | code: int32; stderrTail: string (≤4096 B) | `Services.swift:188` |
| SeparationRunner.swift:20 | `cancelled` | `stem_cancelled` | sin texto propio | — | `Services.swift:175+` (sin confirmar) |
| SeparationRunner.swift:97-98 | `helperFailed` al lanzar | `stem_helper_launch_failed` | no se pudo lanzar el helper: {error} | error: string del sistema | como `helperFailed` (código -1) |

### `invalidInput` (app)

| fichero:línea | código | texto (es) | args | llega por |
|---|---|---|---|---|
| SeparationRunner.swift:49 | `stem_input_missing` | no existe el {what}: {path} | what: «modelo»/«entrada»; path: string | `Services.swift:190` |
| SeparationRunner.swift:61 | `stem_helper_missing` | no existe el helper: {path} | path: string | `Services.swift:190` (AppCore ya comprueba el helper en `:162` con otro texto) |

### `invalidInput` (helper o proceso)

| fichero:línea | código | texto (es) | args |
|---|---|---|---|
| AudioIO.swift:25 | `stem_audio_unreadable` | no se puede leer {why} | why: string |
| AudioIO.swift:27 | `stem_audio_unreadable_file` | no se puede leer {file}: {error} | strings |
| AudioIO.swift:52 | `stem_not_stereo` | se esperaba audio estéreo y tiene {n} canales | n: int |
| AudioIO.swift:55 | `stem_sample_rate_unsupported` | frecuencia {sr} Hz no admitida (44100 o 48000) | sr: Hz (punto) |
| AudioIO.swift:58 | `stem_audio_empty` | el audio está vacío | — |
| AudioIO.swift:177 | `stem_resample_unsupported` | AVAudioConverter no admite {from} → {to} Hz | Hz (punto) |
| AudioIO.swift:195 | `stem_resample_failed` | remuestreo falló: {error} | string |
| AudioIO.swift:255 | `stem_resampler_unavailable` | remuestreador no disponible para {from} → {to} Hz: {error} | Hz; string |
| PanSplitter.swift:189 (G) | `stem_not_stereo` | se esperaba audio estéreo y tiene {n} canales | n: int |
| PanSplitter.swift:193 (G) | `stem_audio_too_short_pan` | audio demasiado corto para separar por panorama ({n} muestras) | n: int |
| PanSplitter.swift:598 (G) | `stem_read_incomplete` | lectura incompleta: {got} de {count} muestras | int, int |
| MaskModel.swift:50 | `stem_mask_shape` | máscara con forma {shape}, se esperaba [1, {stems}, {rows}, {frames}, 2] | shape: [int]; int ×3 |
| MaskModel.swift:53 | `stem_mask_strides` | máscara con strides no soportados {st} | [int] |
| MaskModel.swift:70 | `stem_fp16_failed` | FP16→FP32 falló ({err}) | int |
| MaskModel.swift:108 | `stem_model_input_missing` | el modelo no tiene la entrada {name} {expectedIn} | string; [int] |
| MaskModel.swift:116 | `stem_model_output_missing` | el modelo no tiene la salida {name} | string |
| MaskModel.swift:134 | `stem_model_no_output` | el modelo no devolvió {name} | string |
| MaskModel.swift:152 | `stem_mask_dtype` | máscara de tipo no soportado {raw} | int |
| GuitarStemComposer.swift:104 (G) | `stem_input_is_output` | la entrada no puede ser una pista de guitarra de salida | — |
| GuitarStemComposer.swift:116 (G) | `stem_not_stereo` | se esperaba audio estéreo y tiene {n} canales | n: int |
| GuitarStemComposer.swift:119 (G) | `stem_audio_empty` | el audio está vacío | — |
| GuitarStemComposer.swift:133 (G) | `stem_solo_no_separator` | hay tramos de solo y no hay separador de solista | — |
| GuitarStemComposer.swift:157-158 (G) | `stem_separator_length_mismatch` | el separador devolvió {l}/{r} muestras para {n} | int ×3 |
| GuitarStemComposer.swift:283 (G) | `stem_read_short` | lectura corta: {got} de {n} muestras | int ×2 |
| OnnxMaskModel.swift:33 | `stem_onnx_spec_real_shape` | spec_real con forma {shape} | [int] |
| OnnxMaskModel.swift:47 | `stem_onnx_input_shape` | {name} con forma {shape} | string; [int] |
| OnnxMaskModel.swift:55 | `stem_onnx_inputs_missing` | el modelo no tiene spec_real/spec_imag ni {name}: {names} | string; [string] |
| RoformerLeadSeparator.swift:37 (G) | `stem_lead_chunk_invalid` | tramo estéreo vacío o con canales de distinta longitud | — |
| RoformerLeadSeparator.swift:39 (G) | `stem_lead_sample_rate` | frecuencia {sr} Hz no válida | Hz |

### Stderr del helper (`tf-separate/TFSeparate.swift`, prefijo `tf-separate: `)

| línea | código | texto (es) | args |
|---|---|---|---|
| 42 | `stem_cli_missing_value` | falta el valor de {a} | string |
| 47 | `stem_cli_unknown_arg` | argumento desconocido {a} + línea de uso | string |
| 52 | `stem_cli_usage` | uso: tf-separate --model (ruta .mlmodelc) --input (wav) --out (carpeta) | — |
| 74 | `stem_model_load_failed` | no se pudo cargar el modelo: {describe} | string |
| 77,86 | `stem_helper_sigterm` | interrumpido por SIGTERM | — |
| 90 | `stem_helper_stop_event` | interrumpido por el evento de parada | — |
| 92,120 | `stem_helper_error` | entrada no válida: {msg} (si `invalidInput`) o `\(error)` | string |

Las filas 42/47/52 no pueden ocurrir con la app (construye los argumentos). `MaskModel.swift:36` (`PlatformError.unsupported`) solo en Linux: no llega. Sin confirmar: destino exacto de `cancelled` y del error crudo de `GuitarStemComposer`.

## VideoKit

`tf-video` (CLI) excluido; AppCore no lo usa. Ningún error lleva `LocalizedError`; AppCore los interpola con `\(error)`:

- `MontageError` tiene `CustomStringConvertible` (MontageBuilder.swift:21-31) → «No se pudo exportar el vídeo ({desc}).» (`MontageController.swift:968`) y «No se pudo preparar la vista previa ({desc}).» (`:555`).
- `GuitarFramerError`, `VideoTakeWriterError` y `CameraError` NO tienen `description`: `\(error)` imprime el volcado Swift, p. ej. `read("pista de vídeo")`, `noFormats("id")`, `alreadyRunning`, `empty`. Llegan por `setFraming(.failed("\(error)"))` (`MontageController.swift:491`), «No se pudo grabar la toma ({error}).» (`RecordController.swift:866`; sin confirmar que `VideoTakeWriterError` siempre pase por ahí) y «No se pudo abrir la cámara ({e}).» (`RecordController.swift:670`; `noAccess` va a `cameraState = .denied`).
- Propuesta (decisión de Jorge): código por caso con args, sin volcado Swift.

### MontageError (MontageBuilder.swift:8-16)

| fichero:línea | caso | código | texto (es) | args |
|---|---|---|---|---|
| MontageBuilder.swift:24 | `noVideo` | `video_montage_no_video` | ninguna parte tiene imagen | — |
| MontageBuilder.swift:25 | `audio(s)` | `video_montage_audio` | no se pudo leer el audio {s} | s: fichero |
| MontageBuilder.swift:26 | `composition(s)` | `video_montage_composition` | {s} (texto libre, ver abajo) | string |
| MontageBuilder.swift:27 | `read(s)` | `video_montage_read` | lectura de la composición: {s} | string |
| MontageBuilder.swift:28 | `write(s)` | `video_montage_write` | escritura del fichero: {s} | string |
| MontageBuilder.swift:29 | `containerMismatch` | `video_montage_container_mismatch` | la extensión .{got} no es la del contenedor .{expected} | strings (extensión) |

Orígenes de `s` (llegan por `MontageController:968/555`):

| fichero:línea | código | texto (es) | args |
|---|---|---|---|
| MontageBuilder.swift:124 | `video_montage_composition` | pista de vídeo | — |
| MontageBuilder.swift:132-133 | `video_montage_tracks_end` | las pistas de vídeo acaban en {a} s y el montaje dura {b} s | a,b: double, 4 decimales con punto (`%.4f`), s |
| MontageExporter.swift:187-188 | `video_montage_invalid_composition` | composición de vídeo no válida: {detail} (composición {t1}, lectura {t2}) | strings (`CompositionCheck.text`) |
| MontageExporter.swift:257 | `video_montage_read` | salida de vídeo | — |
| MontageExporter.swift:275 | `video_montage_write` | pista de vídeo | — |
| MontageExporter.swift:292 | `video_montage_write` | pista de audio | — |
| MontageExporter.swift:315,317,319,334,336,339 | `video_montage_write`/`_read` | startWriting / startReading / startReading audio / lectura de vídeo / lectura de audio / estado {n} (si no hay `error`) | n: int |
| MontageExporter.swift:86,146 | `containerMismatch` | (fila de arriba) | extensiones |
| MontageBuilder.swift:102; MontageExporter.swift:159; WindowsMontage.swift:332; MediaFoundationExport.swift:37,38 | `audio` | (fila de arriba) | fichero |
| MontageRendering.swift:27 | `video_montage_composition` | sin compositor en este sistema | — |
| Direct2DCompositor.swift:42 | `video_d2d_hresult` | Direct2D {step}: HRESULT 0x{hr} | step: string; hr: hex |
| Direct2DCompositor.swift:54 | `video_d2d_no_context` | Direct2D sin contexto | — |
| Direct2DCompositor.swift:74 | `video_d2d_too_many_plates` | Direct2D: demasiadas placas | — |
| Direct2DCompositor.swift:113 | `video_d2d_not_bgra` | Direct2D: la salida debe ser BGRA | — |
| Direct2DCompositor.swift:167 | `video_d2d_box_hresult` | Direct2D recuadro {partID}: HRESULT {hr} | string; hr: int decimal |
| WindowsMontage.swift:38 | `video_montage_read` | {fichero}: {error} | strings |
| MediaFoundationExport.swift:52,96,106,119,130; MontageExporter.swift:170,261 | `video_montage_write` | {error} (volcado del sistema) | string |
| MediaFoundationExport.swift:104; MontageBuilder.swift:127,154 | `video_montage_composition` | {error} (volcado) | string |
| MontageCompositor.swift:69 | `video_compositor_instruction` | instrucción o búfer (`NSError`, solo macOS) | — |

### GuitarFramerError (GuitarFramer+Vision.swift:8-11 macOS; +Onnx.swift Windows). Llega por `MontageController.swift:491`

| fichero:línea | caso | código | texto (es) | args |
|---|---|---|---|---|
| Vision.swift:23; Onnx.swift:46,77 | `noVideo` | `video_framer_no_video` | {fichero} / sin vídeo | fichero: string |
| Vision.swift:27 | `read` | `video_framer_read` | pista de vídeo | — |
| Vision.swift:31,35,52 | `read` | `video_framer_read` | {error} / startReading / lectura | string |
| Onnx.swift:18 | `read` | `video_framer_model_load` | no se pudo cargar {modelo}: {error} | strings |
| Onnx.swift:25 | `read` | `video_framer_input_size` | entrada de {n} valores, se esperaban {m} | int ×2 |
| Onnx.swift:61,90 | `read` | `video_framer_read` | {error} | string |
| Onnx.swift:102 | `read` | `video_framer_no_pose_model` | sin modelo de pose en {ruta} | string |

### VideoTakeWriterError (VideoTakeWriter.swift:25-30). Llega por `RecordController.swift:866` (sin confirmar)

| fichero:línea | caso | código | texto (es) | args |
|---|---|---|---|---|
| VideoTakeWriter.swift:26,72,85,87; MediaFoundationWriter.swift:59 | `cannotCreate` | `video_writer_cannot_create` | {error} / no se puede añadir la pista de vídeo / startWriting | string |
| VideoTakeWriter.swift:27,143; MediaFoundationWriter.swift:135,148,149 | `failed` | `video_writer_failed` | {error} / estado {n} / lista de ediciones: {error} | n: int; string |
| VideoTakeWriter.swift:29 | `empty` | `video_writer_empty` | sin texto (no llegó ningún fotograma con tiempo del tema) | — |
| MP4EditList.swift:75,83,85,106,112,122,124,132,134,181,184,197 | `Failure.malformed` | `video_mp4_malformed` | caja {type} de {size} bytes en {off} / sin moov / moov truncado / caja de 64 bits truncada / tamaño de caja {size} en {off} / no es moov / sin mvhd / trak sin mdia / mdia sin mdhd o hdlr / stts truncado | type: string; size, off: int |

`Failure.malformed` llega envuelto en `failed("lista de ediciones: …")` (MediaFoundationWriter.swift:135).

### CameraError (CameraCapture.swift:34-40). Llega por `RecordController.swift:670`

| fichero:línea | caso | código | texto (es) | args |
|---|---|---|---|---|
| CameraCapture.swift:35 | `notFound(id)` | `video_camera_not_found` | sin texto (volcado `notFound("{id}")`) | id: string |
| CameraCapture.swift:36 | `noAccess` | `video_camera_no_access` | sin texto | — |
| CameraCapture.swift:37 | `noFormats(id)` | `video_camera_no_formats` | sin texto | id: string |
| CameraCapture.swift:38,103,104,109,119; MediaFoundationCamera.swift:153 | `configuration(s)` | `video_camera_configuration` | {error} / no se puede añadir la entrada / no se puede añadir la salida / iniciar la captura: HRESULT 0x{hr} | string; hr: hex |
| CameraCapture.swift:39 | `alreadyRunning` | `video_camera_already_running` | sin texto | — |
| CameraDevice.swift:69 | nombre cámara simulada | `video_camera_simulated` | Cámara simulada | — |

`CameraDevice.name` (incluido «Cámara simulada») llega por `VideoCameraAdapter.swift:18` (`SettingsCamera.name`) y `RecordMethods.swift:627` (`RecordCameraEntry.name`): confirmado.

### Pasos de `MediaFoundationError` (MediaFoundation.swift:13: «{step}: HRESULT 0x{hr}»; envuelto en `MontageError` o `VideoTakeWriterError`)

`abrir {fichero}` (:133), `abrir vídeo {fichero}` (:146; WindowsMontage:98), `leer vídeo` (:151; con fichero en WindowsMontage:104), `abrir audio {fichero}` (:175), `leer audio` (:183), `escribir vídeo` (:251), `escribir audio` (:257), `cerrar el fichero` (:260), `crear el escritor` (:241), `iniciar la captura` (MediaFoundationCamera:153). Códigos `video_mf_open`, `video_mf_open_video`, `video_mf_read_video`, `video_mf_open_audio`, `video_mf_read_audio`, `video_mf_write_video`, `video_mf_write_audio`, `video_mf_close`, `video_mf_create_writer`, `video_mf_start_capture`. args: fichero: string; hr: hex.

## StudyKit

Hecho: `BeatError` (LogMel.swift:145-149), `ChordError` (ChordRecognizer.swift:38-41) y `MonoResampler.Failure` (Audio/MonoResampler.swift:12) no son `LocalizedError`. Llegan por `Store/Library.swift:834,853` (`error.localizedDescription`) → `.analysisFailed(id, msg)` → `JobQueue.swift:235` (`error:` del trabajo) y `StudyEdits.swift:363`. Hecho medido: ese `localizedDescription` no devuelve el texto de abajo, sino el genérico de Foundation sin detalle; los textos se pierden. Propuesta (decisión de Jorge): `LocalizedError` o código `study_*` con args.

| fichero:línea | caso | código | texto (es) | args | llega por |
|---|---|---|---|---|---|
| Beat/BeatAudio.swift:14 | `BeatError.unreadableAudio` | `study_beat_audio_unreadable` | {fichero}: {error} | strings | análisis (arriba) |
| OnnxPredictors.swift:19 | `BeatError.model` | `study_beat_model_load` | no se pudo cargar {modelo}: {error} | strings | ídem |
| OnnxPredictors.swift:26 | `BeatError.model` | `study_beat_chunk_size` | trozo de {n} valores, se esperaban {m} | int ×2 | ídem |
| Beat/BeatAnalyzer.swift:72 | `BeatError.model` | `study_beat_model_load` | no se pudo cargar {modelo}: {error} | strings | ídem |
| Beat/BeatAnalyzer.swift:87 | `BeatError.model` | `study_beat_outputs_missing` | faltan las salidas beat/downbeat | — | ídem |
| Beat/BeatAnalyzer.swift:93 | `BeatError.model` | `study_beat_frames` | salida de {n} tramas, se esperaban {m} | int ×2 | ídem |
| Chord/ChordAudio.swift:11 | `ChordError.unreadableAudio` | `study_chord_stems_empty` | lista de stems vacía | — | ídem |
| Chord/ChordAudio.swift:17 | `ChordError.unreadableAudio` | `study_chord_audio_unreadable` | {fichero}: {error} | strings | ídem |
| Chord/ChordAudio.swift:22 | `ChordError.unreadableAudio` | `study_chord_sample_rates` | los stems tienen frecuencias de muestreo distintas | — | ídem |
| OnnxPredictors.swift:49 | `ChordError.model` | `study_chord_model_load` | no se pudo cargar {modelo}: {error} | strings | ídem |
| OnnxPredictors.swift:55 | `ChordError.model` | `study_chord_window_size` | ventana de {n} valores, se esperaban {m} | int ×2 | ídem |
| Chord/ChordRecognizer.swift:75 | `ChordError.model` | `study_chord_no_model` | sin modelo | — | ídem |
| Chord/ChordRecognizer.swift:110 | `ChordError.model` | `study_chord_model_load` | no se pudo cargar {modelo}: {error} | strings | ídem |
| Chord/ChordRecognizer.swift:123 | `ChordError.model` | `study_chord_no_logits` | falta la salida logits | — | ídem |
| Chord/ChordRecognizer.swift:126 | `ChordError.model` | `study_chord_output_shape` | salida de forma {shape}, se esperaba [1, {t}, {c}] | shape: [int]; int ×2 | ídem |
| Chord/ChordRecognizer.swift:175 | `ChordError.model` | `study_chord_logits_count` | logits de {n} valores | int | ídem |
| Audio/MonoResampler.swift:29 | `Failure` | `study_resample_r8brain` | r8brain no admite {from} → {to} Hz: {error} | Hz (punto); string | ídem (sin confirmar si pasa por el analizador) |
| Audio/MonoResampler.swift:41 | `Failure` | `study_resample_unsupported` | AVAudioConverter no admite {from} → {to} Hz | Hz | ídem |
| Audio/MonoResampler.swift:59 | `Failure` | `study_resample_failed` | remuestreo falló: {error} | string | ídem |

`Beat/BeatAnalyzer.swift:55` y `Chord/ChordRecognizer.swift:94` (`PlatformError.unsupported("sin motor de inferencia en esta plataforma")`): solo Linux, no llegan.

## NativeKit

Los 8 textos están en la parte 1, sección NativeKit. Comprobado en `Packages/AppCore/Sources`: AppCore solo importa `NativeAudioFile` (Package.swift:30; no `NativePlatform` ni `NativeONNX`). Usos de `AudioFileReader`: `AudioController.swift:87`, `LibraryMethods.swift:185`, `MontageController.swift:415`, `RecordController.swift:397`, todos con `try?` (el error y su texto se descartan): NO LLEGAN. Único `try` sin descartar: `NativeAudioFile.write` en `RecordController.swift:908` (`makeCountInFile`, la cuenta atrás) → probable «No se pudo grabar la toma ({error}).» (`RecordController.swift:866`), sin confirmar. Ese caso es `AudioFileError.unwritable` («No se puede escribir el audio: {s}», parte 1). Los demás (`native_audio_unreadable`, `native_platform_unsupported`, `native_onnx_runtime` y detalles de `AudioFileIO`) no llegan: ONNX se usa desde StemKit/StudyKit (ya inventariados arriba).

## AnalysisKit, HeadRushKit, MatchKit, Tone3000Kit

No los usa `AppCore` (ni su `Package.swift:13-26` ni sus `Sources`: grep de `import` sin resultados). Cada uno tiene 1 fichero `.swift` y grep de `errorDescription|LocalizedError|localizedDescription|throw|Error|cadenas con espacio` sin resultados: 0 textos. Nada que inventariar.
