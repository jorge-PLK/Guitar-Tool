# Ficha de pantalla · Montaje

Ola: por asignar. Área del puente: `montage`. Destino: `FlutterApp/lib/features/montage/`.

Abreviaturas (todo en `App/Sources/`): MV = `MontageView.swift`, FS = `MontageFramingSheet.swift`, MC = `MontageController.swift`, MP = `MontagePlanning.swift`. AppCore (`AC/`) = `Packages/AppCore/Sources/AppCore/`. Tokens y kit: `docs/flutter/tokens-componentes.md` (TC); aquí solo se citan.

Contrato (apartados 5, 8 y 9): ver `montaje-contrato.md`. Tipos completos de `montage.*`: `docs/flutter/contrato-tipos-c.md` (sección `montage`), no se repiten.

## 1. Qué es

Montaje compone el vídeo final de un tema: elige la mejor toma de cada parte, la coloca en un layout (lado a lado, rejilla, apilado, plano único con cortes), muestra una vista previa sincronizada con el audio de la mezcla, deja ajustar el encuadre de cada toma y exporta MOV/MP4 (HEVC o H.264) con audio normalizado a −14 LUFS y −1 dBTP. Se llega desde la barra lateral (sección Montaje) o desde Biblioteca con un tema; sin tema elegido sale la lista de temas con tomas (MV:30-45).

## 2. Referencia visual (SwiftUI)

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Selector de tema (sin tema) | MV:30-45 | Título «Montaje» `TF.display(30)`; filas `TF.field` r10, padding 12x10; vacío en `TF.muted`; padding de pantalla 40x32 |
| Cuerpo | MV:85-123 | Padding 36x20. Tres columnas: izq. 270 (252 si ancho < 900), centro flexible, der. 300 (276 compact). Altura mínima de las columnas 420 (`previewMinHeight`); máxima 440 si el lienzo es vertical (`portraitMax`). Espaciado 14 |
| Cabecera | MV:130-160 | Subtítulo «artista · tema · N tomas» `TF.body(13)` muted; «Montaje» `TF.display(26)`; botón «Exportar vídeo» (`PrimaryButton`) o «Cancelar exportación» (`SecondaryButton`); líneas de aviso `TF.body(12)` (accent / danger) |
| Banda de exportación | MV:168-215 | En curso: `TF.field` r10, padding 14x10, texto `body(13, medium)` + `AccentBar` (máx. 320) + porcentaje monoespaciado. Hecho: `TF.okBg` r10, icono `checkmark.circle.fill` `TF.ok`, ruta con truncado central, botón «Mostrar en Finder» (MV:185, `SecondaryButton(height: 32)`). Fallo: `TF.dangerBg` r10 con texto `TF.danger` |
| Sin tomas con vídeo | MV:225-236 | `display(18)` + texto muted; padding 20 |
| Columna Layout | MV:241-295 | «Layout» `display(18)`; botón por layout: min. alto 52, padding 8x6, r12, relleno `TF.accentBg`/`TF.field`, borde `TF.accent`/`TF.fieldLine`; nombre `body(14, semibold)`, descripción `body(11)` muted. Miniatura (MV:297-317): losetas r3 color `0x5A636C` (suelto, fuera de `TF`), hueco 3, tamaños 56x30 (horizontal) o 24x40 (vertical), padding 4, fondo `TF.bg` r6, ancho 64. Picker «Rítmica del plano único» (MV:287) |
| Columna Vista previa | MV:323-376 | Cabecera «Vista previa · {lienzo}» y «{tiempo} · {sección}»; superficie con aspecto 9/16 o 16/9, fondo `0x0B0C0E` (suelto) r14, borde `TF.fieldLine`; botón play círculo 44 `TF.accent` con icono `TF.accentInk`; `Slider` tint accent en el rango de la canción (deshabilitado si la vista previa no está lista); tiempo `body(13)` monoespaciado «mm:ss / mm:ss». Padding 20x16 |
| Columna Exportación | MV:406-497 | «Exportación» `display(18)` + botón info (popover «Transiciones», ancho 340, padding 14, `display(16)`, filas clave/valor); pickers de menú: Formato (HEVC/H.264), Contenedor (MOV/MP4), Resolución, FPS (`CameraChoices`); casillas (`.checkbox`): recortar huecos, título, etiquetas de parte, conservar aspecto (deshabilitada con ayuda «Solo en apilado y plano único»). Padding 18x16 |
| Línea de tiempo | MV:499-600 | Eje con margen 10 % (mín. `barDuration`); etiquetas de 270 de ancho; carril 30, sección 24, banda 8, separación 6; carril: fondo `TF.field` r6; barra llena r4 con color de parte, contorno discontinuo = grabado, rayado = huecos cortados (`TF.bg` 0,6/0,7); cursor `TF.text` 2 px; colores de parte `5BC0EB F2A33A 6FD99E C97F9E 5DB5B5` y solista `B79CFF` (sueltos, en la línea de tiempo) |
| Carril «Plano» y cortes | MV:605-725 | Botón «Añadir corte» `body(12, medium)` r8, alto 26; marca de corte 8 px de ancho r2 (`TF.text` si cubierto, `TF.accent` si no); menú del corte (min. 190, padding 12): «Desde {t} manda», lista de partes con check, «Eliminar corte» en `TF.danger` (MV:710) |
| Leyenda | MV:590-596 | Texto `body(12)` muted + enlace subrayado |

