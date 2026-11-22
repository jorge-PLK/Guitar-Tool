# Ficha de pantalla · Ajustes

Ola: por asignar. Área del puente: `settings` (+ `audio`, `video`, `models`, `tools`, `library.relocate*`, `library.usage/cleanup*`). Destino: `FlutterApp/lib/features/settings/`.

Abreviaturas de evidencia: SV = `App/Sources/SettingsView.swift`, AS = `AudioSettingsView.swift`, CS = `CalibrationSheet.swift`, ADM = `AudioDeviceMonitor.swift`, VS = `VideoSettingsView.swift`, SM = `Packages/AppCore/Sources/AppCore/SettingsMethods.swift`, AM = `AudioMethods.swift`, CP = `CameraPreview.swift`, IM = `ImportMethods.swift`, LM = `LinkMethods.swift`, W = `WinApp/Web/settings/`.

## 1. Qué es

Pantalla de configuración única del equipo: se hace una vez y la usan Estudio, Grabar y Montaje. Se llega desde la barra lateral. Tiene tres pestañas, `Audio`, `Cámara y vídeo` y `Biblioteca` (el enum `SettingsTab`, que SV:18 recorre con `allCases` y que la web fija en `screens/settings.js:10-14`), y todo lo que cambia el usuario se guarda en el perfil de equipo del núcleo (`profile.json`).

El apartado «Biblioteca y equipo» del encargo es la pestaña `Biblioteca` (carpeta de proyectos, espacio, limpieza, modelos, fuentes externas). El perfil de equipo en sentido estricto lo forman las pestañas Audio y Cámara y vídeo.

## 2. Referencia visual (SwiftUI)

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Marco de la pantalla | SV:10-12, SV:40-41 | `ScrollView`, `VStack` alineado a la izquierda, `spacing: 20`, `padding(.horizontal, 36).padding(.vertical, 28)`. |
| Título y subtítulo | SV:12-16 | «Ajustes» `TF.display(30)`; subtítulo en `TF.muted`, sin fuente propia → Inter 14 regular (heredada); `spacing: 6`. |
| Pestañas | SV:17-33 | `HStack(spacing: 4)`; cada una `padding(.horizontal, 18)`, `frame(height: 44)`, radio 8, `TF.body(14, .semibold/.medium)`; activa `TF.accent` sobre `TF.accentBg`, inactiva `TF.text2`. Contenedor `padding(3)`, fondo `TF.field`, radio 10, borde `TF.fieldLine`. |
| `SettingsGroup` | SV:50-67 | Dentro de `Card`; título `TF.display(18, .medium)`, nota `TF.body(13)` `TF.muted`; `padding(.horizontal, 20).padding(.vertical, 18)`; `spacing: 14` entre cabecera y contenido **y entre cada fila del contenido** (confirmar con la captura de referencia, ola 0), 6 entre título y nota. |
| `InfoRow` | SV:69-81 | Etiqueta Inter 14 regular `TF.text` (heredada), `Spacer`, control; `spacing: 12`, `padding(.horizontal, 12).padding(.vertical, 10)`, fondo `TF.field`, radio 10. |
| Carpeta de proyectos | SV:110-117 | Rótulo `TF.body(13)` muted; ruta Inter 14 regular `TF.text` en una línea con truncado al medio, rótulo con `spacing: 6`, `minHeight: 44`, `padding(.horizontal, 12)`, radio 8, borde `TF.fieldLine`; «—» si no hay. |
| Espacio usado | SV:118-120 | `InfoRow` con `Fmt.bytes(totalBytes)` semibold `TF.text2`, «—» sin dato. |
| Progreso de cambio de carpeta | SV:121-126 | `ProgressView(value:)` tinte `TF.accent` + «Moviendo N %» (`Fmt.percent`) `TF.body(13)` muted. |
| Botones de biblioteca | SV:127-133 | `HStack(spacing: 8)`: `SecondaryButton` «Cambiar carpeta» (deshabilitado con progreso) y «Limpiar tomas descartadas y stems». |
| Modelos | SV:137-154, SV:182-192 | Fila con `displayName` y estado coloreado; barra con progreso; botón `PrimaryButton` «Descargar» o `SecondaryButton` «Borrar». |
| Fuentes externas | SV:156-180 | Tres `InfoRow` (yt-dlp con `Chip`, Deno, ffmpeg); estado de actualización; botones `PrimaryButton` «Actualizar yt-dlp» y `SecondaryButton` «Volver a la embebida». |
| Dispositivo (Audio) | AS:114-145 | Tres `InfoRow`: salida y entrada con `Picker` `maxWidth: 320`; frecuencia `Picker` segmentado `width: 220`. |
| Aviso de frecuencia | AS:164-175 | Texto `TF.body(13)` `TF.accent`, subtexto `TF.body(12)` muted, botón secundario condicional; `spacing: 8`. |
| Canales | AS:179-202 | Pickers `maxWidth: 280`; `InputMeters` a la izquierda del de entrada. |
| `InputMeters` | AS:66-82 | Una barra por canal, `HStack(alignment: .bottom, spacing: 4)`; pista 8×28, radio 2, relleno `TF.ok` de altura `28 × nivel` (0...1), pista `TF.field`. Sin niveles no pinta nada. |
| Calibración (Audio) | AS:206-229 | Fila «Latencia» con estado; botón secundario «Calibrar latencia» (deshabilitado con `deviceBlock`); motivo en `TF.body(12)` muted. |
| Hoja de calibración | CS:19-32 | Ancho 540, `padding(28)`, `spacing: 18`, fondo `TF.bg`, título `TF.display(22)`. Detalle en apartado 7. |
| Barra lateral (salida) | ADM:34-39 | Título y subtítulo del dispositivo de salida; vive fuera de Ajustes, pero depende del mismo dato (apartado 9, desvío 8). |
| Cámara y previa | VS:244-284 | `HStack(alignment: .top, spacing: 20)`: columna de tres `InfoRow` (`spacing: 10`) y vista previa de ancho 240. Cámara `maxWidth: 280`; resolución y fps `maxWidth: 160`. |
| Vista previa | VS:286-308 | Fondo negro, relación 16:9, radio 10, borde `TF.fieldLine`. Rotación guardada de la cámara aplicada solo a la imagen (VS:130-174, VS:293). |
| Mensajes de la previa | VS:310-321 | Icono 18 pt `TF.muted` + texto `TF.body(12)` `TF.text2` centrado, `padding(8)`. Leyenda simulada: `TF.body(11, .semibold)` blanco, cápsula negra al 60 %, `padding(.horizontal, 8).padding(.vertical, 3)` y `.padding(6)` externo (separación al borde inferior de la previa), alineada abajo. |
| Barras de color | VS:386-394 | Ocho franjas: blanco, amarillo, cian, verde, rosa, rojo, azul, negro, cada una con opacidad 0,85. Colores sueltos fuera de `TF`: pasan a token (`colorBars`). |
| Sincronía | VS:331-350 | Campo numérico `width: 70` alineado a la derecha, «ms» muted y `Stepper` de paso 1, rango −500…500 (VS:182). |
| Exportación | VS:354-383 | `Picker` segmentado `width: 160` (HEVC, H.264), `Picker` de resolución `frame(width: 100)` junto al segmentado en la misma `InfoRow`, texto fijo «normalizado a −14 LUFS», dos `Toggle` `.switch` de tamaño normal (sin `.small`), con acento del sistema (sin `.tint`), `labelsHidden`. |

