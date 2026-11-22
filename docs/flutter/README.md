# Fase 7f · Interfaz única en Flutter

Índice de la documentación de la fase. Cada pieza se lee sola; nadie necesita leerlas todas.

| Fichero | Qué contiene | Quién lo lee |
| --- | --- | --- |
| [../adr/ADR-021.md](../adr/ADR-021.md) | Las 25 decisiones de Jorge, lo descartado, riesgos y condición de paso | Orquestador, una vez |
| [../plan.md](../plan.md) § «Fase 7f» | Olas, casillas y condición de paso | Orquestador, al empezar cada sesión |
| [orquestador.md](orquestador.md) | Agentes, ciclo de una ola, plantilla de encargo, lista de validación, cuándo preguntar | Orquestador |
| [arquitectura.md](arquitectura.md) | `AppCoreFFI`, hilos, canal de fotogramas, estructura de `FlutterApp/`, reglas de Dart, WebView, vídeo, arranque y empaquetado | Todos (la sección que cite el encargo) |
| [contrato.md](contrato.md) | Métodos, eventos y tipos del puente por área; servicios de anfitrión; hilos | Agentes, solo su área (`grep -n '^## '`) |
| [contrato-tipos-a.md](contrato-tipos-a.md) | Tipos de `link`, `playlist`, `audio`, `frames` y `video.preview` | Agentes de Biblioteca, Ajustes y Grabar |
| [contrato-tipos-b.md](contrato-tipos-b.md) | Tipos de `study`, `tab` y `tab.songsterr` | Agentes de Backing y Tablatura |
| [contrato-tipos-c.md](contrato-tipos-c.md) | Tipos de `record`, `takeview` y `montage` | Agentes de Grabar y Montaje |
| [contrato-anfitrion-hilos.md](contrato-anfitrion-hilos.md) | Servicios de anfitrión (`HostServices`, `HiddenPageLoading`) e hilos | Agente del anfitrión y de `AppCoreFFI` |
| [mensajes-nucleo.md](mensajes-nucleo.md) | Inventario de textos que el núcleo envía en español y su código propuesto (Router a RecordMethods); continúa en `mensajes-nucleo-3.md` | `tf-implementer` y `tf-flutter-mech` en el paso a códigos |
| [mensajes-nucleo-3.md](mensajes-nucleo-3.md) | Continuación del inventario de textos del núcleo (en curso) | Ídem |
| [mensajes-nucleo-paquetes.md](mensajes-nucleo-paquetes.md), [mensajes-nucleo-paquetes-2.md](mensajes-nucleo-paquetes-2.md) | Inventario de textos de los paquetes (en curso) | Ídem |
| [tokens-componentes.md](tokens-componentes.md) | Tokens del tema, kit de widgets, iconos, fuentes, ventana | Ola 0; después, consulta |
| [decisiones-interfaz.md](decisiones-interfaz.md) | Resolución de las preguntas de las fichas; manda sobre las «Dudas para Jorge» de cada ficha y deja las dudas reales | Orquestador y agentes de pantalla |
| [pantallas/](pantallas/) | Fichas por pantalla (plantilla en `_PLANTILLA.md`): `biblioteca`, `backing`, `tablatura`, `grabar`, `montaje`, `ajustes` | El agente de esa pantalla |
| [desvios.md](desvios.md) | Registro de desvíos de núcleo, su regla y los nuevos por pantalla y ola | Orquestador, `tf-implementer`, `tf-docs` |

Cada ficha de pantalla va en 2 o 3 ficheros de `pantallas/`: `<pantalla>.md` (visual y estados), `<pantalla>-contrato.md` (apartados 5 y 9: métodos del puente y desvíos) y `<pantalla>-interaccion.md` (apartados 6-8). Hay `-interaccion.md` en `backing`, `tablatura` y `grabar`; `biblioteca`, `montaje` y `ajustes` llevan menos ficheros (`ajustes.md` es la ficha completa; `biblioteca-contrato.md` y `montaje-contrato.md` existen aparte). Si una ficha pide algo que `decisiones-interfaz.md` ya resolvió, vale lo de `decisiones-interfaz.md`.
| [../probes/P9-flutter.md](../probes/P9-flutter.md) | Prueba de viabilidad: pruebas, umbrales, respaldos y resultados | Orquestador y agentes de P9 |
| `ref/<pantalla>/<estado>.png` | Capturas de referencia de SwiftUI (se generan en la ola 0) y `DIFERENCIAS.md` por pantalla | Orquestador al validar |

Reglas que no cambian en toda la fase:

1. Comportamiento = `AppCore`. Aspecto = SwiftUI. `WinApp/Web` = ejemplo de uso del puente.
2. Port 1:1. Lo que no esté en la ficha ni en SwiftUI es una pregunta a Jorge, con alternativas y una recomendada.
3. `App/Sources`, `WinApp/Web` y `Tools/webdev` están congelados hasta que se borren en la ola 5.
4. Opus orquesta y valida; implementan Sonnet y Haiku.
5. Nunca se prueba con la carpeta real de proyectos.
