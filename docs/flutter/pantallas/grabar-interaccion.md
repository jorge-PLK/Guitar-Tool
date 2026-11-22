# Ficha de pantalla · Grabar y «Ver toma» (apartados 6, 7 y 8)

Complementa `grabar.md` (apartados 1-4, 10 y 11) y `grabar-contrato.md` (5 y 9). Rutas relativas a `App/Sources/` salvo indicación. «Web» = `WinApp/Web/record/`. «Core» = `Packages/AppCore/Sources/AppCore/`. Hechos medidos en código; lo que depende de hardware u oído no se afirma.

## 6. Interacción

### 6.1 Teclado y atajos

Grabar **no tiene atajos de teclado propios**: ni `NSEvent`, ni `onKeyPress`, ni `.commands` (grep sobre `RecordView`, `RecordMixer`, `PunchTimeline`, `OffsetSheet`, `TakeViewer`). No hay barra espaciadora para grabar/parar ni para reproducir (tampoco en la web).

| Tecla / contexto | Efecto | Fichero:línea |
| --- | --- | --- |
| Esc en el visor «Ver toma» | Cierra el visor (`model.close(); onClose()`); con el diálogo de eliminar abierto, Esc cierra antes el diálogo (sistema) | `TakeViewer.swift:312` (`.keyboardShortcut(.cancelAction)`) |
| Esc en «Ajustar desfase» | **No cierra**: `.interactiveDismissDisabled(true)`; solo «Cancelar/Descartar toma» o «Guardar» | `OffsetSheet.swift:88` |
| Esc en «Añadir parte» | Cierra (comportamiento del sistema de la hoja; sin `cancelAction`) | `RecordView.swift:348` |
| Intro en «Añadir parte» | **No hace nada** (sin `defaultAction`); hay que pulsar «Añadir» | `RecordView.swift:349-351` |
| Intro / pérdida de foco en el campo de ms | Confirma el valor (`TextField(value:format:)` → `setOffset`, recorta a ±500) | `OffsetSheet.swift:58-60,105-110` |
| Esc / Intro en `confirmationDialog` | Cancelar / acción por defecto del sistema (sin `keyboardShortcut` propio) | `RecordView.swift:134-140`, `TakeViewer.swift:295-300` |
| VoiceOver incrementar/decrementar sobre un fader | ±1 dB | `BackingMixer.swift:309` |

### 6.2 Modificador ⌥ (único `NSEvent`)

`NSEvent.modifierFlags.contains(.option)` se lee en **cada evento de arrastre** del punch (`PunchTimeline.swift:74`): sin ⌥ la marca salta al compás más cercano; con ⌥ queda libre. Flutter: `HardwareKeyboard.instance.isAltPressed` leído en cada `onPointerMove`/`onPanUpdate`. La web hace lo mismo con `e.altKey` y lo manda al núcleo como `free` (`punch.js:41`; núcleo: `RecordController.swift:1075-1089`).

### 6.3 Arrastre de punch-in (`PunchTimeline.swift`)

| Aspecto | Valor |
| --- | --- |
| Gesto | `DragGesture(minimumDistance: 0)` sobre toda la pista (`contentShape(Rectangle())`), l.48-51. Un clic ya es el primer evento de arrastre |
| Dimensiones | pista alto 54 (`:14`), asa 6 de ancho × 54, centrada (`x-3`, `:41,43,63`); tramo punch ancho mínimo 2 (`:40`); cajas de sección ancho mínimo 2, alto 40 (`Self.height-14`), y=7 (`:34-35`) |
| Posición → tiempo | `x/ancho × duration`, recortado a `0...duration` (`:50,73`). **Sin desplazamiento de agarre**: la marca salta al puntero, no se arrastra relativa al punto de pulsación |
| Imán | sin ⌥: `ctl.timing.nearestBar(t)` = el *downbeat* más cercano (`RecordTiming.swift:47-50`; núcleo `RecordTiming.swift:52-55`); si no hay downbeats, `round(t/barSeconds)·barSeconds`. **No hay umbral**: siempre se engancha al compás más cercano. Con ⌥: sin imán |
| Qué asa se mueve | La decide el **primer evento** del gesto (`active == nil`, l.75-79): sin entrada → entrada; con entrada y sin salida → salida; con ambas → la más cercana al puntero (`abs(t-a) <= abs(t-b)`, empate → entrada). Se fija hasta soltar (`onEnded`: `active = nil`, l.51) |
| Entrada ≥ salida | Al mover la entrada a `t ≥ salida`: salida = `nil` (l.83) |
| Salida ≤ entrada | Al mover la salida a `t ≤ entrada`: se intercambian (salida = antigua entrada, entrada = `t`) **y `active` pasa a entrada** (l.85) |
| Borrar marcas | No hay gesto: se re-arman con el interruptor «Punch-in» (no verificado qué limpia; ver §9 de `grabar-contrato.md`) |
| Bloqueo | `Card … .disabled(ctl.isBusy)` (l.59): sin arrastre durante cuenta, grabación, guardado o desfase. El núcleo también lo exige (`guard phase == .idle`, `RecordController.swift:1076`) |
| Cadencia | Mac: sin límite (muta `ctl.punchIn/Out` en cada cambio). Web: como máximo un `record.setPunch` cada 50 ms + uno al soltar (`punch.js:9,53-58`) |
| Cabezal | Línea blanca 1 px alto 54 en `x(time)`, visible si `phase != .idle || time > 0` (l.44-46); no es arrastrable |
| Accesibilidad | Asas con etiqueta «Entrada del punch-in» / «Salida del punch-in» (l.64) |

