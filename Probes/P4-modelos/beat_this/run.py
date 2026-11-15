"""Un tema por una vía (un proceso por tema, lanzado bajo el vigilante por run_all.py):
    Tools/py/.venv/bin/python Probes/P4-modelos/beat_this/run.py --tema T1 --via torch
Vías: torch (referencia, CPU FP32) · coreml_comm (supracut, FP32, CPU+GPU) · coreml_fp16 (conversión propia,
CPU+GPU) · coreml_fp16_ane (propia, CPU+ANE, trozo fijo de 1500) · onnx_coreml / onnx_cpu (musetric, ORT).
Escribe out/beats/<vía>/T*.{beats,downbeats}.txt, out/logits/<vía>_T*.npz y out/runs/<vía>_T*.json."""
import argparse
import time

import numpy as np

import bt_common as C

ap = argparse.ArgumentParser()
ap.add_argument("--tema", required=True, choices=C.TEMAS)
ap.add_argument("--via", required=True)
a = ap.parse_args()
log = C.setup_log("run")
C.ensure_repo(log)


def make_predictor(via: str):
    """Devuelve (predict_chunk, info). predict_chunk(np (1,1500,128) f32) -> (beat, downbeat) logits."""
    if via == "torch":
        import torch
        m = C.load_torch_model()

        def f(x):
            with torch.inference_mode():
                p = m(torch.from_numpy(x))
            return p["beat"][0].numpy(), p["downbeat"][0].numpy()
        return f, {"unit": "CPU", "prec": "fp32"}
    if via.startswith("coreml"):
        import coremltools as ct
        if via == "coreml_comm":
            C.ensure_comm(log)
            mdl = ct.models.CompiledMLModel(str(C.COMM_MODEL), compute_units=ct.ComputeUnit.CPU_AND_GPU)
            info = {"unit": "CPU+GPU", "prec": "fp32"}
        else:
            ane = via.endswith("_ane")
            path = C.OUT / "coreml" / "BeatThis_final0_fp16.mlpackage"
            cu = ct.ComputeUnit.CPU_AND_NE if ane else ct.ComputeUnit.CPU_AND_GPU
            mdl = ct.models.MLModel(str(path), compute_units=cu)
            info = {"unit": "CPU+ANE" if ane else "CPU+GPU", "prec": "fp16"}

        def f(x):
            o = mdl.predict({"spect": x})
            return o["beat"], o["downbeat"]
        return f, info
    if via.startswith("onnx"):
        import onnxruntime as ort
        prov = ["CoreMLExecutionProvider", "CPUExecutionProvider"] if via == "onnx_coreml" else ["CPUExecutionProvider"]
        s = ort.InferenceSession(str(C.ONNX_DIR / "beat_this.onnx"), providers=prov)
        names = [o.name for o in s.get_outputs()]

        def f(x):
            o = dict(zip(names, s.run(None, {"spect": x})))
            return o["beat"], o["downbeat"]
        return f, {"unit": "+".join(p.replace("ExecutionProvider", "") for p in s.get_providers()), "prec": "fp32"}
    raise SystemExit(f"vía desconocida {via}")


t = time.perf_counter()
sig, sr = C.load_audio(a.tema)
t_audio = time.perf_counter() - t
t = time.perf_counter()
predict, info = make_predictor(a.via)
predict(np.zeros((1, C.CHUNK, C.N_MELS), np.float32))  # calentamiento (compilación) dentro de la carga
t_load = time.perf_counter() - t

t0 = time.perf_counter()
mono = C.to_mono_22k(sig, sr)
spect = C.log_mel(mono)
t1 = time.perf_counter()
beat_l, down_l, n_chunks = C.predict_frames(spect, predict)
t2 = time.perf_counter()
beats, downs = C.postprocess(beat_l, down_l)
t3 = time.perf_counter()

C.save_times(C.OUT / "beats" / a.via / f"{a.tema}.beats.txt", beats)
C.save_times(C.OUT / "beats" / a.via / f"{a.tema}.downbeats.txt", downs)
(C.OUT / "logits").mkdir(parents=True, exist_ok=True)
np.savez_compressed(C.OUT / "logits" / f"{a.via}_{a.tema}.npz", beat=beat_l, downbeat=down_l)

res = {"via": a.via, "tema": a.tema, **info, "frames": int(spect.shape[0]), "chunks": n_chunks,
       "audio_s": round(len(mono) / C.SR, 2), "load_audio_s": round(t_audio, 3), "load_model_s": round(t_load, 3),
       "pre_s": round(t1 - t0, 3), "inf_s": round(t2 - t1, 3), "post_s": round(t3 - t2, 3),
       "total_s": round(t3 - t0, 3), "n_beats": len(beats), "n_downbeats": len(downs),
       "bpm": round(C.tempo(beats), 2)}
ref = C.OUT / "logits" / f"torch_{a.tema}.npz"
if a.via != "torch" and ref.exists():
    r = np.load(ref)
    d = np.concatenate([np.abs(beat_l - r["beat"]), np.abs(down_l - r["downbeat"])])
    res["logit_maxdiff"], res["logit_meandiff"] = float(d.max()), float(d.mean())
C.save_json(C.OUT / "runs" / f"{a.via}_{a.tema}.json", res)
log.info("%s", res)
print(f"{a.via} {a.tema}: {res['bpm']} BPM, {len(beats)} pulsos, total {res['total_s']} s "
      f"(pre {res['pre_s']} / inf {res['inf_s']} / post {res['post_s']})")
