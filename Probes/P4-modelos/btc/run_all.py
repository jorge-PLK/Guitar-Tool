"""Repite la prueba BTC entera con un comando:
    Tools/py/.venv/bin/python Probes/P4-modelos/btc/run_all.py [--prec fp16]
Convierte si falta el mlpackage y ejecuta, bajo el vigilante (10 GB) y de uno en uno, cada tema × entrada × vía
(torch → coreml_gpu → coreml_ane). Si una vía Core ML incumple un umbral en T1 se descarta para T2/T3."""
import argparse
import subprocess
import sys

import btc_common as C
import report

ap = argparse.ArgumentParser()
ap.add_argument("--prec", default="fp16", choices=["fp16", "fp32"])
a = ap.parse_args()
log = C.setup_log("run_all")
PY = sys.executable


def guarded(tag, args):
    g = C.OUT / "guard" / f"{tag}.log"
    g.parent.mkdir(parents=True, exist_ok=True)
    cmd = [PY, str(C.GUARD), "--limit-gb", "10", "--log", str(g), "--", PY, *args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    log.info("%s rc=%d\n%s\n%s", tag, r.returncode, r.stdout[-2000:], r.stderr[-4000:])
    return r.returncode


if not (C.OUT / "coreml" / f"BTC_large_voca_{a.prec}.mlpackage").exists():
    if guarded(f"convert_{a.prec}", [str(C.ROOT / "convert.py"), "--precision", a.prec]) != 0:
        sys.exit("falló la conversión: ver out/convert.log")

vias = {"torch": "torch", "coreml_gpu": f"coreml_gpu_{a.prec}", "coreml_ane": f"coreml_ane_{a.prec}"}
alive = list(vias)
for tema in C.TEMAS:
    for v in list(alive):
        name = vias[v]
        for inp in ("stems", "mix"):
            rc = guarded(f"{name}_{tema}_{inp}", [str(C.ROOT / "run.py"), "--tema", tema, "--input", inp,
                                                   "--via", v, "--prec", a.prec])
            if rc != 0:
                C.progress(f"{name} {tema} {inp} FALLÓ rc={rc} (ver out/run.log)")
        rows = [report.row(name, tema, i) for i in ("stems", "mix")]
        bad = [r for r in rows if r is None or not r["pass"]]
        if v != "torch" and tema == "T1" and bad:
            alive.remove(v)
            C.progress(f"vía {name} descartada en T1 (incumple umbral o falló)")
        elif v != "torch":
            C.progress(f"vía {name} {tema}: " + ", ".join(
                f"{r['input']} fid {r.get('fidelity_pct', 0):.2f} % {r['total_s']:.1f} s {r['peak_gb']} GB"
                for r in rows if r))

rows, svm = report.build(list(vias.values()))
ok = [v for v in alive if v != "torch"]
print(f"filas {len(rows)} · vías Core ML que pasan T1: {ok or 'ninguna'} · stems vs mezcla (torch) "
      + ", ".join(f"{t} {s:.1f} %" for t, s in svm.items() if s is not None))
print("tabla:", C.OUT / "results" / "btc_table.csv")
C.progress(f"prueba BTC terminada; vías Core ML vivas: {ok or 'ninguna'}")
