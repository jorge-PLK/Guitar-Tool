# Fixture de Basic Pitch (paridad del Core ML en Swift)

Referencia para el test de paridad del envoltorio de Basic Pitch en TabKit (test pesado, `TF_MODEL_TESTS=1`).

- Modelo: `nmp.mlpackage` oficial de spotify/basic-pitch (ICASSP 2022), commit `fa5997af0a8210982619003269994a1be25eddf3`, licencia Apache-2.0. En la app va como `App/Resources/Models/BasicPitch_nmp.mlpackage.zip` (`ModelCatalog.transcriptionBasicPitch`); el SHA-256 del zip está en `meta.json`.
- Referencia: `nmp.onnx` del mismo commit con ONNX Runtime 1.32 en CPU (la versión de Python). El Core ML desde Python (CPU+GPU) da una diferencia máxima de 1e-6 frente a ella (ver `meta.json`).
- Audio: 6 s del stem de guitarra de T1 (BS-RoFormer SW) desde el segundo 128, a 22050 Hz mono (`librosa.load(sr=22050, mono=True)`, remuestreo soxr_hq), guardado en PCM 16. Las referencias se calcularon desde las muestras ya cuantizadas (`int16 / 32768`, lo mismo que da `AVAudioFile` en float32), así que el test lee el WAV tal cual, sin remuestrear.

## Ficheros

| Fichero | Contenido |
|---|---|
| `audio.wav` | 132 300 muestras, 22050 Hz, mono, PCM 16 bit |
| `note.f32` | posteriorgrama de notas, float32 little-endian, fila mayor `[516][88]` |
| `onset.f32` | posteriorgrama de ataques, float32 little-endian, `[516][88]` |
| `contour.f32` | posteriorgrama de contorno, float32 little-endian, `[516][264]` |
| `notes.json` | `params` del post-proceso y `notes`: `startFrame`, `endFrame`, `pitch` (MIDI), `amplitude`, `startTime`, `endTime` (s), `pitchBends` (enteros, en tercios de semitono) |
| `meta.json` | constantes de ventana y bins, formas, diferencia Core ML (Python) frente a la referencia, SHA-256 del zip del modelo |

Bin `b` de note/onset = nota MIDI `21 + b` (A0 = 27,5 Hz). Contour: 3 bins por semitono desde 27,5 Hz.

## Contrato del modelo

- Entrada `input_2`: `[1, 43844, 1]` float32 (43844 = 2 s · 22050 − 256).
- Salidas, cada una con 172 tramas: `Identity_1` = note `[1, 172, 88]`, `Identity_2` = onset `[1, 172, 88]`, `Identity` = contour `[1, 172, 264]`. Sigmoides ya aplicadas (valores 0–1). El CQT va dentro del modelo.

## Troceado (igual que `basic_pitch.inference.run_inference`)

1. `x` = audio en float32, `n` muestras.
2. Se anteponen 3840 ceros (mitad del solape: 30 tramas · 256).
3. Ventanas de 43844 muestras que empiezan en `i = 0, 36164, 72328, …` mientras `i < n + 3840`; la última se rellena con ceros por la derecha. Aquí salen 4 ventanas.
4. De cada salida se quitan las 15 primeras y las 15 últimas tramas (quedan 142), se concatenan las ventanas y se recorta a `floor(n · 86 / 22050)` tramas (86 = `22050 // 256`, entero): 516.

## Notas (post-proceso por defecto de `predict`)

`output_to_notes_polyphonic(note, onset, onset_thresh=0.5, frame_thresh=0.3, min_note_len=11, infer_onsets=True, melodia_trick=True, energy_tol=11)`, sin límites de frecuencia, y `get_pitch_bends` sobre contour. Tiempos con `model_frames_to_time`:
`t(f) = f · 256 / 22050 − floor(f / 172) · (256 / 22050 · (172 − 43844 / 256) + 0.0018)`.
Las notas salen en el orden de Python (de la última a la primera por ataque): compáralas ordenadas por `(startFrame, pitch)`.

Tolerancias propuestas: posteriorgramas con diferencia absoluta máxima de 1e-4 (Python mide 1e-6), notas iguales en `(startFrame, endFrame, pitch)` y `amplitude` con 1e-4.

## Regenerar

```
Tools/py/.venv/bin/python Probes/P4-modelos/basic_pitch/convert.py
Tools/py/.venv/bin/python Probes/P4-modelos/basic_pitch/compare.py
```

`compare.py` lee `/Volumes/SSD Mac/Personales/Guitar Tool/Probes/testaudio/out/T1/stems/guitar.wav` (otra ruta con `--t1`), reescribe todos los ficheros de esta carpeta salvo este README y deja el informe en `Probes/P4-modelos/basic_pitch/out/`.
