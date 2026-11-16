---
name: guitar-models-contract
description: Cómo cargar en PyTorch/MSST los modelos de guitarra lumabeat/mvsep-mega53-guitar (safetensors MLX) y becruily/mel-band-roformer-guitar; trampas del worktree
metadata:
  type: project
---

- `lumabeat/mvsep-mega53-guitar` se publica como "MLX", pero son los pesos de ZFTurbo en safetensors FP16 con las claves de PyTorch: cargan tal cual en `BSRoformer` de MSST (commit 1f700c38) con una config generada desde su `mvsep_mega53_guitar_config.json` (mask_estimators.0 = guitarra). Solo faltan las 24 `rotary_embed.freqs` (las de por defecto, theta 10000). Trozo de 882000 muestras (1723 tramas); en CPU FP32 cabe en unos 3,5 GB. Hace falta `safetensors` (ya en requirements).
- `becruily/mel-band-roformer-guitar`: `mel_band_roformer` de MSST, carga estricta con su `config_guitar_becruily.yaml` (`!!python/tuple`, lo lee el FullLoader de MSST); hop 441, trozo de 485100; target_instrument Guitar → demix devuelve la clave "Guitar".
- Los dos scripts reutilizables están en Probes/P4-modelos/guitar_models/ (run_torch.py, score.py, listen.py).
- Trampas del worktree aislado: `git -C <ruta del checkout principal>` y `cd` a otra carpeta + git se bloquean → para clonar, hacerlo desde un script Python (subprocess). `uv pip install -c` falla con espacios en la ruta absoluta → usar rutas relativas al worktree (`-c Tools/py/requirements.txt`).

**Why:** localizar formato y config de estos pesos costó varios turnos.
**How to apply:** para cualquier otro RoFormer de MSST reutilizar run_torch.py (añadir una entrada en MODELS). Ver [[bs-roformer-contract]], [[coreml-env-traps]].
