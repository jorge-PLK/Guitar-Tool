"""Fase 5b, «Platos de ADTOF confundidos con charles»: diagnóstico sobre el stem de batería de El roce de tu cuerpo.

Uso: Tools/py/.venv/bin/python Probes/P5b-guitarra/drums/diagnose.py
Activaciones con el puerto PyTorch de ADTOF (paridad con DrumTranscriber, ADR-016) y, por golpe de charles (42) y
de platos (49): activaciones de ambas columnas, rasgos del stem (caída a -20 dB de la banda >3 kHz, centroide,
3-6 kHz frente a >8 kHz), relación con la rejilla de Beat This! de la app y con el bombo, y series regulares.
Salidas: Temp/p5b/drums/roce_act.npy, roce_spec.npy, roce_hits.json, roce_features.csv; resumen por stdout.
"""
import csv
import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfiltfilt, fftconvolve

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "Probes" / "P4-modelos" / "adtof"))
import ad_common as C  # noqa: E402

SONG = Path.home() / "Music/ToneForge/El roce de tu cuerpo - Platero Y Tu"
OUT = ROOT / "Temp" / "p5b" / "drums"
OUT.mkdir(parents=True, exist_ok=True)
HOP = 44  # ~1 ms


def env_db(x, win=220):
    p = np.maximum(fftconvolve(x.astype(np.float64) ** 2, np.ones(win) / win, mode="same"), 0.0)
    return 20 * np.log10(np.sqrt(p[::HOP]) + 1e-9)


def band(x, lo=None, hi=None):
    if lo and hi:
        sos = butter(4, [lo, hi], btype="bandpass", fs=sr, output="sos")
    elif lo:
        sos = butter(4, lo, btype="highpass", fs=sr, output="sos")
    else:
        sos = butter(4, hi, btype="lowpass", fs=sr, output="sos")
    return sosfiltfilt(sos, x)


act_p = OUT / "roce_act.npy"
spec = C.features(SONG / "stems" / "drums.wav")[:, :, 0]
np.save(OUT / "roce_spec.npy", spec.astype(np.float32))
if act_p.exists():
    act = np.load(act_p)
else:
    import torch
    m = C.load_torch()
    with torch.no_grad():
        act = m(torch.from_numpy(spec[:, :, None].astype(np.float32))[None]).numpy()[0]
    np.save(act_p, act.astype(np.float32))
hits = C.pick(act.astype(np.float32))
(OUT / "roce_hits.json").write_text(json.dumps({k: v.tolist() for k, v in hits.items()}))
print("golpes por clase:", {k: len(v) for k, v in hits.items()})

x, sr = sf.read(str(SONG / "stems" / "drums.wav"), dtype="float32", always_2d=True)
x = x.mean(axis=1)
print("stem a", sr, "Hz")
e_hi = env_db(band(x, lo=3000.0))
n_fft = 2048
win = np.hanning(n_fft)
freqs = np.fft.rfftfreq(n_fft, 1 / sr)

an = json.loads((SONG / "cache" / "analysis.json").read_text())["analysis"]["beats"]
beats = np.array(an["beats"])
downs = np.array(an["downbeats"])
eighths = np.sort(np.concatenate([beats, (beats[:-1] + beats[1:]) / 2]))
kick = hits["kick"]
snare = hits["snare"]


