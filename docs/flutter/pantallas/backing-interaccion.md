# Ficha de pantalla · Backing (apartados 6, 7 y 8)

Complementa `backing.md` (apartados 1-4, 10 y 11) y `backing-contrato.md` (5 y 9). Rutas relativas a `App/Sources/` salvo indicación. «Web» = `WinApp/Web/backing/`.

Hecho previo: Backing **no tiene onda**. La «onda» del encargo no existe; los arrastres son sobre la **tira de acordes** (`BackingTimeline.swift`), la **rejilla de compases** (`ChordGrid.swift`), las **asas de borde de sección** y la **barra de posición** (`ProgressBarView`). No hay `.onDrag` (arrastrar y soltar de ficheros) ni `.keyboardShortcut` de ninguna acción de Backing, salvo `.defaultAction` de «Hecho» en la hoja de sección (`SectionBoxes.swift:333`). No hay `onKeyPress`. Las teclas pasan por dos monitores `NSEvent` y por `onExitCommand`/`onSubmit`.

## 6. Interacción

### 6.1 Teclado

| Tecla | Efecto | Condiciones | Fichero:línea |
| --- | --- | --- | --- |
| Espacio (keyCode 49; en Flutter, tecla lógica `LogicalKeyboardKey.space`, no keyCode) | `ctl.togglePlay()` (reproducir/pausar). Evento consumido (no llega al botón enfocado) | Sin ⌘ ⌃ ⌥ ⇧. Ventana clave = ventana del evento, sin hoja (`sheetParent`/`attachedSheet` nil). El primer respondedor no es `NSText` (no se está escribiendo). Auto-repetición ignorada (`isARepeat`) | `SectionGridBoxes.swift:114-130`; instalado en `onAppear` de la tarjeta y retirado en `onDisappear` (`BackingTimeline.swift:21,46-47,57`) |
| Suprimir (117) / Retroceso (51; en Flutter, tecla lógica `LogicalKeyboardKey.delete` / `backspace`, no keyCode) | `selection.clear()` + `session.removeSection(id)` de la sección seleccionada | Hay sección seleccionada; sin ⌘ ⌃ ⌥ (⇧ vale); primer respondedor no es `NSText`. Con la ventana de sección abierta pero el foco fuera del nombre también borra en SwiftUI; en Flutter NO borra (decisiones-interfaz.md, Backing: Supr) | `SectionGridBoxes.swift:141-163` (caso 51/117 en :151) |
| Esc (53; en Flutter, tecla lógica `LogicalKeyboardKey.escape`, no keyCode) | `selection.clear()` (quita selección y asas) | Solo si `selection.popover == nil`; mismas condiciones que Supr | `SectionGridBoxes.swift:155` |
| Esc dentro del nombre de la hoja de sección | Cierra sin renombrar (`cancelled = true`, `popover = nil`) | Foco en el campo «Nombre» | `SectionBoxes.swift:304,411-414` |
| Enter dentro del nombre de la hoja de sección | `done()`: renombra y cierra | Foco en el campo | `SectionBoxes.swift:303,405-409` |
| Enter (default action) | Pulsa «Hecho» | Hoja de sección abierta | `SectionBoxes.swift:333` |
| Enter / Esc en el nombre de un canal de guitarra | Enter confirma (`commit`), Esc cancela (`editing = false`). Perder el foco también confirma | Campo en edición | `BackingMixer.swift:195-199` |
| Esc / clic fuera en popovers de acorde y de sección | Cierre nativo de `.popover` (transitorio). Al cerrar la hoja de sección sin Esc de campo, `onDisappear` renombra con el borrador | — | `BackingTimeline.swift:192`, `ChordGrid.swift:251`, `SectionBoxes.swift:101-104,341` |
| Tab / Intro / Espacio sobre botones | Navegación de foco por defecto de macOS (los botones son `.buttonStyle(.plain)` y reciben foco solo con «Acceso completo con teclado») | Sistema | no hay código propio |
| VoiceOver «incrementar/decrementar» en la barra de posición | `seek(time ± 5 s)` | `accessibilityAdjustableAction` | `BackingTimeline.swift:612` |
| VoiceOver en el fader | `±1 dB` | idem | `BackingMixer.swift:309` |

No hay flechas, Inicio/Fin, Retroceso de página ni atajos ⌘ en Backing.

### 6.2 Modificadores (único: ⌥ Opción)

⌥ se lee con `NSEvent.modifierFlags.contains(.option)` **en el momento de soltar** (o del evento de arrastre), no al empezar:

| Gesto | Sin ⌥ | Con ⌥ | Fichero:línea |
| --- | --- | --- | --- |
| Arrastre de bucle en la tira | Imán al pulso, nombre del bucle «acordes» | Imán al compás, nombre «compases» | `BackingTimeline.swift:303-305` |
| Arrastre de bucle en la rejilla | idem | idem | `ChordGrid.swift:287-288` |
| Arrastre de borde de sección | Imán a cambios de acorde dibujados | Imán a límites de compás (`barMagnet`) si los hay | `SectionBoxes.swift:172,180,183`; `Packages/Store/Sources/Store/SectionEdgeDrag.swift:106-110` |
| ◀ ▶ de inicio/fin en la hoja de sección | Salta al acorde anterior/siguiente (`chordBoundaries`) | Al compás (`barBoundaries` = downbeats) | `SectionBoxes.swift:382`; `StudySession.swift:225-228,239-244` |
| Clic en «Punch» de grabación (otra pantalla) | — | — | no es Backing |

