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
| Preferencias de interfaz (vista Temas/Artistas de la Biblioteca, idioma) | `shared_preferences` con `SharedPreferencesAsync`; regla 9 de `arquitectura.md` ampliada de «solo el idioma» a «preferencias de interfaz que no van al perfil del núcleo» (Jorge, 24/11/2026). | Paridad con `@AppStorage` de SwiftUI sin plugin nuevo; el perfil del núcleo es del equipo, no de la interfaz. |

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
| Calibración: botón «Cancelar» durante la medida | No se añade botón y la hoja no se cierra mientras mide, como SwiftUI. `audio.cancelCalibration` se envía solo si la hoja se destruye de todos modos (cierre de ventana, cambio de pantalla). |
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

## Revisión ampliada: lo que se decidió sin preguntar

Repaso del 22/11/2026 con el criterio 0. «Se mantiene» = revisado y sin cambio.

| Decisión | Resolución | Por qué |
| --- | --- | --- |
| ABI: texturas | El runner registra la textura y pide el fotograma al núcleo (`tf_texture_host`, `tf_frame_copy`); el núcleo no recibe el registro de Flutter. Propuesta hasta P9, prueba 3. | El paquete Swift no enlaza el motor de Flutter; subir de versión no toca el núcleo. |
| Umbral de descartes del canal de fotogramas en Windows | ≤ 3 por minuto a 30 fps con `GpuSurfaceTexture`; 0 en el Mac. Respaldo `PixelBufferTexture`; copia BGRA descartada a 1080p. | Jorge, 23/11/2026, con la medida de P9 (7f): los descartes son peticiones tardías del motor, iguales en los dos caminos. |
| ABI: propiedad de búferes | `tf_core_send` copia antes de volver (búfer de Dart); lo que entrega el núcleo es suyo hasta `tf_core_free`, que Dart llama siempre. Id de textura `int64`. | Sin vidas compartidas entre los dos lados. |
| ABI: cierre | `tf_core_shutdown` asíncrono, con evento `core.shutdown` y un tope sobre el cierre entero. | Síncrono se bloquea en el Mac (`closeStudy` salta a `@MainActor` desde el hilo principal); hoy solo `jobs.shutdown()` tiene tope. |
| ABI: orden de arranque | `send` y `host` asignados antes de `Bridge.start()`. | `WinApp` lo hace al revés y puede perder un evento. |
| `{hostRequest}` / `{hostResponse}` | Se mantiene. Los `host.*` del puente no cambian. | Un solo camino para los diálogos; el núcleo conserva su lógica (primer arranque, mover biblioteca). |
| Límite de 15 s de `CoreClient` | Por defecto 15 s; excepciones en una tabla por método con los valores de la web; las llamadas que esperan a un diálogo, sin límite. Lista en `arquitectura.md`, regla 3. | La web tiene 16 excepciones repartidas por el código; con el límite fijo fallarían calibración, importación y mover biblioteca. |
| Ficheros ≤ ~300 líneas | Se mantiene, como orientación. | Un encargo cabe en el contexto de un agente Sonnet. |
| Estructura de `FlutterApp/` | Se mantiene. | — |
| Umbrales de P9 | Ida y vuelta: se añade p99 < 16 ms a la mediana < 5 ms. 16 ms de bloqueo y 300 ms tras salto, se mantienen. | Una mediana sola esconde los tirones. |
| Contenido de las olas | Se mantiene. | — |
| Commits | Pequeños y frecuentes con push (Jorge); ADR-021 decisión 24, `orquestador.md` y `plan.md` corregidos. | Decían «un commit por ola, sin push». |
| Agentes `tf-flutter*` | Se mantienen. | No citan nada de lo enmendado. |

## Cerradas en la revisión de coherencia (22/11/2026)

Dudas que devolvieron las auditorías de fichas y contratos (`Temp/flutter/audit-*.md`).

