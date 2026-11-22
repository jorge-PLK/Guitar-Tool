# Ficha de pantalla · Backing (apartados 5 y 9)

Ola: <n>. Área del puente: `study`. Destino: `FlutterApp/lib/features/backing/`.
Solo los apartados 5 (Contrato que usa) y 9 (Desvíos detectados). Verificado contra el código el 22/11/2026.

Abreviaturas de fichero: `SM` = `Packages/AppCore/Sources/AppCore/StudyMethods.swift`, `SE` = `.../StudyEdits.swift`, `ST` = `WinApp/Web/backing/store.js`, `SCR` = `WinApp/Web/screens/backing.js`, `SD` = `WinApp/Web/backing/section-drag.js`.

## 5. Contrato que usa

Recuento: 28 métodos (12 en `SM`, 16 en `SE`) y 5 eventos emitidos (`study.state`, `study.position`, `study.levels`, `study.analysis`, `study.guitars`). `study.error` tiene DTO (`SM:158`) y `WinApp/Web` lo escucha (`ST:173`), pero nada lo emite en `AppCore` (ver D-12).

### Orden de llamadas al abrir un tema (WinApp/Web)

1. `Backing()` resuelve el tema y, en un `useEffect([id])`, llama `openStudy(id)` (`SCR:131-136`). Antes lee la preferencia local de «acordes expandidos» (solo interfaz).
2. `openStudy` pone `status='loading'` y vacía transporte, niveles y posición (`ST:56-68`). Si el transporte es mock, importa `mock-study.js` (`ST:68`).
3. `call('study.open', { projectId })` (`ST:69`). Devuelve `StudyOpenResult` con todo el estado (análisis, secciones, guitarras, bucles guardados, transporte). El cliente separa `transport` del resto: `study.value = rest`, `applyTransport(t)`, `status='ready'` (`ST:70-74`). Un `loadError` en el resultado limpia el aviso de audio (`ST:73`).
4. Si falla: `openError = {code, message}` y `status='error'` (`ST:77-81`). Un `open` obsoleto (cambio rápido de tema) se descarta con un `token` (`ST:58`, `ST:68`).
5. Los listeners de eventos se registran al cargar el módulo, no al abrir (`ST:164-173`, `ST:205`, `ST:226`); cada uno ignora el evento si `status !== 'ready'`.
6. Dentro de `study.open` el núcleo hace, en este orden (`SM:277-315`): valida el UUID; carga `project.json`; `close()` del tema anterior; lee el perfil (salida de audio, volumen master); crea sesión, audio y controlador; si hay `audio.*` activo, engancha el reproductor a la sesión de guitarra; si el tema está separado y no hay análisis vigente, pide `ensureAnalysis` a la cola; arranca el ticker de 30 Hz (`SM:312`). Tras la respuesta empiezan `study.position` y `study.levels`.
7. Si después `guitars.process == "processing"`, cada `study.state` provoca `study.snapshot` (`ST:226-232`). Si llega `study.analysis` con `state:"ready"`, también `study.snapshot` (`ST:205-210`).
8. Grabar abre `study.open` y después `record.open` en la misma entrada (`WinApp/Web/screens/record.js:105`); al salir cierra `record.close` y `study.close`, salvo si va a Montaje.
9. Al salir de la pantalla o cambiar de tema: `study.close` (`SCR:136`, `ST:92`). Los errores de `study.close` solo se registran en consola.

### Tabla de contrato

DTO: tipos en el subapartado «Tipos» (líneas de `SM`/`SE` donde se declaran). Los mismos DTO están en `contrato-tipos-b.md` (sección study); si discrepan, manda el código (`AC/StudyMethods.swift`, `StudyEdits.swift`). Respuesta entre paréntesis.

