# Grabar y «Ver toma» · apartados 5 y 9 de la ficha (borrador)

Destino previsto: `docs/flutter/pantallas/grabar-contrato.md` (copiar tal cual). Rutas: `AC/` = `Packages/AppCore/Sources/AppCore/`, `W/` = `WinApp/Web/`, `VK/` = `Packages/VideoKit/Sources/VideoKit/`. Los tipos completos (params, `RecordSnapshot`, eventos, códigos de error) están en `docs/flutter/contrato-tipos-c.md` (secciones `record` y `takeview`) y en `contrato-tipos-a.md` (`audio`, `frames`); aquí solo se referencian por nombre y con la línea Swift entre paréntesis; la definición está en `contrato-tipos-c.md` y `contrato-tipos-a.md`.

## 5. Contrato que usa

Nota previa: todo `record.*` salvo `open`/`close` devuelve `RecordSnapshot` completo y lo mismo emite `record.state`. `W/record/store.js:93-103` (`act`) aplica la respuesta y muestra el error como aviso salvo `not-open`. Los eventos se registran una sola vez al cargar el módulo (`store.js:84-111`) y se ignoran si la pantalla no está `ready`.

### 5.1 Orden de llamadas por momento

| Momento | Orden | Fuente |
| --- | --- | --- |
| Entrar | 1 `study.open {projectId}` (tema de Backing; ver `backing-contrato.md`). 2 `record.open {projectId}` -> `RecordSnapshot`. 3 en paralelo `audio.settings` y `audio.setMeters {visible:true}` (para `guitarIn` y `calibrationValid`). 4 al pintarse la vista previa con `camera.state` `live` o `simulated`, se engancha `frames.camera`. | `store.js:47,50,54,80`; `preview.js:23` (`attachFrames`, canal `camera`) |
| Grabar | `record.start` -> fases `counting` -> `recording` (llegan por `record.state`); `record.position` y `record.levels` a 30 Hz; `audio.levels` a 30 Hz para el medidor de entrada. | `bar.js:62`; `store.js:105-111` |
| Parar | `record.stop` -> `finishing` -> `idle` por `record.state`; la toma nueva aparece en `parts[].takes`. | `bar.js:62` |
| Punch | 1 si no hay toma elegida y la parte tiene mejor: `record.selectTake {takeId: bestTakeId}`. 2 `record.setPunch {enabled}`. 3 puntos: `record.setPunch {in\|out, free: altKey}` al arrastrar. 4 `record.startPunch {takeId}` (menú de la toma), luego `record.stop`. | `bar.js:57-58`; `punch.js:41`; `parts.js:57` |
| Ver toma | 1 `record.prepareViewTake` -> `{allowed}` (si `false` no se abre). 2 `takeview.open {projectId, takeId}`; se escucha `takeview.position` antes de la respuesta y se guarda el primero. 3 `takeview.play`/`pause`/`seek {seconds}`/`setBacking {on}`. 4 al cerrar `takeview.close`. | `store.js:143-147`; `W/screens/record.js:75-77`; `W/record/take-screen.js:21-49` |
| Borrar desde el visor | primero cierra el visor (`takeview.close`) y después `record.deleteTake` (en NTFS no se borra un fichero abierto). | `W/screens/record.js:56-62` |
| Ajustar desfase | `record.adjustOffset {takeId}` -> `snapshot.offset` abre la hoja; `takeview.openOffset`; `record.setOffset {valueMs}` en cada cambio; `record.finishOffset {save, makeDefault}`; `takeview.close`. | `parts.js:56`; `offset-sheet.js:35,75,82,50` |
| Salir | `audio.setMeters {visible:false}`, `record.close`, y `study.close` salvo rumbo a Montaje. | `store.js:64-75`; `W/screens/record.js:109` |

### 5.2 Tabla de contrato

