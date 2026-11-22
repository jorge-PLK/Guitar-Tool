# Ficha de pantalla · Biblioteca

Ola: por asignar. Área del puente: `library` (+ `import`, `jobs`, `link`, `playlist`, `host.pick*`). Destino: `FlutterApp/lib/features/library/`.

Abreviaturas de evidencia (todo en `App/Sources/`): LV = `LibraryView.swift`, RV = `RootView.swift`, AG = `ArtistGrid.swift`, PR = `ProjectRecordingsView.swift`, LS = `LinkImportSheet.swift`, PI = `PlaylistImport.swift`, AM = `AppModel.swift`. Tokens: nombres de `docs/flutter/tokens-componentes.md` (TF.* y `Tf…`); aquí no se redefinen.

## 1. Qué es

Pantalla de inicio de la app: lista de los temas (proyectos) de la carpeta de proyectos, con búsqueda, vista «Temas» (tabla) o «Artistas» (cuadrícula de recuadros), importación (fichero, enlace de YouTube/Spotify, lista) y estado de la separación en stems. Se llega desde la barra lateral («Biblioteca», RV:58, que además cierra la página de detalle) y al arrancar. Pulsar una fila selecciona el tema para Backing/Tablatura/Grabar; el lápiz corrige título y artista; la papelera lo elimina.

Incluye la página de detalle de un tema (`ProjectDetailView`, LV:267-386, con la lista «Grabaciones» de `ProjectRecordingsView`, PR:8-129), la hoja de importación (`LinkImportSheet`, LS:446-830, y `PlaylistImportView`, PI), la hoja de corrección (`SongInfoSheet`, AG:133-167) y la hoja de primer arranque (`FirstRunSheet`, RV:122-137). El visor de tomas (`TakeViewer`) no entra aquí: es de Montaje/Grabar.

## 2. Referencia visual (SwiftUI)

| Elemento | Fichero:línea | Notas de composición |
| --- | --- | --- |
| Marco de la lista | LV:52-63 | `VStack(.leading, spacing: 24)`: cabecera + (cuadrícula o tabla); `padding(.horizontal, 40).padding(.vertical, 32)`. La tabla va en `ScrollView`; la cuadrícula en otro. |
| Barra lateral (compartida) | RV:51-120 | `TfSidebar`/`TfNavRow` del kit (ancho 240, filas 44). Ya documentada en tokens §3.1; aquí solo cambia `section`/`detail` (RV:58). |
| Tarjeta «tema seleccionado» | RV:76-90 | `TfSelectedTrackCard` del kit; activa si la página de detalle de ese tema está abierta. Pulsar = abrir detalle. Tooltip «Abrir la página del tema». |
| Tarjeta de dispositivo | RV:92-103 | `TfDeviceCard`; punto 8×8 de color suelto `Color(hex: 0x4CC38A)` en RV:95 = `TfColors.deviceOk`. Su origen de datos es de Ajustes (ver ajustes.md §9). |
| Cabecera | LV:107-136 | `HStack(.center)`: bloque título (spacing 6) + `Spacer` + [indicador de lista] + buscador + segmentado + botón. Título «Biblioteca» `TF.display(32)`; subtítulo «Tus temas.» `TF.muted`. Separaciones a la derecha: indicador 8, buscador 8, segmentado 8. |
| Indicador de importación de lista | LV:114-127 | Cápsula alto 36, `padding(.horizontal, 12)`, fondo `TF.accentBg`, texto `TF.body(13,.medium)` `TF.accent`; delante `ProgressView` pequeño (en curso) o `checkmark.circle`. Pulsar reabre la hoja de importación. Tooltip «Ver la importación de la lista». Solo aparece si `indicator != nil` (PI:91-103). |
| Buscador | LV:138-150 | `TfTextField`: 240×36, `padding(.horizontal, 12)`, radio 8, fondo `TF.field`, borde `TF.fieldLine`, icono `magnifyingglass` `TF.muted`, botón `xmark.circle.fill` si hay texto. No se persiste (LV:10). |
| Selector de vista | LV:129-133 | `TfSegmented` («Temas», «Artistas»), `fixedSize`, persistido en `@AppStorage("libraryGrouping")` (LV:9). |
| Botón «Importar tema» | LV:134 | `TfPrimaryButton` (alto 44). |
| Tabla | LV:161-189 | `TfCard` (radio 14) con cabecera + filas separadas por `TfDivider` color `TF.line`. Columnas fijas `takes 70 / state 150 / actions 170` (LV:152-154); la primera ocupa el resto. |
| Cabecera de tabla | LV:156-170 | `TfTableHeaderCell` (12 medium MAYÚSCULAS, tracking 0,7, `TF.muted`), `padding(.horizontal, 20).padding(.vertical, 14)`. La cuarta columna es un hueco de 170. |
| Fila de importación en curso | LV:172-181 | Antes de las filas: nombre `TF.body(14,.semibold)`, `Spacer`, barra de progreso 160 de ancho tinte `TF.accent` (`ProgressView(value:)`, es la `TfProgress` del kit), `Chip` working «Importando N %»; `padding h20 v16`. Es lo que ve el usuario al soltar un fichero. |
| Fila de tema | LV:208-254 | `TfListRow`: `padding h20 v14`; portada `TfSongCover` 44×44 radio 8 (LV:414-415, 438-439) + título `TF.body(14,.semibold)` + artista `TF.body(13)` `TF.muted` (spacing 2, hueco 14; el artista se oculta dentro de la vista de un artista, LV:203,214); tomas `TF.text2` o «—»; `Chip` de estado; tres botones 36×36 (carpeta y lápiz = `TfSecondaryButton(height: 36)`, papelera = `TfIconButton` rojo al pasar el ratón, LV:389-405) con `spacing: 8`. |
| Fondos de fila | LV:235-239 | Seleccionada (`backingTarget == id`): `TF.ok @0.12` + franja izquierda de 3 `TF.ok`; hover: `TF.accent @0.07`; la selección manda sobre el hover. Toda la fila es pulsable (`onTapGesture` → `select`, LV:244). |
| Chip de estado | LV:256-264 | `TfChip`: `queued` neutral «En cola»; `running` working «Separando N %»; `done` ok «Separado»; `failed` error «Error» (tooltip = motivo o «Error desconocido»); resto neutral «Importado». |
| Menú contextual de fila | LV:245-253 | Ver apartado 6. |
| Estado vacío | LV:99-105 | `TfStateMessage` ampliado: título `TF.body(15,.semibold)` + texto `TF.muted`, `spacing: 6`, `padding(.vertical, 48)`. En la tabla va tras un `Divider`; en la cuadrícula dentro de `Card`. |
| Sin resultados | LV:65-68 | Texto `TF.muted` centrado, `padding(.vertical, 32)`. |
| Barra del artista abierto | LV:88-97 | `HStack(spacing: 14)`: botón «‹ Artistas» `TF.accent` (sin fondo) + nombre `TF.display(22)` («Sin artista» si vacío). |
| Cuadrícula de artistas | LV:18, 77-85 | `LazyVGrid` adaptativa mínimo 160, máximo 220, `spacing` horizontal 20, vertical 24, `padding(.bottom, 8)`. |
| `ArtistTile` | AG:17-34 | Columna `spacing: 8`: cuadrado 1:1 radio 14, borde `TF.line` (hover `TF.accent @0.6`); nombre `TF.body(14,.semibold)` una línea, cola `…`; «N temas» `TF.body(12)` `TF.muted`. |
| Portada del recuadro | AG:36-50 | Foto del artista (cubre); si no hay: color de `TfColors.artistAvatar(name)` (FNV-1a, matiz `h%360/360`, sat 0,45, brillo 0,5, AG:70-75) + iniciales `TF.display(34)` blanco @0,9 (máx. 2 letras, `?` si vacío, AG:64-68). Sin nombre («Sin artista»): fondo `TF.field` + `person.fill` 40 `TF.muted`. |
| Detalle: marco | LV:312-366 | `ScrollView` > `VStack(.leading, spacing: 24)`, `padding h40 v32`. |
| Detalle: volver | LV:316-317 | «‹ Biblioteca» `TF.accent`, sin fondo. |
| Detalle: título | LV:286-310 | Título `TF.display(32)` + lápiz `TF.muted` (spacing 10); artista `TF.muted`. En edición: `SongInfoFields` (ancho máx. 480) + «Guardar» (Primary, deshabilitado con título vacío) y «Cancelar» (Secondary 36, `Esc`), spacing 10. |
| Detalle: datos | LV:319-326, 382-385 | `TfCard`; tres filas `padding h20 v10`, etiqueta `TF.muted`, valor semibold; `padding(.vertical, 6)`. «Frecuencia» (`Fmt.rate`), «Duración» (`Fmt.duration`), «Estado». |
| Detalle: Stems | LV:327-344 | `TfCard`, `padding h20 v18`, título `TF.display(18)`, `spacing: 10`; cada stem: nombre del tipo (`kind.rawValue`) + tamaño `Fmt.bytes` o «vacío» (`TF.muted`), `padding h12 v10`, fondo `TF.field`, radio 10. |
| Detalle: Grabaciones | PR:26-80; LV:345-349 | `TfCard` `padding h20 v18`; título `TF.display(18)`, `spacing: 12`. Una caja por parte: `padding h14 v12`, radio 12, fondo `TF.field`, borde `TF.fieldLine`, nombre `TF.body(14,.semibold)`, `spacing: 8`. Fila de toma: `HStack(spacing: 12)`: «Toma N» `TF.body(13,.semibold)` ancho 64 (`TF.ok` si es la mejor, `TF.text2` si no) + «★» `TF.ok` + fecha corta `TF.body(12)` muted + duración monoespaciada (`Fmt.clock`, «–» sin dato) + «Con vídeo»/«Sin vídeo» + «1 punch»/«N punches» + `Spacer` + «Ver toma» (▶, Secondary alto 32, deshabilitado sin `processedFile` o `songStart`) + «Eliminar» (Secondary 32). Error en línea `TF.body(12)` `TF.danger`. |
| Detalle: acciones | LV:350-361 | `HStack(spacing: 10)`: «Abrir en Backing track» (Primary, solo si separación `done`), «Mostrar en Finder» (Secondary), `Spacer`, «Eliminar…» texto plano `TF.muted`. |
| Hoja «Importar tema» (vacía) | LS:451-499, 449-475 | `TfSheet` ancho 620, `padding(24)`, `spacing: 18`, fondo `TF.card`, título `TF.display(22)`. Detalle en apartado 7. |
| Hoja de lista | LS:449, 472 | Ancho 880, alto 700 (`playlistSize`). Detalle en apartado 7. |
| Hoja «Corregir título y artista» | AG:133-167 | Ancho 520, `padding(28)`, `spacing: 18`, título `TF.display(22)`; campos alto 40 radio 8 (AG:85-95), botón de intercambiar 36×36 radio 10 (AG:113-117, `arrow.up.arrow.down` 14 `TF.muted`), separación 10 entre columna y botón, 12 entre campos, 6 entre etiqueta y campo. |
| Hoja de primer arranque | RV:122-137 | Ancho 480, `padding(28)`, `spacing: 16`, fondo `TF.card`, título `TF.display(24)`, no se puede descartar (RV:32). Detalle en apartado 7. |
| Diálogos | LV:33-49; RV:35-47; PR:39-45 | Alertas y confirmaciones: ver apartado 7 (`TfAlert`/`TfConfirmDialog`). |

