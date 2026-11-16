---
name: basic-pitch-contract
description: Basic Pitch (spotify/basic-pitch) — instalación sin TF en Python 3.12, nombres de salida del mlpackage, troceado y trampas de la herramienta (git clone, logging)
metadata:
  type: project
---

- `pip install basic-pitch` no se puede tal cual en el venv: pide tensorflow-macos < 2.15.1 (no hay para Py 3.12). Instalar `--no-deps basic-pitch==0.4.0` + pretty_midi 0.2.11 + importlib_resources + resampy 0.4.3 + six. pretty_midi 0.2.10 y resampy 0.4.2 importan `pkg_resources` (no está) y fallan al importar.
- El paquete pip trae nmp.mlpackage, nmp.onnx, nmp.tflite y SavedModel, idénticos al repo. Referencia de Python = nmp.onnx con ORT CPU (sin TF).
- Salidas Core ML: `Identity_1`=note, `Identity_2`=onset, `Identity`=contour (¡no en orden!). ONNX: `StatefulPartitionedCall:1/2/0` con entrada `serving_default_input_2:0`.
- La clase `Model` de basic_pitch carga Core ML con CPU_ONLY e imprime por consola en cada ventana: no usarla; trocear con `window_audio_file` + `unwrap_output` y un predictor propio.
- `ANNOTATIONS_FPS = 22050 // 256 = 86` (entero) para recortar; los tiempos usan 86,13 y un desfase «mágico» por ventana (`model_frames_to_time`).
- basic_pitch configura el logger raíz: poner `propagate = False` en el logger del script o el log sale por consola.
- Modelo FP32 de 270 KB: en CPU+GPU MLComputePlan pone todo en GPU y la GPU calcula en FP32 (dif 1e-6). No hizo falta el ANE.
- Zip reproducible (mismo SHA en cada ejecución): `os.utime` a fecha fija en todo el árbol + `ditto -c -k --norsrc --noextattr --keepParent`.
- Herramienta: el sandbox rechaza `git clone` a rutas con espacios del worktree y `git -C <ruta>`. Descargar de raw.githubusercontent.com en un commit fijo y verificar el SHA-1 de blob de git (`sha1(b"blob %d\0" + data)`) contra `gh api repos/.../git/trees/<commit>?recursive=1`; ejecutar git desde el cwd sin -C.

**Why:** la instalación costó 5 intentos de import; la asignación de salidas y el recorte entero son fáciles de equivocar al portar a Swift.
**How to apply:** reutilizar Probes/P4-modelos/basic_pitch/compare.py (infer/notes). Ver [[coreml-env-traps]], [[btc-contract]].
