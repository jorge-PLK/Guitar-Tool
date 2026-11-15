"""Piezas compartidas de la prueba BS-RoFormer SW: rutas, descarga, carga del modelo,
núcleo sin STFT (lo que se convierte), STFT/iSTFT en numpy (lo que hará Swift con Accelerate)
y troceado con solape idéntico al demix() oficial de MSST."""
from __future__ import annotations

import hashlib
import logging
import subprocess
import sys
import urllib.request
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
REPO = ROOT.parents[2]
TESTAUDIO = REPO / "Probes" / "testaudio" / "out"
MSST = OUT / "msst"
WEIGHTS = OUT / "weights"
sys.path.insert(0, str(ROOT.parent / "common"))

MSST_URL = "https://github.com/ZFTurbo/Music-Source-Separation-Training.git"
MSST_COMMIT = "1f700c386e0dd763fe0a57242bb9420dce987354"
# El repo original jarredou/BS-ROFO-SW-Fixed ya no es público (401). Espejo con los mismos hashes LFS
# (verificado también en cdjmix1991/bandsplit-roformer-sw-by-jarredou).
HF = "https://huggingface.co/enerjazzer/BS-ROFO-SW-Fixed/resolve/main/"
CKPT = WEIGHTS / "BS-Rofo-SW-Fixed.ckpt"
CKPT_SHA256 = "24e7d35ee9c64415673d3fd33e06a67cac2c103c5df6267ba1576459c775916e"
CFG = WEIGHTS / "BS-Rofo-SW-Fixed.yaml"

SR = 44100
N_FFT, HOP, WIN = 2048, 512, 2048
N_FREQ = N_FFT // 2 + 1                     # 1025
CHUNK = 588800                              # config.audio.chunk_size
N_FRAMES = 1 + CHUNK // HOP                 # 1151 (torch.stft center=True)
NUM_OVERLAP = 2                             # config.inference.num_overlap
STEMS = ["bass", "drums", "other", "vocals", "guitar", "piano"]  # orden de salida del modelo


def setup_log(name: str) -> logging.Logger:
    OUT.mkdir(parents=True, exist_ok=True)
    log = logging.getLogger(name)
    log.setLevel(logging.INFO)
    if not log.handlers:
        h = logging.FileHandler(OUT / f"{name}.log")
        h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        log.addHandler(h)
    return log


def _sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def ensure_assets(log: logging.Logger) -> None:
    if not MSST.exists():
        subprocess.run(["git", "clone", MSST_URL, str(MSST)], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(MSST), "fetch", "--depth", "1", "origin", MSST_COMMIT],
                   check=False, capture_output=True)
    subprocess.run(["git", "-C", str(MSST), "checkout", "-q", MSST_COMMIT], check=False, capture_output=True)
    WEIGHTS.mkdir(parents=True, exist_ok=True)
    for p in (CFG, CKPT):
        if not p.exists():
            log.info("descargando %s", p.name)
            urllib.request.urlretrieve(HF + p.name, p)
    got = _sha256(CKPT)
    if got != CKPT_SHA256:
        raise RuntimeError(f"sha256 del checkpoint no coincide: {got}")
    log.info("assets ok (msst %s, ckpt sha256 ok)", MSST_COMMIT[:8])


# ONNX publicado por terceros (export MIT de elicwhite/bs-roformer-web; pesos = rehost de jarredou, sin licencia)
PUB_URL = "https://huggingface.co/elicwhite/bs-roformer-sw-6stem-onnx/resolve/main/bs_roformer_sw_6stem_fp32.onnx"
PUB = OUT / "onnx_pub" / "bs_roformer_sw_6stem_fp32.onnx"
PUB_SHA256 = "224f5f54a7ff9ff0e487aabca0a365d94513d51a6cdb7778152f2371716f2b68"
PUB_CHUNK = 176400                          # trazado a 4 s -> T = 345 tramas


def ensure_onnx_pub(log: logging.Logger) -> Path:
    PUB.parent.mkdir(parents=True, exist_ok=True)
    if not PUB.exists():
        log.info("descargando ONNX publicado")
        urllib.request.urlretrieve(PUB_URL, PUB)
    got = _sha256(PUB)
    if got != PUB_SHA256:
        raise RuntimeError(f"sha256 del ONNX publicado no coincide: {got}")
    return PUB


