---
name: htdemucs-env
description: Cómo instalar y ejecutar demucs (HTDemucs 6s) en Tools/py/.venv sin romper torch/numpy; trampas de uv con rutas con espacios
metadata:
  type: project
---

- `uv pip install -c <ruta con espacios>` falla con «File not found: `/Volumes/SSD`» (uv parte la ruta del fichero de restricciones). Copiar requirements.txt a una ruta sin espacios (scratchpad) y pasar esa con `-c`. `--python` con espacios sí funciona.
- demucs==4.0.1 (PyPI) se instala con `-c requirements.txt` sin tocar torch 2.7.0 ni numpy 2.3.5 (añade dora-search, julius, lameenc, openunmix, retrying, submitit, treetable). PyPI 4.0.1 no trae `demucs.api`: replicar a mano la normalización de `demucs/separate.py` (restar media y dividir por la desviación de la mezcla mono, deshacer al final).
- `TORCH_HOME` antes de importar demucs → los pesos van a `out/weights/hub/checkpoints/` (htdemucs_6s = 5c90dfd2-34c22ccb.th, 55 MB).
- htdemucs_6s funciona en MPS con torch 2.7 sin fallback (demucs hace la STFT en CPU si el dispositivo es mps). Orden de stems: drums, bass, other, vocals, guitar, piano. segment = Fraction(39/5) (7,8 s): convertir a float antes de volcarlo a JSON.
- `shifts=1` aplica un desplazamiento aleatorio: fijar `random.seed` y `torch.manual_seed` en cada pasada para que sea reproducible.

**Why:** la instalación con restricciones falló al primer intento por la ruta con espacios.
**How to apply:** al añadir paquetes al venv, siempre con `-c` (copia sin espacios) y comprobando después las versiones de torch/numpy. Ver [[coreml-env-traps]].
