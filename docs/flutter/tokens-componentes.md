# Fase 7f · Tema y kit de widgets compartidos

Fuente: `App/Sources` (SwiftUI, manda). Comparaciones con `WinApp/Web/tokens.css` e `icons.js` solo para señalar diferencias. Reglas 4 y 5 de [arquitectura.md](arquitectura.md): ningún color, tipografía, radio, espaciado ni texto fuera de `lib/theme/` y `AppLocalizations`.

Ficheros Dart previstos: `theme/tokens.dart` (`TfColors`, `TfRadius`, `TfSpace`, `TfStroke`, `TfOpacity`, `TfShadow`, `TfSize`), `theme/typography.dart` (`TfText`), `theme/tf_theme.dart` (`ThemeData` oscuro, forzado), `widgets/` (kit).

Conteos del barrido (hechos medidos con `grep` sobre `App/Sources`, 16 398 líneas): 56 símbolos SF distintos; 21 `Picker`, 22 `Toggle`, 9 `Slider`, 9 `TextField`, 11 `.sheet`, 5 `.popover`, 2 `.alert`, 8 `confirmationDialog`, 21 `Divider`, 27 `ProgressView`, 22 `Capsule()`.

## 1. Tokens

### 1.1 Colores `TF.*` (`Theme.swift:12-31`)

| Swift | Hex | Dart | Uso |
| --- | --- | --- | --- |
| `TF.bg` | `0F1113` | `TfColors.bg` | fondo de ventana (`RootView.swift:25`) |
| `TF.sidebar` | `15181B` | `TfColors.sidebar` | barra lateral |
| `TF.card` | `171A1D` | `TfColors.card` | `Card`, hojas |
| `TF.field` | `1C2024` | `TfColors.field` | campos, botón secundario, fondos de fila |
| `TF.line` | `252A2F` | `TfColors.line` | borde de tarjeta, divisores |
| `TF.fieldLine` | `2A3036` | `TfColors.fieldLine` | borde de control (35 usos como `.stroke`) |
| `TF.text` | `E8EAED` | `TfColors.text` | texto principal |
| `TF.text2` | `C9CED4` | `TfColors.text2` | texto secundario |
| `TF.muted` | `9AA3AD` | `TfColors.muted` | texto atenuado, iconos |
| `TF.accent` | `F2A33A` | `TfColors.accent` | acento (naranja) |
| `TF.accentBg` | `2A2116` | `TfColors.accentBg` | fondo activo / chip «trabajando» |
| `TF.accentInk` | `1A1206` | `TfColors.accentInk` | texto sobre acento |
| `TF.ok` | `6FD99E` | `TfColors.ok` | éxito |
| `TF.okBg` | `16301F` | `TfColors.okBg` | fondo de chip ok |
| `TF.neutralBg` | `1F242A` | `TfColors.neutralBg` | chip neutro, botón primario deshabilitado |
| `TF.danger` | `F07178` | `TfColors.danger` | error |
| `TF.dangerBg` | `331A1C` | `TfColors.dangerBg` | fondo de chip error |

`TF.sectionPalette` (`Theme.swift:29`, orden de `SectionEditor.paletteCount`): `6C9BD2` azul, `6FB58A` verde, `9C86C9` violeta, `C97F9E` rosa, `5DB5B5` turquesa, `A6B85C` lima, `C8706A` coral. Dart: `TfColors.sectionPalette` (`List<Color>`, mismo orden). El naranja queda fuera «por ser de los solos».

### 1.2 Tipografía (`Theme.swift:33-57`)

Solo existen 5 caras; cada peso pedido se mapea a una. En Flutter se declaran en `pubspec.yaml` como dos familias con 3 y 2 `weight`; `TfText` solo admite los pesos que existen.

| Función Swift | Cara (PostScript) | Dart |
| --- | --- | --- |
| `TF.display(s)` / `.medium` (y `.regular` o menos) | `SpaceGroteskLight-Medium` (500) | `TfText.display(s, TfWeight.medium)` |
| `TF.display(s)` por defecto = `.bold` (semibold, bold, heavy, black) | `SpaceGroteskLight-Bold` (700) | `TfText.display(s)` |
| `TF.body(s)` por defecto `s=14`, `.regular` | `Inter-Regular` (400) | `TfText.body(s)` |
| `TF.body(s, .medium)` | `Inter-Medium` (500) | `TfText.body(s, TfWeight.medium)` |
| `TF.body(s, .semibold/.bold/.heavy)` | `Inter-SemiBold` (600) | `TfText.body(s, TfWeight.semibold)` |

Nota: `.bold` en `body` (p. ej. `TF.body(11, .bold)`, `MixerToggle` `BackingMixer.swift:264`) se pinta en SemiBold 600: Dart no debe ofrecer `bold` para body.

**Tamaños que se usan** (recuento de `.font(...)`):
- `body`: 10 (3), 11 (16), 12 (≈92: 63 regular, 14 semibold, 12 medium, 2 bold…), 13 (≈96: 69 regular, 16 semibold, 7 medium…), 14 (≈29), 15 semibold (8), 16 (2). Pasos: 10, 11, 12, 13, 14, 15, 16.
- `display`: 16 (7), 18 (15 + 1 medium), 20 (6), 22 (8), 24 (1), 26 (5), 28 (1), 30 (5), 32 (2), 34 (1), 64 (1). Títulos de pantalla: 30 (`SettingsView.swift:13`) y 32 (`LibraryView.swift:110`); logo 22 (`RootView.swift:56`); contador de cuenta atrás 64 (`RecordView.swift:381`); iniciales de artista 34 (`ArtistGrid.swift:42`).
- Tamaño por defecto de la vista raíz: `TF.body()` = Inter 14 (`RootView.swift:26-27`: `foregroundStyle(TF.text)` + `font(TF.body())`). El color de texto por defecto de toda la app es `TF.text`, no el del sistema. Dart: `DefaultTextStyle` = `TfText.body(14)` con color `text`.
- `monospacedDigit()`: 38 líneas en `App/Sources/*.swift` (tiempos, dB, porcentajes). Inter con `FontFeature.tabularNums()`.
- Pestañas/selección alternan peso con el estado: `TF.body(13, on ? .semibold : .medium)` (`TabScreen.swift:219`; pastilla de pista: body 13 semibold/medium, icono 12, gap 6, alto 34, h 14, borde `accent` activo completo, `fieldLine` inactivo). El `TfText` debe aceptar peso variable.
- Mayúsculas de cabecera de tabla: `.uppercased()` + `.tracking(0.7)`, body 12 medium (`LibraryView.swift:156-159`). Dart: `letterSpacing: 0.7`.
- Iconos con `.font(.system(size: N))` (tamaño del símbolo, no tipografía): 10, 11, 12, 13, 14, 15, 16, 18, 20, 28 (light), 40.

