# Ficha de pantalla · Backing

Ola: por asignar. Área del puente: `study` (+ `library.takeBacking`). Destino: `FlutterApp/lib/features/backing/`.

Abreviaturas de evidencia (todo en `App/Sources/`): BV = `BackingView.swift`, BT = `BackingTimeline.swift`, BM = `BackingMixer.swift`, CG = `ChordGrid.swift`, CD = `ChordDiagram.swift`, SB = `SectionBoxes.swift`, SG = `SectionGridBoxes.swift`, GO = `GuitarOptionsViews.swift`, RV = `RecordView.swift`. Tokens y kit: `docs/flutter/tokens-componentes.md` (TC); aquí solo se citan.

Contrato (apartados 5 y 9): ver `backing-contrato.md`. Interacción, hojas y textos (apartados 6, 7 y 8): ver `backing-interaccion.md`.

## 1. Qué es

Pantalla de estudio de un tema ya separado: tira o rejilla de acordes con las secciones encima, diagrama del acorde actual, tonalidad, transposición, capo virtual y afinación fina, barra de posición con bucle, transporte, tempo (velocidad), metrónomo y mezclador por pista con master. Se llega desde la barra lateral (sección Backing) o desde Biblioteca con un tema elegido (`model.backingTarget`); sin tema elegido sale una lista de los temas separados (BV:33-52).

No existe forma de onda en Backing: el encargo la nombra, pero SwiftUI no la dibuja (la barra de posición, BT:562-613, es una pista plana de 10 pt). No hay que inventarla. Los medidores son una barra de nivel por canal.

## 2. Referencia visual (SwiftUI)

### 2.1 Marco y cabecera

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Marco | BV:80-99 | `GeometryReader` > `ScrollView` > `FillLastLayout(available: alto − 40, spacing: 14)`; `padding(.horizontal, 36).padding(.vertical, 20)` (`verticalPadding` BV:76). Pantalla baja si alto < 780 (`lowHeight` BV:78). |
| `FillLastLayout` | BV:201-230 | Apila hijos con 14; los hijos de alto ≤ 0,5 (p. ej. `EmptyView` del banner) no suman hueco. El último hijo (mezclador) recibe `clamp(available − usado, minH, max(minH, idealH))`; `minH` = su alto con propuesta 0, `idealH` = su alto natural. Si ni así cabe, el total supera `available` y hace scroll el `ScrollView`. En Dart: `CustomMultiChildLayout` o `LayoutBuilder` con la misma fórmula (mínimo/ideal del mezclador en 2.5). |
| Cabecera | BV:117-146 | `HStack(alignment: .bottom)`. Izquierda `VStack(spacing: 2)`: «artista · título» `TF.body(13)` `TF.muted` (omite los nulos) y «Backing track» `TF.display(26)`. |
| «Sin guitarras» | BV:127-138 | Solo con `ctl.hasGuitar`. Alto 34, `padding h 14`, radio 8, `TF.body(13, .semibold/.medium)`. Activo: texto `TF.accent`, fondo `TF.accentBg`, borde `TF.accent`; inactivo: `TF.text`, `TF.field`, `TF.fieldLine`. Es `TfPill` compacto (TC §3.1) con alto 34. |
| «Tablatura» | BV:139-143 | `SecondaryButton(height: 34)` con icono `music.quarternote.3` y texto. Grupo de los dos: `HStack(spacing: 10)`. |
| Banner de análisis | BV:159-196 | Caja: `TF.body(13)`, `padding h 16 v 12`, fondo `TF.field`, radio 10, borde `TF.fieldLine` 1. Hasta dos cajas: error de carga (texto `TF.danger`) y estado de análisis: analizando (spinner pequeño + `TF.text2`, spacing 12), sin análisis (texto + `SecondaryButton(height: 34)` «Analizar»), fallido (`TF.danger`, 2 líneas, «Reintentar»). `ready` no pinta nada. |
| Tema sin separar | BV:148-157 | `Card` con `padding(20)`, `spacing: 12`, título `TF.display(18)`, texto sin `.font` (tipografía por defecto del sistema, 13 pt) en `TF.muted`, `SecondaryButton` «Ir a la biblioteca». |
| Elegir tema | BV:33-52 | `spacing: 16`, `padding h 40 v 32`; «Backing track» `TF.display(30)`; filas `padding h 12 v 10`, `TF.field`, radio 10, texto sin `.font`. |
| Cargando | BV:22-24 | `ProgressView().controlSize(.small)` centrado. |

