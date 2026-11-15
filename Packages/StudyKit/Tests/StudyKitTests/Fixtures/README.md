# Fixtures de StudyKit (Fase 2)

Referencias en Python para validar los ports a Swift de pulso (Beat This!), acordes (BTC) y tonalidad.
Generadas por `Probes/P4-modelos/fixtures/make_fase2_fixtures.py` (ver su cabecera; etapas audio, btc, beat, key,
readme, cada una bajo `Probes/P4-modelos/common/guard.py`). No se versionan audios completos: solo tramos de T1.

## Formato

- `.f32` / `.i32`: binario crudo little-endian, sin cabecera, orden C (row-major: el último índice es el más rápido).
- `.wav`: PCM 16 bits. **Todas las referencias se calcularon a partir de estas mismas muestras leídas como float
  (muestra / 32768, lo mismo que hace `AVAudioFile`)**, así que la entrada que ve Swift es idéntica a la de Python.
- Tiempos en segundos desde el inicio del tramo.

| Fichero | Forma | Tipo | Bytes | Contenido |
|---|---|---|---|---|
| `mix_22k.wav` | 264600 | WAV PCM 16 mono 22 050 Hz | 529244 | T1 mezcla, 60–72 s: media de canales + soxr HQ (como `bt_common.to_mono_22k`) |
| `harm_22k.wav` | 264600 | WAV PCM 16 mono 22 050 Hz | 529244 | T1 bass+guitar+other+piano (BS-RoFormer), 60–72 s: suma, media de canales, `librosa.resample` soxr_hq |
| `harm_44k_stereo.wav` | 88200 × 2 | WAV PCM 16 estéreo 44 100 Hz | 352844 | suma armónica antes de remuestrear, 60–62 s (prueba de remuestreo) |
| `beat_melbank.f32` | [513, 128] | float32 | 262656 | `mel-filterbank.bin` de musetric/beat-this-onnx, fila = bin STFT |
| `beat_logmel.f32` | [601, 128] | float32 | 307712 | log-mel oficial (`LogMelSpect`, torchaudio) de mix_22k.wav |
| `beat_logits_beat.f32` | [601] | float32 | 2404 | logits `beat` del mlmodelc comunitario, troceado oficial |
| `beat_logits_downbeat.f32` | [601] | float32 | 2404 | logits `downbeat`, ídem |
| `beat_ref.json` | — | JSON | 685 | pulsos/downbeats «minimal» (s), tempo, compases, inicios de trozo |
| `chord_cqt_abs.f32` | [144, 130] | float32 | 74880 | |CQT| crudo de librosa de harm_22k.wav (bins × tramas) |
| `chord_input.f32` | [130, 144] | float32 | 74880 | (log(|CQT|+1e-6) − mean)/std, sin relleno |
| `chord_logits.f32` | [2, 108, 170] | float32 | 146880 | logits Core ML FP16 ANE por ventana (la 2.ª con 86 de relleno) |
| `chord_argmax.i32` | [216] | int32 | 864 | argmax por trama, incluye las 86 tramas de relleno |
| `chord_chroma.f32` | [12, 130] | float32 | 6240 | croma plegado por trama (clase × trama), 0 = C |
| `chord.lab` | — | texto | 186 | `.lab` con la lógica literal de test.py de BTC |
| `chord_ref.json` | — | JSON | 867 | mean, std, num_pad, n_frames, segmentos exactos [inicio, fin, índice] |
| `key_fixture.json` | — | JSON | 1189 | tonalidad del tramo: croma, histograma, 24 puntuaciones, key, alternative |
| `key_songs.json` | — | JSON | 4048 | ídem para T1–T3 completos (suma armónica, .lab Core ML ANE de P4) |

Total: 2297227 B.

## Pulso (Beat This!)

- Preproceso: mono, 22 050 Hz, STFT 1024, hop 441, Hann periódica, centrada con `reflect`; **módulo / sqrt(1024)**
  (`normalized="frame_length"` de torchaudio = `torch.stft(normalized=True)`, es decir / sqrt(n_fft) = /32, **no**
  / sqrt(Σ win²) como dicen P4 y la mini-spec: con Σ win² el log-mel se desvía ~0,49); mel = |X|ᵀ · melbank;
  log1p(1000 · mel). Con `beat_melbank.f32` y esa normalización, la reconstrucción en numpy da máx 3,6e-5 frente a
  `beat_logmel.f32`.
- `beat_melbank.f32` frente al banco de torchaudio (el que usa `LogMelSpect`): máx 1,8e-5; frente a
  `librosa.filters.mel(..., norm=None)` en float64: máx 1,2e-5. Un banco calculado en Swift en doble debería quedar
  < 1e-6 de librosa, no del fichero.
