"""Validación del ONNX lead/rhythm (Windows, ADR-020) frente a PyTorch original y al Core ML de la app.

No reconvierte: usa el ONNX ya exportado por Probes/P8-windows/ort-models/prepare.py (lead_rhythm export) y el
zip de Core ML embebido en la app. Entrada real: Probes/testaudio/out/T1/stems/guitar.wav (pista de guitarras).

Uso (bajo common/guard.py, de una en una):
  onnx_check.py chunk   # un trozo: máscara ORT frente a núcleo torch y Core ML (fallo rápido: SNR ≥ 60 dB)
  onnx_check.py e2e     # 60 s, num_overlap 2 (contrato del Mac): solista y rítmica, error y SDR por tallo; tiempos
Salida: out/onnx_check/ (log, results.json, WAV CHECK_*). Consola: resumen corto."""
import json
import logging
import statistics
import sys
import time
import zipfile
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
P4 = HERE.parent
sys.path.insert(0, str(P4 / "common"))
sys.path.insert(0, str(P4 / "bs_roformer_sw"))
sys.path.insert(0, str(HERE))
import metrics as M  # noqa: E402
import sw_common as C  # noqa: E402
import lr_common as L  # noqa: E402

L.MSST = C.MSST                                   # clon de MSST, commit 1f700c38
ONNX = REPO / "Probes/P8-windows/ort-models/out/lead_rhythm/model.onnx"
ONNX_SHA = "e0c42b06b617efd1649892d912d721e049eee25ac2dc4ed736762b4a657e34b4"
CM_ZIP = REPO / "App/Resources/Models/LeadRhythmMelRoformer_fp16.mlpackage.zip"
GUITAR = REPO / "Probes/testaudio/out/T1/stems/guitar.wav"
START_S, DUR_S, LISTEN_S = 60, 60, 25
OVERLAP = 2                                       # MaskModelContract.leadRhythm (app del Mac)
SNR_SAME_NET = 60.0                               # ADR-020: misma red
SDR_P4 = 35.0                                     # P4: fidelidad frente a PyTorch
SDR_COREML = 15.0                                 # ADR-020: frente a Core ML

stage = sys.argv[1] if len(sys.argv) > 1 else "chunk"
D = HERE / "out" / "onnx_check"
D.mkdir(parents=True, exist_ok=True)
log = logging.getLogger("onnx_check")
log.setLevel(logging.INFO)
log.propagate = False
_h = logging.FileHandler(D / "onnx_check.log")
_h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(_h)
sys.excepthook = lambda t, v, tb: (log.error("excepción no capturada", exc_info=(t, v, tb)),
                                   print(f"ERROR {t.__name__}: {v} (ver {D / 'onnx_check.log'})"))
log.info("=== %s", stage)
RES = D / "results.json"
res = json.loads(RES.read_text()) if RES.exists() else {}


def save():
    RES.write_text(json.dumps(res, indent=1, ensure_ascii=False))


def stats(est: np.ndarray, ref: np.ndarray) -> dict:
    e, r = est.astype(np.float64).ravel(), ref.astype(np.float64).ravel()
    d = e - r
    return {"max": float(np.abs(d).max()), "rms": float(np.sqrt(np.mean(d ** 2))),
            "snr_db": round(float(10 * np.log10(np.sum(r ** 2) / max(np.sum(d ** 2), 1e-30))), 2)}


def ort_session():
    """Mismos ajustes que OnnxMaskModel (separador principal): CPU, ORT_ENABLE_ALL, sin arena ni patrón de
    memoria, hilos automáticos (P8, «Hilos de ONNX Runtime»)."""
    import onnxruntime as ort
    got = L.sha256(ONNX)
    if got != ONNX_SHA:
        raise RuntimeError(f"sha256 del ONNX no coincide: {got}")
    so = ort.SessionOptions()
    so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    so.enable_cpu_mem_arena = False
    so.enable_mem_pattern = False
    t0 = time.perf_counter()
    s = ort.InferenceSession(str(ONNX), sess_options=so, providers=["CPUExecutionProvider"])
    log.info("ort %s, sesión en %.1f s; in %s; out %s", ort.__version__, time.perf_counter() - t0,
             [(i.name, i.shape, i.type) for i in s.get_inputs()], [(o.name, o.shape, o.type) for o in s.get_outputs()])
    return s


