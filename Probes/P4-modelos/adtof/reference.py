"""Golpes de referencia de bombo, caja y charles a partir de las pistas sueltas de Cambridge MT.

Uso: Tools/py/.venv/bin/python Probes/P4-modelos/adtof/reference.py [--songs T1 T2 T3]
Por pieza: micro principal (primer fichero por nombre: Kick/KickIn, Snare/SnareUp, HiHat), filtro de banda
de fase cero, envolvente RMS (5 ms, salto 1 ms) en dB, novedad = subida positiva de la envolvente,
picos con librosa.util.peak_pick, y descarte de fugas por nivel relativo (pico del golpe frente al percentil 95
de la pista; umbral por pista en el valle del histograma entre -30 y -6 dB) y por comparación con los otros micros cercanos (si el golpe suena más fuerte, en términos
relativos, en el micro de otra pieza, es fuga de esa pieza).
Salida: out/ref/T*/{kick,snare,hihat}.txt y out/ref/ref_summary.json. Diagnóstico en out/logs/reference.log.
"""
import argparse
import json

import librosa
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfiltfilt, fftconvolve

import ad_common as C

BANDS = {"kick": (None, 120.0), "snare": (150.0, 2500.0), "hihat": (7000.0, None), "tom": (60.0, 600.0)}
MIN_GAP = {"kick": 0.06, "snare": 0.06, "hihat": 0.045, "tom": 0.06}   # s entre golpes de la misma pieza
LEAK_DB = 6.0      # fuga si en otro micro el golpe está ≥ N dB más alto (relativo a su p95) que en el propio
HOP = 44           # ~1 ms
# ventana RMS por pieza ≥ un periodo de la banda (con 5 ms el bombo filtrado a 120 Hz rizaba y la novedad
# perdía los dobles de semicorchea)
WIN = {"kick": 882, "snare": 441, "hihat": 220, "tom": 662}

ap = argparse.ArgumentParser()
ap.add_argument("--songs", nargs="*", default=C.SONGS)
a = ap.parse_args()
log = C.setup_log("reference")


def mono(p):
    x, sr = sf.read(str(p), dtype="float32", always_2d=True)
    assert sr == C.SR
    return x.mean(axis=1)


def band(x, lo, hi):
    if lo and hi:
        sos = butter(4, [lo, hi], btype="bandpass", fs=C.SR, output="sos")
    elif lo:
        sos = butter(4, lo, btype="highpass", fs=C.SR, output="sos")
    else:
        sos = butter(4, hi, btype="lowpass", fs=C.SR, output="sos")
    return sosfiltfilt(sos, x).astype(np.float32)


def env_db(x, win):
    p = np.maximum(fftconvolve(x.astype(np.float64) ** 2, np.ones(win) / win, mode="same"), 0.0)  # sin NaN
    e = 20 * np.log10(np.sqrt(p[::HOP]) + 1e-9)
    # suelo a 60 dB bajo el máximo: algunas pistas van con puerta (silencio digital) y la apertura desde -180 dB
    # daba picos de novedad enormes que robaban el pico al golpe real cercano
    return np.maximum(e, e.max() - 60.0)


def valley(rel, lo, hi):
    """Umbral por pista: el mínimo del histograma (1 dB, suavizado a 3 dB) de niveles relativos en [lo, hi];
    entre empates, el más cercano a -15 dB."""
    edges = np.arange(lo, hi + 1, 1.0)
    h = np.convolve(np.histogram(rel, bins=edges)[0], np.ones(3) / 3, mode="same")
    c = (edges[:-1] + edges[1:]) / 2
    cand = np.flatnonzero(h == h.min())
    return float(c[cand[np.argmin(np.abs(c[cand] + 15))]])


def candidates(e, gap):
    nov = np.maximum(0.0, np.diff(e, prepend=e[0]))
    nov = np.convolve(nov, np.ones(5), mode="same")          # subida acumulada en 5 ms
    w = int(gap * C.SR / HOP)
    pk = librosa.util.peak_pick(nov, pre_max=w, post_max=w, pre_avg=50, post_avg=10, delta=3.0, wait=w)
    return pk, nov


def peak_level(e, idx, span=40):
    return np.array([e[i:i + span].max() if i < len(e) else -180.0 for i in idx])


