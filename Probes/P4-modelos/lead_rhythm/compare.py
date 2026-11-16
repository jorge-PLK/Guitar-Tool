"""Paridad del Core ML (lr_common: STFT/iSTFT y troceado en numpy, como hará Swift) frente a PyTorch.
Lanzar SIEMPRE bajo ../common/guard.py, un proceso por variante, con python -I.

  compare.py fp32|fp16   # Platero 157-187 s y 60-90 s, T3 desde 144,5 s: SDR del lead frente al lead de PyTorch
                         # (run_torch.py, Temp/bench/platero/lead-rhythm), SDR frente a la referencia de T3,
                         # tiempo por 30 s (CPU+GPU) y memoria pico. WAV en Temp/bench/platero/lead-rhythm-coreml-<prec>/
  compare.py fixture     # fixture de 2 s para el test de paridad de Swift (entrada PCM16 + lead de PyTorch)
Log en out/compare.log; resumen en out/compare_<modo>.json."""
import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lr_common as C  # noqa: E402
from metrics import PeakMem, load_wav, phys_footprint, save_wav, sdr  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("mode", choices=["fp32", "fp16", "fixture"])
args = ap.parse_args()
log = C.setup_log("compare")
log.info("==== compare %s", args.mode)

BENCH = C.WT / "Temp/bench/platero"
REF = BENCH / "lead-rhythm"
CUTS = ["157-187s", "60-90s", "T3-144.5s"]
PLATERO = Path("/Users/jorgefernandezhurtado/Music/ToneForge/El roce de tu cuerpo - Platero Y Tu/stems/guitar.wav")
FIX = C.WT / "Packages/StemKit/Tests/StemKitTests/Fixtures/LeadRhythm"
FIX_START = 165.0          # dentro del solo de Platero
FIX_LEN = 88200            # 2 s: un solo trozo, relleno reflect hasta 132300 (como demix)


def load_coreml(prec):
    import coremltools as ct
    p = C.OUT / C.PACKAGE.format(prec)
    t0 = time.perf_counter()
    m = ct.models.MLModel(str(p), compute_units=ct.ComputeUnit.CPU_AND_GPU)   # nunca ANE
    log.info("%s cargado (CPU_AND_GPU) en %.1f s", p.name, time.perf_counter() - t0)
    return m


class Runner:
    def __init__(self, ml):
        self.ml, self.model_sec, self.calls = ml, 0.0, 0

    def mask(self, spec):
        t0 = time.perf_counter()
        y = self.ml.predict({"spec": spec})["mask"]
        self.model_sec += time.perf_counter() - t0
        self.calls += 1
        return y

    def __call__(self, part):
        return C.run_chunk_np(part, self.mask)


def db(x, ref):
    return 10 * np.log10((np.sum(x.astype(np.float64) ** 2) + 1e-20) / (np.sum(ref.astype(np.float64) ** 2) + 1e-20))


if args.mode in ("fp32", "fp16"):
    base = phys_footprint()[0]
    with PeakMem() as pm:
        r = Runner(load_coreml(args.mode))
        r.mask(np.zeros((1, 2 * C.F, C.FRAMES, 2), np.float32))          # calentamiento
        res = {}
        for cut in CUTS:
            d = REF / cut
            x, sr = load_wav(d / f"lead-rhythm_{cut}_input.wav")
            lead_t, _ = load_wav(d / f"lead-rhythm_{cut}_lead.wav")
            r.model_sec, r.calls = 0.0, 0
            t0 = time.perf_counter()
            lead = C.demix_np(x, r)
            total = time.perf_counter() - t0
            rhythm = x - lead
            dur = x.shape[-1] / sr
            o = {"sdr_vs_torch": round(sdr(lead, lead_t), 2), "max_abs_diff": float(np.abs(lead - lead_t).max()),
                 "mean_abs_diff": float(np.abs(lead - lead_t).mean()), "lead_db": round(db(lead, x), 2),
                 "torch_lead_db": round(db(lead_t, x), 2), "chunks": r.calls,
                 "model_s_per_30s": round(r.model_sec * 30 / dur, 2), "total_s_per_30s": round(total * 30 / dur, 2)}
            if cut.startswith("T3"):
                ref_lead, _ = load_wav(d / f"lead-rhythm_{cut}_ref_lead.wav")
                o["sdr_vs_T3_ref"] = round(sdr(lead, ref_lead), 3)
                o["torch_sdr_vs_T3_ref"] = round(sdr(lead_t, ref_lead), 3)
            res[cut] = o
            log.info("%s: %s", cut, o)
            tag = f"lead-rhythm-coreml-{args.mode}"
            save_wav(BENCH / tag / cut / f"{tag}_{cut}_lead.wav", lead, sr)
            save_wav(BENCH / tag / cut / f"{tag}_{cut}_rhythm.wav", rhythm, sr)
    res["peak_gb"] = round(pm.peak / 2**30, 2)
    res["baseline_gb"] = round(base / 2**30, 2)
    log.info("memoria: base %.2f GB, pico %.2f GB", base / 2**30, pm.peak / 2**30)
    json.dump(res, open(C.OUT / f"compare_{args.mode}.json", "w"), indent=1)
    for cut in CUTS:
        o = res[cut]
        print(f"{cut}: SDR vs torch {o['sdr_vs_torch']} dB, max {o['max_abs_diff']:.2g}, modelo {o['model_s_per_30s']} s/30 s, "
              f"total {o['total_s_per_30s']} s/30 s" + (f", SDR vs ref T3 {o['sdr_vs_T3_ref']} (torch "
                                                         f"{o['torch_sdr_vs_T3_ref']})" if "sdr_vs_T3_ref" in o else ""))
    print(f"pico {res['peak_gb']} GB (base {res['baseline_gb']} GB)")
