"""Candidatos de guitarra en su runtime original (PyTorch, código y demix() oficiales de MSST), sin convertir.

Uso (siempre bajo common/guard.py):
  run_torch.py <modelo> T1 [T2 T3] [--device cpu|mps]
  run_torch.py <modelo> --keys          # solo descarga y compara claves de pesos con el modelo
Modelos: mega53 (lumabeat/mvsep-mega53-guitar, BS-RoFormer, MIT)
         becruily (becruily/mel-band-roformer-guitar, Mel-Band RoFormer, sin licencia: uso personal)
Salida: out/sep/<modelo>/<T>/guitar.wav (+ timing.json); log en out/run_torch_<modelo>.log."""
import argparse
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
import yaml

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "common"))
from metrics import PeakMem, load_wav, save_wav  # noqa: E402

OUT = HERE / "out"
MAIN = Path("/Volumes/SSD Mac/Personales/Guitar Tool")
TESTAUDIO = MAIN / "Probes/testaudio/out"
MSST = OUT / "msst"
MSST_URL = "https://github.com/ZFTurbo/Music-Source-Separation-Training.git"
MSST_COMMIT = "1f700c386e0dd763fe0a57242bb9420dce987354"   # el mismo que la referencia BS-RoFormer SW

MODELS = {
    "mega53": {
        "type": "bs_roformer",
        "base": "https://huggingface.co/lumabeat/mvsep-mega53-guitar/resolve/ba42e7dec9f73631b3a89a3d0c365a5c21bd487c/",
        "files": {"mvsep_mega53_guitar.safetensors": "24fbd2bd29f134f94cb2396e5f43d6b8dcbcef621ae75783275b1c9c281c6fec",
                  "mvsep_mega53_guitar_config.json": "3691ae04991564ef44fa93b9793e95e07d2e21e1df373e129fcc3f871a843306"},
        "weights": "mvsep_mega53_guitar.safetensors",
    },
    "becruily": {
        "type": "mel_band_roformer",
        "base": "https://huggingface.co/becruily/mel-band-roformer-guitar/resolve/e9624f565871f933ac48b7b2af3fbadf763bf438/",
        "files": {"becruily_guitar.ckpt": "83472bbf125774af5282d2e0b86df89eaf2dd45e8a4ec8d68e820ebf3e42a83c",
                  "config_guitar_becruily.yaml": None},
        "weights": "becruily_guitar.ckpt",
        "config": "config_guitar_becruily.yaml",
    },
}

ap = argparse.ArgumentParser()
ap.add_argument("model", choices=list(MODELS))
ap.add_argument("tracks", nargs="*")
ap.add_argument("--device", default="cpu")
ap.add_argument("--keys", action="store_true")
args = ap.parse_args()
M = MODELS[args.model]
W = OUT / "weights" / args.model

OUT.mkdir(parents=True, exist_ok=True)
log = logging.getLogger("run")
log.setLevel(logging.INFO)
_h = logging.FileHandler(OUT / f"run_torch_{args.model}.log")
_h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(_h)
sys.excepthook = lambda t, v, tb: (log.error("".join(traceback.format_exception(t, v, tb))),
                                   print(f"ERROR {t.__name__}: {v} (traza en el log)"))


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def ensure_assets():
    if not MSST.exists():
        subprocess.run(["git", "clone", "-q", MSST_URL, str(MSST)], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(MSST), "checkout", "-q", MSST_COMMIT], check=True, capture_output=True)
    W.mkdir(parents=True, exist_ok=True)
    for name, want in M["files"].items():
        p = W / name
        if not p.exists():
            log.info("descargando %s", name)
            urllib.request.urlretrieve(M["base"] + name, p)
        got = sha256(p)
        log.info("%s sha256 %s", name, got)
        if want and got != want:
            raise RuntimeError(f"sha256 de {name} no coincide: {got}")