| Pregunta | Resolución | Criterio |
| --- | --- | --- |
| Opcionales: `null` explícito o clave ausente (`path` de `PickedFileResult`, `artistPhoto`…) | Regla general de los DTO de Dart: ausente y `null` se leen igual; al enviar, Dart omite la clave. | Robustez: el núcleo hace las dos cosas según el tipo. |
| `study.setTranspose` con `semitones` y `fineCents` a la vez | Sin regla: el núcleo acepta ambos; Dart envía lo que cambie el control. | — |
| Textos de audio y calibración del núcleo (`label`, `hint`, `rows`, `calibrateBlock`, `rateMismatch.*`, `calibrateInstructions`) | Por código y argumentos, como todo texto que genera el núcleo (decisión 16). | Diseño ya decidido. |
| «Abrir Ajustes del Sistema» en Windows | Variante por plataforma en ARB: «Abrir Configuración». Nombre de Windows sin verificar en fuente oficial. | Documentación. |
| Hoja de calibración: ¿se puede cerrar midiendo? | No, como SwiftUI. `audio.cancelCalibration` se envía solo si la hoja se destruye de todos modos (cierre de ventana, cambio de pantalla). | 1:1 + robustez. |
| `video.cameras` y `video.settings` vacías en el Mac sin `--camera`/`--audio simulated` | Hueco claro de núcleo (enumerar no toca señal): `tf-implementer`, antes de la ola 3. | Desvíos. |
| Selector de idioma: ancho y nota | Ancho por captura en la revisión de la ola 1. Sin nota. | Función nueva, mínima. |
| Tablatura: botones de batería (`pieceName(p).capitalized`) | Una clave ARB por pieza, ya con mayúscula; no se capitaliza en código. | Capitalizar depende del idioma. |
| Tablatura: «Sin bucle» conserva el ancla, ¿cómo? | Núcleo: si `tab.span` al limpiar borra también el ancla, es hueco claro (variante que la conserva), ola 2. | Desvíos. |
| Tablatura: reloj numérico del transporte | Misma fuente que el cursor (`study.position` interpolado en el `Ticker`); el texto solo se repinta cuando cambia el valor mostrado. | Un solo reloj. |
| Tablatura: `selectionSummary` y `headerSummary` | Los compone Dart con los datos del estado; si hoy llegan como texto del núcleo, pasan a código y argumentos. | Decisión 16. |
| Tablatura: `D` y `U` con Bloq Mayús | Atajos por tecla lógica y estado real de ⇧ (`SingleActivator`), no por mayúscula del carácter. | Documentación (misma fila que «Teclas por `keyCode`»). |
| Backing: rueda sobre la tira de acordes; cerrar el popover al perder el foco la ventana; Intro en «Añadir parte» | Solo existen en la web: no se portan. Queda el scroll por defecto de Flutter. | 1:1. |
| Backing y Grabar: cadencia de las llamadas durante un arrastre (borde de sección, punch) | Sin periodo fijo: una sola llamada en vuelo por arrastre, la última posición gana, y una final al soltar. Vale para todo arrastre que consulte al núcleo. | Robustez: no acumula cola si el núcleo va lento ni añade retardo si va rápido. |
| Backing: fader con teclado | Lo que tenga SwiftUI: si solo expone la acción ajustable de accesibilidad, `Semantics(onIncrease/onDecrease)` con el mismo paso y sin teclas propias. | 1:1. |
| Hojas: autofoco, trampa de Tab, devolver el foco | Comportamiento por defecto de las rutas de diálogo de Flutter; autofoco donde SwiftUI lo da. Sin trabajo extra. | Documentación. |
| Grabar: campo de milisegundos del desfase | Confirma como SwiftUI; acepta coma o punto decimal. | 1:1 + robustez (teclado español). |
| Tema: `.fontWeight(.semibold)` sobre la fuente heredada (¿se pinta 600 o 400?); separación de 14 entre filas de `SettingsGroup`; ancho de los botones de carpeta y lápiz | Manda lo que se ve: se fija con las capturas de referencia de la ola 0 y el token lleva el peso y la medida de la captura. | 1:1 (base visual = lo que pinta SwiftUI). |
| Songsterr: un slot de voz saldría con `role: "guitar"` y `kind: "vocal"` | Se comprueba con los fixtures de `tab.songsterr.*` en la ola 2; si ocurre, hueco claro de núcleo. Los ids reales de `TabSource` salen de esos mismos fixtures. | Desvíos. |
| `host.preview.show`: unidades del rectángulo | Píxeles lógicos desde la esquina del contenido de la ventana. En Flutter la vista previa es un `TfWebView` dentro de la hoja: la petición `showPreview` solo le da la URL (ya validada por el núcleo) y el rectángulo no se usa para colocar nada. | Robustez: sin ventana nativa superpuesta que sincronizar. |
| Canal entre Dart y `tf-bridge.js` | El canal de mensajes JS del paquete de WebView, oculto tras `TfWebView`. Lo fija P9, prueba 4. | Se mide. |
| `frames.montage`: ¿BGRA o JPEG? | El núcleo emite JPEG en base64 salvo que el anfitrión registre `setMontageFrameSink`; `AppCoreFFI` lo registra y entrega a la textura. | Código (`MontageMethods.swift:762-766`). |
| Tablatura: texto genérico de `tabWebError` | El literal que use SwiftUI para ese fallo; si no hay, «No se pudo mostrar la tablatura.» Se fija en la ola 2. | 1:1. |
| `core_ids_not_uuid` con dos textos (`id`/`takeId` y `projectId`/`takeId`) | Un solo código con argumentos `first` y `second` (los nombres de parámetro). | Un código por fallo, no por punto de llamada; el ARB tiene una sola clave. |

