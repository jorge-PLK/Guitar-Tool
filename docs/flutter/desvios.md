# Fase 7f · Desvíos de núcleo

Un desvío es algo que la app SwiftUI hace y `AppCore` no ofrece, o hace distinto, o que se comporta distinto en Mac y en Windows. La 7c se da por cerrada en funcionalidad (Jorge, 22/11/2026): los desvíos se resuelven aquí.

## Regla (ADR-021, decisión 3)

1. Quien lo encuentra lo reporta con evidencia (`fichero:línea` en SwiftUI y en `AppCore`); `tf-docs` lo añade a la tabla.
2. **Hueco claro** (falta un método, un campo o un evento, y SwiftUI define sin ambigüedad el comportamiento): `tf-implementer` lo arregla en `AppCore` en la misma ola, con su test en `AppCoreTests` y su fixture en `Contract/fixtures/`. No se pregunta.
3. **Exige decisión** (hay que elegir comportamiento, o toca señal, audio, vídeo o sincronía, o cambia el modelo de datos): pregunta a Jorge con alternativas y una recomendada. La pantalla sigue con el resto.
4. **Solo de interfaz** (estado que no necesita persistir ni compartir: selección, plegado, filtro de búsqueda, foco): vive en Dart y no es un desvío de núcleo; se anota para que conste.
5. Nunca se suple en Dart un hueco de núcleo con lógica de negocio.

Estados: `abierto` · `en curso` · `resuelto (commit)` · `pregunta` · `interfaz` · `descartado`.

## Heredados de la 7c

Estado a comprobar al empezar la ola 0 contra `docs/plan/fase-7c.md` («Condición de cierre de la 7c») y `Temp/win/appcore-gap-audit.md`; el commit `894319e` cerró parte.

| Id | Qué | Ola | Tipo | Estado |
| --- | --- | --- | --- | --- |
| B1 | Separador de guitarras en Windows (`guitarSplitter`) | 2 | núcleo | a comprobar |
| B2 | Cambio de carpeta de proyectos en caliente (`Library.relocate`) | 1 | núcleo | a comprobar |
| B3 | Primer arranque: proponer y crear `~/Music/ToneForge` | 1 | núcleo | resuelto (83f61a5): `app.info.proposedProjectsFolder` por plataforma; falta comprobar `URL.path` en Windows |
| B4 | Fotos de artista por `AppCore` | 1 | núcleo | a comprobar |
| B6 | Cierre ordenado (`terminateAll`, `flush`) | 0 | núcleo | a comprobar |
| A1 | Cámaras en Ajustes del Mac por `AppCore` (`resolvedCameras`) | 3 | núcleo | abierto |
| M1 | Hoja «Encuadre» en el Mac (`takeFrame` tenía `nil`; `MontageServices.swift:73-78` ya tiene rama Mac) | 4 | núcleo, vídeo | resuelto en código (`a5f9eb6`); pendiente de que Jorge compruebe `framingFrame` con vídeo real en el Mac |
| R3, M2 | Rendimiento de cámara y vista previa en el Mac | P9 | medida | lo sustituye la prueba 3 de P9 (píxeles crudos) |
| T3 | Guardar fichero y abrir URL desde el anfitrión | 0 | anfitrión Flutter | resuelto en código (b5f880d): `saveFile` y `openURL` por `hostRequest`; falta el lado Dart (F1) |
| S4 | Modelos embebidos en `Bundle.main` | 5 | empaquetado | abierto |
| — | Audio y cámara reales del Mac por el puente de `AppCore` | 3 | hardware (Jorge) | abierto |

## Nuevos de la 7f

Vienen del apartado 9 de las fichas de `pantallas/`. La clase sigue [decisiones-interfaz.md](decisiones-interfaz.md), que manda sobre las fichas. Prefijos: L Biblioteca, K Backing, TB Tablatura, GR Grabar, MO Montaje, AJ Ajustes (T, R, S, N y M ya los usan los heredados y N1/N2). Ola: 1 Biblioteca y Ajustes·Biblioteca; 2 Backing y Tablatura; 3 Grabar, visor y Ajustes·Audio/Vídeo; 4 Montaje. Todos en estado `abierto` salvo que se indique. «Ficha» remite al apartado 9 (`b` = `biblioteca-contrato.md`, `k` = `backing-contrato.md`, `t` = `tablatura-contrato.md`, `g` = `grabar-contrato.md`, `m` = `montaje-contrato.md`, `a` = `ajustes.md`).

