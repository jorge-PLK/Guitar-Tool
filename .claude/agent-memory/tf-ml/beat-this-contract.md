---
name: beat-this-contract
description: Beat This! (pulso, CPJKU/beat_this) — dónde están los pesos, conversiones publicadas que existen o no, contrato del modelo y trampa de la métrica de tempo
metadata:
  type: project
---

- El servidor oficial de checkpoints (cloud.cp.jku.at …/7ik4RrBKTS273gp/final0.ckpt) dio HTTP 500 el 2026-11-15. Espejos HF con el mismo sha256 LFS 8c328b45…8331: `teamup-tech/Beat-This-weights` y `Audante/beat-this-final0`. También `safe-models/beat-this-final0` (safetensors).
- El repo funciona con el venv tal cual (torch 2.7, einops 0.8.2, rotary-embedding-torch 0.9.2, soxr): basta sys.path al clon, sin pip install. Postproceso por defecto = "minimal" (sin madmom).
- `schism-audio/beat-this-coreml` NO existe en HF (401). Core ML publicado que sí: `jessengatai/supracut-beat-this` (BeatThis.mlmodelc.zip, FP32, final0; diferencia de logits con torch 8e-5) — se carga con `ct.models.CompiledMLModel`. Otros: `arraypress/scribe-beat-this` (.aimodel), ONNX `musetric/beat-this-onnx` (config.json + mel-filterbank.bin útiles para portar el mel).
- Su README avisa: en FP16 la atención pierde precisión y la salida es ruido → no gastar intentos en FP16/ANE sin motivo.
- Contrato: `spect` (1,1500,128) f32 log-mel → `beat`, `downbeat` (1,1500) logits; 50 fps; trozo 1500 con borde 6, keep_first.
- Tempo por 60/mediana de intervalos va a saltos de 20 ms (27 tramas = 111,1 BPM, 28 = 107,1): a 110 BPM nunca cae en ±1. Usar media de intervalos (o ajuste) para el tempo.

- **Normalización del log-mel (corregido 2026-11-15)**: `normalized="frame_length"` de torchaudio = `torch.stft(normalized=True)` = |X| / sqrt(n_fft) = /32. P4 y la mini-spec de Fase 2 decían / sqrt(Σ win²): eso desvía el log-mel ~0,49.
- `mel-filterbank.bin` (musetric) difiere del banco de torchaudio 1,8e-5 y de librosa float64 1,2e-5: un umbral de 1e-6 frente al fichero no es alcanzable calculando el banco.
- Pieza < 1500 tramas: `split_piece` devuelve un trozo corto (T+12); el mlmodelc tiene entrada fija → rellenar con ceros a la derecha y recortar. Cambia los logits frente a PyTorch sin rellenar (máx ~6, 1 de 26 pulsos distinto en 12 s).

**Why:** localizar pesos y conversión costó varios turnos; la métrica de tempo parece un fallo del modelo y no lo es.
**How to apply:** reutilizar Probes/P4-modelos/beat_this/bt_common.py. Ver [[coreml-env-traps]], [[btc-contract]].