Colores sueltos fuera de `TF`: `0x4CC38A` (RV:95, `deviceOk`), `.white @0.9` (AG:42). Ningún hex nuevo en el resto de la pantalla.

## 3. Árbol de widgets propuesto

- `LibraryScreen` (LV:21-50): elige entre `LibraryList` y `ProjectDetailPage` según `detail`; aloja los diálogos (limpiar, eliminar) y la hoja de corrección.
  - `TfScreenScroll` con padding 40/32 (kit).
  - `LibraryHeader` (LV:107-136)
    - bloque título/subtítulo
    - `PlaylistIndicator` (LV:114-127): cápsula propia pequeña (no existe en el kit; si se repite, `TfPill`)
    - `LibrarySearchField` → `TfTextField` con lupa y borrar (kit)
    - `TfSegmented` («Temas»/«Artistas»; kit)
    - `TfPrimaryButton` «Importar tema»
  - `SongTable` (LV:161-189) → `TfCard`
    - `TfTableHeaderCell` ×3 (kit)
    - `ImportingRow` (LV:172-181): `TfProgress` + `TfChip`
    - `SongRow` (LV:208-254) → `TfListRow` (kit) + `TfSongCover` (kit) + `TfChip` + `TfSecondaryButton(height: 36)` ×2 + `TfIconButton` papelera; envoltorio `TfContextMenu`
    - `LibraryEmpty` / `NoMatches` → `TfStateMessage`
  - `ArtistBar` (LV:88-97)
  - `ArtistGrid` (LV:71-86) → `GridView` con `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, crossAxisSpacing: 20, mainAxisSpacing: 24)`. Ojo: el mínimo de 160 de `GridItem.adaptive` no tiene equivalente directo; el número de columnas lo da el ancho, así que hay que calcularlo (`floor((ancho+20)/(160+20))` como tope de columnas con ancho ≤ 220) y probar con capturas.
    - `ArtistTile` (AG:7-76), `ArtistAvatar` (`CustomPainter` no; `Container` con color + `Text`); foto vía `Image.memory` desde la `data:` URL
  - `ProjectDetailPage` (LV:267-386)
    - `SongTitleBlock` (LV:286-310) con modo edición → `SongInfoFields`
    - `TfCard` + `InfoRow` ×3 (distinta de `TfInfoRow`: sin fondo propio, `padding h20 v10`, etiqueta muted y valor semibold, LV:382-385; dentro de `TfCard`)
    - `StemsCard`
    - `RecordingsCard` (PR) → `PartBox` → `TakeRow`
    - `DetailActions`
  - Hojas (apartado 7): `ImportSheet` (+ `PlaylistImportView`), `SongInfoSheet`, `FirstRunSheet`