### 2.2 Tarjeta «Línea de tiempo» (acordes, secciones, info, posición, transporte)

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Tarjeta | BT:31-40 | `Card` (`TfCard`); `VStack(spacing: 10)`: cabecera de acordes, área de acordes, fila de info, barra de posición, transporte; `padding h 18 v 12`. |
| Cabecera de acordes | BT:64-117 | `HStack(spacing: 12)`: «Acordes» `TF.display(16)` `TF.text`; botón «Editar acordes» (alto 28, h 10, radio 8, body 12 semibold/medium, icono `pencil` / `pencil.circle.fill` con spacing 6; activo: `accentInk` sobre `TF.accent` sin borde; inactivo `text2`, `field`, `fieldLine`); «Quitar todas (n)» solo en edición con n > 0 (alto 28, h 10, radio 8, body 12 medium, `text2`); texto de ayuda body 12, una línea, cola truncada, prioridad baja, `muted` (en edición `accent`); `Spacer`; «Marcar sección» y «Marcar como solo» solo fuera de edición, con bucle y acordes (alto 28, h 10, radio 8, body 12 medium, icono + texto spacing 6, `fixedSize`; solo: `accent` sobre `accentBg` con borde `accent@0.6`); `SectionApplyButtons` (GO:29-40: «Descartar» `SecondaryButton(28)`, «Aplicar» `ApplyButton` alto 28, h 16, radio 10, body 13 semibold, `accent`/`accentInk`; solo con secciones sin aplicar); «Plegar»/«Expandir» + `chevron.up/down` (alto 28, h 10, radio 8, body 12 medium, `text2`). Animación 0,15 s `easeInOut` al plegar. |
| Área de acordes | BT:149-174 | `VStack(spacing: 10)`; `padding(8)`; plegada: `HStack(alignment: .center, spacing: 12)` [tira ‖ diagrama]; expandida: `HStack(alignment: .top, spacing: 12)` [rejilla ‖ diagrama]. Edición: borde `TF.accent` 1,5 radio 12 y fondo `TF.accentBg@0.4` radio 12; si no, transparente. Sin acordes: texto body 13 `muted` de alto 36 («Sin acordes detectados.» si análisis listo, otro si no). |
| Tarjeta de diagrama | BT:310-323 | `HStack(spacing: 12)`, `padding h 12 v 8`, fondo `TF.field`, radio 10. Diagrama 72×84 (2.4) y `VStack(spacing: 2, leading)` con ancho mín. 90: nombre `TF.display(22)` («—» sin acorde), «Siguiente: X» body 12 `muted` (cadena `" "` si no hay, para no cambiar de alto), «Capo N» body 12 `accent` si capo > 0. |
| Chip de acorde (tira) | BT:263-279 | `VStack(spacing: 0)`: caja de ancho mín. 52 (+6 por lado) y alto 36, radio 8, texto `TF.body(14, .bold)`(→600, TC §1.2); actual: texto `accentInk`, fondo `accent`, sin borde; en bucle: fondo `accent@0.22`, borde `accent`; resto: fondo `field`, borde `fieldLine`; texto de acordes ya pasados `muted@0.7`, futuros `text`. Debajo, número de compás body 10 `muted`, `padding(.leading, 2)`, alto fijo 12 (`barNumberRow` BT:250; `" "` si no abre compás). Bucle activo: acorde en el bucle si su punto medio cae dentro. |
| Tira | BT:176-231 | `ScrollView(.horizontal)` sin indicador; `VStack(spacing: 3)`: hueco de 22 (`SectionBoxes.headerHeight`) + `HStack(spacing: 6)` de chips con `padding(.horizontal, 3)` (`inset + 1`) y `padding(.bottom, 2)`. Alto del marco = 40 + 22 + 3 + 2 + 12 = **79**. Autoscroll al acorde actual con `anchor: .center`, animado. Cajas de sección encima (2.3). |
| Rejilla expandida | CG:116-257 | Ver 2.3 (geometría). |
| Fila de info | BT:342-385 | `FlowRow(spacing: 10)` (RV:296: envuelve; hijos con su tamaño ideal, centrados en vertical en la fila; entre filas 10); `TF.body(13)` `TF.text2`. Elementos: «Tempo detectado: N BPM» (valor semibold `TF.text`, BPM redondeado, «—» sin dato); «Tonalidad:» + menú sin borde `body(13, .semibold)` `TF.text` (24 opciones «Do mayor/menor», «(corregida)» si hay corrección; deshabilitado sin análisis); «Transponer» + selector de ancho 112 (−12…+12, «0 semitonos», `%+d`); «Capo virtual» + selector 112 (Sin capo, Traste 1…12); «Afinación fina» + slider ancho 70 (−50…50, paso 1 por `rounded`, tinte `accent`) + «N cents» ancho 56 `body(13)` cifras monoespaciadas. Selectores = `TfDropdown`, slider = `TfSlider` (TC §3.2). |
| Barra de posición | BT:562-613 | Alto total 22. Pista: cápsula `TF.line` alto 10 a todo el ancho; progreso: cápsula `0x5BC0EB` (hex suelto, BT:581 → `TfColors.timelineBlue`) ancho `x(t)` alto 10; bucle: rectángulo radio 6, relleno `accent@0.18`, borde `accent` 1, alto 22, ancho `max(x(fin) − x(ini), 2)`, desplazado `x(ini)`; cabezal: círculo 14 `TF.text`, sombra negra@0.4 radio 2 y 1 (`TfShadow.playhead`), `offset(x: x(t) − 7)` (sin recorte: sobresale 7 en los extremos). `x(t) = clamp(t / duración, 0, 1) · ancho`. |
| Transporte | BT:427-468 | `FlowRow(spacing: 14)`: **Play/Pausa** círculo 52 `TF.accent`, icono 20 `accentInk` (`play.fill`/`pause.fill`); **reloj** `TF.display(20)` cifras monoespaciadas, «m:ss» en `TF.text` + « / m:ss» en `TF.muted`; **Inicio/Fin** (BT:398-410) `SecondaryButton(height: 30)` en `HStack(spacing: 6)`, «Inicio» pasa a `accent` y «Inicio m:ss» con inicio pendiente, «Fin» deshabilitado sin inicio pendiente ni bucle; **píldora de bucle** (con bucle) `body(13, .semibold)` `accent`, `padding h 10 v 6`, fondo `accentBg`, radio 8, «Bucle: nombre\|libre · m:ss–m:ss» + `xmark` (spacing 6); **Tempo** `HStack(spacing: 10)`: «Tempo» + slider 120 (50…200, paso 5, tinte `accent`) + «NN %» ancho 54 semibold `TF.text` cifras monoespaciadas (`Fmt.percent`); **Metrónomo** casilla (`TfCheckbox`) body 13 `text2`, deshabilitada sin rejilla de pulso. |