| Id | Pantalla | Qué | Clase | Ola | Ficha |
| --- | --- | --- | --- | --- | --- |
| N1 | Todas | Textos de error y avisos del núcleo en español: pasar a `{code, message, args}` (`mensajes-nucleo.md`) | hueco claro (decidido, ADR-021, 16) | 1 | ADR-021 |
| N2 | Grabar, Ajustes, Montaje | Canal de píxeles BGRA por FFI en lugar de `frames.*` en JPEG | hueco claro (decidido, ADR-021, 8) | 3 | ADR-021 |
| L1 | Biblioteca | Marcar la mejor toma desde la lista: `record.markBest` exige sesión de Grabar; falta `library.markBest` que avise a Grabar/estudio si el tema está abierto | hueco claro, resuelto (71a46fa) | 1 | b:1 |
| L2 | Biblioteca | Borrar un tema abierto en estudio: `library.trash`/`delete` deben cerrar la sesión y soltar ficheros (en Windows, bloqueo NTFS sin confirmar; lo prueba Jorge) | hueco claro, resuelto (71a46fa); falta comprobar en Windows | 1 | b:2 |
| L3 | Biblioteca | `ProjectSummary` sin `separationError`; falta el campo para el texto del fallo en la lista | hueco claro, resuelto (71a46fa) | 1 | b:3 |
| L6 | Biblioteca | Selección de tema (`backingTarget`): se limpia al borrar y si el id desaparece de `library.list` | interfaz en Dart | 1 | b:6 |
| L7 | Biblioteca | Búsqueda, agrupación por artista y plegado; agrupación en preferencias locales; paridad de plegado y orden con `LibraryGrouping` | interfaz en Dart | 1 | b:7 |
| L11 | Biblioteca | Carátulas y fotos: se leen por ruta de fichero (`Image.file`), no por `mediaBase` (antes «decisión de Jorge») | interfaz en Dart (resuelto) | 1 | b:11 |
| L12 | Biblioteca | Importar: filtrar `wav`/`flac`/`mp3` antes de llamar a `import.file` | interfaz en Dart | 1 | b:12 |
| K2 | Backing | Imán de bordes de sección a acorde y ⌥ a compás: hecho, ola 2. `study.previewSectionEdge {id,start,to,snap?: none\|chord\|bar}` calcula en el núcleo; `study.updateSection` con `snap` usa la regla `SectionEdgeDrag` | hueco claro (resuelto) | 2 | k:D-2 |
| K3 | Backing | Bucle por arrastre con ajuste a acorde o compás: hecho, ola 2. `study.setLoop {start,end,name?,snap?}` ajusta en el núcleo; Flutter manda `name` desde ARB | hueco claro (resuelto) | 2 | k:D-3 |
| K4 | Backing | Monitores de teclado (Espacio, Supr, Esc, ⌥) | interfaz en Dart | 2 | k:D-4 |
| K7 | Backing | Formas de acorde con capo: hecho, ola 2. `study.chordShape {index,capo?}` → `{index,display,capo,shape{frets,baseFret,barre?}}` | hueco claro (resuelto) | 2 | k:D-7 |
| K8 | Backing | Nombre transpuesto y tonalidad mostrada: hecho, ola 2. `analysis.chords[].display/shape`, `analysis.key.display {tonic,mode}`; `study.setKey {shown:{tonic,mode}}` (el núcleo destranspone); `study.analysis` se reemite tras `setTranspose`, `setCapo` y `setKey` | hueco claro (resuelto) | 2 | k:D-8 |
| K9 | Backing | «Sin guitarras» como N `study.setMix`; solo si `kind == "guitar"` | interfaz en Dart | 2 | k:D-9 |
| K12 | Backing | `study.error` eliminado, hecho en la ola 2: los errores van por respuesta | hueco claro (resuelto) | 2 | k:D-12 |
| TB1 | Tablatura | Errores de alphaTab (`webError`): aviso de la pantalla con mensaje genérico y detalle | interfaz en Dart | 2 | t:D1 |
| TB2 | Tablatura | Rehacer: Ctrl+Y además de Ctrl+⇧+Z en Windows; ⇧⌘Z en Mac | interfaz en Dart | 2 | t:D2 |
| TB3 | Tablatura | Cursor: `study.position` (30 Hz) interpolado en un `Ticker`; sin temporizador propio | interfaz en Dart | 2 | t:D3 |
| TB4 | Tablatura | Teclas por tecla lógica y carácter (teclados no US); lo prueba Jorge | interfaz en Dart | 2 | t:D4 |
| TB5 | Tablatura | Etiqueta «Fuente» por clave ARB | interfaz en Dart | 2 | t:D5 |
| TB6 | Tablatura | Exportar `.gp`: Dart abre el diálogo (`file_selector`) y pasa `path` a `tab.export` (antes «decisión de Jorge») | interfaz en Dart (resuelto) | 2 | t:D6 |
| TB7 | Tablatura | Songsterr oculto: sondeo, tope y serialización de cargas los ejecuta el anfitrión; comprobar que el de Flutter cumple los puntos 1-6 del contrato | se mide (requisito de anfitrión) | 2 | t:D7 |
| TB9 | Tablatura | Eventos del lienzo reenviados a `tab.*` con coalescencia en cliente | interfaz en Dart | 2 | t:D9 |
| TB10 | Tablatura | Hecho, ola 2: `tab.open`, `tab.songsterr.accept`, `tab.songsterr.automatic` y `tab.songsterr.setSource` arrancan o reabren la cola de transcripción en el núcleo | hueco claro (resuelto) | 2 | t:D10 |
| TB11 | Tablatura | La hoja de Songsterr se cierra en el cliente tras `accept` y `automatic` | interfaz en Dart | 2 | t:D11 |
| K-SL | Backing | Marca del bucle del tramo: `StudyLoop.span` (bool) en el snapshot; hecho, ola 2 | hueco claro (resuelto) | 2 | k |
| K-TB | Tablatura | `hasNote` en la selección de tablatura y piezas de batería `kick`/`snare`/`hiHat`/`openHiHat`/`tom`/`crash`; hecho, ola 2 | hueco claro (resuelto) | 2 | t |
| K-TAB | Tablatura | `tab.dismissNotices {}` (Dart ya no oculta avisos por texto) y `tab.span {action:clear, keepAnchor:true}`; fixtures Songsterr `working`, `failed` y `searchFailed`; hecho, ola 2 | hueco claro (resuelto) | 2 | t |
| K-CH | Backing | `study.chordVocabulary` (raíces y calidades mostradas, transpuestas), `analysis.chords[].shown`; `study.setChord` acepta `shown:{root,quality}` y destranspone; hecho, ola 2 | hueco claro (resuelto) | 2 | k |
| K-TS | Tablatura | Cabecera y resumen de selección por código: `header {code: meterBpm\|meter, bar, bpm}`, `selection.summary {code: note\|noNote\|drums\|drumsNoHits, bar, beat, string, fret, pieces[]}`; hecho, ola 2 | hueco claro (resuelto) | 2 | t |
| K-KEY | Tablatura | `tab.keyMap {}` → `rules[{key, shift?, ctrl, alt, when: span\|edit\|editDrums\|editNotDrums}]`, la misma tabla que usa `handleKey` en `AppCore`, con test que recorre el mapa y fixtures `tab.keyMap.*`. Flutter debe reclamar teclas de forma síncrona y `tab.key` es asíncrono; antes Dart duplicaba la lista (`tabKeyMapProvider` cacheado, `tab_shortcuts` consulta el mapa); hecho, ola 2 | hueco claro (resuelto) | 2 | t (804ecf1, 8a16efa) |
| K-BT | Tablatura | `tab.score` expone `timing {beats, beatsPerBar, end}` (tiempos de pulso de la partitura). El cursor se colocaba lineal por compás (`TabGrid.swift`, SwiftUI igual) y se desfasaba con pulsos no uniformes. Dart: `TabTiming`, `tab_timing_map.dart` (segundo → `{bar, fraction}`) y `setCursor(bar, fraction)` en el controlador; hecho, ola 2 | hueco claro (resuelto) | 2 | t (7faff28, 7e66155) |
| GR1 | Grabar | `record.setPunch {enabled:true}` debe elegir la mejor toma si no hay toma elegida | hueco claro | 3 | g:G1 |
| GR2 | Grabar | Nivel de guitarra: Dart lo lee de `audio.levels` y llama a `audio.setMeters` al entrar y salir | interfaz en Dart | 3 | g:G2 |
| GR5 | Grabar, visor | Reproductor de vídeo de Flutter en Windows: HEVC y `playbackRate` fino; mensaje de HEVC en Dart | se mide (P9) | 3 | g:G5 |
| GR6 | Grabar | Imán de ±1,5 dB del Master en la vista | interfaz en Dart | 3 | g:G6 |
| GR7 | Visor | Sincronía vídeo-audio sin reloj común; el seguidor en Dart ya no es el plan (decisión 9 enmendada) | se mide (P9) | 3 | g:G7 |
| GR10 | Grabar | `record.pollCamera` aditivo en `AppCore` (`RecordMethods.swift:363`); SwiftUI sondea la cámara cada 2 s en reposo (`RecordController.swift:483`). La interfaz sondea siempre en reposo (`opened && phase == idle`), 1:1 con SwiftUI; el núcleo decide por estado. Decisión de Jorge, 25/11/2026 | núcleo (resuelto) | 3 | `RecordController.swift:483` |
| GR8 | Visor | Audio del visor en el Mac: SwiftUI usa la salida del sistema, `AppCore` la del perfil. Resuelto por robustez: la del perfil en las dos plataformas (un solo camino de audio); Jorge lo comprueba de oído | interfaz en Dart (resuelto) | 3 | g:G8 |
| MO1 | Montaje | Cancelar la exportación: `cancelled` se trata como reposo | interfaz en Dart | 4 | m:D1 |
| MO2 | Montaje | `reveal` debe seleccionar el fichero exportado, no abrir la carpeta (depende de T3 en Windows) | hueco claro | 4 | m:D2 |
| MO3 | Montaje | Fila «Formato» solo si `export.options.codecs.count > 1` | interfaz en Dart | 4 | m:D3 |
| MO4 | Montaje | Vista previa por píxeles: fps por defecto y sincronía (el canal `montage` ya va a 60 fps) | se mide (P9, prueba 3) | 4 | m:D4 |
| MO5 | Montaje | `audioError` sin mostrar en SwiftUI y sí en la web. Resuelto por fiabilidad: se muestra como aviso bajo la cabecera | interfaz en Dart (resuelto) | 4 | m:D5 |
| MO6 | Montaje | Fotograma de encuadre: `Image.file` con ruta relativa al tema | interfaz en Dart | 4 | m:D6 |
| MO7 | Montaje | «Automática ({parte})»: el snapshot debe traer el id de la parte automática | hueco claro | 4 | m:D7 |
| MO8 | Montaje | «Finder» / «Explorador»: texto por plataforma en ARB | interfaz en Dart | 4 | m:D8 |
| AJ1 | Ajustes · Vídeo | Cámaras reales del Mac por `AppCore` (`video.cameras` vacío): es A1 | hueco claro | 3 | a:1, A1 |
| AJ2 | Ajustes · Biblioteca | Cambio de carpeta en caliente: `host.chooseFolder` + `library.relocate`, no `host.pickProjectsFolder`; tras mover se queda en Ajustes; es B2 | hueco claro | 1 | a:2, B2 |
| AJ3 | Ajustes · Audio | Cancelar calibración: sin botón; cerrar la hoja con la medida en marcha envía `audio.cancelCalibration` (antes «decisión de Jorge») | interfaz en Dart (resuelto) | 3 | a:3 |
| AJ4 | Ajustes · Audio | Textos del núcleo en español y coma decimal: es N1 (por código y argumentos) | hueco claro (decidido) | 1 | a:4, N1 |
| AJ5 | Ajustes · Vídeo | Previa rotada por Flutter (horario); sin selector de giro en Ajustes | interfaz en Dart | 3 | a:5 |
| AJ6 | Ajustes · Vídeo | Selector de códec oculto si `codecs.length == 1` (Windows) | interfaz en Dart | 3 | a:6 |
| AJ8 | Ajustes · Audio | Tarjeta de salida de la barra lateral deducida de `audio.settings` y `audio.devices` (la implementa la carcasa) | interfaz en Dart | 3 | a:8 |
| FC1 | Grabar, Montaje | `FrameChannel` no da el tamaño del fotograma ni avisa del cambio de `textureId`; `TfVideoSurface` recibe `frameSize` por parámetro | hueco claro | 3, 4 | resolver en Grabar B (ola 3) y Montaje P2 (ola 4) |
| AJ9 | Ajustes · Vídeo | Texto del botón de permisos de cámara en Windows: variante por plataforma en ARB (por analogía con «Finder»/«Explorador»; no lo cita `decisiones-interfaz.md`) | interfaz en Dart | 3 | a:9 |

