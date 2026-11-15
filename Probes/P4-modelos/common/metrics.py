"""Métricas comunes de P4 (separación de fuentes). Reutilizable por todos los modelos.

Uso típico:
    from metrics import sdr, si_sdr, diff_stats, residual_db, quality_table, fidelity_table, PeakMem
Todas las señales son numpy float (canales, muestras) o (muestras,).
"""
from __future__ import annotations

import ctypes
import os
import threading
from pathlib import Path

import numpy as np
import soundfile as sf

EPS = 1e-10


def load_wav(path) -> tuple[np.ndarray, int]:
    """Devuelve (canales, muestras) float32 y sr."""
    x, sr = sf.read(str(path), dtype="float32", always_2d=True)
    return x.T.copy(), sr


def save_wav(path, x: np.ndarray, sr: int = 44100) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(path), np.asarray(x, dtype=np.float32).T, sr, subtype="FLOAT")


def _align(a: np.ndarray, b: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    n = min(a.shape[-1], b.shape[-1])
    return a[..., :n].astype(np.float64), b[..., :n].astype(np.float64)


def sdr(est: np.ndarray, ref: np.ndarray) -> float:
    """SDR global (estilo MUSDB/MSST 'sdr'): 10 log10(|ref|² / |ref - est|²), sobre todos los canales."""
    est, ref = _align(est, ref)
    num = np.sum(ref ** 2) + EPS
    den = np.sum((ref - est) ** 2) + EPS
    return float(10 * np.log10(num / den))


def si_sdr(est: np.ndarray, ref: np.ndarray) -> float:
    """SI-SDR por canal (media de canales), con resta de media."""
    est, ref = _align(est, ref)
    est = np.atleast_2d(est)
    ref = np.atleast_2d(ref)
    vals = []
    for e, r in zip(est, ref):
        e = e - e.mean()
        r = r - r.mean()
        alpha = np.dot(e, r) / (np.dot(r, r) + EPS)
        t = alpha * r
        vals.append(10 * np.log10((np.sum(t ** 2) + EPS) / (np.sum((e - t) ** 2) + EPS)))
    return float(np.mean(vals))


def diff_stats(a: np.ndarray, b: np.ndarray) -> dict:
    a, b = _align(a, b)
    d = np.abs(a - b)
    return {"max_abs": float(d.max()), "mean_abs": float(d.mean())}


def residual_db(est: np.ndarray, mix: np.ndarray) -> float:
    """Energía de un stem estimado respecto a la mezcla, en dB (para stems sin referencia)."""
    est, mix = _align(est, mix)
    return float(10 * np.log10((np.sum(est ** 2) + EPS) / (np.sum(mix ** 2) + EPS)))


def quality_table(est_dir, ref_dir, mix_path, stems) -> dict:
    """Calidad frente a la referencia real. stems: lista de nombres.
    Para cada stem: si existe ref_dir/<stem>.wav -> SDR y SI-SDR; si no -> energía residual (dB vs mezcla)."""
    est_dir, ref_dir = Path(est_dir), Path(ref_dir)
    mix, _ = load_wav(mix_path)
    out = {}
    for s in stems:
        est, _ = load_wav(est_dir / f"{s}.wav")
        ref_p = ref_dir / f"{s}.wav"
        if ref_p.exists():
            ref, _ = load_wav(ref_p)
            out[s] = {"sdr": sdr(est, ref), "si_sdr": si_sdr(est, ref)}
        else:
            out[s] = {"residual_db": residual_db(est, mix)}
    return out


def fidelity_table(conv_dir, orig_dir, stems) -> dict:
    """Fidelidad convertido frente a original: SDR (original como referencia) y diferencia máx/media."""
    conv_dir, orig_dir = Path(conv_dir), Path(orig_dir)
    out = {}
    for s in stems:
        c, _ = load_wav(conv_dir / f"{s}.wav")
        o, _ = load_wav(orig_dir / f"{s}.wav")
        out[s] = {"sdr_vs_orig": sdr(c, o), **diff_stats(c, o)}
    return out


def fidelity_verdict(min_sdr: float) -> str:
    """Criterio aprobado: >=35 dB igual; 25-35 vale si no se oye; <25 falla."""
    if min_sdr >= 35:
        return "igual (>=35 dB)"
    if min_sdr >= 25:
        return "vale si no se oye (25-35 dB)"
    return "FALLA (<25 dB)"


def speed_verdict(sec_per_min: float, peak_gb: float) -> str:
    """Criterio: <=60 s/min (1x tiempo real) bien, <=120 aceptable, >120 o >8 GB falla."""
    if peak_gb > 8 or sec_per_min > 120:
        return "FALLA"
    return "bien" if sec_per_min <= 60 else "aceptable"


def clip(src_path, dst_path, start_s: float, dur_s: float = 30.0) -> None:
    x, sr = load_wav(src_path)
    a = int(start_s * sr)
    save_wav(dst_path, x[:, a:a + int(dur_s * sr)], sr)


def loudest_window(path, dur_s: float = 30.0, hop_s: float = 5.0) -> float:
    """Inicio (s) de la ventana de dur_s con más energía (para elegir el tramo de escucha)."""
    x, sr = load_wav(path)
    e = np.sum(x.astype(np.float64) ** 2, axis=0)
    c = np.concatenate([[0.0], np.cumsum(e)])
    w, h = int(dur_s * sr), int(hop_s * sr)
    best, best_s = -1.0, 0.0
    for a in range(0, max(1, len(e) - w), h):
        v = c[a + w] - c[a]
        if v > best:
            best, best_s = v, a / sr
    return best_s


# --- memoria ---------------------------------------------------------------

class _RusageV4(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(f"f{i}", ctypes.c_uint64) for i in range(35)]


def phys_footprint() -> tuple[int, int]:
    """(phys_footprint actual, máximo de vida) del proceso en bytes (macOS, incluye memoria Metal/ANE
    atribuida al proceso). Fuera de macOS devuelve RSS."""
    try:
        lib = ctypes.CDLL("/usr/lib/libproc.dylib")
        buf = _RusageV4()
        if lib.proc_pid_rusage(os.getpid(), 4, ctypes.byref(buf)) == 0:
            return int(buf.f7), int(buf.f28)
    except OSError:
        pass
    import psutil
    r = psutil.Process().memory_info().rss
    return r, r


class PeakMem:
    """Muestrea phys_footprint en segundo plano (complementa el máximo de vida del kernel)."""

    def __init__(self, interval: float = 0.05):
        self.interval, self.peak, self._stop = interval, 0, threading.Event()

    def __enter__(self):
        self._t = threading.Thread(target=self._run, daemon=True)
        self._t.start()
        return self

    def _run(self):
        while not self._stop.is_set():
            self.peak = max(self.peak, phys_footprint()[0])
            self._stop.wait(self.interval)

    def __exit__(self, *a):
        self._stop.set()
        self._t.join()
        self.peak = max(self.peak, phys_footprint()[1])