## 3. Árbol de widgets propuesto

- `SettingsScreen` (SV:5-44): `TfScreenScroll` con título, subtítulo y `TfSegmentedTabs` (pestañas 44 de alto; kit compartido).
  - `AudioTab`
    - `TfSettingsGroup` «Dispositivo» (SV:50) con `TfInfoRow` y `TfDropdown` de salida y entrada, `TfSegmented` de frecuencia y `RateMismatchNotice`.
    - `TfSettingsGroup` «Canales» con `TfDropdown` de salida de backing y `InputMeters` (**`CustomPainter`**, AS:66-82) junto al de entrada de guitarra.
    - `TfSettingsGroup` «Calibración» con `LatencyStatus`, botón y motivo de bloqueo.
    - `CalibrationSheet` (hoja modal de 540; apartado 7).
  - `VideoTab`
    - `TfSettingsGroup` «Cámara» con tres `TfInfoRow` y `CameraPreviewBox` (16:9, `RawImage` del canal `preview`, rotación con `RotatedBox`/`Transform.rotate`, `ColorBars` con **`CustomPainter`** o `Row` de `ColoredBox`).
    - `TfSettingsGroup` «Sincronía» con `OffsetField` (campo + stepper).
    - `TfSettingsGroup` «Exportación por defecto» con `TfSegmented`, `TfDropdown` y dos `TfSwitch`.
  - `LibraryTab`
    - `TfSettingsGroup` «Biblioteca» (campo de carpeta, espacio usado, `RelocationProgress`, botones).
    - `TfSettingsGroup` «Modelos» con `ModelRow`.
    - `TfSettingsGroup` «Fuentes externas» con tres `TfInfoRow`, `TfChip`, `YtDlpStatus`.
    - `TfSettingsGroup` «Idioma» (nuevo, ver «Idioma»).
  - Diálogos: `TfConfirmDialog` para «Carpeta de proyectos» (tres botones) y «Borrar el modelo»; para «Limpiar toda la biblioteca» el diálogo lo define la ficha de Biblioteca (`requestCleanup`, SV:131), que esta pantalla reutiliza.
- `SettingsStore` (Riverpod): `audio`, `video`, `library`, `models`, `tools`; un `Notifier` por pestaña para no pasar de ~300 líneas por fichero.

## 4. Estados

| Estado | Qué se ve | Qué lo decide |
| --- | --- | --- |
| Sin dispositivo de entrada | Selector de entrada en «Ninguna»; el de guitarra queda deshabilitado (AS:199); sin medidores. «Calibrar latencia» deshabilitado con el motivo en 12 pt (AS:214-216). | `audio.settings.inputDeviceUID == null`, `calibrateBlock`. |
| Sin salida elegida | «Salida del sistema» en el selector (AS:119). | `outputDeviceUID == null`. |
| Dispositivo desconectado en caliente | La opción elegida sigue en la lista con «`<nombre>` · desconectado» (AS:154); el motivo sale en `calibrateBlock`. La lista se rehace sin sondeo. | Evento `audio.devicesChanged` (`connected: false`) y `audio.state`. |
| Frecuencia distinta | Aviso naranja con «Grabar y calibrar quedan bloqueados…» y, si la frecuencia del dispositivo es permitida, botón «Usar … como frecuencia de trabajo». | `rateMismatch`, `canUseDeviceRate`. |
| Sin calibrar | «Sin calibrar» en `TF.accent` (AS:227). | `calibration.calibrated == false`. |
| Calibrada | «Calibrada · 2,05 ms · 3 feb 2026» en `TF.ok` (AS:223-225). | `calibration.label`. |
| Calibrando | Hoja con barra `AccentBar` de 8 de alto y porcentaje; la hoja no se puede cerrar (CS:30, CS:60-67). | `audio.calibration` con `phase: "running"`. |
| Calibración fallida | Título rojo y qué hacer; botones «Repetir» y «Cerrar» (CS:117-133, CS:80-86). | `outcome: "failure"`, `failure.reason`. |
| Calibración con error | «No se pudo calibrar» y el mensaje (CS:77-78). | `outcome: "error"`, `error`. |
| Calibración cancelada | SwiftUI no ofrece cancelar; en AppCore la fase vuelve a `idle` sin resultado (`AudioController.swift:581-586`). Sin botón «Cancelar» durante la medida (decisiones-interfaz.md); solo se cancela si la hoja se destruye. | `audio.cancelCalibration`. |
| Sin cámara | Previa con icono de cámara y «No hay ninguna cámara conectada.»; resolución y fps deshabilitados (VS:269, VS:277); nota del grupo igual. | `video.settings.noCamera`, `preview.state == "noCamera"`. |
| Cámara elegida desconectada | Nota «La cámara elegida está desconectada.»; opción «`<nombre>` · desconectada» (VS:239). | `cameraConnected == false`, `cameraName`. |
| Permiso de cámara denegado | Icono de candado, «ToneForge no tiene permiso para usar la cámara.» y botón «Abrir Ajustes del Sistema» (VS:298-302). | `preview.state == "denied"`. |
| Previa simulada | `ColorBars` y leyenda «Vista previa simulada». | `preview.state == "simulated"`. |
| Previa fallida | Icono de triángulo y «No se pudo abrir la cámara (…).» | `preview.state == "failed"`, `message`. |
| Previa abriéndose | Rueda pequeña centrada (`idle`, VS:295). | `preview.state == "idle"` tras `start`. |
| Grabar abierta | La previa no abre otra captura y usa la de Grabar. | `preview.fromRecord == true` (CP:96-101). |
| Descarga de modelo en curso | Estado «Descargando N %» en `TF.accent`, barra, sin botones (SV:141-143, SV:151). | `models.progress` y `models.list.state == "downloading"`. |
| Verificando e instalando | «Verificando…» e «Instalando…» sin barra. | `state == "verifying"/"installing"`. |
| Fallo por hash | «Error» en `TF.danger` con el mensaje como ayuda emergente (SV:190); botón «Descargar» de nuevo (SV:148). | `state == "failed"`, `message`; `models.changed.error`. |
| Modelo instalado | «Descargado · 1,2 GB» en `TF.ok`; botón «Borrar» con confirmación. Si `source == "folder"` (Windows) no hay tamaño ni qué borrar. | `state == "installed"`, `bytes`, `source` (SM:359-363). |
| Cambio de carpeta con progreso | Barra y «Moviendo N %»; «Cambiar carpeta» deshabilitado (SV:121-129). Solo hay barra con «Mover»; «Solo apuntar» no emite progreso útil. | `library.relocateProgress.fraction`. |
| Cambio de carpeta rechazado | Hay cola de trabajo o grabación: error `work-in-progress` (la web muestra un aviso propio, `library.js:46`). | respuesta de `library.relocate`. |
| yt-dlp | «comprobando…» hasta tener `tools.info`; «no disponible» si falta; chip «actualizada» (ok) o «embebida» (neutro); durante la actualización barra lineal indeterminada; resultado en verde o rojo (SV:161-179). | `tools.info`, respuesta de `tools.updateYtDlp`. |