- Fuera de esta pantalla pero la afecta: `DropTarget` global (RV:28-30) sobre toda la ventana → `desktop_drop` (kit).

Ningún `CustomPainter`: todo se resuelve con widgets estándar.

## 4. Estados

| Estado | Qué se ve | Qué lo decide |
| --- | --- | --- |
| Sin carpeta de proyectos | `FirstRunSheet` modal sin cierre (RV:31-32) | `needsFolder` (AM): equivale a que la biblioteca no está abierta/`app.info` sin carpeta |
| Cargando | No hay estado visual en SwiftUI: la lista aparece vacía hasta que llega `refresh()`. Propuesta: no mostrar «Todavía no hay temas» hasta recibir el primer `library.list`. | primera respuesta de `library.list` |
| Biblioteca vacía, vista Temas | Tabla con cabecera + `emptyLibrary` (LV:183-186) | `entries.isEmpty && imports.isEmpty` |
| Biblioteca vacía, vista Artistas | `Card` con `emptyLibrary` (LV:74) | `entries.isEmpty` |
| Con datos, Temas | Filas ordenadas por título plegado (LV:196) | `library.list` |
| Con datos, Artistas | Cuadrícula; al pulsar un recuadro, barra del artista + tabla filtrada sin columna de artista (LV:55-60, 192-195) | `openArtist` (solo UI, no se recuerda; se resetea al cambiar de vista y si el artista desaparece, LV:28-32) |
| Búsqueda sin resultados | «Ningún tema coincide con «…»» (LV:65-68, 197-199) | texto del buscador recortado de espacios |
| Importación en curso | Fila extra arriba con barra y «Importando N %» (LV:172-181) | evento `jobs.progress` / `jobs.list` |
| Estado de separación | Chip por fila (LV:256-264) | `separationState` de `ProjectSummary` + `jobs.progress` |
| Fila seleccionada | Verde con franja (LV:235-238) | `backingTarget` (estado de la app, ver §9 de contrato) |
| Fila en hover | Tinte acento 0,07 | ratón |
| Tema duplicado al importar | Alerta «Este tema ya está en la biblioteca» (RV:38-47) | error de duplicado de `import.file` |
| Aviso genérico | Alerta con título y mensaje + «Aceptar» (RV:35-37) | `notice` (errores de importar, mover a Papelera, etc.) |
| Indicador de lista | Cápsula en cabecera (LV:114-127) | `playlist` en `app.info` (PI:91-103: «Leyendo la lista…», «Buscando N de T», «Importando N de T», «Importación detenida», «Importación terminada», «Importación cancelada» solo si ya corrió) |
| Detalle con edición | Campos en lugar del título (LV:288-298) | estado local `editing` |
| Detalle sin stems | «Sin stems todavía.» (LV:330-332) | `stems` vacío |
| Detalle sin tomas | «Este tema aún no tiene tomas grabadas.» (PR:29-30) | ninguna parte con `takeIDs` |
| Fallo en toma | Línea roja bajo la lista (PR:34, 108, 120) | `failure` local |
| Foto de artista | Mientras no llega: iniciales y color; si llega: foto (AG:36-61) | `library.artistPhoto` |
| Deshabilitados | «Separar de nuevo» y «Limpiar…» si se está separando (LV:246-249); «Ver toma» sin audio procesado (PR:76); «Guardar» con título vacío (LV:293; AG:142) | `isSeparating`, `processedFile`, título |

## 5. Contrato que usa

Ver biblioteca-contrato.md.

## 6. Interacción

- **Pulsar fila**: selecciona el tema (`select`, LV:244); la fila vuelve a verde. No abre el detalle: el detalle se abre desde la tarjeta «tema seleccionado» de la barra (RV:78).
- **Hover**: fila (LV:241-243), `ArtistTile` borde acento (AG:30), papelera icono rojo (LV:402), `MarqueeText` de la tarjeta lateral. En Flutter: `MouseRegion`.
- **Menú contextual de fila** (LV:245-253, clic derecho): «Separar de nuevo» (deshabilitado si se separa), «Cancelar separación» (solo si se separa), «Limpiar…» (deshabilitado si se separa; título «Limpiar «{título}»»), «Mostrar en Finder», línea, «Eliminar…». En Windows «Finder» pasa a «Explorador» (clave propia por plataforma, **decisión de Jorge** si se localiza por sistema).
- **Soltar ficheros**: `dropDestination(for: URL.self)` en toda la ventana (RV:28-30), también sobre otras secciones. Solo importa `wav`, `flac`, `mp3` (AM:694-697); el resto se ignora sin avisar. Flutter: `desktop_drop` en la raíz de la app, no solo en esta pantalla.
- **Teclado**: sin atajos propios en la lista ni en el buscador. En hojas: `Esc` cancela y `Intro` confirma (LS:493,495; AG:159,161; LV:295). La alerta de Papelera marca «Mover a la Papelera» como acción por defecto (`Intro`, LV:44). El buscador no tiene `onSubmit`.
- **Foco**: `SongInfoSheet` y el modo edición del detalle enfocan el campo «Título» al abrirse (AG:165; LV:279).
- **Intercambiar título/artista**: botón entre campos (AG:110-121).
- **Hoja de importación**: `Intro` en el campo de enlace = «Importar» (LS:482); `Intro` en el campo manual = «Añadir» (LS:682-686); no se puede cerrar con `Esc`/clic fuera mientras `canCancel` es falso (LS:474).
- **Foto del artista**: la pide cada recuadro al hacerse visible y cancela al salir de pantalla (AG:32-33); caché por nombre plegado (AG:15, 55-56). En Flutter: pedir dentro del `itemBuilder` (perezoso) y cachear por clave plegada.
- **Persistencia**: solo la vista Temas/Artistas (LV:9). Buscador y artista abierto no.

## 7. Hojas y popovers

### Hoja «Importar tema» / «Importar desde enlace» / «Importar lista» (`LinkImportSheet`, LS:446-830)