Texto de ayuda visible: «Clic: saltar · arrastrar: bucle (⌥ = compases)» (`BackingTimeline.swift`, `chordsHeader`) y «◀ ▶ mueven por acorde · ⌥ por compás» (`SectionBoxes.swift:325`). En Flutter: `HardwareKeyboard.instance.isAltPressed` leído en los mismos instantes.

### 6.3 Umbrales y medidas de los gestos

| Elemento | Valor | Fichero:línea |
| --- | --- | --- |
| Clic frente a arrastre en la rejilla | distancia euclídea < 4 pt = clic (`clickSlop`) | `ChordGrid.swift:141,273-300` |
| Clic frente a arrastre en la tira | `abs(translation.width)` < 4 pt (solo horizontal; la tira es de una fila) | `BackingTimeline.swift:290,300` |
| Gesto de la tira/rejilla | `DragGesture(minimumDistance: 0)`; en modo edición de acordes se anula (`including: .subviews`) | `BackingTimeline.swift:209,288`; `ChordGrid.swift:166-167,272` |
| Asa de borde | `DragGesture(minimumDistance: 1)`; zona de agarre 16 pt de ancho (`grab`), barra visible 6 × `min(max(alto-10, 16), 30)` pt, cursor `columnResize` | `SectionBoxes.swift:139,145,150,152` |
| Mantener pulsado en cabecera de sección | `onLongPressGesture(minimumDuration: 0.5)`: alterna bucle de la sección (`setLoop(start...end, name:)` o `nil` si ya es ese bucle). Bucle «activo» = extremos a < 0,01 s | `SectionBoxes.swift:56-59,97-99` |
| Clic en cabecera | `selection.select(id)`: selecciona y abre hoja | `SectionBoxes.swift:96` |
| Longitud mínima de sección | 0,5 s (`SectionEditor.minLength`); igualdad de tiempos 0,01 s (`sameTime`) | `Packages/Store/Sources/Store/SectionEditor.swift:9,11` |
| Barra de posición | `DragGesture(minimumDistance: 0)`: seek continuo cada ≥ 0,12 s (`scrubInterval`) y seek final al soltar; clic = salto; alto 22; pista 10 de alto, bola 14, caja de bucle alto 22 | `BackingTimeline.swift:560-561,590-606,611` |
| Fader | `DragGesture(minimumDistance: 0)`: y → dB lineal, rango −60…+6 dB, imán a 0 dB si `abs(d) < 1,5`; doble clic = 0 dB. Fader 28 × (150 − (276 − alto canal), mín. 40) | `BackingMixer.swift:285-304`, `BackingController.swift:11`, `BackingMixer.swift:166-168` |
| Master compacto | `Slider` −60…+6, imán a 0 si `abs < 1,5` | `BackingMixer.swift:93-94` |
| Tempo | `Slider` 50…200 %, paso 5 % (`round(v/5)*0.05`), ancho 120 | `BackingTimeline.swift:447-450` |
| Afinación fina | `Slider` `StudySession.fineCentsRange`, redondeado a entero, ancho 70 | `BackingTimeline.swift:377-379` |
| Doble clic en nombre de canal de guitarra | Pasa a edición (solo si el canal tiene `rename`: guitarras separadas) | `BackingMixer.swift:204-206` |

### 6.4 Arrastre de bucle (tira y rejilla)

1. `onChanged`: si el desplazamiento ≥ 4 pt, calcula el acorde (tira, `stripIndex(at:)`) o la celda de pulso (rejilla, `ChordGridGeometry.hit`) bajo el inicio y bajo el puntero, y guarda `stripDrag`/`dragRange` como rango de **vista previa** (resalta los acordes cuyo punto medio cae dentro). No toca el reproductor.
2. `onEnded`: `selection.clear()` siempre. Si < 4 pt: `ctl.seek(to:)` al inicio del acorde (tira) o del pulso (rejilla). Si no: rango `chords[min].start...chords[max].end` (tira) o `lo.time...hi.end` (rejilla) → `StudyBridge.snap(session.beats, rango, bar:)` → `BeatGrid.snap` (`Packages/StudyKit/Sources/StudyKit/Beat/BeatGrid.swift:66-84`: ambos extremos al pulso/compás más cercano; si queda vacío, avanza al siguiente o retrocede al anterior) → `ctl.setLoop(rango, name: "acordes"|"compases")`.
3. `stripIndex`: acorde cuyo marco contiene la x; si cae en un hueco, el de `midX` más cercano (`BackingTimeline.swift:281-284`). Sin imán por distancia: el imán es la cuantización a pulso/compás.
4. Marcas por botón: «Inicio» pone un inicio pendiente a la posición actual (si ya hay bucle y `time < fin`, mueve el inicio del bucle); «Fin» cierra (`pending...time`, nombre nil) o mueve el fin (`BackingTimeline.swift:412-425`). «Fin» deshabilitado sin inicio pendiente ni bucle.
5. La x del bucle de la vista previa y del bucle activo se pintan con `TF.accent` (relleno 0,22 en la tira, 0,28 en la rejilla).

