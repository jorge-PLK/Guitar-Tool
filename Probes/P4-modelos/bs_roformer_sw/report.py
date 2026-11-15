"""Resumen + material de escucha. Uso: report.py --via <tag elegido> T1 T2 T3 ...
- Tabla SDR/SI-SDR por stem (PyTorch y convertido frente a stems reales) desde out/results/*.json
- out/listen/<T>_guitar_{real,torch,<tag>}.wav: 30 s, mismo tramo (ventana de más energía de la guitarra real)
- copia los stems de la vía elegida de T1 a out/stems/T1/"""
import argparse
import json
import shutil

import sw_common as C
from metrics import clip, loudest_window

ap = argparse.ArgumentParser()
ap.add_argument("tracks", nargs="+")
ap.add_argument("--via", required=True, help="tag de compare.py, p. ej. onnx_all")
args = ap.parse_args()

res = {p.stem: json.load(open(p)) for p in sorted((C.OUT / "results").glob("*.json"))}
lines = []
if args.via == "table":  # tabla reutilizable de todas las vías: out/results/sdr_table.{csv,json}
    import csv
    rows = []
    qt = json.load(open(C.OUT / "results" / "quality_torch.json"))
    for name in args.tracks:
        tim = json.load(open(C.OUT / "ref_torch" / name / "timing.json"))
        for s, v in qt.get(name, {}).items():
            rows.append({"model": "bs_roformer_sw", "via": "pytorch_oficial", "chunk": C.CHUNK, "track": name,
                         "stem": s, **v, "sec_per_min": tim["runs"][-1]["sec_per_min"],
                         "peak_gb": tim["runs"][-1]["peak_gb"], "units": tim["device"]})
    for tag, r in res.items():
        if "tracks" not in r:
            continue
        for name in args.tracks:
            tr = r["tracks"].get(name)
            if not tr or "quality_conv" not in tr:
                continue
            spm = min(x["sec_per_min"] for x in tr["runs"])
            pk = max(x["peak_gb"] for x in tr["runs"])
            for s, v in tr["quality_conv"].items():
                fid = tr.get("fidelity", {}).get(s, {})
                rows.append({"model": "bs_roformer_sw", "via": tag, "chunk": r.get("chunk"), "track": name,
                             "stem": s, **v, "sdr_vs_torch": fid.get("sdr_vs_orig"),
                             "max_abs_vs_torch": fid.get("max_abs"), "mean_abs_vs_torch": fid.get("mean_abs"),
                             "sec_per_min": spm, "peak_gb": pk, "size_mb": r.get("size_mb"),
                             "units": tag.rsplit("_", 1)[-1], "status": r.get("status", "")})
    keys = sorted({k for row in rows for k in row}, key=lambda k: list(rows[0]).index(k) if k in rows[0] else 99)
    with open(C.OUT / "results" / "sdr_table.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)
    json.dump(rows, open(C.OUT / "results" / "sdr_table.json", "w"), indent=1)
    print(f"{len(rows)} filas en out/results/sdr_table.csv")
    raise SystemExit
if args.via == "torch":  # solo referencia PyTorch (sin vía convertida)
    from metrics import quality_table
    q = {}
    for name in args.tracks:
        d = C.OUT / "ref_torch" / name
        q[name] = quality_table(d, C.TESTAUDIO / name / "stems", C.TESTAUDIO / name / "mix.wav", C.STEMS)
        t = json.load(open(d / "timing.json"))
        lines.append(f"{name} torch {t['device']}: {t['runs'][0]['sec_per_min']:.1f} s/min, "
                     f"pico {t['runs'][0]['peak_gb']:.2f} GB")
        lines.append("  " + " ".join(f"{s}={v['sdr']:.2f}/{v['si_sdr']:.2f}" if "sdr" in v
                                     else f"{s}=res{v['residual_db']:.1f}dB" for s, v in q[name].items()))
        real = C.TESTAUDIO / name / "stems" / "guitar.wav"
        start = loudest_window(real)
        clip(real, C.OUT / "listen" / f"{name}_guitar_real.wav", start)
        clip(d / "guitar.wav", C.OUT / "listen" / f"{name}_guitar_torch.wav", start)
        lines.append(f"  escucha {name}: tramo {start:.0f}-{start + 30:.0f} s")
    (C.OUT / "results").mkdir(exist_ok=True)
    json.dump(q, open(C.OUT / "results" / "quality_torch.json", "w"), indent=1)
    (C.OUT / "report_torch.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    raise SystemExit
for name in args.tracks:
    for tag, r in res.items():
        tr = r.get("tracks", {}).get(name)
        if not tr:
            continue
        spm = sum(x["sec_per_min"] for x in tr["runs"]) / len(tr["runs"])
        pk = max(x["peak_gb"] for x in tr["runs"])
        lines.append(f"{name} {tag}: {spm:.1f} s/min, pico {pk:.2f} GB, {r['size_mb']:.0f} MB")
        if "fidelity" in tr:
            lines.append("  fidelidad SDR vs torch: " + " ".join(
                f"{s}={v['sdr_vs_orig']:.1f}" for s, v in tr["fidelity"].items()))
        for key in ("quality_torch", "quality_conv"):
            if key in tr:
                lines.append(f"  {key}: " + " ".join(
                    f"{s}={v['sdr']:.2f}/{v['si_sdr']:.2f}" if "sdr" in v else f"{s}=res{v['residual_db']:.1f}dB"
                    for s, v in tr[key].items()))
    real = C.TESTAUDIO / name / "stems" / "guitar.wav"
    start = loudest_window(real)
    L = C.OUT / "listen"
    clip(real, L / f"{name}_guitar_real.wav", start)
    clip(C.OUT / "ref_torch" / name / "guitar.wav", L / f"{name}_guitar_torch.wav", start)
    clip(C.OUT / "conv" / args.via / name / "guitar.wav", L / f"{name}_guitar_{args.via}.wav", start)
    lines.append(f"  escucha {name}: tramo {start:.0f}-{start + 30:.0f} s")

src = C.OUT / "conv" / args.via / "T1"
dst = C.OUT / "stems" / "T1"
dst.mkdir(parents=True, exist_ok=True)
for s in C.STEMS:
    shutil.copy2(src / f"{s}.wav", dst / f"{s}.wav")
(C.OUT / "report.txt").write_text("\n".join(lines) + "\n")
print(f"{len(lines)} líneas en out/report.txt; stems T1 en {dst}")
