# Ficha de pantalla · Grabar y «Ver toma»

Ola: por asignar. Área del puente: `record` (+ `takeview`, `audio`, `video`, `library.*` de tomas). Destino: `FlutterApp/lib/features/record/`.

Esta ficha cubre solo los apartados 1, 2, 3, 4, 10 y 11. El 5 (contrato) y el 9 (desvíos) están en `grabar-contrato.md`; el 6, 7 y 8 (interacción, hojas y textos) en `grabar-interaccion.md`.

Abreviaturas de evidencia: RV = `App/Sources/RecordView.swift`, RM = `RecordMixer.swift`, PT = `PunchTimeline.swift`, BM = `BackingMixer.swift`, VS = `VideoSettingsView.swift`, TV = `TakeViewer.swift`, OS = `OffsetSheet.swift`, RC = `RecordController.swift`, TH = `Theme.swift`.

## 1. Qué es

Pantalla donde se graba la guitarra sobre el backing del tema abierto: vista de cámara en vivo, botón Grabar/Parar con cuenta atrás, opciones de arranque (sección de inicio, cuenta de un compás, margen, punch-in), mezclador compacto con Master y medidor de la entrada, y a la derecha el panel «Partes» con las tomas de cada parte. Se llega desde la barra lateral con un tema elegido (`model.backingTarget`); sin tema se muestra un selector de temas ya separados (RV:26-45).

«Ver toma» es una hoja modal que se abre con el botón ▶ de cada toma: reproduce el vídeo de la toma con su audio procesado, el backing, los punches y el desfase (TV). Desde ella se puede marcar como mejor o eliminar la toma. «Ajustar desfase» es otra hoja (OS) que se documenta en `grabar-interaccion.md` §7; aquí solo se anota su superficie de vídeo (§2.7).

## 2. Referencia visual (SwiftUI)

### 2.1 Marco y cabecera

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Selector de tema (sin tema elegido) | RV:26-45 | `VStack(alignment: .leading, spacing: 16)`, `padding(.horizontal, 40).padding(.vertical, 32)`. «Grabar» `TF.display(30)`; texto `TF.muted`. Fila por tema: `padding(.horizontal, 12).padding(.vertical, 10)`, fondo `TF.field`, radio 10, título con la fuente por defecto del sistema, `Spacer`. |
| Tema sin separar | RV:57-66 | `Card` con `padding(20)` interior y `padding(36)` fuera; título `TF.display(18)`; texto `TF.muted`; `SecondaryButton` «Ir a la biblioteca»; `spacing: 12`. |
| Cargando | RV:17, RV:68 | `ProgressView().controlSize(.small)` centrado (`TfSpinner`). |
| Marco de Grabar | RV:101-118 | `VStack(alignment: .leading, spacing: 14)`: cabecera + `HStack(alignment: .top, spacing: 20)`; `padding(.horizontal, 36).padding(.vertical, 20)`; ocupa todo el espacio, sin scroll general (solo el panel «Partes» y los canales del mezclador). |
| Columna izquierda | RV:106-113 | `VStack(alignment: .leading, spacing: 14)`, `maxWidth/maxHeight: .infinity`: vista previa, barra de grabación, estado, línea de punch (si activo), mezclador. |
| Cabecera | RV:145-164 | `HStack(alignment: .bottom)`. Línea superior `artista · título · Multitoma` (solo las partes que existen) `TF.body(13)` `TF.muted`; «Grabar» `TF.display(26)`; `spacing: 2`. A la derecha «Ir al montaje»: `TF.body(14, .semibold)` `TF.text2`, `padding(.horizontal, 18)`, alto 44, fondo `TF.field`, radio 10, borde `TF.fieldLine`; deshabilitado con `isBusy`. |

