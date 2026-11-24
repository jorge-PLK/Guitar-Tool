# ToneForge

App de escritorio para macOS (Swift/SwiftUI) que iguala el tono de un tema reamplificando tu DI por la HeadRush Flex Prime, con estudio del tema, tablatura y grabación con vídeo. Uso personal, todo en local, sin APIs de pago.

## Estado actual

Fases 5 (ADR-016), 5b (ADR-017), 5c (ADR-019, sin prueba manual de Jorge), 6 (ADR-015) y 7 · Montaje (ADR-018) cerradas en `main` (18/11/2026). Fase 7c (port a Windows, ADR-020/ADR-022, solo x64) cerrada el 24/11/2026 en la rama `pcx64tests`, validada en el PC x64; falta fusionarla en `main`.
Fase 7f (interfaz única en Flutter, ADR-021) en la rama `fase-7f`: P9 cerrada (24/11/2026, ABI de `AppCoreFFI` congelada), siguiente paso la ola 0; los desvíos de núcleo de la 7c se tratan aquí (`docs/flutter/desvios.md`).
Después: actualizador (7d) → instalador de Windows → fase de cambios de UX (sustituye a la 7b). P1, P3 y P5 quedan para el comienzo de la Etapa 2.

## Contexto: leer solo lo que haga falta

- **Spec y plan, un fichero por fase.** Mandan estas copias, no el doc de Claude Docs (ADR-002). `docs/spec.md` (~9k tokens) es el núcleo; cada mini-spec en `docs/spec/fase-N.md`. `docs/plan.md` (~4k) es el índice con «Modelos por fase»; cada fase en `docs/plan/fase-N.md` (la 7c, ~15k: por secciones). Lee entero solo el fichero de la fase que toca.
- **Bocetos `docs/design/<Pantalla>.dc.html`** (~3-4k tokens cada uno: Main, Tab, Edit, Backing, Record, Tone, Settings): solo el de la pantalla en la que se trabaja.
- **Decisiones:** `docs/DECISIONS.md` es un índice de una línea por ADR; el texto está en `docs/adr/ADR-NNN.md`. Nuevo ADR = fichero nuevo + su línea en el índice.
- **Fase 7f (Flutter): `docs/flutter/`.** Al empezar sesión: `docs/plan/fase-7f.md`, `docs/flutter/orquestador.md` y `docs/flutter/arquitectura.md`; el índice del resto está en `docs/flutter/README.md`. Fichas (`pantallas/<pantalla>.md`) y contrato (`contrato*.md`), solo los de la ola en curso y por secciones. Decisiones cerradas de interfaz: `docs/flutter/decisiones-interfaz.md` (`grep` antes de preguntar).
- **Resultados de la Fase 0:** `docs/probes/P<n>-<tema>.md`, uno por prueba.
- **Mapa del código: `docs/CODEMAP.md`** (índice); una ficha por paquete en `docs/codemap/<Kit>.md`. Consulta la del paquete antes de explorar.
- **Bash no lee ficheros.** Ni `cat`, ni `sed -n` de rangos largos, ni `cd … &&` (el cwd ya es la raíz): `Read` para leer, `Grep` con `head_limit` o `grep … | head -40` para buscar. El hook `.claude/hooks/bash-read-guard.js` lo deniega, también en subagentes.
- **Qué expone un fichero Swift, sin leerlo entero:** `grep -nE '^\s*(public|open)\b' <ruta.swift>` (la API entre paquetes es `public` por fuerza). Entero, solo el fichero que vas a editar, y una vez.
- **Nunca leer** audios, modelos (`.mlpackage`, `.mlmodel`, `.onnx`, `.pt`, `.safetensors`) ni logs enteros: `tail`/`grep`.
- **Localizar código** ("dónde está X", "quién llama a Y") → subagente `caveman:cavecrew-investigator`, no una cadena de greps en el hilo principal.

## Estructura

- `Packages/<Kit>/`: un paquete Swift por módulo con sus tests (nombres en `docs/plan.md`, «Forma de trabajo», incluido ModelKit). Lo que depende de la pedalera va detrás de un protocolo con versión simulada.
- `App/`: proyecto Xcode generado con XcodeGen (`App/project.yml`; regenerar con `xcodegen generate --spec App/project.yml`), solo UI y cableado. Embebe el helper `tf-separate` (de StemKit). La lógica y sus tests viven en los paquetes. **Congelado** desde la 7f, igual que `WinApp/Web` y `Tools/webdev`.
- `FlutterApp/` (desde la ola 0 de la 7f): la interfaz única de Mac y Windows. Habla solo con `AppCore` por el puente FFI (`AppCoreFFI`, en `Packages/AppCore`); DTO generados contra `Contract/fixtures/`. Scripts en `Tools/flutter/`.
- `Vendor/helpers/`: helpers embebidos (yt-dlp, Deno, ffmpeg), no se versiona; se generan con `Tools/helpers/fetch.sh` y `build-ffmpeg.sh`.
- `Probes/P<n>-<tema>/`: scripts de la Fase 0 (Python o Swift). Fuera de la puerta de tests.
- `Tools/`: scripts de desarrollo (`test.sh`; entorno Python en `Tools/py/.venv`). `Temp/`: informes y logs, no se versiona.

## Verificar

