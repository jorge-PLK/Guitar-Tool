# Ficha de pantalla · Tablatura — apartados 6 y 8

Apartados **6. Interacción** y **8. Textos** de la ficha de Tablatura (plantilla `_PLANTILLA.md`). Se funden en `tablatura.md` al cerrar la ficha. Área del puente: `tab`. Destino: `FlutterApp/lib/features/tab/`.

Siglas de origen: **Mac** = SwiftUI (`App/Sources`), **Web** = `WinApp/Web`, **Núcleo** = `Packages/AppCore/Sources/AppCore/TabService.swift`. Hecho = leído en el código; "sin comprobar" = deducido, no ejecutado.

## 6. Interacción

### 6.1 Teclado

Quién recibe la tecla:

- **Mac**: `NSEvent.addLocalMonitorForEvents(.keyDown)` de toda la app (`TabController.swift:1058-1064`), instalado al crear el controlador (`TabScreen.swift:77`) y quitado en `close()` (`TabController.swift:358`). Decide el propio `handleKey(NSEvent)` (`:1071-1116`) y la tabla de adornos `ornament(forKey:)` (`:1121-1151`). Identifica por `keyCode` (flechas 126/125/123/124, borrar 51, Supr 117, Esc 53) y por `charactersIgnoringModifiers` (letras, dígitos, signos).
- **Web**: `window.addEventListener('keydown', onKey)` más el `keydown` del iframe (`tab.js:330-355`, `frame.js:61`). `forwardEditKey` (`keys.js:9-26`) reenvía la tecla al núcleo con `tab.edit {op:"key", key, shift, ctrl, alt}` (`ctrl` = Ctrl o Meta). Consume el evento (`preventDefault`) si la reenvió.
- **Núcleo**: `TabService.handleKey(_:shift:ctrl:alt:)` (`TabService.swift:941-977`), llamado desde `tab.edit {op:"key"}` (`:1000`). Usa `KeyboardEvent.key` (`"ArrowUp"`, `"Backspace"`, `"Escape"`...). Devuelve `handled` en `TabState.handled` (`TabTypes.swift:73`). El núcleo no tiene ni emite nada de cursor ni de foco.

Todas las filas de edición exigen `phase == ready` y `editMode` (salvo Esc con tramo, Espacio). "Edición" = modo «Editar notas» activo. Columna "Método" = mensaje que se dispara; las filas marcadas `key` pasan por `tab.edit {op:"key"}` y el núcleo las traduce a la operación indicada.