Abiertos al cerrar la ola 1, para la ola 5 (mensajes del núcleo por código):

| Id | Pantalla | Qué | Clase | Ola | Ficha |
| --- | --- | --- | --- | --- | --- |
| L14 | Biblioteca, importación | `AppCore` no emite `args` en ningún `RPCError`. Dart lee `version`, `name`, `status` y `retryAfter` de `args` (nombres supuestos de `SourceError` y `SpotifySearchError`) y, si faltan, cae a una expresión regular sobre `message`. `LinkFailure` (contrato) no lee `args` | hueco claro (N1) | 5 | N1 |
| L15 | Biblioteca, importación | El aviso genérico de importación sale sin título (`ImportNotice` sin `title`) y las filas fallidas de una lista muestran `error.title` y `error.detail` del núcleo sin traducir por `code` | hueco claro (N1) | 5 | N1 |
| L16 | Biblioteca | Portada de fila: Flutter usa `ProjectSummary.cover`; SwiftUI mira siempre `<carpeta>/source/cover.jpg` (`LibraryView.swift:412-415`). Puede diferir si `cover` falta y el fichero existe | se mide (ola 5) | 5 | b:40 |

Pendiente (menor, sin hacer):

- El user agent de Songsterr está duplicado en Dart (`songsterrPreviewUserAgent`); podría exponerlo el núcleo.
- Avisos, flash y `tab.error` por código (ola 5).

