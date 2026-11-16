"""Basic Pitch: paridad del Core ML oficial frente a la referencia de Python (ONNX Runtime, CPU), notas con el
post-proceso por defecto, velocidad y fixture para el test de paridad de Swift (TabKit).

Requiere haber ejecutado convert.py (out/src con nmp.mlpackage y nmp.onnx).
Uso: Tools/py/.venv/bin/python Probes/P4-modelos/basic_pitch/compare.py [--t1 RUTA/guitar.wav]
"""
import argparse
import hashlib
import json
import logging
import resource
import sys
import time
import traceback
import warnings
from pathlib import Path

import numpy as np
import soundfile as sf

warnings.filterwarnings("ignore")
HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
SRC = OUT / "src"
REPO = HERE.parents[2]
FIX = REPO / "Packages" / "TabKit" / "Tests" / "TabKitTests" / "Fixtures" / "BasicPitch"
T1_DEFAULT = Path("/Volumes/SSD Mac/Personales/Guitar Tool/Probes/testaudio/out/T1/stems/guitar.wav")

log = logging.getLogger("compare")
log.setLevel(logging.INFO)
log.propagate = False
_fh = logging.FileHandler(OUT / "compare.log", mode="w")
_fh.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
log.addHandler(_fh)


def _excepthook(t, v, tb):
    log.error("".join(traceback.format_exception(t, v, tb)))
    print(f"ERROR: {t.__name__}: {v} (ver {OUT / 'compare.log'})")


sys.excepthook = _excepthook

import coremltools as ct  # noqa: E402
import librosa  # noqa: E402
import mir_eval  # noqa: E402
import onnxruntime as ort  # noqa: E402
from basic_pitch import constants as C  # noqa: E402
from basic_pitch import note_creation as nc  # noqa: E402
from basic_pitch.inference import unwrap_output, window_audio_file  # noqa: E402

SR = C.AUDIO_SAMPLE_RATE  # 22050
N_OLAP = 30  # tramas de solape (run_inference)
OLAP_LEN = N_OLAP * C.FFT_HOP  # 7680 muestras
HOP = C.AUDIO_N_SAMPLES - OLAP_LEN  # 36164 muestras
# post-proceso por defecto de basic_pitch.inference.predict
PARAMS = dict(onset_thresh=0.5, frame_thresh=0.3, min_note_len=int(np.round(127.70 / 1000 * (SR / C.FFT_HOP))),
              infer_onsets=True, melodia_trick=True, energy_tol=11, min_freq=None, max_freq=None)
KEYS = ("note", "onset", "contour")


