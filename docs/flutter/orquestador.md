# Fase 7f · Guía del orquestador

Para la sesión Opus que dirige la fase. El orquestador **no programa**: corta, encarga, integra, valida y pregunta. Mano de obra: solo Sonnet y Haiku (ADR-021, decisión 21).

## Qué leer al empezar una sesión

1. `docs/plan/fase-7f.md` (casillas: por dónde va).
2. Este fichero.
3. `docs/flutter/arquitectura.md`.
4. Solo la ficha de la pantalla de la ola en curso (`pantallas/<pantalla>.md`) y, por secciones (`grep -n '^## '`), `contrato.md`.

Una sesión por ola y `/clear` al cerrarla. Tras una ronda de capturas, `/clear`.

## Agentes

| Trabajo | Agente | Modelo |
| --- | --- | --- |
| Pantallas, stores Riverpod, `CustomPainter`, DTO con lógica, `core/`, tests de widgets y de stores | `tf-flutter` | Sonnet |
| Mecánico en Dart: tokens, iconos, claves ARB y su traducción, DTO directos desde fixtures, retoques de 1-2 ficheros | `tf-flutter-mech` | Haiku |
| Swift de `AppCore`/`AppCoreFFI`: ABI, canal de píxeles, fixtures, códigos de mensaje, desvíos de núcleo; scripts de `Tools/flutter/` | `tf-implementer` | Sonnet |
| Localizar código | `caveman:cavecrew-investigator` | Haiku |
| Auditar una pantalla terminada contra su ficha y el contrato | `tf-auditor` | Sonnet |
| Suite entera, build y capturas, una vez por ola antes del commit | `tf-qa` | Sonnet |
| CODEMAP, casillas del plan, resultados de P9, `desvios.md` | `tf-docs` | Sonnet |
| Elegir un respaldo si un plugin falla | `web-researcher` | Sonnet |

No se usa `tf-engineer` ni `tf-ml` (Opus) como mano de obra en esta fase. Si una parte falla dos veces con Sonnet, el orquestador la parte más pequeña y escribe él la mini-spec del trozo difícil (pseudocódigo, casos límite, test que debe pasar); si aun así falla, es una pregunta a Jorge.

## Ciclo de una ola

1. **Mini-spec.** De la ficha de cada pantalla (apartado 10) sale la lista de partes. Comprobar que dos partes paralelas no tocan los mismos ficheros. El kit (`lib/widgets/`), `core/` y `theme/` están congelados fuera de la ola 0: si a una parte le falta un widget o un token, lo pide en su informe y lo añade una parte aparte.
2. **Contrato antes que pantalla.** Para cada área nueva: (a) `tf-implementer` añade al test de fixtures los métodos y eventos del área y vuelca `Contract/fixtures/<área>/`; (b) `tf-flutter-mech` escribe `lib/contract/<área>.dart` y su test contra esos ficheros. Solo entonces arrancan store y pantalla.
3. **Encargos** con la plantilla de abajo, en paralelo cuando no se pisen.
4. **Integrar.** Leer los informes (no el código salvo sospecha), resolver preguntas, registrar desvíos.
5. **Validar cada pantalla** con la lista de abajo. El juicio visual es del orquestador, mirando las dos imágenes; no se delega.
6. **Cierre de ola.** `tf-qa` (una vez): `Tools/test.sh` entero + capturas de todos los estados de la ola. `Tools/flutter/pc.sh` en el PC x64 (avisar a Jorge antes: tiene que estar encendido). `tf-docs`: casillas, CODEMAP, `desvios.md`. Enseñar a Jorge las parejas referencia/Flutter de la ola y su lista de diferencias aceptadas; su visto bueno cierra la ola (casilla del plan).

**Commits** (Jorge, 22/11/2026): pequeños y frecuentes, con `git push` a `fase-7f` tras cada uno y sin preguntar, para que el PC valide en paralelo. Uno por parte integrada, con `Tools/test.sh FlutterApp` (o el paquete tocado) verde; no se espera al cierre de la ola. En inglés, imperativo, sin `Co-Authored-By`. Nunca a `main` ni forzado.

## Plantilla de encargo