### 1.3 Escalas de formato (`Fmt`, `Theme.swift:138-147` y extensiones)

`Fmt.bytes` (`ByteCountFormatter`, estilo archivo), `Fmt.percent` → «NN %» (con espacio), `Fmt.duration` → `m:ss`, `Fmt.rate` → «44,1 kHz» / «48 kHz» / «N Hz»; extensiones `Fmt.db` (`BackingMixer.swift:277`, «−6,0 dB»: 1 decimal, coma), `Fmt.clock` (`BackingTimeline.swift:473`), otra en `CalibrationSheet.swift:4`. En Dart: `TfFmt` en `lib/theme/fmt.dart` (la regla 5 de textos no la afecta: es formato, no copia; el separador decimal de `Fmt.db` y `Fmt.rate` sigue el idioma, coma en español y punto en inglés, con `intl` y coherente con `decimalPattern` del núcleo (Jorge, 24/11/2026)).

## 2. Literales fuera del tema

### 2.1 Colores en hex en las vistas (nombre propuesto)

| Hex | Usos | Ejemplos | Token propuesto | Observación |
| --- | --- | --- | --- | --- |
| `C8433A` | 2 | `RecordView.swift:467`, `BackingRecord.swift:11` | `TfColors.recordButton` | botón Grabar |
| `E5534B` | 1 | `RecordView.swift:433` | `TfColors.recordLive` | punto de grabación; casi igual que `C8433A`, pero no se funden: token propio (Jorge, 24/11/2026) |
| `2F6B45` | 1 | `RecordView.swift:284` | `TfColors.okBorder` | borde de la «mejor toma» |
| `121417` | 1 | `RecordView.swift:366` | `TfColors.previewDeep` | fin del degradado radial de la vista previa; inicio `2A3036` = `fieldLine` |
| `0F1113` @0.75 | 1 | `RecordView.swift:456` | `TfColors.bg` + `TfOpacity.scrim75` | duplica `TF.bg`, no es un color nuevo |
| `0B0C0E` | 1 | `MontageView.swift:351` | `TfColors.videoBg` | fondo de la vista previa de montaje; casi igual que `bg` (`0F1113`), pero no se funden: token propio (Jorge, 24/11/2026) |
| `5A636C` | 1 | `MontageView.swift:299` | `TfColors.tileGrey` | miniatura de disposición |
| `5BC0EB` | 2 | `MontageView.swift:509`, `BackingTimeline.swift:581` | `TfColors.timelineBlue` | carril 1 de montaje y barra de progreso de la línea de tiempo |
| `B79CFF` | 1 | `MontageView.swift:510` | `TfColors.soloViolet` | carril de solos |
| `4CC38A` | 1 | `RootView.swift:95` | `TfColors.deviceOk` | punto «dispositivo conectado»; casi igual que `ok` (`6FD99E`), pero no se funden: token propio, como la web (`--device-ok`) (Jorge, 24/11/2026) |
| `F2A33A` `6FD99E` `C97F9E` `5DB5B5` | 4 | `MontageView.swift:509` | `TfColors.laneColors` = [`timelineBlue`, `accent`, `ok`, `sectionPalette[3]`, `sectionPalette[4]`] | reusan tokens existentes |
| `.white` | ≥8 | `RecordView.swift:478`, `BackingRecord.swift:22`, `ArtistGrid.swift:42` (0.9) | `TfColors.white` | |
| `.black` | ≥9 | `TakeViewer.swift:320`, `VideoSettingsView.swift:288`, `OffsetSheet.swift:34` | `TfColors.black` | fondos de vídeo |
| `Color(hue: h%360/360, sat 0.45, br 0.5)` | 1 | `ArtistGrid.swift:74` | `TfColors.artistAvatar(String name)` | color de avatar derivado de FNV-1a 64 bits del nombre (`ArtistGrid.swift:72-73`) |
| `VideoSettingsView.swift:388`: `.white .yellow .cyan .green .pink .red .blue .black` | 8 | | `TfColors.colorBars` | barras de colores de prueba (sistema, no paleta): sRGB de los colores de SwiftUI en modo oscuro, a confirmar con la captura de referencia (orquestador, 24/11/2026, por el criterio de Jorge) |

Fuera del barrido de vistas: `LinkImportDemo.swift:75` y `SpotifyDemo.swift:54-55` son demos (`NSColor` con RGB 0.95/0.64/0.23 y HSB), no se portan.

### 2.2 Radios de esquina (`cornerRadius`)

| Valor | Usos | Ejemplos | Token |
| --- | --- | --- | --- |
| 10 | 60 | `Theme.swift:67`, `RootView.swift:101`, `TabSourceSheet.swift:54` | `TfRadius.control` |
| 8 | 54 | `LibraryView.swift:148`, `MixerToggle` `BackingMixer.swift:267`, `TakeViewer.swift:353` | `TfRadius.field` |
| 12 | 20 | `RecordView.swift:225`, `MontageView.swift:268`, `BackingMixer.swift:177` | `TfRadius.tile` |
| 6 | 15 | `MontageView.swift:316,566`, `SectionBoxes.swift:384` | `TfRadius.small` |
| 4 | 15 | `ChordDiagram.swift:46`, `MontageView.swift:643`, `BackingMixer.swift:292` | `TfRadius.xs` |
| 14 | 8 | `Theme.swift:116` (`Card`), `ArtistGrid.swift:22`, `RecordView.swift:526` | `TfRadius.card` |
| 3 | 7 | `MontageView.swift:299,792` | `TfRadius.r3` |
| 2 | 7 | `RecordView.swift:478`, `MontageView.swift:677` | `TfRadius.r2` |
| 16 | 3 | `RecordView.swift:365,387` | `TfRadius.hero` |
| 9 | 2 | `SectionBoxes.swift:64,67` | `TfRadius.r9` (cercano a 8/10) |
| 7 | 2 | `TabScreen.swift:250` | `TfRadius.r7` (cercano a 6/8) |