| Acción del usuario o momento | Método / evento | DTO Swift (params → respuesta) | Uso en WinApp/Web |
| --- | --- | --- | --- |
| Entrar en Backing / cambiar de tema | `study.open` (`SM:233`) | `StudyOpenParams` SM:163 → `StudyOpenResult` SM:124 | `ST:69`; `SCR:131` |
| Salir de Backing | `study.close` (`SM:234`) | `Empty` → `Empty` | `ST:92`; `SCR:136` |
| Releer estado sin reabrir (tras análisis o guitarras) | `study.snapshot` (`SE:122`) | `Empty` → `StudyOpenResult` | `ST:194` (`refreshSnapshot`) |
| Play | `study.play` (`SM:235`) | `Empty` → `StudyTransport` SM:47 | `ST:109` |
| Pausa | `study.pause` (`SM:238`) | `Empty` → `StudyTransport` | `ST:110` |
| Clic en barra, acorde o rejilla; arrastre del cursor | `study.seek` (`SM:239`) | `StudySeekParams` SM:164 → `StudyTransport` | `ST:160`; limita el arrastre con `SCRUB_INTERVAL_MS` y fuerza el envío al soltar (`ST:152-160`) |
| Velocidad | `study.setRate` (`SM:242`) | `StudyRateParams` SM:165 → `StudyTransport` | `ST:112` (recorta a `RATE_MIN..RATE_MAX` en el cliente) |
| Transposición en semitonos o ajuste fino | `study.setTranspose` (`SM:245`) | `StudyTransposeParams` SM:166 → `StudyTransport` | `ST:113-114` (envía `semitones` o `fineCents`, nunca ambos) |
| Capo | `study.setCapo` (`SM:251`) | `StudyCapoParams` SM:167 → `StudyTransport` | `ST:115` |
| Bucle por arrastre, por sección o quitar | `study.setLoop` (`SM:254`) | `StudyLoopParams` SM:168 → `StudyTransport` | `ST:116-117`; `{}` quita el bucle |
| Metrónomo on/off | `study.setMetronome` (`SM:269`) | `StudyMetronomeParams` SM:171 → `StudyTransport` | `ST:118-119`; el cliente pasa `gainDB` solo si se le da |
| Fader, mute o solo de un canal | `study.setMix` (`SM:259`) | `StudyMixParams` SM:169 → `StudyTransport` | `ST:141-148` (actualiza en local antes, optimista) |
| «Sin guitarras» | N × `study.setMix` (`muted`) | igual | `SCR:71` (un `setMix` por canal de guitarra) |
| Volumen master | `study.setMaster` (`SM:266`) | `StudyMasterParams` SM:170 → `StudyTransport` | `ST:120` |
| Analizar / Reintentar | `study.analyze` (`SE:123`) | `Empty` → `StudyEditState` SE:32 | `ST:203`; avance por `study.analysis` |
| Corregir tonalidad (o volver a la detectada con `key:null`) | `study.setKey` (`SE:124`) | `StudySetKeyParams` SE:48 → `StudyEditState` | `ST:139` |
| Cambiar un acorde en modo edición | `study.setChord` (`SE:125`) | `StudySetChordParams` SE:49 → `StudyEditState` | `ST:135` (envía `index`, no `label`) |
| Quitar correcciones de un rango | `study.removeChordOverrides` (`SE:126`) | `StudyChordRangeParams` SE:50 → `StudyEditState` | `ST:136` |
| Quitar todas las correcciones | `study.clearChordOverrides` (`SE:134`) | `Empty` → `StudyEditState` | `ST:137` |
| Partir un acorde | `study.splitChord` (`SE:137`) | `StudySplitChordParams` SE:51 → `StudyEditState` | `ST:138` |
| Marcar una sección | `study.markSection` (`SE:138`) | `StudyMarkSectionParams` SE:52 → `StudyEditState` (`added` = id nuevo) | `ST:219` (`snap` no se envía: `none`) |
| Renombrar, recolorear, solo, mover bordes | `study.updateSection` (`SE:139`) | `StudyUpdateSectionParams` SE:60 → `StudyEditState` | `ST:220`; `SD:69` (arrastre, `snap:'none'`) |
| Vista previa durante el arrastre de un borde | `study.previewSectionEdge` (`SE:142`) | `StudyPreviewSectionEdgeParams` SE:54 → `StudyPreviewSections` SE:30 | `SD:77` (~10/s, vale la última respuesta) |
| Flechas de empuje de un borde (⌥ = compás) | `study.nudgeSectionEdge` (`SE:145`) | `StudyNudgeSectionParams` SE:55 → `StudyEditState` | `ST:221` |
| Borrar una sección | `study.deleteSection` (`SE:152`) | `StudyDeleteSectionParams` SE:53 → `StudyEditState` | `ST:222` |
| «Aplicar» secciones (guarda y aplica a guitarras) | `study.applySections` (`SE:158`) | `Empty` → `StudyEditState` | `ST:223` |
| Descartar cambios de secciones | `study.discardSections` (`SE:164`) | `Empty` → `StudyEditState` | `ST:224` |
| Renombrar una guitarra | `study.renameGuitar` (`SE:167`) | `StudyRenameGuitarParams` SE:56 → `StudyEditState` | `ST:218` |
| Separar guitarras en estéreo | `study.setGuitarStereo` (`SE:176`) | `StudyGuitarStereoParams` SE:57 → `StudyEditState` | `ST:217` |
| Cambia el transporte (cualquier causa) | evento `study.state` (`SM:380`) | `StudyTransport` | `ST:171`, `ST:226`; actualiza `outputName`; relee snapshot si guitarras «processing» |
| Reloj y cursor (≤ 30 Hz) | evento `study.position` (`SM:468`) | `StudyPositionEvent` SM:144 | `ST:164` |
| Vúmetros (≤ 30 Hz) | evento `study.levels` (`SM:477`) | `StudyLevelsEvent` SM:154 | `ST:172` |
| Cambia el estado del análisis | evento `study.analysis` (`SE:315`) | `StudyAnalysisEvent` SE:43 | `ST:205` |
| Cambia el trabajo de guitarras | evento `study.guitars` (`SE:399`) | `StudyAnalysisEvent` (mismo tipo; `state` = `idle`/`processing`/`failed`) | `ST:169` (relee snapshot) |

