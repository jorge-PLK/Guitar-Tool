"""Piezas compartidas de la prueba Beat This! (pulso y compás, CPJKU/beat_this, MIT): rutas, descarga del repo y
del checkpoint final0, preproceso oficial (mono → 22050 Hz con soxr → log-mel), troceado oficial (1500 tramas,
borde 6, keep_first), postproceso oficial «minimal» (el de por defecto; DBN desactivado) y métricas.

Lo que habría que portar a Swift: to_mono_22k (media de canales + remuestreo a 22050; AVAudioConverter),
log_mel (STFT 1024/441 hann, center reflect, |X|/sqrt(sum w²), banco mel slaney 128 bandas 30-11000 Hz sin
normalizar, log1p(1000·x); vDSP), split/aggregate (troceado con borde) y postprocess_minimal (máximo local en
±3 tramas, logit > 0, fusión de picos adyacentes, downbeat al pulso más cercano)."""
from __future__ import annotations

import hashlib
import json
import logging
import subprocess
import sys
import time
import traceback
import urllib.request
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
REPO = ROOT.parents[2]
TESTAUDIO = REPO / "Probes" / "testaudio" / "out"
PROGRESS = REPO / "Temp" / "p4-progress.txt"
GUARD = ROOT.parent / "common" / "guard.py"
TEMAS = ["T1", "T2", "T3"]
REF_BPM = {"T1": 125.0, "T2": 74.0, "T3": 110.0}  # Readme de Cambridge MT

# Código y pesos: MIT.
BT_URL = "https://github.com/CPJKU/beat_this.git"
BT_COMMIT = "b95c8ab0c58c2d9fcfd40508ae8dffbc05ac4f5c"
BT_DIR = OUT / "repo"
CKPT_URL = "https://cloud.cp.jku.at/public.php/dav/files/7ik4RrBKTS273gp/final0.ckpt"
# El servidor oficial de JKU daba HTTP 500 el 15/11/2026; dos espejos de HF con el mismo sha256 (LFS):
# teamup-tech/Beat-This-weights y Audante/beat-this-final0.
CKPT_MIRROR = ("https://huggingface.co/teamup-tech/Beat-This-weights/resolve/"
               "4afbe376535aaab71b76ae2ca2d7c16b08877321/final0.ckpt")
CKPT = OUT / "ckpt" / "final0.ckpt"
CKPT_SHA256 = "8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331"

# Core ML comunitario (schism-audio/beat-this-coreml no existe en HF: 401). Sustituto: MIT, final0, FP32.
COMM_REPO = "jessengatai/supracut-beat-this"
COMM_SHA = "33fe1a5a3edb44f6063d71e549d8ea774a41eaa1"
COMM_ZIP_SHA256 = "0464b7497165e82cf68e94bfd3aecf989cb88be3c6ba0ca4ae3f3657cafcd4b5"
COMM_DIR = OUT / "hf_supracut"
COMM_MODEL = COMM_DIR / "BeatThis.mlmodelc"

ONNX_REPO = "musetric/beat-this-onnx"
ONNX_SHA = "25308706dda545c0d5950065bb0604ad71bcf1f5"
ONNX_DIR = OUT / "hf_musetric"

SR = 22050
FPS = 50
CHUNK = 1500   # tramas (30 s)
BORDER = 6
N_MELS = 128
TOL = 0.020    # ±20 ms para la fidelidad


def setup_log(name: str) -> logging.Logger:
    OUT.mkdir(parents=True, exist_ok=True)
    log = logging.getLogger(name)
    log.setLevel(logging.INFO)
    if not log.handlers:
        h = logging.FileHandler(OUT / f"{name}.log")
        h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        log.addHandler(h)

    def hook(et, ev, tb):
        log.error("EXCEPCIÓN:\n%s", "".join(traceback.format_exception(et, ev, tb)))
        sys.__excepthook__(et, ev, tb)
    sys.excepthook = hook
    return log


def progress(paso: str, tema: str, via: str, resultado: str) -> None:
    PROGRESS.parent.mkdir(parents=True, exist_ok=True)
    with open(PROGRESS, "a") as f:
        f.write(f"{time.strftime('%H:%M')} {paso} · {tema} · {via} · {resultado}\n")


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def download(url: str, dst: Path, log: logging.Logger) -> None:
    if dst.exists():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    log.info("descargando %s", url)
    tmp = dst.with_suffix(dst.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "python-urllib"})
    with urllib.request.urlopen(req) as r, open(tmp, "wb") as f:
        while b := r.read(1 << 20):
            f.write(b)
    tmp.rename(dst)


def ensure_repo(log: logging.Logger) -> None:
    if not (BT_DIR / ".git").exists():
        subprocess.run(["git", "clone", "-q", BT_URL, str(BT_DIR)], check=True)
    subprocess.run(["git", "-C", str(BT_DIR), "checkout", "-q", BT_COMMIT], check=True)
    if str(BT_DIR) not in sys.path:
        sys.path.insert(0, str(BT_DIR))
    try:
        download(CKPT_URL, CKPT, log)
    except Exception as e:
        log.warning("servidor oficial falló (%s); uso el espejo", e)
        download(CKPT_MIRROR, CKPT, log)
    sha = sha256(CKPT)
    log.info("repo beat_this commit %s · ckpt final0 sha256 %s", BT_COMMIT, sha)
    if CKPT_SHA256 and sha != CKPT_SHA256:
        raise RuntimeError(f"sha256 del checkpoint distinto: {sha}")