Resuelto: como SwiftUI. Tras el intercambio, el asa activa pasa a la entrada (`PunchTimeline.swift:85`) (decisiones-interfaz.md, «Cerradas por la regla 1:1»). La web difiere y no se copia. Ejemplo de comportamiento: entrada 10, salida 20; arrastrar la salida a 5 deja entrada 5, salida 10, y volver a 15 da entrada 15, salida `nil`.

### 6.4 Faders y deslizadores

| Control | Gesto y valores | Fichero:línea |
| --- | --- | --- |
| `Fader` (Master expandido y canales de stems, guitarras y «Tú · parte») | Rango −60…+6 dB (`BackingController.faderRange`, `BackingController.swift:11`). `DragGesture(minimumDistance: 0)`: valor = posición absoluta del puntero en Y (un clic salta ahí, sin agarre relativo). **Imán a 0 dB si `abs(d) < 1,5`** (`snapDB`). **Doble clic = 0 dB** | `BackingMixer.swift:285,298-304` |
| Medidas | Fader 28×150 en el canal Master (`RecordMixer.swift:180`); carril ancho 6 radio 3; pomo 28×18 radio 4, centro en `h·(1−frac)`; canal 96 de ancho (`:185`) | `BackingMixer.swift:292-295`, `RecordMixer.swift:185` |
| Master compacto | `Slider` nativo −60…+6, ancho 40, `tint(TF.accent)`; imán `abs(v) < 1,5 → 0` al escribir | `RecordMixer.swift:71-72` |
| M / S | Botones 36×36 (`MixerToggle`); en la guitarra que sustituye la parte, M/S **no actúan** (`isForcedMuted`) y se ve silenciada | `BackingMixer.swift:265-268`, `RecordMixer.swift:96-103,138-142` |
| Entrada de guitarra | Solo medidor (sin gesto): barra 12×150 (expandido), 22×8 (compacto) | `RecordMixer.swift:207,84` |
| Web (a replicar) | Flechas ↑/→ +1 dB, ↓/← −1, Mayús ×3, Inicio = 0 dB; `role=slider`, tabulable; master compacto `<input range step=0.5>` con el mismo imán (`FADER_SNAP_DB = 1,5`) | `backing/mixer.js:58-65`, `backing/store.js:10-12`, `record/mixer.js:81-83` |

### 6.5 Menús y acciones de toma (no hay `.contextMenu` en Grabar)

La toma es un `Menu` con `primaryAction` (`RecordView.swift:271-292`): **clic = elegir la toma** (`ctl.selectTake`, l.286), la flecha del indicador (`menuIndicator(.visible)`, l.289) abre el menú. Todo el menú está `disabled(ctl.isBusy)` (l.289).

| Ítem | Acción | Deshabilitado si | Línea |
| --- | --- | --- | --- |
| Marcar como mejor | `markBest` (reasigna la mejor, recarga pistas) | ya es la mejor | 274, `RecordController.swift:780` |
| Ajustar desfase… | `adjustOffset` → abre la hoja 7.2 (`isNew = false`) | la toma no tiene vídeo (`videoFile == nil`) | 275, `RecordController.swift:752` |
| Punch-in | `startPunch(on:)`: elige la toma y activa el punch | nunca | 276, `RecordController.swift:787` |
| Borrar… | `deleting = id` → diálogo 7.3 | nunca | 278 |