| Acción o momento | Método / evento | DTO (definición en `contrato-tipos-c.md` §record/§takeview y `contrato-tipos-a.md` §audio/§frames; Swift entre paréntesis) | Cómo lo usa `WinApp/Web` |
| --- | --- | --- | --- |
| Abrir Grabar | `record.open` | `RecordOpenParams` y `RecordSnapshot`: `contrato-tipos-c.md` §record «DTO» (`AC/RecordMethods.swift:196`, :147; register :262, impl. :431) | `store.js:50` |
| Cerrar Grabar | `record.close` | `Empty` -> `Empty` (:263) | `store.js:72` |
| Leer estado | `record.state` (método y evento) | `RecordSnapshot` :147; evento emitido en :531, no periódico | método sin uso en la web; evento `store.js:105` |
| Posición | `record.position` (evento) | `RecordPositionEvent {seconds, playing, phase}` :186 (`contrato-tipos-c.md` §record «Payload de eventos»); emit :573; 30 Hz, mín. 30 ms (`AC/StudyMethods.swift:11,13`) | `store.js:106-110` (fuera de la señal, avisa a suscriptores) |
| Niveles de canal | `record.levels` (evento) | `RecordLevelsEvent` y `StudyMeter {rmsDB, peakDB}` en dBFS, -120 = silencio: `contrato-tipos-c.md` §record «Payload de eventos» (`AC/RecordMethods.swift:192`; `AC/StudyMethods.swift:149`); emit :581 | `store.js:111` |
| Iniciar toma | `record.start` | `Empty` -> `RecordSnapshot` (:265); errores `busy`, `record-blocked` | `store.js:113`, `bar.js:62` |
| Parar | `record.stop` | (:272) | `store.js:114` |
| Cancelar | `record.cancel` | (:273) | exportado en `store.js:115`; ninguna pantalla lo llama; SwiftUI tampoco lo llama desde la vista (`App/Sources/RecordView.swift`) |
| Elegir parte | `record.selectPart` | `RecordPartParams {partId}` :197 | `store.js:116`, `parts.js:35` |
| Añadir parte | `record.addPart` | `RecordAddPartParams {name, replaces?}` :198 | `store.js:117`, `parts.js:76` |
| Sección de inicio | `record.setStartSection` | `RecordSectionParams {sectionId?}` :199 | `store.js:118`, `bar.js:72` (envía `null` explícito; `JSONDecoder` lo trata como ausente) |
| Cuenta atrás | `record.setCountIn` | `RecordOnParams {on}` :200 | `store.js:119`, `bar.js:76` |
| Margen previo | `record.setPreRoll` | `RecordBarsParams {bars 0...2}` :201 | `store.js:120`, `bar.js:78` |
| Configurar punch | `record.setPunch` | `RecordPunchParams {enabled?, in?, out?, clearIn?, clearOut?, free?}` :203-211 (claves JSON `in`/`out`); solo en `idle` (:312) | `store.js:121`, `bar.js:58`, `punch.js:41` |
| Grabar punch | `record.startPunch` | `RecordTakeParams {takeId}` :202 | `store.js:122`, `parts.js:57` |
| Elegir toma | `record.selectTake` | `RecordTakeParams` (sin `takeId` = deselecciona) | `store.js:123`, `parts.js:21`, `bar.js:57` |
| Mejor toma | `record.markBest` | `RecordTakeParams` | `store.js:124`, `parts.js:55`, `W/screens/record.js:97` |
| Borrar toma | `record.deleteTake` | `RecordTakeParams` (impl. :372) | `store.js:125`, `parts.js:68` |
| Cámara | `record.setCamera` | `RecordCameraParams {cameraId?}` :212 | exportado `store.js:126`; ninguna pantalla lo llama (ver desvío G4) |
| Girar cámara | `record.rotate` | `Empty` | `store.js:127`, `preview.js` (botón «Rotar», solo en `idle`) |
| Hoja de desfase | `record.adjustOffset`, `record.setOffset`, `record.finishOffset` | `RecordTakeParams`; `RecordOffsetParams {valueMs?, deltaMs?, frames?}` :213; `RecordFinishOffsetParams {save, makeDefault?}` :214; rango ±500 ms, se recorta (`contrato-tipos-c.md` §record «Params»; `AC/RecordController.swift:195`) | `store.js:128-130`; `offset-sheet.js:75,82` |
| Mezcla | `record.setMix`, `record.setMaster` | `RecordMixParams {channel, gainDB?, mute?, solo?}` :215; `StudyMasterParams {gainDB}` `AC/StudyMethods.swift:170` (dB; `contrato-tipos-c.md` §record «Params») | `store.js:131-140` (con actualización optimista), `mixer.js:32-37,83` |
| Paso a Ver toma | `record.prepareViewTake` | `Empty` -> `RecordAllowedResult` :216 (impl. :384; solo pausa el reproductor si la fase es `idle`, `RecordController.swift:1041-1045`) | `store.js:143-147` |
| Abrir toma | `takeview.open` | `TakeViewOpenParams` -> `TakeViewSnapshot`: `contrato-tipos-c.md` §takeview «DTO» (`AC/TakeViewMethods.swift:82`, :86; register :258). `TakeViewSnapshot.audioError` (opcional) se muestra como aviso (ver `montaje-contrato.md` D5) | `take-screen.js:27` |
| Abrir toma de la hoja de desfase | `takeview.openOffset` | `Empty` -> `TakeViewSnapshot` (:259) | `offset-sheet.js:35` |
| Transporte | `takeview.play`, `pause`, `seek` | `TakeViewSeekParams {seconds}` :83 | `take-screen.js:47-48`; la hoja usa `seek {seconds:0}` para «volver» (`offset-sheet.js:57`) |
| Backing del visor | `takeview.setBacking` | `TakeViewBackingParams {on}` :84 | `take-screen.js:49` |
| Cerrar visor | `takeview.close` | `Empty` | `take-screen.js:42`, `offset-sheet.js:50` |
| Posición del visor | `takeview.position` (evento) | `TakeViewPositionEvent {seconds, playing, rate, at, epoch}` :105 (todos obligatorios; `contrato-tipos-c.md` §takeview; `seconds` y `at` en s, `at` = reloj de host); emit :500 | `take-screen.js:22-26` -> `CoreTakeSync.push` (`take-sync.js:153`) |
| Fotogramas de cámara | `frames.camera` (evento) | `FrameEvent {seq, width, height, ptsMs, jpeg}`: `contrato-tipos-a.md` §frames «DTO»; `jpeg` = base64 estándar sin prefijo `data:`; `ptsMs` en ms (`AC/FrameRelay.swift:6`) | `W/frames.js:33-60` (`attachFrames`: descarta `seq` menor o igual salvo `seq == 1`, decodifica el JPEG y pinta en un canvas) |
| Estadísticas del relevo | `frames.stats {channel}` | `contrato-tipos-a.md` §frames «DTO»: `FrameStatsParams` -> `FrameRelayStats` (`AC/FrameRelay.swift:271`, :16) | sin uso en Grabar |
| Calibración y entrada de guitarra | `audio.setMeters`, `audio.settings`, `audio.state` (evento), `audio.levels` (evento) | `AudioStateResult` (`calibrationValid`), `AudioSettingsResult.guitarIn` (ausente = sin asignar; índices de canal desde 1) y `AudioLevelsEvent {levels 0...1, rmsDB, peakDB en dBFS, un elemento por canal de entrada}`: `contrato-tipos-a.md` §audio «DTO» (`AC/AudioMethods.swift:85`, :68, :137) | `store.js:80-90` |

