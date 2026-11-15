"""Separación con el modelo convertido (STFT/iSTFT y troceado en numpy, como hará Swift) + métricas.
Uso: compare.py --via coreml_fp16|coreml_fp32|onnx --units all|cpu_gpu|cpu_ne|cpu [--repeat 2] T1 T2 ...
Una ejecución = un proceso (pico de memoria limpio). Stems en out/conv/<tag>/<T>/, resultados en
out/results/<tag>.json. Métricas: fidelidad frente a out/ref_torch/<T> y calidad frente a stems reales."""
import argparse
import json
import time

import numpy as np

import sw_common as C
from metrics import (PeakMem, fidelity_table, load_wav, phys_footprint, quality_table, save_wav)

ap = argparse.ArgumentParser()
ap.add_argument("tracks", nargs="+")
ap.add_argument("--via", required=True,
                choices=["coreml_fp16", "coreml_fp32", "coremlpub", "sunnymead", "onnx", "onnxpub", "null"])
ap.add_argument("--units", default="all", choices=["all", "cpu_gpu", "cpu_ne", "cpu"])
ap.add_argument("--repeat", type=int, default=2)
ap.add_argument("--no-save", action="store_true", help="solo velocidad")
ap.add_argument("--max-first-s", type=float, default=None, help="aborta si la primera inferencia tarda más")
ap.add_argument("--chunk", type=int, default=None, help="muestras por trozo del modelo Core ML (176400 = 4 s)")
args = ap.parse_args()
if args.via.startswith("coreml") and args.units in ("all", "cpu_ne"):
    raise SystemExit("ANE prohibido para este modelo: su compilación colgó el Mac (usar cpu_gpu o cpu)")
SUNNY_CHUNK = 255 * C.HOP          # 130560 muestras -> 256 tramas (2,96 s)
_chunk = args.chunk or {"onnxpub": C.PUB_CHUNK, "sunnymead": SUNNY_CHUNK}.get(args.via, C.CHUNK)
tag = (f"{args.via}_T{1 + _chunk // C.HOP}_{args.units}" if args.via.startswith("coreml_")
       else f"{args.via}_{args.units}")
log = C.setup_log(f"compare_{tag}")
import sys  # noqa: E402

sys.excepthook = lambda t, v, tb: log.error("excepción no capturada", exc_info=(t, v, tb))
chunk = _chunk
n_frames = 1 + chunk // C.HOP

t0 = time.perf_counter()
if args.via == "null":   # sin modelo: mide la memoria/tiempo de la tubería numpy (STFT, troceado, iSTFT)
    size = 0

    def run_spec(spec):
        return np.zeros((12,) + spec.shape[1:], np.float32)
elif args.via == "onnxpub":
    import onnxruntime as ort
    path = C.ensure_onnx_pub(log)
    if args.units == "cpu":
        prov = ["CPUExecutionProvider"]
    else:
        cu = {"all": "ALL", "cpu_gpu": "CPUAndGPU", "cpu_ne": "CPUAndNeuralEngine"}[args.units]
        prov = [("CoreMLExecutionProvider", {"ModelFormat": "MLProgram", "MLComputeUnits": cu,
                                             "RequireStaticInputShapes": "1"}), "CPUExecutionProvider"]
    so = ort.SessionOptions()
    sess = ort.InferenceSession(str(path), sess_options=so, providers=prov)
    log.info("ort %s providers activos: %s; entradas %s", ort.__version__, sess.get_providers(),
             [(i.name, i.shape) for i in sess.get_inputs()])
    size = path.stat().st_size

    def run_spec(spec):                                       # (2,F,T,2) -> (12,F,T,2)
        re, im = sess.run(["out_spec_real", "out_spec_imag"],
                          {"spec_real": spec[None, ..., 0], "spec_imag": spec[None, ..., 1]})
        return np.stack([re[0], im[0]], axis=-1).reshape(12, C.N_FREQ, -1, 2)