Colores sueltos fuera de `TF` en Backing: solo `0x5BC0EB` (BT:581). Sombras `.black.opacity` en cabezal (BT:589) y pomo del fader (BM:294), ya en TC §2.5. Medidas con `.font` omitido: ver tarjeta «Tema sin separar» y «Elegir tema».

### 2.3 Rejilla de acordes y cajas de sección (`CustomPainter`)

Todo en coordenadas del contenido desplazable, origen arriba a la izquierda. Constantes en CG:131-142.

| Constante | Valor | Uso |
| --- | --- | --- |
| `labelWidth` | 84 | columna «c. N» (texto body 11 `muted`, ancho 76 + 8 de hueco) |
| `rowHeight` | 46 | alto de compás |
| `sectionGutter` | 18 | franja sobre cada fila para el nombre de caja |
| `rowSpacing` | 4 | entre filas |
| `barGap` | 4 | hueco a la derecha de cada compás |
| `minBarWidthFor8` | 112 | 8 compases por fila si `(ancho − 84)/8 ≥ 112`, si no 4 |
| `visibleRows` | 4 | alto de la rejilla = `4·(18+46) + 3·4` = **268**; scroll vertical sin indicador |
| `clickSlop` | 4 | umbral clic/arrastre |

Fórmulas (`ChordGridGeometry`, CG:81-106): `barWidth = (ancho − 84)/perRow`; `drawnBarWidth = barWidth − 4`; `rowPitch = 18 + 46 + 4 = 68`; celda `(fila, col, pulso, nPulsos)`: `w = drawnBarWidth/nPulsos`, `x = 84 + col·barWidth + pulso·w`, `y = fila·68 + 18`, alto 46. Hit-test: `fila = clamp(floor(y/68))`, `col = clamp(floor((x−84)/barWidth))`, `pulso = floor(clamp((x−84−col·barWidth)/drawnBarWidth, 0, 0.999999)·n)`. Una sola fuente para dibujar y pulsar (test DEBUG CG:296).