### 5.3 Sincronía de vídeo hoy

**Reloj que manda.** En «Ver toma» y en la hoja de desfase, el núcleo reproduce el audio procesado (`processed.wav`, tiempo 0 = inicio de la toma) y el backing por `StudyAudio` con la salida del perfil (`TakeViewSnapshot.outputName`). El `<video>` va sin sonido (`take-sync.js:142`) y sigue al reloj del núcleo. El vídeo nunca manda.

**Forma y cadencia de `takeview.position`** (`AC/TakeViewMethods.swift:105`, publicación :487-503):

- Campos: `seconds` (s de la toma que suena en `at`, alisado), `playing`, `rate` (1 = avanza, 0 = quieto o esperando la primera muestra), `at` (reloj de host del núcleo en s: QPC en Windows, `mach_absolute_time` en el Mac), `epoch` (sube en cada discontinuidad: play, pausa, seek, final).- Cadencia: ticker de 30 Hz (`TakeViewConstants.positionHz = 30`, :17). Sonando, un evento por tick. En pausa, solo si cambia `seconds` o `epoch` (el `at` no cuenta, :498). Más un evento forzado en cada discontinuidad (open, play, pause, seek, fin).

**`TakeViewClock` del núcleo** (`TakeViewMethods.swift:45-77`): lazo de fase de primer orden contra el reloj de host.

