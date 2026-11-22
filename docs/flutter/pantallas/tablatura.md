# Ficha de pantalla · Tablatura (parte visual nativa)

Ola: por asignar. Área del puente: `tab` (+ `link.*`/`app.info` para la hoja de Songsterr). Destino: `FlutterApp/lib/features/tab/`.

Esta ficha cubre los apartados 1, 2, 3, 4, 7, 10 y 11: lo que es SwiftUI nativo alrededor del WebView de alphaTab. Remisiones:

- Apartados 5 (contrato) y 9 (desvíos): `docs/flutter/pantallas/tablatura-contrato.md`.
- Apartados 6 (interacción: teclado, arrastres, clic en el pentagrama, barra espaciadora) y 8 (textos ARB): `docs/flutter/pantallas/tablatura-interaccion.md`.

Abreviaturas de evidencia: TS = `App/Sources/TabScreen.swift`, TSS = `TabSourceSheet.swift`, TC = `TabController.swift`, TWH = `TabWebHost.swift`, SP = `SongsterrPreview.swift`, SWL = `SongsterrWebLoader.swift`. Tokens y widgets `Tf…`: `docs/flutter/tokens-componentes.md` (no se redefinen aquí). Los textos nativos sin `.font` explícito heredan la fuente de sistema de macOS (13 pt); en Flutter, `TfText` body 13 (por confirmar con captura).

## 1. Qué es

Pantalla de tablatura del tema abierto: muestra la partitura (alphaTab dentro de un WebView) con una cabecera de acciones, selector de fuente (Songsterr o transcripción automática), pastillas de pista con M/S, barra de edición de notas y transporte. Se llega desde la barra lateral (sección Tablatura); sin tema elegido, TS:13-14 muestra un selector de temas con separación hecha (`chooser`, TS:27-46) y, con tema, `TabContent` (TS:15-16).

Es la única pantalla con un WebView propio (el de alphaTab) y otro secundario (vista previa de Songsterr dentro de la hoja). Todo lo demás es SwiftUI nativo y se rehace en Flutter. Fuera de esta ficha queda el contenido del WebView (alphaTab, `WinApp/Web/tab/`).

## 2. Referencia visual (SwiftUI)

### 2.1 Marco, selector de tema y cabecera

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Selector de tema (sin tema elegido) | TS:27-46 | `VStack` alineado a la izquierda, `spacing: 16`, `padding(.horizontal, 40).padding(.vertical, 32)`. «Tablatura» `TF.display(30)`. Sin temas separados: texto `TF.muted`. Con temas: «Elige un tema» `TF.muted` y una fila por tema: `HStack` título + `Spacer`, `padding(.horizontal, 12).padding(.vertical, 10)`, fondo `TF.field`, radio 10, estilo plano. Solo entradas con `separationState == done`. |
| Cargando la sesión | TS:17-19 | `ProgressView` pequeño centrado (`TfSpinner`) mientras `model.study`/`model.backing` son nil. |
| Marco de la pantalla | TS:59-72 | `VStack(alignment: .leading, spacing: 14)`; `padding(.horizontal, 36).padding(.vertical, 20)`; ocupa todo, alineado arriba a la izquierda. Orden: cabecera, aviso (si hay), tarjeta de tablatura, barra de edición (si `editMode` y `phase == .ready`), transporte. |
| Cabecera: títulos | TS:122-129 | `HStack(alignment: .bottom)`; columna `spacing: 2`: «artista · título» `TF.body(13)` `TF.muted` (une artista y título no nulos con « · ») y «Tablatura» `TF.display(26)`. |
| Menú «Fuente» | TS:151-167 | `Menu` sin borde (`borderlessButton`, tamaño al contenido), etiqueta «Fuente: <sourceLabel>» (TC:376: «Songsterr», «Transcripción automática» o «Sin elegir»), `TF.body(13, .medium)` `TF.text2`. Deshabilitado en `.waitingAnalysis` y `.empty`. Elementos en 2.8. Es un `TfMenu`. |
| Botón «Editar notas» | TS:132-142 | Alterna `editMode`. `padding(.horizontal, 14)`, alto 34, radio 8. Reposo: fondo `TF.field`, borde `TF.fieldLine`, texto `TF.text` `body(13,.medium)`. Activo: fondo `TF.accentBg`, borde y texto `TF.accent`, `body(13,.semibold)`. Deshabilitado si `phase != .ready` (sin estilo propio; el plano de SwiftUI atenúa). Rasgo «seleccionado» para accesibilidad. |
| Botón «Exportar a Guitar Pro» | TS:143-145 | `SecondaryButton(height: 34)` (`TfSecondaryButton(height: 34)`). Deshabilitado si `phase != .ready` o la partitura no tiene pistas. |
| Aviso (`noticeBox`) | TS:63, TS:169-181 | Solo si `tab.notices` no está vacío. `HStack(alignment: .top, spacing: 12)`: columna `spacing: 4` con un `Text` por aviso (`TF.text2`), `Spacer`, botón `xmark` plano (accesible «Cerrar aviso»). `TF.body(13)`, `padding(.horizontal, 16).padding(.vertical, 12)`, fondo `TF.field`, radio 10, borde `TF.fieldLine`. Sin icono de aviso (el `TfNotice` del kit lo añade: ver 9 de contrato). Origen de los avisos: TC:243, TC:318, TC:574. |