## 5. Contrato que usa

Los DTO de `SettingsMethods.swift` son diccionarios `SJ` (no hay `struct`); los campos se tomaron de `videoJSON`, `modelEntry`, `usage` y `settingsGet`. Fixtures dorados por método según `arquitectura.md`.

### settings, library, models, tools

| Acción o momento | Método / evento | DTO (Swift) | Uso en la web |
| --- | --- | --- | --- |
| Entrar en Biblioteca | `settings.get` | SM:314-319: `{projectsFolder: String?, activeProjectsFolder: String?, video: <video.settings>}`. | `library.js:24`; marca «reinicio» si difieren (no aplica en Flutter, ver desvío 2). |
| Espacio usado | `library.usage` | SM:321-328: `{totalBytes: Int64, regenerableBytes: Int64, projects: [{id: String, folderName: String, bytes: Int64, regenerableBytes: Int64}]}`. | `library.js:25`; se recarga con `library.changed`. |
| Pulsar «Limpiar…» | `library.cleanupInfo` `{id?: String}` | `CleanupInfoResult{bytes: Int64}` (IM:74). `id` nulo = toda la biblioteca. | `library.js:53`. |
| Confirmar limpieza | `library.cleanup` `{id?: String}` | `CleanupResult{cleaned: Bool, bytes: Int64}` (IM:75). | ficha de Biblioteca. |
| Elegir carpeta | `host.chooseFolder` | `ChosenFolderResult{path: String?}` (IM:90-95; la clave siempre está, con `null` si se cancela). | `library.js:32` (timeout 10 min). |
| Aplicar carpeta | `library.relocate` `{path: String, mode: "move"\|"point"}` | `RelocateResult{path: String, mediaRemapped: Bool}` (IM:97-99). Errores: `bad-params`, `work-in-progress`. | `library.js:41` (timeout 60 min). |
| Progreso del traslado | evento `library.relocateProgress` | `RelocateProgress{fraction: Double}` (0...1). | `library.js:29`. |
| Fin del traslado | evento `library.relocated` | `RelocateResult`. | no lo escucha (usa la respuesta). |
| Abrir Biblioteca / recargar | `models.list` | SM:368-370: `{models: [{id, name, state, fraction: Double?, bytes: Int64?, archiveBytes: Int64, message: String?, source: "store"\|"folder"?}], modelsBytes: Int64}`; `state` ∈ `notInstalled, downloading, verifying, installing, installed, failed`. | `library.js:80`. |
| «Descargar» | `models.download` `{id?: String}` | `{started: Bool}`; `false` si ya había una descarga. | `library.js:89`. |
| Avance | evento `models.progress` | `ModelProgress{id: String, fraction: Double}` (SM:524), un evento por punto porcentual. | `library.js:81`. |
| Fin o fallo | evento `models.changed` | `{models: [...], error: {code: "model-failed", message}?}` (SM:394). | `library.js:82-85`. |
| «Borrar» | `models.delete` `{id?: String}` | Igual que `models.list`. Errores `busy`, `not-found`, `internal`. | `library.js:94`. |
| Abrir Fuentes externas | `tools.info` | `ToolsInfoResult{ytDlpVersion, ytDlpOrigin: "updated"\|"embedded", denoVersion, ffmpegVersion}`, todos `String?` (LM:108-122). | `library.js:125`. |
| «Actualizar yt-dlp» | `tools.updateYtDlp` | `UpdateYtDlpResult{version: String, origin: String, alreadyLatest: Bool}` (LM:124-128). | `library.js:133` (timeout 200 s) y luego `tools.info`. |
| «Volver a la embebida» | `tools.revertYtDlp` | `RevertedResult{reverted: Bool}`. | `library.js:139`. |

### audio

