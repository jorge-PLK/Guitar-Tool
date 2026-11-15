"""Piezas compartidas de la prueba BTC (acordes, vocabulario grande de 170 clases): rutas, descarga del repo
oficial con los pesos, carga del modelo, preproceso (CQT log, igual que utils/mir_eval_modules.py del repo),
ventanas de 108 tramas y paso de tramas a .lab (copia literal de la lógica de test.py).

Lo que habría que portar a Swift: to_mono_22k (Accelerate/AVAudioConverter), cqt_features (CQT de librosa:
144 bins, 24 por octava, fmin C1, hop 2048, por trozos de 10 s), normalize_windows y frames_to_lab."""
from __future__ import annotations

import hashlib
import logging
import subprocess
import sys
import time
import traceback
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
REPO = ROOT.parents[2]
TESTAUDIO = REPO / "Probes" / "testaudio" / "out"
BSR_STEMS = REPO / "Probes" / "P4-modelos" / "bs_roformer_sw" / "out" / "conv" / "coremlpub_cpu_gpu"
STEMS_NO_VOX_DRUMS = ["bass", "guitar", "other", "piano"]
PROGRESS = REPO / "Temp" / "p4-progress.txt"
GUARD = ROOT.parent / "common" / "guard.py"
TEMAS = ["T1", "T2", "T3"]

# Repo oficial: código MIT; pesos en test/ (entrenados con datos no comerciales: uso personal, no redistribuir).
BTC_URL = "https://github.com/jayg996/BTC-ISMIR19.git"
BTC_COMMIT = "2682317be668032e6e4b269ded36adaa2ad57df0"
BTC_DIR = OUT / "repo"
CKPT = BTC_DIR / "test" / "btc_model_large_voca.pt"
CKPT_SHA256 = "1673d23f8f9a55ae7f9e8b80a51da616debb22675b8d8b67ea6ce0ef37b0ab51"
MLPACKAGE = OUT / "coreml" / "BTC_large_voca_{prec}.mlpackage"

SR = 22050            # mp3.song_hz
INST_LEN = 10.0       # mp3.inst_len: la CQT se calcula por trozos de 10 s
HOP = 2048
N_BINS, BPO = 144, 24
T = 108               # model.timestep (tramas por ventana)
N_FEAT = 144
N_CHORDS = 170
FRAME_S = INST_LEN / T  # 0,0926 s por trama (lo que test.py llama feature_per_second)

ROOTS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
QUALITIES = ["min", "maj", "dim", "aug", "min6", "maj6", "min7", "minmaj7", "maj7", "7", "dim7", "hdim7",
             "sus2", "sus4"]