### 2.2 Tarjeta de tablatura (Card + zona del WebView)

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Tarjeta | TS:185-203 | `Card` (`TfCard`: fondo `card`, radio 14, borde `line`), `frame(maxHeight: .infinity)`; contenido `VStack(alignment: .leading, spacing: 12)` con `padding(18)`. De arriba abajo: selector «Oír» (si hay pistas), pastillas de pista, controles de pista (si hay pista), zona WebView, pie. |
| Selector «Oír» | TS:256-283 | Solo si `tab.entries` no está vacío. `HStack(spacing: 8)`, `TF.body(13)`: «Oír» `TF.muted`; dos cápsulas de alto 30 (h 14): «Stems» y «Transcripción» (borde 1). Activa: fondo `TF.accentBg`, borde y texto `TF.accent`, `.semibold`; inactiva: `TF.field`, borde `TF.fieldLine`, `TF.text2`, `.medium`. Con `listenMode == .mixed` ninguna activa y aparece «Mixto» `TF.muted`. Con síntesis en curso (`synthProgress`): `TfSpinner` pequeño + «Sintetizando n/total…» `TF.muted`. |
| Pastillas de pista | TS:206-242 | `ScrollView` horizontal sin indicador, `HStack(spacing: 8)`. Por pista, un `HStack(spacing: 4)` con la pastilla, «M» y «S»; todo el grupo a opacidad 0,55 si `isDimmed` (TC:1199: silenciada, o hay solo y no es ella). Pastilla: `TfPill` cápsula alto 34, h 14, `body(13, .semibold/.medium)`; contenido icono 12 pt + nombre (+ `speaker.wave.2.fill` 11 pt si la pista suena en modo transcripción); activa `TF.accent` sobre `TF.accentBg` con borde `TF.accent`; inactiva `TF.text2` sobre `TF.field` con borde `TF.fieldLine`. Iconos SF por tipo (TS:285-292): guitarra `guitars`, bajo `waveform`, batería `circle.grid.2x2`, voz `mic` (mapa a `tokens-componentes.md` §4). |
| M / S de pista | TS:244-254 | `TfToggleButton` pequeño: 28×28 (no 36), radio 7, `TF.body(11, .bold)`. Off: fondo `TF.field`, texto `TF.text2`, borde `TF.fieldLine`. On: fondo `TF.accent`, texto `TF.accentInk`, sin borde. Etiquetas accesibles: «Silenciar x»/«Activar x» y «Solo x». |
| Pistas pendientes | TS:234-239 | Tras las pastillas, una por pista en cola sin entrada: texto `body(13)` `TF.muted`, alto 34, h 14, cápsula con borde discontinuo (`dash: [3]`, `TF.fieldLine`). Requiere `CustomPainter` (borde discontinuo). |
| Controles de pista | TS:294-319 | Solo con pista seleccionada. `HStack(spacing: 16)`, `TF.body(13)` `TF.text2`. (a) Si no es batería y tiene afinación: «Afinación» `TF.muted` + `TfDropdown` de ancho 170 con `TuningPreset.fixed` (nombres TC:1046: Estándar, Medio tono abajo, Un tono abajo, Drop D) y, si hay, una entrada «Personalizada»/`customLabel`. (b) `TfCheckbox` «Oír transcripción». (c) Si la síntesis de esa pista está en `.rendering`: spinner pequeño + «Sintetizando…» `TF.muted`. (d) `Spacer` y a la derecha `headerSummary` (TC:155: «4/4 · 120 BPM» o solo «4/4») en `TF.muted`. |
| Zona WebView | TS:191-198 | `ZStack` con dos capas, `frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)`, fondo `TF.bg` al 40 % (`TfOpacity.dim`) con radio 10 y recorte `clipShape` radio 10. Es el rectángulo del `TfWebView` (mismo tamaño que la zona; sin borde propio). Ver 2.3. |
| Pie de estado | TS:374-384 | Una línea, `TF.body(13)`, alto fijo 18, `lineLimit(1)`. Texto por prioridad: `flash` (3 s, TC:885-891, color `TF.accent`) > `selectionSummary` (TC:814-826: «Compás n, pulso m · cuerda c, traste t» / «… sin nota» / en batería «… · bombo, caja» o «sin golpes») > fijo «Tablatura de Songsterr · revisa y corrige si hace falta» (pista importada) o «Transcripción automática · revisa y corrige si hace falta». Con `flash` nil el color es `TF.muted`. |

### 2.3 Qué ocupa el WebView y qué va en Flutter

