"""Común a la prueba ADTOF (P4 A4b, transcripción de batería).

Modelo: puerto PyTorch xavriley/ADTOF-pytorch (Frame_RNN de Zehren et al.), clonado en out/repo (sin instalar).
mir_eval, pyloudnorm y mido están en Tools/py/requirements.txt. pretty_midi (que importa el puerto) necesita
pkg_resources: se sustituye
por un módulo vacío y el MIDI se escribe con mido.
"""
from __future__ import annotations

import hashlib
import logging
import re
import sys
import time
import traceback
import types
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
P4 = HERE.parent
ROOT = P4.parent.parent
REPO = OUT / "repo"
REPO_COMMIT = "85c192e78f716ea0b111cc8a5ee4a8f6a3a4f8a9"
WEIGHTS = REPO / "src" / "adtof_pytorch" / "data" / "adtof_frame_rnn_pytorch_weights.pth"
WEIGHTS_SHA = "1bc986e596ec47ba0b44916f87cd4a39f0b2bec23596df3fb5d0e87749217320"
GUARD = P4 / "common" / "guard.py"
PROGRESS = ROOT / "Temp" / "p4-progress.txt"
SONGS = ["T1", "T2", "T3"]
RAW = ROOT / "Probes" / "testaudio" / "out" / "raw"
TESTAUDIO = ROOT / "Probes" / "testaudio" / "out"
BEATS = P4 / "beat_this" / "out" / "beats" / "torch"

for p in (REPO / "src", P4 / "common"):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))
_pm = types.ModuleType("pretty_midi")
_pm.PrettyMIDI = object                       # solo para la anotación de tipo del puerto; no se usa
sys.modules.setdefault("pretty_midi", _pm)

SR = 44100
FPS = 100
LABELS = [35, 38, 47, 42, 49]                 # salida del modelo, en este orden
NAMES = ["kick", "snare", "tom", "hihat", "cymbal"]
THRESHOLDS = [0.22, 0.24, 0.32, 0.22, 0.30]   # FRAME_RNN_THRESHOLDS del puerto (los del ADTOF original)
PIECES = ["kick", "snare", "hihat"]           # las que se miden
TOL = 0.05                                    # ±50 ms
FID_TOL = 0.01                                # ±10 ms para fidelidad Core ML frente a PyTorch


def stem_path(song: str) -> Path:
    return P4 / "bs_roformer_sw" / "out" / "conv" / "coremlpub_cpu_gpu" / song / "drums.wav"


def setup_log(name: str) -> logging.Logger:
    (OUT / "logs").mkdir(parents=True, exist_ok=True)
    log = logging.getLogger(name)
    log.setLevel(logging.INFO)
    if not log.handlers:
        h = logging.FileHandler(OUT / "logs" / f"{name}.log")
        h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        log.addHandler(h)

    def hook(et, ev, tb):
        log.error("EXCEPCIÓN:\n%s", "".join(traceback.format_exception(et, ev, tb)))
        sys.__excepthook__(et, ev, tb)
    sys.excepthook = hook
    return log


def progress(paso: str, tema: str, via: str, resultado: str) -> None:
    with open(PROGRESS, "a") as f:
        f.write(f"{time.strftime('%H:%M')} {paso} · {tema} · {via} · {resultado}\n")


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


# ---------- modelo (puerto) ----------
def features(path: Path) -> np.ndarray:
    """(T, 84, 1) float32: log10(1 + filtro log 12 bandas/oct de |STFT 2048, hop 441, hann|), mono 44,1 kHz."""
    from adtof_pytorch.audio import process_audio_file
    spec, _ = process_audio_file(str(path))
    return spec


def load_torch():
    import contextlib
    import io
    import adtof_pytorch as A
    m = A.create_frame_rnn_model(A.calculate_n_bins())
    with contextlib.redirect_stdout(io.StringIO()):
        A.load_pytorch_weights(m, str(WEIGHTS), strict=True)
    return m.eval()


def pick(act: np.ndarray) -> dict[str, np.ndarray]:
    """act (T, 5) → tiempos (s) por pieza, con el pico del puerto (madmom NotePeakPicking reimplementado)."""
    from adtof_pytorch.post_processing import PeakPicker
    res = PeakPicker(thresholds=THRESHOLDS, fps=FPS).pick(act[None], labels=LABELS)[0]
    return {n: np.asarray(res[l], dtype=np.float64) for n, l in zip(NAMES, LABELS)}


def save_hits(hits: dict[str, np.ndarray], d: Path) -> None:
    d.mkdir(parents=True, exist_ok=True)
    for n, t in hits.items():
        np.savetxt(d / f"{n}.txt", np.asarray(t), fmt="%.4f")


def load_hits(d: Path, names=NAMES) -> dict[str, np.ndarray]:
    out = {}
    for n in names:
        p = d / f"{n}.txt"
        if p.exists():
            out[n] = np.atleast_1d(np.loadtxt(p, ndmin=1))
    return out


def write_midi(hits: dict[str, np.ndarray], path: Path, dur: float = 0.1) -> None:
    import mido
    tpb, tempo = 480, 500000                          # 120 BPM → 1 tick = 1/960 s
    ev = []
    for n, l in zip(NAMES, LABELS):
        for t in hits.get(n, []):
            ev.append((float(t), 1, l))
            ev.append((float(t) + dur, 0, l))
    ev.sort(key=lambda e: (e[0], e[1]))
    mid = mido.MidiFile(ticks_per_beat=tpb)
    tr = mido.MidiTrack()
    mid.tracks.append(tr)
    tr.append(mido.MetaMessage("set_tempo", tempo=tempo, time=0))
    last = 0
    for t, on, l in ev:
        tick = int(round(t * tpb * 1e6 / tempo))
        tr.append(mido.Message("note_on", channel=9, note=l, velocity=100 if on else 0, time=tick - last))
        last = tick
    path.parent.mkdir(parents=True, exist_ok=True)
    mid.save(str(path))


def prf(ref: np.ndarray, est: np.ndarray, win: float = TOL) -> tuple[float, float, float]:
    """(P, R, F) con mir_eval.onset.f_measure."""
    import mir_eval
    if len(ref) == 0 and len(est) == 0:
        return 1.0, 1.0, 1.0
    if len(ref) == 0 or len(est) == 0:
        return 0.0, 0.0, 0.0
    f, p, r = mir_eval.onset.f_measure(np.sort(ref), np.sort(est), window=win)
    return p, r, f


def matched_offsets(ref: np.ndarray, est: np.ndarray, win: float = TOL) -> np.ndarray:
    import mir_eval
    if len(ref) == 0 or len(est) == 0:
        return np.zeros(0)
    ref, est = np.sort(ref), np.sort(est)
    m = mir_eval.util.match_events(ref, est, win)
    return np.array([est[j] - ref[i] for i, j in m])


def raw_tracks(song: str) -> dict[str, list[Path]]:
    """Pistas sueltas de referencia por pieza (mismas reglas de nombre que testaudio/prepare.py)."""
    files = sorted((RAW / song).glob("*.wav"))
    rx = {"kick": r"kick", "snare": r"snare", "hihat": r"hihat|hi-hat", "tom": r"tom"}  # tom: solo para fugas
    return {k: [f for f in files if re.search(r, f.stem.lower())] for k, r in rx.items()}