### 6.5 Asas de borde de sección y su imán

- Solo la sección **seleccionada** muestra asas: dos `SectionEdgeHandle`, fuera del `ForEach` de trozos y con identidad fija (si no, el arrastre muere al cambiar de fila; `SectionGridBoxes.swift:28-34`). Tira: `top = headerHeight (22)`, alto = caja − 22 (`SectionBoxes.swift:218-226`). Rejilla: bordes reales del primer y último trozo, `top = pieza.minY + 18` (`SectionGridBoxes.swift:45-63`).
- Primer evento del gesto: crea `SectionEdgeDrag(editor:id:isStart:cells:bars:grab:)` con las secciones de ese momento; se recrea si cambian id, borde o `startLocation` (`SectionBoxes.swift:173-177`).
- Cuenta (todo en `Store.SectionEdgeDrag`, `SectionEdgeDrag.swift`):
  - Posición → tiempo: fila cuya franja vertical contiene la y (si no, la más cercana); en ella, celda bajo la x (si cae en hueco, la más cercana); tiempo interpolado dentro de la celda (:66-80).
  - Borde inicial: el puntero se mide desde donde está **dibujado** el borde (`anchor`), no desde donde se agarró el asa: `edgePoint = anchor + (location − grab)` (:100-103). Sin moverse, no salta.
  - Imán: límite más cercano (`min |b − t|`) entre los cambios de acorde dibujados (más el primer `time` y el último `end` de las celdas) y el borde original; con ⌥ y si hay compases, entre los inicios y fines de compás (`SectionGridBoxes.swift:104-107`, `SectionBoxes.swift:229-235`) (:106-110).
  - Límites (`SectionEditor.clampedEdge`, :127-147): la sección no baja de 0,5 s; al llegar a la vecina inmediata la empuja hasta dejarla en 0,5 s (sin cascada: su otro borde no se mueve); contra un solo se detiene en su borde.
- Vista previa: `preview = d.sections(at: location, bar:)` en cada `onChanged` (sin limitar cadencia); las cajas se pintan con `edge.preview ?? session.sections`. Al soltar: `session.setSectionEdge(id, start:, to: d.edge(...))` y `cancel()`. Si el sistema cancela el gesto (`@GestureState active` vuelve a false sin `onEnded`) se llama `onCancel` y se descarta la vista previa (`SectionBoxes.swift:141,156`).
- Los cambios son **locales hasta «Aplicar»** (`session.hasUnappliedSections`); «Descartar» vuelve a lo guardado.
- Geometría de la rejilla: `labelWidth 84`, `rowHeight 46`, `rowSpacing 4`, `sectionGutter 18`, `barGap 4`, 4 compases por fila (8 si `(ancho − 84)/8 ≥ 112`), 4 filas visibles (`ChordGrid.swift:131-142,148`). Trozo de caja: sobresale `inset = 2` a los lados y por debajo; se incluyen las celdas cuyo punto medio cae en `[start, end)` (`SectionGridBoxes.swift:18,66-84`). Tira: `headerHeight 22`, `inset 2`, ancho mínimo de caja 8 (`SectionBoxes.swift:201-203,254`).

### 6.6 Menús contextuales (clic derecho / `.contextMenu`)

| Dónde | Entradas | Fichero:línea |
| --- | --- | --- |
| Cabecera de una caja de sección | «Renombrar y ajustar…» (selecciona y abre hoja), «Quitar marca de solo»/«Marcar como solo», separador, «Eliminar sección» (destructivo) | `SectionBoxes.swift:100,268-279` |
| Acorde de la tira (fuera del modo edición) | Con bucle activo: «Marcar sección», «Marcar como solo». Si el punto medio del acorde está en una sección: separador (si hubo las anteriores) + el menú de sección anterior | `BackingTimeline.swift:198,233-244` |
| Nombre de un canal de guitarra | «Cambiar nombre…» (solo con `rename`) | `BackingMixer.swift:206` |
| Rejilla de acordes, barra de posición, faders | Ninguno | — |

Las entradas del menú no se muestran como acciones separadas del clic izquierdo salvo «Eliminar sección» y los «Marcar…» sobre acorde.

### 6.7 Foco

- Hoja de sección: al aparecer, `nameFocused = true` en el siguiente ciclo (`DispatchQueue.main.async`), el nombre editable queda enfocado y seleccionable (`SectionBoxes.swift:337-340`).
- Edición de nombre de canal: `startEditing()` pone `focused = true`; perder el foco ejecuta `commit()` (`BackingMixer.swift:190-198,210-214`).
- Al activar «Editar acordes» o cambiar `editMode`: `chordEditing = nil`, `gridEditing = nil`, `selection.clear()`; al plegar/expandir: `selection.popover = nil` (`BackingTimeline.swift:41-42`).
- `SpaceKeyMonitor` y `SectionKeyMonitor` solo existen mientras la tarjeta está en pantalla (`onAppear`/`onDisappear`, `:44-57`). Tablatura tiene su propio `SpaceKeyMonitor` (`TabScreen.swift:55`).
- Modo edición de acordes: los acordes pasan a ser botones que abren `ChordEditor`; los gestos de la tira/rejilla (saltar, bucle) y de bucle por arrastre quedan desactivados y la franja de acordes se enmarca con `TF.accent` 1,5 (`BackingTimeline.swift:172-173,189-195,209`; `ChordGrid.swift:166,250-252`).