Otros gestos: clic en el cuadro de una **parte** → `selectPart` (solo en reposo, solo si no es la activa; reinicia toma elegida, punch y recarga mezcla, `RecordView.swift:228`, `RecordController.swift:220-228`). Botón ▶ 32×32 de cada toma → «Ver toma»: `prepareToViewTake()` (pausa el transporte; falla si no está en reposo, `RecordController.swift:774-778`); deshabilitado si `isBusy`, sin `processedFile` o sin `songStart` (`RecordView.swift:252-267`).

Web (solo referencia; NO se copia: el menú de toma es como SwiftUI, decisiones-interfaz.md): clic en toma no elegida = elegir; **segundo clic en la elegida, clic derecho o ↓** abren el menú (`PopupMenu` anclado al botón, `ui.js:36-58`: ↑/↓ mueven, Esc y Tab cierran, clic fuera cierra, primer ítem activo con foco).

### 6.6 Foco

SwiftUI: sin `@FocusState` ni `.focusable` en estas vistas; los botones son `.buttonStyle(.plain)` (foco solo con «Acceso completo con teclado»). Foco inicial de las hojas = el del sistema (sin código). Web (a replicar): `Modal` enfoca `autofocus` (`input` en «Añadir parte», `.rec-ms` en el desfase) o el primer elemento, **atrapa Tab** dentro de la hoja y **devuelve el foco** al elemento previo al cerrar (`ui.js:10-27`; `parts.js:77`; `offset-sheet.js:84`).

### 6.7 Diferencias de atajos SwiftUI / web

| Situación | SwiftUI (Mac) | Web (`WinApp/Web/record`) | Flutter |
| --- | --- | --- | --- |
| Modificador de punch libre | ⌥ (`NSEvent`, `PunchTimeline.swift:74`) | Alt (`punch.js:41`) | `isAltPressed`; mostrar «Alt» en Windows (texto 8) |
| Asa activa tras intercambio | pasa a entrada (`:85`) | se mantiene salida | como SwiftUI: pasa a entrada (decisiones-interfaz.md) |
| Cadencia de arrastre | sin límite | 50 ms + al soltar | 50 ms |
| Fader con teclado | solo VoiceOver ±1 | ↑↓←→ ±1, Mayús ±3, Inicio 0 | web |
| Abrir menú de toma | indicador ▾ (`primaryAction` elige) | 2.º clic, clic dcho, ↓ | como SwiftUI (indicador ▾; `primaryAction` elige) |
| Esc en «Ajustar desfase» | no cierra | no cierra (Modal sin `onClose`) | no cierra |
| Esc en «Añadir parte» | cierra (sistema) | cierra | cierra |
| Intro en «Añadir parte» | nada | añade si hay nombre (`parts.js:80`) | web |
| Intro en ms | confirma | confirma y también en `blur`; acepta coma o punto (`offset-sheet.js:62-68,97`) | web |
| Esc en visor | cierra (`cancelAction`) | cierra (`Modal onClose`); el diálogo apilado consume Esc (`stopPropagation`) | web |
| Foco al abrir/cerrar hoja | del sistema | autofocus + trampa de Tab + restitución | web |
| Barra de posición del visor | `Slider` continuo | `range step=0.01`, etiqueta «Posición» (`viewer.js:38`) | comportamiento por defecto de Flutter con foco para las flechas (decisiones-interfaz.md); etiqueta «Posición» solo si el kit la lleva |
| Espacio para reproducir/grabar | no existe | no existe | no añadir (decisión de Jorge si se quiere) |

## 7. Hojas y popovers

Grabar abre 3 hojas (`RecordView.swift:131-133`) y un `confirmationDialog` (l.134); el visor tiene otro. **No abre ninguna hoja de calibración ni de ajustes de audio**: solo avisa con texto (`uncalibratedWarning`, l.172) y la calibración está en Ajustes. Ningún `.popover` ni `.alert` en Grabar.

### 7.1 «Añadir parte» (`AddPartSheet`, `RecordView.swift:332-356`)

