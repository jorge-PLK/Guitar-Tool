"""Prueba de fallo rápido: Mel-Band RoFormer "Lead_Rhythm_Guitar" (origen desconocido, HF RandomFilteredStuff/RVC_V2_Stuff).

SEGURIDAD: pesos anónimos -> solo torch.load(weights_only=True); YAML con SafeLoader (solo se añade el
constructor de !!python/tuple, que construye una tupla y nada más). Solo se usa la clase MelBandRoformer y
demix() de MSST (commit fijado, clon ya existente en guitar_models/out/msst), nunca su loader de checkpoints.

Uso (bajo common/guard.py, con python -I):
  run_torch.py --keys                  # paso 1: descarga, sha256 y casado de claves; para si no casa
  run_torch.py [--device mps|cpu]      # pasos 2-5: recortes de Platero + tramo de T3
Salida: Temp/bench/platero/lead-rhythm/<recorte>/{input,lead,rhythm}.wav, summary.json; log en out/run_torch.log."""
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
import yaml

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "common"))
from metrics import load_wav, save_wav, sdr  # noqa: E402

OUT = HERE / "out"
W = OUT / "weights"                       # directorio de descarga propio (out/ no se versiona)
WT = Path("/Volumes/SSD Mac/Personales/Guitar Tool/.claude/worktrees/fase-4")
MSST = HERE.parent / "guitar_models/out/msst"   # commit 1f700c38
BASE = "https://huggingface.co/RandomFilteredStuff/RVC_V2_Stuff/resolve/c3ac4e45eb290b3ed32ec9c387295021a52c5916/"
CKPT = "model_mel_band_roformer_ep_72_sdr_3.2232.ckpt"
CKPT_SHA = "b3c47bca33609ca1ba0bb2d2076410bfd1eb941b051b72afc1f3e24d12b17eef"
CFG = "config_mel_band_roformer_Lead_Rhythm_Guitar.yaml"
CFG_KARAOKE = "config_mel_band_roformer_karaoke.yaml"   # del mismo commit: para ver si el ckpt casa también con ella
PLATERO = Path("/Users/jorgefernandezhurtado/Music/ToneForge/El roce de tu cuerpo - Platero Y Tu/stems/guitar.wav")
BENCH = WT / "Temp/bench/platero"
DST = BENCH / "lead-rhythm"
CUTS = {"157-187s": 157.0, "60-90s": 60.0}
T3 = Path("/Volumes/SSD Mac/Personales/Guitar Tool/Probes/testaudio/out/T3")
T3_START = 144.5                           # manifest: clip gtr_lead = T3 ElecGtr3 desde 144,5 s
T3_LEAD = ["14_ElecGtr3.wav"]

ap = argparse.ArgumentParser()
ap.add_argument("--keys", action="store_true")
ap.add_argument("--device", default="mps")
args = ap.parse_args()

OUT.mkdir(parents=True, exist_ok=True)
log = logging.getLogger("run")
log.setLevel(logging.INFO)
_h = logging.FileHandler(OUT / "run_torch.log")
_h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(_h)
sys.excepthook = lambda t, v, tb: (log.error("".join(traceback.format_exception(t, v, tb))),
                                   print(f"ERROR {t.__name__}: {v} (traza en el log)"))


class TupleSafeLoader(yaml.SafeLoader):
    pass


TupleSafeLoader.add_constructor("tag:yaml.org,2002:python/tuple",
                                lambda ld, node: tuple(ld.construct_sequence(node)))


def read_yaml(p):
    try:
        return yaml.safe_load(open(p)), "safe_load"
    except yaml.constructor.ConstructorError as e:
        log.info("safe_load no admite una etiqueta (%s); SafeLoader + solo tupla", str(e).splitlines()[0])
        return yaml.load(open(p), Loader=TupleSafeLoader), "SafeLoader+tuple"


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def fetch():
    W.mkdir(parents=True, exist_ok=True)
    for name in (CFG, CFG_KARAOKE, CKPT):
        p = W / name
        if not p.exists():
            log.info("descargando %s", name)
            urllib.request.urlretrieve(BASE + name, p)
        got = sha256(p)
        log.info("%s: %d B sha256 %s", name, p.stat().st_size, got)
        if name == CKPT and got != CKPT_SHA:
            raise RuntimeError(f"sha256 del checkpoint no coincide: {got}")