Un único `TfSheet` con pantallas (`screen`): vacía, resolviendo, preparando, candidatos, trabajando, error, hecho, repetido, lista. Ancho 620 en vacía, 560 en el resto, 880×700 en lista; `padding(24)`; título `TF.display(22)`: «Importar lista» / «Importar tema» (vacía) / «Importar desde enlace» (LS:454). No se puede descartar mientras hay trabajo que no se puede cancelar (LS:474).

- **Vacía** (LS:479-499): campo de enlace (alto 40, radio 8, spinner pequeño a la derecha mientras busca en Spotify); debajo, o bien la ayuda de enlaces admitidos (`TF.body(12)` muted), o un banner de error + la ayuda, o los resultados de Spotify en una lista con fondo `TF.field` radio 8: por fila miniatura 36×36 radio 4 (LS:530), nombre `TF.body(13,.semibold)`, artistas 12 `TF.text2`, álbum · año 11 muted, duración monoespaciada, ▶ «Oír en Spotify» (abre la URL), «Elegir» (Secondary 30); `padding h10 v6`. Botones al pie: «Importar fichero…» (Secondary, deshabilitado si ocupado), hueco 8, «Cancelar» (`Esc`), «Importar» (Primary, `Intro`, deshabilitado si ocupado o campo vacío).
- **Resolviendo** (LS:584-593): spinner + «Leyendo metadatos…» o «Buscando en YouTube…»; con búsqueda, «Suele tardar unos 9 s.»; «Cancelar».
- **Preparando** (LS:572-580): spinner + «Preparando…»; «Cancelar».
- **Candidatos** (LS:597-728): cabecera con portada 104×104 radio 10 (LS:643-648; marcador `music.note`) y campos «Título» y «Artista» (alto 40); banda «Puede que ya lo tengas: …» con «Abrir» (Secondary 28; fondo `TF.neutralBg` radio 8, LS:616-625); banners de error/aviso; o bien confirmación de un vídeo único («VÍDEO A IMPORTAR», tarjeta `TF.field` radio 10, `padding(12)`) o lista «CANDIDATOS EN YOUTUBE» (`maxHeight: 280` con scroll, `spacing: 6`): fila radio 10, `padding h12 v10`, seleccionada fondo `accentBg` + borde `accent`; radio ○/◉, título, canal · duración, diferencia con signo («+1,2 s»), chips «cercano» (ok) y «directo» (neutral), enlace ↗ «Abrir en el navegador»; si ya está en la biblioteca: opacidad 0,7, chip «En la biblioteca» + «Abrir», no seleccionable. Campo manual con «Añadir». Pie: «Cancelar», «Importar» (deshabilitado sin candidato o sin título).
- **Trabajando** (LS:738-757): título/artista, etiqueta de fase («Actualizando yt-dlp…», «Importando en la biblioteca…», «Descargando audio…», «Convirtiendo a WAV…») + porcentaje, `TfAccentBar` (indeterminada si no hay valor), avisos, «Cancelar» (deshabilitado si `canCancel` falso).
- **Error** (LS:759-789): icono triángulo `TF.danger` + título `TF.body(15,.semibold)` + detalle seleccionable `TF.body(13)` muted; banner si yt-dlp ya es el último; botones «Cerrar» y uno de «Actualizar y reintentar» / «Probar con otro enlace» / «Pegar un enlace de YouTube» / «Reintentar».
- **Hecho** (LS:791-796): «Tema importado» (check `TF.ok`), avisos finales, «Cerrar» (Primary).
- **Repetido** (LS:550-568): «Ya está en la biblioteca», tarjeta con título y artista, «No se busca ni se descarga nada.», «Cerrar» y «Abrir».

Los avisos usan `banner` (LS:820-826): `TF.body(13)`, `padding h12 v10`, radio 8; error `TF.danger` sobre `dangerBg`, aviso `TF.accent` sobre `accentBg`.

### Pantalla de lista (`PlaylistImportView`, PI:216-596)

Dentro de la misma hoja (880×700). Cabecera con nombre de la lista (`TF.body(16,.semibold)`, «Lista» si vacío; PI:228); tabla con fondo `TF.bg @0.5`, radio 10, borde `TF.fieldLine` (PI:241-243); fila `padding h14 v8` (PI:264). Fases:

1. **Leyendo** (PI:273-275): spinner + «Leyendo la lista…», «Cancelar».
2. **Elegir temas** (PI:285-302, 310-330): resumen «{total} temas · {marcados} marcados[ · {n} ya en la biblioteca]», «Marcar todos» y «Ninguno» (Secondary 34); casilla 18 (cuadrado ✓), título/artista, chips «En la biblioteca» / «Puede que ya lo tengas» (tooltip «Parecido a: …»), duración ancho 48 a la derecha; aviso de tope de 100 de Spotify; pie «Cerrar» y «Descargar y procesar (N)» o «Buscar en YouTube (N)».
3. **Buscando** (PI:340-350): «Buscando cada tema en YouTube», «Buscando X de N», «Nada se descarga todavía: después podrás revisar los candidatos.», «Cancelar».
4. **Revisar** (PI:363-428): «{n} con candidato · {n} dudosos · {n} omitidos» y banner de revisión; columnas título 250 + duración 40 + selector de candidato (menú desplegable en una caja radio 8, chevron ⌃⌄ 10); chip «dudoso» (error); opciones del menú: candidatos, «Abrir «…» en la biblioteca», «Omitir este tema»; pie «Cerrar», «Seguir buscando» (si faltan), «Descargar y procesar (N)».
5. **Cola** (PI:459-505): «Descargando, importando y separando» o «Cola detenida», «{hechos} de {N} temas», por fila estado («Descargando N %», «Convirtiendo…», «Importado», «Omitido», «En la biblioteca», «En cola») con `TfAccentBar` 140×5; errores con banner; «Cerrar» (tooltip «La cola sigue en segundo plano»), «Actualizar y reintentar»/«Actualizando…», «Reanudar», «Cancelar».
6. **Resumen** (PI:519-545): títulos «Importación terminada» / «Cola cancelada: lo ya importado se conserva»; cuatro cifras `TF.display(26)` (Importados `ok`, Omitidos, Ya en la biblioteca, Fallidos `danger` si > 0) en cajas `TF.field` radio 10 `padding h16 v12`; nota «Los temas importados se están separando en stems; verás el avance en la Biblioteca.»; sección «FALLIDOS» (título 280); «Cerrar», «Reanudar (N)», «Reintentar fallidos (N)».
7. **Error de lista** (PI:583-592): «Cerrar», «Probar con otro enlace».

El `SourceError` se traduce a título y detalle en SwiftUI (LS:405-437); ver apartado 8.

### Hoja «Corregir título y artista» (AG:133-167)