Pintado de un compás (CG:216-225): rectángulo `drawnBarWidth × 46`, radio 8, borde 1; actual (`start ≤ t < end`): fondo `TF.accentBg`, borde `TF.accent`; resto `TF.field`/`TF.fieldLine`. Celda (CG:227-257): alto 40 centrado (`padding v 3`), radio 6; en bucle (punto medio de la celda dentro): relleno `accent@0.28`; texto: si es primer pulso del compás o cambia el acorde, nombre en `body(14, .bold)` alineado a la izquierda con `padding-left 6`, si no «·» `body(13)` centrado; color `TF.text` si es acorde, si no `TF.muted`; una línea, escala mínima 0,6; celda actual: cápsula `accent` de alto 3 y ancho `max(w − 8, 4)` pegada abajo. Transposición: el puente entrega el nombre ya transpuesto (decisiones-interfaz.md, Backing: nombre de acorde transpuesto y formas); SwiftUI lo calcula en `shown` (BT:60). Sin rejilla de pulso: «Sin rejilla de compases todavía.» body 13 `muted` centrado. Autoscroll: a la fila del compás actual con `anchor: .center` (animado al cambiar de fila, sin animar al cambiar `perRow`).

Construcción de `ChordGridLayout` (CG:7-77): lógica de datos (compases por `downbeats`, celda por pulso, acorde sondeado en `t + 0,35·(e − t)`); es regla de presentación a portar, no de pintura: ver apartado 9 de `backing-contrato.md` si el núcleo no la ofrece (la decisión de `decisiones-interfaz.md` solo cubre el nombre transpuesto y las formas, no esta construcción).

Cajas de sección (`SectionBoxPiece`, SB:35-120):

| Parte | Medida |
| --- | --- |
| Caja | radio 9; relleno color de sección `@0.07` (`@0.16` seleccionada); trazo 1,2 (2 si seleccionada o es el bucle activo); color de trazo: seleccionada = color, bucle activo = `TF.accent`, resto = color `@0.85` |
| Color | solo: `TF.accent`; resto `TF.sectionPalette[paleta[id] % 7]` (TC §1.1) |
| Cabecera | rectángulo con esquinas superiores 9 e inferiores 0, ancho de la caja, alto `headerHeight`; relleno solo: `TF.accentBg`, resto color `@0.20` |
| Etiqueta | solo el primer trozo; `padding h 8`; icono `guitars.fill` 10 semibold (solo) + nombre `body(12, .semibold)` una línea, color `accent` (solo) o el de sección; si no cabe, se queda el icono o nada (`ViewThatFits`) |
| Asa de borde | solo en la seleccionada, SB:127-158: zona de agarre 16 de ancho centrada en el borde y de alto = caja − cabecera; barra visible cápsula 6 × `clamp(alto − 10, 16, 30)` del color de sección, sombra negra@0,5 radio 2; cursor `columnResize` |

Tira (SB:191-265): la caja se calcula con los marcos de los chips (coordenadas de la tira): `x(t)` interpola dentro del chip que contiene `t` (inicio: primer chip con `fin > t`; fin: último con `inicio < t`; `k = clamp((t − ini)/(fin − ini))`, `x = chip.minX + chip.ancho·k`); `x0 = x(inicio) − 2`, `x1 = max(x(fin) + 2, x0 + 8)`, `y = 0`, alto = `max(chip.maxY) + 2` (= 22 + 3 + 36 + 2 = **63**), cabecera 22 (`headerHeight`, `inset` 2). Se pinta solo si `fin > primerAcorde.inicio` y `inicio < últimoAcorde.fin`. Rejilla (SG:9-108, `inset` 2): una caja por fila donde haya celdas cuyo punto medio `(t + e)/2` esté en `[inicio, fin)`; `x = min(celda.x) − 2`, ancho `max(celda.x+w) − min + 4`, `y = fila·68`, alto `18 + 46 + 2 = 66`, cabecera 18 (`sectionGutter`); solo el primer trozo lleva nombre. Las asas van aparte con identidad fija: inicio en `primerTrozo.minX`, fin en `últimoTrozo.maxX`, `top = trozo.y + 18`.

