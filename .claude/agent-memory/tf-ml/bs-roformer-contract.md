---
name: bs-roformer-contract
description: Dónde están los pesos de BS-RoFormer SW, orden de stems, parámetros de STFT/troceado y forma del núcleo sin STFT
metadata:
  type: project
---

- Pesos: el repo original `jarredou/BS-ROFO-SW-Fixed` da 401 (ya no es público). Hay espejos con hashes LFS idénticos: `enerjazzer/BS-ROFO-SW-Fixed` (BS-Rofo-SW-Fixed.ckpt/.yaml) y `cdjmix1991/bandsplit-roformer-sw-by-jarredou`. Sha256 del ckpt: 24e7d35e…916e. Licencia "unknown": solo uso personal. No figura en docs/pretrained_models.md de MSST; se carga como model_type `bs_roformer`.
- Orden de stems de salida (config training.instruments): bass, drums, other, vocals, guitar, piano. No es el orden alfabético ni el de Demucs.
- STFT: n_fft 2048, hop 512, ventana hann periódica de 2048, center=True con relleno reflect, sin normalizar. zero_dc=True (bin 0 de la salida a 0).
- Troceado: trozo de 588800 muestras (1151 tramas), num_overlap 2 (paso 294400), fundido lineal de 58880 muestras, relleno reflect del borde (294400) por los dos lados de la canción. `use_amp` es solo para CUDA: en CPU/MPS la referencia es FP32.
- Núcleo convertible: spec (2,1025,1151,2) → (12,1025,1151,2) [stem*2+canal]. 174,7 M parámetros (unos 700 MB en FP32).

- Hay conversiones publicadas: buscarlas ANTES de convertir.
  - `gridshiftstudio/bs-roformer-sw-coreml`: BSRoformerSW.mlpackage. Entrada `spec` [1,2050,1151,2] f32, con el eje (f s) intercalado (índice 2f+canal). La salida se llama `permute_97` (no `mask`): [1,6,2050,1151,2] FP16, máscara compleja; producto complejo y DC a 0 fuera del modelo.
  - `sunnymeadsound/stem-separation-models` bs_roformer_6stem: `spectrogram` [1,4,1025,256] con canales L-re, L-im, R-re, R-im → `stems_spectrogram` [1,6,4,1025,256] = espectro ya enmascarado. Deducido empíricamente con probe_sunnymead.py.
  - `elicwhite/bs-roformer-sw-6stem-onnx`: trozo de 4 s (T=345), spec_real/spec_imag.
  - BSRoformer.cpp (GGML, Metal) + `FractalSurfer/BS-RoFormer-SW-6stem` q8_0 GGUF: la CLI acepta --chunk-size/--overlap; necesita ggml aparte (sin versión fijada en su CI) y -DGGML_CUDA=OFF; en macOS compila sin OpenMP.
- Neural Engine con este modelo: con trozo de 256 tramas, `.cpuAndNeuralEngine` compila en unos 53 s pero cada inferencia es unas 7 veces más lenta que en GPU; `.all` se queda más de 3,5 min en ANECompilerService. No compensa.

**Why:** localizar los pesos y deducir el contrato costó varios turnos.
**How to apply:** reutilizar Probes/P4-modelos/bs_roformer_sw/sw_common.py, que ya implementa todo esto. Ver [[coreml-env-traps]].