## 3. Árbol de widgets propuesto

- `MontageScreen` (selector de tema si no hay) → MV:7-47
  - `MontageHeader` → MV:130-160; botones primario y secundario del kit
  - `MontageExportBanner` (barra de acento del kit) → MV:168-215
  - `MontageBody` (`LayoutBuilder`: compact < 900) → MV:85-123
    - `MontageLayoutColumn` → `LayoutThumb` (**CustomPainter** o `Container` de losetas), picker de rítmica
    - `MontagePreviewColumn` → **`TfVideoSurface`** (widget `Texture` alimentado por el núcleo, canal `montage`; ADR-021 enmendado), botón play 44, `Slider`
    - `MontageSettingsColumn` → pickers de menú, casillas, popover `Transiciones`
  - `MontageTimeline` (**CustomPainter** para eje, barras, huecos y cursor; gestos encima) → MV:499-725
    - `MontageCutMenu` (popover)
  - `MontageFramingSheet` (hoja) → apartado 7; `FramingBoxPainter` (**CustomPainter**: máscara y caja)

## 4. Estados

| Estado | Qué cambia | Dato del núcleo |
| --- | --- | --- |
| Sin tema elegido | Lista de temas con tomas, o texto «Aún no hay temas…» | `library` (temas con vídeo) |
| Cargando | `ProgressView` centrado (MV:17, 60) | `montage.open` en curso |
| Sin tomas con vídeo | Tarjeta MV:225-236; Exportar deshabilitado | `MontageSnapshot` sin carriles con toma (`hasVideo`) |
| Análisis de encuadre | «Exportar» deshabilitado con ayuda «Espera a que termine el análisis del encuadre» | `isAnalyzing` ← `montage.framing` (`analyzing`) |
| Vista previa `none/preparing/ready/error` | `preparing`: vídeo vacío, play y slider deshabilitados; `error`: línea danger con el texto (MV:158) | `preview.phase`, `preview.error` (MC:49) |
| Audio `none/preparing/ready/silent/error` | `silent`: reproduce sin audio; `error`: `audioError` (ninguna vista SwiftUI lo muestra; desvío D5) | `preview.audio.phase`, `transport.audioError` |
| Reproduciendo / pausa | Icono del botón, cursor, tiempo | `montage.position` 30 Hz (`playing`) |
| Exportando | Banda con etapa «Mezclando el audio…»/«Codificando el vídeo…» y %; botón «Cancelar exportación» | `export.phase = running`, `progress`, `stage` |
| Exportado | Banda `okBg`, ruta, LUFS/dBTP, avisos de limitador, ficheros recortados, WAV por pista | `exportStatus.result` |
| Fallo | Banda `dangerBg` | `phase = failed`, `message` |
| Cancelado | AppCore emite `cancelled`; SwiftUI vuelve a `idle` (D1) | `phase` |
| Variantes de layout | Conservar aspecto solo en apilado y plano único; carril «Plano» solo en plano único; en Windows solo H.264 | `keepAspectApplies`, `export.options.codecs` |
| Carril sin toma | Etiqueta «Sin toma» | lane sin `hasVideo` |

## 6. Interacción

- Sin atajos de teclado ni `NSEvent`/`.keyboardShortcut` (grep sin resultados en MV y FS; no se buscó en el resto de `App/`).
- Línea de tiempo: `DragGesture(minimumDistance: 0)` sobre el área de carriles (MV:582) para fijar la posición. En el carril «Plano»: clic en un hueco añade un corte en ese instante y abre su menú (MV:657-659); botón «Añadir corte» lo crea en la posición de la vista previa (MV:613); clic en una marca abre su menú (MV:682); arrastre de la marca con umbral de 4 px la mueve (MV:683-689); «Eliminar corte» (MV:710).
- Reordenar carriles: `.onDrag` / `.onDrop` con `LaneDropDelegate` sobre las etiquetas de parte (MV:762-767) → `moveLane`. Flutter: `Draggable`/`DragTarget` o `ReorderableListView` equivalente.
- Vista previa: botón play y `Slider` de posición (MV:360-368). En la Web `seek` se limita a un envío cada `SCRUB_INTERVAL_MS` = 120 ms más el valor final (`WinApp/Web/montage/store.js:11,160-168`); la interfaz nueva debe limitar igual.
- Hoja Encuadre: `DragGesture(minimumDistance: 0)` sobre el fotograma: arrastre mueve la caja o, si empieza en el punto de la esquina (círculo 14), la escala; en modo «seguir» desplaza el recorte (FS:137-176).
- Popover «Transiciones» (MV:444) y menú del corte: popovers anclados abajo; en Flutter `OverlayPortal`/`MenuAnchor` del kit.
- Foco: sin gestión explícita.

