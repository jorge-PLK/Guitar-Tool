# Fase 7f · Desvíos de núcleo

Un desvío es algo que la app SwiftUI hace y `AppCore` no ofrece, o hace distinto, o que se comporta distinto en Mac y en Windows. La 7c se da por cerrada en funcionalidad (Jorge, 22/11/2026): los desvíos se resuelven aquí.

## Regla (ADR-021, decisión 3)

1. Quien lo encuentra lo reporta con evidencia (`fichero:línea` en SwiftUI y en `AppCore`); `tf-docs` lo añade a la tabla.
2. **Hueco claro** (falta un método, un campo o un evento, y SwiftUI define sin ambigüedad el comportamiento): `tf-implementer` lo arregla en `AppCore` en la misma ola, con su test en `AppCoreTests` y su fixture en `Contract/fixtures/`. No se pregunta.
3. **Exige decisión** (hay que elegir comportamiento, o toca señal, audio, vídeo o sincronía, o cambia el modelo de datos): pregunta a Jorge con alternativas y una recomendada. La pantalla sigue con el resto.
4. **Solo de interfaz** (estado que no necesita persistir ni compartir: selección, plegado, filtro de búsqueda, foco): vive en Dart y no es un desvío de núcleo; se anota para que conste.
5. Nunca se suple en Dart un hueco de núcleo con lógica de negocio.

Estados: `abierto` · `en curso` · `resuelto (commit)` · `pregunta` · `interfaz` · `descartado`.

## Heredados de la 7c

Estado a comprobar al empezar la ola 0 contra `docs/plan/fase-7c.md` («Condición de cierre de la 7c») y `Temp/win/appcore-gap-audit.md`; el commit `894319e` cerró parte.

| Id | Qué | Ola | Tipo | Estado |
| --- | --- | --- | --- | --- |
| B1 | Separador de guitarras en Windows (`guitarSplitter`) | 2 | núcleo | a comprobar |
| B2 | Cambio de carpeta de proyectos en caliente (`Library.relocate`) | 1 | núcleo | a comprobar |
| B3 | Primer arranque: proponer y crear `~/Music/ToneForge` | 1 | núcleo | a comprobar |
| B4 | Fotos de artista por `AppCore` | 1 | núcleo | a comprobar |
| B6 | Cierre ordenado (`terminateAll`, `flush`) | 0 | núcleo | a comprobar |
| A1 | Cámaras en Ajustes del Mac por `AppCore` (`resolvedCameras`) | 3 | núcleo | abierto |
| M1 | Hoja «Encuadre» en el Mac (`takeFrame` tenía `nil`; `MontageServices.swift:73-78` ya tiene rama Mac) | 4 | núcleo, vídeo | resuelto en código (`a5f9eb6`); pendiente de que Jorge compruebe `framingFrame` con vídeo real en el Mac |
| R3, M2 | Rendimiento de cámara y vista previa en el Mac | P9 | medida | lo sustituye la prueba 3 de P9 (píxeles crudos) |
| T3 | Guardar fichero y abrir URL desde el anfitrión | 0 | anfitrión Flutter | resuelto en código (b5f880d): `saveFile` y `openURL` por `hostRequest`; falta el lado Dart (F1) |
| S4 | Modelos embebidos en `Bundle.main` | 5 | empaquetado | abierto |
| — | Audio y cámara reales del Mac por el puente de `AppCore` | 3 | hardware (Jorge) | abierto |

## Nuevos de la 7f

Vienen del apartado 9 de las fichas de `pantallas/`. La clase sigue [decisiones-interfaz.md](decisiones-interfaz.md), que manda sobre las fichas. Prefijos: L Biblioteca, K Backing, TB Tablatura, GR Grabar, MO Montaje, AJ Ajustes (T, R, S, N y M ya los usan los heredados y N1/N2). Ola: 1 Biblioteca y Ajustes·Biblioteca; 2 Backing y Tablatura; 3 Grabar, visor y Ajustes·Audio/Vídeo; 4 Montaje. Todos en estado `abierto` salvo que se indique. «Ficha» remite al apartado 9 (`b` = `biblioteca-contrato.md`, `k` = `backing-contrato.md`, `t` = `tablatura-contrato.md`, `g` = `grabar-contrato.md`, `m` = `montaje-contrato.md`, `a` = `ajustes.md`).