def idx2voca() -> list[str]:
    """Igual que utils.mir_eval_modules.idx2voca_chord: índice = raíz*14 + calidad; 168 = X, 169 = N."""
    out = []
    for i in range(168):
        r, q = ROOTS[i // 14], QUALITIES[i % 14]
        out.append(r if i % 14 == 1 else f"{r}:{q}")
    return out + ["X", "N"]


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


def progress(msg: str) -> None:
    PROGRESS.parent.mkdir(parents=True, exist_ok=True)
    with open(PROGRESS, "a") as f:
        f.write(f"{time.strftime('%H:%M')} P4-BTC: {msg}\n")


def _sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def ensure_assets(log: logging.Logger) -> None:
    if not BTC_DIR.exists():
        log.info("clonando %s", BTC_URL)
        subprocess.run(["git", "clone", "-q", BTC_URL, str(BTC_DIR)], check=True)
    subprocess.run(["git", "-C", str(BTC_DIR), "checkout", "-q", BTC_COMMIT], check=True)
    sha = _sha256(CKPT)
    if sha != CKPT_SHA256:
        raise RuntimeError(f"sha256 del checkpoint distinto: {sha}")
    log.info("repo BTC en %s (commit %s), ckpt sha256 ok", BTC_DIR, BTC_COMMIT)


def load_torch_model():
    """Devuelve (modelo BTC en eval, mean, std). Config = run_config.yaml con large_voca (170 acordes)."""
    import torch
    sys.path.insert(0, str(BTC_DIR))
    import yaml
    if not hasattr(np, "float"):
        np.float = float  # transformer_modules._gen_timing_signal usa np.float (quitado en numpy ≥ 1.24)
    from btc_model import BTC_model  # noqa: E402
    # utils.hparams usa yaml.load sin Loader (PyYAML ≥ 6 lo rechaza): se lee el YAML directamente.
    cfg = yaml.safe_load(open(BTC_DIR / "run_config.yaml"))["model"]
    cfg["num_chords"] = N_CHORDS
    model = BTC_model(config=cfg)
    # mean/std son escalares numpy (no admitidos con weights_only=True); el sha256 se verifica antes.
    if _sha256(CKPT) != CKPT_SHA256:
        raise RuntimeError("sha256 del checkpoint distinto")
    ck = torch.load(str(CKPT), map_location="cpu", weights_only=False)
    model.load_state_dict(ck["model"])
    model.eval()
    return model, float(ck["mean"]), float(ck["std"])


def load_input(tema: str, kind: str) -> tuple[list[np.ndarray], int]:
    """Lee el audio (fuera del tiempo medido). kind: 'stems' (bass+guitar+other+piano de BS-RoFormer Core ML)
    o 'mix'. Devuelve lista de arrays (canales, muestras) float32 y sr."""
    import soundfile as sf
    paths = ([BSR_STEMS / tema / f"{s}.wav" for s in STEMS_NO_VOX_DRUMS] if kind == "stems"
             else [TESTAUDIO / tema / "mix.wav"])
    xs, srs = [], set()
    for p in paths:
        x, sr = sf.read(str(p), dtype="float32", always_2d=True)
        xs.append(x.T.copy())
        srs.add(sr)
    assert len(srs) == 1, srs
    return xs, srs.pop()


def to_mono_22k(xs: list[np.ndarray], sr: int) -> np.ndarray:
    """Suma de stems, a mono (media de canales, como librosa.to_mono) y remuestreo a 22050 (soxr_hq, el
    res_type por defecto de librosa.load)."""
    import librosa
    n = min(x.shape[-1] for x in xs)
    y = np.sum([x[:, :n] for x in xs], axis=0).mean(axis=0)
    return librosa.resample(y, orig_sr=sr, target_sr=SR).astype(np.float32)


def cqt_features(wav: np.ndarray) -> np.ndarray:
    """Copia de audio_file_to_features: CQT por trozos de 10 s concatenados, log(|C| + 1e-6). Sale (tramas, 144)."""
    import librosa
    step = int(SR * INST_LEN)
    parts, cur = [], 0
    while len(wav) > cur + step:
        parts.append(librosa.cqt(wav[cur:cur + step], sr=SR, n_bins=N_BINS, bins_per_octave=BPO, hop_length=HOP))
        cur += step
    parts.append(librosa.cqt(wav[cur:], sr=SR, n_bins=N_BINS, bins_per_octave=BPO, hop_length=HOP))
    feat = np.concatenate(parts, axis=1)
    return np.log(np.abs(feat) + 1e-6).T.astype(np.float32)


def normalize_windows(feat: np.ndarray, mean: float, std: float) -> tuple[np.ndarray, int]:
    """(feat - mean)/std, relleno con ceros hasta múltiplo de 108 (siempre añade num_pad ≥ 1, como test.py).
    Sale (n_ventanas, 108, 144) float32 y num_pad."""
    f = (feat - mean) / std
    num_pad = T - (f.shape[0] % T)
    f = np.pad(f, ((0, num_pad), (0, 0)), mode="constant", constant_values=0)
    return f.reshape(-1, T, N_FEAT).astype(np.float32), num_pad


def frames_to_lab(pred: np.ndarray, num_pad: int, names: list[str]) -> list[str]:
    """pred (n_ventanas, 108) int. Lógica literal de test.py (incluido el corte en la primera trama de relleno)."""
    lines, start, prev = [], 0.0, None
    n_inst = pred.shape[0]
    for t in range(n_inst):
        for i in range(T):
            p = int(pred[t, i])
            if t == 0 and i == 0:
                prev = p
                continue
            if p != prev:
                lines.append("%.3f %.3f %s\n" % (start, FRAME_S * (T * t + i), names[prev]))
                start = FRAME_S * (T * t + i)
                prev = p
            if t == n_inst - 1 and i + num_pad == T:
                if start != FRAME_S * (T * t + i):
                    lines.append("%.3f %.3f %s\n" % (start, FRAME_S * (T * t + i), names[prev]))
                break
    return lines


def patch_masks_fp16_safe(model) -> int:
    """Cambia los -inf de las máscaras de atención (hacia delante/atrás) por -1e4, seguro en FP16 y en el ANE.
    En FP32 el resultado es el mismo (exp(-1e4) = 0). Devuelve cuántas máscaras se tocaron."""
    import torch
    n = 0
    for m in model.modules():
        bm = getattr(m, "bias_mask", None)
        if isinstance(bm, torch.Tensor):
            m.bias_mask = torch.where(torch.isinf(bm), torch.full_like(bm, -1e4), bm)
            n += 1
    return n
