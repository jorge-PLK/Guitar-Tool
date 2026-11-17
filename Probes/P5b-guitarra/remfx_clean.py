"""Fase 5b: quitar la distorsión del stem con RemFX (solo el modelo de distorsión) y transcribir el audio limpio.

Modelo: RemFX (github.com/mhrice/RemFx, código Apache-2.0), checkpoint demucs_distortion_aug.ckpt de Zenodo 8218621
(licencia de los pesos: CC no comercial → uso personal, no redistribuir). Es torchaudio.models.HDemucs(sources=["mixture"],
audio_channels=1, nfft=4096, channels=48) a 48 kHz mono (cfg/model/demucs.yaml, cfg/exp/distortion.yaml); no hace
falta instalar remfx ni sus dependencias: basta torchaudio del venv y las claves «model.model.*» del state_dict.
Preproceso como en su entrenamiento (remfx/datasets.py): trozos de 262 144 muestras (5,46 s) normalizados a −20 LUFS;
la salida se devuelve a la ganancia original del trozo. Solape del 25 % con ventana de Hann y suma normalizada.
Trozos en silencio digital: ceros.

Escribe Temp/p5b/<tema>/remfx/<stem>.wav (48 kHz), las notas <stem>_remfx_{basic_pitch,guitab_e25}.json (para
eval_reference.py --extra) y CHECK_<tema>_<stem>_remfx_estereo.wav (original izquierda, limpio derecha, primeros 60 s).
Uso (pesado: con guard.py): Tools/py/.venv/bin/python Probes/P5b-guitarra/remfx_clean.py --stems guitar_L
"""
import argparse
import hashlib
import json
import logging
import sys
import time
import traceback
import urllib.request
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run as R  # noqa: E402

SRC = R.OUT / "src" / "remfx"
CKPT = SRC / "demucs_distortion_aug.ckpt"
CKPT_URL = "https://zenodo.org/api/records/8218621/files/demucs_distortion_aug.ckpt/content"
CKPT_MD5 = "2bc547a66270d9b3a30a6e17f458e6f5"
SR48 = 48000
CHUNK = 262144
HOP = CHUNK * 3 // 4
LUFS = -20.0

log = logging.getLogger("p5b.remfx")
log.setLevel(logging.INFO)
log.propagate = False
_fh = logging.FileHandler(R.OUT / "remfx.log", mode="a")
_fh.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
log.addHandler(_fh)


def _excepthook(t, v, tb):
    log.error("".join(traceback.format_exception(t, v, tb)))
    print(f"ERROR: {t.__name__}: {v} (ver {R.OUT / 'remfx.log'})")


sys.excepthook = _excepthook


def fetch():
    SRC.mkdir(parents=True, exist_ok=True)
    if not CKPT.exists():
        tmp = CKPT.with_suffix(".part")
        req = urllib.request.Request(CKPT_URL, headers={"User-Agent": "python-urllib/3 model-eval"})
        with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
            while True:
                b = r.read(1 << 22)
                if not b:
                    break
                f.write(b)
        tmp.rename(CKPT)
    h = hashlib.md5()
    with open(CKPT, "rb") as f:
        for b in iter(lambda: f.read(1 << 22), b""):
            h.update(b)
    if h.hexdigest() != CKPT_MD5:
        sys.exit("md5 del checkpoint no coincide")


def load_model(device):
    import torch
    from torchaudio.models import HDemucs
    try:
        ck = torch.load(str(CKPT), map_location="cpu", weights_only=True)
        log.info("checkpoint cargado con weights_only=True")
    except Exception as e:  # hiperparámetros de Lightning con objetos no tensoriales
        log.info("weights_only=True falla (%s); md5 verificado frente a Zenodo → weights_only=False", str(e)[:200])
        ck = torch.load(str(CKPT), map_location="cpu", weights_only=False)
    sd = {k[len("model.model."):]: v for k, v in ck["state_dict"].items() if k.startswith("model.model.")}
    m = HDemucs(sources=["mixture"], audio_channels=1, nfft=4096, channels=48)
    missing, unexpected = m.load_state_dict(sd, strict=True), None
    log.info("HDemucs: %d tensores, %.1f M parámetros", len(sd), sum(p.numel() for p in m.parameters()) / 1e6)
    return m.to(device).eval()