| Acción o momento | Método / evento | DTO (Swift) | Uso en la web |
| --- | --- | --- | --- |
| Entrar en Audio | `audio.settings` | `AudioSettingsResult` (AM:68-83): `outputDeviceUID: String?`, `inputDeviceUID: String?`, `backingOut: {left: Int, right: Int}`, `guitarIn: [Int]?`, `workingSampleRate: Double`, `allowedSampleRates: [{rate: Double, label: String}]`, `backingChoices: [{label, left, right}]`, `guitarChoices: [{label, channels: [Int]?}]`, `rateMismatch: {deviceRate, workingRate, message, hint, canUseDeviceRate: Bool, useLabel}?`, `calibration: {calibrated: Bool, label: String, latencyMS: Double?, date: Date?}`, `calibrateBlock: String?`, `calibrateInstructions: [String]`. | `audio.js:24`. |
| Lista de dispositivos | `audio.devices` | `AudioDevicesResult` (AM:21-26): `inputs`, `outputs`, `systemDefault: AudioDeviceItem?`; `AudioDeviceItem{uid, name, channels: Int, label, connected: Bool, rate: Double?}`. | `audio.js:26`, `device-card.js:19`. |
| Cambiar cualquier selector | `audio.setSettings` | `AudioSetSettingsParams` (AM:144-167): `outputDeviceUID`, `inputDeviceUID`, `guitarIn` con **tres estados** (ausente = no tocar, `null` = sistema/ninguna/sin asignar, valor), `backingOut: {left,right}`, `workingSampleRate: 44100\|48000`. Devuelve `AudioSettingsResult`. Errores `bad-params` (canales inválidos, frecuencia). | `audio.js:37`. |
| Pestaña visible | `audio.setMeters` `{visible: Bool}` | `AudioStateResult` (AM:85-100). `true` al entrar y `false` al salir. | `audio.js:25`, `audio.js:32`. |
| Estado de sesión | `audio.state` y evento `audio.state` | `AudioStateResult`: `sessionOpen, sessionError?, interruptionNote?, hostError?, hosting, metersVisible, recording, calibrationRunning, calibrationValid, calibrateBlock?, recordingNotices: [String], mismatchedRate?, workingSampleRate`. | `audio.js:31` (recarga ajustes). |
| Medidores | evento `audio.levels` | `AudioLevelsEvent{levels: [Float], rmsDB: [Float], peakDB: [Float]}`; `levels` vacío = sin sesión. | `audio.js:29`. |
| Cambio de dispositivos | evento `audio.devicesChanged` | `AudioDevicesResult`. | `audio.js:30`, `device-card.js:30`. |
| «Empezar» | `audio.calibrate` | `AudioCalibrationState` (AM:126-135): `phase: idle\|running\|finished`, `progress: Double?`, `outcome: success\|failure\|error`, `success: {latencyMS, latencySamples, spreadMS, spreadSamples, rigDelayMS?, correctedTakes: Int, rows: [{label, value}]}`, `failure: {reason: noSignal\|saturated\|unstable, spreadMS, title, hint}`, `error: String?`. **La llamada no vuelve hasta acabar**. | `calibration-sheet.js:23` (timeout 60 s). |
| Progreso | evento `audio.calibration` | `AudioCalibrationState`. | `calibration-sheet.js:17`. |
| Cerrar hoja | `audio.cancelCalibration` si `running`, si no `audio.dismissCalibration` | `AudioCalibrationState`. | `calibration-sheet.js:19`. |
| «Repetir» | `audio.dismissCalibration` | `AudioCalibrationState`. | `calibration-sheet.js:25`. |

### video

| Acción o momento | Método / evento | DTO (Swift) | Uso en la web |
| --- | --- | --- | --- |
| Entrar en Cámara y vídeo | `video.cameras` | SM:421-435: `{cameras: [{id, name, kind: builtIn\|external\|continuity\|simulated\|other, isDefault: Bool, resolutions: [{width: Int, height: Int, label, fps: [{value: Double, label}]}]}], defaultId: String?}`. | `video.js:25`. |
| Ajustes de vídeo | `video.settings` | `videoJSON` (SM:439-473): `cameraUID: String?`, `cameraConnected: Bool`, `cameraName: String?`, `effectiveCameraId: String?`, `noCamera: Bool`, `resolution: {width, height, label}`, `fps: Double`, `fpsLabel`, `shown: {resolution, fps, fpsLabel}?`, `offsetMs: Int`, `rotation: Int`, `offsetsMs: {id: Int}`, `rotations: {id: Int}`, `export: {codec: String, resolution, titleOverlay: Bool, exportStemWAVs: Bool, normalizeLUFS: Double}`, `choices: {codecs: [String], exportResolutions: [res], rotations: [0,90,180,270], offsetRangeMs: {min, max}}`. | `video.js:27`. |
| Cambiar cámara, resolución, fps, desfase, giro o exportación | `video.setSettings` | SM:198-219: `{cameraUID?: String\|null (clave presente con null = «Por defecto del sistema»), resolution?: {width,height}, fps?: Double, offset?: {cameraId?: String, ms: Double}, rotation?: {cameraId?: String, degrees: Int}, export?: {codec?, resolution?, titleOverlay?: Bool, exportStemWAVs?: Bool}}`. Solo cambia lo enviado. `ms` se redondea y se limita a ±500; sin `cameraId` se aplica a la cámara efectiva. Devuelve `video.settings`. Errores `bad-params`. | `video.js:32`. |
| Conectar o quitar una cámara | evento `video.camerasChanged` | `Empty`. | `video.js:28` (recarga `video.cameras` y `video.settings`). |
| Entrar en la pestaña | `video.preview.start` | `CameraPreviewResult` (CP:10-24): `state: idle\|live\|simulated\|noCamera\|denied\|failed`, `message: String?`, `cameraId?`, `cameraName?`, `width?`, `height?`, `fps?: Double`, `rotation: Int`, `fromRecord: Bool`. | `video.js:78`. |
| Salir de la pestaña | `video.preview.stop` | `CameraPreviewResult` con `state: "idle"`. | `video.js:80`. |
| «Abrir Ajustes del Sistema» | `video.openCameraPrivacy` | `{opened: Bool}`. | `video.js:94`. |
| Imagen de la previa | canal de fotogramas `preview` (Flutter) | BGRA; en la web `frames.camera` JPEG (`video.js:5`, `attachFrames`). | `video.js:69`. |

## 6. Interacción