Rectángulo del WebView (`TfWebView` con alphaTab): toda la zona de TS:191-198, es decir el ancho de la tarjeta menos `padding(18)` por lado y, en vertical, el hueco que deja el resto de la columna (mínimo 320 px). Fondo del WebView transparente (`drawsBackground = false`, TWH:48); el color que se ve es el de la zona (`TF.bg` @0,4) y el de la propia página.

Capas, de abajo arriba:

1. `TfWebView` (alphaTab). Opacidad 1 solo si `phase == .ready`, o si ya hay entradas y `phase == .working` (TS:193: se sigue viendo la partitura anterior mientras se transcribe otra pista). En el resto de fases, opacidad 0 (sigue vivo y cargado, no se descarga).
2. Overlay de Flutter (`overlay(tab)`, TS:321-362) que cubre el mismo rectángulo y varía por fase (2.4). Es Flutter encima del WebView; si la plataforma no permite componer Flutter sobre una vista nativa, hay que decidirlo en el `TfWebView` (pendiente de Jorge, ver 11).

Se dibuja en Flutter fuera del rectángulo: cabecera, aviso, selector «Oír», pastillas, controles de pista, pie, barra de edición, transporte. Se dibuja en Flutter encima del WebView: mensajes de fase (2.4) y el aviso de error del WebView (TS:324-326 muestra «alphaTab: <error>»; en Flutter, mensaje genérico traducido con el texto de la página como detalle, decisiones-interfaz.md «Errores de alphaTab»; `TF.danger`, `body(13)`, `padding()` de 16, esquina superior izquierda según el contenedor). Lo que pinta alphaTab dentro (pentagrama, cursor de reproducción, selección de tramo y de nota) es del WebView y va en `tablatura-contrato.md` y `tablatura-interaccion.md`: aquí ni se mide ni se reproduce.

### 2.4 Mensajes de fase (overlay)

Los cinco mensajes comparten caja: `padding(24)`, alineados arriba a la izquierda, ocupan todo el rectángulo del WebView, fondo `TF.card` (opaco), título `TF.display(18)`, cuerpo `TF.muted`.

| Fase | Fichero:línea | Notas de composición |
| --- | --- | --- |
| `.working` | TS:327-340 | `VStack(spacing: 12)`: «Transcribiendo…» `display(18)`; «La primera vez tarda un poco. Lo hecho se guarda pista a pista.» `TF.muted`; por pista en cola, `HStack(spacing: 12)`: nombre (ancho 150, a la izquierda) + `TfAccentBar` ancho 220 (valor `progress[id]`; nil = indeterminada), `body(13)`. Fondo `TF.card` opaco solo si no hay entradas (`opacity(entries.isEmpty ? 1 : 0)`); con entradas, fondo transparente y el texto se superpone a la partitura anterior. |
| `.choosingSource` | TS:341-352 | `VStack(spacing: 10)`: «Elige la fuente de la tablatura» `display(18)`; texto «Songsterr trae la tablatura hecha por la comunidad; la transcripción automática sale del audio.» `TF.muted`; `HStack` con dos `SecondaryButton(height: 34)`: «Buscar en Songsterr» y «Transcribir automáticamente». Fondo `TF.card`. |
| `.waitingAnalysis` | TS:353-356 | `message(...)` (TS:364-372, `spacing: 10`): título «Esperando el análisis del tema», cuerpo «La tablatura necesita los compases y pulsos del análisis. Puedes lanzarlo desde Backing track.», botón `SecondaryButton(height: 34)` «Analizar». |
| `.empty` | TS:357-358 | `message`: «No hay pistas que transcribir» / «Este tema no tiene stems de guitarra, bajo o batería con audio.», sin botón. |
| `.failed(m)` | TS:359-360 | `message`: «No se pudo transcribir» / `m`, sin botón. Nótese que no hay «Reintentar» (ver contrato apartado 9). |
| `.ready` + error de web | TS:323-326 | Sin caja: mensaje genérico traducido + detalle (texto de la página) en `TF.danger`, fondo transparente (SwiftUI: «alphaTab: <error>»; decisiones-interfaz.md «Errores de alphaTab»). |

### 2.5 Barra de edición

TS:388-414, visible solo con `editMode && phase == .ready`, debajo de la tarjeta. `HStack(spacing: 10)`, botones `SecondaryButton(height: 32)`, `TF.body(12)`, `Spacer(minLength: 0)` al final.

| Contexto | Elementos |
| --- | --- |
| Siempre | «Deshacer» con icono `arrow.uturn.backward` (deshabilitado sin `canUndo`), «Rehacer» con `arrow.uturn.forward` (sin `canRedo`). |
| Pista de batería (TS:394-398) | Un botón por `DrumPiece.allCases` con `pieceName` en mayúscula inicial (Bombo, Caja, Charles, Charles abierto, Tom, Platos); deshabilitados sin `selection`. Texto de ayuda «B bombo · C caja · H charles · T tom · P platos» `TF.muted`. |
| Pista melódica (TS:399-409) | «Añadir nota» (`plus`), «–» (`minus`, «Acortar nota») y «+» (`plus`, «Alargar nota») ambos deshabilitados sin `selectedNote`, «Borrar» (`trash`, sin `selectedNote`). Ayuda «Dígitos: traste · ↑ ↓: cuerda · ← →: mover · +/−: duración · ⌘Z deshacer» `TF.muted` una línea. En Windows el texto «⌘Z» pasa a «Ctrl+Z» (apartado 8 de la ficha de interacción). |