Título, `SongInfoFields` (Título, Artista, botón intercambiar), pie «Cancelar» (`Esc`) + «Guardar» (`Intro`, deshabilitado con título vacío o guardando). Cierra al guardar con éxito; con título vacío el núcleo responde con aviso «Falta el título» (AM:994).

### Hoja de primer arranque (RV:122-137)

Título, explicación, «Propuesta: ~/Music/ToneForge» (`TF.body(13)` `TF.text2`; en Windows la propuesta cambia, ver §9 de contrato) y «Elegir carpeta…» (Primary a la derecha) que abre el selector de carpetas. Sin botón de cerrar.

### Diálogos de confirmación y alertas

- **Eliminar tema** (LV:41-49): título «¿Eliminar “{título}”?», acciones «Mover a la Papelera» (por defecto), «Eliminar del disco» (destructiva), «Cancelar»; mensaje con el contenido (`TrashRequest.contents`, AM:189-194: «sus stems» / «1 stem» / «N stems», «1 toma»/«N tomas», «1 vídeo»/«N vídeos»).
- **Limpiar** (LV:33-40): título «Limpiar «{título}»» (o global), acciones «Limpiar {bytes}» (destructiva) y «Cancelar».
- **Eliminar toma** (PR:39-45): «¿Eliminar la toma?», «Eliminar Toma N · {parte}» (destructiva), «Cancelar».
- **Duplicado** (RV:38-47), **aviso** (RV:35-37).

## 8. Textos

Claves en `app_es.arb`, todas con prefijo `library_`; inglés lo traduce el agente. Plurales con ICU (`{count, plural, one{…} other{…}}`).

### Cabecera, lista y vacíos

| Clave | Español | Origen |
| --- | --- | --- |
| `library_title` / `library_subtitle` | Biblioteca / Tus temas. | LV:110-111 |
| `library_searchHint` | Buscar tema o artista | LV:141 |
| `library_searchClear` | Borrar búsqueda | LV:144 |
| `library_viewSongs` / `library_viewArtists` | Temas / Artistas | LV:130-131 |
| `library_viewLabel` | Vista (solo accesibilidad) | LV:129 |
| `library_importButton` | Importar tema | LV:134 |
| `library_playlistIndicatorTooltip` | Ver la importación de la lista | LV:125 |
| `library_colSong` / `library_colTakes` / `library_colState` | Tema / Artista · Tomas · Estado (se pintan en mayúsculas; clave `colSong` = «Tema / Artista») | LV:165-167 |
| `library_emptyTitle` | Todavía no hay temas | LV:101 |
| `library_emptyBody` | Importa un wav, flac o mp3, arrástralo a esta ventana o pega un enlace de YouTube o Spotify. | LV:102 |
| `library_noMatch` | Ningún tema coincide con «{query}» | LV:66 |
| `library_importing` | Importando {percent} | LV:178 |
| `library_stateQueued` / `_Running` / `_Done` / `_Failed` / `_Imported` | En cola / Separando {percent} / Separado / Error / Importado | LV:258-262 |
| `library_stateFailedUnknown` | Error desconocido | LV:261 |
| `library_takesNone` | — | LV:218 |
| `library_revealTooltip` | Mostrar en Finder (en Windows «Mostrar en el Explorador»; decisión de Jorge) | LV:224 |
| `library_editTooltip` | Editar título y artista | LV:228 |
| `library_deleteTooltip` / `library_deleteLabel` | Eliminar… / Eliminar | LV:403-404 |
| `library_menuSeparate` / `_menuCancelSeparation` / `_menuClean` / `_menuReveal` / `_menuDelete` | Separar de nuevo / Cancelar separación / Limpiar… / Mostrar en Finder / Eliminar… | LV:246-252 |
| `library_cleanTitle` | Limpiar «{title}» | LV:248 |

### Artistas

| Clave | Español | Origen |
| --- | --- | --- |
| `library_artistsBack` | Artistas | LV:92 |
| `library_noArtist` | Sin artista | LV:94; AG:24 |
| `library_artistTrackCount` | `{count, plural, one{1 tema} other{{count} temas}}` | AG:25 |
| `library_artistTileLabel` | {name}, {count} temas (accesibilidad) | AG:31 |

### Detalle del tema

| Clave | Español | Origen |
| --- | --- | --- |
| `library_detailBack` | Biblioteca | LV:316 |
| `library_infoRate` / `_infoDuration` / `_infoState` | Frecuencia / Duración / Estado | LV:321-323 |
| `library_stateDetailImported` / `_Queued` / `_Running` / `_Done` | Importado / En cola / Separando / Separado | LV:374-377 |
| `library_stateDetailFailed` / `library_stateDetailFailedUnknown` | Error: {message} / desconocido | LV:378 |
| `library_stemsTitle` / `library_stemsNone` / `library_stemEmpty` | Stems / Sin stems todavía. / vacío | LV:329-337 |
| `library_openInBacking` | Abrir en Backing track | LV:352 |
| `library_revealButton` | Mostrar en Finder | LV:355 |
| `library_deleteButton` | Eliminar… | LV:357 |
| `library_save` / `library_cancel` | Guardar / Cancelar | LV:292-294 |

### Grabaciones

| Clave | Español | Origen |
| --- | --- | --- |
| `library_recordingsTitle` | Grabaciones | PR:28 |
| `library_recordingsNone` | Este tema aún no tiene tomas grabadas. | PR:30 |
| `library_takeNumber` | Toma {n} | PR:66 |
| `library_takeBest` | Mejor toma (accesibilidad de ★) | PR:67 |
| `library_takeWithVideo` / `library_takeNoVideo` | Con vídeo / Sin vídeo | PR:70 |
| `library_takePunches` | `{count, plural, one{1 punch} other{{count} punches}}` | PR:71 |
| `library_takeView` / `library_takeDelete` | Ver toma / Eliminar | PR:74, 77 |
| `library_takeLabel` | Toma {n} · {part} | PR:81 |
| `library_takeDeleteTitle` / `_takeDeleteConfirm` / `_takeDeleteMessage` | ¿Eliminar la toma? / Eliminar {label} (por defecto «toma») / Se borra su carpeta (audio y vídeo). No se puede deshacer. | PR:39-44 |
| `library_takeBestError` / `library_takeDeleteError` | No se pudo marcar la toma como mejor ({error}). / No se pudo eliminar la toma ({error}). | PR:108, 120 |
| `library_takeNoDuration` | – | PR:86 |

### Hoja de corrección y primer arranque