Efectos y garantías del núcleo (comprobados):

- Todo método de transporte y edición devuelve el estado ya aplicado y además provoca un `study.state` coalescido por turno (`SM:342-347`, `SM:373-382`, `SE:193-200`). El cliente no necesita reconsultar.
- `previewSectionEdge` no cambia estado, no guarda y no emite `study.state` (`SE:482-483`).
- Los eventos `study.position` y `study.levels` salen con separación mínima de 0,9/30 s (`SM:11-13`). `study.levels` se calla al quedar en silencio, tras una última emisión a -120 dB (`SM:471-476`). `study.position` se emite parado solo si cambia (`SM:464`).
- Sin tema abierto, todo método salvo `study.open` y `study.close` devuelve `not-open` (`study.close` no falla) (`SM:343`, `SE:195`). El cliente lo ignora (`ST:101`, `ST:184`).
- El volumen master se guarda en el perfil con rebote (`SM:351-360`); las ediciones, por `StudySession` con rebote (`SE:5-7`).
- Códigos de error: `bad-params`, `not-open`, `not-found` (id de sección, `SE:270`), `internal` (`SM:284`), `audio-unavailable` (aviso de audio que el cliente muestra, `ST:99`), `load-failed` (`loadError` del reproductor, o tema sin stems que reproducir; solo en `study.play`, `StudyBacking.swift:127,128`), `no-analysis` (`SE:411`), `analysis-unavailable` (`SE:321`, `SE:338`), `not-separated` (`SE:323`), `cannot-split` (`SE:446`, `SE:450`), `section-not-created` (`SE:476`), `save-failed` (`SE:161`, `SE:183`). Los demás de la cola pasan por `JobEngine.map` (`SE:326`).

### Tipos

Convención: JSON con los nombres de campo de Swift. `?` = opcional (un `Optional` nil se omite: clave ausente, nunca `null`, sin `encode(to:)` a mano salvo el `init(from:)` de `StudyUpdateSectionParams`; Dart debe tratar ausente y `null` igual salvo `StudyUpdateSectionParams.color`; en parámetros, ausente significa «no cambia», salvo indicación). Tiempos en segundos (Double). Ganancias en dB. `Empty` = objeto vacío.

**Enums (todos son `String` en el JSON; no hay tipo enum en Swift salvo `GuitarRole` y `AudioMode`)**