### 2.2 Vista de cámara (`RecordPreview`, RV:360-458)

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Caja | RV:364-390 | `ZStack` con `aspectRatio(16/9, .fit)`, `clipShape` radio 16, borde `TF.line`; luego `frame(maxWidth/maxHeight: .infinity)`: ocupa todo el espacio libre de la columna manteniendo 16:9 y se encoge cuando el mezclador se expande (RV:389). |
| Fondo | RV:365-367 | Degradado radial, radio 16: centro `(0.5, 0.4)` unitario, `startRadius 0`, `endRadius 520` pt; de `0x2A3036` (= `TF.fieldLine`) a `0x121417` (hex suelto, `TfColors.previewDeep`). |
| **`TfVideoSurface`** (cámara) | RV:395-396; VS:132-174 | Rectángulo que ocupa **toda la caja** (sin padding). Ver §2.2.1. Solo existe con `cameraState == .live`. |
| Marcador de posición | RV:397-420 | Con `.simulated`: «Vista previa de la cámara · <nombre o simulada> (simulada)»; con `.none/.denied/.failed`: «Sin vídeo: se grabará solo el audio». `ViewThatFits(in: .vertical)` con tres variantes (icono `video` 28 pt light + texto; solo texto; vacío). Texto 14 pt (`TF.body` por defecto) `TF.muted`, centrado, `spacing: 8`, `padding(.top, 64).padding(.horizontal, 16).padding(.bottom, 8)` (los 64 reservan la fila de píldoras). Con `.idle`: `TfSpinner` centrado. |
| Capa de píldoras | RV:369-384 | `VStack` con `padding(16)`: arriba la fila de píldoras; tras `Spacer()`, abajo, el contador de cuenta atrás. |
| Fila de píldoras | RV:372-378 | `ViewThatFits(in: .horizontal)`: variante 1 `HStack(alignment: .top)` con REC fija, `Spacer(minLength: 8)` y píldoras de cámara; variante 2 `VStack(alignment: .leading, spacing: 8)` con REC y debajo, a la derecha, las de cámara. |
| Píldora (base) | RV:453-457 | `TF.body(14)`, una línea (`lineLimit(1)`, recorta con «…»), `padding(.horizontal, 12).padding(.vertical, 6)`, fondo `0x0F1113` @0,75 (= `TF.bg`), cápsula. |
| Píldora REC | RV:429-436 | `HStack(spacing: 8)`: círculo 10×10, rojo `TfColors.<nombre>` (token con nombre, decisiones-interfaz.md; nombre definitivo en `tokens-componentes.md` §2.1; el botón ya cita `TfColors.recordButton`) si `phase` no es `.idle` ni `.adjusting`, si no `TF.muted`; texto `«REC · »` (solo en ese caso) + `Toma N · <parte>` en `semibold`. N = `nextTakeNumber` (RC:209). Texto con el color primario del sistema (blanco). |
| Píldora de formato | RV:422-427 | Solo con `cameraLabel` (`<resolución> · <fps>`, RC:393-396): texto `TF.text2`. |
| Píldora «Rotar» | RV:438-451 | `HStack(spacing: 6)`: icono `rotate.right` + «Rotar» o «Rotar · N°» (90/180/270); `TF.text2` con 0°, `TF.accent` con giro. Deshabilitada si `phase != .idle` (sin cambio visual propio). |
| Contador de cuenta atrás | RV:380-382 | Número `TF.display(64)` blanco, sombra negra @0,6, radio 10, y +4; abajo y centrado horizontalmente en la caja (dentro del `VStack` con `padding(16)`). |

#### 2.2.1 `TfVideoSurface` en la vista de cámara

Equivalencias con lo que hace AVFoundation hoy (VS:146-174):

- **Rectángulo**: toda la caja 16:9 (sin esquinas propias; el recorte de radio 16 lo hace la caja).
- **Relación de aspecto de la fuente**: la del formato de cámara (`videoFormat.width/height`); la caja es siempre 16:9, la imagen no obliga a 16:9. El relay de Windows entrega 640 px de ancho a 15 fps (dato no versionado, medido en local); la dimensión real llega con cada fotograma.
- **Encuadre**: `videoGravity = .resizeAspect` (VS:156) = **fit/contain**: imagen entera, con barras sobre el degradado de fondo. Nunca recorta (nunca `fill`).
- **Rotación**: `rotation` ∈ {0, 90, 180, 270} en sentido horario (`cameraRotation`, RC:407). Con 90°/270° la capa toma ancho y alto de la caja intercambiados y se gira alrededor del centro, de modo que `resizeAspect` encaja la imagen **ya girada** (VS:162-173). En Flutter: relación de aspecto de la fuente girada (`w/h` si 0/180, `h/w` si 90/270), contain en la caja y `RotatedBox(quarterTurns: rotation / 90)`. Solo es de vista: la cámara graba sin girar.
- **Espejo**: el código **no lo fija** (`grep -i mirror` sin resultados en `App/Sources` ni `VideoKit`). Queda el valor por defecto de `AVCaptureVideoPreviewLayer` (ajuste automático del espejo). Se replica lo que salga de la captura de SwiftUI con cámara real (ola 3); ver §11.1 y decisiones-interfaz.md, «Se resuelven midiendo».
- **Sin transiciones**: el giro se aplica con `CATransaction.setDisableActions(true)` (VS:164-165): salto seco.

### 2.3 Barra de grabación (`RecordBar`, RV:462-538)

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Tarjeta | RV:524-527 | `padding(.horizontal, 16).padding(.vertical, 14)`, fondo `TF.card`, radio 14, borde `TF.line`; `VStack(alignment: .leading, spacing: 12)`; fuente base `TF.body(14)` `TF.text2`. |
| Fila de transporte | RV:473-497 | `HStack(spacing: 14)`: botón, tiempo, `Spacer(minLength: 0)`, etiqueta de desfase. |
| Botón Grabar/Parar | RV:474-489 | Cápsula de alto 48, `padding(.horizontal, 22)`, fondo `0xC8433A` (RV:467; `TfColors.recordButton`); `TF.body(15, .semibold)` blanco; `HStack(spacing: 8)` con icono 10×10: círculo blanco («Grabar») o cuadrado blanco radio 2 («Parar»). Opacidad 0,4 si bloqueado (`phase == .idle && blockReason != nil`), `.finishing` o `.adjusting`. «Parar» en `.counting` y `.recording`. |
| Tiempo | RV:491-494 | `Fmt.duration(time)` (m:ss con redondeo, TH:141) en `TF.display(20)` + « / » + total en `TF.body(16, .medium)` `TF.muted`, dígitos monoespaciados. Total = `plannedStop ?? duration`. `time` se refresca cada 0,05 s (RV:98, RV:122). |
| Etiqueta de desfase | RV:530-537 | Solo con cámara (`defaultOffset != nil`): «Desfase de la cámara: sin ajustar» (`TF.muted`) o «+N ms»/«−N ms» en `TF.ok`; `TF.body(13, .semibold)`, una línea, `minimumScaleFactor(0.75)`. |
| Opciones | RV:499-522 | `FlowRow(spacing: 18)` (RV:296-329: envuelve en filas, centrado vertical por fila, separación entre filas = `spacing`): menú «Empezar en» (Principio + secciones), casilla «Cuenta de 1 compás», menú «Margen» (2 compases, 1 compás, Sin margen), casilla «Punch-in». Controles nativos: `TfDropdown`, `TfCheckbox` (`tokens-componentes.md` §3.2). |