- El tramo tiene 601 tramas (< 1500): un solo trozo, inicio −6, de 601 + 6 + 6 = 613 tramas, rellenado con
  ceros a la derecha hasta 1500 para el mlmodelc (entrada fija) y recortado a 613; luego se quita el borde de 6.
  Informativo: PyTorch oficial sobre el trozo de 613 sin rellenar da logits distintos (máx
  6.09) y coincide el 96.2 % de pulsos.
- Postproceso «minimal» de `beat_this` sobre `beat_logits_*`: 25 pulsos, 6 downbeats,
  tempo (media a ±20 % de la mediana) 125.00.
- `chunk_starts`: inicios de `split_piece(spect, 1500, border_size=6, avoid_short_end=True)` para 601, 1000, 1500 y
  3050 tramas: {'601': [-6], '1000': [-6], '1500': [-6, 6], '3050': [-6, 1482, 1556]}. Cada trozo = spect[max(s,0) : min(s+1500, T)] con relleno de ceros
  max(0, −s) a la izquierda y max(0, min(6, s+1500−T)) a la derecha.

## Acordes (BTC)

- CQT: `librosa.cqt(y, sr=22050, n_bins=144, bins_per_octave=24, hop_length=2048)` (fmin C1 por defecto), por trozos de
  10 s (220 500 muestras) concatenados; el tramo de 12 s da 108 + 22 = 130 tramas.
- `chord_input.f32` = (log(|CQT| + 1e-6) − -2.2279878897355596) / 1.7191329394436938. Ventanas de 108 sin solape, la última
  rellena con ceros (86 tramas); entrada Core ML `cqt` [1,108,144], salida `logits` [1,108,170].
- Logits: `BTC_large_voca_fp16.mlpackage` (el del zip de la app), `CPU_AND_NE`. Fotograma = 10/108 s.

## Tonalidad (receta de la mini-spec, §1 KeyDetector)

1. Croma: bin k de |CQT| (144 bins, 24 por octava, fmin C1) → clase (k div 2) mod 12 (0 = C); suma sobre todas las
   tramas (`chord_chroma.f32` es el plegado por trama, antes de sumar).
2. Histograma: por segmento (excluidos 168 = X y 169 = N), duración (fin − inicio, exacta en múltiplos de 10/108 s)
   sumada a cada nota del acorde: raíz = índice div 14, calidad = índice mod 14 con notas min 0,3,7 · maj 0,4,7 ·
   dim 0,3,6 · aug 0,4,8 · min6 0,3,7,9 · maj6 0,4,7,9 · min7 0,3,7,10 · minmaj7 0,3,7,11 · maj7 0,4,7,11 ·
   7 0,4,7,10 · dim7 0,3,6,9 · hdim7 0,3,6,10 · sus2 0,2,7 · sus4 0,5,7.
3. Perfiles Temperley Kostka-Payne (índice 0 = tónica): mayor [0.748, 0.06, 0.488, 0.082, 0.67, 0.46, 0.096, 0.715, 0.104, 0.366, 0.057, 0.4]; menor [0.712, 0.084, 0.474, 0.618, 0.049, 0.46, 0.105, 0.747, 0.404, 0.067, 0.133, 0.33].
   Perfil de la tonalidad con tónica t: p_t[pc] = p[(pc − t) mod 12]. s = ½·r(croma, p_t) + ½·r(histograma, p_t),
   r = Pearson (0 si una varianza es 0).
4. `scores` en orden: 0–11 = C, C#, D, D#, E, F, F#, G, G#, A, A#, B mayor; 12–23 = las mismas menores. key = argmax,
   alternative = segunda, confidence = s1 − s2. Nombres «C:maj» / «A:min».

Resultados: tramo F#:maj; T1 B:maj (0.0083), T2 A:maj (0.1957), T3 F#:min (0.0975).

## Versiones

numpy 2.3.5, librosa 1.0.1, soxr 1.1.0, soundfile 0.14.0, torch 2.7.0, torchaudio 2.7.0, coremltools 9.0, scipy 1.18.1; BTC commit 2682317; beat_this commit
b95c8ab; mlmodelc jessengatai/supracut-beat-this@33fe1a5; melbank musetric/beat-this-onnx@2530870.

## Regenerar

```
PY=Tools/py/.venv/bin/python
mkdir -p Probes/P4-modelos/fixtures/out
for s in audio btc beat key readme; do
  $PY Probes/P4-modelos/common/guard.py --limit-gb 10 --log Probes/P4-modelos/fixtures/out/guard_$s.log -- \
    $PY Probes/P4-modelos/fixtures/make_fase2_fixtures.py --stage $s
done
```
Requiere las salidas de P4 (stems de BS-RoFormer, `btc/out/coreml`, `btc/out/pred`, `beat_this/out/hf_supracut`).