| Constante | Valor | Línea | Efecto |
| --- | --- | --- | --- |
| `gain` | 0,1 por muestra | :49 | a 30 Hz, constante de tiempo ~0,33 s; el temblor de un bloque se reduce ×0,23 |
| `resyncThreshold` | 0,030 s | :47 | un residuo mayor es discontinuidad (hueco del dispositivo): se reancla a la lectura cruda |
| Arranque | `rate: 0` hasta que `rawPosition` se mueve | :57-62 | `reset()` en play, pausa y seek |

**`VideoFollower` y `CoreClock` de la web** (`W/record/take-sync.js`):

| Constante | Valor | Línea | Efecto |
| --- | --- | --- | --- |
| `CLOCK.SKEW_WINDOW_S` | 5 s | :42 | ventana del filtro de mínimos de `now - at` (desfase entre relojes + retraso de entrega); posición = `seconds + rate · (now - skew - at)` (:60-64) |
| `FOLLOW.DEADBAND_S` | 0,003 s | :70 | zona muerta: velocidad 1 |
| `FOLLOW.HARD_S` | 0,25 s | :71 | por encima, salto duro |
| `FOLLOW.JUMP_SEEK_S` | 0,05 s | :72 | tras una discontinuidad (`epoch` nuevo o `recheck`), salto si la deriva pasa de esto |
| `FOLLOW.GAIN_PER_S` | 3 por s | :73 | `rate = 1 - deriva · 3` (constante de tiempo 0,33 s) |
| `FOLLOW.MAX_RATE_DEV` | 0,25 | :74 | velocidad entre 0,75 y 1,25 |
| `FOLLOW.RATE_STEP` | 0,005 | :75 | cambios menores no se aplican (salvo volver a 1) |
| `FOLLOW.LEAD_MAX_S` | 0,3 s | :76 | adelanto máximo de un salto (se mide con el evento `seeked`) |
| `FOLLOW.LEAD_EMA` | 0,5 | :77 | peso de la última medida del adelanto |
| En pausa | seek si `|deriva| > 0,001 s` | :95 | además pausa el `<video>` y velocidad 1 |

Cadencia del seguidor: un paso por `requestAnimationFrame` (:148-149), no por evento. Tiempo de vídeo objetivo = `songStart + t + desfaseMs/1000` (`videoTarget`, :124), con `VIDEO_PTS_ORIGIN_S = 0` (:13; pendiente de la VM según el comentario :9-10). En un tramo de punch manda su vídeo y su desfase (`sourceAt`, :22-26). En la hoja de desfase, un cambio de desfase sube `offsetEpoch` y se trata como una búsqueda (`followEpoch`, :129): el núcleo ni se entera.

**SwiftUI.** No hay seguidor ni reloj intermedio. `TakeViewerModel` (`App/Sources/TakeViewer.swift:142`) construye un solo `AVPlayerItem` con `MontageBuilder.load(...)` + `builder.make(...)` + `makePlayerItem()` (:215-219) con vídeo, toma procesada y backing (o `audioOnlyItem`, :94-122, sin vídeo). Manda el reloj de `AVPlayer`; AVFoundation sincroniza imagen y sonido dentro del ítem. La posición de la UI sale de un observador periódico de 0,1 s (:172-177). El desfase de vídeo se aplica al construir la composición (`OffsetSheet.swift:125`, `preview.composition(videoOffset:)`), no en marcha. `setBacking` rehace la composición en el mismo instante (:191-231). El audio sale por `AVPlayer` a la salida predeterminada del sistema: no hay `audioOutputDeviceUniqueID` en `App/Sources` (grep sin resultados). Hoy el Mac suena por la salida del sistema; tras DI:13 (`decisiones-interfaz.md`) el visor sonará por la salida del perfil (`TakeViewSnapshot.outputName`), igual que Windows.