| # | Tecla + modificadores | Acción | Método `tab.*` / efecto | Mac (`TabController.swift`) | Web (`keys.js`, `tab.js`) | Núcleo (`TabService.swift`) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Esc (sin mod., hay tramo, lectura) | Quita el tramo y su bucle | `tab.span {clear}` (Web) / `clearSpan()` (Mac, núcleo vía `key`) | `:1076` | `keys.js:13-16` → `spanAction('clear')` | `:944` (`clearSpan`) |
| 2 | Esc (sin mod., hay tramo, edición) | Igual que 1 | `tab.edit {op:key}` | `:1076` | `keys.js:20-24` | `:944` |
| 3 | Esc (edición, sin tramo; con o sin ⇧) | Quita la selección | `tab.edit {op:deselect}` (vía `key`) | `:1093` | vía `key` | `:956` |
| 4 | Espacio (sin mod.) | Reproducir / pausar | Transporte `study.*` (no `tab.*`); sin repetición | `SectionGridBoxes.swift:114-135` (`SpaceKeyMonitor`), `TabScreen.swift:115` | `tab.js:334-338` | no recibe |
| 5 | ⌘Z (Mac) / Ctrl+Z (Win) | Deshacer | `tab.edit {op:undo}` | `:1081` | `keys.js:22` → `key` | `:947` |
| 6 | ⇧⌘Z / Ctrl+⇧Z | Rehacer | `tab.edit {op:redo}` | `:1082` | `keys.js:22` → `key` | `:947` |
| 7 | Ctrl+Y (solo Windows) | Rehacer | `tab.edit {op:redo}` directo | no existe | `keys.js:19-20` | `key` con `ctrl`+`y` devuelve false (`:949`) |
| 8 | ⌥Y (no batería) | Armónico artificial | `tab.edit {op:ornament, name:artificialHarmonic}` | `:1083-1085` | `keys.js:22` | `:948` |
| 9 | ↑ | Cuerda arriba | `tab.edit {op:moveString, up:true}` | `:1088` | `key` | `:951` |
| 10 | ↓ | Cuerda abajo | `tab.edit {op:moveString, up:false}` | `:1089` | `key` | `:952` |
| 11 | ← | Selección un pulso atrás | `tab.edit {op:move, forward:false}` | `:1090` | `key` | `:953` |
| 12 | → | Selección un pulso adelante | `tab.edit {op:move, forward:true}` | `:1091` | `key` | `:954` |
| 13 | ⇧← | Mueve atrás el extremo móvil del tramo (y bucle) | `tab.span {extendBack}` | `:1090` | `key` | `:953` |
| 14 | ⇧→ | Igual hacia delante | `tab.span {extendForward}` | `:1091` | `key` | `:954` |
| 15 | Retroceso o Supr | Borra la nota / golpes seleccionados | `tab.edit {op:delete}` | `:1092` | `key` | `:955` |
| 16 | 0-9 (sin mod.) | Teclea traste (acumula dígitos) | `tab.edit {op:digit, value}` | `:1096` | `key` | `:959` |
| 17 | `+` o `=` | Alarga la nota un paso | `tab.edit {op:duration, sign:1}` | `:1098` | `key` | `:961` |
| 18 | `-` | Acorta la nota un paso | `tab.edit {op:duration, sign:-1}` | `:1099` | `key` | `:962` |
| 19 | B (batería) | Bombo | `tab.edit {op:hit, piece:kick}` | `:1104` | `key` | `:967` |
| 20 | C (batería) | Caja | `{op:hit, piece:snare}` | `:1105` | `key` | `:968` |
| 21 | H (batería) | Charles | `{op:hit, piece:hiHat}` | `:1106` | `key` | `:969` |
| 22 | T (batería) | Tom | `{op:hit, piece:tom}` | `:1107` | `key` | `:970` |
| 23 | P (batería) | Platos | `{op:hit, piece:crash}` | `:1108` | `key` | `:971` |
| 24 | O (sin ⇧) | Nota fantasma | `{op:ornament, name:ghost}` | `:1125` | `key` | `ornament(forKey:)` (misma tabla) |
| 25 | `;` | Acento | `{op:ornament, name:accent}` | `:1123` | `key` | idem |
| 26 | `:` | Acento fuerte | `{op:ornament, name:heavyAccent}` | `:1124` | `key` | idem |
| 27 | F (batería, sin ⇧) | Flam | `{op:ornament, name:flam}` | `:1128` | `key` | idem |
| 28 | `!` | Staccato (no batería) | `{op:ornament, name:staccato}` | `:1130` | `key` | idem |
| 29 | `)` | Tapping | `{op:ornament, name:tapping}` | `:1131` | `key` | idem |
| 30 | ⇧D | Púa abajo | `{op:ornament, name:pickDown}` | `:1132` | `key` | idem |
| 31 | ⇧U | Púa arriba | `{op:ornament, name:pickUp}` | `:1133` | `key` | idem |
| 32 | P (guitarra/bajo) | Palm mute | `{op:ornament, name:palmMute}` | `:1138` | `key` | idem |
| 33 | I | Let ring | `{op:ornament, name:letRing}` | `:1139` | `key` | idem |
| 34 | H (guitarra/bajo) | Hammer-on / pull-off | `{op:ornament, name:hammerPull}` | `:1140` | `key` | idem |
| 35 | S | Slide | `{op:ornament, name:slide}` | `:1141` | `key` | idem |
| 36 | B (guitarra/bajo) | Bend | `{op:ornament, name:bend}` | `:1142` | `key` | idem |
| 37 | V | Vibrato | `{op:ornament, name:vibrato}` | `:1143` | `key` | idem |
| 38 | W | Vibrato de palanca | `{op:ornament, name:whammyVibrato}` | `:1144` | `key` | idem |
| 39 | X | Nota muerta | `{op:ornament, name:dead}` | `:1145` | `key` | idem |
| 40 | Y (sin ⌥) | Armónico natural | `{op:ornament, name:naturalHarmonic}` | `:1146` | `key` | idem |
| 41 | G | Nota de adorno (grace); activa `graceMode` | `{op:ornament, name:grace}` | `:1147`, modo `:1078-1080` | `key` | `:946`, idem |
| 42 | L | Ligadura | `{op:ornament, name:tie}` | `:1148` | `key` | idem |

Reglas comunes (Mac = núcleo; Web las delega):

- Los adornos son interruptores (`toggleOrnament`). En batería solo valen O, F, `;` y `:`; B C H T P son golpes (`:1118-1120`, `:1128`).
- `graceMode` se apaga con cualquier tecla que no sea Retroceso, Supr, G o dígito (`:1078-1080`; núcleo `:946`).
- Las letras van sin ⇧, salvo ⇧D y ⇧U. Los signos `! ) ; :` valen con o sin ⇧ (según el teclado).
- Con ⌘/Ctrl o ⌥ solo valen ⌘Z, ⇧⌘Z y ⌥Y. El resto con esos modificadores no se usa (Mac `:1086`; núcleo `:949`).
- No actúan con el foco en un campo de texto (ver 6.2).
- Fuera de edición no hay más tecla que Esc y Espacio.
- No hay `.keyboardShortcut` ni `.onKeyPress` en la pantalla (`grep` sobre `Tab*.swift`, `Songsterr*.swift`: 0 resultados).
- Estado del núcleo que conviene reflejar en la UI: `canUndo`, `canRedo`, `selectedNote` (habilitan los botones de la barra de edición, `TabScreen.swift:388-408`).

**Diferencias entre orígenes** (9):