Más `Capsule()` (22 usos, `Theme.swift:94,134`) → `TfRadius.pill` (radio = alto/2). `LibraryView.swift:438` usa `Self.radius = 8`. Casi iguales: 7 y 9 podrían ser 8; 3 podría ser 2 o 4. Los tokens mantienen el valor literal; no se funden (orquestador, 24/11/2026, por el criterio de Jorge de no fundir valores).

### 2.3 Grosores y bordes

- `.stroke(color)` sin ancho = 1 pt (≈60 usos; 35 con `TF.fieldLine`, 6 con `TF.line`, 8 con acento). `TfStroke.hairline = 1`.
- `lineWidth: 1.5` (`BackingTimeline`, resalte de edición de acordes); `lineWidth: 2` (`TfStroke.thick`, 2 usos: `TF.accent` y `TF.text` en selección de color, `VideoSettingsView.swift:~390`). Trazo discontinuo `dash: [3]` con `TF.fieldLine` (1 uso).
- Separador vertical de la barra lateral: `Rectangle().fill(TF.line).frame(width: 1)` (`RootView.swift:77`). Franja de fila seleccionada: ancho 3 (`LibraryView.swift:238`).
- Borde por estado: en reposo `fieldLine`; activo `accent` (4 + 2 + 2 + …); atenuado `accent @0.6` (`ArtistGrid.swift:23`, `BackingMixer.swift:254`); sin borde cuando está activo relleno (`.clear`).

### 2.4 Opacidades (literales)

| Valor | Usos | Ejemplos | Token |
| --- | --- | --- | --- |
| 0.6 | 10 | `ArtistGrid.swift:23`, `RecordView.swift:381`, `Theme.swift:81` (deshabilitado) | `TfOpacity.disabled` (control) / `.borderAccent` |
| 0.5 | 6 | `BackingMixer.swift:252,294` | `TfOpacity.half` |
| 0.4 | 6+ | `TabScreen.swift:197`, `MontageView.swift:574` | `TfOpacity.dim` |
| 0.55 | 5 | `BackingMixer.swift` (`dim ? 0.55 : 1`) | `TfOpacity.muted` (cercano a 0.5) |
| 0.7 | 3+4 | `MontageView.swift:574`, `BackingRecord.swift:186`; pulsado secundario `Theme.swift:79` | `TfOpacity.pressedSecondary` |
| 0.8 | 2+2 | pulsado primario `Theme.swift:66` | `TfOpacity.pressedPrimary` |
| 0.85 | 3 | `MontageView.swift:646`, `VideoSettingsView.swift:391` | `TfOpacity.bars` |
| 0.35 / 0.28 / 0.30 / 0.22 / 0.20 / 0.18 / 0.16 / 0.12 / 0.07 | 3/2/1/1/1/1/1/1/1 | `MontageView.swift:792,828`; fila seleccionada ok 0.12 `LibraryView.swift:235`; hover 0.07 `LibraryView.swift:236`; sección 0.16/0.07 (`SectionBoxes`) | `TfOpacity.tintStrong/…` |
| 0.45, 0.75, 0.9 | 1 c/u | deshabilitado de otro control, scrim 0.75 `RecordView.swift:456`, blanco 0.9 `ArtistGrid.swift:42` | |

Casi iguales: 0.4/0.45/0.5/0.55 (atenuado), 0.18/0.20/0.22 (tintes). Escala mínima propuesta: 0.07, 0.12, 0.2, 0.35, 0.4, 0.5, 0.6, 0.7, 0.8, 0.85; no se usa: las opacidades mantienen el valor literal de SwiftUI, sin fundir (orquestador, 24/11/2026, por el criterio de Jorge).

### 2.5 Sombras (4, todas negras)

| Parámetros | Dónde | Token |
| --- | --- | --- |
| @0.6, r10, y4 | `RecordView.swift:381` (cuenta atrás) | `TfShadow.countdown` |
| @0.4, r2, y1 | `BackingTimeline.swift:589` (cabezal) | `TfShadow.playhead` |
| @0.5, r3, y2 | `BackingMixer.swift:294` (pomo del fader) | `TfShadow.knob` |
| @0.5, r2, y0 | `SectionBoxes.swift:146` (caja de sección) | `TfShadow.sectionBox` |

### 2.6 Espaciado entre elementos (`HStack/VStack/LazyVGrid spacing`)

Valores y recuento (todos los `spacing:`): 6 (54), 12 (49), 8 (47), 10 (42), 14 (32), 4 (20), 2 (17), 16 (14), 0 (14), 20 (8), 3 (6), 18 (4), 24 (3), 1 (1). Ejemplos: 12 `LibraryView.swift:174`; 14 `LibraryView.swift:210` y `SettingsGroup` `SettingsView.swift:56`; 6 `BackingMixer.swift:166`; 20 `SettingsView.swift:11`.

### 2.7 Padding

Horizontales más frecuentes: 12 (21), 10 (14), 20 (13), 14 (11), 18 (9), 16 (9), 40 (6), 36 (5), 6, 8, 4. Verticales: 10 (13), 12 (12), 6 (7), 32 (7), 14 (6), 18 (5), 3, 4, 16, 8, 20, 24, 28, 48, 64 (`.padding(.top, 64)`, 1). Uniformes: 24 (8), 12 (8), 20 (4), 28 (3), 16, 14, 8, 36, 18, 6, 4, 3. Medidas de pantalla: Ajustes `36/28` (`SettingsView.swift:40`); Tablatura `36/20` en una zona (`TabScreen.swift:71`) y `40/32` en otra (`TabScreen.swift:44`); Grabar `40/32` (`RecordView.swift:43`) y `36/20` (`RecordView.swift:117`). Hojas: `padding(24)` (`TabSourceSheet.swift:38`), `padding(28)` (`RootView.swift:133`, `CalibrationSheet.swift:28`).

**Escala mínima de espaciado/padding** (`TfSpace`): `s1 1 · s2 2 · s3 3 · s4 4 · s6 6 · s8 8 · s10 10 · s12 12 · s14 14 · s16 16 · s18 18 · s20 20 · s24 24 · s28 28 · s32 32 · s36 36 · s40 40 · s48 48 · s64 64`. Casi iguales (no fundir sin decisión): 9 (2) y 22 (1) horizontal en `SectionBoxes`/`PlaylistImport`; 3 y 4; 18, 20 y 16.

### 2.8 Tamaños fijos de control (frame height, `Theme`/vistas)