### 2.4 Estado, punch y mezclador

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Líneas de estado | RV:168-188 | `VStack(alignment: .leading, spacing: 4)`; cada línea `TF.body(12)`, multilínea, `TF.muted` (motivo de bloqueo), `TF.accent` (avisos) o `TF.danger` (errores de carga o guardado). Sin fondo ni icono. Orden: bloqueo, «sin calibrar», cámara, mensajes del controlador, avisos de toma, errores. |
| **`PunchTimeline`** (**`CustomPainter`**) | PT:7-89 | Solo con `punchEnabled`. `Card`, `padding(.horizontal, 16).padding(.vertical, 12)`, `VStack(spacing: 8)`; título «Punch-in» `TF.display(16)`, resumen «Entrada m:ss,d · Salida m:ss,d» (`—` si falta) `TF.body(12)` `TF.muted` monoespaciado; zona de dibujo; ayuda `TF.body(12)` `TF.muted`. `.disabled` si `isBusy`. Geometría en §2.5. |
| Mezclador | RM:19-61 | `Card`, `padding(.horizontal, 20).padding(.vertical, 14)`, `VStack(spacing: 10)`. Cabecera `HStack(spacing: 12)`: «Mezclador» `TF.display(18)`, `Spacer`, «Salida: <dispositivo o —>» `TF.body(12)` `TF.muted` una línea (recorta al final), botón «Expandir»/«Plegar» (`TF.body(13, .medium)` `TF.text2`, `padding(.horizontal, 12)`, alto 30, fondo `TF.field`, radio 8, borde `TF.fieldLine`). |
| Cabecera compacta | RM:67-87 | `HStack(spacing: 10)`: «Master» `TF.body(12, .semibold)`, `Slider` ancho 40 (−60…+6 dB, tinte `TF.accent`, imán a 0 si \|v\| < 1,5), valor `Fmt.db` `TF.body(12)` `TF.text2`; `Divider` alto 28; «Tu guitarra» `TF.body(12, .semibold)` + medidor horizontal 22×8 (§2.5). |
| Canal compacto | RM:123-135 | Columna `spacing: 4`, ancho 76: nombre `TF.body(12, .semibold)` (`minimumScaleFactor(0.8)`, recorte al medio) y `HStack(spacing: 6)` con M y S (`MixerToggle`: 36×36, radio 8, `TF.body(12, .bold)`; activo `TF.accent`/`TF.accentInk`, inactivo `TF.field`/`TF.text2` con borde `TF.fieldLine`). Opacidad 0,55 si silenciado o solo ajeno. Canales: Voz, Batería, Bajo, Guitarra (o una por guitarra separada), Piano, Resto (solo audibles y no vacíos) y un «Tú · parte» por cada mejor toma de otra parte. |
| Disposición compacta | RM:88-120 | Canales en `ScrollView(.horizontal)` sin indicador, `HStack(alignment: .top, spacing: 6)`; `ViewThatFits(in: .horizontal)`: una fila (cabecera, `Divider` 28, canales) o dos (cabecera encima, canales debajo). |
| Mezclador expandido | RM:39-56 | `HStack(alignment: .top, spacing: 10)`: `RecordMasterChannel`, `GuitarInputChannel`, `Divider` alto 200 con `padding(.horizontal, 6)`, y `ScrollView(.horizontal)` con indicador (`spacing: 10`, `padding(.bottom, 10)`) de `MixerChannel`. |
| `RecordMasterChannel` | RM:172-189 | Ancho 96, alto 276 (`MixerChannel.height`, BM:161), `padding(.vertical, 12)`, radio 12, fondo `TF.accentBg` @0,5, borde `TF.accent` @0,6. «Master» `TF.body(12, .semibold)` (alto 22); `Fader` 28×150 con `padding(.horizontal, 18).padding(.top, 4)`; valor `Fmt.db`; relleno vacío de 40; `spacing: 6`. |
| `GuitarInputChannel` | RM:192-216 | Ancho 96, alto 276, radio 12, fondo `TF.field`, borde `TF.fieldLine`. Título «Tu guitarra» (22), barra de nivel 12×150 (§2.5) con `padding(.top, 4)`, «Entrada» `TF.body(12)` `TF.text2`, relleno de 40. |
| `MixerChannel` | BM:143-203 | Ancho 96 × 276; título 22; fader 28×150 + `levelBar` 8×150, `spacing: 10`; valor «−6,0 dB» o «Silenciado»; M/S 36×36, `spacing: 6`, `padding(.top, 4)`; opacidad 0,55 si atenuado. Guitarra que se sustituye: silenciada y no reactivable (RM:138-142). Ya especificado como `TfMixerChannel`, `TfFader`, `TfLevelBar` en `tokens-componentes.md` §3.1: reutilizar. |

### 2.5 Geometría de lo que va en `CustomPainter`

