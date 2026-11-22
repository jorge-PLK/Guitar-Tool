# Ficha de pantalla · Montaje · contrato, textos y desvíos

Continuación de `montaje.md` (apartados 1-4, 6, 7, 10, 11). Aquí van los apartados 5, 8 y 9. Los tipos completos de `montage.*` están en `docs/flutter/contrato-tipos-c.md` (sección `montage`, DTO en las líneas 261-341); aquí solo se citan por nombre. Abreviaturas: MM = `AC/MontageMethods.swift`, MC = `AC/MontageController.swift`, MS = `AC/MontageServices.swift` (`AC/` = `Packages/AppCore/Sources/AppCore/`), MV = `App/Sources/MontageView.swift`, FS = `App/Sources/MontageFramingSheet.swift`, AMC = `App/Sources/MontageController.swift`, WS = `WinApp/Web/montage/store.js`.

## 5. Contrato que usa

Todos los métodos devuelven `MontageSnapshot` salvo los indicados. Las líneas MM de los métodos están en la tabla de `contrato-tipos-c.md` (223-249).

| Acción o momento | Método / evento | DTO (Swift) | Uso hoy en `WinApp/Web` |
| --- | --- | --- | --- |
| Abrir pantalla con tema | `montage.open` `{projectId}` | `MontageOpenParams` MM:267 → `MontageSnapshot` MM:201 | WS:81 (token anti-carrera; suscribe antes, WS:60-63) |
| Salir de la pantalla | `montage.close` | `Empty` | WS:104 |
| Estado | evento `montage.state` | `MontageSnapshot` | WS:60 |
| Posición durante la reproducción | evento `montage.position` (30 Hz) | `MontagePositionEvent` MM:242 `{seconds (tema), videoSeconds, playing}` | WS:61 |
| Progreso de exportación | evento `montage.export` (≤ 4 Hz) | `MontageExportEvent` MM:144 | WS:62 |
| Progreso de análisis de encuadre | evento `montage.framing` | `MontageFramingEvent` MM:153 | WS:63 |
| Vista previa | canal binario `montage` (BGRA, ≤ 60 fps, `latestWins`, lado mayor 640, PTS en ms de vídeo) | `MontageFramePixels` (`AC/FrameImage.swift:9-13`); relé MM:768-775 | JPEG por `frames.montage` (`columns.js:91`, `attachFrames`). En Flutter: `TfVideoSurface` (`Texture`) por el canal de píxeles (N2) |
| Elegir layout | `montage.setLayout` `{layout}` (`side\|grid\|stack\|single\|single-landscape`) | `MontageLayoutParams` MM:268 | WS:122 |
| Rítmica del plano único | `montage.setSingleRhythm` `{partId?}` | `MontagePartParams` MM:269 | WS:123 |
| Casillas: huecos, título, etiquetas, aspecto | `setCutGaps`, `setCaption`, `setShowPartLabels`, `setKeepVideoAspect` `{on}` | `MontageBoolParams` MM:270 | WS:124-127 |
| Reordenar carril | `montage.moveLane` `{id, to}` (`setPartOrder {ids}` existe; la interfaz no lo usa) | `MontageMoveLaneParams` MM:271 | WS:128 |
| Añadir corte (botón o clic en carril «Plano») | `montage.addCut` `{time, partId?, exact?}` | `MontageAddCutParams` MM:273 → `MontageAddCutResult` MM:248 `{cutId, snapshot}` | WS:132-135 (devuelve `cutId` para abrir el menú) |
| Mover corte (arrastre) | `montage.moveCut` `{id, time}` | `MontageCutMoveParams` MM:274 | WS:136 |
| Parte de un corte | `montage.setCutPart` `{id, partId?}` | `MontageCutPartParams` MM:275 | WS:137 |
| Eliminar corte / todos | `montage.removeCut` `{id}` / `clearCuts` | `MontageIDParams` MM:276 | WS:138-139 |
| Ajustes de exportación | `montage.setExport` (parciales: codec, container, resolution, fps, normalize, limiter, trackWAVs) | `MontageSetExportParams` MM:277 | WS:129 |
| Exportar / cancelar / descartar | `startExport`, `cancelExport`, `dismissExport` | `Empty`; estado en `MontageExportInfo` MM:127 y `MontageExportEvent` | WS:142-144 |
| «Mostrar en Finder/Explorador» | `montage.reveal` | `MontageRevealResult` MM:265 `{revealed}` | WS:145-147 |
| Cambiar modo, caja, zoom, desplazamiento de encuadre | `montage.setFraming` | `MontageSetFramingParams` MM:287 | WS:150 |
| Restablecer, reanalizar, girar toma | `resetFraming`, `reanalyze`, `rotateTake` `{takeId}` | `MontageTakeParams` MM:286 | WS:151-153 |
| Fotograma de la hoja | `montage.framingFrame` `{takeId, time}` | `MontageFramingFrameParams` MM:296 → `MontageFramingFrameResult` MM:253 `{path, width, height, time, version, box}`; PNG sin compresión, lado mayor 1280 (MC:829-853) | WS:154; `sheet.js:52-60` con debounce `FRAME_DEBOUNCE_MS` |
| Play / pausa / seek | `montage.play`, `pause`, `seek {seconds}` (tiempo del tema, recortado a `span`; MC:743-751) | `MontageSeekParams` MM:297 | WS:157-168 (seek cada `SCRUB_INTERVAL_MS` = 120 ms y envío final, WS:11) |
| Ritmo de la vista previa | `montage.setPreviewFps` `{fps}` (1...60, defecto 15) | `MontageFPSParams` MM:298 | no se usa |