### 2.6 Transporte

TS:418-455. `HStack(spacing: 14)`, `Spacer(minLength: 0)` al final. Es el mismo transporte que Backing (los métodos son `audio.*`/`backing.*`); aquí solo se anota la composición.

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Volver al inicio | TS:421-426 | Círculo 44×44, icono `backward.end.fill` 15 pt `TF.text`, fondo `TF.field`, borde `TF.fieldLine`. «Volver al inicio». |
| Reproducir/pausa | TS:428-434 | Círculo 52×52 `TF.accent`, icono `play.fill`/`pause.fill` 20 pt `TF.accentInk`. «Reproducir»/«Pausar». |
| Reloj | TS:436-437 | `Fmt.clock(time)` `TF.text` + « / » + `Fmt.clock(duration)` `TF.muted`, `TF.display(20)`, dígitos monoespaciados. Se refresca cada 0,05 s (`Timer`, TS:57, TS:110-114) (referencia SwiftUI; en Flutter el cursor va por `Ticker` sobre `study.position`, decisiones-interfaz.md «Cursor de tablatura a 20 o 30 Hz»; el reloj numérico usa esa misma fuente y solo repinta el texto cuando cambia el valor mostrado). |
| Tempo | TS:439-446 | «Tempo» + `TfSlider` 50…200 de paso efectivo 5 (ancho 120, `TF.accent`) + porcentaje `Fmt.percent(rate)` `.semibold` `TF.text`, ancho 54 a la izquierda, dígitos monoespaciados; `body(13)` `TF.text2`. |
| Metrónomo | TS:448-450 | `TfCheckbox` «Metrónomo», `body(13)` `TF.text2`; deshabilitado sin `session.beats`. |
| Bucle | TS:457-479 | `TfMenu` sin borde: etiqueta «Bucle» (`TF.text2`) o «Bucle: <nombre\|libre> · m:ss–m:ss» (`TF.accent`), `body(13, .semibold)`. Elementos: «Sin bucle»; «Selección» si hay tramo (`spanLoopName`, TC:23); «Compás n» si hay compás seleccionado; una entrada por sección del tema. En Flutter la marca de «Selección» no se compara por texto: el bucle del tramo lleva una marca del núcleo y el texto visible sale de ARB (`tabLoopSelection`) (decisiones-interfaz.md, «Nombres por defecto que el núcleo guarda en español»; cita `TabService:42`). |

### 2.7 Diálogo de confirmación

TS:103-108: `confirmationDialog` «¿Pasar a transcripción automática?»; acción destructiva «Pasar a automática», «Cancelar»; mensaje «Se quitan las pistas de Songsterr y sus ediciones; las demás se transcriben del audio.». Se lanza desde el menú «Fuente» cuando `usesSongsterr` (TS:158). Es un `TfConfirmDialog`.

### 2.8 Menú «Fuente»

TS:153-160: «Buscar en Songsterr…» (abre la hoja, 7.1); «Cambiar emparejamiento…» solo si `usesSongsterr` (`reviewPairing`); «Transcripción automática» (deshabilitada si `tabSource == .automatic`; con Songsterr pasa por 2.7).

### 2.9 Colores sueltos

Sin hex fuera de `TF` en `TabScreen.swift`, `TabSourceSheet.swift` ni `TabWebHost.swift` (grep de `0x`/`Color(` solo devuelve la función `confidenceColor`, que usa `TF.ok/accent/danger/muted`). Opacidades literales: 0,4 (zona WebView), 0,55 (pista atenuada).

## 3. Árbol de widgets propuesto

```
TabScreen (decide chooser / cargando / contenido según backingTarget y sesión)
├─ TabThemeChooser                         // TS:27-46
└─ TabContent                              // TS:49
   ├─ TabHeader                            // TS:121
   │  ├─ TfText ×2 (artista · título, «Tablatura»)
   │  ├─ TabSourceMenu (TfMenu)            // TS:151
   │  ├─ TfPill-like «Editar notas» (toggle)
   │  └─ TfSecondaryButton(height: 34) «Exportar a Guitar Pro»
   ├─ TfNotice (aviso descartable)         // TS:169
   ├─ TfCard → TabCard                     // TS:185
   │  ├─ TabListenSelector                 // TS:257
   │  ├─ TabTrackStrip (scroll horizontal) // TS:206
   │  │  ├─ TabTrackPill (TfPill + TfToggleButton M/S compacto)
   │  │  └─ TabPendingPill (CustomPainter: borde discontinuo)
   │  ├─ TabTrackControls (TfDropdown, TfCheckbox, TfSpinner) // TS:294
   │  ├─ TabStage (Stack)                  // TS:191
   │  │  ├─ TfWebView (alphaTab)
   │  │  └─ TabPhaseOverlay (working / choosingSource / message / webError)
   │  └─ TabFooter (línea de estado)       // TS:374
   ├─ TabEditBar (TfSecondaryButton(height: 32))   // TS:388
   ├─ TabTransport (TfSlider, TfCheckbox, TfMenu)  // TS:418
   ├─ TabSourceSheetHost → TfSheet         // TSS (apartado 7.1)
   │  ├─ SongsterrChoosing / Working / Pairing / Failed
   │  └─ TfWebView (vista previa de Songsterr, panel derecho)
   └─ TfConfirmDialog «¿Pasar a transcripción automática?»
```