**Medidor vertical** (`GuitarInputChannel`, RM:198-207; mismo trazo que `levelBar`, BM:206-219):
- Lienzo 12×150 (canal Entrada) u 8×`faderHeight` (stems; 150 con el alto por defecto 276).
- Pista: `RRect` radio 4 `TF.bg`. Relleno: `RRect` radio 4 anclado abajo, alto = `h × clamp(nivel, 0, 1)`, degradado lineal de abajo arriba calculado **sobre el rectángulo del relleno** (no de la pista), con paradas `TF.ok` en 0,70 y `TF.accent` en 0,92.
- Nivel de entrada: ya 0…1 (máximo de los canales de guitarra asignados, RV:126-128). Stems: `(rmsDB − floor) / −floor` con `floor = −60 dB` (BM:208-209), recortado a 0…1; canal atenuado = 0.
- Refresco cada 0,05 s (RV:98): repintar con `ValueNotifier`.

**Medidor horizontal compacto** (RM:78-85): lienzo 22×8; pista `RRect` radio 3 `TF.bg`; relleno `RRect` radio 3 `TF.ok` (sin degradado), ancho `22 × clamp(nivel, 0, 1)`, anclado a la izquierda.

**Zona de punch** (PT:23-68), ancho = el de la tarjeta menos 32, alto fijo **54** (PT:14):
- Escala: `x(t) = t / max(duration, 0,001) × ancho` (segundos; `duration` = duración del tema).
- Fondo: `RRect` radio 8 `TF.bg`, toda la zona.
- Secciones: `RRect` radio 4, color `TF.sectionPalette[(sectionPalette[id] ?? 0) % 7]` @0,30, ancho `max(x(fin) − x(inicio), 2)`, alto 40 (54 − 14), `y = 7`. Nombre arriba a la izquierda: `TF.body(10, .medium)` en el color pleno, una línea, `padding(.horizontal, 4)`.
- Tramo (si hay entrada `a`; `b` = salida o `a` si falta): `Rect` `TF.accent` @0,28, ancho `max(x(b) − x(a), 2)`, alto 54, `y = 0`.
- Asas: `RRect` radio 2 `TF.accent` de **6×54**, en `x(a) − 3` y `x(b) − 3`; una por marca existente.
- Cursor: línea blanca @0,8 de **1×54** en `x(time)`, la última capa; solo si `phase != .idle` o `time > 0`.
- Accesibilidad de las asas: «Entrada del punch-in», «Salida del punch-in».
- Clic, arrastre, imán al compás y ⌥: `grabar-interaccion.md` §6.

**Línea de tiempo de tomas**: no existe en SwiftUI; las tomas son botones en el panel «Partes» (§2.6). No se pide inventarla.

### 2.6 Panel «Partes» y lista de tomas

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Panel | RV:114, RV:192-208 | `ScrollView` de ancho fijo **320**; `Card`, `padding(.horizontal, 20).padding(.vertical, 18)`; `VStack(spacing: 12)`. «Partes» `TF.display(18)`; nota `TF.body(13)` `TF.muted` multilínea. |
| Caja de parte | RV:210-231 | `VStack(alignment: .leading, spacing: 8)`, `padding(.horizontal, 14).padding(.vertical, 12)`, ancho completo, radio 12. Activa: fondo `TF.accentBg`, borde `TF.accent` 1; inactiva: `TF.field` y `TF.fieldLine`. Clic en toda la caja = elegir parte. |
| Cabecera de parte | RV:213-219 | Nombre `TF.body(14, .semibold)` una línea, `Spacer`, chip. Debajo «Sustituye: <guitarra>» o «Parte añadida» `TF.body(12)` `TF.muted`. |
| Chip de estado | RV:233-241 | Cápsula, `padding(.horizontal, 9).padding(.vertical, 3)`, `TF.body(11, .semibold)`: «Hecha» `TF.ok`/`TF.okBg`; «Grabando» `TF.danger`/`TF.dangerBg`; «Pendiente» `TF.text2`/`TF.neutralBg`. Difiere del `Chip` del tema (padding 10/4, 12 pt): `TfChip` necesita parámetro de tamaño. |
| Lista de tomas | RV:220-222 | `FlowRow` con separación 6: por toma, botón-menú + botón ▶ (RV:257-269). |
| Botón de toma | RV:271-292 | «Toma N» o «Toma N · mejor», `TF.body(12, .semibold)`, `padding(.horizontal, 10)`, alto 32, radio 8. Reposo: fondo `TF.sidebar`, borde `TF.fieldLine` 1, texto `TF.text2`. Seleccionada: fondo `TF.accentBg`, borde `TF.accent` **2**. Mejor: fondo `TF.okBg`, texto `TF.ok`, borde `0x2F6B45` 1 (`TfColors.okBorder`). La seleccionada gana al mejor en fondo y borde; el texto sigue en `TF.ok` si es mejor. Chevron del sistema a la derecha (`menuIndicator(.visible)`, `fixedSize`). Deshabilitado con `isBusy`. |
| Botón ▶ | RV:260-268 | 32×32, icono `play.fill` 11 pt `TF.text2`, fondo `TF.sidebar`, radio 8, borde `TF.fieldLine`; separación 4 con el botón de toma. Deshabilitado con `isBusy`, sin `processedFile` o sin `songStart`. |
| Añadir parte | RV:199-204 | Ancho completo, alto 44, `TF.body(14, .medium)` `TF.text2`, borde discontinuo (trazo 1, patrón 4-3, radio 10) en `TF.muted`. Deshabilitado con `isBusy`. |
| Menú de toma | RV:273-282 | «Marcar como mejor» (inactiva si ya es la mejor), «Ajustar desfase…» (inactiva sin vídeo), «Punch-in», separador, «Borrar…» (destructiva). `TfMenu`. |