| ID | Diferencia | Mac | Web | Núcleo | Propuesta |
| --- | --- | --- | --- | --- | --- |
| D1 | Rehacer con Ctrl+Y | no | sí (`keys.js:19-20`) | no lo conoce en `key` | Flutter en Windows: Ctrl+Y además de Ctrl+⇧+Z, enviando `{op:redo}`. En macOS solo ⇧⌘Z, sin Ctrl+Y. Resuelto (decisiones-interfaz.md, «Rehacer con Ctrl+Y»). |
| D2 | Qué modificador es "⌘" | solo ⌘ (`mods == .command`, `:1081`); Ctrl físico no vale | `ctrl = ctrlKey \|\| metaKey` (`keys.js:12`) | `ctrl` booleano | Flutter manda `ctrl` = Cmd en macOS, Ctrl en Windows. |
| D3 | Esc / «Sin bucle» y el ancla del tramo | `clearSpan()` conserva `spanAnchor` (`:1076`, `TabScreen.swift:459`): un ⇧clic posterior amplía desde el ancla | `spanAction('clear')` (`keys.js:14`, `tab.js:291`) pone `spanAnchor = nil` (`TabService.swift:619`): el ⇧clic siguiente empieza tramo nuevo | Esc por `key` conserva el ancla (`:944`); `tab.span clear` la borra | Hueco: Mac lo define. Flutter debe usar `key` para Esc y, para «Sin bucle», un `clear` que conserve el ancla. Resuelto: el ancla se conserva, como SwiftUI (decisiones-interfaz.md, «Tablatura: «Sin bucle» y Esc, ¿borran el ancla del tramo?»). Falta una variante en `tab.span` que conserve el ancla. |
| D4 | Foco que bloquea teclas | `firstResponder is NSText` (`:1072`) | `INPUT`, `SELECT`, `TEXTAREA` (`tab.js:332-333`) | no decide | En Flutter: no actuar si un `EditableText` tiene el foco. |
| D5 | Espacio | Se consume siempre salvo campo de texto, modificadores, hoja abierta o ventana distinta; sin repetición (`SectionGridBoxes.swift:118-131`) | No actúa si hay un `<button>` enfocado ni con modificadores; no comprueba hojas; exige `studyStatus == ready` (`tab.js:334-338`) | no recibe | Seguir el criterio de Mac; en Flutter, un `Shortcuts` global que ignore el espacio si un campo de texto tiene el foco o hay hoja modal. |
| D6 | Tecla no usada | `handleKey` devuelve false → el evento sigue (`:1062`) | Consume toda tecla "known" aunque el núcleo devuelva `handled:false` (ignora `TabState.handled`, `keys.js:24-25`) | devuelve `handled` | Flutter: respetar `handled` (mandar `KeyEventResult.ignored` si es false) o filtrar antes como Mac. |
| D7 | Cadencia del cursor de reproducción | `Timer` de 0,05 s (20 Hz) y solo si cambia >1 ms (`TabScreen.swift:57,110-114`, `TabController.swift:698-702`) | evento `study.position` (máx. 30 Hz, `StudyMethods.swift:10`), sin umbral (`store.js:255-262`) | no tiene `tab.cursor` | Resuelto: ni 20 ni 30 Hz; el cursor sale de `study.position` (30 Hz, del núcleo) interpolado en un `Ticker` por fotograma, sin temporizador propio (decisiones-interfaz.md, «Cursor de tablatura a 20 o 30 Hz»). Ver 6.4. |
| D8 | Arrastre de pulsos | cada `beatDrag` se aplica directo (`:663-666`) | coalescido: un `tab.beatDrag` en vuelo, solo se guarda el último pendiente (`store.js:60-84`) | idempotente por pulso | Flutter: copiar el coalescido de Web. |
| D9 | Teclas que se reenvían al núcleo | todas (decide `handleKey`) | solo las "known": 1 carácter sin ⌘/⌥ (salvo ⌘Z, ⌥Y) o `Arrow*`, `Backspace`, `Delete`, `Escape`; nunca Espacio, Tab, Enter, F1-F12 (`keys.js:5-23`) | acepta cualquiera | Flutter: mismo filtro que Web (evita viaje inútil por tecla). Con Bloq Mayús, `e.key` llega en mayúscula y `D`/`U` se activan sin ⇧ (sin comprobar si Mac hace lo mismo). Resuelto para teclados no US: atajos por tecla lógica (`SingleActivator`); cifras y letras de edición por `KeyEvent.character`; se prueba con teclado español en el PC (decisiones-interfaz.md, «Teclas por `keyCode` o por carácter»). |

### 6.2 Foco: página de alphaTab frente a controles nativos

Hechos:

- **Mac**: la partitura es un `WKWebView` (`TabWebHost.swift`). No se llama a `makeFirstResponder`, ni a `focus()`. No hace falta: los monitores locales (`handleKey`, `SpaceKeyMonitor`) ven la tecla antes que la cadena de respondedores, así que la web nunca "captura" teclas de edición mientras no devuelvan false. Quien sí captura es un campo de texto (`NSText`): ahí el monitor no actúa. Un `Button` enfocado no bloquea las flechas ni los dígitos; el Espacio lo consume el monitor antes que el botón (`SectionGridBoxes.swift:110-112`).
- **Web (Windows)**: la partitura es un `<iframe>` del mismo origen (`frame.js:41-45`). Un clic dentro da el foco al iframe y entonces las teclas llegan por su propio `keydown` (`frame.js:61` → `tab.js:onKey`). Un clic en los botones de la barra deja el foco en el documento padre y llegan por `window`. `AlphaFrame.focus()` (`frame.js:124`) existe pero nadie lo llama; no hay "devolver el foco" tras pulsar un botón. Las teclas de `INPUT/SELECT/TEXTAREA` no se reenvían (`tab.js:332-333`).
- **Núcleo**: no sabe del foco. Solo recibe `key` y responde `handled`.

Propuesta para Flutter (opinión, sin regla en la spec):

- Un único `Focus`/`Shortcuts` envolviendo la pantalla, de modo que da igual quién tenga el foco salvo un `EditableText`.
- Si la partitura es un webview, no debe quedarse con las teclas: reenviar `keydown` al `Focus` de Flutter, o dejar que la página las ignore y las trate Flutter. Decisión de la ficha de arquitectura, no de este apartado.
- Tras usar un botón de la barra, no hace falta devolver el foco explícitamente si el `Focus` es de pantalla.

### 6.3 Ratón dentro de la partitura

Todo parte de `tf-bridge.js` (`App/Resources/alphaTab/tf-bridge.js`), que no distingue plataforma:

- `mousedown` en captura guarda `e.shiftKey` en `lastShift` (`:420`); `mouseup` termina el arrastre (`:421`).
- `beatMouseDown` → `beatClick {track, bar, beat, shift}` y empieza arrastre (`:422-427`).
- `beatMouseMove` con el botón pulsado y pulso distinto del último → `beatDrag {track, bar, beat}` (`:428-434`).
- `noteMouseDown` → `noteClick {track, bar, beat, string(0-based), fret, shift}` (`:435-439`). En un clic sobre nota se disparan los dos manejadores (`beatMouseDown` y `noteMouseDown`); el orden lo fija alphaTab (sin comprobar).
- Pista del índice: `track`, `bar`, `beat` son índices de alphaTab; el núcleo los resuelve con `alpha.ref(...)` y comprueba que la pista es la seleccionada (si no, ignora).

| Mensaje de la página | Método | Efecto (Mac `TabController.swift` = núcleo `TabService.swift`) |
| --- | --- | --- |
| `beatClick` sin ⇧, o con ⇧ sin ancla | `tab.beatClick {track, bar, beat, shift}` | Quita el tramo y bucle anterior (`clearSpan`), fija ancla del tramo = ese pulso. Si el pulso ya estaba seleccionado: no toca selección ni cuerda, pero hace `seek` a su tiempo (otra vez). Si no: selecciona el pulso conservando la cuerda previa. Mac `:650-662` = núcleo `:518-531`. |
| `beatClick` con ⇧ y ancla | idem | Amplía el tramo desde el ancla hasta ese pulso y lo pone como bucle `Selección` (`extendSpan(to:)`); salta al inicio solo si cambió el inicio. Mac `:654, 720-738` = núcleo `:522, 561-579`. |
| `beatDrag` con ancla | `tab.beatDrag {track, bar, beat}` | Igual que ⇧clic: amplía el tramo (y bucle) hasta el pulso. Sin ancla, se ignora. Mac `:663-666` = núcleo `:533-538`. |
| `noteClick` sin ⇧ | `tab.noteClick {track, bar, beat, string, shift:false}` | Selecciona el pulso y la cuerda de la nota (cuerda JSON → cuerda de la partitura según la afinación). Mac `:667-671` = núcleo `:540-546`. |
| `noteClick` con ⇧ | no se envía en Web (`store.js:69`); Mac y núcleo lo ignoran (`guard !shift`) | Lo trata el `beatClick` con ⇧. |
| `rendered` | no es método: el anfitrión recoloca cursor, selección y rango | Mac `:643-648`; Web `frame.js:70-75`. |
| `cursor`, `ready`, `error` | `cursor` lo emite la página pero Mac y Web lo ignoran; `error` → `webError` | Mac `:649`; Web `store.js:64`. |

Estado a pintar según los eventos del núcleo: `tab.selection {bar, fraction}` (marcador azul de 2 px, `tf-bridge.js:385-386`; `bar < 0` lo oculta) y `tab.range {startBar, startFraction, endBar, endFraction}` (rectángulos por compás, `tf-bridge.js:534`; `sb < 0` lo oculta). Emitidos por `emitSelectionMarker` (`TabService.swift:548-557`) y `emitRangeMarker` (`:628-635`). Mac los calcula en el controlador (`updateSelectionMarker`, `:704-711`).

### 6.4 Selección de rango, bucle y cursor de reproducción

| Qué | Quién lo mueve | Cadencia | Fuente |
| --- | --- | --- | --- |
| Cursor de reproducción | Mac: la vista, con `Timer.publish(every: 0.05)` llama `tab.updateCursor(time:follow:true)`; el controlador solo reenvía si pasaron >1 ms y la partitura está pintada (`rendered`). Web: `followPosition` suscrito a `study.position`. | Mac 20 Hz; Web ≤30 Hz | `TabScreen.swift:57,110-114`; `TabController.swift:698-702`; `store.js:255-262`; `StudyMethods.swift:10` |
| Seguir el cursor (`follow`) | La página: si el cursor sale de la vista, desplaza `scrollTo` para dejarlo a un tercio de la altura. No actúa con el cursor visible. | por evento | `tf-bridge.js:515-521` |
| Marcador de selección | Núcleo emite `tab.selection` en cada cambio de selección | por evento | `TabService.swift:548` |
| Rango del tramo | Núcleo emite `tab.range` en cada cambio de tramo | por evento | `TabService.swift:628` |
| Bucle del tramo | Clic/arrastre/⇧clic/⇧←→ crean el bucle `Selección` (`spanLoopName`; en Flutter la marca no se compara por texto, ver `tabLoopSelection` en 8.1) con `ctl.setLoop`; `seek` al inicio si cambia el inicio. Si el bucle activo deja de ser `Selección`, se quita solo el resaltado (`loopChanged`). Web lo replica con `watchLoop` (`store.js:264-273`). | por evento | `TabController.swift:23,727-738,761-773`; `TabService.swift:568-579` |
| Menú «Bucle» | Opciones: «Sin bucle», `Selección` (si hay tramo), «Compás N» (compás de la selección), una por sección del tema. | por clic | `TabScreen.swift:457-479` |

Qué hace falta de Flutter: dibujar la partitura recibe `tab.score` (ya es así); el cursor lo mueve el almacén suscrito a `study.position` (como Web); la cadencia está resuelta en D7 (`Ticker` por fotograma sobre `study.position`); no se porta el umbral de 1 ms de Mac ni el tope de 20/30 Hz.