| Clave | Español | Origen |
| --- | --- | --- |
| `library_editSheetTitle` | Corregir título y artista | AG:155 |
| `library_fieldTitle` / `library_fieldArtist` | Título / Artista | AG:107-108 |
| `library_swapTooltip` | Intercambiar título y artista | AG:120 |
| `library_firstRunTitle` | Elige tu carpeta de proyectos | RV:127 |
| `library_firstRunBody` | Cada tema vive en su propia carpeta, con sus stems, tomas y vídeo. Puedes cambiarla más tarde en Ajustes. | RV:128 |
| `library_firstRunProposal` | Propuesta: {path} (Mac: `~/Music/ToneForge`) | RV:130 |
| `library_firstRunChoose` | Elegir carpeta… | RV:131 |

### Diálogos y avisos

| Clave | Español | Origen |
| --- | --- | --- |
| `library_trashTitle` | ¿Eliminar “{title}”? | LV:41 |
| `library_trashToBin` / `library_trashDelete` | Mover a la Papelera / Eliminar del disco (en Windows «Papelera de reciclaje», decisión de Jorge) | LV:44-45 |
| `library_trashMessage` | Se va con el tema: {contents}. Si se está separando o está abierto en Backing, se detiene primero.\nEliminar del disco no se puede deshacer. La Papelera conserva la carpeta hasta que la vacíes. | LV:48 |
| `library_trashContentsStems` | `{count, plural, =0{sus stems} one{1 stem} other{{count} stems}}` | AM:190 |
| `library_trashContentsTakes` / `_Videos` | `{count, plural, one{1 toma} other{{count} tomas}}` / `{count, plural, one{1 vídeo} other{{count} vídeos}}` | AM:191-192 |
| `library_cleanConfirm` | Limpiar {bytes} | LV:36 |
| `library_cleanMessage` | Se borrarán tomas descartadas y stems por {bytes}. Los stems se pueden volver a generar. | LV:39 |
| `library_duplicateTitle` | Este tema ya está en la biblioteca | RV:38 |
| `library_duplicateOpen` | Abrir el existente | RV:40 |
| `library_duplicateMessage` | Ya hay un proyecto con el mismo audio (mismo SHA-256) o con el mismo vídeo de origen. ¿Quieres abrirlo? | RV:46 |
| `library_noticeOk` | Aceptar | RV:36 |
| `library_errImportFile` | No se pudo importar {file} | AM:712 |
| `library_errTrashTitle` / `_errTrashBody` | No se pudo mover a la Papelera / {error} No se ha borrado nada; te queda «Eliminar del disco». | AM:978-979 |
| `library_errDelete` / `_errClean` / `_errSeparate` / `_errCancel` / `_errOpen` / `_errSave` | No se pudo eliminar del disco / No se pudo limpiar / No se pudo separar {title} (en la lista de la barra: «No se pudo separar») / No se pudo cancelar / No se pudo abrir el tema / No se pudo guardar el título | AM:976, 942, 643, 913, 734, 996 |
| `library_errTitleEmptyTitle` / `_errTitleEmptyBody` | Falta el título / El título no puede quedar vacío. | AM:994 |
| `library_errBusy` / `_errWorkInProgress` / `_errUnsafeDeletion` / `_errProjectNotFound` / `_errDuplicate` | El tema está ocupado (separándose o reconvirtiéndose). / Hay una separación en curso o en cola. / La carpeta del tema no es un proyecto válido de la biblioteca; no se ha borrado nada. / No se encuentra el proyecto en la carpeta. / Ese tema ya está en la biblioteca. | AM:1078-1082 |

### Hoja de importación

| Clave | Español | Origen |
| --- | --- | --- |
| `library_importTitleEmpty` / `_importTitleLink` / `_importTitleList` | Importar tema / Importar desde enlace / Importar lista | LS:454 |
| `library_importLinkHint` | Pega un enlace o busca en Spotify | LS:482 |
| `library_importSupported` | Se admiten enlaces de un vídeo de YouTube (youtube.com/watch, youtu.be, music.youtube.com) y de una canción de Spotify (open.spotify.com/track o spotify:track), además de listas de YouTube (youtube.com/playlist) y listas o álbumes de Spotify (open.spotify.com/playlist, open.spotify.com/album). Episodios no. | LS:403 |
| `library_importFile` / `_importCancel` / `_importGo` | Importar fichero… / Cancelar / Importar | LS:489-494 |
| `library_importSpotifyNone` | Spotify no ha encontrado nada para «{query}» | LS:512 |
| `library_importListenTooltip` / `_importChoose` | Oír en Spotify / Elegir | LS:541-542 |
| `library_importRepeatedTitle` / `_importRepeatedBody` | Ya está en la biblioteca / No se busca ni se descarga nada. | LS:552, 562 |
| `library_importClose` / `_importOpen` | Cerrar / Abrir | LS:564-565 |
| `library_importPreparing` | Preparando… | LS:576 |
| `library_importReadingMeta` / `_importSearchingYt` / `_importSlow` | Leyendo metadatos… / Buscando en YouTube… / Suele tardar unos 9 s. | LS:588-590 |
| `library_importPossible` | Puede que ya lo tengas: {name} | LS:617 |
| `library_importVideoLabel` / `_importCandidatesLabel` | VÍDEO A IMPORTAR / CANDIDATOS EN YOUTUBE | LS:650, 667 |
| `library_importSpotifyDuration` | Spotify: {duration} | LS:670 |
| `library_importNoResults` | La búsqueda no ha dado resultados. Pega a mano un enlace de YouTube. | LS:675 |
| `library_importNoClose` | Ningún candidato queda a {seconds} s o menos de la duración de Spotify. Elige con cuidado o pega a mano un enlace de YouTube. | LS:676 |
| `library_importManualLabel` / `_importManualHint` / `_importManualAdd` | ¿Ninguno convence? Pega un enlace de YouTube / https://www.youtube.com/watch?v=… / Añadir | LS:682-686 |
| `library_importChipClose` / `_importChipLive` / `_importChipInLibrary` | cercano / directo / En la biblioteca | LS:708-711 |
| `library_importOpenBrowser` | Abrir en el navegador | LS:727 |
| `library_importUpdating` / `_importImporting` / `_importDownloading` / `_importConverting` | Actualizando yt-dlp… / Importando en la biblioteca… / Descargando audio… / Convirtiendo a WAV… | LS:132-139 |
| `library_importDone` | Tema importado | LS:793 |
| `library_importFailTitle` | No se pudo importar | LS:761 |
| `library_importUpdateRetry` / `_importOtherLink` / `_importPasteYt` / `_importRetry` | Actualizar y reintentar / Probar con otro enlace / Pegar un enlace de YouTube / Reintentar | LS:777-783 |
| `library_importAlreadyLatest` | yt-dlp ya es la última versión: YouTube ha cambiado algo y hay que esperar a que se corrija. Mientras, importa el fichero a mano (Importar tema > Desde fichero…). | LS:772 |

### Errores de fuente (`SourceError`, LS:405-437)