def build(cfg):
    sys.path.insert(0, str(MSST))
    sys.dont_write_bytecode = True
    from models.bs_roformer.mel_band_roformer import MelBandRoformer
    return MelBandRoformer(**dict(cfg["model"]))


def compare(model, sd, tag):
    msd = model.state_dict()
    missing = [k for k in msd if k not in sd]
    unexpected = [k for k in sd if k not in msd]
    shape_bad = [(k, tuple(sd[k].shape), tuple(msd[k].shape)) for k in sd if k in msd and sd[k].shape != msd[k].shape]
    log.info("%s: modelo %d claves, pesos %d; faltan %d %s; sobran %d %s; forma distinta %d %s", tag, len(msd), len(sd),
             len(missing), missing[:6], len(unexpected), unexpected[:6], len(shape_bad), shape_bad[:4])
    return missing, unexpected, shape_bad


def load():
    import torch
    fetch()
    try:
        obj = torch.load(W / CKPT, map_location="cpu", weights_only=True)
    except Exception as e:  # noqa: BLE001
        log.error("weights_only=True FALLA: %r -> se para aquí, no se carga de otra forma", e)
        print(f"PARADO: torch.load(weights_only=True) falla: {type(e).__name__}: {str(e)[:200]}")
        sys.exit(2)
    top = list(obj.keys())[:8] if isinstance(obj, dict) else type(obj).__name__
    log.info("checkpoint: tipo %s, primeras claves %s", type(obj).__name__, top)
    sd = obj.get("state_dict", obj.get("model", obj)) if isinstance(obj, dict) else obj
    sd = {k.removeprefix("module.").removeprefix("_orig_mod."): v for k, v in sd.items()}
    dt = sorted({str(v.dtype) for v in sd.values()})
    log.info("pesos: %d tensores, %.1f M valores, dtypes %s", len(sd), sum(v.numel() for v in sd.values()) / 1e6, dt)
    cfg, how = read_yaml(W / CFG)
    log.info("config (%s): audio %s training %s model %s inference %s", how, cfg.get("audio"),
             {k: cfg["training"].get(k) for k in ("instruments", "target_instrument")}, cfg["model"], cfg.get("inference"))
    model = build(cfg)
    miss, unexp, bad = compare(model, sd, "Lead_Rhythm")
    try:
        kcfg, _ = read_yaml(W / CFG_KARAOKE)
        log.info("config karaoke: model %s training %s", kcfg["model"],
                 {k: kcfg["training"].get(k) for k in ("instruments", "target_instrument")})
        km, ku, kb = compare(build(kcfg), sd, "karaoke")
        kar = f"karaoke: faltan {len(km)} sobran {len(ku)} forma {len(kb)}"
    except Exception as e:  # noqa: BLE001
        kar = f"karaoke: no comparable ({type(e).__name__})"
        log.info(kar)
    ok = not miss and not unexp and not bad
    msg = (f"weights_only OK ({how}); Lead_Rhythm: faltan {len(miss)} sobran {len(unexp)} forma {len(bad)}"
           f" -> {'CASA' if ok else 'NO CASA'}; {kar}")
    log.info(msg)
    if not ok:
        print("DESCARTADO: " + msg)
        sys.exit(3)
    model.load_state_dict({k: v.float() for k, v in sd.items()}, strict=True)
    model.eval()
    return model, cfg, msg


def db(x, ref):
    return 10 * np.log10((np.sum(x.astype(np.float64) ** 2) + 1e-20) / (np.sum(ref.astype(np.float64) ** 2) + 1e-20))


def cut(x, sr, start, dur=30.0):
    a = int(round(start * sr))
    return np.ascontiguousarray(x[:, a:a + int(round(dur * sr))])


model, cfg, keymsg = load()
if args.keys:
    print(keymsg)
    sys.exit(0)

import torch  # noqa: E402
from ml_collections import ConfigDict  # noqa: E402
from utils.model_utils import demix  # noqa: E402