- Se abre con «Añadir parte» (l.199, deshabilitado si `isBusy`).
- Composición: VStack espaciado 14; título `TF.display(20)`; `TextField` redondeado «Nombre de la parte»; `Picker` «Guitarra que sustituye» con «Ninguna (parte añadida)» y una opción por `ctl.guitarRoles`; fila Cancelar (`SecondaryButton`) / Añadir (`PrimaryButton`). Ancho 420, padding 24, fondo `TF.card`.
- Estados: «Añadir» deshabilitado si el nombre recortado está vacío (l.351). Sin estados de carga ni error.
- Acciones: `ctl.addPart(name:replaces:)` (recorta, añade, guarda con rebote y activa la parte nueva, `RecordController.swift:230-236`).

### 7.2 «Ajustar desfase» (`OffsetSheet.swift`, 150 líneas)

- Se abre (a) **al terminar una toma con vídeo** (`isNew = true`, toma pendiente) o (b) desde el menú de toma (`isNew = false`). Contrato en Windows: `takeview.openOffset` (reloj del reproductor del núcleo, evento `takeview.position`; `docs/CODEMAP.md` ola 2).
- Composición: ancho 720, padding 24, espaciado 16. Título `TF.display(22)`; ayuda 13 muted; recuadro 16:9 negro radio 12 con borde `TF.line` (vídeo de `TakePreview` con la guitarra grabada); fila «Reproducir / pausa» + «Al principio» (`SecondaryButton(height: 34)`); fila de pasos: `−1 fotograma`, `−1 ms`, campo (ancho 76, alineado a la derecha, 0 o 1 decimal) + «ms», `+1 ms`, `+1 fotograma`, y a la derecha «Fotograma = X ms»; casilla «Guardar como desfase por defecto de esta cámara (nombre)» (marcada al abrir); pie Cancelar/Guardar.
- Medidas: rango ±500 ms (`RecordController.swift:103`); fotograma = `1000 / max(fps, 1)` ms; el valor inicial es `round(initialOffset·1000)`; cualquier cambio se recorta al rango y, si cambia, reconstruye la composición conservando posición y si sonaba (`OffsetSheet.swift:105-131`). **Cada cambio lanza un `Task` sin coalescer** (riesgo de carreras al pulsar rápido; en Flutter, unir cambios y sonar con el reloj del núcleo).
- Reproducción: «Reproducir / pausa» alterna; si queda ≤ 1/30 s para el final vuelve a 0 antes de reproducir (l.95); «Al principio» busca 0. Pausa al cerrar (l.75,80,90).
- Estados: cargando (spinner mientras no hay `preview` ni error); error (texto rojo en el recuadro); listo. Reproducir y Al principio deshabilitados sin `preview`.
- Cierre: rótulos según `isNew`: «Descartar toma»/«Guardar toma» o «Cancelar»/«Guardar». `finishOffset(save:offset:makeDefault:)` (`RecordController.swift:698-706`): nueva+guardar → `savePending`; nueva+descartar → `discardPending` (borra la toma); existente+guardar → `setOffset(… camera: (cameraID, makeDefault))`; existente+cancelar → nada. «Cancelar» envía `makeDefault: false`. Offset enviado en **segundos** (`offsetMs/1000`); positivo = la imagen llega tarde.
- Foco: ver 6.1/6.6; web autoenfoca el campo de ms.

### 7.3 Confirmación «¿Borrar la toma?» (en Grabar, `RecordView.swift:134-140`)

`confirmationDialog` con título visible, botón destructivo «Borrar toma» (→ `ctl.deleteTake(id)`, que solo corre en reposo y muestra el error en `messages`, `RecordController.swift:793-808`), «Cancelar» y mensaje «Se borra su carpeta (audio y vídeo). No se puede deshacer.». Se dispara desde «Borrar…» del menú de toma. En Flutter: `AlertDialog`/`TfDialog` modal, ancho 420 como en la web (`viewer.js`, `parts.js`).

### 7.4 Visor «Ver toma» (`TakeViewer.swift`)

