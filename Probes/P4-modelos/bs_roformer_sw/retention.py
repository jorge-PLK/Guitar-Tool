"""Prueba de retención de memoria de Core ML en un mismo proceso (gridshift, CPU_AND_GPU).
Carga el modelo UNA vez y separa el mismo tema N veces seguidas, sin referencias ni métricas;
escribe los stems y libera arrays (del + gc) tras cada pasada. Registra RSS y phys_footprint tras
cargar y al final de cada pasada, y el pico muestreado (cada 50 ms) de cada pasada.
Uso: retention.py [T1] [--passes 3]   (lanzar con ../common/guard.py)"""
import argparse
import gc
import sys
import threading
import time

import numpy as np
import psutil

import sw_common as C
from metrics import load_wav, phys_footprint, save_wav

ap = argparse.ArgumentParser()
ap.add_argument("track", nargs="?", default="T1")
ap.add_argument("--passes", type=int, default=3)
args = ap.parse_args()
log = C.setup_log("retention")
sys.excepthook = lambda t, v, tb: log.error("excepción no capturada", exc_info=(t, v, tb))
proc = psutil.Process()


def snap():
    return proc.memory_info().rss / 1e9, phys_footprint()[0] / 1e9


class Sampler:
    def __enter__(self):
        self.peak_rss = self.peak_fp = 0.0
        self._s = threading.Event()
        self._t = threading.Thread(target=self._run, daemon=True)
        self._t.start()
        return self

    def _run(self):
        while not self._s.is_set():
            r, f = snap()
            self.peak_rss, self.peak_fp = max(self.peak_rss, r), max(self.peak_fp, f)
            self._s.wait(0.05)

    def __exit__(self, *a):
        self._s.set()
        self._t.join()


import coremltools as ct  # noqa: E402

r0 = snap()
mdl = ct.models.MLModel(str(C.OUT / "coreml_pub" / "BSRoformerSW.mlpackage"), compute_units=ct.ComputeUnit.CPU_AND_GPU)
out_name = mdl.get_spec().description.output[0].name


def run_chunk(part):
    spec = C.stft_np(part)
    T = spec.shape[2]
    x = np.ascontiguousarray(spec.transpose(1, 0, 2, 3).reshape(1, 2 * C.N_FREQ, T, 2))
    m = mdl.predict({"spec": x})[out_name][0].astype(np.float32)
    sr_, si_ = x[0, ..., 0], x[0, ..., 1]
    o = np.stack([sr_ * m[..., 0] - si_ * m[..., 1], sr_ * m[..., 1] + si_ * m[..., 0]], -1)
    o[:, :2] = 0.0
    o = o.reshape(6, C.N_FREQ, 2, T, 2).transpose(0, 2, 1, 3, 4).reshape(12, C.N_FREQ, T, 2)
    return C.istft_np(o, C.CHUNK).reshape(6, 2, -1)


r1 = snap()
log.info("antes de cargar: rss %.2f GB fp %.2f GB; tras cargar: rss %.2f GB fp %.2f GB", *r0, *r1)
lines = [f"tras cargar: RSS {r1[0]:.2f} GB (footprint {r1[1]:.2f})"]
for i in range(args.passes):
    with Sampler() as s:
        t0 = time.perf_counter()
        mix, sr = load_wav(C.TESTAUDIO / args.track / "mix.wav")
        est = C.demix_np(mix, run_chunk)
        for k, st in enumerate(C.STEMS):
            save_wav(C.OUT / "retention" / f"{st}.wav", est[k], sr)
        del est, mix
        gc.collect()
        dt = time.perf_counter() - t0
    r = snap()
    log.info("pasada %d: %.1f s; fin rss %.2f GB fp %.2f GB; pico rss %.2f GB fp %.2f GB",
             i + 1, dt, *r, s.peak_rss, s.peak_fp)
    lines.append(f"pasada {i + 1}: fin RSS {r[0]:.2f} GB (fp {r[1]:.2f}), pico RSS {s.peak_rss:.2f} (fp {s.peak_fp:.2f}), {dt:.0f} s")
print("\n".join(lines))
