# Fixture de ADTOF (paridad de `DrumTranscriber`)

Referencia de Python para el port a Swift de la transcripción de batería (mini-spec de la Fase 5, «Transcripción», Batería).

- Modelo: ADTOF Frame_RNN (Zehren et al., CC BY-NC-SA 4.0, uso personal), puerto PyTorch `xavriley/ADTOF-pytorch` commit `85c192e`. En la app va como `App/Resources/Models/ADTOF_FrameRNN_fp32.mlpackage.zip` (`ModelCatalog.drumsADTOF`): Core ML FP32 con GRU nativa de MIL, macOS 15, **`.cpuOnly`** (la GPU calcula mal la GRU nativa). SHA-256 del zip en `meta.json`.
- Referencia: PyTorch 2.7.0 en CPU, FP32. El Core ML embebido (desde Python, `CPU_ONLY`) da una diferencia máxima de 2,7e-7 y los mismos golpes (ver `meta.json`, `parity`).
- Audio: 10 s del stem de batería de T1 (BS-RoFormer SW) desde el segundo 108, mono (media de canales), 44,1 kHz, PCM 16. Espectrograma, activaciones y golpes salen de las muestras ya cuantizadas (`int16 / 32768`, lo mismo que da `AVAudioFile` en float32): el test lee el WAV tal cual.

## Ficheros

| Fichero | Contenido |
|---|---|
| `audio.wav` | 441 000 muestras, 44 100 Hz, mono, PCM 16 bit |
| `spec.f32` | entrada del modelo, float32 little-endian, fila mayor `[1001][84]` (al modelo: `[1, 1001, 84, 1]`) |
| `act.f32` | salida del modelo (sigmoide), float32 little-endian, fila mayor `[1001][5]`; columnas bombo 35, caja 38, tom 47, charles 42, platos 49 |
| `hits.json` | `labels`, `names`, `counts` y `hits`: `frame` (trama a 100 fps), `time` (s = frame / 100), `note` (MIDI GM de percusión), ordenados por `(frame, note)`. 53 golpes: 19 / 10 / 7 / 6 / 11 |
| `filterbank.json` | banco logarítmico `[84, 1024]` en disperso: `entries` = `[band, fftBin, weight]` (solo pesos no nulos), para depurar el banco de Swift |
| `meta.json` | preproceso, formas, parámetros de picos, paridad Core ML, tiempos y SHA-256 del zip del modelo |

## Preproceso (`adtof_pytorch.audio.AudioProcessor`)

1. `x` float32 mono a 44,1 kHz, `n` muestras. Se rellenan 1024 ceros a cada lado (`center=True`, relleno constante).
2. Tramas de 2048 muestras con salto 441 (100 fps): `T = 1 + floor(n / 441)` (aquí 1001). Ventana `np.hanning(2048)`, simétrica: `w[i] = 0.5 − 0.5·cos(2πi / 2047)`.
3. `|FFT|` de los bins 0..1023 (sin el de Nyquist), sin normalizar.
4. `spec[t][b] = log10(1 + Σ_k fb[b][k] · |X_t[k]|)`, con `fb` el banco de `filterbank.json`: 12 bandas por octava de 20 Hz a 20 kHz, frecuencias al bin más cercano de `fftfreq(2048, 1/44100)[:1024]`, bins repetidos eliminados, triángulos estilo madmom normalizados a suma 1 (84 bandas).

## Picos (`NotePeakPickingProcessor` del puerto, por columna, a 100 fps)

Umbrales: bombo 0,22 · caja 0,24 · tom 0,32 · charles 0,22 · platos 0,30.

1. Media móvil de 12 tramas (10 antes, 1 después; bordes rellenos repitiendo el extremo): `p = max(0, a − media)`.
2. Máximo local en 4 tramas (2 antes, 1 después; bordes repitiendo el extremo): pico si `p[t] ≥ máx` y `p[t] ≥ umbral` (el umbral se aplica a `p`, no a la activación).
3. Picos encadenados a ≤ 2 tramas del anterior del grupo forman un grupo; de cada grupo queda el de mayor `p` (el primero si empatan).
4. Tiempo = `t / 100` s.

Tolerancias de la spec: activaciones con diferencia < 1e-4 (Python mide 2,7e-7), golpes a ±10 ms.

## Regenerar

```
Tools/py/.venv/bin/python Probes/P4-modelos/adtof/package.py --install
Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --log Probes/P4-modelos/adtof/out/logs/guard_fixture.log -- Tools/py/.venv/bin/python Probes/P4-modelos/adtof/make_fase5_fixture.py
```

`package.py` comprueba `Probes/P4-modelos/adtof/out/conv/adtof_fp32n.mlpackage` (lo genera `run_all.py --convert`) y deja el zip, idéntico en cada ejecución, en `App/Resources/Models`. `make_fase5_fixture.py` (`--start`, `--seconds`) lee el stem de T1 de `Probes/P4-modelos/bs_roformer_sw/out/conv/coremlpub_cpu_gpu/T1/drums.wav`, reescribe todos los ficheros de esta carpeta salvo este README y deja el informe en `Probes/P4-modelos/adtof/out/fase5/`.
