"""Transcribe el stem de batería de un tema con ADTOF (una vía, un tema por proceso; lanzar bajo guard.py).

Uso: Tools/py/.venv/bin/python Probes/P4-modelos/adtof/run.py --song T1 --via torch|coreml_fp16|coreml_fp32
Salidas: out/act/<vía>/T*.npy (activaciones T×5), out/hits/<vía>/T*/<pieza>.txt, out/midi/<vía>/T*.mid,
out/runs/<vía>_T*.json (tiempos). Log en out/logs/run.log.
"""
import argparse
import json
import time

import numpy as np

import ad_common as C

ap = argparse.ArgumentParser()
ap.add_argument("--song", required=True)
ap.add_argument("--via", required=True, choices=["torch", "coreml_fp16", "coreml_fp32", "coreml_fp16n", "coreml_fp32n"])
a = ap.parse_args()
log = C.setup_log("run")

t0 = time.perf_counter()
x = C.features(C.stem_path(a.song))                     # (T, 84, 1)
t_feat = time.perf_counter() - t0

t1 = time.perf_counter()
if a.via == "torch":
    import torch
    m = C.load_torch()
    t_load = time.perf_counter() - t1
    t1 = time.perf_counter()
    with torch.no_grad():
        act = m(torch.from_numpy(x)[None]).numpy()[0]
else:
    import coremltools as ct
    pkg = C.OUT / "conv" / f"adtof_{a.via.split('_')[1]}.mlpackage"
    # GRU nativa (vías *n): la GPU calcula mal gru con reset_after (dif. 0,52 frente a 5e-7 en CPU) → CPU_ONLY
    cu = ct.ComputeUnit.CPU_ONLY if a.via.endswith("n") else ct.ComputeUnit.CPU_AND_GPU
    m = ct.models.MLModel(str(pkg), compute_units=cu)
    t_load = time.perf_counter() - t1
    t1 = time.perf_counter()
    act = m.predict({"spec": x[None].astype(np.float32)})["act"][0]
t_model = time.perf_counter() - t1

t2 = time.perf_counter()
hits = C.pick(act.astype(np.float32))
t_pick = time.perf_counter() - t2
total = time.perf_counter() - t0

dur = x.shape[0] / C.FPS
(C.OUT / "act" / a.via).mkdir(parents=True, exist_ok=True)
np.save(C.OUT / "act" / a.via / f"{a.song}.npy", act.astype(np.float32))
C.save_hits(hits, C.OUT / "hits" / a.via / a.song)
C.write_midi(hits, C.OUT / "midi" / a.via / f"{a.song}.mid")
info = {"song": a.song, "via": a.via, "frames": int(x.shape[0]), "audio_s": round(dur, 2),
        "feat_s": round(t_feat, 3), "load_s": round(t_load, 3), "model_s": round(t_model, 3),
        "pick_s": round(t_pick, 3), "total_s": round(total, 3),
        "total_s_per_audio_min": round(total / dur * 60, 3), "hits": {k: int(len(v)) for k, v in hits.items()}}
(C.OUT / "runs").mkdir(parents=True, exist_ok=True)
(C.OUT / "runs" / f"{a.via}_{a.song}.json").write_text(json.dumps(info, indent=1))
log.info("%s", info)
print(f"{a.via} {a.song}: {info['hits']} total {info['total_s']} s (modelo {info['model_s']} s)")