`CustomPainter`: borde discontinuo de la pastilla pendiente. Todo lo demás son widgets del kit o contenedores de layout. Los widgets `Tab…` son locales a `features/tab/`; el kit solo gana lo que ya listó `tokens-componentes.md` (`TfPill`, `TfNotice`, `TfSheet`, `TfDropdown`, `TfCheckbox`, `TfSlider`, `TfMenu`, `TfConfirmDialog`, `TfSpinner`, `TfAccentBar`, `TfCard`).

## 4. Estados

El estado lo decide `tab.phase` (TC:27-37) y, para la hoja, `tab.importStage` (TC:40-47). Datos de entrada: `session.project.tabSource` (nil = sin elegir), `session.beats` (nil = sin análisis), pistas con audio.

| Estado | Qué cambia en pantalla | Dato que lo decide |
| --- | --- | --- |
| Sin tema | Selector de temas (2.1); vacío: «Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.» en `TF.muted`. | `model.backingTarget == nil`; temas con `separationState == done`. |
| Cargando sesión | Spinner centrado, sin cabecera. | `backingTarget` fijado pero `model.study`/`model.backing` aún nil (TS:17-19). |
| Controlador sin crear | Solo la cabecera y un `Spacer` (TS:62-69), sin botones. | `tab == nil` durante el `.task` inicial. |
| `.waitingAnalysis` | Overlay «Esperando el análisis…» con botón «Analizar»; WebView oculto; «Editar notas», «Exportar» y menú «Fuente» deshabilitados. | Sin rejilla de compases (`session.beats == nil`). |
| `.empty` | Overlay «No hay pistas que transcribir»; mismos botones deshabilitados. | Ningún stem de guitarra, bajo o batería con audio. |
| `.choosingSource` | Overlay con dos botones; además TC:389-392 abre sola la hoja de Songsterr salvo `suppressAutoSearch`. Menú «Fuente» muestra «Sin elegir». «Editar notas» y «Exportar» deshabilitados. | `project.tabSource == nil`. |
| `.working` sin pistas | Overlay opaco «Transcribiendo…» con barras por pista (indeterminada si `progress[id] == nil`). | `phase == .working`, `entries.isEmpty`. |
| `.working` con pistas | WebView visible con la partitura previa; overlay transparente con el mismo texto encima; pastillas visibles; botones de edición deshabilitados (dependen de `.ready`). | `phase == .working`, `!entries.isEmpty`. |
| `.ready` | WebView visible; cabecera completa; barra de edición si `editMode`. | `phase == .ready`. |
| `.ready` con aviso | Cuadro de aviso entre la cabecera y la tarjeta hasta cerrarlo con la X. | `!notices.isEmpty` (TC:73; `dismissNotices`, TC:351). |
| `.ready` con error del WebView | Texto «alphaTab: …» en rojo sobre el WebView, que sigue visible (genérico + detalle, ver 2.4). | `webError` (TC:93). |
| `.failed(m)` | Overlay «No se pudo transcribir» con `m`. Sin reintento. | `phase == .failed`. |
| Modo edición | «Editar notas» activo (acento); barra de edición bajo la tarjeta; ayuda según batería o melódica. | `editMode` y `phase == .ready`. |
| Selección | Pie con «Compás n, pulso m …»; botones de edición habilitados según `selection`/`selectedNote`. | `selection`, `selectedNote`. |
| Aviso efímero | Pie en `TF.accent` durante 3 s con el texto del flash. | `flash` (TC:885-891). |
| Escuchando transcripción | Altavoz en la pastilla; casilla «Oír transcripción» marcada; selector «Oír»: «Stems»/«Transcripción»/«Mixto»; «Sintetizando n/total…» o «Sintetizando…» mientras se renderiza. | `isListening`, `listenMode`, `synthProgress`, `synth[id] == .rendering`. |
| Pista silenciada/solo | Grupo de pastilla al 55 %; M o S en acento. | `isDimmed`, `isMuted`, `isSolo`. |
| Bucle activo | Etiqueta del menú «Bucle: …» en acento. | `ctl.loop != nil`. |
| Reproduciendo | Botón central con pausa; reloj corre a 0,05 s (referencia SwiftUI; en Flutter el cursor va por `Ticker` sobre `study.position`, decisiones-interfaz.md «Cursor de tablatura a 20 o 30 Hz»; el reloj numérico usa esa misma fuente y solo repinta el texto cuando cambia el valor mostrado). | `ctl.isPlaying`, `ctl.player.currentTime`. |