### 2.7 Visor «Ver toma» (TV) y superficie de «Ajustar desfase»

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Hoja | TV:282-301 | Ancho fijo **720**, `padding(20)`, fondo `TF.bg`; `VStack(alignment: .leading, spacing: 14)`: cabecera, pantalla, controles, error (si hay), acciones. |
| Cabecera | TV:303-315 | `HStack`: título «Toma N · <parte>» `TF.display(18)`; si es la mejor, chip «★ mejor» `TF.body(11, .semibold)` `TF.ok` sobre `TF.okBg`, `padding(.horizontal, 9).padding(.vertical, 3)`, cápsula; `Spacer`; botón `xmark` 13 pt semibold `TF.text2` (Esc lo cierra). |
| Pantalla | TV:318-332 | `ZStack` con fondo **negro** (`Color.black`), `aspectRatio(16/9, .fit)`, radio **10**, borde `TF.line`. Contenido: **`TfVideoSurface`** con vídeo; «Sin vídeo: solo audio» `TF.body(12)` `TF.muted` si hay audio y no vídeo; `TfSpinner` mientras carga (sin error). |
| Controles | TV:334-359 | `HStack(spacing: 12)`: botón redondo 36×36 `TF.accent`, icono `play.fill`/`pause.fill` 15 pt `TF.accentInk`; posición `m:ss` (`Fmt.clock`, trunca, BackingTimeline:473) `TF.body(12)` `TF.muted` monoespaciada; `Slider` flexible `0…max(duración, 0,1)` (`TfSlider` con tinte `TF.accent`; SwiftUI usa el acento del sistema, desvío visual aceptado, decisiones-interfaz.md); duración igual que la posición; botón «Backing»/«Backing mudo» (alto 32, `padding(.horizontal, 10)`, radio 8, fondo `TF.field`, borde `TF.fieldLine`; icono `speaker.wave.2.fill` o `speaker.slash.fill` + `TF.body(12, .semibold)`; `TF.text2` encendido, `TF.accent` mudo). |
| Error | TV:287 | Línea `TF.body(12)` `TF.danger`. |
| Acciones | TV:361-367 | `HStack(spacing: 10)`: `SecondaryButton` «Marcar como mejor» (inactivo si ya es la mejor), `Spacer`, `SecondaryButton` «Eliminar…» (confirma con diálogo, TV:295-300). |
| Superficie de «Ajustar desfase» | OS:34-48 | Misma receta: negro, 16:9 fit, radio **12**, borde `TF.line`, `PlayerLayerView` o error `TF.danger` con `padding()` o `TfSpinner`. Resto de la hoja: `grabar-interaccion.md` §7. |

**`TfVideoSurface` en el visor** (TV:322, OS:135-149): `AVPlayerLayer` con `videoGravity = .resizeAspect` (fit), llena la caja (`autoresizingMask` ancho y alto). Diferencias con la cámara:
- **Relación de aspecto**: la del lienzo del plan, `canvas: .landscape` (TV:79), que es 16:9; el reproductor entrega ya la composición renderizada con `MontageBuilder.renderSize(canvas, maxDimension: previewMaxDimension)`. La imagen coincide con la caja: casi no hay barras. Si el vídeo de la toma es vertical, el montaje lo encaja dentro del 16:9 (barras negras laterales); lo hace el núcleo, no el widget.
- **Rotación**: la aplica el plan (`rotation: VideoRotation(degrees: take.videoRotation ?? 0)`, TV:50) antes de entregar el fotograma; `TfVideoSurface` **no gira** nada en el visor.
- **Espejo**: ninguno (composición, no capa de captura).
- **Origen del fotograma**: textura alimentada por el núcleo con el reloj del audio como maestro (`takeview.position`, `grabar-contrato.md`); la hoja no tiene reproductor propio en Flutter.

## 3. Árbol de widgets propuesto