def mega53_yaml():
    """Config de MSST a partir del JSON de lumabeat (parámetros del modelo original de ZFTurbo)."""
    j = json.load(open(W / "mvsep_mega53_guitar_config.json"))
    model = {k: j[k] for k in ["dim", "depth", "stereo", "num_stems", "time_transformer_depth",
                               "freq_transformer_depth", "linear_transformer_depth", "dim_head", "heads",
                               "stft_n_fft", "stft_hop_length", "stft_win_length", "stft_normalized",
                               "mask_estimator_depth", "mlp_expansion_factor", "zero_dc"]}
    model.update(freqs_per_bands=tuple(j["freqs_per_bands"]), attn_dropout=0.0, ff_dropout=0.0, flash_attn=True)
    cfg = {"audio": {"chunk_size": j["chunk_size"], "num_channels": 2, "sample_rate": j["sample_rate"]},
           "model": model,
           "training": {"instruments": j["instruments"], "target_instrument": None, "use_amp": False},
           "inference": {"batch_size": 1, "num_overlap": j["num_overlap"]}}
    p = W / "msst_config.yaml"
    with open(p, "w") as f:
        yaml.dump(cfg, f)            # tuple -> !!python/tuple, lo lee el FullLoader de MSST
    return p


def load_state():
    import torch
    p = W / M["weights"]
    if p.suffix == ".safetensors":
        from safetensors.torch import load_file
        sd = load_file(str(p))
    else:
        sd = torch.load(p, map_location="cpu", weights_only=True)
        if isinstance(sd, dict) and "state_dict" in sd:
            sd = sd["state_dict"]
    return {k: v.float() for k, v in sd.items()}


def load_model():
    import torch  # noqa: F401
    ensure_assets()
    sys.path.insert(0, str(MSST))
    sys.dont_write_bytecode = True
    from utils.settings import get_model_from_config
    cfg_path = mega53_yaml() if args.model == "mega53" else W / M["config"]
    model, config = get_model_from_config(M["type"], str(cfg_path))
    sd = load_state()
    msd = model.state_dict()
    missing = [k for k in msd if k not in sd]
    unexpected = [k for k in sd if k not in msd]
    shape_bad = [(k, tuple(sd[k].shape), tuple(msd[k].shape)) for k in sd if k in msd and sd[k].shape != msd[k].shape]
    log.info("claves: modelo %d, pesos %d; faltan %d %s; sobran %d %s; forma distinta %d %s",
             len(msd), len(sd), len(missing), missing[:8], len(unexpected), unexpected[:8], len(shape_bad), shape_bad[:4])
    # Única ausencia admitida: frecuencias del rotary (lumabeat las omite; el modelo recalcula las de por defecto).
    if [k for k in missing if not k.endswith("rotary_embed.freqs")] or unexpected or shape_bad:
        raise RuntimeError(f"pesos incompatibles: faltan {missing[:5]} sobran {unexpected[:5]} forma {shape_bad[:3]}")
    model.load_state_dict(sd, strict=False)
    model.eval()
    n = sum(v.numel() for v in model.parameters())
    log.info("modelo %s cargado: %.1f M parámetros", args.model, n / 1e6)
    return model, config, len(missing), n


model, config, n_missing, n_params = load_model()
if args.keys:
    print(f"{args.model}: claves ok ({n_missing} rotary recalculadas), {n_params / 1e6:.1f} M parámetros")
    sys.exit(0)

import torch  # noqa: E402
from utils.model_utils import demix  # noqa: E402

dev = torch.device(args.device)
model = model.to(dev)
log.info("torch %s device %s chunk %s overlap %s instruments %s target %s", torch.__version__, dev,
         config.audio.chunk_size, config.inference.num_overlap, list(config.training.instruments),
         getattr(config.training, "target_instrument", None))
summary = []
for name in args.tracks:
    mix, sr = load_wav(TESTAUDIO / name / "mix.wav")
    assert sr == 44100 and mix.shape[0] == 2
    dur_min = mix.shape[-1] / sr / 60
    with PeakMem() as pm:
        t0 = time.perf_counter()
        res = demix(config, model, mix, dev, M["type"], pbar=False)
        if dev.type == "mps":
            torch.mps.synchronize()
        dt = time.perf_counter() - t0
    key = [k for k in res if k.lower() == "guitar"][0]
    d = OUT / "sep" / args.model / name
    save_wav(d / "guitar.wav", res[key], sr)
    t = {"device": str(dev), "dur_min": dur_min, "sec": dt, "sec_per_min": dt / dur_min, "peak_gb": pm.peak / 1e9,
         "out_keys": list(res)}
    json.dump(t, open(d / "timing.json", "w"), indent=1)
    log.info("%s: %s", name, t)
    summary.append(f"{name}: {dt / dur_min:.1f} s/min en {dev}, pico {pm.peak / 1e9:.2f} GB -> {d / 'guitar.wav'}")
print("\n".join(summary))
