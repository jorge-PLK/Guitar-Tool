"""WAV de escucha para Jorge: por tema, 30 s con bombo, caja y charles sonando.

Uso: Tools/py/.venv/bin/python Probes/P4-modelos/adtof/listen.py --via torch
(a) <T>_a_stem.wav: stem de batería (BS-RoFormer Core ML gridshift), estéreo tal cual.
(b) <T>_b_render.wav: transcripción renderizada con muestras SINTETIZADAS aquí (sin muestras externas):
    bombo = seno con barrido 120→45 Hz y caída exp. 0,35 s; caja = tono 190 Hz + ruido paso banda 1-6 kHz,
    caída 0,18 s; charles = ruido paso alto 7 kHz, caída 0,05 s. Solo las tres piezas medidas (sin tom ni platos).
(c) <T>_c_overlay.wav: estéreo, izquierda = stem (mono), derecha = render.
Los 9 ficheros van a un mismo nivel integrado (pyloudnorm, BS.1770): el más alto en el que ningún fichero
pasa de -1 dBFS de pico de muestra. WAV float. Nivel y picos en out/listen/listen.json.
Ventana: los 30 s (paso 1 s) que maximizan el mínimo de golpes de las tres piezas según la transcripción.
"""
import argparse
import json

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

import ad_common as C

ap = argparse.ArgumentParser()
ap.add_argument("--via", default="torch")
ap.add_argument("--dur", type=float, default=30.0)
a = ap.parse_args()
log = C.setup_log("listen")
import pyloudnorm as pyln  # noqa: E402

SR = C.SR
rng = np.random.default_rng(0)


def env(n, tau):
    return np.exp(-np.arange(n) / (tau * SR)).astype(np.float32)


def kick():
    n = int(0.35 * SR)
    f = 45 + 75 * np.exp(-np.arange(n) / (0.04 * SR))
    return (np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.09)).astype(np.float32)


def snare():
    n = int(0.18 * SR)
    noise = sosfilt(butter(2, [1000, 6000], btype="bandpass", fs=SR, output="sos"), rng.standard_normal(n))
    tone = np.sin(2 * np.pi * 190 * np.arange(n) / SR)
    return (0.6 * noise * env(n, 0.05) + 0.5 * tone * env(n, 0.03)).astype(np.float32)


def hihat():
    n = int(0.05 * SR)
    noise = sosfilt(butter(4, 7000, btype="highpass", fs=SR, output="sos"), rng.standard_normal(n))
    return (0.5 * noise * env(n, 0.012)).astype(np.float32)


SAMPLES = {"kick": kick(), "snare": snare(), "hihat": hihat()}


def render(hits, start, n):
    y = np.zeros(n + SR, np.float32)
    for p, s in SAMPLES.items():
        for t in hits.get(p, []):
            i = int(round((t - start) * SR))
            if 0 <= i < n:
                y[i:i + len(s)] += s
    return y[:n]


PEAK_DBFS = -1.0


meter = pyln.Meter(SR)
out = C.OUT / "listen"
out.mkdir(parents=True, exist_ok=True)
info, files = {}, {}
for song in C.SONGS:
    hits = C.load_hits(C.OUT / "hits" / a.via / song)
    stem, sr = sf.read(str(C.stem_path(song)), dtype="float32", always_2d=True)
    dur_song = len(stem) / SR
    best, best_s = -1, 0.0
    for s in np.arange(0, max(0.0, dur_song - a.dur) + 1e-9, 1.0):
        c = min(int(((hits[p] >= s) & (hits[p] < s + a.dur)).sum()) for p in C.PIECES)
        if c > best:
            best, best_s = c, float(s)
    i0, n = int(best_s * SR), int(a.dur * SR)
    seg = stem[i0:i0 + n]
    ren = render(hits, best_s, len(seg))
    for tag, x in (("a_stem", seg), ("b_render", ren), ("c_overlay", np.stack([seg.mean(axis=1), ren], axis=1))):
        files[f"{song}_{tag}"] = (x.astype(np.float32), meter.integrated_loudness(x), float(np.abs(x).max()))
    info[song] = {"start_s": best_s, "min_hits_per_piece": best}

# Nivel común: el más alto en el que ningún fichero pasa de -1 dBFS de pico de muestra
# (para cada fichero, LUFS con el que su pico queda en -1 dBFS; el común es el mínimo de esos).
target = min(l + (PEAK_DBFS - 20 * np.log10(pk)) for _, l, pk in files.values())
peaks = {}
for name, (x, l, pk) in files.items():
    y = (x * 10 ** ((target - l) / 20)).astype(np.float32)
    sf.write(str(out / f"{name}.wav"), y, SR, subtype="FLOAT")
    peaks[name] = round(20 * float(np.log10(np.abs(y).max())), 2)
summary = {"lufs": round(float(target), 2), "max_peak_dbfs": max(peaks.values()), "peaks_dbfs": peaks, "songs": info}
log.info("%s", summary)
(out / "listen.json").write_text(json.dumps(summary, indent=1))
print(f"nivel común {summary['lufs']} LUFS, pico máx {summary['max_peak_dbfs']} dBFS")