def load_model(log: logging.Logger):
    """Modelo original de MSST (BSRoformer) en eval, FP32, CPU. Devuelve (model, config)."""
    import torch
    ensure_assets(log)
    if str(MSST) not in sys.path:
        sys.path.insert(0, str(MSST))
    from utils.settings import get_model_from_config
    model, config = get_model_from_config("bs_roformer", str(CFG))
    sd = torch.load(CKPT, map_location="cpu", weights_only=True)
    if isinstance(sd, dict) and "state_dict" in sd:
        sd = sd["state_dict"]
    missing, unexpected = model.load_state_dict(sd, strict=False)
    log.info("load_state_dict: missing=%d unexpected=%d", len(missing), len(unexpected))
    if missing or unexpected:
        raise RuntimeError(f"pesos incompatibles: {missing[:5]} {unexpected[:5]}")
    model.eval()
    return model, config


# --- núcleo convertible ------------------------------------------------------

def make_core(model, n_frames: int = N_FRAMES):
    """nn.Module: spec (2, 1025, n_frames, 2) [canal, frec, trama, re/im] -> (12, 1025, 1151, 2)
    [stem*2+canal, frec, trama, re/im] = espectro de cada stem ya enmascarado (con DC a 0).
    Mismo cálculo que BSRoformer.forward entre torch.stft y torch.istft."""
    import torch
    from torch import nn

    m = model
    assert not m.skip_connection and all(len(b) == 2 for b in m.layers)

    # Rotary con tablas cos/sin precalculadas para las longitudes fijas (1151 tramas, 62 bandas).
    # Mismo cálculo que rotary_embedding_torch; evita su caché con .item(), que rompe coremltools 9
    # (TypeError en _cast con numpy 2.x).
    def patch_rotary(emb, n):
        with torch.no_grad():
            freqs = emb.forward(emb.get_seq_pos(n, device="cpu", dtype=torch.float32), seq_len=n)
        cos, sin = freqs.cos(), freqs.sin()                                  # (n, dim_head)
        d = cos.shape[-1]

        def rot(t, seq_dim=None, offset=0, scale=None, inverse=False):
            x = t.reshape(t.shape[0], t.shape[1], n, d // 2, 2)
            rh = torch.stack((-x[..., 1], x[..., 0]), dim=-1).reshape(t.shape[0], t.shape[1], n, d)
            return t * cos + rh * sin

        emb.rotate_queries_or_keys = rot

    patch_rotary(m.layers[0][0].layers[0][0].rotary_embed, n_frames)
    patch_rotary(m.layers[0][1].layers[0][0].rotary_embed, len(m.band_split.dim_inputs))

    class Core(nn.Module):
        def __init__(self):
            super().__init__()
            self.m = m
            dc = torch.ones(1, N_FREQ * m.audio_channels, 1, 1)               # eje (f s)
            dc[:, :m.audio_channels] = 0.0 if m.zero_dc else 1.0
            self.register_buffer("dc", dc)

        def forward(self, spec):
            s, f, t, c = spec.shape                                   # 2, 1025, T, 2
            x = spec.permute(1, 0, 2, 3).reshape(1, f * s, t, c)      # b (f s) t c
            stft_repr = x
            x = x.permute(0, 2, 1, 3).reshape(1, t, f * s * c)        # b t (f c)
            x = self.m.band_split(x)                                  # b t nb d
            for time_tr, freq_tr in self.m.layers:
                nb, d = x.shape[2], x.shape[3]
                x = x.permute(0, 2, 1, 3).reshape(nb, t, d)
                x = time_tr(x)
                x = x.reshape(1, nb, t, d).permute(0, 2, 1, 3).reshape(t, nb, d)
                x = freq_tr(x)
                x = x.reshape(1, t, nb, d)
            x = self.m.final_norm(x)
            mask = torch.stack([fn(x) for fn in self.m.mask_estimators], dim=1)  # b n t (f c)
            n = mask.shape[1]
            # rango <= 5 en todo el grafo (límite de Core ML)
            mask = mask.reshape(n, t, f * s, c).permute(0, 2, 1, 3)              # n (f s) t c
            sr_, si_ = stft_repr[..., 0:1], stft_repr[..., 1:2]                   # 1 (f s) t 1
            mr, mi = mask[..., 0:1], mask[..., 1:2]
            out = torch.cat([sr_ * mr - si_ * mi, sr_ * mi + si_ * mr], dim=-1)   # n (f s) t c
            out = out * self.dc
            out = out.reshape(n, f, s, t, c).permute(0, 2, 1, 3, 4).reshape(n * s, f, t, c)
            return out

    return Core().eval()


# --- STFT / iSTFT (equivalentes a torch.stft/istft con center=True, reflect, hann periódica) ---

_WINDOW = (0.5 - 0.5 * np.cos(2 * np.pi * np.arange(WIN) / WIN)).astype(np.float64)


def stft_np(x: np.ndarray) -> np.ndarray:
    """x (C, N) -> (C, 1025, 1 + N//512, 2) float32."""
    pad = N_FFT // 2
    xp = np.pad(x.astype(np.float64), ((0, 0), (pad, pad)), mode="reflect")
    T = 1 + x.shape[-1] // HOP
    idx = np.arange(N_FFT)[None, :] + HOP * np.arange(T)[:, None]
    frames = xp[:, idx] * _WINDOW                                  # C T n_fft
    S = np.fft.rfft(frames, n=N_FFT, axis=-1)                      # C T F
    S = np.transpose(S, (0, 2, 1))
    return np.stack([S.real, S.imag], axis=-1).astype(np.float32)


def istft_np(S: np.ndarray, length: int) -> np.ndarray:
    """S (K, 1025, T, 2) -> (K, length) float32 (OLA con hann, normalizado por sum(w²))."""
    Z = S[..., 0].astype(np.float64) + 1j * S[..., 1].astype(np.float64)
    K, F, T = Z.shape
    frames = np.fft.irfft(np.transpose(Z, (0, 2, 1)), n=N_FFT, axis=-1) * _WINDOW   # K T n_fft
    total = N_FFT + HOP * (T - 1)
    y = np.zeros((K, total))
    env = np.zeros(total)
    w2 = _WINDOW ** 2
    for t in range(T):
        a = t * HOP
        y[:, a:a + N_FFT] += frames[:, t]
        env[a:a + N_FFT] += w2
    pad = N_FFT // 2
    y = y[:, pad:pad + length]
    env = env[pad:pad + length]
    return (y / np.where(env > 1e-11, env, 1.0)).astype(np.float32)


# --- troceado idéntico a utils.model_utils.demix (modo generic) ---------------

def window_array(size: int, fade: int) -> np.ndarray:
    w = np.ones(size, dtype=np.float32)
    w[-fade:] = np.linspace(1, 0, fade, dtype=np.float32)
    w[:fade] = np.linspace(0, 1, fade, dtype=np.float32)
    return w


def demix_np(mix: np.ndarray, run_chunk, n_out: int = len(STEMS), chunk: int = CHUNK,
             num_overlap: int = NUM_OVERLAP) -> np.ndarray:
    """mix (2, N). run_chunk((2, chunk)) -> (n_out, 2, chunk). Devuelve (n_out, 2, N).
    Con chunk/num_overlap por defecto = configuración oficial; otro chunk = mismo esquema, trozo distinto."""
    step = chunk // num_overlap
    fade, border = chunk // 10, chunk - step
    L0 = mix.shape[-1]
    padded = L0 > 2 * border and border > 0
    if padded:
        mix = np.pad(mix, ((0, 0), (border, border)), mode="reflect")
    L = mix.shape[-1]
    win = window_array(chunk, fade)
    result = np.zeros((n_out,) + mix.shape, dtype=np.float32)
    counter = np.zeros(L, dtype=np.float32)
    i = 0
    while i < L:
        part = mix[:, i:i + chunk]
        n = part.shape[-1]
        if n < chunk:
            mode = "reflect" if n > chunk // 2 else "constant"
            part = np.pad(part, ((0, 0), (0, chunk - n)), mode=mode)
        y = run_chunk(part)
        w = win.copy()
        if i == 0:
            w[:fade] = 1
        if i + step >= L:
            w[-fade:] = 1
        result[..., i:i + n] += y[..., :n] * w[:n]
        counter[i:i + n] += w[:n]
        i += step
    result /= counter                                         # en sitio: sin copias de la canción entera
    np.nan_to_num(result, copy=False)
    return result[..., border:-border] if padded else result
