"""Tabla de resultados BTC: fidelidad frente a PyTorch (misma entrada), tiempos, pico de memoria (vigilante)
y coincidencia stems frente a mezcla (PyTorch). Escribe out/results/btc_table.{csv,json}."""
import csv
import json
import re

import numpy as np

import btc_common as C

TH_FID, TH_TIME, TH_MEM = 0.99, 15.0, 8.0


def peak_gb(tag: str):
    p = C.OUT / "guard" / f"{tag}.log"
    if not p.exists():
        return None
    m = re.findall(r"pico ([\d.]+) GB", p.read_text())
    return float(m[-1]) if m else None


def _pred(via, tema, inp):
    p = C.OUT / "pred" / via / f"{tema}_{inp}.npz"
    if not p.exists():
        return None
    z = np.load(p)
    n = z["pred"].size - int(z["num_pad"])
    return z["pred"].reshape(-1)[:n], z["logits"].reshape(-1, C.N_CHORDS)[:n]


def row(via, tema, inp):
    rj = C.OUT / "results" / "runs" / f"{via}_{tema}_{inp}.json"
    if not rj.exists():
        return None
    r = json.loads(rj.read_text())
    r["peak_gb"] = peak_gb(f"{via}_{tema}_{inp}")
    ref, me = _pred("torch", tema, inp), _pred(via, tema, inp)
    if via != "torch" and ref is not None and me is not None:
        r["fidelity_pct"] = 100 * float(np.mean(ref[0] == me[0]))
        d = np.abs(ref[1] - me[1])
        r["logit_diff_max"], r["logit_diff_mean"] = float(d.max()), float(d.mean())
    r["pass_fid"] = via == "torch" or r.get("fidelity_pct", 0) >= 100 * TH_FID
    r["pass_time"] = r["total_s"] <= TH_TIME
    r["pass_mem"] = r["peak_gb"] is not None and r["peak_gb"] <= TH_MEM
    r["pass"] = r["pass_fid"] and r["pass_time"] and r["pass_mem"]
    return r


def stems_vs_mix(tema, via="torch"):
    s, m = _pred(via, tema, "stems"), _pred(via, tema, "mix")
    if s is None or m is None:
        return None
    n = min(len(s[0]), len(m[0]))
    return 100 * float(np.mean(s[0][:n] == m[0][:n]))


def build(vias):
    rows = [r for v in vias for t in C.TEMAS for i in ("stems", "mix") if (r := row(v, t, i))]
    svm = {t: stems_vs_mix(t) for t in C.TEMAS}
    out = C.OUT / "results"
    out.mkdir(parents=True, exist_ok=True)
    (out / "btc_table.json").write_text(json.dumps({
        "thresholds": {"fidelity_pct": 100 * TH_FID, "total_s": TH_TIME, "peak_gb": TH_MEM},
        "rows": rows, "stems_vs_mix_pct_torch": svm,
        "weights": f"{C.BTC_URL}@{C.BTC_COMMIT} test/btc_model_large_voca.pt sha256 {C.CKPT_SHA256}",
    }, indent=1))
    cols = ["tema", "input", "via", "duration_s", "fidelity_pct", "logit_diff_max", "logit_diff_mean", "pre_s",
            "infer_s", "post_s", "total_s", "load_model_s", "peak_gb", "n_segments", "pass"]
    with open(out / "btc_table.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols + ["stems_vs_mix_pct_torch"], extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({**{k: (round(v, 4) if isinstance(v, float) else v) for k, v in r.items()},
                        "stems_vs_mix_pct_torch": round(svm[r["tema"]], 2) if r["via"] == "torch" and svm[r["tema"]] else ""})
    return rows, svm


if __name__ == "__main__":
    import sys
    rows, svm = build(sys.argv[1:] or ["torch", "coreml_gpu_fp16", "coreml_ane_fp16"])
    for r in rows:
        print(f"{r['tema']} {r['input']:5s} {r['via']:16s} fid {r.get('fidelity_pct', 100):6.2f} % "
              f"t {r['total_s']:5.2f} s mem {r['peak_gb']} GB {'OK' if r['pass'] else 'FALLA'}")
    print("stems vs mezcla (torch):", {k: (round(v, 1) if v else None) for k, v in svm.items()})