### 6.5 Menús contextuales

- Mac: ninguno en la pantalla (`grep contextMenu|willOpenMenu` en `Tab*.swift`, `Songsterr*.swift`: 0). Sin comprobar: el `WKWebView` de la partitura conserva el menú contextual por defecto de WebKit (sin código que lo quite).
- Windows: `AreDefaultContextMenusEnabled` solo con devtools (`CWebView2Host.cpp:349`, `:547`); en producción no hay menú contextual.
- Menús desplegables (no contextuales): «Fuente: …» (`TabScreen.swift:151-167`), selector de afinación (`:299-306`), «Bucle» (`:457-479`).
- Resuelto: sin menú contextual (decisiones-interfaz.md, «Tablatura: zoom y menú contextual»).

### 6.6 Scroll y zoom

- Scroll: nativo de la página (`window.scrollY`). La partitura va en modo `Page` (`tf-bridge.js:401`) con el texto no seleccionable (`:407-408`). Se conserva el desplazamiento al repintar (`pendingScroll`, `:411, :441`). Rueda y barra: las del navegador. El cursor sigue por 6.4.
- Zoom: la app no lo tiene. Mac: sin código de zoom ni magnificación (sin comprobar el valor por defecto de `WKWebView`). Windows: `put_IsZoomControlEnabled(FALSE)` (`CWebView2Host.cpp:347, :676`). Escala de alphaTab sin tocar (valor por defecto).
- Resuelto: sin zoom (decisiones-interfaz.md, «Tablatura: zoom y menú contextual»).
- Arrastrar y soltar ficheros: no hay en esta pantalla (`grep onDrop|onDrag` sobre `Tab*.swift`: 0).

## 8. Textos

Claves en camelCase con prefijo `tab_`. Texto literal en español tal como está en el código. Variables entre `{}` (marcador ARB). `.help(`: no hay ninguno en `Tab*.swift` ni `Songsterr*.swift` (0 resultados), así que no hay tooltips; las etiquetas de accesibilidad se listan como `tab_a11y*`.

### 8.1 Textos que van a ARB (SwiftUI)

Cabecera y selector de tema

| Clave ARB | Texto | Fichero:línea |
| --- | --- | --- |
| `tabTitle` | Tablatura | `TabScreen.swift:30, 127` |
| `tabChooserEmpty` | Aún no hay temas separados. Importa uno y sepáralo en la biblioteca. | `TabScreen.swift:32` |
| `tabChooserPick` | Elige un tema | `TabScreen.swift:34` |
| `tabEditNotes` | Editar notas | `TabScreen.swift:133` |
| `tabExportGuitarPro` | Exportar a Guitar Pro | `TabScreen.swift:143` |
| `tabSourceMenu` | Fuente: {fuente} | `TabScreen.swift:162` |
| `tabSourceSongsterrSearch` | Buscar en Songsterr… | `TabScreen.swift:153` |
| `tabSourceChangePairing` | Cambiar emparejamiento… | `TabScreen.swift:155` |
| `tabSourceAutomatic` | Transcripción automática | `TabScreen.swift:157`; `TabController.swift:379` |
| `tabSourceSongsterr` | Songsterr | `TabController.swift:378` |
| `tabSourceNone` | Sin elegir | `TabController.swift:380` |
| `tabA11yCloseNotice` | Cerrar aviso | `TabScreen.swift:176` |

Pistas y controles de pista

| Clave ARB | Texto | Fichero:línea |
| --- | --- | --- |
| `tabA11yUnmute` | Activar {pista} | `TabScreen.swift:227` |
| `tabA11yMute` | Silenciar {pista} | `TabScreen.swift:227` |
| `tabA11ySolo` | Solo {pista} | `TabScreen.swift:230` |
| `tabTrackMuteLetter` | M | `TabScreen.swift:227` |
| `tabTrackSoloLetter` | S | `TabScreen.swift:230` |
| `tabListenLabel` | Oír | `TabScreen.swift:270` |
| `tabListenStems` | Stems | `TabScreen.swift:271` |
| `tabListenTranscription` | Transcripción | `TabScreen.swift:272` |
| `tabListenMixed` | Mixto | `TabScreen.swift:273` |
| `tabSynthProgress` | Sintetizando {hecho}/{total}… | `TabScreen.swift:277` |
| `tabSynthRendering` | Sintetizando… | `TabScreen.swift:313` |
| `tabTuning` | Afinación | `TabScreen.swift:298-299` |
| `tabListenTrack` | Oír transcripción | `TabScreen.swift:309` |
| `tabTuningStandard` | Estándar | `TabController.swift:1048` |
| `tabTuningHalfDown` | Medio tono abajo | `TabController.swift:1049` |
| `tabTuningWholeDown` | Un tono abajo | `TabController.swift:1050` |
| `tabTuningDropD` | Drop D | `TabController.swift:1051` |
| `tabTuningCustom` | Personalizada | `TabController.swift:1052` |
| `tabHeaderSummary` | {compás} · {bpm} BPM | `TabController.swift:164, 169` |

Estados de la zona de partitura

