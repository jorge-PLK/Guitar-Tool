"""Común a convert.py y compare.py: Mel-Band RoFormer "Lead_Rhythm_Guitar" (pesos anónimos de HF, openrail,
uso personal) como núcleo sin STFT, con el mismo contrato que el BS-RoFormer SW de la app (StemKit):

  entrada  `spec` [1, 2050, 301, 2] float32 = STFT del trozo, fila 2·f + canal, (re, im) en el último eje
  salida   `mask` [1, 1, 2050, 301, 2]      = máscara compleja ya promediada entre bandas (mismo layout)

Fuera del modelo (Swift/Accelerate, aquí numpy): STFT n_fft 2048, hop 441, Hann periódica, center=True con
reflect; producto complejo spec·mask; bin 0 (DC) a cero; iSTFT normalizada por Σw²; trozos de 132300
muestras (3 s, 301 tramas) con num_overlap 1 y fundido lineal de 13230 como `demix` de MSST.

El scatter_add_ complejo de MelBandRoformer.forward (promedio de las máscaras de bandas solapadas) se
sustituye por K gathers con índices fijos + suma + división por el número de bandas de cada frecuencia:
mismo orden de suma que scatter_add (por índice de origen creciente), sin complejos ni scatter.
SEGURIDAD: checkpoint solo con torch.load(weights_only=True); YAML con SafeLoader + constructor de tupla."""
from __future__ import annotations

import hashlib
import logging
import sys
import traceback
from pathlib import Path

import numpy as np
import yaml

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
W = OUT / "weights"
WT = HERE.parents[2]                                  # raíz del worktree
MSST = HERE.parent / "guitar_models/out/msst"         # commit 1f700c38
sys.path.insert(0, str(HERE.parent / "common"))

CKPT = "model_mel_band_roformer_ep_72_sdr_3.2232.ckpt"
CKPT_SHA = "b3c47bca33609ca1ba0bb2d2076410bfd1eb941b051b72afc1f3e24d12b17eef"
CFG = "config_mel_band_roformer_Lead_Rhythm_Guitar.yaml"
HF_COMMIT = "c3ac4e45eb290b3ed32ec9c387295021a52c5916"

SR = 44100
N_FFT = 2048
HOP = 441
F = N_FFT // 2 + 1                  # 1025
CHUNK = 132300                      # config.audio.chunk_size (3 s)
NUM_OVERLAP = 1                     # config.inference.num_overlap
FRAMES = 1 + CHUNK // HOP           # 301
PACKAGE = "LeadRhythmMelRoformer_{}.mlpackage"
FIXED_MTIME = 1_700_000_000         # zip reproducible


def setup_log(name: str) -> logging.Logger:
    OUT.mkdir(parents=True, exist_ok=True)
    log = logging.getLogger(name)
    log.setLevel(logging.INFO)
    h = logging.FileHandler(OUT / f"{name}.log")
    h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(h)

    def hook(t, v, tb):
        log.error("".join(traceback.format_exception(t, v, tb)))
        print(f"ERROR {t.__name__}: {v} (traza en out/{name}.log)")
    sys.excepthook = hook
    return log


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


class TupleSafeLoader(yaml.SafeLoader):
    pass


TupleSafeLoader.add_constructor("tag:yaml.org,2002:python/tuple",
                                lambda ld, node: tuple(ld.construct_sequence(node)))


def load_model(log: logging.Logger):
    """MelBandRoformer FP32 en CPU con los pesos verificados (sha256) y casado estricto."""
    import torch
    p = W / CKPT
    got = sha256(p)
    if got != CKPT_SHA:
        raise RuntimeError(f"sha256 del checkpoint no coincide: {got}")
    sd = torch.load(p, map_location="cpu", weights_only=True)
    sd = {k.removeprefix("module."): v.float() for k, v in sd.items()}
    cfg = yaml.load(open(W / CFG), Loader=TupleSafeLoader)
    sys.path.insert(0, str(MSST))
    sys.dont_write_bytecode = True
    from models.bs_roformer.mel_band_roformer import MelBandRoformer
    model = MelBandRoformer(**dict(cfg["model"]))
    model.load_state_dict(sd, strict=True)
    model.eval()
    a = cfg["audio"]
    assert (a["chunk_size"], a["hop_length"], a["n_fft"], cfg["inference"]["num_overlap"]) == (CHUNK, HOP, N_FFT, NUM_OVERLAP)
    log.info("modelo cargado: sha256 OK, %d tensores, %.1f M parámetros, torch %s", len(sd),
             sum(v.numel() for v in sd.values()) / 1e6, torch.__version__)
    return model, cfg


