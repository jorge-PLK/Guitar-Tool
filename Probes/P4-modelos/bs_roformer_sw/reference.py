"""Referencia: BS-RoFormer SW original (PyTorch, código y demix() oficiales de MSST, config oficial).
Uso: reference.py T1 T2 [T3 ...] [--device mps|cpu] [--repeat 1]
Salida: out/ref_torch/<T>/<stem>.wav y out/ref_torch/<T>/timing.json"""
import argparse
import json
import time

import numpy as np

import sw_common as C
from metrics import PeakMem, load_wav, save_wav

ap = argparse.ArgumentParser()
ap.add_argument("tracks", nargs="+")
ap.add_argument("--device", default="mps")
ap.add_argument("--repeat", type=int, default=1)
args = ap.parse_args()

log = C.setup_log("reference")
import torch  # noqa: E402

model, config = C.load_model(log)
dev = torch.device(args.device if (args.device != "mps" or torch.backends.mps.is_available()) else "cpu")
model = model.to(dev)
from utils.model_utils import demix  # noqa: E402  (sys.path de MSST ya añadido)

log.info("torch %s device %s chunk %s overlap %s instruments %s", torch.__version__, dev,
         config.audio.chunk_size, config.inference.num_overlap, config.training.instruments)
assert list(config.training.instruments) == C.STEMS

summary = []
for name in args.tracks:
    mix, sr = load_wav(C.TESTAUDIO / name / "mix.wav")
    assert sr == C.SR and mix.shape[0] == 2
    dur_min = mix.shape[-1] / sr / 60
    runs = []
    for r in range(args.repeat):
        with PeakMem() as pm:
            t0 = time.perf_counter()
            res = demix(config, model, mix, dev, "bs_roformer", pbar=False)
            if dev.type == "mps":
                torch.mps.synchronize()
            dt = time.perf_counter() - t0
        runs.append({"sec": dt, "sec_per_min": dt / dur_min, "peak_gb": pm.peak / 1e9})
        log.info("%s run %d: %.1f s (%.1f s/min) pico %.2f GB", name, r, dt, dt / dur_min, pm.peak / 1e9)
    d = C.OUT / "ref_torch" / name
    for s in C.STEMS:
        save_wav(d / f"{s}.wav", res[s], sr)
    json.dump({"device": str(dev), "dur_min": dur_min, "runs": runs}, open(d / "timing.json", "w"), indent=1)
    summary.append(f"{name}: {np.mean([x['sec_per_min'] for x in runs]):.1f} s/min en {dev}, "
                   f"pico {max(x['peak_gb'] for x in runs):.2f} GB")
print("\n".join(summary))