Reglas de uso en `WinApp/Web` (WS:108-119): las acciones aplican el snapshot de la respuesta; `audio-unavailable` pasa a aviso (`actionError`), `not-open` se ignora, los demás errores se muestran y se registran. Códigos de error: `contrato-tipos-c.md` 342-360. Rutas: `framingFrame.path` es relativa a la carpeta del tema; `export.result.path` es absoluta.

## 8. Textos

Claves ARB propuestas (prefijo `montage`), texto literal de SwiftUI. Los errores de AppCore pasarán a `{code, message, args}` (N1); hasta entonces se muestran tal cual.

| Clave | Texto | Origen |
| --- | --- | --- |
| `montageTitle` | Montaje | MV:30, 137 |
| `montageEmptyNoSongs` | Aún no hay temas con tomas grabadas. Graba alguna parte con vídeo en Grabar. | MV:32 |
| `montagePickSong` | Elige un tema | MV:35 |
| `montageTakesCount` | {n, plural, =1{1 toma} other{{n} tomas}} | MV:135 |
| `montageExport` | Exportar vídeo | MV:143 |
| `montageExportWait` | Espera a que termine el análisis del encuadre | MV:144 |
| `montageExportCancel` | Cancelar exportación | MV:141 |
| `montageAudioOnlyParts` | Sin vídeo (solo audio, sin recuadro): {parts}. | MV:155 |
| `montageExportStage` | {stage}… (`Mezclando el audio` / `Codificando el vídeo`, texto de AppCore) | MV:173 |
| `montageExportDone` | Vídeo exportado: {path} | MV:183 |
| `montageNotNormalized` | (sin normalizar) | MV:190 |
| `montageLimiterPeak` | Se limitó la ganancia para no pasar de −1 dBTP: la mezcla queda por debajo de −14 LUFS. | MV:193 |
| `montageLimiterBoth` | El limitador no llegó a −14 LUFS y −1 dBTP a la vez: la mezcla queda en los valores mostrados. | MV:196 |
| `montageClipped` | {file}: recortado | MV:199 |
| `montageTracksDir` | WAV por pista en {path} | MV:201 |
| `montageReveal` | Mostrar en Finder (Mac) / Mostrar en el Explorador (Windows; texto por confirmar) | MV:185 |
| `montageNoVideoTitle` | Aún no hay tomas con vídeo | MV:229 |
| `montageNoVideoBody` | El montaje usa la mejor toma de cada parte. Graba alguna parte con la cámara y vuelve. | MV:230 |
| `montageLayout` | Layout | MV:255 |
| `montageSingleRhythm` | Rítmica del plano único | MV:287 |
| `montageAutoPart` | Automática ({part}) | MV:289 |
| `montagePreviewTitle` | Vista previa · {canvas} | MV:343 |
| `montageExportSection` | Exportación | MV:441 |
| `montageTransitions` | Transiciones | MV:425, 443 |
| `montageKeepAspectHelp` | Solo en apilado y plano único | MV:468 |
| `montageCodecHevc` / `montageCodecH264` | HEVC / H.264 | MV:448-449 |
| `montageContainerMov` / `montageContainerMp4` | MOV / MP4 | MV:452-453 |
| `montageBand` | Tramo del vídeo | MV:543 |
| `montageNoTake` | Sin toma | MV:551 |
| `montagePlane` | Plano | MV:611 |
| `montageAddCut` | Añadir corte | MV:614 |
| `montageAddCutHelp` | Crea un corte en la posición de la vista previa | MV:620 |
| `montageCutFrom` | Desde {t} manda | MV:699 |
| `montageCutNoTake` | Sin toma en {t} | MV:706 |
| `montageCutUncovered` | {t} · {part} no tiene toma aquí: se ve el automático («La parte» si no hay nombre) | MV:694 |
| `montageCutDelete` | Eliminar corte | MV:710 |
| `montageLegend` | Barra llena = en pantalla; el contorno discontinuo es lo grabado; lo rayado son huecos cortados. La solista solo aparece en el solo y su ent… (texto completo en MV:590) | MV:590 |
| `montageFramingTitle` | Encuadre · {part} | FS:30 |
| `montageFramingFollow` | Seguir la guitarra | FS:32 |
| `montageFramingInstant` | Instante | FS:40 |
| `montageFramingReset` / `Reanalyze` / `Done` | Restablecer / Reanalizar / Hecho | FS:47-51 |
| `montageFramingNoImage` | Sin imagen en este instante | FS:96 |
| `montageFramingFixedHelp` | Caja automática: arrástrala para moverla; el punto de la esquina la escala. (variante con caja manual: FS:183-184) | FS:183 |
| `montageFramingFollowHelp` | El recorte sigue la trayectoria de la guitarra; arrastra sobre el fotograma para desplazarlo. | FS:200 |
| `montageErrNoTakes` | No hay tomas con vídeo que montar. | `not-ready`, MM:476 |
| `montageErrExport` | No se pudo exportar el vídeo ({error}) | AppCore (MC) |