def feats(t):
    f = int(round(t * C.FPS))
    w = act[max(0, f - 2):f + 3]
    i = int(round(t * sr / HOP))
    seg = e_hi[i:i + 40]
    pk = i + int(np.argmax(seg))
    peak = e_hi[pk]
    below = np.flatnonzero(e_hi[pk:pk + 1500] < peak - 20)
    decay = (float(below[0]) if len(below) else 1500.0) * HOP / sr * 1000
    s0 = int(t * sr)
    fr = x[s0:s0 + n_fft]
    if len(fr) < n_fft:
        fr = np.pad(fr, (0, n_fft - len(fr)))
    mag = np.abs(np.fft.rfft(fr * win)) ** 2
    cen = float((freqs * mag).sum() / (mag.sum() + 1e-12))
    e36 = mag[(freqs >= 3000) & (freqs < 6000)].sum()
    e8 = mag[freqs >= 8000].sum()
    db = np.abs(downs - t).min() if len(downs) else 9
    eb = np.abs(eighths - t).min()
    bb = np.abs(beats - t).min()
    return dict(t=t, a_hh=float(w[:, 3].max()), a_cy=float(w[:, 4].max()), decay_ms=decay, centroid=cen,
                r36_8_db=float(10 * np.log10((e36 + 1e-12) / (e8 + 1e-12))),
                on_down=bool(db <= 0.04), on_beat=bool(bb <= 0.04), on_eighth=bool(eb <= 0.04),
                with_kick=bool(np.abs(kick - t).min() <= 0.03) if len(kick) else False,
                with_snare=bool(np.abs(snare - t).min() <= 0.03) if len(snare) else False)


rows = []
for name in ("hihat", "cymbal"):
    for t in hits[name]:
        r = feats(float(t))
        r["cls"] = name
        rows.append(r)
rows.sort(key=lambda r: r["t"])
# series: IOI con el golpe anterior/siguiente de la misma clase (platos) y de charles+platos
for name in ("cymbal",):
    ts = np.array([r["t"] for r in rows if r["cls"] == name])
    rs = [r for r in rows if r["cls"] == name]
    for k, r in enumerate(rs):
        r["ioi_prev"] = float(ts[k] - ts[k - 1]) if k > 0 else 9.0
        r["ioi_next"] = float(ts[k + 1] - ts[k]) if k + 1 < len(ts) else 9.0
with open(OUT / "roce_features.csv", "w", newline="") as fh:
    keys = ["t", "cls", "a_hh", "a_cy", "decay_ms", "centroid", "r36_8_db", "on_down", "on_beat", "on_eighth",
            "with_kick", "with_snare", "ioi_prev", "ioi_next"]
    w = csv.DictWriter(fh, keys)
    w.writeheader()
    for r in rows:
        w.writerow({k: r.get(k, "") for k in keys})


def summ(rs, label):
    if not rs:
        print(label, "vacío")
        return
    a = lambda k: np.array([r[k] for r in rs], float)  # noqa: E731
    q = lambda v: "p10 %.3g p50 %.3g p90 %.3g" % tuple(np.percentile(v, [10, 50, 90]))  # noqa: E731
    print(f"{label} n={len(rs)}")
    print("  a_hh", q(a("a_hh")), "| a_cy", q(a("a_cy")))
    print("  decay_ms", q(a("decay_ms")), "| centroid", q(a("centroid")), "| r36_8_db", q(a("r36_8_db")))
    print("  %% en compás %.0f, en pulso %.0f, en corchea %.0f, con bombo %.0f, con caja %.0f" % tuple(
        100 * a(k).mean() for k in ("on_down", "on_beat", "on_eighth", "with_kick", "with_snare")))


hh = [r for r in rows if r["cls"] == "hihat"]
cy = [r for r in rows if r["cls"] == "cymbal"]
summ(hh, "charles")
summ(cy, "platos")
ratio = np.array([r["a_hh"] / max(r["a_cy"], 1e-6) for r in cy])
print("platos: a_hh/a_cy hist (0,.1,.25,.5,1,2,inf):", np.histogram(ratio, [0, .1, .25, .5, 1, 2, 1e9])[0].tolist())
print("platos con a_hh>=0.22 (también charles):", int(sum(r["a_hh"] >= 0.22 for r in cy)))
iso = np.array([min(r["ioi_prev"], r["ioi_next"]) for r in cy])
print("platos: IOI mínimo con otro plato (s) hist (0,.13,.2,.3,.4,.6,1,inf):",
      np.histogram(iso, [0, .13, .2, .3, .4, .6, 1, 1e9])[0].tolist())
ser = [r for r, m in zip(cy, iso) if m < 0.4]
isol = [r for r, m in zip(cy, iso) if m >= 0.4]
summ(ser, "platos en serie (IOI<0,4 s)")
summ(isol, "platos aislados (IOI>=0,4 s)")
