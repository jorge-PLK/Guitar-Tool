"""Fase 5b: rítmica escrita desde los acordes BTC de la app con el ritmo de los ataques del stem.

Acordes: cache/analysis.json (segmentos BTC; N/X = nada). Formas (reglas fijas, iguales en todo el tema):
  full  forma de StudyKit/ChordShapes.swift portada tal cual (abiertas explícitas; si no, plantilla de cejilla tipo E o
        tipo A, la de traste más alto menor = posición más baja).
  p5    quinta: raíz + 5.ª en las cuerdas graves, raíz en la 6.ª o la 5.ª, la de traste más bajo (posición más baja).
  p58   raíz + 5.ª + octava, misma regla.
Ataques (fuentes):
  gt    ataques de Guitab E25 (notas agrupadas a 30 ms).
  bp    ataques de Basic Pitch con puerta: fuera las notas cuyo ataque cae con el stem < −60 dBFS (RMS).
  flux  flujo espectral tipo SuperFlux (Böck y Widmer 2013: mel 138 bandas, lag 2, max_size 3, hop 256), parámetros
        por defecto, sin ajustar a la referencia; misma puerta de −60 dBFS.
  sufijo _q: ataques cuantizados a semicorcheas de la rejilla de pulsos de la app.
Cada golpe dura hasta el siguiente ataque, el cambio de acorde o la primera trama < −60 dBFS. Sordinas (palm mute): no
se detectan (sin regla barata fiable): todo golpe lleva la forma completa de la variante.

Escribe Temp/p5b/<tema>/<stem>_btc_<forma>_<ataques>[_q].json (formato de run.py, con cuerda 1 = Mi agudo y traste).
Uso: Tools/py/.venv/bin/python Probes/P5b-guitarra/btc_rhythm.py [--stems guitar_L,guitar_R,guitar] [--check VARIANTE]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run as R  # noqa: E402

import librosa  # noqa: E402

OPEN_MIDI = [40, 45, 50, 55, 59, 64]  # 6.ª..1.ª
QORDER = ["min", "maj", "dim", "aug", "min6", "maj6", "min7", "minmaj7", "maj7", "dom7", "dim7", "hdim7", "sus2", "sus4"]
GATE_RMS = 10 ** (-60 / 20)

# ---- ChordShapes.swift (StudyKit), 6.ª..1.ª, None = muteada
OPEN = {
    (0, "maj"): [None, 3, 2, 0, 1, 0], (0, "dom7"): [None, 3, 2, 3, 1, 0], (0, "maj7"): [None, 3, 2, 0, 0, 0],
    (0, "sus2"): [None, 3, 0, 0, 1, 3],
    (2, "maj"): [None, None, 0, 2, 3, 2], (2, "min"): [None, None, 0, 2, 3, 1], (2, "dim"): [None, None, 0, 1, 3, 1],
    (2, "min6"): [None, None, 0, 2, 0, 1], (2, "maj6"): [None, None, 0, 2, 0, 2], (2, "min7"): [None, None, 0, 2, 1, 1],
    (2, "minmaj7"): [None, None, 0, 2, 2, 1], (2, "maj7"): [None, None, 0, 2, 2, 2], (2, "dom7"): [None, None, 0, 2, 1, 2],
    (2, "dim7"): [None, None, 0, 1, 0, 1], (2, "hdim7"): [None, None, 0, 1, 1, 1], (2, "sus2"): [None, None, 0, 2, 3, 0],
    (2, "sus4"): [None, None, 0, 2, 3, 3],
    (5, "maj7"): [None, None, 3, 2, 1, 0],
    (7, "maj"): [3, 2, 0, 0, 0, 3], (7, "dom7"): [3, 2, 0, 0, 0, 1], (7, "maj7"): [3, 2, 0, 0, 0, 2],
    (7, "maj6"): [3, 2, 0, 0, 0, 0],
}
E_FORM = {
    "maj": [0, 2, 2, 1, 0, 0], "min": [0, 2, 2, 0, 0, 0], "dim": [0, 1, 2, 0, None, None], "aug": [0, 3, 2, 1, 1, 0],
    "min6": [0, 2, 2, 0, 2, 0], "maj6": [0, 2, 2, 1, 2, 0], "min7": [0, 2, 0, 0, 0, 0], "minmaj7": [0, 2, 1, 0, 0, 0],
    "maj7": [0, 2, 1, 1, 0, 0], "dom7": [0, 2, 0, 1, 0, 0], "dim7": [0, 1, 2, 0, 2, None], "hdim7": [0, 1, 0, 0, None, None],
    "sus4": [0, 2, 2, 2, 0, 0],
}
A_FORM = {
    "maj": [None, 0, 2, 2, 2, 0], "min": [None, 0, 2, 2, 1, 0], "dim": [None, 0, 1, 2, 1, None],
    "aug": [None, 0, 3, 2, 2, 1], "min6": [None, 0, 2, 2, 1, 2], "maj6": [None, 0, 2, 2, 2, 2],
    "min7": [None, 0, 2, 0, 1, 0], "minmaj7": [None, 0, 2, 1, 1, 0], "maj7": [None, 0, 2, 1, 2, 0],
    "dom7": [None, 0, 2, 0, 2, 0], "dim7": [None, 0, 1, 2, 1, 2], "hdim7": [None, 0, 1, 0, 1, None],
    "sus2": [None, 0, 2, 2, 0, 0], "sus4": [None, 0, 2, 2, 3, 0],
}


def chordshape(root: int, q: str):
    if (root, q) in OPEN:
        return OPEN[(root, q)]
    cands = []
    if q in E_FORM:
        f0 = (root - 4) % 12
        cands.append([None if x is None else x + f0 for x in E_FORM[q]])
    if q in A_FORM:
        f0 = (root - 9) % 12
        cands.append([None if x is None else x + f0 for x in A_FORM[q]])
    return min(cands, key=lambda s: max(x for x in s if x is not None))  # min estable = el primero en empate (Swift)


def power(root: int, octave: bool):
    fe, fa = (root - 4) % 12, (root - 9) % 12
    if fe <= fa:  # raíz en la 6.ª
        s = [fe, fe + 2, fe + 2 if octave else None, None, None, None]
    else:         # raíz en la 5.ª
        s = [None, fa, fa + 2, fa + 2 if octave else None, None, None]
    return s


def shape_for(idx: int, voicing: str):
    if idx >= 168:
        return None
    root, qi = divmod(idx, 14)
    if voicing == "full":
        return chordshape(root, QORDER[qi])
    return power(root, voicing == "p58")


def shape_notes(shape):
    return [(6 - i, f, OPEN_MIDI[i] + f) for i, f in enumerate(shape) if f is not None]  # (cuerda 1=aguda, traste, midi)


# ---- ataques

def frame_rms(y):
    return librosa.feature.rms(y=y, frame_length=1024, hop_length=256)[0]


def onsets_from_notes(notes, rms):
    t = np.array(sorted(n["onset"] for n in notes))
    t = t[[rms[min(int(x * R.SR / 256), len(rms) - 1)] >= GATE_RMS for x in t]] if len(t) else t
    out = []
    for x in t:
        if not out or x - out[-1] > 0.03:
            out.append(float(x))
    return np.array(out)


def flux_onsets(y, rms):
    env = librosa.onset.onset_strength(y=y, sr=R.SR, hop_length=256, n_mels=138, fmin=27.5, fmax=16000.0, lag=2,
                                       max_size=3)
    # guitarra distorsionada = dinámica comprimida: con la normalización global de librosa unos pocos picos (entradas
    # tras silencio) tapan el resto (145 ataques en el tema). Regla fija: contraste local (máximo en 2 s) y espera de
    # 35 ms; elegida una vez, sin mirar la referencia.
    from scipy.ndimage import maximum_filter1d
    env = env / (maximum_filter1d(env, size=int(2.0 * R.SR / 256)) + 1e-9)
    fr = librosa.onset.onset_detect(onset_envelope=env, sr=R.SR, hop_length=256, units="frames", backtrack=False,
                                    normalize=False, wait=3, pre_max=3, post_max=3, pre_avg=9, post_avg=9, delta=0.07)
    fr = [f for f in fr if rms[min(f, len(rms) - 1)] >= GATE_RMS]
    return librosa.frames_to_time(np.array(fr, dtype=int), sr=R.SR, hop_length=256)


def quantize(t, beats):
    b = np.asarray(beats)
    step = np.median(np.diff(b))
    ext = np.concatenate([[b[0] - 4 * step + i * step for i in range(4)], b, [b[-1] + (i + 1) * step for i in range(16)]])
    sub = np.concatenate([np.linspace(ext[i], ext[i + 1], 4, endpoint=False) for i in range(len(ext) - 1)])
    q = sub[np.abs(sub[None, :] - np.asarray(t)[:, None]).argmin(1)] if len(t) else t
    return np.unique(q)


# ---- golpes

def strikes(onsets, segs, rms, dur, voicing):
    starts = np.array([s["start"] for s in segs])
    notes = []
    for i, t in enumerate(onsets):
        j = max(int(np.searchsorted(starts, t, side="right")) - 1, 0)
        shp = shape_for(segs[j]["index"], voicing)
        if shp is None:
            continue
        end = min(onsets[i + 1] if i + 1 < len(onsets) else dur, segs[j]["end"])
        f0, f1 = int(t * R.SR / 256), int(end * R.SR / 256)
        quiet = np.nonzero(rms[f0 + 1:f1] < GATE_RMS)[0]
        if len(quiet):
            end = (f0 + 1 + quiet[0]) * 256 / R.SR
        if end - t < 0.02:
            continue
        for s, f, p in shape_notes(shp):
            notes.append({"onset": float(t), "offset": float(end), "pitch": int(p), "amp": 0.8, "string": s, "fret": int(f)})
    return notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--song", type=Path, default=R.DEFAULT_SONG)
    ap.add_argument("--stems", default="guitar_L,guitar_R,guitar")
    ap.add_argument("--check", default="", help="variante para la que escribir CHECK_ (p. ej. p5_gt_q)")
    a = ap.parse_args()
    song = a.song.expanduser()
    tag = R.song_tag(song)
    d = R.OUT / tag
    an = json.loads((song / "cache" / "analysis.json").read_text())["analysis"]
    segs, beats = an["chords"]["segments"], an["beats"]["beats"]
    names = []
    for stem in a.stems.split(","):
        y = R.load_stem(song / "stems" / f"{stem}.wav")
        rms = frame_rms(y)
        dur = len(y) / R.SR
        src = {"gt": onsets_from_notes(json.loads((d / f"{stem}_guitab_e25.json").read_text())["notes"], rms),
               "bp": onsets_from_notes(json.loads((d / f"{stem}_basic_pitch.json").read_text())["notes"], rms),
               "flux": flux_onsets(y, rms)}
        for k in list(src):
            src[k + "_q"] = quantize(src[k], beats)
        for voicing in ("full", "p5", "p58"):
            for k, on in src.items():
                name = f"btc_{voicing}_{k}"
                notes = strikes(on, segs, rms, dur, voicing)
                (d / f"{stem}_{name}.json").write_text(json.dumps({"notes": notes, "infer_s": 0.0,
                                                                   "info": {"onsets": len(on)}}))
                if stem == a.stems.split(",")[0]:
                    names.append(name)
                if a.check and name == f"btc_{a.check}":
                    R.write_check(notes, y, tag, stem, name, d)
        print(stem, {k: len(v) for k, v in src.items()})
    print(",".join(names))


if __name__ == "__main__":
    main()