elif args.via == "coremlpub":
    # gridshiftstudio/bs-roformer-sw-coreml: spec [1, 2050, T, 2] (canales intercalados por bin, eje (f s))
    # -> mask [1, 6, 2050, T, 2]; el producto complejo y el DC a 0 (zero_dc del original) van fuera.
    import coremltools as ct
    units = {"cpu_gpu": ct.ComputeUnit.CPU_AND_GPU, "cpu": ct.ComputeUnit.CPU_ONLY}[args.units]
    path = C.OUT / "coreml_pub" / "BSRoformerSW.mlpackage"
    mdl = ct.models.MLModel(str(path), compute_units=units)
    size = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())

    def run_spec(spec):                                       # (2,F,T,2) -> (12,F,T,2)
        T = spec.shape[2]
        x = np.ascontiguousarray(spec.transpose(1, 0, 2, 3).reshape(1, 2 * C.N_FREQ, T, 2))
        m = next(iter(mdl.predict({"spec": x}).values()))[0].astype(np.float32)  # 6, 2050, T, 2 (salida FP16)
        sr_, si_ = x[0, ..., 0], x[0, ..., 1]
        out = np.stack([sr_ * m[..., 0] - si_ * m[..., 1], sr_ * m[..., 1] + si_ * m[..., 0]], -1)
        out[:, :2] = 0.0                                                      # DC (f=0, ambos canales)
        return out.reshape(6, C.N_FREQ, 2, T, 2).transpose(0, 2, 1, 3, 4).reshape(12, C.N_FREQ, T, 2)
elif args.via == "sunnymead":
    # sunnymeadsound/stem-separation-models bs_roformer_6stem: spectrogram [1,4,1025,256] canales
    # (L-re, L-im, R-re, R-im) -> stems_spectrogram [1,6,4,1025,256] = espectro ya enmascarado
    # (deducido con probe_sunnymead.py). DC a 0 fuera, como zero_dc del original.
    # Trozo corto -> aquí sí se permite ANE (all / cpu_ne), siempre tras cpu_gpu y con el vigilante.
    import coremltools as ct
    units = {"all": ct.ComputeUnit.ALL, "cpu_gpu": ct.ComputeUnit.CPU_AND_GPU,
             "cpu_ne": ct.ComputeUnit.CPU_AND_NE, "cpu": ct.ComputeUnit.CPU_ONLY}[args.units]
    path = C.OUT / "coreml_pub_sunnymead" / "bs_roformer_6stem.mlpackage"
    mdl = ct.models.MLModel(str(path), compute_units=units)
    size = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())

    def run_spec(spec):                                       # (2,F,T,2) -> (12,F,T,2)
        x = spec.transpose(0, 3, 1, 2).reshape(1, 4, C.N_FREQ, -1)          # (c, ri) -> L-re,L-im,R-re,R-im
        y = mdl.predict({"spectrogram": np.ascontiguousarray(x)})["stems_spectrogram"][0]   # 6,4,F,T
        y = y.reshape(6, 2, 2, C.N_FREQ, -1).transpose(0, 1, 3, 4, 2).reshape(12, C.N_FREQ, -1, 2)
        y[:, 0] = 0.0
        return y
elif args.via.startswith("coreml"):
    import coremltools as ct
    units = {"all": ct.ComputeUnit.ALL, "cpu_gpu": ct.ComputeUnit.CPU_AND_GPU,
             "cpu_ne": ct.ComputeUnit.CPU_AND_NE, "cpu": ct.ComputeUnit.CPU_ONLY}[args.units]
    path = C.OUT / "coreml" / f"bs_roformer_sw_{args.via.split('_')[1]}_T{n_frames}.mlpackage"
    mdl = ct.models.MLModel(str(path), compute_units=units)
    size = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())

    def run_spec(spec):
        return mdl.predict({"spec": spec})["stems_spec"]
else:
    import onnxruntime as ort
    path = C.OUT / "onnx" / "bs_roformer_sw_fp32.onnx"
    if args.units == "cpu":
        prov = ["CPUExecutionProvider"]
    else:
        cu = {"all": "ALL", "cpu_gpu": "CPUAndGPU", "cpu_ne": "CPUAndNeuralEngine"}[args.units]
        prov = [("CoreMLExecutionProvider", {"ModelFormat": "MLProgram", "MLComputeUnits": cu,
                                             "RequireStaticInputShapes": "1"}), "CPUExecutionProvider"]
    sess = ort.InferenceSession(str(path), providers=prov)
    log.info("ort providers activos: %s", sess.get_providers())
    size = sum(f.stat().st_size for f in path.parent.glob("bs_roformer_sw_fp32.onnx*"))

    def run_spec(spec):
        return sess.run(["stems_spec"], {"spec": spec})[0]