| Campo | Valores |
| --- | --- |
| `StudyChannel.kind`, `StudyEmptyStem.kind` | `vocals`, `drums`, `bass`, `guitar`, `piano`, `other` (`StemKind.rawValue`, orden de canales `SM:17-19`; nombres «Voz», «Batería», «Bajo», «Guitarra», «Piano», «Resto») |
| `StudyChannel.guitarRole`, `StudyRenameGuitarParams.role`, claves de `StudyGuitarsInfo.names` | `rhythm`, `left`, `right`, `lead` (`Packages/Store/Sources/Store/Guitars.swift:7-8`). Nombres por defecto: «Guitarra rítmica», «Guitarra izq.», «Guitarra der.», «Guitarra solista» (`Guitars.swift:13-16`) |
| `StudyChannel.id` | `kind` para stems; `GuitarRole.trackID` para guitarras separadas (`guitar_rhythm`, `guitar_L`, `guitar_R`, `guitar_lead`) (`SM:391`, `SM:396`). Es la clave de `StudyLevelsEvent.channels` y el `channel` de `StudyMixParams` |
| `StudyAnalysisInfo.state`, `StudyAnalysisEvent.state` (análisis) | `missing`, `analyzing`, `ready`, `failed` (`SE:254-261`; `failed` lleva `error`) |
| `StudyGuitarsInfo.process`, `StudyAnalysisEvent.state` (en `study.guitars`) | `idle`, `processing`, `failed` (`SE:24`, `SE:376-384`) |
| `StudyAudioInfo.mode` | `simulated`, `device` (`AudioMode`, `StudyAudio.swift:6-10`) |
| `StudyMarkSectionParams.snap` | `none` (por defecto), `beat`, `bar` (`SE:469-474`) |
| `StudyUpdateSectionParams.snap` | `none` (por defecto), `beat`, `bar`, `chord` (`SE:503-506`) |
| `StudySetKeyParams.key` | `"C:maj"`, `"A:min"` (raíz en sostenidos + `:maj`/`:min`); `null` quita la corrección (`SE:406-409`) |
| `StudySetChordParams.label` | `"C:min"`, `"F#:7"`, `"N"` (`SE:431`) |
| `StudyChord.index`, `StudySetChordParams.index` | 0...169 (0...167 acordes): `raíz*14 + calidad` (calidades en orden min, maj, dim, aug, min6, maj6, min7, minmaj7, maj7, 7, dim7, hdim7, sus2, sus4); 168 = desconocido; 169 = sin acorde (`SE:426`; `WinApp/Web/backing/chords.js:3-10`) |
| `StudyUpdateSectionParams.color`, `StudySectionInfo.color` | índice de paleta `0...6` (`paletteCount` = 7, `Store/SectionEditor.swift:89`) (`SE:500-501`); ausente en params = no cambia; `null` = automático |

**Transporte**

`StudyTransport` (`SM:47`)

| Campo | Tipo | Notas |
| --- | --- | --- |
| `playing` | Bool | |
| `position` | Double | s |
| `duration` | Double | s |
| `rate` | Double | factor de velocidad |
| `transpose` | Int | semitonos |
| `fineCents` | Double | centésimas de semitono |
| `capo` | Int | traste |
| `metronome` | `StudyMetronome` | `on` Bool, `gainDB` Double, `available` Bool (= hay cuadrícula de pulsos, `SM:408`) |
| `loop` | `StudyLoop?` | `start` Double, `end` Double, `name` String?; no se guarda en el proyecto (`StudyBacking.swift:20-21`) |
| `masterGainDB` | Double | del perfil |
| `channels` | `[StudyChannel]` | `id` String, `kind` String, `guitarRole` String?, `name` String, `gainDB` Double, `muted` Bool, `solo` Bool |
| `anySolo` | Bool | |
| `audioError` | String? | último fallo de salida o de reproducción |
| `outputName` | String | aparato de salida; en Windows se conoce al abrir la salida |

Rango del fader: -60...+6 dB (`StudyBacking.swift:12`). Rangos que recorta el núcleo: `rate` 0.5...2.0; `transpose` -12...12 semitonos; `fineCents` -50...50; `capo` 0...12; `gainDB` (canal, master, metrónomo) -60...6; `seek` 0...`duration`.

**Abrir y snapshot**

`StudyOpenResult` (`SM:124`): `projectId` String (UUID), `title` String, `artist` String?, `duration` Double, `sampleRate` Double, `loadError` String?, `audio` `StudyAudioInfo{mode, outputName}`, `transport` `StudyTransport`, `emptyStems` `[StudyEmptyStem{kind, name}]`, `usesSeparatedGuitars` Bool, `analysis` `StudyAnalysisInfo`, `chordOverrides` `[StudyOverrideInfo{start, end, index}]`, `sections` `[StudySectionInfo]`, `unappliedSections` Bool, `loops` `[StudySavedLoop{id, name, start, end}]`, `guitars` `StudyGuitarsInfo`.