### 2.4 Diagrama de acorde (`CustomPainter`)

`ChordDiagram` (CD:1-67): lienzo **72 × 84**; margen superior 16; 5 filas de traste; `left = 22`, `right = 72 − 6 = 66`, `top = 16`, `bottom = 84 − 4 = 80`; `stringGap = (66 − 22)/5 = 8,8`; `fretGap = (80 − 16)/5 = 12,8`; `x(s) = 22 + 8,8·s` (s = 0 es la 6.ª cuerda); `y(r) = 16 + 12,8·r`. Tinta `TF.muted@0.8`. Orden de pintado:

1. Trastes `r = 0…5`: línea horizontal de `left` a `right`; cejuela (`r = 0` y `base == 1`): `TF.text2` grosor 3; resto tinta, grosor 1.
2. Cuerdas `s = 0…5`: línea vertical de `top` a `bottom`, tinta, grosor 1.
3. Si `base > 1`: texto «{base}fr» `body(10, .semibold)` `TF.text2` centrado en `(10, y(0) + 6,4)`.
4. Cejilla (`shape.barre`): `fila = b.fret − base`; `a = 6 − max(from, to)`, `z = 6 − min(from, to)`; rectángulo `x(a) − 4`, `y(fila) + 6,4 − 4`, ancho `x(z) − x(a) + 8`, alto 8, radio 4, `TF.accent`.
5. Por cuerda: `nil` → «×» `body(11, .bold)` `TF.muted` centrado en `(x(s), 7)`; traste 0 → círculo 7 × 7 trazo 1 `TF.text2` centrado en `(x(s), 7)`; traste > 0 con `0 ≤ fila < 5` → círculo de diámetro 10 `TF.accent` centrado en `(x(s), y(fila) + 6,4)` (`fila = traste − base`); fuera de rango no se pinta.

`base`: si ninguna cuerda al aire y el traste pisado más bajo es > 1, `base` = ese traste; si no `shape.baseFret`. Sin forma (`shape == nil`): no pinta nada pero ocupa 72 × 84. Etiquetas de accesibilidad: «Diagrama del acorde» / «Sin diagrama».