summary = {}
for song in a.songs:
    tracks = C.raw_tracks(song)
    log.info("== %s pistas: %s", song, {k: [p.name for p in v] for k, v in tracks.items()})
    envs, cands, levels, p95 = {}, {}, {}, {}
    for piece, files in tracks.items():
        if not files:
            log.info("%s %s: sin pista suelta → no se mide", song, piece)
            continue
        es = [env_db(band(mono(f), *BANDS[piece]), WIN[piece]) for f in (files if piece == "tom" else files[:1])]
        n_e = max(len(v) for v in es)
        e = np.max([np.pad(v, (0, n_e - len(v)), constant_values=-180.0) for v in es], axis=0)
        pk, nov = candidates(e, MIN_GAP[piece])
        lv = peak_level(e, pk)
        envs[piece], cands[piece], levels[piece] = e, pk, lv
        p95[piece] = float(np.percentile(lv, 95)) if len(lv) else 0.0
        rel = lv - p95[piece]
        hist, edges = np.histogram(rel, bins=np.arange(-60, 9, 3))
        log.info("%s %s (%s): %d candidatos; histograma nivel rel. p95 (3 dB desde -60): %s",
                 song, piece, files[0].name, len(pk), hist.tolist())
    out_d = C.OUT / "ref" / song
    out_d.mkdir(parents=True, exist_ok=True)
    summary[song] = {}
    for piece in envs:
        if piece == "tom":
            continue
        pk, lv = cands[piece], levels[piece]
        rel = lv - p95[piece]
        thr = valley(rel, -30.0, -6.0)
        keep = rel >= thr
        n_level = int((~keep).sum())
        # fuga: nivel relativo en los otros micros cercanos en el mismo instante
        leak = np.zeros(len(pk), bool)
        for other in envs:
            if other == piece:
                continue
            o_rel = peak_level(envs[other], pk) - p95[other]
            leak |= o_rel >= rel + LEAK_DB
        n_leak = int((keep & leak).sum())
        keep &= ~leak
        t = pk[keep] * HOP / C.SR
        np.savetxt(out_d / f"{piece}.txt", t, fmt="%.4f")
        dur = len(envs[piece]) * HOP / C.SR
        info = {"file": tracks[piece][0].name, "track_s": round(dur, 1), "thr_db": thr,
                "candidates": int(len(pk)), "drop_level": n_level, "drop_leak": n_leak, "hits": int(keep.sum()),
                "per_min": round(float(keep.sum() / dur * 60), 1)}
        # plausibilidad: % de golpes a ±30 ms de la rejilla (semicorcheas ∪ tresillos de corchea) de los pulsos de
        # Beat This! (referencia torch de A4a), y nivel del golpe más flojo aceptado
        bp = C.BEATS / f"{song}.beats.txt"
        if bp.exists() and len(t):
            b = np.loadtxt(bp)
            grid = np.concatenate([b[:-1] + k * np.diff(b) / q for q in (4, 3) for k in range(q)])
            d = np.abs(t[:, None] - grid[None, :]).min(axis=1)
            info["on_grid_pct"] = round(100 * float((d <= 0.03).mean()), 1)
            ioi = np.diff(t)
            info["ioi_min_ms"] = round(float(ioi.min() * 1000), 1) if len(ioi) else None
        # golpes por compás (compases de Beat This!), solo compases con algún golpe: la moda debe ser musical
        dp = C.BEATS / f"{song}.downbeats.txt"
        if dp.exists() and len(t):
            db = np.loadtxt(dp)
            cnt = np.histogram(t, bins=db)[0]
            cnt = cnt[cnt > 0]
            info["per_bar_mode"] = int(np.bincount(cnt).argmax())
            info["per_bar_hist"] = np.bincount(cnt).tolist()
        # sensibilidad del umbral: candidatos que no son fuga en los 6 dB por debajo del umbral
        info["near_below_thr"] = int(((rel < thr) & (rel >= thr - 6) & ~leak).sum())
        loose = (rel >= thr - 6) & ~leak                       # variante «floja» (umbral 6 dB más bajo), solo informativa
        np.savetxt(out_d / f"{piece}_loose.txt", pk[loose] * HOP / C.SR, fmt="%.4f")
        summary[song][piece] = info
        log.info("%s %s: %s", song, piece, info)
    # comprobación de desfase: correlación de la envolvente grave del bombo suelto con el stem de batería
    if "kick" in envs:
        for name, p in [("stem_bsroformer", C.stem_path(song)), ("mix", C.TESTAUDIO / song / "mix.wav")]:
            s = 10 ** (env_db(band(mono(p), *BANDS["kick"]), WIN["kick"]) / 20)     # envolvente lineal
            k = 10 ** (envs["kick"] / 20)
            n = min(len(s), len(k))
            ks, ss = k[:n] - k[:n].mean(), s[:n] - s[:n].mean()
            lags = range(-200, 201)
            cc = [float(np.dot(ks[max(0, -l):n - max(0, l)], ss[max(0, l):n - max(0, -l)])) for l in lags]
            lag_ms = list(lags)[int(np.argmax(cc))] * HOP / C.SR * 1000
            summary[song].setdefault("lag_ms", {})[name] = round(lag_ms, 1)
            log.info("%s desfase bombo suelto → %s: %.1f ms (positivo = %s va retrasado)", song, name, lag_ms, name)

(C.OUT / "ref" / "ref_summary.json").write_text(json.dumps(summary, indent=1))
for song, d in summary.items():
    print(song, {k: (v["hits"], v["thr_db"], v.get("on_grid_pct")) if isinstance(v, dict) and "hits" in v else v
                 for k, v in d.items()})