| Id | Pantalla | Qué | Clase | Ola | Ficha |
| --- | --- | --- | --- | --- | --- |
| N1 | Todas | Textos de error y avisos del núcleo en español: pasar a `{code, message, args}` (`mensajes-nucleo.md`) | hueco claro (decidido, ADR-021, 16) | 1 | ADR-021 |
| N2 | Grabar, Ajustes, Montaje | Canal de píxeles BGRA por FFI en lugar de `frames.*` en JPEG | hueco claro (decidido, ADR-021, 8) | 3 | ADR-021 |
| L1 | Biblioteca | Marcar la mejor toma desde la lista: `record.markBest` exige sesión de Grabar; falta `library.markBest` que avise a Grabar/estudio si el tema está abierto | hueco claro | 1 | b:1 |
| L2 | Biblioteca | Borrar un tema abierto en estudio: `library.trash`/`delete` deben cerrar la sesión y soltar ficheros (en Windows, bloqueo NTFS sin confirmar; lo prueba Jorge) | hueco claro | 1 | b:2 |
| L3 | Biblioteca | `ProjectSummary` sin `separationError`; falta el campo para el texto del fallo en la lista | hueco claro | 1 | b:3 |
| L6 | Biblioteca | Selección de tema (`backingTarget`): se limpia al borrar y si el id desaparece de `library.list` | interfaz en Dart | 1 | b:6 |
| L7 | Biblioteca | Búsqueda, agrupación por artista y plegado; agrupación en preferencias locales; paridad de plegado y orden con `LibraryGrouping` | interfaz en Dart | 1 | b:7 |
| L11 | Biblioteca | Carátulas y fotos: se leen por ruta de fichero (`Image.file`), no por `mediaBase` (antes «decisión de Jorge») | interfaz en Dart (resuelto) | 1 | b:11 |
| L12 | Biblioteca | Importar: filtrar `wav`/`flac`/`mp3` antes de llamar a `import.file` | interfaz en Dart | 1 | b:12 |
| K2 | Backing | Imán de bordes de sección a acorde y ⌥ a compás: `previewSectionEdge` y `updateSection` deben dar el resultado de `SectionEdgeDrag`; test que lo compare | hueco claro | 2 | k:D-2 |
| K3 | Backing | Bucle por arrastre con ajuste a acorde o compás: falta `snap` en `study.setLoop`; test de paridad | hueco claro | 2 | k:D-3 |
| K4 | Backing | Monitores de teclado (Espacio, Supr, Esc, ⌥) | interfaz en Dart | 2 | k:D-4 |
| K7 | Backing | Formas de acorde con capo: falta método (`ChordShapes`) | hueco claro | 2 | k:D-7 |
| K8 | Backing | Nombre de acorde transpuesto y tonalidad mostrada: el puente da el nombre sin transponer | hueco claro | 2 | k:D-8 |
| K9 | Backing | «Sin guitarras» como N `study.setMix`; solo si `kind == "guitar"` | interfaz en Dart | 2 | k:D-9 |
| K12 | Backing | `study.error` declarado y nunca emitido: emitirlo o quitarlo del DTO y del cliente | hueco claro | 2 | k:D-12 |
| TB1 | Tablatura | Errores de alphaTab (`webError`): aviso de la pantalla con mensaje genérico y detalle | interfaz en Dart | 2 | t:D1 |
| TB2 | Tablatura | Rehacer: Ctrl+Y además de Ctrl+⇧+Z en Windows; ⇧⌘Z en Mac | interfaz en Dart | 2 | t:D2 |
| TB3 | Tablatura | Cursor: `study.position` (30 Hz) interpolado en un `Ticker`; sin temporizador propio | interfaz en Dart | 2 | t:D3 |
| TB4 | Tablatura | Teclas por tecla lógica y carácter (teclados no US); lo prueba Jorge | interfaz en Dart | 2 | t:D4 |
| TB5 | Tablatura | Etiqueta «Fuente» por clave ARB | interfaz en Dart | 2 | t:D5 |
| TB6 | Tablatura | Exportar `.gp`: Dart abre el diálogo (`file_selector`) y pasa `path` a `tab.export` (antes «decisión de Jorge») | interfaz en Dart (resuelto) | 2 | t:D6 |
| TB7 | Tablatura | Songsterr oculto: sondeo, tope y serialización de cargas los ejecuta el anfitrión; comprobar que el de Flutter cumple los puntos 1-6 del contrato | se mide (requisito de anfitrión) | 2 | t:D7 |
| TB9 | Tablatura | Eventos del lienzo reenviados a `tab.*` con coalescencia en cliente | interfaz en Dart | 2 | t:D9 |
| TB10 | Tablatura | `tab.open`, `tab.songsterr.accept` y `tab.songsterr.automatic` deben arrancar la cola de transcripción | hueco claro | 2 | t:D10 |
| TB11 | Tablatura | La hoja de Songsterr se cierra en el cliente tras `accept` y `automatic` | interfaz en Dart | 2 | t:D11 |
| GR1 | Grabar | `record.setPunch {enabled:true}` debe elegir la mejor toma si no hay toma elegida | hueco claro | 3 | g:G1 |
| GR2 | Grabar | Nivel de guitarra: Dart lo lee de `audio.levels` y llama a `audio.setMeters` al entrar y salir | interfaz en Dart | 3 | g:G2 |
| GR5 | Grabar, visor | Reproductor de vídeo de Flutter en Windows: HEVC y `playbackRate` fino; mensaje de HEVC en Dart | se mide (P9) | 3 | g:G5 |
| GR6 | Grabar | Imán de ±1,5 dB del Master en la vista | interfaz en Dart | 3 | g:G6 |
| GR7 | Visor | Sincronía vídeo-audio sin reloj común; el seguidor en Dart ya no es el plan (decisión 9 enmendada) | se mide (P9) | 3 | g:G7 |
| GR10 | Grabar | `record.pollCamera` expuesto (SwiftUI pollCamera cada 2 s, RV:99,130); aprobado por Jorge 25/11 | núcleo (resuelto) | 3 | g:G10 |
| GR8 | Visor | Audio del visor en el Mac: SwiftUI usa la salida del sistema, `AppCore` la del perfil. Resuelto por robustez: la del perfil en las dos plataformas (un solo camino de audio); Jorge lo comprueba de oído | interfaz en Dart (resuelto) | 3 | g:G8 |
| MO1 | Montaje | Cancelar la exportación: `cancelled` se trata como reposo | interfaz en Dart | 4 | m:D1 |
| MO2 | Montaje | `reveal` debe seleccionar el fichero exportado, no abrir la carpeta (depende de T3 en Windows) | hueco claro | 4 | m:D2 |
| MO3 | Montaje | Fila «Formato» solo si `export.options.codecs.count > 1` | interfaz en Dart | 4 | m:D3 |
| MO4 | Montaje | Vista previa por píxeles: fps por defecto y sincronía (el canal `montage` ya va a 60 fps) | se mide (P9, prueba 3) | 4 | m:D4 |
| MO5 | Montaje | `audioError` sin mostrar en SwiftUI y sí en la web. Resuelto por fiabilidad: se muestra como aviso bajo la cabecera | interfaz en Dart (resuelto) | 4 | m:D5 |
| MO6 | Montaje | Fotograma de encuadre: `Image.file` con ruta relativa al tema | interfaz en Dart | 4 | m:D6 |
| MO7 | Montaje | «Automática ({parte})»: el snapshot debe traer el id de la parte automática | hueco claro | 4 | m:D7 |
| MO8 | Montaje | «Finder» / «Explorador»: texto por plataforma en ARB | interfaz en Dart | 4 | m:D8 |
| AJ1 | Ajustes · Vídeo | Cámaras reales del Mac por `AppCore` (`video.cameras` vacío): es A1 | hueco claro | 3 | a:1, A1 |
| AJ2 | Ajustes · Biblioteca | Cambio de carpeta en caliente: `host.chooseFolder` + `library.relocate`, no `host.pickProjectsFolder`; tras mover se queda en Ajustes; es B2 | hueco claro | 1 | a:2, B2 |
| AJ3 | Ajustes · Audio | Cancelar calibración: sin botón; cerrar la hoja con la medida en marcha envía `audio.cancelCalibration` (antes «decisión de Jorge») | interfaz en Dart (resuelto) | 3 | a:3 |
| AJ4 | Ajustes · Audio | Textos del núcleo en español y coma decimal: es N1 (por código y argumentos) | hueco claro (decidido) | 1 | a:4, N1 |
| AJ5 | Ajustes · Vídeo | Previa rotada por Flutter (horario); sin selector de giro en Ajustes | interfaz en Dart | 3 | a:5 |
| AJ6 | Ajustes · Vídeo | Selector de códec oculto si `codecs.length == 1` (Windows) | interfaz en Dart | 3 | a:6 |
| AJ8 | Ajustes · Audio | Tarjeta de salida de la barra lateral deducida de `audio.settings` y `audio.devices` (la implementa la carcasa) | interfaz en Dart | 3 | a:8 |
| FC1 | Grabar, Montaje | `FrameChannel` no da el tamaño del fotograma ni avisa del cambio de `textureId`; `TfVideoSurface` recibe `frameSize` por parámetro | hueco claro | 3, 4 | resolver en Grabar B (ola 3) y Montaje P2 (ola 4) |
| AJ9 | Ajustes · Vídeo | Texto del botón de permisos de cámara en Windows: variante por plataforma en ARB (por analogía con «Finder»/«Explorador»; no lo cita `decisiones-interfaz.md`) | interfaz en Dart | 3 | a:9 |