load_s = time.perf_counter() - t0
# primera predicción (compilación/especialización de Core ML) fuera de la medida de canción
t0 = time.perf_counter()
run_spec(np.zeros((2, C.N_FREQ, n_frames, 2), np.float32))
warm_s = time.perf_counter() - t0
log.info("%s carga %.1f s, primera inferencia %.1f s, tamaño %.0f MB", tag, load_s, warm_s, size / 1e6)
if args.max_first_s and warm_s > args.max_first_s:
    second_s = None
    if True:
        (C.OUT / "results").mkdir(exist_ok=True)
        json.dump({"tag": tag, "chunk": chunk, "size_mb": size / 1e6, "load_s": load_s, "first_infer_s": warm_s,
                   "second_infer_s": second_s, "status": f"abortado: inferencia > {args.max_first_s} s"},
                  open(C.OUT / "results" / f"{tag}.json", "w"), indent=1)
        print(f"{tag}: ABORTADO, carga {load_s:.1f} s, primera inferencia {warm_s:.1f} s por trozo")
        raise SystemExit(3)


def run_chunk(part):
    y = run_spec(C.stft_np(part))
    return C.istft_np(y, chunk).reshape(len(C.STEMS), 2, -1)


res = {"tag": tag, "chunk": chunk, "size_mb": size / 1e6, "load_s": load_s, "first_infer_s": warm_s, "tracks": {}}
for name in args.tracks:
    mix, sr = load_wav(C.TESTAUDIO / name / "mix.wav")
    dur_min = mix.shape[-1] / sr / 60
    runs = []
    for r in range(args.repeat):
        with PeakMem() as pm:
            t0 = time.perf_counter()
            est = C.demix_np(mix, run_chunk, chunk=chunk)
            dt = time.perf_counter() - t0
        runs.append({"sec": dt, "sec_per_min": dt / dur_min, "peak_gb": pm.peak / 1e9})
        log.info("%s run %d: %.1f s (%.1f s/min) pico %.2f GB", name, r, dt, dt / dur_min, pm.peak / 1e9)
    tr = {"dur_min": dur_min, "runs": runs}
    if not args.no_save and args.via != "null":
        d = C.OUT / "conv" / tag / name
        for k, s in enumerate(C.STEMS):
            save_wav(d / f"{s}.wav", est[k], sr)
        refd = C.OUT / "ref_torch" / name
        if refd.exists():
            tr["fidelity"] = fidelity_table(d, refd, C.STEMS)
            tr["quality_torch"] = quality_table(refd, C.TESTAUDIO / name / "stems",
                                                C.TESTAUDIO / name / "mix.wav", C.STEMS)
        tr["quality_conv"] = quality_table(d, C.TESTAUDIO / name / "stems", C.TESTAUDIO / name / "mix.wav", C.STEMS)
        log.info("%s %s", name, json.dumps({k: tr[k] for k in tr if k != "runs"}))
    res["tracks"][name] = tr
    del est, mix
    import gc
    gc.collect()

res["lifetime_peak_gb"] = phys_footprint()[1] / 1e9
(C.OUT / "results").mkdir(exist_ok=True)
rp = C.OUT / "results" / f"{tag}.json"
if rp.exists():  # un proceso por tema: fusionar con lo ya medido
    old = json.load(open(rp))
    old["tracks"].update(res["tracks"])
    res["tracks"] = old["tracks"]
json.dump(res, open(rp, "w"), indent=1)
lines = [f"{tag}: {size / 1e6:.0f} MB, carga {load_s:.1f}+{warm_s:.1f} s, pico vida {res['lifetime_peak_gb']:.2f} GB"]
for name, tr in res["tracks"].items():
    spm = [x["sec_per_min"] for x in tr["runs"]]
    fid = tr.get("fidelity")
    f = f", SDR vs torch min {min(v['sdr_vs_orig'] for v in fid.values()):.1f} dB" if fid else ""
    lines.append(f"  {name}: s/min {' / '.join(f'{v:.1f}' for v in spm)}{f}")
print("\n".join(lines))