| Clave ARB | Texto | Fichero:línea |
| --- | --- | --- |
| `tabWebError` | Mensaje genérico traducido (texto exacto por fijar); se muestra con `{detalle}` = texto de la página. El prefijo literal `alphaTab:` deja de ser el texto de ARB. | `TabScreen.swift:325` |
| `tabWorkingTitle` | Transcribiendo… | `TabScreen.swift:329` |
| `tabWorkingBody` | La primera vez tarda un poco. Lo hecho se guarda pista a pista. | `TabScreen.swift:330` |
| `tabChoosingTitle` | Elige la fuente de la tablatura | `TabScreen.swift:343` |
| `tabChoosingBody` | Songsterr trae la tablatura hecha por la comunidad; la transcripción automática sale del audio. | `TabScreen.swift:344` |
| `tabChoosingSongsterr` | Buscar en Songsterr | `TabScreen.swift:347` |
| `tabChoosingAutomatic` | Transcribir automáticamente | `TabScreen.swift:348` |
| `tabWaitingTitle` | Esperando el análisis del tema | `TabScreen.swift:354` |
| `tabWaitingBody` | La tablatura necesita los compases y pulsos del análisis. Puedes lanzarlo desde Backing track. | `TabScreen.swift:355` |
| `tabWaitingAction` | Analizar | `TabScreen.swift:356` |
| `tabEmptyTitle` | No hay pistas que transcribir | `TabScreen.swift:358` |
| `tabEmptyBody` | Este tema no tiene stems de guitarra, bajo o batería con audio. | `TabScreen.swift:358` |
| `tabFailedTitle` | No se pudo transcribir | `TabScreen.swift:360` |

Barra inferior (pie)

| Clave ARB | Texto | Fichero:línea |
| --- | --- | --- |
| `tabFooterSongsterr` | Tablatura de Songsterr · revisa y corrige si hace falta | `TabScreen.swift:377` |
| `tabFooterAutomatic` | Transcripción automática · revisa y corrige si hace falta | `TabScreen.swift:378` |
| `tabSelectionPlace` | Compás {compás}, pulso {pulso} | `TabController.swift:818` |
| `tabSelectionDrums` | {lugar} · {piezas} | `TabController.swift:821` |
| `tabSelectionNoHits` | sin golpes | `TabController.swift:821` |
| `tabSelectionNote` | {lugar} · cuerda {cuerda}, traste {traste} | `TabController.swift:824` |
| `tabSelectionNoNote` | {lugar} · cuerda {cuerda}, sin nota | `TabController.swift:826` |
| `tabPieceKick` | bombo | `TabController.swift:831` |
| `tabPieceSnare` | caja | `TabController.swift:832` |
| `tabPieceHiHat` | charles | `TabController.swift:833` |
| `tabPieceOpenHiHat` | charles abierto | `TabController.swift:834` |
| `tabPieceTom` | tom | `TabController.swift:835` |
| `tabPieceCrash` | platos | `TabController.swift:836` |

Los botones de batería usan `pieceName(p).capitalized` (`TabScreen.swift:396`): Flutter debe capitalizar la primera letra en código (Bombo, Caja, Charles, Charles abierto, Tom, Platos) o tener claves propias; decisión de la ficha.

Barra de edición

| Clave ARB | Texto | Fichero:línea |
| --- | --- | --- |
| `tabUndo` | Deshacer | `TabScreen.swift:390` |
| `tabRedo` | Rehacer | `TabScreen.swift:392` |
| `tabDrumKeysHint` | B bombo · C caja · H charles · T tom · P platos | `TabScreen.swift:398` |
| `tabAddNote` | Añadir nota | `TabScreen.swift:400` |
| `tabA11yShortenNote` | Acortar nota | `TabScreen.swift:402` |
| `tabA11yLengthenNote` | Alargar nota | `TabScreen.swift:404` |
| `tabDelete` | Borrar | `TabScreen.swift:405` |
| `tabKeysHint` | Dígitos: traste · ↑ ↓: cuerda · ← →: mover · +/−: duración · ⌘Z deshacer | `TabScreen.swift:407` |

En Windows `⌘Z` debería ser `Ctrl+Z`: clave doble (`tabKeysHintMac`, `tabKeysHintWin`). Resuelto: variante por plataforma (decisiones-interfaz.md, «Rehacer con Ctrl+Y»: el texto de ayuda «⌘Z» lleva variante por plataforma).

Transporte y bucle

| Clave ARB | Texto | Fichero:línea |
| --- | --- | --- |
| `tabA11yRewind` | Volver al inicio | `TabScreen.swift:426` |
| `tabA11yPause` | Pausar | `TabScreen.swift:434` |
| `tabA11yPlay` | Reproducir | `TabScreen.swift:434` |
| `tabTempo` | Tempo | `TabScreen.swift:440` |
| `tabMetronome` | Metrónomo | `TabScreen.swift:448` |
| `tabLoop` | Bucle | `TabScreen.swift:473` |
| `tabLoopActive` | Bucle: {nombre} · {desde}–{hasta} | `TabScreen.swift:471` |
| `tabLoopFree` | libre | `TabScreen.swift:471` |
| `tabLoopNone` | Sin bucle | `TabScreen.swift:459` |
| `tabLoopSelection` | Selección. En Flutter la marca de «Selección» no se compara por texto: el bucle del tramo lleva una marca del núcleo y el texto visible sale de ARB (decisiones-interfaz.md, «Nombres por defecto que el núcleo guarda en español»; cita `TabService:42`). | `TabController.swift:23` |
| `tabLoopBar` | Compás {n} | `TabScreen.swift:464` |
| `tabLoopBarName` | compás {n} (nombre del bucle, minúscula) | `TabScreen.swift:464` |

Confirmación

| Clave ARB | Texto | Fichero:línea |
| --- | --- | --- |
| `tabConfirmAutoTitle` | ¿Pasar a transcripción automática? | `TabScreen.swift:103` |
| `tabConfirmAutoAction` | Pasar a automática | `TabScreen.swift:104` |
| `tabConfirmAutoCancel` | Cancelar | `TabScreen.swift:105` |
| `tabConfirmAutoBody` | Se quitan las pistas de Songsterr y sus ediciones; las demás se transcriben del audio. | `TabScreen.swift:107` |

