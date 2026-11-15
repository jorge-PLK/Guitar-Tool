"""HTDemucs 6s original (paquete demucs 4.0.1), medición de calidad y velocidad. Un tema por proceso.
Uso:
  separate.py --download                 # solo descarga los pesos a out/weights (ligero)
  separate.py T1 [--runs 2] [--device mps|cpu]   # lanzar SIEMPRE con common/guard.py
Configuración por defecto de la CLI de demucs: segment del modelo, overlap 0.25, shifts=1 (semilla fija),
normalización por media/desviación de la mezcla mono como en demucs/separate.py.
Salidas: out/stems/<T>/<stem>.wav, out/results/<T>.json, out/separate_<T>.log"""
import argparse
import json
import logging
import os
import random
import sys
import time
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
REPO = ROOT.parents[2]
TESTAUDIO = REPO / "Probes" / "testaudio" / "out"
WEIGHTS = OUT / "weights"
os.environ["TORCH_HOME"] = str(WEIGHTS)  # torch.hub guarda aquí los pesos (no versionado)
sys.path.insert(0, str(ROOT.parent / "common"))

import numpy as np  # noqa: E402
import torch  # noqa: E402
from demucs.apply import apply_model  # noqa: E402
from demucs.pretrained import get_model  # noqa: E402

from metrics import PeakMem, load_wav, quality_table, save_wav  # noqa: E402

MODEL = "htdemucs_6s"
SEED = 0

ap = argparse.ArgumentParser()
ap.add_argument("track", nargs="?")
ap.add_argument("--runs", type=int, default=1)
ap.add_argument("--device", default="mps")
ap.add_argument("--download", action="store_true")
a = ap.parse_args()

OUT.mkdir(parents=True, exist_ok=True)
log = logging.getLogger("htdemucs")
log.setLevel(logging.INFO)
fh = logging.FileHandler(OUT / f"separate_{a.track or 'download'}.log")
fh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(fh)
sys.excepthook = lambda t, v, tb: log.error("EXCEPCIÓN\n%s", "".join(traceback.format_exception(t, v, tb)))

log.info("demucs/torch/numpy: %s %s %s", __import__("demucs").__version__, torch.__version__, np.__version__)
model = get_model(MODEL)
model.eval()
ckpts = sorted(WEIGHTS.rglob("*.th"))
size_mb = sum(p.stat().st_size for p in ckpts) / 1e6
n_par = sum(p.numel() for p in model.parameters())
sub = model.models[0] if hasattr(model, "models") else model
log.info("modelo %s: %d submodelos, %.1f M parámetros, %.1f MB (%s), sources %s, segment %s, sr %d",
         MODEL, len(getattr(model, "models", [model])), n_par / 1e6, size_mb, [p.name for p in ckpts],
         model.sources, getattr(sub, "segment", None), model.samplerate)
if a.download:
    print(f"pesos: {size_mb:.1f} MB, {n_par / 1e6:.1f} M parámetros, stems {model.sources}")
    raise SystemExit

dev = a.device if (a.device != "mps" or torch.backends.mps.is_available()) else "cpu"
mix_path = TESTAUDIO / a.track / "mix.wav"
mix, sr = load_wav(mix_path)
assert sr == model.samplerate, (sr, model.samplerate)
dur_min = mix.shape[1] / sr / 60
log.info("tema %s: %.2f min, %d canales, dispositivo %s", a.track, dur_min, mix.shape[0], dev)

runs, sources = [], None
for i in range(a.runs):
    random.seed(SEED)
    torch.manual_seed(SEED)
    wav = torch.from_numpy(mix)
    with PeakMem() as pm:
        t0 = time.perf_counter()
        with torch.no_grad():
            ref = wav.mean(0)
            w = (wav - ref.mean()) / ref.std()
            out = apply_model(model, w[None], device=dev, shifts=1, split=True, overlap=0.25,
                              progress=False, num_workers=0)[0]
            out = out * ref.std() + ref.mean()
        if dev == "mps":
            torch.mps.synchronize()
        sec = time.perf_counter() - t0
    sources = out.numpy()
    runs.append({"sec": sec, "sec_per_min": sec / dur_min, "peak_gb": pm.peak / 1e9})
    log.info("pasada %d: %.1f s (%.1f s/min), pico %.2f GB", i + 1, sec, sec / dur_min, pm.peak / 1e9)
    del out, w

stem_dir = OUT / "stems" / a.track
for s, x in zip(model.sources, sources):
    save_wav(stem_dir / f"{s}.wav", x, sr)
q = quality_table(stem_dir, TESTAUDIO / a.track / "stems", mix_path, model.sources)
for s, v in q.items():
    log.info("calidad %s %s", s, v)
res = {"model": MODEL, "via": f"pytorch_{dev}", "device": dev, "demucs": __import__("demucs").__version__,
       "torch": torch.__version__, "segment": float(getattr(sub, "segment", 0)), "overlap": 0.25, "shifts": 1,
       "seed": SEED, "size_mb": size_mb, "params_m": n_par / 1e6, "track": a.track, "dur_min": dur_min,
       "runs": runs, "quality": q}
(OUT / "results").mkdir(parents=True, exist_ok=True)
json.dump(res, open(OUT / "results" / f"{a.track}.json", "w"), indent=1)
g = q.get("guitar", {})
print(f"{a.track} {dev}: {min(r['sec_per_min'] for r in runs):.1f} s/min, pico {max(r['peak_gb'] for r in runs):.2f} GB,"
      f" guitarra SDR {g.get('sdr', float('nan')):.2f} dB")