## 7. Hojas y popovers

No hay popovers en esta pantalla (grep de `.popover` en `TabScreen.swift`/`TabSourceSheet.swift`: ninguno). Hay un menú «Fuente» y un menú de bucle (2.6, 2.8), un diálogo de confirmación (2.7) y una hoja (`TabSourceSheet`).

### 7.1 Hoja «Tablatura de Songsterr» (`TabSourceSheet`, TSS)

**Disparo:** TS:99-102; `tab.sourceSheetOpen`; la abre sola `askForSource` (TC:389-392) o el menú «Fuente» / botón «Buscar en Songsterr». Cierre: `closeSourceSheet`. Es un `TfSheet`.

**Marco (TSS:23-41).** `HStack(alignment: .top, spacing: 20)`: columna de lista de ancho fijo 612 (`listWidth`) con `VStack(spacing: 14)`, y, si hay vista previa, panel de ancho 640 (`previewWidth`). `padding(24)`, fondo `TF.bg`, alto fijo 640 (`sheetHeight`); ancho total 660 sin previa o 660 + 20 + 640 = 1320 con previa (en Flutter, min(1320, ventana − márgenes); lista 612 fija). `TF.body(13)` `TF.text2`. Título «Tablatura de Songsterr» `TF.display(22)`. El paso lo decide `importStage` (TC:40): `.choosing`, `.working`, `.pairing`, `.failed`.

En una ventana de Flutter menor de 1320 px de ancho la hoja con vista previa no cabe: el ancho disponible mínimo de ventana está en `tokens-componentes.md` §6; Resuelto: ancho = el menor entre 1320 y la ventana menos márgenes; la lista conserva 612 y la vista previa ocupa el resto; se comprueba con captura a 1100 (decisiones-interfaz.md, «Hoja de Songsterr de 1320 px con ventana mínima de 1100»).

**Paso `.choosing` (TSS:63-90).**

| Elemento | Línea | Composición |
| --- | --- | --- |
| Línea de búsqueda | TSS:66 | «Búsqueda: artista · título» `TF.muted`. |
| Buscando | TSS:68-70 | Spinner pequeño + «Buscando en Songsterr…», centrado en el espacio libre. Estados `.idle`/`.searching`. |
| Fallo de búsqueda | TSS:71-73, 158-168 | Caja de problema (abajo) y `Spacer`. |
| Resultados | TSS:92-139 | Ver abajo. |
| Campo de enlace | TSS:141-156 | `HStack(spacing: 8)`: campo plano «O pega un enlace de Songsterr» (`padding(.horizontal, 10)`, alto 32, fondo `TF.field`, radio 8, borde `TF.fieldLine`, Enter envía) + `SecondaryButton(height: 32)` «Usar enlace» (deshabilitado con enlace vacío tras recortar o `lookup.isBusy`). Debajo, si hay `linkIssue`, su mensaje en `TF.danger`; `spacing: 6`. |
| Botonera | TSS:78-88 | `HStack`: «Cancelar» `SecondaryButton(height: 36)`; `Spacer`; «Vista previa» `SecondaryButton(36)` (solo con previa cerrada; deshabilitado sin `selectedID`); «Transcribir automáticamente» `SecondaryButton(36)`; «Usar esta» `PrimaryButton` (deshabilitado sin `selectedSong`). |

Resultados (TSS:92-139), `VStack(spacing: 10)`:

- Ficha de la versión marcada (`selectedSong`): `padding(12)`, fondo `TF.field`, radio 10, borde `TF.fieldLine`. Título «artista · título» `body(14,.semibold)` `TF.text`; por pista una fila `spacing: 10`: nombre (ancho 190, 1 línea), instrumento `TF.muted` (ancho 170, 1 línea), afinación `TF.muted` dígitos monoespaciados. Afinación (TSS:171-175): notas de la cuerda más grave a la más aguda separadas por espacio con nombres «C C# D D# E F F# G G# A A# B» o «-» sin datos. Mientras carga (`loadingID`): spinner + «Leyendo las pistas…»; si falla (`detailIssue`): caja de problema.
- «Otros resultados» `TF.muted` y lista con desplazamiento que ocupa el resto: cada fila `padding(.horizontal, 10).padding(.vertical, 6)`, radio 8, `spacing: 4` entre filas; marcada: fondo `TF.accentBg`, icono `largecircle.fill.circle` en `TF.accent` y texto `TF.text`; no marcada: transparente, icono `circle` `TF.muted`, texto `TF.text2`; una línea. Pulsar marca la versión (`select`) y abre la vista previa (`previewOpen = true`, TSS:120).

