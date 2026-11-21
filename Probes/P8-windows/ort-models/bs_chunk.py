"""BS-RoFormer SW: ONNX con trozo intermedio (T entre 345 y 1151) para ORT en Windows.

Uso (siempre bajo Probes/P4-modelos/common/guard.py, de uno en uno):
  bs_chunk.py export <T> [--via dynamo|ts]   núcleo de sw_common.make_core(T) con la interfaz del ONNX
                                             publicado (spec_real/spec_imag -> out_spec_real/out_spec_imag)
  bs_chunk.py check <T>                      reempaqueta en un solo fichero y compara ORT CPU con torch
  bs_chunk.py e2e <T>                        T1 entero con ORT CPU (trozo (T-1)*512, num_overlap 2):
                                             s/min, SDR frente a stems reales y frente a la app (Core ML)
  bs_chunk.py smoke <T>                      entradas/referencias fijas para ort-smoke (T1, minuto 1)
Escribe out/bs_roformer_T<T>/ y out/bs_roformer_T<T>.log; por consola un resumen."""
import argparse
import json
import logging
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
P4 = REPO / "Probes" / "P4-modelos"
sys.path.insert(0, str(P4 / "common"))
sys.path.insert(0, str(P4 / "bs_roformer_sw"))
import metrics as M  # noqa: E402
import sw_common as C  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("stage", choices=["export", "check", "e2e", "smoke"])
ap.add_argument("frames", type=int)
ap.add_argument("--via", default="dynamo", choices=["dynamo", "ts"])
args = ap.parse_args()
T = args.frames
CHUNK = (T - 1) * C.HOP
D = HERE / "out" / f"bs_roformer_T{T}"
D.mkdir(parents=True, exist_ok=True)
log = logging.getLogger("bsT")
log.setLevel(logging.INFO)
log.propagate = False
_h = logging.FileHandler(HERE / "out" / f"bs_roformer_T{T}.log")
_h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(_h)
sys.excepthook = lambda t, v, tb: (log.error("excepción no capturada", exc_info=(t, v, tb)),
                                   print(f"ERROR {t.__name__}: {str(v)[:300]} (ver out/bs_roformer_T{T}.log)"))
log.info("=== %s T=%d chunk=%d via=%s", args.stage, T, CHUNK, args.via)
STATE = D / "mac.json"
state = json.loads(STATE.read_text()) if STATE.exists() else {}
ONNX = D / "model.onnx"


def spec_t1_min1():
    mix, _ = M.load_wav(C.TESTAUDIO / "T1" / "mix.wav")
    return C.stft_np(mix[:, 60 * C.SR:60 * C.SR + CHUNK])          # (2, 1025, T, 2)


def session():
    """ORT CPU sin arena ni patrón de memoria: los tensores de atención (bandas*cabezas*T*T) se liberan al
    momento en vez de quedarse en la arena; es lo que haría la app en Windows con 8 GB."""
    import onnxruntime as ort
    so = ort.SessionOptions()
    so.enable_cpu_mem_arena = False
    so.enable_mem_pattern = False
    return ort.InferenceSession(str(ONNX), sess_options=so, providers=["CPUExecutionProvider"])