**Diferencia a recordar en Flutter.** Con el núcleo, imagen y sonido son dos dispositivos con relojes distintos y la imagen debe seguir al sonido. Flutter no porta `VideoFollower`: el motor de vídeo se decide en P9 (ADR-021, decisión 9): `fvp` con `onSync`, o reproductor nativo en el núcleo esclavo del reloj de audio. Tolerancia: medio fotograma. `takeview.position` sigue siendo el reloj publicado (`at` en reloj de host del núcleo, `epoch` en cada discontinuidad); lo que haga el motor con él es asunto de P9.

### 5.4 Fotogramas hoy

| Dato | Valor | Fichero:línea |
| --- | --- | --- |
| Relevo de cámara | 15 fps, 640 px de ancho, JPEG calidad 0,7, sin `latestWins` | `AC/FrameRelay.swift:51-52`; `VK/FrameJPEG.swift:39,41` |
| Creación | `service.makeCameraRelay` -> `Bridge.makeFrameRelay(channel: RecordService.cameraChannel)` | `AC/RecordMethods.swift:705` (comentario :704); `FrameRelay.swift:262-268`; asignación a la captura en :458-461 (la ficha de encargo decía ~655: el número real es 705) |
| Misma cámara en Ajustes | `CameraPreviewService.makeRelay` con el mismo canal | `RecordMethods.swift:711-712` |
| Tipo de fotograma, Mac | `FramePixelBuffer = CVPixelBuffer` | `VK/CameraCapture.swift:11` |
| Formato de captura, Mac | NV12 de rango limitado: `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` | `VK/CameraCapture.swift:107` (:347 es 32BGRA, otra ruta) |
| Tipo de fotograma, Windows | clase propia `FramePixelBuffer` (`#if !canImport(CoreVideo)`): `pixelFormat` (`bgra` o `nv12`), `width`, `height`, `bytesPerRow`, `byteCount`, `baseAddress`, alineada a 64; NV12 BT.709 rango limitado, plano UV tras el Y (`planeBaseAddress(1)`) | `VK/FramePixelBuffer.swift:13-40` |
| Origen en Windows | `MediaFoundationCamera.deliver` crea un `FramePixelBuffer(.nv12)` por fotograma y copia las filas Y y UV desde el búfer de Media Foundation | `VK/MediaFoundationCamera.swift:176-187` |
| Codificación | Mac: vImage + ImageIO; Windows: promedio de área + `PortableJPEG` en Swift, base 4:2:0 | `VK/FrameJPEG.swift:30-36` |
| Punto de enganche 1 | `RecordService.previewHook`: en el hilo de captura, con `f.pixelBuffer` sin convertir ni copiar, llama `relay.push(pb, ptsMs: hostSeconds*1000)` | `RecordMethods.swift:498-503` (ganchado en :460; la ficha decía :497, es el comentario) |
| Punto de enganche 2 | `FrameRelay.push` (admisión y límite de cadencia) y `FrameRelay.run`: `encode(frame)` (:193) -> `FrameEvent` con base64 (:195) -> `emit` (:197) | `FrameRelay.swift:124`, `:190-197` (la ficha decía ~159) |
| Punto de sustitución | el cierre `encode: (FramePixelBuffer) throws -> JPEGFrame` se inyecta en `init` | `FrameRelay.swift:63,97` |
| Equivalente en Windows | el mismo `previewHook`/`push`; el argumento es el `FramePixelBuffer` NV12 de `deliver`, de modo que `baseAddress`, `bytesPerRow`, `width`, `height` y `planeBaseAddress(1)` bastan para entregar píxeles crudos | `grep -rn FramePixelBuffer Packages` (ver líneas arriba) |
| Coste de datos (aritmética, no medido) | NV12 = 1,5 B por píxel: 640x360 = 345.600 B; 1920x1080 = 3.110.400 B por fotograma. JPEG a 640x360 ~25-45 kB (comentario `FrameJPEG.swift:38`), más 1/3 por base64 | |