- `RecordScreen` (RV:7-24): `RecordTopicChooser` (RV:26-45), `TfSpinner` o `RecordContent`.
  - `RecordContent` (RV:48-85): tema sin separar → `TfCard` con aviso + `TfSecondaryButton`; si no, `RecordBody`.
  - `RecordBody` (RV:87-141): `Padding(36, 20)` > `Column`:
    - `RecordHeader` (RV:145-164) con «Ir al montaje» (alto 44, `TfSecondaryButton` con texto semibold `text2`: reutilizar con parámetro).
    - `Row(crossAxisAlignment: start, gap: 20)`:
      - `Expanded > Column(gap: 14)`:
        - `RecordPreview` (RV:360-458): `AspectRatio(16/9)` + `ClipRRect(16)` + borde; `Stack`:
          - `PreviewBackdrop` (`DecoratedBox` con `RadialGradient`; o `CustomPainter` si la captura no coincide).
          - **`TfVideoSurface`** (`Texture`; fit + `RotatedBox`; §2.2.1) o `PreviewPlaceholder` (`TfStateMessage` ampliado).
          - `PreviewOverlay` (`Padding(16)`): `RecPill`, `FormatPill`, `RotatePill` con `LayoutBuilder` que reproduce el `ViewThatFits`; `CountdownNumber` (`Text` 64 con sombra).
        - `RecordBar` (RV:462-538): `TfCard` > `RecordButton` (cápsula 48), `TimeReadout`, `OffsetLabel`, `Wrap(spacing: 18)` con `TfDropdown`, `TfCheckbox`, `TfDropdown`, `TfCheckbox`.
        - `RecordStatusLines` (RV:168-188).
        - `PunchTimeline` (PT) con `PunchTimelinePainter` (**`CustomPainter`**, §2.5).
        - `RecordMixer` (RM): `TfCard` > `MixerHeader`, `CompactMixer` (Master con `TfSlider` 40, `HorizontalLevelPainter` (**`CustomPainter`**), canales con `TfToggleButton`) o `ExpandedMixer` (`TfMixerChannel` con `TfFader` y `TfLevelBar` (**`CustomPainter`**), `MasterChannel`, `GuitarInputChannel` con `VerticalLevelPainter` (**`CustomPainter`**)).
      - `SizedBox(320) > SingleChildScrollView > PartsPanel` (RV:192-208): `TfCard` > `PartBox` (RV:210-231) > `PartStatusChip`, `TakeWrap` (`Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: center)`) > `TakeButton` (`TfMenu` + `TfIconButton` 32×32); «Añadir parte» con `DashedRRectPainter` (**`CustomPainter`**, si el kit no trae borde discontinuo).
  - `TakeViewerSheet` (TV:261-367, hoja en `TfSheet` de 720): cabecera, `VideoBox` (negro, 16:9, radio 10, **`TfVideoSurface`**), `ViewerControls` (botón 36, `TfSlider`, botón Backing), `ViewerActions`. Estado en `TakeViewerStore` (posición, `playing`, `backingOn`, `hasBacking`, `error`).
  - Otras hojas y diálogos (`grabar-interaccion.md` §7): `AddPartSheet`, `OffsetSheet` (su `VideoBox` con radio 12 y `TfVideoSurface`), `TfConfirmDialog` de borrado.
- `RecordStore` (Riverpod; contrato en `grabar-contrato.md`): `phase`, `cameraState`, `time`, `levels`, `parts`, `takes`, `punch`, `mix`. Un `Notifier` para el flujo de grabación y otro para el mezclador (~300 líneas por fichero).

**`CustomPainter`**: `PunchTimelinePainter`, `VerticalLevelPainter` (también `TfLevelBar`), `HorizontalLevelPainter`, `DashedRRectPainter`. **`Texture`** (`TfVideoSurface`): cámara, visor y «Ajustar desfase».

## 4. Estados

`phase` = `idle | counting(n) | recording | finishing | adjusting` (RC:89); `cameraState` = `idle | none(msg) | denied | simulated | failed(msg) | live` (RC:90-93). «Ocupado» = `phase != .idle` (RC:510): deshabilita «Ir al montaje», opciones, menús y botones de toma, «Añadir parte», punch y «Rotar».

