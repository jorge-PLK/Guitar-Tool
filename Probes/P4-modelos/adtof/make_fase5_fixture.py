"""Fase 5 · parte 1: fixture de paridad para `DrumTranscriber` (TabKit) y paridad del Core ML embebido.

Uso (bajo el vigilante):
  Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --log Probes/P4-modelos/adtof/out/logs/guard_fixture.log \
      -- Tools/py/.venv/bin/python Probes/P4-modelos/adtof/make_fase5_fixture.py

1. Recorta 10 s del stem de batería de T1 (BS-RoFormer SW, Core ML publicado) desde el segundo 108, a mono
   (media de canales), lo cuantiza a PCM 16 y escribe audio.wav. Todo lo demás sale de las muestras ya cuantizadas
   (int16 / 32768, lo que da AVAudioFile en float32).
2. Espectrograma de entrada [T, 84] con el preproceso del puerto (adtof_pytorch.audio.AudioProcessor), comprobado
   contra `process_audio_file(audio.wav)`; banco de filtros en filterbank.json (solo los pesos no nulos).
3. Activaciones [T, 5] de PyTorch (CPU, FP32) y golpes con el PeakPicker del puerto (umbrales del contrato).
4. Paridad: descomprime App/Resources/Models/ADTOF_FrameRNN_fp32.mlpackage.zip, lo carga en CPU_ONLY y compara
   activaciones y golpes; cronometra el fixture y el stem completo de T1.
Escribe en Packages/TabKit/Tests/TabKitTests/Fixtures/drums/ (salvo el README) y el informe en out/fase5/.
Log en out/logs/fixture.log.
"""
import argparse
import json
import shutil
import subprocess
import time

import numpy as np
import soundfile as sf
import torch

import ad_common as C

FIX = C.ROOT / "Packages" / "TabKit" / "Tests" / "TabKitTests" / "Fixtures" / "drums"
ZIP = C.ROOT / "App" / "Resources" / "Models" / "ADTOF_FrameRNN_fp32.mlpackage.zip"
WORK = C.OUT / "fase5"
HOP = 441
N_FFT = 2048


def peak_params() -> dict:
    from adtof_pytorch.post_processing import PeakPicker
    p = PeakPicker(thresholds=C.THRESHOLDS, fps=C.FPS).processors[0]
    return {"pre_avg_frames": round(p.pre_avg * C.FPS), "post_avg_frames": round(p.post_avg * C.FPS),
            "pre_max_frames": round(p.pre_max * C.FPS), "post_max_frames": round(p.post_max * C.FPS),
            "combine_frames": max(1, round(p.combine * C.FPS))}