Descartados (sin trabajo, constan por si se vuelve a preguntar):

- L4 · `videoCount` solo en `library.project`: Dart la llama al abrir el diálogo de eliminar (`b:4`).
- L5 · Foto de artista como `data:` hasta 2 MB: se mantiene (`b:5`).
- L8 · Duplicados: la alerta del Mac sirve para ficheros y enlaces (`b:8`).
- L9 · Textos de error de enlace y lista: los pone el núcleo (`b:9`).
- L10 · Indicador de lista en la cabecera: ya en `PlaylistSnapshot.indicator` (`b:10`).
- L13 · Cancelar enlace con `link.cancel`/`playlist.cancel`, no `jobs.cancel` (`b:13`).
- K1 · A/B de tomas: código muerto, no se porta (`k:D-1`).
- K5 · `gainDB` del metrónomo: sin interfaz (`k:D-5`).
- K6 · Bucles guardados (`study.open.loops`): sin interfaz (`k:D-6`).
- K10 · Edición de secciones en dos tiempos: ya cubierta por el puente (`k:D-10`).
- K11 · `study.setChord` con `label`: sin impacto (`k:D-11`).
- TB8 · El lienzo no usa SoundFont: no cargarlo en el WebView (`t:D8`).
- TB12 · Métodos sin uso en Windows: informativo (`t:D12`).
- GR3 · `calibrationValid` sale de `audio.*`: nada que añadir (`g:G3`).
- GR4 · Selector de cámara en Grabar: no se añade, la cámara se elige en Ajustes (`g:G4`).
- GR9 · `record.cancel` sin llamadas: no se implementa (`g:G9`).
- AJ7 · Guardado del perfil repartido entre `audio.setSettings` y `video.setSettings`: informativo (`a:7`).
- AJ10 · «Verificando/Instalando» no viene en `models.progress`: informativo (`a:10`).