**Caja de problema (`issueBox`, TSS:158-168).** `padding(12)`, fondo `TF.dangerBg`, radio 10, sin borde; mensaje `TF.text`; si `suggestsAutomatic` y (`.noResults` o no reintentable): «Puedes transcribir el tema automáticamente.» `TF.muted`; si `canRetry`: «Reintentar» `SecondaryButton(32)`.

**Paso `.working(text)` (TSS:179-189).** `VStack(spacing: 12)`: texto, `TfAccentBar` indeterminada de ancho 260, `Spacer`, «Cancelar» (vuelve a resultados) `SecondaryButton(36)`.

**Paso `.failed(issue)` (TSS:191-201).** Caja de problema con reintento de importación, `Spacer`, «Volver» a la izquierda y «Transcribir automáticamente» a la derecha (`SecondaryButton(36)`).

**Paso `.pairing` (TSS:205-248).**

- Texto «Qué pista de Songsterr va con cada stem. La confianza es el parecido medido con el audio.» `TF.muted`.
- Tabla en caja (`padding(.horizontal, 12)`, fondo `TF.field`, radio 10, borde `TF.fieldLine`) con filas de alto 44 separadas por `TfDivider` (`TF.line`):
  - Fila normal (TSS:298-319): nombre del slot (ancho 150, `TF.text`), flecha `arrow.right` `TF.muted`, `TfDropdown` de ancho 260 («Transcripción automática» o pistas con « (NN %)» de similitud), `Spacer`, confianza a la derecha solo si hay pista elegida («NN %» o «sin medir») con `confidenceColor`.
  - Fila de solista sin secciones (TSS:262-268): nombre, flecha, «Transcripción automática (el tema no tiene secciones de solo)» `TF.muted`.
  - Filas de solista con secciones (TSS:270-294): una por solo; el nombre solo en la primera; «Solo k (m:ss)» `TF.text2` monoespaciado, flecha `arrow.left`, `TfDropdown` ancho 200 («Ninguna» o pistas), confianza a la derecha.
  - `confidenceColor` (TSS:323-330, «solo orientativo, no umbrales de la spec»): `TF.ok` desde 0,6; `TF.accent` desde 0,35; `TF.danger` por debajo; `TF.muted` si es nil. Porcentaje: `Int((v×100).rounded())` + « %» (TSS:321).
- Si hay `extraTracks`: «Pistas extra, sin stem: a, b. Entran en la tablatura y en el .gp y solo suenan con «Oír transcripción».» `TF.muted`.
- Avisos (`plan.warnings`): lista con desplazamiento, `padding(12)`, alto máximo 140, fondo `TF.accentBg` radio 10; cada uno con icono `exclamationmark.triangle` en `TF.accent` y texto `TF.text2`, `spacing: 6`/`4`.
- Botonera: «Atrás» y «Todo automático» (`SecondaryButton(36)`), `Spacer`, «Cancelar» (`SecondaryButton(36)`) y «Aceptar» `PrimaryButton`.

**Vista previa de Songsterr (TSS:43-58 y `SongsterrPreview`, SP).** Panel derecho, ancho 640, `VStack(spacing: 10)`. Cabecera: «Vista previa» `body(14,.semibold)` `TF.text`, `Spacer`, «Usar esta» `PrimaryButton` (deshabilitado sin `selectedSong`), «Cerrar» `SecondaryButton(32)`. Debajo, el WebView secundario recortado con radio 10 y borde `TF.fieldLine`; ocupa el ancho 640 y el alto restante de la hoja (640 − 2×24 − cabecera y `spacing 10`). Condición (TSS:18-21): solo existe si `previewOpen`, `importStage == .choosing` y hay `selectedID`; la URL es `SongsterrReader.songURL(songId:)`. El panel desaparece al pasar a `.working`/`.pairing`. Comportamiento del WebView (SP:15-24): navegación normal (desplazar, reproductor propio de Songsterr), gestos atrás/adelante, almacén de datos por defecto (persiste cookies entre sesiones, para no repetir el aviso), user agent de Safari compartido con el cargador (`SongsterrWebLoader.userAgent`, SWL:15), recarga solo si cambia la URL. En Flutter es un segundo `TfWebView` con almacén persistente (las cookies y el user agent son del anfitrión). No hay cargador visible: `SongsterrWebLoader` es un WebView oculto de 1200×800 (SWL:26) que descarga datos; no tiene aspecto y no se rehace como widget (ver contrato).

Textos y contrato de esta hoja: apartados 5 y 8 de las fichas de remisión.

## 10. Partes de trabajo sugeridas