def infer(audio: np.ndarray, predict) -> dict:
    """Igual que basic_pitch.inference.run_inference, pero desde un array a 22050 Hz mono."""
    padded = np.concatenate([np.zeros(OLAP_LEN // 2, np.float32), audio.astype(np.float32)])
    outs = {k: [] for k in KEYS}
    for w, _ in window_audio_file(padded, HOP):
        for k, v in predict(w[None].astype(np.float32)).items():
            outs[k].append(v)
    return {k: unwrap_output(np.concatenate(v), len(audio), N_OLAP) for k, v in outs.items()}


def onnx_predictor():
    s = ort.InferenceSession(str(SRC / "nmp.onnx"), providers=["CPUExecutionProvider"])
    names = ["StatefulPartitionedCall:1", "StatefulPartitionedCall:2", "StatefulPartitionedCall:0"]
    return lambda x: dict(zip(KEYS, s.run(names, {"serving_default_input_2:0": x})))


def coreml_predictor(units):
    m = ct.models.MLModel(str(SRC / "nmp.mlpackage"), compute_units=units)

    def p(x):
        r = m.predict({"input_2": x})
        return {"note": r["Identity_1"], "onset": r["Identity_2"], "contour": r["Identity"]}
    return p


def compute_plan(units) -> dict:
    """Cuenta de operaciones por dispositivo preferido (MLComputePlan) para estas unidades."""
    from collections import Counter
    from coremltools.models.compute_plan import MLComputePlan

    m = ct.models.MLModel(str(SRC / "nmp.mlpackage"), compute_units=units)
    plan = MLComputePlan.load_from_path(path=m.get_compiled_model_path(), compute_units=units)
    prog = plan.model_structure.program
    cnt = Counter()
    for op in prog.functions["main"].block.operations:
        if op.operator_name == "const":
            continue
        u = plan.get_compute_device_usage_for_mlprogram_operation(op)
        cnt[type(u.preferred_compute_device).__name__ if u else "None"] += 1
    return dict(cnt)


def notes(out: dict):
    """Notas en tramas (output_to_notes_polyphonic) y en segundos con pitch bends (model_output_to_notes)."""
    fr = nc.output_to_notes_polyphonic(out["note"].copy(), out["onset"].copy(), PARAMS["onset_thresh"],
                                       PARAMS["frame_thresh"], PARAMS["min_note_len"], PARAMS["infer_onsets"],
                                       None, None, PARAMS["melodia_trick"], PARAMS["energy_tol"])
    midi, ev = nc.model_output_to_notes({k: v.copy() for k, v in out.items()}, onset_thresh=PARAMS["onset_thresh"],
                                        frame_thresh=PARAMS["frame_thresh"], infer_onsets=PARAMS["infer_onsets"],
                                        min_note_len=PARAMS["min_note_len"], melodia_trick=PARAMS["melodia_trick"])
    assert len(fr) == len(ev)
    return fr, ev, midi


def diffs(ref: dict, est: dict) -> dict:
    return {k: (float(np.max(np.abs(ref[k] - est[k]))), float(np.mean(np.abs(ref[k] - est[k])))) for k in KEYS}


def fmeasure(ref_ev, est_ev) -> dict:
    def arr(ev):
        if not ev:
            return np.zeros((0, 2)), np.zeros(0)
        return (np.array([[e[0], e[1]] for e in ev], float),
                librosa.midi_to_hz(np.array([e[2] for e in ev], float)))
    ri, rp = arr(ref_ev)
    ei, ep = arr(est_ev)
    on = mir_eval.transcription.precision_recall_f1_overlap(ri, rp, ei, ep, onset_tolerance=0.05, offset_ratio=None)
    off = mir_eval.transcription.precision_recall_f1_overlap(ri, rp, ei, ep, onset_tolerance=0.05)
    return {"F_onset": on[2], "F_onset_offset": off[2], "n_ref": len(ref_ev), "n_est": len(est_ev)}


def exact_matches(fa, fb) -> int:
    return len({(a[0], a[1], a[2]) for a in fa} & {(b[0], b[1], b[2]) for b in fb})


def pick_clip(y: np.ndarray, seconds: float) -> int:
    """Inicio (muestra) del tramo con la guitarra siempre activa: máximo del RMS mínimo por segundo."""
    rms = np.sqrt(np.mean(y[: len(y) // SR * SR].reshape(-1, SR) ** 2, axis=1)) + 1e-9
    n = int(seconds)
    best = max(range(20, len(rms) - n), key=lambda s: rms[s:s + n].min())
    return best * SR


def quantize_wav(path: Path, x: np.ndarray) -> np.ndarray:
    sf.write(path, x, SR, subtype="PCM_16")
    q, _ = sf.read(path, dtype="int16")
    return (q.astype(np.float32) / 32768.0)


def listen(path: Path, clip: np.ndarray, midi) -> None:
    syn = midi.synthesize(fs=SR)[: len(clip)]
    syn = np.pad(syn, (0, len(clip) - len(syn)))
    syn = syn / (np.max(np.abs(syn)) + 1e-9) * np.max(np.abs(clip))
    sf.write(path, np.stack([clip, syn], axis=1), SR, subtype="PCM_16")


def timing(audio: np.ndarray, make, reps: int = 3) -> dict:
    t0 = time.perf_counter()
    p = make()
    p(np.zeros((1, C.AUDIO_N_SAMPLES, 1), np.float32))
    load = time.perf_counter() - t0
    ts = []
    for _ in range(reps):
        t = time.perf_counter()
        infer(audio, p)
        ts.append(time.perf_counter() - t)
    return {"load_s": load, "s_per_min": float(np.median(ts)) * 60 * SR / len(audio)}


def write_fixture(clip6: np.ndarray, ref: dict, fr, ev, cm_diff: dict, zip_sha: str) -> None:
    FIX.mkdir(parents=True, exist_ok=True)
    files = {}
    for k in KEYS:
        p = FIX / f"{k}.f32"
        ref[k].astype("<f4").tofile(p)
        files[p.name] = {"shape": list(ref[k].shape), "dtype": "float32 little-endian, fila mayor [trama][bin]"}
    out_notes = [{"startFrame": int(a[0]), "endFrame": int(a[1]), "pitch": int(a[2]), "amplitude": float(a[3]),
                  "startTime": float(e[0]), "endTime": float(e[1]),
                  "pitchBends": [int(b) for b in e[4]] if e[4] is not None else None}
                 for a, e in zip(fr, ev)]
    (FIX / "notes.json").write_text(json.dumps({"params": PARAMS, "notes": out_notes}, indent=1))
    meta = {
        "audio": {"file": "audio.wav", "sampleRate": SR, "channels": 1, "format": "PCM 16 bit",
                  "samples": int(len(clip6)), "read_as": "int16 / 32768"},
        "windowing": {"windowSamples": C.AUDIO_N_SAMPLES, "overlapFrames": N_OLAP, "overlapSamples": OLAP_LEN,
                      "hopSamples": HOP, "leftPadSamples": OLAP_LEN // 2, "framesPerWindow": C.ANNOT_N_FRAMES,
                      "trimFramesEachSide": N_OLAP // 2,
                      "outputFrames": int(np.floor(len(clip6) * C.ANNOTATIONS_FPS / SR)),
                      "windows": int(np.ceil((len(clip6) + OLAP_LEN // 2) / HOP))},
        "bins": {"note": C.N_FREQ_BINS_NOTES, "onset": C.N_FREQ_BINS_NOTES, "contour": C.N_FREQ_BINS_CONTOURS,
                 "midiOffset": nc.MIDI_OFFSET, "contourBinsPerSemitone": C.CONTOURS_BINS_PER_SEMITONE,
                 "baseFrequencyHz": C.ANNOTATIONS_BASE_FREQUENCY},
        "files": files,
        "reference": "ONNX Runtime 1.32 CPU, nmp.onnx de spotify/basic-pitch@fa5997a",
        "coremlPythonVsReference": {k: {"max": v[0], "mean": v[1]} for k, v in cm_diff.items()},
        "modelZipSha256": zip_sha,
    }
    (FIX / "meta.json").write_text(json.dumps(meta, indent=1))
    log.info("fixture en %s: %s", FIX, {p.name: p.stat().st_size for p in sorted(FIX.iterdir())})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--t1", type=Path, default=T1_DEFAULT)
    a = ap.parse_args()
    y, _ = librosa.load(str(a.t1), sr=SR, mono=True)  # igual que get_audio_input
    s0 = pick_clip(y, 10)
    log.info("T1 %.1f s; tramo de 10 s desde %.1f s", len(y) / SR, s0 / SR)
    clip10 = quantize_wav(OUT / "clip10s.wav", y[s0:s0 + 10 * SR])
    FIX.mkdir(parents=True, exist_ok=True)
    clip6 = quantize_wav(FIX / "audio.wav", y[s0:s0 + 6 * SR])

    ref_p = onnx_predictor()
    gpu_p = coreml_predictor(ct.ComputeUnit.CPU_AND_GPU)
    cpu_p = coreml_predictor(ct.ComputeUnit.CPU_ONLY)
    res = {}
    ref = infer(clip10, ref_p)
    log.info("formas %s", {k: v.shape for k, v in ref.items()})
    fr_ref, ev_ref, midi_ref = notes(ref)
    for name, p in (("coreml_cpu_gpu", gpu_p), ("coreml_cpu", cpu_p)):
        est = infer(clip10, p)
        fr, ev, midi = notes(est)
        res[name] = {"diff": diffs(ref, est), **fmeasure(ev_ref, ev), "exact": exact_matches(fr_ref, fr)}
        log.info("%s %s", name, json.dumps(res[name]))
        if name == "coreml_cpu_gpu":
            listen(OUT / "listen_10s_coreml.wav", clip10, midi)
    listen(OUT / "listen_10s_onnx.wav", clip10, midi_ref)

    # notas en un tramo largo (60 s) para tener más notas en el F-measure, y velocidad
    long = y[30 * SR:90 * SR]
    ref_l = infer(long, ref_p)
    est_l = infer(long, gpu_p)
    _, ev_rl, _ = notes(ref_l)
    fr_el, ev_el, _ = notes(est_l)
    res["long60_cpu_gpu"] = {"diff": diffs(ref_l, est_l), **fmeasure(ev_rl, ev_el)}
    log.info("long60 %s", json.dumps(res["long60_cpu_gpu"]))
    speed = {
        "onnx_cpu": timing(long, onnx_predictor),
        "coreml_cpu_gpu": timing(long, lambda: coreml_predictor(ct.ComputeUnit.CPU_AND_GPU)),
        "coreml_cpu": timing(long, lambda: coreml_predictor(ct.ComputeUnit.CPU_ONLY)),
    }
    log.info("velocidad %s", json.dumps(speed))
    try:
        plan = {"cpu_gpu": compute_plan(ct.ComputeUnit.CPU_AND_GPU)}
    except Exception as e:  # informativo: no debe tumbar el fixture
        plan = {"error": repr(e)}
    log.info("compute plan %s", json.dumps(plan))

    # fixture (6 s, PCM 16 ya cuantizado; referencia ONNX)
    ref6 = infer(clip6, ref_p)
    cm6 = infer(clip6, gpu_p)
    fr6, ev6, _ = notes(ref6)
    zip_sha = json.loads((OUT / "manifest.json").read_text())["zip"]["sha256"]
    write_fixture(clip6, ref6, fr6, ev6, diffs(ref6, cm6), zip_sha)
    fr6c, _, _ = notes(cm6)
    log.info("fixture: notas ref %d, coreml %d, iguales %d", len(fr6), len(fr6c), exact_matches(fr6, fr6c))
    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 2**30
    log.info("pico RSS %.2f GB", peak)
    (OUT / "results.json").write_text(json.dumps({"clip_start_s": s0 / SR, "parity": res, "speed": speed,
                                                  "compute_plan": plan, "fixture_notes": len(fr6), "peak_rss_gb": peak}, indent=1))

    g = res["coreml_cpu_gpu"]
    print("10 s CPU+GPU vs ONNX: " + ", ".join(f"{k} max {v[0]:.2e} media {v[1]:.2e}" for k, v in g["diff"].items()))
    print(f"notas 10 s: F_on {g['F_onset']:.3f} F_on+off {g['F_onset_offset']:.3f} ({g['n_est']}/{g['n_ref']}, "
          f"iguales {g['exact']}); 60 s: F_on {res['long60_cpu_gpu']['F_onset']:.3f} "
          f"({res['long60_cpu_gpu']['n_est']}/{res['long60_cpu_gpu']['n_ref']})")
    print("s por min: " + ", ".join(f"{k} {v['s_per_min']:.2f} (carga {v['load_s']:.2f})" for k, v in speed.items()))
    print(f"plan CPU+GPU: {plan}")
    print(f"fixture: {len(fr6)} notas, pico {peak:.2f} GB; detalle en {OUT / 'compare.log'}")


if __name__ == "__main__":
    main()