- Se abre con ▶ de la toma (hoja `.sheet(item:)`, `RecordView.swift:133,244-255`; título «Toma n · parte»). También lo abre `ProjectRecordingsView` (fuera de este alcance). Contrato Windows: `takeview.open` / `takeview.close` y evento `takeview.position {seconds, playing, at, epoch}` a 30 Hz (el Mac refresca cada 0,1 s, `TakeViewer.swift:172`).
- Composición: VStack espaciado 14, padding 20, ancho 720, fondo `TF.bg` (las otras hojas usan `TF.card`). Cabecera: título `TF.display(18)`, chip «★ mejor» (11 semibold, `TF.ok` sobre `TF.okBg`, cápsula 9×3) si es la mejor, botón ✕ 13 semibold. Pantalla 16:9 negra radio 10 con borde `TF.line`. Controles: play/pausa círculo 36 `TF.accent` (icono 15, `TF.accentInk`), tiempo actual (12, monoespaciado, muted), barra de posición, duración, botón «Backing»/«Backing mudo» (alto 32, radio 8, icono altavoz). Texto de error 12 `TF.danger`. Acciones: «Marcar como mejor» (`SecondaryButton`) a la izquierda y «Eliminar…» a la derecha.
- Medidas y reglas: tiempos `m:ss` truncado (`Fmt.clock`, `BackingTimeline.swift:473`); `seek` recorta a `0...duration` con tolerancia 0; play al final (`position ≥ duration − 0,1`) vuelve a 0 (l.245); el backing se rehace con la misma posición y estado de reproducción (`setBacking`, l.192-237; una generación descarta cargas obsoletas); sin vídeo = recuadro negro con «Sin vídeo: solo audio». Suena la toma (volumen de su canal «Tú · parte») y los stems con la mezcla de Grabar; la guitarra que la parte sustituye se silencia durante la toma (`TakeViewPlanning.plan`, l.37-83, silencios en l.65 y 73).
- Estados: cargando (spinner si no hay error); listo con vídeo; listo solo audio; error (pantalla negra sin spinner + línea roja); reproduciendo/pausado; backing activo/mudo (botón deshabilitado si no está listo o no hay stems, `hasBacking`); «Marcar como mejor» deshabilitado si ya lo es.
- Acciones: marcar mejor → `ctl.markBest` (no cierra); eliminar → confirmación propia (abajo) y `onDelete` = cerrar visor + `ctl.deleteTake` (`RecordView.swift:248`); cerrar → `model.close()` (pausa, suelta el ítem) y `viewing = nil`. Al desaparecer también cierra (l.294).
- Confirmación del visor (`TakeViewer.swift:295-300`): «¿Eliminar la toma?» / «Eliminar toma» / «Cancelar» / mismo mensaje. **El texto difiere del de Grabar** («Borrar» frente a «Eliminar»); se conservan ambos tal cual.
- Foco: Esc cierra (6.1); sin atajos de reproducción.

## 8. Textos

Claves camelCase; `{x}` = parámetro ICU. Líneas: `RV` = `RecordView.swift`, `RM` = `RecordMixer.swift`, `PT` = `PunchTimeline.swift`, `OS` = `OffsetSheet.swift`, `TV` = `TakeViewer.swift`, `RC` = `RecordController.swift`, `BM` = `BackingMixer.swift`. Los canales/botones M/S, «Silenciado» y «Volumen» se comparten con Backing: reutilizar sus claves si ya existen (`study_*`).

### 8.1 Pantalla, cabecera, vista previa y barra