## Cerradas por Jorge al empezar la ola 0 (24/11/2026)

| Pregunta | Resolución |
| --- | --- |
| Iconos: licencia y origen | Se portan los `path` de Lucide (licencia ISC, mismo estilo de trazo 24×24, `stroke-width 2`, extremos redondos que `WinApp/Web/icons.js`) a `theme/icons.dart` como `Path`, sin plugin, con la licencia en `assets/licenses/`. Los que Lucide no tenga se dibujan con el mismo trazo. Sustituye a «27 de la web + 28 a mano». |
| Iconos: trazo o relleno | Trazo. |
| Acento de `TfCheckbox`, `TfSegmented` y los `TfSwitch` de Ajustes · Vídeo (hoy acento del sistema, azul) | `TF.accent` naranja en todos, como el slider del visor. |
| `TfApplyButton` | Variante parametrizada de `TfPrimaryButton` (alto 28, body 13 semibold, sin estado deshabilitado propio). |
| `TfProgress` y `TfAccentBar` | Se quedan separados (1:1). |
| `TfPopover` | Sin flecha: `OverlayPortal`, fondo `card`, borde `line`, radio 10. |
| `TfMenu` | Aspecto propio: fondo `card`, radio 10. |
| `TfScroll` | Barra fina con `fieldLine` y `muted`. |
| Colores casi iguales (`C8433A`/`E5534B`, `0B0C0E`/`0F1113`, `4CC38A`/`6FD99E`) | No se funden: cada hex es un token con nombre. |
| Separador decimal de `Fmt.db` y `Fmt.rate` | Según el idioma (coma en español, punto en inglés) con `intl`, coherente con los mensajes del núcleo (`decimalPattern`). |

## Cerradas durante la ola 1 (25/11/2026)

| Pregunta | Resolución |
| --- | --- |
| Carpeta propuesta del primer arranque | La da el núcleo por plataforma, `app.info.proposedProjectsFolder` (Jorge, 25/11/2026). |
| `TfSettingsGroup.note` | Opcional, y las rutas se truncan al medio en el kit (Jorge, 25/11/2026). |
| «Abrir» del diálogo de duplicado | Cambia a la sección Biblioteca (Jorge, 25/11/2026). |
| Alertas de biblioteca | Cola FIFO con una sola visible (`library_alerts_host.dart`) (Jorge, 25/11/2026). |
| Tamaños de letra | Ninguno numérico fuera de `theme/`: tokens `TfSize.fontNN`, en todas las olas (Jorge, 25/11/2026). |
| Medidas propias de pantalla | Constantes con nombre en `features/<f>/<f>_metrics.dart` (orquestador, 25/11/2026); el test de literales solo vigila color, fuente, radio y padding. |
| Meses de `library_format.dart` | Literales es/en: `intl` en español exige `initializeDateFormatting` en `main` (orquestador, 25/11/2026). |
| Iconos `.fill` de SF Symbols | `TfSecondaryButton.iconFilled` (orquestador, 25/11/2026). |
| Segmentado Temas/Artistas e Idioma | Segmento activo naranja, ya decidido en [tokens-componentes.md](tokens-componentes.md) (`TfSegmented`) (Jorge, 24/11/2026). |

## Dudas reales, para Jorge

Ninguna abierta. La rama `fase-7f` existe y la documentación está subida.

Lo demás quedó resuelto arriba. Jorge puede revocar cualquier fila; las que cambian algo que hoy ve o oye en el Mac son: salida de audio del visor, Supr en Backing, aviso de `audioError`, acento del slider del visor.