### 2.5 Mezclador

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Tarjeta | BM:30-70 | `Card`; `VStack(spacing: 10)`, `padding h 20 v 14`. Cabecera `HStack(spacing: 12)`: «Mezclador» `TF.display(18)`, `Spacer`, `GuitarStereoToggle` (GO:9-27: estado de guitarras + interruptor pequeño `TF.accent`, body 13 medium; solo con guitarra o pistas separadas) y «Salida: nombre\|—» body 12 `muted`. |
| Cuerpo normal | BM:45-65 | `GeometryReader`: `ch = clamp(alto − 10, 166, 276)`; `HStack(alignment: .top, spacing: 10)`: master, divisor vertical de alto `max(ch − 76, 40)` con `padding h 6`, `ScrollView(.horizontal)` con indicador y `HStack(spacing: 10)` de canales con `padding-bottom 10`. Alto del cuerpo: mín. **210** (176 si pantalla baja), ideal y máx. **286** (276 + 10). Altura mínima de la tarjeta = 28 + 22 + 10 + 210 = 270 (236 baja); ideal = 346 (cálculo del autor de la ficha, no literal). |
| Orden de canales | BM:22-24 | Voz, Batería, Bajo, Guitarra, Piano, Resto. Se omiten los no audibles y los vacíos. Con guitarras separadas, «Guitarra» se sustituye por un canal por pista (`guitarTracks`, nombre editable). |
| Canal | BM:143-190 | `VStack(spacing: 6)`, ancho **96**, alto `ch`, `padding v 12`, fondo `TF.field`, radio 12, borde `TF.fieldLine`; atenuado `@0.55` si silenciado o hay solo ajeno. Contenido: título (alto 22, `body(12, .semibold)`, una línea, escala 0,9, `padding h 4`); `HStack(spacing: 10)` [fader 28 × `fh` ‖ barra de nivel 8 × `fh`] con `padding-top 4`; valor «−6,0 dB» o «Silenciado» `body(12)` `text2`; `HStack(spacing: 6)` [M, S] con `padding-top 4`. `fh = max(150 − (276 − ch), 40)`. Sumando: 12+22+6+4+150+6+~15+6+4+36+12 ≈ 273-276. |
| Master | BM:238-255 | Mismo ancho/alto/espaciado; fondo `accentBg@0.5`, borde `accent@0.6`; título «Master»; fader con `padding h 18` y `padding-top 4`; valor `Fmt.db`; hueco vacío de 40 donde irían M/S. |
| `MixerToggle` M/S | BM:257-272 | 36×36, radio 8, `body(12, .bold)`; ver `TfToggleButton` (TC §3.1). |
| Fader | BM:281-311 | `TfFader` (TC §3.1). Posición del pomo: `frac = (dB + 60)/66`; pomo 28×18, radio 4, `TF.text2`, sombra negra@0,5 radio 3 y 2; centro en `h·(1 − frac)` (`offset(y: h·(1 − frac) − 9)`): sobresale 9 por arriba y abajo en los extremos, sin recorte. Carril 6 de ancho, radio 3, `TF.bg`, centrado. El valor sale de la posición del puntero directo (`f = 1 − clamp(y/h)`), sin corregir el agarre del pomo. |
| Barra de nivel (`CustomPainter`) | BM:222-234 | 8 × `fh`, radio 4, fondo `TF.bg`; relleno desde abajo de alto `fh·f`, `f = clamp((rmsDB + 60)/60, 0, 1)` (`meterFloorDB` −60), radio 4, degradado vertical **relativo al propio relleno** (no a la barra): `ok` hasta el 70 %, mezcla hasta `accent` en el 92 %, `accent` por encima. Con canal atenuado (`dim`) el nivel es 0. Muestreo: 20 Hz (BV:72, 100-104). |
| Cuerpo compacto | BM:87-129 | Con la rejilla expandida: `HStack(alignment: .center, spacing: 16)`: «Master» `body(13, .semibold)` + slider 150 (−60…6, imán: \|valor\| < 1,5 → 0, tinte `accent`) + `Fmt.db` `body(12)` `text2` ancho 62; divisor vertical alto 28; `HStack(alignment: .top, spacing: 8)` con un bloque por canal (ancho mín. 78 expansible): nombre `body(12, .semibold)`, una línea, escala 0,8, truncado en el medio, centrado + M y S (36, spacing 6), `VStack(spacing: 4)`; atenuado `@0.55`. Sin faders ni barras. |

Medidas que SwiftUI deja al sistema (revisar en la captura): alturas naturales de los textos, sin `fixedSize` salvo donde se indica.

## 3. Árbol de widgets propuesto

- `BackingScreen` (marco con padding 36/20 y `FillLastLayout`; `CustomMultiChildLayout`) ← `BackingView`/`BackingContent` BV:13-115
  - `BackingChooser` ← `chooser` BV:33; `TfSpinner` de carga
  - `BackingHeader` ← BV:117 (`TfPill` «Sin guitarras», `TfSecondaryButton` «Tablatura»)
  - `AnalysisBanner` ← BV:159 (`TfStateMessage`/caja); `NotSeparatedCard` ← BV:148 (`TfCard`)
  - `TimelineCard` (`TfCard`) ← `BackingTimelineCard` BT:8
    - `ChordsHeader` ← BT:64 (`TfPill`, `SectionApplyButtons`)
    - `ChordsArea` (marco de edición) ← BT:149
      - `ChordStrip` ← BT:176: `ChordChip` x N (widget; kit local); `SectionBoxesLayer` **`CustomPainter`** + capa de gestos y asas ← `SectionBoxes`
      - `ChordGridView` **`CustomPainter`** (compases, celdas, subrayado, bucle, rejilla) + `GridSectionBoxesLayer` **`CustomPainter`** ← CG:116, SG:9. Las celdas se pintan; el popover de edición (apartado 7) se ancla a la geometría de `ChordGridGeometry`.
      - `ChordDiagramCard` ← BT:310 con `ChordDiagramPainter` **`CustomPainter`** 72×84 ← CD
    - `InfoRow` (`Wrap`) ← BT:342: `TfDropdown`, `TfSlider`
    - `PositionBar` **`CustomPainter`** (pista, progreso, bucle, cabezal) ← BT:562
    - `TransportRow` (`Wrap`) ← BT:427: botón play circular, reloj, `TfSecondaryButton(30)` Inicio/Fin, `LoopPill`, `TfSlider` tempo, `TfCheckbox` metrónomo
  - `MixerCard` (`TfCard`) ← `BackingMixer` BM:7
    - `GuitarStereoToggle` ← GO:9 (`TfSwitch`)
    - `MixerChannel` x N ← BM:143 (`TfMixerChannel`, `TfToggleButton`, `TfFader`, `TfLevelBar` **`CustomPainter`** o widgets simples) y `MasterChannel` ← BM:238
    - `CompactMixer` ← BM:87

