---
name: btc-contract
description: BTC (acordes, jayg996/BTC-ISMIR19) — trampas del código de 2019 con el entorno actual, contrato de ventana y conversión Core ML
metadata:
  type: project
---

- Pesos dentro del repo (no LFS): test/btc_model_large_voca.pt (170 acordes), commit 2682317b. LICENSE del repo = MIT (la spec dice pesos no comerciales: tratar como uso personal).
- Trampas con el entorno (torch 2.7, numpy 2.3, PyYAML 6), sin tocar el repo:
  - `utils/hparams.HParams.load` usa yaml.load sin Loader → leer run_config.yaml con yaml.safe_load(...)["model"] y pasar el dict a BTC_model.
  - `transformer_modules._gen_timing_signal` usa `np.float` → poner `np.float = float` antes de importar btc_model.
  - El ckpt guarda mean/std como escalares numpy → torch.load(weights_only=True) falla; verificar sha256 y usar weights_only=False.
  - No importar utils/mir_eval_modules (importa mir_eval); el vocabulario y el preproceso están copiados en Probes/P4-modelos/btc/btc_common.py.
- Máscaras de atención con -inf (bias_mask, atributo normal, no buffer) → cambiar a -1e4 antes de trazar: en FP32 da lo mismo (dif 0) y es seguro en FP16/ANE.
- Convertir solo self_attn_layers + output_projection: (1,108,144) → logits (1,108,170); argmax fuera. ct.convert tarda 3 s, primer intento bien.
- Modelo de 3 M parámetros: el ANE con ventana de 108 tramas es seguro (pico < 2 GB, compila en unos 4 s) y MLComputePlan (coremltools.models.compute_plan) funciona para contar operaciones por dispositivo.

- La receta de tonalidad vive en `fixtures/make_fase2_fixtures.py`, que parsea argumentos y escribe fixtures al importarse: no se puede importar; copiar sus funciones (cqt_abs, fold_chroma, segments, chord_histogram, key_estimate). Para un tema nuevo de principio a fin hay un guion de ejemplo en `Temp/jorge-roce/analyze.py` (decode con ffmpeg → sep → btc → key). Avisos de librosa «n_fft=512 is too large» en el último trozo corto: normales.

**Why:** los tres primeros fallos fueron de compatibilidad del código de 2019, no de conversión.
**How to apply:** reutilizar btc_common.py; para otro modelo pequeño, el ANE con ventana fija es la primera opción. Ver [[coreml-env-traps]].
