# Fase 7f · Preguntas de las fichas, resueltas

Las fichas de `pantallas/` y el relevo de planificación dejaron unas 45 preguntas. Jorge (22/11/2026): se resuelven con la documentación oficial y el criterio de ADR-021 (robusto, fiable, menor overhead); a él solo le llegan las dudas reales. Este fichero es el resultado. Manda sobre el apartado «Dudas para Jorge» de cada ficha.

Criterios, por orden: (0) **robustez, fiabilidad y rendimiento mandan sobre cualquier ADR previo, incluida la regla 1:1** (Jorge, 22/11/2026); (1) regla 1:1 de ADR-021 (aspecto e interacción = SwiftUI; comportamiento = `AppCore`); (2) regla de desvíos de [desvios.md](desvios.md) (hueco claro → se arregla en `AppCore` con test; estado solo de interfaz → Dart); (3) documentación oficial; (4) lo que solo se sabe midiendo va a P9 o a la ola.

## Cerradas por robustez y fiabilidad (por encima del 1:1)

| Pregunta | Resolución | Por qué |
| --- | --- | --- |
| Montaje: `audioError` no se muestra en SwiftUI | Se muestra, como en la web: línea de aviso bajo la cabecera. | Un fallo de audio silencioso no es fiable. |
| Backing: Supr con el popover de sección abierto y el foco fuera del nombre | No borra la sección (como la web). | Evita un borrado accidental. |
| Visor de tomas en el Mac: salida de audio | La del perfil, por `AppCore`, igual que en Windows. Deja de sonar por la salida del sistema. | Un solo camino de audio y un solo reloj en las dos plataformas; Flutter solo habla con `AppCore`. Jorge lo comprueba de oído en la ola 3. |
| P9: el PC «una sola vez, al final» | Dos pasadas: primero solo hilos de Windows y compilación de las candidatas de WebView (prueba 7, primera parte), en cuanto la prueba 2 esté verde en el Mac; el resto al final. | Fallar rápido: los hilos son el riesgo mayor y pueden cambiar la arquitectura (proceso aparte). |
| Nombres por defecto que el núcleo guarda en español (`Guitarra`, secciones, tomas) | El núcleo recibe el idioma al arrancar (`LaunchOptions`) y genera los nombres nuevos en ese idioma; lo ya guardado no se toca. «Selección» (`TabService:42`) deja de compararse por texto: pasa a ser una marca. | Comparar por un texto traducible es frágil. |
| Mensajes: código del error de origen | `AppCore` conserva el código del paquete que falló en vez de aplanarlo a texto. | Diagnóstico fiable y traducción completa. |

Evidencia oficial: `Temp/research/7f-ui-facts.md` (no versionado). «Sin verificar» = la fuente oficial no se pudo leer; se comprueba en la ola indicada.

## Cerradas por la regla 1:1

| Pregunta | Resolución |
| --- | --- |
| Tablatura: icono en el aviso y botón «Reintentar» en el fallo | No se añaden: SwiftUI no los tiene. |
| Tablatura: zoom y menú contextual | No hay: SwiftUI no los tiene. |
| Tablatura: «Sin bucle» y Esc, ¿borran el ancla del tramo? | Como SwiftUI: el ancla se conserva. |
| Grabar: selector de cámara | No: ni SwiftUI ni la web lo usan (`record.setCamera` existe pero nadie lo llama). La cámara se elige en Ajustes. |
| Grabar: tras intercambiar entrada y salida del punch, qué borde se mueve | Como SwiftUI (`PunchTimeline.swift:85`): la entrada. |
| Grabar: menú de toma | Como SwiftUI. |
| Grabar y visor: «Borrar» frente a «Eliminar» | Cada texto, literal de SwiftUI. |
| Grabar: dos rojos sueltos (`E5534B`, `C8433A`) | Dos tokens con nombre. |
| Calibración: botón «Cancelar» durante la medida | No se añade botón. Cerrar la hoja con la medida en marcha envía `audio.cancelCalibration` (comportamiento de `AppCore`, como la web). |
| Ajustes: tras mover la carpeta de proyectos | Se queda en Ajustes, como SwiftUI. |
| Backing: bucles guardados (`study.open.loops`), `gainDB` del metrónomo | Sin interfaz: SwiftUI no la tiene. |
| Backing: A/B, `RecordButton`, `ComparePanel`, `TakeChannel` | Código muerto: no se porta. |
| Backing: ⇧+Espacio | No se porta: solo existe en la web. |
| Montaje: qué se ve al cancelar la exportación | Como SwiftUI: vuelve a reposo. |
| Montaje: fila «Formato» | Solo donde el núcleo ofrece más de un formato. |

## Cerradas por la regla de desvíos

Hueco claro: `tf-implementer` lo arregla en `AppCore` con test y fixture en la ola de la pantalla.

| Pregunta | Resolución |
| --- | --- |
| Backing: imán del arrastre de bordes y del bucle, ¿núcleo o Dart? | Núcleo. Una sola implementación con test que compare con `SectionEdgeDrag`. |
| Backing: nombre de acorde transpuesto y formas | Núcleo: el puente entrega nombre transpuesto y un método de formas (`ChordShapes`). |
| Biblioteca: marcar la mejor toma desde la lista | Núcleo: método nuevo (hoy `record.markBest` exige sesión abierta). |
| Biblioteca: borrar un tema abierto en estudio | Núcleo: `library.trash`/`delete` cierran la sesión. |
| Biblioteca: `separationError` en `library.list` | Núcleo. |
| Grabar: `record.setPunch` selecciona la mejor toma | Núcleo. |
| Tablatura: `tab.open` no arranca la cola de transcripción | Núcleo. |
| Montaje: «Automática» | Núcleo. |
| Montaje: «Mostrar» abre la carpeta y no el fichero | Núcleo: selecciona el fichero (`NSWorkspace.activateFileViewerSelecting`; `SHOpenFolderAndSelectItems`). `url_launcher` no sabe hacerlo. |
| Biblioteca, Backing, Tablatura: selección, búsqueda, plegado, agrupación, monitores de teclado | Dart. Es estado efímero según la documentación de Flutter. |
| Grabar: nivel de entrada de guitarra | Dart lo lee de `audio.levels`; no se duplica en `record.levels`. |
| Mensajes: `JobInfo.text` y textos de fase | Por código y argumentos (decisión 16); el texto se compone en Dart. |