else:
    import torch
    from ml_collections import ConfigDict

    model, cfg = C.load_model(log)
    from utils.model_utils import demix

    g, sr = load_wav(PLATERO)
    a = int(FIX_START * sr)
    x16 = np.round(np.clip(g[:, a:a + FIX_LEN], -1, 32767 / 32768) * 32768).astype(np.int16)
    del g
    FIX.mkdir(parents=True, exist_ok=True)
    sf.write(str(FIX / "input_2s_pcm16.wav"), x16.T, sr, subtype="PCM_16")
    x = (x16.astype(np.float32) / 32768.0)                                  # como AVAudioFile
    with torch.no_grad():
        lead_t = demix(ConfigDict(cfg), model, x, torch.device("cpu"), "mel_band_roformer", pbar=False)["Lead"]
    lead_t = lead_t.astype(np.float32)
    sf.write(str(FIX / "lead_torch_2s_f32.wav"), lead_t.T, sr, subtype="FLOAT")
    # primer trozo tal como lo ve el modelo: spec de la entrada rellenada (reflect) y su máscara de PyTorch
    part = np.pad(x, ((0, 0), (0, C.CHUNK - FIX_LEN)), mode="reflect")
    spec = C.stft_spec(part)
    core, _ = C.make_core(model)
    with torch.no_grad():
        mask_t = core(torch.from_numpy(spec)).numpy()
    probes = [(r_, t_) for r_ in (2, 3, 101, 400, 1201, 2049) for t_ in (0, 150, 300)]
    out = {"source": f"Platero stems/guitar.wav desde {FIX_START} s, {FIX_LEN} muestras, PCM16 (x/32768)",
           "sample_rate": sr, "reference": "PyTorch MelBandRoformer + demix de MSST (CPU FP32)",
           "lead_rms": float(np.sqrt(np.mean(lead_t.astype(np.float64) ** 2))),
           "input_rms": float(np.sqrt(np.mean(x.astype(np.float64) ** 2))),
           "lead_first8_L": lead_t[0, :8].tolist(), "lead_at_44100_LR": [float(lead_t[0, 44100]), float(lead_t[1, 44100])],
           "mask_probes": [{"row": r_, "frame": t_, "re": float(mask_t[0, 0, r_, t_, 0]),
                            "im": float(mask_t[0, 0, r_, t_, 1])} for r_, t_ in probes],
           "spec_probes": [{"row": r_, "frame": t_, "re": float(spec[0, r_, t_, 0]), "im": float(spec[0, r_, t_, 1])}
                           for r_, t_ in probes]}
    for prec in ("fp32", "fp16"):
        lead_c = C.demix_np(x, Runner(load_coreml(prec)))
        out[f"coreml_{prec}_sdr_vs_torch"] = round(sdr(lead_c, lead_t), 2)
        out[f"coreml_{prec}_max_abs_diff"] = float(np.abs(lead_c - lead_t).max())
    json.dump(out, open(FIX / "reference.json", "w"), indent=1)
    log.info("fixture: %s", {k: v for k, v in out.items() if k.startswith("coreml") or k.endswith("rms")})
    print(f"fixture en {FIX}: Core ML fp32 {out['coreml_fp32_sdr_vs_torch']} dB, fp16 {out['coreml_fp16_sdr_vs_torch']} dB "
          f"frente a PyTorch")
