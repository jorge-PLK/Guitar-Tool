---
name: coreml-env-traps
description: Versiones que funcionan y trampas de coremltools/torch/numpy/ONNX en Tools/py/.venv (M3 Pro 18 GB)
metadata:
  type: project
---

Entorno de conversión (Python 3.12, uv) — trampas que costaron intentos:

- **coremltools 9.0 → torch máx 2.7.0** (`coremltools._deps._TORCH_MAX_VERSION`). Fijar torch==2.7.0.
- **numpy 2.5 rompe coremltools 9.0**: `TypeError: only 0-dimensional arrays can be converted to Python scalars` en `frontend/torch/ops.py _cast`. Con numpy 2.3.5 funciona. Mirar la versión de numpy ANTES del primer intento (uv instala la última).
- **Core ML: rango ≤ 5** en todo el grafo (falla al final de ct.convert, tras minutos). Al escribir envoltorios, no usar unsqueeze a rango 6 para difundir (broadcast).
- El código de MSST (ZFTurbo) importa librosa aunque solo uses BS-RoFormer (vía `models/bs_roformer/__init__`).
- rotary_embedding_torch usa una caché con `.item()`; para trazar con forma fija conviene parchear `rotate_queries_or_keys` con tablas cos/sin precalculadas (resultado idéntico, max 1e-6).
- **Memoria (18 GB)**: BS-RoFormer con trozo de 1151 tramas → la atención temporal de un trozo pide unos 2,5 GB. PyTorch en MPS: OOM (el asignador acumula unos 20 GB) → referencia en CPU. El exportador TorchScript de ONNX murió con exit 137 al volver a trazar el modelo con otro proceso pesado en marcha → exportar el ScriptModule ya trazado, sin plegado de constantes, y sin otro proceso pesado a la vez.
- Exportador TorchScript de ONNX (torch 2.7, opset 18) con el núcleo de BS-RoFormer a T=1151: pico de 48 GB de memoria (intercambio a disco) y exit 1. Antes de exportar, probar con T pequeño o con el exportador dynamo. Hay un ONNX de terceros que funciona (elicwhite/bs-roformer-sw-6stem-onnx), pero trazado a T=345 (trozos de 4 s), no a la configuración oficial.
- **TRAMPA GRAVE (2026-11-15): convertir BS-RoFormer con el trozo completo (1151 tramas) en Core ML más la compilación para el ANE (ANECompilerService al 80 % de CPU, proceso del sistema que no es hijo del script) más una descarga en paralelo colgaron el Mac de 18 GB (reinicio por watchdog).** Desde entonces es obligatorio: lanzar todo lo pesado con `Probes/P4-modelos/common/guard.py` (SIGKILL a 10 GB), un solo proceso pesado a la vez, `compute_units=CPU_AND_GPU` en ct.convert y al cargar (nunca `.all` ni `.cpuAndNeuralEngine` sin permiso expreso) y trozo corto (unas 345 tramas, 4 s).
- Medir la memoria con **un proceso por tema**: en un mismo proceso la huella sube de un tema a otro (en Core ML, de 5,9 a más de 10 GB en T1→T3) y el vigilante lo mata aunque cada tema por separado use menos de 6 GB. Medir también la vía `null` (la tubería numpy sin modelo, unos 2,3 GB en un tema de 5 min) para separar el modelo de la tubería.
- Ejecutar los procesos pesados de uno en uno: el límite de 3 intentos se gasta en fallos de memoria/entorno.
- **Las trazas de error siempre a fichero** (`sys.excepthook` → log). Nunca filtrar con grep la salida de un intento: se perdió el error del último intento de ONNX.

**Why:** cada conversión de un modelo de 700 MB tarda 2-5 min y el límite es de 3 intentos por vía.
**How to apply:** antes del primer ct.convert, comprobar versiones (torch ≤ máx de ct, numpy < 2.5), listar las aten ops del trazado y revisar el rango de los tensores del envoltorio. Ver [[bs-roformer-contract]].
