"""Prepara un modelo para ort-smoke (Windows): ONNX, entrada fija, referencias y tiempos en el Mac.

Uso: prepare.py <modelo> <etapa>
  bs_roformer  ort | torch | coreml | e2e
Escribe out/<modelo>/ (model.onnx, *.bin, manifest.txt, mac.json) y out/<modelo>.log.
Por consola solo un resumen. Lanzar lo pesado bajo Probes/P4-modelos/common/guard.py."""
import argparse
import gc
import json
import logging
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
REPO = HERE.parents[2]
P4 = REPO / "Probes" / "P4-modelos"
TESTAUDIO = REPO / "Probes" / "testaudio" / "out"
sys.path.insert(0, str(P4 / "common"))
import metrics as M  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("model")
ap.add_argument("stage")
args = ap.parse_args()

D = OUT / args.model
D.mkdir(parents=True, exist_ok=True)
log = logging.getLogger("prep")
log.setLevel(logging.INFO)
log.propagate = False
_h = logging.FileHandler(OUT / f"{args.model}.log")
_h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(_h)
sys.excepthook = lambda t, v, tb: (log.error("excepción no capturada", exc_info=(t, v, tb)),
                                   print(f"ERROR {t.__name__}: {v} (ver out/{args.model}.log)"))
log.info("=== %s %s", args.model, args.stage)

STATE = D / "mac.json"
state = json.loads(STATE.read_text()) if STATE.exists() else {"manifest": {}, "mac": {}}


def save_state():
    STATE.write_text(json.dumps(state, indent=1))
    m = state["manifest"]
    if "model" not in m:            # etapa sin manifiesto (p. ej. export): solo mac.json
        return
    lines = [f"model {m['model']}"] + m.get("in", []) + m.get("out", []) + m.get("ref2", [])
    if "runs_per_minute" in m:
        lines.append(f"runs_per_minute {m['runs_per_minute']}")
    (D / "manifest.txt").write_text("\n".join(lines) + "\n")


def wbin(name: str, arr) -> str:
    a = np.ascontiguousarray(arr, dtype=np.float32)
    a.tofile(D / name)
    return ",".join(str(s) for s in a.shape)


def timed(fn, runs: int = 3):
    t0 = time.perf_counter()
    y = fn()
    first = time.perf_counter() - t0
    ts = []
    for _ in range(runs):
        t0 = time.perf_counter()
        y = fn()
        ts.append(time.perf_counter() - t0)
    return y, first, float(np.median(ts))


def link_model(src: Path):
    dst = D / "model.onnx"
    if dst.is_symlink() or dst.exists():
        dst.unlink()
    dst.symlink_to(src)
    return src.stat().st_size


def ort_cpu(path: Path):
    import onnxruntime as ort
    so = ort.SessionOptions()
    so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    sess = ort.InferenceSession(str(path), sess_options=so, providers=["CPUExecutionProvider"])
    log.info("ort %s; in %s; out %s", ort.__version__, [(i.name, i.shape) for i in sess.get_inputs()],
             [(o.name, o.shape) for o in sess.get_outputs()])
    return sess