def coreml_model():
    import coremltools as ct
    pkg = D / "coreml" / "LeadRhythmMelRoformer_fp16.mlpackage"
    if not pkg.exists():
        zipfile.ZipFile(CM_ZIP).extractall(D / "coreml")
    return ct.models.MLModel(str(pkg), compute_units=ct.ComputeUnit.CPU_AND_GPU)


def load_guitar():
    x, sr = M.load_wav(GUITAR)
    assert sr == L.SR and x.shape[0] == 2, (sr, x.shape)
    return x[:, START_S * sr:(START_S + DUR_S) * sr].astype(np.float32), sr


if stage == "chunk":
    import torch
    x, sr = load_guitar()
    spec = L.stft_spec(x[:, :L.CHUNK])
    sess = ort_session()
    y_o = sess.run(["mask"], {"spec": spec})[0]
    model, _ = L.load_model(log)
    core = L.make_core(model)[0]
    with torch.no_grad():
        y_t = core(torch.from_numpy(spec)).numpy()
    r = {"ort_vs_torch_core": stats(y_o, y_t)}
    log.info("máscara ORT vs núcleo torch %s", r["ort_vs_torch_core"])
    if r["ort_vs_torch_core"]["snr_db"] < SNR_SAME_NET:
        res["chunk"] = r | {"veredicto": "descartado (SNR < 60 dB frente a torch)"}
        save()
        print("DESCARTADO: ORT vs torch", r["ort_vs_torch_core"])
        sys.exit(1)
    ml = coreml_model()
    y_c = np.asarray(ml.predict({"spec": spec})["mask"], np.float32).reshape(y_o.shape)
    r["ort_vs_coreml"] = stats(y_o, y_c)
    r["coreml_vs_torch_core"] = stats(y_c, y_t)
    res["chunk"] = r
    save()
    log.info("chunk %s", r)
    print("chunk:", {k: v["snr_db"] for k, v in r.items()}, "dB SNR")