def ensure_comm(log: logging.Logger) -> None:
    if COMM_MODEL.exists():
        return
    z = COMM_DIR / "BeatThis.mlmodelc.zip"
    download(f"https://huggingface.co/{COMM_REPO}/resolve/{COMM_SHA}/BeatThis.mlmodelc.zip", z, log)
    if sha256(z) != COMM_ZIP_SHA256:
        raise RuntimeError("sha256 del zip comunitario distinto")
    subprocess.run(["unzip", "-q", "-o", str(z), "-d", str(COMM_DIR)], check=True)


def load_torch_model():
    import torch
    from beat_this.inference import load_model
    torch.set_grad_enabled(False)
    return load_model(str(CKPT), "cpu")


# ---------- preproceso (oficial) ----------
def load_audio(tema: str) -> tuple[np.ndarray, int]:
    import soundfile as sf
    return sf.read(TESTAUDIO / tema / "mix.wav", dtype="float64")


def to_mono_22k(sig: np.ndarray, sr: int) -> np.ndarray:
    """Igual que Audio2Frames.signal2spect: media de canales y soxr a 22050."""
    import soxr
    if sig.ndim == 2:
        sig = sig.mean(1)
    if sr != SR:
        sig = soxr.resample(sig, in_rate=sr, out_rate=SR)
    return sig


_MEL = None


def log_mel(mono22: np.ndarray):
    """LogMelSpect oficial (torchaudio) → tensor torch (T, 128) float32."""
    global _MEL
    import torch
    from beat_this.preprocessing import LogMelSpect
    if _MEL is None:
        _MEL = LogMelSpect(device="cpu")
    with torch.inference_mode():
        return _MEL(torch.tensor(mono22, dtype=torch.float32))


# ---------- troceado + agregado (oficial) con un predictor cualquiera ----------
def predict_frames(spect, predict_chunk) -> tuple[np.ndarray, np.ndarray, int]:
    """predict_chunk(np (1,T,128) float32) -> (beat (T,), downbeat (T,)) logits. Usa split_piece y
    aggregate_prediction del repo (chunk 1500, borde 6, keep_first). Devuelve logits por trama y nº de trozos."""
    import torch
    from beat_this.inference import aggregate_prediction, split_piece
    chunks, starts = split_piece(spect, CHUNK, border_size=BORDER, avoid_short_end=True)
    preds = []
    for c in chunks:
        b, d = predict_chunk(c.unsqueeze(0).numpy().astype(np.float32))
        preds.append({"beat": torch.as_tensor(np.asarray(b, dtype=np.float32).reshape(-1)),
                      "downbeat": torch.as_tensor(np.asarray(d, dtype=np.float32).reshape(-1))})
    b, d = aggregate_prediction(preds, starts, spect.shape[0], CHUNK, BORDER, "keep_first", "cpu")
    return b.numpy(), d.numpy(), len(chunks)


def postprocess(beat_logits: np.ndarray, downbeat_logits: np.ndarray):
    import torch
    from beat_this.model.postprocessor import Postprocessor
    pp = Postprocessor(type="minimal", fps=FPS)
    b, d = pp(torch.as_tensor(beat_logits), torch.as_tensor(downbeat_logits))
    return np.asarray(b, dtype=np.float64), np.asarray(d, dtype=np.float64)


# ---------- métricas ----------
def tempo(beats: np.ndarray) -> float:
    return float(60.0 / np.median(np.diff(beats))) if len(beats) > 2 else float("nan")


def tempo_fine(beats: np.ndarray) -> float:
    """Informativo: 60 / media de los intervalos a ±20 % de la mediana (la mediana va a saltos de 20 ms: a 50 fps
    un intervalo de 27 tramas es 111,1 BPM y uno de 28, 107,1; la media de muchos intervalos no tiene ese salto)."""
    if len(beats) < 3:
        return float("nan")
    d = np.diff(beats)
    m = np.median(d)
    d = d[(d > 0.8 * m) & (d < 1.2 * m)]
    return float(60.0 / d.mean())


def tempo_verdict(bpm: float, ref: float) -> str:
    if abs(bpm - ref) <= 1:
        return "ok"
    for k, name in ((2, "doble"), (0.5, "mitad")):
        if abs(bpm - ref * k) <= 1 * k:
            return f"octava ({name})"
    return "fallo"


def match_pct(ref: np.ndarray, est: np.ndarray, tol: float = TOL) -> float:
    """% de instantes de ref con un instante de est a ±tol."""
    if len(ref) == 0:
        return 100.0 if len(est) == 0 else 0.0
    if len(est) == 0:
        return 0.0
    est = np.sort(est)
    i = np.clip(np.searchsorted(est, ref), 1, len(est) - 1)
    dist = np.minimum(np.abs(est[i - 1] - ref), np.abs(est[i] - ref))
    return float(100.0 * np.mean(dist <= tol + 1e-9))


def bar_histogram(beats: np.ndarray, downbeats: np.ndarray) -> dict[int, int]:
    """Nº de pulsos entre downbeats consecutivos → cuántas veces."""
    idx = np.searchsorted(beats, downbeats)
    h: dict[int, int] = {}
    for n in np.diff(idx):
        h[int(n)] = h.get(int(n), 0) + 1
    return dict(sorted(h.items()))


def save_times(path: Path, t: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{x:.4f}\n" for x in t))


def load_times(path: Path) -> np.ndarray:
    return np.loadtxt(path, ndmin=1) if path.exists() and path.stat().st_size else np.array([])


def save_json(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=1, ensure_ascii=False))
