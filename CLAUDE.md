# ToneForge

App de escritorio para macOS (Swift/SwiftUI) que iguala el tono de un tema reamplificando tu DI por la HeadRush Flex Prime, con estudio del tema, tablatura y grabación con vídeo. Uso personal, todo en local, sin APIs de pago.

## Estado actual

Fase 5c · Interfaz de la tablatura cerrada el 18/11/2026 (ADR-019), sin prueba manual de Jorge: lo que salga va a la fase final de arreglos generales. Fusionada con fase-7 y llevada a main.
Siguiente: fase final de arreglos generales.
P1, P3 y P5 quedan para el comienzo de la Etapa 2.

## Contexto: leer solo lo que haga falta

- **Spec `docs/spec.md` (~7k tokens) y plan `docs/plan.md` (~3k).** Mandan estas copias, no el doc de Claude Docs (ADR-002). Lee solo la sección que toque: `grep -n '^## ' docs/spec.md` y luego `offset`/`limit`.
- **Bocetos `docs/design/<Pantalla>.dc.html`** (~3-4k tokens cada uno: Main, Tab, Edit, Backing, Record, Tone, Settings): solo el de la pantalla en la que se trabaja.
- **Decisiones:** `docs/DECISIONS.md` es un índice de una línea por ADR; el texto está en `docs/adr/ADR-NNN.md`. Nuevo ADR = fichero nuevo + su línea en el índice.
- **Resultados de la Fase 0:** `docs/probes/P<n>-<tema>.md`, uno por prueba.
- **Mapa del código: `docs/CODEMAP.md`**, una sección por paquete. Consúltalo antes de explorar, por secciones (`grep -n '^## '`).
- **Qué expone un fichero Swift, sin leerlo entero:** `grep -nE '^\s*(public|open)\b' <ruta.swift>` (la API entre paquetes es `public` por fuerza). Entero, solo el fichero que vas a editar, y una vez.
- **Nunca leer** audios, modelos (`.mlpackage`, `.mlmodel`, `.onnx`, `.pt`, `.safetensors`) ni logs enteros: `tail`/`grep`.
- **Localizar código** ("dónde está X", "quién llama a Y") → subagente `caveman:cavecrew-investigator`, no una cadena de greps en el hilo principal.

## Estructura

- `Packages/<Kit>/`: un paquete Swift por módulo con sus tests (nombres en `docs/plan.md`, «Forma de trabajo», incluido ModelKit). Lo que depende de la pedalera va detrás de un protocolo con versión simulada.
- `App/`: proyecto Xcode generado con XcodeGen (`App/project.yml`; regenerar con `xcodegen generate --spec App/project.yml`), solo UI y cableado. Embebe el helper `tf-separate` (de StemKit). La lógica y sus tests viven en los paquetes.
- `Vendor/helpers/`: helpers embebidos (yt-dlp, Deno, ffmpeg), no se versiona; se generan con `Tools/helpers/fetch.sh` y `build-ffmpeg.sh`.
- `Probes/P<n>-<tema>/`: scripts de la Fase 0 (Python o Swift). Fuera de la puerta de tests.
- `Tools/`: scripts de desarrollo (`test.sh`; entorno Python en `Tools/py/.venv`). `Temp/`: informes y logs, no se versiona.

## Verificar

- **`Tools/test.sh`** sin argumentos: `swift test` de cada paquete + build de la app, salida resumida (totales, fallos, errores con fichero:línea). Escribe `Temp/last-run.txt`, que es lo que lee `commit-gate.sh`. **`Tools/test.sh <Paquete> [Filtro]`** mientras se itera (no escribe `last-run.txt`). Salida 0 verde, 1 fallos, 2 compilación o nada que probar. Logs completos en `Temp/logs/`.
- Nunca `xcodebuild` ni `swift test` a pelo: miles de líneas que se quedan en contexto.
- Los tests pesados con modelo se activan con `TF_MODEL_TESTS=1` y se lanzan siempre bajo `Probes/P4-modelos/common/guard.py`, de uno en uno.
- **El hardware y el oído son de Jorge.** Ningún agente toca el dispositivo de audio ni decide si algo suena bien: devuelve números (latencia en ms, distancia, desfase) y el comando o el WAV para que Jorge lo pruebe. Lo visual de la app lo juzga el hilo principal leyendo la captura.

## Subagentes: uno por trabajo

Nunca `general-purpose`, `claude` ni un agente "Lead": el hook global `agent-route.js` los rechaza (en BeatBeat eran el 44 % del gasto de subagentes, ~830k ponderados por llamada). El hilo principal es el orquestador de la fase: escribe la mini-spec, la corta en partes, lanza un agente por parte (en paralelo si no se pisan), integra y comprueba la condición de paso; no programa las partes. Qué parte va a Opus y cuál a Sonnet lo dice `docs/plan.md`, «Modelos por fase». No pases `model` al lanzar: cada agente fija el suyo.

| Trabajo | Agente |
| --- | --- |
| Implementar una parte que el plan asigna a Sonnet: pantallas, cableado, conectores, scripts de prueba | `tf-implementer` (Sonnet) |
| Implementar una parte que el plan asigna a Opus: señal, sincronía, integración de modelos, compositor, distancia, optimizador | `tf-engineer` (Opus) |
| Convertir y validar modelos (Core ML, ONNX): separación, acordes, pulso, batería | `tf-ml` (Opus, con memoria) |
| Edición mecánica de 1-2 ficheros (renombrar, retoque acotado) | `caveman:cavecrew-builder` |
| Auditar coherencia código-spec, huecos de una fase, señal y distancia | `tf-auditor` (Sonnet) |
| Verificar (suite entera, build de la app, captura) | `tf-qa` (Sonnet). Lo lanza solo el hilo principal, una vez, al terminar todo y justo antes del commit. |
| CODEMAP, ADR, Estado actual, casillas del plan, resultados de pruebas | `tf-docs` (Sonnet, effort low) |
| Localizar código | `caveman:cavecrew-investigator` (Haiku) |
| Buscar en internet (Remote Editor, TONE3000, modelos, manual) | `web-researcher` (Sonnet) |

## Reglas

- Fase a fase, una rama por fase (`fase-N`). Preguntar antes de inventar reglas que no estén en la spec.
- Al cerrar una fase (`/phase-close`), en el mismo commit: `docs/CODEMAP.md`, "Estado actual" de este fichero (máximo 3 líneas: lo cargan todas las sesiones), casillas y condición de paso en `docs/plan.md`, lo aprendido en `docs/spec.md` y el ADR.
- Commits en inglés, imperativo, estilo de `git log`; sin trailer `Co-Authored-By`. Sin push. Al cerrar cada fase, commit sin pedir confirmación; a mitad de fase, solo si Jorge lo pide.