```
Parte: <ola>.<n> <nombre>            Agente: tf-flutter | tf-flutter-mech | tf-implementer
Lee: docs/flutter/arquitectura.md (reglas de Dart) · docs/flutter/pantallas/<x>.md §<apartados> ·
     docs/flutter/contrato.md §<área> · docs/flutter/tokens-componentes.md §<componentes>
Crea/edita (solo estos ficheros): <rutas>
No toques: lib/core, lib/theme, lib/widgets, lib/contract (salvo que sea tu parte), otras features
Hecho cuando: <tests que deben existir y pasar> · Tools/test.sh FlutterApp <filtro> verde ·
              flutter analyze sin avisos · estados capturables con --mock --screen <x> --state <y>
Referencia visual: docs/flutter/ref/<pantalla>/<estado>.png
Devuelve: formato del agente (≤ 15 líneas) + desvíos + lo que te faltó del kit
```

El encargo cita secciones exactas (fichero y encabezado `##`) de `pantallas/<p>.md`, `pantallas/<p>-interaccion.md` y de los `contrato-tipos-*.md` que use la parte; nunca "lee la ficha". Si lo necesario supera ~3k tokens, el orquestador pega en el encargo solo las líneas que hacen falta. Objetivo: que el agente arranque con menos de 15k de lectura.

Un encargo = un trabajo que quepa en 100k de contexto. Una pantalla grande son varias partes (store, cuerpo, cada `CustomPainter`, cada hoja).

## Lista de validación de una pantalla

Mecánica (la puede pasar `tf-auditor` contra la ficha):

- [ ] Todos los métodos y eventos del apartado 5 de la ficha se usan, y ninguno fuera de él.
- [ ] Ningún widget llama a `CoreClient`; ningún literal de color, medida o texto fuera de `theme/` y ARB (`grep`).
- [ ] Todas las claves ARB existen en `app_es.arb` y `app_en.arb`; el español coincide con el literal de SwiftUI.
- [ ] Tests de store (cada evento `*.state` y cada error), de widgets (cada estado del apartado 4) y goldens presentes y verdes.
- [ ] Ficheros ≤ ~300 líneas; sin dependencias nuevas.

Visual (orquestador, con las dos imágenes delante, por cada estado del apartado 11):

- [ ] Estructura: mismas zonas, mismo orden, mismas proporciones.
- [ ] Tokens: fondos, bordes, acento, textos primario/secundario/apagado.
- [ ] Tipografía: familia, peso y tamaño por nivel; truncado y saltos de línea.
- [ ] Medidas: alturas de fila y de control, radios, separaciones, alineación de columnas.
- [ ] Controles: aspecto en reposo, activo, deshabilitado y con foco.
- [ ] Dibujo propio: rejillas, medidores, líneas de tiempo y diagramas con la misma geometría.
- [ ] Diferencias aceptadas anotadas en `docs/flutter/ref/<pantalla>/DIFERENCIAS.md` con su motivo (p. ej. suavizado del texto, control nativo de macOS redibujado).

Funcional (app real contra `AppCore`, carpeta de prueba): recorrido del apartado 11 de la ficha en el Mac; lo de hardware, a Jorge con el comando exacto.

## Cuándo se pregunta a Jorge

Siempre como pregunta con alternativas y una recomendada. Obligatorio en: fallo de un umbral de P9; desvío que no es un hueco claro o toca señal, audio o vídeo; añadir o cambiar un plugin; cualquier diferencia visual que no sea de motor de render; cualquier cosa que no esté en la ficha ni en SwiftUI; cambio en la ABI congelada.

## Capturas de referencia (ola 0)

`tf-qa` captura la app SwiftUI con un proyecto fijo de prueba (copia en `Temp/flutter/ref-projects/`, nunca la carpeta real) en cada estado listado en el apartado 11 de las fichas, a 1440×900, y las deja en `docs/flutter/ref/<pantalla>/<estado>.png`. Los estados que SwiftUI no pueda fijar por argumentos (`--screen`, `--project`, demos de DEBUG) se listan y los captura Jorge a mano o se aceptan sin referencia.

## Riesgos que vigilar

- Hilo principal bloqueado por una llamada FFI: síntoma, la interfaz se congela. Toda llamada lenta es un desvío de núcleo.
- Deriva del contrato: si un test de DTO falla tras tocar `AppCore`, se regeneran los fixtures y se corrige el DTO en la misma parte.
- Foco del WebView en Tablatura: probar teclado tras cada cambio de esa pantalla.
- Goldens: se generan y comparan solo en el Mac.
- Contexto: las fichas y el contrato se leen por secciones; el código SwiftUI lo leen los agentes, no el orquestador.