| Parte | Ficheros Dart (en `FlutterApp/lib/features/tab/`) | Tamaño | Agente |
| --- | --- | --- | --- |
| A. Esqueleto, selector de tema y cabecera | `tab_screen.dart`, `tab_theme_chooser.dart`, `tab_header.dart`, `tab_source_menu.dart`, `tab_notice.dart` | M | `tf-flutter` |
| B. Tarjeta de pistas (sin WebView) | `tab_card.dart`, `tab_listen_selector.dart`, `tab_track_strip.dart`, `tab_track_pill.dart`, `tab_pending_pill.dart` (painter), `tab_track_controls.dart`, `tab_footer.dart` | M | `tf-flutter` |
| C. Zona del WebView y overlay de fases | `tab_stage.dart`, `tab_phase_overlay.dart` (necesita la decisión sobre `TfWebView` y la composición Flutter-sobre-WebView) | M | `tf-flutter` |
| D. Barra de edición y transporte | `tab_edit_bar.dart`, `tab_transport.dart`, `tab_loop_menu.dart` | S | `tf-flutter-mech` (maquetación; el cableado de teclas va con la ficha de interacción) |
| E. Hoja de Songsterr | `songsterr_sheet.dart`, `songsterr_choosing.dart`, `songsterr_pairing.dart`, `songsterr_issue_box.dart`, `songsterr_preview.dart` | L | `tf-flutter` |
| F. Diálogo y piezas del kit usadas | `tab_confirm_auto.dart` (usa `TfConfirmDialog` del kit) | S | `tf-flutter-mech` |

Orden: el kit (`tokens-componentes.md` §7) primero; A y B en paralelo; C después de la decisión del `TfWebView`; D y E sin dependencia entre sí; F al final. El `TabStore` (estado de fase, pistas, selección, flash) lo crea el agente que cierre `tablatura-contrato.md`.

## 11. Criterios de aceptación

Capturas de referencia a igualar (nombre propuesto, sobre el tema oscuro y ventana 1280×800 del Mac; las toma Jorge con la app SwiftUI):

| Estado | PNG |
| --- | --- |
| Selector de tema, vacío y con temas | `tab-chooser-empty.png`, `tab-chooser-list.png` |
| Elegir fuente (overlay) | `tab-choosing-source.png` |
| Transcribiendo sin pistas / con pistas | `tab-working-empty.png`, `tab-working-with-tracks.png` |
| Listo, sin edición | `tab-ready.png` |
| Listo con aviso | `tab-ready-notice.png` |
| Modo edición, melódica y batería | `tab-edit-melodic.png`, `tab-edit-drums.png` |
| Esperando análisis, sin pistas, fallo | `tab-waiting.png`, `tab-empty.png`, `tab-failed.png` |
| Pista silenciada y con solo; «Oír: Mixto»; sintetizando | `tab-mute-solo.png`, `tab-listen-mixed.png`, `tab-synth.png` |
| Hoja: búsqueda con resultados, con vista previa, trabajando, fallo, emparejamiento con avisos | `songsterr-choosing.png`, `songsterr-preview.png`, `songsterr-working.png`, `songsterr-failed.png`, `songsterr-pairing.png` |
| Diálogo «Pasar a automática» | `tab-confirm-auto.png` |

Tests de widgets que deben existir (sin WebView real: `TfWebView` falso):

- Para cada fase de 2.4 y 4, el overlay muestra título y botón correctos; con `.working` y pistas el WebView falso está visible y el overlay no es opaco; en `.ready` con `webError` aparecen el mensaje genérico y el detalle (no se comprueba el prefijo literal «alphaTab:», ver 2.4).
- Cabecera: «Editar notas», «Exportar» y menú «Fuente» deshabilitados en las fases de la tabla 4.
- Pastilla: activa/inactiva, atenuada al 55 % con `isDimmed`, M/S de 28×28.
- Pie: prioridad `flash` > `selectionSummary` > texto fijo, `flash` desaparece a los 3 s (tiempo falso).
- Barra de edición: botones deshabilitados sin selección; variante batería con seis botones.
- Hoja: un test por paso (`choosing` con resultados, `failed`, `working`, `pairing`); marcar un resultado abre la previa; `confidenceColor` por tramos (0,6 y 0,35 exactos); `tuningText` de «E A D G B E» (cuerda grave primero); ancho 660 sin previa; con previa, min(1320, ventana − márgenes) con la lista en 612.
- Store: transiciones de fase, caducidad del `flash`, `notices` descartables.

Pasos manuales para Jorge (necesitan vista o el WebView real):

1. Comprobar que la partitura de alphaTab queda exactamente en el rectángulo de 2.3 (mínimo 320 px de alto, esquinas de 10 px) y que los mensajes de fase y el error de web se ven por encima.
2. En Windows, con `TfWebView` real: que el overlay `.working` con pistas se vea sobre la partitura anterior sin tapar su cursor.
3. Songsterr: la previa inicia sesión/cookies una vez y las conserva entre sesiones; la hoja cabe en la ventana mínima.
4. Comparar capturas Flutter y SwiftUI de la lista anterior.

Dudas sin resolver: (a) composición Flutter encima de un WebView nativo: se mide en P9, pruebas 4 y 7. Resuelto: (b) hoja de 1320 px, ver 7.1 (decisiones-interfaz.md); (c) no se añaden icono ni «Reintentar» a `TfNotice` ni a `.failed` (decisiones-interfaz.md, «Tablatura: icono en el aviso y botón «Reintentar» en el fallo»).