| Clave | Título | Detalle |
| --- | --- | --- |
| `library_srcOffline` | Sin conexión | No se ha podido conectar. Comprueba la red y reintenta. |
| `library_srcUnsupported` | Enlace no admitido | (`library_importSupported`) |
| `library_srcSpotifyUnreadable` | No se han podido leer los datos de Spotify | Pega un enlace de YouTube del tema en su lugar. |
| `library_srcAgeRestricted` | Vídeo con restricción de edad | Vídeo con restricción de edad: no se puede descargar sin cuenta. |
| `library_srcRegion` | No disponible en tu región | Este vídeo no está disponible en tu país. |
| `library_srcPrivate` | Vídeo privado | Este vídeo es privado. |
| `library_srcRemoved` | Vídeo no disponible | Este vídeo se ha retirado o ya no está disponible. |
| `library_srcNoAudioFormat` | Sin audio descargable | Este vídeo no ofrece audio descargable. |
| `library_srcExtractorBroken` | yt-dlp puede estar desactualizado[ (versión {version})] | YouTube ha cambiado algo y yt-dlp no sabe leerlo. (o el detalle recibido) |
| `library_srcFfmpegFailed` | Falló la conversión | últimas 4 líneas del mensaje |
| `library_srcHelperMissing` | Falta un componente | No se encuentra «{name}» dentro de la app. Reinstala ToneForge. |
| `library_srcLaunchFailed` | No se pudo lanzar el proceso | últimas 4 líneas |
| `library_srcHttpStatus` | Respuesta inesperada | El servidor respondió con el código {code}. |
| `library_srcTimedOut` | Tiempo agotado | El servidor tarda demasiado en responder. Reintenta. |
| `library_srcCancelled` | Cancelado | (vacío) |
| `library_srcChecksum` | Actualización rechazada | La suma SHA-256 del yt-dlp descargado no coincide. No se ha instalado nada. |
| `library_srcUpdateFailed` | No se pudo actualizar yt-dlp | últimas 4 líneas |
| `library_srcRateLimited` | YouTube ha limitado las peticiones | YouTube ha limitado las peticiones; espera unos minutos y reintenta. |
| `library_srcNoAudioProduced` | Sin audio | yt-dlp terminó pero no dejó ningún fichero de audio. |

### Lista (`PlaylistImportView` e indicador)

| Clave | Español | Origen |
| --- | --- | --- |
| `library_plIndLoading` / `_plIndSearching` / `_plIndImporting` | Leyendo la lista… / Buscando {n} de {total} / Importando {n} de {total} | PI:93-97 |
| `library_plIndStopped` / `_plIndFinished` / `_plIndCancelled` | Importación detenida / Importación terminada / Importación cancelada | PI:98-100 |
| `library_plDefaultName` | Lista | PI:228 |
| `library_plSummary` | {total} temas · {selected} marcados | PI:285 |
| `library_plSummaryInLibrary` | ` · {n} ya en la biblioteca` | PI:285 |
| `library_plSelectAll` / `_plSelectNone` | Marcar todos / Ninguno | PI:287-288 |
| `library_plCap` | Spotify devuelve como máximo 100 temas por lista: puede haber cortado esta. Si faltan temas, impórtalos desde su enlace. | PI:291 |
| `library_plDownload` / `_plSearch` | Descargar y procesar ({n}) / Buscar en YouTube ({n}) | PI:299-302 |
| `library_plChipMaybe` / `_plMaybeTooltip` | Puede que ya lo tengas / Parecido a: {title} | PI:326 |
| `library_plSearchingAll` / `_plSearchingN` / `_plNothingYet` | Buscando cada tema en YouTube / Buscando {n} de {total} / Nada se descarga todavía: después podrás revisar los candidatos. | PI:340-348 |
| `library_plReviewSummary` | {proposed} con candidato · {doubtful} dudosos · {skipped} omitidos | PI:363 |
| `library_plReviewBanner` | Revisa lo propuesto: nada se descarga hasta que pulses «Descargar y procesar». Los «dudosos» no tienen propuesta: elige uno o se omiten. | PI:364 |
| `library_plKeepSearching` | Seguir buscando | PI:370 |
| `library_plChipDoubtful` | dudoso | PI:384 |
| `library_plOpenExisting` / `_plSkipItem` | Abrir «{title}» en la biblioteca / Omitir este tema | PI:397, 405 |
| `library_plInLibrarySuffix` | {label} · En la biblioteca | PI:396 |
| `library_plChoiceSkipped` / `_Failed` / `_Pending` / `_NoResults` / `_Pick` | Omitido / Falló la búsqueda: {title} / Sin buscar / Sin resultados: omitir / Elige un candidato… | PI:435-438 |
| `library_plQueueTitle` / `_plQueueStopped` / `_plQueueCount` | Descargando, importando y separando / Cola detenida / {done} de {total} temas | PI:459-461 |
| `library_plRateLimitedHint` | No se reintenta sola: reanuda cuando quieras. | PI:468 |
| `library_plLatestKept` | yt-dlp ya es la última versión: YouTube ha cambiado algo y hay que esperar a que se corrija. Lo ya importado se conserva. | PI:470 |
| `library_plCloseTooltip` | La cola sigue en segundo plano | PI:476 |
| `library_plUpdating` / `_plUpdateRetry` / `_plResume` / `_plCancel` | Actualizando… / Actualizar y reintentar / Reanudar / Cancelar | PI:479-485 |
| `library_plDownloading` / `_plConverting` / `_plQImported` / `_plQSkipped` / `_plQInLibrary` / `_plQQueued` | Descargando[ N %] / Convirtiendo… / Importado / Omitido / En la biblioteca / En cola | PI:498-505 |
| `library_plDoneTitle` / `_plCancelledTitle` | Importación terminada / Cola cancelada: lo ya importado se conserva | PI:519 |
| `library_plStatImported` / `_Skipped` / `_InLibrary` / `_Failed` | Importados / Omitidos / Ya en la biblioteca / Fallidos | PI:521-524 |
| `library_plSeparatingNote` | Los temas importados se están separando en stems; verás el avance en la Biblioteca. | PI:527 |
| `library_plFailedHeader` | FALLIDOS | PI:533 |
| `library_plResumeN` / `_plRetryFailed` | Reanudar ({n}) / Reintentar fallidos ({n}) | PI:539-542 |

La pantalla de error de lista (PI:579-592) usa los mismos títulos y detalles de `SourceError` de la tabla anterior; sus botones son «Cerrar» y «Probar con otro enlace».

## 9. Desvíos detectados

Ver biblioteca-contrato.md.

## 10. Partes de trabajo sugeridas

Ya existe una versión web en `WinApp/Web/screens/library.js` (y `library-dialogs.js`, `import-files.js`, `link-sheet.js`, `playlist-sheet.js`) que sirve de guía de comportamiento, no de código a copiar.

