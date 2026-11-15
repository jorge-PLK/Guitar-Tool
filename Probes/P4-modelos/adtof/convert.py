"""Convierte ADTOF Frame_RNN (puerto PyTorch) a Core ML (mlprogram) con longitud temporal flexible.

Uso: Tools/py/.venv/bin/python Probes/P4-modelos/adtof/convert.py --prec fp16|fp32 [--attempt N]
Entrada `spec` (1, T, 84, 1) f32 (T flexible 100..60000, tramas a 100 fps) → salida `act` (1, T, 5) sigmoide
[bombo 35, caja 38, tom 47, charles 42, platos 49]. Escribe out/conv/adtof_<prec>.mlpackage y comprueba la
diferencia con PyTorch sobre 20 s del stem de T1. Log en out/logs/convert.log.
"""
import argparse
import collections
import json
import time

import numpy as np
import torch

import ad_common as C

ap = argparse.ArgumentParser()
ap.add_argument("--prec", choices=["fp16", "fp32"], required=True)
ap.add_argument("--attempt", type=int, default=1)
ap.add_argument("--gru", choices=["loop", "native"], default="native",
                help="loop: traducción de coremltools (while_loop por paso, muy lenta); native: gru_native.py (iOS18)")
a = ap.parse_args()
log = C.setup_log("convert")

import coremltools as ct  # noqa: E402

if a.gru == "native":
    import gru_native  # noqa: F401,E402  (registra la traducción de aten::gru)
tag = a.prec + ("n" if a.gru == "native" else "")

log.info("intento %d %s: torch %s coremltools %s numpy %s", a.attempt, a.prec, torch.__version__, ct.__version__,
         np.__version__)
assert C.sha256(C.WEIGHTS) == C.WEIGHTS_SHA
m = C.load_torch()
x = torch.from_numpy(C.features(C.stem_path("T1"))[3000:5000])[None]     # 20 s del stem de T1
with torch.no_grad():
    ref = m(x).numpy()
    tr = torch.jit.trace(m, x)
ops = collections.Counter(n.kind() for n in tr.inlined_graph.nodes())
log.info("aten ops del trazado: %s", dict(ops))

T = ct.RangeDim(lower_bound=100, upper_bound=60000, default=2000)
t0 = time.time()
ml = ct.convert(
    tr,
    inputs=[ct.TensorType(name="spec", shape=(1, T, 84, 1), dtype=np.float32)],
    outputs=[ct.TensorType(name="act", dtype=np.float32)],
    convert_to="mlprogram",
    compute_precision=ct.precision.FLOAT16 if a.prec == "fp16" else ct.precision.FLOAT32,
    compute_units=ct.ComputeUnit.CPU_AND_GPU,
    minimum_deployment_target=ct.target.macOS15 if a.gru == "native" else ct.target.macOS13,
)
ml.short_description = "ADTOF Frame_RNN (Zehren et al., CC BY-NC-SA 4.0; puerto xavriley/ADTOF-pytorch 85c192e)"
ml.input_description["spec"] = "log10(1+filtro log 12 b/oct 20 Hz-20 kHz de |STFT| 2048/441 hann), 44,1 kHz mono, 100 fps"
ml.output_description["act"] = "sigmoide por trama: bombo35, caja38, tom47, charles42, platos49"
out = C.OUT / "conv" / f"adtof_{tag}.mlpackage"
out.parent.mkdir(parents=True, exist_ok=True)
ml.save(str(out))
t_conv = time.time() - t0
mil_ops = collections.Counter(op.op_type for f in ml._mil_program.functions.values() for op in f.operations)
log.info("MIL ops: %s", dict(mil_ops))

ml2 = ct.models.MLModel(str(out), compute_units=ct.ComputeUnit.CPU_AND_GPU)
y = ml2.predict({"spec": x.numpy()})["act"]
d = np.abs(y - ref)
info = {"prec": tag, "attempt": a.attempt, "convert_s": round(t_conv, 1), "max_diff": float(d.max()),
        "mean_diff": float(d.mean()), "size_mb": round(sum(f.stat().st_size for f in out.rglob("*") if f.is_file()) / 1e6, 2)}
log.info("%s", info)
(C.OUT / "conv" / f"adtof_{tag}.json").write_text(json.dumps(info, indent=1))
print(info)