44 (11: `PrimaryButton`, `SecondaryButton` por defecto, `navRow`, pestañas), 36 (10: botones secundarios compactos, campo de búsqueda `LibraryView.swift:147`, `TrashRowButton`), 28 (11: `ApplyButton`, botones de cabecera de acordes, barras de nivel), 40 (9), 34 (4: pastilla de pista `TabScreen.swift:222`), 32 (4: campo de enlace `TabSourceSheet.swift:146`), 30, 24, 20. Token: `TfSize.controlLg 44`, `controlMd 36`, `controlSm 28`; resto como constante local de su widget, en `theme/` (regla 4).

Diferencia con web (`tokens.css:38-49`): `--ctl-h 44`, `--ctl-h-sm 36`, `--radius-card 14`, `--radius-ctl 10`, `--radius-sm 8`, `--sidebar-w 240`, `--pad-x 40`, `--pad-y 32` coinciden. No tiene 28, 34, 32, 12, 6, 4, 3, 2, 16. Extras de la web ausentes en SwiftUI: `--accent-hover FFC170` (SwiftUI usa `accent @0.8` al pulsar), `--blue 2F7CF6` (azul del sistema).

## 3. Componentes

Estados: en SwiftUI solo existe «pulsado» (`configuration.isPressed`) y «deshabilitado» (`isEnabled`) en los dos botones; **hover** solo en `ArtistTile` (borde acento 0.6), fila de biblioteca (tinte 0.07), `TrashRowButton` (icono `danger`) y `MarqueeText`. **Foco**: no hay anillo propio; los campos usan el del sistema, y los botones `.plain` no muestran foco visible. Lo que no está en esta lista no tiene estado.

### 3.1 Propios (dibujados en SwiftUI)