`StudyAnalysisInfo` (`SM:80`): `state` String, `error` String?, `beats` `[Double]`, `downbeats` `[Double]`, `bpm` Double?, `beatsPerBar` Int?, `chords` `[StudyChord]`, `key` `StudyKey`.

`StudyChord` (`SM:65`): `start`, `end` Double; `index` Int; `name` String (sin transponer: `StudyKitBridge.chordName(index)`, `SE:233`); `overridden` Bool.

`StudyKey` (`SM:73`): `detected`, `override`, `effective` String? (formato `C:maj`); `confidence` Double?.

`StudySectionInfo` (`SM:102`): `id` String (UUID), `name` String, `start`, `end` Double, `solo` Bool, `color` Int?, `paletteIndex` Int? (color efectivo para dibujar, `SE:247-250`).

`StudyGuitarsInfo` (`SE:20`): `stereoSplit` Bool, `usesSeparatedGuitars` Bool, `names` `[String: String]` (clave = rol), `process` String, `error` String?, `saveError` String?.

`StudyEditState` (`SE:32`), respuesta de todas las ediciones: `analysis`, `chordOverrides`, `sections`, `unappliedSections`, `loops`, `guitars` (como en `StudyOpenResult`), `added` String? (id de la sección recién marcada; solo `markSection`), `transport` `StudyTransport`. No trae `title`, `emptyStems` ni `audio`.

`StudyPreviewSections` (`SE:30`): `sections` `[StudySectionInfo]` (copia recortada; no toca el estado).

**Parámetros** (`SM:163-171`, `SE:48-57`)

| Tipo | Campos |
| --- | --- |
| `StudyOpenParams` | `projectId` String (UUID, obligatorio) |
| `StudySeekParams` | `seconds` Double |
| `StudyRateParams` | `rate` Double |
| `StudyTransposeParams` | `semitones` Int?, `fineCents` Double? (cada uno solo se aplica si viene) |
| `StudyCapoParams` | `capo` Int |
| `StudyLoopParams` | `start` Double?, `end` Double?, `name` String?. Sin `start` o sin `end` finitos quita el bucle; si `end < start` se usa `end = start` (`SM:256`) |
| `StudyMixParams` | `channel` String (id de canal; si no existe, `bad-params`), `gainDB` Double?, `mute` Bool?, `solo` Bool? |
| `StudyMasterParams` | `gainDB` Double |
| `StudyMetronomeParams` | `on` Bool?, `gainDB` Double? |
| `StudySetKeyParams` | `key` String? |
| `StudySetChordParams` | `start`, `end` Double (0 ≤ start < end), `index` Int?, `label` String? (exactamente uno de los dos) |
| `StudyChordRangeParams` | `start`, `end` Double (`end >= start`) |
| `StudySplitChordParams` | `at` Double (parte por el pulso más cercano; ese pulso debe quedar a más de 50 ms de ambos extremos, `SE:13`, `SE:449`) |
| `StudyMarkSectionParams` | `start`, `end` Double (0 ≤ start < end ≤ duración), `solo` Bool?, `snap` String? |
| `StudyUpdateSectionParams` | `id` String, `name` String?, `start` Double?, `end` Double?, `solo` Bool?, `snap` String?, `color` Int? (ausente ≠ `null`, `SE:59`) |
| `StudyPreviewSectionEdgeParams` | `id` String, `start` Bool (true = borde inicial), `to` Double |
| `StudyNudgeSectionParams` | `id` String, `start` Bool, `forward` Bool, `bar` Bool? (true = a límites de compás; false = a límites de acorde, `SE:148`) |
| `StudyDeleteSectionParams` | `id` String |
| `StudyRenameGuitarParams` | `role` String, `name` String (vacío = nombre por defecto, `SE:172-173`) |
| `StudyGuitarStereoParams` | `on` Bool |

**Eventos**

| Evento | Payload |
| --- | --- |
| `study.state` | `StudyTransport` |
| `study.position` | `StudyPositionEvent{seconds Double, playing Bool}` |
| `study.levels` | `StudyLevelsEvent{channels: {id → StudyMeter{rmsDB Double, peakDB Double}}}`; -120 = silencio (`SM:478`); solo los ids de `channels` |
| `study.analysis` | `StudyAnalysisEvent{state String, error String?}` |
| `study.guitars` | `StudyAnalysisEvent{state String, error String?}` |
| `study.error` (no se emite) | `StudyErrorEvent{code String, message String}` `SM:158` |

## 9. Desvíos detectados