| Parte | Ficheros Dart | Tamaño | Agente |
| --- | --- | --- | --- |
| A. Contrato y stores | `contract/library.dart` (+ `link`, `playlist`, `jobs`), `features/library/library_store.dart` (lista, filtro, agrupación, selección, detalle), `import_store.dart` (jobs y soltar ficheros), `link_import_store.dart`, `playlist_store.dart` + fixtures en `Contract/fixtures/{library,link,playlist}/` | L | `tf-flutter` (Sonnet) |
| B. Lista y cabecera | `library_screen.dart`, `widgets/library_header.dart`, `song_table.dart`, `song_row.dart`, `importing_row.dart`, `library_empty.dart`, `row_context_menu.dart` | M | `tf-flutter` (Sonnet) |
| C. Artistas | `widgets/artist_grid.dart`, `artist_tile.dart`, `artist_bar.dart`, `artist_avatar.dart` (iniciales + color FNV-1a) y caché de fotos | M | `tf-flutter` (Sonnet) |
| D. Detalle del tema | `project_detail_page.dart`, `widgets/stems_card.dart`, `recordings_card.dart`, `part_box.dart`, `take_row.dart` | M | `tf-flutter` (Sonnet) |
| E. Hoja de importación (un tema) | `sheets/import_sheet.dart` con las 8 pantallas, `candidate_row.dart`, `spotify_track_row.dart`, `source_messages.dart` | L | `tf-flutter` (Sonnet) |
| F. Importación de lista | `sheets/playlist_import_view.dart` (6 fases), `playlist_indicator.dart` | L | `tf-flutter` (Sonnet) |
| G. Hojas pequeñas y diálogos | `sheets/song_info_sheet.dart` (+ `song_info_fields.dart`), `first_run_sheet.dart`, `dialogs/trash_dialog.dart`, `clean_dialog.dart`, `delete_take_dialog.dart`, `duplicate_dialog.dart`, `notice_dialog.dart` | M | `tf-flutter-mech` (Haiku) con revisión |
| H. Soltar ficheros | `widgets/drop_target.dart` en la raíz de la app (kit) | S | `tf-flutter-mech` (Haiku) |
| I. Textos | claves del apartado 8 en `app_es.arb` y `app_en.arb` | M | `tf-flutter-mech` (Haiku) |
| J. Tests | `test/features/library/*`, goldens | M | `tf-flutter` (Sonnet) |

Orden: A primero; B, C, D, E, G, H en paralelo; F tras E (comparte la hoja y `source_messages.dart`); I y J al final. A y C dependen de las decisiones de agrupación y selección (apartado 9 del contrato).

## 11. Criterios de aceptación

Capturas de referencia a igualar (SwiftUI en Mac con datos de ejemplo):

| Estado | PNG |
| --- | --- |
| Lista de temas con todos los estados de separación | `library-songs.png` |
| Lista vacía (Temas y Artistas) | `library-empty-songs.png`, `library-empty-artists.png` |
| Importación en curso (fila superior) | `library-importing.png` |
| Búsqueda sin resultados | `library-nomatch.png` |
| Cuadrícula de artistas, con foto, con iniciales y «Sin artista» | `library-artists.png` |
| Artista abierto | `library-artist-open.png` |
| Fila seleccionada y fila en hover | `library-row-selected.png`, `library-row-hover.png` |
| Indicador de lista en cabecera | `library-playlist-indicator.png` |
| Detalle con stems y grabaciones; sin tomas; en edición | `library-detail.png`, `-notakes.png`, `-edit.png` |
| Hoja de importación: vacía, resultados Spotify, resolviendo, candidatos, confirmación única, trabajando, error, hecho, repetido | `library-import-empty.png`, `-spotify.png`, `-resolving.png`, `-candidates.png`, `-confirm.png`, `-working.png`, `-error.png`, `-done.png`, `-repeated.png` |
| Hoja de lista: elegir, revisar, cola, resumen | `library-playlist-pick.png`, `-review.png`, `-queue.png`, `-summary.png` |
| Corregir título y artista; primer arranque | `library-songinfo.png`, `library-firstrun.png` |
| Diálogos: eliminar tema, limpiar, eliminar toma, duplicado, aviso | `library-dlg-trash.png`, `-clean.png`, `-take.png`, `-duplicate.png`, `-notice.png` |

Tests de store (con `MockCore`): la lista se ordena por título plegado y la búsqueda ignora mayúsculas y tildes en título y artista; la agrupación por artista pone «Sin artista» al final y ordena temas por título; el artista abierto se cierra al cambiar de vista o si desaparece; `library.changed` recarga; `jobs.progress` actualiza el chip y la fila de importación; el duplicado abre la alerta con el id existente; soltar ficheros filtra a wav/flac/mp3 y llama `import.file` por ruta; el cambio de vista se persiste y buscador y artista abierto no; «Guardar» envía `library.rename` con el artista vacío como ausente y no cierra si falla; eliminar toma recarga el detalle; el indicador de lista solo aparece con texto y «Importación cancelada» solo si la cola corrió.

Tests de widget: fila (seleccionada, hover, columnas 70/150/170, artista oculto dentro de un artista); `ArtistTile` (iniciales de las dos primeras palabras, `?` si vacío, color estable entre ejecuciones: `artistAvatar('Metallica')` fijo); cuadrícula con 160-220 de ancho y columnas coherentes; chip por cada estado; botón «Guardar» deshabilitado con título vacío; hoja de importación: «Importar» deshabilitado con campo vacío y con trabajo en curso, `Esc` cierra salvo con trabajo sin cancelar; plurales («1 tema»/«2 temas», «1 punch»/«2 punches», `contents` del diálogo); caja de parte con «Ver toma» deshabilitado.

Pasos manuales para Jorge (red, disco o criterio de vista):

1. Importar un wav, un flac y un mp3 reales (arrastrando y con «Importar fichero…») y ver la fila de progreso y el chip hasta «Separado».
2. Importar por enlace de YouTube y de Spotify con red real: candidatos, diferencia de duración, «cercano»/«directo», tema ya existente.
3. Importar una lista de Spotify de más de 100 temas y una de YouTube; cancelar, reanudar y reintentar fallidos.
4. Ver la foto de artista de Spotify con credenciales (requiere clave de Jorge) y el caso sin credenciales (iniciales).
5. Primer arranque en una máquina sin perfil: elegir carpeta y ver la lista vacía.
6. Eliminar a la Papelera y del disco un tema separado con tomas y vídeo; comprobar el texto del diálogo y que la carpeta llega a la papelera del sistema.
7. Comparar con la captura de SwiftUI el aspecto de la cuadrícula a varios anchos de ventana.