- **`Tools/test.sh`** sin argumentos: `swift test` de cada paquete + build de la app, salida resumida (totales, fallos, errores con fichero:línea). Escribe `Temp/last-run.txt`, que es lo que lee `commit-gate.sh`. **`Tools/test.sh <Paquete> [Filtro]`** mientras se itera (no escribe `last-run.txt`). Salida 0 verde, 1 fallos, 2 compilación o nada que probar. Logs completos en `Temp/logs/`.
- Nunca `xcodebuild` ni `swift test` a pelo: miles de líneas que se quedan en contexto.
- Los tests pesados con modelo se activan con `TF_MODEL_TESTS=1` y se lanzan siempre bajo `Probes/P4-modelos/common/guard.py`, de uno en uno.
- **El hardware y el oído son de Jorge.** Ningún agente toca el dispositivo de audio ni decide si algo suena bien: devuelve números (latencia en ms, distancia, desfase) y el comando o el WAV para que Jorge lo pruebe. Lo visual de la app lo juzga el hilo principal leyendo la captura.

## Subagentes: uno por trabajo

Nunca `general-purpose`, `claude` ni un agente "Lead": el hook global `agent-route.js` los rechaza (en BeatBeat eran el 44 % del gasto de subagentes, ~830k ponderados por llamada). El hilo principal es el orquestador de la fase: escribe la mini-spec, la corta en partes, lanza un agente por parte (en paralelo si no se pisan), integra y comprueba la condición de paso; no programa las partes. Qué parte va a Opus y cuál a Sonnet lo dice `docs/plan.md`, «Modelos por fase». No pases `model` al lanzar: cada agente fija el suyo. En la 7f la mano de obra es solo Sonnet y Haiku (ADR-021, decisión 21): ni `tf-engineer` ni `tf-ml`; el Swift de `AppCore`/`AppCoreFFI` es de `tf-implementer`. Ciclo de ola, plantilla de encargo y lista de validación: `docs/flutter/orquestador.md`.

**Encargo que no obliga a explorar** (los subagentes son el 68 % del gasto, y de él el 76 % es releer su propio contexto): cada encargo trae los ficheros a tocar, las firmas o tipos que necesita ya copiados, las secciones exactas de docs que leer (fichero + encabezado, nunca «lee la ficha») y el criterio de hecho con el comando de test. Una parte debe caber en unas 40-60 peticiones y en el tope de 100k; si no, se parte en dos.

| Trabajo | Agente |
| --- | --- |
| Implementar una parte que el plan asigna a Sonnet: pantallas, cableado, conectores, scripts de prueba | `tf-implementer` (Sonnet) |
| Dart de la 7f que no sea mecánico: pantallas, stores Riverpod, `CustomPainter`, hojas, `core/`, DTO con lógica y sus tests | `tf-flutter` (Sonnet) |
| Dart mecánico de la 7f: tokens, iconos, ARB y su traducción, DTO directos desde fixtures, retoques de 1-2 ficheros | `tf-flutter-mech` (Haiku) |
| Implementar una parte que el plan asigna a Opus: señal, sincronía, integración de modelos, compositor, distancia, optimizador | `tf-engineer` (Opus) |
| Convertir y validar modelos (Core ML, ONNX): separación, acordes, pulso, batería | `tf-ml` (Opus, con memoria) |
| Edición mecánica de 1-2 ficheros (renombrar, retoque acotado) | `caveman:cavecrew-builder` |
| Auditar coherencia código-spec, huecos de una fase, señal y distancia | `tf-auditor` (Sonnet) |
| Verificar (suite entera, build de la app, captura) | `tf-qa` (Sonnet). Lo lanza solo el hilo principal, una vez, al terminar todo y justo antes del commit. |
| CODEMAP, ADR, Estado actual, casillas del plan, resultados de pruebas | `tf-docs` (Sonnet, effort low) |
| Localizar código | `caveman:cavecrew-investigator` (Haiku) |
| Buscar en internet (Remote Editor, TONE3000, modelos, manual) | `web-researcher` (Sonnet) |

## Reglas

- **UIs viejas congeladas (ADR-021, decisión 4).** En `fase-7f`, `App/Sources`, `WinApp/Web` y `Tools/webdev` no se tocan; se borran en el commit de cierre de la fase. La paridad Mac/Windows ya no se aplica a ellas.
- **Mac y Windows, paridad sobre Flutter.** Toda función o cambio de comportamiento va a `AppCore` y a `FlutterApp/`, que es la misma en las dos plataformas, y se comprueba en el Mac y en el PC x64 (`Tools/flutter/pc.sh`). Flutter habla solo con `AppCore`; un hueco de núcleo se arregla en `AppCore` con test y se anota en `docs/flutter/desvios.md`. Lo que no pueda igualarse en función se lista a Jorge.
- **Port 1:1 (ADR-021).** Aspecto e interacción = SwiftUI; comportamiento = `AppCore`. Robustez, fiabilidad y rendimiento mandan sobre el 1:1 y sobre cualquier ADR previo (Jorge, 22/11/2026). Añadir o cambiar un plugin, o tocar la ABI congelada, es una pregunta a Jorge.
- Fase a fase, una rama por fase (`fase-N`). Preguntar antes de inventar reglas que no estén en la spec.
- Al cerrar una fase (`/phase-close`), en el mismo commit: `docs/codemap/<Kit>.md` y la línea 3 de `docs/CODEMAP.md`, "Estado actual" de este fichero (máximo 3 líneas: lo cargan todas las sesiones), casillas y condición de paso en `docs/plan/fase-N.md`, lo aprendido en `docs/spec.md` o `docs/spec/fase-N.md` y el ADR.
- Commits en inglés, imperativo, estilo de `git log`; sin trailer `Co-Authored-By`. Desde la Fase 7f (Jorge, 22/11/2026): commits pequeños y frecuentes con `git push` a la rama de la fase tras cada uno, sin pedir confirmación, para que Jorge valide en paralelo en el PC. Nunca push a `main` ni forzado.