| Clave | Texto | Fichero:línea |
| --- | --- | --- |
| `record_title` | Grabar | RV:29, 151 |
| `record_chooserEmpty` | Aún no hay temas separados. Importa uno y sepáralo en la biblioteca. | RV:31 |
| `record_chooserPick` | Elige un tema | RV:33 |
| `record_notSeparatedTitle` | Este tema aún no está separado | RV:60 |
| `record_notSeparatedBody` | Grabar necesita los stems. Sepáralo desde la biblioteca y vuelve. | RV:61 |
| `record_goLibrary` | Ir a la biblioteca | RV:62 |
| `record_headerMulti` | Multitoma | RV:149 (tras artista y título, separados por « · ») |
| `record_goMontage` | Ir al montaje | RV:155 |
| `record_goMontageHelp` | Monta las mejores tomas en un vídeo | RV:162 (`.help`) |
| `record_previewSimulated` | Vista previa de la cámara · {camera} (simulada) | RV:398 (camera por defecto «simulada») |
| `record_previewNoVideo` | Sin vídeo: se grabará solo el audio | RV:400 |
| `record_recPrefix` | REC · | RV:434 |
| `record_takePill` | Toma {n} · {part} | RV:434 |
| `record_rotate` | Rotar | RV:444 |
| `record_rotateDegrees` | Rotar · {degrees}° | RV:444 |
| `record_rotateHelp` | Gira la imagen de esta cámara 90° en sentido horario (no se recodifica; se aplica al ver y montar) | RV:449 (`.help`) |
| `record_rotateA11y` | Rotar cámara, ahora {degrees} grados | RV:450 |
| `record_start` | Grabar | RV:480, 489 |
| `record_stop` | Parar | RV:480 |
| `record_stopA11y` | Parar la grabación | RV:489 |
| `record_durationHelpTheme` | Duración del tema | RV:493 (`.help`) |
| `record_durationHelpAuto` | Para sola al acabar la sección más el margen | RV:493 (`.help`) |
| `record_startAt` | Empezar en | RV:500 |
| `record_startBeginning` | Principio | RV:501 |
| `record_countIn` | Cuenta de 1 compás | RV:506 |
| `record_preRoll` | Margen | RV:509 |
| `record_preRoll2` | 2 compases | RV:510 |
| `record_preRoll1` | 1 compás | RV:511 |
| `record_preRoll0` | Sin margen | RV:512 |
| `record_punchToggle` | Punch-in | RV:516 |
| `record_punchToggleHelp` | Vuelve a grabar un tramo de una toma | RV:521 (`.help`) |
| `record_offsetUnset` | Desfase de la cámara: sin ajustar | RV:533 |
| `record_offsetValue` | Desfase de la cámara: {ms} ms (con signo «+» si positivo) | RV:533 |

### 8.2 Estado, errores y avisos

| Clave | Texto | Fichero:línea |
| --- | --- | --- |
| `record_uncalibrated` | Sin calibrar: la toma puede ir desfasada decenas de ms; se corregirá al calibrar. | BackingRecord.swift:46 (usado en RV:172) |
| `record_cameraAudioOnly` | {message} Se grabará solo el audio. | RV:174, 176 |
| `record_cameraDenied` | Sin permiso de cámara: se grabará solo el audio. Concédelo en Ajustes del Sistema > Privacidad > Cámara. | RV:175 (llega del núcleo por código en Mac y Windows; decisiones-interfaz.md, decisión 16) |
| `record_blockPickPart` | Elige una parte. | RC:502 |
| `record_blockPickTake` | Elige la toma sobre la que hacer el punch-in. | RC:504 |
| `record_blockMarkPunch` | Marca la entrada y la salida del punch-in en la línea de tiempo. | RC:505 |
| `record_cameraNone` | No hay ninguna cámara conectada. | RC:430 |
| `record_cameraMissing` | La cámara elegida en Ajustes no está conectada. | RC:430 |
| `record_cameraOpenFailed` | No se pudo abrir la cámara ({error}). | RC:443, 468 |
| `record_cameraUnplugged` | Se desconectó la cámara: se grabará solo el audio. | RC:492 |
| `record_errStems` | No se pudieron cargar los stems ({error}). | RC:335 |
| `record_errPriorTakes` | No se pudieron cargar tus tomas anteriores ({error}). | RC:388 |
| `record_errDeviceClosed` | El dispositivo no está abierto. | RC:557 |
| `record_errStart` | No se pudo empezar a grabar. | RC:583 |
| `record_errSave` | No se pudo guardar la toma. | RC:596 |
| `record_errTake` | No se pudo grabar la toma ({error}). | RC:632 |
| `record_noticeStopped` | La toma se detuvo y se guardó lo grabado. | RC:598 |
| `record_noticeNoFrames` | No llegaron fotogramas de la cámara: la toma es solo de audio. | RC:614 |
| `record_errDelete` | No se pudo borrar la toma ({error}). | RC:801 |
| `record_errPunchTake` | No se encontró la toma del punch. | RC:814 |
| `record_blockNoInput` | Elige un dispositivo de entrada en Ajustes · Audio. | `Packages/AudioKit/Sources/AudioKit/AppLogic.swift:39` |
| `record_blockNoGuitar` | Asigna la entrada de guitarra en Ajustes · Audio. | AppLogic.swift:40 |
| `record_blockChannels` | Los canales elegidos se repiten: revisa Ajustes · Audio. | AppLogic.swift:41 |
| `record_blockInDisconnected` | El dispositivo de entrada no está conectado. | AppLogic.swift:42 |
| `record_blockOutDisconnected` | El dispositivo de salida no está conectado. | AppLogic.swift:43 |
| `record_blockRate` | El dispositivo está a {device} y la frecuencia de trabajo es {working} | AppLogic.swift:45-46 (sin punto final en el código) |
| `record_blockSpeed` | Solo se graba a velocidad 100 %: pon el tempo al 100 %. | AppLogic.swift:48 |
| `record_blockLoop` | Solo se graba sin bucle: quita el bucle. | AppLogic.swift:49 |
| `record_blockBusy` | Hay una calibración o una grabación en marcha. | AppLogic.swift:50 |

