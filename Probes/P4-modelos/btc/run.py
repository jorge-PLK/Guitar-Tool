"""Acordes de un tema con una vía. Un proceso por tema × entrada × vía (para medir la memoria con el vigilante).
Uso: run.py --tema T1 --input stems|mix --via torch|coreml_gpu|coreml_ane [--prec fp16]
Tiempo medido: desde el audio ya leído (suma de stems, mono, 22 kHz, CQT, normalizado) hasta las líneas del .lab;
excluye solo la carga del modelo. Salidas: out/lab/<via>/, out/pred/<via>/, out/results/runs/."""
import argparse
import json
import time

import numpy as np

import btc_common as C

ap = argparse.ArgumentParser()
ap.add_argument("--tema", required=True, choices=C.TEMAS)
ap.add_argument("--input", required=True, choices=["stems", "mix"])
ap.add_argument("--via", required=True, choices=["torch", "coreml_gpu", "coreml_ane"])
ap.add_argument("--prec", default="fp16", choices=["fp16", "fp32"])
a = ap.parse_args()
via = a.via if a.via == "torch" else f"{a.via}_{a.prec}"
tag = f"{via}_{a.tema}_{a.input}"
log = C.setup_log("run")
log.info("=== %s ===", tag)
names = C.idx2voca()

# Carga del modelo (excluida del tiempo)
t0 = time.perf_counter()
if a.via == "torch":
    import torch
    torch.set_grad_enabled(False)
    model, mean, std = C.load_torch_model()

    def infer(w: np.ndarray) -> np.ndarray:
        x = torch.from_numpy(w)
        return model.output_layer.output_projection(model.self_attn_layers(x)[0]).numpy()
else:
    import coremltools as ct
    _, mean, std = C.load_torch_model()  # solo mean/std (también están en los metadatos del mlpackage)
    cu = ct.ComputeUnit.CPU_AND_GPU if a.via == "coreml_gpu" else ct.ComputeUnit.CPU_AND_NE
    path = C.OUT / "coreml" / f"BTC_large_voca_{a.prec}.mlpackage"
    ml = ct.models.MLModel(str(path), compute_units=cu)

    def infer(w: np.ndarray) -> np.ndarray:
        return ml.predict({"cqt": w})["logits"]
t_load = time.perf_counter() - t0

xs, sr = C.load_input(a.tema, a.input)  # lectura del WAV, excluida

t0 = time.perf_counter()
wav = C.to_mono_22k(xs, sr)
feat = C.cqt_features(wav)
wins, num_pad = C.normalize_windows(feat, mean, std)
t1 = time.perf_counter()
logits = np.empty((wins.shape[0], C.T, C.N_CHORDS), np.float32)
t_first = None
for i in range(wins.shape[0]):
    ti = time.perf_counter()
    logits[i] = infer(wins[i:i + 1])[0]
    if t_first is None:
        t_first = time.perf_counter() - ti
t2 = time.perf_counter()
pred = logits.argmax(-1)
lines = C.frames_to_lab(pred, num_pad, names)
t3 = time.perf_counter()

lab = C.OUT / "lab" / via / f"{a.tema}_{a.input}.lab"
lab.parent.mkdir(parents=True, exist_ok=True)
lab.write_text("".join(lines))
npz = C.OUT / "pred" / via / f"{a.tema}_{a.input}.npz"
npz.parent.mkdir(parents=True, exist_ok=True)
np.savez_compressed(npz, pred=pred, logits=logits, num_pad=num_pad)
res = {
    "tema": a.tema, "input": a.input, "via": via, "duration_s": len(wav) / C.SR,
    "n_windows": int(wins.shape[0]), "n_frames_valid": int(pred.size - num_pad), "n_segments": len(lines),
    "load_model_s": t_load, "pre_s": t1 - t0, "infer_s": t2 - t1, "first_window_s": t_first,
    "post_s": t3 - t2, "total_s": t3 - t0,
}
rj = C.OUT / "results" / "runs" / f"{tag}.json"
rj.parent.mkdir(parents=True, exist_ok=True)
rj.write_text(json.dumps(res, indent=1))
log.info("%s", res)

if a.via == "coreml_ane":  # qué operaciones caen en el ANE (fuera del tiempo medido)
    try:
        from collections import Counter
        from coremltools.models.compute_plan import MLComputePlan
        plan = MLComputePlan.load_from_path(path=ml.get_compiled_model_path(), compute_units=cu)
        ops = plan.model_structure.program.functions["main"].block.operations
        dev = Counter(type(plan.get_compute_device_usage_for_mlprogram_operation(o).preferred_compute_device).__name__
                      for o in ops if plan.get_compute_device_usage_for_mlprogram_operation(o) is not None)
        log.info("plan de cálculo (operaciones por dispositivo preferido): %s", dict(dev))
    except Exception as e:  # informativo
        log.warning("sin plan de cálculo: %r", e)

print(f"{tag}: total {res['total_s']:.2f} s (pre {res['pre_s']:.2f} · inf {res['infer_s']:.2f} · post {res['post_s']:.3f})"
      f" · carga {t_load:.1f} s · {len(lines)} segmentos")
C.progress(f"{tag} hecho: {res['total_s']:.1f} s por tema, {len(lines)} segmentos")