Lo que no se puede asegurar desde el código: la cadencia real de `frames.camera` con cámaras físicas y el coste en Dart de decodificar base64 + JPEG a 15 fps (pendiente de Jorge / prueba 3 de P9, `docs/probes/P9-flutter.md`).

## 9. Desvíos detectados

Clasificación según `docs/flutter/desvios.md` (líneas 7-13). Los hechos están verificados leyendo el código citado.

| Id | Desvío | Evidencia SwiftUI | Evidencia `AppCore` / web | Clasificación |
| --- | --- | --- | --- | --- |
| G1 | `record.setPunch {enabled:true}` no selecciona la mejor toma. Hoy lo hace el cliente con dos llamadas. | `App/Sources/RecordView.swift:517-518`: si activa el punch sin toma elegida y la parte tiene mejor, `selectTake(best)` antes de `punchEnabled = on` | `AC/RecordMethods.swift:312-322` (`setPunch` solo asigna `punchEnabled` y los puntos); `AC/RecordController.swift:230` (`didSet` solo borra los puntos al apagar). Web: `W/record/bar.js:57-58` lo suple en cliente | **Hueco claro** (regla 2): la regla de SwiftUI es inequívoca (sin toma elegida y con mejor, elegirla). Arreglar en `AppCore` con test y fixture; en Dart no se replica (regla 5) (DI:51). |
| G2 | El nivel de entrada de guitarra no va en `record.levels`. | `RecordView.swift:126-128`: `model.audio.settings?.guitarIn` y `model.audio.inputLevels`, máximo de los canales asignados | `record.levels` solo lleva `mix.channels` y `mix.takeChannels` (`contrato-tipos-c.md` §record, `RecordLevelsEvent` :192). Existe `audio.levels` (`AudioLevelsEvent` `AC/AudioMethods.swift:137`) y `audio.settings.guitarIn` (:72). Web: `store.js:85-90` hace el máximo en cliente | **Interfaz / descartado como hueco de núcleo**: el dato está en `audio.*` y SwiftUI hace la misma combinación en la vista. Costes a anotar: Flutter debe llamar `audio.setMeters {visible:true}` al entrar y `{visible:false}` al salir (`store.js:71,80`) y reducir `guitarIn` (índices de canal desde 1) a un máximo sobre `AudioLevelsEvent.levels` (0...1) o `.rmsDB` (dBFS). Resuelto (DI:56): Dart lo lee de `audio.levels`; no se duplica en `record.levels`. |
| G3 | `RecordSnapshot` no trae `calibrationValid`. | `RecordView.swift:172`: `audio.calibrationValid` | El campo vive en `audio.state` (`AudioStateResult` `AC/AudioMethods.swift:95`, calculado en `AudioController.swift:385`). Web: `store.js:81,84` lo lee de `audio.setMeters` y del evento `audio.state`; aviso en `bar.js:93` | **Descartado como hueco**: no falta nada, solo hay que leerlo de `audio.*` (mismo canal que G2). Anotar que el aviso depende de dos fuentes (`blockReason` del snapshot y `calibrationValid`). |
| G4 | SwiftUI no tiene selector de cámara en Grabar. La ficha de encargo decía que la web usa `record.setCamera`: **no es cierto**, la web solo la exporta (`store.js:126`) y no hay llamadas en `record/*.js` ni en `screens/record.js` (búsqueda `setCamera`: solo `store.js` y `mock/record.js`). | `RecordView.swift:422-449`: solo etiqueta de formato y botón «Rotar»; la cámara se elige en Ajustes (`App/Sources/VideoSettingsView.swift`). `App/Sources/RecordController.swift` no tiene `chooseCamera` | `record.setCamera` existe en el núcleo (`AC/RecordMethods.swift:338`, `RecordController.swift:617`) y `RecordSnapshot.camera.cameras` lista las opciones | **Descartado**: Flutter reproduce SwiftUI (sin selector). Añadir uno sería función nueva: Cerrado (DI:27): no hay selector; la cámara se elige en Ajustes. |
| G5 | El mensaje de HEVC solo existe en la web. | AVFoundation reproduce HEVC (sin mensaje). | `W/record/take-sync.js:15-19`: códigos de `MediaError` 3 y 4 -> «Este equipo no puede reproducir el vídeo de esta toma (HEVC).»; el núcleo no tiene forma de saber si el reproductor del cliente decodifica | **Interfaz** para el texto (sale del error del reproductor de Dart). Pero el fondo toca vídeo: El motor de vídeo (`fvp` con `onSync`, o reproductor nativo del núcleo esclavo del reloj de audio) se decide en P9 (ADR-021, decisión 9); HEVC en Windows lo mide P9 (prueba 7). El texto del error de HEVC sigue siendo de interfaz. |
| G6 | Imán de ±1,5 dB del Master solo en cliente. | `App/Sources/RecordMixer.swift:71`: `abs($0) < 1.5 ? 0 : $0` en la vista | `W/backing/store.js:12` (`FADER_SNAP_DB = 1.5`), `W/record/mixer.js:83`. El núcleo acepta cualquier `gainDB` (`StudyMasterParams`) | **Interfaz** (regla 4): SwiftUI también lo hace en la vista. Constante 1,5 dB en Dart; el fader llega a ±6 dB (`BackingController.faderRange`, rango de la web en `backing/store.js`). |
| G7 | Sin reloj común para vídeo: la web persigue al audio con `VideoFollower`; SwiftUI usa un solo `AVPlayerItem`. | `TakeViewer.swift:215-219` | `take-sync.js:69-121`; núcleo `TakeViewMethods.swift:45-77` | **Decidido (ADR-021, decisión 9 enmendada; DI:78; `desvios.md` GR7):** el seguidor en Dart (`VideoFollower`) ya no es el plan. El motor de vídeo lo elige P9 por error A/V medido, con tolerancia de medio fotograma: (a) `fvp` (mdk) con su callback de reloj externo `onSync`, o (b) reproductor nativo en el núcleo esclavo del reloj de audio (`AVPlayer.setRate(_:time:atHostTime:)`, `AVPlayerItemVideoOutput` -> `CVPixelBuffer` -> textura). El audio suena en el núcleo; el vídeo va en silencio y sigue `takeview.position {seconds, playing, rate, at, epoch}`. Los números de §5.3 (`CoreClock`, `VideoFollower`) quedan como referencia de lo que hace la web hoy, no como especificación. **Se mide (P9)**; sin pregunta abierta. |
| G8 | Dos relojes de audio distintos: en SwiftUI el visor suena por la salida predeterminada del sistema; en el núcleo, por la salida del perfil. | `TakeViewer.swift` (sin `audioOutputDeviceUniqueID`) | `TakeViewSnapshot.outputName` (`TakeViewMethods.swift:86`) | Resuelto (DI:13): el visor del Mac pasa a sonar por la salida del perfil, por AppCore, igual que en Windows. Jorge lo comprueba de oído en la ola 3. |
| G9 | `record.cancel` está en el contrato y nadie lo llama. | `RecordView.swift` no llama `cancelTake`; solo existe `RecordController.cancelTake` (`App/Sources/RecordController.swift`, núcleo :760) | `store.js:115` exportado sin uso | **Interfaz / sin acción**: no se implementa en Flutter salvo petición. |

Hechos medidos frente a opiniones: los números de §5.3 y §5.4 son lectura directa del código; la aritmética de bytes de §5.4 es cálculo propio; las recomendaciones de G2, G7 y G8 quedaron resueltas por `decisiones-interfaz.md` (ver filas G2, G7, G8).

### Dudas para Jorge

Sin dudas abiertas en esta ficha. G5/G7 pasan a P9; G2 resuelta (Dart lee `audio.levels`, DI:56); G4 resuelta (sin selector, DI:27); G8 resuelta (DI:13).