### 6.8 Auto-scroll (no es entrada, pero afecta al foco visual)

Tira: `proxy.scrollTo(acorde actual, anchor: .center)` con animación al cambiar el acorde actual y al aparecer (`BackingTimeline.swift:213-216`). Rejilla: igual por fila actual y al cambiar compases por fila (`ChordGrid.swift:174-176`).

### 6.9 Diferencias de atajos SwiftUI/web

La web (`WinApp/Web`) añade accesibilidad por teclado que el Mac solo da por VoiceOver. Para Flutter, la base es el Mac; las filas «solo web» no se portan salvo las que `decisiones-interfaz.md` recoja: flechas en sliders y barra de posición = comportamiento por defecto de Flutter; ⇧+Espacio = no se porta.

| Acción | SwiftUI (Mac) | Web | Fichero:línea (web) | Nota |
| --- | --- | --- | --- | --- |
| Reproducir/pausar | Espacio sin ⌘⌃⌥⇧; no con hoja delante; no escribiendo (`NSText`); sin repetición | Espacio (`e.code === 'Space'`) sin ⌃ ⌘ ⌥ (⇧ **sí** pasa); no en `INPUT/SELECT/TEXTAREA`; solo con tema listo; sin repetición | `screens/backing.js:144-156` | Diferencia: ⇧+Espacio alterna en web y no en Mac. Web tampoco comprueba hojas modales (el foco queda en la hoja y no suele ser un input, así que puede alternar con una hoja abierta). En Flutter no se porta ⇧+Espacio (decisiones-interfaz.md, Backing: ⇧+Espacio). |
| Borrar sección seleccionada | Supr / Retroceso | `Delete` / `Backspace` | `sections.js:49-56` | Web además aborta si hay `.menu`, `.modal` o `.popover` abierto y exige `.strip-canvas`/`.grid-canvas` en pantalla; Mac no mira popovers; Flutter sigue a la web: con popover abierto no borra (decisiones-interfaz.md). Ambos: sin ⌘⌃⌥ (web excluye también ⌃/⌘/⌥ con `ctrlKey/metaKey/altKey`) |
| Deseleccionar | Esc si no hay hoja abierta | `Escape` si `!sectionPanel.value` | `sections.js:56` | Igual |
| Cerrar popover | Esc nativo / clic fuera | `Escape` (captura, `stopPropagation`), clic fuera (`mousedown`) y pérdida de foco de la ventana (`blur`) | `chord-editor.js:28-35` | Web cierra además al perder el foco la ventana. Resuelto: solo existe en la web, no se porta (decisiones-interfaz.md) |
| Confirmar nombre de sección | Enter | `Enter` en el input | `sections.js:135` | Igual |
| Cancelar nombre de sección | Esc en el campo | `Escape` → `onClose('escape')` sin guardar | `sections.js:172` | Igual |
| Nombre de canal | Doble clic; clic derecho → «Cambiar nombre…»; Enter/Esc | `onDblClick` y `onContextMenu` (con `renamable`); Enter/Esc | `mixer.js:89-92` | Igual |
| Fader por teclado | Solo VoiceOver ±1 dB | `↑`/`→` +1 dB, `↓`/`←` −1 dB (redondeado a entero), con ⇧ pasos de 3 dB, `Home` = 0 dB | `mixer.js:58-66` | Solo web. Resuelto: lo que tenga SwiftUI; `Semantics(onIncrease/onDecrease)` con el mismo paso (±1 dB) y sin teclas propias (decisiones-interfaz.md) |
| Fader doble clic | 0 dB | 0 dB | `mixer.js:69` | Igual |
| Barra de posición por teclado | Solo VoiceOver ±5 s | `→` +5 s, `←` −5 s (foco en el slider) | `controls.js:73-77` | Solo web; en Flutter, flechas por defecto con foco, sin trabajo extra (decisiones-interfaz.md) |
| Alt al arrastrar bucle/borde | ⌥ → compases | `e.altKey` | `strip.js:287-288`, `grid.js:283-284`, `strip.js:245,262`, `grid.js:243,258` | Igual (en Windows Alt sola activa la barra de menús del sistema solo en Win32; en WebView2 no) |
| ◀ ▶ del borde con Alt | `NSEvent.modifierFlags` | `e.altKey` | `sections.js:108` | Igual |
| Mantener pulsado = bucle de sección | 0,5 s | `LONG_PRESS_MS = 500` | `strip.js:52`, `grid.js:23` | Igual |
| Umbral clic/arrastre | 4 pt | `CLICK_SLOP = 4` | `strip.js:50`, `grid.js:21` | Igual |
| Rueda sobre la tira | `ScrollView` nativo | `onWheel`: usa `deltaX` o `deltaY` con ⇧ para desplazar horizontal | `strip.js:302` | Solo web (Mac: gesto de trackpad/rueda con scroll horizontal). Resuelto: no se porta; queda el scroll por defecto de Flutter (decisiones-interfaz.md) |
| Cadencia de la vista previa del borde | Sin limitar | ~10/s al núcleo (`PREVIEW_EVERY_MS = 100`), con seguimiento local entre respuestas | `section-drag.js:57,5` | Es consecuencia de que el cálculo vive en el núcleo en web. Resuelto: sin periodo fijo; una sola llamada en vuelo por arrastre, la última posición gana, y una final al soltar (decisiones-interfaz.md) |
| Zona de agarre del asa | 16 pt | `HANDLE_GRAB = 16`; `DRAG_MIN = 1` | `section-drag.js:11-15` | Igual |