| Widget Flutter | Origen | Medidas / tokens / estados |
| --- | --- | --- |
| `TfPrimaryButton` | `PrimaryButton` `Theme.swift:60-70` | alto 44, padding h 20, radio 10, body 14 semibold. Normal: fondo `accent`, texto `accentInk`. Pulsado: fondo `accent @0.8`. Deshabilitado: fondo `neutralBg`, texto `muted`, borde `fieldLine` 1. |
| `TfSecondaryButton({height=44})` | `SecondaryButton` `Theme.swift:72-83` | padding h 16, radio 10, body 14 medium, fondo `field` (pulsado `@0.7`), borde `fieldLine`, texto `text`. Deshabilitado: texto `muted` y todo `@0.6`. Alturas usadas: 36 (`LibraryView.swift:224`), 28 (`GuitarOptionsViews.swift:35`). |
| `TfApplyButton` | `ApplyButton` `GuitarOptionsViews.swift:44-51` | alto 28, h 16, radio 10, body 13 semibold, `accent`/`accentInk`, pulsado `@0.8`. Sin estado deshabilitado propio. Se implementa como variante parametrizada de `TfPrimaryButton` (alto 28, body 13 semibold) (Jorge, 24/11/2026). |
| `TfIconButton` | `TrashRowButton` `LibraryView.swift:389-405`; `nudge` `SectionBoxes.swift:380-387`; `SecondaryButton` con icono | Tres variantes. (a) Papelera `TrashRowButton`: 36×36, radio 10, fondo `field`, borde `fieldLine`, icono 14 `muted`, hover `danger` (`LibraryView.swift:389-405`). (b) Carpeta y lápiz de fila: **no** son 36×36 sino `SecondaryButton(height: 36)`: ancho = icono + 2×16, icono con `TF.body(14,.medium)`, color `text` (no `muted`), sin hover (`LibraryView.swift:221-228`); el ancho exacto depende del símbolo SF (confirmar con la captura de referencia, ola 0). (c) `nudge`: 30×24, radio 6, icono 11 bold color `text` (no `muted`) (`SectionBoxes.swift:384-386`). |
| `TfAccentBar({double? value, height=6})` | `AccentBar` `Theme.swift:87-110` | cápsula `field` de fondo, relleno `accent`; con valor: ancho `max(height, w·clamp(v))`; sin valor: tramo de 30 % del ancho que va y viene con `0.5−0.5·cos(2π t)`, periodo 1,6 s. Alturas usadas 5, 6 (def.), 8. Anchos externos 140, 220, 260, 320, expandido. Sin estados. |
| `TfCard` | `Card` `Theme.swift:112-119` | fondo `card`, radio 14, borde `line` 1. Sin padding propio. |
| `TfChip(kind)` | `Chip` `Theme.swift:121-136` | cápsula, padding h 10 v 4, body 12 semibold. ok `ok/okBg`, working `accent/accentBg`, neutral `text2/neutralBg`, error `danger/dangerBg`. Sin estados. |
| `TfFmt` | `Fmt` | ver §1.3. |
| `TfMarquee` | `MarqueeText.swift:5-38` | una línea; si no cabe, `…` al final; al pasar el ratón corre `overflow` px a 30 px/s (lineal) y vuelve en 0,2 s `easeOut`; alto fijo; cambia el texto → reinicia. Hover. |
| `TfNavRow` + `TfSidebar` | `RootView.swift:51-120` | barra 240 de ancho, padding h 16 v 24, fondo `sidebar`, borde derecho `line` 1. Fila: alto 44, h 12, radio 10, icono 18 + hueco 10 + texto body 14 medium; activa: texto/icono `accent` fondo `accentBg`; inactiva: `text2`, sin fondo. Logo «Tone»+«Forge»(`accent`) display 22, `padding(.horizontal, 12).padding(.bottom, 20)` (`RootView.swift:57`). Separación de filas 4. `Spacer` empuja Ajustes + tarjetas al fondo. |
| `TfSelectedTrackCard` | `selectedCard` `RootView.swift:76-90` | padding 12 y `padding(.top, 8)` (`:88`), separación título/artista 2, borde `.clear` cuando no activa, radio 10, fondo `field` (activa `accentBg` + borde `accent`), título `TfMarquee` body 14 semibold, artista body 12 `muted`. |
| `TfDeviceCard` | `deviceCard` `RootView.swift:92-103` | padding 12 y `padding(.top, 8)` (`:102`), separación 6, radio 10, fondo `field`; fila punto+título con separación 8: punto 8×8 `deviceOk` (o `muted` si desconectado) + título body 14 semibold + subtítulo body 12 `muted`. |
| `TfTabBar` | pestañas `SettingsView.swift:17-32` | contenedor `field` radio 10 borde `fieldLine`, padding 3, separación 4; botón alto 44, h 18, radio 8; activo body 14 semibold `accent` en `accentBg`; inactivo medium `text2`. |
| `TfPill` (pastilla de pista, de acción) | `TabScreen.swift:213-225`; `BackingTimeline.swift:122-130` | cápsula alto 34 (h 14) para pistas; botón compacto alto 28, radio 8, h 10 para cabeceras. Pastilla de pista: icono 12, gap 6, body 13 semibold/medium, borde `accent` activo completo; pastilla «pendiente» de trazo discontinuo `dash [3]` (`TabScreen.swift:234-239`). Activo: texto `accent`, fondo `accentBg`; inactivo `text2`/`field`, borde `fieldLine` (activo `accent @0.6` en solos). |
| `TfToggleButton` (M/S) | `MixerToggle` `BackingMixer.swift:257-272`; `trackToggle` `TabScreen.swift:245-253` | Dos tamaños: `MixerToggle` 36×36, radio 8, body 12 bold(→600) (`BackingMixer.swift:265-269`); `trackToggle` de Tablatura 28×28, radio 7, body 11 bold(→600) (`TabScreen.swift:247-251`). Colores iguales. Off: `field`, texto `text2`, borde `fieldLine`; On: `accent`, texto `accentInk`, sin borde. |
| `TfFader` | `Fader` `BackingMixer.swift:281-311` | −60…+6 dB, imán ±1,5 dB a 0 dB, doble clic = 0 dB; carril 6 ancho radio 3 `bg`; pomo 28×18 radio 4 `text2` con sombra `knob`; el hueco útil es de 28 de ancho. Altura base 150, mínima 40. Arrastre sin tolerancia, accesible por incrementos de 1 dB. |
| `TfLevelBar` | `levelBar` `BackingMixer.swift:222-234` | 8 de ancho × alto del fader, radio 4, fondo `bg`; relleno desde abajo de alto `fader·f` (`f = clamp((rmsDB+60)/60, 0, 1)`), radio 4, degradado vertical **relativo al propio relleno, no a la barra**: `ok` hasta el 70 % del relleno, mezcla lineal hasta `accent` en el 92 %, `accent` por encima (`CustomPainter`: shader con `begin/end` sobre el rect del relleno). Nivel 0 si `dim` = canal en mute **o** solo ajeno. |
| `TfInputMeters` | `InputMeters` `AudioSettingsView.swift:66-82` | por canal, 8×28 radio 2, fondo `field`, relleno `ok`, separación 4. |
| `TfMixerChannel` | `MixerChannel` `BackingMixer.swift:143-236` | 96 de ancho × alto variable (276 normal, mín. 166), padding v 12, radio 12, fondo `field`, borde `fieldLine`, atenuado `@0.55` si mute o solo ajeno. Master: fondo `accentBg @0.5`, borde `accent @0.6`. Título alto 22 body 12 semibold. Edición de nombre con `TextField` nativo `roundedBorder`. |
| `TfSettingsGroup` | `SettingsView.swift:50-67` | `TfCard` con padding h 20 v 18, título display 18 medium, nota body 13 `muted`, separación 14/6; la separación 14 también va **entre cada fila del contenido** (el contenido es hijo directo del `VStack(spacing: 14)`, `:56-62`; si llega envuelto en un único contenedor no aplica; confirmar con la captura de referencia, ola 0). |
| `TfInfoRow` | `InfoRow` `SettingsView.swift:69-81` | h 12 v 10, radio 10, fondo `field`, `HStack(spacing: 12)`; etiqueta = `Text(label)` sin fuente propia → Inter 14 regular `text` (heredado, `RootView.swift:26-27`) + `Spacer` + valor según cada llamada (p. ej. body 14 semibold `text2`; el peso semibold sobre fuente heredada: confirmar con la captura de referencia, ola 0). |
| `TfTableHeaderCell` | `headCell` `LibraryView.swift:156-159` | body 12 medium MAYÚSCULAS `letterSpacing 0.7` `muted`. |
| `TfListRow` | `row` `LibraryView.swift:208-254` | padding h 20 v 14, separador `line` (`Divider().overlay(TF.line)`), reposo transparente; hover: `accent @0.07`; seleccionada: `ok @0.12` + franja izquierda 3 `ok`. Columnas 70/150/170. |
| `TfSongCover` | `SongCover` `LibraryView.swift:410-445` | 44×44, radio 8, borde `line`; sin carátula: fondo `field` + `music.note` 18 `muted`. Miniatura 88 px. |
| `TfTextField` | `searchField` `LibraryView.swift:138-150` (ancho fijo 240, separación icono-texto 8); `ArtistGrid.swift:88`; `LinkImportSheet.swift:813`; `TabSourceSheet.swift:145` | `.plain` dentro de contenedor propio: h 12 (campo de enlace h 10), alto 36 (enlace 32), radio 8 (enlace: ver `TabSourceSheet.swift:146`), fondo `field`, borde `fieldLine`. Icono `magnifyingglass` + botón de borrar `xmark.circle.fill` en `muted`. Foco: no se dibuja anillo propio. |
| `TfStateMessage` (estado vacío/aviso) | `emptyLibrary`/`emptyMessage` `LibraryView.swift:~203-205`; `message` `VideoSettingsView.swift:310-316` | icono 18 `muted` + texto body 12 `text2` centrado, separación 6, padding 8; vista previa 16:9 radio 10 borde `fieldLine`. |
| `TfNotice` | aviso descartable `TabScreen.swift:~170-180` | fila con icono `exclamationmark.triangle` (`accent`/`danger`) y botón `xmark` plain. Detalle de medidas por verificar en la pantalla de Tablatura. |
| `TfSheet` | `FirstRunSheet` `RootView.swift:122-137`; `CalibrationSheet`; `SongInfoSheet` `ArtistGrid.swift:133`; `TabSourceSheet`; `LinkImportSheet`; `OffsetSheet`; `MontageFramingSheet`; `AddPartSheet` `RecordView.swift:332` | modal de macOS; fondo `card` en `FirstRunSheet`, `MontageFramingSheet`, `RecordView` (`AddPartSheet`) y `bg` en `CalibrationSheet`; padding real 24 (Tab, Montaje, Offset, LinkImport) o 28 (FirstRun, Calibración); título display 22-24, cuerpo `muted`, botones al pie alineados a la derecha: `Cancelar`/`Repetir` `SecondaryButton` de 44 por defecto (`CalibrationSheet.swift:51,83`) + acción `PrimaryButton`; comprobar la altura en el resto de hojas antes de fijarla en 36. Atajos `Esc`/`Intro`. Anchos: 420, 480 (primer arranque), 540 (calibración), 720, 760. Sin cabecera propia: la hoja de macOS no tiene barra de título. |
| `TfPopover` | `.popover` `MontageView.swift:444,691`; `BackingTimeline.swift:192`; `ChordGrid.swift:251`; `SectionBoxes.swift:101` | popover nativo con flecha (`arrowEdge: .bottom`); contenido propio sobre el fondo del sistema. En Flutter: `OverlayPortal` con fondo `card`, borde `line`, radio 10, sin flecha (Jorge, 24/11/2026). |