Del kit (`Tf…`): `TfCard`, `TfPill`, `TfSecondaryButton`, `TfDropdown`, `TfSlider`, `TfCheckbox`, `TfSwitch`, `TfToggleButton`, `TfFader`, `TfLevelBar`, `TfMixerChannel`, `TfSpinner`, `TfStateMessage`, `TfShadow.playhead`. Propios de Backing (no están en el kit): `ChordChip`, `ChordGridView`, secciones, `ChordDiagramPainter`, `PositionBar`, `LoopPill`.

## 4. Estados

| Estado | Qué cambia en pantalla | Dato que lo decide |
| --- | --- | --- |
| Sin tema elegido | lista de temas separados (o mensaje «Aún no hay temas separados…») | `model.backingTarget == nil`; `entries` con `separationState == done` |
| Abriendo | spinner centrado | `backingTarget` fijado y `study`/`backing` aún nulos |
| Tema sin separar | solo cabecera + tarjeta «Este tema aún no está separado» | `project.separation.state != done` o sin stems audibles ni vacíos (BV:85) |
| Análisis `analyzing` | banner con spinner; se puede reproducir; acordes aparecen al terminar («Los acordes aparecerán…») | `session.analysisState` |
| Análisis `missing` / `failed` | banner con «Analizar» / «No se pudo analizar: …» + «Reintentar» | `analysisState` |
| Error de carga | caja con texto `danger` sobre el banner | `ctl.loadError` |
| Listo, plegado | tira de acordes + diagrama a la derecha, mezclador completo (faders y niveles) | `chordsExpanded == false` (se recuerda por tema, clave `backing.chordsExpanded.<projectID>`) |
| Listo, expandido | rejilla de compases + diagrama; mezclador compacto (master deslizante + M/S) | `chordsExpanded == true` |
| Sin acordes | texto «Sin acordes detectados.» (análisis listo) o del análisis; diagrama con «—» | `session.effectiveChords.isEmpty` |
| Sin rejilla de pulso | rejilla expandida: «Sin rejilla de compases todavía.»; metrónomo deshabilitado; «Tonalidad» deshabilitada sin `analysis` | `session.beats == nil` |
| Edición de acordes | marco de acento 1,5 con fondo `accentBg@0.4`, botón activo, «Quitar todas (n)» con n > 0, ayuda en `accent`; ocultos «Marcar…»; sin marcar bucles | `editMode` |
| Bucle activo | zona de acento en chips/celdas (`@0.22`/`@0.28`), rectángulo en la barra, píldora «Bucle…», «Marcar…» visibles, «Fin» habilitado | `ctl.loop`, `ctl.loopName`, `pendingLoopStart` |
| Inicio de bucle pendiente | «Inicio m:ss» en `accent`; «Fin» habilitado | `pendingLoopStart` |
| Sección seleccionada | caja `@0.16` trazo 2 con asas; ventana de sección (apartado 7) | `SectionSelection.selected/popover` |
| Secciones sin aplicar | aparecen «Descartar» y «Aplicar» | `session.hasUnappliedSections` |
| Guitarras separadas / procesando | canales por pista en lugar de «Guitarra»; estado «Procesando guitarras…» o error junto al interruptor | `session.usesSeparatedGuitars`, `model.guitarProcess[projectID]` |
| Canal silenciado o solo ajeno | canal `@0.55`, nivel 0, valor «Silenciado» si está silenciado | `StemMix.muted`, `anySolo && !solo` |
| Sin guitarras (global) | botón activo en `accent` | `ctl.guitarsOff` |
| Reproduciendo | icono pausa, acorde actual resaltado, autoscroll, medidores vivos | `ctl.isPlaying`, `ctl.player.currentTime` (20 Hz) |
| Capo > 0 | «Capo N» en la tarjeta de diagrama; formas con capo | `settings.capo` |
| Pantalla baja (< 780) | mínimo del mezclador 176 en vez de 210 | alto de ventana |