def clean(y48, model, device):
    import pyloudnorm as pyln
    import torch
    meter = pyln.Meter(SR48)
    n = len(y48)
    starts = list(range(0, max(n - CHUNK, 0) + 1, HOP))
    if starts[-1] + CHUNK < n:
        starts.append(n - CHUNK if n > CHUNK else 0)
    out = np.zeros(n, np.float64)
    wsum = np.zeros(n, np.float64)
    win = np.hanning(CHUNK + 2)[1:-1] + 1e-3
    with torch.no_grad():
        for s in starts:
            x = y48[s:s + CHUNK]
            seg = np.zeros(CHUNK, np.float32)
            seg[:len(x)] = x
            if np.abs(seg).max() < 1e-5:
                y = np.zeros(CHUNK)
            else:
                lufs = meter.integrated_loudness(seg.astype(np.float64))
                g = 10 ** ((LUFS - lufs) / 20) if np.isfinite(lufs) else 1.0
                t = torch.from_numpy((seg * g).astype(np.float32))[None, None].to(device)
                y = model(t)[0, 0, 0].float().cpu().numpy() / g
            L = min(CHUNK, n - s)
            out[s:s + L] += y[:L] * win[:L]
            wsum[s:s + L] += win[:L]
    return (out / np.maximum(wsum, 1e-9)).astype(np.float32)


def main():
    import soundfile as sf
    import soxr
    import torch
    ap = argparse.ArgumentParser()
    ap.add_argument("--stems", default="guitar_L")
    ap.add_argument("--device", default="cpu")
    a = ap.parse_args()
    song = R.DEFAULT_SONG
    tag = R.song_tag(song)
    d = R.OUT / tag
    (d / "remfx").mkdir(parents=True, exist_ok=True)
    fetch()
    model = load_model(a.device)
    lines = []
    for stem in a.stems.split(","):
        x, sr = sf.read(str(song / "stems" / f"{stem}.wav"), dtype="float32", always_2d=True)
        y = x.mean(1)
        y48 = soxr.resample(y, sr, SR48, quality="HQ").astype(np.float32) if sr != SR48 else y
        torch.set_num_threads(max(torch.get_num_threads(), 1))
        t0 = time.perf_counter()
        yc = clean(y48, model, a.device)
        dt = time.perf_counter() - t0
        dur = len(y48) / SR48
        sf.write(str(d / "remfx" / f"{stem}.wav"), yc, SR48, subtype="FLOAT")
        msg = f"{stem}: {dur:.0f} s, {dt:.1f} s de RemFX en {a.device} = {dt / (dur / 60):.1f} s por minuto"
        log.info(msg)
        lines.append(msg)
        # CHECK_: original izquierda, limpio derecha, primeros 60 s
        k = 60 * SR48
        o, c = y48[:k], yc[:k]
        pk = max(np.abs(o).max(), np.abs(c).max()) + 1e-9
        sf.write(str(d / f"CHECK_{tag}_{stem}_remfx_estereo.wav"), np.stack([o / pk * 0.8, c / pk * 0.8], 1), SR48,
                 subtype="PCM_16")
        # transcripción del audio limpio (mismos corredores que run.py)
        y22 = soxr.resample(yc, SR48, R.SR, quality="HQ").astype(np.float32)
        for model_name in ("basic_pitch", "guitab_e25"):
            notes, t_inf, info = R.transcribe(model_name, y22, "cpu")
            (d / f"{stem}_remfx_{model_name}.json").write_text(json.dumps({"notes": notes, "infer_s": t_inf, "info": info}))
            lines.append(f"  {model_name}: {len(notes)} notas")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
