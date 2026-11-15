"""Repite la prueba Beat This! entera con un comando:
    Tools/py/.venv/bin/python Probes/P4-modelos/beat_this/run_all.py [--all]
Torch (referencia) en T1-T3 y después las vías candidatas en orden (coreml_comm → coreml_fp16 → onnx_coreml),
cada tema en su propio proceso bajo el vigilante (10 GB). Fallo rápido: una vía que incumple un umbral en T1 se
descarta y se pasa a la siguiente; la primera que pasa T1 se prueba en T2/T3 y se elige. --all prueba todas."""
import argparse
import subprocess
import sys

import bt_common as C
import report

ap = argparse.ArgumentParser()
ap.add_argument("--all", action="store_true", help="no parar en la primera vía que pasa")
ap.add_argument("--vias", nargs="*", default=["coreml_comm", "coreml_fp16", "onnx_coreml"])
a = ap.parse_args()
log = C.setup_log("run_all")
PY = sys.executable


def guarded(tag, args):
    g = C.OUT / "guard" / f"{tag}.log"
    g.parent.mkdir(parents=True, exist_ok=True)
    g.unlink(missing_ok=True)
    cmd = [PY, str(C.GUARD), "--limit-gb", "10", "--log", str(g), "--", PY, *args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    log.info("%s rc=%d\n%s\n%s", tag, r.returncode, r.stdout[-2000:], r.stderr[-4000:])
    return r.returncode


def run(via, tema):
    rc = guarded(f"{via}_{tema}", [str(C.ROOT / "run.py"), "--tema", tema, "--via", via])
    r = report.row(via, tema) if rc == 0 else None
    if r is None:
        C.progress("ejecución", tema, via, f"FALLÓ rc={rc} (ver out/run.log)")
    else:
        C.progress("ejecución", tema, via, f"{r['bpm']} BPM ({r['tempo']}) fid {r['fid_torch_in_via']}/"
                   f"{r['fid_via_in_torch']} % {r['total_s']} s {r['peak_gb']} GB {'PASA' if r['pass'] else 'NO PASA'}")
    return r


def prepare(via):
    if via == "coreml_fp16" and not (C.OUT / "coreml" / "BeatThis_final0_fp16.mlpackage").exists():
        return guarded("convert_fp16", [str(C.ROOT / "convert.py")]) == 0
    if via.startswith("onnx") and not (C.ONNX_DIR / "beat_this.onnx").exists():
        C.download(f"https://huggingface.co/{C.ONNX_REPO}/resolve/{C.ONNX_SHA}/beat_this.onnx",
                   C.ONNX_DIR / "beat_this.onnx", log)
    return True


C.ensure_repo(log)
for t in C.TEMAS:
    run("torch", t)
done, chosen = ["torch"], None
for via in a.vias:
    if not prepare(via):
        C.progress("preparación", "-", via, "FALLÓ (ver out/convert.log)")
        continue
    done.append(via)
    r = run(via, "T1")
    if not (r and r["pass"]):
        C.progress("descarte", "T1", via, "incumple un umbral en T1")
        continue
    rows = [r] + [run(via, t) for t in ("T2", "T3")]
    if all(x and x["pass"] for x in rows) and chosen is None:
        chosen = via
        if not a.all:
            break

rows = report.build(done)
subprocess.run([PY, str(C.ROOT / "clicks.py"), "torch", *([chosen] if chosen else [])], capture_output=True)
print(f"vía elegida: {chosen or 'ninguna'} · tabla: {C.OUT / 'results' / 'beat_table.csv'}")
for r in rows:
    print(f"{r['via']:12s} {r['tema']} {r['bpm']:6.1f} BPM {r['tempo']:14s} fid {r['fid_torch_in_via']:6.2f}/"
          f"{r['fid_via_in_torch']:6.2f} {r['total_s']:5.2f} s {r['peak_gb']} GB {r['bar_hist']}")
C.progress("fin", "T1-T3", chosen or "ninguna", "prueba beat_this terminada")