Avisos y mensajes breves (el aviso breve dura 3 s: `TabController.swift:884-892`)

| Clave ARB | Texto | Fichero:línea |
| --- | --- | --- |
| `tabNoticeRedone` | Se han rehecho: {pistas}. Su audio cambió, así que se perdieron las ediciones de esas pistas. | `TabController.swift:243` |
| `tabNoticeTranscription` | Transcripción: {partes}. | `TabController.swift:318` |
| `tabNoticeShifted` | {n} notas fuera del registro de la afinación se subieron o bajaron una octava | `TabController.swift:316` |
| `tabNoticeDropped` | {n} se quitaron por no caber en las cuerdas | `TabController.swift:317` |
| `tabNoticeAnd` | {a} y {b} (unión de las dos partes) | `TabController.swift:318` |
| `tabFlashSaveFailed` | No se pudo guardar la tablatura: {error} | `TabController.swift:634` |
| `tabFlashNoHits` | No hay golpes seleccionados. | `TabController.swift:976` |
| `tabFlashNoNote` | No hay ninguna nota seleccionada. | `TabController.swift:980` |
| `tabFlashRetuned` | {n} notas se movieron una octava y {m} se quitaron por no caber en la afinación. | `TabController.swift:1041` |
| `tabFlashNoSoundfont` | Falta el soundfont de alphaTab en la app. | `TabController.swift:1276` |
| `tabSynthFailedSoundfont` | Falta el soundfont en la app | `TabController.swift:1276` |
| `tabFlashSynthFailed` | No se pudo sintetizar la pista: {error} | `TabController.swift:1298` |
| `tabFlashSaved` | Guardado {fichero}. | `TabController.swift:1343` |
| `tabFlashExportFailed` | No se pudo exportar: {error} | `TabController.swift:1345` |

Errores de edición (`TabController.message(for:)`, `TabController.swift:871-881`)

| Clave ARB | Texto | Línea |
| --- | --- | --- |
| `tabEditNothingSelected` | No hay nada seleccionado. | `:873` |
| `tabEditWrongKind` | Esa edición no vale para esta pista. | `:874` |
| `tabEditNoOtherString` | No hay otra cuerda en esa dirección. | `:875` |
| `tabEditFretRange` | El traste saldría de 0–24. | `:876` |
| `tabEditStringOccupied` | Ya hay una nota en esa cuerda en ese punto. | `:877` |
| `tabEditInvalidPosition` | Esa posición no está en la rejilla de la pista. | `:878` |
| `tabEditInvalidDuration` | Esa duración no cabe. | `:879` |
| `tabEditNoTieOrigin` | No hay una nota anterior igual en esa cuerda a la que ligarla. | `:880` |

Hoja de Songsterr (`TabSourceSheet.swift`, `SongsterrLookup.swift`, `TabController.swift`)

| Clave ARB | Texto | Fichero:línea |
| --- | --- | --- |
| `tabSheetTitle` | Tablatura de Songsterr | `TabSourceSheet.swift:26` |
| `tabSheetPreview` | Vista previa | `TabSourceSheet.swift:47, 82` |
| `tabSheetUseThis` | Usar esta | `TabSourceSheet.swift:49, 86` |
| `tabSheetClose` | Cerrar | `TabSourceSheet.swift:51` |
| `tabSheetSearch` | Búsqueda: {artista · título} | `TabSourceSheet.swift:66` |
| `tabSheetSearching` | Buscando en Songsterr… | `TabSourceSheet.swift:69` |
| `tabSheetCancel` | Cancelar | `TabSourceSheet.swift:79, 185, 244` |
| `tabSheetAutomatic` | Transcribir automáticamente | `TabSourceSheet.swift:85, 198` |
| `tabSheetReadingTracks` | Leyendo las pistas… | `TabSourceSheet.swift:110` |
| `tabSheetOtherResults` | Otros resultados | `TabSourceSheet.swift:114` |
| `tabSheetLinkHint` | O pega un enlace de Songsterr | `TabSourceSheet.swift:145` |
| `tabSheetUseLink` | Usar enlace | `TabSourceSheet.swift:150` |
| `tabSheetSuggestAuto` | Puedes transcribir el tema automáticamente. | `TabSourceSheet.swift:162` |
| `tabSheetRetry` | Reintentar | `TabSourceSheet.swift:164` |
| `tabSheetBack` | Volver | `TabSourceSheet.swift:196` |
| `tabSheetPairingHelp` | Qué pista de Songsterr va con cada stem. La confianza es el parecido medido con el audio. | `TabSourceSheet.swift:207` |
| `tabSheetExtraTracks` | Pistas extra, sin stem: {nombres}. Entran en la tablatura y en el .gp y solo suenan con «Oír transcripción». | `TabSourceSheet.swift:220` |
| `tabSheetBackShort` | Atrás | `TabSourceSheet.swift:241` |
| `tabSheetAllAutomatic` | Todo automático | `TabSourceSheet.swift:242` |
| `tabSheetAccept` | Aceptar | `TabSourceSheet.swift:245` |
| `tabSheetNoSolos` | Transcripción automática (el tema no tiene secciones de solo) | `TabSourceSheet.swift:265` |
| `tabSheetSoloRow` | Solo {n} ({tiempo}) | `TabSourceSheet.swift:276, 279` |
| `tabSheetSoloNone` | Ninguna | `TabSourceSheet.swift:280` |
| `tabSheetConfidenceUnmeasured` | sin medir | `TabSourceSheet.swift:288, 314` |
| `tabSheetPickAutomatic` | Transcripción automática | `TabSourceSheet.swift:306` |
| `tabSheetWorkingRead` | Leyendo Songsterr… | `TabController.swift:450` |
| `tabSheetWorkingDownload` | Descargando pistas de Songsterr… | `TabController.swift:450, 488` |
| `tabIssueNoResults` | No está en Songsterr. | `Packages/SourceKit/Sources/SourceKit/Songsterr/SongsterrLookup.swift:40` |
| `tabIssueRateLimited` | Songsterr está limitando las peticiones. Espera un poco y vuelve a intentarlo. | `Packages/SourceKit/Sources/SourceKit/Songsterr/SongsterrLookup.swift:41` |
| `tabIssueOffline` | No se pudo conectar con Songsterr. Comprueba la conexión. | `Packages/SourceKit/Sources/SourceKit/Songsterr/SongsterrLookup.swift:42` |
| `tabIssueFormatChanged` | Songsterr ha cambiado su formato. | `Packages/SourceKit/Sources/SourceKit/Songsterr/SongsterrLookup.swift:43` |
| `tabIssueInvalidLink` | Ese enlace no es de Songsterr. | `Packages/SourceKit/Sources/SourceKit/Songsterr/SongsterrLookup.swift:44` |
| `tabIssueHttp` | Songsterr respondió con el error {código}. | `Packages/SourceKit/Sources/SourceKit/Songsterr/SongsterrLookup.swift:33` |

