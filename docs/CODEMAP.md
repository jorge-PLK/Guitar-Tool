# ToneForge · Mapa del código

Última actualización: 2026-11-15 · cierre de la Fase 0 · Etapa 1 (ADR-006).

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

Sondas de la Fase 0 (`Probes/P<n>-<tema>/`), desechables; resultados en `docs/probes/`. Los paquetes de `Packages/` siguen sin código.

| Fichero | qué hace (ADR-NNN) |
| --- | --- |
| `Probes/P2-audio-usb/` | Paquete Swift `P2AudioUSB`: CLI `p2` (`Sources/p2`: `Commands`, `HAL`, `Session`) sobre CoreAudio y `P2Core` (WAV, FFT, señales, detectores, analizador, autotest) con `Tests/P2CoreTests`. Audio USB de la Flex Prime (ADR-006) |
| `Probes/P4-modelos/common/{guard,metrics}.py` | `guard.py`: vigilante de memoria (10 GB) obligatorio para procesos pesados; `metrics.py`: SDR y medidas comunes |
| `Probes/P4-modelos/bs_roformer_sw/` | Separador elegido: Core ML publicado de gridshift, CPU+GPU, SDR, retención y comparativas (ADR-004). Resultados en `out/results/` |
| `Probes/P4-modelos/bsroformer_cpp/run.py` | Respaldo BSRoformer.cpp con GGUF q8 en Metal (ADR-004) |
| `Probes/P4-modelos/htdemucs/` | `separate.py` y `report.py`: HTDemucs 6s, solo comparación (ADR-004) |
| `Probes/P4-modelos/btc/run_all.py` | Acordes BTC: referencia PyTorch y Core ML FP16 (ADR-006). Comando: `Tools/py/.venv/bin/python Probes/P4-modelos/btc/run_all.py` |
| `Probes/P4-modelos/beat_this/run_all.py` | Pulso Beat This! con el `mlmodelc` comunitario; `--all` prueba todas las vías (ADR-006). Mismo comando que BTC con su ruta |
| `Probes/P4-modelos/adtof/run_all.py` | Batería ADTOF en Core ML FP32 con GRU nativa; `--convert` la primera vez (ADR-006). Mismo comando con su ruta |
| `Probes/P6-timepitch/{run.sh,p6.py,AppleRender}` | Comparación ciega de `AVAudioUnitTimePitch` y Rubber Band: `run.sh Probes/testaudio/out/clips/*.wav` (ADR-005) |
| `Probes/testaudio/prepare.py` | Prepara los temas y tramos de prueba (`out/` ignorado) |

Recursos: modelos y resultados en `Probes/P4-modelos/*/out/` (no versionados); entorno de Python en `Tools/py/.venv`, dependencias fijadas en `Tools/py/requirements.txt`.

## Tools

| Fichero | qué hace |
| --- | --- |
| `Tools/test.sh` | `swift test` de cada paquete + build de la app con salida resumida; escribe `Temp/last-run.txt` en la pasada completa (ADR-003) |