elif stage == "e2e":
    import torch
    x, sr = load_guitar()
    out = {}
    # 1) ONNX Runtime CPU, con tiempos por trozo.
    sess = ort_session()
    warm = L.stft_spec(x[:, :L.CHUNK])
    for _ in range(2):
        sess.run(["mask"], {"spec": warm})
    tchunks = []

    def ort_mask(s):
        t0 = time.perf_counter()
        y = sess.run(["mask"], {"spec": s})[0]
        tchunks.append(time.perf_counter() - t0)
        return y

    t0 = time.perf_counter()
    lead_o = L.demix_np(x, lambda p: L.run_chunk_np(p, ort_mask), num_overlap=OVERLAP)
    wall = time.perf_counter() - t0
    per_min = 60.0 / DUR_S
    out["speed_ort_cpu"] = {"chunks": len(tchunks), "chunk_median_s": round(statistics.median(tchunks), 3),
                            "chunk_min_s": round(min(tchunks), 3), "model_s_per_min": round(sum(tchunks) * per_min, 1),
                            "wall_s_per_min": round(wall * per_min, 1), "threads": "automático (0)",
                            "arena": False, "mem_pattern": False}
    log.info("ORT e2e %s", out["speed_ort_cpu"])
    del sess
    # 2) PyTorch original (MelBandRoformer.forward con su STFT), CPU FP32.
    model, _ = L.load_model(log)

    def torch_chunk(p):
        with torch.no_grad():
            y = model(torch.from_numpy(np.ascontiguousarray(p, np.float32))[None]).numpy()
        return y.reshape(-1, 2, y.shape[-1])[0][:, :p.shape[-1]]

    t0 = time.perf_counter()
    lead_t = L.demix_np(x, torch_chunk, num_overlap=OVERLAP)
    out["speed_torch_cpu_s_per_min"] = round((time.perf_counter() - t0) * per_min, 1)
    rhy_o, rhy_t = x - lead_o, x - lead_t
    out["ort_vs_torch"] = {"lead": stats(lead_o, lead_t) | {"sdr": round(M.sdr(lead_o, lead_t), 2)},
                           "rhythm": stats(rhy_o, rhy_t) | {"sdr": round(M.sdr(rhy_o, rhy_t), 2)}}
    log.info("ORT vs torch %s", out["ort_vs_torch"])
    n = LISTEN_S * sr
    tag = f"T1guitar_{START_S}-{START_S + LISTEN_S}s"
    M.save_wav(D / f"CHECK_b1lr_lead_onnx_{tag}.wav", lead_o[:, :n], sr)
    M.save_wav(D / f"CHECK_b1lr_rhythm_onnx_{tag}.wav", rhy_o[:, :n], sr)
    M.save_wav(D / f"CHECK_b1lr_lead_torch_{tag}.wav", lead_t[:, :n], sr)
    if min(out["ort_vs_torch"]["lead"]["sdr"], out["ort_vs_torch"]["rhythm"]["sdr"]) < SDR_P4:
        res["e2e"] = out | {"veredicto": "descartado (SDR < 35 dB frente a PyTorch)"}
        save()
        print("DESCARTADO: ORT vs torch", out["ort_vs_torch"])
        sys.exit(1)
    del model
    # 3) Core ML de la app (FP16, CPU+GPU).
    ml = coreml_model()
    tc = []

    def cm_mask(s):
        t1 = time.perf_counter()
        y = np.asarray(ml.predict({"spec": s})["mask"], np.float32).reshape(1, 1, 2 * L.F, L.FRAMES, 2)
        tc.append(time.perf_counter() - t1)
        return y

    lead_c = L.demix_np(x, lambda p: L.run_chunk_np(p, cm_mask), num_overlap=OVERLAP)
    out["speed_coreml_model_s_per_min"] = round(sum(tc[1:]) / max(len(tc) - 1, 1) * len(tc) * per_min, 1)
    rhy_c = x - lead_c
    out["ort_vs_coreml"] = {"lead": stats(lead_o, lead_c) | {"sdr": round(M.sdr(lead_o, lead_c), 2)},
                            "rhythm": stats(rhy_o, rhy_c) | {"sdr": round(M.sdr(rhy_o, rhy_c), 2)}}
    out["coreml_vs_torch"] = {"lead": stats(lead_c, lead_t) | {"sdr": round(M.sdr(lead_c, lead_t), 2)},
                              "rhythm": stats(rhy_c, rhy_t) | {"sdr": round(M.sdr(rhy_c, rhy_t), 2)}}
    M.save_wav(D / f"CHECK_b1lr_lead_coreml_{tag}.wav", lead_c[:, :n], sr)
    out["lead_level_db"] = round(float(10 * np.log10(np.mean(lead_t ** 2) + 1e-20)), 1)
    out["input_level_db"] = round(float(10 * np.log10(np.mean(x ** 2) + 1e-20)), 1)
    res["e2e"] = out
    save()
    log.info("e2e %s", out)
    print("SDR lead/rhythm ORT-torch", out["ort_vs_torch"]["lead"]["sdr"], out["ort_vs_torch"]["rhythm"]["sdr"],
          "| ORT-CoreML", out["ort_vs_coreml"]["lead"]["sdr"], out["ort_vs_coreml"]["rhythm"]["sdr"],
          "| ORT CPU s/min", out["speed_ort_cpu"]["model_s_per_min"], out["speed_ort_cpu"]["wall_s_per_min"])