Notas:

- Las filas con rangos de línea sacadas de ventanas parciales (p. ej. `TabController.swift:316-318`, `SongsterrLookup.swift:33`) están comprobadas (exactas); `SongsterrLookup.swift` está en `Packages/SourceKit/Sources/SourceKit/Songsterr/`. `TabSourceSheet.swift:96-130` (nombres de resultados y pistas) son datos, no textos fijos.
- Mensajes de error del núcleo (`RPCError` en `TabService.swift`, p. ej. «La tablatura no está lista.») hoy se redactan en español en el núcleo (`TabService.swift:981, 985, 992, 997, 1005, 1014, 623`). Resuelto: el núcleo conserva el código del error y los argumentos; el texto se compone en Dart con ARB (decisiones-interfaz.md, «Mensajes: código del error de origen» y «`JobInfo.text` y textos de fase»).
- El texto de «Compás {n}, pulso {m}» etc. se arma en el controlador de Mac (`selectionSummary`, `headerSummary`); el núcleo entrega `TabState.header` ya formado en Web (`tab.js` lo usa tal cual). Sin comprobar si `selectionSummary` también llega del núcleo.

### 8.2 Textos que viven dentro de la página web (no van a ARB salvo decisión)

`tab.html` solo contiene mensajes técnicos de error hacia el anfitrión; no hay texto de interfaz visible (`App/Resources/alphaTab/tab.html`). El anfitrión los muestra tras el prefijo `alphaTab:` (`tabWebError`).

| Origen | Texto literal | Fichero:línea | Observación |
| --- | --- | --- | --- |
| `tab.html` | `String(e.message) + ' @' + fichero:línea` (error de script) | `tab.html:13` | Técnico. Va dentro de `tabWebError`. |
| `tab.html` | `unhandledrejection: …` | `tab.html:15` | Técnico, inglés. |
| `tab.html` | `init: …` | `tab.html:31` | Técnico, inglés. |
| `tf-bridge.js` | `Unsupported drum piece: {gm}` | `tf-bridge.js:110` | Inglés. |
| `tf-bridge.js` | `Unknown track kind: {kind}` | `tf-bridge.js:140` | Inglés. |
| `tf-bridge.js` | `Track "{name}" has {n} bars, expected {m}` | `tf-bridge.js:142` | Inglés. |
| `tf-bridge.js` | `Track "{name}" needs a tuning` | `tf-bridge.js:181` | Inglés. |
| `tf-bridge.js` | `String out of range: {s}` | `tf-bridge.js:227` | Inglés. |
| `tf-bridge.js` | `Unknown {what}: {name}` | `tf-bridge.js:246` | Inglés. |
| `tf-bridge.js` | `alphaTab: {mensaje}` + pila | `tf-bridge.js:418` | Prefijo ya duplicado por `tabWebError`. |
| `tf-bridge.js` | `{función}: {mensaje}` + pila | `tf-bridge.js:586` | Técnico. |
| `tf-bridge.js` | nombres GM de percusión (`Acoustic Kick Drum`, `Kick Drum`, `Charley`, `Tom Medium`, `Crash High`...) | `tf-bridge.js:41-47` | Nombres de instrumento internos de la tabla alphaTab, no se muestran. |
| `frame.js` (Web) | `Partitura` (título accesible del iframe) | `WinApp/Web/tab/frame.js:44` | Solo existe en Windows; no hay equivalente Mac. |
| `tab.js` (Web) | `No se pudo abrir la tablatura`, `Reintentar` | `WinApp/Web/screens/tab.js:369-371` | Pantalla de error de apertura que solo existe en Windows (SwiftUI no la tiene). Si Flutter la necesita: `tabOpenFailed`, `tabSheetRetry`. |

Resuelto: los textos de dentro de la página no van a ARB; Dart muestra un mensaje genérico traducido y el texto de la página como detalle (decisiones-interfaz.md, «Errores de alphaTab (`webError`)»).