# --------------------------------------------------------------------------- BS-RoFormer SW (separación)
def bs_roformer():
    sys.path.insert(0, str(P4 / "bs_roformer_sw"))
    import sw_common as C
    start = 60 * C.SR                                           # T1, minuto 1
    st = args.stage
    if st == "ort":
        mix, sr = M.load_wav(TESTAUDIO / "T1" / "mix.wav")
        spec = C.stft_np(mix[:, start:start + C.PUB_CHUNK])     # (2, 1025, 345, 2)
        sess = ort_cpu(C.ensure_onnx_pub(log))
        feed = {"spec_real": spec[None, ..., 0], "spec_imag": spec[None, ..., 1]}
        (re, im), first, med = timed(lambda: sess.run(["out_spec_real", "out_spec_imag"], feed))
        m = state["manifest"]
        m["model"] = "model.onnx"
        m["in"] = [f"in spec_real in_real.bin {wbin('in_real.bin', feed['spec_real'])}",
                   f"in spec_imag in_imag.bin {wbin('in_imag.bin', feed['spec_imag'])}"]
        wbin("ref_real.bin", re)
        wbin("ref_imag.bin", im)
        m["out"] = ["out out_spec_real ref_real.bin", "out out_spec_imag ref_imag.bin"]
        m["runs_per_minute"] = 60 * C.SR / (C.PUB_CHUNK // C.NUM_OVERLAP)
        state["mac"]["ort_cpu"] = {"first_s": first, "median_s": med, "per_min_s": med * m["runs_per_minute"],
                                   "size_mb": link_model(C.PUB) / 1e6, "out_shape": list(re.shape)}
        np.save(D / "spec.npy", spec)
    elif st == "torch":
        import torch
        spec = np.load(D / "spec.npy")
        model, _ = C.load_model(log)
        core = C.make_core(model, spec.shape[2])
        with torch.no_grad():
            y, first, med = timed(lambda: core(torch.from_numpy(spec)).numpy(), runs=1)   # (12, F, T, 2)
        shape = state["mac"]["ort_cpu"]["out_shape"]
        re, im = y[..., 0].reshape(shape), y[..., 1].reshape(shape)
        ref_re = np.fromfile(D / "ref_real.bin", np.float32).reshape(shape)
        log.info("torch vs ort mac: max %.3g", float(np.abs(ref_re - re).max()))
        wbin("torch_real.bin", re)
        wbin("torch_imag.bin", im)
        state["manifest"]["ref2"] = ["ref2 out_spec_real torch_real.bin", "ref2 out_spec_imag torch_imag.bin"]
        state["mac"]["torch_cpu"] = {"first_s": first, "median_s": med,
                                     "ort_vs_torch_max": float(np.abs(ref_re - re).max()),
                                     "ort_vs_torch_snr_db": float(10 * np.log10(np.sum(re.astype(np.float64) ** 2)
                                                                  / np.sum((ref_re - re).astype(np.float64) ** 2)))}
    elif st == "coreml":
        import coremltools as ct
        mix, sr = M.load_wav(TESTAUDIO / "T1" / "mix.wav")
        spec = C.stft_np(mix[:, start:start + C.CHUNK])
        x = np.ascontiguousarray(spec.transpose(1, 0, 2, 3).reshape(1, 2 * C.N_FREQ, -1, 2))
        mdl = ct.models.MLModel(str(C.OUT / "coreml_pub" / "BSRoformerSW.mlpackage"),
                                compute_units=ct.ComputeUnit.CPU_AND_GPU)
        _, first, med = timed(lambda: mdl.predict({"spec": x}))
        rpm = 60 * C.SR / (C.CHUNK // C.NUM_OVERLAP)
        state["mac"]["coreml_gridshift_cpu_gpu"] = {"chunk_frames": int(x.shape[2]), "first_s": first,
                                                    "median_s": med, "per_min_s": med * rpm}
    elif st == "e2e":
        # Tema T1 entero ya separado en P4 con las dos vías: ONNX publicado (CPU) y Core ML de la app.
        a, b = C.OUT / "conv" / "onnxpub_cpu" / "T1", C.OUT / "conv" / "coremlpub_cpu_gpu" / "T1"
        res = {}
        for s in C.STEMS:
            x, sr = M.load_wav(a / f"{s}.wav")
            y, _ = M.load_wav(b / f"{s}.wav")
            res[s] = round(M.sdr(x, y), 2)
            if s == "guitar":
                t0 = 60 * sr
                M.save_wav(D / "T1_guitar_60-85s_onnx.wav", x[:, t0:t0 + 25 * sr], sr)
                M.save_wav(D / "T1_guitar_60-85s_coreml.wav", y[:, t0:t0 + 25 * sr], sr)
        state["mac"]["e2e_sdr_onnx_vs_coreml_db"] = res
    else:
        raise SystemExit(f"etapa desconocida {st}")


# --------------------------------------------------------------------------- comunes a los modelos pequeños
def fn(name: str) -> str:
    return name.replace(":", "_").replace("/", "_")


def stats(a: np.ndarray, b: np.ndarray, mode: str | None) -> dict:
    a64, b64 = a.astype(np.float64).ravel(), b.astype(np.float64).ravel()
    d = np.abs(a64 - b64)
    r = {"max": float(d.max()), "mean": float(d.mean()),
         "snr_db": float(10 * np.log10(np.sum(a64 ** 2) / max(np.sum(d ** 2), 1e-30)))}
    if mode == "argmax":
        r["argmax_igual"] = f"{int((a.argmax(-1) == b.argmax(-1)).sum())}/{a.size // a.shape[-1]}"
    elif mode and mode.startswith("thr="):
        t = float(mode[4:])
        r["umbral_igual"] = f"{int(((a > t) == (b > t)).sum())}/{a.size}"
    return r


def export_onnx(module, example: tuple, in_names, out_names, opset: int = 17) -> Path:
    import torch
    dst = D / "model.onnx"
    if dst.is_symlink():
        dst.unlink()
    t0 = time.perf_counter()
    with torch.no_grad():
        torch.onnx.export(module, example, str(dst), input_names=in_names, output_names=out_names,
                          opset_version=opset, do_constant_folding=True, dynamo=False)
    import onnx
    mp = onnx.load(str(dst), load_external_data=False)
    log.info("onnx exportado %s en %.1f s, opset %s, %.1f MB, nodos %d", dst.name, time.perf_counter() - t0,
             [o.version for o in mp.opset_import], dst.stat().st_size / 1e6, len(mp.graph.node))
    return dst


def standard(onnx_path: Path, feed: dict, out_names: list, rpm: float, coreml=None, modes=None, origin=""):
    """ORT CPU en el Mac (referencia 'out') y, si hay, Core ML de la app (referencia 'ref2')."""
    import onnx
    modes = modes or {}
    sess = ort_cpu(onnx_path)
    outs, first, med = timed(lambda: sess.run(out_names, feed))
    m = state["manifest"]
    m["model"] = "model.onnx"
    m["in"] = [f"in {k} in_{fn(k)}.bin {wbin(f'in_{fn(k)}.bin', v)}" for k, v in feed.items()]
    m["out"], m["ref2"] = [], []
    for k, y in zip(out_names, outs):
        wbin(f"ref_{fn(k)}.bin", y)
        m["out"].append(f"out {k} ref_{fn(k)}.bin {modes.get(k, '')}".strip())
    m["runs_per_minute"] = rpm
    mp = onnx.load(str(onnx_path), load_external_data=False)
    state["mac"]["ort_cpu"] = {"first_s": first, "median_s": med, "per_min_s": med * rpm,
                               "size_mb": onnx_path.stat().st_size / 1e6, "origin": origin,
                               "opset": [o.version for o in mp.opset_import if o.domain in ("", "ai.onnx")],
                               "shapes": {k: list(y.shape) for k, y in zip(out_names, outs)}}
    if coreml is not None:
        ys, cf, cm = timed(coreml)
        diffs = {}
        for k, y0 in zip(out_names, outs):
            y = np.asarray(ys[k], np.float32).reshape(y0.shape)
            wbin(f"coreml_{fn(k)}.bin", y)
            m["ref2"].append(f"ref2 {k} coreml_{fn(k)}.bin {modes.get(k, '')}".strip())
            diffs[k] = stats(y, y0, modes.get(k))
        state["mac"]["coreml"] = {"first_s": cf, "median_s": cm, "per_min_s": cm * rpm, "ort_mac_vs_coreml": diffs}
    return outs


def load_mix(sr_out: int | None = None, mono: bool = False):
    x, sr = M.load_wav(TESTAUDIO / "T1" / "mix.wav")
    if mono:
        x = x.mean(0)
    if sr_out and sr_out != sr:
        import soxr
        x = soxr.resample(x.T if x.ndim == 2 else x, sr, sr_out).astype(np.float32)
        x = x.T if x.ndim == 2 else x
        sr = sr_out
    return x, sr


# --------------------------------------------------------------------------- lead/rhythm (Mel-Band RoFormer)
def lead_rhythm():
    import urllib.request
    sys.path.insert(0, str(P4 / "bs_roformer_sw"))
    sys.path.insert(0, str(P4 / "lead_rhythm"))
    import sw_common as C
    import lr_common as L
    L.MSST = C.MSST                                              # mismo commit 1f700c38
    base = "https://huggingface.co/RandomFilteredStuff/RVC_V2_Stuff/resolve/" + L.HF_COMMIT + "/"
    start = 60 * L.SR
    if args.stage == "export":
        import torch
        L.W.mkdir(parents=True, exist_ok=True)
        for name in (L.CFG, L.CKPT):
            if not (L.W / name).exists():
                log.info("descargando %s", name)
                urllib.request.urlretrieve(base + name, L.W / name)
        model, _ = L.load_model(log)
        core = L.make_core(model)[0]
        mix, _ = load_mix()
        spec = L.stft_spec(mix[:, start:start + L.CHUNK])                  # (1, 2050, 301, 2)
        with torch.no_grad():
            y, first, med = timed(lambda: core(torch.from_numpy(spec)).numpy(), runs=1)
        state["mac"]["torch_cpu"] = {"first_s": first, "median_s": med}
        np.save(D / "spec.npy", spec)
        np.save(D / "torch_mask.npy", y)
        export_onnx(core, (torch.from_numpy(spec),), ["spec"], ["mask"])
    elif args.stage == "run":
        import zipfile
        import coremltools as ct
        spec = np.load(D / "spec.npy")
        pkg = D / "coreml" / "LeadRhythmMelRoformer_fp16.mlpackage"
        if not pkg.exists():
            zipfile.ZipFile(REPO / "App/Resources/Models/LeadRhythmMelRoformer_fp16.mlpackage.zip").extractall(D / "coreml")
        ml = ct.models.MLModel(str(pkg), compute_units=ct.ComputeUnit.CPU_AND_GPU)
        (y,) = standard(D / "model.onnx", {"spec": spec}, ["mask"], 60 * L.SR / L.CHUNK,
                        coreml=lambda: {"mask": ml.predict({"spec": spec})["mask"]},
                        origin="export propio (torch 2.7, TorchScript) de lr_common.make_core")
        state["mac"]["ort_vs_torch"] = stats(np.load(D / "torch_mask.npy"), y, None)
    elif args.stage == "e2e":
        import coremltools as ct
        import onnxruntime as ort
        ml = ct.models.MLModel(str(D / "coreml" / "LeadRhythmMelRoformer_fp16.mlpackage"),
                               compute_units=ct.ComputeUnit.CPU_AND_GPU)
        sess = ort.InferenceSession(str(D / "model.onnx"), providers=["CPUExecutionProvider"])
        mix, sr = load_mix()
        seg = mix[:, start:start + 25 * sr]
        a = L.demix_np(seg, lambda p: L.run_chunk_np(p, lambda s: sess.run(["mask"], {"spec": s})[0]))
        b = L.demix_np(seg, lambda p: L.run_chunk_np(p, lambda s: ml.predict({"spec": s})["mask"]))
        M.save_wav(D / "T1_lead_60-85s_onnx.wav", a, sr)
        M.save_wav(D / "T1_lead_60-85s_coreml.wav", b, sr)
        state["mac"]["e2e_sdr_onnx_vs_coreml_db"] = round(M.sdr(a, b), 2)


# --------------------------------------------------------------------------- BTC (acordes)
def btc():
    import torch
    import coremltools as ct
    sys.path.insert(0, str(P4 / "btc"))
    import btc_common as B
    B.ensure_assets(log)
    model, mean, std = B.load_torch_model()
    B.patch_masks_fp16_safe(model)

    class Wrap(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.enc, self.proj = m.self_attn_layers, m.output_layer.output_projection

        def forward(self, x):
            return self.proj(self.enc(x)[0])

    xs, sr = B.load_input("T1", "mix")
    wav = B.to_mono_22k([x[:, 60 * sr:121 * sr] for x in xs], sr)
    x = B.normalize_windows(B.cqt_features(wav), mean, std)[0][:6]          # (6, 108, 144) = 60 s
    path = export_onnx(Wrap(model).eval(), (torch.from_numpy(x),), ["cqt"], ["logits"])
    ml = ct.models.MLModel(str(B.MLPACKAGE).format(prec="fp16"), compute_units=ct.ComputeUnit.CPU_AND_NE)
    standard(path, {"cqt": x}, ["logits"], 1.0,
             coreml=lambda: {"logits": np.concatenate([ml.predict({"cqt": x[i:i + 1]})["logits"] for i in range(6)])},
             modes={"logits": "argmax"}, origin="export propio (torch 2.7) de self_attn_layers+output_projection")


# --------------------------------------------------------------------------- Beat This! (pulso)
def beat_this():
    import urllib.request
    import coremltools as ct
    sys.path.insert(0, str(P4 / "beat_this"))
    import bt_common as BT
    BT.ensure_repo(log)
    src = BT.ONNX_DIR / "beat_this.onnx"
    if not src.exists():
        log.info("descargando beat_this.onnx (musetric)")
        urllib.request.urlretrieve(f"https://huggingface.co/{BT.ONNX_REPO}/resolve/{BT.ONNX_SHA}/beat_this.onnx", src)
    if BT.sha256(src) != "1337dc6c21257ed6b803418efc320df42b5d8eb296ef16648ef60457cd4b9e55":
        raise RuntimeError("sha256 de beat_this.onnx distinto")
    link_model(src)
    sig, sr = BT.load_audio("T1")
    spect = BT.log_mel(BT.to_mono_22k(sig, sr)).numpy()
    x = np.ascontiguousarray(spect[60 * BT.FPS:60 * BT.FPS + BT.CHUNK][None], np.float32)   # (1, 1500, 128)
    ml = ct.models.CompiledMLModel(str(BT.COMM_MODEL), compute_units=ct.ComputeUnit.CPU_AND_GPU)
    standard(D / "model.onnx", {"spect": x}, ["beat", "downbeat"], 60 * BT.FPS / (BT.CHUNK - 2 * BT.BORDER),
             coreml=lambda: ml.predict({"spect": x}), modes={"beat": "thr=0", "downbeat": "thr=0"},
             origin=f"publicado {BT.ONNX_REPO}@{BT.ONNX_SHA[:8]} (final0, MIT)")


# --------------------------------------------------------------------------- Basic Pitch
def basic_pitch():
    import coremltools as ct
    import basic_pitch as bp
    src = Path(bp.__file__).parent / "saved_models" / "icassp_2022"
    link_model(src / "nmp.onnx")
    mono, sr = load_mix(22050, mono=True)
    x = np.ascontiguousarray(mono[60 * sr:60 * sr + 43844].reshape(1, 43844, 1), np.float32)
    ml = ct.models.MLModel(str(src / "nmp.mlpackage"), compute_units=ct.ComputeUnit.CPU_ONLY)

    def cm():
        r = ml.predict({"input_2": x})
        return {"StatefulPartitionedCall:1": r["Identity_1"], "StatefulPartitionedCall:2": r["Identity_2"],
                "StatefulPartitionedCall:0": r["Identity"]}
    standard(D / "model.onnx", {"serving_default_input_2:0": x},
             ["StatefulPartitionedCall:1", "StatefulPartitionedCall:2", "StatefulPartitionedCall:0"],
             60 * 22050 / 36164, coreml=cm,
             modes={"StatefulPartitionedCall:1": "thr=0.3", "StatefulPartitionedCall:2": "thr=0.5"},
             origin=f"publicado en el paquete pip basic-pitch {getattr(bp, '__version__', '0.4.0')} (Apache-2.0)")


# --------------------------------------------------------------------------- ADTOF (batería)
def adtof():
    import torch
    import coremltools as ct
    sys.path.insert(0, str(P4 / "adtof"))
    import ad_common as A
    model = A.load_torch()
    feats = A.features(P4 / "bs_roformer_sw/out/conv/coremlpub_cpu_gpu/T1/drums.wav")   # (T, 84, 1)
    x = np.ascontiguousarray(feats[6000:9000][None], np.float32)                     # 30 s a 100 fps
    path = export_onnx(model, (torch.from_numpy(x),), ["spec"], ["act"])
    ml = ct.models.MLModel(str(A.OUT / "conv" / "adtof_fp32n.mlpackage"), compute_units=ct.ComputeUnit.CPU_ONLY)
    sp = ml.get_spec().description
    i_name, o_name = sp.input[0].name, sp.output[0].name
    log.info("coreml adtof: %s -> %s", i_name, o_name)
    standard(path, {"spec": x}, ["act"], 2.0, coreml=lambda: {"act": ml.predict({i_name: x})[o_name]},
             modes={"act": "thr=0.22"}, origin="export propio (torch 2.7) del puerto xavriley/ADTOF-pytorch")


{"bs_roformer": bs_roformer, "lead_rhythm": lead_rhythm, "btc": btc, "beat_this": beat_this,
 "basic_pitch": basic_pitch, "adtof": adtof}[args.model]()
save_state()
gc.collect()
print(f"{args.model} {args.stage}: " + json.dumps(state["mac"])[:900])