- No hay atajos de teclado, arrastres ni menús contextuales en Ajustes (las tres vistas no usan `.keyboardShortcut`, `.onDrag` ni `NSEvent`).
- `Stepper` y campo de desfase (VS:343-346): el campo es numérico entero, alineado a la derecha; fuera de ±500 se limita en el núcleo (SM:506). El campo deshabilita con `uid == nil` (VS:348).
- Pickers nativos de macOS: en Flutter son `TfDropdown`; las pestañas se pueden recorrer con Tab y activar con Enter o Espacio (criterio de accesibilidad propio, no viene de SwiftUI).
- Ciclo de vida: al aparecer Audio se llama a `audio.setMeters{visible:true}` y al desaparecer `false` (AS:96-97); al aparecer Cámara y vídeo arranca la previa y al desaparecer se para (VS:192-201). Debe ocurrir también al cambiar de pestaña, no solo al salir de Ajustes.
- Rehacer la previa: cambia la cámara, la resolución, los fps o la lista de cámaras (VS:203, VS:217-221).
- Foco: ninguna hoja pide foco inicial; la hoja de calibración no se cierra con Escape mientras mide (CS:30).

## 7. Hojas y popovers

### Hoja «Calibrar latencia»

- Referencia: CS:19-134. Ancho 540, `padding(28)`, fondo `TF.bg`, título `TF.display(22)`, `spacing: 18`. Se cierra al desaparecer con `dismissCalibration` (CS:31).
- Estado inicial (CS:36-56): tres párrafos `TF.body(14)` `TF.text2` (el tercero muted) con los textos de `calibrateInstructions`; si hay `calibrateBlock`, texto `TF.body(13)` `TF.accent`; botones «Cancelar» y «Empezar» (deshabilitado con bloqueo).
- Midiendo (CS:60-67): «Midiendo… no toques la guitarra ni muevas el cable.», `AccentBar` de 8 de alto y porcentaje `TF.body(13)` muted con `monospacedDigit`.
- Éxito (CS:90-108): `Chip` «Calibrada» (ok) y panel `TF.field`, radio 10, `padding(14)`, filas de etiqueta ancho 120 `TF.body(13)` muted y valor `TF.body(14, .semibold)` color `TF.text` (no `text2`), `spacing: 12` entre columnas, 8 entre filas, 12 entre el chip y el panel; las filas llegan hechas en `success.rows`. Botón primario «Cerrar».
- Fallo y error: título `TF.display(16)` `TF.danger` y pista `TF.body(14)`; «Repetir» (secundario) y «Cerrar» (primario).
- Contrato: `audio.calibrate`, evento `audio.calibration`, `audio.cancelCalibration`, `audio.dismissCalibration` (apartado 5). La web envía `cancelCalibration` si se cierra con la medida en marcha (`calibration-sheet.js:19`). Resuelto: en Flutter la hoja no se puede cerrar midiendo, como SwiftUI; `cancelCalibration` se envía solo si la hoja se destruye de todos modos (cierre de ventana, cambio de pantalla; decisiones-interfaz.md).

### Diálogos de confirmación

- «Carpeta de proyectos» (SV:91-99): botones «Mover los temas aquí», «Solo apuntar a esta carpeta», «Cancelar»; mensaje ««`<ruta>`»: ¿mover los temas existentes a la carpeta nueva o solo apuntar a ella?». Mover = `mode: "move"`; apuntar = `mode: "point"`.
- «Borrar el modelo» (SV:100-105): «Borrar» destructivo y «Cancelar»; mensaje «Se volverá a descargar la próxima vez que separes un tema.»

## 8. Textos

Claves en `app_es.arb` (español literal; inglés lo traduce el agente).

