"""Tabla de resultados ADTOF: P/R/F por pieza y tema (±50 ms, mir_eval), tiempos, pico de memoria y
fidelidad de las vías Core ML frente a PyTorch (% de golpes coincidentes a ±10 ms por pieza).

Uso: Tools/py/.venv/bin/python Probes/P4-modelos/adtof/evaluate.py [--vias torch coreml_fp16 ...] [--tag base]
Lee out/ref/, out/hits/<vía>/, out/runs/, out/logs/guard_<vía>_T*.log. Escribe out/results/drum_table.{csv,json}.
"""
import argparse
import csv
import json
import re

import numpy as np

import ad_common as C

ap = argparse.ArgumentParser()
ap.add_argument("--vias", nargs="*", default=["torch", "coreml_fp16", "coreml_fp32"])
ap.add_argument("--hits-root", default="hits", help="subcarpeta de out/ con los golpes (p. ej. hits_drumsep)")
ap.add_argument("--name", default="drum_table")
a = ap.parse_args()
log = C.setup_log("evaluate")


def peak_gb(via, song):
    g = C.OUT / "logs" / f"guard_{via}_{song}.log"
    if not g.exists():
        return None
    m = re.findall(r"pico ([\d.]+) GB", g.read_text())
    return float(m[-1]) if m else None


rows = []
for via in a.vias:
    for song in C.SONGS:
        hd = C.OUT / a.hits_root / via / song
        if not hd.exists():
            continue
        est = C.load_hits(hd)
        ref = C.load_hits(C.OUT / "ref" / song, C.PIECES)
        ref_loose = C.load_hits(C.OUT / "ref" / song, [f"{p}_loose" for p in C.PIECES])
        run = C.OUT / "runs" / f"{via}_{song}.json"
        run = json.loads(run.read_text()) if run.exists() else {}
        row = {"via": via, "song": song, "total_s": run.get("total_s"),
               "s_per_audio_min": run.get("total_s_per_audio_min"), "peak_gb": peak_gb(via, song)}
        for p in C.PIECES:
            if p not in ref:
                row.update({f"{p}_P": None, f"{p}_R": None, f"{p}_F": None, f"{p}_n_ref": None})
                continue
            P, R, F = C.prf(ref[p], est.get(p, np.zeros(0)))
            off = C.matched_offsets(ref[p], est.get(p, np.zeros(0)))
            row.update({f"{p}_P": round(P, 3), f"{p}_R": round(R, 3), f"{p}_F": round(F, 3),
                        f"{p}_n_ref": int(len(ref[p])), f"{p}_n_est": int(len(est.get(p, []))),
                        f"{p}_offset_ms_median": round(float(np.median(off)) * 1000, 1) if len(off) else None,
                        f"{p}_F_loose": round(C.prf(ref_loose[f"{p}_loose"], est.get(p, np.zeros(0)))[2], 3)})
        if via != "torch":
            tr = C.load_hits(C.OUT / a.hits_root / "torch" / song)
            for p in C.NAMES:
                t_ref, t_est = tr.get(p, np.zeros(0)), est.get(p, np.zeros(0))
                n = max(len(t_ref), len(t_est))
                match = len(C.matched_offsets(t_ref, t_est, C.FID_TOL))
                row[f"fid_{p}_pct"] = round(100.0 * match / n, 2) if n else 100.0
        if song == "T1":
            row["T1_verdict"] = "FALLA" if min(row["kick_F"], row["snare_F"]) < 0.7 else "PASA"
        if row["peak_gb"] is not None and row["peak_gb"] > 8:
            row["mem_verdict"] = "FALLA"
        rows.append(row)
        log.info("%s", row)

out = C.OUT / "results"
out.mkdir(parents=True, exist_ok=True)
(out / f"{a.name}.json").write_text(json.dumps(rows, indent=1))
keys = sorted({k for r in rows for k in r}, key=lambda k: (k not in ("via", "song"), k))
with open(out / f"{a.name}.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=keys)
    w.writeheader()
    w.writerows(rows)
for r in rows:
    s = " ".join(f"{p[:2]} {r[f'{p}_P']}/{r[f'{p}_R']}/{r[f'{p}_F']}" for p in C.PIECES if r.get(f"{p}_F") is not None)
    fid = " fid " + "/".join(str(r[f"fid_{p}_pct"]) for p in C.PIECES) if f"fid_kick_pct" in r else ""
    print(f"{r['via']} {r['song']}: {s} | {r['total_s']} s {r['peak_gb']} GB{fid} {r.get('T1_verdict', '')}")