### 3.2 Controles nativos de macOS sin personalizar (hay que dibujarlos en Flutter)

Aspecto actual en macOS con tema oscuro forzado y sin `AccentColor` en el catálogo (`App/Resources/Assets.xcassets` solo trae `AppIcon`), así que los controles sin `.tint` usan el **acento del sistema del usuario (azul por defecto)**. Descripción por conocimiento de macOS: validar con captura (pendiente de Jorge).

| Widget Flutter | SwiftUI | Dónde | Cómo se ve hoy |
| --- | --- | --- | --- |
| `TfDropdown<T>` | `Picker(...).pickerStyle(.menu)` | 21 `Picker`: `RecordView.swift:500,509`, `MontageView.swift:288,486`, `AudioSettingsView.swift:117,127`, `TabScreen.swift:299` | botón redondeado gris del sistema con etiqueta y chevrones arriba/abajo a la derecha; al pulsar, menú emergente del sistema. `fixedSize()`: ancho = contenido. Anchos fijos en Ajustes: 320 (salida/entrada), 280, 160. |
| `TfSegmented` | `.pickerStyle(.segmented)` | `LibraryView.swift:133`, `AudioSettingsView.swift:141` (ancho 220), `VideoSettingsView.swift:362` (160) | control segmentado del sistema; segmento activo relleno con el acento del sistema (la web lo imita con `--blue 2F7CF6`, `tokens.css:30`). En Flutter, segmento activo `TF.accent` naranja (Jorge, 24/11/2026). |
| `TfSwitch` | `Toggle` `.switch` (`.controlSize(.small)`, `.tint(TF.accent)`) | `GuitarOptionsViews.swift:21`, `SectionBoxes.swift:321`, `MontageFramingSheet.swift:34`, `VideoSettingsView.swift:375,380` (sin tint ni `.controlSize(.small)`: tamaño normal, `.switch` + `labelsHidden`, acento del sistema; los de `GuitarOptionsViews.swift:21` sí son small + `accent`) | interruptor pequeño de macOS; encendido naranja `accent`; los de `VideoSettingsView`, que hoy salen con el acento del sistema, también van en `TF.accent` naranja (Jorge, 24/11/2026). |
| `TfCheckbox` | `Toggle` `.checkbox` | `RecordView.swift:507,520`, `TabScreen.swift:311,449`, `BackingTimeline.swift:464`, `MontageView.swift:493` (`.tint(accent)`), `OffsetSheet.swift:71` | casilla cuadrada del sistema con marca blanca sobre acento del sistema; con `tint` naranja solo en `MontageView.swift:493`. En Flutter, `TF.accent` naranja en todas (Jorge, 24/11/2026). Etiqueta body 13 `text2`. |
| `TfSlider` | `Slider(...).tint(TF.accent)` | `BackingMixer.swift:92` (150), `TabScreen.swift:441` (120), `BackingTimeline.swift:377` (70) y `:456` (120), `RecordMixer.swift:72` (40), `MontageFramingSheet.swift:41,209`, `MontageView.swift:367`, `TakeViewer.swift:343` (sin tint) | carril delgado con parte izquierda `accent` y pomo circular blanco del sistema. Pasos: velocidad 5 % (`(v/5).rounded()*0.05`), cents 1, dB con imán a 0 (±1,5). |
| `TfStepper` | `Stepper(...).labelsHidden()` | `VideoSettingsView.swift:346` | par ▲▼ del sistema junto al campo de «ms». |
| `TfNumberField` | `TextField(value:format:).textFieldStyle(.roundedBorder)` | `VideoSettingsView.swift:343` (70), `OffsetSheet.swift:58` (76), `BackingMixer.swift:195`, `SectionBoxes.swift:300`, `RecordView.swift:341` | campo con borde redondeado de macOS (oscuro, borde fino gris, foco con halo del acento del sistema). Alto del sistema ≈22 (**medir**). |
| `TfSpinner` | `ProgressView().controlSize(.small/.mini)` | 27 usos, p. ej. `RecordView.swift:17`, `MontageView.swift:737` (`.mini`) | rueda de aspas gris del sistema, 16 px (small) / 10 px (mini). |
| `TfProgress` | `ProgressView(value:).tint(accent)` | `SettingsView.swift:123,142,169`, `LibraryView.swift:177` (ancho 160) | barra lineal del sistema, relleno naranja, alto del sistema (≈4-6); distinta de `TfAccentBar`: `TfProgress` se queda separado (1:1) (Jorge, 24/11/2026). |
| `TfMenu` / `TfContextMenu` | `Menu {}` y `.contextMenu` | `RecordView.swift:273`, `TabScreen.swift:152,458`, `BackingTimeline.swift:198,348`, `LibraryView.swift:245`, `PlaylistImport.swift:393` | menú nativo oscuro de macOS con `Divider`. En Flutter se dibuja con `MenuAnchor` o `OverlayPortal`, fondo `card`, radio 10, aspecto propio (Jorge, 24/11/2026). |
| `TfDivider` | `Divider().overlay(TF.line)` / `Divider()` | 21 usos; con color en `LibraryView.swift:173`; el resto sin color (`MontageView.swift:709`, `BackingMixer.swift:96`: vertical alto 28) | 1 px, color `line` o del sistema (gris translúcido). |
| `TfAlert` / `TfConfirmDialog` | `.alert` / `confirmationDialog` | `RootView.swift:35,38`; `SettingsView.swift:91,100`; `TakeViewer.swift:295` (+5 más) | alerta nativa modal con título, mensaje y botones; la de confirmación es hoja con botón destructivo rojo. Texto con `Text(...)`. |
| `TfTooltip` | `.help("…")` | 46 usos, p. ej. `ArtistGrid.swift:120`, `RecordView.swift:449` | etiqueta emergente del sistema tras ~1 s. Flutter: `Tooltip` con tokens. |
| `TfScroll` | `ScrollView` | todas las pantallas | barras superpuestas del sistema; Flutter: `Scrollbar` fina con `fieldLine`/`muted` (Jorge, 24/11/2026). |