| Clave | Español | Origen |
| --- | --- | --- |
| `settings_title` | Ajustes | SV:13 |
| `settings_subtitle` | Se configura una vez y lo usan todas las pantallas. Se guarda en tu perfil de equipo. | SV:14 |
| `settings_tabAudio` / `settings_tabVideo` / `settings_tabLibrary` | Audio / Cámara y vídeo / Biblioteca | `screens/settings.js:11-13` (SwiftUI usa `SettingsTab.rawValue`, mismos textos) |
| `settings_audio_deviceTitle` / `_deviceNote` | Dispositivo / Por dónde suena el backing y por dónde entra tu guitarra. | AS:115 |
| `settings_audio_output` / `_input` / `_rate` | Dispositivo de salida / Dispositivo de entrada / Frecuencia de trabajo | AS:116-136 |
| `settings_audio_systemOutput` / `_noInput` | Salida del sistema / Ninguna | AS:119, AS:129 |
| `settings_audio_deviceOption` | `{name} · {channels} can.` | AS:152 |
| `settings_audio_deviceDisconnected` / `_chosenFallback` | `{name} · desconectado` / Dispositivo elegido | AS:154 |
| `settings_audio_rateMismatch` | El dispositivo está a `{device}` y la frecuencia de trabajo es `{working}` | AS:166 |
| `settings_audio_rateMismatchHint` | Grabar y calibrar quedan bloqueados; el backing suena igual. | AS:168 |
| `settings_audio_useRate` | Usar `{rate}` como frecuencia de trabajo | AS:171 |
| `settings_audio_channelsTitle` / `_channelsNote` | Canales / Qué entra y qué sale por cada canal del dispositivo. | AS:184 |
| `settings_audio_backingOut` / `_guitarIn` | Salida del backing / Entrada de guitarra | AS:185-192 |
| `settings_audio_backingChoice` | Salidas `{l}` y `{r}` · estéreo | AS:51 |
| `settings_audio_unassigned` / `_inputN` / `_inputsNM` | Sin asignar / Entrada `{n}` / Entradas `{n}` y `{m}` | AS:59-60 |
| `settings_audio_calTitle` / `_calNote` | Calibración / Un pulso de prueba mide el retardo de ida y vuelta del dispositivo. | AS:208-209 |
| `settings_audio_latency` / `_calibrate` | Latencia / Calibrar latencia | AS:210-211 |
| `settings_audio_calibrated` / `_uncalibrated` | Calibrada · `{ms}` ms · `{date}` / Sin calibrar | AS:224-227 |
| `settings_cal_title` | Calibrar latencia | CS:21 |
| `settings_cal_step1`, `_step2`, `_step3` | Las tres instrucciones literales | CS:39-41 |
| `settings_cal_running` | Midiendo… no toques la guitarra ni muevas el cable. | CS:62 |
| `settings_cal_start` / `_cancel` / `_retry` / `_close` | Empezar / Cancelar / Repetir / Cerrar | CS:51-85 |
| `settings_cal_done` | Calibrada | CS:92 |
| `settings_cal_rowLatency` / `_rowSpread` / `_rowRig` / `_rowCorrected` | Latencia / Dispersión / Retardo del rig / Tomas corregidas | CS:94-102 |
| `settings_cal_rigNone` | sin canal de referencia: la latencia calibrada vale tal cual | CS:99 |
| `settings_cal_rigNote` | `{ms}` ms · se corregirá en cada toma | CS:97 |
| `settings_cal_correctedNote` | `{n}` de este tema, hechas sin calibrar | CS:102 |
| `settings_cal_errorTitle` | No se pudo calibrar | CS:77 |
| `settings_cal_noSignalTitle` / `_noSignalHint` | No llegó la señal de prueba / Comprueba el cable de una salida del dispositivo a la entrada de guitarra, y que la entrada elegida sea esa. Después repite. | CS:120-121 |
| `settings_cal_saturatedTitle` / `_saturatedHint` | La señal llegó saturada / Baja el volumen de salida del dispositivo (con una pedalera, el del rig o el de la salida) y repite. | CS:123-124 |
| `settings_cal_unstableTitle` / `_unstableHint` | Las medidas no coinciden entre sí (dispersión de `{ms}` ms) / Carga un rig vacío o sin delay ni reverb, cierra otras apps de audio y repite. | CS:126-127 |
| `settings_video_cameraTitle` | Cámara | VS:252 |
| `settings_video_inUse` / `_chosenOff` / `_none` | En uso: `{name}`. / La cámara elegida está desconectada. / No hay ninguna cámara conectada. | VS:249-251 |
| `settings_video_camera` / `_resolution` / `_fps` | Cámara / Resolución / Fotogramas por segundo | VS:255-271 |
| `settings_video_systemDefault` | Por defecto del sistema | VS:258 |
| `settings_video_cameraDisconnected` / `_chosenFallback` | `{name}` · desconectada / Cámara elegida | VS:239 |
| `settings_video_simulated` | Vista previa simulada | VS:294 |
| `settings_video_denied` / `_openSystem` | ToneForge no tiene permiso para usar la cámara. / Abrir Ajustes del Sistema (en Windows «Abrir Configuración», variante por plataforma; ver desvío 9) | VS:300-301, CP:59 |
| `settings_video_openFailed` | No se pudo abrir la cámara (`{error}`). | VS:117, CP:153 |
| `settings_video_syncTitle` / `_syncNote` / `_offset` | Sincronía / Se ajusta al terminar cada toma; este es el valor con el que empieza la siguiente. / Desfase por defecto de esta cámara | VS:340-342 |
| `settings_video_exportTitle` / `_exportNote` | Exportación por defecto / Se puede cambiar en cada montaje. | VS:355 |
| `settings_video_format` / `_volume` / `_volumeValue` | Formato de vídeo / Volumen / normalizado a −14 LUFS | VS:356-370 |
| `settings_video_titleOverlay` / `_stemWavs` | Rótulo con el título del tema / WAV de cada pista | VS:372-377 |
| `settings_lib_title` / `_note` | Biblioteca / Una carpeta por tema, con sus stems, tomas y vídeo. | SV:109 |
| `settings_lib_folder` / `_usage` | Carpeta de proyectos / Espacio usado | SV:111-118 |
| `settings_lib_moving` | Moviendo `{percent}` | SV:124 |
| `settings_lib_change` / `_clean` | Cambiar carpeta / Limpiar tomas descartadas y stems | SV:128-131 |
| `settings_lib_cleanTitle` | Limpiar toda la biblioteca | SV:131 |
| `settings_lib_moveHere` / `_pointOnly` / `_cancel` | Mover los temas aquí / Solo apuntar a esta carpeta / Cancelar | SV:94-96 |
| `settings_lib_relocateMessage` | «`{path}`»: ¿mover los temas existentes a la carpeta nueva o solo apuntar a ella? | SV:98 |
| `settings_lib_workInProgress` | Hay trabajo en curso. Espera a que terminen las separaciones y vuelve a cambiar la carpeta. | `library.js:46` (texto de la web, no de SwiftUI) |
| `settings_models_title` / `_note` | Modelos / Se descargan la primera vez que se usan. | SV:139 |
| `settings_models_pending` / `_downloading` / `_verifying` / `_installing` / `_installed` / `_error` | Pendiente · `{size}` / Descargando `{percent}` / Verificando… / Instalando… / Descargado · `{size}` / Error | SV:185-190 |
| `settings_models_download` / `_delete` | Descargar / Borrar | SV:147-149 |
| `settings_models_deleteTitle` / `_deleteMessage` | Borrar el modelo / Se volverá a descargar la próxima vez que separes un tema. | SV:100-104 |
| `settings_tools_title` / `_note` | Fuentes externas / Importar desde enlace usa yt-dlp, Deno y ffmpeg, que van dentro de la app. Si YouTube cambia y las descargas fallan, actualiza yt-dlp. | SV:159-160 |
| `settings_tools_checking` / `_unavailable` | comprobando… / no disponible | SV:162 |
| `settings_tools_updated` / `_embedded` | actualizada / embebida | SV:163 |
| `settings_tools_update` / `_revert` | Actualizar yt-dlp / Volver a la embebida | SV:174-176 |
| `error_model-failed`, `error_busy`, `error_work-in-progress`, `error_bad-params` | Sin texto en SwiftUI; el fallback es `message` del núcleo | SM:391, SM:402, IM:260 |

## 9. Desvíos detectados