if args.stage == "export":
    import torch
    from torch import nn
    model, _ = C.load_model(log)
    core = C.make_core(model, T)

    class Pub(nn.Module):
        """Interfaz del ONNX publicado (elicwhite): (1,2,F,T) re/im -> (1,6,2,F,T) re/im."""
        def __init__(self, c):
            super().__init__()
            self.c = c

        def forward(self, spec_real, spec_imag):
            y = self.c(torch.stack([spec_real[0], spec_imag[0]], dim=-1))     # (12, F, T, 2)
            f, t = y.shape[1], y.shape[2]
            return y[..., 0].reshape(1, 6, 2, f, t), y[..., 1].reshape(1, 6, 2, f, t)

    wrap = Pub(core).eval()
    spec = spec_t1_min1()
    ex = (torch.from_numpy(np.ascontiguousarray(spec[None, ..., 0])),
          torch.from_numpy(np.ascontiguousarray(spec[None, ..., 1])))
    with torch.no_grad():
        t0 = time.perf_counter()
        ref_re, ref_im = (a.numpy() for a in wrap(*ex))
        log.info("torch CPU un trozo: %.1f s", time.perf_counter() - t0)
    np.save(D / "torch_re.npy", ref_re)
    np.save(D / "torch_im.npy", ref_im)
    t0 = time.perf_counter()
    with torch.no_grad():
        if args.via == "dynamo":
            prog = torch.onnx.export(wrap, ex, dynamo=True, input_names=["spec_real", "spec_imag"],
                                     output_names=["out_spec_real", "out_spec_imag"], optimize=True)
            log.info("dynamo: programa exportado en %.1f s; huella %.2f GB (pico %.2f)", time.perf_counter() - t0,
                     *(v / 1e9 for v in M.phys_footprint()))
            del model, core, wrap
            import gc
            gc.collect()
            log.info("tras liberar torch: huella %.2f GB", M.phys_footprint()[0] / 1e9)
            # external_data: los pesos se escriben a model.onnx.data en streaming (con un único fichero, el
            # intento 1 pasó de 10 GB al serializar)
            prog.save(str(ONNX), external_data=True)
            log.info("guardado: huella %.2f GB (pico %.2f)", *(v / 1e9 for v in M.phys_footprint()))
            del prog
            gc.collect()
        else:
            traced = torch.jit.trace(wrap, ex, check_trace=False)
            del model
            torch.onnx.export(traced, ex, str(ONNX), input_names=["spec_real", "spec_imag"],
                              output_names=["out_spec_real", "out_spec_imag"], opset_version=17,
                              dynamo=False, do_constant_folding=False)
    state["export"] = {"via": args.via, "export_s": time.perf_counter() - t0}