Descartados (sin trabajo, constan por si se vuelve a preguntar):

- L4 · `videoCount` solo en `library.project`: Dart la llama al abrir el diálogo de eliminar (`b:4`).
- L5 · Foto de artista como `data:` hasta 2 MB: se mantiene (`b:5`).
- L8 · Duplicados: la alerta del Mac sirve para ficheros y enlaces (`b:8`).
- L9 · Textos de error de enlace y lista: los pone el núcleo (`b:9`).
- L10 · Indicador de lista en la cabecera: ya en `PlaylistSnapshot.indicator` (`b:10`).
- L13 · Cancelar enlace con `link.cancel`/`playlist.cancel`, no `jobs.cancel` (`b:13`).
- K1 · A/B de tomas: código muerto, no se porta (`k:D-1`).
- K5 · `gainDB` del metrónomo: sin interfaz (`k:D-5`).
- K6 · Bucles guardados (`study.open.loops`): sin interfaz (`k:D-6`).
- K10 · Edición de secciones en dos tiempos: ya cubierta por el puente (`k:D-10`).
- K11 · `study.setChord` con `label`: sin impacto (`k:D-11`).
- TB8 · El lienzo no usa SoundFont: no cargarlo en el WebView (`t:D8`).
- TB12 · Métodos sin uso en Windows: informativo (`t:D12`).
- GR3 · `calibrationValid` sale de `audio.*`: nada que añadir (`g:G3`).
- GR4 · Selector de cámara en Grabar: no se añade, la cámara se elige en Ajustes (`g:G4`).
- GR9 · `record.cancel` sin llamadas: no se implementa (`g:G9`).
- AJ7 · Guardado del perfil repartido entre `audio.setSettings` y `video.setSettings`: informativo (`a:7`).
- AJ10 · «Verificando/Instalando» no viene en `models.progress`: informativo (`a:10`).

Montaje D9 (M1) no se repite: ver la fila M1 de los heredados.