Resuelto: con el popover de sección abierto y el foco fuera del nombre, Supr/Retroceso NO borra la sección (como la web; difiere de SwiftUI por robustez) (decisiones-interfaz.md, «Cerradas por robustez y fiabilidad»: Backing, Supr con el popover abierto).

## 7. Hojas y popovers

Backing no usa `.sheet`; todo son `.popover` anclados, más menús. Tamaños en pt (px lógicos).

### 7.1 Hoja «Sección / Solo» (`SectionPopover`, `SectionBoxes.swift:283-415`)

- **Se abre**: clic en la cabecera de una caja, «Renombrar y ajustar…», al marcar una sección/solo (`markLoop` → `select`). Ancla `arrowEdge: .bottom`, solo desde el primer trozo de la caja (`isFirst`). Una a la vez (`selection.popover: UUID?`).
- **Composición** (VStack, spacing 12, padding 16, ancho 300): título «Sección» o «Solo» (`TF.display(16)`); campo «Nombre» (`roundedBorder`, enfocado); rejilla 3 columnas de sugerencias (spacing 6; botones alto 24, radio 6, activa `TF.line`, resto `TF.field`; `Intro, Estrofa, Estribillo, Puente, Final`); fila «Color» (etiqueta 46 de ancho; 7 círculos de 20 con aro `TF.text` 2 pt y `padding(-3)` si es el elegido; el naranja no se ofrece; en solo: círculo `TF.accent` + «Los solos van en naranja»); `Toggle «Solo»` (switch pequeño, tinte `TF.accent`); `Divider`; filas «Inicio» y «Fin» (etiqueta 46, ◀ 30×24 radio 6, tiempo `m:ss.d` en semibold 14 monoespaciado minWidth 64, ▶); nota «◀ ▶ mueven por acorde · ⌥ por compás» (11, `TF.muted`); fila «Escuchar en bucle» (icono `repeat`) a la izquierda y «Eliminar» (destructivo) a la derecha; «Hecho» a la derecha (default).
- **Estados**: color de solo vs. paleta (`SectionEditor.paletteCount = 7`); el chip de sugerencia activa se resalta si `draft == name`; «Solo» al cambiar mantiene el nombre por defecto sincronizado («Solo»/«Solo 2», «Sección N») si el usuario no lo tocó (`SectionBoxes.swift:316-321`; `SectionEditor.swift:27-38,81`).
- **Acciones**: nombre vacío → nombre por defecto (`SectionEditor.swift:73`); color: clic en la elegida vuelve a automático (`setSectionColor(id, nil)`); ◀▶ → `nudgeSectionEdge`; «Escuchar en bucle» → `setLoop(start...end, name)`, `seek(start)`, y reproduce si estaba parado (`:398-403`); «Eliminar» → `selection.clear()` + `removeSection`; «Hecho»/Enter → `renameSection` + cierra; Esc en el campo → cierra sin renombrar; cerrar de otra forma → renombra con el borrador (`onDisappear`, `:341`).

### 7.2 Hoja «Acorde» (`ChordEditor`, `BackingTimeline.swift:480-557`)

- **Se abre**: solo en modo edición de acordes, clic en un acorde de la tira (popover del botón del chip) o en una celda de la rejilla con acorde (`chordEditing: Int?`, `gridEditing: Double?`; uno a la vez). En la rejilla recibe `time = c.time`.
- **Composición** (VStack spacing 12, padding 16): título «Acorde» (`TF.display(16)`); 12 raíces en rejilla de 6 columnas de 44 (spacing 6) con nombres `ChordLabel(index: r*qualityCount+1).name`; calidades en 4 columnas de 60 (`mayor` si el sufijo está vacío); chip «N (sin acorde)»; `Divider`; «Partir aquí» a la izquierda, «Quitar corrección» a la derecha. Chip: alto 30, minWidth 36, padding 4, radio 6, activo `TF.accent`/`TF.accentInk`, inactivo `TF.field`.
- **Estados**: raíz y calidad iniciales del acorde mostrado (transpuesto; en Flutter el nombre transpuesto y las formas los entrega el núcleo, decisiones-interfaz.md); «Partir aquí» deshabilitado si el cursor no cae dentro del tramo o el pulso más cercano queda a ≤ 0,05 s de un extremo; «Quitar corrección» deshabilitado sin overrides que solapen el tramo.
- **Acciones**: elegir raíz o calidad escribe en cuanto hay las dos (`commit()` → `session.setChord(start:end:index:)`, índice sin transponer = `shown.transposed(by: −transpose).index`; la conversión a índice sin transponer se confirma en `backing-contrato.md`); N → `setChord(... noChordIndex)`; «Partir aquí» → dos `setChord` partidos en `nearestBeat(time)`; «Quitar corrección» → `removeChordOverrides(in:)`. El popover **no se cierra** al elegir.