def hit_list(hits: dict) -> list[dict]:
    out = [{"frame": int(round(t * C.FPS)), "time": round(float(t), 6), "note": lab}
           for n, lab in zip(C.NAMES, C.LABELS) for t in hits[n]]
    return sorted(out, key=lambda h: (h["frame"], h["note"]))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", type=float, default=108.0, help="segundo de inicio en el stem de T1")
    ap.add_argument("--seconds", type=float, default=10.0)
    a = ap.parse_args()
    log = C.setup_log("fixture")
    import coremltools as ct
    log.info("torch %s coremltools %s numpy %s", torch.__version__, ct.__version__, np.__version__)
    FIX.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)

    # 1. audio
    stem = C.stem_path("T1")
    x, sr = sf.read(str(stem), dtype="float32", always_2d=True)
    assert sr == C.SR, sr
    i0, n = int(round(a.start * sr)), int(round(a.seconds * sr))
    mono = x[i0:i0 + n].mean(axis=1)
    q = np.clip(np.round(mono * 32768.0), -32768, 32767).astype(np.int16)
    wav = FIX / "audio.wav"
    sf.write(str(wav), q, sr, subtype="PCM_16")
    audio, _ = sf.read(str(wav), dtype="float32")
    assert np.array_equal(audio, q.astype(np.float32) / 32768.0)

    # 2. espectrograma
    from adtof_pytorch.audio import AudioProcessor
    proc = AudioProcessor()
    spec = proc.apply_filterbank(proc.compute_stft(audio)).T.astype(np.float32)        # (T, 84)
    via_file = C.features(wav)[:, :, 0]
    feat_diff = float(np.abs(spec - via_file).max())
    T = spec.shape[0]
    assert spec.shape == (1 + n // HOP, 84), spec.shape
    fb = proc.filterbank                                                               # (84, 1024)
    nz = np.argwhere(fb != 0)
    (FIX / "filterbank.json").write_text(json.dumps({
        "shape": list(fb.shape), "layout": "entries = [band, fftBin, weight]; fila band, columna fftBin de |X|[0:1024]",
        "entries": [[int(b), int(k), float(fb[b, k])] for b, k in nz]}, separators=(",", ":")))

    # 3. referencia PyTorch
    m = C.load_torch()
    t0 = time.perf_counter()
    with torch.no_grad():
        act = m(torch.from_numpy(spec)[None, :, :, None]).numpy()[0].astype(np.float32)  # (T, 5)
    t_torch = time.perf_counter() - t0
    hits = hit_list(C.pick(act))
    spec.astype("<f4").tofile(FIX / "spec.f32")
    act.astype("<f4").tofile(FIX / "act.f32")

    # 4. Core ML embebido
    unz = WORK / "unzipped"
    shutil.rmtree(unz, ignore_errors=True)
    unz.mkdir(parents=True)
    subprocess.run(["/usr/bin/ditto", "-x", "-k", str(ZIP), str(unz)], check=True)
    pkg = unz / "ADTOF_FrameRNN_fp32.mlpackage"
    t0 = time.perf_counter()
    ml = ct.models.MLModel(str(pkg), compute_units=ct.ComputeUnit.CPU_ONLY)
    t_load = time.perf_counter() - t0
    feed = {"spec": spec[None, :, :, None]}
    times = []
    for _ in range(5):
        t0 = time.perf_counter()
        y = ml.predict(feed)["act"][0]
        times.append(time.perf_counter() - t0)
    d = np.abs(y - act)
    hits_ml = hit_list(C.pick(y.astype(np.float32)))
    full = C.features(stem)
    t0 = time.perf_counter()
    ml.predict({"spec": full[None].astype(np.float32)})
    t_full = time.perf_counter() - t0

    counts = {str(l): sum(h["note"] == l for h in hits) for l in C.LABELS}
    (FIX / "hits.json").write_text(json.dumps({"labels": C.LABELS, "names": C.NAMES, "counts": counts, "hits": hits},
                                              indent=1))
    parity = {"coreml_cpu_only_max_abs_diff": float(d.max()), "coreml_cpu_only_mean_abs_diff": float(d.mean()),
              "coreml_hits_identical": hits_ml == hits, "spec_vs_process_audio_file_max_abs_diff": feat_diff}
    meta = {
        "source": {"song": "T1", "stem": "drums.wav (BS-RoFormer SW, Core ML publicado)", "start_s": a.start,
                   "seconds": a.seconds, "mono": "media de canales", "quantized": "PCM 16, x = int16 / 32768"},
        "audio": {"file": "audio.wav", "sample_rate": C.SR, "samples": int(n), "channels": 1, "subtype": "PCM_16"},
        "preprocess": {"n_fft": N_FFT, "hop": HOP, "window": "np.hanning(2048): 0.5 - 0.5 cos(2 pi i / 2047)",
                       "center": True, "pad": "1024 ceros a cada lado", "magnitude_bins": "|X|[0:1024]",
                       "filterbank": "filterbank.json [84, 1024]", "log": "log10(1 + fb @ |X|)",
                       "frames": "T = 1 + floor(samples / 441)"},
        "arrays": {"spec.f32": {"shape": [T, 84], "dtype": "float32 little-endian, fila mayor"},
                   "act.f32": {"shape": [T, 5], "dtype": "float32 little-endian, fila mayor",
                               "columns": dict(zip(C.NAMES, C.LABELS))}},
        "model": {"zip": ZIP.name, "zip_sha256": C.sha256(ZIP), "zip_bytes": ZIP.stat().st_size,
                  "input": "spec [1, T, 84, 1] float32", "output": "act [1, T, 5] float32", "compute_units": "cpuOnly",
                  "reference": "PyTorch 2.7.0 CPU FP32, puerto xavriley/ADTOF-pytorch " + C.REPO_COMMIT[:7]},
        "peaks": {"fps": C.FPS, "thresholds": dict(zip(C.NAMES, C.THRESHOLDS)), **peak_params()},
        "parity": parity,
        "timing_s": {"torch_fixture": round(t_torch, 4), "coreml_load": round(t_load, 3),
                     "coreml_fixture_median": round(float(np.median(times)), 4),
                     "coreml_full_T1": round(t_full, 3), "full_T1_frames": int(full.shape[0])},
    }
    (FIX / "meta.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False))
    shutil.copy2(FIX / "meta.json", WORK / "fixture_report.json")
    size = sum(f.stat().st_size for f in FIX.iterdir() if f.is_file())
    log.info("%s", json.dumps(meta, ensure_ascii=False))
    print(f"T={T} golpes {counts} · Core ML máx {d.max():.2e} media {d.mean():.2e} · golpes iguales {hits_ml == hits}")
    print(f"tiempo Core ML fixture {np.median(times):.4f} s · T1 completo {t_full:.3f} s · fixture {size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
