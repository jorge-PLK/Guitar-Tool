"""Tablas y escucha a ciegas de HTDemucs 6s. Ligero (no hace falta el vigilante). Uso: report.py T1 T2 T3
- out/results/sdr_table.{csv,json}: tabla propia (mismo formato largo que la de BS-RoFormer)
- añade/actualiza las filas de HTDemucs (columna label = «HTDemucs 6s (PyTorch)») en
  bs_roformer_sw/out/results/sdr_table.{csv,json} sin tocar las demás filas
- out/blind/T<n>_guitar_{X,Y,ref}.wav (30 s) + out/blind/key.json (barajado con semilla fija)
- out/report.log y resumen en consola"""
import csv
import json
import logging
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
P4 = ROOT.parent
TESTAUDIO = P4.parent / "testaudio" / "out"
BSR = P4 / "bs_roformer_sw" / "out"
sys.path.insert(0, str(P4 / "common"))
from metrics import load_wav, save_wav  # noqa: E402

LABEL = "HTDemucs 6s (PyTorch)"
MODEL = "htdemucs_6s"
BSR_TAG = "coremlpub_cpu_gpu"
CLIPS = {"T1": 115, "T2": 155, "T3": 210}
DUR = 30
SEED = 20261115
STEMS = ["guitar", "piano", "bass", "drums", "vocals", "other"]

tracks = sys.argv[1:] or ["T1", "T2", "T3"]
log = logging.getLogger("report")
log.setLevel(logging.INFO)
fh = logging.FileHandler(OUT / "report.log")
fh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(fh)

# --- tabla propia ----------------------------------------------------------
rows = []
for t in tracks:
    r = json.load(open(OUT / "results" / f"{t}.json"))
    spm = min(x["sec_per_min"] for x in r["runs"])
    pk = max(x["peak_gb"] for x in r["runs"])
    for s, v in r["quality"].items():
        rows.append({"model": MODEL, "via": r["via"], "chunk": round(r["segment"] * 44100), "track": t, "stem": s,
                     **v, "sec_per_min": spm, "peak_gb": pk, "units": r["device"], "size_mb": r["size_mb"],
                     "label": LABEL})


def write_table(path_stem: Path, all_rows: list) -> None:
    keys = []
    for row in all_rows:
        keys += [k for k in row if k not in keys]
    with open(path_stem.with_suffix(".csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(all_rows)
    json.dump(all_rows, open(path_stem.with_suffix(".json"), "w"), indent=1)


write_table(OUT / "results" / "sdr_table", rows)

# --- tabla compartida: conserva lo existente y reemplaza solo filas de HTDemucs ----
shared = json.load(open(BSR / "results" / "sdr_table.json"))
n0 = len(shared)
shared = [x for x in shared if x.get("model") != MODEL]
kept = len(shared)
write_table(BSR / "results" / "sdr_table", shared + rows)
log.info("tabla compartida: %d filas antes, %d conservadas, %d de HTDemucs añadidas", n0, kept, len(rows))

# --- comparación con BS-RoFormer gridshift -----------------------------------
bsr = {(x["track"], x["stem"]): x for x in shared if x.get("via") == BSR_TAG}
mine = {(x["track"], x["stem"]): x for x in rows}
lines = ["tema stem  HTDemucs  gridshift  (SDR dB; res=energía residual dB sin referencia)"]
for t in tracks:
    for s in STEMS:
        h, b = mine.get((t, s), {}), bsr.get((t, s), {})
        fmt = lambda d: f"{d['sdr']:6.2f}" if "sdr" in d else (f"res{d['residual_db']:6.1f}" if "residual_db" in d else "  -  ")
        lines.append(f"{t} {s:6s} {fmt(h):>9s} {fmt(b):>9s}")
for t in tracks:
    r = json.load(open(OUT / "results" / f"{t}.json"))
    lines.append(f"{t}: " + ", ".join(f"{x['sec_per_min']:.1f} s/min pico {x['peak_gb']:.2f} GB" for x in r["runs"]))
for ln in lines:
    log.info(ln)
(OUT / "results" / "vs_gridshift.txt").write_text("\n".join(lines) + "\n")

# --- escucha a ciegas --------------------------------------------------------
blind = OUT / "blind"
rng = random.Random(SEED)
key = {"seed": SEED, "dur_s": DUR, "candidates": {"htdemucs": f"{MODEL} PyTorch MPS",
                                                   "bsroformer": f"BS-RoFormer SW Core ML gridshift ({BSR_TAG})"}}
for t in tracks:
    a = CLIPS[t]
    srcs = {"htdemucs": OUT / "stems" / t / "guitar.wav",
            "bsroformer": BSR / "conv" / BSR_TAG / t / "guitar.wav",
            "ref": TESTAUDIO / t / "stems" / "guitar.wav"}
    clips = {}
    for k, p in srcs.items():
        x, sr = load_wav(p)
        clips[k] = x[:, a * sr:(a + DUR) * sr]
        log.info("%s %s: %s, %.1f s, tramo %d-%d s -> %s muestras", t, k, p, x.shape[1] / sr, a, a + DUR,
                 clips[k].shape[1])
        assert clips[k].shape[1] == DUR * sr, (t, k, clips[k].shape)
    order = ["htdemucs", "bsroformer"]
    rng.shuffle(order)
    for letter, k in zip("XY", order):
        save_wav(blind / f"{t}_guitar_{letter}.wav", clips[k], sr)
    save_wav(blind / f"{t}_guitar_ref.wav", clips["ref"], sr)
    key[t] = {"start_s": a, "X": order[0], "Y": order[1]}
json.dump(key, open(blind / "key.json", "w"), indent=1)
print("\n".join(lines))
print(f"blind: {blind} ({len(tracks) * 3} wav + key.json); tabla compartida {kept}+{len(rows)} filas")