Regla de clasificación: `docs/flutter/desvios.md:5-13`. «SwiftUI» = `App/Sources`. «Hueco claro» lo arregla `tf-implementer` en `AppCore`; «decisión» pregunta a Jorge; «interfaz» vive en Dart.

| # | Desvío | Evidencia SwiftUI | Qué falta o difiere en AppCore | Clasificación |
| --- | --- | --- | --- | --- |
| D-1 | A/B de tomas dentro de la mezcla (Backing con tomas grabadas) | `BackingController.swift:28-42` (estado A/B), `:255` (`// MARK: A/B`) | El controlador portado no lo lleva: `StudyBacking.swift:5-6` («El A/B de tomas (Fase 3) es de la parte de Grabar y no se porta aquí»). No hay método `study.*` de A/B. La parte de Grabar sí existe (`record.*`) | Decisión de Jorge: ¿el A/B se hace en Backing o ya vive en `record.*`/`takeview`? Hay que comprobar si `record.*` cubre «Tú en directo» y el silencio del stem de guitarra en B (`BackingController.swift:81`, `:42`) |
| D-2 | Arrastre de bordes de sección con imán a acorde y ⌥ a compás | `SectionBoxes.swift:161-172`; `SectionGridBoxes.swift:28`, `:88`; `BackingTimeline.swift`; lógica en `Packages/Store/Sources/Store/SectionEdgeDrag.swift:6-16` (imán al límite de acorde dibujado o al compás con ⌥, siempre incluyendo el borde original) | `updateSection` admite `snap: chord` (`SE:518`, usa `chordBoundaries` sin el borde original y sin variante de compás en arrastre) y `previewSectionEdge` no admite `snap` (`SE:484-491`). `WinApp/Web` rehace el imán en JS (`SD:60-69`) y manda `snap:'none'` | Hueco claro: `previewSectionEdge` y `updateSection` deben dar el resultado con imán (acorde, y compás con ⌥) con la regla de `SectionEdgeDrag` (incluye `original`). Posición → tiempo por celdas es geometría de vista: interfaz (Dart). Regla 5 de `desvios.md`: no replicar el imán en Dart |
| D-3 | Bucle por arrastre con ajuste a acorde o compás (⌥) y nombre | `BackingTimeline.swift:303-305`, `ChordGrid.swift:287-288` (`StudyBridge.snap(session.beats, r, bar:)`; nombre `"compases"`/`"acordes"`) | `study.setLoop` (`SM:254`) no tiene `snap`; el ajuste a pulso/compás solo existe en `StudyEditsBridge.snap` (interno, `StudyEditsBridge.swift:19`), usado por `markSection`. `WinApp/Web` lo calcula en el cliente (`WinApp/Web/backing/grid.js:284`) | Hueco claro: añadir `snap` (`none`/`bar`) a `StudyLoopParams` o ajustar el rango en el núcleo; el nombre del bucle ya viaja (`name`). Ojo: el ajuste de SwiftUI sale de los límites de los acordes elegidos y del compás (`BeatGrid.snap`, rango por compases); la cuenta tiene que salir igual |
| D-4 | Monitores `NSEvent`: Espacio (play/pausa), Supr/Retroceso (borra sección seleccionada), Esc (deselecciona), ⌥ al soltar | `SectionGridBoxes.swift:114-135` (Espacio, `keyCode 49`, sin modificadores, no actúa escribiendo ni con hoja abierta), `:141-167` (Supr 51/117, Esc 53); ⌥ vía `NSEvent.modifierFlags` en `SectionBoxes.swift:172`, `:382`, `ChordGrid.swift:287`, `BackingTimeline.swift:303` | No es de núcleo: borrar usa `study.deleteSection` y play/pausa `study.play`/`study.pause`, que ya existen. `WinApp/Web` lo rehace en DOM (`SCR:153`, `WinApp/Web/backing/sections.js:49`) | Interfaz: Dart (`Shortcuts`/`Focus`; reproducir las condiciones de guarda del monitor). Consta, no es desvío de núcleo |
| D-5 | `study.setMetronome` admite `gainDB` y SwiftUI no tiene control | `BackingTimeline.swift:463` (solo `Toggle("Metrónomo")`); `BackingController.swift:163-166` (`setMetronome(_ on:)`) | `StudyMetronomeParams.gainDB` (`SM:171`) y `StudyMetronome.gainDB` existen; en SwiftUI no hay ajuste de volumen del clic en Backing | Decisión de Jorge: ¿se ofrece fader del clic en Flutter (el método ya lo permite) o se omite para igualar SwiftUI? Recomendado: omitir |
| D-6 | Bucles guardados (`study.open.loops`) sin interfaz | `StudySession.swift:250-259` (`add/update/removeLoop`); ninguna vista fuera de `StudySession` los usa (grep `addLoop`, `removeLoop`, `.loops` en `App/Sources`) | `loops` viaja en `StudyOpenResult` y `StudyEditState`, pero no hay método para crear, renombrar ni borrar | Decisión de Jorge: el dato existe y SwiftUI no lo muestra. Recomendado: Flutter no los muestra y no se añaden métodos (el bucle activo sigue sin guardarse) |
| D-7 | Formas de acorde (diagramas) con capo | `BackingTimeline.swift:313` (`ChordShapes.shape(for:capo:)` de StudyKit); `ChordDiagram.swift` | No hay método de formas. `WinApp/Web` las reimplementa en JS (`WinApp/Web/backing/chords.js:1-2`, `:103-104`; `diagram.js`) | Hueco claro: el comportamiento lo define StudyKit; falta un método (p. ej. `study.chordShape{index, capo}` o formas en el snapshot). Flutter no debe portar `ChordShapes` a Dart (regla 5) |
| D-8 | Nombre de acorde transpuesto (y tonalidad mostrada) | Nombres transpuestos y `SpanishNotes` en `BackingView.swift` (según `chords.js:1`) y StudyKit `ChordLabel` | `StudyChord.name` sale sin transponer (`SE:233`); `StudyKey` solo da `C:maj`. `WinApp/Web` transpone y traduce a «La menor» en JS (`WinApp/Web/backing/chords.js:22`, `:36-58`), incluido el camino inverso al corregir tonalidad (`storedKeyLabel`, `:58`) | Hueco claro: el núcleo debe dar el nombre ya transpuesto (según `transpose`) o un método de formato; el puente solo devuelve índice sin transponer. Mismo criterio que D-7 |
| D-9 | «Sin guitarras» | `BackingView.swift:127-131` (botón), `BackingController.swift:242-253` (silencia stem o todas las pistas separadas; segunda pulsación restaura) | No hay método propio: son N `study.setMix` (`mute`). `WinApp/Web` lo hace así (`SCR:71`) | Interfaz si se acepta el patrón; cada `setMix` provoca su `study.state`. Solo se vuelve desvío de núcleo si importa la atomicidad (sin parpadeo de mezcla). Dato de interfaz: «activo» = todas las guitarras con `muted` en `StudyTransport.channels`; mostrar el botón solo si hay canal `kind == "guitar"` (`hasGuitar`, `BackingController.swift:243`) |
| D-10 | Edición de secciones en dos tiempos | `StudySession`: secciones en edición hasta «Aplicar» (`hasUnappliedSections`) | El puente lo cubre (`unappliedSections`, `applySections`, `discardSections`). Sin desvío, anotado por cómo se usa | Descartado |
| D-11 | `study.setChord` con `label` | Mac elige acorde por índice del selector | `label` existe y no se usa en `WinApp/Web` (`ST:135` envía `index`) | Descartado (sin impacto) |
| D-12 | Evento `study.error` | n/a | `StudyErrorEvent` (`SM:158`) declarado y escuchado en `ST:173`; ningún `emit("study.error", ...)` en `AppCore` (grep en `Packages/AppCore/Sources`). Los fallos de audio llegan por `StudyTransport.audioError` y el código `audio-unavailable` | Hueco claro menor: o se emite o se quita del DTO y del cliente. Flutter debe leer `audioError` del transporte, no `study.error` |

Notas de verificación:

- Los desvíos D-1, D-2, D-3, D-5, D-6, D-7, D-8, D-9 salen de la lista del encargo y se han comprobado en el código. D-4 (monitores) también. D-8 y D-12 son nuevos respecto a esa lista.
- Lo que solo se valida con la pedalera o de oído (sonido del A/B, nivel del metrónomo, latencia de salida) no es hallazgo: queda para Jorge.
- Para D-3 y D-2 falta confirmar que la cuenta del imán da el mismo resultado numérico en `AppCore` y en `SectionEdgeDrag`; hay que cubrirlo con test en `AppCoreTests` al arreglarlo.