Los mensajes de `blockReason` y `messages` llegan por código y argumentos; Dart compone el texto con las claves ARB de arriba (decisiones-interfaz.md, «Mensajes: código del error de origen» y «JobInfo.text y textos de fase»).

### 8.3 Mezclador, punch-in, partes y tomas

| Clave | Texto | Fichero:línea |
| --- | --- | --- |
| `record_mixerTitle` | Mezclador | RM:24 |
| `record_mixerOutput` | Salida: {device} («—» si vacío) | RM:26 |
| `record_mixerFold` / `record_mixerExpand` | Plegar / Expandir | RM:29 |
| `record_mixerFoldA11y` / `record_mixerExpandA11y` | Plegar el mezclador / Expandir el mezclador | RM:34 |
| `record_master` | Master | RM:70, 178 |
| `record_yourGuitar` | Tu guitarra | RM:77, 197 |
| `record_inputWord` | Entrada | RM:208 |
| `record_inputLevelA11y` | Nivel de la entrada de guitarra | RM:86, 214 |
| `record_stemVocals` … `record_stemOther` | Voz, Batería, Bajo, Guitarra, Piano, Resto | RM:16 |
| `record_muted` | Silenciado | BM:178 |
| `record_muteA11y` / `record_unmuteA11y` / `record_soloA11y` | Silenciar {name} / Activar {name} / Solo {name} (botones «M» y «S») | BM:181-182 (usados en RM:129-130) |
| `record_faderA11y` | Volumen | BM:307 |
| `record_punchTitle` | Punch-in | PT:20 |
| `record_punchSummary` | Entrada {in} · Salida {out} («—» sin marca; `m:ss,d`) | PT:67-69 |
| `record_punchHelp` | Haz clic para marcar la entrada y después la salida; arrastra las marcas para moverlas (⌥ = libre, sin imán al compás). | PT:54 (web: «Alt = libre», `punch.js:73`; usar «Alt» en Windows) |
| `record_punchEntryA11y` / `record_punchExitA11y` | Entrada del punch-in / Salida del punch-in | PT:64 |
| `record_parts` | Partes | RV:195 |
| `record_partsHelp` | En cada toma suena el backing sin esa parte y con tus tomas anteriores. | RV:196 |
| `record_partReplaces` | Sustituye: {guitar} | RV:218 |
| `record_partAdded` | Parte añadida | RV:218 |
| `record_statusDone` / `record_statusRecording` / `record_statusPending` | Hecha / Grabando / Pendiente | RV:235-237 |
| `record_addPart` | Añadir parte | RV:200 |
| `record_take` | Toma {n} | RV:280 |
| `record_takeBest` | Toma {n} · mejor | RV:280 |
| `record_takeA11y` | Toma {n} (+ «, mejor») | RV:291 |
| `record_menuBest` | Marcar como mejor | RV:274 |
| `record_menuOffset` | Ajustar desfase… | RV:275 |
| `record_menuPunch` | Punch-in | RV:276 |
| `record_menuDelete` | Borrar… | RV:278 |
| `record_viewTake` | Ver toma | RV:267 (`.help`; web `title`, `parts.js:28`) |
| `record_viewTakeA11y` | Ver toma {n} | RV:267 |
| `record_viewerTitle` | Toma {n} · {part} | RV:254 |
| `record_deleteTitle` | ¿Borrar la toma? | RV:134 |
| `record_deleteConfirm` | Borrar toma | RV:136 |
| `record_deleteBody` | Se borra su carpeta (audio y vídeo). No se puede deshacer. | RV:139 |
| `record_cancel` | Cancelar | RV:137, 348; OS:74 |
| `record_addPartTitle` | Añadir parte | RV:340 |
| `record_addPartName` | Nombre de la parte | RV:341 |
| `record_addPartReplaces` | Guitarra que sustituye | RV:342 |
| `record_addPartNone` | Ninguna (parte añadida) | RV:343 |
| `record_addPartAdd` | Añadir | RV:349 |

