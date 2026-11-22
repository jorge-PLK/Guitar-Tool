# Probes

Sondas de la Fase 0 (`Probes/P<n>-<tema>/`), desechables; resultados en `docs/probes/`.

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
| `Probes/P4-modelos/fixtures/make_fase2_fixtures.py` | Genera los fixtures de `Packages/StudyKit/Tests/StudyKitTests/Fixtures/` (12 s de T1 en WAV de 16 bits y referencias Python) (ADR-009) |
| `Probes/P7-fuentes/` | Sondas de fuentes externas (enlaces de YouTube y Spotify), en scripts numerados (ADR-008); `09-list.sh` a `13-parse-listas.py` son la prueba ampliada: candidatos de cinco temas con `tf-fetch`, descarga con tiempos, restricción de edad, y embeds de lista y álbum con su resumen (ADR-011) |
| `Probes/P6-timepitch/{run.sh,p6.py,AppleRender}` | Comparación ciega de `AVAudioUnitTimePitch` y Rubber Band: `run.sh Probes/testaudio/out/clips/*.wav` (ADR-005) |
| `Probes/P4-modelos/{guitar_models,basic_pitch,lead_rhythm}/` | Fase 4 (ADR-014): modelos de guitarra frente a BS-RoFormer SW (`run_torch.py`, `score.py`, `listen.py`), conversión y paridad de Basic Pitch y del lead/rhythm (`convert.py`, `compare.py`) |
| `Probes/P5b-guitarra/` | (ADR-017) Pruebas de la 5b: evaluación contra Songsterr (`eval_reference.py`) y `check-techniques.js` (46/46 adornos en alphaTab y `.gp`) |
| `Probes/P5c-voces/check-vocal.js` | (ADR-019) Comprobación de la pista de voz en alphaTab |
| `Probes/P5-alphatab/make-spike.js` | (ADR-016) Prueba inicial de alphaTab: partitura de guitarra, bajo y batería exportada a `.gp` |
| `Probes/P4-modelos/adtof/{package.py,make_fase5_fixture.py}` | (ADR-016) `package.py` empaqueta ADTOF para la app; `make_fase5_fixture.py` genera el fixture de `Tests/TabKitTests/Fixtures/drums/` (activaciones y golpes de Python) |
| `Probes/testaudio/prepare.py` | Prepara los temas y tramos de prueba (`out/` ignorado) |

Recursos: modelos y resultados en `Probes/P4-modelos/*/out/` (no versionados); entorno de Python en `Tools/py/.venv`, dependencias fijadas en `Tools/py/requirements.txt`.