| Estado | Qué se ve | Qué lo decide |
| --- | --- | --- |
| Sin tema elegido | Selector de temas separados, o «Aún no hay temas separados…» (RV:26-45). | `backingTarget == nil`, `entries` con separación `done`. |
| Cargando tema | `TfSpinner` centrado. | `model.study == nil`; `ctl == nil`. |
| Tema sin separar | `TfCard` «Este tema aún no está separado» y botón a la biblioteca. | `session.project.separation.state != .done`. |
| Sin cámara | Caja con degradado y marcador «Sin vídeo: se grabará solo el audio» (icono según altura); sin píldora de formato ni «Rotar» ni etiqueta de desfase; línea de estado `TF.accent` «<motivo> Se grabará solo el audio.». Grabar sigue permitido. | `cameraState` = `none` / `failed` (con mensaje del núcleo); `cameraLabel == nil`. |
| Sin permiso de cámara | Igual que arriba; línea de estado con la ruta a Ajustes del Sistema (RV:175; en Windows y Mac el texto llega del núcleo por código, decisiones-interfaz.md, decisión 16). | `cameraState == .denied`. |
| Cámara simulada | Marcador «Vista previa de la cámara · <nombre> (simulada)»; sí hay píldoras de formato y «Rotar» y etiqueta de desfase. | `cameraState == .simulated`. |
| Buscando cámara | `TfSpinner` en el centro de la caja. Se re-sondea cada 2 s (RV:99, RV:130). | `cameraState == .idle`. |
| Sin calibrar | No bloquea. Línea `TF.accent` «Sin calibrar: la toma puede ir desfasada decenas de ms; se corregirá al calibrar.» solo en reposo y sin otro bloqueo (RV:172). El botón sigue activo. | `!audio.calibrationValid`, `blockReason == nil`, `phase == .idle`. |
| Bloqueado | Botón Grabar al 0,4 y deshabilitado; línea `TF.muted` con el motivo (RV:171): sin dispositivo de entrada, sin entrada de guitarra, canales repetidos, entradas o salidas desconectadas, frecuencia distinta, velocidad ≠ 100 %, bucle, calibración en marcha, «Elige una parte.», o con punch: «Elige la toma sobre la que hacer el punch-in.» / «Marca la entrada y la salida del punch-in en la línea de tiempo.». | `blockReason` (`audio.recordBlock` + parte activa + plan de punch, RC:499-508). |
| Preparado | Botón «Grabar» rojo con círculo blanco; tiempo `0:00 / m:ss`; píldora REC con punto gris `TF.muted` y «Toma N · parte» (sin «REC ·»); todo habilitado. | `phase == .idle`, `blockReason == nil`. |
| Cuenta atrás | Botón «Parar» (cuadrado blanco); número 64 pt blanco abajo en la caja, cambia cada tiempo; píldora REC con punto `0xE5534B` y «REC · Toma N · parte»; el resto deshabilitado; mezcla y medidores animados. | `phase == .counting(n)`, `n` decide el número. |
| Grabando | «Parar»; tiempo avanza cada 0,05 s sobre el total (`plannedStop` o duración); REC rojo; chip de la parte activa «Grabando» (`TF.danger`); «Rotar» deshabilitado; cursor blanco en la zona de punch si está visible; medidor de entrada y de canales vivos. | `phase == .recording`; `status(of:)` = `.recording` (RC:211-214). |
| Punch armado | Casilla «Punch-in» marcada; «Empezar en» deshabilitado; aparece `PunchTimeline` con asas, tramo y resumen; sin marcas: bloqueo «Marca la entrada y la salida…». Durante el punch: tramo y cursor dibujados; para solo 0,5 s después de la salida. La casilla se deshabilita si la parte no tiene tomas. | `punchEnabled`, `punchIn`, `punchOut`, `selectedTake`; `activePart.takeIDs.isEmpty`. |
| Procesando | Botón al 0,4 y deshabilitado (con «Parar» o «Grabar» según la fase previa; el REC sigue rojo porque `phase != .idle`, RV:430); sin spinner ni texto propio; al terminar aparece la toma nueva en el panel. | `phase == .finishing`. |
| Mensajes de fin de toma | Líneas `TF.accent`: «La toma se detuvo y se guardó lo grabado.», «No llegaron fotogramas de la cámara: la toma es solo de audio.», avisos de toma (`takeNotices`). | `ctl.messages`, `audio.takeNotices`. |
| Ajustando desfase | Hoja «Ajustar desfase» abierta; REC con punto gris; botón Grabar al 0,4 deshabilitado. | `phase == .adjusting`, `offsetRequest != nil`. |
| Reproduciendo toma (visor) | Hoja de 720 abierta sobre Grabar (que queda inerte): ▶ cambia a pausa, posición y slider avanzan (el slider tiene paso continuo; el núcleo emite `takeview.position` a 30 Hz), «Backing»/«Backing mudo». Sin vídeo: caja negra con «Sin vídeo: solo audio». Cargando: `TfSpinner` en la caja y controles deshabilitados. Al llegar al final, ▶ reinicia desde 0 (TV:245). Sin stems: botón «Backing» deshabilitado (`hasBacking == false`). | `ready`, `hasVideo`, `isPlaying`, `backingOn`, `hasBacking`; al abrir, `prepareToViewTake()` debe devolver true (RV:253). |
| Error del visor | Línea `TF.danger` bajo los controles: «Esta toma no tiene audio que reproducir.» o «No se pudo preparar la toma (…)». Controles deshabilitados; «Marcar como mejor» y «Eliminar…» siguen activos. | `TakeViewerModel.error`, `ready == false`. |
| Error de carga de stems o de guardado | Línea `TF.danger` en el bloque de estado: «No se pudieron cargar los stems (…)», «No se pudieron cargar tus tomas anteriores (…)», o `takeSaveError`. | `ctl.loadError`, `session.takeSaveError`. |
| Error al grabar | Línea `TF.accent` con el mensaje del fallo («No se pudo grabar la toma (…)» o el de `RecordFailure`); la fase vuelve a `idle`. | `ctl.messages`. |
| Mezclador plegado/expandido | Plegado por defecto (altura mínima); expandido muestra faders y medidores y encoge la caja de cámara conservando 16:9. Estado local de la pantalla, no se guarda. | `mixerExpanded` (RV:95). |
| Parte activa / otra | Caja activa en `TF.accentBg`/`TF.accent`; resto en `TF.field`. Al grabar, solo la activa muestra «Grabando». | `activePartID`. |
| Toma seleccionada / mejor / ambas | Ver botón de toma (§2.6); la selección es la base del punch-in. | `selectedTakeID`, `bestTakeID`. |

Pendiente de Jorge (de oído o con hardware): ver §11.

## 10. Partes de trabajo sugeridas

| Parte | Ficheros Dart | Tamaño | Agente |
| --- | --- | --- | --- |
| A. Contrato y stores | `contract/record.dart`, `contract/takeview.dart`, `features/record/record_store.dart`, `mixer_store.dart`, `take_viewer_store.dart` + fixtures en `Contract/fixtures/record/` (`grabar-contrato.md`) | L | `tf-flutter` (Sonnet) |
| B. Superficie de vídeo | `widgets/tf_video_surface.dart` (`Texture`, fit, rotación, espejo configurable, tamaño dinámico) en el kit | M | `tf-flutter` (Sonnet) |
| C. Carcasa y selector | `record_screen.dart`, `record_topic_chooser.dart`, `record_header.dart`, marco, estados de tema | S | `tf-flutter-mech` (Haiku) |
| D. Vista de cámara | `widgets/record_preview.dart` (fondo, píldoras con `LayoutBuilder`, contador, marcador de posición) | M | `tf-flutter` (Sonnet) |
| E. Barra de grabación y estado | `widgets/record_bar.dart`, `status_lines.dart`, `time_readout.dart` | M | `tf-flutter` (Sonnet) |
| F. Zona de punch | `widgets/punch_timeline.dart` + `punch_timeline_painter.dart` (`CustomPainter`, §2.5) | M | `tf-flutter` (Sonnet) |
| G. Mezclador | `widgets/record_mixer.dart`, `compact_mixer.dart`, `expanded_mixer.dart`, `vertical_level_painter.dart`, `horizontal_level_painter.dart` (reutiliza `TfMixerChannel`/`TfFader` del kit) | L | `tf-flutter` (Sonnet) |
| H. Panel de partes y tomas | `widgets/parts_panel.dart`, `part_box.dart`, `take_button.dart`, `dashed_rrect_painter.dart`, menú de toma | M | `tf-flutter` (Sonnet) |
| I. Visor «Ver toma» | `sheets/take_viewer_sheet.dart`, `widgets/viewer_controls.dart` | M | `tf-flutter` (Sonnet) |
| J. Hojas de desfase y de parte | `sheets/offset_sheet.dart`, `sheets/add_part_sheet.dart` (`grabar-interaccion.md` §7) | M | `tf-flutter` (Sonnet) |
| K. Textos | claves de `grabar-interaccion.md` §8 en `app_es.arb` y `app_en.arb` | S | `tf-flutter-mech` (Haiku) |
| L. Tests | `test/features/record/*`, goldens | M | `tf-flutter` (Sonnet) |