## Cerradas por documentación oficial

| Pregunta | Resolución | Evidencia |
| --- | --- | --- |
| Rehacer con Ctrl+Y | Windows: Ctrl+Y además de Ctrl+⇧+Z. Mac: ⇧⌘Z, sin Ctrl+Y. El texto de ayuda «⌘Z» lleva variante por plataforma. | Microsoft Learn, aceleradores de teclado. Convención de Mac sin verificar en el HIG. |
| Teclas por `keyCode` o por carácter (teclados no US) | Atajos por tecla lógica (`SingleActivator` usa `LogicalKeyboardKey`); cifras y letras de edición por `KeyEvent.character`. Se prueba con teclado español en el PC. | API de `SingleActivator` y `KeyEvent`. |
| Números dentro de los mensajes del núcleo | Los argumentos viajan como número; los formatea `gen-l10n` (`type: double`, `format: decimalPattern`). Corrige de paso el `%g` con punto de `Services.swift:181`. | Guía de internacionalización de Flutter. Sin verificar del todo: releer en la ola 0. |
| Exportar `.gp` (`tab.export` sin ruta devuelve `saved:false`) | Dart abre el diálogo con `file_selector` (`getSaveLocation`) y llama a `tab.export` con `path`. No se implementa `saveFile` en el anfitrión. | pub.dev `file_selector` (flutter.dev). En Mac con sandbox, entitlement `user-selected` de lectura y escritura. |
| Rejilla de artistas (`GridItem.adaptive` 160-220) | Delegado propio que respete mínimo y máximo; `SliverGridDelegateWithMaxCrossAxisExtent` no tiene mínimo. Se comprueba con capturas. | API del delegado. |
| «Finder», «Papelera», «Explorador» | Variante de texto por plataforma en ARB: «Explorador de archivos» y «Papelera de reciclaje» en Windows. | Nombres de Windows sin verificar en fuente oficial. |
| Slider del visor con el acento del sistema | `TF.accent`. Flutter no tiene API oficial para el acento de macOS y un plugin solo para esto no compensa. Desvío visual aceptado; se enseña a Jorge en la revisión de la ola 3. | API de `SystemColor`: solo web. |
| Carátulas: `mediaBase` o disco | Por ruta de fichero (`Image.file`), como fija `arquitectura.md`. La foto de artista sigue llegando como `data:` hasta 2 MB. | — |
| Hoja de Songsterr de 1320 px con ventana mínima de 1100 | Flutter estable es de una sola ventana: la hoja no puede salirse. Ancho = el menor entre 1320 y la ventana menos márgenes; la lista conserva 612 y la vista previa ocupa el resto. Se comprueba con captura a 1100. | Recorte sin verificar en fuente oficial; multiventana es experimental. |
| Flechas en sliders y barra de posición | Comportamiento por defecto de Flutter con foco; sin trabajo extra. | Sin verificar; se mira en la ola 2. |

## Cerradas por diseño ya decidido

| Pregunta | Resolución |
| --- | --- |
| Tolerancia del seguidor de vídeo (3 ms o medio fotograma) | Sin objeto: el seguidor en Dart ya no es el plan (decisión 9 enmendada). Medio fotograma es el umbral de P9. |
| Cursor de tablatura a 20 o 30 Hz | Ni uno ni otro: sale de `study.position` (30 Hz, del núcleo) interpolado en un `Ticker` por fotograma. Sin temporizador propio. |
| Errores de alphaTab (`webError`) | Dart los muestra en el aviso de la pantalla: mensaje genérico traducido y el texto de la página como detalle. Los textos de dentro de la página no van a ARB. |
| Biblioteca sin estado «cargando» | No se muestra «Todavía no hay temas» hasta recibir el primer `library.list`. |
| Texto de «sin permiso de cámara» en Windows; mensajes de bloqueo y error | Llegan del núcleo por código (decisión 16). |
| Sitio del selector de idioma | Grupo «Idioma» al final de la pestaña Biblioteca de Ajustes, control segmentado. Función nueva sin referencia; se enseña a Jorge en la revisión de la ola 1. |

## Se resuelven midiendo

| Pregunta | Dónde |
| --- | --- |
| Mensajes de fase y error de Flutter encima del WebView | P9, prueba 4 (Mac) y 7 (PC). |
| Cadencia de la vista previa de Montaje | P9, prueba 3. El canal `montage` ya entrega a 60 fps. |
| Espejo de la cámara | SwiftUI no lo fija y la documentación no aclara el valor por defecto en macOS. Captura de SwiftUI con cámara real en la ola 3 (hardware de Jorge); la textura replica lo que salga. |
| `framingFrame` en el Mac (desvío M1, resuelto en código) | Jorge, con vídeo real, en la ola 4. |

## Dudas reales, para Jorge

1. Rama `fase-7f` y commit de la documentación (regla del proyecto: a mitad de fase, solo si Jorge lo pide).

Lo demás quedó resuelto arriba. Jorge puede revocar cualquier fila; las que cambian algo que hoy ve o oye en el Mac son: salida de audio del visor, Supr en Backing, aviso de `audioError`, acento del slider del visor.