Montaje D9 (M1) no se repite: ver la fila M1 de los heredados.

## Cierre de la ola 3 (Grabar, visor y Ajustes · Audio/Vídeo)

| Id | Qué | Estado |
| --- | --- | --- |
| GR11 | Motivo de bloqueo por código: `record.state.block` y `audio.*.calibrateBlock` (campo `calibrateBlockMessage`) llevan `CoreMessage {code, message, args}` aditivo junto al texto (commit `4d07d46`; cliente en `core_message.dart`). No existe `audio.recordBlock`: el bloqueo llega solo por `record.state.block` y `calibrateBlock` | resuelto (`4d07d46`) |
| N1b | Textos del núcleo en español que quedan para la ola 5 (decisión de Jorge, 25/11/2026): filas del resultado de calibración (`success.rows`); los 5 errores de Grabar y Ajustes que se muestran con `error.message`; `AudioMethods.swift` 177-181, 367, 370, 376-379 y 409-416; `CameraPreview` 59, 153 y 172. `video.preview.start.failed` mete `\(error)` en `message` | abierto (ola 5) |
| GR12 | Un solo códec de vídeo: no se puede fixturear en Mac (el selector oculto de AJ6 solo se prueba con datos de test) | informativo |
| FC1b | `contrato-tipos-c.md` no recogía `takeview.video` ni los campos FC1 `videoWidth`, `videoHeight` y `videoRotation` de `TakeViewSnapshot` | resuelto (contrato actualizado) |
| GR13 | Artista: Grabar lo toma de `library.list`, porque el snapshot de `record` no lo trae. `snapshot.projectId` no se compara con el proyecto pedido (el fixture trae `…0004`) | interfaz en Dart |
| GR14 | `frameChannelProvider(FrameChannelId.x)` es una family en `core` (`123c855` y `6e5ace4` en `fase-7f`); con `--mock` devuelve `null` y no hay fotograma | interfaz en Dart |
| GR15 | El visor de toma pinta con `rotation: 0` aunque `takeview` trae `videoRotation` 90. Falta confirmar si el fotograma ya llega rotado del núcleo | pregunta abierta: se verifica con hardware en la prueba de Jorge |
| GR16 | Fotograma del visor en pausa. Las tomas cuya composición empieza con una edición vacía (p. ej. 0,0198 s) no daban buffer en t=0, así que se veía negro hasta play. En pausa, seek y poll a `firstImageTime` (`TakeVideoPlayer.swift`, b405d64). Además `tf_texture_create` señala el fotograma que ya tiene el canal (70e27bb), porque Dart crea la textura tras `takeview.open`. Nota: trazas `TF_TRACE_TAKE=1` (`AppCore/TakeTrace.swift`), apagadas por defecto | resuelto en AppCore con test (`TakeViewFrameFlowTests`) |
| GR17 | Arrastre del timeline del visor, petición de Jorge (26/11/2026). Comportamiento nuevo frente a SwiftUI, que hace un seek exacto por cada cambio sin coalescer (`TakeViewer.swift:343`). En Flutter, throttle de 80 ms durante el gesto y seek final exacto (`take_viewer_scrub.dart`, 3d0492d). En el núcleo, los seeks en pausa se coalescen con «el último gana» sin cancelar el que está en vuelo (400573f), unos 6 ms por seek exacto en 1920 HEVC | resuelto, comportamiento nuevo aprobado por Jorge |
| GR18 | Carrera en `VideoConversionEngine.wait(takeId:)` durante el swap del vídeo convertido (`settling[takeId]`, be1ea09). Intermitente de `VideoConversionTests:420`, no reproducido tras el arreglo | resuelto (sin confirmar por reproducción) |
| GR19 | El enlace de la Biblioteca `openTakeViewer` (ola 1) abre ya el visor de la ola 3 con `TakeViewerHost`: título «Toma N · parte», mejor y borrar por `library.markBest`/`library.deleteTake`, 1:1 con `ProjectRecordingsView.swift:92-109` (c24e68d) | interfaz en Dart |

