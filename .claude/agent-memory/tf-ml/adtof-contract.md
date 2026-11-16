---
name: adtof-contract
description: ADTOF (batería) — puerto PyTorch, dependencias fuera del venv, trampa de GRU en coremltools (while_loop lento, gru nativa mal en GPU), contrato y trampas de la referencia por pistas sueltas
metadata:
  type: project
---

- Puerto: github xavriley/ADTOF-pytorch (commit 85c192e, SIN licencia propia; original MZehren/ADTOF CC BY-NC-SA 4.0). Pesos incluidos en el repo (3,6 MB). Se usa por sys.path, sin instalar.
- El puerto importa pretty_midi, que necesita pkg_resources (no está en el venv) → módulo falso en sys.modules con `PrettyMIDI = object`; MIDI con mido. mir_eval/pyloudnorm/mido/future ya están en Tools/py/requirements.txt (pyloudnorm 0.1.1 necesita `future`).
- Entrada: 84 bandas (no 168: el README engaña), `calculate_n_bins()` = 84. Contrato: spec (1,T,84,1) → (1,T,5) sigmoide [35,38,47,42,49], 100 fps, umbrales 0.22/0.24/0.32/0.22/0.30.
- **coremltools 9.0 traduce aten::gru a while_loop por paso**: fiel pero 40-70 veces más lento (52 s en un tema de 3 min). Arreglo: `adtof/gru_native.py` → MIL `gru` iOS18 (macOS15) con reset_after=True, orden de puertas PyTorch r,z,n → Core ML r,n,z, bias=b_h, input_bias=b_i, y **la salida de direction="reverse" sale invertida en el tiempo** (hay que darle la vuelta).
- **La GPU calcula mal la gru nativa** (dif. 0,52 en FP32 y FP16); en CPU_ONLY dif. 5e-7. Usar CPU_ONLY (FP32): 0,35-0,55 s por tema.
- Referencia por pistas sueltas: las pistas de Cambridge MT pueden ir con puerta (silencio digital) → poner suelo a la envolvente en dB (máx − 60 dB) o los saltos desde −180 dB roban picos (perdí 170 bombos en T1). Ventana RMS ≥ un periodo de la banda (bombo 20 ms). HOP de 44 muestras ≠ 1 ms exacto: convertir con SR/HOP, no ×1000.
- `out/conv/adtof_fp32n.json` dice max_diff 0,52: es la comprobación de convert.py en CPU_AND_GPU (GPU mal), no un modelo roto. Para saber si un .mlpackage es el bueno sin ejecutarlo: `ct.utils.load_spec` y contar ops MIL (gru 6, while_loop 0) y "FLOAT16" en `str(spec.mlProgram)` (0) — lo hace `adtof/package.py`.
- Embebido en la app (Fase 5): `adtof/package.py --install` da un zip idéntico en cada ejecución (mtime fijo + ditto --norsrc --noextattr); fixture de TabKit con `make_fase5_fixture.py`. Picos del puerto: el umbral se aplica a act − media móvil, no a la activación.
- Sesiones en worktree: `git -C <ruta>` se rechaza (usar git sin -C); en zsh, `--include="*.swift"` entre comillas.

**Why:** cada trampa costó 2-4 turnos.
**How to apply:** reutilizar adtof/ad_common.py, gru_native.py y reference.py para cualquier modelo con GRU o cualquier referencia de pistas sueltas. Ver [[coreml-env-traps]].