### 8.4 Ajustar desfase

| Clave | Texto | Fichero:línea |
| --- | --- | --- |
| `record_offsetTitle` | Ajustar desfase | OS:30 |
| `record_offsetHelp` | Dale al play y mueve el desfase hasta que imagen y sonido coincidan (un golpe seco en las cuerdas ayuda). Positivo = la imagen llega tarde. | OS:31 |
| `record_offsetPlayPause` | Reproducir / pausa | OS:48 |
| `record_offsetRestart` | Al principio | OS:50 |
| `record_offsetMinusFrame` | −1 fotograma (signo U+2212) | OS:55 |
| `record_offsetMinusMs` | −1 ms | OS:56 |
| `record_offsetPlusMs` | +1 ms | OS:64 |
| `record_offsetPlusFrame` | +1 fotograma | OS:65 |
| `record_offsetMsA11y` | Desfase en milisegundos | OS:61 |
| `record_offsetUnit` | ms | OS:62 |
| `record_offsetFrameNote` | Fotograma = {ms} ms | OS:67 |
| `record_offsetMakeDefault` | Guardar como desfase por defecto de esta cámara ({camera}) | OS:70 |
| `record_offsetDiscard` | Descartar toma | OS:74 |
| `record_offsetSaveTake` | Guardar toma | OS:79 |
| `record_offsetSave` | Guardar | OS:79 |
| `record_offsetLoadError` | No se pudo abrir la toma ({error}). | OS:119 |

### 8.5 Visor «Ver toma»

| Clave | Texto | Fichero:línea |
| --- | --- | --- |
| `takeview_close` | Cerrar | TV:312-313 (`.help` y etiqueta) |
| `takeview_bestChip` | ★ mejor | TV:307 |
| `takeview_noVideo` | Sin vídeo: solo audio | TV:324 |
| `takeview_play` / `takeview_pause` | Reproducir / Pausa (etiquetas de accesibilidad) | TV:341 |
| `takeview_position` | Posición (solo web, `viewer.js:38`; el Slider de Swift no tiene etiqueta) | — |
| `takeview_backing` | Backing | TV:349 |
| `takeview_backingMuted` | Backing mudo | TV:349 |
| `takeview_backingMuteHelp` | Silenciar el backing | TV:357 (`.help`) |
| `takeview_backingUnmuteHelp` | Oír el backing | TV:357 (`.help`) |
| `takeview_markBest` | Marcar como mejor | TV:363 |
| `takeview_delete` | Eliminar… | TV:365 |
| `takeview_deleteTitle` | ¿Eliminar la toma? | TV:295 |
| `takeview_deleteConfirm` | Eliminar toma | TV:296 |
| `takeview_deleteBody` | Se borra su carpeta (audio y vídeo). No se puede deshacer. | TV:299 |
| `takeview_errNoAudio` | Esta toma no tiene audio que reproducir. | TV:205 |
| `takeview_errPrepare` | No se pudo preparar la toma ({error}). | TV:235 |
| `takeview_errInnerNoAudio` | la toma no tiene audio procesado | TV:135 (dentro de {error}) |
| `takeview_errInnerAudio` | no se pudo leer el audio {file} | TV:136 (dentro de {error}) |

`takeview_cancel` reutiliza `record_cancel` (TV:297).

## Dudas para Jorge

1. Resuelto: como SwiftUI (`PunchTimeline.swift:85`): pasa a mover la entrada (decisiones-interfaz.md, «Cerradas por la regla 1:1»: Grabar, tras intercambiar entrada y salida).
2. Resuelto: llega del núcleo por código (decisiones-interfaz.md, «Cerradas por diseño ya decidido»: Texto de «sin permiso de cámara» en Windows).
3. Resuelto: por código y argumentos; el texto se compone en Dart con ARB (decisiones-interfaz.md, «Cerradas por robustez y fiabilidad»: Mensajes, código del error de origen; «Cerradas por la regla de desvíos»: Mensajes, `JobInfo.text` y textos de fase).
4. Resuelto: como SwiftUI (decisiones-interfaz.md, «Cerradas por la regla 1:1»: Grabar, menú de toma).
5. Resuelto: cada texto, literal de SwiftUI (decisiones-interfaz.md, «Cerradas por la regla 1:1»: «Borrar» frente a «Eliminar»).