dev = torch.device(args.device)
model = model.to(dev)
config = ConfigDict(cfg)
tgt = config.training.get("target_instrument")
log.info("torch %s device %s chunk %s overlap %s target %s", torch.__version__, dev, config.audio.chunk_size,
         config.inference.num_overlap, tgt)


def separate(x, sr):
    t0 = time.perf_counter()
    res = demix(config, model, x, dev, "mel_band_roformer", pbar=False)
    if dev.type == "mps":
        torch.mps.synchronize()
    dt = time.perf_counter() - t0
    keys = list(res)
    lead = res["Lead"] if "Lead" in res else res[keys[0]]
    rhythm = res["Rhythm"] if "Rhythm" in res else x - lead
    return lead.astype(np.float32), rhythm.astype(np.float32), dt, keys


# calentamiento (MPS compila kernels la primera vez)
g, sr = load_wav(PLATERO)
assert sr == 44100 and g.shape[0] == 2, (sr, g.shape)
separate(cut(g, sr, 0.0, 6.0), sr)

summary = {"keys": keymsg, "device": str(dev), "cuts": {}}
lines = []
for name, start in CUTS.items():
    x = cut(g, sr, start)
    lead, rhythm, dt, keys = separate(x, sr)
    d = DST / name
    save_wav(d / "input.wav", x, sr)
    save_wav(d / "lead.wav", lead, sr)
    save_wav(d / "rhythm.wav", rhythm, sr)
    r = {"out_keys": keys, "sec": round(dt, 2), "lead_db": round(db(lead, x), 2), "rhythm_db": round(db(rhythm, x), 2),
         "lead_plus_rhythm_err_db": round(db(lead + rhythm - x, x), 1)}
    ref = BENCH / "sweep/gate-w0.30-s0.15" / name / "guitar_C.wav"
    if ref.exists():
        c, _ = load_wav(ref)
        n = min(c.shape[-1], x.shape[-1])
        r["guitar_C_db"] = round(db(c[:, :n], x[:, :n]), 2)
        r["sdr_lead_vs_guitar_C"] = round(sdr(lead[:, :n], c[:, :n]), 2)
    summary["cuts"][name] = r
    log.info("%s: %s", name, r)
    lines.append(f"{name}: lead {r['lead_db']} dB, rhythm {r['rhythm_db']} dB, guitar_C {r.get('guitar_C_db')} dB,"
                 f" {dt:.1f} s/30 s ({keys})")

# Paso 5: T3, tramo gtr_lead del manifest (ElecGtr3 suelta = solista; ElecGtr1/1DT/2 = rítmicas)
gs, _ = load_wav(T3 / "stems/guitar.wav")
x = cut(gs, sr, T3_START)
lead_ref = sum(cut(load_wav(T3 / "guitar_parts" / f)[0], sr, T3_START) for f in T3_LEAD)
rhy_ref = x - lead_ref
lead, rhythm, dt, keys = separate(x, sr)
d = DST / "T3-144.5s"
for nm, a in (("input", x), ("lead", lead), ("rhythm", rhythm), ("ref_lead", lead_ref), ("ref_rhythm", rhy_ref)):
    save_wav(d / f"{nm}.wav", a, sr)
r = {"sec": round(dt, 2), "ref_lead_db": round(db(lead_ref, x), 2), "lead_db": round(db(lead, x), 2),
     "sdr_lead": round(sdr(lead, lead_ref), 2), "sdr_rhythm": round(sdr(rhythm, rhy_ref), 2),
     "sdr_lead_if_input": round(sdr(x, lead_ref), 2), "sdr_rhythm_if_input": round(sdr(x, rhy_ref), 2)}
summary["T3"] = r
log.info("T3: %s", r)
lines.append(f"T3 144.5s: SDR lead {r['sdr_lead']} (entrada tal cual {r['sdr_lead_if_input']}), rhythm {r['sdr_rhythm']}"
             f" (entrada {r['sdr_rhythm_if_input']}); lead real {r['ref_lead_db']} dB vs estimado {r['lead_db']} dB")
json.dump(summary, open(DST / "summary.json", "w"), indent=1)
print("\n".join(lines))
