"""Fase 5b: series de golpes de platos (49) de ADTOF en El roce y rasgos de banda alta por golpe.

Uso: Tools/py/.venv/bin/python Probes/P5b-guitarra/drums/series.py   (después de diagnose.py)
Serie = golpes de platos consecutivos con IOI <= MAX_IOI. Rasgos de la banda >5 kHz del stem (sin bombo ni
cuerpo de caja): nivel de pico relativo a la mediana de su serie, caída a +150 ms (antes de la corchea siguiente
a 171 BPM) y centroide de 2-16 kHz; el mismo cálculo en los golpes de charles y de platos aislados como referencia.
"""
import json
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfiltfilt, fftconvolve

ROOT = Path(__file__).resolve().parents[3]
SONG = Path.home() / "Music/ToneForge/El roce de tu cuerpo - Platero Y Tu"
OUT = ROOT / "Temp" / "p5b" / "drums"
MAX_IOI = 0.6

hits = {k: np.array(v) for k, v in json.loads((OUT / "roce_hits.json").read_text()).items()}
act = np.load(OUT / "roce_act.npy")
x, sr = sf.read(str(SONG / "stems" / "drums.wav"), dtype="float32", always_2d=True)
x = x.mean(axis=1)
hp = sosfiltfilt(butter(4, 5000, btype="highpass", fs=sr, output="sos"), x)
win = int(0.005 * sr)
env = 10 * np.log10(np.maximum(fftconvolve(hp.astype(np.float64) ** 2, np.ones(win) / win, mode="same"), 0) + 1e-12)
an = json.loads((SONG / "cache" / "analysis.json").read_text())["analysis"]["beats"]
downs = np.array(an["downbeats"])
beats = np.array(an["beats"])
n_fft = 2048
fq = np.fft.rfftfreq(n_fft, 1 / sr)
band = (fq >= 2000) & (fq <= 16000)


def hf(t):
    i = int(t * sr)
    pk = i + int(np.argmax(env[i:i + int(0.03 * sr)]))
    lvl = env[pk]
    s150 = env[pk + int(0.15 * sr)] - lvl if pk + int(0.15 * sr) < len(env) else np.nan
    fr = hp[i:i + n_fft] if i + n_fft <= len(hp) else np.pad(hp[i:], (0, i + n_fft - len(hp)))
    m = np.abs(np.fft.rfft(fr * np.hanning(n_fft))) ** 2
    cen = float((fq[band] * m[band]).sum() / (m[band].sum() + 1e-12))
    return lvl, s150, cen


def show(label, ts):
    if len(ts) == 0:
        print(label, "vacío")
        return
    f = np.array([hf(t) for t in ts])
    q = lambda v: "p10 %.3g p50 %.3g p90 %.3g" % tuple(np.nanpercentile(v, [10, 50, 90]))  # noqa: E731
    print(f"{label} n={len(ts)}  nivel>5k dB {q(f[:, 0])} | caída a 150 ms dB {q(f[:, 1])} | centroide 2-16k {q(f[:, 2])}")


cy = hits["cymbal"]
kick = hits["kick"]
series = []
cur = [cy[0]]
for t in cy[1:]:
    if t - cur[-1] <= MAX_IOI:
        cur.append(t)
    else:
        series.append(cur)
        cur = [t]
series.append(cur)
print(f"platos {len(cy)} en {len(series)} series (IOI <= {MAX_IOI} s)")
lens = np.array([len(s) for s in series])
print("longitud de serie: hist (1,2,3-4,5-8,9-16,17+):", np.histogram(lens, [1, 2, 3, 5, 9, 17, 1e9])[0].tolist())
firsts, rest, singles = [], [], []
for s in series:
    s = np.array(s)
    ioi = np.diff(s)
    if len(s) == 1:
        singles.append(s[0])
        continue
    med = np.median(ioi)
    reg = np.mean(np.abs(ioi - med) <= 0.03 * 2) * 100
    t0 = s[0]
    on_down = np.abs(downs - t0).min() <= 0.04
    with_k = np.abs(kick - t0).min() <= 0.03
    lv = np.array([hf(t)[0] for t in s])
    print(f"  serie {t0:7.2f}-{s[-1]:7.2f} s n={len(s):3d} IOI mediana {med * 1000:4.0f} ms regular {reg:3.0f}% "
          f"1.º: compás {int(on_down)} bombo {int(with_k)} nivel-mediana {lv[0] - np.median(lv):+5.1f} dB, "
          f"máx resto-mediana {np.max(lv[1:]) - np.median(lv):+5.1f} dB")
    firsts.append(t0)
    rest.extend(s[1:])
show("charles (42)", hits["hihat"])
show("platos aislados", np.array(singles))
show("platos 1.º de serie", np.array(firsts))
show("platos resto de serie", np.array(rest))