## 10. Partes de trabajo sugeridas

| Parte | Ficheros Dart | Tamaño | Agente |
| --- | --- | --- | --- |
| A. Contrato y stores | `contract/study.dart`, `features/backing/backing_store.dart`, `session_store.dart`, fixtures en `Contract/fixtures/study/` | L | `tf-flutter` (Sonnet) |
| B. Carcasa | `backing_screen.dart`, `backing_layout.dart` (`FillLastLayout`), `backing_header.dart`, `analysis_banner.dart`, `chooser.dart` | M | `tf-flutter` (Sonnet) |
| C. Info y transporte | `widgets/info_row.dart`, `transport_row.dart`, `loop_pill.dart`, `position_bar.dart` (`CustomPainter`) | M | `tf-flutter` (Sonnet) |
| D. Acordes: tira y diagrama | `widgets/chord_strip.dart`, `chord_chip.dart`, `chord_diagram.dart` (`CustomPainter`), `chords_header.dart` | M | `tf-flutter` (Sonnet) |
| E. Rejilla de compases | `widgets/chord_grid.dart`, `chord_grid_geometry.dart` (puro, con tests), `chord_grid_painter.dart` | L | `tf-flutter` (Sonnet) |
| F. Secciones | `widgets/section_boxes.dart` (tira y rejilla), `section_painter.dart`, asas | L | `tf-flutter` (Sonnet) |
| G. Mezclador | `widgets/mixer_card.dart`, `mixer_channel.dart`, `master_channel.dart`, `compact_mixer.dart`, `level_bar.dart` | M | `tf-flutter` (Sonnet) |
| H. Textos, tests y goldens | claves en `app_es.arb`/`app_en.arb`, `test/features/backing/*` | M | `tf-flutter-mech` (Haiku) |

Orden: A y B; C, D, G en paralelo; E tras D (comparte `ChordGridLayout` y selección); F tras E (usa su geometría). F depende de `backing-interaccion.md` (asas, popover).

## 11. Criterios de aceptación

Capturas de referencia (Mac con `--screen backing --project <tema>`; flags en `AppModel.swift:116-127`: `--chords-expanded`, `--chords-edit`, `--select-section N`):

| Estado | PNG |
| --- | --- |
| Sin tema elegido | `backing-chooser.png` |
| Tema sin separar | `backing-notseparated.png` |
| Plegado, parado, sin bucle | `backing-strip.png` |
| Plegado con bucle y píldora | `backing-strip-loop.png` |
| Expandido (rejilla de 4 y de 8 compases) | `backing-grid-4.png`, `backing-grid-8.png` |
| Edición de acordes | `backing-chords-edit.png` |
| Sección seleccionada con asas (tira y rejilla) | `backing-section-strip.png`, `backing-section-grid.png` |
| Solo (insignia de guitarra) | `backing-solo.png` |
| Capo y transposición con diagrama | `backing-capo.png` |
| Análisis en curso / sin análisis / fallido | `backing-analyzing.png`, `-missing.png`, `-failed.png` |
| Guitarras separadas | `backing-guitars.png` |
| Pantalla baja (alto < 780) | `backing-low.png` |
| Mezclador con solo y silencio | `backing-mixer-solo.png` |

Tests de widget y geometría (puros): `ChordGridGeometry` (celda ↔ hit-test en centro y a 0,5 pt de los bordes, como CG:296); 4 u 8 compases según ancho 112; rectángulos de caja de sección en tira (63 de alto) y en rejilla (66, partida por filas); `ChordDiagramPainter` con golden para Do, Fa con cejilla (`base`), Sol# y sin forma; posición del pomo y valor del fader en −60, 0 (imán ±1,5) y +6; barra de nivel (f a −60, −30, 0 dB); `FillLastLayout` (mínimo, ideal y exceso con scroll); barra de posición (`x(t)` en los extremos). Tests de store: bloque de transporte y mezcla según apartado 5 (`backing-contrato.md`).

Pasos manuales para Jorge (oído o pedalera): que el metrónomo, el bucle, el cambio de velocidad y la transposición suenen igual que en el Mac; que el autoscroll del acorde actual siga al audio sin saltos; comparar a ojo la tira y la rejilla con las capturas.