def make_core(model, n_frames: int = FRAMES):
    """nn.Module: spec (1, 2·F, T, 2) -> mask (1, 1, 2·F, T, 2). Mismo cálculo que MelBandRoformer.forward
    entre torch.stft y el producto stft_repr·masks_averaged."""
    import torch
    from torch import nn

    m = model
    assert not m.skip_connection and all(len(b) == 2 for b in m.layers) and len(m.mask_estimators) == 1

    def patch_rotary(emb, n):
        # tablas cos/sin fijas: evita la caché con .item() de rotary_embedding_torch (rompe coremltools 9)
        with torch.no_grad():
            freqs = emb.forward(emb.get_seq_pos(n, device="cpu", dtype=torch.float32), seq_len=n)
        cos, sin = freqs.cos(), freqs.sin()
        d = cos.shape[-1]

        def rot(t, seq_dim=None, offset=0, scale=None, inverse=False):
            x = t.reshape(t.shape[0], t.shape[1], n, d // 2, 2)
            rh = torch.stack((-x[..., 1], x[..., 0]), dim=-1).reshape(t.shape[0], t.shape[1], n, d)
            return t * cos + rh * sin

        emb.rotate_queries_or_keys = rot

    n_bands = len(m.band_split.dim_inputs)
    patch_rotary(m.layers[0][0].layers[0][0].rotary_embed, n_frames)
    patch_rotary(m.layers[0][1].layers[0][0].rotary_embed, n_bands)

    fi = m.freq_indices.cpu().numpy()                  # (Frep,) índices en el eje (f s)
    rows = 2 * F
    occ = [[] for _ in range(rows)]
    for src, dst in enumerate(fi):
        occ[dst].append(src)                           # orden creciente de origen = orden de scatter_add
    K = max(len(o) for o in occ)
    idx = np.zeros((K, rows), dtype=np.int64)
    valid = np.zeros((K, rows), dtype=np.float32)
    for r, o in enumerate(occ):
        for k in range(K):
            idx[k, r] = o[min(k, len(o) - 1)]
            valid[k, r] = 1.0 if k < len(o) else 0.0
    denom = np.repeat(m.num_bands_per_freq.cpu().numpy(), 2).astype(np.float32)   # (f r)
    assert (denom == np.array([len(o) for o in occ])).all()

    class Core(nn.Module):
        def __init__(self):
            super().__init__()
            self.m = m
            self.K = K
            self.register_buffer("freq_indices", torch.from_numpy(fi.astype(np.int64)))
            self.register_buffer("idx", torch.from_numpy(idx))
            self.register_buffer("valid", torch.from_numpy(valid).reshape(K, rows, 1, 1))
            self.register_buffer("denom", torch.from_numpy(np.maximum(denom, 1e-8)).reshape(rows, 1, 1))

        def forward(self, spec):
            t = spec.shape[2]
            x = torch.index_select(spec, 1, self.freq_indices)           # 1 Frep t c
            frep = x.shape[1]
            x = x.permute(0, 2, 1, 3).reshape(1, t, frep * 2)             # b t (f c)
            x = self.m.band_split(x)                                      # b t nb d
            for time_tr, freq_tr in self.m.layers:
                nb, d = x.shape[2], x.shape[3]
                x = x.permute(0, 2, 1, 3).reshape(nb, t, d)
                x = time_tr(x)
                x = x.reshape(1, nb, t, d).permute(0, 2, 1, 3).reshape(t, nb, d)
                x = freq_tr(x)
                x = x.reshape(1, t, nb, d)
            mask = self.m.mask_estimators[0](x)                           # 1 t (Frep c)
            mask = mask.reshape(t, frep, 2).permute(1, 0, 2)              # Frep t c
            acc = torch.index_select(mask, 0, self.idx[0])
            for k in range(1, self.K):
                acc = acc + torch.index_select(mask, 0, self.idx[k]) * self.valid[k]
            acc = acc / self.denom                                        # (f s) t c
            return acc.reshape(1, 1, acc.shape[0], t, 2)

    log_info = {"Frep": int(len(fi)), "K": K, "bands": n_bands}
    return Core().eval(), log_info


# --- STFT / iSTFT equivalentes a torch.stft/istft (center=True, reflect, Hann periódica) ---------------

_WIN = (0.5 - 0.5 * np.cos(2 * np.pi * np.arange(N_FFT) / N_FFT)).astype(np.float64)


def stft_spec(x: np.ndarray) -> np.ndarray:
    """x (2, N) -> spec (1, 2·F, 1 + N//HOP, 2) float32, fila 2·f + canal."""
    pad = N_FFT // 2
    xp = np.pad(x.astype(np.float64), ((0, 0), (pad, pad)), mode="reflect")
    T = 1 + x.shape[-1] // HOP
    idx = np.arange(N_FFT)[None, :] + HOP * np.arange(T)[:, None]
    S = np.fft.rfft(xp[:, idx] * _WIN, n=N_FFT, axis=-1)              # s T F
    S = np.transpose(S, (2, 0, 1))                                    # F s T
    out = np.stack([S.real, S.imag], axis=-1).reshape(1, 2 * F, T, 2)
    return out.astype(np.float32)


def istft_spec(S: np.ndarray, length: int) -> np.ndarray:
    """S (2·F, T, 2) (fila 2·f + canal) -> (2, length) float32."""
    Z = S[..., 0].astype(np.float64) + 1j * S[..., 1].astype(np.float64)
    Z = Z.reshape(F, 2, -1).transpose(1, 2, 0)                        # s T F
    T = Z.shape[1]
    frames = np.fft.irfft(Z, n=N_FFT, axis=-1) * _WIN
    total = N_FFT + HOP * (T - 1)
    y = np.zeros((2, total))
    env = np.zeros(total)
    for t in range(T):
        a = t * HOP
        y[:, a:a + N_FFT] += frames[:, t]
        env[a:a + N_FFT] += _WIN ** 2
    pad = N_FFT // 2
    y, env = y[:, pad:pad + length], env[pad:pad + length]
    return (y / np.where(env > 1e-11, env, 1.0)).astype(np.float32)


def apply_mask(spec: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """spec (1, 2F, T, 2), mask (1, 1, 2F, T, 2) -> espectro enmascarado (2F, T, 2) con DC a 0 (zero_dc)."""
    s = spec[0].astype(np.float32)
    mk = mask.reshape(2 * F, -1, 2).astype(np.float32)
    out = np.empty_like(s)
    out[..., 0] = s[..., 0] * mk[..., 0] - s[..., 1] * mk[..., 1]
    out[..., 1] = s[..., 0] * mk[..., 1] + s[..., 1] * mk[..., 0]
    out[:2] = 0.0
    return out


def run_chunk_np(part: np.ndarray, predict_mask) -> np.ndarray:
    """part (2, CHUNK) -> lead (2, CHUNK). predict_mask(spec) -> mask (1, 1, 2F, T, 2)."""
    spec = stft_spec(part)
    return istft_spec(apply_mask(spec, predict_mask(spec)), part.shape[-1])


def window_array(size: int, fade: int) -> np.ndarray:
    w = np.ones(size, dtype=np.float32)
    w[-fade:] = np.linspace(1, 0, fade, dtype=np.float32)
    w[:fade] = np.linspace(0, 1, fade, dtype=np.float32)
    return w


def demix_np(mix: np.ndarray, run_chunk, chunk: int = CHUNK, num_overlap: int = NUM_OVERLAP) -> np.ndarray:
    """utils.model_utils.demix (modo generic) con una sola salida: mix (2, N) -> (2, N)."""
    step = chunk // num_overlap
    fade, border = chunk // 10, chunk - step
    L0 = mix.shape[-1]
    padded = L0 > 2 * border and border > 0
    if padded:
        mix = np.pad(mix, ((0, 0), (border, border)), mode="reflect")
    L = mix.shape[-1]
    win = window_array(chunk, fade)
    result = np.zeros(mix.shape, dtype=np.float32)
    counter = np.zeros(L, dtype=np.float32)
    i = 0
    while i < L:
        part = mix[:, i:i + chunk]
        n = part.shape[-1]
        if n < chunk:
            part = np.pad(part, ((0, 0), (0, chunk - n)), mode="reflect" if n > chunk // 2 else "constant")
        y = run_chunk(part)
        w = win.copy()
        if i == 0:
            w[:fade] = 1
        if i + step >= L:
            w[-fade:] = 1
        result[:, i:i + n] += y[:, :n] * w[:n]
        counter[i:i + n] += w[:n]
        i += step
    with np.errstate(invalid="ignore", divide="ignore"):
        result /= counter
    np.nan_to_num(result, copy=False)
    return result[:, border:-border] if padded else result
