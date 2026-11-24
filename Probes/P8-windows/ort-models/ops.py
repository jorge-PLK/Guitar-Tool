"""Inventario de cada out/<modelo>/model.onnx: opset, entradas/salidas (nombre, forma, tipo), operadores y los
que pueden obligar a DirectML a caer a CPU. También prepara la lista de ficheros de la release (tamaño, SHA-256).

Uso: ops.py [modelo ...]   -> out/ops.json, out/release_files.txt; resumen por consola.
Si algún modelo conserva un GLU con Split (DirectML lo calcula mal), no escribe release_files.txt y sale con 1.
La tabla de kernels de DirectML (docs/OperatorKernels.md de onnxruntime) no se pudo bajar (GitHub 404 el
19/11/2026): la lista DUDOSOS es la conocida del EP de DirectML (sin flujo de control, sin secuencias, sin
dominio ai.onnx.ml; tensores int64 de formas en CPU) y se confirma en un PC con GPU."""
import hashlib
import json
import sys
from pathlib import Path

import onnx

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glu_slice import find_glu  # noqa: E402

OUT =Path(__file__).resolve().parent / "out"
MODELS = sys.argv[1:] or ["bs_roformer", "bs_roformer_T575", "lead_rhythm", "beat_this", "btc", "basic_pitch",
                          "adtof", "pose"]
# Operadores sin kernel de DirectML o con restricciones conocidas (caen a CPU o fallan al crear la sesión).
DUDOSOS = {"Loop": "flujo de control", "If": "flujo de control", "Scan": "flujo de control",
           "NonZero": "salida de forma dinámica", "Unique": "sin kernel DML", "STFT": "sin kernel DML",
           "SequenceAt": "secuencias", "SequenceConstruct": "secuencias", "Range": "int64, CPU",
           "Einsum": "DML solo algunas ecuaciones", "GRU": "kernel DML propio: comparar con CPU",
           "LSTM": "kernel DML propio: comparar con CPU", "GatherND": "índices int64",
           "ArgMax": "salida int64", "Cast": "a/desde int: posible copia a CPU", "Mod": "tipos limitados",
           "ScatterND": "reducciones no soportadas", "TopK": "salida int64"}
TYPES = {1: "float32", 6: "int32", 7: "int64", 10: "float16"}


def dims(vi):
    return [d.dim_value or d.dim_param for d in vi.type.tensor_type.shape.dim]


res, files, glu_bad = {}, [], []
for name in MODELS:
    p = OUT / name / "model.onnx"
    if not p.exists():
        continue
    real = p.resolve()
    m = onnx.load(str(real), load_external_data=False)
    ops = {}
    for n in m.graph.node:
        key = n.op_type if n.domain in ("", "ai.onnx") else f"{n.domain}:{n.op_type}"
        ops[key] = ops.get(key, 0) + 1
    r = {"file": str(real.relative_to(OUT.parents[2])) if OUT.parents[2] in real.parents else str(real),
         "size_mb": round(real.stat().st_size / 1e6, 1),
         "opset": {o.domain or "ai.onnx": o.version for o in m.opset_import},
         "inputs": [(i.name, dims(i), TYPES.get(i.type.tensor_type.elem_type)) for i in m.graph.input
                    if i.name not in {t.name for t in m.graph.initializer}],
         "outputs": [(o.name, dims(o), TYPES.get(o.type.tensor_type.elem_type)) for o in m.graph.output],
         "nodes": len(m.graph.node), "ops": dict(sorted(ops.items(), key=lambda kv: -kv[1])),
         "dudosos_dml": {k: f"{ops[k]}x {v}" for k, v in DUDOSOS.items() if k in ops}}
    n_glu = len(find_glu(m.graph))
    if n_glu:   # DirectML calcula mal el GLU con Split (22/11/2026): no entra en la release sin glu_slice.py
        r["dudosos_dml"]["GLU-Split"] = f"{n_glu}x mal en DML con fusión: glu_slice.py rewrite"
        glu_bad.append(name)
    del m
    h = hashlib.sha256()
    with open(real, "rb") as f:
        for b in iter(lambda: f.read(1 << 24), b""):
            h.update(b)
    r["sha256"] = h.hexdigest()
    res[name] = r
    files.append(f"{name}.onnx\t{real.stat().st_size}\t{r['sha256']}\t{real}")
    print(f"{name}: {r['size_mb']} MB opset {r['opset']} in {r['inputs']} out {r['outputs']} "
          f"dudosos {list(r['dudosos_dml'])}")
(OUT / "ops.json").write_text(json.dumps(res, indent=1))
if glu_bad:
    sys.exit(f"GLU con Split en {glu_bad}: pasar glu_slice.py rewrite; release_files.txt sin escribir")
(OUT / "release_files.txt").write_text("nombre\tbytes\tsha256\torigen\n" + "\n".join(files) + "\n")