Orden: A y B primero; C a J en paralelo (D, I y J necesitan B); K y L al final. G depende del kit (`TfMixerChannel`, `TfFader`, `TfLevelBar`) de la ola de cimientos.

## 11. Criterios de aceptación

Capturas de referencia (SwiftUI en Mac con `--screen record`, `record-counting`, `record-offset`, `record-mixer-expanded` y `--window 1100x680` y `1440x900`, `RecordDemo.swift`; el resto requiere sembrar el estado):

| Estado | PNG |
| --- | --- |
| Preparado, cámara simulada, mezclador compacto (1440×900 y 1100×680) | `record-ready.png`, `record-ready-min.png` |
| Cuenta atrás (`record-counting`) | `record-counting.png` |
| Grabando | `record-recording.png` |
| Procesando | `record-finishing.png` |
| Punch armado con marcas y secciones | `record-punch.png` |
| Punch armado sin marcas (bloqueado) | `record-punch-unmarked.png` |
| Sin cámara / permiso denegado | `record-nocamera.png`, `record-denied.png` |
| Sin calibrar | `record-uncalibrated.png` |
| Mezclador expandido (`record-mixer-expanded`) | `record-mixer-expanded.png` |
| Panel de partes con tomas: mejor, seleccionada, ambas | `record-parts.png` |
| Hoja de desfase (`record-offset`) | `record-offset.png` |
| Visor reproduciendo, sin vídeo, cargando, error | `takeview-playing.png`, `-audioonly.png`, `-loading.png`, `-error.png` |
| Tema sin separar / selector de temas | `record-notsplit.png`, `record-chooser.png` |

Tests de store (con `MockCore`): `RecordStore` pasa por `idle → counting(n) → recording → finishing → idle` según los eventos; el botón envía `startTake` en `idle` y `stopTake` en `counting` y `recording`; `blockReason` se refleja sin habilitar el botón; el punch exige toma elegida y marcas antes de habilitar; `rotateCamera` suma 90 módulo 360; `setCountIn`, `setPreRoll`, `setStartSection` envían solo lo que cambia; mezclador: `setMaster` con imán a 0 dB por debajo de 1,5; `TakeViewerStore` con `takeview.position` actualiza posición y `playing`, reinicia desde 0 al final y deshabilita «Backing» sin stems.

Tests de widget: `PunchTimelinePainter` (posiciones de asas, tramo y cursor con `duration` conocida; ancho mínimo 2 para secciones y tramo); `VerticalLevelPainter` (alto del relleno = `h × nivel`, degradado 0,70/0,92) y `HorizontalLevelPainter` (22×8); `TfVideoSurface` (contain con aspecto 4:3 en caja 16:9; giro de 90° intercambia aspecto; sin fotograma no pinta); botón de toma (los cuatro aspectos); píldora REC (punto gris frente a rojo y «REC · »); marcador de posición con tres alturas; `FlowRow` equivalente (`Wrap`) envuelve a 860 de ancho mínimo.

Solo Jorge puede probarlo con hardware o de vista/oído:

1. Cámara real en Mac y en Windows: imagen, giro con «Rotar» (0, 90, 180, 270), proporciones con vídeo vertical y **espejo** frente a SwiftUI (§2.2.1).
2. Cuenta atrás y grabación con la Flex Prime: el contador y el cursor del tiempo siguen al audio sin saltos; fluidez a 15 fps de la vista previa de Windows.
3. Medidor de «Tu guitarra» con la guitarra real: respuesta a 0,05 s y color (naranja cerca del tope).
4. Punch-in: marcar y mover asas con y sin ⌥, parada 0,5 s tras la salida.
5. «Ver toma»: sincronía imagen y sonido a ojo con un golpe seco, y que coincida con lo que enseña «Ajustar desfase».
6. Colores y contraste de las píldoras sobre una imagen real clara y oscura.

## Dudas para Jorge

1. Resuelto: se replica lo que salga de la captura de SwiftUI con cámara real en la ola 3 (hardware de Jorge) (decisiones-interfaz.md, «Se resuelven midiendo»: Espejo de la cámara). Sigue siendo prueba manual de §11.1.
2. Resuelto: dos tokens con nombre (decisiones-interfaz.md, «Cerradas por la regla 1:1»: Grabar, dos rojos sueltos).
3. Resuelto: `TF.accent`; desvío visual aceptado, se enseña a Jorge en la revisión de la ola 3 (decisiones-interfaz.md, «Cerradas por documentación oficial»: Slider del visor).
