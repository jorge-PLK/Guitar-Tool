"""Tabla de resultados: out/results/beat_table.{csv,json}. Fidelidad frente a torch a ±20 ms en los dos sentidos,
tempo frente al Readme, pico de memoria del vigilante, histograma de pulsos por compás (informativo)."""
import csv
import json
import re

import numpy as np

import bt_common as C

FID_MIN, TIME_MAX, MEM_MAX = 99.0, 10.0, 8.0


def peak_gb(via: str, tema: str):
    g = C.OUT / "guard" / f"{via}_{tema}.log"
    if not g.exists():
        return None
    m = re.findall(r"pico ([\d.]+) GB", g.read_text())
    return float(m[-1]) if m else None


def row(via: str, tema: str):
    p = C.OUT / "runs" / f"{via}_{tema}.json"
    if not p.exists():
        return None
    r = json.loads(p.read_text())
    bd = C.OUT / "beats"
    beats = C.load_times(bd / via / f"{tema}.beats.txt")
    downs = C.load_times(bd / via / f"{tema}.downbeats.txt")
    tb = C.load_times(bd / "torch" / f"{tema}.beats.txt")
    td = C.load_times(bd / "torch" / f"{tema}.downbeats.txt")
    r["ref_bpm"] = C.REF_BPM[tema]
    r["tempo"] = C.tempo_verdict(r["bpm"], C.REF_BPM[tema])
    r["bpm_fine"] = round(C.tempo_fine(beats), 2)
    r["tempo_fine"] = C.tempo_verdict(r["bpm_fine"], C.REF_BPM[tema])
    r["fid_torch_in_via"] = round(C.match_pct(tb, beats), 2)
    r["fid_via_in_torch"] = round(C.match_pct(beats, tb), 2)
    r["fid_down_torch_in_via"] = round(C.match_pct(td, downs), 2)
    r["fid_down_via_in_torch"] = round(C.match_pct(downs, td), 2)
    r["peak_gb"] = peak_gb(via, tema)
    h = C.bar_histogram(beats, downs)
    r["bar_hist"] = h
    r["first_downbeats"] = [round(float(x), 2) for x in downs[:6]]
    r["pct_4_4"] = round(100 * h.get(4, 0) / max(1, sum(h.values())), 1)
    torch_bpm = json.loads((C.OUT / "runs" / f"torch_{tema}.json").read_text())["bpm"]
    # una vía no se descarta por un fallo de tempo que ya tiene la referencia (es del modelo, no de la vía)
    tempo_ok = r["tempo"] == "ok" or (via != "torch" and abs(r["bpm"] - torch_bpm) < 0.5)
    r["pass"] = bool(tempo_ok and min(r["fid_torch_in_via"], r["fid_via_in_torch"]) >= FID_MIN
                     and r["total_s"] <= TIME_MAX and (r["peak_gb"] or 99) <= MEM_MAX)
    return r


COLS = ["via", "tema", "unit", "prec", "ref_bpm", "bpm", "tempo", "bpm_fine", "tempo_fine", "n_beats", "n_downbeats", "fid_torch_in_via",
        "fid_via_in_torch", "fid_down_torch_in_via", "fid_down_via_in_torch", "logit_maxdiff", "logit_meandiff",
        "pre_s", "inf_s", "post_s", "total_s", "load_model_s", "load_audio_s", "peak_gb", "chunks", "pct_4_4",
        "bar_hist", "first_downbeats", "pass"]


def build(vias):
    rows = [r for v in vias for t in C.TEMAS if (r := row(v, t))]
    d = C.OUT / "results"
    d.mkdir(parents=True, exist_ok=True)
    with open(d / "beat_table.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLS, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: (json.dumps(r[k]) if isinstance(r.get(k), (dict, list)) else r.get(k)) for k in COLS})
    C.save_json(d / "beat_table.json", rows)
    return rows


if __name__ == "__main__":
    import sys
    for r in build(sys.argv[1:] or ["torch"]):
        print(r["via"], r["tema"], r["bpm"], r["tempo"], r["bpm_fine"], r["fid_torch_in_via"], r["fid_via_in_torch"],
              r["total_s"], r["peak_gb"], r["bar_hist"], r["pass"])