Resto del trabajo sin widget propio: arrastrar y soltar (`RootView.swift:28` ficheros; `MontageView.swift:762` carriles) → `desktop_drop` y `Draggable`; `Canvas` (`ChordDiagram.swift:14`, líneas de tiempo, tira de acordes) → `CustomPainter` (regla 7).

## 4. Iconos

SF Symbols **no es redistribuible fuera de las plataformas de Apple** (licencia de Apple). La web (`WinApp/Web/icons.js`) usa SVG de trazo 24×24, `stroke-width 2`, extremos y uniones redondos, `currentColor`. Resolución (Jorge, 24/11/2026): `TfIcons` (`theme/icons.dart`) porta los `path` de Lucide (licencia ISC, mismo estilo de trazo) como `Path`, sin plugin, con la licencia en `assets/licenses/`; los que Lucide no tenga se dibujan con el mismo trazo. Todos de trazo, no rellenos. La columna «Icono web» de la tabla indica el equivalente de `icons.js` y sirve de guía del estilo.

| Símbolo SF | Usos | Ejemplo | Icono web | Nota |
| --- | --- | --- | --- | --- |
| `music.note.list` | 1 | `RootView.swift:58` | `library` | |
| `slider.vertical.3` | 1 | `RootView.swift:59` | `backing` | |
| `music.quarternote.3` | 2 | `RootView.swift:60` | `tab` | |
| `record.circle` | 1 | `RootView.swift:61` | `record` | |
| `film` | 1 | `RootView.swift:62` | `montage` | |
| `gearshape` | 1 | `RootView.swift:64` | `settings` | |
| `magnifyingglass` | 1 | `LibraryView.swift:140` | `search` | |
| `xmark` | 3 | `TakeViewer.swift:311` | `close` | |
| `trash` | 2 | `TabScreen.swift:405` | `trash` | |
| `folder` | 1 | `LibraryView.swift:222` | `folder` | |
| `pencil` | 3 | `BackingTimeline.swift:70` | `pencil` | |
| `chevron.left` | 3 | `LibraryView.swift:92` | `chevronLeft` | |
| `chevron.down` | 1 | `BackingTimeline.swift:107` | `chevronDown` | |
| `checkmark.circle` | 1 | `LibraryView.swift:117` | `check` | |
| `info.circle` | 2 | `MontageView.swift:442` | `info` | |
| `exclamationmark.triangle` | 2 | `TabSourceSheet.swift:229` | `warning` | |
| `arrow.up.right.square` | 1 | `LinkImportSheet.swift:726` | `external` | |
| `play.fill` | 7 | `TabScreen.swift:429` | `play` | |
| `arrow.uturn.backward` | 1 | `TabScreen.swift:390` | `undo` | |
| `arrow.uturn.forward` | 1 | `TabScreen.swift:392` | `redo` | |
| `plus` | 2 | `TabScreen.swift:400` | `plus` | |
| `minus` | 1 | `TabScreen.swift:401` | `minus` | |
| `arrow.up.arrow.down` | 1 | `ArtistGrid.swift:113` | `swap` | |
| `person.fill` | 1 | `ArtistGrid.swift:47` | `person` | |
| `music.note` | 3 | `LibraryView.swift:434` | `music` | |
| `xmark.circle.fill` | 1 | `LibraryView.swift:143` | aprox. `close` | falta variante en círculo relleno |
| `checkmark.circle.fill` | 3 | `MontageView.swift:182` | aprox. `check` | falta variante rellena |
| `exclamationmark.triangle.fill` | 3 | `GuitarOptionsViews.swift:69` | aprox. `warning` | falta variante rellena |
| `chevron.right` | 1 | `SectionBoxes.swift:375` | **sin** (espejo de `chevronLeft`) | derivable |
| `chevron.up` | 1 | `BackingTimeline.swift:107` | **sin** (espejo de `chevronDown`) | derivable |
| `chevron.up.chevron.down` | 1 | `PlaylistImport.swift:423` | **sin** | indicador de menú |
| `checkmark` | 1 | `MontageView.swift:719` | **sin** (la de la web va en círculo) | |
| `checkmark.square.fill`, `square` | 1+1 | `PlaylistImport.swift:317` | **sin** | casilla propia de lista |
| `circle`, `largecircle.fill.circle` | 2+2 | `TabSourceSheet.swift:122`, `LinkImportSheet.swift:698` | **sin** | radio propio |
| `pencil.circle.fill` | 1 | `BackingTimeline.swift:70` | **sin** | |
| `pause.fill` | 4 | `TabScreen.swift:429` | **sin** | |
| `playpause.fill` | 1 | `OffsetSheet.swift:48` | **sin** | |
| `backward.end.fill` | 2 | `TabScreen.swift:422` | **sin** | |
| `repeat` | 1 | `SectionBoxes.swift:327` | **sin** | |
| `arrow.left`, `arrow.right` | 1+2 | `TabSourceSheet.swift:278,264` | **sin** | |
| `video` | 2 | `RecordView.swift:411` | **sin** | |
| `camera.fill` | 1 | `VideoSettingsView.swift:296` | **sin** | |
| `lock.fill` | 1 | `VideoSettingsView.swift:300` | **sin** | |
| `rotate.right` | 2 | `MontageView.swift:748` | **sin** | |
| `line.3.horizontal` | 1 | `MontageView.swift:730` | **sin** | asa de arrastre |
| `guitars`, `guitars.fill` | 1+2 | `TabScreen.swift:287`, `BackingTimeline.swift:101` | **sin** | |
| `waveform` | 1 | `TabScreen.swift:288` | **sin** | |
| `mic` | 1 | `TabScreen.swift:290` | **sin** | |
| `circle.grid.2x2` | 1 | `TabScreen.swift:289` | **sin** | |
| `speaker.wave.2.fill`, `speaker.slash.fill` | 2+1 | `TakeViewer.swift:348` | **sin** | |
| `rectangle.dashed` | 1 | `BackingTimeline.swift:100` | **sin** | |