| # | Gravedad | Desvío | Evidencia | Qué falta o qué hay | Tratamiento |
| --- | --- | --- | --- | --- | --- |
| 1 | Alta | Cámaras en el Mac por AppCore: `video.cameras` y `video.settings` salen vacías (`noCamera: true`) salvo con `--camera` o `--audio simulated`, mientras `video.preview.start` usa el sistema real. | SM:268-273 (`#if !os(Windows)` devuelve `nil` sin opciones); CP:102 y `RecordController.swift:165-171` (`resolve` cae a `.system()`); SwiftUI usa el proveedor real, VS:193. | Selector, nota y previa pueden hablar de cámaras distintas; en Mac con Flutter la lista saldría vacía y la previa abriría la real. El comentario de SM:266-267 dice que es deliberado para tests y `tf-webdev`. | Hueco claro: el comportamiento de SwiftUI manda (lista real). Sin proponer implementación; queda anotado para el planificador. Resuelto: hueco claro de núcleo, lo implementa `tf-implementer` antes de la ola 3 (decisiones-interfaz.md). |
| 2 | Alta | Cambio de carpeta en caliente. SwiftUI elige y aplica en el mismo flujo; AppCore separa `host.chooseFolder` y `library.relocate`, que rechaza con trabajo en cola o grabando y cierra antes los ficheros del tema abierto (estudio, visor de tomas, Montaje, tablatura). | SV:91-99, SV:128; IM:245-271 (rechazo IM:260, cierre IM:261); `JobQueue.swift:388-400`. | La respuesta `mediaRemapped` y `projectsFolderChanged` sirven a la web (`mediaBase`); Flutter abre ficheros por ruta. `host.pickProjectsFolder` guarda en el perfil y devuelve `restartRequired: true` (IM:325); no usarlo en Ajustes. La web marca «reinicio» si `projectsFolder != activeProjectsFolder` (`library.js:24`). | Hueco claro en el flujo (usar `host.chooseFolder` + `library.relocate`). Qué hace Flutter con las pantallas abiertas al cerrarse los ficheros (la web hace `go('library')`) Resuelto: tras mover la carpeta, Flutter se queda en Ajustes, como SwiftUI (decisiones-interfaz.md). |
| 3 | Media | Cancelar la calibración. AppCore la ofrece; SwiftUI no tiene botón mientras mide. | CS:30; `AudioController.swift:581-586`; web `calibration-sheet.js:19`. | Sin botón no hay forma de abortar 5 s de pitidos. | Resuelto: no se añade botón «Cancelar» durante la medida; `audio.cancelCalibration` se envía solo si la hoja se destruye con la medida en marcha (decisiones-interfaz.md). |
| 4 | Media | Textos del núcleo en español y con coma decimal. Con inglés, `label`, `message`, `hint`, `title`, `rows`, `calibration.label`, `rateMismatch.*`, `calibrateBlock`, `calibrateInstructions` llegan en español. | AM:348-357 (`number`, `dateText` con `Locale("es")`), AM:176-181, AM:322-323, `AudioController.swift:486-488`. | Faltan códigos y números sin formato para traducir en Dart. | Resuelto: el núcleo conserva el código del error y entrega códigos y argumentos numéricos; Dart compone el texto y gen-l10n formatea los números. Vale también para los textos de audio y calibración (`label`, `hint`, `rows`, `calibrateBlock`, `rateMismatch.*`, `calibrateInstructions`). El núcleo recibe el idioma por `LaunchOptions` solo para nombres por defecto (decisiones-interfaz.md). |
| 5 | Baja | Previa y rotación. SwiftUI usa `AVCaptureVideoPreviewLayer` con giro propio; AppCore entrega fotogramas por canal y `rotation` en el resultado. | VS:130-174, VS:293; CP:20-21. | El giro solo se muestra, no se edita en Ajustes (`video.setSettings.rotation` existe y lo usa Grabar). | Hueco claro: Flutter rota la imagen (horario). Sin selector de giro en Ajustes. |
| 6 | Baja | Códec en Windows. SwiftUI ofrece HEVC y H.264; en Windows `choices.codecs` solo trae `h264` y `normalized` fuerza H.264. | SM:87-96, SM:468. | Ninguno. | Hueco claro: no pintar selector si `codecs.length == 1`. |
| 7 | Baja | Perfil. SwiftUI guarda con `model.saveProfile()`; AppCore reparte la escritura entre `audio.setSettings` y `video.setSettings` (con `profileLock`). No existe un método genérico que guarde `projectsFolder`. | AS:105-110, VS:210-215; SM:228, SM:498. | Ninguno. | Informativo. |
| 8 | Baja | Tarjeta de salida de la barra lateral (`AudioDeviceMonitor`): no hay método propio. | ADM:34-39; web `device-card.js:19`. | Se deduce de `audio.settings` (`outputDeviceUID`) y `audio.devices` (`connected`, `name`); textos «Salida del sistema» / «Por defecto» / «Conectado» / «Sin conectar». | Hueco claro; lo implementa la carcasa, no esta pantalla. |
| 9 | Baja | Abrir permisos de cámara: SwiftUI llama a `x-apple.systempreferences`; AppCore abre `ms-settings:privacy-webcam` en Windows con el mismo método. | VS:323-327; CP:31-37. | El texto del botón dice «Ajustes del Sistema» también en Windows. | Resuelto: variante de texto por plataforma en ARB; en Windows «Abrir Configuración», nombre sin verificar en fuente oficial (decisiones-interfaz.md). |
| 10 | Baja | Estado de «Verificando/Instalando» y barra de descarga no vienen en `models.progress` (solo fracción de descarga). | SM:386-388, SM:354-361. | Para ver «Verificando…» hay que recargar `models.list` o esperar `models.changed`. | Informativo. |

## 10. Partes de trabajo sugeridas

| Parte | Ficheros Dart | Tamaño | Agente |
| --- | --- | --- | --- |
| A. Contrato y stores | `contract/settings.dart`, `contract/audio.dart`, `contract/video.dart`, `features/settings/settings_store.dart`, `audio_store.dart`, `video_store.dart`, `library_store.dart` + fixtures en `Contract/fixtures/{settings,audio,video}/` | L | `tf-flutter` (Sonnet) |
| B. Carcasa y pestañas | `settings_screen.dart`, `widgets/settings_group.dart`, `widgets/info_row.dart` (o kit), tabs | S | `tf-flutter-mech` (Haiku) |
| C. Pestaña Audio | `audio_tab.dart`, `widgets/input_meters.dart` (`CustomPainter`), `widgets/rate_mismatch.dart`, `widgets/latency_status.dart` | M | `tf-flutter` (Sonnet) |
| D. Hoja de calibración | `sheets/calibration_sheet.dart` | M | `tf-flutter` (Sonnet) |
| E. Pestaña Cámara y vídeo | `video_tab.dart`, `widgets/camera_preview_box.dart` (canal `preview`, rotación, barras de color), `widgets/offset_field.dart`, `widgets/export_group.dart` | L | `tf-flutter` (Sonnet) |
| F. Pestaña Biblioteca | `library_tab.dart`, `widgets/model_row.dart`, `widgets/tools_group.dart`, `widgets/relocation_progress.dart`, diálogos | M | `tf-flutter` (Sonnet) |
| G. Idioma | `widgets/language_group.dart`, preferencia en `shared_preferences` | S | `tf-flutter-mech` (Haiku) |
| H. Textos | claves de apartado 8 en `app_es.arb` y `app_en.arb` | M | `tf-flutter-mech` (Haiku) |
| I. Tests | `test/features/settings/*`, goldens | M | `tf-flutter` (Sonnet) |

