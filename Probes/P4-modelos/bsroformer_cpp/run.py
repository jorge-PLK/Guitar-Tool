"""BSRoformer.cpp (GGML, Metal) con el GGUF q8_0 de BS-RoFormer SW. Uso: run.py T1 [T2 ...] [--repeat 1]
Requisitos: compilado en out/build (ver BUILD abajo). Lanzar con ../common/guard.py.
- Descarga el GGUF a out/ y verifica sha256.
- Ejecuta la CLI con el trozo oficial (588800 muestras, 2 solapes), mide tiempo de pared y pico de
  phys_footprint del proceso CLI, guarda su salida en out/cli_<T>.log.
- Renombra stem_0..5 -> bass, drums, other, vocals, guitar, piano en out/stems/<T>/ y calcula métricas
  (fidelidad frente a la referencia PyTorch de bs_roformer_sw y calidad frente a los stems reales).
- Resultados en ../bs_roformer_sw/out/results/bsrcpp_q8_metal.json (misma estructura que compare.py).
BUILD (reproducible): src = chenmozhijin/BSRoformer.cpp @ a7b9625f; ggml = ggml-org/ggml @ 3af5f576 en out/ggml;
  cmake -S out/src -B out/build -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
  cmake --build out/build --config Release -j 8 --target bs_roformer-cli"""
import argparse
import ctypes
import hashlib
import json
import logging
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
sys.path.insert(0, str(ROOT.parent / "common"))
sys.path.insert(0, str(ROOT.parent / "bs_roformer_sw"))
import sw_common as SW  # noqa: E402
from metrics import fidelity_table, load_wav, quality_table  # noqa: E402

GGUF_URL = "https://huggingface.co/FractalSurfer/BS-RoFormer-SW-6stem/resolve/main/gguf/BS-RoFormer-SW-6stem-q8_0.gguf"
GGUF = OUT / "BS-RoFormer-SW-6stem-q8_0.gguf"
GGUF_SHA = "e4c53c3389c4426bf8b6cdbcc4e3d7d813323ef8a3e4f1f157084b71960bdf63"
CLI = OUT / "build" / "bs_roformer-cli"
TAG = "bsrcpp_q8_metal"

ap = argparse.ArgumentParser()
ap.add_argument("tracks", nargs="+")
ap.add_argument("--repeat", type=int, default=1)
args = ap.parse_args()

OUT.mkdir(exist_ok=True)
log = logging.getLogger("bsrcpp")
log.setLevel(logging.INFO)
fh = logging.FileHandler(OUT / "run.log")
fh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(fh)
sys.excepthook = lambda t, v, tb: log.error("excepción no capturada", exc_info=(t, v, tb))

if not GGUF.exists():
    log.info("descargando GGUF")
    urllib.request.urlretrieve(GGUF_URL, GGUF)
h = hashlib.sha256()
with open(GGUF, "rb") as f:
    for b in iter(lambda: f.read(1 << 20), b""):
        h.update(b)
if h.hexdigest() != GGUF_SHA:
    raise RuntimeError(f"sha256 del GGUF no coincide: {h.hexdigest()}")
log.info("GGUF ok (%d B)", GGUF.stat().st_size)

_lib = ctypes.CDLL("/usr/lib/libproc.dylib")


class _Ru(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(f"f{i}", ctypes.c_uint64) for i in range(35)]


def footprint(pid):
    b = _Ru()
    return int(b.f7) if _lib.proc_pid_rusage(pid, 4, ctypes.byref(b)) == 0 else 0


def run_cli(mix_path, out_wav, cli_log):
    with open(cli_log, "w") as lf:
        t0 = time.perf_counter()
        p = subprocess.Popen([str(CLI), str(GGUF), str(mix_path), str(out_wav), "--chunk-size", str(SW.CHUNK),
                              "--overlap", str(SW.NUM_OVERLAP)], stdout=lf, stderr=subprocess.STDOUT)
        peak = [0]

        def samp():
            while p.poll() is None:
                peak[0] = max(peak[0], footprint(p.pid))
                time.sleep(0.05)
        th = threading.Thread(target=samp, daemon=True)
        th.start()
        rc = p.wait()
        dt = time.perf_counter() - t0
        th.join()
    if rc != 0:
        raise RuntimeError(f"CLI rc={rc}; ver {cli_log}")
    return dt, peak[0]


res_path = SW.OUT / "results" / f"{TAG}.json"
res = json.load(open(res_path)) if res_path.exists() else {"tag": TAG, "chunk": SW.CHUNK, "tracks": {}}
res["size_mb"] = GGUF.stat().st_size / 1e6
res["build"] = {"src": "chenmozhijin/BSRoformer.cpp@a7b9625f", "ggml": "ggml-org/ggml@3af5f576"}
lines = []
for name in args.tracks:
    mix_path = SW.TESTAUDIO / name / "mix.wav"
    mix, sr = load_wav(mix_path)
    dur_min = mix.shape[-1] / sr / 60
    d = OUT / "stems" / name
    d.mkdir(parents=True, exist_ok=True)
    runs = []
    for r in range(args.repeat):
        dt, pk = run_cli(mix_path, d / "out.wav", OUT / f"cli_{name}_{r}.log")
        runs.append({"sec": dt, "sec_per_min": dt / dur_min, "peak_gb": pk / 1e9})
        log.info("%s run %d: %.1f s (%.1f s/min) pico CLI %.2f GB", name, r, dt, dt / dur_min, pk / 1e9)
    for i, s in enumerate(SW.STEMS):
        (d / f"out_stem_{i}.wav").replace(d / f"{s}.wav")
    tr = {"dur_min": dur_min, "runs": runs,
          "fidelity": fidelity_table(d, SW.OUT / "ref_torch" / name, SW.STEMS),
          "quality_conv": quality_table(d, SW.TESTAUDIO / name / "stems", mix_path, SW.STEMS)}
    log.info("%s %s", name, json.dumps({k: tr[k] for k in ("fidelity", "quality_conv")}))
    res["tracks"][name] = tr
    fid = " ".join(f"{s}={v['sdr_vs_orig']:.1f}" for s, v in tr["fidelity"].items())
    lines.append(f"{name}: s/min {' / '.join(f'{x['sec_per_min']:.1f}' for x in runs)}, "
                 f"pico {max(x['peak_gb'] for x in runs):.2f} GB; SDR vs torch {fid}")
json.dump(res, open(res_path, "w"), indent=1)
print("\n".join(lines))