Pendiente al implementar: copiar del fichero los textos de `limiterText` (MV:186-192), de `CameraChoices.label` (resolución y fps) y de las ayudas de zoom y desplazamiento (FS:181-212); no están transcritos aquí.

## 9. Desvíos detectados

Clasificación según la regla de `docs/flutter/desvios.md` (líneas 5-13). Ids locales D1-D9; el orquestador les asigna N-id al pasarlos a la tabla.

| Id | Qué | Evidencia SwiftUI | Qué hace AppCore | Tipo | Propuesta |
| --- | --- | --- | --- | --- | --- |
| D1 | Cancelar exportación: SwiftUI vuelve a `idle`, AppCore deja la fase en `cancelled` | AMC:596 (cancelar → `.idle`) | `cancelled`; `dismissExport` vuelve a `idle` (MM:482-483) | Solo de interfaz | Flutter trata `cancelled` como `idle` en la banda; sin cambio de núcleo |
| D2 | `reveal` abre la carpeta `video/`, no selecciona el fichero | AMC:509 `revealInFinder(url)` → `activateFileViewerSelecting` (url del fichero) | MM:517 abre la carpeta | Hueco claro; el efecto en Windows depende de T3 (anfitrión) | `reveal` selecciona el fichero exportado (`explorer /select` en Windows) |
| D3 | Fila «Formato» (HEVC/H.264): SwiftUI siempre la muestra; en Windows solo existe H.264 | MV:447 | `export.options.codecs` solo `h264` en Windows (MM:105) | Solo de interfaz | Mostrar la fila solo si `codecs.count > 1` |
| D4 | Vista previa a 15 fps por píxeles frente a `AVPlayer` | MV:379-402 (`AVPlayerLayer`, `resizeAspect`) | Bucle a `previewFps` (defecto 15, 1...60), salta fotogramas si va atrasado (MC:765-790); el audio WAV manda el reloj (MS:22-34) | Exige decisión de Jorge (vídeo y sincronía) | Decidir el fps por defecto (15/30/60) con la medida de la prueba 3 de P9; tolerancia de sincronía 1 fotograma (spec) |
| D5 | `audioError` sin mostrar | grep `audioError` en `App/Sources/Montage*.swift`: sin resultados | `play` lanza `audio-unavailable` con ese texto (MC:718); `transport.audioError` | Exige decisión de Jorge (comportamiento nuevo) | La Web lo muestra como aviso (WS:114); proponer mostrarlo igual (línea danger bajo la cabecera) |
| D6 | Fotograma de la hoja: PNG por ruta frente a `CGImage` | FS:94 (`Image(decorative:)`) | PNG en `cache/montage/framing-<take>.png` (MC:829-853) | Solo de interfaz (transporte) | `Image.file` con ruta relativa a la carpeta del tema |
| D7 | «Automática ({parte})» y «se ve el automático» se resuelven en la interfaz | MV:289 (`options.first?.partName`) | El snapshot solo trae `singleRhythmCandidates` y `cutCandidates` (ids); `partName` está en `lanes` | Hueco claro | Añadir al snapshot el id de la parte automática; hasta entonces Dart toma el primer candidato (no duplicar más regla) |
| D8 | Texto «Finder» / «Explorador» | MV:185 | No hay texto | Solo de interfaz | Clave ARB por plataforma |
| D9 | M1: `takeFrame` en el Mac | App usa `frameImage` propio (AMC:449-467) | `takeFrame` NO devuelve `nil` en el Mac: rama `canImport(AVFoundation)` con `TakePreview` + `MacMontageComposer.bgra` (MS:73-78); solo el `#else` de MS:80 da `nil` | Resuelto en código (comentario «M1 (parte 3)», MS:72; introducido en `a5f9eb6`) | La fila M1 de `desvios.md` sigue «abierto» y su texto es falso: pasar a `resuelto (a5f9eb6)` cuando Jorge compruebe `framingFrame` con vídeo real en el Mac |

Sin desvío: `mixProgressShare` (0,15) y `previewDebounce` (0,15 s) coinciden en ambos lados; N2 (canal de píxeles por FFI) ya figura en `desvios.md`.