### 7.3 Menú «Tonalidad» (`BackingTimeline.swift:348-361`)

`Menu` con `.borderlessButton`, deshabilitado sin `session.analysis`. 24 entradas (12 raíces × mayor/menor en el orden `0..<24`, texto «Do mayor», «Do menor»…, almacenadas sin transposición con `transposed(by: −transpose)`), y si hay corrección: separador + «Volver a la detectada». Etiqueta: nombre + « (corregida)» si `keyOverride != nil`. Web equivalente: `KeyMenu` (`chord-editor.js:92-109`).

### 7.4 Menús `Picker` de Transponer y Capo (`BackingTimeline.swift:363-375`)

`Picker` de macOS (ancho 112): Transponer = `StudySession.transposeRange` con «0 semitonos» y `%+d`; Capo = «Sin capo» y «Traste 1…12».

### 7.5 Menús contextuales

Ver 6.6 (sección, acorde de la tira, nombre de canal).

### 7.6 Banners (no son hojas, pero son bloques de estado)

`bannerBox`: padding 16×12, radio 10, fondo `TF.field`, borde `TF.fieldLine` (`BackingView.swift:195-200`). Tres: error de carga (`ctl.loadError`, `TF.danger`), analizando (con `ProgressView` pequeño), sin análisis («Analizar») y fallo («Reintentar»).

## 8. Textos