Orden: A, luego B; C, D, E, F en paralelo; G y H al final. A y E dependen de cerrar el desvío 1 (núcleo, antes de la ola 3); el desvío 4 está resuelto.

## 11. Criterios de aceptación

Capturas de referencia a igualar (SwiftUI en Mac con `--screen` equivalente; `VideoDemo` en VS:396-416 da dos cámaras simuladas):

| Estado | PNG |
| --- | --- |
| Audio, sin calibrar y con dispositivos | `settings-audio-uncalibrated.png` |
| Audio, aviso de frecuencia distinta | `settings-audio-ratemismatch.png` |
| Audio, dispositivo elegido desconectado | `settings-audio-disconnected.png` |
| Hoja midiendo, éxito, fallo `noSignal`, error | `settings-cal-running.png`, `-success.png`, `-failure.png`, `-error.png` |
| Cámara y vídeo, cámara simulada | `settings-video-simulated.png` |
| Cámara y vídeo, sin cámara y permiso denegado | `settings-video-nocamera.png`, `-denied.png` |
| Biblioteca, modelo instalado / descargando / fallo | `settings-library-model-*.png` |
| Biblioteca, moviendo carpeta al 40 % | `settings-library-moving.png` |
| Idioma en inglés | `settings-library-language-en.png` |

Tests de store (con `MockCore`): `audio.setSettings` envía `null` explícito para «Salida del sistema», «Ninguna» y «Sin asignar» y omite lo que no cambia; `audio.setMeters` true/false al cambiar de pestaña; `video.setSettings` con `cameraUID: null` frente a ausente; `video.preview.start/stop` al entrar y salir de la pestaña y al cambiar de cámara; `models.progress` y `models.changed` (éxito y fallo); `library.relocate` con `move`/`point`, progreso y error `work-in-progress`; `video.camerasChanged` recarga; el `audio.calibrate` se resuelve a la vez que llegan eventos `audio.calibration` (la respuesta no debe duplicar el estado).

Tests de widget: `InputMeters` (altura 28 × nivel, sin niveles no pinta); selector de resolución y fps con las opciones de `video.cameras`; ocultar selector de códec con un solo códec; diálogo de carpeta con tres botones; deshabilitado de «Cambiar carpeta» durante el traslado.

Solo Jorge puede probarlo con hardware o de oído:

1. Calibrar con la Flex Prime real: cable, rig vacío, resultado en ms frente a la medida previa de la web y SwiftUI (misma cifra con 0,1 ms de tolerancia); fallos reales de `saturated` y `unstable`.
2. Desenchufar y volver a enchufar la interfaz de audio y la pedalera con la hoja abierta y con la pestaña visible; que los medidores se apaguen y vuelvan.
3. Cambiar la frecuencia del dispositivo desde el panel del sistema y comprobar el aviso (en Mac la frecuencia se pide; en Windows no se cambia).
4. Cámara real en Mac: primera petición de permiso, denegado, concedido tras volver de Ajustes del Sistema; Continuity Camera apareciendo y desapareciendo.
5. Vista previa a 720p con 30 fps sin cortes y rotada a 90°, 180° y 270° (rotación guardada desde Grabar); que no se abra una segunda captura con Grabar abierta.
6. Desfase por defecto: que el valor guardado sea el que empieza la siguiente toma en Grabar.
7. Cambio de carpeta con una biblioteca real grande en un disco externo (copia, verificación, borrado del original; cancelar a mitad no corresponde: no hay método).
8. Descarga real del modelo (varios GB): progreso, corte de red, fallo por hash.
9. Actualizar yt-dlp con red real y volver a la embebida.

## Idioma (nuevo en la 7f)

Decisión de Jorge: español e inglés, selector «Idioma: Sistema / Español / English», guardado en las preferencias de la interfaz (`shared_preferences`, `arquitectura.md:96`), no en el perfil del núcleo.

- **Dónde encaja:** un `TfSettingsGroup` nuevo llamado «Idioma» al final de la pestaña `Biblioteca`. Es el único sitio de Ajustes que no es un dispositivo (Audio y Cámara y vídeo describen hardware del perfil) y ya agrupa cosas de la app (carpeta, modelos, herramientas). El texto «Se guarda en tu perfil de equipo» (SV:14) no sería cierto para esta fila; la nota del grupo debe decir que se guarda en esta aplicación. Resuelto: grupo «Idioma» al final de la pestaña `Biblioteca`, control segmentado; función nueva sin referencia, se enseña a Jorge en la revisión de la ola 1 (decisiones-interfaz.md).
- **Control a imitar:** `InfoRow` (SV:69-81) con `Picker` segmentado de tres opciones, igual que «Frecuencia de trabajo» (AS:136-142, `.pickerStyle(.segmented)`, `frame(width: 220)`). Con tres etiquetas más largas («Sistema», «Español», «English») el ancho de 220 queda justo. Resuelto: el ancho (260-300) se fija por captura en la revisión de la ola 1 (decisiones-interfaz.md).
- **Textos:** `settings_lang_title` «Idioma», `settings_lang_label` «Idioma», `settings_lang_system` «Sistema», `settings_lang_es` «Español», `settings_lang_en` «English» (los nombres de idioma no se traducen). Resuelto: el grupo no lleva nota (decisiones-interfaz.md).
- **Comportamiento:** el cambio se aplica al momento (sin reiniciar) y también debe respetar `--locale es|en` del arranque (`arquitectura.md:108`). Los textos del núcleo llegan por código y argumentos y se componen en Dart en el idioma elegido (decisiones-interfaz.md); los nombres por defecto nuevos los genera el núcleo en el idioma recibido en `LaunchOptions`.
