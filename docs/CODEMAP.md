# ToneForge · Mapa del código

Última actualización: 2026-11-15 · antes de la Fase 0: solo configuración y docs (ADR-003).

Una sección por paquete (nombres de `docs/plan.md`, «Forma de trabajo»), más la app, las pruebas y las herramientas. Fila por fichero: `| Fichero | qué hace (ADR-NNN): APIs públicas |`. Se lee por secciones: `grep -n '^## ' docs/CODEMAP.md`.

## Packages/AudioKit

E/S de audio y reproducción. Sin código.

## Packages/StemKit

Separación de stems. Sin código.

## Packages/StudyKit

Acordes, pulso, bucles. Sin código.

## Packages/AnalysisKit

Huella del tono y distancia. Sin código.

## Packages/MatchKit

Optimizador. Sin código.

## Packages/HeadRushKit

Conector del Remote Editor de la Flex Prime. Sin código.

## Packages/Tone3000Kit

Conector de TONE3000. Sin código.

## Packages/TabKit

Transcripción y tablatura. Sin código.

## Packages/VideoKit

Captura y montaje de vídeo. Sin código.

## Packages/Store

Archivo de proyecto e índice en SwiftData. Sin código.

## App

Proyecto Xcode: UI y cableado. Sin código.

## Probes

Scripts de la Fase 0 (`Probes/P<n>-<tema>/`); resultados en `docs/probes/`. Sin código.

## Tools

| Fichero | qué hace |
| --- | --- |
| `Tools/test.sh` | `swift test` de cada paquete + build de la app con salida resumida; escribe `Temp/last-run.txt` en la pasada completa (ADR-003) |