## Notas de plataforma

Anfitrión de la 7f en macOS; no son desvíos de núcleo.

- **Snap de rejilla y tira (ola 2):** solo mandan `none`, `chord` o `bar`; el núcleo rechaza `beat` con `bad-params`. La rejilla sin ⌥ ajusta a acorde y con ⌥ a compás, como SwiftUI (f60c6df, 0cf1ad9). `MockCore` acepta parámetros inválidos: los tests de widgets no validan el contrato.
- **Impeller desactivado en macOS** (`FLTEnableImpeller=false`, 7367f34, ffe5b26) hasta que salga el arreglo del crash SIGSEGV en `io.flutter.raster`, `impeller::Canvas::SetupRenderPass` desde `EmbedderExternalViewEmbedder` con platform views (Flutter 3.44.5). Revisar al subir Flutter.
- **`DropTarget` de `desktop_drop`:** `MainFlutterWindow` lo oculta durante los eventos de ratón; su `NSView` tapaba la ventana en `hitTest` y el `WKWebView` no recibía clics (de896fc, 6f23a00).
- **Nada pintado por Flutter encima de un platform view** (bordes de `TfCard` en primer plano, `ClipRRect`): `FlutterMutatorView` mete ese rect en `_hitTestIgnoreRegion` y macOS no entrega el ratón al WebView. Regla: bordes de fondo (`DecoratedBox`) alrededor de los WebViews (529c803, 665ebf9).
- **Teclas dentro del WebView de la partitura:** se reenvían a los atajos con un shim `keydown` (e5611f0, 41b17d2).
- **`tab.html` con `html{overflow-y:scroll}`:** si la barra vertical aparece tras el primer render, el ancho baja y alphaTab vuelve a renderizar encima sin limpiar (partitura doble al arrancar directo en Tablatura) (5ff9ecd).