if args.stage in ("export", "check"):
    import gc
    import onnx
    if (D / "model.onnx.data").exists():
        # Un solo fichero (< 2 GB): ORT no infiere formas de tensores pequeños guardados fuera (Split con sus
        # tamaños en model.onnx.data -> ShapeInferenceError al cargar).
        t0 = time.perf_counter()
        mp = onnx.load(str(ONNX))
        onnx.save(mp, str(ONNX))
        del mp
        gc.collect()
        (D / "model.onnx.data").unlink()
        log.info("reempaquetado en un fichero en %.1f s; huella %.2f GB", time.perf_counter() - t0,
                 M.phys_footprint()[0] / 1e9)
    mp = onnx.load(str(ONNX), load_external_data=False)
    ops = {}
    for n in mp.graph.node:
        ops[n.op_type] = ops.get(n.op_type, 0) + 1
    size = ONNX.stat().st_size
    log.info("onnx %.1f MB, opset %s, nodos %d, ops %s", size / 1e6,
             [(o.domain, o.version) for o in mp.opset_import], len(mp.graph.node), ops)
    state.setdefault("export", {}).update({"size_mb": size / 1e6, "nodes": len(mp.graph.node), "ops": ops,
                                           "opset": [o.version for o in mp.opset_import if o.domain in ("", "ai.onnx")]})
    del mp
    sess = session()
    log.info("sesión creada: huella %.2f GB (pico %.2f)", *(v / 1e9 for v in M.phys_footprint()))
    spec = spec_t1_min1()
    feed = {"spec_real": np.ascontiguousarray(spec[None, ..., 0]), "spec_imag": np.ascontiguousarray(spec[None, ..., 1])}
    ref_re, ref_im = np.load(D / "torch_re.npy"), np.load(D / "torch_im.npy")
    t0 = time.perf_counter()
    re, im = sess.run(["out_spec_real", "out_spec_imag"], feed)
    first = time.perf_counter() - t0
    t0 = time.perf_counter()
    sess.run(["out_spec_real", "out_spec_imag"], feed)
    med = time.perf_counter() - t0
    a = np.concatenate([ref_re.ravel(), ref_im.ravel()]).astype(np.float64)
    b = np.concatenate([re.ravel(), im.ravel()]).astype(np.float64)
    snr = float(10 * np.log10(np.sum(a ** 2) / np.sum((a - b) ** 2)))
    state["ort_vs_torch"] = {"max": float(np.abs(a - b).max()), "mean": float(np.abs(a - b).mean()), "snr_db": snr}
    state["ort_cpu_chunk"] = {"first_s": first, "second_s": med, "per_min_s": med * 60 * C.SR / (CHUNK // 2)}
    log.info("ort CPU trozo %.1f / %.1f s; vs torch %s", first, med, state["ort_vs_torch"])

elif args.stage == "e2e":
    sess = session()

    def run_chunk(part):
        s = C.stft_np(part)
        re, im = sess.run(["out_spec_real", "out_spec_imag"],
                          {"spec_real": np.ascontiguousarray(s[None, ..., 0]),
                           "spec_imag": np.ascontiguousarray(s[None, ..., 1])})
        y = np.stack([re[0].reshape(12, C.N_FREQ, T), im[0].reshape(12, C.N_FREQ, T)], axis=-1)
        return C.istft_np(y, CHUNK).reshape(len(C.STEMS), 2, -1)

    mix, sr = M.load_wav(C.TESTAUDIO / "T1" / "mix.wav")
    dur_min = mix.shape[-1] / sr / 60
    t0 = time.perf_counter()
    est = C.demix_np(mix, run_chunk, chunk=CHUNK)
    dt = time.perf_counter() - t0
    out = D / "T1"
    for k, s in enumerate(C.STEMS):
        M.save_wav(out / f"{s}.wav", est[k], sr)
    del est
    q = M.quality_table(out, C.TESTAUDIO / "T1" / "stems", C.TESTAUDIO / "T1" / "mix.wav", C.STEMS)
    app = C.OUT / "conv" / "coremlpub_cpu_gpu" / "T1"
    vs_app = {}
    for s in C.STEMS:
        x, _ = M.load_wav(out / f"{s}.wav")
        y, _ = M.load_wav(app / f"{s}.wav")
        vs_app[s] = round(M.sdr(x, y), 2)
        if s == "guitar":
            M.save_wav(D / f"T1_guitar_60-85s_onnxT{T}.wav", x[:, 60 * sr:85 * sr], sr)
    state["e2e"] = {"sec": dt, "sec_per_min": dt / dur_min,
                    "sdr_real": {s: round(v.get("sdr", float("nan")), 2) for s, v in q.items()},
                    "sdr_vs_app": vs_app}
    log.info("e2e %s", state["e2e"])

else:   # smoke
    import onnxruntime as ort
    spec = spec_t1_min1()
    feed = {"spec_real": np.ascontiguousarray(spec[None, ..., 0], np.float32),
            "spec_imag": np.ascontiguousarray(spec[None, ..., 1], np.float32)}
    sess = ort.InferenceSession(str(ONNX), providers=["CPUExecutionProvider"])
    re, im = sess.run(["out_spec_real", "out_spec_imag"], feed)
    for n, a in (("in_real.bin", feed["spec_real"]), ("in_imag.bin", feed["spec_imag"]),
                 ("ref_real.bin", re), ("ref_imag.bin", im)):
        np.ascontiguousarray(a, np.float32).tofile(D / n)
    np.load(D / "torch_re.npy").astype(np.float32).tofile(D / "torch_real.bin")
    np.load(D / "torch_im.npy").astype(np.float32).tofile(D / "torch_imag.bin")
    sh = ",".join(map(str, feed["spec_real"].shape))
    (D / "manifest.txt").write_text(
        f"model model.onnx\nin spec_real in_real.bin {sh}\nin spec_imag in_imag.bin {sh}\n"
        "out out_spec_real ref_real.bin\nout out_spec_imag ref_imag.bin\n"
        "ref2 out_spec_real torch_real.bin\nref2 out_spec_imag torch_imag.bin\n"
        f"runs_per_minute {60 * C.SR / (CHUNK // 2)}\n")
    state["smoke"] = {"in_shape": list(feed["spec_real"].shape), "out_shape": list(re.shape)}

STATE.write_text(json.dumps(state, indent=1))
print(f"T={T} {args.stage}: " + json.dumps(state)[:700])