Resumen: 56 símbolos distintos; 25 con equivalente exacto, 3 con aproximación (variante rellena), **28 sin equivalente en la web** (de ellos 2 derivables por espejo); se toman de Lucide o se dibujan con el mismo trazo. Los SF usados son en su mayoría rellenos (`.fill`), pero en Flutter todos van de trazo (Jorge, 24/11/2026).

## 5. Fuentes y recursos

`App/Resources/Fonts/` (cargadas con `ATSApplicationFontsPath=Fonts`, `App/Sources/Info.plist`):

| Fichero | Familia / estilo | PostScript | Peso | Licencia |
| --- | --- | --- | --- | --- |
| `inter-latin-400.ttf` | Inter Regular | `Inter-Regular` | 400 | SIL OFL 1.1 (`LICENSE-Inter.txt`) |
| `inter-latin-500.ttf` | Inter Medium | `Inter-Medium` | 500 | ídem |
| `inter-latin-600.ttf` | Inter SemiBold | `Inter-SemiBold` | 600 | ídem |
| `space-grotesk-latin-500.ttf` | «Space Grotesk Light» Medium | `SpaceGroteskLight-Medium` | 500 | SIL OFL 1.1 (`LICENSE-SpaceGrotesk.txt`) |
| `space-grotesk-latin-700.ttf` | «Space Grotesk Light» Bold | `SpaceGroteskLight-Bold` | 700 | ídem |

Medido con `fc-scan`: son estáticas (no variables) y solo subconjunto latino. En Flutter la familia del `pubspec` es libre (`Inter`, `SpaceGrotesk`) y el nombre PostScript no importa; en el ZIP de Windows basta con empaquetarlas como assets. La web usa `fonts/*.woff2` de los mismos nombres (`tokens.css:6-10`). Las licencias OFL exigen incluir el texto (`LICENSE-*.txt`) en el paquete.

Otros recursos que la interfaz carga (`App/Resources`): `AppIcon.svg` (fuente) y `Assets.xcassets/AppIcon.appiconset/icon_{16,32,64,128,256,512,1024}.png` (regenerados con `Tools/make-icon.sh`; yunque «TF» en dos tonos: degradado oscuro `262B31→0F1113` y ámbar `FFC170→EE9624`); `alphaTab/` (`alphaTab.min.js`, `tab.html`, `tf-bridge.js`, `font/Bravura.woff2` + `Bravura-OFL.txt`, `soundfont/sonivox.sf2` + `LICENSE`, `LICENSE-alphaTab-MPL-2.0.txt`); `Models/` (4 `.mlpackage.zip`, solo Mac; no son de interfaz). Sin `AccentColor`, sin imágenes de interfaz: todos los iconos son SF Symbols. Carátulas y fotos de artista se leen del proyecto (`source/cover.jpg`).

## 6. Ventana

- Mínimo 1100×680 (`WindowMetrics`, `ToneForgeApp.swift:5-8,30`; mínimos en :6-7, aplicados en :30); inicial 1440×900 (`.defaultSize`, `ToneForgeApp.swift:41`). Tamaño restaurado por el sistema (`SceneStorage`).
- Tema oscuro forzado: `.preferredColorScheme(.dark)` (`ToneForgeApp.swift:29`); no hay tema claro. Dart: un solo `ThemeData(brightness: dark)`.
- Barra lateral: ancho fijo 240 (`RootView.swift:12`), siempre visible, sin colapsar ni arrastrar. Contenido a la derecha en `maxWidth/maxHeight: .infinity`. Mínimo de contenido = 1100−240 = 860.
- Barra de título estándar del sistema; sin barra de herramientas. Sin multiventana efectiva (`WindowGroup` único).
- Zona de soltar ficheros: toda la ventana (`RootView.swift:28`, `importFiles`).
- Altura baja: el mezclador adapta su altura (`mixerChannelHeight`, mínimo 166).
- Web (`tokens.css`): `--sidebar-w 240` igual.

## 7. Partes de trabajo sugeridas (ola de cimientos)

**Haiku (mecánico, un solo patrón):**
1. `theme/tokens.dart`: `TfColors` (§1.1 + §2.1), `TfRadius`, `TfSpace`, `TfStroke`, `TfOpacity`, `TfShadow`, `TfSize`. Tabla → constantes; test que compara cada hex con el de `Theme.swift`.
2. `theme/typography.dart`: `TfText.display/body`, `TfWeight`, `pubspec.yaml` con las 5 fuentes y licencias en `assets/licenses/`.
3. `theme/fmt.dart` (`TfFmt`, §1.3) con pruebas contra las funciones de `Fmt` (tabla de casos).
4. `theme/icons.dart`: portar los `path` de Lucide (ISC, licencia en `assets/licenses/`) a `Path` y un test de goldens por icono (§4) (Jorge, 24/11/2026).
5. Test que falla si aparece un literal `Color(0x…)`, `fontSize:`, `BorderRadius.circular(` o `EdgeInsets` numérico en `lib/` fuera de `theme/` (regla 4).

**Sonnet (decisiones de forma, estados, gestos):**
1. Botones y chip: `TfPrimaryButton`, `TfSecondaryButton`, `TfIconButton`, `TfChip`, `TfCard`, `TfAccentBar` (animación sin valor), con goldens por estado.
2. `TfTextField`, `TfNumberField`, `TfDropdown`, `TfSegmented`, `TfSwitch`, `TfCheckbox`, `TfSlider`, `TfStepper`: dibujados desde cero, con foco y teclado (§3.2).
3. `TfFader`, `TfLevelBar`, `TfInputMeters`, `TfMixerChannel` (`CustomPainter`, gestos, doble clic, imán).
4. `TfSheet`, `TfPopover`, `TfMenu`, `TfAlert`, `TfTooltip`, `TfMarquee`, `TfScroll`: capas, foco, `Esc`/`Intro`.
5. `TfSidebar`, `TfNavRow`, `TfTabBar`, `TfListRow`, `TfSettingsGroup`, `TfInfoRow`, `TfStateMessage`, `TfNotice`.
6. Iconos que Lucide no tenga (§4): se dibujan con el mismo trazo (Jorge, 24/11/2026).

## Pendientes de Jorge

- Aspecto de los controles nativos: se fija con las capturas de referencia de la ola 0.