## 7. Hojas y popovers

### Hoja «Encuadre» (FS)
- **Visual** (FS:54): ancho 760, padding 24, fondo `TF.card`; título «Encuadre · {parte}» `display(20)`; fotograma con altura máx. 400 y aspecto del PNG (por defecto 16/9); máscara negra 0,5 con relleno par-impar fuera de la caja; caja con trazo `TF.accent` 2; punto de escala círculo 14 (solo modo fijo); sin imagen: «Sin imagen en este instante».
- **Controles:** Toggle «Seguir la guitarra»; slider «Instante» (rango de la toma, valor `body(13)` ancho 44); modo fijo: texto de ayuda y deslizadores (título de 130 de ancho, valor de 56); modo seguir: zoom 0,5...3 y desplazamiento −0,5...0,5. Botones «Restablecer», «Reanalizar» (`SecondaryButton`), «Hecho» (`PrimaryButton`). Lado mínimo de caja 0,05; debounce de 80 ms al pedir el fotograma; instante inicial = mitad de la primera presencia o, si no hay, de la toma.
- **Estados:** analizando (`montage.framing`), sin imagen (`no-frame`), caja automática frente a manual (`manualBox == nil`).
- **Contrato:** `montage.framingFrame` devuelve la **ruta de un PNG** (lado mayor 1280, `AC/MontageController.swift:829-853`) y la caja efectiva; Flutter lo abre con `Image.file` (ruta relativa a la carpeta del tema). `setFraming`, `resetFraming`, `reanalyze`. Detalle en `montaje-contrato.md`.

### Popover «Transiciones» (MV:420-435)
Ancho 340, padding 14; lista de pares nombre/valor, solo lectura.

### Menú del corte (MV:695-725)
Ver apartado 2; una parte sin toma en ese instante queda deshabilitada con ayuda «Sin toma en {t}» (MV:706).

## 10. Partes de trabajo sugeridas

| Parte | Ficheros Dart | Tamaño | Agente |
| --- | --- | --- | --- |
| P1 Store y DTO | `montage_store.dart`, `montage_models.dart` (según `contrato-tipos-c.md`) | M | `tf-flutter` |
| P2 Superficie de vídeo | `tf_video_surface.dart` (`Texture` + canal `montage`, PTS en ms) | M | `tf-flutter` |
| P3 Cabecera, columnas Layout y Exportación, banda | `montage_screen.dart`, `montage_header.dart`, `montage_layout_column.dart`, `montage_settings_column.dart`, `montage_export_banner.dart` | M | `tf-flutter` |
| P4 Línea de tiempo y cortes | `montage_timeline.dart`, `montage_timeline_painter.dart`, `montage_cut_menu.dart` | L | `tf-flutter` |
| P5 Hoja Encuadre | `montage_framing_sheet.dart`, `framing_box_painter.dart` | M | `tf-flutter` |
| P6 Textos ARB y mocks | `app_es.arb` (claves `montage*`), fixtures | S | `tf-flutter-mech` |

P2 y P4 no comparten ficheros; P3 y P5 dependen de P1.

## 11. Criterios de aceptación

- Capturas a igualar (nombres propuestos): `montaje-sin-tema`, `montaje-listo`, `montaje-compact`, `montaje-vertical`, `montaje-exportando`, `montaje-exportado`, `montaje-fallo`, `montaje-sin-tomas`, `montaje-encuadre-fijo`, `montaje-encuadre-seguir`, `montaje-corte-menu`.
- Tests de store: abrir tema y mapear `MontageSnapshot`; `montage.position` actualiza el cursor sin reconstruir el snapshot; `cancelled` se muestra como `idle` (D1); `framingFrame` abre la ruta devuelta; el seek se limita a `span` y a un envío cada 120 ms.
- Tests de widgets: «Exportar» deshabilitado con análisis en curso; conservar aspecto deshabilitado fuera de apilado/plano único; fila Formato oculta si solo hay un códec; layout compact < 900.
- Para Jorge (hardware o criterio de vista/oído): sincronía audio-vídeo de la vista previa (tolerancia 1 fotograma, spec), aspecto de la vista previa a 15 fps frente a `AVPlayer`, exportación real con −14 LUFS, arrastre en la línea de tiempo con ratón y trackpad, `framingFrame` con vídeo real en el Mac (M1).