Claves `study_<elemento>` en camelCase. Los textos con `%@`/`%d` son parámetros ICU `{x}` en ARB. Líneas de `App/Sources/` salvo indicación.
| Clave ARB | Texto literal | Fichero:línea |
| --- | --- | --- |
| `study_title` | Backing track | `BackingView.swift:36`, `:123` |
| `study_chooserEmpty` | Aún no hay temas separados. Importa uno y sepáralo en la biblioteca. | `BackingView.swift:38` |
| `study_chooserPick` | Elige un tema | `BackingView.swift:40` |
| `study_withoutGuitars` | Sin guitarras | `BackingView.swift:129` |
| `study_tabButton` | Tablatura | `BackingView.swift:140` |
| `study_tabButtonTooltip` | Abrir la tablatura de este tema | `BackingView.swift:143` |
| `study_notSeparatedTitle` | Este tema aún no está separado | `BackingView.swift:151` |
| `study_notSeparatedBody` | Backing track necesita los stems. Sepáralo desde la biblioteca y vuelve. | `BackingView.swift:152` |
| `study_goToLibrary` | Ir a la biblioteca | `BackingView.swift:153` |
| `study_analyzing` | Analizando acordes y pulso… Puedes reproducir mientras tanto. | `BackingView.swift:169` |
| `study_analysisMissing` | Sin análisis de acordes ni pulso todavía. | `BackingView.swift:175` |
| `study_analyze` | Analizar | `BackingView.swift:177` |
| `study_analysisFailed` | No se pudo analizar: {message} | `BackingView.swift:183` |
| `study_retry` | Reintentar | `BackingView.swift:185` |
| `study_errorLoadStems` | No se pudieron cargar los stems ({error}). | `BackingController.swift:76` |
| `study_errorPlay` | No se pudo reproducir ({error}). | `BackingController.swift:132` |
| `study_errorSaveStudy` | No se pudo guardar el estudio: {error} | `StudySession.swift:340` |
| `study_errorSaveGuitarOptions` | No se pudieron guardar las opciones: {error} | `StudySession.swift:128` |
| `study_errorSaveSections` | No se pudieron guardar las secciones: {error} | `StudySession.swift:191` |
| `study_errorSaveGuitarNames` | No se pudieron guardar los nombres: {error} | `StudySession.swift:346` |
| `study_chords` | Acordes | `BackingTimeline.swift:67` |
| `study_editChords` | Editar acordes | `BackingTimeline.swift:71` |
| `study_clearOverrides` | Quitar todas ({count}) | `BackingTimeline.swift:85` |
| `study_clearOverridesTooltip` | Quita todas las correcciones de acordes de este tema | `BackingTimeline.swift:92` |
| `study_editModeHint` | Modo edición: clic en un acorde para cambiarlo o partirlo. No se marcan bucles. | `BackingTimeline.swift:94` |
| `study_dragHint` | Clic: saltar · arrastrar: bucle (⌥ = compases) | `BackingTimeline.swift:95` |
| `study_markSection` | Marcar sección | `BackingTimeline.swift:100` (y `:237`) |
| `study_markSolo` | Marcar como solo | `BackingTimeline.swift:101` (y `:238`) |
| `study_markSectionTooltip` | Marca el bucle como una sección | `BackingTimeline.swift:131` |
| `study_markSoloTooltip` | Marca el bucle como un solo: sus guitarras se separan al aplicar | `BackingTimeline.swift:131` |
| `study_expand` | Expandir | `BackingTimeline.swift:106` |
| `study_collapse` | Plegar | `BackingTimeline.swift:106` |
| `study_expandA11y` | Expandir acordes | `BackingTimeline.swift:115` |
| `study_collapseA11y` | Plegar acordes | `BackingTimeline.swift:115` |
| `study_noChords` | Sin acordes detectados. | `BackingTimeline.swift:161` |
| `study_chordsAfterAnalysis` | Los acordes aparecerán al terminar el análisis. | `BackingTimeline.swift:161` |
| `study_noGrid` | Sin rejilla de compases todavía. | `ChordGrid.swift:184` |
| `study_barLabel` | c. {number} | `ChordGrid.swift:204` |
| `study_nextChord` | Siguiente: {name} | `BackingTimeline.swift:316` |
| `study_capoShown` | Capo {fret} | `BackingTimeline.swift:317` |
| `study_tempoDetected` | Tempo detectado | `BackingTimeline.swift:345` |
| `study_bpm` | {bpm} BPM | `BackingTimeline.swift:345` |
| `study_key` | Tonalidad: | `BackingTimeline.swift:347` |
| `study_keyMajor` / `study_keyMinor` | {note} mayor / {note} menor | `BackingTimeline.swift:332,339` |
| `study_keyCorrected` | (corregida) | `BackingTimeline.swift:357` |
| `study_keyBackToDetected` | Volver a la detectada | `BackingTimeline.swift:354` |
| `study_transpose` | Transponer | `BackingTimeline.swift:363` |
| `study_transposeZero` | 0 semitonos | `BackingTimeline.swift:366` |
| `study_capo` | Capo virtual | `BackingTimeline.swift:370` |
| `study_capoNone` | Sin capo | `BackingTimeline.swift:372` |
| `study_capoFret` | Traste {n} | `BackingTimeline.swift:373` |
| `study_fineTune` | Afinación fina | `BackingTimeline.swift:376` |
| `study_cents` | {n} cents | `BackingTimeline.swift:379` |
| `study_noteNames` | Do, Do#, Re, Re#, Mi, Fa, Fa#, Sol, Sol#, La, La#, Si | `BackingView.swift:9` |
| `study_play` / `study_pause` | Reproducir / Pausar (accesibilidad) | `BackingTimeline.swift:435` |
| `study_loopStartButton` | Inicio {time} (el sufijo solo con inicio pendiente) | `BackingTimeline.swift:400` |
| `study_loopStartTooltip` | Marca el inicio del bucle en la posición actual | `BackingTimeline.swift:403` |
| `study_loopEnd` | Fin | `BackingTimeline.swift:404` |
| `study_loopEndTooltip` | Marca el final del bucle en la posición actual | `BackingTimeline.swift:407` |
| `study_loopLabel` | Bucle: {name} · {from}–{to} | `BackingTimeline.swift:444` |
| `study_loopFree` | libre | `BackingTimeline.swift:444` |
| `study_loopNameChords` / `study_loopNameBars` | acordes / compases (nombre del bucle creado por arrastre) | `BackingTimeline.swift:305`; `ChordGrid.swift:289` |
| `study_loopClearA11y` | Quitar bucle | `BackingTimeline.swift:447` |
| `study_tempo` | Tempo | `BackingTimeline.swift:455` |
| `study_metronome` | Metrónomo | `BackingTimeline.swift:463` |
| `study_positionA11y` | Posición | `BackingTimeline.swift:610` |
| `study_positionValueA11y` | {time} de {duration} | `BackingTimeline.swift:611` |
| `study_apply` | Aplicar | `GuitarOptionsViews.swift:37` |
| `study_applyTooltip` | Guarda las secciones. Las pistas de guitarra se rehacen, en segundo plano, solo si cambian los solos | `GuitarOptionsViews.swift:39` |
| `study_discard` | Descartar | `GuitarOptionsViews.swift:34` |
| `study_discardTooltip` | Vuelve a las secciones guardadas | `GuitarOptionsViews.swift:36` |
| `study_stereoSplit` | Guitarras en L y R | `GuitarOptionsViews.swift:19` |
| `study_stereoSplitTooltip` | L = canal izquierdo, R = canal derecho de la pista de guitarras | `GuitarOptionsViews.swift:23` |
| `study_guitarsProcessing` | Procesando guitarras… | `GuitarOptionsViews.swift:63` |
| `study_sectionBoxTooltip` | {name}{ (solo)} · {from}–{to} · clic: editar, mantener: bucle | `SectionBoxes.swift:106` |
| `study_sectionA11y` | {Solo\|Sección} {name}, {from} a {to} | `SectionBoxes.swift:108` |
| `study_sectionA11yHint` | Clic para editarla; mantener pulsado para repetirla en bucle | `SectionBoxes.swift:109` |
| `study_handleStartA11y` / `study_handleEndA11y` | Borde de inicio / Borde de fin | `SectionBoxes.swift:157` |
| `study_menuRenameAdjust` | Renombrar y ajustar… | `SectionBoxes.swift:274` |
| `study_menuUnmarkSolo` | Quitar marca de solo | `SectionBoxes.swift:275` |
| `study_menuMarkSolo` | Marcar como solo | `SectionBoxes.swift:275` |
| `study_menuDeleteSection` | Eliminar sección | `SectionBoxes.swift:277` |
| `study_sectionSheetSection` / `study_sectionSheetSolo` | Sección / Solo | `SectionBoxes.swift:299` |
| `study_sectionName` | Nombre | `SectionBoxes.swift:300` |
| `study_sectionSuggestions` | Intro, Estrofa, Estribillo, Puente, Final | `SectionBoxes.swift:289` |
| `study_sectionColor` | Color | `SectionBoxes.swift:349` |
| `study_sectionColorN` | Color {n} (accesibilidad de la muestra) | `SectionBoxes.swift:360` |
| `study_sectionSoloOrange` | Los solos van en naranja | `SectionBoxes.swift:352` |
| `study_sectionSolo` | Solo | `SectionBoxes.swift:316` |
| `study_sectionStart` / `study_sectionEnd` | Inicio / Fin | `SectionBoxes.swift:323-324` |
| `study_sectionNudgeA11y` | {Inicio\|Fin} {después\|antes} | `SectionBoxes.swift:389` |
| `study_sectionNudgeHint` | ◀ ▶ mueven por acorde · ⌥ por compás | `SectionBoxes.swift:325` |
| `study_sectionListen` | Escuchar en bucle | `SectionBoxes.swift:327` |
| `study_sectionDelete` | Eliminar | `SectionBoxes.swift:329` |
| `study_sectionDone` | Hecho | `SectionBoxes.swift:333` |
| `study_sectionDefaultName` | Sección {n} / Solo / Solo {n} (nombres por defecto; el núcleo los genera) | `Packages/Store/Sources/Store/SectionEditor.swift:27-33` |
| `study_chordSheetTitle` | Acorde | `BackingTimeline.swift:514` |
| `study_chordMajor` | mayor (calidad con sufijo vacío) | `BackingTimeline.swift:523` |
| `study_chordNone` | N (sin acorde) | `BackingTimeline.swift:527` |
| `study_chordSplit` | Partir aquí | `BackingTimeline.swift:534` |
| `study_chordSplitTooltip` | Parte el tramo en el pulso más cercano al cursor de reproducción | `BackingTimeline.swift:541` |
| `study_chordRemoveOverride` | Quitar corrección | `BackingTimeline.swift:543` |
| `study_mixer` | Mezclador | `BackingMixer.swift:40` |
| `study_mixerOutput` | Salida: {device} (— si vacío) | `BackingMixer.swift:37` |
| `study_stemVocals` … `study_stemOther` | Voz, Batería, Bajo, Guitarra, Piano, Resto | `BackingMixer.swift:25` |
| `study_master` | Master | `BackingMixer.swift:90`, `:244` |
| `study_muted` | Silenciado | `BackingMixer.swift:178` |
| `study_dbValue` | {value} dB (coma decimal, 1 decimal) | `BackingMixer.swift:178`, `:277` |
| `study_muteA11y` / `study_unmuteA11y` | Silenciar {name} / Activar {name} | `BackingMixer.swift:181` (también `:123` en el compacto) |
| `study_soloA11y` | Solo {name} | `BackingMixer.swift:182` (también `:124`) |
| `study_muteLetter` / `study_soloLetter` | M / S | `BackingMixer.swift:181-182` |
| `study_channelRenameTooltip` | Doble clic para cambiar el nombre | `BackingMixer.swift:205` |
| `study_channelRenameMenu` | Cambiar nombre… | `BackingMixer.swift:206` |
| `study_channelNameField` | Nombre | `BackingMixer.swift:194` |
| `study_faderA11y` | Volumen | `BackingMixer.swift:307` |

Notas de texto:

- Formato de tiempo: `m:ss` (`BackingTimeline.swift:473`, definición de `Fmt.clock`) y `m:ss.d` en la hoja de sección (`SectionBoxes.swift:393-396`). Porcentaje: `{n} %` con espacio (`Theme.swift:140`).
- Código muerto no listado: `RecordButton`, `ComparePanel`, `TakeChannel` (`BackingRecord.swift`) y `takeError`/`takeSaveError` (`BackingController.swift:309`, `StudySession.swift:316`) porque solo los alimenta la grabación/toma, que ya no sale en Backing.
- Hay textos de depuración (`#if DEBUG`, `--grid-hit-selftest`, `--select-section`, `DebugLog`) que no se portan.
- No hay diálogos de confirmación en Backing: eliminar sección y quitar bucle son inmediatos (sin `.alert` ni `confirmationDialog`).
- Los mensajes de error en ARB deben conservar `{error}` tal como el núcleo lo manda; `AppCore` ya devuelve `saveError` («No se pudo guardar el estudio: …», ver `docs/codemap/AppCore.md`).
